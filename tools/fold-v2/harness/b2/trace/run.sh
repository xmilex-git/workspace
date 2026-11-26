#!/bin/bash
# run.sh <name> <config|restart|acl|lease|stats|ssl> — record one run of the instrumented build (tla2 install).
# The raw events go to trace/<name>.raw; events.py turns them into the logs of the models.
set -u
NAME="${1:?name}"; SC="${2:?scenario}"
WS=/home/cubrid/dev/workspace; S=$WS/.git_ignored_dir/scratch/fold-v2
INST=$HOME/optdebug/CUBRID-cas-fold-v2-tla2; DBDIR=$S/smoke/db; DB=foldv2s0
CTL=$WS/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
T=$S/b2/trace; PORT=36711; SPORT=36712
LANIP=$(ip -4 -o addr show scope global | awk 'NR==1{sub(/\/.*/, "", $4); print $4}')
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
JAR="$INST/jdbc/cubrid_jdbc.jar"
mkdir -p $T/java $T/$NAME.d
cp "$WS/.git_ignored_dir/conf/foldv2s0.conf" "$T/$NAME.d/sess.conf"
printf 'cas_access_control=yes\ncas_access_control_file=%s/conf/b2t_acl.txt\n' "$INST" >> "$T/$NAME.d/sess.conf"
(cd $WS && CONF=$T/$NAME.d/sess.conf CUBRID=$INST just conf > $T/$NAME.d/conf.out 2>&1) || { echo "ABORT: conf"; exit 2; }
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=b2trace" -keyout "$T/$NAME.d/ssl.key" -out "$T/$NAME.d/ssl.crt" > "$T/$NAME.d/openssl.out" 2>&1 || { echo "ABORT: openssl"; exit 2; }
cp "$T/$NAME.d/ssl.crt" "$INST/conf/cas_ssl_cert.crt"; cp "$T/$NAME.d/ssl.key" "$INST/conf/cas_ssl_cert.key"; chmod 600 "$INST/conf/cas_ssl_cert.key"
cat > "$INST/conf/cubrid_broker.conf" <<EOC
[broker]
MASTER_SHM_ID           =36790
ADMIN_LOG_FILE          =log/broker/cubrid_broker.log

[%B2T]
SERVICE                 =ON
BROKER_PORT             =$PORT
MIN_NUM_APPL_SERVER     =4
MAX_NUM_APPL_SERVER     =4
APPL_SERVER_SHM_ID      =36791
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =ON
LONG_QUERY_TIME         =60
SESSION_TIMEOUT         =300
KEEP_CONNECTION         =ON
DIRECT_HANDOFF          =ON

