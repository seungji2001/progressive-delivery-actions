# ALB weighted target group: 트래픽 전환은 GitHub Actions 가 리스너 가중치를 직접 바꿔서 한다.

# 인터넷 공개 ALB 는 데모의 목적 그대로다 (GitHub 호스티드 러너가 스모크/부하를 보낸다).
#trivy:ignore:AWS-0053
resource "aws_lb" "main" {
  name               = "${local.p}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  idle_timeout       = 60

  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "color" {
  for_each = toset(["blue", "green"])

  name        = "${local.p}-${each.key}"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate awsvpc
  protocol    = "HTTP"
  port        = 8080

  # 기본 300s 는 배포를 느리게 만든다. 앱 graceful shutdown(20s) 보다 길게, ECS stopTimeout(30s) 과 맞춘다.
  deregistration_delay = 30
  slow_start           = 0

  health_check {
    path                = "/health/readiness"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  stickiness {
    type    = "lb_cookie"
    enabled = false
  }
}

# HTTPS 는 도메인·ACM 이 필요해 범위 밖이다 (README "알려진 한계"). 민감 데이터를 다루지 않는다.
#trivy:ignore:AWS-0054
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.color["blue"].arn
        weight = 100
      }

      target_group {
        arn    = aws_lb_target_group.color["green"].arn
        weight = 0
      }

      stickiness {
        enabled  = false
        duration = 1
      }
    }
  }

  # 가중치는 워크플로우(scripts/aws/set-weights.sh)가 소유한다.
  # 이 설정이 없으면 다음 terraform plan/apply 가 트래픽을 초기값으로 되돌린다.
  lifecycle {
    ignore_changes = [default_action]
  }
}

# 스모크 테스트용 색 지정 라우팅 (로컬 nginx 의 X-Target-Color 와 같은 규격).
# 누구나 헤더로 비활성 색을 호출할 수 있다는 점은 데모 범위에서 허용하는 위험이다 (README).
resource "aws_lb_listener_rule" "target_color" {
  for_each = { blue = 10, green = 11 }

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.color[each.key].arn
  }

  condition {
    http_header {
      http_header_name = "X-Target-Color"
      values           = [each.key]
    }
  }
}
