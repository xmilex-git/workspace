# TPCH-SSPQ FK campaign — Q06 report

## 3-a. Causal multiplier card

```text
R_wall 2.394672x [wall, median of 3 per engine; PostgreSQL is 2.3947x faster]
= F_plan  1.000000x [plan-shape; structural equality, proved below]
× F_units 0.974111x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   2.458314x [total query CPU-seconds]

F_cpu 2.458314x [total query CPU-seconds]
= F_work 1.000000x [heap rows scanned: 59,986,052 vs 59,986,052 — exactly equal]
× F_cost 2.458314x [total-query CPU-seconds per scanned row: 385.56 ns vs 156.84 ns]
```

**Read the card in one line: the two engines run the same plan, scan the same 59,986,052
rows, and keep the same number of cores busy (5.97 vs 5.81). CUBRID loses 2.39x because
it spends 1,094 cycles on a row where PostgreSQL spends 430.**

Q06 is the campaign's first query where **every factor except one is exactly 1**. That is
not a weakness of the decomposition, it is the finding: with plan shape, work volume and
parallel width all controlled to equality by measurement rather than by assumption, the
whole gap is per-row execution cost, and section 6 localizes 90.3% of it to four named
bands.

`F_plan = 1.0000` is assigned **numerically, on structural equality**, which section 16
permits only when equality is proved. Four independent proofs, not one:

1. **Same shape.** CUBRID: single `sscan` on `lineitem` carrying all three sargs, into a
   `buildvalue` gather (`q6-plan-est-cubrid.out`, `q6-trace-cubrid.out`). PostgreSQL:
   `Parallel Seq Scan on lineitem` with the same three predicates as `Filter`, into
   `Partial Aggregate → Gather → Finalize Aggregate` (`q6-plan-act-pg.out`). One scan
   node, one per-unit partial aggregate, one gather, one final value, on both sides.
2. **Same rows in.** 59,986,052 scanned on both, per-worker breakdowns summing exactly
   (CUBRID `readrows: 9,938,887..10,011,920` × 6; PostgreSQL `rows=189877.33 loops=6`
   plus `Rows Removed by Filter: 9807798` × 6 = 1,139,264 + 58,846,788 = 59,986,052).
3. **Same rows out.** 1,139,264 qualifying rows and the byte-identical scalar
   `1230113636.0101`, both confirmed against independent `count(*)` ground truth run on
   both engines (`q6-groundtruth-cubrid.out`, `q6-groundtruth-pg.out`).
4. **No alternative existed.** `lineitem` carries a primary key on
   `(l_orderkey, l_linenumber)`, `fk_lineitem_orders (l_orderkey)` and
   `fk_lineitem_partsupp (l_partkey, l_suppkey)`, and Q06's sargs are on `l_shipdate`,
   `l_discount` and `l_quantity` — no index covers any of them, so a full scan is the
   only access path either optimizer could choose. `F_plan` cannot be hiding a plan
   decision because neither engine had one to make.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 1.000000x | plan-node shape | — (structural equality, not a ratio) | four proofs above | `q6-plan-est-cubrid.out`, `q6-plan-est-pg.out`, `q6-plan-act-pg.out`, `q6-trace-cubrid.out`, `q6-groundtruth-*.out` | direct A/B |
| `F_units` | 0.974111x | active execution units | CPU-seconds / wall-second over the section 12 block | `U_P/U_C` = 5.81408/5.96860 | `Q06-postgresql-headline-telemetry-run3.json`, `Q06-cubrid-headline-telemetry-run2.json` | profile attribution |
| `F_cpu` | 2.458314x | total query CPU-seconds | per query execution | `CPU_C/CPU_P` = 23.1283/9.4082 | same telemetry JSONs | profile attribution |
| `F_work` | 1.000000x | heap rows scanned | rows | `W_C/W_P` = 59,986,052/59,986,052 | `q6-trace-cubrid.out`, `q6-plan-act-pg.out`, `q6-groundtruth-*.out` | direct A/B |
| `F_cost` | 2.458314x | CPU-seconds per scanned row | scanned rows | `(CPU_C/W_C)/(CPU_P/W_P)` = 385.56 ns / 156.84 ns | `Q06-causal-card.json`, `q6-bands.txt` | profile attribution |

**`F_units` is below 1, so CUBRID's parallelism is not the problem on Q06 — it is
marginally CUBRID's advantage.** After Q05, where `F_units = 5.2771x` was the entire
loss, this is worth stating plainly: at the same configured cap (6 vs 5+leader) CUBRID
measures **5.9686** active units against PostgreSQL's **5.81408**, and its serial tail is
**0.000 s** against PostgreSQL's **0.232 s** `Gather`/`Finalize` tail. The
`configured node/gather-cap comparison` label happens to coincide with measured width
here; that coincidence is a measurement, not an inference from settings.

**Reconstruction residual = 0.000000%, and as on Q04 and Q05 that is an identity, not a
prediction.** `CPU_stmt` is attributed as `U × t_median` with `U` measured on the same
block the headline is defined on, so `F_units × F_cpu = T_C/T_P` by construction. Closure
therefore rests entirely on the independent quantities, and Q06 has four:

- **`U` reproducibility.** CUBRID 5.96500 / 5.96860 / 5.97964 across three independently
  gated telemetry runs — a **0.25%** max-min spread, the tightest in the campaign.
  PostgreSQL 5.84122 / 5.80618 / 5.81408, **0.60%**.
- **TWU**, computed from actual sample timestamp deltas over the busy window only, gives
  **5.9498** (CUBRID, **0.31%** from `U`) and **5.5784** (PostgreSQL, **4.05%** from `U`
  — the whole discrepancy is the 0.232 s serial tail, which TWU spans and `U` averages
  over).
- **`perf stat` on verified PID sets**, a third instrument: **6.008 CPUs utilized** for
  CUBRID (**+0.66%** against `U = 5.9686`) and **5.718** / **5.739** across two captures
  for PostgreSQL's executor set against an executor-only `U` of 5.6068 (**+2.0%** /
  **+2.4%**). *Q06 is the first query in this campaign where `perf stat` yields a valid
  PostgreSQL utilization number at all*; section 6 explains the harness fix that made it
  possible and section 12 records it as a closed campaign gap.
- **Instructions and IPC**, an entirely separate counter path: CUBRID executes **2,515
  instructions per scanned row at IPC 2.30**, PostgreSQL **762 at IPC 1.77**. That is a
  3.30x instruction ratio recovered by a 1.2994x IPC advantage → **2.539x**, against the
  measured executor-CPU ratio of **2.5457x**, closing to **0.3%**.

