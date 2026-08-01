# TPCH-SSPQ FK campaign — Q17 report

TPC-H Query 17, Small-Quantity-Order Revenue.

## 1. Identity

| Field | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q17 |
| SSOT commit | `5ea64a5792950fa1b4d39fdba794cce7879d0bdf` |
| SSOT blob SHA | `510478846bff081d3223d3835069283a7cd2e47b` |
| GJC session ID | `gajae_code_msa28w86_5e9yix4p` |
| Raw root | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q17` |
| Engine block order | Q17 is odd → CUBRID block first, then PostgreSQL (SSOT section 12) |
| Scale | TPC-H SF10, histogram-enabled controlled comparison |

| Engine | Source SHA | Install prefix | Binary SHA-256 | ELF Build ID |
|---|---|---|---|---|
| CUBRID | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9` | `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` | `4df41ee21300bf617bccd5e1d5c8522b074ef86e` |
| PostgreSQL | `5713b437abed7085e7d59849c6e9e0f4f469633d` | `/home/cubrid/pg/pg20devel-5713b437` | `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` | `5f2cb2987765c612638c278f85cfc85c211fffe1` |

Both running binaries were resolved through `/proc/<pid>/exe` and their SHA-256 matched the
frozen `reports/bootstrap/build-manifest.json` (`frozen: true`). Ownership gate `OK` on both
engines before and after every measurement block; `cub_master` pid 1433697 on port 1523,
postmaster pid 1433696 on port 5442, both campaign-owned.

**Preflight (stage 14.1)** — `q17-preflight.txt`:

- `ssot_drift=NONE` (HEAD blob == pinned blob); `git status --porcelain -- tpch-sspq` empty at
  session start; branch `main`, `HEAD == origin/main == 5ea64a5`.
- cpuset: 34 engine TIDs (cub_master 2, cub_server 24, postmaster 1, pg children 7),
  **0 off-cpuset** → PASS. External SUT-set load 0.272 core-s/s against the 6.0 threshold.
- Schema contract: CUBRID 8 FK-owned B-trees, PostgreSQL 8 FKs / 8 `idx_fk_*` / 8 `convalidated`,
  exact child-column order including composite `fk_lineitem_partsupp (l_partkey, l_suppkey)`.
- Row counts identical on both engines (lineitem 59,986,052; part 2,000,000).
- Statistics: CUBRID `update_statistics_update_histogram=y`, `default_histogram_bucket_count=300`;
  PostgreSQL `default_statistics_target=100`.
- Parallel/buffer contract: CUBRID `parallelism=6`, `max_parallel_workers=100`,
  `data_buffer_size=8.0G`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`,
  `parallel_leader_participation=on`, `shared_buffers=8192MB`, `statement_timeout=300000 ms`,
  `jit=off`. Label: **configured node/gather-cap comparison**, **configured-equal buffer budget**.
- Query provenance: `queries/q17-cubrid.sql`, `queries/q17-pg.sql` and the canonical
  `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q17.sql` all SHA-256
  `b796f1bbeb94a927d180a3a4fcde1697d55f13711f92450bc94aaf9a3bba3e3f`. `queries/diff/q17.diff` is
  0 bytes and `cmp` confirms the two dialect files are byte-identical — **zero dialect changes**.

`dynamic_shared_memory_type` is not recorded as decision-relevant here: neither engine's natural
Q17 plan contains a Parallel Hash Join or a large parallel gather (section 4), so the section 9
`/dev/shm` consideration does not bind on this query.

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored; no timeout occurred on either engine, and the
300-second rule of section 13 was never approached (slowest single statement 9.36 s).

| Field | Value |
|---|---|
| Status | `result-equivalent-at-SF10` |
| Rows | 1 |
| `ORDER BY` present | no → canonical whole-row sort with duplicate multiplicity preserved |
| CUBRID output | `3295493.512857142857142857142857142857143` |
| PostgreSQL output | `3295493.512857142857` |
| Absolute difference | 1.43e-13 |
| Tolerance allowed | 1e-12 × max(1, |a|, |b|) = 3.30e-06 |

The difference is purely an output-scale (decimal-places) difference on the same value, which is
exactly what the section 11 rule permits; raw decimal text is preserved above and in
`q17-correctness-cubrid.out` / `q17-correctness-postgresql.out`. The tolerance is not being used
to hide a different row set: the row count is 1 on both sides and the independent ground-truth
probe (section 5) confirms both engines aggregated the same 5,526 qualifying lineitem rows.

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
0.016676x = 0.112151x [plan] × 0.203216x [units] × 0.731709x [CPU-sec]

              equivalently, CUBRID-faster form:
59.9656x    = 8.9166x [plan]  × 4.9209x [units]  × 1.3667x [CPU-sec]

0.731709x [CPU-sec] = 0.535303x [work] × 1.366905x [cost]
```

`F_plan` is **numeric** and is anchored on a same-engine PostgreSQL native/controlled A/B.
Anchor direction: **PostgreSQL native (hash join, lineitem-driven) → PostgreSQL controlled
(index nested loop, part-driven)**, the controlled shape being the one CUBRID chooses natively.
The only change is `enable_hashjoin=off` passed through `PGOPTIONS`; the query text is untouched,
so this is a plan-shape control and not a dialect change. `F_units` and `F_cpu` are then computed
on the **remaining controlled cross-engine pair** — CUBRID native versus PostgreSQL controlled —
which are structurally the same plan (section 4). Native and controlled denominators are not mixed.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `R_wall` | 0.016676x (PG/CUBRID 59.9656x) | wall seconds | median of 3 measured WARM statements, block1 | `T_C / T_P` | `Q17-cubrid-headline-block1.json`, `Q17-postgresql-headline-block1.json` | direct A/B |
| `F_plan` | 0.112151x (8.9166x) | wall seconds | same engine, same block regime, 3 measured statements | `T_Pc / T_P` | `Q17-postgresql-nlj-headline-block1.json`, `Q17-postgresql-headline-block1.json` | direct A/B (same-engine controlled) |
| `F_units` | 0.203216x (4.9209x) | core-seconds per wall-second | total query CPU over the 4-statement block ÷ sum of statement walls | `U_Pc / U_C` | `Q17-cubrid-headline-telemetry.json`, `Q17-postgresql-nlj-headline-telemetry.json` | per-TID sampler, actual timestamp deltas |
| `F_cpu` | 0.731709x (1.3667x) | total query CPU-seconds | per measured statement, `U × t` | `CPU_C / CPU_Pc` | same two telemetry artifacts | per-TID sampler |
| `F_work` | 0.535303x (1.8681x fewer) | executor tuple reads (heap rows + index rows), whole plan | one measured statement | `W_C / W_P` | `q17-trace-cubrid.out`, `q17-plan-act-pg-nlj.out`, `q17-groundtruth-pg.out` | direct count (engine trace + EXPLAIN ANALYZE loops/rows) |
| `F_cost` | 1.366905x | core-seconds per executor tuple read | same | `(CPU_C/W_C)/(CPU_Pc/W_P)` | derived, `q17-causal-card.txt` | profile attribution |

Measured inputs (`q17-causal-card.txt`):

| Quantity | Value |
|---|---|
| `T_C` CUBRID native median | 0.146000 s |
| `T_P` PostgreSQL native median | 8.754980 s |
| `T_Pc` PostgreSQL controlled (nlj) median | 0.981877 s |
| `U_C` | 4.92437 core-s/wall-s |
| `U_P` | 1.09132 core-s/wall-s |
| `U_Pc` | 1.00071 core-s/wall-s |
| `CPU_C = U_C·T_C` | 0.718958 core-s |
| `CPU_P = U_P·T_P` | 9.554485 core-s |
| `CPU_Pc = U_Pc·T_Pc` | 0.982574 core-s |
| `W_C` | 2,122,770 tuple reads (2,000,000 part heap + 61,385 outer index + 61,385 subquery index) |
| `W_P` | 3,965,548 tuple reads (2,000,000 part heap + 61,385 outer index + 61,385×31.02 subquery index) |

