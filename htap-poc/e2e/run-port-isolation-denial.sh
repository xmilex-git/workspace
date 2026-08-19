#!/usr/bin/env bash
# CDC 포트 격리 필수화 실증 (workspace#79, P0-6 / 리뷰 §4.22 임시 제한 지원)
#
# 결정(charting ③): CDC 서버측 인증·인가는 ADR 0011 D11대로 별건(out of scope).
# 이 절차는 그 결정의 귀결 — "CDC 포트는 서버 보안 경계가 아니다" — 를 실증한다.
#
# 사실(엔진 코드): cub_master는 cubrid_port_id를 INADDR_ANY(0.0.0.0)로 bind한다
# (src/connection/tcp.c:665). localhost-bind 파라미터가 없으므로, 리뷰 §4.22의
# "포트 localhost bind"는 엔진 안에서 불가능하다. 격리는 반드시 망 계층
# (firewall allowlist / 전용 관리망)에서 강제해야 한다.
#
# 실증 구조(대조):
#   RISK   — 망이 닿는 raw CDC client(cdclogdump)가 '일반 DB 로그인'만으로 붙어
#            변경 스트림 전체(UPDATE 후상·INSERT·DELETE 전상 before-image)를 읽는다.
#            → JDBC SELECT gate는 운영 편의 검사이지 보안 경계가 아님을 실증.
#   DENIAL — 같은 client가 CDC 포트에 '닿지 못하면'(필터/무경로) CONNECT 자체가
#            실패한다(rc=-10). firewall allowlist·전용 관리망이 만들어내는 상태.
#
# 결론: 임의 raw client와 (before-image 포함) 전체 이력 사이를 막는 유일한 것은
#       망 도달성뿐 → 파일럿에서 망 격리는 '권고'가 아니라 '필수 전제조건'.
#
# 전제: htapdb 서버 기동 + harness/cdclogdump 빌드(make CUBRID=...).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="${HARNESS:-$HERE/../harness}"
DUMP="$HARNESS/cdclogdump"
DB="${DB:-htapdb}"
PORT="${PORT:-1523}"
USER="${DBUSER:-dba}"
PW="${DBPW:-}"                       # dba 무암호 기본
HOSTIP="${HOSTIP:-$(hostname -I | awk '{print $1}')}"
EVID="$HERE/evidence"
mkdir -p "$EVID"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:$HOME/CUBRID/lib"

pw_args() { [ -n "$PW" ] && printf -- '-w\n%s\n' "$PW"; }

echo "== 사전 확인: cub_master가 어느 주소에 bind 되었나 (INADDR_ANY 기대) =="
ss -tlnp 2>/dev/null | grep ":$PORT " || echo "(ss 조회 실패 — 무시 가능)"
echo

echo "== RISK: 망이 닿는 raw CDC client가 일반 로그인만으로 스트림을 읽는다 =="
# DELETE의 before-image가 보이도록 소량 트래픽 주입 (있으면 좋고 없어도 절차는 성립)
csql -u dba --no-pager "$DB" -c "
  CREATE TABLE IF NOT EXISTS t_secret(id INT PRIMARY KEY, val VARCHAR(50));
  INSERT INTO t_secret VALUES (1,'before'); COMMIT;
  UPDATE t_secret SET val='leaked-secret' WHERE id=1;
  INSERT INTO t_secret VALUES (2,'pii-row');
  DELETE FROM t_secret WHERE id=2; COMMIT;" >/dev/null 2>&1 || true
T0=$(( $(date +%s) - 20 ))
RISK="$EVID/issue-79-raw-attach.txt"
timeout 30 "$DUMP" -d "$DB" -H "$HOSTIP" -p "$PORT" -u "$USER" $(pw_args) \
    -t "$T0" -i 6 -m 400 -a 1 > "$RISK" 2>&1 || true
echo "  host=$HOSTIP:$PORT user=$USER → 증거: $RISK"
grep -qE "CONNECT rc=0" "$RISK" \
  && echo "  [OK] 일반 로그인으로 CDC 세션 연결됨 (서버측 transport 인증 없음)" \
  || { echo "  [FAIL] 연결되지 않음 — 서버/계정/포트 확인"; }
echo "  --- raw client가 읽은 실제 DML(발췌) ---"
grep -iE 'type=1\(DML\)|as_str=|type=2\(DCL\)' "$RISK" | head -8 | sed 's/^/    /'
echo "  (DELETE의 cond[...] as_str 가 before-image 노출 — SELECT 권한만으로 이력이 열린다)"
echo

echo "== DENIAL: 포트에 닿지 못하면 같은 client도 CONNECT 실패 (rc=-10) =="
DEN="$EVID/issue-79-denial.txt"
: > "$DEN"
run_deny() { # label host port
  local label="$1" h="$2" p="$3"
  echo "### $label ($h:$p)" | tee -a "$DEN"
  timeout 8 "$DUMP" -d "$DB" -H "$h" -p "$p" -u "$USER" $(pw_args) \
      -t "$(date +%s)" -i 1 -m 5 2>&1 | grep -iE 'CONFIG|CONNECT|fail' | tee -a "$DEN"
  echo | tee -a "$DEN"
}
# A) 리스너 없음/필터됨 → connection refused  (firewall DROP/REJECT 대리)
run_deny "필터/리스너 없음 (firewall DROP 대리)" 127.0.0.1 1
# B) 무경로 격리망 (RFC5737 TEST-NET-1) → 도달 불가  (전용 관리망 대리)
run_deny "무경로 격리망 (전용 관리망 대리)" 192.0.2.1 "$PORT"
if grep -qE 'connect failed \(rc=-10\)' "$DEN"; then
  echo "  [OK] 도달 불가 시 raw client는 스트림에 붙지 못함 → 격리가 경계를 만든다"
else
  echo "  [WARN] 예상한 connect 실패가 관측되지 않음 — 환경 확인"
fi
echo
echo "완료. 증거: $RISK , $DEN"
echo "판정: 망 격리(firewall allowlist/전용 관리망)만이 raw client를 차단한다 —"
echo "      파일럿 필수 전제조건(support-scope §5-13, setup-guide §1·§2.3)."