**A wall-clock-only view of the same result, and why it is not offered as a check.** With
the scan forced serial on both engines the medians are CUBRID 20.562 s and PostgreSQL
6.5699 s (`q6-counterfactuals.txt`), a **3.1297x** ratio, and telemetry confirms both are
genuinely single-unit (`U` = 1.00333 and 1.03859). Dividing that by the parallel-speedup
ratio (CUBRID 5.3063x ÷ PostgreSQL 4.0601x = 1.30696x) returns 2.394672x — but that is
*algebraically* `T_C/T_P` again, so it is an identity and is **not** presented as
independent confirmation. What the serial pair does contribute is genuinely new
information, and it is the most interesting number in the report: **single-threaded,
CUBRID's per-row cost ratio is 3.1297x, worse than the 2.4583x it shows in the parallel
regime.** CUBRID parallelizes *better* (5.31x on 6 units, 88% efficiency) than PostgreSQL
(4.06x on 5+leader, 68%), and that advantage claws back 1.27x of a 3.13x deficit.
Section 8 attributes both engines' parallel CPU inflation to named bands.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q06 |
| SSOT commit | `d19dca410b7fc8382d52f4ee7d79175d0a16e203` |
| SSOT blob | `76778d21ae437e87575c4ef7c609a9ccea81e6f1` |
| GJC session ID | `gajae_code_ms7ztf7g_9w2w4xfn` |
| Raw dir | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q06` |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13`, ELF Build ID `4df41ee21300bf617bccd5e1d5c8522b074ef86e` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b`, ELF Build ID `5f2cb2987765c612638c278f85cfc85c211fffe1` |
| CUBRID DB / port | `tpch_sf10_q1` / 1523 (`cub_server` pid 1612732, `cub_master` pid 1433697) |
| PostgreSQL PGDATA / port | `/home/cubrid/pg/pgdata-tpch-sspq` / 5442 (postmaster pid 1433696) |

Both running binaries hash-match the frozen `reports/bootstrap/build-manifest.json`. **No
server was started, stopped or restarted during Q06** — both engines ran on the processes
that survived Q05, so no start-time identity re-verification was required and none is
claimed. Ownership gates (section 10) classified **OK** before (`preflight-Q06.txt`) and
after (`q6-postcheck.txt`) the measurement blocks; the post-block gate records **0 orphan
`csql`, 0 orphan `psql`, 0 parallel workers, 0 client backends, 36 engine TIDs with 0
off-cpuset**, and the CUBRID pool conserved at exactly **524,288 pages** (8 GiB / 16 KiB).

**No SSOT drift.** `HEAD` = `origin/main` = `1faea891136342989f62fc4d8de36d4feb9282e0` at
both preflight and post-check, and `HEAD:tpch-sspq/SSOT.md` = the pinned blob
`76778d21…` at both times. The pinned `ssot_commit d19dca41…` is the commit that last
modified `SSOT.md`; the two commits since (`e89194b`, `1faea89`) are Q05's report and
backfill record and touch no rule. `git status --porcelain -- tpch-sspq` was empty at
both gates. `SSOT_DRIFT = NONE`.

Query provenance: `queries/q6-cubrid.sql` byte-matches the canonical source
`/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q6.sql`, SHA-256
`fc3777c90f604fae417dba1cd9a5974e8ee0afd474f0ac9f5a6927b5663c8367` (`cmp` verified). The
PostgreSQL dialect (`6c0092060f249a660d16e277a9e40cb43d4e43a54f9b97cf57c818bedc24e741`)
differs in exactly one line, recorded in `queries/diff/q6.diff`:
`DATE_ADD(DATE '1994-01-01', INTERVAL 1 YEAR)` → `date '1994-01-01' + interval '1' year`,
because CUBRID's `DATE_ADD` has no PostgreSQL equivalent. No hint, join reordering,
subquery rewrite, extra predicate or semantic cast exists in either measured file.

**That one dialect line has a measurable consequence, and it was measured rather than
assumed.** PostgreSQL's `date + interval` yields a *timestamp*, so its plan shows
`l_shipdate < '1995-01-01 00:00:00'::timestamp` and pays a date→timestamp promotion on
every row (`date_cmp_timestamp_internal` 0.64%, `date_lt_timestamp` 0.46%), where CUBRID's
`DATE_ADD` yields a date and compares date-to-date. A diagnostic variant replacing the
expression with the literal `date '1995-01-01'` — never a measured dialect file — runs at
**1607.452 ms against the dialect file's 1610.603 ms, a 0.20% difference**
(`q6-counterfactuals.txt`), inside the block noise. The dialect choice does not bias the
headline, and now that is a number rather than a presumption.

Schema: 8 named FKs and 8 corresponding child B-trees verified on both engines with exact
child-column order; all PostgreSQL `pg_constraint.convalidated = true` (8/8/8). Row counts
exact-equal on both engines (`lineitem` 59,986,052, `orders` 15,000,000, `partsupp`
8,000,000, `part` 2,000,000, `customer` 1,500,000, `supplier` 100,000, `nation` 25,
`region` 5). **Q06 references only `lineitem` and uses none of the FK indexes**, which is
why it is the campaign's cleanest per-row-cost measurement: no join, no index, no sort, no
grouping, one aggregate.

Contract state at measurement time:

- statistics: CUBRID `update_statistics_update_histogram=y`,
  `default_histogram_bucket_count=300` (target). Actual per-column bucket count remains
  **UNMEASURED** (opaque serialized `VARBIT` in `_db_histogram`) — carried forward from
  bootstrap and Q01–Q05. PostgreSQL standard `ANALYZE`,
  `default_statistics_target=100`, all eight tables last analyzed 2026-07-30 17:54.
- parallel, `configured node/gather-cap comparison`: CUBRID `parallelism=6`,
  `max_parallel_workers=100`; PostgreSQL `max_parallel_workers_per_gather=5`,
  `max_parallel_workers=5`, `parallel_leader_participation=on`,
  `max_worker_processes=16` (non-binding), `statement_timeout=300000 ms`, `jit=off`,
  `debug_assertions=off`. On Q06 the configured caps (6 and 5+leader) and the measured
  units (5.97 and 5.81) agree — the one query so far where they do.
- buffer/cache, `configured-equal buffer budget`: CUBRID `data_buffer_size=8.0G`
  (`data_buffer_pages=524288`), PostgreSQL `shared_buffers=8192MB` (1,048,576 buffers).
  **Neither engine's working set fits**: `lineitem` is 682,937 CUBRID heap pages
  (10,670.9 MiB at 16 KiB) and 1,125,128 PostgreSQL pages (8,790 MiB at 8 KiB), so both
  exceed their pool by 30.2% and 7.3% respectively. Section 5 makes that the report's
  second finding.
- shared memory, `parallel-plan-availability parity`: PostgreSQL
  `dynamic_shared_memory_type=mmap`, verified live with `source=configuration file`,
  `sourcefile=postgresql.conf:969`. Q06's plan contains a `Gather`, so section 9 makes
  recording it mandatory; unlike Q05 the DSM demand here is trivial (six partial
  aggregate rows in the tuple queue) and no DSM poll was taken.
- I/O path, recorded because section 5 and section 7 both depend on it: PostgreSQL
  `io_method=worker`, `io_combine_limit=16` (× 8 kB = 128 kB max per read),
  `effective_io_concurrency=16`, all at `source=default`.
- cpuset/NUMA: SUT+client CPUs `0-15` (node0), collectors CPUs `20-23`. **34 engine TIDs
  at preflight and 36 after the blocks, 0 off-cpuset both times.** `cub_server`
  8,626.16 MB node0 / 4.62 MB node1 (99.95% node0); postmaster 165.48 MB node0 /
  0.60 MB node1.
- external SUT-set load was **within contract throughout**: 0.512 core-s/s at preflight
  and 0.334 at post-check (threshold 1.5), and all twelve accepted headline blocks plus
  all six telemetry runs and both perf windows verified `CLEAN` at 4 Hz, with
  `external_max` between 0.42 and 1.29. **One block-5 attempt was rejected as
  `INVALID_BACKGROUND_LOAD` and retried** (section 3-b).

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored.

Q06 has no `ORDER BY` and returns exactly one row, so the section 11 canonical-sort rule
is trivially satisfied; row count, row multiset and raw decimal text were compared as
usual.

| Field | CUBRID | PostgreSQL |
|---|---|---|
| `revenue` | `1230113636.0101` | `1230113636.0101` |

The two 17-byte outputs are **byte-identical**, so the 1e-12 relative tolerance was
available but **never entered**. Comparator: `harness/correctness_check.py` delegating to
the bootstrap-verified `harness/smoke_check.py` rules (`q6-correctness.json`,
`q6-correctness-cubrid.out`, `q6-correctness-postgresql.out`).

Independent ground truth, identical on both engines (`q6-groundtruth-cubrid.out`,
`q6-groundtruth-pg.out`), used later for `W`, for `F_work`, and as the control that
exposes the section 5 trace defect:

| Quantity | Value (both engines) |
|---|---|
| `lineitem` rows | 59,986,052 |
| `l_shipdate` in [1994-01-01, 1995-01-01) | 9,099,165 |
| `l_discount` in [0.05, 0.07] | 16,361,562 |
| `l_quantity` < 24 | 27,590,886 |
| **all three predicates (Q06 qualifying rows)** | **1,139,264** |
| `sum(l_extendedprice*l_discount)` over those rows | 1230113636.0101 |
| distinct `l_discount` values / range | 11 / [0.00, 0.10] |
| distinct `l_shipdate` values / range | 2,526 / [1992-01-02, 1998-12-01] |
| `l_quantity` range | [1.00, 50.00] |

## 3-b. Headline timings

Regime `single-query-repeat WARM`; metadata connection mode
`single-connection-four-statements` (1 uncounted warmup + 3 measured, one direct
connection, no reconnect/prepare between measured statements, connection establishment
excluded). **Q06 is even, so the engine-block order is PostgreSQL block first, then
CUBRID block** (section 12), and the blocks were grouped per engine rather than
alternated, per section 24. Each statement fully consumed its single row into a
campaign-owned fixed sink under `work/Q06/sink`; content hashes computed after the timers
stopped.

| Field | CUBRID | PostgreSQL |
|---|---|---|
| WARM established after | 40-statement gate, half-split trend −0.4119%, first pass at statement 12 | 40-statement gate, half-split trend +0.1704%, first pass at statement 12 |
| warmup (uncounted) | 3.837000 s | 1.649093 s |
| measured run 1 | 3.875000 s | 1.627361 s |
| measured run 2 | 3.837000 s | 1.618176 s |
| measured run 3 | 3.882000 s | 1.617205 s |
| **median (headline)** | **3.875000 s** | **1.618176 s** |
| mean | 3.864667 s | 1.620914 s |
| within-block sd | 0.024214 s (0.625%) | 0.005604 s (0.346%) |
| block wall (4 statements) | 15.452 s | 6.518 s |
| sink bytes | 703 | 198 |
| sink SHA-256 | `43ae3205783da58e31f44934…` | `16fd4a74a404f6c032deed02…` |
| external load during block | mean 0.165 / max 0.939 → `CLEAN` | mean 0.129 / max 0.520 → `CLEAN` |

**Median wall ratio = 2.394672x (CUBRID / PostgreSQL) — PostgreSQL is 2.3947x faster.**
Correctness status `result-equivalent-at-SF10`; censoring status: not censored (3.88 s and
1.62 s against a 300 s limit). No confidence interval is claimed from three values.

Reproducibility. **Six gated blocks per engine were measured rather than the contractual
one**, because CUBRID's first three medians spanned 2.84% and three blocks cannot tell a
drift from a wobble:

| Block | CUBRID median | PostgreSQL median | ratio |
|---|---|---|---|
| 1 (reported) | 3.875000 s | 1.618176 s | **2.394672x** |
| 2 | 3.864000 s | 1.622130 s | 2.382053x |
| 3 | 3.768000 s | 1.614617 s | 2.333680x |
| 4 | 3.856000 s | 1.617169 s | 2.384414x |
| 5 | 3.886999 s | 1.623834 s | 2.393717x |
| 6 | 3.797000 s | 1.616397 s | 2.349052x |
| median of medians | **3.860000 s** | **1.617672 s** | **2.386144x** |
| min–max spread | 3.083% | 0.570% | 2.559% |

Block 1 is reported because it is the first block accepted under the gate, which is the
campaign's stated convention. It is **not** the median of medians: that pair gives
**2.386144x**, **0.36% below** the reported 2.394672x, recorded rather than silently
resolved in either direction and smaller than the 2.56% block-to-block ratio spread.

**Why six blocks, and what they settled.** Blocks 1→3 fell monotonically (3.875 → 3.864 →
3.768), which is exactly the signature that invalidated Q05's first three blocks. Blocks
4→6 (3.856, 3.887, 3.797) show it was **not** a drift: the level oscillates around
3.84 s with no direction, the extremes are blocks 3 and 5 in the wrong order for a decay,
and each block's median tracks the level its own preceding 40-statement warm reached
(3.836→3.875, 3.852→3.864, 3.814→3.768, 3.869→3.856, 3.865→3.887, 3.819→3.797 — the two
series move together). So Q06's CUBRID level is set by which subset of a 682,937-page
relation the 524,288-page pool happens to hold when the block starts, wobbling ±1.5%, and
no block was invalidated. This is the mild form of Q05's IMP-002 pool-history finding, and
it is why the reported figure is accompanied by the median of medians rather than
presented alone.

Measurement-resolution note: `csql` reports elapsed time at 1 ms granularity, so CUBRID's
headline carries ±0.013% quantization at this magnitude, far below its 0.625% within-block
sd; `psql` reports µs.

**WARM gate parameters, and how they were derived rather than inherited.** Q05 proved the
Q04 constants are not universal and made them environment-overridable, so Q06 derived its
own from its own stationary null distribution (`q6-warmgate-bootstrap.json`, moving-block
bootstrap, seed 20260731, 20,000 resamples, block length = the measured plateau length):

| Series length | CUBRID null p95 / p99 / max | PostgreSQL null p95 / p99 / max |
|---|---|---|
| n = 20 | 1.44% / 1.80% / 2.27% | 0.43% / 0.45% / 0.47% |
| n = 40 | 1.04% / 1.32% / 1.91% | 0.32% / 0.40% / 0.46% |
| n = 60 | 0.86% / 1.07% / 1.90% | 0.26% / 0.35% / 0.45% |

against a genuinely warming CUBRID series (the first 40-statement probe, level
3.9585 → 3.8230 s) scoring **2.45%**. Q06 therefore ran the gate at **40 statements** with
`LEVEL_TOL = 2.0%` for CUBRID (above the n=40 stationary null max of 1.91%, below the
2.45% warming signal) and the stock **1.0%** for PostgreSQL (2.2x above its n=40 null max
of 0.46%, and its measured trend is 0.25%), `SPREAD_SANITY = 5.0%` for both (the converged
CUBRID probe's own raw spread is 3.29% and PostgreSQL's is 4.16%). **The CUBRID separation
is thin — 1.91% null max against a 2.45% signal, only 1.28x — and that is recorded as a
weakness rather than presented as a clean gate**; the absolute-level cross-check in the
next paragraph is what actually carries the WARM claim on the CUBRID side.

WARM proof (proved, not assumed):

| Evidence | CUBRID | PostgreSQL |
|---|---|---|
| steady state proved before timing | 40-statement pre-warm per block, half-split trend −0.41% within a 2.0% tolerance derived from this query's own stationary null | 40-statement pre-warm per block, half-split trend +0.17% within 1.0% |
| independent convergence probe | 100 statements, median **3.826 s**, half-split trend **−0.69%** over the whole series and **+0.30%** over the trailing 40 | 40 statements, median **1.590795 s**, half-split trend **+0.25%**, trailing spread 0.41% |
| absolute-level cross-check | six block medians 3.768–3.887 s straddle the independently measured 3.826 s stationary level; reported block 1 is **+1.28%** above it | six block medians 1.6146–1.6238 s sit **+1.5% to +2.1%** above the 1.5908 s stationary level — see note |
| device `read_bytes` (per `/proc/<pid>/io`) | **0.00 MB** across all three telemetry blocks | 0.00 MB (one 128 KiB delta in one of three blocks) |
| engine buffer counters | trace `fetch 682,938 / ioread 608,427` per statement = **89.1% miss**; pool conserved at 524,288 pages | `shared hit=1,035,988 read=89,140` summing to exactly `relpages` 1,125,128 = **7.9% miss** |
| `rchar` per statement | **9.286 GiB** | 0.611 GiB |
| read syscalls per statement | **608,510** (16,377 B each) | 39,043 (2.01 pages each) |
| warmup vs median | −0.98% (warmup *faster*) | +1.91% |

Two honest caveats on this table. First, **neither engine is buffer-resident on Q06**, so
"WARM" here means *the OS page cache is warm and each engine's pool has reached its own
stable equilibrium* — not *no physical reads*. That is proved by `read_bytes` = 0: all
9.286 GiB and 0.611 GiB per statement are served from the page cache, and nothing reaches
the device. Second, **both engines' block statements sit slightly above their own
40-statement stationary level** (CUBRID +1.3%, PostgreSQL +1.5–2.1%) because the
40-statement warm runs in a *separate connection*: the block's own first statements pay a
per-connection cost the warm cannot remove. That is the section 12 contract
(`single-connection-four-statements`, one uncounted warmup) and applies to both engines, so
it biases the *levels* and not materially the *ratio* — the stationary-level ratio is
3.826/1.5908 = **2.4051x** against the reported 2.3947x, **0.43%** apart.

## 4. Plan

**The two engines choose the same plan because it is the only plan, and both cost it
accurately enough that the choice was never in doubt.**

CUBRID estimated (`SET OPTIMIZATION LEVEL 514`, verified non-executing: 0.02 s wall,
"There are no results"), `q6-plan-est-cubrid.out`:

```text
Join graph nodes:
  node[0]: dba.lineitem dba.lineitem(59986052/682937) (sargs 0 1 2) (loc 0)
Join graph terms:
  term[0]: l_shipdate range (date '01/01/1994' ge_lt date '01/01/1995') (sel 0.148261) (sarg term)
  term[1]: l_discount range (0.05 ge_le 0.07)                          (sel 0.179933) (sarg term)
  term[2]: l_quantity range (min inf_lt 24)                            (sel 0.4801)   (sarg term)

Query plan:
  sscan
      class: lineitem node[0]
      sargs: term[0] AND term[1] AND term[2]
      cost:  832902 card 768284
```

CUBRID actual (trace, `q6-trace-cubrid.out`):

```text
SELECT (time: 3888, fetch: 682946, fetch_time: 3768, ioread: 608434)
  SCAN (table: dba.lineitem), (heap time: 3888, fetch: 682938, ioread: 608427,
                               readrows: 59986052, rows: 59986052)
       (parallel workers: 6, heap time: 3852..3888,
        readrows: 9938887..10011920, rows: 9938887..10011920, gather: buildvalue)
```

PostgreSQL actual (`q6-plan-act-pg.out`):

```text
Finalize Aggregate                       (actual time=1554.735..1685.721 rows=1 loops=1)
  Buffers: shared hit=1035988 read=89140
  ->  Gather                             Workers Planned: 5   Workers Launched: 5
        ->  Partial Aggregate            (actual time=1550.951..1550.952 rows=1 loops=6)
              ->  Parallel Seq Scan on public.lineitem
                    (actual time=0.125..1511.279 rows=189877.33 loops=6)
                    Filter: ((l_shipdate >= '1994-01-01'::date)
                         AND (l_shipdate < '1995-01-01 00:00:00'::timestamp)
                         AND (l_discount >= 0.05) AND (l_discount <= 0.07)
                         AND (l_quantity < '24'::numeric))
                    Rows Removed by Filter: 9807798        [x 6 loops = 58,846,788]
                    Buffers: shared hit=1035988 read=89140
                    Worker 0..4: 190242 / 191315 / 188974 / 189580 / 189783 rows
