#!/usr/bin/env bash
# CDC 포트 격리 필수화 실증 (workspace#79, P0-6) — #81 종착에서 리뷰 BLOCKER-4로 교정.
#
# 결정(charting ③): CDC 서버측 인증·인가는 ADR 0011 D11대로 별건(out of scope).
# 이 절차는 그 결정의 귀결 — "CDC 포트는 서버 보안 경계가 아니다" — 를 실증한다.
#
# 실측 코드 사실 두 가지(엔진 bdbeaf3f1):
#   1. cub_master는 cubrid_port_id를 INADDR_ANY(0.0.0.0)로 bind한다
#      (src/connection/tcp.c:665). localhost-bind 파라미터가 없으므로 엔진 안에서
#      포트 격리는 불가능하다 — 격리는 반드시 망 계층에서 강제해야 한다.
#   2. CDC 프로토콜 요청(scdc_start_session / scdc_find_lsa / scdc_get_loginfo …)은
#      network_sr.c:729-745에서 CHECK_AUTHORIZATION action attribute 없이 등록된다.
#      즉 DBA 권한 검사는 서버가 강제하지 않는다 — DBA 게이트는 오직 클라이언트 측
#      cubrid_log_db_login(cubrid_log.c:902, au_is_dba_group_member)에만 존재한다.
#
#      정확한 위협 모델(실측 2026-08-20, #79 "일반 로그인" 표현을 여기서 정밀화):
#      · 전체 스트림(범위 미지정) raw 읽기는 DBA 그룹 계정을 요구한다 — 비-DBA는
#        NO_TABLE_PRIVILEGE(-37)로 거부(부분 완화, 정직히 기록).
#      · 그러나 특정 테이블로 scope한 raw 읽기(cubrid_log_set_extraction_table_names,
#        harness -c owner.table)는 그 테이블 SELECT 권한만 있으면 **비-DBA도 성공**한다
#        (커넥터가 쓰는 바로 그 per-table 인가 모델). 즉 민감 테이블에 SELECT를 가진
#        임의 계정 + 망 도달성이면 그 테이블의 before-image 이력이 열린다.
#      어느 경우든 포트 자체에는 transport 인증·암호화가 없고(scdc_* 요청은
#      CHECK_AUTHORIZATION 없이 등록됨, network_sr.c:729-745; DBA 검사는 클라이언트 측
#      cubrid_log_db_login에만 존재), 막는 것은 오직 망 도달성이다.
#
# 실증 구조(대조):
#   RISK-ALL   — DBA raw client가 범위 미지정으로 스트림 전체(before-image 포함)를 읽는다.
#   RISK-SCOPED— 비-DBA(SELECT만) raw client가 -c로 scope해 그 테이블 before-image를 읽는다.
#                (최소권한 공격자 경로 — 가장 현실적 위협) 둘 다 assert로 강제.
#   NONDBA-ALL — 비-DBA 범위 미지정 전체 읽기는 거부된다(부분 완화, 정직 기록).
#   DENIAL     — 포트에 닿지 못하면 어느 client도 CONNECT 실패. assert로 강제.
#
# 파일럿 실제 방화벽 gate: 단일 호스트 자기완결 실행은 transport 사실만 증명한다.
# 실제 2-호스트 allowlist 검증(허용 호스트 성공 + 비허용 호스트 동일 포트 실패)은
# ALLOW_HOST/DENY_HOST env로 구동하며 — 미지정 시 SKIP이 아니라 안내 후, 파일럿
# 전제조건 문서(support-scope §5-14)가 요구하는 운영자 몫임을 명시한다.
#
# 전제: htapdb 서버 기동 + harness/cdclogdump 빌드(make CUBRID=...).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="${HARNESS:-$HERE/../harness}"
DUMP="$HARNESS/cdclogdump"
DB="${DB:-htapdb}"
PORT="${PORT:-1523}"
USER="${DBUSER:-dba}"                # raw client는 DBA 계정 필요 (아래 NONDBA가 이유 실증)
PW="${DBPW:-}"                        # dba 무암호 기본
NONDBA_USER="${NONDBA_USER:-cdc_e2e}" # PUBLIC-only 계정 (run-e2e가 생성)
NONDBA_PW="${NONDBA_PW:-cdc_e2e}"
HOSTIP="${HOSTIP:-$(hostname -I | awk '{print $1}')}"
EVID="$HERE/evidence"
mkdir -p "$EVID"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:$HOME/CUBRID/lib"

