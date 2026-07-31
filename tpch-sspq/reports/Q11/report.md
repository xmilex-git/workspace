# TPCH-SSPQ FK campaign — Q11 report

## 3-a. Causal multiplier card

```text
R_wall 1.681443x [wall, median of 3 per engine; PostgreSQL is 1.6814x faster]
= F_plan  1.001493x [GROUP BY execution strategy; CUBRID-side controlled A/B — a NULL result]
× F_units 1.235944x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   1.358424x [total query CPU-seconds]

F_cpu on the native pair is 1.358179x and it decomposes on the event Q11 is
actually bound by — data-page fixes:

F_cpu(native) 1.358179x [total query CPU-seconds]
= F_work 1.496357x [data-page fixes: 1,011,949 vs 676,275]
× F_cost 0.907657x [total-query CPU-seconds per page fix: 1339.0 ns vs 1475.2 ns]
```

**Read the card in one line: CUBRID's plan is the better plan, its per-page-fix cost is
lower than PostgreSQL's, its IPC is higher — and it still loses 1.68x because it asks its
buffer manager for 1.50x as many pages and runs the whole query on one thread.**
`F_cost` is **below 1.0**: CUBRID spends 1339.0 ns of total query CPU per page fix against
PostgreSQL's 1475.2 ns. Q11's CPU factor is a *count* factor, not a unit-cost factor.

**But the headline number is not the finding.** The finding is that before it could be
measured at all, CUBRID's Q11 had to be driven through a **2.6408x** performance decay that
no parameter, plan or query change causes and that the SSOT §12 WARM gate cannot see:

| | first connection | saturated |
|---|---|---|
| block median wall | **3.544000 s** | **1.342000 s** |
| trace `ioread` per statement | **566,103** | **0** |
| `/proc/<cub_server>/io` read syscalls per statement | 551,116 | 96 |
| page-cache bytes copied per statement | 8.406 GiB | ~0 |
| trace `fetch` (page FIXES) per statement | 1,012,042 | **1,011,949** |
| trace `fetch_time` | 2,061 ms | 326 ms |
| traced statement time | 3,360 ms | 1,532 ms |
| device `read_bytes` delta | 0 | 0 |
| PostgreSQL, same interval | `shared hit=676275 read=0`, 1079.898 ms | `shared hit=676275 read=0`, **1080.016 ms** |

The plan is identical, the query text is identical, every parameter is identical, and the
**page-fix count is identical to 0.01%**. The only thing that changed is how many of those
fixes missed. 94.9% of the 1,828 ms recovered is accounted for by the trace's own
`fetch_time` (2,061 → 326 ms). PostgreSQL's number moved by **0.01%** over the same 22
minutes and ~370 statements. That is `IMP-018`, and it is the largest single measured effect
of this campaign so far.

The mechanism is not inferred from a profile band. It is a **connection-driven** migration,
which the probe below isolates by holding the statement count per connection at the SSOT §12
block size and varying only the number of connections:

| new connection # | block median | reads/statement | `Num_data_page_private_count` | `Num_data_page_lru3` |
|---|---|---|---|---|
| 1 | 1.5810 s | 49,292 | 5,002 | 441,130 |
| 2 | 1.5400 s | 34,538 | 5,002 | 437,186 |
| 3 | 1.4360 s | 18,306 | 5,002 | 433,305 |
| 4 | 1.3530 s | 3,519 | 5,001 | 429,534 |
| 5 | 1.3520 s | **135** | 1,580 | 426,217 |
| 6…60 | 1.318–1.370 s | 111–127 | 1,638 | 426,613 |

`Num_data_page_private_count` sits at **5,002** — i.e. at
`PGBUF_PRIVATE_LRU_MAX_HARD_QUOTA = 5000` (`page_buffer.c:1024`) — for exactly as long as
the misses persist, and drops to 1,638 the moment they stop, while the shared hot zone
`Num_data_page_lru1` rises 15,092 → 82,352 → **97,369**, which is Q11's whole working set.
A single session can retain **5,000 of 524,288 pages (0.95%)** of an 8,192 MB pool.

And the same probe run the other way proves the driver is the *connection*, not the
statement: **one** connection executing **120** statements is flat at 2.450–2.521 s with
syscr stable at 193k–210k (half-split trend −0.16%), and **one** connection executing **60**
statements immediately after the 60-connection sweep is flat at **1.3300 s median, 2.28%
spread, 96 reads/statement**.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 1.001493x | GROUP BY execution strategy (runtime-abandoned hash → sort, vs sort from the start) | same-engine controlled A/B on CUBRID | `T_C_native/T_C_nohashagg` = 1.342000/1.340000 | `Q11-cubrid-headline-block3.json`, `Q11-cubrid-nohashagg-headline.json`, `q11-trace-cubrid-saturated.out`, `variants/trace-cubrid-NO_HASH_AGGREGATE.out` | direct A/B (**null result**) |
| `F_units` | 1.235944x | active execution units | CPU-seconds / wall-second over the §12 block | `U_P_native/U_C_nohashagg` = 1.24996/1.01134 | `Q11-postgresql-headline-telemetry-run7.json`, `Q11-cubrid-nohashagg-headline-telemetry.json` | profile attribution |
| `F_cpu` | 1.358424x | total query CPU-seconds | per query execution | `CPU_C_nohashagg/CPU_P_native` = 1.3552/0.9976 | same telemetry JSONs | profile attribution |
| `F_work` | 1.496357x | data-page fixes | pages requested from the buffer manager | `W_C/W_P` = 1,011,949/676,275 | `q11-trace-cubrid-saturated.out` (`fetch`), `q11-plan-act-pg-saturated.out` (`shared hit`) | direct A/B |
| `F_cost` | 0.907657x | CPU-seconds per page fix | page fixes | `(CPU_C/W_C)/(CPU_P/W_P)` = 1339.0 ns / 1475.2 ns | `Q11-causal-card.json`, `q11-card-calc.txt` | profile attribution |

### Three anchors, all reconstructing exactly

Q11 admits three controlled A/Bs, and all three are reported because each isolates a
different factor and they disagree in sign — which is the point.

```text
anchor A  PostgreSQL-side, AGGREGATION STRATEGY
1.681443x = 0.927064x [plan] × 1.182925x [units] × 1.533258x [CPU-sec]

anchor B  CUBRID-side, GROUP BY EXECUTION STRATEGY  (primary; a null result)
1.681443x = 1.001493x [plan] × 1.235944x [units] × 1.358424x [CPU-sec]

anchor C  PostgreSQL-side, REMOVING ITS ONLY PARALLEL UNIT
1.681443x = 1.091149x [plan] × 0.978200x [units] × 1.575326x [CPU-sec]
```

**Anchor A** is `PostgreSQL native (HashAggregate, 16 planned partitions, 17 batches,
Memory Usage 8337 kB, Disk Usage 15064 kB) → PostgreSQL controlled `enable_hashagg=off`
(GroupAggregate over an external-merge Sort — CUBRID's shape)`. Its `F_plan` is
**0.927064x, below 1.0**: forcing PostgreSQL onto CUBRID's sort-based aggregation makes
PostgreSQL **1.0787x faster** (0.798124 s → 0.739912 s). PostgreSQL's own cost model picks
the worse of the two strategies here and CUBRID picks the better one. Limitation stated up
front: the two orders differ in one tie (§2), and switching PostgreSQL's aggregation also
changes its top-level input ordering, so anchor A is an aggregation-strategy factor and not
a pure hash-vs-sort-cost factor.

**Anchor B** is `CUBRID native (plan-time hash-eligible → runtime `HS_REJECT_ALL` → fallback
sort) → CUBRID controlled `/*+ NO_HASH_AGGREGATE */` (`HS_NONE` → sort from the start)`. It
is the anchor Q10 used to recover 1.313675x, and on Q11 it recovers **nothing**:
1.342000 s → 1.340000 s, `F_plan = 1.001493x`, inside the 1.28% CUBRID block band. The
variant's estimated plan tree is identical (cost `9752` on both sides), its page-fix count is
identical (`fetch: 1011949` on both), its result rows are identical (34,740 extracted rows,
same SHA-256), and its trace differs in exactly one token —
`GROUPBY (time: 313, hash: partial, …)` → `GROUPBY (time: 309, hash: false, …)` — with **no**
`(parallel workers: …)` sub-line in either case. Q11's group-by sorts 323,920 rows through
**1,516** sort pages against Q10's **75,893**, so with `sort_check_parallelism()`'s veto
removed `compute_parallel_degree` still returns 1. This is a measured negative control for
both IMP-015 and IMP-016, and it is chosen as the *primary* anchor precisely because it is
null: it means Q11's `F_units` and `F_cpu` are not contaminated by a plan difference.

**Anchor C** is `PostgreSQL native (InitPlan `Gather`, Workers Planned 1, Launched 1) →
PostgreSQL controlled `max_parallel_workers_per_gather=0``. `F_plan = 1.091149x`:
PostgreSQL's single worker — its **only** parallel unit on this query — is worth 9.11%
(0.798124 s → 0.870872 s) and its `U` falls 1.24996 → **0.98764**. On the resulting
serial-vs-serial pair CUBRID loses **1.540984x** instead of 1.681443x, and its CPU factor
rises to `F_cpu = 1.575326x`. That is the honest statement of Q11's CPU gap: **at equal
(serial) units CUBRID spends 1.5753x PostgreSQL's total query CPU.**

**Reconstruction residual = +0.000000% on all three anchors, and as in Q04–Q10 that is an
identity, not a prediction.** `CPU_stmt` is attributed as `U × t_median` with `U` measured on
the same block regime the wall is defined on, so `F_units × F_cpu = T_C/T_P` by construction.
Closure rests on the independent quantities:

- **`U` reproducibility over three independently gated saturated telemetry runs**: CUBRID
  1.01304 / 1.00864 / 1.00965 (**0.44%** max−min); PostgreSQL 1.24996 / 1.25933 / 1.23889
  (**1.65%**).
- **TWU**, from actual sample timestamp deltas over the busy window only: **0.9975**
  (CUBRID, −1.20% from `U`), **1.2293** (PostgreSQL, −1.65%), **0.9928** (CUBRID
  `NO_HASH_AGGREGATE`, −1.83%), **1.1716** (PostgreSQL `enable_hashagg=off`, −1.90%),
  **0.9916** (PostgreSQL serial, +0.40%). Every configuration's independent unit estimate
  agrees with its `U` to under 1.9%.
- **`perf stat` on verified PID sets**, a third instrument: **0.998 CPUs utilized** for
  CUBRID (`U` = 1.00965, **−1.2%**) and **1.329** for PostgreSQL's postmaster-inherited
  leader+worker set (`U` = 1.24996, **+6.3%**).
- **The engines' own node accounting**, a fourth and fully independent route. CUBRID's
  saturated trace sums to 593 + 619 + 313 + 7 = 1,532 ms = the traced `SELECT (time: 1532)`
  exactly, with no node reporting a parallel worker — so `U ≈ 1` is forced by the trace, not
  assumed. PostgreSQL's `EXPLAIN ANALYZE` puts 237 ms of its 1,080 ms into a 2-unit
  `Gather`, i.e. `U ≈ 1 + 237/1080 = 1.219`, against the measured 1.24996 (**−2.5%**).
- **Instructions and IPC**, a separate counter path: CUBRID **141.849 G instructions at
  IPC 1.65**, PostgreSQL **159.126 G at IPC 1.39** over their respective 30.002 s windows;
  normalised per statement that is **6.345 G vs 4.233 G**, i.e. CUBRID retires **1.4988x**
  the instructions — which matches `F_work` 1.496357x to **0.2%** and is why Q11 is called a
  count problem. **CUBRID's IPC is 18.7% HIGHER than PostgreSQL's**, so Q11 is emphatically
  not a memory-stall story.
- **Context switches**, a fifth independent counter: CUBRID **39,935 in 30.002 s
  (1.334 K/s)** against PostgreSQL **349 (8.75/s)** — a **152x** rate difference on a query
  where CUBRID launches no workers at all.

### Error budget, stated before any factor is interpreted

| Quantity | Blocks | min | max | spread |
|---|---|---|---|---|
| CUBRID block-median wall (saturated) | 3 telemetry + contract block3 | 1.327000 s | 1.343999 s | **1.28%** |
| PostgreSQL block-median wall (saturated) | 3 telemetry + contract block3 | 0.798124 s | 0.809841 s | **1.47%** |

