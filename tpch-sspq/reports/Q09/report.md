# TPCH-SSPQ FK campaign — Q09 report

## 3-a. Causal multiplier card

```text
R_wall 2.115055x [wall, median of 3 per engine; PostgreSQL is 2.1151x faster]
= F_plan  1.384468x [plan-shape; PostgreSQL-side controlled A/B, anchor named below]
× F_units 1.177424x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   1.297496x [total query CPU-seconds]

F_cpu 1.297496x is the CONTROLLED pair's CPU factor. On the native pair the same
quantity is 1.786360x, and it decomposes as

F_cpu(native) 1.786360x [total query CPU-seconds]
= F_work 0.379590x [plan-node tuple touches: 18,745,215 vs 49,382,743]
× F_cost 4.706019x [total-query CPU-seconds per tuple touch: 2914.1 ns vs 619.2 ns]
```

**Read the card in one line: CUBRID chose the wrong plan. Both engines are faster on the
hash shape and slower on the index-nested-loop shape, and CUBRID is the one running the
index-nested-loop shape.** Forcing PostgreSQL onto CUBRID's shape costs PostgreSQL
**1.3845x**; forcing CUBRID onto PostgreSQL's shape *gains* CUBRID **1.5425x**
(10.980999 s → 7.118999 s). The two independent A/Bs agree in direction and in magnitude,
and neither engine's optimizer is being asked to do anything exotic — the winning plan is
the one CUBRID's own executor runs at **6.23 active units with a 12.17-unit peak**.

Q09 is the exact converse of Q08. There `F_plan` and `F_cpu` both favoured CUBRID and the
whole loss sat in `F_units`. Here `F_units` is the *smallest* factor (1.177x of a 2.115x
gap) and the plan-shape factor is real, numeric and reproducible from both sides.

`F_plan` is numeric by a **PostgreSQL-side controlled A/B**, direction stated explicitly:
*PostgreSQL native (`Parallel Hash Join` tree) → PostgreSQL controlled
(`enable_hashjoin=off, enable_mergejoin=off`, the index-nested-loop chain CUBRID chooses
natively)*. That variant plan (`variants/plan-nestloop_forced.out`) is node-for-node
CUBRID's native shape: `part(p_name sarg) → partsupp(idx_fk_partsupp_part) →
supplier(PK) → nation(PK, memoized) → lineitem(idx_fk_lineitem_partsupp) →
orders(PK, memoized)`. The remaining controlled cross-engine pair is
(CUBRID native, PostgreSQL controlled index-NL) and carries `F_units` and `F_cpu`;
native and controlled denominators are never mixed.

Both engines' plans produce the **identical intermediate cardinalities
108,782 / 435,128 / 3,261,613 → 175**, independently confirmed by ground-truth `count(*)`
queries that both engines answer identically (`q9-groundtruth-cubrid.out`,
`q9-groundtruth-pg.out`) and cross-checked against `q9-plan-act-pg.out`'s `loops × rows`.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 1.384468x | plan-node shape | same-engine controlled A/B on PostgreSQL | `T_P_idxnl/T_P_native` = 7.187919/5.191826 | `Q09-postgresql-idxnl-headline.json`, `Q09-postgresql-headline-block1.json`, `variants/plan-nestloop_forced.out` | direct A/B |
| `F_units` | 1.177424x | active execution units | CPU-seconds / wall-second over the section 12 block | `U_P_idxnl/U_C_native` = 5.85720/4.97459 | `Q09-postgresql-idxnl-headline-telemetry.json`, `Q09-cubrid-headline-telemetry-run3.json` | profile attribution |
| `F_cpu` | 1.297496x | total query CPU-seconds | per query execution | `CPU_C_native/CPU_P_idxnl` = 54.6260/42.1011 | same telemetry JSONs | profile attribution |
| `F_work` | 0.379590x | plan-node tuple touches | tuples | `W_C/W_P` = 18,745,215/49,382,743 | `q9-groundtruth-*.out`, `q9-plan-act-pg.out`, `q9-plan-est-cubrid.out` | direct A/B |
| `F_cost` | 4.706019x | CPU-seconds per tuple touch | tuple touches | `(CPU_C/W_C)/(CPU_P/W_P)` = 2914.1 ns / 619.2 ns | `Q09-causal-card.json`, `q9-card-calc.txt` | profile attribution |

**Second anchor.** Anchoring on the CUBRID side (*CUBRID native index-NL → CUBRID
controlled `/*+ USE_HASH(orders, supplier) */`, i.e. PostgreSQL's native shape on the
dominant path*) gives

```text
2.115055x = 1.542492x [plan] × 0.945381x [units] × 1.450414x [CPU-sec]
```

which also reconstructs exactly. PostgreSQL's shape *saves* CUBRID **1.5425x**
(7.119 s vs 10.981 s) while CUBRID's utilization *rises* from `U = 4.97459` to
`U = 6.23022` — CUBRID is not merely running the wrong shape slowly, it is running the
wrong shape at a **lower** parallel width than the shape it rejected. Note the sign flip
against Q08, where the same experiment (forcing CUBRID onto PostgreSQL's hash shape) made
CUBRID **1.5123x slower**; Q08 is therefore a positive control proving the CUBRID
optimizer's join-method choice is not uniformly wrong, and Q09 is a case where it is.

**Reconstruction residual = −0.000000% on anchor A and +0.000000% on anchor B, and as in
Q04–Q08 that is an identity, not a prediction.** `CPU_stmt` is attributed as `U × t_median`
with `U` measured on the same block regime the wall is defined on, so
`F_units × F_cpu = T_C/T_P` by construction. Closure rests on the independent quantities:

- **`U` reproducibility.** CUBRID native 4.97747 / 4.96873 / 4.97459 across three
  independently gated WARM-converged telemetry runs (**0.18%** max−min — the tightest of
  the campaign so far); PostgreSQL native 5.9091 / 5.88993 / 5.8726 (**0.62%**).
- **TWU**, from actual sample timestamp deltas over the busy window only: **4.9644**
  (CUBRID, **−0.20%** from `U`), **5.8428** (PostgreSQL, **−0.80%**), **6.2113**
  (CUBRID USE_HASH, −0.30%), **5.8249** (PG index-NL, −0.55%). Every configuration's
  independent unit estimate agrees with its `U` to under 1%.
- **`perf stat` on verified PID sets**, a third instrument: **5.022 CPUs utilized** for
  CUBRID (**+0.95%** against `U` = 4.97459) and **5.617** for PostgreSQL's
  postmaster-inherited executor set (**−4.62%**; PostgreSQL's auxiliary io-worker CPU is
  3.87 core-s per block and the perf window's back-to-back statements omit the block's
  inter-statement gaps).
- **Instructions and IPC**, a separate counter path: CUBRID **395.432 G instructions at
  IPC 1.11**, PostgreSQL **526.022 G at IPC 1.31** over their respective 25 s windows;
  normalised per statement that is **173.68 G vs 109.23 G**, i.e. CUBRID retires
  **1.5900x** the instructions at **0.8473x** the IPC — the quantitative form of
  "it walks 3.26 M B-tree descents where PostgreSQL streams 15 M tuples through a hash
  table".
- **Context switches**, a fourth independent counter: CUBRID **284,577 in 25.002 s
  (2.266 K/s)** against PostgreSQL **14,412 (102.6/s)** — **22.1x the rate**.

### Error budget, stated before any factor is interpreted

| Quantity | Blocks | min | max | spread |
|---|---|---|---|---|
| CUBRID block-median wall | 3 telemetry + 1 contract block | 10.659000 s | 11.000000 s | **3.20%** |
| PostgreSQL block-median wall | 3 telemetry + 1 contract block | 5.115516 s | 5.191826 s | **1.49%** |

The ratio band implied by those two spreads is **2.0530x .. 2.1503x**, and the contract
`R_wall = 2.115055x` sits inside it. Unlike Q08, every factor in this card except
`F_units` is far outside the band: `F_plan` 1.3845x and 1.5425x, `F_cpu` 1.7864x native.
Q09's verdict is therefore **"CUBRID 2.12x slower, and the plan choice alone accounts for
1.54x of it"**, and it is safe to interpret at that precision.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q09 (Product Type Profit Measure) |
| Pinned `ssot_commit` | `10ee29b0270b1e86dc72b4de5db44792622b2254` |
| Pinned `ssot_blob_sha` | `510478846bff081d3223d3835069283a7cd2e47b` |
| SSOT drift | `NONE` — HEAD blob `510478846bff081d3223d3835069283a7cd2e47b` equals the pinned blob at the pre-block gate (`preflight-Q09.txt`) and at the post-block gate (`q9-postcheck.txt`) |
| GJC session ID | `gajae_code_ms8uwty0_cr51ca7y` |
| Workspace HEAD at measurement | `9968a9be04c1c1be7be3e1e2557a5bf27b504320` (== `origin/main`, `tpch-sspq` porcelain empty) |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 merge `b334446d6`) |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` (matches frozen build manifest) |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` (matches frozen build manifest) |
| Databases | CUBRID `tpch_sf10_q1` (pid 1612732), PostgreSQL `tpch_sspq` @ `/home/cubrid/pg/pgdata-tpch-sspq` port 5442 (postmaster pid 1433696) |
| Ownership gate | `OK` at pre-block and post-block; both PIDs resolve to the campaign prefixes, ports 1523/5442 owned by them |
| Schema gate | 8 CUBRID FK-owned B-trees / 8 PostgreSQL FKs (`convalidated=t`) / 8 `idx_fk_*` btree indexes, exact child-column order |
| Statistics | CUBRID `update_statistics_update_histogram=y`, `default_histogram_bucket_count=300`; PostgreSQL `default_statistics_target=100` — histogram-enabled controlled comparison |
| Parallel/buffer contract | CUBRID `parallelism=6`, `max_parallel_workers=100`, `data_buffer_size=8.0G`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`, `parallel_leader_participation=on`, `shared_buffers=8192MB`, `dynamic_shared_memory_type=mmap`, `jit=off`, `statement_timeout=300s` — configured node/gather-cap comparison, configured-equal buffer budget |
| cpuset / NUMA | 34 engine TIDs, `off_cpuset=0` at pre-block and post-block; SUT+client on CPUs 0-15/node0, collectors on 20-23 |
| Query provenance | `q9.sql` SHA-256 `2b09d5e36aae69b139a92ee74cc585c88ece33741e0c6eb37cf986806a0ad3fe` — canonical, active CUBRID and active PostgreSQL files are **byte-identical** (`queries/diff/q9.diff` empty, `cmp` verified: zero dialect changes) |
| Engine block order | Q09 is odd → CUBRID block first, then PostgreSQL block (SSOT section 12) |
| External load gate | threshold 6.0 core-s/s; every accepted block `CLEAN` on attempt 1 (`external_max` 0.8403 CUBRID / 0.6260 PostgreSQL) |

