# Terraform: AWS 인프라

ALB weighted target group(blue/green) + ECS Fargate ARM64 + GitHub OIDC. **트래픽 전환은 Terraform 이 아니라 GitHub Actions 가 한다.** Terraform 은 무대만 만든다.

## 스택 구조

```
infra/terraform/
├── bootstrap/   상시 유지 (비용 ≈ 0)
│   ├── state.tf        S3 state 버킷 (버전관리, SSE-S3, TLS 강제, prevent_destroy)
│   ├── iam_github.tf   GitHub OIDC provider + Role 3개 (ci / deploy / infra)
│   ├── ecr.tf          pda-coupon-api (IMMUTABLE, scan_on_push, lifecycle)
│   └── budget.tf       월 예산 알림
└── runtime/     시연 후 destroy
    ├── network.tf      VPC, public subnet ×2, IGW, SG (NAT 없음)
    ├── alb.tf          ALB, TG blue/green, 가중치 리스너, X-Target-Color 규칙
    ├── ecs.tf          클러스터, 태스크 정의(ARM64), 서비스 pda-blue / pda-green, 로그 그룹(3일)
    ├── state.tf        SSM /pda/stable-color (커밋 포인터)
    └── monitoring.tf   색별 5xx·p95 알람, ELB 5xx 알람, 대시보드
```

**왜 두 스택인가:** OIDC Role 과 ECR 을 runtime 과 함께 지우면 `destroy.yml` 이 다음 번에 자기 자신을 실행할 권한을 잃고, 롤백 대상 이미지도 사라진다.

## 적용 순서

```bash
# 0) 로컬 관리자 자격증명 (root 사용 금지. IAM Identity Center 프로필 권장)
aws sso login --profile <admin-profile>; export AWS_PROFILE=<admin-profile>

# 1) bootstrap — 로컬 state 로 최초 apply
#    state 버킷이 아직 없으므로 versions.tf 의 `backend "s3" {}` 를 먼저 주석 처리한다 (# backend "s3" {})
cd infra/terraform/bootstrap
cp bootstrap.tfvars.example bootstrap.tfvars   # github_owner, github_oidc_sub_prefix, state_bucket_name, email 수정
terraform init
terraform plan  -var-file=bootstrap.tfvars
terraform apply -var-file=bootstrap.tfvars

# 2) bootstrap state 를 S3 로 이전
#    versions.tf 의 backend 블록 주석을 다시 해제한 뒤 (레포에는 해제된 상태로 커밋돼 있다)
terraform init -migrate-state \
  -backend-config="bucket=<state_bucket_name>" -backend-config="key=bootstrap/terraform.tfstate" \
  -backend-config="region=ap-northeast-2" -backend-config="use_lockfile=true" -backend-config="encrypt=true"

# 3) terraform output 값을 GitHub Variables 에 등록
#    AWS_REGION, AWS_ROLE_ARN_CI, AWS_ROLE_ARN_DEPLOY, AWS_ROLE_ARN_INFRA, ECR_REPOSITORY, TF_STATE_BUCKET

# 4) CI 로 릴리즈 이미지를 ECR 에 push: gh workflow run ci.yml -f ref=v1.0.1 (v2.0.1, v2.1.1 동일)
#    v1.0.0/v2.0.0/v2.1.0 은 Trivy CRITICAL 로 차단됨 → 패치 릴리즈 사용 (docs/troubleshooting.md #1)

# 5) runtime
cd ../runtime
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
terraform plan  -out=tfplan
terraform apply tfplan
```

이후 배포는 `blue-green.yml` / `canary.yml`, 정리는 `destroy.yml` (runtime 만 삭제).

## 설계 결정

| 결정 | 이유 |
| --- | --- |
| 리스너 `ignore_changes = [default_action]` | 가중치는 워크플로우가 소유. 없으면 다음 plan 이 트래픽을 초기값으로 되돌린다 |
| 서비스 `ignore_changes = [task_definition, desired_count]` | 이미지·태스크 수도 워크플로우가 소유 |
| 이름 규약 `pda-*` + 이름 조회 | runtime 을 재생성하면 ARN 이 바뀐다. 워크플로우는 ARN 을 저장하지 않고 매번 이름으로 찾는다 |
| SSM `/pda/stable-color` | 리스너 가중치 = 실제 트래픽(진실 원천), SSM = 마지막 승격 완료 색(커밋 포인터). 50/50 같은 중간 상태에서도 stable 을 판별할 수 있고, 두 값이 어긋나면 중단된 배포로 감지한다 |
| S3 네이티브 잠금 (`use_lockfile`) | DynamoDB 잠금은 Terraform 1.11 부터 deprecated. 테이블이 필요 없다 |
| ECS deployment controller = `ECS` | CodeDeploy·ECS 내장 blue/green 을 쓰면 전환 로직이 파이프라인 밖으로 숨는다 |
| FARGATE 만 (Spot 제외) | Spot 중단은 시연 재현성을 해친다 |
| ARM64 | 로컬(Apple Silicon)·CI(`ubuntu-24.04-arm`) 빌드와 일치, x86 대비 약 20% 저렴 |
| 외부 모듈 미사용 | 전환 구조(가중치 리스너, 색별 TG/서비스)가 코드에 그대로 드러나야 한다 |

## 비용

