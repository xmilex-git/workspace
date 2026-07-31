# TPCH-SSPQ FK campaign — Q08 report

## 3-a. Causal multiplier card

```text
R_wall 1.111086x [wall, median of 3 per engine; PostgreSQL is 1.1111x faster]
= F_plan  0.964885x [plan-shape; PostgreSQL-side controlled A/B, anchor named below]
× F_units 1.373763x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   0.838224x [total query CPU-seconds]

F_cpu 0.838224x is the CONTROLLED pair's CPU factor. On the native pair the same
quantity is 0.805422x, and it decomposes as

F_cpu(native) 0.805422x [total query CPU-seconds]
= F_work 0.151371x [plan-node tuple touches: 4,200,631 vs 27,750,587]
× F_cost 5.320850x [total-query CPU-seconds per tuple touch: 1034.2 ns vs 194.4 ns]
```

**Read the card in one line: CUBRID picks the better plan, touches 6.6x fewer tuples and
spends 16% less total CPU — and still loses by 11%, because it converts that CPU into
wall on 3.82 active units against PostgreSQL's 5.25.**

Q08 is the campaign's first query where **`F_plan` and `F_cpu` both favour CUBRID and the
entire loss sits in `F_units`**. Two of the three factors are below 1.0; only the
parallel-unit factor is above. That inverts Q07, where the plan choice was the whole
story.

`F_plan` is numeric by a **PostgreSQL-side controlled A/B**, direction stated explicitly:
*PostgreSQL native (`Parallel Hash Join` tree) → PostgreSQL controlled
(`enable_hashjoin=off, enable_mergejoin=off`, the index-nested-loop chain CUBRID chooses
natively)*. Forcing PostgreSQL onto CUBRID's shape makes PostgreSQL **1.0364x faster**
(0.986521 s vs 1.022423 s), so `F_plan = 0.964885x`: **CUBRID's plan shape is the better
of the two and contributes nothing to the gap.** The remaining controlled cross-engine
pair is (CUBRID native, PostgreSQL controlled index-NL) and carries `F_units` and
`F_cpu`; native and controlled denominators are never mixed.

That pair is matched **node-for-node on the dominant path**. Both drive
`part(p_type sarg) → lineitem(fk_lineitem_partsupp) → orders(PK) → customer(PK) →
nation n1 ⨝ region → supplier(PK) → nation n2`, and both produce the identical
intermediate cardinalities **13,452 / 403,487 / 122,404 / 122,404 → 24,254**,
independently confirmed by ground-truth `count(*)` queries that both engines answer
identically (`q8-groundtruth-cubrid.out`, `q8-groundtruth-pg.out`) and cross-checked
against `q8-plan-act-pg.out`'s `loops × rows`.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 0.964885x | plan-node shape | same-engine controlled A/B on PostgreSQL | `T_P_idxnl/T_P_native` = 0.986521/1.022423 | `Q08-postgresql-idxnl-headline.json`, `Q08-postgresql-headline-block1.json`, `variants/plan-nestloop_forced.out` | direct A/B |
| `F_units` | 1.373763x | active execution units | CPU-seconds / wall-second over the section 12 block | `U_P_idxnl/U_C_native` = 5.25338/3.82408 | `Q08-postgresql-idxnl-headline-telemetry.json`, `Q08-cubrid-headline-telemetry-run5.json` | profile attribution |
| `F_cpu` | 0.838224x | total query CPU-seconds | per query execution | `CPU_C_native/CPU_P_idxnl` = 4.3442/5.1826 | same telemetry JSONs | profile attribution |
| `F_work` | 0.151371x | plan-node tuple touches | tuples | `W_C/W_P` = 4,200,631/27,750,587 | `q8-groundtruth-*.out`, `q8-plan-act-pg.out`, `q8-trace-cubrid.out` | direct A/B |
| `F_cost` | 5.320850x | CPU-seconds per tuple touch | tuple touches | `(CPU_C/W_C)/(CPU_P/W_P)` = 1034.2 ns / 194.4 ns | `Q08-causal-card.json`, `q8-card-calc.txt` | profile attribution |

**Second anchor.** Anchoring on the CUBRID side (*CUBRID native index-NL → CUBRID
controlled `/*+ USE_HASH(orders, customer) */`, i.e. PostgreSQL's native shape on the
dominant path*) gives

```text
1.111086x = 0.661234x [plan] × 0.818389x [units] × 2.053208x [CPU-sec]
```

which also reconstructs exactly. PostgreSQL's shape costs CUBRID **1.5123x**
(1.718 s vs 1.136 s) at **2.5492x** the total query CPU — **even though CUBRID reaches
`U = 6.44602` on that shape against `U = 3.82408` natively.** CUBRID is therefore not
unable to fill its configured width; it fills it only when the plan is a hash tree that
scans `orders` and `customer` whole. The optimizer's choice is correct on both engines,
which is the exact converse of Q07's `IMP-011` and is recorded there as a positive
control.

**Reconstruction residual = 0.000000% on both anchors, and as in Q04–Q07 that is an
identity, not a prediction.** `CPU_stmt` is attributed as `U × t_median` with `U` measured
on the same block regime the wall is defined on, so `F_units × F_cpu = T_C/T_P` by
construction. Closure rests on the independent quantities:

- **`U` reproducibility.** CUBRID native 4.05007 / 3.7401 / 3.91672 / 3.82408 / 3.73438
  across five independently gated WARM-converged telemetry runs (**8.45%** max–min;
  a sixth run is excluded, see section 2); PostgreSQL native 5.2815 / 4.98971 / 5.27535
  (**5.85%**).
- **TWU**, from actual sample timestamp deltas over the busy window only: **3.8178**
  (CUBRID, **−0.16%** from `U`), **5.5367** (PostgreSQL, **+4.95%**, the discrepancy being
  the 0.232 s `Gather Merge` serial tail that TWU spans and `U` averages over),
  **5.2479** (PG index-NL, −0.10%), **6.3913** (CUBRID USE_HASH, −0.85%).
- **`perf stat` on verified PID sets**, a third instrument: **3.790 CPUs utilized** for
  CUBRID (**−0.89%** against `U` = 3.82408) and **5.514** for PostgreSQL's
  postmaster-inherited executor set (**+4.52%**; PostgreSQL's auxiliary CPU is 0.01 core-s,
  so executor and total-query `U` are the same number here, and the residual is the perf
  window's back-to-back statements against the block's inter-statement gaps).
- **Instructions and IPC**, a separate counter path: CUBRID **252.359 G instructions at
  IPC 1.20**, PostgreSQL **341.463 G at IPC 1.10** over their respective 20 s profile
  windows — CUBRID retires **0.7391x** the instructions at **1.0909x** the IPC, which is
  the quantitative form of "it probes 4.2 M tuples while PostgreSQL scans 27.8 M".
- **Context switches**, a fourth independent counter: CUBRID **207,274 in 20.002 s
  (2.734 K/s)** against PostgreSQL **7,880 (71/s)** — **38.5x the rate**, the signature of
  the synchronous per-page fix/unfix path in section 6.

### Error budget, stated before any factor is interpreted

This is the binding constraint on Q08 and it is larger than three of the five factors:

| Quantity | Blocks | min | max | spread |
|---|---|---|---|---|
| CUBRID block-median wall | 5 valid telemetry blocks | 1.037 s | 1.240 s | **19.58%** |
| PostgreSQL block-median wall | 3 telemetry + 1 contract block | 1.022423 s | 1.037084 s | **1.43%** |