The ratio band implied by those two spreads is **1.6386x .. 1.6839x**. The contract
`R_wall = 1.681443x` sits at the **top** of that band, so the honest verdict is
"CUBRID **1.64x–1.68x** slower". `F_work` 1.4964x, `F_cost` 0.9077x, `F_units` 1.2359x,
`F_cpu` 1.3584x and anchor C's `F_plan` 1.0911x are all outside the 2.8% band width and are
safe to interpret at the stated precision. Anchor B's `F_plan` **1.001493x is inside the
band** and is reported as a **null result**, not as a 0.15% effect. Anchor A's `F_plan`
0.927064x is 2.6x the band width.

**The saturated-state spreads above are the error budget of the reported numbers. They are
not the uncertainty of "Q11 CUBRID": across the whole session, before saturation, CUBRID's
block medians span 3.544 s .. 1.327 s, a 2.671x range (2.851x including the convergence
probe's 3.782999 s), while PostgreSQL's 12 block medians span 1.47%.** That range is a measured property of
the engine (§5-e), not measurement noise, and it is why the headline is taken where it is.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q11 (Important Stock Identification) |
| Pinned `ssot_commit` | `122c21596b15c5bf9c9a1a4b8d46c7fdaac4ee69` |
| Pinned `ssot_blob_sha` | `510478846bff081d3223d3835069283a7cd2e47b` |
| SSOT drift | `NONE` — HEAD blob `510478846bff081d3223d3835069283a7cd2e47b` equals the pinned blob at the pre-block gate (`preflight-Q11.txt`) and at the post-block gate (`q11-postcheck.txt`). The pinned commit `122c215` and the workspace HEAD `6c86974` carry the **same** `SSOT.md` blob, verified by `git rev-parse` on both |
| GJC session ID | `019fb8e7-fe3e-7000-b0d5-5a2ee55b905a` |
| Workspace HEAD at measurement | `6c86974f1ebbb76f302babe9cfd4d393058c0e97` (== `origin/main`, `tpch-sspq` porcelain empty before and after) |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 merge `b334446d6`) |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13`, ELF Build ID `4df41ee21300bf617bccd5e1d5c8522b074ef86e`, RelWithDebInfo, gcc 8.5.0 |
| CUBRID server PID / DB | 1612732 / `tpch_sf10_q1`, port 1523 owner `cub_master` PID 1433697 — classified `OK` (campaign prefix) pre- and post-block |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b`, ELF Build ID `5f2cb2987765c612638c278f85cfc85c211fffe1`, gcc 8.5.0, JIT off, assertions off |
| PostgreSQL postmaster / PGDATA | 1433696 / `/home/cubrid/pg/pgdata-tpch-sspq`, port 5442 — classified `OK` pre- and post-block |
| Both binary hashes | match the frozen `reports/bootstrap/build-manifest.json` (`frozen: true`) |
| Canonical query SHA-256 | `9be250c024070328dfa525f161340eecc5d850708d3b3f86e26219ed90c1dc22` — `queries/q11-cubrid.sql` **byte-matches** `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q11.sql` |
| PostgreSQL dialect SHA-256 | `4a3eceded446e6fac21461e7a2d502e6a8bfcc5c78cac69f32800a546b42c442`, one change (`queries/diff/q11.diff`, 641 B): the bracket-quoted identifier `[value]` → the standard double-quoted `"value"`, in the select list and in `ORDER BY`. No hint, no join reordering, no subquery rewrite, no extra predicate, no semantic cast |
| Schema | 8 FKs / 8 FK-owned child B-trees on CUBRID; 8 FKs all `convalidated=t` plus 8 explicit `idx_fk_*` `USING btree` on PostgreSQL, exact child-column order verified |
| Row counts (both engines, exact `COUNT(*)`) | region 5, nation 25, supplier 100,000, customer 1,500,000, part 2,000,000, partsupp 8,000,000, orders 15,000,000, lineitem 59,986,052 |
| Statistics track | `histogram-enabled controlled comparison` — CUBRID `update_statistics_update_histogram=y`, `default_histogram_bucket_count=300`; PostgreSQL standard `ANALYZE`, `default_statistics_target=100`. `pg_stat_user_tables.last_analyze` reads `never` because the statistics collector was reset by a later postmaster restart, not because `ANALYZE` is missing — `reports/bootstrap` records the run and `pg_statistic` is populated |
| Parallel/buffer label | `configured node/gather-cap comparison`, **not** DOP parity and **not** global-worker parity; `configured-equal buffer budget` |
| Parallel settings | CUBRID `parallelism=6`, `max_parallel_workers=100`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`, `parallel_leader_participation=on`, `max_worker_processes=16`. **Neither cap binds on Q11**: CUBRID launches 0 workers and PostgreSQL launches 1 |
| Buffer/cache | CUBRID `data_buffer_size=8.0G` (`data_buffer_pages=524288`, 16 KiB pages); PostgreSQL `shared_buffers=1048576 × 8kB = 8192MB`. **Load-bearing for Q11** — see §3-a and §7 |
| Shared memory | PostgreSQL `dynamic_shared_memory_type=mmap` (`postgresql.conf:969`). Recorded per SSOT §9; Q11's only DSM consumer is the InitPlan's 2-row `Gather` tuple queue, so this setting is not load-bearing here |
| CPU/NUMA | SUT + client CPUs `0-15`, memory node0; collectors `20-23`. All engine TIDs inside the cpuset: 34 pre-block (cub_master 2, cub_server 24, postmaster 1, pg_children 7), 35 post-block — `off_cpuset=0` both times |
| External SUT-set load | 0.312 core-s/s pre-block, 0.268 post-block, threshold 6.0 → `PASS`. Every accepted block carries `load_verdict=CLEAN` under the strict per-sample rule (contract block3: `external_max` 0.7635 CUBRID, 0.4541 PG) |
| Engine block order | Q11 is **odd** → CUBRID block first, then PostgreSQL block (SSOT §12) |
| Timeout | not reached; no censoring (max statement 3.563 s against a 300 s limit) |

## 2. Correctness

| Item | Value |
|---|---|
| Status | **`result-equivalent-at-SF10`** |
| Detail | 8,685 rows, `ordered=True` — the query has `ORDER BY value desc`, so the ordered result sequence was compared exactly |
| Comparator | `harness/correctness_check.py` → `smoke_check.py`, SSOT §11 rules: exact ordered sequence, raw decimal text preserved, relative tolerance `abs(a-b) ≤ 1e-12 × max(1, abs(a), abs(b))` allowed for output-scale only |
| Raw | `q11-correctness.json`, `q11-correctness-cubrid.out` (161,577 B), `q11-correctness-postgresql.out` (161,576 B) |
| Censoring | none |
| Independent cross-check 1 | 11 ground-truth queries returned **identical** values on both engines (`q11-groundtruth-cubrid.out` vs `q11-groundtruth-pg.out`), including the group count 304,774 the aggregation must produce, the post-`HAVING` count 8,685 and the `HAVING` threshold itself, `8102913.765246800000` |
| Independent cross-check 2 | the 34,740 result rows extracted from CUBRID's contract-block sink and from PostgreSQL's contract-block sink hash to the **same** SHA-256 `66148d0cace80b83c0c18f6e5874ee2e8b53f8ab4db97dbdc1ab5d3835b43012` — the two engines' 8,685-row outputs are byte-identical including decimal text and tie order (`q11-variant-equivalence.txt`) |
| Controlled variants | CUBRID `/*+ NO_HASH_AGGREGATE */` and PostgreSQL `max_parallel_workers_per_gather=0` both return rows byte-identical to their own engine's native block. PostgreSQL `enable_hashagg=off` differs in **exactly 2 of 8,685 positions**, and they are a transposition of two rows carrying the **identical** aggregate value `8576064.00` (`170816` and `782948`): same row multiset, identical value sequence. `order by value desc` has no tiebreaker, so both orders satisfy the query. Tolerance is **not** used to hide a different row set — the multiset comparison is exact |

Top row, both engines: `393251 | 20382773.62`. Second and third: `534271 | 19554795.32`,
`828067 | 19354244.05`.

## 3-b. Headline timings

Regime: **`single-query-repeat WARM`**, metadata connection mode
**`single-connection-four-statements`** — one direct campaign connection, one uncounted
warmup statement, WARM proved, three measured statements consecutively, connection closed.
CUBRID uses `csql -C` direct ad-hoc execution; PostgreSQL uses one `psql` Unix-socket
connection with the simple-query protocol. Every statement fully consumes all 8,685 rows into
a campaign-owned fixed sink under `work/Q11/sink` with no terminal rendering; output bytes are
recorded and the content hash is computed after the headline timer stops.

| Field | CUBRID | PostgreSQL |
|---|---|---|
| uncounted warmup (s) | 1.340000 | 1.061985 |
| measured 1 (s) | 1.342000 | 0.798124 |
| measured 2 (s) | 1.340000 | 0.795354 |
| measured 3 (s) | 1.346000 | 0.805589 |
| **median (headline, s)** | **1.342000** | **0.798124** |
| mean (s) | 1.342667 | 0.799689 |
| within-block sd (s) | 0.003055 (**0.2275%**) | 0.005294 (**0.662%**) |
| contract block used | **block3** (of 3; blocks 1–2 superseded, §5-e) | **block3** (of 3, taken for symmetry) |
| block accepted on attempt | 1 of 6 | 1 of 6 |
| load verdict | `CLEAN` (external mean 0.2226, max 0.7635 core-s/s) | `CLEAN` (external mean 0.2567, max 0.4541) |
| sink bytes / SHA-256 | 1,251,371 / `f8d10a878a5708a8ff21ba27a12dd2af…` | 646,399 / `3e9a88466e1525fa5d96f4690195e81b…` |
| **median wall ratio** | **1.681443x** (CUBRID slower by 68.14%) | — |
| correctness / censoring | `result-equivalent-at-SF10` / none | `result-equivalent-at-SF10` / none |

No confidence interval is claimed from three values. The **1.28% / 1.47%** saturated
block-median spreads in the error budget above are the campaign's honest uncertainty on these
numbers.

### All three contract blocks, because the CUBRID series is the finding

| Block | CUBRID measured (s) | median | PostgreSQL measured (s) | median | ratio |
|---|---|---|---|---|---|
| block1 | 3.563 / 3.544 / 3.540 | 3.544000 | 0.800174 / 0.795736 / 0.799853 | 0.799853 | 4.43081x |
| block2 | 2.297 / 2.257 / 2.258 | 2.258000 | 0.799585 / 0.800342 / 0.800674 | 0.800342 | 2.82005x |
| **block3** | **1.342 / 1.340 / 1.346** | **1.342000** | **0.798124 / 0.795354 / 0.805589** | **0.798124** | **1.68144x** |

Every one of the six blocks was accepted on attempt 1 with `load_verdict=CLEAN` and a
`CONVERGED` WARM gate. PostgreSQL's three medians span **0.06%**. CUBRID's span **2.64x**.
§5-e is why, and block3 is why the headline is taken there.

### WARM proof

WARM is proved, not assumed, on four independent grounds.

1. **Gate parameters derived from measurement, not inherited.** Two independent
   40-statement load-gated convergence probes: PostgreSQL converged at statement 12, steady
   0.803524 s; CUBRID converged at statement 12, steady 3.782999 s, half-split trend
   **+0.0000%**, trailing spread 0.6873%. The PostgreSQL probe was *rejected* by the default
   gate with `monotone trailing window (still drifting)` even though its level is flat to
   0.14%, so the monotone false-rejection rate was measured on the known-stationary body of
   both probes: **`WINDOW=4` → CUBRID 5/36 (13.9%), PostgreSQL 7/36 (19.4%); `WINDOW=6` →
   2/34 (5.9%) and 1/34 (2.9%)** against an analytic white-noise rate of `2/W!` = 8.3% and
   0.28%. Q11 therefore runs every gate at **`WINDOW=6`**, which is *stricter* on the spread
   test and 3–7x less prone to the artifact, with `LEVEL_TOL` unchanged from Q10 (CUBRID 3.0%
   / PG 1.0%) and `SPREAD` 5.0% / 3.0%. Both probes pass at `WINDOW=6` on the full 40 and on
   the first 20. Derivation: `q11-warm-gate-params.txt`.
2. **Per-block WARM establishment.** Every timed block ran a 20-statement uncounted
   `warm_establish.py` pass first and had to pass the gate before the contract block was
   timed. Contract block3: CUBRID `CONVERGED, half-split trend −0.0745%, trailing spread
   3.7397%, steady 1.337`; PostgreSQL `CONVERGED, half-split trend +0.0384%, trailing spread
   0.9537%, steady 0.797643`. No CUBRID or PostgreSQL block attempt was ever rejected on
   Q11 — for the WARM gate or for load.
3. **Zero physical reads at the device *and* zero buffer misses.** In the saturated state
   CUBRID's trace reports `ioread: 0` at **every** node of the statement, `/proc/<cub_server>/io`
   reports 96 read syscalls per statement (against 1,011,949 page fixes), and device
   `read_bytes` delta is 0. PostgreSQL reports `Buffers: shared hit=676275` with `read`
   absent, `pg_statio_user_tables.heap_blks_read` unchanged across the block
   (415,136,483 → 415,136,483) and device `read_bytes` delta 0. **This is the first query of
   the campaign where WARM means zero buffer misses on both engines rather than
   "misses served from the OS page cache"** — which is exactly what makes §6's profile
   comparison clean.
4. **The saturation proof itself.** 60 successive connections × 4 statements flat at
   1.318–1.370 s, then 60 statements in one connection flat at 1.316–1.346 s (median
   1.3300 s, spread 2.28%, half-split trend +0.678%), at 96–127 reads per statement
   (`q11-conn-probe.txt`). WARM here is not "the last four statements look alike"; it is a
   demonstrated fixed point of both the wall and the miss count under both variation axes.

## 4. Plan

### 4-a. CUBRID native (estimated, `SET OPTIMIZATION LEVEL 514`, non-executing)

```text
temp(order by)                                             cost 9752 card 320000
  subplan: temp(group by)   sort: 1 asc                    cost 8322 card 320000
    subplan: idx-join (inner join)                         cost 6892 card 320000
      outer: idx-join (inner join)                         cost   89 card 4000
        outer: sscan  nation    sargs: n_name='GERMANY'    cost    1 card 1
        inner: iscan  supplier  index: fk_supplier_nation  cost  113 card 100000
      inner: iscan  partsupp   index: fk_partsupp_supplier cost    5 card 8000000
  + a separate, structurally IDENTICAL uncorrelated subquery plan for the HAVING threshold
