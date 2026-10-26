#!/usr/bin/env bash
# fast-cs-csql.sh — csql scripts in client/server mode against a private server, in parallel (fast-cs-jdbc.sh's
# namespaces: a user, mount, ipc, pid and net namespace per job, so no port or shm meets another job's or the host's).
# Each job overlays the install (volatile), creates a fresh en_US.utf8 database, optionally loads demodb, starts the
# server, runs `csql -u dba <db> -i <script.sql>` (stdout and stderr together), optionally dumps the plan cache, stops.
# Typical use: the same script on a release install and on a new build, then diff the two outputs.
#
# usage: fast-cs-csql.sh <out-dir> <label> <install> <script.sql> [<label> <install> <script.sql> ...]
#   per job, in <out-dir> (an existing output is never overwritten):
#     <label>.<script>.out   csql output        <label>.<script>.plandump   cubrid plandump -o (FAST_CS_PLANDUMP=1)
#     <label>.<script>.createdb.log, .loaddb.log, .server.log, .server.err, .rc, .rel
# env: FAST_CS_JOBS (default 4), FAST_CS_DEMO=1 (load the install's demo/demodb_schema+objects), FAST_CS_PLANDUMP=1,
#      FAST_CS_CONF_APPEND (server parameters, one per line), FAST_CS_TIMEOUT (seconds per job, default 1800)
# The job dirs stay under <out-dir>/.fast-cs-csql/<run>/ (database volumes included): remove them by their literal path.
set -u

SELF="$(readlink -f "${BASH_SOURCE[0]}")"

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
  export PATH="$INST/bin:$PATH" LD_LIBRARY_PATH="$INST/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export LC_ALL=en_US.utf8 LANG=en_US.utf8
  "$INST/bin/cubrid_rel" 2>&1 | head -3 >"$PFX.rel"
  ( cd "$J/db" && timeout 300 "$INST/bin/cubrid" createdb --db-volume-size=256M --log-volume-size=128M "$DB" en_US.utf8 ) \
    </dev/null >"$PFX.createdb.log" 2>&1 || exit 93
  if [ "${FAST_CS_DEMO:-0}" = 1 ]; then
    ( cd "$J/db" && timeout 300 "$INST/bin/cubrid" loaddb -u dba -s "$INST/demo/demodb_schema" -d "$INST/demo/demodb_objects" "$DB" ) \
      </dev/null >"$PFX.loaddb.log" 2>&1 || exit 93
  fi
  # daemons inherit stdout/stderr: a file, never a pipe
  timeout -k 10 120s "$INST/bin/cubrid" server start "$DB" </dev/null >"$PFX.server.log" 2>&1 || exit 94
  cd "$J" || exit 90
  timeout "${FAST_CS_TIMEOUT:-1800}" "$INST/bin/csql" -u dba "$DB" -i "$CLS" </dev/null >"$PFX.out" 2>&1
  rc=$?
  if [ "${FAST_CS_PLANDUMP:-0}" = 1 ]; then
    timeout 120 "$INST/bin/cubrid" plandump -o "$PFX.plandump" "$DB" </dev/null >/dev/null 2>&1
  fi
  cat "$INST"/log/server/"$DB"_2*.err >"$PFX.server.err" 2>/dev/null
  timeout -k 10 60s "$INST/bin/cubrid" server stop "$DB" </dev/null >>"$PFX.server.log" 2>&1
  timeout -k 5 30s "$INST/bin/cubrid" service stop </dev/null >>"$PFX.server.log" 2>&1
  exit $rc
fi

[ $# -ge 4 ] && [ $(( ($# - 1) % 3 )) -eq 0 ] || { echo "usage: fast-cs-csql.sh <out-dir> <label> <install> <script.sql> [...]"; exit 2; }
OUTD="$1"; shift
mkdir -p "$OUTD" || exit 2
OUTD="$(readlink -f "$OUTD")"
RUN="$OUTD/.fast-cs-csql/$(date -u +%Y%m%dT%H%M%SZ)-$$"
MAX="${FAST_CS_JOBS:-4}"
LABELS=(); INSTS=(); SRCS=(); PFXS=()
while [ $# -gt 0 ]; do
  label="$1"; inst="$(readlink -f "$2")"; src="$(readlink -f "$3")"; shift 3
  [ -x "$inst/bin/cub_server" ] || { echo "ERROR: $inst lacks cub_server or jdbc/cubrid_jdbc.jar"; exit 2; }
  [ -f "$src" ] || { echo "ERROR: $src not found"; exit 2; }
  pfx="$OUTD/$label.$(basename "$src" .sql)"
  for p in "${PFXS[@]}"; do [ "$p" = "$pfx" ] && { echo "ERROR: two jobs write $pfx.*"; exit 2; }; done
  for ext in out err rc rel plandump; do
    [ -e "$pfx.$ext" ] && { echo "ERROR: $pfx.$ext exists (never overwritten; pick a new label)"; exit 2; }
  done
  LABELS+=("$label"); INSTS+=("$inst"); SRCS+=("$src"); PFXS+=("$pfx")
done
mkdir -p "$RUN" || exit 2
for n in "${!PFXS[@]}"; do mkdir -p "$RUN/$n"; done

start=$(date +%s)
for n in "${!PFXS[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$MAX" ]; do wait -n; done
  J="$RUN/$n"
  (
    t0=$(date +%s%N)
    timeout -k 10 $(( ${FAST_CS_TIMEOUT:-1800} + 600 ))s unshare -Urmipnf --mount-proc --kill-child bash "$SELF" --job "$J" \
      "${INSTS[$n]}" "${SRCS[$n]}" "x" "fcj$n" "${PFXS[$n]}" >"$J/job.log" 2>&1
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
[ "$failed" -eq 0 ] || { echo "RESULT: FAILED (see <label>.<script>.rc/.out and $RUN/<n>/job.log; 90-95 = namespace/createdb/server)"; exit 1; }
echo "RESULT: OK"
