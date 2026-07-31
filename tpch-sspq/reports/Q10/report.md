# TPCH-SSPQ FK campaign — Q10 report

## 3-a. Causal multiplier card

```text
R_wall 1.689622x [wall, median of 3 per engine; PostgreSQL is 1.6896x faster]
= F_plan  1.313675x [GROUP BY execution strategy; CUBRID-side controlled A/B, anchor named below]
× F_units 1.229390x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   1.046193x [total query CPU-seconds]

F_cpu 1.046193x is the CONTROLLED pair's CPU factor. On the native pair the same
quantity is 1.251216x, and it decomposes as

F_cpu(native) 1.251216x [total query CPU-seconds]
= F_work 0.283507x [plan-node tuple touches: 24,556,558 vs 86,617,111]
× F_cost 4.413350x [total-query CPU-seconds per tuple touch: 995.3 ns vs 225.5 ns]
```

**Read the card in one line: CUBRID picked the better plan and then ran the one node that
matters single-threaded.** Q10 is the first query of this campaign where CUBRID's optimizer
beats PostgreSQL's — forcing PostgreSQL onto CUBRID's index-nested-loop shape makes
**PostgreSQL 1.6979x faster** (4.218695 s → 2.484120 s), and forcing CUBRID onto
PostgreSQL's hash shape makes **CUBRID 1.94x slower** (7.13 s → 13.81/13.87 s). CUBRID still
loses 1.6896x, and **52.0% of the log-gap** is one defect: the `GROUP BY` sort that reduces
1,147,084 rows to 381,105 groups runs on **one** thread while every other node of the same
plan runs on **five or six**.

That is not an inference from a profile band. It is a same-engine controlled A/B whose
estimated plan tree is *byte-identical* to native (cost `649494` on both sides, same node
order, same indexes — `variants/plan-cubrid-NO_HASH_AGGREGATE.out` vs
`q10-plan-est-cubrid.out`), and whose result rows are *byte-identical* to native
(`q10-variant-equivalence.txt`, both SHA-256 `23bb9755…`). The only thing the
`/*+ NO_HASH_AGGREGATE */` hint changes is which aggregation strategy the executor takes, and
CUBRID's own trace prints the difference:

| | native | controlled `/*+ NO_HASH_AGGREGATE */` |
|---|---|---|
| `GROUPBY` node | `time: 3834, hash: partial, sort: true, page: 75893, ioread: 66611, rows: 381105` | `time: 2565, hash: false, sort: true, page: 24088, ioread: 0, rows: 381105` |
| `GROUPBY` workers | **no `(parallel workers: …)` sub-line at all** | `(parallel workers: 5, time: 261..268, page: 21758..22885, ioread: 4..6)` |
| temp list-file re-scan feeding it | `SCAN (temp time: 805, …)` | `SCAN (temp time: 274, …)` |
| whole-statement `ioread` | 76,808 | 11,646 |
| join subtree | 3168 ms | 3287 ms (unchanged within noise) |
| block-median wall | **7.128000 s** | **5.426000 s** |

`F_plan` is numeric by a **CUBRID-side controlled A/B**, direction stated explicitly:
*CUBRID native (plan-time hash-eligible → runtime `HS_REJECT_ALL` → **serial** fallback sort)
→ CUBRID controlled `/*+ NO_HASH_AGGREGATE */` (`HS_NONE` → **parallel** sort)*. The
remaining controlled cross-engine pair is (CUBRID controlled, PostgreSQL native) and carries
`F_units` and `F_cpu`; native and controlled denominators are never mixed.

Both engines' plans produce the **identical intermediate cardinalities
15,000,000 → 573,157 → 1,147,084 → 381,105 → 20**, independently confirmed by ground-truth
`count(*)` queries that both engines answer identically (`q10-groundtruth-cubrid.out`,
`q10-groundtruth-pg.out`) and cross-checked against `q10-plan-act-pg.out`'s `loops × rows`
and against CUBRID's trace `readrows`/`rows`.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 1.313675x | GROUP BY execution strategy (serial fallback sort vs parallel sort) on a byte-identical plan tree | same-engine controlled A/B on CUBRID | `T_C_native/T_C_nohashagg` = 7.128000/5.426000 | `Q10-cubrid-headline-block1.json`, `Q10-cubrid-nohashagg-headline.json`, `q10-trace-cubrid.out`, `variants/trace-cubrid-NO_HASH_AGGREGATE.out`, `variants/plan-cubrid-NO_HASH_AGGREGATE.out` | direct A/B |
| `F_units` | 1.229390x | active execution units | CPU-seconds / wall-second over the section 12 block | `U_P_native/U_C_nohashagg` = 4.63013/3.76620 | `Q10-postgresql-headline-telemetry-run2.json`, `Q10-cubrid-nohashagg-headline-telemetry.json` | profile attribution |
| `F_cpu` | 1.046193x | total query CPU-seconds | per query execution | `CPU_C_nohashagg/CPU_P_native` = 20.4354/19.5331 | same telemetry JSONs | profile attribution |
| `F_work` | 0.283507x | plan-node tuple touches | tuples | `W_C/W_P` = 24,556,558/86,617,111 | `q10-groundtruth-*.out`, `q10-plan-act-pg.out`, `q10-trace-cubrid.out`, `q10-card-calc.txt` | direct A/B |
| `F_cost` | 4.413350x | CPU-seconds per tuple touch | tuple touches | `(CPU_C/W_C)/(CPU_P/W_P)` = 995.3 ns / 225.5 ns | `Q10-causal-card.json`, `q10-card-calc.txt` | profile attribution |

**Second anchor.** Anchoring on the PostgreSQL side (*PostgreSQL native `Parallel Hash Join`
tree → PostgreSQL controlled `enable_hashjoin=off, enable_mergejoin=off`, i.e. CUBRID's
index-NL chain*) gives

```text
1.689622x = 0.588836x [plan] × 1.338884x [units] × 2.143147x [CPU-sec]
```

which also reconstructs exactly. `F_plan = 0.588836x` is **below 1.0**: PostgreSQL's own cost
model chose a plan **1.6979x slower** than the one CUBRID chose. Anchor B is therefore the
mirror image of Q09 — there CUBRID's optimizer was wrong and PostgreSQL's was right; here
CUBRID's is right and PostgreSQL's is wrong. Anchor B is stated with an explicit limitation:
turning off hash joins on the PostgreSQL side *also* switches its aggregation from
`GroupAggregate over Gather Merge` to `Finalize GroupAggregate over Gather Merge over Partial
GroupAggregate` (5 workers launched instead of 4), so anchor B's `F_plan` is a
join-shape-**plus**-parallel-aggregation factor, not a pure join-shape factor. Anchor A has no
such contamination: its plan tree is byte-identical.

The two anchors bracket the engine-level gap from both sides and agree:

- on the **same join shape**, CUBRID takes 7.128 s where PostgreSQL takes 2.484 s
  (**2.869427x**);
- of that, **1.313675x** is recovered by the group-by A/B alone, leaving
  5.426/2.484 = **2.184x** of residual per-tuple execution cost;
- and CUBRID reaches that 2.184x while touching **3.53x fewer tuples**
  (`F_work` 0.283507x), i.e. its per-tuple cost is **4.413350x** PostgreSQL's.

**Reconstruction residual = +0.000000% on anchor A and −0.000000% on anchor B, and as in
Q04–Q09 that is an identity, not a prediction.** `CPU_stmt` is attributed as `U × t_median`
with `U` measured on the same block regime the wall is defined on, so
`F_units × F_cpu = T_C/T_P` by construction. Closure rests on the independent quantities:

- **`U` reproducibility.** CUBRID native 3.41158 / 3.43793 / 3.42875 across three
  independently gated WARM-converged telemetry runs (**0.77%** max−min); PostgreSQL native
  4.66743 / 4.63013 / 4.57817 (**1.95%**).
- **TWU**, from actual sample timestamp deltas over the busy window only: **3.4245**
  (CUBRID, **−0.12%** from `U`), **4.5860** (PostgreSQL, **−0.95%**), **3.7477**
  (CUBRID `NO_HASH_AGGREGATE`, −0.49%), **4.6562** (PostgreSQL index-NL, +1.43%). Every
  configuration's independent unit estimate agrees with its `U` to under 1.5%.
- **`perf stat` on verified PID sets**, a third instrument: **3.518 CPUs utilized** for
  CUBRID (**+2.60%** against `U` = 3.42875) and **4.045** for PostgreSQL's
  postmaster-inherited leader+4-worker set (**−12.6%**; that set deliberately excludes the
  io workers and `psql`, which contribute 9.60 core-s of `auxiliary_query_cpu` per block).
- **An arithmetic prediction of `U` from the trace**, a fourth and fully independent route.
  Weighting CUBRID's traced node times by their observed worker counts —
  3168 ms at ~5.5 units (orders heap scan 6 workers, probe 5) + 805 ms at 5 + 3834 ms at
  **1** + 113 ms at 3 — predicts `U ≈ 3.24` against the measured 3.42875 (**−5.5%**). No
  weighting that puts the `GROUPBY` node above 1 unit can reach the measured value; the
  serial group-by is required to explain `U`.
- **Instructions and IPC**, a separate counter path: CUBRID **468.376 G instructions at
  IPC 1.59**, PostgreSQL **534.074 G at IPC 1.59** over their respective 30.002 s windows;
  normalised per statement that is **78.06 G vs 66.76 G**, i.e. CUBRID retires **1.1693x**
  the instructions at **identical IPC**. Q10 is therefore *not* a memory-stall story — the
  extra cost is extra instructions, on 3.53x fewer tuples.
- **Context switches**, a fifth independent counter: CUBRID **249,411 in 30.002 s
  (2.363 K/s)** against PostgreSQL **91,164 (751/s)** — **3.15x the rate**.

