# TPCH-SSPQ FK campaign — Q12 report

TPC-H Query 12, *Shipping Modes and Order Priority*.

## 3-a. Causal multiplier card

```text
R_wall 1.541648x [wall, median of 3 per engine; PostgreSQL is 1.5416x faster]
= F_plan  1.000000x [plan-shape; structural equality, section 4-c]
× F_units 1.102707x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   1.398058x [total query CPU-seconds]

F_cpu 1.398058x [total query CPU-seconds]
= F_work 1.000000x [lineitem rows scanned: 59,986,052 vs 59,986,052 — EXACTLY equal]
× F_cost 1.398058x [396.80 ns vs 283.82 ns of total query CPU per row scanned]
```

**Read the card in one line: both engines run the same plan, launch the same six
execution units, and scan exactly the same 59,986,052 rows — so every part of Q12's
1.54x lands in `F_cost`, the CPU spent per row.** `F_work` is not approximately 1, it
is exactly 1: the row count is a ground-truth `count(*)` both engines answer
identically, CUBRID's trace reproduces it as the sum over its six workers
(9,938,887…10,011,920 each) and PostgreSQL's as `Rows Removed by Filter` 9,945,875 × 6
loops plus 310,803 output rows. **This is the exact inverse of Q11**, whose `F_cpu` was
entirely a count factor (`F_work` 1.4964x) with `F_cost` *below* 1.

**The obvious explanation is wrong and the measurement says so.** Q12 looks like a
parallelism story — a 10,671 MiB single-table scan where PostgreSQL prints
`Workers Planned: 5` and CUBRID's plan text prints nothing. It is not. CUBRID runs
**six parallel heap-scan workers** (`q12-trace-cubrid.out`: `parallel workers: 6`), and
each engine's own parallelism switch, measured through the same gated §12 block, says
CUBRID's parallel implementation is the **better** one:

| | CUBRID | PostgreSQL |
|---|---|---|
| serial wall (1 unit) | 21.636999 s | 13.098051 s |
| parallel wall | **4.039000 s** | **2.619923 s** |
| speedup from going parallel | **5.3570x** | 4.9994x |
| CPU inflation from going parallel | **1.0971x** | 1.1733x |
| measured U (core-s per wall-s) | 5.89315 | 6.49842 |
| TWU | 5.8296 | 6.4932 |
| parallel efficiency vs TWU | **91.9%** | 77.0% |

CUBRID converts its six units into 5.357x for a 9.7% CPU surcharge; PostgreSQL gets
4.999x for 17.3%. **Q12's gap is already present at one unit and parallelism narrows
it**: serial 21.636999/13.098051 = **1.65193x**, parallel **1.541648x**. Anything that
attributes Q12 to missing or weak CUBRID parallelism is refuted by a same-engine A/B on
the engine's own switch.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 1.000000x | plan shape | — | structural equality of the operator chain, argued node-by-node in 4-c | `q12-plan-est-cubrid.out`, `q12-plan-est-pg.out`, `q12-trace-cubrid.out`, `q12-plan-act-pg.out` | structural equality |
| `F_units` | 1.102707x | active execution units | CPU-seconds / wall-second over the §12 block | `U_P/U_C` = 6.49842/5.89315 | `Q12-postgresql-headline-telemetry-run2.json`, `Q12-cubrid-headline-telemetry-run1.json` | profile attribution |
| `F_cpu` | 1.398058x | total query CPU-seconds | per query execution | `CPU_C/CPU_P` = 23.8024/17.0254 | same telemetry JSONs × the block medians | profile attribution |
| `F_work` | 1.000000x | lineitem rows scanned | one statement | `59,986,052 / 59,986,052` | `q12-groundtruth-cubrid.out`, `q12-groundtruth-pg.out`, `q12-trace-cubrid.out`, `q12-plan-act-pg.out` | direct A/B (ground truth) |
| `F_cost` | 1.398058x | CPU-seconds per row scanned | rows scanned | `(CPU_C/W_C)/(CPU_P/W_P)` = 396.80 ns / 283.82 ns | `Q12-causal-card.json`, `q12-card-calc.txt` | profile attribution |

**Reconstruction residual: `F_plan × F_units × F_cpu` = 1.541648x against `R_wall`
1.541648x, residual `+0.000000000%`.** CPU is attributed as `U × t_median` on the same
block regime the wall is defined on, so the identity is exact by construction; the
independent cross-checks are TWU (within −1.08% of `U` on CUBRID, −0.08% on
PostgreSQL), the two controlled unit A/Bs above, `perf stat`, and the trace/EXPLAIN
counters.

### Secondary decomposition on data-page fixes

```text
F_cpu 1.398058x
= F_work 0.800351x [data-page fixes: 1,788,621 vs 2,234,797]
× F_cost 1.746806x [13,307.7 ns vs 7,618.3 ns of total query CPU per page fix]
```

`F_work` is below 1 only because CUBRID's 16 KiB page halves the heap-scan fix count for
the same bytes. The **join** side is near-identical — CUBRID 1,105,561 index+heap fixes
against PostgreSQL's 1,109,634, a ratio of 0.9963x on 310,803 probes — which is what
makes the physical-read comparison in section 5-e a like-for-like one. CUBRID's total
was measured directly: `statdump Num_data_page_fetches` bracketed around one traced
native statement moved by 1,788,621, reproducing `682,937 heap + 1,105,561 index =
1,788,498` to **0.007%**.

### Error budget, stated before any factor is interpreted

| | contract blocks | + telemetry blocks | spread |
|---|---|---|---|
| CUBRID block medians | 4.039 / 4.049 / 4.045 | 3.936 … 4.049 | 0.25% / **2.87%** |
| PostgreSQL block medians | 2.619923 / 2.624023 / 2.629931 | 2.619923 … 2.642269 | 0.38% / 0.85% |

Ratio band implied by the two spreads: 1.4896x … 1.5455x, against the contract
`R_wall` of 1.5416x. **Error budget = 2.87%** (worst single-engine block-median
spread). The card's residual is 0.000000000%, so the card is closed. Every effect
claimed below is larger than 2.87% of the quantity it is claimed against, or is
explicitly labelled as a bound rather than a value.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| Query | Q12 — Shipping Modes and Order Priority |
| SSOT commit | `d6e337130915e260bca8277c379915beeac85d09` |
| SSOT blob SHA | `510478846bff081d3223d3835069283a7cd2e47b` |
| SSOT drift | **NONE** — verified at preflight and again at post-block gate; `HEAD:tpch-sspq/SSOT.md` equals the pin at both |
| GJC session ID | `gajae_code_ms99nxvi_8e3xv48r` |
| Raw root | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q12` (270 artifacts, 4.9 MB) |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (includes PR #7441 merge `b334446d6`) |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` (PostgreSQL 20devel) |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b`, ELF Build ID `5f2cb2987765c612638c278f85cfc85c211fffe1` |
| Build flags | CUBRID RelWithDebInfo, assertions disabled, not stripped; PostgreSQL `--enable-debug --without-llvm`, assertions off, JIT off — frozen `reports/bootstrap/build-manifest.json`, `frozen: true` |
| Ownership gate | pre-block and post-block **OK** — `cub_master` 1433697, `cub_server` 1612732, postmaster 1433696, all resolving to the campaign prefixes; both binary hashes match the frozen manifest |
| cpuset / NUMA | 34 engine TIDs, **0 off-cpuset** before and after; SUT+client CPUs 0-15 (node0), collectors 20-23 |
| External load | 0.262 core-s/s at preflight, 0.266 at post-block, every accepted block `CLEAN` (threshold 6.0) |
| Query provenance | `queries/q12-cubrid.sql` SHA-256 `e528823a063a0d1bbf7ed6afd6cb3c133fecfdacf163e4d71890331d354565a0`, **byte-matches** `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q12.sql` |
| Dialect | `queries/q12-pg.sql` SHA-256 `46742565ea52506cf25cff86bd29022eb5f35da91a52157010b115509dc0089f`; one change (`queries/diff/q12.diff`, 622 bytes): `DATE_ADD(DATE '1994-01-01', INTERVAL 1 YEAR)` → `date '1994-01-01' + interval '1' year`. No hint, no join reordering, no subquery rewrite, no extra predicate, no semantic cast |
| Schema contract | 8 FK / 8 child B-trees per engine, exact column order, all PostgreSQL constraints `convalidated=t` |
| Statistics | histogram-enabled controlled comparison: CUBRID `update_statistics_update_histogram=y`, bucket target 300; PostgreSQL `default_statistics_target=100`, standard `ANALYZE` |
| Parallel/buffer | configured node/gather-cap comparison, configured-equal buffer budget: CUBRID `parallelism=6`, `max_parallel_workers=100`, `data_buffer_size=8.0G` (524,288 pages); PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`, `parallel_leader_participation=on`, `shared_buffers=8192MB` (1,048,576 blocks) |
| Shared memory | `dynamic_shared_memory_type=mmap` — load-bearing for Q12: PostgreSQL's `Gather Merge` tuple queues live in DSM, and the mmap fault-in of those segments is a *measured* 1.8966 core-s band in its profile (section 6-b) |
| Row counts | identical on both engines: lineitem 59,986,052; orders 15,000,000 |
| Stored size | lineitem: CUBRID 682,937 × 16 KiB = **10,671 MiB**; PostgreSQL 1,125,128 × 8 KiB = **8,790 MiB**. orders: CUBRID 151,689 × 16 KiB = 2,370 MiB; PostgreSQL heap 2,041 MB, total 2,483 MB |
| Engine block order | Q12 is even → **PostgreSQL block first, then CUBRID** (SSOT §12) |

