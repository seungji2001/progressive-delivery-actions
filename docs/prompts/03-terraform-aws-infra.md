# 3단계 프롬프트: Terraform AWS 인프라 (ALB weighted blue/green + ECS Fargate ARM64) + GitHub OIDC

> `prompt-engineer` 에이전트가 고도화한 실행 프롬프트. 포트폴리오의 "AI 활용 기록"으로 보관한다.

## 설계 결정 요약
- **스택 분리:** `bootstrap`(상시 유지: state 버킷, OIDC, IAM Role, ECR, Budgets — 비용 거의 0) / `runtime`(시연 후 destroy: VPC, ALB, ECS, CloudWatch). OIDC Role·ECR을 runtime과 함께 지우면 destroy.yml이 다음에 자기 자신을 실행할 권한을 잃는다.
- **NAT Gateway 미사용:** public subnet + Fargate public IP. 태스크 SG 인바운드를 ALB SG로만 제한.
- **드리프트 방지:** 워크플로우가 소유하는 값(리스너 가중치, 서비스 task_definition/desired_count)은 `ignore_changes`.
- **이름 기반 조회:** runtime 재생성 시 ARN이 바뀌므로 워크플로우는 `pda-*` 이름으로 조회. IAM 정책도 이름 기반 ARN 패턴.
- **활성 색 상태:** ALB 리스너 가중치 = 실제 트래픽(진실 원천), SSM `/pda/stable-color` = 마지막 승격 완료 색(커밋 포인터). 4단계에서도 쓰므로 3단계에서 생성.

## Role
너는 AWS 네트워킹·ECS·IAM에 능숙하고 비용과 최소 권한을 숫자와 근거로 설명하는 시니어 클라우드 엔지니어다. Terraform 코드는 리뷰어가 diff만 보고도 의도를 알 수 있게 명시적으로 작성한다.

## Context
- 먼저 `README.md`, `docs/prompts/01~02`, `infra/local/README.md`를 읽는다.
- 이번 작업은 **3단계: `infra/terraform/`**. **`terraform apply`는 절대 실행하지 않는다.** `fmt`/`validate`/`plan`까지만.
- 전제: 앱 8080, `/health/readiness`, graceful 20s, arm64, curl/HEALTHCHECK 없음, 장애는 실제 500. 스모크는 `X-Target-Color` 헤더. 이미지 태그 릴리즈 `vX.Y.Z`, main `sha-<short>`, ECR IMMUTABLE.
- 원칙: OIDC + `aws elbv2 modify-listener` 직접 제어. CodeDeploy/Argo/EKS/ECS 내장 blue-green 미사용. deployment controller `ECS`, 색별 서비스.
- **이름 규약(변경 금지):** prefix `pda` → ALB `pda-alb`, TG/서비스 `pda-blue`/`pda-green`, 클러스터 `pda-cluster`, family `pda-coupon-api`, 로그 `/ecs/pda-coupon-api`, ECR `pda-coupon-api`, SSM `/pda/stable-color`, 태스크 Role `pda-ecs-execution`/`pda-ecs-task`, GitHub Role `pda-gha-ci`/`pda-gha-deploy`/`pda-gha-infra`. 태그 `Project=progressive-delivery-actions`, `Stack=bootstrap|runtime`, `ManagedBy=terraform`.
- Terraform `>= 1.11`, AWS provider 최신 안정 메이저 고정, 외부 모듈 미사용, 관심사별 파일 분리.
- 비밀값·계정 ID 하드코딩 금지. `*.tfvars`, `backend.hcl` gitignore, `*.example`만 커밋.
- 범위 밖: Actions YAML, HTTPS/ACM/Route53(HTTP:80만, 한계로 명시), 오토스케일링, Container Insights, ALB 액세스 로그, WAF.