### Error budget, stated before any factor is interpreted

| Quantity | Blocks | min | max | spread |
|---|---|---|---|---|
| CUBRID block-median wall | 3 telemetry + 1 contract block | 7.128000 s | 7.215000 s | **1.22%** |
| PostgreSQL block-median wall | 3 telemetry + 1 contract block | 4.112718 s | 4.218695 s | **2.58%** |

The ratio band implied by those two spreads is **1.6896x .. 1.7543x**. The contract
`R_wall = 1.689622x` sits at the **bottom** of that band — the contract block happens to pair
CUBRID's fastest block median with PostgreSQL's slowest — so the honest verdict is
"CUBRID **1.69x–1.75x** slower", and every number below is quoted against the contract pair
that the band's lower edge represents. `F_plan` 1.3137x, `F_units` 1.2294x, `F_work` 0.2835x
and `F_cost` 4.4134x are all far outside the 3.8% band width and are safe to interpret at the
stated precision. `F_cpu(controlled)` 1.046193x is **only 1.2x the band width** and is
explicitly *not* interpreted as a meaningful CUBRID CPU deficit on the controlled pair; the
CPU statement Q10 does support is the native-pair `F_cost` 4.413350x.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q10 (Returned Item Reporting) |
| Pinned `ssot_commit` | `122c21596b15c5bf9c9a1a4b8d46c7fdaac4ee69` |
| Pinned `ssot_blob_sha` | `510478846bff081d3223d3835069283a7cd2e47b` |
| SSOT drift | `NONE` — HEAD blob `510478846bff081d3223d3835069283a7cd2e47b` equals the pinned blob at the pre-block gate (`preflight-Q10.txt`) and at the post-block gate (`q10-postcheck.txt`) |
| GJC session ID | `gajae_code_ms90h16s_gnzs6uz1` |
| Workspace HEAD at measurement | `122c21596b15c5bf9c9a1a4b8d46c7fdaac4ee69` (== `origin/main`, `tpch-sspq` porcelain empty before and after) |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 merge `b334446d6`) |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13`, ELF Build ID `4df41ee21300bf617bccd5e1d5c8522b074ef86e`, RelWithDebInfo, gcc 8.5.0 |
| CUBRID server PID / DB | 1612732 / `tpch_sf10_q1`, port 1523 owner `cub_master` PID 1433697 — classified `OK` (campaign prefix) pre- and post-block |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b`, ELF Build ID `5f2cb2987765c612638c278f85cfc85c211fffe1`, gcc 8.5.0, JIT off, assertions off |
| PostgreSQL postmaster / PGDATA | 1433696 / `/home/cubrid/pg/pgdata-tpch-sspq`, port 5442 — classified `OK` pre- and post-block |
| Both binary hashes | match the frozen `reports/bootstrap/build-manifest.json` (`frozen: true`) |
| Canonical query SHA-256 | `4d2f36b71c0503ec5ade05313e28d3dfb427e4ba9fa78e2b75e68a7e9e747d0f` — `queries/q10-cubrid.sql` **byte-matches** `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q10.sql` |
| PostgreSQL dialect SHA-256 | `c402d5b1e59bb8eab3a9a5effddcb71acd9cbb8be53b8b0f768afcd7a3284c61`, one change (`queries/diff/q10.diff`, 639 B): `DATE_ADD(DATE '1993-10-01', INTERVAL 3 MONTH)` → `date '1993-10-01' + interval '3' month`. No hint, no join reordering, no subquery rewrite, no extra predicate, no semantic cast |
| Schema | 8 FKs / 8 FK-owned child B-trees on CUBRID; 8 FKs all `convalidated=t` plus 8 explicit `idx_fk_*` `USING btree` on PostgreSQL, exact child-column order verified |
| Row counts (both engines, exact `COUNT(*)`) | region 5, nation 25, supplier 100,000, customer 1,500,000, part 2,000,000, partsupp 8,000,000, orders 15,000,000, lineitem 59,986,052 |
| Statistics track | `histogram-enabled controlled comparison` — CUBRID `update_statistics_update_histogram=y`, `default_histogram_bucket_count=300`; PostgreSQL standard `ANALYZE`, `default_statistics_target=100`, 478 rows in `pg_statistic` with 101-bucket histograms on `c_custkey`/`o_custkey`/`o_orderdate`/`o_orderkey`/`l_orderkey` and MCV lists on `c_nationkey`(25)/`l_returnflag`(3). `pg_stat_user_tables.last_analyze` reads `never` because the statistics collector was reset by a later postmaster restart, not because `ANALYZE` is missing — `reports/bootstrap` records the run and `pg_statistic` is populated |
| Parallel/buffer label | `configured node/gather-cap comparison`, **not** DOP parity and **not** global-worker parity; `configured-equal buffer budget` |
| Parallel settings | CUBRID `parallelism=6`, `max_parallel_workers=100`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`, `parallel_leader_participation=on`, `max_worker_processes=16` |
| Buffer/cache | CUBRID `data_buffer_size=8.0G` (`data_buffer_pages=524288`); PostgreSQL `shared_buffers=1048576 × 8kB = 8192MB` |
| Shared memory | PostgreSQL `dynamic_shared_memory_type=mmap` (`postgresql.conf:969`). **Load-bearing for Q10**: the native plan contains two `Parallel Hash Join` nodes, the inner one running at `Batches: 16 (originally 1)`, so its DSM hash table plus the `Gather Merge` tuple queues are exactly the case the 64000k `/dev/shm` would have failed with `posix` |
| CPU/NUMA | SUT + client CPUs `0-15`, memory node0; collectors `20-23`. All engine TIDs inside the cpuset: 34 pre-block (cub_master 2, cub_server 24, postmaster 1, pg_children 7), 35 post-block — `off_cpuset=0` both times |
| External SUT-set load | 1.054 core-s/s pre-block, 0.270 post-block, threshold 6.0 → `PASS`. Every accepted block carries `load_verdict=CLEAN` under the strict per-sample rule (`external_max` 0.7308 PG, 0.7674 CUBRID) |
| Engine block order | Q10 is **even** → PostgreSQL block first, then CUBRID block (SSOT section 12) |
| Timeout | not reached; no censoring |

**One naming note.** The session prompt labelled Q10 "R and S Grouped by Extended Price".
That is not this query. Q10 in the canonical TPC-H set — and in the byte-verified
`q10-cubrid.sql` measured here — is **Returned Item Reporting**: `customer ⋈ orders ⋈
lineitem ⋈ nation`, `o_orderdate` in Q4/1993 and `l_returnflag = 'R'`, grouped by customer
and ordered by `sum(l_extendedprice * (1 - l_discount)) desc` with `LIMIT 20`. The measured
artifact is the canonical Q10; the prompt's label is disregarded as a mislabel, not treated
as a different query.

## 2. Correctness

| Item | Value |
|---|---|
| Status | **`result-equivalent-at-SF10`** |
| Detail | 20 rows, `ordered=True` — the query has `ORDER BY revenue desc` with `LIMIT 20`, so the ordered result sequence was compared exactly |
| Comparator | `harness/correctness_check.py` → `smoke_check.py`, SSOT section 11 rules: exact ordered sequence, raw decimal text preserved, relative tolerance `abs(a-b) ≤ 1e-12 × max(1, abs(a), abs(b))` allowed for output-scale only |
| Raw | `q10-correctness.json`, `q10-correctness-cubrid.out` (3,938 B), `q10-correctness-postgresql.out` (3,737 B) |
| Censoring | none |
| Independent cross-check | 11 ground-truth `count(*)` queries returned **identical** values on both engines (`q10-groundtruth-cubrid.out` vs `q10-groundtruth-pg.out`), including the group count 381,105 that the aggregation must produce |
| Controlled variants | both `F_plan` variants also return **byte-identical result rows** to their own engine's native run (`q10-variant-equivalence.txt`): CUBRID `23bb9755…` for native and `/*+ NO_HASH_AGGREGATE */`; PostgreSQL `c0cc4a8e…` for native and forced index-NL |

Top row, both engines: `1237537 | Customer#001237537 | 884989.6657 | 7840.17 | RUSSIA | … `.

## 3-b. Headline timings

Regime: **`single-query-repeat WARM`**, metadata connection mode
**`single-connection-four-statements`** — one direct campaign connection, one uncounted
warmup statement, WARM proved, three measured statements consecutively, connection closed.
CUBRID uses `csql -C` direct ad-hoc execution; PostgreSQL uses one `psql` Unix-socket
connection with the simple-query protocol. Every statement fully consumes all rows into a
campaign-owned fixed sink under `work/Q10/sink` with no terminal rendering; output bytes are
recorded and the content hash is computed after the headline timer stops.

| Field | CUBRID | PostgreSQL |
|---|---|---|
| uncounted warmup (s) | 6.745000 | 4.311569 |
| measured 1 (s) | 6.947999 | 4.218695 |
| measured 2 (s) | 7.146000 | 4.211516 |
| measured 3 (s) | 7.128000 | 4.219128 |
| **median (headline, s)** | **7.128000** | **4.218695** |
| mean (s) | 7.074000 | 4.216446 |
| within-block sd (s) | 0.109490 (**1.548%**) | 0.004275 (**0.101%**) |
| block accepted on attempt | 2 of 6 (attempt 1 rejected: WARM not established) | 1 of 6 |
| load verdict | `CLEAN` (external mean 0.1612, max 0.7674 core-s/s) | `CLEAN` (external mean 0.1588, max 0.7308) |
| sink bytes / SHA-256 | 20,664 / `7d6f60087121b2dd248cc6b7…` | 15,082 / `e30f848ed124443f6cde9a8f…` |
| **median wall ratio** | **1.689622x** (CUBRID slower by 68.96%) | — |
| correctness / censoring | `result-equivalent-at-SF10` / none | `result-equivalent-at-SF10` / none |

