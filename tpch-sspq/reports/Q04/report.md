# TPCH-SSPQ FK campaign — Q04 report

## 3-a. Causal multiplier card

```text
R_wall 1.843301x [wall, median of 3 per engine; PostgreSQL is 1.8433x faster]
= F_plan  1.000000x [plan-shape; structural equality proven node by node, section 4]
× F_units 0.964986x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   1.910185x [total query CPU-seconds]

F_cpu 1.910185x [total query CPU-seconds]
= F_work 0.939713x [plan-node tuple touches: 17,188,713 vs 18,291,452]
× F_cost 2.032732x [total-query CPU-seconds per plan-node tuple touch]
```

**`F_plan` is numeric `1.0000` for Q04 by structural equality, not by an A/B.** Both
optimizers reach the *same* plan without any hint: a parallel full scan of `orders`
under the same date range, then a per-surviving-row probe into the FK B-tree on
`lineitem.l_orderkey` that stops at the first row satisfying
`l_commitdate < l_receiptdate`. The equality is proven per node, not asserted:
**573,671 index searches on both engines** (CUBRID trace `readkeys`, PostgreSQL
`Index Searches` and the `pg_stat_user_indexes.idx_scan` delta), **831,334 vs 832,822
index entries examined** (0.18% apart), and **526,040 output rows** on both. Section 16
permits a numeric `F_plan` on exactly this basis. Counterfactuals confirm both
optimizers chose correctly for their own engine: PostgreSQL forced off nested loop
takes 3.758 s (3.87x worse than its own 0.972 s `EXPLAIN ANALYZE`), and no CUBRID hint
produces a different shape or a better time.

Read in the direction of the loss: at an identical plan, identical work
(`F_work = 0.9397`, and the 6.0% is a node-decomposition artifact — see below) and
identical parallel utilization (`F_units = 0.9650`, 5.40 vs 5.21 CPU-seconds per
wall-second), CUBRID burns **1.9102x the CPU**. The whole gap is per-tuple cost:
**556.5 ns vs 273.8 ns per tuple touch**.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 1.000000x | plan-node shape | n/a (structural equality) | per-node identity, section 4 | `q4-plan-est-cubrid.out`, `q4-plan-act-pg.out`, `q4-trace-cubrid.out`, `q4-idxstat-probe.out` | direct A/B |
| `F_units` | 0.964986x | active execution units | CPU-seconds / wall-second | `U_P/U_C`, `U = CPU_block/Σ(block statement walls)` = 5.21484/5.40406 | `Q04-postgresql-headline-telemetry-run3.json`, `Q04-cubrid-headline-telemetry-run2.json` | profile attribution |
| `F_cpu` | 1.910185x | total query CPU-seconds | per query execution | `CPU_C/CPU_P` = 9.5652/5.0075 | same telemetry JSONs | profile attribution |
| `F_work` | 0.939713x | plan-node tuple touches | tuples | `W_C/W_P` = 17,188,713/18,291,452 | `q4-trace-cubrid.out`, `q4-plan-act-pg.out`, `q4-idxstat-probe.out`, `q4-semijoin-entries.out` | direct A/B |
| `F_cost` | 2.032732x | CPU-seconds per tuple touch | tuple touches | `(CPU_C/W_C)/(CPU_P/W_P)` = 556.5 ns / 273.8 ns | `Q04-causal-card.json` | profile attribution |

**Reconstruction residual = +0.000000%, and that is by construction rather than by
luck — stated plainly because the alternative would be to dress an identity as a
prediction.** `U` is measured on the *same* section 12 block the headline is defined
on (new `harness/headline_telemetry.py`, see section 5), and the median statement's CPU
is attributed as `CPU_stmt = U × t_median`, so `F_units × F_cpu = t_C/t_P` identically.
The substantive claims are therefore not the residual but: (a) the CPU numerator now
comes from the headline regime instead of being imported from a single-statement
regime, which is what closes Q03's carried-forward gap; and (b) the attribution rule's
one assumption — constant utilization across a block's statements — is **tested**
against an independent instrument. Cross-check: single-statement telemetry gives
`U_C` 5.28575/5.30551/5.32111 (median 5.30551, **−1.8%** vs the block `U_C`) and `U_P`
5.35982/5.36725/5.36977 (median 5.36725, **+2.9%** vs the block `U_P`). CUBRID's CPU per
statement is the same in both regimes (9.49–9.50 vs 9.51 core-s) and only its wall
differs; PostgreSQL genuinely spends ~0.3 core-s more per statement on a fresh
connection. **`F_units` therefore carries roughly ±3% of regime uncertainty**, which is
recorded rather than hidden — it does not disturb the conclusion, because `F_units` is
within 3.5% of 1.0 either way and `F_cpu` carries the loss. Had `U` been taken from the
single-statement telemetry as in Q01–Q03, the card would reconstruct to **−2.0065%**.

`F_work`'s 6.0% deficit is a node-counting artifact, not a work difference, and the
sensitivity is given rather than argued away: CUBRID reports one `temp(group by)` node
where PostgreSQL reports `Sort` + `Partial GroupAggregate` + `Gather Merge` +
`Finalize GroupAggregate`, and PostgreSQL additionally exposes the semi-join as its own
node where CUBRID folds it into a scan sarg. Collapsing each engine's post-join
aggregation chain to a single node gives `W_C = 17,188,708`, `W_P = 17,765,352`,
**`F_work = 0.967541`** and `F_cost = 1.974`. At the data-access layer, where all the
cost actually is, the two engines agree to 0.18%. Both figures are in
`Q04-causal-card.json`; the card above uses the literal section 16 definition.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q04 |
| SSOT commit | `5912f0654f1e98beea154c7003d372f52a24a9c4` |
| SSOT blob | `6ce8e04da201fd3f5e1b2d3dae42db1534d5b51a` |
| GJC session ID | `gajae_code_ms7lo36d_6uez896z` |
| Raw dir | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q04` |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` |
| CUBRID DB / port | `tpch_sf10_q1` / 1523 (`cub_server` pid 1445555, `cub_master` pid 1433697) |
| PostgreSQL PGDATA / port | `/home/cubrid/pg/pgdata-tpch-sspq` / 5442 (postmaster pid 1433696) |

Both running binaries hash-match the frozen `reports/bootstrap/build-manifest.json`.
Ownership gates (section 10) classified **OK** before and after every measurement
block; the post-block gate (`q4-postcheck.txt`) records 0 orphan `csql`, 0 orphan
`psql`, 0 parallel workers and 0 client backends remaining, satisfying section 13's
"no next run while orphan work remains", and the CUBRID pool is conserved at exactly
524,288 pages (8 GiB / 16 KiB) across the block.

**No SSOT re-pinning occurred during Q04.** `git rev-parse HEAD:tpch-sspq/SSOT.md`
equalled the pinned blob `6ce8e04d…` at preflight and at completion, `HEAD` ==
`origin/main` == `f218c59` throughout, and the pinned `ssot_commit 5912f065…` is an
ancestor of `HEAD` with an identical `SSOT.md` blob (verified with `git rev-parse` and
`git merge-base --is-ancestor` before any action, and the file was read to EOF —
895 lines — before the first stage). `SSOT_DRIFT` was never set.

Query provenance: `queries/q4-cubrid.sql` byte-matches the canonical source
`/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q4.sql`, SHA-256
`c1c292e2b4b374bba36baffeaff541818a864a53fb6f76bb9d4350fc1b90ee04`. The PostgreSQL
dialect (`49f39e64…`) differs in exactly one line, recorded in `queries/diff/q4.diff`:
`DATE_ADD(DATE '1993-07-01', INTERVAL 3 MONTH)` → `date '1993-07-01' + interval '3' month`,
because CUBRID's `DATE_ADD` has no PostgreSQL equivalent. Both sides evaluate to
1993-10-01 and the engines return identical results; no hint, join reordering,
subquery rewrite, extra predicate or semantic cast exists in either measured file. The
hinted CUBRID variants used as counterfactuals are separate diagnostic probe files
under `work/Q04`, never measured dialect files.

Schema: 8 named FKs and 8 corresponding child B-trees verified on both engines with
exact child-column order (including composite `fk_lineitem_partsupp (l_partkey,
l_suppkey)` at key_order 0,1); all PostgreSQL `pg_constraint.convalidated = true`
(8/8/8). Row counts exact-equal (`orders` 15,000,000, `lineitem` 59,986,052).
**Q04 is the campaign's purest FK-index query so far**: both engines drive the entire
semi-join through the FK B-tree on `l_orderkey` — `fk_lineitem_orders` on CUBRID,
`idx_fk_lineitem_orders` on PostgreSQL — and this plan does not exist under the
discarded PK-only schema on either side.

Contract state at measurement time:

- statistics: CUBRID `update_statistics_update_histogram=y`,
  `default_histogram_bucket_count=300` (target). Actual per-column bucket count
  remains **UNMEASURED** (opaque serialized `VARBIT` in `_db_histogram`) — carried
  forward from bootstrap and Q01–Q03. PostgreSQL standard `ANALYZE`,
  `default_statistics_target=100`, all eight tables last analyzed 2026-07-30 17:54
  (post-FK-creation).
- parallel, `configured node/gather-cap comparison`: CUBRID `parallelism=6`,
  `max_parallel_workers=100`; PostgreSQL `max_parallel_workers_per_gather=5`,
  `max_parallel_workers=5`, `parallel_leader_participation=on`,
  `max_worker_processes=16` (non-binding), `statement_timeout=300000 ms`, `jit=off`.
- buffer/cache, `configured-equal buffer budget`: CUBRID `data_buffer_size=8.0G`,
  PostgreSQL `shared_buffers=8192MB`. **Q04's working set straddles that budget, and
  the two engines land on opposite sides of it.** This is the central finding of the
  query; sections 5, 7 and 9 measure it.
- shared memory, `parallel-plan-availability parity`: PostgreSQL
  `dynamic_shared_memory_type=mmap`, verified live with `source=configuration file,
  sourcefile=postgresql.conf:969`, `/dev/shm` untouched at 628k of 64000k
  (`q4-shared-memory-verification.txt`). Q04's PostgreSQL plan contains a
  `Gather Merge`, so section 9 makes recording this mandatory. **It is also
  exonerated as a cost source here**: the live `pg_dynshmem/mmap.*` segments total
  32 KiB + 1 MiB, and DSM symbols appear 4 times in a 113,285-sample profile, so the
  large page-table band in section 6 is `shared_buffers`, not the contracted DSM
  backing.
- cpuset/NUMA: SUT+client CPUs `0-15` (node0), collectors CPUs `20-23`. 34 engine
  TIDs at preflight and 35 after the blocks, **0 off-cpuset** both times.
  `cub_server` 8,854.11 MB node0 / 4.57 MB node1 (99.95% node0); postmaster
  166.14 MB node0 / 0.69 MB node1. No page migration during the runs.
- external SUT-set load was **within contract throughout**: 0.322 core-s/s at
  preflight (threshold 1.5), and every accepted block verified `CLEAN` at 4 Hz.
  Unlike Q03, no block had to wait out a neighbour.

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored.

Q04 has `ORDER BY`, so the ordered result sequence was compared exactly. 5 rows on both
engines, all fields equal — text (including the CHAR(15) `o_orderpriority` padding),
integers, NULLs, row count and row multiset. Raw decimal text preserved. The 1e-12
relative tolerance was available but **not needed**: Q04 returns no non-integer value,
so no field could have used it.

| `o_orderpriority` | `order_count` |
|---|---|
| `1-URGENT` | 105,214 |
| `2-HIGH` | 104,821 |
| `3-MEDIUM` | 105,227 |
| `4-NOT SPECIFIED` | 105,422 |
| `5-LOW` | 105,356 |

