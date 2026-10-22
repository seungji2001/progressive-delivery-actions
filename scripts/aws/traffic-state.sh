#!/usr/bin/env bash
# 현재 트래픽 상태를 읽는다.
#   - 리스너 가중치 = 실제 트래픽 상태 (진실 원천)
#   - SSM /pda/stable-color = 마지막 승격 완료 색 (커밋 포인터)
# 정상: stable 색 100 / 다른 색 0 이고 SSM 과 일치 → consistent=true
# 그 외(가중치가 섞여 있거나 SSM 과 불일치)는 이전 배포가 중단된 상태 → 호출 측은 배포를 거부한다.
set -euo pipefail
# shellcheck source=scripts/aws/common.sh
source "$(dirname "$0")/common.sh"

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { echo "Usage: traffic-state.sh"; exit 0; }

listener="$(listener_arn)"
groups="$(aws elbv2 describe-listeners --listener-arns "${listener}" \
	--query 'Listeners[0].DefaultActions[0].ForwardConfig.TargetGroups' --output json)"

weight_of() {
	local arn
	arn="$(tg_arn "$1")"
	jq -r --arg arn "${arn}" '(map(select(.TargetGroupArn == $arn))[0].Weight) // 0' <<<"${groups}"
}

blue_weight="$(weight_of blue)"
green_weight="$(weight_of green)"
pointer="$(aws ssm get-parameter --name "${STATE_PARAM}" --query 'Parameter.Value' --output text)"

consistent=false
if [[ "${pointer}" == blue && "${blue_weight}" == 100 && "${green_weight}" == 0 ]] ||
	[[ "${pointer}" == green && "${green_weight}" == 100 && "${blue_weight}" == 0 ]]; then
	consistent=true
fi

emit blue_weight "${blue_weight}"
emit green_weight "${green_weight}"
emit stable_color "${pointer}"
emit candidate_color "$(other_color "${pointer}")"
emit consistent "${consistent}"

if [[ "${consistent}" != true ]]; then
	log "traffic state inconsistent: blue=${blue_weight} green=${green_weight} pointer=${pointer}"
	log "→ 이전 배포가 중단된 상태. canary.yml mode=recover 로 stable 색 100% 로 복구한다."
fi