Q12's driving relation does **not** fit either pool: 1.30x the budget on CUBRID, 1.07x
on PostgreSQL. That is the precondition for everything in section 5-e.

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored; both engines completed far inside the
300 s timeout.

| l_shipmode | high_line_count | low_line_count |
|---|---|---|
| `MAIL` | 62,071 | 93,045 |
| `SHIP` | 62,426 | 93,261 |

2 rows, `ORDER BY l_shipmode` present, so the ordered sequence was compared exactly
under SSOT §11. Text, integers, NULLs, row count and row multiset match; all output
values are integers, so the decimal tolerance never engaged. CUBRID renders
`l_shipmode` as the CHAR(10)-padded `'MAIL      '` and PostgreSQL as `MAIL      ` —
identical after the comparator's documented text normalisation, and the padding itself
is identical.

Independent confirmation from the join arithmetic: 62,071 + 93,045 + 62,426 + 93,261 =
**310,803**, which equals ground truth `G5_scan_survivors` and `G6_join_rows`
independently computed on both engines, and equals PostgreSQL's `Index Searches:
310803` and its `rows=51800.50 × 6 loops`.

Raw: `q12-correctness.json` (`222f8acc…`), `q12-correctness-cubrid.out`,
`q12-correctness-postgresql.out`.

## 3-b. Headline timings

Regime: **single-query-repeat WARM**. Connection mode:
**`single-connection-four-statements`** — one direct connection, one uncounted warmup,
three measured statements, no prepare/pool/reconnect between them, connection
establishment excluded, every statement fully consuming all rows into a campaign-owned
sink under `work/Q12` with no terminal rendering. CUBRID uses `csql -C` direct ad-hoc
execution; PostgreSQL one `psql` Unix-socket connection on the simple-query protocol.

| | statement 1 | statement 2 | statement 3 | median | mean | sd |
|---|---|---|---|---|---|---|
| **CUBRID** (block1, headline) | 4.052000 | 4.039000 | 4.015000 | **4.039000 s** | 4.035333 | 0.018771 |
| **PostgreSQL** (block1, headline) | 2.633592 | 2.612043 | 2.619923 | **2.619923 s** | 2.621853 | 0.010903 |

**Median wall ratio: 1.541648x — PostgreSQL faster.** Mean ratio 1.538744x, so the
median is not an artifact of the choice of statistic. Three values per engine; no
confidence interval is claimed from three values (SSOT §12).

Uncounted warmup statements: CUBRID 4.069999 s, PostgreSQL 2.663710 s — 0.77% and 1.67%
above their own block medians, i.e. the block is on its level from the first measured
statement.

Sinks: CUBRID 1,327 bytes SHA-256 `c8462766…`; PostgreSQL 318 bytes SHA-256
`8c3259bd…`. The byte counts differ because CUBRID's `csql` writes a bordered result
table and `psql -A -t` writes unaligned tuples only; the *content* equivalence is
section 2's gate, and per-statement client wall includes that transfer and sink write
while client formatting/transfer CPU stays in `auxiliary_query_cpu`, never attributed to
the executor.

### All three blocks per engine

| block | CUBRID median | PostgreSQL median |
|---|---|---|
| 1 (**headline**) | **4.039000** | **2.619923** |
| 2 | 4.049000 | 2.624023 |
| 3 | 4.044999 | 2.629931 |
| spread | **0.25%** | **0.38%** |

Every one of the six blocks was accepted on **attempt 1** with a `CLEAN` load verdict
under both the strict per-sample rule and the contract-window rule. Blocks 2 and 3 are
retained as stability evidence and are marked non-headline in the manifest. Q12 shows
none of Q11's block-to-block level shifting, and section 5-e explains why: there is no
residency state to lose when the working set is 1.30x the pool.

### WARM proof

WARM is proved, not assumed. Gate parameters were derived from **this query's own**
40-statement convergence probes rather than inherited (`q12-warm-gate-params.txt`):

| | probe steady state | half-split trend | trailing spread | first converged at |
|---|---|---|---|---|
| PostgreSQL | 2.600109 s | +0.2158% | 0.2123% | statement 12 |
| CUBRID | 4.019000 s | −0.4948% | 1.2192% | statement 12 |

Chosen: `WARM_STATEMENTS=20`, `WINDOW=6`; `LEVEL_TOL` 0.010 (PostgreSQL, 4.6x margin
over the measured trend) and 0.020 (CUBRID, 4.0x); `SPREAD_SANITY` 0.030 both.

The headline blocks' own warm establishment reported **CONVERGED** for both engines:
PostgreSQL half-split trend −0.0285% over 20 statements, trailing spread 0.7403%, steady
2.601916 s; CUBRID +0.2739%, spread 1.4618%, steady 4.036000 s. Both converged at
statement 18 of 20. The steady states the gate certified (2.601916 / 4.036000) sit
0.69% and 0.07% from the block medians actually measured.

Physical-read deltas and engine buffer counters are in section 5-d/5-e. Neither engine
reaches zero physical reads on Q12 — both working sets exceed both pools — so WARM here
means *proved-stationary*, not *zero-miss*, and the stationarity is what the probes
above certify.

## 4. Plan

### 4-a. CUBRID native (estimated, `SET OPTIMIZATION LEVEL 514`, non-executing)

```text
temp(group by)
    subplan: idx-join (inner join)
                 outer: sscan
                            class: lineitem node[1]
                            sargs: term[1] AND term[2] AND term[3] AND term[4]
                            cost:  832902 card 23711
                 inner: iscan
                            class: orders node[0]
                            index: pk_orders_o_orderkey term[0]
                            cost:  4 card 15000000
                 cost:  845116 card 10114
    sort:  1 asc
    cost:  845161 card 10114
```

Sarg terms, **in the order the optimizer assigned them**, with the selectivity it
printed:

| term | predicate | printed sel | true sel | error |
|---|---|---|---|---|
| `term[1]` | `l_commitdate < l_receiptdate` | **0.1** | 0.632301 | **6.32x low** |
| `term[2]` | `l_shipdate < l_commitdate` | **0.1** | 0.487564 | **4.88x low** |
| `term[3]` | `l_receiptdate` range `[1994-01-01, 1995-01-01)` | 0.148988 | 0.151676 | 1.02x |
| `term[4]` | `l_shipmode` IN (`MAIL`,`SHIP`) | 0.265306 | 0.285741 | 1.08x |

That ordering is not cosmetic — it is the physical per-row evaluation order, and it is
the subject of IMP-019 (sections 8-b and 9).

### 4-b. PostgreSQL native (`EXPLAIN ANALYZE, BUFFERS, VERBOSE, SETTINGS`)

```text
Finalize GroupAggregate  (actual time=2528.338..2672.819 rows=2.00 loops=1)
  Buffers: shared hit=1700847 read=533950
  ->  Gather Merge  (actual time=2522.081..2672.808 rows=12.00 loops=1)
        Workers Planned: 5   Workers Launched: 5
        ->  Partial GroupAggregate  (actual time=2511.734..2517.888 rows=2.00 loops=6)
              ->  Sort  (actual time=2505.612..2506.841 rows=51800.50 loops=6)
                    Sort Key: lineitem.l_shipmode
                    Sort Method: quicksort  Memory: 3792kB
                    ->  Nested Loop  (actual time=0.247..2485.509 rows=51800.50 loops=6)
                          Inner Unique: true
                          ->  Parallel Seq Scan on public.lineitem
                                (actual time=0.174..2270.760 rows=51800.50 loops=6)
                                Filter: ((l_shipmode = ANY ('{MAIL,SHIP}')) AND
                                         (l_commitdate < l_receiptdate) AND
                                         (l_shipdate < l_commitdate) AND
                                         (l_receiptdate >= '1994-01-01') AND
                                         (l_receiptdate < '1995-01-01 00:00:00'))
                                Rows Removed by Filter: 9945875
                                Buffers: shared hit=591178 read=533950
                          ->  Index Scan using orders_pkey on public.orders
                                (actual time=0.004..0.004 rows=1.00 loops=310803)
                                Index Cond: (o_orderkey = l_orderkey)
                                Index Searches: 310803
                                Buffers: shared hit=1109634
