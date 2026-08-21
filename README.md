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

---

## CI/CD Pipeline (GitHub Actions)

Automated Terraform workflow: developer pushes → plan runs → team approves → apply runs automatically.

### Flow

```
Developer pushes to feature/* branch
    ↓
Creates PR to main
    ↓
terraform plan runs automatically → plan output posted as PR comment
    ↓
Team reviews PR + plan output → approves & merges
    ↓
Merge to main triggers terraform apply job
    ↓
GitHub Environment "production" approval gate
    ↓
Designated reviewer approves in GitHub UI
    ↓
terraform apply -auto-approve runs (zero human intervention after approval)
```

### Pipeline Triggers

| Event | What Happens |
|-------|-------------|
| Push to `feature/**` | Plan only (validates changes) |
| PR to `main` | Plan + posts output as PR comment |
| Merge/push to `main` | Plan + Apply (after environment approval) |

### Setup for a New Team Member (Step-by-Step)

Follow these steps if you're setting up this repo from scratch or onboarding.

#### Step 1: Prerequisites

- AWS account with admin access (to create IAM resources)
- GitHub repo (this one) with Actions enabled
- Terraform CLI installed locally (v1.7+)
- AWS CLI installed and configured locally

#### Step 2: Generate SSH Key Pair

The key pair is used for SSH access to the EC2 instances.

```bash
# Generate a new key pair (if you don't have one)
ssh-keygen -t ed25519 -f keys/my-new-key -C "terraform-prometheus"

# This creates:
#   keys/my-new-key       ← PRIVATE key (never commit this!)
#   keys/my-new-key.pub   ← PUBLIC key (safe to commit, referenced by Terraform)
```

Place the `.pub` file in the `keys/` directory of this repo. The private key stays on your machine only.

#### Step 3: Create AWS OIDC Identity Provider (one-time)

This allows GitHub Actions to assume an IAM role without storing any AWS credentials.

```bash
# Create the OIDC provider in AWS (run once per AWS account)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

#### Step 4: Create IAM Role for GitHub Actions

Create a role that GitHub Actions can assume via OIDC.

```bash
# Create trust policy file
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<YOUR_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO>:*"
        }
      }
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name GitHubActions-TerraformPrometheus \
  --assume-role-policy-document file://trust-policy.json

# Attach permissions (adjust to least-privilege for production)
aws iam attach-role-policy \
  --role-name GitHubActions-TerraformPrometheus \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

# Also needs S3 + DynamoDB for state backend
aws iam attach-role-policy \
  --role-name GitHubActions-TerraformPrometheus \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam attach-role-policy \
  --role-name GitHubActions-TerraformPrometheus \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
```

> **Note:** Replace `<YOUR_ACCOUNT_ID>`, `<YOUR_GITHUB_ORG>`, and `<YOUR_REPO>` with actual values.

#### Step 5: Configure GitHub Repository

1. Go to **Settings → Secrets and variables → Actions → Variables tab**
2. Add repository variable:

| Variable | Value |
|----------|-------|
| `AWS_ROLE_ARN` | `arn:aws:iam::<ACCOUNT_ID>:role/GitHubActions-TerraformPrometheus` |

> We use a **variable** (not a secret) because the role ARN is not sensitive — it can't be used without OIDC auth.

#### Step 6: Create GitHub Environment with Approval Gate

1. Go to **Settings → Environments → New environment**
2. Name it: `production`
3. Check **Required reviewers** → add team members who approve infra changes
4. Optionally set a **Wait timer** (e.g., 5 minutes for cooling off)

After this, when code merges to `main`:
- The apply job shows **"Waiting for review"** in Actions
- Reviewer gets notified → clicks **"Approve and deploy"**
- `terraform apply` runs automatically

#### Step 7: Create S3 Backend (if not exists)

The Terraform state is stored in S3 with DynamoDB locking.

```bash
# Create S3 bucket for state
aws s3api create-bucket \
  --bucket shivakrishna-tf-state-dev \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket shivakrishna-tf-state-dev \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name vosukula-state-locking \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

#### Step 8: First Local Run (verify it works)

```bash
cd terraform-prometheus
terraform init
terraform plan
# Review the plan output
terraform apply
```

#### Step 9: Push and Test Pipeline

```bash
git checkout -b feature/test-pipeline
# Make a small change (e.g., add a tag)
git add . && git commit -m "test: verify CI/CD pipeline"
git push -u origin feature/test-pipeline
# Open PR → plan runs and posts comment → review → merge → apply runs
```

### How Approval Works (No Secrets Anywhere)

| Component | How It's Secured |
|-----------|-----------------|
| AWS credentials | OIDC — GitHub proves identity to AWS, no keys stored |
| SSH public key | Committed in `keys/` directory (public keys are not secrets) |
| SSH private key | Never committed — stays on developer's machine only |
| State file | S3 bucket with encryption + DynamoDB locking |
| Apply permission | GitHub Environment approval gate (human review) |

### Workflow Diagram

```
┌──────────────┐     ┌───────────────┐     ┌──────────────────┐
│  Developer   │────▶│  GitHub PR    │────▶│  terraform plan  │
│  pushes code │     │  created      │     │  runs in Actions │
└──────────────┘     └───────────────┘     └────────┬─────────┘
                                                     │
                                            Plan output posted
                                            as PR comment
                                                     │
                                                     ▼
                     ┌───────────────┐     ┌──────────────────┐
                     │  Team reviews │────▶│  PR merged to    │
                     │  plan output  │     │  main branch     │
                     └───────────────┘     └────────┬─────────┘
                                                     │
                                                     ▼
                     ┌───────────────┐     ┌──────────────────┐
                     │  Environment  │────▶│  terraform apply │
                     │  approval     │     │  -auto-approve   │
                     └───────────────┘     └──────────────────┘
                     (reviewer clicks              │
                      "Approve")                   ▼
                                           Infrastructure
                                           deployed to AWS
```

### Local Development (unchanged)

```bash
# Still works exactly as before
terraform init
terraform plan
terraform apply
```

The pipeline uses OIDC — your local machine uses `~/.aws/credentials` or `aws configure` as normal. No overlap, no conflicts.

