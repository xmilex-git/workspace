# TPCH-SSPQ FK campaign — Q02 report

## 3-a. Causal multiplier card

```text
R_wall 0.147363x [wall, median of 3 per engine; CUBRID is 6.7860x faster]
= F_plan  UNMEASURED [plan-shape; structurally different, no clean same-engine anchor]
× F_units 0.226575x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   0.625874x [total query CPU-seconds]

F_cpu 0.625874x [total query CPU-seconds]
= F_work 0.314406x [plan-node tuple touches: 2,276,539 vs 7,240,771]
× F_cost 1.990658x [total-query CPU-seconds per plan-node tuple touch]
```

Read in the direction of the win: CUBRID is **6.7860x faster**, of which **4.4136x**
is `1/F_units` (CUBRID actually runs 4.69 active units, PostgreSQL 1.06) and
**1.5978x** is `1/F_cpu`. Inside `F_cpu`, CUBRID touches **3.1806x fewer** pipeline
tuples but pays **1.9907x more CPU per tuple**. CUBRID wins Q02 by doing far less
work far more concurrently, while remaining the less efficient engine per unit of
work — the same per-unit deficit Q01 measured as `F_cost = 2.7407`.

Reconstruction: `0.226575 × 0.625874 = 0.141807` vs headline `0.147363`.
**Residual = −3.770%.** Measured error budget: within-block relative sd 0.652%
(CUBRID) and 0.423% (PostgreSQL), 0.777% combined in quadrature — which alone does
*not* cover the residual. The remainder is a fully measured regime offset, not
noise: the stage-14.7 telemetry runs that supply the CPU numerators are
single-statement-per-connection runs and sit **+8.11%** (CUBRID) and **+12.35%**
(PostgreSQL) above their own headline medians. Their differential predicts a
residual of `1.0811/1.1235 − 1 = −3.770%`, which matches the observed −3.770% to
**0.000 pp**. The residual is therefore deterministic and explained, and the card is
closed. Mechanism of the offset is identified in section 5.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | **UNMEASURED** | plan-node shape | n/a | no GUC-level same-engine control reproduces the contrasting shape (section 4) | `q2-plan-act-pg.out`, `q2-plan-act-pg-controlled.out`, `q2-plan-act-pg-nl.out`, `q2-trace-cubrid.out` | — |
| `F_units` | 0.226575x | active execution units | CPU-seconds / wall-second | `U_P/U_C`, `U=CPU/T` | `Q02-*-telemetry-run*.json` | profile attribution |
| `F_cpu` | 0.625874x | total query CPU-seconds | per query execution | `CPU_C/CPU_P` = 1.79/2.86 | `Q02-*-telemetry-run*.json` | profile attribution |
| `F_work` | 0.314406x | plan-node tuple touches | tuples | `W_C/W_P` = 2,276,539/7,240,771 | `q2-trace-cubrid.out`, `q2-plan-act-pg.out` | direct A/B |
| `F_cost` | 1.990658x | CPU-seconds per tuple touch | tuple touches | `(CPU_C/W_C)/(CPU_P/W_P)` = 786.3 ns / 395.0 ns | `Q02-causal-card.json` | profile attribution |

`U_C = 1.79/0.381640 = 4.69029`, `U_P = 2.86/2.691255 = 1.06270`.
No factor double-counts: `F_units` carries only the CPU-per-wall-second ratio,
`F_work` only the tuple count, `F_cost` only the residual CPU per tuple, and
`F_plan` is left explicitly unquantified rather than absorbing any of them.
**`F_plan = UNMEASURED` is a real limitation, not a formality:** the plan shapes
differ (section 4), and because PostgreSQL's parallelism covers only its `part`
scan, a large part of what `F_units` measures is a *consequence* of PostgreSQL's
plan choice. `F_units` and the unquantified `F_plan` are therefore entangled, and
no claim is made that they are independent. Per section 16 a numeric `F_plan`
requires structural equality or a same-engine controlled A/B; neither exists here,
so it is not assigned a number.

`W` is defined as the sum over plan nodes of the tuples each node processed (rows
output plus rows its own filter rejected), each node counted exactly once. Full
per-node derivation is in `Q02-causal-card.json` and reproduced in section 8.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q02 |
| SSOT commit | `5912f0654f1e98beea154c7003d372f52a24a9c4` |
| SSOT blob | `6ce8e04da201fd3f5e1b2d3dae42db1534d5b51a` |
| GJC session ID | `gajae_code_ms7esqu3_mj3cgscn` |
| Raw dir | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q02` |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` |
| CUBRID DB / port | `tpch_sf10_q1` / 1523 (`cub_server` pid 1445555, `cub_master` pid 1433697) |
| PostgreSQL PGDATA / port | `/home/cubrid/pg/pgdata-tpch-sspq` / 5442 (postmaster pid 1433696) |

Both running binaries hash-match the frozen `reports/bootstrap/build-manifest.json`.
Ownership gates (section 10) classified **OK** before and after every measurement
block; after both blocks 0 orphan `csql`, 0 orphan `psql`, 0 leftover backends and
0 leftover parallel workers remained.

**SSOT re-pinning during this query.** Q02 began pinned to
`ad1433b4…`/`3f742927…`. Four contract updates were issued by direct user
instruction mid-query (authority order 1 in section 2) and each was verified before
adoption — commit object present, blob SHA matching the stated value, previous pin
an ancestor, and the diff inspected:

| New pin | Blob | Change | Measurement impact |
|---|---|---|---|
| `2a5c4452…` | `a855b570…` | §21 execution boundary: worker never writes Notion | none (reporting only) |
| `f8c7cfd0…` | `049f511c…` | §21 tightened: all Notion writes via a Notion-capable subagent | none (reporting only) |
| `b3b7a874…` | `2118be0f…` | §18 improvement-candidate quality bar; §21 mirror depth floor | none on measurement; applied to sections 7/8/9 |
| `5912f065…` | `6ce8e04d…` | §9 shared memory contract: PostgreSQL `dynamic_shared_memory_type=mmap` | none; the setting was already live before all Q02 measurement (verified, sections 1 and 4) |

No update touched the schema, statistics, parallel, buffer or timing contract, so no
completed measurement was invalidated and nothing was re-run. `SSOT_DRIFT` was never
set: at each step `git rev-parse HEAD:tpch-sspq/SSOT.md` equalled the pinned blob.

Query provenance: `queries/q2-cubrid.sql` byte-matches the canonical source
`/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q2.sql`, SHA-256
`a55d3ac3f7b5c109cbf6bb91d402a2061b934f1ceae766a50976e29068990758`. The PostgreSQL
dialect file is **byte-identical** to the canonical CUBRID file (same SHA-256;
`queries/diff/q2.diff` is 0 bytes, and `cmp q2-cubrid.sql q2-pg.sql` is clean):
Q02 needs zero dialect changes. No hint, join reordering, subquery rewrite, extra
predicate or semantic cast exists on either side.

Schema: 8 named FKs and 8 corresponding child B-trees verified on both engines with
exact child-column order, including composite `fk_lineitem_partsupp
(l_partkey, l_suppkey)` at key_order 0,1; all PostgreSQL `pg_constraint.convalidated
= true` (8/8/8). Row counts are exact-equal on both engines (`part` 2,000,000,
`partsupp` 8,000,000, `supplier` 100,000, `nation` 25, `region` 5).
**Q02 exercises the campaign's FK indexes directly**: CUBRID uses the FK-owned
B-tree `fk_partsupp_part`, and PostgreSQL uses `idx_fk_partsupp_part` and
`idx_fk_partsupp_supplier`. This query would not have the same plan under the
discarded PK-only schema.

Contract state at measurement time:

- statistics: CUBRID `update_statistics_update_histogram=y`,
  `default_histogram_bucket_count=300` (target). Actual per-column bucket count
  remains **UNMEASURED** (opaque serialized `VARBIT` in `_db_histogram`, no
  SQL-exposed bucket-count field) — carried forward from bootstrap and Q01.
  PostgreSQL standard `ANALYZE`, `default_statistics_target=100`, all eight tables
  last analyzed 2026-07-30 17:54 (post-FK-creation; the 2026-07-28 autoanalyze
  timestamps are superseded).
- parallel, `configured node/gather-cap comparison`: CUBRID `parallelism=6`,
  `max_parallel_workers=100`; PostgreSQL `max_parallel_workers_per_gather=5`,
  `max_parallel_workers=5`, `parallel_leader_participation=on`,
  `max_worker_processes=16` (non-binding), `statement_timeout=300000 ms`, `jit=off`.
- buffer/cache, `configured-equal buffer budget`: CUBRID `data_buffer_size=8.0G`,
  PostgreSQL `shared_buffers=8192MB`. Not a claim of equivalent cache architecture,
  eviction policy or page format. Unlike Q01, **Q02's working set fits both
  budgets**: the five referenced relations are 1,858.0 MiB on CUBRID
  (`part` 380.5 + `partsupp` 1,457.5 + `supplier` 20.0 + `nation`/`region` ~0) and
  1,706 MB on PostgreSQL, so neither engine self-evicts and the Q01 buffer-pressure
  confound is absent here.