There is no `LIMIT` and the group key has exactly 5 distinct values, so unlike Q03 no
boundary proof is required — the `ORDER BY o_orderpriority` is a total order over the
full result. Independent row-count ground truth, identical on both engines
(`q4-groundtruth-cubrid.out`, `q4-groundtruth-pg.out`) and used later for `W` and for
the section 9 trace control:

| Quantity | Value (both engines) |
|---|---|
| orders in `[1993-07-01, 1993-10-01)` | 573,671 |
| …of those, with a late `lineitem` | **526,040** (= Σ of the 5 counts above) |
| lineitem rows belonging to those orders | 2,294,856 |
| …of those, with `l_commitdate < l_receiptdate` | 1,450,571 |

Comparator: `harness/correctness_check.py` delegating to the bootstrap-verified
`harness/smoke_check.py` rules.

## 3-b. Headline timings

Regime `single-query-repeat WARM`; metadata connection mode
`single-connection-four-statements` (1 uncounted warmup + 3 measured, one direct
connection, no reconnect/prepare between measured statements, connection establishment
excluded). **Q04 is even, so the engine-block order is PostgreSQL block first, then
CUBRID block** (section 12). Each statement fully consumed all 5 rows into a
campaign-owned fixed sink under `work/Q04/sink`; content hashes computed after the
timers stopped.

The reported block is the **first block accepted under the section 12 WARM gate
described in section 5**; the two further blocks are reproducibility evidence, not a
replacement for it (section 12: extra repetitions are a diagnostic decision).

| Field | CUBRID | PostgreSQL |
|---|---|---|
| WARM established after | 12 statements (steady 1.773 s) | 13 statements (steady 0.947128 s) |
| warmup (uncounted) | 1.772000 s | 1.030398 s |
| measured run 1 | 1.765000 s | 0.984511 s |
| measured run 2 | 1.779999 s | 0.960234 s |
| measured run 3 | 1.770000 s | 0.958864 s |
| **median (headline)** | **1.770000 s** | **0.960234 s** |
| mean | 1.771666 s | 0.967870 s |
| within-block sd | 0.007637 s (0.431%) | 0.014428 s (1.491%) |
| sink bytes | 1691 | 555 |
| sink SHA-256 | `a3ec7e6f7556f3c2…` | `a041b34aacdcea4a…` |
| external load during block | mean 0.290 / max 0.873 → `CLEAN` | mean 0.236 / max 0.529 → `CLEAN` |

**Median wall ratio = 1.843301x (CUBRID / PostgreSQL) — PostgreSQL is 1.8433x
faster.** Correctness status `result-equivalent-at-SF10`; censoring status: not
censored (both engines far inside the 300 s timeout). No confidence interval is claimed
from three values.

Reproducibility across three independently gated blocks:

| Block | CUBRID median | PostgreSQL median | ratio |
|---|---|---|---|
| 1 (reported) | 1.770000 s | 0.960234 s | 1.843301x |
| 2 | 1.756000 s | 0.961496 s | 1.826321x |
| 3 | 1.779000 s | 0.956731 s | 1.859457x |
| spread | 1.299% | 0.496% | 1.8% |

Block 1 is simultaneously the median of the three CUBRID medians and the median of the
three PostgreSQL medians, so the reported headline and the median-of-medians coincide.
One CUBRID attempt was refused by the WARM gate before it was ever timed
("monotone trailing window (still drifting)") and retried; that refusal is retained as
evidence.

Measurement-resolution note: `csql` reports elapsed time at 1 ms granularity, so
CUBRID's headline carries ±0.056% quantization at this magnitude, well below its 0.431%
within-block sd; `psql` reports µs.

**PostgreSQL's within-block sd (1.491%) is 3.5x CUBRID's, and the reason is measured,
not guessed.** Its three measured statements decline monotonically
(0.9845 → 0.9602 → 0.9589) because a *fresh backend* pays a per-connection cost that a
single uncounted warmup does not remove. This is not a WARM failure of the database:
`harness/warm_establish.py` had already driven the database to a proven steady state of
0.947128 s in a preceding connection, and a brand-new connection still starts at
1.0304 s. Section 6 identifies the mechanism — page-table population in newly forked
parallel workers. Consequence, stated with its direction: the mandated regime places
PostgreSQL's measured statements **+1.39%** above its own long-run steady state
(0.960234 vs 0.947128) while CUBRID sits **−0.17%** below its own (1.770 vs 1.773), so
the contract regime **understates CUBRID's deficit by ~1.5%**. The steady-state ratio
is 1.773/0.947128 = **1.8720x** against the contract headline of 1.8433x. The contract
number is the headline, as section 12 requires; the steady-state number is recorded so
the bias is visible rather than silent.

WARM proof (proved, not assumed):

| Evidence | CUBRID | PostgreSQL |
|---|---|---|
| steady state proved before timing | 20-statement pre-warm, converged at statement 12, level shift 0.11% then 0.11% | 20-statement pre-warm, converged at statement 13, level shift 0.26% then 0.08% |
| device `read_bytes` during block | 0.00 MiB | 0.00 MiB |
| engine buffer counters | trace `fetch 3,277,822 / ioread 342,384` per statement; LRU pool conserved at 524,288 pages pre and post | `Buffers: shared hit=3,013,495 read=0` — **zero physical reads** |
| `rchar` per statement | 4,535,681,928 B (4.22 GiB) | 1,390,736 B (1.33 MiB) |
| read syscalls per statement | 276,950 | 415 |
| warmup vs median | +0.11% | +7.31% (per-connection, see above) |

CUBRID's `ioread` is deliberately **non-zero** and that is the finding, not a WARM
failure: WARM in this campaign means steady state with no cold-start penalty, and it is
proved here by an explicit convergence gate plus device reads of 0.00 MiB on both
engines. Every CUBRID miss is served by the OS page cache; none reaches the device.

**Perfmon counter usability, unchanged from Q03.** `Num_data_page_fetches` /
`Num_data_page_ioreads` read 15,305,689 / 2,325,951 both before and after the CUBRID
block (`Q04-cubrid-headline-block1.json` `buffer_counters`) while the LRU zone gauges
move, reconfirming Q03's finding that they advance at moments unrelated to statement
execution and are unusable as a per-block gauge. WARM evidence therefore rests on
device `read_bytes`, `/proc/<pid>/io`, LRU zone conservation and the trace's per-node
`ioread`.

## 4. Plan

**The two engines reach the same plan, and this is the first Q in the campaign where
that happens with no hint on either side.** That is what makes `F_plan` numeric.

CUBRID estimated (`SET OPTIMIZATION LEVEL 514`, verified non-executing: 0.02 s wall,
no rows), `q4-plan-est-cubrid.out`:

```text
temp(group by)
    subplan: sscan
                 class: orders node[0]
                 sargs: term[0] AND term[1]
                 subqs: 0
                 cost: 61093205 card 56845
    sort: 1 asc
term[0]: o_orderdate range (date '07/01/1993' ge_lt date '10/01/1993') (sel 0.0378967) (rank 2)
term[1]: exists (select l_orderkey from lineitem
                 where l_orderkey = orders.o_orderkey
                   and l_commitdate range (min inf_lt l_receiptdate)
                   and inst_num() <= 1)                                 (sel 0.1) (rank 9)

  -- correlated subquery plan:
  iscan
      class: lineitem node[0]
      index: fk_lineitem_orders term[0]
      sargs: term[1] AND term[2]        <- inst_num()<=1, l_commitdate<l_receiptdate
      cost: 4 card 1
```

CUBRID actual (trace, `q4-trace-cubrid.out`):

```text
SELECT (time: 1972, fetch: 3277822, fetch_time: 3160, ioread: 342384)
  SCAN (table: dba.orders) (heap time: 1967, fetch: 3277752, ioread: 342381,
       readrows: 15000000, rows: 15000000)
       (parallel workers: 6, heap time: 1848..1967,
        readrows: 2380011..2525461, rows: 2380011..2525461, gather: mergeable list)
  GROUPBY (time: 0, hash: partial, sort: true, page: 0, ioread: 0, rows: 5)
  SUBQUERY (correlated)
    SELECT (time: 1330, fetch: 3126018, fetch_time: 2820, ioread: 301406)
      SCAN (index: dba.lineitem.fk_lineitem_orders) (btree time: 983, fetch: 2552347,
           ioread: 301406, readkeys: 573671, filteredkeys: 573671, rows: 831334)
           (lookup time: 528, rows: 526040)
```

PostgreSQL actual (`EXPLAIN ANALYZE BUFFERS VERBOSE TIMING`, `q4-plan-act-pg.out`):

```text
Finalize GroupAggregate (actual time=886.507..1036.778 rows=5)
  Buffers: shared hit=3013495                       <- read=0
  Gather Merge (rows=30)  Workers Planned: 5  Launched: 5
    Partial GroupAggregate (rows=5 loops=6)
      Sort (quicksort 3073kB) Sort Key: o_orderpriority (rows=87673.33 loops=6)
        Nested Loop Semi Join (rows=87673.33 loops=6)
          -> Parallel Seq Scan on orders (rows=95611.83 loops=6)
               Filter: (o_orderdate >= '1993-07-01' AND o_orderdate < '1993-10-01')
               Rows Removed by Filter: 2404388/loop
               Buffers: shared hit=261264
          -> Index Scan using idx_fk_lineitem_orders on lineitem
               (actual time=0.005..0.005 rows=0.92 loops=573671)
               Index Cond: (l_orderkey = o_orderkey)
               Filter: (l_commitdate < l_receiptdate)
               Index Searches: 573671
               Buffers: shared hit=2752196
Planning Time: 1.113 ms   Execution Time: 1037.084 ms
```

Node-by-node identity — this table *is* the `F_plan = 1.0000` evidence:

| Node | CUBRID | PostgreSQL | agreement |
|---|---|---|---|
| driving scan | parallel `sscan orders`, 6 workers | `Parallel Seq Scan on orders`, leader + 5 workers | same |
| rows read from `orders` | 15,000,000 | 14,999,999 (573,671 + 14,426,328) | exact |
| rows passing the date range | 573,671 (= `readkeys`) | 573,671 | **exact** |
| inner access path | B-tree `fk_lineitem_orders` on `l_orderkey` | B-tree `idx_fk_lineitem_orders` on `l_orderkey` | same |
| index searches | 573,671 (`readkeys`/`filteredkeys`) | 573,671 (`Index Searches`; `idx_scan` delta 573,673 incl. 2 probe scans) | **exact** |
| index entries examined | 831,334 | 832,822 (`idx_tup_read` delta) | 0.18% |
| heap tuples fetched and filtered | 831,334 | 832,820 (`idx_tup_fetch` delta) | 0.18% |
| semi-join semantics | `inst_num() <= 1` → first match wins | `Nested Loop Semi Join` → first match wins | same |
| rows surviving the semi-join | 526,040 | 526,040 | **exact** |
| groups | 5 | 5 | exact |

The 832,820 figure is independently reproduced from data: a `row_number()` derivation
that replays the early-exit rule row by row over the same order set
(`q4-semijoin-entries.out`) returns **832,820** entries examined, matching PostgreSQL's
`idx_tup_fetch` delta exactly and CUBRID's trace to 0.18%. The 0.18% residue is
physical-order tie-breaking within a duplicate key (CUBRID orders by OID, PostgreSQL by
`ctid`), not a semantic difference.

