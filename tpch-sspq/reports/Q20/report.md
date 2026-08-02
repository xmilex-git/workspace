# TPCH-SSPQ FK campaign — Q20 report

TPC-H Query 20, Potential Part Promotion.

## 1. Identity

| Field | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q20 |
| SSOT commit | `1b5fbc021353b16cf4b7375695fd6cad4ec4402d` |
| SSOT blob SHA | `510478846bff081d3223d3835069283a7cd2e47b` |
| GJC session ID | `gajae_code_msbcoz5r_9q99b9x2` |
| Raw root | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q20` |
| Engine block order | Q20 is even → PostgreSQL block first, then CUBRID (SSOT section 12) |
| Scale | TPC-H SF10, histogram-enabled controlled comparison |

| Engine | Source SHA | Install prefix | Binary SHA-256 | ELF Build ID |
|---|---|---|---|---|
| CUBRID | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9` | `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` | `4df41ee21300bf617bccd5e1d5c8522b074ef86e` |
| PostgreSQL | `5713b437abed7085e7d59849c6e9e0f4f469633d` | `/home/cubrid/pg/pg20devel-5713b437` | `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` | `5f2cb2987765c612638c278f85cfc85c211fffe1` |

Both running binaries were resolved through `/proc/<pid>/exe` and their SHA-256 matched the frozen
`reports/bootstrap/build-manifest.json` (`frozen: true`).

**Preflight (stage 14.1)** — `q20-preflight.txt`:

- `ssot_drift=NONE` (HEAD blob == pinned blob); `git status --porcelain -- tpch-sspq` empty at
  session start; branch `main`, `HEAD == origin/main == 1b5fbc0`.
- cpuset: 34 engine TIDs (cub_master 2, cub_server 24, postmaster 1, pg children 7),
  **0 off-cpuset** → PASS. External SUT-set load 0.576 core-s/s against the 6.0 threshold.
- Ownership gate `OK` on both engines: `cub_master` pid 1433697 on port 1523, `cub_server`
  pid 1612732, postmaster pid 1433696 on port 5442, all campaign-owned.
- Schema contract: CUBRID 8 FK-owned B-trees, PostgreSQL 8 FKs / 8 `idx_fk_*` / 8 `convalidated`,
  exact child-column order including composite `fk_lineitem_partsupp (l_partkey, l_suppkey)`.
- Row counts identical on both engines (lineitem 59,986,052; partsupp 8,000,000; part 2,000,000;
  supplier 100,000).
- Statistics: CUBRID `update_statistics_update_histogram=y`, `default_histogram_bucket_count=300`;
  PostgreSQL `default_statistics_target=100`.
- Parallel/buffer contract: CUBRID `parallelism=6`, `max_parallel_workers=100`,
  `data_buffer_size=8.0G`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`,
  `parallel_leader_participation=on`, `shared_buffers=8192MB`, `statement_timeout=300000 ms`,
  `jit=off`. Label: **configured node/gather-cap comparison**, **configured-equal buffer budget**.
- Query provenance: `queries/q20-cubrid.sql` and the canonical
  `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q20.sql` both SHA-256
  `d7b9dfc07b721f7b96abc8e370d85bf81f5e5f2968de5f4a87cb86af297f2504`; byte-match confirmed.
  `queries/q20-pg.sql` is `3ec146224a6b9e9d7c6817d5fd75d34c34b8b78565e1c8e68834a0d77c4bb136`.
  `queries/diff/q20.diff` (489 bytes) contains **exactly one hunk, one line**:
  `DATE_ADD(DATE '1994-01-01', INTERVAL 1 YEAR)` → `date '1994-01-01' + interval '1' year`.
  Reason: CUBRID's `DATE_ADD` has no PostgreSQL spelling; both denote `1995-01-01`, and both
  engines' actual plans print the identical resolved bound (`l_shipdate < '1995-01-01'`). No hint,
  no join reordering, no subquery rewrite, no extra predicate, no semantic cast.

**Mid-query server restart, declared.** After every headline, telemetry and perf artifact had been
captured, `cub_server` was restarted **once**, through the mandated wrapper
`~/dev/workspace/.claude/skills/cubrid-server-control/scripts/cubrid-server-ctl.sh restart`, to run
the cold-pool residency A/B in section 5. `cub_server` pid therefore changes from **1612732**
(all measurements) to **2646189** (residency A/B and postflight). The post-restart ownership gate
re-resolved the same executable and the same SHA-256, cpuset was reapplied to **every** TID
(124 TIDs, 0 off-cpuset), and `parallelism=6` / `max_parallel_workers=100` / `data_buffer_size=8.0G`
were re-verified before the A/B ran. No headline value was measured after the restart; the A/B
independently reproduces the headline level (section 5).

**Postflight** — `q20-postflight.txt`: same executables and SHA-256, 31 engine TIDs with
**0 off-cpuset**, external load 0.282 core-s/s, 8 FK / 8 `idx_fk_*` / 8 `convalidated` unchanged,
`ssot_drift=NONE`, working tree still clean.

`dynamic_shared_memory_type=mmap` is not decision-relevant here: neither engine's Q20 plan contains
a Parallel Hash Join, and the only `Gather Merge` in either plan carries 4,054 supplier rows, so the
section 9 `/dev/shm` consideration does not bind on this query.

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored; no timeout on either engine. The slowest single
statement anywhere in this query was 7.50 s against the 300 s rule of section 13.

| Field | Value |
|---|---|
| Status | `result-equivalent-at-SF10` |
| Rows | 1,804 |
| `ORDER BY` present | yes (`order by s_name`) → ordered sequence compared exactly |
| Columns | `s_name` (char), `s_address` (varchar) — text only, no decimals |
| Absolute difference | 0 |
| Tolerance exercised | **none** — Q20 returns no numeric column, so the section 11 decimal rule is not reachable |

Q20 is the campaign's cleanest correctness case: the projection is two text columns, so there is no
decimal to normalise and no tolerance that could hide anything. Row count, row order and every byte
of both columns match. The result is independently confirmed by the section 5 ground-truth probe,
which counts **1,804** qualifying suppliers on **both** engines through a differently-written
equivalent query (`q20-groundtruth.sql`).

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
0.291327x = 0.160325x [plan] × 0.831505x [units] × 2.185313x [CPU-sec]

2.185313x [CPU-sec] = 1.000000x [work] × 2.185313x [cost]
```

**Q20 is a query CUBRID wins, so the `F_plan` anchor is on the SLOWER engine.** Anchor direction:
**PostgreSQL native → PostgreSQL controlled (`derived`)**, a same-engine A/B in which the controlled
variant expresses, in PostgreSQL, the plan shape CUBRID's optimizer *rewrites the campaign query
into* — the uncorrelated `IN` subquery materialised as one derived table, evaluated once, bottom-up
(section 4). `F_units` and `F_cpu` are computed on the **remaining controlled cross-engine pair** —
CUBRID native versus PostgreSQL controlled — which execute the same plan shape over the same tuples.
Native and controlled denominators are not mixed:

