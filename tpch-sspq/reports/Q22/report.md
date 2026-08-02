# TPCH-SSPQ FK campaign — Q22 report

TPC-H Query 22, Global Sales Opportunity.

## 1. Identity

| Field | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q22 |
| SSOT commit (session pin) | `c6b037f7bd7b4cc1a656bc0cfabad0d81de63e9d` |
| SSOT blob SHA | `510478846bff081d3223d3835069283a7cd2e47b` |
| GJC session ID | `gajae_code_msbqesrv_8od37q3s` |
| Raw root | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q22` |
| Engine block order | Q22 is even → PostgreSQL block first, then CUBRID (SSOT section 12) |
| Scale | TPC-H SF10, histogram-enabled controlled comparison |

| Engine | Source SHA | Install prefix | Binary SHA-256 | ELF Build ID |
|---|---|---|---|---|
| CUBRID | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9` | `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` | `4df41ee21300bf617bccd5e1d5c8522b074ef86e` |
| PostgreSQL | `5713b437abed7085e7d59849c6e9e0f4f469633d` | `/home/cubrid/pg/pg20devel-5713b437` | `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` | `5f2cb2987765c612638c278f85cfc85c211fffe1` |

Both running binaries were resolved through `/proc/<pid>/exe` and their SHA-256 matched the frozen
`reports/bootstrap/build-manifest.json` (`frozen: true`), before and after the mid-query CUBRID
server restart described in section 5-a.

**SSOT pin versus repository HEAD.** `HEAD`, `origin/main` and the session pin were all
`c6b037f7bd7b4cc1a656bc0cfabad0d81de63e9d` for the whole query, and
`git rev-parse HEAD:tpch-sspq/SSOT.md` at that commit is
**`510478846bff081d3223d3835069283a7cd2e47b`**, byte-identical to the pinned blob. `ssot_drift=NONE`
on the preflight, the post-remediation preflight and the postflight. No pull, branch switch or SSOT
edit occurred during the query.

**Preflight (stage 14.1)** — `q22-preflight.txt`, captured 2026-08-02T20:44:39+09:00:

- branch `main`, `HEAD == origin/main == c6b037f`, `git status --porcelain -- tpch-sspq` empty,
  `ssot_drift=NONE`.
- cpuset: 30 engine TIDs (cub_master 2, cub_server 20, postmaster 1, pg children 7),
  **0 off-cpuset** → PASS. External SUT-set load 0.292 core-s/s against the 6.0 threshold.
  *This gate passed and was still not sufficient — see section 5-a.*
- Ownership gate `OK` on both engines: `cub_master` pid 1433697 on port 1523, `cub_server`
  pid 2646189, postmaster pid 1433696 on port 5442, all campaign-owned, all resolved through
  `/proc/<pid>/exe`.
- Schema contract: CUBRID 8 FK-owned B-trees, PostgreSQL 8 FKs / 8 `idx_fk_*` / 8 `convalidated`,
  exact child-column order including composite `fk_lineitem_partsupp (l_partkey, l_suppkey)`.
- Row counts identical on both engines (customer 1,500,000; orders 15,000,000; lineitem 59,986,052).
- Statistics: CUBRID `update_statistics_update_histogram=y`, `default_histogram_bucket_count=300`;
  PostgreSQL `default_statistics_target=100`. The four columns Q22 touches all carry 101 histogram
  bucket boundaries on the PostgreSQL side (`customer.c_phone`, `customer.c_acctbal`,
  `customer.c_custkey`, `orders.o_custkey`). `pg_stat_user_tables.last_analyze` reads `never` because
  `pg_stat` was reset on 2026-07-31T17:43:10+09:00, after the bootstrap `ANALYZE` of
  2026-07-30T17:54; `pg_class.reltuples` and `pg_stats` are populated, so the statistics themselves
  are intact. Q21 recorded the same `never`.
- Parallel/buffer contract: CUBRID `parallelism=6`, `max_parallel_workers=100`,
  `data_buffer_size=8.0G`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`,
  `parallel_leader_participation=on`, `shared_buffers=8192MB`, `dynamic_shared_memory_type=mmap`,
  `statement_timeout=300000 ms`, `jit=off`. Labels: **configured node/gather-cap comparison**,
  **configured-equal buffer budget**.
- Query provenance: `queries/q22-cubrid.sql`, `queries/q22-pg.sql` and the canonical
  `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q22.sql` all SHA-256
  `c3a2d47181a287370a7377fe1396d1b4fe3b252d901d60de3ee042e62440eec6`. `queries/diff/q22.diff` is
  **0 bytes** and `cmp` confirms the two dialect files are byte-identical: **Q22 has zero dialect
  changes**. No hint, no join reordering, no subquery rewrite, no extra predicate, no semantic cast.

**Post-remediation preflight** — `q22-preflight-postremediation.txt`, captured after the server
restart of section 5-a: `ssot_drift=NONE`, ownership `OK`, **136 engine TIDs, 0 off-cpuset**,
external load 0.294 core-s/s, 8 FK / 8 `idx_fk_*` / 8 `convalidated`, every contracted parameter
unchanged, query SHA-256 unchanged.

**Postflight** — `q22-postflight.txt`: this is the capture that **failed**, with
`TOTAL engine tids=32 off_cpuset=2 -> FAIL`, and it is what triggered the full re-measurement.
Section 5-a documents the cause, the remediation and the scope.

## 2. Correctness

`result-equivalent-at-SF10`, 7 rows, `ordered=True` (`q22-correctness.json`, re-run under the
affinity guard after remediation and accepted on the first attempt).

Q22 has an `ORDER BY cntrycode`, so the ordered result sequence was compared exactly, subject only
to the SSOT section 11 decimal rule. Both engines return the same 7 rows in the same order:

| cntrycode | numcust | totacctbal |
|---|---|---|
| 13 | 9025 | 67592468.28 |
| 17 | 9067 | 68084663.34 |
| 18 | 9210 | 69312783.61 |
| 23 | 8984 | 67607771.32 |
| 29 | 9199 | 69015438.26 |
| 30 | 9343 | 70118838.04 |
| 31 | 9086 | 68144525.38 |

`sum(numcust) = 63,914`, which the independent ground-truth probe reproduces exactly as `gt5`
(section 8-b). Text, integers, NULLs, row count and row multiset match exactly; raw decimal text is
preserved on both sides; no tolerance was needed for any of the 21 values. Censoring: **none**
(both engines complete in about 1 second, three orders of magnitude inside the 300 s timeout).

**One representational difference is worth recording because it is not noise — it is the mechanism
behind IMP-030.** The uncorrelated `avg(c_acctbal)` threshold prints as
`4998.1529609771174720` on PostgreSQL and `4.998152960977117e+03` on CUBRID, because
`avg(numeric)` returns **numeric** on PostgreSQL and **DOUBLE** on CUBRID. Under the SSOT decimal
rule these agree: `|a-b| = 4.720e-13 ≤ 1e-12 × max(1,|a|,|b|) = 4.998e-9`. The values agree, the
types do not, and the type difference is what forces CUBRID's per-row `NUMERIC → double` coercion
measured in section 8-c.

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
1.810078x = 1.0000x [plan] × 0.407931x [units] × 4.437218x [CPU-sec]

4.437218x [CPU-sec] = 1.000000x [work] × 4.437218x [cost]
```

**Q22 is the first query of the campaign on which the two engines execute the same plan shape over
identical logical work, so `F_plan` is `1.0000` by structural equality and there is no anchor and no
controlled denominator anywhere in the card.** SSOT section 16 permits a numeric `F_plan=1.0000`
"only when structural equality or direct controlled evidence proves it". The structural equality is
proved item by item in section 4-a: both engines scan `customer` twice, both evaluate the `avg`
subquery exactly once, both resolve the `NOT EXISTS` with 190,691 index probes on the FK index over
`o_custkey`, and both finish with a sort-based group-by over 7 groups. `F_units` and `F_cpu` are
therefore computed on the **native cross-engine pair**:

```text
R_wall = T_C/T_P = (T_C/T_P) with F_plan = 1
                    F_units × F_cpu
```

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `R_wall` | 1.810078x | wall seconds | median of 3 measured WARM statements, block 1 | `T_C / T_P` | `Q22-cubrid-headline-block1.json`, `Q22-postgresql-headline-block1.json` | direct A/B |
| `F_plan` | 1.0000x | plan shape | — (no anchor; structural equality) | asserted equal, proved in section 4-a | `q22-plan-est-cubrid.out`, `q22-plan-est-pg.out`, `q22-plan-act-pg.out`, `q22-trace-cubrid.out` | structural equality (two plans + two execution instruments) |
| `F_units` | 0.407931x | core-seconds per wall-second | total query CPU over the 4-statement block ÷ sum of that block's statement walls | `U_P / U_C` | `Q22-postgresql-headline-telemetry.json`, `Q22-cubrid-headline-telemetry.json` | per-TID sampler, actual timestamp deltas |
| `F_cpu` | 4.437218x | total query CPU-seconds | per measured statement, `U × t` | `CPU_C / CPU_P` | same two telemetry artifacts | per-TID sampler |
| `F_work` | 1.000000x | customer rows to which the row predicate is applied (3,000,000 per statement, both engines) | one measured statement | `W_C / W_P` | `q22-groundtruth.json`, `q22-trace-cubrid.out`, `q22-plan-act-pg.out` | direct count (three independent instruments) |
| `F_work` (second event) | 1.000000x | anti-join index probes (190,691, both engines) | one measured statement | `W2_C / W2_P` | CUBRID `readkeys: 190691`, PostgreSQL `Index Searches: 190691`, ground truth `gt4` | direct count (three independent instruments) |
| `F_cost` | 4.437218x | core-seconds per row predicate evaluation | same | `(CPU_C/W_C)/(CPU_P/W_P)` | derived, `q22-causal-card.txt` | profile attribution + direct A/B band series |

Measured inputs (`q22-causal-card.txt`, `q22-causal-card.json`):