Planning Time: 1.217 ms
Execution Time: 2673.156 ms
```

`Execution Time` 2673.156 ms is 2.03% above the 2.619923 s headline median — the
`EXPLAIN ANALYZE` instrumentation overhead, which is why this is a separate
non-headline run.

### 4-c. Shape comparison — why `F_plan = 1.0000`

SSOT §16 permits a numeric `F_plan` of 1.0000 only on structural equality or direct
controlled evidence. Q12 has structural equality, operator for operator:

| stage | CUBRID | PostgreSQL | same? |
|---|---|---|---|
| driving access | `sscan` on `lineitem`, all four predicates pushed down as sargs | `Parallel Seq Scan on lineitem` with the same five filter conjuncts | **yes** — full heap scan with pushed-down residual filter |
| join method | `idx-join (inner join)` | `Nested Loop`, `Inner Unique: true` | **yes** — index-nested-loop |
| inner access | `iscan` on `pk_orders_o_orderkey` | `Index Scan using orders_pkey` | **yes** — same index, same unique PK |
| join direction | lineitem outer, orders inner | lineitem outer, orders inner | **yes** |
| grouping | `temp(group by)` with `sort: 1 asc` | `Sort` → `Partial GroupAggregate` → `Finalize GroupAggregate` | **yes** — sort-based grouping on `l_shipmode` |
| ordering | `sort: 1 asc` | `Gather Merge` preserves `Sort Key: l_shipmode` | **yes** |
| execution units | 6 parallel heap-scan workers | 5 workers + leader = 6 | **yes** |

Both engines therefore make the same four plan decisions — scan `lineitem` rather than
use an index, drive the join from `lineitem`, probe `orders` by its primary key, and
group by sorting — and both execute them on six units. There is no plan A/B to anchor
because there is no plan difference to anchor. The two controlled variants in 4-d
change only the unit count and confirm that neither native plan is an artifact of it:
the operator chain is identical at 1 unit and at 6 on both engines.

The two counters that would betray a hidden shape difference agree: index probes 310,803
(PostgreSQL `Index Searches`) against CUBRID's 310,430–310,732 `readkeys` (0.12%
apart — the shortfall is the parallel-worker statistics merge defect of IMP-005, see
5-a), and index-side page fixes 1,109,634 vs 1,105,561 (0.37%).

### 4-d. Controlled unit variants (both through the same gated §12 block)

| variant | switch | wall (median of 3) | U | TWU | CPU |
|---|---|---|---|---|---|
| CUBRID native | — | 4.039000 s | 5.89315 | 5.8296 | 23.8024 |
| CUBRID controlled | `/*+ NO_PARALLEL_SCAN */` | 21.636999 s | 1.00275 | 1.0021 | 21.6965 |
| PostgreSQL native | — | 2.619923 s | 6.49842 | 6.4932 | 17.0254 |
| PostgreSQL controlled | `max_parallel_workers_per_gather=0` | 13.098051 s | 1.10788 | 1.1057 | 14.5111 |

Both variants keep the query text and the operator chain and move only the unit count;
the CUBRID variant is a hint injected by `sed` over the canonical file with join and
predicate text untouched (`variants/q12-cubrid-noparscan.sql`), the PostgreSQL variant
is a `PGOPTIONS` setting with no extra statement in the block. Both were WARM-gated and
load-gated exactly like the contract blocks, at `WINDOW=4` with `LEVEL_TOL` widened to
0.030/0.015 because the serial statements are ~6x longer — recorded here because the
gate parameters differ from the contract blocks'.

Serial `U` lands at 1.00275 (CUBRID) and 1.10788 (PostgreSQL); CUBRID's serial
executor is exactly one unit (86.310 core-s over an 86.672 s block), and PostgreSQL's
excess over 1.0 is its io workers, correctly classified as auxiliary.

## 5. Execution telemetry

### 5-a. Node-level time, CUBRID trace (`SET TRACE ON`, non-headline)

```text
SELECT (time: 4153, fetch: 113, fetch_time: 1, ioread: 19)
  SCAN (table: dba.lineitem), (heap time: 4152, fetch: 44, ioread: 12, readrows: 0, rows: 0)
       (parallel workers: 6, heap time: 3987..4152, readrows: 9938887..10011920,
        rows: 9938887..10011920, gather: mergeable list)
    SCAN (index: dba.orders.pk_orders_o_orderkey), (btree time: 402, fetch: 1105561,
          ioread: 117883, readkeys: 310430, filteredkeys: 310430, rows: 310430)
          (lookup time: 193, rows: 310430)
  GROUPBY (time: 0, hash: partial, sort: true, page: 0, ioread: 0, rows: 2)