The ratio band implied by those two spreads is **0.9999x .. 1.2128x**, and the contract
`R_wall = 1.1111x` sits inside it. Q08's honest verdict is therefore
**"near parity, CUBRID 1.11x slower with a CUBRID-side level band that reaches parity at
its fast end"**, not "CUBRID is 11% slower" as a point fact. Section 5 identifies the
mechanism behind the CUBRID band and shows it is not measurement noise: block CPU is a
linear function of buffer-pool re-read traffic at **r = +0.978**.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q08 (National Market Share) |
| Pinned `ssot_commit` | `10ee29b0270b1e86dc72b4de5db44792622b2254` |
| Pinned `ssot_blob_sha` | `510478846bff081d3223d3835069283a7cd2e47b` |
| SSOT drift | `NONE` — HEAD blob `510478846bff081d3223d3835069283a7cd2e47b` equals the pinned blob at pre-block and post-block gates |
| GJC session ID | `gajae_code_ms8qkc6c_v1bq25m2` |
| Engine block order | Q08 is even → **PostgreSQL block first, then CUBRID block** (SSOT §12) |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (includes PR #7441 merge `b334446d6`) |
| CUBRID executable | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server` |
| CUBRID binary SHA-256 | `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` (matches frozen build manifest) |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL executable | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres` |
| PostgreSQL binary SHA-256 | `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` (matches frozen build manifest) |
| CUBRID DB / port owner | `tpch_sf10_q1`, `cub_master` pid 1433697 on 1523, `cub_server` pid 1612732 — ownership `OK` |
| PGDATA / port owner | `/home/cubrid/pg/pgdata-tpch-sspq`, postmaster pid 1433696 on 5442 — ownership `OK` |
| Query provenance | `queries/q8-cubrid.sql` SHA-256 `c2c3580fd9c70e6021ea9d0814826cb01bfe377c224a9d2f2aaca5270a36652b`, **byte-identical** to `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q8.sql` |
| PostgreSQL dialect | **zero dialect changes** — `queries/q8-pg.sql` is byte-identical to the CUBRID file (`queries/diff/q8.diff` is 0 bytes, verified by `cmp`) |
| Schema baseline | 8 FK / 8 child B-tree gate PASS both engines; PostgreSQL `convalidated` 8/8; counts `8/8/8` |
| Statistics track | histogram-enabled controlled comparison — CUBRID `update_statistics_update_histogram=y`, `default_histogram_bucket_count=300`; PostgreSQL `default_statistics_target=100` |
| Parallel contract | configured node/gather-cap comparison — CUBRID `parallelism=6`, `max_parallel_workers=100`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`, `parallel_leader_participation=on`, `max_worker_processes=16` |
| Buffer contract | configured-equal buffer budget — CUBRID `data_buffer_size=8.0G` (524,288 pages), PostgreSQL `shared_buffers=1048576 × 8kB = 8192 MB` |
| Shared memory | PostgreSQL `dynamic_shared_memory_type=mmap` (config file line 969). **Q08 requires this record: `Parallel Hash Join` appears three times in PostgreSQL's natural plan.** Measured DSM cost is in section 5 |
| Other live settings | PostgreSQL `jit=off`, `statement_timeout=300000 ms`, `io_method=worker`, `io_combine_limit=16`, `effective_io_concurrency=16`, `debug_assertions=off` |
| CPU / NUMA | SUT+client CPUs `0-15` (node0), collectors `20-23`; all 34–35 engine TIDs inside the cpuset at pre-block and post-block gates (`off_cpuset=0`) |
| Row counts | region 5, nation 25, supplier 100,000, customer 1,500,000, part 2,000,000, partsupp 8,000,000, orders 15,000,000, lineitem 59,986,052 — identical both engines |
| Preflight external load | 0.358 core-s/s (threshold 6.0) → PASS |

## 2. Correctness

| Item | Value |
|---|---|
| Status | **`result-equivalent-at-SF10`** |
| Detail | 2 rows, `ordered=True` (Q08 has `ORDER BY o_year`, so the ordered sequence is compared exactly) |
| Censoring | none — neither engine approached the 300 s timeout (both ≈1.0–1.2 s) |
| Raw | `q8-correctness.json`, `q8-correctness-cubrid.out`, `q8-correctness-postgresql.out` |

Both engines return:

| `o_year` | `mkt_share` (CUBRID raw text) | `mkt_share` (PostgreSQL raw text) |
|---|---|---|
| 1995 | `0.03882014251433219621787549443333812689395` | `0.03882014251433219622` |
| 1996 | `0.03948968749183991638443237442778882976311` | `0.03948968749183991638` |

CUBRID carries 20 more fractional digits than PostgreSQL on the division result. This is
an **output-scale** difference only and is admitted by the SSOT §11 rule
`abs(a-b) ≤ 1e-12 × max(1, abs(a), abs(b))`: the largest relative difference is
`1.8e-21` on the 1995 row, nine orders of magnitude inside the tolerance. Raw decimal
text is preserved above; tolerance is not used to hide a different row set — the row
count, the row multiset and the `o_year` keys match exactly.

**One run was invalidated and is excluded from every calculation.** CUBRID
headline-regime telemetry `run2` recorded statement times `[1.269, 1.225, 1.161, 1.027]`
— monotone decreasing — and `warm_establish.py` exited 4 with
`monotone trailing window (still drifting)`. SSOT §12 requires WARM to be proved and
invalidates a run whose WARM gate failed, so the block was timed on a decay curve and is
excluded. It is retained as evidence with `Q08-cubrid-headline-telemetry-run2-INVALID.json`,
and three further runs (4, 5, 6) were measured so that five WARM-converged CUBRID
telemetry blocks exist.

## 3-b. Headline timings

Regime `single-query-repeat WARM`, metadata connection mode
`single-connection-four-statements` (1 uncounted warmup + 3 measured, one direct
connection, no reconnect or prepare between measured statements, full row consumption
into a campaign-owned sink, no terminal rendering).

| Field | Value |
|---|---|
| CUBRID statement times (s) | **1.147, 1.136, 1.048** (uncounted warmup 1.134) |
| CUBRID median (s) | **1.136** |
| CUBRID mean / within-block sd (s) | 1.110333 / 0.054262 (4.89%) |
| PostgreSQL statement times (s) | **1.044851, 1.019921, 1.022423** (uncounted warmup 1.085094) |
| PostgreSQL median (s) | **1.022423** |
| PostgreSQL mean / within-block sd (s) | 1.029065 / 0.013728 (1.33%) |
| **Median wall ratio** | **1.111086x** (PostgreSQL faster) |
| Correctness / censoring | `result-equivalent-at-SF10` / not censored |
| Blocks accepted | both engines on **attempt 1** |
| Load gate | CUBRID `CLEAN` (external mean 0.318, max 0.9453, max-1s 0.5504); PostgreSQL `CLEAN` (0.2681 / 0.7658 / 0.3844) — threshold 6.0 core-s/s |
| WARM proof | CUBRID converged, half-split trend −0.9615% over 40 statements, trailing spread 1.3204%, steady 1.136 s; PostgreSQL converged, +0.3106% over 40, spread 1.1021%, steady 1.018576 s |
| Sink | CUBRID 1192 B `ea9a293f1b188548…`; PostgreSQL 358 B `ee983d08570e7583…` |
| Physical reads | **CUBRID `read_bytes` delta 0; PostgreSQL `heap_blks_read` delta 0** over the whole block — WARM is proved at the device level on both sides |

No confidence interval is claimed from three values. The three-value spread is reported
above and the much larger **cross-block** spread is reported in the section 3-a error
budget, because on Q08 the cross-block term dominates the within-block term on the CUBRID
side (19.58% vs 4.89%).

### WARM convergence parameters and how they were chosen

Both engines were probed with an independent 40-statement convergence series before any
headline block, under the same load gate (`q8-convergence-pg.json`,
`q8-convergence-cubrid.json`):

| Engine | first index the gate would pass | half-split trend | trailing spread | steady level | parameters used for the block |
|---|---|---|---|---|---|
| PostgreSQL | 12 | −0.1096% | 0.7770% | 1.029916 s | `n=40`, `LEVEL_TOL=1.0%`, `SPREAD=3.0%` |
| CUBRID | 19 | +0.9955% | 2.1429% | 1.120 s | `n=40`, `LEVEL_TOL=3.0%`, `SPREAD=5.0%` |

The asymmetric tolerance is the one SSOT §12's harness documents from Q05's measured
null distribution (CUBRID half-split null p95 2.16% at n=40, PostgreSQL 0.73%); Q08's own
probes reproduce that asymmetry (2.14% vs 0.78% trailing spread), so the parameters are
justified by this query's own data and not inherited blindly.

### Controlled-plan variants (non-headline anchors)

| Configuration | statement times (s) | median (s) | `U` | total query CPU (core-s) | load gate |
|---|---|---|---|---|---|
| PostgreSQL controlled index-NL (`enable_hashjoin=off, enable_mergejoin=off`) | 1.00737, 0.986521, 0.98075 | **0.986521** | 5.25338 | 5.1826 | `CLEAN` 0.723 |
| CUBRID controlled `/*+ USE_HASH(orders, customer) */` | 1.763, 1.712, 1.718 | **1.718** | 6.44602 | 11.0743 | `CLEAN` 1.314 |

## 4. Plan

### CUBRID native (`q8-plan-est-cubrid.out`, `SET OPTIMIZATION LEVEL 514`, non-executing)

```text
temp(group by)  sort: 1 asc   cost 288795 card 10338
  hash-join  edge term[1]  (supplier.s_nationkey = n2.n_nationkey)
    hash-join  edge term[0]  (n1.n_regionkey = region.r_regionkey)      [region sarg r_name='AMERICA']
      hash-join  edge term[2]  (customer.c_nationkey = n1.n_nationkey)
        idx-join → iscan customer  pk_customer_c_custkey   term[4]
          idx-join → iscan orders  pk_orders_o_orderkey    term[6], sargs term[9] (o_orderdate range)
            idx-join → iscan lineitem  fk_lineitem_partsupp term[5]
              sscan part  sargs term[7] (p_type='ECONOMY ANODIZED STEEL')  cost 29353 card 13248
    idx-join → iscan supplier  pk_supplier_s_suppkey  term[3]
```

Estimated cardinalities: part 13,248 → lineitem-join 397,336 → orders-join 51,728 →
customer-join 51,728 → n1 51,690 → region 10,338. Against ground truth
(13,452 / 403,487 / 122,404 / 122,404 / 122,404 / 24,254) the optimizer is accurate on
the first two levels (−1.5%, −1.5%) and underestimates from the `orders` level down by
**2.37x** (51,728 vs 122,404), because `term[9]`'s `o_orderdate` range selectivity
(0.305194) is applied to a stream whose `o_orderkey` distribution correlates with
`o_orderdate` in TPC-H. The final estimate 10,338 vs 24,254 is 2.35x low. **This
misestimate does not change the chosen shape** — the A/B in section 3-a shows the chosen
shape is the faster one on both engines — so it is recorded as an accuracy observation,
not as a defect with a measured cost on Q08.

**CUBRID parallelises this plan.** `q8-trace-cubrid.out`:

```text
SCAN (table: dba.part), (heap time: 1094, fetch: 8, ioread: 2, readrows: 0, rows: 0)
     (parallel workers: 5, heap time: 1018..1094, readrows: 399448..401913,
      rows: 399448..401913, gather: mergeable list)
```

Five worker threads split part's 2,000,000 heap rows evenly (399,448..401,913 each) and
each worker runs the whole inner index-nested-loop chain. The three uncorrelated
`nation`/`region` subqueries each report `parallel workers: 2`. So Q08 is **not** a
repeat of Q07's fully serial chain: the driving spec here is a 24,353-page heap scan, not
a 1-page `nation` scan, so `scan_check_parallel_scan_possible()` permits it.

### PostgreSQL native (`q8-plan-act-pg.out`, `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, TIMING)`)

```text
Finalize GroupAggregate                        actual 1007.509..1142.088  rows=2    loops=1
  Gather Merge   Workers Planned 5  Launched 5  actual 1006.581..1142.069  rows=12   loops=1
    Partial GroupAggregate                     actual  999.698..1000.959  rows=2    loops=6
      Sort  quicksort 452kB                    actual  998.797..999.250   rows=4042 loops=6
        Hash Join (supplier.s_nationkey = n2.n_nationkey)              rows=4042 loops=6
          Parallel Hash Join (lineitem.l_suppkey = supplier.s_suppkey) rows=4042 loops=6
            Parallel Hash Join (lineitem.l_orderkey = orders.o_orderkey) rows=4042 loops=6
              Nested Loop                      actual    0.179..307.002   rows=67248 loops=6
                Parallel Index Scan part_pkey  actual    0.132..77.355    rows=2242 loops=6
                  Filter: p_type = 'ECONOMY ANODIZED STEEL'
                Index Scan idx_fk_lineitem_partsupp on lineitem  rows=29.99 loops=13452
              Parallel Hash  Buckets 1048576 Batches 1 Memory 43904kB   rows=151727 loops=6
                Parallel Hash Join (orders.o_custkey = customer.c_custkey) rows=151727 loops=6
                  Parallel Seq Scan on orders  Filter: o_orderdate range  rows=759586 loops=6
                  Parallel Hash  Buckets 524288 Batches 1 Memory 15904kB rows=49906 loops=6
                    Hash Join (customer.c_nationkey = n1.n_nationkey)    rows=49906 loops=6
                      Parallel Seq Scan on customer                      rows=250000 loops=6
                      Hash ← Hash Join (n1.n_regionkey = region.r_regionkey) rows=5 loops=6
            Parallel Hash  Buckets 131072 Batches 1 Memory 5056kB       rows=16667 loops=6
              Parallel Seq Scan on supplier                              rows=16667 loops=6
          Hash  Buckets 1024 Batches 1 Memory 10kB ← Seq Scan on nation n2  rows=25 loops=6
