#!/usr/bin/env bash
# 테스트 사용자를 DB에 만들고, 그 사용자의 Access Token(JWT)을 발급한다.
#
# 왜 필요한가: 원본은 카카오·네이버 로그인으로만 토큰을 준다. 프런트 없이 API를 확인하려고
# 앱과 같은 규칙(HMAC 서명, subject = user id)으로 토큰을 직접 만든다. 앱 코드는 건드리지 않는다.
#
# 사용: ./scripts/issue-test-token.sh [닉네임]        (기본 닉네임: tester)
#       TOKEN=$(./scripts/issue-test-token.sh) && curl -H "Authorization: Bearer $TOKEN" localhost:8080/api/users/me
#
# 앱이 한 번 떠서 user 테이블을 만든 뒤(ddl-auto: update)에 실행한다.

set -euo pipefail   # 명령 실패·미정의 변수·파이프 중간 실패에서 즉시 멈춘다

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../.env}"
NICKNAME="${1:-tester}"
TTL_SECONDS="${TTL_SECONDS:-1800}"   # 30분. 앱 설정의 access 만료와 맞춘다

die() { echo "오류: $*" >&2; exit 1; }

# .env에서 필요한 값만 읽는다 (source로 통째로 실행하지 않는다)
read_env() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2-
}

[[ -f "$ENV_FILE" ]] || die ".env 파일이 없다: $ENV_FILE"
JWT_SECRET="$(read_env JWT_SECRET)"
MYSQL_ROOT_PASSWORD="$(read_env MYSQL_ROOT_PASSWORD)"
[[ -n "$JWT_SECRET" ]] || die "JWT_SECRET이 비어 있다"
# jjwt는 키 길이로 알고리즘을 고른다. 64바이트 이상이어야 HS512다
(( ${#JWT_SECRET} >= 64 )) || die "JWT_SECRET은 64자 이상이어야 한다 (지금 ${#JWT_SECRET}자)"
[[ "$NICKNAME" =~ ^[A-Za-z0-9_-]{1,20}$ ]] || die "닉네임은 영문·숫자·_- 20자 이내"

# DB 접속 명령. 기본은 compose의 mysql 컨테이너, MYSQL_CMD로 바꿀 수 있다
MYSQL_CMD="${MYSQL_CMD:-docker compose -f $SCRIPT_DIR/../compose.local.yml exec -T mysql mysql -uroot -p$MYSQL_ROOT_PASSWORD jjhg}"
sql() { $MYSQL_CMD -N -B -e "$1" 2>/dev/null; }

# 같은 닉네임이 있으면 재사용하고, 없으면 만든다
user_id="$(sql "SELECT id FROM user WHERE nickname='$NICKNAME' AND deleted_at IS NULL LIMIT 1;")" \
  || die "DB 접속 실패 (앱이 한 번 떠서 테이블이 생겼는지 확인)"
if [[ -z "$user_id" ]]; then
  sql "INSERT INTO user (name, nickname, email, created_at, updated_at)
       VALUES ('$NICKNAME', '$NICKNAME', NULL, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6));" \
    || die "사용자 생성 실패"
  user_id="$(sql "SELECT id FROM user WHERE nickname='$NICKNAME' ORDER BY id DESC LIMIT 1;")"
  echo "사용자 생성: id=$user_id nickname=$NICKNAME" >&2
else
  echo "기존 사용자 사용: id=$user_id nickname=$NICKNAME" >&2
fi

# base64url: JWT는 +/ 대신 -_ 를 쓰고 끝의 = 를 뗀다
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

now=$(date +%s)
header='{"alg":"HS512"}'
payload="{\"sub\":\"$user_id\",\"iat\":$now,\"exp\":$((now + TTL_SECONDS))}"

signing_input="$(printf '%s' "$header" | b64url).$(printf '%s' "$payload" | b64url)"
signature="$(printf '%s' "$signing_input" | openssl dgst -sha512 -mac HMAC -macopt "key:$JWT_SECRET" -binary | b64url)"

echo "$signing_input.$signature"
