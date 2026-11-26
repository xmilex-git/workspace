#!/bin/bash
# smoke_b2.sh <install> <dbdir> <db> — B2 smoke: what a CAS did for its connection, done by the server's session.
# Rewrites the install's cubrid.conf (session conf + ddl_audit_log, cas_access_control) and cubrid_broker.conf;
# restores both on exit.  Brokers: B2 (cleartext, AUTO, SQL/slow/access logs), B2S (SSL, DIRECT_HANDOFF_SSL_DB).
# Cases: 1 SQL log lines of a connection, flushed while it is idle; slow log of a statement past LONG_QUERY_TIME
#        2 two sessions at once write <broker>_1 and <broker>_2; the next one takes index 1 again
#        3 access log NEW line
#        4 ACCESS_CONTROL: a client address not in the file is rejected and logged; allowed after `server acl reload`
#        5 broker_changer SQL_LOG: a live session and a later one both follow; a CAS number is refused
#        6 cubrid broker reset: an idle AUTO session yields (RESET in its SQL log) and its client goes on
#        7 SHOW SESSION STATUS rows of the sessions, a row's counters as of a request boundary
#        8 cubrid killtran of a session's transaction ends its connection, the server stays
#        9 SSL client through DIRECT_HANDOFF_SSL_DB: TLS ends in the server
#       10 DDL audit log written by the session
#       11 generated keys of an autocommit insert (the first page of the result outlives the query)
#       12 execute_array past LONG_QUERY_TIME: the slow log has its bind values
#       13 MAX_PREPARED_STMT_COUNT of the broker's conf caps the session's handles
# ONLY="n m" runs a subset.  ENVX="VAR=v ..." is added to the server's environment (the memory check).
set -u
INST="${1:?install}"; DBDIR="${2:?dbdir}"; DB="${3:?db}"
WS=/home/cubrid/dev/workspace
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
HERE=$WS/.git_ignored_dir/scratch/fold-v2/b2/smoke
OUT=$HERE/out-${TAG:-$(basename "$(dirname "$INST")")}
SESSCONF=${SESSCONF:-$WS/.git_ignored_dir/conf/foldv2s0.conf}
PORT=36711; SPORT=36712
LANIP=$(ip -4 -o addr show scope global | awk 'NR==1{sub(/\/.*/, "", $4); print $4}')
rm -rf "$OUT"; mkdir -p "$OUT"
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
JAR="$INST/jdbc/cubrid_jdbc.jar"
BAK="$OUT/confbak"; mkdir -p "$BAK"; cp -p "$INST/conf/cubrid.conf" "$INST/conf/cubrid_broker.conf" "$INST/conf/cas_ssl_cert.crt" "$INST/conf/cas_ssl_cert.key" "$BAK/"
# the SSL broker wants a private key only its owner reads; the install's sample key is 0644
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=b2smoke" -keyout "$OUT/ssl.key" -out "$OUT/ssl.crt" > "$OUT/openssl.out" 2>&1 || { echo "ABORT: openssl"; exit 2; }
cp "$OUT/ssl.crt" "$INST/conf/cas_ssl_cert.crt"; cp "$OUT/ssl.key" "$INST/conf/cas_ssl_cert.key"; chmod 600 "$INST/conf/cas_ssl_cert.key"
PASS=0; FAIL=0
run() { case " ${ONLY:-$1} " in *" $1 "*) return 0;; esac; return 1; }
ok() { echo "CASE $1 PASS $2"; PASS=$((PASS+1)); }
bad() { echo "CASE $1 FAIL $2"; FAIL=$((FAIL+1)); }
broker() { BRD_DEBUG_LOG=$OUT/brd.log cubrid broker "$@" < /dev/null > "$OUT/broker-$1.$(date +%s%N)" 2>&1; }
cleanup() {
  broker stop
  "$CTL" stop "$DB" > "$OUT/final.stop" 2>&1
  cp -p "$BAK/cubrid.conf" "$BAK/cubrid_broker.conf" "$BAK/cas_ssl_cert.crt" "$BAK/cas_ssl_cert.key" "$INST/conf/"
  rm -f "$INST/conf/b2_acl.txt" "$INST/conf/b2_ip.txt"
}
trap cleanup EXIT