No confidence interval is claimed from three values. The `1.22%` / `2.58%` block-median
spreads in the error budget above are the campaign's honest uncertainty on these numbers.

### WARM proof

WARM is proved, not assumed, on three independent grounds.

1. **Convergence probes (40 statements per engine, independently load-gated, uncounted).**
   PostgreSQL converged at statement 12, half-split trend **+0.4896%** over 40 statements,
   trailing spread 2.0017%, steady-state median 4.271 s. CUBRID converged at statement 12,
   half-split trend **+0.1969%**, trailing spread 1.5722%, steady-state median 7.124 s.
   Raw: `q10-convergence-pg.json`, `q10-convergence-cubrid.json`.
   These probes set the block parameters actually used: PostgreSQL `n=20`, `LEVEL_TOL 1.0%`,
   `SPREAD 3.0%`; CUBRID `n=20`, `LEVEL_TOL 3.0%`, `SPREAD 5.0%`.
2. **Per-block WARM establishment.** Every timed block ran a 20-statement uncounted
   `warm_establish.py` pass first and had to pass the gate before the contract block was
   timed. PostgreSQL contract block: `CONVERGED, half-split trend +0.3546%, trailing spread
   0.4204%, steady 4.214866`. CUBRID contract block attempt 1 was **rejected** —
   `NOT_CONVERGED: monotone trailing window (still drifting)` — and the block was not timed;
   attempt 2 passed at `+0.1966%, trailing spread 1.5192%, steady 7.109` and was timed.
3. **Zero physical reads at the device.** Across the whole non-headline diagnostic block
   (1 warmup + 3 statements), `/proc/<cub_server>/io` shows `read_bytes` delta **0** with
   `rchar` delta 36.73 GB (9.18 GB/statement) and 2,242,548 read syscalls — every one a page
   cache hit. Device deltas: CUBRID `sda` read **0.008 MiB**, `dm-*` ≤ 0.047 MiB;
   PostgreSQL `sdb` read **0.199 MiB**. Raw: `Q10-cubrid-buffer-io-diag.json`,
   `Q10-postgresql-buffer-io-diag.json`.

Both engines' working sets exceed their 8192MB budgets (lineitem alone is 10,670.9 MiB of
CUBRID heap and 8,790 MB of PostgreSQL heap), so "WARM" here means **steady state with all
buffer misses served from the OS page cache and zero device reads**, which is exactly what
the measurements show. It does not mean zero buffer misses: PostgreSQL reports
`shared hit=1025419 read=397150` per statement and CUBRID reports 76,808 page `ioread` per
statement in its trace. That physical-read delta is recorded here as SSOT section 9 requires,
and it is symmetric — neither engine gets a residency advantage.

## 4. Plan

### 4-a. CUBRID native (estimated, `SET OPTIMIZATION LEVEL 514`, non-executing)

```text
temp(order by)                                                    cost 649494 card 237795
  subplan: temp(group by)   sort: 1,2,4,7,5,6,8 asc               cost 646485 card 237795
    subplan: hash-join (inner join)  edge: term[0]                cost 643476 card 237795
      outer: idx-join (inner join)                                cost 630073 card 237969
        outer: idx-join (inner join)                              cost 507516 card 237969
          outer: sscan   orders     sargs: o_orderdate range      cost 189189 card 568450
          inner: iscan   lineitem   index: fk_lineitem_orders
                                    sargs: l_returnflag='R'       cost      4 card 14720577
        inner: iscan   customer   index: pk_customer_c_custkey    cost      4 card 1500000
      inner: sscan   nation                                       cost      1 card 25
```

Selectivities the optimizer used: `c_nationkey=n_nationkey` 0.0399707, `c_custkey=o_custkey`
6.66667E-07, `l_orderkey=o_orderkey` 2.84383E-08, `o_orderdate` range **0.0378967**,
`l_returnflag='R'` **0.2454**. Both sarg estimates are good: the true `o_orderdate`
selectivity is 573,157/15,000,000 = 0.0382105 (**1.008x**) and the true `l_returnflag`
selectivity is 14,808,183/59,986,052 = 0.2468601 (**1.006x**). The final cardinality estimate
is 237,795 against a true 381,105 (**0.6239x**) — a mild under-estimate that does not change
the plan.

### 4-b. PostgreSQL native (`EXPLAIN ANALYZE, BUFFERS, VERBOSE, SETTINGS`)

```text
Limit                                        actual 4245.332..4461.508  rows=20
  Sort  (top-N heapsort, Memory: 34kB)       actual 4245.331..4461.506  rows=20
    GroupAggregate                           actual 3337.918..4340.232  rows=381105
      Group Key: c_custkey, n_name
      Gather Merge  (Workers Planned 4, Launched 4)  actual 3337.903..3748.926  rows=1147084
        Sort  (external merge, Disk: ~43.6 MB per unit)  actual 3333.551..3364.015  rows=229416.8  loops=5
          Nested Loop  (Inner Unique)        actual 3038.460..3227.127  rows=229416.8  loops=5
            Parallel Hash Join  (c_custkey = o_custkey)  actual 3038.430..3168.320
              Parallel Seq Scan on customer  actual 0.007..23.709  rows=300000  loops=5
              Parallel Hash  (Buckets 131072 (orig 1048576), Batches 16 (orig 1), Mem 4960kB)
                Parallel Hash Join  (l_orderkey = o_orderkey)  actual 504.505..2858.954
                  Parallel Seq Scan on lineitem  Filter l_returnflag='R'
                                                 actual 0.081..2043.547  rows=2961636.6  loops=5
                                                 Rows Removed by Filter: 9035574 per loop
                  Parallel Hash  (Buckets 1048576, Batches 1, Mem 30688kB)
                    Parallel Seq Scan on orders  Filter o_orderdate range
                                                 actual 0.044..461.205  rows=114631.4  loops=5
                                                 Rows Removed by Filter: 2885369 per loop
            Memoize  (Cache Key c_nationkey, Hits 231350, Misses 25, Evictions 0)  loops=1147084
              Index Scan using nation_pkey    loops=125
Buffers: shared hit=1025419 read=397150, temp read=65800 written=66086
Planning Time: 2.609 ms   Execution Time: 4464.501 ms
```

### 4-c. Shape comparison — what is the same and what is not

| Stage | CUBRID | PostgreSQL | same? |
|---|---|---|---|
| orders access | full heap `sscan`, 6 parallel workers, `o_orderdate` sarg | `Parallel Seq Scan`, 4 workers + leader, same filter | **yes** (both scan all 15,000,000, both keep 573,157) |
| orders ⋈ lineitem | **index-NL**: 573,157 `fk_lineitem_orders` descents → 2,292,924 entries → 1,147,084 after `l_returnflag` | **Parallel Hash Join**: full 59,986,052-row lineitem scan → 14,808,183 after filter, probed against a 573,157-row hash | **no** |
| ⋈ customer | **index-NL** on `pk_customer_c_custkey` | **Parallel Hash Join** against a full 1,500,000-row `Parallel Seq Scan` | **no** |
| ⋈ nation | `hash-join`, 25-row build, in memory | `Nested Loop` + `Memoize` (25 misses, 231,350 hits per unit) over `nation_pkey` | different node, identical effect |
| GROUP BY 1,147,084 → 381,105 | **sort-based, `hash: partial`, SERIAL**, 75,893 sort pages, 66,611 temp ioreads | `GroupAggregate` over `Gather Merge` over a **per-unit parallel** `Sort` (5 × ~43.6 MB external merge) | **no — the decisive difference** |
| ORDER BY + LIMIT 20 | `temp(order by)`, 113 ms | `top-N heapsort`, 34 kB | equivalent |
| intermediate hand-off | join result **materialised into a temp list file** and re-scanned (`SCAN temp`, 805 ms, 1,147,084 rows) | `TupleTableSlot` passed by reference into `Sort` | **no** |

So `F_plan` cannot be assigned 1.0000 by structural equality — the join methods and the
aggregation pipeline both differ — which is why both anchors are measured controlled A/Bs
rather than asserted.

### 4-d. Controlled-plan variants (all four measured through the same gated section-12 block)

| Variant | Shape | Block median | vs its own native |
|---|---|---|---|
| CUBRID native | index-NL chain, serial group-by sort | 7.128000 s | — |
| CUBRID `/*+ NO_HASH_AGGREGATE */` | **identical plan tree** (cost 649494), parallel group-by sort | **5.426000 s** | **1.3137x faster** |
| CUBRID `/*+ USE_HASH(lineitem, customer) */` | full lineitem `sscan` → `iscan orders PK` → hash-join customer, cost **9,427,968** | 13.809 / 13.869 s (2-statement probe) | **1.94x slower** |
| PostgreSQL native | Parallel Hash Join tree, 4 workers | 4.218695 s | — |
| PostgreSQL `enable_hashjoin=off, enable_mergejoin=off` | **node-for-node CUBRID's shape**, 5 workers, Partial+Finalize GroupAggregate | **2.484120 s** | **1.6979x faster** |

The forced PostgreSQL plan is node-for-node CUBRID's native shape:
`Parallel Seq Scan orders (o_orderdate filter) → Index Scan idx_fk_lineitem_orders
(l_returnflag filter) → Index Scan customer_pkey → Memoize/Index Scan nation_pkey`
(`variants/plan-act-pg-idxnl.out`), and it reports the exact probe counts CUBRID's shape
requires: `Index Searches: 573157` on lineitem (2 surviving rows and 2 removed per loop) and
`Index Searches: 1147084, loops=1147084` on `customer_pkey`.

## 5. Execution telemetry

### 5-a. Node-level time, CUBRID trace (`SET TRACE ON`, non-headline; traced statement 8048 ms)

