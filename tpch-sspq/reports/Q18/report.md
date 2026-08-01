# Q18 — TPC-H *Large Volume Customer* — CUBRID vs PostgreSQL at SF10

Campaign `tpch-sspq-fk-r1-20260730`. Track: **histogram-enabled controlled
comparison**, **configured node/gather-cap comparison**, **configured-equal
buffer budget**. Not an official TPC-H result; no QphH, no throughput, no claim
about released product versions.

## 1. Identity

| Field | Value |
|---|---|
| campaign_id | `tpch-sspq-fk-r1-20260730` |
| QNN | Q18 — TPC-H *Large Volume Customer* |
| ssot_commit (pinned at session creation) | `41e295dd6531bcfcd77114a21575895dc13e7118` |
| ssot_blob_sha | `510478846bff081d3223d3835069283a7cd2e47b` |
| SSOT drift | **NONE**, verified at preflight *and* at the post-block gate: `HEAD` = `origin/main` = `41e295dd6531bcfcd77114a21575895dc13e7118` and `git rev-parse HEAD:tpch-sspq/SSOT.md` = the pinned blob at both. Both pins were verified with `git rev-parse` and `git hash-object` **before** any measurement started. |
| gjc_session_id | `gajae_code_msa9jlby_r5xvme65` |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (includes PR #7441 merge `b334446d6`) |
| CUBRID build | CUBRID 11.5.0.2366-607f1ee 64bit RelWithDebInfo, gcc 8.5.0, cmake 3.26.5, assertions disabled, not stripped |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13`, ELF Build ID `4df41ee21300bf617bccd5e1d5c8522b074ef86e` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL build | PostgreSQL 20devel, gcc 8.5.0, `--enable-debug --without-llvm`, assertions disabled, JIT disabled, not stripped |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b`, ELF Build ID `5f2cb2987765c612638c278f85cfc85c211fffe1` |
| both hashes vs frozen `reports/bootstrap/build-manifest.json` | **match**, pre-block and post-block (`frozen: true`) |
| databases | CUBRID `tpch_sf10_q1` port 1523 (server PID 1612732, `cub_master` 1433697); PostgreSQL `tpch_sspq` PGDATA `/home/cubrid/pg/pgdata-tpch-sspq` port 5442 (postmaster PID 1433696) |
| ownership gate | `OK` (campaign-owned, correct executable/DB/port) at preflight **and** post-block; no non-campaign server was touched |
| schema | 8 FKs and 8 child B-trees per engine, exact column order; PostgreSQL `convalidated` 8/8 |
| statistics | CUBRID `update_statistics_update_histogram=y`, `default_histogram_bucket_count=300`; PostgreSQL `default_statistics_target=100` |
| parallel | CUBRID `parallelism=6`, `max_parallel_workers=100`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`, `parallel_leader_participation=on`, `max_worker_processes=16` |
| buffer/cache | CUBRID `data_buffer_size=8.0G`; PostgreSQL `shared_buffers=8192MB` |
| shared memory | PostgreSQL `dynamic_shared_memory_type=mmap`. Q18's native PostgreSQL plan contains a **Parallel Hash Join** and a large **Gather Merge**, so §9 requires this be recorded: the setting is load-bearing on this query. |
| cpuset / NUMA | SUT+client CPUs 0–15 node0, collectors 20–23. All engine TIDs on-cpuset **before** (34 TIDs, 0 off) and **after** (35 TIDs, 0 off) |
| external load | 0.256 core-s/s at preflight, 0.280 core-s/s at post-block (threshold 6.0) |
| orphans after the run | 0 `csql`, 0 `psql`, 0 PG parallel workers |
| engine block order | Q18 is **even** → PostgreSQL block first, then CUBRID (§12) |
| query provenance | canonical / active-CUBRID / active-PG all SHA-256 `4f23d144b8ecadd2a0a108849da6605d0e2dd5f14d5f0265d39e24011457e87f`; `queries/diff/q18.diff` **0 bytes** |

### A statistics-catalog note that is *not* a contract failure

PostgreSQL's `pg_stat_user_tables` reports `last_analyze=never` /
`last_autoanalyze=never` for all eight relations. This is an **activity-counter**
artifact (the stats file was reset at some point after bootstrap), not a missing
`ANALYZE`: `reltuples`/`relpages` are populated on every relation and `pg_stats`
carries full histograms for every Q18 column — `l_orderkey`, `l_partkey`,
`o_custkey`, `o_orderkey`, `o_totalprice`, `o_orderdate`, `c_custkey`, `c_name`
all have **101 histogram bounds** (= `default_statistics_target` 100 + 1), and
`l_quantity` carries a **50-entry MCV** list with `n_distinct=50`, which is the
correct representation for a 50-value domain. The identical `last_analyze=never`
appears in Q17's preflight, so this is a stable campaign-wide catalog state and
not something Q18 introduced.

## 2. Correctness

`result-equivalent-at-SF10`.

| | value |
|---|---|
| rows | **100** on both engines (`LIMIT 100`) |
| ordering | `ORDER BY o_totalprice desc, o_orderdate` — compared as an **exact ordered sequence** (§11) |
| comparison rule | text, integers, dates, NULLs, row count and row multiset matched exactly |
| decimal handling | raw decimal text preserved; the 1e-12 relative tolerance was never needed — every decimal matched byte-for-byte |
| first differing row | none |
| censoring | none — neither engine approached the 300 s timeout (CUBRID 37.5 s, PostgreSQL 41.8 s) |
| artifact | `q18-correctness.json`, full result sets `q18-correctness-cubrid.out` (6,713 B) / `q18-correctness-postgresql.out` (6,312 B) |

### Dialect: zero changes

`queries/diff/q18.diff` is **0 bytes**. `queries/q18-pg.sql` is byte-identical to
`queries/q18-cubrid.sql`, which is byte-identical to the canonical source
`/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q18.sql`; all three
SHA-256 `4f23d144…57e87f`. There is no dialect artifact on Q18 and no syntax
difference that could explain any part of the gap. Note in particular that the
`TO_CHAR(o_orderdate,'YYYY-MM-DD')` projection and the `LIMIT 100` are in the
**canonical** file and are therefore identical on both sides.

### Independent ground truth, both engines

Seven `count(*)` statements executed separately on **each** engine, outside any
plan's own instrumentation (`q18-groundtruth-cubrid.out`, `q18-groundtruth-pg.out`
— **identical**):

| key | value | role |
|---|---|---|
| `lineitem_total` | 59,986,052 | rows the subquery must aggregate |
| `orders_total` | 15,000,000 | |
| `customer_total` | 1,500,000 | |
| `subquery_groups_prehaving` | **15,000,000** | distinct `l_orderkey` groups the GROUP BY forms — the number the 2 MB hash table is asked to hold |
| `bigorders` | **624** | groups surviving `HAVING sum(l_quantity) > 300` |
| `rows_into_final_group` | **4,368** | lineitem rows entering the outer grouping |
| `final_groups` | **624** | groups emitted before `LIMIT 100` |

Both engines' actual plans agree with these independently: PostgreSQL's
`GroupAggregate` reports `Rows Removed by Filter: 14999125` with `rows=624`
(14,999,125 + 624 = 15,000,000 ✓) and CUBRID's trace reports
`GROUPBY (… rows: 624)` and `SCAN (index: fk_lineitem_orders … rows: 4368)`.

## 3. Headline timings and causal multiplier card

### 3-a. Causal multiplier card

```text
R_wall 0.896281x [wall, median of 3 per engine; CUBRID is 1.1157x faster]
= F_plan  0.734231x [plan-shape; same-engine PostgreSQL A/B, section 4-d]
× F_units 1.069863x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   1.140993x [total query CPU-seconds]

F_cpu 1.140993x [total query CPU-seconds]
= F_work 0.500036x [lineitem row-fetches performed by the plan: 59,990,420 vs 119,972,104]
× F_cost 2.281820x [1684.7 ns vs 738.3 ns of total query CPU per lineitem row-fetch]
```

**Read the card in one line: CUBRID wins Q18, but it wins entirely on `F_plan`,
and `F_plan` is a PostgreSQL plan-choice defect rather than a CUBRID execution
advantage.** Measured against PostgreSQL's *own better plan*, CUBRID is 14.1%
behind on CPU and 7.0% behind on active units.

- **`F_plan` 0.734231x — PostgreSQL's optimizer picks a plan 1.362x slower than
  one PostgreSQL can already produce.** Native PostgreSQL places the subquery's
  `GroupAggregate` on the **inner side of a Merge Join**, and the inner side of a
  merge join is not partitioned, so **every one of the 6 parallel units
  re-executes the entire 60M-row index scan**: `q18-plan-act-pg.out` shows
  `Index Scan using idx_fk_lineitem_orders … rows=59985038.00 loops=6`, with each
  worker independently reporting ~59,986,052 rows. With `enable_indexscan=off`
  the same query becomes `Parallel Seq Scan → Partial HashAggregate → Sort →
  Gather Merge`, whose scan **is** partitioned (`rows=9997675.33 loops=6` =
  59,986,052 exactly), and the measured median drops **41.787122 s → 30.681412 s**.
- **`F_units` 1.069863x and `F_cpu` 1.140993x — on the controlled pair CUBRID
  loses both.** CUBRID runs at U 2.69842 against PostgreSQL-noidx's 2.88694, and
  spends 101.06 core-s against 88.57 core-s.
- **`F_work` is 0.500036x and `F_cost` is 2.281820x.** CUBRID touches almost
  exactly **half** as many lineitem rows (it reaches the outer lineitem through
  `fk_lineitem_orders` for just 4,368 rows, where PostgreSQL-noidx re-scans the
  whole table), and pays **2.28x more CPU per row touched**.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 0.734231x | plan shape (subquery scan partitioned vs replicated) | wall-seconds, same engine, same block regime | `T_P_noidx / T_P_native` = 30.681412 / 41.787122 | `Q18-postgresql-noidx-headline.json`, `Q18-postgresql-headline-block1.json`, `q18-plan-act-pg.out`, `q18-plan-act-pg-noidx.out` | direct A/B (same engine, controlled plan) |
| `F_units` | 1.069863x | active execution units | CPU-seconds / wall-second over the §12 block | `U_P'/U_C` = 2.88694 / 2.69842 | `Q18-postgresql-noidx-headline-telemetry.json`, `Q18-cubrid-headline-telemetry.json` | profile attribution |
| `F_cpu` | 1.140993x | total query CPU-seconds | per query execution | `CPU_C/CPU_P'` = 101.064 / 88.575 | same telemetry JSONs × the block medians | profile attribution |
| `F_work` | 0.500036x | lineitem row-fetches performed by the plan | one statement | `59,990,420 / 119,972,104` | `q18-groundtruth-*.out`, `q18-trace-cubrid.out`, `q18-plan-act-pg-noidx.out` | direct A/B (ground truth) |
| `F_cost` | 2.281820x | CPU-seconds per lineitem row-fetch | lineitem row-fetches | `(CPU_C/W_C)/(CPU_P'/W_P')` = 1684.7 ns / 738.3 ns | `q18-causal-card.json` | profile attribution |

**Anchor direction and denominator discipline (§16).** `F_plan` is anchored on
the **PostgreSQL native → PostgreSQL controlled** pair; `F_units` and `F_cpu` are
then computed on the **remaining controlled cross-engine pair**, CUBRID-native vs
PostgreSQL-`noidx`. No native denominator is mixed with a controlled one. The
anchor is on the PostgreSQL side because **CUBRID has no switch that changes only
this decision** — CUBRID already materialises the uncorrelated subquery once and
has no plan in its space that replicates it — whereas PostgreSQL has exactly such
a switch.

**Reconstruction residual: `F_plan × F_units × F_cpu` = 0.896280869x against
`R_wall` 0.896280869x, residual `-0.0000000000%`.** CPU is attributed as
`U × t_median` on the same block regime the wall is defined on, so the identity
is exact by construction once `F_plan` is factored out on its own same-engine
pair. Independent cross-checks: TWU (2.7041 vs `U` 2.69842 on CUBRID, +0.21%;
2.8826 vs 2.88694 on PostgreSQL-noidx, −0.15%), the PostgreSQL-serial A/B
(section 4-d), and `perf stat` (section 6-c).

### Error budget, stated before any factor is interpreted

| | contract block medians | spread |
|---|---|---|
| CUBRID, 3 gated §12 blocks | 37.452998 / 37.131998 / 37.471999 s | **0.9078%** |
| PostgreSQL, 3 gated §12 blocks | 41.787122 / 42.345682 / 42.455839 s | **1.6003%** |
| within-block sd (block 1) | CUBRID 0.159632 s (0.426%), PostgreSQL 0.211618 s (0.506%) | |

Any factor inside ~1.6% is not interpreted. `F_plan` 0.734231x is **16.6x** the
PostgreSQL band; `F_cost` 2.281820x is far outside it. `F_units` 1.069863x
(+7.0%) is **4.4x** the PostgreSQL band and is interpreted, but with the caveat
that it is the smallest of the three factors. The redundant-`DISTINCT` A/B
(+0.188%, section 9) is **inside** the band and is explicitly *not* interpreted
as an effect.

### 3-b. Headline timings

| Field | CUBRID | PostgreSQL |
|---|---|---|
| measured statement 1 | 37.545999 s | 42.098848 s |
| measured statement 2 | 37.452998 s | 41.787122 s |
| measured statement 3 | 37.234999 s | 41.695059 s |
| **median (headline)** | **37.452998 s** | **41.787122 s** |
| mean | 37.411332 s | 41.860343 s |
| within-block sd | 0.159632 s | 0.211618 s |
| uncounted warmup statement | 37.603999 s | 43.639275 s |
| **median wall ratio** | **0.896281x** — **CUBRID is 1.115722x faster** | |
| correctness | `result-equivalent-at-SF10` | |
| censoring | none | |

Regime `single-query-repeat WARM`, metadata connection mode
`single-connection-four-statements`, one direct campaign connection per block
(CUBRID `csql -C`, PostgreSQL one `psql` Unix-socket simple-query connection),
one uncounted warmup then three measured statements, no reconnect and no prepare
between them, every row fully consumed into a campaign-owned sink under
`work/Q18` with no terminal rendering. Connection establishment is excluded.

### All three blocks per engine

| Block | CUBRID measured (s) | median | PostgreSQL measured (s) | median |
|---|---|---|---|---|
| 1 (headline) | 37.545999 / 37.452998 / 37.234999 | 37.452998 | 42.098848 / 41.787122 / 41.695059 | 41.787122 |
| 2 | 37.131998 / 37.224999 / 37.040999 | 37.131998 | 42.649502 / 42.345682 / 41.952817 | 42.345682 |
| 3 | 37.471999 / 37.549998 / 37.426999 | 37.471999 | 42.861934 / 42.455839 / 41.678117 | 42.455839 |

Block 1 is the headline for both engines. **All six blocks were accepted on
attempt 1** under both the strict per-sample rule and the contract-window rule;
external SUT-set load over the six blocks stayed at mean 0.125–0.241 and max
1.657 core-s/s against the 6.0 threshold.

### Sink integrity — and why the sink SHA differs between blocks

Sink size is byte-identical across all three blocks per engine (CUBRID 47,364 B;
PostgreSQL 25,386 B), but the PostgreSQL **sink SHA-256 differs between blocks**.
That is not a result difference: `psql` writes its `\timing` lines into the same
stream the harness hashes, so the sink contains four `Time: NNNNN.NNN ms` lines
whose digits change every run while their byte length does not. Stripping only
those lines makes the result payload **byte-identical across blocks**, SHA-256
`2137a4f1f52b89ac215d9bd36091b066f2d5c2a1ee09d18478c7fc253695b679` for blocks 1
and 2 alike (401 lines = 4 statements × 100 rows + trailing newline). The
contract hash is retained as specified (§12: hash computed after the timer
stops); this note records what it does and does not prove.

### Controlled variants (never headline values)

| Configuration | median (s) | vs its own native | U | TWU | CPU/block |
|---|---|---|---|---|---|
| CUBRID native | 37.452998 | — | 2.69842 | 2.7041 | 373.98 core-s |
| CUBRID `NO_HASH_AGGREGATE` on the subquery | 40.173998 | **1.0727x slower** | 1.89108 | 1.8912 | 303.01 core-s |
| PostgreSQL native | 41.787122 | — | 5.67482 | 5.6667 | 970.36 core-s |
| PostgreSQL `enable_indexscan=off` (**F_plan anchor**) | 30.681412 | **1.3620x faster** | 2.88694 | 2.8826 | 350.46 core-s |
| PostgreSQL `max_parallel_workers_per_gather=0` | 24.282188 | **1.7209x faster** | — | — | — |
| CUBRID subquery only, `DISTINCT` present | 34.570999 | +0.188% (inside band) | — | — | — |
| CUBRID subquery only, `DISTINCT` removed | 34.505999 | — | — | — | — |

Every variant passed the **same** §9 load gate and carries its own WARM proof;
every artifact is tagged so it can never overwrite a native block.

### WARM proof

WARM is proved, not assumed, and on Q18 the proof is unusually clear-cut:
**neither engine performs a single physical disk read during a measured block**,
yet both move tens of gigabytes through `read()`.

| | CUBRID | PostgreSQL |
|---|---|---|
| WARM gate | converged, half-split trend +0.4396% / −1.1808% / +0.4396% within 2.00% | converged, +0.0039% / −0.9501% / −1.7993% within 2.00% |
| `/proc/<server>/io` `read_bytes` delta per block | **65,536 B / 0 B / 16,384 B** | **0 B / 0 B / 0 B** |
| `/proc/<server>/io` `rchar` delta per block | 67.96 / 67.98 / 68.00 GB (≈16.99 GB per statement) | 102.97 / 103.08 / 103.08 GB (≈25.74 GB per statement) |
| engine buffer counter | `Num_data_page_ioreads` delta **0** — **counter unusable, see below** | `pg_statio` `heap_blks_read` delta 5,689,168 blocks/block (≈11.1 GB per statement) |
| working set vs 8192 MB budget | `lineitem` heap alone is 10,670.9 MiB — **does not fit** | `lineitem` heap alone is 8,790 MB — **does not fit** |

The important reading: **`read_bytes` is zero, so nothing reaches the disk**, but
`rchar` is enormous because *neither engine's 8 GB buffer can hold the 10.7 GB
`lineitem` table*, so both re-read it from the OS page cache every statement.
This is symmetric between the engines and is exactly the situation §9's
`configured-equal buffer budget` label exists to describe: equal budgets, both
too small for this query's working set, and the difference therefore *not*
attributable to buffer sizing. CUBRID's 16.99 GB/statement is `lineitem`
(10.67 GiB) plus its temp-spill re-reads (422,017 pages × 16 KiB = 6.44 GiB) —
the two sum to 17.11 GiB, matching the measurement.

**`cubrid statdump` remains unusable on this server**, reconfirming the Q14/Q16
finding: bracketing a whole four-statement block gives delta 0 on
`Num_data_page_fetches`, `Num_data_page_ioreads` and every other counter while
`/proc` recorded real activity over the same window. The counters are retained
with an explicit invalid reason and are **excluded from every calculation**;
Q18's CUBRID buffer evidence rests on `/proc/<cub_server>/io`.

## 4. Plan

### 4-a. CUBRID (estimated, `SET OPTIMIZATION LEVEL 514`)

```
temp(order by)
  temp(group by)                                   sort 1,2,3 asc   cost 23978143 card 25588498
    idx-join  outer: idx-join  outer: idx-join
                                 outer: sscan av1861 (the materialised subquery)  card 14929885
                                 inner: iscan orders  pk_orders_o_orderkey
                               inner: iscan customer  pk_customer_c_custkey
              inner: iscan lineitem  fk_lineitem_orders

subquery av1861:
temp(distinct)                                     cost 1308583 card 59986052
  temp(group by)   subplan: sscan lineitem         sort 1 asc  cost 1070742 card 59986052
```

Two things are worth naming. First, CUBRID rewrites `o_orderkey IN (…)` into a
**materialised derived table `av1861` joined once**, and drives the join *from*
that derived table into `orders`/`customer`/`lineitem` by primary/foreign key —
so the expensive subquery is evaluated exactly once. Second, CUBRID's estimate
for `av1861` is **14,929,885 rows against a true 624** — the `HAVING
sum(l_quantity) > 300` selectivity is not estimated at all. That estimate is
wrong by 4 orders of magnitude yet **costs Q18 nothing**, because the plan it
produces (drive from the subquery, probe by unique key) is the same plan a
correct estimate would produce.

### 4-b. PostgreSQL (actual, `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, TIMING)`)

```
Limit                                                    actual 48154..48473 ms  rows=100
  Sort  (top-N heapsort, 48kB)   Key: o_totalprice DESC, to_char(o_orderdate)
    Finalize GroupAggregate                              rows=624
      Gather Merge   Workers Planned: 5  Launched: 5
        Partial GroupAggregate                           rows=104 loops=6
          Sort (quicksort ~71kB)  Key: c_custkey, o_orderkey
            Nested Loop                                  rows=728 loops=6
              Parallel Hash Join   Inner Unique: true    rows=104 loops=6
                Merge Join         Inner Unique: true    rows=104 loops=6   (584..48007 ms)
                  Parallel Index Scan orders_pkey        rows=2499749.67 loops=6
                  GroupAggregate                         rows=624 loops=6   (6..47244 ms)
                    Filter: sum(l_quantity) > 300;  Rows Removed by Filter: 14999125
                    Index Scan idx_fk_lineitem_orders    rows=59985038.00 loops=6  (0.038..35432 ms)
                Parallel Hash  <- Parallel Seq Scan customer   rows=250000 loops=6
              Index Scan idx_fk_lineitem_orders          rows=7 loops=624
Execution Time: 48473.280 ms      Buffers: shared hit=6167587 read=1558250
```

**The single most important line in this report** is
`Index Scan using idx_fk_lineitem_orders … rows=59985038.00 loops=6`. Because the
subquery's `GroupAggregate` is the **inner** input of a `Merge Join` that sits
inside the parallel region, it is *not* partitioned: the leader and all five
workers each scan the whole 59,986,052-row index and each discards the same
14,999,125 groups. Per-worker rows confirm it individually (59,979,968 /
59,986,052 / 59,986,052 / 59,986,052 / 59,986,052, leader 59,986,052). Total
lineitem index+heap fetches for the subquery: **359,910,228**, six times what the
query logically requires.

### 4-c. Plan comparison summary

| | CUBRID | PostgreSQL (native) |
|---|---|---|
| subquery evaluation | once, materialised as `av1861` | **6×, once per parallel unit** |
| subquery input access | `sscan lineitem`, parallel, **partitioned** (6 workers × ~10M rows) | `Index Scan idx_fk_lineitem_orders`, **replicated** (6 × 59.99M rows) |
| subquery aggregation | partial hash → sort-based group-by, **spills 422,017 temp pages** | streaming `GroupAggregate` in index order, **no sort, no spill** |
| semijoin dedup | extra `temp(distinct)` node (redundant; see §7) | `reduce_unique_semijoins` proves uniqueness → plain inner join, `Inner Unique: true` |
| outer lineitem access | `iscan fk_lineitem_orders`, 4,368 rows | `Index Scan idx_fk_lineitem_orders`, 624 searches × 7 rows |
| final aggregation | `temp(group by)` then `temp(order by)` | `Partial GroupAggregate → Gather Merge → Finalize GroupAggregate → top-N Sort` |
| parallelism actually achieved | scan phase ~6 units, **group-by phase 1 unit** | ~5.67 units throughout |

Each engine gets one thing right that the other gets wrong. CUBRID evaluates the
subquery once but then aggregates it serially with a 6.4 GiB spill. PostgreSQL
aggregates without any sort or spill but pays for it six times over.

### 4-d. The F_plan anchor: PostgreSQL native → PostgreSQL `enable_indexscan=off`

`enable_indexscan=off` is the only switch that changes this one decision, and it
changes it exactly: the subquery's access path becomes a **Parallel Seq Scan**,
which the parallel machinery *does* partition.

```
Hash Join  (lineitem.l_orderkey = lineitem_1.l_orderkey)   Inner Unique: true
  Seq Scan on lineitem                        rows=59986052.00 loops=1     (outer side)
  Hash <- Finalize GroupAggregate             rows=624 loops=1
           Gather Merge  Workers Launched: 5  rows=15001773
             Sort  Key: l_orderkey
               Partial HashAggregate          rows=2500295.50 loops=6   Planned Partitions: 16
                 Parallel Seq Scan lineitem_1 rows=9997675.33 loops=6   <-- PARTITIONED
Execution Time: 33135.660 ms
```

`9997675.33 × 6 = 59,986,052` — exactly the table, scanned exactly once in total,
and exactly what CUBRID's parallel `sscan` does (`readrows: 9938887..10011920`
per worker). Measured through the full §12 block regime with its own WARM proof:
**30.681412 s against native 41.787122 s**, and total block CPU **350.46 core-s
against 970.36** — a 2.77x CPU reduction from deleting redundant work.

