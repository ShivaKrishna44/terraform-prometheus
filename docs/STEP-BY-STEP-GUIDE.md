# Prometheus Monitoring Stack — Complete Step-by-Step Guide

Do this end-to-end without asking anyone. Every step, every command, every check.

---

## Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform installed
- SSH key pair in AWS (or create one — see Step 1)

---

## Step 1: Create SSH Key Pair (If You Don't Have One)

```bash
# Generate locally
ssh-keygen -t rsa -b 2048 -f C:/Devops/my-new-key -N ""

# This creates:
# C:/Devops/my-new-key       (private — for SSH)
# C:/Devops/my-new-key.pub   (public — goes to AWS)
```

---

## Step 2: Create S3 Backend (For Terraform State)

```bash
aws s3 mb s3://vosukula-remote-state --region us-east-1

aws dynamodb create-table --table-name vosukula-state-lock1 \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

---

## Step 3: Deploy Infrastructure

```bash
cd C:/Devops/Repository/terraform-prometheus

terraform init
terraform plan
terraform apply -auto-approve
```

**Expected outputs:**
```
prometheus_url     = "http://<ip>:9090"
grafana_url        = "http://<ip>:3000"
alertmanager_url   = "http://<ip>:9093"
node_exporter_public_ip = "<ip>"
```

**Save these IPs — you'll need them.**

---

## Step 4: Wait 3-5 Minutes

The user_data script installs everything on boot. It takes time to:
- Download Prometheus (~80MB)
- Download Grafana (~95MB)
- Download Alertmanager (~30MB)
- Download Node Exporter (~10MB)
- Start all services

---

## Step 5: Verify Services Are Running

### Option A: From your laptop (no SSH needed)

```bash
# Check Prometheus
curl -s http://<prometheus-ip>:9090/-/healthy
# Expected: "Prometheus Server is Healthy"

# Check Grafana
curl -s http://<prometheus-ip>:3000/api/health
# Expected: {"commit":"...","database":"ok","version":"..."}

# Check Node Exporter
curl -s http://<node-exporter-ip>:9100/metrics | head -5
# Expected: Lines starting with "# HELP" or "# TYPE"
```

### Option B: SSH in and check (if curl fails)

```bash
ssh -i C:/Devops/my-new-key ec2-user@<prometheus-ip>

# Check services
sudo systemctl status prometheus
sudo systemctl status grafana-server
sudo systemctl status alertmanager

# Check user_data log (did the script complete?)
sudo tail -20 /var/log/cloud-init-output.log
# Look for: "=== Monitoring Stack Installed ==="
```

---

## Step 6: Troubleshooting If Services Don't Start

### Problem: "wget: command not found"
```bash
sudo yum install -y wget tar
sudo bash /var/lib/cloud/instance/scripts/part-001  # Re-run user_data
```

### Problem: Prometheus won't start (config error)
```bash
# Check what's wrong
/opt/prometheus/promtool check config /opt/prometheus/prometheus.yml

