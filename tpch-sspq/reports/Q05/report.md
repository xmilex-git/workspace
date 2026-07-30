# TPCH-SSPQ FK campaign — Q05 report

## 3-a. Causal multiplier card

```text
R_wall 3.749374x [wall, median of 3 per engine; PostgreSQL is 3.7494x faster]
= F_plan  0.555954x [plan-shape; PostgreSQL-side controlled A/B, anchor named below]
× F_units 5.277061x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   1.277990x [total query CPU-seconds]

F_cpu 1.277990x [total query CPU-seconds]
= F_work 1.111333x [plan-node tuple touches: 9,814,264 vs 8,831,078]
× F_cost 1.149962x [total-query CPU-seconds per plan-node tuple touch]
```

**Read the card in one line: CUBRID picks the better plan, executes it with almost
exactly PostgreSQL's CPU, and loses 3.75x anyway because it runs that plan on one
thread.**

`F_plan` is numeric by a **PostgreSQL-side controlled A/B**, and the anchor direction
matters, so it is stated explicitly: *PostgreSQL native (all-parallel-hash) →
PostgreSQL controlled (`enable_seqscan=off`, index-nested-loop on `lineitem` — the
shape CUBRID chooses natively)*. Forcing PostgreSQL onto CUBRID's shape makes
PostgreSQL **1.7987x faster than its own native choice** (1.425705 s vs 2.564428 s).
The plan factor is therefore *in CUBRID's favour* and cannot explain any part of the
loss. The remaining controlled cross-engine pair is (CUBRID native, PostgreSQL
controlled) and carries `F_units` and `F_cpu`; native and controlled denominators are
never mixed.

That pair is chosen because it is matched **node-for-node on the dominant path**: the
same FK B-tree `l_orderkey` driven with **exactly 456,771 probes on both engines**
(CUBRID trace `readkeys: 456771`, PostgreSQL `Index Searches: 456771`), yielding
**1,825,856 rows on both**, with identical intermediate cardinalities **300,270 /
456,771 / 1,825,856 / 72,985** independently confirmed by ground-truth `count(*)`
queries that both engines answer identically.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 0.555954x | plan-node shape | same-engine controlled A/B on PostgreSQL | `T_P_idxnl/T_P_native` = 1.425705/2.564428 | `Q05-postgresql-idxnl-headline.json`, `Q05-postgresql-headline-block1.json`, `q5-plan-act-pg-idxnl.out` | direct A/B |
| `F_units` | 5.277061x | active execution units | CPU-seconds / wall-second over the section 12 block | `U_P/U_C` = 5.42598/1.02822 | `Q05-postgresql-idxnl-headline-telemetry-run1.json`, `Q05-cubrid-headline-telemetry-run2.json` | profile attribution |
| `F_cpu` | 1.277990x | total query CPU-seconds | per query execution | `CPU_C/CPU_P` = 9.8863/7.7358 | same telemetry JSONs | profile attribution |
| `F_work` | 1.111333x | plan-node tuple touches | tuples | `W_C/W_P` = 9,814,264/8,831,078 | `q5-trace-cubrid.out`, `q5-plan-act-pg-idxnl.out`, `q5-groundtruth-*.out` | direct A/B |
| `F_cost` | 1.149962x | CPU-seconds per tuple touch | tuple touches | `(CPU_C/W_C)/(CPU_P/W_P)` = 1007.3 ns / 876.0 ns | `Q05-causal-card.json` | profile attribution |

**Reconstruction residual = 0.000000%, and as in Q04 that is an identity, not a
prediction.** `CPU_stmt` is attributed as `U × t_median` with `U` measured on the same
block the headline is defined on, so `F_units × F_cpu = T_C/T_P` by construction. The
load-bearing evidence is elsewhere: (a) `U` is reproducible across three independent
runs per configuration (CUBRID 1.0247/1.0282/1.0378, PostgreSQL-idxnl
5.4111/5.4260/5.4816, both 1.3% max-min); (b) TWU, computed from actual sample
timestamp deltas over the busy window only, independently gives 1.0263 and 5.5433
(0.19% and 2.2% from `U`, the latter being the 0.233 s serial tail); (c) **`perf stat`
on the verified CUBRID PID set reports 1.043 CPUs utilized**, a third instrument
confirming `U ≈ 1.03`; and (d) the whole decomposition is reproduced by an independent
anchor below.

