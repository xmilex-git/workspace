#!/bin/bash
# smoke_b4.sh <install> <dbdir> — one broker in front of two databases (foldv2s0 = A, foldv2b = B), and the
# domain cache of sessions that follow each other.
# Brokers: B4 36701 (MAX 5, no DIRECT_HANDOFF line: a CAS broker hands over anyway), B4AUTO 36702 (MAX 1,
# KEEP_CONNECTION=AUTO), B4SO 36703 (ACCESS_MODE=SO), B4ONE 36704 (MAX 1).
# Rewrites the install's cubrid.conf (session conf) and cubrid_broker.conf; restores both on exit.
# Cases: 1 sessions one after another, and two at once, resolve object/set-of-object domains of one class
#        2 MAX 1: a session of B open over a broker restart holds the slot a connect to A waits for
#        3 a database whose server is down, and one databases.txt lacks: -677 with the host list
#        4 one client, a session of A and of B: a cancel of A's statement ends A's, B's runs to its end
#        5 a hand-written cancel with a wrong session id does nothing; with the session's id it cancels
#        6 `cubrid broker status` shows the front counters; no cub_cas runs; restart of an appl server is refused
#        7 a slave-only broker refuses the session (-10017); INFO line: what the JDBC driver does with its altHosts
#        8 AUTO, MAX 1: an idle session of B yields its slot to a connect to A, and is resumed
#        9 B's server stopped (SIGSTOP): a connect to B fails, A goes on; after SIGCONT B's old session and a new one run
#       10 broker_changer reaches the sessions of both servers (SQL_LOG ON: both write their log)
#       11 a 20 MiB bound string
# ONLY="n m" runs a subset.
set -u
INST="${1:?install}"; DBDIR="${2:?dbdir}"; A=foldv2s0; B=foldv2b
WS=/home/cubrid/dev/workspace
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
HERE=$WS/.git_ignored_dir/scratch/fold-v2/b4/smoke
OUT=$HERE/out-${TAG:-$(basename "$(dirname "$INST")")}-$(date +%s)
SESSCONF=${SESSCONF:-$WS/.git_ignored_dir/conf/foldv2s0.conf}
mkdir -p "$OUT"
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
JAR="$INST/jdbc/cubrid_jdbc.jar"; [ -f "$JAR" ] || JAR=$HOME/release/CUBRID-cas-fold-v2/jdbc/cubrid_jdbc.jar
BAK="$OUT/confbak"; mkdir -p "$BAK"; cp "$INST/conf/cubrid.conf" "$INST/conf/cubrid_broker.conf" "$BAK/"
PASS=0; FAIL=0
run() { case " ${ONLY:-$1} " in *" $1 "*) return 0;; esac; return 1; }
ok() { echo "CASE $1 PASS $2"; PASS=$((PASS+1)); }
bad() { echo "CASE $1 FAIL $2"; FAIL=$((FAIL+1)); }
broker() { cubrid broker "$@" < /dev/null > "$OUT/broker-$1.$(date +%s%N)" 2>&1; }
bpid() { pgrep -u "$USER" -f "cub_server $B" | head -1; }
cleanup() {
  p=$(bpid); [ -n "$p" ] && kill -CONT "$p" 2>/dev/null
  broker stop
  "$CTL" stop $A > "$OUT/final.stop" 2>&1; "$CTL" stop $B >> "$OUT/final.stop" 2>&1
  cp "$BAK/cubrid.conf" "$BAK/cubrid_broker.conf" "$INST/conf/"
}
trap cleanup EXIT
one() { # name port max keep access shm
  cat <<EOC

[%$1]
SERVICE                 =ON
BROKER_PORT             =$2
MIN_NUM_APPL_SERVER     =$3
MAX_NUM_APPL_SERVER     =$3
APPL_SERVER_SHM_ID      =$6
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =OFF
SESSION_TIMEOUT         =300
KEEP_CONNECTION         =$4
ACCESS_MODE             =$5
EOC
  [ "${DH:-0}" = 1 ] && echo "DIRECT_HANDOFF          =ON"   # a build before this change needs the line
}
{ printf '[broker]\nMASTER_SHM_ID           =36790\nADMIN_LOG_FILE          =log/broker/cubrid_broker.log\n'
  one B4 36701 5 ON RW 36791; one B4AUTO 36702 1 AUTO RW 36792; one B4SO 36703 2 ON SO 36793; one B4ONE 36704 1 ON RW 36794; } > "$OUT/cubrid_broker.conf"
