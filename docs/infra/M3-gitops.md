# M3 — GitHub Actions + ArgoCD (GitOps)

앱 코드를 push하면 이미지 빌드부터 클러스터 반영까지 사람 손 없이 진행된다.

## 흐름

```
개발자: src/ 수정 → git push (release)
   ▼
GitHub Actions (build-and-deploy.yml)
   ├─ 이미지 빌드 → ghcr.io/silkair/infra-jjhg:sha-<커밋 7자리>
   └─ k8s/app.yaml의 image 태그를 새 값으로 바꿔 커밋 (github-actions[bot])
   ▼
ArgoCD (클러스터 안, Application "jjhg")
   └─ 저장소 k8s/ 를 주기적으로 확인 → 바뀐 태그로 Deployment 갱신 → 새 파드
```

| 구성 요소 | 값 |
|---|---|
| CI | GitHub Actions (checkout@v6, setup-buildx@v4, login@v4, build-push@v7, gha 캐시) |
| 레지스트리 인증 | 워크플로의 `GITHUB_TOKEN` (개인 토큰을 저장소에 두지 않음) |
| CD | ArgoCD v3.5.7, Application `jjhg` (path `k8s`, recurse false, automated prune + selfHeal) |
| ArgoCD 화면 | `http://argocd.jjhg.local` (Gateway HTTPRoute, server.insecure) |

## 원본 진짜할게 배포와의 차이

| | 원본 | 이 저장소 |
|---|---|---|
| 배포 방식 | Actions → GHCR → EC2의 self-hosted runner가 `docker run` (push) | Actions는 Git만 바꾸고, 클러스터 안의 ArgoCD가 Git을 읽어 반영 (pull) |
| 클러스터·서버 접근 권한 | CI가 서버에서 명령을 실행 | CI는 클러스터에 접근하지 않음 |
| 원하는 상태의 기록 | 실행 명령 안의 `-e` 환경변수 | Git의 매니페스트 (이력이 남음) |
| 직접 변경 시 | 그대로 남음 | ArgoCD selfHeal이 Git 상태로 되돌림 |
| 되돌리기 | 이전 이미지로 다시 `docker run` | Git에서 태그 커밋을 되돌리면 ArgoCD가 반영 |

## 설계에서 정한 것

- **태그 = `sha-커밋 7자리`**: 어떤 커밋의 이미지인지 바로 보이고, 되돌릴 대상이 분명하다.
- **무한 반복 방지 두 겹**: 워크플로 `paths`에 `k8s/`를 넣지 않았다. 또 `GITHUB_TOKEN`으로 한 push는 새 워크플로를 실행하지 않는다(GitHub 규칙).
- **`concurrency` + `git pull --rebase`**: 빌드가 겹치거나 그사이 다른 커밋이 올라와도 태그 커밋이 엇갈리지 않게.
- **Application 범위**: `k8s/` 바로 아래만. 클러스터 공통(`k8s/infra/`)과 테스트(`k8s/test/`)는 제외. Secret은 Git에 없으므로 ArgoCD가 관리하지 않는다.

## 확인 결과

| 확인 | 결과 |
|---|---|
| selfHeal | `kubectl scale --replicas=0` → 몇 초 안에 1로 복구 |
| 손으로 실행한 워크플로 | 봇 커밋 `deploy: jjhg-api sha-ab096c0` 생성 |
| 코드 push로 자동 실행 | `/health` 응답 변경 커밋 → 봇 커밋 `deploy: jjhg-api sha-d685986` → ArgoCD 동기화 리비전 일치 → `curl http://jjhg.local/health` 응답이 새 문구로 바뀜 |

## 알고 넘어갈 약점

- 워크플로에서 테스트를 돌리지 않는다 (원본 Dockerfile이 테스트를 건너뛰고 빌드)
- ArgoCD 화면이 HTTP (Gateway에 인증서 미적용)
- ArgoCD는 기본 약 3분 주기로 저장소를 확인하므로 반영까지 시간이 걸린다 (webhook 미구성)
