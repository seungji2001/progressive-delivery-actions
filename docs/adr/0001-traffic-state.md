# ADR 0001: 활성 색(트래픽 상태) 저장 방식

- 상태: 채택 (2026-10-22)
- 관련: `infra/terraform/runtime/state.tf`, `scripts/aws/traffic-state.sh`, `canary.yml mode=recover`

## 배경

Blue-Green·카나리 워크플로우는 시작할 때 "지금 어느 색이 stable 인가"를 알아야 한다. 또 배포가 도중에 끊기면(러너 장애, 승인 대기 중 취소, 사람이 Cancel) 가중치가 50/50 같은 중간 상태로 남을 수 있는데, 다음 실행이 이를 감지하지 못하면 잘못된 색을 stable 로 보고 배포를 덮어쓴다.

## 결정

두 값을 함께 쓴다.

| 값 | 의미 | 갱신 시점 |
| --- | --- | --- |
| **ALB 리스너 가중치** | 실제 트래픽 상태 (진실 원천) | 매 단계 `set-weights.sh` |
| **SSM `/pda/stable-color`** | 마지막으로 승격을 **마친** 색 (커밋 포인터) | 성공의 마지막 단계에서만 1회 |

- 정상 상태: stable 색 100 / 다른 색 0 이고 SSM 과 일치 → `consistent=true`.
- 그 외는 중단된 배포 → 새 배포는 **거부**하고 `canary.yml mode=recover` 로 SSM 색 100% 로 되돌린다.
- 롤백 단계는 SSM 을 먼저 본다. SSM 이 이미 후보 색이면(커밋 이후 실패) 롤백하지 않는다 → 이전 색이 이미 축소된 상태에서 되돌려 장애를 만드는 일을 막는다.

## 검토한 대안

| 대안 | 기각 이유 |
| --- | --- |
| 리스너 가중치만 사용 | 50/50 에서는 어느 쪽이 stable 인지 판별할 수 없다. 중단 감지도 불가 |
| S3 JSON 파일 | 동시 쓰기 경합과 잠금을 직접 구현해야 한다. 워크플로우 `concurrency` 가 있어도 수동 조작과 경합 |
| TG / 서비스 태그 | 상태가 여러 리소스에 흩어져 원자적으로 읽고 쓰기 어렵다 |
| DynamoDB 테이블 | 조건부 쓰기는 강력하지만 이 규모에는 과하고, runtime destroy 와 수명 관리가 복잡해진다 |

## 결과

- 추가 비용 없음 (SSM Standard 파라미터 무료).
- Terraform 은 SSM 값을 `ignore_changes = [value]` 로 무시 → 워크플로우가 소유.
- deploy Role 은 이 파라미터 하나에만 Get/Put 권한을 가진다.
