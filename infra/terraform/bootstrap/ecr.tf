# 이미지는 runtime 을 destroy 해도 남아야 하므로 bootstrap 에 둔다.
# IMMUTABLE: 같은 태그 = 같은 이미지. 롤백 대상 이미지가 바뀌지 않음을 보장한다.

resource "aws_ecr_repository" "app" {
  name                 = "${var.name_prefix}-coupon-api"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true # 기본 스캔 (무료). CI 에서는 Trivy 로 별도 차단
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "untagged 이미지는 1일 후 삭제"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "릴리즈 태그는 최근 10개 유지"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["v*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 3
        description  = "main 빌드(sha-*)는 최근 10개 유지"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["sha-*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}