**Anchor robustness — the second anchor, and why both are reported.** Anchoring instead
on the CUBRID side (*CUBRID native → CUBRID controlled `/*+ USE_HASH */`, i.e.
PostgreSQL's native shape*) gives

```text
3.749374x = 0.871003x [plan] × 0.948571x [units] × 4.538053x [CPU-sec]
```

also reconstructing exactly. The two anchors disagree about *where* the loss sits, and
that disagreement is the finding rather than a defect: on the **index-NL** shape
CUBRID's parallel utilization is 5.28x worse and its CPU is nearly equal (1.278x); on
the **hash** shape its utilization is *equal* (6.77 vs 6.42 units, `F_units` 0.949) and
its CPU is 4.54x worse. CUBRID has a fast plan it will not parallelize and a parallel
plan that costs 4.5x the CPU. The residual cross-engine factor is shape-dependent
(6.744x on index-NL, 4.305x on hash) and both are reported rather than one being
presented as *the* engine gap.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q05 |
| SSOT commit | `d19dca410b7fc8382d52f4ee7d79175d0a16e203` |
| SSOT blob | `76778d21ae437e87575c4ef7c609a9ccea81e6f1` |
| GJC session ID | `gajae_code_ms7p9g4j_r7yxsbvc` |
| Raw dir | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q05` |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` |
| CUBRID DB / port | `tpch_sf10_q1` / 1523 (`cub_server` pid 1612732 after the section 5 restarts, `cub_master` pid 1433697) |
| PostgreSQL PGDATA / port | `/home/cubrid/pg/pgdata-tpch-sspq` / 5442 (postmaster pid 1433696) |

Both running binaries hash-match the frozen `reports/bootstrap/build-manifest.json`.
Ownership gates (section 10) classified **OK** before and after every measurement
block and before and after each of the two CUBRID restarts; the post-block gate
(`q5-postcheck.txt`) records 0 orphan `csql`, 0 orphan `psql`, 0 parallel workers,
0 client backends, 35 engine TIDs with **0 off-cpuset**, and the CUBRID pool conserved
at exactly 524,288 pages (8 GiB / 16 KiB).

**SSOT re-pin during Q05, recorded rather than glossed.** The session was created
pinned to `ssot_commit 5912f065…` (blob `6ce8e04d…`) and was re-pinned mid-query to
`d19dca41…` (blob `76778d21…`) on the user's direct instruction, which is authority
order 1 in section 2. `git diff 5912f065..d19dca41 -- tpch-sspq/SSOT.md` is exactly
**+11 lines, all inside section 21** (a Notion markdown formatting rule added after a
Q04 page-rendering bug); sections 1–20 and 22–27 are byte-identical. No
measurement-contract term changed — not engine SHA, schema, statistics, the
parallel/buffer/shared-memory contract, the timing regime, timeout, CPU accounting,
the causal-card definition, evidence rules or the report format — so **no stage
collected before the re-pin was invalidated and none was repeated for it**. The old
pin is an ancestor of the new one. `SSOT_DRIFT` was raised and cleared as
`NONE_AFTER_REPIN`; full record in `q5-ssot-repin.txt`. The new rule constrains the
Notion-capable reconciler subagent, not this worker, which per section 21 never writes
to Notion.

Query provenance: `queries/q5-cubrid.sql` byte-matches the canonical source
`/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q5.sql`, SHA-256
`a5da88eb418872eaf7f153376251c1c40af89f9c611b8d8c98f1e0ca8e27f7ab`. The PostgreSQL
dialect (`64978055…`) differs in exactly one line, recorded in `queries/diff/q5.diff`:
`DATE_ADD(DATE '1994-01-01', INTERVAL 1 YEAR)` → `date '1994-01-01' + interval '1' year`,
because CUBRID's `DATE_ADD` has no PostgreSQL equivalent. Both evaluate to 1995-01-01.
No hint, join reordering, subquery rewrite, extra predicate or semantic cast exists in
either measured file; the hinted CUBRID variants and the `PGOPTIONS` PostgreSQL variant
used as counterfactuals are separate diagnostic artifacts under `variants/`, never
measured dialect files.

Schema: 8 named FKs and 8 corresponding child B-trees verified on both engines with
exact child-column order; all PostgreSQL `pg_constraint.convalidated = true` (8/8/8).
Row counts exact-equal on both engines (`lineitem` 59,986,052, `orders` 15,000,000,
`customer` 1,500,000, `supplier` 100,000, `nation` 25, `region` 5). **Q05 is the
campaign's first query where the FK indexes decide the entire plan shape on one engine
and are ignored by the other**: CUBRID drives the whole join through
`fk_nation_region` → `fk_customer_nation` → `fk_orders_customer` →
`fk_lineitem_orders`, while PostgreSQL's cost model prefers four parallel hash joins
over sequential scans.

Contract state at measurement time:

- statistics: CUBRID `update_statistics_update_histogram=y`,
  `default_histogram_bucket_count=300` (target). Actual per-column bucket count remains
  **UNMEASURED** (opaque serialized `VARBIT` in `_db_histogram`) — carried forward from
  bootstrap and Q01–Q04. PostgreSQL standard `ANALYZE`,
  `default_statistics_target=100`, all eight tables last analyzed 2026-07-30 17:54.
- parallel, `configured node/gather-cap comparison`: CUBRID `parallelism=6`,
  `max_parallel_workers=100`; PostgreSQL `max_parallel_workers_per_gather=5`,
  `max_parallel_workers=5`, `parallel_leader_participation=on`,
  `max_worker_processes=16` (non-binding), `statement_timeout=300000 ms`, `jit=off`.
  **Q05 is the query where this label earns its keep**: the configured caps are 6 and 6,
  and the measured units are 1.03 and 5.43. Nothing about the configuration predicts
  that, which is exactly why section 9 forbids inferring execution units from settings.
- buffer/cache, `configured-equal buffer budget`: CUBRID `data_buffer_size=8.0G`,
  PostgreSQL `shared_buffers=8192MB`. At the reported state neither engine is
  buffer-bound on this query (section 5).
- shared memory, `parallel-plan-availability parity`: PostgreSQL
  `dynamic_shared_memory_type=mmap`, verified live with `source=configuration file`,
  `sourcefile=postgresql.conf:969`. Q05's PostgreSQL plan contains three Parallel Hash
  Joins and a Gather Merge, so section 9 makes recording this mandatory — and **Q05 is
  the first query in the campaign to prove the contract is load-bearing rather than
  precautionary** (section 5).
- cpuset/NUMA: SUT+client CPUs `0-15` (node0), collectors CPUs `20-23`. 34 engine TIDs
  at preflight and 35 after the blocks, **0 off-cpuset** both times; re-verified after
  each restart (128 TIDs immediately post-start, 0 off-cpuset). `cub_server`
  8,626.01 MB node0 / 4.62 MB node1 (99.95% node0); postmaster 165.48 MB node0 /
  0.60 MB node1.
- external SUT-set load was **within contract throughout**: 0.772 core-s/s at preflight
  (threshold 1.5) and every accepted block verified `CLEAN` at 4 Hz, with
  `external_max` between 0.49 and 1.09. One perf capture was rejected as
  `INVALID_BACKGROUND_LOAD` and retried.

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored.

Q05 has `ORDER BY`, so the ordered result sequence was compared exactly. 5 rows on both
engines, all fields equal — text (including the CHAR(25) `n_name` padding), row count
and row multiset. Raw decimal text preserved.

| `n_name` | `revenue` |
|---|---|
| `INDIA` | 536862587.9995 |
| `CHINA` | 535350829.9282 |
| `VIETNAM` | 532269388.7176 |
| `JAPAN` | 526766837.1444 |
| `INDONESIA` | 523176852.3189 |

The `ORDER BY revenue desc` is a total order over the 5 output rows and the values are
separated by ≥ 0.6%, so no ordering ambiguity exists. The 1e-12 relative tolerance was
available but **not needed**: every `revenue` value matched to the last recorded digit,
character for character, so the comparison never entered the tolerance branch.

Independent ground truth, identical on both engines (`q5-groundtruth-cubrid.out`,
`q5-groundtruth-pg.out`), used later for `W` and as the IMP-005 control:

| Quantity | Value (both engines) |
|---|---|
| ASIA nations | 5 |
| customers in ASIA nations | 300,270 |
| orders of those customers (all dates) | 3,006,380 |
| …restricted to 1994 | **456,771** |
| lineitem rows of those orders | **1,825,856** |
| …surviving the `l_suppkey = s_suppkey AND c_nationkey = s_nationkey` join | **72,985** |
| all orders in 1994 (any nation) | 2,275,919 |

Comparator: `harness/correctness_check.py` delegating to the bootstrap-verified
`harness/smoke_check.py` rules.

## 3-b. Headline timings

Regime `single-query-repeat WARM`; metadata connection mode
`single-connection-four-statements` (1 uncounted warmup + 3 measured, one direct
connection, no reconnect/prepare between measured statements, connection establishment
excluded). **Q05 is odd, so the engine-block order is CUBRID block first, then
PostgreSQL block** (section 12). Each statement fully consumed all 5 rows into a
campaign-owned fixed sink under `work/Q05/sink`; content hashes computed after the
timers stopped.

The reported block is **block 1 of the three blocks measured after the WARM steady
state was established** (section 5 explains why an earlier set of three blocks was
invalidated and re-measured).

| Field | CUBRID | PostgreSQL |
|---|---|---|
| WARM established after | 40-statement gate, half-split trend −1.2704% | 40-statement gate, half-split trend −1.0177% |
| warmup (uncounted) | 9.636000 s | 2.570110 s |
| measured run 1 | 9.652999 s | 2.568654 s |
| measured run 2 | 9.615000 s | 2.550927 s |
| measured run 3 | 9.570000 s | 2.564428 s |
| **median (headline)** | **9.615000 s** | **2.564428 s** |
| mean | 9.612666 s | 2.561336 s |
| within-block sd | 0.041549 s (0.432%) | 0.009259 s (0.361%) |
| sink bytes | 1835 | 555 |
| sink SHA-256 | `d0c81e14411d208d…` | see manifest |
| external load during block | mean 0.279 / max 1.084 → `CLEAN` | mean 0.152 / max 0.523 → `CLEAN` |

**Median wall ratio = 3.749374x (CUBRID / PostgreSQL) — PostgreSQL is 3.7494x faster.**
Correctness status `result-equivalent-at-SF10`; censoring status: not censored (both
engines far inside the 300 s timeout). No confidence interval is claimed from three
values.

Reproducibility across three independently gated blocks:

| Block | CUBRID median | PostgreSQL median | ratio |
|---|---|---|---|
| 1 (reported) | 9.615000 s | 2.564428 s | 3.749374x |
| 2 | 9.582000 s | 2.540045 s | 3.772374x |
| 3 | 9.590999 s | 2.527942 s | 3.793995x |
| spread | 0.344% | 1.436% | 1.2% |

Unlike Q04, block 1 is **not** the median of medians on both sides: the
median-of-medians pair is (9.590999, 2.540045) giving **3.775917x**, 0.71% above the
reported 3.749374x. Block 1 is reported because it is the first block accepted under
the gate, which is the campaign's stated convention; the 0.71% difference is recorded
rather than silently resolved in either direction, and it is smaller than the
block-to-block spread.

Measurement-resolution note: `csql` reports elapsed time at 1 ms granularity, so
CUBRID's headline carries ±0.010% quantization at this magnitude, far below its 0.432%
within-block sd; `psql` reports µs.

WARM proof (proved, not assumed):

| Evidence | CUBRID | PostgreSQL |
|---|---|---|
| steady state proved before timing | 40-statement pre-warm, half-split trend −1.27% within a 3.0% tolerance derived from this query's own stationary null distribution | 40-statement pre-warm, half-split trend −1.02% |
| independent convergence probe | 40 statements, median 9.528 s, half-to-half drift **−0.10%** | 40 statements, median 2.685 s, half-to-half drift **−0.03%** |
| device `read_bytes` (per `/proc/<pid>/io`) | 0.00 MB | 0.00 MB |
| engine buffer counters | trace `fetch 7,524,219 / ioread 65,169` per statement = **0.87% miss**; LRU pool conserved at 524,288 pages | `shared hit=2,618,227 read=0` — **zero physical reads** |
| `rchar` per statement | 1.0673 GB | 2.4 MB |
| read syscalls per statement | 65,285 (= trace `ioread` 65,169 + catalog) | 9,311 |
| warmup vs median | +0.22% | +0.22% |

Host-wide `/proc/diskstats` showed 26.90 MiB of device reads across the whole CUBRID
telemetry block against 1,018 MiB of page-cache reads, i.e. **>99.3% of CUBRID's misses
are served by the OS page cache and essentially none reach the device**; that counter
is host-wide and shared with other tenants, so it is an upper bound on campaign device
I/O, not an attribution.

## 4. Plan

**The two engines choose structurally different plans, and — for the first time in this
campaign — CUBRID's choice is the better one on both engines.**

CUBRID estimated (`SET OPTIMIZATION LEVEL 514`, verified non-executing: 0.02 s wall,
"There are no results"), `q5-plan-est-cubrid.out`:

```text
temp(order by)
  subplan: temp(group by)
    subplan: hash-join (inner join)          edge: term[1] AND term[4]
      outer: idx-join  ← idx-join ← idx-join ← idx-join
               outer: sscan  class: region   sargs: term[8]     cost 1 card 1
               inner: iscan  class: nation   index: fk_nation_region      cost 3
               inner: iscan  class: customer index: fk_customer_nation    cost 1744
               inner: iscan  class: orders   index: fk_orders_customer    sargs: term[7]
               inner: iscan  class: lineitem index: fk_lineitem_orders    cost 4
      inner: sscan class: supplier                                        cost 1531
      cost: 532621 card 31269
```

CUBRID actual (trace, `q5-trace-cubrid.out`, reported state):

```text
SELECT (time: 10846, fetch: 7524219, fetch_time: 2943, ioread: 65169)
  SCAN (temp) readrows: 72985
  GROUPBY (hash: true, rows: 5)   ORDERBY (sort: true)
  HASHJOIN (time: 10781, fetch: 7523848, ioread: 65169)
    BUILD (rows: 100000, method: hybrid)
    PROBE (readrows: 1825856, readkeys: 73040, rows: 72985)
          (parallel workers: 4)
    SUBQUERY (uncorrelated)
          (parallel workers: 2, time: 10691, fetch: 7436542, ioread: 65168)   ← 99% of the query
      SCAN (table: dba.region)                        readrows: 5, rows: 1
      SCAN (index: dba.nation.fk_nation_region)       readkeys: 1, rows: 5
      SCAN (index: dba.customer.fk_customer_nation)   readkeys: 5, rows: 300270
      SCAN (index: dba.orders.fk_orders_customer)     btree 5062 ms, readkeys: 300270,
                                                      rows: 3006380 (lookup 4082 ms, rows: 456771)
      SCAN (index: dba.lineitem.fk_lineitem_orders)   btree 4220 ms, readkeys: 456771,
                                                      rows: 1825856 (lookup 2172 ms)
      SCAN (table: dba.supplier)                      readrows: 100000
```

PostgreSQL native actual (`q5-plan-act-pg.out`): four Parallel Hash Joins over Parallel
Seq Scans, `Workers Planned/Launched: 5`, `Parallel Seq Scan on lineitem` reading all
**59,986,052** rows, `Buffers: shared hit=992,821 read=431,861`, `Execution Time
2962 ms`.

PostgreSQL controlled (`enable_seqscan=off`, `q5-plan-act-pg-idxnl.out`) — the shape used
as the card's cross-engine pair:

```text
Gather Merge  Workers Planned: 5  Launched: 5            Buffers: shared hit=2618227 read=0
  Parallel Hash Join                                     rows=12164.17 loops=6
    Nested Loop                                          rows=304309.33 loops=6
      Parallel Hash Join                                 rows=76128.50 loops=6
        Parallel Index Scan using orders_pkey            rows=379319.83 loops=6
        Hash Join (customer ⋈ nation ⋈ region)           rows=50045.00 loops=6
      Index Scan using idx_fk_lineitem_orders            rows=4.00 loops=456771
                                                         Index Searches: 456771
    Parallel Index Scan using supplier_pkey              rows=16666.67 loops=6
Execution Time: 1506.550 ms
```

Node-by-node agreement on the dominant path — this table is the `F_plan` anchor's
justification:

| Node | CUBRID native | PostgreSQL controlled | agreement |
|---|---|---|---|
| ASIA nations | 5 (`readkeys 1 → rows 5`) | 5 | exact |
| customers in ASIA | 300,270 | 300,270 (`50045 × 6`) | **exact** |
| orders after date filter | 456,771 | 456,771 (`76128.5 × 6`) | **exact** |
| inner access path on `lineitem` | B-tree `fk_lineitem_orders` | B-tree `idx_fk_lineitem_orders` | same index |
| index probes on that B-tree | 456,771 (`readkeys`) | 456,771 (`Index Searches`) | **exact** |
| rows from `lineitem` | 1,825,856 | 1,825,856 (`304309.33 × 6`) | **exact** |
| final join output | 72,985 | 72,985 (`12164.17 × 6`) | **exact** |
| groups | 5 | 5 | exact |
| **active execution units** | **1.03** | **5.43** | **5.28x apart** |

Where they still differ, and it is stated rather than hidden: CUBRID reaches
`customer` and `orders` through the FK indexes (touching only ASIA customers and only
their orders), while PostgreSQL — denied sequential scans — reads all 1,500,000
customers and all 15,000,000 orders through their primary keys and hash-joins them. So
**CUBRID's plan does strictly less logical work on the customer/orders path** and still
loses. That asymmetry is what `F_work = 1.111` measures, and it goes the wrong way for
CUBRID only because its index-NL on `orders` examines 3,006,380 index entries to yield
456,771 survivors.

Counterfactuals in both directions, identical variants grouped in one connection per
section 24 and, for the two used in the card, measured through the full gated block
protocol:

| Variant | Plan reached | Wall | Verdict |
|---|---|---|---|
| CUBRID native | FK index-NL chain + hash join | **9.615 s** (median of 3, gated block) | baseline |
| CUBRID `/*+ USE_HASH */` | all-hash over sequential scans (PostgreSQL's shape) | **11.039 s** (median of 3, gated block) | 1.148x worse — CUBRID's own choice is right |
| CUBRID `/*+ NO_PARALLEL_SCAN */` | unchanged shape, serial | 9.716 s | **+1.1%, i.e. no loss from removing parallelism** |
| CUBRID `/*+ PARALLEL(6) */` | unchanged | 9.605 s | no change |
| CUBRID `/*+ PARALLEL(12) */` | unchanged | 9.648 s | no change |
| CUBRID `/*+ NO_PARALLEL_SUBQUERY */` | unchanged | 9.740 s | no change |
| PostgreSQL native | four Parallel Hash Joins | **2.564428 s** (median of 3, gated block) | baseline |
| PostgreSQL `enable_seqscan=off` | index-NL on `lineitem`, CUBRID's shape | **1.425705 s** (median of 3, gated block) | **1.799x faster than its own native plan** |
| PostgreSQL `enable_hashjoin=off` | Merge Join + NL + Memoize | 2.285 s (`EXPLAIN ANALYZE`) | 1.30x faster than native |
| PostgreSQL `enable_hashjoin=off, enable_mergejoin=off` | full NL chain | 3.645 s | 1.23x worse |
| PostgreSQL `max_parallel_workers_per_gather=0` | serial hash | 18.599 s | 6.29x worse; parallel speedup 6.29x |

Three things follow, and the third is the whole report. First, **CUBRID's optimizer made
the right call** — its own alternative is 1.148x worse and the shape it chose is 1.799x
*better* on PostgreSQL. Second, **PostgreSQL's optimizer made the wrong call**, leaving
1.799x on the table by costing the 456,771-probe index path above four parallel hash
joins; that is a genuine PostgreSQL cost-model miss and is reported because a comparison
that only lists one engine's mistakes is not a comparison. Third, **the four CUBRID
parallelism hints move the wall by at most 1.1%, and serial execution is statistically
indistinguishable from `PARALLEL(12)`** — because, as section 7 shows in source, there
was never any parallelism on this plan to remove.

## 5. Execution telemetry

Non-headline diagnostic runs; per-TID sampler on CPUs `20-23`, weighted by actual sample
timestamp deltas. Three runs per configuration, each preceded by `harness/warm_establish.py`
and all load-gated; the recorded run is the **median-`U`** run. All runs retained in raw.

| Metric | CUBRID native | PostgreSQL controlled (idxnl) | PostgreSQL native | CUBRID `USE_HASH` |
|---|---|---|---|---|
| block walls, 4 statements | 38.35 / **37.95** / 38.13 s | **5.763** / 5.779 / 5.799 s | 10.858 / 10.809 / **10.764** s | **43.37** / 43.40 / 44.40 s |
| `executor_cpu` (per block) | 38.24 core-s | 31.27 core-s | 60.79 core-s | 274.28 core-s |
| `auxiliary_query_cpu` (per block) | 0.78 core-s | **0.00 core-s** | 8.95 core-s (`pg_io_worker` 7.88) | 22.87 core-s |
| `total_query_cpu` (per block) | **39.02 core-s** | **31.27 core-s** | 69.08 core-s | 296.25 core-s |
| `U` = CPU_block / Σwalls | **1.02822** | **5.42598** | 6.41800 | 6.76597 |
| `total_query_cpu` per median statement | **9.8863 core-s** | **7.7358 core-s** | 16.4585 core-s | 74.6895 core-s |
| planned workers | 6 (`parallelism=6`) | 5 + leader | 5 + leader | 6 (`parallelism=6`) |
| launched workers | trace: **2** on the join chain, 4 on the hash probe | 5 + leader = 6 | 5 + leader = 6 | 6 |
| max simultaneous active units | 3.1810 | 5.63 | 6.72 | **12.3064** |
| time-weighted active units (TWU) | **1.0263** | **5.5433** | 6.5416 | 6.7711 |
| serial tail | 9.554 s | 0.233 s | 0.232 s | 0.00 s |
| `rchar` per statement | 1.0673 GB | 2.4 MB | 3.3986 GB | 16.6862 GB |
| read syscalls per statement | 65,285 | 9,311 | 370,520 | 1,018,586 |
| device read | ~0 (host-wide 26.9 MiB/block) | 0.00 MiB | 0.00 MiB | 0.03 MiB |
| `unattributed_background` | none claimed | none claimed | none claimed | none claimed |

**`U` and TWU agree to 0.19% on CUBRID (1.02822 vs 1.0263) and `perf stat` independently
reports 1.043 CPUs utilized.** Three instruments, three ways of measuring, one answer:
CUBRID executes Q05's chosen plan on approximately one core. Its serial tail is
9.554 s — the entire statement. Against a configured `parallelism=6`, that is the
finding.

Buffer state is explicitly **not** Q05's story, which is worth saying because it was
Q04's: at the reported state CUBRID misses 65,169 of 7,524,219 page fixes (0.87%) and
PostgreSQL's controlled plan takes **zero** physical reads with 2,618,227 buffer
accesses. Both engines are resident. PostgreSQL's controlled plan working set is
directly measured (`q5-workingset.out`): 395,737 distinct `lineitem` heap pages +
95,024 index pages + 261,264 `orders` heap + 41,131 `orders_pkey` + 35,984 `customer`
heap + 4,116 `customer_pkey` + 2,256 + 276 = **835,788 of 1,048,576 buffers, 20.3%
headroom**, which is why `read=0`.

### The shared-memory contract is load-bearing on Q05, and here is the number

Section 9 mandates recording `dynamic_shared_memory_type=mmap` whenever a Parallel Hash
Join or large gather is in either engine's natural plan. Q05 goes further than
recording. Polling `pg_dynshmem` at 20 Hz through one native execution
(`q5-shared-memory-verification.txt`) measures a **DSM peak of 96,943k — 1.5297x the
63,372k available in this host's `/dev/shm`**. Under the PostgreSQL default
`dynamic_shared_memory_type=posix` that allocation lands in `/dev/shm` and Q05's natural
plan would fail outright with `could not resize shared memory segment`, not run slowly.
Q04 recorded a peak of 48,412k against the same 64,000k mount; **Q05 is the first query
in this campaign whose measured peak actually exceeds the limit**, so the contract that
section 9 justified on precautionary grounds is now justified on evidence. Without it,
Q05's PostgreSQL baseline would not exist and every factor in this card would be
uncomputable.

### WARM establishment: three defects found, all of which changed a number

**1. The reported headline is the second set of blocks; the first three were invalidated
(changed the headline by 12.2%).** Three CUBRID blocks were accepted at medians
10.702 / 10.712 / 10.673 s, each preceded by a converged 20-statement warm. A 40-statement
probe then falsified the level: the true single-query-repeat steady state is **9.528 s**
(half-to-half drift −0.10%). The accepted blocks sat 12.2% high. Per section 12 a failed
WARM gate invalidates the run, so all six blocks (both engines, for a coherent
replacement set) were invalidated, retained under `pre-restart-pool/` with
`INVALID.json`, and re-measured. The ratio moved from 4.048x to 3.749x — a 7.4% error
had it stood.

**2. CUBRID's buffer pool has a history-dependent equilibrium it cannot leave (the cause
of defect 1).** The same query, same data, same plan measures:

| Pool history | Level | Miss count / statement |
|---|---|---|
| restart + native-only, ≥80 statements | **9.47–9.68 s** | 65,169 |
| restart + native-only, ~40 statements (intermediate plateau) | 11.08 s | — |
| carrying the correctness/ground-truth/plan workloads | 10.67–10.71 s | 619,299 |
| after ONE 24-statement `/*+ USE_HASH */` full-scan block | **13.27–13.55 s** | ~1,631,608 |

The post-`USE_HASH` level is *stable over 60 further native statements and never
self-recovers*; only `cubrid-server-ctl.sh restart` plus native-only repetition returns
it to 9.5 s. That is a **25x swing in miss count and a 42% swing in wall time decided
purely by what the pool saw earlier**. The 11.08 s plateau reproduced across two
independent restarts. The obvious alternative explanation — cross-engine OS page-cache
interference from the section 12 alternating block order — was **tested and rejected**:
a converged CUBRID re-probed immediately after a 40-statement PostgreSQL workload
measured 9.596 s against 9.528 s, **+0.71%**. This is recorded as a new Q05 relation on
IMP-002.

**3. The WARM gate itself was measuring the wrong statistic (changed which blocks were
accepted).** `harness/warm_establish.py` compared two adjacent 4-statement window
medians at a 1.0% tolerance. Evaluated against Q05's **known-converged** 40-statement
probe, that statistic produces up to **3.74%** — it rejects a query that has in fact
converged, the precise failure its own docstring warned about. The cause is that Q05's
series is not white noise: it contains multi-statement plateau excursions (statements
13–18 of `q5-convergence-cubrid.out` sit 2.6% below baseline), so a 4-sample median is
not a stable level estimate. The replacement compares the medians of the two halves of
the whole series, and its threshold was **derived, not guessed**: a moving-block
bootstrap (block length 6 ≥ the observed plateau length) over the stationary probes
gives

| series length | CUBRID null p95 / max | PostgreSQL null p95 / max |
|---|---|---|
| n = 20 | 2.68% / 3.49% | 0.92% / 1.28% |
| n = 40 | 2.16% / 2.99% | 0.73% / 1.17% |

against a genuinely warming 40-statement series scoring **13.17%**. At n=20 null and
signal *overlap* and no threshold can separate them — which is why the statement count,
not the tolerance, was the real fix. Q05 therefore runs the gate at 40 statements with
`LEVEL_TOL = 3.0%` (above the n=40 stationary null max of 2.99%, 4.4x below the warming
signal) and `SPREAD_SANITY = 5.0%` (above the 4.24% raw spread the converged probe
itself shows). Validated against ten recorded series with known ground truth: the new
gate is correct on **3/3 at n=40** and 8/10 overall, both misses being n=20 cases the
bootstrap predicts are unresolvable. All six re-measured blocks were then accepted on
the first attempt.

**4. A stale-canonical-file trap in `measure_block.sh` silently duplicated a
measurement.** When every attempt is rejected the script exits non-zero but used to
leave the previous run's canonical artifacts in place, so a caller copying
`Q05-cubrid-headline.json` into a per-block name recorded the earlier block again. This
actually happened here: two "new" CUBRID blocks were byte-identical
(`sha256 1768a44e2222ca58`) to an already-invalidated block. Caught by hashing the
per-block files against each other, not by inspection. Fixed by removing the canonical
names at the start of a run, so a rejected run leaves a missing file instead of a
duplicated measurement.

## 6. Profile

Non-headline. `perf` attached to verified PID sets, never all-CPU. CUBRID: `-p 1612732`
(`cub_server`, 26 TIDs, all query threads inside that process). PostgreSQL: `perf stat`
on the discovered leader plus exactly its 5 parallel workers; `perf record` on
`postmaster + leader`, relying on perf's inherit-on-fork because worker PIDs are
transient per statement. Drivers replayed the identical statement in one connection
(CUBRID 10 repeats, PostgreSQL 45), grouping identical variants per section 24. **The
PostgreSQL profile used for the comparison is the controlled index-NL plan**, matching
the card's cross-engine pair; the native-plan profile is retained separately.

Coverage validation against `perf stat`: CUBRID 26,733 samples / 39 symbol lines above
0.4% / **0 `[unknown]`** / 0 lost; PostgreSQL-idxnl 140,365 samples / **0 `[unknown]`** /
0 lost. Driver completion verified (10 `csql` result-set markers; 225 non-empty
PostgreSQL sink lines = 45 × 5 rows).

| Metric | CUBRID native | PostgreSQL controlled (idxnl) |
|---|---|---|
| cycles (25.0 s window) | 74,523,372,598 | 78,788,984,361 |
| instructions | 91,377,430,283 | 120,587,681,407 |
| **IPC** | **1.23** | **1.53** |
| frequency | 2.858 GHz | 2.794 GHz |
| task-clock | 26,074.18 ms | 28,198.97 ms |
| CPUs utilized | **1.043** | 1.128 (partial set — see caveat) |
| context-switches | 32,779 | 23,469 |
| instructions per core-second | 3.5044e9 | 4.2762e9 |
| instructions per statement | 34.64e9 | 33.08e9 |

Caveat, as on Q04: PostgreSQL's "CPUs utilized" of 1.128 is **not** its parallel
utilization — the leader persists across the driver's 45 statements but the 5 workers
are per-statement, so the fixed PID set covers one statement's workers. Utilization
comes from telemetry (`U` 5.42598, TWU 5.5433), not from this row. CUBRID's 1.043 *is*
its utilization, because all its query threads live in the one attached process — which
is precisely why the two numbers can be compared for CUBRID and not for PostgreSQL.

**`F_cpu` decomposes into IPC, not instruction count** — the opposite of Q04. The two
engines execute nearly the same number of instructions per statement (34.64e9 vs
33.08e9, **1.047x**) and differ in IPC (1.23 vs 1.53, **1.244x**);
`1.047 × 1.244 = 1.302` against the measured `F_cpu` of 1.278, closing to 1.9% from an
entirely separate instrument. CUBRID is not doing more work per tuple here; it is
stalling more per instruction, which is what a single thread chasing a 456,771-probe
random index walk with no memory-level parallelism from sibling workers looks like.

Top self cost, CUBRID (`profile-cubrid-flat.txt`):
`pgbuf_fix_release` **18.98%**, `spage_get_record` 7.29%,
`__memmove_evex_unaligned_erms` 5.46%, `pgbuf_lru_boost_bcb` 4.62%,
`btree_search_leaf_page` 3.97%, `or_mvcc_get_repid_and_flags` 3.46%,
`heap_attrinfo_read_dbvalues` 2.92%, `rep_movs_alternative` [k] 2.65%, `pgbuf_unfix`
2.56%, `btree_search_nonleaf_page` 2.29%, `qdata_copy_db_value_to_tuple_value` 1.44%,
`__pthread_mutex_unlock_usercnt` 1.43%, `heap_prepare_get_context` 1.30%,
`__pthread_mutex_trylock` 1.24%, `qexec_execute_scan` 1.19%, `btree_compare_key` 1.17%,
`qdata_generate_tuple_desc_for_valptr_list` 1.13%, `__pthread_mutex_lock` 1.07%,
`eval_pred` 1.05%, `fetch_val_list` 1.04%.

Top self cost, PostgreSQL controlled (`profile-pg-idxnl-flat.txt`):
`heap_hot_search_buffer` **12.04%**, `ExecParallelScanHashBucket` 7.92%,
`next_uptodate_folio` [k] 7.37%, `ExecInterpExpr` 4.33%,
`tts_buffer_heap_getsomeattrs` 3.79%, `_bt_compare` 3.64%, `LockBufferInternal` 3.04%,
`hash_search_with_hash_value` 2.85%, `LWLockAttemptLock` 2.83%,
`folio_remove_rmap_ptes` [k] 2.43%, `filemap_map_pages` [k] 2.35%, `BufferLockUnlock`
2.25%, `PinBuffer` 2.20%, `_compound_head` [k] 2.03%, `heap_page_prune_opt` 1.96%,
`folios_put_refs` [k] 1.84%, `heapam_index_fetch_tuple` 1.65%,
`HeapTupleSatisfiesVisibility` 1.46%, `_bt_readpage` 1.37%, `zap_present_ptes` [k] 1.24%.

Banded (each band against its own engine's `total_query_cpu`: CUBRID 9.8863 core-s,
PostgreSQL 7.7358 core-s):

| Band | CUBRID | PostgreSQL (idxnl) |
|---|---|---|
| buffer fix / pin / unfix / LRU | **26.85% = 2.654 core-s** | 10.32% = 0.798 core-s |
| record & attribute extraction | 15.94% = 1.576 core-s | 3.79% = 0.293 core-s |
| heap tuple fetch / visibility / prune | (inside extraction band) | **17.11% = 1.324 core-s** |
| memmove / page copy | 8.11% = 0.802 core-s | — |
| B-tree descent | 7.43% = 0.735 core-s | 5.01% = 0.388 core-s |
| hash-join probe | 1.66% = 0.164 core-s | 10.77% = 0.833 core-s |
| mutex / lightweight locking | 3.74% = 0.370 core-s | (inside buffer band) |
| intermediate tuple materialization | 3.61% = 0.357 core-s | — |
| predicate / expression evaluation | 1.05% = 0.104 core-s | 4.33% = 0.335 core-s |
| **parallel-worker page-table churn** | **0.00 core-s (threaded model)** | **17.26% = 1.335 core-s** |
| banded subtotal | 68.39% = 6.762 core-s | 68.59% = 5.306 core-s |

Two observations that cut against CUBRID and one that cuts for it. Against: CUBRID
spends **2.654 core-s in the buffer manager against PostgreSQL's 0.798** — 3.3x — on a
plan where its miss rate is only 0.87%, so this is the *hit* path, not I/O; and
`pgbuf_fix_release` alone at 18.98% is the single largest symbol in either profile,
consistent with 7,524,219 page fixes per statement against PostgreSQL's 2,618,227
(2.87x). For CUBRID: PostgreSQL again burns **17.26% = 1.335 core-s on page-table setup
and teardown for workers it forks per statement** — the Q04 finding reproducing on a
different plan — which CUBRID's threaded model does not pay at all. Net of that band,
`F_cpu` would be **1.545x** rather than 1.278x, so PostgreSQL's win here is achieved
while wasting a sixth of its own CPU on process-model overhead.

## 7. Source contrast

| Item | CUBRID file:line | PostgreSQL file:line | Difference | Class |
|---|---|---|---|---|
| Parallel degree of an uncorrelated subquery | `src/query/parallel/px_parallel.cpp:85-109` `compute_parallel_degree()`, `case parallel_type::SUBQUERY`. Lines **89-92** are the decision: `/* TODO: degree fixed at 1 (main + gather = 2) to be revised when exact parallel count is available for many uncorrelated subqueries */ auto_degree = 1;`. Lines **99-103** discard an explicit hint: `else if ((UINT32) hint_degree >= start_degree) { /* hint ignored, degree fixed for subquery, ignore the parallelism parameter */ return auto_degree; }`. By contrast the SCAN path at `src/query/parallel/px_scan/px_scan.cpp:416-419` derives its degree from `num_data_pages`. Introduced by `ec77e0bef [CBRD-26311]` | `src/backend/optimizer/path/allpaths.c:830` `set_rel_consider_parallel()` marks a rel parallel-safe and `:2919-2922` extends the same marking to subquery rels, so a subquery is **not** a parallelism barrier; `:608` `generate_useful_gather_paths()` places the Gather **above an arbitrary parallel-safe plan branch** rather than at a scan; `src/backend/executor/execParallel.c:1514` `ParallelQueryMain()` → `:1583` `ExecutorRun()` runs the *whole* branch in each worker; `src/backend/executor/nodeNestloop.c:61` `ExecNestLoop()` needs no parallel-specific variant at all | Q05's entire 5-table index-NL chain is folded into an uncorrelated subquery, so **99% of the query runs at a hardcoded degree of 1** while the trivial hash-probe above it parallelizes normally. Measured: `U` 1.02822 vs 5.42598, TWU 1.0263 vs 5.5433, `perf` 1.043 CPUs utilized. `F_units = 5.2771x`, the largest single factor isolated anywhere in this campaign. The source comment predicts the measurement exactly: `PARALLEL(6)` and `PARALLEL(12)` leave the subquery node at `parallel workers: 2` and move the wall by ≤1.1% | structural absence |
| Data-page fix on the buffer-hit path | `src/storage/page_buffer.c:2211` `pgbuf_fix_release()` — **18.98% of CUBRID's profile**, the largest single symbol, reached 7,524,219 times per statement with only 0.87% missing; LRU bookkeeping on the hit path adds `pgbuf_lru_boost_bcb` 4.62% and `pgbuf_unfix` 2.56% | `src/backend/storage/buffer/bufmgr.c` `PinBuffer()` (2.20%) + `LockBufferInternal()` (3.04%) + `BufferLockUnlock()` (2.25%) + `LWLockAttemptLock()` (2.83%), reached 2,618,227 times per statement with **0** misses | 2.654 vs 0.798 core-s (3.3x) for 2.87x the page fixes, i.e. comparable per-fix cost but far more fixes: CUBRID's index-NL re-fixes a page per probe where PostgreSQL's hash side touches each page once. Not an I/O finding — both engines are resident | same stage, lower measured cost |
| Parallel execution unit lifecycle | Threaded: parallel scan units are pooled threads inside `cub_server` (one address space, one page table). No per-statement address-space construction appears anywhere in the Q05 profile | `src/backend/postmaster/postmaster.c` `postmaster_child_launch()` → `src/backend/access/transam/parallel.c` `ParallelWorkerMain()` forks a process per statement; the kernel faults in each child's PTEs (`filemap_map_pages`/`next_uptodate_folio`, 9.72%) and tears them down at `exit_mmap`→`zap_pte_range` (`folio_remove_rmap_ptes`/`folios_put_refs`/`zap_present_ptes`, 7.54%) | **17.26% = 1.335 core-s of PostgreSQL's query CPU against 0.00 on CUBRID.** The one large band where CUBRID's architecture is measurably ahead; net of it `F_cpu` would be 1.545x rather than 1.278x. Reproduces Q04's finding on a completely different plan shape | same stage, lower measured cost (CUBRID favoured) |
| Buffer replacement equilibrium after a competing scan | `src/storage/page_buffer.c` victim selection and LRU zone promotion (`pgbuf_get_victim`, `pgbuf_lru_boost_bcb`, `pgbuf_unlatch_void_zone_bcb`) | `src/backend/storage/buffer/freelist.c:442` `BAS_BULKREAD` ring bounds a large scan's footprint so it cannot evict the resident set | One 24-statement `USE_HASH` full-scan block moves CUBRID's native-plan miss count from 65,169 to ~1,631,608 per statement (**25x**) and its wall from 9.5 s to 13.4 s (**+41%**), and the pool never recovers without a restart. PostgreSQL shows no equivalent: its 40-statement probe drifts −0.03% | structural absence |
| Parallel-scan trace statistics for a nested chain | `src/query/parallel/px_scan/px_scan_trace_handler.cpp:492-500` per-`scan_ptr`-level merge overlapping `xasl_merge_stats()`'s own subtree walk (`src/xasl/xasl_iteration.cpp:205`, `xasl_iteration.hpp:189-191`) | `src/backend/executor/execParallel.c:1173` `planstate_tree_walker()` visits each PlanState exactly once; `:1115` `InstrAggNode()` aggregates one worker slot per visited node | Q05 is a **second negative control** for IMP-005 and pins the boundary from the other side: it has the campaign's deepest `scan_ptr` chain (5 levels) yet every counter is exact against ground truth, because the chain runs at degree 1 and never enters the parallel-worker merge. Fixing IMP-009 would expose this chain to the multiplication for the first time | common to both engines (on this query) |

## 8. Causal decomposition details

1. **CUBRID chose the better plan and it is not close.** Its own alternative is 1.148x
   worse (`USE_HASH`, 11.039 s vs 9.615 s) and the shape it chose is **1.799x faster on
   PostgreSQL** than PostgreSQL's own choice (1.425705 s vs 2.564428 s). `F_plan` is
   0.5560 — the plan factor is a *credit* to CUBRID. Any account of Q05 that starts
   "CUBRID picked a bad plan" is refuted by a direct A/B on both engines.
2. **The work is nearly the same and slightly favours PostgreSQL's bookkeeping.**
   `F_work = 1.111`. CUBRID's plan touches strictly fewer customer and order rows (it
   reaches only ASIA customers through `fk_customer_nation`), but its index-NL on
   `orders` examines 3,006,380 index entries to yield 456,771 survivors, which is what
   puts `F_work` above 1. On the dominant `lineitem` path the two engines agree
   **exactly**: 456,771 probes, 1,825,856 rows.
