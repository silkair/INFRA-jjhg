# INFRA-jjhg

팀 프로젝트 **진짜할게** 백엔드를 온프레미스 쿠버네티스 클러스터에 직접 구성·배포하는 개인 인프라 프로젝트입니다.

- 원본: [prgrms-web-devcourse-final-project/WEB5_7_SixPeoplePlz_BE](https://github.com/prgrms-web-devcourse-final-project/WEB5_7_SixPeoplePlz_BE) (프로그래머스 데브코스 팀 프로젝트, 2025.07~08)
- 애플리케이션 코드는 원본 팀의 작업입니다. 원본에서 저는 계약 도메인과 서비스 계층 테스트를 맡았습니다.
- **이 저장소에서 추가·변경한 인프라 구성은 모두 제 작업입니다.** 앱 코드 변경은 S3 호환 스토리지 엔드포인트 설정 1건뿐입니다.

## 목표

| 단계 | 내용 | 상태 |
|---|---|---|
| M0 | 로컬 기동 (Docker Compose: MySQL·Redis·RustFS·앱) | 완료 |
| M1 | VMware VM 3대에 kubeadm 클러스터 구축, Bash 노드 준비 스크립트 | 완료 |
| M2 | Deployment·Service·Ingress, StatefulSet+PVC, MetalLB | 예정 |
| M3 | GitHub Actions(이미지 빌드·GHCR) + ArgoCD GitOps 배포 | 예정 |
| M4 | kube-prometheus-stack, SLO 1개, 알림 규칙 | 예정 |
| M5 | AWS 기본 망을 Terraform으로 생성·삭제 | 예정 |
| M6 | 장애 재현과 대응 기록 | 예정 |

## 원본과 다른 점

| | 원본 | 이 저장소 |
|---|---|---|
| 실행 환경 | AWS EC2 한 대 | 로컬 Compose → 온프레미스 K8s(VMware·kubeadm) |
| 배포 | GHCR + self-hosted runner가 `docker run -e ...` 20여 개 | (M3) GitHub Actions + ArgoCD |
| 설정·비밀값 | 실행 명령의 환경변수 | `.env` → (M2) ConfigMap·Secret |
| 오브젝트 스토리지 | AWS S3 | RustFS (S3 호환) |
| 로그인 | 카카오·네이버 OAuth | 검증용으로 같은 규칙의 JWT를 스크립트로 발급 |

## 문서

- 로컬 실행: [docs/infra/M0-local.md](docs/infra/M0-local.md)
- 원본 서비스 소개(기능·ERD·아키텍처): [docs/original-README.md](docs/original-README.md)
- 클러스터 구축: [docs/infra/M1-cluster.md](docs/infra/M1-cluster.md)
- 구축기(블로그): [kubeadm 클러스터 직접 구축](https://silkair001.tistory.com/55)