Buffers: shared hit=796312   (read=0)
Planning Time: 3.915 ms   Execution Time: 1142.331 ms
```

`Batches: 1` on every hash node — nothing spilled, so no batch files and no temp I/O.
`shared hit=796312 / read=0` proves WARM at the buffer level. Estimated vs actual:
`rows=4427` estimated against 24,254 actual at the top join, i.e. PostgreSQL is **5.48x
low** where CUBRID is 2.35x low; both underestimate the same `o_orderdate`/`o_orderkey`
correlation, and neither misestimate changes the shape either engine picks.

`Execution Time: 1142.331 ms` is 11.7% above the uninstrumented headline median
(1.022423 s) — the `TIMING`/`BUFFERS` instrumentation overhead. **No `EXPLAIN` number is
used as a headline value or in the causal card**; the plan run is a separate non-headline
run per SSOT §14.6.

### Shape comparison and what the A/B proves

| Level | CUBRID native | PostgreSQL native | PostgreSQL controlled (anchor) |
|---|---|---|---|
| `part` access | `sscan` heap, 5 parallel workers, `p_type` sarg | `Parallel Index Scan part_pkey` + filter, 5 workers + leader | same as native |
| `part → lineitem` | `idx-join` on `fk_lineitem_partsupp` | `Nested Loop` + `Index Scan idx_fk_lineitem_partsupp` | same |
| `→ orders` | `idx-join` on `pk_orders_o_orderkey`, date sarg pushed to the probe | `Parallel Hash Join` against a 910,360-row hash of `orders ⨝ customer ⨝ n1 ⨝ region` | `Index Scan orders_pkey` |
| `→ customer` | `idx-join` on `pk_customer_c_custkey` | inside the same hash build | `Index Scan customer_pkey` |
| `n1 ⨝ region` | two `hash-join`s | `Hash Join` inside the build side | `Materialize` + `Nested Loop` |
| `→ supplier` | `idx-join` on `pk_supplier_s_suppkey` | `Parallel Hash Join`, 100,000-row build | `Index Scan supplier_pkey` |
| `→ n2` | `hash-join`, 25-row build | `Hash Join`, 25-row build | `Materialize` + `Nested Loop` |
| aggregate | `temp(group by)` hash+sort | `Sort` → `Partial GroupAggregate` → `Gather Merge` → `Finalize` | same as native |

The controlled PostgreSQL plan is a node-for-node reproduction of CUBRID's chain, which
is what makes anchor A's remaining pair legitimate. The two residual differences are
named rather than hidden: PostgreSQL reaches `part` through `part_pkey` where CUBRID uses
a heap scan, and PostgreSQL materialises the two 25-row `nation` relations for a nested
loop where CUBRID hash-joins them. Both are on relations that contribute <0.1% of either
engine's measured cost (section 6), and the CUBRID-side anchor B, which has the mirrored
residual differences, returns the same `R_wall` to 6 decimal places.

CUBRID's own cost model rates its chosen plan at **288,795** and the
`USE_HASH(orders, customer)` variant at **3,112,001** — 10.8x more expensive. The
measured ratio is 1.5123x in the same direction. The model's *ordering* is right and its
*magnitude* is 7.1x pessimistic, which is the `HJ_MEM_ALLOC_CONSTANT` / per-row spill
penalty behaviour `IMP-011` documents; on Q08 that pessimism costs nothing because the
ordering it produces is correct.

## 5. Execution telemetry

Per-TID sampling, sampler pinned to CPUs 20-23, TWU weighted by **actual sample
timestamp deltas**. All values below are non-headline diagnostics.

| Quantity | CUBRID native | PostgreSQL native | PG controlled idx-NL | CUBRID controlled hash |
|---|---|---|---|---|
| `executor_cpu` (core-s / block) | 18.44 | 22.12 | 21.35 | 43.39 |
| `auxiliary_query_cpu` (core-s / block) | 0.08 | 0.01 | 0.01 | 1.21 |
| `total_query_cpu` (core-s / block) | **18.52** | **22.13** | 21.36 | 44.60 |
| `unattributed_background` | none observed; load gate `CLEAN` on every block | | | |
| `U` = CPU/Σstatement walls | 3.82408 | 5.27535 | 5.25338 | 6.44602 |
| TWU (actual dt weighting) | 3.8178 | 5.5367 | 5.2479 | 6.3913 |
| max simultaneous active units | **5.2166** | **6.2449** | 6.1742 | 11.1882 |
| serial tail | 0.337 s | 0.232 s | 0.239 s | 0.228 s |
| planned workers | 5 (`compute_parallel_degree` SCAN branch) | 5 (`Workers Planned`) | 5 | up to 6 per hash node |
| launched workers | 5 (`parallel workers: 5` in trace) | **5 launched + leader participating (`loops=6`)** | 5 + leader | — |

CPU classification: CUBRID `executor` = `parallel-query` (17.15–18.44) + `transaction`
(0.81–0.97) threads; `auxiliary` = `pgbuf-page-flush`, `dwb-flush-block`, `dwb-file-sync`,
`log-checkpoint`, `vacuum-master`, `deadlock-detect`. PostgreSQL `executor` = leader
backend (3.79) + parallel workers (18.33); `auxiliary` = postmaster (0.01). No PostgreSQL
io-worker CPU appeared in any Q08 block, consistent with `read=0`.

**The unit deficit is the whole loss, and it is 5 against 6.** CUBRID's peak is 5.2166
units and PostgreSQL's 6.2449 — a ratio of 1.1971x, which covers **87%** of the measured
`F_units = 1.373763x`; the remaining 1.148x is the longer CUBRID serial tail (0.337 s vs
0.232 s) plus worker imbalance (`heap time: 1018..1094` ms across the five CUBRID
workers, a 7.5% straggler spread). Section 7 gives the two source lines that produce
"5, coordinator idle" instead of "5 + leader".

### CUBRID block-level pool churn: the mechanism behind the 19.58% wall band

`q8-poolchurn-regression.txt`, five WARM-converged, load-gated CUBRID blocks
(`run2` excluded):

| run | block median (s) | `U` | total query CPU (core-s) | read syscalls | `rchar` (MiB) | device `read_bytes` (MiB) |
|---|---|---|---|---|---|---|
| 3 | 1.0370 | 3.7401 | 17.47 | 56,922 | 883.0 | 37.8 |
| 4 | 1.0520 | 3.9167 | 17.59 | 77,984 | 1212.2 | 7.7 |
| 1 | 1.1130 | 4.0501 | 18.12 | 171,435 | 2672.3 | 0.0 |
| 6 | 1.2400 | 3.7344 | 18.53 | 198,080 | 3088.6 | 0.0 |
| 5 | 1.1990 | 3.8241 | 18.52 | 239,073 | 3729.1 | 0.0 |

```text
Pearson r(rchar_MiB, CPU_core_s)      = +0.9779
Pearson r(CPU_core_s, block_median_s) = +0.9717
Pearson r(rchar_MiB, block_median_s)  = +0.9057
Pearson r(rchar_MiB, U)               = +0.0449
OLS  CPU_core_s = 17.1185 + 0.000400 * rchar_MiB   ->  0.4099 core-s per GiB re-read
OLS  median_s   = 0.9752 + 0.000066 * rchar_MiB   ->  0.0676 s per GiB re-read
```

Read the chain: **pool re-read traffic → block CPU → block wall**, with `U` uninvolved
(r = +0.04). CUBRID's total CPU per block moves only 6.07% while its wall moves 19.58%,
because the CPU increase and the `U` decrease compound. `read_bytes` is 0 on three of the
five blocks and <38 MiB on the other two, so **this is not storage I/O**: it is CUBRID
buffer-pool misses re-served by the OS page cache, at 16,344 bytes per `pread` (exactly
one 16 KiB CUBRID page).

The instability is reproducible at statement granularity. `q8-iobisect.txt` runs the
identical warm statement in six configurations and gets **166 to 71,654 read syscalls
(0.3 MiB to 1116 MiB)** for the same query on the same server with the same 8 GiB pool —
the count is a function of what the previous statement left resident, not of the
statement. This is why the OLS intercept matters: extrapolated to zero churn CUBRID
projects to **0.9752 s**, which is **faster than PostgreSQL's measured 1.022423 s**. That
is a projection over n=5 with r=0.906, explicitly not a measurement, and it is registered
as such.

Why the working set sits exactly at the pool boundary: CUBRID's chain performs 403,487
random heap lookups into `lineitem` (682,937 pages × 16 KiB) and 403,487 into `orders`
(151,689 pages). Under uniform-key random access the expected distinct pages touched are
`682,937 × (1 − e^(−403,487/682,937)) = 304,600` and effectively all 151,689 `orders`
pages, i.e. `304,600 × 16 KiB + 151,689 × 16 KiB + part 380 MiB + customer 329 MiB
≈ 7.85 GiB` against a 8.00 GiB pool — a 98% fill. PostgreSQL runs the same 403,487
lineitem lookups over **8 KiB** pages, so its random-access footprint is
`339,000 × 8 KiB = 2.65 GiB`, and its whole plan touches 796,312 buffers = 6.2 GiB with
`read=0`. The page-size difference is a structural property of the two stored formats,
which SSOT §9 explicitly excludes from the "configured-equal buffer budget" claim
("not a claim of equivalent internal cache architecture, eviction policy, or page
format"); the arithmetic above is an analytic estimate, labelled as such, and the
measured quantities that stand on their own are the `read_bytes`/`rchar`/`syscr` deltas.

### `/proc` I/O, device and NUMA

| Quantity (per statement, warm block) | CUBRID | PostgreSQL |
|---|---|---|
| read syscalls | 14,231 – 60,829 (block-dependent, above) | **1,704** |
| `rchar` | 220 – 994 MiB | **1.7 MiB** |
| `read_bytes` (device) | **0** (3 of 5 blocks) | **1 KiB** |
| write syscalls | 1,037 | 39,398 |
| `wchar` / `write_bytes` | 6.7 MiB / 2.6 MiB | **322.7 MiB / 322.7 MiB** |
| device read | 0 MiB on every volume | 0 MiB on every volume |
| device write | 0.8 MiB (`sda`), 0.15 MiB (`sdb`) | 0.5 MiB (`sda`), 0.34 MiB (`sdb`) |

PostgreSQL's 322.7 MiB per statement of **`write_bytes` that never reaches a device**
(`cancelled_write_bytes` 755 MiB) is the `dynamic_shared_memory_type=mmap` contract from
SSOT §9: each statement creates DSM segments for three `Parallel Hash` nodes
(43,904 + 15,904 + 5,056 kB = 64.9 MiB of hash tables), the pages are dirtied in a
file-backed mapping under `pg_dynshmem/`, and the segment is destroyed at statement end
before writeback. It costs syscalls and page-cache pages but no I/O. This is recorded
because §9 requires it wherever a `Parallel Hash Join` is in the natural plan; it is
**not** charged as a defect on either side, and the profile in section 6 shows the
associated kernel cost is not in the DSM path.

NUMA: `cub_server` 8,696 MiB private on node0 against 53 MiB on node1 (99.4% node-local);
postmaster 155.6 MiB node0 / 0.5 MiB node1. Unchanged pre- to post-block. No cross-node
drift on either engine.

### CUBRID trace statistics are internally inconsistent by a per-level multiplier

`q8-trace-cubrid.out` against ground truth:

| Trace node | trace counter | ground truth | ratio |
|---|---|---|---|
| `lineitem` `fk_lineitem_partsupp` `readkeys` | 67,236 | 13,452 index descents | **×5.00** (= worker count) |
| `orders` `pk_orders_o_orderkey` `readkeys` | 806,974 | 403,487 probes | **×2.00** |
| `orders` lookup `rows` | 244,808 | 122,404 | **×2.00** |
| `customer` `pk_customer_c_custkey` `readkeys` | 367,194 | 122,404 probes | **×3.00** |
| top-level `SCAN` / `GROUPBY` `rows` | 24,254 | 24,254 | ×1.00 |

The multiplier equals 1 at the top, the worker count at the driving level, and the
scan_ptr depth at the intermediate levels. Every one of these is an exact integer
multiple, which is what makes it a merge-accounting defect rather than a measurement
disagreement — and it is why **no CUBRID trace counter is used as a work numerator in
section 3-a**; the `F_work` numerator is built from ground-truth cardinalities that both
engines confirm. This is Q08's contribution to `IMP-005`.

`cubrid statdump`'s global perfmon counters (`Num_data_page_fetches`,
`Num_data_page_ioreads`, `Num_data_page_dirties`) returned **delta 0** across a verified
4-statement block, and also across a trivial serial `count(*)` — frozen at
43,155,954 / 5,035,592 / 6,574,460. This reproduces the Q03/Q04/Q06 finding unchanged;
all Q08 I/O evidence comes from `/proc/<pid>/io`.

## 6. Profile

Non-headline. `perf stat` and `perf record -F 999 -g --call-graph dwarf` on verified PID
sets, collectors pinned to CPUs 20-23. CUBRID attaches to `cub_server` pid 1612732 (all
31 query worker threads live inside it). PostgreSQL attaches `perf stat` to the
postmaster **before** the client connects, so inherit-on-fork counts the leader and every
statement's parallel workers and nothing else.

| `perf stat` | CUBRID | PostgreSQL |
|---|---|---|
| cycles | 210,114,068,342 | 310,667,251,750 |
| instructions | 252,359,301,607 | 341,462,591,941 |
| IPC | **1.20** | **1.10** |
| task-clock | 75,810.35 ms | 110,289.79 ms |
| CPUs utilized | **3.790** | **5.514** |
| frequency | 2.772 GHz | 2.817 GHz |
| context switches | **207,274 (2.734 K/s)** | **7,880 (71/s)** |
| window | 20.002045 s | 20.001722 s |

Sample coverage: CUBRID 75,004 samples, 1,218 flat lines, **0 `[unknown]`**; PostgreSQL
111,037 samples, 2,134 flat lines, **0 `[unknown]`**; 0 lost samples on both. No all-CPU
profile was used.

| Shared object | CUBRID share | PostgreSQL share |
|---|---|---|
| engine userspace | `libcubrid.so.11.5` **83.16%** | `postgres` **69.33%** |
| kernel | 7.47% | **30.17%** |
| `libpthread` | **5.32%** | 0.00% |
| `libc` | 3.85% | 0.29% |
| `[xfs]` | 0.03% | 0.19% |

### CUBRID top self cost (`profile-cubrid-flat-nog.txt`)

| % | symbol | band |
|---|---|---|
| 17.76 | `pgbuf_fix_release` | page-buffer fix |
| 8.18 | `spage_get_record` | slotted-page record access |
| 7.58 | `btree_search_leaf_page` | B-tree descent |
| **5.41** | **`pgbuf_lru_boost_bcb`** | **page-buffer LRU list surgery on unfix** |
| 4.24 | `pgbuf_unfix` | page-buffer unfix |
| 3.66 | `rep_movs_alternative` `[k]` | `pread` copy-to-user |
| 3.40 | `btree_search_nonleaf_page` | B-tree descent |
| 3.37 | `__memmove_evex_unaligned_erms` | record copy |
| 3.06 | `heap_attrinfo_read_dbvalues` | tuple deform |
| 2.02 | `btree_compare_key` | B-tree descent |
| 1.99 / 1.85 / 1.32 | `__pthread_mutex_lock` / `_trylock` / `_unlock_usercnt` | mutex |

Banded: **page-buffer fix/unfix/LRU 27.41%** (`pgbuf_fix_release` + `pgbuf_lru_boost_bcb`
+ `pgbuf_unfix`), B-tree descent 14.44%, record/tuple access 15.75%, memcpy 7.03%,
mutex 5.16%, comparison/eval 2.63%.

Call graph (`perf report -S pgbuf_lru_boost_bcb`):

```text
5.38%  parallel-query  libcubrid.so.11.5
  parallel_scan::task<MERGEABLE_LIST, HEAP>::drain_slot_oids
   qexec_execute_scan → scan_next_scan → heap_get_visible_version
     → heap_clean_get_context → pgbuf_unfix → pgbuf_unfix
        → pgbuf_lru_boost_bcb → pgbuf_lru_adjust_zones
             → pgbuf_lru_adjust_zone1 → pgbuf_bcb_change_zone