NAT Gateway 를 쓰지 않는 것이 핵심이다. 아래 단가는 서울 리전 기준 참고값이며, apply 전에 공식 가격 페이지에서 다시 확인한다.
([ALB](https://aws.amazon.com/elasticloadbalancing/pricing/) · [Fargate](https://aws.amazon.com/fargate/pricing/) · [VPC/NAT/IPv4](https://aws.amazon.com/vpc/pricing/))

### 인터넷 경로 선택지 (태스크 → ECR / CloudWatch Logs)

| 방식 | 과금 구조 | 시간당 (대략) | 채택 |
| --- | --- | --- | --- |
| NAT Gateway | 시간당 고정비 + GB당 처리비, AZ마다 | 약 $0.06 × AZ 수 + 데이터 | X |
| VPC 인터페이스 엔드포인트 (ecr.api, ecr.dkr, logs) | 엔드포인트 × AZ 수 시간당 | 약 $0.013 × 3 × 2 = $0.08 | X |
| 태스크 public IPv4 | IP당 시간당 | 약 $0.005 × 태스크 1~2개 | **O** |

### 시연 1시간 기준 (runtime)

| 리소스 | 수량 | 비고 |
| --- | --- | --- |
| ALB | 1 | 시간당 고정비 + LCU |
| ALB public IPv4 | 2 (AZ당 1) | |
| Fargate ARM64 0.5 vCPU / 1 GB | 1~2 태스크 | 카나리 중에만 2개 |
| 태스크 public IPv4 | 1~2 | |
| CloudWatch 알람 5개, 대시보드 1개, 로그 3일 보존 | | 무료 범위 근처 |

합계는 시간당 약 $0.1 미만 수준이다. **시연이 끝나면 바로 `destroy.yml` 을 실행한다.** bootstrap(S3, ECR, IAM, Budgets)은 사용량 기반이라 거의 0 이다.

## 권한 (GitHub OIDC Role)

| Role | 허용 sub | 권한 |
| --- | --- | --- |
| `pda-gha-ci` | `ref:refs/heads/main`, `ref:refs/tags/v*` | ECR push (해당 리포지토리만) |
| `pda-gha-deploy` | `environment:preview`, `environment:production` | 태스크 정의 등록, `pda-*` 서비스 업데이트, `pda-alb` 리스너 수정, 지표 조회, SSM 포인터, `pda-ecs-*` PassRole |
| `pda-gha-infra` | `environment:infra` | runtime 스택 리소스 + state `runtime/*` 키. `pda-ecs-*` Role 에는 ECS 실행 정책만 붙일 수 있고 인라인 정책은 쓸 수 없다(권한 상승 방지). 나머지 넓은 범위는 environment 승인으로 보완 |

- `pull_request` 이벤트에는 어떤 Role 도 허용하지 않는다(포크 PR 이 AWS 에 접근하지 못함).
- job 에 `environment:` 가 있으면 OIDC 토큰의 sub 가 `<prefix>:environment:<name>` 형식이 된다.
- `<prefix>` 는 레포 설정에 따라 이름 기반 `repo:<owner>/<repo>` 또는 **immutable** `repo:<owner>@<owner_id>/<repo>@<repo_id>` 다. 이 레포는 immutable 형식이다 — `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` 의 `sub_claim_prefix` 를 `bootstrap.tfvars` 의 `github_oidc_sub_prefix` 에 넣는다.

## 종료 시간 정합성 (다운타임 0)

| 순서 | 설정 | 값 |
| --- | --- | --- |
| 1. 리스너 weight 0 | 워크플로우 | 새 요청 차단 |
| 2. 등록 해제 drain | TG `deregistration_delay` | 30s |
| 3. SIGTERM → graceful shutdown | Spring `timeout-per-shutdown-phase` | 20s |
| 4. 강제 종료 | 컨테이너 `stopTimeout` | 30s |

조건: `stopTimeout(30) > graceful(20)`, `deregistration_delay(30) ≥ 가장 긴 요청 + 여유`. 로컬 검증(2단계 시나리오 D)에서 "가중치 0 → 정지" 순서는 실패 0건이었다.

## 지표 관련 주의

- ALB 지표는 **60초 해상도**이고 수집 지연이 1~2분 있다 → 5단계 게이트의 관찰 창을 그만큼 길게 잡는다.
- `HTTPCode_Target_5XX_Count` 는 5xx 가 0이면 **데이터 포인트 자체가 없다** → 게이트는 "없음 = 0" 으로 처리해야 한다.
- TargetGroup 차원 값은 전체 ARN 이 아니라 `targetgroup/pda-green/<id>` 형식의 **ARN suffix** 다.

## 정적 검사

```bash
terraform fmt -check -recursive
(cd bootstrap && terraform init -backend=false && terraform validate)
(cd runtime   && terraform init -backend=false && terraform validate)
docker run --rm -v "$PWD":/src aquasec/trivy:0.70.0 config --severity HIGH,CRITICAL /src
```

Trivy 결과: 조치 1건(`drop_invalid_header_fields = true`), 수용 4건은 코드에 `#trivy:ignore` 와 사유를 남겼다.

| ID | 내용 | 판단 |
| --- | --- | --- |
| AWS-0052 | ALB invalid header 미차단 | **조치** |
| AWS-0053 | 공개 ALB | 수용 — 데모 목적, 러너가 접근해야 함 |
| AWS-0054 | HTTPS 미사용 | 수용 — 도메인·ACM 범위 밖, 민감 데이터 없음 |
| AWS-0104 | 태스크 egress 0.0.0.0/0:443 | 수용 — NAT·엔드포인트 없이 AWS 퍼블릭 엔드포인트 접근 필요 |
| AWS-0132 | state 버킷 CMK 미사용 | 수용 — SSE-S3 충분, CMK 월 고정비 |

## 알려진 한계

- HTTP:80 만 제공 (HTTPS/Route53 없음).
- `X-Target-Color` 헤더로 누구나 비활성 색을 직접 호출할 수 있다 (스모크 테스트용, 데모 범위에서 허용).
- 오토스케일링, Container Insights, ALB 액세스 로그, WAF 는 범위 밖.
