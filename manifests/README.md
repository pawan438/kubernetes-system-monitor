## Observability Architecture

\`\`\`mermaid
graph TB
    A[system-monitor Pods] -->|cAdvisor metrics| B[kubelet]
    A -->|pod state| C[kube-state-metrics]
    D[Cluster Nodes] -->|host metrics| E[node-exporter]
    B --> F[Prometheus]
    C --> F
    E --> F
    F -->|queried by| G[Grafana]
    F -->|evaluates| H[PrometheusRule alerts]
    H -->|fires to| I[Alertmanager]
\`\`\`

Prometheus, Grafana, and Alertmanager are deployed together via the
`kube-prometheus-stack` Helm chart (see `monitoring/prometheus-grafana-values.yaml`).
`system-monitor` itself is not instrumented — all metrics come from
Kubernetes-level sources (kubelet, kube-state-metrics, node-exporter),
which is sufficient for infrastructure-level observability of a simple app.

## Monitoring Workflow

1. Prometheus scrapes kubelet, kube-state-metrics, and node-exporter every
   30s (see `monitoring/metrics-collection.md` for the full pipeline).
2. Metrics are queried live via Grafana dashboards, or ad-hoc via the
   Prometheus UI/API for one-off investigation.
3. `PrometheusRule` alerts continuously evaluate against the same metrics
   and fire to Alertmanager when thresholds are breached.

## Logging Strategy

Application logs are handled two ways:
- **Real-time**: `kubectl logs -l app=system-monitor` — pulled directly
  from the container's stdout, which the health-check script writes to
  in addition to its log file.
- **Persistent**: the app also writes to `health.log` on its PVC
  (`/app/data/health.log`), which survives pod restarts and is separate
  from the ephemeral container logs `kubectl logs` shows.

There's no centralized log aggregation (e.g. Loki, ELK) in this project —
logs are checked per-pod via `kubectl logs`. This is a reasonable choice
at this scale (3 replicas, one namespace); a log aggregator would become
worthwhile if the app scaled to many pods/nodes where correlating logs
across pods by hand becomes impractical.

## Alert Configuration

See `monitoring/prometheus-rules.yaml`. Two alerts are defined:

| Alert | Condition | Severity |
|---|---|---|
| `SystemMonitorPodDown` | Fewer than 3 pods `Running` for over 1 minute | critical |
| `SystemMonitorHighCPU` | CPU usage exceeds 0.15 cores for over 2 minutes | warning |

Both were verified via `curl http://localhost:9090/api/v1/rules` to be
loaded and evaluating (`"health":"ok"`). The 1-minute debounce on pod-down
is intentional — it's longer than the ~12 seconds a normal pod replacement
takes, so only genuinely stuck failures page, not routine self-healing.

## Dashboard Overview

- **Kubernetes / Views / Global** (community, ID 15757) — cluster-wide
  CPU/RAM/resource-count overview, useful for spotting cluster-level
  pressure unrelated to this specific app.
- **system-monitor Overview** (custom, `monitoring/grafana-dashboard-system-monitor.json`)
  — CPU usage, memory usage, and per-pod Running status, scoped
  specifically to this app's 3 replicas.

## Troubleshooting Workflow

See `monitoring/troubleshooting.md` for detailed, scenario-based
investigation steps (pod crashes, high resource usage, missing replicas,
Ingress connectivity). General approach: start with `kubectl get pods` +
`kubectl describe pod` for anything not `Running`; use Prometheus/Grafana
to confirm resource-related theories with real numbers; check
`kubectl get events` for a timeline of what Kubernetes itself observed.
