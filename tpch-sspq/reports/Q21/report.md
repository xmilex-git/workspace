# TPCH-SSPQ FK campaign — Q21 report

TPC-H Query 21, Suppliers Who Kept Orders Waiting.

## 1. Identity

| Field | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q21 |
| SSOT commit (session pin) | `1b5fbc021353b16cf4b7375695fd6cad4ec4402d` |
| SSOT blob SHA | `510478846bff081d3223d3835069283a7cd2e47b` |
| GJC session ID | `gajae_code_msbgsf4l_4tombfrn` |
| Raw root | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q21` |
| Engine block order | Q21 is odd → CUBRID block first, then PostgreSQL (SSOT section 12) |
| Scale | TPC-H SF10, histogram-enabled controlled comparison |

| Engine | Source SHA | Install prefix | Binary SHA-256 | ELF Build ID |
|---|---|---|---|---|
| CUBRID | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9` | `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` | `4df41ee21300bf617bccd5e1d5c8522b074ef86e` |
| PostgreSQL | `5713b437abed7085e7d59849c6e9e0f4f469633d` | `/home/cubrid/pg/pg20devel-5713b437` | `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` | `5f2cb2987765c612638c278f85cfc85c211fffe1` |

Both running binaries were resolved through `/proc/<pid>/exe` and their SHA-256 matched the frozen
`reports/bootstrap/build-manifest.json` (`frozen: true`).

**SSOT pin versus repository HEAD.** The session is pinned to `ssot_commit 1b5fbc0` /
`ssot_blob 5104788`. Repository `HEAD` and `origin/main` were at `29f3b14` (Q20's report and Notion
backfill commits) throughout Q21, and `git rev-parse HEAD:tpch-sspq/SSOT.md` at that commit is
**`510478846bff081d3223d3835069283a7cd2e47b`** — byte-identical to the pinned blob. The measurement
contract therefore did not move: `ssot_drift=NONE` on both the preflight and the postflight capture.
No pull, branch switch or SSOT edit occurred during the query.

**Preflight (stage 14.1)** — `q21-preflight.txt`:

- branch `main`, `HEAD == origin/main == 29f3b14`, `git status --porcelain -- tpch-sspq` empty,
  `ssot_drift=NONE`.
- cpuset: 30 engine TIDs (cub_master 2, cub_server 20, postmaster 1, pg children 7),
  **0 off-cpuset** → PASS. External SUT-set load 0.236 core-s/s against the 6.0 threshold.
- Ownership gate `OK` on both engines: `cub_master` pid 1433697 on port 1523, `cub_server`
  pid 2646189, postmaster pid 1433696 on port 5442, all campaign-owned, all resolved through
  `/proc/<pid>/exe`.
- Schema contract: CUBRID 8 FK-owned B-trees, PostgreSQL 8 FKs / 8 `idx_fk_*` / 8 `convalidated`,
  exact child-column order including composite `fk_lineitem_partsupp (l_partkey, l_suppkey)`.
- Row counts identical on both engines (lineitem 59,986,052; orders 15,000,000; supplier 100,000;
  nation 25).
- Statistics: CUBRID `update_statistics_update_histogram=y`, `default_histogram_bucket_count=300`;
  PostgreSQL `default_statistics_target=100`.
- Parallel/buffer contract: CUBRID `parallelism=6`, `max_parallel_workers=100`,
  `data_buffer_size=8.0G`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`,
  `parallel_leader_participation=on`, `shared_buffers=8192MB`, `statement_timeout=300000 ms`,
  `jit=off`. Label: **configured node/gather-cap comparison**, **configured-equal buffer budget**.
- Query provenance: `queries/q21-cubrid.sql`, `queries/q21-pg.sql` and the canonical
  `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q21.sql` all SHA-256
  `2a75d4908a2adad3b7a0c2a2cb6455e478c1f1ab9b92666d4dd6bd1f261434ce`. `queries/diff/q21.diff` is
  **0 bytes** and `cmp` confirms the two dialect files are byte-identical: **Q21 has zero dialect
  changes**. No hint, no join reordering, no subquery rewrite, no extra predicate, no semantic cast
  — there was nothing to change.

**Postflight** — `q21-postflight.txt`: same executables and SHA-256, same pids (2646189 / 1433696),
30 engine TIDs with **0 off-cpuset**, external load 0.330 core-s/s, 8 FK / 8 `idx_fk_*` /
8 `convalidated` unchanged, `ssot_drift=NONE`, working tree still clean. **No server was stopped,
started or restarted at any point during Q21.**

`dynamic_shared_memory_type=mmap` **is** decision-relevant here: PostgreSQL's natural Q21 plan is a
`Gather` over a `Nested Loop Anti Join` whose inner side is fed by a `Hash Join`, with 5 workers
launched and 135,716 rows crossing the gather queue. The plan reached its natural shape and no
`could not resize shared memory segment` error occurred; the configured value is recorded as
section 9 of the SSOT requires.

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored; no timeout on either engine. The slowest single
statement anywhere in Q21 was the traced CUBRID run at 65.40 s against the 300 s rule of section 13,
and the slowest measured statement was 50.41 s.

| Field | Value |
|---|---|
| Status | `result-equivalent-at-SF10` |
| Rows | 100 |
| `ORDER BY` present | yes (`order by numwait desc, s_name`) → ordered sequence compared exactly |
| Columns | `s_name` (char), `numwait` (integer count) |
| Absolute difference | 0 |
| Tolerance exercised | **none** — Q21's only numeric column is an integer `count(*)`, so the section 11 decimal rule is not reachable |

Row count, row order and every byte of both columns match (`q21-correctness.json`,
`q21-correctness-cubrid.out`, `q21-correctness-postgresql.out`). The result is independently
confirmed by the section 5 ground-truth probe, which counts **39,448** qualifying
(supplier, lineitem) pairs over **4,009** distinct suppliers on **both** engines through a
differently-written equivalent query (`q21-groundtruth.sql`) — the same 4,009 groups the CUBRID
trace and the PostgreSQL `GroupAggregate` each report, of which the query returns the top 100.

## 3. Headline timings and causal multiplier card

### 3-a. Causal multiplier card

```text
R_wall [wall]
= F_plan [plan-shape]
× F_units [total-query-CPU/wall correction, explained by TWU]
× F_cpu [total query CPU-seconds]

F_cpu [total query CPU-seconds]
= F_work [named work event]
× F_cost [CPU-seconds or cycles / work event]
```

```text
16.020754x = 3.064206x [plan] × 2.068640x [units] × 2.527436x [CPU-sec]

2.527436x [CPU-sec] = 0.869750x [work] × 2.905936x [cost]
```

**Q21 is a query CUBRID loses, and the plan defect is CUBRID's, so the `F_plan` anchor is on
CUBRID.** Anchor direction: **CUBRID native → CUBRID controlled (`late`)**, a same-engine A/B in
which the controlled variant expresses, in CUBRID, the evaluation order PostgreSQL reaches by
converting the two correlated sublinks into a semi-join and an anti-join — the expensive
`EXISTS` / `NOT EXISTS` predicates evaluated only on the supplier-restricted stream instead of at
the `lineitem l1` scan (section 4). `F_units` and `F_cpu` are computed on the **remaining controlled
cross-engine pair** — CUBRID controlled versus PostgreSQL native. Native and controlled denominators
are not mixed:

```text
R_wall = T_C/T_P = (T_C/T_Cc) × (T_Cc/T_P)
                     F_plan     F_units × F_cpu