Planning Time: 0.580 ms      Execution Time: 1685.803 ms
```

Node-by-node agreement — this is the `F_plan = 1.0000` justification:

| Node | CUBRID | PostgreSQL | agreement |
|---|---|---|---|
| access path on `lineitem` | `sscan` (full heap scan) | `Parallel Seq Scan` | same, and the only one available |
| sargs pushed into the scan | 3 (`term[0..2]`) | 3 (5 scalar comparisons in `Filter`) | same predicates, same push-down |
| rows scanned | 59,986,052 | 59,986,052 (`189877.33 + 9807798` per loop × 6) | **exact** |
| rows qualifying | 1,139,264 (ground truth) | 1,139,264 (`189877.33 × 6`) | **exact** |
| per-unit work balance | 9,938,887…10,011,920 (0.73% spread) | 188,974…191,315 (1.24% spread) | both balanced |
| aggregation | per-worker partial → `gather: buildvalue` | `Partial Aggregate` → `Gather` → `Finalize Aggregate` | same shape |
| execution units | 6 workers | 5 workers + leader = 6 | **same width** |
| serial tail | 0.000 s | 0.232 s | PostgreSQL pays a tail |
| **active execution units** | **5.9686** | **5.8141** | **2.7% apart** |

**Cardinality estimation, recorded because it is wrong on one side and consequence-free
on both.** Actual selectivities are 0.151688 (`l_shipdate`), 0.272839 (`l_discount`) and
0.459955 (`l_quantity`), product 0.019039 → 1,142,000 predicted against 1,139,264 actual,
so the three predicates are independent to 0.24%. Against that:

| Term | CUBRID estimate | actual | error |
|---|---|---|---|
| `l_shipdate` range | 0.148261 | 0.151688 | −2.3% |
| `l_quantity < 24` | 0.4801 | 0.459955 | +4.4% |
| **`l_discount` in [0.05, 0.07]** | **0.179933** | **0.272839** | **−34.0%** |
| combined card | 768,284 | 1,139,264 | **−32.6% (1.483x low)** |
| PostgreSQL card | 1,131,505 (`226301 × 5`) | 1,139,264 | **−0.68%** |

CUBRID underestimates Q06's row count by 1.483x, essentially all of it from `l_discount`,
a column with **11 distinct values in [0.00, 0.10]** where the requested range covers
exactly 3 of them (0.2727) and a bucket-exact histogram should be nearly perfect. The
estimate is not even the uniform-continuous value (0.02/0.10 = 0.2000), so something other
than plain interpolation produced it. **It has no consequence on Q06** — a full scan is the
only plan, and both engines reached it — so no candidate was allocated: Q06 cannot
distinguish which estimator produced 0.179933 without a source dig it has no measurement
to validate against, and section 18 forbids a candidate that is a restated observation.
It is recorded here so that a later query whose plan *does* turn on a numeric-range
selectivity has a documented prior. This is deliberately **not** filed as a Q06 relation on
IMP-003, whose root cause is specifically leading-wildcard LIKE selectivity read from
histogram upper boundaries; asserting they are the same mechanism would be a guess.

Counterfactuals in both directions, identical variants grouped in one connection per
section 24 (`q6-counterfactuals.txt`, trailing-median of grouped repeats):

| Variant | Plan reached | Wall | Verdict |
|---|---|---|---|
| CUBRID native (`parallelism=6`) | `sscan`, 6 workers | **3.875 s** (median of 3, gated block) | baseline |
| CUBRID `/*+ NO_PARALLEL_SCAN */` | `sscan`, serial | **20.562 s** | parallel speedup **5.3063x** of 6 |
| CUBRID `/*+ PARALLEL(1) */` | `sscan`, serial (**no** `parallel workers` line) | 21.31 s | degenerates to the serial path — see section 5 |
| CUBRID `/*+ PARALLEL(2) */` | `sscan`, 2 workers | 11.04 s | 1.86x of serial |
| CUBRID `/*+ PARALLEL(3) */` | `sscan`, 3 workers | 7.37 s | 2.79x |
| CUBRID `/*+ PARALLEL(6) */` | `sscan`, 6 workers | 3.894 s | identical to native (hint is a no-op at the configured degree) |
| CUBRID `/*+ PARALLEL(12) */` | `sscan`, 12 workers | **2.021 s** | **1.917x faster than native** — see below |
| PostgreSQL native (5+leader) | `Parallel Seq Scan` | **1.618176 s** (median of 3, gated block) | baseline |
| PostgreSQL `max_parallel_workers_per_gather=0` | `Seq Scan`, serial | **6.5699 s** | parallel speedup **4.0601x** of 6 |
| PostgreSQL `=1` | 1 worker + leader | 3.925 s | 1.67x |
| PostgreSQL `=2` | 2 workers + leader | 2.858 s | 2.30x |
| PostgreSQL `=11` | 11 workers + leader | **1.297 s** | 5.06x |
| PostgreSQL date-literal variant (diagnostic) | unchanged | 1.607 s | dialect cast costs 0.20% |

Three things follow. First, **the contract's configured cap is doing real work on this
query and the report must not quietly step outside it**: at `parallelism=12` CUBRID reaches
2.021 s, **1.917x faster than its own contracted 3.875 s**, and at
`max_parallel_workers_per_gather=11` PostgreSQL reaches 1.297 s. The headline stays at 6
vs 5+leader because that is the campaign contract, and the DOP-12 figure is reported as a
counterfactual — but it means Q06's 2.39x is a statement about a configured comparison, and
CUBRID has headroom on this plan that the configuration withholds. Second, **CUBRID
parallelizes this scan better than PostgreSQL does** (5.31x vs 4.06x on the same 6 units,
88% vs 68% efficiency), which is the mirror image of Q05. Third, **the serial pair is the
cleanest per-row cost measurement in the campaign so far**: 20.562 s vs 6.5699 s = 3.1297x
with one unit each and `U` = 1.00 on both sides, no parallelism, no plan choice, no
cardinality difference.

## 5. Execution telemetry

Non-headline diagnostic runs; per-TID sampler on CPUs `20-23`, weighted by actual sample
timestamp deltas. Three runs per configuration, each preceded by
`harness/warm_establish.py` and all load-gated; the recorded run is the **median-`U`** run.
All runs retained in raw.

| Metric | CUBRID native (6) | PostgreSQL native (5+leader) | CUBRID serial | PostgreSQL serial |
|---|---|---|---|---|
| block walls, 4 statements | 15.202 / **15.414** / 15.327 s | 6.6424 / 6.6515 / **6.6562** s | 85.665 s | 27.008 s |
| `executor_cpu` (per block) | 91.87 core-s | 37.32 core-s | 85.35 core-s | 27.07 core-s |
| `auxiliary_query_cpu` (per block) | **0.13 core-s** | 1.38 core-s (`pg_io_worker` 1.29) | 0.60 core-s | 0.98 core-s (`pg_io_worker`) |
| `total_query_cpu` (per block) | **92.00 core-s** | **38.70 core-s** | 85.95 core-s | 28.05 core-s |
| `U` = CPU_block / Σwalls | **5.96860** | **5.81408** | **1.00333** | **1.03859** |
| `total_query_cpu` per median statement | **23.1283 core-s** | **9.4082 core-s** | 20.6305 core-s | 6.8234 core-s |
| planned workers | 6 (`parallelism=6`) | 5 + leader | 1 | 1 |
| launched workers | trace: **6** | **5** + leader = 6 | — | — |
| max simultaneous active units | 6.3592 | 7.9276 | 1.02 | 1.09 |
| time-weighted active units (TWU) | **5.9498** | **5.5784** | 1.0030 | 1.0305 |
| serial tail | **0.000 s** | 0.232 s | — | — |
| `rchar` per statement | **9.286 GiB** | 0.611 GiB | 2.422 GiB | 0.590 GiB |
| read syscalls per statement | **608,510** | 39,043 | 158,927 | 21,519 |
| device read | **0.00 MiB** | 0.00 MiB (0.12 MiB in 1 of 3 blocks) | 0.00 MiB | 0.00 MiB |
| `unattributed_background` | none claimed | none claimed | none claimed | none claimed |

`U` and TWU agree to **0.31%** on CUBRID and 4.05% on PostgreSQL (the 0.232 s tail), and
`perf stat` independently reports **6.008 CPUs utilized** for CUBRID. Three instruments,
one answer: **both engines execute Q06 on approximately six units, and CUBRID's are
marginally better occupied.** CUBRID's `auxiliary_query_cpu` is 0.13 core-s per block
against PostgreSQL's 1.38 — but that asymmetry is not an efficiency claim, it is the
process model: PostgreSQL's physical reads are executed by separate `pg_io_worker`
processes and land in auxiliary, while CUBRID's are executed inline by the query threads
themselves and land in executor. Section 7 shows the code.

### The buffer finding: parallelism silently discards CUBRID's own scan resistance

This is Q06's second result and it is a same-engine A/B with an arithmetically predicted
control value. `lineitem` is 682,937 CUBRID heap pages in a 524,288-page pool, so the
**unavoidable overflow is 682,937 − 524,288 = 158,649 pages per statement**. Measured
physical reads per statement (`q6-lru-ab.txt`, each variant driven to its own equilibrium
with two full passes before the measured pass; `/proc/<cub_server>/io` `syscr` deltas ÷
statement count):

| Scan units | reads/statement | pages retained | miss | vs predicted overflow |
|---|---|---|---|---|
| `NO_PARALLEL_SCAN` (1) | **158,930** | 524,007 | **23.27%** | **+0.18%** |
| `NO_PARALLEL_SCAN` (1), repeat | 162,257 | 520,680 | 23.76% | +2.27% |
| `PARALLEL(1)` — degenerates to serial | 158,929 | 524,008 | 23.27% | +0.18% |
| `PARALLEL(3)` | 468,980 | 213,957 | 68.67% | 2.96x |
| native `PARALLEL(6)` | 458,209 | 224,728 | 67.09% | 2.89x |
| `PARALLEL(12)` | 459,242 | 223,695 | 67.25% | 2.89x |
| **headline-regime blocks (6)** | **608,510** | 74,427 | **89.1%** | **3.83x** |

PostgreSQL, same query, same 7.3%-oversized situation
(1,125,128 pages in 1,048,576 buffers, predicted overflow 76,552):

| Scan units | `heap_blks_read`/statement | vs predicted overflow |
|---|---|---|
| serial (`per_gather=0`) | **76,987** | +0.57% |
| 5 workers + leader | **78,482** | +2.52% |
| 5 workers + leader (`EXPLAIN ANALYZE` capture) | 89,140 | +16.4% |

**Read the two tables together.** On one scan thread CUBRID's replacement policy is not
merely adequate, it is *optimal* — it retains the entire pool's worth of the relation and
re-reads only the arithmetic overflow, matching the prediction to 0.18%. Put the identical
scan on 3, 6 or 12 pooled workers and retention collapses to 214k–225k pages, and in the
section 12 headline regime to 74k. **PostgreSQL's DOP effect on the same measurement is
1.9%; CUBRID's is 188%.** And the degradation is a *step* at ≥2 workers that is then flat
across DOP 3/6/12, not something that scales with worker count — which is what a
contention explanation would predict and is why contention is rejected. Section 7 locates
the branch in source; it is filed as **IMP-010**.

Three limitations, stated rather than glossed:

1. **The cleanest control is unavailable on this build.** `/*+ PARALLEL(1) */` does not
   dispatch to one pooled worker — it degenerates to the serial non-`px` path
   (`variants/trace-PARALLEL1.txt`: no `parallel workers` line, correct `rows: 1139264`,
   158,929 reads). So "one pooled worker" cannot be separated from "one thread" by
   measurement here, and the mechanism claim rests on the source branch plus the
   DOP-flat step.
2. **The parallel figure is itself unstable** (458k–608k at the same DOP 6) while the
   serial figure is pinned to the overflow in two independent settings. That instability is
   further evidence for the finding, but it means the amplification must be quoted as a
   range (2.88x–3.83x) and the headline regime happens to sit at the bad end.
3. **On this host it costs comparatively little.** `read_bytes` is **0**: every one of
   those 9.286 GiB is a page-cache copy, not device I/O, worth 2.543 core-s (section 6).
   On a host where the working set did not fit RAM the same 4.6 GiB of extra reads would
   be disk traffic. Q06 measures the **cheap** case and claims only the cheap case.

### Both engines pay ~2.5 core-s to parallelize, for opposite reasons

| Engine | serial CPU/stmt | parallel CPU/stmt | inflation | where the profile says it goes |
|---|---|---|---|---|
| CUBRID | 20.6305 core-s | 23.1283 core-s | **1.121x (+2.500)** | extra page-cache reads: 608,510 vs 158,927 syscalls, and the kernel read band is 2.543 core-s parallel vs an estimated 0.882 core-s at the serial read count → **1.66 core-s, 66% of the inflation** |
| PostgreSQL | 6.8234 core-s | 9.4082 core-s | **1.379x (+2.585)** | per-statement worker fork/teardown: page-table setup and teardown 1.338 core-s + per-tuple memory context churn 0.298 core-s = **1.636 core-s, 63% of the inflation** |

That symmetry is the reason the parallel-regime `F_cpu` (2.4583x) is *better* for CUBRID
than the serial cost ratio (3.1297x): PostgreSQL's process model taxes it more heavily for
going parallel than CUBRID's threaded model taxes CUBRID, and that tax partly offsets
CUBRID's per-row deficit.

### An observability defect found while collecting this evidence

**CUBRID's server-global page-buffer counters do not advance for the parallel scan path at
all.** `cubrid statdump` reported `Num_data_page_fetches = 23,255,736`,
`Num_data_page_ioreads = 814,716` and `Data_page_buffer_hit_ratio = 96.49` **both before
and after** a statement that provably issued **608,635 `pread` syscalls totalling
9.29 GiB** (`/proc/<cub_server>/io` `syscr` and `rchar` deltas, `q6-cubrid-bufstate.txt`).
Two consecutive invocations returned byte-identical values down to
`Num_data_page_hash_anchor_waits`. A single Q06 statement fetches 682,938 pages, so a
counter sitting at 23.2M after hundreds of such statements is not merely lagging.

Consequence for this report: **every buffer number above comes from the query trace plus
`/proc/<pid>/io`, never from `statdump`**, and the two agree to 0.03% (trace `ioread`
608,427 against 608,510 measured syscalls, the difference being catalog reads). `statdump`'s
data-page gauges are recorded as **UNRELIABLE for this campaign**. Filed as a Q06 relation
on IMP-005.

### A second trace defect, with the serial run as its control

For the identical query and identical result, the trace's qualified-row counter is correct
serially and wrong in parallel:

| Variant | trace `readrows` | trace `rows` | truth |
|---|---|---|---|
| `NO_PARALLEL_SCAN` | 59,986,052 | **1,139,264** | 1,139,264 ✓ |
| `PARALLEL(1)` (serial path) | 59,986,052 | **1,139,264** | ✓ |
| `PARALLEL(3)` | 59,986,052 | **59,986,052** | ✗ |
| native `PARALLEL(6)` | 59,986,052 | **59,986,052** | ✗ |
| `PARALLEL(12)` | 59,986,052 | **59,986,052** | ✗ |

On the parallel path `rows` is overwritten by `readrows`. A user reading a parallel Q06
trace therefore cannot see that **98.1% of the scanned rows were discarded by the sargs** —
precisely the number one needs to judge whether an index would help. No runtime cost; a
real observability defect. Also filed on IMP-005, together with a **positive control** for
IMP-005's original `(k−1)x` finding: Q06's `scan_ptr` chain is depth 1, the predicted
multiplication is 1x, and the trace's `fetch` (682,938) matches the relation's page count
(682,937) exactly.

## 6. Profile

Non-headline. `perf` attached to verified PID sets, never all-CPU. CUBRID: `-p 1612732`
(`cub_server`; 31 TIDs, all query threads inside that one process). PostgreSQL:
`perf stat` attached to the **postmaster before the driver's connection existed**, so
inherit-on-fork counts the leader backend plus every statement's parallel workers and
nothing else; `perf record` on `postmaster + live leader` with the same inheritance.
Drivers replayed the identical statement in one connection (CUBRID 18 repeats,
PostgreSQL 42), grouping identical variants per section 24, each preceded by a
40-statement warm and a load gate (`CLEAN`, external max 1.04 / 0.87).

Coverage validation against `perf stat`: CUBRID 150,073 samples / 37 symbol lines above
0.3% / **0 `[unknown]`** / 0 lost; PostgreSQL 141,148 samples / **0 `[unknown]`** / 0 lost.
Driver completion verified (CUBRID 90 non-empty sink lines = 18 × 5 rendered lines;
PostgreSQL 42 non-empty sink lines = 42 × 1 row).

| Metric | CUBRID | PostgreSQL |
|---|---|---|
| cycles | 426,662,593,024 (25.002 s window) | 406,661,958,167 (25.002 s window) |
| instructions | 983,118,989,203 | 720,659,359,577 |
| **IPC** | **2.30** | **1.77** |
| frequency | 2.840 GHz | 2.845 GHz |
| task-clock | 150,209.64 ms | 142,960.02 ms |
| **CPUs utilized** | **6.008** | **5.718** (5.739 in a second capture) |
| context-switches | 279,358 | 9,268 |
| instructions per core-second | 6.5450e9 | 5.0410e9 |
| **cycles per scanned row** | **1,093.5** | **430** |
| **instructions per scanned row** | **2,515** | **762** |

**Q06 is the first query in this campaign where `perf stat` gives a valid PostgreSQL
utilization reading, and closing that gap was a harness change.** Q04 and Q05 both had to
caveat the number as a partial set because PostgreSQL's parallel workers are transient per
statement, so a post-hoc PID snapshot covers at most one statement's workers; on Q06 the
snapshot raced the workers' exit outright and `perf stat` produced no counters at all
("Problems finding threads of monitor"). Attaching to the postmaster *before* the client
connects fixes both symptoms with one change, because io workers and background workers
pre-date the attach and stay in auxiliary — exactly the executor/auxiliary split
`telemetry_run.py`'s `classify()` already applies. `harness/perf_run.sh` was changed
accordingly, re-run end to end, and the fixed path reproduces the ad-hoc measurement to
**0.37%** (5.718 vs 5.739 CPUs utilized, IPC 1.77 both). Section 12 records it as a closed
carried-forward gap.

**`F_cpu` decomposes into instruction count, not IPC — the opposite of Q05.** CUBRID
executes **3.30x** the instructions per scanned row and recovers **1.2994x** of that
through higher IPC (2.30 vs 1.77), netting 2.539x against the measured executor-CPU ratio
of 2.5457x (**0.3%**). CUBRID's IPC being *higher* is worth pausing on: it is not running
into memory stalls that PostgreSQL avoids, it is executing far more instructions and doing
so efficiently. 2,515 instructions to test three predicates on one row and discard it in
98.1% of cases is the finding, and the next table says where they go.

Top self cost, CUBRID (`profile-cubrid-flat.txt`):
`heap_attrinfo_read_dbvalues` **18.04%**, `eval_pred` **11.90%**,
`rep_movs_alternative` [k] 9.18%, `mr_data_readval_numeric` **8.72%**,
`tp_value_compare_with_error` 3.97%, `heap_next_1page` 3.81%, `eval_value_rel_cmp` 3.48%,
`parallel_scan::slot_iterator::next_qualified_slot_with_peek` 2.53%, `pr_clear_value`
2.30%, `numeric_db_value_compare` 2.03%, `heap_scan_get_visible_version` 1.97%,
`or_header_size` 1.90%, `or_mvcc_get_header` 1.76%, `db_value_domain_init` 1.65%,
`eval_data_filter` 1.59%, `spage_get_record_data` 1.46%, `spage_get_record` 1.23%,
`filemap_get_read_batch` [k] 1.16%, `or_header_size@plt` 1.07%, `mr_cmpval_date` 1.05%,
`spage_get_record_type` 1.02%, `pgbuf_unlatch_void_zone_bcb` 0.97%,
`__pthread_mutex_lock` 0.92%, `spage_next_record` 0.83%, `filemap_read` [k] 0.67%,
`heap_page_is_bestspace` 0.63%, `pr_type_from_id` 0.61%, `mr_data_readval_date` 0.57%,
`or_mvcc_get_repid_and_flags` 0.56%, `pr_type_from_id@plt` 0.48%,
`pgbuf_get_victim_from_lru_list` 0.47%, `pgbuf_get_victim` 0.44%, `or_rep_id` 0.43%,
`tp_domain_disk_size` 0.34%, `pgbuf_fix_release` 0.34%, `float_numeric_db_value_mul` 0.31%.

Top self cost, PostgreSQL (`profile-pg-flat.txt`):
`tts_buffer_heap_getsomeattrs` **36.54%**, `ExecInterpExpr` **10.23%**,
`heapgettup_pagemode` 6.03%, `next_uptodate_folio` [k] 5.75%, `ExecSeqScanWithQual`
2.87%, `hash_search_with_hash_value` 2.86%, `heap_page_prune_opt` 1.92%,
`StrategyGetBuffer` 1.73%, `folio_remove_rmap_ptes` [k] 1.70%, `_compound_head` [k] 1.66%,
`filemap_map_pages` [k] 1.59%, `ExecStoreBufferHeapTuple` 1.58%, `heap_getnextslot` 1.51%,
`folios_put_refs` [k] 1.25%, `cmp_numerics` 1.20%, `LWLockAttemptLock` 1.15%,
`heap_prepare_pagescan` 1.00%, `detoast_attr` 0.90%, `PinBuffer` 0.90%,
`MemoryContextReset` 0.82%, `zap_present_ptes` [k] 0.81%, `cmp_abs_common` 0.77%,
`AllocSetReset` 0.75%, `AllocSetFree` 0.68%, `date_cmp_timestamp_internal` 0.64%,
`AllocSetAlloc` 0.59%, `date_lt_timestamp` 0.46%, `date_ge` 0.46%,
`native_irq_return_iret` [k] 0.46%, `folio_add_file_rmap_ptes` [k] 0.45%, `pfree` 0.45%,
`cmp_var_common` 0.39%, `set_pte_range` [k] 0.38%, `free_pages_and_swap_cache` [k] 0.37%,
`sync_regs` [k] 0.33%, `numeric_ge` 0.31%.

Banded against each engine's own **executor** CPU per statement (CUBRID 23.0956 core-s,
PostgreSQL 9.0727 core-s), ranked by absolute contribution to the **14.023 core-s executor
excess**. Every symbol above 0.3% is assigned to exactly one band; nothing is unbanded
(`q6-bands.txt`):

| Band | CUBRID | PostgreSQL | Δ core-s | share of excess | C/P |
|---|---|---|---|---|---|
| **C sarg / predicate evaluation** | 24.02% = **5.548** | 14.46% = **1.312** | **+4.236** | **30.2%** | **4.23x** |
| **B per-value type/domain decode (NUMERIC, DATE)** | 14.67% = **3.388** | 0.00% = **0.000** | **+3.388** | **24.2%** | **absent** |
| **G kernel page-cache read path (`read()` copy)** | 11.01% = **2.543** | 0.00% = **0.000** | **+2.543** | **18.1%** | **absent** |
| A tuple deform / attribute materialisation | 23.70% = 5.474 | 39.02% = 3.540 | +1.933 | 13.8% | 1.55x |
| H parallel-worker page-table setup/teardown (kernel) | 0.00% = 0.000 | 14.75% = 1.338 | **−1.338** | −9.5% | CUBRID favoured |
| D scan iteration / slotted-page navigation | 8.82% = 2.037 | 11.41% = 1.035 | +1.002 | 7.1% | 1.97x |
| E MVCC visibility / row header | 4.72% = 1.090 | 1.92% = 0.174 | +0.916 | 6.5% | 6.26x |
| I per-tuple memory management | 0.00% = 0.000 | 3.29% = 0.298 | −0.298 | −2.1% | CUBRID favoured |
| F buffer manager fix/pin/victim + latching | 3.50% = 0.808 | 6.64% = 0.602 | +0.206 | 1.5% | 1.34x |
| J aggregate accumulation (NUMERIC mul/add) | 0.31% = 0.072 | 0.00% = 0.000 | +0.072 | 0.5% | absent |
| **banded subtotal** | **90.75% = 20.959** | **91.49% = 8.301** | **+12.659** | **90.3%** | |

Four readings, two of which cut against the obvious story:

- **Bands B + C are one root cause and they are the report: 7.624 core-s, 54.4% of the
  entire excess.** CUBRID materializes each sarg attribute into a `DB_VALUE` (decoding the
  NUMERIC header and copying digits through `db_make_numeric` **per row**) and then walks a
  `PRED_EXPR` tree calling a fully generic comparator that re-inspects both domains
  **per row** — 59,986,052 times, to discard 58,846,788 of them. This is IMP-008, and Q06
  is its strongest evidence by a factor of nine over Q04's 0.825 core-s.
- **Band A is *not* the finding, despite being PostgreSQL's largest single symbol.**
  `tts_buffer_heap_getsomeattrs` at 36.54% looks alarming until it is converted:
  3.540 core-s against CUBRID's 5.474, a mere **1.55x**. PostgreSQL's profile is dominated
  by tuple deform precisely *because* everything else it does is cheap. Any account of Q06
  that starts from percentage shares rather than core-seconds gets this backwards.
- **Band G is CUBRID paying, in the executor, for I/O PostgreSQL does elsewhere and less
  often.** 2.543 core-s of kernel page-copy, and the call graph resolves 100% of the 9.18%
  `rep_movs_alternative` weight to a single chain (section 7). IMP-010 governs how many
  such reads happen; IMP-007 governs what each one costs.
- **Bands H + I are 1.636 core-s CUBRID does not pay at all**, the Q04/Q05 process-model
  finding reproducing on a third plan shape. Net of them, `F_cpu` would be **2.744x**
  rather than 2.458x — so PostgreSQL wins Q06 while spending 18% of its own executor CPU
  on forking and tearing down workers it re-creates for every statement.

## 7. Source contrast

| Item | CUBRID file:line | PostgreSQL file:line | Difference | Class |
|---|---|---|---|---|
| Per-row sarg attribute materialisation | `src/query/query_evaluator.c:2765` — `eval_data_filter()` calls `heap_attrinfo_read_dbvalues()` **before** the predicate can look at anything; `src/storage/heap_file.c:10464` `heap_attrinfo_read_dbvalues()` (**18.04%**) → `:10256` `heap_attrvalue_transform_to_dbvalue()` → `src/object/object_primitive.c:8743` `mr_data_readval_numeric()` (**8.72%**) which per row re-reads the leading size byte (`:8763`), re-parses `NUMERIC_HEADER_SIZE` (`:8788`), re-reads `domain->precision`/`scale` and calls `db_make_numeric` (3.66% of the profile) to copy the digits into a fresh `DB_VALUE`; teardown at `pr_clear_value` 2.30% and `db_value_domain_init` 1.65% | `src/backend/executor/execExprInterp.c:662` `EEO_CASE(EEOP_SCAN_FETCHSOME)` → `src/backend/executor/execTuples.c:751` `tts_buffer_heap_getsomeattrs()` → `:1017` `slot_deform_heap_tuple()` deforms **only up to the highest attnum the compiled expression needs**, computed once by `ExecComputeSlotInfo()` (`src/backend/executor/execExpr.c:3057`), into flat `Datum`/`isnull` arrays. A `numeric` Datum is a **pointer into the buffer page**; `src/backend/utils/adt/numeric.c:2529` `cmp_numerics()` → `:8054 cmp_var_common()` → `:11425 cmp_abs_common()` compare the on-disk digit arrays in place. There is no decode-to-value step to profile | **3.388 core-s vs 0.000.** CUBRID's per-value decode band has no PostgreSQL counterpart at all: 24.2% of the CPU excess is spent constructing typed values that are immediately thrown away for 98.1% of rows. Call-graph verified end to end: `next_qualified_slot_with_peek → eval_data_filter → heap_attrinfo_read_dbvalues (17.89%) → heap_attrvalue_read → heap_attrvalue_transform_to_dbvalue → mr_data_readval_numeric (8.40%) → db_make_numeric (3.66%)` | structural absence |
| Sarg comparison dispatch | `src/query/query_evaluator.c:1666` `eval_pred()` — **11.90%**, a recursive `PRED_EXPR` tree walk re-dispatched per row (call graph shows `eval_pred → eval_pred → eval_pred`, 6.36% still live at depth 3); `:152` `eval_value_rel_cmp()` (3.48%) re-inspects both `DB_VALUE` domains and may coerce (`tp_domain_resolve_default`/`tp_value_coerce`, `:255-257`) before comparing; `src/object/object_domain.c:10404` `tp_value_compare_with_error()` (3.97%, self-recursive at 2.26%) → `mr_cmpval_numeric` (`object_primitive.c:8865`) → `numeric_db_value_compare` 2.03%; plus **1.55% in pure PLT stubs** (`or_header_size@plt` 1.07%, `pr_type_from_id@plt` 0.48%) for cross-object per-row type dispatch | `src/backend/executor/execExpr.c:229` `ExecInitQual()` compiles the qual **once** into a linear `ExprEvalStep` program; `src/backend/executor/execExprInterp.c:470` `ExecInterpExpr()` (10.23%) runs it with direct-threaded dispatch; `:1182 EEO_CASE(EEOP_QUAL)`; `:944 EEO_CASE(EEOP_FUNCEXPR_STRICT)` calls an **already-resolved** `FmgrInfo`; the comparison functions themselves are `numeric.c:2484 numeric_ge()` / `:2499 numeric_lt()` and `src/backend/utils/adt/date.c:764 date_cmp_timestamp_internal()` / `:800 date_lt_timestamp()` / `:431 date_ge()` | **5.548 core-s vs 1.312 (4.23x)** on identical predicate work over identical rows. CUBRID re-decides *what it is comparing* on every row; PostgreSQL decided at plan time. 30.2% of the CPU excess. Both engines evaluate the same three range terms over 59,986,052 rows — CUBRID's own plan dump enumerates them as `term[0..2]`, PostgreSQL's `Filter` as 5 scalar comparisons | same stage, lower measured cost |
| Where a newly read page is inserted in the replacement structure | `src/storage/page_buffer.c:6845` `pgbuf_unlatch_void_zone_bcb()` — every page that comes off disk passes here (`:206` `PGBUF_VOID_ZONE` is *"temporary zone after reading bcb from disk and until adding to a lru list"*). At `:6900-6918`, **if the fixing thread has an LRU identity** (`thread_private_lru_index != -1`) the page goes to `pgbuf_lru_add_new_bcb_to_top()` on that thread's **private** list with `pgbuf_bcb_register_hit_for_lru()`; at `:6934`, otherwise, it goes to `pgbuf_lru_add_new_bcb_to_middle(..., pgbuf_get_shared_lru_index_for_add())` — the **middle of a round-robin shared list**, where `pgbuf_get_victim_from_lru_list()` (`:9268`) reclaims it almost immediately. A pooled worker never has an identity: `src/thread/thread_entry_task.cpp:75-76` `retire_context()` sets `private_lru_index = -1` and `m_is_private_lru_enabled = false`, `:95` `recycle_context()` repeats it, and `src/query/parallel/px_scan/px_scan_task.cpp:94` propagates `m_px_orig_thread_entry = m_parent_thread_p` from the parent **and nothing else** — the parent's `private_lru_index` is not copied. Only `src/session/session.c:740` and `src/connection/server_support.c:2401,2437` ever set one, i.e. the client transaction thread that serves a `NO_PARALLEL_SCAN` scan | `src/backend/access/heap/heapam.c:398-410` `initscan()`: `scan->rs_nblocks > NBuffers / 4` ⇒ `scan->rs_strategy = GetAccessStrategy(BAS_BULKREAD)`. The decision is a property of the **scan** and the relation's size, never of the executing process; `:1340` sets `SO_ALLOW_STRAT` for a normal heap scan so **each parallel worker's own `heap_beginscan` builds its own ring** and behaviour is identical at any DOP. `src/backend/storage/buffer/freelist.c:426,442` `GetAccessStrategy()`/`case BAS_BULKREAD` (256 kB ring); `:623 GetBufferFromRing()` and `:702 AddBufferToRing()` recycle only the pages **the scan itself read**, so they cannot evict the resident portion; `:184 StrategyGetBuffer()` is **1.73% of PostgreSQL's Q06 profile**, i.e. the ring is demonstrably active here | **CUBRID's scan resistance is a property of the fixing THREAD; PostgreSQL's is a property of the SCAN.** Consequence, measured on the same pool and relation: 1 unit → 158,930 reads (the 158,649-page arithmetic overflow, +0.18%); 3/6/12 units → 468,980/458,209/459,242 (**2.9x**, flat in DOP); headline regime → 608,510 (**3.83x**). PostgreSQL: 76,987 serial vs 78,482 at DOP 5 against a predicted 76,552 — a **1.9%** DOP effect. Costs 2.543 core-s of kernel copy on CUBRID against 0.000 in PostgreSQL's executor | structural absence |
| How a single buffer miss is served | `src/storage/page_buffer.c:2211` `pgbuf_fix_release()` → `:8349` `pgbuf_claim_bcb_for_fix()` → `src/storage/file_io.c:3935` `fileio_read()` → one `pread64` of **16,377 bytes** on the query thread. `perf -g` resolves **100%** of the 9.18% `rep_movs_alternative` weight to exactly this chain: `pgbuf_ordered_fix_release → pgbuf_fix_release → pgbuf_claim_bcb_for_fix → fileio_read → __libc_pread64 → __x64_sys_pread64 → vfs_read → xfs_file_read_iter → xfs_file_buffered_read → filemap_read → copy_page_to_iter → _copy_to_iter → rep_movs_alternative`. **608,510 such syscalls per statement**, all inline in the executor | `src/backend/storage/aio/read_stream.c:923` `stream->io_combine_limit` (`:332`, `:614`, `:939`) accumulates misses and issues reads of up to `io_combine_limit` pages (16 × 8 kB = 128 kB configured); with `io_method = worker` those reads execute in separate `pg_io_worker` processes. Measured: **39,043 syscalls for 78,482 pages = 2.01 pages per read**, and the executor profile contains **no kernel read-copy symbol at all** — the cost surfaces as **0.34 core-s of `auxiliary_query_cpu` per statement** instead of 2.543 core-s of executor CPU | 15.6x the syscalls, and on the wrong side of the executor boundary. Note the two effects **compose and must not be summed**: IMP-010 sets how many misses there are, IMP-007 sets what each costs, and they share the identical 2.543 core-s band | structural absence |
| Per-row MVCC/visibility bookkeeping | `heap_scan_get_visible_version` 1.97% plus the record-header re-reads it drives — `or_mvcc_get_header` 1.76%, `or_header_size` 1.90% (+1.07% PLT), `or_mvcc_get_repid_and_flags` 0.56%, `or_rep_id` 0.43% — evaluated per row inside the scan | `src/backend/access/heap/heapam.c:619` `heap_prepare_pagescan()` resolves visibility **once per page** (checking the all-visible bit) and `:1074` `heapgettup_pagemode` then walks a pre-validated line pointer array; the only visibility symbol above 0.3% is `heap_page_prune_opt` at 1.92%, and `HeapTupleSatisfiesVisibility` does not appear at all | 1.090 vs 0.174 core-s (**6.26x**), 6.5% of the excess. Per-row versus per-page granularity. Recorded and **not** filed as a candidate — see section 8 for why | same stage, lower measured cost |
| Parallel execution unit lifecycle | Threaded: units are pooled threads inside `cub_server` (one address space, one page table). No per-statement address-space construction appears anywhere in Q06's profile; `auxiliary_query_cpu` is 0.13 core-s per 4-statement block | `src/backend/access/transam/parallel.c:1301` `ParallelWorkerMain()` and `src/backend/executor/execParallel.c:1514` `ParallelQueryMain()` — a process is forked per statement; the kernel faults in each child's PTEs (`next_uptodate_folio` 5.75%, `filemap_map_pages` 1.59%, `_compound_head` 1.66%, `set_pte_range` 0.38%, `folio_add_file_rmap_ptes` 0.45%) and tears them down (`folio_remove_rmap_ptes` 1.70%, `folios_put_refs` 1.25%, `zap_present_ptes` 0.81%, `free_pages_and_swap_cache` 0.37%) | **1.338 core-s of PostgreSQL's executor CPU against 0.000 on CUBRID**, plus 0.298 core-s of per-tuple memory-context churn. Net of both, `F_cpu` would be 2.744x rather than 2.458x. Third independent reproduction of the Q04/Q05 finding, now on a bare scan | same stage, lower measured cost (CUBRID favoured) |

## 8. Causal decomposition details

1. **Everything except per-row cost is controlled to equality, and that is measured rather
   than argued.** `F_plan = 1.0000` by four proofs (same shape, same 59,986,052 rows in,
   same 1,139,264 rows out and byte-identical scalar, and no alternative access path
   existed on either engine). `F_work = 1.0000` **exactly** — the same integer on both
   sides, not a ratio that rounds to one. `F_units = 0.9741`, i.e. marginally CUBRID's
   favour, confirmed by TWU (5.9498 vs 5.5784) and by `perf stat` (6.008 vs 5.718). So
   `R_wall` reduces to `F_cost` and nothing is left unexplained by construction.
2. **The per-row cost gap is 2.4583x in the parallel regime and 3.1297x serially, and the
   difference is PostgreSQL's process model.** Serial: 20.562 s vs 6.5699 s at `U` = 1.00
   on both. Parallel inflation: CUBRID +2.500 core-s (66% attributed to its extra
   page-cache reads), PostgreSQL +2.585 core-s (63% attributed to worker page-table churn
   and memory-context churn). CUBRID converts 6 units into 5.31x and PostgreSQL into
   4.06x, which is why the parallel-regime ratio is the *kinder* of the two numbers for
   CUBRID.
3. **54.4% of the CPU excess is one root cause: the generic per-row value pipeline.**
   Bands B (3.388 core-s, structurally absent in PostgreSQL) and C (4.236 core-s, 4.23x)
   are both IMP-008: decode each sarg attribute into a typed `DB_VALUE`, then compare
   through a comparator that re-resolves domains, 59,986,052 times, discarding 98.1% of
   the results. At 2,515 instructions per scanned row against PostgreSQL's 762, this is
   where the instructions are.
4. **18.1% is physical-read cost that is 65% avoidable without touching the I/O path at
   all.** Band G is 2.543 core-s of kernel page copy, and the same scan on one thread
   takes 158,930 reads instead of 608,510. Reproducing the serial retention would put the
   band near 0.882 core-s. This is IMP-010, and it is the one Q06 finding with a
   one-site fix.
5. **The MVCC band (0.916 core-s, 6.26x) is real and deliberately not filed as a
   candidate.** It is 6.5% of the excess and the per-page-versus-per-row contrast is clean
   in source, but on this profile `or_header_size` and `or_mvcc_get_header` are reached
   from inside `heap_attrinfo_read_dbvalues`'s own record walk, so the band cannot be
   separated from IMP-008's band by measurement here. Filing it would risk a candidate
   whose effect double-counts an existing one, which section 18 forbids. It is recorded
   with its number so a query where visibility is reached independently can allocate it.
6. **Explanations considered and rejected, with the number that rejected each.**
   - *"CUBRID picked a worse plan."* Rejected: there is only one plan. No index covers any
     of the three sarg columns; both engines full-scan; row counts in and out are
     identical integers.
   - *"CUBRID does more work."* Rejected: `F_work = 1.0000` exactly, 59,986,052 on both.
   - *"CUBRID's parallelism is the problem, as on Q05."* Rejected and **inverted**:
     `F_units = 0.9741`, TWU 5.9498 vs 5.5784, `perf stat` 6.008 vs 5.718, serial tail
     0.000 s vs 0.232 s, and CUBRID's parallel speedup is 5.31x against PostgreSQL's
     4.06x. Q06 is the counter-example to Q05.
   - *"CUBRID is stalling on memory."* Rejected: its **IPC is higher** (2.30 vs 1.77). It
     executes 3.30x the instructions and executes them well.
   - *"Attribute deform is the problem — it is PostgreSQL's biggest symbol."* Rejected by
     converting shares to core-seconds: 5.474 vs 3.540, only **1.55x**, 13.8% of the
     excess. Percentage shares invert this conclusion; core-seconds do not.
   - *"The buffer miss difference explains the gap."* Rejected as the *primary* cause: the
     entire kernel read band is 2.543 core-s = 18.1% of the excess, and `read_bytes` is
     **0** so none of it is device I/O. It is a real and largely removable cost, not the
     main one.
   - *"Then CUBRID's 89% miss rate is a replacement-policy failure, as IMP-002 says."*
     Rejected in that form, and this is Q06's sharpest correction: on **one** thread the
     same policy on the same oversized relation retains the arithmetic optimum
     (158,930 reads against a predicted 158,649, **+0.18%**). The failure is specific to
     the parallel scan path, which is why IMP-010 was allocated and IMP-002's Q01/Q03/Q04
     relations are flagged for re-validation rather than reused.
   - *"It is contention between the parallel workers."* Rejected: the degradation is a
     **step** at ≥2 workers and then **flat** across DOP 3/6/12 (68.67%/67.09%/67.25%).
     Contention predicts DOP dependence.
   - *"The `date + interval` dialect line biases PostgreSQL."* Rejected by direct A/B:
     the date-literal variant runs 0.20% faster, inside block noise.
   - *"CUBRID's 1.483x cardinality underestimate matters."* Rejected: with one plan
     available on each engine, no plan decision depends on it. Recorded in section 4 as a
     prior for a later query, with no candidate allocated.
   - *"IMP-001 (NUMERIC accumulation) drives Q06 — it is a `sum` of a product."* Rejected
     as material: `float_numeric_db_value_mul` is **0.31% = 0.072 core-s**, because only
     1,139,264 of 59,986,052 rows ever reach the aggregate. Q06 confirms IMP-001 is a
     high-cardinality-aggregate finding, not a scan finding.
   - *"CUBRID at `PARALLEL(12)` is 1.917x faster, so report that."* Rejected: the contract
     fixes the comparison at `parallelism=6` vs 5+leader. Reported as a counterfactual,
     with the explicit note that Q06's 2.39x is a statement about a *configured* comparison
     and CUBRID has withheld headroom on this plan.

**Error budget and closure.** The reconstruction residual is 0.000000% and is declared an
identity, so closure rests on the independent quantities: `U` reproduces within **0.25%**
(CUBRID) and **0.60%** (PostgreSQL) across three gated runs each; TWU agrees with `U` to
**0.31%** and **4.05%** (the latter being the 0.232 s serial tail); `perf stat` gives a
third reading of both utilizations at **+0.66%** and **+2.0%**; `F_cpu` is independently
reproduced from instruction counts and IPC to **0.3%**; the stationary-level ratio
(3.826/1.5908 = 2.4051x) agrees with the headline to **0.43%**; and block-to-block
reproducibility of `R_wall` over six blocks per engine is 2.3337–2.3947 (**2.56%**), with
the median-of-medians ratio 0.36% from the reported figure. Band accounting covers
**90.3%** of the CPU excess with every symbol above 0.3% assigned and none unbanded. The
card is closed.

## 9. Improvements

Registry state before Q06: `IMP-001`…`IMP-009`, `next_id: IMP-010`. Deduplication: the Git
ledger was searched by title, both source locations and root cause. `IMP-003`, `IMP-004`,
`IMP-006` and `IMP-009` touch no path Q06 exercises (no LIKE, no join, no intermediate
materialization, no subquery); `IMP-001` was **considered and rejected** for a Q06 relation
on a measured 0.31%. `IMP-002`, `IMP-005`, `IMP-007` and `IMP-008` are extended rather than
duplicated. One new ID was allocated; `next_id` advances to `IMP-011`. No old-campaign
candidate ID was consulted.

| ID | Root cause | Priority | Category | Status | Evidence type | Effect on Q06 |
|---|---|---|---|---|---|---|
| `IMP-008` | (existing, **raised P1→P0**) Sarg evaluation routes every row through the generic `DB_VALUE` pipeline — per-row NUMERIC decode into a typed value, then a comparator that re-resolves domains — where PostgreSQL compiles the qual once into type-specialized steps over in-place Datums | **P0** | expression/type | `measured` | profile attribution | **7.624 core-s = 54.4% of the CPU excess**; 4.23x on the comparable predicate band and a structurally absent 3.388 core-s decode band |
| `IMP-010` | (**new**) Scan-resistance is a property of the fixing *thread*, not of the scan: a pooled parallel-query worker has no private LRU identity, so pages it reads land in the middle of a shared list instead of the top of the session's private list | **P1** | buffer/IO, parallelism | `measured` | **direct A/B** | 2.88x–3.83x physical-read amplification (458,209–608,510 vs 158,930 per statement) worth ≈1.66 core-s (11.8%) |
| `IMP-007` | (existing, **raised P2→P1**) Every miss is served by a synchronous single-page 16 KiB `pread` on the query thread, with no batching and no offload | **P1** | buffer/IO | `measured` | profile attribution | 2.543 core-s (18.1%) with the copy sampled **inside** `pgbuf_fix_release`; 15.6x PostgreSQL's syscall count |
| `IMP-002` | (existing) Buffer replacement — Q06 supplies the **serial control it never had** and **re-scopes** it | P1 | buffer/IO | `measured` | direct A/B | no new steady-state cost; refutes the "policy cannot retain a marginally oversized working set" wording for the serial path |
| `IMP-005` | (existing) Parallel-scan trace statistics — Q06 adds **two new defects** and a **positive control** | P2 | parallelism | `measured` | direct A/B | zero runtime cost; parallel trace reports `rows` = `readrows`, and `statdump` page counters never advance |

**Ranking justification.** `IMP-008` outranks everything on magnitude by 4.6x: 7.624
core-s against `IMP-010`'s ≈1.66 and `IMP-007`'s ≤2.543, and it is the only candidate whose
fix would change the headline materially. `IMP-010` ranks second despite the smaller number
because it has the best evidence in the report — a same-engine A/B against an
*arithmetically predicted* control value (158,649 predicted, 158,930 measured) — and the
cheapest fix (propagating two existing fields at one existing propagation site).
`IMP-007` ranks third **and must be sequenced after IMP-010**, because IMP-010 removes 65%
of the reads that IMP-007 would make cheaper; doing IMP-007 first would optimize work that
should not exist. `IMP-002` and `IMP-005` carry no Q06 cost and rank last on effect, but
`IMP-002`'s re-scoping is elevated in importance because it changes what three earlier
queries' evidence means. **Effects are not summed**: IMP-008's bands (B, C) are disjoint by
symbol from IMP-010's and IMP-007's (band G), so those add; **IMP-010 and IMP-007 share the
identical 2.543 core-s band and compose multiplicatively**, so their joint upper bound is
that band, not the sum of two claims.

### IMP-010 — going parallel silently discards the buffer pool's scan resistance

- **Mechanism, CUBRID.** Every page read from disk passes through
  `pgbuf_unlatch_void_zone_bcb()` (`src/storage/page_buffer.c:6845`; `PGBUF_VOID_ZONE` is
  defined at `:206` as *"temporary zone after reading bcb from disk and until adding to a
  lru list"*). That function branches on the **fixing thread's** LRU identity: with one
  (`:6900-6918`) the page goes to the **top of that thread's private list** and is
  registered as a hit; without one (`:6934`) it goes to the **middle of a round-robin
  shared list**, where `pgbuf_get_victim_from_lru_list()` (`:9268`) reclaims it almost at
  once. A pooled parallel-query worker never has an identity —
  `thread_entry_task.cpp:75-76` sets `private_lru_index = -1` and
  `m_is_private_lru_enabled = false` on retire, `:95` repeats it on recycle, and
  `px_scan_task.cpp:94` propagates `m_px_orig_thread_entry` from the parent **and nothing
  else**. Only `session.c:740` and `server_support.c:2401,2437` ever assign one, i.e. the
  client transaction thread that serves a serial scan.
- **Mechanism, PostgreSQL.** Scan resistance is attached to the **scan**: `initscan()`
  (`heapam.c:398-410`) sets `BAS_BULKREAD` whenever `rs_nblocks > NBuffers/4`, and `:1340`
  sets `SO_ALLOW_STRAT` for a normal heap scan so *each parallel worker's own*
  `heap_beginscan` builds its own 256 kB ring (`freelist.c:426,442`). `GetBufferFromRing`
  /`AddBufferToRing` (`:623`, `:702`) recycle only pages the scan itself read, so the
  resident portion of the relation is never evicted, at any DOP. `StrategyGetBuffer`
  (`:184`) is 1.73% of PostgreSQL's Q06 profile, so the ring is provably active.
- **Why the direction follows.** The prediction is arithmetic, not inferred: a pool of
  524,288 pages over a 682,937-page relation must miss at least 158,649 pages per pass.
  One thread measures **158,930** (+0.18%). Three, six and twelve workers measure
  468,980 / 458,209 / 459,242 — a step, then flat. PostgreSQL's own DOP effect on the same
  quantity is **1.9%** (76,987 → 78,482 against a predicted 76,552). Concurrency
  contention is excluded by the flatness; the source says what changed instead.
- **Evidence event and denominator.** Physical page reads per statement =
  `/proc/<cub_server>/io` `syscr` delta ÷ statement count, cross-checked against the
  trace's own `ioread` (608,427 trace vs 608,510 syscalls, 0.03%). Raw: `q6-lru-ab.txt`,
  `q6-cubrid-bufstate.txt`, `q6-serial-telemetry.txt`, `variants/trace-*.txt`,
  `Q06-cubrid-headline-telemetry-run{1,2,3}.json`.
- **Effect range.** Direct A/B: 458,209 → 158,930 reads, i.e. −4.57 GiB of page-cache
  traffic per statement. If the kernel read band scales with bytes, 2.543 → ≈0.882 core-s,
  releasing ≈**1.66 core-s of the 14.023 core-s excess (11.8%)**. Independently bounded by
  CUBRID's measured parallel CPU inflation of 2.500 core-s (20.6305 serial → 23.1283 at 6
  units), of which this is 66%. Wall effect at 5.97 active units is ≈0.28 s of 3.875 s.
  **On a host where the working set did not fit RAM the same 4.57 GiB would be device I/O
  and the effect would be far larger; this campaign measures the cheap case and claims only
  the cheap case.** Evidence type: direct A/B.
- **Implementation direction.** Propagate the parent's LRU identity into the worker's
  thread entry at `px_scan_task.cpp:94`, beside the existing `m_px_orig_thread_entry`
  assignment: copy `m_parent_thread_p->private_lru_index` and call the existing
  `pgbuf_thread_variables_init()` so `m_is_private_lru_enabled` follows;
  `thread_entry_task.cpp:75-76` already clears both on retire. All N workers of one scan
  then share the one private list of the owning session — the *same* list the serial path
  uses — so serial retention is reproduced exactly rather than approximated. If that proves
  contended at high DOP, the cheaper fallback is to keep the shared list but insert at the
  **top** rather than the middle when the fixing thread is a parallel-scan worker of a
  sequential scan. The structurally clean fix, and the one PostgreSQL's design argues for,
  is to make scan resistance a property of the **scan** (a per-scan strategy handed to
  `pgbuf_fix`, as at `freelist.c:426`), which removes the whole defect class rather than
  this instance.
- **Correctness/regression risk.** **Low** for the insertion-point variants: LRU placement
  is a performance policy and cannot change results, and latching/pinning is untouched. The
  real risks are operational: (a) one private list mutated by N workers concentrates
  list-lock traffic, which must be measured at high DOP — the fallback exists for that
  outcome; (b) a private list legitimately holding the whole pool must not starve other
  sessions, so `pgbuf_adjust_quotas` under a single large private consumer needs checking —
  noting that **the serial path already produces exactly this state today**, so it is a
  state the pool demonstrably tolerates.
- **Validation criteria.** (1) Q01–Q22 results byte-identical. (2) Q06 CUBRID physical
  reads per statement fall from 458,209 to within 5% of the serial 158,930 at DOP 6,
  measured the same way and cross-checked against trace `ioread`. (3) The same holds at
  DOP 3 and DOP 12 — **DOP independence is the property being restored**. (4) The
  `rep_movs_alternative` + `filemap_*` band falls from 11.01% to under 5%. (5) Q06 CUBRID
  median improves against 3.875 s under the same `warm_establish` + `measure_block`
  protocol with the WARM gate still `CONVERGED`, and block-to-block spread does not exceed
  the 3.08% recorded here. (6) **Q01/Q03/Q04 physical reads must be re-measured**, because
  Q06 shows their IMP-002 conclusion may in fact be this defect. (7) A high-DOP contention
  check: `cub_server` mutex/latch time must not rise above its current 3.50% buffer-manager
  band.
- **Priority.** **P1** — 2.883x measured amplification with a same-engine A/B against an
  arithmetically predicted control, worth ≈11.8% of the CPU excess, from a one-site fix.
  Not P0 because on this host every one of those reads is a page-cache hit
  (`read_bytes` = 0) so the wall effect is only ≈0.28 s of 3.875 s.
- **Difficulty.** **Low** — two existing fields propagated at one existing propagation
  site plus a call to an existing initializer; no new mechanism, no data-structure change,
  no plan or semantic change. Medium if the contention fallback is needed; high for the
  per-scan-strategy redesign recorded as the alternative.
- **Upstream precedent.** No prior CBRD issue or PR propagating the session's private LRU
  index into parallel-scan workers was identified in the pinned tree at `607f1ee9`. The
  *pattern* of propagating per-session executor state into `px` workers is already
  established at `px_scan_task.cpp:94` for `m_px_orig_thread_entry`, so this extends an
  accepted pattern rather than introducing one. On the PostgreSQL side the corresponding
  change — `BAS_BULKREAD` ring buffers for large scans — is ancient and settled, which is
  exactly why PostgreSQL's numbers here are DOP-independent; that is precedent for the
  design, not for the CUBRID patch.
- **Known limitation, recorded not glossed.** The cleanest control (one *pooled worker*,
  separating "which thread fixes the page" from "how many threads contend") is
  unobtainable on this build: `/*+ PARALLEL(1) */` degenerates to the serial non-`px` path.
  The mechanism claim therefore rests on the source branch plus the DOP-flat step, and
  validation criterion (3) is written to settle it.

### IMP-008 — Q06 relation: the campaign's largest non-parallelism cost difference

Q06 is the query this candidate was written for, and it raises it from **P1 to P0**. On
Q04 the band was 0.825 core-s and 18.1% of that query's CPU excess. On Q06 — with
`F_plan = 1.0000` and `F_work = 1.0000`, so no plan or cardinality confound exists — the
same root cause accounts for **7.624 core-s and 54.4% of a 14.023 core-s excess**, and
**4.23x** on the directly comparable predicate band (5.548 vs 1.312 core-s).

Q06 also adds a component Q04 could not see, because Q04's sargs are dates and Q06's are
NUMERIC: **`mr_data_readval_numeric` alone is 8.72% = 2.014 core-s**, decoding
`l_discount` and `l_quantity` out of the record into a fresh `DB_VALUE` via
`db_make_numeric` on **every one of 59,986,052 rows**, 58,846,788 of which are then
discarded. PostgreSQL has **no counterpart symbol at all** — a `numeric` Datum is a pointer
into the buffer page and `cmp_numerics` compares the on-disk digit arrays in place — so
this is a **structural absence**, not a dearer implementation of the same work, and it is
the part of IMP-008 that is provably removable rather than possibly irreducible. That is
the A/B leverage the old P1 justification explicitly lacked. A further **1.55% = 0.358
core-s** is pure PLT stub overhead (`or_header_size@plt` 1.07%, `pr_type_from_id@plt`
0.48%) for cross-object per-row type dispatch that a plan-time-resolved comparison would
not perform at all. Full fields, call-graph proof and both engines' symbol tables in
`reports/improvement-registry.json`.

### IMP-007 — Q06 relation: the copy is inside the buffer fix, on the query thread

Q06 is IMP-007's largest measurement and its cleanest proof. `perf -g` resolves **100%** of
the 9.18% `rep_movs_alternative` weight to one chain ending in
`pgbuf_fix_release → pgbuf_claim_bcb_for_fix → fileio_read → pread64`, i.e. the page-cache
copy happens **inside the buffer fix on the executor thread**, 608,510 times per statement
at 16,377 bytes each, for a total of 2.543 core-s (11.01% of the profile, 18.1% of the
excess). PostgreSQL issues **39,043** syscalls for 78,482 pages (2.01 pages per read, via
`io_combine_limit = 16`) and executes them in separate `pg_io_worker` processes, so its
executor profile contains no kernel read-copy symbol and the cost appears as **0.34 core-s
of `auxiliary_query_cpu`**. Raised P2 → P1: on Q03/Q04 the asynchrony argument was
weakened because PostgreSQL took few or zero physical reads, whereas on Q06 both engines
read and the 15.6x syscall difference is directly measurable. Still not P0, and explicitly
**sequenced after IMP-010**, which removes 65% of the reads at a fraction of the cost.

### IMP-002 — Q06 relation: the serial control, and a re-scoping

Q06 supplies the control this candidate never had. IMP-002's root cause is worded as the
replacement policy failing "to retain a working set that marginally exceeds the pool". Q06
tests exactly that situation — 682,937 pages against a 524,288-page pool, 30.2% oversized —
and on **one** scan thread the policy retains 524,007 pages and reads 158,930, the
arithmetic optimum to **0.18%**. The wording is therefore not supported for the serial path;
the failure is real but belongs to the parallel scan path and is now tracked as IMP-010 with
a source-localized cause.

**Action recorded rather than taken:** IMP-002's Q01, Q03 and Q04 evidence was all collected
on parallel scans and has **not** been re-measured serially. Those relations are **flagged
for re-validation**. If a serial re-measurement lands on the predicted pool overflow there
too, that evidence belongs to IMP-010 and IMP-002 should be narrowed to its Q05
pool-hysteresis failure mode. Re-measuring a closed query needs its own gated blocks and is
outside Q06's scope, so it is recorded in the ledger rather than done here. Q06's own
contribution to the Q05 hysteresis finding is mild and consistent: a **3.08%** non-monotone
block-to-block level wobble that tracks the level each block's own warm left behind.

### IMP-005 — Q06 relation: two new defects and a positive control

Two mechanically distinct new defects in the same subsystem, both zero-runtime-cost
observability failures, both proved by a serial control on the identical query:

1. **The parallel trace reports `rows` = `readrows`.** Serial and `PARALLEL(1)` report
   `rows: 1139264` correctly; `PARALLEL(3)`, native `PARALLEL(6)` and `PARALLEL(12)` all
   report `rows: 59986052`. Ground truth is 1,139,264, confirmed identically on both
   engines by `count(*)` and by PostgreSQL's own actual plan
   (`189877.33 × 6` qualifying plus `9807798 × 6` removed = 59,986,052 exactly). A reader
   of a parallel Q06 trace cannot see that **98.1%** of scanned rows were filtered out —
   the one number needed to judge whether an index would help.
2. **`statdump`'s data-page counters never advance on the parallel path.**
   `Num_data_page_fetches` = 23,255,736, `Num_data_page_ioreads` = 814,716 and
   `Data_page_buffer_hit_ratio` = 96.49 were byte-identical before and after a statement
   that issued 608,635 `pread` syscalls totalling 9.29 GiB. All Q06 buffer evidence
   therefore comes from the trace plus `/proc/<pid>/io`, which agree to **0.03%**, and
   `statdump`'s page gauges are recorded as **UNRELIABLE for this campaign**.

Plus a **positive control** for IMP-005's original `(k−1)x` finding: Q06's `scan_ptr` chain
is depth 1, the predicted multiplication is 1x, and the trace's `fetch` of 682,938 matches
the relation's 682,937 heap pages exactly. Together with Q05's negative control (a 5-level
chain that runs at degree 1 and is exact), the defect is now bounded from both sides: it
needs a nested chain **and** parallel workers on it.

None of the candidates is marked `validated`: no correctness evidence for a fix exists yet.
Full fields in `reports/improvement-registry.json`.

## 10. Evidence index

Format: `claim → raw file → formula → evidence type → SHA-256`.
All paths are under `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q06/`; byte sizes and
full hashes for all **256** artifacts (248 valid, 8 retained-invalid) are in
`reports/Q06/raw-manifest.json`.

| Claim | Raw file | Formula / basis | Evidence type | SHA-256 |
|---|---|---|---|---|
| preflight: ownership OK, 34 TIDs 0 off-cpuset, 8FK/8-btree 8/8/8 convalidated, row counts, contract values, provenance, external load 0.512 PASS | `preflight-Q06.txt` | direct capture | direct A/B | see manifest |
| post-block gate: 0 orphans, 36 TIDs 0 off-cpuset, pool conserved at 524,288 pages, external 0.334 PASS, live PG settings incl. `dynamic_shared_memory_type=mmap`, `io_method=worker`, `io_combine_limit=16` | `q6-postcheck.txt` | direct capture | direct A/B | see manifest |
| `SSOT_DRIFT = NONE`: HEAD = origin/main = `1faea89`, `HEAD:tpch-sspq/SSOT.md` = pinned blob at both gates, `porcelain(tpch-sspq)` empty | `preflight-Q06.txt`, `q6-postcheck.txt` | `git rev-parse` | direct A/B | see manifest |
| Q06 `result-equivalent-at-SF10`, 1 row, byte-identical `1230113636.0101`, tolerance never entered | `q6-correctness.json`, `q6-correctness-{cubrid,postgresql}.out` | canonical compare (no ORDER BY) | direct A/B | see manifest |
| **ground truth 1,139,264 qualifying of 59,986,052, identical on both engines**, plus per-predicate counts and column ranges | `q6-groundtruth-cubrid.out`, `q6-groundtruth-pg.out` | `count(*)` under the same predicates | direct A/B | see manifest |
| CUBRID estimated plan, non-executing (0.02 s, no rows): single `sscan`, 3 sargs, `sel` 0.148261/0.179933/0.4801, card 768,284 | `q6-plan-est-cubrid.out`, `q6-plan-est-cubrid.time` | `SET OPTIMIZATION LEVEL 514` | direct A/B | see manifest |
| PostgreSQL estimated plan + live `Settings:`: `Parallel Seq Scan`, rows 226,301/worker | `q6-plan-est-pg.out` | `EXPLAIN (COSTS, VERBOSE, SETTINGS)` | direct A/B | see manifest |
| **CUBRID 3 headline values, median 3.875000 s** | `Q06-cubrid-headline-block1.json` | median of 3 measured statements | direct A/B | see manifest |
| **PostgreSQL 3 headline values, median 1.618176 s** | `Q06-postgresql-headline-block1.json` | median of 3 measured statements | direct A/B | see manifest |
| headline reproducibility across **6 gated blocks per engine**: ratios 2.3947/2.3821/2.3337/2.3844/2.3937/2.3491, median-of-medians 2.386144 | `Q06-*-headline-block{1..6}.json` | per-block medians | direct A/B | see manifest |
| all 12 accepted blocks `CLEAN` (external max 0.42–1.29); one block-5 attempt `INVALID_BACKGROUND_LOAD`, retried | `Q06-*-bgload-block{1..6}.json`, `Q06-cubrid-headline-attempt2-INVALID.json` | host-wide SUT busy minus campaign CPU, 4 Hz | direct A/B | see manifest |
| **WARM: CUBRID stationary level 3.826 s over 100 statements, trend −0.69% (trailing-40 +0.30%)** | `q6-convergence-cubrid-long.json` | 100 identical statements, one connection | direct A/B | see manifest |
| WARM: PostgreSQL stationary level 1.590795 s, 40-statement trend +0.25%, spread 0.41% | `q6-convergence-pg.json` | same | direct A/B | see manifest |
| CUBRID warming series (first probe) scores −2.45%, the signal the gate must separate | `q6-convergence-cubrid.json` | half-split trend | direct A/B | see manifest |
| **gate tolerances derived from a moving-block bootstrap null (CUBRID n=40 max 1.91% vs signal 2.45%; PostgreSQL n=40 max 0.46%)** | `q6-warmgate-bootstrap.json`, `q6-warmgate-bootstrap.py` | bootstrap of the half-split trend statistic, seed 20260731, 20,000 reps | projection | see manifest |
| stationary-level ratio 3.826/1.5908 = 2.4051x agrees with the headline to 0.43% | `q6-convergence-cubrid-long.json`, `q6-convergence-pg.json` | ratio of independently measured levels | direct A/B | see manifest |
| CUBRID actual trace: `parallel workers: 6`, fetch 682,938, **ioread 608,427**, readrows 59,986,052 | `q6-trace-cubrid.out` | `SET TRACE ON` + `SHOW TRACE` | direct A/B | see manifest |
| PostgreSQL actual: `Workers Launched: 5`, `shared hit=1035988 read=89140` (= relpages exactly), `Rows Removed by Filter: 9807798` ×6 | `q6-plan-act-pg.out`, `q6-plan-act-pg.json` | `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, TIMING, SETTINGS, WAL)` | direct A/B | see manifest |
| **serial A/B: CUBRID 20.562 s vs PostgreSQL 6.5699 s = 3.1297x per-row cost ratio at `U`≈1 on both** | `q6-counterfactuals.txt`, `Q06-cubrid-serial-headline-telemetry.json`, `Q06-postgresql-serial-headline-telemetry.json` | grouped-repeat medians + telemetry `U` | direct A/B | see manifest |
| DOP sweep: CUBRID 20.562/11.04/7.37/3.875/2.021 s at 1/2/3/6/12 units; PostgreSQL 6.5699/3.925/2.858/1.618/1.297 s at 0/1/2/5/11 workers | `q6-counterfactuals.txt` | grouped-repeat trailing medians | direct A/B | see manifest |
| **`PARALLEL(12)` reaches 2.021 s, 1.917x faster than the contracted `parallelism=6`** | `q6-counterfactuals.txt`, `variants/trace-PARALLEL12.txt` | grouped-repeat median + trace worker count | direct A/B | see manifest |
| dialect `date + interval` cast costs 0.20% (1610.603 vs 1607.452 ms) | `q6-counterfactuals.txt`, `variants/q6-pg-DATEDATE.sql` | grouped-repeat trailing median | direct A/B | see manifest |
| **IMP-010: reads/statement 158,930 (1 unit) vs 468,980/458,209/459,242 (3/6/12) against a predicted 158,649 overflow** | `q6-lru-ab.txt` | `/proc/<cub_server>/io` `syscr` delta ÷ statements, 2 equilibrating passes per variant | direct A/B | see manifest |
| **IMP-010 contrast: PostgreSQL 76,987 (serial) vs 78,482 (dop 5) against a predicted 76,552 — 1.9% DOP effect** | `q6-serial-telemetry.txt`, `q6-bufstate.txt` | `pg_stat_reset()` + `pg_statio_user_tables` per statement | direct A/B | see manifest |
| `PARALLEL(1)` degenerates to the serial path (no `parallel workers` line, correct `rows`, 158,929 reads) — the limitation on IMP-010's control | `variants/trace-PARALLEL1.txt`, `q6-lru-ab.txt` | trace + syscall delta | direct A/B | see manifest |
| **headline-regime CUBRID rchar 9.286 GiB and 608,510 read syscalls/statement, device `read_bytes` 0** | `Q06-cubrid-headline-telemetry-run{1,2,3}.json` | `/proc/<pid>/io` deltas ÷ 4 statements; `/proc/diskstats` | profile attribution | see manifest |
| CUBRID headline-regime CPU 92.00 core-s/block, `U` 5.96860, TWU 5.9498, tail 0.000 s | `Q06-cubrid-headline-telemetry-run2.json` | per-TID ticks / `SC_CLK_TCK`, actual dt weighting | profile attribution | see manifest |
| PostgreSQL headline-regime CPU 38.70 core-s/block, `U` 5.81408, TWU 5.5784, tail 0.232 s, `pg_io_worker` 1.29 core-s | `Q06-postgresql-headline-telemetry-run3.json` | same | profile attribution | see manifest |
| `U` reproducibility: CUBRID 5.9650/5.9686/5.97964 (0.25%), PostgreSQL 5.84122/5.80618/5.81408 (0.60%) | `Q06-*-headline-telemetry-run{1,2,3}.json` | same | profile attribution | see manifest |
| serial telemetry: CUBRID `U` 1.00333 / PostgreSQL `U` 1.03859, proving both serial variants are single-unit | `Q06-{cubrid,postgresql}-serial-headline-telemetry.json` | same | profile attribution | see manifest |
| **CUBRID IPC 2.30, 6.008 CPUs utilized, 983.1e9 instructions in 25.002 s** | `perf-stat-cubrid.txt` | `instructions/cycles`, `task-clock/elapsed` | profile attribution | see manifest |
| **PostgreSQL IPC 1.77, 5.718 CPUs utilized (valid executor set via postmaster inherit-on-fork)** | `perf-stat-pg.txt` | same | profile attribution | see manifest |
| CUBRID bands: sarg 24.02%, domain decode 14.67%, kernel read 11.01%, deform 23.70%; 0 unresolved symbols | `profile-cubrid-flat.txt`, `q6-bands.txt` | `perf report` self% × executor CPU/statement | profile attribution | see manifest |
| PostgreSQL bands: deform 39.02%, sarg 14.46%, worker page-table 14.75%; 0 unresolved symbols | `profile-pg-flat.txt`, `q6-bands.txt` | same | profile attribution | see manifest |
| **call graph: 100% of `rep_movs_alternative` under `pgbuf_fix_release → fileio_read → pread64`; 17.89% of deform under `eval_data_filter`; `mr_data_readval_numeric` 8.40% under it** | `profile-cubrid-callgraph.txt` | `perf report -g caller` | profile attribution | see manifest |
| perf coverage: 150,073 / 141,148 samples, 0 lost, 0 `[unknown]`, drivers completed | `perf-record-cubrid.log`, `perf-record-pg.log`, `sink/Q06-{cubrid,pg}-perf.out` | `perf record` stderr + sink line counts | profile attribution | see manifest |
| **IMP-005: parallel trace reports `rows`=`readrows`; serial reports 1,139,264 correctly** | `variants/trace-{NOPARALLELSCAN,PARALLEL1,PARALLEL3,PARALLEL12}.txt`, `q6-trace-cubrid.out` | trace counters vs ground truth | direct A/B | see manifest |
| **IMP-005: `statdump` page counters byte-identical across a statement that issued 608,635 preads** | `q6-cubrid-bufstate.txt` | `cubrid statdump` before/after vs `/proc/<pid>/io` deltas | direct A/B | see manifest |
| card factors, `W` derivation, all cross-checks | `Q06-causal-card.json`, `q6-card-calc.txt` | section 16 formulas | profile attribution | see manifest |
| **retained-invalid**: block-5 attempt 1 WARM not established, attempt 2 `INVALID_BACKGROUND_LOAD`; superseded by attempt 3, excluded from all calculations | `Q06-cubrid-*-attempt2.*`, `Q06-cubrid-headline-attempt2-INVALID.json` | see section 3-b | invalid | see manifest (`valid=false`) |

Not promoted (dispensable work per SSOT section 19): the raw `perf-*.data` captures
(1,268 MB CUBRID, 1,184 MB PostgreSQL, plus a 1,193 MB superseded PostgreSQL capture) and
the per-TID sampler dumps, which are fully summarised by the promoted `profile-*-flat.txt`
/ `-callgraph.txt` and by the telemetry JSONs plus their intervals files. The manifest
records all four decisions under `not_promoted`, including why the superseded capture
exists.

## 11. Notion sync

**Status: `NOTION_OUT_OF_WORKER_SCOPE` → idempotent Git backfill record written
(write path 3 only).**

Section 21's execution boundary is explicit: this GJC/tmux worker session runs on the
remote build host, has no Notion connector, and **must never attempt a Notion write**. Its
Notion-adjacent duty ends at committing and pushing this report, manifest and registry to
`origin/main`. Accordingly:

1. *official Notion connector* — **not attempted** (forbidden for the worker; also not
   exposed to this session's tool set).
2. *logged-in Aside browser* — **not attempted** (forbidden for the worker).
3. *idempotent Git backfill record* — **written**: appended to
   `reports/notion_backfill_pending.jsonl`, keyed on
   `campaign_id + QNN + session_id + report_commit + content_fingerprint`, carrying the
   section 21 required query fields with the same field names as this report.
   `content_fingerprint` follows the Q01–Q05 convention: sha256 of this `report.md` at
   `report_commit`. The record is written only after report, manifest and registry are
   durable on `origin/main`. `pending_cleared` is `false`.

This satisfies the section 26 gate item ("Notion relations are synced **or** an idempotent
backfill record is durable") without a Notion call. Pending is **not** cleared: clearing
requires a server-side refetch, which only a Notion-capable subagent may perform. Sections
3-a, 3-b, 4, 6, 7, 8 and 9 of this report are written to be that mirror's source, including
the full factor table, both engines' plan shapes with a per-node comparison, both engines'
top-cost symbols, `file:line` on both sides of every contrast, the rejected explanations
with their rejecting numbers, and the complete section 18 content for `IMP-010` plus the
extended `IMP-002`, `IMP-005`, `IMP-007` and `IMP-008`.

Notes for the reconciler, beyond the usual fields:

- **Two priority changes must be mirrored**: `IMP-008` P1 → **P0** and `IMP-007` P2 →
  **P1**, each with the measured justification recorded in the ledger.
- `next_id` is now **`IMP-011`**, and `IMP-010` is the campaign's first candidate carrying
  an *arithmetically predicted* control value.
- **`IMP-002` is re-scoped, not merely extended.** Its Q01/Q03/Q04 relations are flagged
  for re-validation. A mirror that presents IMP-002 unchanged would misstate the campaign's
  current position.
- Section 21's markdown formatting rule (added at this query's pin `d19dca41` after Q04's
  page rendered literal `n` glyphs and literal `<table>` tags) applies: this report contains
  markdown tables, fenced code blocks and `##` headings throughout. Assemble the mirror with
  real newlines, do not escape the structural markup, and refetch the page afterwards to
  scan for an isolated `n` token or a literal `<`/`&lt;` inside a rendered table before
  considering the write done.