## 2. Correctness

| Item | Value |
|---|---|
| Status | **`result-equivalent-at-SF10`** |
| Rows | 175, `ORDER BY` present → exact ordered sequence compared |
| Censoring | none; both engines complete far inside the 300 s timeout |
| Comparator | `harness/correctness_check.py Q09` → `smoke_check.py` (SSOT section 11 rules: raw decimal text preserved, relative 1e-12 output-scale tolerance only) |
| Evidence | `q9-correctness.json`, `q9-correctness-cubrid.out`, `q9-correctness-postgresql.out` |

No tolerance was needed to reconcile a row: the decimal texts match at full scale.

**Sink-level cross-check.** The headline blocks write full result sets to campaign-owned
sinks: CUBRID 46,408 bytes (`sha256:448270932a8f3aa6…`), PostgreSQL 32,334 bytes
(`sha256:e86960fdde9b04c1…`). The byte counts differ only because CUBRID's `csql` pads
`char(25)` `n_name` and renders a header; the 175 (nation, year, sum_profit) triples are
identical, which the correctness gate proves independently of the sinks.

## 3-b. Headline timings

Regime: `single-query-repeat WARM`, metadata connection mode
`single-connection-four-statements` (1 uncounted warmup + 3 measured, one direct
connection, no reconnect/prepare between measured statements, full row consumption into a
campaign-owned sink, content hash computed after the timer stops).

| Field | CUBRID | PostgreSQL |
|---|---|---|
| uncounted warmup | 10.993000 s | 5.295911 s |
| measured #1 | 11.001000 s | 5.240345 s |
| measured #2 | 10.980999 s | 5.183993 s |
| measured #3 | 10.857000 s | 5.191826 s |
| **median (headline)** | **10.980999 s** | **5.191826 s** |
| mean | 10.946333 s | 5.205388 s |
| within-block stddev | 0.078008 s (0.71%) | 0.030526 s (0.59%) |
| sink bytes / SHA-256 | 46,408 / `448270932a8f3aa6…` | 32,334 / `e86960fdde9b04c1…` |
| block accepted on | attempt 1, load `CLEAN` | attempt 1, load `CLEAN` |
| **median wall ratio** | **2.115055x** (CUBRID slower) | — |
| correctness / censoring | `result-equivalent-at-SF10` / not censored | same |

Three values only, so no confidence interval is claimed; the band in section 3-a is the
honest uncertainty statement.

**WARM is proved, not assumed.** Each block was preceded by a separate uncounted
20-statement `warm_establish.py` run on the same connection regime, gated on a half-split
level test. Parameters were derived from 40-statement convergence probes run under the
load gate before any block was timed (`q9-convergence-cubrid.json`,
`q9-convergence-pg.json`):

| Engine | probe n | first index that would pass | half-split trend | trailing spread | block parameters used |
|---|---|---|---|---|---|
| CUBRID | 40 | 15 | −0.49% | 0.30% | n=20, `LEVEL_TOL` 3.0%, `SPREAD` 5.0% |
| PostgreSQL | 40 | 12 | −0.17% | 1.28% | n=20, `LEVEL_TOL` 1.0%, `SPREAD` 3.0% |

