#!/usr/bin/env bash
# 후보 색 서비스에 새 이미지를 배포하고 ALB 대상 그룹에서 healthy 가 될 때까지 기다린다.
# 후보 색의 리스너 가중치가 0 일 때만 실행한다 (사용자 트래픽이 가지 않는 상태).
set -euo pipefail
# shellcheck source=scripts/aws/common.sh
source "$(dirname "$0")/common.sh"

usage() {
	cat <<'EOF'
Usage: deploy-candidate.sh --color <blue|green> --image-tag <tag> [--env KEY=VALUE ...]
  --env 는 후보 태스크에만 주입된다 (예: --env FAULT_RATE=0.3). 지정하지 않은 FAULT_* 는 0 으로 초기화.
Outputs: task_definition, stabilize_seconds
EOF
}

color="" tag="" envs=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		--color) color="$2"; shift 2 ;;
		--image-tag) tag="$2"; shift 2 ;;
		--env) envs+=("$2"); shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done
[[ "${color}" == blue || "${color}" == green ]] || { usage >&2; exit 2; }
[[ -n "${tag}" ]] || { usage >&2; exit 2; }

# 1) 이미지 존재 확인 (IMMUTABLE ECR: 태그 = 고정된 이미지)
aws ecr describe-images --repository-name "${ECR_REPOSITORY}" --image-ids "imageTag=${tag}" >/dev/null || {
	log "image ${ECR_REPOSITORY}:${tag} not found in ECR"
	exit 2
}

# 2) 후보 가중치 0 확인
weight="$("$(dirname "$0")/traffic-state.sh" 2>/dev/null | grep "^${color}_weight=" | cut -d= -f2)"
if [[ "${weight}" != 0 ]]; then
	log "candidate ${color} has weight ${weight}, refusing to deploy"
	exit 2
fi

# 3) 최신 태스크 정의를 바탕으로 이미지·환경변수만 바꾼 새 revision 등록
env_json="$(printf '%s\n' "FAULT_RATE=0" "FAULT_DELAY_MS=0" "${envs[@]+"${envs[@]}"}" |
	jq -Rn '[inputs | select(length > 0) | capture("^(?<name>[^=]+)=(?<value>.*)$")] | reduce .[] as $e ({}; .[$e.name] = $e.value) | to_entries | map({name: .key, value: .value})')"

current="$(aws ecs describe-task-definition --task-definition "${TASK_FAMILY}" --query taskDefinition --output json)"
image="$(jq -r '.containerDefinitions[0].image | sub(":[^:]+$"; "")' <<<"${current}"):${tag}"

new_def="$(jq --arg image "${image}" --argjson env "${env_json}" '
	del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities,
		.registeredAt, .registeredBy, .deregisteredAt)
	| .containerDefinitions[0].image = $image
	| .containerDefinitions[0].environment = $env' <<<"${current}")"

td_arn="$(aws ecs register-task-definition --cli-input-json "${new_def}" \
	--query 'taskDefinition.taskDefinitionArn' --output text)"
log "registered ${td_arn} (${image})"
emit task_definition "${td_arn}"

# 4) 후보 서비스 업데이트 → 안정화 대기
start="$(date +%s)"
aws ecs update-service --cluster "${CLUSTER}" --service "$(service_of "${color}")" \
	--task-definition "${td_arn}" --desired-count 1 >/dev/null
log "waiting for $(service_of "${color}") to become stable"
aws ecs wait services-stable --cluster "${CLUSTER}" --services "$(service_of "${color}")"

# 5) ALB 대상 그룹 healthy 확인 (서비스 안정화와 TG 헬스체크는 별개)
tg="$(tg_arn "${color}")"
for _ in $(seq 1 30); do
	# shellcheck disable=SC2016 # JMESPath 리터럴 백틱
	healthy="$(aws elbv2 describe-target-health --target-group-arn "${tg}" \
		--query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text)"
	((healthy >= 1)) && break
	sleep 5
done
((healthy >= 1)) || { log "no healthy target in ${NAME_PREFIX}-${color}"; exit 1; }

emit stabilize_seconds "$(($(date +%s) - start))"
log "${color} ready with ${tag}"