## 12. Completion checklist

- [x] preflight and correctness status recorded (section 1, section 2); external load
      0.512 core-s/s PASS at preflight, no wait required; post-block gate re-run and PASS
- [x] three valid headline values for each completing engine (both completed; neither
      censored). **Six gated blocks per engine were measured rather than the contractual
      one**, because three could not distinguish a drift from a wobble; every accepted
      block verified `CLEAN` against the section 9 threshold at 4 Hz and preceded by a
      proved WARM steady state under a gate whose tolerance was derived from this query's
      own measured stationary null distribution
- [x] timeout confirmations — not applicable, neither engine censored (3.88 s and 1.62 s
      against a 300 s limit)
- [x] plan, execution, profile and source contrast sections complete
- [x] causal multiplier card has evidence for every factor, with **`F_plan` numeric
      (1.0000) by four independent structural-equality proofs and `F_work` exactly 1.0000**,
      the residual declared an identity rather than a prediction, and closure carried by
      five independent quantities (`U` reproducibility, TWU, `perf stat`,
      instructions × IPC, and the stationary-level ratio)
- [x] Git improvement ledger deduplicated and committed (`IMP-010` allocated with the full
      section 18 field set; `IMP-008` extended and **raised to P0**; `IMP-007` extended and
      **raised to P1**; `IMP-002` **re-scoped** with its Q01/Q03/Q04 relations flagged for
      re-validation; `IMP-005` given two new defects and a positive control; `IMP-001`
      **considered and rejected** for a Q06 relation on a measured 0.31%; `next_id:
      IMP-011`)
