#!/usr/bin/env bash
# scripts/local/*.sh 공용 함수. source 해서 사용한다.

LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../infra/local" && pwd)"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_FILE="${LOCAL_DIR}/nginx/upstreams/app_weighted.conf"
ENV_FILE="${LOCAL_DIR}/.env"
ACCESS_LOG="${LOCAL_DIR}/.logs/access.json"
BASE_URL="${BASE_URL:-http://localhost:8000}"

export LOCAL_DIR SCRIPTS_DIR UPSTREAM_FILE ENV_FILE ACCESS_LOG BASE_URL

log() { echo "[$(date '+%H:%M:%S')] $*" >&2; }

now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }

compose() { docker compose -f "${LOCAL_DIR}/compose.yaml" "$@"; }

other_color() { if [[ "$1" == "blue" ]]; then echo green; else echo blue; fi; }

# 현재 upstream 파일에서 해당 색의 가중치(0~100)를 읽는다. down 이면 0.
weight_of() {
	local color="$1" line
	line="$(grep -E "server ${color}:8080" "${UPSTREAM_FILE}" || true)"
	if [[ -z "${line}" || "${line}" == *" down"* ]]; then
		echo 0
	else
		sed -E 's/.*weight=([0-9]+).*/\1/' <<<"${line}"
	fi
}

# 가중치 100 인 색 = stable
stable_color() {
	if [[ "$(weight_of blue)" == "100" ]]; then echo blue
	elif [[ "$(weight_of green)" == "100" ]]; then echo green
	else echo ""
	fi
}

# infra/local/.env 의 KEY=VALUE 를 갱신한다 (compose 가 자동으로 읽는 파일)
env_set() {
	local key="$1" value="$2"
	touch "${ENV_FILE}"
	if grep -q "^${key}=" "${ENV_FILE}"; then
		sed -i.bak -E "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}" && rm -f "${ENV_FILE}.bak"
	else
		echo "${key}=${value}" >>"${ENV_FILE}"
	fi
}

env_get() {
	local key="$1" default="${2:-}"
	if [[ -f "${ENV_FILE}" ]] && grep -q "^${key}=" "${ENV_FILE}"; then
		grep "^${key}=" "${ENV_FILE}" | tail -1 | cut -d= -f2-
	else
		echo "${default}"
	fi
}

color_upper() { tr '[:lower:]' '[:upper:]' <<<"$1"; }

# 색 지정 헤더로 readiness 를 폴링한다 (앱 이미지에 curl 이 없어 compose healthcheck 대신 사용)
wait_ready() {
	local color="$1" timeout="${2:-60}" start
	start="$(date +%s)"
	until curl -sf -o /dev/null -H "X-Target-Color: ${color}" "${BASE_URL}/health/readiness"; do
		if (($(date +%s) - start > timeout)); then
			log "${color}: readiness timeout (${timeout}s)"
			return 1
		fi
		sleep 0.5
	done
}
