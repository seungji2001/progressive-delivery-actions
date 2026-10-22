variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "name_prefix" {
  description = "4·5단계 워크플로우가 이 이름으로 리소스를 조회한다. 변경 금지."
  type        = string
  default     = "pda"
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "allowed_ingress_cidrs" {
  description = "ALB :80 접근 허용 대역. GitHub 호스티드 러너가 스모크/부하를 보내야 하므로 좁히기 어렵다."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "initial_image_tag" {
  description = "최초 apply 시 blue 서비스가 띄울 이미지 태그. ECR 에 미리 push 되어 있어야 한다."
  type        = string
  default     = "v1.0.0"
}

variable "task_cpu" {
  description = "JVM 기동 시간을 고려한 값. 1단계 측정(로컬 readiness 약 4s)을 기준으로 조정한다."
  type        = number
  default     = 512
}

variable "task_memory" {
  type    = number
  default = 1024
}

variable "alarm_5xx_threshold" {
  description = "색별 TG 1분당 5xx 개수 알람 임계값 (관찰용. 판정은 5단계 metric-gate.sh)"
  type        = number
  default     = 5
}

variable "alarm_p95_seconds" {
  type    = number
  default = 0.5
}