```text
R_wall = T_C/T_P = (T_Pc/T_P) × (T_C/T_Pc)
                    F_plan      F_units × F_cpu
```

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `R_wall` | 0.291327x | wall seconds | median of 3 measured WARM statements, block1 | `T_C / T_P` | `Q20-cubrid-headline-block1.json`, `Q20-postgresql-headline-block1.json` | direct A/B |
| `F_plan` | 0.160325x | wall seconds | same engine, same block regime, same load gate, same 20-statement WARM gate | `T_Pc / T_P` | `Q20-postgresql-derived-headline-block1.json`, `Q20-postgresql-headline-block1.json` | direct A/B (same-engine controlled) |
| `F_units` | 0.831505x | core-seconds per wall-second | total query CPU over the 4-statement block ÷ sum of that block's statement walls | `U_Pc / U_C` | `Q20-cubrid-headline-telemetry.json`, `Q20-postgresql-derived-headline-telemetry.json` | per-TID sampler, actual timestamp deltas |
| `F_cpu` | 2.185313x | total query CPU-seconds | per measured statement, `U × t` | `CPU_C / CPU_Pc` | same two telemetry artifacts | per-TID sampler |
| `F_work` | 1.000000x | executions of the correlated `lineitem` aggregate subquery | one measured statement | `W_C / W_Pc` | `q20-trace-cubrid-resident.out`, `q20-plan-act-pg-derived.out`, `q20-groundtruth-*.out` | direct count (engine trace + EXPLAIN loops, confirmed against ground truth) |
| `F_cost` | 2.185313x | core-seconds per subquery execution | same | `(CPU_C/W_C)/(CPU_Pc/W_Pc)` | derived, `q20-causal-card.txt` | profile attribution |

Measured inputs (`q20-causal-card.txt`, `q20-causal-card.json`):

| Quantity | Value |
|---|---|
| `T_C` CUBRID native median (proven-resident) | 1.992000 s |
| `T_P` PostgreSQL native median | 6.837673 s |
| `T_Pc` PostgreSQL controlled (`derived`) median | 1.096253 s |
| `U_C` | 1.23869 core-s/wall-s |
| `U_P` | 1.01345 core-s/wall-s |
| `U_Pc` | 1.02998 core-s/wall-s |
| `CPU_C = U_C·T_C` | 2.467478 core-s |
| `CPU_P = U_P·T_P` | 6.929644 core-s |
| `CPU_Pc = U_Pc·T_Pc` | 1.129119 core-s |
| `W_C` | 86,204 correlated-subquery executions |
| `W_Pc` | 86,204 correlated-subquery executions |

**Reading the card in words.** CUBRID finishes Q20 in **0.291327x** of PostgreSQL's wall, i.e.
**3.4326x faster**. That entire advantage, and more, comes from `F_plan`: PostgreSQL's own optimizer
chooses a plan that costs it **6.2373x** against a plan PostgreSQL can execute perfectly well
(1.096253 s) and which its own cost model ranks only 1.1711x more expensive. Strip the plan
difference out and the remaining controlled pair runs the *other* way: on identical work CUBRID
needs **2.185313x** the CPU, partly offset by sustaining **1.2026x** more active units, for a net
**1.8171x** disadvantage at matched plan shape. Q20 therefore looks like a CUBRID win and is, on
the wall, but the mechanism is a PostgreSQL plan-choice defect, not a CUBRID execution advantage —
the same shape of finding as Q18, reached here through a much cleaner controlled pair.

**`F_work` is exactly 1.000000, and that is a measurement rather than an assumption.** Both sides of
the controlled pair drive from `part`, filter `p_name like 'forest%'` to **21,551** rows, probe
`partsupp` by `ps_partkey` to **86,204** rows, fire the correlated `lineitem` aggregate **86,204**
times, keep **58,655** qualifying `partsupp` rows, reduce them to **44,482** distinct supplier keys
and emit **1,804** rows. Every one of those six numbers is identical on the two engines and each is
confirmed twice — once by the engine's own instrument (CUBRID `SET TRACE ON`, PostgreSQL
`EXPLAIN (ANALYZE)` `loops`/`Index Searches`) and once by the independent `COUNT(*)` ground-truth
probe run on both engines. `F_cpu` is therefore entirely `F_cost`.

**Reconstruction residual: +0.0000%.** As on Q17 and Q19 this must be read honestly: with
`F_plan = T_Pc/T_P` and `F_units × F_cpu = T_C/T_Pc` the product telescopes to `T_C/T_P` by
construction, so the residual tests arithmetic, not independence. The card's genuine validation is
that `U`, the only non-wall input, is confirmed by an instrument the card does not use — `perf stat`
"CPUs utilized" over a separate 30-second replay window:

| Configuration | sampler `U` (block) | `perf stat` CPUs utilized | agreement | TWU (block) | peak units | serial tail |
|---|---|---|---|---|---|---|
| CUBRID native | 1.23869 | 1.242 | **+0.27%** | 1.2407 | 5.6049 | 1.799 s |
| PostgreSQL controlled (derived) | 1.02998 | 0.973 | −5.53% | 1.0082 | 1.4367 | 4.979 s |
| PostgreSQL native | 1.01345 | 0.976 | −3.70% | 1.0707 | 1.9054 | 7.899 s |

CUBRID's two instruments agree to 0.27% and its TWU to +0.16%. The two PostgreSQL figures sit
3.7–5.5% below their sampler values, in the same direction and for the same reason as on Q19: the
`perf stat` window is a back-to-back replay in one connection, whereas `U` is measured over the
4-statement contract block whose first statement is the burn-in statement. The `perf` numbers are
used as a **direction-and-magnitude cross-check**, never as a card input.

### 3-b. Headline timings

All three measured statements from every accepted block. Block 1 is the headline (campaign
convention since Q12); blocks 2–3 are block-to-block stability evidence.

| Configuration | block 1 | block 2 | block 3 | block-1 median | mean | sd |
|---|---|---|---|---|---|---|
| **CUBRID native** (headline) | 1.992000 / 1.988999 / 1.998000 | 1.982 / 1.980 / 1.983 | 1.970 / 1.949 / 1.939 | **1.992000 s** | 1.993000 | 0.004583 |
| **PostgreSQL native** (headline) | 6.947950 / 6.559072 / 6.837673 | 6.945247 / 6.543834 / 6.842164 | 6.870785 / 6.453392 / 6.754521 | **6.837673 s** | 6.781565 | 0.200419 |
| PostgreSQL controlled (`derived`) | 1.097258 / 1.096253 / 1.095227 | 1.097176 / 1.096746 / 1.101046 | 1.093737 / 1.092522 / 1.091280 | 1.096253 s | 1.096246 | 0.001016 |
| CUBRID **low-residency** (not the headline, section 5) | 3.231 / 3.162 / 3.148 | 3.210 / 3.193999 / 3.158 | 3.194 / 3.190 / 3.203 | 3.162000 s | 3.180333 | 0.044433 |

| Field | Value |
|---|---|
| CUBRID median seconds | **1.992000** |
| PostgreSQL median seconds | **6.837673** |
| Median wall ratio `T_C/T_P` | **0.291327x** (CUBRID 3.4326x faster) |
| Correctness | `result-equivalent-at-SF10` |
| Censoring | none |

Three values are reported and the median is the headline. Mean and within-block standard deviation
are given above. **No confidence interval is claimed from three values.** Block-median spread across
the three independent blocks is 2.170% (CUBRID), 1.282% (PostgreSQL native) and 0.425% (PostgreSQL
controlled); recomputing the whole card on block 2 or block 3 moves `R_wall` by at most 0.96% and
`F_plan` by at most 0.89% (`q20-causal-card.txt`, sensitivity table).