(cd $WS && CONF=$SESSCONF CUBRID=$INST just conf > "$OUT/conf.out" 2>&1) || { echo "ABORT: conf"; exit 2; }
[ -n "${EXTRA_CONF:-}" ] && printf '%s\n' "$EXTRA_CONF" >> "$INST/conf/cubrid.conf"
cp "$OUT/cubrid_broker.conf" "$INST/conf/cubrid_broker.conf"
mkdir -p "$OUT/java"; javac -d "$OUT/java" "$HERE/B4Jdbc.java" "$HERE/B4Cancel.java" > "$OUT/javac.out" 2>&1 || { echo "ABORT: javac"; cat "$OUT/javac.out"; exit 2; }
jdbc() { p=$1; d=$2; shift 2; java ${JOPT:-} -cp "$OUT/java:$JAR" B4Jdbc "$p" "$d" dba "" "$@" 2>&1 | sed -u -E 's/\[CAS INFO[^]]*\]//; s/,\[SESSION-[0-9]+\]//; s/ +$//'; }
flat() { tr '\n' '|' < "$1" | cut -c1-${2:-300}; }
has() { grep -q -E "$2" "$1"; }
P=36701; PAUTO=36702; PSO=36703; PONE=36704
cores_before=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_")
for d in $A $B; do "$CTL" start $d > "$OUT/start-$d.out" 2>&1 || { echo "ABORT: start $d"; cat "$OUT/start-$d.out"; exit 2; }; done
for d in $A $B; do csql -u dba $d -c "DROP TABLE IF EXISTS b4o; DROP TABLE IF EXISTS b4c; DROP TABLE IF EXISTS b4big; CREATE TABLE b4c (a INT) DONT_REUSE_OID; CREATE TABLE b4o (o b4c, s SET OF b4c, q SEQUENCE OF b4c); INSERT INTO b4c VALUES (1); INSERT INTO b4o (o) SELECT b4c FROM b4c; CREATE TABLE b4big (s STRING);" > "$OUT/fixture-$d.out" 2>&1; done
broker start; sleep 1

if run 1; then
  dom() { jdbc $P $A "SELECT o.a, s, q FROM b4o" "CREATE TABLE b4x$1 (o b4c, s SET OF b4c)" "INSERT INTO b4x$1 (o) SELECT b4c FROM b4c" "SELECT COUNT(*) FROM b4x$1 WHERE o IS NOT NULL" "SELECT o.a FROM b4x$1" "DROP TABLE b4x$1" "COMMIT"; }
  for i in 1 2 3 4 5 6; do dom $i > "$OUT/c1-s$i.out"; done
  dom 7 > "$OUT/c1-s7.out" & p7=$!; dom 8 > "$OUT/c1-s8.out"; wait $p7
  same=0; for i in 2 3 4 5 6 7 8; do cmp -s "$OUT/c1-s1.out" "$OUT/c1-s$i.out" && same=$((same+1)); done
  [ $same -eq 7 ] && has "$OUT/c1-s1.out" '^1 OK 1$' && has "$OUT/c1-s1.out" '^5 OK 1$' && ! grep -q ERR "$OUT/c1-s1.out" \
    && ok 1 "8 sessions: $(flat "$OUT/c1-s1.out" 120)" || bad 1 "same=$same $(flat "$OUT/c1-s1.out" 400)"
fi
if run 2; then
  jdbc $PONE $B "SELECT 1" "SLEEP 20" "SELECT 2" > "$OUT/c2-hold.out" &
  hp=$!; sleep 3
  broker stop; broker start; sleep 1
  t0=$(date +%s); JOPT=-Dct=90 jdbc $PONE $A "SELECT 1" > "$OUT/c2-one.out"; t1=$(date +%s)
  wait $hp
  w=$((t1 - t0))
  [ $w -ge 8 ] && [ $w -lt 60 ] && has "$OUT/c2-one.out" '^1 OK 1$' && has "$OUT/c2-hold.out" '^3 OK 2$' \
    && ok 2 "the connect to $A waited ${w}s for the survivor of $B" || bad 2 "waited ${w}s one: $(flat "$OUT/c2-one.out") hold: $(flat "$OUT/c2-hold.out")"
