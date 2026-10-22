#!/usr/bin/env bash
# CloudWatch ALB 지표로 후보 TG 를 판정한다 (서버 측, 권위 있는 판정).
# Exit: 0 통과 / 10 임계 초과 / 11 표본 부족 / 2 사용법·환경 오류   (scripts/local/gate.sh 와 같은 규약)
#
# 주의
#   - ALB 지표는 60초 해상도 + 1~2분 수집 지연 → 창을 분 경계에 맞추고, 호출 측은 전환 후 최소 60초 뒤부터 부른다.
#   - HTTPCode_Target_5XX_Count 는 5xx 가 0 이면 데이터 포인트가 없다 → "없음 = 0".
#   - percentile 은 기간끼리 평균 낼 수 없다 → p95 는 창 전체를 period 하나로 조회한다.
#   - TargetGroup 차원은 전체 ARN 이 아니라 ARN suffix(targetgroup/pda-green/<id>). 전체 ARN 이면 빈 결과 → 표본 부족 오판.
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: metric-gate.sh --tg-suffix <targetgroup/..> --lb-suffix <app/..> --start <epoch> --end <epoch>
                      [--max-5xx-rate 0.01] [--max-p95-ms 500] [--min-requests 50]
                      [--metrics-json <file>]   # 오프라인 판정 (AWS 호출 없음, fixture 테스트용)
Output: JSON 한 줄 {"requests","5xx","rate","p95_ms","window_s","verdict","reason"}
EOF
}

tg="" lb="" start="" end="" max_rate="${GATE_MAX_5XX_RATE:-0.01}" max_p95="${GATE_MAX_P95_MS:-500}"
min_req="${GATE_MIN_REQUESTS:-50}" metrics_json="${GATE_METRICS_JSON:-}" # GATE_METRICS_JSON: 드라이런/테스트용
while [[ $# -gt 0 ]]; do
	case "$1" in
		--tg-suffix) tg="$2"; shift 2 ;;
		--lb-suffix) lb="$2"; shift 2 ;;
		--start) start="$2"; shift 2 ;;
		--end) end="$2"; shift 2 ;;
		--max-5xx-rate) max_rate="$2"; shift 2 ;;
		--max-p95-ms) max_p95="$2"; shift 2 ;;
		--min-requests) min_req="$2"; shift 2 ;;
		--metrics-json) metrics_json="$2"; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

if [[ -n "${metrics_json}" ]]; then
	[[ -f "${metrics_json}" ]] || { echo "not found: ${metrics_json}" >&2; exit 2; }
	data="$(cat "${metrics_json}")"
	window=0
else
	[[ -n "${tg}" && -n "${lb}" && -n "${start}" && -n "${end}" ]] || { usage >&2; exit 2; }
	# 분 경계 정렬
	start=$((start / 60 * 60))
	end=$((end / 60 * 60))
	window=$((end - start))
	if ((window < 60)); then
		printf '{"requests":0,"5xx":0,"rate":0,"p95_ms":0,"window_s":%d,"verdict":"insufficient","reason":"window < 60s"}\n' "${window}"
		exit 11
	fi
	queries="$(jq -nc --arg tg "${tg}" --arg lb "${lb}" --argjson p "${window}" '
		def q(id; metric; stat): {
			Id: id,
			MetricStat: {
				Metric: {Namespace: "AWS/ApplicationELB", MetricName: metric,
					Dimensions: [{Name: "TargetGroup", Value: $tg}, {Name: "LoadBalancer", Value: $lb}]},
				Period: $p, Stat: stat
			}
		};
		[q("req"; "RequestCount"; "Sum"), q("e5xx"; "HTTPCode_Target_5XX_Count"; "Sum"), q("p95"; "TargetResponseTime"; "p95")]')"
	data="$(aws cloudwatch get-metric-data --metric-data-queries "${queries}" \
		--start-time "${start}" --end-time "${end}" --output json)"
fi

# 값이 없으면 0 (5xx 없음 = 0, 요청 없음 = 0 → 표본 부족)
read -r requests e5xx p95_ms < <(jq -r '
	def sum_of(id): ([.MetricDataResults[] | select(.Id == id) | .Values[]] | add) // 0;
	def first_of(id): ([.MetricDataResults[] | select(.Id == id) | .Values[]] | max) // 0;
	"\(sum_of("req") | floor) \(sum_of("e5xx") | floor) \(first_of("p95") * 1000 | floor)"' <<<"${data}")

verdict=pass code=0 reason=ok
if ((requests < min_req)); then
	verdict=insufficient code=11 reason="requests ${requests} < ${min_req}"
elif awk -v e="${e5xx}" -v r="${requests}" -v m="${max_rate}" 'BEGIN { exit !(e / r > m) }'; then
	verdict=fail code=10 reason="5xx"
elif ((p95_ms > max_p95)); then
	verdict=fail code=10 reason="p95"
fi

rate="$(awk -v e="${e5xx}" -v r="${requests}" 'BEGIN { printf "%.4f", (r > 0 ? e / r : 0) }')"
printf '{"requests":%d,"5xx":%d,"rate":%s,"p95_ms":%d,"window_s":%d,"verdict":"%s","reason":"%s"}\n' \
	"${requests}" "${e5xx}" "${rate}" "${p95_ms}" "${window}" "${verdict}" "${reason}"
exit "${code}"