**PostgreSQL's within-block spread is structure, not noise.** Its three measured statements are
always high/low/high, and the 40-statement convergence probe shows why: after a 2-statement burn-in
the PostgreSQL native series is **bimodal with period two**, alternating 6.5152 s and 6.8234 s
(+4.7303%), with lag-1 autocorrelation **−0.9092**, all 37 consecutive triples alternating in sign,
and the two phases **disjoint** (max of the fast phase 6.5451 s < min of the slow phase 6.7496 s).
Section 5 identifies the cause exactly. This is why the Q20 WARM gate had to be re-derived
(`q20-warm-gate-params.txt`): the inherited 3.0% spread sanity floor **rejects** this provably
stationary series (`spread 4.8962% > 3.00% (unstable)`, rc=4), so `SPREAD_SANITY` was raised to 6.0%
against the measured alternation amplitude, `WINDOW` was fixed at an **even** value so a trailing
window always spans whole phase pairs, and `LEVEL_TOL` was set at 2.0% against a **phase-preserving**
moving-block bootstrap (max 1.12% at n=20) rather than the naive resample, which manufactures phase
imbalance the engine never produces and inflates the null to 5.24%.

## 4. Plan

Both engines reach the same *logical* decomposition — TPC-H Q20's nested `IN` subqueries — and then
diverge completely on which relation drives.

### 4-a. CUBRID (`q20-plan-est-cubrid.out`, `q20-trace-cubrid-resident.out`)

CUBRID does not keep the `IN` subqueries as subqueries. `qo_rewrite_subqueries()` converts each
**uncorrelated** `IN` into a **derived table appended to `FROM`**, recursively, so the query becomes
a bottom-up pipeline of three nested derived specs (`av1861`):

```text
temp(order by)                                   -- outer: supplier x nation x av1861
  idx-join
    idx-join
      sscan av1861(node[2])                      -- distinct ps_suppkey list
      iscan supplier  index: pk_supplier_s_suppkey
    iscan nation      index: pk_nation_n_nationkey  sargs: n_name='CANADA'
  sort: 1 asc

  av1861 = temp(distinct)                        -- middle derived spec
    idx-join
      sscan av1861(node[1])                      -- distinct p_partkey list
      iscan partsupp index: fk_partsupp_part  sargs: ps_availqty > (subquery)  subqs: 0
                                                 -- correlated lineitem aggregate as a sarg
    av1861 = temp(distinct)                      -- inner derived spec
      sscan part  sargs: p_name range ('forest' ge_lt 'foresu')
```

Traced actuals, fully resident (`ioread: 0` at every node):

| Node | Measured |
|---|---|
| `SELECT` (top) | time 2251 ms, fetch 1,300,830, fetch_time 413 ms, **ioread 0** |
| `sscan part` | readrows 2,000,000, **parallel workers: 5**, heap time 115–116 ms each, gather mergeable list |
| inner `temp(distinct)` scan | readrows **21,551** |
| `iscan partsupp fk_partsupp_part` | readkeys **21,551**, rows **86,204**, fetch 150,857, lookup 197 ms |
| correlated `iscan lineitem fk_lineitem_partsupp` | readkeys **86,204**, filteredkeys 86,158, rows **645,483**, lookup rows **98,107**, btree time 2,448 ms, fetch 904,095 |
| middle `temp(distinct)` scan | readrows **44,482** |
| `iscan supplier pk_supplier_s_suppkey` | readkeys 44,482, rows 44,482 |
| `iscan nation pk_nation_n_nationkey` | readkeys 25, rows 1 |
| `MEMOIZE` | **hit 44,457 / miss 25**, size 4 KB |
| `ORDERBY` | sort true, page 282, ioread 0 |

### 4-b. PostgreSQL native (`q20-plan-est-pg.out`, `q20-plan-act-pg.out`)

PostgreSQL keeps both `IN` subqueries as *relations*: `convert_ANY_sublink_to_join()` pulls each
sublink up as a `JOIN_SEMI`, leaving the join order entirely to the cost model — which drives from
`supplier`:

```text
Nested Loop Semi Join                                     (cost 2,812,921)  rows=1804 actual 7466 ms
  -> Gather Merge  (Workers Planned 1, Launched 1)        supplier x nation('CANADA'), 4,054 rows
  -> Nested Loop                                          loops=4054
       -> Index Scan idx_fk_partsupp_supplier on partsupp loops=4054  rows=41.48  Removed=20
            Filter: ps_availqty > (SubPlan expr_1)
            SubPlan expr_1
              -> Aggregate                                loops=247,287
                   -> Index Scan idx_fk_lineitem_partsupp loops=247,287 rows=1.14 Removed=6
       -> Index Scan part_pkey on part                    loops=168,171  Filter: p_name ~~ 'forest%'
Buffers: shared hit=2,940,804 read=589,094
```

### 4-c. PostgreSQL controlled (`derived`) — the `F_plan` anchor

The controlled variant (`q20-derived.sql`) wraps the uncorrelated `IN` subquery in a
`WITH ... AS MATERIALIZED` CTE. `MATERIALIZED` is PostgreSQL's optimization fence and is the closest
available counterpart to `mq_make_derived_spec()`'s derived spec. **Nothing else in the query
changes**, and its result is byte-identical to the campaign query on the same engine (1,804 rows,
verified by `diff` after delimiter normalisation, `q20-derived-result-pg.out`).

```text
Sort                                                      (cost 3,294,140)  actual 1642 ms
  CTE ps -> Unique                                        rows=44,482
    -> Sort                                               rows=58,655
      -> Nested Loop                                      rows=58,655
        -> Seq Scan on part      Filter p_name ~~ 'forest%'  rows=21,551  Removed=1,978,449
        -> Index Scan idx_fk_partsupp_part on partsupp    loops=21,551  rows=2.72  Removed=1
             Filter: ps_availqty > (SubPlan expr_1)
             SubPlan expr_1 -> Aggregate                  loops=86,204
               -> Index Scan idx_fk_lineitem_partsupp     loops=86,204  rows=1.14  Removed=6
  -> Hash Join  ps x (nation x supplier bitmap)           rows=1,804
Buffers: shared hit=1,033,307 read=0
```

### 4-d. The comparison that matters

| Quantity | CUBRID native | PostgreSQL **controlled** | PostgreSQL **native** |
|---|---|---|---|
| Driving relation | `part` | `part` | `supplier` |
| `part` rows surviving the `like` | 21,551 | 21,551 | (probed by pkey, 168,171 loops) |
| `partsupp` rows examined | 86,204 | 86,204 | ~250,943 |
| **correlated subquery executions** | **86,204** | **86,204** | **247,287** |
| `lineitem` index rows read | 645,483 | ~615,496 | ~1,765,629 |
| distinct supplier keys formed | 44,482 | 44,482 | (semi-join, no distinct) |
| buffer page fetches | 1,300,830 × 16 KiB | 1,033,307 × 8 KiB | 3,529,898 × 8 KiB |
| physical reads | **0** | **0** | 589,094 pages |
| median wall | 1.992000 s | 1.096253 s | 6.837673 s |

PostgreSQL's native plan fires the expensive correlated aggregate **2.8686x** more often than it
needs to, because it drives from the 4,054 Canadian suppliers (each owning 80 `partsupp` rows) and
evaluates the `ps_availqty > (SubPlan)` filter — a `baserestrictinfo` on `partsupp` — *before*
joining to `part`. Driving from `part` instead restricts `partsupp` to 86,204 rows first. The
`Nested Loop Semi Join`'s early exit saves some of it (247,287 rather than the full 324,320
Canadian `partsupp` rows, confirmed by ground truth), but not enough.

**Structural note.** CUBRID's shape is not *chosen*; it is **forced** by the rewrite. A derived spec
is materialised bottom-up and is not a relation the join-order search may reorder, so CUBRID could
not have produced PostgreSQL's supplier-driven plan even if its cost model had preferred it. On Q20
that rigidity is worth 6.2373x in CUBRID's favour. It is a structural difference, not a CUBRID
optimizer achievement, and section 8 records the cases where the same rigidity would cost CUBRID.

## 5. Execution telemetry

