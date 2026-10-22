# 아래 값을 GitHub 레포 Settings → Variables 에 등록한다 (Secrets 는 필요 없음).

output "AWS_ROLE_ARN_CI" {
  value = aws_iam_role.gha["ci"].arn
}

output "AWS_ROLE_ARN_DEPLOY" {
  value = aws_iam_role.gha["deploy"].arn
}

output "AWS_ROLE_ARN_INFRA" {
  value = aws_iam_role.gha["infra"].arn
}

output "ECR_REPOSITORY" {
  value = aws_ecr_repository.app.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "TF_STATE_BUCKET" {
  value = aws_s3_bucket.state.bucket
}