- shared memory, `parallel-plan-availability parity`: PostgreSQL
  `dynamic_shared_memory_type=mmap`, verified live with
  `source=configuration file, sourcefile=postgresql.conf:969` (line 159 carries the
  packaged `posix` default and is overridden later in the same file; last wins).
  CUBRID has no equivalent parameter — its parallel scan units share process memory
  rather than a POSIX/SysV segment. The host `/dev/shm` is a fixed 64000k tmpfs
  (628k in use), not campaign-controlled. This setting was already live before every
  Q02 measurement, so no Q02 value is affected by it; it is recorded here because
  Q02's natural PostgreSQL plan contains a parallel gather (`Gather Merge`, 4 workers
  launched), which section 9 makes a recording trigger. Evidence:
  `q2-shared-memory-verification.txt`.
- cpuset/NUMA: SUT+client CPUs `0-15` (node0), collectors CPUs `20-23`. All 35
  engine TIDs verified on `0-15` with **0 off-cpuset** before and after each block.
  `cub_server` 8,644.99 MB node0 / 4.55 MB node1 (99.95% node0); postmaster
  170.00 MB node0 / 0.67 MB node1. No page migration during the runs.
- external SUT-set load before measurement: 0.542 core-seconds/second, under the
  1.5 threshold. No `INVALID_BACKGROUND_LOAD`.

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored.

Q02 has `ORDER BY`, so the ordered result sequence was compared exactly. 100 rows on
both engines (`LIMIT 100`), all fields equal — text, integers, dates, NULLs, row
count and row multiset. Raw decimal text preserved. The 1e-12 relative tolerance was
available but **not needed**: no field required it.

The `LIMIT 100` boundary was explicitly proven non-arbitrary rather than assumed.
The unlimited query returns **4,667 rows** and all **4,667** `(s_acctbal, n_name,
s_name, p_partkey)` sort-key tuples are distinct, so the `ORDER BY` is a total order
and `LIMIT 100` is deterministic. The boundary is strictly separated: row 100 is
`(9766.22, GERMANY, Supplier#000066352, 1516321)` and row 101 is
`(9761.50, ROMANIA, Supplier#000030892, 530891)`. Equivalence here is structural,
not a coincidence of tie-breaking.

Comparator: `harness/correctness_check.py` delegating to the bootstrap-verified
`harness/smoke_check.py` rules.

## 3-b. Headline timings

Regime `single-query-repeat WARM`; metadata connection mode
`single-connection-four-statements` (1 uncounted warmup + 3 measured, one direct
connection, no reconnect/prepare between measured statements, connection
establishment excluded). **Q02 is even, so the engine-block order is PostgreSQL
block first, then CUBRID block** (section 12). Each statement fully consumed all 100
rows into a campaign-owned fixed sink under `work/Q02/sink`; content hashes computed
after the timers stopped.

| Field | CUBRID | PostgreSQL |
|---|---|---|
| warmup (uncounted) | 0.363000 s | 2.687241 s |
| measured run 1 | 0.353000 s | 2.408541 s |
| measured run 2 | 0.357000 s | 2.388589 s |
| measured run 3 | 0.353000 s | 2.395453 s |
| **median (headline)** | **0.353000 s** | **2.395453 s** |
| mean | 0.354333 s | 2.397528 s |
| within-block sd | 0.002309 s (0.652%) | 0.010137 s (0.423%) |
| sink bytes | 97456 | 78730 |
| sink SHA-256 | `7a23799325d52d3f…` | `5a4c8c1aa45b993c…` |

**Median wall ratio = 0.147363x (CUBRID / PostgreSQL) — CUBRID is 6.7860x faster.**
Correctness status `result-equivalent-at-SF10`; censoring status: not censored (both
engines far inside the 300 s timeout). No confidence interval is claimed from three
values.

Measurement-resolution note: `csql` reports elapsed time at 1 ms granularity
(`0.353000 sec`), so CUBRID's headline carries ±0.28% quantization at this
magnitude; `psql` reports µs. This is recorded rather than smoothed, and it is
smaller than CUBRID's 0.652% within-block sd.

WARM proof (proved, not assumed):

| Evidence | CUBRID | PostgreSQL |
|---|---|---|
| device `read_bytes` delta across block | 0 | 0 |
| engine buffer counters | pool conserved at exactly 524,288 pages (8 GiB / 16 KiB) pre and post: `lru1+lru2+lru3` = 1,435+26,214+496,639 → 37,832+5+486,451 | `heap_blks_read` delta **0**; `heap_blks_hit` +1,688,852/statement |
| `rchar` across whole 4-statement block | 2,696 B | — |
| warmup vs median | +2.83% | +12.18% |
| in-query physical reads (actual run) | trace `ioread: 0` at every node | `Buffers: shared hit=1849729`, no `read=` |

No WARM gate failure, so no run was invalidated or restarted. PostgreSQL's warmup
excess (+12.18%) is *not* a cold-cache effect — `heap_blks_read` is 0 for all four
statements — and is diagnosed in section 5.

## 4. Plan

The two engines choose **structurally different plans**. This is the central fact of
Q02.

CUBRID estimated (`SET OPTIMIZATION LEVEL 514`, verified non-executing: 0.02 s wall,
no result rows):

```text
temp(order by)
    subplan: idx-join (inner join)          <- 5-way left-deep index nested loop
                 outer: ... idx-join
                            outer: sscan class: part node[0]
                                       sargs: term[5] AND term[6]
                                       cost: 29353 card 368
                            inner: iscan class: partsupp node[2]
                                       index: fk_partsupp_part term[4]
                                       sargs: term[3]
                 inner: iscan class: supplier  index: pk_supplier_s_suppkey
                 inner: iscan class: nation    index: pk_nation_n_nationkey
                 inner: iscan class: region    index: pk_region_r_regionkey
    sort: 1 desc, 3 asc, 2 asc, 4 asc
    cost: 29592 card 1
term[5]: p_type like '%BRASS' (sel 0.00921158) (rank 3)
term[6]: p_size=15 (sel 0.02)
```

CUBRID actual (trace):

```text
SELECT (time: 399, fetch: 155, fetch_time: 0, ioread: 0)
  SCAN (table: dba.part) (heap time: 397, fetch: 28, ioread: 0)
       (parallel workers: 5, heap time: 389..397, readrows: 399448..401913,
        topnsort: true, gather: mergeable list)
    SCAN (index: dba.partsupp.fk_partsupp_part) (btree time: 18, ioread: 0,
        readkeys: 7854, filteredkeys: 7854, rows: 31416) (lookup time: 12)
      SCAN (index: dba.supplier.pk_supplier_s_suppkey) (readkeys: 9160, rows: 9160)
      MEMOIZE (hit: 176, miss: 9160, size: 6830KB, enabled: true)
        SCAN (index: dba.nation.pk_nation_n_nationkey) (readkeys: 78, rows: 78)
        MEMOIZE (hit: 13926, miss: 78, size: 30KB, enabled: true)
          SCAN (index: dba.region.pk_region_r_regionkey) (readkeys: 24, rows: 20)
          MEMOIZE (hit: 18648, miss: 24, size: 7KB, enabled: true)
    SUBQUERY (correlated)
      SELECT (time: 115, fetch: 677874, ioread: 0)
        SCAN (index: dba.partsupp.fk_partsupp_part) (readkeys: 15708, rows: 62832)
          SCAN (index: dba.supplier.pk_supplier_s_suppkey) (rows: 62832)
            SCAN (index: dba.nation.pk_nation_n_nationkey) (rows: 59230)
              SCAN (index: dba.region.pk_region_r_regionkey) (rows: 9334)
      SUBQUERY_CACHE (hit: 47124, miss: 15708, size: 3276896, status: enabled)
  ORDERBY (time: 1, sort: true, page: 0, ioread: 0)
```

PostgreSQL actual (`EXPLAIN ANALYZE BUFFERS VERBOSE TIMING`):

```text
Limit (actual time=2836.103..2836.325 rows=100)
  Buffers: shared hit=1849729, temp read=73250 written=73337
  Sort (top-N heapsort, 69kB)
    Merge Join (actual time=2202.540..2834.358 rows=4667)
      Merge Cond: (part.p_partkey = partsupp.ps_partkey)
      Join Filter: (partsupp.ps_supplycost = (SubPlan expr_1))
      Rows Removed by Join Filter: 1684
      -> Gather Merge (rows=7854)  Workers Planned: 4  Launched: 4
           -> Parallel Index Scan using part_pkey (rows=1570.80 loops=5)
              Filter: ((p_type ~~ '%BRASS') AND (p_size = 15))
              Rows Removed by Filter: 398429/loop
      -> Materialize (rows=1602443)  Storage: Memory  Max: 18kB
           -> Sort (rows=1602443)  Sort Key: partsupp.ps_partkey
                Sort Method: external merge  Disk: 293024kB
                -> Nested Loop (actual time=0.139..1329.086 rows=1602640)
                     -> Nested Loop (rows=20033)  [region x (supplier hash nation)]
                     -> Index Scan using idx_fk_partsupp_supplier (rows=80 loops=20033)
      SubPlan expr_1 -> Aggregate (actual time=0.018..0.018 loops=6351)
Planning Time: 2.892 ms   Execution Time: 2851.969 ms
```

Shape difference, stated precisely:

- **CUBRID** drives from the 7,854 parts that satisfy the two `part` predicates and
  probes `partsupp` through the FK B-tree (31,416 rows), then `supplier`/`nation`/
  `region` through PKs with a `MEMOIZE` cache on each inner side. The `LIMIT 100` is
  pushed into the parallel scan as `topnsort: true`. Peak intermediate size is the
  6,830 KB memo, and `ORDERBY` spends 1 ms with `page: 0, ioread: 0` (no spill).
- **PostgreSQL** materializes the *other* side: it builds `supplier ⋈ nation ⋈
  partsupp` as **1,602,640 rows**, sorts them by `ps_partkey` with an **external
  merge spilling 293,024 kB**, materializes that, and merge-joins it against the
  7,854 parts. Peak intermediate size is 293 MB of temp files (73,250 blocks read,
  73,337 written).

Both engines use the campaign FK indexes, so the index availability is **not** the
differentiator: CUBRID uses `fk_partsupp_part` in both the outer join and the
subquery; PostgreSQL uses `idx_fk_partsupp_part` in `SubPlan expr_1` and
`idx_fk_partsupp_supplier` in the main pipeline.

Estimate quality on the `part` predicate pair: CUBRID `card 368` vs actual 7,854
(**21.3x under**); PostgreSQL `rows=8366` vs actual 7,854 (**1.07x**, 6.5% error).
The CUBRID error traces to a single term — `p_type like '%BRASS'` estimated at
`sel 0.00921158` against a measured 399,587/2,000,000 = **0.19979** (21.7x under)
— while `p_size=15` is estimated 0.02 against a measured 39,575/2,000,000 = 0.0198
(1.1% error). PostgreSQL's own leading-wildcard estimate is 521,980 vs 399,587
(1.31x over). This misestimate is not cosmetic; section 7 shows it decides the
predicate evaluation order.

Why `F_plan` is `UNMEASURED` and not a number. Three same-engine counterfactuals
were run on PostgreSQL to try to isolate the plan factor:

| Variant | Plan reached | Execution time | Verdict |
|---|---|---|---|
| native | Merge Join over 1.6M-row external-merge sort | 2851.969 ms | baseline |
| `enable_mergejoin=off` | Hash Join, still builds 1.6M-row hash | 2731.477 ms | moves the materialization, does not remove it |
| `enable_mergejoin=off, enable_hashjoin=off` | index NL on `part→partsupp`, but `Seq Scan on supplier` per outer row (49,919.68 rows × 4,668 loops) | 21083.361 ms | reaches CUBRID's *join order* only by injecting a different penalty |

No GUC-level control reproduces CUBRID's shape (index NL driven by `part` **with**
index access to `supplier`/`nation`/`region`), so there is no chained counterfactual
that varies plan shape alone. Per section 16, `F_plan` is therefore written
`UNMEASURED` and `F_units`/`F_cpu` are computed on the **native** cross-engine pair,
with native denominators on both sides and no mixing. One bounded observation is
recorded without being promoted to a factor: in the third variant the
`part → partsupp → SubPlan` subtree alone produced its 4,668 qualifying rows in
**870.971 ms**, so a hypothetical PostgreSQL plan with CUBRID's shape *and*
index access on the small dimensions would plausibly land near 0.9–1.0 s rather than
2.4 s. That is a projection, not an A/B, and it anchors nothing.

**PostgreSQL's plan space was not truncated by host shared memory.** Section 9 warns
that a `/dev/shm` ceiling can silently remove Parallel Hash Join and thereby
confound exactly this `F_plan` reasoning, so it was checked rather than assumed. Two
proofs, both in `q2-shared-memory-verification.txt`:

1. Parallel Hash Join *does* execute on this host under `mmap` DSM. A probe join
   (`partsupp ⋈ part` on `p_size < 40`) reached `Parallel Hash Join` with
   `Workers Launched: 5` and `Buckets: 262144  Batches: 16  Memory Usage: 5920kB`,
   completing in 582 ms with no `No space left on device`. `/dev/shm` stayed at
   628k of 64000k throughout and the DSM segments appear as
   `PGDATA/pg_dynshmem/mmap.*`, i.e. DSM is file-backed and never touches the
   64000k tmpfs.
2. Parallel Hash Join is nevertheless **not** part of Q02's natural plan, for
   planner rather than host reasons. Forcing the hash path (`enable_mergejoin=off`)
   yields a **non-parallel** `Hash Join` (`Buckets: 65536  Batches: 64
   Memory Usage: 5623kB`, 2,675 ms) because the join qual carries the correlated
   `SubPlan expr_1` on `part.p_partkey` across the `Gather` boundary. Every function
   involved is parallel-safe (`textlike=s`, `int4eq=s`, `numeric_eq=s`, `min=s`), so
   parallel-safety is not the limiter either.

PostgreSQL therefore had Parallel Hash Join available and still chose the merge-join
plan with a 293 MB external sort. `F_plan` stays `UNMEASURED`, but its unmeasured
content is a genuine cost-model decision, not an artifact of host shared-memory
sizing.

## 5. Execution telemetry

Non-headline diagnostic runs; sampler on CPUs `20-23`, per-TID, weighted by actual
sample timestamp deltas. Three runs per engine; the **median-by-wall** run is the
recorded one (CUBRID run 2, PostgreSQL run 1). All three runs per engine are retained
in raw.

| Metric | CUBRID | PostgreSQL |
|---|---|---|
| telemetry walls (3 runs) | 0.380707 / **0.381640** / 0.382600 s | **2.691255** / 2.677482 / 2.703111 s |
| `executor_cpu` | 1.76 core-s (`parallel-query` 1.76) | 2.78 core-s (`pg_backend` 2.54, `pg_parallel_worker` 0.24) |
| `auxiliary_query_cpu` | 0.03 core-s (`csql` 0.01, `dwb-*`/`vacuum-master` 0.02) | 0.12 core-s (`pg_background`) |
| `total_query_cpu` | **1.79 core-s** | **2.86 core-s** |
| planned workers | 6 (`parallelism=6`) | 4 (`Workers Planned: 4`, cap 5) + leader |
| launched workers | 5 (trace `parallel workers: 5`) | 4 (`Workers Launched: 4`) + leader = 5 |
| max simultaneous active units | 5.1502 | 2.0618 |
| time-weighted active units (TWU) | **4.6663** | **1.0681** |
| serial tail | 0.000 s | 0.486 s |
| `rchar` | 22,306 B | 1,201,625,386 B |
| read syscalls (`syscr`) | 171 | 147,959 |
| `write_bytes` | 12,288 B | 597,327,872 B (temp spill) |
| device read | 0 | 0 |
| device write | 0.03 MiB (unrelated) | 0.08 MiB |
| `unattributed_background` | none claimed | none claimed |

TWU is an independent cross-check of `U`, not a substitute: `U_C=4.6903` vs
TWU 4.6663 (0.51% apart); `U_P=1.0627` vs TWU 1.0681 (0.51% apart). Neither was
derived from the configured cap, and no nominal interval was used for weighting —
`perf task-clock` gives a third independent reading (4.965 and 1.015 CPUs utilized).

**PostgreSQL is effectively serial (TWU 1.068).** Its 4 workers exist only for the
`part` index scan, which is 38.710 ms of a 2,836 ms query; everything expensive —
the 1.6M-row nested loop, the external-merge sort, the materialize, the merge join
and the `SubPlan` — runs in the leader. Its 0.486 s serial tail is the top-N sort
plus final merge. CUBRID's TWU 4.6663 with a **0.000 s** serial tail reflects the
`topnsort` pushdown: the per-worker sort means there is no serial gather-and-sort
phase to pay for.

The 293 MB spill is real but is **not** disk I/O: `write_bytes` 597 MB and 147,959
read syscalls against a device write of 0.08 MiB and device read of 0, i.e. the temp
files live entirely in the OS page cache. It is a CPU and memory-bandwidth cost, and
it is already carried by `F_work` (the 1.6M sorted rows), so it is not
double-counted as an I/O factor.

**Mechanism of the +8.11%/+12.35% telemetry offset** (the source of the card's
residual): a telemetry run is one statement in a fresh connection, whereas a headline
value is the 2nd–4th statement of one connection. PostgreSQL's first statement per
backend is reproducibly ~12% slower (warmup 2.687241 s; three independent telemetry
runs 2.691/2.677/2.703 s; measured repeats 2.389–2.409 s) with `heap_blks_read = 0`
throughout, so it is not cache warming. It is consistent with first-touch page
faulting of the ~293 MB sort/temp working set into a fresh backend's address space,
which a second statement in the same backend reuses. CUBRID's smaller +8.11% is its
+2.83% first-statement effect plus residual sampler perturbation on a 0.35 s query.
This is exactly why section 12 mandates a warmup plus three measured statements, and
it is why the headline — not the telemetry wall — is the reported time.

Sampler perturbation was measured and reduced rather than assumed: at a 20 ms period
the original sampler re-ran process discovery (3 `pgrep` spawns) every sample, and
CUBRID telemetry walls drifted 0.3799 → 0.3991 → 0.4088 s. Caching discovery to a
0.1 s refresh (`harness/telemetry_run.py`) removed the drift, giving the stable
0.3807/0.3816/0.3826 s above at ~97 samples per run.

