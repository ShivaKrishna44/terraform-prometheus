#!/bin/bash
set -e

# Update system
sudo yum update -y
sudo yum install -y wget tar

# --- Install Prometheus ---
cd /opt
sudo wget https://github.com/prometheus/prometheus/releases/download/v2.53.0/prometheus-2.53.0.linux-amd64.tar.gz
sudo tar -xvf prometheus-2.53.0.linux-amd64.tar.gz
sudo mv prometheus-2.53.0.linux-amd64 prometheus

# Prometheus config
sudo cat > /opt/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["localhost:9093"]

rule_files:
  - "alert-rules/*.yml"

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
        labels:
          app: "prometheus"

  - job_name: "ec2_instances"
    ec2_sd_configs:
      - region: "us-east-1"
        filters:
          - name: tag:Monitoring
            values: ["true"]
        port: 9100
    relabel_configs:
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance_id
      - source_labels: [__meta_ec2_tag_Name]
        target_label: name
      - source_labels: [__meta_ec2_private_ip]
        target_label: private_ip
EOF

# Alert rules
sudo mkdir -p /opt/prometheus/alert-rules

sudo cat > /opt/prometheus/alert-rules/instance-down.yml << 'EOF'
groups:
- name: InstanceDown
  rules:
  - alert: InstanceDownAlert
    expr: up < 1
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Instance is Down"
EOF

sudo cat > /opt/prometheus/alert-rules/cpu-utilisation.yml << 'EOF'
groups:
- name: CPUUtilisation
  rules:
  - alert: CPUUtilisationAlert
    expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])*100)) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High CPU on {{ $labels.name }}"
EOF

sudo cat > /opt/prometheus/alert-rules/memory.yml << 'EOF'
groups:
- name: MemoryUsage
  rules:
  - alert: HighMemoryAlert
    expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High memory on {{ $labels.name }}"
EOF

sudo cat > /opt/prometheus/alert-rules/disk.yml << 'EOF'
groups:
- name: DiskUsage
  rules:
  - alert: DiskAlmostFull
    expr: (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Disk > 80% on {{ $labels.name }}"
EOF

# Prometheus systemd service
sudo cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus Monitoring System
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/opt/prometheus/prometheus --config.file=/opt/prometheus/prometheus.yml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

# --- Install Alertmanager ---
cd /opt
sudo wget https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz
sudo tar -xvf alertmanager-0.27.0.linux-amd64.tar.gz
sudo mv alertmanager-0.27.0.linux-amd64 alertmanager

sudo cat > /opt/alertmanager/alertmanager.yml << 'EOF'
route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'email'

receivers:
  - name: 'email'
    email_configs:
    - smarthost: 'smtp.gmail.com:587'
      auth_username: 'your-from-email@gmail.com'
      auth_password: 'your-app-password'
      from: 'your-from-email@gmail.com'
      to: 'your-to-email@gmail.com'
      headers:
        subject: 'Prometheus Alert: {{ .CommonAnnotations.summary }}'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
EOF

sudo cat > /etc/systemd/system/alertmanager.service << 'EOF'
[Unit]
Description=AlertManager System
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/opt/alertmanager/alertmanager --config.file=/opt/alertmanager/alertmanager.yml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable alertmanager
sudo systemctl start alertmanager

# --- Install Grafana ---
sudo cat > /etc/yum.repos.d/grafana.repo << 'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

sudo yum install -y grafana
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

echo "=== Monitoring Stack Installed ==="
echo "Prometheus:   http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9090"
echo "Grafana:      http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000 (admin/admin)"
echo "Alertmanager: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9093"