| Quantity | Value |
|---|---|
| `T_C` CUBRID median | 1.101000 s |
| `T_P` PostgreSQL median | 0.608261 s |
| `U_C` | 4.95333 core-s/wall-s |
| `U_P` | 2.02062 core-s/wall-s |
| `CPU_C = U_C·T_C` | 5.453622 core-s |
| `CPU_P = U_P·T_P` | 1.229063 core-s |
| `TWU_C` / `TWU_P` | 4.9148 / 2.1025 |
| peak simultaneous units C / P | 5.7194 / 5.3677 |
| serial tail C / P | 0.0 / 0.0 s |
| `W` row predicate evaluations, both engines | 3,000,000 |
| `W2` anti-join index probes, both engines | 190,691 |
| CPU per row predicate evaluation | CUBRID 1.8179 µs, PostgreSQL 0.4097 µs |

**Reading the card in words.** PostgreSQL finishes Q22 in **1/1.810078** of CUBRID's wall, i.e.
**1.8101x faster**, the narrowest cross-engine gap of any query in the campaign so far. The
decomposition is unusually clean because two of the four factors are exactly 1: the plans are the
same shape and the logical work is *identical to the row*. What is left is a straight fight between
utilisation and CPU efficiency, and **the two engines win one each**:

- `F_units = 0.407931` is **below 1**, meaning CUBRID sustains **2.45x more parallel units** than
  PostgreSQL on this query — 4.95333 against 2.02062. That is not a CUBRID achievement so much as a
  PostgreSQL shortfall: PostgreSQL launches 4 of 4 planned workers for the cheap `avg` InitPlan and
  then only **1 of 4** for the expensive main pipeline, reproducibly, in 16 of 16 observed
  executions (section 5-c).
- `F_cpu = 4.437218` is the whole story on the other side: CUBRID burns **4.44x the CPU-seconds**
  for the same 3,000,000 row evaluations and the same 190,691 index probes. Per row evaluation that
  is 1.8179 µs against 0.4097 µs.

So **PostgreSQL wins Q22 by 1.81x while running the dominant pipeline at 2 units against CUBRID's
5.** If PostgreSQL had launched the workers it planned, the gap would be larger, not smaller.
Because `F_work` is exactly 1, `F_cost` carries all of `F_cpu`, and section 8 attributes it to named
bands measured by direct same-SQL A/B rather than by profile share alone.

**Reconstruction residual: +0.0000%.** As on Q17–Q21 this must be read honestly: with `F_plan` set
to 1 and `F_units × F_cpu = (U_P/U_C) × (U_C·T_C)/(U_P·T_P)`, the product telescopes to `T_C/T_P` by
construction, so the residual tests arithmetic, not independence. The card's genuine validation is
that its only non-wall input, `U`, is confirmed by instruments the card does not use:

| Configuration | sampler `U` (block) | TWU (block) | `perf stat` CPUs utilized | agreement | peak units | serial tail |
|---|---|---|---|---|---|---|
| CUBRID | 4.95333 | 4.9148 | 4.991 | **+0.76%** | 5.7194 | 0.0 s |
| PostgreSQL | 2.02062 | 2.1025 | see section 5-d | **−21.5% (sampler undercounts)** | 5.3677 | 0.0 s |

CUBRID's three instruments agree to within 0.76% (sampler vs `perf stat`) and 0.75% (sampler vs
TWU). **PostgreSQL's sampler `U` is measurably low, and section 5-d quantifies it with a
dual-instrument experiment rather than an argument**: over one section 12 block, `perf stat`
attached to the postmaster measured 6.85546 core-s where the sampler measured 5.38 core-s, a 27.4%
undercount, because PostgreSQL's parallel workers are separate processes that live 0.16–0.44 s and a
25 ms `/proc` sampler loses their discovery latency and their final CPU delta at exit. CUBRID has no
such exposure: its query workers are long-lived pooled threads inside one process.

`R_wall`, `F_plan` and `F_work` are unaffected by this, and `F_units × F_cpu` telescopes to
`T_C/T_P` regardless, so the correction moves only the **split**:

| | `F_units` | `F_cpu` | product |
|---|---|---|---|
| sampler (reported, campaign-consistent with Q01–Q21) | 0.407931 | 4.437218 | 1.810078 |
| `perf stat`-corrected `U_P` | 0.519806 | 3.482222 | 1.810078 |

The card reports the **sampler** values so that `F_units` and `F_cpu` stay comparable with the other
21 queries. The consequence is stated plainly: **the reported `F_cpu` is an upper bound on CUBRID's
CPU disadvantage and the reported `F_units` a lower bound on PostgreSQL's utilisation advantage.**
Every band in section 8 is measured by A/B on wall and CPU deltas within one engine, so none of them
depends on this cross-engine calibration.

### 3-b. Headline timings

All four statements of every accepted block; the first is the uncounted warm-up statement and the
last three are the measured triple. Block 1 is the headline (campaign convention since Q12); blocks
2–3 are block-to-block stability evidence. **Every block below was measured after the section 5-a
remediation and carries both a `CLEAN` load-gate verdict and a `CLEAN` all-TID affinity verdict.**

| Configuration | block 1 (measured triple) | block 2 | block 3 | block-1 median | mean | sd |
|---|---|---|---|---|---|---|
| **PostgreSQL** (headline) | 0.608261 / 0.609068 / 0.608201 | 0.616259 / 0.613193 / 0.608576 | 0.612317 / 0.610495 / 0.614189 | **0.608261 s** | 0.608510 | 0.000484 |
| **CUBRID** (headline) | 1.102 / 1.101 / 1.099 | 1.101 / 1.101 / 1.096 | 1.101 / 1.097 / 1.105 | **1.101000 s** | 1.100667 | 0.001528 |

Uncounted warm-up statements: PostgreSQL 0.639447 / 0.638039 / 0.632810, CUBRID 1.107 / 1.105 /
1.100.

| Field | Value |
|---|---|
| CUBRID median seconds | **1.101000** |
| PostgreSQL median seconds | **0.608261** |
| Median wall ratio `T_C/T_P` | **1.810078x** (PostgreSQL 1.8101x faster) |
| Correctness | `result-equivalent-at-SF10` |
| Censoring | none |

Three values are reported and the median is the headline; mean and within-block standard deviation
are given above. **No confidence interval is claimed from three values.** Block-median spread across
the three independent blocks is **0.811%** (PostgreSQL: 0.608261–0.613193) and **0.000%** (CUBRID:
1.101 on all three blocks). Recomputing `R_wall` on block 2 or block 3 gives 1.7955x and 1.7981x,
i.e. within **0.81%** of the headline. Every accepted block carries load-gate verdict `CLEAN` with
`external_max` between 1.188 and 2.897 core-s/s against the 6.0 threshold, sampled at 0.05 s
because a Q22 block is only 2.4–4.4 s of wall and the default 0.25 s period would cover it with too
few samples for the during-run half of the gate to carry information.

Output sinks are byte-stable across blocks: PostgreSQL 642 B every block
(`681f1ffa1dee65dd` / `1ec12a6c00deaeb7` / `634485588f8bc826`), CUBRID 2844 B every block
(`fe05ef8d608805c2` / `67bd458446d24dd7` / `58ae68e9d4762b70`). The two engines' sinks differ in
size only because `csql` and `psql` render the same 7 rows differently; the values are identical
(section 2). Sink hashes differ between blocks because each block writes its own timing lines into
the same sink file, which is why the content hash is computed after the headline timer stops.

### 3-c. WARM proof

**Q22 is the campaign's strongest WARM case, and the proof is positive rather than merely steady.**
The whole working set — `customer` heap (328.9 MiB / 21,049 CUBRID pages; 281 MB / 35,984 PostgreSQL
pages) plus the `o_custkey` index (120 MB on PostgreSQL) — fits the contracted 8192 MB pool on both
engines, so residency is achievable, and it was achieved:

| Evidence | CUBRID | PostgreSQL |
|---|---|---|
| `/proc` `read_bytes` delta over the block | **0** on all 3 blocks | **0** on all 3 blocks |
| engine buffer counter | trace `ioread: 0` on every scan node | `heap_blks_read` delta **0** on all 3 blocks |
| buffer hits over the block | trace `fetch: 932487` per statement, all hits | `heap_blks_hit` delta 447,249 / 447,242 / 447,258 |
| device reads | 0 | 0 |

There are **no physical reads anywhere in Q22 on either engine**, so every page fetch in section 5
is a buffer hit and the buffer-manager band in section 6 is pure hit-path overhead with no I/O
mixed in. That makes Q22 the cleanest isolation of IMP-013 in the campaign.

WARM-gate parameters were derived by measurement, not inherited (`q22-warm-gate-params.txt`).
40-statement single-connection convergence probes:

| Engine | statements | half-split trend | trailing spread | converged after | steady median |
|---|---|---|---|---|---|
| PostgreSQL | 40 | −0.2125% | 0.8433% | 12 | 0.610385 s |
| CUBRID | 40 | −0.2846% | 0.6635% | 12 | 1.102 s |

Both engines sit an order of magnitude inside the inherited tolerances (`WINDOW=4`,
`LEVEL_TOL=1.0%`, `SPREAD_SANITY=3.0%`), so **no threshold was relaxed and `WARM_STATEMENTS=12` is
each probe's measured `converged_after_statements`, not a guess**. Unlike Q21, no warm-up run was
rejected on either engine across the six accepted blocks. CUBRID has no burn-in statement at all —
statement 1 of its probe is already at the plateau — because the working set is resident before the
probe starts.

## 4. Plan

### 4-a. Structural equality, item by item

This is the evidence for `F_plan = 1.0000`. Four instruments are used: CUBRID's estimated plan
(`SET OPTIMIZATION LEVEL 514`), CUBRID's execution trace (`SET TRACE ON`), PostgreSQL's
`EXPLAIN (COSTS, VERBOSE, SETTINGS)` and PostgreSQL's
`EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, TIMING)`.