```

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `R_wall` | 16.020754x | wall seconds | median of 3 measured WARM statements, block1 | `T_C / T_P` | `Q21-cubrid-headline-block1.json`, `Q21-postgresql-headline-block1.json` | direct A/B |
| `F_plan` | 3.064206x | wall seconds | same engine, same block regime, same load gate, same 12-statement WARM gate, byte-identical result | `T_C / T_Cc` | `Q21-cubrid-headline-block1.json`, `Q21-cubrid-late-headline-block1.json` | direct A/B (same-engine controlled) |
| `F_units` | 2.068640x | core-seconds per wall-second | total query CPU over the 4-statement block ÷ sum of that block's statement walls | `U_P / U_Cc` | `Q21-postgresql-headline-telemetry.json`, `Q21-cubrid-late-headline-telemetry.json` | per-TID sampler, actual timestamp deltas |
| `F_cpu` | 2.527436x | total query CPU-seconds | per measured statement, `U × t` | `CPU_Cc / CPU_P` | same two telemetry artifacts | per-TID sampler |
| `F_work` | 0.869750x | evaluations of the two correlated `lineitem` subqueries (`EXISTS` on `l2` + `NOT EXISTS` on `l3`) | one measured statement | `W_Cc / W_P` | `q21-trace-late.out`, `q21-plan-act-pg.out`, `q21-groundtruth-{cubrid,pg}.out` | direct count (three independent instruments) |
| `F_cost` | 2.905936x | core-seconds per subquery evaluation | same | `(CPU_Cc/W_Cc)/(CPU_P/W_P)` | derived, `q21-causal-card.txt` | profile attribution |

Measured inputs (`q21-causal-card.txt`, `q21-causal-card.json`):

| Quantity | Value |
|---|---|
| `T_C` CUBRID native median | 49.394998 s |
| `T_P` PostgreSQL native median | 3.083188 s |
| `T_Cc` CUBRID controlled (`late`) median | 16.120000 s |
| `U_C` | 5.75237 core-s/wall-s |
| `U_P` | 6.32660 core-s/wall-s |
| `U_Cc` | 3.05834 core-s/wall-s |
| `CPU_C = U_C·T_C` | 284.138545 core-s |
| `CPU_P = U_P·T_P` | 19.506097 core-s |
| `CPU_Cc = U_Cc·T_Cc` | 49.300410 core-s |
| `W_C` CUBRID **native** subquery evaluations (not a card input) | 35,975,762 |
| `W_Cc` CUBRID controlled subquery evaluations | 1,442,116 |
| `W_P` PostgreSQL semi/anti-join probes | 1,658,082 |

**Reading the card in words.** PostgreSQL finishes Q21 in **1/16.020754** of CUBRID's wall, i.e.
**16.0208x faster**, the second-largest cross-engine gap in the campaign after Q19. The single
largest factor is CUBRID's own: **3.064206x** comes from *where* CUBRID is forced to evaluate the two
correlated sublinks. Removing only that — same engine, same query semantics, byte-identical
100-row result — takes CUBRID from 49.394998 s to 16.120000 s. The remaining **5.228355x** is a
genuine execution gap on a matched evaluation order, and it splits almost evenly: **2.068640x**
because PostgreSQL sustains 6.32660 active units where CUBRID's controlled plan sustains 3.05834,
and **2.527436x** because CUBRID burns 2.53x the CPU-seconds. `F_work` is **below 1**: at matched
evaluation order CUBRID actually performs **13.0% fewer** correlated evaluations than PostgreSQL
(1,442,116 against 1,658,082, because CUBRID's controlled shape applies the `o_orderstatus = 'F'`
restriction *before* the sublinks and PostgreSQL applies it after), so the whole of `F_cpu` and more
is `F_cost`: **2.905936x** the CPU per evaluation.

**`F_work` is a measurement, not an assumption, and every count is confirmed twice.** The
independent `COUNT(*)` ground-truth probe (`q21-groundtruth.sql`, run separately on both engines)
returns **identical** values on CUBRID and PostgreSQL for all seven cardinalities: 4,010 Saudi
suppliers, 7,309,184 `'F'` orders, 29,058,120 lineitems in `'F'` orders, 18,321,400 *late* lineitems
in `'F'` orders, 1,522,366 late lineitems of Saudi suppliers, 734,523 late Saudi lineitems in `'F'`
orders, 39,448 total qualifying pairs. Each of those reappears in an engine instrument:
PostgreSQL's `Index Searches: 1522366` (anti join) and `Index Searches: 135716` (semi join);
CUBRID's controlled trace `readkeys: 734523` and `readkeys: 707593`; CUBRID's native trace
`readkeys: 36642798` and `readkeys: 35308724`, which are exactly **2×** the true counts because at
that plan depth the trace merges a level's counters twice (IMP-005, calibrated in section 4-c).

**Reconstruction residual: +0.0000%.** As on Q17, Q19 and Q20 this must be read honestly: with
`F_plan = T_C/T_Cc` and `F_units × F_cpu = T_Cc/T_P` the product telescopes to `T_C/T_P` by
construction, so the residual tests arithmetic, not independence. The card's genuine validation is
that `U`, its only non-wall input, is confirmed by an instrument the card does not use — `perf stat`
"CPUs utilized" over a separate replay window:

| Configuration | sampler `U` (block) | `perf stat` CPUs utilized | agreement | TWU (block) | peak units | serial tail |
|---|---|---|---|---|---|---|
| CUBRID native | 5.75237 | 5.728 | **−0.42%** | 5.7502 | 7.0134 | 0.063 s |
| CUBRID controlled (`late`) | 3.05834 | 3.199 | +4.60% | 3.0574 | 7.4088 | 0.051 s |
| PostgreSQL native | 6.32660 | 5.856 | −7.44% | 6.3367 | 7.5883 | 0.235 s |

CUBRID native's two instruments agree to 0.42% and its TWU to −0.04%. PostgreSQL's −7.44% has a
measured cause rather than an excuse: `perf stat` is attached to the postmaster *before* the client
connects, so inherit-on-fork counts the leader and every statement's parallel workers but **not**
the `pg_io_worker` processes, which were forked at server start. Those workers are 6.51 of the
79.22 core-s the sampler attributes to the block (8.22%); PostgreSQL's **executor-only** `U` is
5.8067, against which `perf stat` agrees to **+0.85%**. The `perf` numbers are used as a
direction-and-magnitude cross-check, never as a card input.

### 3-b. Headline timings

All three measured statements from every accepted block. Block 1 is the headline (campaign
convention since Q12); blocks 2–3 are block-to-block stability evidence.

| Configuration | block 1 | block 2 | block 3 | block-1 median | mean | sd |
|---|---|---|---|---|---|---|
| **CUBRID native** (headline) | 49.249999 / 49.394998 / 49.410998 | 49.852998 / 49.662999 / 49.712998 | 49.273999 / 48.760998 / 49.363998 | **49.394998 s** | 49.351998 | 0.088696 |
| **PostgreSQL native** (headline) | 3.083188 / 3.083793 / 3.081962 | 3.081031 / 3.079621 / 3.076704 | 3.082668 / 3.096682 / 3.075944 | **3.083188 s** | 3.082981 | 0.000933 |
| CUBRID controlled (`late`) | 16.425 / 16.095999 / 16.120000 | 16.247999 / 16.151 / 16.179999 | 16.093 / 16.099999 / 16.110999 | 16.120000 s | 16.213666 | 0.183413 |

| Field | Value |
|---|---|
| CUBRID median seconds | **49.394998** |
| PostgreSQL median seconds | **3.083188** |
| Median wall ratio `T_C/T_P` | **16.020754x** (PostgreSQL 16.0208x faster) |
| Correctness | `result-equivalent-at-SF10` |
| Censoring | none |

Three values are reported and the median is the headline. Mean and within-block standard deviation
are given above. **No confidence interval is claimed from three values.** Block-median spread across
the three independent blocks is 0.889% (CUBRID native), 0.116% (PostgreSQL) and 0.496% (CUBRID
controlled); recomputing the whole card on block 2 or block 3 moves `R_wall` by at most **0.99%**
and `F_plan` by at most **0.39%** (`q21-causal-card.txt`, sensitivity table). Every accepted block
carries load-gate verdict `CLEAN` under **both** the strict per-sample rule and the contract-window
rule, with `external_max` between 0.459 and 0.766 core-s/s against the 6.0 threshold.

**The WARM gate was expensive on this query, and every rejection is retained.** Nine 12-statement
CUBRID warm-up runs were rejected across the six CUBRID blocks — two for a monotone trailing window,
seven for a half-split trend just over the inherited 1.0% tolerance (largest +1.4338%). **No
threshold was relaxed: every accepted block passed the inherited gate.** A moving-block bootstrap
over all 76 CUBRID steady-state statements measured on Q21 (`q21-warm-gate-bootstrap.txt`, block
length 6, 20,000 resamples) shows why the gate misfires here: at n=12 the null distribution of the
gate's own trend statistic has p95 **1.8278%** and max **3.2699%**, so a 1.0% tolerance rejects
roughly a quarter of genuinely converged runs, and `P(monotone trailing window)` is a further
5.540%. The cause is physical rather than statistical — Q21's working set is 13.0 GB against an
8192 MB pool on both engines, so each statement inherits whatever the previous one evicted and the
level wanders 4.3840% peak-to-peak with no trend. The gate that matches the measured null
(`WINDOW=4`, `LEVEL_TOL=0.035`, `SPREAD_SANITY=0.045`) is recorded in `q21-warm-gate-params.txt` but
**was not applied**, because re-measuring blocks that already passed a stricter test cannot improve
them.

## 4. Plan

Both engines compute the same thing and disagree about one decision only: **what a correlated
`EXISTS` is**. That single difference produces every structural divergence below.

### 4-a. CUBRID native (`q21-plan-est-cubrid.out`, `q21-trace-cubrid.out`)

CUBRID does not convert the sublinks into anything. `qo_rewrite_subqueries()` flattens only
*uncorrelated* `IN` / `= SOME` forms; a `PT_EXISTS` receives one treatment and one only — a `LIMIT 1`
pushed inside it (`qo_add_limit_clause`, visible as `inst_num()<=1` in the dumped subplans). Both
sublinks therefore survive into the join graph as **predicates over one relation** (`lineitem l1`),
and `qo_analyze_term()` classifies any single-relation term as a `sarg` of that relation's scan:

```text
Join graph terms:
term[3]: [nation].n_name='SAUDI ARABIA'                            (sel 0.04)   (sarg term)
term[4]: exists (select l2.l_orderkey from lineitem l2
          where l2.l_orderkey=l1.l_orderkey
            and (l2.l_suppkey<>l1.l_suppkey) and inst_num()<=1)    (sel 0.1)  (rank 9)  (sarg term)
term[5]: l1.l_receiptdate range (l1.l_commitdate gt_inf max)       (sel 0.1)  (rank 2)  (sarg term)
term[6]: [orders].o_orderstatus='F'                                (sel 0.4821) (sarg term)
term[7]: not exists (select l3.l_orderkey from lineitem l3 ...)    (sel 0.9)  (rank 10) (sarg term)

Query plan:
temp(order by)                                            cost 123427506 card 4441
  temp(group by)
    hash-join  edge: term[0]                              -- x nation('SAUDI ARABIA')
      hash-join  edge: term[1]                            -- x supplier
        idx-join
          outer: sscan orders   sargs: term[6]            cost 189189  card 7231500
          inner: iscan l1  index: fk_lineitem_orders term[2]
                 sargs: term[4] AND term[5] AND term[7]   subqs: 0 1
        inner: sscan supplier                             cost 1531 card 100000
      inner: sscan nation  sargs: term[3]