| Node | exclusive time | share | workers | pages / ioread |
|---|---|---|---|---|
| join subtree (`SUBQUERY (uncorrelated)` → orders sscan → lineitem iscan → customer iscan) | 3168 ms | 39.4% | orders heap scan **6**, subquery 2 | lineitem btree ioread 385,785 |
| `HASHJOIN` with nation (own cost) | 117 ms | 1.5% | probe **5** | 20,364 |
| `SCAN (temp …)` — re-read of the materialised join result | 805 ms | 10.0% | **5** | 0 |
| **`GROUPBY` (sort-based, `hash: partial`)** | **3834 ms** | **47.6%** | **none — serial** | **page 75,893, ioread 66,611** |
| `ORDERBY` | 113 ms | 1.4% | 3 | — |
| sum | 8037 ms | 99.9% of the traced 8048 ms | | |

The traced statement is 12.9% slower than the headline median (8.048 s vs 7.128 s) because
tracing is instrumented and non-headline; the *shares* are what this table is used for.

### 5-b. Node-level time, PostgreSQL (`EXPLAIN ANALYZE`; 4464.5 ms, 5.8% above the 4218.7 ms headline)

| Stage | interval | share |
|---|---|---|
| lineitem `Parallel Seq Scan` + filter | 0 → 2043.5 ms | 45.8% |
| orders scan + hash build (concurrent) | 0 → 503.1 ms | — |
| inner `Parallel Hash Join` complete | → 2858.9 ms | 18.3% |
| `Parallel Hash` build of the 1,147,084-row join result (16 batches) | → 2954.1 ms | 2.1% |
| top `Parallel Hash Join` + `Nested Loop`/`Memoize` | → 3227.1 ms | 6.1% |
| per-unit `Sort` (5 × external merge ~43.6 MB) | → 3333.6 ms | **2.4%** |
| `Gather Merge` + `GroupAggregate` → 381,105 groups | → 4340.2 ms | 24.8% |
| top-N `Sort` + `Limit` | → 4461.5 ms | 2.7% |

PostgreSQL's whole sort-and-aggregate tail is **~1,234 ms** (per-unit sort 106 ms in parallel
plus 1,002 ms of gather-merge + `GroupAggregate` plus 121 ms of final sort) against CUBRID's
**4,752 ms** (`SCAN temp` 805 + `GROUPBY` 3834 + `ORDERBY` 113). That 3.85x is the mechanism
behind the whole gap.

### 5-c. CPU accounting (SSOT section 15; median-U telemetry run per configuration)

| Configuration | `executor_cpu` | `auxiliary_query_cpu` | `total_query_cpu` | `U` | TWU | peak units | serial tail |
|---|---|---|---|---|---|---|---|
| CUBRID native | 93.10 core-s | 4.64 core-s | 97.74 core-s | 3.42875 | 3.4245 | 6.6368 | 0.0 s |
| PostgreSQL native | 67.03 | 9.60 | 76.63 | 4.63013 | 4.5860 | 6.6740 | 0.235 s |
| CUBRID `NO_HASH_AGGREGATE` | 80.48 | 1.19 | 81.67 | 3.76620 | 3.7477 | 6.7804 | 0.0 s |
| PostgreSQL forced index-NL | 45.50 | 0.00 | 45.50 | 4.59070 | 4.6562 | 6.1848 | 0.119 s |

`executor_cpu` is query threads inside `cub_server` for CUBRID and the leader backend plus
parallel workers for PostgreSQL; `auxiliary_query_cpu` is `csql` parse/plan/result work for
CUBRID and io workers plus `psql` for PostgreSQL. They are never merged, and nothing
unattributable is folded in. Note that PostgreSQL's `auxiliary_query_cpu` is **8.1x**
CUBRID's on the native pair (9.60 vs 1.19 core-s per block on the comparable configurations)
— PostgreSQL pays visible io-worker CPU where CUBRID pays kernel `pread` copy cost inside its
own executor threads (section 6).

Worker counts, from each engine's own reporting:

- CUBRID native: orders heap scan `parallel workers: 6, readrows: 2380011..2525461` (6 × ≈2.5M
  = 15,000,000), hash-join probe `parallel workers: 5`, temp re-scan `parallel workers: 5`,
  order-by `parallel workers: 3`, **group-by: none**. Peak 6.6368 simultaneous active units,
  measured on 0.25 s per-TID samples weighted by actual timestamp deltas.
- PostgreSQL native: `Workers Planned: 4, Workers Launched: 4` plus a participating leader
  (`loops=5` on every node under the `Gather Merge`) = 5 units. The gather width is set by the
  **outer** side of the top hash join — `customer` at 281 MB — not by the 8,790 MB lineitem;
  the forced index-NL variant, whose driving scan *is* orders (2,041 MB), launches **5**.

### 5-d. Buffer, `/proc` I/O, iostat and NUMA (stage 14.7, non-headline, 4-statement block)

| Quantity | CUBRID | PostgreSQL |
|---|---|---|
| device read (all block devices) | 0.008 MiB `sda`, ≤0.047 MiB `dm-*` | 0.199 MiB `sdb`/`dm-2`, 0.047 MiB `sda` |
| **device write** | **836.824 MiB `sda`** (≈209 MiB/statement) | **4.406 MiB `sda`**, 2.402 MiB `sdb` |
| `/proc/<server>/io read_bytes` | **0** | 10,813,440 |
| `/proc/<server>/io rchar` | 36.73 GB (9.18 GB/statement) | 5.15 GB |
| `/proc/<server>/io write_bytes` | 835,751,936 (209 MiB/statement) | 5,936,893,952 with `cancelled_write_bytes` 11,460,018,176 |
| read syscalls | 2,242,548 (560,637/statement) | 633,106 |
| buffer counters | `Data_page_buffer_hit_ratio` 91.65 unchanged; LRU zones moved (lru1 89,602→84,100, lru2 11,368→10,654, lru3 423,318→429,534, `victim_candidate` +6,215) | `blks_read` +1,820,281, `blks_hit` +3,879,781 over the block |
| per-statement engine-level misses | 76,808 page `ioread` × 16 KiB = 1.17 GB (trace) | 397,150 blocks × 8 KiB = 3.03 GB (`EXPLAIN`) |
| NUMA | `cub_server` 8,786.96 MB node0 / 6.71 MB node1 | `postgres` 154.20 MB node0 / 0.52 MB node1 |

**The decisive line is the device write.** CUBRID physically writes ~209 MiB per statement of
external-sort temp file, because its serial group-by sort spills 75,893 pages. PostgreSQL
generates *more* nominal temp traffic (11.46 GB of `cancelled_write_bytes`, i.e. pages
dirtied and deleted before writeback, plus `temp written=66086` blocks reported by `EXPLAIN`)
but almost none of it reaches the device — 4.4 MiB. The `/*+ NO_HASH_AGGREGATE */` variant's
trace shows the same effect on the CUBRID side from the other direction: group-by sort pages
75,893 → 24,088 and group-by sort `ioread` 66,611 → **0**.

**One CUBRID instrument is recorded as unusable.** `cubrid statdump -c` reported a delta of
**exactly 0** for `Num_data_page_fetches`, `Num_data_page_ioreads`, `Num_data_page_iowrites`,
`Num_data_page_dirties` and `Num_file_ioreads` across a block that the trace shows fetched
1,574,584 pages per statement, and `page_fix_by_type` came back empty. The gauge-style
counters in the same dump *did* move (LRU zones, `victim_candidate`, `Num_network_requests`
385→394, `Num_vacuum_master` 15,528→15,533), so the dump is being refreshed; the
data-page *counters* are simply not being accumulated in this server's configuration. Those
five numbers are therefore excluded from every calculation in this report, and the buffer/IO
claims rest on `/proc/<pid>/io`, `/proc/diskstats` and the per-statement trace counters
instead. Raw: `q10-cubrid-statdump-{pre,mid,post}.txt`, `Q10-cubrid-buffer-io-diag.json`.

## 6. Profile

`perf` is non-headline. Both captures attach to a **verified PID set**, never an all-CPU
profile, and resolved-sample coverage was validated: CUBRID 1,173 flat lines with
**0 unknown-symbol lines**, PostgreSQL 1,999 flat lines with **0 unknown-symbol lines**.

| | CUBRID | PostgreSQL |
|---|---|---|
| PID set | `cub_server` 1612732 (all 32 query worker TIDs live inside it) | postmaster 1433696 → leader 1996486 + workers 1996487-1996490 |
| window / repeats | 30.002 s / 6 statements | 30.002 s / 8 statements |
| cycles | 295,044,906,024 @ 2.795 GHz | 335,135,950,416 @ 2.762 GHz |
| instructions | 468,375,932,999 | 534,073,999,261 |
| **IPC** | **1.59** | **1.59** |
| instructions / statement | **78.06 G** | **66.76 G** (ratio **1.1693x**) |
| task-clock | 105,557.61 ms = **3.518 CPUs** (`U` = 3.42875, +2.60%) | 121,352.86 ms = **4.045 CPUs** (`U` = 4.63013, −12.6%, io workers excluded by design) |
| context switches | 249,411 = **2.363 K/s** | 91,164 = **751/s** (**3.15x** apart) |
| samples | 30,649 | 3,521 |

### 6-a. CUBRID resolved-symbol bands (self %, `cycles`; 76.64% of the profile accounted, 72.86% banded)