The CUBRID probe reports `converged=false` for one reason only — its *trailing four*
statements happened to descend monotonically (11.007 / 10.941 / 10.866 / 10.829, a 1.6%
excursion) — while the level over all 40 statements moved −0.49%. Q09 is the campaign's
most level-stable query on both engines,
and every other block's warm gate did converge (CUBRID: headline −0.98%, telemetry run 1
−0.50%, telemetry run 3 +0.03%, `USE_HASH` variant −0.39%; PostgreSQL: headline −0.32%,
telemetry run 1 −0.18%, telemetry run 3 −0.36%, index-NL variant −0.02%). The one CUBRID
telemetry run whose warm gate returned `NOT_CONVERGED` is reported with that flag in
section 5 rather than silently averaged in.

**Physical-read state.** `read_bytes` deltas are **0** on both engines for every timed
block: nothing was read from the device inside a measured statement. Both engines
nevertheless miss their own 8192 MB buffer budget heavily and re-read from the OS page
cache — that traffic is quantified in section 5 and is *not* a WARM-gate failure, it is
the working-set-vs-pool fact this query exposes.

## 4. Plan

### 4-a. CUBRID native (`q9-plan-est-cubrid.out`, `q9-trace-cubrid.out`)

```text
temp(order by)
  temp(group by)                                    sort 1 asc, 2 asc ; hash partial
    idx-join  inner: iscan nation  pk_nation_n_nationkey        (MEMOIZE hit/miss 16,307,440/625)
      idx-join  inner: iscan supplier  pk_supplier_s_suppkey
        idx-join  inner: iscan orders  pk_orders_o_orderkey
          idx-join  inner: iscan lineitem  fk_lineitem_partsupp  (term[1] AND term[4])
            idx-join  inner: iscan partsupp  fk_partsupp_part
              sscan part  sargs: p_name like '%green%'           (parallel workers: 5)
```

A pure index-nested-loop chain: one parallel heap scan of `part` feeding five levels of
index probes. `parallelism=6` is honoured — the trace records `parallel workers: 5` on the
driving scan and telemetry measures `U = 4.97`.

### 4-b. PostgreSQL native (`q9-plan-est-pg.out`, `q9-plan-act-pg.out`)

```text
Finalize GroupAggregate
  Gather Merge (Workers Planned 5, Launched 5)
    Partial GroupAggregate
      Sort  (external merge, Disk 35.1-35.4 MB per worker)
        Hash Join  (nation, 25 rows)
          Parallel Hash Join   Hash Cond: orders.o_orderkey = lineitem.l_orderkey
            Parallel Seq Scan on orders                      15,000,000 rows
            Parallel Hash  (Buckets 131072  Batches 32  8320 kB)
              Nested Loop   Join Filter: supplier.s_suppkey = lineitem.l_suppkey
                Parallel Hash Join  (supplier, 100,000 rows)
                  Nested Loop
                    Parallel Index Scan using part_pkey   Filter p_name ~~ '%green%'
                    Index Scan using idx_fk_partsupp_part
                Index Scan using idx_fk_lineitem_partsupp  435,128 searches, 7.50 rows each
```

### 4-c. The two shapes, and who is faster on each

| Shape | CUBRID wall | PostgreSQL wall | faster engine |
|---|---|---|---|
| index-nested-loop chain (`orders`/`supplier` probed by key) | **10.980999 s** (native) | 7.187919 s (`enable_hashjoin=off, enable_mergejoin=off`) | PostgreSQL, 1.5277x |
| hash tree (`orders`/`supplier` scanned and hashed) | 7.118999 s (`/*+ USE_HASH(orders, supplier) */`) | **5.191826 s** (native) | PostgreSQL, 1.3711x |

Both engines prefer the hash shape by a wide margin (CUBRID 1.5425x, PostgreSQL 1.3845x),
and only one of them picks it. The controlled CUBRID plan
(`variants/plan-USE_HASH_ORDERS_SUPPLIER.out`) is the same tree PostgreSQL builds
natively on the dominant path: `part → partsupp(idx) → lineitem(idx) → hash-join orders →
hash-join supplier → idx-join nation`.

### 4-d. Estimated vs actual cardinality — the cause of the choice

CUBRID's plan dump prints its own estimates next to costs, and ground truth is known
exactly from `q9-groundtruth-*.out` (both engines agree on every line):

| Stage | CUBRID estimate | actual | error |
|---|---|---|---|
| `part` after `p_name like '%green%'` | 3,200 | 108,782 | **34.0x low** |
| `⨝ partsupp` (fk_partsupp_part) | 8,015 | 435,128 | **54.3x low** |
| `⨝ lineitem` (fk_lineitem_partsupp) | **2** | **3,261,613** | **1,630,806x low** |
| `⨝ orders` / `⨝ supplier` / `⨝ nation` | 1 / 1 / 1 | 3,261,613 each | ~3.26 M x low |

PostgreSQL's estimate for the same join is 554,069 against the actual 3,261,613 — 5.9x
low, six orders of magnitude closer.

The collapse at the `lineitem` level is arithmetic and reproducible from the dump's own
numbers. CUBRID scores the two-column FK match as two independent equalities:

```text
term[1]  ps_suppkey = l_suppkey   (sel 1.00319E-05)   ~ 1/99,682  (supplier NDV)
term[4]  p_partkey  = l_partkey   (sel 5E-07)         ~ 1/2,000,000 (part NDV)
selectivity = 1.00319E-05 x 5E-07 = 5.016E-12
card = 8,015 x 59,986,052 x 5.016E-12 = 2.41  ->  printed "card 2"
```

The true selectivity of that pair is not the product: `(l_partkey, l_suppkey)` is the
child side of `fk_lineitem_partsupp`, whose parent key is `partsupp(ps_partkey,
ps_suppkey)`, so each `partsupp` row matches `59,986,052 / 8,000,000 = 7.4983` lineitem
rows and the selectivity is `1/8,000,000 = 1.25E-07` — **24,920x** larger than the product
CUBRID uses. Applied to the true outer cardinality it reproduces the measurement:
`435,128 × 7.4983 = 3,262,750` against the measured 3,261,613 (0.03%).

With `card 2` flowing into them, the three remaining index-NL levels are costed at 4-5
units each and the whole chain lands at **36,082**, while the hash alternative — whose
cost is dominated by the cardinality-independent `orders` heap scan — lands at
**984,797**. The optimizer therefore prefers the NL chain by **27.3x** on a plan that
measurement shows is **1.5425x slower**.

## 5. Execution telemetry

All values are non-headline, captured on the identical section 12 block regime under the
same load gate.

| Configuration | wall (block median) | U [core-s/wall-s] | TWU | peak units | serial tail | executor CPU | auxiliary CPU | total CPU / block |
|---|---|---|---|---|---|---|---|---|
| CUBRID native | 10.899 s | **4.97459** | 4.9644 | 5.3523 | 0.111 s | 215.94 | 0.38 | 216.32 core-s |
| PostgreSQL native | 5.151 s | **5.88993** | 5.8428 | 8.2587 | 0.350 s | 117.63 | 4.37 | 122.00 core-s |
| CUBRID `USE_HASH(orders,supplier)` | 7.156 s | 6.23022 | 6.2113 | **12.1704** | 0.000 s | 171.57 | 6.77 | 178.34 core-s |
| PostgreSQL index-NL forced | 7.180 s | 5.85720 | 5.8249 | 6.4925 | 0.356 s | 168.40 | 0.72 | 169.12 core-s |