**Reconstruction residual: +0.0000%.** This must be read honestly: with `F_plan = T_Pc/T_P` and
`F_units × F_cpu = T_C/T_Pc` the product telescopes to `T_C/T_P` by construction, so the residual
tests arithmetic, not independence. The card's genuine validation is that `U`, which is the only
non-wall input, is confirmed by **two independent instruments** that the card does not use:

| Configuration | sampler `U` | sampler executor-only `U` | `perf stat` CPUs utilized | delta | TWU | TWU vs `U` |
|---|---|---|---|---|---|---|
| CUBRID native | 4.92437 | 4.8739 | 4.892 | −0.37% | 4.6063 | −6.46% |
| PostgreSQL native | 1.09132 | 0.9969 | 1.001 | −0.41% | 1.0866 | −0.43% |
| PostgreSQL controlled (nlj) | 1.00071 | 1.0007 | 0.972 | +2.95% | 1.0081 | +0.74% |

`perf stat` attaches to the server process tree only, so the comparable sampler figure is the
executor-only one (it excludes 0.03 / 3.33 / 0.00 core-s of client and auxiliary CPU respectively);
on that basis the two instruments agree to within 0.41% on both native configurations. TWU is
weighted by actual sample timestamp deltas, never by a nominal interval, and is never substituted
for the configured cap.

**Error budget.** The dominant term is CUBRID's client timer resolution: `csql` prints three
decimals, so one quantum is 0.001 s = **0.6849%** of `T_C`. Within-block standard deviations are
CUBRID 0.001732 s (1.1863%), PostgreSQL 0.013837 s (0.1581%), PostgreSQL-nlj 0.002072 s (0.2110%).
No factor in the card is claimed to a precision finer than the 0.68% CUBRID quantum.

### 3-b. Headline timings

Regime `single-query-repeat WARM`, connection mode `single-connection-four-statements`
(1 uncounted warmup + 3 measured, one direct connection, no reconnect or prepare between
statements, all rows fully consumed into a campaign-owned sink under `work/Q17`).
Headline = block1 for every configuration, the first gated section-12 block after the WARM gate
passed. Blocks 2 and 3 are retained as block-to-block stability evidence.

| Field | CUBRID | PostgreSQL |
|---|---|---|
| measured statement 1 | 0.149000 s | 8.755040 s |
| measured statement 2 | 0.146000 s | 8.731043 s |
| measured statement 3 | 0.146000 s | 8.754980 s |
| **median (headline)** | **0.146000 s** | **8.754980 s** |
| mean | 0.147000 s | 8.747021 s |
| within-block standard deviation | 0.001732 s | 0.013837 s |
| uncounted warmup statement | 0.150000 s | 9.360582 s |
| **median wall ratio** `T_C/T_P` | **0.016676** (PostgreSQL/CUBRID **59.9656x**) | |
| correctness | `result-equivalent-at-SF10` | |
| censoring | not censored; no timeout on either engine | |

Three values only; no confidence interval is claimed.

Block-to-block stability (medians): CUBRID 0.146 / 0.148 / 0.147 s (spread 1.3605%, i.e. two
timer quanta), PostgreSQL 8.754980 / 8.763105 / 8.698797 s (spread 0.7345%). Controlled variant
PostgreSQL-nlj 0.981877 / 0.978823 / 0.972367 s (spread 0.9705%).

Every block was **accepted on attempt 1** with load verdict `CLEAN` under the strict per-sample
rule (`TPCH_SSPQ_LOAD_VERDICT` left at its `verdict` default), so no block needed the
contract-window reading. External SUT-set load during the accepted blocks: CUBRID mean 0.385
max 2.4951 core-s/s, PostgreSQL mean 0.2129 max 0.655, PostgreSQL-nlj mean 1.1262 max 1.679 —
all under the 6.0 threshold. Because CUBRID's whole 4-statement block is only ~0.59 s of wall,
the during-run load monitor was run at a 0.05 s period for CUBRID instead of the 0.25 s default
so the block is covered by ~12 samples rather than 2; this only makes the during-run gate finer,
never coarser (`harness/measure_block.sh`, `TPCH_SSPQ_BGLOAD_INTERVAL`).

**WARM proof (proved, not assumed).** WARM gate parameters were derived, not guessed
(`q17-warm-gate-params.txt`): a 200-statement CUBRID probe and a 40-statement PostgreSQL probe
established the stationary level, and a moving-block bootstrap (block length 6, 4000 reps) over
the stationary segments gave the null distribution of the half-split trend statistic at the
series length actually used — CUBRID p95 0.6897% / max 1.3793% at n=40, PostgreSQL p95 0.3132% /
max 0.4634%. The gate was therefore set to WINDOW 6, `LEVEL_TOL` 3.0%, `SPREAD_SANITY` 7.0%,
40 warm statements, one parameter set for both engines. CUBRID's level cannot be resolved below
one timer quantum (0.6849%), and the stationary segment's own trailing spread at window 6 reaches
4.1096%, which is why a tighter tolerance would reject an engine that has in fact converged.
All six blocks converged: CUBRID −2.0270% / +0.6803% / +0.0000%, PostgreSQL +0.4718% / −0.1675% /
+0.1243%.

Physical-read evidence per engine:

- **CUBRID: zero physical reads.** The engine's own trace reports `ioread: 0` at the SELECT level
  and at every scan node (`q17-trace-cubrid.out`); the telemetry block recorded process
  `read_bytes = 0` and device `sectors_read = 0` on every data device; and a `statdump` delta
  taken with adequate flush latency around one execution shows 161,531 page fetches against
  **+1** `Num_data_page_ioreads`. Note that `statdump` deltas taken immediately around the 0.59 s
  block read as exactly zero on all three blocks — that is a flush-latency artifact of sampling a
  sub-second window, not a zero-fetch claim, so the WARM proof above rests on the trace, procfs
  and device evidence rather than on those block gauges.
- **PostgreSQL native: cannot reach zero physical reads, by construction.** `heap_blks_read`
  deltas were 937,800 / 887,112 / 836,424 per 4-statement block (≈234k / 222k / 209k per
  statement, ≈1.8 GB), and `EXPLAIN ANALYZE` confirms `read=196866` for a single statement.
  lineitem occupies 1,125,128 blocks against a `shared_buffers` of 1,048,576 blocks, so the plan
  PostgreSQL chose has a working set that provably does not fit the configured-equal 8192 MB
  budget. The engine is nevertheless at steady state — the level converged and within-block
  spread is 0.16% — so this is WARM in the steady-state sense the contract requires, with the
  residual reads recorded rather than hidden.
- **PostgreSQL controlled (nlj): zero physical reads.** `heap_blks_read` delta 0 and an identical
  `heap_blks_hit` delta of 8,026,344 in all three blocks; `EXPLAIN ANALYZE` shows
  `Buffers: shared hit=2198652` with no `read=`. The plan PostgreSQL *rejected* is fully resident.

The controlled cross-engine pair used for `F_units` and `F_cpu` is therefore a
**zero-physical-read pair on both sides**, which removes I/O residency as a confound from those
two factors and confines it to `F_plan`.

## 4. Plan

### CUBRID — estimated (`SET OPTIMIZATION LEVEL 514`, no execution)

```text
idx-join (inner join)
    outer: sscan  class: part node[1]   sargs: term[2] AND term[3]   cost: 29353 card 1992
    inner: iscan  class: lineitem node[0]  index: fk_lineitem_partsupp term[1]  sargs: term[0]
    sargs: term[0]        subqs: 0        cost: 57848 card 5975

term[0]: [lineitem].l_quantity range (min inf_lt (select 0.2*avg(l_quantity) ...)) (sel 0.1)
term[1]: [part].p_partkey=[lineitem].l_partkey  (sel 5E-07) (mergeable) (indexable)
term[2]: [part].p_container='MED BOX'  (sel 0.0249)
term[3]: [part].p_brand='Brand#23'     (sel 0.04)
subquery[0]: {p_partkey[1]} {node[1]} (from term(s) 0)      <- correlated on the PART node
```

