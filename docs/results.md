# AWS 실측 결과 (2026-10-22, ap-northeast-2)

실제 AWS(ECS Fargate ARM64 + ALB)에서 GitHub Actions 워크플로우로 실행한 결과다. 모든 수치는 Actions 로그·Job Summary·러너 부하 CSV 에서 뽑았다.

- 이미지: `v1.0.1`(정액) · `v2.0.1`(정률) · `v2.1.1`(정률 + `FAULT_DELAY_MS`) — Tomcat CVE 패치 릴리즈 ([troubleshooting](troubleshooting.md#1-trivy-게이트가-첫-릴리즈를-차단했다-critical-cve-3건))
- 부하: GitHub 호스티드 러너(미국)에서 ALB(서울)로 `POST /coupons/issue`. 러너 측 지연 약 300ms 는 대륙 간 왕복 시간이고, 서버 측 p95 는 CloudWatch 기준 2~5ms 다.
- 게이트 기본값: 5xx 비율 ≤ 1%, p95 ≤ 500ms, 최소 요청 50, 단계별 최소 관찰 180s

## 요약

| # | 시나리오 | 결과 | 핵심 수치 |
| --- | --- | --- | --- |
| 1 | Blue-Green `v1.0.1 → v2.0.1` | **PROMOTED** | 요청 2,056건 / **실패 0** (전환 + 이전 색 drain 포함) |
| 2 | Blue-Green 후보에 `FAULT_RATE=0.5` | **ROLLED_BACK** | 전환 → 감지 **15s**, 감지 → 원복 **8s** |
| 3 | 카나리 후보에 `FAULT_RATE=0.2` | **ROLLED_BACK(fast-guard:5xx)** | 10% 단계에서 차단, 전체 5xx 1.89% |
| 4 | 카나리 후보에 `FAULT_DELAY_MS=800` | **ROLLED_BACK(p95)** | CloudWatch p95 **805ms** > 500ms, 10% 단계에서 차단 |
| 5 | 카나리 `v2.0.1 → v2.1.1` | **PROMOTED** | 10 → 50 → 승인 → 50 재판정 → 100, 요청 4,455건 / **실패 0** |
| 6 | 카나리 `v2.1.1 → v3.0.0` (**실제 코드 결함**, 주입 없음) | **ROLLED_BACK(fast-guard:5xx)** | 10% 전환 → 감지 **60s** → 원복 **7s** |

## 1. Blue-Green 승격

| 단계 | 시각 (UTC) | 소요 |
| --- | --- | --- |
| prepare (green 기동 → healthy → 스모크) | 05:19:42 → 05:23:05 | 3m23s |
| production 승인 대기 | 05:23:05 → 05:23:17 | 12s |
| switch (baseline 30s → 100% → 관찰 180s → 커밋 → blue drain) | 05:23:17 → 05:27:36 | 4m19s |

- CloudWatch 게이트: 후보 요청 1,074건, 5xx 0, **p95 5ms** → pass
- blue 축소(desired 0 → stable)는 **17s**. 이 동안 부하를 유지해 drain 중 실패 0건을 확인했다.

## 2. Blue-Green 롤백 (후보에만 `FAULT_RATE=0.5`)

```
05:32:57  listener weights: blue=100 green=0      ← 후보(blue, v1.0.1) 100% 전환
05:33:12  fast guard: samples 37, 5xx 19           ← 15s 만에 감지
05:33:20  listener weights: blue=0 green=100      ← 원복 (stable = green, v2.0.1)
05:33:26  마지막 후보 응답                           ← 사용자 영향 종료
```

- 사용자 영향 구간 **18.9s**, 전체 576건 중 5xx 71건. 원복 후 `traffic-state` = `consistent=true`.
- 감지 → 원복 8s 의 대부분은 GitHub Actions 의 step 전환 시간이다(실패 step 종료 → 롤백 step 시작). 원복 자체(`modify-listener` + 검증)는 1~2s.

## 3·4. 카나리 자동 롤백

| | 5xx 주입 (`FAULT_RATE=0.2`) | 지연 주입 (`FAULT_DELAY_MS=800`) |
| --- | --- | --- |
| 10% 적용 | 05:38:50 | 05:44:19 |
| 판정 | 05:40:53 **fast guard** (123s) | 05:47:26 **CloudWatch p95 805ms** (187s, 요청 57건) |
| 원복 | 05:41:00 (7s) | 05:47:33 (7s) |
| 사용자 영향 | 전체 847건 중 5xx 16건 (1.89%) | 5xx 0, 러너 p95 1,162ms |

**관찰**
- 같은 시점 CloudWatch 는 60초 창에 요청 3~4건만 집계했다(지표 수집 지연). 서버 측 지표만으로는 판정할 수 없는 구간을 클라이언트 측 fast guard 가 메웠다.
- 다만 fast guard 감지에도 **123s** 가 걸렸다. 10% 단계에서 후보는 약 1 rps 만 받는데 fast guard 창이 30s 라 최소 표본(20)을 채우기 어려웠다. → **개선**: 카나리에서는 fast guard 창을 120s 로 넓혔다 (`FAST_GUARD_WINDOW`, 오프라인 테스트 통과, AWS 재측정은 다음 시연에서).
- p95 롤백은 "표본 50건"을 채울 때까지 기다린 뒤 판정했다(57건 시점). 표본 없이 승격하지 않는다는 원칙과, 10% 단계의 낮은 트래픽이 맞물린 결과다.

## 5. 카나리 승격

| 단계 | 후보 요청 | 5xx | CloudWatch p95 | 판정 |
| --- | --- | --- | --- | --- |
| 10% | 58 | 0 | 4ms | pass (185s) |
| 50% | 416 | 0 | 3ms | pass (185s) |
| ── production 승인 ── | | | | |
| 50% 재판정 | 410 | 0 | 2ms | pass (184s) |
| 100% | 585 | 0 | 2ms | pass (185s) |

- 총 소요 **16m21s** (05:48:31 → 06:04:52). 단계마다 최소 관찰 180s + 지표 지연 60s 가 대부분이다.
- 승인 후 바로 100% 로 가지 않고 50% 에서 다시 판정했다 — 승인을 기다리는 동안 아무도 지표를 보지 않았기 때문이다.
- 러너 부하 합계 4,455건, 실패 0.

## 6. 실제 코드 결함 롤백 (`v3.0.0`, 녹화)

![canary v3 auto rollback](demo/canary-v3-auto-rollback.gif)

**결함** — v3 에 "회원 등급별 추가 할인"을 넣으면서 등급 보너스 표(`Map.of(0, 0L, 1, 500L, 3, 1000L)`)에 **등급 2 를 빠뜨렸다**. 등급 2 사용자는 `NullPointerException` → 500. 장애 주입(`FAULT_*`) 없이 코드 결함만으로 낸 장애다.

| 검사 | 결과 | 이유 |
| --- | --- | --- |
| 단위 테스트 | 통과 | 테스트 사용자 `u-1` 은 등급 1 |
| 스모크 테스트 | 통과 | `smoke` 는 등급 3 |
| Trivy | 통과 | 의존성 문제가 아님 |
| **카나리 10%** | **차단** | 실제 트래픽은 사용자마다 달라 약 25% 가 등급 2 |

```
07:28:47  SMOKE OK [green] v3.0.0                 ← 스모크는 통과
07:29:17  listener weights: blue=90 green=10      ← 10% 노출
07:30:17  step 10% FAILED: fast-guard             ← 60s 감지 (후보 21건 중 5xx 5건)
07:30:24  listener weights: blue=100 green=0      ← 7s 원복
```

- 러너 부하 480건 중 5xx 6건(1.25%) — 10% 노출이 영향 범위를 제한했다. 후보가 응답한 구간은 61s.
- fast guard 창을 30s → 120s 로 넓힌 뒤의 첫 AWS 측정: 감지 **123s → 60s**.
- 녹화는 로컬 nginx 프록시(`infra/local/monitor-proxy`)로 모니터 페이지를 ALB 와 같은 오리진에 띄우고 브라우저 트래픽(약 20 rps)을 함께 보냈다. 화면의 5xx 수치는 브라우저 트래픽 기준이다. 차트의 세로 공백은 브라우저 요청이 잠시 없던 1초 구간이다.
- 이 실행의 정리는 `destroy.yml` 로 했다 — 35 리소스 삭제 성공 (권한 수정 후 실제 삭제 경로 검증 완료).
- 실행: [39740352525](https://github.com/seungji2001/progressive-delivery-actions/actions/runs/39740352525) · destroy [39741066827](https://github.com/seungji2001/progressive-delivery-actions/actions/runs/39741066827)

## 인프라 수명주기

| 작업 | 소요 |
| --- | --- |
| runtime apply (35 리소스) | 153s |
| runtime destroy (35 리소스) | 193s |
| CI 이미지 빌드 + Trivy + ECR push (arm64 네이티브 러너) | 약 2~3분 |

시연 종료 후 bootstrap(S3 state, ECR, IAM Role, OIDC provider, 예산)까지 전부 삭제했다(2026-10-22). 다시 실행하려면 [infra/terraform/README.md](../infra/terraform/README.md) 의 적용 순서대로 bootstrap 부터 만든다.

비용: runtime 을 약 50분 운영 — ALB + Fargate ARM64 1~2 태스크 + public IPv4 기준 시간당 약 $0.08~0.1. 시연 직후 destroy 했다.

## 실행 링크

- Blue-Green 승격: [39727371342](https://github.com/seungji2001/progressive-delivery-actions/actions/runs/39727371342)
- Blue-Green 롤백: [39728202034](https://github.com/seungji2001/progressive-delivery-actions/actions/runs/39728202034)
- 카나리 5xx 롤백: [39728829745](https://github.com/seungji2001/progressive-delivery-actions/actions/runs/39728829745)
- 카나리 p95 롤백: [39729490949](https://github.com/seungji2001/progressive-delivery-actions/actions/runs/39729490949)
- 카나리 승격: [39730128028](https://github.com/seungji2001/progressive-delivery-actions/actions/runs/39730128028)

> 시연 중 `production`/`infra` 승인은 API 로 자동 승인했다(코멘트 `approved by automation (demo)`). 녹화용 시연에서는 Actions 화면에서 직접 승인한다.
