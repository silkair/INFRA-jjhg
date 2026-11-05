# M0 — 로컬 기동

원본 진짜할게 백엔드를 MySQL·Redis·RustFS와 함께 한 대에서 띄운다. 이후 K8s로 옮길 기준점이다.

## 실행

```bash
cp .env.example .env
# .env의 비밀번호를 바꾸고 JWT_SECRET을 채운다
#   openssl rand -base64 48 | tr -d '\n'
docker compose -f compose.local.yml up -d --build
docker compose -f compose.local.yml logs -f app     # "Started JinjjahalgaeApiApplication" 확인
```

## 확인

```bash
# 1) 인증 없이 열린 경로
curl -s localhost:8080/actuator/health

# 2) 테스트 사용자 토큰으로 인증 API
TOKEN=$(./scripts/issue-test-token.sh)
curl -s -H "Authorization: Bearer $TOKEN" localhost:8080/api/users/me

# 3) presigned URL 발급 → RustFS에 업로드
curl -s -X POST localhost:8080/api/files/presigned-url \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"fileName":"test.png"}'
# 응답의 preSignedUrl로: curl -X PUT --upload-file ./test.png "<preSignedUrl>"
# RustFS 콘솔(localhost:9001)에서 객체가 생겼는지 본다
```

Swagger: http://localhost:8080/docs

## 외부 연동 처리

| 연동 | 원본 | 여기서 |
|---|---|---|
| 카카오·네이버 로그인 | 사용자 토큰으로 제공자 API 호출 | 사용 안 함. `scripts/issue-test-token.sh`로 같은 규칙의 JWT 발급 |
| 푸시 | Expo 푸시 API (Firebase 설정은 호출처 없음) | 비활성 |
| S3 Presigned URL | AWS S3 | RustFS(S3 호환). `S3Config`에 엔드포인트 설정 추가 |
| CloudFront | 클라이언트가 이미지 URL 조립 | 범위 밖 |

## 원본과 다른 점

| | 원본 | 이 저장소 |
|---|---|---|
| 실행 | EC2에서 `docker run -e ...` 20여 개 | compose 한 파일 + `.env` |
| 의존 서비스 | 별도로 띄움 | MySQL·Redis·RustFS를 compose에 포함 |
| 오브젝트 스토리지 | AWS S3 | RustFS (S3 호환) |
| 배포 워크플로 | GHCR + self-hosted runner | 제거. M3에서 새로 만든다 |
