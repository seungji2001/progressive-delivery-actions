# progressive-delivery-actions

> **AWS 실측 결과**: [docs/results.md](docs/results.md) · **실제로 만난 문제**: [docs/troubleshooting.md](docs/troubleshooting.md) · 로컬 검증: [infra/local](infra/local/README.md)

> GitHub Actions 하나로 **Blue-Green 배포**와 **카나리 배포(자동 롤백 포함)** 를 오케스트레이션한 클라우드 엔지니어링 포트폴리오

## 1. 왜 이 주제인가

배포 전략 포트폴리오에서 평가받는 것은 "서비스 기능"이 아니라 **배포 파이프라인이 실패를 어떻게 다루는가**다.
그래서 서비스는 작고 단순하게 두고, 아래 세 가지를 눈으로 보이게 만드는 데 집중한다.

1. 트래픽이 v1 → v2 로 **단계적으로 넘어가는 과정** (0 → 10 → 50 → 100%)
2. 지표가 나빠졌을 때 **사람 개입 없이 자동 롤백**되는 과정
3. Blue-Green 에서 **즉시 전환 / 즉시 복귀** 가 가능한 구조

## 2. 데모 서비스: 쿠폰 발급 API

| 항목 | 내용 |
| --- | --- |
| 도메인 | 커머스 쿠폰 발급 (`POST /coupons/issue`, `GET /coupons/{id}`) |
| 선택 이유 | 커머스 실무 경험과 연결되고, "할인 로직 변경"이 배포 리스크의 현실적인 예시가 됨 |
| 버전 시나리오 | **v1** 정액 할인 → **v2** 정률 할인(정상 릴리즈) → **v3** 의도적 버그(5xx 증가, 롤백 시연용) |
| 관측 포인트 | `GET /version`, `GET /health`, 응답 헤더 `X-App-Version`, 에러율·p95 지연 |
| 장애 주입 | 환경변수 `FAULT_RATE` 로 에러율 조절 → 카나리 자동 롤백 재현 |

부가로 **트래픽 모니터 페이지**(정적 HTML)를 두어 요청을 계속 보내며 응답 버전 비율을 실시간 차트로 보여준다. (README GIF / 면접 시연용)

## 3. 아키텍처

**확정 스택:** AWS · Spring Boot 4.1 (Java 21, Gradle) · Terraform · GitHub Actions · 별도 레포

```
GitHub (push / tag)
   │
   ▼
GitHub Actions ──(OIDC, 장기 키 없음)──▶ AWS
   │  build → test → Trivy 스캔 → ECR push
   │
   ├─ blue-green.yml
   │     green 서비스 기동 → 스모크 테스트 → ALB 리스너 100% 전환
   │     → 관찰 시간 → blue 축소 (실패 시 리스너 원복)
   │
   └─ canary.yml
         ALB 가중치 10% → 지표 게이트 → 50% → 지표 게이트 → 100%
         지표 게이트 = CloudWatch 5xx 비율 / p95 지연 임계값
         임계 초과 시 가중치 0% 로 자동 롤백 + Job Summary 리포트

AWS
  ALB ─┬─ Target Group: blue  ── ECS Fargate Service (v현재)
       └─ Target Group: green ── ECS Fargate Service (v신규)
  ECR · CloudWatch(Alarms/Logs) · Terraform 으로 전부 IaC
```

### 설계 결정

- **GitHub Actions 가 트래픽 전환을 직접 수행**한다 (ALB weighted target group 을 `aws elbv2 modify-listener` 로 제어).
  CodeDeploy·Argo Rollouts 에 맡기지 않는 이유: "GitHub Actions를 활용한 배포 전략"이라는 주제에서 전환 로직이 파이프라인 코드에 그대로 드러나야 하기 때문.
- **ECS Fargate + ALB**: EKS 대비 비용·운영 부담이 낮고 블루/그린 타깃 그룹 구성이 단순함.
- **Environments + 승인**: `production` 환경에 required reviewer 를 걸어 100% 전환 직전 수동 승인 단계 시연.
- **비용 통제**: `terraform destroy` 워크플로우를 별도로 두어 시연 후 즉시 정리.

## 4. 디렉토리 계획

```
progressive-delivery-actions/
├── app/                     # 쿠폰 발급 API - Spring Boot 4.1 / Java 21 / Gradle (+ Dockerfile, 테스트)
├── monitor/                 # 버전 비율 실시간 모니터 페이지
├── infra/terraform/         # VPC, ALB, ECS, ECR, CloudWatch, OIDC Role
├── .github/workflows/       # ci.yml, blue-green.yml, canary.yml, destroy.yml
├── scripts/                 # 가중치 전환 / 지표 게이트 / 부하 생성 스크립트
└── docs/                    # 아키텍처 다이어그램, 시연 GIF, 회고
```

## 5. 진행 단계

| 단계 | 내용 | 산출물 |
| --- | --- | --- |
| 1 | 쿠폰 API v1 (Spring Boot) + Docker + 단위 테스트 | `app/` ✅ |
| 2 | 로컬 docker compose + nginx 가중치로 Blue-Green/카나리 개념 검증 | `infra/local/` ✅ |
| 3 | Terraform 으로 AWS 인프라 구성 + GitHub OIDC | `infra/terraform/` ✅ AWS 적용 |
| 4 | CI + Blue-Green 워크플로우 | `.github/workflows/` ✅ AWS 실측 |
| 5 | 카나리 워크플로우 + 지표 게이트 + 자동 롤백 | `canary.yml` ✅ AWS 실측 |
| 6 | v3 장애 주입 → 자동 롤백 시연 녹화 | `docs/` GIF |
| 7 | 포트폴리오 문서화 (문제 → 설계 → 결과 → 회고) | README |

## 6. 포트폴리오에 남길 수치

- 배포 1회 소요 시간, 롤백 소요 시간 (목표: 자동 롤백 1분 이내)
- 카나리 단계별 에러율 / p95 지연 그래프
- 다운타임 0 증명 (배포 중 부하 테스트 실패 요청 수)