cp "$SESSCONF" "$OUT/sess.conf"
cat >> "$OUT/sess.conf" <<EOC
ddl_audit_log=yes
cas_access_control=yes
cas_access_control_file=$INST/conf/b2_acl.txt
EOC
(cd $WS && CONF=$OUT/sess.conf CUBRID=$INST just conf > "$OUT/conf.out" 2>&1) || { echo "ABORT: conf"; exit 2; }
printf '[%%B2]\n%s:dba:b2_ip.txt\n' "$DB" > "$INST/conf/b2_acl.txt"
echo "10.9.9.9" > "$INST/conf/b2_ip.txt"
cat > "$INST/conf/cubrid_broker.conf" <<EOC
[broker]
MASTER_SHM_ID           =36790
ADMIN_LOG_FILE          =log/broker/cubrid_broker.log

[%B2]
SERVICE                 =ON
BROKER_PORT             =$PORT
MIN_NUM_APPL_SERVER     =4
MAX_NUM_APPL_SERVER     =4
APPL_SERVER_SHM_ID      =36791
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =ON
SLOW_LOG                =ON
LONG_QUERY_TIME         =1
ACCESS_LOG              =ON
MAX_PREPARED_STMT_COUNT =10
SESSION_TIMEOUT         =300
KEEP_CONNECTION         =AUTO
DIRECT_HANDOFF          =ON

[%B2S]
SERVICE                 =ON
BROKER_PORT             =$SPORT
MIN_NUM_APPL_SERVER     =2
MAX_NUM_APPL_SERVER     =2
APPL_SERVER_SHM_ID      =36792
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =ON
SSL                     =ON
KEEP_CONNECTION         =ON
DIRECT_HANDOFF          =ON
DIRECT_HANDOFF_SSL_DB   =$DB
EOC
mkdir -p "$OUT/java"; javac -d "$OUT/java" "$HERE/B2Jdbc.java" > "$OUT/javac.out" 2>&1 || { echo "ABORT: javac"; cat "$OUT/javac.out"; exit 2; }
j() { java -cp "$OUT/java:$JAR" B2Jdbc 127.0.0.1 $PORT "$DB" dba - "$@"; }
SQLDIR="$INST/log/broker/sql_log"; SLOWDIR="$INST/log/broker/sql_log"
rm -f "$SQLDIR"/b2_*.sql.log "$SQLDIR"/b2s_*.sql.log "$SQLDIR"/b2_*.slow.log "$INST"/log/broker/b2.access* "$INST"/log/*ddl_audit*/* 2>/dev/null
cores_before=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_|cub_broker|java")

/usr/bin/env ${ENVX:-} "$CTL" start "$DB" > "$OUT/start.out" 2>&1 || { echo "ABORT: server start"; cat "$OUT/start.out"; exit 2; }
broker start; sleep 1
j "u:DROP TABLE IF EXISTS b2t" "u:CREATE TABLE b2t (id INT AUTO_INCREMENT PRIMARY KEY, v INT)" "u:INSERT INTO b2t (v) VALUES (1), (2)" > "$OUT/fixture.out" 2>&1 || { echo "ABORT: fixture"; cat "$OUT/fixture.out"; exit 2; }
sleep 1; rm -f "$SQLDIR"/b2_*.sql.log "$SQLDIR"/b2_*.slow.log

