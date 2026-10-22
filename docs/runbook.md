# 운영 런북

배포 중 문제가 생겼을 때 운영자가 할 일. 확인 명령은 레포 스크립트와 aws CLI **읽기** 명령만 쓴다.

공통 준비:

```bash
export AWS_REGION=ap-northeast-2   # 로컬 관리자 프로필 또는 deploy Role 자격증명
scripts/aws/traffic-state.sh       # blue/green 가중치, SSM stable-color, consistent 여부
scripts/aws/resolve-resources.sh   # ALB DNS, 리스너, TG ARN suffix
```

## 1. 배포가 ROLLED_BACK 으로 끝났다

**신호** — 워크플로우 빨간색, Job Summary 첫 줄 `ROLLED_BACK(reason=…)`. 빨간색은 자동 롤백이 정상 동작한 결과다.

**확인**
1. Job Summary: 단계별 요청 수 · 5xx 비율 · p95 · 판정 사유, 롤백 소요 시간 두 가지(판정 → 원복, 판정 → 마지막 후보 응답).
2. artifact `canary-<run_id>`: `canary-report.json`, `load.csv` → `scripts/load/summarize.sh load.csv`.
3. 후보 버전 로그:
   ```bash
   aws logs filter-log-events --log-group-name /ecs/pda-coupon-api \
     --start-time <판정 시각 epoch ms - 300000> --filter-pattern '"ERROR"'
   ```
   v3 결함은 여기서 `NullPointerException` 으로 바로 드러났다.

**복구 확인** — `traffic-state.sh` 가 `consistent=true` 이고 stable 색이 100 인지 본다. 후보 서비스는 이미 desired 0 이다.

**다음 조치** — 결함 수정 후 **새 태그**로 릴리즈한다(IMMUTABLE ECR, 같은 태그 재사용 불가).

## 2. 트래픽 상태 불일치 (`consistent=false`)

**신호** — 새 배포가 prepare 단계에서 "트래픽 상태 불일치" 로 거부된다. 이전 실행이 중간에 취소·중단돼 가중치가 섞여 있거나 SSM 과 어긋난 상태다.

**확인**
```bash
scripts/aws/traffic-state.sh
aws elbv2 describe-listeners --listener-arns <listener_arn> \
  --query 'Listeners[0].DefaultActions[0].ForwardConfig.TargetGroups'
aws ssm get-parameter --name /pda/stable-color --query Parameter.Value --output text
```

**조치** — `canary.yml` `mode=recover` 실행(production 승인 필요). SSM 이 가리키는 색을 100% 로 맞추고 다른 색을 0 으로 축소한다.

> 검증 상태: `mode=recover` 는 구현됐지만 **AWS 에서 실행해 보지 않았다**. 처음 쓸 때는 실행 전후 `traffic-state.sh` 결과를 기록한다.

## 3. SSM 커밋 이후 단계(이전 색 축소)가 실패했다

**신호** — 워크플로우 실패인데 롤백 step 이 "승격이 이미 커밋됨 — 롤백하지 않음" 경고를 남겼다.

**의미** — 새 버전이 이미 100% 이고 SSM 도 새 색이다. 이전 색을 되돌리면 축소 중인 태스크로 트래픽을 보내 장애가 날 수 있으므로 **의도적으로 롤백하지 않는다**.

**확인 · 조치**
```bash
scripts/aws/traffic-state.sh                         # 새 색 100, consistent=true 확인
aws ecs describe-services --cluster pda-cluster --services pda-blue pda-green \
  --query 'services[].[serviceName,desiredCount,runningCount]'
```
이전 색이 desired 0 이 아니면 `scripts/aws/scale-service.sh --color <이전 색> --count 0 --wait`.

## 4. destroy 가 실패했고 과금이 이어진다

**신호** — `destroy.yml` 실패, Summary 에 남은 runtime 리소스 목록.

**조치 순서** (실제로 겪은 상황 → [troubleshooting #5](troubleshooting.md#5-destroy-워크플로우가-권한-부족으로-실패했다))
1. 과금을 먼저 멈춘다 — 로컬 관리자 자격증명(시연 당시 root 세션 — 권장하지 않음, IAM Identity Center 권장)으로:
   ```bash
   cd infra/terraform/runtime
   terraform init -backend-config=backend.hcl
   terraform destroy
   ```
2. 남은 것 확인:
   ```bash
   aws elbv2 describe-load-balancers --query 'length(LoadBalancers)'
   aws ecs list-clusters --query 'length(clusterArns)'
   aws ec2 describe-network-interfaces --query 'length(NetworkInterfaces[?Association.PublicIp])'
   ```
   모두 0 이어야 한다.
3. 원인(대개 권한 누락)을 `infra/terraform/bootstrap/iam_github.tf` 에 반영하고, 다음 시연에서 `destroy.yml` 로 다시 검증한다.

## 5. 예산 알림 메일을 받았다

**신호** — AWS Budgets `pda-monthly` 의 실제 80% 또는 예측 100% 초과 메일.

**확인**
```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'
aws ecs list-clusters
aws ec2 describe-network-interfaces --query 'NetworkInterfaces[?Association.PublicIp].[NetworkInterfaceId,Description]'
```

**조치** — runtime 이 남아 있으면 `destroy.yml`(또는 4번 절차). 시간당 과금 리소스는 ALB, Fargate 태스크, public IPv4 다. bootstrap(S3, ECR, IAM)은 사용량 과금이라 거의 0 이다.
