# Kubernetes System Monitor

A containerized system health-check application deployed on Kubernetes.
It checks CPU, RAM, and disk usage every 30 seconds and serves the results
over HTTP.

## Project Structure
kubernetes-system-monitor/
├── app/                  # Application source
│   ├── dockerfile         # Docker image definition
│   ├── main.sh             # Core health-check logic (CPU/RAM/disk)
│   └── start.sh             # Wrapper: loops main.sh + runs HTTP server
├── manifests/            # Kubernetes manifests
│   ├── deployment.yaml     # Deployment (3 replicas)
│   └── service.yaml         # NodePort Service
└── README.md              # This file
## Application Flow

1. `start.sh` is the container's entrypoint. It does two things in parallel:
   - Starts a Python HTTP server on port 8080, serving `health.log`
   - Runs `main.sh` in a loop every 30 seconds
2. `main.sh` checks CPU, RAM, and disk usage. If any exceed 85%, it logs a
   CRITICAL message; otherwise it logs STATUS OKAY.
3. Each check result is appended to `/app/health.log` inside the container.
4. The Kubernetes Service exposes port 80 (routed to container port 8080),
   so `health.log` can be viewed over HTTP.
5. The Deployment runs 3 replicas. If a Pod is deleted or crashes,
   Kubernetes automatically creates a new one to maintain 3 running Pods.

## Deployment Instructions

**1. Build the Docker image:**
```bash
cd app
docker build -t system-monitor:v1 -f dockerfile .
```

**2. Load the image into your kind cluster:**
```bash
kind load docker-image system-monitor:v1 --name <your-cluster-name>
```

**3. Apply the manifests:**
```bash
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/service.yaml
```

**4. Verify Pods are running:**
```bash
kubectl get pods
```

**5. Access the health log (kind doesn't expose NodePorts to host by default):**
```bash
kubectl port-forward svc/system-monitor-service 8080:80
curl http://localhost:8080/health.log
```

**6. Test self-healing (delete a Pod, confirm it's replaced):**
```bash
kubectl get pods
kubectl delete pod <pod-name>
kubectl get pods
```
