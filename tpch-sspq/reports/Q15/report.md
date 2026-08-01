# TPCH-SSPQ FK campaign — Q15 report

Campaign `tpch-sspq-fk-r1-20260730` · query **Q15 (Top Supplier / View Cost Ratio)** ·
pinned `ssot_commit` `cc56df92dfb91ede9bbcfd77a4823f5634a8413f`
(`ssot_blob_sha` `510478846bff081d3223d3835069283a7cd2e47b`) ·
GJC session `gajae_code_ms9qr67o_itsemzua`.

Q15 is **one logical query** (SSOT §6): `create view revenue0` → `select` → `drop view revenue0`,
handled in one query session. Every timed unit in this report is that three-statement session,
and every block proves `revenue0` absent before it starts and absent after it ends.

---

## 3-a. Causal multiplier card

```text
R_wall 0.979380x  [CUBRID FASTER by 2.11%]
= F_plan   1.004907x  [plan-shape]
× F_units  0.501351x  [total-query-CPU/wall correction, explained by TWU]
× F_cpu    1.943941x  [total query CPU-seconds]

F_cpu 1.943941x  [total query CPU-seconds]
= F_work 1.000000x  [lineitem heap rows read per session]
× F_cost 1.943941x  [core-seconds per row read]
```

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `R_wall` | **0.979380x** | wall seconds per logical session | block-1 medians | `T_C / T_P` = 10.445000 / 10.664912 | `Q15-{cubrid,postgresql}-headline-block1.json` | direct A/B |
| `F_plan` | **1.004907x** | plan node count / shape | CUBRID **controlled** (`ORDER BY` node removed) | `T_C_native / T_C_controlled` = 10.445000 / 10.393999 | `Q15-cubrid-noorderby-headline.json` | direct A/B |
| `F_units` | **0.501351x** | core-seconds of total query CPU per wall-second | `U_C` controlled pair, `U_P` PostgreSQL native | `U_P / U_C` = 1.91609 / 3.82185 | `Q15-*-headline-telemetry-run{1,2,3}.json` | profile attribution |
| `F_cpu` | **1.943941x** | core-seconds per logical session | as above | `CPU_C / CPU_P` = 39.7243 / 20.4349 | same | profile attribution |
| `F_work` | **1.000000x** | lineitem heap rows read | both engines | `W_C / W_P` = 119,972,104 / 119,972,104 | `variants/q15-groundtruth.out`, `q15-plan-act-pg-warm.out`, `q15-trace-cubrid.out` | direct A/B |
| `F_cost` | **1.943941x** | core-seconds per row read | both engines | `(CPU_C/W_C) / (CPU_P/W_P)` = 331.11 ns / 170.33 ns | `q15-bands.txt`, `perf-stat-*.txt` | profile attribution |

**Reconstruction.** `1.004907 × 0.501351 × 1.943941 = 0.979380`; `R_wall = 0.979380`;
**residual `+0.000000%`**. As in earlier queries this is declared an *identity*, not a prediction:
`F_units × F_cpu = T_C_controlled / T_P` holds by construction once `CPU ≡ U × T`, so the residual
measures only the carry-over of `U` from the native CUBRID block to the controlled one. The one
approximation is named explicitly in the error budget below.

`F_plan` is numeric, and it is neither `UNMEASURED` nor `1.0000`. Every cost-carrying node is
identical (§4-c). The **only** node-count difference is the final ordering, and it was measured by
a same-engine A/B rather than asserted immaterial: removing CUBRID's `temp(order by)` — the node
PostgreSQL never emits because it *derives* the order — is worth 0.4907%.

### Error budget, stated before any factor is interpreted

| Source | Magnitude | Effect on the card |
|---|---|---|
| within-block sd (CUBRID / PostgreSQL, block 1) | 0.036166 s (0.346%) / 0.008340 s (0.078%) | bounds `R_wall` at ±0.35% |
| cross-block band (3 blocks/engine) | CUBRID 0.134%, PostgreSQL 0.811% | `R_wall` band **0.975746 – 0.985016** |
| `U` carry-over native → controlled CUBRID | ORDER BY node is 0.4907% of wall, 1 row, inside the serial tail | ≤0.5% on `F_cpu`; the residual absorbs it to 0 |
| `U` vs independent TWU | `TWU_P/TWU_C` = 0.499503 vs `F_units` 0.501351 | −0.3687% |
| `U` vs independent `perf stat` "CPUs utilized" | 3.752 / 1.954 vs `U` 3.82185 / 1.91609 | −1.8% / +1.9% |
| `U` block-regime vs single-session telemetry | 3.82185 vs 3.73350; 1.91609 vs 1.93390 | −2.3% / +0.9% |

**The ratio sits inside that band, so the direction — CUBRID marginally faster — is stated as
"between 0.9757x and 0.9850x", never as a precise 2.11%.** This is the Q08 carried-forward rule
for any ratio below ~1.25x, and it is why three independent blocks per engine were measured.

### The single most important qualification in this report

`F_units 0.501351x` says PostgreSQL ran Q15 at **half** CUBRID's CPU-per-wall-second. That is not
a PostgreSQL inability. Q15 is the first query in this campaign that needs **two concurrent
parallel subtrees**, and SSOT §9 configures `max_parallel_workers = 5` for PostgreSQL against
`max_parallel_workers = 100` for CUBRID — a difference §9 explicitly labels *"not global-worker
parity"*. The sibling `Gather Merge` takes all 5 slots, so when the `InitPlan` is evaluated the
global pool is empty and PostgreSQL reports **`Workers Launched: 0`** and runs 8.8 s of an
11.2 s statement single-threaded (§4-b, §8-a).

A control with the **global** pool at 12 and the **per-gather cap unchanged at 5**
(`Q15-postgresql-mpw12-headline.json`) launches 5 workers in *both* subtrees and finishes the
same logical session in **4.484525 s** — **2.3782x faster than PostgreSQL's own contract number,
and 2.3291x faster than CUBRID**. Q15's near-parity is therefore a property of the configured
global budget, and this report never claims CUBRID "matches" or "beats" PostgreSQL on Q15 in any
sense beyond the §9 configuration it was measured under.

---

## 3-b. Headline timings

| Field | CUBRID | PostgreSQL |
|---|---|---|
| session 1 / 2 / 3 (headline block) | 10.403000 / 10.445000 / 10.474999 | 10.664912 / 10.659686 / 10.676017 |
| **median (headline)** | **10.445000 s** | **10.664912 s** |
| mean | 10.441000 s | 10.666872 s |
| within-block standard deviation | 0.036166 s | 0.008340 s |
| uncounted warmup session (excluded) | 10.369999 s | 11.062667 s |
| **median wall ratio** | **0.979380x** (CUBRID faster; band 0.975746–0.985016) | |
| correctness | `result-equivalent-at-SF10` | |
| censoring | none — 10.4 / 10.7 s against a 300 s timeout | |

Three values per engine, median is the headline; no confidence interval is claimed from three
values. Engine-block order was **CUBRID first, then PostgreSQL** (SSOT §12, Q15 is odd).

### The logical session decomposed, so §6's unit hides nothing

| Phase | CUBRID median | PostgreSQL median |
|---|---|---|
| `create view revenue0` | 0.001000 s | 0.000835 s |
| `select … from supplier, revenue0 …` | 10.441000 s | 10.663653 s |
| `drop view revenue0` | 0.003000 s | 0.000425 s |
| **logical session total (headline)** | **10.445000 s** | **10.664912 s** |
| DDL share of the session | **0.0383%** | **0.0118%** |

