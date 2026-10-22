#!/usr/bin/env bash
# blue-green.sh / canary.sh 공용 배포 단계. source 해서 사용한다.
# AWS 대응: deploy_candidate ↔ scripts/aws/deploy-candidate.sh, smoke ↔ smoke-test.sh

# 후보 색 컨테이너를 새 이미지로 재생성한다. 후보는 가중치 0(down) 상태라 사용자 트래픽이 가지 않는다.
deploy_candidate() {
	local color="$1" tag="$2" fault_rate="${3:-0}" fault_delay="${4:-0}" upper
	upper="$(color_upper "${color}")"
	docker image inspect "coupon-api:${tag}" >/dev/null 2>&1 || {
		log "image coupon-api:${tag} not found (scripts/local/build-image.sh ${tag})"
		return 2
	}
	if [[ "$(weight_of "${color}")" != "0" ]]; then
		log "candidate ${color} still receives traffic (weight $(weight_of "${color}")), refusing to redeploy"
		return 2
	fi
	env_set "${upper}_TAG" "${tag}"
	env_set "${upper}_FAULT_RATE" "${fault_rate}"
	env_set "${upper}_FAULT_DELAY_MS" "${fault_delay}"
	log "deploy ${color} ← coupon-api:${tag} (FAULT_RATE=${fault_rate}, FAULT_DELAY_MS=${fault_delay})"
	compose up -d --no-deps --force-recreate "${color}" >/dev/null 2>&1
	wait_ready "${color}" 90
}

# 헤더 라우팅으로 후보 색만 직접 호출해 검증한다 (ALB 리스너 규칙 X-Target-Color 와 동일)
smoke() {
	local color="$1" expect="$2" version header attempt
	curl -sf -o /dev/null -H "X-Target-Color: ${color}" "${BASE_URL}/health/readiness" || {
		log "smoke: readiness failed"; return 1
	}
	version="$(curl -sf -H "X-Target-Color: ${color}" "${BASE_URL}/version" | jq -r .version)"
	[[ "${version}" == "${expect}" ]] || { log "smoke: /version=${version}, expected ${expect}"; return 1; }
	for attempt in 1 2 3; do
		header="$(curl -s -o /dev/null -w '%{http_code} %header{x-app-version}' -X POST \
			-H "X-Target-Color: ${color}" -H 'Content-Type: application/json' \
			-d '{"userId":"smoke","orderAmount":25000}' "${BASE_URL}/coupons/issue")"
		if [[ "${header}" == "201 ${expect}" ]]; then
			log "smoke: ${color} OK (${expect})"
			return 0
		fi
		log "smoke: POST attempt ${attempt} → ${header}"
	done
	return 1
}

LOAD_PID=""
start_load() {
	local out="$1" rps="${2:-50}"
	"${SCRIPTS_DIR}/load/load.sh" --target "${BASE_URL}" --duration 3600 --concurrency 4 --rps "${rps}" --out "${out}" 2>/dev/null &
	LOAD_PID=$!
	log "load started (rps≈${rps}) → ${out}"
}

stop_load() {
	if [[ -n "${LOAD_PID}" ]]; then
		pkill -TERM -P "${LOAD_PID}" 2>/dev/null || true
		kill -TERM "${LOAD_PID}" 2>/dev/null || true
		wait "${LOAD_PID}" 2>/dev/null || true
		LOAD_PID=""
	fi
}

# 부하 CSV 에서 시각 t 이후 마지막으로 후보 버전이 응답한 시각 (사용자 영향 종료 시각)
last_response_of() {
	local csv="$1" version="$2" since="$3"
	awk -F, -v v="${version}" -v s="${since}" 'NR > 1 && $3 == v && $1 >= s && $1 > m { m = $1 } END { print m + 0 }' "${csv}"
}
