#!/usr/bin/env bash
# fast-counters.sh — the DomainBench counter harness (JDBC; DomainBench.java unchanged) split over parallel C/S stacks.
#
# Each stack runs in its own user+mount+IPC+PID+net namespace (unshare -Urmipnf): the install and the bench database
# are volatile overlays (fsync never reaches the disk, nothing is written to either lower), ports, SysV shm and
# /dev/shm are private (every stack uses the conf's own ports; /etc/hosts maps the host name to loopback there), and
# every cub_* process dies with its namespace.
#
# Sharding (the sequential harness spends ~6 min on p0; P2-expr alone is ~1 min):
#   - a cell always runs whole in one stack, L -> H= -> H!= on one connection, as in the sequential harness;
#   - cells that share one SQL text (P1-int, P7-scan-0) share a stack, in the sequential order;
#   - p0 cells go to 8 stacks balanced by the per-cell time of #342's gate run (t342-c1, 5 measured reps, ms):
#       P2-expr 50500 | P3-agg 35756 | P6-in 34691 | P8-values 16622 + P3-analytic 11791 + P7-agg-0 8672
#       | P1-numeric 14209 + P3-lead 12001 + P1-string 10045 | P4-topn 13494 + P1-date 12582 + P9-range-heap 10880
#       | P4-group 13333 + P3-group 13043 + P6-union 9750 | rest: P1-int 11444 + P7-scan-0 9722 + P6-cte 10913 + P5-* ...
#     the "rest" stack takes every cell not named (so a cell added to DomainBench later is never skipped);
#   - the p24 cells run in a ninth stack with parallelism=24.
#
# usage: fast-counters.sh <out-dir> <install>
#   out-dir  must not exist. Results: <out-dir>/output/counters-p0.tsv, counters-p24.tsv (+ .err, the sequential
#            harness's format: one header, one row per cell/variant/rep), <out-dir>/logs/provenance.txt, and per stack
#            <out-dir>/s/<n>/ (stack.log, bench.tsv/.err, up-install/log = that stack's server and broker logs).
#   install  the CUBRID install to measure. Only read: the conf copy (campaign cubrid.conf + parallelism) and every
#            log land in the stack's overlay.
# env: FAST_CTR_SHARDS=1   all p0 cells in one stack, the sequential harness's order (equivalence checks)
#      FAST_CTR_CONF=path  conf source (default: the tooling repo's campaign cubrid.conf, what `just conf` copies)
#      FAST_GATE_ROOT=dir  the checkout whose .git_ignored_dir holds the bench assets (default: this script's checkout)
set -u

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
HERE="$(dirname "$SELF")"
REPO="${FAST_GATE_ROOT:-$(cd "$HERE/../.." && pwd)}"
SRC_BASE="$REPO/.git_ignored_dir/scratch/312-330/baseline-runtime"	# DomainBench.java and the bench database
DBNAME=dpin330bench
DBPATH="$SRC_BASE/db/bench"		# the path databases.txt and the volume info record; each stack mounts over it
BASE="$REPO/.git_ignored_dir/scratch/fast-gate/base"	# reflink snapshot of $DBPATH, every stack's database lower
URL="jdbc:cubrid:localhost:30000:$DBNAME:dba::"