```

Traced statement 4,153 ms, 2.82% above the headline median.

**Three of these numbers are wrong and the report does not use them.** `SELECT fetch:
113`, `SCAN … fetch: 44`, `readrows: 0` and `rows: 0` are main-thread-only values: the
same statement's `statdump Num_data_page_fetches` delta is **1,788,621**, so the SELECT
node under-reports page fixes by **15,829x**, and it reports zero rows read for a scan
that read 59,986,052. The per-worker range line is the only place the real scan figures
appear, and it is a *range*, not a total. That is IMP-005, and Q12 is its largest
instance. The same statement re-run with `/*+ NO_PARALLEL_SCAN */` reports every field
correctly (`SELECT (fetch: 2608801, ioread: 417881)` against a statdump delta of
2,608,803 — two fixes apart). The index-scan sub-node's counters *are* aggregated across
workers and are used.

### 5-b. Node-level time, PostgreSQL

`Execution Time` 2673.156 ms. Node-level: `Parallel Seq Scan` 2270.760 ms of the
2485.509 ms nested loop (91.4%), the loop itself adding 214.7 ms of index probing, then
`Sort` 20.3 ms, `Partial GroupAggregate` 11.0 ms, `Gather Merge` 154.9 ms to the final
2672.819 ms. The scan dominates on both engines, which is expected when 99.48% of
59,986,052 rows are rejected by the filter.

### 5-c. CPU accounting (SSOT §15, median-U telemetry run per configuration)

| | CUBRID | PostgreSQL |
|---|---|---|
| `executor_cpu` (core-s / 4-statement block) | 93.230 | 60.460 |
| `auxiliary_query_cpu` (core-s / block) | 0.200 | 8.410 |
| `total_query_cpu` (core-s / block) | **93.430** | **68.870** |
| block wall `t_block` | 15.8540 s | 10.5980 s |
| `U` = CPU/wall | **5.89315** | **6.49842** |
| TWU (actual timestamp deltas) | 5.8296 (−1.08% vs U) | 6.4932 (−0.08%) |
| max simultaneous active units | 6.4040 | 7.7605 |
| serial tail | 0.113 s | 0.235 s |
| `U` reproducibility over 3 runs | 5.89047 / 5.89315 / 5.89414 (**0.06%**) | 6.40527 / 6.49842 / 6.51819 (1.76%) |
| **per-statement total query CPU** (`U × median`) | **23.8024** | **17.0254** |

Process classification: CUBRID's executor CPU is the query threads inside `cub_server`
and its auxiliary is `csql` parse/plan/result work (0.200 core-s, 0.2%); PostgreSQL's
executor is the leader backend plus its five parallel workers and its auxiliary is the
io workers plus `psql` (8.410 core-s, **12.2%** of its total). That asymmetry is real
and is why `total_query_cpu` — not executor CPU — is the card's numerator: with
`io_method=worker`, PostgreSQL performs its physical reads in separate processes, and
charging only the executor would silently give it a 12.2% discount. Nothing is left in
`unattributed_background`.

Planned workers: CUBRID 6 (auto-degree, capped by `parallelism=6`), PostgreSQL 5.
Launched: CUBRID 6, PostgreSQL 5 (`Workers Launched: 5`, plus a participating leader).
Neither number is inferred from settings — both are read from the engines' own output.

`perf stat` cross-check over a 60 s window on a verified PID set:

| | CUBRID | PostgreSQL |
|---|---|---|
| cycles | 958,363,615,553 | 966,942,251,329 |
| instructions | 2,221,352,712,763 | 1,920,040,337,314 |
| **IPC** | **2.32** | **1.99** |
| CPUs utilized | 5.775 | 5.857 |
| task-clock | 346,533.70 ms | 351,430.86 ms |
| implied CPU per statement | 23.328 core-s (−2.0% vs 23.8024) | 15.345 core-s |
| context switches | 670,076 | 5,155 |

PostgreSQL's 15.345 core-s matches its *executor-only* telemetry figure of 15.115
core-s to 1.5%, not its 17.025 core-s total — exactly as expected, because `perf` was
attached to the postmaster with inherit-on-fork and therefore counts the leader and
every statement's workers but **not** the io workers, which pre-date the attach. The two
independent instruments agree on both engines.

**CUBRID's IPC is higher (2.32 vs 1.99): it is not stalling, it is executing more
instructions.** Per lineitem row scanned: **CUBRID 2,493 instructions, PostgreSQL
1,398** — 1.784x. That single number is the whole of Q12, and section 6 says where the
instructions go.

### 5-d. Buffer, `/proc` I/O, iostat and NUMA (stage 14.7, non-headline)

Per statement over one WARM-established, load-gated 4-statement block:

| | CUBRID | PostgreSQL |
|---|---|---|
| read syscalls (`/proc/<server>/io syscr`) | **722,946.5** | 7,737.5 (postmaster only — see below) |
| bytes read (`rchar`) | **11.029 GiB** | 133.9 MiB (postmaster only) |
| device `read_bytes` | **0** | **0** |
| buffer accesses | 2,237,444 (statdump-derived) | 2,237,444 (`blks_hit` 1,882,342 + `blks_read` 355,102) |

PostgreSQL's `/proc` figures are the **postmaster's** and are *not* comparable: with
`io_method=worker` its reads happen in io worker processes. They are reported here for
completeness and are explicitly not used in any ratio. PostgreSQL's physical reads are
taken from `pg_statio_user_tables` (355,102 per statement in the diagnostic block) and
from `EXPLAIN ANALYZE` (533,950 in the plan run) — the two differ by pool state, and
their *total* access count agrees with CUBRID's to 0.12%, which is the comparison that
matters.

Device `read_bytes` is 0 on both engines in the block: every miss is served by the OS
page cache, so the cost is CPU and memory bandwidth, not storage. NUMA: `cub_server`
8,826 MB private on node0 with 5.48 MB on node1; postmaster 150.88 MB node0. No
cross-node drift over the block; 0 off-cpuset TIDs before and after.

`iostat` during both blocks shows no device read activity, consistent with
`read_bytes = 0`.

### 5-e. Where Q12's physical reads actually go, and the collateral eviction

This is the section the `F_cost` factor is made of. Both engines miss a comparable
number of pages; only one of them misses on the *join's inner relation*.

Direct same-engine A/B, `/proc/<cub_server>/io` and `statdump` bracketed around **one
traced statement** each, differing only in CUBRID's own parallel-scan switch:

| | CUBRID parallel (native) | CUBRID serial (`NO_PARALLEL_SCAN`) |
|---|---|---|
| read syscalls | **613,666** | **418,246** |
| `rchar` | 9.361 GiB | 6.376 GiB |
| device `read_bytes` | 5,607,424 | 0 |
| `statdump Num_data_page_ioreads` | 613,460 | 417,882 |
| `statdump Num_data_page_fetches` | 1,788,621 | 2,608,803 |
| trace `ioread` on the orders index node | **117,883** | 158,081 |

Going parallel adds **195,420 physical reads and 2.985 GiB of page-cache traffic per
statement (+46.7%)**, reproducing IMP-010's Q06 finding on a new query. CUBRID's
heap-scan component of the native figure, 613,666 − 117,883 = 495,783 (722,946 − 117,883
= 605,064 in the headline-regime block), sits within 0.6% of Q06's independently
measured headline-regime figure of 608,510 for the same relation.

**The decisive comparison is the inner side of the join:**

| | CUBRID | PostgreSQL |
|---|---|---|
| index+heap page fixes on `orders` | 1,105,561 | 1,109,634 |
| probes | 310,430–310,732 | 310,803 |
| **physical reads on `orders`** | **100,930 – 117,883** | **0** |

Near-identical work — 0.9963x the fixes — and PostgreSQL takes **zero** physical reads
while CUBRID takes six figures. (The two CUBRID traces give 117,883 and 100,930; the
value is pool-state dependent and both are reported rather than averaged.)

The mechanism is not inferred from the profile, it is read off the source and confirmed
by the switch above. PostgreSQL chooses a **bulk-read ring** for this scan precisely
*because* the relation is large: `heapam.c:397-399` tests
`scan->rs_nblocks > NBuffers / 4` — 1,125,128 > 262,144 — and `heapam.c:410` then takes
`GetAccessStrategy(BAS_BULKREAD)`, a **256 kB ring** (`freelist.c:442-447`) that each
parallel worker builds for itself. The 8,790 MiB scan therefore cycles through ~32
buffers per worker instead of evicting the pool, so the 2,483 MB `orders` relation stays
entirely resident inside the same 8,192 MB budget. CUBRID has no such concept: a page
the heap scan has finished with reaches `pgbuf_unlatch_void_zone_bcb`
(`page_buffer.c:6845`) and is unconditionally inserted into an LRU list — the top of the
thread's private list at `:6907`/`:6915`, its middle at `:6924`, or the middle of a
round-robin shared list at `:6933` — with **no strategy parameter anywhere in the fix
path** to say "this page is streaming, reuse it immediately". A grep of
`page_buffer.c`, `heap_file.c` and `px_scan.cpp` for `bulk.?read`, `scan_resist`,
`ring buffer` and `BAS_BULK` returns nothing.

**Bounding it honestly:** the entire kernel page-cache band this produces is 2.4326
core-s on CUBRID against PostgreSQL's comparable 1.8966 core-s, so only **+0.5360
core-s — 7.9% of Q12's 6.7771 core-s CPU excess — is addressable here.** On Q12 this
mechanism is real, directly proved, and *not* the dominant term. Section 6 finds the
dominant term somewhere else entirely.

## 6. Profile

Non-headline. `perf record` attached to a verified PID set (never all-CPU), 60 s window,
30 repeats in one connection per engine, both pre-warmed through
`warm_establish.py` and load-gated. **CUBRID 333,064 samples, PostgreSQL 110,097
samples, `0` unknown-symbol lines on both.** Self-% is converted to core-seconds with
each configuration's measured total query CPU from the card.

### 6-a. CUBRID resolved-symbol bands (89.38% banded, **empty unbanded remainder**)

| band | self % | core-s | top symbols |
|---|---|---|---|
| **A. per-row attribute materialisation into DB_VALUEs** | **34.41%** | **8.1904** | `heap_attrinfo_read_dbvalues` 21.64, `mr_readval_char_internal` 2.52, `or_header_size` 2.31, `mr_data_readval_date` 1.75, `or_mvcc_get_header` 1.70, `or_header_size@plt` 1.04, `or_mvcc_get_repid_and_flags` 0.95, `tp_domain_disk_size` 0.91, `db_value_put_encoded_date` 0.59, `mr_data_readval_char` 0.54, `or_rep_id` 0.46 |
| C. predicate evaluation (generic DB_VALUE comparator) | 19.07% | 4.5391 | `eval_pred` 8.46, `tp_value_compare_with_error` 5.07, `eval_value_rel_cmp` 2.90, `eval_data_filter` 1.63, `mr_cmpval_date` 1.01 |
| D. kernel page-cache copy on the query thread (pread) | 10.22% | 2.4326 | `rep_movs_alternative` 8.45, `filemap_get_read_batch` 1.12, `filemap_read` 0.65 |
| F. heap page/slot walk | 9.83% | 2.3398 | `heap_next_1page` 3.50, `heap_scan_get_visible_version` 1.74, `parallel_scan::slot_iterator::next_qualified_slot_with_peek` 1.47, `spage_*` 3.12 |
| **B. DB_VALUE lifecycle (init/clear/type dispatch)** | **6.31%** | **1.5019** | `pr_clear_value` 3.71, `db_value_domain_init` 0.92, `pr_type_from_id` 0.74, `pr_type_from_id@plt` 0.56, `pr_clear_value@plt` 0.38 |
| E. buffer manager fix/unfix + LRU surgery + victim search | 4.15% | 0.9878 | `pgbuf_fix_release` 1.06, `pgbuf_unlatch_void_zone_bcb` 0.98, `pgbuf_unfix` 0.62, `pgbuf_get_victim*` 1.00 |
| I. userspace memmove/memcmp | 3.56% | 0.8474 | `__memmove_evex_unaligned_erms` 3.56 |
| H. mutex / synchronisation | 1.49% | 0.3547 | `__pthread_mutex_lock` 1.04, `__pthread_mutex_unlock_usercnt` 0.45 |
| G. B-tree descent | 0.34% | 0.0809 | `btree_search_nonleaf_page` 0.34 |

### 6-b. PostgreSQL resolved-symbol bands (88.74% banded, **empty unbanded remainder**)

| band | self % | core-s | top symbols |
|---|---|---|---|
| **C. predicate evaluation (compiled ExprEvalStep program)** | **29.19%** | **4.9697** | `bpchareq` 12.47, `ExecEvalScalarArrayOp` 7.91, `ExecInterpExpr` 6.62, `pg_newlocale_from_collation` 1.39, `ArrayGetNItemsSafe` 0.80 |
| **A. per-row attribute materialisation (tuple deform)** | **28.81%** | **4.9050** | `tts_buffer_heap_getsomeattrs` 26.61, `ExecStoreBufferHeapTuple` 0.98, `pg_detoast_datum_packed` 0.82, `pg_detoast_datum` 0.40 |
| D. kernel page-cache / mm (fault-in of the mmap DSM + page cache) | 11.14% | 1.8966 | `next_uptodate_folio` 4.37, `folio_remove_rmap_ptes` 1.43, `filemap_map_pages` 1.30, `_compound_head` 1.22, `folios_put_refs` 1.09, `zap_present_ptes` 0.74 |
| F. heap page/slot walk | 9.42% | 1.6038 | `ExecSeqScanWithQual` 3.52, `heapgettup_pagemode` 2.44, `heap_page_prune_opt` 1.54, `heap_getnextslot` 1.20 |
| E. buffer manager pin/unpin + hash lookup + lwlock | 5.60% | 0.9534 | `hash_search_with_hash_value` 2.70, `LWLockAttemptLock` 1.60, `PinBuffer` 0.96 |
| I. userspace memmove/memcmp | 2.99% | 0.5091 | `__memcmp_evex_movbe` 2.99 |
| G. B-tree descent | 1.12% | 0.1907 | `_bt_compare` 1.12 |
| **B. DB_VALUE lifecycle** | **0.47%** | **0.0800** | `MemoryContextReset` 0.47 — **no counterpart exists**; PostgreSQL deforms into flat Datum/isnull arrays with no per-value type object |

### 6-c. Band-by-band, in absolute core-seconds

| band | CUBRID | PostgreSQL | delta | ratio |
|---|---|---|---|---|
| **A. attribute materialisation** | 8.1904 | 4.9050 | **+3.2854** | 1.670x |
| **B. value lifecycle** | 1.5019 | 0.0800 | **+1.4219** | 18.770x |
| F. heap page/slot walk | 2.3398 | 1.6038 | +0.7360 | 1.459x |
| D. kernel page-cache / mm | 2.4326 | 1.8966 | +0.5360 | 1.283x |
| H. mutex | 0.3547 | 0.0000 | +0.3547 | n/a |
| I. memmove/memcmp | 0.8474 | 0.5091 | +0.3383 | 1.665x |
| E. buffer manager | 0.9878 | 0.9534 | +0.0344 | 1.036x |
| G. B-tree descent | 0.0809 | 0.1907 | **−0.1098** | 0.424x |
| **C. predicate evaluation** | 4.5391 | 4.9697 | **−0.4306** | **0.913x** |
| **SUM (banded)** | 21.2746 | 15.1083 | +6.1663 | |
| total query CPU | 23.8024 | 17.0254 | **+6.7771** | |

Bands A + B are **+4.7073 core-s = 69.5% of the entire CPU excess.** The banded sum
accounts for 91.0% of the excess; the 0.6108 core-s remainder is the unbanded tail
(10.62% of CUBRID's profile, 11.26% of PostgreSQL's), which is symbol-level dust with no
single entry above 0.3%.

**Two negative deltas matter as much as the positive ones.** CUBRID's predicate
evaluation is *cheaper in absolute core-seconds* than PostgreSQL's, and its B-tree
descent is 0.424x. Q12 does not lose on comparing values or on probing an index. It
loses on getting the values out of the page in the first place.

## 7. Source contrast

| Item | CUBRID `file:line` | PostgreSQL `file:line` | Difference | Class |
|---|---|---|---|---|
| Per-row attribute materialisation | `src/storage/heap_file.c:10464 heap_attrinfo_read_dbvalues()`; `:10256 heap_attrvalue_transform_to_dbvalue()`; `:10219/:10191 heap_attrvalue_point_variable()/point_fixed()` | `src/backend/executor/execTuples.c:751 tts_buffer_heap_getsomeattrs()` → `:1017 slot_deform_heap_tuple()` | CUBRID builds a fully typed `DB_VALUE` per attribute per row; PostgreSQL writes a raw `Datum` into a flat array and, for a run of fixed-width attributes, advances by the cached `attcacheoff` instead of re-deriving each offset. Measured **27.31 ns vs 5.45 ns per attribute materialised (5.01x)** — while CUBRID materialises 5 attributes per row and PostgreSQL 15 | same stage, lower measured cost |
| Per-row record header decode | `src/storage/object_representation.h or_header_size()` (2.31% + 1.04% via PLT), `or_mvcc_get_header()` (1.70%), `or_mvcc_get_repid_and_flags()` (0.95%), `or_rep_id()` (0.46%) | folded into `slot_deform_heap_tuple()`; `src/include/access/htup_details.h` `HeapTupleHeaderGetNatts`/`att_addlength_pointer` are inlined macros | CUBRID re-decodes the MVCC header and representation id per row through non-inlined calls; PostgreSQL's equivalents are inlined into the deform loop and never appear as separate profile symbols | structural absence (of inlining) |
| Per-attribute domain/size resolution | `src/object/object_domain.c tp_domain_disk_size()` (0.91%), `src/object/object_primitive.c pr_type_from_id()` (0.74% + 0.56% via PLT) | `src/backend/executor/execExpr.c:3057 ExecComputeSlotInfo()` computes the attribute count **once** per plan node | CUBRID resolves each attribute's domain and disk size per row; PostgreSQL resolves the deform extent once at plan time | same stage, lower measured cost |
| Per-value teardown | `src/object/object_primitive.c pr_clear_value()` (3.71% + 0.38% via PLT), `db_value_domain_init()` (0.92%) | none — no per-value object is constructed | **1.5019 core-s against 0.0800 core-s (18.77x).** PostgreSQL has no per-value lifecycle to pay for | **structural absence** |
| Sarg evaluation order | `src/optimizer/query_planner.c:10520-10523` — the `PC_ATTR`/`PC_ATTR` arm of `qo_comp_selectivity()` is an empty `/* TODO: add histogram selectivity */`, falling to `:10514`/`:10624` `DEFAULT_COMP_SELECTIVITY`, defined `src/optimizer/query_planner.h:118` as `0.1`; `src/optimizer/query_graph.c:6183-6201 qo_discover_edges()` then sorts sarg terms "selectivity asc" | `src/backend/optimizer/plan/createplan.c order_qual_clauses()` sorts quals by **estimated cost only**, stable for equal cost; `src/include/utils/selfuncs.h:37 DEFAULT_INEQ_SEL 0.3333333333333333` feeds cardinality estimation but never qual order | CUBRID lets a placeholder selectivity decide the physical evaluation order, so the two least selective predicates run first. **106,195,014 vs 91,506,768 predicate-term evaluations** | **structural absence** (of an attr-vs-attr estimate) |
| Scan-resistant buffer strategy | `src/storage/page_buffer.c:6845 pgbuf_unlatch_void_zone_bcb()` → `:6907`/`:6915` private-list top, `:6924` private-list middle, `:6933` shared-list middle. No strategy parameter exists on the fix path (`pgbuf_fix`/`pgbuf_ordered_fix` reached via `src/storage/heap_file.c:7517 heap_scan_pb_latch_and_fetch()`). Searched `page_buffer.c`, `heap_file.c`, `px_scan.cpp` for `bulk.?read`, `scan_resist`, `ring buffer`, `BAS_BULK` — **no match** | `src/backend/access/heap/heapam.c:397-399` `scan->rs_nblocks > NBuffers / 4` → `:410 GetAccessStrategy(BAS_BULKREAD)`; `src/backend/storage/buffer/freelist.c:442-447` 256 kB ring; `:623 GetBufferFromRing()`, `:702 AddBufferToRing()`, `:752 StrategyRejectBuffer()`; `src/backend/access/table/tableam.c:423` applies the same size test to the parallel scan | PostgreSQL confines a large scan to a per-worker 256 kB ring, so it cannot evict the join's inner relation; CUBRID's scan pages enter the shared LRU and do. **`orders` physical reads: 100,930–117,883 vs 0** | **structural absence** |
| Physical read submission | `src/storage/page_buffer.c pgbuf_claim_bcb_for_fix()` → `fileio_read()` → `__libc_pread64`, on the query thread; 613,666 single-page 16 KiB preads per statement | `io_method=worker` — reads performed by separate io worker processes (8.410 core-s of `auxiliary_query_cpu` per block, excluded from executor CPU) | CUBRID pays page-cache copy inside the executor's critical path (`rep_movs_alternative` 8.45%); PostgreSQL pays it off the critical path | same stage, different placement |
| Parallel scan degree | `src/query/parallel/px_scan/px_scan.cpp:416` `compute_parallel_degree(SCAN, num_data_pages, hint)`; `src/query/parallel/px_parallel.cpp:36-175` `floor(log2(pages/2048)) + 2` capped by `parallelism` | `src/backend/optimizer/path/allpaths.c:876 create_plain_partial_paths()` → `:4973 compute_parallel_worker()`, `1 + floor(log3(pages/min_parallel_table_scan_size))` capped by `max_parallel_workers_per_gather` | Both auto-derive a degree from relation size and cap it; CUBRID decides at execution time in the scan, PostgreSQL at plan time in the optimizer. Both arrive at 6 units here. **Common to both engines** | common to both engines |
| Parallel-worker statistics merge | `src/query/parallel/px_scan/px_scan_trace_handler.cpp:492-500 merge_xasl_tree()`; `src/xasl/xasl_iteration.cpp:87/:205` | `EXPLAIN ANALYZE` reports per-worker and aggregated `Buffers`/`rows` correctly at every node | CUBRID's parallel trace reports main-thread-only `fetch`/`readrows` at the SELECT and SCAN nodes (113 against a measured 1,788,621) | structural absence |

## 8. Causal decomposition details

### 8-a. What actually happens, in order

Both engines execute the identical shape: scan all 59,986,052 `lineitem` rows, apply
four predicates that reject 99.48% of them, probe `orders` by primary key for each of
the 310,803 survivors, and sort-group the result into 2 rows on 6 units.

Per statement, per engine:

| | CUBRID | PostgreSQL |
|---|---|---|
| rows scanned | 59,986,052 | 59,986,052 |
| attributes materialised per row | 5 | 15 |
| attributes materialised total | 299,930,260 | 899,790,780 |
| predicate-term evaluations | 106,195,014 | 91,506,768 |
| survivors → index probes | 310,803 | 310,803 |
| index+heap page fixes | 1,105,561 | 1,109,634 |
| total page fixes | 1,788,621 | 2,234,797 |
| physical reads | 613,666 (722,946 in the block regime) | 533,950 |
| — of them on `orders` | **100,930 – 117,883** | **0** |
| instructions per row | **2,493** | **1,398** |
| IPC | 2.32 | 1.99 |
| total query CPU | 23.8024 core-s | 17.0254 core-s |

### 8-b. Where the 1.5416x actually goes

`R_wall` 1.541648x = `F_units` 1.102707x × `F_cpu` 1.398058x. The units factor is
small and understood: both engines run 6 units, and PostgreSQL simply keeps them
slightly busier (U 6.49842 vs 5.89315) because 12.2% of its CPU is io workers running
*concurrently* with the executor, whereas CUBRID's reads are synchronous on the query
threads and therefore serialise against its own scan.

The CPU factor, +6.7771 core-s, resolves by measured band:

| contributor | core-s | share of excess | candidate | evidence |
|---|---|---|---|---|
| per-row attribute materialisation (band A) | +3.2854 | **48.5%** | IMP-020 | profile attribution |
| per-value lifecycle (band B) | +1.4219 | **21.0%** | IMP-020 | profile attribution |
| heap page/slot walk (band F) | +0.7360 | 10.9% | — | profile attribution |
| kernel page-cache copy (band D) | +0.5360 | 7.9% | IMP-010 / IMP-007 | direct A/B + profile |
| mutex (band H) | +0.3547 | 5.2% | — | profile attribution |
| memmove/memcmp (band I) | +0.3383 | 5.0% | IMP-020 (same per-row path) | profile attribution |
| buffer manager (band E) | +0.0344 | 0.5% | IMP-013 | profile attribution |
| B-tree descent (band G) | −0.1098 | −1.6% | — | CUBRID cheaper |
| predicate evaluation (band C) | −0.4306 | −6.4% | — | **CUBRID cheaper** |
| unbanded tail | +0.6108 | 9.0% | — | residual |

Inside the negative band C sits a *positive* effect that a reordering fix would
recover: CUBRID performs 33,243,739 excess predicate-term evaluations because of the
sarg ordering defect. Priced at the per-term cost measured in the same band
(17.44% = 4.1512 core-s over 106,195,014 evaluations = 39.1 ns; the per-row entry point
`eval_data_filter` is excluded because reordering does not change how many rows enter
the filter), that is **1.2998 core-s = 19.2% of the excess** — recoverable *even though
the band as a whole is already cheaper than PostgreSQL's*, because it is a count
problem, not a unit-cost problem:

| order | rows reaching each term | term evaluations |
|---|---|---|
| CUBRID actual (`0.1`-driven) | 59,986,052 → 37,929,348 → 7,190,268 → 1,089,346 | **106,195,014** |
| PostgreSQL actual (cost-ordered) | 59,986,052 → 17,140,455 → 10,836,921 → 2,054,567 → 1,488,773 | 91,506,768 |
| true-selectivity-optimal | 59,986,052 → 9,098,427 → 2,600,101 → 1,266,695 | **72,951,275** |

CUBRID performs **1.1605x** PostgreSQL's evaluations with **one fewer term**, and
**+45.57%** over the order it would itself choose given a correct estimate. Every
survivor count is an independent ground-truth `count(*)` that both engines answer
identically.

### 8-c. Explanations considered and REJECTED, with the number that rejected each

1. **"CUBRID has no intra-query parallelism for this plan, PostgreSQL does."**
   REJECTED. `q12-trace-cubrid.out` reports `parallel workers: 6` with per-worker
   `readrows` 9,938,887…10,011,920. Both engines run 6 units. The plan text does not
   annotate it because the degree is an execution-time decision
   (`px_scan.cpp:416`), not a plan property.
2. **"CUBRID's parallelism is weaker / scales worse."** REJECTED by a same-engine A/B
   on each engine's own switch: CUBRID **5.3570x** speedup for **1.0971x** CPU,
   PostgreSQL **4.9994x** for **1.1733x**. CUBRID's parallel implementation is the
   better one on this query by both measures, and its parallel efficiency is 91.9% of
   TWU against PostgreSQL's 77.0%.
3. **"The gap is created by parallel execution."** REJECTED: the gap is *larger*
   serially. Serial 21.636999/13.098051 = **1.65193x** versus parallel **1.541648x**.
   Parallelism narrows Q12's gap by 6.7%.
4. **"CUBRID's generic DB_VALUE comparator (IMP-008) is what loses Q12."** REJECTED by
   the profile: band C is 4.5391 core-s on CUBRID against 4.9697 core-s on PostgreSQL
   — **0.913x, CUBRID cheaper** — at 39.1 ns per term evaluation against 54.3 ns. On
   Q04 the same band was 4.24x *against* CUBRID; the difference is the data type
   (Q04's NUMERIC/DATE coercion prologue versus Q12's DATE-vs-DATE and
   CHAR(10)-vs-constant). This is recorded as a Q12 counter-example on IMP-008.
5. **"The 117,883 physical reads on `orders` are the dominant cost."** REJECTED as
   *dominant*, retained as real. The entire kernel page-cache band is 2.4326 core-s and
   only the **+0.5360 core-s** delta over PostgreSQL is addressable — 7.9% of the
   excess, against bands A+B's 69.5%.
6. **"CUBRID is memory-stalled on the larger page-cache traffic."** REJECTED by
   `perf stat`: CUBRID's IPC is **2.32** against PostgreSQL's **1.99**. It is not
   stalling; it is retiring 1.784x more instructions per row (2,493 vs 1,398).
7. **"The 16 KiB vs 8 KiB page size explains the CPU gap."** REJECTED: the page-size
   difference makes CUBRID fix **fewer** pages (1,788,621 vs 2,234,797, `F_work`
   0.800351x on that event), so it works in CUBRID's favour on the count and cannot
   explain a CPU excess. It is recorded as the reason the page-fix decomposition is the
   *secondary* one.
8. **"CUBRID materialises more attributes per row than PostgreSQL."** REJECTED and
   inverted: CUBRID materialises **5** attributes per row, PostgreSQL **15** (it must
   deform up to `l_shipmode`, attribute 15 of lineitem's 16). CUBRID spends more CPU
   doing three times less of it — 27.31 ns vs 5.45 ns per attribute.
9. **"`statdump`'s zero page-counter delta over the diagnostic block means the counters
   are broken."** NOT CONCLUDED. The block-bracketed counters did show a zero delta
   across 24 statements while a single *traced* statement moved
   `Num_data_page_fetches` by 1,788,621. The likely gate is
   `perfmon_is_perf_tracking_and_active()`, but this campaign did not run the
   controlled experiment that would prove it, so it is recorded as an observation on
   IMP-005 and those three files are marked EXCLUDED from every calculation in the
   manifest. Q12 uses the trace-bracketed statdump deltas and `/proc/<cub_server>/io`
   instead, which agree with each other to 0.03%.

### 8-d. What is left after IMP-020 and IMP-019, and in what order

IMP-020's realistic first target (band B in full, 1.5019 core-s, plus the per-row header
and domain re-decode inside band A, 7.47% = 1.7780 core-s) is **3.2799 core-s = 13.8% of
CUBRID's query CPU**, about **0.557 s** of the 4.039 s median at the measured U. Adding
IMP-019's 1.2998 core-s — disjoint by band, so the two add — gives 4.5797 core-s, about
0.778 s, which would bring Q12 to roughly 3.26 s against PostgreSQL's 2.62 s. Neither
candidate closes the gap alone, and no combination measured here closes it entirely: the
residual would still be bands F, H and I plus the irreducible part of A.

Effects are **not** summed across IMP-010, IMP-007 and IMP-002: all three name the same
2.4326 core-s kernel band from different angles, and the band's addressable part is
claimed exactly once, by IMP-010.

## 9. Improvements

Ledger synced and searched before allocation; the full search is recorded in
`q12-registry-dedup.txt` (four searches by title, by both source locations and by root
cause). **Two new IDs allocated; five existing root causes reused with new Q12
relations.** `next_id` advanced `IMP-019` → `IMP-021`.

### New candidates

**IMP-020 (P0, expression/type + storage, difficulty high) — ranked first.**
Per-row scan output is materialised into fully typed `DB_VALUE`s: for every row the
heap scan re-reads the MVCC/representation header, re-resolves each attribute's domain
and disk size, calls a type-specific `mr_data_readval_*` to build a `DB_VALUE`, and
afterwards tears each one down with `pr_clear_value` — where PostgreSQL deforms the
same tuple into a flat `Datum`/`isnull` array using cached attribute offsets, with no
per-value type object, no per-value domain init and no per-value teardown at all.
Mechanism per row: CUBRID `heap_file.c:10464` → `:10256` → `mr_data_readval_date`/
`mr_readval_char_internal` → `pr_clear_value`; PostgreSQL `execTuples.c:751` → `:1017`
with the extent computed once by `execExpr.c:3057`, values then read as raw Datums at
`execExprInterp.c:719`. Measured **+3.2854 core-s (band A) + 1.4219 core-s (band B) =
+4.7073 core-s, 69.5% of Q12's CPU excess**; 27.31 ns vs 5.45 ns per attribute (5.01x)
while materialising 3x fewer attributes. Evidence type: profile attribution
(333,064 samples, 0 unresolved, empty unbanded remainder). Ranked first on magnitude
(69.5% vs IMP-019's 19.2% and IMP-010's 7.9%) and on denominator quality (attributes
materialised is a ground-truth count). Upstream precedent for the direction:
`a2f738e75 [CBRD-26924]` (#7281) and `b334446d6 [CBRD-27041]` (#7441, **in the pinned
build**) both cut per-row heap-scan overhead by hoisting work out of the row loop; no
prior PR caches per-attribute domain/disk-size resolution across rows or reuses
`DB_VALUE` containers. Predecessor **IMP-008**, which Q12 re-scopes (see below).

**IMP-019 (P1, optimizer + expression/type, difficulty low) — ranked second.**
The selectivity of a comparison between two *attributes* is an unconditional hardcoded
`DEFAULT_COMP_SELECTIVITY = 0.1` — the attr-vs-attr arm of `qo_comp_selectivity()` is
an explicit empty `/* TODO: add histogram selectivity */` at
`query_planner.c:10520-10523` — and because `qo_discover_edges()`
(`query_graph.c:6183-6201`) then orders sarg terms by *ascending estimated
selectivity*, every column-vs-column comparison is evaluated before genuinely selective
constant predicates. PostgreSQL cannot have this failure: `order_qual_clauses()` sorts
quals by estimated **cost** only, so a wrong selectivity cannot invert its filter order.
Measured **33,243,739 excess predicate-term evaluations per statement (+45.57%)**,
priced at the measured 39.1 ns/evaluation = **1.2998 core-s, 19.2% of the CPU excess**.
Evidence type: projection (measured counts × measured unit cost) — CUBRID offers no
switch that changes sarg order without also changing the estimate, so the direct A/B
requires the patch and is recorded as validation criterion (3). Upstream precedent is
direct: `10d0aa0e7 [CBRD-26746]` (#7508) replaced a constant default with a
histogram-derived estimate for the attr-vs-attr **equality** case; this is the same
change for the **inequality** case that #7508 left as the TODO.

### Existing candidates given a Q12 relation and Q12 evidence (no new ID)

- **IMP-010** (P1) — Q12 extends it from **self**-eviction to **collateral** eviction:
  Q06 measured the parallel scan re-reading the relation it was scanning; Q12 measures
  it evicting the inner side of its own index-nested-loop join. Direct A/B: parallel
  613,666 reads / 9.361 GiB vs serial 418,246 / 6.376 GiB (**+46.7%**), and
  `orders` physical reads **100,930–117,883 vs PostgreSQL's 0** on a 0.9963x-identical
  fix count. Addressable: +0.5360 core-s (7.9%).
- **IMP-008** (P0) — Q12 is a **counter-example** to its root cause and the reason
  IMP-020 exists: its comparator band is 0.913x, i.e. CUBRID *cheaper*, while doing
  1.1605x more evaluations. Its Q04/Q06/Q10 evidence and P0 priority are unchanged, but
  its effect must not be assumed to generalise to every sarg-bound query.
- **IMP-007** (P1) — 613,666 synchronous single-page 16 KiB preads per statement on the
  six query threads, 2.4326 core-s of kernel band inside the executor's critical path,
  against PostgreSQL performing its reads in separate io worker processes (8.410 core-s
  of auxiliary CPU). Q12 is the cleanest instance so far: comparable miss counts, only
  one engine paying inside the executor.
- **IMP-005** (P2) — largest instance yet: the native trace reports `SELECT fetch: 113`
  and `readrows: 0` against a measured 1,788,621 fixes and 59,986,052 rows — a
  **15,829x** under-report — while the `NO_PARALLEL_SCAN` run of the same statement is
  exact to 2 fixes. Plus the new `statdump` observation recorded in 8-c(9).
- **IMP-002** (P1) — Q12 genuinely satisfies its "working set exceeds the pool" premise
  (1.30x), and its serial control is **1.35x** the arithmetic floor where Q06's was
  1.0018x, because Q12 interleaves 310,803 random index probes with the sequential
  scan. No new effect size claimed; the addressable CPU is IMP-010's and is not
  double-counted.

## 10. Evidence index

Format: `claim → raw file → formula → evidence type → SHA-256`. All paths relative to
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q12/`.