3. **The per-tuple cost is nearly the same.** `F_cost = 1.150` — 1007.3 ns vs 876.0 ns
   per tuple touch. Combined with (2), the whole CPU story is `F_cpu = 1.278`.
4. **The entire loss is parallelism.** `F_units = 5.2771`, and it is measured three ways
   that agree: `U` 1.02822 vs 5.42598, TWU 1.0263 vs 5.5433, and `perf stat` 1.043 CPUs
   utilized on the verified CUBRID PID set. The root cause is pinned to a hardcode in
   the pinned tree — `px_parallel.cpp:89-92` fixes an uncorrelated subquery's degree at
   1 and `:99-103` explicitly discards a hint — and the source comment's own prediction
   is confirmed by measurement: `PARALLEL(6)` and `PARALLEL(12)` leave the subquery at
   2 workers and change the wall by ≤1.1%.
5. **Localisation of the 2.15 core-s CPU excess** (9.8863 vs 7.7358 core-s). It is small
   and it is not where the wall time went, which is the point. The two contributing
   bands are the buffer-fix hit path (2.654 vs 0.798 core-s, from 2.87x the page fixes)
   and record/attribute extraction (1.576 vs 0.293 core-s); against these PostgreSQL
   *adds* 1.335 core-s of parallel-worker page-table churn that CUBRID does not pay,
   which is why the net is only 1.278x.
