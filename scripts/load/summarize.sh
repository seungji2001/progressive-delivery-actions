#!/usr/bin/env bash
# load.sh CSV 를 요약한다: 버전별 비율, 상태코드 분포, 5xx 비율, 연결 실패, p50/p95/p99.
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: summarize.sh <csv> [--since-ms <epoch_ms>] [--until-ms <epoch_ms>] [--format text|markdown|json]
  markdown 출력은 GitHub Actions Job Summary 에 그대로 붙일 수 있다.
EOF
}

csv="" since=0 until=0 format=text
while [[ $# -gt 0 ]]; do
	case "$1" in
		--since-ms) since="$2"; shift 2 ;;
		--until-ms) until="$2"; shift 2 ;;
		--format) format="$2"; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		-*) usage >&2; exit 2 ;;
		*) csv="$1"; shift ;;
	esac
done
[[ -f "${csv}" ]] || { usage >&2; exit 2; }

filtered="$(awk -F, -v s="${since}" -v u="${until}" \
	'NR > 1 && $1 >= s && (u == 0 || $1 <= u)' "${csv}")"

if [[ -z "${filtered}" ]]; then
	echo "no samples" >&2
	exit 11
fi

percentiles="$(cut -d, -f4 <<<"${filtered}" | sort -n | awk '
	{ v[NR] = $1 }
	END {
		p50 = v[int((NR - 1) * 0.50) + 1]; p95 = v[int((NR - 1) * 0.95) + 1]; p99 = v[int((NR - 1) * 0.99) + 1]
		printf "%d %d %d", p50, p95, p99
	}')"

awk -F, -v fmt="${format}" -v pct="${percentiles}" '
	{
		total++
		code[$2]++
		ver = ($3 == "" ? "(none)" : $3)
		vers[ver]++
		if ($2 ~ /^5/) { e5++; ve5[ver]++ }
		if ($2 == "000") conn++
		if (first == 0 || $1 < first) first = $1
		if ($1 > last) last = $1
	}
	END {
		split(pct, p, " ")
		rate = e5 / total
		dur = (last - first) / 1000
		if (fmt == "json") {
			printf "{\"total\":%d,\"duration_s\":%.1f,\"5xx\":%d,\"5xx_rate\":%.4f,\"conn_fail\":%d,\"p50_ms\":%d,\"p95_ms\":%d,\"p99_ms\":%d,\"versions\":{", total, dur, e5, rate, conn + 0, p[1], p[2], p[3]
			sep = ""
			for (v in vers) { printf "%s\"%s\":%d", sep, v, vers[v]; sep = "," }
			printf "},\"versions_5xx\":{"
			sep = ""
			for (v in vers) { printf "%s\"%s\":%d", sep, v, ve5[v] + 0; sep = "," }
			printf "},\"codes\":{"
			sep = ""
			for (c in code) { printf "%s\"%s\":%d", sep, c, code[c]; sep = "," }
			print "}}"
		} else if (fmt == "markdown") {
			printf "| 항목 | 값 |\n| --- | --- |\n"
			printf "| 총 요청 | %d (%.1fs) |\n| 5xx | %d (%.2f%%) |\n| 연결 실패 | %d |\n", total, dur, e5, rate * 100, conn + 0
			printf "| 지연 p50 / p95 / p99 | %d / %d / %d ms |\n\n", p[1], p[2], p[3]
			printf "| 버전 | 요청 | 비율 | 5xx |\n| --- | --- | --- | --- |\n"
			for (v in vers) printf "| %s | %d | %.1f%% | %d |\n", v, vers[v], vers[v] * 100 / total, ve5[v] + 0
			printf "\n| 상태코드 | 건수 |\n| --- | --- |\n"
			for (c in code) printf "| %s | %d |\n", c, code[c]
		} else {
			printf "total=%d duration=%.1fs 5xx=%d (%.2f%%) conn_fail=%d p50=%dms p95=%dms p99=%dms\n", total, dur, e5, rate * 100, conn + 0, p[1], p[2], p[3]
			for (v in vers) printf "  version %-10s %6d (%5.1f%%) 5xx=%d\n", v, vers[v], vers[v] * 100 / total, ve5[v] + 0
			for (c in code) printf "  status  %-10s %6d\n", c, code[c]
		}
	}' <<<"${filtered}"
