# 1. IAM Policy for Prometheus EC2 to Describe Instances
resource "aws_iam_policy" "prometheus_ec2_describe_policy" {
  name        = "PrometheusEC2DescribePolicy"
  description = "Allows Prometheus EC2 to describe instances to discover scrape targets"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeNetworkInterfaces"
        ],
        Resource = "*"
      }
    ]
  })
}

# 2. IAM Role for Prometheus EC2
resource "aws_iam_role" "prometheus_ec2_role" {
  name = "PrometheusEC2Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# 3. Attach the policy to the role
resource "aws_iam_role_policy_attachment" "prometheus_attach_policy" {
  role       = aws_iam_role.prometheus_ec2_role.name
  policy_arn = aws_iam_policy.prometheus_ec2_describe_policy.arn
}

# 4. IAM Instance Profile
resource "aws_iam_instance_profile" "prometheus_instance_profile" {
  name = "PrometheusInstanceProfile"
  role = aws_iam_role.prometheus_ec2_role.name
}