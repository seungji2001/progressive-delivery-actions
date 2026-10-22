#!/usr/bin/env bash
# nginx 가중치 upstream 을 교체하고 graceful reload 한다. (AWS: aws elbv2 modify-listener)
# 성공 시 반영 시각(epoch ms)을 stdout 으로 출력한다.
set -euo pipefail
# shellcheck source=scripts/local/lib.sh
source "$(dirname "$0")/lib.sh"

usage() {
	cat <<'EOF'
Usage: set-weights.sh --blue <0-100> --green <0-100>
  두 값의 합은 100 이어야 한다. 0% 인 색은 nginx 'down' 으로 처리한다.
Exit: 0 성공 / 1 nginx 설정 검증 실패(이전 설정으로 복원) / 2 사용법 오류
EOF
}

blue="" green=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--blue) blue="$2"; shift 2 ;;
		--green) green="$2"; shift 2 ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

[[ "${blue}" =~ ^[0-9]+$ && "${green}" =~ ^[0-9]+$ ]] || { usage >&2; exit 2; }
if ((blue + green != 100)); then
	echo "blue + green must be 100 (got $((blue + green)))" >&2
	exit 2
fi

server_line() {
	local color="$1" weight="$2"
	if ((weight == 0)); then
		echo "    server ${color}:8080 resolve down;"
	else
		echo "    server ${color}:8080 resolve weight=${weight};"
	fi
}

tmp="${UPSTREAM_FILE}.tmp"
backup="${UPSTREAM_FILE}.bak"
{
	echo "# managed by scripts/local/set-weights.sh — blue=${blue} green=${green}"
	echo "upstream app_weighted {"
	echo "    zone app_weighted 64k;"
	server_line blue "${blue}"
	server_line green "${green}"
	echo "    keepalive 16;"
	echo "}"
} >"${tmp}"

[[ -f "${UPSTREAM_FILE}" ]] && cp "${UPSTREAM_FILE}" "${backup}"
mv "${tmp}" "${UPSTREAM_FILE}"

if ! compose exec -T nginx nginx -t -q; then
	log "nginx -t failed, restoring previous upstream"
	[[ -f "${backup}" ]] && mv "${backup}" "${UPSTREAM_FILE}"
	exit 1
fi
compose exec -T nginx nginx -s reload >/dev/null 2>&1
rm -f "${backup}"

applied="$(now_ms)"
log "weights applied: blue=${blue} green=${green}"
echo "${applied}"
