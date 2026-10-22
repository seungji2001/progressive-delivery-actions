#!/usr/bin/env bash
# 로컬 환경 초기화: blue=v1.0.0 100% / green=v2.0.0 0% 로 기동한다.
set -euo pipefail
# shellcheck source=scripts/local/lib.sh
source "$(dirname "$0")/lib.sh"

blue_tag="${1:-v1.0.0}"
green_tag="${2:-v2.0.0}"

mkdir -p "${LOCAL_DIR}/.logs"
: >"${ENV_FILE}"
env_set BLUE_TAG "${blue_tag}"
env_set GREEN_TAG "${green_tag}"
env_set BLUE_FAULT_RATE 0
env_set GREEN_FAULT_RATE 0

# nginx 가 처음 뜰 때 읽을 기본 upstream (blue 100 / green 0)
cat >"${UPSTREAM_FILE}" <<'EOF'
# managed by scripts/local/set-weights.sh — blue=100 green=0
upstream app_weighted {
    zone app_weighted 64k;
    server blue:8080 resolve weight=100;
    server green:8080 resolve down;
    keepalive 16;
}
EOF

compose up -d --force-recreate >/dev/null 2>&1
wait_ready blue 90
wait_ready green 90
log "ready: blue=${blue_tag}(100%) green=${green_tag}(0%) → ${BASE_URL}  monitor: ${BASE_URL}/monitor/"
