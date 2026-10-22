#!/usr/bin/env bash
# 카나리 단계 실행기: 단계마다 가중치 변경 → 지표 지연 대기 → 판정 루프.
#   판정 = metric-gate.sh(CloudWatch, 권위) + fast-guard.sh(러너 CSV, 조기 감지)
#   0 이고 최소 관찰 시간 경과 → 다음 단계 / 10 → 즉시 실패 / 11 → 최대 대기 안에서 재시도, 넘으면 실패
#   표본 부족도 롤백이다: 증거 없이 승격하지 않는다.
# 실패 시 판정 시각과 사유를 파일로 남기고(롤백 소요 시간 측정용) 종료 코드 10/11 로 끝난다.
set -euo pipefail
# shellcheck source=scripts/aws/common.sh
source "$(dirname "$0")/common.sh"

usage() {
	cat <<'EOF'
Usage: canary-run.sh --steps <10,50> --candidate <blue|green> --version <tag>
                     --tg-suffix <..> --lb-suffix <..> --csv <load.csv> --report <canary-report.json>
Env: GATE_MAX_5XX_RATE(0.01) GATE_MAX_P95_MS(500) GATE_MIN_REQUESTS(50)
     GATE_WINDOW_SECONDS(180, 단계별 최소 관찰) GATE_MAX_WAIT_SECONDS(420) GATE_METRIC_DELAY(60) GATE_POLL(30)
Files: gate-decision.ms, gate-reason (실패 시)
EOF
}

steps="" candidate="" version="" tg="" lb="" csv="" report=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--steps) steps="$2"; shift 2 ;;
		--candidate) candidate="$2"; shift 2 ;;
		--version) version="$2"; shift 2 ;;
		--tg-suffix) tg="$2"; shift 2 ;;
		--lb-suffix) lb="$2"; shift 2 ;;
		--csv) csv="$2"; shift 2 ;;
		--report) report="$2"; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done
[[ -n "${steps}" && -n "${candidate}" && -n "${version}" && -n "${tg}" && -n "${lb}" && -n "${csv}" && -n "${report}" ]] || { usage >&2; exit 2; }

min_observe="${GATE_WINDOW_SECONDS:-180}"
max_wait="${GATE_MAX_WAIT_SECONDS:-420}"
delay="${GATE_METRIC_DELAY:-60}"
poll="${GATE_POLL:-30}"
# fast guard 창: 10% 단계에서 후보는 전체 rps 의 10% 만 받는다 (10 rps → 약 1 rps).
# 30s 창이면 최소 표본 20 을 채울 수 없어 감지가 늦어진다 (AWS 실측: 123s) → 기본 120s.
fg_window="${FAST_GUARD_WINDOW:-120}"
dir="$(dirname "$0")"

[[ -f "${report}" ]] || echo '[]' >"${report}"

record() { # step json
	jq --argjson row "$2" --arg step "$1" '. + [$row + {step: ($step | tonumber)}]' "${report}" >"${report}.tmp" && mv "${report}.tmp" "${report}"
}

fail_with() { # code reason json step
	now_ms >gate-decision.ms
	echo "$2" >gate-reason
	record "$4" "$3"
	log "step $4% FAILED: $2"
	exit "$1"
}

IFS=',' read -r -a step_list <<<"${steps}"
for pct in "${step_list[@]}"; do
	if [[ "${candidate}" == blue ]]; then
		w=(--blue "${pct}" --green "$((100 - pct))")
	else
		w=(--blue "$((100 - pct))" --green "${pct}")
	fi
	"${dir}/set-weights.sh" "${w[@]}" >/dev/null
	t_step="$(date +%s)"
	log "step ${pct}%: weights applied, waiting ${delay}s for ALB metrics"

	# 지표 지연 동안에도 fast guard 는 계속 본다
	fg="$("${dir}/../load/fast-guard.sh" --csv "${csv}" --version "${version}" --window "${fg_window}" \
		--follow --until "$((t_step + delay))" --interval 5)" || fail_with 10 "fast-guard" "${fg}" "${pct}"

	while true; do
		elapsed=$(($(date +%s) - t_step))
		fg="$("${dir}/../load/fast-guard.sh" --csv "${csv}" --version "${version}" --window "${fg_window}")" ||
			fail_with 10 "fast-guard" "${fg}" "${pct}"

		set +e
		gate="$("${dir}/metric-gate.sh" --tg-suffix "${tg}" --lb-suffix "${lb}" --start "${t_step}" --end "$(date +%s)")"
		code=$?
		set -e
		log "step ${pct}% (${elapsed}s): ${gate}"

		case "${code}" in
			0)
				if ((elapsed >= min_observe)); then
					record "${pct}" "$(jq -c --argjson e "${elapsed}" '. + {elapsed_s: $e}' <<<"${gate}")"
					break
				fi
				;;
			10) fail_with 10 "$(jq -r .reason <<<"${gate}")" "${gate}" "${pct}" ;;
			11) ((elapsed < max_wait)) || fail_with 11 "insufficient" "${gate}" "${pct}" ;;
			*) fail_with 2 "gate-error" '{}' "${pct}" ;;
		esac
		sleep "${poll}"
	done
done
log "all steps passed: ${steps}"
