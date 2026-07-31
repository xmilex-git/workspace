# TPCH-SSPQ FK campaign — Q07 report

## 3-a. Causal multiplier card

```text
R_wall 9.409348x [wall, median of 3 per engine; PostgreSQL is 9.4093x faster]
= F_plan  1.435536x [plan-shape; PostgreSQL-side controlled A/B, anchor named below]
× F_units 4.832349x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   1.356399x [total query CPU-seconds]

F_cpu 1.356399x  is the CONTROLLED pair's CPU factor. On the native pair the same
quantity is 1.537551x, and it decomposes as

F_cpu(native) 1.537551x [total query CPU-seconds]
= F_work 0.191700x [plan-node tuple touches: 15,218,469 vs 79,386,706]
× F_cost 8.020590x [total-query CPU-seconds per tuple touch: 1562 ns vs 195 ns]
```

**Read the card in one line: CUBRID chooses a plan that touches 5.2x fewer tuples than
PostgreSQL's, then runs it on exactly one thread — and the same CUBRID server executes
the plan it rejected 3.67x faster, at 7.20 active units.**

Q07 is the campaign's first query where **the dominant factor is a plan CHOICE that the
losing engine itself can beat**, so the card is built on two anchors and both are
reported.

`F_plan` is numeric by a **PostgreSQL-side controlled A/B**, direction stated
explicitly: *PostgreSQL native (`Parallel Hash Join` tree) → PostgreSQL controlled
(`enable_hashjoin=off, enable_mergejoin=off`, the index-nested-loop chain CUBRID chooses
natively)*. Forcing PostgreSQL onto CUBRID's shape costs PostgreSQL **1.4355x**
(3.618685 s vs 2.520791 s), so the shape is genuinely worse but explains only a seventh
of the gap. The remaining controlled cross-engine pair is (CUBRID native, PostgreSQL
controlled index-NL) and carries `F_units` and `F_cpu`; native and controlled
denominators are never mixed.

That pair is matched **node-for-node on the dominant path**: both drive
`customer → orders(fk_orders_customer) → lineitem(fk_lineitem_orders) → supplier(PK)`,
and both produce the identical intermediate cardinalities **120,469 / 1,205,808 /
4,819,158 → 1,463,770 / 58,365**, independently confirmed by ground-truth `count(*)`
queries that both engines answer identically (`q7-groundtruth-cubrid.out`,
`q7-groundtruth-pg.out`).

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 1.435536x | plan-node shape | same-engine controlled A/B on PostgreSQL | `T_P_idxnl/T_P_native` = 3.618685/2.520791 | `Q07-postgresql-idxnl-headline.json`, `Q07-postgresql-headline-blockh1.json`, `variants/plan-nestloop_forced.out` | direct A/B |
| `F_units` | 4.832349x | active execution units | CPU-seconds / wall-second over the section 12 block | `U_P_idxnl/U_C_native` = 4.84211/1.00202 | `Q07-postgresql-idxnl-headline-telemetry.json`, `Q07-cubrid-headline-telemetry-run2.json` | profile attribution |
| `F_cpu` | 1.356399x | total query CPU-seconds | per query execution | `CPU_C_native/CPU_P_idxnl` = 23.7669/17.5221 | same telemetry JSONs | profile attribution |
| `F_work` | 0.191700x | plan-node tuple touches | tuples | `W_C/W_P` = 15,218,469/79,386,706 | `q7-trace-cubrid.out`, `q7-plan-act-pg.out`, `q7-groundtruth-*.out` | direct A/B |
| `F_cost` | 8.020590x | CPU-seconds per tuple touch | tuple touches | `(CPU_C/W_C)/(CPU_P/W_P)` = 1562 ns / 195 ns | `Q07-causal-card.json`, `q7-card-calc.txt` | profile attribution |

