# 2단계 프롬프트: 로컬 docker compose + nginx 가중치로 Blue-Green/카나리 개념 검증 + v2(정률 할인)

> `prompt-engineer` 에이전트가 고도화한 실행 프롬프트. 포트폴리오의 "AI 활용 기록"으로 보관한다.

## 설계 결정 요약
- **v2는 별도 이미지:** 빌드 인자로 정책을 고르면 두 코드 경로가 모든 이미지에 들어가 컴파일 타임 기능 플래그가 된다. 대신 **git 태그 = 릴리즈 단위 = 이미지 태그** 원칙. `v1.0.0` 위에 v2 커밋(정률 정책만 Bean, 정액 구현 삭제) → `v2.0.0` 태그. `build-image.sh <git-ref>`가 `git worktree`로 해당 ref를 빌드해 재현 가능.
- 로컬 구성은 ALB를 흉내 낸다(upstream weight ↔ weighted TG, `X-Target-Color` ↔ 리스너 규칙, nginx JSON 로그 ↔ CloudWatch 지표).
- 부하/요약 스크립트는 4·5단계 러너에서도 쓰므로 출력 규격(CSV 컬럼, 종료 코드)을 이 단계에서 고정한다.

## Role
너는 컨테이너 기반 점진적 배포(Blue-Green, 카나리)를 설계해 본 시니어 플랫폼 엔지니어다. 클라우드에 올리기 전에 로컬에서 트래픽 전환·지표 판정·롤백 개념을 재현하고, 이후 AWS(ALB weighted target group) 구현과 1:1로 대응되는 구조를 만든다.

## Context
- 프로젝트: `progressive-delivery-actions` (`레포 루트`). 먼저 루트 `README.md`, `docs/prompts/01-coupon-api-v1.md`, `app/README.md`를 읽는다.
- **1단계 산출물(전제 인터페이스):** 포트 8080, `GET /health/readiness`, `GET /version`(version/commit/startedAt/hostname), 모든 응답에 `X-App-Version`, `FAULT_RATE`로 `/coupons/**`에 실제 HTTP 500, graceful shutdown 20s, Dockerfile `ARG APP_VERSION`/`ARG GIT_SHA`, arm64, 이미지에 curl·HEALTHCHECK 없음.
- **사전 조건:** `git tag -l v1.0.0`이 있고 `app/`에 커밋되지 않은 변경이 없어야 한다.
- 범위: (a) v2 정률 할인 코드, (b) 로컬 compose + nginx 가중치 환경, (c) 가중치 전환·Blue-Green·카나리 데모 스크립트, (d) 부하 생성·요약 스크립트, (e) `monitor/` 정적 페이지.
- **릴리즈 원칙:** 릴리즈 단위 = git 태그 = 이미지 태그 = `APP_VERSION`. 빌드 인자로 정책 선택 **금지**. v2 커밋은 `PercentageDiscountPolicy`를 유일한 `DiscountPolicy` Bean으로 만들고 `FixedAmountDiscountPolicy`와 그 테스트를 삭제한다. 롤백은 코드가 아니라 이전 이미지로 한다.
- **AWS 대응 관계:**
  | 로컬 | AWS (3~5단계) |
  | --- | --- |
  | nginx upstream `weight` | ALB 리스너 forward의 target group weight |
  | `X-Target-Color: blue/green` 헤더 라우팅 | ALB 리스너 규칙(http-header 조건) → 해당 색 TG |
  | nginx JSON 액세스 로그의 status/request_time | CloudWatch `HTTPCode_Target_5XX_Count`, `TargetResponseTime` |
  | `nginx -s reload` | `aws elbv2 modify-listener` |
  | `docker compose stop`(grace 30s) | ECS 태스크 종료(deregistration_delay, stopTimeout) |
- 범위 밖: Terraform, GitHub Actions, AWS CLI, v3, `FAULT_DELAY_MS`(5단계), 앱 CORS(모니터는 같은 오리진 프록시).
- 제약: 스크립트는 `bash` + `curl`(8.x, `%header{}`) + `jq` + `awk`만. `set -euo pipefail`, `--help`, shellcheck 무경고. 모니터는 빌드 도구·CDN 없는 순수 HTML/CSS/JS. 포트: nginx `8000`, blue `127.0.0.1:8081`, green `127.0.0.1:8082`.

