# TPCH-SSPQ FK campaign — Q19 report

TPC-H Query 19, Discounted Revenue.

## 1. Identity

| Field | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q19 |
| SSOT commit | `84d0d39c1d2c40d330cc55c1d13dbe4cc458355f` |
| SSOT blob SHA | `510478846bff081d3223d3835069283a7cd2e47b` |
| GJC session ID | `gajae_code_msb674z8_0rfkosdv` |
| Raw root | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q19` |
| Engine block order | Q19 is odd → CUBRID block first, then PostgreSQL (SSOT section 12) |
| Scale | TPC-H SF10, histogram-enabled controlled comparison |

| Engine | Source SHA | Install prefix | Binary SHA-256 | ELF Build ID |
|---|---|---|---|---|
| CUBRID | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9` | `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` | `4df41ee21300bf617bccd5e1d5c8522b074ef86e` |
| PostgreSQL | `5713b437abed7085e7d59849c6e9e0f4f469633d` | `/home/cubrid/pg/pg20devel-5713b437` | `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` | `5f2cb2987765c612638c278f85cfc85c211fffe1` |

Both running binaries were resolved through `/proc/<pid>/exe` and their SHA-256 matched the frozen
`reports/bootstrap/build-manifest.json` (`frozen: true`). Ownership gate `OK` on both engines
before and after every measurement block; `cub_master` pid 1433697 on port 1523, `cub_server`
pid 1612732, postmaster pid 1433696 on port 5442, all campaign-owned and unchanged between
`q19-preflight.txt` and `q19-postflight.txt`.

**Preflight (stage 14.1)** — `q19-preflight.txt`:

- `ssot_drift=NONE` (HEAD blob == pinned blob); `git status --porcelain -- tpch-sspq` empty at
  session start; branch `main`, `HEAD == origin/main == 84d0d39`.
- cpuset: 34 engine TIDs (cub_master 2, cub_server 24, postmaster 1, pg children 7),
  **0 off-cpuset** → PASS. External SUT-set load 0.276 core-s/s against the 6.0 threshold.
- Schema contract: CUBRID 8 FK-owned B-trees, PostgreSQL 8 FKs / 8 `idx_fk_*` / 8 `convalidated`,
  exact child-column order including composite `fk_lineitem_partsupp (l_partkey, l_suppkey)`.
- Row counts identical on both engines (lineitem 59,986,052; part 2,000,000).
- Statistics: CUBRID `update_statistics_update_histogram=y`, `default_histogram_bucket_count=300`;
  PostgreSQL `default_statistics_target=100`. PostgreSQL's per-table `last_analyze` reads `never`
  because `pg_stat_user_tables` was reset after bootstrap; the statistics themselves are present
  and were verified directly — `pg_statistic` holds 478 rows and `pg_stats` reports
  `l_partkey` 101 histogram bounds, `p_brand` 25 MCVs, `p_container` 40, `p_size` 50,
  `l_quantity` 50, `l_shipmode` 7, `l_shipinstruct` 4, i.e. every column Q19 predicates on.
- Parallel/buffer contract: CUBRID `parallelism=6`, `max_parallel_workers=100`,
  `data_buffer_size=8.0G`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`,
  `parallel_leader_participation=on`, `shared_buffers=8192MB`, `statement_timeout=300000 ms`,
  `jit=off`. Label: **configured node/gather-cap comparison**, **configured-equal buffer budget**.
- Query provenance: `queries/q19-cubrid.sql`, `queries/q19-pg.sql` and the canonical
  `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q19.sql` all SHA-256
  `fbe313a66a138e380b249c625864b77600c17fda915633dac2ed5d57b2f62937`. `queries/diff/q19.diff` is
  0 bytes and `cmp` confirms the two dialect files are byte-identical — **zero dialect changes**.

**Postflight** — `q19-postflight.txt`, captured after the last measurement block: same three PIDs
and executables, 36 engine TIDs with **0 off-cpuset**, external load 0.222 core-s/s, 8 FK / 8
`idx_fk_*` / 8 `convalidated` unchanged, `ssot_drift=NONE`, working tree still clean. The TID
count rose from 34 to 36 because the CUBRID parallel-query worker pool grew by two threads during
the run; both inherited the correct affinity, which is the condition SSOT section 9 requires.

`dynamic_shared_memory_type` is not decision-relevant here: neither engine's Q19 plan contains a
Parallel Hash Join, and PostgreSQL's `Gather` carries a single aggregate transition value per
worker (`rows=5`), so the section 9 `/dev/shm` consideration does not bind on this query.

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored; no timeout on either engine. The slowest single
statement was 46.67 s against the 300 s rule of section 13.

| Field | Value |
|---|---|
| Status | `result-equivalent-at-SF10` |
| Rows | 1 |
| `ORDER BY` present | no → canonical whole-row sort with duplicate multiplicity preserved |
| CUBRID output | `30104438.0911` |
| PostgreSQL output | `30104438.0911` |
| Absolute difference | 0 (byte-identical decimal text) |
| Tolerance allowed | 1e-12 × max(1, \|a\|, \|b\|) = 3.01e-05 |

Unlike most queries in this campaign the two engines emit the *same decimal text*, so the section
11 tolerance is not exercised at all. The tolerance is not being used to hide a different row set:
the row count is 1 on both sides, and the independent ground-truth probe (section 5) confirms both
engines aggregated the same **1,134** qualifying lineitem rows.

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
160.7196x = 121.4491x [plan] × 0.731010x [units] × 1.810304x [CPU-sec]

1.810304x [CPU-sec] = 1.000000x [work] × 1.810304x [cost]
```

`F_plan` is **numeric** and is anchored on a same-engine CUBRID native/controlled A/B.
Anchor direction: **CUBRID native → CUBRID controlled (`orextract`)**, where the controlled
variant is the campaign query plus one redundant, logically-implied part-only OR restriction —
precisely the clause PostgreSQL derives for itself in `extract_restriction_or_clauses()`
(`orclauses.c:75-118`). The controlled shape is therefore the one PostgreSQL reaches natively.
`F_units` and `F_cpu` are computed on the **remaining controlled cross-engine pair** — CUBRID
controlled versus PostgreSQL native — which execute the same plan shape over the same tuples
(section 4). Native and controlled denominators are not mixed.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `R_wall` | 160.7196x | wall seconds | median of 3 measured WARM statements, block1 | `T_C / T_P` | `Q19-cubrid-headline-block1.json`, `Q19-postgresql-headline-block1.json` | direct A/B |
| `F_plan` | 121.4491x | wall seconds | same engine, same block regime, same warm gate, 3 measured statements | `T_C / T_Cc` | `Q19-cubrid-headline-block1.json`, `Q19-cubrid-orextract-headline-block1.json` | direct A/B (same-engine controlled) |
| `F_units` | 0.731010x | core-seconds per wall-second | total query CPU over the 4-statement block ÷ sum of statement walls | `U_P / U_Cc` | `Q19-cubrid-orextract-headline-telemetry.json`, `Q19-postgresql-headline-telemetry.json` | per-TID sampler, actual timestamp deltas |
| `F_cpu` | 1.810304x | total query CPU-seconds | per measured statement, `U × t` | `CPU_Cc / CPU_P` | same two telemetry artifacts | per-TID sampler |
| `F_work` | 1.000000x | executor tuple reads (part heap rows + lineitem index rows) | one measured statement | `W_Cc / W_P` | `q19-trace-orextract.out`, `q19-plan-act-pg.out`, `q19-groundtruth-*.out` | direct count (engine trace + EXPLAIN loops, confirmed against ground truth) |
| `F_cost` | 1.810304x | core-seconds per executor tuple read | same | `(CPU_Cc/W_Cc)/(CPU_P/W_P)` | derived, `q19-causal-card.txt` | profile attribution |

Measured inputs (`q19-causal-card.txt`, `q19-causal-card.json`):

| Quantity | Value |
|---|---|
| `T_C` CUBRID native median | 46.514998 s |
| `T_Cc` CUBRID controlled (`orextract`) median | 0.383000 s |
| `T_P` PostgreSQL native median | 0.289417 s |
| `U_C` | 4.97273 core-s/wall-s |
| `U_Cc` | 4.96702 core-s/wall-s |
| `U_P` | 3.63094 core-s/wall-s |
| `CPU_C = U_C·T_C` | 231.306526 core-s |
| `CPU_Cc = U_Cc·T_Cc` | 1.902369 core-s |
| `CPU_P = U_P·T_P` | 1.050856 core-s |
| `W_C` | 61,986,052 tuple reads (2,000,000 part heap + 59,986,052 lineitem index) |
| `W_Cc` | 2,142,584 tuple reads (2,000,000 part heap + 142,584 lineitem index) |
| `W_P` | 2,142,584 tuple reads (2,000,000 part heap + 142,584 lineitem index) |

**`F_work` is exactly 1.000000, and that is a measurement rather than an assumption.** Both sides
of the controlled pair scan the whole 2,000,000-row `part` table (neither engine has an index on
`p_brand`/`p_container`/`p_size`) and both read exactly 142,584 lineitem index rows. The 142,584
is confirmed three independent ways: CUBRID's trace (`rows: 142584`), PostgreSQL's
`Index Scan ... loops=4754` with `Rows Removed by Filter: 30` per loop plus 1,134 returned
(4,754 × 30 + 1,134 = 143,754, the per-loop figure being a rounded average), and a direct
`COUNT(*)` ground-truth probe run on both engines that returns 142,584 on each. `F_cpu` is
therefore entirely `F_cost`, and Q19 gives this campaign a controlled pair in which the two
engines read *identical tuples* — the cleanest possible denominator for a per-tuple cost claim.

**Reconstruction residual: +0.0000%.** As on Q17 this must be read honestly: with
`F_plan = T_C/T_Cc` and `F_units × F_cpu = T_Cc/T_P` the product telescopes to `T_C/T_P` by
construction, so the residual tests arithmetic, not independence. The card's genuine validation is
that `U`, the only non-wall input, is confirmed by instruments the card does not use:

| Configuration | sampler `U` (block) | sampler executor-only | TWU (block) | single-statement `U` | `perf stat` CPUs utilized |
|---|---|---|---|---|---|
| CUBRID native | 4.97273 | 4.96406 | 4.9728 | 4.96333 | 5.020 |
| CUBRID controlled | 4.96702 | 4.94063 | 4.8257 | 4.73404 | 4.963 |
| PostgreSQL native | 3.63094 | 3.62270 | 3.5792 | 4.05172 | 4.632 |

