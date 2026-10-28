---
name: cubrid-server-control
description: "Start, stop, or restart a local CUBRID database server safely via a bundled wrapper script. ALWAYS use this skill (never the raw `cubrid server ...` command) whenever you are about to start/stop/restart/bounce a CUBRID server or a specific database — because the raw command HANGS forever when its output is captured by a pipe (the agent Bash tool, CI, `$(...)`, `| tee`). Use when the user says 'start/stop/restart the server', 'bounce cubrid', 'cubrid server start|stop|restart <db>', '서버 켜/꺼/재시작', 'demodb 띄워/내려', or whenever a task requires the CUBRID server to be running or stopped."
argument-hint: "<start|stop|restart|status> [db_name]"
---

# CUBRID Server Control (hang-proof)

Control the local CUBRID server lifecycle. **All server start/stop/restart MUST go
through the bundled wrapper** — never run `cubrid server ...` directly.

## Target workspace

This skill controls the CUBRID server belonging to the checkout passed as the
first argument; resolve it before doing anything else:

```bash
WORKSPACE="${1:?WORKSPACE required (pass the target CUBRID checkout)}"
```

The wrapper itself takes only the action and db name; it drives whatever `$CUBRID`
and `cubrid` on `PATH` resolve to. So every call names the install inline —
`CUBRID=<install> PATH=<install>/bin:$PATH CUBRID_DATABASES=<db dir> scripts/cubrid-server-ctl.sh …`
(the Bash tool keeps no environment between calls) — and `command -v cubrid` is checked
once against `<install>/bin/cubrid`; a profile's `CUBRID=~/CUBRID` silently drives another install.

## The one rule

`cubrid server start <db>` spawns the long-lived `cub_server`/`cub_master` daemons,
which inherit the calling process's stdout/stderr. When those fds are a **pipe**
— exactly what the agent Bash tool, CI, `$(...)`, `| tee`, or `> >(...)` create —
the daemon holds the pipe open, the reader never gets EOF, and the call **HANGS
FOREVER**. The wrapper redirects the command's output to a regular log file
(no reader → no hang), waits for completion, and prints a short, capture-safe
summary. So:

- ✅ Run the wrapper. Its output is safe to capture/pipe/redirect.
- ❌ NEVER run `cubrid server start|stop|restart` yourself — not even with
  `> log`, `2>&1`, `| tee`, or inside `$(...)`. Always delegate to the wrapper.

## Usage

```bash
.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh <start|stop|restart|status> [db_name]
```

Examples:

```bash
# start / stop / restart a specific database
scripts/cubrid-server-ctl.sh start demodb
scripts/cubrid-server-ctl.sh restart demodb
scripts/cubrid-server-ctl.sh stop demodb

# all databases (omit the name)
scripts/cubrid-server-ctl.sh start
scripts/cubrid-server-ctl.sh stop

# just check what's running (safe, read-only)
scripts/cubrid-server-ctl.sh status
```

The wrapper prints `RESULT: OK | FAILED | TIMEOUT`, the captured cubrid output,
and a `cubrid server status` snapshot. It exits with cubrid's own exit code
(`0` = success), so callers can branch on `$?`.

## Before starting

- Before any server or broker starts, `just port-claim <db> <effort>` picks a free `cubrid_port_id` in 1700–1799 and a broker hundred-block from 36000 and records the claim in `.git_ignored_dir/port-registry/claims.md`, and writes a session conf `.git_ignored_dir/conf/<db>.conf` (the campaign conf with that port) that reaches the install only through `CONF=.git_ignored_dir/conf/<db>.conf CUBRID=<install> just conf` — the installed conf is never hand-edited; `just ports` shows claims and live listeners, `just port-release <db|port>` drops the claim when the effort ends; 1523 (default master), 1568 (`~/CUBRID` install) and the 30000/33000 broker ranges are never claimed, and a port found in use by someone without a claim goes into `.git_ignored_dir/port-registry/reserved.txt`. (P1) A claim protects against agents, not against humans' servers: check `ss -ltn` too.
- Before a start, read the install's `conf/cubrid.conf`: `data_buffer_size=512M` on every server any session starts on this host (a 70 GiB host; two full gates at 16 × ~1 GB per lane ran it out), the claimed `cubrid_port_id`, and — when the run needs engine defaults — a conf holding only `cubrid_port_id`, because the campaign conf that `just conf` and `port-claim` write has `double_write_buffer_size=0` and `parallelism=24`. (P2)
- A parameter or environment variable set only for the csql client changes nothing in the server; pass it to the server's start (the wrapper inherits the caller's `CUBRID_*` environment and `$CUBRID/conf/cubrid.conf`), and read it back with `cubrid paramdump -C <db>`. (P6)
- An interactive CUBRID utility never runs in automation without its answers supplied (a flag or explicit stdin), because an EOF-looping prompt grows the log until the disk is full; automation logs get a size cap and a free-space check, and bounded evidence (statdump counters, file-size deltas) is preferred over full dumps. (P7)