## Task
1. **v2 정률 할인 (`app/`)**: `PercentageDiscountPolicy` — `orderAmount * percent / 100`(정수 절사), 상한 `max-discount-amount`, 최소 주문금액 동일, `type()="PERCENTAGE"`. 설정 `coupon.percent`(기본 10, 1~100), `coupon.max-discount-amount`(기본 5000), 환경변수 `COUPON_PERCENT`, `COUPON_MAX_DISCOUNT_AMOUNT`. `coupon.fixed-amount` 제거. **API 스키마는 v1과 완전히 같아야 한다**(카나리 중 두 버전 동시 응답). 경계값 테스트 추가.
2. **`scripts/local/build-image.sh <git-ref>`**: `git worktree add --detach`로 ref의 `app/` 빌드, `APP_VERSION=<ref>`, `GIT_SHA=$(git rev-parse --short <ref>)`, `--platform linux/arm64`, `trap`으로 worktree 정리. `--working-tree <version>` 모드는 `GIT_SHA=<HEAD>-dirty`.
3. **`infra/local/`**: `compose.yaml`(blue `${BLUE_TAG:-v1.0.0}`, green `${GREEN_TAG:-v2.0.0}` + `FAULT_RATE=${GREEN_FAULT_RATE:-0}`, nginx stable-alpine 버전 고정, `stop_grace_period: 30s`, `mem_limit: 1g`). nginx: `map $http_x_target_color` 헤더 라우팅, `/monitor/` 정적 서빙, **`proxy_next_upstream`에 `http_500` 추가 금지**(장애가 재시도로 가려짐), keepalive, JSON 액세스 로그(`.logs/`, gitignore). upstream 파일은 **디렉토리 단위 마운트**(단일 파일 bind mount는 `mv` 교체 시 inode 문제). 기본 blue 100 / green 0.
4. **`scripts/local/set-weights.sh --blue <n> --green <n>`**: 합 100 아니면 종료 2. 0%는 `down`. 임시 파일 → `mv` → `nginx -t` → 실패 시 복원·종료 1 → `nginx -s reload`. 전환 시각(epoch ms) 출력.
5. **부하·측정**: `scripts/load/load.sh --target --duration --concurrency [--rps] --out [--header]` — POST 위주, CSV `epoch_ms,http_code,app_version,latency_ms`, 연결 실패 `000`, SIGTERM 정상 종료. `scripts/load/summarize.sh <csv> [--since-ms] [--format text|markdown|json]` — 버전별 비율, 상태코드 분포, 5xx 비율, 연결 실패, p50/p95/p99.
6. **데모 시나리오**: `scripts/local/gate.sh --color --window --max-5xx-rate --max-p95-ms --min-requests` (종료 코드 **0 통과 / 10 임계 초과 / 11 표본 부족 / 2 오류**). `scripts/local/blue-green.sh <new-tag>`(비활성 색 재기동 → readiness → 헤더 스모크 → 100% 전환 → 관찰 → 실패 시 원복). `scripts/local/canary.sh <new-tag> [--steps 10,50,100]`(단계별 gate, 실패 시 즉시 stable 100 원복, 롤백 소요 시간 출력, 종료 1).
7. **`monitor/`**: 같은 오리진 `POST /coupons/issue` 반복, 최근 120초 1초 버킷 **버전별 비율 누적 영역 차트 + 5xx 비율 선**(canvas/SVG 직접), 누적 카운터, 최근 응답 20줄, 시작/정지, `?path=`, `?concurrency=`.
8. **문서**: `infra/local/README.md`(대응표, 실행 순서, 시나리오, 측정 결과). `.gitignore`에 `.logs/`, CSV 출력 경로.

## Expected Output
- 생성/수정 파일 목록과 핵심 결정.
- 검증 실행: `./gradlew clean test`, `build-image.sh v1.0.0`, `--working-tree v2.0.0`, shellcheck, compose up, (A) 부하 중 Blue-Green v1→v2 실패 0건, (B) 카나리 정상 승격, (C) `GREEN_FAULT_RATE=0.3` 카나리 자동 롤백, (D) 종료 순서 검증(weight 0 → stop은 실패 0 / weight 50에서 stop은 실패 발생).
- 기록할 수치: 가중치 반영 시간, 전환 중 실패 요청 수, 카나리 단계별 5xx/p95, 로컬 롤백 소요 시간, 시나리오 D 정상/반례 실패 건수.
- 커밋하지 않는다.

## 다음 단계로 넘길 메모
- 헤더 라우팅 `X-Target-Color: blue|green` → 3단계 ALB 리스너 규칙, 4단계 스모크.
- 종료 코드 규약 0/10/11/2 → 5단계 `metric-gate.sh`도 따른다.
- `load.sh` CSV 규격 → 4·5단계 다운타임 0 증명, fast guard 입력.
- 종료 순서 검증 결과 → 3단계 deregistration_delay/stopTimeout 산정 근거.
- 팁: nginx `max_fails`는 error/timeout만 세므로 500은 그대로 전달된다(ALB와 동일). 장시간 POST 부하 시 인메모리 저장소 증가는 "의도된 제약"으로 기록.