### 5-a. Buffer state of the headline — and a bistable CUBRID level

**PostgreSQL native cannot be resident, by construction.** `heap_blks_read` deltas over the
4-statement blocks are 2,396,522 / 2,396,521 / 2,396,518 — **599,130 pages ≈ 4.68 GB per
statement** — reproducible to within 4 pages across three independent blocks. `EXPLAIN (ANALYZE,
BUFFERS)` confirms `read=589,094` for a single statement. The plan touches 324,320 `partsupp` rows
and 247,287 scattered `lineitem` index probes over an 11 GB index against `shared_buffers=8192MB`.

**That is also the cause of the period-2 alternation** reported in section 3-b. A dedicated
per-statement probe (`q20-pgreads.out`) interleaves the query with `pg_statio_user_tables` snapshots
in one connection:

| statement | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| wall (s) | 7.775 | 6.598 | 6.814 | 6.485 | 6.815 | 6.485 | 6.795 | 6.506 | 6.792 | 6.500 |
| `heap_blks_read` delta | 628,809 | 569,452 | 628,808 | 569,452 | 628,809 | 569,452 | 628,809 | 569,452 | 628,809 | 569,452 |

The correlation is exact and deterministic: every slow statement reads **628,809** pages and every
fast one **569,452**, a difference of **59,357 pages (464 MB)** costing ≈0.30 s, i.e. ≈5.1 µs per
extra page read. The controlled `derived` variant, which is fully resident, shows **no alternation
at all** (40-statement probe: 1.0961–1.1117 s after one burn-in statement) and `heap_blks_read`
delta **exactly 0** on all three of its blocks. The alternation is a property of the native plan's
oversized working set, not of the query or the host.

**CUBRID's headline level is bistable, and the first three CUBRID blocks were measured in the wrong
state.** The blocks now preserved as `Q20-cubrid-lowresident-*` passed the WARM gate's *level* test
— 40 consecutive self-repeats held 3.146–3.205 s with half-split trend −0.1576% and no drift — but
failed the other half of the section 12 WARM proof, *"record physical read deltas"*: the engine
trace of an equally converged statement reported **`ioread: 204665`** (`q20-trace-cubrid.out`).
After the section 5 ground-truth probes ran, the identical statement settled at 1.91–2.01 s with
trace **`ioread: 0`** and `cub_server` `/proc` `read_bytes` delta **exactly 0** across 30 consecutive
self-repeats. Both levels are self-consistent, so this is buffer hysteresis, not warm-up. The
headline was therefore **re-measured** under a proven-resident pool; every re-measured block carries
its own residency proof (`Q20-cubrid-residency-block*.txt`: `read_bytes` unchanged at
17,837,154,304 across all three blocks) and the closing trace reports `ioread: 0`.

**The cold-pool A/B (`q20-residency-driver.log`) settles which level is the contract's.** After a
wrapper-mediated `cub_server` restart (ownership gate re-verified, cpuset reapplied to all 124 TIDs,
parameters re-verified):

| Phase | What ran | Result |
|---|---|---|
| A | 30 Q20 self-repeats in ONE session, from a genuinely cold pool | statement 1 = **6.896 s**; statements 2–30 = **1.916–2.043 s**; `syscr` delta 490,005 (≈7.5 GB) almost entirely in statement 1; VmRSS 2.58 GB → **8.43 GB**; closing trace **`ioread: 0`** |
| B | a **different** session touches the same pages once | result 98,107; no level change to observe — already resident |
| C | 15 Q20 self-repeats in a NEW session after the foreign touch | **1.831–2.168 s**, closing trace **`ioread: 0`** |

**This falsified the hypothesis it was built to test.** The private-LRU explanation (IMP-018:
a session's pages escape to the shared pool only when a *different* session touches them) predicts
that phase A should stall at the slow level and phase C should jump. It does not: from a cold pool
Q20 reaches full residency **within one statement** and never leaves. What the A/B proves instead is
sharper and is the finding this report records:

> Q20's distinct working set is ≈490,005 pages of the 524,288-page (8 GB) pool — **93.5%**. It fits,
> but only just. From cold it loads in one statement and stays. If the pool already holds a foreign
> working set, the combined demand exceeds the pool, and CUBRID's replacement policy will not
> reclaim that space in favour of the repeatedly-accessed Q20 pages: **40 consecutive identical
> statements failed to converge out of the degraded equilibrium**, which cost **1.5874x**
> (3.162000 s against 1.992000 s) at constant plan, constant query text and constant fetch count
> (1,300,830 page fetches in both states).

Repetition is excluded as the escape route by two independent 30- and 40-statement controls, and
intrinsic un-residency is excluded by the cold-start phase A. This is the history-dependent
equilibrium already recorded as IMP-002's Q05 mode, measured here more cleanly than anywhere else in
the campaign because the two states differ in *nothing* but residency.

### 5-b. CPU decomposition, units and I/O

Measured over the section 12 4-statement block with a per-TID sampler at a 20 ms nominal period,
weighted by **actual timestamp deltas**:

| Configuration | executor CPU | auxiliary CPU | total query CPU | sum of statement walls | `U` | TWU | peak units | serial tail |
|---|---|---|---|---|---|---|---|---|
| CUBRID native | 9.810 core-s | 0.050 core-s | 9.860 core-s | 7.9600 s | 1.23869 | 1.2407 | 5.6049 | 1.799 s |
| PostgreSQL native | 27.730 core-s | 0.310 core-s | 28.040 core-s | 27.6679 s | 1.01345 | 1.0707 | 1.9054 | 7.899 s |
| PostgreSQL controlled | 5.070 core-s | 0.000 core-s | 5.070 core-s | 4.9224 s | 1.02998 | 1.0082 | 1.4367 | 4.979 s |

Executor / auxiliary classification is explicit, never inferred: CUBRID's `executor` bucket is
`parallel-query` (0.58 core-s) plus `transaction` (1.88 core-s) threads inside `cub_server`, and its
`auxiliary` bucket is `dwb-flush-block` and `vacuum-master`; PostgreSQL's is `pg_backend` against
`pg_background`. `csql`/`psql` client CPU is auxiliary by construction and is never attributed to the
executor.

**Both engines are essentially serial on this query, and that matters for the card.** CUBRID reaches
5.6 active units, but only during the 122 ms parallel `part` heap scan; **1.799 s of the 1.992 s
statement (90.3%) runs at one active unit** inside the middle derived spec, which is an uncorrelated
subquery. PostgreSQL's controlled plan is equally serial (peak 1.4367, tail 4.979 s of a 4.92 s
block). So CUBRID's `F_units` advantage of 1.2026x comes almost entirely from that one parallel
scan, and the campaign's known "uncorrelated subquery degree is hardcoded to 1" defect (IMP-009)
binds on 90.3% of the statement **without** costing CUBRID anything against PostgreSQL here, because
PostgreSQL does not parallelise its counterpart either. Section 9 records that constraint on
IMP-009's effect claim.

Device I/O over the telemetry windows is zero-read on every configuration (`sectors_read: 0` on all
devices); the PostgreSQL native `read_bytes` of 1,695,744 with `syscr` 13,220,030 is page-cache
traffic, not device traffic. `/proc` `syscr` on `cub_server` across the three re-measured CUBRID
blocks totals 9,021 for 12 statements — session control traffic, not data pages.

## 6. Profile

Stage 14.8, non-headline. `perf record -F 999 -g --call-graph dwarf` attached to a verified PID set
(CUBRID: `cub_server` pid 1612732, all query worker threads inside it; PostgreSQL: postmaster
attached *before* the client connected so inherit-on-fork covers the leader and every statement's
workers). Coverage: 37,644 / 30,068 / 29,975 samples, no `[unknown]` symbol in any top-16.

