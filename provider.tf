terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.84.0"
    }
  }

backend "s3" {
bucket         = "shivakrishna-tf-state-dev"
key            = "dev/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "vosukula-state-locking"
  }
}

provider "aws" {
  # Configuration options
  region = "us-east-1"
}