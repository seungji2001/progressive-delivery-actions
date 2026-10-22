# 1단계 프롬프트: 쿠폰 발급 API v1 + Dockerfile + 테스트

> `prompt-engineer` 에이전트가 고도화한 실행 프롬프트. 포트폴리오의 "AI 활용 기록"으로 보관한다.

## Role
너는 Spring Boot 3.x / Java 21 백엔드와 컨테이너 기반 배포(ECS Fargate + ALB)에 능숙한 시니어 엔지니어다. "배포 전략을 보여주기 위한 작고 관측 가능한 서비스"를 만드는 데 집중한다.

## Context
- 프로젝트: `progressive-delivery-actions` — GitHub Actions로 Blue-Green/카나리 배포(자동 롤백 포함)를 오케스트레이션하는 클라우드 엔지니어링 포트폴리오.
  - 레포 경로: `/Users/seungjibaek/Desktop/applyment/progressive-delivery-actions`
  - 설계 원본: 레포 루트 `README.md` — 먼저 읽는다.
- 이번 작업은 **1단계: `app/` 디렉토리에 쿠폰 발급 API v1 + Dockerfile + 테스트**를 만드는 것이다.
- 이 앱을 이후 단계에서 어떻게 쓰는지(지금 맞춰야 하는 인터페이스):
  - ALB 대상 그룹 헬스체크 → `GET /health/readiness`
  - 카나리 지표 게이트 → ALB `HTTPCode_Target_5XX_Count`, `TargetResponseTime`(p95). 따라서 **장애 주입은 반드시 앱이 실제 HTTP 5xx 상태 코드로 응답**해야 한다.
  - 모니터 페이지와 스모크 테스트 → 응답 헤더 `X-App-Version`, `GET /version`으로 어떤 버전이 응답했는지 식별
  - Blue 축소 시 다운타임 0 → graceful shutdown 필요
  - v2(정률 할인)와 v3(의도적 5xx)는 **새 이미지로 릴리즈**한다(기능 플래그 아님). v1 코드는 v2 변경이 작은 diff로 끝나는 구조여야 한다.
- 기술 스택: Java 21, Gradle(Kotlin DSL + Wrapper 포함), Spring Boot 최신 안정 버전 (실제 구현: 4.1.1 — Initializr 에서 3.x 지원 종료), spring-boot-starter-web, spring-boot-starter-validation, spring-boot-starter-actuator, JUnit 5 + AssertJ + MockMvc.
- 제약:
  - **DB 없음.** `ConcurrentHashMap` 기반 인메모리 저장소만 쓴다. JPA, Redis, Spring Security, Lombok, AWS SDK는 넣지 않는다(DTO는 Java record).
  - 비밀값이 필요 없는 구조로 만든다. 설정은 모두 환경변수로 덮어쓸 수 있어야 한다.
  - v2/v3 코드, Terraform, GitHub Actions, monitor 페이지는 이번 범위가 아니다.
  - 금액은 `long`(원 단위)으로 다루고 `double`은 쓰지 않는다.

## Task
1. **프로젝트 골격**
   - `app/` 아래 Gradle 프로젝트. 패키지: `com.portfolio.coupon`.
   - `springBoot { buildInfo() }`를 활성화한다.
   - `app/.dockerignore`.

2. **도메인 / API (v1 정액 할인)**
   - `DiscountPolicy` 인터페이스(`long discount(long orderAmount)`, `String type()`)와 v1 구현 `FixedAmountDiscountPolicy`.
   - 정책 값은 `@ConfigurationProperties("coupon")`로 받는다. 기본값: `fixed-amount=3000`, `min-order-amount=10000`. `@Validated`로 음수 금지.
   - `POST /coupons/issue`
     - 요청: `{ "userId": "u-1", "orderAmount": 25000 }` (userId는 필수이고 공백 불가, orderAmount는 양수)
     - 응답 `201 Created` + `Location: /coupons/{id}`. 본문: `couponId(UUID)`, `userId`, `discountType("FIXED")`, `orderAmount`, `discountAmount`, `finalAmount`, `issuedAt`, `appVersion`
     - 최소 주문금액 미만이면 `422`. 할인액이 주문금액을 넘으면 finalAmount를 0으로 하한 처리한다.
   - `GET /coupons/{id}`: 있으면 `200`, 없으면 `404`.
   - 에러 응답은 `@RestControllerAdvice` + Spring `ProblemDetail`(RFC 7807)로 통일한다. 검증 실패는 400, 미존재는 404, 정책 위반은 422, 예기치 못한 오류는 500.

3. **버전 노출**
   - `app.version` ← 환경변수 `APP_VERSION`. 없으면 build-info 버전을 쓴다. `app.commit` ← 환경변수 `GIT_SHA`(기본 `unknown`).
   - `GET /version` → `{ "version", "commit", "startedAt", "hostname" }`. hostname은 태스크 구분용이다.
   - `OncePerRequestFilter`로 **모든 응답(에러 응답과 장애 주입 응답 포함)**에 `X-App-Version` 헤더를 단다.

4. **헬스체크(Actuator)**
   - `management.endpoints.web.base-path=/`, `path-mapping.health=health`로 `GET /health`를 노출한다. `management.endpoint.health.probes.enabled=true`로 `/health/liveness`, `/health/readiness`를 활성화한다.
   - 노출 엔드포인트는 `health`만 둔다(env, beans 등 노출 금지).