| CUBRID native (top self-cost) | | PostgreSQL controlled `derived` | | PostgreSQL native | |
|---|---|---|---|---|---|
| `pgbuf_fix_release` | 13.00% | `hash_search_with_hash_value` | 17.34% | `rep_movs_alternative` `[k]` | 19.38% |
| `pgbuf_lru_boost_bcb` | 6.96% | `tts_buffer_heap_getsomeattrs` | 11.45% | `hash_search_with_hash_value` | 13.54% |
| `spage_get_record` | 5.45% | `heap_page_prune_opt` | 11.04% | `pg_checksum_block_fallback` | 8.38% |
| `heap_attrinfo_read_dbvalues` | 3.88% | `PinBuffer` | 8.13% | `_bt_compare` | 5.85% |
| `eval_pred` | 3.69% | `heap_hot_search_buffer` | 6.49% | `heap_page_prune_opt` | 4.73% |
| `__memmove_evex_unaligned_erms` | 3.67% | `_bt_compare` | 4.67% | `PinBuffer` | 4.16% |
| `or_mvcc_get_repid_and_flags` | 3.31% | `ExecInterpExpr` | 3.43% | `heap_hot_search_buffer` | 2.57% |
| `eval_value_rel_cmp` | 2.51% | `StartReadBuffer` | 1.36% | `StrategyGetBuffer` | 2.51% |
| `tp_value_compare_with_error` | 2.07% | `heapgettup_pagemode` | 1.28% | `filemap_get_read_batch` `[k]` | 2.44% |
| `pgbuf_unfix` | 1.97% | `LWLockAttemptLock` | 1.25% | `xas_descend` `[k]` | 1.67% |

`perf stat` over the same windows:

| Configuration | cycles | instructions | IPC | Gcycles/statement | Ginstr/statement | cycles per subquery execution | instructions per subquery execution |
|---|---|---|---|---|---|---|---|
| CUBRID native | 106,560,433,749 | 158,995,092,901 | **1.49** | 7.076 | 10.557 | **82,080** | **122,468** |
| PostgreSQL controlled | 84,347,628,560 | 104,225,517,590 | **1.24** | 3.082 | 3.809 | **35,755** | **44,181** |
| PostgreSQL native | 84,598,967,569 | 77,892,698,757 | **0.92** | 19.282 | 17.753 | 223,679 | 205,947 |

The controlled-pair cycles ratio, **7.076 / 3.082 = 2.2959x**, is an independent reconstruction of
`F_cpu = 2.185313x` from a counter the card does not use, agreeing to **+5.1%**.

Bands, converted to core-seconds per statement against each configuration's measured total query CPU
(`q20-bands.txt`):

| Band | CUBRID native | PostgreSQL controlled |
|---|---|---|
| buffer fix/unfix + LRU list surgery / buffer lookup+pin+replacement | 24.09% = **0.5944 core-s** | 32.26% = **0.3643 core-s** |
| per-row `DB_VALUE` materialisation / tuple access + visibility | 19.13% = **0.4720 core-s** | 30.77% = **0.3474 core-s** |
| generic predicate/comparator dispatch / expression + index compare | 11.50% = **0.2838 core-s** | 10.11% = **0.1142 core-s** |
| B-tree descent/search | 3.51% = 0.0866 core-s | (inside `_bt_compare`, above) |
| bands total | 58.23% = 1.4368 core-s | 73.14% = 0.8258 core-s |

Note the honest reading of the percentage columns: PostgreSQL's *shares* are higher, but its *total*
is 2.185x smaller, so CUBRID's absolute cost is larger in every band — 1.63x on buffer handling,
1.36x on row materialisation, 2.49x on predicate evaluation.

**PostgreSQL native's profile is dominated by the cost of its plan choice.** `rep_movs_alternative`
(19.38%) is the kernel page copy under `__libc_pread64 → vfs_read → xfs_file_read_iter →
filemap_read → copy_page_to_iter`; together with `filemap_get_read_batch`, `xas_descend`, `xas_load`
and `pg_checksum_block_fallback` — the checksum PostgreSQL computes on every page it *reads* —
**34.27% of the native profile, 2.3748 core-s of 6.9296 core-s per statement, is work that exists
only because the plan is not resident**. The controlled variant's figure for the same bands is
**0.00%**. IPC collapses to 0.92 in the native plan against 1.24 in the controlled one, for the same
reason.

## 7. Source contrast