**Independent confirmation from the opposite direction.** Setting
`max_parallel_workers_per_gather=0` — keeping the native index-scan plan but
allowing only one unit, which makes replication impossible — gives
**24.282188 s, 1.7209x faster than native PostgreSQL**. Two different switches,
two different resulting plan shapes, same conclusion: PostgreSQL's parallel plan
for Q18 is slower than its own serial plan, and the cause is that the parallel
plan multiplies the dominant scan instead of dividing it.

## 5. Execution telemetry

| | CUBRID native | PostgreSQL native | PostgreSQL `noidx` (controlled) |
|---|---|---|---|
| block wall | 138.592 s | 170.994 s | 121.395 s |
| telemetry-block median | 34.662999 s | 42.544345 s | 30.281805 s |
| `executor_cpu` | 359.22 core-s | 968.84 core-s | 340.48 core-s |
| `auxiliary_query_cpu` | 14.76 core-s | 1.52 core-s | 9.98 core-s |
| `total_query_cpu` | **373.98 core-s** | **970.36 core-s** | **350.46 core-s** |
| `U` (CPU-s / wall-s) | 2.69842 | 5.67482 | 2.88694 |
| **TWU** (actual timestamp deltas) | 2.7041 | 5.6667 | 2.8826 |
| max simultaneous active units | 6.9082 | 6.5073 | 7.1925 |
| serial tail | **12.548 s** | 0.236 s | 2.903 s |
| samples | 1,254 | 1,482 | — |
| load verdict | CLEAN | CLEAN | CLEAN |

