## Monitoring & Observability

This project uses **Prometheus** and **Grafana**, installed via the
`kube-prometheus-stack` Helm chart, for metrics collection and visualization.

### Installation

\`\`\`bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring
\`\`\`

This installs Prometheus, Grafana, Alertmanager, node-exporter, and
kube-state-metrics as a single bundled stack, with Grafana pre-configured
to use Prometheus as a data source.

### Accessing the dashboards

Both are ClusterIP by default (no external exposure, consistent with this
project's security posture) — access locally via port-forward:

\`\`\`bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
\`\`\`

Grafana admin password:
\`\`\`bash
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d
\`\`\`

### Dashboards

- **Kubernetes / Views / Global** (community dashboard ID 15757) — cluster-wide
  CPU, RAM, and resource-count overview.
- **system-monitor Overview** (custom, `grafana-dashboard-system-monitor.json`)
  — CPU usage, memory usage, and live Pod status specifically for this app's
  pods.

### Application logs and events

\`\`\`bash
# Recent logs across all system-monitor pods
kubectl logs -l app=system-monitor --tail=20

# Recent cluster events, filtered to this app's pods
kubectl get events --field-selector involvedObject.kind=Pod \
  --sort-by='.lastTimestamp' | grep system-monitor
\`\`\`

### Alerting

Two Prometheus alerts are defined in `prometheus-rules.yaml`:

| Alert | Condition | Severity |
|---|---|---|
| `SystemMonitorPodDown` | Fewer than 3 `system-monitor` pods `Running` for over 1 minute | critical |
| `SystemMonitorHighCPU` | Combined CPU usage exceeds 0.15 cores (75% of the 200m limit) for over 2 minutes | warning |

Apply with:
\`\`\`bash
kubectl apply -f prometheus-rules.yaml
\`\`\`

Verify rules are loaded and evaluating:
\`\`\`bash
curl -s http://localhost:9090/api/v1/rules | grep -A2 SystemMonitor
\`\`\`
## Failure Simulation & Self-Healing

To verify observability end-to-end, a pod was deleted manually while the
cluster was under normal load:

\`\`\`bash
kubectl delete pod <system-monitor-pod-name>
\`\`\`

**Observed behavior:**
1. Kubernetes Events showed `Killing` for the deleted pod, followed by
   `Scheduled`, `Pulled`, `Created`, and `Started` for its replacement
   — including the `fix-permissions` init container running again before
   the main app container started.
2. The replacement pod reached `1/1 Running` within ~12 seconds — fast
   enough that the `SystemMonitorPodDown` alert (which requires a 1-minute
   sustained gap) did not fire, demonstrating that the Deployment's
   self-healing is faster than the alert's intentional debounce window.
3. `kube_pod_status_phase` in Prometheus reflected the transition in
   real time — the deleted pod's `Running` series dropped to `0`
   while the new pod's `Running` series appeared at `1`.

This confirms the monitoring stack captures Pod-level failures accurately,
and that Kubernetes' own reconciliation loop handles recovery fast enough
that end users would see no meaningful downtime with 3 replicas.