| Item | CUBRID `file:line` | PostgreSQL `file:line` | Difference | Class |
|---|---|---|---|---|
| What an uncorrelated `IN (subquery)` becomes | `src/optimizer/rewriter/query_rewrite.c:292` calls `qo_rewrite_subqueries()`; `src/optimizer/rewriter/query_rewrite_subquery.c:40` walks the CNF list, `:73-75` admits `PT_IS_IN`, `:123` requires `arg2->info.query.correlation_level == 0`, `:165` calls `mq_make_derived_spec()` (`src/parser/view_transform.c:10918`) which appends the subquery to `FROM` as a **derived spec**, and `:219` recurses into that spec so the nested `IN` is rewritten too. A derived spec is materialised bottom-up and is **not** a relation the join-order search may reorder. Visible as three nested `av1861` specs and `temp(distinct)` in `q20-plan-est-cubrid.out`. | `src/backend/optimizer/plan/subselect.c:1341` `convert_ANY_sublink_to_join()`, with `:1450` `result->jointype = under_not ? JOIN_ANTI : JOIN_SEMI`. The sublink becomes a first-class **semi-join**, and every join order over `{supplier, nation, partsupp, part}` stays in the search space. Visible as `Nested Loop Semi Join` in `q20-plan-act-pg.out`. | CUBRID **fixes** the evaluation order at rewrite time; PostgreSQL **defers** it to the cost model. On Q20 the fixed order is the good one and the cost model picks the bad one, worth 6.2373x. | structural absence (of the choice itself) |
| Where the expensive correlated filter is evaluated | The `ps_availqty > (subquery)` term is a `sarg` on the `partsupp` `iscan` (`q20-plan-est-cubrid.out`: `sargs: term[1] ... subqs: 0`), and that `iscan` is driven by `ps_partkey` from the materialised `part` list, so it fires 86,204 times. | `src/backend/optimizer/path/costsize.c:636` `tuples_fetched = clamp_row_est(indexSelectivity * baserel->tuples)` and `:800` `cpu_run_cost += cpu_per_tuple * tuples_fetched` charge the `SubPlan` on every index-matched tuple — correctly. The qual is a `baserestrictinfo` on `partsupp`, so it is evaluated at whichever `partsupp` scan the chosen order produces: 80 rows per supplier × 4,054 suppliers in the native plan. | Same stage in both engines; the count differs only because the driving relation differs. 86,204 against 247,287 executions. | same stage, lower measured cost (**CUBRID better**) |
| Why PostgreSQL's cost model prefers the worse order | No counterpart — CUBRID never ranks the two orders (see row 1). | `src/backend/optimizer/path/costsize.c:636` uses `indexSelectivity`, which for `ps_partkey = p_partkey` comes from `pg_stats.n_distinct`. Measured: `partsupp.ps_partkey n_distinct = 444,930` against a true **2,000,000** — a **4.4952x** underestimate — while `partsupp.ps_suppkey n_distinct = 99,714` against a true 100,000 is accurate to 0.29% (`q20-pgstats-probe.out`). The estimator degrades on `ps_partkey` because that column is perfectly clustered (`correlation = 0.9999991`), which is exactly the case block-sampled distinct estimation handles worst. | PostgreSQL therefore believes each `part`-driven probe fetches `8,000,357/444,930 = 17.98` rows instead of 4, costing it `17.98 × 8.48 = 152.5` per loop (matching the planned `159.48`) instead of ≈40.9. That single asymmetry inverts the ranking: estimated 3,288,816 vs 2,812,921 (supplier-driven wins by 1.169x), where a correct `n_distinct` would give ≈892,203 vs 2,812,921 (part-driven wins by 3.15x) and the measured truth is 1.096253 s vs 6.837673 s. | same stage, lower measured cost (**CUBRID better**) |
| Per-page buffer handling on a hit | `src/storage/page_buffer.c` `pgbuf_fix_release` 13.00% and `pgbuf_lru_boost_bcb` 6.96% of the CUBRID profile; the boost path takes `pthread_mutex_lock(&lru_list->mutex)` and performs doubly-linked-list surgery plus zone rebalancing on unfix. 1,300,830 fetches/statement → **0.5944 core-s**. | `src/backend/storage/buffer/bufmgr.c` → `BufTableLookup` → `hash_search_with_hash_value` 17.34% and `PinBuffer` 8.13%: a hash probe plus an atomic refcount, no list and no per-unfix mutex. 1,033,307 fetches/statement → **0.3643 core-s**. | 1.259x more fetches but 1.632x more CPU → **1.30x more CPU per page fetch**. | same stage, lower measured cost |
| Materialising a row's attributes | `src/storage/heap_file.c:10464` `heap_attrinfo_read_dbvalues()` 3.88%, plus `spage_get_record` 5.45%, `or_mvcc_get_repid_and_flags` 3.31%, `mr_readval_string_internal` 1.86% and `__memmove_evex_unaligned_erms` 3.67% — per row, re-read the MVCC/representation header, re-resolve each attribute's domain, build fully-typed `DB_VALUE`s. **0.4720 core-s**. | `src/backend/executor/execTuples.c` `tts_buffer_heap_getsomeattrs` 11.45% plus `heap_page_prune_opt` 11.04% and `heap_hot_search_buffer` 6.49% — deform into a flat `Datum`/`isnull` array with no per-attribute domain resolution. **0.3474 core-s**. | 1.36x, on identical rows. | same stage, lower measured cost |
| Evaluating a scan predicate | `src/query/query_evaluator.c:1666` `eval_pred()` 3.69%, `:152` `eval_value_rel_cmp()` 2.51%, `tp_value_compare_with_error` 2.07%, `mr_cmpval_string` 1.71%, `pr_midxkey_compare` 1.45% — a generic `PRED_EXPR` tree re-walked and re-dispatched per row. **0.2838 core-s**. | `src/backend/executor/execExprInterp.c` `ExecInterpExpr` 3.43% plus `_bt_compare` 4.67% — the qual is compiled once into type-specialised `ExprEvalStep`s. **0.1142 core-s**. | 2.49x, on identical rows. | same stage, lower measured cost |
| Parallelising the dominant operator | `src/query/parallel/px_parallel.cpp:85-109` `compute_parallel_degree()`, `case parallel_type::SUBQUERY`, `:89-92` `auto_degree = 1` with the in-source `TODO`. The middle derived spec — 90.3% of the statement — is an uncorrelated subquery and runs at one active unit while `parallelism=6` is configured. | `src/backend/optimizer/plan/createplan.c` CTE paths: a `MATERIALIZED` CTE is likewise not parallelised; measured peak 1.4367 units, serial tail 4.979 s of a 4.92 s block. | **Neither engine parallelises it.** The defect binds on CUBRID but costs nothing against PostgreSQL on this query. | common to both engines |

**Absence claims — searched paths, symbols and patterns.** For "CUBRID never ranks the two join
orders", the searched paths were `src/optimizer/rewriter/query_rewrite.c`,
`src/optimizer/rewriter/query_rewrite_subquery.c`, `src/optimizer/query_graph.c`,
`src/optimizer/query_planner.c`, `src/optimizer/plan_generation.c` and
`src/parser/view_transform.c`; the searched symbols and patterns were `qo_rewrite_subqueries`,
`mq_make_derived_spec`, `mq_rewrite_query_as_derived`, `correlation_level`, `PT_IS_IN`,
`PT_EQ_SOME`, `derived_table`, `QO_TC_JOIN` and `JOIN_SEMI`. `qo_rewrite_subqueries()` has exactly
two `mq_make_derived_spec()` call sites (`:165` for `PT_EQ`/`PT_IS_IN`/`PT_EQ_SOME` and `:256` for
the `_SOME` comparison family) and both unconditionally append a derived spec; no path anywhere
produces a semi-join relation that the join-order search could reorder, and no cost comparison
between "flatten as derived spec" and any alternative exists.

## 8. Causal decomposition details

**The 6.2373x plan factor is the whole of Q20's cross-engine result, and it is PostgreSQL's.**
`F_plan = 0.160325x` is a same-engine, same-regime, same-gate A/B: PostgreSQL runs 6.837673 s on the
plan it chooses and 1.096253 s on a plan that returns byte-identical rows and that its own executor
builds without any hint, join reordering or semantic change — only an optimization fence. The
mechanism decomposes cleanly and every step is measured:

1. PostgreSQL drives from `supplier` rather than `part` → the `ps_availqty > (SubPlan)` filter is
   applied to 250,943 rather than 86,204 `partsupp` rows → the correlated `lineitem` aggregate runs
   **247,287** times instead of **86,204**, a factor of **2.8686x** (`loops` on both plans, plus a
   ground-truth `COUNT(*)` bracketing both: 324,320 Canadian `partsupp` rows before semi-join early
   exit, 86,204 `forest%` `partsupp` rows).
2. Those extra probes are scattered over an 11 GB `lineitem` index, pushing the working set past
   `shared_buffers=8192MB` → **589,094 physical page reads per statement** instead of **0**.
3. The physical reads cost **34.27% of the profile, 2.3748 core-s per statement**, in the kernel
   page-cache path plus the per-read page checksum, and drop IPC from 1.24 to 0.92.

2.8686x of work amplification and 2.3748 core-s of non-resident overhead account for the 6.2373x
between them: `CPU_P/CPU_Pc = 6.1372x` against a wall ratio of 6.2373x, the 1.6% gap being the
slightly lower utilization of the native plan (1.01345 against 1.02998).

**Root cause, quantified.** PostgreSQL's ranking of the two orders turns on one statistic.
`n_distinct(partsupp.ps_partkey) = 444,930` against a true 2,000,000 makes each `part`-driven probe
look 4.4952x fatter than it is; `n_distinct(partsupp.ps_suppkey) = 99,714` against a true 100,000 is
accurate. With the correct value the part-driven plan would be costed at ≈892,203 against the
supplier-driven 2,812,921 and PostgreSQL would choose it. The proximate reason the estimator fails
on one column and not the other is visible in the same catalog: `ps_partkey` has
`correlation = 0.9999991` (partsupp is stored clustered by part key) against `6.8e-05` for
`ps_suppkey`.

**Explanations considered and REJECTED by measurement.**

- *"CUBRID wins because it parallelises and PostgreSQL does not."* Rejected. CUBRID's parallelism is
  confined to a 122 ms `part` heap scan; 90.3% of its statement runs at one active unit. `F_units`
  is 0.831505x, i.e. worth only 1.2026x, and the matched-plan PostgreSQL variant is equally serial
  (peak 1.4367). Utilization explains 1.20 of a 3.43x win, not the win.
