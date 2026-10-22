#!/usr/bin/env bash
# X-Target-Color 헤더로 특정 색을 직접 호출해 검증한다.
# ALB 리스너 규칙과 로컬 nginx(infra/local) 가 같은 규격이라 둘 다에서 실행할 수 있다.
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: smoke-test.sh --base-url <url> --color <blue|green> --expect-version <version>
  1) GET  /health/readiness  → 200
  2) GET  /version           → .version == expect
  3) POST /coupons/issue     → 201 + X-App-Version == expect (최대 3회)
Exit: 0 통과 / 1 실패 / 2 사용법 오류
EOF
}

base="" color="" expect=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--base-url) base="$2"; shift 2 ;;
		--color) color="$2"; shift 2 ;;
		--expect-version) expect="$2"; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done
[[ -n "${base}" && -n "${color}" && -n "${expect}" ]] || { usage >&2; exit 2; }

hdr=(-H "X-Target-Color: ${color}")
fail() { echo "SMOKE FAIL [${color}]: $*" >&2; exit 1; }

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${hdr[@]}" "${base}/health/readiness")"
[[ "${code}" == 200 ]] || fail "readiness=${code}"

version="$(curl -s --max-time 5 "${hdr[@]}" "${base}/version" | jq -r '.version // empty')"
[[ "${version}" == "${expect}" ]] || fail "/version=${version:-<none>}, expected ${expect}"

for attempt in 1 2 3; do
	result="$(curl -s -o /dev/null --max-time 5 -w '%{http_code} %header{x-app-version}' -X POST "${hdr[@]}" \
		-H 'Content-Type: application/json' -d '{"userId":"smoke","orderAmount":25000}' "${base}/coupons/issue")"
	if [[ "${result}" == "201 ${expect}" ]]; then
		echo "SMOKE OK [${color}] ${expect}" >&2
		exit 0
	fi
	echo "POST attempt ${attempt}: ${result}" >&2
	sleep 1
done
fail "POST /coupons/issue did not return '201 ${expect}'"