`executor_cpu` is CUBRID's query threads inside `cub_server` and PostgreSQL's
leader backend plus parallel workers; `auxiliary_query_cpu` is `csql` /
`psql` and attributable background threads. TWU is computed from actual sample
timestamp deltas, never a nominal interval, and agrees with `U` to within 0.21%
on CUBRID and 0.15% on PostgreSQL-noidx.

### The decisive telemetry result: CUBRID spends 63.4% of Q18 at one active unit

Time-weighted distribution of active units across CUBRID's whole 4-statement
block (`Q18-cubrid-headline-telemetry-intervals.json`, 1,253 real intervals):

| active units | wall time | share |
|---|---|---|
| ~0 | 2.24 s | 1.6% |
| **~1** | **89.10 s** | **63.4%** |
| ~2 | 4.60 s | 3.3% |
| ~4 | 0.45 s | 0.3% |
| ~6 | 44.11 s | 31.4% |
| total | 140.50 s | |

The per-statement shape repeats cleanly four times (5 s buckets, mean units):

```
4.7 6.1 3.2 | 1.2 1.2 1.0 1.0 | 5.6 6.1 2.8 | 1.2 1.1 1.0 1.0 |
5.7 6.3 2.6 | 1.2 1.1 1.0 1.0 | 6.1 6.1 2.2 | 1.2 1.1 1.0 0.9
```