# ---------------------------------------------------------------------------------------------------------------
# inside one stack's namespaces (ns-root; PID 1): fast-counters.sh --stack <stack dir> <parallelism> <cell regex>
# ---------------------------------------------------------------------------------------------------------------
if [ "${1:-}" = "--stack" ]; then
  S="$2"; MODE="$3"; REGEX="$4"
  cd "$S" || exit 90
  step() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }
  die() { step "FAILED: $*"; exit 91; }
  mkdir -p "$S/up-install" "$S/work-install" "$S/up-db" "$S/work-db" "$S/t" "$S/reg" "$S/jtmp" || die mkdir
  /usr/sbin/ip link set lo up || die "lo up"
  # the server reaches its master through the host name, which /etc/hosts maps to an address this namespace lacks
  h="$(hostname)"
  { printf '127.0.0.1\t%s\n' "$h"; /usr/bin/grep -v -w -F "$h" /etc/hosts; } >"$S/hosts" || die hosts
  mount --bind "$S/hosts" /etc/hosts || die "hosts bind"
  # POSIX shm names carry the pid (DMRB: /cubbase_dmrb_<pid>_<n>), and pids repeat across PID namespaces
  mount -t tmpfs -o size=64m,mode=1777 tmpfs /dev/shm || die "private /dev/shm"
  mount -t overlay overlay -o "lowerdir=$INSTALL,upperdir=$S/up-install,workdir=$S/work-install,volatile,userxattr" \
    "$INSTALL" || die "install overlay"
  mount -t overlay overlay -o "lowerdir=$BASE/bench,upperdir=$S/up-db,workdir=$S/work-db,volatile,userxattr" \
    "$DBPATH" || die "db overlay"
  # CUBRID_TMP holds the master's and the PL server's unix sockets (108-byte path limit): a short private path
  mount --bind "$S/t" /srv || die "CUBRID_TMP bind"
  cp "$BASE/databases.txt" "$S/reg/databases.txt" || die registry
  cp "$CONF_SRC" "$INSTALL/conf/cubrid.conf" || die conf
  sed -i -E "s/^parallelism=.*/parallelism=$MODE/" "$INSTALL/conf/cubrid.conf" || die "conf parallelism"
  export HOME=/home CUBRID="$INSTALL" CUBRID_DATABASES="$S/reg" CUBRID_TMP=/srv
  export PATH="$INSTALL/bin:$PATH" LD_LIBRARY_PATH="$INSTALL/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export LC_ALL=en_US.utf8 LANG=en_US.utf8
  step "conf: $(/usr/bin/grep -E '^parallelism=' "$INSTALL/conf/cubrid.conf"); $h -> $(python3 -c 'import socket,sys; print(socket.gethostbyname(sys.argv[1]))' "$h")"
  # stdout/stderr to files: the daemons inherit them (a pipe would hang the caller)
  timeout -k 10 90s cubrid server start "$DBNAME" </dev/null >"$S/server-start.log" 2>&1 || die "server start (server-start.log)"
  timeout -k 5 60s cubrid broker start </dev/null >"$S/broker-start.log" 2>&1 || die "broker start (broker-start.log)"
  for i in $(seq 1 60); do	# a LISTEN socket on 30000 (0x7530) in this namespace; no probe connection
    awk '$2 ~ /:7530$/ && $4 == "0A" { f = 1 } END { exit !f }' /proc/net/tcp /proc/net/tcp6 2>/dev/null && break
    [ "$i" -eq 60 ] && die "broker port 30000 not ready"
    sleep 1
  done
  step "stack up (broker port ready after ${i}s); java cells=$REGEX"
  BENCH_PARALLELISM="$MODE" timeout -k 10 540s java -XX:-UsePerfData -Djava.io.tmpdir="$S/jtmp" \
    -cp "$JAR:$CLASSES" DomainBench "$URL" run "$REGEX" >"$S/bench.tsv" 2>"$S/bench.err"
  rc=$?
  step "java rc=$rc"
  timeout -k 5 30s cubrid broker stop </dev/null >"$S/stop.log" 2>&1
  timeout -k 10 60s cubrid server stop "$DBNAME" </dev/null >>"$S/stop.log" 2>&1
  timeout -k 5 30s cubrid service stop </dev/null >>"$S/stop.log" 2>&1
  step "stopped; namespace exit"
  exit "$rc"
fi

