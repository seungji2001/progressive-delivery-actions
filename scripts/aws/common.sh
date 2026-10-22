#!/usr/bin/env bash
# scripts/aws/*.sh 공용. source 해서 사용한다.
# 리소스는 ARN 을 저장하지 않고 이름 규약(pda-*)으로 매번 조회한다 (runtime 재생성 시 ARN 이 바뀜).

NAME_PREFIX="${NAME_PREFIX:-pda}"
CLUSTER="${NAME_PREFIX}-cluster"
ALB_NAME="${NAME_PREFIX}-alb"
TASK_FAMILY="${NAME_PREFIX}-coupon-api"
STATE_PARAM="/${NAME_PREFIX}/stable-color"
ECR_REPOSITORY="${ECR_REPOSITORY:-${NAME_PREFIX}-coupon-api}"

export NAME_PREFIX CLUSTER ALB_NAME TASK_FAMILY STATE_PARAM ECR_REPOSITORY

log() { echo "[$(date -u '+%H:%M:%S')] $*" >&2; }

now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }

other_color() { if [[ "$1" == "blue" ]]; then echo green; else echo blue; fi; }

service_of() { echo "${NAME_PREFIX}-$1"; }

# GitHub Actions 에서는 $GITHUB_OUTPUT 에도 기록한다
emit() {
	echo "$1=$2"
	if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "$1=$2" >>"${GITHUB_OUTPUT}"; fi
}

listener_arn() {
	local lb
	lb="$(aws elbv2 describe-load-balancers --names "${ALB_NAME}" --query 'LoadBalancers[0].LoadBalancerArn' --output text)"
	# shellcheck disable=SC2016 # JMESPath 리터럴 백틱
	aws elbv2 describe-listeners --load-balancer-arn "${lb}" --query 'Listeners[?Port==`80`].ListenerArn | [0]' --output text
}

tg_arn() {
	aws elbv2 describe-target-groups --names "${NAME_PREFIX}-$1" --query 'TargetGroups[0].TargetGroupArn' --output text
}