```

Selectivities the optimizer used: `n_name='GERMANY'` 0.04, `s_nationkey=n_nationkey` 0.04,
`ps_suppkey=s_suppkey` 1E-05. Both join estimates are exact by construction (25 nations,
100,000 suppliers) and the final cardinality estimate is **320,000 against a true 323,920
(0.9879x)** — the most accurate cardinality estimate CUBRID has produced in this campaign.
The group estimate is not used: the plan sorts.

### 4-b. PostgreSQL native (`EXPLAIN ANALYZE, BUFFERS, VERBOSE, SETTINGS`), saturated

```text
Sort  (quicksort, Memory: 656kB)                     actual 1077.757..1078.042 rows=8685
  InitPlan expr_1
    -> Finalize Aggregate                            actual  237.080.. 237.172 rows=1
       -> Gather  (Workers Planned 1, Launched 1)     actual  236.715.. 237.161 rows=2
          -> Partial Aggregate                       actual  234.158.. 234.161 loops=2
             -> Nested Loop                          actual    0.105.. 201.906 rows=161960 loops=2
                -> Hash Join  (s_nationkey = n_nationkey)   actual 0.060..9.549 rows=2024.5 loops=2
                   -> Parallel Seq Scan on supplier  actual    0.017..  3.928 rows=50000 loops=2
                   -> Hash (Buckets 1024, Batches 1, 9kB)
                      -> Seq Scan on nation  Filter n_name='GERMANY'  Rows Removed 24
                -> Index Scan using idx_fk_partsupp_supplier  rows=80 loops=4049
                   Index Searches: 4049
  -> HashAggregate                                   actual  874.583..1074.399 rows=8685
     Group Key: ps_partkey
     Filter: (sum(...) > (InitPlan expr_1).col1)
     Planned Partitions: 16  Batches: 17  Memory Usage: 8337kB  Disk Usage: 15064kB
     Rows Removed by Filter: 296089
     -> Nested Loop                                  actual    0.830.. 508.099 rows=323920
        -> Nested Loop                               actual    0.794..   5.892 rows=4049
           -> Seq Scan on nation  Filter n_name='GERMANY'  Rows Removed 24
           -> Bitmap Heap Scan on supplier  Heap Blocks: exact=1872  rows=4049
              -> Bitmap Index Scan on idx_fk_supplier_nation  Index Searches: 1
        -> Index Scan using idx_fk_partsupp_supplier  rows=80 loops=4049
           Index Searches: 4049
