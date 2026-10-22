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

variable "github_oidc_sub_prefix" {
  description = <<-EOT
    OIDC 토큰 sub 의 prefix. 최근 생성된 레포는 GitHub 의 immutable subject 형식을 쓴다:
      repo:<owner>@<owner_id>/<repo>@<repo_id>
    확인: gh api repos/<owner>/<repo>/actions/oidc/customization/sub → sub_claim_prefix
    비워 두면 이름 기반 형식(repo:<owner>/<repo>)을 쓴다.
  EOT
  type        = string
  default     = ""
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
