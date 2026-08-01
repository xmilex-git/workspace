# TPCH-SSPQ FK campaign — Q14 report

TPC-H Query 14, *Promotion Effect*.

> **Naming note.** The session prompt labelled Q14 "Order Priority Checking". That is
> Q04's title; TPC-H Q14 is *Promotion Effect*, and `queries/q14-cubrid.sql` line 1 reads
> `-- TPC-H Query 14: Promotion Effect`. The QNN is unambiguous — SSOT §1 fixes the order
> `Q01 → Q22` and Q01–Q13 are complete — so the mislabel changes nothing about the target
> and this report measures Q14, Promotion Effect.

## 3-a. Causal multiplier card

```text
R_wall 1.884804x [wall, median of 3 per engine; PostgreSQL is 1.8848x faster]
= F_plan  1.120833x [plan-shape; same-engine CUBRID A/B, section 4-d]
× F_units 1.001341x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   1.679358x [total query CPU-seconds]

F_cpu 1.679358x [total query CPU-seconds]
= F_work 1.000000x [lineitem rows scanned: 59,986,052 vs 59,986,052 — EXACTLY equal]
× F_cost 1.679358x [277.17 ns vs 165.04 ns of total query CPU per row scanned]
```

**Read the card in one line: Q14's gap is two things — CUBRID picks the wrong join, and
then pays more CPU per row for the join it does pick.** Unlike Q12 (all `F_cost`) and
Q11 (all `F_work`), Q14 is the first query in this campaign where a *numeric* `F_plan`
and a large `F_cost` both survive, and `F_units` is essentially exactly 1.

`F_plan` is **not** an assumption. It is a same-engine A/B on CUBRID's own switch: forced
onto the hash-join shape PostgreSQL chooses, and with every campaign-contracted setting
held fixed, CUBRID measures **2.880 s against its native 3.228 s**. CUBRID's optimizer
rates the plan it rejects **1.98x more expensive** than the one it picks, while
measurement says the rejected plan is **1.1208x faster**. That is a ranking inversion,
and section 8-a reproduces it arithmetically from three constants in the source.

**The obvious "CUBRID is bad at parallelism" story is wrong, and Q14 refutes it from both
sides.** Each engine's own parallelism switch, measured through the same gated §12 block:

| | CUBRID | PostgreSQL |
|---|---|---|
| serial wall (1 unit) | 18.012999 s | 6.651414 s |
| parallel wall | **3.228000 s** | **1.712645 s** |
| speedup from going parallel | **5.5802x** | 3.8837x |
| CPU inflation from going parallel | **1.0700x** | 1.3905x |
| measured U (core-s per wall-s) | 5.96455 | 5.78072 |
| TWU | 5.9536 | 5.8058 |
| parallel efficiency vs U | **93.6%** | 67.2% |

CUBRID converts its six units into 5.5802x for a 7.0% CPU surcharge; PostgreSQL gets
3.8837x for 39.1%. CUBRID's parallel scan is the **better** implementation here, and
`F_units` is 1.001341x — a 0.13% term. Nothing in Q14's gap is parallelism.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 1.120833x | plan shape | wall-seconds, same engine, same block regime | `T_C_native / T_C_hash8` = 3.228 / 2.880 | `Q14-cubrid-headline-block1.json`, `Q14-cubrid-usehash2-headline.json`, `q14-plan-est-cubrid.out`, `q14-plan-est-cubrid-usehash2.out` | direct A/B (same engine, controlled plan) |
| `F_units` | 1.001341x | active execution units | CPU-seconds / wall-second over the §12 block | `U_P/U_C'` = 5.78072/5.77298 | `Q14-postgresql-headline-telemetry-run{1,2,3}.json`, `Q14-cubrid-usehash2-headline-telemetry.json` | profile attribution |
| `F_cpu` | 1.679358x | total query CPU-seconds | per query execution | `CPU_C'/CPU_P` = 16.6262/9.9003 | same telemetry JSONs × the block medians | profile attribution |
| `F_work` | 1.000000x | lineitem rows scanned | one statement | `59,986,052 / 59,986,052` | `q14-groundtruth-cubrid.out`, `q14-groundtruth-pg.out`, `q14-trace-cubrid.out`, `q14-plan-act-pg.out` | direct A/B (ground truth) |
| `F_cost` | 1.679358x | CPU-seconds per row scanned | rows scanned | `(CPU_C'/W_C)/(CPU_P/W_P)` = 277.17 ns / 165.04 ns | `Q14-causal-card.json`, `q14-bands.txt` | profile attribution |

**Anchor direction and denominator discipline (SSOT §16).** `F_plan` is anchored on the
CUBRID native → CUBRID controlled pair; `F_units` and `F_cpu` are then computed on the
**remaining controlled cross-engine pair**, CUBRID-hash-at-8MB vs PostgreSQL-native. No
native denominator is mixed with a controlled one. The controlled leg is `usehash2`
(`/*+ USE_HASH(part, lineitem) */`) and **not** `hashmem128`, because `usehash2` holds
every other contracted setting fixed — including `max_hash_list_scan_size` at its default
8 MB — and varies exactly one thing, the join method. `hashmem128` varies the plan *and*
the memory budget, so it is reported as a separate A/B in section 8-b rather than as the
anchor.

**Reconstruction residual: `F_plan × F_units × F_cpu` = 1.884804x against `R_wall`
1.884804x, residual `-0.000000000%`.** CPU is attributed as `U × t_median` on the same
block regime the wall is defined on, so the identity is exact by construction once
`F_plan` is factored out on its own same-engine pair; the independent cross-checks are
TWU (within −0.18% of `U` on CUBRID native, +0.43% on PostgreSQL), the two controlled
unit A/Bs above, `perf stat`, and the trace/EXPLAIN counters.

### Error budget, stated before any factor is interpreted

| | contract block medians | spread |
|---|---|---|
| CUBRID | 3.228 / 3.232 / 3.210 | **0.6854%** |
| PostgreSQL | 1.712645 / 1.709223 / 1.722673 | **0.7869%** |

Ratio band implied by the two spreads: 1.863383x … 1.890918x, against the contract
`R_wall` of 1.884804x. **Error budget = 0.7869%** (worst single-engine block-median
spread). The card's residual is 0.000000000%, so the card is closed. Every effect claimed
below is larger than 0.7869% of the quantity it is claimed against, or is explicitly
labelled as a bound rather than a value.

`F_plan`'s 12.08% and `F_cost`'s 67.94% are both far outside that budget. `F_units`'
0.13% is **inside** it and is therefore reported as *indistinguishable from 1.0*, not as
a measured effect.

## 3-b. Headline timings

| Field | CUBRID | PostgreSQL |
|---|---|---|
| run 1 / 2 / 3 (headline block) | 3.228 / 3.242 / 3.216 | 1.730007 / 1.712645 / 1.711661 |
| **median (headline)** | **3.228000 s** | **1.712645 s** |
| mean | 3.228667 s | 1.718104 s |
| within-block standard deviation | 0.013013 s | 0.010320 s |
| **median wall ratio** | **1.884804x** (PostgreSQL faster) | |
| correctness | `result-equivalent-at-SF10` | |
| censoring | none — neither engine approached the 300 s timeout | |