Buffers: shared hit=676275, temp read=1330 written=3103
Planning Time: 1.693 ms   Execution Time: 1080.016 ms
```

### 4-c. Shape comparison — what is the same and what is not

| Stage | CUBRID | PostgreSQL | same? |
|---|---|---|---|
| `n_name='GERMANY'` | `sscan nation`, 25 rows read, 1 kept | `Seq Scan on nation`, 24 removed, 1 kept | **yes** |
| ⋈ supplier | **`iscan fk_supplier_nation`**, 4,049 rows, 1 index descent (`readkeys: 1`) | **`Bitmap Index Scan idx_fk_supplier_nation` + `Bitmap Heap Scan`**, 4,049 rows, `Index Searches: 1`, `Heap Blocks: exact=1872` | different node, **identical rows and identical index** |
| ⋈ partsupp | **`iscan fk_partsupp_supplier`**, `readkeys: 4049`, 323,920 rows | **`Index Scan idx_fk_partsupp_supplier`**, `Index Searches: 4049`, `loops=4049`, 323,920 rows | **yes — node for node, index for index, probe count for probe count** |
| `GROUP BY ps_partkey`, 323,920 → 304,774 → 8,685 | **sort-based**, `hash: partial` (runtime-abandoned hash), 1,516 sort pages, **serial** | **`HashAggregate`**, 16 planned partitions, **17 batches**, 8,337 kB in memory + **15,064 kB spilled to disk** | **no — the only optimizer disagreement, and PostgreSQL's side is the slower one** |
| `HAVING` threshold subquery | `SUBQUERY (uncorrelated)` — a structurally **identical** second copy of the whole join, **serial**, 619 ms | `InitPlan expr_1` — the same join, but **`Gather` with 1 worker** and a `Parallel Seq Scan` of all 100,000 suppliers instead of an index probe, 237 ms | **no — same work, PostgreSQL parallelises it** |
| `ORDER BY value desc` | `temp(order by)`, 7 ms, 8,685 rows | `Sort` quicksort 656 kB, 4 ms | equivalent |
| join → aggregation hand-off | join result **materialised into a temp list file** and re-scanned | `TupleTableSlot` passed by reference | **no** |

So `F_plan` cannot be assigned 1.0000 by structural equality — the aggregation strategy and
the subquery's parallelism both differ — which is why all three anchors are measured
controlled A/Bs rather than asserted. It is worth stating plainly how *close* the two plans
are: the join subtree is node-for-node, index-for-index and probe-count-for-probe-count
identical, and both engines independently produce the same 25 → 1 → 4,049 → 323,920 →
304,774 → 8,685 cardinality chain.

### 4-d. Controlled-plan variants (all measured through the same gated §12 block)

| Variant | Shape | Block median | vs its own native |
|---|---|---|---|
| CUBRID native | serial idx-NL ×2, sort-based group-by | 1.342000 s | — |
| CUBRID `/*+ NO_HASH_AGGREGATE */` | **identical plan tree** (cost 9752), `hash: false` instead of `hash: partial`, still serial sort | **1.340000 s** | **1.0015x — null** |
| PostgreSQL native | idx-NL ×2, `HashAggregate` 17 batches, InitPlan 1 worker | 0.798124 s | — |
| PostgreSQL `enable_hashagg=off` | `GroupAggregate` over `Sort` (external merge, Disk: 8248 kB) — CUBRID's shape | **0.739912 s** | **1.0787x faster** |
| PostgreSQL `max_parallel_workers_per_gather=0` | identical plan, InitPlan `Gather` → plain `Aggregate` | **0.870872 s** | **1.0911x slower** |

The forced PostgreSQL `GroupAggregate` is node-for-node CUBRID's aggregation shape and its
`EXPLAIN` confirms the mechanism: `Sort Method: external merge Disk: 8248kB` replaces
`Batches: 17 … Disk Usage: 15064kB`, and `Execution Time` falls 1080.016 → 1020.089 ms.
The serial variant turns `Gather (Workers Launched: 1) → Partial Aggregate` (237 ms) into a
plain `Aggregate` (316.9 ms) and pushes `HashAggregate` from 874.6→1074.4 ms to
953.5→1149.9 ms.

## 5. Execution telemetry

### 5-a. Node-level time, CUBRID trace (`SET TRACE ON`, non-headline, saturated; traced statement 1,532 ms)

| Node | exclusive time | share | workers | fetch / ioread |
|---|---|---|---|---|
| main join (`nation sscan` → `supplier iscan` → `partsupp iscan`) | 593 ms | 38.7% | **none — serial** | 340,127 / **0** |
| `SUBQUERY (uncorrelated)` — a second, identical copy of the join | 619 ms | 40.4% | **none — serial** | 340,131 / **0** |
| `GROUPBY` (sort-based, `hash: partial`) | 313 ms | 20.4% | **none — serial** | page 1,516 / **0** |
| `ORDERBY` | 7 ms | 0.5% | **none — serial** | page 1,516 / **0** |
| sum | 1,532 ms | 100.0% of the traced 1,532 ms | | 1,011,949 / **0** |

The trace sums to the traced statement time exactly, and **no node reports a
`(parallel workers: …)` sub-line**, which is the independent confirmation of `U ≈ 1`. Within
each join copy, `btree time` is 423 / 465 ms and `lookup time` 369 / 416 ms — i.e. the
partsupp index probe plus heap lookup is essentially the whole join. The traced statement is
14.2% slower than the headline median (1.532 s vs 1.342 s) because tracing is instrumented
and non-headline; the *shares* are what this table is used for.

**The single largest structural fact in this table: 79.1% of CUBRID's statement is the same
join executed twice, and both copies are single-threaded.**

### 5-b. Node-level time, PostgreSQL (`EXPLAIN ANALYZE`; 1,080.0 ms, 35.3% above the 798.1 ms headline)

| Stage | interval | share |
|---|---|---|
| `InitPlan expr_1` — the `HAVING` threshold, 2 units | 0 → 237.2 ms | 22.0% |
| main `nation` → `supplier` bitmap scan | 0.8 → 5.9 ms | 0.5% |
| main `partsupp` index probes (4,049 loops, 323,920 rows) | → 508.1 ms | 46.5% |
| `HashAggregate` build + 17-batch spill + `HAVING` filter | 874.6 → 1074.4 ms | 18.5% |
| final `Sort` + output | → 1078.0 ms | 0.3% |

PostgreSQL's aggregation tail is **~204 ms** against CUBRID's **320 ms** (`GROUPBY` 313 +
`ORDERBY` 7), and PostgreSQL's threshold subquery is **237 ms** against CUBRID's **619 ms**.
The main join is the one place they are close: 508 ms vs 593 ms.

### 5-c. CPU accounting (SSOT §15; median-U telemetry run per configuration, saturated)

| Configuration | `executor_cpu` | `auxiliary_query_cpu` | `total_query_cpu` | `U` | TWU | peak units | serial tail |
|---|---|---|---|---|---|---|---|
| CUBRID native | 5.36 core-s | 0.08 core-s | 5.44 core-s | 1.00965 | 0.9975 | 1.1400 | 5.434 s |
| PostgreSQL native | 4.33 | 0.00 | 4.33 | 1.24996 | 1.2293 | 2.0375 | 0.353 s |
| CUBRID `NO_HASH_AGGREGATE` | 5.35 | 0.09 | 5.44 | 1.01134 | 0.9928 | 1.1478 | 5.439 s |
| PostgreSQL `enable_hashagg=off` | 3.84 | 0.00 | 3.84 | 1.19434 | 1.1716 | 2.0620 | 0.351 s |
| PostgreSQL serial | 3.71 | 0.00 | 3.71 | 0.98764 | 0.9916 | 1.0430 | 3.741 s |

Values are per **block** (1 uncounted warmup + 3 measured statements). `executor_cpu` is
query threads inside `cub_server` for CUBRID and the leader backend plus parallel workers for
PostgreSQL; `auxiliary_query_cpu` is `csql` parse/plan/result work for CUBRID and io workers
plus `psql` for PostgreSQL. They are never merged and nothing unattributable is folded in.

Two things to note. First, **PostgreSQL's `auxiliary_query_cpu` is 0.00 on Q11** — with zero
buffer misses its io workers never run, which is the mirror image of Q10 where they cost
9.60 core-s. Second, CUBRID's `serial_tail_s` is **5.434 s of a 5.370 s block**: the tail *is*
the block. Peak simultaneous units 1.1400 (CUBRID) reflects the sampler catching the
`csql` client and the server thread in the same 0.25 s bucket, not a second query unit.

Worker counts, from each engine's own reporting:

- CUBRID native: **no `parallel workers` sub-line at any node of the trace**, at either
  copy of the join, the group-by or the order-by. `parallelism=6` and
  `max_parallel_workers=100` are configured and neither binds. The driving scan is a 1-page
  `nation` heap scan, so the SCAN auto-degree formula cannot produce more than 1, and the
  uncorrelated subquery's degree is hardcoded to 1 (IMP-009).
- PostgreSQL native: `Workers Planned: 1, Workers Launched: 1` in the InitPlan only, plus a
  participating leader (`loops=2` on every node under that `Gather`) = 2 units there and 1
  unit everywhere else. That single worker is `F_units` in its entirety (anchor C).

### 5-d. Buffer, `/proc` I/O, iostat and NUMA (stage 14.7, non-headline, 4-statement block)

| Quantity | CUBRID | PostgreSQL |
|---|---|---|
| device read (all block devices) | **0.000 MiB** | **0.000 MiB** |
| device write | 262.492 MiB `sdb` (≈65.6 MiB/statement) | 23.484 MiB `sdb` (≈5.9 MiB/statement) |
| `/proc/<server>/io read_bytes` | **0** | **0** |
| `/proc/<server>/io rchar` | 16.61 GB (4.153 GB/statement) | 263.7 MB (65.9 MB/statement) |
| `/proc/<server>/io write_bytes` | 4,079,616 | 373,432,320 with `cancelled_write_bytes` 373,268,480 |
| read syscalls | 1,014,735 (253,684/statement) | 32,614 (8,153/statement) |
| buffer counters | `Num_data_page_lru1` **97,369**, `lru2` 306, `lru3` 426,613, `private_count` **1,638**, `private_quota` 5,242 | `heap_blks_read` **+0**, `heap_blks_hit` +2,607,932 over the block |
| per-statement engine-level misses (saturated) | **0** page `ioread` (trace) | **0** blocks read (`EXPLAIN`, `pg_statio`) |
| NUMA | `cub_server` 8,825.88 MB node0 / 5.65 MB node1 | `postgres` 150.88 MB node0 / 0.51 MB node1 |

Note the diag block was taken *mid-migration* (253,684 reads/statement), which is why its
`rchar` is 4.153 GB/statement; the saturated numbers are in §3-a and §5-a. The two rows that
matter are read as a pair with §5-e: **at every point of the session both engines' device
reads are 0**, so this is never a disk story — it is entirely about which side of the
`pread` boundary the pages sit on.

CUBRID's 65.6 MiB/statement of device write is the group-by sort's 1,516 temp pages plus the
join's temp list file. PostgreSQL writes less to the device (5.9 MiB) while generating *more*
nominal temp traffic (373 MB of `cancelled_write_bytes`, pages dirtied and dropped before
writeback, plus `temp written=3103` blocks from the 17-batch HashAggregate spill).

**One CUBRID instrument is recorded as unusable, reproducing Q10's finding.**
`cubrid statdump -c` reported a delta of **exactly 0** for `Num_data_page_fetches`,
`Num_data_page_ioreads`, `Num_data_page_iowrites`, `Num_data_page_dirties` and
`Num_file_ioreads` across a block the trace shows fetched 1,012,000 pages per statement, and
`page_fix_by_type` came back empty. This was independently re-confirmed on Q11 by running one
statement between two dumps: the counters did not move while `/proc/<cub_server>/io` recorded
551,116 read syscalls and 8.406 GiB of `rchar`. The gauge-style fields in the same dump *do*
track (`Num_data_page_lru1/lru2/lru3`, `Num_data_page_private_count`,
`Num_data_page_private_quota`, `victim_candidate`), and those gauges are **load-bearing for
IMP-018**. So the five counters are excluded from every calculation here and the gauges are
cited. Raw: `q11-cubrid-statdump-{pre,mid,post}.txt`, `Q11-cubrid-buffer-io-diag.json`.

### 5-e. The measurement that had to be made before any other: CUBRID's 2.6408x buffer-retention decay

This subsection exists because Q11 cannot be measured without it, and because it is the
reason the headline is taken from block3 rather than block1.

**What was observed.** CUBRID's block median fell monotonically across every stage of this
one session while PostgreSQL's did not move:

| stage | CUBRID block median | PostgreSQL block median |
|---|---|---|
| 40-statement convergence probe | 3.782999 s | 0.803524 s |
| contract block1 | 3.544000 s | 0.799853 s |
| telemetry run1 / 2 / 3 | 3.263 / 3.031 / 2.821 s | 0.808050 / 0.799501 / 0.803909 s |
| 120-statement single-connection probe | 2.477 s (flat, see below) | — |
| contract block2 | 2.258000 s | 0.800342 s |
| telemetry run4 / 5 / 6 | 2.053 / 1.907 / 1.685 s | 0.807231 / 0.805497 / 0.806641 s |
| 60-connection sweep, connections 5–60 | 1.318–1.370 s | — |
| contract block3 + telemetry 7/8/9 | 1.342 / 1.341 / 1.327 / 1.343999 s | 0.798124 / 0.800721 / 0.801753 / 0.809841 s |

Every CUBRID block above individually **passed** the WARM gate. Over all 12 blocks of the
session (9 telemetry + 3 contract) PostgreSQL's medians span **0.798124 s .. 0.809841 s
(1.47%)** and its individual measured statements span 0.7945 s .. 0.8121 s; CUBRID's block
medians span **3.544 s .. 1.327 s (2.671x)**, and including the 40-statement convergence
probe's steady state of 3.782999 s the session range is **2.851x**.

**Two probes separate the variable.** Statement count and connection count were varied
independently:

- **one connection, 120 statements** (`q11-drift-probe-cubrid.txt`): wall 2.450–2.521 s,
  **half-split trend −0.16%**, syscr per statement stable at 193,235–210,348, mean 207,599,
  device `read_bytes` delta **0** over 379.9 GiB of `rchar`. **Flat.**
- **60 connections × 4 statements** (`q11-conn-probe.txt`): reads per statement
  49,292 → 34,538 → 18,306 → 3,519 → **135** over the first five connections, then
  111–127 for the remaining 55, with the wall following 1.581 → 1.353 → 1.318–1.370 s.
  **Decays, and saturates.**
- **one connection, 60 statements immediately afterwards**: median **1.3300 s**, min 1.316,
  max 1.346, spread **2.28%**, 96 reads/statement. **Flat at the new level.**

So the decay is driven by the number of **connections**, not by the number of statements.

**Three traces of the same statement, taken 22 minutes apart, hold everything constant but
the miss count:**

| | first (`q11-trace-cubrid.out`) | mid (`…-asymptote.out`) | saturated (`…-saturated.out`) |
|---|---|---|---|
| `SELECT (time: …)` | 3,360 ms | 1,748 ms | **1,532 ms** |
| `fetch` (page fixes) | 1,012,042 | 1,012,172 | **1,011,949** |
| `ioread` | 566,103 | 67,605 | **0** |
| `fetch_time` | 2,061 ms | 528 ms | **326 ms** |
| partsupp scan `btree time` | 1,297 ms | 534 ms | 423 ms |
| supplier scan `ioread` | 3,790 | 0 | 0 |
| `GROUPBY time` | 320 ms | 312 ms | **313 ms** |
| `ORDERBY time` | 7 ms | 7 ms | **7 ms** |

The page-fix count varies by **0.02%**, the group-by and order-by times do not move at all,
and `fetch_time` accounts for **1,735 ms of the 1,828 ms (94.9%)** recovered. PostgreSQL's
`EXPLAIN ANALYZE` over the same interval: `Execution Time` 1079.898 ms → 1080.016 ms,
`Buffers: shared hit=676275 read=0` both times.

**The mechanism, from the pinned source, with the counters that confirm each step.**

1. Q11 runs entirely on the client transaction thread (no parallel units anywhere), so
   `thread_private_lru_index != -1` and every page it physically reads is unfixed onto the
   **top of that session's private LRU list** —
   `page_buffer.c:6902-6912`, `pgbuf_unlatch_void_zone_bcb()`.
2. That list's quota is
   `new_quota = MIN(activity_share × all_private_quota, PGBUF_PRIVATE_LRU_MAX_HARD_QUOTA, num_buffers/2)`
   — `page_buffer.c:14378-14380`, with the constant `PGBUF_PRIVATE_LRU_MAX_HARD_QUOTA 5000`
   at `page_buffer.c:1024`. With one active session `activity_share ≈ 1`, and
   `all_private_quota = (num_buffers − invalid) × private_pages_ratio`
   (`page_buffer.c:14363`) with `private_pages_ratio` pinned at its floor
   `MIN_PRIVATE_RATIO 0.01f` (`page_buffer.c:14193`), giving `0.01 × 524,288 = 5,242`.
   **Both ceilings land within 9% of each other on this pool size, so the measurement cannot
   separate them and both would have to be fixed.** Observed
   `Num_data_page_private_quota` = 5,242 / 5,448 / 5,242 in three independent dumps, and
   `Num_data_page_private_count` = **5,002 / 5,003** whenever the misses are present.
3. Beyond quota the list's bottom becomes victim candidates and pages are recycled. The one
   escape into the ~519,000-page shared pool is
   `pgbuf_should_move_private_to_shared()` — `page_buffer.c:6951-6984` — whose conditions are
   **(a)** `thread_private_lru_index != bcb_lru_idx`, i.e. a *different* session touches the
   page, or **(b)** `pgbuf_bcb_is_hot(bcb)` **and** `PGBUF_IS_BCB_OLD_ENOUGH`.
4. Condition (b) needs `PGBUF_FIX_COUNT_THRESHOLD = 64` fixes (`page_buffer.c:106`, tested at
   `:16294`) accumulated **while the page is resident**. Q11 fixes a given partsupp heap page
   `323,920 / 93,281 = 3.47` times per statement, spread across the statement, inside a
   5,000-page window over a 93,281-page heap — so (b) is effectively unreachable, which is
   why one connection running 120 statements never improves.
5. Condition (a) fires per **new connection**, because `pgbuf_assign_private_lru()`
   (`page_buffer.c:14451+`) hands every connection a fresh private list. Each new connection
   therefore migrates the previous one's pages into the shared pool. Observed:
   `Num_data_page_lru1` (the shared hot zone) **15,092 → 82,352 → 97,369** — Q11's whole
   working set — while `Num_data_page_private_count` falls **5,002 → 1,638**.

**Why this is not IMP-002.** Q11's entire referenced working set is ~97,400 pages of a
524,288-page pool, i.e. **18.6% of it**. IMP-002's premise — a working set that *exceeds* the
pool — is absent, and the saturated state proves the set fits by taking **zero** reads. The
binding limit is measured at ~5,000 pages, **0.95%** of the pool. Q11 also refutes Q05's
formulation that the pool "cannot leave" its equilibrium "without a server restart": 20
further connections leave it, with no restart and no parameter change. Hence a new ID,
**IMP-018**, with Q11 also recorded on IMP-002 as the query that bounds its symptom from
above. Deduplication record: `q11-registry-dedup.txt`.

**What this costs the campaign's own protocol, stated plainly.** SSOT §12's WARM gate
operates on a single connection's statement series. Q11 proves that a CUBRID query can be
converged on that criterion — half-split trend −0.16% over 120 statements — while its true
steady state is **1.86x faster** (2.477 s vs 1.330 s) and reachable only by opening more
connections. Every
Q11 CUBRID artifact taken before saturation is preserved with an explicit
`invalid_reason` in `raw-manifest.json`, and the report's numbers all come from the saturated
state. This is a candidate protocol strengthening for future queries (drive N connections,
not N statements, before the contract block); it is **not** applied retroactively to Q01–Q10
and no Q01–Q10 number is restated here.

## 6. Profile

`perf` is non-headline. Both captures attach to a **verified PID set**, never an all-CPU
profile, and resolved-sample coverage was validated: CUBRID 1,422 flat lines with
**0 unknown-symbol lines**, PostgreSQL 1,575 flat lines with **0 unknown-symbol lines**. Both
were taken in the saturated state, so **neither profile contains any physical-read work** —
the cleanest like-for-like comparison of the two buffer managers this campaign has produced.

| | CUBRID | PostgreSQL |
|---|---|---|
| PID set | `cub_server` 1612732 (all 26 query worker TIDs live inside it) | postmaster 1433696 → leader 2037469 + worker 2037507 |
| window / repeats | 30.002 s / 60 statements driven (≈22.4 completed) | 30.002 s / 60 driven (≈37.6 completed) |
| cycles | 86,046,676,375 @ 2.873 GHz | 114,577,321,141 @ 2.873 GHz |
| instructions | 141,848,566,511 | 159,126,193,112 |
| **IPC** | **1.65** | **1.39** |
| instructions / statement | **6.345 G** | **4.233 G** (ratio **1.4988x**) |
| task-clock | 29,945.28 ms = **0.998 CPUs** (`U` = 1.00965, −1.2%) | 39,884.02 ms = **1.329 CPUs** (`U` = 1.24996, +6.3%) |
| context switches | 39,935 = **1.334 K/s** | 349 = **8.75/s** (**152x** apart) |
| samples | 30,207 | 26,138 |

**The instruction ratio 1.4988x matches `F_work` 1.496357x to 0.16%.** CUBRID retires 1.50x
the instructions because it performs 1.50x the page fixes, at a *higher* IPC. There is no
stall story and no per-operation-cost story in Q11's CPU factor.

### 6-a. CUBRID resolved-symbol bands (self %, `cycles`; 83.92% of the profile accounted, 65.11% banded)

| share | band | top symbols |
|---|---|---|
| **21.07%** | **pgbuf hash lookup + fix/unfix + LRU list surgery** | `pgbuf_fix_release` 17.06, `pgbuf_unfix` 2.45, `pgbuf_ordered_fix_release` 0.71, `pgbuf_ordered_unfix` 0.47, `pgbuf_set_dirty` 0.38 |
| **15.92%** | **heap record access** | `spage_get_record` 4.62, `heap_attrinfo_read_dbvalues` 4.32, `or_mvcc_get_repid_and_flags` 3.86, `heap_prepare_get_context` 1.71, `or_mvcc_get_header` 0.58, `spage_get_record_data` 0.45, `heap_get_visible_version_internal` 0.38 |
| 7.26% | NUMERIC arithmetic (sum + multiply per row) | `float_numeric_db_value_mul` 3.17, `qdata_evaluate_aggregate_list` 1.30, `float_numeric_db_value_add` 1.06, `numeric_db_value_coerce_to_num` 0.64, `qdata_add_dbval` 0.61, `qdata_multiply_dbval` 0.48 |
| 6.13% | userspace memmove/memset | `__memmove_evex_unaligned_erms` 5.69, `__memset_evex_unaligned_erms` 0.44 |
| 5.23% | external sort machinery (group-by + order-by) | `qfile_compare_partial_sort_record` 2.47, `sort_exphase_merge` 0.81, `mr_data_readval_numeric` 0.81, `numeric_db_value_compare` 0.74, `sort_run_merge` 0.40 |
| 3.71% | `DB_VALUE` lifecycle | `pr_clear_value` 2.27, `db_value_domain_init` 1.44 |
| **3.06%** | **libpthread mutex** | `__pthread_mutex_unlock_usercnt` 1.29, `__pthread_mutex_trylock` 1.01, `__pthread_mutex_lock` 0.76 |
| 2.73% | list-file tuple materialisation | `qfile_generate_tuple_into_list` 0.83, `qexec_end_one_iteration` 0.78, `qdata_generate_tuple_desc_for_valptr_list` 0.71, `qdata_copy_db_value_to_tuple_value` 0.41 |
| **0.00%** | **kernel page-cache copy on the query thread** | *nothing above the 0.3% cut — the saturated state takes no reads* |
| unbanded, top | | `fetch_val_list` 2.33, `fetch_peek_arith` 1.68, `scan_next_scan_local` 1.44, `malloc` 1.21, `tp_value_cast_internal` 1.14, `fetch_peek_dbval_slow` 1.02, `logtb_find_isolation` 0.86, `btree_select_visible_object_for_range_scan` 0.54 |

The call graph resolves `pgbuf_fix_release`'s internals: `pgbuf_search_hash_chain` (inlined)
3.86% + `pgbuf_search_hash_chain_no_bcb_lock` (inlined) 1.62% = **5.48% of the profile is
buffer hash-chain search**, plus `pgbuf_lockfree_fix_ro` 3.77%, `pgbuf_latch_bcb_upon_fix`
0.81% + 0.73% and the trylock/unlock pair 0.95% + 0.65%. 15.04% of `pgbuf_fix_release`'s
19.44% inclusive arrives via `pgbuf_ordered_fix_release`.

### 6-b. PostgreSQL resolved-symbol bands (84.26% accounted, 69.04% banded)

| share | band | top symbols |
|---|---|---|
| **23.72%** | **buffer hash lookup + pin/unpin + lwlock** | `hash_search_with_hash_value` 12.73, `PinBuffer` 4.41, `LWLockAttemptLock` 1.70, `LockBufferInternal` 0.76, `UnpinBufferNoOwner` 0.74, `GetPrivateRefCountEntrySlow` 0.70, `LWLockRelease` 0.68, `StartReadBuffer` 0.65, `BufferLockUnlock` 0.53, `hash_bytes` 0.47, `ResourceOwnerForget` 0.35 |
| 8.07% | heap/seq scan | `heap_page_prune_opt` 7.56, `heap_fill_tuple` 0.51 |
| 7.08% | index/heap fetch + visibility | `heap_hot_search_buffer` 6.01, `HeapTupleSatisfiesVisibility` 0.57, `heapam_index_fetch_tuple` 0.50 |
| 6.99% | numeric arithmetic (sum + multiply per row) | `make_result_safe` 2.05, `init_var_from_num` 1.46, `mul_var` 1.07, `accum_sum_add` 0.64, `numeric_mul_safe` 0.62, `do_numeric_accum` 0.42, `sub_abs` 0.38, `int64_to_numericvar` 0.35 |
| 6.80% | kernel mm / temp file | `_compound_head` 3.82, `zap_present_ptes` 0.94, `folio_remove_rmap_ptes` 0.74, `folios_put_refs` 0.50, `free_pages_and_swap_cache` 0.46, `rep_movs_alternative` 0.34 |
| 6.71% | palloc / memory context | `AllocSetAlloc` 2.28, `AllocSetFree` 1.15, `palloc0` 0.84, `AllocSetReset` 0.72, `palloc` 0.70, `MemoryContextReset` 0.59, `pfree` 0.43 |
| 3.80% | hash aggregate build/probe + spill | `LookupTupleHashEntry` 1.24, `LookupTupleHashEntryHash` 0.85, `agg_retrieve_hash_table` 0.78, `lookup_hash_entries` 0.56, `tuplehash_iterate` 0.37 |
| 2.47% | expression interpreter | `ExecInterpExpr` 2.47 |
| 2.24% | tuple deform | `tts_buffer_heap_getsomeattrs` 1.43, `tts_minimal_getsomeattrs` 0.81 |
| unbanded, top | | `next_uptodate_folio` 5.39, `filemap_map_pages` 1.52, `detoast_attr` 1.08, `numeric_sum` 0.93, `ExecStoreMinimalTuple` 0.74 |

**A correction to the campaign's working assumption, forced by the call graph.**
`hash_search_with_hash_value` at 12.73% self is **not** the `HashAggregate`: the call graph
resolves 13.41% of its 13.62% inclusive through
`StartReadBuffer → PinBufferForBlock → BufferAlloc → BufTableLookup`, i.e. it is
PostgreSQL's **shared-buffer hash table**, the exact counterpart of CUBRID's
`pgbuf_search_hash_chain`. Attributing it to the aggregate — the naive reading of the flat
profile — would have produced a false 15.38%-vs-1.66% "CUBRID's buffer manager is 10x
heavier" claim. Corrected, the two buffer bands are:

| | CUBRID | PostgreSQL |
|---|---|---|
| buffer band, self % | 21.07% + 3.06% libpthread = **24.13%** | **23.72%** |
| page fixes per statement | **1,011,949** | **676,275** |
| total query CPU per statement | 1.3550 core-s | 0.9976 core-s |
| **total query CPU per page fix** | **1339.0 ns** | **1475.2 ns** |
| IPC | **1.65** | 1.39 |

**The shares are equal to 1.017x, and per page fix CUBRID is 1.1017x CHEAPER.** Q11's CPU
gap is therefore entirely a *count* of buffer requests, not their unit price, and IMP-013 is
recorded as **refuted on Q11** (§9). PostgreSQL's own cost per fix is inflated by
`heap_page_prune_opt` 7.56%, whose call graph is 9.16% `asm_exc_page_fault → handle_mm_fault`
— soft page faults taken while reading page headers — and by `next_uptodate_folio` 5.39% +
`filemap_map_pages` 1.52% in the temp-file mapping path of its 17-batch spill. Those are
PostgreSQL-side costs and they are recorded here without a CUBRID counterpart claim.

## 7. Source contrast

| Item | CUBRID `file:line` | PostgreSQL `file:line` | Difference | Class |
|---|---|---|---|---|
| A single session can retain only 5,000 buffer pages of a 524,288-page pool, because the cap is a compile-time constant unrelated to `data_buffer_size` | `src/storage/page_buffer.c:1024` `#define PGBUF_PRIVATE_LRU_MAX_HARD_QUOTA 5000`; applied at `:14379` `new_quota = MIN (new_quota, PGBUF_PRIVATE_LRU_MAX_HARD_QUOTA);`; second, independent ceiling at `:14193` `#define MIN_PRIVATE_RATIO 0.01f` feeding `:14363` `all_private_quota = (int) ((pgbuf_Pool.num_buffers - …invalid_cnt) * quota->private_pages_ratio)` | `src/backend/storage/buffer/freelist.c:184` `StrategyGetBuffer(BufferAccessStrategy strategy, …)` — a ring is consulted **only** `if (strategy != NULL)`, otherwise a clock sweep over the whole `NBuffers`; there is no per-backend, per-session or per-connection buffer budget anywhere in the file | CUBRID's default for a session's scan is a **5,000-page (78 MiB) window**; PostgreSQL's default is **the whole pool**. Measured: 566,103 reads/statement vs 0, and `Num_data_page_private_count` pinned at 5,002 | **structural absence** |
| Every page a serial query reads is placed on the session's private list rather than a shared one | `src/storage/page_buffer.c:6902-6912` `pgbuf_unlatch_void_zone_bcb()` — `if (thread_private_lru_index != -1) { … pgbuf_lru_add_new_bcb_to_top (thread_p, bcb, thread_private_lru_index); pgbuf_bcb_register_hit_for_lru (bcb); return; }`; `:206` `PGBUF_VOID_ZONE` is documented as the zone every physically read page passes through | `src/backend/storage/buffer/bufmgr.c:926` `ReadBufferExtended(reln, forkNum, blockNum, RBM_NORMAL, NULL)` — an index scan passes `strategy = NULL`; `:3335-3341` `if (strategy == NULL) { /* Default case: increase usagecount unless already max. */ … buf_state += BUF_USAGECOUNT_ONE; }` | A page CUBRID reads competes only inside its own session's 5,000-page list; a page PostgreSQL reads competes for the whole pool and earns full `usagecount` up to `BM_MAX_USAGE_COUNT` | **structural absence** |
| The escape from the private list is unreachable for a scan pattern | `src/storage/page_buffer.c:6951-6984` `pgbuf_should_move_private_to_shared()` — cond 1 `thread_private_lru_index != bcb_lru_idx` (another session), cond 2 `pgbuf_bcb_is_hot(bcb)` **and** `PGBUF_IS_BCB_OLD_ENOUGH`; `:106` `#define PGBUF_FIX_COUNT_THRESHOLD 64`, tested at `:16294` | `src/backend/storage/buffer/freelist.c:442` `case BAS_BULKREAD:` (256 kB ring) and `:755` `if (strategy->btype != BAS_BULKREAD)` — PostgreSQL **has** a small-window mode, but it is **opt-in** for large sequential scans; nothing demotes a default-strategy page into a smaller window | Q11 fixes a heap page 3.47 times per statement, so the 64-fix bar is unreachable inside a 5,000-page window; the working set escapes only when *another connection* arrives. Measured: 120 statements on one connection change nothing; 4 more connections change everything | **structural absence** |
| The one operator control over this machinery cannot be changed on a running server | `src/base/system_parameter.c:4168-4175` `PRM_ID_PB_NUM_PRIVATE_CHAINS` / `PRM_NAME_PB_NUM_PRIVATE_CHAINS` `"num_private_chains"`, flags `(PRM_FOR_SERVER \| PRM_RELOADABLE)`, `PRM_CLEAR_DYNAMIC_FLAG` | `src/backend/storage/buffer/freelist.c:511` `GetAccessStrategyWithSize(btype, ring_size_kb)` — the ring size is a per-scan argument, and the only global knob (`shared_buffers`) is the pool itself | An operator observing Q11 at 3.544 s has no runtime control that reaches the cause | **structural absence** |
| The uncorrelated `HAVING` subquery — a full second copy of the join — cannot use more than one unit | `src/query/parallel/px_parallel.cpp:85-109` `compute_parallel_degree()`, `case parallel_type::SUBQUERY`, `:89-92` `/* TODO: degree fixed at 1 (main + gather) */` (already registered as IMP-009) | `src/backend/optimizer/plan/planner.c` / `subselect.c` InitPlan generation places the uncorrelated aggregate under a normal `Gather`; the executed plan reports `Workers Planned: 1, Workers Launched: 1` and `loops=2` on every node beneath it | Measured: CUBRID's `SUBQUERY (uncorrelated)` is 619 ms of a 1,532 ms statement with no worker; PostgreSQL's `InitPlan` is 237 ms with 2 units, and removing that worker costs PostgreSQL 1.091149x | **structural absence** |
| The join result is materialised into a temp list file before aggregation, and the aggregation's page traffic goes through the buffer manager | `src/query/query_executor.c:1255-1259` `qexec_end_one_iteration()` — generate tuple into list-file page for every output tuple of a `BUILDLIST_PROC`; `src/query/list_file.c:1851` `qfile_generate_tuple_into_list` (already registered as IMP-006). Profile: 2.73% self, and the 331,691 extra page fixes it causes are banded under pgbuf | `src/backend/executor/nodeAgg.c` consumes its outer `Nested Loop`'s `TupleTableSlot` by reference, and `hashagg_spill_tuple` (`:3029`) spills to a **temp file** outside the buffer manager: `EXPLAIN` reports `temp read=1330 written=3103` and `shared hit` unchanged | **331,691 of CUBRID's 1,011,949 page fixes (32.8%) are the aggregation's; PostgreSQL's aggregation performs zero shared-buffer accesses.** CUBRID's join subtree alone (680,258 fixes) is within 0.6% of PostgreSQL's entire total | **same stage, lower measured cost** |
| Per-row heap record access decodes an MVCC header on a table with one version per row | `src/storage/heap_file.c` via `heap_prepare_get_context` 1.71% → `heap_get_visible_version_internal` 0.38% → `or_mvcc_get_repid_and_flags` 3.86% + `or_mvcc_get_header` 0.58%, with `spage_get_record` 4.62% and `heap_attrinfo_read_dbvalues` 4.32% | `src/backend/access/heap/heapam.c` `heap_hot_search_buffer` 6.01% + `HeapTupleSatisfiesVisibility` 0.57%, plus `heap_page_prune_opt` 7.56% whose own cost is 9.16% kernel page-fault | 15.92% vs 15.15% — **near parity**, on 323,920 heap lookups per join copy on both sides. Recorded so the band is not later mistaken for a differentiator | **common to both engines** |
| Aggregate accumulation performs a generalized per-row NUMERIC multiply and add | `src/query/numeric_opfunc.c` `float_numeric_db_value_mul` 3.17% / `float_numeric_db_value_add` 1.06%, `src/query/query_opfunc.c` `qdata_multiply_dbval` 0.48% / `qdata_add_dbval` 0.61%, `qdata_evaluate_aggregate_list` 1.30% (already registered as IMP-001) | `src/backend/utils/adt/numeric.c` `make_result_safe` 2.05%, `init_var_from_num` 1.46%, `mul_var` 1.07%, `accum_sum_add` 0.64%, `numeric_mul_safe` 0.62%, `do_numeric_accum` 0.42% | 7.26% vs 6.99% = **1.039x — parity**. Q11 does **not** reproduce Q01's 2.949x per-row NUMERIC gap, and is recorded as the query that bounds IMP-001's generality | **common to both engines** |

