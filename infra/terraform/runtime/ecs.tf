# 색별 ECS 서비스 2개(pda-blue / pda-green)가 태스크 정의 family 하나(pda-coupon-api)를 공유한다.
# deployment controller 는 ECS(rolling). ECS 내장 blue/green·CodeDeploy 는 쓰지 않는다:
# 전환 로직이 GitHub Actions 파이프라인 코드에 그대로 드러나야 하기 때문.
#
# 종료 시간 정합성 (다운타임 0 조건)
#   1. 리스너 weight 0          → 새 요청이 오지 않음
#   2. desired 0 → TG 등록 해제  → deregistration_delay 30s 동안 진행 중 요청 drain
#   3. SIGTERM                  → Spring graceful shutdown 최대 20s
#   4. stopTimeout 30s          → 넘으면 SIGKILL
#   조건: stopTimeout(30) > graceful(20), deregistration_delay(30) ≥ 가장 긴 요청 + 여유

data "aws_ecr_repository" "app" {
  name = "${local.p}-coupon-api"
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.p}-coupon-api"
  retention_in_days = 3
}

resource "aws_ecs_cluster" "main" {
  name = "${local.p}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # 비용 절감. 판정은 ALB 지표로 한다
  }
}

# Spot 은 중단 위험이 있어 시연 재현성을 해치므로 FARGATE 만 사용
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.p}-coupon-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  # Apple Silicon / ubuntu-24.04-arm 러너에서 빌드한 arm64 이미지와 일치. Graviton 은 x86 대비 약 20% 저렴
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${data.aws_ecr_repository.app.repository_url}:${var.initial_image_tag}"
      essential = true
      portMappings = [
        { containerPort = 8080, protocol = "tcp" }
      ]
      environment = [
        { name = "FAULT_RATE", value = "0" }
      ]
      stopTimeout = 30
      # 컨테이너 healthCheck 없음: 이미지에 curl 이 없고, ALB 대상 그룹 헬스체크를 사용한다
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "app"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "color" {
  for_each = { blue = 1, green = 0 }

  name            = "${local.p}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = each.value
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true # NAT 없이 ECR/Logs 에 접근 (network.tf 참고)
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.color[each.key].arn
    container_name   = "app"
    container_port   = 8080
  }

  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  wait_for_steady_state = false

  # 이미지(task_definition)와 태스크 수(desired_count)는 워크플로우가 소유한다.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}