Estimate quality: CUBRID's date sarg is accurate (`sel 0.0378967` vs actual
573,671/15,000,000 = 0.0382, 0.9% low) but it assigns the `EXISTS` term a flat
`sel 0.1` default against an actual 526,040/573,671 = 0.917, so its final cardinality
estimate is 56,845 against an actual 526,040 (9.25x under). PostgreSQL makes the
*opposite-signed* error: `rows=3073` per worker → 18,438 against 526,040 (28.5x under).
**Neither misestimate changes either engine's plan choice**, both engines already having
picked the best available shape, so this is recorded as a shared modelling limitation
and not raised as a candidate. It is worth one line, though, that PostgreSQL's estimate
is 3x further off than CUBRID's here.

Counterfactuals in both directions, each measured with identical variants grouped in
one connection per section 24:

| Variant | Plan reached | Wall | Verdict |
|---|---|---|---|
| CUBRID native | parallel `sscan orders` + correlated FK B-tree probe | **1.770 s** (median of 3) | baseline |
| CUBRID `/*+ NO_PARALLEL_SCAN */` | same shape, serial | 7.178 s | 4.05x worse; parallel speedup 4.05x on 6 units |
| CUBRID `/*+ USE_HASH */` | unchanged (no join to hash — the EXISTS stays a correlated subquery) | 1.776 s | no shape change |
| CUBRID `/*+ NO_PARALLEL_SUBQUERY */` | unchanged | 1.789 s | no shape change |
| CUBRID `/*+ PARALLEL(6) */` | unchanged | 1.779 s | no shape change |
| CUBRID `/*+ NO_SUBQUERY_CACHE */` | unchanged | 1.7685 s (trailing-8 of 20) | −0.11% vs 1.7705 s native; inside noise |
| PostgreSQL native | `Nested Loop Semi Join` over `idx_fk_lineitem_orders` | **0.960234 s** (median of 3) | baseline |
| PostgreSQL `enable_nestloop=off` | `Parallel Hash Semi Join`, 256 batches, 6.32M rows hashed/worker | 3.758 s (`EXPLAIN ANALYZE`) | 3.87x worse than its native |
| PostgreSQL `enable_indexscan=off` | same `Parallel Hash Semi Join` | 3.759 s | 3.87x worse |
| PostgreSQL `max_parallel_workers_per_gather=0` | same shape, serial | 3.778 s | 3.89x worse; parallel speedup 3.89x |

Two things follow. First, **there is no better plan on either side**, so `F_plan` is not
merely equal-by-luck: each engine's alternatives are 3.9–4.1x worse. Second, the
serial-versus-parallel counterfactuals show CUBRID achieving a *slightly better*
parallel speedup (4.05x) than PostgreSQL (3.89x) on the same 6 configured units, and the
serial-to-serial ratio 7.178/3.778 = **1.900x** is *larger* than the parallel ratio
1.843x — confirming from a second direction that CUBRID's deficit is not a parallelism
deficit.

## 5. Execution telemetry

Non-headline diagnostic runs; sampler on CPUs `20-23`, per-TID, weighted by actual
sample timestamp deltas. Three runs per engine per instrument, all preceded by
`harness/warm_establish.py` and all load-gated; the recorded run is the **median-U** run
(CUBRID run 2, PostgreSQL run 3). All runs are retained in raw.

| Metric | CUBRID | PostgreSQL |
|---|---|---|
| block walls, 4 statements (3 runs) | 7.110 / **7.041** / 7.014 s | 3.899 / 3.956 / **3.927** s |
| `executor_cpu` (per block) | 37.94 core-s (`parallel-query` 37.82, `transaction` 0.12) | 20.47 core-s (`pg_parallel_worker` 16.95, `pg_backend` 3.52) |
| `auxiliary_query_cpu` (per block) | 0.11 core-s (`pgbuf-page-flush` 0.04, `dwb-*` 0.03, `vacuum-master` 0.02, `pgbuf-maintain` 0.01, `csql` 0.01) | 0.01 core-s (`postmaster`) |
| `total_query_cpu` (per block) | **38.05 core-s** | **20.48 core-s** |
| `U` = CPU_block / Σwalls | **5.40406** | **5.21484** |
| `total_query_cpu` per median statement | **9.5652 core-s** | **5.0075 core-s** |
| planned workers | 6 (`parallelism=6`) | 5 (`Workers Planned: 5`) + leader |
| launched workers | 6 (trace `parallel workers: 6`) | 5 (`Workers Launched: 5`) + leader = 6 |
| max simultaneous active units | 6.2940 | 6.1850 |
| time-weighted active units (TWU) | **5.4209** | **5.4391** |
| serial tail | 0.000 s | 0.235 s |
| `rchar` per block | 18,142,807,808 B | 4,936,615 B |
| read syscalls (`syscr`) per block | 1,107,573 | 1,463 |
| `write_bytes` per block | 225,280 B | 3,457,024 B |
| device read | 0.00 MiB | 0.00 MiB |
| `unattributed_background` | none claimed | none claimed |

TWU is an independent cross-check of `U`, not a substitute. CUBRID `U` 5.40406 vs TWU
5.4209 (0.31% apart) and `perf` gives a third independent reading of 5.448 CPUs
utilized. PostgreSQL `U` 5.21484 vs TWU 5.4391 (4.3% apart, the largest such gap in the
campaign so far) — the difference is real and is the 0.235 s serial tail: TWU is
computed over the busy window only, while `U` divides by the full statement walls
including that tail. No value was derived from a configured cap and no nominal interval
was used for weighting.

**Both engines run at essentially the same parallel utilization**, 5.42 vs 5.44 TWU
against a configured 6 units on both sides, which is why `F_units` is 0.965 and
parallelism is explicitly *not* part of Q04's explanation.

**The decisive telemetry result is the I/O column: CUBRID issues 276,950 read syscalls
per statement and PostgreSQL issues 415 — 667x — at an identical 8192MB budget, on an
identical plan, for identical data.** PostgreSQL's `EXPLAIN` confirms it from the other
side: `Buffers: shared hit=3,013,495 read=0`. CUBRID's trace reports 3,277,822 logical
page fixes with 342,384 misses, a **10.45% miss rate** against PostgreSQL's **0.00%**,
at a logical-fix count only 1.088x higher. Sections 6, 7 and 9 attribute the cost and
the cause.

### Why the working sets land on opposite sides of the same budget

PostgreSQL's side is **directly measured** (`q4-workingset.out`):

| Component | 8 KiB pages | MiB |
|---|---|---|
| `lineitem` distinct heap pages actually touched | 473,929 | 3,703 |
| `orders` heap (full scan) | 261,264 | 2,041 |
| `idx_fk_lineitem_orders` | 95,024 | 742 |
| **total** | **830,217** | **6,486** |
| `shared_buffers` | 1,048,576 | 8,192 |

It fits, with **20.8% headroom**, which is exactly why `read=0`.

CUBRID's side is a **projection**, labelled as such, from a model validated on the
measured PostgreSQL side. Model: the fraction of heap pages touched by an
order-clustered random probe is `1 − (1−p)^r`, where `p = 573,671/15,000,000 = 0.03824`
is the selected fraction of orders and `r` is orders per heap page. For PostgreSQL,
`r = 53.32/3.999 = 13.33` predicts **40.54%** against a measured **42.12%** — the model
is good to 1.6 pp. CUBRID's 16 KiB page holds 87.84 lineitem rows, so `r = 21.97` and
the predicted touched fraction is **57.55%** = 393,085 pages = 6,142 MiB. Adding the
full `orders` scan (151,689 pages = 2,370 MiB) gives **8,510 MiB of heap alone against
an 8,192 MiB pool** — over by 3.9% before the index is counted at all. CUBRID's index
page count is **UNMEASURED** (`db_index` exposes no page column, verified in
`q4-index-pages.txt`); PostgreSQL's equivalent term is 742 MiB, so the true gap is
substantially wider than 3.9%.

The mechanism is page size interacting with random access, and it is worth stating
precisely because it is *not* a replacement-policy defect: for a sequential scan a
16 KiB page is neutral or better, but for Q04's order-clustered random probe the same
selected tuples span **6.00 GiB of 16 KiB pages versus 3.62 GiB of 8 KiB pages, 1.66x
more bytes for the same rows**. That is what pushes CUBRID over a budget PostgreSQL
clears with 20.8% to spare.

### Harness work done during Q04

Three defects and one gap were found and fixed, all of which changed a number. Each is
recorded because Q03's precedent is that a discovered instrument defect is evidence,
not an embarrassment to be smoothed over.

1. **PostgreSQL executor/auxiliary misclassification (fixed; changed the section 15
   split by 12.2%).** `harness/telemetry_run.py`'s `engine_procs()` reclassified the
   leader backend and all 5 parallel workers as `pg_background` (auxiliary) on their
   final sample, because an exiting PostgreSQL child has an **empty**
   `/proc/<pid>/cmdline` and fell through the cmdline test. Measured misattribution:
   5 workers × 12 ticks + leader × 8 ticks = **0.68 core-s moved from `executor_cpu` to
   `auxiliary_query_cpu`**, 12.2% of `total_query_cpu`. `total_query_cpu`, TWU and `U`
   are *unaffected* (the sum is identical), so `F_cpu` and `F_units` never depended on
   it — but section 15 requires the split to be right, and it was not. Fixed by pinning
   a pid's role once positively identified and by skipping rather than guessing an
   empty cmdline. The pre-fix runs are retained under `pre-classifier-fix/` with
   `INVALID.json`. Post-fix, PostgreSQL's auxiliary is 0.00–0.01 core-s and its io
   workers are confirmed to consume **zero** CPU on this query (their tick counters
   never move), which is consistent with 415 read syscalls.
2. **WARM was not established, and the first accepted blocks were wrong (fixed;
   changed the headline).** The first Q04 blocks passed the physical-read half of the
   section 12 WARM proof and were accepted, but a 14-repeat probe then falsified the
   steady-state half. PostgreSQL: 1026.9, 967.4, 960.1, 946.9, 944.8, 948.7, … ms — the
   contract block's three measured statements sat at 988/972/967 ms against a steady
   state near 947 ms. CUBRID: internally stable inside any block (sd 0.4%) but its
   *level* was inherited from whatever ran before it — the first block measured
   **1.706 s** and every later block reproduces **1.774–1.779 s**, because Q04's working
   set does not fit CUBRID's pool and residency is therefore history-dependent. Section
   12 says a failed WARM gate invalidates the run and restarts at warmup, so both
   engines' first blocks were invalidated (`pre-warm-gate/` + `INVALID.json`) and
   re-measured through a new `harness/warm_establish.py` stage wired into
   `harness/measure_block.sh`. The gate targets *systematic drift* — non-monotone
   trailing window, plus two consecutive window-median shifts ≤ 1.0% — rather than
   jitter, because CUBRID's own spread reaches 1.2% over a 4-statement window at a
   perfectly stable level and a spread gate would reject a converged engine. The
   criterion was validated offline against both recorded 14-repeat traces before being
   used. Had this not been caught, Q04's headline ratio would have been **1.755x**
   instead of 1.843x, a 4.8% error, and it would not have reproduced.
3. **The WARM gate aborted instead of retrying (fixed).** The first version exited the
   attempt loop when convergence failed. It now retries like a rejected load gate, since
   the next attempt starts from the state the failed one left behind. One CUBRID block
   was subsequently rescued this way.
4. **Q03's carried-forward CPU-regime gap (closed).** Q03 recorded that the card's CPU
   numerators came from single-statement-per-connection telemetry sitting +0.495% /
   +1.537% above the headline regime, and that "a future harness change could sample CPU
   inside the headline block itself". `harness/headline_telemetry.py` does that: it runs
   the identical section 12 block under the same sampler and reports
   `U = CPU_block / Σ(statement walls)` as a directly measured quantity. On Q04 the old
   method would have left a **−2.0065%** residual; the new one leaves none, and the
   single-statement instrument is retained as the independent cross-check quoted in
   section 3-a.