**Second anchor, and it is the finding rather than a robustness note.** Anchoring on the
CUBRID side (*CUBRID native index-NL → CUBRID controlled `/*+ USE_HASH */`, i.e.
PostgreSQL's native shape*) gives

```text
9.409348x = 3.669400x [plan] × 0.852022x [units] × 3.009635x [CPU-sec]
```

which also reconstructs exactly. On its own hash-join plan **CUBRID reaches 7.19707
active units against PostgreSQL's 6.13206 — `F_units` = 0.852, i.e. CUBRID is the wider
of the two — and finishes in 6.464 s.** The plan CUBRID's optimizer actually picked is
**3.6694x slower than the plan the same server, same statistics, same 8-FK schema would
have run**, and it is the only one of the two that CUBRID cannot parallelize at all
(section 7 shows the line that blocks it). Q07's 9.41x is therefore predominantly an
optimizer-decision loss, not an execution-engine loss: had CUBRID chosen the hash plan
the gap would be **2.5643x** (6.464/2.520791).

**Reconstruction residual = 0.000000% on both anchors, and as in Q04–Q06 that is an
identity, not a prediction.** `CPU_stmt` is attributed as `U × t_median` with `U`
measured on the same block the wall is defined on, so `F_units × F_cpu = T_C/T_P` by
construction. Closure rests on the independent quantities:

- **`U` reproducibility.** CUBRID native 1.00282 / 1.00202 / 1.00109 across three
  independently gated telemetry runs (**0.17%** max–min); PostgreSQL native 6.10278 /
  6.13206 / 6.23458 (**2.16%**).
- **TWU**, from actual sample timestamp deltas over the busy window only: **1.0016**
  (CUBRID, **−0.04%** from `U`), **6.3049** (PostgreSQL, **+2.82%**, the discrepancy
  being the 0.123 s `Gather Merge` serial tail that TWU spans and `U` averages over),
  **4.8734** (PG index-NL, +0.65%), **7.1825** (CUBRID USE_HASH, −0.20%).
- **`perf stat` on verified PID sets**, a third instrument: **1.011 CPUs utilized** for
  CUBRID (**+0.90%** against `U` = 1.00202) and **5.785** for PostgreSQL's
  postmaster-inherited executor set (**−5.66%** against a total-query `U` of 6.13206
  that includes 5.80 core-s of io-worker/psql auxiliary CPU, which `perf stat` on the
  post-attach fork tree does not count).
- **Instructions and IPC**, a separate counter path: CUBRID **171.16 G instructions at
  IPC 1.07**, PostgreSQL **784.80 G at IPC 1.41** over their respective profile windows
  — PostgreSQL executes 4.6x the instructions at 1.32x the IPC, which is the
  quantitative form of "it scans 60 M rows while CUBRID probes 15 M tuples".

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q07 |
| SSOT commit (final pin) | `10ee29b0270b1e86dc72b4de5db44792622b2254` |
| SSOT blob (final pin) | `5104788` (`510478846bff081d3223d3835069283a7cd2e47b`) |
| SSOT commits this query was pinned to, in order | `d19dca41…` (creation) → `f60fe90…` (operator threshold decision) → `10ee29b…` (tmux-driver pattern) |
| GJC session ID | `gajae_code_ms85runy_ajpvyez5` |
| Child tmux driver sessions (section 22/24) | `q7cub`, `q7pg`, `q7tel`, `q7var`, `q7perf` — all removed after their driver logs were consumed |
| Raw dir | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q07` |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` |
| CUBRID DB / port | `tpch_sf10_q1` / 1523 (`cub_server` pid 1612732, `cub_master` pid 1433697) |
| PostgreSQL PGDATA / port | `/home/cubrid/pg/pgdata-tpch-sspq` / 5442 (postmaster pid 1433696) |

Both running binaries hash-match the frozen `reports/bootstrap/build-manifest.json`. **No
server was started, stopped or restarted during Q07** — both engines ran on the processes
that survived Q06, so no start-time identity re-verification was required and none is
claimed. Ownership gates (section 10) classified **OK** before (`preflight-Q07.txt`) and
after (`q7-postcheck.txt`) the measurement blocks; the post-block gate records **0 orphan
`csql`, 0 orphan `psql`, 0 parallel workers, 0 client backends, 35 engine TIDs with 0
off-cpuset**, and the CUBRID pool conserved at exactly **524,288 pages** (8 GiB / 16 KiB).

**Two SSOT re-pins during Q07, recorded rather than glossed** (`q7-ssot-repin.txt`). The
session was created pinned to `d19dca41…`. Mid-query the operator raised section 9's
external-CPU quiet gate from 1.5 to 6.0 core-s/s (`f60fe90`, +6/−2 lines, entirely inside
section 9's CPU-and-memory block) and then codified the child-tmux-session pattern this
query had to invent (`10ee29b`, +5/−1 lines in sections 22 and 24). `git diff` confirms
**no other rule changed** — not engine SHA, schema, statistics, the parallel/buffer/
shared-memory contract, the timing regime, timeout, CPU accounting, the causal-card
definition, evidence rules or the report format — and each old pin is an ancestor of the
next. The threshold change only **raises** an acceptance bound, so nothing already
accepted was withdrawn; and because **no Q07 headline block had been accepted under the
old bound**, no headline value carries the old gate. Load-independent stages collected
before the re-pin (preflight, correctness, estimated plans, trace, `EXPLAIN ANALYZE`,
ground truth, level history, self-load root cause, load sensitivity) stand unchanged and
were not repeated. `SSOT_DRIFT = NONE_AFTER_REPIN`.

Local `main` had diverged from `origin/main` (the operator's harness sync was committed on
this host as `1c3319c`, the two SSOT edits were pushed from the control copy). The two
sides touch disjoint files — `harness/preflight_check.sh` + `harness/wait_quiet.py` versus
`SSOT.md` — so they were reconciled with a **merge** (`813b917`), never a rebase, reset,
force checkout or force push.

Query provenance: `queries/q7-cubrid.sql` byte-matches the canonical source
`/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q7.sql`, SHA-256
`44f650099eb082475c0ea9534f4271c3b82956d14b7c5b365ab7598cd63c82f6`. **Q07 is the
campaign's first query whose PostgreSQL dialect file is byte-identical to the CUBRID
file** — `queries/diff/q7.diff` is 0 bytes and `cmp` reports the two files identical — so
no dialect artifact can bias this comparison at all. The hinted CUBRID variant and the
`PGOPTIONS` PostgreSQL variants used as controlled anchors are separate diagnostic
artifacts under `variants/`, never measured dialect files.

Schema: 8 named FKs and 8 corresponding child B-trees verified on both engines with exact
child-column order; all PostgreSQL `pg_constraint.convalidated = true` (8/8/8). Row counts
exact-equal on both engines (`lineitem` 59,986,052, `orders` 15,000,000, `partsupp`
8,000,000, `part` 2,000,000, `customer` 1,500,000, `supplier` 100,000, `nation` 25,
`region` 5). **Q07 drives its entire CUBRID plan through three of the eight campaign FK
indexes** (`fk_customer_nation`, `fk_orders_customer`, `fk_lineitem_orders`) plus
`pk_supplier_s_suppkey`, while PostgreSQL uses none of them — the sharpest instance yet of
the FK indexes deciding one engine's plan and being ignored by the other.

Contract state at measurement time:

- statistics: CUBRID `update_statistics_update_histogram=y`,
  `default_histogram_bucket_count=300` (target). Actual per-column bucket count remains
  **UNMEASURED** (opaque serialized `VARBIT` in `_db_histogram`) — carried forward from
  bootstrap and Q01–Q06. PostgreSQL standard `ANALYZE`, `default_statistics_target=100`.
  **`pg_stat_all_tables.last_analyze` reads `never` for all eight tables**, which is not a
  statistics-contract violation but a collector artifact: Q06's IMP-010 work called
  `pg_stat_reset()` at 07:26. The statistics themselves are intact and were verified
  directly in `pg_statistic` — every Q07 column carries MCV (`stakind 1`) and/or histogram
  (`stakind 2`) plus correlation slots, e.g. `lineitem.l_shipdate` `stakinds=1,2,3`
  `ndistinct=2506`, `lineitem.l_suppkey` `stakinds=1,2,3` `ndistinct=98713`.
- parallel, `configured node/gather-cap comparison`: CUBRID `parallelism=6`,
  `max_parallel_workers=100`; PostgreSQL `max_parallel_workers_per_gather=5`,
  `max_parallel_workers=5`, `parallel_leader_participation=on`,
  `max_worker_processes=16` (non-binding), `statement_timeout=300000 ms`, `jit=off`,
  `debug_assertions=off`. On Q07 the configured caps say 6 and 5+leader while the measured
  units are **1.00 and 6.13** — the widest divergence between configuration and
  measurement in the campaign so far, and section 7 names the code that causes it.
- buffer/cache, `configured-equal buffer budget`: CUBRID `data_buffer_size=8.0G`
  (`data_buffer_pages=524288`), PostgreSQL `shared_buffers=8192MB` (1,048,576 buffers).
  Neither engine's Q07 working set is resident: CUBRID misses **3,113,586 of 14,516,296**
  page fetches (21.4%) and PostgreSQL reads **479,724 of 1,424,714** buffer accesses
  (33.7%) from outside its pool. Both are served by the OS page cache, not the device
  (section 5).
- shared memory, `parallel-plan-availability parity`: PostgreSQL
  `dynamic_shared_memory_type=mmap`, verified live with `source=configuration file`,
  `sourcefile=postgresql.conf:969`. **Mandatory to record here**: Q07's PostgreSQL plan
  contains two `Parallel Hash Join` nodes, one of which spills to **16 batches**
  (`temp read=19309 written=19644`), i.e. exactly the DSM-hungry shape that the default
  `posix` setting would have failed on this host's 62.5 MiB `/dev/shm`.
- I/O path: PostgreSQL `io_method=worker`, `io_combine_limit=16` (× 8 kB = 128 kB max per
  read), `effective_io_concurrency=16`, all at `source=default`.
- cpuset/NUMA: SUT+client CPUs `0-15` (node0), collectors CPUs `20-23`. **34 engine TIDs
  at preflight and 35 after the blocks, 0 off-cpuset both times.** `cub_server`
  8,628.23 MB node0 / 4.62 MB node1 (99.95% node0); postmaster 165.48 MB node0 /
  0.60 MB node1.
- external SUT-set load: **0.828 core-s/s at preflight and 0.306 at post-check** against
  the re-pinned 6.0 threshold. Section 3-b documents the load history in full, because
  Q07's measurement was blocked by it for most of the session and the root cause turned
  out to be the measurement harness itself.

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored.

Q07 has `ORDER BY supp_nation, cust_nation, l_year`, so the ordered sequence was compared
exactly, position by position:

| # | supp_nation | cust_nation | l_year | revenue (both engines) |
|---|---|---|---|---|
| 1 | FRANCE | GERMANY | 1995 | `521960141.7003` |
| 2 | FRANCE | GERMANY | 1996 | `524796110.3842` |
| 3 | GERMANY | FRANCE | 1995 | `542199700.0546` |
| 4 | GERMANY | FRANCE | 1996 | `533640926.2614` |

All four decimal strings are **byte-identical**, so the 1e-12 relative tolerance was
available but **never entered**; text, integers, dates, NULLs, row count and row multiset
match exactly. Comparator: `harness/correctness_check.py` delegating to the
bootstrap-verified `harness/smoke_check.py` rules (`q7-correctness.json`,
`q7-correctness-cubrid.out`, `q7-correctness-postgresql.out`).

Independent ground truth, identical on both engines (`q7-groundtruth-cubrid.out`,
`q7-groundtruth-pg.out`), used later for `W`, for `F_work`, and as the cross-check on
every intermediate cardinality in both plans:

| Quantity | Value (both engines) |
|---|---|
| `nation` rows matching FRANCE/GERMANY | 2 |
| `supplier` in those nations | 8,010 |
| `customer` in those nations | 120,469 |
| `orders` of those customers | 1,205,808 |
| `lineitem` of those orders | 4,819,158 |
| … of those, `l_shipdate` in [1995-01-01, 1996-12-31] | 1,463,770 |
| `lineitem` in the ship-date window (whole table) | 18,230,325 |
| `lineitem` in the window with a FR/DE **supplier** | 1,460,257 |
| **Q07 qualifying rows** (both nation predicates) | **58,365** |
| Q07 output groups | 4 |
| `lineitem` rows total | 59,986,052 |

## 3-b. Headline timings

Regime `single-query-repeat WARM`; metadata connection mode
`single-connection-four-statements` (1 uncounted warmup + 3 measured, one direct
connection, no reconnect/prepare between measured statements, connection establishment
excluded). **Q07 is odd, so the engine-block order is CUBRID block first, then PostgreSQL
block** (section 12), and blocks were grouped per engine with a per-block re-warm, per
section 24. Each statement fully consumed its 4 rows into a campaign-owned fixed sink
under `work/Q07/sink`; content hashes computed after the timers stopped.

| Field | CUBRID | PostgreSQL |
|---|---|---|
| WARM established after | 12-statement gate, half-split trend +0.8469%, first pass at statement 12 | 24-statement gate, half-split trend −0.1281%, first pass at statement 13 |
| warmup (uncounted) | 23.880999 s | 2.593741 s |
| measured run 1 | 24.078000 s | 2.496420 s |
| measured run 2 | 23.718999 s | 2.529707 s |
| measured run 3 | 23.604999 s | 2.520791 s |
| **median (headline)** | **23.718999 s** | **2.520791 s** |
| mean | 23.800666 s | 2.515639 s |
| within-block sd | 0.201552 s (0.847%) | 0.014069 s (0.559%) |
| block wall (4 statements) | 95.306 s | 10.148 s |
| sink bytes | 2,580 | 1,286 |
| sink SHA-256 | `6bda3108b3fa141bba75bb10…` | `f85f878e34772df36acf4229…` |
| external load during block | mean 0.629 / max 2.409 → `CLEAN` (strict per-sample, threshold 6.0) | mean 0.811 / max 2.439 → `CLEAN` |

**Median wall ratio = 9.409348x (CUBRID / PostgreSQL) — PostgreSQL is 9.4093x faster.**
Correctness status `result-equivalent-at-SF10`; censoring status: not censored (23.7 s and
2.5 s against a 300 s limit). No confidence interval is claimed from three values. Both
accepted blocks are `CLEAN` under the **strict per-sample** reading of the section 9 gate
at the re-pinned 6.0 core-s/s threshold — no relaxed acceptance rule was used for either
headline.

**Reproducibility.** Only one block per engine passed both gates, so the reproducibility
evidence is the population of measured-but-rejected blocks, all preserved
(`INVALID.json` indexes them):

| CUBRID block | median | why not headline |
|---|---|---|
| reported (`blockh1`) | **23.718999 s** | accepted, strict `CLEAN` |
| 15:07 attempt | 23.936999 s | `INVALID_BACKGROUND_LOAD` (ext_max 4.24, old 1.5 gate) |
| 15:20 attempt | 23.374999 s | `INVALID_BACKGROUND_LOAD` (ext_max 4.33) |
| 15:29 attempt | 24.344999 s | `INVALID_BACKGROUND_LOAD` (ext_max 5.82) |
| 16:36 attempt | 24.043999 s | `INVALID_BACKGROUND_LOAD` (ext_max 8.82, above the new 6.0 gate too) |
| median of the five | 23.94 s (+0.9% vs reported) | — |

| PostgreSQL block | median | why not headline |
|---|---|---|
| reported (`blockh1`) | **2.520791 s** | accepted, strict `CLEAN` |
| second block | 2.536194 s | `INVALID_BACKGROUND_LOAD` (ext_max 6.15) |
| independent 40-statement convergence probe | 2.428275 s steady level | uncounted warm probe |

The block-to-block spread is **0.9% (CUBRID)** and **0.6% (PostgreSQL)**, i.e. below the
within-block sd on the CUBRID side — Q07's walls are stable once the engine is converged.

**WARM proof (proved, not assumed), and Q07 needed far more of it than any earlier
query.**

| Evidence | CUBRID | PostgreSQL |
|---|---|---|
| steady state proved before timing | 12-statement pre-warm per block, half-split trend +0.85% within a 3.0% tolerance | 24-statement pre-warm per block, half-split trend −0.13% within 1.0% |
| independent convergence probe | 30 statements, median **34.66 s**, trend −0.29% — *at a level 46% above the final one, see below* | 40 statements, median **2.428 s**, trend −0.20%, trailing spread 0.80% |
| absolute-level cross-check | five block medians 23.37–24.34 s straddle the pre-warm steady levels 23.72–24.16 s; reported block is **−0.8%** below its own warm level | four block/probe medians 2.428–2.536 s; reported block is **+3.8%** above the 40-statement stationary level (per-connection cost the separate warm connection cannot remove) |
| device `read_bytes` (per `/proc/<pid>/io`) | **0 B** across the telemetry block (one 228 KiB delta in the whole trace probe) | 69.6 MiB over a 4-statement block, i.e. 17.4 MiB/statement against 3.17 GiB read |
| engine buffer counters | trace `fetch 14,516,296 / ioread 3,113,586` per statement = **21.4% miss** | `shared hit=944,990 read=479,724` = **33.7% miss**, `heap_blks_read 414,208 + hit 710,922` per statement on `lineitem` alone |
| `rchar` per statement | **47.35 GiB** | 3.17 GiB |
| read syscalls per statement | **3,102,738** (16,384 B each) | 162,663 (19.5 kB each, i.e. `io_combine_limit` batching) |
| warmup vs median | +0.68% | +2.89% |

**Q07's CUBRID level takes ~50 statements to converge, an order of magnitude longer than
Q04–Q06, and the campaign's WARM gate cannot see it.** The full statement-level history of
every Q07 CUBRID statement this session executed (`q7-cubrid-level-history.txt`, 118
statements in execution order) shows: 34.34→34.49 s across the first 30 statements
(trend −0.29%, i.e. *the gate declares this converged*), 33.0–33.4 s for the next 4, then a
**step to 24.2 s** at statement 35 and a slow settle to 23.3–23.9 s from statement ~60
onward. The gate is not wrong about local stationarity; it is blind to a level shift that
happens between blocks, because it only ever sees one block's worth of statements. This is
the strong form of Q05's IMP-002 pool-history finding, and it is why the reported block was
taken after 100+ statements and why the earlier, higher-level blocks are explicitly listed
as rejected rather than averaged in. The mechanism is measurable and is the same one
section 5 quantifies: 3.1 M single-page reads per statement, whose page-cache hit rate
depends on how much of the 10.7 GiB `lineitem` heap the host page cache has accumulated.

**The measurement environment, and a defect in the campaign's own control plane.** Q07
could not obtain a clean block for six hours, and the root cause was **the worker session
itself** (`q7-selfload.txt`): `bun /home/cubrid/.bun/bin/gjc`, the GJC runtime hosting this
query, ran with affinity `0-31` and a 74.9% lifetime CPU average — it busy-polls ~0.8 core
continuously whether or not a tool call is active — so the scheduler placed the
measurement control plane **on the SUT set it was measuring**. Section 9 assigns CPUs 0-15
to SUT+client and 20-23 to collectors; nothing had ever pinned the worker runtime.
`taskset -a -cp 24-31` on the agent/tmux trees removed it (visible container CPU on the SUT
set afterwards: **0.000 core-s/s**), leaving a genuine outside-container neighbour that
oscillated between 0.31 and 16.0 core-s/s. That neighbour is what the operator's threshold
decision addressed.

**How much the residual neighbour can bias these numbers is measured, not assumed**
(`q7-loadsens.txt`): adding 2 and 4 *known* busy cores pinned to the SUT set shifts the
trailing-4 median by **+0.47% / +0.33% (PostgreSQL)** and **+0.0% (CUBRID at +2 cores)**;
only at ~9 core-s/s external does CUBRID move materially (+5.8%). Both accepted blocks ran
at external mean 0.63 and 0.81, so the load-induced bias on the reported ratio is bounded
well below the 0.85% within-block sd.

Measurement-resolution note: `csql` reports elapsed time at 1 ms granularity, so CUBRID's
headline carries ±0.004% quantization at this magnitude; `psql` reports µs.

## 4. Plan

**The two engines pick structurally different plans, and for once the slower engine's
choice is refuted by its own executor.**

CUBRID estimated (`SET OPTIMIZATION LEVEL 514`, verified non-executing: 0.02 s wall,
"There are no results"), `q7-plan-est-cubrid.out`:

```text
temp(group by)
  subplan: idx-join (inner join)                      cost 14100 card 292
    outer: idx-join …
      outer: idx-join …
        outer: idx-join …
          outer: nl-join (inner join)  edge: term[0] AND term[1]   cost 53 card 1
            outer: sscan  class: n1 node[4]  sargs term[8]         cost 1 card 2
            inner: sscan  class: n2 node[5]  sargs term[0,1,7]     cost 1 card 2
          inner: iscan  class: customer  index: fk_customer_nation term[3]   cost 1744
        inner: iscan  class: orders    index: fk_orders_customer  term[5]    cost 4
      inner: iscan  class: lineitem  index: fk_lineitem_orders term[6] sargs term[9] cost 4
    inner: iscan  class: supplier  index: pk_supplier_s_suppkey term[4] sargs term[2] cost 3
  sort: 1 asc, 2 asc, 3 asc                            cost 14107 card 292
```

Six relations, five join levels, **one driving scan of a 1-page table** and four index
descents per surviving row. CUBRID has no `EXPLAIN ANALYZE`; its actual execution is read
from `SET TRACE ON` (`q7-trace-cubrid.out`), which agrees with ground truth at every level:

| trace node | index | readkeys | rows out | heap lookups → after sarg | fetch | ioread | btree ms | lookup ms |
|---|---|---|---|---|---|---|---|---|
| `SCAN nation` (n1) | — | — | 2 (of 25 readrows) | — | 3 | 0 | 0 | — |
| `SCAN nation` (n2) | — | — | 2 (of 50 readrows) | — | 54 | 0 | 0 | — |
| `SCAN customer` | `fk_customer_nation` | 2 | 120,469 | 120,469 | 120,721 | 93,707 | 376 | 363 |
| `SCAN orders` | `fk_orders_customer` | 120,469 | 1,205,808 | 1,205,808 | 1,567,644 | 1,281,382 | 6,397 | 5,703 |
| `SCAN lineitem` | `fk_lineitem_orders` | 1,205,808 | 4,819,158 | 4,819,158 → **1,463,770** | 8,436,582 | 1,496,729 | 14,804 | 6,335 |
| `SCAN supplier` | `pk_supplier_s_suppkey` | 1,463,762 | 1,463,762 | 1,463,762 → **58,365** | 4,391,286 | 241,766 | 5,882 | 2,444 |
| `GROUPBY` | hash+sort | — | 4 | — | 0 | 0 | 72 | — |
| **SELECT total** | | | | | **14,516,296** | **3,113,586** | 28,131 ms | |

PostgreSQL estimated and actual (`EXPLAIN (ANALYZE, BUFFERS, TIMING, VERBOSE)`,
`q7-plan-est-pg.out`, `q7-plan-act-pg.out`, `Workers Launched: 5`):

```text
Finalize GroupAggregate                        actual 2856 ms, rows 4
  Gather Merge  (Workers Planned/Launched 5)   rows 24
    Partial GroupAggregate                     rows 4, loops 6
      Sort  quicksort 1189 kB                  rows 9,727.5, loops 6
        Parallel Hash Join  (l_orderkey = o_orderkey)      rows 9,727.5 loops 6
          Join Filter: (FR,DE) OR (DE,FR)      Rows Removed 9,775
          -> Parallel Hash Join (l_suppkey = s_suppkey)    rows 243,376 loops 6
               -> Parallel Seq Scan lineitem   rows 3,038,387 loops 6, Removed 6,959,288
               -> Parallel Hash <- Hash Join supplier x nation n1   rows 1,335 loops 6
          -> Parallel Hash  Buckets 131072 Batches 16 Memory 5824 kB, temp written 7,136
               -> Parallel Hash Join (o_custkey = c_custkey)  rows 200,968 loops 6
                    -> Parallel Seq Scan orders     rows 2,500,000 loops 6
                    -> Parallel Hash <- Hash Join customer x nation n2  rows 20,078 loops 6
```

Node-by-node the two plans share **no** access path: CUBRID reads 15.2 M tuples through
four B-trees and never scans a large table; PostgreSQL scans `lineitem` (59,986,052 rows,
41,755,727 discarded by the ship-date filter), `orders` (15,000,000) and `customer`
(1,500,000) end to end and joins them with three parallel hash joins, one spilling to 16
batches. Every intermediate cardinality in both plans matches the ground-truth table in
section 2 exactly.

**The controlled A/Bs (each a gated section-12 block of its own, `variants/`):**

| Configuration | shape | median wall | U (units) | vs its own native |
|---|---|---|---|---|
| CUBRID native | idx-NL chain, serial | 23.718999 s | 1.00202 | — |
| CUBRID `/*+ USE_HASH */` | 5 hash joins over sscans | **6.464000 s** | **7.19707** | **3.6694x faster** |
| PostgreSQL native | parallel hash tree | 2.520791 s | 6.13206 | — |
| PostgreSQL `enable_hashjoin=off, enable_mergejoin=off` | NL chain `customer→orders→lineitem→supplier`, parallel outer | 3.618685 s | 4.84211 | 1.4355x slower |

Uncounted single-statement probes (`q7-variant-driver.log`, cold, listed for completeness
and never used in the card): PostgreSQL native-shape serial 14.46 s, PostgreSQL NL serial
17.94 s — i.e. PostgreSQL's own parallel speedup is 5.73x on its native shape.

**CUBRID's optimizer prefers the plan it loses with by a factor of 872 in estimated cost**:
`idx-join` total 14,107 versus `hash-join` total 12,297,558 (`variants/plan-USE_HASH.out`),
while the measured ratio is 0.27 the other way. `F_plan` is therefore not a shape penalty
that CUBRID had to pay — it is a decision error, and section 7 points at the two lines of
cost model that produce it.

## 5. Execution telemetry

Three independently gated headline-regime telemetry runs per configuration; the
median-`U` run is the reported one (`Q07-*-headline-telemetry-run*.json`).

| Quantity | CUBRID native | PostgreSQL native | PG controlled idx-NL | CUBRID controlled USE_HASH |
|---|---|---|---|---|
| block wall (4 statements) | 95.876 s | 10.088 s | 14.618 s | 25.980 s |
| `executor_cpu` | 95.370 core-s | 56.060 core-s | 69.860 core-s | 181.850 core-s |
| `auxiliary_query_cpu` | 0.700 core-s | 5.800 core-s | 0.920 core-s | 5.130 core-s |
| `total_query_cpu` | 96.070 core-s | 61.860 core-s | 70.780 core-s | 186.980 core-s |
| `U = CPU/wall` | **1.00202** | **6.13206** | 4.84211 | **7.19707** |
| TWU (actual sample deltas) | 1.0016 | 6.3049 | 4.8734 | 7.1825 |
| max simultaneous units | 1.2861 | 8.4527 | 5.3444 | **13.0964** |
| serial tail | 95.857 s (the whole block) | 0.123 s | 0.243 s | **0.000 s** |
| planned / launched workers | n/a / 0 | 5 / 5 | 5 / 5 | n/a / up to 12 observed |

**CUBRID executes Q07's chosen plan on exactly one thread.** `U = 1.002`, TWU `1.0016`,
`perf stat` `1.011 CPUs utilized`, and the "serial tail" is the entire block. The peak of
1.29 units is the client `csql` overlapping the server thread, not a second query thread.
`parallelism=6` and `max_parallel_workers=100` were in force and verified live the whole
time.

**The same server reaches 7.20 units — above its own configured `parallelism=6` — on the
hash plan**, with peak 13.1 simultaneous units and a **zero** serial tail. So CUBRID's
parallel machinery is neither disabled nor incapable here; it is unreachable from the plan
the optimizer picked.

### The 3.1-million-syscall statement

Per measured statement (`/proc/<pid>/io` deltas over the telemetry block, divided by 4):

| | CUBRID | PostgreSQL | ratio |
|---|---|---|---|
| `rchar` (bytes copied out of the page cache) | **47.35 GiB** | 3.17 GiB | **14.9x** |
| `syscr` (read syscalls) | **3,102,738** | 162,663 | **19.1x** |
| bytes per read syscall | 16,384 (one page) | ~19,968 (2.4 pages) | — |
| device `read_bytes` | 0 | 17.4 MiB | — |

CUBRID issues **one `pread` per 16 KiB page miss**, PostgreSQL issues one read per
`io_combine_limit`-batched run of blocks. The consequence is directly visible in the
profile: 23.53% of CUBRID's cycles are `rep_movs_alternative` inside
`_copy_to_iter ← filemap_read ← __x64_sys_pread64`, i.e. **a quarter of the query is the
kernel memcpy that services those 3.1 M single-page reads**. This is the same mechanism as
IMP-007, at 4.4x the per-statement syscall count Q06 measured, and it is a property of the
index-NL plan: 4.8 M random `lineitem` heap lookups over a 10.7 GiB heap cannot be batched
the way a sequential scan can.

Neither engine touches the device in steady state, so "WARM" here means *the OS page cache
is warm and each engine's pool has reached its own equilibrium*, not *no physical reads* —
identical to Q06's caveat, and proved the same way by `read_bytes ≈ 0`.

## 6. Profile

Non-headline. `perf record -F 999 -g --call-graph dwarf` on verified PID sets, with
`perf stat` on the same sets as the coverage cross-check; **0 unresolved-symbol lines in
either flat profile** (1,323 CUBRID / 1,799 PostgreSQL symbol lines).

CUBRID (`profile-cubrid-flat.txt`, `perf-stat-cubrid.txt`: 159.92 G cycles,
171.16 G instructions, IPC 1.07, 2.876 GHz, 1.011 CPUs utilized, 55,931 samples):

| self% | symbol | band |
|---|---|---|
| 23.53% | `rep_movs_alternative` [k] | page-cache → buffer-pool copy for single-page `pread` |
| 9.14% | `pgbuf_fix_release` | buffer fix path |
| 5.33% | `filemap_get_read_batch` [k] | page-cache lookup per `pread` |
| 3.16% | `spage_get_record` | slotted-page record extraction |
| 2.80% + 2.72% | `btree_search_nonleaf_page`, `btree_search_leaf_page` | B-tree descent |
| 2.09% | `pgbuf_unfix` | buffer unfix |
| 1.87% | `__memmove_evex_unaligned_erms` | intra-server copy |
| 1.82% + 1.82% | `__pthread_mutex_lock/unlock_usercnt` | buffer-pool latching |
| 1.78% | `btree_compare_key` | key comparison |
| 1.76% + 1.45% | `xas_load`, `xas_descend` [k] | page-cache radix walk |
| 1.61% | `heap_attrinfo_read_dbvalues` | heap tuple → DB_VALUE |
| 1.10% | `pgbuf_get_victim_from_lru_list` | victim search |

**Banded: ~32.1% of CUBRID's cycles are page-fetch mechanics** (`rep_movs_alternative` +
`filemap_get_read_batch` + `xas_load`/`xas_descend`), **~14.9% buffer-pool bookkeeping**
(`pgbuf_fix_release`, `pgbuf_unfix`, mutexes, victim search) and **~7.3% B-tree descent**
— that is 54% of the query before a single output row is formed.

PostgreSQL (`profile-pg-flat.txt`, `perf-stat-pg.txt`: 557.50 G cycles, 784.80 G
instructions, IPC 1.41, 2.753 GHz, 5.785 CPUs utilized, 200,745 samples):

| self% | symbol | band |
|---|---|---|
| 29.65% | `tts_buffer_heap_getsomeattrs` | tuple deform in the parallel seq scans |
| 9.75% | `ExecParallelScanHashBucket` | hash probe |
| 5.56% | `ExecInterpExpr` | expression/filter evaluation |
| 4.60% | `next_uptodate_folio` [k] | page-cache batch lookup |
| 4.23% | `heapgettup_pagemode` | page-at-a-time heap scan |
| 2.97% | `hash_search_with_hash_value` | hash table lookup |
| 2.94% | `ExecParallelHashJoin` | join driver |
| 2.42% | `dsa_get_address` | shared hash-table addressing |
| 2.17% | `ExecSeqScanWithQual` | scan + qual |
| 1.97% | `heap_page_prune_opt` | opportunistic pruning |

The two profiles are shaped by their plans, exactly as the card says: **PostgreSQL spends
its cycles on tuples** (deform 29.65% + expression 5.56% + heap scan 4.23% = 39.4% on 60 M
rows), **CUBRID spends its cycles on pages** (32.1% page fetch + 14.9% pool bookkeeping)
for 15.2 M tuples. PostgreSQL's kernel share is 4.6%+1.3% against CUBRID's ~32%.

## 7. Source contrast

| Item | CUBRID file:line | PostgreSQL file:line | Difference | Class |
|---|---|---|---|---|
| **Parallelism is unreachable for every inner join level** | `src/query/parallel/px_scan/px_scan_checker.cpp:874-877` — in `process_xasl_node_recursive()`, `for (XASL_NODE *xaslp = arg->scan_ptr; xaslp; xaslp = xaslp->scan_ptr) process_xasl_node_recursive_force_cannot_parallel (xaslp);`, and `:995-998` inside that callee, which sets `ACCESS_SPEC_FLAG_NO_PARALLEL_SCAN` on every spec of the subtree. A CUBRID multi-way join is a `scan_ptr` chain, so only the **outermost** access spec may parallelize — here a 1-page `nation` scan, for which `px_parallel.cpp:171-173` (`degree = MIN (auto_degree, parallelism)`, "SCAN/HASH_JOIN/SORT use 0 for serial execution and require at least 2 for real parallelism") returns serial | `src/backend/optimizer/path/joinpath.c:2096` `consider_parallel_nestloop()` and `:999` `try_partial_nestloop_path()` build a *partial* nested-loop path whose parallel-ness propagates up the join tree; `src/backend/executor/nodeGather.c:182` `LaunchParallelWorkers()` then runs the whole join subtree in every worker | PostgreSQL parallelizes a *join*; CUBRID parallelizes only the driving *scan* of a join, so the shape CUBRID chose is structurally serial. Measured: `U` 1.00202 vs 4.84211 on the same shape | structural absence |
| **The plan chooser is DOP-blind** | `src/optimizer/query_planner.c:3340` `qo_nljoin_cost()` and `:3576` `qo_hjoin_cost()` contain no parallel-degree term; the only parallel input to planning is `:3054`/`:13460` `qo_check_hjoin_for_parallel_opt()`, a boolean flag on an already-chosen hash-join plan, and `xasl->parallelism` is assigned after plan selection (`src/parser/xasl_generation.c:17214`, `src/optimizer/plan_generation.c:2840`) | `src/backend/optimizer/path/costsize.c:6641` `get_parallel_divisor()`, applied in `cost_seqscan` (`:315-331`), `final_cost_nestloop` (`:4017-4020`) and `final_cost_hashjoin` (`:4474-4477`): every partial path's CPU cost and row count is divided by the effective worker count | CUBRID compares a serial-only plan against a parallelizable plan on a single-threaded cost scale, so the parallelizable plan can never win on cost. Measured: it lost by 872x on cost and won by 3.67x on wall | structural absence |
| **An explicit heuristic bias toward nested loop** | `src/optimizer/query_planner.c:87` `#define HJ_MEM_ALLOC_CONSTANT 1500 /* Heuristic offset to prefer NL join over hash join */`, added into both build orders at `:3626` and `:3634`; plus `:85-86` `HJ_BUILD_CPU_OVERHEAD_FACTOR 40` / `HJ_PROBE_CPU_OVERHEAD_FACTOR 20` multiplying `QO_CPU_WEIGHT` per row | `src/backend/optimizer/path/costsize.c:4439` `final_cost_hashjoin()` charges `cpu_operator_cost` per tuple and per bucket comparison with no method-preference constant | The preference for NL is hard-coded rather than derived, and the per-row factors (40 build / 20 probe) are 2-4x the `QO_CPU_WEIGHT` scale used for scan rows | same stage, lower measured cost |
| **Spill penalty scales with total cardinality** | `src/optimizer/query_planner.c:3650-3658`: once `inner_cardinality * per_entry_size > max_hash_list_scan_size * 0.8`, the cost gains `(inner_cardinality + outer_cardinality) * HJ_FILE_IO_WEIGHT` (`:90`, 0.5/row) — for Q07's 1.46 M × 18.2 M join that single term dominates the 12.3 M plan cost | `src/backend/optimizer/path/costsize.c:4320` `initial_cost_hashjoin()` charges spill I/O as `seq_page_cost * (inner_pages + outer_pages)` for the batches actually predicted, i.e. per **page**, not per row | CUBRID charges spill per row at a fixed weight; the same spill on PostgreSQL cost 16 batches of page I/O and measured 690 ms of a 2.5 s query | same stage, lower measured cost |
| **Every page miss is one synchronous single-page `pread`** | `src/storage/page_buffer.c:8349` `pgbuf_claim_bcb_for_fix()` → `src/storage/file_io.c:3935` `fileio_read (…, size_t page_size)` → one `__libc_pread64` per 16 KiB page; measured 3,102,738 per statement, 23.53% of cycles in the kernel copy (call graph in `profile-cubrid-callgraph.txt`) | `src/backend/storage/aio/read_stream.c:16,332,819` merges adjacent block reads up to `io_combine_limit` and issues them through the AIO worker pool; `src/backend/access/heap/heapam.c:743` `read_stream_next_buffer()` feeds `heapgettup_pagemode` (`:1074`) | 19.1x more read syscalls and 14.9x more page-cache bytes copied per statement. Same root cause as IMP-007, here amplified by random index-driven heap access | same stage, lower measured cost |

Searched and **not** found on the CUBRID side, recorded per section 17: any parallel-degree
term in `qo_*_cost` (`grep -n 'parallel' src/optimizer/query_planner.c` → 9 hits, all
either `PLAN_PARALLEL_OPT_NO` bookkeeping, the `qo_check_hjoin_for_parallel_opt` boolean,
or comments); any multi-page/vectored read path reachable from `pgbuf_claim_bcb_for_fix`
(`fileio_read_pages` at `file_io.c:4211` exists but is used by backup/restore and
`btree_load`, not by the buffer-fix path); any propagation of the outer spec's
parallel eligibility into `scan_ptr` levels (`px_scan_checker.cpp` has three call sites
that walk `scan_ptr`, all of them force-blocking: `:874`, `:976`, `:1016`).

## 8. Causal decomposition details

**Both anchors, side by side** (`q7-card-calc.txt`, `Q07-causal-card.json`):

| | anchor A (PostgreSQL-side) | anchor B (CUBRID-side) |
|---|---|---|
| controlled leg | PG native → PG `enable_hashjoin=off,enable_mergejoin=off` | CUBRID native → CUBRID `/*+ USE_HASH */` |
| `F_plan` | 1.435536x | 3.669400x |
| remaining cross-engine pair | (CUBRID native, PG idx-NL) | (CUBRID USE_HASH, PG native) |
| `F_units` | 4.832349x | 0.852022x |
| `F_cpu` | 1.356399x | 3.009635x |
| product | 9.409348x | 9.409348x |
| residual | 0.000000% | −0.000000% |

The two anchors disagree about *where* the loss sits, and that disagreement is the result
rather than a defect. On the **index-NL** shape CUBRID's utilization is 4.83x worse and its
CPU is only 1.36x worse; on the **hash** shape its utilization is *better* (7.20 vs 6.13)
and its CPU is 3.01x worse. Read together: **CUBRID has a plan it will not parallelize and
a plan whose parallel CPU costs 3x PostgreSQL's — and it picks the first.** The residual
cross-engine factor is shape-dependent (6.55x on index-NL, 2.56x on hash) and both are
reported rather than one being presented as *the* engine gap.

**Work and cost on the native pair.** `F_cpu(native)` = 1.537551x factors two ways, and
both are reported because they answer different questions:

| Work event | `W_C` | `W_P` | `F_work` | `F_cost` | reading |
|---|---|---|---|---|---|
| plan-node tuple touches | 15,218,469 | 79,386,706 | 0.191700x | 8.020590x | CUBRID touches **5.2x fewer tuples** and pays **8.0x more CPU per tuple** |
| buffer page fetches | 14,516,296 | 1,424,714 | 10.188919x | 0.150904x | CUBRID fetches **10.2x more pages**, each carrying 6.6x less work |

`W_C` tuple touches = index rows + heap lookups at every trace level
(25 + 50 + 2×120,469 + 2×1,205,808 + 2×4,819,158 + 2×1,463,762); `W_P` = rows examined by
all six scans (59,986,052 + 15,000,000 + 1,500,000 + 100,000 + 25 + 25) plus every hash
build/probe/sort/aggregate row from `q7-plan-act-pg.out`. Neither engine's number is an
estimate.

**Explanations considered and rejected, with the number that rejected them:**

- *"CUBRID is slower because its plan is worse."* Rejected by anchor A: forcing the same
  shape on PostgreSQL costs only **1.4355x** of the 9.41x. The shape is a seventh of the
  gap.
- *"CUBRID is slower because it does more work."* Rejected by `F_work` = **0.1917** — it
  does 5.2x **less** tuple work than PostgreSQL. Its plan is the more selective one.
- *"CUBRID's parallelism is misconfigured for Q07."* Rejected by the USE_HASH block:
  the same server, same parameters, reaches **U = 7.19707** with peak 13.1 units on the
  hinted plan. The configuration is fine; the chosen plan is unparallelizable
  (section 7, `px_scan_checker.cpp:874-877`).
- *"The 21.4% buffer miss rate is the cause."* Rejected as *the* cause by the USE_HASH
  control: that plan scans **more** data (five sequential scans over `lineitem`, `orders`,
  `customer`, `supplier`, `nation`) and still finishes 3.67x faster. Page-fetch mechanics
  are 32% of the native profile, but they are a consequence of 4.8 M random heap lookups,
  not an independent defect. They do bound how much a pure parallelization fix could
  recover.
- *"The measurement is contaminated by host load."* Rejected quantitatively: both accepted
  blocks are strict-`CLEAN` at external mean 0.63/0.81 core-s/s, and the controlled
  load-sensitivity experiment puts the bias of even 2 extra busy cores at ≤0.47%
  (`q7-loadsens.txt`), against a 9.41x effect.
- *"CUBRID's 23.7 s is a cold number."* Rejected by the 118-statement level history: the
  reported block sits at the bottom of a converged plateau (23.3–24.3 s over the final 60
  statements) and 46% below the first probe's level. The direction of any residual
  warm-up bias is *against* the reported value being too high.

**What a fix would be worth, arithmetically.** If CUBRID chose the hash plan on Q07 the
ratio becomes 6.464/2.520791 = **2.5643x** (a 3.67x improvement); if in addition its
per-tuple CPU on that shape matched PostgreSQL's, the remaining `F_cpu` 3.01x would close
to ~1. These are bounds from measured configurations, not projections.

## 9. Improvements

### IMP-011 — the plan chooser cannot see parallel degree, so it prefers a serial index-nested-loop chain over a hash-join plan the same executor runs 3.67x faster at 7.20 units

**Status** `measured`. **Priority** `P0` — Q07's single largest factor: 3.6694x of a 9.41x
gap, measured by same-engine A/B, and the mechanism is shared by every join query whose
selective path is an FK index chain. **Category** optimizer, parallelism. **Difficulty**
high — it changes what the cost model compares, not one branch. **Evidence type** direct
A/B (plus profile attribution for the band split).

**Mechanism, per operation.** CUBRID's join enumeration costs a nested-loop-with-index
plan in `qo_nljoin_cost()` (`src/optimizer/query_planner.c:3340`) and a hash-join plan in
`qo_hjoin_cost()` (`:3576`). Neither function has any notion of how many threads the plan
will run on; the parallel degree is decided *after* plan selection
(`xasl->parallelism`, `src/parser/xasl_generation.c:17214`) and then filtered by
`scan_check_parallel_scan_possible()` (`px_scan_checker.cpp:1065`), whose
`scan_ptr` walk at `:874-877` force-blocks parallel scan on **every inner join level**. So
the optimizer compares a plan that will get 1 thread against a plan that will get 7.2
threads on a scale where both get 1. On Q07 it additionally adds
`HJ_MEM_ALLOC_CONSTANT 1500` ("Heuristic offset to prefer NL join over hash join", `:87`)
and a per-row spill penalty `(inner_card + outer_card) * 0.5` (`:3650-3658`) that alone
dominates the hash plan's 12,297,558 estimated cost against the index-NL plan's 14,107.
Measured outcome: the plan it rejects runs in **6.464 s at U 7.19707 with a 0.000 s serial
tail**, the plan it picks runs in **23.719 s at U 1.00202** with the whole block as serial
tail.

**What PostgreSQL does instead.** `get_parallel_divisor()`
(`src/backend/optimizer/path/costsize.c:6641`) is applied inside `cost_seqscan`
(`:315-331`), `final_cost_nestloop` (`:4017-4020`) and `final_cost_hashjoin`
(`:4474-4477`), so a partial path is costed at its per-worker cost and the parallel hash
plan wins on cost for the same reason it wins on the clock. PostgreSQL also *has* the
parallel nested-loop option (`joinpath.c:2096` `consider_parallel_nestloop`), which is why
its forced index-NL variant still reaches U 4.84 — the shape and the parallelism are
independent there, and coupled in CUBRID.

**Quantified expected effect.** 3.6694x on Q07's wall (23.719 s → 6.464 s), which moves the
CUBRID/PostgreSQL ratio from 9.4093x to 2.5643x. Mapped to bands: it removes the
`F_units` 4.83x term of anchor A and replaces the 32.1% page-fetch + 14.9% pool-bookkeeping
profile bands (a consequence of 4.8 M random heap lookups) with the hash plan's sequential
scans.

**Implementation direction.** Make plan comparison parallel-aware in the two cost
functions: derive the degree each candidate would actually get (the same predicate
`scan_check_parallel_scan_possible()` will later apply, plus `px_parallel.cpp`'s
`compute_parallel_degree`) and divide the variable CPU cost by it, exactly as
`get_parallel_divisor()` does. Two smaller, independently shippable steps: (a) charge the
hash spill per *page* rather than per row (`:3650-3658`), (b) re-derive
`HJ_MEM_ALLOC_CONSTANT`/`HJ_BUILD_CPU_OVERHEAD_FACTOR`/`HJ_PROBE_CPU_OVERHEAD_FACTOR`
from measurement instead of keeping a hard-coded NL preference.

**Correctness/regression risk** medium-high: it changes plan choice for every join query,
so a plan-stability suite is mandatory; low semantic risk since no operator changes.
**Validation criteria** Q07 chooses the hash plan without a hint and lands within 5% of
6.464 s; Q05's index-NL choice (where the NL shape is genuinely 1.80x better for
PostgreSQL) must **not** flip; Q01–Q22 plan-shape diff reviewed; TPC-H SF10 total wall not
regressed. **Relations** — predecessor: none; **alternative**: teach
`px_scan_checker` to parallelize inner join levels (fixes the same 4.83x from the executor
side and would make CUBRID's *native* plan parallel, but is a much larger change and does
not fix the cost-model blindness); **containment**: IMP-009 (hardcoded degree 1 for
uncorrelated subqueries) is the same class of defect — a plan-time parallel-degree decision
made without measurement — but on a different code path. **Upstream precedent**: no
precedent in the pinned CUBRID history for a DOP-aware plan cost; PR #7441 (in this
campaign's SHA) added parallel hash join *execution*, which is precisely what the cost
model has not caught up with.

