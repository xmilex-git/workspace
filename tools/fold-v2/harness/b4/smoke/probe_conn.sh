#!/bin/bash
# probe_conn.sh <install> <dbdir> — what a JDBC driver gets when it asks a broker for a database whose server is
# down (foldv2b, in databases.txt) and for one databases.txt does not have. FOLD=1: DIRECT_HANDOFF broker.
set -u
INST="${1:?install}"; DBDIR="${2:?dbdir}"
WS=/home/cubrid/dev/workspace
HERE=$WS/.git_ignored_dir/scratch/fold-v2/b4/smoke
OUT=$HERE/out-conn-${TAG:-x}-$(date +%s)
SESSCONF=${SESSCONF:-$WS/.git_ignored_dir/conf/foldv2s0.conf}
FOLD=${FOLD:-1}
mkdir -p "$OUT"
export CUBRID="$INST" CUBRID_DATABASES="$DBDIR" PATH="$INST/bin:$PATH"
[ "$(command -v cubrid)" = "$INST/bin/cubrid" ] || { echo "ABORT: cubrid is $(command -v cubrid)"; exit 2; }
JAR=$HOME/release/CUBRID-cas-fold-v2/jdbc/cubrid_jdbc.jar
BAK="$OUT/confbak"; mkdir -p "$BAK"; cp "$INST/conf/cubrid.conf" "$INST/conf/cubrid_broker.conf" "$BAK/"
broker() { cubrid broker "$1" < /dev/null > "$OUT/broker-$1.$(date +%s%N)" 2>&1; }
cleanup() { broker stop; cp "$BAK/cubrid.conf" "$BAK/cubrid_broker.conf" "$INST/conf/"; }
trap cleanup EXIT
{ cat <<EOC
[broker]
MASTER_SHM_ID           =36790
ADMIN_LOG_FILE          =log/broker/cubrid_broker.log

[%B4]
SERVICE                 =ON
BROKER_PORT             =36701
MIN_NUM_APPL_SERVER     =2
MAX_NUM_APPL_SERVER     =2
APPL_SERVER_SHM_ID      =36791
LOG_DIR                 =log/broker/sql_log
ERROR_LOG_DIR           =log/broker/error_log
SQL_LOG                 =OFF
KEEP_CONNECTION         =ON
EOC
[ "$FOLD" = 1 ] && echo "DIRECT_HANDOFF          =ON"; } > "$OUT/cubrid_broker.conf"
(cd $WS && CONF=$SESSCONF CUBRID=$INST just conf > "$OUT/conf.out" 2>&1) || { echo "ABORT: conf"; exit 2; }
cp "$OUT/cubrid_broker.conf" "$INST/conf/cubrid_broker.conf"
mkdir -p "$OUT/java"; javac -d "$OUT/java" "$HERE/B4Jdbc.java" > "$OUT/javac.out" 2>&1 || { echo "ABORT: javac"; exit 2; }
jdbc() { d=$1; shift; java -cp "$OUT/java:$JAR" B4Jdbc 36701 "$d" dba "" "$@" 2>&1 | sed -E 's/\[CAS INFO[^]]*\]//; s/,\[SESSION-[0-9]+\]//; s/ +$//'; }
broker start; sleep 1
echo "down:    $(jdbc foldv2b 'SELECT 1' | tr '\n' '|' | cut -c1-260)"
echo "unknown: $(jdbc nosuchdb 'SELECT 1' | tr '\n' '|' | cut -c1-260)"
echo "OUT $OUT"