| # | Claim | Raw file | Formula / locator | Evidence type | SHA-256 |
|---|---|---|---|---|---|
| 1 | SSOT pin verified, no drift, 8FK/8-btree, contract params, 0 off-cpuset | `preflight-Q12.txt` | `ssot_drift=NONE`; `TOTAL engine tids=34 off_cpuset=0` | preflight capture | `f27e795a…` |
| 2 | `result-equivalent-at-SF10`, 2 rows ordered | `q12-correctness.json` | `result.status` | correctness gate | `222f8acc…` |
| 3 | CUBRID headline 4.039000 s (4.052/4.039/4.015) | `Q12-cubrid-headline-block1.json` | `median_s` of `measured_times_s` | headline block | `23f12647…` |
| 4 | PostgreSQL headline 2.619923 s (2.633592/2.612043/2.619923) | `Q12-postgresql-headline-block1.json` | `median_s` | headline block | `3035b17a…` |
| 5 | `R_wall` = 1.541648x | `Q12-causal-card.json` | `4.039000 / 2.619923` | derived | `10f93662…` |
| 6 | CUBRID WARM CONVERGED, trend +0.2739% | `Q12-cubrid-warm-block1.json` | `converged`, `verdict` | warm gate | `d4e48474…` |
| 7 | PostgreSQL WARM CONVERGED, trend −0.0285% | `Q12-postgresql-warm-block1.json` | `converged`, `verdict` | warm gate | `cbd0b262…` |
| 8 | Gate parameters derived from Q12's own probes | `q12-warm-gate-params.txt`, `q12-convergence-cubrid.json`, `q12-convergence-pg.json` | steady 4.019000 / 2.600109, trends −0.4948% / +0.2158% | warm convergence probe | `8b02dd80…`, `60ee01a8…`, `ca7fbf72…` |
| 9 | CUBRID plan: sscan + idx-join + temp(group by), sargs ordered 0.1/0.1/0.148988/0.265306 | `q12-plan-est-cubrid.out` | `Query plan:` block, `Join graph terms` | estimated plan | `c1626aff…` |
| 10 | PostgreSQL plan: Parallel Seq Scan + Nested Loop + Sort + GroupAggregate, 5 workers | `q12-plan-est-pg.out` | `EXPLAIN (COSTS, VERBOSE, SETTINGS)` | estimated plan | `51898ca6…` |
| 11 | CUBRID runs **6 parallel workers**; index `fetch 1105561`, `ioread 117883` | `q12-trace-cubrid.out` | `parallel workers: 6`; SCAN(index) counters | actual plan trace | `10854331…` |
| 12 | PostgreSQL `orders_pkey` **read=0**, `hit=1109634`, 310,803 searches | `q12-plan-act-pg.out` | Index Scan node `Buffers` | actual plan | `352eb7e1…` |
| 13 | `F_work` = 1.0000: 59,986,052 rows both engines; 310,803 survivors | `q12-groundtruth-cubrid.out`, `q12-groundtruth-pg.out` | `G0_lineitem_total`, `G5`, `G6` | direct A/B (ground truth) | `1952fb09…`, `ffd31d3f…` |
| 14 | `U_C` = 5.89315, exec 93.230 / aux 0.200 core-s | `Q12-cubrid-headline-telemetry-run1.json` | `utilization.U_core_s_per_wall_s` | telemetry | `8f45fa12…` |
| 15 | `U_P` = 6.49842, exec 60.460 / aux 8.410 core-s | `Q12-postgresql-headline-telemetry-run2.json` | `utilization.U_core_s_per_wall_s` | telemetry | `b30a11f6…` |
| 16 | CUBRID serial 21.636999 s → 5.3570x speedup, 1.0971x CPU | `Q12-cubrid-noparscan-headline.json`, `Q12-cubrid-noparscan-headline-telemetry.json` | `median_s`; `U × median` | direct A/B | `ce136cf0…`, `f1ce2eeb…` |
| 17 | PostgreSQL serial 13.098051 s → 4.9994x speedup, 1.1733x CPU | `Q12-postgresql-noparallel-headline.json`, `Q12-postgresql-noparallel-headline-telemetry.json` | `median_s`; `U × median` | direct A/B | `37f08cb2…`, `3a05877c…` |
| 18 | Parallel adds 195,420 reads / 2.985 GiB per statement; fixes 1,788,621 | `q12-serial-parallel.out`, `q12-serial-serial.out`, `q12-serial-io-parallel-post.txt`, `q12-serial-io-serial-post.txt` | `syscr` and `statdump` deltas across one traced statement each | direct A/B | `be53767a…`, `a5d9e564…`, `f10b0232…`, `7da3293a…` |
| 19 | CUBRID 722,946.5 reads and 11.029 GiB per statement, device `read_bytes` 0 | `Q12-cubrid-buffer-io-diag.json` | `proc_io_per_statement` | buffer/IO diagnostics | `ededa1ee…` |
| 20 | PostgreSQL 2,237,444 buffer accesses per statement | `Q12-postgresql-buffer-io-diag.json` | `pg_statio` pre/post delta ÷ 4 | buffer/IO diagnostics | `ee4f6d5e…` |
| 21 | Predicate evaluations 106,195,014 / 91,506,768 / 72,951,275 | `q12-selectivity-probe-cubrid.out`, `q12-selectivity-probe-pg.out` | Σ rows reaching each term, per order | direct A/B (ground truth) | `71dfc464…`, `e521e59b…` |
| 22 | CUBRID bands A 34.41%, B 6.31%, C 19.07%, D 10.22% | `profile-cubrid-flat.txt`, `q12-profile-bands.txt` | self-% summed per band × 23.8024 core-s | profile attribution | `ae4477f3…`, `12dd9f8f…` |
| 23 | PostgreSQL bands A 28.81%, B 0.47%, C 29.19%, D 11.14% | `profile-pg-flat.txt`, `q12-profile-bands.txt` | self-% summed per band × 17.0254 core-s | profile attribution | `6e20bcd0…`, `12dd9f8f…` |
| 24 | Bands A+B = +4.7073 core-s = 69.5% of the excess | `q12-profile-bands.txt` | band-by-band absolute comparison | profile attribution | `12dd9f8f…` |
| 25 | IPC 2.32 vs 1.99; 2,493 vs 1,398 instructions per row | `perf-stat-cubrid.txt`, `perf-stat-pg.txt` | `instructions ÷ (window ÷ median) ÷ 59,986,052` | profile attribution | `5abb122c…`, `e995da81…` |
| 26 | Card reconstructs with residual +0.000000000%; budget 2.87% | `q12-card-calc.txt`, `Q12-causal-card.json` | `F_plan × F_units × F_cpu` vs `R_wall` | derived | `185467f1…`, `10f93662…` |
| 27 | Registry dedup: 4 searches, 2 new IDs, 5 reuses | `q12-registry-dedup.txt` | search record | provenance | see manifest |
| 28 | Post-block ownership OK, 0 off-cpuset, no orphans, no SSOT drift | `q12-postcheck.txt` | ownership gate + cpuset revalidation | post-block gate | `a05d045e…` |