## 6. Profile

Non-headline. `perf` attached to verified PID sets, never all-CPU.
CUBRID: `-p 1445555` (`cub_server`; all query worker threads live inside that
process, 30 TIDs). PostgreSQL: `perf stat` on the discovered leader `1458730` plus
exactly its 4 parallel workers `1458731-1458734`; `perf record` on
`postmaster 1433696 + leader`, relying on perf's inherit-on-fork so the per-statement
parallel workers are sampled as they spawn (worker PIDs are transient across
statements, which made a fixed worker PID list invalid for the record window).
Sub-second statements cannot fill a sampling window, so a driver replayed the
identical statement in one connection (CUBRID 60 repeats, PostgreSQL 16 repeats),
grouping identical variants per section 24.

Coverage validation against `perf stat`: CUBRID 36,429 samples, 568 resolved symbol
lines, **zero `[unknown]`**; PostgreSQL 15,790 samples, 1,704 resolved symbol lines,
**zero `[unknown]`**. Driver completion verified (60 result markers; 1,600 result
rows = 16 × 100).

| Metric | CUBRID | PostgreSQL | Ratio |
|---|---|---|---|
| cycles (12.0 s window) | 164,018,420,777 | 34,854,923,005 | — |
| instructions (12.0 s window) | 381,286,180,140 | 59,617,283,072 | — |
| **IPC** | **2.325** | **1.710** | 1.360 (CUBRID better) |
| frequency | 2.753 GHz | 2.861 GHz | 0.962 |
| task-clock | 59,586.77 ms | 12,181.26 ms | — |
| CPUs utilized | 4.965 | 1.015 | — |
| context-switches | 137,673 / 12 s | 282 / 12 s | — |
| instructions per core-second | 6.399e9 | 4.894e9 | 1.307 |
| instructions per statement | 11.454e9 | 13.997e9 | 0.818 |
| **instructions per tuple touch** | **5,031** | **1,933** | **2.603** |

Consistency check: `2.603 (instructions/tuple) ÷ 1.307 (instructions/core-second)
= 1.991` = `F_cost` exactly. CUBRID's per-tuple deficit is an instruction-count
deficit partially offset by 1.36x better instruction throughput — the same signature
as Q01 (there 2.949x instructions/row at 1.073x better IPC).

Top self cost, CUBRID (`profile-cubrid-flat.txt`):
`lang_strmatch_utf8` **22.01%**, `qstr_eval_like` **12.78%**,
`heap_attrinfo_read_dbvalues` 6.17%, `intl_utf8_to_cp` 4.82%,
`intl_nextchar_utf8` 3.09%, `eval_pred` 3.05%, `pgbuf_fix_release` 2.71%,
`__memmove_evex_unaligned_erms` 2.69%, `heap_next_1page` 1.93%,
`intl_utf8_to_cp@plt` 1.75%, `pr_clear_value` 1.44%,
`mr_readval_string_internal` 1.30%, `db_string_like` 1.20%, `pgbuf_unfix` 1.16%,
`spage_get_record` 1.14%, `intl_nextchar_utf8@plt` 1.07%,
`btree_search_leaf_page` 0.98%.

Top self cost, PostgreSQL (`profile-pg-flat.txt`):
`heap_hot_search_buffer` 8.38%, `hash_search_with_hash_value` 7.28%,
`heap_fill_tuple` 4.37%, `heap_page_prune_opt` 3.83%,
`__memmove_evex_unaligned_erms` 3.64%, `rep_movs_alternative` [k] 3.61%,
`nocachegetattr` 3.50%, `tts_buffer_heap_getsomeattrs` 3.18%,
**`UTF8_MatchText` 3.00%**, `PinBuffer` 2.61%, `radix_sort_recursive` 2.48%,
`next_uptodate_folio` [k] 2.26%, `ExecInterpExpr` 2.15%, `LockBufferInternal` 1.43%,
`tts_minimal_getsomeattrs` 1.36%, `comparetup_heap` 1.06%,
`tuplesort_heap_replace_top` 0.89%.

Banded: CUBRID's **LIKE/UTF-8 band is 46.72%** of profiled self cost
(`lang_strmatch_utf8` + `qstr_eval_like` + `intl_utf8_to_cp` + `@plt` +
`intl_nextchar_utf8` + `@plt` + `db_string_like`) = **0.836 core-s of 1.79**.
PostgreSQL's comparable band is `UTF8_MatchText` **3.00%** = 0.0858 core-s of 2.86.
Both engines apply the same predicate to the same 2,000,000 `part` rows, so this is
a like-for-like per-row comparison: **418.1 ns/row vs 42.9 ns/row = 9.75x**.
Of CUBRID's band, **2.82%** of total query CPU is spent purely in PLT call stubs
(`intl_utf8_to_cp@plt` 1.75% + `intl_nextchar_utf8@plt` 1.07%), i.e. the two hottest
leaf helpers are called through the dynamic linker per character rather than inlined.
PostgreSQL's remaining cost is spread across buffer lookup and tuple deform
(`heap_hot_search_buffer`, `hash_search_with_hash_value`, `PinBuffer`,
`nocachegetattr`, `tts_*` ≈ 26%) and the 1.6M-row sort
(`radix_sort_recursive`, `comparetup_heap`, `tuplesort_heap_replace_top` ≈ 4.4%) —
i.e. the cost of the tuples its plan chose to materialize.

## 7. Source contrast

| Item | CUBRID file:line | PostgreSQL file:line | Difference | Class |
|---|---|---|---|---|
| Leading-wildcard LIKE selectivity from a histogram | `src/optimizer/histogram/histogram_cl.cpp:1427` `histogram_get_like_selectivity()`; MCV probe loop `:1480-1486`; **non-MCV estimate = fraction of matching bucket *upper-boundary* values** `:1487-1501`; size gate and blend `:1508-1526`; called from `src/optimizer/query_planner.c:10101` inside `qo_like_selectivity()` (`:10068`), reached from `qo_expr_selectivity()` `PT_LIKE` case `:9934` | `src/backend/utils/adt/selfuncs.c:807` `mcv_selectivity()` and `:898` `histogram_selectivity()`, combined for pattern operators at `:1032` and `:1042` | Both engines LIKE-test their MCV list. For the non-MCV mass CUBRID tests the pattern against **one representative string per bucket** (`bucket_hi`) and uses the matching-bucket fraction directly once the histogram has ≥100 entries; PostgreSQL applies the operator function across the histogram bound array itself and combines it with the MCV result. A bucket's upper boundary is a sort-order artefact, so a suffix pattern uncorrelated with that order matches boundaries at a rate unrelated to its true frequency. Measured: CUBRID `sel 0.00921158` vs actual `0.19979` = **21.7x under**; PostgreSQL 0.26099 vs 0.19979 = 1.31x over. | same stage, lower measured cost |
| Conjunctive predicate evaluation order | `src/optimizer/plan_generation.c:1577` `make_pred_from_bitset()`; ordering keys at `:1615-1636` — primary key is `pred_order`, then **selectivity** (`:1630`), and the cost proxy `rank` is consulted **only when selectivities are exactly equal** (`:1635`). The cost information exists: `get_opcode_rank()` `src/optimizer/query_graph.c:3406` classifies `PT_LIKE` in "Group 3 -- heavy" | `src/backend/optimizer/plan/createplan.c` `order_qual_clauses()` sorts strictly by `cost_qual_eval_node()` per-tuple cost (`items[i].cost = qcost.per_tuple`), security level being the only higher key | CUBRID orders by estimated selectivity and discards its own heavy/light classification unless there is an exact tie, so a 21.7x-underestimated LIKE (0.0092) sorts ahead of an accurately estimated integer equality (0.02) and runs on all 2,000,000 rows. PostgreSQL orders by cost, but assigns `textlike` the default `procost` equal to `int4eq`, so its stable sort preserves list order and it *also* evaluates the LIKE first — confirmed empirically: both-predicates 106 ms ≈ LIKE-only 109 ms, versus ~88 ms for the cheap predicate alone. Neither engine gets this right; only CUBRID is badly hurt, because its matcher is 9.75x more expensive. | common to both engines |
| UTF-8 LIKE matcher inner loop | `src/base/language_support.c:2831` `lang_strmatch_utf8()` — per character position it calls `intl_utf8_to_cp()` on **both** target and pattern (`:2857-2858`) and maps each codepoint through the collation weight table `weight_ptr[cp1]`/`[cp2]` (`:2869-2894`); driven from `src/query/string_opfunc.c:5906` `qstr_eval_like()`. No byte-lockstep path and no ASCII fast path | `src/backend/utils/adt/like_match.c:84` `MatchText()` — documents and implements byte-by-byte comparison "even for multi-byte encodings" because text and pattern stay in lockstep, with `NextChar` for UTF-8 defined as the inline macro `do { (p)++; (plen)--; } while ((plen) > 0 && (*(p) & 0xC0) == 0x80 )` at `src/backend/utils/adt/like.c:129-131`; `MatchText` bound to `UTF8_MatchText` at `:132` | PostgreSQL compares raw bytes and advances characters with a two-instruction inline macro; CUBRID decodes both operands to codepoints through a non-inlined PLT call per character and then performs two collation-weight table lookups. Measured on the identical 2,000,000-row predicate: 418.1 ns/row vs 42.9 ns/row (**9.75x**, profile band), corroborated by a same-engine A/B increment of 181.5 ms vs 21.0 ms (**8.64x**). 2.82% of CUBRID's query CPU is PLT stub overhead alone. | same stage, lower measured cost |
| Correlated-subquery result cache | `src/query/query_executor.c` subquery cache, observed live as `SUBQUERY_CACHE (hit: 47124, miss: 15708, size: 3276896, status: enabled)` in `q2-trace-cubrid.out`, plus `MEMOIZE` on each inner index scan (`hit: 176/13926/18648`) | no counterpart for a `SubPlan` expression: `q2-plan-act-pg.out` shows `SubPlan expr_1` re-executed `loops=6351` with no cache node; PostgreSQL's `Memoize` node applies to parameterized *paths*, not `SubPlan` expressions | CUBRID answers 47,124 of 62,832 correlated `min(ps_supplycost)` probes from cache (75.0% hit) and so executes the subquery 15,708 times; PostgreSQL executes its `SubPlan` 6,351 times but must re-derive each. This is a CUBRID *advantage*, recorded for completeness — it is a PostgreSQL-side structural absence, not a CUBRID improvement candidate. | structural absence |
| Tuple deform and buffer access | `heap_attrinfo_read_dbvalues` 6.17%, `mr_readval_string_internal` 1.30%, `spage_get_record` 1.14%, `pgbuf_fix_release`+`pgbuf_unfix` 3.87% | `nocachegetattr` 3.50%, `tts_buffer_heap_getsomeattrs` 3.18%, `heap_fill_tuple` 4.37%, `heap_hot_search_buffer` 8.38%, `hash_search_with_hash_value` 7.28%, `PinBuffer` 2.61% | Comparable proportional cost on both sides (CUBRID ~12.5%, PostgreSQL ~29% — the latter higher because its plan touches 3.18x more tuples). Not a CUBRID-specific defect. | common to both engines |