6. **Explanations considered and rejected, with the number that rejected each.**
   - *"CUBRID picked a worse plan."* Rejected: its shape is 1.799x **faster** when
     PostgreSQL is forced onto it, and its own hash alternative is 1.148x worse.
   - *"CUBRID does more work."* Rejected: `F_work = 1.111`, and on the dominant path the
     probe counts are **identical** (456,771 on both).
   - *"CUBRID's per-tuple cost is the problem."* Rejected: `F_cost = 1.150`, and
     instructions per statement differ by only **4.7%** (34.64e9 vs 33.08e9).
   - *"CUBRID is buffer/IO-bound, as in Q04."* Rejected: at the reported state it misses
     **0.87%** of 7,524,219 fixes and takes essentially zero device reads; PostgreSQL's
     controlled plan takes **zero** physical reads. Buffer misses cost Q05 nothing at
     steady state.
   - *"CUBRID's parallelism is configured too low."* Rejected: `parallelism=6`, the same
     configured cap as PostgreSQL's 5+leader. The cap is not what binds — a hardcoded
     degree of 1 for subqueries is, and it ignores both the parameter and the hint.
   - *"Then forcing the hint will fix it."* Rejected by direct A/B: `PARALLEL(6)`
     9.605 s, `PARALLEL(12)` 9.648 s, native 9.615 s, serial 9.716 s — a 1.1% band. The
     source says why at `px_parallel.cpp:101`.
   - *"The 4.048x first measured is the answer."* Rejected: that came from an unconverged
     buffer pool; the converged answer is 3.749x. Recorded in full in section 5 rather
     than quietly replaced.
   - *"Cross-engine OS page-cache interference from the alternating block order explains
     the level shifts."* Rejected by controlled probe: **+0.71%**.
   - *"IMP-005 (trace double-counting) corrupts Q05's `W`."* Rejected: every counter is
     exact against independently derived ground truth, because the chain runs at degree
     1. Recorded as a negative control, and as a **dependency**: fixing IMP-009 would
     expose it.
   - *"IMP-008 (per-row domain re-resolution) drives Q05."* Rejected as material:
     `eval_pred` is 1.05% and the whole predicate band is 0.104 core-s, because Q05's
     only sargs are one date range and one `r_name` equality on a 5-row table. No Q05
     relation was added to IMP-008 rather than record one the profile does not support.
   - *"PostgreSQL's plan is optimal and CUBRID should copy it."* Rejected, and inverted:
     PostgreSQL leaves **1.799x** on the table by costing the index path above four
     parallel hash joins. Both engines' optimizers are graded here, not just CUBRID's.