### PostgreSQL — estimated (`EXPLAIN (COSTS, VERBOSE, SETTINGS)`, no execution)

```text
Aggregate  (cost=1933241.95..1933241.96 rows=1)
  -> Hash Join  (cost=49711.16..1933195.71 rows=18496)   Inner Unique: true
       Hash Cond:   (lineitem.l_partkey = part.p_partkey)
       Join Filter: (lineitem.l_quantity < (SubPlan expr_1))
       -> Seq Scan on lineitem  (cost=0.00..1725000.88 rows=59987288)
       -> Hash (rows=2023) -> Gather (Workers Planned: 4) -> Parallel Seq Scan on part
       SubPlan expr_1
         -> Aggregate (cost=112.98..112.99)
              -> Index Scan using idx_fk_lineitem_partsupp on lineitem (cost=0.44..112.91 rows=27)
```

**The two shapes are structurally different, so `F_plan` is not 1.0000 and is not asserted.**
CUBRID drives from the filtered `part` side and index-probes lineitem; PostgreSQL drives from
lineitem and sequentially scans all 59,986,052 rows to probe a 2,044-entry hash table.

### Actual plans (stage 14.6, separate non-headline runs, each engine driven to its own steady state first)

CUBRID trace (`q17-trace-cubrid.out`), one execution, `time: 157` ms:

```text
SELECT (time: 157, fetch: 4, ioread: 0)
  SCAN (table: dba.part) (heap time: 157, ioread: 0)
       (parallel workers: 5, heap time: 148..157, readrows: 399448..401913, gather: buildvalue)
    SCAN (index: lineitem.fk_lineitem_partsupp) (btree time: 15, readkeys: 10219, rows: 61385)
    SUBQUERY (correlated)
      SELECT (time: 39, fetch: 139208, ioread: 0)
        SCAN (index: lineitem.fk_lineitem_partsupp) (btree time: 33, readkeys: 20438, rows: 122770)
        SUBQUERY_CACHE (hit: 118682, miss: 4088, size: 1980048, status: enabled)
```

PostgreSQL native `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, TIMING)` (`q17-plan-act-pg.out`),
`Execution Time: 10882.154 ms` (instrumented, above the 8.755 s headline — 61,385 instrumented
subplan loops plus 60M instrumented scan rows):

```text
Hash Join (actual time=60.466..10880.247 rows=5526 loops=1)
  Rows Removed by Join Filter: 55859
  Buffers: shared hit=3059341 read=196866
  -> Seq Scan on lineitem (actual time=0.119..2979.000 rows=59986052 loops=1)
        Buffers: shared hit=928262 read=196866
  -> Hash (rows=2044) -> Gather (Workers Launched: 4) -> Parallel Seq Scan on part
        Rows Removed by Filter: 399591 (per worker, loops=5)
  SubPlan expr_1
    -> Aggregate (actual time=0.038..0.038 rows=1 loops=61385)
         -> Index Scan using idx_fk_lineitem_partsupp (rows=31.02 loops=61385)
              Index Searches: 61385      Buffers: shared hit=2090095
```

PostgreSQL controlled `nlj` (`q17-plan-act-pg-nlj.out`), `Execution Time: 1253.680 ms`:

```text
Nested Loop (actual time=1.289..1252.841 rows=5526 loops=1)   Buffers: shared hit=2198652
  -> Seq Scan on part (actual time=0.698..229.298 rows=2044 loops=1)
        Rows Removed by Filter: 1997956    Buffers: shared hit=40984
  -> Index Scan using idx_fk_lineitem_partsupp on lineitem (rows=2.70 loops=2044)
        Index Searches: 2044     Buffers: shared hit=2157668
        Filter: (lineitem.l_quantity < (SubPlan expr_1))     Rows Removed by Filter: 27
        SubPlan expr_1
          -> Aggregate (actual time=0.016..0.016 rows=1 loops=61385)
               -> Index Scan using idx_fk_lineitem_partsupp (rows=31.02 loops=61385)
                    Index Searches: 61385      Buffers: shared hit=2090095
```

### Plan comparison summary

| Aspect | CUBRID native | PostgreSQL native | PostgreSQL controlled (nlj) |
|---|---|---|---|
| Join method | index nested loop, part outer | hash join, lineitem outer | index nested loop, part outer |
| lineitem rows scanned for the join | 61,385 (index) | 59,986,052 (seq) | 61,385 (index) |
| part rows scanned | 2,000,000 (parallel, 5 workers) | 2,000,000 (parallel, 4 workers) | 2,000,000 (serial) |
| Correlated subquery invocations | 61,385 | 61,385 | 61,385 |
| Correlated subquery **executions** | **2,044** | **61,385** | **61,385** |
| Buffer accesses | — (`fetch` 161,531/exec) | 3,256,207 (196,866 physical) | 2,198,652 (0 physical) |
| Active units | 4.92 | 1.09 | 1.00 |
| Estimated cost | 57,848 | 1,933,196 | 6,466,108 |

Two planner facts are worth stating precisely, because they are the whole of `F_plan`:

1. **PostgreSQL costs the winning shape at 3.34x the losing one.** Its own estimate is 6,466,108
   for the nested loop against 1,933,196 for the hash join, yet the nested loop measures 8.92x
   *faster*. The cost model's error is concentrated in how the correlated `SubPlan` in the join
   qual is charged: it is charged per inner candidate row in the nested loop
   (`Index Scan ... cost=0.44..3161.12`, i.e. 27 candidate rows × 112.98 plus the index scan), but
   the hash join's total of 1,933,196 leaves only ≈8,515 cost units after the 1,725,001 outer seq
   scan, the 49,686 hash build and the 149,968 hash probe — far less than the same 61,385
   evaluations would cost at 112.98 each. Both plans execute the SubPlan exactly 61,385 times, as
   `loops=61385` shows in both actual plans, so the two estimates disagree about identical work.
2. **The join can never be parallelised.** With `parallel_setup_cost=0`, `parallel_tuple_cost=0`
   and `min_parallel_table_scan_size=0` (`q17-plan-est-pg-parallel_forced.out`), PostgreSQL still
   places `Gather` *below* the Hash Join rather than above it, so the join and all 61,385 SubPlan
   executions stay in the leader. That is why `U_P` is 1.09 and not ~6: only the 59 ms part scan
   is parallel. The mechanism is cited in section 7.

## 5. Execution telemetry

Per-TID sampler pinned to collector CPUs 20-23, weighted by actual sample timestamp deltas.
Sampler period was set per configuration because CUBRID's whole block is ~0.59 s: 0.01 s for
CUBRID (211 samples), 0.05 s for PostgreSQL native (638 samples), 0.02 s for PostgreSQL-nlj
(255 samples).

| Quantity | CUBRID native | PostgreSQL native | PostgreSQL nlj |
|---|---|---|---|
| `t_block` (Σ statement walls) | 0.5950 s | 35.2601 s | 4.0971 s |
| `executor_cpu` | 2.90 core-s | 35.15 core-s | 4.10 core-s |
| `auxiliary_query_cpu` | 0.03 core-s | 3.33 core-s | 0.00 core-s |
| `total_query_cpu` | 2.93 core-s | 38.48 core-s | 4.10 core-s |
| `U = total_query_cpu / t_block` | 4.92437 | 1.09132 | 1.00071 |
| time-weighted active units (TWU) | 4.6063 | 1.0866 | 1.0081 |
| max simultaneous active units | 7.8629 | 1.6494 | 1.4301 |
| busy window | 0.636 s | 35.414 s | 4.027 s |
| serial tail | 0.023 s | 2.218 s | 4.027 s |
| planned workers | 5 (trace: `parallel workers: 5`) | 4 (Gather, part scan only) | 0 |
| launched workers | 5 | 4 (`Workers Launched: 4`) | 0 |

Executor/auxiliary classification (`per_bucket_core_s`):