One instrument question was raised and **closed as a non-issue by measurement rather
than assumption**: the sampler's per-TID `/proc` reads were suspected of perturbing
CUBRID's block, since its sampled wall (1.77 s) exceeded the first block's 1.706 s. A
calibration at sampling periods 0.4 / 0.2 / 0.1 / 0.05 s (`q4-sampler-calibration.csv`)
shows CUBRID's block wall **flat at 7.07–7.11 s across a factor of 8 in sampling rate** —
so the sampler is not the cause, and the difference was buffer-pool state (defect 2
above). The same calibration establishes the correct sampling period: PostgreSQL's
measured CPU is 13.59 / 18.75 / 21.10 / 20.70 core-s at 0.4 / 0.2 / 0.1 / 0.05 s, i.e.
coarse sampling **misses transient per-statement workers entirely** and only converges
at ≤ 0.1 s, which is the period used. CUBRID converges by 0.1 s as well (37.07 / 38.07 /
38.29 / 38.30).

## 6. Profile

Non-headline. `perf` attached to verified PID sets, never all-CPU. CUBRID: `-p 1445555`
(`cub_server`; all query worker threads live inside that process, 31 TIDs). PostgreSQL:
`perf stat` on the discovered leader `1524794` plus exactly its 5 parallel workers
`1524829-1524833`; `perf record` on `postmaster 1433696 + leader`, relying on perf's
inherit-on-fork because worker PIDs are transient per statement. A driver replayed the
identical statement in one connection (CUBRID 26 repeats, PostgreSQL 46), grouping
identical variants per section 24; both captures ran under `CLEAN` load
(`external_max` 0.938 and 0.632) after `warm_establish` had converged.

Coverage validation against `perf stat`: CUBRID 109,352 samples / 944 resolved symbol
lines / **0 `[unknown]`** / 0 lost; PostgreSQL 113,285 samples / 1,864 lines / **0
`[unknown]`** / 0 lost. Driver completion verified (26 `csql` result-set markers;
PostgreSQL 230 non-empty sink lines = 46 × 5 rows).

| Metric | CUBRID | PostgreSQL |
|---|---|---|
| cycles (20.0 s window) | 296,826,840,900 | 51,131,997,093 |
| instructions | 438,084,926,442 | 77,364,963,091 |
| **IPC** | **1.48** | **1.51** |
| frequency | 2.724 GHz | 2.743 GHz |
| task-clock | 108,968.14 ms | 18,641.01 ms |
| CPUs utilized | 5.448 | 0.932 (partial set, see below) |
| context-switches | 294,648 | 136 |
| instructions per core-second | 4.0203e9 | 4.1503e9 |
| instructions per statement | 38.455e9 | 20.783e9 |
| **instructions per tuple touch** | **2,237.2** | **1,136.2** |

Two caveats, stated rather than smoothed. (a) PostgreSQL's "CPUs utilized" of 0.932 is
**not** its parallel utilization: the leader persists across the driver's 46 statements
but the 5 parallel workers are per-statement, so the fixed PID set covers one
statement's workers. Utilization comes from telemetry (`U` 5.21484, TWU 5.4391), not
from this row; IPC and instructions-per-core-second are unaffected because they are
ratios over whatever work the set actually did. (b) CUBRID's 294,648 context switches
against PostgreSQL's 136 is the signature of 276,950 blocking `pread()` calls per
statement, and is itself corroborating evidence for section 7's first row.

**`F_cpu` decomposes almost entirely into instruction count, not stalls**, and the two
engines' IPC is statistically indistinguishable (1.48 vs 1.51):
`1.8504x (instructions per statement) × 1.0323x (CPU-seconds per instruction) = 1.9102 = F_cpu`,
matching to four decimals. Per tuple touch, CUBRID executes **1.969x** the instructions.

Top self cost, CUBRID (`profile-cubrid-flat.txt`):
`rep_movs_alternative` [k] **10.18%**, `heap_attrinfo_read_dbvalues` 5.31%,
`eval_pred` 5.02%, `pgbuf_fix_release` 5.02%, `__pthread_mutex_lock` 4.79%,
`tp_value_compare_with_error` 3.20%, `__memmove_evex_unaligned_erms` 3.02%,
`__pthread_mutex_unlock_usercnt` 2.58%, `heap_next_1page` 2.43%, `pgbuf_unfix` 2.27%,
`spage_get_record` 1.95%, `eval_value_rel_cmp` 1.68%, `btree_search_leaf_page` 1.66%,
`pgbuf_unlatch_void_zone_bcb` 1.46%, `btree_search_nonleaf_page` 1.45%,
`pgbuf_lru_boost_bcb` 1.41%, `filemap_get_read_batch` [k] 1.26%, `or_mvcc_get_header`
1.11%, `eval_data_filter` 1.08%, `heap_scan_get_visible_version` 1.05%,
`spage_get_record_data` 1.02%, `btree_compare_key` 0.98%.

Top self cost, PostgreSQL (`profile-pg-flat.txt`):
`tts_buffer_heap_getsomeattrs` **16.09%**, `next_uptodate_folio` [k] **10.41%**,
`_bt_compare` 5.85%, `LWLockAttemptLock` 4.60%, `ExecInterpExpr` 4.37%,
`hash_search_with_hash_value` 3.77%, `PinBuffer` 3.53%, `filemap_map_pages` [k] 3.23%,
`folio_remove_rmap_ptes` [k] 3.21%, `heap_page_prune_opt` 2.95%, `_compound_head` [k]
2.83%, `folios_put_refs` [k] 2.44%, `ExecSeqScanWithQual` 1.99%, `heapgettup_pagemode`
1.79%, `heap_hot_search_buffer` 1.72%, `zap_present_ptes` [k] 1.71%,
`LockBufferInternal` 1.00%, `UnlockReleaseBuffer` 0.90%, `folio_add_file_rmap_ptes` [k]
0.87%, `heap_getnextslot` 0.84%.

Banded (each band against its own engine's `total_query_cpu`: CUBRID 9.5652 core-s,
PostgreSQL 5.0075 core-s):

| Band | CUBRID | PostgreSQL |
|---|---|---|
| kernel page-cache read + copy on the buffer-miss path | **12.13% = 1.160 core-s** | **0.00 core-s** (zero physical reads) |
| buffer manager fix/unfix/LRU (CUBRID) / pin+lock (PG) | 11.33% = 1.084 core-s | 16.06% = 0.804 core-s |
| predicate / expression evaluation | **11.29% = 1.080 core-s** | **5.09% = 0.255 core-s** |
| record / attribute extraction | 15.86% = 1.517 core-s | 17.69% = 0.886 core-s |
| B-tree descent | 4.87% = 0.466 core-s | 7.06% = 0.354 core-s |
| mutex / lightweight locking | 8.28% = 0.792 core-s | (inside buffer band: `LWLockAttemptLock` 4.60%) |
| userspace memmove/memcpy | 3.02% = 0.289 core-s | — |
| heap access / scan machinery | (inside extraction band) | 8.45% = 0.423 core-s |
| **parallel-worker page-table churn** | **0.00 core-s (threaded model)** | **27.43% = 1.374 core-s** |
| banded subtotal | 66.78% = 6.388 core-s | 81.78% = 4.095 core-s |

**The single most surprising result in Q04 is the last row, and it runs against
CUBRID's disadvantage: PostgreSQL spends 27.43% of its query CPU — 1.374 core-s —
populating and tearing down page tables for parallel workers it forks and destroys on
every statement.** The call graph attributes it exactly and it is not the campaign's
`mmap` DSM setting: the fault-in half (`filemap_map_pages` → `next_uptodate_folio` /
`set_pte_range`, 15.6%) appears *inside*
`ParallelWorkerMain → ParallelQueryMain → ExecutorRun → ExecAgg → ExecSort →
ExecNestLoop → ExecScan → IndexNext → index_getnext_slot`, i.e. a freshly forked worker
faulting in its own PTEs for the 8 GiB `shared_buffers` mapping (`/dev/zero` MAP_SHARED,
verified in `/proc/<postmaster>/maps`) as it touches buffers; the teardown half
(`exit_mmap → unmap_vmas → zap_pte_range → zap_present_ptes / folio_remove_rmap_ptes /
folios_put_refs`, 11.4%) hangs off `__x64_sys_exit_group`. The live `pg_dynshmem/mmap.*`
segments are 32 KiB and 1 MiB and DSM symbols appear 4 times in 113,285 samples, so
section 9's `dynamic_shared_memory_type=mmap` is exonerated. This is also the mechanism
behind PostgreSQL's +7.31% warmup statement and its 1.491% within-block sd.

The honest reading of that finding is that it makes CUBRID's result *worse*, not
better: **PostgreSQL wins by 1.8433x while burning 27.4% of its CPU on process-model
overhead that CUBRID's threaded parallel-scan model does not pay at all.** Net of that
band, PostgreSQL's query CPU would be 3.63 core-s and `F_cpu` would be **2.63x**. It is
reported here, and as a source-contrast row in section 7, because a comparison that only
lists the other engine's advantages is not a comparison.

## 7. Source contrast