- [x] every claim indexed to raw evidence and checksum (256 artifacts; 8 retained as
      invalid and excluded from all calculations)
- [x] report, manifest and registry committed, pushed and reachable from `origin/main`
- [x] `QUERY_COMPLETE` emitted by the worker session
- [ ] **current session removed and absence verified — OUTSTANDING, control-plane
      action.** This worker *is* the Q06 session: tmux session
      `gajae_code_ms7ztf7g_9w2w4xfn`. Self-removal would terminate the worker mid-turn and
      make the mandated dual absence check unobservable, so it is deliberately NOT claimed
      here. Per section 22 steps 7-9 and the section 23 `QUERY_COMPLETE` action, removal
      and absence verification are performed from outside this session, before any Q07
      session is created:

      ```
      gjc session remove gajae_code_ms7ztf7g_9w2w4xfn
      gjc session status gajae_code_ms7ztf7g_9w2w4xfn      # expect: absent
      tmux has-session -t gajae_code_ms7ztf7g_9w2w4xfn     # expect: non-zero exit
      # if remove refuses a live session, exact-target fallback (never by pattern):
      tmux kill-session -t gajae_code_ms7ztf7g_9w2w4xfn
      ```

      The Q05 session `gajae_code_ms7p9g4j_r7yxsbvc` was verified absent at the start of
      this query by both mandated checks (`gjc session status` → `gjc_tmux_session_not_found`,
      `tmux has-session` → exit 1) and `gjc session list` showed exactly one session, this
      one, so the section 22 "never two measurement sessions concurrently" rule held
      throughout Q06.