| Stage | CUBRID | PostgreSQL | Same shape? |
|---|---|---|---|
| threshold subquery | `SUBQUERY (uncorrelated)` → `SCAN (table: dba.customer)`, `readrows: 1500000`, `parallel workers: 5`, `gather: buildvalue` | `InitPlan expr_1` → `Finalize Aggregate` → `Gather` (4 launched) → `Partial Aggregate` → `Parallel Seq Scan on customer`, 1,500,000 rows | **yes** — one full parallel scan of `customer`, aggregated once |
| evaluated how often | **once** (uncorrelated subquery node) | **once** (`InitPlan`, `loops=1`) | **yes** |
| candidate scan | `SCAN (table: dba.customer)`, `readrows: 1500000`, `rows: 1500000`, `parallel workers: 5`, `gather: mergeable list` | `Parallel Seq Scan on customer`, `rows=95345.50 loops=2` + `Rows Removed by Filter: 654654 ×2` = 1,500,000 | **yes** — second full parallel scan of `customer` |
| filter predicates | `sargs: term[0] AND term[1] AND term[2]` on the scan | `Filter: c_acctbal > (InitPlan expr_1).col1 AND substring(c_phone,1,2) = ANY (...)` | **yes** |
| anti-join | `SUBQUERY (correlated)` → `SCAN (index: dba.orders.fk_orders_customer)`, `readkeys: 190691` | `Nested Loop Anti Join` → `Index Only Scan using idx_fk_orders_customer`, `Index Searches: 190691` | **same access path and same probe count**; the representation differs (see 4-b) |
| aggregation | `GROUPBY (hash: partial, sort: true, rows: 7)` | `Sort` → `Partial GroupAggregate` → `Gather Merge` → `Finalize GroupAggregate`, 7 rows | **yes** — sort-based group-by, 7 groups |
| parallelism | 5 units on both `customer` scans | 5 units on the InitPlan, 2 on the main pipeline | contracted difference, accounted in `F_units` |

The operator trees are the same modulo the parallel decoration and the sublink representation. The
parallel/serial difference is *not* counted in `F_plan`: it appears exactly once, in `F_units`, as
the measured utilisation ratio. This is the "configured node/gather-cap comparison" label of SSOT
section 9, not a claim of DOP parity.

### 4-b. The one representational difference, and why it lives in `F_cost`

PostgreSQL converts the `NOT EXISTS` sublink into a real **`Nested Loop Anti Join`** whose inner
side is an **`Index Only Scan`** with `Heap Fetches: 0` and `Output: orders.o_custkey` — the index
key alone. CUBRID keeps it as a **correlated subquery** re-executed per candidate row
(`SUBQUERY (correlated)`) whose select list is a heap column, so its index scan must also perform a
data-row lookup:

```text
CUBRID   SCAN (index: dba.orders.fk_orders_customer), (btree time: 197, fetch: 699554, ioread: 0,
                readkeys: 190691, filteredkeys: 126777, rows: 126777) (lookup time: 48, rows: 126777)
PostgreSQL  Index Only Scan using idx_fk_orders_customer on public.orders
                (actual time=0.002..0.002 rows=0.66 loops=190691)
                Heap Fetches: 0
                Index Searches: 190691
```

Both perform **190,691 index probes** — the numbers are equal, which is why `F_work = 1.0000`. What
differs is what a probe *costs*, so the difference belongs to `F_cost`, and section 8-d measures it
by direct A/B rather than asserting it. Two distinct root causes live here: the per-row subquery
representation (IMP-028, first raised on Q21) and the projection that defeats index covering
(IMP-031, new, and independently fixable — band probe B8 proves it).

### 4-c. Estimated versus actual

CUBRID's estimated plan predicts `card 1350` for the group-by output against the actual 7 rows, and
`card 13661` for the threshold subquery's scan against the actual 381,776 qualifying rows. Its
selectivity for the 7-element `IN` list is the fixed `(sel 0.01)` shown on `term[0]`, against a true
selectivity of 419,974/1,500,000 = **0.2800** — a 28x underestimate — and `(sel 0.9)` for the
`NOT EXISTS` on `term[2]` against a true 63,914/190,691 = **0.3352**. PostgreSQL's estimate is also
wrong in the same direction (`rows=2015` for the anti-join output against 31,957 per loop, and
`rows=8060` for the group-by against 7), so **neither engine's estimate is good here and neither
estimate changes the chosen plan**: both pick the same access paths anyway. No estimate error is
used as an explanation for the headline, and no selectivity improvement is proposed for Q22 —
the plans are already the same shape and the gap is entirely per-row cost.

The one estimate that *does* matter is CUBRID's term ordering, because it decides how many rows the
`NUMERIC → double` coercion runs on. The estimated plan ranks `term[1]` (the `c_acctbal` range,
`rank 2`) ahead of `term[0]` (the `IN` list, `rank 3`), so the coercion is applied to all
**1,500,000** rows of the candidate scan rather than to the 419,974 that pass the country filter.
That is recorded in IMP-030 as a contributing factor, not as a separate candidate.

## 5. Execution telemetry

### 5-a. The section 9 cpuset violation, the remediation, and the full re-measurement

**This query was measured twice.** The first pass was invalidated by a genuine SSOT section 9
violation, every artifact of it is retained under
`raw/Q22/invalid-affinity-20260802/` with `INVALID.json` and `valid=false` in the manifest, and the
whole pipeline was re-measured. The incident is reported here in full because it changes how the
campaign's affinity gate must work.

**What was found.** The stage 14.1 postflight reported
`TOTAL engine tids=32 off_cpuset=2 -> FAIL`. Two `cub_server` pooled threads named `transaction`
(TIDs 2717567 and 2729910, created 20:53:35 and 21:16:13) had `Cpus_allowed_list: 24-31` while the
contract requires `0-15`, and they had consumed 3.15 and 0.24 core-seconds there.

**What that revealed, which is much worse.** A continuous all-TID guard written to investigate
(`harness/affinity_guard.py`, new) showed that on **every** CUBRID statement, all five
`parallel-query` worker threads — the threads that actually execute the query — were being created
with affinity `24-31` and were burning **16.5–16.8 core-seconds each** outside the contracted SUT
set:

```text
Q22-cubrid-block3-affinity-a1.json  verdict OFF_CPUSET
  (2732315,'parallel-query',first_seen 12.367s, 16.59 core-s off-cpuset)
  (2732316,'parallel-query',12.367s, 16.59) (2732317,'parallel-query',12.367s, 16.61)
  (2732318,'parallel-query',12.367s, 16.73) (2732319,'parallel-query',12.367s, 16.63)
```

**Root cause, in CUBRID's source at the pinned SHA.** CUBRID rebinds its own pooled threads from an
affinity mask it caches **once, at process start**:

- `src/base/resources.cpp:190-192` — `context &effective ()` holds a **function-local static**
  whose own comment states it "must be called first in the main thread's entry point";
- `src/base/resources.cpp:204-218` — that static is initialised from `affinity_cpuset()`, i.e. the
  process's `sched_getaffinity` **at start**, and stored as `ctx.affinity.bitmap`;
- `src/base/resources.cpp:174-188` — `clearaffinity()` then calls
  `pthread_setaffinity_np (pthread_self (), ..., ctx.affinity.bitmap)` for pooled threads.

`cub_server` pid 2646189 had been started with a mask of CPUs 24-31. The campaign's later `taskset`
fixed the threads that existed at that moment — which is why the preflight legitimately reported
`0 off-cpuset` — but it could not update CUBRID's cached bitmap, so **every thread created
afterwards was bound back to 24-31**.

**Why the pre/post TID gate could not catch it.** `parallel-query` threads exist only while a
statement is running. An idle-server check before and after a block sees none of them; the postflight
caught only the two long-lived `transaction` threads that happened to survive. This is precisely the
SSOT section 24 failure mode "new pooled threads escaped cpuset → all-TID pre/post validation and
invalidation", and Q22 shows that a pre/post **pair** is not sufficient for it. `affinity_guard.py`
samples every engine TID for the whole of a stage at 0.1 s and returns `CLEAN` only if no engine TID
was ever observed outside CPUs 0-15.

**Why "reapply affinity and rerun" was not enough.** The offending threads are created *during* the
run, so reapplying beforehand cannot prevent them: three consecutive guarded attempts at CUBRID
block 3 were rejected, each with five fresh off-cpuset `parallel-query` workers
(`Q22-cubrid-block3-affinity-a{1,2,3}.json`).

**Remediation.** `cub_server` was stopped and restarted **through the mandatory wrapper**
(`.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh`, never raw
`cubrid server ...`) under `taskset -c 0-15`, so that `resources::effective()` caches the campaign
cpuset itself. The ownership gate classified the server `OK` (campaign-owned executable under the
campaign prefix) before it was touched; no non-campaign process was stopped. Verification, all
recorded:

- guard over two real parallel Q22 statements: **`CLEAN`**, 141 engine TIDs, 0 off-cpuset
  (`q22-affinity-verify-postrestart.json`);
- post-remediation preflight: **136 engine TIDs, 0 off-cpuset**, external load 0.294 core-s/s;
- identity unchanged: `cub_server` pid 2737859, `/proc/<pid>/exe` under the campaign prefix,
  SHA-256 `e5043f0e…2a13`, matching the frozen build manifest;
- contract unchanged: `parallelism=6`, `max_parallel_workers=100`, `data_buffer_size=8.0G`,
  `update_statistics_update_histogram=y`, `default_histogram_bucket_count=300`, 8 FK / 8 `idx_fk_*`
  / 8 `convalidated`, query SHA-256 identical.

**Scope of the re-measurement.** Everything CUBRID-side was invalid because every CUBRID statement
ran its workers off-cpuset; the PostgreSQL blocks additionally fail the *all-TID* gate because
off-cpuset CUBRID threads existed while they ran. Rather than argue about which measurements were
"really" affected, **all 38 stages were re-run under the guard**: both convergence probes, the
correctness gate, the estimated plans, all six headline blocks, the actual plans, the CUBRID trace,
the ground truth, both block telemetries, both perf captures and all 15 band probes. **Every one was
accepted on its first guarded attempt**, and all 51 accepted guard verdicts are `CLEAN`.

**Direction of the bias, stated because it matters.** The violation had given CUBRID 8 CPUs *beyond*
the contract, on a second NUMA node, so it flattered CUBRID. Correcting it made CUBRID **slower**:

