#!/usr/bin/env bash
# fast-cs-jdbc.sh — JDBC jobs against a private server + broker, in parallel (fast-cs-java.sh's namespaces: a user,
# mount, ipc, pid and net namespace per job, so the master, server and broker ports never meet another job's or the
# host's). Each job overlays the install (volatile), creates a fresh database, starts the server and the broker, runs
# a Java program through the install's own JDBC driver, optionally dumps the plan cache, and stops everything.
#
# usage: fast-cs-jdbc.sh <out-dir> <label> <install> <Main.java> [<label> <install> <Main.java> ...]
#   the program gets the JDBC URL as args[0] (jdbc:cubrid:localhost:<broker port>:<db>:::) and FAST_CS_JDBC_ARGS after it
#   per job, in <out-dir> (an existing output is never overwritten):
#     <label>.<Main>.out / .err   program stdout / stderr     <label>.<Main>.plandump   cubrid plandump -o (FAST_CS_PLANDUMP=1)
#     <label>.<Main>.createdb.log, .server.log, .broker.log, .rc, .rel
# env: FAST_CS_JOBS (default 4), FAST_CS_JDBC_ARGS, FAST_CS_PLANDUMP=1, FAST_CS_CONF_APPEND (server parameters, one per line),
#      FAST_CS_JAVA_HOME (default /usr/lib/jvm/java-1.8.0-openjdk), FAST_CS_TIMEOUT (seconds per job, default 1800)
# The job dirs stay under <out-dir>/.fast-cs-jdbc/<run>/ (database volumes included): remove them by their literal path.
set -u

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
JH="${FAST_CS_JAVA_HOME:-/usr/lib/jvm/java-1.8.0-openjdk}"

if [ "${1:-}" = "--job" ]; then
  J="$2"; INST="$3"; CLS="$4"; MAIN="$5"; DB="$6"; PFX="$7"
  mkdir -p "$J/up-install" "$J/work-install" "$J/empty" "$J/up-db" "$J/work-db" "$J/db" "$J/t" || exit 90
  /usr/sbin/ip link set lo up || exit 90
  h="$(hostname)"
  { printf '127.0.0.1\t%s\n' "$h"; /usr/bin/grep -v -w -F "$h" /etc/hosts; } >"$J/hosts" || exit 90
  mount --bind "$J/hosts" /etc/hosts || exit 90
  mount -t tmpfs -o size=256m,mode=1777 tmpfs /dev/shm || exit 90
  mount -t overlay overlay -o "lowerdir=$INST,upperdir=$J/up-install,workdir=$J/work-install,volatile,userxattr" \
    "$INST" || exit 91
  RP="$(readelf -d "$INST/bin/cub_server" | sed -n 's/.*(RPATH).*\[\(.*\)\]/\1/p')"
  { [ -z "$RP" ] || [ "$RP" = "$INST/lib" ] || [ ! -d "$RP" ]; } || mount --bind "$INST/lib" "$RP" || exit 91
  if [ -n "${FAST_CS_CONF_APPEND:-}" ]; then
    printf '%s\n' "$FAST_CS_CONF_APPEND" >>"$INST/conf/cubrid.conf" || exit 91
  fi
  mount -t overlay overlay -o "lowerdir=$J/empty,upperdir=$J/up-db,workdir=$J/work-db,volatile,userxattr" \
    "$J/db" || exit 92
  mount --bind "$J/t" /srv || exit 90
  export HOME=/home CUBRID="$INST" CUBRID_DATABASES="$J/db" CUBRID_TMP=/srv
  export PATH="$INST/bin:$JH/bin:$PATH" LD_LIBRARY_PATH="$INST/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export LC_ALL=en_US.utf8 LANG=en_US.utf8
  "$INST/bin/cubrid_rel" 2>&1 | head -3 >"$PFX.rel"
  ( cd "$J/db" && timeout 300 "$INST/bin/cubrid" createdb --db-volume-size=256M --log-volume-size=128M "$DB" en_US.utf8 ) \
    </dev/null >"$PFX.createdb.log" 2>&1 || exit 93
  # daemons inherit stdout/stderr: a file, never a pipe
  timeout -k 10 120s "$INST/bin/cubrid" server start "$DB" </dev/null >"$PFX.server.log" 2>&1 || exit 94
  timeout -k 10 120s "$INST/bin/cubrid" broker start </dev/null >"$PFX.broker.log" 2>&1 || exit 95
  port="$(awk -F= '/^\[%/{s=($0 ~ /query_editor/)} s && /^BROKER_PORT/{gsub(/[ \t]/,"",$2); print $2; exit}' \
    "$INST/conf/cubrid_broker.conf")"
  [ -n "$port" ] || exit 95
  cd "$J" || exit 90
  # shellcheck disable=SC2086
  timeout "${FAST_CS_TIMEOUT:-1800}" java -cp "$INST/jdbc/cubrid_jdbc.jar:$CLS" "$MAIN" \
    "jdbc:cubrid:localhost:$port:$DB:::" ${FAST_CS_JDBC_ARGS:-} </dev/null >"$PFX.out" 2>"$PFX.err"
  rc=$?
  if [ "${FAST_CS_PLANDUMP:-0}" = 1 ]; then
    timeout 120 "$INST/bin/cubrid" plandump -o "$PFX.plandump" "$DB" </dev/null >/dev/null 2>&1
  fi
  cat "$INST"/log/server/"$DB"_2*.err >"$PFX.server.err" 2>/dev/null
  timeout -k 10 60s "$INST/bin/cubrid" broker stop </dev/null >>"$PFX.broker.log" 2>&1
  timeout -k 10 60s "$INST/bin/cubrid" server stop "$DB" </dev/null >>"$PFX.server.log" 2>&1
  timeout -k 5 30s "$INST/bin/cubrid" service stop </dev/null >>"$PFX.server.log" 2>&1
  exit $rc
