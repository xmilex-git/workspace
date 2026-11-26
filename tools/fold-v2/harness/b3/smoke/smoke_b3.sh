#!/bin/bash
# smoke_b3.sh <install> <dbdir> <db> — the write gates of a session by its broker's ACCESS_MODE and by the
# server's read_only, through three brokers (RW 36701, RO 36702, SO 36703). FOLD=1 (default) gives the brokers
# DIRECT_HANDOFF=ON (sessions in the server); FOLD=0 runs the same statements through CAS processes of a
# develop install, which is what the fold must match.
# Rewrites the install's cubrid.conf (session conf) and cubrid_broker.conf; restores both on exit.
# Cases: 1 RW broker: INSERT, DDL, SAVEPOINT, serial NEXT_VALUE all run
#        2 RO broker: SELECT runs; INSERT and DDL are refused (-581) and the session goes on; SAVEPOINT and serial
#        3 SO broker: refused at connect on a server without HA (its state is active); the next RW connect works
#        4 an RO session and its logout change nothing for an RW session that is open meanwhile
#        5 read_only=yes server: an RW session's INSERT, DDL, SAVEPOINT, serial are refused, also after another
#          session connected and logged out; the session is closed or goes on as on develop
# ONLY="n m" runs a subset. The lines of every case are in $OUT/c<n>*.out for the fold/develop diff.
set -u
INST="${1:?install}"; DBDIR="${2:?dbdir}"; DB="${3:?db}"
WS=/home/cubrid/dev/workspace
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
HERE=$WS/.git_ignored_dir/scratch/fold-v2/b3/smoke
OUT=$HERE/out-${TAG:-$(basename "$(dirname "$INST")")}-$(date +%s)
SESSCONF=${SESSCONF:-$WS/.git_ignored_dir/conf/foldv2s0.conf}
FOLD=${FOLD:-1}
mkdir -p "$OUT"
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
JAR="$INST/jdbc/cubrid_jdbc.jar"; [ -f "$JAR" ] || JAR=$HOME/release/CUBRID-cas-fold-v2/jdbc/cubrid_jdbc.jar
BAK="$OUT/confbak"; mkdir -p "$BAK"; cp "$INST/conf/cubrid.conf" "$INST/conf/cubrid_broker.conf" "$BAK/"
PASS=0; FAIL=0
run() { case " ${ONLY:-$1} " in *" $1 "*) return 0;; esac; return 1; }
ok() { echo "CASE $1 PASS $2"; PASS=$((PASS+1)); }
bad() { echo "CASE $1 FAIL $2"; FAIL=$((FAIL+1)); }
broker() { cubrid broker "$1" < /dev/null > "$OUT/broker-$1.$(date +%s%N)" 2>&1; }
cleanup() {
  broker stop
  "$CTL" stop "$DB" > "$OUT/final.stop" 2>&1
  cp "$BAK/cubrid.conf" "$BAK/cubrid_broker.conf" "$INST/conf/"
}
trap cleanup EXIT
one() { # name port access_mode shm
  cat <<EOC

[%$1]
SERVICE                 =ON
BROKER_PORT             =$2
MIN_NUM_APPL_SERVER     =3
MAX_NUM_APPL_SERVER     =3
APPL_SERVER_SHM_ID      =$4
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =OFF
SESSION_TIMEOUT         =300
KEEP_CONNECTION         =ON
ACCESS_MODE             =$3
EOC
  [ "$FOLD" = 1 ] && echo "DIRECT_HANDOFF          =ON"
}
{ printf '[broker]\nMASTER_SHM_ID           =36790\nADMIN_LOG_FILE          =log/broker/cubrid_broker.log\n'
  one B3RW 36701 RW 36791; one B3RO 36702 RO 36792; one B3SO 36703 SO 36793; } > "$OUT/cubrid_broker.conf"
conf() { # extra cubrid.conf lines
  (cd $WS && CONF=$SESSCONF CUBRID=$INST just conf > "$OUT/conf.out" 2>&1) || { echo "ABORT: conf"; exit 2; }
  [ -n "${1:-}" ] && printf '%s\n' "$1" >> "$INST/conf/cubrid.conf"
  cp "$OUT/cubrid_broker.conf" "$INST/conf/cubrid_broker.conf"
}
mkdir -p "$OUT/java"; javac -d "$OUT/java" "$HERE/B3Jdbc.java" > "$OUT/javac.out" 2>&1 || { echo "ABORT: javac"; cat "$OUT/javac.out"; exit 2; }
jdbc() { p=$1; shift; java -cp "$OUT/java:$JAR" B3Jdbc "$p" "$DB" dba "" "$@" 2>&1 | sed -E 's/\[CAS INFO[^]]*\]//; s/ +$//'; }
RW=36701; RO=36702; SO=36703
cores_before=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_")
has() { grep -q -E "$2" "$1"; }

conf ""
"$CTL" start "$DB" > "$OUT/start.out" 2>&1 || { echo "ABORT: server start"; cat "$OUT/start.out"; exit 2; }
csql -u dba "$DB" -c "DROP TABLE IF EXISTS b3t; DROP TABLE IF EXISTS b3d; DROP SERIAL IF EXISTS b3s; CREATE TABLE b3t (a INT); CREATE SERIAL b3s; INSERT INTO b3t VALUES (0);" > "$OUT/fixture.out" 2>&1
broker start; sleep 1

