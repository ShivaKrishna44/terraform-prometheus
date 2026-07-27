# =============================================================================
# IAM Role for Prometheus EC2 instance
# Needed for EC2 service discovery (ec2_sd_configs)
# =============================================================================

resource "aws_iam_role" "prometheus" {
  name = "prometheus-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "prometheus_ec2_discovery" {
  name = "ec2-read-access"
  role = aws_iam_role.prometheus.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances",
        "ec2:DescribeTags"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "prometheus_instance_profile" {
  name = "prometheus-instance-profile"
  role = aws_iam_role.prometheus.name
}
