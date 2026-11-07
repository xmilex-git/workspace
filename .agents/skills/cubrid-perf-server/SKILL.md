---
name: cubrid-perf-server
description: "Measure CUBRID performance on the team's two dedicated perf servers (perf-node0/1, 8 cores and 16 GiB each, 12:00-22:00 KST) through one script: reserve a free node in its schedule.txt, push a local install, run the benchmark, pull the results, and leave the node as it was. Use whenever a wall-time, throughput or latency number decides something (A/B of a fix, a regression check, TPC-H timing), when the user says '성능 테스트', '성능 서버', '벤치 돌려', 'wall time 재', 'TPC-H 시간 재', or when this host is too loaded to time anything."
argument-hint: "<status|reserve|push|conf|exec|pull|release> ..."
---

# CUBRID perf servers

The development host is shared by many sessions and too loaded for wall time; its speed judgments stay on
`perf stat -e instructions:u`. Every wall-time, throughput or latency number that decides something is
measured here instead.

## Terms

See `GLOSSARY.md` → "성능 서버": **성능 서버**, **예약**, **빈 성능 서버**, **예약 연장**, **공용 SF10 DB**.

- **run**: one reservation and everything it put on the node, all under `/home/cubrid/perf-runs/<run-id>/`
  (installs, run DBs, outputs, `cleanup.sh`, `watchdog.sh`). Its local evidence lives in
  `/home/cubrid/perf-run-out/<run-id>/`.

## The servers

| node | address | cpuset | memory |
|---|---|---|---|
| `perf-node0` | `cubrid@192.168.1.248` | 0-7 (NUMA 0) | 16 GiB cgroup |
| `perf-node1` | `cubrid@192.168.1.249` | 8-15 (NUMA 1) | 16 GiB cgroup |

Both are podman containers on one Xeon Silver 4110 host and share the disk `/dev/sda5`. They run 12:00-22:00
KST and are stopped outside that window; `/home` survives the restart. Login is by this host's SSH key
(installed 2026-11-06); the password is never written down. Rocky 8.10 matches this host, so a release install
built here runs there as is (the RPATH points at the local prefix, `exec` sets `LD_LIBRARY_PATH`).

## Steps

All commands are `S=.agents/skills/cubrid-perf-server/scripts/perfsrv.sh`, run from the tooling repo.

1. **Reserve first.** `$S status` shows both schedules and any foreign processes; `$S reserve <minutes> [node]`
   takes the first free node (248 before 249) and prints `RUN=<run-id> NODE=<ip>`. Reading `schedule.txt` and
   the process list is the only thing done on a node without a reservation; `push`, `conf` and `exec` refuse
   unless this run's line is in `schedule.txt` and its end has not passed.
   - Minutes = the planned measurement time plus margin; the end is capped at 21:55 so servers stop cleanly
     before the 22:00 shutdown, and a run that would end after 21:50 is not started.
   - A node is free when no line of its `schedule.txt` overlaps [now, end] — a `송일한` line of another session counts as occupied — and no process outside root, dbus and ssh/bash runs in the container (P2).
   - Both busy: stop and tell the user, in Korean, the earliest free time from `status`; ask before waiting.
2. **Push each install to compare.** `$S push <run> <install>` sends it to `install-<sha12>/`, checks the
   libcubrid sha256 on the node and writes the standard conf; it prints `SHA=<sha12>`.
3. **Run.** `$S exec <run> <sha12> '<command>'` runs the command on the node with `CUBRID` = that install,
   `CUBRID_DATABASES` = the run's own `databases/` (which also lists the shared SF10 DB), `OUT` = the run's
   `out/` as cwd, and streams its output into the local `exec.log`.
   Server start/stop go inside the command with their output redirected to a file — `cubrid server start` holding the ssh pipe hangs the call (P3).
   Detached work on a node is a simple command with its own redirection, never a backgrounded `&&` chain (P1).
4. **Release.** `$S release <run>` pulls `out/`, stops the watchdog, sets the line's end to now, stops every
   process of the run, deletes the run dir with a literal `rm -rf`, and prints `CLEANUP OK` only
   when `ls -1A ~` equals the listing taken before the reservation and no run process is left. A
   `CLEANUP DIFF` is reported and fixed before the task closes.
   The run's servers stop first, through `cubrid server stop` while their `cub_master` still runs, then the exec process groups, then every process whose exe lies under the run dir (P5).

Completion: `RELEASED` printed, `CLEANUP OK`, and the run's results in `/home/cubrid/perf-run-out/<run-id>/`.

## The end time is enforced on the node

`reserve` starts `watchdog.sh` on the node (it survives this session). Ten minutes before the end, while the
run is busy (a command group or a process of its installs alive), it extends the line by one hour, up to the
next foreign reservation's start and 21:55; otherwise the run ends at the end time: the watchdog runs the same
`cleanup.sh` (stops everything, deletes the run dir). Output already streamed into the local `exec.log` stays;
anything only in the remote `out/` is gone, so pull after each measurement.

## Standard conf

`push` writes it: QAHome values with `data_buffer_size=12G` instead of 15G, because the containers are capped at 16 GiB (P4).
`$S conf <run> <sha12> dwb-on|dwb-off` rewrites it. A measurement that needs other values edits `$CUBRID/conf/cubrid.conf` inside its
`exec` command and says so in the report.

```
[service]  service=server
[common]   data_buffer_size=12G  log_buffer_size=256M  sort_buffer_size=8M  parallelism=32
           max_parallel_workers=100  error_log_size=2000000000  max_clients=100  cubrid_port_id=1523
           log_max_archives=0  stored_procedure=no   (double write buffer on)
```

A run DB uses the QAHome volume layout: data 10G ×4 (`createdb --db-volume-size=10G` + `addvoldb -S -p data`
×3), temp 5G ×1, page 16K, log 512M. The DWB is on for `createdb`/`addvoldb`, off for the load (schema, data,
index, statistics), and on again before any measurement.

## Shared SF10 DB

`/home/cubrid/databases/tpch_sf10` on both nodes (loaded 2026-11-06 with develop `dcbab24d0` release, rows
checked against TPC-H SF10; ~8 minutes per node) is the one thing a release leaves behind. Measurements only
read it; a workload that writes copies it into the run first (`cubrid copydb` into the run's `databases/`).
When a build cannot open it (a disk format change), reloading means deleting a shared DB: ask the user, then
`$S exec <run> <sha12> "$(cat scripts/load-sf10.sh)"` after `cubrid deletedb tpch_sf10` with
`CUBRID_DATABASES=/home/cubrid/databases`.

## Measuring

- Per-query timing (TPC-H and the like) restarts the server before each query, then times one cold and one warm run of it and reports both (P7).
- A and B run on the same node in the same reservation, interleaved (A B A B …), never A on one node and B on
  the other: the NUMA nodes differ and the disk is shared.
- A and B read the same DB files; a build that cannot open the shared SF10 DB is compared only against builds run on a DB loaded in the same run, never against the shared DB (P8).
- Profiling: `perf_event_paranoid` is -1 in the containers and release installs carry debug_info, so `perf record -p <cub_server pid>` resolves engine symbols without sudo; `SET TRACE ON` + `SHOW TRACE` beside it separates a plan change (fetch counts differ) from buffer residency (same fetches, different ioread).
- `perf record` on a node runs with `--no-buildid-cache`, and `perf report` reads the data inside the run dir before release (P6).
- The report names the node, run-id, both fingerprints, the conf if not standard, every repetition with
  median and spread, and whether the other node had a reservation during the run (shared-disk interference).