| Item | CUBRID file:line | PostgreSQL file:line | Difference | Class |
|---|---|---|---|---|
| Data-page buffer miss on a working set that marginally exceeds the pool | `src/storage/page_buffer.c:2211` pgbuf_fix_release(); miss branch reaches `pgbuf_claim_bcb_for_fix()` → `src/storage/file_io.c:3935` fileio_read() = one synchronous `pread` of exactly one 16 KiB page on the calling query thread. Victim/zone logic in the same file (`pgbuf_get_victim`, `pgbuf_lru_boost_bcb`, `pgbuf_unlatch_void_zone_bcb`, all in the Q04 profile) | `src/backend/storage/buffer/bufmgr.c` PinBuffer()/StartReadBuffer() path — reached 3,013,495 times with **0** misses; `src/backend/storage/buffer/freelist.c:442` BAS_BULKREAD ring keeps a large scan from evicting the resident set | At an identical 8192MB budget and an identical plan, CUBRID misses 342,384 times per statement (10.45%) and PostgreSQL misses 0. Measured cost of the miss path: **1.160 core-s vs 0.000**, call-graph verified to `__libc_pread64 ← fileio_read ← pgbuf_claim_bcb_for_fix ← pgbuf_fix_release`, all samples in `parallel-query` executor threads. Contributing storage-format term: CUBRID's 16 KiB page makes the same order-clustered random row set span 6.00 GiB against 3.62 GiB of 8 KiB pages. | same stage, lower measured cost |
| Scan-level sarg evaluation | `src/query/query_evaluator.c:2741` eval_data_filter() per row → `:1666` eval_pred() re-walks the PRED_EXPR tree → `:2150` eval_pred_comp0() does `fetch_peek_dbval()` for both sides then `:2186` eval_value_rel_cmp() → `:152` eval_value_rel_cmp() re-inspects both DB_VALUE domains and may `tp_domain_resolve_default()`/`tp_value_coerce()` at `:255-257` before calling `:271`/`:276` `tp_value_compare_with_error()` (`src/object/object_domain.c:10404`), the fully generic comparator. `eval_fnc()` (`:2590`) specializes only the evaluator function, not the (domain, domain, REL_OP) triple | `src/backend/executor/execExpr.c:229` ExecInitQual() compiles the qual **once** into a linear ExprEvalStep program; `:2789` picks the specialized `EEOP_FUNCEXPR_STRICT_2` opcode; `src/backend/executor/execExprInterp.c:252` ExecReadyInterpretedExpr() further specializes short step sequences and installs direct-threaded dispatch; `:719` `EEOP_SCAN_VAR` takes the attribute as a raw Datum from the already-deformed slot; `:996` `EEOP_FUNCEXPR_STRICT_2` does null checks then one indirect call to the resolved fmgr function; `src/backend/utils/adt/date.c:404` date_lt() / `:431` date_ge() compare two int32 `DateADT`s | Both engines evaluate exactly 30,832,820 comparisons (15,000,000 × 2 date terms + 832,820 × 1). CUBRID spends 1.080 core-s, PostgreSQL 0.255 core-s — **35.0 ns vs 8.3 ns per comparison, 4.24x**. CUBRID re-decides per row what it is comparing; PostgreSQL decided once at plan time. | structural absence |
| Parallel execution unit lifecycle | Threaded: parallel scan workers are pooled threads inside `cub_server` (all 31 TIDs in one address space, one page table). No per-statement address-space construction appears anywhere in the Q04 profile. | `src/backend/postmaster/postmaster.c` postmaster_child_launch() → `src/backend/access/transam/parallel.c` ParallelWorkerMain() forks a process per statement; the kernel then faults in the child's PTEs for the 8 GiB `shared_buffers` mapping (`filemap_map_pages`/`next_uptodate_folio`/`set_pte_range`, 15.6%) and tears them down at `__x64_sys_exit_group` → `exit_mmap` → `zap_pte_range` (11.4%) | **27.43% = 1.374 core-s of PostgreSQL's query CPU, against 0.00 on CUBRID.** This is the one large band where CUBRID's architecture is measurably ahead, and it is why PostgreSQL's first statement in a fresh connection costs +7.31%. Net of it, `F_cpu` would be 2.63x rather than 1.91x. | same stage, lower measured cost (CUBRID favoured) |
| Parallel-scan trace/statistics merge for a correlated subquery | `src/query/parallel/px_scan/px_scan_trace_handler.cpp:467-470` merges the root's `dptr_list` once; the duplicating "for nl join" loop at `:493-500` (and its inner `dptr_list` loop at `:496-499`) is skipped entirely because `xasl_tree->scan_ptr` is nullptr for a single-table driving scan. `xasl_merge_stats()` (`src/xasl/xasl_iteration.cpp:87`, ending at `:205` with `iterate_xasl_tree`) recurses `dptr_list` then `scan_ptr` at `src/xasl/xasl_iteration.hpp:180-197` | `src/backend/executor/execParallel.c:1173` planstate_tree_walker() visits each PlanState exactly once; `:1115` InstrAggNode() aggregates one worker slot for the node currently visited; `src/backend/executor/instrument.c:232` never re-walks children | Q04 is the **negative control** for IMP-005. Under a 6-worker parallel scan every counter is exact — `readrows` 15,000,000 vs a true cardinality of 15,000,000, `readkeys` 573,671 vs a true 573,671, `lookup rows` 526,040 vs a true 526,040. The (depth−1) multiplication needs a non-empty `scan_ptr` chain, which Q04 does not have. | common to both engines (on this query) |
| Tuple attribute extraction | `src/storage/heap_file.c:10464` heap_attrinfo_read_dbvalues() materializes each needed attribute into a DB_VALUE before any predicate sees it (5.31%) | `src/backend/executor/execTuples.c:1017` slot_deform_heap_tuple(), called from `:751` tts_buffer_heap_getsomeattrs(), deforms in place bounded by the attributes actually requested (16.09%) | Comparable absolute cost (1.517 vs 0.886 core-s over the extraction band) and PostgreSQL's is proportionally *larger*. Recorded so IMP-008's predicate band is not inflated by folding extraction into it. | common to both engines |
| Correlated-subquery result cache | `src/query/subquery_cache.c:336` sq_put() / `:406` sq_get(); the self-disabling guard at `:410-418` turns the cache off once size exceeds 60% of `max_subquery_cache_size` (2.0M configured) when `SQ_CACHE_HIT/SQ_CACHE_MISS < SQ_CACHE_MIN_HIT_RATIO` (`subquery_cache.h:40`, value 9) | `src/backend/executor/nodeMemoize.c` — not chosen for this plan, correctly, since the correlation key is unique | Q04's correlation key `o_orderkey` is **unique**, so the cache can never hit: hit ratio is exactly 0 over 573,671 probes. Controlled A/B nevertheless measures **1.7685 s with `/*+ NO_SUBQUERY_CACHE */` vs 1.7705 s native (−0.11%, inside a 0.3–0.6% noise band)**, because the guard disables the cache early. Real mechanism, no material cost — recorded and explicitly **not** raised as a candidate. | common to both engines |

## 8. Causal decomposition details

1. **Both optimizers found the same plan unaided, and it is the right one.**
   `F_plan = 1.0000` rests on node-by-node identity (section 4), not on similarity of
   description: 573,671 index searches and 526,040 output rows on both engines, with
   index entries examined agreeing to 0.18% and independently reproduced at 832,820 by
   a `row_number()` replay of the early-exit rule. Every alternative shape is 3.87–4.05x
   worse on its own engine. There is no plan-choice defect on either side, and unlike
   Q03 no hint was needed to reach a controlled comparison.
2. **Work is identical at the data-access layer; the 6.0% in `F_work` is bookkeeping.**
   CUBRID reports one `temp(group by)` node where PostgreSQL reports four post-join
   nodes, and PostgreSQL exposes the semi-join as a node where CUBRID folds it into a
   scan sarg. Collapsing both engines' aggregation chains gives `F_work = 0.9675`. The
   scan and probe counts — where all the cost is — agree to 0.18%.
3. **Parallelism is not the explanation, from three independent directions.**
   `F_units = 0.9650`; TWU 5.4209 vs 5.4391 against 6 configured units on both sides;
   and the serial-to-serial counterfactual ratio (7.178/3.778 = **1.900x**) is *larger*
   than the parallel ratio (1.843x), so removing parallelism entirely would widen
   CUBRID's deficit rather than narrow it. CUBRID's parallel speedup (4.05x) is in fact
   slightly better than PostgreSQL's (3.89x).
4. **The whole loss is per-tuple CPU, and it is instruction count, not stalling.**
   `F_cost = 2.0327` — 556.5 ns vs 273.8 ns per tuple touch. `perf` decomposes it as
   `1.9691x (instructions per tuple) × 1.0323x (CPU-seconds per instruction) = 2.0327`,
   at IPC 1.48 vs 1.51. There is no memory-stall story here; CUBRID simply executes
   about twice the instructions for the same tuples.
5. **Localisation of the 4.558 core-s excess.** Two bands account for 43.6% of it:
   - *buffer misses that PostgreSQL does not take at all* — 1.160 core-s of kernel
     page-cache read and copy, call-graph verified to the `pgbuf_fix_release` miss
     branch, against **0.000 core-s** on PostgreSQL, which reads zero pages for this
     query at the same 8192MB. **25.5% of the excess** (IMP-002).
   - *predicate evaluation* — 1.080 vs 0.255 core-s for the same 30,832,820
     comparisons, 35.0 ns vs 8.3 ns each. **18.1% of the excess** (IMP-008).
     The remainder is spread across mutex/latching (0.792 core-s, itself partly a
     consequence of 276,950 blocking reads and 294,648 context switches), a
     0.280 core-s buffer-manager difference, and 0.631 core-s of attribute extraction —
     the last of which is explicitly *not* charged to CUBRID as a defect, since
     PostgreSQL spends proportionally more of its own CPU there.
6. **PostgreSQL wins while wasting a quarter of its own CPU.** 27.43% = 1.374 core-s of
   its query CPU is per-statement parallel-worker page-table setup and teardown, which
   CUBRID's threaded model does not pay. Net of it, `F_cpu` would be **2.63x** instead
   of 1.9102x. The comparison is reported in both directions.
7. **Explanations considered and rejected, with the number that rejected each.**
   - *"CUBRID picked a worse plan."* Rejected: the plans are node-for-node identical
     (573,671 searches and 526,040 output rows on both), and each engine's alternatives
     are 3.87–4.05x worse.
   - *"CUBRID does more work."* Rejected: `F_work = 0.9397`, and 0.9675 once the
     node-decomposition artifact is removed. At the data-access layer the counts agree
     to **0.18%**.
   - *"CUBRID's parallelism is inferior."* Rejected: TWU 5.4209 vs 5.4391, and CUBRID's
     serial→parallel speedup is *better* (4.05x vs 3.89x).
   - *"CUBRID stalls on memory."* Rejected: IPC 1.48 vs 1.51, and the CPU gap
     decomposes as 1.969x instructions × 1.032x CPU-per-instruction.
   - *"CUBRID's I/O is slower."* Rejected: device reads are **0.00 MiB on both engines**.
     Every one of CUBRID's 276,950 reads per statement is served by the OS page cache.
     The cost is CPU and memory bandwidth, not disk, which is why it is charged to
     `F_cost` and not treated as an I/O factor.
   - *"CUBRID lacks read combining."* Rejected, as on Q03 and more sharply here: all
     276,950 reads are exactly 16,377 bytes (`rchar`/`syscr`), i.e. precisely one 16 KiB
     page per call — but PostgreSQL issues **415** reads, so there is nothing to combine
     against. The lever is not reading in bigger units, it is not missing (IMP-002).
   - *"The correlated-subquery cache costs CUBRID something, since its hit ratio is
     provably 0 over 573,671 unique keys."* Rejected by direct A/B: **1.7685 s vs
     1.7705 s, −0.11%**, inside a 0.3–0.6% noise band, because
     `subquery_cache.c:410-418` disables the cache early once the hit ratio fails.
     Mechanism real, effect immaterial, no candidate raised.
   - *"The section 9 `dynamic_shared_memory_type=mmap` contract is inflating
     PostgreSQL's kernel cost."* Rejected: the live DSM segments are 32 KiB and 1 MiB,
     DSM symbols appear 4 times in 113,285 samples, and the call graph puts the page-table
     band on the `/dev/zero` MAP_SHARED `shared_buffers` mapping instead.
   - *"IMP-006 (list-file materialization) applies to Q04."* Rejected as material: the
     path runs, but this plan materializes only 526,040 result tuples rather than an
     intermediate join stream, and `fetch_val_list` reaches just 0.55% of profile. No Q04
     relation was added to IMP-006 rather than record one the profile does not support.
   - *"CUBRID's cardinality misestimate matters."* Rejected: CUBRID is 9.25x under and
     PostgreSQL is 28.5x under — PostgreSQL is the *worse* estimator here — and neither
     changes its plan.

Error budget and closure: the reconstruction residual is **+0.000000%**, which section
3-a states is an identity rather than a prediction, so the card's closure rests instead
on the independent quantities being consistent: `U` from the headline-regime instrument
agrees with the single-statement instrument to −1.8% (CUBRID) and +2.9% (PostgreSQL),
with TWU to 0.31% (CUBRID) and 4.3% (PostgreSQL, the 0.235 s serial tail), and with
`perf` task-clock to 0.8% (CUBRID). `F_cpu`'s decomposition into instructions ×
CPU-per-instruction reproduces it to four decimals from an entirely separate instrument.
Block-to-block reproducibility of `R_wall` is 1.826–1.859 (1.8%). The card is closed.

## 9. Improvements

Registry state before Q04: `IMP-001`…`IMP-007`, `next_id: IMP-008`. Deduplication: the
Git ledger was searched by title, both source locations and root cause. `IMP-001`
(NUMERIC accumulation, `numeric_opfunc.c:2477`), `IMP-003` (LIKE selectivity) and
`IMP-004` (UTF-8 LIKE matcher, `language_support.c:2831`) touch no path Q04 exercises
materially. `IMP-006` was **considered and rejected** for a Q04 relation (item 7 above).
`IMP-002` and `IMP-007` are Q04's root causes and were extended rather than duplicated.
One new ID was allocated; `next_id` advances to `IMP-009`. No old-campaign candidate ID
was consulted.

