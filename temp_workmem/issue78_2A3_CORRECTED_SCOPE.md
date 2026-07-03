# 2A-3 CORRECTED SCOPE — bug2 real cause & next-session plan (2026-07-01)

Authoritative record: GitHub #78 comment `4850257401` + evidence `issue65_evidence.md` entry (q).
Tree: `wm-integ-7173-develop` HEAD `017afa968` (slice-1 death-code only), src CLEAN, release rebuilt clean.

## What landed this session
- **slice-1** (`017afa968`, pushed): removed vestigial raw-fd sector-scan registry (dead map + accessors) from px_hash_join. Behavior-neutral, verified (serial 200360), governed.

## The correction (plan premise was WRONG)
Plan/evidence(o) said "bug2 = parallel PHJ partition write race; fix = per-worker tape (ADR0004, remove part_mutexes)". **Falsified by measurement:**
- bug2 query (`o_orderkey<200000`=200360) does **NOT partition** — it takes `HASHJOIN_STATUS_PARALLEL_PROBE` (single hash table + parallel probe). gdb: `build_partitions` not the correctness path.
- Row loss is in the **INPUT READ**: parallel probe reads probe input via `qfile_open_list_sector_scan`/`sector_page_iterator` (px_hash_join.cpp:611) which **loses rows on arbitrary derived lists** (identical to buggy1/2A-2c, a #7173 sector-machinery defect). Parallel split reads its input the same way.
- Proof: serial=correct (200360/2000495); parallel(8)=lossy (149510/149574); **env-OFF gives the SAME wrong values** → pre-existing, independent of any gate. `part_mutexes` write is mutex-serialized → NOT the loss source.
- A per-worker-output-tape migration was implemented, found buggy (own race: varying 209198/837199 on `<2000000`) AND orthogonal to bug2 → **reverted**.
- `CUBRID_WM_SCAN_NEW=1 CUBRID_WM_SORT_NEW=1` + parallel PHJ → **server crash + `ERROR: Invalid XASL tree node content`** → PHJ is not NEW-input-aware.

## The REAL 2A-3 fix (next focused session)
Goal: parallel PHJ (probe + partition-split) must not lossy-read its input. Redesign-aligned (mirrors 2A-2f "OLD arbitrary list → not parallel; NEW → chunk_distributor").

Two coupled sub-problems:
1. **Make parallel PHJ input read safe.** Replace `sector_page_iterator` input distribution with `chunk_distributor`+`tapeset_reader` over a **NEW-backed** input, in BOTH:
   - parallel probe: `parallel_query::hash_join::probe_execute` input scan (px_hash_join.cpp:611) + `probe_task` page iteration (px_hash_join_task_manager.cpp).
   - parallel split: `split_task::execute` `m_page_iter.get_next_page(sector_scan)`.
   Requires the PHJ input list to be NEW-backed. Determine whether SCAN_NEW makes the join input NEW, or whether 2A-3 must materialize/convert the input to NEW before the parallel read.
2. **Fix the `Invalid XASL tree node content` crash** on SCAN_NEW+SORT_NEW+parallel PHJ. Lead: `ER_QPROC_INVALID_XASLNODE` — most probable origin in the parallel worker XASL clone path (`src/xasl/xasl_spawner.cpp` :95/:160/:352/:668) or `px_scan_task.cpp` :536/:555; needs a **debug build + core/gdb stack trace** to pinpoint (RelWithDebInfo silent SIGSEGV → `gdb -p <pid> -batch` or debug build). Confirm whether it is pre-existing (SCAN_NEW×PHJ, prior slices) vs introduced.

Then (perf/ADR0004, separate slice): per-worker OUTPUT tapes to remove `part_mutexes`+append-copy on the migrated partition path — re-implement WITHOUT the race the first attempt had (root-cause the varying 209198/837199 first).

## Correctness-vs-perf note (EXIT gate tension)
- Minimal correctness fix = force parallel PHJ → serial when input not safely parallel-readable. Fixes bug2 (deterministic 200360) + #77, but fails `PHJ median ≤ develop×1.10` (serial). NOT committed this session (would be a perf-regressing band-aid the plan didn't request).
- Both EXIT requirements (deterministic 200360 AND ≤develop×1.10) need sub-problem 1 (NEW-input chunk_distributor parallel read) complete.

## Verification protocol reminders (measured this session)
- PHJ parallel loss is **session-state dependent**: cold separate `csql -c` runs can show 200360; a batched `csql -i` session shows 149510 deterministically. MUST test both (batched + many runs).
- Server env decides WM gates (getenv at `cubrid server start`); csql client env is ignored. Use env-isolated `env -i PATH=$RED/bin:/usr/bin:/bin CUBRID=$RED CUBRID_DATABASES=/home/cubrid/databases`.
- golden: HASHJOIN(o_orderkey<200000) count=200360; serial <2000000 count=2000495.