Harness changes made during Q06 (all under `harness/`, section 5 allowlist):

- `harness/perf_run.sh` — **closed a carried-forward campaign gap: PostgreSQL's
  `perf stat` utilization was invalid on Q04 and Q05 and produced nothing at all on Q06.**
  Both symptoms are one defect: PostgreSQL's parallel workers are transient per statement,
  so any post-hoc PID snapshot covers at most one statement's workers, and on Q06 the
  snapshot raced their exit and `perf stat` failed with "Problems finding threads of
  monitor". For PostgreSQL the script now attaches `perf stat` to the **postmaster before
  the driver's connection exists**, so perf's inherit-on-fork counts the leader backend and
  every statement's parallel workers and nothing else — io workers and background workers
  pre-date the attach and stay in auxiliary, matching `telemetry_run.py`'s existing
  `classify()` split. The CUBRID path is unchanged (all query threads live in the one
  pre-existing `cub_server` process, so a post-hoc attach is complete), and the PostgreSQL
  worker snapshot is still resolved and printed, now explicitly labelled informational.
  Verified by re-running the whole PostgreSQL profile stage through the fixed script: it
  reproduces the ad-hoc measurement to 0.37% (5.718 vs 5.739 CPUs utilized, IPC 1.77 both)
  and the flat profile agrees with the pre-fix capture within 0.3 pp per symbol.