Process classification (SSOT section 15) is explicit in every telemetry JSON:
CUBRID `executor` = `cub_server` parallel-query + transaction threads, `auxiliary` =
page-flush/DWB/vacuum/deadlock threads; PostgreSQL `executor` = leader backend + parallel
workers, `auxiliary` = io workers (3.87 core-s per native block) + background processes.
Time-weighted units use actual sample timestamp deltas, never a nominal interval.

**Three CUBRID telemetry runs, one caveat.** Run 2's warm gate returned `NOT_CONVERGED`
("monotone trailing window") at a block level 2.6% below the other two (10.659 s against
10.899 s and 11.000 s); its `U` (4.96873) is
within 0.18% of the other runs, so it is reported and used for the `U` median but its
block wall (10.659 s) is flagged in the error budget rather than treated as a level shift.

### 5-a. Buffer-pool and I/O traffic (`Q09-*-buffer-io-diag.json`)

Per measured statement, from `/proc/<server>/io` deltas across a dedicated non-headline
4-statement block:

| Quantity | CUBRID | PostgreSQL |
|---|---|---|
| `read_bytes` (device) | **0** | **0** |
| `rchar` (page-cache reads) | **30.497 GB** | 18.647 GB |
| `syscr` (read syscalls) | **1,861,608** | 2,273,118 |
| bytes per read syscall | 16,382 (= 16 KiB page) | 8,203 (= 8 KiB page) |
| engine buffer misses | 1,861,608 pages × 16 KiB | 1,230,806 pages × 8 KiB (`heap_blks_read`) |
| engine buffer hits | — (see note) | 2,428,941 (`heap_blks_hit`) |
| temp/spill writes | 0 | 1.669 GB (`Sort Method: external merge`) |

Note on CUBRID's global page counters: `cubrid statdump -c` advances on a coarse internal
cycle, so its `Num_data_page_fetches` / `Num_data_page_ioreads` deltas across a
40-second block read as 0 while the cumulative values do move between blocks
(43,155,954 → 70,705,740 fetches over Q08→Q09). The per-statement traffic above is
therefore taken from the kernel's own accounting, which is independent of the engine.

**The trace's own I/O counters agree once the section 5-b multiplier is removed:**
`lineitem` 3,332,998 ÷ 2 + `orders` 284,076 ÷ 3 + `partsupp` 72,382 + `nation`/`supplier`
21 = **1,833,573** predicted page reads vs **1,861,608** measured `syscr` (+1.5%).

**The same measurement on the controlled variants isolates the shape, not the pool**
(sampler `rchar` per block, `Q09-*-headline.json`):

| Configuration | `rchar` per statement | wall |
|---|---|---|
| CUBRID native (index-NL) | 30.44 GB | 10.981 s |
| CUBRID `USE_HASH(orders,supplier)` | **23.61 GB** | 7.119 s |
| PostgreSQL native (hash) | 19.69 GB | 5.192 s |
| PostgreSQL index-NL forced | **26.84 GB** | 7.188 s |

Within each engine, the index-NL shape moves ~1.3x the bytes of the hash shape through
the same buffer pool. The pool size is identical in all four rows, so the traffic is a
property of the plan, not of the buffer budget.

### 5-b. Trace counter multiplier (independent confirmation of IMP-005)

`q9-trace-cubrid.out` reports scan row counts that are exact integer multiples of the
ground truth, by nesting depth:

| Scan level | depth | trace `rows` | ground truth | ratio |
|---|---|---|---|---|
| `partsupp` (fk_partsupp_part) | 2 | 435,128 | 435,128 | 1x |
| `lineitem` (fk_lineitem_partsupp) | 3 | 6,523,226 | 3,261,613 | **exactly 2x** |
| `orders` (PK) | 4 | 9,784,839 | 3,261,613 | **exactly 3x** |
| `supplier` (PK) | 5 | 12,197,824 | 3,261,613 | 3.74x |
| `nation` (PK, memoize hit+miss) | 6 | 16,308,065 | 3,261,613 | **exactly 5x** |

This is IMP-005's `(k−1)`-times reporting rule, now observed at depths 3, 4 and 6 of a
six-level chain (Q05 established it at depths 3 and 4). Depth 5's 3.74x instead of 4x is a
new detail worth recording. **No trace row counter is used as a work numerator anywhere in
this report**; every `W` term comes from ground-truth `count(*)`.

## 6. Profile

Non-headline. `perf record -F 999 -g --call-graph dwarf` on verified PID sets
(CUBRID: `cub_server` pid 1612732, 30 TIDs, all query threads inside that process;
PostgreSQL: postmaster attached before the connection existed, so leader + every
statement's workers are inherited and io/background workers that predate the attach are
excluded). Coverage: **0 unknown-symbol lines** in either flat profile
(CUBRID 1,106 lines / 125,280 samples, PostgreSQL 2,079 lines / 140,393 samples).

`perf stat` on the same sets: CUBRID 5.022 CPUs utilized, IPC 1.11, 2.836 GHz,
395.432 G instructions, 284,577 context switches (2.266 K/s); PostgreSQL 5.617 CPUs
utilized, IPC 1.31, 2.851 GHz, 526.022 G instructions, 14,412 context switches (102.6/s).

Bands, as a share of each engine's own samples, and converted to absolute CPU using that
engine's measured per-statement CPU (CUBRID 54.626 core-s, PostgreSQL 30.580 core-s):

| Band | CUBRID % | CUBRID core-s/stmt | PostgreSQL % | PostgreSQL core-s/stmt |
|---|---|---|---|---|
| buffer fix/unfix/LRU/victim | **21.38%** | **11.68** | 10.03% (pin/unpin/clock-sweep/lwlock) | 3.07 |
| kernel page-cache read path | 16.57% | 9.05 | 22.26% | 6.81 |
| B-tree descent/compare | **12.32%** | **6.73** | 2.98% | 0.91 |
| slotted-page / heap record access | 9.44% | 5.16 | 9.53% (tuple form/deform/sort-tuple/spill) | 2.91 |
| libpthread mutex | **5.49%** | **3.00** | — (lwlock counted above) | — |
| expression / type | 5.36% | 2.93 | 9.15% | 2.80 |
| executor scan/fetch driver | 3.96% | 2.16 | — | — |
| hash join build/probe + shared tuplestore | — (not in native plan) | — | 14.43% | 4.41 |
| page checksum verify on read | — | — | 3.31% | 1.01 |
| memory allocator | — (<0.3% cut) | — | 2.91% | 0.89 |

Top symbols, CUBRID: `rep_movs_alternative` 12.55% (kernel copy out of the page cache),
`pgbuf_fix_release` 11.66%, `spage_get_record` 5.37%, `btree_search_leaf_page` 5.10%,
`pgbuf_unfix` 3.42%, `btree_search_nonleaf_page` 2.87%, `__pthread_mutex_lock` 2.31%,
`pgbuf_lru_boost_bcb` 1.98%.

Top symbols, PostgreSQL: `rep_movs_alternative` 9.79%, `ExecParallelScanHashBucket` 6.38%,
`hash_search_with_hash_value` 4.62%, `next_uptodate_folio` 4.11%,
`pg_checksum_block_fallback` 3.31%, `ExecInterpExpr` 3.04%, `heap_page_prune_opt` 2.56%,
`LWLockAttemptLock` 2.34%, `PinBuffer` 1.94%.