```

The two sublinks are `subqs: 0 1` on the `l1` index scan, which is the **inner of an orders-driven
index join**. The Saudi-supplier restriction is applied two hash joins *above* it. So the correlated
subqueries run on every late lineitem of every `'F'` order.

Traced actuals (`q21-trace-cubrid.out`; the traced statement costs 65.40 s against the 49.39 s
headline because `SET TRACE ON` instruments 36 million subquery evaluations — no trace *time* is
used anywhere in this report, only counts):

| Node | Measured |
|---|---|
| `sscan orders` | **parallel workers: 6**, readrows 2,380,011–2,525,461 per worker (15,000,000 total) |
| `iscan l1 fk_lineitem_orders` | readkeys **7,309,184** (= the `'F'` order count), rows **29,058,120**, lookup rows **18,321,400** (= late lineitems in `'F'` orders), btree time 8,498 ms, fetch 23,146,499, ioread 470,614 |
| correlated `iscan l2 fk_lineitem_orders` (`EXISTS`) | readkeys 36,642,798 → **18,321,399** after the IMP-005 depth-3 ÷2, rows 44,505,876, lookup rows 35,308,724 → **17,654,362**, fetch 154,434,270, ioread 44,544 |
| correlated `iscan l3 fk_lineitem_orders` (`NOT EXISTS`) | readkeys 35,308,724 → **17,654,362**, rows 64,802,188, lookup rows 33,327,580 → **16,663,790**, fetch 170,728,360, ioread 42,942 |
| `SUBQUERY_CACHE` | **hit: 2, miss: 110,772, size: 15,101,184, status: disabled** |
| supplier hash join `PROBE` | readrows/readkeys/rows **990,572** (= 17,654,362 − 16,663,790, the rows surviving both sublinks) |
| nation hash join `PROBE` | rows **39,448**, parallel workers: 3 |
| `GROUPBY` | hash: partial, sort: true, rows **4,009** |
| top `SELECT` | fetch 1,016,255, `/proc` `syscr` delta **670,508** and `rchar` delta **10.98 GB** for the one traced statement |

### 4-b. PostgreSQL native (`q21-plan-est-pg.out`, `q21-plan-act-pg.out`)

`pull_up_sublinks_qual_recurse()` converts `EXISTS` into a `JOIN_SEMI` and `NOT EXISTS` into a
`JOIN_ANTI`. They are now *relations in the join graph*, and the cost model puts both **above** the
hash join that restricts `lineitem` to the 4,010 Saudi suppliers:

```text
Limit                                              (cost 1497440.63)  actual 3286.699 ms  rows=100
  Sort / GroupAggregate                            rows=4009   (input 39,448 rows)
    Nested Loop  x orders_pkey  Filter o_orderstatus='F'   loops=81,045    rows=39,448
      Nested Loop Semi Join                        rows=135,716
        Gather (Workers Planned 5, Launched 5)     rows=135,716
          Nested Loop Anti Join                    loops=6  rows=22,619 per worker
            Hash Join  l1.l_suppkey = supplier.s_suppkey      rows=253,728 per worker
              Parallel Seq Scan lineitem l1  Filter l_receiptdate > l_commitdate
                                             rows=6,321,558 per worker  Removed=3,676,117
              Hash  <- nation('SAUDI ARABIA') x Bitmap Heap Scan supplier  rows=4,010
            Index Scan idx_fk_lineitem_orders l3   loops=1,522,366  Index Searches: 1522366
              Filter: l3.l_receiptdate > l3.l_commitdate AND l3.l_suppkey <> l1.l_suppkey
        Index Scan idx_fk_lineitem_orders l2       loops=135,716    Index Searches: 135716
Buffers: shared hit=8,777,072 read=280,774        Execution Time: 3287.006 ms
```

### 4-c. CUBRID controlled (`late`) — the `F_plan` anchor

The controlled variant (`q21-late.sql`) writes the same four-way join as a derived table, so the two
sublinks correlate to the derived spec instead of to `lineitem l1`. **Nothing else in the query
changes** — no hint, no index directive, no predicate added or removed — except a
`limit 2147483647` inside the derived table, whose only function is to stop CUBRID's view merging
from flattening the derived spec straight back into the native plan. That flattening is itself
recorded: `q21-plan-est-late.out` (the derived table *without* the limit) reproduces the native plan
node for node at the identical cost 123,427,506. The variant returns the **byte-identical 100-row
result** on the same engine, verified row by row against the native block sink
(`q21-late-result-cubrid.out` vs `sink/Q21-cubrid-headline-block1.out`).

```text
-- derived spec, materialised                                     cost 1134830
idx-join
  outer: hash-join  edge: term[1]                                 cost 1134827 card 239944
    outer: idx-join  nation('SAUDI ARABIA') -> iscan supplier fk_supplier_nation
    inner: sscan l1   sargs: term[5] (l_receiptdate > l_commitdate)   cost 832902
  inner: iscan orders pk_orders_o_orderkey  sargs: term[6] ('F')
-- outer query
temp(order by) / temp(group by)
  sscan t   sargs: term[0] AND term[1]   subqs: 0 1               cost 400919 card 4441
