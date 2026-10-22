#!/usr/bin/env bash
# 로컬 Blue-Green: 비활성 색 배포 → 스모크 → 100% 전환 → 관찰 → (실패 시) 즉시 원복
set -euo pipefail
# shellcheck source=scripts/local/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=scripts/local/deploy-lib.sh
source "$(dirname "$0")/deploy-lib.sh"

usage() {
	cat <<'EOF'
Usage: blue-green.sh <new-tag> [--observe <sec>] [--fault-rate <0-1>] [--scale-down] [--no-load]

  --observe     전환 후 관찰 시간 (기본 20)
  --fault-rate  후보에만 주입할 FAULT_RATE (관찰 구간 롤백 시연용, 기본 0)
  --scale-down  성공 시 이전 색을 정지 (부하를 유지한 채 drain 중 실패 0건 확인)
  --no-load     자체 부하를 만들지 않는다 (외부에서 load.sh 를 돌릴 때)
Result: PROMOTED / ROLLED_BACK / ABORTED_BEFORE_SWITCH / NO_OP
EOF
}

tag="" observe=20 fault_rate=0 scale_down=false with_load=true
while [[ $# -gt 0 ]]; do
	case "$1" in
		--observe) observe="$2"; shift 2 ;;
		--fault-rate) fault_rate="$2"; shift 2 ;;
		--scale-down) scale_down=true; shift ;;
		--no-load) with_load=false; shift ;;
		-h | --help) usage; exit 0 ;;
		-*) usage >&2; exit 2 ;;
		*) tag="$1"; shift ;;
	esac
done
[[ -n "${tag}" ]] || { usage >&2; exit 2; }

stable="$(stable_color)"
[[ -n "${stable}" ]] || { log "traffic state inconsistent (no color at 100%). run set-weights.sh first"; exit 2; }
candidate="$(other_color "${stable}")"
stable_tag="$(env_get "$(color_upper "${stable}")_TAG")"

if [[ "${stable_tag}" == "${tag}" ]]; then
	echo "RESULT=NO_OP (${stable} already runs ${tag})"
	exit 0
fi

t_start="$(now_ms)"
log "stable=${stable}(${stable_tag}) candidate=${candidate}(${tag})"

deploy_candidate "${candidate}" "${tag}" "${fault_rate}"
t_ready="$(now_ms)"

if ! smoke "${candidate}" "${tag}"; then
	echo "RESULT=ABORTED_BEFORE_SWITCH (smoke failed, listener untouched → nothing to roll back)"
	exit 1
fi

csv="${LOCAL_DIR}/.logs/blue-green-$(date +%Y%m%d-%H%M%S).csv"
if [[ "${with_load}" == true ]]; then
	start_load "${csv}" 50
	trap stop_load EXIT
	sleep 3
fi

args=(--blue 0 --green 0)
if [[ "${candidate}" == blue ]]; then args=(--blue 100 --green 0); else args=(--blue 0 --green 100); fi
t_switch="$("${SCRIPTS_DIR}/local/set-weights.sh" "${args[@]}")"

log "observing ${observe}s"
sleep "${observe}"

set +e
gate_json="$("${SCRIPTS_DIR}/local/gate.sh" --version "${tag}" --since-ms "${t_switch}" --window "${observe}" --min-requests 20)"
gate_code=$?
set -e
log "gate: ${gate_json}"

if ((gate_code != 0)); then
	t_decision="$(now_ms)"
	if [[ "${stable}" == blue ]]; then args=(--blue 100 --green 0); else args=(--blue 0 --green 100); fi
	t_restored="$("${SCRIPTS_DIR}/local/set-weights.sh" "${args[@]}")"
	sleep 2
	stop_load
	echo "RESULT=ROLLED_BACK (gate exit ${gate_code})"
	echo "rollback_ms=$((t_restored - t_decision))"
	if [[ -f "${csv}" ]]; then
		last="$(last_response_of "${csv}" "${tag}" "${t_decision}")"
		((last > 0)) && echo "last_candidate_response_after_decision_ms=$((last - t_decision))"
		"${SCRIPTS_DIR}/load/summarize.sh" "${csv}"
	fi
	exit 1
fi

if [[ "${scale_down}" == true ]]; then
	log "stopping previous color ${stable} (load continues)"
	compose stop "${stable}" >/dev/null 2>&1
	sleep 3
fi

stop_load
t_end="$(now_ms)"
echo "RESULT=PROMOTED ${stable}(${stable_tag}) → ${candidate}(${tag})"
echo "deploy_ready_ms=$((t_ready - t_start)) switch_at_ms=$((t_switch - t_start)) total_ms=$((t_end - t_start))"
[[ -f "${csv}" ]] && "${SCRIPTS_DIR}/load/summarize.sh" "${csv}"
exit 0