No other harness file was modified: Q05's `warm_establish.py` rewrite already exposed the
gate parameters as environment overrides, which is all Q06 needed to derive and apply its
own thresholds.

Known carried-forward gaps, explicitly recorded rather than silently omitted:

- CUBRID actual histogram bucket count remains `UNMEASURED` (opaque `VARBIT` catalog);
  target 300 is configured and verified. Q06 makes this gap *more* interesting rather than
  less: CUBRID's `l_discount` range selectivity is 1.516x low on a column with 11 distinct
  values where a bucket-exact histogram should be near-perfect, and without the actual
  bucket contents the cause cannot be attributed. Because Q06 has only one possible plan,
  nothing measured here depends on it, and no candidate was allocated on a guess.
- **`cubrid statdump`'s data-page counters are newly recorded as UNRELIABLE** (section 5):
  they did not advance across a statement that provably issued 608,635 `pread` syscalls.
  Every buffer number in this report comes from the query trace plus `/proc/<pid>/io`, which
  agree to 0.03%. This is now a Q06 relation on IMP-005 rather than an unexplained
  discrepancy, but it means the campaign has no working server-global page-buffer gauge.
- CUBRID's index page count is still not exposed by `db_index`, so any CUBRID-side index
  page accounting remains a projection. Q06 uses no index and does not depend on one.
