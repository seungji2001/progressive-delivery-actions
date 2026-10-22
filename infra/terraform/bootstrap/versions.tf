terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # 최초 apply 는 로컬 state 로 한다 (state 버킷이 아직 없음).
  # 이후 README 절차대로 backend "s3" 를 켜고 `terraform init -migrate-state` 로 이전한다.
  # backend "s3" {}
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