fi
if run 3; then
  "$CTL" stop $B > "$OUT/c3-stop.out" 2>&1
  jdbc $P $B "SELECT 1" > "$OUT/c3-down.out"; jdbc $P nosuchdb "SELECT 1" > "$OUT/c3-unknown.out"
  jdbc $P $A "SELECT 1" > "$OUT/c3-a.out"
  "$CTL" start $B > "$OUT/c3-start.out" 2>&1
  jdbc $P $B "SELECT 1" > "$OUT/c3-b.out"
  has "$OUT/c3-down.out" "^CONNECT ERR -677 Failed to connect to database server, '$B', on the following host\(s\): localhost" \
    && has "$OUT/c3-unknown.out" "^CONNECT ERR -677 Failed to connect to database server, 'nosuchdb', on the following host\(s\): localhost" \
    && has "$OUT/c3-a.out" '^1 OK 1$' && has "$OUT/c3-b.out" '^1 OK 1$' \
    && ok 3 "$(flat "$OUT/c3-down.out" 120)" || bad 3 "down: $(flat "$OUT/c3-down.out") unknown: $(flat "$OUT/c3-unknown.out") b: $(flat "$OUT/c3-b.out")"
fi
if run 4; then
  java -cp "$OUT/java:$JAR" B4Cancel $P $A $B > "$OUT/c4.out" 2>&1
  has "$OUT/c4.out" '^A cancelled early$' && has "$OUT/c4.out" '^B completed late$' \
    && ok 4 "$(flat "$OUT/c4.out")" || bad 4 "$(flat "$OUT/c4.out" 500)"
fi
if run 5; then
  forge() { # out-prefix mode: the victim sleeps, the cancel is forged from its row of SHOW SESSION STATUS
    jdbc $P $A "ROWS SHOW SESSION STATUS" "SELECT SLEEP(10)" > "$OUT/$1.out" &
    vp=$!; sleep 3
    tok=$(awk '$2 == "ROW" {print $3; exit}' "$OUT/$1.out"); sid=$(awk '$2 == "ROW" {print $8; exit}' "$OUT/$1.out")
    [ "$2" = wrong ] && sid=$((sid + 1000))
    python3 "$HERE/forge_cancel.py" $P "$tok" sid "$sid" > "$OUT/$1.forge" 2>&1
    wait $vp
  }
  forge c5-wrong wrong; forge c5-right right
  has "$OUT/c5-wrong.out" '^2 OK' && has "$OUT/c5-right.out" '^2 ERR' \
    && ok 5 "wrong id: $(sed -n '$p' "$OUT/c5-wrong.out" | cut -c1-40), $(cat "$OUT/c5-wrong.forge"); its id: $(sed -n '$p' "$OUT/c5-right.out" | cut -c1-60), $(cat "$OUT/c5-right.forge")" \
    || bad 5 "wrong: $(flat "$OUT/c5-wrong.out") $(cat "$OUT/c5-wrong.forge") right: $(flat "$OUT/c5-right.out") $(cat "$OUT/c5-right.forge")"
fi
if run 6; then
  jdbc $P $A "SELECT 1" > "$OUT/c6-one.out"
  broker_monitor b4 < /dev/null > "$OUT/c6-status.out" 2>&1
  broker_monitor -b < /dev/null > "$OUT/c6-status-b.out" 2>&1
  cubrid_broker restart B4 1 < /dev/null > "$OUT/c6-restart.out" 2>&1
  ncas=$(pgrep -u "$USER" -x cub_cas | wc -l)
  has "$OUT/c6-status.out" 'ACCEPTED : [1-9][0-9]*, HANDOFFS : [1-9][0-9]*, REJECTED : [0-9]+, SLOTS : 0/5' && [ "$ncas" = 0 ] && has "$OUT/c6-restart.out" 'hands its connections' \
    && ok 6 "$(grep -m1 ACCEPTED "$OUT/c6-status.out" | sed 's/^ *//')" || bad 6 "cub_cas=$ncas status: $(flat "$OUT/c6-status.out" 400) restart: $(flat "$OUT/c6-restart.out")"
fi
if run 7; then
  jdbc $PSO $A "SELECT 1" > "$OUT/c7-so.out"
  JOPT=-Dalt=$P jdbc $PSO $A "SELECT 1" > "$OUT/c7-alt.out"
  has "$OUT/c7-so.out" '^CONNECT ERR -10017' && ok 7 "$(flat "$OUT/c7-so.out" 60)" || bad 7 "so: $(flat "$OUT/c7-so.out")"
  echo "INFO 7 with altHosts=127.0.0.1:$P: $(flat "$OUT/c7-alt.out" 60)"
