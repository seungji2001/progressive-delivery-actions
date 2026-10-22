#!/usr/bin/env bash
# 색 서비스의 태스크 수를 조정한다. --wait 이면 안정화까지 기다린다.
set -euo pipefail
# shellcheck source=scripts/aws/common.sh
source "$(dirname "$0")/common.sh"

usage() { echo "Usage: scale-service.sh --color <blue|green> --count <n> [--wait]"; }

color="" count="" wait=false
while [[ $# -gt 0 ]]; do
	case "$1" in
		--color) color="$2"; shift 2 ;;
		--count) count="$2"; shift 2 ;;
		--wait) wait=true; shift ;;
		-h | --help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done
[[ "${color}" == blue || "${color}" == green ]] && [[ "${count}" =~ ^[0-9]+$ ]] || { usage >&2; exit 2; }

aws ecs update-service --cluster "${CLUSTER}" --service "$(service_of "${color}")" --desired-count "${count}" >/dev/null
log "$(service_of "${color}") desired=${count}"
if [[ "${wait}" == true ]]; then
	aws ecs wait services-stable --cluster "${CLUSTER}" --services "$(service_of "${color}")"
	log "$(service_of "${color}") stable"
fi