Absence claim for the fourth row (PostgreSQL correlated-subquery cache) was
established by searching the pinned PostgreSQL tree
`/home/cubrid/dev/postgres` at `5713b437`: `SubPlan` execution goes through
`ExecSubPlan`/`ExecScanSubPlan` with no result-cache node interposed, and
`Memoize` (`src/backend/executor/nodeMemoize.c`) is only ever placed on a
parameterized inner *path* by `createplan.c`/`pathnode.c`, never on a `SubPlan`
expression. The live plan confirms it: `SubPlan expr_1` shows `loops=6351` with no
cache node and no hit/miss instrumentation.

## 8. Causal decomposition details

1. **Parallelism is the largest single factor, and it is a plan consequence.**
   `1/F_units = 4.4136x`. CUBRID actually ran 5 launched workers at TWU 4.6663 with a
   0.000 s serial tail; PostgreSQL launched 4 workers but reached TWU 1.0681 with a
   0.486 s serial tail, because its 4 workers only cover the `part` index scan
   (38.710 ms of 2,836 ms) while the 1.6M-row nested loop, the 293 MB external-merge
   sort, the materialize, the merge join and the `SubPlan` all execute in the leader.
   This is *not* a configured-cap artefact: the cap is 5 and the planner asked for 4.
   Because the low utilization follows from the chosen plan, this factor and the
   unquantified `F_plan` are entangled; that is stated rather than resolved.
2. **Work volume is the second factor.** `1/F_work = 3.1806x`. Per-node derivation,
   each node counted once (rows it output plus rows its own filter rejected):

   | CUBRID node | tuples | PostgreSQL node | tuples |
   |---|---|---|---|
   | `part` parallel scan (readrows) | 2,000,000 | `Parallel Index Scan part` examined | 2,000,000 |
   | `partsupp` iscan `fk_partsupp_part` | 31,416 | `Gather Merge` | 7,854 |
   | `supplier` iscan pk | 9,160 | `Seq Scan region` (NL outer) | 5 |
   | `nation` iscan pk | 78 | `Seq Scan supplier` | 100,000 |
   | `region` iscan pk | 24 | `Seq Scan nation` / `Hash` | 25 / 25 |
   | subq `partsupp` iscan | 62,832 | `Hash Join supplier×nation` | 100,000 |
   | subq `supplier` iscan | 62,832 | NL `region×(supplier⋈nation)` examined | 100,000 |
   | subq `nation` iscan | 59,230 | `Index Scan idx_fk_partsupp_supplier` | 1,602,640 |
   | subq `region` iscan | 46,300 | `Sort` external merge input | 1,602,443 |
   | `ORDERBY` top-N input | 4,667 | `Materialize` input | 1,602,443 |
   | | | `Merge Join` filter evaluations | 6,351 |
   | | | `SubPlan expr_1` inner tuples (6,351 loops) | 114,318 |
   | | | top-N `Sort` input | 4,667 |
   | **W_C** | **2,276,539** | **W_P** | **7,240,771** |

   The gap is almost entirely three PostgreSQL nodes — the 1.6M-row index scan, sort
   and materialize (4,807,526 tuples, 66.4% of `W_P`) — which exist only because of
   its merge-join plan.
3. **Per-tuple CPU cost is where CUBRID loses.** `F_cost = 1.9907` (786.3 ns vs
   395.0 ns per tuple touch). Decomposed by `perf`: 2.603x instructions per tuple at
   1.307x better instruction throughput → 1.991x, matching `F_cost` to 3 decimals.
   The deficit is instruction count, not stalling.
4. **Localisation of the per-tuple deficit.** 46.72% of CUBRID's profiled self cost
   is the LIKE/UTF-8 band against 3.00% for PostgreSQL on the *same* 2,000,000-row
   predicate — 418.1 ns/row vs 42.9 ns/row. A same-engine A/B confirms it
   independently: adding `p_type like '%BRASS'` to a bare `part` scan costs CUBRID
   +181.5 ms wall and PostgreSQL +21.0 ms, **both at 5 active units** — CUBRID
   `parallel workers: 5` and PostgreSQL `Workers Launched: 4` + leader on *both*
   variants, evidenced in `q2-predicate-ab-units.txt` — so 0.907 vs 0.105 core-s per
   2M rows (8.64x). Two independent methods (9.75x profile-band,
   8.64x A/B) bracket the same effect.
5. **The predicate order amplifies it, and both engines get the order wrong.**
   CUBRID evaluates the expensive LIKE on all 2,000,000 rows instead of the 39,575
   surviving `p_size=15`, because its ordering key is estimated selectivity and its
   LIKE estimate is 21.7x low. Measured A/B: `p_size=15` alone 0.062 s, LIKE alone
   0.2435 s, both 0.2535 s — i.e. "both" costs what LIKE-first costs, and the SQL
   text order is irrelevant (0.2535 s vs 0.2530 s when swapped). If the cheap
   predicate ran first the stage would cost `0.062 + 0.1815 × 39575/2000000 = 65.6 ms`
   instead of 253 ms, taking Q02 from 353 ms to ~166 ms (**−53.1%**). PostgreSQL has
   the same ordering flaw (both 106 ms ≈ LIKE-only 109 ms vs 88 ms cheap-only) but
   loses only ~0.7% of its wall to it, because its matcher is 9.75x cheaper.
6. **Explanations considered and rejected, with the number that rejected each.**
   - *"PostgreSQL is slow because it spills 293 MB to disk."* Rejected as a
     first-order cause: device `write_bytes` across the telemetry run was
     **0.08 MiB** and device reads **0** — the 293,024 kB of temp lives in the OS
     page cache. The spill's cost is CPU/memory-bandwidth on 1.6M tuples, already
     carried by `F_work`; counting it again as I/O would double-count.
   - *"The FK indexes explain the difference."* Rejected: **both** engines use them
     (`fk_partsupp_part`; `idx_fk_partsupp_part` + `idx_fk_partsupp_supplier`), so
     they cannot be the differentiator. They do make Q02 a genuine FK-campaign
     query — this plan is unavailable under the discarded PK-only schema.
   - *"CUBRID wins on parallelism alone."* Rejected: `1/F_units = 4.4136x` of the
     total **6.7860x**; the remaining **1.5978x** is CPU-seconds, and within that
     CUBRID is 1.99x *worse* per tuple. Parallelism is the largest factor, not the
     only one.
   - *"CUBRID's engine is simply more CPU-efficient here."* Rejected: `F_cost =
     1.9907` and 5,031 vs 1,933 instructions per tuple show the opposite. CUBRID wins
     despite worse per-tuple efficiency.
   - *"The 21.7x LIKE selectivity error caused a bad join order."* Rejected as the
     mechanism of harm: CUBRID's join order (drive from `part`, probe `partsupp` by
     FK index) is the *good* order and is what beats PostgreSQL. The measured harm of
     the misestimate is confined to predicate evaluation order inside the `part`
     scan, worth 53.1% of Q02 — large, but not a join-order defect.
   - *"CUBRID's `SUBQUERY_CACHE` is the main advantage."* Rejected as primary: the
     correlated subquery is 115 ms of CUBRID's 399 ms traced time and the cache
     saves 47,124 of 62,832 probes (75.0%). Removing the cache entirely would add
     roughly 3x that subtree (~+345 ms), taking CUBRID to ~0.70 s — still 3.4x faster
     than PostgreSQL's 2.395 s. Real, but secondary.
   - *"Q01's buffer-replacement finding (IMP-002) applies here too."* Rejected: Q02's
     working set (1,858 MiB CUBRID / 1,706 MB PostgreSQL) fits the equal 8,192 MB
     budget, CUBRID's pool is conserved at 524,288 pages across the block and every
     trace node reports `ioread: 0`. No reuse deficit exists to observe.