- *"CUBRID wins because it does less I/O."* Rejected as a *cause*. At matched plan shape **both**
  engines take zero physical reads (CUBRID trace `ioread: 0` and `/proc read_bytes` delta 0;
  PostgreSQL `heap_blks_read` delta 0 on all three derived blocks). The I/O difference is a
  *consequence* of PostgreSQL's plan choice, already counted inside `F_plan`; counting it again
  would double-count.
- *"CUBRID's optimizer made a better decision."* Rejected. CUBRID makes no decision: `:165` of
  `query_rewrite_subquery.c` appends a derived spec unconditionally for any uncorrelated `IN`, and
  a derived spec cannot be reordered. The good plan is the *only* plan CUBRID can build.
- *"CUBRID's low-residency 3.16 s level is its true single-query-repeat WARM level."* Rejected by
  the cold-pool A/B: from an empty buffer pool the identical statement reaches full residency within
  one statement and runs at 1.916–2.043 s. The 3.16 s level requires a pre-existing foreign working
  set and is inherited residency, precisely the effect `warm_establish.py` exists to remove.
- *"The residency hysteresis is the private-LRU 5,000-BCB cap (IMP-018)."* Rejected. That mechanism
  predicts a cold single session cannot accumulate its working set and that a foreign session's
  touch releases it; phase A shows the cold single session accumulating 7.5 GB in one statement and
  holding it for 30 statements, and phase C shows the foreign touch changing nothing.
- *"PostgreSQL's period-2 alternation is host noise or a sampling artifact."* Rejected: lag-1
  autocorrelation −0.9092, disjoint phases, and an exact one-to-one correspondence with a
  59,357-page difference in `heap_blks_read` on every statement of an independent probe.

**Error budget.** The card's inputs carry: median-of-3 statement timing with block-to-block spread
0.425–2.170%; sampler `U` cross-checked against `perf stat` at +0.27% (CUBRID) and −3.70/−5.53%
(PostgreSQL, direction explained above); `F_cpu` independently reconstructed from `perf` cycles at
+5.1%; `F_work` exact by direct count on both engines. The reconstruction residual is +0.0000% by
construction. No factor is claimed to more precision than these bounds support, and the qualitative
conclusion (`F_plan` dominates; CUBRID is behind at matched plan) survives every one of them by more
than an order of magnitude.

## 9. Improvements

**Q20 allocates NO new improvement ID. `next_id` remains `IMP-028`.** The Git ledger was synced and
searched by root-cause title, CUBRID source location, PostgreSQL source location and mechanism
before deciding. Every measured CUBRID-side effect on Q20 matched an existing root cause, so per
SSOT section 18 the existing entries receive Q20 relations and evidence rather than a duplicate ID.

| Existing entry | What Q20 adds | Measured on Q20 |
|---|---|---|
| **IMP-002** — data buffer replacement fails to retain a working set that marginally exceeds the pool; history-dependent equilibrium | The campaign's cleanest measurement of the equilibrium mode, with a **cold-pool A/B** that separates it from every competing explanation. Two self-consistent levels for the identical statement differing in nothing but residency. | **1.5874x** (3.162000 s → 1.992000 s) at constant plan, query text and page-fetch count (1,300,830 both states); trace `ioread` 204,665 → 0; working set 490,005 pages = **93.5% of the 524,288-page pool**; 40 consecutive self-repeats fail to escape the degraded state; from cold, residency is reached in **one** statement |
| **IMP-013** — every page unfix on a HIT path performs mutex-protected LRU list surgery | A matched-plan, matched-tuple, zero-physical-read comparison — the cleanest denominator this entry has had. | `pgbuf_fix_release` 13.00% + `pgbuf_lru_boost_bcb` 6.96% + `pgbuf_unfix` 1.97% + mutex 1.59% = **24.09% = 0.5944 core-s**, against PostgreSQL's `hash_search_with_hash_value`+`PinBuffer`+lock band 32.26% = 0.3643 core-s → **1.30x more CPU per page fetch** |
| **IMP-020** — per-row scan output materialised into fully-typed `DB_VALUE`s | Same matched pair, on identical rows. | **19.13% = 0.4720 core-s** against PostgreSQL's `tts_buffer_heap_getsomeattrs` band 30.77% = 0.3474 core-s → **1.36x** |
| **IMP-008** — scan-level sarg evaluation routes every row through the generic `DB_VALUE` comparator | Same matched pair. | **11.50% = 0.2838 core-s** against PostgreSQL's `ExecInterpExpr`+`_bt_compare` band 10.11% = 0.1142 core-s → **2.49x**, the largest per-band ratio on Q20 |
| **IMP-009** — parallel degree of an uncorrelated subquery hardcoded to 1 | A **constraint on the effect claim**, not just a confirmation. | The defect binds on **90.3%** of the CUBRID statement (serial tail 1.799 s of 1.992 s, one active unit, `parallelism=6` configured) yet contributes **zero** to the cross-engine gap, because PostgreSQL's matched-plan CTE is equally serial (peak 1.4367). Q20 bounds IMP-009's cross-engine value at ~0 for this shape while leaving its absolute headroom (up to ~1.8 s of serial work) intact |

**Ranking on Q20.** IMP-002 ranks first: it is the only entry whose Q20 effect is a *measured wall
number* (1.5874x) rather than a profile band, and it is the one that nearly caused this report to
publish a headline 58.7% too slow. IMP-013 ranks second (largest absolute band, 0.5944 core-s),
IMP-020 third (0.4720 core-s), IMP-008 fourth by absolute cost but first by ratio (2.49x), and
IMP-009 last on this query because its measured cross-engine contribution is zero. Together the
three profile bands account for 1.3502 core-s of CUBRID's 1.338359 core-s excess over PostgreSQL's
controlled plan (2.467478 − 1.129119), i.e. the bands over-cover the excess slightly because
PostgreSQL pays its own cost inside the same bands; the honest statement is that **all** of the
matched-plan CPU gap lives in buffer handling, row materialisation and predicate evaluation, and
none of it in the plan or in I/O.

**No CUBRID-side improvement is claimed from the 3.4326x headline win.** The win is PostgreSQL's
defect, and this campaign's ledger records CUBRID improvements. The PostgreSQL `n_distinct` finding
is recorded in sections 7 and 8 as a source contrast, not as a registry entry.

## 10. Evidence index

Format: `claim → raw file:line → formula → evidence type → SHA-256 (first 16)`.