| share | band | top symbols |
|---|---|---|
| **14.60%** | **pgbuf fix/unfix + LRU victim machinery** | `pgbuf_fix_release` 6.17, `pgbuf_get_victim_candidates_from_lru` 4.03, `pgbuf_unfix` 1.85, `pgbuf_unlatch_void_zone_bcb` 0.97, `pgbuf_get_victim_from_lru_list` 0.84, `pgbuf_get_victim` 0.42, `pgbuf_claim_bcb_for_fix` 0.32 |
| **10.36%** | **kernel page-cache copy on the query thread (`pread`)** | `rep_movs_alternative` 8.07, `filemap_get_read_batch` 0.87, `iomap_set_range_uptodate` 0.70, `filemap_read` 0.41, `rwsem_optimistic_spin` 0.31 |
| **8.91%** | **collation / string value read-write-compare** | `lang_fastcmp_byte` 2.84, `lang_mht2str_byte` 1.85, `mr_data_writeval_string` 1.23, `mr_readval_string_internal` 0.93, `mr_readval_char_internal` 0.50, `mr_cmpval_char` 0.46, `mr_data_lengthval_string` 0.39, `mr_writeval_char_internal` 0.36, `mr_data_lengthval_char` 0.35 |
| 7.24% | heap record access | `heap_attrinfo_read_dbvalues` 2.79, `spage_get_record` 1.88, `spage_get_record_data` 0.65, `heap_next_1page` 0.65, `or_mvcc_get_repid_and_flags` 0.52, `or_mvcc_get_header` 0.41, `heap_scan_get_visible_version` 0.34 |
| 5.66% | list-file tuple materialisation | `qdata_copy_db_value_to_tuple_value` 1.13, `qdata_generate_tuple_desc_for_valptr_list` 1.05, `qfile_locate_tuple_next_value` 0.90, `qfile_locate_tuple_value_r` 0.73, `qdata_get_tuple_value_size_from_dbval` 0.59, `qfile_generate_tuple_into_list` 0.47, `pr_data_writeval_disk_size` 0.41, `qfile_save_tuple` 0.38 |
| 5.33% | external sort machinery (group-by + order-by) | `qfile_compare_partial_sort_record` 1.55, `mr_data_cmpdisk_numeric` 0.76, `mr_data_readval_numeric` 0.56, `sort_exphase_merge` 0.52, `qdata_load_agg_hentry_from_tuple` 0.47, `sort_run_merge` 0.41, `numeric_db_value_compare` 0.37, `qfile_make_sort_key` 0.36, `qdata_agg_hkey_compare` 0.33 |
| 5.33% | userspace memmove/compare | `__memmove_evex_unaligned_erms` 5.01, `__memcmp_evex_movbe` 0.32 |
| 3.91% | B-tree descent | `btree_search_leaf_page` 1.69, `btree_search_nonleaf_page` 1.30, `btree_compare_key` 0.92 |
| 3.77% | generic `DB_VALUE` comparator / predicate eval | `tp_value_compare_with_error` 1.45, `eval_pred` 1.38, `eval_value_rel_cmp` 0.56, `eval_data_filter` 0.38 |
| **3.35%** | **libpthread mutex** | `__pthread_mutex_lock` 1.36, `__pthread_mutex_unlock_usercnt` 1.09, `__pthread_mutex_trylock` 0.90 |
| 3.08% | `DB_VALUE` lifecycle | `pr_clear_value` 1.69, `db_value_domain_init` 1.07, `pr_type_from_id` 0.32 |
| **1.32%** | **hash-aggregate work that is then DISCARDED** | `mht_get_hash_number` 0.95, `qexec_hash_gby_agg_tuple` 0.37 |

### 6-b. PostgreSQL resolved-symbol bands (81.95% accounted, 76.83% banded)

| share | band | top symbols |
|---|---|---|
| **21.62%** | **tuple deform (`slot_getsomeattrs`)** | `tts_buffer_heap_getsomeattrs` 19.87, `tts_minimal_getsomeattrs` 1.31, `heap_deform_tuple` 0.44 |
| 11.59% | expression interpreter + `bpchareq` | `ExecInterpExpr` 5.90, `bpchareq` 5.13, `pg_newlocale_from_collation` 0.56 |
| 11.31% | parallel hash join probe/build | `ExecParallelScanHashBucket` 7.23, `hash_search_with_hash_value` 1.68, `ExecParallelHashJoin` 1.17, `ExecJustHashOuterVarStrict` 0.50, `ExecParallelHashTableInsert` 0.42, `ExecParallelHashTableInsertCurrentBatch` 0.31 |
| 10.92% | heap scan | `heapgettup_pagemode` 2.45, `heap_fill_tuple` 2.32, `ExecSeqScanWithQual` 1.90, `ExecStoreBufferHeapTuple` 1.20, `heap_prepare_pagescan` 0.88, `heap_getnextslot` 0.87, `heap_page_prune_opt` 0.81, `heap_compute_data_size` 0.49 |
| 8.05% | kernel mm (temp-file page-cache teardown) | `_compound_head` 3.88, `zap_present_ptes` 1.33, `folio_remove_rmap_ptes` 0.91, `rep_movs_alternative` 0.78, `folios_put_refs` 0.68, `free_pages_and_swap_cache` 0.47 |
| 4.49% | numeric arithmetic (sum accumulation) | `init_var_from_num` 1.11, `make_result_safe` 0.76, `mul_var` 0.61, `sub_abs` 0.58, `accum_sum_add` 0.44, `numeric_mul_safe` 0.35, `numeric_avg_accum` 0.32, `numeric_sub_safe` 0.32 |
| 4.07% | palloc / memory context | `AllocSetAlloc` 1.52, `AllocSetFree` 0.99, `MemoryContextReset` 0.77, `palloc0` 0.41, `pfree` 0.38 |
| 1.95% | detoast | `detoast_attr` 1.23, `pg_detoast_datum_packed` 0.72 |
| **1.66%** | **buffer pin + lwlock** | `LWLockAttemptLock` 1.04, `PinBuffer` 0.62 |
| 1.17% | sort / gather-merge comparison | `heap_compare_slots` 1.17 |

**The single sharpest profile contrast in the campaign so far**: CUBRID spends **17.95%**
(14.60% pgbuf + 3.35% libpthread) doing buffer bookkeeping where PostgreSQL spends **1.66%** —
a **10.8x** relative share — and it does so while touching **3.53x fewer tuples**. PostgreSQL's
own dominant band is tuple deform at 21.62%, which is honest work proportional to the
59,986,052 + 15,000,000 + 1,500,000 rows its plan chose to read.

## 7. Source contrast

| Item | CUBRID `file:line` | PostgreSQL `file:line` | Difference | Class |
|---|---|---|---|---|
| A parallel sort is forbidden for a `GROUP BY` that was *plan-time* hash-eligible, even after the executor abandoned hashing at run time | `src/storage/external_sort.c:5228-5234` — `SORT_LISTFILE_PX_ARG *px = (SORT_LISTFILE_PX_ARG *) sort_param->px_extra_arg; if (px == NULL \|\| px->hash_eligible) return 1;`; contract at `src/storage/external_sort.h:172` `int hash_eligible; /* GROUP_BY only: if non-zero, parallelism must be skipped (0 otherwise) */`; value supplied at `src/query/query_executor.c:5657` `gby_px.hash_eligible = gbstate.hash_eligible;` | `src/backend/optimizer/plan/planner.c:8019` `gather_grouping_paths()` — for every partial path it applies `create_sort_path()` (:8072) *below* `create_gather_merge_path()` (:8083); there is no hashing-related condition anywhere in the function, and the sorted grouping strategy is offered at `planner.c:7793` independently of the hashed one at `:7875` | CUBRID returns a degree of **1 before evaluating `compute_parallel_degree` at all**; PostgreSQL always considers the parallel sort. Measured: `GROUPBY` 3834 ms serial vs PostgreSQL's 5 × ~106 ms concurrent | **structural absence** |
| Hash aggregation is abandoned for the whole statement by a hardcoded selectivity constant | `src/query/query_executor.c:134` `#define HASH_AGGREGATE_VH_SELECTIVITY_THRESHOLD 0.5f`, `:131` `#define HASH_AGGREGATE_VH_SELECTIVITY_TUPLE_THRESHOLD 2000`, decision at `:4838-4849` `if (context->tuple_count > 2000) { selectivity = (float) context->group_count / context->tuple_count; if (selectivity > 0.5f) { context->state = HS_REJECT_ALL; qdata_save_agg_htable_to_list(...); } }`, latched at `:4648` `if (context->state == HS_REJECT_ALL) return NO_ERROR;` | `src/backend/executor/nodeAgg.c:1866` `hash_agg_check_limits()` — tests only `MemoryContextMemAllocated` against `hash_mem_limit` and `hash_ngroups_current` against `hash_ngroups_limit`; **no selectivity term exists**. On breach it calls `hash_agg_enter_spill_mode()` (`:1907`) and `hashagg_spill_tuple()` (`:3029`), keeping resident groups aggregating and spilling only would-be-new groups into hash partitions it reprocesses at `:2734` `agg_refill_hash_table()` | CUBRID **flips strategy permanently** on a runtime sample of the first 2000 tuples; PostgreSQL **never flips**, it degrades by spilling, and its hashed-vs-sorted choice is a planner cost comparison (`planner.c:7875`) | **structural absence** |
| The counter that heuristic reads is inflated by the eviction path | `src/query/query_executor.c:4740-4741` `context->tuple_count++; context->group_count++;` on every insert, against the eviction loop at `:4808-4835` which adjusts `context->hash_size -= …` twice and calls `mht_rem(...)` but **never decrements `group_count`** | `src/backend/executor/nodeAgg.c:1861` `uint64 ngroups = aggstate->hash_ngroups_current;` — maintained as the count of groups *currently resident* (incremented at `:3243` `initialize_hash_entry`, reset at `:2814` when a batch is reloaded), so it can never drift above the truth | CUBRID's ratio is a monotonically drifting **overestimate**; measured true selectivity 0.332243 global and ≤0.424788 on every input prefix, yet the >0.5 branch provably fired | **structural absence** |
| The aggregate memory budget cannot be changed on a running server | `src/query/query_executor.c:4643` `static UINT64 mem_limit = prm_get_bigint_value (PRM_ID_MAX_AGG_HASH_SIZE);` — a function-local static with a dynamic initializer, evaluated once per **server process**, consumed at `:4808`; declared changeable at `src/base/system_parameter.c:3472` | `src/backend/executor/nodeAgg.c:4396` `hash_agg_set_limits(...)` per `AggState` at executor init from the live `work_mem`/`hash_mem_multiplier`, re-called per spill batch at `:2831`, and read live on every insert at `:1871` | CUBRID freezes the budget at the first hash-aggregate tuple of the process; PostgreSQL re-reads it per statement and per batch. Measured: a 256x change (2M → 512M) moved `GROUPBY` 3834→3761 ms, inside the 1.22% block spread | **structural absence** |
| Intermediate join result is materialised to a temp file before aggregation | `src/query/query_executor.c:5641` `estimated_pages = qfile_get_estimated_pages_for_sorting (list_id, &gbstate.key_info);` operating on the `list_id` the join wrote, fed by `qfile_add_tuple_to_list` / `qfile_save_tuple`; trace node `SCAN (temp time: 805, readrows: 1147084)` | `src/backend/executor/nodeSort.c` consumes its outer `Nested Loop`'s `TupleTableSlot` by reference; nothing between the join and the sort writes a file | CUBRID pays 805 ms and 5.66% of profile handing 1,147,084 rows from the join to the aggregation | **same stage, lower measured cost** (already registered as IMP-006) |
| Every page unfix does mutex-protected LRU list surgery | `src/storage/page_buffer.c` `pgbuf_unfix` / `pgbuf_get_victim_candidates_from_lru` / `pgbuf_unlatch_void_zone_bcb` (profile band 14.60% + 3.35% libpthread) | `src/backend/storage/buffer/bufmgr.c` `PinBuffer` / `UnpinBuffer` clock-sweep with no list and no mutex (profile band 1.66% incl. `LWLockAttemptLock`) | 10.8x relative profile share at 3.53x fewer tuple touches | **same stage, lower measured cost** (already registered as IMP-013) |
| Buffer misses served by a synchronous single-page `pread` on the query thread | `fileio_read` ← `pgbuf_claim_bcb_for_fix` ← `pgbuf_fix_release` (call graph resolved in `profile-cubrid-callgraph.txt`); 10.36% of cycles in kernel page-cache copy, 560,637 read syscalls per statement, `read_bytes` = 0 | `io_method=worker` — dedicated io workers, which is why PostgreSQL's `auxiliary_query_cpu` is 9.60 core-s per block against CUBRID's 1.19 and its kernel band is 8.05% mm teardown rather than 10.36% inline copy | CUBRID pays page-cache copy inside the executor's critical path | **same stage, lower measured cost** (already registered as IMP-007) |
| Depth-3 scan trace counters are unreliable | `src/query/query_executor.c` `xasl_merge_stats` (IMP-005) — trace reports `SCAN (index: dba.customer.pk_customer_c_custkey) … readkeys: 2250758, rows: 2250758, fetch: 7736050` | `variants/plan-act-pg-idxnl.out` `Index Scan using customer_pkey … loops=1147084, Index Searches: 1147084` for the **byte-identical** operation | CUBRID's counter is **1.96214x** the required value; the required value is independently fixed by ground truth `G3 = 1,147,084` | **common to both engines** — no: **structural absence** on the CUBRID side (reporting defect, already registered as IMP-005) |