Error budget and closure: residual −3.770% against a combined within-block relative
sd of 0.777% **plus** the measured single-statement-per-connection regime offsets of
+8.11% (CUBRID) and +12.35% (PostgreSQL), whose differential predicts −3.770%. The
prediction matches the observation to 0.000 pp, so the residual is accounted for
deterministically rather than absorbed into noise. The card is closed.

## 9. Improvements

Registry state before Q02: `IMP-001`, `IMP-002` (both from Q01), `next_id:
IMP-003`. Deduplication: the Git ledger was searched by title, both source locations
and root cause. `IMP-001` is NUMERIC aggregate accumulation
(`numeric_opfunc.c:2477`) and `IMP-002` is data-buffer replacement
(`page_buffer.c`); neither overlaps a LIKE/selectivity path, so Q02 allocates two new
IDs and `next_id` advances to `IMP-005`. No old-campaign candidate ID was consulted.

| ID | Root cause | Priority | Category | Status | Evidence type | Effect |
|---|---|---|---|---|---|---|
| `IMP-003` | Leading-wildcard LIKE selectivity estimated from bucket *boundary* values only, producing a 21.7x under-estimate that then decides conjunctive predicate evaluation order | **P0** | optimizer | `measured` | direct A/B | **−53.1% of Q02 wall** (353 ms → ~166 ms) |
| `IMP-004` | UTF-8 LIKE matcher decodes both operands to codepoints per character through PLT calls plus collation-weight lookups, with no byte-lockstep or ASCII fast path | **P1** | expression/type | `measured` | direct A/B + profile attribution | 8.64–9.75x per-row LIKE cost; band = 46.72% of Q02 CPU (0.836 of 1.79 core-s) |

**Ranking justification.** `IMP-003` outranks `IMP-004` on three measured grounds,
even though `IMP-004` owns the larger raw profile band. First, `IMP-003` alone
captures most of `IMP-004`'s Q02 benefit: fixing the estimate reorders the
predicates, which cuts LIKE evaluations from 2,000,000 to 39,575 (50.5x) and yields
the measured −53.1%, whereas fixing only the matcher (8.64x cheaper per row) would
reduce the same 253 ms stage to about 62 + 181.5/8.64 = 83 ms, i.e. −48.2% — similar
in Q02 but achieved by making a wasted computation faster rather than not doing it.
Second, `IMP-003` is a localized arithmetic change inside one estimator, whereas
`IMP-004` touches the collation dispatch path used by every string comparison, so it
carries materially more regression surface. Third, `IMP-003` has direct upstream
precedent in the pinned history (CBRD-27039, same file, same defect class) while
`IMP-004` has none. The two are recorded with a containment relation and their
effects are **not summed**: for Q02 they overlap almost completely, and the honest
combined statement is bounded by the ordering fix alone.

### IMP-003 — LIKE selectivity from bucket boundaries misorders conjunctive predicates

- **Mechanism, CUBRID.** For the non-MCV mass of a string histogram,
  `histogram_get_like_selectivity()` (`src/optimizer/histogram/histogram_cl.cpp:1427`)
  tests the pattern against **one value per bucket** — the bucket's upper boundary
  `bucket_hi` — and, once the histogram has ≥100 entries, uses that matching-bucket
  fraction directly as the selectivity (`:1487-1501`, `:1508-1512`). A bucket
  boundary is an artefact of sort order, so a suffix pattern uncorrelated with that
  order matches boundaries at a frequency unrelated to its true frequency. The result
  feeds `qo_like_selectivity()` (`src/optimizer/query_planner.c:10068`, call at
  `:10101`) and becomes the term's selectivity. `make_pred_from_bitset()`
  (`src/optimizer/plan_generation.c:1577`) then orders AND-predicates by selectivity
  (`:1630`) and consults its own cost proxy `rank` **only on an exact selectivity
  tie** (`:1635`) — even though `get_opcode_rank()`
  (`src/optimizer/query_graph.c:3406`) already classifies `PT_LIKE` as
  "Group 3 -- heavy". Net effect: `p_type like '%BRASS'` (estimated 0.00921158,
  actual 0.19979) is placed ahead of `p_size = 15` (estimated 0.02, actual 0.0198)
  and is evaluated on all 2,000,000 `part` rows.
- **Mechanism, PostgreSQL.** `histogram_selectivity()`
  (`src/backend/utils/adt/selfuncs.c:898`) applies the operator function across the
  histogram bound array and `mcv_selectivity()` (`:807`) across the MCV list,
  combining both for pattern operators at `:1032`/`:1042`. Its leading-wildcard
  estimate lands at 0.26099 against a true 0.19979 (1.31x), versus CUBRID's 21.7x.
- **Why the direction follows.** The estimator already LIKE-tests MCVs correctly; the
  defect is confined to using a single boundary string as a bucket's proxy. Probing
  stored bucket sample values, or falling back to `like_term_selectivity` when the
  pattern has no usable prefix, removes the 21.7x error, which in turn fixes the
  ordering without any change to the ordering code.
- **Evidence event and denominator.** LIKE evaluations per `part` scan: 2,000,000
  actual vs 39,575 achievable, denominator = rows scanned in the `part` node.
  A/B walls: `p_size=15` 0.062 s, LIKE-only 0.2435 s, both 0.2535 s, swapped order
  0.2530 s (`q2-predicate-ab-cubrid.out`); estimate vs actual from
  `q2-plan-est-cubrid.out` (`sel 0.00921158`, `card 368`) against measured counts
  39,575 / 399,587 / 7,854.
- **Effect range.** −53.1% of Q02 wall (353 ms → ~166 ms), evidence type direct A/B.
  Generalizes to any query whose cheap predicate is estimated less selective than an
  expensive string predicate on the same relation.
- **Implementation direction.** In `histogram_get_like_selectivity()`, treat a
  pattern with no usable fixed prefix as not estimable from bucket boundaries: either
  probe per-bucket stored sample values, or set `*success = false` so
  `qo_like_selectivity()` falls back to `PRM_ID_LIKE_TERM_SELECTIVITY`. Optionally,
  and separately, promote `rank` above selectivity in `make_pred_from_bitset()` when
  the rank classes differ by more than one group.
- **Correctness/regression risk.** Low-to-medium: selectivity affects plan choice
  only, never results. Risk is plan churn on other string predicates — a fallback to
  the parameter default is deliberately conservative, and prefix patterns
  (`'ABC%'`), which boundary probing does handle correctly, must keep their current
  path.
- **Validation criteria.** (1) `p_type like '%BRASS'` estimated selectivity within
  2x of 0.19979; (2) `q2-plan-est-cubrid.out` shows `sargs: term[p_size] AND
  term[like]` order inverted; (3) Q02 median wall ≤ 0.20 s with byte-identical
  100-row output versus `Q02-cubrid-headline.out`; (4) no Q01–Q22 plan regression.
- **Priority.** **P0** — the single largest measured, actionable CUBRID-side effect
  in Q02: −53.1% of wall from one estimator change.
- **Difficulty.** **Low-to-medium** — a localized early-return/fallback in one
  function; medium only if per-bucket sample probing is chosen over the fallback.
- **Upstream precedent.** Yes: `5510afbfb` `[CBRD-27039] Fix five
  histogram-consumption defects (selectivity math + concurrent-fetch robustness)
  (#7442)` — same file, same class of change, and an ancestor of the pinned build
  `607f1ee9`. Related: `aabba8d1e [CBRD-26202] Add Optimizer Histogram Support
  (#7180)` introduced this estimator; `10d0aa0e7 [CBRD-26746]` extended histogram use
  to equi-join selectivity. Predicate-order precedent: `ce7937a27 [CBRD-24668]`.
- **Relations.** Predecessor: none. Alternative: promoting `rank` above selectivity
  in `make_pred_from_bitset()` (same outcome for Q02, wider blast radius).
  Containment: **contains most of `IMP-004`'s Q02 effect** — after this fix only
  39,575 rows reach the matcher.

### IMP-004 — UTF-8 LIKE matcher has no byte-lockstep or ASCII fast path

- **Mechanism, CUBRID.** `lang_strmatch_utf8()`
  (`src/base/language_support.c:2831`), driven from `qstr_eval_like()`
  (`src/query/string_opfunc.c:5906`), advances one *character* at a time and per
  position calls `intl_utf8_to_cp()` on **both** the target and the pattern
  (`:2857-2858`), then maps each resulting codepoint through the collation weight
  table (`weight_ptr[cp1]`, `weight_ptr[cp2]`, `:2869-2894`). There is no ASCII fast
  path and no byte-lockstep comparison. The profile shows the two decode helpers
  reached through the PLT on every character: `intl_utf8_to_cp` 4.82% +
  `@plt` 1.75%, `intl_nextchar_utf8` 3.09% + `@plt` 1.07%.
