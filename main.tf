# =============================================================================
# Monitoring Stack — Prometheus + Grafana + Alertmanager + Node Exporter
# Launches 2 EC2 instances: 1 for monitoring server, 1 as a target to monitor
# =============================================================================

# Default VPC
data "aws_vpc" "default" {
  default = true
}

# Subnets (exclude us-east-1e which doesn't support t3)
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  }
}

# Latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# =============================================================================
# SSH Key Pair
# =============================================================================
resource "aws_key_pair" "monitoring" {
  key_name   = "my-new-key"
  public_key = file("C:/Devops/my-new-key.pub")
}

# =============================================================================
# Security Group — Allow Prometheus, Grafana, Node Exporter, SSH
# =============================================================================
resource "aws_security_group" "prometheus" {
  name        = "prometheus-monitoring"
  description = "Allow monitoring stack traffic"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Alertmanager"
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Node Exporter"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prometheus-monitoring-sg"
  }
}

# =============================================================================
# Node Exporter Instance (target to monitor)
# =============================================================================
resource "aws_instance" "node_exporter" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.prometheus.id]
  key_name               = aws_key_pair.monitoring.key_name
  user_data              = file("node_exporter.sh")

  tags = {
    Name       = "node-exporter-target"
    Monitoring = "true"
  }
}

# =============================================================================
# Prometheus Server (Prometheus + Grafana + Alertmanager)
# =============================================================================
resource "aws_instance" "prometheus" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.prometheus.id]
  key_name               = aws_key_pair.monitoring.key_name
  user_data              = file("prometheus.sh")
  iam_instance_profile   = aws_iam_instance_profile.prometheus_instance_profile.name

  tags = {
    Name = "prometheus-server"
  }

  depends_on = [aws_instance.node_exporter]
}