FAILED=0
fail() { echo "  [FAIL] $*"; FAILED=1; }
ok()   { echo "  [OK] $*"; }
pw_args() { [ -n "$PW" ] && printf -- '-w\n%s\n' "$PW"; }

# CDC는 단일 consumer(cdc_Gl.conn) — 실행 중인 소스 커넥터가 세션을 쥐고 있으면 raw
# cdclogdump의 START_SESSION과 상호 대체(replace)되어 접속이 굶는다. 다른 시나리오
# 스크립트와 동일하게 메인 소스를 잠시 정지하고 종료 시 복원한다.
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
MAIN=cubrid-source-poc
MAIN_WAS_RUNNING=""
if curl -fsS "$CONNECT_URL/connectors/$MAIN/status" 2>/dev/null \
        | python3 -c 'import json,sys;exit(0 if json.load(sys.stdin)["connector"]["state"]=="RUNNING" else 1)' 2>/dev/null; then
    MAIN_WAS_RUNNING=yes
    curl -fsS -X PUT "$CONNECT_URL/connectors/$MAIN/stop" >/dev/null 2>&1 || true
    for _ in $(seq 1 15); do
        [ "$(curl -fsS "$CONNECT_URL/connectors/$MAIN/status" | python3 -c 'import json,sys;print(json.load(sys.stdin)["connector"]["state"])' 2>/dev/null || echo x)" = STOPPED ] && break
        sleep 2
    done
    echo "(CDC 단일 consumer: $MAIN 정지 — 종료 시 복원)"
fi
restore_main () { [ -n "$MAIN_WAS_RUNNING" ] && curl -fsS -X PUT "$CONNECT_URL/connectors/$MAIN/resume" >/dev/null 2>&1 || true; }
trap restore_main EXIT

echo "== 사전 확인: cub_master가 어느 주소에 bind 되었나 (INADDR_ANY 기대) =="
ss -tlnp 2>/dev/null | grep ":$PORT " || echo "(ss 조회 실패 — 무시 가능)"
echo

echo "== 시드: 결정론적 고정 상태(매 실행 DROP 후 재생성 — 구 증거 오염 원인 제거) =="
# 모든 DML을 커밋해 스트림에 실린다. cdc_e2e에 SELECT만 부여(비-DBA scoped 경로용).
csql -u dba --no-pager "$DB" -c "
  DROP TABLE IF EXISTS t_secret;
  CREATE TABLE t_secret(id INT PRIMARY KEY, val VARCHAR(50)); COMMIT;
  GRANT SELECT ON t_secret TO $NONDBA_USER;
  INSERT INTO t_secret VALUES (1,'before'); COMMIT;
  UPDATE t_secret SET val='leaked-secret' WHERE id=1;
  INSERT INTO t_secret VALUES (2,'pii-row');
  DELETE FROM t_secret WHERE id=2; COMMIT;" >/dev/null 2>&1 \
    || { echo "  [FAIL] 시드 트래픽 주입 실패 — 서버/계정 확인"; exit 1; }
T0=$(( $(date +%s) - 15 ))
sleep 2

assert_before_images () { # $1 = evidence file, $2 = label
    local f="$1" l="$2"
    grep -qF 'as_str="leaked-secret"' "$f" && ok "$l UPDATE 후상 노출: leaked-secret" || fail "$l UPDATE 후상 미노출"
    grep -A3 'dml_type=1(UPDATE)' "$f" | grep -qF 'as_str="before"' \
        && ok "$l UPDATE 전상(before-image) 노출: before" || fail "$l UPDATE before-image 미노출"
    grep -A3 'dml_type=2(DELETE)' "$f" | grep -qF 'as_str="pii-row"' \
        && ok "$l DELETE 전상(before-image) 노출: pii-row" || fail "$l DELETE before-image 미노출"
}

