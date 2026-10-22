terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # 최초 apply 는 이 블록을 주석 처리한 채 로컬 state 로 한다 (state 버킷이 아직 없음).
  # 이후 `terraform init -migrate-state -backend-config=...` 로 S3 의 bootstrap/terraform.tfstate 로 이전했다.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "progressive-delivery-actions"
      Stack     = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