The profile is the plan choice made visible: CUBRID spends **11.68 + 6.73 = 18.41
core-seconds per statement** in buffer-manager and B-tree machinery — **4.63x**
PostgreSQL's 3.98 core-seconds in the same two bands, and 60.2% of PostgreSQL's *entire*
30.58 core-second statement — because an index-NL chain converts every one of
3.26 M intermediate rows into a fresh root-to-leaf descent plus page fix/unfix pairs,
while a hash join converts them into one sequential pass plus a bucket probe.

## 7. Source contrast

| Item | CUBRID file:line | PostgreSQL file:line | Difference | Class |
|---|---|---|---|---|
| Multi-column FK join selectivity | `src/optimizer/query_planner.c:7927` (`planner_visit_node`: `selectivity *= QO_TERM_SELECTIVITY (term);` for every join term, floored only at `1/cardinality` on :7928) | `src/backend/optimizer/path/costsize.c:5698` (`fkselec = get_foreign_key_join_selectivity(...)` before `clauselist_selectivity`) and `:6005-6011` (`fkselec *= 1.0 / ref_tuples`) | PostgreSQL matches the join clauses against `root->fkey_list`, removes them from the clause list and substitutes `1/parent_rows`; CUBRID multiplies the two clause selectivities as independent events | structural absence |
| Per-clause equality selectivity source | `src/optimizer/query_planner.c:10189-10238` (`qo_equal_selectivity`: histogram join selectivity, else `1/MAX(lhs_icard, rhs_icard)`, else `DEFAULT_EQUIJOIN_SELECTIVITY`) — all per column pair, no multi-column entity | `src/backend/optimizer/path/costsize.c:5810-5813` comment: *"especially for multi-column FKs where that function's assumption that the clauses are independent falls down badly"* | both engines estimate a single column pair the same way; only PostgreSQL has a rule that fires *before* the independent product is formed | structural absence |
| FK metadata reachable from the optimizer | `src/optimizer/query_graph.c:9955` `qo_is_pk_fk_full_join()` — walks `QO_NODE_INDEXES`, tests `SM_CONSTRAINT_FOREIGN_KEY` and `fk_info->ref_class_pk_btid` against the parent PK B-tree ID; **single caller** at `:9927` inside `qo_discover_sort_limit_join_nodes()` | `src/backend/optimizer/path/costsize.c:5830` (`foreach(lc, root->fkey_list)`) — the same structural test, consumed by the cost model | CUBRID already performs the exact FK-covers-this-join test PostgreSQL needs, but uses the answer only to drop nodes from sort/limit evaluation, never to derive a join size | structural absence |
| Hash join executor availability | `src/query/query_hash_join.c:156` `qexec_hash_join()`, with parallel-thread path at `:2000-2010` | `src/backend/executor/nodeHashjoin.c:818` `ExecParallelHashJoin`, `src/backend/executor/nodeHash.c:2079` `ExecParallelScanHashBucket` | **not** an absence: CUBRID's hash join runs this query at `U=6.23` with a 12.17-unit peak and is 1.5425x faster than the plan chosen. The defect is entirely in plan selection | common to both engines |
| NL-vs-hash cost comparison constants | `src/optimizer/query_planner.c:87` `HJ_MEM_ALLOC_CONSTANT 1500 /* Heuristic offset to prefer NL join over hash join */`, applied at `:3626` and `:3634` | no equivalent constant; `initial_cost_hashjoin`/`final_cost_hashjoin` in `costsize.c` cost the build and probe from estimated rows only | CUBRID adds a fixed anti-hash offset; on Q09 it is 1,500 against a 948,715 cost gap (0.16%) and is **not** the deciding term — recorded so the ranking in section 9 can reject it with a number | same stage, lower measured cost |
| Page fix/unfix on the hit path | `src/storage/page_buffer.c:2211` `pgbuf_fix_release`, `:3024` `pgbuf_unfix`, `:10073` `pgbuf_lru_boost_bcb`, `:6845` `pgbuf_unlatch_void_zone_bcb` — mutex-protected LRU list surgery per unfix | `src/backend/storage/buffer/bufmgr.c:3295` `PinBuffer` (atomic refcount bump, no list), `src/backend/storage/buffer/freelist.c:184` `StrategyGetBuffer` (clock sweep) | 21.38% of CUBRID's profile vs 10.03% of PostgreSQL's, on a plan that fixes 1.86 M pages per statement | same stage, lower measured cost |
| B-tree descent per intermediate row | `src/storage/btree.c:5190` `btree_search_nonleaf_page`, `:5538` `btree_search_leaf_page`, `:19461` `btree_compare_key` | `src/backend/access/nbtree/nbtsearch.c:102` `_bt_search`, `:691` `_bt_compare` | same algorithm on both sides; the 4.1x profile-share difference (12.32% vs 2.98%) is a consequence of *how many* descents the chosen plan requires, not of descent cost | common to both engines |
| Leading-wildcard LIKE selectivity | `src/optimizer/query_planner.c:10068` `qo_like_selectivity` (reached from `:9936`) — estimated 0.0016 for `p_name like '%green%'` | `src/backend/utils/adt/like_support.c` `patternsel`/`like_selectivity` — PostgreSQL's `part` row estimate 121,206 vs actual 108,782 | CUBRID 3,200 vs actual 108,782 = 34.0x low; PostgreSQL 1.11x high | same stage, lower measured cost |

Absence claims were established by searching the whole optimizer directory
(`src/optimizer/*.c`, `*.h`) for `foreign`, `foreign_key`, `fkey`, `fk_` — 11 matches
total in `query_planner.c` + `query_graph.c`, all inside `qo_is_pk_fk_full_join` and its
single sort/limit caller — and by confirming `qo_is_pk_fk_full_join` has exactly one
call site (`grep -n qo_is_pk_fk_full_join src/optimizer/*.c` → declaration :263,
comment :9880, call :9927, definition :9955).

## 8. Causal decomposition details

### 8-a. What the numbers force

1. `R_wall = 2.115055x`, error band 2.0530x .. 2.1503x.
2. `F_plan` is real and measured from both sides: 1.384468x (PostgreSQL forced onto
   CUBRID's shape) and 1.542492x (CUBRID forced onto PostgreSQL's shape). The two are not
   the same number and should not be — each is measured on its own engine's constant
   factors — but they bracket the same conclusion: **the hash shape is worth ~1.4-1.5x on
   this query, on either engine.**
3. After removing the plan factor on anchor A, the remaining controlled cross-engine pair
   carries 1.527702x, split into `F_units` 1.177424x and `F_cpu` 1.297496x. Both engines
   are then running the *same shape*, and CUBRID still needs 1.30x the CPU at 0.85x the
   parallel width.
4. On the native pair, `F_cpu` is 1.786360x and decomposes into `F_work` 0.379590x and
   `F_cost` 4.706019x: CUBRID touches **2.63x fewer tuples** and spends **4.71x more CPU
   per touch**. That is the signature of trading sequential streaming for random probing.

### 8-b. Work accounting (`W`), stated explicitly

