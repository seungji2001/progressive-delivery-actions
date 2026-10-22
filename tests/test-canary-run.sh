#!/usr/bin/env bash
# canary-run.sh 를 가짜 aws CLI + metric-gate fixture 로 오프라인 검증한다.
#   1) 정상 fixture → 모든 단계 통과, 최종 가중치 = 마지막 단계
#   2) 5xx fixture → 첫 단계에서 exit 10, gate-decision.ms / gate-reason 기록
#   3) 표본 부족 fixture → 최대 대기 초과 후 exit 11
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
export PATH="${root}/tests/fake-aws:${PATH}"
export GATE_METRIC_DELAY=1 GATE_POLL=1 GATE_WINDOW_SECONDS=1 GATE_MAX_WAIT_SECONDS=3
echo "epoch_ms,http_code,app_version,latency_ms" >"${work}/load.csv"

run() { # name fixture steps expected-exit
	export FAKE_AWS_STATE="${work}/$1.state" GATE_METRICS_JSON="${root}/tests/fixtures/metric-gate/$2"
	set +e
	(cd "${work}" && "${root}/scripts/aws/canary-run.sh" --steps "$3" --candidate green --version v2.1.0 \
		--tg-suffix targetgroup/pda-green/abc --lb-suffix app/pda-alb/xyz \
		--csv "${work}/load.csv" --report "${work}/$1.json" 2>/dev/null)
	code=$?
	set -e
	weights="$(cat "${FAKE_AWS_STATE}")"
	if [[ "${code}" == "$4" ]]; then echo "ok   $1 → exit ${code}, weights ${weights}, report $(jq -c 'map({step, verdict})' "${work}/$1.json")"
	else echo "FAIL $1 → exit ${code} (expected $4)"; exit 1; fi
}

run promote pass.json "10,50" 0
[[ "$(jq -r .green "${work}/promote.state")" == 50 ]] || { echo "FAIL final weight"; exit 1; }
run fail-5xx fail-5xx.json "10,50" 10
[[ -s "${work}/gate-decision.ms" && "$(cat "${work}/gate-reason")" == 5xx ]] || { echo "FAIL decision files"; exit 1; }
run insufficient insufficient.json "10" 11
echo "all canary-run tests passed"