- `perf stat`'s "CPUs utilized" is now valid for **both** engines (see the harness change
  above), which removes the Q04/Q05 asymmetry caveat. The remaining asymmetry is only that
  CUBRID's number covers one process while PostgreSQL's covers a process tree; both are
  complete for their engine.
- The reported block is block 1 by the campaign's first-accepted-block convention and is
  **not** simultaneously the median of medians: the median-of-medians ratio is 2.386144x
  against the reported 2.394672x, **−0.36%**. Recorded rather than resolved in either
  direction. Six blocks per engine were measured specifically so this could be stated with
  a spread rather than asserted.
- **Q06's headline is a statement about a configured comparison, and on this query that
  matters more than usual**: at `parallelism=12` CUBRID reaches 2.021 s (1.917x faster than
  its contracted 3.875 s) and at `max_parallel_workers_per_gather=11` PostgreSQL reaches
  1.297 s. Both are counterfactuals outside the contract. The 2.3947x headline is correct
  for the contracted `configured node/gather-cap comparison` and should not be read as a
  ceiling for either engine.
- Both engines' block statements sit 1.3–2.1% above their own 40-statement stationary level
  because the WARM establishment runs in a separate connection while the contract fixes the
  measured block at four statements in one connection. This biases levels, not materially
  the ratio (stationary-level ratio 2.4051x vs headline 2.3947x, 0.43%).
- The CUBRID WARM gate's separation on Q06 is thin: the n=40 stationary null max is 1.91%
  against a 2.45% warming signal (1.28x). The absolute-level cross-check against the
  independently measured 3.826 s stationary level is what actually carries the WARM claim on
  the CUBRID side, and it is reported alongside the gate verdict rather than in place of it.
- The measurement host is shared and containerised (host-wide `/proc/stat` and
  `/proc/diskstats`), so external load is invisible to `ps` inside the container and any
  device-I/O figure is an upper bound shared with other tenants rather than an attribution
  to this campaign. On Q06 the relevant reading is that device `read_bytes` is **0** for
  both engines, which is a lower-bound-safe direction for every claim made here.
- The CUBRID databases live under a repository-internal `.git_ignored_dir`; this is the
  reused SF10 dataset and moving it would be a destructive action outside the cleanup
  manifest, so it was left untouched and only recorded.
- The pinned CUBRID source checkout shows one dirty entry, ` M cubrid-cci` (a submodule
  pointer, not a source file). `git rev-parse HEAD` matches the pinned
  `607f1ee9fb2394de129e083602c84a6525fc685c` exactly and every `file:line` in section 7 was
  read at that commit; the running binary's SHA-256 and ELF Build ID match the frozen build
  manifest, so the measured binary predates and is unaffected by that entry. Recorded for
  completeness. The PostgreSQL checkout at `5713b437` shows only an untracked `.omc/`
  directory.