Roughly 11 s at ~6 units (the parallel heap scan) followed by ~22 s at 1 unit
(the sort-based group-by). This matches CUBRID's own trace exactly —
`SCAN … heap time: 11829 … parallel workers: 6` then
`GROUPBY (time: 29563, hash: partial, sort: true, page: 422017, ioread: 459086)`.
**For 63.4% of Q18's wall clock, 15 of the 16 SUT cores are idle.**

### CUBRID trace (non-headline, `SET TRACE ON`)

```
SELECT (time: 41430, fetch: 34647311, fetch_time: 10574, ioread: 1036316)
  SCAN (temp) readrows: 624, rows: 624
    SCAN (index: orders.pk_orders_o_orderkey) readkeys: 624, rows: 624
      SCAN (index: customer.pk_customer_c_custkey) readkeys: 623, rows: 623
      MEMOIZE (time: 1, hit: 1, miss: 623, size: 201KB, enabled: true)
        SCAN (index: lineitem.fk_lineitem_orders) readkeys: 624, rows: 4368
  GROUPBY (time: 7, hash: true, sort: true, page: 0, rows: 624)
  ORDERBY (time: 0, sort: true)
  SUBQUERY (uncorrelated)
    SELECT (time: 41400, fetch: 34635715, ioread: 1036124)
      SCAN (table: lineitem) heap time: 11829, readrows: 59986052
           (parallel workers: 6, readrows: 9938887..10011920, gather: mergeable list)
      GROUPBY (time: 29563, hash: partial, sort: true, page: 422017, ioread: 459086, rows: 624)
```