- CUBRID executor 2.90 = `parallel-query` 2.87 + `transaction` 0.02 + `connections` 0.01;
  auxiliary 0.03 = `csql` 0.01 + `dwb-file-sync` 0.01 + `vacuum-master` 0.01. **99.0% of CUBRID's
  executor CPU is in the parallel-query worker pool.**
- PostgreSQL native executor 35.15 = leader backend; auxiliary 3.33 = `pg_io_worker` 3.32 +
  postmaster 0.01. The io-worker CPU is auxiliary by the section 15 rule and is never attributed
  to the executor; it exists because this plan takes 196,866 buffer misses per statement.
- PostgreSQL nlj executor 4.10 = leader backend; auxiliary 0.00 — with zero physical reads there
  is no io-worker CPU at all.

`unattributed_background` is nil: every sampled TID resolved to one of the buckets above.

I/O over the telemetry block: CUBRID process `read_bytes` 0 and device `sectors_read` 0 (write
traffic 0.03–0.09 MiB is checkpoint/WAL background, not query reads). PostgreSQL native
`rchar` 7,338,908,917 with 10.59 MiB device reads on `sdb3` — the buffer misses are served almost
entirely by the OS page cache rather than the device, which is why they cost CPU (io workers)
rather than device latency. PostgreSQL nlj `read_bytes` 17,072,128 with 0 device sectors read.

Two configuration observations, neither of which affects any number above:

- CUBRID reached **5 active units against a configured `parallelism=6`**. The trace reports
  `parallel workers: 5` and `gather: buildvalue`; `U_C` 4.92 and TWU 4.61 are consistent with five
  producing units and a coordinator that is a pure consumer. This is the IMP-012 mechanism and is
  recorded as a Q17 relation in section 9.
- A session-level `SET SYSTEM PARAMETERS 'parallelism=1'` was accepted without error but had no
  effect (still `parallel workers: 5`, still 0.161 s). `PRM_ID_PARALLELISM` is declared
  `PRM_FOR_SERVER | PRM_FOR_CLIENT | PRM_FORCE_SERVER` with **no `PRM_USER_CHANGE`**
  (`src/base/system_parameter.c:5111-5122`), so refusing the change is correct; only the silent
  acceptance is questionable. No candidate is raised: there is no measured performance effect and
  it is outside Q17's causal chain. Recorded so the failed serial A/B is not mistaken for a result.

## 6. Profile

Non-headline. `perf stat` and `perf record -F 999 -g --call-graph dwarf` attached to verified PID
sets (CUBRID: the single `cub_server` pid, all query worker threads inside it; PostgreSQL: the
postmaster before the client connected, so inherit-on-fork covers the leader and every statement's
workers). `perf report` pinned to CPUs 20-23.

| Configuration | samples | lost | unresolved symbols | cycles | instructions | IPC | GHz | CPUs utilized |
|---|---|---|---|---|---|---|---|---|
| CUBRID native | 132,837 | 0 | 0 | 401,999,888,319 | 919,779,129,521 | 2.29 | 2.739 | 4.892 |
| PostgreSQL native | 30,625 | 0 | 0 | 86,431,558,772 | 124,316,626,849 | 1.44 | 2.877 | 1.001 |
| PostgreSQL nlj | 29,981 | 0 | 0 | 84,046,705,621 | 200,309,496,504 | 2.38 | 2.881 | 0.972 |

PostgreSQL native's IPC of 1.44 against the controlled plan's 2.38 is itself part of `F_plan`:
the 60M-row sequential scan feeding hash probes is memory-bound in a way the index-driven plan is
not, and it executes 38% fewer instructions to do 8.9x more wall.

### Top-cost symbols

CUBRID native (top 18 of 41 symbol lines ≥0.3%, 84.91% of the profile above threshold):

| % | symbol | % | symbol |
|---|---|---|---|
| 15.18 | `heap_attrinfo_read_dbvalues` | 2.17 | `eval_value_rel_cmp` |
| 5.93 | `pgbuf_fix_release` | 1.95 | `or_mvcc_get_header` |
| 5.92 | `__memmove_evex_unaligned_erms` | 1.92 | `heap_scan_get_visible_version` |
| 5.43 | `mr_readval_char_internal` | 1.89 | `spage_get_record` |
| 5.27 | `eval_pred` | 1.84 | `eval_data_filter` |
| 4.51 | `mr_cmpval_char` | 1.79 | `or_header_size` |
| 3.68 | `heap_next_1page` | 1.66 | `parallel_scan::slot_iterator::next_qualified_slot_with_peek` |
| 3.07 | `pr_clear_value` | 1.60 | `or_mvcc_get_repid_and_flags` |
| 2.72 | `lang_fastcmp_byte` | 1.31 | `pgbuf_unfix` |
| 2.69 | `tp_value_compare_with_error` | 2.28 | `db_value_domain_init` |

PostgreSQL controlled nlj (top 18 of 60 symbol lines ≥0.3%, 91.15% above threshold):

| % | symbol | % | symbol |
|---|---|---|---|
| 12.19 | `tts_buffer_heap_getsomeattrs` | 2.24 | `heap_hot_search_buffer` |
| 8.30 | `hash_search_with_hash_value` | 2.08 | `bpchareq` |
| 4.05 | `ExecInterpExpr` | 2.06 | `BufferLockUnlock` |
| 3.67 | `PinBuffer` | 1.92 | `accum_sum_add` |
| 2.83 | `StartReadBuffer` | 1.74 | `ResourceOwnerForget` |
| 2.77 | `GetPrivateRefCountEntrySlow` | 1.65 | `heapam_index_fetch_tuple` |
| 2.68 | `LWLockRelease` | 1.62 | `_bt_compare` |
| 2.63 | `UnpinBufferNoOwner` | 1.60 | `heap_page_prune_opt` |
| 2.55 | `LWLockAttemptLock` | 1.58 | `AllocSetReset` |
| 2.34 | `LockBufferInternal` | 2.33 | `hash_bytes` |

PostgreSQL native (top 10): `tts_buffer_heap_getsomeattrs` 24.22, `ExecScanHashBucket` 11.34,
`hash_search_with_hash_value` 9.50, `ExecHashJoin` 6.71, `ExecSeqScan` 5.03,
`heap_page_prune_opt` 4.86, `heapgettup_pagemode` 4.32, `PinBuffer` 3.00, `heap_getnextslot` 2.66,
`ExecJustHashOuterVarStrict` 2.30. Its dominant call path is
`slot_deform_heap_tuple → tts_buffer_heap_getsomeattrs → ExecJustHashOuterVarStrict →
ExecHashJoinOuterGetTuple → ExecHashJoin` at 21.07% — deforming 60M lineitem tuples purely to
extract the hash key. That entire band exists only because of the plan choice and is therefore
inside `F_plan`, not inside `F_cpu`.

### Banded comparison on the controlled pair (same plan shape)

Bands are exhaustive over the ≥0.3% symbol lines; the unbanded remainder above threshold is 0.00%
for CUBRID.

| Band | CUBRID % → core-s | PostgreSQL nlj % → core-s | Ratio |
|---|---|---|---|
| A+B attribute materialisation and value lifecycle | 27.51% → 0.19779 | 13.25% → 0.13019 | **1.52x core-s on 1.87x fewer tuples** |
| C predicate / sarg evaluation | 19.59% → 0.14084 | 8.35% → 0.08205 | **1.72x** |
| D buffer fix/unfix, pin/lock, resource owner | 8.92% → 0.06413 | 37.99% → 0.37327 | **0.17x — PostgreSQL 5.8x higher** |
| E scan driver / memmove | 12.89% → 0.09267 | ~6.5% → 0.06387 | 1.45x |
| F numeric aggregation | 2.27% → 0.01632 | ~5.4% → 0.05306 | 0.31x |

