# Bank Transaction Simulator

Generates realistic ICICI/HDFC-style banking traffic for Prometheus + Grafana monitoring.

## What It Simulates

| Metric | Description |
|--------|-------------|
| Transactions/sec | 50-150 TPS depending on time of day |
| Transaction types | UPI (40%), Card (20%), IMPS (15%), NEFT (10%), ATM (8%), RTGS (5%), Cheque (2%) |
| Channels | Mobile App, Internet Banking, ATM, Branch, POS Terminal |
| Regions | Mumbai, Delhi, Bangalore, Hyderabad, Chennai, Kolkata, Pune, Ahmedabad |
| Success rates | UPI: 96%, Card: 94%, ATM: 92%, NEFT: 99%, RTGS: 99.5% |
| Active users | 45K mobile, 12K web, 3K ATM (peak hours: 3x multiplier) |
| Failure reasons | Insufficient funds, timeout, fraud block, invalid account, daily limit exceeded |
| Latency | UPI: 300ms, NEFT: 2s, ATM: 3s (failures take 3x longer) |

## Traffic Patterns (Realistic)

```
Time         Multiplier   TPS     Active Users
00:00-06:00  0.4x         ~20     Low (ATM only)
06:00-09:00  1.0x         ~50     Waking up
09:00-12:00  2.5x         ~125    Morning peak (salary credits, bill pay)
12:00-14:00  1.8x         ~90     Lunch dip
14:00-18:00  2.2x         ~110    Afternoon
18:00-21:00  3.0x         ~150    Evening peak (UPI dinner, shopping)
21:00-00:00  1.2x         ~60     Late night
```

## Quick Start (Local)

```bash
cd bank-simulator
pip install -r requirements.txt
python app.py
```

Open:
- http://localhost:8000/ — Simulator info page
- http://localhost:8000/metrics — Raw Prometheus metrics

## Deploy on EC2 (with existing Prometheus stack)

### Step 1: Copy to your node-exporter instance (or any EC2)

```bash
scp -i your-key.pem -r bank-simulator/ ec2-user@<instance-ip>:~/
```

### Step 2: Install and run

```bash
ssh -i your-key.pem ec2-user@<instance-ip>

cd bank-simulator
pip3 install -r requirements.txt
nohup python3 app.py > /tmp/bank-simulator.log 2>&1 &
```

### Step 3: Add to Prometheus config

On your Prometheus server, edit `/opt/prometheus/prometheus.yml`:

```yaml
scrape_configs:
  # Existing configs...

  - job_name: "bank_simulator"
    scrape_interval: 5s
    static_configs:
      - targets: ["<simulator-ip>:8000"]
        labels:
          app: "bank-transactions"
```

Reload Prometheus:
```bash
curl -X POST http://localhost:9090/-/reload
```

### Step 4: Copy alert rules

```bash
cp alert-rules.yaml /opt/prometheus/alert-rules/bank-alerts.yaml
curl -X POST http://localhost:9090/-/reload
```

### Step 5: Import Grafana Dashboard

In Grafana (http://<prometheus-ip>:3000):
1. Go to Dashboards → Import
2. Paste the JSON from `grafana-dashboard.json` (or create panels manually)

## Key Prometheus Queries (for Grafana panels)

### Transactions per second (by type)
```promql
sum(rate(bank_transactions_total[1m])) by (type)
```

### Success rate (%)
```promql
sum(rate(bank_transactions_total{status="success"}[5m])) / sum(rate(bank_transactions_total[5m])) * 100
```

### Revenue per minute (INR)
```promql
sum(rate(bank_revenue_total_inr[1m])) by (region)
```

### P95 latency by transaction type
```promql
histogram_quantile(0.95, sum(rate(bank_response_time_seconds_bucket[5m])) by (le, type))
```

### Active users by channel
```promql
bank_active_users
```

### Failure reasons breakdown
```promql
sum(rate(bank_transaction_failures[5m])) by (reason)
```

### Top failing regions
```promql
topk(5, sum(rate(bank_transactions_total{status="failed"}[5m])) by (region))
```

### Pending queue depth
```promql
bank_pending_transactions
```

### System errors by service
```promql
sum(rate(bank_system_errors_total[5m])) by (service)
```

## Alert Rules

| Alert | Condition | Severity |
|-------|-----------|----------|
| HighTransactionFailureRate | >5% failures for 2m | Critical |
| UPIHighFailureRate | >3% UPI failures for 3m | Critical |
| HighTransactionLatency | P95 > 5s for 3m | Warning |
| HighPendingQueue | NEFT queue > 1000 for 5m | Warning |
| ActiveUsersDropped | Mobile users drop >50% | Critical |
| FraudBlockSpike | >10 blocks/sec for 2m | Warning |
| SystemErrorsHigh | >5 errors/sec for 1m | Critical |
| NoTransactions | 0 TPS for 2m | Critical |
| LoginFailureRateHigh | >15% login failures for 3m | Warning |
| RevenueDrop | Revenue <50% vs yesterday | Warning |

## Interview Answer

> "We built a banking transaction monitoring system with Prometheus and Grafana. The application exposes custom metrics — transaction counters by type/status/channel/region, latency histograms, active user gauges, and queue depth. Prometheus scrapes every 5 seconds. We have alert rules for failure rate spikes (>5% triggers PagerDuty), latency degradation (P95 > 5s), and complete outage detection (0 TPS for 2 minutes). Grafana dashboards show real-time TPS, revenue, success rates, and regional breakdown. The on-call team gets notified via Alertmanager → Slack + PagerDuty with runbook links."
