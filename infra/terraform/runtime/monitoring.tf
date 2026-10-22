# ALB 지표는 60초 해상도이고 수집 지연이 1~2분 있다 → 5단계 게이트의 관찰 창 산정 근거.
# 알람은 관찰·4단계 관찰 구간 보조 판정용이며 SNS 액션은 붙이지 않는다
# (롤백 판정은 워크플로우 코드에 드러나야 한다).

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  for_each = aws_lb_target_group.color

  alarm_name          = "${local.p}-${each.key}-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.alarm_5xx_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching" # 5xx 가 0 이면 데이터 포인트 자체가 없다

  dimensions = {
    TargetGroup  = each.value.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "target_p95" {
  for_each = aws_lb_target_group.color

  alarm_name          = "${local.p}-${each.key}-p95"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.alarm_p95_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = each.value.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name          = "${local.p}-alb-elb-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

# 5·6단계 증거 스크린샷용 대시보드 (무료 3개 범위)
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.p}-progressive-delivery"

  dashboard_body = jsonencode({
    widgets = [
      for i, m in [
        { title = "RequestCount by color", metric = "RequestCount", stat = "Sum" },
        { title = "Target 5xx by color", metric = "HTTPCode_Target_5XX_Count", stat = "Sum" },
        { title = "TargetResponseTime p95 by color", metric = "TargetResponseTime", stat = "p95" },
        { title = "HealthyHostCount by color", metric = "HealthyHostCount", stat = "Maximum" },
        ] : {
        type   = "metric"
        x      = (i % 2) * 12
        y      = floor(i / 2) * 6
        width  = 12
        height = 6
        properties = {
          title  = m.title
          region = var.aws_region
          period = 60
          stat   = m.stat
          view   = "timeSeries"
          metrics = [
            for color, tg in aws_lb_target_group.color : [
              "AWS/ApplicationELB", m.metric, "TargetGroup", tg.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix,
              { label = color, color = color == "blue" ? "#3b82f6" : "#10b981" }
            ]
          ]
        }
      }
    ]
  })
}