5. **장애 주입(FAULT_RATE)**
   - `fault.rate` ← 환경변수 `FAULT_RATE`(0.0~1.0, 기본 0.0). 범위를 벗어나면 **기동 실패(fail-fast)**.
   - 적용 대상은 `/coupons/**`뿐이다. `/health/**`, `/version`은 **절대 제외**한다. 헬스체크까지 실패하면 ECS가 태스크를 교체해 버려서 "지표 게이트에 의한 롤백" 시연이 흐려진다.
   - 확률 판정용 난수 소스는 주입 가능한 빈(예: `DoubleSupplier`)으로 분리해 테스트에서 결정적으로 만든다.
   - 주입된 장애는 `500` + ProblemDetail(`type: .../fault-injected`)로 응답하고, WARN 로그에 `faultInjected=true`를 남긴다.

6. **운영 설정**
   - `server.shutdown=graceful`, `spring.lifecycle.timeout-per-shutdown-phase=20s`, 포트 8080.
   - 로그는 콘솔 한 줄 형식으로 남기고 버전을 포함한다. Spring Boot 3.4 이상이면 `logging.structured.format.console=ecs`를 써도 된다.

7. **Dockerfile (`app/Dockerfile`)**
   - 멀티 스테이지 빌드: `eclipse-temurin:21-jdk`에서 `./gradlew bootJar` → `eclipse-temurin:21-jre` 런타임.
   - Spring Boot jarmode로 레이어를 추출해 캐시 효율을 확보한다.
   - `ARG APP_VERSION`, `ARG GIT_SHA` → `ENV`로 전달한다(CI가 `--build-arg`로 주입).
   - non-root 사용자로 실행, `EXPOSE 8080`, `JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"`(Fargate 메모리 한도 대응).
   - Docker `HEALTHCHECK`는 넣지 않는다(ALB 대상 그룹 헬스체크를 사용). 런타임 이미지에 불필요한 패키지를 추가하지 않는다(이후 Trivy 스캔 대상).

8. **테스트**
   - 단위: `FixedAmountDiscountPolicy`(경계값: 최소금액 미만/동일/초과, 할인액 > 주문금액), 장애 주입 판정(rate 0 → 항상 통과, 1 → 항상 실패, stub 난수로 임계 경계), 인메모리 저장소.
   - `@WebMvcTest`: 201 + Location, 400(검증 실패), 404, 422, 모든 응답의 `X-App-Version` 헤더, `FAULT_RATE=1`일 때 `/coupons/**`는 500이고 `/version`은 200.
   - `@SpringBootTest(webEnvironment = RANDOM_PORT)` 스모크 1개: `/health/readiness` 200 UP, `/version` 응답 형식, 발급 후 조회 왕복.
   - `FAULT_RATE` 범위 밖 값으로 컨텍스트 기동이 실패하는지 검증(`ApplicationContextRunner` 등).

9. **문서**: `app/README.md`에 엔드포인트 표, 환경변수 표(`APP_VERSION`, `GIT_SHA`, `FAULT_RATE`, `COUPON_FIXED_AMOUNT`, `COUPON_MIN_ORDER_AMOUNT`), 로컬 실행/빌드 명령을 적고, 알려진 제약(인메모리라 태스크·버전 간 쿠폰 조회 불가 → 404)을 명시한다.

## Expected Output
- 생성/수정한 파일 목록(절대 경로)과 핵심 설계 결정 요약. 특히 "다음 단계(ALB 헬스체크, 지표 게이트, v2 diff)를 위해 맞춘 부분"을 따로 설명한다.
- 아래 검증을 실제로 실행하고 결과를 보고한다:
  ```bash
  cd app && ./gradlew clean test
  docker build --build-arg APP_VERSION=v1 --build-arg GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo local) -t coupon-api:v1 .
  docker run --rm -d -p 8080:8080 --name coupon-v1 coupon-api:v1
  curl -i localhost:8080/health/readiness
  curl -i localhost:8080/version
  curl -i -X POST localhost:8080/coupons/issue -H 'Content-Type: application/json' -d '{"userId":"u-1","orderAmount":25000}'
  docker rm -f coupon-v1
  docker run --rm -d -p 8080:8080 -e FAULT_RATE=0.5 --name coupon-fault coupon-api:v1
  for i in $(seq 1 100); do curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8080/coupons/issue -H 'Content-Type: application/json' -d '{"userId":"u-1","orderAmount":25000}'; done | sort | uniq -c
  curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/health/readiness   # 장애 주입 중에도 200이어야 함
  docker rm -f coupon-fault
  ```
- 기록할 수치: 이미지 크기, 컨테이너 기동~readiness UP 소요 시간, FAULT_RATE=0.5에서 측정된 5xx 비율. 포트폴리오 문서와 카나리 관찰 시간 산정에 쓴다.
- 커밋은 하지 않는다. 변경 사항만 남기고 보고한다.

## 다음 단계로 넘길 메모
- **이미지 아키텍처:** Apple Silicon 빌드는 arm64. 3단계에서 Fargate ARM64(Graviton) 채택 검토(비용 약 20% 절감 + 로컬 빌드 일치).
- **p95 게이트 시연:** 지연 주입(`FAULT_DELAY_MS`)이 필요하면 5단계에서 추가.
- **인메모리 404:** 가중치 라우팅 중 발급/조회가 다른 태스크로 가면 404 → 4xx라 게이트 영향 없음. 부하 스크립트는 POST 위주, 회고에 "의도된 제약"으로 기록.
- **graceful shutdown 정합성:** 20s 설정을 3단계 ALB `deregistration_delay`·ECS `stopTimeout`(각 30s 이상)과 맞춰야 다운타임 0.