- **Mechanism, PostgreSQL.** `MatchText()`
  (`src/backend/utils/adt/like_match.c:84`) explicitly compares **byte by byte even
  for multi-byte encodings**, on the documented grounds that text and pattern stay in
  lockstep outside wildcard handling; character advancement uses the inline macro
  `NextChar(p, plen) do { (p)++; (plen)--; } while ((plen) > 0 && (*(p) & 0xC0) ==
  0x80 )` (`src/backend/utils/adt/like.c:129-131`, bound to `UTF8_MatchText` at
  `:132`). No codepoint materialization, no weight-table lookup, no out-of-line call.
- **Why the direction follows.** The pattern `'%BRASS'` and the column are pure
  ASCII under a deterministic collation, so codepoint decoding and weight mapping are
  provably redundant: byte equality implies weight equality in that case. A
  fast path gated on "deterministic collation and both operands single-byte/ASCII"
  reproduces PostgreSQL's cheap loop without touching general collation semantics.
- **Evidence event and denominator.** CPU-seconds per `part` row for the LIKE
  predicate, denominator = 2,000,000 rows scanned. Profile band 46.72% × 1.79 =
  0.836 core-s → 418.1 ns/row, versus PostgreSQL `UTF8_MatchText` 3.00% × 2.86 =
  0.0858 core-s → 42.9 ns/row (**9.75x**). Independent A/B: +181.5 ms vs +21.0 ms
  wall at 5 active units on both engines → 0.907 vs 0.105 core-s (**8.64x**).
- **Effect range.** 8.64x–9.75x reduction of per-row LIKE cost; upper bound on Q02 is
  the 46.72% band (0.836 core-s of 1.79). Evidence type: direct A/B plus profile
  attribution. **Not additive with `IMP-003`.**
- **Implementation direction.** Add an early fast path in `lang_strmatch_utf8()` (or
  dispatch from `qstr_eval_like()`) for deterministic built-in collations where both
  operands are ASCII: compare bytes and advance with an inlined continuation-byte
  skip. Secondarily, make `intl_utf8_to_cp`/`intl_nextchar_utf8` inlinable (static
  inline in a header, or `-fvisibility` hidden) to remove the 2.82% PLT overhead.
- **Correctness/regression risk.** **Medium-to-high** — this path implements LIKE
  semantics for every collation, including contraction- and UCA-level collations
  (`lang_strmatch_utf8_w_contr`, `lang_strmatch_utf8_uca_w_level`). The fast path
  must be gated so that any non-deterministic collation, contraction table,
  case-insensitive collation, trailing-space rule or non-ASCII byte falls back to the
  existing loop.
- **Validation criteria.** (1) full LIKE/collation regression suite unchanged,
  including contraction and case-insensitive collations and `ignore_trailing_space`;
  (2) `select count(*) from part where p_type like '%BRASS'` returns 399,587 with
  wall ≤ 0.10 s; (3) `lang_strmatch_utf8` + `intl_*` band below 15% in a re-profiled
  Q02; (4) Q02 output byte-identical to `Q02-cubrid-headline.out`.
- **Priority.** **P1** — larger raw band than `IMP-003` (46.72% of query CPU) but
  ranked lower because `IMP-003` removes 98.0% of the affected rows for less risk;
  P1 rather than P2 because the matcher is shared by every LIKE in the workload, so
  the fix generalizes beyond Q02.
- **Difficulty.** **Medium** — the fast path itself is small, but correct gating
  across the collation matrix (built-in vs UCA, contractions, case-insensitive,
  trailing-space) is the real work; inlining the helpers is a separate low-risk step.
- **Upstream precedent.** **No precedent found.** Searching the pinned CUBRID history
  for LIKE/collation matcher optimization work returned only correctness and feature
  commits (e.g. `14589b6fa`, `c37a85a2a` on communication histograms; no
  `lang_strmatch_*` performance change). Recorded explicitly as no-precedent.
- **Relations.** Predecessor: none. Alternative: `IMP-003` (cheaper, achieves a
  similar Q02 result by avoiding the work instead of accelerating it). Containment:
  **contained by `IMP-003` for Q02**; independent for any query where the LIKE cannot
  be deferred behind a cheaper predicate.

Neither candidate is marked `validated`: no correctness evidence for a fix exists
yet. Full fields in `reports/improvement-registry.json`.

## 10. Evidence index

Format: `claim → raw file → formula → evidence type → SHA-256`.
All paths are under `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q02/`; byte sizes
and full hashes for all **54** artifacts are in `reports/Q02/raw-manifest.json`.

| Claim | Raw file | Formula / basis | Evidence type | SHA-256 |
|---|---|---|---|---|
| preflight: ownership OK, 35 TIDs 0 off-cpuset, load 0.542, 8FK/8-btree, row counts, contract values, provenance | `preflight-Q02.txt` | direct capture | direct A/B | `5499c774e8c0dd36…` |
| Q02 `result-equivalent-at-SF10`, 100 rows ordered | `q2-correctness.json` | ordered sequence compare, 1e-12 relative on numerics | direct A/B | `5de304f32eee896d…` |
| CUBRID result rows (raw text preserved) | `q2-correctness-cubrid.out` | — | direct A/B | `e89abe13c9105a77…` |
| PostgreSQL result rows (raw text preserved) | `q2-correctness-postgresql.out` | — | direct A/B | `9ac201cec02d2e2e…` |
| CUBRID estimated plan, non-executing; `sel 0.00921158`, `card 368`, sarg order LIKE-first | `q2-plan-est-cubrid.out` | `SET OPTIMIZATION LEVEL 514` | direct A/B | `dd92a7705fc8d74c…` |
| PostgreSQL estimated plan + live `Settings:` | `q2-plan-est-pg.out` | `EXPLAIN (COSTS, VERBOSE, SETTINGS)` | direct A/B | `e796a4b1089f65ce…` |
| CUBRID 3 headline values, median 0.353000 s, WARM gauges | `Q02-cubrid-headline.json` | median of 3 measured statements | direct A/B | `a3e3de32752f4242…` |
| CUBRID sink, 4 stmts × 100 rows fully consumed | `Q02-cubrid-headline.out` | per-statement `(N sec)` lines | direct A/B | `7a23799325d52d3f…` |
| PostgreSQL 3 headline values, median 2.395453 s, `heap_blks_read` delta 0 | `Q02-postgresql-headline.json` | median of 3 measured statements | direct A/B | `d6bf28369755d3f8…` |
| PostgreSQL sink, 4 stmts × 100 rows fully consumed | `Q02-postgresql-headline.out` | `\timing` per statement | direct A/B | `5a4c8c1aa45b993c…` |
| `parallel workers: 5`, `topnsort: true`, `SUBQUERY_CACHE hit 47124/miss 15708`, MEMOIZE, `ioread: 0` | `q2-trace-cubrid.out` | `SET TRACE ON` + `SHOW TRACE` | direct A/B | `68a5211a217b9798…` |
| `Workers Launched: 4`, `external merge Disk: 293024kB`, `temp read=73250`, 1,602,443 sorted rows, `SubPlan loops=6351` | `q2-plan-act-pg.out` | `EXPLAIN ANALYZE BUFFERS` | direct A/B | `6d5fd16cc8f93700…` |
| plan counterfactual: `enable_mergejoin=off` → 2731.477 ms, still 1.6M-row build | `q2-plan-act-pg-controlled.out` | `EXPLAIN ANALYZE` under GUC | direct A/B | `d1f3376ffbc711d7…` |
| plan counterfactual: `+enable_hashjoin=off` → 21083.361 ms, seq-scan-per-row penalty | `q2-plan-act-pg-nl.out` | `EXPLAIN ANALYZE` under GUC | direct A/B | `5846040af3495937…` |
| predicate-cost A/B: 0.062 / 0.2435 / 0.2535 / 0.2530 s, counts 39,575 / 399,587 / 7,854 | `q2-predicate-ab-cubrid.out` | wall per statement, same connection | direct A/B | `f1c4c549c92e67c3…` |
| CUBRID `total_query_cpu` 1.79 core-s, TWU 4.6663, serial tail 0.000 s (median run) | `Q02-cubrid-telemetry-run2.json` | per-TID ticks / `SC_CLK_TCK`, actual dt weighting | profile attribution | `f90f93bc843bf356…` |
| PostgreSQL `total_query_cpu` 2.86 core-s, TWU 1.0681, serial tail 0.486 s (median run) | `Q02-postgresql-telemetry-run1.json` | per-TID ticks / `SC_CLK_TCK`, actual dt weighting | profile attribution | `ca47329aba606063…` |
| telemetry reproducibility (3 runs/engine) and +8.11%/+12.35% regime offsets | `Q02-{cubrid,postgresql}-telemetry-run{1,2,3}.json` | wall vs headline median | profile attribution | see manifest |
| CUBRID IPC 2.325, 4.965 CPUs utilized | `perf-stat-cubrid.txt` | `instructions/cycles`, `task-clock/elapsed` | profile attribution | `71534236cc1d30b3…` |
| PostgreSQL IPC 1.710, 1.015 CPUs utilized | `perf-stat-pg.txt` | `instructions/cycles`, `task-clock/elapsed` | profile attribution | `896e9c121ef92c78…` |
| CUBRID LIKE/UTF-8 band 46.72%, 0 unresolved symbols | `profile-cubrid-flat.txt` | `perf report` self% | profile attribution | `6df8836707d2e3fc…` |
| PostgreSQL `UTF8_MatchText` 3.00%, 0 unresolved symbols | `profile-pg-flat.txt` | `perf report` self% | profile attribution | `1617e7212bb96226…` |
| call paths for `lang_strmatch_utf8` / `qstr_eval_like` | `profile-cubrid-callgraph.txt` | dwarf call-graph | profile attribution | see manifest |
| `dynamic_shared_memory_type=mmap` live; PHJ executes (5 workers, 16 batches) with `/dev/shm` at 628k/64000k; PHJ absent from Q02 for planner reasons | `q2-shared-memory-verification.txt` | direct capture + forced-path probe | direct A/B | `29298d5a6a4256a0…` |
| Q02 forced hash path probe input | `q2-phj-probe.sql` | `EXPLAIN ANALYZE` under `enable_mergejoin=off` | direct A/B | `6309332339152d61…` |
| A/B active-unit basis: CUBRID `parallel workers: 5` on both variants; PostgreSQL `Workers Launched: 4` + leader on both | `q2-predicate-ab-units.txt` | trace + `EXPLAIN ANALYZE` per variant | direct A/B | `d31b1a8068f47ec5…` |
| perf coverage: CUBRID 36,429 samples, PostgreSQL 15,790 samples, 0 lost | `perf-record-cubrid.log` (`perf-record-pg.log` `7f763cd104388ffe…`) | `perf record` stderr | profile attribution | `5280543931502a6f…` |
| perf driver consumed all rows (60 CUBRID statements; 16 x 100 PostgreSQL rows) | `Q02-cubrid-perf-driver-sink.out` (`Q02-postgresql-perf-driver-sink.out` `64370e36197a20ee…`) | statement result markers | direct A/B | `b329fd59d8e34d03…` |
| card factors, `W` per-node derivation, residual −3.770% vs predicted −3.770% | `Q02-causal-card.json` | section 16 formulas | profile attribution | `fd97ecfbb572bc38…` |

