# 5단계 프롬프트: 카나리(canary.yml) + 지표 게이트 + 자동 롤백 + FAULT_DELAY_MS

> `prompt-engineer` 에이전트가 고도화한 실행 프롬프트. 포트폴리오의 "AI 활용 기록"으로 보관한다.

## 설계 결정 요약
- **두 층 게이트:** ALB 지표는 60초 해상도 + 1~2분 지연 → 권위 판정은 CloudWatch 게이트(5xx 비율, p95, 최소 요청 수), 빠른 감지는 러너 부하 CSV 기반 fast guard. 롤백 시간은 "판정 → 원복 검증"과 "판정 → 마지막 후보 응답" 두 가지로 측정.
- 5xx 0건이면 데이터 포인트가 없으므로 0으로 취급. percentile은 기간 평균 불가 → 관찰 창 전체를 하나의 period로 조회.
- 승인 대기 중 악화 대비: 승인 후 100% 직전 게이트 재판정.
- 상태 저장: "리스너 = 진실 원천 + SSM = 커밋 포인터"를 ADR로 확정, `recover` 모드 추가.

## Role
너는 SRE 관점에서 점진적 배포의 판정 로직(표본 크기, 지표 지연, 오탐/미탐)을 설계하는 시니어 엔지니어다. 게이트가 "왜 통과했고 왜 실패했는지"를 사람이 Job Summary 한 장으로 이해할 수 있게 만든다.

## Context
- 먼저 `README.md`, `docs/prompts/01~04`, `infra/terraform/README.md`, `.github/workflows/README.md`를 읽는다.
- 이번 작업은 **`canary.yml`, `scripts/aws/metric-gate.sh`, 앱 `FAULT_DELAY_MS`, 상태 저장 ADR, recover 모드**.
- 전제: 4단계 `scripts/aws/*`, 2단계 `load.sh`/`summarize.sh`, 종료 코드 **0/10/11/2**, 3단계 TG 지표(차원 = ARN suffix), SSM, 1단계 `FAULT_RATE`.
- ADR(`docs/adr/0001-traffic-state.md`): 대안(리스너만 → 50/50에서 stable 판별 불가, S3 JSON → 경합·잠금, TG 태그 → 의미 분산)과 기각 사유.
- 게이트 기본값(Variables로 덮어쓰기): `GATE_MAX_5XX_RATE=0.01`, `GATE_MAX_P95_MS=500`, `GATE_MIN_REQUESTS=50`, `GATE_WINDOW_SECONDS=180`, `GATE_MAX_WAIT_SECONDS=420`, 단계 `10,50,100`.
- 범위 밖: v3·녹화(6단계), 문서(7단계), Argo/CodeDeploy, 알람 액션 기반 롤백.

## Task
1. **앱 `FAULT_DELAY_MS`(릴리즈 `v2.1.0`)**: 0~10000, 범위 밖 기동 실패, `/coupons/**`만, 에러와 독립, `Sleeper` 추상화로 테스트 무대기, ALB idle timeout 근거 README.
2. **`scripts/aws/metric-gate.sh`**: `--tg-suffix --lb-suffix --start --end` + 임계값, 오프라인 `--metrics-json`. `get-metric-data` 1회(RequestCount Sum, 5XX Sum, p95 period=창 전체). 5XX 없음=0, 요청 부족=11, 초과=10. JSON 한 줄 + markdown 표. `tests/fixtures/` 5종 + `test-metric-gate.sh`.
3. **`scripts/load/fast-guard.sh`**: CSV tail, 후보 버전 최근 30초 5xx 비율 초과 & 표본 ≥ 20 → 종료 10. 연결 실패 별도 카운트.
4. **`canary.yml`**(dispatch: `mode` deploy|recover, `image_tag`, `steps`=`10,50`, `fault_rate`, `fault_delay_ms`), `concurrency: pda-traffic`.
   - recover(production): 리스너를 SSM stable 100으로, 다른 색 0.
   - `prepare`(preview): traffic-state → deploy-candidate(후보에만 FAULT env) → smoke.
   - `canary`(preview): load + fast-guard 백그라운드 → 단계마다 가중치 → T+60s 이후 30초 간격 gate(0 진행 / 11 재시도, 최대 대기 초과 시 **표본 부족도 롤백** / 10 즉시 실패 / fast guard 종료 시 즉시 실패) → 단계 결과 JSON 누적.
   - `promote`(production, **승인**): 승인 후 게이트 재판정 → 100 → 최종 게이트 → SSM 갱신 → 이전 색 축소.
   - 자동 롤백(`if: failure() || cancelled()`): stable 100 → 롤백 소요 시간 2종 → 후보 0 → job 실패(Summary 첫 줄에 "정상적인 롤백 결과" 명시).
   - Summary: `PROMOTED`/`ROLLED_BACK(reason=5xx|p95|insufficient|fast-guard)`/`RECOVERED`, 단계별 표, mermaid `xychart-beta`, `canary-report.json`·CSV artifact.
5. **4단계 정리**: blue-green 관찰 판정을 metric-gate + fast-guard로 교체, 불일치 메시지에 recover 안내, 권한 최소 보강.

## Expected Output
- `./gradlew clean test`, actionlint, shellcheck, `test-metric-gate.sh`, 로컬 fast-guard 검증(GREEN_FAULT_RATE=0.3, 가중치 50 → 종료 10).
- AWS 시연(사용자): (1) v2.0.0 → v2.1.0 PROMOTED, (2) `fault_rate=0.2` ROLLED_BACK(5xx), (3) `fault_delay_ms=800` ROLLED_BACK(p95), (4) 취소 → 불일치 → recover.
- 수치: 단계별 요청 수/5xx/p95, 롤백 소요 2종, 총 소요, 연결 실패 수.
- 커밋하지 않는다.

## 다음 단계로 넘길 메모
- 6단계 v3는 FAULT 환경변수가 아니라 **코드 결함**으로 5xx를 내는 `v3.0.0` 이미지.
- 녹화 시 `monitor/`를 로컬 nginx 프록시(대상 = ALB DNS)로 같은 오리진 실행 + CloudWatch 대시보드 캡처.
- 팁: 10% 단계에서 최소 요청 수를 채울 rps를 역산(50건/120초 → 전체 약 4~5 rps 이상). TG 차원에 전체 ARN을 넣으면 빈 결과 → 표본 부족 오판. `HTTPCode_ELB_5XX_Count`도 참고 지표로 표시.
