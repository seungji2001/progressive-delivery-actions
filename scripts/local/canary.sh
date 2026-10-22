#!/usr/bin/env bash
# 로컬 카나리: 단계별 가중치(10→50→100) + 단계마다 지표 게이트, 실패 시 즉시 stable 100 원복
set -euo pipefail
# shellcheck source=scripts/local/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=scripts/local/deploy-lib.sh
source "$(dirname "$0")/deploy-lib.sh"

usage() {
	cat <<'EOF'
Usage: canary.sh <new-tag> [--steps 10,50,100] [--window <sec>] [--fault-rate <0-1>] [--fault-delay-ms <ms>]
                 [--max-5xx-rate 0.01] [--max-p95-ms 500] [--min-requests 30] [--no-load]

  각 단계: 가중치 변경 → window 초 관찰 → gate.sh (0 통과 / 10 임계 초과 / 11 표본 부족)
  통과가 아니면(표본 부족 포함) 즉시 stable 100 으로 원복하고 exit 1.
Result: PROMOTED / ROLLED_BACK / ABORTED_BEFORE_SWITCH / NO_OP
EOF
}

tag="" steps="10,50,100" window=20 fault_rate=0 fault_delay=0 max_rate=0.01 max_p95=500 min_req=30 with_load=true
while [[ $# -gt 0 ]]; do
	case "$1" in
		--steps) steps="$2"; shift 2 ;;
		--window) window="$2"; shift 2 ;;
		--fault-rate) fault_rate="$2"; shift 2 ;;
		--fault-delay-ms) fault_delay="$2"; shift 2 ;;
		--max-5xx-rate) max_rate="$2"; shift 2 ;;
		--max-p95-ms) max_p95="$2"; shift 2 ;;
		--min-requests) min_req="$2"; shift 2 ;;
		--no-load) with_load=false; shift ;;
		-h | --help) usage; exit 0 ;;
		-*) usage >&2; exit 2 ;;
		*) tag="$1"; shift ;;
	esac
done
[[ -n "${tag}" ]] || { usage >&2; exit 2; }

stable="$(stable_color)"
[[ -n "${stable}" ]] || { log "traffic state inconsistent (no color at 100%)"; exit 2; }
candidate="$(other_color "${stable}")"
stable_tag="$(env_get "$(color_upper "${stable}")_TAG")"
[[ "${stable_tag}" != "${tag}" ]] || { echo "RESULT=NO_OP"; exit 0; }

weights_for() { # <candidate-percent>
	local c="$1" s=$((100 - $1))
	if [[ "${candidate}" == blue ]]; then echo "--blue ${c} --green ${s}"; else echo "--blue ${s} --green ${c}"; fi
}

t_start="$(now_ms)"
log "stable=${stable}(${stable_tag}) candidate=${candidate}(${tag}) steps=${steps}"
deploy_candidate "${candidate}" "${tag}" "${fault_rate}" "${fault_delay}"
smoke "${candidate}" "${tag}" || { echo "RESULT=ABORTED_BEFORE_SWITCH"; exit 1; }

csv="${LOCAL_DIR}/.logs/canary-$(date +%Y%m%d-%H%M%S).csv"
if [[ "${with_load}" == true ]]; then
	start_load "${csv}" 50
	trap stop_load EXIT
	sleep 3
fi

printf '%-6s %-9s %-8s %-6s %-8s %-7s %s\n' step requests 5xx rate p95_ms verdict elapsed_s >&2
IFS=',' read -r -a step_list <<<"${steps}"
for pct in "${step_list[@]}"; do
	# shellcheck disable=SC2046
	t_step="$("${SCRIPTS_DIR}/local/set-weights.sh" $(weights_for "${pct}"))"
	sleep "${window}"
	set +e
	gate_json="$("${SCRIPTS_DIR}/local/gate.sh" --version "${tag}" --since-ms "${t_step}" --window "${window}" \
		--max-5xx-rate "${max_rate}" --max-p95-ms "${max_p95}" --min-requests "${min_req}")"
	gate_code=$?
	set -e
	printf '%-6s %-9s %-8s %-6s %-8s %-7s %s\n' "${pct}%" \
		"$(jq -r .requests <<<"${gate_json}")" "$(jq -r '.["5xx"]' <<<"${gate_json}")" \
		"$(jq -r .rate <<<"${gate_json}")" "$(jq -r .p95_ms <<<"${gate_json}")" \
		"$(jq -r .verdict <<<"${gate_json}")" "$((($(now_ms) - t_step) / 1000))" >&2

	if ((gate_code != 0)); then
		t_decision="$(now_ms)"
		# shellcheck disable=SC2046
		t_restored="$("${SCRIPTS_DIR}/local/set-weights.sh" $(weights_for 0))"
		sleep 2
		stop_load
		echo "RESULT=ROLLED_BACK at ${pct}% (reason: $(jq -r .reason <<<"${gate_json}"))"
		echo "rollback_ms=$((t_restored - t_decision))"
		if [[ -f "${csv}" ]]; then
			last="$(last_response_of "${csv}" "${tag}" "${t_decision}")"
			((last > 0)) && echo "last_candidate_response_after_decision_ms=$((last - t_decision))"
			"${SCRIPTS_DIR}/load/summarize.sh" "${csv}"
		fi
		exit 1
	fi
done

stop_load
echo "RESULT=PROMOTED ${stable}(${stable_tag}) → ${candidate}(${tag})"
echo "total_ms=$(($(now_ms) - t_start))"
[[ -f "${csv}" ]] && "${SCRIPTS_DIR}/load/summarize.sh" "${csv}"
exit 0