**Absence claims are recorded with what was searched.** For "no selectivity term in
PostgreSQL's hash-aggregate limit check": searched `src/backend/executor/nodeAgg.c` (4,600+
lines, all of `hash_agg_check_limits`, `hash_agg_set_limits`, `hash_agg_enter_spill_mode`,
`hash_choose_num_partitions`, `hashagg_spill_init/tuple/finish`, `agg_refill_hash_table`) and
`src/backend/optimizer/plan/planner.c` for the patterns `selectivity`, `ngroups`,
`hash_mem`, `spill`, `enable_hashagg`, `can_hash`; the only ratio PostgreSQL forms is
`hashentrysize` bookkeeping, never groups/tuples. For "no existing CUBRID candidate touches
`external_sort.c`": grepped every `cubrid_source` entry of IMP-001..IMP-014 in
`reports/improvement-registry.json` — zero hits on `external_sort`, zero on
`sort_check_parallelism`, zero on `HASH_AGGREGATE`, zero on `max_agg_hash_size`
(`q10-registry-dedup.txt`).

## 8. Causal decomposition details

### 8-a. What actually happens, in order

1. CUBRID's optimizer costs the index-NL chain at **649,494** and the hash alternative at
   **9,427,968**, picks the index-NL chain, and is **right**: the hash variant measures
   13.809/13.869 s against 7.13 s native.
2. That chain runs **well and in parallel**: the orders heap scan reaches the configured
   `parallelism=6` (`readrows: 2380011..2525461` across 6 workers), the lineitem and customer
   index probes ride on it, the nation hash join costs 117 ms, and the whole join subtree
   completes in **3168 ms** — which is, to three digits, exactly what PostgreSQL's native
   hash-join tree needs to reach the same 1,147,084 rows (`Parallel Hash Join` complete at
   **3168.3 ms**). Up to this point the two engines are level.
3. CUBRID then materialises those 1,147,084 rows into a temp list file and re-reads them
   (`SCAN temp`, 805 ms, 5 workers).
4. CUBRID's `GROUP BY` had been marked hash-eligible at plan time
   (`xasl_generation.c:16563`). At run time, once 2000 tuples had passed,
   `qexec_hash_gby_agg_tuple` computed `group_count/tuple_count > 0.5f` and set
   `context->state = HS_REJECT_ALL` (`query_executor.c:4845`), dumping the partial hash table
   to a list file. The trace records this as `hash: partial` (`query_dump.c:3948-3951`).
5. `qexec_groupby` then falls back to a sort — the correct thing to do — but hands
   `sort_listfile` a `SORT_LISTFILE_PX_ARG` whose `hash_eligible` is still the **plan-time**
   flag (`query_executor.c:5657`). `sort_check_parallelism`'s `SORT_GROUP_BY` branch sees it
   non-zero and returns **1** before evaluating anything else
   (`external_sort.c:5230-5234`). The 1,147,084-row sort runs on one thread, spills 75,893
   pages, reads 66,611 of them back, writes ~209 MiB to the device, and takes **3834 ms** —
   **47.6% of the statement**.
6. PostgreSQL reaches the same *strategic* conclusion — 381,105 groups of ~200 bytes do not
   fit `work_mem 4MB × hash_mem_multiplier 2 = 8MB`, so `GroupAggregate` was costed cheaper
   than `HashAggregate` and the executed plan is sort-based too — but its sort is **parallel**:
   `gather_grouping_paths()` put `create_sort_path` under `create_gather_merge_path`, so 5
   units each sort ~229,417 tuples into their own ~43.6 MB external merge (**~106 ms of
   wall**) and the leader only runs an n-way binary-heap merge
   (`heap_compare_slots`, 1.17% of profile) plus the final `GroupAggregate`.

### 8-b. Why the 0.5f heuristic fired on a query whose selectivity is 0.332

The trace's `hash: partial` maps to `HS_REJECT_ALL`, and `HS_REJECT_ALL` has **exactly one
assignment site** in the pinned tree — `query_executor.c:4845`, inside the
`selectivity > 0.5f` branch. So the branch provably fired. But the true selectivity is not
above 0.5 anywhere:

| window (input arrives in orderkey order) | tuples | distinct groups | selectivity |
|---|---|---|---|
| first 2,001 (the first point the test can fire) | 2,001 | 850 | **0.424788** |
| first 5,000 | 5,000 | 2,133 | 0.426600 |
| first 20,000 | 20,000 | 8,444 | 0.422200 |
| first 200,000 | 200,000 | 81,617 | 0.408085 |
| whole input | 1,147,084 | 381,105 | **0.332243** |

Raw: `q10-selectivity-probe-cubrid.out` and `q10-selectivity-probe-pg.out` — both engines
return the identical five rows. The reason the local ratio is ~0.42 rather than the global
0.332 is itself measured: there are **1,147,084 / 491,924 = 2.33184** returned lineitems per
distinct order, and one order belongs to one customer, so any orderkey-contiguous prefix sees
roughly one new group per 2.33 tuples, while globally a customer's 3.01 rows are spread over
1.29 orders that are far apart in the scan.

The only mechanism in the code that can lift the *computed* ratio above the *true* one is the
eviction path: `group_count` is incremented on every hash-table insert
(`query_executor.c:4740-4741`) and is **never decremented** when the
`while (context->hash_size > mem_limit)` loop evicts an entry (`:4808-4835`, which adjusts
`hash_size` twice and calls `mht_rem` but leaves `group_count` alone). Eviction is guaranteed
here: each hash value stores the **whole ~200-byte output tuple** (`:4707-4728`, taken because
`g_output_first_tuple` is false without `ROLLUP`) plus a 7-column key of which five are
strings 25/15/25/40/117 bytes wide, so 381,105 groups need ~76 MB against a 2 MB budget. This
is the **minimum overstatement the measurement requires**: at least
`0.5 / 0.424788 = 1.1771x`, and 1.5049x against the global value. That step is labelled
**inference from source plus the arithmetic necessity that the branch fired**, not a direct
measurement — see 8-c for the experiment that would close it and why it is blocked.

### 8-c. Explanations considered and REJECTED, with the number that rejected each