The subquery is 41,400 ms of the 41,430 ms statement — Q18 *is* its subquery on
CUBRID. Within it, the parallel scan is 11,829 ms and the serial group-by is
**29,563 ms (71.4%)**. The outer join pipeline costs 30 ms.

## 6. Profile

Perf is non-headline. All numbers below come from verified PID attachment
(never an all-CPU profile).

### 6-a. Capture integrity — one failure and one repair, both recorded

The first capture used `--call-graph dwarf`. On PostgreSQL the record step
attached to a leader PID that had already exited and wrote **0 samples**
(`q18-perf-pg.log`: `[coverage] flat lines=0`). On CUBRID it *ran* but the
per-sample stack copy throttled the sampler to **1,575 samples over 85 s**
(~18/s against a 999 Hz target), and at that rate the query threads were
statistically absent: the surviving histogram was 49.48% `dwb-flush-block`,
17.97% `vacuum-master` — background daemons. **Neither profile was used for any
number in this report.** Both were re-captured with frame-pointer-free flat
sampling (no per-sample stack copy, therefore no throttling), and the PostgreSQL
call graph was additionally re-captured with a live leader. `perf stat` from the
original run succeeded and is retained unchanged.

| | samples | unresolved symbols | comm distribution |
|---|---|---|---|
| CUBRID flat (repaired) | 252,168 | **0** | `parallel-query` 69.11%, `transaction` 27.25%, `pgbuf-page-flush` 3.38% |
| PostgreSQL (repaired) | 268,774 | **0** | `postgres` 100% |

### 6-b. Top-cost symbols

**PostgreSQL** (`profile-pg-flat.txt`) — the replication cost is visible directly
as buffer-lock traffic:

| % | symbol |
|---|---|
| **33.48** | `LockBufferInternal` |
| **15.19** | `BufferLockUnlock` |
| 5.08 | `ExecInterpExpr` |
| 3.12 | `tts_buffer_heap_getsomeattrs` |
| 1.94 | `heap_hot_search_buffer` |
| 1.80 / 1.75 | `AllocSetAlloc` / `AllocSetReset` |
| 1.57 | `ExecAgg` |
| 1.30 | `heapam_index_fetch_tuple` |
| 1.25 / 0.81 / 0.51 / 0.47 | `accum_sum_add` / `do_numeric_accum` / `accum_sum_final` / `numeric_avg_accum` |
| 0.83 / 0.67 / 0.45 | `_bt_readpage` / `_bt_next` / `btgettuple` |

**`LockBufferInternal` + `BufferLockUnlock` = 48.67% of PostgreSQL's cycles.**
That is the mechanical signature of six units concurrently walking the *same*
index and heap pages: every one of the 359,910,228 row-fetches takes and releases
a buffer content lock, and six units contend on identical pages.

**CUBRID** (`profile-cubrid-flat.txt`), resolved coverage 77.55% at a 0.30%
limit, banded:

| band | % | representative symbols |
|---|---|---|
| hash aggregation | **13.97** | `qdata_agg_hkey_compare` 3.44, `qexec_hash_gby_agg_tuple` 2.79, `mht_get` 2.07, `qdata_save_agg_hentry_to_list` 1.66, `mht_rem` 1.53 |
| value/type layer | 12.30 | `tp_value_compare_with_error` 2.21, `qdata_get_tuple_value_size_from_dbval` 1.99, `pr_clear_value` 1.60, `float_numeric_db_value_add` 1.55 |
| heap scan + materialisation | 11.55 | `heap_attrinfo_read_dbvalues` 3.40, `parallel_scan::slot_iterator::next_qualified_slot_with_peek` 1.53, `heap_next_1page` 1.35 |
| sort / list-file merge | 7.66 | `qfile_compare_partial_sort_record` 3.27, `sort_run_merge` 0.80 |
| allocator | 7.28 | `mspace_free` 2.38, `mspace_malloc` 1.48, `__tls_get_addr` 1.28 |

The `transaction` comm — CUBRID's **single serial connection thread** — accounts
for 18.36 of the 77.55 resolved points, and its own top entries are exactly the
sort-merge of the spilled aggregate: `qfile_compare_partial_sort_record` 3.27%,
`pgbuf_fix_release` 1.74%, `pgbuf_unfix` 1.36%,
`qdata_load_agg_hentry_from_tuple` 1.24%, `sort_run_merge` 0.80%. This is the
same 63.4%-at-one-unit phase seen in telemetry, now attributed to symbols.

### 6-c. `perf stat` cross-check (native pair)

| | CUBRID | PostgreSQL |
|---|---|---|
| cycles | 492,632,543,133 | 1,298,539,004,044 |
| instructions | 875,393,310,413 | 1,588,826,160,817 |
| IPC | **1.78** | **1.22** |
| task-clock | 178,559.15 ms | 475,169.14 ms |
| CPUs utilized | 2.101 | 5.280 |
| window | 85.002 s | 90.002 s |

PostgreSQL's 5.280 CPUs-utilized corroborates telemetry `U` 5.67482 once the
window's idle edges are removed (475.169 s / ~84 s of statement = 5.66).
Instruction ratio C/P = 0.551 and cycle ratio 0.379 bracket the native-pair CPU
ratio 0.426 from either side; the spread is the IPC gap (1.78 vs 1.22), i.e.
PostgreSQL retires *more* instructions at *worse* IPC — the expected signature of
lock-contended memory traffic rather than arithmetic work.

## 7. Source contrast