# ---------------------------------------------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------------------------------------------
OUT="${1:?usage: fast-counters.sh <out-dir> <install>}"
INSTALL="$(readlink -f "${2:?usage: fast-counters.sh <out-dir> <install>}")"
CONF_SRC="${FAST_CTR_CONF:-$REPO/cubrid.conf}"
[ -e "$OUT" ] && { echo "ERROR: $OUT exists (a run never reuses an out-dir)"; exit 2; }
[ -x "$INSTALL/bin/cub_server" ] || { echo "ERROR: $INSTALL is not a CUBRID install"; exit 2; }
[ -f "$CONF_SRC" ] || { echo "ERROR: conf source $CONF_SRC not found"; exit 2; }
JAR="$(ls "$INSTALL"/jdbc/cubrid-jdbc-*.jar 2>/dev/null | /usr/bin/grep -v -E -- '-(javadoc|sources)\.jar$' | head -1)"
[ -n "$JAR" ] || JAR="$INSTALL/jdbc/cubrid_jdbc.jar"
[ -f "$JAR" ] || { echo "ERROR: no JDBC jar under $INSTALL/jdbc"; exit 2; }
mkdir -p "$OUT/output" "$OUT/logs" "$OUT/classes" "$OUT/s" || exit 2
OUT="$(readlink -f "$OUT")"
CLASSES="$OUT/classes"
PROV="$OUT/logs/provenance.txt"
utc() { date -u +%FT%TZ; }

# the database lower: a reflink snapshot, taken once while no server has the bench database open
mkdir -p "$BASE" || exit 3
exec 9>"$BASE/.snapshot.lock"; flock 9
if [ ! -d "$BASE/bench" ]; then
  if pgrep -f "^cub_server $DBNAME" >/dev/null; then
    echo "ERROR: a cub_server has $DBNAME open; cannot snapshot $DBPATH now"; exit 3
  fi
  rm -rf -- "${BASE:?}/bench.partial"
  cp -a --reflink=always "$DBPATH" "$BASE/bench.partial" || { echo "ERROR: reflink snapshot failed"; exit 3; }
  cp "$SRC_BASE/db/databases.txt" "$BASE/databases.txt" || exit 3
  printf 'snapshot of %s taken %s (reflink)\n' "$DBPATH" "$(utc)" >"$BASE/SNAPSHOT.txt"
  mv "$BASE/bench.partial" "$BASE/bench" || exit 3
fi
flock -u 9; exec 9>&-

{
  printf 'label=%s\ninstall=%s\ndb=%s\nurl=%s\n' "$(basename "$OUT")" "$INSTALL" "$DBNAME" "$URL"
  printf 'runner=%s (parallel stacks, volatile overlays; DomainBench unchanged: %s)\n' "$SELF" "$SRC_BASE/bench/DomainBench.java"
  printf 'db_lower=%s/bench (%s)\n' "$BASE" "$(cat "$BASE/SNAPSHOT.txt")"
  printf 'libcubrid_sha256=%s\n' "$(sha256sum "$INSTALL/lib/libcubrid.so" | cut -d' ' -f1)"
  printf 'cub_server_sha256=%s\n' "$(sha256sum "$INSTALL/bin/cub_server" | cut -d' ' -f1)"
  printf 'jdbc=%s sha256=%s\n' "$JAR" "$(sha256sum "$JAR" | cut -d' ' -f1)"
  printf 'db_registration_sha256=%s\n' "$(sha256sum "$BASE/databases.txt" | cut -d' ' -f1)"
  printf 'conf_source=%s sha256=%s\n' "$CONF_SRC" "$(sha256sum "$CONF_SRC" | cut -d' ' -f1)"
  printf 'started_utc=%s\n' "$(utc)"
} >"$PROV"

javac -cp "$JAR" -d "$CLASSES" "$SRC_BASE/bench/DomainBench.java" >"$OUT/logs/javac.log" 2>&1
rc=$?
printf 'javac_rc=%s\n' "$rc" >>"$PROV"
[ "$rc" -eq 0 ] || { echo "ERROR: javac failed (logs/javac.log)"; exit 4; }

NAMED="P2-expr|P3-agg|P6-in|P8-values|P3-analytic|P7-agg-0|P1-numeric|P3-lead|P1-string|P4-topn|P1-date|P9-range-heap|P4-group|P3-group|P6-union"
if [ "${FAST_CTR_SHARDS:-8}" = 1 ]; then
  P0=(".*")
else
  P0=("P2-expr" "P3-agg" "P6-in" "P8-values|P3-analytic|P7-agg-0" "P1-numeric|P3-lead|P1-string"
      "P4-topn|P1-date|P9-range-heap" "P4-group|P3-group|P6-union" "(?!(?:$NAMED)\$).*")