if run 1; then
  j "q:SELECT 4101 FROM db_root" "q:SELECT SLEEP(2) + 4102 FROM db_root" "s:4" "q:SELECT 4103 FROM db_root" > "$OUT/c1.out" 2>&1 &
  jp=$!
  sleep 5.2    # the connection is idle in its s:4: the flush timer wrote what the first two statements logged
  mid=$(cat "$SQLDIR"/b2_1.sql.log 2>/dev/null)
  wait $jp
  sleep 0.5
  end=$(cat "$SQLDIR"/b2_1.sql.log 2>/dev/null)
  slow=$(cat "$SQLDIR"/b2_1.slow.log 2>/dev/null)
  if echo "$mid" | grep -q "CLIENT IP 127.0.0.1" && echo "$mid" | grep -q "CLIENT VERSION" \
     && echo "$mid" | grep -q "connect db $DB@.* user dba .* session id" && echo "$mid" | grep -q "4102" \
     && ! echo "$mid" | grep -q "4103" && echo "$end" | grep -q "4103" && echo "$end" | grep -q "con_close" \
     && echo "$slow" | grep -q "4102" && ! echo "$slow" | grep -q "4101"; then
    ok 1 "sql log $(echo "$end" | wc -l) lines, flushed while idle; slow log $(echo "$slow" | wc -l) lines"
  else bad 1 "mid=$(echo "$mid" | wc -l) end=$(echo "$end" | wc -l) slow=$(echo "$slow" | wc -l)"; echo "$mid" > "$OUT/c1.mid"; fi
fi
if run 2; then
  rm -f "$SQLDIR"/b2_*.sql.log
  j "q:SELECT 4201 FROM db_root" "s:4" > "$OUT/c2-a.out" 2>&1 & pa=$!
  sleep 1
  j "q:SELECT 4202 FROM db_root" "s:3" > "$OUT/c2-b.out" 2>&1 & pb=$!
  sleep 1
  j "rows:SHOW SESSION STATUS" > "$OUT/c2-c.out" 2>&1
  wait $pa $pb; sleep 0.5
  j "q:SELECT 4204 FROM db_root" > "$OUT/c2-d.out" 2>&1; sleep 0.5
  idx=$(grep '^B2: rows' "$OUT/c2-c.out" | awk -F'|' '{print $2}' | sort | tr '\n' ' ')
  if grep -q 4201 "$SQLDIR"/b2_1.sql.log && grep -q 4202 "$SQLDIR"/b2_2.sql.log && grep -q "SESSION STATUS" "$SQLDIR"/b2_3.sql.log \
     && grep -q 4204 "$SQLDIR"/b2_1.sql.log && [ "$idx" = "1 2 3 " ]; then ok 2 "log indexes of three sessions at once: $idx; the next took 1"
  else bad 2 "idx=[$idx] files=$(ls "$SQLDIR" | grep -c '^b2_')"; fi
fi
if run 3; then
  if grep -q -E "^[0-9]+ 127\.0\.0\.1 .* $DB dba NEW [0-9]+" "$INST"/log/broker/b2.access; then ok 3 "$(grep -c NEW "$INST"/log/broker/b2.access) NEW lines"
  else bad 3 "$(ls "$INST"/log/broker/ | tr '\n' ' ')"; fi
fi
if run 4; then
  java -cp "$OUT/java:$JAR" B2Jdbc "$LANIP" $PORT "$DB" dba - "q:SELECT 4401 FROM db_root" > "$OUT/c4-a.out" 2>&1; ra=$?
  echo "${LANIP%.*}.*" > "$INST/conf/b2_ip.txt"
  cubrid server acl reload "$DB" > "$OUT/c4-reload.out" 2>&1; rr=$?
  java -cp "$OUT/java:$JAR" B2Jdbc "$LANIP" $PORT "$DB" dba - "q:SELECT 4402 FROM db_root" > "$OUT/c4-b.out" 2>&1; rb=$?
  if [ $ra -eq 3 ] && grep -q "Address is rejected" "$OUT/c4-a.out" && grep -q -E "$LANIP .* $DB dba REJECT" "$INST"/log/broker/b2.access.denied \
     && [ $rr -eq 0 ] && [ $rb -eq 0 ] && grep -q "q 4402" "$OUT/c4-b.out"; then ok 4 "rejected $LANIP, allowed after acl reload"
  else bad 4 "ra=$ra rr=$rr rb=$rb $(tail -1 "$OUT/c4-a.out")"; fi