Full 270-artifact index with byte sizes, creation commands, producing stages and
validity flags: `reports/Q12/raw-manifest.json`. 28 artifacts carry an explicit
invalid/excluded reason (3 unusable `statdump` block captures, 5 sizing-probe files,
12 non-headline blocks 2–3, 8 controlled-variant artifacts); none of them is used in
any calculation.

## 11. Notion sync

Not performed by this session. Per SSOT §21 the GJC/tmux worker session runs on the
remote build host, has no Notion connector, and **must never attempt a Notion write**;
its Notion-adjacent duty ends at committing and pushing this report and manifest to
`origin/main`. An idempotent backfill record (write path 3) has been appended to
`reports/notion_backfill_pending.jsonl` with the idempotency key
`campaign_id + QNN + session_id + report_commit + content_fingerprint`, carrying the
full section-21 content payload. Notion sync is to be performed by the dedicated
reconciler subagent with Notion tool access, reading the pushed commit as source of
truth, and the pending record cleared only after a server-side refetch.

## 12. Completion checklist

| SSOT §26 gate | Status |
|---|---|
| preflight and correctness status recorded | **yes** — §1, §2; `result-equivalent-at-SF10` |
| three valid headline values per completing engine | **yes** — CUBRID 4.052/4.039/4.015, PostgreSQL 2.633592/2.612043/2.619923; all six blocks accepted on attempt 1, all `CLEAN` |
| timeout confirmations if censored | **n/a** — neither engine censored (4.039 s and 2.620 s against a 300 s timeout) |
| plan, execution, profile and source contrast complete | **yes** — §4, §5, §6, §7 |
| causal card has evidence or explicit `UNMEASURED` | **yes** — every factor measured, no `UNMEASURED`; residual +0.000000000% against a 2.87% budget |
| improvement ledger deduplicated and committed | **yes** — `q12-registry-dedup.txt`; IMP-019 + IMP-020 allocated, `next_id` → IMP-021; Q12 relations added to IMP-002/005/007/008/010 |
| Notion relations synced or idempotent backfill durable | **backfill durable** — `reports/notion_backfill_pending.jsonl`, write path 3 only (§11) |
| every claim indexed to raw evidence and checksum | **yes** — §10, 28 indexed claims; 270-artifact manifest with SHA-256 |
| report, manifest and registry committed, pushed, reachable from `origin/main` | **yes** — see `report_commit` in the status block |
| `QUERY_COMPLETE` emitted | **yes** |
| current session removed and absence verified | performed immediately after the push, with both `gjc session status` and `tmux has-session` |