## Task
1. **Remote state**: S3(버전 관리, SSE-S3, Public Access Block, `prevent_destroy`, TLS 강제, lifecycle). **잠금은 S3 네이티브 `use_lockfile = true`**(DynamoDB 잠금은 1.11부터 deprecated). bootstrap은 로컬 state로 apply 후 `-migrate-state`. `runtime/backend.hcl.example`.
2. **GitHub OIDC + IAM**: `create_oidc_provider` 변수로 기존 provider 분기. 신뢰 정책 `aud=sts.amazonaws.com`, sub 제한:
   | Role | 허용 sub | 용도 |
   | --- | --- | --- |
   | `pda-gha-ci` | `ref:refs/heads/main`, `ref:refs/tags/v*` | ECR push |
   | `pda-gha-deploy` | `environment:preview`, `environment:production` | 배포·가중치 전환 |
   | `pda-gha-infra` | `environment:infra` | runtime destroy |
   PR에는 어떤 Role도 허용하지 않는다. 권한은 최소·이름 기반 ARN 패턴(deploy: ECS RegisterTaskDefinition/UpdateService/Describe*, ELB Describe*/ModifyListener(`listener/app/pda-alb/*`), CloudWatch GetMetricData/DescribeAlarms, SSM Get/Put(`/pda/stable-color`), ECR DescribeImages, `iam:PassRole`(`role/pda-ecs-*`, PassedToService 조건)).
3. **ECR**: IMMUTABLE, scan_on_push, lifecycle(`v*` 10개, `sha-*` 10개, untagged 1일), `force_delete=false`.
4. **Budgets**: 월 $10 기본, 실제 80% / 예측 100% 이메일.
5. **네트워크**: VPC + public subnet 2개(다른 AZ), IGW. **NAT·private subnet 없음.** 비용 비교표(NAT vs VPC 엔드포인트 vs 태스크 public IPv4)를 공식 가격 출처와 함께 README에. 태스크 SG는 ALB SG에서 8080만.
6. **ALB**: TG `target_type=ip`, 8080, 헬스체크 `/health/readiness`(interval 10, timeout 5, healthy/unhealthy 2), **`deregistration_delay=30`**. 리스너 HTTP:80 forward(blue 100 / green 0), **`ignore_changes=[default_action]`**. 리스너 규칙 priority 10/11: `X-Target-Color` 헤더 → 해당 TG.
7. **ECS**: 클러스터 `pda-cluster`(FARGATE만, Spot 제외). 태스크 정의 ARM64, cpu 512 / mem 1024, 이미지 `${initial_image_tag}`(기본 `v1.0.0`), `FAULT_RATE=0`, awslogs, **`stopTimeout=30`**. 서비스 `pda-blue`(1)/`pda-green`(0), public IP, grace 60s, min 100/max 200, circuit breaker rollback, **`ignore_changes=[task_definition, desired_count]`**. 종료 시간 정합성 표: weight 0 → deregistration 30s drain → SIGTERM → graceful 20s → stopTimeout 30s.
8. **상태 저장**: SSM `/pda/stable-color`(Standard, 초기 `blue`, `ignore_changes=[value]`).
9. **CloudWatch**: 색별 5XX(Sum, 60s)·p95(`extended_statistic="p95"`, 0.5s) 알람, `treat_missing_data=notBreaching`, ELB 5XX 알람, 대시보드 1개, 로그 보존 3일. ALB 지표 60초 해상도·수집 지연 명시.
10. **출력/문서**: `alb_dns_name`, `listener_arn`, TG ARN/suffix, 서비스명, 대시보드 URL. `infra/terraform/README.md`(스택 구조, 적용 순서, 비용·권한·종료 시간 표, 한계).

## Expected Output
- `terraform fmt -check -recursive`, bootstrap/runtime `init -backend=false && validate`. 자격증명이 있을 때만 plan. 고정비 리소스(ALB, public IPv4, Fargate) 보고.
- 커밋하지 않고 apply하지 않는다.

## 다음 단계로 넘길 메모
- 워크플로우는 이름으로 매번 조회. 정상 상태는 `stable=100 / other=0` + SSM 일치.
- 권한 부족 시 `iam_github.tf`를 고치고 PR diff로 남긴다.
- 5xx가 0이면 **데이터 포인트 자체가 없다.** TargetGroup 차원은 ARN suffix.
- runtime apply 전 `initial_image_tag` 이미지가 ECR에 있어야 한다.
