# PITFALLS — the rules in SKILL.md and the incidents that produced them

Each `P<n>` is one rule. The **Rule** line is the exact sentence SKILL.md carries at the step named in
**Applies at**; keep the two byte-identical. **Case** is the incident that paid for the rule. **Source**
is where the lesson lived before it was folded in here (auto-memory slugs are deleted once absorbed;
kept for traceability only).

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule only when no rule fits — then add the sentence to SKILL.md in the same commit.

### P1 — claim the port first
- Rule: Before any server or broker starts, `just port-claim <db> <effort>` picks a free `cubrid_port_id` in 1700–1799 and a broker hundred-block from 36000 and records the claim in `.git_ignored_dir/port-registry/claims.md`, and writes a session conf `.git_ignored_dir/conf/<db>.conf` (the campaign conf with that port) that reaches the install only through `CONF=.git_ignored_dir/conf/<db>.conf CUBRID=<install> just conf` — the installed conf is never hand-edited; `just ports` shows claims and live listeners, `just port-release <db|port>` drops the claim when the effort ends; 1523 (default master), 1568 (`~/CUBRID` install) and the 30000/33000 broker ranges are never claimed, and a port found in use by someone without a claim goes into `.git_ignored_dir/port-registry/reserved.txt`.
- Applies at: Before starting
- Case (2026-09-20): `port-claim` handed out 1702 to an agent while another session's master on that port happened to be down; a stopped master frees the port but not the intent, and people running servers by hand write no claim lines — `reserved.txt` was added and 1700–1703 reserved.
- Source: CUBRID_SSOT.md §3.17, docs/agents/port-registry.md

### P2 — the conf before the start
- Rule: Before a start, read the install's `conf/cubrid.conf`: `data_buffer_size=512M` on every server any session starts on this host (a 70 GiB host; two full gates at 16 × ~1 GB per lane ran it out), the claimed `cubrid_port_id`, and — when the run needs engine defaults — a conf holding only `cubrid_port_id`, because the campaign conf that `just conf` and `port-claim` write has `double_write_buffer_size=0` and `parallelism=24`.
- Applies at: Before starting
- Case (2026-10-19, CBRD-27583): the host had 60.1 GiB of 70.4 GiB used by processes, mostly two lanes' full gate shards; the user set 512M for every server, no overlapping targeted and full CTP, and no smoke server during a gate.
- Case (2026-09-28, #348 triage): every campaign CTP server had run with the DWB off since 2026-09-16; the redo-assert observations came only from such servers.
- Source: memory:data-buffer-512m-all-servers, memory:campaign-conf-disables-dwb

### P3 — the master respawns a killed server
- Rule: After `kill -9` of a hung `cub_server`, the still-running `cub_master` relaunches it within seconds (and a server that dies again within 120 s of its last relaunch stays down), so stop the server through the wrapper — or stop that install's master — before changing the conf (edit the session conf and re-apply it with `just conf`), start fresh, and once it is up confirm the parameters with `cubrid paramdump -C <db>` (hidden parameters such as `test_mode` and `parallel_sort_page_threshold` never appear there); in a crash loop, poll for the relaunch and start the server yourself when none comes.
- Applies at: Stopping and restarting
- Case (2026-09-24, #350): after both kills the master relaunched `cub_server <db>` before the conf edit was applied, so the relaunched server ran the old parallelism. 2026-09-28 (#363): the `to_char` crash run twice within 2 minutes left the server down until a manual start (`SERVER_MONITOR_UNACCEPTABLE_REVIVE_TIMEDIFF_IN_SECS = 120`).
- Source: memory:cub-master-respawns-killed-server, CUBRID_SSOT.md §3.6

### P4 — `server stop` leaves the master; stop it by pid
- Rule: `cubrid server stop <db>` does not stop `cub_master`; a stray master keeps the claimed port (a listener with no `cub_server`) and a rebuilt binary then fails to bind, so stop that master by its exact pid with SIGTERM — the one whose `/proc/<pid>/exe` (or `CUBRID=` in `/proc/<pid>/environ`) is under the install — never `pkill cub` or `cubrid service stop` on this shared host, and always `server stop` (confirmed by process absence) before any master stop, so an in-flight stop is not lost and no `cub_server` is orphaned; an orphan is ended with SIGTERM, not `kill -9`.
- Applies at: Stopping and restarting
- Case (SSOT §3.5, §3.14): stopping the master first lost a pending server stop and left `cub_server` orphaned; `cubrid master stop` does not exist in archive builds ("utility-name is invalid").
- Case (2026-08-28): CTP's host-side teardown ran `pkill cub` and killed every cub_* of the user on every port — the reason CTP runs only in containers and nothing on this host broadens a stop to a pattern.
- Source: CUBRID_SSOT.md §3.5, §3.14, memory:host-repro-on-gha-archive-builds, docs/agents/port-registry.md

### P5 — `CUBRID_TMP` must match and be short
- Rule: A control command finds the master's unix socket under `$CUBRID_TMP` (the master puts its socket at a path derived from the environment that started **it**; on this host a shared master uses `$HOME/CUBRID/var/CUBRID_SOCK`), so "Could not connect to master server" while `ps` shows a live `cub_server` and `ss -tlnp` shows the master on the port is an environment mismatch, not a hang: read the master's value with `tr '\0' '\n' < /proc/<pid>/environ | grep CUBRID_TMP`, export the same one, and keep it short — the socket path `$CUBRID_TMP/cubrid_tcp_setup_server<pid>` must fit in 107 bytes (an 83-character scratch path failed with `-359 Datagram bind error … Invalid argument`; 69 worked).
- Applies at: Stopping and restarting
- Case (2026-08-14, SSOT): a stop issued from a shell with another `CUBRID_TMP` failed to connect; 2026-10-07 (#386): an extracted gha archive under a long scratch path would not start until `CUBRID_TMP` was shortened.
- Source: CUBRID_SSOT.md §3.14, memory:host-repro-on-gha-archive-builds, docs/agents/port-registry.md

### P6 — parameters are server-side
- Rule: A parameter or environment variable set only for the csql client changes nothing in the server; pass it to the server's start (the wrapper inherits the caller's `CUBRID_*` environment and `$CUBRID/conf/cubrid.conf`), and read it back with `cubrid paramdump -C <db>`.
- Applies at: Before starting
- Case (SSOT §3.7): a feature env exported in the csql shell was taken as "enabled" while the server ran without it.
- Source: CUBRID_SSOT.md §3.7

### P7 — no interactive utility without stdin
- Rule: An interactive CUBRID utility never runs in automation without its answers supplied (a flag or explicit stdin), because an EOF-looping prompt grows the log until the disk is full; automation logs get a size cap and a free-space check, and bounded evidence (statdump counters, file-size deltas) is preferred over full dumps.
- Applies at: Before starting
- Case (SSOT §3.10): a prompt re-asked on EOF filled the disk with repeated prompt lines.
- Source: CUBRID_SSOT.md §3.10

### P8 — leave the host as found
- Rule: When the effort ends, stop its servers through the wrapper, stop its master by pid (P4), `just port-release` the claim, and restore any install conf a smoke rewrote; servers left running are not fine, short SA jobs are.
- Applies at: Stopping and restarting
- Case (SSOT §3.9, §6): a tree left dirty and daemons left running were the first thing the next session tripped on; a leftover `xasl_debug_dump=yes` in an install conf pollutes the next CTP or smoke.
- Source: CUBRID_SSOT.md §3.9, memory:server-stack-at-error-without-gdb