Error budget and closure: the reconstruction residual is 0.000000% and is declared an
identity, so closure rests on the independent quantities. `U` reproduces within 1.3%
across three runs per configuration; TWU agrees with `U` to 0.19% (CUBRID) and 2.2%
(PostgreSQL, the 0.233 s serial tail); `perf` gives a third reading of CUBRID's
utilization at 1.043 against `U` 1.028 (**1.4%**); `F_cpu` is independently reproduced
from instruction counts and IPC to **1.9%**; and the entire decomposition is reproduced
by a second, differently-anchored counterfactual (anchor B) that also reconstructs
exactly. Block-to-block reproducibility of `R_wall` is 3.7494–3.7940 (**1.2%**). The
card is closed.

## 9. Improvements

Registry state before Q05: `IMP-001`…`IMP-008`, `next_id: IMP-009`. Deduplication: the
Git ledger was searched by title, both source locations and root cause. `IMP-001`
(NUMERIC accumulation), `IMP-003` (LIKE selectivity), `IMP-004` (UTF-8 LIKE matcher),
`IMP-006` (list-file materialization) and `IMP-008` (sarg domain re-resolution) touch no
path Q05 exercises materially — `IMP-008` was **considered and rejected** for a Q05
relation on a measured 1.05%. `IMP-002` and `IMP-005` are extended rather than
duplicated. One new ID was allocated; `next_id` advances to `IMP-010`. No old-campaign
candidate ID was consulted.