Band A+B on CUBRID = `heap_attrinfo_read_dbvalues` 15.18 + `mr_readval_char_internal` 5.43 +
`mr_data_readval_char` 0.75 + `pr_clear_value` 3.07 + `db_value_domain_init` 2.28 +
`pr_type_from_id`(+plt) 0.80; on PostgreSQL = `tts_buffer_heap_getsomeattrs` 12.19 +
`detoast_attr` 0.74 + `pg_detoast_datum_packed` 0.32. Per executor tuple read this is CUBRID
93.2 ns against PostgreSQL 32.8 ns — **2.84x**.

Band C on CUBRID = `eval_pred` 5.27 + `mr_cmpval_char` 4.51 + `lang_fastcmp_byte` 2.72 +
`tp_value_compare_with_error` 2.69 + `eval_value_rel_cmp` 2.17 + `eval_data_filter` 1.84 +
`tp_value_cast_internal` 0.39; on PostgreSQL = `ExecInterpExpr` 4.05 + `bpchareq` 2.08 +
`__memcmp_evex_movbe` 1.35 + `FunctionCall2Coll` 0.44 + `pg_newlocale_from_collation` 0.43. Both
engines evaluate the identical two `part` predicates over the identical 2,000,000 rows, so per
part row this is CUBRID 70.4 ns against PostgreSQL 41.0 ns — **1.72x**.

Band D is a **counter-example to IMP-013** and is reported as such: on Q17's controlled pair
PostgreSQL spends 5.8x more core-seconds on buffer management than CUBRID, because its 2,198,652
buffer accesses each pay pin, content-lock, resource-owner and buffer-table-hash bookkeeping,
and 95.1% of those accesses come from the 61,385 SubPlan index scans that CUBRID does not perform.
No IMP-013 relation is added for Q17.

## 7. Source contrast

| Item | CUBRID file:line | PostgreSQL file:line | Difference | Class |
|---|---|---|---|---|
| Correlated scalar-subquery re-execution | `src/query/fetch.c:4086-4111` — in `fetch_peek_dbval()` `case TYPE_CONSTANT`, when the subquery XASL carries `XASL_USES_SQ_CACHE` the executor first calls `sq_get(thread_p, SQ_CACHE_KEY_STRUCT(xasl), xasl, regu_var)`; only on a miss does it run `EXECUTE_REGU_VARIABLE_XASL` and then `sq_put()` the result keyed on the correlation values. Cache implemented in `src/query/subquery_cache.c:290-322` (`sq_cache_initialize`), `:336-393` (`sq_put`), `:400-430` (`sq_get`). | `src/backend/executor/nodeSubplan.c:84-86` dispatches to `ExecHashSubPlan` only when `subplan->useHashTable`; otherwise `ExecScanSubPlan`. `src/backend/executor/nodeSubplan.c:198-241` — `ExecScanSubPlan` unconditionally adds every `parParam` to `planstate->chgParam` and calls `ExecReScan(planstate)`, i.e. a full re-execution on every invocation. `useHashTable` is set only at `src/backend/optimizer/plan/subselect.c:527-531`, gated on `subLinkType == ANY_SUBLINK && splan->parParam == NIL` — an **uncorrelated** ANY sublink. Q17's is `EXPR_SUBLINK` and correlated, so the hashed path is unreachable. `src/backend/optimizer/plan/subselect.c` states it directly in a comment: results are "not interesting for parameter change signaling since we always re-evaluate the subplan". | CUBRID memoises the correlated subquery on its correlation key and executes it 2,044 times for 61,385 invocations (96.7% hit rate); PostgreSQL has no memo for a correlated SubPlan and executes it 61,385 times in **both** of its plans (`loops=61385` in `q17-plan-act-pg.out` and `q17-plan-act-pg-nlj.out`). 30.03x fewer executions, exactly the 30 lineitem rows per matching part measured in `q17-groundtruth-pg.out`. | structural absence |
| Parallelisation of a join whose qual contains a correlated subquery | CUBRID parallelises the driving `part` heap scan at 5 workers with the correlated subquery evaluated inside the scan (`q17-trace-cubrid.out`: `parallel workers: 5`, `gather: buildvalue`), reaching `U_C` 4.92. Parallel-scan task path visible in the profile as `parallel_scan::task<...>::loop → drain_slot_oids → next_qualified_slot_with_peek → eval_data_filter`. | `src/backend/optimizer/util/clauses.c:931-950` — `max_parallel_hazard_walker` rejects a `SubPlan` whose `subplan->parallel_safe` is false as `PROPARALLEL_RESTRICTED`. `parallel_safe` is copied from the subquery's own plan at `src/backend/optimizer/plan/subselect.c:351`, and that plan is itself parallel-restricted because the correlated `p_partkey` reference is a `PARAM_EXEC` Param not in `safe_param_ids` — `src/backend/optimizer/util/clauses.c:960-973`. The joinrel therefore never acquires a partial path. | Measured, not inferred: with `parallel_setup_cost=0`, `parallel_tuple_cost=0` and `min_parallel_table_scan_size=0`, PostgreSQL still emits `Gather` *below* the Hash Join (`q17-plan-est-pg-parallel_forced.out`), leaving the join and all 61,385 SubPlan executions in the leader. `U_P` 1.09, `U_Pc` 1.00 against CUBRID's 4.92. | structural absence |
| Per-row materialisation of scan output | `src/storage/heap_file.c` `heap_attrinfo_read_dbvalues()` — 15.18% of the CUBRID profile, reached from `eval_data_filter` (`src/query/query_evaluator.c`) once per part row; with `mr_readval_char_internal` 5.43%, `db_value_domain_init` 2.28% and `pr_clear_value` 3.07% the band is 27.51% → 0.19779 core-s, 93.2 ns per executor tuple read. | `src/backend/executor/execTuples.c` `tts_buffer_heap_getsomeattrs()` → `slot_deform_heap_tuple()` — 12.19% → 0.13019 core-s, 32.8 ns per executor tuple read. Deforms into a flat Datum/isnull array using cached attribute offsets; no per-value type object, no per-value domain init, no per-value teardown. | 2.84x more CPU per tuple on the same plan shape, both engines fully resident with zero physical reads. | same stage, lower measured cost |
| Scan-level predicate evaluation | `eval_pred` / `eval_value_rel_cmp` (`src/query/query_evaluator.c`) → `tp_value_compare_with_error` (`src/object/object_domain.c`) → `mr_cmpval_char` → `lang_fastcmp_byte` — 19.59% → 0.14084 core-s, 70.4 ns per part row for the two `bpchar` equality sargs. | `ExecInterpExpr` (`src/backend/executor/execExprInterp.c`) with the qual compiled once into type-specialised steps, calling `bpchareq` (`src/backend/utils/adt/varchar.c`) directly — 8.35% → 0.08205 core-s, 41.0 ns per part row. | 1.72x more CPU for the identical two predicates over the identical 2,000,000 rows. | same stage, lower measured cost |
| Buffer pin/unpin accounting | `pgbuf_fix_release` 5.93% + `pgbuf_unfix` 1.31% + mutex band 1.30% = 8.92% → 0.06413 core-s. | `PinBuffer` 3.67 + `StartReadBuffer` 2.83 + `GetPrivateRefCountEntrySlow` 2.77 + `LWLockRelease` 2.68 + `UnpinBufferNoOwner` 2.63 + `LWLockAttemptLock` 2.55 + `LockBufferInternal` 2.34 + `BufferLockUnlock` 2.06 + `ResourceOwnerForget` 1.74 + `hash_search_with_hash_value` 8.30 + `hash_bytes` 2.33 + others = 37.99% → 0.37327 core-s. | PostgreSQL spends 5.8x more here, driven by 2,198,652 buffer accesses against CUBRID's memoised access pattern. Counter-example to IMP-013 on this query. | same stage, lower measured cost (CUBRID favoured) |
| Selectivity of `attribute < (correlated subquery)` | `src/optimizer/query_planner.c:10498-10625` `qo_comp_selectivity()` — `pc_lhs` is `PC_ATTR`, `pc_rhs` for a subquery falls to `default: break` at `:10558-10559`, so the function returns `DEFAULT_COMP_SELECTIVITY` at `:10624` (`= 0.1`, `src/optimizer/query_planner.h:118`). Visible as `term[0] ... (sel 0.1)` in `q17-plan-est-cubrid.out`. | `src/backend/optimizer/path/clausesel.c` / `src/backend/utils/adt/selfuncs.c` reach the same situation through `clause_selectivity` with no statistics for a SubPlan result and fall back to `DEFAULT_INEQ_SEL` (0.3333, `src/include/utils/selfuncs.h`), giving the `rows=18496` estimate against a true 5,526. | Both engines guess. **No measured effect on Q17 on either side**: CUBRID chose the optimal plan regardless, and PostgreSQL's plan error is caused by the join-qual SubPlan costing described in section 4, not by this selectivity. | common to both engines |

