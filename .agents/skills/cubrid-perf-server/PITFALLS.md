# PITFALLS — the rules in SKILL.md and the incidents that produced them

Each `P<n>` is one rule. The **Rule** line is the exact sentence SKILL.md carries at the step named in
**Applies at**; keep the two byte-identical. **Case** is the incident that paid for the rule. **Source**
is where the lesson came from.

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule only when no rule fits — then add the sentence to SKILL.md in the same commit.

### P1 — a backgrounded `&&` chain holds the ssh pipe
- Rule: Detached work on a node is a simple command with its own redirection, never a backgrounded `&&` chain (P1).
- Applies at: Steps 3 (Run)
- Case (2026-11-06, SF10 load): `ssh node "cd X && setsid nohup bash load.sh > log 2>&1 < /dev/null & sleep 20; …"` never returned: the `&` backgrounds the whole `cd && setsid …` list as a subshell that keeps the ssh stdout open until the load ends. The loop over both nodes stalled on node0, and node1's load started ~2 minutes late.
- Source: this session

### P2 — `/proc/loadavg` in the container is the host's
- Rule: A node is free when no line of its `schedule.txt` overlaps [now, end] — a `송일한` line of another session counts as occupied — and no process outside root, dbus and ssh/bash runs in the container (P2).
- Applies at: Steps 1 (Reserve first)
- Case (2026-11-06, skill design): both nodes reported the identical load average `0.27 0.62 1.61` and 761 tasks; a load gate would call node0 busy while someone benchmarks on node1. The container's own process list is the signal.
- Source: this session

### P3 — `cubrid server start` over an ssh pipe hangs
- Rule: Server start/stop go inside the command with their output redirected to a file — `cubrid server start` holding the ssh pipe hangs the call (P3).
- Applies at: Steps 3 (Run)
- Case (2026-11-06): the same daemon-inherits-the-pipe hang the `cubrid-server-control` wrapper exists for; `exec` sends the command's output to a file on the node and streams it with `tail --pid`, so the daemons hold a file, not the pipe.
- Source: cubrid-server-control "The one rule"

### P4 — 16 GiB cgroup, not the QAHome machine
- Rule: `push` writes it: QAHome values with `data_buffer_size=12G` instead of 15G, because the containers are capped at 16 GiB (P4).
- Applies at: Standard conf
- Case (2026-11-06, user decision): QAHome runs `data_buffer_size=15G`; the containers' `memory.max` is 17179869184, leaving ~1 GiB for the server's threads, sort buffers and eight concurrent loaddb clients — an OOM kill during the load. The user approved 12G and kept `parallelism=32` for plan parity with QA.
- Source: this session

### P5 — the exec group holds `cub_master`
- Rule: The run's servers stop first, through `cubrid server stop` while their `cub_master` still runs, then the exec process groups, then every process whose exe lies under the run dir (P5).
- Applies at: Steps 4 (Release) and the watchdog's cleanup
- Case (2026-11-06, TPC-H 99fa309 vs develop): killing the exec's process group to restart a pass also killed `cub_master` (it does not leave the group), so `cubrid server stop` answered "Could not connect to master server" and the server on the shared SF10 DB was left to a signal; `timeout` puts `csql` in its own group, so the csql survived the group kill too. SIGTERM ended the server in 3 s; cleanup.sh now stops servers first and falls back to SIGTERM, and the exe-path kill catches what `timeout` moved out of the group.
- Source: this session
