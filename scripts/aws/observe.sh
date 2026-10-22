#!/usr/bin/env bash
# Blue-Green 전환 후 관찰 구간 판정. 카나리와 같은 판정 로직을 쓴다.
#   관찰 중: fast-guard.sh (러너 CSV, 후보 버전 5xx·연결 실패)
#   관찰 끝: metric-gate.sh (CloudWatch, 전환 시각 ~ 지금)
# Exit: 0 통과 / 10 실패 / 11 표본 부족(= 실패로 취급) / 2 사용법 오류
set -euo pipefail
# shellcheck source=scripts/aws/common.sh
source "$(dirname "$0")/common.sh"

usage() {
	cat <<'EOF'
Usage: observe.sh --csv <load.csv> --version <candidate-version> --tg-suffix <..> --lb-suffix <..>
                  --since <epoch_s> --seconds <n>
EOF
}

csv="" version="" tg="" lb="" since="" seconds=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--csv) csv="$2"; shift 2 ;;
		--version) version="$2"; shift 2 ;;
		--tg-suffix) tg="$2"; shift 2 ;;
		--lb-suffix) lb="$2"; shift 2 ;;
		--since) since="$2"; shift 2 ;;
		--seconds) seconds="$2"; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done
[[ -n "${csv}" && -n "${version}" && -n "${tg}" && -n "${lb}" && -n "${since}" && -n "${seconds}" ]] || { usage >&2; exit 2; }

dir="$(dirname "$0")"

if ! fg="$("${dir}/../load/fast-guard.sh" --csv "${csv}" --version "${version}" \
	--follow --until "$((since + seconds))" --interval 5)"; then
	log "fast guard: ${fg}"
	emit observe_reason "$(jq -r .reason <<<"${fg}")"
	exit 10
fi

set +e
gate="$("${dir}/metric-gate.sh" --tg-suffix "${tg}" --lb-suffix "${lb}" --start "${since}" --end "$(date +%s)")"
code=$?
set -e
log "metric gate: ${gate}"
emit observe_reason "$(jq -r '.reason' <<<"${gate}")"
exit "${code}"
