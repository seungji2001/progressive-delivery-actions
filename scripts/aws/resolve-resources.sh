#!/usr/bin/env bash
# 이름 규약으로 ALB / 리스너 / TG / ECS 리소스를 조회해 KEY=VALUE 로 출력한다.
set -euo pipefail
# shellcheck source=scripts/aws/common.sh
source "$(dirname "$0")/common.sh"

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { echo "Usage: resolve-resources.sh"; exit 0; }

lb_json="$(aws elbv2 describe-load-balancers --names "${ALB_NAME}" --query 'LoadBalancers[0]' --output json)"
lb_arn="$(jq -r .LoadBalancerArn <<<"${lb_json}")"

emit alb_dns "$(jq -r .DNSName <<<"${lb_json}")"
emit lb_suffix "${lb_arn#*:loadbalancer/}"
emit listener_arn "$(listener_arn)"

for color in blue green; do
	arn="$(tg_arn "${color}")"
	emit "tg_${color}_arn" "${arn}"
	emit "tg_${color}_suffix" "${arn##*:}"
done

emit cluster "${CLUSTER}"
emit service_blue "$(service_of blue)"
emit service_green "$(service_of green)"