| | invalid (pre-remediation) | valid (post-remediation) | change |
|---|---|---|---|
| CUBRID convergence-probe steady median | 1.055 s | 1.102 s | **+4.5%** |
| CUBRID block-1 median | 1.059 s | 1.101 s | **+4.0%** |
| PostgreSQL block-1 median | 0.608599 s | 0.608261 s | −0.06% |
| `R_wall` | 1.740057x | **1.810078x** | +4.0% |

The corrected headline is worse for CUBRID than the invalidated one. The profile shape did not
change (band ordering and symbol shares are within 0.5 pp), and CUBRID's anti-join band reproduced
across the two rounds to 0.5% (1.17624 → 1.18252 core-s), which is independent evidence that the
re-measurement moved the *level* and not the *mechanism*.

**Campaign-wide implication — escalated, not acted on.** Q21 was measured against the **same**
contaminated server instance: `raw/Q21/q21-preflight.txt` records `cub_server … pid=2646189`, the
process this session found bound to 24-31. Q21's CUBRID `parallel-query` workers therefore also ran
outside the contracted cpuset, and since the bias favours CUBRID, **Q21's true CUBRID time is ≥ its
reported 49.394998 s and its true `R_wall` ≥ the reported 16.020754x** — the conclusion that CUBRID
loses Q21 stands, the number does not. Q17–Q20 ran against pid 1612732, which no longer exists, so
their exposure cannot be determined retroactively from this host. Whether to re-measure completed
queries is a campaign-contract decision for the operator under SSOT section 25; this session did not
touch durable completed work.

### 5-b. CPU decomposition, units and I/O

Measured over the section 12 4-statement block with a per-TID sampler at a 25 ms nominal period,
weighted by **actual timestamp deltas** (the period is finer than the 50 ms used on long queries
because a Q22 block is only 2.4–4.4 s):

| Configuration | executor CPU | auxiliary CPU | total query CPU | sum of statement walls | `U` | TWU | peak units | serial tail |
|---|---|---|---|---|---|---|---|---|
| CUBRID | 21.730 | 0.030 | 21.760 core-s | 4.391 s | 4.95333 | 4.9148 | 5.7194 | 0.0 s |
| PostgreSQL | 5.010 | 0.000 | 5.010 core-s | 2.479 s | 2.02062 | 2.1025 | 5.3677 | 0.0 s |

Per-bucket attribution (SSOT section 15 categories):

| Engine | bucket | core-s over the block | class |
|---|---|---|---|
| CUBRID | `cub_server:parallel-query` | 21.65 | executor |
| CUBRID | `cub_server:transaction` | 0.08 | executor |
| CUBRID | `cub_server:dwb-flush-block` | 0.02 | auxiliary |
| CUBRID | `cub_server:vacuum-master` | 0.01 | auxiliary |
| PostgreSQL | `pg_backend:postgres` (leader) | 2.34 | executor |
| PostgreSQL | `pg_parallel_worker:postgres` | 2.67 | executor |

`unattributed_background` is zero on both engines: every core-second in the table is attributed to a
named PID/TID bucket. PostgreSQL's auxiliary CPU is **0.000** because there are no physical reads at
all on this query, so no `pg_io_worker` does any work — which is also why Q21's explanation for its
PostgreSQL `perf` discrepancy (io workers) does not apply here, and why section 5-d had to find the
real cause.

I/O over the block: CUBRID `/proc` `rchar` 82,976 B and `syscr` 137 across the traced statement
(`q22-trace-io-pre.txt` / `q22-trace-io-post.txt`), `read_bytes` delta **0**; PostgreSQL `rchar`
5,145,670 B, `syscr` 1,530, `read_bytes` delta **0**. Device reads are zero on every disk on both
engines. Page traffic is therefore the right I/O unit for Q22 and it is all hits: CUBRID 932,487
page fetches per statement (16 KiB pages) against PostgreSQL 683,897 buffer hits (8 KiB pages), i.e.
CUBRID moves **14.2 GiB** through its buffer manager per statement against PostgreSQL's **5.2 GiB**,
a **2.73x** byte ratio of which exactly 2x is the page-size difference.

### 5-c. PostgreSQL leaves 3 of its 5 contracted workers unused

This is the measured reason `F_units` is below 1, and it is a PostgreSQL-side fact, not a CUBRID
improvement candidate.

| Probe | `avg` InitPlan `Gather` | main `Gather Merge` | runs |
|---|---|---|---|
| native Q22, 12 `EXPLAIN ANALYZE` in one connection (`q22-pgworkers-probe.out`) | Planned 4, **Launched 4** | Planned 4, **Launched 1** | 12 / 12 |
| native Q22, 4 more runs (`q22-pgworkers-control.out`) | Planned 4, **Launched 4** | Planned 4, **Launched 1** | 4 / 4 |
| band probe B6, which has **no InitPlan** (`q22-pgworkers-control.out`) | — | `Gather` Planned 4, **Launched 4** | 4 / 4 |

The B6 control isolates the cause. Under the contracted `max_parallel_workers = 5`, the InitPlan's
four workers are evaluated first and have not been reaped by the postmaster when the main
`Gather Merge` asks for its four, so exactly one slot remains. The effect is fully reproducible —
16 of 16 native executions — and it means PostgreSQL executes the expensive part of Q22
(the 1,500,000-row candidate scan plus 190,691 index probes plus the sort) at **2 units**, while
CUBRID executes the same work at **5**. PostgreSQL still wins by 1.81x.

Recorded as required by SSOT section 9: never infer planned, launched, simultaneous or time-weighted
execution units from settings. Here the *planned* count is 4, the *launched* count is 1, the *peak
simultaneous* count is 5.3677 (during the InitPlan) and the *time-weighted* count is 2.1025 — four
different numbers, all measured, none substituted for another.

### 5-d. The per-TID sampler undercounts PostgreSQL — measured, not argued

`perf stat` over a 30 s replay window reports 4.991 CPUs utilized for CUBRID against a sampler `U`
of 4.95333 (**+0.76%**), but 2.711 for PostgreSQL against 2.02062. A replay window and a
4-statement block are different denominators, so instead of comparing those two numbers, **one
section 12 block was observed by both instruments simultaneously** (`dualinstrument.sh`,
`q22-pg-dualinstrument-perf.txt`, `q22-dualinstrument.log`):

| Instrument | attribution | CPU over the same block |
|---|---|---|
| `perf stat -p <postmaster>`, attached **before** the block's connection existed | inherit-on-fork: leader + every statement's parallel workers, nothing that pre-dates the attach | **6.85546 core-s** task-clock |
| `harness/headline_telemetry.py` per-TID sampler at 25 ms | explicit executor/auxiliary PID classification | **5.38 core-s** |

The sampler is **21.5% low** (`perf/sampler = 1.274`). The cause is structural: PostgreSQL's
parallel workers are separate processes that exist only for one `Gather` — the InitPlan's four for
about 0.157 s each and the main pipeline's one for about 0.44 s — so a 25 ms `/proc` differencing
sampler loses each worker's discovery latency and the CPU it accrues after the last sample before
exit. The arithmetic agrees: the sampler attributes 0.7675 core-s of worker CPU per statement, while
the plan's own timings imply about 1.07 core-s (4 × 0.157 + 1 × 0.44). CUBRID is unaffected because
its query workers are long-lived pooled threads inside one already-attached process, which is
exactly why its two instruments agree to 0.76%.

Effect on the card: section 3-a reports both splits. `perf` numbers are used as a
direction-and-magnitude cross-check, never as a card input, and both `perf` captures passed the
coverage validation SSOT section 15 requires — **0 unknown-symbol lines** on both engines
(CUBRID 1349 flat lines / 38,071 samples, PostgreSQL 1912 flat lines / 19,290 samples), with verified
PID attachment rather than an all-CPU profile.

## 6. Profile

Non-headline. `perf record -F 999 -g --call-graph dwarf` against verified PID sets; shares are
converted to core-seconds per statement by multiplying by that engine's measured per-statement total
query CPU from section 5-b (`q22-bands.txt`, `q22-bands.json`).

| Instrument | CUBRID | PostgreSQL |
|---|---|---|
| cycles (30 s window) | 405,865,990,101 | 227,194,434,645 |
| instructions | 865,276,709,825 | 496,748,516,379 |
| IPC | 2.13 | 2.19 |
| task-clock | 149,750.40 ms (4.991 CPUs) | 81,339.44 ms (2.711 CPUs) |
| statements in the driver | 36 | 60 |
| resolved self-cost lines | 1349, **0 unknown symbols** | 1912, **0 unknown symbols** |

**IPC is essentially equal (2.13 vs 2.19), which is the first thing the profile settles: CUBRID is
not stalling more per instruction, it is executing far more instructions for the same work.**
Normalising instructions by task-clock and multiplying by the measured per-statement CPU of section
5-b — which needs no assumption about how many statements fell inside the perf window — CUBRID
retires 5.778 G instructions per core-second × 5.453622 core-s = **31.51 G instructions per
statement**, against PostgreSQL's 6.107 × 1.229063 = **7.51 G**. That is a **4.198x instruction
ratio for byte-identical logical work**, and it independently corroborates `F_cpu = 4.437218x` to
within **5.4%** from counters the card never touches. The residual 5.4% is the IPC and clock
difference (2.13 vs 2.19 IPC, 2.710 vs 2.793 GHz).

### 6-a. CUBRID bands (per-statement total query CPU 5.45362 core-s)