| ID | Root cause | Priority | Category | Status | Evidence type | Effect on Q05 |
|---|---|---|---|---|---|---|
| `IMP-009` | Uncorrelated-subquery parallel degree is hardcoded to 1 and explicitly ignores both `parallelism` and an explicit `PARALLEL` hint, so a whole join chain folded into a subquery runs single-threaded | **P0** | parallelism | `measured` | direct A/B | `F_units = 5.2771x` — the entire loss; `U` 1.028 vs 5.426 at a plan matched to 456,771 identical probes |
| `IMP-002` | (existing) Buffer replacement fails to retain a marginal working set — Q05 adds a **distinct failure mode**: a history-dependent equilibrium the pool cannot leave without a restart | P1 | buffer/IO | `measured` | direct A/B | no steady-state cost (0.87% miss), but a 25x miss swing and +41% wall swing decided by pool history |
| `IMP-005` | (existing) Parallel-scan trace statistics multiply a nested chain's counters | P2 | parallelism | `measured` | direct A/B | second **negative control**; also a hard **dependency** — fixing IMP-009 exposes Q05's 5-level chain to the defect |

**Ranking justification.** `IMP-009` outranks everything by an order of magnitude:
5.2771x against 1.278x for all CPU effects at the matched plan combined. It is also the
only Q05 candidate whose fix would change the headline. `IMP-002`'s Q05 relation ranks
second not on cost — it costs nothing at steady state — but because it is a *correctness
of measurement* hazard that already invalidated three gated blocks, and because a 25x
miss swing on identical inputs is a policy defect regardless of whether this query pays
for it. `IMP-005` ranks last on its own merits but is elevated in sequencing: it must be
fixed **before or with** IMP-009. The three are **not summed**: IMP-009 is a wall-time
factor at constant CPU, IMP-002's Q05 evidence is a warm-up-state effect with zero
steady-state cost, and IMP-005 has no runtime cost at all, so there is no overlapping
effect to double-count.

### IMP-009 — an entire join chain runs single-threaded because its container is a subquery