**Absence claims are recorded with what was searched.** For "PostgreSQL has no per-session
buffer budget": searched `src/backend/storage/buffer/freelist.c` in full (all of
`StrategyGetBuffer`, `ClockSweepTick`, `StrategySyncStart`, `GetAccessStrategy`,
`GetAccessStrategyWithSize`, `GetAccessStrategyBufferCount`, `GetAccessStrategyPinLimit`,
`GetBufferFromRing`, `AddBufferToRing`, `StrategyRejectBuffer`) and
`src/backend/storage/buffer/bufmgr.c` for the patterns `strategy`, `quota`, `private`,
`per-backend`, `session`, `ring_size`; the only bounded window is the opt-in
`BufferAccessStrategy` ring, and the only per-backend structure is
`PrivateRefCountEntry`, which is a pin bookkeeping array and not a residency budget. For "no
existing CUBRID candidate touches the private-LRU quota": grepped every `cubrid_source`
entry of IMP-001..IMP-017 in `reports/improvement-registry.json` for
`PGBUF_PRIVATE_LRU_MAX_HARD_QUOTA`, `MIN_PRIVATE_RATIO`, `private_pages_ratio`,
`should_move_private_to_shared`, `PGBUF_FIX_COUNT_THRESHOLD`, `pgbuf_bcb_is_hot` and
`hard quota` — **zero hits on all seven**; `private_lru` hits only IMP-002 and IMP-010, whose
mechanisms are separated in §5-e and in `q11-registry-dedup.txt`.