### Stage ledger

| stage | status |
|---|---|
| 14.1 preflight | OK — `preflight-Q12.txt` |
| 14.2 correctness | OK — `result-equivalent-at-SF10` |
| 14.3 estimated plans | OK — both engines, non-executing |
| 14.4/14.5 headline blocks | OK — PostgreSQL first (even QNN), 3 blocks each, all attempt 1 |
| 14.6 actual plans + trace | OK — each preceded by its own WARM establishment |
| 14.7 CPU/thread, `/proc` I/O, iostat, NUMA, buffer | OK — 3 telemetry runs + 1 diagnostic block per engine |
| 14.8 perf cycles/instructions/call-graph | OK — verified PID sets, 0 unresolved symbols |
| 14.9 source `file:line` contrast | OK — 9 rows, both engines |
| 14.10 causal decomposition | OK — residual +0.000000000% |
| 14.11 registry dedup and relations | OK — 2 new, 5 reused |
| 14.12 manifest, report, commit, backfill | OK |
| 14.13 completion checklist + `QUERY_COMPLETE` | OK |
| 14.14 session removal + absence verification | performed after push |

### Invalid / excluded artifacts, preserved as evidence

- `q12-cubrid-statdump-{pre,mid,post}.txt` — zero delta on every `Num_data_page_*`
  counter across 24 statements while a single traced statement moved
  `Num_data_page_fetches` by 1,788,621. Excluded from every calculation; the mechanism
  is recorded as an observation on IMP-005, not as a proven claim.
- `q12-size-*` — 3-repeat sizing probe with no WARM or load gate, used only to choose
  the later stages' statement counts and window sizes.
- Blocks 2 and 3 for both engines — valid measurements, retained as the block-to-block
  stability evidence; the headline is block 1.
- Controlled-variant artifacts (`*-noparscan-*`, `*-noparallel-*`) — never headline
  values; used as the `F_units` cross-check and as IMP-010's Q12 A/B.
