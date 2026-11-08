#!/usr/bin/env bash
#
# cubrid-server-ctl.sh — hang-proof wrapper around `cubrid server start|stop|restart [db]`
#
# WHY THIS EXISTS
# --------------
# `cubrid server start <db>` launches the long-lived `cub_server` / `cub_master`
# daemons, which INHERIT the stdout/stderr file descriptors of the `cubrid`
# utility that spawned them. If those fds are a PIPE — which is exactly what
# happens when an agent (Claude Code's Bash tool), CI, `$(...)`, `... | tee`, or
# `> >(...)` captures the output — the daemon keeps the pipe's write end open
# forever. The reader never sees EOF and the call HANGS indefinitely.
#
# THE FIX
# -------
# Point the cubrid command's stdin at /dev/null and its stdout/stderr at a
# regular LOG FILE (a regular file has no reader waiting on EOF, so it can never
# cause this hang). The daemon then inherits the log-file fd, never the agent's
# capture pipe. This wrapper waits for the short-lived `cubrid` utility to finish,
# then prints a small, captured-safe summary to ITS OWN stdout and exits promptly
# — so the agent's pipe gets a clean EOF and never blocks.
#
# => Callers may capture THIS wrapper's output freely. Never run the raw
#    `cubrid server ...` command under a pipe/redirection yourself.
#
# USAGE
#   cubrid-server-ctl.sh <start|stop|restart|status> [db_name]
#
# ENV
#   CUBRID                       CUBRID install root (auto-detected if unset)
#   CUBRID_SERVER_CTL_LOGDIR     where to write logs (default: <repo>/.claude/scratch/cubrid-server-ctl)
#   CUBRID_SERVER_CTL_TIMEOUT    seconds before the cubrid call is force-killed (default: 120)
#
# EXIT CODE: forwards the underlying `cubrid` exit code (0 = success).

set -u

action="${1:-}"
db="${2:-}"

usage() {
  echo "usage: $(basename "$0") <start|stop|restart|status> [db_name]" >&2
}

case "$action" in
  start|stop|restart|status) ;;
  ""|-h|--help) usage; exit 2 ;;
  *) echo "ERROR: unknown action '$action'" >&2; usage; exit 2 ;;
esac

# --- locate the cubrid binary --------------------------------------------------
if [ -n "${CUBRID:-}" ] && [ -x "$CUBRID/bin/cubrid" ]; then
  CUBRID_BIN="$CUBRID/bin/cubrid"
elif command -v cubrid >/dev/null 2>&1; then
  CUBRID_BIN="$(command -v cubrid)"
else
  echo "ERROR: cannot find the 'cubrid' binary (set \$CUBRID or add it to PATH)" >&2
  exit 127
fi

# --- resolve a disk-backed log dir (NEVER /tmp) --------------------------------
# Prefer the project repo's .claude/scratch; fall back to the user's home scratch.
self="${BASH_SOURCE[0]}"
self="$(readlink -f "$self" 2>/dev/null || echo "$self")"
repo_root="$(cd "$(dirname "$self")/../../../.." 2>/dev/null && pwd || true)"

if [ -n "${CUBRID_SERVER_CTL_LOGDIR:-}" ]; then
  LOGDIR="$CUBRID_SERVER_CTL_LOGDIR"
elif [ -n "$repo_root" ] && [ -d "$repo_root/.claude" ]; then
  LOGDIR="$repo_root/.claude/scratch/cubrid-server-ctl"
else
  LOGDIR="$HOME/.claude/scratch/cubrid-server-ctl"
fi
mkdir -p "$LOGDIR" 2>/dev/null || { echo "ERROR: cannot create log dir '$LOGDIR'" >&2; exit 1; }

stamp="$(date +%Y%m%d-%H%M%S)"
LOG="$LOGDIR/${action}${db:+-$db}-$stamp.log"
TIMEOUT="${CUBRID_SERVER_CTL_TIMEOUT:-120}"

