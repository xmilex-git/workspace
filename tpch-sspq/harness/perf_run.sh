#!/usr/bin/env bash
# TPCH-SSPQ FK campaign (tpch-sspq-fk-r1-20260730) — stage 14.8 profile capture.
# SSOT section 15: perf is NON-HEADLINE. Attaches to a verified PID set (never an
# all-CPU profile), captures cycles/instructions/IPC plus a dwarf call graph, and
# validates resolved-sample coverage against `perf stat`.
#
# Short queries (Q02 CUBRID ~0.35 s) cannot fill a sampling window with one
# statement, so the driver replays the identical statement in ONE connection for
# the whole window. Grouping identical variants and re-warming per block is the
# section 24 requirement; this is a diagnostic run and never a headline value.
#
# Usage: perf_run.sh QNN cubrid|postgresql N_REPEATS WINDOW_S
set -uo pipefail

QNN="${1:?usage: perf_run.sh QNN cubrid|postgresql N_REPEATS WINDOW_S}"
ENGINE="${2:?}"
NREP="${3:?}"
WIN="${4:?}"
N="$((10#${QNN#Q}))"

CAMPAIGN=tpch-sspq-fk-r1-20260730
RAW_ROOT="/data/tpch-sspq/${CAMPAIGN}"
W="${RAW_ROOT}/work/${QNN}"
REPO=/home/cubrid/dev/workspace/tpch-sspq
PG_PREFIX=/home/cubrid/pg/pg20devel-5713b437
COLLECTOR_CPUS=20-23
SUT_CPUS=0-15

# shellcheck disable=SC1091
. "${RAW_ROOT}/raw/Q01/campaign-env.sh"
mkdir -p "$W/sink"

if [ "$ENGINE" = cubrid ]; then
  SUF=cubrid; TAG=cubrid
else
  SUF=pg; TAG=pg
fi

# --- build the repeat driver -------------------------------------------------
DRV="$W/q${N}-${ENGINE}-perf-driver.sql"
: > "$DRV"
QTXT="$(cat "${REPO}/queries/q${N}-${SUF}.sql")"
case "$QTXT" in *\;) ;; *) QTXT="${QTXT};";; esac
for _ in $(seq 1 "$NREP"); do printf '%s\n' "$QTXT" >> "$DRV"; done

# --- launch the driver in the background ------------------------------------
if [ "$ENGINE" = cubrid ]; then
  taskset -c "$SUT_CPUS" "${CUBRID}/bin/csql" -C -u dba "${CUBRID_DB}" --no-pager \
      -i "$DRV" > "$W/sink/${QNN}-${ENGINE}-perf.out" 2>"$W/${QNN}-${ENGINE}-perf.err" &
else
  taskset -c "$SUT_CPUS" "${PG_PREFIX}/bin/psql" -h "$PGHOST" -p "$PGPORT" -d "$PGDATABASE" \
      -A -t -f "$DRV" > "$W/sink/${QNN}-${ENGINE}-perf.out" 2>"$W/${QNN}-${ENGINE}-perf.err" &
fi
DRIVER_PID=$!

# skip the first statement (first-statement-per-connection penalty), then resolve PIDs
sleep 1.5

PIDSET=""
if [ "$ENGINE" = cubrid ]; then
  SRV="$(pgrep -f "cub_server ${CUBRID_DB}" | head -1)"
  PIDSET="$SRV"
  echo "[pid attach] cub_server=${SRV} exe=$(readlink -f "/proc/${SRV}/exe")"
  echo "[pid attach] all query worker threads live inside this process; TIDs=$(ls "/proc/${SRV}/task" | wc -l)"
else
  LEADER="$("${PG_PREFIX}/bin/psql" -h "$PGHOST" -p "$PGPORT" -d "$PGDATABASE" -Atc \
    "select pid from pg_stat_activity where state='active' and query like '%p_size = 15%' and pid <> pg_backend_pid() order by query_start limit 1;")"
  if [ -z "$LEADER" ]; then echo "ERROR: could not resolve PG leader backend" >&2; kill $DRIVER_PID 2>/dev/null; exit 1; fi
  WORKERS="$(pgrep -P "$(pgrep -f "${PG_PREFIX}/bin/postgres -D ${PGHOST}" | head -1)" | while read -r c; do
      tr '\0' ' ' < "/proc/$c/cmdline" 2>/dev/null | grep -q 'parallel worker' && echo "$c"; done | tr '\n' ' ')"
  PIDSET="$LEADER $WORKERS"
  echo "[pid attach] leader=${LEADER} exe=$(readlink -f "/proc/${LEADER}/exe")"
  echo "[pid attach] parallel workers=${WORKERS:-<none active at sample time>}"
fi
# normalize: no empty fields / trailing comma (perf record rejects them)
normalize_pids() { echo "$*" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -un | paste -sd,; }
PIDCSV="$(normalize_pids $PIDSET)"
echo "[pid attach] perf target set = ${PIDCSV}"

# --- perf stat over the window ----------------------------------------------
taskset -c "$COLLECTOR_CPUS" perf stat -e cycles,instructions,task-clock,context-switches \
    -p "$PIDCSV" -- sleep "$WIN" 2>"$W/perf-stat-${TAG}.txt"
echo "[perf stat] -> $W/perf-stat-${TAG}.txt"

# --- perf record (call graph) over a second window --------------------------
# PG parallel workers are transient per statement, so re-resolve the set right
# before recording, and include the postmaster: perf record inherits into tasks
# forked after attach, which is how later statements' workers get sampled.
if [ "$ENGINE" = postgresql ]; then
  PM="$(pgrep -f "${PG_PREFIX}/bin/postgres -D ${PGHOST}" | head -1)"
  LEADER2="$("${PG_PREFIX}/bin/psql" -h "$PGHOST" -p "$PGPORT" -d "$PGDATABASE" -Atc \
    "select pid from pg_stat_activity where state='active' and query like '%p_size = 15%' and pid <> pg_backend_pid() order by query_start limit 1;")"
  PIDCSV="$(normalize_pids "$PM" "${LEADER2:-$LEADER}")"
  echo "[pid attach] perf record target set = ${PIDCSV} (postmaster + live leader, workers inherited)"
fi
taskset -c "$COLLECTOR_CPUS" perf record -F 999 -g --call-graph dwarf \
    -p "$PIDCSV" -o "$W/perf-${TAG}.data" -- sleep "$WIN" 2>"$W/perf-record-${TAG}.log"
echo "[perf record] -> $W/perf-${TAG}.data"

wait $DRIVER_PID 2>/dev/null
echo "[driver] exit=$? repeats=${NREP}"
grep -cE 'rows selected|^9[0-9]{3}\.' "$W/sink/${QNN}-${ENGINE}-perf.out" 2>/dev/null | sed 's/^/[driver] result-row markers: /'

# --- reports + coverage validation -------------------------------------------
perf report -i "$W/perf-${TAG}.data" --stdio --no-children -F overhead,symbol \
    --percent-limit 0.3 > "$W/profile-${TAG}-flat.txt" 2>/dev/null
perf report -i "$W/perf-${TAG}.data" --stdio -g graph,0.5,caller \
    > "$W/profile-${TAG}-callgraph.txt" 2>/dev/null

TOT=$(grep -c . "$W/profile-${TAG}-flat.txt")
UNK=$(grep -c '\[unknown\]' "$W/profile-${TAG}-flat.txt")
echo "[coverage] flat lines=${TOT} unknown-symbol lines=${UNK}"
grep -E 'samples|lost' "$W/perf-record-${TAG}.log" | sed 's/^/[coverage] /'
echo "done"