On both CUBRID configurations every instrument agrees: block `U` against `perf stat` is +0.95%
and −0.08%, and against TWU it is +0.001% and −2.8%. **PostgreSQL's `perf stat` figure is not a
valid cross-check of `U_P` and is not used as one.** `perf stat` was captured over a 250-statement
back-to-back replay, whereas `U_P` is measured over the 4-statement contract block; at a 0.29 s
statement level the two regimes differ in how much of the wall is inter-statement worker
teardown, which is exactly the 27.6% gap seen. Within the block regime PostgreSQL's two
independent instruments — sampler `U` 3.63094 and TWU 3.5792, the latter weighted by actual
timestamp deltas — agree to 1.4%, and those are what the card rests on. The single-statement
figures are likewise a different denominator (one statement's busy window, no inter-statement
gaps) and are reported rather than substituted.

**Error budget.** CUBRID's `csql` timer quantum of 0.001 s is 0.0022% of `T_C` and 0.26% of
`T_Cc`; `psql` prints microseconds. Within-block standard deviations are CUBRID native 0.120567 s
(0.2592%), PostgreSQL 0.011471 s (3.9635%), CUBRID controlled 0.002517 s (0.6572%). PostgreSQL's
within-block spread is by far the largest and is not noise — it is the per-connection decay
discussed under the WARM proof below, and it biases the headline **against PostgreSQL**. No factor
in the card is claimed to a precision finer than 0.26%.

### 3-b. Headline timings

Regime `single-query-repeat WARM`, connection mode `single-connection-four-statements`
(1 uncounted warmup + 3 measured, one direct connection, no reconnect or prepare between
statements, all rows fully consumed into a campaign-owned sink under `work/Q19`).
Headline = block1 for every configuration, the first gated section-12 block after the WARM gate
passed. Blocks 2 and 3 are retained as block-to-block stability evidence.

| Field | CUBRID | PostgreSQL |
|---|---|---|
| measured statement 1 | 46.434998 s | 0.302977 s |
| measured statement 2 | 46.514998 s | 0.289417 s |
| measured statement 3 | 46.671999 s | 0.280171 s |
| **median (headline)** | **46.514998 s** | **0.289417 s** |
| mean | 46.540665 s | 0.290855 s |
| within-block standard deviation | 0.120567 s | 0.011471 s |
| uncounted warmup statement | 46.564999 s | 0.319201 s |
| sink bytes / SHA-256 prefix | 708 / `ba0e12160be7b67a` | 138 / `b262a5b4c911` |
| **median wall ratio** `T_C/T_P` | **160.7196** (PostgreSQL/CUBRID **0.006222x**) | |
| correctness | `result-equivalent-at-SF10` | |
| censoring | not censored; no timeout on either engine | |

Controlled variant (SSOT section 16 `F_plan` anchor), same regime and same gate:

| Field | CUBRID controlled `orextract` |
|---|---|
| measured statements | 0.385 / 0.383 / 0.380 s |
| **median** | **0.383000 s** |
| mean / sd | 0.382667 s / 0.002517 s |
| uncounted warmup | 0.388 s |
| sink bytes / SHA-256 prefix | 705 / `2012257dbd71` |

Three values only per configuration; no confidence interval is claimed.

Block-to-block stability (medians): CUBRID native 46.514998 / 46.146998 / 45.855998 s
(spread 1.4280%), PostgreSQL 0.289417 / 0.288229 / 0.290924 s (spread 0.9312%), CUBRID controlled
0.383 / 0.385 / 0.380 s (spread 1.3055%).

**Every one of the nine blocks was accepted on attempt 1** with load verdict `CLEAN` under the
strict per-sample rule (`TPCH_SSPQ_LOAD_VERDICT` left at its `verdict` default), so no block needed
the contract-window reading. External SUT-set load during the accepted headline blocks: CUBRID
mean 0.1928 max 1.1763, PostgreSQL mean 0.2575 max 2.0605, CUBRID controlled mean 0.2894 max
2.5911 core-s/s — all far under the 6.0 threshold. Because the PostgreSQL and controlled-variant
blocks are only 1.1–1.6 s of wall, the during-run load monitor was run at a 0.02 s period for
those two instead of the 0.25 s default, giving 70 and 78 samples rather than 4–6; CUBRID native's
183 s block kept the default and got 662 samples. This only makes the during-run gate finer, never
coarser (`harness/measure_block.sh`, `TPCH_SSPQ_BGLOAD_INTERVAL`).

**WARM gate parameters were derived, not guessed** (`q19-warm-gate-params.txt`). Q19 is the first
query in this campaign where the two engines' statement levels differ by more than two orders of
magnitude (45.9 s against 0.2715 s, 169x), so a single shared statement count is not derivable and
the counts are per engine, each justified against the same measured null:

- A 20-statement CUBRID probe and a 60-statement PostgreSQL probe established each stationary
  segment. A moving-block bootstrap (block length 6, 4000 reps) over those segments gave the null
  distribution of the gate's own half-split trend statistic at the lengths actually used:
  CUBRID n=12 p95 0.6029% / max 0.8425%; PostgreSQL n=30 p95 0.5267% / max 0.8021%.
- **CUBRID: 12 statements.** It is the gate's minimum (3×WINDOW) and already costs 9.2 min per
  block — 28 min of pure gate work over three blocks — while the probe shows CUBRID is at steady
  state from statement 2 (statement 1 is only +0.91% above plateau, inside its own 1.33%
  window=4 trailing spread).
- **PostgreSQL: 30 statements.** Its per-connection decay spans 7 statements (+19.8%, +11.8%,
  +7.1%, +5.0%, +4.7%, +2.2%, +0.8% off plateau). Applying the gate statistic to the *real* probe
  prefix gives −3.93% at n=12 — more than 3x the n=12 stationary-null max — and −0.50% at n=30.
  No tolerance can fix that without blinding the gate to a genuinely warming engine; the statement
  count has to clear the burn-in. At 0.2715 s a statement, 30 costs 8.2 s per block.
