#!/usr/bin/env bash
# nginx JSON 액세스 로그로 후보 버전의 최근 window 를 판정한다. (5단계 metric-gate.sh 의 로컬 축소판)
# Exit: 0 통과 / 10 임계 초과 / 11 표본 부족 / 2 사용법·환경 오류
set -euo pipefail
# shellcheck source=scripts/local/lib.sh
source "$(dirname "$0")/lib.sh"

usage() {
	cat <<'EOF'
Usage: gate.sh --version <app-version> [--window <sec>] [--since-ms <epoch_ms>]
               [--max-5xx-rate 0.01] [--max-p95-ms 500] [--min-requests 30]

  ALB 의 TargetGroup 차원에 대응해 '응답한 버전(X-App-Version)' 으로 후보를 구분한다.
  창 = max(now - window, since-ms) ~ now
EOF
}

version="" window=30 since=0 max_rate=0.01 max_p95=500 min_req=30
while [[ $# -gt 0 ]]; do
	case "$1" in
		--version) version="$2"; shift 2 ;;
		--window) window="$2"; shift 2 ;;
		--since-ms) since="$2"; shift 2 ;;
		--max-5xx-rate) max_rate="$2"; shift 2 ;;
		--max-p95-ms) max_p95="$2"; shift 2 ;;
		--min-requests) min_req="$2"; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done
[[ -n "${version}" ]] || { usage >&2; exit 2; }
[[ -f "${ACCESS_LOG}" ]] || { echo "access log not found: ${ACCESS_LOG}" >&2; exit 2; }

now="$(now_ms)"
from=$((now - window * 1000))
((since > from)) && from="${since}"

# 최근 로그만 읽는다 (데모 규모에서 충분)
result="$(tail -n 50000 "${ACCESS_LOG}" | jq -sc --arg v "${version}" --argjson from "${from}" '
	map(select(.ts * 1000 >= $from and .app_version == $v and (.uri | startswith("/coupons"))))
	| (map(.request_time * 1000) | sort) as $lat
	| {
		requests: length,
		e5xx: map(select(.status >= 500)) | length,
		p95_ms: (if ($lat | length) > 0 then $lat[((($lat | length) - 1) * 0.95 | floor)] else 0 end)
	}')"

requests="$(jq -r .requests <<<"${result}")"
e5xx="$(jq -r .e5xx <<<"${result}")"
p95="$(jq -r '.p95_ms | floor' <<<"${result}")"

verdict=pass code=0 reason=ok
if ((requests < min_req)); then
	verdict=insufficient code=11 reason="requests ${requests} < ${min_req}"
elif awk -v e="${e5xx}" -v r="${requests}" -v m="${max_rate}" 'BEGIN { exit !(e / r > m) }'; then
	verdict=fail code=10 reason="5xx rate > ${max_rate}"
elif ((p95 > max_p95)); then
	verdict=fail code=10 reason="p95 ${p95}ms > ${max_p95}ms"
fi

rate="$(awk -v e="${e5xx}" -v r="${requests}" 'BEGIN { printf "%.4f", (r > 0 ? e / r : 0) }')"
printf '{"version":"%s","window_s":%d,"requests":%d,"5xx":%d,"rate":%s,"p95_ms":%d,"verdict":"%s","reason":"%s"}\n' \
	"${version}" $(((now - from) / 1000)) "${requests}" "${e5xx}" "${rate}" "${p95}" "${verdict}" "${reason}"
exit "${code}"
