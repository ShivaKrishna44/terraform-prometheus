#!/bin/bash
VERSION=1.9.1

echo "directory: $(pwd)"
cd /opt/
wget https://github.com/prometheus/node_exporter/releases/download/v$VERSION/node_exporter-$VERSION.linux-amd64.tar.gz
tar -xzf node_exporter-$VERSION.linux-amd64.tar.gz
mv node_exporter-$VERSION.linux-amd64 node_exporter

cd /tmp
git clone https://github.com/DAWS-82S/terraform-prometheus.git
cd terraform-prometheus
cp node_exporter.service /etc/systemd/system/node_exporter.service

systemctl daemon-reload
systemctl start node_exporter
systemctl enable node_exporter

if ! systemctl is-active --quiet "node_exporter"; then
  echo "ERROR: node_exporter is not running!"
  exit 1
else
  echo "node_exporter is running."
fi