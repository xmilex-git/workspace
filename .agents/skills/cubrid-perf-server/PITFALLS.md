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

### P6 — `perf record` writes a build-id cache into `~`
- Rule: `perf record` on a node runs with `--no-buildid-cache`, and `perf report` reads the data inside the run dir before release (P6).
- Applies at: Measuring
- Case (2026-11-06, q18-q21 analysis): eight `perf record -p` runs left `/home/cubrid/.debug` (1.3 GiB of build-id and kallsyms copies) outside the run dir; release printed `CLEANUP DIFF` with `> .debug` and the directory was deleted by hand.
- Source: this session

### P7 — a sequential pass times the previous query's footprint
- Rule: Per-query timing (TPC-H and the like) restarts the server before each query, then times one cold and one warm run of it and reports both (P7).
- Applies at: Measuring
- Case (2026-11-06, 99fa309 vs develop): one warm-up pass then one measured pass of q1-q22 on one server showed q19-q21 20-70% faster on develop, but their plans and fetch counts were identical; only ioread differed, because the old q18 plan read 847K pages and evicted what q19-q21 reuse (19.3 GB data, 12 GB buffer). The user set the per-query restart, cold then warm, on 2026-11-07.
- Source: user decision 2026-11-07

### P8 — two loads of the same SF10 DB are not the same disk workload
- Rule: A and B read the same DB files; a build that cannot open the shared SF10 DB is compared only against builds run on a DB loaded in the same run, never against the shared DB (P8).
- Applies at: Measuring
- Case (2026-11-07, TPC-H 4adcd4090 vs develop): 4adcd4090 cannot open the shared DB (catalog change 5a3e7a14b), so it ran on a DB loaded in the run and q21 showed +8.5% on develop. The same develop build then ran q21 at 18.2 s on the shared DB and 15.7 s on a fresh load with the same script (median of 15). Heap statistics, fetch and ioread were identical and evicting the page cache kept the gap; the fresh load needed ~5% fewer disk read requests for the same 12.2 GB at the same time per request (sda is an AVAGO SMC3108 MegaRAID virtual disk; its rotational=1 does not tell the media). Page placement from the eight parallel loaders differs per load.
- Source: this session

### P9 — an SA-mode process holds the whole buffer pool
- Rule: An SA-mode utility (`loaddb -S`, `csql -S`) allocates `data_buffer_size` (12G) in its own process, so a container runs one at a time and never beside a running server (P9).
- Applies at: Standard conf
- Case (2026-11-07, SA reload of the shared DB): two SA loads ran at once on perf-node0 (the shared `tpch_sf10` and the run's `tpch_e0`); the memory cgroup killed the `cub_admin` of the shared load at lineitem row 35.4M (anon-rss 8.4 GB, `FINISH rc=254`) and left the shared DB half loaded. The same load alone on perf-node1 finished. The node0 DB was deleted and reloaded alone.
- Source: this session

### P10 — `deletedb` leaves the old archive logs
- Rule: `deletedb` leaves the old archive logs (`tpch_sf10_lgar*`) in the DB directory, so they are removed by literal `rm` before the `rmdir` (P10).
- Applies at: Shared SF10 DB
- Case (2026-11-27, reload for develop 9dd488a1b): develop `9dd488a1b` refused the 11-07 DB ("Database is incompatible"); `cubrid deletedb tpch_sf10` returned 0 but left `tpch_sf10_lgar037`..`040` (2 GiB) on both nodes, so the `rmdir` failed and `load-sf10.sh` stopped at `test ! -e`. The four files were removed by literal `rm` and the load restarted.
- Source: this session

### P11 — two loads in CS mode are two different heaps
- Rule: Two DBs that stand for one (a disk format change between A and B) take their heaps from a one-thread `loaddb -S` and are compared by `;info stats` of every table before anything is measured: a CS-mode load always has two or more workers (`loaddb_worker_count`) and its page counts differ from load to load (P11).
- Applies at: Measuring
- Case (2026-11-28, JOB 113 queries, cbed1d5 vs 435b0b7 vs PR 8808): the disk compatibility level changed between the two builds (11.5 to 11.51), so each side had its own DB, both loaded with `loaddb -C`. cast_info came out at 149,498 and 149,502 heap pages, 57 of the 113 plans differed between the two DBs (0 between the two builds that shared one), and the ratios of 24a, 27c, 21c, 33c followed the plans, not the builds. Reloaded with the heap by `loaddb -S` (two loads side by side, `data_buffer_size=5G` each for the load) and the keys and indexes by `loaddb -C -i ... --no-logging-index`: 0 of 580 `;info stats` lines differ, and the 113 plans are the same on three builds.
- Source: user correction 2026-11-28 ("그게 플랜보다는 no logging index나 힙 차이일걸")

### P12 — a warm pass on a buffer smaller than the data still reads the disk
- Rule: A warm number is reported only when the query's trace shows `ioread: 0` on every node; data larger than the 12G buffer is measured with `data_buffer_size=13G`, which the 16 GiB container holds (P12).
- Applies at: Measuring
- Case (2026-11-28, JOB on perf-node0): the JOB data is 12.3G and the standard buffer 12G. After a discarded execution and three timed ones, the trace of 14 of the 113 queries still read pages (8c 100,273, 12c 162,483, 19d 21,054); 12a took 0.33 s where QA's 15G run takes 0.23 s. With 13G and a server restart per query every trace showed `ioread: 0`, 12a took 0.22 s, and 12c moved from +5.1% to -4.5% against the old build.
- Case (2026-11-28, the same run, all 113 queries in one server pass at 13G): the traces of 14 queries still showed `ioread` above 0 (the same 14 as at 12G: 7c 8c 8d 9d 12a 12c 13a 13d 15c 15d 18b 18c 19d 26b; 310,793 to 367,498 reads a pass), on every build alike. A server started for 13 queries (13a and 19d among them) showed 0 on all. The earlier queries' pages and the temporary files of a long pass fill the buffer, so a query whose trace is not 0 is timed again in a pass of its own.
- Source: user question 2026-11-28 ("warm으로 잰거맞아??")

### P13 — a CI build and a local build are two compilers
- Rule: A and B are built by one compiler: a CI archive build (GCC 8.3.1) and a local `just build release` (GCC 8.5.0) of the same source differ by up to 6% a query, so a build made on this host is compared only with builds made on this host, and the `GCC: ` line of both libraries (`strings lib/libcubrid.so.11.5`) goes into the report (P13).
- Applies at: Measuring
- Case (2026-11-28, JOB on perf-node0, PR 8808): the head of the PR as the CI built it (GCC 8.3.1, `c25afac126a1`) and as `just build release` built it here (GCC 8.5.0, `82b2da344887`) ran 13 queries three rounds side by side, 13G, `ioread: 0`: the local build was 0.9% to 5.8% faster (19d 5.22 s against 4.92 s, 13a 2.89 against 2.80), 4.25% in the sum. Against the CI build of the commit before the regression 19d was +7.8% as a CI build and +1.6% as a local build; against that commit built here (`29b6a7892769`) it was -1.1%. Three of the 14 queries that looked more than 5% slower were not slower at all between builds of one compiler.
- Source: this session
