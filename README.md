# System Monitor — Kubernetes Deployment

A bash-based health monitoring app that checks CPU, RAM, and disk usage against a threshold, logs results, and serves the log over HTTP. Originally built as a Docker container, now deployed as a production-style Kubernetes workload on a local `kind` cluster.

## Architecture

The app runs as a single container per Pod:
- `main.sh` performs the health checks (CPU/RAM/disk usage, log file error scan) every 30 seconds via a loop in `start.sh`.
- A `python3 -m http.server` process runs alongside it in the same container, serving the `/app` directory (including the log file) over port 8080.
- The Deployment manages **3 replicas** of this Pod, all behind a single NodePort Service (`system-monitor-service`) that load-balances traffic across them.
## Storage Design

Health check output (`health.log`) needs to survive Pod restarts, so it's stored on a **PersistentVolume (PV)** rather than the container's writable layer.

- `manifests/pv.yaml` — defines a `hostPath`-backed PV (100Mi) pointing at `/mnt/data/system-monitor` on the `kind` node. `hostPath` is used because this is a single-node local cluster; a real multi-node or cloud cluster would use a cloud-native storage class (e.g. EBS, Persistent Disk) instead.
- `manifests/pvc.yaml` — a PersistentVolumeClaim that explicitly binds to `system-monitor-pv` by name (`volumeName`), rather than relying on `kind`'s default dynamic provisioner. This keeps the binding predictable and demonstrates manual PV/PVC wiring.
- The PVC is mounted at `/app/data` inside the container. `LOG_FILE` is set to `/app/data/health.log` so all replicas write to the same persistent location.

## Configuration Management

Configuration is split by sensitivity, following Kubernetes best practice:

- **ConfigMap** (`manifests/configmap.yaml`) holds non-sensitive settings:
  - `LOG_FILE`: path to the health log
  - `THRESHOLD`: CPU/RAM/disk warning threshold (%)
- **Secret** (`manifests/secret.yaml`) holds sensitive values:
  - `ALERT_WEBHOOK_TOKEN`: placeholder token for a future alerting integration

Both are injected into the container as environment variables via `envFrom` in the Deployment, and `main.sh` reads them with safe defaults (e.g. `THRESHOLD="${THRESHOLD:-85}"`) so it still works if the env vars are missing.

**Note:** the Secret in this repo uses a placeholder value for demonstration. In a real deployment, Secrets should never be committed to git — apply them directly with `kubectl` or manage them with a tool like Sealed Secrets or an external secrets manager.

## Scaling Strategy

The Deployment runs `replicas: 3` by default, with per-container resource requests/limits:
- Requests: 50m CPU / 64Mi memory (guaranteed minimum)
- Limits: 200m CPU / 128Mi memory (hard ceiling)

This keeps each replica lightweight while preventing any single Pod from starving the node. Replica count can be adjusted with:

```bash
kubectl scale deployment system-monitor --replicas=<N>
```

**Health probes** ensure only healthy Pods receive traffic:
- **Readiness probe** (`GET /` on port 8080): removes a Pod from the Service's routing pool if it stops responding, without killing it.
- **Liveness probe** (`GET /` on port 8080): restarts the container if it becomes unresponsive.

## Deployment Process

Manifests are applied in dependency order — storage and config first, then the workload:

```bash
kubectl apply -f manifests/pv.yaml
kubectl apply -f manifests/pvc.yaml
kubectl apply -f manifests/configmap.yaml
kubectl apply -f manifests/secret.yaml
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/service.yaml
```

Check status:

```bash
kubectl get pods
kubectl get pv,pvc
kubectl get svc
```

Test the app (via port-forward, since NodePort isn't host-reachable on this `kind` setup):

```bash
kubectl port-forward svc/system-monitor-service 8080:80
curl http://localhost:8080/health.log
```

### Rolling Updates

To deploy a new image version with zero downtime:

```bash
# Build and load the new image into kind
docker build -t system-monitor:v2 ./app
kind load docker-image system-monitor:v2 --name system-monitor

# Trigger the rolling update
kubectl set image deployment/system-monitor system-monitor=system-monitor:v2

# Watch the rollout
kubectl rollout status deployment/system-monitor
```

Kubernetes replaces Pods one at a time by default, so the Service always has at least 2 healthy replicas available during the update — no downtime.

To roll back if something goes wrong:

```bash
kubectl rollout undo deployment/system-monitor
```
## Ingress Routing Configuration

Routing is host-based: requests for `monitor.local` are matched and sent to
`system-monitor-service` on port 80 (which forwards to the Pods' port 8080).

\`\`\`yaml
rules:
  - host: monitor.local
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: system-monitor-service
              port:
                number: 80
\`\`\`

Path-based routing can be added by adding more entries under `paths`, e.g.
routing `/api` to a different backend Service, without needing a new Ingress
or a new external IP.
## HTTPS / TLS Setup

TLS is terminated at the Ingress Controller using a Kubernetes `Secret` of
type `kubernetes.io/tls`.

**For local development** (this repo currently uses this):
\`\`\`bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout monitor.local.key \
  -out monitor.local.crt \
  -subj "/CN=monitor.local/O=system-monitor"

kubectl create secret tls system-monitor-tls \
  --cert=monitor.local.crt \
  --key=monitor.local.key
\`\`\`

**For production**, replace the self-signed cert with a real one, typically
automated via [cert-manager](https://cert-manager.io/) and Let's Encrypt —
cert-manager watches Ingress resources and automatically requests, renews,
and stores certificates as Secrets, so no manual cert generation is needed.

The Ingress references the Secret like this:
\`\`\`yaml
tls:
  - hosts:
      - monitor.local
    secretName: system-monitor-tls
\`\`\`