echo "== RISK-ALL: DBA raw client가 범위 미지정으로 스트림 전체(before-image 포함)를 읽는다 =="
RISK="$EVID/issue-79-raw-attach.txt"
timeout 30 "$DUMP" -d "$DB" -H "$HOSTIP" -p "$PORT" -u "$USER" $(pw_args) \
    -t "$T0" -a 1 -m 400 -i 8 > "$RISK" 2>&1 || true
echo "  host=$HOSTIP:$PORT user=$USER(DBA) → 증거: $RISK"
grep -qE "CONNECT rc=0" "$RISK" \
  && ok "DBA raw client 연결됨 (서버측 transport 인증 없음)" || fail "연결되지 않음 — 서버/계정/포트 확인"
assert_before_images "$RISK" "RISK-ALL:"
echo "  --- 읽힌 DML(발췌) ---"; grep -iE 'dml_type=|as_str=' "$RISK" | head -10 | sed 's/^/    /'
echo

echo "== RISK-SCOPED: 비-DBA($NONDBA_USER, SELECT만) raw client가 -c로 그 테이블을 읽는다 =="
# 최소권한 공격자 경로 — 가장 현실적 위협. 커넥터가 쓰는 per-table 인가 모델과 동일.
SCOPED="$EVID/issue-79-nondba-scoped-read.txt"
timeout 25 "$DUMP" -d "$DB" -H "$HOSTIP" -p "$PORT" -u "$NONDBA_USER" -w "$NONDBA_PW" \
    -c "dba.t_secret" -t "$T0" -a 1 -m 400 -i 8 > "$SCOPED" 2>&1 || true
echo "  host=$HOSTIP:$PORT user=$NONDBA_USER(비-DBA, SELECT) scope=dba.t_secret → 증거: $SCOPED"
grep -qE "CONNECT rc=0" "$SCOPED" \
  && ok "비-DBA scoped raw client 연결됨 — SELECT만으로 CDC 스트림 접근" \
  || fail "비-DBA scoped 연결 실패 — per-table 인가 모델 확인"
assert_before_images "$SCOPED" "RISK-SCOPED:"
echo

echo "== NONDBA-ALL: 비-DBA 범위 미지정 전체 읽기는 거부된다 (부분 완화, 정직 기록) =="
NONDBA_OUT="$EVID/issue-79-nondba-allstream-denied.txt"
timeout 15 "$DUMP" -d "$DB" -H "$HOSTIP" -p "$PORT" -u "$NONDBA_USER" -w "$NONDBA_PW" \
    -t "$(date +%s)" -i 1 -m 5 > "$NONDBA_OUT" 2>&1 || true
if grep -qE "CONNECT rc=0" "$NONDBA_OUT"; then
    fail "비-DBA($NONDBA_USER) 전체 스트림에 붙었다 — 예상 밖(범위 미지정은 DBA 필요)"
else
    ok "비-DBA 전체 스트림 거부됨($(grep -oE 'CONNECT rc=-?[0-9]+' "$NONDBA_OUT"|head -1)) — 전체 읽기는 DBA 필요(부분 완화)"
fi
echo

echo "== DENIAL: 포트에 닿지 못하면 같은 client도 CONNECT 실패한다 =="
DEN="$EVID/issue-79-denial.txt"
: > "$DEN"
deny_reaches() { # label host port  → 0(=차단 관측) / 1(=예상 밖 연결)
  local label="$1" h="$2" p="$3"
  echo "### $label ($h:$p)" >> "$DEN"
  local out
  out="$(timeout 8 "$DUMP" -d "$DB" -H "$h" -p "$p" -u "$USER" $(pw_args) \
      -t "$(date +%s)" -i 1 -m 5 2>&1)"
  echo "$out" | grep -iE 'CONFIG|CONNECT|fail' >> "$DEN"; echo >> "$DEN"
  echo "$out" | grep -qE "CONNECT rc=0" && return 1 || return 0
}
# A) 리스너 없음/필터됨 → connection refused (firewall DROP/REJECT 대리)
deny_reaches "필터/리스너 없음 (firewall DROP 대리)" 127.0.0.1 1 \
  && ok "리스너 없는 endpoint: raw client 붙지 못함" \
  || fail "리스너 없는 endpoint에 연결됨 — 있을 수 없음"