if run 1; then
  jdbc $RW "INSERT INTO b3t VALUES (1)" "SAVEPOINT" "SELECT b3s.NEXT_VALUE" "CREATE TABLE b3d (x INT)" "DROP TABLE b3d" "COMMIT" "SELECT COUNT(*) FROM b3t" > "$OUT/c1.out"
  has "$OUT/c1.out" '^1 OK 1$' && has "$OUT/c1.out" '^2 OK' && has "$OUT/c1.out" '^3 OK [0-9]+' && has "$OUT/c1.out" '^4 OK' && has "$OUT/c1.out" '^7 OK 2$' \
    && ok 1 "$(tr '\n' '|' < "$OUT/c1.out" | cut -c1-200)" || bad 1 "$(tr '\n' '|' < "$OUT/c1.out" | cut -c1-400)"
fi
if run 2; then
  jdbc $RO "SELECT COUNT(*) FROM b3t" "INSERT INTO b3t VALUES (2)" "SELECT COUNT(*) FROM b3t" "CREATE TABLE b3d (x INT)" "SAVEPOINT" "SELECT b3s.NEXT_VALUE" "COMMIT" "SELECT COUNT(*) FROM b3t" > "$OUT/c2.out"
  has "$OUT/c2.out" '^1 OK [0-9]+$' && has "$OUT/c2.out" '^2 ERR -581' && has "$OUT/c2.out" '^3 OK [0-9]+$' && has "$OUT/c2.out" '^4 ERR -581' && has "$OUT/c2.out" '^8 OK [0-9]+$' \
    && ok 2 "$(tr '\n' '|' < "$OUT/c2.out" | cut -c1-300)" || bad 2 "$(tr '\n' '|' < "$OUT/c2.out" | cut -c1-500)"
fi
if run 3; then
  # a server without HA is in the active state: a slave-only broker's session is refused there (a CAS: -743 from
  # its host loop; a session: CAS_ER_FREE_SERVER -10017, which a driver goes to its next altHost on)
  jdbc $SO "SELECT COUNT(*) FROM b3t" > "$OUT/c3.out"
  jdbc $RW "SELECT COUNT(*) FROM b3t" > "$OUT/c3-after.out"
  want='-10017'; [ "$FOLD" = 1 ] || want='-743'
  has "$OUT/c3.out" "^CONNECT ERR $want" && has "$OUT/c3-after.out" '^1 OK [0-9]+$' \
    && ok 3 "$(tr '\n' '|' < "$OUT/c3.out" | cut -c1-120)" || bad 3 "$(tr '\n' '|' < "$OUT/c3.out" | cut -c1-500)"
fi
if run 4; then
  jdbc $RW "INSERT INTO b3t VALUES (41)" "COMMIT" "SLEEP 4" "INSERT INTO b3t VALUES (42)" "COMMIT" "SLEEP 4" "INSERT INTO b3t VALUES (43)" "CREATE TABLE b3d (x INT)" "DROP TABLE b3d" "COMMIT" > "$OUT/c4.out" &
  wp=$!; sleep 1
  jdbc $RO "SELECT 1" "SLEEP 5" "INSERT INTO b3t VALUES (44)" "COMMIT" > "$OUT/c4-ro.out"     # open over the 2nd insert, gone before the 3rd
  wait $wp
  ! grep -q ERR "$OUT/c4.out" && has "$OUT/c4-ro.out" '^3 ERR -581' \
    && ok 4 "rw: $(grep -c OK "$OUT/c4.out") OK, ro: $(sed -n 3p "$OUT/c4-ro.out" | cut -c1-80)" || bad 4 "rw: $(tr '\n' '|' < "$OUT/c4.out" | cut -c1-400) ro: $(tr '\n' '|' < "$OUT/c4-ro.out" | cut -c1-200)"
fi
if run 5; then
  broker stop; "$CTL" stop "$DB" > "$OUT/c5-stop.out" 2>&1
  conf "read_only=yes"
  "$CTL" start "$DB" > "$OUT/c5-start.out" 2>&1 || { bad 5 "server start with read_only=yes"; }
  broker start; sleep 1
  jdbc $RW "INSERT INTO b3t VALUES (51)" "ROLLBACK" "SLEEP 4" "INSERT INTO b3t VALUES (52)" "ROLLBACK" "SLEEP 4" "INSERT INTO b3t VALUES (53)" "ROLLBACK" \
     "CREATE TABLE b3d (x INT)" "ROLLBACK" "SAVEPOINT" "ROLLBACK" "SELECT b3s.NEXT_VALUE" "ROLLBACK" "SELECT COUNT(*) FROM b3t" > "$OUT/c5.out" &
  wp=$!; sleep 1
  jdbc $RW "SELECT 1" "SLEEP 2" > "$OUT/c5-other.out"       # connects after the 1st insert, logs out before the 2nd
  wait $wp
  jdbc $RW "SELECT COUNT(*) FROM b3t" > "$OUT/c5-count.out"
  n=$(grep -c -E '^(1|4|7|9) ERR -581' "$OUT/c5.out")
  [ "$n" = 4 ] && ! grep -q -E '^(1|4|7|9) OK' "$OUT/c5.out" \
    && ok 5 "$(tr '\n' '|' < "$OUT/c5.out" | cut -c1-600)" || bad 5 "$(tr '\n' '|' < "$OUT/c5.out" | cut -c1-700)"
fi
cores_after=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_")
[ "$cores_after" -eq "$cores_before" ] || { echo "CORES: $cores_before -> $cores_after"; FAIL=$((FAIL+1)); }
echo "OUT $OUT"
echo "SMOKE_B3: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
