#!/usr/bin/env bash
# ALB 리스너 가중치를 직접 바꾼다 (트래픽 전환의 유일한 지점). 반영을 검증한 뒤 시각(epoch ms)을 출력한다.
set -euo pipefail
# shellcheck source=scripts/aws/common.sh
source "$(dirname "$0")/common.sh"

usage() {
	cat <<'EOF'
Usage: set-weights.sh --blue <0-100> --green <0-100>
Exit: 0 성공 / 1 반영 검증 실패 / 2 사용법 오류
EOF
}

blue="" green=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--blue) blue="$2"; shift 2 ;;
		--green) green="$2"; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done
[[ "${blue}" =~ ^[0-9]+$ && "${green}" =~ ^[0-9]+$ ]] || { usage >&2; exit 2; }
((blue + green == 100)) || { echo "blue + green must be 100" >&2; exit 2; }

listener="$(listener_arn)"
blue_arn="$(tg_arn blue)"
green_arn="$(tg_arn green)"

actions="$(jq -nc --arg b "${blue_arn}" --arg g "${green_arn}" --argjson bw "${blue}" --argjson gw "${green}" '[{
	Type: "forward",
	ForwardConfig: {
		TargetGroups: [{TargetGroupArn: $b, Weight: $bw}, {TargetGroupArn: $g, Weight: $gw}],
		TargetGroupStickinessConfig: {Enabled: false}
	}
}]')"

aws elbv2 modify-listener --listener-arn "${listener}" --default-actions "${actions}" >/dev/null

applied="$(aws elbv2 describe-listeners --listener-arns "${listener}" \
	--query 'Listeners[0].DefaultActions[0].ForwardConfig.TargetGroups' --output json |
	jq -r --arg b "${blue_arn}" --arg g "${green_arn}" \
		'"\(map(select(.TargetGroupArn == $b))[0].Weight) \(map(select(.TargetGroupArn == $g))[0].Weight)"')"

if [[ "${applied}" != "${blue} ${green}" ]]; then
	log "verify failed: expected '${blue} ${green}', got '${applied}'"
	exit 1
fi

log "listener weights: blue=${blue} green=${green}"
now_ms