Three values per engine; the median is the headline. No confidence interval is claimed
from three values. Engine-block order was **PostgreSQL first, then CUBRID** (SSOT §12,
Q14 is even).

### All three blocks per engine

| block | CUBRID median | PostgreSQL median |
|---|---|---|
| 1 (**headline**) | **3.228000** | **1.712645** |
| 2 | 3.232000 | 1.709223 |
| 3 | 3.210000 | 1.722673 |
| spread | **0.6854%** | **0.7869%** |

Five of the six contract blocks were accepted on **attempt 1** with a `CLEAN` load verdict
under both the strict per-sample rule and the contract-window rule. PostgreSQL block 3 was
rejected once on attempt 1 by the **WARM gate** (not the load gate) — `NOT_CONVERGED,
monotone trailing window` — and accepted on attempt 2. Blocks 2 and 3 are retained as
stability evidence and are marked non-headline in the manifest.

### WARM proof

WARM is proved, not assumed. Gate parameters were derived from **this query's own**
40-statement convergence probes rather than inherited (`q14-warm-gate-params.txt`):

| | probe steady state | half-split trend | trailing spread | first converged at |
|---|---|---|---|---|
| PostgreSQL | 1.702215 s | +0.0942% | 0.8651% | statement 13 |
| CUBRID | 3.236 s | +0.6815% | 0.5562% | statement 12 |

Chosen: `WARM_STATEMENTS=22` (1.69x the later convergence point), `WINDOW=6`; `LEVEL_TOL`
0.015 (PostgreSQL) and 0.020 (CUBRID); `SPREAD_SANITY` 0.020 both engines. CUBRID's
`LEVEL_TOL` is looser than Q13's 1.00% because Q14's CUBRID series carries a +0.68%
half-split trend — 4.3x Q13's — which a 1.00% gate would reject at only 1.47x margin
despite the series being visibly stationary (no monotone segment, range 3.184–3.270 s).
Each tolerance still sits 6.6x–8.8x below the 13.17% half-split trend the campaign's
warming reference series produces.

PostgreSQL's probe shows a clear **per-connection decay curve** over statements 1–4
(1.8384 → 1.7494) and is flat from statement 5; CUBRID's shows no decay curve and no
monotone segment. This is why the contract blocks' first (uncounted) statement is
consistently the slowest on the PostgreSQL side (1.751/1.758/1.769) and why it is
excluded by the §12 contract.

**Q14 is not a zero-physical-read query on either engine**, unlike Q13. Section 5-d
quantifies it; the working set exceeds both engines' equal 8192 MB budget.

## 2. Correctness

`result-equivalent-at-SF10`. Q14 returns a single row and has no `ORDER BY`, so the
comparison is the whole-row multiset under the §11 decimal rule.

| | value |
|---|---|
| CUBRID | `16.64759494161509526491533839327571214500` |
| PostgreSQL | `16.6475949416150953` |
| rule | `abs(a-b) ≤ 1e-12 × max(1, abs(a), abs(b))` |
| difference | 0 at PostgreSQL's output scale; CUBRID prints 38 significant digits, PostgreSQL 18 |
| row count | 1 vs 1 |
| verdict | **`result-equivalent-at-SF10`** — a pure output-scale difference, not a different row set or predicate decision |

Raw decimal text is preserved in `q14-correctness-cubrid.out` / `q14-correctness-postgresql.out`.

### Dialect artifact, isolated and quantified

`queries/diff/q14.diff` is a single hunk, the only permitted class of change:

```diff
-	and l_shipdate < DATE_ADD(DATE '1995-09-01', INTERVAL 1 MONTH);
+	and l_shipdate < date '1995-09-01' + interval '1' month;
```

This translation is **not semantically neutral in type**, and the report says so rather
than hiding it. PostgreSQL's `date + interval` yields a **timestamp**, so its plan prints
`Filter: (... AND (lineitem.l_shipdate < '1995-10-01 00:00:00'::timestamp without time
zone))` — a date/timestamp comparison — while CUBRID's `DATE_ADD` stays a `DATE`. Q14
proves the row sets are identical and therefore that the artifact is a per-row *cost*
question, not a correctness one (`q14-dialect-equivalence-pg.out`):

| PostgreSQL form | rows |
|---|---|
| `l_shipdate < date '1995-09-01' + interval '1' month` (the dialect file) | 749,223 |
| `l_shipdate < date '1995-10-01'` (plain date literal) | 749,223 |
| `pg_typeof(date '1995-09-01' + interval '1' month)` | `timestamp without time zone` |

The two forms select **exactly the same 749,223 rows**, which is also the value both
engines return for `G1` in the dialect-neutral ground-truth script. The artifact can only
*penalise* PostgreSQL (it forces a date→timestamp promotion per surviving row), so it is
**conservative with respect to this report's conclusion** that PostgreSQL is faster. It is
recorded, not corrected, because correcting it would change the canonical-derived dialect
file, which SSOT §6 forbids outside a contract change.

### Independent ground truth, both engines

Every cardinality below was answered by running the *same* dialect-neutral statement on
both engines. All eight agree exactly.

| id | quantity | CUBRID | PostgreSQL |
|---|---|---|---|
| G0 | lineitem rows | 59,986,052 | 59,986,052 |
| G0 | part rows | 2,000,000 | 2,000,000 |
| G1 | lineitem rows in the shipdate window | 749,223 | 749,223 |
| G2 | join output rows | 749,223 | 749,223 |
| G3 | `p_type like 'PROMO%'` rows in the join | 124,739 | 124,739 |
| G4 | distinct `l_partkey` in the window | 624,910 | 624,910 |
| G5 | `part` rows with `p_type like 'PROMO%'` | 332,975 | 332,975 |
| G6 | lineitem rows scanned (= G0) | 59,986,052 | 59,986,052 |

