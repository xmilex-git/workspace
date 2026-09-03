#!/usr/bin/env bash
# CBRD-27365 smoke runner. 서버는 이미 기동돼 있어야 한다(cubrid-server-control 스킬로 기동).
# Usage: run_smoke.sh <db> [broker_port]   — env: CUBRID (install), CUBRID_DATABASES (db 등록 dir)
#   expected.out 이 없으면 현재 출력을 expected.out 으로 기록(기준 생성 모드).
#   broker_port 를 주면 ScrollSmoke(JDBC 역방향 커서)도 실행해 expected_scroll.out 과 비교.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
db="${1:?db name}"; bport="${2:-}"
: "${CUBRID:?CUBRID (install dir) required}"
out="$here/.last.out"
"$CUBRID/bin/csql" -u dba "$db" -i "$here/smoke.sql" 2>&1 \
  | sed -E 's/ \([0-9]+\.[0-9]+ sec\)//g' > "$out"
if [ ! -f "$here/expected.out" ]; then cp "$out" "$here/expected.out"; echo "[smoke] expected.out 생성"; fi
if diff -u "$here/expected.out" "$out"; then echo "[smoke] csql PASS"; else echo "[smoke] csql FAIL"; exit 1; fi
if [ -n "$bport" ]; then
  ( cd "$here" && javac ScrollSmoke.java && java -cp ".:$CUBRID/jdbc/cubrid_jdbc.jar" ScrollSmoke "$bport" "$db" > "$here/.last_scroll.out" 2>&1 )
  if [ ! -f "$here/expected_scroll.out" ]; then cp "$here/.last_scroll.out" "$here/expected_scroll.out"; echo "[smoke] expected_scroll.out 생성"; fi
  if diff -u "$here/expected_scroll.out" "$here/.last_scroll.out"; then echo "[smoke] scroll PASS"; else echo "[smoke] scroll FAIL"; exit 1; fi
fi