`W` = plan-node tuple touches: rows examined at each scan node, index entries walked, heap
lookups performed, hash-table rows built and probed. Every cardinality is ground truth
(`q9-groundtruth-*.out`, identical on both engines), cross-checked against
`q9-plan-act-pg.out` `loops × rows`.

```text
W_C (CUBRID index-NL) = 2,000,000  part heap scan
                      +   435,128  partsupp index entries
                      + 3,263,460  lineitem index entries (435,128 searches x 7.4983)
                      + 3,261,613  orders PK probes
                      + 3,261,613  supplier PK probes
                      + 3,261,613  nation PK probes (memoized: 625 misses)
                      + 3,261,613  group-by sort input
                      +       175  output rows
                      = 18,745,215

W_P (PostgreSQL hash) = 2,000,000  part index scan rows examined (1,891,218 filtered out)
                      +   435,128  partsupp index entries
                      +   100,000  supplier scan  +  100,000 hash build  + 435,128 probes
                      + 3,263,460  lineitem index entries
                      + 3,261,613  hash build (lineitem side)
                      +15,000,000  orders parallel seq scan + 15,000,000 hash probes
                      +       150  nation scan + 150 hash build + 3,261,613 probes
                      + 3,261,613  sort input
                      + 3,261,613  partial aggregate input
                      +     1,050  partial groups + 1,050 gather-merge rows + 175 output
                      = 49,382,743
```

### 8-c. Explanations considered and rejected, with the number that rejected each

- **"CUBRID has no parallel hash join, so it cannot use PostgreSQL's plan."**
  Rejected by direct A/B: `/*+ USE_HASH(orders, supplier) */` runs at **U = 6.23022 with a
  12.1704-unit peak**, the highest utilization measured anywhere in this query, and
  finishes in **7.118999 s**. The executor is not the constraint.
- **"This is Q08 again — a parallel-unit deficit (IMP-012)."**
  Rejected by magnitude: `F_units` is 1.177424x on the controlled pair and 1.184003x
  native, against a 2.115055x gap; and CUBRID's *rejected* plan reaches 6.23 units, above
  PostgreSQL's 5.89. Q09's unit factor is the smallest of the three.
- **"Buffer pool sizing / the working set does not fit (IMP-002)."**
  Rejected by the within-engine variant comparison: with the identical 8192 MB pool, the
  hash shape moves 23.61 GB/statement against the index-NL shape's 30.44 GB and finishes
  1.5425x sooner. PostgreSQL shows the mirror image (19.69 GB native vs 26.84 GB forced
  index-NL). Pool size is a constant across all four rows; the plan is not.
- **"The LIKE selectivity error (IMP-003) causes the wrong plan."**
  Rejected arithmetically: correcting only the `part` estimate (3,200 → 108,782, 34.0x)
  scales the lineitem-join estimate from 2.41 to ~82 rows — still **39,800x** below the
  true 3,261,613, and still far cheaper than the 984,797-cost hash plan. IMP-003 is a
  contributing error, not the deciding one.
- **"`HJ_MEM_ALLOC_CONSTANT`'s anti-hash offset (part of IMP-011) causes the wrong plan."**
  Rejected by size: the constant is 1,500 against a plan-cost gap of
  984,797 − 36,082 = 948,715, i.e. **0.16%** of the difference. Even zeroing it leaves the
  NL chain 26.9x cheaper on the cost scale.
- **"CUBRID's per-row executor cost is simply higher, so any plan loses."**
  Rejected by the controlled pair: on the *same* index-NL shape CUBRID needs 1.297496x
  PostgreSQL's CPU — real, and consistent with IMP-006/IMP-008/IMP-013 — but that is 1.30x
  of a 2.12x gap. The plan choice contributes more than the per-row cost does.

### 8-d. What remains after the plan factor