fi
if run 8; then
  JOPT=-Dct=90 jdbc $PAUTO $B "SET @b4 = 8" "COMMIT" "SLEEP 8" "SELECT @b4" > "$OUT/c8-b.out" &
  bp=$!; sleep 3
  t0=$(date +%s); JOPT=-Dct=90 jdbc $PAUTO $A "SELECT 1" "COMMIT" > "$OUT/c8-a.out"; t1=$(date +%s)
  wait $bp
  w=$((t1 - t0))
  [ $w -lt 5 ] && has "$OUT/c8-a.out" '^1 OK 1$' && has "$OUT/c8-b.out" '^4 OK 8$' \
    && ok 8 "the connect to $A took ${w}s; $B's session read its variable after: $(sed -n 4p "$OUT/c8-b.out")" || bad 8 "waited ${w}s a: $(flat "$OUT/c8-a.out") b: $(flat "$OUT/c8-b.out")"
fi
if run 9; then
  JOPT=-Dct=90 jdbc $P $B "SELECT 1" "COMMIT" "SLEEP 30" "SELECT 2" > "$OUT/c9-old.out" &
  op=$!; sleep 3
  sp=$(bpid); kill -STOP "$sp"
  t0=$(date +%s); JOPT=-Dct=12 jdbc $P $B "SELECT 1" > "$OUT/c9-stopped.out"; t1=$(date +%s)
  jdbc $P $A "SELECT 1" > "$OUT/c9-a.out"
  kill -CONT "$sp"
  jdbc $P $B "SELECT 1" > "$OUT/c9-new.out"
  wait $op
  has "$OUT/c9-stopped.out" '^CONNECT ERR' && has "$OUT/c9-a.out" '^1 OK 1$' && has "$OUT/c9-new.out" '^1 OK 1$' && has "$OUT/c9-old.out" '^4 OK 2$' \
    && ok 9 "stopped: $(flat "$OUT/c9-stopped.out" 60) after $((t1 - t0))s; $A, a new and the old session of $B ran" \
    || bad 9 "stopped: $(flat "$OUT/c9-stopped.out") a: $(flat "$OUT/c9-a.out") new: $(flat "$OUT/c9-new.out") old: $(flat "$OUT/c9-old.out")"
fi
if run 10; then
  rm -f "$INST"/log/broker/sql_log/b4_*.sql.log
  jdbc $P $A "SELECT 1001 FROM db_root" "COMMIT" "SLEEP 6" "SELECT 1002 FROM db_root" "COMMIT" > "$OUT/c10-a.out" &
  ap=$!
  jdbc $P $B "SELECT 2001 FROM db_root" "COMMIT" "SLEEP 6" "SELECT 2002 FROM db_root" "COMMIT" > "$OUT/c10-b.out" &
  bp=$!; sleep 3
  broker_changer B4 SQL_LOG ON < /dev/null > "$OUT/c10-changer.out" 2>&1
  wait $ap $bp
  cat "$INST"/log/broker/sql_log/b4_*.sql.log > "$OUT/c10-sqllog.out" 2>/dev/null
  broker_changer B4 SQL_LOG OFF < /dev/null >> "$OUT/c10-changer.out" 2>&1
  has "$OUT/c10-sqllog.out" 'SELECT 1002' && has "$OUT/c10-sqllog.out" 'SELECT 2002' && ! has "$OUT/c10-sqllog.out" 'SELECT [12]001' \
    && ok 10 "$(flat "$OUT/c10-changer.out" 80)" || bad 10 "changer: $(flat "$OUT/c10-changer.out") log: $(grep -c -i select "$OUT/c10-sqllog.out")"
fi
if run 11; then
  jdbc $P $A "BIG 20" "SELECT LENGTH(s) FROM b4big" "ROLLBACK" > "$OUT/c11.out"
  has "$OUT/c11.out" '^1 OK 1$' && has "$OUT/c11.out" '^2 OK 20971520$' && ok 11 "$(flat "$OUT/c11.out" 80)" || bad 11 "$(flat "$OUT/c11.out" 400)"
fi
sleep 1
for d in $A $B; do cubrid tranlist $d < /dev/null > "$OUT/tranlist-$d.out" 2>&1; done
cores_after=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_")
[ "$cores_after" -eq "$cores_before" ] || { echo "CORES: $cores_before -> $cores_after"; FAIL=$((FAIL+1)); }
grep -l -E 'Assertion|SIGSEGV|SIGABRT' "$INST"/log/server/${A}_*.err "$INST"/log/server/${B}_*.err 2>/dev/null | tail -3
echo "OUT $OUT"
echo "SMOKE_B4: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
