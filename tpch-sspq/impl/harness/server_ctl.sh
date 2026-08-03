#!/usr/bin/env bash
# TPCH-SSPQ implementation campaign `tpch-sspq-impl-r1-20260803` — campaign server
# start/stop with the section 3-a affinity + NUMA contract applied FROM PROCESS
# START, and the section 3-b ownership gate.
#
# WHY THE WRAPPER IS WRAPPED
# --------------------------
# Section 3-b mandates that every start/stop goes through
#   ~/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
# (raw `cubrid server ...` hangs forever when its stdout is a pipe).
# Section 3-a mandates that `cub_server` is launched under `taskset -c 0-15` with
# `numactl --membind=0`, never re-pinned afterwards. These compose in exactly one
# way: the affinity wrapper goes OUTSIDE the hang-proof wrapper, so `cub_server`
# inherits both the CPU mask and the memory policy at fork.
#
# Post-hoc `taskset` provably cannot work here. src/base/resources.cpp:190
#   context &effective () { /* must be called first in the main thread */ static context ctx = ...; }
# caches the affinity mask ONCE in a function-local static at server start, and
# resources.cpp:174-188 clearaffinity() rebinds every later pooled thread to that
# cached bitmap. A mask applied to the running server is therefore ignored by every
# thread created afterwards.
#
# Usage: server_ctl.sh start|stop|status|identity [OUT_JSON]
set -uo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${HARNESS}/campaign_env.sh"

ACTION="${1:?usage: server_ctl.sh start|stop|status|identity [OUT_JSON]}"
OUT_JSON="${2:-}"

CTL=/home/cubrid/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh
LOGDIR="${RAW_ROOT}/work/BASELINE/serverctl"
mkdir -p "$LOGDIR"
export CUBRID_SERVER_CTL_LOGDIR="$LOGDIR"

# Never pipe a cubrid command's stdout (it hangs). Everything below redirects to a
# regular file, then reads the file.
stamp() { date -u +%Y%m%dT%H%M%SZ; }

server_pid() { pgrep -f "cub_server ${CUBRID_DB}" | head -1; }
master_pid() { pgrep -x cub_master | head -1; }

case "$ACTION" in
  start)
    if [ -n "$(server_pid)" ]; then
      echo "server already running pid=$(server_pid)"; exit 0
    fi
    log="${LOGDIR}/start-$(stamp).log"
    # Affinity + membind applied at fork; the hang-proof wrapper runs inside it.
    taskset -c "$SUT_CPUS" numactl --membind="$MEMBIND_NODE" \
      "$CTL" start "$CUBRID_DB" > "$log" 2>&1 </dev/null
    rc=$?
    echo "start rc=${rc} log=${log}"
    sed -n '1,40p' "$log"
    [ "$rc" -eq 0 ] || exit "$rc"
    # settle, then prove the contract
    for i in $(seq 1 60); do [ -n "$(server_pid)" ] && break; sleep 1; done
    [ -n "$(server_pid)" ] || { echo "FATAL cub_server did not appear"; exit 1; }
    sleep 3
    exec "$0" identity "$OUT_JSON"
    ;;

  stop)
    p="$(server_pid)"
    if [ -z "$p" ]; then echo "no campaign cub_server running"; exit 0; fi
    # Section 3-b: only campaign-owned servers may be stopped. Prove ownership
    # BEFORE stopping, never after.
    exe="$(readlink -f "/proc/$p/exe" 2>/dev/null || true)"
    case "$exe" in
      "${CUBRID_HOME}/bin/cub_server") ;;
      *) echo "REFUSING to stop pid=$p exe=$exe — not campaign-owned (section 3-b)"; exit 1 ;;
    esac
    log="${LOGDIR}/stop-$(stamp).log"
    timeout 180 "$CTL" stop "$CUBRID_DB" > "$log" 2>&1 </dev/null
    rc=$?
    echo "stop rc=${rc} log=${log}"
    sed -n '1,40p' "$log"
    for i in $(seq 1 60); do [ -z "$(server_pid)" ] && break; sleep 1; done
    [ -z "$(server_pid)" ] && echo "cub_server gone" || { echo "FATAL cub_server still present"; exit 1; }
    exit 0
    ;;

  status)
    echo "cub_server pid: $(server_pid)"
    echo "cub_master pid: $(master_pid)"
    exit 0
    ;;

  identity)
    python3.11 "${HARNESS}/server_identity.py" ${OUT_JSON:+"$OUT_JSON"}
    exit $?
    ;;

  *) echo "unknown action $ACTION" >&2; exit 2 ;;
esac