Truncated hashes above are the manifest's first 16 hex digits; the manifest carries
the full 64-hex value, byte size and creation command for every artifact.

## 11. Notion sync

**Status: `NOTION_OUT_OF_WORKER_SCOPE` → idempotent Git backfill record written
(write path 3 only).**

Section 21's execution boundary (as tightened at pins `2a5c4452…`, `f8c7cfd0…`) is
explicit: this GJC/tmux worker session runs on the remote build host, has no Notion
connector, and **must never attempt a Notion write**. Its Notion-adjacent duty ends
at committing and pushing this report and manifest to `origin/main`. Accordingly:

1. *official Notion connector* — **not attempted** (forbidden for the worker; also
   not exposed to this session's tool set).
2. *logged-in Aside browser* — **not attempted** (forbidden for the worker).
3. *idempotent Git backfill record* — **written**: appended to
   `reports/notion_backfill_pending.jsonl`, keyed on
   `campaign_id + QNN + session_id + report_commit + content_fingerprint`, carrying
   the section 21 required query fields with the same field names as this report.
   `content_fingerprint` follows the Q01 convention: sha256 of this `report.md` at
   `report_commit`. The record was written only after the report, manifest and
   registry were durable on `origin/main`, so the key it carries is stable and a
   later re-run of the same reconciliation cannot produce a second, differently-keyed
   row for the same content. `pending_cleared` is `false`.

This satisfies the section 26 gate item ("Notion relations are synced **or** an
idempotent backfill record is durable") without a Notion call. Pending is **not**
cleared: clearing requires a server-side refetch, which only a Notion-capable
subagent may perform. Per the section 21 execution boundary, the actual mirror
write — operational state, the Q01–Q22 row, and one page per improvement candidate,
at the section 21 content-depth floor — is performed by a dedicated Notion-capable
subagent dispatched during section 23 reconciliation, reading the pushed commit as
source of truth. Sections 3-a, 3-b, 4, 6, 7, 8 and 9 of this report are written to
be that mirror's source, including the full factor table, both engines' plan shapes,
both engines' top-cost symbols, `file:line` on both sides of every contrast, the
rejected explanations with their rejecting numbers, and the complete section 18
content for `IMP-003` and `IMP-004`.

## 12. Completion checklist

- [x] preflight and correctness status recorded (section 1, section 2)
- [x] three valid headline values for each completing engine (both engines completed;
      neither censored)
- [x] timeout confirmations — not applicable, neither engine censored
- [x] plan, execution, profile and source contrast sections complete
- [x] causal multiplier card has evidence for every factor, with `F_plan` recorded as
      explicit `UNMEASURED` and three counterfactuals documenting why; residual
      −3.770% matches its measured prediction to 0.000 pp
- [x] Git improvement ledger deduplicated and committed (`IMP-003`, `IMP-004`, each
      carrying the full section 18 field set including priority, category,
      difficulty, upstream precedent and ranking justification)
- [x] every claim indexed to raw evidence and checksum (54 artifacts)
- [x] report, manifest and registry committed, pushed and reachable from
      `origin/main`. Durable commits: `05ea623` (report, raw manifest,
      `IMP-003`/`IMP-004`), `dd17518` (section 9 shared-memory contract and the
      Parallel-Hash-Join availability proof), `2c34e58` (registry merge placing
      `IMP-003`/`IMP-004` on top of `origin/main`'s section-18-enriched
      `IMP-001`/`IMP-002`, field names harmonized to `ranking_rationale` and array
      `category`, `next_id: IMP-005`), and merge `3c53999`; plus this finalizing
      commit and the backfill-record commit that follows it. Verified after the
      merge: `report.md`, `raw-manifest.json` and `improvement-registry.json` are
      byte-identical to the blobs on `origin/main`, all **47** raw artifacts
      re-hash to their manifest entries (0 mismatched, 0 missing), and all 24
      evidence-index rows still match the manifest.
      A push-integration blocker occurred and was handled per section 4: the first
      push was rejected non-fast-forward because `origin/main` had advanced with a
      concurrent edit to the same `improvement-registry.json`. No automatic rebase
      or merge was performed; the divergence was reported with the exact overlap and
      resolved by the main session, after which this worker re-verified the merged
      result rather than assuming it.
- [x] `QUERY_COMPLETE` emitted by the worker session
- [ ] **current session removed and absence verified — OUTSTANDING, control-plane
      action.** This worker *is* the Q02 session: tmux session
      `gajae_code_ms7esqu3_mj3cgscn`. Self-removal would terminate the worker
      mid-turn and make the mandated dual absence check unobservable, so it is
      deliberately NOT claimed here. Per section 22 steps 7-9 and the section 23
      `QUERY_COMPLETE` action, removal and absence verification are performed from
      outside this session, before any Q03 session is created:

      ```
      gjc session remove gajae_code_ms7esqu3_mj3cgscn
      gjc session status gajae_code_ms7esqu3_mj3cgscn      # expect: absent
      tmux has-session -t gajae_code_ms7esqu3_mj3cgscn     # expect: non-zero exit
      # if remove refuses a live session, exact-target fallback (never by pattern):
      tmux kill-session -t gajae_code_ms7esqu3_mj3cgscn
      ```

      The Q01 session `gajae_code_ms7bmpvn_fqbk4jb6` was verified absent at the start
      of this query by both checks (`gjc session status` →
      `gjc_tmux_session_not_found`, `tmux has-session` → exit 1), so the section 22
      "never two measurement sessions concurrently" rule held throughout Q02.

Known carried-forward gaps, explicitly recorded rather than silently omitted:

- CUBRID actual histogram bucket count remains `UNMEASURED` (opaque `VARBIT`
  catalog); target 300 is configured and verified. This directly limits `IMP-003`:
  the bucket boundary values that produce the 21.7x under-estimate cannot be read
  from SQL, so the estimator's exact arithmetic path is not reconstructed here — only
  its input parameters, its code path, and its measured output error.
- CUBRID accumulating perfmon counters (`Num_data_page_fetches`,
  `Num_data_page_ioreads`) remain frozen in this build, so WARM evidence uses
  `/proc/<pid>/io`, `/proc/diskstats`, the LRU zone gauges and the query trace's
  per-node `ioread` instead.
- The stage-14.7 CPU numerators come from single-statement-per-connection telemetry
  runs, which sit +8.11%/+12.35% above the headline medians. The effect on the card
  is quantified, predicted and closed (section 3-a, section 5) rather than removed; a
  future harness change could sample CPU inside the headline block itself.
- `reports/bootstrap/build-manifest.json` pins `ssot_commit 1d6a5ea6…` while this
  query ends pinned at `5912f065…`. The intervening SSOT changes touched the
  buffer/cache contract (already applied and recorded), the Notion execution
  boundary, the improvement-candidate quality bar and the shared-memory contract
  (which documents an already-live setting) — no engine SHA, schema, statistics,
  parallel-worker or timing term — so no bootstrap finding is invalidated.
- The CUBRID databases live under a repository-internal `.git_ignored_dir`; this is
  the reused SF10 dataset and moving it would be a destructive action outside the
  cleanup manifest, so it was left untouched and only recorded.