[%B2TS]
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
aclfile() {   # aclfile <rules>: the access control file with that many rules of the B2T broker (its version)
  { echo "[%B2T]"; for i in $(seq 1 "$1"); do echo "$DB:dba:b2t_ip.txt"; done; } > "$INST/conf/b2t_acl.txt.new"
  mv "$INST/conf/b2t_acl.txt.new" "$INST/conf/b2t_acl.txt"
}
mark() { python3 -c "import time,os,sys; open(sys.argv[1],'a').write('TLATRACE %d %d %d %s\n' % (time.monotonic_ns(), os.getpid(), os.getpid(), sys.argv[2]))" "$T/$NAME.raw" "$1"; }
aclfile 1; echo "${LANIP%.*}.*" > "$INST/conf/b2t_ip.txt"
javac -d $T/java $S/b2/smoke/B2Jdbc.java || exit 2
: > $T/$NAME.raw
export CUBRID_TLATRACE_OUT=$T/$NAME.raw
broker() { cubrid broker "$1" < /dev/null > "$T/$NAME.d/broker-$1.$(date +%s%N).out" 2>&1; }
j() { java -cp "$T/java:$JAR" B2Jdbc 127.0.0.1 $PORT "$DB" dba - "$@"; }
jl() { java -cp "$T/java:$JAR" B2Jdbc "$LANIP" $PORT "$DB" dba - "$@"; }
"$CTL" start "$DB" > $T/$NAME.d/start.out 2>&1 || { echo "ABORT: server start"; exit 2; }
broker start; sleep 1
rc=0
case "$SC" in
  config)   # a live session takes a change at its next request; a later session is handed the new conf
    j "q:SELECT 1 FROM db_root" "s:3" "q:SELECT 2 FROM db_root" "s:3" "q:SELECT 3 FROM db_root" > $T/$NAME.d/a.out 2>&1 & pa=$!
    sleep 1.5; broker_changer B2T LONG_QUERY_TIME 61 > $T/$NAME.d/ch1.out 2>&1
    sleep 1; j "q:SELECT 4 FROM db_root" "s:3" "q:SELECT 5 FROM db_root" > $T/$NAME.d/b.out 2>&1 & pb=$!
    sleep 2; broker_changer B2T LONG_QUERY_TIME 62 > $T/$NAME.d/ch2.out 2>&1
    wait $pa $pb ;;
  restart)  # the broker restarts under a live session; the change after it reaches the session's server
    j "q:SELECT 1 FROM db_root" "s:7" "q:SELECT 2 FROM db_root" > $T/$NAME.d/a.out 2>&1 & pa=$!
    sleep 1.5; broker stop; broker start; sleep 1
    broker_changer B2T LONG_QUERY_TIME 61 > $T/$NAME.d/ch1.out 2>&1
    wait $pa ;;
  acl)      # checks from an address that is not the loopback; two reloads at once; a rewrite; an unreadable rewrite
    jl "q:SELECT 1 FROM db_root" > $T/$NAME.d/a.out 2>&1
    cubrid server acl reload "$DB" > $T/$NAME.d/r1.out 2>&1 & cubrid server acl reload "$DB" > $T/$NAME.d/r2.out 2>&1 & wait
    aclfile 2; mark "FEdit bad=0"; sleep 0.5
    cubrid server acl reload "$DB" > $T/$NAME.d/r3.out 2>&1
    jl "q:SELECT 2 FROM db_root" > $T/$NAME.d/b.out 2>&1
    aclfile 3; echo "$DB:dba:b2t_missing.txt" >> "$INST/conf/b2t_acl.txt"; mark "FEdit bad=1"; sleep 0.5
    cubrid server acl reload "$DB" > $T/$NAME.d/r4.out 2>&1
    jl "q:SELECT 3 FROM db_root" > $T/$NAME.d/c.out 2>&1
    aclfile 4; mark "FEdit bad=0"; sleep 0.5
    cubrid server acl reload "$DB" > $T/$NAME.d/r5.out 2>&1
    jl "q:SELECT 4 FROM db_root" > $T/$NAME.d/d.out 2>&1 ;;
  lease)    # three sessions at once, one leaves, the next takes its index; the server is killed; the first index again
    j "q:SELECT 1 FROM db_root" "s:2" > $T/$NAME.d/a.out 2>&1 & pa=$!
    sleep 0.7; j "q:SELECT 2 FROM db_root" "s:4" > $T/$NAME.d/b.out 2>&1 & pb=$!
    sleep 0.7; j "q:SELECT 3 FROM db_root" "s:30" > $T/$NAME.d/c.out 2>&1 & pc=$!
    wait $pa; j "q:SELECT 4 FROM db_root" > $T/$NAME.d/d.out 2>&1
    wait $pb
    spid=""; for p in $(pgrep -x cub_server); do [ "$(readlink /proc/$p/exe 2>/dev/null)" = "$(readlink -f "$INST/bin/cub_server")" ] && spid=$p; done
    kill -9 $spid; mark "Crash pid=$spid"; wait $pc
    sleep 2; "$CTL" stop "$DB" > $T/$NAME.d/stop-killed.out 2>&1
    "$CTL" start "$DB" > $T/$NAME.d/start2.out 2>&1 || { echo "ABORT: second start"; rc=1; }
    sleep 1; j "q:SELECT 5 FROM db_root" > $T/$NAME.d/e.out 2>&1 ;;
  stats)    # two sessions; SHOW SESSION STATUS; killtran of one of them
    j "q:SELECT 1 FROM db_root" "s:6" "q:SELECT 2 FROM db_root" > $T/$NAME.d/a.out 2>&1 & pa=$!
    sleep 2; j "q:SELECT 3 FROM db_root" "rows:SHOW SESSION STATUS" > $T/$NAME.d/b.out 2>&1
    tran=$(grep '^B2: rows' $T/$NAME.d/b.out | sed 's/^B2: rows //' | sort -t'|' -k1,1n | head -1 | awk -F'|' '{print $7}')
    cubrid killtran -i "$tran" -f "$DB@localhost" > $T/$NAME.d/kill.out 2>&1 || rc=1
    wait $pa ;;
  ssl)      # a TLS client through DIRECT_HANDOFF_SSL_DB
    java -cp "$T/java:$JAR" B2Jdbc 127.0.0.1 $SPORT "$DB" dba ssl "q:SELECT 1 FROM db_root" > $T/$NAME.d/a.out 2>&1 || rc=1 ;;
  *) echo "unknown scenario"; rc=2 ;;
esac
sleep 1
broker stop
"$CTL" stop "$DB" > $T/$NAME.d/stop.out 2>&1
unset CUBRID_TLATRACE_OUT
rm -f "$INST/conf/b2t_acl.txt" "$INST/conf/b2t_ip.txt"
echo "scenario $SC rc=$rc raw=$(wc -l < $T/$NAME.raw) $(cat $T/$NAME.d/[a-e].out 2>/dev/null | /usr/bin/grep -c -E '^B2: (q|rows) ') result lines, $(cat $T/$NAME.d/[a-e].out 2>/dev/null | /usr/bin/grep -c 'ERR') errors"