### IMP-007 — Q07 relation: 3.1 M single-page `pread`s per statement, 4.4x Q06's rate

Q07 is IMP-007's worst measured case: `syscr` **3,102,738 per statement** (Q06: 608,510),
`rchar` **47.35 GiB** (Q06: 9.29 GiB), and **23.53%** of all CUBRID cycles inside
`rep_movs_alternative ← _copy_to_iter ← filemap_read ← __x64_sys_pread64 ← fileio_read ←
pgbuf_claim_bcb_for_fix`. New evidence added by Q07: the rate is a property of the *plan*,
not of the table — the same query's hash plan reads more data with a fraction of the
syscalls, and PostgreSQL's `read_stream.c` batching gives 2.4 pages per read against
CUBRID's 1.0. Status stays `measured`; Q07 raises its priority justification from
"9.29 GiB/statement" to "47.35 GiB/statement on a plan the optimizer prefers".

### IMP-002 — Q07 relation: the pool-history effect is now a 46% level shift, not ±1.5%

Q05 recorded that a CUBRID block's level depends on what the pool already held (±4.2%);
Q06 saw ±1.5%. Q07 measures **34.66 s → 23.31 s (−32.7%) across 118 statements of the
identical query**, with a step change between blocks and a settle only after ~60
statements (`q7-cubrid-level-history.txt`). This is the same root cause (pool retention of
a working set that exceeds the pool) with an order of magnitude more amplitude, and it has
a measurement consequence the campaign must carry: **a 12–40 statement WARM gate cannot
detect it**, because the drift is between blocks, not within one.

