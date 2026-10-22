#!/usr/bin/env bash
# metric-gate.sh 를 fixture(get-metric-data 응답 형식)로 오프라인 검증한다.
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
fixtures="${dir}/../../tests/fixtures/metric-gate"

# fixture : 기대 종료 코드
cases=(
	"pass.json:0"
	"fail-5xx.json:10"
	"fail-p95.json:10"
	"no-5xx-datapoints.json:0"
	"insufficient.json:11"
)

failed=0
for c in "${cases[@]}"; do
	file="${c%%:*}" expected="${c##*:}"
	set +e
	out="$("${dir}/metric-gate.sh" --metrics-json "${fixtures}/${file}" --max-5xx-rate 0.01 --max-p95-ms 500 --min-requests 50)"
	code=$?
	set -e
	if [[ "${code}" == "${expected}" ]]; then
		echo "ok   ${file} → ${code} ${out}"
	else
		echo "FAIL ${file} → ${code} (expected ${expected}) ${out}"
		failed=1
	fi
done
exit "${failed}"
