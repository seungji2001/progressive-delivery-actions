# GitHub Actions → AWS 인증은 OIDC 만 사용한다 (장기 Access Key 없음).
#
# 신뢰 정책의 sub 형식 주의:
#   - job 에 environment 가 없으면  <prefix>:ref:refs/heads/main
#   - job 에 environment 가 있으면  <prefix>:environment:<name>
#   - <prefix> 는 레포 설정에 따라 이름 기반(repo:<owner>/<repo>) 또는
#     immutable 형식(repo:<owner>@<owner_id>/<repo>@<repo_id>). immutable 형식은 레포 이름을
#     재사용(삭제 후 재생성·이름 변경)하는 공격으로 Role 을 가로챌 수 없어 더 안전하다.
# pull_request 이벤트(repo:<owner>/<repo>:pull_request)에는 어떤 Role 도 허용하지 않는다.
#
# runtime 스택은 시연 후 destroy/재생성되므로 ARN 이 바뀐다. 권한은 이름 기반 ARN 패턴으로 지정해
# runtime 을 다시 만들어도 이 정책을 고칠 필요가 없게 한다.

locals {
  account_id = data.aws_caller_identity.current.account_id
  sub_prefix = var.github_oidc_sub_prefix != "" ? var.github_oidc_sub_prefix : "repo:${var.github_owner}/${var.github_repo}"
  p          = var.name_prefix
  region     = var.aws_region
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

data "aws_iam_policy_document" "trust" {
  for_each = {
    ci     = ["${local.sub_prefix}:ref:refs/heads/main", "${local.sub_prefix}:ref:refs/tags/v*"]
    deploy = ["${local.sub_prefix}:environment:preview", "${local.sub_prefix}:environment:production"]
    infra  = ["${local.sub_prefix}:environment:infra"]
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

resource "aws_iam_role" "gha" {
  for_each = data.aws_iam_policy_document.trust

  name                 = "${local.p}-gha-${each.key}"
  assume_role_policy   = each.value.json
  max_session_duration = 3600
}

# ---------------------------------------------------------------------------
# ci: 이미지 push 만
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ci" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # 리소스 수준 권한 미지원
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "ci" {
  name   = "ecr-push"
  role   = aws_iam_role.gha["ci"].id
  policy = data.aws_iam_policy_document.ci.json
}

# ---------------------------------------------------------------------------
# deploy: 후보 배포 + 리스너 가중치 전환 + 지표 조회 + 상태 포인터
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "deploy" {
  statement {
    sid = "EcsTaskDefinition"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"] # 리소스 수준 권한 미지원
  }

  statement {
    sid = "EcsServices"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
    ]
    resources = ["arn:aws:ecs:${local.region}:${local.account_id}:service/${local.p}-cluster/${local.p}-*"]
  }

  statement {
    sid = "EcsTasks"
    actions = [
      "ecs:DescribeTasks",
      "ecs:ListTasks",
    ]
    resources = ["*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = ["arn:aws:ecs:${local.region}:${local.account_id}:cluster/${local.p}-cluster"]
    }
  }

  statement {
    sid       = "ElbRead"
    actions   = ["elasticloadbalancing:Describe*"]
    resources = ["*"] # Describe 는 리소스 수준 권한 미지원
  }

  statement {
    sid       = "ElbShiftTraffic"
    actions   = ["elasticloadbalancing:ModifyListener"]
    resources = ["arn:aws:elasticloadbalancing:${local.region}:${local.account_id}:listener/app/${local.p}-alb/*"]
  }

  statement {
    sid = "Metrics"
    actions = [
      "cloudwatch:DescribeAlarms",
      "cloudwatch:GetMetricData",
    ]
    resources = ["*"]
  }

  statement {
    sid = "TrafficStatePointer"
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter",
    ]
    resources = ["arn:aws:ssm:${local.region}:${local.account_id}:parameter/${local.p}/stable-color"]
  }

  statement {
    sid       = "EcrVerifyImage"
    actions   = ["ecr:DescribeImages"]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.p}-ecs-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "progressive-delivery"
  role   = aws_iam_role.gha["deploy"].id
  policy = data.aws_iam_policy_document.deploy.json
}

# ---------------------------------------------------------------------------
# infra: runtime 스택 apply/destroy. 범위가 넓은 대신 environment `infra` 의 수동 승인으로 보완한다.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "infra" {
  statement {
    sid = "RuntimeServices"
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "ecs:*",
      "logs:*",
      "cloudwatch:*",
      "ssm:*",
      "tag:GetResources",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  statement {
    sid = "EcrRead"
    # runtime 의 data "aws_ecr_repository" 는 태그도 읽는다 (ListTagsForResource) — 실제 destroy 실행에서 발견
    actions   = ["ecr:DescribeRepositories", "ecr:DescribeImages", "ecr:ListTagsForResource"]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    # 권한 상승 방지: 이 Role 은 pda-ecs-* Role 을 만들 수 있으므로, 붙일 수 있는 정책과
    # 인라인 정책 작성을 막지 않으면 "관리자 정책을 붙인 Role 을 만들어 태스크로 실행" 경로가 생긴다.
    # → 인라인 정책 작성(PutRolePolicy) 은 허용하지 않고, 관리형 정책은 ECS 실행 정책 하나만 붙일 수 있다.
    sid = "TaskRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRolePolicies",
      "iam:TagRole",
      "iam:UntagRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.p}-ecs-*"]
  }

  statement {
    sid       = "TaskRolePolicyAttachOnlyEcsExecution"
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.p}-ecs-*"]

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
    }
  }

  statement {
    sid       = "PassTaskRolesToEcsOnly"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.p}-ecs-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "ElbServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com", "ecs.amazonaws.com"]
    }
  }

  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid = "RuntimeState"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [
      "${aws_s3_bucket.state.arn}/runtime/terraform.tfstate",
      "${aws_s3_bucket.state.arn}/runtime/terraform.tfstate.tflock",
    ]
  }
}

resource "aws_iam_role_policy" "infra" {
  name   = "runtime-stack"
  role   = aws_iam_role.gha["infra"].id
  policy = data.aws_iam_policy_document.infra.json
}
