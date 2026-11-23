#!/usr/bin/env bash
# 부하 테스트용 가상 사용자를 DB에 만든다. cp1에서 실행한다.
#
# 닉네임 <접두어>-0001 ~ <접두어>-NNNN 사용자를 만들고(이미 있으면 건너뜀), k6에 넘길 id 범위를 출력한다.
# 토큰은 k6가 같은 규칙(HS512, subject = user id)으로 직접 만든다.
# 비교 측정마다 접두어를 바꿔 새 사용자로 시작하면, 앞 측정에서 쌓인 계약이 다음 측정에 섞이지 않는다.
#
# 사용: bash seed-load-users.sh [사용자 수] [접두어]      (기본 100명, 접두어 lt)

set -euo pipefail

NS="${NS:-jjhg}"
COUNT="${1:-100}"
PREFIX="${2:-lt}"
[[ "$PREFIX" =~ ^[a-z0-9]{1,8}$ ]] || { echo "접두어는 영소문자·숫자 8자 이내" >&2; exit 1; }
[[ "$COUNT" =~ ^[0-9]+$ ]] && (( COUNT >= 1 && COUNT <= 1000 )) || { echo "사용자 수는 1~1000" >&2; exit 1; }

# DB 비밀번호는 Secret에서 꺼낸다 (화면·파일에 남기지 않는다)
pw="$(kubectl -n "$NS" get secret jjhg-secrets -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 -d)"
sql() { kubectl -n "$NS" exec -i mysql-0 -- mysql -uroot -p"$pw" jjhg -N -B -e "$1" 2>/dev/null; }

# 1부터 COUNT까지 숫자를 만들어(재귀 CTE) 없는 닉네임만 한 번에 넣는다
sql "INSERT INTO user (name, nickname, email, created_at, updated_at)
     WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < $COUNT)
     SELECT CONCAT('$PREFIX-', LPAD(n, 4, '0')), CONCAT('$PREFIX-', LPAD(n, 4, '0')), NULL, UTC_TIMESTAMP(6), UTC_TIMESTAMP(6)
     FROM seq
     WHERE NOT EXISTS (SELECT 1 FROM user u WHERE u.nickname = CONCAT('$PREFIX-', LPAD(seq.n, 4, '0')));"

read -r min max cnt <<<"$(sql "SELECT MIN(id), MAX(id), COUNT(*) FROM user WHERE nickname LIKE '$PREFIX-%' AND deleted_at IS NULL;")"
echo "가상 사용자 ${cnt}명: id ${min} ~ ${max}"
if (( max - min + 1 != cnt )); then
  echo "주의: id가 연속되지 않는다. 범위 안에 다른 사용자가 섞여 있을 수 있다" >&2
fi
echo "k6 실행 시: -e USER_MIN=${min} -e USER_MAX=${max}"
