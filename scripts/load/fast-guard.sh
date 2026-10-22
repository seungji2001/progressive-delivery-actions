#!/usr/bin/env bash
# 러너 부하 CSV 로 후보 버전의 최근 5xx 비율을 본다 (클라이언트 측, 지연 없는 조기 감지).
# CloudWatch 게이트(metric-gate.sh)는 권위 있는 판정이지만 1~2분 늦다. 둘 중 하나라도 실패하면 롤백한다.
# Exit: 0 이상 없음 / 10 임계 초과 / 2 사용법 오류
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: fast-guard.sh --csv <load.csv> --version <candidate> [--window 30] [--max-5xx-rate 0.05]
                     [--min-samples 20] [--max-conn-fail 0] [--follow --until <epoch>] [--interval 5]

  --follow  --until 시각까지 interval 마다 반복 검사 (백그라운드 감시용)
  연결 실패(000)는 버전과 관계없이 별도로 센다 (다운타임 신호).
EOF
}

csv="" version="" window=30 max_rate=0.05 min_samples=20 max_conn=0 follow=false until=0 interval=5
while [[ $# -gt 0 ]]; do
	case "$1" in
		--csv) csv="$2"; shift 2 ;;
		--version) version="$2"; shift 2 ;;
		--window) window="$2"; shift 2 ;;
		--max-5xx-rate) max_rate="$2"; shift 2 ;;
		--min-samples) min_samples="$2"; shift 2 ;;
		--max-conn-fail) max_conn="$2"; shift 2 ;;
		--follow) follow=true; shift ;;
		--until) until="$2"; shift 2 ;;
		--interval) interval="$2"; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done
[[ -n "${csv}" && -n "${version}" ]] || { usage >&2; exit 2; }

check() {
	local now_ms result
	now_ms="$(perl -MTime::HiRes=time -e 'printf "%d", time * 1000')"
	[[ -f "${csv}" ]] || return 0
	result="$(awk -F, -v v="${version}" -v from="$((now_ms - window * 1000))" '
		NR > 1 && $1 >= from {
			if ($2 == "000") conn++
			if ($3 == v) { n++; if ($2 ~ /^5/) e++ }
		}
		END { printf "%d %d %d", n, e, conn }' "${csv}")"
	read -r n e conn <<<"${result}"
	if ((conn > max_conn)); then
		echo "{\"verdict\":\"fail\",\"reason\":\"fast-guard:connection-failure\",\"samples\":${n},\"5xx\":${e},\"conn_fail\":${conn}}"
		return 10
	fi
	if ((n >= min_samples)) && awk -v e="${e}" -v n="${n}" -v m="${max_rate}" 'BEGIN { exit !(e / n > m) }'; then
		echo "{\"verdict\":\"fail\",\"reason\":\"fast-guard:5xx\",\"samples\":${n},\"5xx\":${e},\"conn_fail\":${conn}}"
		return 10
	fi
	return 0
}

if [[ "${follow}" != true ]]; then
	check
	exit $?
fi

while (($(date +%s) < until)); do
	check || exit $?
	sleep "${interval}"
done
