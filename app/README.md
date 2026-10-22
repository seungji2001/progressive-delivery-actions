# coupon-api

Blue-Green / 카나리 배포 시연용 쿠폰 발급 API. 기능은 최소로 두고, **어떤 버전이 응답했는지**와 **장애를 의도적으로 낼 수 있는지**에 집중한다.

- Java 21 · Spring Boot 4.1 · Gradle (Kotlin DSL)
- 인메모리 저장소 (DB 없음)

## 릴리즈

| 태그 | 할인 정책 | 비고 |
| --- | --- | --- |
| `v1.0.0` | 정액 할인 (`FixedAmountDiscountPolicy`, 기본 3,000원) | `COUPON_FIXED_AMOUNT` |
| `v2.0.0` | 정률 할인 (`PercentageDiscountPolicy`, 기본 10%, 최대 5,000원) | 정액 구현은 삭제됨 |
| `v2.1.0` | v2.0.0 과 동일 | `FAULT_DELAY_MS` 지연 주입 추가 (p95 게이트 시연용) |
| `v1.0.1` · `v2.0.1` · `v2.1.1` | 각각 v1.0.0 · v2.0.0 · v2.1.0 과 동일 | 내장 Tomcat 을 11.0.27 로 고정한 **패치 릴리즈** — 원래 태그는 Trivy CRITICAL CVE 로 배포 차단됨 ([troubleshooting #1](../docs/troubleshooting.md)). **AWS 에 배포한 것은 패치 릴리즈뿐이다** |
| `v3.0.0` | v2.1.1 + 회원 등급별 추가 할인 | **시연용으로 심은 결함**(등급 2 누락 → NPE). 브랜치 `release/v3`, main 에는 병합하지 않음 |

- 릴리즈 단위 = git 태그 = 이미지 태그 = `APP_VERSION`. 정책을 빌드 인자나 기능 플래그로 고르지 않는다. 롤백은 코드가 아니라 **이전 이미지**로 한다.
- **API 스키마는 버전 간에 동일하다**(필드명·타입 같고 값만 다름). 카나리 중에는 두 버전이 동시에 응답하므로 스키마 호환이 배포 안전성의 전제다.

## 엔드포인트

| Method | Path | 설명 | 장애 주입 대상 |
| --- | --- | --- | --- |
| POST | `/coupons/issue` | 쿠폰 발급. `201` + `Location` | O |
| GET | `/coupons/{id}` | 쿠폰 조회. 없으면 `404` | O |
| GET | `/version` | `version`, `commit`, `startedAt`, `hostname` | X |
| GET | `/health` | 전체 헬스 | X |
| GET | `/health/readiness` | **ALB 대상 그룹 헬스체크 경로** | X |
| GET | `/health/liveness` | 프로세스 생존 여부 | X |

- 모든 응답(에러 포함)에 `X-App-Version` 헤더가 붙는다.
- 오류는 RFC 7807 `ProblemDetail` 형식: 검증 실패 `400`, 미존재 `404`, 최소 주문금액 미만 `422`, 주입된 장애·예기치 못한 오류 `500`.

```bash
curl -X POST localhost:8080/coupons/issue \
  -H 'Content-Type: application/json' \
  -d '{"userId":"u-1","orderAmount":25000}'
```

## 환경변수

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `APP_VERSION` | build-info 버전 | 응답·헤더·로그에 노출할 버전. CI 가 `--build-arg` 로 주입 |
| `GIT_SHA` | `unknown` | 빌드 커밋 |
| `FAULT_RATE` | `0.0` | `/coupons/**` 에 500 을 낼 확률 (0.0~1.0). 범위 밖이면 기동 실패 |
| `FAULT_DELAY_MS` | `0` | `/coupons/**` 응답 지연(0~10000ms, v2.1.0 부터). 에러 주입과 독립. ALB idle timeout(60s)보다 훨씬 작게 제한해 연결 끊김(ELB 5xx)이 아니라 `TargetResponseTime` p95 로 관측되게 한다 |
| `COUPON_PERCENT` | `10` | 정률 할인 비율(1~100). v2 부터 |
| `COUPON_MAX_DISCOUNT_AMOUNT` | `5000` | 최대 할인 금액(원). v2 부터 |
| `COUPON_MIN_ORDER_AMOUNT` | `10000` | 최소 주문 금액(원) |

## 실행

```bash
# 테스트
./gradlew test

# 로컬 실행
./gradlew bootRun

# 이미지 빌드 / 실행
docker build --build-arg APP_VERSION=v1 --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t coupon-api:v1 .
docker run --rm -p 8080:8080 coupon-api:v1

# 장애 주입 (요청의 50% 가 500)
docker run --rm -p 8080:8080 -e FAULT_RATE=0.5 coupon-api:v1
```

## 배포 파이프라인을 위한 설계

| 항목 | 이유 |
| --- | --- |
| 장애 주입은 실제 HTTP 500 | 카나리 지표 게이트가 ALB `HTTPCode_Target_5XX_Count` 로 판정하기 때문 |
| `/health/**`, `/version` 은 장애(에러·지연) 주입 제외 | 헬스체크가 실패하면 ECS 가 태스크를 교체해 "지표 게이트에 의한 롤백" 시연이 흐려짐 |
| graceful shutdown 20s | ALB `deregistration_delay` / ECS `stopTimeout`(30s 이상)과 맞춰 다운타임 0 |
| `DiscountPolicy` 인터페이스 | v2(정률 할인) 릴리즈가 구현체 교체만으로 끝나도록 |
| 버전은 빌드 시점 주입 | 같은 이미지 = 같은 버전. 기능 플래그가 아닌 이미지 단위 릴리즈 |
| ECS 형식 구조화 로그 | CloudWatch Logs Insights 에서 `service.version`, `faultInjected` 로 필터링 |

## 알려진 제약

- 저장소가 인메모리라 태스크·버전 간에 쿠폰이 공유되지 않는다. 가중치 라우팅 중 발급과 조회가 다른 태스크로 가면 `404` 가 날 수 있다(4xx 라 지표 게이트에는 영향 없음, 의도된 제약).
- Apple Silicon 에서 빌드하면 `arm64` 이미지가 만들어진다. Fargate 는 `ARM64` 런타임으로 맞춘다.

## 측정값 (로컬, Apple Silicon / Docker Desktop)

| 항목 | 값 |
| --- | --- |
| 테스트 | 24개 통과 |
| 이미지 크기 | 약 135MB (arm64, 압축 기준) |
| 컨테이너 기동 → readiness UP | 약 3.9초 |
| `FAULT_RATE=0.5` 에서 POST 200회 | 201: 112회 / 500: 88회 (5xx 44%) |
| 장애 주입 중 readiness 50회 | 200: 50회 |
| SIGTERM 시 | `Commencing graceful shutdown` → `Graceful shutdown complete` |