fi
MODES=(); REGEXES=()
for r in "${P0[@]}"; do MODES+=(0); REGEXES+=("$r"); done
MODES+=(24); REGEXES+=(".*")

export INSTALL BASE DBPATH CONF_SRC JAR CLASSES
PIDS=()
for n in "${!MODES[@]}"; do
  S="$OUT/s/$n"; mkdir -p "$S"
  printf 'stack=%s mode=%s cells=%s start_utc=%s\n' "$n" "${MODES[$n]}" "${REGEXES[$n]}" "$(utc)" >>"$PROV"
  timeout -k 10 700s unshare -Urmipnf --mount-proc --kill-child bash "$SELF" --stack "$S" "${MODES[$n]}" "${REGEXES[$n]}" \
    >"$S/stack.log" 2>&1 &
  PIDS+=($!)
done
failed=0
for n in "${!PIDS[@]}"; do
  wait "${PIDS[$n]}"; rc=$?
  S="$OUT/s/$n"
  printf 'stack=%s rc=%s rows=%s errors=%s end_utc=%s\n' "$n" "$rc" "$({ wc -l <"$S/bench.tsv"; } 2>/dev/null || echo 0)" \
    "$({ wc -l <"$S/bench.err"; } 2>/dev/null || echo 0)" "$(utc)" >>"$PROV"
  [ "$rc" -eq 0 ] || failed=1
  # the database upper holds the copied-up volumes (reflinks); only the logs are kept
  chmod -R u+rwx -- "${S:?}/work-install" "${S:?}/work-db" 2>/dev/null
  rm -rf -- "${S:?}/up-db" "${S:?}/work-db" "${S:?}/work-install" "${S:?}/jtmp"
done

python3 - "$OUT" "${MODES[@]}" <<'EOF' >>"$PROV"
import sys, os
out, modes = sys.argv[1], sys.argv[2:]
ORDER = ["P1-int", "P1-string", "P1-numeric", "P1-date", "P2-expr", "P3-agg", "P3-group", "P3-lead", "P3-analytic",
         "P4-topn", "P4-group", "P5-eq", "P5-between", "P5-multi", "P5-correlated", "P5-iss", "P5-mro", "P6-in",
         "P6-union", "P6-cte", "P7-scan-0", "P7-agg-0", "P7-scan-24", "P7-agg-24", "P8-values", "P9-range-heap",
         "P9-range-index"]
for mode in sorted(set(modes), key=int):
    header, rows, errs, seen = None, [], [], set()
    for n, m in enumerate(modes):
        if m != mode:
            continue
        s = os.path.join(out, "s", str(n))
        try:
            lines = open(os.path.join(s, "bench.tsv")).read().splitlines()
        except OSError:
            lines = []
        if lines:
            if header is None:
                header = lines[0]
            elif lines[0] != header:
                print(f"merge: stack {n} header differs")
            for l in lines[1:]:
                key = tuple(l.split("\t")[:4])
                if key in seen:
                    print(f"merge: duplicate row {key} (stack {n})")
                seen.add(key)
                rows.append(l)
        try:
            errs += open(os.path.join(s, "bench.err")).read().splitlines()
        except OSError:
            pass
    rank = {c: i for i, c in enumerate(ORDER)}
    rows.sort(key=lambda l: rank.get(l.split("\t")[0], len(ORDER)))  # stable: shard order within a cell
    with open(os.path.join(out, "output", f"counters-p{mode}.tsv"), "w") as f:
        if header is not None:
            f.write(header + "\n")
        for l in rows:
            f.write(l + "\n")
    with open(os.path.join(out, "output", f"counters-p{mode}.err"), "w") as f:
        for l in errs:
            f.write(l + "\n")
    print(f"mode={mode} rows={len(rows) + (header is not None)} errors={len(errs)}")
EOF
printf 'finished_utc=%s\n' "$(utc)" >>"$PROV"
cat "$PROV"
[ "$failed" -eq 0 ] || { echo "RESULT: FAILED (a stack failed: see s/<n>/stack.log)"; exit 1; }
echo "RESULT: OK"
