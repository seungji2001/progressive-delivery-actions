# 로컬 개념 검증: nginx 가중치로 Blue-Green / 카나리

AWS 에 올리기 전에 트래픽 전환 · 지표 판정 · 롤백을 로컬에서 재현한다. 구조는 3~5단계 AWS 구현과 1:1 로 대응한다.

## AWS 대응 관계

| 로컬 | AWS (3~5단계) |
| --- | --- |
| nginx `:8000` | ALB `:80` |
| `blue` / `green` 컨테이너 | ECS 서비스 `pda-blue` / `pda-green` |
| upstream `weight` (0% 는 `down`) | 리스너 forward 의 target group weight |
| `X-Target-Color: blue/green` 헤더 라우팅 | 리스너 규칙(http-header) → 해당 색 TG |
| `scripts/local/set-weights.sh` (`nginx -s reload`) | `aws elbv2 modify-listener` |
| nginx JSON 액세스 로그 (`status`, `request_time`, `app_version`) | `HTTPCode_Target_5XX_Count`, `TargetResponseTime` |
| `scripts/local/gate.sh` | `scripts/aws/metric-gate.sh` (5단계) |
| `stop_grace_period: 30s` | ECS `stopTimeout` 30s |
| `proxy_next_upstream off` | ALB 는 실패 요청을 다른 대상으로 재시도하지 않음 |

## 실행

```bash
# 0) 릴리즈 태그로 이미지 빌드 (git worktree 로 해당 태그를 체크아웃해 빌드 → 재현 가능)
scripts/local/build-image.sh v1.0.0
scripts/local/build-image.sh v2.0.0

# 1) 환경 기동: blue=v1.0.0 100% / green=v2.0.0 0%
scripts/local/up.sh

# 2) 모니터 (브라우저): http://localhost:8000/monitor/

# 3) 시나리오
scripts/local/blue-green.sh v2.0.0 --observe 20 --scale-down    # A. Blue-Green
scripts/local/up.sh && scripts/local/canary.sh v2.0.0           # B. 카나리 정상 승격
scripts/local/up.sh && scripts/local/canary.sh v2.0.0 --fault-rate 0.3   # C. 카나리 자동 롤백

# 정리
docker compose -f infra/local/compose.yaml down
```

- 이미지 태그와 장애 주입 값은 `infra/local/.env` 에 저장된다(스크립트가 관리, gitignore).
- `blue-green.sh` / `canary.sh` 는 자체 부하(약 35~50 rps)를 만들고 끝에 요약을 출력한다. 부하 CSV 와 nginx 로그는 `infra/local/.logs/` 에 남는다.

## 스크립트 규약 (4·5단계에서 그대로 재사용)

| 스크립트 | 규약 |
| --- | --- |
| `scripts/load/load.sh` | CSV `epoch_ms,http_code,app_version,latency_ms`. 연결 실패는 `000` |
| `scripts/load/summarize.sh` | `--format text\|markdown\|json`. markdown 은 Job Summary 용 |
| `scripts/local/gate.sh` | 종료 코드 **0 통과 / 10 임계 초과 / 11 표본 부족 / 2 오류** |
| 카나리 판정 | 표본 부족(11)도 롤백. 증거 없이 승격하지 않는다 |

## 측정 결과 (2026-10-22, Apple Silicon · Docker Desktop)

### A. Blue-Green v1.0.0 → v2.0.0 (부하 중 전환 + 이전 색 정지)

| 항목 | 값 |
| --- | --- |
| 후보 기동 → readiness | 7.9s |
| 시작 → 100% 전환 | 13.7s |
| 총 소요 | 37.7s |
| 요청 / 실패 | **893건 / 0건** (5xx 0, 연결 실패 0) |
| 버전 분포 | v1.0.0 12.8% → v2.0.0 87.2% |

### B. 카나리 정상 승격 (window 20s)

| 단계 | 후보 요청 | 5xx | p95 | 판정 |
| --- | --- | --- | --- | --- |
| 10% | 71 | 0 | 18ms | pass |
| 50% | 227 | 0 | 35ms | pass |
| 100% | 708 | 0 | 8ms | pass |

총 69.6s, 전체 2,098건 중 실패 0건.

### C. 카나리 자동 롤백 (`FAULT_RATE=0.3` 을 후보에만 주입)

| 항목 | 값 |
| --- | --- |
| 판정 | 10% 단계에서 후보 73건 중 5xx 18건 (24.7%) → fail |
| **롤백 소요 (판정 → 가중치 원복)** | **618ms** |
| 판정 → 마지막 후보 응답 | 676ms |
| 사용자 영향 | 전체 958건 중 5xx 19건 (1.98%) — 10% 카나리로 영향 범위 제한 |

### D. 종료 순서 검증 (부하 중 green 컨테이너 정지)

| 순서 | 실패 |
| --- | --- |
| 가중치 0 → 정지 (정상) | 0건 / 441건 |
| 가중치 50 상태에서 정지 (반례) | 502 1건 / 521건 |

반례의 실패가 1건에 그친 이유는 nginx 의 passive health check(`max_fails=1`)가 첫 실패 직후 해당 서버를 제외하기 때문이다. **ALB 는 active health check(10s × 2회)로 대상을 제외하므로 같은 상황에서 실패가 더 길게 이어진다.** 그래서 AWS 에서도 "가중치 0 → deregistration drain → 정지" 순서를 지킨다.

## 알려진 차이 · 제약

- 가중치 반영은 `nginx -s reload` 직후다. ALB 의 `modify-listener` 도 수 초 안에 반영되지만 CloudWatch 지표는 60초 해상도라 5단계 게이트는 관찰 창을 더 길게 잡는다.
- 저장소가 인메모리라 버전 간 쿠폰 조회가 안 된다. 부하는 POST 만 보낸다(의도된 제약).