`G2 == G1` confirms the FK is 1:1 on this join: every qualifying lineitem row matches
exactly one part row, which is what makes `F_work` on rows scanned a clean event.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| Query | Q14 — Promotion Effect |
| SSOT commit | `cc56df92dfb91ede9bbcfd77a4823f5634a8413f` (pinned) |
| SSOT blob SHA | `510478846bff081d3223d3835069283a7cd2e47b` |
| SSOT drift | **NONE**. At session start and at the post-block gate, `HEAD`, `origin/main` and the pinned commit were all `cc56df9`, and `git rev-parse HEAD:tpch-sspq/SSOT.md` = the pinned blob. `git status --porcelain -- tpch-sspq` empty at preflight |
| GJC session ID | `gajae_code_ms9lsury_44tsq3zq` (internal `GJC_SESSION_ID` `019fba9d-c91b-7000-a1de-bc9652686ee0`) |
| Predecessor session | Q13's session `gajae_code_ms9ecbdx_vugn5vtz` was verified ABSENT before any Q14 work: `gjc session status` → `gjc_tmux_session_not_found`, `tmux has-session` → `can't find session` (SSOT §22 steps 8–9). Exactly one measurement session existed throughout |
| Raw root | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q14` |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (includes PR #7441 merge `b334446d6`), checkout `/home/cubrid/dev/tpch-sspq-fk-r1/cubrid-src` |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` (PostgreSQL 20devel), checkout `/home/cubrid/dev/postgres` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` |
| Build flags | CUBRID RelWithDebInfo, assertions disabled, not stripped; PostgreSQL `--enable-debug --without-llvm`, assertions off, JIT off — frozen `reports/bootstrap/build-manifest.json`, `frozen: true`; both live binary hashes re-verified against it at preflight |
| Ownership gate | pre-block **OK** — `cub_master` 1433697, `cub_server` 1612732, postmaster 1433696, all resolving to the campaign prefixes; port 1523 owned by `cub_master`, 5442 by the campaign postmaster |
| cpuset / NUMA | 34 engine TIDs, **0 off-cpuset** at preflight; SUT+client CPUs 0-15 (node0), collectors 20-23. `cub_server` private memory 8,830.61 MB on node0 / 1.62 MB on node1 — the buffer pool is node-local |
| External load | 0.264 core-s/s at preflight; every accepted block `CLEAN` under both the strict per-sample rule and the contract-window rule (threshold 6.0, SSOT §9) |
| Query provenance | `queries/q14-cubrid.sql` SHA-256 `ac695215cd7d7207207b2489626707baf412bd3823a7c163a4c8b3f9fc358c38`, **byte-matches** `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q14.sql` |
| Dialect | `queries/q14-pg.sql` SHA-256 `e35d543e6dd5d6cbe0fb61e9d3a2a91c4f4f8c6b25876ea2adc957953f658d4f`; `queries/diff/q14.diff` is 548 bytes, ONE hunk, date-arithmetic translation only. No hint, no join reordering, no subquery rewrite, no extra predicate. The type promotion it introduces is isolated and quantified in section 2 |
| Schema contract | 8 FK / 8 child B-trees per engine, exact column order, all PostgreSQL constraints `convalidated=t` |
| Statistics | histogram-enabled controlled comparison: CUBRID `update_statistics_update_histogram=y`, bucket target 300; PostgreSQL `default_statistics_target=100`, standard `ANALYZE` |
| Parallel/buffer | configured node/gather-cap comparison, configured-equal buffer budget: CUBRID `parallelism=6`, `max_parallel_workers=100`, `data_buffer_size=8.0G`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`, `parallel_leader_participation=on`, `shared_buffers=8192MB` |
| Shared memory | `dynamic_shared_memory_type=mmap`. **Load-bearing for Q14** and recorded as SSOT §9 requires: PostgreSQL's natural plan is a Parallel Hash Join whose shared hash table and tuple queues live in DSM, it runs **32 batches** with 15,264 temp blocks written, and the mmap fault-in of those segments is a *measured* profile band (section 6-b, 1.254 core-s per statement). At the default `posix` this plan would have had to fit the host's 62.5 MiB `/dev/shm` |
| Row counts | identical on both engines: lineitem 59,986,052; part 2,000,000 |
| Stored size | lineitem: CUBRID 682,937 × 16 KiB = 10,670.9 MiB; PostgreSQL heap 8,790 MB, total 11 GB. part: CUBRID 24,353 × 16 KiB = 380.5 MiB; PostgreSQL heap 320 MB, total 363 MB |
| Engine block order | Q14 is even → **PostgreSQL block first, then CUBRID** (SSOT §12) |
| Harness deviation | The CUBRID `hashmem128` controlled variant needed a session parameter on the block connection. `csql` 11.5.0 has no connection-time parameter option (the PostgreSQL variants use `PGOPTIONS`), so `work/Q14/prelude_run.py` prepends one `SET SYSTEM PARAMETERS` statement and drops its statement time, leaving the §12 contract otherwise byte-identical: one direct connection, one uncounted warmup, three measured statements, no reconnect or prepare between them. Used **only** for that variant, never for a headline block. The parameter was verified session-scoped and non-leaking (server-level `max_hash_list_scan_size` still `8.0M` afterwards), which is what makes the `usehash2` 8 MB claim valid |

Q14's working set does **not** fit either engine's 8192 MB budget, which is why both
engines take physical reads in the measured regime (section 5-d) and why this query has a
real I/O term as well as a CPU term.

## 4. Plan

### 4-a. CUBRID native (estimated, SQL `SET OPTIMIZATION LEVEL 514`, non-executing)

```text
idx-join (inner join)
    outer: sscan
               class: lineitem node[0]
               sargs: term[1]
               cost:  832902 card 752032
    inner: iscan
               class: part node[1]
               index: pk_part_p_partkey term[0]
               cost:  4 card 2000000
    cost:  1220202 card 752032
```

A nested-loop index join: scan lineitem with the shipdate sarg, then probe `part`'s
primary-key B-tree once per surviving row. Wall of the plan dump was 0.02 s, which is the
proof it did not execute.

### 4-b. PostgreSQL native (estimated and actual)

```text
Finalize Aggregate
  -> Gather (Workers Planned: 5, Workers Launched: 5)
     -> Partial Aggregate
        -> Parallel Hash Join   (Inner Unique: true, Hash Cond: l_partkey = p_partkey)
           -> Parallel Seq Scan on lineitem
                 Filter: (l_shipdate >= '1995-09-01'::date
                          AND l_shipdate < '1995-10-01 00:00:00'::timestamp)
                 Rows Removed by Filter: 9,872,805  (x6 loops)
           -> Parallel Hash   Buckets: 131072  Batches: 32  Memory Usage: 4896kB
              -> Parallel Seq Scan on part
```

A parallel hash join: build a **shared** hash table over all of `part` across the six
participants, then stream the filtered lineitem rows through it. `Execution Time:
1791.852 ms`, `Planning Time: 1.190 ms`, `Buffers: shared hit=913508 read=252604, temp
read=14915 written=15264`.

### 4-c. The plans are structurally DIFFERENT — `F_plan` is numeric, not 1.0000

This is the first query in this campaign where I do **not** claim structural equality.
CUBRID probes an index 749,222 times; PostgreSQL builds a 2,000,000-row hash table. There
is no node-for-node correspondence, so `F_plan = 1.0000` would be unsupportable and
`UNMEASURED` would be lazy when a same-engine controlled A/B is available. Section 4-d
supplies that A/B.

Both plans do agree on the one thing `F_work` needs: **each scans all 59,986,052 lineitem
rows**. CUBRID's trace reports it as six workers reading 9,938,887…10,011,920 rows each;
PostgreSQL's as `Rows Removed by Filter` 9,872,805 × 6 loops plus 124,870.5 × 6 output
rows. Both sum to 59,986,052.

### 4-d. The `F_plan` anchor — CUBRID forced onto PostgreSQL's shape

`/*+ USE_HASH(part, lineitem) */`, default 8 MB budget, everything else fixed:

```text
hash-join (inner join)
    edge:  term[0]
    outer: sscan  class: lineitem  sargs: term[1]   cost: 832902  card 752032
    inner: sscan  class: part                       cost:  29353  card 2000000
    cost:  2416443 card 752032
```

Identical outer and inner scan costs to the plan the optimizer *chooses* at 128 MB; the
only difference is the total. Measured through the same §12 block regime:

| CUBRID configuration | plan | plan cost | block median |
|---|---|---|---|
| native (8 MB budget) | idx-join | **1,220,202** | 3.228000 s |
| `/*+ USE_HASH(part, lineitem) */` (8 MB) | hash-join, 6 partitions | **2,416,443** | **2.880000 s** |
| `max_hash_list_scan_size=128M` (no hint) | hash-join, single batch | **1,040,427** | 2.959000 s |

**The cost model's ranking is inverted.** It rates native 1.98x cheaper than the 8 MB hash
plan, which is in fact 1.1208x faster. `F_plan = 3.228 / 2.880 = 1.120833x`.

Note the hint is needed only because `USE_HASH(part)` alone is insufficient: the hint is
read from the *inner* node, so naming only `part` still leaves the reversed join order
(part outer, lineitem inner) free to take an idx-join on `fk_lineitem_partsupp` at cost
1,929,147, which then wins. Naming both tables closes that escape
(`q14-plan-est-cubrid-usehash.out` vs `q14-plan-est-cubrid-usehash2.out`).

### 4-e. PostgreSQL forced onto CUBRID's shape — the positive control

`enable_hashjoin=off, enable_mergejoin=off` gives PostgreSQL a `Nested Loop` over a
`Parallel Seq Scan on lineitem` with an index probe into `part` — CUBRID's native shape:

| PostgreSQL configuration | block median | vs its own native |
|---|---|---|
| native parallel hash join | 1.712645 s | — |
| forced nested-loop index join | 2.086580 s | **1.2183x slower** |
| `enable_hashjoin=off` only | (Merge Join + Sort, not CUBRID's shape — not used as an anchor) | |

So the hash shape is worth **1.2183x to PostgreSQL** and **1.1208x to CUBRID** on the same
data. Both engines' cost models are asked the same question; only CUBRID's answers wrong.
This is a cross-engine *corroboration* of the anchor's direction, and it is reported as a
bound, not as `F_plan`, because the two engines' executors differ.

## 5. Execution telemetry

### 5-a. Units, utilization and TWU

| | CUBRID native | CUBRID hash 8 MB | PostgreSQL native |
|---|---|---|---|
| U (core-s per wall-s) | 5.96455 | 5.77298 | 5.78072 |
| TWU (actual timestamp-delta weighted) | 5.9536 | 5.7600 | 5.8058 |
| TWU vs U | −0.18% | −0.23% | +0.43% |
| max simultaneous active units | 6.2415 | 11.4209 | 9.2266 |
| serial tail | 0.000 s | 0.000 s | 0.117 s |
| executor CPU (core-s / block) | 72.590 | 64.670 | 39.250 |
| auxiliary CPU (core-s / block) | 0.100 | 1.090 | 1.760 |
| total query CPU (core-s / block) | 72.690 | 65.760 | 41.010 |

TWU is computed from actual sample timestamp deltas, never a nominal interval, and agrees
with `U` within 0.43% on every configuration — so the configured cap is never substituted
for measured utilization. CUBRID's `max_parallel_workers=100` and PostgreSQL's
`max_parallel_workers=5` are **settings**, and no planned/launched/simultaneous count is
inferred from them: PostgreSQL's plan reports `Workers Planned: 5, Workers Launched: 5`
and CUBRID's trace reports `parallel workers: 6`.

CUBRID's auxiliary CPU is ~0.1 core-s because `csql` consumes a single-row result;
PostgreSQL's 1.76 core-s includes `psql` and its io workers. Both are reported separately
and never folded into executor CPU.

### 5-b. Three telemetry runs per engine

| run | CUBRID U | CUBRID total CPU | PostgreSQL U | PostgreSQL total CPU |
|---|---|---|---|---|
| 1 | 5.96455 | 72.690 | 5.94702 | 40.780 |
| 2 | 5.96231 | 72.770 | 5.73801 | 39.290 |
| 3 | 5.97389 | 72.750 | 5.78072 | 41.010 |
| **median** | **5.96455** | 72.750 | **5.78072** | 40.780 |

CUBRID's three `U` values span 0.19%; PostgreSQL's span 3.6%. The median run is used.
CUBRID telemetry run 2's WARM establishment reported `NOT_CONVERGED` (spread 2.1811% >
2.00%); its `U` (5.96231) is within 0.04% of the two converged runs, so it is retained and
flagged rather than driving the median.

### 5-c. CPU attribution to the contract regime

| | CUBRID native | CUBRID hash 8 MB | PostgreSQL |
|---|---|---|---|
| block median | 3.228000 s | 2.880000 s | 1.712645 s |
| U | 5.96455 | 5.77298 | 5.78072 |
| **total query CPU per statement** | **19.2536 core-s** | **16.6262 core-s** | **9.9003 core-s** |
| per lineitem row scanned | 320.97 ns | **277.17 ns** | **165.04 ns** |

### 5-d. Physical reads and buffer behaviour — measured, and WARM is qualified

Q14's working set exceeds both engines' equal 8192 MB budget, so unlike Q13 this is **not**
a zero-miss query. Per measured statement, from `/proc/<pid>/io` sampled across every
engine PID by the harness sampler:

| | CUBRID | PostgreSQL |
|---|---|---|
| read syscalls / statement | **431,446** | 49,077 – 84,844 |
| bytes read / statement (`rchar`) | **7.068 GB** | 1.19 – 1.87 GB |
| bytes per read syscall | 16,383 B (one 16 KiB page per miss) | — |
| bytes written / statement | ~0 | ~258 MB (hash spill temp) |
| **device** reads | **0 MiB** | **0 MiB** |
| implied miss rate vs its own scan | 431,446 / 682,937 heap pages = **63.2%** | `pg_statio` 119,543 blks_read/statement of 1,166,112 = **10.3%** |

**Device reads are zero on both sides** — the host page cache absorbs everything — so this
is not disk latency. It is CPU spent copying pages the engine has already read, and it
shows up directly in the profile (section 6-a, CUBRID's 2.940 core-s/statement copy band).
The WARM gate is therefore satisfied in the sense SSOT §12 requires (proved-stationary,
verified by the convergence probes and by three block medians within 0.69%/0.79%), but
Q14's WARM is **stationary-with-misses**, not Q13's stronger *proved-stationary and
zero-miss*. That distinction is stated rather than glossed.

PostgreSQL's `EXPLAIN (ANALYZE, BUFFERS)` run, which is a separate non-headline statement,
recorded `shared hit=913508 read=252604` — i.e. exactly `lineitem` 1,125,128 +
`part` 40,984 = 1,166,112 blocks touched, one full pass of both relations.

**`cubrid statdump` is unusable for per-statement physical-read accounting on this server**
and is excluded from every calculation. Bracketing one full statement gives delta 0 for
`Num_data_page_fetches` and `Num_data_page_ioreads` in both `-c` and non-cumulative mode,
and the stage-14.7 diag block recorded delta 0 for every counter while `/proc/<cub_server>/io`
recorded 28.27 GB of `rchar` over the same four statements. The counters are not permanently
stuck (they advanced 2,292,477 across this session) but they do not track statement
completion; the update mechanism was **not** determined and no claim here depends on it
(`q14-statdump-unusable.txt`).

### 5-e. CUBRID trace — the idx-join's real work

```text
SELECT (time: 3300, fetch: 9, ioread: 6)
  SCAN (table: dba.lineitem), (heap time: 3300)
       (parallel workers: 6, heap time: 3258..3299,
        readrows: 9938887..10011920, rows: 9938887..10011920, gather: buildvalue)
    SCAN (index: dba.part.pk_part_p_partkey),
         (btree time: 816, fetch: 2996858, ioread: 0,
          readkeys: 749222, filteredkeys: 749222, rows: 749222)
         (lookup time: 207, rows: 749222)
```

749,222 B-tree probes cost **2,996,858 page fetches — exactly 4.0000 per probe** (root +
two internal + leaf), plus a heap lookup for `p_type`. B-tree time 816 ms and lookup time
207 ms, together 1,023 ms of the traced 3,300 ms. (The trace reports 749,222 against
ground truth 749,223, a 1-row/0.00013% accounting difference that is noted and not used
in any calculation.)

## 6. Profile

`perf` is non-headline. Attached to verified PID sets — CUBRID's single multithreaded
`cub_server` 1612732 (31 TIDs), PostgreSQL's leader 2236875 plus its five live workers —
never an all-CPU profile. Resolved-sample coverage: **0 unknown-symbol lines** on both
sides (CUBRID 832 flat lines / 517,117 samples; PostgreSQL 1,428 flat lines / 72,694
samples), validated against `perf stat`.

| | CUBRID | PostgreSQL |
|---|---|---|
| cycles / statement | 52.294e9 | 27.398e9 |
| instructions / statement | **98.674e9** | **46.715e9** |
| IPC | 1.887 | 1.705 |
| task-clock CPUs utilized | 5.772 | 5.834 |

Instruction count is an *independent* confirmation of `F_cpu`: 98.674/46.715 = **2.112x**
on the native pair, against the card's native-pair `F_cpu` of 1.945x — the same story from
a counter that never touches the sampler.

### 6-a. CUBRID top symbols (≥0.6%)

```text
 9.64%  heap_attrinfo_read_dbvalues        4.58%  heap_next_1page
 9.61%  rep_movs_alternative  [kernel]     4.46%  __memmove_evex_unaligned_erms
 8.94%  eval_pred                          3.66%  tp_value_compare_with_error
 5.48%  pgbuf_fix_release                  3.03%  eval_value_rel_cmp
 2.59%  btree_search_leaf_page             2.52%  spage_get_record
 2.40%  heap_scan_get_visible_version      2.22%  or_mvcc_get_header
 2.13%  eval_data_filter                   1.92%  parallel_scan::slot_iterator::next_qualified_slot_with_peek
 1.55%  or_mvcc_get_repid_and_flags        1.39%  pgbuf_unfix
 1.33%  __pthread_mutex_lock               1.25%  pr_clear_value
```

### 6-b. PostgreSQL top symbols (≥0.6%)

```text
36.73%  tts_buffer_heap_getsomeattrs       8.69%  ExecInterpExpr
 5.55%  next_uptodate_folio   [kernel]     4.28%  heapgettup_pagemode
 3.03%  hash_search_with_hash_value        2.76%  ExecSeqScanWithQualProject
 2.10%  heap_getnextslot                   2.10%  StrategyGetBuffer
 2.03%  heap_page_prune_opt                1.78%  _compound_head        [kernel]
 1.66%  folio_remove_rmap_ptes [kernel]    1.58%  ExecStoreBufferHeapTuple
 1.51%  filemap_map_pages     [kernel]     1.27%  folios_put_refs       [kernel]
 1.18%  LWLockAttemptLock                  1.14%  heap_prepare_pagescan
 0.90%  zap_present_ptes      [kernel]     0.90%  PinBuffer
 0.75%  ExecParallelHashTableInsertCurrentBatch   0.74%  ExecParallelScanHashBucket
```

### 6-c. Bands, in absolute core-seconds per statement

| band | CUBRID (of 19.2536) | PostgreSQL (of 9.9003) |
|---|---|---|
| row materialise + predicate evaluation | 44.22% → **8.514 core-s** | 60.06% → **5.946 core-s** |
| page copy out of the OS page cache / DSM mmap fault-in | 15.27% → 2.940 core-s | 12.67% → 1.254 core-s |
| buffer fix/unfix/LRU + mutex | 9.23% → 1.777 core-s | 4.18% → 0.414 core-s |
| join mechanics | B-tree probe 2.59% → 0.499 core-s | parallel hash build+probe 4.52% → 0.447 core-s |

**PostgreSQL spends a larger *share* of a much smaller budget on the same work.** The
like-for-like row-materialisation ratio is 8.514 / 5.946 = **1.4318x**, which is the
single largest identified component of `F_cost` 1.679358x.

PostgreSQL's kernel band is dominated by page-fault symbols (`next_uptodate_folio`,
`filemap_map_pages`, `folio_remove_rmap_ptes`, `folios_put_refs`, `zap_present_ptes`) —
this is the `dynamic_shared_memory_type=mmap` DSM being faulted in for the 32-batch
parallel hash, exactly the effect SSOT §9 requires to be recorded when a Parallel Hash
Join is in the plan. It costs PostgreSQL 1.254 core-s per statement and is a real price it
pays for the plan that still wins.

## 7. Source contrast

| Item | CUBRID file:line | PostgreSQL file:line | Difference | Class |
|---|---|---|---|---|
| Hash-join spill accounting decides plan choice | `src/optimizer/query_planner.c:3650-3658` — `inner_build_io_cost += (inner_cardinality + outer_cardinality) * HJ_FILE_IO_WEIGHT` once the build exceeds `max_hash_list_scan_size * HJ_PARTITION_FILL_FACTOR`; `:90 #define HJ_FILE_IO_WEIGHT 0.5` **per row** | `src/backend/optimizer/path/costsize.c:4386-4423` `initial_cost_hashjoin()` — calls `ExecChooseHashTableSize()`, and when `numbatches > 1` charges `seq_page_cost * (inner_pages + outer_pages)`, i.e. **per page** for the predicted batches, and never disqualifies the path | CUBRID bills 1,376,016 units for a spill that measures 89 ms; PostgreSQL bills pages | same stage, lower measured cost |
| Anti-hash heuristic offset | `src/optimizer/query_planner.c:87` — `#define HJ_MEM_ALLOC_CONSTANT 1500 /* Heuristic offset to prefer NL join over hash join */`, added to both build orders | no counterpart — PostgreSQL has no constant whose stated purpose is to prefer one join method | structural absence (0.13% of Q14's margin — named for completeness, not a deciding term) | structural absence |
| Hash memory budget and how it scales | `src/base/system_parameter.c:3519-3532` — `max_hash_list_scan_size`, default **8 MB**, hard maximum **128 MB**, a flat per-statement budget that does not scale with `data_buffer_size` or with parallelism | `src/backend/executor/nodeHash.c:3680-3691` `get_hash_memory_limit()` = `work_mem * hash_mem_multiplier`; `nodeHash.c:717-734` — Parallel Hash multiplies it by `(parallel_workers + 1)` to use the **combined** budget, falling back to per-worker batching rather than avoiding the plan | PostgreSQL gets 8 MB × 6 = 48 MB and still batches to 32 when that is not enough; CUBRID gets a flat 8 MB. **Measured NOT to be Q14's deciding term** (section 8-b) | same stage, lower measured cost |
| Spill threshold arithmetic (cost model vs executor) | `src/optimizer/query_planner.c:94` `HJ_HASH_ENTRY_POS_SIZE 12` and `:91 HJ_PARTITION_FILL_FACTOR 0.8`, mirroring `src/query/query_hash_join.c:1356` `part_cnt = CEIL_PTVDIV(per_entry_size * min_tuple_cnt, mem_limit * PARTITION_FILL_FACTOR)` with `per_entry_size = 2*sizeof(MHT_HLS_SLOT) + sizeof(MHT_HLS_ENTRY) + sizeof(QFILE_TUPLE_SIMPLE_POS)` = 52 B | `src/backend/executor/nodeHash.c:683-760` `ExecChooseHashTableSize()` returns `nbatch`, and the planner costs that same `nbatch` | the two CUBRID sites agree with each other and with the trace (6 partitions predicted, 6 observed); the defect is the *price*, not the *threshold* | common to both engines |
| Per-row tuple materialisation (the `F_cost` residual) | `heap_attrinfo_read_dbvalues` 9.64%, `or_mvcc_get_header` 2.22%, `spage_get_record` 2.52%, `pr_clear_value` 1.25% — a fully-typed `DB_VALUE` built and torn down per attribute per row | `src/backend/executor/execTuples.c` `tts_buffer_heap_getsomeattrs` → `slot_deform_heap_tuple` 36.73% — deform into a flat Datum/isnull array using cached offsets, no per-value type object and no teardown | 8.514 vs 5.946 core-s per statement on identical 59,986,052 rows | same stage, lower measured cost |
| Scan predicate evaluation | `eval_pred` 8.94% + `tp_value_compare_with_error` 3.66% + `eval_value_rel_cmp` 3.03% — generic `DB_VALUE` comparator with per-call domain resolution | `ExecInterpExpr` 8.69% — qual compiled once into type-specialized `ExprEvalStep`s | 15.63% vs 8.69% of each engine's own budget, on budgets that differ 1.94x | same stage, lower measured cost |

The absence claim in row 2 was checked, not assumed: the PostgreSQL optimizer directory
was searched for a constant offset applied to hash-join cost to bias against it
(`costsize.c` hash-join cost path, `initial_cost_hashjoin`/`final_cost_hashjoin`); none
exists. `USE_HASH`/`NO_USE_HASH` hint plumbing was located at
`src/parser/csql_grammar.y:23951-23952`, `src/optimizer/query_graph.c:4521-4527` and
`src/optimizer/query_planner.c:6692-6705`.

## 8. Causal decomposition details

### 8-a. `F_plan` reproduced arithmetically from three source constants

CUBRID's `qo_hjoin_cost()` (`src/optimizer/query_planner.c`) computes, for the
outer-as-build order:

```text
outer_build_cpu = inner_card × QO_CPU_WEIGHT × HJ_PROBE_CPU_OVERHEAD_FACTOR
                + outer_card × QO_CPU_WEIGHT × HJ_BUILD_CPU_OVERHEAD_FACTOR
                + HJ_MEM_ALLOC_CONSTANT
                = 2,000,000 × 0.0025 × 20 + 752,032 × 0.0025 × 40 + 1,500
                = 100,000 + 75,203.2 + 1,500 = 176,703.2
```

Adding the two scan costs and the build's page term:

```text
832,902 (lineitem sscan) + 29,353 (part sscan) + 176,703.2 + 1,469 (outer_pages)
  = 1,040,427   ← exactly the cost CUBRID prints at max_hash_list_scan_size=128M
```

The reconstruction is **exact to the unit**. Then the spill term:

```text
spill = (inner_card + outer_card) × HJ_FILE_IO_WEIGHT
      = (2,000,000 + 752,032) × 0.5 = 1,376,016

1,040,427 + 1,376,016 = 2,416,443   ← exactly the cost CUBRID prints at 8 MB
```

So the **entire** difference between the two hash-join costs is the spill penalty, and:

| quantity | value |
|---|---|
| idx-join cost (chosen) | 1,220,202 |
| hash-join cost at 8 MB (rejected) | 2,416,443 |
| decision margin | 1,196,241 |
| spill penalty | **1,376,016 — 115% of the margin** |
| `HJ_MEM_ALLOC_CONSTANT` | 1,500 — **0.13%** of the margin |

Removing the spill term alone flips the choice. That is not a hypothesis: setting
`max_hash_list_scan_size=128M` removes it and CUBRID picks the hash join **with no hint**
at cost 1,040,427.

**How wrong is the penalty?** The 8 MB run genuinely spills — `q14-trace-cubrid-usehash2.out`
prints `SPLIT (time: 89, fetch: 40413, ioread: 10408, partitions: 6)` and `BUILD ...
method: hybrid`, against `BUILD ... method: memory` and no `SPLIT` node at 128 MB. The
partition count is predicted exactly by the in-tree formula:

```text
ceil(749,223 rows × 52 B / (8 MiB × 0.8)) = ceil(5.805) = 6      trace: partitions: 6
```

which independently confirms both the 52-byte per-entry size and the threshold arithmetic.
Anchoring the cost scale on the native plan (1,220,202 units ↔ 3.228 s ⇒ 2.6455 µs/unit),
the 1,376,016-unit penalty implies **3.640 s** of wall. The measured cost of that spill is
**0.089 s** of a 3,244 ms statement (2.7%). **The spill is overcharged by 40.9x.** A
per-page charge — `inner_pages + outer_pages` ≈ 4,521 units — would have let the hash plan
win on cost.

### 8-b. Explanations considered and REJECTED, with the number that rejected them

- **"The hash memory budget is too small."** Rejected by **79 ms**. If the 8 MB budget were
  the defect, giving the join 16x more memory should help. It does not: the 128 MB
  single-batch run measures **2.959 s** against the 8 MB partitioned run's **2.880 s** — the
  bigger budget is **0.0274x slower**. The defect is the cost model's *valuation* of
  spilling, not the amount of memory. This also disposes of "scale
  `max_hash_list_scan_size` with `data_buffer_size`" as Q14's fix.
- **"CUBRID is bad at parallelism."** Rejected by a same-engine A/B on each engine's own
  switch: CUBRID 5.5802x speedup at a 7.0% CPU surcharge (93.6% efficiency) vs PostgreSQL
  3.8837x at 39.1% (67.2%). `F_units` = 1.001341x, which is *inside* the 0.7869% error
  budget and therefore indistinguishable from 1.
- **"`HJ_MEM_ALLOC_CONSTANT`, the explicit anti-hash offset, causes it."** Rejected: 1,500
  against a 1,196,241 margin is **0.13%**. (Q09 rejected it at 0.16% for the same reason.)
- **"CUBRID scans more rows."** Rejected by ground truth: both engines scan **exactly**
  59,986,052 lineitem rows, `F_work` = 1.000000x, confirmed independently by each engine's
  own `count(*)`, by CUBRID's six-worker trace sum, and by PostgreSQL's
  `Rows Removed by Filter` + output rows.
- **"The dialect's `interval` translation penalises CUBRID."** Rejected by direction: the
  translation forces a date→timestamp promotion on **PostgreSQL**, the engine that wins, so
  it is conservative with respect to the conclusion. Row sets proved identical (749,223 both
  forms).
- **"It's physical I/O."** Rejected as *disk* I/O: device reads are **0 MiB** on both
  engines. It is real, but it is CPU spent copying page-cache pages (2.940 vs 1.254 core-s
  per statement), and it is counted inside `F_cost`, not as a separate I/O term.

### 8-c. What remains after the plan is fixed

Fixing `F_plan` alone would move Q14's `R_wall` from 1.884804x to **1.681625x**. The
residual is `F_cost` 1.679358x on `F_work` exactly 1.0 — a pure CPU-per-row difference of
277.17 ns vs 165.04 ns over the same 59,986,052 rows, whose largest identified component is
per-row tuple materialisation (1.4318x, 8.514 vs 5.946 core-s) and whose second is the
page-copy band (2.940 vs 1.254 core-s). Both are existing registered candidates; see
section 9.

### 8-d. A structural cost CUBRID's hash join still pays

Even when CUBRID runs the hash join, its trace shows both inputs first materialised into
temp list files — `SUBQUERY (uncorrelated)` feeding a `SCAN (temp ...)` of 749,223 rows —
where PostgreSQL streams the probe side straight through `Parallel Hash Join`. This is why
CUBRID's forced hash join reaches 2.880 s and not PostgreSQL's 1.713 s, and it relates to
the already-registered IMP-006. It is recorded as an observation with a `file:line`-backed
mechanism, not quantified as a separate factor, because no controlled A/B isolates it on
Q14.

## 9. Improvements

**No new improvement ID was allocated for Q14, and that is the correct outcome under SSOT
§18.** The registry was synced and searched by title, CUBRID source location, PostgreSQL
source location and root cause before any candidate was considered. Q14's deciding term is
already registered as **IMP-011**, whose `cubrid_source` already names
`src/optimizer/query_planner.c:3650-3658 spill penalty '(inner_cardinality +
outer_cardinality) * HJ_FILE_IO_WEIGHT'` and whose `implementation_direction` already lists
*"(a) charge hash spill per page rather than per row"*. Q14 does not add a new mechanism —
it **isolates** that one and puts a number on it. Allocating IMP-022 for the same code line
would be exactly the duplication §18 exists to prevent. `next_id` remains `IMP-022`.

| ID | relation to Q14 | what Q14 contributes |
|---|---|---|
| **IMP-011** | **primary — isolating experiment** | First query where the per-row spill penalty *alone* inverts the plan ranking: 1,376,016 units = 115% of the 1,196,241 margin, reproduced exactly from source constants, against a measured spill cost of 89 ms (**40.9x overcharge**). Parallel-degree blindness does **not** apply (CUBRID's chosen plan is already parallel and its parallelism is the better one), and `HJ_MEM_ALLOC_CONSTANT` is 0.13% — so Q14 cleanly separates this candidate's sub-item (a) from its other halves. Also **rejects** the memory-budget hypothesis by 79 ms. `F_plan` 1.120833x of a 1.884804x gap; fixing it alone moves `R_wall` to 1.681625x |
| **IMP-020** | supporting evidence | Q14 gives this candidate its cleanest denominator yet: with the plan shape controlled away, the whole residual is `F_cpu` 1.679358x on `F_work` **exactly** 1.000000x — 277.17 vs 165.04 ns per row. Profile attribution: 8.514 vs 5.946 core-s per statement on the materialise+predicate band (1.4318x), corroborated by `perf stat` instruction counts 98.674e9 vs 46.715e9 (2.112x) |
| **IMP-018** | supporting evidence | Scan-resident stress case: 431,446 read syscalls and 7.068 GB per CUBRID statement (one 16 KiB page per miss, 63.2% miss rate) against PostgreSQL's 49,077–84,844 and 1.19–1.87 GB, with **zero device reads** on both sides — so the cost is the 2.940 core-s/statement page-copy band, not disk. Also records that `cubrid statdump` is unusable for per-statement physical-read accounting on this server |
| IMP-006 | related observation, not quantified | CUBRID materialises both hash-join inputs into temp list files (section 8-d) where PostgreSQL streams the probe side |
| IMP-008 | related observation | `tp_value_compare_with_error` 3.66% + `eval_value_rel_cmp` 3.03% inside Q14's predicate band |

**Ranking.** IMP-011 first: it is the only Q14 candidate whose removal is *measured* to
change the wall by more than the error budget (1.1208x direct same-engine A/B against a
0.7869% band). IMP-020 second: larger in absolute core-seconds (2.568 core-s/statement of
the residual) but supported by profile attribution rather than an A/B. IMP-018 third
(1.686 core-s/statement differential, attribution). IMP-006 and IMP-008 are recorded
without independent Q14 quantification. Effects must **not** be summed: IMP-011 changes
*which* plan runs, IMP-020/IMP-018 change what *that* plan costs per row, and the card
already accounts for both through `F_plan` and `F_cost` separately.

## 10. Evidence index

`claim → raw file:line → formula → evidence type → SHA-256` — SHA-256 values for every
file are in `reports/Q14/raw-manifest.json`; the manifest is the authoritative index.

| claim | raw pointer | formula | evidence type |
|---|---|---|---|
| `R_wall` 1.884804x | `Q14-cubrid-headline-block1.json`, `Q14-postgresql-headline-block1.json` | 3.228 / 1.712645 | direct measurement |
| `F_plan` 1.120833x | `Q14-cubrid-headline-block1.json`, `Q14-cubrid-usehash2-headline.json` | 3.228 / 2.880 | direct A/B, same engine |
| `F_units` 1.001341x | `Q14-postgresql-headline-telemetry-run{1,2,3}.json`, `Q14-cubrid-usehash2-headline-telemetry.json` | 5.78072 / 5.77298 | profile attribution |
| `F_cpu` 1.679358x | same telemetry × block medians | 16.6262 / 9.9003 | profile attribution |
| `F_work` 1.000000x | `q14-groundtruth-cubrid.out`, `q14-groundtruth-pg.out`, `q14-trace-cubrid.out`, `q14-plan-act-pg.out` | 59,986,052 / 59,986,052 | direct A/B (ground truth) |
| plan cost inversion | `q14-plan-est-cubrid.out`, `q14-plan-est-cubrid-usehash2.out`, `q14-plan-est-cubrid-hashmem128.out` | 1,220,202 vs 2,416,443 vs 1,040,427 | direct measurement |
| spill penalty = 1,376,016 | `q14-plan-est-cubrid-usehash2.out` minus `q14-plan-est-cubrid-hashmem128.out` | 2,416,443 − 1,040,427 | direct measurement |
| spill overcharged 40.9x | `q14-trace-cubrid-usehash2.out` (`SPLIT time: 89`), `Q14-causal-card.json` | 1,376,016 × 2.6455 µs / 0.089 s | projection with explicit formula |
| 6 partitions predicted = observed | `q14-trace-cubrid-usehash2.out`, `query_hash_join.c:1356` | ceil(749,223 × 52 / (8 MiB × 0.8)) | direct A/B |
| memory-budget hypothesis rejected | `Q14-cubrid-usehash2-headline.json`, `Q14-cubrid-hashmem128-headline.json` | 2.880 vs 2.959 | direct A/B |
| parallelism hypothesis rejected | `Q14-cubrid-noparscan-headline.json`, `Q14-postgresql-noparallel-headline.json` | 18.012999/3.228 vs 6.651414/1.712645 | direct A/B |
| PostgreSQL plan control | `Q14-postgresql-nlidx-headline.json`, `q14-plan-est-pg-nlidx.out` | 2.086580 / 1.712645 | direct A/B |
| physical reads | `Q14-cubrid-headline-telemetry-run1.json`, `Q14-postgresql-headline-telemetry-run{1,2,3}.json`, `Q14-{cubrid,postgresql}-buffer-io-diag.json` | rchar/4, syscr/4 per block | direct measurement |
| statdump unusable | `q14-statdump-unusable.txt`, `Q14-cubrid-buffer-io-diag.json` | pre/post delta = 0 | direct measurement |
| profile bands | `profile-cubrid-flat-nocg.txt`, `profile-pg-flat-nocg.txt`, `q14-bands.txt` | share × CPU/statement | profile attribution |
| instructions/statement | `perf-stat-cubrid.txt`, `perf-stat-pg.txt` | event count ÷ (task-clock ÷ CPU-s per statement) | direct measurement |
| correctness | `q14-correctness.json`, `q14-correctness-{cubrid,postgresql}.out` | §11 decimal rule | direct A/B |
| dialect row-set identity | `q14-dialect-equivalence-pg.out` | 749,223 = 749,223 | direct A/B |
| WARM gate derivation | `q14-warm-gate-params.txt`, `q14-convergence-{cubrid,pg}.json` | half-split trend, trailing spread over 40 statements | direct measurement |
| preflight / contract gates | `preflight-Q14.txt` | 8 FK / 8 B-tree, parameter dump, binary hashes | direct measurement |

Invalid artifacts are retained under the raw root with an explicit reason and excluded
from every calculation: `INVALID-noprelude-*` (the first `cubrid-hashmem128` telemetry
attempt, which ran the native plan because the prelude shim did not yet patch
`build_block`; see `INVALID-noprelude-Q14-cubrid-hashmem128-telemetry.README`).

## 11. Notion sync

**Not performed by this session, by design.** SSOT §21's execution boundary states that the
GJC/tmux worker session on the remote build host has no Notion connector and must never
attempt a Notion write; its Notion-adjacent duty ends at committing and pushing the
report/manifest to `origin/main`.

Accordingly this session used **write path 3**: an idempotent record appended to
`reports/notion_backfill_pending.jsonl`, keyed by
`campaign_id + QNN + session_id + report_commit + content_fingerprint`. The Q01–Q22
database row, the improvement-registry mirror pages for IMP-011/IMP-018/IMP-020 and the
operational-state update are owed by the dedicated Notion-capable subagent (SSOT §23),
reading the pushed commit as source of truth. The pending record must be cleared only
after a server-side refetch.

## 12. Completion checklist

| SSOT §26 gate | status |
|---|---|
| preflight and correctness status recorded | **yes** — `preflight-Q14.txt` all gates PASS; `result-equivalent-at-SF10` |
| three valid headline values for each completing engine | **yes** — CUBRID 3.228/3.242/3.216, PostgreSQL 1.730007/1.712645/1.711661 |
| timeout confirmations if censored | **n/a** — no timeout; slowest measured statement 3.242 s against a 300 s limit |
| plan, execution, profile and source contrast sections complete | **yes** — sections 4, 5, 6, 7 |
| causal multiplier card has evidence or explicit `UNMEASURED` | **yes** — all five factors measured, residual 0.000000000%, no `UNMEASURED` term |
| Git improvement ledger deduplicated and committed | **yes** — dedup performed against all 21 existing candidates; no new ID (correct outcome); IMP-011/IMP-018/IMP-020 extended with Q14 evidence and relations |
| Notion relations synced or idempotent backfill record durable | **backfill record durable** — write path 3, per the §21 execution boundary for a worker session |
| every claim indexed to raw evidence and checksum | **yes** — section 10 + `raw-manifest.json` |
| report, manifest and registry committed, pushed, reachable from `origin/main` | **yes** — see `report_commit` in the manifest |
| `QUERY_COMPLETE` emitted | **yes** |
| current session removed and absence verified | **owed by the controller.** A GJC session cannot remove itself. SSOT §22 steps 7–8 (`gjc session remove gajae_code_ms9lsury_44tsq3zq`, then absence verified with **both** `gjc session status gajae_code_ms9lsury_44tsq3zq` and `tmux has-session -t gajae_code_ms9lsury_44tsq3zq`) are the transition owner's step, and only then may the Q15 session be created |

Child tmux sessions spawned by this session to host long-running block drivers
(`q14conv`, `q14hl`, `q14act`, `q14probe`, `q14tel`, `q14var`, `q14fix`, `q14perf`) were
each polled to an explicit `DRIVER_EXIT` marker and are all gone; they are an
implementation detail of this single query session under SSOT §22, not concurrent
measurement sessions.