# B) 무경로 격리망 (RFC5737 TEST-NET-1) → 도달 불가 (전용 관리망 대리)
deny_reaches "무경로 격리망 (전용 관리망 대리)" 192.0.2.1 "$PORT" \
  && ok "무경로 endpoint: raw client 붙지 못함" \
  || fail "무경로 endpoint에 연결됨 — 있을 수 없음"
echo "  증거: $DEN"
echo

echo "== ALLOWLIST(실제 파일럿 gate): 실서버 포트에 대한 2-호스트 allowlist =="
if [ -n "${ALLOW_HOST:-}" ] && [ -n "${DENY_HOST:-}" ]; then
    # 허용 호스트: 실서버 CDC 포트 연결 성공해야 함
    A_OUT="$(timeout 15 "$DUMP" -d "$DB" -H "$ALLOW_HOST" -p "$PORT" -u "$USER" $(pw_args) \
        -t "$(date +%s)" -i 1 -m 5 2>&1)"
    echo "$A_OUT" | grep -qE "CONNECT rc=0" \
      && ok "허용 호스트 $ALLOW_HOST:$PORT 연결 성공" \
      || fail "허용 호스트 $ALLOW_HOST:$PORT 연결 실패 — allowlist가 커넥터 워커를 막고 있다"
    # 비허용 호스트: 동일 서버·동일 포트 연결 실패해야 함
    D_OUT="$(timeout 15 "$DUMP" -d "$DB" -H "$DENY_HOST" -p "$PORT" -u "$USER" $(pw_args) \
        -t "$(date +%s)" -i 1 -m 5 2>&1)"
    echo "$D_OUT" | grep -qE "CONNECT rc=0" \
      && fail "비허용 호스트 $DENY_HOST:$PORT 가 연결됨 — allowlist 미작동" \
      || ok "비허용 호스트 $DENY_HOST:$PORT 연결 차단됨"
    # 방화벽 규칙 스냅샷 보관(가능한 경우)
    { echo "# captured $(date -u +%FT%TZ)"; (nft list ruleset 2>/dev/null || iptables -S 2>/dev/null || echo "(no nft/iptables readable)"); } \
        > "$EVID/issue-79-firewall-snapshot.txt" 2>&1
    echo "  방화벽 규칙 스냅샷: $EVID/issue-79-firewall-snapshot.txt"
else
    echo "  [ATTENTION] ALLOW_HOST/DENY_HOST 미지정 — 이 자기완결 실행은 transport 사실만"
    echo "  증명한다. 실제 파일럿 방화벽 allowlist 검증(허용 호스트 성공 + 비허용 호스트"
    echo "  동일 포트 실패 + 규칙 스냅샷)은 파일럿 환경에서 반드시 별도 수행해야 하며,"
    echo "  support-scope §5-14 사내 파일럿 전제조건이 이를 필수로 규정한다."
    echo "  예: ALLOW_HOST=<connect-worker-ip> DENY_HOST=<user-net-ip> $0"
fi
echo

if [ "$FAILED" -ne 0 ]; then
    echo "판정: FAIL — 위 [FAIL] 항목 확인. (증거: $RISK, $NONDBA_OUT, $DEN)"
    exit 1
fi
echo "판정: PASS — DBA raw client는 전체 이력을(RISK-ALL), 비-DBA는 SELECT만으로 해당"
echo "      테이블 before-image를(RISK-SCOPED) 읽는다. 전체 읽기는 DBA 필요(NONDBA-ALL,"
echo "      부분 완화)지만 도달성만이 실 경계다 — 못 닿으면 붙지 못한다(DENIAL)."
echo "      CDC 포트는 서버 경계가 아니므로 망 격리가 파일럿 필수 전제조건이다"
echo "      (support-scope §5-13/§5-14, setup-guide §1·§2.3)."