## 8. Causal decomposition details

### 8-a. What actually happens, in order (saturated state)

1. CUBRID's optimizer costs the index-NL chain at **6,892** and estimates the final
   cardinality at **320,000 against a true 323,920 (0.9879x)**. It picks
   `nation sscan → supplier iscan(fk_supplier_nation) → partsupp iscan(fk_partsupp_supplier)`.
   PostgreSQL picks the **same** chain with the **same** indexes and the **same** probe
   counts (`Index Searches: 1` then `Index Searches: 4049`). There is no join-shape
   disagreement to measure.
2. That chain costs CUBRID **593 ms** and PostgreSQL **508 ms** — a 1.17x difference on the
   part of the query where the two engines agree.
3. CUBRID then materialises the 323,920-row join result into a temp list file and re-reads it
   for the group-by; PostgreSQL passes slots by reference. This is the origin of **331,691 of
   CUBRID's 1,011,949 page fixes (32.8%)**, against **zero** shared-buffer accesses from
   PostgreSQL's aggregation.
4. CUBRID's `GROUP BY` was marked hash-eligible at plan time, and at run time
   `qexec_hash_gby_agg_tuple` computed `group_count/tuple_count > 0.5f` and set
   `HS_REJECT_ALL`, which the trace prints as `hash: partial`. **On Q11 that decision is
   correct**: the measured ratio is **1.000000** on the first 2,000 tuples, 1.000000 at
   5,040, 1.000000 at 20,000, 0.968610 at 200,000 and **0.940893** over the whole input
   (`q11-selectivity.txt`, identical on both engines). CUBRID falls back to a sort, which
   takes **313 ms** for 323,920 rows through 1,516 pages.
5. PostgreSQL reaches the **opposite** strategic conclusion and hashes: `HashAggregate` with
   16 planned partitions, 17 batches, 8,337 kB resident and **15,064 kB spilled**, costing
   **~200 ms** plus 6.80% of its profile in kernel temp-file mapping. Forcing it onto
   CUBRID's sort makes it **1.0787x faster**, so PostgreSQL's cost model is the one that is
   wrong here.
6. CUBRID then runs the `HAVING` threshold as `SUBQUERY (uncorrelated)` — a structurally
   identical second copy of the whole join — on **one thread**, for **619 ms**.
   PostgreSQL runs the same subquery as an `InitPlan` under a `Gather` with **1 worker
   launched**, for **237 ms**. That worker is PostgreSQL's only parallel unit, it is worth a
   measured **1.091149x** to PostgreSQL, and it is the entirety of `F_units` 1.235944x.
7. Both engines sort 8,685 rows and return them: CUBRID 7 ms, PostgreSQL 4 ms.

### 8-b. Where the 1.68x actually goes

Two decompositions, both exact, on disjoint evidence:

```text
by unit parity (anchor C)
  1.681443x  = 1.091149x [PostgreSQL's single InitPlan worker]
             × 1.540984x [the remaining serial-vs-serial gap]

by work event (native pair)
  1.358179x [CPU] = 1.496357x [page fixes] × 0.907657x [CPU per page fix]
  1.681443x [wall] = 1.238013x [units] × 1.358179x [CPU]
```

and the page-fix count itself decomposes structurally:

| | fixes | share of `W_C` | PostgreSQL counterpart |
|---|---|---|---|
| join subtree, first copy | 340,127 | 33.6% | 337,946 |
| join subtree, second copy (the `HAVING` subquery) | 340,131 | 33.6% | 338,326 |
| aggregation list-file + sort pages | **331,691** | **32.8%** | **0** |
| `W_C` total | 1,011,949 | | 676,275 |

CUBRID's two join copies together (680,258) are within **0.6%** of PostgreSQL's *entire*
buffer traffic. **The whole of `F_work` is the aggregation's list-file round trip** — IMP-006
— and `F_work` is, after `F_units`, the whole of the gap.

### 8-c. Explanations considered and REJECTED, with the number that rejected each

