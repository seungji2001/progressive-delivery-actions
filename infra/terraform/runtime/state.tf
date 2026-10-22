# 활성 색 상태 저장
#   - ALB 리스너 가중치 = 실제 트래픽 상태 (진실 원천)
#   - SSM /pda/stable-color = 마지막으로 승격을 마친 색 (커밋 포인터, 성공의 마지막 단계에서만 갱신)
# 정상 상태: stable 색 100 / 다른 색 0 이고 두 값이 일치.
# 어긋나면 이전 배포가 중단된 것 → 4·5단계 워크플로우가 배포를 거부하거나 recover 한다.

resource "aws_ssm_parameter" "stable_color" {
  name  = "/${local.p}/stable-color"
  type  = "String"
  tier  = "Standard" # 무료
  value = "blue"

  lifecycle {
    ignore_changes = [value]
  }
}