# --- run the command with fds DETACHED from any capturing pipe -----------------
# stdin  <- /dev/null   (no controlling terminal needed)
# stdout -> log file    (regular file: the daemon inheriting this fd cannot hang us)
# stderr -> log file
# A `timeout` backstop guards against any unexpected block.
echo "==> cubrid server $action ${db:-(all)}   [log: $LOG]"

if command -v timeout >/dev/null 2>&1; then
  timeout -k 10 "$TIMEOUT" "$CUBRID_BIN" server "$action" ${db:+"$db"} </dev/null >>"$LOG" 2>&1
  rc=$?
else
  "$CUBRID_BIN" server "$action" ${db:+"$db"} </dev/null >>"$LOG" 2>&1
  rc=$?
fi

# --- report back over the wrapper's own (safely-capturable) stdout -------------
echo "----- cubrid output -------------------------------------------------------"
if [ -s "$LOG" ]; then
  cat "$LOG"
else
  echo "(no output)"
fi
echo "---------------------------------------------------------------------------"

if [ "$rc" -eq 124 ]; then
  echo "RESULT: TIMEOUT after ${TIMEOUT}s (cubrid call was force-killed). exit=$rc"
elif [ "$rc" -eq 0 ]; then
  echo "RESULT: OK (cubrid server $action ${db:-(all)}). exit=$rc"
else
  echo "RESULT: FAILED. exit=$rc"
fi

# --- stop: also stop the master `server start` spawned (P4) ---------------------
# `cubrid server stop` leaves cub_master listening on the port.  Once no cub_server of
# this install is left, SIGTERM the install's masters — only this user's, in this
# shell's pid/net namespace (namespace jobs keep theirs) and with the same CUBRID_TMP
# (another session's socket dir is its own).  ~/CUBRID is the shared install: never.
proc_env() { tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null | sed -n "s/^$2=//p"; }
install_pids() {  # <binary name>: pids of this install's <binary>, same namespaces and CUBRID_TMP
  local p exe
  for p in $(pgrep -u "$(id -u)" -x "$1"); do
    exe="$(readlink "/proc/$p/exe" 2>/dev/null)"; exe="${exe% (deleted)}"
    [ "$exe" = "$root/bin/$1" ] || continue
    [ "$(readlink "/proc/$p/ns/pid")" = "$(readlink /proc/self/ns/pid)" ] || continue
    [ "$(readlink "/proc/$p/ns/net")" = "$(readlink /proc/self/ns/net)" ] || continue
    [ "$(proc_env "$p" CUBRID_TMP)" = "${CUBRID_TMP:-}" ] || continue
    echo "$p"
  done
}
if [ "$action" = stop ] && [ "$rc" -eq 0 ]; then
  root="$(dirname "$(dirname "$(readlink -f "$CUBRID_BIN")")")"
  if [ "$root" = "$(readlink -f "$HOME/CUBRID")" ]; then
    echo "MASTER: kept (shared install $root)"
  else
    for _ in $(seq 30); do [ -z "$(install_pids cub_server)" ] && break; sleep 1; done
    servers="$(install_pids cub_server | tr '\n' ' ')"
    masters="$(install_pids cub_master | tr '\n' ' ')"
    if [ -n "$servers" ]; then
      echo "MASTER: kept (cub_server still running: $servers)"
    elif [ -z "$masters" ]; then
      echo "MASTER: none running for $root"
    else
      kill -TERM $masters
      for _ in $(seq 10); do [ -z "$(install_pids cub_master)" ] && break; sleep 1; done
      left="$(install_pids cub_master | tr '\n' ' ')"
      if [ -z "$left" ]; then echo "MASTER: stopped $masters"; else echo "MASTER: still running after SIGTERM: $left"; fi
    fi
  fi
fi

# Quick state confirmation (status is short-lived and safe to capture directly).
echo "----- cubrid server status ------------------------------------------------"
"$CUBRID_BIN" server status </dev/null 2>&1 || true
echo "---------------------------------------------------------------------------"

exit "$rc"
