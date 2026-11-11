#!/usr/bin/env bash
# 클러스터(jjhg 네임스페이스)의 앱용 테스트 토큰 발급. cp1에서 실행한다.
#
# issue-test-token.sh를 그대로 쓰되, 비밀값은 쿠버네티스 Secret에서 읽고
# DB 접속은 mysql-0 파드로 한다.
#
# 사용: bash issue-test-token-k8s.sh [닉네임]

set -euo pipefail

NS="${NS:-jjhg}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT          # 비밀값 임시 파일은 끝나면 반드시 지운다

# Secret의 키=값을 .env 형식으로 꺼낸다 (base64 디코딩)
kubectl -n "$NS" get secret jjhg-secrets \
  -o go-template='{{range $k, $v := .data}}{{$k}}={{$v | base64decode}}{{"\n"}}{{end}}' > "$tmp"

pw="$(grep -E '^MYSQL_ROOT_PASSWORD=' "$tmp" | cut -d= -f2-)"

MYSQL_CMD="kubectl -n $NS exec -i mysql-0 -- mysql -uroot -p$pw jjhg" \
ENV_FILE="$tmp" \
  bash "$SCRIPT_DIR/issue-test-token.sh" "$@"
