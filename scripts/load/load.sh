#!/usr/bin/env bash
# POST /coupons/issue 를 반복 호출하고 응답마다 CSV 한 줄을 남긴다.
# CSV 규격(4·5단계 러너에서도 재사용, 변경 금지): epoch_ms,http_code,app_version,latency_ms
#   - 연결 실패는 http_code=000 (다운타임으로 집계)
# 요구: curl 7.84+ (-w '%header{}'), perl (응답 완료 시각 기록)
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: load.sh --target <base-url> --duration <sec> --concurrency <n> --out <csv>
               [--rps <total-rps>] [--header 'K: V']

  POST 위주로 호출한다: 가중치 라우팅 중 발급/조회가 다른 인스턴스로 가면
  인메모리 저장소 때문에 404 가 나므로 조회는 하지 않는다.
  SIGTERM/SIGINT 를 받으면 진행 중인 요청을 마치고 종료한다.
EOF
}

target="" duration="" concurrency="" out="" rps="" header=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--target) target="$2"; shift 2 ;;
		--duration) duration="$2"; shift 2 ;;
		--concurrency) concurrency="$2"; shift 2 ;;
		--out) out="$2"; shift 2 ;;
		--rps) rps="$2"; shift 2 ;;
		--header) header="$2"; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done
[[ -n "${target}" && -n "${duration}" && -n "${concurrency}" && -n "${out}" ]] || { usage >&2; exit 2; }

# 워커당 요청 간 간격(초). rps 미지정이면 간격 없이 최대 속도.
interval=0
if [[ -n "${rps}" ]]; then
	interval="$(awk -v c="${concurrency}" -v r="${rps}" 'BEGIN { printf "%.3f", c / r }')"
fi

mkdir -p "$(dirname "${out}")"
[[ -s "${out}" ]] || echo "epoch_ms,http_code,app_version,latency_ms" >"${out}"

end=$((SECONDS + duration))
stop=0

worker() {
	local curl_args=(-s -o /dev/null --max-time 10 -X POST
		-H 'Content-Type: application/json'
		-d '{"userId":"load","orderAmount":25000}'
		-w '%{http_code},%header{x-app-version},%{time_total}\n')
	[[ -n "${header}" ]] && curl_args+=(-H "${header}")
	trap 'stop=1' TERM INT
	while ((SECONDS < end && stop == 0)); do
		curl "${curl_args[@]}" "${target}/coupons/issue" || true
		[[ "${interval}" == "0" ]] || sleep "${interval}"
	done | perl -MTime::HiRes=time -ne '
		BEGIN { $| = 1 }
		chomp;
		my ($code, $version, $total) = split /,/, $_, -1;
		printf "%d,%s,%s,%d\n", time * 1000, $code, $version, $total * 1000;
	' >>"${out}"
}

pids=()
for _ in $(seq 1 "${concurrency}"); do
	worker &
	pids+=($!)
done

terminate() {
	stop=1
	for pid in "${pids[@]}"; do pkill -TERM -P "${pid}" 2>/dev/null || true; kill -TERM "${pid}" 2>/dev/null || true; done
}
trap terminate TERM INT

wait "${pids[@]}" 2>/dev/null || true