| Rejected explanation | Rejected by |
|---|---|
| "CUBRID chose the wrong join shape" (the Q09 story) | CUBRID's own hash alternative `/*+ USE_HASH(lineitem, customer) */` measures **13.809 / 13.869 s against 7.13 s native — 1.94x slower** at an estimated cost of 9,427,968 vs 649,494. And from the other side, PostgreSQL forced onto CUBRID's shape gets **1.6979x faster** (2.484120 s vs 4.218695 s). CUBRID's shape is the better shape on *both* engines. |
| "the working set does not fit CUBRID's 8 GiB buffer" (IMP-002) | `/proc/<cub_server>/io read_bytes` delta = **0** and device read delta **0.008 MiB** across the whole 4-statement diagnostic block. There are no physical reads to blame. |
| "the 2 MB `max_agg_hash_size` budget is what abandons hashing" | Refuted by source, not by experiment: the `while (context->hash_size > mem_limit)` loop at `:4808-4835` **only evicts**; it contains no assignment to `context->state`. `HS_REJECT_ALL` has exactly one assignment site, `:4845`, the selectivity test. |
| "then raise `max_agg_hash_size` and the query gets faster" | **Cannot be tested on a running server, and the attempt proves why**: `SET SYSTEM PARAMETERS 'max_agg_hash_size=512M'` (256x) left the verdict bit-identical — still `hash: partial`, `GROUPBY` 3834 → **3761 ms** (−1.90%) and sort pages 75,893 → **73,606** (−3.01%), both inside the 1.22% CUBRID block spread. The parameter is captured in a **function-local `static`** at `query_executor.c:4643`, so it is frozen for the life of the server process. Recorded as IMP-017; it is the reason 8-b's final step stays an inference. |
| "CUBRID's parallel-scan degree saturates below the cap" (IMP-012) | Q10 is a **negative control** for IMP-012: the driving heap scan *does* reach the configured 6 (`parallel workers: 6, readrows: 2380011..2525461`). The deficit is not in the scan. |
| "CUBRID's uncorrelated-subquery degree is hardcoded to 1" (IMP-009) | Q10's join chain *is* inside `SUBQUERY (uncorrelated)`, but the trace shows `(parallel workers: 2 …)` on the subquery with `parallel workers: 6` on the heap scan beneath it, and the join subtree matches PostgreSQL's 3168 ms exactly. Whatever IMP-009 does on Q05, it is not what limits Q10 — so no Q10 relation was added to it. |
| "it is a memory-stall / cache-locality difference" | **IPC is 1.59 on both engines.** The gap is instruction count (78.06 G vs 66.76 G per statement), not stalls. |
| "CUBRID's serial `ORDER BY` is the tail" | `ORDERBY` is **113 ms**, 1.4% of the traced statement, and it *does* report `parallel workers: 3`. |
| "the multi-column FK selectivity product mis-estimates the join" (IMP-014) | Q10's only FK index in play, `fk_lineitem_orders`, is single-column, and both sarg selectivity estimates are accurate to 1% (4-a). The final cardinality estimate is 0.6239x of truth, which changes no plan decision. |

### 8-d. What the residual 2.184x is, and what it is not

After the group-by defect is removed, the same plan shape still costs CUBRID
5.426 s against PostgreSQL's 2.484 s. Q10 attributes that residual by band rather than
claiming a single cause, and the bands do not overlap:

- **17.95%** of CUBRID's cycles are buffer bookkeeping (14.60% pgbuf + 3.35% libpthread)
  against PostgreSQL's **1.66%** — IMP-013, and Q10 is its cleanest isolation yet because
  `F_work` 0.283507x means CUBRID pays it on **3.53x fewer** tuples.
- **10.36%** is kernel page-cache copy executed inline by the query threads — IMP-007.
- **8.91%** is collation/string value handling, driven by a group key with five string
  columns totalling 222 bytes — this is where CUBRID's sort keys cost more than
  PostgreSQL's, and it is *not* separately registered because Q10 cannot separate it from
  the sort it is measured inside.
- **5.66%** is list-file materialisation of the join→aggregation hand-off — IMP-006.
- **3.77%** is the generic `DB_VALUE` comparator and predicate evaluation for two sargs —
  IMP-008.
- **1.32%** is a hash table that is built and thrown away — the wasted half of IMP-016.

Summed, those bands are 48.0% of CUBRID's profile against 3.6% of the corresponding
PostgreSQL bands (`PinBuffer`+`LWLockAttemptLock` 1.66%, `heap_compare_slots` 1.17%, detoast
0.78% of the comparable work). That is consistent with `F_cost` 4.413350x, but it is an
**attribution, not an A/B**, and no part of it is summed with `F_plan` — the 1.313675x plan
factor and these bands are measured on disjoint configurations.

## 9. Improvements

Registry synced, searched by title / CUBRID source location / PostgreSQL source location /
root cause before allocating (`q10-registry-dedup.txt`). Ledger went from 14 candidates
(`next_id IMP-015`) to **17** (`next_id IMP-018`).

### New candidates (ranked)

| Rank | ID | P | Category | Root cause (one line) | Measured effect |
|---|---|---|---|---|---|
| **1** | **IMP-015** | **P0** | parallelism, aggregation/sort | `sort_check_parallelism()` refuses `SORT_GROUP_BY` parallelism whenever the query was *plan-time* hash-eligible, even after the executor abandoned hashing at run time — so the fallback sort is serial | **direct A/B 1.313675x** (7.128 → 5.426 s); `GROUPBY` 3834 → 2565 ms with 5 workers; sort pages 75,893 → 24,088; sort temp ioreads 66,611 → 0; `U` 3.42875 → 3.76620. **52.0% of Q10's log-gap.** Difficulty **low** — one condition |
| 2 | IMP-016 | P1 | aggregation/sort, optimizer | the `0.5f` very-high-selectivity abort is evaluated on a `group_count` the LRU eviction path never decrements, so the 2 MB budget drifts the estimate past 0.5 on a query whose true selectivity is 0.332243 | overstatement ≥ **1.1771x** (0.5/0.424788); owns IMP-015's trigger, so shares the 1.313675x; plus **1.32%** of profile on a discarded hash table. Difficulty **medium** |
| 3 | IMP-017 | P2 | aggregation/sort, expression/type | `max_agg_hash_size` is captured in a **function-local `static`** (`query_executor.c:4643`), so the parameter is frozen for the server process lifetime | **null result is the evidence**: 256x change moved `GROUPBY` 3834 → 3761 ms and pages 75,893 → 73,606, inside the 1.22% block spread. Changes no Q10 number; restores a control. Difficulty **low** |

Ranking justification against the measured bands: IMP-015 owns the single largest measured
factor and is the cheapest change, and its correctness surface is already covered by an
executed A/B that returned byte-identical rows. IMP-016 is causally upstream but its fix
alters strategy selection for every hash-aggregate query in the product for the same measured
Q10 gain. IMP-017 changes no Q10 number on its own and is ranked last, but is recorded
because it is a 1-line defect that silently disables an operator control and is the specific
reason 8-b's last step is an inference. Every rejected sibling explanation and the number
that rejected it is in 8-c and is duplicated into each candidate's `ranking_rationale`.

### Existing candidates given a Q10 relation and Q10 evidence (no new ID)

| ID | Q10 contribution |
|---|---|
| IMP-005 | Depth-3 customer scan counter reads **2,250,758** against a required **1,147,084** (**1.96214x**), the required value fixed independently by ground truth `G3` *and* by PostgreSQL's `Index Searches: 1147084` on the byte-identical shape. Q10 does **not** reproduce the clean "depth 3 is exactly 2x" rule (exact doubling would be 2,294,168; reported is 1.89% below). The depth-2 lineitem counter **is** exact (2,292,924 = ground truth `H4`). Q10's `F_work` therefore uses ground truth and excludes the trace counter. |
| IMP-006 | `SCAN (temp time: 805, readrows: 1147084)` — 10.0% of the traced statement purely to hand rows from join to aggregation; profile band 5.66%. Separable: the `NO_HASH_AGGREGATE` variant drops the same node to 274 ms. |
| IMP-007 | 10.36% of cycles in kernel page-cache copy with the call graph resolved to `fileio_read ← pgbuf_claim_bcb_for_fix`; 560,637 read syscalls/statement for 9.18 GB rchar at `read_bytes = 0`. |
| IMP-008 | 3.77% banded (`tp_value_compare_with_error` 1.45%) for two sargs, against PostgreSQL's compiled `ExecInterpExpr` 5.90% + `bpchareq` 5.13% on **26.1x** the rows. |
| IMP-011 | **Negative control, the strongest in the campaign**: CUBRID's join-method choice is not merely acceptable, it beats PostgreSQL's. `F_plan` on the PostgreSQL-side anchor is **0.588836x**. Any future IMP-011 work must keep Q10 as a regression control. |
| IMP-013 | 14.60% pgbuf + 3.35% libpthread = **17.95%** vs PostgreSQL's **1.66%** (10.8x), at **3.53x fewer** tuple touches; `F_cost` 4.413350x = 995.3 ns vs 225.5 ns per touch; context switches 2.363 K/s vs 751/s; IPC identical at 1.59 so it is instructions, not stalls. |

No Q10 relation was added to IMP-002 (zero physical reads), IMP-004 (no `LIKE`), IMP-009
(join subtree matches PostgreSQL exactly), IMP-010 (device reads ≈ 0), IMP-012 (scan reaches
the configured 6) or IMP-014 (single-column FK index, sarg estimates accurate to 1%) — each
with the rejecting number recorded in `q10-registry-dedup.txt`.

All three new candidates are `status: measured`. None is marked `validated`: that requires
correctness evidence for an *implemented* change, and nothing was implemented.

## 10. Evidence index