| Item | CUBRID `file:line` | PostgreSQL `file:line` | Difference | Class |
|---|---|---|---|---|
| Parallelism of a sort-based GROUP BY | `src/storage/external_sort.c` `sort_check_parallelism()`, `SORT_GROUP_BY`/`SORT_ANALYTIC` branch: `/* hash_eligible is GROUP_BY only …; skip parallelism when set */ if (px == NULL || px->hash_eligible) { return 1; }`. `hash_eligible` originates as `buildlist->g_hash_eligible`, set at **XASL-generation time** from query *shape* only — `src/parser/xasl_generation.c:16556-16568` sets it `true` unless the `NO_HASH_AGGREGATE` hint is present and `pt_is_hash_agg_eligible` rejects a select-list/HAVING item. It is never re-evaluated after the executor degrades to sorting (`hash: partial` in `q18-trace-cubrid.out`). Consequence: the 29,563 ms group-by runs at **1 unit**. | `src/backend/executor/nodeAgg.c` implements partial/final aggregation as ordinary parallel-aware plan nodes; the planner emits `Partial GroupAggregate → Gather Merge → Finalize GroupAggregate` (`q18-plan-act-pg.out`), so aggregation parallelism is a *plan* property and carries no dependency on whether hashing was chosen. In the `noidx` anchor the same query runs `Partial HashAggregate` at `loops=6` and finalises through `Gather Merge`. | CUBRID's sort-based aggregation has **no parallel path reachable for a hash-eligible query**, independent of what the executor actually did at runtime. 89.10 s of CUBRID's 140.50 s block at one active unit. | structural absence |
| Deduplication of an `IN (subquery)` result | `src/parser/type_checking.c:5037` — for any range expression whose `arg2` is a query, `expr->info.expr.arg2->info.query.all_distinct = PT_DISTINCT;` is applied **unconditionally** (comment: *"duplicates are not relevant; order by is not relevant"*). No check exists for a subquery that is already distinct. Execution is a real extra pass: `QFILE_FLAG_DISTINCT` builds a sort list over every column (`src/query/list_file.c:1284-1300`) and the list file is sorted and deduplicated. Visible as `temp(distinct)` above `temp(group by)` in `q18-plan-est-cubrid.out`, costed at 1,308,583 against 1,070,742. | `src/backend/optimizer/plan/planmain.c:237` calls `reduce_unique_semijoins()`; `src/backend/optimizer/plan/analyzejoins.c:1042` → `rel_supports_distinctness()` `:1118` → `innerrel_is_unique()` `:1524` → `rel_is_distinct_for()` `:1178` → `query_is_distinct_for()` `:1328`, whose `:1372-1389` proves distinctness *because* the subquery has a `GROUP BY` covering the join columns, then deletes the semijoin's `SpecialJoinInfo` so SEMI becomes a plain inner join. Visible as `Inner Unique: true` on the Merge Join in `q18-plan-act-pg.out`. | CUBRID has no "already distinct" proof and cannot drop the `DISTINCT` it added. **Measured Q18 effect: +0.188%, inside the 1.6% error band — not an effect on this query** (see §9). | structural absence |
| Evaluation count of an uncorrelated `IN` subquery | `src/optimizer/rewriter/query_rewrite_subquery.c:165` → `mq_make_derived_spec()` (`src/parser/view_transform.c:10918`) materialises the subquery as one derived spec `av1861` appended to `FROM`, evaluated **once** and then joined by key. | `src/backend/optimizer/plan/subselect.c:1341` `convert_ANY_sublink_to_join()` pulls the sublink up as a `JOIN_SEMI` sub-select RTE. When the resulting subquery path lands on the **inner** side of a `Merge Join` inside a parallel region it is re-executed per unit — `rows=59985038.00 loops=6` in `q18-plan-act-pg.out` — because inner inputs of a join are not partitioned. | CUBRID does 59,986,052 subquery row-fetches; PostgreSQL does 359,910,228 for the identical logical work. This is the whole of `F_plan` 0.734231x. | same stage, lower measured cost (**CUBRID better**) |
| Aggregation memory budget | `max_agg_hash_size = 2.0M` and `sort_buffer_size = 2.0M` (server defaults, `cubrid paramdump`) while the campaign grants `data_buffer_size = 8192M`. The subquery must form **15,000,000 groups**; a 2 MB hash table holds a negligible fraction, so the executor degrades to sorting and spills **422,017 temp pages / 459,086 ioreads**. `max_agg_hash_size` is not session-settable (`ERROR: Cannot change system parameter`). | PostgreSQL sizes hash aggregation from `work_mem` and, when it does not fit, plans `Partial HashAggregate` with `Planned Partitions: 16` (`q18-plan-act-pg-noidx.out`) — a spill strategy chosen and costed *by the planner*, not a runtime collapse into a global sort. | The 8 GB buffer budget is unreachable by the operator that dominates Q18. Raising only the session-settable half (`sort_buffer_size` 2M→256M) cuts spill pages 65.5% and the traced statement 6.93% (§9). | same stage, lower measured cost |

**Absence claims — searched paths, symbols and patterns.** For the "already
distinct" proof the searched paths were `src/optimizer/`, `src/parser/` and
`src/query/`; the searched patterns were `query_is_distinct` (0 hits),
`is_distinct_for` (0), `redundant.*distinct` (0), `remove.*distinct` (0),
`distinct.*redundant` (0), `distinct_elim` (0), `already.*distinct` (0),
`eliminate.*distinct` (2 hits, both executor comments about on-the-fly duplicate
elimination, not a planner proof) and `unique_for` (7 hits, all FK/index grammar
and `execute_schema.c` error paths). The only site that resets
`all_distinct = PT_ALL` is `src/parser/type_checking.c:7056`, inside
`pt_to_false_subquery()` — folding a provably-empty subquery — which is unrelated.

## 8. Causal decomposition details

### 8-a. Where Q18's time actually goes

| phase | CUBRID | PostgreSQL native | PostgreSQL `noidx` |
|---|---|---|---|
| subquery input scan | 11,829 ms, 6 units, partitioned | 35,432 ms, 6 units, **replicated 6×** | 653 ms/unit, 6 units, partitioned |
| subquery aggregation | **29,563 ms, 1 unit**, 422,017 spill pages | folded into the index scan (streaming, no sort) | 9,962 ms/unit partial + finalise |
| outer join + final agg | 30 ms | ~1,200 ms | ~13,000 ms (extra full `lineitem` seq scan) |
| traced statement total | 41,430 ms | 48,473 ms | 33,136 ms |

### 8-b. Explanations considered and rejected, with the number that rejected them

- **"CUBRID wins because its optimizer is better here."** Rejected as a *general*
  claim, accepted only in the narrow sense of `F_plan`. On the controlled pair
  CUBRID is **1.140993x worse on CPU** and **1.069863x worse on units**. Its
  win is 0.734231x of plan shape on PostgreSQL's side of the comparison.
- **"CUBRID's redundant `DISTINCT` is a real cost."** Rejected by direct
  same-engine A/B: 34.570999 s with it against 34.505999 s without,
  **+0.188%**, roughly one within-block sd (0.075 s) and well inside the 1.6%
  error band. The optimizer *estimates* it at +22% of subquery cost
  (1,308,583 vs 1,070,742) only because it also estimates the subquery at
  59,986,052 rows; the `DISTINCT` actually runs **after** `HAVING`, on 624 rows.
  Recorded as a planner-level redundancy with **no measured Q18 effect**.
- **"CUBRID's 14.9M-row estimate for `av1861` costs it something."** Rejected:
  the estimate is wrong by ~24,000x (14,929,885 vs 624) yet selects the same
  join order and access paths a correct estimate would select, and the outer
  pipeline costs 30 ms of 41,430 ms.