## Stopping and restarting

- After `kill -9` of a hung `cub_server`, the still-running `cub_master` relaunches it within seconds (and a server that dies again within 120 s of its last relaunch stays down), so stop the server through the wrapper — or stop that install's master — before changing the conf (edit the session conf and re-apply it with `just conf`), start fresh, and once it is up confirm the parameters with `cubrid paramdump -C <db>` (hidden parameters such as `test_mode` and `parallel_sort_page_threshold` never appear there); in a crash loop, poll for the relaunch and start the server yourself when none comes. (P3)
- `cubrid server stop <db>` does not stop `cub_master`; a stray master keeps the claimed port (a listener with no `cub_server`) and a rebuilt binary then fails to bind, so stop that master by its exact pid with SIGTERM — the one whose `/proc/<pid>/exe` (or `CUBRID=` in `/proc/<pid>/environ`) is under the install — never `pkill cub` or `cubrid service stop` on this shared host, and always `server stop` (confirmed by process absence) before any master stop, so an in-flight stop is not lost and no `cub_server` is orphaned; an orphan is ended with SIGTERM, not `kill -9`. (P4)
- A control command finds the master's unix socket under `$CUBRID_TMP` (the master puts its socket at a path derived from the environment that started **it**; on this host a shared master uses `$HOME/CUBRID/var/CUBRID_SOCK`), so "Could not connect to master server" while `ps` shows a live `cub_server` and `ss -tlnp` shows the master on the port is an environment mismatch, not a hang: read the master's value with `tr '\0' '\n' < /proc/<pid>/environ | grep CUBRID_TMP`, export the same one, and keep it short — the socket path `$CUBRID_TMP/cubrid_tcp_setup_server<pid>` must fit in 107 bytes (an 83-character scratch path failed with `-359 Datagram bind error … Invalid argument`; 69 worked). (P5)
- When the effort ends, stop its servers through the wrapper, stop its master by pid (P4), `just port-release` the claim, and restore any install conf a smoke rewrote; servers left running are not fine, short SA jobs are. (P8)

The incidents behind each `P<n>` are in `PITFALLS.md`; a new lesson goes there as a case under its rule, or as a new rule added to both files in one commit.

## Workflow checklist

When you need to start/stop/restart a CUBRID server:

1. Resolve the wrapper relative to the skill dir:
   `.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh`
   (the script self-locates its repo root, so no absolute path is needed).
2. Invoke it with the action and optional `db_name`. Let the Bash tool capture
   its output normally — that is safe.
3. Read the `RESULT:` line and the status snapshot to confirm the outcome.
   On `FAILED`/`TIMEOUT`, open the log file printed in the `[log: ...]` header.
4. Never fall back to a raw `cubrid server ...` call if the wrapper is present.

## Notes

- Requires `$CUBRID` set (auto-detected; falls back to `cubrid` on `PATH`).
- Logs go to `<repo>/.claude/scratch/cubrid-server-ctl/` (override with
  `CUBRID_SERVER_CTL_LOGDIR`). Never `/tmp`.
- Force-kill backstop after `CUBRID_SERVER_CTL_TIMEOUT` seconds (default 120).
- `status` is read-only and never hangs; the others manage daemons.