```

**Every heap-row visibility fetch in the index-nested-loop chain pays LRU list surgery on
unfix.** That is the per-touch cost behind `F_cost = 5.320850x`.

### PostgreSQL top self cost (`profile-pg-flat-nog.txt`)

| % | symbol | band |
|---|---|---|
| 19.26 | `tts_buffer_heap_getsomeattrs` | tuple deform |
| 9.90 | `ExecParallelScanHashBucket` | parallel hash probe |
| **8.75** | **`next_uptodate_folio` `[k]`** | **minor page fault installing a shared-buffer PTE** |
| 6.18 | `ExecInterpExpr` | expression eval |
| 3.24 | `heap_page_prune_opt` | opportunistic pruning |
| 3.21 | `hash_search_with_hash_value` | hash lookup |
| 2.91 | `ExecParallelHashTableInsert` | parallel hash build |
| 2.70 / 2.62 / 2.25 / 1.71 / 1.32 / 0.72 / 0.55 | `_compound_head`, `filemap_map_pages`, `folio_remove_rmap_ptes`, `folios_put_refs`, `zap_present_ptes`, `folio_add_file_rmap_ptes`, `set_pte_range` `[k]` | page-fault / rmap |
| 2.01 / 1.98 / 1.93 | `heapgettup_pagemode`, `heap_hot_search_buffer`, `ExecSeqScanWithQual` | heap scan |
| 1.91 / 1.23 / 0.56 | `PinBuffer`, `LWLockAttemptLock`, `LockBufferInternal` | buffer pin/lock |

Banded: tuple deform + expression 25.44%, parallel hash 18.18%,
**kernel page-fault/rmap 20.62%**, heap scan 7.25%, buffer pin/lock **3.70%**.

The 20.62% kernel band is **not** the DSM mapping. Its call graph is unambiguous:

```text
8.75%  next_uptodate_folio  [k]
  |--5.70%-- ParallelWorkerMain → ParallelQueryMain → ExecAgg → ExecSort
  |          → ExecHashJoin → ExecParallelHashJoin → ExecNestLoop → IndexNext
  |          → index_fetch_heap → heapam_index_fetch_tuple → heap_page_prune_opt
  |          → PageGetPruneXid → asm_exc_page_fault → ... → filemap_map_pages
   --2.85%-- heapgettup_pagemode → heap_prepare_pagescan → heap_page_prune_opt
             → PageGetPruneXid → asm_exc_page_fault → ... → filemap_map_pages