- **"PostgreSQL is slower because of physical I/O."** Rejected: `read_bytes`
  delta is **0** on every PostgreSQL block. The 5,689,168 `heap_blks_read` are
  shared-buffer misses served by the OS page cache, and 48.67% of PostgreSQL's
  cycles are buffer lock/unlock, not I/O wait.
- **"Clearing `hash_eligible` will unblock the serial group-by."** Rejected by
  direct A/B, and this is the most instructive negative result in Q18. The only
  user-reachable lever, `/*+ NO_HASH_AGGREGATE */`, made CUBRID **slower**:
  40.173998 s against 37.452998 s (+7.3%), with TWU *falling* 2.7041 → 1.8912 and
  serial tail *rising* 12.548 s → 30.578 s. The trace shows why —
  `GROUPBY (time: 43073, hash: false, sort: true, page: 139848)` against the
  native `(time: 29563, hash: partial, sort: true, page: 422017)`: the hint
  removes the partial hash pre-aggregation that reduces 59,986,052 rows toward
  15,000,000 groups, and the sort did not become parallel anyway. **The hint
  changes two things at once, so it cannot isolate `sort_check_parallelism()`;
  it refutes the naive fix rather than measuring the real one.**

### 8-c. Bound on the serial-group-by opportunity

Because no switch isolates it, the size of the serial-aggregation problem is
stated as a **bound**, not a measurement. CUBRID's block spends 89.10 s of
140.50 s at ~1 unit (22.28 s per statement) and 44.11 s at ~6 units. If the
serial phase were perfectly parallelised to the 6 units the scan already
achieves — ignoring merge and gather overhead, which is why this is an upper
bound — the statement would fall from 37.45 s to roughly
`37.45 − 22.28 + 22.28/6 ≈ 18.9 s`, i.e. **at most ~1.98x**. Against
PostgreSQL's *best* plan (30.681412 s) that would move CUBRID from 1.22x behind
to ~1.62x ahead. Evidence type: **upper bound**, from measured per-unit
time-weighted telemetry.

## 9. Improvements

Registry synced before allocation; searched by title, both source locations and
root cause. **No new ID was allocated for Q18's primary finding** — it is an
existing root cause that Q18 now supplies the campaign's strongest evidence for.

### Reused: IMP-015 (`P0`, aggregation/sort + parallelism, status `measured`)

*"`sort_check_parallelism()` unconditionally refuses parallelism for a
`SORT_GROUP_BY` whenever the query was marked hash-aggregate-eligible, even after
the executor has already abandoned hash aggregation at runtime."*

Q18 relation and evidence added:

- **Mechanism, per operation.** CUBRID: `src/parser/xasl_generation.c:16556-16568`
  sets `g_hash_eligible = true` for Q18's subquery purely because `sum()` is
  hash-aggregatable; at runtime the 2 MB `max_agg_hash_size` cannot hold the
  **15,000,000** groups the ground truth confirms, so the executor degrades to a
  sort (`hash: partial`, 422,017 spill pages); `src/storage/external_sort.c`
  `sort_check_parallelism()`'s `SORT_GROUP_BY` branch then returns 1 *because
  `px->hash_eligible` is still set*, so the fallback sort is single-threaded.
  PostgreSQL: aggregation parallelism is a plan property
  (`src/backend/executor/nodeAgg.c` partial/final nodes under `Gather Merge`),
  independent of hashing — `Partial HashAggregate … loops=6` in the `noidx` plan.
- **Quantified effect, mapped to a measured band.** 89.10 s of the 140.50 s
  CUBRID block at ~1 active unit (**63.4%**, time-weighted from 1,253 real
  intervals); the trace attributes 29,563 ms of the 41,430 ms statement to that
  `GROUPBY`; the profile attributes it to the `transaction` comm (18.36 of 77.55
  resolved points) led by `qfile_compare_partial_sort_record` 3.27% and
  `sort_run_merge` 0.80%. Upper bound on the fix: **~1.98x** (§8-c).
- **Evidence type:** profile attribution + upper bound. **Not** direct A/B — §8-b
  records why the only available switch cannot isolate this decision.
- **Implementation direction:** re-evaluate the parallel decision on the *actual*
  runtime state instead of the XASL-time flag — i.e. consult the executor's
  hash-aggregate outcome (the `hash: partial` / `HS_REJECT_ALL` condition) at the
  point `sort_listfile` is entered, rather than the planner's `g_hash_eligible`.
- **Correctness/regression risk:** medium. Parallel sort-group-by already exists
  and is exercised for non-hash-eligible queries, so the risk is scheduling and
  worker-pool pressure, not result correctness; a query whose hash aggregation
  *succeeds* must keep its current path.
- **Validation criteria:** on Q18, TWU rises above ~4 with unchanged results and
  unchanged spill page count; `q18-groundtruth` values byte-identical; no
  regression on a query where hash aggregation completes in memory.
- **Ranking against siblings:** ranked #1 for Q18. It governs 63.4% of the block
  wall, where IMP-016/IMP-017 govern the spill *size* (worth a measured 6.93%,
  below) and the redundant `DISTINCT` is worth 0.188% (inside the error band).

### Reused: IMP-016 / IMP-017 (aggregation/sort) — new Q18 evidence

IMP-017 already records that `max_agg_hash_size` is read into a function-local
static and that a session-level `SET SYSTEM PARAMETERS` to 512M *provably changed
nothing*. Q18 independently confirms the parameter is not even settable here
(`ERROR: Cannot change system parameter "max_agg_hash_size=256M"`). Q18 adds a
measurement on the **session-settable** half of the same budget:

| `sort_buffer_size` | traced statement | GROUPBY time | spill pages | ioread |
|---|---|---|---|---|
| 2M (server default, native) | 41.106 s | 29,230 ms | 422,040 | 455,485 |
| 256M | **38.257 s** | **26,400 ms** | **145,717** | **225,405** |
| delta | **−6.93%** | −9.68% | **−65.5%** | −50.5% |

Controlled cleanly: the scan phase is unchanged across both runs (11,836 ms vs
11,813 ms), and the −2.849 s statement delta is accounted for almost entirely by
the −2.830 s `GROUPBY` delta. Evidence type: **direct A/B (same engine,
controlled parameter)**. This is a *configuration* finding, not a code change:
it shows the 8 GB buffer contract does not reach the operator that dominates Q18.

### Recorded, not promoted: unconditional `PT_DISTINCT` on `IN` subqueries

`src/parser/type_checking.c:5037` adds `PT_DISTINCT` to every `IN`-subquery
without checking whether the subquery is already distinct, where PostgreSQL
proves exactly that at `analyzejoins.c:1372-1389` and reduces SEMI to inner join.
The mechanism is real and the asymmetry is real, but the **measured Q18 effect is
+0.188%, inside the error band**, because Q18's `DISTINCT` runs after `HAVING` on
624 rows. It is therefore recorded in this report's §7 contrast with an explicit
"no measured effect on Q18" and **no registry ID is allocated from Q18 evidence**;
allocating one here would violate §18's requirement that a candidate state a
mechanism with an evidence event and denominator that actually moved. A query
whose `IN` subquery has no selective `HAVING` would be the place to measure it.