- `WINDOW` 4, `LEVEL_TOL` 2.0% (above both engines' stationary-null max at their own n),
  `SPREAD_SANITY` 4.5% (above each engine's observed window=4 trailing spread).
- All nine blocks converged: CUBRID native +0.0862% / −0.4348% / −0.0435%, PostgreSQL +0.2570% /
  +0.5348% / +0.7156%, CUBRID controlled +0.5222% / +0.2604% / +0.0000%.

**A per-connection decay survives inside PostgreSQL's contract block, and it is reported rather
than removed.** The section 12 block opens a *fresh* connection and times statements 2–4 of that
connection, so PostgreSQL's decay restarts even though `warm_establish.py` had just driven the
engine to steady state in a separate connection. The block's four statements read 0.3192 / 0.3030
/ 0.2894 / 0.2802 s, still descending, while the engine-level steady state measured immediately
before the same block was 0.267694 s. PostgreSQL's headline median of 0.289417 s is therefore
**8.11% above its own steady state**, which *understates* CUBRID's deficit: at both engines' steady
states the ratio would be 46.515 / 0.267694 = 173.8x rather than the reported 160.7x. The contract
fixes the block at one warmup plus three measured statements in one connection, so the contract
value is what is reported as the headline, with the direction of the bias recorded here.

**Physical-read evidence per configuration** — this is the single most important WARM observation
on Q19:

- **CUBRID native: cannot reach zero physical reads, by construction, and is not claimed to.** The
  engine's own trace reports `ioread: 14313083` on the lineitem index scan against `fetch:
  66035067`, i.e. a 78.33% buffer hit rate and **14.31 million misses per statement**. This is
  independently confirmed by procfs: the single-statement telemetry recorded `syscr` 14,339,369
  and `rchar` 234,928,017,320, which is 16,383.4 bytes per read — exactly one 16 KiB page per
  syscall — agreeing with the trace to 0.18%. Over the whole 4-statement block that is `syscr`
  57,353,960 and `rchar` 939.7 GB. Device reads were 1,632 sectors (0.80 MiB) on `sdb3`, so
  essentially all 234.9 GB per statement is served by the OS page cache at ~5.05 GB/s, costing CPU
  rather than device latency. The plan's working set — the lineitem heap alone is 682,937 pages =
  10.67 GiB, plus the `fk_lineitem_partsupp` index — provably exceeds the configured-equal 8192 MB
  budget, so full residency is impossible for the plan CUBRID chose. The engine is nevertheless at
  steady state in the sense the contract requires: the level converged, within-block sd is 0.26%,
  and the three block medians lie within 1.43%.
- **CUBRID controlled (`orextract`): zero physical reads.** Trace `ioread: 0` on the index scan and
  `ioread: 1` at the SELECT level; telemetry `syscr` 213 and `rchar` 332,300 for the entire block;
  device `sectors_read` 0.
- **PostgreSQL native: zero physical reads.** `EXPLAIN (ANALYZE, BUFFERS)` reports
  `Buffers: shared hit=197972` with no `read=` anywhere in the plan; telemetry `syscr` 1,184,
  `rchar` 3,991,107, device `sectors_read` 0.

The controlled cross-engine pair used for `F_units` and `F_cpu` is therefore a **zero-physical-read
pair on both sides**, which removes I/O residency as a confound from those two factors and confines
it entirely to `F_plan`.

CUBRID `statdump` buffer gauges again read a delta of exactly 0 over a whole block on this server
(the Q14/Q16/Q18 defect, reconfirmed on Q19). They are retained in the headline JSONs and
**excluded from every calculation**; the CUBRID buffer evidence above rests on the engine trace and
on `/proc`, which agree with each other to 0.18%.

## 4. Plan

### CUBRID — estimated (`SET OPTIMIZATION LEVEL 514`, no execution)

```text
idx-join (inner join)
    outer: sscan   class: part node[1]                     cost: 29353   card 2000000
                   -- NO sargs
    inner: iscan   class: lineitem node[0]
                   index: fk_lineitem_partsupp term[1]
                   sargs: term[0] AND term[2] AND term[3]  cost: 4       card 3978667
    sargs: term[0]                                         cost: 1929147 card 142

node[0]: dba.lineitem(59986052/682937) (sargs 2 3)
node[1]: dba.part(2000000/24353)            <- no sarg list at all

term[0]: (((p_brand='Brand#12' and p_container in {...} and l_quantity>=1 and l_quantity<=1+10
           and p_size between 1 and 5) or (p_brand='Brand#23' and ...) ) or (p_brand='Brand#34' and ...))
         (sel 3.56402E-05) (rank 3) (join term) (inner-join) (loc 0)
term[1]: part.p_partkey=lineitem.l_partkey (sel 5E-07) (join term) (mergeable) (indexable)
term[2]: lineitem.l_shipinstruct='DELIVER IN PERSON' (sel 0.25) (sarg term)
term[3]: lineitem.l_shipmode range ('AIR' = or 'AIR REG' =) (sel 0.265306) (sarg term)
```

### PostgreSQL — estimated (`EXPLAIN (COSTS, VERBOSE, SETTINGS)`, no execution)

```text
Finalize Aggregate  (cost=192603.80..192603.81 rows=1)
  -> Gather  (cost=192603.37..192603.78 rows=4)   Workers Planned: 4
       -> Partial Aggregate  (cost=191603.37..191603.38 rows=1)
            -> Nested Loop  (cost=0.44..191601.41 rows=261)
                 -> Parallel Seq Scan on part  (cost=0.00..62232.78 rows=1190)
                      Filter: ((p_size >= 1) AND
                               (   (p_brand='Brand#12' AND p_container = ANY('{SM CASE,...}') AND p_size <= 5)
                                OR (p_brand='Brand#23' AND p_container = ANY('{MED BAG,...}') AND p_size <= 10)
                                OR (p_brand='Brand#34' AND p_container = ANY('{LG CASE,...}') AND p_size <= 15)))
                 -> Index Scan using idx_fk_lineitem_partsupp on lineitem  (cost=0.44..108.70 rows=1)
                      Index Cond: (l_partkey = p_partkey)
                      Filter: (l_shipmode = ANY(...) AND l_shipinstruct='DELIVER IN PERSON'
                               AND (quantity ranges) AND (the full original 3-arm OR))
Settings: max_parallel_workers_per_gather = '5', max_parallel_workers = '5'
```

**The join method, the driving relation and the index are the same on both engines — and that is
what makes Q19 unusual.** Both pick `part` as the outer relation and index-probe `lineitem` on the
FK index `(l_partkey, l_suppkey)`. There is exactly one structural difference, and it is the whole
of `F_plan`: **PostgreSQL's `part` scan carries a filter and CUBRID's does not.**

PostgreSQL manufactured that filter. The user's `WHERE` clause contains no part-only conjunct at
all — every one of the three OR arms mixes `part` and `lineitem` columns, so the whole disjunction
is a *join* predicate. PostgreSQL nevertheless derives a redundant part-only clause from it
(`(arm1_part) OR (arm2_part) OR (arm3_part)`) and pushes it into the scan, cutting `part` from
2,000,000 rows to 4,754 before a single index probe happens. CUBRID has no such derivation: its
`term[0]` touches two nodes, is classified `QO_TC_JOIN`, and can only be evaluated where both
relations are available — at the join. Its `part` scan therefore has an empty sarg list and
estimated card 2,000,000, and it index-probes lineitem **once for every part key in the table**.

CUBRID *did* extract the two conjuncts it can: `l_shipinstruct` and `l_shipmode` are textually
identical in all three arms, so its OR-compaction factored them out into `term[2]`/`term[3]` and
attached them to the lineitem scan. The four predicates that *differ* between arms —
`p_brand`, `p_container`, `p_size`, `l_quantity` — could not be factored and stayed inside the
single join term. Section 7 pins this to the exact line that requires textual identity.

Those two extracted conjuncts do **not** rescue the plan, and the ground truth says why. They are
selective — only 2,141,904 of the 59,986,052 lineitem rows have
`l_shipmode in ('AIR','AIR REG') and l_shipinstruct = 'DELIVER IN PERSON'`, a 28.0x reduction —
but the index is on `(l_partkey, l_suppkey)`, so neither column can become an index *condition*.
They are attached to `node[0]` as data filters applied to rows the index scan has already fetched,
which is exactly what the trace shows: the scan reads all `rows: 59986052` and the reduction
happens afterwards. Only a restriction on the *driving* relation can cut the index band, and that
is the one CUBRID cannot derive.

### Actual plans (stage 14.6, separate non-headline runs, each configuration driven to its own steady state first)

CUBRID native trace (`q19-trace-cubrid.out`), one execution, `time: 52162` ms (instrumented, above
the 46.515 s headline):

```text
SELECT (time: 52162, fetch: 4, ioread: 2)
  SCAN (table: dba.part) (heap time: 52162, ioread: 0)
       (parallel workers: 5, heap time: 51591..52162, readrows: 399448..401913, gather: buildvalue)
    SCAN (index: dba.lineitem.fk_lineitem_partsupp)
       (btree time: 51819, fetch: 66035067, ioread: 14313083,
        readkeys: 9995954, filteredkeys: 7995955, rows: 59986052)
       (lookup time: 48121, rows: 1134)
```

CUBRID controlled `orextract` trace (`q19-trace-orextract.out`), `time: 387` ms:

```text
SELECT (time: 387, fetch: 4, ioread: 1)
  SCAN (table: dba.part) (heap time: 387, ioread: 0)
       (parallel workers: 5, heap time: 379..386, readrows: 399448..401913, gather: buildvalue)
    SCAN (index: dba.lineitem.fk_lineitem_partsupp)
       (btree time: 82, fetch: 156945, ioread: 0,
        readkeys: 23760, filteredkeys: 19006, rows: 142584)
       (lookup time: 75, rows: 1134)
```

PostgreSQL native `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, TIMING)` (`q19-plan-act-pg.out`),
`Execution Time: 310.229 ms` (instrumented, above the 289.4 ms headline):

```text
Finalize Aggregate (actual time=245.494..310.136 rows=1 loops=1)  Buffers: shared hit=197972
  -> Gather (actual time=245.349..310.125 rows=5 loops=1)   Workers Planned: 4  Workers Launched: 4
       -> Partial Aggregate (actual time=241.471..241.472 rows=1 loops=5)
            -> Nested Loop (actual time=2.525..241.338 rows=226.80 loops=5)
                 -> Parallel Seq Scan on part (actual time=0.178..105.736 rows=950.80 loops=5)
                      Rows Removed by Filter: 399049       Buffers: shared hit=40984
                 -> Index Scan using idx_fk_lineitem_partsupp (rows=0.24 loops=4754)
                      Index Searches: 4754                 Buffers: shared hit=156988
                      Rows Removed by Filter: 30
Planning Time: 1.442 ms
```

### Plan comparison summary

| Aspect | CUBRID native | CUBRID controlled (`orextract`) | PostgreSQL native |
|---|---|---|---|
| Join method | index nested loop, part outer | index nested loop, part outer | index nested loop, part outer |
| `part` rows scanned | 2,000,000 | 2,000,000 | 2,000,000 |
| `part` scan sargs | **none** | 27 CNF conjuncts | 1 extracted OR + `p_size >= 1` |
| `part` rows surviving into the join | **2,000,000** | **4,754** | **4,754** |
| lineitem index probes | 2,000,000 (one per part key) | 4,754 | 4,754 (`Index Searches: 4754`) |
| lineitem index rows read | **59,986,052** | **142,584** | **142,584** |
| Buffer accesses | 66,035,067 fetches | 156,945 fetches | 197,972 (`shared hit`) |
| Physical reads / statement | **14,313,083** | 0 | 0 |
| Result rows | 1,134 | 1,134 | 1,134 |
| Active units | 4.97 | 4.97 | 3.63 |
| Parallel workers | 5 | 5 | 4 launched + participating leader |
| Estimated cost | 1,929,147 | 29,357 | 192,604 |

Two points worth stating precisely:

1. **CUBRID's own cost model ranks the two plans correctly.** It costs the unfiltered plan at
   1,929,147 and the filtered one at 29,357 — a 65.7x preference for the filtered shape, which is
   the right direction and roughly the right magnitude against a measured 121.4x. This is *not* an
   optimizer-costing defect like Q17's or Q07's. CUBRID never gets to compare the two plans,
   because the filtered plan is not in its search space at all: no rewrite produces the part-only
   restriction. The defect is in plan *space*, not plan *choice*.
2. **The index scan is where the time goes, not the heap scan.** In the native trace the part heap
   scan and the whole statement both report 52,162 ms while the nested index scan reports 51,819 ms
   of btree time — 99.3% of the statement is inside the lineitem probe. In the controlled variant
   the same node drops to 82 ms of 387 ms.

## 5. Execution telemetry

Per-TID sampler pinned to collector CPUs 20-23, weighted by actual sample timestamp deltas.
Sampler period was set per configuration because the three blocks differ by 120x in wall: 0.1 s for
CUBRID native (1,654 samples over a 183 s block), 0.01 s for PostgreSQL (258 samples over 1.198 s)
and 0.01 s for CUBRID controlled (285 samples over 1.516 s).

| Quantity | CUBRID native | CUBRID controlled | PostgreSQL native |
|---|---|---|---|
| `t_block` (Σ statement walls) | 183.328 s | 1.516 s | 1.198 s |
| `executor_cpu` | 910.05 core-s | 7.49 core-s | 4.34 core-s |
| `auxiliary_query_cpu` | 1.59 core-s | 0.04 core-s | 0.01 core-s |
| `total_query_cpu` | 911.64 core-s | 7.53 core-s | 4.35 core-s |
| `U = total_query_cpu / t_block` | 4.97273 | 4.96702 | 3.63094 |
| time-weighted active units (TWU) | 4.9728 | 4.8257 | 3.5792 |
| max simultaneous active units | 5.4142 | 6.2374 | 8.1016 |
| busy window | 183.32 s | 1.56 s | 1.215 s |
| serial tail | 0.113 s | 0.000 s | 0.145 s |
| planned workers | 5 (trace `parallel workers: 5`) | 5 | 4 (`Workers Planned: 4`) |
| launched workers | 5 | 5 | 4 (`Workers Launched: 4`) |

Executor/auxiliary classification (`per_bucket_core_s`):

- **CUBRID native** executor 910.05 = `parallel-query` 907.57 + `transaction` 2.44 +
  `connections` 0.04; auxiliary 1.59 = `vacuum-master` 0.40 + `dwb-flush-block` 0.44 +
  `pgbuf-page-flus` 0.29 + `dwb-file-sync` 0.28 + `pgbuf-maintain` 0.08 + `pgbuf-flush-con` 0.05 +
  `deadlock-detect` 0.02 + `log-checkpoint`/`log-clock`/`session-control` 0.03. **99.7% of CUBRID's
  executor CPU is in the parallel-query worker pool.**
- **CUBRID controlled** executor 7.49 = `parallel-query` 7.47 + `transaction` 0.02; auxiliary
  0.04 = `dwb-flush-block` 0.02 + `vacuum-master` 0.02.
- **PostgreSQL** executor 4.34 = leader backend 1.00 + parallel workers 3.34; auxiliary 0.01 =
  postmaster. There is **no io-worker CPU at all**, because this plan takes zero buffer misses.

`unattributed_background` is nil in all three configurations: every sampled TID resolved to one of
the buckets above.

**`F_units` favours CUBRID on Q19, which is a reversal worth stating.** CUBRID reaches 4.97 active
units on both its configurations; PostgreSQL reaches 3.63. PostgreSQL's shortfall is not a worker
cap — it launched all 4 planned workers, and with a participating leader its ceiling is 5 — but the
serial fraction of a 0.29 s statement: `Gather` starts at 245.3 ms of a 310.1 ms instrumented run,
and worker startup and teardown are not free at this timescale (section 6 shows 40.6% of
PostgreSQL's CPU is kernel address-space work for exactly those forks and exits). CUBRID's worker
pool is pre-existing threads inside one `cub_server` process and pays none of that.

I/O over the telemetry block: **CUBRID native** process `rchar` 939,658,262,368 and `syscr`
57,353,960 against device `sectors_read` 1,632 (0.80 MiB on `sdb3`) — 939.7 GB of reads served by
the OS page cache, not the device, which is why they cost CPU rather than latency. **CUBRID
controlled** `rchar` 332,300, `syscr` 213, device reads 0. **PostgreSQL** `rchar` 3,991,107,
`syscr` 1,184, device reads 0. Write traffic on all three is checkpoint/WAL background.

CUBRID reached **5 active units against a configured `parallelism=6`** on both configurations —
the IMP-012 mechanism, recorded as a Q19 relation in section 9. It is not a binding factor here:
even at a full 6 units the controlled variant's 1.902 core-s would need 0.317 s against
PostgreSQL's 0.289 s.

## 6. Profile

Non-headline. `perf stat` and `perf record -F 999 -g --call-graph dwarf` attached to verified PID
sets (CUBRID: the single `cub_server` pid, all 30 query worker threads inside it; PostgreSQL: the
postmaster before the client connected, so inherit-on-fork covers the leader and every statement's
workers). `perf report` pinned to CPUs 20-23. Repeat counts were sized so the replay driver stays
busy across both sequential windows (`perf stat` then `perf record`): CUBRID native 4 repeats over
2×60 s, PostgreSQL 250 and CUBRID controlled 200 over 2×30 s.

| Configuration | samples | unresolved symbols | cycles | instructions | IPC | GHz | CPUs utilized | ctx-switches |
|---|---|---|---|---|---|---|---|---|
| CUBRID native | 300,748 | 0 | 861,571,470,313 | 676,277,913,957 | **0.78** | 2.860 | 5.020 | 719,243 |
| CUBRID controlled | 148,752 | 0 | 424,616,145,429 | 1,121,949,653,623 | **2.64** | 2.852 | 4.963 | 337,573 |
| PostgreSQL native | 142,066 | 0 | 399,986,922,441 | 471,764,152,468 | **1.18** | 2.878 | 4.632 | 2,645 |

CUBRID native's IPC of 0.78 against its own controlled plan's 2.64 is itself a measurement of what
the missing restriction costs: the same engine, on the same query, runs at **3.4x worse IPC**
because 14.3 million page-cache copies per statement destroy locality. The context-switch counts are *not* evidence for this and are
not used as such: normalised by window length CUBRID runs at 11,987/s native and 11,252/s
controlled — the same rate — against PostgreSQL's 88/s, so that column separates the two engines'
threading models, not the two CUBRID plans.

### Band decomposition (`q19-bands.txt`, exhaustive over the ≥0.3% symbol lines; unbanded remainder 0.00% in all three)

**CUBRID native** (profile total above threshold 87.26%, per-statement CPU 231.3065 core-s):

| Band | share | core-s |
|---|---|---|
| A kernel page-cache copy on the buffer-miss `pread` path | 30.25% | 69.970 |
| B buffer fix/unfix, LRU surgery, victim search | 29.25% | 67.657 |
| C buffer-pool mutex | 6.02% | 13.925 |
| D record/attribute materialisation and value lifecycle | 11.96% | 27.664 |
| E predicate / sarg evaluation | 8.36% | 19.337 |
| F scan driver / btree | 1.05% | 2.429 |
| G profiler self-cost (not engine work) | 0.37% | 0.856 |

**Bands A+B+C are 65.52% = 151.55 core-s of 231.31.** Two-thirds of everything CUBRID spends on
Q19 is buffer-miss machinery that exists only because the plan touches 60M lineitem index rows.
The call graph pins both halves exactly:

- `rep_movs_alternative` 22.48% is reached through
  `pgbuf_ordered_fix_release → pgbuf_fix_release → pgbuf_claim_bcb_for_fix → fileio_read →
  __libc_pread64 → entry_SYSCALL_64 → vfs_read → xfs_file_buffered_read → filemap_read →
  copy_page_to_iter → _copy_to_iter → rep_movs_alternative` — the kernel copying 16 KiB pages from
  the page cache into CUBRID's buffer pool, synchronously, on the query worker thread.
- `pgbuf_lru_boost_bcb` 6.35% is reached through
  `parallel_scan::task::loop → drain_slot_oids → qexec_execute_scan → scan_next_scan →
  scan_next_index_scan → heap_get_visible_version → heap_prepare_get_context →
  heap_prepare_object_page → pgbuf_unfix → pgbuf_unlatch_bcb_upon_unfix → pgbuf_lru_boost_bcb` —
  LRU list surgery on the *unfix* of a page that was already resident.

**CUBRID controlled** (89.98% above threshold, 1.9024 core-s):

| Band | share | core-s | ns / executor tuple read |
|---|---|---|---|
| E predicate / sarg evaluation | 56.53% | 1.07541 | 501.92 |
| D record/attribute materialisation and value lifecycle | 22.51% | 0.42822 | 199.86 |
| F scan driver / memmove | 5.66% | 0.10767 | 50.25 |
| B buffer fix/unfix, LRU surgery | 5.28% | 0.10045 | 46.88 |

**PostgreSQL native** (89.76% above threshold, 1.0509 core-s):

| Band | share | core-s | ns / executor tuple read |
|---|---|---|---|
| K kernel parallel-worker address-space setup and teardown | 40.60% | 0.42665 | 199.13 |
| E predicate / sarg evaluation | 19.74% | 0.20744 | 96.82 |
| D record/attribute materialisation and value lifecycle | 13.33% | 0.14008 | 65.38 |
| B buffer pin/lock/lookup and page pruning | 13.04% | 0.13703 | 63.96 |
| F scan driver / btree | 3.05% | 0.03205 | 14.96 |

### Top-cost symbols

CUBRID native: `rep_movs_alternative` [k] 22.48, `pgbuf_fix_release` 10.87, `pgbuf_lru_boost_bcb`
6.35, `eval_pred` 4.17, `__pthread_mutex_lock` 3.89, `pgbuf_unlatch_void_zone_bcb` 3.44,
`pgbuf_unfix` 3.19, `spage_get_record` 3.17, `filemap_get_read_batch` [k] 2.97,
`heap_attrinfo_read_dbvalues` 2.02.

CUBRID controlled: `eval_pred` 28.50, `tp_value_compare_with_error` 9.41,
`heap_attrinfo_read_dbvalues` 7.58, `eval_value_rel_cmp` 7.43, `lang_fastcmp_byte` 4.28,
`pgbuf_fix_release` 4.14, `mr_cmpval_char` 3.33, `mr_readval_char_internal` 2.66,
`__memmove_evex_unaligned_erms` 2.26, `pr_clear_value` 1.97.

PostgreSQL: `next_uptodate_folio` [k] 13.60, `tts_buffer_heap_getsomeattrs` 12.11, `ExecInterpExpr`
7.86, `bpchareq` 6.51, `_compound_head` [k] 6.48, `heap_page_prune_opt` 4.01, `filemap_map_pages`
[k] 3.94, `hash_search_with_hash_value` 3.73, `__memcmp_evex_movbe` 3.34,
`folio_remove_rmap_ptes` [k] 3.00.

**PostgreSQL's largest single band is not database code.** 40.60% of its Q19 CPU is kernel
address-space work, and the call graph shows both directions: `filemap_map_pages →
next_uptodate_folio` and `set_pte_range → folio_add_file_rmap_ptes` under
`postmaster_child_launch → BackgroundWorkerMain → ParallelWorkerMain → ParallelQueryMain →
standard_ExecutorRun`, i.e. each freshly forked parallel worker faulting in the 8 GB
`shared_buffers` mapping as it touches buffers; and `__x64_sys_exit_group → do_exit → exit_mm →
exit_mmap → unmap_vmas → zap_pte_range → zap_present_ptes → folio_remove_rmap_ptes` on the way
out. This is per-statement cost, not a replay artifact — PostgreSQL forks 4 workers for every
0.29 s Q19 statement in the contract block exactly as it does in the replay — and it is why the
`F_cost` figure understates CUBRID's per-tuple disadvantage: excluding band K entirely,
PostgreSQL's engine-side CPU is 0.624 core-s and `F_cpu` would be **3.05x** rather than 1.81x.
The card reports the measured 1.81x, which includes the tax, and this paragraph bounds the other
side.

### Banded comparison on the controlled pair (identical plan shape, identical tuple counts)

| Band | CUBRID controlled | PostgreSQL | Ratio |
|---|---|---|---|
| E predicate / sarg evaluation | 1.07541 core-s (501.92 ns/tuple) | 0.20744 core-s (96.82 ns/tuple) | **5.18x** |
| D materialisation and value lifecycle | 0.42822 core-s (199.86 ns/tuple) | 0.14008 core-s (65.38 ns/tuple) | **3.06x** |
| B buffer management | 0.10045 core-s | 0.13703 core-s | 0.73x (PostgreSQL higher) |

**Band E's 5.18x is an upper bound on per-comparison cost, not a clean per-comparison ratio, and
is used as such in section 9.** The controlled pair is not predicate-count-neutral: CUBRID
evaluates the extracted restriction as **27 distributed CNF conjuncts** (each a 3-way OR) because
that is the only form its rewriter can produce, while PostgreSQL evaluates one 3-arm OR plus
`p_size >= 1`. Band D's 3.06x *is* clean — both engines materialise the same 2,142,584 tuples and
the same columns — and it is the ratio section 9 attributes to IMP-020.

## 7. Source contrast

| Item | CUBRID file:line | PostgreSQL file:line | Difference | Class |
|---|---|---|---|---|
| Deriving a single-relation restriction from a join OR-of-ANDs | **No counterpart exists.** A term's evaluation site is fixed by how many relations its segments touch: `src/optimizer/query_graph.c:2508` `n = bitset_cardinality (&(QO_TERM_NODES (term)))`, then `:2536-2540` `n == 1 → QO_TERM_CLASS = QO_TC_SARG` bound to that node and `:2542-2544` `n == 2 → QO_TC_JOIN`. Q19's disjunction touches `part` and `lineitem`, so it is `QO_TC_JOIN` at `loc 0` and nothing in the optimizer manufactures an additional `n == 1` term from it. Visible as `node[1]: dba.part(2000000/24353)` with no sarg list in `q19-plan-est-cubrid.out`. | `src/backend/optimizer/util/orclauses.c:75-118` `extract_restriction_or_clauses()` walks each baserel's `joininfo`, and for every `restriction_is_or_clause(rinfo) && join_clause_is_movable_to(rinfo, rel)` calls `:156-245` `extract_or_clause()`, which requires only that **each arm contribute at least one clause mentioning only that rel** (`:204`/`:213` `is_safe_restriction_clause_for`, defined `:126-140` as `bms_equal(rinfo->clause_relids, rel->relids)`), returning `make_orclause(clauselist)` at `:243`. `:250-330` `consider_new_or_clause()` accepts it if `or_selec <= 0.9` and appends it to `rel->baserestrictinfo` at `:296`, then rescales the join clause's cached selectivity so the joinrel estimate is unchanged. Called from `src/backend/optimizer/plan/planmain.c:269`. | PostgreSQL turns a pure join predicate into a base-relation filter that cuts `part` from 2,000,000 to 4,754 rows and the lineitem index band from 59,986,052 to 142,584 rows. CUBRID cannot express the derivation, so it index-probes lineitem once per part key in the table. Measured at **121.4491x wall** by the same-engine A/B. | **structural absence** |
| Factoring a conjunct out of an OR | `src/parser/cnf.c:637-750` (`pt_transform_cnf_post`, `case PT_OR`) removes a conjunct from both OR sides only when the two are **textually identical**: `:673-694` computes a `pt_calculate_similarity` fingerprint, and on a match `:697-706` calls `parser_print_tree()` on each side and compares with `pt_str_compare(..., CASE_SENSITIVE)`; only then is the conjunct moved to `common_list` at `:715`. That is why `l_shipinstruct='DELIVER IN PERSON'` and the `l_shipmode` range — byte-identical in all three arms — became `term[2]`/`term[3]`, while `p_brand`, `p_container`, `p_size` and `l_quantity`, which differ per arm, could not be. | `src/backend/optimizer/prep/prepqual.c:509-560` `process_duplicate_ors()` implements the same inverse-OR-distributive-law factoring, and PostgreSQL's `p_size >= 1` conjunct in the `part` filter is its output (`BETWEEN` is expanded to two comparisons at parse time, so the shared lower bound is a separate, identical conjunct that CUBRID's atomic `PT_BETWEEN` node hides). PostgreSQL does not have to rely on it for the hard case, because `orclauses.c` covers the non-identical arms. | Both engines have common-conjunct factoring; only PostgreSQL also has per-relation extraction. On Q19 the factoring difference alone is worth nothing — `p_size >= 1` is true for every row of `part` — so this row is recorded to delimit the finding, not to add cost. | common to both engines |
| Distributing an OR into CNF at all | `src/parser/cnf.c:462-492` `count_and_or()` scores a conjunct's distributed CNF size, **multiplying over OR arms and adding over AND arms** (`:478-484`), and `:988` selects `TRANSFORM_CNF_AND_OR` (full distribution) at `<= 100` and `TRANSFORM_CNF_OR_COMPACT` (keep the OR whole) above it. Q19's own disjunction scores 8³ = 512 and is kept whole; the restriction added by the controlled variant scores 3³ = 27 and is distributed into the 27 conjuncts seen in `q19-plan-est-orextract.out`. So even when CUBRID *is* handed a single-relation OR it materialises it as up to 27 sargs rather than one. | PostgreSQL keeps the extracted clause as a single `BoolExpr` OR (`make_orclause` at `orclauses.c:243`) and compiles it once into `ExprEvalStep`s; `q19-plan-act-pg.out` shows one `Filter` with one OR. | CUBRID's only route to a per-relation sarg is full distribution, whose cost grows as the product of arm sizes and which is switched off exactly when the predicate is large. This is why the improvement in section 9 is not "call `count_and_or` with a bigger limit". | **structural absence** |
| Serving a data-page buffer miss | `src/storage/page_buffer.c:8464` — inside `pgbuf_claim_bcb_for_fix()` (`:8338`), a miss calls `fileio_read (thread_p, fileio_get_volume_descriptor (vpid->volid), &bufptr->iopage_buffer->iopage, vpid->pageid, IO_PAGESIZE)`; `src/storage/file_io.c:3956` `fileio_read()` calls `fileio_os_read()` (`:3870`), which is a bare `pread (vol_fd, io_page_p, count, offset)` at `:3918` — one synchronous single-page syscall on the query worker thread, no batching, no readahead. Measured: 14,339,369 preads of exactly 16,383.4 bytes per statement, 22.48% of the profile in the kernel copy alone. | `src/backend/storage/buffer/bufmgr.c:1938` `AsyncReadBuffers()` submits the read through `smgrstartreadv(ioh, ...)` at `:2153` against an AIO handle, with `io_method` defaulting to `IOMETHOD_WORKER` (`src/include/storage/aio.h:42`, `src/backend/storage/aio/aio.c:74`), so the copy happens in a separate io worker and the backend waits in `WaitReadBuffers()` (`:1759`). On Q19 PostgreSQL never enters this path — it takes zero misses. | On Q19 the difference is not exercised by PostgreSQL at all; it is CUBRID's amplifier. Every one of the 14.3M misses that the missing OR-extraction creates is paid in-line on the executor thread. Effect is inside `F_plan`, not `F_cpu`. | same stage, lower measured cost |
| Evaluating a scan-level predicate | `src/query/query_evaluator.c:1666` `eval_pred()` walks the `PRED_EXPR` tree per row and reaches `src/object/object_domain.c:10404` `tp_value_compare_with_error()` through `eval_value_rel_cmp`, which resolves the domain and dispatches to `mr_cmpval_char`/`lang_fastcmp_byte` per comparison. Controlled pair: 1.07541 core-s, 501.92 ns per executor tuple read. | `src/backend/executor/execExprInterp.c` `ExecInterpExpr()` runs a qual compiled once into type-specialised steps calling `bpchareq` (`src/backend/utils/adt/varchar.c`) and `ExecEvalScalarArrayOp` directly. Controlled pair: 0.20744 core-s, 96.82 ns per executor tuple read. | 5.18x, but see the caveat in section 6: CUBRID is evaluating 27 conjuncts to PostgreSQL's one, so this is an upper bound on per-comparison cost, not a clean denominator. | same stage, lower measured cost |
| Materialising scan output | `src/storage/heap_file.c` `heap_attrinfo_read_dbvalues()` 7.58%, with `mr_readval_char_internal` 2.66%, `pr_clear_value` 1.97%, `db_value_domain_init` 1.12%, `pr_type_from_id` 1.12%+0.58% — 0.42822 core-s, 199.86 ns per executor tuple read on the controlled pair. | `src/backend/executor/execTuples.c` `tts_buffer_heap_getsomeattrs()` → `slot_deform_heap_tuple()` 12.11%, with `pg_detoast_datum_packed` 0.77% — 0.14008 core-s, 65.38 ns per executor tuple read. | **3.06x on identical tuple counts and identical columns.** This is the clean band on Q19. | same stage, lower measured cost |

**Claims of absence were searched, not assumed.** For a CUBRID counterpart to
`extract_restriction_or_clauses` the searched paths were `src/optimizer/query_graph.c`,
`src/optimizer/query_planner.c`, `src/optimizer/plan_generation.c`,
`src/optimizer/rewriter/query_rewrite*.c` and `src/parser/cnf.c`; the searched symbols and patterns
were `CNF`, `conjunctive normal`, `or_next`, `PT_OR`, `QO_TC_SARG`, `QO_TC_JOIN`, `qo_analyze_term`
and `count_and_or`. What exists is (a) the CNF distribution/compaction pass in `cnf.c` and (b) the
node-cardinality term classifier in `query_graph.c:2508-2544`. Neither derives a *new, redundant*
single-relation clause from a multi-relation OR, which is the specific operation `orclauses.c`
performs. The related comment at `query_graph.c:2047` — *"only interesting in one predicate term;
if 'term' has 'or_next', it was derived from OR term"* — guards `qo_analyze_term`'s indexability
analysis at `:2051` and confirms that a term carrying `or_next` is deliberately excluded from
single-predicate treatment.

## 8. Causal decomposition details

The 160.7196x median wall gap decomposes into three separately measured factors.

**`F_plan` = 121.4491x — a redundant clause PostgreSQL derives and CUBRID cannot.**
Adding one logically-implied part-only OR restriction to the query text and changing nothing else
moves CUBRID from 46.514998 s to 0.383000 s in the same block regime, through the same gate, with
the same 12-statement warm-up, returning the byte-identical `30104438.0911`. That single factor removes
**99.80% of the absolute wall gap** (46.132 s of the 46.226 s that separates the two engines) and
accounts for 94.5% of it on a log scale; everything else on Q19 is worth 1.32x combined.

The anchor decomposes further, and the two halves multiply to the CPU ratio:

| Quantity | CUBRID native | CUBRID controlled | ratio |
|---|---|---|---|
| executor tuple reads | 61,986,052 | 2,142,584 | **28.93x** |
| CPU per tuple read | 3,731.59 ns | 887.89 ns | **4.20x** |
| total CPU | 231.3065 core-s | 1.9024 core-s | 121.59x |
| active units `U` | 4.97273 | 4.96702 | 1.001x |

So the plan factor is 28.93x more tuples **times** 4.20x more CPU per tuple, at essentially
identical utilization. The per-tuple half is entirely the buffer misses: 14,313,083 physical reads
per statement against 0, 65.52% of native CPU in bands A+B+C, IPC 0.78 against 2.64.

**`F_units` = 0.731010x — CUBRID parallelises better than PostgreSQL here.**
`U_Cc` 4.96702 against `U_P` 3.63094. This is not inferred from `parallelism=6`: it is the measured
ratio of total query CPU to summed statement wall, cross-checked by TWU from actual timestamp
deltas (4.8257 / 3.5792) and, on the CUBRID side, by `perf stat` CPUs-utilized (4.963). PostgreSQL
launched every worker it planned; its shortfall is the serial head and tail of a 0.29 s statement
plus the fork/exit cost of section 6's band K. This is the first factor in the campaign where the
parallel comparison runs in CUBRID's favour, and it is reported as such.

**`F_cpu` = 1.810304x — decomposed as `F_work` 1.000000x × `F_cost` 1.810304x.**
`F_work` is exactly 1: on the controlled pair the two engines read the same 2,000,000 part heap
rows and the same 142,584 lineitem index rows, confirmed by engine trace, `EXPLAIN` loop counts and
an independent `COUNT(*)` on both engines. The entire remaining difference is per-tuple cost:
887.89 ns against 490.46 ns, both engines warm with zero physical reads and the same plan shape.
Section 6 attributes it: materialisation 3.06x per tuple (clean), predicate evaluation 5.18x
(upper bound), partially offset by CUBRID's 0.73x *lower* buffer-management band — and note that
PostgreSQL is simultaneously paying 0.42665 core-s, 40.6% of its total, in kernel worker
fork/exit, without which `F_cpu` would be 3.05x.

**Explanations considered and rejected**, with the number that rejected each:

1. *"CUBRID picked the wrong plan; its cost model prefers the unfiltered shape."* **Rejected by
   measurement.** CUBRID costs the unfiltered plan at 1,929,147 and the filtered one at 29,357
   (`q19-plan-est-cubrid.out`, `q19-plan-est-orextract.out`) — a 65.7x preference in the *correct*
   direction against a measured 121.4x. The optimizer would choose the filtered plan instantly if
   it could see it. Q19 is a plan-**space** defect, not a plan-**choice** defect, which is what
   separates it from IMP-011 and IMP-014 and is why it needs its own root cause.
2. *"The cost is CUBRID's CNF distribution: emulating the extraction produces 27 sargs where
   PostgreSQL has one, so CUBRID is paying for 27 predicate evaluations per part row."*
   **Rejected by measurement.** A weaker *conjunctive envelope* form of the same restriction
   (`p_brand in (3)`, `p_container in (12)`, `p_size between 1 and 15`) distributes to only **3**
   sargs, and it is **slower**, not faster: 0.804 s traced against the 27-sarg variant's 0.387 s,
   because the looser filter passes 646,526 lineitem index rows instead of 142,584
   (`q19-trace-envelope.out` against `q19-trace-orextract.out`). Cost tracks the rows the
   restriction fails to eliminate, not the number of conjuncts.
3. *"Then the conjunct form is irrelevant."* **Also rejected — by a measurement that cuts the other
   way, and this one changes the improvement's implementation direction.** A third form expressing
   the *same* restriction with the same selectivity (`q19-oneterm.sql`, 28 sargs, identical index
   band: `rows: 142584`, `readkeys: 23760`, `fetch: 156945`) runs at a gated median of **0.293 s**
   against the anchor's 0.383 s — 1.31x faster, and within **1.24%** of PostgreSQL's 0.289417 s.
   So the residual 1.32x cross-engine gap is not intrinsic to CUBRID's executor; it is sensitive to
   the exact conjunct form the rewriter emits. This variant was originally constructed as a control
   that would express the restriction as **one** term by pushing `count_and_or` above its 100
   threshold, and **it failed at that stated goal** — CUBRID's range rewriter re-merged the added
   bounds and the clause still distributed (28 part sargs, not 1). It is therefore reported as a
   predicate-*form* probe, not as the `F_plan` anchor, and the faithful 3-arm emulation
   (`q19-orextract.sql`, exactly what `extract_or_clause` builds) remains the anchor. Its
   consequence for section 9 is concrete: an implementation must care how the extracted clause is
   materialised, not merely that it exists.
4. *"CUBRID's disadvantage is the buffer manager (IMP-002/IMP-007/IMP-013)."* **Rejected as the
   root cause, accepted as the amplifier.** Bands A+B+C are 151.55 core-s of CUBRID native's
   231.31 — an enormous number — but the controlled variant on the same engine, same buffer pool
   and same settings takes **zero** physical reads. The 14.3M misses per statement are created by
   the plan, so they belong inside `F_plan`; there is no separable buffer-budget finding on Q19,
   and the configured-equal 8192 MB budget is entirely adequate for the plan CUBRID could not
   reach. The relations recorded in section 9 are scoped accordingly.
5. *"PostgreSQL wins on parallelism."* **Rejected by measurement, in the opposite direction.**
   `U_P` 3.63094 against `U_Cc` 4.96702; `F_units` is 0.731010x, i.e. utilization is a CUBRID
   *advantage* on Q19 worth 1.37x, and PostgreSQL wins the query anyway.
6. *"CUBRID's parallel-scan trace counters are inflated by the IMP-005 (k−1) merge, so the
   59,986,052 and 142,584 figures cannot be trusted."* **Rejected by ground truth.** The controlled
   variant's traced index band of 142,584 equals the independent `COUNT(*)` probe exactly, on both
   engines; the native variant's 59,986,052 equals the exact lineitem row count; and both traces
   report `lookup rows: 1134`, the exact result cardinality. At Q19's plan depth the merge artifact
   does not appear, which bounds IMP-005's scope rather than undermining these numbers.

Effects are not summed: `F_plan`, `F_units` and `F_cpu` multiply, and `F_work`/`F_cost` decompose
`F_cpu` alone. The physical reads and the buffer bands are named once, inside `F_plan`, which owns
them.

## 9. Improvements

The registry was synced and searched by title, CUBRID source location, PostgreSQL source location
and root cause before any decision. Q19's dominant finding matches **no existing entry**: the
closest optimizer candidates are IMP-011 (join plan selection is parallel-degree blind), IMP-014
(multi-column FK join selectivity), IMP-019 (`qo_comp_selectivity` fallback), IMP-003 and IMP-022
(LIKE selectivity) — all of them are *costing* defects that mis-rank plans the optimizer can
already build. Q19's defect is that the better plan is **absent from the search space**, and
CUBRID's own cost model prefers it 65.7x once it is handed over. That is a distinct root cause and
receives a new ID.

**ID allocation note.** The Git ledger moved during this query. At Q19 session start `next_id` was
`IMP-024`; by the time this report was ready to push, `origin/main` had advanced by two commits
that allocated **IMP-024** (Q10, GROUP BY key not reduced by functional dependency), **IMP-025**
(Q16, uncorrelated `NOT IN` anti-join evaluated as an O(n) linear scan) and **IMP-026** (Q10,
sort-key collation compare with no abbreviated key), moving `next_id` to `IMP-027`. Per SSOT
section 18 the Git ledger is the canonical allocation authority, so the Q19 candidate was
**re-allocated from IMP-024 to IMP-027** against the updated ledger rather than pushed over the
collision, and the deduplication search was re-run against the three newly arrived entries. None
of them shares Q19's root cause: IMP-024 is about the *width* of a GROUP BY key, IMP-025 about
membership-test data structure inside an anti-join, IMP-026 about string-comparison representation
during a sort. None concerns deriving a base-relation restriction from a join predicate. The
`ssot_commit` pinned by this session was unaffected — `origin/main`'s `SSOT.md` blob is still
`510478846bff081d3223d3835069283a7cd2e47b`, so there was no `SSOT_DRIFT` and no measurement was
invalidated.

### IMP-027 (new) — no per-relation restriction is derived from a join OR-of-ANDs

| Field | Value |
|---|---|
| ID | `IMP-027` |
| Root cause | A join predicate that is an OR of per-relation AND groups yields no single-relation restriction, so every base scan under it runs unfiltered and the join drives the entire inner relation |
| Priority | **P0** — 121.4491x measured wall on Q19 (46.514998 s → 0.383000 s), removing 99.80% of the absolute cross-engine wall gap; the largest single factor in this campaign |
| Category | optimizer |
| Difficulty | medium |
| Status | `measured` |
| Q relations | Q19 (primary) |

**Mechanism, CUBRID side.** `qo_analyze_term()` fixes a term's evaluation site from the number of
relations its segments touch: `src/optimizer/query_graph.c:2508`
`n = bitset_cardinality (&(QO_TERM_NODES (term)))`, then `:2536-2540` `n == 1 → QO_TC_SARG` bound to
that node, `:2542-2544` `n == 2 → QO_TC_JOIN`. Q19's disjunction touches `part` and `lineitem`, so
it is a join term and is evaluated only at the join. The only two mechanisms that can turn an OR
into a single-relation sarg are (a) full CNF distribution, gated at
`src/parser/cnf.c:988` by `count_and_or() > 100` where `count_and_or` (`:462-492`) *multiplies*
over OR arms — Q19's own predicate scores 8³ = 512 and is excluded — and (b) common-conjunct
factoring at `src/parser/cnf.c:637-750`, which requires the conjuncts to be **textually identical**
across arms (`parser_print_tree` + `pt_str_compare` at `:697-706`). Q19's `l_shipmode` and
`l_shipinstruct` are identical and were factored; `p_brand`, `p_container`, `p_size` and
`l_quantity` differ per arm and were not. Result: `node[1]: dba.part(2000000/24353)` with an empty
sarg list, 2,000,000 index probes, 59,986,052 lineitem index rows and 14,313,083 physical reads per
statement.

**Mechanism, PostgreSQL side.** `extract_restriction_or_clauses()`
(`src/backend/optimizer/util/orclauses.c:75-118`, called from
`src/backend/optimizer/plan/planmain.c:269`) examines each baserel's `joininfo` for OR clauses
movable to that rel and calls `extract_or_clause()` (`:156-245`). That function requires only that
**each arm contribute at least one clause mentioning only that rel** — arms need not agree —
using `is_safe_restriction_clause_for()` (`:126-140`, `bms_equal(rinfo->clause_relids,
rel->relids)`), and returns `make_orclause(clauselist)` at `:243`. `consider_new_or_clause()`
(`:250-330`) keeps it when `or_selec <= 0.9`, appends it to `rel->baserestrictinfo` at `:296`, and
rescales the original join clause's cached selectivity so the joinrel row estimate is unchanged.
On Q19 that clause cuts `part` from 2,000,000 to 4,754 rows before any index probe.

**Quantified effect, mapped to named counters.** Same-engine A/B, both configurations gated,
warm-proved and returning `30104438.0911`:

| Named counter | CUBRID native | CUBRID + extracted restriction | Change |
|---|---|---|---|
| headline median wall | 46.514998 s | 0.383000 s | **121.4491x** |
| `part` rows entering the join | 2,000,000 | 4,754 | 420.7x |
| lineitem index rows (trace `rows:`) | 59,986,052 | 142,584 | 420.7x |
| executor tuple reads | 61,986,052 | 2,142,584 | 28.93x |
| trace `ioread` per statement | 14,313,083 | 0 | eliminated |
| `/proc` `syscr` per statement | 14,339,369 | ~53 | eliminated |
| total query CPU per statement | 231.3065 core-s | 1.9024 core-s | 121.59x |
| IPC (`perf stat`) | 0.78 | 2.64 | 3.4x |
| profile bands A+B+C (buffer-miss machinery) | 65.52% / 151.55 core-s | 5.28% / 0.10 core-s | eliminated |

**Implementation direction.** Add a per-relation restriction-extraction pass over `QO_TC_JOIN`
terms whose `pt_expr` is an OR: for each participating node, walk the OR arms and collect, per arm,
the conjuncts whose segments lie entirely in that node; if **every** arm yields at least one, emit
their disjunction as a new `QO_TC_SARG` term on that node and mark it redundant so join
selectivity is not double-counted (PostgreSQL's `consider_new_or_clause` rescaling at
`orclauses.c:300-329` is the reference for that bookkeeping, and `qo_analyze_term`'s existing
selectivity path is where the compensation must land). Two Q19-specific constraints on the
implementation, both measured rather than assumed:
(a) the derived term must **not** be routed through `count_and_or`'s distribution path — Q19's
predicate scores 512 and would be excluded outright, which is precisely the gap;
(b) the *form* of the emitted term matters. Two semantically identical, identically selective forms
of the same restriction measured 0.383 s and 0.293 s (`q19-orextract.sql` vs `q19-oneterm.sql`,
both with the identical index band `rows: 142584 / readkeys: 23760 / fetch: 156945`), a 1.31x
spread, with the faster form landing within 1.24% of PostgreSQL. Emitting the clause is worth
121x; emitting it well is worth a further 1.3x.

**Correctness/regression risk.** Medium-low but real. The added clause is redundant by
construction, so results cannot change if extraction is correct; the two hazards are (1)
double-counted selectivity shrinking joinrel estimates and flipping unrelated plans — PostgreSQL
calls its own compensation a "MAJOR HACK" at `orclauses.c:53-58` and documents that it fails for
outer and IN joins, so CUBRID must restrict the pass to inner-join terms as PostgreSQL effectively
does; and (2) volatile or subquery-bearing arms, which must be excluded exactly as
`is_safe_restriction_clause_for` excludes `contain_volatile_functions` at `orclauses.c:136-137`.
Three-valued logic needs care: a NULL-yielding arm must not let the derived clause reject a row the
original OR would keep — extracting a *disjunction* of per-arm conditions is safe here because it
is implied by the original, but the pass must never extract a conjunction across arms.

**Validation criteria.** (1) Q19 CUBRID native median drops from 46.5 s to under 0.5 s with
`q19-cubrid.sql` unmodified; (2) `q19-plan-est-cubrid.out` shows a non-empty sarg list on
`node[1]` and the trace's lineitem index band drops from 59,986,052 to 142,584 rows with
`ioread: 0`; (3) the result stays byte-identical at `30104438.0911` and the Q01–Q22 correctness
gate still passes on both engines; (4) no other query's plan shape changes, checked against the
estimated plans already captured for Q01–Q18.

**Upstream precedent.** No CBRD issue or PR was found doing this kind of change; the searched
CUBRID paths and symbols are listed in section 7. The precedent is on the PostgreSQL side and is
explicit: `orclauses.c` exists as a self-contained 330-line file whose header comment
(`:33-73`) uses exactly this shape — *"WHERE ((a.x = 42 AND b.y = 43) OR (a.x = 44 AND b.z = 45))"*
transformed by adding *"AND (a.x = 42 OR a.x = 44)"* — which is a compact statement of the work
CUBRID would need to do.

**Ranking against sibling candidates on Q19.** IMP-027 first and alone in its class: at 121.4491x
it removes 99.80% of the absolute wall gap (46.132 s of 46.226 s), and every other relation below
is either a consequence of it (IMP-007, IMP-013) or worth under 2x on the controlled pair
(IMP-020, IMP-008, IMP-012).

### Relations added to existing candidates

| Existing candidate | Q19 relation | Evidence added | Evidence type |
|---|---|---|---|
| **IMP-007** synchronous single-page `pread` on the query thread | added, **scoped as an amplifier of IMP-027, not an independent Q19 finding** | The largest instance in the campaign: 14,339,369 preads per statement of exactly 16,383.4 bytes each (`/proc` `syscr` and `rchar`, agreeing with the trace's `ioread: 14313083` to 0.18%), 234.9 GB per statement served from the OS page cache at 5.05 GB/s with only 0.80 MiB of device reads. Band A is 30.25% → 69.970 core-s in the kernel copy alone, with the full call path `pgbuf_claim_bcb_for_fix → fileio_read → __libc_pread64 → filemap_read → copy_page_to_iter → rep_movs_alternative`. Scope: the controlled variant on the same engine takes **zero** misses, so this cost exists only under the plan IMP-027 forces. | profile attribution + direct count |
| **IMP-013** LRU surgery on every unfix | added | Band B 29.25% → 67.657 core-s plus band C mutex 6.02% → 13.925 core-s, i.e. **35.27% of CUBRID's Q19 CPU**. `pgbuf_lru_boost_bcb` 6.35% is reached on the *hit* path through `pgbuf_unfix → pgbuf_unlatch_bcb_upon_unfix`, with `pgbuf_fix_release` 10.87%, `pgbuf_unlatch_void_zone_bcb` 3.44%, `pgbuf_unfix` 3.19% and `__pthread_mutex_lock` 3.89%. Same scope caveat as IMP-007. Note this **reverses Q17's counter-example**: on Q17's controlled pair PostgreSQL's buffer band was 5.8x CUBRID's; on Q19's controlled pair it is 1.36x CUBRID's (0.13703 vs 0.10045 core-s), and on the native plan CUBRID's is 674x PostgreSQL's in absolute core-seconds. | profile attribution |
| **IMP-020** per-row DB_VALUE materialisation | added, **as a clean denominator** | Band D on a controlled pair that reads *identical tuples*: CUBRID 0.42822 core-s against PostgreSQL 0.14008 core-s, 199.86 ns against 65.38 ns per executor tuple read — **3.06x**. Both sides zero physical reads, same plan shape, same 2,142,584 tuple reads, same columns. `heap_attrinfo_read_dbvalues` 7.58% + `mr_readval_char_internal` 2.66% + `pr_clear_value` 1.97% + `db_value_domain_init` 1.12% + `pr_type_from_id`(+plt) 1.70% against `tts_buffer_heap_getsomeattrs` 12.11% + `pg_detoast_datum_packed` 0.77%. | profile attribution |
| **IMP-008** generic sarg comparator | added, **as an upper bound only** | Band E on the controlled pair: CUBRID 1.07541 core-s (501.92 ns/tuple) against PostgreSQL 0.20744 core-s (96.82 ns/tuple) = 5.18x, `eval_pred` 28.50% + `tp_value_compare_with_error` 9.41% + `eval_value_rel_cmp` 7.43% + `lang_fastcmp_byte` 4.28% + `mr_cmpval_char` 3.33% against `ExecInterpExpr` 7.86% + `bpchareq` 6.51% + `__memcmp_evex_movbe` 3.34%. **Explicitly not a clean per-comparison denominator**: CUBRID is evaluating 27 distributed CNF conjuncts to PostgreSQL's single 3-arm OR, so the conjunct count is confounded with per-comparison cost. Q17's 1.72x on identical predicates remains the clean figure; Q19 bounds it above. | upper bound |
| **IMP-012** parallel degree saturates below the configured cap | added, **with a measured non-binding verdict** | CUBRID again reaches 5 active units against `parallelism=6` on both configurations (`U_C` 4.97273, `U_Cc` 4.96702, TWU 4.9728/4.8257, trace `parallel workers: 5`, `gather: buildvalue`). At a full 6 units the controlled variant's 1.9024 core-s would need 0.317 s. But Q19 is the first query where CUBRID's utilization **exceeds** PostgreSQL's (3.63094), so `F_units` is 0.731010x in CUBRID's favour and this candidate is not on Q19's critical path. Recorded to bound its priority, not to raise it. | projection (upper bound) |
| **IMP-005** parallel-scan trace statistics merged (k−1) times | added as **negative/scope-bounding evidence** | At Q19's plan depth (parallel heap scan → nested index scan) the artifact does **not** appear: the traced index band 142,584 equals the independent `COUNT(*)` ground truth exactly, the native band 59,986,052 equals the exact lineitem row count, and `lookup rows: 1134` equals the exact result cardinality — all on both engines. This bounds the defect to the depth-3+ nested-loop subtrees Q17 and earlier queries exercised, and confirms Q19's trace counters are usable as-is. | direct count against ground truth |
| IMP-002 buffer replacement fails to retain the working set | **not added** | Considered and rejected as a Q19 relation: IMP-002's root cause is a working set that *marginally* exceeds the pool being evicted anyway. Q19 native's working set (lineitem heap 10.67 GiB plus the FK index) is ~1.8x the 8192 MB pool, so non-residency is arithmetic rather than a policy failure, and the measured 78.33% hit rate (66,035,067 fetches, 14,313,083 misses) is *better* than the ~56% a pool-size bound alone would predict. There is no like-for-like PostgreSQL comparison either, because PostgreSQL never touches this working set. | — |
| IMP-018 private-LRU hard quota | **not added** | Considered and rejected: a 5,000-BCB (78 MiB) per-session retention cap would predict a hit rate near zero on a 14.2 GiB working set, whereas Q19 measures 78.33%, so pages are demonstrably escaping to the shared pool on this workload. Q19 does not reproduce the mechanism and is not offered as evidence for it. | — |
| IMP-011 parallel-degree-blind join costing | **not added** | Not applicable: both engines chose the same join method, the same driving relation and the same index. There is no plan-choice disagreement on Q19. | — |

**The single largest engineering finding on Q19 is a CUBRID optimizer gap with a 121x measured
price and a 330-line reference implementation in PostgreSQL.** It is also the cheapest to state
precisely: CUBRID already costs the better plan 65.7x lower; it simply cannot build it.

## 10. Evidence index

Format: `claim → raw file → formula/locator → evidence type → SHA-256`. Paths are relative to
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q19/`. Full byte sizes and hashes for all 237
artifacts are in `raw-manifest.json`.

| Claim | Raw file | Formula / locator | Evidence type | SHA-256 |
|---|---|---|---|---|
| Preflight all gates PASS, `ssot_drift=NONE`, 8FK/8idx, 0 off-cpuset | `q19-preflight.txt` | whole file | direct capture | `51e03637f9ac85f8…` |
| Postflight same PIDs, 0 off-cpuset, schema unchanged | `q19-postflight.txt` | whole file | direct capture | `bfb5599ef0852ad1…` |
| `result-equivalent-at-SF10`, 1 row, byte-identical decimal | `q19-correctness.json` | `result.status` | direct A/B | `a3604a24f8e23da4…` |
| CUBRID `part` scan has NO sargs, card 2,000,000; `term[0]` is a join term | `q19-plan-est-cubrid.out` | `Query plan:` block; `node[1]` line | direct capture | `e03536bc34e457f9…` |
| PostgreSQL `part` scan carries the extracted OR filter | `q19-plan-est-pg.out` | `Parallel Seq Scan on public.part … Filter:` | direct capture | `369dd28258918874…` |
| Controlled variant gives `part` 27 CNF sargs, est. cost 29,357 | `q19-plan-est-orextract.out` | `Query plan:`; `node[1] (sargs 2 3 … 30)` | direct capture | `ad18ab2800d8825f…` |
| `T_C` = 46.514998 s, three measured WARM statements | `Q19-cubrid-headline-block1.json` | `measured_times_s`, `median_s` | direct A/B | `f5717dfea38cfa6e…` |
| `T_P` = 0.289417 s | `Q19-postgresql-headline-block1.json` | `measured_times_s`, `median_s` | direct A/B | `700ec8b280acf107…` |
| `T_Cc` = 0.383000 s (`F_plan` anchor) | `Q19-cubrid-orextract-headline-block1.json` | `measured_times_s`, `median_s` | direct A/B | `dc11e4104b18696c…` |
| Block-to-block stability, CUBRID 1.428% | `Q19-cubrid-headline-block2.json`, `…block3.json` | `median_s` | direct A/B | `4a0dc4a7e878732e…`, `8f82876a158eee4d…` |
| Block-to-block stability, PostgreSQL 0.931% | `Q19-postgresql-headline-block2.json`, `…block3.json` | `median_s` | direct A/B | `8127af9d41589519…`, `a3dd77393eb85b82…` |
| Block-to-block stability, controlled 1.306% | `Q19-cubrid-orextract-headline-block2.json`, `…block3.json` | `median_s` | direct A/B | `6e7f8c103dd68cf2…`, `0c59e75138a1aeed…` |
| `U_C` = 4.97273, executor 910.05 / aux 1.59 core-s | `Q19-cubrid-headline-telemetry.json` | `utilization.U_core_s_per_wall_s`, `cpu.*` | per-TID sampler | `3bce252d70f81ebe…` |
| `U_P` = 3.63094, no io-worker CPU | `Q19-postgresql-headline-telemetry.json` | same | per-TID sampler | `080b5a90af96b0e3…` |
| `U_Cc` = 4.96702, serial tail 0.000 s | `Q19-cubrid-orextract-headline-telemetry.json` | same | per-TID sampler | `59ae6a3c23c7a45a…` |
| Single-statement `U` cross-check and `syscr` 14,339,369 / `rchar` 234.9 GB | `Q19-cubrid-telemetry.json` | `units`, `io.engine_and_client` | per-TID sampler + procfs | `981a6d3108ef6133…` |
| CUBRID native `ioread: 14313083`, index band `rows: 59986052`, `parallel workers: 5` | `q19-trace-cubrid.out` | trace body | direct capture | `8c086fd070f03f66…` |
| CUBRID controlled `ioread: 0`, index band `rows: 142584`, `lookup rows: 1134` | `q19-trace-orextract.out` | trace body | direct capture | `2622c8f64705f7f6…` |
| PostgreSQL `Index Searches: 4754`, `shared hit=197972` with no `read=` | `q19-plan-act-pg.out` | `Index Scan …`; `Buffers:` lines | direct capture | `5a34e37ff48259d4…` |
| Ground truth 2,000,000 part / 4,754 qualifying / 142,584 lineitem / 1,134 result | `q19-groundtruth-cubrid.out` | six `COUNT(*)` probes | direct count | `b0508d60a3906915…` |
| Same ground truth from the other engine, identical | `q19-groundtruth-pg.out` | same six probes | direct count | `96c538a3c5e5da33…` |
| CUBRID native profile, bands A+B+C 65.52%, 0 unresolved symbols | `profile-cubrid-flat.txt` | symbol lines ≥0.3% | profile attribution | `17859e4bb1ccbb8f…` |
| `rep_movs_alternative` reached via `pgbuf_claim_bcb_for_fix → fileio_read → pread` | `profile-cubrid-callgraph.txt` | `rep_movs_alternative` caller chain | profile attribution | `8493acb7ab9a1121…` |
| CUBRID controlled profile bands | `profile-cubrid-orextract-flat.txt` | symbol lines ≥0.3% | profile attribution | `9b7a29866211c8b6…` |
| PostgreSQL profile, kernel band 40.60% | `profile-pg-flat.txt` | symbol lines ≥0.3% | profile attribution | `094a54056fc8ddf9…` |
| PG kernel band is parallel-worker fork/exit (`ParallelWorkerMain`, `exit_mmap`) | `profile-pg-callgraph.txt` | `filemap_map_pages`, `zap_present_ptes` caller chains | profile attribution | `56f76b52052cb47a…` |
| CUBRID native 5.020 CPUs utilized, IPC 0.78 | `perf-stat-cubrid.txt` | `perf stat` output | direct capture | `830a7ecb2b359c8c…` |
| CUBRID controlled 4.963 CPUs utilized, IPC 2.64 | `perf-stat-cubrid-orextract.txt` | `perf stat` output | direct capture | `cc3b5b6cd223d635…` |
| PostgreSQL 4.632 CPUs utilized, IPC 1.18 (replay regime, not a `U_P` cross-check) | `perf-stat-pg.txt` | `perf stat` output | direct capture | `18f696693e5d37f9…` |
| Rejected hypothesis 2: envelope form has 3 sargs and is SLOWER (0.804 s, 646,526 index rows) | `q19-trace-envelope.out` | trace body | direct A/B | `3f0da1ce08d65630…` |
| Rejected hypothesis 2: envelope estimated plan, 3 part sargs | `q19-plan-est-envelope.out` | `node[1] (sargs 2 4 5)` | direct capture | `b4fd325b4e72e7fc…` |
| Rejected hypothesis 3: predicate FORM is worth 1.31x — gated median 0.293 s | `Q19-cubrid-oneterm-headline.json` | `measured_times_s`, `median_s` | direct A/B | `d64f7548d18e4117…` |
| Rejected hypothesis 3: same selectivity — identical index band 142,584 / readkeys 23,760 | `q19-trace-oneterm.out` | trace body | direct capture | `acbd6f921f2a8f8b…` |
| Rejected hypothesis 3: the single-term control FAILED its goal — still 28 part sargs | `q19-plan-est-oneterm.out` | `node[1] (sargs 2 3 … 31)` | direct capture | `8cc14a6458f9704b…` |
| Controlled variant returns the identical value `30104438.0911` | `q19-orextract-result-cubrid.out` | whole file | direct A/B | `1f87d990fa487008…` |
| Envelope variant returns the identical value `30104438.0911` | `q19-envelope-result-cubrid.out` | whole file | direct A/B | `1f87d990fa487008…` |
| Card inputs, factors, residual +0.0000% | `q19-causal-card.txt` | whole file | derived calculation | `3fb2a3d57cfb5bad…` |
| Exhaustive profile bands, unbanded remainder 0.00% | `q19-bands.txt` | whole file | derived calculation | `dc6376b90da2e92a…` |
| WARM gate parameters derived by moving-block bootstrap; per-engine counts justified | `q19-warm-gate-params.txt` | whole file | derived statistic | `b021a088b9d0a688…` |
| CUBRID 20-statement convergence probe, stationary from statement 2 | `q19-convprobe-cubrid.json` | `statement_times_s` | direct capture | `66c25f5891669420…` |
| PostgreSQL 60-statement probe, 7-statement per-connection decay | `q19-convprobe-postgresql-n60.json` | `statement_times_s` | direct capture | `664e78f9d8f0e76b…` |
| WARM convergence per block | `Q19-cubrid-warm-block1.json`, `Q19-postgresql-warm-block1.json`, `Q19-cubrid-orextract-warm-block1.json` | `converged`, `verdict`, `steady_state_median_s` | derived statistic | `97d449a012b3609e…`, `96f259b1201392c1…`, `b6831b8d209e9bb0…` |
| Load gate CLEAN during each accepted headline block | `Q19-cubrid-bgload-block1.json`, `Q19-postgresql-bgload-block1.json`, `Q19-cubrid-orextract-bgload-block1.json` | `verdict`, `external_max` | direct capture | `67af97a45df9fd17…`, `bd5794ae73d89a3e…`, `89e501c2bdcef0b4…` |

## 11. Notion sync

Not performed by this session, by contract. SSOT section 21 execution boundary: the GJC/tmux
worker session runs on the remote build host, has no Notion connector, and **must never attempt a
Notion write**; its Notion-adjacent duty ends at committing and pushing this report, the raw
manifest and the improvement registry to `origin/main`. All Notion mirroring — the
operational-state page, the Q01–Q22 database row for Q19, the new **IMP-027** improvement-registry
page and the relation updates on IMP-005/007/008/012/013/020 — is performed only by a dedicated
subagent with Notion tool access, reading the pushed GitHub commit as source of truth.

Status: **pending reconciler subagent**. No `reports/notion_backfill_pending.jsonl` record was
written by this session either, since that file is the third write path of the same section 21
sequence and is likewise owned by the Notion-capable subagent.

## 12. Completion checklist

- [x] Preflight recorded: identity, schema, ownership, NUMA/cpuset, statistics, parallel/buffer
      contract, query provenance — all PASS, `ssot_drift=NONE`
- [x] Postflight ownership gate recorded after the last block — same PIDs, 0 off-cpuset, 8FK/8idx
- [x] Correctness status recorded: `result-equivalent-at-SF10`, byte-identical decimal, not censored
- [x] Estimated plans captured without execution, both engines (stage 14.3)
- [x] CUBRID WARM + 3 measured headline statements (stage 14.4); WARM proved, gate parameters derived
- [x] PostgreSQL WARM + 3 measured headline statements (stage 14.5)
- [x] Three valid headline values exist for each engine; both engines completed, no censoring
- [x] Three gated blocks per configuration; all nine accepted on attempt 1 with `CLEAN` load verdict
- [x] Actual plans and CUBRID traces captured in separate non-headline runs (stage 14.6)
- [x] CPU/thread, `/proc` I/O, iostat, NUMA and buffer diagnostics (stage 14.7); executor and
      auxiliary CPU reported separately, `unattributed_background` nil
- [x] Separate perf cycles/instructions/call-graph runs (stage 14.8); 0 unresolved symbols in all
      three profiles, sample coverage validated against `perf stat`
- [x] CUBRID source `file:line` and PostgreSQL counterpart `file:line` for every claimed problem
      (stage 14.9); claims of absence record searched paths, symbols and patterns
- [x] Causal multiplier decomposition with a numeric `F_plan` anchored on a same-engine
      native/controlled A/B; residual +0.0000% with the telescoping caveat stated (stage 14.10)
- [x] Improvement registry deduplicated: searched by title, both source locations and root cause;
      one new root cause allocated (**IMP-027**), six existing candidates given Q19 relations,
      three explicitly **not** added with reasons (stage 14.11)
- [x] Raw manifest written (237 artifacts, 18,401,199 bytes), every claim indexed to a raw file and
      SHA-256 (stage 14.12)
- [x] Report, manifest and registry committed and pushed to `origin/main`, and verified reachable
      from it (`git merge-base --is-ancestor HEAD origin/main`)
- [x] Dispensable work deleted (SSOT section 19): `work/Q19` removed in full after every
      non-dispensable file was SHA-256-verified against `raw/Q19`; the 4.6 GB of `perf-*.data`
      is the only measurement output not promoted and the manifest records why
- [x] Child block-driver tmux sessions consumed (SSOT section 24): all six — `q19conv`,
      `q19blocks`, `q19plans`, `q19tel`, `q19tel1`, `q19perf` — verified absent by
      `tmux has-session`; 0 orphan `csql`/`psql`/`perf` processes and 0 active PostgreSQL
      backends remain
- [ ] Notion sync — ⏭ **deferred to the section 21/23 reconciler subagent by contract.** Section 21
      bars this worker from every Notion write path, and the backfill idempotency key needs
      `report_commit`, which does not exist until this work is pushed. Handoff values are in
      section 11; the new registry page to create is **IMP-027**
- [x] `QUERY_COMPLETE` emitted
- [ ] Current measurement session removed and absence verified — ⏭ **controller step, not this
      worker's.** Section 22 has the controlling session remove the worker after durable
      completion and verify with both `gjc session status <id>` and `tmux has-session -t <id>`.
      This session is `gajae_code_msb674z8_0rfkosdv`; it reports `QUERY_COMPLETE` and stops.