### IMP-005 — Q07 relation: trace statistics are consistent here, and that is a positive control

Q06 found `SET TRACE ON` merging parallel-scan statistics incorrectly. Q07's trace runs
on a **serial** plan and its every counter reconciles exactly with independent ground truth
(120,469 / 1,205,808 / 4,819,158 / 1,463,770 / 58,365) and with `/proc` I/O
(`ioread 3,113,586` vs `syscr 3,102,738`, 0.35% apart). The defect is therefore confirmed
to be specific to the parallel path, not to trace accounting in general.

### IMP-010, IMP-006, IMP-008 — considered and **not** related on Q07

IMP-010 (parallel scans losing private-LRU scan resistance) cannot apply to CUBRID's Q07
plan because it never runs a parallel scan; it *could* apply to the USE_HASH variant and is
left for the query that measures that path natively. IMP-006 (intermediate results
materialized to list files) is not visible: the trace shows `GROUPBY … page: 0, ioread: 0`
and the join is a pipelined `scan_ptr` chain. IMP-008 (generic `DB_VALUE` sarg dispatch)
is present but small here — `heap_attrinfo_read_dbvalues` 1.61%, `btree_compare_key` 1.78%
— because Q07's per-row predicate work is one date-range comparison and one nation-key
equality, against Q06's three sargs on 60 M rows.