## 10. Evidence index

`claim → raw file:line → formula → evidence type → SHA-256` (full digests in
`raw-manifest.json`; every path below is under
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q18/`).

| claim | raw file | formula | evidence type |
|---|---|---|---|
| CUBRID headline 37.452998 s | `Q18-cubrid-headline-block1.json` | median of `measured_times_s` | direct measurement |
| PostgreSQL headline 41.787122 s | `Q18-postgresql-headline-block1.json` | median of `measured_times_s` | direct measurement |
| `R_wall` 0.896281x | `q18-causal-card.json` | `T_C / T_P` | derived |
| `F_plan` 0.734231x | `Q18-postgresql-noidx-headline.json` | `T_P_noidx / T_P_native` | direct A/B |
| `F_units` 1.069863x | `Q18-{cubrid,postgresql-noidx}-headline-telemetry.json` | `U_P' / U_C` | profile attribution |
| `F_cpu` 1.140993x | same | `(U_C·T_C)/(U_P'·T_P')` | profile attribution |
| `F_work` 0.500036x | `q18-groundtruth-*.out`, `q18-plan-act-pg-noidx.out` | `59,990,420 / 119,972,104` | ground truth |
| residual −0.0000000000% | `q18-causal-card.txt` | `F_plan·F_units·F_cpu / R_wall − 1` | derived |
| PG replicates subquery 6× | `q18-plan-act-pg.out` | `rows=59985038.00 loops=6` | engine EXPLAIN |
| PG anchor scan is partitioned | `q18-plan-act-pg-noidx.out` | `9997675.33 × 6 = 59,986,052` | engine EXPLAIN |
| CUBRID 63.4% at one unit | `Q18-cubrid-headline-telemetry-intervals.json` | Σ`dt` where `units`≈1 / Σ`dt` | profile attribution |
| CUBRID serial group-by 29,563 ms | `q18-trace-cubrid.out` | trace `GROUPBY (time: …)` | engine trace |
| PG buffer-lock 48.67% | `profile-pg-flat.txt` | `LockBufferInternal + BufferLockUnlock` | perf, verified PID set |
| `sort_buffer_size` A/B −6.93% | `q18-sortbuf-{2M,256M}-trace.out` | traced statement medians | direct A/B |
| `DISTINCT` A/B +0.188% | `Q18-cubrid-distinct-{on,off}-headline.json` | median ratio | direct A/B |
| `NO_HASH_AGGREGATE` +7.3% | `Q18-cubrid-nohashagg-headline.json` | median ratio | direct A/B |
| PG serial 1.7209x faster | `Q18-postgresql-serial-headline.json` | `T_P_native / T_P_serial` | direct A/B |
| zero physical reads | `Q18-*-headline-block*.json` `sampler.engine_read_bytes_delta` | delta over block | direct measurement |
| ground truth identical | `q18-groundtruth-{cubrid,pg}.out` | byte comparison | ground truth |
| WARM gate parameters | `q18-warm-gate-params.txt` | moving-block bootstrap, 4000 reps | derived |

## 11. Notion sync

**Not performed by this session.** Per SSOT §21 the GJC/tmux worker session runs
on the remote build host, has no Notion connector and must never attempt a Notion
write; its Notion-adjacent duty ends at pushing this report to `origin/main`.
**No backfill record was appended by this session either.** SSOT §21 places all
three write paths — official connector, Aside browser, and the idempotent
`reports/notion_backfill_pending.jsonl` record — inside the Notion sync
procedure, which is the §23 reconciler subagent's responsibility, and it ends
this worker's duty at the push. The record also cannot be formed here: its
idempotency key is
`campaign_id + QNN + session_id + report_commit + content_fingerprint`, and
`report_commit` does not exist until the commit below is pushed. The reconciler
must therefore create it while reading the pushed commit as source of truth,
exactly as Q17's own record documents
(`notion_write_path: "3 — … appended by the Notion-capable RECONCILER subagent
(not the measurement worker)"`).

Handoff values for the reconciler: `campaign_id` `tpch-sspq-fk-r1-20260730`,
`qnn` `Q18`, `gjc_session_id` `gajae_code_msa9jlby_r5xvme65`, `ssot_commit`
`41e295dd6531bcfcd77114a21575895dc13e7118`, `ssot_blob_sha`
`510478846bff081d3223d3835069283a7cd2e47b`, `cubrid_median_s` `37.452998`,
`postgresql_median_s` `41.787122`, `median_wall_ratio` `0.896281`,
`raw_dir` `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q18`.

## 12. Completion checklist

| § | Requirement | Status |
|---|---|---|
| 26 | preflight and correctness status recorded | ✅ preflight + postflight captured, `result-equivalent-at-SF10` |
| 26 | three valid headline values per completing engine | ✅ 3 measured statements × 3 blocks per engine, all accepted on attempt 1 |
| 13 | timeout confirmations | ✅ n/a — no timeout; 37.5 s / 41.8 s against a 300 s limit |
| 14 | estimated plans without execution | ✅ `q18-plan-est-cubrid.out`, `q18-plan-est-pg.out` |
| 14 | actual plans + CUBRID trace, separate non-headline runs | ✅ `q18-plan-act-pg.out`, `q18-trace-cubrid.out` |
| 14 | CPU/thread, `/proc` I/O, NUMA, buffer diagnostics | ✅ section 5 |
| 14 | separate perf cycles/instructions/call-graph runs | ✅ section 6, including a recorded capture failure and its repair |
| 14 | CUBRID and PostgreSQL `file:line` source contrast | ✅ section 7, 4 rows + absence-search record |
| 16 | causal multiplier card with evidence or explicit `UNMEASURED` | ✅ all five factors numeric, residual −0.0000000000% |
| 18 | improvement registry deduplicated | ✅ reused IMP-015/016/017; **no new ID allocated**, with reason |
| 19 | raw manifest with sizes, hashes, commands | ✅ `raw-manifest.json` |
| 26 | every claim indexed to raw evidence | ✅ section 10 |
| 26 | committed, pushed, reachable from `origin/main` | ✅ see `report_commit` |
| 21 | Notion sync or durable backfill record | ⏭ **deferred to the §23 reconciler subagent by contract** — §21 bars this worker from every Notion write path, and the backfill key needs `report_commit`, which does not exist until this commit is pushed. Handoff values are in §11. |
| 22 | `QUERY_COMPLETE` emitted | ✅ |
| 24 | child block-driver tmux sessions consumed | ✅ all 8 (`q18probe`, `q18blocks`, `q18plans`, `q18tel`, `q18var`, `q18fin`, `q18perf`, `q18perf2`) verified absent by `tmux has-session`; 0 orphan `csql`/`psql`/`perf`/PG workers |
| 22 | measurement session removed and absence verified | ⏭ **controller step, not this worker's** — §22 has the controlling session remove the worker after durable completion and verify with both `gjc session status <id>` and `tmux has-session -t <id>`. This session is `gajae_code_msa9jlby_r5xvme65`; it reports `QUERY_COMPLETE` and stops. |
