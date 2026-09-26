#!/usr/bin/env bash
# fast-sa.sh — stand-alone (csql -S) probe jobs in parallel. Each job runs in its own user+mount+IPC+PID namespace
# (unshare -Urmipf): the install is a volatile overlay (SA error logs and every other write stay out of it) and the
# job's database is created fresh on a volatile overlay (fsync never reaches the disk).
# It replaces run-probe.sh (one database per label, its files run one after another) with one fresh database per job,
# so a probe file must create what it reads (the #343 probes and every CTP case do).
#
# usage: fast-sa.sh <out-dir> <label> <install> <sql> [<label> <install> <sql> ...]
#   per job, in <out-dir> (created if missing; an existing output is never overwritten):
#     <label>.<sql base>.out / .err   csql stdout / stderr (the names run-probe.sh used)
#     <label>.<sql base>.createdb.log, .rc (csql exit code; 90-93 = namespace/createdb failure), .rel (cubrid_rel)
#   work: <out-dir>/.fast-sa/<run>/<n>/ — up-install/ keeps that job's SA logs; its database is removed at the end
# env: FAST_SA_JOBS   jobs at once (default 16)
set -u

SELF="$(readlink -f "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------------------------------------------------------
# inside one job's namespaces (ns-root; PID 1): fast-sa.sh --job <job dir> <install> <sql> <db> <output prefix>
# ---------------------------------------------------------------------------------------------------------------
if [ "${1:-}" = "--job" ]; then
  J="$2"; INST="$3"; SQL="$4"; DB="$5"; PFX="$6"
  mkdir -p "$J/up-install" "$J/work-install" "$J/empty" "$J/up-db" "$J/work-db" "$J/db" "$J/t" || exit 90
  mount -t overlay overlay -o "lowerdir=$INST,upperdir=$J/up-install,workdir=$J/work-install,volatile,userxattr" \
    "$INST" || exit 91
  mount -t overlay overlay -o "lowerdir=$J/empty,upperdir=$J/up-db,workdir=$J/work-db,volatile,userxattr" \
    "$J/db" || exit 92
  # CUBRID_TMP holds the PL server's unix socket (108-byte path limit): a short private path
  mount --bind "$J/t" /srv || exit 90
  # POSIX shm names carry the pid (DMRB: /cubbase_dmrb_<pid>_<n>), and pids repeat across PID namespaces
  mount -t tmpfs -o size=64m,mode=1777 tmpfs /dev/shm || exit 90
  export HOME=/home CUBRID="$INST" CUBRID_DATABASES="$J/db" CUBRID_TMP=/srv
  export PATH="$INST/bin:$PATH" LD_LIBRARY_PATH="$INST/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export LC_ALL=en_US.utf8 LANG=en_US.utf8
  "$INST/bin/cubrid_rel" 2>&1 | head -1 >"$PFX.rel"
  ( cd "$J/db" && timeout 300 "$INST/bin/cubrid" createdb --db-volume-size=20M --log-volume-size=20M "$DB" en_US.utf8 ) \
    </dev/null >"$PFX.createdb.log" 2>&1 || exit 93
  cd "$J" || exit 90
  timeout 600 "$INST/bin/csql" -S -u dba --no-auto-commit --no-pager -i "$SQL" "$DB" </dev/null >"$PFX.out" 2>"$PFX.err"
  exit $?
fi

# ---------------------------------------------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------------------------------------------
[ $# -ge 4 ] && [ $(( ($# - 1) % 3 )) -eq 0 ] || { echo "usage: fast-sa.sh <out-dir> <label> <install> <sql> [...]"; exit 2; }
OUTD="$1"; shift
mkdir -p "$OUTD" || exit 2
OUTD="$(readlink -f "$OUTD")"
RUN="$OUTD/.fast-sa/$(date -u +%Y%m%dT%H%M%SZ)-$$"
MAX="${FAST_SA_JOBS:-16}"
LABELS=(); INSTS=(); SQLS=(); PFXS=()
while [ $# -gt 0 ]; do
  label="$1"; inst="$(readlink -f "$2")"; sql="$(readlink -f "$3")"; shift 3
  [ -x "$inst/bin/csql" ] || { echo "ERROR: $inst is not a CUBRID install"; exit 2; }
  [ -f "$sql" ] || { echo "ERROR: $sql not found"; exit 2; }
  pfx="$OUTD/$label.$(basename "$sql" .sql)"
  for p in "${PFXS[@]}"; do [ "$p" = "$pfx" ] && { echo "ERROR: two jobs write $pfx.*"; exit 2; }; done
  for ext in out err createdb.log rc rel; do
    [ -e "$pfx.$ext" ] && { echo "ERROR: $pfx.$ext exists (never overwritten; pick a new label)"; exit 2; }
  done
  LABELS+=("$label"); INSTS+=("$inst"); SQLS+=("$sql"); PFXS+=("$pfx")
done
mkdir -p "$RUN" || exit 2

start=$(date +%s)
for n in "${!PFXS[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$MAX" ]; do wait -n; done
  J="$RUN/$n"; mkdir -p "$J"
  (
    t0=$(date +%s%N)
    timeout -k 10 900s unshare -Urmipf --mount-proc --kill-child bash "$SELF" --job "$J" "${INSTS[$n]}" "${SQLS[$n]}" \
      "fsa$n" "${PFXS[$n]}" >"$J/job.log" 2>&1
    rc=$?
    echo "$rc" >"${PFXS[$n]}.rc"
    echo "$rc $(( ($(date +%s%N) - t0) / 1000000 ))" >"$J/rc-elapsed"
  ) &
done
wait

failed=0
printf '%-4s %-12s %-28s %4s %9s %6s %s\n' job label sql rc elapsed_ms errB install
for n in "${!PFXS[@]}"; do
  J="$RUN/$n"
  { read -r rc el <"$J/rc-elapsed"; } 2>/dev/null || { rc=99; el=-; }
  errb=$(stat -c %s "${PFXS[$n]}.err" 2>/dev/null || echo -)
  printf '%-4s %-12s %-28s %4s %9s %6s %s\n' "$n" "${LABELS[$n]}" "$(basename "${SQLS[$n]}")" "$rc" "$el" "$errb" "${INSTS[$n]}"
  [ "$rc" = 0 ] || failed=1
  # the database and the overlay work dirs go; up-install (the job's SA logs) and job.log stay
  chmod -R u+rwx -- "${J:?}/work-install" "${J:?}/work-db" 2>/dev/null
  rm -rf -- "${J:?}/up-db" "${J:?}/work-db" "${J:?}/work-install" "${J:?}/empty" "${J:?}/db" "${J:?}/t"
done
echo "wall_s=$(( $(date +%s) - start )) jobs=${#PFXS[@]} max_parallel=$MAX work=$RUN"
[ "$failed" -eq 0 ] || { echo "RESULT: FAILED (see <label>.<sql>.rc and $RUN/<n>/job.log)"; exit 1; }
echo "RESULT: OK"