fi
if run 5; then
  j "q:SELECT 4501 FROM db_root" "s:3" "q:SELECT 4502 FROM db_root" "s:3" "q:SELECT 4503 FROM db_root" > "$OUT/c5.out" 2>&1 & jp=$!
  sleep 1.5
  f=$(grep -l 4501 "$SQLDIR"/b2_*.sql.log | head -1)
  broker_changer B2 SQL_LOG OFF > "$OUT/c5-off.out" 2>&1; r1=$?
  sleep 3
  broker_changer B2 SQL_LOG ON > "$OUT/c5-on.out" 2>&1; r2=$?
  broker_changer B2 1 SQL_LOG ON > "$OUT/c5-cas.out" 2>&1; r3=$?
  wait $jp; sleep 0.5
  j "q:SELECT 4504 FROM db_root" > "$OUT/c5-d.out" 2>&1; sleep 0.5
  if [ $r1 -eq 0 ] && [ $r2 -eq 0 ] && ! grep -q "^OK" "$OUT/c5-cas.out" && grep -q "no CAS" "$OUT/c5-cas.out" && [ -n "$f" ] \
     && ! grep -q 4502 "$SQLDIR"/b2_*.sql.log && grep -q 4503 "$SQLDIR"/b2_*.sql.log && grep -q 4504 "$SQLDIR"/b2_*.sql.log; then
    ok 5 "OFF hid a live session's statement, ON brought it back; $(cat "$OUT/c5-cas.out" | head -1 | cut -c1-70)"
  else bad 5 "r=$r1/$r2/$r3 f=$f"; fi
fi
if run 6; then
  j "q:SELECT 4601 FROM db_root" "s:5" "q:SELECT 4602 FROM db_root" > "$OUT/c6.out" 2>&1 & jp=$!
  sleep 2
  cubrid broker reset b2 > "$OUT/c6-reset.out" 2>&1; rr=$?
  wait $jp; rc=$?; sleep 0.5
  if [ $rr -eq 0 ] && [ $rc -eq 0 ] && grep -q "q 4602" "$OUT/c6.out" && grep -q -h "RESET" "$SQLDIR"/b2_*.sql.log; then ok 6 "the idle session yielded on reset and its client went on"
  else bad 6 "reset rc=$rr client rc=$rc $(cat "$OUT/c6-reset.out" | head -2 | tr '\n' ' ')"; fi
fi
if run 7; then
  j "q:SELECT 4701 FROM db_root" "q:SELECT 4702 FROM db_root" "rows:SHOW SESSION STATUS" > "$OUT/c7.out" 2>&1
  row=$(grep '^B2: rows' "$OUT/c7.out" | head -1)
  # Token|Log_index|Broker|Client_ip|Db_user|Session_id|Tran_index|Num_requests|Num_transactions|Num_queries|...|Client_type|...|Client_version
  if echo "$row" | awk -F'|' '{exit !($3 == "b2" && $4 == "127.0.0.1" && toupper($5) == "DBA" && $10 >= 2 && $19 == "JDBC")}'; then ok 7 "$(echo "$row" | cut -c10-90)"
  else bad 7 "$row"; fi
fi
if run 8; then
  j "q:SELECT 4801 FROM db_root" "s:6" "q:SELECT 4802 FROM db_root" > "$OUT/c8.out" 2>&1 & jp=$!
  sleep 2
  j "rows:SHOW SESSION STATUS" > "$OUT/c8-status.out" 2>&1
  # the holder is the row that is not the one asking (the asker has the largest token)
  tran=$(grep '^B2: rows' "$OUT/c8-status.out" | sed 's/^B2: rows //' | sort -t'|' -k1,1n | head -1 | awk -F'|' '{print $7}')
  cubrid killtran -i "$tran" -f "$DB@localhost" > "$OUT/c8-kill.out" 2>&1; rk=$?
  sleep 1
  j "rows:SHOW SESSION STATUS" > "$OUT/c8-after.out" 2>&1
  n_after=$(grep -c '^B2: rows' "$OUT/c8-after.out")
  wait $jp; sleep 0.5
  if [ -n "$tran" ] && [ $rk -eq 0 ] && [ "$n_after" -eq 1 ] && pgrep -u "$(id -u)" -f "cub_server $DB" > /dev/null; then ok 8 "killtran $tran ended the session ($(grep -c 'q 4802' "$OUT/c8.out") reconnect read)"
  else bad 8 "tran=$tran kill rc=$rk rows after=$n_after $(tail -2 "$OUT/c8-kill.out" | tr '\n' ' ')"; fi