```

Every one of PostgreSQL's 5 parallel workers is **forked fresh for each statement**, so
the first touch of every shared-buffer page in that worker's address space takes a minor
fault to install the PTE (`shared_buffers` is `MAP_SHARED|MAP_ANONYMOUS`, which Linux
backs with tmpfs, hence `filemap_map_pages`), and the matching rmap teardown is paid when
the worker exits. At 796,312 buffer touches per statement spread over 6 processes that is
~130k PTE installs per worker per statement. **CUBRID's workers are threads in one
process sharing one page table and pay none of this** — its total kernel share is 7.47%,
of which the page-cache read path (`rep_movs_alternative` 3.66% + `filemap_get_read_batch`
0.51% + `filemap_read` 0.27%) is the pool-churn cost from section 5, not faults.

**So the two engines pay for the same thing in opposite places**: CUBRID pays 27.41% in
its own userspace buffer bookkeeping plus 5.32% in `libpthread`; PostgreSQL pays 3.70% in
userspace pin/lock plus 20.62% in the kernel's page tables. That symmetry is why
`F_cpu` lands at only 0.838x despite `F_work` being 0.151x.

## 7. Source contrast

| Item | CUBRID `file:line` | PostgreSQL `file:line` | Difference | Class |
|---|---|---|---|---|
| Parallel degree of the driving heap scan | `src/query/parallel/px_parallel.cpp:36` `compute_parallel_degree()`; SCAN branch `:145-171` computes `auto_degree = (63 − __builtin_clzll(num_pages / scan_page_threshold)) + 2` then `degree = MIN(auto_degree, parallelism)`. `part` = 24,353 pages, `parallel_scan_page_threshold` default **2048** (`src/base/system_parameter.c:5135-5146`, `PRM_HIDDEN`) → `x = 11`, `floor(log2 11) = 3`, `auto_degree = 5`, `MIN(5, 6) = 5`. The configured `parallelism=6` is never reached | `src/backend/optimizer/path/allpaths.c:4973` `compute_parallel_worker()` — log₃ ladder on `min_parallel_table_scan_size`/`min_parallel_index_scan_size`, capped at the call site by `max_parallel_workers_per_gather`; on the same relation it returns the full cap of 5 | Both derive a degree from a page-count logarithm, but CUBRID's is a log₂ of a 2048-page unit that saturates *below* the configured cap on a 24,353-page relation, so the cap is decorative here | same stage, lower measured cost |
| Coordinator/leader participation | `src/query/parallel/px_scan/px_scan.cpp:1794-1812` `manager::start_tasks()` pushes exactly `m_parallelism` tasks to the worker pool; the calling transaction thread then only calls `m_result_handler->read()` at `:1873` to consume the merged list. It never executes a scan task, so **active units = degree** | `src/backend/executor/nodeGatherMerge.c:253-254` `if (parallel_leader_participation \|\| node->nreaders == 0)` and `:403-404` "Slot 0 is always for the leader. Leader always calls `ExecProcNode()`"; `src/backend/executor/nodeGather.c:214-215` the same for plain `Gather`; costed at `src/backend/optimizer/path/costsize.c:6641` `get_parallel_divisor()`, which adds `1.0 − 0.3 × nworkers` of leader contribution | CUBRID's coordinator is a pure consumer; PostgreSQL's leader is a producer *and* consumer. Measured peak units **5.2166 vs 6.2449**, `loops=6` vs `parallel workers: 5` | **structural absence** |
| Replacement bookkeeping per page unfix | `src/storage/page_buffer.c:10073` `pgbuf_lru_boost_bcb()` — on unfix of any BCB in LRU zone 2 or 3 it takes `pthread_mutex_lock(&lru_list->mutex)` (`:10113`), calls `pgbuf_remove_from_lru_list()`, `pgbuf_lru_add_bcb_to_top()`, then `pgbuf_lru_adjust_zone1()` (`:9834`) or `pgbuf_lru_adjust_zones()` (`:9937`), which call `pgbuf_bcb_change_zone()` (`:15819`). Reached from `src/storage/heap_file.c:25026` `heap_get_visible_version()` → `pgbuf_unfix` (`:3024`) on every heap row | `src/backend/storage/buffer/bufmgr.c:3479` `UnpinBuffer()` / `:3488` `UnpinBufferNoOwner()` — decrement a **process-local** `PrivateRefCountEntry`, and only at zero do one `pg_atomic_fetch_sub_u64(&buf->state, BUF_REFCOUNT_ONE)`. `:3295` `PinBuffer()` bumps `usagecount` **inside the same CAS** on `buf->state`. The clock-sweep replacement algorithm keeps no list, so there is no list to reorder and no per-list mutex | CUBRID's LRU-list policy requires mutex-protected doubly-linked-list surgery plus zone rebalancing per unfix; PostgreSQL's clock sweep requires one atomic counter bump. Measured **5.41% + 5.32% libpthread vs 1.91% + 1.23%** | **structural absence** |
| Buffer fix path cost | `src/storage/page_buffer.c:2211` `pgbuf_fix_release()` — 17.76% of CUBRID's profiled self cost, the single largest symbol | `src/backend/storage/buffer/bufmgr.c:1223` `PinBufferForBlock()` / `:1276` `ReadBuffer_common()` — does not appear above the 0.25% cut; `PinBuffer` is 1.91% | Same stage (locate-and-pin a resident page), 9.3x the measured share | same stage, lower measured cost |
| Per-statement worker lifecycle | threads from a persistent pool (`cubthread::worker_pool_impl::core_impl::worker_impl::run` in every CUBRID call graph); one process, one page table, no PTE work | `src/backend/executor/nodeGather.c:182` / `nodeGatherMerge.c:223` `LaunchParallelWorkers()` forks 5 backends per statement; each first-touch of a `shared_buffers` page faults through `filemap_map_pages` → `next_uptodate_folio`, and the rmap is torn down at exit | Opposite direction: CUBRID's thread model avoids **20.62%** of kernel page-fault/rmap cost that PostgreSQL pays | same stage, lower measured cost (**CUBRID favourable**) |
| Buffer-pool retention at a working set near the pool size | `src/storage/page_buffer.c:2211` miss branch → `pgbuf_claim_bcb_for_fix()` → `src/storage/file_io.c:3935` `fileio_read()`, one 16 KiB page per synchronous `pread` on the query thread. 14,231–60,829 such calls per statement, unstable across identical warm repeats | `src/backend/storage/aio/read_stream.c:1030` `read_stream_next_buffer()` + `src/backend/storage/buffer/freelist.c:442` `BAS_BULKREAD`; measured 1,704 read syscalls/statement and `shared hit=796312 read=0` | CUBRID re-reads 220–994 MiB/statement from the OS page cache at an 8 GiB budget where PostgreSQL re-reads 1.7 MiB | same stage, lower measured cost |
| NUMERIC aggregate accumulation | `src/query/numeric_opfunc.c:2477` `float_numeric_db_value_add()`, `src/query/query_opfunc.c:2059` `qdata_add_numeric_to_dbval()` | `src/backend/utils/adt/numeric.c` `do_numeric_accum` path | Q01's `IMP-001` band. On Q08 the aggregate sees only **24,254** rows, and no NUMERIC symbol reaches the 0.25% cut on either engine | common to both engines (**not material on Q08**) |

**Claim of absence, searched explicitly.** For "CUBRID has no leader-participation
equivalent": searched `src/query/parallel/` for `leader`, `participat`, `main_thread_scan`,
`self_execute`, and read `px_scan.cpp` `start_tasks()`/`next()`, `px_worker_manager.cpp`
`try_reserve_workers()`/`push_task()`, and `px_parallel.cpp` in full. `start_tasks()`
(`px_scan.cpp:1794`) is the only task-submission site for a parallel scan and it submits
`m_parallelism` tasks with no branch that executes one on the calling thread; the calling
thread's only scan-related work in `manager::next()` is `m_result_handler->read()`. For
"CUBRID's cost model has no per-unfix-free replacement policy": searched
`src/storage/page_buffer.c` for `clock`, `sweep`, `usage_count`, `usagecount` — no
clock-sweep implementation exists; the file implements private/shared LRU lists with
zones 1/2/3.

## 8. Causal decomposition details

### The chain, in the order the numbers force

1. **Shape is not the problem, and that is measured, not assumed.** `F_plan = 0.964885x`.
   PostgreSQL forced onto CUBRID's index-NL chain runs **1.0364x faster** than its own
   parallel-hash choice (0.986521 s vs 1.022423 s, `Q08-postgresql-idxnl-headline.json`).
   Conversely CUBRID forced onto PostgreSQL's shape is **1.5123x slower** (1.718 s vs
   1.136 s) at **2.5492x** the CPU. Both engines' optimizers pick the better available
   shape on this query.
2. **Work strongly favours CUBRID.** `F_work = 0.151371x`: 4,200,631 plan-node tuple
   touches against 27,750,587. CUBRID never reads `orders` or `customer` whole; it makes
   403,487 `orders` PK probes and 122,404 `customer` PK probes. PostgreSQL scans all
   15,000,000 `orders` rows and all 1,500,000 `customer` rows to build a 910,360-row hash
   table. Every cardinality in both columns is confirmed by ground-truth `count(*)` that
   both engines answer identically.
3. **Per-touch cost strongly favours PostgreSQL.** `F_cost = 5.320850x`: 1034.2 ns vs
   194.4 ns of total query CPU per touch. PostgreSQL's touches are sequential-scan tuples
   whose page is already pinned (`heapgettup_pagemode` 2.01%, deform 19.26%); CUBRID's are
   random index descents each ending in a `pgbuf_fix_release`/`pgbuf_unfix` pair with LRU
   list surgery (27.41% band) under a per-list mutex (5.32% `libpthread`).
4. **Net CPU still favours CUBRID.** `F_cpu = 0.838224x` (controlled) / `0.805422x`
   (native): 4.3442 core-s against 5.3936. Steps 2 and 3 nearly cancel; CUBRID wins the
   CPU account by 16–19%.
5. **The loss is entirely `F_units = 1.373763x`.** CUBRID reaches 3.82408 core-s of CPU
   per wall-second where PostgreSQL reaches 5.27535. 87% of that is the raw unit count —
   5.2166 peak vs 6.2449 — traced in section 7 to two lines: the `auto_degree` formula
   saturating at 5 below the configured cap of 6 (`px_parallel.cpp:171`), and
   `start_tasks()` submitting `m_parallelism` tasks with no participating coordinator
   (`px_scan.cpp:1794-1812`) against PostgreSQL's always-participating leader
   (`nodeGatherMerge.c:403-404`). The remaining 1.148x is the longer serial tail (0.337 s
   vs 0.232 s) and a 7.5% straggler spread across CUBRID's five workers
   (`heap time: 1018..1094` ms).

### Explanations considered and rejected, with the number that rejected them

- **"CUBRID chose the wrong plan, as on Q07."** Rejected by the PostgreSQL-side A/B:
  PostgreSQL is **1.0364x faster** on CUBRID's shape, so `F_plan = 0.964885x < 1`. Also
  rejected by the CUBRID-side A/B: PostgreSQL's shape costs CUBRID **1.5123x** at
  **2.5492x** the CPU. `IMP-011` therefore does **not** apply to Q08, and Q08 is recorded
  there as a positive control for the cost model's ordering.
- **"CUBRID cannot parallelise a nested-loop chain (Q07's `px_scan_checker` block)."**
  Rejected by the trace: `parallel workers: 5, readrows: 399448..401913` on the driving
  `part` scan, and by `U = 3.82408` / peak 5.2166. Q07's blocker bit because its driving
  spec was a 1-page `nation` scan; Q08's is 24,353 pages, so the outermost spec
  parallelises. The Q08 defect is the *degree* and the *non-participating coordinator*,
  not a total block.
- **"CUBRID's parallel width is capped by `parallelism=6` and it is simply using it."**
  Rejected by arithmetic on the source: `auto_degree = floor(log2(24353/2048)) + 2 = 5`,
  so `MIN(5, 6) = 5` — the cap is never reached, and the CUBRID `USE_HASH` variant proves
  the executor can reach `U = 6.44602` and peak 11.1882 units on the same server, i.e.
  the width is available and this plan does not ask for it.
- **"CUBRID is slower because it is CPU-hungrier."** Rejected by `F_cpu = 0.838224x`:
  CUBRID uses **16% less** total query CPU and retires **0.7391x** the instructions.
- **"The 19.58% CUBRID wall band is measurement noise, so the ratio is not real."**
  Rejected by `r(rchar, CPU) = +0.9779` and `r(CPU, wall) = +0.9717` over five gated
  blocks: the band is a reproducible function of pool re-read traffic, with `U` uninvolved
  (`r = +0.045`). It is a real engine behaviour, which is why the ratio is reported with a
  band rather than discarded.
- **"PostgreSQL's 30.17% kernel share is a campaign artifact of
  `dynamic_shared_memory_type=mmap`."** Rejected by the call graph: the dominant kernel
  symbol `next_uptodate_folio` (8.75%) arrives via
  `heap_page_prune_opt → PageGetPruneXid → asm_exc_page_fault → filemap_map_pages`, i.e.
  first-touch PTE installs on `shared_buffers` inside freshly forked workers — an
  engine property of the process-per-worker model, not the DSM mapping. The DSM cost is
  visible instead as 322.7 MiB/statement of `write_bytes` with 0 device writes, which is
  syscall and page-cache cost, not the profiled kernel band.
- **"CUBRID's aggregate NUMERIC path (`IMP-001`) contributes."** Rejected by
  cardinality: the aggregate consumes 24,254 rows on both engines, and no NUMERIC symbol
  reaches the 0.25% profile cut on either side.
- **"The `orders`-level cardinality misestimate (2.37x low) costs CUBRID time."**
  Rejected by the A/B: the shape the misestimate produced is the faster shape on both
  engines, so the misestimate has no measured wall cost on Q08. Recorded as an accuracy
  observation in section 4.

### What would change the verdict, quantified

Amdahl on the measured split (CUBRID `total_query_cpu` 4.3442 core-s per statement, of
which the `transaction`-thread serial part is ≈0.20 core-s, leaving 4.14 core-s parallel,
plus 0.108 s of measured overhead/imbalance):

```text
at 5 units (measured):  4.14/5 + 0.20 + 0.108 = 1.136 s   <- matches the headline exactly
at 6 units (projected): 4.14/6 + 0.20 + 0.108 = 0.998 s   -> R_wall 0.976x, CUBRID ahead
```

Adding the pool-churn intercept from section 5 (0.9752 s at zero churn) the two levers
are independent and both land CUBRID at or below PostgreSQL's 1.022423 s. Both figures
are **projections** with their formula shown, not measurements, and they are registered
as such with the improvement candidates.

## 9. Improvements

Registry synced before allocation; searched by title, CUBRID source location, PostgreSQL
source location and root cause. Two new root causes allocated (`IMP-012`, `IMP-013`),
four existing candidates gain Q08 relations, and one existing candidate is explicitly
**not** related.

### Ranking against the measured bands

1. **`IMP-012`** (coordinator does not participate + `auto_degree` saturates below the
   configured cap) — **the only factor above 1.0 in the card.** Owns `F_units = 1.373763x`,
   of which the raw unit count 6/5 = 1.1971x is 87%. P0.
2. **`IMP-013`** (per-unfix LRU list surgery under a per-list mutex) — owns the largest
   single profile band on either engine (27.41% fix/unfix/LRU + 5.32% mutex) and is the
   `F_cost = 5.320850x` driver. It does not by itself cause the loss (`F_cpu` still
   favours CUBRID by 16%), but it is the lever that converts CUBRID's 6.6x work advantage
   into a win instead of a 16% CPU margin. P1.
3. **`IMP-002` / `IMP-007`** (Q08 relations) — the pool-churn band, worth up to 0.1608 s
   of CUBRID's 1.136 s by OLS intercept, but on a projection with n=5. P1/P1, unchanged.
4. **`IMP-005`** (Q08 relation) — no wall cost; it damages the *instrument*, which on Q08
   forced the `F_work` numerator onto ground-truth queries. P2, unchanged.

### `IMP-012` — the parallel coordinator is a pure consumer, and the scan auto-degree saturates below the configured cap, so a parallelisable plan runs at 5 units where PostgreSQL runs the same shape at 6

- **Mechanism, CUBRID side.** For a parallel heap scan CUBRID calls
  `compute_parallel_degree(SCAN, num_pages, hint)`
  (`src/query/parallel/px_parallel.cpp:36`). The SCAN branch (`:145-171`) computes
  `auto_degree = floor(log2(num_pages / parallel_scan_page_threshold)) + 2` and then
  `degree = MIN(auto_degree, parallelism)`. With `part` at 24,353 pages and
  `parallel_scan_page_threshold = 2048` (`src/base/system_parameter.c:5135-5146`, a
  `PRM_HIDDEN` parameter) this is `floor(log2(11)) + 2 = 5`, so the configured
  `parallelism = 6` is never reached. The degree is a function of the **driving relation's
  page count only** — it cannot see that each of those pages drives ~16 `lineitem` index
  probes plus an `orders` and a `customer` PK probe, i.e. that the per-page work is three
  orders of magnitude above a bare scan. Then
  `manager::start_tasks()` (`src/query/parallel/px_scan/px_scan.cpp:1794-1812`) pushes
  exactly `m_parallelism` tasks to the worker pool, and the calling transaction thread's
  only scan-related work in `manager::next()` is `m_result_handler->read()` (`:1873`) on
  the merged list. So active units = degree = 5, and the coordinator contributes
  0.20 core-s of the 4.34 core-s statement.
- **Mechanism, PostgreSQL side.** `compute_parallel_worker()`
  (`src/backend/optimizer/path/allpaths.c:4973`) also derives workers from a page-count
  logarithm, but on the same relation returns the full `max_parallel_workers_per_gather`
  cap of 5, and then the leader **also executes the plan**:
  `src/backend/executor/nodeGatherMerge.c:253-254`
  (`if (parallel_leader_participation || node->nreaders == 0)`) and `:403-404`
  ("Slot 0 is always for the leader. Leader always calls `ExecProcNode()`"), with
  `src/backend/executor/nodeGather.c:214-215` doing the same for plain `Gather`. The cost
  model knows it: `get_parallel_divisor()`
  (`src/backend/optimizer/path/costsize.c:6641`) adds `1.0 − 0.3 × nworkers` of leader
  contribution to the divisor. Measured result: `loops=6` on every node under the
  `Gather Merge`, peak 6.2449 units.
- **Evidence event and denominator.** Active execution units over one gated section 12
  block, measured per-TID with actual timestamp-delta weighting: CUBRID peak **5.2166**,
  TWU 3.8178, `U` 3.82408 (median of 5 WARM-converged runs, 8.45% max–min); PostgreSQL
  controlled index-NL — the same plan shape — peak **6.1742**, TWU 5.2479, `U` 5.25338.
  `F_units = 5.25338/3.82408 = 1.373763x`; the unit-count component is `6.2449/5.2166 =
  1.1971x`, i.e. **87%** of it. Independent confirmation from `perf stat`: 3.790 CPUs
  utilized (−0.89% against `U`).
- **Effect range.** Amdahl on the measured split gives 1.136 s → **0.998 s** at 6 units
  (`R_wall` 1.111086x → 0.976x, CUBRID ahead). Evidence type **projection**; the
  reconstruction at 5 units matches the measured headline exactly, which is what makes
  the 6-unit arithmetic credible but does not make it measured. A larger `auto_degree`
  ceiling on this relation would additionally raise the degree above 5, but the degree a
  work-aware formula *should* pick is not established by Q08 and is deliberately not
  claimed.
- **Implementation direction.** Two independently shippable steps. (a) Let the parallel
  coordinator execute a task: in `manager::next()`, when the merged-list read would block
  and an unclaimed input range remains, run one task inline on the calling thread — the
  input handler already partitions by range, so this needs no new partitioning, and it is
  the direct analogue of `need_to_scan_locally`. (b) Make the SCAN `auto_degree` aware of
  the per-page work of the `scan_ptr` chain hanging off the spec rather than of the
  driving relation's page count alone, and reach the configured `parallelism` when that
  work justifies it; the cheapest correct version multiplies `num_pages` by the estimated
  inner-probe count already available in the plan the spec came from
  (`src/optimizer/plan_generation.c:3204-3234` performs the equivalent computation for
  index scans and would be the place to keep the two consistent).
- **Correctness / regression risk.** (a) Medium: the coordinator thread would hold scan
  state it currently does not, so error/interrupt propagation
  (`m_interrupt`, `ERROR_INTERRUPTED_FROM_MAIN_THREAD` at `px_scan.cpp:1876`) and trace
  merging must both be re-checked — and trace merging is already defective
  (`IMP-005`), so this must not be shipped without fixing that first. (b) Low-medium:
  raising degree changes worker-pool pressure; `max_parallel_workers=100` bounds it, but a
  plan-stability and concurrency suite is required. No operator semantics change on either
  step.
- **Validation criteria.** Q08 CUBRID peak units ≥ 6.0 and `U` ≥ 4.5 with no hint, wall
  within 5% of 0.998 s; Q07's `USE_HASH` variant `U = 7.19707` does not regress; Q05's
  uncorrelated-subquery degree (`IMP-009`) is untouched by the change; Q01–Q22 plan-shape
  diff reviewed and SF10 total wall not regressed; the new degree validated against
  measured `U`, never against the configured cap.
- **Relations.** *Containment*: `IMP-009` — the same function
  `compute_parallel_degree()`, but its SUBQUERY branch (`px_parallel.cpp:84-108`,
  `auto_degree = 1` with an explicit "TODO: degree fixed at 1" comment); Q08 is the SCAN
  branch plus the coordinator, a different defect in the same decision point.
  *Alternative*: raise `parallel_scan_page_threshold` from its hidden 2048 default so the
  log₂ ladder reaches the cap sooner — rejected as the primary direction because it is a
  global constant that cannot distinguish a bare scan from a scan driving a three-level
  index-NL chain, which is exactly the information the formula is missing.
  *Predecessor*: none. *Not related*: `IMP-011` — that candidate is about the cost model
  preferring the wrong shape; on Q08 the cost model prefers the right shape.
- **Upstream precedent.** No precedent in the pinned CUBRID history for a participating
  parallel coordinator. PR #7441, included in this campaign's source SHA `607f1ee9`, added
  parallel hash-join execution; it did not change `start_tasks()`'s submit-only model.
- **Priority P0** — it is the only factor above 1.0 in Q08's card, it owns
  `F_units = 1.373763x` of a 1.111086x gap, and the mechanism applies to every CUBRID plan
  whose driving spec is a mid-sized heap scan.
- **Category** parallelism, optimizer. **Difficulty high** — not a localized
  early-return: step (a) changes which thread owns scan state and interacts with the
  known-defective trace merge; step (b) moves a degree decision that currently lives in a
  post-plan pass into something the planner can inform.
- **Status `measured`.**

### `IMP-013` — every page unfix in a hit path performs mutex-protected LRU list surgery, so CUBRID's 6.6x work advantage nets only a 16% CPU advantage

- **Mechanism, CUBRID side.** `pgbuf_lru_boost_bcb()`
  (`src/storage/page_buffer.c:10073`) is called on unfix of any BCB in LRU zone 2 or 3. It
  takes `pthread_mutex_lock(&lru_list->mutex)` (`:10113`), calls
  `pgbuf_remove_from_lru_list()`, `pgbuf_lru_add_bcb_to_top()`, then
  `pgbuf_lru_adjust_zone1()` (`:9834`) or `pgbuf_lru_adjust_zones()` (`:9937`), which walk
  the list to re-balance zone boundaries via `pgbuf_bcb_change_zone()` (`:15819`). This is
  reached once **per heap row** on Q08's dominant path:
  `heap_get_visible_version()` (`src/storage/heap_file.c:25026`) →
  `heap_clean_get_context` → `pgbuf_unfix` (`:3024`) → `pgbuf_lru_boost_bcb`, verified in
  the call graph at 5.38% of the `parallel-query` threads' cost. Q08 performs ~1.35 M such
  fix/unfix pairs per statement (403,487 `lineitem` + 403,487 `orders` + 122,404
  `customer` + 24,254 `supplier` heap lookups, each with its index descent).
- **Mechanism, PostgreSQL side.** `UnpinBuffer()` / `UnpinBufferNoOwner()`
  (`src/backend/storage/buffer/bufmgr.c:3479` / `:3488`) decrement a process-local
  `PrivateRefCountEntry->refcount`, and only when it reaches zero issue one
  `pg_atomic_fetch_sub_u64(&buf->state, BUF_REFCOUNT_ONE)`. `PinBuffer()` (`:3295`) bumps
  `usagecount` **inside the same compare-and-swap** that takes the pin. PostgreSQL's
  replacement algorithm is a clock sweep, so there is no ordered list to maintain, no
  per-list mutex, and no zone rebalance. Searched `page_buffer.c` for
  `clock`/`sweep`/`usagecount` — CUBRID has no clock-sweep equivalent.
- **Evidence event and denominator.** `perf record -F 999 -g --call-graph dwarf` on
  verified PID sets, self cost as a share of resolved samples (0 `[unknown]`, 0 lost, 75 k
  CUBRID / 111 k PostgreSQL samples): CUBRID `pgbuf_fix_release` 17.76% +
  `pgbuf_lru_boost_bcb` 5.41% + `pgbuf_unfix` 4.24% = **27.41%**, plus `libpthread`
  **5.32%**; PostgreSQL `PinBuffer` 1.91% + `LWLockAttemptLock` 1.23% +
  `LockBufferInternal` 0.56% = **3.70%**, `libpthread` 0.00%. Denominator for the causal
  factor: total query CPU-seconds per plan-node tuple touch — **1034.2 ns (CUBRID) vs
  194.4 ns (PostgreSQL)**, `F_cost = 5.320850x`.
- **Effect range.** Bounded by the 27.41% + 5.32% band, and bounded *below* by the fact
  that a clock sweep still pays the fix/locate cost: a realistic target is the
  `pgbuf_lru_boost_bcb` + mutex portion, 10.73% of CUBRID's profiled self cost, i.e.
  ≈0.47 core-s of the 4.34 core-s statement. At the measured `U` that is ≈0.12 s of wall,
  which combined with `IMP-012` would put CUBRID clearly ahead. Evidence type **profile
  attribution** (upper bound on the band, not a direct A/B — no in-contract switch exists
  to disable the boost).
- **Implementation direction.** Three increasingly invasive options, cheapest first.
  (a) Extend the existing zone-1 early-out: `pgbuf_lru_boost_bcb`'s own comment
  (`:10086-10098`) already documents an age-based suppression rule ("if a page is quickly
  fixed several times, its age is really small ... we don't boost it") implemented in
  `pgbuf_unlatch_bcb_upon_unfix`; on a random index-probe workload almost every touch is
  a *cold, single* touch of a zone-2/3 page, which is the case the rule does not cover.
  Suppress the boost when the BCB's hit count since insertion is 1 and the fix was a
  read-only visibility fetch. (b) Batch the boost: record boost intent in the BCB and
  apply it to the list under one mutex acquisition per N unfixes. (c) Replace the LRU
  lists with a clock sweep over the BCB array, which removes the list and the per-list
  mutex entirely — PostgreSQL's `freelist.c` `StrategyGetBuffer` is the reference shape.
- **Correctness / regression risk.** Low on correctness: the boost is a replacement-policy
  hint with no effect on visibility, latching or recovery. Medium-high on performance
  regression: suppressing boosts changes eviction order, so a workload whose hot set
  currently survives *because* of aggressive boosting could start missing. Option (a) is
  the only one shippable without a full buffer-pool re-validation.
- **Validation criteria.** `pgbuf_lru_boost_bcb` + `libpthread` share on Q08 drops below
  3% with `pgbuf_fix_release` unchanged; Q08 `total_query_cpu` drops by ≥0.3 core-s per
  statement; **`Q08` per-statement read-syscall count does not increase** (this is the
  regression that matters — a worse eviction order would show up as more pool churn, which
  section 5 shows costs 0.4099 core-s per GiB); Q01/Q03/Q04/Q06 walls not regressed, since
  those are the sequential-scan queries whose retention `IMP-002` already flags.
- **Relations.** *Containment*: `IMP-002` — that candidate is about *retention failure* at
  a working set near the pool size and already lists `pgbuf_lru_boost_bcb` among the
  symbols in Q04's miss-path profile; `IMP-013` is the *hit-path cost of the same
  bookkeeping*, which is a different quantity (`IMP-002` costs physical reads, `IMP-013`
  costs CPU on pages that were found). *Alternative*: `IMP-010` — same subsystem, but the
  insertion-position defect for newly read pages (private vs shared LRU by thread
  identity); fixing `IMP-010` changes *where* pages land, fixing `IMP-013` changes
  *whether the list is touched at all* on a hit. *Predecessor*: none.
- **Upstream precedent.** No precedent in the pinned CUBRID history for removing or
  batching the LRU boost. The age-based suppression comment at `page_buffer.c:10086-10098`
  shows the cost was anticipated by the original author for a repeat-fix pattern, which is
  the closest thing to a precedent and is why option (a) is proposed first.
- **Priority P1** — it owns the largest profile band on either engine and is the lever
  that turns CUBRID's 6.6x work advantage into a wall win, but it is not the factor that
  loses Q08 (`F_cpu` already favours CUBRID by 16%), so it ranks below `IMP-012`.
- **Category** buffer/IO, parallelism. **Difficulty medium** for option (a) — a localized
  predicate in one function with an existing suppression precedent; **very high** for
  option (c).
- **Status `measured`.**

### `IMP-002` — Q08 relation: the strongest quantification so far, and a projection that reaches parity

Q08 adds a five-block regression rather than another instance: `r(rchar, CPU) = +0.9779`,
`r(CPU, wall) = +0.9717`, slope **0.4099 core-s per GiB** of pool re-read, and an OLS
intercept of **0.9752 s** at zero churn against PostgreSQL's measured 1.022423 s. It also
adds the instability evidence: the identical warm statement measured **166 to 71,654 read
syscalls** across six configurations of the same server (`q8-iobisect.txt`). Working-set
arithmetic for Q08's access pattern puts CUBRID at ≈7.85 GiB of a 8.00 GiB pool (98%
fill) against PostgreSQL's ≈2.65 GiB random footprint on 8 KiB pages — the
"marginally exceeds the pool" condition this candidate names, now on a random
index-driven pattern like Q04's. `read_bytes = 0` on three of five blocks, so the cost is
page-cache re-read CPU, not storage. `q_relations` becomes
`Q01, Q03, Q04, Q05, Q06, Q07, Q08`.

### `IMP-007` — Q08 relation: 14,231–60,829 single-page `pread`s per statement, and 38.5x PostgreSQL's context-switch rate

Q08's per-statement read-syscall count is block-dependent (see `IMP-002`) but is a
single-page `pread` in every case: `rchar/syscr = 16,344 bytes`, exactly one 16 KiB page.
The synchronous nature is visible as **207,274 context switches in 20.002 s (2.734 K/s)**
against PostgreSQL's **7,880 (71/s)** — 38.5x the rate — and as 4.44% of CUBRID's profile
in the page-cache read path (`rep_movs_alternative` 3.66% + `filemap_get_read_batch` 0.51%
+ `filemap_read` 0.27%). PostgreSQL issues 1,704 read syscalls per statement with
`read=0` at the buffer level. `q_relations` becomes `Q03, Q04, Q06, Q07, Q08`.

### `IMP-005` — Q08 relation: an exact per-level integer multiplier, and it cost the report its work instrument

Q08 is the cleanest demonstration yet because every discrepancy is an exact integer
multiple of ground truth: `lineitem readkeys ×5.00` (the worker count),
`orders readkeys ×2.00`, `orders lookup rows ×2.00`, `customer readkeys ×3.00`
(the `scan_ptr` depth), top-level `rows ×1.00`. The consequence is methodological: the
`F_work` numerator in section 3-a had to be built from ground-truth `count(*)` queries
instead of the trace, and `IMP-012`'s implementation step (a) cannot ship before this is
fixed, because moving work onto the coordinator thread adds another merge level.
`q_relations` becomes `Q03, Q04, Q05, Q06, Q07, Q08`.

### `IMP-011` — considered and explicitly **not** related on Q08 (positive control)

`IMP-011` claims join plan selection is parallel-degree blind and therefore picks serial
index-NL over a parallelisable hash plan. On Q08 the same code path picks index-NL and
that is **correct**: the hash plan is 1.5123x slower on CUBRID (1.718 s vs 1.136 s) at
2.5492x the CPU, and PostgreSQL is 1.0364x faster when forced onto CUBRID's index-NL
shape. CUBRID's cost model rates the two 288,795 vs 3,112,001 — the *ordering* is right,
the *magnitude* is 7.1x pessimistic. Q08 is therefore recorded on `IMP-011` as a positive
control: a query where the parallel-degree blindness did not change the outcome, because
the plan CUBRID's model prefers is also the plan that parallelises. This is the
counterexample `IMP-011`'s validation criteria demand ("Q05's native index-NL choice does
NOT flip"), and Q08 supplies a second one.

### `IMP-001`, `IMP-003`, `IMP-004`, `IMP-006`, `IMP-008`, `IMP-009`, `IMP-010` — not related on Q08

- `IMP-001` (NUMERIC aggregate accumulation): the aggregate sees 24,254 rows; no NUMERIC
  symbol reaches the 0.25% profile cut on either engine.
- `IMP-003` / `IMP-004` (leading-wildcard `LIKE` selectivity and the UTF-8 `LIKE`
  matcher): Q08 has no `LIKE`.
- `IMP-006` (intermediate-result materialisation per value): CUBRID's list-file traffic on
  Q08 is 6.7 MiB `wchar` per statement against PostgreSQL's 322.7 MiB of DSM writes;
  the band does not appear in the profile above the cut.
- `IMP-008` (generic `DB_VALUE` comparator for scan sargs): `tp_value_compare_with_error`
  0.59%, `eval_value_rel_cmp` 0.50%, `mr_cmpval_*` 1.02% — 2.11% total, an order of
  magnitude below the 27.41% buffer band, because Q08's sargs are evaluated on 2 M `part`
  rows only.
- `IMP-009` (uncorrelated-subquery degree hardcoded to 1): Q08's three `nation`/`region`
  subqueries do report `parallel workers: 2`, i.e. the hardcoded degree, but they consume
  <0.1% of measured cost. Contained by `IMP-012` as the sibling branch of the same
  function.
- `IMP-010` (private vs shared LRU insertion by thread identity): Q08's scans run on
  pooled parallel workers throughout, so there is no same-query client-thread/worker-thread
  contrast to measure. Related to `IMP-013` as an alternative in the same subsystem.

## 10. Evidence index

Format: `claim → raw file:line → formula → evidence type → SHA-256`. Hashes below are the
first 16 hex digits of the SHA-256 of the promoted immutable artifact under
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q08/`; full 64-digit values, byte sizes,
creation commands and validity flags are in `reports/Q08/raw-manifest.json`.