Claims of absence were searched, not assumed. For a PostgreSQL correlated-subplan memo the searched
paths were `src/backend/executor/nodeSubplan.c`, `src/backend/executor/nodeMemoize.c` and
`src/backend/optimizer/plan/subselect.c`; the searched symbols/patterns were `useHashTable`,
`hashtable`, `ExecHashSubPlan`, `Memoize`, `chgParam` and `ExecReScan`. `Memoize` exists in
PostgreSQL but is a **nested-loop inner-path** cache keyed on join parameters
(`src/backend/optimizer/util/pathnode.c` `create_memoize_path`, planned only in
`src/backend/optimizer/path/joinpath.c`), not a cache over a SubPlan expression, and no Memoize
node appears in either Q17 plan.

## 8. Causal decomposition details

The 59.9656x median wall gap decomposes into three independent, separately measured factors.

**`F_plan` = 8.9166x — PostgreSQL's plan choice, anchored by a same-engine A/B.**
Forcing `enable_hashjoin=off` and changing nothing else moves PostgreSQL from 8.754980 s to
0.981877 s. The controlled plan is structurally CUBRID's: seq-scan the filtered `part`, index-probe
lineitem on `idx_fk_lineitem_partsupp`. Three measured consequences of the native choice, all
folded into this factor and none double-counted elsewhere:
lineitem rows scanned 59,986,052 against 61,385 (977x);
physical reads 196,866 per statement against 0;
IPC 1.44 against 2.38. PostgreSQL's own cost model ranks these two plans the wrong way round by
3.34x, and section 4 pins that to how the join-qual SubPlan is charged — 61,385 executions are
charged at ≈112.98 each in the nested loop and at roughly 0.14 each in the hash join, for work
that both actual plans confirm is identical (`loops=61385` in both).

**`F_units` = 4.9209x — CUBRID parallelises, PostgreSQL cannot.**
`U_C` 4.92437 against `U_Pc` 1.00071. This is not inferred from `parallelism=6`: it is the measured
ratio of total query CPU to summed statement wall, cross-checked by `perf stat` CPUs-utilized
(4.892 / 0.972) and by TWU from actual timestamp deltas (4.6063 / 1.0081). PostgreSQL's controlled
plan is *entirely* serial — its serial tail equals its whole busy window, 4.027 s of 4.027 s — and
section 7 gives the source reason: the correlated SubPlan is parallel-restricted, so the joinrel
has no partial path, and the outer `part` scan cannot be parallelised under a nested loop whose
inner is parameterised. CUBRID runs the same `part` scan at 5 workers.

**`F_cpu` = 1.3667x — CUBRID uses 27% less total query CPU**, decomposed as
`F_work` 0.535303x × `F_cost` 1.366905x.

*`F_work` (1.8681x fewer executor tuple reads)* is almost entirely the subquery memo. Band by band:
the `part` heap band is 2,000,000 rows on both sides — exact parity, both engines scan the whole
table because neither has an index on `(p_brand, p_container)`. The outer lineitem index band is
61,385 on both sides. The **subquery band is 61,385 rows on CUBRID against 1,903,163 on
PostgreSQL — 31.0x** — because CUBRID executes the subquery 2,044 times and PostgreSQL 61,385
times. 2,044 is exactly the number of distinct qualifying `p_partkey` values
(`q17-groundtruth-pg.out`: `parts_matching_sargs|2044`), which is the strongest possible
confirmation that the memo key is the correlation value and that it hits on every repeat.

*`F_cost` (1.3669x more CPU per tuple read)* is CUBRID's per-row overhead, and because the plan
shape is controlled away this is the cleanest denominator this campaign has had for it: 338.69 ns
against 247.78 ns per executor tuple read, both engines warm with zero physical reads. Section 6
attributes it: attribute materialisation and value lifecycle 2.84x per tuple, predicate evaluation
1.72x per part row, partially offset by CUBRID's 5.8x *lower* buffer-management cost.

**Direct A/B on the memo itself.** `max_subquery_cache_size` carries `PRM_USER_CHANGE`, so the
cache can be switched off in-session. Same engine, same plan, same warm state:

| `max_subquery_cache_size` | wall | subquery band | `SUBQUERY_CACHE` |
|---|---|---|---|
| 2 MB (contract default) | **0.161 s** | 31 ms | hit 118,682 / miss 4,088, `enabled` |
| 0 (cache off) | **0.784 s** | 645 ms | absent |
| 16 MB | 0.161 s | 32 ms | hit 118,682 / miss 4,088, `enabled` |

The memo is worth **4.87x** on CUBRID's Q17 (0.784 → 0.161 s), and the subquery band alone moves
20.8x (645 → 31 ms). Raising the budget 8x changes nothing, so the default is not binding. Note
that even with the memo disabled CUBRID (0.784 s) still beats PostgreSQL's controlled plan
(0.982 s) and its native plan (8.755 s) — the memo explains most of `F_work` but none of `F_plan`
or `F_units`.

**Explanations considered and rejected**, with the number that rejected each:

1. *"CUBRID's subquery cache is about to overflow: the trace reports `size: 1980048` against a
   2 MB budget, i.e. 94.4% full at only 2,044 keys, so Q17 sits on a cliff edge
   (`subquery_cache.c:378-383` disables the cache permanently on the first entry that does not
   fit)."* **Rejected by measurement.** A probe with the identical shape and 4,051 distinct keys
   still reported `status: enabled` at the 2 MB default, and a probe with **16,030** distinct keys
   — 7.8x Q17's — also retained every key (`miss: 32060` = 2 × 16,030) with `status: enabled`.
   Both probes reported a `size` (2,445,672 and 5,224,800) *larger than the 2 MB budget they ran
   under*, and a run at an explicit budget of 1,500,000 bytes reported `size: 1539408` and stayed
   enabled. The traced `size` therefore is not the quantity compared at `subquery_cache.c:378`,
   the cliff is nowhere near Q17, and no candidate is raised. The hypothesis was quantitatively
   attractive and wrong.
2. *"CUBRID takes zero page fetches, so the part scan is served from some higher-level cache."*
   **Rejected by measurement.** `statdump` deltas around the 0.59 s block read as exactly 0 for
   both `Num_data_page_fetches` and `Num_data_page_ioreads`, but a delta taken around a single
   execution with adequate flush latency shows **+161,531 fetches** and +1 ioread. The zero was a
   statistics-flush-latency artifact of sampling a sub-second window, not a fetch-free scan.
3. *"PostgreSQL's disadvantage is buffer-management cost (IMP-013's mechanism, reversed)."*
   **Rejected as the primary cause.** PostgreSQL's buffer band is indeed 5.8x CUBRID's
   (0.37327 against 0.06413 core-s), but that is 0.309 core-s inside a controlled pair whose total
   CPU gap is only 0.264 core-s in CUBRID's favour, and it explains none of the 8.9x `F_plan`.
   It is reported in section 6 as a counter-example rather than as support.
4. *"The `sel 0.1` placeholder for `l_quantity < (subquery)` misleads CUBRID's optimizer."*
   **Rejected by measurement.** CUBRID's estimate of the join output is 5,975 against a true 5,526
   — a 8.1% error — and it selected the optimal plan. The placeholder is real
   (`query_planner.c:10624`) but costs nothing on Q17.