| Band | self% | core-s/stmt |
|---|---|---|
| IN-list SET walk + generic value compare (IMP-029, IMP-008) | 25.03% | 1.36504 |
| per-row DB_VALUE alloc/copy/clear churn (IMP-020, IMP-029) | 23.30% | 1.27069 |
| buffer fix/unfix + LRU + buffer mutex (IMP-013, IMP-007) | 10.68% | 0.58245 |
| heap row materialisation (IMP-020) | 9.20% | 0.50173 |
| B-tree descent for the anti-join probe (IMP-028) | 3.04% | 0.16579 |
| expression fetch / regu-var dispatch (IMP-008) | 2.63% | 0.14343 |
| SUBSTRING + UTF-8 char-length scan | 2.16% | 0.11780 |
| NUMERIC → double coercion via dec-string + atof + pow (IMP-030) | 2.16% | 0.11780 |
| memmove / libc bulk copy | 1.60% | 0.08726 |
| parallel-scan slot iteration + gather | 0.61% | 0.03327 |
| per-probe subquery open/execute/teardown (IMP-028) | 0.34% | 0.01854 |
| (unbucketed resolved symbols) | 0.98% | 0.05345 |
| **total resolved** | **81.73%** | **4.45724** |

Top self-cost symbols: `mr_cmpval_string` 5.86%, `eval_pred` 3.86%, `mr_setval_string` 3.70%,
`lang_fastcmp_byte` 3.62%, `pr_clear_value` 3.52%, `tp_value_compare_with_error` 3.41%,
`heap_attrinfo_read_dbvalues` 3.16%, `mspace_malloc` 2.92%, `mspace_free` 2.86%,
`db_value_domain_init` 2.63%, `pgbuf_fix_release` 2.26%, `__pthread_mutex_lock` 2.08%.

### 6-b. PostgreSQL bands (per-statement total query CPU 1.22906 core-s)

| Band | self% | core-s/stmt |
|---|---|---|
| IN-list ScalarArrayOp + text equality | 18.03% | 0.22160 |
| bpchar→text + SUBSTRING + UTF-8 length + detoast | 17.94% | 0.22049 |
| tuple deform + heap access | 16.13% | 0.19825 |
| buffer manager (pin/lock/hash) | 8.73% | 0.10730 |
| palloc / memory context | 8.10% | 0.09955 |
| expression interpreter | 5.87% | 0.07215 |
| B-tree descent for the anti-join probe | 5.83% | 0.07165 |
| kernel page-table / mmap DSM path | 4.26% | 0.05236 |
| numeric comparison (exact, no string round-trip) | 1.80% | 0.02212 |
| nested-loop anti join + agg + sort | 0.43% | 0.00528 |
| (unbucketed resolved symbols) | 1.31% | 0.01610 |
| **total resolved** | **88.43%** | **1.08686** |

Top self-cost symbols: `tts_buffer_heap_getsomeattrs` 12.57%, `__memcmp_evex_movbe` 6.46%,
`ExecEvalScalarArrayOp` 5.62%, `texteq` 4.85%, `ExecInterpExpr` 4.75%, `pg_mblen_range` 4.31%,
`dotrim` 4.08%, `_bt_compare` 3.81%, `AllocSetAlloc` 3.11%, `LWLockAttemptLock` 2.64%.

**PostgreSQL is not free of Q22's expression cost either.** Its second-largest band, 17.94%, is
`bpchar → text` conversion plus `SUBSTRING` plus UTF-8 length scanning plus detoast — `c_phone` is
`char(15)`, so `substring(c_phone,1,2)` forces a `bpchar→text` cast that calls `rtrim` (`dotrim`
4.08%) and multibyte length walks (`pg_mblen_range` 4.31%). Both engines pay for the same
`SUBSTRING`; the difference is what happens around it.

### 6-c. The band comparison that explains the headline

| Band pair | CUBRID | PostgreSQL | ratio |
|---|---|---|---|
| IN-list evaluation | 1.36504 core-s (25.03%) | 0.22160 core-s (18.03%) | **6.16x** |
| per-row value materialisation / allocation | 1.27069 core-s (23.30%) | 0.09955 core-s (8.10%) | **12.76x** |
| heap row / tuple access | 0.50173 core-s (9.20%) | 0.19825 core-s (16.13%) | 2.53x |
| buffer manager (all hits) | 0.58245 core-s (10.68%) | 0.10730 core-s (8.73%) | 5.43x |
| B-tree descent | 0.16579 core-s (3.04%) | 0.07165 core-s (5.83%) | 2.31x |
| SUBSTRING / text handling | 0.11780 core-s (2.16%) | 0.22049 core-s (17.94%) | **0.53x** (PostgreSQL pays more) |
| numeric comparison | 0.11780 core-s (2.16%) | 0.02212 core-s (1.80%) | 5.33x |

Two bands carry the query: evaluating a **7-element constant `IN` list** and the **per-row DB_VALUE
churn it drives** are together **48.33%** of CUBRID's profiled self cost = **2.63573 core-s** of
5.45362, against PostgreSQL's 18.03% + 8.10% = 0.32115 core-s. That single comparison — 8.2x on the
combined band — is what `F_cost = 4.437218` is made of. And the one band where PostgreSQL is
*worse* (text/SUBSTRING handling, 0.53x) is the band CUBRID is efficient at, which is why the
overall gap is 1.81x rather than 4x.

## 7. Source contrast

| Item | CUBRID `file:line` | PostgreSQL `file:line` | Difference | Class |
|---|---|---|---|---|
| Constant `IN`-list membership | `src/query/query_evaluator.c:363` `for (i = 0; i < set_size (set); i++)`; `:365` `set_get_element (set, i, &elem_val)`; `:370` `eval_value_rel_cmp (...)`; `:371` `pr_clear_value (&elem_val)` | `src/backend/executor/execExprInterp.c:4122` `nitems = ArrayGetNItems(...)` (once); `:4146-4148` `fetch_att` + `att_addlength_pointer` (in place); `:4162` `fcinfo->flinfo->fn_addr(fcinfo)` (pre-resolved) | CUBRID re-reads the set length **per iteration**, materialises a **fresh DB_VALUE per element per row**, dispatches through the generic comparator, then frees it. PostgreSQL computes the length once, reads each element **in place by pointer arithmetic with no allocation**, and calls an already-resolved operator function. | same stage, lower measured cost |
| Large constant `IN` lists | no compiled or hashed representation exists; `eval_some_eval()` has no fast path | `src/backend/optimizer/util/clauses.c:2531` `#define MIN_ARRAY_SIZE_FOR_HASHED_SAOP 9`; `:2549` `convert_saop_to_hashed_saop()`; `src/backend/executor/execExprInterp.c:4257` `ExecEvalHashedScalarArrayOp()` | PostgreSQL converts a ≥9-element constant array into a hash probe **at plan time**. CUBRID has no equivalent code point. | structural absence |
| Element comparison | `src/object/object_primitive.c:11464` `mr_cmpval_string()` (5.86%) → `src/base/language_support.c:5453` `lang_fastcmp_byte()` (3.62%), reached via `src/object/object_domain.c:10404` `tp_value_compare_with_error()` (3.41%) | `src/backend/utils/adt/varlena.c` `texteq()` (4.85%) → `__memcmp_evex_movbe` (6.46%) | Both do a byte comparison; CUBRID reaches it through three levels of generic dispatch per element, PostgreSQL through one direct function pointer. | same stage, lower measured cost |
| `NUMERIC` vs threshold comparison | `src/query/numeric_opfunc.c:4039-4055` `numeric_coerce_num_to_double()`: `:4046` `numeric_coerce_num_to_dec_str()` formats to a **decimal string**, `:4051` `atof(num_string) / pow(10.0, scale)` parses it back and calls libm `pow` — **per row**; dispatched from `src/query/numeric_opfunc.c:5951` and reached from `src/object/object_domain.c:6977` `tp_value_cast_internal()` at `:7357`/`:7471` | `src/backend/utils/adt/numeric.c:2469` `numeric_gt()` → `:2529` `cmp_numerics()` → `:8054` `cmp_var_common()` | CUBRID converts an exact NUMERIC to double by **printing and re-parsing it**; PostgreSQL compares the stored digit arrays exactly. CUBRID's own comment at `:4049-4050` documents the resulting precision loss and `:4053-4054` carries a TODO referencing CBRD issue CUBRIDSUS-2637. | same stage, lower measured cost |
| Why that coercion happens at all | `avg(NUMERIC)` returns **DOUBLE** (measured: `4.998152960977117e+03`) | `avg(numeric)` returns **numeric** (measured: `pg_typeof(avg(c_acctbal)) = numeric`) | PostgreSQL's aggregate stays exact, so the row loop compares numeric-to-numeric and needs no coercion. | structural absence |
| `EXISTS` representation | `src/parser/xasl_generation.c:1685` `pt_to_regu_variable (..., UNBOX_AS_TABLE)`; `:1694-1698` `/* exists op must fetch one tuple */ XASL_SET_FLAG (..., XASL_NEED_SINGLE_TUPLE_SCAN)` | `src/backend/executor/nodeIndexonlyscan.c:63` `IndexOnlyNext()` with the visibility-map gate at `:165` `if (!VM_ALL_VISIBLE(...))` | CUBRID answers "does a row exist" by **producing a tuple**, so the subquery's select list becomes a requirement on the scan; PostgreSQL's anti-join inner side needs no columns and answers from the index (`Heap Fetches: 0`, `relallvisible/relpages = 99.978%`). | structural absence |
| Index covering for that probe | `src/optimizer/query_graph.c:6933` `qo_is_coverage_index()`, called at `:7598` `index_entryp->cover_segments = qo_is_coverage_index (...)`; the machinery is fully wired at `src/optimizer/plan_generation.c:3360` `qo_is_index_covering_scan()` and used at `src/optimizer/query_planner.c:2023`, `:2253`, `:2346` | inner side projects `orders.o_custkey` only — the index key | Nothing is missing in CUBRID's covering machinery; it is **disqualified upstream** because the `o_orderkey` segment introduced purely by the EXISTS projection is not in `fk_orders_customer`. Proved by A/B: projecting `o_custkey` instead flips the trace to `covered: true`. | same stage, lower measured cost |
| Correlated sublink → join | `src/optimizer/rewriter/query_rewrite.c:291` `/* rewrite uncorrelated subquery to join query (TODO : correlated) */`; `:246-251` the only EXISTS rewrite is `qo_add_limit_clause()` | plan: `Nested Loop Anti Join` | CUBRID has no semi-join/anti-join in its join vocabulary (IMP-028, established on Q21); the sublink stays a per-row predicate. | structural absence |
| Buffer hit path | `src/storage/page_buffer.c:2211` `pgbuf_fix_release()` (2.26%), `pgbuf_unfix` (1.01%), plus `__pthread_mutex_lock` 2.08% and `cubthread::get_entry` 1.79% | `PinBuffer` (1.60%), `LWLockAttemptLock` (2.64%), `hash_search_with_hash_value` (2.04%) | 5.43x on the band with **zero physical reads on either engine**, so this is pure hit-path overhead (IMP-013). | same stage, lower measured cost |
| Row materialisation | `src/storage/heap_file.c` `heap_attrinfo_read_dbvalues()` (3.16%) + `spage_get_record` (1.11%) + `mr_data_readval_numeric` (0.67%) | `tts_buffer_heap_getsomeattrs()` (12.57%), one symbol, no per-attribute allocation | CUBRID builds fully-typed DB_VALUEs per row (IMP-020); PostgreSQL deforms into a slot with no allocation. 2.53x. | same stage, lower measured cost |
| `SUBSTRING` on a fixed-length column | `src/query/string_opfunc.c:1739` `db_string_substring()` (0.96%) + `intl_char_size` (1.20%) = 2.16% | `text_substring` (1.70%) + `dotrim` (4.08%) + `pg_mblen_range` (4.31%) + detoast = 17.94% | **PostgreSQL is worse here**: `c_phone` is `char(15)`, so `substring(c_phone,1,2)` forces a `bpchar→text` cast that rtrims and re-walks multibyte lengths. Recorded because a source contrast must not be one-directional. | common to both engines |

