# system-monitor-chart

A Helm chart for deploying the `system-monitor` application, supporting
separate configurations for development and production environments.

## Chart Structure

\`\`\`
system-monitor-chart/
├── Chart.yaml              # Chart metadata (name, version, appVersion)
├── values.yaml              # Default configuration
├── values-dev.yaml          # Dev environment overrides
├── values-prod.yaml         # Production environment overrides
└── templates/
    ├── _helpers.tpl           # Naming/label helpers shared across templates
    ├── deployment.yaml         # Deployment (init container, security context, probes)
    ├── service.yaml            # ClusterIP Service
    ├── ingress.yaml            # Ingress with TLS
    ├── configmap.yaml          # App configuration (LOG_FILE, THRESHOLD)
    ├── secret.yaml             # ALERT_WEBHOOK_TOKEN
    ├── pvc.yaml                # PersistentVolumeClaim
    ├── serviceaccount.yaml     # Dedicated ServiceAccount
    └── NOTES.txt               # Post-install access instructions
\`\`\`

Note: RBAC (Role/RoleBinding) and NetworkPolicy are managed as plain
manifests outside this chart (see `../manifests/`), not templated here —
this chart focuses on the resources explicitly scoped for Helm
management (Deployment, Service, Ingress, ConfigMap, Secret, PVC).

## Configuration Management

All configurable values live in `values.yaml`, including:
- `image.repository` / `image.tag` — which container image to run
- `replicaCount` — number of pod replicas
- `resources` — CPU/memory requests and limits
- `config.logFile` / `config.threshold` — app behavior via ConfigMap
- `secret.alertWebhookToken` — sensitive config via Secret
- `ingress.hosts` / `ingress.tls` — routing and HTTPS
- `persistence.size` — PVC storage size

Nothing app-specific is hardcoded in the templates — every environment
difference is expressed through values files layered on top of the base.

## Environment-Specific Configuration

\`\`\`bash
# Development (1 replica, lower resource limits, monitor-dev.local)
helm install system-monitor . -f values-dev.yaml

# Production (5 replicas, higher resource limits, monitor.example.com)
helm install system-monitor . -f values-prod.yaml
\`\`\`

`values-dev.yaml` and `values-prod.yaml` only specify what differs from
`values.yaml` — Helm merges them on top of the defaults at install/upgrade
time.

## Installation Guide

\`\`\`bash
# Validate the chart before installing
helm lint .
helm template . -f values-dev.yaml

# Install
helm install system-monitor . -f values-dev.yaml

# Verify
kubectl get pods -l app=system-monitor
helm status system-monitor
\`\`\`

**Prerequisite**: if reusing an existing PVC/PV from a prior non-Helm
deployment, Helm will refuse to manage it until it's labeled/annotated
correctly:
\`\`\`bash
kubectl label pvc system-monitor-pvc app.kubernetes.io/managed-by=Helm
kubectl annotate pvc system-monitor-pvc meta.helm.sh/release-name=system-monitor
kubectl annotate pvc system-monitor-pvc meta.helm.sh/release-namespace=default
\`\`\`

## Upgrade and Rollback Process

**Upgrade** — change any value, then apply:
\`\`\`bash
# Edit values-dev.yaml, e.g. change replicaCount
helm upgrade system-monitor . -f values-dev.yaml
kubectl get pods -l app=system-monitor
\`\`\`

**Rollback** — revert to any previous revision:
\`\`\`bash
helm history system-monitor              # List all revisions
helm rollback system-monitor <revision>    # Roll back to a specific one
\`\`\`

Every `helm upgrade` and `helm rollback` creates a **new** revision entry
— rollback doesn't delete history, it adds a new revision that restores
an old configuration. This was verified in this project: revision 1
(install, 1 replica) → revision 2 (upgrade, 2 replicas) → revision 3
(rollback to revision 1, back to 1 replica) — all three remain visible
in `helm history`.

## Best Practices Followed

- **No hardcoded secrets in templates** — `secret.yaml`'s value comes
  from `values.yaml`/environment overrides, never committed as a real
  token (see the main repo's `.gitignore` and `secret.yaml.example`
  pattern for the equivalent plain-manifest approach).
- **`helm lint` and `helm template` before every install/upgrade** —
  catches YAML/templating errors without touching the cluster.
- **Environment-specific values files, not branching templates** —
  `values-dev.yaml`/`values-prod.yaml` differ only in values, not logic;
  the templates themselves stay identical across environments.
- **Explicit resource requests/limits per environment** — dev runs
  leaner than production, rather than one-size-fits-all.
- **Chart version and app version tracked separately** in `Chart.yaml`
  (`version` for the chart's own changes, `appVersion` for the
  `system-monitor` image tag it deploys).