5. *"CUBRID wins because PostgreSQL's working set does not fit `shared_buffers`."* **Rejected as a
   separable factor.** The 196,866 physical reads per statement are real, but they occur only in
   the plan PostgreSQL chose; the controlled plan takes zero. The effect is therefore inside
   `F_plan` and is not an independent buffer-budget finding — the configured-equal 8192 MB budget
   is adequate for the plan PostgreSQL declined to use.

Effects are not summed: `F_plan`, `F_units` and `F_cpu` multiply, and `F_work`/`F_cost` are a
decomposition of `F_cpu` alone. The buffer band and the physical reads are named once each, in the
factor that owns them.

## 9. Improvements

**No new IMP ID is allocated for Q17.** The registry was synced and searched by title, CUBRID
source location, PostgreSQL source location and root cause before any decision; every measured
CUBRID-side effect on Q17 matches an existing root cause, so per SSOT section 18 the existing
entries receive Q17 relations and evidence instead of a duplicate ID. `next_id` remains `IMP-024`.

Q17 is a query CUBRID wins by 59.97x, so its contribution to the registry is unusual: it supplies
the campaign's **cleanest plan-shape-controlled denominator** for the two per-row cost candidates,
because both engines were driven into the same plan and both ran with zero physical reads.

| Existing candidate | Q17 relation | Evidence added | Evidence type |
|---|---|---|---|
| **IMP-020** per-row DB_VALUE materialisation | added | Band A+B 27.51% → 0.19779 core-s against PostgreSQL's 13.25% → 0.13019 core-s on a structurally identical plan; 93.2 ns vs 32.8 ns per executor tuple read (2.84x). Both sides zero physical reads, so no residency confound. | profile attribution |
| **IMP-008** generic sarg comparator | added | Band C 19.59% → 0.14084 core-s against 8.35% → 0.08205 core-s for the identical two `bpchar` sargs over the identical 2,000,000 `part` rows; 70.4 ns vs 41.0 ns per row (1.72x). `mr_cmpval_char` 4.51% + `tp_value_compare_with_error` 2.69% + `lang_fastcmp_byte` 2.72% against `bpchareq` 2.08%. | profile attribution |
| **IMP-012** parallel degree saturates below the configured cap | added | CUBRID reached 5 active units against `parallelism=6`: `U_C` 4.92437, TWU 4.6063, trace `parallel workers: 5`, `gather: buildvalue`. At a full 6 units the same CPU (0.718958 core-s) would complete in ≈0.120 s against the measured 0.146 s. | projection (upper bound; not a direct A/B — `parallelism` lacks `PRM_USER_CHANGE`, so a same-engine degree A/B could not be run in-session) |
| **IMP-005** parallel-scan trace statistics merged (k−1) times | added | Third independent depth-3 instance, and the first on the `SUBQUERY_CACHE` counters, which no prior query exercised. Exactly 2x on every counter, confirmed against ground truth three times: `miss` 4,088 vs 2,044 distinct keys; 8,102 vs 4,051; 32,060 vs 16,030. Also `readkeys` 20,438 vs 10,219, `filteredkeys` 16,350 vs 8,175, `rows` 122,770 vs 61,385. New consequence: the traced `size` is likewise unusable, reporting 2,445,672 and 5,224,800 under a 2 MB budget while `status: enabled`, so an operator cannot use the trace to size `max_subquery_cache_size`. | direct count against ground truth |
| **IMP-019** `qo_comp_selectivity` hardcoded fallback | added, with an explicit **zero measured effect** | Q17 hits the same function's fallback return at `query_planner.c:10624` through a different unhandled operand-class arm (`PC_ATTR` vs subquery, `:10558-10559`) than IMP-019's `PC_ATTR/PC_ATTR` TODO at `:10524`, yielding `term[0] ... (sel 0.1)`. CUBRID nonetheless chose the optimal plan and estimated the join output at 5,975 against a true 5,526. Recorded to widen the root cause's arm coverage and to bound its priority, not as new cost. | upper bound (≈0 on Q17) |
| IMP-013 buffer fix/unfix LRU surgery | **not added — counter-example** | On Q17's controlled pair PostgreSQL's buffer band is 5.8x CUBRID's (0.37327 vs 0.06413 core-s). Recorded in section 6 so the candidate's effect range is not overstated. | — |

Ranking of the Q17 relations against the measured bands: **IMP-020 first** (0.19779 core-s, the
largest single CUBRID band and 2.84x its PostgreSQL counterpart), **IMP-008 second**
(0.14084 core-s, 1.72x), **IMP-012 third** (a 0.026 s wall projection, no direct A/B available),
**IMP-005 fourth** (observability only, no wall effect), **IMP-019 last** (zero measured effect on
this query). IMP-020 and IMP-008 are disjoint bands — materialising a value versus comparing it —
so their effects add, but no claim is made about the same core-seconds twice.

The single largest engineering finding on Q17 is a **PostgreSQL** weakness, not a CUBRID one, and
it is recorded here rather than in the registry because the registry allocates CUBRID improvement
candidates: PostgreSQL executes a correlated scalar subquery 61,385 times where CUBRID executes it
2,044 times (`nodeSubplan.c:198-241` versus `fetch.c:4086-4111`), and separately cannot parallelise
any join whose qual contains that subquery (`clauses.c:931-950`, `:960-973`).

## 10. Evidence index

