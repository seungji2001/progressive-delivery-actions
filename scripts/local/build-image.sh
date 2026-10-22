#!/usr/bin/env bash
# git ref(태그) 단위로 coupon-api 이미지를 빌드한다.
# 릴리즈 단위 = git 태그 = 이미지 태그 = APP_VERSION 원칙을 로컬에서 재현한다.
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  build-image.sh <git-ref>                 # 예: build-image.sh v1.0.0
  build-image.sh --working-tree <version>  # 커밋 전 작업 트리를 빌드 (GIT_SHA=<HEAD>-dirty)

Env:
  PLATFORM  빌드 플랫폼 (기본 linux/arm64)
EOF
}

PLATFORM="${PLATFORM:-linux/arm64}"
REPO_ROOT="$(git rev-parse --show-toplevel)"

build() {
	local context="$1" version="$2" sha="$3"
	echo "building coupon-api:${version} (GIT_SHA=${sha}, ${PLATFORM})" >&2
	docker build --platform "${PLATFORM}" \
		--build-arg "APP_VERSION=${version}" \
		--build-arg "GIT_SHA=${sha}" \
		-t "coupon-api:${version}" "${context}/app"
}

case "${1:-}" in
	-h | --help | "")
		usage
		[[ -n "${1:-}" ]] || exit 2
		exit 0
		;;
	--working-tree)
		[[ -n "${2:-}" ]] || { usage >&2; exit 2; }
		build "${REPO_ROOT}" "$2" "$(git -C "${REPO_ROOT}" rev-parse --short HEAD)-dirty"
		;;
	*)
		ref="$1"
		sha="$(git -C "${REPO_ROOT}" rev-parse --short "${ref}^{commit}")"
		worktree="$(mktemp -d)"
		cleanup() { git -C "${REPO_ROOT}" worktree remove --force "${worktree}" >/dev/null 2>&1 || true; }
		trap cleanup EXIT
		git -C "${REPO_ROOT}" worktree add --detach "${worktree}" "${ref}" >/dev/null 2>&1
		build "${worktree}" "${ref}" "${sha}"
		;;
esac