**Claims of absence record what was searched.** For "no semi-join/anti-join in CUBRID's executor
vocabulary": `src/query/query_list.h:37-45` defines
`JOIN_TYPE { NO_JOIN, JOIN_INNER, JOIN_LEFT, JOIN_RIGHT, JOIN_OUTER, JOIN_CSELECT }` and a
case-insensitive search of the whole `src/` tree for `semi join` / `semijoin` / `anti join` /
`antijoin` in any spelling returns 0 matches (established on Q21, re-verified at the same SHA). For
"no compiled/hashed constant `IN` list": searched `src/query/query_evaluator.c` for any fast path in
`eval_some_eval`/`eval_pred_alsm*`, and the ALSM term structure for any cached array — the
right-hand side is always reached as a `DB_SET` through `db_get_set()` (`:2382`, `:2405`). For
"CUBRID's covering machinery is present, not absent": `qo_is_index_covering_scan` is defined at
`src/optimizer/plan_generation.c:3360`, declared at `src/optimizer/optimizer.h:204` and consumed at
three sites in `src/optimizer/query_planner.c`, and band probe B8 makes it fire on this very query.

## 8. Causal decomposition details

### 8-a. Why `F_plan` is 1.0000 and not `UNMEASURED`

SSOT section 16 allows a numeric `F_plan` only under structural equality or direct controlled
evidence. Section 4-a establishes structural equality with four instruments, and the two
representational differences that remain (the sublink form and the projection) are *cost*
differences on an identical access path with an identical probe count, not shape differences: both
engines perform 190,691 index probes into `orders` on the same FK-owned index over `o_custkey`. No
controlled A/B was needed for the card, and consequently **no controlled denominator appears in
it** — native and controlled denominators cannot be mixed here because there is only one pair.

Explicitly considered and rejected as an `F_plan` component:

- **"PostgreSQL parallelises and CUBRID does not."** Rejected by measurement: CUBRID's trace shows
  `parallel workers: 5` on *both* `customer` scans, and its `U` is 4.95333 against PostgreSQL's
  2.02062. The engine that under-parallelises Q22 is PostgreSQL (section 5-c). Parallelism appears
  once, in `F_units`.
- **"CUBRID re-evaluates the `avg` subquery per row."** Rejected by the trace: the node is
  `SUBQUERY (uncorrelated)` with a single `SCAN … readrows: 1500000`, i.e. one evaluation, matching
  PostgreSQL's `InitPlan expr_1` with `loops=1`. Had it been per-row, the scan would have reported
  1.5M × 1.5M row reads.
