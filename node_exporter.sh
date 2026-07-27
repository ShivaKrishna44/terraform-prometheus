#!/bin/bash
set -e

# Update system
sudo yum update -y
sudo yum install -y wget tar

# --- Install Node Exporter ---
cd /opt
sudo wget https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz
sudo tar -xvf node_exporter-1.8.1.linux-amd64.tar.gz
sudo mv node_exporter-1.8.1.linux-amd64 node_exporter

# Systemd service (matches your working prometheus repo)
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

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

echo "=== Node Exporter installed ==="
echo "Metrics at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9100/metrics"
