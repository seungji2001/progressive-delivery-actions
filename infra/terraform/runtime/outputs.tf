# 워크플로우는 이 출력을 저장하지 않고 이름(pda-*)으로 매번 조회한다. 아래는 사람이 확인하는 용도.

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "listener_arn" {
  value = aws_lb_listener.http.arn
}

output "target_groups" {
  value = {
    for color, tg in aws_lb_target_group.color : color => {
      arn        = tg.arn
      arn_suffix = tg.arn_suffix
    }
  }
}

output "load_balancer_arn_suffix" {
  value = aws_lb.main.arn_suffix
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "service_names" {
  value = { for color, svc in aws_ecs_service.color : color => svc.name }
}

output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}