## 10. Evidence index

Format: `claim → raw file:line → formula → evidence type → SHA-256` (SHA-256 of every file
in `reports/Q07/raw-manifest.json`; all paths relative to
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q07/`).

| Claim | Raw pointer | Formula / derivation | Evidence type |
|---|---|---|---|
| CUBRID median 23.718999 s | `Q07-cubrid-headline-blockh1.json` `statement_times_all[1:]` | median of 3 measured statements | direct measurement |
| PostgreSQL median 2.520791 s | `Q07-postgresql-headline-blockh1.json` | median of 3 | direct measurement |
| `R_wall` 9.409348x | both above | 23.718999/2.520791 | direct measurement |
| Both blocks strict-`CLEAN` at threshold 6.0 | `Q07-cubrid-bgload-blockh1.json`, `Q07-postgresql-bgload-blockh1.json` `verdict`,`external_max` | max over 0.25 s samples ≤ 6.0 | direct measurement |
| `F_plan` 1.435536x | `Q07-postgresql-idxnl-headline.json`, `Q07-postgresql-headline-blockh1.json` | 3.618685/2.520791 | direct A/B |
| `F_plan` (anchor B) 3.669400x | `Q07-cubrid-usehash-headline.json` | 23.718999/6.464000 | direct A/B |
| `U` CUBRID 1.00202 / PG 6.13206 | `Q07-cubrid-headline-telemetry-run2.json`, `Q07-postgresql-headline-telemetry-run2.json` | CPU_block/t_block, median-U of 3 runs | profile attribution |
| `U` PG idx-NL 4.84211 / CUBRID hash 7.19707 | `Q07-postgresql-idxnl-headline-telemetry.json`, `Q07-cubrid-usehash-headline-telemetry.json` | same | profile attribution |
| TWU 1.0016 / 6.3049 / 4.8734 / 7.1825 | same four JSONs, `units.time_weighted_active_units` | actual sample timestamp deltas | profile attribution |
| `perf stat` 1.011 / 5.785 CPUs | `perf-stat-cubrid.txt`, `perf-stat-pg.txt` | task-clock / elapsed on verified PID sets | profile attribution |
| CUBRID single-threaded, tail = whole block | `Q07-cubrid-headline-telemetry-run2.json` `units.serial_tail_s` 95.857 | per-TID sampler | profile attribution |
| tuple touches 15,218,469 vs 79,386,706 | `q7-trace-cubrid.out`, `q7-plan-act-pg.out`, `q7-groundtruth-*.out` | sum of per-node rows + heap lookups / rows examined | direct A/B |
| page fetches 14,516,296 vs 1,424,714 | `q7-trace-cubrid.out` `SELECT (… fetch:)`, `q7-plan-act-pg.out` `Buffers: shared hit+read` | counter read | direct measurement |
| 3,102,738 read syscalls, 47.35 GiB `rchar` per statement | `Q07-cubrid-headline-telemetry-run2.json` `io.engine_and_client` | (syscr, rchar)/4 statements | direct measurement |
| 23.53% cycles in the page-copy path | `profile-cubrid-flat.txt`, `profile-cubrid-callgraph.txt` | perf self% with call graph | profile attribution |
| 29.65% cycles in tuple deform (PG) | `profile-pg-flat.txt` | perf self% | profile attribution |
| every intermediate cardinality equal on both engines | `q7-groundtruth-cubrid.out`, `q7-groundtruth-pg.out` | independent `count(*)` | direct A/B |
| CUBRID estimated cost 14,107 (idx-NL) vs 12,297,558 (hash) | `q7-plan-est-cubrid.out`, `variants/plan-USE_HASH.out` | optimizer dump | direct measurement |
| 118-statement level history 34.66 → 23.31 s | `q7-cubrid-level-history.txt` | per-statement client walls in execution order | direct measurement |
| worker self-load was ~0.8 core on the SUT set | `q7-selfload.txt` | `ps`/`/proc/stat` attribution before and after `taskset` | direct measurement |
| load bias ≤0.47% at +2 cores | `q7-loadsens.txt` | trailing-4 median shift vs known added hogs | direct A/B |
| SSOT re-pins non-substantive | `q7-ssot-repin.txt` | `git diff` of the two commits | direct measurement |
| preflight/postcheck gates | `preflight-Q07.txt`, `q7-postcheck.txt` | ownership, 8FK/8idx, cpuset, params | direct measurement |
| excluded artifacts | `INVALID.json`, `quarantine/README.txt` | explicit index of non-evidence | — |

## 11. Notion sync

Not performed by this worker. Section 21's execution boundary: the GJC/tmux worker session
runs on the remote build host, has no Notion connector, and its Notion-adjacent duty ends
at pushing the report and manifest to `origin/main`. An idempotent backfill record was
appended to `reports/notion_backfill_pending.jsonl` (write path 3) with idempotency key
`campaign_id + QNN + session_id + report_commit + content_fingerprint`. The section 23
reconciler subagent performs the operational-state update, the Q01–Q22 row, the
improvement-registry mirror page for IMP-011 and the relation edits, reading the pushed
commit as source of truth, and clears the pending record only after a server-side refetch.

Content required in the Notion page body (section 21 richness rule): the causal card with
both anchors and the full factor table, the headline table, the section 4 plan comparison
including the two controlled A/Bs, the top-cost symbols for both engines, the full section
7 source contrast with `file:line` on both sides, the section 8 narrative including the six
rejected explanations and the numbers that rejected them, and IMP-011 with its own
registry page.

## 12. Completion checklist

| Item | State |
|---|---|
| preflight recorded (identity/schema/ownership/NUMA/cpuset) | **done** — `preflight-Q07.txt`, 34 TIDs 0 off-cpuset, 8FK/8idx/8validated, binaries hash-match |
| correctness gate | **done** — `result-equivalent-at-SF10`, 4 rows byte-identical, not censored |
| estimated plans without execution | **done** — `q7-plan-est-cubrid.out` (0.02 s, no rows), `q7-plan-est-pg.out` |
| CUBRID WARM + 3 headline runs | **done** — `Q07-cubrid-headline-blockh1.json`, strict `CLEAN` |
| PostgreSQL WARM + 3 headline runs | **done** — `Q07-postgresql-headline-blockh1.json`, strict `CLEAN` |
| actual plans and CUBRID trace in separate non-headline runs | **done** — `q7-plan-act-pg.out` (`Workers Launched 5`), `q7-trace-cubrid.out` |
| CPU/thread, `/proc` I/O, iostat, NUMA and buffer diagnostics | **done** — 3 telemetry runs per engine + 2 variant runs, `q7-bufstate.txt`, device I/O in each telemetry JSON. **Gap recorded**: `cubrid statdump -c` returned identical pre/post counters in `q7-bufstate.txt` (the wrapper's statement did not register), so CUBRID page counters are taken from `SET TRACE ON` and `/proc/<pid>/io` instead — both cross-check to 0.35% |
| separate perf cycles/instructions/call-graph runs | **done** — 55,931 + 200,745 samples, 0 unresolved symbols, `perf stat` on verified PID sets |
| CUBRID and PostgreSQL `file:line` | **done** — 5-row contrast table, all lines verified against the pinned SHAs |
| causal multiplier decomposition | **done** — two anchors, residual 0.000000%, `F_work`/`F_cost` on two work events |
| improvement registry deduplicated | **done** — IMP-011 allocated after searching by title, both source locations and root cause; IMP-007/002/005 gained Q07 relations; IMP-010/006/008 explicitly recorded as not related on Q07 |
| raw manifest + report committed and pushed | **done** — see `report_commit` in the STATUS block |
| every claim indexed to raw evidence and checksum | **done** — section 10 + `raw-manifest.json` |
| Notion synced or backfill durable | **backfill record appended** (write path 3); reconciler subagent owns the sync |
| `QUERY_COMPLETE` emitted | **done** |
| session removed and absence verified | **pending the two `gjc session status` / `tmux has-session` checks that follow this report** |

**Carried forward to the campaign, not resolved by Q07:**

1. **The WARM gate is blind to between-block level drift.** Q07 moved 32.7% across 118
   statements while every 12–40 statement gate reported convergence. A future harness
   change should compare a block's level against the *previous block's* level, not only
   against its own warm series.
2. **Proposed SSOT amendment (not applied during this query so the pin stays stable):**
   section 9 should require the GJC worker runtime and the tmux server to be pinned off the
   SUT set, and `preflight_check.sh` should verify it the way it already verifies engine
   TIDs. Q07 lost six hours to a 0.8-core self-inflicted load that no gate looked for.
3. **`cubrid statdump` per-statement delta capture** needs a working wrapper (item above).