- **"The anti-join order differs."** Rejected: CUBRID's term ranks (`term[1]` rank 2, `term[0]` rank
  3, `term[2]` rank 10) put the `NOT EXISTS` last, exactly where PostgreSQL puts it (after the
  filter, as the anti-join's inner side). Both engines probe 190,691 times, which is the arithmetic
  confirmation.

### 8-b. `F_work = 1.0000`, confirmed on two events by three instruments

`q22-groundtruth.sql` was run **separately on both engines**, outside any plan's instrumentation.
All eight cardinalities agree exactly across engines:

| | quantity | value | reappears as |
|---|---|---|---|
| gt1 | customers total | 1,500,000 | CUBRID `readrows: 1500000` (both scans); PostgreSQL 381,776 out + 223,645×5 removed (avg branch) and 190,691 out + 654,654×2 removed (candidate branch) |
| gt2 | rows passing the cntrycode filter alone | 419,974 | band probe B2 row count on both engines |
| gt3 | the `avg` threshold | 4998.1529609771174720 | the `InitPlan` / uncorrelated subquery value |
| gt4 | **candidates reaching the anti-join** | **190,691** | CUBRID `readkeys: 190691`; PostgreSQL `Index Searches: 190691`; band probes B6/B7 row count on both engines |
| gt5 | candidates surviving the anti-join | 63,914 | `sum(numcust)` of the answer |
| gt6 | candidates rejected (they have orders) | 126,777 | CUBRID `filteredkeys: 126777`, `lookup … rows: 126777` |
| gt7 | answer groups | 7 | 7 rows returned |
| gt8 | rows the `avg` aggregates | 381,776 | PostgreSQL `rows=76355.20 loops=5` |

The card's work event is **customer rows to which the row predicate is applied**: `customer` is
scanned twice per statement on both engines, 1,500,000 rows each, so `W = 3,000,000` on both and
`F_work = 1.0000`. The second, independently measured event — anti-join index probes — gives
`F_work = 190,691/190,691 = 1.0000` as well. **Because `F_work` is exactly 1 on two different
events measured by three different instruments, the entire 4.437218x CPU gap is `F_cost`.** There is
no work-volume explanation available for Q22, which is what makes it a clean per-row-cost
comparison.

### 8-c. Measured bands, by direct same-SQL A/B

The profile bands of section 6 are attributions. The bands below are **differences of two measured
configurations**, each configuration byte-identical SQL on both engines, each run through the same
WARM gate, the same section 9 load gate and the same all-TID affinity guard as a headline block. The
series adds exactly one stage of Q22 at a time:

| Probe | what it is | CUBRID median / CPU | PostgreSQL median / CPU |
|---|---|---|---|
| B1 | `count(*)` over `customer`, no predicate | 0.000 s / — ¹ | 0.029798 s / 0.01217 core-s |
| B2 | B1 + `SUBSTRING(c_phone,1,2) IN (7 values)` | 0.365 s / 1.81002 | 0.159618 s / 0.45985 |
| B3 | exactly Q22's uncorrelated `avg` subquery | 0.404 s / 2.01375 | 0.166247 s / 0.56978 |
| B4 | the full query **without** the `NOT EXISTS` | 0.856 s / 4.24252 | 0.489537 s / 1.07547 ² |
| B5 | the full query (= the headline configuration) | 1.094 s / 5.42504 | 0.612540 s / 1.25831 ² |
| B6 | candidate selection with a **double** threshold literal (coercion on) | 0.420250 s / 2.09282 ² | 0.116501 s / 0.29408 ² |
| B7 | identical, with an **exact decimal** threshold literal (coercion off) | 0.390250 s / 1.93592 ² | 0.116048 s / 0.29087 ² |
| B8 | the full query with the `NOT EXISTS` projecting the **index key** | 1.072 s / 5.31500 | — |

¹ CUBRID answers an unqualified `count(*)` from catalog statistics without scanning (0.000 s), so B1
is not a scan baseline on CUBRID and is not used as one. B2 is the joint baseline.
² mean of 4 replicates; the sensitive pairs were replicated because a band is a difference of two
large numbers (see below).

Stage-wise CPU ratio, CUBRID / PostgreSQL, on byte-identical SQL: **B2 3.936x, B3 3.534x,
B4 3.945x, B5 4.311x**. B5 is the whole query and its 4.311x independently reproduces the card's
`F_cpu = 4.437218` from the headline blocks to within **2.8%**, using a different set of runs — a
genuine cross-check, since B5 and the headline share no measurement.

**Why the sensitive pairs were replicated.** A band is `CPU(B_n) − CPU(B_{n−1})`. On CUBRID that is
safe: `U` is 4.936–4.985 across every band probe (0.99% spread). On PostgreSQL it is not, because
`U` depends on how many workers the `Gather` actually launched, which is quantized (section 5-c);
two independent rounds of the same B4/B5 pair gave 0.0922 and 0.1921 core-s. Each sensitive probe
was therefore measured **four times** and the band is reported as a mean with the observed spread:

| Band | pair | CUBRID | PostgreSQL | ratio |
|---|---|---|---|---|
| **anti-join** | B5 − B4 | +238.0 ms wall, **+1.18252 core-s** = 6201 ns/probe | +123.003 ms wall (120.95/122.48/123.48/125.10), **+0.18284 core-s** (0.192/0.218/0.155/0.167) = 959 ns/probe | **6.467x** (replicate range 5.43–7.64x) |
| **NUMERIC→double coercion** | B6 − B7 | +30.0 ms wall (27/26/29/38), **+0.15691 core-s** (0.1513/0.1264/0.1600/0.1900), **all 4 replicates positive** = **104.60 ns/row** | +0.453 ms wall (−2.23/+1.45/+1.66/+0.93), +0.00321 core-s (−0.0346/+0.0484/−0.0067/+0.0058), **replicates straddle zero** = 2.14 ns/row | **~49x**, and PostgreSQL's is not resolvable from zero |
| **per-probe row lookup** | B5 − B8 | +22.0 ms wall, **+0.11004 core-s** = 868 ns per eliminated lookup | — (PostgreSQL already does 0 heap fetches) | — |

The coercion A/B deserves emphasis because it is the cleanest single-mechanism measurement in this
report. B6 and B7 differ **only** in how the threshold literal is written — `4998.1529609771174720e0`
(double) versus `4998.1529609771174720` (exact decimal) — and both select **exactly 190,691 rows on
both engines**, so the semantics are provably unchanged (`c_acctbal` has scale 2, so no value can
compare equal to a 20-digit threshold). CUBRID pays +7.69% wall and +8.1% CPU for writing it the
first way; PostgreSQL pays nothing measurable. **The PostgreSQL arm is the control that rules out
the alternative explanation** that the two literal forms are somehow different amounts of work.

### 8-d. Splitting the anti-join band, and what is *not* summed

The 1.18252 core-s CUBRID anti-join band contains more than one root cause, and SSOT section 18
forbids summing overlapping effects. The split:

| Component | core-s/stmt | evidence | owner |
|---|---|---|---|
| per-probe data-row lookup (126,777 lookups) | **0.11004** | B5 − B8, trace flips to `covered: true`, page fetches fall by exactly 126,777 | **IMP-031** |
| B-tree descent + per-probe subquery machinery + the rest | **1.07248** | remainder of the band; profile bands 3.04% + 0.34% | **IMP-028** |
| **total anti-join band** | **1.18252** | B5 − B4 | — |

`IMP-031 ⊂ IMP-028`: fixing IMP-028 (converting the sublink to a real anti-join) would make IMP-031
moot, because PostgreSQL's anti-join inner side needs no columns and that is exactly why it reports
`Heap Fetches: 0`. But IMP-031 is a projection choice fixable **without** any join conversion, which
makes it the strictly cheaper independent step. The two are never added together.

Likewise the 23.30% (1.27069 core-s) per-row DB_VALUE alloc/copy/clear band is **shared** between
IMP-020 (per-**row** scan-output materialisation) and IMP-029 (per-**element** materialisation inside
the IN-list loop). The profile separates the symbols that are unambiguous —
`set_get_element`/`setobj_get_element`/`set_size`/`set_tform_disk_set` belong to the IN-list loop,
`heap_attrinfo_read_dbvalues`/`spage_get_record` belong to row output — but `mspace_malloc`,
`mspace_free`, `mr_setval_string`, `pr_clear_value` and `db_value_domain_init` are called from both.
Those five symbols are 15.63% = 0.85226 core-s and are **not** attributed to either candidate
exclusively; IMP-029's effect range is stated as an interval (1.14–2.41 core-s) precisely because of
this ambiguity, rather than claiming the whole band.

### 8-e. Explanations considered and rejected, with the number that rejected them

- **"CUBRID is slower because it is not parallel."** Rejected: `U_C = 4.95333` against
  `U_P = 2.02062`. CUBRID sustains 2.45x more units. `F_units = 0.407931 < 1`.
- **"CUBRID does more I/O."** Rejected: `read_bytes` delta is **0** on both engines on all six
  blocks, `ioread: 0` on every CUBRID scan node, `heap_blks_read` delta 0 on all three PostgreSQL
  blocks. There is no physical I/O in Q22 at all. (CUBRID does move 2.73x the *bytes* through its
  buffer manager, 14.2 vs 5.2 GiB, of which exactly 2x is the 16 KiB vs 8 KiB page size — that is
  counted in the buffer band, not as I/O.)
- **"CUBRID reads more rows / does more work."** Rejected: `F_work = 1.0000` on two independent
  events, confirmed by three instruments (section 8-b).
- **"CUBRID's plan is worse."** Rejected: same shape on four instruments, same access path, same
  190,691 probes (section 4-a).
- **"CUBRID stalls more (memory-bound)."** Rejected: IPC 2.13 against 2.19, a 2.7% difference.
  CUBRID retires 2.9x the instructions per statement; the gap is instruction count, not stall.
- **"It is the `SUBSTRING`."** Rejected, and in the opposite direction: CUBRID's SUBSTRING band is
  2.16% (0.11780 core-s) against PostgreSQL's 17.94% (0.22049 core-s). PostgreSQL pays *more* for
  the substring because `c_phone` is `char(15)` and the cast rtrims.
- **"It is the numeric coercion."** Rejected as the *main* explanation, though it is real: measured
  at 0.15691 core-s = 2.88% of CUBRID's 5.453622 core-s. Kept as IMP-030, ranked #2.
- **"It is the anti-join."** Rejected as the main explanation: the whole band is 1.18252 core-s =
  21.7% of CUBRID's CPU, and even removing it entirely would leave 4.27 core-s against
  PostgreSQL's 1.23.
- **"It is the estimate errors."** Rejected: both engines mis-estimate (CUBRID 28x low on the `IN`
  selectivity, PostgreSQL 16x low on the anti-join output) and neither mis-estimate changes the
  chosen plan.

What survives is the per-row expression machinery: **48.33% of CUBRID's Q22 CPU is spent walking a
7-element constant `IN` list through the generic collection and DB_VALUE APIs**, against 26.13% for
PostgreSQL's compiled equivalent plus its allocator. That is IMP-029, ranked #1.

## 9. Improvements

Three new IDs allocated (`IMP-029`, `IMP-030`, `IMP-031`; `next_id` → `IMP-032`) and four existing
root causes reused with Q22 relations and new evidence. The dedup search and the reasoning for every
allocation are recorded in `reports/improvement-registry.json` under `q22_allocation_note`.

### Ranking

| # | ID | root cause | measured effect on Q22 | priority | difficulty |
|---|---|---|---|---|---|
| 1 | **IMP-029** | constant `IN`-list evaluated per row by walking a generic `DB_SET`, materialising and freeing a DB_VALUE per element per row | 25.03% self = 1.36504 core-s, plus the shared 23.30% churn band; recoverable interval **1.14–2.41 core-s of 5.45362** (21–44%) | P0 | medium |
| 2 | **IMP-030** | `NUMERIC → double` coercion implemented as decimal-string + `atof` + `pow`, forced into the row loop because `avg(NUMERIC)` returns DOUBLE | **0.15691 core-s** (2.88%), 104.60 ns/row, 4/4 replicates positive; ~49x PostgreSQL's | P1 | low |
| 3 | **IMP-031** | `EXISTS` compiled as "produce a tuple", so the probe projects a heap column and the covering index is disqualified | **0.11004 core-s** (2.02%), 868 ns per eliminated lookup, 126,777 lookups removed, trace `covered: true` | P1 | medium |

The ranking is justified against the measured bands: IMP-029 is an order of magnitude larger than
either other candidate, acts on all 3,000,000 row evaluations rather than a sub-population, and its
band ratio (6.16x) is the closest of the three to the whole-query `F_cost` of 4.437218x — i.e. it is
the band that actually explains the headline. IMP-030 outranks IMP-031 on effect (0.157 vs 0.110
core-s), on evidence strength (4 paired replicates plus a cross-engine control, versus a single A/B),
on difficulty (low versus medium) and because it carries a precision consequence as well as a cost.
IMP-031's Q22 value understates its general value, because on a non-resident working set the 126,777
eliminated lookups would be physical reads rather than cycles.

### Reused root causes

| ID | Q22 evidence added |
|---|---|
| **IMP-008** | The `IN` list is a second, larger consumer of the same generic comparator: `tp_value_compare_with_error` 3.41% self, reached 7x per non-matching row from `eval_some_eval`. IMP-029 owns the per-element *materialisation*; IMP-008 keeps the comparator *dispatch*. Complementary, not substitutable. |
| **IMP-013** | Buffer fix/unfix + LRU + mutex band 10.68% = 0.58245 core-s against PostgreSQL's 8.73% = 0.10730 (5.43x), with **zero physical reads on either engine** — the campaign's cleanest isolation of this root cause. |
| **IMP-020** | Heap row materialisation 9.20% = 0.50173 core-s over 3,000,000 row visits against PostgreSQL's single-symbol `tts_buffer_heap_getsomeattrs` band 16.13% = 0.19825 (2.53x on the materialisation band). |
| **IMP-028** | Second query for this root cause and a cleaner isolation than Q21: same plan shape, same 190,691 probes, `F_work` exactly 1. Anti-join band 1.18252 core-s (6201 ns/probe) against 0.18284 (959 ns/probe) = **6.467x**, replicate range 5.43–7.64x. Contains IMP-031's 0.11004 core-s; not summed. |

**No candidate here is a restated profile line.** Each states what the engine does per row or per
operation, what PostgreSQL does instead with both `file:line` citations from section 7, and why the
change direction follows; each carries an effect range with its evidence type, an implementation
direction, a correctness/regression risk, validation criteria, a difficulty with reason, an upstream
precedent statement, and its relations. Evidence types used: **direct A/B** (IMP-030, IMP-031, and
the band series), **profile attribution** (IMP-029's band share), and **upper/lower bound**
(IMP-029's interval, IMP-031's lower bound). No overlapping effects are summed (section 8-d).

## 10. Evidence index

Format: `claim → raw file:line → formula → evidence type → SHA-256` (SHA-256 of every artifact is in
`reports/Q22/raw-manifest.json`; 944 artifacts, 799 valid, 145 invalid, 444,863,337 bytes under
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q22`).

| Claim | Raw file | Formula / field | Evidence type |
|---|---|---|---|
| `T_C = 1.101000 s` | `Q22-cubrid-headline-block1.json` | `median_s` of `measured_times_s` | direct measurement |
| `T_P = 0.608261 s` | `Q22-postgresql-headline-block1.json` | `median_s` | direct measurement |
| `R_wall = 1.810078x` | both above | `T_C / T_P` | direct A/B |
| `U_C = 4.95333`, `CPU_C = 5.453622` | `Q22-cubrid-headline-telemetry.json` | `total_query_cpu_block_core_s / t_block_s`; `U × T_C` | per-TID sampler |
| `U_P = 2.02062`, `CPU_P = 1.229063` | `Q22-postgresql-headline-telemetry.json` | same | per-TID sampler |
| `F_plan = 1.0000` | `q22-plan-est-cubrid.out`, `q22-plan-est-pg.out`, `q22-plan-act-pg.out`, `q22-trace-cubrid.out` | structural equality, section 4-a | structural equality |
| `F_work = 1.0000` (rows) | `q22-groundtruth.json`, `q22-trace-cubrid.out`, `q22-plan-act-pg.out` | `2 × gt1 / 2 × gt1` | direct count, 3 instruments |
| `F_work = 1.0000` (probes) | `q22-trace-cubrid.out` `readkeys: 190691`; `q22-plan-act-pg.out` `Index Searches: 190691`; `q22-groundtruth.json` `gt4` | `190691/190691` | direct count, 3 instruments |
| WARM: no physical reads | all six `Q22-*-headline-block*.json` | `sampler.engine_read_bytes_delta = 0`; PostgreSQL `heap_blks_read` delta 0 | direct measurement |
| anti-join band 6.467x | `Q22-{cubrid,postgresql}-bandB{4,5}*-headline-telemetry.json` | `(CPU_B5 − CPU_B4)_C / (CPU_B5 − CPU_B4)_P`, PostgreSQL mean of 4 | direct A/B |
| coercion band 104.60 ns/row | `Q22-cubrid-bandB{6,7}*-headline-telemetry.json` | `(CPU_B6 − CPU_B7)/1.5e6`, 4 replicates | direct A/B |
| coercion is CUBRID-specific | `Q22-postgresql-bandB{6,7}*-headline-telemetry.json` | same on PostgreSQL: 2.14 ns/row, replicates straddle zero | direct A/B (control) |
| row-set unchanged by B6/B7 | `q22-band-B6-{cubrid,postgresql}.out`, `q22-band-B7-{cubrid,postgresql}.out` | all four report `190691` | direct count |
| covering scan A/B | `q22-trace-B8-cubrid.out` | `covered: true`, no `lookup` stage, `fetch: 572777` vs `699554` | direct A/B |
| B8 answer identical | `q22-band-B8-cubrid.out` | 7 rows byte-identical to the canonical answer | direct comparison |
| row-lookup band 0.11004 core-s | `Q22-cubrid-band{B5,B8}-headline-telemetry.json` | `CPU_B5 − CPU_B8` | direct A/B |
| profile bands | `profile-cubrid-flat.txt`, `profile-pg-flat.txt` | self% × per-statement CPU, `q22-bands.txt` | profile attribution |
| perf coverage validated | `q22-perf-cubrid.log`, `q22-perf-pg.log` | `unknown-symbol lines=0` on both | coverage check |
| IPC 2.13 / 2.19 | `perf-stat-cubrid.txt`, `perf-stat-pg.txt` | `instructions / cycles` | perf stat |
| sampler undercounts PostgreSQL 21.5% | `q22-pg-dualinstrument-perf.txt`, `q22-dualinstrument.log` | `6.85546 / 5.38` over one block | dual instrument |
| PostgreSQL launches 1 of 4 workers | `q22-pgworkers-probe.out` (12 runs), `q22-pgworkers-control.out` (4+4 runs) | `Workers Launched` per `Gather` | direct count, 16/16 |
| InitPlan causes it | `q22-pgworkers-control.out` | B6 (no InitPlan) launches 4/4 in 4/4 runs | direct A/B (control) |
| cpuset violation | `q22-postflight.txt`, `Q22-cubrid-block3-affinity-a{1,2,3}.json`, `invalid-affinity-20260802/INVALID.json` | `off_cpuset=2 -> FAIL`; guard `verdict: OFF_CPUSET` with per-TID core-s | all-TID guard |
| remediation verified | `q22-affinity-verify-postrestart.json`, `q22-preflight-postremediation.txt`, `q22-cubrid-restart.log` | `verdict: CLEAN`, 141 TIDs / 0 off; 136 TIDs / 0 off; SHA-256 match | all-TID guard + ownership gate |
| all re-measured stages clean | 51 × `Q22-*-affinity.json` | every `verdict = CLEAN` | all-TID guard |
| correctness | `q22-correctness.json`, `q22-correctness-{cubrid,postgresql}.out` | `result-equivalent-at-SF10`, 7 rows ordered | direct comparison |
| query provenance | `q22-preflight.txt` | three SHA-256 identical, `q22.diff` 0 bytes | direct hash |

## 11. Notion sync

**Not performed by this session, by design.** SSOT section 21's execution boundary is explicit: the
GJC/tmux worker session runs on the remote build host, has no Notion connector, and "must never
attempt a Notion write"; its Notion-adjacent duty ends at committing and pushing the report and
manifest to `origin/main`.

An idempotent backfill record was appended to `reports/notion_backfill_pending.jsonl` (SSOT section
21 write path 3), keyed by
`campaign_id + QNN + session_id + report_commit + content_fingerprint`. The dedicated
Notion-capable subagent is to read the pushed commit as source of truth and mirror:

- the causal multiplier card of section 3-a with the full factor table, **including the disclosed
  `F_units`/`F_cpu` split sensitivity**;
- headline timings from section 3-b;
- the plan comparison of section 4-a showing both engines' shapes, not a verdict;
- the profiling top-cost symbols of section 6 for both engines;
- the full source contrast of section 7 with `file:line` on both sides;
- the causal decomposition narrative of section 8 **including the rejected explanations of 8-e and
  the numbers that rejected them**;
- all three improvement candidates of section 9, each also getting its own improvement-registry
  page carrying the full section 18 content;
- **the section 5-a cpuset incident and its campaign-wide implication for Q21**, which the operator
  needs in the operational-state page, not buried in a Git report.

Pending record is cleared only after a server-side refetch confirms the write.

## 12. Completion checklist

| SSOT section 26 gate | Status |
|---|---|
| preflight and correctness status recorded | **yes** — `q22-preflight.txt`, `q22-preflight-postremediation.txt`, `q22-postflight.txt`, `q22-correctness.json` (`result-equivalent-at-SF10`) |
| three valid headline values for each completing engine | **yes** — 3 measured statements × 3 accepted blocks per engine, all post-remediation, all load-gate `CLEAN` and affinity-guard `CLEAN` |
| timeout confirmations if censored | n/a — no censoring; both engines ≈1 s against a 300 s timeout |
| plan, execution, profile and source contrast sections complete | **yes** — sections 4, 5, 6, 7 |
| causal multiplier card has evidence or explicit `UNMEASURED` | **yes** — every factor numeric with evidence type; no `UNMEASURED` factor; residual +0.0000% with its telescoping limitation stated and the `U` cross-checks given |
| Git improvement ledger deduplicated and committed | **yes** — 3 new IDs, 4 reuses, `next_id` → `IMP-032`, dedup reasoning in `q22_allocation_note` |
| Notion relations synced or idempotent backfill durable | **backfill record durable** in `reports/notion_backfill_pending.jsonl`; the Notion write itself is outside this session's execution boundary (SSOT section 21) |
| every claim indexed to raw evidence and checksum | **yes** — section 10; 944 artifacts hashed in `reports/Q22/raw-manifest.json` |
| report, manifest and registry committed, pushed, reachable from `origin/main` | **yes** — see the commit recorded in the backfill record |
| `QUERY_COMPLETE` emitted | **yes** — section 12-a |
| current session removed and absence verified | performed by the controlling session after this report is durable (SSOT section 22.7-22.8) |

Additional gates specific to Q22:

| Gate | Status |
|---|---|
| SSOT drift | `ssot_drift=NONE` on all three captures; `HEAD == origin/main == c6b037f` throughout |
| all-TID cpuset gate | **PASS after remediation** — 51 of 51 accepted stages `CLEAN` under continuous sampling; the failing first pass is retained as `valid=false` evidence with `INVALID.json` |
| ownership gate before and after each block | `OK` on both engines, both passes; the mid-query CUBRID restart used the mandatory wrapper and re-verified executable SHA-256, DB name, port and every contracted parameter |
| invalid runs excluded from calculations | **yes** — 145 artifacts marked `valid=false`; no invalidated number appears in the card, the bands or the headline |
| WARM proved, not assumed | **yes** — zero physical reads on both engines on all six blocks, plus 40-statement convergence probes on both engines |
| engine block order | PostgreSQL first, then CUBRID (Q22 even, SSOT section 12) |

### 12-a. Status block

```yaml
TPCH_SSPQ_STATUS:
  campaign_id: tpch-sspq-fk-r1-20260730
  query: Q22
  ssot_commit: c6b037f7bd7b4cc1a656bc0cfabad0d81de63e9d
  ssot_blob_sha: 510478846bff081d3223d3835069283a7cd2e47b
  session_id: gajae_code_msbqesrv_8od37q3s
  stage: 14.13-completion-checklist
  state: complete
  report_commit: 802b892e3b1b5ae32afd4496ba7dca902fc235cc
  artifact_fingerprint: 8573a23b91d14c3582ba4a6304ea445900573114c6a03dfa4562a513d09d6a22
  timestamp: 2026-08-02T22:23:15+09:00
  next_action: QUERY_COMPLETE
```

**QUERY_COMPLETE**

### 12-b. Operator escalation carried out of this query

Two items are escalated rather than decided here, per SSOT section 25:

1. **Q21's CUBRID numbers were measured against the same mis-bound `cub_server` instance
   (pid 2646189)** and its `parallel-query` workers therefore also ran outside the contracted
   cpuset. The bias favours CUBRID, so Q21's reported 49.394998 s and 16.020754x are lower bounds;
   the qualitative conclusion is unchanged. Q17-Q20 used pid 1612732, which no longer exists, so
   their exposure is not determinable from this host. Re-measuring durable completed queries is a
   campaign-contract decision, not a worker-session action.
2. **The campaign's affinity procedure needs to change, not just this server.** Because CUBRID
   caches its affinity mask at process start (`src/base/resources.cpp:190-192`), applying `taskset`
   to a *running* `cub_server` cannot hold: every pooled thread created later is rebound to the
   stale mask. `cub_server` must be **started** under `taskset -c 0-15`, and the all-TID gate must
   sample continuously during a stage rather than only before and after it
   (`harness/affinity_guard.py`, added by this query).