| ID | Root cause | Priority | Category | Status | Evidence type | Effect on Q04 |
|---|---|---|---|---|---|---|
| `IMP-002` | Data-buffer replacement fails to retain a working set that marginally exceeds the pool — now also for **random index-driven** access, not only sequential scans | **P1** (was P3) | buffer/IO | `measured` | profile attribution + direct A/B | 1.160 vs **0.000** core-s; 342,384 misses/statement vs **0** at the same 8192MB; **25.5% of the CPU excess** |
| `IMP-008` | Scan sargs route every row through the generic `tp_value_compare_with_error()` with per-call domain resolution, where PostgreSQL compiles the qual once into type-specialized steps | **P1** | expression/type | `measured` | profile attribution | 1.080 vs 0.255 core-s over 30,832,820 identical comparisons (35.0 vs 8.3 ns); **18.1% of the excess** |
| `IMP-007` | (existing, Q03) Every buffer miss is a synchronous single-page `pread` on the query thread | P2 | buffer/IO | `measured` | profile attribution | Q04 relation added: 276,950 blocking reads/statement at exactly 16,377 B each vs 415; **but scope narrowed** — see below |
| `IMP-005` | (existing, Q03) Parallel-scan trace statistics count nested-loop levels (depth−1) times | P2 | parallelism | `measured` | direct A/B | Q04 relation added as a **negative control**: all counters exact; the defect requires a `scan_ptr` chain |

**Ranking justification.** `IMP-002` outranks `IMP-008` on measured share of the
matched-plan CPU excess (25.5% vs 18.1%) and on decisiveness of the contrast — the
comparison engine pays literally zero on that band, which is as clean as a cross-engine
result gets. `IMP-008` outranks `IMP-007` because on Q04 `IMP-007`'s motivating
argument does not apply at all: with PostgreSQL at zero physical reads there is no
asynchrony contrast, and the same 1.160 core-s is fully addressable by *not missing*
rather than by overlapping the miss. That is a **narrowing** of `IMP-007` on this
query, recorded rather than glossed, and the Q04 relation is explicitly annotated so it
cannot be misread as evidence for asynchrony. `IMP-008` sits below `IMP-002` on share
but is the cheaper fix (medium vs high difficulty, with a low-difficulty first step).
The bands are **not summed**: they are verified disjoint by symbol (kernel copy plus
buffer manager versus predicate evaluation), and `IMP-002` and `IMP-007` are two levers
on the *same* core-seconds — miss count versus cost per miss — so adding them would
double-count.

### IMP-002 — a working set 3.9% too large for the pool costs 1.160 core-s that PostgreSQL does not pay

- **Mechanism, CUBRID.** `pgbuf_fix_release()` (`src/storage/page_buffer.c:2211`) looks
  the page up; on a miss `pgbuf_claim_bcb_for_fix()` takes a victim through the LRU zone
  logic and calls `fileio_read()` (`src/storage/file_io.c:3935`), one synchronous `pread`
  of one 16 KiB page on the calling query thread. Because Q04's page set marginally
  exceeds the pool, the same pages are evicted and re-read every statement: 342,384
  misses out of 3,277,822 fixes, 10.45%, reproducibly, statement after statement.
- **Mechanism, PostgreSQL.** The same logical access — 3,013,495 buffer accesses — takes
  **zero** physical reads, because its 830,217-page working set (measured, not modelled:
  473,929 distinct `lineitem` heap pages + 261,264 `orders` pages + 95,024 index pages)
  fits its 1,048,576 buffers with 20.8% headroom. `freelist.c:442`'s `BAS_BULKREAD` ring
  additionally protects the resident set from scan-driven eviction.
- **Why the direction follows.** The plans are identical and the logical fix counts are
  within 8.8%, so the entire difference is retention. And the cost is not hypothetical:
  the call graph puts 10.18% of CUBRID's CPU in `rep_movs_alternative` reached *only*
  via `__libc_pread64 ← fileio_read ← pgbuf_claim_bcb_for_fix ← pgbuf_fix_release`, with
  `filemap_get_read_batch` 1.26% and `filemap_read` 0.69% on the same path, all in
  `parallel-query` executor threads.
- **Evidence event and denominator.** CPU-seconds in the kernel page-cache read/copy
  band per statement; denominator = pages read from outside the pool (342,384 CUBRID,
  0 PostgreSQL). Raw: `profile-cubrid-flat.txt`, `profile-cubrid-callgraph.txt`,
  `q4-trace-cubrid.out`, `q4-plan-act-pg.out`, `q4-workingset.out`.
- **Contributing mechanism, separated from the candidate.** CUBRID's 16 KiB page holds
  87.8 lineitem rows against PostgreSQL's 53.3, so the same order-clustered random row
  set spans 6.00 GiB instead of 3.62 GiB — 1.66x more bytes for the same tuples. Page
  size is a storage-format constant, not a replacement-policy defect, so it is recorded
  as contributing rather than folded into the candidate.
- **Effect range.** 1.160 core-s, 12.13% of CUBRID's query CPU and 25.5% of the
  4.558 core-s excess. Upper bound on what perfect retention recovers; lower bound on
  the cost of non-retention, since the 1.084 core-s buffer-manager band also contains
  victim-selection work that retention would shrink but not remove.
- **Implementation direction.** A scan-resistant / access-aware replacement policy so a
  working set at 1.0–1.1x the pool retains a resident fraction instead of self-evicting;
  Q04 shows the target includes random index-driven probes, not just large sequential
  scans, so a single `BAS_BULKREAD`-style ring is not a complete answer. Cheapest probe
  that would separate policy from page size: re-run Q04 with `data_buffer_size` raised
  just past the projected 8,510 MiB heap working set and confirm `ioread` collapses
  toward 0 — a diagnostic, never inside a headline block, and not a contract change.
- **Correctness/regression risk.** None expected for results; replacement policy does
  not affect correctness. Risk is regression for workloads that rely on current LRU
  promotion.
- **Validation criteria.** (1) Q04 CUBRID `ioread` per statement falls from 342,384
  toward 0 with the pool unchanged at 8192MB and output byte-identical to
  `sink-Q04-cubrid-headline-block1.out`; (2) the kernel page-cache band falls below 3%
  of profiled self cost; (3) Q04 CUBRID median wall improves against 1.770 s under the
  same `warm_establish` + `measure_block` protocol with the WARM gate still `CONVERGED`;
  (4) buffer hit ratio > 0 on a repeated scan of a table 1.0–1.5x the pool (the original
  Q01 criterion); (5) Q01–Q22 results unchanged.
- **Priority.** **P1**, raised from P3. The P3 justification was that device
  `read_bytes` is 0 so misses cost nothing material; Q04 refutes that with a number —
  serving them from the OS page cache costs 1.160 core-s of executor CPU per statement.
  Not P0 because no direct A/B yet shows how much a realistic policy change recovers,
  and part of the gap is page size rather than policy.
- **Difficulty.** **High** — victim selection and zone promotion in `page_buffer.c` plus
  scan-context plumbing from the executor, and the random-probe case needs a different
  signal from the sequential-scan case.
- **Upstream precedent.** None identified for a scan-resistant replacement policy in the
  pinned tree.

### IMP-008 — every sarg comparison re-resolves its operand domains

- **Mechanism, CUBRID.** The heap scan calls `eval_data_filter()`
  (`src/query/query_evaluator.c:2741`) per row, which walks the `PRED_EXPR` tree through
  `eval_pred()` (`:1666`) to `eval_pred_comp0()` (`:2150`); that peeks both operands with
  `fetch_peek_dbval()` and calls `eval_value_rel_cmp()` (`:2186` → `:152`), which
  **re-inspects both DB_VALUE domains on every call** and may run
  `tp_domain_resolve_default()`/`tp_value_coerce()` (`:255-257`) before finally calling
  `tp_value_compare_with_error()` (`:271`/`:276`,
  `src/object/object_domain.c:10404`) — the fully generic comparator.
  `eval_fnc()` (`:2590`) already specializes the evaluator *function* by single-node
  type, but not the concrete (domain, domain, `REL_OP`) triple.
- **Mechanism, PostgreSQL.** `ExecInitQual()` (`src/backend/executor/execExpr.c:229`)
  compiles the qual **once** into a linear `ExprEvalStep` program; `:2789` selects the
  specialized `EEOP_FUNCEXPR_STRICT_2` opcode; `ExecReadyInterpretedExpr()`
  (`src/backend/executor/execExprInterp.c:252`) specializes short step sequences further
  and installs direct-threaded dispatch. At run time `EEOP_SCAN_VAR` (`:719`) takes the
  attribute as a raw Datum from the already-deformed slot and
  `EEOP_FUNCEXPR_STRICT_2` (`:996`) does null checks plus one indirect call into
  `date_lt()`/`date_ge()` (`src/backend/utils/adt/date.c:404`/`:431`), which compare two
  `int32` `DateADT`s.
- **Why the direction follows.** The comparison *count* is identical by construction —
  30,832,820 on both engines — and the plans are identical, so the 4.24x cost difference
  can only be per-comparison overhead. The overhead PostgreSQL does not have is exactly
  the per-row domain decision that it hoisted to plan time.
- **Evidence event and denominator.** CPU-seconds in the predicate-evaluation symbol
  band per statement; denominator 30,832,820 comparisons. CUBRID: `eval_pred` 5.02% +
  `tp_value_compare_with_error` 3.20% + `eval_value_rel_cmp` 1.68% + `eval_data_filter`
  1.08% = 11.29% = 1.080 core-s. PostgreSQL: `ExecInterpExpr` 4.37% + `FunctionCall2Coll`
  0.72% = 5.09% = 0.255 core-s. Raw: `profile-cubrid-flat.txt`, `profile-pg-flat.txt`.
- **Deliberate conservatism.** PostgreSQL's `ExecInterpExpr` is charged in full to
  predicates although the same interpreter also does projection, which makes 4.24x an
  understatement; and CUBRID's `fetch_val_list` (0.55%) and `mr_data_readval_date`
  (0.42%) are **excluded** so this band cannot overlap IMP-006's.
- **Effect range.** 0.825 core-s, 18.1% of the 4.558 core-s excess. Upper bound is the
  full 1.080 core-s band; the realistic target is the coercion/domain-resolution
  prologue, the comparison itself being irreducible. No wall-clock claim: at 5.4 active
  units, CPU converts to wall only in proportion to utilization.
- **Implementation direction.** Bind a resolved comparison for the concrete
  (domain, domain, `REL_OP`) triple at `SCAN_PRED` setup, extending the specialization
  `eval_fnc()` already performs, so `eval_value_rel_cmp()`'s per-call prologue runs once
  per scan instead of once per row. Cheapest first step: the constant side of a range
  sarg is known at compile time, so pre-coerce it to the column domain when the
  predicate is built and take the fast path unconditionally afterwards.
- **Correctness/regression risk.** Medium — coercion rules, NULL handling, total vs
  ordinal order and string collation must be preserved exactly, and a wrongly cached
  domain decision silently changes predicate *results* rather than crashing. The
  constant-pre-coercion sub-step is materially lower risk: it changes when a coercion
  happens, not which one.
- **Validation criteria.** (1) Q01–Q22 results byte-identical, the only acceptable
  correctness evidence for a comparison change; (2) the band falls below 6% of profiled
  self cost on Q04; (3) Q04 CUBRID median wall improves against 1.770 s under the same
  protocol; (4) targeted tests for mixed-domain comparisons (date vs timestamp, numeric
  vs int, collated strings) and NULL on either side — exactly the cases the fast path
  must decline; (5) no regression on Q01, dominated by a different expression path.
- **Priority.** **P1** — 18.1% of the measured excess on a path every sargable scan
  executes. Not P0 because no A/B yet separates the removable prologue from the
  irreducible comparison inside the 35.0 ns.
