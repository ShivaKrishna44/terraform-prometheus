# Terraform Prometheus — EC2 Monitoring Stack

One `terraform apply` launches a complete monitoring stack with dashboards and email alerts.

---

## What Gets Created

| Resource | Purpose | Port |
|----------|---------|------|
| EC2: prometheus-server | Prometheus + Grafana + Alertmanager | 9090, 3000, 9093 |
| EC2: node-exporter-target | Target being monitored | 9100 |
| Security Group | Opens required ports | 22, 3000, 9090, 9093, 9100 |
| IAM Role | Allows Prometheus EC2 auto-discovery | - |

---

## Architecture

```
┌─────────────────────────────────────┐
│  prometheus-server (t3.micro)        │
│                                      │
│  Prometheus (:9090)                  │
│    ├── Scrapes targets every 15s     │
│    ├── Evaluates alert rules         │
│    └── Sends alerts to Alertmanager  │
│                                      │
│  Grafana (:3000)                     │
│    ├── Queries Prometheus for data   │
│    └── Displays dashboards           │
│                                      │
│  Alertmanager (:9093)                │
│    ├── Receives alerts from Prometheus│
│    ├── Groups similar alerts         │
│    └── Sends email notifications     │
└──────────────────┬──────────────────┘
                   │ scrapes :9100 every 15s
                   ▼
┌─────────────────────────────────────┐
│  node-exporter-target (t3.micro)     │
│                                      │
│  Node Exporter (:9100)               │
│    └── Exposes: CPU, memory, disk,   │
│        network metrics               │
└─────────────────────────────────────┘

Prometheus auto-discovers ANY EC2 instance tagged: Monitoring=true
```

---

## How Monitoring Works (The Flow)

```
Step 1: Node Exporter runs on target EC2 → exposes metrics at :9100/metrics

Step 2: Prometheus scrapes :9100 every 15 seconds → stores metrics in time-series DB

Step 3: Prometheus evaluates alert rules every 15 seconds:
        "Is CPU > 80% for 5 minutes?" → YES → fires alert

Step 4: Prometheus sends alert to Alertmanager (:9093)

Step 5: Alertmanager groups alerts, waits 30s for more → sends email via Gmail SMTP

Step 6: Grafana queries Prometheus → displays real-time graphs on dashboard
```

---

## How Alerts Work

### Alert Rules (defined in Prometheus)

| Alert | Expression | Fires When |
|-------|-----------|-----------|
| InstanceDown | `up < 1` | Target unreachable for 1 minute |
| HighCPU | `CPU idle < 20%` | CPU > 80% for 5 minutes |
| HighMemory | `MemAvailable < 15%` | Memory > 85% for 5 minutes |
| DiskFull | `disk_avail < 20%` | Disk > 80% for 5 minutes |

### Alert Flow

```
Prometheus detects: CPU > 80% for 5 min
    ↓
Alert state: PENDING (waiting for 'for' duration)
    ↓ (5 min passes, still high)
Alert state: FIRING → sends to Alertmanager
    ↓
Alertmanager groups it, waits 30s (group_wait)
    ↓
Sends email: "Prometheus Alert: High CPU on node-exporter-target"
    ↓
When CPU drops below 80% → RESOLVED email sent
```

### Alertmanager Configuration

```yaml
route:
  receiver: 'email'
  group_by: ['alertname']     # Group alerts with same name
  group_wait: 30s              # Wait 30s to batch related alerts
  group_interval: 5m           # Between groups of same alert
  repeat_interval: 1h          # Don't spam — repeat every 1 hour

receivers:
  - name: 'email'
    email_configs:
      - smarthost: 'smtp.gmail.com:587'
        from: 'alerts@yourdomain.com'
        to: 'oncall@yourdomain.com'
```

---

## How Grafana Dashboard Works

### Setup After Deploy

```
1. Open Grafana: http://<prometheus-ip>:3000
2. Login: admin / admin (change password)
3. Add Data Source:
   → Configuration → Data Sources → Add → Prometheus
   → URL: http://localhost:9090
   → Click "Save & Test" → "Data source is working" ✅
4. Import Dashboard:
   → Dashboards → Import → Dashboard ID: 1860
   → Select Prometheus data source → Import
   → Node Exporter Full dashboard loads with all metrics
```

