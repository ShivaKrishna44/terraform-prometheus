output "prometheus_public_ip" {
  value = aws_instance.prometheus.public_ip
}

output "node_exporter_public_ip" {
  value = aws_instance.node_exporter.public_ip
}

output "prometheus_url" {
  value = "http://${aws_instance.prometheus.public_ip}:9090"
}

output "grafana_url" {
  value = "http://${aws_instance.prometheus.public_ip}:3000"
}

output "alertmanager_url" {
  value = "http://${aws_instance.prometheus.public_ip}:9093"
}