- **Difficulty.** **Medium** — the specialization hook already exists in `eval_fnc()`;
  the work is proving semantic equivalence across domain pairs, not restructuring the
  executor. The constant-pre-coercion sub-step alone is low.
- **Upstream precedent.** Partial and same-direction: `eval_value_rel_cmp()` already
  carries a constant-coercion optimization, commented *"check for constant values to
  coerce 1-time, then reduce many-times coerce at tp_value_compare_with_error()"* at
  `src/query/query_evaluator.c:178`, so hoisting per-row domain work out of the
  comparison path is an accepted pattern in this very file. No prior CBRD issue/PR was
  identified that generalizes it to full (domain, domain, `REL_OP`) dispatch; the pinned
  tree at `607f1ee9` was searched for changes to `eval_value_rel_cmp`, `eval_pred_comp0`
  and `tp_value_compare_with_error` call sites.

### IMP-005 — Q04 negative control

Q04 adds no runtime finding but pins the defect's boundary. Under a 6-worker parallel
outer scan every trace counter is **exact**: `orders` `readrows` 15,000,000 against a
true cardinality of 15,000,000; subquery `readkeys` 573,671 against a true probe count
of 573,671; `lookup rows` 526,040 against a true 526,040. The reason is structural —
Q04's XASL hangs the correlated `EXISTS` off the **root** node's `dptr_list` and has no
`scan_ptr` chain, so `merge_xasl_tree()` merges it exactly once at
`px_scan_trace_handler.cpp:467-470` and the duplicating loop at `:493-500` never runs.
This **scopes** the defect (it requires a non-empty `scan_ptr` chain) and pins the
root-dptr path with exact numbers a fix must preserve; it does **not** clear the
`:496-499` inner `dptr_list` loop, which is still double-counted by construction because
the enclosing `xasl_merge_stats(xptr1)` has already recursed into `xptr1->dptr_list` via
`iterate_xasl_tree` (`xasl_iteration.hpp:180-187`, called from `xasl_iteration.cpp:205`).
Q04 simply does not exercise it. A Q04 regression pin was added to IMP-005's validation
criteria.

None of the candidates is marked `validated`: no correctness evidence for a fix exists
yet. Full fields in `reports/improvement-registry.json`.

## 10. Evidence index

Format: `claim → raw file → formula → evidence type → SHA-256`.
All paths are under `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q04/`; byte sizes and
full hashes for all **236** artifacts are in `reports/Q04/raw-manifest.json`.

| Claim | Raw file | Formula / basis | Evidence type | SHA-256 |
|---|---|---|---|---|
| preflight: ownership OK, 34 TIDs 0 off-cpuset, 8FK/8-btree 8/8/8 convalidated, row counts, contract values, provenance, external load 0.322 PASS | `preflight-Q04.txt` | direct capture | direct A/B | `4b6716ebdfd82a34…` |
| post-block ownership OK, 0 orphans, 35 TIDs 0 off-cpuset, pool conserved 524,288 pages | `q4-postcheck.txt` | direct capture | direct A/B | see manifest |
| Q04 `result-equivalent-at-SF10`, 5 rows ordered | `q4-correctness.json`, `q4-correctness-{cubrid,postgresql}.out` | ordered sequence compare | direct A/B | see manifest |
| ground truth 573,671 orders in range / 526,040 with a late lineitem, identical both engines | `q4-groundtruth-cubrid.out`, `q4-groundtruth-pg.out` | `count(*)` under the same predicates | direct A/B | see manifest |
| CUBRID estimated plan, non-executing (0.02 s, no rows): sscan + correlated FK B-tree probe | `q4-plan-est-cubrid.out`, `q4-plan-est-cubrid.time` | `SET OPTIMIZATION LEVEL 514` | direct A/B | see manifest |
| PostgreSQL estimated plan + live `Settings:` | `q4-plan-est-pg.out` | `EXPLAIN (COSTS, VERBOSE, SETTINGS)` | direct A/B | see manifest |
| **WARM established before timing**: CUBRID converged at statement 12 (steady 1.773 s), PostgreSQL at 13 (steady 0.947128 s) | `Q04-{cubrid,postgresql}-warm-block1.json` | 20 repeats, non-monotone window + two window-median shifts ≤ 1% | direct A/B | see manifest |
| CUBRID 3 headline values, median 1.770000 s, warmup +0.11% | `Q04-cubrid-headline-block1.json` | median of 3 measured statements | direct A/B | see manifest |
| CUBRID sink, 4 statements × 5 rows fully consumed, 1691 B | `sink-Q04-cubrid-headline-block1.out` | per-statement `(N sec)` lines | direct A/B | `a3ec7e6f7556f3c2…` |
| PostgreSQL 3 headline values, median 0.960234 s, `Buffers: read=0` | `Q04-postgresql-headline-block1.json` | median of 3 measured statements | direct A/B | see manifest |
| PostgreSQL sink, 4 statements × 5 rows fully consumed, 555 B | `sink-Q04-postgresql-headline-block1.out` | `\timing` per statement | direct A/B | `a041b34aacdcea4a…` |
| both headline blocks `CLEAN` (external max 0.873 / 0.529) | `Q04-{cubrid,postgresql}-bgload-block1.json` | host-wide SUT busy minus absolute campaign CPU, 4 Hz | direct A/B | see manifest |
| headline reproducibility across 3 gated blocks: ratios 1.8433 / 1.8263 / 1.8595 | `Q04-*-headline-block{1,2,3}.json` | per-block medians | direct A/B | see manifest |
| **contract regime sits +1.39% above PostgreSQL's steady state and −0.17% below CUBRID's** | `Q04-*-warm-block1.json` vs `Q04-*-headline-block1.json` | steady median vs contract median | direct A/B | see manifest |
| CUBRID actual trace: `parallel workers: 6`, readrows 15,000,000, readkeys 573,671, lookup rows 526,040, fetch 3,277,822, ioread 342,384 | `q4-trace-cubrid.out` | `SET TRACE ON` + `SHOW TRACE` | direct A/B | `d060a37e65ed8f82…` |
| PostgreSQL actual plan: `Workers Launched: 5`, `Index Searches: 573671`, `shared hit=3013495 read=0` | `q4-plan-act-pg.out`, `q4-plan-act-pg.json` | `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, TIMING[, FORMAT JSON])` | direct A/B | `07f8cd3247ced26b…` |
| **exact** PostgreSQL index counters: 573,673 scans, 832,822 tuples read, 832,820 fetched | `q4-idxstat-probe.out` | `pg_stat_user_indexes` delta across one statement | direct A/B | see manifest |
| independent replay of the early-exit rule gives 832,820 entries examined | `q4-semijoin-entries.out` | `row_number()` over `ctid` per orderkey, first qualifying position | direct A/B | see manifest |
| plan counterfactuals PostgreSQL: nestloop-off 3.758 s, indexscan-off 3.759 s, serial 3.778 s | `q4-plan-ab-pg.out` | `EXPLAIN ANALYZE` under GUC | direct A/B | see manifest |
| plan counterfactuals CUBRID: serial 7.178 s, USE_HASH 1.776 s, NO_PARALLEL_SUBQUERY 1.789 s, PARALLEL(6) 1.779 s | `q4-plan-ab-cubrid2.out` | wall per statement, identical variants grouped in one connection | direct A/B | see manifest |
| **subquery cache costs ≤0.2%**: 1.7685 s NO_SUBQUERY_CACHE vs 1.7705 s native | `q4-sqcache-nosqcache.out`, `q4-sqcache-native.out` | trailing-8 median of 20 repeats per variant | direct A/B | see manifest |
| CUBRID headline-regime CPU 38.05 core-s/block, `U` 5.40406, TWU 5.4209, tail 0.000 s | `Q04-cubrid-headline-telemetry-run2.json` | per-TID ticks / `SC_CLK_TCK`, actual dt weighting; `U = CPU_block/Σwalls` | profile attribution | see manifest |
| PostgreSQL headline-regime CPU 20.48 core-s/block, `U` 5.21484, TWU 5.4391, tail 0.235 s | `Q04-postgresql-headline-telemetry-run3.json` | same | profile attribution | see manifest |
| `U` cross-check, single-statement regime: CUBRID 5.30551 (−1.8%), PostgreSQL 5.36725 (+2.9%) | `Q04-{cubrid,postgresql}-telemetry-run{1,2,3}.json` | `U = total_query_cpu/client_wall` | profile attribution | see manifest |
| **CUBRID 276,950 read syscalls and 4.5357 GB `rchar` per statement vs PostgreSQL 415 and 1.39 MB** | `Q04-cubrid-headline-telemetry-run2.json`, `Q04-postgresql-headline-telemetry-run3.json` | `/proc/<pid>/io` deltas ÷ 4 statements | profile attribution | see manifest |
| device read 0.00 MiB on both engines | same telemetry JSONs | `/proc/diskstats` delta | direct A/B | see manifest |
| **PostgreSQL working set fits: 830,217 of 1,048,576 buffers, 20.8% headroom** | `q4-workingset.out` | `count(distinct (ctid::text::point)[0])` + `relpages` | direct A/B | see manifest |
| CUBRID working-set projection 8,510 MiB heap-only vs 8,192 MiB pool; model validated on PostgreSQL to 1.6 pp | `q4-workingset.out`, `Q04-causal-card.json` | `1-(1-p)^r`, `p`=0.03824, `r`=orders per heap page | projection | see manifest |
| CUBRID index page count unavailable | `q4-index-pages.txt` | `db_index` catalog probe | UNMEASURED | see manifest |
| CUBRID IPC 1.48, 5.448 CPUs utilized, 294,648 context switches | `perf-stat-cubrid.txt` | `instructions/cycles`, `task-clock/elapsed` | profile attribution | `a083b1f52b7e2583…` |
| PostgreSQL IPC 1.51, 136 context switches, partial PID set | `perf-stat-pg.txt` | `instructions/cycles` | profile attribution | `2701700329f85c20…` |
| CUBRID bands: kernel miss path 12.13%, buffer manager 11.33%, predicates 11.29%; 0 unresolved symbols | `profile-cubrid-flat.txt` | `perf report` self% | profile attribution | see manifest |
| PostgreSQL bands: worker page-table churn 27.43%, extraction 17.69%, buffer 16.06%, predicates 5.09%; 0 unresolved symbols | `profile-pg-flat.txt` | `perf report` self% | profile attribution | see manifest |
| **CUBRID kernel copy is 100% on the buffer-miss path** (`rep_movs_alternative ← copy_page_to_iter ← filemap_read ← pread64 ← fileio_read ← pgbuf_claim_bcb_for_fix ← pgbuf_fix_release`), all in `parallel-query` threads | `profile-cubrid-callgraph.txt` | dwarf call graph | profile attribution | see manifest |
| **PostgreSQL page-table band is `shared_buffers`, not DSM**: fault-in under `ParallelWorkerMain→…→index_getnext_slot`, teardown under `__x64_sys_exit_group→exit_mmap→zap_pte_range` | `profile-pg-callgraph.txt` | dwarf call graph | profile attribution | see manifest |
| DSM exonerated: live segments 32 KiB + 1 MiB, 4 DSM symbols in 113,285 samples, `/dev/shm` 628k of 64000k | `q4-shared-memory-verification.txt`, `profile-pg-callgraph.txt` | direct capture + symbol count | direct A/B | see manifest |
| perf coverage: 109,352 / 113,285 samples, 0 lost, 0 `[unknown]` | `perf-record-cubrid.log`, `perf-record-pg.log` | `perf record` stderr | profile attribution | see manifest |
| perf drivers consumed all rows (26 and 46 statements) | `sink-Q04-cubrid-perf.out`, `sink-Q04-pg-perf.out` | statement result markers | direct A/B | see manifest |
| perf captures ran under external load ≤ 1.5 (`CLEAN`, max 0.938 / 0.632) | `perf-cubrid-bgload.json`, `perf-pg-bgload.json` | 4 Hz load trace | direct A/B | see manifest |
| **sampler does not perturb CUBRID**: block wall flat at 7.07–7.11 s across sampling periods 0.4→0.05 s | `q4-sampler-calibration.csv` | 8x sweep of the sampling period | direct A/B | see manifest |
| **sampling period ≤ 0.1 s is required**: PostgreSQL CPU 13.59 / 18.75 / 21.10 / 20.70 core-s at 0.4 / 0.2 / 0.1 / 0.05 s | `q4-sampler-calibration.csv` | same sweep | direct A/B | see manifest |
| steady-state convergence: PostgreSQL settles ~947 ms by statement 4-5, CUBRID holds 1.752–1.788 s with no trend | `q4-convergence-pg.out`, `q4-convergence-cubrid.out` | 14 consecutive repeats, one connection | direct A/B | see manifest |
| card factors, per-node `W` derivation, residual, `U` cross-check, working-set model | `Q04-causal-card.json` | section 16 formulas | profile attribution | `5face9e8546c0e66…` |
| **superseded pre-WARM-gate blocks** (CUBRID median 1.706 s, PostgreSQL 0.972228 s), excluded from all calculations | `pre-warm-gate/` + `INVALID.json` | see section 5 defect 2 | invalid | see manifest (valid=false) |
| **superseded pre-classifier-fix telemetry** (0.68 core-s misfiled executor→auxiliary), excluded | `pre-classifier-fix/` + `INVALID.json` + `Q04-postgresql-telemetry-samples.json` | see section 5 defect 1 | invalid | see manifest (valid=false) |

