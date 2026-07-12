# Metrics Collection

This document describes how metrics are collected for `system-monitor`
and the cluster it runs on.

## Collection pipeline

\`\`\`
[Pod: system-monitor]  [kubelet/cAdvisor]  [kube-state-metrics]  [node-exporter]
         │                     │                     │                  │
         └─────────────────────┴─────────────────────┴──────────────────┘
                                       │
                                  [Prometheus]
                                (scrapes every 30s)
                                       │
                                  [Grafana]
                              (queries Prometheus,
                               renders dashboards)
\`\`\`

Prometheus doesn't scrape `system-monitor` directly — the app itself
exposes no `/metrics` endpoint (it's a bash health-check script, not an
instrumented service). Instead, metrics come from three sources the
`kube-prometheus-stack` chart installs automatically:

| Source | Provides |
|---|---|
| **kubelet / cAdvisor** | Per-container CPU, memory, network, filesystem usage — the `container_*` metrics |
| **kube-state-metrics** | Kubernetes object state — pod phase, replica counts, restarts — the `kube_*` metrics |
| **node-exporter** | Host-level metrics — node CPU, memory, disk — the `node_*` metrics |

## Key metrics used in this project

| Metric | Meaning |
|---|---|
| `container_cpu_usage_seconds_total` | Cumulative CPU seconds consumed; use with `rate()` for a usage rate |
| `container_memory_working_set_bytes` | Actual memory in use (closest to what OOM-killer considers) |
| `kube_pod_status_phase` | Pod lifecycle phase (`Running`, `Pending`, `Failed`, etc.) as a 1/0 gauge per phase |
| `kube_pod_container_status_restarts_total` | Restart count per container — spikes indicate crash loops |

## Scrape configuration

Scrape targets and intervals are managed automatically by the Prometheus
Operator via `ServiceMonitor` and `PodMonitor` custom resources, which
`kube-prometheus-stack` creates out of the box for kubelet, node-exporter,
and kube-state-metrics. No manual `prometheus.yml` scrape config was
written for this project — this is one of the main advantages of the
Operator pattern over vanilla Prometheus.

To see what's currently being scraped:
\`\`\`bash
kubectl get servicemonitors -n monitoring
kubectl get podmonitors -n monitoring
\`\`\`

## If application-level metrics were added later

Currently `system-monitor` only exposes a directory listing and log file
over HTTP — no `/metrics` endpoint. If custom app metrics were added
(e.g. instrumenting `main.sh`'s checks with a Prometheus client library
or a simple text-based exporter), a `ServiceMonitor` would need to be
added pointing at that endpoint, something like:

\`\`\`yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: system-monitor
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: system-monitor
  endpoints:
    - port: metrics
      interval: 30s
\`\`\`

This is documented here as a placeholder for future work, not yet
implemented in this project.