| Claim | Raw pointer | Formula | Evidence type | SHA-256 (16) |
|---|---|---|---|---|
| `R_wall = 1.111086x`; CUBRID 1.147/1.136/1.048, median 1.136 | `Q08-cubrid-headline-block1.json` `measured_times_s`, `median_s` | `median(1.147,1.136,1.048)` | direct measurement | `11a6c21e82fc95c7` |
| PostgreSQL 1.044851/1.019921/1.022423, median 1.022423 | `Q08-postgresql-headline-block1.json` `measured_times_s`, `median_s` | `median(...)`; ratio `1.136/1.022423` | direct measurement | `5e56a16b49c907e5` |
| Both blocks accepted attempt 1, gate `CLEAN` | `Q08-cubrid-bgload-block1.json`, `Q08-postgresql-bgload-block1.json` `verdict`, `external_max` | per-sample external CPU ≤ 6.0 core-s/s | direct measurement | `7ea883bbc8787a34`, `69ed4c61ecb8f755` |
| `F_plan = 0.964885x` (CUBRID's shape is better) | `Q08-postgresql-idxnl-headline.json` `median_s` = 0.986521 | `0.986521/1.022423` | direct A/B | `8d1425aeece59e56` |
| PG controlled plan reproduces CUBRID's chain node-for-node | `variants/plan-nestloop_forced.out` lines 15-61 (`Nested Loop` ×6, `orders_pkey`, `customer_pkey`, `supplier_pkey`) | node-by-node against `q8-plan-est-cubrid.out` `Query plan:` block | direct A/B | `977d29e0f08c3c7b` |
| CUBRID controlled hash variant = 1.718 s, 1.5123x slower | `Q08-cubrid-hashoc-headline.json` `median_s` | `1.718/1.136` | direct A/B | `2acc71aa5d367f7b` |
| CUBRID hash variant is PostgreSQL's shape (cost 3,112,001) | `variants/plan-USE_HASH_ORDERS_CUSTOMER.out` `Query plan:` block | plan-only run, `SET OPTIMIZATION LEVEL 514` | direct A/B | `fad48aa859ba50c7` |
| `F_units = 1.373763x` | `Q08-postgresql-idxnl-headline-telemetry.json` `utilization.U_core_s_per_wall_s` = 5.25338; `Q08-cubrid-headline-telemetry-run5.json` = 3.82408 | `5.25338/3.82408` | profile attribution | `a6500f2e2228df66`, `488e55f36c6feb24` |
| `F_cpu = 0.838224x`; CPU 4.3442 vs 5.1826 core-s | same two telemetry JSONs, `cpu.total_query_cpu_block_core_s` and `U` | `(3.82408×1.136)/(5.25338×0.986521)` | profile attribution | `a6500f2e2228df66`, `488e55f36c6feb24` |
| `F_cpu(native) = 0.805422x` | `Q08-postgresql-headline-telemetry-run3.json` `U` = 5.27535 | `(3.82408×1.136)/(5.27535×1.022423)` | profile attribution | `a4c36c382a26848f` |
| CUBRID reaches `U = 6.44602`, peak 11.1882 on the hash shape | `Q08-cubrid-hashoc-headline-telemetry.json` `utilization`, `units` | direct read | profile attribution | `899e7151a02ff357` |
| Intermediate cardinalities 13,452 / 403,487 / 122,404 / 122,404 / 24,254 identical on both engines | `q8-groundtruth-cubrid.out`, `q8-groundtruth-pg.out` (rows `G1`–`G6`, `H1`–`H3`) | `count(*)` per join prefix | direct A/B | `ff68a9c36803e491`, `8060fec9b4e23885` |
| `F_work = 0.151371x`, `F_cost = 5.320850x`, `W_C` 4,200,631 / `W_P` 27,750,587 | `q8-card-calc.txt` section `[F_work / F_cost on the NATIVE pair]`; `Q08-causal-card.json` `native_pair` | per-node touch sum from ground truth; `F_cost=(CPU_C/W_C)/(CPU_P/W_P)` | direct A/B (work) + profile attribution (cost) | `9bec4a03e1569d88`, `6c0829520b19d682` |
| Both anchors reconstruct at 0.000000% residual | `q8-card-calc.txt` anchor A and anchor B blocks | `F_plan×F_units×F_cpu` vs `T_C/T_P` | identity | `9bec4a03e1569d88` |
| CUBRID pool churn: `r(rchar,CPU)=+0.9779`, `r(CPU,wall)=+0.9717`, 0.4099 core-s/GiB, zero-churn intercept 0.9752 s | `q8-poolchurn-regression.txt` (5-block table + Pearson + OLS lines) | OLS and Pearson over 5 WARM-converged blocks | projection (intercept), profile attribution (slope) | `ab1487d0acb2b917` |
| Identical warm statement = 166..71,654 read syscalls | `q8-iobisect.txt` rows A–D | `/proc/<cub_server>/io` deltas around each form | direct measurement | `dfba13aadcd8286e` |
| CUBRID parallel workers = 5, readrows 399,448..401,913, gather mergeable list | `q8-trace-cubrid.out` `SCAN (table: dba.part)` block | `SET TRACE ON; … SHOW TRACE;`, separate non-headline run | direct measurement | `561a07f468e56987` |
| CUBRID trace counters carry an exact per-level multiplier (×5.00 / ×2.00 / ×3.00 / ×1.00) | `q8-trace-cubrid.out` `readkeys`/`rows` per node vs `q8-groundtruth-*.out` | counter ÷ ground truth | direct A/B | `561a07f468e56987` |
| PostgreSQL `Workers Launched 5`, `loops=6`, `shared hit=796312 read=0`, `Batches: 1` | `q8-plan-act-pg.out` lines 1-13, 44-135, 343-345 | `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, TIMING)`, separate non-headline run | direct measurement | `0fd2fa85553cc7eb` |
| CUBRID estimated plan and 288,795 cost; `part` sscan + 3-level idx-join chain | `q8-plan-est-cubrid.out` `Query plan:` block | `SET OPTIMIZATION LEVEL 514`, non-executing (0.02 s) | direct measurement | `40b713e10688519a` |
| PostgreSQL estimated plan, `Workers Planned 5` | `q8-plan-est-pg.out` | `EXPLAIN (COSTS, VERBOSE, SETTINGS)`, non-executing | direct measurement | `19f1637c6dc46c11` |
| `perf stat` CUBRID 3.790 CPUs, IPC 1.20, 252.359 G insn, 207,274 ctx-sw | `perf-stat-cubrid.txt` | attached to verified pid 1612732 for 20.002 s | direct measurement | `ab0f4ce1a96fad9d` |
| `perf stat` PostgreSQL 5.514 CPUs, IPC 1.10, 341.463 G insn, 7,880 ctx-sw | `perf-stat-pg.txt` | postmaster attach before client connect, inherit-on-fork, 20.002 s | direct measurement | `e82aa18eb21293df` |
| CUBRID buffer band 27.41% + `libpthread` 5.32%; `pgbuf_lru_boost_bcb` 5.41% | `profile-cubrid-flat-nog.txt`; `profile-cubrid-callgraph.txt` (`pgbuf_lru_boost_bcb` caller chain) | self-cost share of 75,004 resolved samples, 0 `[unknown]`, 0 lost | profile attribution | `8903401aa5926869` |
| PostgreSQL buffer band 3.70%; kernel 30.17%; `next_uptodate_folio` 8.75% via `heap_page_prune_opt`→page fault | `profile-pg-flat-nog.txt`; `profile-pg-callgraph.txt` | self-cost share of 111,037 resolved samples, 0 `[unknown]`, 0 lost | profile attribution | `24d34cda13241402` |
| `result-equivalent-at-SF10`, 2 rows, ordered | `q8-correctness.json`, `q8-correctness-cubrid.out`, `q8-correctness-postgresql.out` | SSOT §11 comparator, ordered sequence, 1e-12 relative tolerance | direct A/B | `8c839f652f284df2` |
| CUBRID `read_bytes` 0, `statdump` perfmon frozen (delta 0) | `Q08-cubrid-buffer-io-diag.json` `buffer`, `proc_io_delta`, `device_delta_MiB` | `statdump` and `/proc/<pid>/io` deltas around one non-headline block | direct measurement | `704bd9481c0ccbb2` |
| PostgreSQL 322.7 MiB/statement `write_bytes` with 0 device write (mmap DSM) | `Q08-postgresql-buffer-io-diag.json` `proc_io_per_statement`, `device_delta_MiB` | `/proc/<postmaster>/io` deltas around one non-headline block | direct measurement | `ccdbef8239e629f3` |
| Preflight: 8 FK / 8 idx_fk_* / convalidated 8, cpuset `off_cpuset=0`, external 0.358 | `preflight-Q08.txt` | SSOT §14.1 gate script | direct measurement | `a22e17dae88c3630` |
| Post-block: ownership `OK`, 0 orphans, `off_cpuset=0`, no SSOT drift | `q8-postcheck.txt` | SSOT §10 post-block gate | direct measurement | `e75b959aa1a90224` |
| CUBRID telemetry run2 invalidated (WARM gate failed) | `Q08-cubrid-headline-telemetry-run2-INVALID.json` | `warm_establish.py` rc=4, monotone trailing window | exclusion record | `e15cddca59dce688` |
| WARM parameters justified by this query's own 40-statement probes | `q8-convergence-cubrid.json`, `q8-convergence-pg.json` | half-split trend and trailing spread at n=40 | direct measurement | `673e0a9d57bc72be`, `2e8de683d20fc9a0` |

## 11. Notion sync

Per SSOT §21 **Execution boundary**: this report was produced by the GJC/tmux worker
session `gajae_code_ms8qkc6c_v1bq25m2` on the remote build host, which has no Notion
connector. Its Notion-adjacent duty ends at committing and pushing this report, the raw
manifest and the improvement registry to `origin/main`.

| Field | Value |
|---|---|
| Write path attempted by this session | **none** — the worker session must never issue a Notion write |
| Durable fallback | idempotent record appended to `reports/notion_backfill_pending.jsonl` (write path 3) |
| Idempotency key | `campaign_id + QNN + session_id + report_commit + content_fingerprint` |
| Required follow-up | the section 23 reconciler subagent (or a purpose-spawned one-off subagent) with Notion tool access must mirror this report from the pushed GitHub commit: Q08 database row, page body carrying the §21 content-richness set (causal card with full factor table, headline timings, plan comparison for both engines, profile top symbols for both engines, full source contrast with `file:line` on both sides, the decomposition narrative including rejected explanations, every improvement candidate), plus one improvement-registry page each for `IMP-012` and `IMP-013` with all §18 fields and every select/property populated, and Q08 relations added to `IMP-002`, `IMP-005`, `IMP-007`, `IMP-011` |
| Formatting rule to apply | assemble content with real newline characters, never the two-glyph literal `\n`; never escape `<table>`/`<tr>`/`<td>`, `##` headings or code fences; after writing, `notion-fetch` the page back and scan for an isolated `n` token or a literal `<`/`&lt;` inside a rendered table |

Notion availability does not block measurement, deep analysis, final IMP ID allocation or
query transition (SSOT §21). `IMP-012` and `IMP-013` are allocated in the Git ledger and
pushed; the same IDs are to be backfilled, never reallocated.

## 12. Completion checklist

| SSOT §26 gate | Status |
|---|---|
| Preflight and correctness status recorded | **done** — `preflight-Q08.txt` (all gates PASS, `ssot_drift=NONE`), `q8-correctness.json` `result-equivalent-at-SF10` |
| Three valid headline values for each completing engine | **done** — CUBRID 1.147/1.136/1.048; PostgreSQL 1.044851/1.019921/1.022423; both blocks accepted on attempt 1 with `CLEAN` load verdicts |
| Timeout confirmations if censored | **n/a** — neither engine censored; both ≈1.0–1.2 s against a 300 s timeout |
| Plan section complete | **done** — §4: estimated plans both engines (non-executing), CUBRID trace with parallel-worker annotation, PostgreSQL `EXPLAIN ANALYZE`, node-for-node shape table, estimate-vs-ground-truth accuracy |
| Execution section complete | **done** — §5: per-TID CPU decomposition (executor/auxiliary/unattributed), TWU from actual timestamp deltas, planned/launched/peak/serial-tail, `/proc` I/O, iostat, device and NUMA deltas, buffer counters, the 5-block pool-churn regression |
| Profile section complete | **done** — §6: `perf stat` both engines on verified PID sets, 0 `[unknown]` and 0 lost samples, banded flat profiles, call-graph verification of both dominant bands |
| Source contrast complete | **done** — §7: 7 rows with `file:line` on both sides, classes assigned, plus an explicit searched-paths/symbols record for the two absence claims |
| Causal multiplier card has evidence or explicit `UNMEASURED` | **done** — §3-a: every factor numeric with event unit, denominator, formula, raw pointer and evidence type; `F_plan` numeric by a same-engine controlled A/B with the anchor direction named; two anchors, both reconstructing at 0.000000% residual; error budget stated before interpretation. No factor is `UNMEASURED` |
| Reconstruction residual within the measured error budget | **done** — residual 0.000000% on both anchors (identity by construction); the independent closure evidence is `U` reproducibility (8.45% / 5.85%), TWU (−0.16% / +4.95%), `perf stat` (−0.89% / +4.52%) and the instruction/IPC and context-switch counters |
| Git improvement ledger deduplicated and committed | **done** — searched by title, both source locations and root cause before allocating; `IMP-012` and `IMP-013` allocated; Q08 relations added to `IMP-002`, `IMP-005`, `IMP-007`; `IMP-011` recorded as an explicit positive control (not related); `IMP-001`/`003`/`004`/`006`/`008`/`009`/`010` recorded as not related with the number that rejected each |
| Notion relations synced or idempotent backfill durable | **backfill durable** — worker session is barred from Notion writes by §21; idempotent record appended to `reports/notion_backfill_pending.jsonl`; reconciler subagent scope specified in §11 |
| Every claim indexed to raw evidence and checksum | **done** — §10, 30 rows, each with raw pointer, formula, evidence type and SHA-256; full hashes in `raw-manifest.json` |
| Report, manifest and registry committed, pushed, reachable from `origin/main` | see `report_commit` in the `TPCH_SSPQ_STATUS` block emitted with this report |
| `QUERY_COMPLETE` emitted | on completion of the push verification |
| Current session removed and absence verified | after the push, with `gjc session status <exact-id>` and `tmux has-session -t <exact-id>` |

### Invalid runs retained and excluded

| Artifact | Reason | Handling |
|---|---|---|
| `Q08-cubrid-headline-telemetry-run2.json` | `WARM_NOT_ESTABLISHED` — `warm_establish.py` rc=4, `monotone trailing window (still drifting)`; statement times `[1.269, 1.225, 1.161, 1.027]` were timed on a decay curve | `Q08-cubrid-headline-telemetry-run2-INVALID.json` written; excluded from every `U`, TWU, CPU and regression calculation; superseded by runs 4, 5, 6 |

### Carried forward to later queries

1. **`cubrid statdump` per-statement deltas are still unusable** (frozen global perfmon
   counters, reproduced here on a trivial serial scan as well). Q06 recorded the same;
   all Q08 I/O evidence therefore comes from `/proc/<pid>/io`. A working per-statement
   CUBRID buffer-counter instrument remains an open harness item.
2. **CUBRID's cross-block wall level is not stable on random-access plans** (19.58% on
   Q08 against PostgreSQL's 1.43%). The section 5 regression explains it, but the
   consequence for the campaign is methodological: for any query whose ratio lands below
   ~1.25x, the contract median-of-3 must be reported together with a cross-block band, or
   the ratio will read as more precise than the engine is.
3. **`IMP-012` step (a) is blocked by `IMP-005`.** Moving work onto the parallel
   coordinator adds another trace-merge level, and the merge is already defective by an
   exact per-level multiplier. The trace fix must land first.