fi
if run 9; then
  java -cp "$OUT/java:$JAR" B2Jdbc 127.0.0.1 $SPORT "$DB" dba ssl "q:SELECT 4901 FROM db_root" "rows:SHOW SESSION STATUS" > "$OUT/c9.out" 2>&1; rc=$?
  java -cp "$OUT/java:$JAR" B2Jdbc 127.0.0.1 $SPORT "$DB" dba - "q:SELECT 4902 FROM db_root" > "$OUT/c9-plain.out" 2>&1; rp=$?
  sleep 0.5
  if [ $rc -eq 0 ] && grep -q "q 4901" "$OUT/c9.out" && grep -q 4901 "$SQLDIR"/b2s_1.sql.log && [ $rp -ne 0 ]; then ok 9 "TLS session served; a cleartext client of the SSL broker is refused (rc=$rp)"
  else bad 9 "ssl rc=$rc plain rc=$rp $(tail -1 "$OUT/c9.out" | cut -c1-150)"; fi
fi
if run 10; then
  j "u:CREATE TABLE b2ddl (x INT)" "u:DROP TABLE b2ddl" > "$OUT/c10.out" 2>&1; sleep 0.5
  f=$(grep -r -l "b2ddl" "$INST"/log/ddl_audit 2>/dev/null | head -1)
  if [ -n "$f" ] && grep -q -i "create table b2ddl" "$f"; then ok 10 "$(basename "$f"): $(grep -c b2ddl "$f") lines"
  else bad 10 "$(ls "$INST"/log | tr '\n' ' ')"; fi
fi
if run 11; then
  j "gk:INSERT INTO b2t (v) VALUES (11)" "gk:INSERT INTO b2t (v) VALUES (12)" > "$OUT/c11.out" 2>&1
  if [ "$(grep -c '^B2: gk [0-9]' "$OUT/c11.out")" -eq 2 ] && ! grep -q ERR "$OUT/c11.out"; then ok 11 "keys $(grep '^B2: gk' "$OUT/c11.out" | awk '{print $3}' | tr '\n' ' ')"
  else bad 11 "$(tail -2 "$OUT/c11.out" | tr '\n' ' ' | cut -c1-200)"; fi
fi
if run 12; then
  rm -f "$SQLDIR"/b2_*.slow.log
  j "batch:UPDATE b2t SET v = v + SLEEP(1) WHERE id = ?|1|2" > "$OUT/c12.out" 2>&1; sleep 0.5
  if grep -q "batch 2" "$OUT/c12.out" && grep -q -h "execute_array" "$SQLDIR"/b2_*.slow.log && grep -q -h "bind 1 : INT 1" "$SQLDIR"/b2_*.slow.log \
     && grep -q -h "bind 2 : INT 2" "$SQLDIR"/b2_*.slow.log; then ok 12 "slow log has the batch and its binds"
  else bad 12 "$(cat "$OUT/c12.out" | tr '\n' ' ' | cut -c1-200)"; fi
fi
if run 13; then
  j "prep:14" > "$OUT/c13.out" 2>&1
  if grep -q "^B2: prep 10$" "$OUT/c13.out"; then ok 13 "$(grep 'prep stop' "$OUT/c13.out")"
  else bad 13 "$(grep prep "$OUT/c13.out" | tr '\n' ' ')"; fi
fi
"$CTL" stop "$DB" > "$OUT/end.stop" 2>&1 || { echo "STOP FAILED"; FAIL=$((FAIL+1)); }
cores_after=$(ls /data/core/ 2>/dev/null | grep -c -E "cub_|cub_broker|java")
[ "$cores_after" -eq "$cores_before" ] || { echo "CORES: $cores_before -> $cores_after"; FAIL=$((FAIL+1)); }
grep -l -i -E 'assert|SIGSEGV|SIGABRT' "$INST"/log/server/*.err 2>/dev/null | head -3
echo "SMOKE_B2: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
