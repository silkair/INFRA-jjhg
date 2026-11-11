# M2 — 클러스터에 앱 배포

M1에서 만든 클러스터에 진짜할게 백엔드와 MySQL·Redis·RustFS를 올리고, 노트북에서 도메인으로 접속한다.

## 구성

```
노트북 (hosts: jjhg.local, s3.jjhg.local, s3-console.jjhg.local → 192.168.125.200)
  ▼
MetalLB (L2, 풀 192.168.125.200-220)
  ▼
Envoy Gateway (Gateway API) ─ Gateway jjhg-gateway :80
  ├─ HTTPRoute jjhg.local            → Service jjhg-api:8080 → Deployment jjhg-api (1)
  ├─ HTTPRoute s3.jjhg.local         → Service rustfs:9000
  └─ HTTPRoute s3-console.jjhg.local → Service rustfs:9001
                                        StatefulSet mysql · redis · rustfs (+ PVC, local-path)
```

| 항목 | 값 |
|---|---|
| 앱 이미지 | `ghcr.io/silkair/infra-jjhg:0.1.0` (GHCR, 공개) |
| 스토리지 | local-path-provisioner v0.0.37, 기본 StorageClass |
| LoadBalancer | MetalLB v0.16.2 (native, L2) |
| 입구 | Envoy Gateway v1.10.0 (Gateway API) — ingress-nginx는 2026-03 은퇴로 제외 |
| 네임스페이스 | `jjhg` |

## compose(M0)와의 대응

| M0 | M2 |
|---|---|
| `.env` | Secret `jjhg-secrets` (`k8s/secret.env.example` 형식, 커밋하지 않음) |
| `environment:` 중 비밀이 아닌 값 | ConfigMap `jjhg-api-config` |
| `mysql`·`redis`·`rustfs` 서비스 + 볼륨 | StatefulSet + `volumeClaimTemplates` (PVC) |
| `s3-init` | Job `s3-bucket-init` |
| `healthcheck` | `startupProbe`·`readinessProbe`·`livenessProbe` |
| `app` + `8080:8080` | Deployment + Service + HTTPRoute |
| 서비스 이름(`mysql`) | `mysql.jjhg.svc.cluster.local` (CoreDNS) |

## 설계에서 정한 것

- **DB류는 StatefulSet**: 파드 이름과 PVC가 고정으로 짝지어져, 다시 떠도 같은 디스크를 붙인다. 앱은 상태가 없어 Deployment.
- **앱 replicas 1**: 앱 안의 스케줄러(5분 주기·자정)가 파드 수만큼 중복 실행된다.
- **probe 분리**: startup·readiness는 actuator health(DB·Redis 포함), liveness는 tcpSocket. DB가 잠깐 끊겼다고 앱을 재시작하지 않게.
- **JVM 힙**: `-XX:MaxRAMPercentage=75` (기본 25%는 768Mi 제한에서 약 190Mi).
- **presigned URL 주소**: 업로드는 클러스터 바깥(노트북)이 하므로 `S3_ENDPOINT`를 Gateway 도메인(`http://s3.jjhg.local`)으로.

## 배포 순서 (cp1)

```bash
kubectl apply -f k8s/namespace.yaml
kubectl create secret generic jjhg-secrets -n jjhg --from-env-file=k8s/secret.env
kubectl apply -f k8s/mysql.yaml -f k8s/redis.yaml -f k8s/rustfs.yaml
kubectl apply -f k8s/s3-bucket-job.yaml
kubectl apply -f k8s/app-config.yaml -f k8s/app.yaml

# 클러스터 공통 (한 번)
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.37/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.2/config/manifests/metallb-native.yaml
kubectl apply -f k8s/infra/metallb-pool.yaml
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.10.0 -n envoy-gateway-system --create-namespace
kubectl apply -f k8s/infra/gateway.yaml -f k8s/routes.yaml
```

## 확인 결과

| 완료 기준 | 결과 |
|---|---|
| 파드를 지워도 데이터 유지 | `mysql-0` 삭제 → 재생성 후 이전에 넣은 행 그대로 |
| Gateway 경유 API 호출 | 노트북에서 `http://jjhg.local/actuator/health` UP, 테스트 토큰으로 `/api/users/me` 성공, presigned URL로 `s3.jjhg.local`에 업로드 200 |

## 남은 개선

- DB를 root 계정으로 접속 중 → 앱 전용 계정
- local-path는 데이터가 노드에 묶인다 (노드 장애 시 접근 불가) → M6에서 확인
- 이미지 빌드·배포가 수동 → M3에서 GitHub Actions + ArgoCD