Even on the controlled pair, CUBRID needs 1.297496x the CPU at 0.85x the parallel width.
The profile attributes that residue to the buffer-manager and B-tree bands
(21.38% + 12.32% + 5.49% mutex of CUBRID's samples) against PostgreSQL's
(10.03% + 2.98%), which is the Q08-established IMP-013 mechanism operating on a plan that
fixes 1.86 M pages per statement. Q09 adds no new candidate there; it adds a second
measured instance and a much larger absolute band (11.68 core-s/statement vs Q08's
27.41% of a 4.34 core-s budget).

## 9. Improvements

### IMP-014 (new, P0) — multi-column FK join selectivity is estimated as a product of independent per-column selectivities

**Mechanism.** For each join term CUBRID computes one per-column-pair selectivity in
`qo_equal_selectivity()` (`query_planner.c:10189-10238`: histogram join selectivity, else
`1/MAX(index cardinality)`), and `planner_visit_node()` multiplies them
(`query_planner.c:7927`). When two terms are the two halves of one composite foreign key —
here `l_partkey = ps_partkey` and `l_suppkey = ps_suppkey`, exactly the child columns of
the campaign's own `fk_lineitem_partsupp` — the product understates the true selectivity by
the ratio between the parent's row count and the product of the two column NDVs:
`1.25E-07 / (1.00319E-05 × 5E-07) = 24,920x`. PostgreSQL fires
`get_foreign_key_join_selectivity()` (`costsize.c:5698`, `:5818`) *before* forming any
product: it matches the clause set against `root->fkey_list`, removes the matched clauses
and substitutes `1/parent_rows` (`costsize.c:6008`), with the in-tree comment naming this
exact failure mode ("especially for multi-column FKs where that function's assumption that
the clauses are independent falls down badly", `costsize.c:5810-5813`).

**Why the direction follows.** CUBRID does not lack the metadata: `qo_is_pk_fk_full_join()`
(`query_graph.c:9955`) already walks the node's index entries, tests
`SM_CONSTRAINT_FOREIGN_KEY` and compares `fk_info->ref_class_pk_btid` against the parent's
PK B-tree — the same structural test PostgreSQL performs — but its single caller
(`:9927`) uses the answer only to exclude nodes from sort/limit evaluation. The change is
to reuse that predicate in the cardinality path: when the set of join terms between two
nodes covers all columns of an FK whose parent side is the other node's PK, replace the
product of their selectivities with `1/parent_cardinality`.

**Measured effect.** Direct A/B on the same engine, same block regime, same load gate:
CUBRID native 10.980999 s → `/*+ USE_HASH(orders, supplier) */` 7.118999 s = **1.5425x**,
which would move Q09's `R_wall` from 2.115055x to 1.371218x. Supporting projection from
the plan dump's own cost numbers: the NL chain is costed 36,082 against the hash plan's
984,797 while being 1.54x slower; restoring the true 3,261,613-row flow multiplies the
three remaining NL levels' per-probe costs (4-5 each) by ~3.26 M, putting the chain above
13 M and inverting the comparison decisively.

**Priority P0** — largest single measured factor in a 2.115x gap, on a defect that is
data-independent (any multi-column FK join at any scale) and whose fix reuses an existing
in-tree predicate. **Category** optimizer. **Difficulty** medium: the predicate exists and
is unit-testable; the work is threading an FK-aware selectivity override into
`planner_visit_node()`'s term loop and ensuring it fires once per FK (PostgreSQL's own
"chicken out and ignore this FK" guard at `costsize.c:5940-5960` is the precedent for
avoiding double-counting). **Risk**: plan changes on FK-joined workloads; cardinality
estimates rise, so hash/merge plans become reachable where NL was previously chosen —
correctness is unaffected (selectivity is not a semantic filter), but plan regression
testing on the full TPC-H set is required. **Validation**: (1) `q9-plan-est-cubrid.out`
must print a lineitem-join cardinality within an order of magnitude of 3,261,613 instead
of 2; (2) the natively chosen plan must become the hash tree; (3) the Q09 headline must
land at the measured 7.119 s ± the 3.20% CUBRID band; (4) Q07/Q08 must not regress —
Q08 is a positive control where the NL choice is correct and must survive. **Upstream
precedent**: PostgreSQL commit series that introduced `get_foreign_key_join_selectivity`
(PG 9.6, `costsize.c`) is the direct precedent for the change shape; no CBRD issue/PR
implementing FK-aware join selectivity was found in the pinned tree.

**Relations.** Predecessor: none. Alternative: none (the LIKE and constant-offset
explanations were measured and rejected in section 8-c). Contains/overlaps: IMP-011 —
both change which join method is chosen, but IMP-011's mechanism is parallel-degree-blind
costing plus the anti-hash constant, while IMP-014's is the cardinality that feeds those
cost functions. On Q09 IMP-011's constant accounts for 0.16% of the cost gap, so the two
must not have their effects summed; IMP-014 is the deciding term here and IMP-011 was the
deciding term on Q07.

### Existing candidates confirmed by Q09 (relations added, no new IDs)

| ID | Q09 evidence | effect on Q09 |
|---|---|---|
| IMP-003 (LIKE selectivity) | `p_name like '%green%'` estimated 3,200 vs actual 108,782 = **34.0x low** (`q9-plan-est-cubrid.out` term[8] sel 0.0016) | contributing error only; section 8-c shows correcting it alone does not change the plan |
| IMP-005 (trace per-level merge multiplier) | depths 3/4/6 reported exactly 2x/3x/5x ground truth; depth 5 at 3.74x is a new variant of the same defect (`q9-trace-cubrid.out` vs `q9-groundtruth-*.out`) | none on wall; blocks use of trace counters as work numerators |
| IMP-007 (synchronous single-page pread) | **1,861,608 read syscalls per statement**, 16,382 bytes each, `read_bytes=0` (all from OS page cache), 16.57% of the CUBRID profile in the kernel read path | bounded by the 9.05 core-s/statement kernel-read band |
| IMP-011 (join-method selection) | second instance of an NL-over-hash misselection; here the anti-hash constant is 0.16% of the cost gap, so Q09 refines IMP-011's scope rather than confirming its mechanism | see IMP-014 ranking |
| IMP-013 (page fix/unfix LRU surgery) | **21.38%** of CUBRID's profile (11.68 core-s/statement) vs PostgreSQL's 10.03% (3.07 core-s), plus 5.49% libpthread mutex; 22.1x PostgreSQL's context-switch rate | the dominant part of the 1.297496x residual `F_cpu` on the controlled pair |
| IMP-002 (pool retention) | 30.44 GB/statement re-read at an 8192 MB budget | present but rejected as the deciding factor (section 8-c) |

### Ranking

1. **IMP-014** — 1.5425x, direct A/B, deciding factor.
2. **IMP-013** — the largest identified share of the 1.297496x same-shape CPU residual.
3. **IMP-007** — 9.05 core-s/statement kernel read path, upper bound, partly a consequence
   of the plan chosen (the hash shape reads 23% fewer bytes).
4. **IMP-003** — real 34.0x estimate error, but shown not to change the plan alone.
5. **IMP-005** — no wall effect; an evidence-integrity defect.

## 10. Evidence index

Format: `claim → raw file → formula → evidence type → SHA-256`. All paths are relative to
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q09/`.

| Claim | Raw file | Formula | Evidence type | SHA-256 |
|---|---|---|---|---|
| CUBRID headline median 10.980999 s | `Q09-cubrid-headline-block1.json` | median of `measured_times_s` | direct measurement | `a19cf3560e0cd810389e29cd6c75e4a4050b25f8cb295af998b0fdef63725522` |
| PostgreSQL headline median 5.191826 s | `Q09-postgresql-headline-block1.json` | median of `measured_times_s` | direct measurement | `7ee7ec44385f036f81625f52a9ed29d20685502de6ac542137dde0a5a0e66dd9` |
| `R_wall` 2.115055x and both anchors | `Q09-causal-card.json`, `q9-card-calc.txt` | section 16 formulas | derived | `dec4616ef56125401bcb4cac6f28cab8eb9501a971f3ae0a0c5ed48236bcc228`, `520d447d729cdfd691a33daa0e261d89cb672b70cc28daa824e3753d9ad8586f` |
| `F_plan` 1.384468x (anchor A) | `Q09-postgresql-idxnl-headline.json` | `T_P_idxnl/T_P_native` | direct A/B | `db0bcce809bf7a163af1727062456014b8c516c9e2ad1cf2fddae1842abd5f1a` |
| `F_plan` 1.542492x (anchor B) | `Q09-cubrid-hashos-headline.json` | `T_C_native/T_C_hashos` | direct A/B | `c65dd2eb094998f4affc5a771c8f17a5187488f2ac8b81b005a32ed98084d7e3` |
| `U_C` 4.97459, TWU 4.9644 | `Q09-cubrid-headline-telemetry-run3.json` | `CPU_block/T_block` | profile attribution | `b3da43f0ac5593bc3373df5f6bfdbf54052d859fa568805865c17a05c6a734a2` |
| `U_P` 5.88993, TWU 5.8428 | `Q09-postgresql-headline-telemetry-run2.json` | `CPU_block/T_block` | profile attribution | `3dc248e1a70802e33a713495864e5c0e961b3210ca4c9136a8630532caf9a7d7` |
| `U_C_hashos` 6.23022, peak 12.1704 | `Q09-cubrid-hashos-headline-telemetry.json` | per-TID sampler, actual timestamp deltas | profile attribution | `b156445ed1bb0cec34678e596761f0ebeb45009d633ebdfb48955c8ae9fed46d` |
| `U_P_idxnl` 5.85720 | `Q09-postgresql-idxnl-headline-telemetry.json` | per-TID sampler | profile attribution | `b12e5aa08c9aaa1a6efba09b808096c82b401f50ddc9391524a855881fafdf9e` |
| CUBRID plan shape + estimates (card 2, cost 36,082) | `q9-plan-est-cubrid.out` | `SET OPTIMIZATION LEVEL 514` | direct measurement | `ef4e81c0104111a29ace716d10bad32526d60864ea12508db62be303b89f3d0e` |
| CUBRID controlled plan (hash tree, cost 984,797) | `variants/plan-USE_HASH_ORDERS_SUPPLIER.out` | `SET OPTIMIZATION LEVEL 514` + hint | direct measurement | `a4a4a3f3de2c13dca28f3da5b1deef8bc84b24092f739c12f2355d050f1b654b` |
| PostgreSQL controlled plan == CUBRID's shape | `variants/plan-nestloop_forced.out` | `EXPLAIN` with `enable_hashjoin=off, enable_mergejoin=off` | direct measurement | `96b80d9d09c20fe312fcedf98081ae264aff547de0f1c5192ab56a99739bdf55` |
| PostgreSQL actual plan, 5 workers, 3,261,613 rows | `q9-plan-act-pg.out` | `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, TIMING)` | direct measurement | `82d441b5f5ff33d984212d3301edc870cef5998deab9281cef9be7bec9f2d706` |
| CUBRID trace, 5 parallel workers, per-level counters | `q9-trace-cubrid.out` | `SET TRACE ON; … SHOW TRACE;` | direct measurement | `45fd0089a847fd6c442bcd163281946b5f32b05d4e3a16a073275bb20f96a0f2` |
| Ground-truth cardinalities, both engines identical | `q9-groundtruth-cubrid.out`, `q9-groundtruth-pg.out` | staged `count(*)` | direct A/B | `585bda34fe61c7e91f9b022d02c20db5920e8ddbc96d6606774853d78fd7a73e`, `1ce2ce597ac379f55401f695c91934936cc5057e11eed525e655b035177c3186` |
| Result equivalence, 175 ordered rows | `q9-correctness.json` | SSOT section 11 comparator | direct A/B | `8e80d702646adaf400baa81129f19ef0ef764ad1fa1ea156d96ebf614efb5ab3` |
| CUBRID profile bands (pgbuf 21.38%, btree 12.32%) | `profile-cubrid-flat.txt`, `q9-profile-bands.txt` | `perf report --no-children`, band sums | profile attribution | `61b7baf42b986cfb501d6d61c479ad1ce53cdcf0ce2f7b187c2d50fdee4fb3a0`, `1638405d64f5eeb8ca0182e39710010dd8f251329e4e11dcefa39af8387fae6c` |
| PostgreSQL profile bands (hash 14.43%, buffer 10.03%) | `profile-pg-flat.txt` | same | profile attribution | `e066e3c9d3dd9fe28af6c87b04bde229eb9013478273258dc17468fec3ee0233` |
| CUBRID 5.022 CPUs, IPC 1.11, 395.432 G insn | `perf-stat-cubrid.txt` | `perf stat -p <cub_server>` | direct measurement | `c4ab5389b5f9ccf8b29196c4b456b0dd18b721a35b59129a0c5548bf7556526e` |
| PostgreSQL 5.617 CPUs, IPC 1.31, 526.022 G insn | `perf-stat-pg.txt` | `perf stat -p <postmaster>` | direct measurement | `dabdb362b531f807841da861096a41ebdfb1d7463110b2ebabcab41018b11748` |
| CUBRID 1,861,608 preads / 30.497 GB per statement | `Q09-cubrid-buffer-io-diag.json` | `/proc/<cub_server>/io` delta ÷ 4 | direct measurement | `ed7c3aa9c1419a5f506ba514721e921bb173a53059eb8f984ede20f085371c4b` |
| PostgreSQL 2,273,118 preads / 18.647 GB per statement | `Q09-postgresql-buffer-io-diag.json` | `/proc/<postmaster>/io` delta ÷ 4 | direct measurement | `18bcce6ff5ecf9596dc2cba129fe0bb2d217126a2a15000540ac0981a0bbf26c` |
| WARM parameter derivation | `q9-convergence-cubrid.json`, `q9-convergence-pg.json` | 40-statement half-split level test | direct measurement | `8760f7060b2aae9017bf2dcadd9f7170b3fe1f3e38107b1db24a6874cf63ffb0`, `612a86fb4568f66d2a7abeae5cdca7b4bfd3d5e3ec9dd9a4950333b1254032de` |
| Pre-block identity/schema/ownership/NUMA gate | `preflight-Q09.txt` | `harness/preflight_check.sh Q09 …` | direct measurement | `4f862666596c0e48f2b5d8d3ee297bdac5071d1bc8baba67db11b5ea93da9254` |
| Post-block ownership/cpuset/orphan gate | `q9-postcheck.txt` | `work/Q09/postcheck.sh` | direct measurement | `fbb05f7b7dd4922e98d111cf47527be9e47eeff9d3338c97dd29bac02f53ef2c` |

Full artifact list with byte sizes, creation commands, producing stages and validity:
`reports/Q09/raw-manifest.json` (236 artifacts, 0 invalid).

## 11. Notion sync

The GJC/tmux worker session has no Notion connector and performed **no** Notion write
(SSOT section 21 execution boundary). Its duty ended at committing and pushing this report,
the raw manifest and the improvement ledger to `origin/main`.

Write path taken: **path 3** — an idempotent record appended to
`reports/notion_backfill_pending.jsonl` with key
`campaign_id + QNN + session_id + report_commit + content_fingerprint`, to be consumed by
the section 23 reconciler subagent (which holds the Notion tools) reading the pushed commit
as source of truth. Pending is cleared only after a server-side refetch.

Content the mirror must carry for Q09: the causal card with both anchors and the full
factor table, headline timings, the four-row plan comparison of section 4-c, the
estimated-vs-actual cardinality table of section 4-d, both engines' top profile symbols,
the full section 7 source contrast with `file:line` on both sides, the section 8-c
rejected explanations with their rejecting numbers, and IMP-014 as its own
improvement-registry page plus relation edges to IMP-002/003/005/007/011/013.

## 12. Completion checklist

| Gate (SSOT section 26) | Status |
|---|---|
| preflight and correctness status recorded | ✅ `preflight-Q09.txt` (all gates PASS), `q9-correctness.json` (`result-equivalent-at-SF10`) |
| three valid headline values per completing engine | ✅ CUBRID 11.001 / 10.980999 / 10.857; PostgreSQL 5.240345 / 5.183993 / 5.191826 — one block each, accepted on attempt 1 with `CLEAN` load verdict |
| timeout confirmations | n/a — neither engine censored (max statement 11.0 s against a 300 s timeout) |
| plan, execution, profile, source contrast complete | ✅ sections 4, 5, 6, 7 |
| causal multiplier card has evidence or explicit `UNMEASURED` | ✅ every factor numeric with formula, raw pointer and evidence type; residual −0.000000% / +0.000000% |
| Git improvement ledger deduplicated and committed | ✅ IMP-014 allocated (`next_id` → IMP-015); Q09 relations added to IMP-002/003/005/007/011/013 rather than new IDs |
| Notion relations synced or idempotent backfill durable | ✅ backfill record appended (write path 3); reconciler subagent owns the Notion write |
| every claim indexed to raw evidence and checksum | ✅ section 10 + `raw-manifest.json` (236 artifacts, SHA-256 each) |
| report, manifest, registry committed, pushed, reachable from `origin/main` | ✅ see `report_commit` in the status block |
| `QUERY_COMPLETE` emitted | ✅ |
| current session removed and absence verified | pending — executed by the reconciler after this push (a session cannot remove itself) |

Child tmux driver sessions used for the long-running blocks (`q09corr`, `q09conv`,
`q09hl`, `q09plan`, `q09gt`, `q09probe`, `q09var`, `q09diag`, `q09perf`) were each polled
to their `DRIVER_EXIT` marker and killed by exact name; `tmux ls` shows none remaining.