```

Traced actuals (`q21-trace-late.out`):

| Node | Measured |
|---|---|
| `sscan lineitem` inside the derived spec | readrows **59,986,052**, **parallel workers: 6** |
| hash join `PROBE` x 4,010 suppliers | rows **1,522,366** (= ground truth `late_lineitems_saudi`) |
| `iscan orders pk_orders_o_orderkey` | readkeys 1,522,310, lookup rows **734,497** |
| materialised `SCAN temp` | readrows **734,523** (= ground truth `late_lineitems_saudi_F`), **parallel workers: 2** |
| correlated `iscan l2` (`EXISTS`) | readkeys **734,523**, rows 892,490, lookup rows 707,593 |
| correlated `iscan l3` (`NOT EXISTS`) | readkeys **707,593**, rows 1,297,947, lookup rows 668,145 |
| `GROUPBY` | rows **4,009** |

The controlled trace also **calibrates the IMP-005 double count**: at this shallower depth the l2
`readkeys` equals the independent `COUNT(*)` (734,523) exactly, factor 1; at the native depth the
same counter reads exactly 2× the independent `COUNT(*)`. The halved native figures also close the
arithmetic internally — 17,654,362 − 16,663,790 = 990,572, the trace's own post-sublink row count.

### 4-d. The comparison that matters

| Quantity | CUBRID native | CUBRID **controlled** | PostgreSQL native |
|---|---|---|---|
| What an `EXISTS` becomes | a `sarg` of the `l1` scan | a `sarg` of the derived-spec scan | a `JOIN_SEMI` relation |
| What a `NOT EXISTS` becomes | a `sarg` of the `l1` scan | a `sarg` of the derived-spec scan | a `JOIN_ANTI` relation |
| Driving relation | `orders` (15,000,000 scanned) | `nation` → `supplier` (4,010) | `nation` → `supplier` (4,010) |
| Rows the sublinks are evaluated on | **18,321,400** | **734,523** | 1,522,366 (anti), then 135,716 (semi) |
| **correlated subquery evaluations** | **35,975,762** | **1,442,116** | **1,658,082** |
| `lineitem` index rows read by the sublinks | 109,308,064 | 2,190,437 | ~1.66 M probes × 1.91 rows |
| Rows entering the supplier restriction | 990,572 | (restricted first) | (restricted first) |
| Final rows / groups | 39,448 / 4,009 | 39,448 / 4,009 | 39,448 / 4,009 |
| Physical page reads (pool misses) per statement | 670,565 (10.23 GiB) | 1,018,456 (15.54 GiB) | 349,789 (2.24 GiB) |
| Device reads | **0** | **0** | **0** |
| median wall | 49.394998 s | 16.120000 s | 3.083188 s |

**CUBRID's own cost model prefers the controlled plan by ~80x and still cannot build it.** The
native plan is costed at **123,427,506**; the controlled shape's two parts cost **1,134,830**
(derived spec) + **400,960** (outer) = 1,535,790. This is a plan-**space** defect, not a
plan-**choice** defect — the same class as Q19's IMP-027, and the opposite of Q20, where PostgreSQL
had the better plan in its space and ranked it wrong.

**PostgreSQL's estimates on Q21 are also badly wrong, and it does not matter.** Its top-level
estimate is `rows=1` against 39,448 actual; `pg_stats.n_distinct(lineitem.l_orderkey)` is 405,706
against a true 15,000,000 (a 36.97x under-estimate, `q21-pgstats-probe.out`); the l3 index scan is
estimated at 49 rows per loop and delivers 0.91. The plan is still right, because the *shape* is in
the search space and the semi/anti joins can only be placed above a restriction the hash join
already performs. Q21 is therefore a clean demonstration that plan-space membership dominates
estimate quality.

## 5. Execution telemetry

### 5-a. Buffer state — neither engine is resident, and that is a property of the query

Q21 references `lineitem` (10,670.9 MiB heap, 682,937 CUBRID pages / 1,125,128 PostgreSQL blocks)
and `orders` (2,370.1 MiB, 151,689 / 261,264) against the contracted **8192 MB** pool on both sides.
A 13.0 GB working set cannot be resident in an 8 GB pool, so unlike Q20 there is no residency state
to reach and no hysteresis to escape. The section 12 requirement that applies is the one this report
satisfies: the **level** is proved steady per configuration by a convergence probe, and the
**physical-read deltas are recorded**.

| Configuration | pool misses / statement | bytes re-read / statement | device reads | source |
|---|---|---|---|---|
| CUBRID native | 670,565 pages × 16 KiB | **10.23 GiB** | 0 | `/proc` `syscr` 2,682,259 and `rchar` 43,923,336,064 over the 4-statement block |
| CUBRID controlled | 1,018,456 pages × 16 KiB | **15.54 GiB** | 0 | `/proc` `syscr` 4,073,824, `rchar` 66,734,839,044 |
| PostgreSQL native | 349,789 blocks × 8 KiB | **2.24 GiB** | 0 (`read_bytes` 49,152) | `/proc` `syscr` 1,399,157, `rchar` 9,629,542,106; `pg_statio` `heap_blks_read` delta 1,469,076 per block = 367,269/statement |

The one traced CUBRID statement independently reproduces its own figure: `syscr` delta **670,508**
and `rchar` delta **10,977,595,208** bytes = 16,383.6 bytes per read (`q21-trace-io-{pre,post}.txt`).
`read_bytes` is **0** everywhere, so every miss is served by the OS page cache — the cost is CPU and
memory bandwidth on the executor thread, not disk.

At **matched plan shape** CUBRID re-reads **6.94x** as many pages and **5.42x** as many bytes as
PostgreSQL for the same tuples, of which exactly 2x is the 16 KiB vs 8 KiB page size and the rest is
retention. That is the IMP-002/IMP-007 pair, quantified in section 9.

**The `cubrid statdump` gauges are again unusable on this server** and are excluded from every
calculation. Over a 200-second block they report delta **0** for every counter, including
`Num_data_page_fetches`, while the engine trace reports 1,016,255 page fetches for a *single*
statement. Same defect as Q14/Q16/Q18/Q19/Q20; the gauges are retained inside the headline JSONs for
audit and CUBRID buffer/IO evidence rests on `/proc` and the trace instead.

### 5-b. CPU decomposition, units and I/O

Measured over the section 12 4-statement block with a per-TID sampler at a 50 ms nominal period,
weighted by **actual timestamp deltas**:

| Configuration | executor CPU | auxiliary CPU | total query CPU | sum of statement walls | `U` | TWU | peak units | serial tail |
|---|---|---|---|---|---|---|---|---|
| CUBRID native | 1148.720 core-s | 2.520 core-s | 1151.240 core-s | 200.1330 s | 5.75237 | 5.7502 | 7.0134 | 0.063 s |
| CUBRID controlled | 188.960 core-s | 8.890 core-s | 197.850 core-s | 64.6920 s | 3.05834 | 3.0574 | 7.4088 | 0.051 s |
| PostgreSQL native | 72.710 core-s | 6.510 core-s | 79.220 core-s | 12.5217 s | 6.32660 | 6.3367 | 7.5883 | 0.235 s |

Executor / auxiliary classification is explicit, never inferred. CUBRID's executor bucket is
`parallel-query` (1145.83 core-s native, 166.34 controlled) plus `transaction` (2.86 / 22.60) threads
inside `cub_server`; its auxiliary bucket is `dwb-flush-block`, `pgbuf-page-flush` and
`vacuum-master`. PostgreSQL's executor bucket is `pg_backend` (12.00 core-s) plus
`pg_parallel_worker` (60.71 core-s); its auxiliary bucket is `pg_io_worker` (6.41 core-s) and
`pg_background` (0.10). `csql` / `psql` client CPU is auxiliary by construction and is never
attributed to the executor.

**The utilization story is the second half of Q21 and it is specific.** CUBRID's *native* plan is
the more parallel one: 5.75237 units, because the driving `sscan orders` runs at 6 workers and every
subquery evaluation happens inside those workers. The *controlled* plan is only 3.05834 units,
because the phase that evaluates its 1,442,116 correlated subqueries is the scan of a materialised
derived spec, and the trace shows that scan at **`(parallel workers: 2)`** while the `lineitem` heap
scan inside the same statement runs at **`(parallel workers: 6)`**. That is
`px_parallel.cpp:85-92`'s `case parallel_type::SUBQUERY ... auto_degree = 1` plus its gather thread —
IMP-009, and here it costs a whole card factor (`F_units = 2.068640x`). PostgreSQL runs the entire
equivalent region under one `Gather` with 5 launched workers and a participating leader.

An unusual consequence worth stating plainly: **CUBRID's bad plan burns 5.7635x the CPU of its good
plan but is only 3.0642x slower**, because the bad plan is 1.8809x more parallel. Parallelism is
partially hiding the plan defect, which is why the plan factor is measured on wall and the execution
factors on the controlled pair.

Device I/O over the telemetry windows is zero-read on every configuration (`sectors_read` 0–72 on
all devices, i.e. noise); the writes visible on `sda` / `sdb` / `dm-2` are CUBRID double-write-buffer
and PostgreSQL WAL/checkpoint traffic, not query reads.

## 6. Profile

Stage 14.8, non-headline. `perf record -F 999 -g --call-graph dwarf` attached to a verified PID set
(CUBRID: `cub_server` pid 2646189, all query worker threads inside it, 28 TIDs; PostgreSQL:
postmaster attached *before* the client connected so inherit-on-fork covers the leader and every
statement's workers, leader 2706222 with workers 2706223–2706227). Coverage: **289,785 / 109,802 /
171,655 samples, 0 lost, and 0 `[unknown]`-symbol lines** in any of the three flat reports.

| CUBRID native (top self-cost) | | CUBRID controlled `late` | | PostgreSQL native | |
|---|---|---|---|---|---|
| `pgbuf_fix_release` | 8.35% | `heap_attrinfo_read_dbvalues` | 10.29% | `tts_buffer_heap_getsomeattrs` | 23.77% |
| `__pthread_mutex_lock` | 8.12% | `rep_movs_alternative` `[k]` | 9.32% | `ExecScanHashBucket` | 6.56% |
| `pgbuf_unfix` | 4.70% | `fetch_val_list` | 3.55% | `ExecInterpExpr` | 5.26% |
| `__pthread_mutex_unlock_usercnt` | 4.15% | `pgbuf_fix_release` | 2.51% | `_bt_compare` | 4.73% |
| `btree_search_nonleaf_page` | 3.98% | `spage_get_record` | 2.50% | `next_uptodate_folio` `[k]` | 4.59% |
| `spage_get_record` | 2.63% | `pgbuf_get_victim_candidates_from_lru` | 2.43% | `LWLockAttemptLock` | 4.04% |
| `heap_attrinfo_read_dbvalues` | 2.54% | `qdata_generate_tuple_desc_for_valptr_list` | 2.37% | `hash_search_with_hash_value` | 3.05% |
| `btree_compare_key` | 2.32% | `parallel_scan::slot_iterator::next_qualified_slot_with_peek` | 2.34% | `ExecSeqScanWithQual` | 3.01% |
| `__pthread_mutex_trylock` | 2.25% | `__pthread_mutex_lock` | 2.16% | `heapgettup_pagemode` | 2.95% |
| `btree_search_leaf_page` | 1.80% | `heap_next_1page` | 2.14% | `PinBuffer` | 2.41% |
| **`scan_open_index_scan`** | **1.77%** | `qdata_copy_db_value_to_tuple_value` | 1.73% | `ExecHashJoin` | 2.40% |
| `eval_pred` | 1.65% | `pr_clear_value` | 1.60% | `heap_page_prune_opt` | 1.78% |

`perf stat` over the same windows:

| Configuration | cycles | instructions | IPC | Gcycles/statement | Ginstr/statement | cycles per subquery evaluation | instructions per evaluation |
|---|---|---|---|---|---|---|---|
| CUBRID native | 819,502,688,505 | 1,172,457,596,629 | **1.43** | 809.587 | 1158.271 | 22,504 | 32,196 |
| CUBRID controlled | 313,982,485,559 | 561,893,457,764 | **1.79** | 148.865 | 266.404 | 103,227 | 184,731 |
| PostgreSQL native | 474,347,700,488 | 720,118,092,466 | **1.52** | 48.750 | 74.009 | 29,402 | 44,635 |

Bands, converted to core-seconds per statement against each configuration's measured total query CPU
(`q21-bands.txt`, `q21-bands.json`):

| Band | CUBRID native | CUBRID controlled | PostgreSQL native |
|---|---|---|---|
| buffer fix/unfix + LRU surgery + buffer mutex | 29.30% = **83.2526** | 13.94% = **6.8725** | 15.02% = **2.9298** (lookup/pin/replacement) |
| B-tree descent and key compare | 13.23% = 37.5915 | 4.62% = 2.2777 | (inside `_bt_compare`, below) |
| per-row `DB_VALUE` materialisation | 12.01% = 34.1250 | 30.77% = **15.1697** | 31.90% = **6.2224** (tuple deform + heap access) |
| per-evaluation subquery open/execute/teardown | **11.13% = 31.6246** | 4.37% = 2.1544 | — (no counterpart; the probe is an `ExecProcNode`) |
| generic predicate/comparator dispatch | 4.84% = 13.7523 | 5.39% = **2.6573** | 16.14% = **3.1483** (expression + index compare) |
| kernel page-cache read path | 1.23% = 3.4949 | 11.24% = **5.5414** | 11.85% = **2.3115** |
| intermediate list-file materialisation | 1.10% = 3.1255 | 9.71% = **4.7871** | 1.57% = **0.3062** (executor node dispatch) |
| hash join build/probe | 0.14% = 0.3978 | 4.08% = **2.0115** | 11.19% = **2.1827** |
| **bands total** | 72.98% = 207.3643 | 84.12% = 41.4715 | 87.67% = 17.1010 |

Two readings, both honest:

- **Native versus controlled, same engine.** Every band except three grows with the plan defect:
  buffer handling **+76.38**, B-tree descent **+35.31**, subquery open/teardown **+29.47**, DB_VALUE
  materialisation **+18.96**, predicate dispatch **+11.10** core-s per statement. Those five are the
  234.84 core-s that IMP-028 removes; they are attributed to IMP-028 and are **not** charged to
  IMP-013 / IMP-020 / IMP-008 a second time. The three bands that *shrink* under the native plan
  (list-file −1.66, hash join −1.61, kernel read path −2.05) shrink because the controlled plan
  scans all of `lineitem` and materialises a derived spec, which the native plan does not.
- **Controlled versus PostgreSQL, matched shape.** DB_VALUE materialisation **2.44x**, buffer
  handling **2.35x**, page-cache read path **2.40x**, list-file materialisation **15.63x**; hash
  join is **0.92x** and predicate dispatch is **0.84x** — i.e. on this query CUBRID is *cheaper*
  than PostgreSQL in two of the six comparable bands. Section 9 records both directions.

The controlled-pair **cycles** ratio, `148.865 / 48.750 = 3.0536x`, is an independent reconstruction
of `F_cpu = 2.527436x` from a counter the card does not use, agreeing to **+20.8%**. That gap is
mostly accounted for by the two known `perf`/sampler discrepancies pulling in opposite directions
(+4.60% on CUBRID controlled, −7.44% on PostgreSQL, product 1.1301, i.e. 13.0 of the 20.8 points);
the residual 6.9% is the different statement coverage of the two windows (2.11 statements against
9.73). It is reported as a magnitude cross-check, not as a card input.

## 7. Source contrast

| Item | CUBRID `file:line` | PostgreSQL `file:line` | Difference | Class |
|---|---|---|---|---|
| What a correlated `EXISTS` becomes | `src/optimizer/rewriter/query_rewrite.c:246-251` — the *entire* treatment: `case PT_EXISTS: if (pt_is_query (node->info.expr.arg1)) { qo_add_limit_clause (parser, node->info.expr.arg1); } break;`. A `LIMIT 1` is pushed in; the sublink stays a predicate. The flattening path that does exist, `src/optimizer/rewriter/query_rewrite_subquery.c:73-75`, admits only `PT_EQ / PT_IS_IN / PT_EQ_SOME / PT_GT_SOME / PT_GE_SOME / PT_LT_SOME / PT_LE_SOME`, and `:123` additionally requires `correlation_level == 0`; its target is `mq_make_derived_spec()` (`src/parser/view_transform.c:10918`), a derived table, not a join. | `src/backend/optimizer/prep/prepjointree.c:936-964` calls `convert_EXISTS_sublink_to_join(root, sublink, false, available_rels)`; `:1056-1084` is the same call with `under_not = true` under a `NOT`. `src/backend/optimizer/plan/subselect.c:1593` implements it and `:1758` sets `result->jointype = under_not ? JOIN_ANTI : JOIN_SEMI;`. | CUBRID keeps a row predicate; PostgreSQL creates a join relation whose position the cost model chooses. | **structural absence** |
| Whether a semi/anti join exists at all | `src/query/query_list.h:37-45` — `typedef enum { NO_JOIN = -1, JOIN_INNER, JOIN_LEFT, JOIN_RIGHT, JOIN_OUTER, JOIN_CSELECT } JOIN_TYPE;`. Five members, none of them semi or anti. A case-insensitive search of the whole `src/` tree for `semi join` / `semijoin` / `anti join` / `antijoin` in any spelling returns **0 matches**. | `src/include/nodes/nodes.h:315-316` — `JOIN_SEMI, /* 1 copy of each LHS row that has match(es) */ JOIN_ANTI, /* 1 copy of each LHS row that has no match */`, with `:309-310` stating the design: *"The planner recognizes these cases and converts them to joins. So the planner and executor must support these codes."* | The conversion above has no target type to convert *into*. | **structural absence** |
| Where a single-relation predicate may be evaluated | `src/optimizer/query_graph.c:2535-2537` — `else if (n == 1) { QO_TERM_CLASS (term) = QO_TC_SARG; head_node = QO_ENV_NODE (env, bitset_iterate (&(QO_TERM_NODES (term)), &iter)); }`, where `n` is the cardinality of the term's node set (`:2508`). The classification looks at that number and **nothing else** — not the term's rank, not `QO_TERM_SUBQUERIES`, not any cost. `:6375-6392` shows the only later escape: a sarg becomes `QO_TC_AFTER_JOIN` solely when its node is the null-supplying side of an **outer** join. An inner join can never move it. | `src/backend/optimizer/plan/createplan.c:5293` `order_qual_clauses()` orders the remaining quals by cost — but on Q21 PostgreSQL never needs it, because the expensive terms are joins, not quals. | CUBRID's placement rule is cardinality-based and unconditional; the expensive term is pinned to `lineitem l1`'s scan wherever that scan lands in the join order. This is what makes the structural absence *unrecoverable* rather than merely suboptimal. | **structural absence** |
| Cost of an `EXISTS` term | `src/optimizer/query_planner.c:10005-10007` — `case PT_EXISTS: selectivity = DEFAULT_EXISTS_SELECTIVITY; /* make a guess */ break;`, the constant being `0.1` at `src/optimizer/query_planner.h:114`. Dumped as `term[4] ... (sel 0.1) (rank 9)` and `term[7] ... (sel 0.9) (rank 10)`. Rank comes from `src/optimizer/query_graph.c:3562` — `QO_TERM_RANK (term) = bitset_cardinality (&(QO_TERM_SUBQUERIES (term))) * RANK_QUERY` with `RANK_QUERY = 8` (`:77`) — and `src/optimizer/plan_generation.c:1615-1640` orders sargs by ascending selectivity then ascending rank, which is why the cheap date comparison is evaluated before the sublinks. | `src/backend/optimizer/path/costsize.c` costs a semi/anti join path per candidate join order, using real relation cardinalities on both sides. | CUBRID prices 36 million subquery executions as a 0.1 constant. This is **not** the root cause: a better estimate would change the plan's cost but not the *set* of plans, because the term is a sarg by construction. | same stage, lower measured cost |
| Executing the predicate, per row | `src/parser/xasl_generation.c:1685-1698` builds `pt_make_pred_term_comp (regu_var1, NULL, R_EXISTS, ...)`; `src/query/query_evaluator.c:1840-1885` is the `R_EXISTS` arm, which per row tries `sq_get()` and otherwise runs `EXECUTE_REGU_VARIABLE_XASL` (`src/query/xasl.h:539`) — a complete subquery XASL open, index-scan start, B-tree descent, heap lookups, comparator calls and teardown. Measured share: **11.13% = 31.62 core-s per statement** in that machinery alone (`scan_open_index_scan` 1.77%, `qexec_execute_mainblock` 1.33%, `scan_next_scan_local` 0.87%, `btree_prepare_bts` 0.58%, `scan_get_index_oidset` 0.57%, `qexec_intprt_fnc` 0.52%, `qexec_start_mainblock_iterations` 0.48%, `qexec_open_scan` 0.33%, `qexec_execute_scan` 0.31%, allocator 2.08%, MVCC snapshot 0.79%). | `src/backend/executor/nodeNestloop.c:210-222` — `if (ExecQual(joinqual, econtext)) { node->nl_MatchedOuter = true; if (node->js.jointype == JOIN_ANTI) { node->nl_NeedNewOuter = true; continue; } ... if (node->js.single_match) node->nl_NeedNewOuter = true; }`, with `:169-172` emitting the anti-join's unmatched row. The inner index scan is opened **once** and rescanned per outer tuple; there is no per-row XASL open or teardown. | 6.80 µs of marginal CPU per CUBRID evaluation against 3.17 µs per PostgreSQL probe, and CUBRID performs 21.70x as many. | same stage, lower measured cost |
| The mitigation CUBRID does have | `src/query/subquery_cache.c:337-395` (`sq_put`) / `:407-434` (`sq_get`) plus `src/parser/xasl_generation.c:28947+` (`pt_prepare_corr_subquery_hash_result_cache`). The cache keys on the correlated values (`sq_make_key`) and self-disables once it passes 60% of `max_subquery_cache_size` with a hit ratio below `SQ_CACHE_MIN_HIT_RATIO` (`src/query/subquery_cache.h:40`, = 9 → 90%); the parameter defaults to 2 MB (`src/base/system_parameter.c:4995-5001`, max 16 MB). Measured on Q21: **hit 2, miss 110,772, status disabled** — a 0.0018% hit rate on a key that is near-unique per row. | No counterpart is needed: the join conversion removes the per-row execution rather than memoising it. | The mitigation is behaving **correctly** and cannot help: no cache size makes a per-row-distinct key hit. Recorded so the finding is not mistaken for a tuning gap. | structural absence |
| Parallel degree of the phase that evaluates the sublinks | `src/query/parallel/px_parallel.cpp:85-92` — `case parallel_type::SUBQUERY: ... /* TODO: degree fixed at 1 (main + gather = 2) ... */ auto_degree = 1;`, and `:96-102` returns that degree whether the hint is absent or set, explicitly ignoring `parallelism`. Observed as `(parallel workers: 2)` on the derived-spec scan in `q21-trace-late.out` while the `lineitem` heap scan in the same statement runs at `(parallel workers: 6)`. | `src/backend/optimizer/plan/createplan.c` places the semi/anti joins **inside** the `Gather`, so all 5 launched workers plus the participating leader evaluate them; measured `U` 6.32660 with peak 7.5883. | 3.05834 against 6.32660 active units = the card's `F_units` 2.068640x. | same stage, lower measured cost |
| Per-page buffer handling on a hit | `src/storage/page_buffer.c` `pgbuf_fix_release` 8.35% + `pgbuf_unfix` 4.70% + `__pthread_mutex_lock` 8.12% + `__pthread_mutex_unlock_usercnt` 4.15% + `__pthread_mutex_trylock` 2.25% = **29.30% = 83.25 core-s** natively, **13.94% = 6.87 core-s** at matched plan. The unfix path takes the LRU list mutex and performs list surgery plus zone rebalancing. | `src/backend/storage/buffer/bufmgr.c` → `hash_search_with_hash_value` 3.05% + `PinBuffer` 2.41% + `LWLockAttemptLock` 4.04% + `StrategyGetBuffer` 1.23% + others = **15.02% = 2.93 core-s**: a hash probe and an atomic refcount, no list and no per-unfix mutex. | 2.35x more CPU at matched plan shape. | same stage, lower measured cost |
| Materialising a row's attributes | `src/storage/heap_file.c` `heap_attrinfo_read_dbvalues` 10.29% plus `spage_get_record` 2.50%, `or_mvcc_get_repid_and_flags` 1.24%, `or_header_size` 0.96%, `pr_type_from_id` 0.58%, `pr_clear_value` 1.60% — per row, re-read the MVCC/representation header, re-resolve each attribute's domain, build fully-typed `DB_VALUE`s, tear each one down. **30.77% = 15.17 core-s** at matched plan. | `src/backend/executor/execTuples.c` `tts_buffer_heap_getsomeattrs` 23.77% (with `slot_deform_heap_tuple` inlined) — deform into a flat `Datum`/`isnull` array using cached attribute offsets, no per-value type object, no teardown. **31.90% = 6.22 core-s**. | 2.44x, on the same 59,986,052 rows. | same stage, lower measured cost |
| Serving a buffer-pool miss | Every miss is a synchronous 16 KiB `pread()` on the query worker thread: 1,018,456 per statement at matched plan (`/proc` `syscr`), kernel band **11.24% = 5.54 core-s**. CUBRID's auxiliary bucket over the whole block is 2.52–8.89 core-s and contains **no I/O submitter at all**. | 349,789 reads per statement, kernel band 11.85% = 2.31 core-s — but **6.51 core-s of PostgreSQL's total query CPU sits in `pg_io_worker` processes**, i.e. submission is off the executor path entirely. | CUBRID pays 2.40x the kernel-path CPU on the critical path and has no equivalent of the io workers. | same stage, lower measured cost |
| Evaluating the surviving scan predicates | `src/query/query_evaluator.c` `eval_pred` / `eval_pred_comp0` / `eval_value_rel_cmp` + `tp_value_compare_with_error` + `mr_cmpval_date` = **5.39% = 2.66 core-s** at matched plan. | `src/backend/executor/execExprInterp.c` `ExecInterpExpr` 5.26% plus `_bt_compare` 4.73% and `_bt_binsrch` / `_bt_check_compare` = **16.14% = 3.15 core-s**. | **0.84x — CUBRID is cheaper here.** Q21's surviving quals are one date-vs-date column comparison and one integer inequality; PostgreSQL pays `_bt_compare` on 1.66 M index probes. | same stage, **lower measured cost on the CUBRID side** |

**Absence claims — searched paths, symbols and patterns.** For *"CUBRID never converts a correlated
`EXISTS` into a join, and has no join type to convert it into"*, the searched paths were
`src/optimizer/rewriter/query_rewrite.c`, `src/optimizer/rewriter/query_rewrite_subquery.c`,
`src/optimizer/query_graph.c`, `src/optimizer/query_planner.c`, `src/optimizer/plan_generation.c`,
`src/parser/view_transform.c`, `src/parser/xasl_generation.c`, `src/query/query_list.h`,
`src/query/query_evaluator.c` and `src/query/subquery_cache.c`; the searched symbols and patterns
were `semi join`, `semijoin`, `anti join`, `antijoin`, `JOIN_SEMI`, `JOIN_ANTI`, `PT_EXISTS`,
`qo_rewrite_subqueries`, `mq_make_derived_spec`, `QO_TC_SARG`, `QO_TC_JOIN`, `QO_TC_AFTER_JOIN`,
`correlation_level` and `DEFAULT_EXISTS_SELECTIVITY`. `PT_EXISTS` appears in the optimizer exactly
three times — `query_rewrite.c:246` (push a LIMIT), `query_graph.c:2153` and `:3181` (collect its
segments so the term can be classified), and `query_planner.c:10005` (the 0.1 selectivity guess) —
and in none of them does a join appear. The whole-tree case-insensitive search for any spelling of
semi/anti join returns 0 matches.

## 8. Causal decomposition details

**The 3.064206x plan factor is CUBRID's, and it is a plan-space defect.** `F_plan` is a same-engine,
same-regime, same-gate A/B: CUBRID runs 49.394998 s on the plan it must build and 16.120000 s on a
plan that returns byte-identical rows and that its own cost model rates ~80x cheaper
(1,535,790 against 123,427,506). The mechanism decomposes cleanly and every step is measured:

1. Both correlated sublinks reference only `lineitem l1`, so `qo_analyze_term()` makes them sargs of
   the `l1` scan (`query_graph.c:2535-2537`). Nothing downstream can move a sarg past an inner join.
2. The `l1` scan is the inner of the `orders`-driven index join, so the sublinks are evaluated on
   every late lineitem of every `'F'` order: **18,321,400** `EXISTS` evaluations, of which
   **17,654,362** survive to a `NOT EXISTS` evaluation — **35,975,762** subquery executions per
   statement, against **1,442,116** in the controlled plan (**24.947x**) and **1,658,082** semi/anti
   probes in PostgreSQL (**21.697x**).
3. The marginal cost of those extra executions is directly measurable:
   `(284.138545 − 49.300410) core-s / (35,975,762 − 1,442,116) evaluations` =
   **6.80 µs = 19,470 cycles each** at the measured 2.861 GHz. PostgreSQL's counterpart, read from
   `q21-plan-act-pg.out`, is `0.003 ms × 1,522,366` (anti) + `0.005 ms × 135,716` (semi) = 5.25
   core-s over 1,658,082 probes = **3.17 µs per probe**. CUBRID pays **2.15x per evaluation and
   performs 21.70x as many**.
4. 234.84 core-s — **82.6% of CUBRID's entire total query CPU** — is the work the conversion
   removes. It surfaces in the profile as +76.38 core-s of buffer fix/unfix, +35.31 of B-tree
   descent, +29.47 of subquery open/teardown, +18.96 of `DB_VALUE` materialisation and +11.10 of
   predicate dispatch.

**Why 5.7635x of CPU is only 3.0642x of wall.** The native plan sustains 5.75237 active units
against the controlled plan's 3.05834, so 1.8809x of the extra CPU is absorbed by parallelism
(`5.7635 / 1.8809 = 3.0642`, exact). This is the one place where CUBRID's parallel scan helps it,
and it helps by hiding a defect.

**The remaining 5.228355x, at matched evaluation order.** `F_units = 2.068640x` is IMP-009 acting as
a whole card factor: the phase that evaluates the controlled plan's 1.44 M correlated subqueries is
a derived-spec scan pinned to degree 1 + gather by `px_parallel.cpp:89-92`, measured at
`(parallel workers: 2)` in the same statement whose heap scan runs at 6. `F_cpu = 2.527436x`
decomposes as `F_work = 0.869750x` (CUBRID does **13.0% fewer** evaluations, because its controlled
shape applies `o_orderstatus = 'F'` before the sublinks and PostgreSQL applies it after) times
`F_cost = 2.905936x`, and the per-band attribution of that cost is section 6's controlled-pair
column: `DB_VALUE` materialisation 2.44x, buffer handling 2.35x, page-cache read path 2.40x,
list-file materialisation 15.63x, against hash join 0.92x and predicate dispatch 0.84x where CUBRID
is ahead.

**Explanations considered and REJECTED by measurement.**

- *"CUBRID loses because PostgreSQL parallelises and CUBRID does not."* Rejected for the native
  plan, accepted only in its precise form for the controlled one. CUBRID's **native** plan is the
  more parallel of the two (5.75237 units against PostgreSQL's 6.32660, and 1.8809x more parallel
  than its own better plan). Parallelism explains `F_units = 2.068640x` of a 16.020754x gap — 2.07x,
  not 16x — and only on the controlled pair, where the defect is specific and localized to
  `parallel_type::SUBQUERY`.
- *"CUBRID loses because it does more I/O."* Rejected as a *root* cause. Device reads are zero on
  every configuration. Pool-miss traffic is real and is charged where it belongs: at matched plan
  shape it is 2.40x of kernel-path CPU (5.54 against 2.31 core-s), inside `F_cost`, not a separate
  factor. Natively the kernel band is only 1.23% = 3.49 core-s, i.e. the 16x gap is *not* an I/O
  story at all — it is 82.6% CPU spent executing subqueries.
- *"The subquery result cache just needs to be bigger than its 2 MB default."* Rejected by direct
  measurement: `SUBQUERY_CACHE (hit: 2, miss: 110772, size: 15101184, status: disabled)`. The key is
  the correlated pair `(l_orderkey, l_suppkey)`, near-unique across 18.3 M evaluations, so the hit
  rate is 0.0018% and no cache size changes it. The self-disable at `subquery_cache.c:415-421` is
  correct behaviour, not the defect.
- *"`DEFAULT_EXISTS_SELECTIVITY = 0.1` is the root cause."* Rejected. A better estimate changes the
  plan's **cost** but not the **set** of plans, because a single-relation term is a sarg by
  construction (`query_graph.c:2535-2537`). CUBRID already rates the controlled shape ~80x cheaper
  and still cannot build it. The estimate would matter only *after* a semi/anti join exists, to rank
  the new orders.
- *"PostgreSQL wins because its estimates are better."* Rejected, and it is worth saying loudly:
  PostgreSQL's Q21 estimates are terrible — top-level `rows=1` against 39,448 actual, and
  `n_distinct(l_orderkey) = 405,706` against a true 15,000,000, a 36.97x under-estimate. It wins
  because the right *shape* is in its search space, not because it costs it well.
- *"The 24.95x work difference is a trace artifact."* Rejected by three independent instruments. The
  native trace's `readkeys` are exactly 2× an independent `COUNT(*)` (IMP-005's depth-3 double
  count, calibrated against the controlled trace where the same counter matches the same `COUNT(*)`
  exactly), the halved figures close the trace's own internal arithmetic
  (17,654,362 − 16,663,790 = 990,572, the reported post-sublink row count), and the `COUNT(*)` probe
  itself returns identical values on both engines.
- *"CUBRID's controlled variant is faster only because `LIMIT 2147483647` prunes something."*
  Rejected: 2,147,483,647 exceeds the derived spec's 734,523 rows by four orders of magnitude, the
  variant returns the byte-identical 100-row result with identical `numwait` values, and the trace
  shows the derived spec materialising all 734,523 rows.

**Error budget.** The card's inputs carry: median-of-3 statement timing with block-to-block spread
0.116–0.889%; sampler `U` cross-checked against `perf stat` at −0.42% (CUBRID native), +4.60%
(CUBRID controlled) and −7.44% (PostgreSQL, +0.85% on the executor-only comparison the attach
actually covers); `F_cpu` independently reconstructed from `perf` cycles at +20.8%, of which 13.0
points are the two `U` discrepancies compounding; `F_work` exact by direct count on three
instruments. The reconstruction residual is +0.0000% by construction. The qualitative conclusions —
that the plan factor is CUBRID's and worth 3.06x, that utilization is worth 2.07x, and that CUBRID
is 2.53x more CPU-expensive at matched shape — each survive every one of those bounds by more than
an order of magnitude.

## 9. Improvements

**Q21 allocates one new improvement ID, `IMP-028`. `next_id` moves to `IMP-029`.** The Git ledger
was synced and searched by root-cause title, CUBRID source location, PostgreSQL source location and
mechanism before allocating (`q21_allocation_note` in `reports/improvement-registry.json`). The
nearest existing entries are deliberately not reused: **IMP-025** is an *uncorrelated* `NOT IN`
whose RHS is materialised once and probed by an O(n) linear scan — Q21's subquery is never
materialised at all; **IMP-019** reorders sargs *within* one scan, whereas Q21's defect fixes *which
scan* the term is attached to; **IMP-011 / IMP-014** are cost-model defects that mis-rank plans the
search space contains, whereas here the good plan is absent from the search space.

### IMP-028 (new, P0, difficulty high, status `measured`)

> A correlated `EXISTS` / `NOT EXISTS` sublink is never turned into a semi-join or an anti-join —
> CUBRID has no such join type at all (`query_list.h:37-45`) — so it survives into planning as a
> `PT_EXISTS` predicate over **one** relation, which `qo_analyze_term()` classifies unconditionally
> as `QO_TC_SARG` on that relation's scan; the subquery is therefore opened, executed and torn down
> once per scanned row and can never be deferred past the join that would have reduced the driving
> relation 24.95x.

| Field | Value |
|---|---|
| Category | optimizer |
| Evidence event | evaluations of the two correlated `lineitem` subqueries per statement |
| Evidence type | direct A/B (same-engine controlled, 3 gated blocks per configuration, byte-identical result) + engine trace + `EXPLAIN (ANALYZE)` loops + independent `COUNT(*)` identical on both engines |
| Measured effect | **3.064206x** wall on Q21 (49.394998 s → 16.120000 s); 234.84 of 284.14 core-s = **82.6%** of CUBRID's total query CPU |
| Work | 35,975,762 → 1,442,116 evaluations (24.947x); PostgreSQL 1,658,082 (21.697x) |
| Marginal cost | 6.80 µs / 19,470 cycles per CUBRID evaluation against 3.17 µs per PostgreSQL probe |
| CUBRID mechanism | per candidate `l1` row: `eval_pred()` reaches the `R_EXISTS` arm, builds the correlated key, misses the (already disabled) subquery cache, and executes a complete subquery XASL — `scan_open_index_scan` on `fk_lineitem_orders`, a B-tree descent for `l_orderkey`, a heap lookup per matching entry to fetch `l_suppkey` (and the two dates for `l3`), the generic `DB_VALUE` comparator for `<>`, then teardown |
| PostgreSQL mechanism | `pull_up_sublinks` makes the sublinks a `JOIN_ANTI` (l3) and a `JOIN_SEMI` (l2); the cost model places both above the hash join that restricts `lineitem` to 4,010 Saudi suppliers, and each probe is an `ExecProcNode` on an already-open index scan with a `JOIN_ANTI` / `single_match` early exit |
| Implementation direction | (1) add `JOIN_SEMI` / `JOIN_ANTI` to `JOIN_TYPE` with nested-loop and hash-join executor support mirroring `nodeNestloop.c:210-222`; (2) add a `PT_EXISTS` arm to `qo_rewrite_subqueries()` that pulls the subquery's FROM item into the outer FROM as a semi/anti-joined node so `qo_analyze_term()` sees an `n == 2` `QO_TC_JOIN` term. **Cheaper intermediate step that captures the measured effect without a new join type:** let a sarg whose `QO_TERM_SUBQUERIES` bitset is non-empty be *deferrable*, and place it at the highest join level whose available segments still cover it — the controlled variant proves placement alone is worth 3.064206x |
| Correctness risk | High for the rewrite (outer-side duplicate multiplicity — Q21 *counts* rows; `NOT EXISTS` NULL semantics; subqueries carrying aggregates / HAVING / set operations; and the `LIMIT 1` that `query_rewrite.c:249` has *already* injected). Low for the deferral-only variant, which changes evaluation position and not row multiplicity, and whose correctness argument is the one that already justifies `QO_TC_AFTER_JOIN` |
| Validation criteria | byte-identical 100 rows and total `numwait` 39,448; trace `readkeys` on l2/l3 falling from 36,642,798 / 35,308,724 to at most 2×734,523 / 2×707,593; median WARM wall ≤ 16.12 s over three gated blocks; no regression on the uncorrelated-`IN` queries (Q02 / Q16 / Q18 / Q20); TPC-H Q04 and Q22, which also carry correlated `EXISTS` / `NOT EXISTS`, must not regress |
| Upstream precedent | **None found.** Searched paths and symbols are listed in section 7's absence claim. The only related upstream work in the pinned tree is the subquery result cache, which mitigates the per-row cost rather than removing it, and which measurably disables itself on this query |

### Existing entries that received Q21 relations and evidence

| Entry | What Q21 adds | Measured on Q21 |
|---|---|---|
| **IMP-009** — parallel degree of an uncorrelated subquery hardcoded to 1 | Its **largest measured cross-engine cost in the campaign**, and a clean one: an entire card factor | `F_units = U_P/U_Cc = 6.32660 / 3.05834 =` **2.068640x** of the 5.228355x controlled-pair gap. The derived-spec scan that evaluates 1,442,116 subqueries runs at `(parallel workers: 2)` while the `lineitem` heap scan in the same statement runs at 6 and `parallelism=6` is configured (`px_parallel.cpp:85-92`) |
| **IMP-020** — per-row scan output materialised into fully-typed `DB_VALUE`s | Matched plan, same 59,986,052 rows, largest band of the controlled configuration | 30.77% = **15.1697 core-s** against PostgreSQL's `tts_buffer_heap_getsomeattrs` band 31.90% = 6.2224 core-s → **2.44x** |
| **IMP-013** — every page unfix on a HIT path performs mutex-protected LRU list surgery | Matched plan, zero device reads on both sides; the mutex share is unusually explicit | 13.94% = **6.8725 core-s** against PostgreSQL's 15.02% = 2.9298 → **2.35x**. Natively the same band is 29.30% = 83.25 core-s, the largest band anywhere in Q21, but that inflation is IMP-028's and is attributed there |
| **IMP-007** — every buffer miss is a synchronous single-page `pread` on the query thread | The clearest cross-engine contrast this entry has had, because PostgreSQL's side is now a **separate process class** | CUBRID 1,018,456 synchronous 16 KiB `pread`s per statement, kernel band 11.24% = 5.5414 core-s **on the executor path**; PostgreSQL 349,789 reads, band 11.85% = 2.3115 core-s, plus **6.51 core-s in `pg_io_worker` processes** — the asynchronous submission this entry says CUBRID lacks. CUBRID's auxiliary bucket contains no I/O submitter at all |
| **IMP-002** — buffer replacement fails to retain a working set that exceeds the pool | A **bound**, not an extension: on Q21 residency is impossible for both engines by construction (13.0 GB set, 8192 MB pool), so neither policy can be blamed for missing | At matched plan CUBRID re-reads **1,018,456 pages = 15.54 GiB** per statement against PostgreSQL's **349,789 = 2.24 GiB** — 6.94x pages, 5.42x bytes, of which exactly 2x is the 16 KiB vs 8 KiB page. Device reads 0 on both. The 76-statement steady-state series wanders 4.3840% with no trend |
| **IMP-006** — every intermediate join result tuple is materialised into a list-file page | Largest per-band ratio on Q21, with an explicit scope caveat | 9.71% = **4.7871 core-s** against PostgreSQL's executor-node-dispatch band 1.57% = 0.3062 → **15.63x**. Caveat: the controlled variant materialises its derived spec by construction, so part of this is the price of the counterfactual; the **native** plan still pays 1.10% = 3.1255 core-s for the rewriter's own nested derived specs |
| **IMP-008** — scan-level sarg evaluation routes every row through the generic `DB_VALUE` comparator | A **constraint**, not a confirmation | At matched plan the band is 5.39% = **2.6573 core-s** against PostgreSQL's 16.14% = 3.1483 → **0.84x, i.e. CUBRID is cheaper here**. Q21 bounds IMP-008's cross-engine value at ~0 for a low-arity integer/date predicate mix |
| **IMP-005** — nested-chain trace stat merge double counts | First **calibration** of the multiplier against an independent instrument | Deep trace `readkeys` 36,642,798 against a true 18,321,400 = exactly 2.0000; the same counter one level shallower reads 734,523, matching its `COUNT(*)` exactly, factor 1. All Q21 work numbers are reported halved at depth 3 and unhalved at depth 2 |

**Ranking on Q21.** IMP-028 first: the only entry whose Q21 effect is a measured **wall** number from
a same-engine A/B (3.064206x), and the only one that is 82.6% of the query's CPU. IMP-009 second: an
independent card factor of 2.068640x. IMP-020 third (2.44x on the largest controlled band, 15.17
core-s), IMP-013 fourth (2.35x, 6.87 core-s), IMP-007 / IMP-002 fifth as a pair (5.42x the
page-cache read traffic at matched plan, with PostgreSQL's io workers as the direct contrast),
IMP-006 sixth (15.63x ratio but scope-caveated), and **IMP-008 last, because on Q21 it measures
0.84x in CUBRID's favour**. Nothing is double counted: the profile bands are charged at the
**controlled** plan, i.e. after IMP-028's effect has already been removed, and the native-plan
inflation of the same bands is attributed to IMP-028 alone.

**No PostgreSQL-side improvement is claimed.** PostgreSQL's badly wrong Q21 estimates
(`rows=1` against 39,448; `n_distinct(l_orderkey)` 36.97x under) are recorded in sections 4 and 8 as
a source contrast and a rejected explanation, not as a registry entry — this campaign's ledger
records CUBRID improvements.

## 10. Evidence index

Format: `claim → raw file → formula → evidence type → SHA-256 (first 16)`.

| Claim | Raw evidence | Formula | Type | SHA-256 |
|---|---|---|---|---|
| CUBRID median 49.394998 s | `raw/Q21/Q21-cubrid-headline-block1.json` `median_s` | median of `measured_times_s` | direct A/B | `df036aa08f53e2f7` |
| PostgreSQL median 3.083188 s | `raw/Q21/Q21-postgresql-headline-block1.json` `median_s` | median of `measured_times_s` | direct A/B | `6f28c3a4779cff24` |
| CUBRID controlled median 16.120000 s | `raw/Q21/Q21-cubrid-late-headline-block1.json` `median_s` | median of `measured_times_s` | direct A/B | `de97c9650bf0cad4` |
| `R_wall` 16.020754x, `F_plan` 3.064206x, `F_units` 2.068640x, `F_cpu` 2.527436x, `F_work` 0.869750x, `F_cost` 2.905936x, residual +0.0000% | `raw/Q21/q21-causal-card.json` / `.txt` | SSOT section 16 formulas | derived | `859163f4aef9ee93` |
| `U`, TWU, peak units, serial tail, executor/auxiliary split | `raw/Q21/Q21-cubrid-headline-telemetry.json`, `Q21-cubrid-late-headline-telemetry.json`, `Q21-postgresql-headline-telemetry.json` | `U = total_query_cpu_block / Σ statement walls` | per-TID sampler | `2a93323189da57e9`, `aaecfa07fa7497d2`, `55e73a34025c753e` |
| `W_C = 35,975,762` (18,321,400 + 17,654,362) | `raw/Q21/q21-trace-cubrid.out` `readkeys: 36642798` / `35308724`, ÷2 for IMP-005 | direct count | direct count | `d5c64f94aa5bf16c` |
| `W_Cc = 1,442,116` (734,523 + 707,593) | `raw/Q21/q21-trace-late.out` `readkeys: 734523` / `707593` | direct count | direct count | `2aebc1efdc629a65` |
| `W_P = 1,658,082` (1,522,366 + 135,716) | `raw/Q21/q21-plan-act-pg.out` `Index Searches: 1522366` / `135716` | direct count | direct count | `880c2f8dad75bd77` |
| Ground truth identical on both engines: 4,010 / 7,309,184 / 29,058,120 / 18,321,400 / 1,522,366 / 734,523 / 39,448 | `raw/Q21/q21-groundtruth-cubrid.out`, `q21-groundtruth-pg.out`, `q21-groundtruth.json` | independent `COUNT(*)` | direct count | `51fc7e7e20277c29`, `acc0e868503d27f1` |
| CUBRID native plan: both sublinks are sargs of the `l1` scan, cost 123,427,506 | `raw/Q21/q21-plan-est-cubrid.out` | `SET OPTIMIZATION LEVEL 514` | estimated plan | `5d3894eadcfcc6c9` |
| CUBRID controlled plan: derived spec 1,134,830 + outer 400,960 | `raw/Q21/q21-plan-est-late.out` (merged form) and the `SET OPTIMIZATION LEVEL 514` dump inside `q21-late-driver.log` | `SET OPTIMIZATION LEVEL 514` | estimated plan | `af2ad2a445e5673e` |
| PostgreSQL converts the sublinks to `Nested Loop Semi Join` / `Nested Loop Anti Join` | `raw/Q21/q21-plan-est-pg.out`, `q21-plan-act-pg.out` | `EXPLAIN (COSTS, VERBOSE, SETTINGS)` / `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, TIMING)` | actual plan | `ecfd3eb023e9b1c1`, `880c2f8dad75bd77` |
| Controlled variant returns byte-identical rows | `raw/Q21/q21-late-result-cubrid.out` vs `raw/Q21/sink/Q21-cubrid-headline-block1.out` | row-by-row comparison of both result blocks | direct comparison | `6ded56ad20eab713` |
| Subquery cache disabled at hit 2 / miss 110,772 | `raw/Q21/q21-trace-cubrid.out` `SUBQUERY_CACHE (...)` | engine counter | engine counter | `d5c64f94aa5bf16c` |
| Physical reads: CUBRID 670,565 / 1,018,456 pages, PostgreSQL 349,789 blocks, device reads 0 | the three telemetry JSONs (`io.engine_and_client` `syscr` / `rchar` / `read_bytes`), `q21-trace-io-{pre,post}.txt`, headline JSON `buffer_counters` | delta ÷ 4 statements | procfs + engine counter | as above |
| Profile bands and `perf stat` | `raw/Q21/profile-{cubrid,cubrid-late,pg}-flat.txt`, `profile-*-callgraph.txt`, `perf-stat-{cubrid,cubrid-late,pg}.txt`, `q21-bands.json` / `.txt` | share × measured total query CPU | profile attribution | `1f4cd5511cc68f1d`, `12e7d3a3d0bd3c9f`, `6cf9e3b707d0f4c0`, `3d37d0e68c8c6046`, `b225d33fb05a1ec4`, `71b2904ccd19c898`, `13dd2107bb5336c4` |
| PostgreSQL `n_distinct(l_orderkey) = 405,706` against a true 15,000,000 | `raw/Q21/q21-pgstats-probe.out` | `pg_stats` vs `count(distinct)` | direct count | `dd8f7201c9cbf7bc` |
| Correctness `result-equivalent-at-SF10`, 100 rows, ordered | `raw/Q21/q21-correctness.json`, `q21-correctness-{cubrid,postgresql}.out` | SSOT section 11 comparator | direct comparison | `919c292b05717ec9` |
| Preflight / postflight gates, `ssot_drift=NONE`, 0 off-cpuset, 8 FK / 8 `idx_fk_*` / 8 `convalidated` | `raw/Q21/q21-preflight.txt`, `q21-postflight.txt` | SSOT section 7/9/10 checks | catalog + procfs | `63c22b1e92ffb9e9`, `ecadde5d3aa01106` |
| WARM gate derivation and the measured null it sits on | `raw/Q21/q21-warm-gate-params.txt`, `q21-warm-gate-bootstrap.txt`, `q21-convprobe-{cubrid,postgresql}.json` | moving-block bootstrap, block length 6, 20,000 resamples | derived | `29cd93e1bf30cdd7`, `389eceda63a99dc7` |
| Controlled variant SQL | `raw/Q21/q21-late.sql` | — | SQL input | `e819d82ca53bd141` |

Per-artifact byte size, SHA-256, creation command, producing stage and validity are recorded for all
**222** promoted files in `reports/Q21/raw-manifest.json` (28,476,855 bytes).

## 11. Notion sync

**Out of scope for this worker session, by SSOT section 21's execution boundary.** The GJC/tmux
worker session runs on the remote build host and has no Notion connector; it must never attempt a
Notion write. Its Notion-adjacent duty ends at committing and pushing this report, the raw manifest
and the improvement-registry update to `origin/main`.

All Notion synchronisation for Q21 — operational-state update, the Q01–Q22 database row, the new
`IMP-028` registry page plus relations for IMP-002 / IMP-005 / IMP-006 / IMP-007 / IMP-008 /
IMP-009 / IMP-013 / IMP-020, and the section 21 content-richness requirements — is to be performed
by the dedicated reconciler subagent with Notion tool access, reading the pushed commit as source of
truth. An idempotent backfill record keyed on
`campaign_id + QNN + session_id + report_commit + content_fingerprint` is appended to
`reports/notion_backfill_pending.jsonl` in the same push, so the sync can be reconciled later
without re-deriving anything from this session.

## 12. Completion checklist

| Gate (SSOT section 26) | Status |
|---|---|
| Preflight and correctness status recorded | **PASS** — `q21-preflight.txt` / `q21-postflight.txt`, `ssot_drift=NONE` both times, 0 off-cpuset both times, 8 FK / 8 `idx_fk_*` / 8 `convalidated`; correctness `result-equivalent-at-SF10`, 100 rows, tolerance not reachable |
| Three valid headline values per completing engine | **PASS** — 3 accepted blocks × 3 measured statements per configuration (CUBRID native, PostgreSQL native, CUBRID controlled); all load-gate verdicts `CLEAN` under both the strict per-sample and the contract-window rule |
| Timeout confirmations | **N/A** — no timeout; slowest measured statement 50.41 s, slowest statement anywhere 65.40 s (traced), against 300 s |
| Plan, execution, profile, source contrast complete | **PASS** — sections 4, 5, 6, 7 |
| Causal card has evidence or explicit `UNMEASURED` | **PASS** — every factor numeric and measured; no `UNMEASURED` factor; residual +0.0000% with its limitation stated and an independent `perf`-cycles cross-check at +20.8% whose components are accounted for |
| Git improvement ledger deduplicated and committed | **PASS** — one new ID `IMP-028` after a documented search; `next_id` → `IMP-029`; Q21 relations and evidence added to IMP-002 / 005 / 006 / 007 / 008 / 009 / 013 / 020, two of them as explicit constraints; `q21_allocation_note` records the rejected candidates |
| Notion relations synced or idempotent backfill durable | **PASS (backfill)** — worker is barred from Notion writes by section 21; idempotent record appended to `reports/notion_backfill_pending.jsonl` |
| Every claim indexed to raw evidence and checksum | **PASS** — section 10 plus `raw-manifest.json` (222 artifacts) |
| Report, manifest, registry committed, pushed, reachable from `origin/main` | recorded in the raw manifest as `report_commit` |
| `QUERY_COMPLETE` emitted | see the status block below |
| Current session removed and absence verified | controller step after this push |

**Harness changes made during Q21: none.** `harness/measure_block.sh`, `headline_run.py`,
`warm_establish.py`, `headline_telemetry.py`, `telemetry_run.py`, `perf_run.sh`,
`preflight_check.sh` and `correctness_check.py` all ran unmodified, with the harness-default WARM
gate (`WINDOW=4`, `LEVEL_TOL=0.010`, `SPREAD=0.030`) and per-configuration statement counts supplied
through their existing environment overrides. Q21 is the first query of the campaign that needed no
gate relaxation at all.

**Retained non-headline and rejected evidence.** Nine rejected CUBRID warm-up runs are preserved
(`Q21-cubrid*-warm-attempt*.json` / `.log`) together with their load traces; they are uncounted
engine time, never headline values, and are the input to the bootstrap in
`q21-warm-gate-bootstrap.txt`. Two non-headline warm-ups did not converge and are declared rather
than hidden: the CUBRID controlled trace warm-up and the PostgreSQL `EXPLAIN` warm-up
(`q21-cubrid-late-trace-warm.log`, `q21-pg-explain-warm.log`, the latter at 3.053904 s against the
block level of 3.083188 s, 0.95% low). Neither feeds a headline or a card input — the artifacts they
precede are read for counts and plan shape, and every count they produce is independently confirmed
by the `COUNT(*)` ground-truth probe. The three `perf-*.data` files (4.6 GB) are excluded from
promotion; the derived flat/call-graph reports and `perf stat` counters that every profile number in
this report is read from are promoted and hashed.

```yaml
TPCH_SSPQ_STATUS:
  campaign_id: tpch-sspq-fk-r1-20260730
  query: Q21
  ssot_commit: 1b5fbc021353b16cf4b7375695fd6cad4ec4402d
  ssot_blob_sha: 510478846bff081d3223d3835069283a7cd2e47b
  session_id: gajae_code_msbgsf4l_4tombfrn
  stage: 14.13-completion-checklist
  state: complete
  report_commit: see raw-manifest.json
  artifact_fingerprint: see raw-manifest.json
  timestamp: 2026-08-02T20:05:00+09:00
  next_action: QUERY_COMPLETE
```