Not promoted (dispensable work per SSOT section 19): the raw `perf-*.data` files
(881 MB CUBRID, 900 MB PostgreSQL) and the per-TID sampler dumps of the accepted
telemetry runs, which are fully summarised by the promoted telemetry JSONs and intervals
files. The one sampler dump that carries an independent finding — the pre-classifier-fix
PostgreSQL set that *proves* the executor/auxiliary misclassification — **is** promoted,
under `pre-classifier-fix/`. The manifest records both decisions under `not_promoted`.

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
   `content_fingerprint` follows the Q01–Q03 convention: sha256 of this `report.md` at
   `report_commit`. The record is written only after the report, manifest and registry
   are durable on `origin/main`, so the key it carries is stable. `pending_cleared` is
   `false`.

This satisfies the section 26 gate item ("Notion relations are synced **or** an
idempotent backfill record is durable") without a Notion call. Pending is **not**
cleared: clearing requires a server-side refetch, which only a Notion-capable subagent
may perform. Per the section 21 execution boundary the actual mirror write —
operational state, the Q01–Q22 row, and one page per improvement candidate at the
section 21 content-depth floor — is performed by a dedicated Notion-capable subagent
dispatched during section 23 reconciliation, reading the pushed commit as source of
truth. Sections 3-a, 3-b, 4, 6, 7, 8 and 9 of this report are written to be that
mirror's source, including the full factor table, both engines' plan shapes with a
per-node identity comparison, both engines' top-cost symbols, `file:line` on both sides
of every contrast, the rejected explanations with their rejecting numbers, and the
complete section 18 content for `IMP-008` plus the extended `IMP-002`, `IMP-005` and
`IMP-007`. The mirror must reflect that **`IMP-002` moved P3 → P1** and that
`next_id` is now `IMP-009`.

## 12. Completion checklist

- [x] preflight and correctness status recorded (section 1, section 2); external load
      0.322 core-s/s PASS at preflight, no wait required
- [x] three valid headline values for each completing engine (both completed; neither
      censored), every accepted block verified `CLEAN` against the section 9 external
      load threshold at 4 Hz **and** preceded by a proved WARM steady state
- [x] timeout confirmations — not applicable, neither engine censored (1.77 s and
      0.96 s against a 300 s limit)
- [x] plan, execution, profile and source contrast sections complete
- [x] causal multiplier card has evidence for every factor, with **`F_plan` numeric
      (1.0000) by node-by-node structural equality** — 573,671 index searches and
      526,040 output rows identical on both engines, index entries agreeing to 0.18%
      and independently reproduced at 832,820. Residual is 0 and is declared an
      identity rather than a prediction, with the independent cross-checks that do the
      real work stated in sections 3-a and 8
- [x] Git improvement ledger deduplicated and committed (`IMP-008` allocated with the
      full section 18 field set; `IMP-002` extended with Q04's random-access evidence
      and **raised P3 → P1** on a measured number that refutes its own former P3
      justification; `IMP-007` given a Q04 relation but explicitly **narrowed**, since
      PostgreSQL takes zero physical reads and so offers no asynchrony contrast here;
      `IMP-005` given a Q04 **negative control** that scopes the defect and adds a
      regression pin; `IMP-006` **considered and rejected** for a Q04 relation;
      `next_id: IMP-009`)
- [x] every claim indexed to raw evidence and checksum (236 artifacts; 38 retained as
      invalid under `pre-warm-gate/` and `pre-classifier-fix/` with `INVALID.json` and
      excluded from all calculations)
- [x] report, manifest and registry committed, pushed and reachable from `origin/main`
- [x] `QUERY_COMPLETE` emitted by the worker session
- [ ] **current session removed and absence verified — OUTSTANDING, control-plane
      action.** This worker *is* the Q04 session: tmux session
      `gajae_code_ms7lo36d_6uez896z`. Self-removal would terminate the worker mid-turn
      and make the mandated dual absence check unobservable, so it is deliberately NOT
      claimed here. Per section 22 steps 7-9 and the section 23 `QUERY_COMPLETE`
      action, removal and absence verification are performed from outside this session,
      before any Q05 session is created:

      ```
      gjc session remove gajae_code_ms7lo36d_6uez896z
      gjc session status gajae_code_ms7lo36d_6uez896z      # expect: absent
      tmux has-session -t gajae_code_ms7lo36d_6uez896z     # expect: non-zero exit
      # if remove refuses a live session, exact-target fallback (never by pattern):
      tmux kill-session -t gajae_code_ms7lo36d_6uez896z
      ```

      The Q03 session `gajae_code_ms7i3rb7_gba2sjdp` was verified absent at the start
      of this query by both checks (`gjc session status` →
      `gjc_tmux_session_not_found`, `tmux has-session` → exit 1), so the section 22
      "never two measurement sessions concurrently" rule held throughout Q04.

Harness changes made during Q04 (all under `harness/`, section 5 allowlist):

- `harness/warm_establish.py` (new) — the missing half of the section 12 WARM proof.
  Drives an engine to its own steady state in a separate uncounted connection and
  proves convergence before the contract block is timed: non-monotone trailing window,
  two consecutive window-median shifts ≤ 1.0%, and a 3.0% spread sanity cap. The gate
  targets systematic drift rather than jitter, because CUBRID's own spread reaches 1.2%
  over a 4-statement window at a stable level; the criterion was validated offline
  against both recorded 14-repeat traces before use. Nothing it produces is ever a
  headline value.
- `harness/headline_telemetry.py` (new) — closes Q03's carried-forward gap by sampling
  CPU **inside** the section 12 headline block, so `U = CPU_block / Σ(statement walls)`
  is measured in the regime the headline is defined on instead of imported from a
  single-statement regime. Documents its one attribution rule (`CPU_stmt = U × t_stmt`)
  and the cross-check that tests it, and deliberately does **not** attempt per-statement
  segmentation, because the inter-statement gap is single-digit milliseconds and
  resolving it would need a sampling period fast enough to perturb the block.
- `harness/measure_block.sh` — runs `warm_establish.py` before each attempt, records the
  verdict per attempt, and treats a failed WARM gate as a retryable rejection like the
  load gate rather than as a hard abort.
- `harness/telemetry_run.py` — fixed the PostgreSQL executor/auxiliary misclassification
  (an exiting child's empty `/proc/<pid>/cmdline` fell through to `pg_background`,
  misfiling 0.68 core-s = 12.2% of `total_query_cpu`); a pid's role is now pinned once
  positively identified, and an empty cmdline is skipped rather than guessed.

Known carried-forward gaps, explicitly recorded rather than silently omitted:

- CUBRID actual histogram bucket count remains `UNMEASURED` (opaque `VARBIT` catalog);
  target 300 is configured and verified. Q04's date sarg estimate is accurate to 0.9%,
  so this gap does not bind here.
- CUBRID's accumulating perfmon page counters remain unusable as a per-block gauge
  (Q03's finding, reconfirmed on Q04: identical before and after the block). WARM
  evidence uses the convergence gate, device `read_bytes`, `/proc/<pid>/io`, LRU zone
  conservation and the trace's per-node `ioread`.
- **CUBRID's index page count is not exposed** by `db_index`, so the CUBRID side of the
  working-set accounting is a projection from a model validated on the measured
  PostgreSQL side (1.6 pp), and its index term is omitted entirely. The conclusion does
  not depend on it: the heap terms alone exceed the pool.
- `F_units` carries roughly ±3% of regime uncertainty, quantified in section 3-a from
  the disagreement between the two CPU instruments. It does not disturb any conclusion
  because `F_units` is within 3.5% of 1.0 on either instrument.
- The section 12 regime places PostgreSQL's measured statements **+1.39%** above its own
  long-run steady state, because a fresh backend's parallel workers must populate page
  tables for the 8 GiB `shared_buffers` mapping and one uncounted warmup does not
  amortise that. CUBRID pays **−0.17%**. The contract headline (1.8433x) therefore
  understates CUBRID's deficit against the steady-state ratio (1.8720x) by ~1.5%. The
  contract number is reported as the headline, as section 12 requires; the bias is
  recorded rather than corrected.
- `reports/bootstrap/build-manifest.json` pins `ssot_commit 1d6a5ea6…` while this query
  is pinned at `5912f065…`. The intervening SSOT changes touched the buffer/cache
  contract (already applied), the Notion execution boundary, the improvement-candidate
  quality bar and the shared-memory contract — no engine SHA, schema, statistics,
  parallel-worker or timing term — so no bootstrap finding is invalidated.
- The measurement host is shared and containerised (host-wide `/proc/stat`), so external
  load is invisible to `ps` inside the container. Unlike Q03, Q04 saw no neighbour
  contention: preflight 0.322 core-s/s and every accepted block `CLEAN` with
  `external_max` between 0.53 and 0.94.
- **A cross-query question Q04 raises and does not answer.** Q04 is the first query
  whose headline depended on buffer residency inherited from the preceding stage, and
  the WARM gate now removes that dependence. Q01 and Q03 were re-examined for the same
  pattern from their retained work directories and are clean: drift across the three
  measured statements is +0.08% (Q01 CUBRID) and +0.28% (Q01 PostgreSQL), −0.42% (Q03
  CUBRID) and +0.08% (Q03 PostgreSQL), against Q04's +2.1% before the gate. Q02's work
  directory no longer exists, so its statement series could not be re-checked from raw;
  its committed report records measured statements of 0.353 / 0.357 / 0.353 s (CUBRID)
  and 2.408541 / 2.388589 / 2.395453 s (PostgreSQL) — non-monotone on both engines,
  with within-block sd of 0.652% and 0.423% — which is inconsistent with an unconverged
  decay. That is an inference from the committed report rather than a re-measurement,
  and is recorded as such rather than as a clean bill of health.
- The CUBRID databases live under a repository-internal `.git_ignored_dir`; this is the
  reused SF10 dataset and moving it would be a destructive action outside the cleanup
  manifest, so it was left untouched and only recorded.
