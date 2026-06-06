# Look up your default VPC automatically
data "aws_vpc" "default" {
  default = true
}

# Look up compatible subnets (excluding us-east-1e)
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

# Prometheus Server Instance
resource "aws_instance" "prometheus" {
  ami                    = "ami-0220d79f3f480ecf5" 
  vpc_security_group_ids = [aws_security_group.prometheus.id]
  instance_type          = "t3.micro"
  
  # Pulls from our new filtered data source
  subnet_id              = data.aws_subnets.default.ids[0]

  user_data            = file("prometheus.sh")
  iam_instance_profile = aws_iam_instance_profile.prometheus_instance_profile.name
  
  tags = {
    Name = "prometheus"
  }
  depends_on = [aws_instance.node_exporter]
}

# Node Exporter Instance
resource "aws_instance" "node_exporter" {
  ami                    = "ami-0220d79f3f480ecf5" 
  vpc_security_group_ids = [aws_security_group.prometheus.id]
  instance_type          = "t3.micro"
  
  # Pulls from our new filtered data source
  subnet_id              = data.aws_subnets.default.ids[0]
  
  user_data              = file("node_exporter.sh")
  
  tags = {
    Name       = "node-exporter"
    Monitoring = "true"
  }
}

resource "aws_security_group" "prometheus" {
  name        = "prometheus"
  description = "Allow traffic for monitoring stack"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prometheus-sg"
  }
}