### What Dashboard Shows

| Panel | Metric | What It Tells You |
|-------|--------|-------------------|
| CPU Usage | `rate(node_cpu_seconds_total)` | How busy the server is |
| Memory Usage | `node_memory_MemAvailable_bytes` | How much RAM is free |
| Disk Space | `node_filesystem_avail_bytes` | How full the disk is |
| Network I/O | `rate(node_network_receive_bytes_total)` | Traffic in/out |
| System Load | `node_load1, node_load5, node_load15` | Overall system pressure |

### How Grafana Gets Data

```
Grafana panel has a PromQL query:
  → 100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
     ↓
Grafana sends HTTP request to Prometheus:
  → GET http://localhost:9090/api/v1/query_range?query=...&start=...&end=...
     ↓
Prometheus returns time-series data points
     ↓
Grafana renders the line graph
     ↓
Auto-refreshes every 10 seconds (configurable)
```

---

## Deploy

```bash
cd terraform-prometheus

# 1. Update alertmanager email (optional — for email alerts)
# Edit prometheus.sh → search for "your-from-email" and replace

# 2. Deploy
terraform init
terraform apply

# 3. Wait 2-3 minutes for user_data to finish installing
# 4. Open URLs from outputs
```

### Outputs

```
prometheus_url     = "http://3.95.xx.xx:9090"      ← Query metrics here
grafana_url        = "http://3.95.xx.xx:3000"      ← Dashboards here (admin/admin)
alertmanager_url   = "http://3.95.xx.xx:9093"      ← Alert status here
node_exporter_public_ip = "54.xx.xx.xx"             ← Target being monitored
```

---

## Verify Everything Works

```bash
# 1. Check Prometheus targets (should show node-exporter as UP)
# Open: http://<prometheus-ip>:9090/targets

# 2. Run a query in Prometheus
# Open: http://<prometheus-ip>:9090/graph
# Query: up
# Should show 2 results (prometheus itself + node-exporter)

# 3. Check Alertmanager
# Open: http://<prometheus-ip>:9093
# Shows active/silenced alerts

# 4. Check Node Exporter directly
# Open: http://<node-exporter-ip>:9100/metrics
# Raw metrics output (CPU, memory, disk, etc.)
```

---

## How EC2 Auto-Discovery Works

Instead of hardcoding target IPs, Prometheus auto-discovers EC2 instances:

```yaml
# In prometheus.yml
- job_name: "ec2_instances"
  ec2_sd_configs:
    - region: "us-east-1"
      filters:
        - name: tag:Monitoring
          values: ["true"]    ← Only instances with this tag
      port: 9100
```

**How it works:**
1. Prometheus uses IAM role to call `ec2:DescribeInstances`
2. Finds all instances tagged `Monitoring=true`
3. Adds them as scrape targets automatically
4. New instance tagged `Monitoring=true` → discovered within 60 seconds

**To add more targets:** Just launch any EC2 with tag `Monitoring=true` and node_exporter installed → Prometheus picks it up automatically.

---

## Adding Custom Alerts

Create a new rule file in `/opt/prometheus/alert-rules/`:

```yaml
# Example: Alert when disk I/O is high
groups:
- name: DiskIO
  rules:
  - alert: HighDiskIO
    expr: rate(node_disk_io_time_seconds_total[5m]) > 0.9
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "High disk I/O on {{ $labels.name }}"
```

Then reload Prometheus (no restart needed):
```bash
curl -X POST http://localhost:9090/-/reload
```

---

## Interview Answer

> "We run Prometheus on EC2 with EC2 service discovery — any instance tagged Monitoring=true gets automatically scraped. Alert rules evaluate every 15 seconds. When a threshold is breached (CPU > 80% for 5 min), Prometheus fires the alert to Alertmanager, which groups related alerts and sends email notifications via SMTP. Grafana connects to Prometheus as a data source and displays pre-built dashboards (Node Exporter Full, dashboard ID 1860). The entire stack deploys with one terraform apply including IAM, security groups, and user_data scripts."

---

## Cleanup

```bash
terraform destroy
```