fi

[ $# -ge 4 ] && [ $(( ($# - 1) % 3 )) -eq 0 ] || { echo "usage: fast-cs-jdbc.sh <out-dir> <label> <install> <Main.java> [...]"; exit 2; }
OUTD="$1"; shift
mkdir -p "$OUTD" || exit 2
OUTD="$(readlink -f "$OUTD")"
RUN="$OUTD/.fast-cs-jdbc/$(date -u +%Y%m%dT%H%M%SZ)-$$"
MAX="${FAST_CS_JOBS:-4}"
LABELS=(); INSTS=(); SRCS=(); PFXS=()
while [ $# -gt 0 ]; do
  label="$1"; inst="$(readlink -f "$2")"; src="$(readlink -f "$3")"; shift 3
  [ -x "$inst/bin/cub_server" ] && [ -f "$inst/jdbc/cubrid_jdbc.jar" ] || { echo "ERROR: $inst lacks cub_server or jdbc/cubrid_jdbc.jar"; exit 2; }
  [ -f "$src" ] || { echo "ERROR: $src not found"; exit 2; }
  pfx="$OUTD/$label.$(basename "$src" .java)"
  for p in "${PFXS[@]}"; do [ "$p" = "$pfx" ] && { echo "ERROR: two jobs write $pfx.*"; exit 2; }; done
  for ext in out err rc rel plandump; do
    [ -e "$pfx.$ext" ] && { echo "ERROR: $pfx.$ext exists (never overwritten; pick a new label)"; exit 2; }
  done
  LABELS+=("$label"); INSTS+=("$inst"); SRCS+=("$src"); PFXS+=("$pfx")
done
mkdir -p "$RUN" || exit 2

# compile each program against its own install's driver, outside the namespaces
for n in "${!PFXS[@]}"; do
  mkdir -p "$RUN/$n/classes" || exit 2
  "$JH/bin/javac" -nowarn -cp "${INSTS[$n]}/jdbc/cubrid_jdbc.jar" -d "$RUN/$n/classes" "${SRCS[$n]}" \
    >"${PFXS[$n]}.javac.log" 2>&1 || { echo "ERROR: javac failed, see ${PFXS[$n]}.javac.log"; exit 2; }
done

start=$(date +%s)
for n in "${!PFXS[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$MAX" ]; do wait -n; done
  J="$RUN/$n"
  (
    t0=$(date +%s%N)
    timeout -k 10 $(( ${FAST_CS_TIMEOUT:-1800} + 600 ))s unshare -Urmipnf --mount-proc --kill-child bash "$SELF" --job "$J" \
      "${INSTS[$n]}" "$J/classes" "$(basename "${SRCS[$n]}" .java)" "fcj$n" "${PFXS[$n]}" >"$J/job.log" 2>&1
    rc=$?
    echo "$rc" >"${PFXS[$n]}.rc"
    echo "$rc $(( ($(date +%s%N) - t0) / 1000000 ))" >"$J/rc-elapsed"
  ) &
done
wait

failed=0
printf '%-4s %-12s %-20s %4s %9s %s\n' job label program rc elapsed_ms install
for n in "${!PFXS[@]}"; do
  J="$RUN/$n"
  { read -r rc el <"$J/rc-elapsed"; } 2>/dev/null || { rc=99; el=-; }
  printf '%-4s %-12s %-20s %4s %9s %s\n' "$n" "${LABELS[$n]}" "$(basename "${SRCS[$n]}")" "$rc" "$el" "${INSTS[$n]}"
  [ "$rc" = 0 ] || failed=1
done
echo "wall_s=$(( $(date +%s) - start )) jobs=${#PFXS[@]} max_parallel=$MAX work=$RUN"
[ "$failed" -eq 0 ] || { echo "RESULT: FAILED (see <label>.<Main>.rc/.err and $RUN/<n>/job.log; 90-95 = namespace/createdb/server/broker)"; exit 1; }
echo "RESULT: OK"
