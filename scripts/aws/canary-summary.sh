#!/usr/bin/env bash
# 카나리 Job Summary (markdown) 를 stdout 으로 출력한다.
#   결과 배지, 단계별 판정 표, 단계별 5xx·p95 차트(mermaid xychart), 롤백 소요 시간, 러너 부하 요약
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: canary-summary.sh --title <t> --result <success|failure|cancelled> --report <report.json> --csv <load.csv>
                         [--reason <r>] [--rollback-ms <n>] [--impact-ms <n>]
EOF
}

title="" result="" reason="" rollback="" impact="" report="" csv=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--title) title="$2"; shift 2 ;;
		--result) result="$2"; shift 2 ;;
		--reason) reason="$2"; shift 2 ;;
		--rollback-ms) rollback="$2"; shift 2 ;;
		--impact-ms) impact="$2"; shift 2 ;;
		--report) report="$2"; shift 2 ;;
		--csv) csv="$2"; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

if [[ "${result}" == success ]]; then
	echo "## PASSED — ${title}"
else
	echo "## ROLLED_BACK(reason=${reason:-${result}}) — ${title}"
	echo "> 빨간색 = 자동 롤백이 정상 동작한 결과"
fi
echo ""

if [[ -s "${report}" ]] && [[ "$(jq length "${report}")" -gt 0 ]]; then
	echo "| 단계 | 요청 | 5xx | 5xx 비율 | p95 | 판정 | 관찰 |"
	echo "| --- | --- | --- | --- | --- | --- | --- |"
	jq -r '.[] | "| \(.step)% | \(.requests // .samples // "-") | \(.["5xx"] // "-") | \(.rate // "-") | \(.p95_ms // "-")ms | \(.verdict) | \(.elapsed_s // "-")s |"' "${report}"
	echo ""
	echo '```mermaid'
	echo 'xychart-beta'
	echo '    title "단계별 5xx 비율(%) / p95(ms)"'
	echo "    x-axis [$(jq -r 'map("\"\(.step)%\"") | join(", ")' "${report}")]"
	echo "    y-axis \"value\""
	echo "    bar [$(jq -r 'map((.rate // 0) * 100) | join(", ")' "${report}")]"
	echo "    line [$(jq -r 'map(.p95_ms // 0) | join(", ")' "${report}")]"
	echo '```'
	echo ""
fi

if [[ -n "${rollback}" ]]; then
	echo "| 롤백 | 값 |"
	echo "| --- | --- |"
	echo "| **판정 → 가중치 원복 검증** | **${rollback}ms** |"
	echo "| 판정 → 마지막 후보 응답 (사용자 영향 종료) | ${impact:-0}ms |"
	echo ""
fi

if [[ -f "${csv}" ]]; then
	echo "### 러너 부하 요약"
	"$(dirname "$0")/../load/summarize.sh" "${csv}" --format markdown 2>/dev/null || echo "(no samples)"
fi