Format: `claim → raw file:line → formula → evidence type → SHA-256`. Paths are relative to
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q17/`. Full byte sizes and hashes for all 216
artifacts are in `raw-manifest.json`.

| Claim | Raw file | Formula / locator | Evidence type | SHA-256 |
|---|---|---|---|---|
| Preflight all gates PASS, `ssot_drift=NONE`, 8FK/8idx, 0 off-cpuset | `q17-preflight.txt` | whole file | direct capture | `b3c82294…f8457` |
| `result-equivalent-at-SF10`, 1 row | `q17-correctness.json` | `result.status` | direct A/B | `f6db5f63…96c0b` |
| CUBRID estimated plan is a part-driven idx-join, `term[0] sel 0.1` | `q17-plan-est-cubrid.out` | `Query plan:` block | direct capture | `34bc968e…1a049` |
| PostgreSQL estimated plan is a lineitem-driven hash join, cost 1,933,196 | `q17-plan-est-pg.out` | `Hash Join (cost=49711.16..1933195.71)` | direct capture | `7efb7040…2b1b2` |
| PostgreSQL costs the winning nested loop at 6,466,108 (3.34x the hash join) | `q17-plan-est-pg-nohashjoin.out` | `Nested Loop (cost=0.44..6466108.18)` | direct capture | `8061dddb…1e895` |
| Join stays in the leader even with parallel costs zeroed | `q17-plan-est-pg-parallel_forced.out` | `Gather` nested *below* `Hash Join` | direct capture | `f375339f…c0615` |
| `T_C` = 0.146000 s, three measured WARM statements | `Q17-cubrid-headline-block1.json` | `measured_times_s`, `median_s` | direct A/B | `696edc92…3f8bb` |
| `T_P` = 8.754980 s | `Q17-postgresql-headline-block1.json` | `measured_times_s`, `median_s` | direct A/B | `69724650…cc146` |
| `T_Pc` = 0.981877 s (F_plan anchor) | `Q17-postgresql-nlj-headline-block1.json` | `measured_times_s`, `median_s` | direct A/B | `59528802…4155` |
| `U_C` = 4.92437, executor 2.90 / aux 0.03 core-s | `Q17-cubrid-headline-telemetry.json` | `utilization.U_core_s_per_wall_s`, `cpu.*` | per-TID sampler | `6a192b46…16a6` |
| `U_P` = 1.09132, io-worker aux 3.32 core-s | `Q17-postgresql-headline-telemetry.json` | same | per-TID sampler | `3fb7ea1f…a39fc` |
| `U_Pc` = 1.00071, serial tail = whole busy window | `Q17-postgresql-nlj-headline-telemetry.json` | `units.serial_tail_s` vs `units.busy_window_s` | per-TID sampler | `f52470c8…b514` |
| CUBRID `ioread: 0`, `parallel workers: 5`, `SUBQUERY_CACHE hit 118682 / miss 4088` | `q17-trace-cubrid.out` | trace body | direct capture | `a6066e67…f7548` |
| PostgreSQL `SubPlan loops=61385`, `read=196866`, rows 5,526 | `q17-plan-act-pg.out` | `SubPlan expr_1 … loops=61385`; `Buffers: shared hit=3059341 read=196866` | direct capture | `c750671f…bceb0` |
| Controlled plan: `loops=61385`, `Index Searches: 2044`, zero physical reads | `q17-plan-act-pg-nlj.out` | `Buffers: shared hit=2198652` | direct capture | `b4d55883…66ab` |
| Ground truth 2,044 parts / 61,385 rows / 5,526 qualifying / 30 per part | `q17-groundtruth-pg.out` | five `COUNT(*)` probes | direct count | `6e69d36d…1aa4e` |
| Same ground truth from the other engine | `q17-groundtruth-cubrid.out` | same five probes | direct count | `653e4f9b…90ca8` |
| CUBRID profile bands, 0 lost samples, 0 unresolved symbols | `profile-cubrid-flat.txt` | symbol lines ≥0.3% | profile attribution | `0b73e335…cfc6d` |
| PostgreSQL controlled profile bands | `profile-pg-nlj-flat.txt` | symbol lines ≥0.3% | profile attribution | `90d57cb3…0277` |
| PostgreSQL native profile, `tts_buffer_heap_getsomeattrs` 24.22% | `profile-pg-flat.txt` | symbol lines ≥0.3% | profile attribution | `7a304827…d1498` |
| CUBRID 4.892 CPUs utilized, IPC 2.29 | `perf-stat-cubrid.txt` | `perf stat` output | direct capture | `f7585533…9ed9e` |
| PostgreSQL 1.001 CPUs utilized, IPC 1.44 | `perf-stat-pg.txt` | `perf stat` output | direct capture | `d9772108…a7577` |
| PostgreSQL controlled 0.972 CPUs utilized, IPC 2.38 | `perf-stat-pg-nlj.txt` | `perf stat` output | direct capture | `83edb5d3…57043` |
| Memo A/B: 0.161 s with cache | `q17-sqcache-2M.out` | `1 row selected. (0.161000 sec)` | direct A/B | `cb04b009…cdc09` |
| Memo A/B: 0.784 s without cache | `q17-sqcache-0.out` | `1 row selected. (0.784000 sec)` | direct A/B | `8296ccd6…a4ee` |
| Memo A/B: 8x budget changes nothing | `q17-sqcache-16M.out` | `1 row selected. (0.161000 sec)` | direct A/B | `eadc080f…4d18e` |
| Rejected hypothesis 1: cache holds 4,051 keys at 2 MB | `q17-cliff-2M.out` | `miss: 8102 … status: enabled` | direct A/B | `eb7ee36e…1035` |
| Rejected hypothesis 1: cache holds 16,030 keys at 2 MB | `q17-capacity-2M.out` | `miss: 32060 … status: enabled` | direct A/B | `072fec10…5cb0d` |
| Rejected hypothesis 1: traced `size` exceeds an explicit 1,500,000 B budget | `q17-sqcache-1500000.out` | `size: 1539408 … status: enabled` | direct A/B | `262ba2e0…8a90` |
| Cliff-probe key counts (2,044 / 4,051 / 16,030) | `q17-cache-cliff-cardinality.txt` | grouped counts | direct count | `5fcc42d5…65c1` |
| WARM gate parameters derived by moving-block bootstrap | `q17-warm-gate-params.txt` | whole file | derived statistic | `ff5b409b…c8197` |
| 200-statement CUBRID stationarity probe | `q17-longprobe-cubrid.out` | parsed statement times | direct capture | `c075d7d8…d5c25` |
| Causal card inputs, factors and residual | `q17-causal-card.txt` | whole file | derived calculation | `499a63c9…46e0` |
| WARM physical-read evidence and CPU buckets | `q17-warm-and-io.txt` | whole file | derived calculation | `cecf79c2…5cc6` |
| Block-to-block stability, CUBRID | `Q17-cubrid-headline-block2.json`, `…block3.json` | `median_s` | direct A/B | `2b05ef31…2e5d`, `dae8a919…1d79` |
| Block-to-block stability, PostgreSQL | `Q17-postgresql-headline-block2.json`, `…block3.json` | `median_s` | direct A/B | `686b39fd…a2d9`, `da27e3db…d995f` |
| Load gate CLEAN during each accepted block | `Q17-cubrid-bgload-block1.json`, `Q17-postgresql-bgload-block1.json`, `Q17-postgresql-nlj-bgload-block1.json` | `verdict`, `external_max` | direct capture | `be245dc3…3e55`, `7d6ec935…f442`, `781b1a7e…0932` |
| WARM convergence per block | `Q17-cubrid-warm-block1.json`, `Q17-postgresql-warm-block1.json` | `converged`, `verdict` | derived statistic | `590497bf…317a`, `510154c5…0bb5` |

## 11. Notion sync

Not performed by this session, by contract. SSOT section 21 execution boundary: the GJC/tmux
worker session runs on the remote build host, has no Notion connector, and **must never attempt a
Notion write**; its Notion-adjacent duty ends at committing and pushing this report, the raw
manifest and the improvement registry to `origin/main`. All Notion mirroring — operational-state
page, the Q01–Q22 database row for Q17, improvement relations and any backfill catch-up — is
performed only by a dedicated subagent with Notion tool access, reading the pushed GitHub commit
as source of truth.

Status: **pending reconciler subagent**. No `reports/notion_backfill_pending.jsonl` record was
written by this session either, since that file is the third write path of the same section 21
sequence and is likewise owned by the Notion-capable subagent.

## 12. Completion checklist

- [x] Preflight recorded: identity, schema, ownership, NUMA/cpuset, statistics, parallel/buffer
      contract, query provenance — all PASS, `ssot_drift=NONE`
- [x] Correctness status recorded: `result-equivalent-at-SF10`, not censored
- [x] Estimated plans captured without execution, both engines (stage 14.3)
- [x] CUBRID WARM + 3 measured headline statements (stage 14.4); WARM proved, gate parameters derived
- [x] PostgreSQL WARM + 3 measured headline statements (stage 14.5)
- [x] Three valid headline values exist for each engine; both engines completed, no censoring
- [x] Actual plans and CUBRID trace captured in separate non-headline runs (stage 14.6)
- [x] CPU/thread, `/proc` I/O, device I/O, NUMA and buffer diagnostics (stage 14.7)
- [x] Separate perf cycles/instructions/call-graph runs, verified PID sets, 0 lost samples,
      0 unresolved symbols, coverage validated against `perf stat` (stage 14.8)
- [x] CUBRID and PostgreSQL `file:line` source contrast with searched paths/symbols for the
      absence claims (stage 14.9)
- [x] Causal multiplier decomposition with numeric `F_plan` anchored on a same-engine A/B,
      residual and error budget stated, `U` cross-checked by two independent instruments (stage 14.10)
- [x] Improvement registry synced and deduplicated; no duplicate ID allocated; five existing
      candidates given Q17 relations and evidence; one explicit counter-example recorded (stage 14.11)
- [x] Every claim indexed to raw evidence and SHA-256; `raw-manifest.json` written for 216 artifacts
- [x] Report, manifest and registry committed and pushed to `origin/main` (stage 14.12)
- [x] Notion sync deliberately **not** attempted — section 21 execution boundary; left to the
      reconciler subagent
- [x] `QUERY_COMPLETE` emitted (stage 14.13)
- [ ] Current GJC session removed and absence verified (stage 14.14) — performed by the controlling
      session after `QUERY_COMPLETE`, since a session cannot verify its own absence