| Rejected explanation | Rejected by |
|---|---|
| "CUBRID chose the wrong plan" | The join subtree is node-for-node, index-for-index and probe-count-for-probe-count **identical** on both engines (`Index Searches: 1` then `4049` on each side). The only differing decision is the aggregation strategy, and **PostgreSQL's is the wrong one**: `enable_hashagg=off` makes PostgreSQL **1.0787x faster** (0.798124 → 0.739912 s), so anchor A's `F_plan` is **0.927064x**, below 1. |
| "the working set does not fit CUBRID's 8 GiB buffer" (IMP-002's premise) | The set is ~97,400 pages of 524,288 = **18.6%** of the pool, and the saturated state takes **0** reads, 0 device `read_bytes` and 96 read syscalls per statement. It fits 5.4x over. |
| "then the misses are unavoidable and CUBRID is just slower" | 566,103 → **0** reads per statement on the **same plan with the same 1,012,000 page fixes**, achieved with no parameter change, no restart and no query change — only more connections. |
| "the decay is just the query getting warmer with more statements" | **120 statements on ONE connection are flat**: 2.450–2.521 s, half-split trend −0.16%, syscr 193k–210k. Five *connections* move it from 49,292 to 135 reads. The variable is connections, not statements. |
| "CUBRID's serial group-by sort is the tail" (IMP-015) | `/*+ NO_HASH_AGGREGATE */` measures **1.340000 s against 1.342000 s** — `F_plan` 1.001493x, inside the 1.28% band — with an identical plan tree (cost 9752), an identical page-fix count (1,011,949) and identical result rows. The variant's trace still shows no `parallel workers` on `GROUPBY`: at **1,516** sort pages (Q10 had 75,893) `compute_parallel_degree` returns 1 with or without the veto. |
| "the 0.5f hash-aggregate abort fired wrongly again" (IMP-016) | Measured true selectivity **1.000000 / 1.000000 / 1.000000 / 0.968610 / 0.940893** over the input prefixes, identical on both engines. `HS_REJECT_ALL` is **correct** on Q11. |
| "`max_agg_hash_size` is the constraint" (IMP-017) | Hash aggregation is abandoned on the **first** evaluation of a ratio that is exactly 1.000000, so the eviction loop that the frozen-`static` defect lives in never runs. |
| "CUBRID's buffer manager is more expensive per page" (IMP-013) | With zero misses on **both** sides the buffer bands are CUBRID **24.13%** vs PostgreSQL **23.72%** — equal to 1.017x — and per page fix CUBRID spends **1339.0 ns** of total query CPU against PostgreSQL's **1475.2 ns**, i.e. **1.1017x cheaper**. This required correcting the flat profile: `hash_search_with_hash_value` 12.73% is `BufTableLookup`, not the `HashAggregate` (§6-b). |
| "it is a memory-stall / cache-locality difference" | **CUBRID's IPC is 1.65 against PostgreSQL's 1.39** — CUBRID stalls *less*. The gap is 1.4988x the instructions, matching `F_work` 1.496357x to 0.16%. |
| "CUBRID's parallel-scan degree saturates below the cap" (IMP-012) | Q11 launches **no** parallel units at all (`U` 1.00965, TWU 0.9975, no `parallel workers` sub-line anywhere), so the SCAN auto-degree formula is never evaluated. The driving scan is a 1-page `nation` heap scan. |
| "the parallel-worker private-LRU bypass explains the misses" (IMP-010) | Same reason: Q11 has no parallel workers, so `private_lru_index = -1` never occurs. Q11's pages **do** reach the private list correctly — the list is simply capped at 5,000. |
| "the NUMERIC accumulator is the cost" (IMP-001) | 7.26% vs 6.99% of profiled self cost — **parity at 1.039x** — on 2 × 323,920 multiply-and-add per statement. |
| "the trace's row counters are inflated, so `F_work` is wrong" (IMP-005) | Every Q11 trace counter is **exact** against ground truth both engines answer identically: partsupp `rows: 323920` = G3, supplier `rows: 4049` = G2, `GROUPBY rows: 8685` = G5, nation `readrows: 25` = 25. Q11 is depth 3, the depth at which Q08/Q10 saw ~2x inflation, and shows none — because it runs no parallel scan units, which sharpens IMP-005 from "depth" to "parallel scan trace merging". |
| "the multi-column FK selectivity product mis-estimates the join" (IMP-014) | Q11's only FK indexes in play, `fk_supplier_nation` and `fk_partsupp_supplier`, are single-column, so no product is formed. Final cardinality estimate 320,000 vs a true 323,920 = **0.9879x**. |

### 8-d. What is left after IMP-018, and in what order

Assume IMP-018 is fixed and Q11 starts at its saturated 1.342 s on the first connection.
The remaining 1.68x, attributed by measurement and non-overlapping:

- **`F_units` 1.238013x** — PostgreSQL's single InitPlan worker, worth a measured
  **1.091149x** to PostgreSQL by direct A/B. On the CUBRID side this is **IMP-009**
  (`compute_parallel_degree()`'s `case parallel_type::SUBQUERY` degree-1 hardcode) applied to
  a node that is **619 ms of a 1,532 ms statement**. This is a projection for CUBRID, not a
  CUBRID A/B; IMP-009's direct CUBRID A/B remains Q05's.
- **`F_work` 1.496357x**, of which **32.8% of all CUBRID page fixes** are the aggregation's
  temp list-file round trip against PostgreSQL's zero — **IMP-006**, and Q11 is its sharpest
  measurement.
- **`F_cost` 0.907657x** — a CUBRID *advantage* of 1.1017x per page fix. Nothing to fix, and
  a regression control for any buffer-manager change.
- **anchor A's `F_plan` 0.927064x** — a CUBRID *advantage* of 1.0787x in aggregation-strategy
  choice. Nothing to fix, and a regression control for any plan-cost change (IMP-011).
- **near-parity bands that are recorded so they are not later mistaken for causes**: heap
  record access 15.92% vs 15.15%, NUMERIC arithmetic 7.26% vs 6.99%.

Summed, the two candidates that survive (IMP-009 via `F_units`, IMP-006 via `F_work`)
multiply to `1.091149 × 1.496357 = 1.632`, against a total gap of 1.681443x — i.e. they
account for **97.1%** of it. That is an **attribution built from one executed A/B (anchor C)
and one exact counter ratio (page fixes)**, not a prediction of what fixing either would
yield, and no part of it is summed with `F_plan`: the three anchors are measured on disjoint
configurations.

## 9. Improvements

Registry synced from `origin/main` at HEAD `6c86974` and searched by title / CUBRID source
location / PostgreSQL source location / root cause before allocating
(`q11-registry-dedup.txt`, which records all seven negative pattern searches and the
numbers that separate the new candidate from IMP-002 and IMP-010). Ledger went from 17
candidates (`next_id IMP-018`) to **18** (`next_id IMP-019`).

### New candidate

| Rank | ID | P | Category | Root cause (one line) | Measured effect |
|---|---|---|---|---|---|
| **1** | **IMP-018** | **P0** | buffer/IO | A single session can retain only `PGBUF_PRIVATE_LRU_MAX_HARD_QUOTA = 5000` buffer pages regardless of `data_buffer_size`, because every page it reads goes on that session's private LRU list and escapes into the shared pool only when a *different* session touches it or it reaches 64 fixes while resident | **direct A/B 2.6408x** (3.544000 → 1.342000 s); reads/statement 566,103 → 0; `fetch_time` 2,061 → 326 ms of a 3,360 → 1,532 ms statement (**94.9%** of the recovery); page-fix count **invariant** at 1,012,042 → 1,011,949 (0.01%); `Num_data_page_private_count` pinned at 5,002 while it lasts, `Num_data_page_lru1` 15,092 → 97,369 when it ends. Difficulty **low** — one constant plus one clamp |

Ranking justification: IMP-018 is the only new candidate, and it is ranked above every
existing candidate Q11 touches because the measured bands say so — 2.6408x by direct A/B
against IMP-006's 32.8% of the remaining page fixes and IMP-009's 619 ms of 1,532 ms. Every
rejected sibling explanation and the number that rejected it is in §8-c and is duplicated
into the candidate's `ranking_rationale`. The candidate records its own limitation
explicitly: on this pool size the hard cap (5,000) and the `MIN_PRIVATE_RATIO` floor
(0.01 × 524,288 = 5,242) coincide within 9%, so **the measurement cannot separate them and
both must be changed**; and it records the many-session regression risk that the adaptive
quota exists to prevent, with a concurrency control in its validation criteria.

`IMP-018` is `status: measured`. It is **not** `validated`: that requires correctness
evidence for an *implemented* change, and nothing was implemented.

### Existing candidates given a Q11 relation and Q11 evidence (no new ID)

| ID | Q11 contribution |
|---|---|
| IMP-002 | Bounds this candidate's symptom from above and separates it from IMP-018: 566,103 reads/statement on a working set that is **18.6% of the pool**, so the "working set exceeds the pool" premise is absent. Also refutes Q05's "equilibrium it cannot leave without a server restart" — 20 further connections leave it, no restart. |
| IMP-005 | **Negative control**, and it sharpens the candidate. Every Q11 trace counter is exact against ground truth (partsupp 323,920 = G3, supplier 4,049 = G2, `GROUPBY` 8,685 = G5) at scan depth 3 — the depth at which Q08/Q10 saw ~2x inflation. Q11 runs no parallel scan units, so the defect is a property of **parallel** scan trace merging, not of nesting depth. |
| IMP-006 | **Sharpest measurement to date.** 331,691 of CUBRID's 1,011,949 page fixes (**32.8%**) are the aggregation's temp list-file write + re-read and its sort pages, against **0** shared-buffer accesses from PostgreSQL's aggregation (its spill is `temp read=1330 written=3103`, outside the buffer manager). CUBRID's two join copies alone (680,258) are within 0.6% of PostgreSQL's entire total. Since `F_cpu` decomposes exactly as `F_work` (page fixes) × `F_cost` and `F_cost` **favours CUBRID**, this candidate owns essentially all of Q11's CPU factor. |
| IMP-007 | The clearest measurement of what each miss costs, because the miss count varies 566,103 → 0 with everything else fixed: 2,061 ms of a 3,360 ms statement in `fetch_time`, 551,116 read syscalls moving 8.406 GiB at exactly 16,384 bytes each with device `read_bytes` = 0 — i.e. ~3.7 µs per synchronous single-page `pread` on the query thread. In the saturated state the kernel page-cache band is **0.00%**. This **orders** the two candidates: on Q11, removing the reads (IMP-018) dominates making them cheaper (IMP-007), whose remaining Q11 value is zero. |
| IMP-009 | **Direct structural instance and the second-largest Q11 factor.** The `HAVING` threshold is `SUBQUERY (uncorrelated) → SELECT (time: 619, fetch: 340131, ioread: 0)` with **no** worker — 619 ms of a 1,532 ms statement (40.4%). PostgreSQL runs the identical subquery as `InitPlan → Gather (Workers Launched: 1)` in 237 ms, and that single worker is worth a measured **1.091149x** to PostgreSQL and is the whole of `F_units` 1.238013x. On equal (serial) units CUBRID loses 1.540984x instead of 1.681443x. Projection for the CUBRID side; IMP-009's direct CUBRID A/B remains Q05's. |
| IMP-011 | **Negative control in CUBRID's favour, and a regression control.** The one plan decision the optimizers make differently is the aggregation strategy, and PostgreSQL's is wrong: `enable_hashagg=off` makes PostgreSQL **1.0787x faster**, so `F_plan` on that anchor is **0.927064x**, below 1. Any future IMP-011 work must keep Q11 as a regression control — there is nothing to gain and 7.9% to lose. |
| IMP-013 | **REFUTED on Q11**, under the best possible conditions for it: zero physical reads on **both** engines, so the bands are pure hit-path cost. CUBRID 24.13% vs PostgreSQL 23.72% (equal to 1.017x), and per page fix CUBRID spends **1339.0 ns** against PostgreSQL's **1475.2 ns** — **1.1017x cheaper** — at IPC 1.65 vs 1.39. Required correcting the flat-profile reading: `hash_search_with_hash_value` 12.73% is `BufTableLookup`, not the `HashAggregate` (§6-b). Q11 bounds the claim rather than contradicting Q08/Q09/Q10, and is added as a regression control. |
| IMP-015 | **Negative control by executed A/B.** `hash: partial` is present, so the veto **is** armed, yet `/*+ NO_HASH_AGGREGATE */` measures 1.340000 s vs 1.342000 s (`F_plan` 1.001493x, inside the band) with an identical plan tree, an identical page-fix count and identical rows, and no `parallel workers` on `GROUPBY` in either case. At 1,516 sort pages (Q10: 75,893) the sort is too small for `compute_parallel_degree` to exceed 1. The veto costs nothing unless the fallback sort would have been parallelised. |
| IMP-016 | **Negative control, and the most informative one this candidate has.** `HS_REJECT_ALL` also fired here, and here it is **correct**: measured selectivity 1.000000 / 1.000000 / 1.000000 / 0.968610 / 0.940893 over the input prefixes, identical on both engines. So the 0.5f test is not wrong as a rule, and the candidate's claim must stay narrowly on the undecremented `group_count`. Q11 is the control a fix must not flip. |
| IMP-001 | **Near-parity control.** NUMERIC band CUBRID 7.26% vs PostgreSQL 6.99% (1.039x) on 2 × 323,920 multiply-and-add. Q11 does not reproduce Q01's 2.949x per-row gap and bounds IMP-001's generality across aggregate shapes. No effect claim from Q11. |

No Q11 relation was added to IMP-003 or IMP-004 (no `LIKE`), IMP-008 (Q11's only sarg is
`n_name='GERMANY'` on a 25-row table; `eval_data_filter` and
`tp_value_compare_with_error` are both below the 0.3% profile cut), IMP-010 or IMP-012 (no
parallel units at all), IMP-014 (single-column FK indexes; cardinality estimate 0.9879x of
truth) or IMP-017 (the eviction loop never runs) — each with the rejecting number recorded in
`q11-registry-dedup.txt` and §8-c.

## 10. Evidence index

Format: `claim → raw file:line → formula → evidence type → SHA-256`. Raw root
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q11`; sizes and SHA-256 for all **363**
promoted artifacts are in `raw-manifest.json`, which is the authoritative checksum list and
which carries an explicit `invalid_reason` on the **25** artifacts that are preserved as
evidence but excluded from the reported numbers. The entries below give the pointer and the
derivation.

| # | Claim | Raw pointer | Formula | Evidence type |
|---|---|---|---|---|
| 1 | CUBRID headline median 1.342000 s | `Q11-cubrid-headline-block3.json` → `measured_times_s` | median of 3 measured | direct measurement |
| 2 | PostgreSQL headline median 0.798124 s | `Q11-postgresql-headline-block3.json` | median of 3 measured | direct measurement |
| 3 | `R_wall` 1.681443x | both above | `1.342000 / 0.798124` | direct measurement |
| 4 | blocks 1–3 series 3.544 / 2.258 / 1.342 s vs PostgreSQL 0.799853 / 0.800342 / 0.798124 s | `Q11-{cubrid,postgresql}-headline-block{1,2,3}.json` | per-block median of 3 | direct measurement |
| 5 | the decay is **connection**-driven, not statement-driven | `q11-conn-probe.txt` (60 connections × 4) vs `q11-drift-probe-cubrid.txt` (1 connection × 120) and `q11-conn-probe.txt` probe B (1 connection × 60) | reads/statement and median per connection vs per statement | direct A/B |
| 6 | reads/statement 566,103 → 0 with the page-fix count invariant | `q11-trace-cubrid.out`, `q11-trace-cubrid-asymptote.out`, `q11-trace-cubrid-saturated.out` | trace `fetch` / `ioread` / `fetch_time` per statement | direct A/B |
| 7 | 94.9% of the recovery is `fetch_time` | same three traces | `(2061−326)/(3360−1532)` | direct A/B |
| 8 | reads are OS page-cache copies, never device reads | `Q11-cubrid-read-decay.json`, `Q11-cubrid-buffer-io-diag.json` | `/proc/<pid>/io` `syscr`/`rchar` deltas at 16,384 B per read with `read_bytes` delta 0 | direct measurement |
| 9 | the retention window is ~5,000 pages | `q11-conn-probe.txt`, `Q11-cubrid-headline-block3.json` `buffer_counters` | `Num_data_page_private_count` 5,002/5,003 vs `PGBUF_PRIVATE_LRU_MAX_HARD_QUOTA` 5000 and `Num_data_page_private_quota` 5,242 = 0.01 × 524,288 | direct measurement + source |
| 10 | the working set migrates into the shared pool | `q11-conn-probe.txt` | `Num_data_page_lru1` 15,092 → 82,352 → 97,369; `private_count` 5,002 → 1,638 | direct measurement |
| 11 | PostgreSQL is invariant over the same interval | `q11-plan-act-pg.out`, `q11-plan-act-pg-asymptote.out`, `q11-plan-act-pg-saturated.out`, `Q11-postgresql-buffer-io-diag.json` | `shared hit=676275 read=0` and Execution Time 1079.898 / 1080.016 ms; `heap_blks_read` delta 0 | direct measurement |
| 12 | `F_plan` anchor B = 1.001493x (**null**) | `Q11-cubrid-headline-block3.json`, `Q11-cubrid-nohashagg-headline.json` | `1.342000 / 1.340000` | direct A/B (null result) |
| 13 | anchor B's plan tree and fix count are identical | `q11-plan-est-cubrid.out` vs `variants/plan-cubrid-NO_HASH_AGGREGATE.out`; `q11-trace-cubrid-saturated.out` vs `variants/trace-cubrid-NO_HASH_AGGREGATE.out` | cost 9752 both; `fetch: 1011949` both; `hash: partial` → `hash: false` | direct A/B |
| 14 | `F_plan` anchor A = 0.927064x (PostgreSQL's own choice is worse) | `Q11-postgresql-groupagg-headline.json`, `variants/plan-act-pg-groupagg.out` | `0.739912 / 0.798124`; `Batches: 17, Disk Usage 15064kB` → `external merge Disk: 8248kB` | direct A/B |
| 15 | `F_plan` anchor C = 1.091149x (PostgreSQL's only worker) | `Q11-postgresql-noparallel-headline.json`, `variants/plan-act-pg-noparallel.out` | `0.870872 / 0.798124`; `Gather (Workers Launched: 1)` → plain `Aggregate` | direct A/B |
| 16 | `U`/TWU/`F_units`/`F_cpu`, residual ±0.000000% on all three anchors | `q11-card-calc.txt`, `Q11-causal-card.json`, `Q11-*-headline-telemetry-run{7,8,9}.json` | see §3-a formulas | profile attribution |
| 17 | `F_work` 1.496357x, `F_cost` 0.907657x | `q11-trace-cubrid-saturated.out` (`fetch: 1011949`), `q11-plan-act-pg-saturated.out` (`shared hit=676275`), `q11-card-calc.txt` | `W_C/W_P`; `(CPU_C/W_C)/(CPU_P/W_P)` | direct A/B (counts) + profile attribution (CPU) |
| 18 | the aggregation is 32.8% of CUBRID's page fixes and 0% of PostgreSQL's | `q11-trace-cubrid-saturated.out`, `q11-plan-act-pg-saturated.out` | `(1,011,949 − 680,258)/1,011,949`; PostgreSQL `temp read=1330 written=3103` with `shared hit` unchanged | direct A/B |
| 19 | cardinality chain identical on both engines | `q11-groundtruth-cubrid.out`, `q11-groundtruth-pg.out` | 11 rows compared, incl. G3 323,920, G4 304,774, G5 8,685, threshold 8102913.765246800000 | direct A/B |
| 20 | group-by selectivity 1.000000 … 0.940893, so `HS_REJECT_ALL` is correct | `q11-selectivity.txt`, `q11-selectivity-probe-{cubrid,pg}.out` | `groups/tuples` per input prefix | direct A/B |
| 21 | profile bands, 0 unresolved lines both engines | `profile-cubrid-flat.txt`, `profile-pg-flat.txt`, `q11-profile-bands.txt` | self-% summed per band | profile attribution |
| 22 | `hash_search_with_hash_value` is `BufTableLookup`, not the `HashAggregate` | `profile-pg-callgraph.txt` | 13.41% of 13.62% inclusive via `StartReadBuffer → PinBufferForBlock → BufferAlloc → BufTableLookup` | profile attribution |
| 23 | buffer bands equal, CUBRID cheaper per fix | `q11-profile-bands.txt`, `q11-card-calc.txt` | 24.13% vs 23.72%; 1339.0 ns vs 1475.2 ns per fix | profile attribution |
| 24 | IPC 1.65 vs 1.39, instructions/statement 6.343 G vs 4.232 G | `perf-stat-cubrid.txt`, `perf-stat-pg.txt` | `instructions / (window / median_wall)` | direct measurement |
| 25 | context switches 1.334 K/s vs 8.75/s | same two files | `context-switches / seconds elapsed` | direct measurement |
| 26 | CUBRID runs Q11 with zero parallel units | `q11-trace-cubrid-saturated.out`, `Q11-cubrid-headline-telemetry-run{7,8,9}.json` | no `parallel workers` sub-line; `U` 1.00965, TWU 0.9975, peak 1.1400 | direct measurement |
| 27 | WARM gate parameters derived by measurement (`WINDOW=6`) | `q11-warm-gate-params.txt`, `q11-convergence-{cubrid,pg}.json` | monotone-window rate 5/36 and 7/36 at W=4 vs 2/34 and 1/34 at W=6 | direct measurement |
| 28 | pre/post-block gates PASS, `ssot_drift=NONE` | `preflight-Q11.txt`, `q11-postcheck.txt` | see §1 | direct measurement |
| 29 | correctness: 8,685 ordered rows, and the two engines' rows are byte-identical | `q11-correctness.json`, `q11-variant-equivalence.txt` | SSOT §11 comparator; SHA-256 `66148d0c…` on both engines' extracted rows | direct A/B |
| 30 | the `enable_hashagg=off` difference is a tie transposition, not a mismatch | `q11-variant-equivalence.txt` | 2 of 8,685 positions, both value `8576064.00`; multiset and value sequence identical | direct A/B |
| 31 | CUBRID `statdump` data-page counters unusable, gauges usable | `q11-cubrid-statdump-{pre,mid,post}.txt`, `Q11-cubrid-buffer-io-diag.json` | counter delta exactly 0 against 1,012,000 traced fetches/statement; LRU and private gauges do track | direct measurement (negative) |

## 11. Notion sync

This report was produced by the GJC/tmux worker session on the remote measurement host, which
has **no Notion connector**. Per SSOT §21 (Execution boundary) its Notion-adjacent duty ends
at committing and pushing this report, `raw-manifest.json` and the improvement registry to
`origin/main`; it must never attempt a Notion write.

Write path used: **path 3 of 3** — an idempotent record appended to
`reports/notion_backfill_pending.jsonl`, keyed by
`campaign_id + QNN + session_id + report_commit + content_fingerprint`. The Notion
operational-state update, the Q01–Q22 database row for Q11, the new improvement-registry page
for **IMP-018** and the ten updated pages (IMP-001, 002, 005, 006, 007, 009, 011, 013, 015,
016) must be performed by a dedicated subagent with Notion tool access, reading the pushed
GitHub commit as source of truth, and the pending record cleared only after a server-side
refetch.

Fields the mirror must carry are the same field names used above: QNN and status; campaign ID
and `ssot_commit`; exact GJC session ID; correctness/censoring; CUBRID seconds, PostgreSQL
seconds and ratio; causal multiplier summary; report commit and raw manifest link;
improvement relations; content fingerprint and last verified timestamp. Per §21's
content-richness rule the page body must mirror §3-a's factor table **and all three anchors**,
§3-b's headline timings **including the three-block series**, §4-c's plan comparison, §5-e's
retention-decay finding (which is the query's headline result), §6's top-cost symbols for both
engines **including the `BufTableLookup` correction**, §7's full `file:line` contrast, §8's
narrative **including 8-c's rejected explanations and the numbers that rejected them**, and
every candidate in §9 — with the negative controls stated as negative controls, since five of
this query's ten existing-candidate relations are refutations rather than confirmations.

## 12. Completion checklist

| SSOT §26 gate | Status |
|---|---|
| preflight and correctness status recorded | **yes** — `preflight-Q11.txt` all gates PASS, `ssot_drift=NONE`; `q11-correctness.json` `result-equivalent-at-SF10`, 8,685 rows ordered |
| three valid headline values for each completing engine | **yes** — CUBRID 1.342 / 1.340 / 1.346; PostgreSQL 0.798124 / 0.795354 / 0.805589; both blocks accepted on attempt 1 with `load_verdict=CLEAN` under the strict per-sample rule, both WARM gates `CONVERGED`, both taken in the proven saturated buffer state (§5-e) |
| timeout confirmations if censored | **n/a** — no timeout; max statement 3.563 s against a 300 s limit |
| plan section complete | **yes** — estimated (both engines, non-executing), actual (`EXPLAIN ANALYZE` + CUBRID `SET TRACE ON`) captured at **three** points of the buffer-migration curve, plus 3 controlled variants with their own plans and traces |
| execution telemetry complete | **yes** — node-level time both engines, CPU split executor/auxiliary, worker counts, `U`/TWU/peak/tail over 9 telemetry runs per engine, `/proc` I/O, iostat, `/proc/diskstats`, NUMA, buffer counters (with the `statdump` counters explicitly excluded and the gauges explicitly used) |
| profile complete | **yes** — verified PID sets, `perf stat` + call graph, 0 unknown-symbol lines both engines, banded, taken in the zero-miss state; one flat-profile misattribution found and corrected against the call graph (§6-b) |
| source contrast complete | **yes** — 8 rows, `file:line` on both sides, classes assigned, absence claims record searched paths/symbols/patterns |
| causal multiplier card has evidence or explicit `UNMEASURED` | **yes** — every factor numeric with a named controlled A/B; **no `UNMEASURED` factors**; three anchors, residual ±0.000000% on each; error budget stated before interpretation and the one factor inside the band (anchor B's `F_plan` 1.001493x) reported as a **null result** rather than an effect |
| Git improvement ledger deduplicated and committed | **yes** — `q11-registry-dedup.txt`; 1 new ID IMP-018, 10 reuses of which 5 are refutations, `next_id IMP-019` |
| Notion relations synced **or** idempotent backfill durable | **backfill record** — write path 3, per §21's execution boundary (this session has no connector) |
| every claim indexed to raw evidence and checksum | **yes** — §10 index; `raw-manifest.json` carries size + SHA-256 + creation command + stage + validity for all 363 promoted files |
| report, manifest and registry committed, pushed, reachable from `origin/main` | see `report_commit` in the status block |
| `QUERY_COMPLETE` emitted | see the status block |
| current session removed and absence verified | **owed by the controller** — a session cannot remove itself; both checks (`gjc session status <id>` and `tmux has-session -t <id>`) are the transition owner's step |

### Invalid / superseded artifacts, preserved as evidence

| Artifact | Reason |
|---|---|
| `Q11-cubrid-headline-block1.json` (+ its `warm`/`bgload` block copies) | **SUPERSEDED, not a headline value.** Internally WARM-`CONVERGED` and load-`CLEAN`, but taken at 566,103 reads/statement while the working set was still trapped in the 5,000-page private-LRU window: median 3.544000 s against the saturated 1.342000 s. Retained as the direct A/B evidence for IMP-018 |
| `Q11-cubrid-headline-block2.json` (+ copies) | same, at ~207,600 reads/statement: median 2.258000 s |
| `Q11-postgresql-headline-block{1,2}.json` | superseded **for symmetry only**; PostgreSQL's three block medians span 0.06% and every `EXPLAIN` reports `shared hit=676275 read=0` |
| `Q11-cubrid-headline-telemetry-run{1..6}.json` | **not used for the causal card**: taken on the migration curve (block medians 3.263 / 3.031 / 2.821 / 2.053 / 1.907 / 1.685 s). Retained as the decay evidence. The card uses saturated runs 7–9 |
| `Q11-postgresql-headline-telemetry-run{1..6}.json` | not used for the card, for symmetry with the CUBRID runs of the same index (PostgreSQL's own `U` over runs 1–9 spans 4.4%) |
| `q11-trace-cubrid.out`, `q11-plan-act-pg.out` | retained and **cited**, but as the *first* point of the migration curve rather than as the query's plan evidence; the saturated pair is what §4 and §5 analyse |
| `q11-cubrid-statdump-{pre,mid,post}.txt` | retained, but the five data-page **counters** they contain are excluded from every calculation (zero delta against a trace showing 1,012,000 page fetches per statement, re-confirmed on Q11 by a single-statement bracket). The LRU-zone and private-list **gauges** in the same files are cited and are load-bearing for IMP-018 |
| `q11-convergence-pg.json` | `converged: False` with verdict `monotone trailing window (still drifting)` on a series whose level is flat to 0.14% — the false negative that forced the `WINDOW=6` derivation. Retained as the evidence for `q11-warm-gate-params.txt` |
| `q11-retprobe-*.sql` | generated by an earlier draft of the retention sweep that was superseded by `conn_probe.sh` once the variable was identified as the connection rather than the page count; retained as stage input, not cited |

No run was excluded for `INVALID_BACKGROUND_LOAD`: every accepted block reported
`load_verdict=CLEAN` under the strict per-sample rule, with `external_max` between 0.4541 and
0.8359 core-s/s against the 6.0 threshold, and the pre/post external load was 0.312 / 0.268.
