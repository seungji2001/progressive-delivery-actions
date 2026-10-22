variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "name_prefix" {
  description = "리소스 이름 prefix. 워크플로우가 이름으로 리소스를 조회하므로 runtime 스택과 같아야 한다."
  type        = string
  default     = "pda"
}

variable "github_owner" {
  description = "GitHub 사용자 또는 조직 이름"
  type        = string
}

variable "github_repo" {
  type    = string
  default = "progressive-delivery-actions"
}

variable "state_bucket_name" {
  description = "Terraform state S3 버킷 이름 (전역 유일)"
  type        = string
}

variable "create_oidc_provider" {
  description = "계정에 GitHub OIDC provider 가 이미 있으면 false (계정당 1개만 존재 가능)"
  type        = bool
  default     = true
}

variable "monthly_budget_usd" {
  type    = number
  default = 10
}

variable "budget_alert_email" {
  type = string
}