- **Mechanism, CUBRID.** `compute_parallel_degree()`
  (`src/query/parallel/px_parallel.cpp:85-109`) returns a fixed degree for
  `parallel_type::SUBQUERY`: line 92 is `auto_degree = 1`, guarded by the maintainers'
  own TODO at lines 89-91 (*"degree fixed at 1 (main + gather = 2) to be revised when
  exact parallel count is available for many uncorrelated subqueries"*). Lines 99-103
  then discard an explicit hint with the comment *"hint ignored, degree fixed for
  subquery, ignore the parallelism parameter"*. The SCAN path
  (`px_scan.cpp:416-419`) by contrast derives its degree from `num_data_pages`. Q05's
  optimizer folds the whole `region → nation → customer → orders → lineitem` index-NL
  chain into an uncorrelated subquery feeding a hash-join probe, so the node holding
  99% of the query's time gets degree 1 while the probe above it gets 4 workers.
- **Mechanism, PostgreSQL.** Parallelism is a property of the plan *branch*, not of a
  scan node: `set_rel_consider_parallel()` (`allpaths.c:830`, extended to subquery rels
  at `:2919-2922`) makes a subquery no barrier at all;
  `generate_useful_gather_paths()` (`:608`) places the Gather above an arbitrary
  parallel-safe branch; and `ParallelQueryMain()` → `ExecutorRun()`
  (`execParallel.c:1514`, `:1583`) runs that whole branch in every worker.
  `ExecNestLoop()` (`nodeNestloop.c:61`) therefore needs no parallel variant — it
  inherits parallelism from where it sits, which is how PostgreSQL drives the same
  456,771 index probes across 6 units.
- **Why the direction follows.** The plans are matched node-for-node on the dominant
  path and the CPU differs by only 1.278x, so the 6.744x residual wall gap on that pair
  can only be concurrency. And the mechanism is not inferred from the gap: it is read
  from the source and then confirmed by the source's own prediction — hints are inert
  (`PARALLEL(6)` 9.605 s, `PARALLEL(12)` 9.648 s, serial 9.716 s, native 9.615 s) and
  the trace shows `parallel workers: 2` on the subquery under every one of them.
- **Evidence event and denominator.** Active execution units = CPU-seconds per
  wall-second over the section 12 block; denominator the block's summed statement walls.
  CUBRID 39.02 core-s / 37.95 s = 1.02822; PostgreSQL 31.27 core-s / 5.763 s = 5.42598.
  Raw: `Q05-cubrid-headline-telemetry-run{1,2,3}.json`,
  `Q05-postgresql-idxnl-headline-telemetry-run{1,2,3}.json`, `q5-trace-cubrid.out`,
  `variants/out2-PARALLEL6.txt`, `variants/out2-PARALLEL12.txt`, `perf-stat-cubrid.txt`.
- **Effect range.** `F_units = 5.2771x` of the 3.7494x total. Upper bound on what perfect
  parallelization recovers; the realistic target is PostgreSQL's own 5.43 units on the
  same plan, which would put CUBRID at 9.8863 core-s / 5.43 = **1.82 s**, i.e. faster
  than PostgreSQL's native 2.564 s. Evidence type: direct A/B.
- **Implementation direction.** Replace the fixed `auto_degree = 1` with a degree derived
  from the subquery's estimated input size, exactly as the SCAN branch already derives
  one, and stop discarding the hint at `:99-103`. Cheapest first step, independently
  shippable and directly testable on Q05: **honour an explicit `PARALLEL(n)` hint for a
  subquery**, converting a hardcode into a user-controllable degree so the
  auto-derivation can be validated against measurement before becoming the default.
- **Correctness/regression risk.** Medium. Nothing changes semantically for a read-only
  uncorrelated block, but the body must be proved parallel-safe by the existing
  `px_scan_checker` rules, and — critically — raising this degree puts Q05's 5-level
  `scan_ptr` chain onto the trace-merge path that IMP-005 documents as multiplying
  counters (k−1) times. **IMP-005 must be fixed first or validated together.**
- **Validation criteria.** (1) Q01–Q22 results byte-identical; Q05 output byte-identical
  to `sink-Q05-cubrid-headline-block1.out`. (2) Q05's trace reports the uncorrelated
  subquery with >2 workers **and** counters still exactly 5 / 300,270 / 3,006,380 /
  456,771 / 1,825,856 / 72,985 (the IMP-005 regression pin). (3) `U` rises from 1.028
  toward 5.43 under `harness/headline_telemetry.py`. (4) Q05 CUBRID median improves
  against 9.615 s under the same `warm_establish` + `measure_block` protocol with the
  40-statement WARM gate still `CONVERGED`. (5) No regression on Q04, whose *correlated*
  `EXISTS` subquery is a different path.
- **Priority.** **P0** — 5.2771x measured, the largest factor isolated anywhere in this
  campaign, and it is the whole of Q05's loss.
- **Difficulty.** **High** — the degree change is one line, but making a multi-level
  index-NL chain execute correctly across workers requires input partitioning for the
  driving scan, per-worker `scan_ptr` state, and a correct statistics merge. The
  hint-honouring first step is **low**.
- **Upstream precedent.** Direct and same-direction: `978b628c8 [CBRD-26931] "Parallelize
  uncorrelated scalar subquery inner scan" (#7316)` fixed precisely this defect class for
  uncorrelated **scalar** subqueries, after TPC-H Q15 regressed from 12.2 s to 24.2 s
  because an identical `lineitem` scan ran with 10 workers in a `FROM`-clause derived
  table and 1 worker inside a scalar subquery. Q05 is the same root cause in the branch
  that fix did not cover — a **non-scalar** uncorrelated subquery consumed by a join —
  and `px_parallel.cpp:89-91` still carries the TODO saying the fixed degree is to be
  revised.

### IMP-002 — Q05 relation: a pool equilibrium that cannot be left without a restart

Q05 adds **no** steady-state cost evidence: 65,169 misses of 7,524,219 fixes (0.87%),
zero device reads. What it adds is that the level the pool settles at is decided by
workload history and is not self-correcting — 9.47–9.68 s on a native-only pool,
10.67–10.71 s carrying earlier workloads, and **13.27–13.55 s after one 24-statement
`USE_HASH` full-scan block, stable over 60 further native statements and never
recovering**. Miss counts across those states: 65,169 / 619,299 / ~1,631,608, a **25x
swing** on identical data, query and plan. Only a server restart plus native-only
repetition returns it. PostgreSQL shows no equivalent (40-statement probe drift
−0.03%), and cross-engine OS page-cache interference was tested and rejected at +0.71%.
Recorded as a policy defect and as the measurement hazard that invalidated Q05's first
three gated blocks. Full fields in `reports/improvement-registry.json`.

### IMP-005 — Q05 negative control and a sequencing dependency

Q05 has the campaign's deepest `scan_ptr` chain — five nested index scans — which by the
documented (k−1)x rule should overstate the level-5 counters by 4x. Every counter is
instead **exact** against independently derived ground truth (5 / 300,270 / 3,006,380 /
456,771 / 1,825,856 / 72,985). The reason is structural and ties the two candidates
together: the chain runs inside the degree-1 subquery of IMP-009, so the parallel-worker
stats merge that produces the multiplication is never entered. This **scopes** the defect
from a second direction — it needs both a `scan_ptr` chain *and* parallel workers on it —
and creates a hard ordering constraint: fixing IMP-009 would expose this chain to the
multiplication for the first time. A Q05 regression pin was added to IMP-005's validation
criteria.

None of the candidates is marked `validated`: no correctness evidence for a fix exists
yet. Full fields in `reports/improvement-registry.json`.

## 10. Evidence index

Format: `claim → raw file → formula → evidence type → SHA-256`.
All paths are under `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q05/`; byte sizes and
full hashes for all **373** artifacts (289 valid, 84 retained-invalid) are in
`reports/Q05/raw-manifest.json`.

| Claim | Raw file | Formula / basis | Evidence type | SHA-256 |
|---|---|---|---|---|
| preflight: ownership OK, 34 TIDs 0 off-cpuset, 8FK/8-btree 8/8/8 convalidated, row counts, contract values, provenance, external load 0.772 PASS | `preflight-Q05.txt` | direct capture | direct A/B | see manifest |
| SSOT re-pin 5912f065→d19dca41 is section-21-only; no measurement-contract term changed | `q5-ssot-repin.txt` | `git diff` over the two blobs | direct A/B | see manifest |
| post-block gate: 0 orphans, 35 TIDs 0 off-cpuset, pool conserved at 524,288 pages | `q5-postcheck.txt` | direct capture | direct A/B | see manifest |
| Q05 `result-equivalent-at-SF10`, 5 rows ordered, tolerance never entered | `q5-correctness.json`, `q5-correctness-{cubrid,postgresql}.out` | ordered sequence compare | direct A/B | see manifest |
| ground truth 300,270 / 456,771 / 1,825,856 / 72,985, identical on both engines | `q5-groundtruth-cubrid.out`, `q5-groundtruth-pg.out` | `count(*)` under the same predicates | direct A/B | see manifest |
| CUBRID estimated plan, non-executing (0.02 s, no rows): FK index-NL chain + hash join | `q5-plan-est-cubrid.out`, `q5-plan-est-cubrid.time` | `SET OPTIMIZATION LEVEL 514` | direct A/B | see manifest |
| PostgreSQL estimated plan + live `Settings:` | `q5-plan-est-pg.out` | `EXPLAIN (COSTS, VERBOSE, SETTINGS)` | direct A/B | see manifest |
| **CUBRID 3 headline values, median 9.615000 s** | `Q05-cubrid-headline-block1.json` | median of 3 measured statements | direct A/B | see manifest |
| **PostgreSQL 3 headline values, median 2.564428 s** | `Q05-postgresql-headline-block1.json` | median of 3 measured statements | direct A/B | see manifest |
| headline reproducibility across 3 gated blocks: 3.7494 / 3.7724 / 3.7940 | `Q05-*-headline-block{1,2,3}.json` | per-block medians | direct A/B | see manifest |
| both headline blocks `CLEAN` (external max 1.084 / 0.523) | `Q05-*-bgload-block1.json` | host-wide SUT busy minus campaign CPU, 4 Hz | direct A/B | see manifest |
| **WARM steady state = 9.528 s, half-to-half drift −0.10% over 40 statements** | `q5-convergence-cubrid.out` | 40 identical statements, one connection | direct A/B | see manifest |
| PostgreSQL stationary: 40-statement drift −0.03% | `q5-convergence-pg.out` | same | direct A/B | see manifest |
| **gate tolerance derived from a moving-block bootstrap null (n=40 max 2.99% vs warming 13.17%)** | `q5-convergence-{cubrid,pg}.out`, `harness/warm_establish.py:59-89` | block-bootstrap of the half-split trend statistic | projection | see manifest |
| **pool hysteresis: 9.5 / 10.7 / 13.4 s and 65,169 / 619,299 / ~1,631,608 misses by history alone** | `q5-convergence-cubrid.out`, `q5-trace-cubrid.out`, `pre-restart-pool/`, `warm-for-hltel-cubrid-*.log` | trace `ioread`, `/proc/<pid>/io` `syscr` | direct A/B | see manifest |
| **cross-engine page-cache interference rejected at +0.71%** | `q5-xengine-probe-cubrid.out` | 10 CUBRID statements immediately after a 40-statement PostgreSQL workload | direct A/B | see manifest |
| restarts: binary hash re-verified, 128 TIDs 0 off-cpuset, parameters intact | `q5-cubrid-restart.txt` | `cubrid-server-ctl.sh restart` + section 10 gate | direct A/B | see manifest |
| CUBRID actual trace: `parallel workers: 2` on the subquery, readkeys 456,771, fetch 7,524,219, ioread 65,169 | `q5-trace-cubrid.out` | `SET TRACE ON` + `SHOW TRACE` | direct A/B | see manifest |
| PostgreSQL native actual: `Workers Launched: 5`, `shared hit=992821 read=431861` | `q5-plan-act-pg.out`, `q5-plan-act-pg.json` | `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, TIMING)` | direct A/B | see manifest |
| **PostgreSQL controlled actual: `Index Searches: 456771`, `read=0`, 1506.550 ms** | `q5-plan-act-pg-idxnl.out` | same, under `PGOPTIONS=-c enable_seqscan=off` | direct A/B | see manifest |
| **`F_plan` anchor: PostgreSQL is 1.799x faster on CUBRID's shape (1.425705 vs 2.564428 s)** | `Q05-postgresql-idxnl-headline.json`, `Q05-postgresql-headline-block1.json` | gated block medians | direct A/B | see manifest |
| anchor B: CUBRID's own hash alternative is 1.148x worse (11.039 vs 9.615 s) | `Q05-cubrid-usehash-headline.json` | gated block median | direct A/B | see manifest |
| **hints are inert: PARALLEL(6) 9.605 / PARALLEL(12) 9.648 / serial 9.716 / native 9.615 s, subquery stays at 2 workers** | `variants/out2-*.txt`, `variants/tr-PARALLEL6.sql` trace output | trailing-4 median of 8 grouped repeats | direct A/B | see manifest |
| PostgreSQL counterfactuals: nestloop-forced 3.645 s, hashjoin-off 2.285 s, serial 18.599 s | `q5-plan-ab-pg.out` | `EXPLAIN ANALYZE` under GUC | direct A/B | see manifest |
| CUBRID headline-regime CPU 39.02 core-s/block, `U` 1.02822, TWU 1.0263, tail 9.554 s | `Q05-cubrid-headline-telemetry-run2.json` | per-TID ticks / `SC_CLK_TCK`, actual dt weighting | profile attribution | see manifest |
| PostgreSQL controlled CPU 31.27 core-s/block, `U` 5.42598, TWU 5.5433 | `Q05-postgresql-idxnl-headline-telemetry-run1.json` | same | profile attribution | see manifest |
| CUBRID `USE_HASH` reaches 6.77 units and 296.25 core-s/block | `Q05-cubrid-usehash-headline-telemetry-run1.json` | same | profile attribution | see manifest |
| **CUBRID 65,285 read syscalls/statement vs PostgreSQL-controlled 9,311; device ~0 both** | telemetry JSONs above | `/proc/<pid>/io` deltas ÷ 4 statements | profile attribution | see manifest |
| PostgreSQL controlled working set fits: 835,788 of 1,048,576 buffers, 20.3% headroom | `q5-workingset.out` | `count(distinct (ctid::text::point)[0])` + `relpages` | direct A/B | see manifest |
| CUBRID index page count unavailable (`db_index` exposes no page column) | `q5-index-pages.txt` | catalog probe listing every exposed column | UNMEASURED | see manifest |
| CUBRID IPC 1.23, **1.043 CPUs utilized**, 32,779 context switches | `perf-stat-cubrid.txt` | `instructions/cycles`, `task-clock/elapsed` | profile attribution | see manifest |
| PostgreSQL controlled IPC 1.53, partial PID set | `perf-stat-pg-idxnl.txt` | `instructions/cycles` | profile attribution | see manifest |
| CUBRID bands: buffer fix 26.85%, extraction 15.94%, B-tree 7.43%; 0 unresolved symbols | `profile-cubrid-flat.txt` | `perf report` self% | profile attribution | see manifest |
| PostgreSQL controlled bands: heap fetch 17.11%, worker page-table churn 17.26%, hash probe 10.77%; 0 unresolved | `profile-pg-idxnl-flat.txt` | `perf report` self% | profile attribution | see manifest |
| perf coverage: 26,733 / 140,365 samples, 0 lost, 0 `[unknown]` | `perf-record-cubrid.log`, `perf-record-pg-idxnl.log` | `perf record` stderr | profile attribution | see manifest |
| **DSM peak 96,943k = 1.5297x available `/dev/shm`; the mmap contract is load-bearing** | `q5-shared-memory-verification.txt` | 20 Hz `pg_dynshmem` poll through one execution | direct A/B | see manifest |
| card factors, both anchors, `W` derivation, `U` cross-check | `Q05-causal-card.json`, `q5-card-calc.txt` | section 16 formulas | profile attribution | see manifest |
| **superseded pre-restart blocks** (CUBRID 10.702/10.712/10.673, PostgreSQL 2.643623/2.644426/2.653256) and polluted-pool telemetry, excluded from all calculations | `pre-restart-pool/` + `INVALID.json` | see section 5 defects 1–3 | invalid | see manifest (valid=false) |

Not promoted (dispensable work per SSOT section 19): the raw `perf-*.data` files
(224 MB CUBRID, 1,202 MB PostgreSQL native, 1,119 MB PostgreSQL controlled) and the
per-TID sampler dumps of the accepted telemetry runs, which are fully summarised by the
promoted telemetry JSONs and intervals files. The manifest records both decisions under
`not_promoted`.

## 11. Notion sync

**Status: `NOTION_OUT_OF_WORKER_SCOPE` → idempotent Git backfill record written
(write path 3 only).**

Section 21's execution boundary is explicit: this GJC/tmux worker session runs on the
remote build host, has no Notion connector, and **must never attempt a Notion write**.
Its Notion-adjacent duty ends at committing and pushing this report, manifest and
registry to `origin/main`. Accordingly:

1. *official Notion connector* — **not attempted** (forbidden for the worker; also not
   exposed to this session's tool set).
2. *logged-in Aside browser* — **not attempted** (forbidden for the worker).
3. *idempotent Git backfill record* — **written**: appended to
   `reports/notion_backfill_pending.jsonl`, keyed on
   `campaign_id + QNN + session_id + report_commit + content_fingerprint`, carrying the
   section 21 required query fields with the same field names as this report.
   `content_fingerprint` follows the Q01–Q04 convention: sha256 of this `report.md` at
   `report_commit`. The record is written only after the report, manifest and registry
   are durable on `origin/main`. `pending_cleared` is `false`.

This satisfies the section 26 gate item ("Notion relations are synced **or** an
idempotent backfill record is durable") without a Notion call. Pending is **not**
cleared: clearing requires a server-side refetch, which only a Notion-capable subagent
may perform. Per the section 21 execution boundary the actual mirror write is performed
by a dedicated Notion-capable subagent dispatched during section 23 reconciliation,
reading the pushed commit as source of truth. Sections 3-a, 3-b, 4, 6, 7, 8 and 9 of
this report are written to be that mirror's source, including the full factor table,
both anchors, both engines' plan shapes with a per-node comparison, both engines'
top-cost symbols, `file:line` on both sides of every contrast, the rejected explanations
with their rejecting numbers, and the complete section 18 content for `IMP-009` plus the
extended `IMP-002` and `IMP-005`. The mirror must reflect that **`next_id` is now
`IMP-010`** and that **`IMP-009` is the campaign's first P0 parallelism candidate**.

Note for the reconciler: the SSOT gained a section 21 markdown formatting rule at the
pin this query used (`d19dca41`), added after Q04's page rendered literal `n` glyphs and
literal `<table>` tags. This report contains markdown tables, fenced code blocks and
`##` headings throughout; assemble the mirror with real newlines, do not escape the
structural markup, and refetch the page afterwards to scan for an isolated `n` token or
a literal `<`/`&lt;` inside a rendered table before considering the write done.

## 12. Completion checklist

- [x] preflight and correctness status recorded (section 1, section 2); external load
      0.772 core-s/s PASS at preflight, no wait required
- [x] three valid headline values for each completing engine (both completed; neither
      censored), every accepted block verified `CLEAN` against the section 9 external
      load threshold at 4 Hz **and** preceded by a proved WARM steady state under a gate
      whose tolerance was derived from this query's own measured stationary null
      distribution
- [x] timeout confirmations — not applicable, neither engine censored (9.62 s and 2.56 s
      against a 300 s limit)
- [x] plan, execution, profile and source contrast sections complete
- [x] causal multiplier card has evidence for every factor, with **`F_plan` numeric
      (0.5560) by a named PostgreSQL-side controlled A/B**, a second differently-anchored
      decomposition that reconstructs independently, and the residual declared an
      identity rather than a prediction
- [x] Git improvement ledger deduplicated and committed (`IMP-009` allocated with the
      full section 18 field set and a directly matching upstream precedent, CBRD-26931;
      `IMP-002` extended with Q05's pool-hysteresis failure mode; `IMP-005` given a
      second **negative control** plus a hard sequencing dependency on IMP-009;
      `IMP-008` **considered and rejected** for a Q05 relation on a measured 1.05%;
      `next_id: IMP-010`)
- [x] every claim indexed to raw evidence and checksum (373 artifacts; 84 retained as
      invalid under `pre-restart-pool/` with `INVALID.json` and excluded from all
      calculations)
- [x] report, manifest and registry committed, pushed and reachable from `origin/main`
- [x] `QUERY_COMPLETE` emitted by the worker session
- [ ] **current session removed and absence verified — OUTSTANDING, control-plane
      action.** This worker *is* the Q05 session: tmux session
      `gajae_code_ms7p9g4j_r7yxsbvc`. Self-removal would terminate the worker mid-turn
      and make the mandated dual absence check unobservable, so it is deliberately NOT
      claimed here. Per section 22 steps 7-9 and the section 23 `QUERY_COMPLETE` action,
      removal and absence verification are performed from outside this session, before
      any Q06 session is created:

      ```
      gjc session remove gajae_code_ms7p9g4j_r7yxsbvc
      gjc session status gajae_code_ms7p9g4j_r7yxsbvc      # expect: absent
      tmux has-session -t gajae_code_ms7p9g4j_r7yxsbvc     # expect: non-zero exit
      # if remove refuses a live session, exact-target fallback (never by pattern):
      tmux kill-session -t gajae_code_ms7p9g4j_r7yxsbvc
      ```

      The Q04 session `gajae_code_ms7lo36d_6uez896z` was verified absent at the start of
      this query (`gjc session list` showed exactly one session, this one), so the
      section 22 "never two measurement sessions concurrently" rule held throughout Q05.

Harness changes made during Q05 (all under `harness/`, section 5 allowlist):

- `harness/warm_establish.py` — **replaced the level test.** The adjacent 4-statement
  window-median comparison was measured against Q05's own known-converged 40-statement
  probe and produces up to 3.74%, i.e. it rejects a converged query by construction, the
  exact failure its docstring warned about. It now compares the medians of the two halves
  of the whole series (n/2 samples per side instead of 4), which averages out the
  multi-statement plateau excursions that broke the old statistic. `WINDOW`,
  `LEVEL_TOL`, `SPREAD_SANITY` and the statement count are now environment-overridable
  because Q05 proved the Q04 constants are not universal, and the docstring records the
  moving-block bootstrap null distribution that every future threshold must be justified
  against. Defaults are unchanged, so no earlier query's gate behaviour is altered
  retroactively.
- `harness/warm_establish.py`, `harness/headline_run.py`, `harness/headline_telemetry.py`,
  `harness/measure_block.sh` — **controlled-plan variants are now measurable in the
  section 12 block regime** via optional `[SQL_FILE|-] [VARIANT_TAG]` arguments,
  mirroring `telemetry_run.py`'s existing convention. Without this a numeric `F_plan`
  anchor and its remaining cross-engine pair would have had to mix a block-regime
  denominator with a single-statement one, which section 16 forbids. PostgreSQL variants
  are expressed through `PGOPTIONS` rather than an extra `set` statement, because an
  extra statement would emit its own `\timing` line and corrupt statement-time parsing
  and would change the statement count the contract fixes at 4. Variant artifacts are
  tagged `<engine>-<variant>` and the native paths are byte-identical to before
  (verified by constructing both and diffing the generated block files).
- `harness/measure_block.sh` — **fixed a stale-canonical-file trap.** When every attempt
  was rejected the script exited non-zero but left the previous run's canonical
  artifacts in place, so a caller copying them into per-block names silently recorded an
  earlier block twice. This happened during Q05 and was caught by hashing the per-block
  files against each other. The canonical names are now removed at the start of a run, so
  a rejected run leaves a missing file instead of a duplicated measurement.

Known carried-forward gaps, explicitly recorded rather than silently omitted:

- CUBRID actual histogram bucket count remains `UNMEASURED` (opaque `VARBIT` catalog);
  target 300 is configured and verified. Q05's plan choice is driven by FK index
  availability and join cardinality rather than by a histogram-sensitive selectivity, and
  CUBRID's date sarg estimate (`sel 0.152751` against an actual 2,275,919/15,000,000 =
  0.1517) is accurate to 0.7%, so this gap does not bind here.
- CUBRID's index page count is still not exposed by `db_index` (every exposed column is
  listed in `q5-index-pages.txt`), so any CUBRID-side page accounting remains a
  projection. Q05 does not depend on one: its miss rate is 0.87% and buffer residency is
  not the finding.
- `perf stat`'s "CPUs utilized" is a valid utilization reading for CUBRID (all query
  threads in one attached process) but **not** for PostgreSQL (workers are per-statement
  and the attached set covers one statement's). PostgreSQL utilization comes from
  telemetry only. This asymmetry is inherent to the two process models, not a harness
  defect, and is stated wherever the number appears.
- The reported block is block 1 by the campaign's first-accepted-block convention, but
  unlike Q04 it is not simultaneously the median of medians; the median-of-medians ratio
  is 3.775917x against the reported 3.749374x, **+0.71%**. Recorded rather than resolved
  in either direction.
- Q05's headline required two CUBRID server restarts to reach a reproducible pool state.
  The restarts are campaign-owned, went through the mandated wrapper, and were followed
  by the full section 10 identity/affinity/parameter gate each time — but the underlying
  need for them is itself the IMP-002 finding, and it means Q05's CUBRID number is
  specifically the *native-only-pool* steady state rather than the level a mixed
  workload would see. Both are reported.
- The measurement host is shared and containerised (host-wide `/proc/stat` and
  `/proc/diskstats`), so external load is invisible to `ps` inside the container and the
  26.90 MiB of device reads observed during a CUBRID telemetry block is an upper bound
  shared with other tenants rather than an attribution to this campaign.
- The CUBRID databases live under a repository-internal `.git_ignored_dir`; this is the
  reused SF10 dataset and moving it would be a destructive action outside the cleanup
  manifest, so it was left untouched and only recorded.