| Claim | Raw evidence | Formula | Type |
|---|---|---|---|
| CUBRID median 1.992000 s | `raw/Q20/Q20-cubrid-headline-block1.json` `median_s` | median of `measured_times_s` | direct A/B |
| PostgreSQL median 6.837673 s | `raw/Q20/Q20-postgresql-headline-block1.json` `median_s` | median of `measured_times_s` | direct A/B |
| PostgreSQL controlled median 1.096253 s | `raw/Q20/Q20-postgresql-derived-headline-block1.json` `median_s` | median of `measured_times_s` | direct A/B |
| `R_wall = 0.291327x` | both headline JSONs | `T_C / T_P` | direct A/B |
| `F_plan = 0.160325x` | `Q20-postgresql-derived-headline-block1.json`, `Q20-postgresql-headline-block1.json` | `T_Pc / T_P` | direct A/B (same engine) |
| `F_units`, `F_cpu` | `Q20-cubrid-headline-telemetry.json`, `Q20-postgresql-derived-headline-telemetry.json`, `*-telemetry-stmt-times.json` | `U = total_query_cpu / Σ statement walls` | per-TID sampler |
| `F_work = 1.000000` (86,204 both engines) | `q20-trace-cubrid-resident.out` (`readkeys: 86204`), `q20-plan-act-pg-derived.out` (`loops=86204`), `q20-groundtruth-cubrid.out` / `q20-groundtruth-pg.out` (`partsupp_of_forest_parts,86204`) | direct count, three independent instruments | direct count |
| PostgreSQL native fires the subquery 247,287 times | `q20-plan-act-pg.out` `SubPlan expr_1 ... loops=247287` | direct count | direct count |
| PostgreSQL native reads 589,094 pages/statement | `q20-plan-act-pg.out` `Buffers: shared hit=2940804 read=589094`; `Q20-postgresql-headline-block*.json` `buffer_counters` delta 2,396,522 per 4 statements | delta / 4 | engine counter |
| PostgreSQL controlled reads 0 pages | `Q20-postgresql-derived-headline-block{1,2,3}.json` `buffer_counters` delta 0; `q20-plan-act-pg-derived.out` `read=0` | delta | engine counter |
| Period-2 alternation ↔ 59,357-page read difference | `q20-pgreads.out` (10 statements, `MARK` lines) | per-statement `heap_blks_read` delta vs `Time:` | direct A/B |
| CUBRID headline is resident | `Q20-cubrid-residency-block{1,2,3}.txt` (`read_bytes` 17837154304 unchanged), `q20-trace-cubrid-resident.out` (`ioread: 0`) | `/proc` delta + engine trace | procfs + engine counter |
| CUBRID low-residency level 3.162000 s / `ioread: 204665` | `Q20-cubrid-lowresident-headline-block1.json`, `q20-trace-cubrid.out` | median; trace counter | direct A/B |
| Residency hysteresis 1.5874x, cold-pool A/B | `q20-residency-driver.log` (phases A/B/C), `q20-resid-{A,C}-trace.out` | `3.162000 / 1.992000`; phase times | direct A/B (same engine, cold start) |
| CUBRID working set 490,005 pages = 93.5% of pool | `q20-residency-driver.log` phase A `syscr` delta; `data_buffer_size=8.0G` / 16 KiB = 524,288 | `490005 / 524288` | procfs + parameter |
| Profile bands and `perf stat` | `perf-stat-{cubrid,pg,pg-derived}.txt`, `profile-{cubrid,pg,pg-derived}-flat.txt`, `q20-bands.json` | share × measured total query CPU | profile attribution |
| `n_distinct(ps_partkey)=444,930` vs true 2,000,000 | `q20-pgstats-probe.out` | `pg_stats` vs `count(distinct)` | direct count |
| Correctness `result-equivalent-at-SF10`, 1,804 rows | `q20-correctness.json`, `q20-correctness-{cubrid,postgresql}.out` | section 11 comparator | direct comparison |
| Controlled variant returns identical rows | `q20-derived-result-pg.out` vs `q20-correctness-postgresql.out` | `diff` after delimiter normalisation | direct comparison |
| Preflight/postflight gates | `q20-preflight.txt`, `q20-postflight.txt` | section 7/9/10 checks | catalog + procfs |
| WARM gate derivation | `q20-warm-gate-params.txt`, `q20-convprobe-{cubrid,postgresql,postgresql-derived}.json` | phase-preserving moving-block bootstrap | derived |

Per-artifact byte size, SHA-256, creation command, producing stage and validity are recorded for all
promoted files in `reports/Q20/raw-manifest.json`.

## 11. Notion sync

**Out of scope for this worker session, by SSOT section 21's execution boundary.** The GJC/tmux
worker session runs on the remote build host and has no Notion connector; it must never attempt a
Notion write. Its Notion-adjacent duty ends at committing and pushing this report, the raw manifest
and the improvement-registry update to `origin/main`.

All Notion synchronisation for Q20 — operational-state update, the Q01–Q22 database row, the
improvement relations for IMP-002/IMP-008/IMP-009/IMP-013/IMP-020, and the section 21 content
richness requirements — is to be performed by the dedicated reconciler subagent with Notion tool
access, reading the pushed commit as source of truth. An idempotent backfill record keyed on
`campaign_id + QNN + session_id + report_commit + content_fingerprint` is appended to
`reports/notion_backfill_pending.jsonl` in the same push, so the sync can be reconciled later
without re-deriving anything from this session.

## 12. Completion checklist

| Gate (SSOT section 26) | Status |
|---|---|
| Preflight and correctness status recorded | **PASS** — `q20-preflight.txt` / `q20-postflight.txt`, `ssot_drift=NONE`, 0 off-cpuset both times, 8 FK / 8 `idx_fk_*` / 8 `convalidated`; correctness `result-equivalent-at-SF10`, 1,804 rows |
| Three valid headline values per completing engine | **PASS** — 3 accepted blocks × 3 measured statements per configuration; all load-gate verdicts `CLEAN` under both the strict per-sample and contract-window rules |
| Timeout confirmations | **N/A** — no timeout; slowest statement 7.50 s against 300 s |
| Plan, execution, profile, source contrast complete | **PASS** — sections 4, 5, 6, 7 |
| Causal card has evidence or explicit `UNMEASURED` | **PASS** — every factor numeric and measured; no `UNMEASURED` factor; residual +0.0000% with its limitation stated |
| Git improvement ledger deduplicated and committed | **PASS** — no new ID; `next_id` stays `IMP-028`; Q20 relations and evidence added to IMP-002/008/009/013/020 with a `q20_dedup_note` |
| Notion relations synced or idempotent backfill durable | **PASS (backfill)** — worker is barred from Notion writes by section 21; idempotent record appended to `reports/notion_backfill_pending.jsonl` |
| Every claim indexed to raw evidence and checksum | **PASS** — section 10 plus `raw-manifest.json` |
| Report, manifest, registry committed, pushed, reachable from `origin/main` | recorded in the raw manifest as `report_commit` |
| `QUERY_COMPLETE` emitted | see the status block below |
| Current session removed and absence verified | controller step after this push |

**Harness changes made during Q20** (promoted to `harness/` only where reusable): none to the
measurement harnesses themselves. `harness/measure_block.sh`, `headline_run.py`,
`warm_establish.py`, `telemetry_run.py` and `perf_run.sh` ran unmodified; Q20's WARM-gate parameters
were supplied through their existing environment overrides
(`TPCH_SSPQ_WARM_WINDOW=4`, `TPCH_SSPQ_WARM_LEVEL_TOL=0.020`, `TPCH_SSPQ_WARM_SPREAD=0.060`).

**Invalid / superseded evidence retained, not deleted.** The three low-residency CUBRID blocks are
preserved under `Q20-cubrid-lowresident-*` with their warm, bgload and sink artifacts. They are
**valid measurements of a real engine state** and are used as such in section 5; they are simply not
the section 12 headline, because they fail the physical-read half of the WARM proof. Two
single-statement telemetry runs (`Q20-*-telemetry.json`, no `-headline-`) are likewise retained but
are not card inputs, because on PostgreSQL they measure the burn-in statement; the block-regime
runs supersede them, and the PostgreSQL native block run was repeated under the tag `nativeblock`
after a tag collision destroyed the first one rather than being reconstructed from a log line.

```yaml
TPCH_SSPQ_STATUS:
  campaign_id: tpch-sspq-fk-r1-20260730
  query: Q20
  ssot_commit: 1b5fbc021353b16cf4b7375695fd6cad4ec4402d
  ssot_blob_sha: 510478846bff081d3223d3835069283a7cd2e47b
  session_id: gajae_code_msbcoz5r_9q99b9x2
  stage: 14.13-completion-checklist
  state: complete
  report_commit: see raw-manifest.json
  artifact_fingerprint: see raw-manifest.json
  timestamp: 2026-08-02T16:00:00+09:00
  next_action: QUERY_COMPLETE
```
