# 4단계 프롬프트: CI(ci.yml) + Blue-Green(blue-green.yml) + Destroy(destroy.yml)

> `prompt-engineer` 에이전트가 고도화한 실행 프롬프트. 포트폴리오의 "AI 활용 기록"으로 보관한다.

## 설계 결정 요약
- 승인은 "100% 전환 직전": job을 `prepare`(environment `preview`) / `switch`(environment `production`, 승인) 로 분리, 거절·취소 시 후보 비용을 막는 `cleanup` job.
- 전환 로직은 YAML이 아니라 `scripts/aws/*.sh` — 5단계 재사용, `smoke-test.sh`는 2단계 로컬 nginx로 사전 검증.
- arm64는 네이티브 `ubuntu-24.04-arm` 러너(QEMU 대비 수 배 빠름, public 레포 권장 이유).
- ECR IMMUTABLE → 태그 공간 분리(`vX.Y.Z` / `sha-*`), push 멱등화.

## Role
너는 GitHub Actions 보안(OIDC, 최소 권한 토큰, 액션 SHA 고정)과 무중단 배포 자동화에 능숙한 시니어 DevOps 엔지니어다. 파이프라인이 성공했을 때보다 **실패했을 때 무엇을 남기고 어떻게 원복하는지**를 먼저 설계한다.

## Context
- 먼저 `README.md`, `docs/prompts/01~03`, `infra/local/README.md`, `infra/terraform/README.md`를 읽는다.
- 이번 작업은 **`.github/workflows/ci.yml`, `blue-green.yml`, `destroy.yml`과 `scripts/aws/`**.
- 전제: 앱 인터페이스(1단계), `load.sh`/`summarize.sh`/`X-Target-Color`(2단계), `pda-*` 이름 규약·Role 3종·Environments `preview`/`production`/`infra`(3단계).
- GitHub Variables만 사용(Secrets 없음): `AWS_REGION`, `AWS_ROLE_ARN_CI`, `AWS_ROLE_ARN_DEPLOY`, `AWS_ROLE_ARN_INFRA`, `ECR_REPOSITORY`, `TF_STATE_BUCKET`. ARN은 변수로 두지 않고 이름으로 조회.
- 원칙: OIDC만, 최상위 `permissions: {}`, **서드파티 액션 전체 SHA 고정**, `aws elbv2 modify-listener` 직접 전환(전환을 숨기는 액션 금지), 수치 기록(승인 대기 시간 분리).
- 범위 밖: canary.yml, 지표 게이트, `FAULT_DELAY_MS`, v3.

## Task
1. **`scripts/aws/`**: `resolve-resources.sh`(이름 조회 → KEY=VALUE), `traffic-state.sh`(가중치 + SSM → `stable_color`, `candidate_color`, `consistent`; 불일치 시 배포 거부), `set-weights.sh`(modify-listener 후 반영 검증, epoch ms), `deploy-candidate.sh --color --image-tag [--env]`(ECR 존재 확인 → 새 revision → update-service desired 1 → `wait services-stable` → target health), `smoke-test.sh --base-url --color --expect-version`(**로컬 nginx로도 실행 가능**), `scale-service.sh`.
2. **`ci.yml`**: PR/main/tag `v*.*.*`/dispatch. `test` job(temurin 21, setup-gradle, `./gradlew test`, shellcheck, actionlint). `image` job(PR 제외, `ubuntu-24.04-arm`): 태그 결정 → buildx arm64 → **Trivy**(CRITICAL 실패, SARIF 업로드) → OIDC → ECR → 기존 태그면 skip → push → Summary.
3. **`blue-green.yml`**(dispatch: `image_tag`, `observe_seconds`=180, `fault_rate`="0", `scale_down_previous`=true). `concurrency: pda-traffic`(canary/destroy와 공유).
   - `prepare`(preview): traffic-state → no-op 판정 → deploy-candidate → smoke(실패 시 후보 0, "리스너 미변경" 명시).
   - `switch`(production, **승인**): 백그라운드 load → baseline 30s → candidate 100 → 관찰(후보 5xx > 1% 또는 연결 실패 ≥ 1 또는 TG 5xx 알람 ALARM이면 실패) → 실패: **즉시 stable 100 원복** + 롤백 소요 시간 → 성공: SSM 갱신(커밋 지점) → 이전 색 축소(부하 유지, 실패 0 증명). 원복은 `if: failure() || cancelled()`.
   - `cleanup`: 승인 거절/취소 시 리스너 후보 가중치 0 확인 후 축소.
   - Summary: `PROMOTED`/`ROLLED_BACK`/`ABORTED_BEFORE_SWITCH`/`NO_OP`, 타이밍 표(승인 대기 분리), summarize markdown, CSV artifact.
4. **`destroy.yml`**: `confirm == destroy-runtime`, environment `infra`, `terraform destroy`(runtime만), 잔여 리소스 태그 조회. **bootstrap은 절대 건드리지 않는다.**
5. **문서**: `.github/workflows/README.md` — 트리거, Environment/Variables, mermaid 흐름도, 실패 시나리오 표.

## Expected Output
- `actionlint`, `shellcheck`, 로컬 nginx로 `smoke-test.sh` 성공/실패 검증.
- AWS 절차(사용자): 태그 push → CI → runtime apply → `blue-green.yml image_tag=v2.0.0` → 승인 → PROMOTED → `fault_rate=0.5`로 ROLLED_BACK → destroy.
- 수치: 총 소요(승인 대기 제외/포함), 안정화, 전환 반영, 롤백 소요, 배포 중 실패 요청 수(목표 0).
- 커밋하지 않는다.

## 다음 단계로 넘길 메모
- 스크립트는 5단계에서 재사용, 관찰 판정은 `metric-gate.sh`로 교체.
- 상태 불일치는 지금은 거부, 5단계에서 recover 모드.
- `scale_down_previous=true` 이후 롤백은 재배포. 즉시 복귀 시연은 false로.
- 팁: 1인 레포는 production "Prevent self-review" off. private 레포의 required reviewer는 유료. concurrency 대기 실행은 1개만 유지된다.
