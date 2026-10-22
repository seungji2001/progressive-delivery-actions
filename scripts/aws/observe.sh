#!/usr/bin/env bash
# Blue-Green 전환 후 관찰 구간 판정.
#   (a) 러너 부하 CSV: 후보 버전 5xx 비율 > 임계 또는 연결 실패 ≥ 1
#   (b) 후보 TG 5xx 알람 상태 = ALARM
# 5단계에서 metric-gate.sh + fast-guard.sh 로 교체 예정.
# Exit: 0 통과 / 10 실패 / 2 사용법 오류
set -euo pipefail
# shellcheck source=scripts/aws/common.sh
source "$(dirname "$0")/common.sh"

usage() {
	cat <<'EOF'
Usage: observe.sh --csv <load.csv> --version <candidate-version> --color <color>
                  --since-ms <epoch_ms> --seconds <n> [--max-5xx-rate 0.01]
EOF
}

csv="" version="" color="" since="" seconds="" max_rate=0.01
while [[ $# -gt 0 ]]; do
	case "$1" in
		--csv) csv="$2"; shift 2 ;;
		--version) version="$2"; shift 2 ;;
		--color) color="$2"; shift 2 ;;
		--since-ms) since="$2"; shift 2 ;;
		--seconds) seconds="$2"; shift 2 ;;
		--max-5xx-rate) max_rate="$2"; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done
[[ -n "${csv}" && -n "${version}" && -n "${color}" && -n "${since}" && -n "${seconds}" ]] || { usage >&2; exit 2; }

summarize="$(dirname "$0")/../load/summarize.sh"
deadline=$(($(date +%s) + seconds))

while (($(date +%s) < deadline)); do
	sleep 10
	stats="$("${summarize}" "${csv}" --since-ms "${since}" --format json 2>/dev/null || echo '{}')"
	requests="$(jq -r --arg v "${version}" '.versions[$v] // 0' <<<"${stats}")"
	e5xx="$(jq -r --arg v "${version}" '.versions_5xx[$v] // 0' <<<"${stats}")"
	conn="$(jq -r '.conn_fail // 0' <<<"${stats}")"
	alarm="$(aws cloudwatch describe-alarms --alarm-names "${NAME_PREFIX}-${color}-5xx" \
		--query 'MetricAlarms[0].StateValue' --output text 2>/dev/null || echo UNKNOWN)"
	log "observe: ${version} requests=${requests} 5xx=${e5xx} conn_fail=${conn} alarm=${alarm}"

	if ((conn > 0)); then
		emit observe_reason "connection-failure"; exit 10
	fi
	if ((requests > 0)) && awk -v e="${e5xx}" -v r="${requests}" -v m="${max_rate}" 'BEGIN { exit !(e / r > m) }'; then
		emit observe_reason "5xx-rate"; exit 10
	fi
	if [[ "${alarm}" == ALARM ]]; then
		emit observe_reason "cloudwatch-alarm"; exit 10
	fi
done

emit observe_reason "ok"