Format: `claim → raw file:line → formula → evidence type → SHA-256`. Raw root
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q10`; sizes and SHA-256 for every file are in
`raw-manifest.json`, which is the authoritative checksum list. The entries below give the
pointer and the derivation.

| # | Claim | Raw pointer | Formula | Evidence type |
|---|---|---|---|---|
| 1 | CUBRID headline median 7.128000 s | `Q10-cubrid-headline-block1.json` → `statement_times_all[1:]` | median of 3 measured | direct measurement |
| 2 | PostgreSQL headline median 4.218695 s | `Q10-postgresql-headline-block1.json` | median of 3 measured | direct measurement |
| 3 | `R_wall` 1.689622x | both above | `7.128000 / 4.218695` | direct measurement |
| 4 | `F_plan` 1.313675x | `Q10-cubrid-headline-block1.json`, `Q10-cubrid-nohashagg-headline.json` | `7.128000 / 5.426000` | direct A/B |
| 5 | anchor A plan tree byte-identical | `q10-plan-est-cubrid.out`, `variants/plan-cubrid-NO_HASH_AGGREGATE.out` | cost 649494 both, same node order | direct A/B |
| 6 | anchor A result rows byte-identical | `q10-variant-equivalence.txt` | both `23bb9755…` | direct A/B |
| 7 | `GROUPBY` serial vs 5 workers | `q10-trace-cubrid.out`, `variants/trace-cubrid-NO_HASH_AGGREGATE.out` | trace `GROUPBY` lines and their `(parallel workers: …)` sub-lines | direct A/B |
| 8 | `F_plan(anchor B)` 0.588836x | `Q10-postgresql-idxnl-headline.json` | `2.484120 / 4.218695` | direct A/B |
| 9 | CUBRID hash variant 1.94x slower | `q10-probe-driver.log` | 13.809, 13.869 s vs 7.128 s | direct A/B |
| 10 | `U_C` 3.42875, `U_P` 4.63013 | `Q10-cubrid-headline-telemetry-run3.json`, `Q10-postgresql-headline-telemetry-run2.json` | median-U of 3 gated runs | profile attribution |
| 11 | `F_units`/`F_cpu` both anchors, residual ±0.000000% | `q10-card-calc.txt`, `Q10-causal-card.json` | see section 3-a formulas | profile attribution |
| 12 | `F_work` 0.283507x, `F_cost` 4.413350x | `q10-groundtruth-{cubrid,pg}.out`, `q10-plan-act-pg.out`, `q10-trace-cubrid.out`, `q10-card-calc.txt` | `W_C/W_P` = 24,556,558/86,617,111 | direct A/B (cardinalities) + profile attribution (CPU) |
| 13 | intermediate cardinalities identical on both engines | `q10-groundtruth-cubrid.out`, `q10-groundtruth-pg.out` | 11 `count(*)` rows compared | direct A/B |
| 14 | true selectivity 0.332243, prefixes ≤ 0.424788 | `q10-selectivity-probe-cubrid.out`, `q10-selectivity-probe-pg.out` | `groups/tuples` per window | direct A/B |
| 15 | `hash: partial` = `HS_REJECT_ALL`, one assignment site | `q10-trace-cubrid.out` + `query_dump.c:3948-3951`, `query_executor.c:4845` | source reading | direct A/B (state) + source |
| 16 | 256x `max_agg_hash_size` change is inert | `q10-bigagghash-trace.out` | `GROUPBY` 3834→3761 ms, page 75,893→73,606 | direct A/B (null result) |
| 17 | CUBRID depth-3 counter 1.96214x the required probes | `q10-trace-cubrid.out`, `variants/plan-act-pg-idxnl.out` | `2,250,758 / 1,147,084` | direct A/B |
| 18 | zero physical device reads, both engines | `Q10-cubrid-buffer-io-diag.json`, `Q10-postgresql-buffer-io-diag.json` | `/proc/<pid>/io read_bytes` delta, `/proc/diskstats` delta | direct measurement |
| 19 | CUBRID writes 836.824 MiB/block to device vs PostgreSQL 4.406 MiB | same two files | `device_delta_MiB` | direct measurement |
| 20 | profile bands (14.60%/3.35% vs 1.66% etc.) | `profile-cubrid-flat.txt`, `profile-pg-flat.txt`, `q10-profile-bands.txt` | self-% summed per band, 0 unresolved lines | profile attribution |
| 21 | IPC 1.59 both, 78.06 G vs 66.76 G instructions/statement | `perf-stat-cubrid.txt`, `perf-stat-pg.txt` | `instructions / repeats` | direct measurement |
| 22 | preflight and post-block gates PASS, `ssot_drift=NONE` | `preflight-Q10.txt`, `q10-postcheck.txt` | see section 1 | direct measurement |
| 23 | WARM convergence, both engines | `q10-convergence-pg.json`, `q10-convergence-cubrid.json`, `Q10-*-warm*.json` | half-split trend over 40 statements | direct measurement |
| 24 | CUBRID `statdump` data-page counters unusable | `q10-cubrid-statdump-{mid,post}.txt` | delta exactly 0 against trace `fetch: 1574584` | direct measurement (negative) |

## 11. Notion sync

This report was produced by the GJC/tmux worker session on the remote measurement host, which
has **no Notion connector**. Per SSOT section 21 (Execution boundary) its Notion-adjacent
duty ends at committing and pushing this report, `raw-manifest.json` and the improvement
registry to `origin/main`; it must never attempt a Notion write.

Write path used: **path 3 of 3** — an idempotent record appended to
`reports/notion_backfill_pending.jsonl`, keyed by
`campaign_id + QNN + session_id + report_commit + content_fingerprint`. The Notion
operational-state update, the Q01–Q22 database row for Q10, the three new
improvement-registry pages (IMP-015/016/017) and the six updated ones must be performed by a
dedicated subagent with Notion tool access, reading the pushed GitHub commit as source of
truth, and the pending record cleared only after a server-side refetch.

Fields the mirror must carry are the same field names used above: QNN and status; campaign ID
and `ssot_commit`; exact GJC session ID; correctness/censoring; CUBRID seconds, PostgreSQL
seconds and ratio; causal multiplier summary; report commit and raw manifest link;
improvement relations; content fingerprint and last verified timestamp. Per section 21's
content-richness rule the page body must mirror section 3-a's factor table, section 3-b's
headline timings, section 4-c's plan comparison, section 6's top-cost symbols for both
engines, section 7's full `file:line` contrast, section 8's narrative **including 8-c's
rejected explanations and the numbers that rejected them**, and every candidate in section 9.

## 12. Completion checklist

| SSOT section 26 gate | Status |
|---|---|
| preflight and correctness status recorded | **yes** — `preflight-Q10.txt` all gates PASS, `ssot_drift=NONE`; `q10-correctness.json` `result-equivalent-at-SF10` |
| three valid headline values for each completing engine | **yes** — CUBRID 6.947999 / 7.146000 / 7.128000; PostgreSQL 4.218695 / 4.211516 / 4.219128; both blocks `load_verdict=CLEAN` under the strict per-sample rule |
| timeout confirmations if censored | **n/a** — no timeout; max statement 7.146 s against a 300 s limit |
| plan section complete | **yes** — estimated (both engines, non-executing), actual (`EXPLAIN ANALYZE` + CUBRID `SET TRACE ON`), plus 3 controlled variants and their plans |
| execution telemetry complete | **yes** — node-level time both engines, CPU split executor/auxiliary, worker counts, `U`/TWU/peak/tail, `/proc` I/O, iostat, `/proc/diskstats`, NUMA, buffer counters (with the `statdump` instrument explicitly excluded and why) |
| profile complete | **yes** — verified PID sets, `perf stat` + call-graph, 0 unknown-symbol lines both engines, banded |
| source contrast complete | **yes** — 8 rows, `file:line` on both sides, classes assigned, absence claims record searched paths/symbols/patterns |
| causal multiplier card has evidence or explicit `UNMEASURED` | **yes** — every factor numeric with a named controlled A/B; **no `UNMEASURED` factors**; residual ±0.000000% on both anchors; error budget stated before interpretation and the one factor inside the band (`F_cpu(controlled)` 1.046193x) explicitly not interpreted |
| Git improvement ledger deduplicated and committed | **yes** — `q10-registry-dedup.txt`; 3 new IDs IMP-015/016/017, 6 reuses, `next_id IMP-018` |
| Notion relations synced **or** idempotent backfill durable | **backfill record** — write path 3, per section 21's execution boundary (this session has no connector) |
| every claim indexed to raw evidence and checksum | **yes** — section 10 index; `raw-manifest.json` carries size + SHA-256 + creation command + stage + validity for every promoted file |
| report, manifest and registry committed, pushed, reachable from `origin/main` | see `report_commit` in the status block |
| `QUERY_COMPLETE` emitted | see the status block |
| current session removed and absence verified | **owed by the controller** — a session cannot remove itself; both checks (`gjc session status <id>` and `tmux has-session -t <id>`) are the transition owner's step |

### Invalid / rejected artifacts, preserved as evidence

| Artifact | Reason |
|---|---|
| `Q10-cubrid-warm-attempt1.json` / `.log` | CUBRID contract block attempt 1: WARM `NOT_CONVERGED (monotone trailing window)`; block **not timed**, no headline value produced |
| `Q10-cubrid-nohashagg-warm-attempt1.json` / `.log` | same, for the `NO_HASH_AGGREGATE` variant block |
| `q10-cubrid-statdump-{pre,mid,post}.txt` | retained, but the data-page counters they contain are **excluded from every calculation** (zero delta against a trace showing 1,574,584 page fetches per statement); the LRU-zone gauges in the same files are cited |
| `q10-bigagghash-trace.out` | a deliberate null-result probe, kept because the null result is the evidence for IMP-017 |

No run was excluded for `INVALID_BACKGROUND_LOAD`: every accepted block reported
`load_verdict=CLEAN` under the strict per-sample rule, with `external_max` between 0.6356 and
0.9974 core-s/s against the 6.0 threshold, and the pre/post external load was 1.054 / 0.270.