# If alert rules have "labels" at group level — remove them
sudo sed -i '/^  labels:/d' /opt/prometheus/alert-rules/*.yml
sudo sed -i '/^    team: devops/d' /opt/prometheus/alert-rules/*.yml

# Restart
sudo systemctl restart prometheus
```

### Problem: Grafana install killed (OOM)
```bash
# Check memory
free -h
# If less than 500MB free — instance too small

# Fix: use t3.small (2GB RAM) instead of t3.micro (1GB)
# Update variables.tf → instance_type = "t3.small"
# terraform apply
```

### Problem: Disk full
```bash
df -h
# If root is 100% — disk too small

# Fix: add root_block_device { volume_size = 20 } in main.tf
# terraform apply (recreates instance)
```

---

## Step 7: Configure Grafana Dashboard

1. Open browser: `http://<prometheus-ip>:3000`
2. Login: `admin` / `admin` (change password or skip)
3. **Add Data Source:**
   - Go to: Connections → Data sources → Add data source
   - Select: Prometheus
   - URL: `http://localhost:9090`
   - Click: Save & Test
   - Expected: "Data source is working" ✅
4. **Import Dashboard:**
   - Go to: Dashboards → Import
   - Dashboard ID: `1860` → Click Load
   - Select Prometheus data source → Import
   - Expected: Node Exporter Full dashboard with CPU, Memory, Disk graphs

---

## Step 8: Verify Prometheus Targets

Open: `http://<prometheus-ip>:9090/targets`

You should see:
| Target | Status |
|--------|--------|
| prometheus (localhost:9090) | UP ✅ |
| ec2_instances (172.x.x.x:9100) | UP ✅ |

If ec2_instances shows DOWN — the node-exporter instance might still be booting or security group isn't allowing port 9100.

---

## Step 9: Check Alert Rules

Open: `http://<prometheus-ip>:9090/alerts`

You should see:
| Alert | Status |
|-------|--------|
| CPUUtilisationAlert | inactive (green) |
| DiskAlmostFull | inactive (green) |
| InstanceDownAlert | inactive (green) |
| HighMemoryAlert | inactive (green) |

All green = everything healthy. No alerts firing.

---

## Step 10: Test Alerting (Simulate Instance Down)

```bash
# Stop the monitored instance
aws ec2 stop-instances --instance-ids $(aws ec2 describe-instances --filters "Name=tag:Name,Values=node-exporter-target" --query "Reservations[0].Instances[0].InstanceId" --output text --region us-east-1) --region us-east-1
```

**Wait 1-2 minutes, then check:**

1. Prometheus Alerts (`http://<ip>:9090/alerts`):
   - InstanceDownAlert → changes from green → yellow (pending) → red (firing)

2. Alertmanager (`http://<ip>:9093`):
   - Shows "1 alert" with instance details

3. Email (if configured):
   - Receive email: "Alert: Instance is Down"

**Start it back:**
```bash
aws ec2 start-instances --instance-ids $(aws ec2 describe-instances --filters "Name=tag:Name,Values=node-exporter-target" --query "Reservations[0].Instances[0].InstanceId" --output text --region us-east-1) --region us-east-1
```

Alert auto-resolves after instance comes back up.

---

## Step 11: Configure Email Alerts (Optional)

SSH into prometheus server:
```bash
ssh -i C:/Devops/my-new-key ec2-user@<prometheus-ip>
sudo vi /opt/alertmanager/alertmanager.yml
```

Replace with:
```yaml
route:
  receiver: 'email'
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h

receivers:
  - name: 'email'
    email_configs:
      - smarthost: 'smtp.gmail.com:587'
        auth_username: 'your-email@gmail.com'
        auth_password: 'your-16-char-app-password'
        from: 'your-email@gmail.com'
        to: 'your-email@gmail.com'
        headers:
          subject: 'Alert: {{ .CommonAnnotations.summary }}'
```

**Get Gmail App Password:**
Google Account → Security → 2-Step Verification → App passwords → Generate

```bash
sudo systemctl restart alertmanager
```

---

## Step 12: Add More Targets to Monitor

Any EC2 instance tagged `Monitoring=true` with node_exporter running gets auto-discovered.

To add a new target:
1. Launch EC2 with tag `Monitoring=true`
2. Install node_exporter on it:
```bash
cd /opt
sudo wget https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz
sudo tar -xvf node_exporter-1.8.1.linux-amd64.tar.gz
sudo mv node_exporter-1.8.1.linux-amd64 node_exporter
sudo cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter Agent
Wants=network-online.target
After=network-online.target
[Service]
ExecStart=/opt/node_exporter/node_exporter
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable --now node_exporter
```
3. Prometheus discovers it within 60 seconds — check Targets page.

---

## Step 13: Cleanup (Stop Billing)

```bash
cd C:/Devops/Repository/terraform-prometheus
terraform destroy -auto-approve
```

---

## Quick Reference Card

| What | URL | Credentials |
|------|-----|-------------|
| Prometheus | http://IP:9090 | None |
| Grafana | http://IP:3000 | admin/admin |
| Alertmanager | http://IP:9093 | None |
| Node Exporter | http://IP:9100/metrics | None |

| Check | Command |
|-------|---------|
| Service running? | `sudo systemctl status prometheus` |
| Config valid? | `/opt/prometheus/promtool check config /opt/prometheus/prometheus.yml` |
| User data log | `sudo tail -20 /var/log/cloud-init-output.log` |
| Disk space | `df -h` |
| Memory | `free -h` |
| Reload config (no restart) | `curl -X POST http://localhost:9090/-/reload` |

---

## Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| Services not reachable | Script still running | Wait 3-5 min, check cloud-init log |
| wget not found | Amazon Linux 2023 missing wget | `sudo yum install -y wget tar` |
| Prometheus won't start | Bad alert rule YAML | `promtool check config` to find error |
| Grafana install killed | OOM on t3.micro (1GB RAM) | Use t3.small (2GB RAM) |
| Disk full | Default 8GB too small | Add `root_block_device { volume_size = 20 }` |
| Can't SSH | Wrong key or permissions | `chmod 400 key.pem` or use correct key |
| Targets DOWN | Security group or node_exporter not running | Check port 9100 in SG, check service |
| Grafana "No data" | Wrong datasource URL | Use `http://localhost:9090` (not public IP) |
