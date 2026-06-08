terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Using local state — AWS Academy Learner Lab does not support S3 backend
  # Do NOT commit terraform.tfstate to git
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "SecureGate"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
