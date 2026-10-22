# 면접 예상 질문

짧은 답과 근거 문서. 수치는 모두 [results.md](results.md) 실측값이다.

**Q1. 왜 CodeDeploy 나 Argo Rollouts 를 쓰지 않았나?**
전환·판정·롤백이 파이프라인 코드에 드러나야 리뷰하고 테스트할 수 있다고 봤다. 게이트 로직을 종료 코드 규약으로 분리해 CloudWatch fixture 와 가짜 aws CLI 로 CI 에서 테스트한다. 대가는 직접 만든 코드의 유지 부담이다. → [architecture #4](architecture.md#4-설계-결정-전체)

**Q2. 실서비스에는 러너 부하가 없는데 fast guard 는 어떻게 하나?**
fast guard 는 10% 단계에서도 표본을 보장하려는 시연 설계다. 실서비스라면 실제 트래픽의 ALB 지표로 최소 표본까지 기다리고, 앱이 내보내는 에러율·지연 지표를 같이 본다. 표본 부족은 지금처럼 승격 거부로 처리한다. → README 회고 "프로덕션이라면"

**Q3. 1분 이내 롤백 목표는 달성했나?**
Blue-Green 은 23s(감지 15s + 원복 8s)로 달성했다. 카나리는 67~194s 로 미달이다. 10% 단계 후보는 약 1 rps 이고 ALB 지표가 60초 해상도라 표본을 모으는 데 시간이 걸린다. fast guard 창을 120s 로 넓힌 뒤 감지가 123s → 60s 였다(조건이 다른 1회씩의 비교라 단정은 못 한다). p95 는 표본 50건 대기가 의도된 설계다. → [results](results.md)

**Q4. 태스크가 public subnet 에서 public IP 를 받는데 안전한가?**
태스크 SG 인바운드는 ALB SG 에서 오는 8080 만 허용한다. 인터넷에서 태스크로 직접 들어올 경로가 없다. public IP 는 NAT 없이 ECR·Logs 에 나가기 위한 것이고, egress 도 443 만 연다. 운영 환경이라면 private subnet + VPC 엔드포인트를 쓴다. → [architecture #1](architecture.md#1-aws-네트워크--보안-경계)

**Q5. GitHub Actions 가 어떻게 AWS 에 인증하나? 포크 PR 은?**
OIDC 로 Role 을 assume 한다. Role 3개가 각각 sub 조건(브랜치·태그 / environment)으로 묶여 있고 `pull_request` 는 어떤 Role 에도 없다. sub 는 owner·repo 숫자 ID 가 든 immutable 형식이라 레포 이름 재사용으로 가로챌 수 없다. → [architecture #2](architecture.md#2-cicd--oidc-신뢰-경계)

**Q6. 승격 커밋 이후 실패하면?**
SSM 이 이미 새 색이면 롤백하지 않는다. 이전 색이 축소 중이라 되돌리면 오히려 장애가 난다. 가중치(실제 트래픽)와 SSM(커밋 포인터)을 분리한 이유다. → [ADR 0001](adr/0001-traffic-state.md), [runbook #3](runbook.md#3-ssm-커밋-이후-단계이전-색-축소가-실패했다)

**Q7. 테스트가 있는데 카나리가 왜 필요한가? (그 결함, 일부러 넣은 거죠?)**
맞다, 시연을 위해 심었다. 다만 환경변수 주입이 아니라 실제로 흔한 형태(조회 표의 누락 키 → NPE)로 만들었다. 이 결함은 단위 테스트와 스모크 테스트를 모두 통과했다. 테스트 사용자가 우연히 문제 없는 등급이었다. 사용자마다 다른 실제 트래픽에서만 드러났고, 카나리가 10% 노출에서 막았다(러너 부하 기준 5xx 1.25%). → [results #6](results.md#6-코드-결함-롤백-v300-녹화)

**Q8. Trivy 가 릴리즈를 막았을 때 왜 무시하지 않았나?**
CRITICAL 이고 수정 버전이 있었다. 게이트를 예외 처리하면 게이트가 의미를 잃는다. 이미 공개한 태그를 덮어쓰지 않고 패치 릴리즈를 냈다 — 롤백 대상 이미지가 바뀌면 안 되기 때문이다. → [troubleshooting #1](troubleshooting.md#1-trivy-게이트가-첫-릴리즈를-차단했다-critical-cve-3건)

**Q9. 비용은?**
runtime(ALB + Fargate ARM64 1~2 태스크 + public IPv4)은 시간당 약 $0.08~0.1. NAT 를 쓰지 않은 게 가장 큰 절감이다. 시연 후 destroy 하고, 끝난 뒤에는 bootstrap 까지 삭제했다. → [infra/terraform README](../infra/terraform/README.md)

**Q10. 다시 한다면 무엇을 바꾸겠나?**
판정 step 안에서 바로 원복(현재 원복 7~8s 의 대부분이 step 전환 대기), 색별 태스크 2개 이상, 알람 알림 채널 연결, recover 모드의 실제 장애 훈련.

**Q11. 시나리오마다 1회 실행인데 감지 시간을 믿을 수 있나?**
통계적 근거는 아니다. 각 수치는 "이 설계가 실제로 동작한다"는 증거이고, 분포를 말하려면 같은 조건 반복 측정이 필요하다. 그래서 README 에 범위와 단서를 함께 적었다.

**Q12. DB 스키마가 바뀌는 서비스라면 Blue-Green 을 어떻게 하나?**
이 앱은 인메모리라 다루지 않았다. 두 버전이 동시에 트래픽을 받으므로 스키마는 expand → migrate → contract 순서로, 구·신 버전이 모두 동작하는 상태를 유지하며 바꾼다. 롤백 시 되돌릴 수 없는 마이그레이션(컬럼 삭제 등)은 마지막 contract 단계로 미룬다. API 스키마를 버전 간 동일하게 유지한 것([app/README](../app/README.md))도 같은 원칙이다.

**Q13. infra Role 이 IAM Role 을 만들 수 있는데 권한 상승 위험은?**
처음 정책에는 경로가 있었다 — `pda-ecs-*` Role 에 아무 정책이나 붙여 태스크로 실행할 수 있었다. 독립 점검에서 발견해 인라인 정책 작성을 막고 관리형 정책은 ECS 실행 정책 하나만 붙일 수 있게 조건을 걸었다(`iam:PolicyARN`). 남은 위험과 대응은 [architecture #2](architecture.md#2-cicd--oidc-신뢰-경계).
