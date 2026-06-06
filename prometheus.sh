#!/bin/bash

PROM_VERSION=3.4.0
ALERT_MANGER_VERSION=0.28.1
cd /opt
wget https://github.com/prometheus/prometheus/releases/download/v$PROM_VERSION/prometheus-$PROM_VERSION.linux-amd64.tar.gz
tar -xf  prometheus-$PROM_VERSION.linux-amd64.tar.gz
mv prometheus-$PROM_VERSION.linux-amd64 prometheus

wget https://github.com/prometheus/alertmanager/releases/download/v$ALERT_MANGER_VERSION/alertmanager-$ALERT_MANGER_VERSION.linux-amd64.tar.gz
tar -xf alertmanager-$ALERT_MANGER_VERSION.linux-amd64.tar.gz
mv alertmanager-$ALERT_MANGER_VERSION.linux-amd64 alertmanager

cd /tmp
git clone https://github.com/DAWS-82S/terraform-prometheus.git
cd terraform-prometheus
cp prometheus.service /etc/systemd/system/prometheus.service
cp alertmanager.service  /etc/systemd/system/alertmanager.service

rm -rf /opt/prometheus/prometheus.yml
rm -rf /opt/alertmanager/alertmanager.yml
cp prometheus.yml /opt/prometheus/prometheus.yml
cp alertmanager.yml /opt/alertmanager/alertmanager.yml
cp -r alert-rules /opt/prometheus/

systemctl start alertmanager
systemctl enable alertmanager
if ! systemctl is-active --quiet "alertmanager"; then
  echo "ERROR: alertmanager is not running!"
  exit 1
else
  echo "alertmanager is running."
fi

systemctl start prometheus
systemctl enable prometheus
if ! systemctl is-active --quiet "prometheus"; then
  echo "ERROR: prometheus is not running!"
  exit 1
else
  echo "prometheus is running."
fi

curl -o gpg.key https://rpm.grafana.com/gpg.key
rpm --import gpg.key
cp grafana.repo /etc/yum.repos.d/grafana.repo

dnf install grafana -y

cp prometheus-ds.yml /etc/grafana/provisioning/datasources/prometheus.yaml
chown root:grafana /etc/grafana/provisioning/datasources/prometheus.yaml
chmod 640 /etc/grafana/provisioning/datasources/prometheus.yaml

systemctl daemon-reload
systemctl start grafana-server
systemctl enable grafana-server