Both DDL statements together are ≤0.04% of a session on either engine, so "logical-session total"
(SSOT §6's unit) and "SELECT only" cannot disagree materially — the SELECT-only ratio is
0.979091x against the session ratio 0.979380x. Both are recorded for every block, so no reading of
§6 is foreclosed. `CREATE VIEW` is metadata-only on both engines and is proved so, not assumed:
PostgreSQL leaves `pg_class.relkind='v', relpages=0, reltuples=-1` plus one `pg_rewrite`
`_RETURN` rule of 4739 bytes, and rejects `EXPLAIN CREATE VIEW` outright because there is no plan
to show; CUBRID leaves a `db_class` row with `class_type='VCLASS'`
(`q15-plan-est-pg-createview-catalog.out`, `q15-plan-est-cubrid-createview-catalog.out`).

### All three blocks per engine

| block | CUBRID median | PostgreSQL median | ratio |
|---|---|---|---|
| 1 (**headline**) | **10.445000** | **10.664912** | 0.979380x |
| 2 | 10.458999 | 10.618106 | 0.985016x |
| 3 | 10.454999 | 10.704629 | 0.976679x |
| median of block medians | 10.454999 | 10.664912 | 0.980317x |
| band spread | 0.134% | 0.811% | |

### WARM proof

`WARM is proved, not assumed` (SSOT §12). Every block established its own steady state first, in
a separate uncounted connection, and the gate is on the **logical session total**:

| block | CUBRID | PostgreSQL |
|---|---|---|
| 1 | converged after 18 sessions, steady 10.448000, trend +0.5760%, spread 0.7944% | converged after 18, steady 10.644321, trend −0.0630%, spread 0.7249% |
| 2 | converged after 18, steady 10.438000, trend −0.4483%, spread 1.3987% | converged after 18, steady 10.613039, trend −0.1135%, spread 0.6000% |
| 3 | converged after 18, steady 10.486999, trend −0.0478%, spread 1.5448% | converged after 18, steady 10.659744, trend +0.1316%, spread 0.5592% |

**Gate parameters are measured for this query, not inherited** (`q15-warm-gate-params.txt`).
Two 20-session convergence probes were run first. At the campaign default `WINDOW=4` the gate
*rejected* the CUBRID probe with "monotone trailing window (still drifting)" on a series whose
level is not drifting: half-split drift −0.2485% against a 1.00% tolerance, trailing spread
1.5425% against a 3.00% sanity bound. That is the monotonicity test firing on jitter — for a flat
noisy series the chance that `n` consecutive samples are strictly monotone is `2/n!`, i.e. 8.3333%
at `n=4` and 0.2778% at `n=6`. `WINDOW=6` was therefore adopted (`WINDOW=8` is unusable:
`converged()` needs `3×WINDOW` samples and the probe budget is 20 sessions). `LEVEL_TOL` 1.0% and
`SPREAD_SANITY` 3.0% were left at campaign defaults; both engines pass on the measured probes.

**Physical reads and buffer state (§12 requirement).** Device reads are **zero on both engines**
across every telemetry run (`/proc/<server>/io` `read_bytes` delta = 0; `/proc/diskstats` shows
writes only) — both engines are genuinely WARM, and every buffer miss reported in §5-d is served
from the OS page cache, not the device. What differs between the engines inside that equal budget
is enormous, and it is the measured core of `F_cost`.

**Load gate.** All twelve reported blocks are `CLEAN` under both the strict per-sample rule and
the contract-window rule. Worst observed `external_max` was 2.7777 core-s/s (PostgreSQL block 1)
with `external_max_1s` 0.8324, against the §9 threshold of 6.0; means ranged 0.181–0.227. No block
was ever rejected for background load.

---

## 2. Correctness

`result-equivalent-at-SF10`. **1 row**, ordered comparison, zero mismatches.

`harness/correctness_check.py` previously refused Q15 (`"Q15 is one logical unit (create/select/
drop); use smoke_check.py"`). A Q15 branch was added this session so the per-query gate covers it:
it proves the view absent, creates it, runs the §11 comparator on the SELECT, drops it, and proves
absence again — using the same verified comparator as every other query (exact ordered sequence for
an `ORDER BY` query, raw decimal text, relative `1e-12` tolerance for output scale only).

| Step | CUBRID | PostgreSQL |
|---|---|---|
| pre-create `revenue0` exists | `false` | `false` |
| `create view` rc / view exists after | 0 / `true` | 0 / `true` |
| SELECT comparison | `result-equivalent-at-SF10`, 1 row, ordered=True | |
| `drop view` rc / view exists after | 0 / `false` | 0 / `false` |

Absence is proved from the catalogs (`db_class` on CUBRID, `information_schema.views` on
PostgreSQL), never by selecting from the view. The single result row is byte-identical on both
engines:

```text
69998 | Supplier#000069998 | ,ZT4VX2ygq9dLsG298SbYYSVUqeH,jhLSRVxNxGv | 16-386-278-9829 | 2194132.8166
```

Every headline, telemetry, profile and variant block independently re-verified
`view_state = {before_block: absent, after_block: absent}`; no block ever left `revenue0` behind.

### Dialect artifact, isolated and quantified

`queries/diff/q15_create_view.diff` carries one change, with its reason:
`DATE_ADD(DATE '1996-01-01', INTERVAL 3 MONTH)` → `date '1996-01-01' + interval '3' month`. It is
not cosmetic — it changes the comparison **type**, which the plans confirm:

| | scan filter as planned |
|---|---|
| CUBRID | `l_shipdate range (date '01/01/1996' ge_lt date '04/01/1996')` — date vs **date** |
| PostgreSQL native (dialect) | `l_shipdate < '1996-04-01 00:00:00'::timestamp without time zone` — date vs **timestamp** |
| PostgreSQL control (`datecmp`) | `l_shipdate < '1996-04-01'::date` — date vs **date** |

So the artifact is real in the plan and had to be measured, not waved away. A full gated block of
the control gives **10.771991 s against 10.664912 s native**: removing the timestamp comparison
makes PostgreSQL **1.0040% slower**, i.e. the effect is *within the PostgreSQL cross-block band
(0.811%) and of the opposite sign to a penalty*. The dialect translation therefore does not
inflate PostgreSQL's number and explains none of the ratio. Semantics are identical too — the
date-only bound selects exactly the same 2,265,714 rows (`variants/q15-groundtruth.out`).

### Independent ground truth, both engines

Needed because CUBRID's parallel trace reports `rows = readrows` (the known IMP-005 defect, §5-e),
so the trace cannot be used for the `F_work` event:

| Quantity | CUBRID | PostgreSQL |
|---|---|---|
| `lineitem` total rows | 59,986,052 | 59,986,052 |
| rows passing the `l_shipdate` range | **2,265,714** | **2,265,714** |
| distinct `l_suppkey` in the window | **100,000** | **100,000** |

PostgreSQL's plan states the same split from the other side: `rows=2265714` plus
`Rows Removed by Filter: 57720338` per expansion = 59,986,052.

---

## 1. Identity

| Item | Value |
|---|---|
| Campaign | `tpch-sspq-fk-r1-20260730` |
| SSOT commit / blob | `cc56df92dfb91ede9bbcfd77a4823f5634a8413f` / `510478846bff081d3223d3835069283a7cd2e47b` |
| GJC session | `gajae_code_ms9qr67o_itsemzua` |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (includes PR #7441 merge `b334446d6`) |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server` |
| CUBRID binary SHA-256 | `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` |
| CUBRID ELF Build ID | `4df41ee21300bf617bccd5e1d5c8522b074ef86e` (RelWithDebInfo, gcc 8.5.0-22, not stripped) |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres` |
| PostgreSQL binary SHA-256 | `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` |
| PostgreSQL ELF Build ID | `5f2cb2987765c612638c278f85cfc85c211fffe1` (optimized + debug symbols, JIT off) |
| Database / socket | `tpch_sf10_q1` (port 1523) / `tpch_sspq` (`/home/cubrid/pg/pgdata-tpch-sspq`, port 5442) |

Live-verified against the frozen `reports/bootstrap/build-manifest.json` at preflight: both binary
hashes match exactly, `frozen: true`. Both engine source trees were re-verified at their pinned
SHAs before any source citation in §7 (`git -C /home/cubrid/dev/tpch-sspq-fk-r1/cubrid-src
rev-parse HEAD` and `git -C /home/cubrid/dev/postgres rev-parse HEAD`).

**SSOT pin verification, before any measurement.** Local `HEAD` = `origin/main` =
`48c34c9c2d860795e6f8ad6ab9b52517c30c20d3`, branch `main`, `git status --porcelain -- tpch-sspq`
empty. The pinned `ssot_commit` `cc56df9` is three commits behind that `HEAD` (the intervening
commits are Q14's report and its Notion backfill record), but the `SSOT.md` **blob** is
byte-identical at the pinned commit, at `HEAD`, at `origin/main` and in the worktree:
`510478846bff081d3223d3835069283a7cd2e47b`. SSOT §2 makes the *file* the authority, and §4.7's
`HEAD == origin/main` requirement holds, so the verdict is **no `SSOT_DRIFT`** and measurement was
allowed to proceed. `preflight_check.sh` recorded the same verdict independently
(`ssot_drift=NONE (HEAD blob == pinned blob)`). The file was read completely to EOF (915 lines)
before any stage ran.

**Ownership gate (SSOT §10), before and after every block:** `cub_master` pid 1433697 and
`cub_server tpch_sf10_q1` pid 1612732 both resolve to the campaign prefix; port 1523 is owned by
that `cub_master`; the PostgreSQL postmaster pid 1433696 resolves to the campaign prefix with
`PGDATA=/home/cubrid/pg/pgdata-tpch-sspq` on port 5442. Classification **`OK`** (campaign-owned and
correct) on both sides, both times. No non-campaign process or database was stopped or touched. All
CUBRID start/stop operations would have gone through the mandated
`cubrid-server-control/scripts/cubrid-server-ctl.sh` wrapper; none were needed, because both
servers were already campaign-owned and correctly configured.

**Schema contract (§7).** 8 FKs / 8 child B-trees on both engines, exact column order,
`convalidated = t` on all eight PostgreSQL constraints, all eight `idx_fk_*` `USING btree`,
including the two-column `fk_lineitem_partsupp (l_partkey, l_suppkey)`. Row counts identical on
both engines for all eight tables (`lineitem` 59,986,052; `orders` 15,000,000; `partsupp`
8,000,000; `part` 2,000,000; `customer` 1,500,000; `supplier` 100,000; `nation` 25; `region` 5).

**Statistics (§8).** CUBRID `update_statistics_update_histogram=y`,
`default_histogram_bucket_count=300`; PostgreSQL `default_statistics_target=100`. Track label:
**histogram-enabled controlled comparison**, not "default configuration". *Carried-forward gaps
reproduced on Q15:* CUBRID's actual per-column histogram bucket count remains `UNMEASURED` (opaque
VARBIT catalog), and `pg_stat_all_tables.last_analyze` still reads `never` for all eight tables
because Q06's IMP-010 work called `pg_stat_reset()`; `pg_statistic` itself is populated and
`reltuples`/`relpages` are correct (`lineitem` 5.9987288e+07 / 1,125,128).

**Parallel, buffer and shared-memory contract (§9).** CUBRID `parallelism=6`,
`max_parallel_workers=100`, `data_buffer_size=8.0G`. PostgreSQL
`max_parallel_workers_per_gather=5`, `max_parallel_workers=5`,
`parallel_leader_participation=on`, `max_worker_processes=16`, `shared_buffers=8192MB`
(1,048,576 × 8 kB), `statement_timeout=300000 ms`, `jit=off`,
`dynamic_shared_memory_type=mmap`. Label: **configured node/gather-cap comparison** with a
**configured-equal buffer budget** — not DOP parity and **not global-worker parity**. Q15 is the
query where that last clause decides the result (§3-a, §8-a). `dynamic_shared_memory_type=mmap` is
recorded as §9 requires, because a large parallel gather is part of both engines' natural plan here.

**cpuset / NUMA.** SUT and client on CPUs `0-15`, memory node0; collectors on `20-23`. All 34
engine TIDs inside the SUT set before the run (`cub_master` 2, `cub_server` 24, postmaster 1, pg
children 7), `off_cpuset = 0` → **PASS**. External SUT-set load 0.276 core-s/s at preflight against
the §9 threshold of 6.0. `numastat -p` captured pre/post for both servers; `cub_server`'s 8,891 MB
resident is 99.98% on node0 (8,851.88 MB private on node0 against 1.56 MB on node1).

**Query provenance (§6).** `queries/q15-cubrid.sql` SHA-256
`86f7ed4d6c9b0c6b59e84fbb4a8cc7b3329337a800a8a6a2cd8311f41a776ca1` byte-matches the canonical
`/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q15.sql`. The three split files match their
canonical counterparts exactly: `q15_create_view` `31123071066b6b97…`, `q15_select`
`4f9065885660078f…`, `q15_drop_view` `ca285fe85df8f2d1…`. `q15_select` and `q15_drop_view` are
**byte-identical between the CUBRID and PostgreSQL dialects** (zero-byte diff artifacts); only the
view definition differs, by the one documented `DATE_ADD` translation.

---

## 4. Plan

### 4-a. CUBRID native (estimated, SQL `SET OPTIMIZATION LEVEL 514`, non-executing)

Captured in 0.024 s wall with `0 row selected` — the statement is planned, never executed. CUBRID
rewrites Q15 into **three** query statements, because `revenue0` is referenced twice:

```text
Query stmt 1 — the join's view input
temp(group by)
    subplan: sscan  class: revenue0 [= lineitem] node[0]
             sargs: term[0]   cost: 832902  card 2281165
    sort: 1 asc                cost: 843065  card 2281165

Query stmt 2 — the max() subquery's own, SEPARATE expansion of the same view
temp(group by)
    subplan: sscan  class: revenue0 [= lineitem]
             sargs: term[0]   cost: 832902  card 2281165
    sort: 1 asc                cost: 843065  card 2281165
   … then:  sscan class: revenue0(99829/194)  cost: 444 card 99829     [max over the groups]

Query stmt 3 — the outer query
temp(order by)
    subplan: idx-join (inner join)
             outer: sscan  class: revenue0 node[1](99829/194)
                    sargs: term[1]  cost: 444  card 100
             inner: iscan  class: supplier  index: pk_supplier_s_suppkey term[0]
                    cost: 3  card 100000
             cost: 497 card 100
    sort: 1 asc   cost: 503 card 100
```

Estimated 2,281,165 rows past the date range against an actual 2,265,714 — **+0.68%**, an
essentially exact selectivity estimate (`sel 0.0380283`). Nothing in Q15 is an estimation failure
on either side, on either engine.

### 4-b. PostgreSQL native (estimated and actual)

```text
Nested Loop  (cost=2776683.92..2844536.39 rows=494)  (actual 11227.809 ms, rows=1)
  Inner Unique: true
  Buffers: shared hit=2094459 read=155835, temp read=26000 written=42599
  InitPlan expr_1                                    (actual 8817.665 ms, rows=1)   <-- expansion A
    -> Aggregate  max(sum(...))
       -> Finalize GroupAggregate  rows=100000
          -> Gather Merge   Workers Planned: 5   Workers Launched: 0     <-- ZERO
             -> Sort (external merge, Disk: 7944kB)
                -> Partial HashAggregate  Batches: 5  Disk Usage: 80720kB
                   -> Parallel Seq Scan on lineitem   rows=2265714, Removed by Filter 57720338
  -> Finalize GroupAggregate  rows=1, Removed by Filter 99999            <-- expansion B
     -> Gather Merge    Workers Planned: 5   Workers Launched: 5
        -> Sort (external merge, Disk: 7744kB) x6
           -> Partial HashAggregate  Batches: 5  Disk Usage: 15128kB x6
              -> Parallel Seq Scan on lineitem  rows=377619 x6 loops
  -> Index Scan using supplier_pkey on supplier   rows=1, Index Searches: 1
Settings: max_parallel_workers_per_gather = '5', max_parallel_workers = '5'
Planning Time: 1.155 ms      Execution Time: 11234.885 ms
```

**`Workers Launched: 0` in the `InitPlan` is systematic, not a transient.** It reproduces
identically in the cold capture (8799.435 ms) and the warm repeat (8817.665 ms), while the sibling
`Gather Merge` launches 5 both times, and the *same* view body run standalone launches 5 workers
and completes in **2370.418 ms**. The mechanism is visible in the node timings and confirmed by
the `mpw12` control (§8-a): an `InitPlan` is evaluated **lazily**, at the moment the outer
`Finalize GroupAggregate`'s `Filter` first needs its value — by which time the sibling
`Gather Merge` has already registered 5 parallel workers, and `max_parallel_workers = 5` is
globally exhausted.

### 4-c. The plans are structurally the SAME — node by node

| Stage | CUBRID | PostgreSQL | equal? |
|---|---|---|---|
| view expansions per session | 2, sequential | 2, sequential | **yes** |
| `lineitem` access | `sscan` + `sargs term[0]` | `Parallel Seq Scan` + `Filter` | yes (full scan + pushed range) |
| rows read / passed per expansion | 59,986,052 / 2,265,714 | 59,986,052 / 2,265,714 | **yes, exactly** |
| grouping | `temp(group by)`, `hash: partial, sort: true` | `Partial HashAggregate` → `Sort` → `Finalize GroupAggregate` | yes (partial hash + sort merge) |
| groups produced | 100,000 | 100,000 | **yes, exactly** |
| spill | group-by temp, 16,266 pages | HashAgg `Disk Usage 80720kB` / `15128kB`, Sort `external merge 7944kB` | both spill |
| `max()` consumption | `sscan` over the second expansion | `Aggregate` over the `InitPlan` expansion | yes |
| supplier lookup | `iscan pk_supplier_s_suppkey`, 1 row | `Index Scan using supplier_pkey`, 1 row, `Index Searches: 1` | **yes, exactly** |
| join | `idx-join (inner join)` | `Nested Loop`, `Inner Unique: true` | yes |
| final ordering | **`temp(order by)`** | **no Sort node** | **NO — the only difference** |

PostgreSQL needs no Sort because `Gather Merge` already delivers `l_suppkey` order and the equijoin
`s_suppkey = l_suppkey` preserves it into `order by s_suppkey`. CUBRID materialises a
`temp(order by)` instead. That is the whole of `F_plan`, and §4-d measures it.

### 4-d. The `F_plan` anchor — CUBRID without the node PostgreSQL doesn't have

Same-engine A/B, same load gate, same block regime, `ORDER BY` removed from the SELECT:

| | median session | vs native |
|---|---|---|
| CUBRID native | 10.445000 s | — |
| CUBRID controlled (`noorderby`) | **10.393999 s** | **−0.4907%** |

`F_plan = 10.445000 / 10.393999 = 1.004907x`, anchor direction **CUBRID native → CUBRID
controlled**. `F_units` and `F_cpu` are then computed on the remaining cross-engine pair with the
**controlled** CUBRID denominator throughout; native and controlled denominators are never mixed.

### 4-e. Why the sequential double expansion is not a plan defect on either side

Neither engine reuses the first expansion for the second. Both re-scan and re-aggregate all of
`lineitem`. This is *common to both engines* (§7's third class), so it cancels out of the card
entirely and is not filed as a CUBRID candidate: PostgreSQL's `InitPlan` and its outer branch are
two independent subplans over the same view, exactly as CUBRID's two rewritten statements are. It
is, however, the reason Q15 needs two parallel subtrees at once, which is what exposes the
configured global-budget asymmetry.

---

## 5. Execution telemetry

### 5-a. Units, utilization and TWU

Measured **inside the §12 contract block** — a `hltel` mode was added to the Q15 harness for this
reason, mirroring what `harness/headline_telemetry.py` does for every other query, so that
`F_units × F_cpu` reconstructs the HEADLINE wall ratio and not a single-session one. Three runs per
engine:

| Quantity | CUBRID | PostgreSQL |
|---|---|---|
| `executor_cpu` (core-s / 4-session block) | 147.90 / 148.27 / 148.91 | 80.98 / 80.62 / 80.58 |
| `auxiliary_query_cpu` (core-s / block) | 16.51 / 8.84 / 11.26 | 2.28 / 2.27 / 2.27 |
| `total_query_cpu` (core-s / block) | 164.41 / 157.11 / 160.17 | 83.26 / 82.89 / 82.85 |
| `U = CPU_block / Σ statement walls` | 3.94666 / 3.76347 / **3.82185** | 1.91867 / **1.91609** / 1.91333 |
| **TWU** (actual timestamp deltas) | 3.9419 / 3.7663 / **3.8212** | 1.9088 / **1.9087** / 1.9075 |
| max simultaneous active units | 7.3217 / 7.2031 / 7.4065 | 7.4347 / 7.6041 / 7.6318 |
| serial tail | 1.576 / 1.464 / 1.464 s | 0.232 / 0.234 / 0.232 s |
| planned workers | 6 per scan (`parallelism=6`) | 5 per gather, × 2 gathers |
| **launched workers** | **6 + 6** (both expansions) | **5 + 0** (`InitPlan` got none) |

`U` and TWU are independent statistics and agree to **0.37%** on the ratio. `perf stat` on the
verified PID sets is a third, fully independent instrument and agrees again: **3.752 CPUs
utilized** for CUBRID, **1.954** for PostgreSQL. No configured cap and no nominal sampling interval
was ever substituted for measured utilization, and no planned/launched/simultaneous/time-weighted
figure was inferred from a setting.

The `max simultaneous active units` figures (7.2–7.6) exceed both engines' configured degrees on
both sides; they are instantaneous sample peaks that include client and attributable background
threads, and they are reported as such — never as a DOP claim.

### 5-b. CPU attribution to the contract regime

`total_query_cpu` per **logical session**, from `U × T` on the pair the card uses: CUBRID
**39.7243 core-s**, PostgreSQL **20.4349 core-s**. Cross-checked by `perf stat` task-clock over its
own 45.002 s window: CUBRID 168.865 core-s / 4.308 sessions = **39.194**, PostgreSQL 87.919 /
4.220 = **20.836** — agreement to 1.3% and 2.0%. Executor and auxiliary are always reported
separately; CUBRID's auxiliary (8.84–16.51 core-s per block) is `csql` result-rendering plus
attributable `cub_server` background threads and is never folded into executor CPU. Client
formatting/transfer CPU remains auxiliary by construction. Nothing was left as
`unattributed_background` in either engine's busy window.

### 5-c. Three telemetry runs per engine (single-session regime, cross-check)

| run | CUBRID wall / exec / aux / total | PostgreSQL wall / exec / aux / total |
|---|---|---|
| 1 | 10.4443 / 36.27 / 2.34 / 38.61 | 11.0930 / 20.61 / 0.59 / 21.20 |
| 2 | 10.3224 / 36.38 / 3.50 / 39.88 | 11.1311 / 21.06 / 0.57 / 21.63 |
| 3 | 10.3924 / 36.20 / 2.60 / 38.80 | 11.1276 / 20.95 / 0.57 / 21.52 |

The single-session regime inflates PostgreSQL's wall by 4.4% (11.13 against 10.66) because the
per-TID sampler perturbs it — which is precisely why the card's `U` comes from the block-regime
harness. These runs are retained as the independent `u_crosscheck` and as the source of the I/O
deltas in §5-d.

### 5-d. Physical reads and buffer behaviour — the measured core of `F_cost`

Both engines are WARM (**zero device reads**) under a **configured-equal 8192 MB** budget. What
they do inside that budget differs by an order of magnitude, per **logical session**:

| Quantity | CUBRID | PostgreSQL | ratio |
|---|---|---|---|
| buffer fetches | 1,388,220 (2 × 694,110) | 2,250,257 (2 × 1,125,128) | 0.617x |
| buffer **misses** | **1,116,942** (558,473 + 558,469) | **268,652** | **4.16x** |
| **miss rate** | **80.46%** | **11.94%** | 6.74x |
| bytes pulled through `read()` (`rchar`) | **18.14 GiB** | **1.63 GiB** | **11.1x** |
| read syscalls (`syscr`) | **1,161,523** | **93,977** | **12.4x** |
| device reads (`read_bytes`) | **0** | **0** | — |
| temp/spill writes (3 runs) | 380.2 MiB | 666.3 MiB | 0.57x |

CUBRID's page counts come from `SET TRACE ON` (`fetch`, `ioread`) and `/proc/<pid>/io`, which
cross-check to ~6% (1,116,942 misses × 16 KiB = 17.04 GiB against a measured 18.14 GiB `rchar`, the
remainder being sort/temp file reads). *Carried-forward gap reproduced:* CUBRID's `statdump` global
perfmon counters again do not advance across a verified 4-session block — `Num_data_page_fetches`,
`_dirties` and `_flushed` all show delta 0, only LRU gauges move (`Num_data_page_lru1` +3,233,
`lru3` −3,664, `private_quota` −7,459) — reproducing Q03/Q04/Q06/Q08. PostgreSQL's numbers come
from `pg_statio_user_tables` and reconcile exactly: 268,652 + 1,981,605 = 2,250,257 against
2 × 1,125,128 relpages = 2,250,256.

**A quantified secondary cause, deliberately NOT filed as a candidate.** Part of CUBRID's miss rate
is storage density, not replacement policy: the same 59,986,052 rows occupy 682,937 × 16 KiB =
**10,670.9 MiB** on CUBRID against 1,125,128 × 8 KiB = **8,790.1 MiB** on PostgreSQL — **1.214x**,
or 186.5 against 153.6 bytes per row. Under the equal 8192 MiB budget that alone drops resident
coverage from 93.20% to 76.77%. It is recorded here with its numbers and **not** filed as an
improvement candidate, because Q15 has no source-level measurement of *where* those 32.9 bytes per
row go, and SSOT §18 forbids a candidate that is a restated observation. (Same disposition as
Q06's cardinality note.)

### 5-e. CUBRID trace — both expansions parallel, the group-by serial

```text
SELECT (time: 11121, fetch: 6097536, fetch_time: 8593, ioread: 1158338)
  SCAN (temp time: 10, fetch: 242, ioread: 242, readrows: 100000, rows: 1)
    SCAN (index: dba.supplier.pk_supplier_s_suppkey) (btree time: 0, readkeys: 1, filteredkeys: 1, rows: 1)
  SUBQUERY (uncorrelated)
    SELECT (time: 5560, ioread: 579197)                                   <-- expansion A
      SCAN (table: dba.lineitem) (heap time: 2915, fetch: 694110, ioread: 558473, readrows: 59986052)
           (parallel workers: 6, heap time: 2585..2914, readrows: 9938887..10011920, gather: mergeable list)
      GROUPBY (time: 2644, hash: partial, sort: true, page: 16266, ioread: 20711, rows: 100000)
    SELECT (time: 5551, ioread: 578896)
      SCAN (temp time: 4, fetch: 144, readrows: 100000, rows: 100000)
      SUBQUERY (uncorrelated)
        SELECT (time: 5528, ioread: 578844)                               <-- expansion B
          SCAN (table: dba.lineitem) (heap time: 2891, fetch: 694110, ioread: 558469, readrows: 59986052)
               (parallel workers: 6, heap time: 2570..2891, readrows: 9938887..10011920, gather: mergeable list)
          GROUPBY (time: 2636, hash: partial, sort: true, page: 16219, ioread: 20362, rows: 100000)
```

Three things are measured here. **(i)** Both expansions run the `lineitem` scan at **6 parallel
workers** with near-perfect balance (9,938,887–10,011,920 rows each), and they run **sequentially**
(5560 + 5551 ≈ 11111 ≈ the 11121 total) — the same sequential double expansion PostgreSQL performs.
**(ii)** The `GROUPBY` lines carry **no `parallel workers` sub-line at all**: CUBRID's group-by is
**serial**, 2644 + 2636 = 5280 ms of an 11121 ms statement at one active unit. §8-b measures what
that costs. **(iii)** `rows: 59986052` on the scan is the **IMP-005** defect (the parallel path
overwrites `rows` with `readrows`); ground truth is 2,265,714, verified independently on both
engines — so Q15 becomes another Q relation for that existing candidate.

---

## 6. Profile

Non-headline. `perf stat` and `perf record` on **verified PID sets** — CUBRID attached to
`cub_server` pid 1612732 (all 32 query worker threads live inside that process), PostgreSQL
attached to the **postmaster before the client connected** so inherit-on-fork counts the leader and
every statement's workers. Coverage validated against `perf stat`: **zero `[unknown]` symbol lines**
and **zero lost samples** on both sides (CUBRID 190,340 samples / 800 flat lines; PostgreSQL 84,385
samples / 1,849 flat lines). No all-CPU profile was used.

| | cycles | instructions | IPC | task-clock | CPUs utilized |
|---|---|---|---|---|---|
| CUBRID | 463.53 G | 922.10 G | **1.99** | 168.865 core-s | 3.752 |
| PostgreSQL | 246.30 G | 452.82 G | **1.84** | 87.919 core-s | 1.954 |

Per logical session that is 107.59 G against 58.37 G cycles and 214.02 G against 107.31 G
instructions — **1,784 against 894 instructions per `lineitem` row read, a 1.996x ratio** that
independently reproduces `F_cost = 1.9439x`. CUBRID's IPC is *higher*: it is not stalling, it is
retiring almost exactly twice the instructions for the same row.

*Stage caveat, recorded rather than hidden:* the pre-profile warm-up used 12 sessions, below the
`3 × WINDOW = 18` that `converged()` needs to *declare* convergence, so its gate printed
"insufficient statements". The engine was still driven through 12 full logical sessions (~2 min)
immediately before profiling, and perf is explicitly non-headline, so no headline value depends on
this.

### 6-a. CUBRID top symbols (≥0.5%), absolute core-seconds per session

| band | % | core-s | symbols |
|---|---|---|---|
| record/slot decode + MVCC header | 16.86 | 6.608 | `or_mvcc_get_repid_and_flags` 2.34, `or_mvcc_get_header` 1.90, `or_header_size` 0.79, `spage_get_record_data` 1.60, `spage_get_record` 1.30, `spage_get_record_type` 1.11, `spage_next_record` 1.04, `heap_scan_get_visible_version` 2.13, `heap_next_1page` 3.92, `heap_page_is_bestspace` 0.73 |
| sarg / predicate evaluation | 15.20 | 5.957 | `eval_pred` 6.88, `tp_value_compare_with_error` 4.11, `eval_value_rel_cmp` 2.44, `eval_data_filter` 1.77 |
| per-row DB_VALUE materialisation | 12.43 | 4.872 | `heap_attrinfo_read_dbvalues` 8.97, `pr_clear_value` 1.18, `fetch_val_list` 1.53, `mr_data_readval_date` 0.75 |
| **page read: kernel copy + pread path** | **11.67** | **4.574** | `rep_movs_alternative` 9.76, `filemap_get_read_batch` 1.17, `filemap_read` 0.74 |
| **buffer replacement victim search** | **10.19** | **3.994** | `pgbuf_get_victim_candidates_from_lru` |
| buffer fix/unfix/latch + mutex | 4.94 | 1.936 | `pgbuf_fix_release` 1.88, `pgbuf_unfix` 0.92, `pgbuf_unlatch_void_zone_bcb` 0.92, `__pthread_mutex_lock` 1.22 |
| parallel scan slot iteration | 2.70 | 1.058 | `parallel_scan::slot_iterator::next_qualified_slot_with_peek` |
| sort / group-by merge | 2.58 | 1.011 | `qfile_compare_partial_sort_record` 1.84, `sort_run_merge` 0.74 |
| numeric arithmetic | 0.70 | 0.274 | `float_numeric_db_value_mul` |
| **accounted** | **77.27** | **30.285** | |

The `rep_movs_alternative` band is not ambiguous — its call graph is
`__libc_pread64 ← fileio_read ← pgbuf_claim_bcb_for_fix ← pgbuf_fix_release`, i.e. the kernel
copying a single 16 KiB page into CUBRID's buffer pool, on the query thread itself.

### 6-b. PostgreSQL top symbols (≥0.5%), absolute core-seconds per session

| band | % | core-s | symbols |
|---|---|---|---|
| tuple deform to Datum array | 41.77 | 8.703 | `tts_buffer_heap_getsomeattrs` 35.52, `tts_minimal_getsomeattrs` 0.90, `ExecStoreBufferHeapTuple` 1.56, `ExecStoreMinimalTuple` 0.91, `heap_fill_tuple` 1.16, `detoast_attr` 0.94, `__memmove_evex_unaligned_erms` 0.78 |
| compiled expression evaluation | 11.68 | 2.434 | `ExecInterpExpr` 8.18, `ExecSeqScanWithQual` 2.74, `make_result_safe` 0.76 |
| heap scan / page access | 9.15 | 1.906 | `heapgettup_pagemode` 5.07, `heap_getnextslot` 1.49, `heap_prepare_pagescan` 1.03, `heap_page_prune_opt` 1.56 |
| hash aggregate | 5.95 | 1.240 | `hash_search_with_hash_value` 3.31, `LookupTupleHashEntry` 1.20, `LookupTupleHashEntryHash` 0.67, `hashagg_spill_tuple` 0.77 |
| numeric arithmetic | 4.45 | 0.927 | `do_numeric_accum` 1.16, `init_var_from_num` 1.14, `accum_sum_add` 0.95, `sub_abs` 0.62, `mul_var` 0.58 |
| page read: kernel copy + mapping | 3.88 | 0.808 | `next_uptodate_folio` 2.55, `filemap_map_pages` 0.76, `folio_remove_rmap_ptes` 0.57 |
| memory context | 1.95 | 0.406 | `AllocSetAlloc` 1.35, `MemoryContextReset` 0.60 |
| buffer pin + lwlock | 1.62 | 0.338 | `PinBuffer` 0.93, `LWLockAttemptLock` 0.69 |
| **accounted** | **80.45** | **16.762** | |

### 6-c. Bands compared in absolute core-seconds per session

| band pair | CUBRID | PostgreSQL | gap |
|---|---|---|---|
| **buffer + page-read path** | 10.504 | 1.146 | **+9.358** |
| row materialisation / decode | 11.480 | 10.610 | +0.870 |
| **predicate evaluation** | 5.957 | 2.434 | **+3.524** |
| aggregation + sort | 1.286 | 2.573 | **−1.288** |
| sum of these gaps | | | **+12.464** |
| total measured CPU gap per session | 39.194 | 20.836 | **+18.358** |

Two results here matter more than the totals.

**Row materialisation is at parity on Q15 — CUBRID 11.480 against PostgreSQL 10.610 core-s,
+8.2%.** PostgreSQL's single largest symbol in the entire profile is
`tts_buffer_heap_getsomeattrs` at 35.52% / 8.703 core-s. Q12/Q13/Q14 filed IMP-020 on CUBRID's
per-row DB_VALUE materialisation; on Q15 that mechanism is **not** a differentiator, because Q15
projects only 4 of `lineitem`'s 16 columns and PostgreSQL pays a comparable deform cost. Stating
this prevents over-claiming an existing candidate on a query whose measurement does not support it.

**CUBRID's aggregation is cheaper than PostgreSQL's, by 1.288 core-s.** CUBRID's partial-hash +
sort group-by beats PostgreSQL's `HashAggregate` (which spills 5 batches, 80,720 kB on the serial
branch) plus its `Sort` external merges. This is a factor *below* 1.0 and it is reported as such,
not omitted for being inconvenient to the "CUBRID is slower" direction.

---

## 7. Source contrast

| Item | CUBRID `file:line` | PostgreSQL `file:line` | Difference | Class |
|---|---|---|---|---|
| Global parallel-worker budget when a second subtree asks for workers | `src/query/parallel/px_worker_manager_global.cpp:57,77-78` — pool sized from `PRM_ID_MAX_PARALLEL_WORKERS` (=100 here); `:97-138` `try_reserve_workers()` grants a **partial** reservation ("reserve as many as possible, up to requested") | `src/backend/postmaster/bgworker.c:1103-1112` — `RegisterDynamicBackgroundWorker()` returns `false` for every parallel worker once `parallel_register_count − parallel_terminate_count >= max_parallel_workers` (=5 here); the requester silently proceeds with whatever it got | CUBRID's second 6-worker expansion draws from a 100-slot pool with 94 free; PostgreSQL's second gather finds 0 of 5 free because the sibling still holds them, and reports `Workers Launched: 0` | same stage, lower measured cost (**configured** — see below) |
| When the uncorrelated scalar subquery is evaluated | `src/query/query_executor.c` — rewritten statement 2 is a separate `SUBQUERY (uncorrelated)` executed before the join consumes its outer input (trace §5-e) | `src/backend/executor/nodeSubplan.c:1094-1118` `ExecSetParamPlan()`, reached from `ExecEvalParamExec()` — an `InitPlan` is evaluated **lazily**, at first reference to its `PARAM_EXEC` | CUBRID evaluates its second expansion while no other parallel subtree holds workers; PostgreSQL's lazy evaluation lands it *inside* the sibling gather's lifetime | structural absence |
| Parallelism of a sort-based `GROUP BY` | `src/storage/external_sort.c:5229-5234` — `sort_check_parallelism()`: `if (px == NULL \|\| px->hash_eligible) return 1;`, with the flag set purely syntactically at `src/parser/xasl_generation.c:16555-16571` (a hint or an aggregate-type tree walk; **no cost comparison**) | `src/backend/executor/nodeAgg.c` + `nodeGatherMerge.c` — the partial aggregate runs inside every parallel worker and `Gather Merge` finalises; no flag disables the parallel path merely because hashing is possible | CUBRID's group-by runs serial (5,280 ms of 11,121 ms at 1 unit) whenever hash aggregation is merely *eligible*; PostgreSQL parallelises the partial aggregate unconditionally | structural absence |
| Serving a buffer miss | `src/storage/page_buffer.c` — `pgbuf_claim_bcb_for_fix → fileio_read → __libc_pread64`, a synchronous single-page `pread` on the query thread (4.574 core-s), plus `pgbuf_get_victim_candidates_from_lru` LRU victim search (3.994 core-s) | `src/backend/storage/buffer/bufmgr.c` — clock-sweep `PinBuffer`/`StrategyGetBuffer` with no per-page LRU list surgery (`PinBuffer` + `LWLockAttemptLock` = 0.338 core-s) | 10.504 against 1.146 core-s for the same zero-device-read workload | same stage, lower measured cost |
| Evaluating the scan range predicate | `eval_pred → eval_value_rel_cmp → tp_value_compare_with_error` — generic `DB_VALUE` comparator with per-call domain resolution (5.957 core-s over 119,972,104 rows) | `src/backend/executor/execExprInterp.c` `ExecInterpExpr` — the qual compiled once into type-specialised `ExprEvalStep`s (2.434 core-s over the same rows) | 2.45x on the identical row count and identical predicate | same stage, lower measured cost |
| Double evaluation of the view | two rewritten statements, each a full scan + group-by (§4-a) | `InitPlan expr_1` plus the outer branch, each a full scan + aggregate (§4-b) | **none** — neither engine reuses the first expansion | **common to both engines** |

The first row decides Q15's wall-clock, and it is classified with care: the *code* difference is
real (a partial-reservation pool against an all-or-nothing global cap), but the *measured outcome*
on Q15 is produced by the campaign's configured values (100 against 5), which SSOT §9 declares to
be deliberately non-parity. It is therefore **not** filed as a PostgreSQL defect nor as a CUBRID
advantage; §8-a quantifies both readings.

Claims of absence were searched, not assumed: `hash_eligible` was traced across
`src/parser/xasl_generation.c`, `src/query/query_executor.c`, `src/query/parallel/px_scan/`,
`src/query/xasl.h`, `src/query/{xasl_to_stream,stream_to_xasl}.c` and
`src/storage/external_sort.{c,h}` (patterns `hash_eligible`, `g_hash_eligible`,
`sort_check_parallelism`, `SORT_GROUP_BY`), and the only cost-free syntactic assignment is the one
cited above.

---

## 8. Causal decomposition details

### 8-a. Where Q15's 11 seconds actually go, on both engines

Both engines spend their session on two sequential expansions of `revenue0`. The difference is
purely how many execution units each expansion gets:

| | expansion A | expansion B | supplier lookup + order | total |
|---|---|---|---|---|
| CUBRID | 5560 ms @ **6 workers** | 5528 ms @ **6 workers** | ~33 ms | 11121 ms (trace) |
| PostgreSQL | 2340 ms @ **6 units** (5 workers + leader) | **8817 ms @ 1 unit** (`Workers Launched: 0`) | ~18 ms | 11235 ms (`Execution Time`) |

PostgreSQL executes one expansion **2.38x faster** than CUBRID executes one (2340 against
~5545 ms) and the other **1.59x slower** (8817 against 5528 ms). The two errors nearly cancel,
which is the entire reason Q15 lands at 0.9794x instead of somewhere far from 1.

**Direct controls, all measured through the same load gate and the same block regime:**

| Control | median session | reading |
|---|---|---|
| PostgreSQL native (contract) | 10.664912 s | 5 workers on one expansion, 0 on the other |
| PostgreSQL serial (`max_parallel_workers_per_gather=0`) | **16.789883 s** | the gather buys only **1.5743x**, far less than 6x, because just *one* expansion ever gets workers |
| PostgreSQL global pool 12, per-gather cap still 5 | **4.484525 s** | **both** subtrees launch 5; `Execution Time` 4571.757 ms; **2.3782x** faster than native and **2.3291x** faster than CUBRID |
| CUBRID native | 10.445000 s | 6 workers on **both** expansions |

The `mpw12` plan is proof, not inference: `InitPlan … Workers Planned: 5 / Workers Launched: 5`
**and** the sibling `Workers Planned: 5 / Workers Launched: 5`. This control is explicitly
**outside** the §9 contract and is never a headline value; it exists so the report can separate
"PostgreSQL serialises an `InitPlan`" (false) from "the configured global pool of 5 was already
fully consumed by the sibling" (true, and measured).

### 8-b. What CUBRID's serial group-by costs — a direct same-engine A/B

CUBRID's `GROUPBY` carries no `parallel workers` sub-line because `sort_check_parallelism()`
returns 1 whenever `hash_eligible` is set (`external_sort.c:5229-5234`), and
`xasl_generation.c:16555-16571` sets that flag purely syntactically. `/*+ NO_HASH_AGGREGATE */`
clears it. The trace then changes exactly as the source predicts:

| | native | `NO_HASH_AGGREGATE` |
|---|---|---|
| `GROUPBY` line, expansion A | `hash: partial, sort: true` — **no parallel sub-line** | `hash: false, sort: true` + **`(parallel workers: 3, time: 330..338)`** |
| `GROUPBY` time, A / B | 2644 / 2636 ms | **2305 / 2220 ms** |
| statement total (trace) | 11121 ms | **10305 ms** |

**Measured effect, and its honest status.** The variant's gated block was **REJECTED by the WARM
gate on all four attempts** — trailing spread 3.94%, 5.37%, 6.16%, 5.68%, all above the 3.00%
sanity bound — so it yields **no** headline-comparable number, and none is quoted. What the 80
uncounted sessions do establish is direction and a bound: median **9.2615 s** against a native
warm-session median of 10.4565 s (**−11.33%**), with **79 of 80** variant sessions faster than the
*fastest* of 60 native warm sessions (native min 10.334 s; variant max 9.818 s excluding a single
11.111 s outlier). Evidence type: **lower bound** on an improvement, not a direct A/B. The
instability is itself a finding: the path CUBRID would take with that flag cleared is ~11% faster
*and* measurably less stable.

### 8-c. Explanations considered and REJECTED, with the number that rejected them

- **"The PostgreSQL dialect's `date + interval` cast penalises PostgreSQL."** Rejected. The cast is
  real in the plan (`::timestamp without time zone` against the control's `::date`), but removing it
  makes PostgreSQL **1.0040% slower**, not faster, and that is inside its own 0.811% cross-block
  band. The sign is wrong for a penalty and the magnitude is band noise.
- **"CUBRID wins because it has the better plan."** Rejected. The plans are node-for-node identical
  on every cost-carrying stage (§4-c), with identical row counts (59,986,052 read / 2,265,714
  passed / 100,000 groups on both engines). The only node difference is worth **0.4907%** and it
  runs *against* CUBRID.
- **"CUBRID wins because PostgreSQL cannot parallelise an uncorrelated scalar subquery."** Rejected
  outright by the `mpw12` control: with a global pool of 12 and the *same* per-gather cap,
  PostgreSQL's `InitPlan` launches 5 workers and the session drops to **4.484525 s**.
- **"IMP-020 (per-row DB_VALUE materialisation) explains CUBRID's CPU."** Rejected for Q15. That
  band is **11.480 against 10.610 core-s — +8.2%, near parity** — because Q15 projects 4 of 16
  `lineitem` columns and PostgreSQL's own `tts_buffer_heap_getsomeattrs` costs 8.703 core-s. Q15 is
  therefore **not** filed as a relation on IMP-020.
- **"CUBRID's aggregation is the problem."** Rejected, sign inverted: CUBRID's group-by band is
  **1.288 core-s cheaper** than PostgreSQL's hash-aggregate + sort bands.
- **"CUBRID is stalling on memory."** Rejected: CUBRID's IPC is **1.99** against PostgreSQL's
  **1.84**. CUBRID is not stalled; it retires 1,784 instructions per row against 894.
- **"The 80.46% buffer miss rate is purely a replacement-policy failure."** Partially rejected as
  stated: 1.214x storage density (10,670.9 against 8,790.1 MiB for the same rows) drops CUBRID's
  resident coverage to 76.77% against PostgreSQL's 93.20% under the equal 8192 MB budget, so density
  is a genuine co-cause and is recorded separately (§5-d) rather than folded into the policy claim.
- **"Q15's near-parity means CUBRID is competitive on this shape."** Rejected as an
  over-generalisation: §8-a shows it is the arithmetic of one 2.38x win against one 1.59x loss under
  a configured global pool of 5, and §8-d states what remains once that is equalised.

### 8-d. What remains after the configuration is equalised

If PostgreSQL is given a global pool that can serve both of Q15's subtrees, Q15 stops being a
near-tie and becomes a **2.3291x** PostgreSQL win — and the explanation is then no longer
parallelism at all, it is `F_cost`. CUBRID spends **331.11 ns** of CPU per `lineitem` row against
PostgreSQL's **170.33 ns** for provably identical work, and §6-c localises 12.464 of the 18.358
core-s gap to two bands: the buffer + page-read path (**+9.358 core-s**) and predicate evaluation
(**+3.524 core-s**). Those two are where Q15's improvement candidates are, and both are existing
root causes receiving their largest absolute numbers so far rather than new discoveries.

---

## 9. Improvements

Q15 allocated **no new `IMP-NNN`**; `reports/improvement-registry.json` still ends at `IMP-021` with
`next_id` unchanged. The registry was synced and searched by title, CUBRID source location,
PostgreSQL source location and root cause before this decision. Every mechanism Q15 measures is
already an allocated root cause, and SSOT §18 requires reusing an existing root cause and adding Q
relations plus evidence rather than minting a duplicate.

| ID | Existing root cause | What Q15 adds | Evidence type |
|---|---|---|---|
| **IMP-002** | Data buffer replacement fails to retain a working set that marginally exceeds the pool | Q15's largest absolute figure yet: **80.46% miss rate** (1,116,942 of 1,388,220 fetches) against PostgreSQL's **11.94%** under an identical configured 8192 MB budget, with **zero device reads** on both sides, plus a quantified co-cause (1.214x storage density → 76.77% against 93.20% resident coverage). Cost: `pgbuf_get_victim_candidates_from_lru` **3.994 core-s/session, 10.19%** of CUBRID's profile | profile attribution |
| **IMP-007** | Every data-page buffer miss is served by a synchronous single-page `pread` on the query thread, with no async submission and no per-scan readahead | **1,161,523 read syscalls** and **18.14 GiB** pulled through `read()` per session, against PostgreSQL's 93,977 / 1.63 GiB — 12.4x and 11.1x. The kernel copy alone is **4.574 core-s/session (11.67%)**, call graph `rep_movs_alternative ← __libc_pread64 ← fileio_read ← pgbuf_claim_bcb_for_fix ← pgbuf_fix_release`. With IMP-002 this is **9.358 of the 18.358 core-s** CPU gap | profile attribution |
| **IMP-008** | Scan-level sarg evaluation routes every row through the generic `DB_VALUE` comparator with per-call domain resolution and coercion | **5.957 against 2.434 core-s (2.45x)** for the identical predicate on the identical 119,972,104 rows — and here that range predicate is the *only* qual, on the widest row count in the campaign so far | profile attribution |
| **IMP-013** | Every page unfix on a HIT path performs mutex-protected LRU doubly-linked-list surgery plus zone rebalancing | `pgbuf_fix_release` + `pgbuf_unfix` + `pgbuf_unlatch_void_zone_bcb` + `__pthread_mutex_lock` = **1.936 core-s/session (4.94%)** against PostgreSQL's `PinBuffer` + `LWLockAttemptLock` = **0.338 core-s (1.62%)**, a 5.7x ratio | profile attribution |
| **IMP-015** | `sort_check_parallelism()` refuses parallelism for a `SORT_GROUP_BY` whenever the query was marked hash-aggregate-eligible | First trace-level proof that the **flag alone** causes it, with no runtime abandonment involved: native `GROUPBY` has **no `parallel workers` sub-line** and costs 2644 + 2636 = **5280 ms of 11121 ms at one active unit**, while `/*+ NO_HASH_AGGREGATE */` clears `g_hash_eligible` and the same node reports **`parallel workers: 3`** at 2305 + 2220 ms. Whole-session effect **≥11.33% faster** (median 9.2615 against 10.4565 s over 80 against 60 sessions; 79/80 below the fastest native session) | **lower bound** (the variant's block was WARM-gate rejected at up to 6.16% spread; no direct A/B number is claimed) |
| **IMP-005** | Parallel-scan trace statistics are merged per `scan_ptr` level and again by the subtree walk, so counters are misreported | Q15 reproduces the `rows = readrows` defect on both expansions (`rows: 59986052` where ground truth is 2,265,714), which is exactly why the `F_work` event had to be established by independent `count(*)` on both engines rather than read from the trace | direct A/B |

**Explicitly NOT filed.** IMP-020 — row materialisation is at parity here (+8.2%, §8-c).
IMP-016 / IMP-017 — Q15's group/tuple selectivity is 100,000 / 2,265,714 = **0.0441**, nowhere near
the 0.5f heuristic, and the trace shows hash aggregation is *used* (`hash: partial`), not abandoned,
so Q15's serialisation is IMP-015's flag rather than IMP-016's runtime drift. The storage-density
observation (§5-d) — quantified but with no source-level mechanism measured in Q15, so filing it
would breach §18's ban on a candidate that restates an observation.

**Ranking of what Q15 says to fix first**, justified against the measured bands:
1. **IMP-007 + IMP-002 together** — 9.358 core-s, **51% of the measured CPU gap**, and the only
   band where CUBRID is an order of magnitude away from PostgreSQL rather than a factor of two.
2. **IMP-008** — 3.524 core-s, 19% of the gap, and the cheapest to reason about because the qual is
   a single date range over one column.
3. **IMP-015** — worth **≥11% of wall** on this query, the only one of the five that moves
   `F_units` rather than `F_cost`, but ranked third because its measured status is a bound rather
   than a direct A/B and because the faster path is also the less stable one.
4. **IMP-013** — 1.936 core-s, real but largely a consequence of the miss volume that IMP-002 and
   IMP-007 govern; fixing those first shrinks this automatically.
5. **IMP-005** — zero runtime cost; it is a correctness-of-evidence defect, and Q15 is the fourth
   query that had to work around it.

---

## 10. Evidence index

Format: `claim → raw file:line → formula → evidence type → SHA-256`. SHA-256 values for every
artifact are in `reports/Q15/raw-manifest.json`; the raw root is
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q15`.

| Claim | Raw evidence | Formula / derivation | Evidence type |
|---|---|---|---|
| No `SSOT_DRIFT`; blob identical at pin, `HEAD`, `origin/main`, worktree | `preflight-Q15.txt` `[git]` block | `git rev-parse <ref>:tpch-sspq/SSOT.md` compared with the pinned blob | direct A/B |
| Binaries match the frozen build manifest | `preflight-Q15.txt` ownership-gate block | `sha256sum` against `reports/bootstrap/build-manifest.json` | direct A/B |
| 8 FK / 8 child B-tree parity, `convalidated=t` | `preflight-Q15.txt` schema block | `db_index` / `pg_constraint` + `pg_class` catalog counts | direct A/B |
| 34/34 engine TIDs inside cpuset 0-15; external load 0.276 core-s/s | `preflight-Q15.txt` cpuset block | `sched_getaffinity` per TID; `/proc/stat` delta over 5 s | direct A/B |
| `result-equivalent-at-SF10`, 1 row, view absent before and after | `q15-correctness.json`, `q15-correctness-select-{cubrid,postgresql}.out` | §11 comparator; `db_class` / `information_schema.views` probes | direct A/B |
| `T_C = 10.445000 s`, `T_P = 10.664912 s` | `Q15-{cubrid,postgresql}-headline-block1.json` | median of 3 measured logical-session totals | direct A/B |
| Cross-block band 0.134% / 0.811% | `Q15-*-headline-block{1,2,3}.json` | `(max−min)/median` of block medians | direct A/B |
| WARM converged, gate on session totals, `WINDOW=6` | `Q15-*-warm-block{1,2,3}.json`, `q15-warm-gate-params.txt` | non-monotone trailing window + half-split level + spread | direct A/B |
| Every block `CLEAN` under both load rules | `Q15-*-bgload-block{1,2,3}.json` | `bgload_monitor.py` 0.25 s samples against 6.0 core-s/s | direct A/B |
| DDL is 0.0383% / 0.0118% of a session | `Q15-*-headline-block1.json` `create_view_only`/`drop_view_only` | `(create+drop)/session_total` | direct A/B |
| `CREATE VIEW` is metadata-only | `q15-plan-est-pg-createview-catalog.out`, `q15-plan-est-cubrid-createview-catalog.out`, `q15-plan-est-pg-createview.out` | `pg_class`/`pg_rewrite`/`db_class` rows; `EXPLAIN CREATE VIEW` rejected | direct A/B |
| CUBRID estimated plan, non-executing, 0.024 s | `q15-plan-est-cubrid.out`, `q15-plan-est-cubrid.time` | `SET OPTIMIZATION LEVEL 514` | direct A/B |
| `Workers Launched: 0` in the `InitPlan`, both captures | `q15-plan-act-pg.out:16`, `q15-plan-act-pg-warm.out:16` | `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, TIMING, SETTINGS)` | direct A/B |
| Standalone view body launches 5 workers, 2370.418 ms | `q15-plan-act-pg-viewbody.out:7-8,68` | same | direct A/B |
| Both CUBRID expansions at 6 workers; group-by serial | `q15-trace-cubrid.out` Trace Statistics | `SET TRACE ON` + `SHOW TRACE` | direct A/B |
| `W_C = W_P = 119,972,104` rows; 2,265,714 filtered; 100,000 groups | `variants/q15-groundtruth.out`, `q15-plan-act-pg-warm.out` | `count(*)` on both engines; plan `rows` + `Rows Removed by Filter` | direct A/B |
| `U_C = 3.82185`, `U_P = 1.91609` | `Q15-*-headline-telemetry-run{1,2,3}.json` | `CPU_block / Σ statement walls`, in-block | profile attribution |
| TWU 3.8212 / 1.9087, actual-delta weighted | same | Σ`units×dt` / Σ`dt` over the busy window | profile attribution |
| `perf stat` 3.752 / 1.954 CPUs utilized | `perf-stat-cubrid.txt`, `perf-stat-pg.txt` | task-clock / elapsed on verified PID sets | profile attribution |
| CUBRID 1,116,942 misses, 18.14 GiB, 1,161,523 syscalls; PG 268,652 / 1.63 GiB / 93,977 | `q15-trace-cubrid.out`, `q15-{cubrid,postgresql}-io-{pre,mid,post}.txt`, `q15-pg-statio-*.txt` | trace `ioread`; `/proc/<pid>/io` deltas; `pg_statio_user_tables` deltas | direct A/B |
| Zero device reads on both engines | `q15-*-io-*.txt` `read_bytes`, `q15-*-diskstats-*.txt` | pre/post delta | direct A/B |
| CUBRID `statdump` counters frozen (delta 0) | `Q15-cubrid-headline-block1.json` `buffer_counters` | pre/post delta across the block | direct A/B |
| Profile bands, absolute core-s per session | `profile-{cubrid,pg}-flat-nocg.txt`, `q15-bands.txt` | `band% × (task-clock/sessions in window)` | profile attribution |
| 1,784 vs 894 instructions per row | `perf-stat-*.txt`, `q15-bands.txt` | `instructions / sessions / 119,972,104` | profile attribution |
| `F_plan = 1.004907x` | `Q15-cubrid-noorderby-headline.json` | `T_C_native / T_C_controlled` | direct A/B |
| PG serial 16.789883 s; `mpw12` 4.484525 s; `datecmp` 10.771991 s | `Q15-postgresql-{noparallel,mpw12,datecmp}-headline.json` | median of 3 measured session totals per gated block | direct A/B |
| `mpw12` launches 5 workers in both subtrees | `variants/q15-plan-act-pg-mpw12.out:15-16,81-82,148` | `EXPLAIN (ANALYZE …)` under `PGOPTIONS` | direct A/B |
| `NO_HASH_AGGREGATE` → `parallel workers: 3` on the group-by | `variants/q15-trace-cubrid-nohashagg.out` | `SET TRACE ON` + `SHOW TRACE` | direct A/B |
| `NO_HASH_AGGREGATE` ≥11.33% faster, 79/80 sessions | `Q15-cubrid-nohashagg-warm-attempt{1,2,3,4}.json` | median of 80 uncounted sessions against 60 native | lower bound |
| Card closes with residual +0.000000% | `q15-card.json` | `F_plan × F_units × F_cpu` against `R_wall` | derived |

---

## 11. Notion sync

**Not performed by this session, by contract.** SSOT §21's execution boundary states that the
GJC/tmux worker session runs on the remote build host, has no Notion connector, and **must never
attempt a Notion write**; its Notion-adjacent duty ends at committing and pushing the report and
manifest to `origin/main`. Accordingly this session used **write path 3**: an idempotent record was
appended to `reports/notion_backfill_pending.jsonl`, keyed by
`campaign_id + QNN + session_id + report_commit + content_fingerprint`, carrying the full §21
content payload (causal card with the factor table, headline timings, plan comparison for both
engines, profile top symbols for both engines, the complete source contrast with `file:line` on
both sides, the causal-decomposition narrative including the rejected explanations and the numbers
that rejected them, and the six improvement relations with their evidence). The pending record is
to be consumed by the dedicated §23 reconciler subagent with Notion tool access, reading the pushed
GitHub commit as source of truth; it must be cleared only after a server-side refetch.

---

## 12. Completion checklist

| SSOT §26 gate | Status |
|---|---|
| preflight and correctness status recorded | **yes** — §1, §2; `preflight-Q15.txt`, `q15-correctness.json` |
| three valid headline values for each completing engine | **yes** — 3 measured logical sessions per engine per block, 3 blocks per engine, all 12 blocks `CLEAN` |
| timeout confirmations if censored | **n/a** — 10.4 / 10.7 s against a 300 s timeout; nothing censored |
| plan, execution, profile and source contrast complete | **yes** — §4, §5, §6, §7 |
| causal multiplier card has evidence or explicit `UNMEASURED` | **yes** — all six factors numeric with unit, denominator, formula, raw pointer and evidence type; residual +0.000000% |
| Git improvement ledger deduplicated and committed | **yes** — no new ID; six existing candidates gained Q15 relations, `next_id` unchanged |
| Notion relations synced or an idempotent backfill record durable | **backfill record durable** (write path 3); Notion write is the §23 reconciler's step, forbidden to this session by §21 |
| every claim indexed to raw evidence and checksum | **yes** — §10 plus `reports/Q15/raw-manifest.json` |
| report, manifest and registry committed, pushed, reachable from `origin/main` | **yes** — see the commit recorded in the manifest and the backfill record |
| `QUERY_COMPLETE` emitted | **yes** |
| current session removed and absence verified | **owed by the controller.** A GJC session cannot remove itself. SSOT §22 steps 7–8 (`gjc session remove gajae_code_ms9qr67o_itsemzua`, then absence verified with **both** `gjc session status gajae_code_ms9qr67o_itsemzua` and `tmux has-session -t gajae_code_ms9qr67o_itsemzua`) are the transition owner's step, and only then may the Q16 session be created |

Child tmux sessions spawned by this session to host long-running block drivers (`q15conv`,
`q15hl`, `q15tel`, `q15hltel`, `q15perf`, `q15var`) are an implementation detail of this single
query session per SSOT §22, not concurrent measurement sessions. Each was polled for its explicit
`ALL_BLOCKS_DONE` marker and none remains alive.

**Harness changes committed with this query** (all additive; no existing query's reproducibility is
affected):
- `harness/correctness_check.py` — added the Q15 branch that previously delegated to
  `smoke_check.py`, so the per-query §11 gate now covers the create/select/drop unit with
  catalog-based view-absence proofs on both sides.
- `harness/q15_session.py` — new. The Q15 logical-session harness: `warm`, `headline` and `hltel`
  modes over the three-statement session, with per-phase and per-session accounting. Needed because
  `headline_run.py` would repeat the file four times and then slice statement times 1..3, which on
  Q15 mixes one session's SELECT with the next session's DDL and would report a `DROP VIEW` as a
  headline value.
- `harness/q15_gated_block.sh` — new. Identical gate policy to `measure_block.sh` (quiet pre-gate,
  `bgload_monitor.py`, `CLEAN`/`INVALID_BACKGROUND_LOAD` verdict, every attempt preserved, canonical
  names removed up front), driving `q15_session.py` instead of `warm_establish.py` +
  `headline_run.py`.

**Carried-forward gaps after Q15:**
- CUBRID's actual per-column histogram bucket count is still `UNMEASURED` (opaque VARBIT catalog);
  target 300 is configured and verified.
- CUBRID's `statdump -c` global perfmon counters still do not advance per statement (Q03/Q04/Q06/
  Q08/Q15). All CUBRID page evidence comes from `SET TRACE ON` and `/proc/<pid>/io`, which
  cross-check to ~6% here.
- `pg_stat_all_tables.last_analyze` still reads `never` for all eight tables because Q06's IMP-010
  work called `pg_stat_reset()`; `pg_statistic` is populated and `reltuples`/`relpages` are correct.
- IMP-005's `rows = readrows` trace defect still forces independent ground truth for any `F_work`
  event on a parallel CUBRID scan.
- **New, Q15-specific:** the campaign's `max_parallel_workers` asymmetry (CUBRID 100 against
  PostgreSQL 5) is measurement-relevant for any query needing two concurrent parallel subtrees.
  Q15 is the first such query and the effect is 2.3782x on PostgreSQL. A future SSOT amendment
  should decide whether §9 keeps the current deliberate non-parity — this report does **not**
  change the contract mid-query; it measures and labels it.
- **New, Q15-specific:** the WARM gate's trailing-window monotonicity test rejects a converged
  series with probability `2/WINDOW!` (8.33% at the campaign default `WINDOW=4`). Q15 raised
  `WINDOW` to 6 from its own probes; a future harness change should make this the campaign default
  rather than a per-query derivation.

`QUERY_COMPLETE`
