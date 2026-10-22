# 실제 AWS 적용 중 만난 문제와 해결

## 1. Trivy 게이트가 첫 릴리즈를 차단했다 (CRITICAL CVE 3건)

**상황** — 태그 `v1.0.0`, `v2.0.0`, `v2.1.0` 이미지를 CI 로 빌드하자 `image` job 이 Trivy 단계에서 실패했다.

```
org.apache.tomcat.embed:tomcat-embed-core 11.0.24
  CVE-2026-65182  CRITICAL  Security constraint bypass          fixed: 11.0.25
  CVE-2026-65905  CRITICAL  DIGEST authenticator replay bypass  fixed: 11.0.25
  CVE-2026-68525  CRITICAL  FORM authentication bypass          fixed: 11.0.25
```

Spring Boot 4.1.1 이 끌어오는 내장 Tomcat 이었고, 당시 Boot 4.1.x 최신 패치에도 수정 버전이 포함되지 않았다.

**판단**
- 게이트를 완화(`ignore`)하지 않는다. "CRITICAL + 수정 버전 존재" 는 차단 기준 그대로다.
- 이미 공개한 태그를 다시 쓰지 않는다. 릴리즈 태그는 불변이어야 롤백 대상이 흔들리지 않는다.

**해결**
- `build.gradle.kts` 에 `extra["tomcat.version"] = "11.0.27"` 로 Boot 관리 버전을 덮어썼다 (제거 조건을 주석으로 남김).
- 각 릴리즈 태그에서 같은 수정만 얹은 **패치 릴리즈** `v1.0.1`, `v2.0.1`, `v2.1.1` 을 만들었다 (각각 테스트 통과 확인).
- 로컬 Trivy 재스캔 CRITICAL 0 → CI 재빌드 통과 → ECR push.

**배운 점** — 공급망 스캔은 "통과용 체크"가 아니라 실제로 릴리즈를 막는 장치여야 의미가 있다. 이번에는 첫 배포 전에 막혔다.

## 2. OIDC AssumeRole 이 거부됐다 (immutable subject)

**상황** — Trivy 를 통과한 뒤 `configure-aws-credentials` 가 12회 재시도 끝에 실패했다.

```
Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

**원인** — 새로 만든 레포는 GitHub 의 **immutable subject** 형식을 쓴다.

```
$ gh api repos/seungji2001/progressive-delivery-actions/actions/oidc/customization/sub
{"use_default":true,"use_immutable_subject":true,
 "sub_claim_prefix":"repo:seungji2001@86452494/progressive-delivery-actions@1429147927"}
```

Role 신뢰 정책은 이름 기반 `repo:seungji2001/progressive-delivery-actions:ref:...` 만 허용하고 있었다.

**해결** — Terraform 변수 `github_oidc_sub_prefix` 를 추가해 신뢰 정책의 sub 를 immutable 형식으로 바꿨다. 비워 두면 기존 이름 기반 형식으로 동작한다.

**배운 점** — immutable 형식은 owner/repo **숫자 ID** 를 포함한다. 레포를 지우고 같은 이름으로 다시 만들거나 이름을 바꿔도 다른 레포가 이 Role 을 가로챌 수 없다. 장애였지만 결과적으로 더 안전한 신뢰 정책이 됐다.

## 3. 태그 재빌드 실행끼리 서로를 취소했다 (concurrency)

**상황** — `workflow_dispatch ref=v1.0.0`, `ref=v2.0.0`, `ref=v2.1.0` 을 연달아 실행하자 두 개가 `cancelled` 로 끝났다.

**원인** — 세 실행 모두 `github.ref` 가 `refs/heads/main` 이라 같은 concurrency 그룹이었다. GitHub 은 그룹당 대기 실행을 하나만 유지하고 새 실행이 오면 이전 대기 실행을 취소한다.

**해결** — 그룹 키에 재빌드 대상을 넣었다: `ci-${{ github.ref }}-${{ inputs.ref || 'push' }}`.

같은 동작이 트래픽 그룹(`pda-traffic`)에서는 **의도된 안전장치**다 — 배포 대기열에 오래된 요청이 쌓이지 않는다. 문서(`.github/workflows/README.md`)에 그 차이를 적어 두었다.

## 4. 러너와 로컬의 ShellCheck 버전 차이

로컬(0.11)에서는 경고가 없던 `A && B || C` 패턴을 러너의 ShellCheck 가 SC2015 로 보고했다. `if` 문으로 바꿔 해결했다. 린터 버전 차이로 CI 결과가 갈릴 수 있다는 점을 기록해 둔다.
