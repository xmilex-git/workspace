# TPCH-SSPQ FK campaign — Q16 report

TPC-H Query 16, *Parts/Supplier Relationship*.

## 3-a. Causal multiplier card

```text
R_wall 2.411225x [wall, median of 3 per engine; PostgreSQL is 2.4112x faster]
= F_plan  0.929368x [plan-shape; same-engine PostgreSQL A/B, section 4-d]
× F_units 0.855774x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   3.031730x [total query CPU-seconds]

F_cpu 3.031730x [total query CPU-seconds]
= F_work 1.000000x [rows entering the grouping/DISTINCT pipeline: 1,186,602 vs 1,186,602 — EXACTLY equal]
× F_cost 3.031730x [8000.1 ns vs 2638.8 ns of total query CPU per row]
```

**Read the card in one line: Q16's gap is not the plan, not parallelism, and not
I/O — it is what CUBRID pays per row to execute a plan it picked correctly.**
Two of the three factors are *below* 1.0, which has not happened before in this
campaign, and both matter:

- **`F_plan` is 0.929368x — CUBRID's plan shape is the *better* one.** Anchored on
  PostgreSQL's own `enable_presorted_aggregate` switch (section 4-d): forced into
  CUBRID's aggregation shape, PostgreSQL measures **1.112363 s against its native
  1.196902 s**, i.e. the shape PostgreSQL's optimizer picks is **7.06% slower**
  than the shape CUBRID picks. The obvious story — "CUBRID's `count(DISTINCT)`
  plan is wrong" — is refuted by the other engine's own switch.
- **`F_units` is 0.855774x — CUBRID runs at *more* active units.** Measured
  U 3.28929 against PostgreSQL-controlled 2.81489 (native 3.06804), TWU 3.2399,
  and CUBRID's own `NO_PARALLEL_SCAN` A/B gives a **2.6646x** speedup for a 17.60%
  CPU surcharge (81.0% efficiency against U). Nothing in Q16's gap is parallelism.
- **Everything is in `F_cost` 3.031730x on `F_work` exactly 1.000000x.** Both
  engines scan the same 2,000,000 `part` rows, perform the same 296,824 index
  searches into `partsupp`, carry the same 1,186,602 rows into grouping and emit
  the same 27,840 groups — all four counts verified by independent ground-truth
  `count(*)` run on **both** engines and returning byte-identical values.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 0.929368x | plan shape (DISTINCT-aggregate sort key) | wall-seconds, same engine, same block regime | `T_P_nopresorted / T_P_native` = 1.112363 / 1.196902 | `Q16-postgresql-nopresorted-headline.json`, `Q16-postgresql-headline-block1.json`, `q16-plan-est-pg-nopresorted.out`, `q16-plan-est-pg.out` | direct A/B (same engine, controlled plan) |
| `F_units` | 0.855774x | active execution units | CPU-seconds / wall-second over the §12 block | `U_P'/U_C` = 2.81489 / 3.28929 | `Q16-postgresql-nopresorted-headline-telemetry.json`, `Q16-cubrid-headline-telemetry-run2.json` | profile attribution |
| `F_cpu` | 3.031730x | total query CPU-seconds | per query execution | `CPU_C/CPU_P'` = 9.492891 / 3.131179 | same telemetry JSONs × the block medians | profile attribution |
| `F_work` | 1.000000x | rows into the grouping/DISTINCT pipeline | one statement | `1,186,602 / 1,186,602` | `q16-groundtruth-cubrid.out`, `q16-groundtruth-pg.out`, `q16-trace-cubrid.out`, `q16-plan-act-pg.out` | direct A/B (ground truth) |
| `F_cost` | 3.031730x | CPU-seconds per row into grouping | rows into grouping | `(CPU_C/W_C)/(CPU_P'/W_P)` = 8000.1 ns / 2638.8 ns | `Q16-causal-card.json`, `q16-bands.txt` | profile attribution |

**Anchor direction and denominator discipline (SSOT §16).** `F_plan` is anchored
on the **PostgreSQL native → PostgreSQL controlled** pair; `F_units` and `F_cpu`
are then computed on the **remaining controlled cross-engine pair**, CUBRID-native
vs PostgreSQL-`nopresorted`. No native denominator is mixed with a controlled one.
The identity `R_wall = (T_P'/T_P) × (T_C/T_P')` holds by construction, and
`F_units × F_cpu = T_C/T_P'` = 2.594694x.

The anchor is on the **PostgreSQL** side, not the CUBRID side, because CUBRID has
no switch that changes only this decision: the `count(DISTINCT)` execution strategy
is not a costed alternative in CUBRID's plan space at all (section 7). PostgreSQL
does have exactly that switch, and it changes **exactly one line of the plan** —
the sort key gains or loses `ps_suppkey` — with every other node byte-identical
including costs (section 4-d).

**Reconstruction residual: `F_plan × F_units × F_cpu` = 2.411224979x against
`R_wall` 2.411224979x, residual `0.000000000000%`.** CPU is attributed as
`U × t_median` on the same block regime the wall is defined on, so the identity is
exact by construction once `F_plan` is factored out on its own same-engine pair.
The independent cross-checks are TWU (−1.50% against `U` on CUBRID, +1.57% on
PostgreSQL-controlled), `perf stat` instruction counts (2.3932x against `F_cpu`'s
2.5851x on the *native* pair — section 6-d explains the 7.4% spread), the two
parallelism A/Bs, and the engines' own trace/EXPLAIN counters.

### Error budget, stated before any factor is interpreted

| | contract block medians | spread |
|---|---|---|
| CUBRID, 3 gated §12 blocks | 2.886000 / 2.887000 / 2.869000 s | **0.6237%** |
| PostgreSQL, 3 gated §12 blocks | 1.196902 / 1.194293 / 1.199570 s | **0.4409%** |
| within-block sd (block 1) | CUBRID 0.007937 s (0.275%), PostgreSQL 0.004575 s (0.383%) | |

Every factor below 1.0065x is inside the measurement band and is not interpreted.
`F_plan` 0.929368x is **11.3x** the CUBRID band and **16.0x** the PostgreSQL band,
so it is a real effect and not noise. The `F_cost` 3.031730x and the serial-phase
3.5773x of section 8 are far outside it.

## 3-b. Headline timings

| Field | CUBRID | PostgreSQL |
|---|---|---|
| measured statement 1 | 2.889000 s | 1.196902 s |
| measured statement 2 | 2.886000 s | 1.198148 s |
| measured statement 3 | 2.874000 s | 1.189675 s |
| **median (headline)** | **2.886000 s** | **1.196902 s** |
| mean | 2.883000 s | 1.194908 s |
| within-block sd | 0.007937 s | 0.004575 s |
| uncounted warmup statement | 2.881000 s | 1.219912 s |
| **median wall ratio** | **2.411225x** (PostgreSQL faster) | |
| correctness | `result-equivalent-at-SF10` | |
| censoring | none — neither engine approached the 300 s timeout | |

Regime `single-query-repeat WARM`, metadata connection mode
`single-connection-four-statements`, one direct campaign connection per block,
one uncounted warmup then three measured statements, no reconnect and no prepare
between them, every row fully consumed into a campaign-owned sink under `work/Q16`
with no terminal rendering. Sink size is byte-identical across all six blocks:
9,205,567 bytes (CUBRID) and 4,269,142 bytes (PostgreSQL). Sink content hashes are
computed after the headline timer stops.

### All three blocks per engine

| Block | CUBRID measured (s) | median | PostgreSQL measured (s) | median |
|---|---|---|---|---|
| 1 (headline) | 2.889000 / 2.886000 / 2.874000 | 2.886000 | 1.196902 / 1.198148 / 1.189675 | 1.196902 |
| 2 | 2.877000 / 2.887000 / 2.904000 | 2.887000 | 1.194293 / 1.185576 / 1.195576 | 1.194293 |
| 3 | 2.870000 / 2.869000 / 2.859000 | 2.869000 | 1.200341 / 1.199570 / 1.194097 | 1.199570 |

Block 1 is the headline for both engines (the first gated §12 block after the WARM
gate passed). Blocks 2 and 3 are valid measurements retained as stability evidence.
Five of the six blocks were accepted on attempt 1; PostgreSQL block 3 was rejected
once by the **WARM** gate (trailing-6 spread 3.3297% > 2.50%), not by the load gate,
and accepted on attempt 2. Every accepted block is `CLEAN` under **both** the strict
per-sample rule and the contract-window rule; external SUT-set load over all six
blocks stayed at mean 0.198–0.256 and max 0.843 core-s/s against the 6.0 threshold.

### Controlled variants (never headline values)

| Configuration | median (s) | vs its own native | U | TWU | CPU/statement |
|---|---|---|---|---|---|
| CUBRID native | 2.886000 | — | 3.28929 | 3.2399 | 9.4929 core-s |
| CUBRID `/*+ NO_PARALLEL_SCAN */` | 7.690000 | 2.6646x slower | 1.04975 | 1.0545 | 8.0726 core-s |
| PostgreSQL native | 1.196902 | — | 3.06804 | 3.0978 | 3.6721 core-s |
| PostgreSQL `enable_presorted_aggregate=off` | 1.112363 | **1.075998x faster** | 2.81489 | 2.8594 | 3.1312 core-s |
| PostgreSQL `max_parallel_workers_per_gather=0` | 4.123853 | 3.4454x slower | 0.99162 | 0.9959 | 4.0893 core-s |

Every variant was measured through the **same** §12 block regime and the **same**
SSOT §9 load gate as the native blocks, each with its own WARM proof, and every
artifact carries the variant tag so it can never overwrite a native block.

### WARM proof

WARM is proved, not assumed, and on Q16 it is proved to be **complete on both
engines** — this is the first query in the campaign with zero physical reads on
both sides.

| | CUBRID | PostgreSQL |
|---|---|---|
| engine buffer counter delta over a 4-statement block | `Num_data_page_ioreads` 0, `Num_data_page_fetches` 0 — **counter unusable, see below** | `pg_stat_database.blks_read` 761,539,937 → 761,539,937, delta **0** |
| `/proc/<server>/io` `read_bytes` delta | **0** | **0** |
| `/proc/<server>/io` `rchar` delta | 14,912 B over 4 statements (3,728 B/statement) | 255,254,434 B (63.8 MB/statement) |
| `/proc/diskstats` device read delta | 0.254 MiB (whole host, all devices) | 0.000 MiB |
| `pg_statio` heap+idx reads on Q16's relations | n/a | delta 0 |
| working set vs 8192 MB budget | `part` 380.5 MiB + `partsupp` index; fits | `part` 320 MB + `partsupp_pkey`; fits |

CUBRID's `rchar` of 3,728 B per statement is not a buffer miss — it is three
orders of magnitude below one 16 KiB page per statement, so the entire Q16
working set is resident and the 27,840 per-group temp list files (section 8)
never reach a write syscall either (`write_bytes` delta 4,096 B across the whole
block). **PostgreSQL's 63.8 MB/statement of `rchar` is not a data read**: it is the
external-merge sort spilling to temp files (`Sort Method: external merge Disk:
12,136 kB` × 5 units, `temp read=7574 written=7594` 8 kB blocks = 59.2 MB), i.e.
the engine that reads *more* from the OS on Q16 is the faster one, and the
difference is temp-sort traffic, not table I/O.

**`cubrid statdump` remains unusable on this server** — reconfirming the Q14
finding. Bracketing a whole four-statement block gives delta 0 on
`Num_data_page_fetches`, `Num_data_page_ioreads`, `Num_data_page_dirties` and every
other counter, in `-c` mode, while `/proc` recorded real (small) activity over the
same window. The counters are retained as evidence with an explicit invalid reason
and are **excluded from every calculation**; Q16's CUBRID buffer evidence rests on
`/proc/<cub_server>/io` and `/proc/diskstats`.

## 2. Correctness

`result-equivalent-at-SF10`.

| | value |
|---|---|
| rows | **27,840** on both engines |
| ordering | `ORDER BY supplier_cnt desc, p_brand, p_type, p_size` — total order, compared as an exact ordered sequence |
| comparison rule | SSOT §11 ordered-sequence comparison; text, integers, NULLs, row count and row multiset matched exactly |
| decimal handling | no decimal output column in Q16 (`count(DISTINCT)` is an exact integer), so the 1e-12 relative tolerance was never exercised |
| first differing row | none |
| censoring | none |
| artifact | `q16-correctness.json`, full result sets `q16-correctness-cubrid.out` (1,178,613 B) / `q16-correctness-postgresql.out` (1,067,252 B) |

### Dialect: zero changes

`queries/diff/q16.diff` is **0 bytes**. `queries/q16-pg.sql` is byte-identical to
`queries/q16-cubrid.sql`, which is itself byte-identical to the canonical source
`/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q16.sql`; all three
SHA-256 `0317fb05accbe6eb87ae713558e709f0b52760de53bc14000b191dbd94049ba9`. There
is no dialect artifact to isolate on Q16 and no syntax difference that could
explain any part of the gap.

### Independent ground truth, both engines

Eleven `count(*)` statements, executed separately on **each** engine outside any
plan's own instrumentation (`q16-groundtruth-cubrid.out`, `q16-groundtruth-pg.out`
— identical):

| key | value | role |
|---|---|---|
| `part_total` | 2,000,000 | rows scanned by both engines' `part` scan |
| `part_brand_ne` | 1,919,874 | `p_brand <> 'Brand#45'` |
| `part_type_notlike` | 1,933,121 | `p_type not like 'MEDIUM POLISHED%'` |
| `part_type_like` | 66,879 | the positive twin |
| `part_size_in` | 319,686 | `p_size in (49,14,23,45,19,3,36,9)` |
| `part_all3` | **296,824** | surviving `part` rows = index searches into `partsupp` |
| `partsupp_total` | 8,000,000 | |
| `ps_joined_surviving_part` | **1,187,296** | = 296,824 × 4.0000 exactly |
| `supplier_complaints` | **56** | `s_comment like '%Customer%Complaints%'` |
| `ps_after_antijoin` | **1,186,602** | rows into grouping — the `F_work` denominator |
| `output_groups` | **27,840** | = the result row count |

## 1. Identity

| Field | Value |
|---|---|
| campaign_id | `tpch-sspq-fk-r1-20260730` |
| QNN | Q16 — TPC-H *Parts/Supplier Relationship* |
| ssot_commit (pinned at session creation) | `cc56df92dfb91ede9bbcfd77a4823f5634a8413f` |
| ssot_blob_sha | `510478846bff081d3223d3835069283a7cd2e47b` |
| SSOT drift | **NONE**, verified at preflight and again at the post-block gate: `HEAD` = `origin/main` = `1c9c6184c144dfce25de55a042e1a2da039e2b50`, and `git rev-parse HEAD:tpch-sspq/SSOT.md` = the pinned blob at both. The pinned commit `cc56df9` is an ancestor of `HEAD` and `SSOT.md` is byte-identical between them, so the pinned contract and the current `main` contract are the same document. |
| gjc_session_id | `gajae_code_ms9x5fbd_qza0x9su` |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (includes PR #7441 merge `b334446d6`) |
| CUBRID build | CUBRID 11.5.0.2366-607f1ee 64bit RelWithDebInfo, gcc 8.5.0, assertions disabled, not stripped |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13`, ELF Build ID `4df41ee21300bf617bccd5e1d5c8522b074ef86e` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL build | PostgreSQL 20devel, gcc 8.5.0, `--enable-debug --without-llvm`, assertions off (`debug_assertions=off` live-verified), JIT off (live-verified), not stripped |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b`, ELF Build ID `5f2cb2987765c612638c278f85cfc85c211fffe1` |
| both hashes vs frozen `reports/bootstrap/build-manifest.json` | **match**, pre-block and post-block |
| databases | CUBRID `tpch_sf10_q1` port 1523 (owner PID 1612732, `cub_master` 1433697); PostgreSQL `tpch_sspq` PGDATA `/home/cubrid/pg/pgdata-tpch-sspq` port 5442 (postmaster PID 1433696) |
| ownership gate | `OK` (campaign-owned, correct executable/DB/port) at preflight **and** at the post-block gate; no non-campaign server was touched |
| schema | 8 FKs and 8 child B-trees per engine, exact column order, PostgreSQL `convalidated` 8/8 |
| statistics | CUBRID `update_statistics_update_histogram=y`, `default_histogram_bucket_count=300`; PostgreSQL `default_statistics_target=100`. Track label: **histogram-enabled controlled comparison** |
| parallel | CUBRID `parallelism=6`, `max_parallel_workers=100`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`, `parallel_leader_participation=on`, `max_worker_processes=16`. Label: **configured node/gather-cap comparison** |
| buffer/cache | CUBRID `data_buffer_size=8.0G` (524,288 pages); PostgreSQL `shared_buffers=8192MB`. Label: **configured-equal buffer budget** |
| shared memory | PostgreSQL `dynamic_shared_memory_type=mmap` (§9 parallel-plan-availability parity). Q16's PostgreSQL plan contains a **Parallel Hash Anti Join** and a large **Gather Merge**, so this setting is load-bearing on this query and is recorded as §9 requires. |
| cpuset / NUMA | SUT+client CPUs 0–15 node0, collectors 20–23. All engine TIDs on-cpuset **before** (34 TIDs, 0 off) and **after** (35 TIDs, 0 off) |
| external load | 0.250 core-s/s at preflight, 0.968 core-s/s at post-block (threshold 6.0) |
| orphans after the run | 0 `csql`, 0 `psql`, 0 PG parallel workers, 0 PG client backends |
| engine block order | Q16 is **even** → PostgreSQL block first, then CUBRID (§12) |
| query provenance | canonical / active-CUBRID / active-PG all SHA-256 `0317fb05...49ba9`; `queries/diff/q16.diff` 0 bytes |

## 4. Plan

### 4-a. CUBRID native (estimated, SQL `SET OPTIMIZATION LEVEL 514`, non-executing)

```text
temp(order by)                                    sort: 4 desc, 1 asc, 2 asc, 3 asc   cost 33448 card 18944
  temp(group by)                                  sort: 1 asc, 2 asc, 3 asc           cost 33331 card 18944
    idx-join (inner join)                                                             cost 33214 card 18944
      outer: sscan  class: part      sargs: term[1] AND term[2] AND term[3]           cost 29353 card  7564
      inner: iscan  class: partsupp  index: pk_partsupp_ps_partkey_ps_suppkey (covers)
                                     filtr: term[4]                                   cost     4 card 7999519
  SUBQUERY (uncorrelated):
    temp(distinct)                                                                    cost  1537 card 10
      sscan class: supplier  sargs: term[0]                                           cost  1531 card 10
```

### 4-b. PostgreSQL native (estimated and actual)

```text
Sort                              (cost=362713.89..363099.36 rows=154186)  actual 1267.023..1267.911 rows=27840
  Sort Key: count(DISTINCT ps_suppkey) DESC, p_brand, p_type, p_size       quicksort Memory: 2507kB
  GroupAggregate                  (cost=187932.07..344681.44 rows=154186)  actual  619.064..1233.393 rows=27840
    Group Key: p_brand, p_type, p_size
    Gather Merge                  (cost=187932.07..331176.12 rows=1196346) actual  619.031..1094.029 rows=1186602
      Workers Planned: 4   Workers Launched: 4
      Sort                        (cost=186932.01..187679.72 rows=299086)  actual  614.107..714.856 rows=237320.40 loops=5
        Sort Key: p_brand, p_type, p_size, ps_suppkey                      external merge Disk: 12136kB
        Parallel Hash Anti Join   (cost=2991.80..151550.34 rows=299086)    actual    7.680..264.664 rows=237320.40 loops=5
          Hash Cond: (ps_suppkey = s_suppkey)   Inner Unique: true
          Nested Loop             (cost=0.43..144782.90 rows=299116)       actual    0.069..236.588 rows=237459.20 loops=5
            Parallel Seq Scan on part                                      actual    0.017..87.663  rows=59364.80 loops=5
              Filter: p_brand <> 'Brand#45' AND p_type !~~ 'MEDIUM POLISHED%' AND p_size = ANY ('{49,14,23,45,19,3,36,9}')
              Rows Removed by Filter: 340635
            Index Only Scan using partsupp_pkey on partsupp                actual    0.002..0.002   rows=4.00 loops=296824
              Index Cond: (ps_partkey = p_partkey)   Heap Fetches: 0   Index Searches: 296824
          Parallel Hash           (cost=2991.29..2991.29 rows=6)           actual    7.509..7.509   rows=11.20 loops=5
            Buckets: 1024  Batches: 1  Memory Usage: 168kB
            Parallel Seq Scan on supplier   Filter: s_comment ~~ '%Customer%Complaints%'   Rows Removed by Filter: 19989
Planning Time: 1.468 ms    Execution Time: 1269.591 ms    Buffers: shared hit=935570, temp read=7574 written=7594
```

### 4-c. The join/access skeleton is structurally IDENTICAL — and that is unusual

Node for node, in execution order, the two engines agree on every decision that
this campaign has previously found them disagreeing about:

| decision | CUBRID | PostgreSQL | same? |
|---|---|---|---|
| driving relation | `part`, full scan | `part`, Parallel Seq Scan | **yes** |
| `part` predicate placement | all three sargs pushed into the scan | all three in one `Filter` | **yes** |
| join method | `idx-join` (index nested loop) | `Nested Loop` | **yes** |
| inner access | `iscan pk_partsupp_ps_partkey_ps_suppkey`, **covering** | `Index Only Scan using partsupp_pkey`, **Heap Fetches: 0** | **yes** |
| join order | `part` outer, `partsupp` inner | `part` outer, `partsupp` inner | **yes** |
| `NOT IN` set | materialised once as a distinct list | built once as a shared Parallel Hash | **yes (logically)** |
| aggregation strategy | sort-based (`hash: false, sort: true`) | `GroupAggregate` (sort-based, not `HashAggregate`) | **yes** |
| final `ORDER BY` | separate `temp(order by)` sort | separate `Sort` | **yes** |
| parallel | 5 scan workers, 3 group-by sort workers | 4 workers + participating leader = 5 units | **yes (5 vs 5)** |

**The single structural difference is the sort key of the grouping sort.**
PostgreSQL sorts on **four** columns — `p_brand, p_type, p_size, ps_suppkey` —
which makes `count(DISTINCT ps_suppkey)` a streaming adjacent-duplicate check.
CUBRID sorts on **three** — `sort: 1 asc, 2 asc, 3 asc` — and therefore has to
deduplicate `ps_suppkey` inside each group separately (sections 7 and 8).

Because the difference is real, `F_plan` is **not** assigned 1.0000 by structural
equality. It is measured.

### 4-d. The `F_plan` anchor — PostgreSQL forced onto CUBRID's aggregation shape

PostgreSQL exposes the exact decision as a GUC. With
`enable_presorted_aggregate=off`, `adjust_group_pathkeys_for_groupagg()` returns
immediately (`planner.c:3516-3517`), `group_pathkeys` is not extended with the
DISTINCT aggregate's pathkey, `aggref->aggpresorted` stays false, and
`nodeAgg.c:4268` sets `pertrans->aggsortrequired = true` — a per-group tuplesort.
That is CUBRID's shape.

The controlled plan differs from the native plan in **exactly one line**:

```text
native:        Sort Key: part.p_brand, part.p_type, part.p_size, partsupp.ps_suppkey
nopresorted:   Sort Key: part.p_brand, part.p_type, part.p_size
```

Every other node, and every printed **cost**, is byte-identical — `Parallel Hash
Anti Join (cost=2991.80..151550.34 rows=299086)`, `Gather Merge
(cost=187932.07..331176.12 rows=1196346)`, `GroupAggregate
(cost=187932.07..344681.44 rows=154186)`, `Sort (cost=362713.89..363099.36)` — so
the A/B isolates the DISTINCT-aggregate strategy and nothing else.

| | native (presorted DISTINCT) | controlled (per-group tuplesort) |
|---|---|---|
| headline median | 1.196902 s | **1.112363 s** |
| sort key width | 4 columns | 3 columns |
| worker sort spill | `external merge Disk: 12136 kB` | `external merge Disk: 12040 kB` |
| worker sort completes at | 714.856 ms | 607.108 ms |
| `GroupAggregate` window | 619.064 → 1233.393 ms | 544.612 → 1163.132 ms |
| `Execution Time` | 1269.591 ms | 1196.951 ms (EXPLAIN ANALYZE) |
| U | 3.06804 | 2.81489 |
| CPU/statement | 3.6721 core-s | 3.1312 core-s |
| serial-ish time/statement (<1.5 units) | 0.147 s | 0.291 s |
| parallel time/statement | 1.052 s at 3.390 units | 0.818 s at 3.422 units |

**`F_plan = 1.112363 / 1.196902 = 0.929368x`.** The narrower sort saves more in the
parallel phase (1.052 → 0.818 s) than the per-group tuplesort costs in the serial
phase (0.147 → 0.291 s), and the net is 7.06% in CUBRID's shape's favour.

This is a genuine finding about **PostgreSQL**, recorded here because the campaign
measures both engines with the same instrument: on Q16, PostgreSQL's own
presorted-aggregate optimization is a **net loss of 7.06%**, because
`adjust_group_pathkeys_for_groupagg()` extends the sort key without costing the
extra sort column against the per-group tuplesort it avoids. It is not an
improvement candidate for this campaign (the campaign's subject is CUBRID) but it
is the reason `F_plan` is below 1.0, so it is stated explicitly rather than folded
into a residual.

### 4-e. CUBRID's estimated cardinalities — a 39.24x error that changed nothing

| node | CUBRID estimate | ground truth | error |
|---|---|---|---|
| `part` after all three sargs | **7,564** | 296,824 | **39.24x under** |
| `idx-join` output | 18,944 | 1,186,602 | 62.64x under |
| `temp(group by)` output | 18,944 | 27,840 | 1.47x under |
| `supplier` after `s_comment LIKE` | 10 | 56 | 5.60x under |

The dominant term is `p_type not like 'MEDIUM POLISHED%'` at estimated selectivity
**0.0263974** against a true 0.966561 — a 36.61x error that section 8-b shows is
*pattern-independent*, and which is registered as **IMP-022**. The `supplier`
under-estimate is the leading-wildcard arm of the same estimator and is registered
against the existing **IMP-003**.

**Neither error cost Q16 any wall time.** CUBRID selected the same skeleton
PostgreSQL did (4-c), `F_plan` is anchored on PostgreSQL's switch, and no factor in
the card is attributed to cardinality error. This is stated in the card, in the
registry and here so the 39.24x is not later mistaken for a measured effect.

## 5. Execution telemetry

### 5-a. Units, utilization and TWU

Sampled per TID on the collector CPUs (20–23) with actual sample-timestamp-delta
weighting — never a nominal interval — over the identical §12 four-statement block
the headline is defined on, three runs per configuration; the median-`U` run is
reported.

| configuration | U (core-s/wall-s) | TWU | peak simultaneous | serial tail (last stmt) | executor CPU | auxiliary CPU | total CPU (block) |
|---|---|---|---|---|---|---|---|
| CUBRID native | **3.28929** | 3.2399 | 5.2129 | 1.125 s | 37.400 | 0.190 | 37.590 core-s |
| CUBRID `NO_PARALLEL_SCAN` | 1.04975 | 1.0545 | 2.9839 | 1.015 s | 32.090 | 0.280 | 32.370 core-s |
| PostgreSQL native | 3.06804 | 3.0978 | 5.1941 | 0.117 s | 14.830 | 0.030 | 14.860 core-s |
| PostgreSQL `nopresorted` | **2.81489** | 2.8594 | 5.2090 | 0.115 s | 12.650 | 0.030 | 12.680 core-s |
| PostgreSQL `noparallel` | 0.99162 | 0.9959 | 1.1335 | 16.498 s | 16.400 | 0.030 | 16.430 core-s |

TWU agrees with `U` to within −1.50% (CUBRID) and +1.57% (PostgreSQL-controlled),
which is the independent confirmation §16 requires; neither a configured cap nor a
nominal interval was substituted anywhere.

**Planned / launched / maximum-simultaneous / time-weighted, per §15:**

| | CUBRID | PostgreSQL |
|---|---|---|
| planned units | not a plan-time property in CUBRID; degree is chosen at execution | `Workers Planned: 4` (+ leader) |
| launched units | trace `parallel workers: 5` (scan) and `parallel workers: 3` (group-by sort) | `Workers Launched: 4`, leader participating = 5 |
| maximum simultaneous active units | 5.2129 | 5.1941 |
| time-weighted active units | 3.2399 | 3.0978 |
| serial tail | 1.125 s | 0.117 s |

The **peak** is essentially identical (5.21 vs 5.19). The **time-weighted** value
is where they part, and section 8-c shows exactly why.

### 5-b. Three telemetry runs per engine

| run | CUBRID U | CUBRID TWU | CUBRID CPU | PostgreSQL U | PostgreSQL TWU | PostgreSQL CPU |
|---|---|---|---|---|---|---|
| 1 | 3.28733 | 3.2488 | 37.400 | 3.07723 | 3.1075 | 14.890 |
| 2 | **3.28929** | 3.2399 | 37.590 | 3.03747 | 3.0722 | 14.730 |
| 3 | 3.30632 | 3.2697 | 37.940 | **3.06804** | 3.0978 | 14.860 |
| spread of U | 0.58% | | | 1.31% | | |

Every telemetry block ran under its own WARM proof and its own load gate; all six
verdicts `CLEAN`.

### 5-c. CPU attribution to the contract regime

| bucket | CUBRID (core-s/block) | PostgreSQL (core-s/block) |
|---|---|---|
| `executor:cub_server:parallel-query` | 33.64 | — |
| `executor:cub_server:transaction` + `connections` | 3.76 | — |
| `executor:pg_parallel_worker:postgres` | — | 10.11 |
| `executor:pg_backend:postgres` | — | 4.72 |
| **executor total** | **37.40** | **14.83** |
| `auxiliary:client_csql:csql` / `client_psql:psql` | 0.14 | 0.03 |
| `auxiliary:cub_server:{dwb-*,vacuum-master,pgbuf-*}` / `postmaster` | 0.05 | 0.00 |
| **auxiliary total** | **0.19** | **0.03** |
| **total_query_cpu** | **37.59** | **14.86** |
| unattributed_background | none observed above the sampler's resolution | none |

PostgreSQL's `io worker` processes are classified as **auxiliary**, never executor,
per the §24 prevention rule; on Q16 they consumed no measurable CPU because there
were zero physical reads. Client formatting/transfer CPU (`csql`/`psql`) is
auxiliary and is never attributed to executor CPU, but **is** included in
`total_query_cpu`, which is the quantity the causal card uses.

### 5-d. Physical reads and buffer behaviour

Covered in full in section 3-b (WARM proof). The load-bearing facts for the card:
**both engines took zero physical reads**, so none of Q16's 3.031730x `F_cost` is
I/O, and none of IMP-002 / IMP-007 / IMP-018 (the campaign's buffer-retention
candidates) fires on this query. PostgreSQL's larger `rchar` is temp-sort spill,
which is *its* cost, not CUBRID's.

### 5-e. CUBRID trace — where the time is

```text
SELECT (time: 3069, fetch: 1220055, fetch_time: 140, ioread: 0)
  SCAN (table: dba.part), (heap time: 1581, fetch: 8, ioread: 0)
       (parallel workers: 5, heap time: 1566..1580, readrows: 399448..401913, gather: mergeable list)
    SCAN (index: dba.partsupp.pk_partsupp_ps_partkey_ps_suppkey),
       (btree time: 1188, fetch: 899139, ioread: 0,
        readkeys: 1484120, filteredkeys: 1186602, rows: 1186602, covered: true)
  GROUPBY (time: 1471, hash: false, sort: true, page: 128, ioread: 0, rows: 27840)
          (parallel workers: 3, time: 291..306, page: 6846..7174, ioread: 0..0)
  ORDERBY (time: 17, sort: true, page: 333, ioread: 0)
  SUBQUERY (uncorrelated)
    SELECT (time: 127, fetch: 6410, fetch_time: 2, ioread: 0)
      SCAN (table: dba.supplier), (heap time: 127, readrows: 500000, rows: 280)
```

Three readings, each cross-checked against the ground truth and against the
`NO_PARALLEL_SCAN` trace of the same query:

1. **`readkeys: 1484120` decomposes exactly**: 1,187,296 matched `partsupp` rows
   + 296,824 index searches = 1,484,120. So CUBRID performs exactly 296,824
   searches — identical to PostgreSQL's `Index Searches: 296824` — and
   `filteredkeys: 1186602` is exactly the ground-truth `ps_after_antijoin`. The
   `part` sargs *are* applied before the probe, despite the parallel node
   reporting `rows == readrows` (a per-worker trace-counter artifact; the serial
   run reports the correct `rows: 296824`).
2. **`GROUPBY time: 1471` against `parallel workers: 3, time: 291..306`.** Only
   ~300 ms of the 1,471 ms group-by is inside the sort workers. The remaining
   **~1,170 ms is the post-sort scan/finalize loop**, and it matches the
   independently measured 1.041 s sub-1.5-unit phase (section 8-c). The GROUPBY
   temp footprint is 3 × ~7,000 pages ≈ 336 MiB, with `ioread: 0`.
3. **`SCAN supplier readrows: 500000` on a 100,000-row table.** The uncorrelated
   `NOT IN` subquery is materialised **once per parallel scan worker** — exactly
   5× — which the `NO_PARALLEL_SCAN` trace confirms by reporting `readrows:
   100000, rows: 56`. 400,000 redundant rows and 400,000 redundant
   leading-wildcard `LIKE` evaluations per statement. This is recorded against
   IMP-009; its wall effect is near zero (the copies run concurrently) and its
   CPU effect is ~0.49 core-s of 9.4929 (5.2%).

## 6. Profile

`perf` is non-headline. Both windows are 90 s, `perf stat` and `perf record
-F 999 -g --call-graph dwarf` on **verified PID sets**, never an all-CPU profile.
PostgreSQL's `perf stat` was attached to the postmaster *before* the driver
connection existed so inherit-on-fork covers the leader and every statement's
workers; CUBRID's every query worker thread lives inside the single `cub_server`
process (30 TIDs). Resolved-sample coverage: **0 unknown-symbol lines** on both
sides (1,630 / 1,506 flat lines), 0 lost samples, 290,733 / 299,765 samples.

### 6-a. `perf stat` over the window

| | CUBRID | PostgreSQL |
|---|---|---|
| cycles | 818,353,024,340 | 836,233,786,097 |
| instructions | 2,013,361,898,619 | 2,028,566,257,549 |
| IPC | 2.46 | 2.43 |
| task-clock | 292,507.89 ms | 297,048.05 ms |
| CPUs utilized | 3.250 | 3.300 |
| statements completed in the window | 31.19 | 75.19 |
| **instructions per statement** | **64.562e9** | **26.978e9** |
| cycles per statement | 26.242e9 | 11.121e9 |
| task-clock per statement | 9.3798 core-s | 3.9504 core-s |

**Two engines burning the same instructions and the same cycles per second — and
one of them finishes 2.41x more queries with them.** The per-statement instruction
ratio is **2.3932x** and the per-statement task-clock ratio **2.3744x**, against
`F_cpu` 2.585109x on the *native* pair. The 7.4% spread is expected and is
explained, not hand-waved: the perf statement count is derived from the 90 s window
divided by the headline median, so it charges CUBRID and PostgreSQL for the
inter-statement client turnaround that the telemetry `t_block` denominator
excludes; `perf record` also adds its own overhead to the second window. Both are
independent corroborations of `F_cpu`'s direction and magnitude, not substitutes
for it.

### 6-b. CUBRID top symbols (≥0.5% self)

| self % | symbol | band |
|---|---|---|
| 5.94 | `tp_value_compare_with_error` | D predicate |
| 5.09 | `eval_some_list_eval` | B `NOT IN` membership |
| 4.29 | `lang_fastcmp_byte` | I collation compare |
| 3.98 | `eval_value_rel_cmp` | D predicate |
| 3.87 | `eval_pred` | D predicate |
| 3.78 | `qfile_scan_list_next` | A list-file/sort |
| 3.32 | `lang_strmatch_utf8` | C LIKE |
| 3.09 | `qstr_eval_like` | C LIKE |
| 2.63 | `pr_clear_value` | E materialisation |
| 2.34 | `__memmove_evex_unaligned_erms` | H libc |
| 2.27 | `qfile_update_qlist_count` | A list-file/sort |
| 1.86 | `heap_attrinfo_read_dbvalues` | E materialisation |
| 1.80 | `qfile_retrieve_tuple` | A |
| 1.60 | `qfile_compare_partial_sort_record` | A |
| 1.59 / 1.19 / 0.95 | `lf_freelist_claim` / `lf_freelist_retire` / `lf_stack_pop` | A (per-group file churn) |
| 1.56 | `pr_midxkey_compare` | A |
| 1.46 | `qfile_locate_tuple_value_r` | A |
| 1.45 + 1.00 | `pgbuf_fix_release` (parallel-query + transaction) | G buffer |
| 1.26 | `mr_data_readval_int` | E |
| 1.03 | `qdata_generate_tuple_desc_for_valptr_list` | A |
| 0.97 / 0.86 / 0.57 | `btree_search_leaf_page` / `btree_search_nonleaf_page` / `btree_compare_key` | F index |
| 0.75 / 0.64 | `intl_utf8_to_cp` / `intl_nextchar_utf8` | C LIKE |

### 6-c. PostgreSQL top symbols (≥0.5% self)

| self % | symbol | band |
|---|---|---|
| 17.42 | `nocachegetattr` | A sort |
| 10.09 | `comparetup_heap_tiebreak` | A sort |
| 5.52 | `__memcmp_evex_movbe` | A sort |
| 4.08 | `bpchartruelen` | A sort |
| 3.91 | `bpcharfastcmp_c` | A sort |
| 3.34 | `ExecInterpExpr` | D predicate |
| 3.22 | `varstrfastcmp_c` | A sort |
| 3.06 | `tts_buffer_heap_getsomeattrs` | E materialisation |
| 2.59 | `_bt_compare` | F index |
| 2.50 | `heap_compare_slots` | A sort (Gather Merge) |
| 2.03 | `ExecEvalScalarArrayOp` | D predicate |
| 1.75 | `LWLockAttemptLock` | G buffer |
| 1.67 | `pg_detoast_datum_packed` | A sort |
| 1.60 | `qsort_tuple` | A sort |
| 1.54 | `heap_fill_tuple` | A sort |
| 1.12 | `tts_minimal_getsomeattrs` | A sort |
| 1.08 | `PinBuffer` | G buffer |
| 0.97 | `shm_mq_send_bytes` | H gather IPC |
| 0.72 | `UTF8_MatchText` | C LIKE |

### 6-d. Bands, in absolute core-seconds per statement

Self-% summed per band and converted with each engine's own total-query CPU per
measured statement (CUBRID 9.4929, PostgreSQL-native 3.67115 core-s).
`q16-bands.txt` / `Q16-bands.json`.

| band | CUBRID % | CUBRID core-s | PostgreSQL % | PostgreSQL core-s | ratio |
|---|---|---|---|---|---|
| A sort / group-by / DISTINCT list-file | 28.09 | **2.6666** | 57.30 | **2.1036** | **1.268x** |
| B anti-join membership | 5.09 | 0.4832 | 1.89 | 0.0694 | 6.96x |
| C LIKE matcher | 8.64 | 0.8202 | 0.72 | 0.0264 | **31.07x** |
| D predicate evaluation | 16.75 | 1.5901 | 7.34 | 0.2695 | **5.90x** |
| E row materialisation | 12.44 | 1.1809 | 4.77 | 0.1751 | **6.74x** |
| F index scan (B-tree) | 5.62 | 0.5335 | 5.93 | 0.2177 | 2.45x |
| G buffer pool | 3.72 | 0.3531 | 5.23 | 0.1920 | 1.84x |
| H libc memory / gather IPC | 3.40 | 0.3228 | 2.48 | 0.0910 | — (not comparable) |
| I collation compare / kernel page cache | 4.95 | 0.4699 | 3.12 | 0.1145 | — (not comparable) |
| unclassified | 5.78 | 0.5487 | 7.12 | 0.2614 | |

**The most important row is the first one.** The sort/group-by/DISTINCT band is
**57.30% of PostgreSQL's entire profile and only 28.09% of CUBRID's** — yet in
absolute core-seconds they are within 1.268x of each other. PostgreSQL spends most
of a small budget on the work Q16 actually is; CUBRID spends a minority of a large
budget on it, and the majority on per-row machinery around it. That is the shape of
a `F_cost` query, and it is why Q16's improvements are ranked the way section 9
ranks them.

The 31.07x LIKE band deserves its own normalisation, because the evaluation counts
differ: CUBRID evaluates `LIKE` 2,500,000 times per statement (2,000,000 `p_type`
+ 500,000 `s_comment`, the latter 5× inflated by section 5-e), PostgreSQL
2,100,000 times. Per evaluation that is **328 ns against 12.6 ns — 26.10x**.

## 7. Source contrast

| Item | CUBRID `file:line` | PostgreSQL `file:line` | Difference | Class |
|---|---|---|---|---|
| `count(DISTINCT x)` per-group state | `src/query/query_aggregate.cpp:162-173` — `qdata_initialize_aggregate_list()` calls `qdata_process_distinct_or_sort()` for every group; `:70-115` — that function `db_private_alloc`s a type list and `qfile_open_list(..., QFILE_FLAG_DISTINCT, ...)` at `:98`, then `qfile_close_list`/`qfile_destroy_list` the previous group's file at `:108-109`. **27,840 temp list files per Q16 statement.** | `src/backend/executor/nodeAgg.c:587-622` — `initialize_aggregate()` creates a per-group `tuplesort_begin_datum()` **only** `if (pertrans->aggsortrequired)`; `:4257-4268` clears `aggsortrequired` when `aggref->aggpresorted`. In the presorted case **no per-group state is allocated at all**, and in the non-presorted case it is an in-memory tuplesort with a `work_mem` budget, never a file. | structural absence (CUBRID has no in-memory or presorted path) | structural absence |
| `count(DISTINCT x)` per-row cost | `src/query/query_aggregate.cpp:810-867` — the comment at `:810-814` states the design; then `:840` `pr_data_writeval_disk_size()`, `:841` `db_private_alloc()`, `:844` `pr_type_p->data_writeval()`, `:859` `qfile_add_item_to_list()`, `:861/:866` `db_private_free_and_init()`, `:867` `pr_clear_value_vector()`. **One malloc + disk-format serialize + file append + free per operand row; 1,186,602 per statement.** | `src/backend/executor/execExprInterp.c:5792` — `ExecEvalPreOrderedDistinctSingle()`: **one** `FunctionCall2Coll(&pertrans->equalfnOne, ..., pertrans->lastdatum, value)`. Compiled in as `EEOP_AGG_PRESORTED_DISTINCT_SINGLE` (`execExpr.c:3916`, dispatched at `execExprInterp.c:2238`), so it is one step of the already-running expression program. Non-presorted fallback: `nodeAgg.c:891-902`, a streaming "not distinct from prior" skip inside `process_ordered_aggregate_single()`. | same stage, lower measured cost — and one side has no allocation at all | structural absence |
| `count(DISTINCT x)` finalize | `src/query/query_aggregate.cpp:1388-1431` — `:1403` `qfile_sort_list(agg_p->list_id, ..., Q_DISTINCT, false)` → `SORT_ELIM_DUP` (`src/query/list_file.c:4722`, flag at `:4801`), then `:1428-1431` `db_make_bigint(..., list_id_p->tuple_cnt)`. **A full external-sort entry point invoked 27,840 times per statement purely to obtain a count.** | `src/backend/executor/nodeAgg.c:1314-1342` — `finalize_aggregates()` skips `process_ordered_aggregate_single()` entirely when presorted and takes the `:1328-1342` branch, which only releases the cached last datum. | structural absence | structural absence |
| Where the DISTINCT work runs | `src/query/query_executor.c:4784` (and `:4597`) — `qdata_evaluate_aggregate_list()` is called from the **post-sort** scan of the sorted list; the parallel phase ended with the sort. Measured: 1.041 s/statement below 1.5 active units. | `src/backend/optimizer/plan/planner.c:8019` `gather_grouping_paths()` — the sort is placed **below** `create_gather_merge_path()`, so the leader's aggregate loop overlaps the workers. Measured: 0.291 s/statement (controlled leg), 0.147 s (native). | same stage, lower measured cost | same stage, lower measured cost |
| Planner support for a presorted DISTINCT | **absent.** `qexec_groupby`'s SORT_LIST is built from the GROUP BY columns only (`sort: 1 asc, 2 asc, 3 asc` in `q16-plan-est-cubrid.out`). Searched `src/optimizer/` and `src/query/` for `presort`, `aggpresorted`, `agg_sorted`, `distinct.*sort_list` extension and for any cost term comparing "wider sort" against "per-group dedup": no such concept exists. `agg_p->sort_list` (`query_aggregate.cpp:1392-1399`) is the *aggregate's own* ORDER BY, not the group-by sort. | `src/backend/optimizer/plan/planner.c:3501` `adjust_group_pathkeys_for_groupagg()`, call site `:3809`, GUC gate `:3516-3517`, and the `aggpresorted` flag it sets. | structural absence | structural absence |
| Anchored `NOT LIKE` selectivity | `src/optimizer/histogram/histogram_cl.cpp:1311-1329` — skips the fixed literal prefix, with the in-code justification *"The fixed prefix before it is assumed to be already handled by a range predicate"*; `:1334-1337` returns **1.0** for a pattern with no wildcard at all; `src/optimizer/query_planner.c:9939-9943` — `PT_NOT_LIKE` = `1 - qo_like_selectivity()`, and **no NOT-LIKE → range rewrite exists anywhere**, so the assumption is false on exactly this branch. | `src/backend/utils/adt/like_support.c` `patternsel()` / `prefix_selectivity()` — PostgreSQL has the same prefix/range concept but **multiplies the prefix range selectivity into** the estimate instead of dropping it, and does so for the negated form too; `src/backend/utils/adt/selfuncs.c:807,898,1032,1042` apply the real operator to real MCV/histogram values. | structural absence (of the prefix term on the negated branch) | structural absence |
| Leading-wildcard `LIKE` selectivity | `src/optimizer/histogram/histogram_cl.cpp:1487-1501` — non-MCV estimate is the fraction of matching bucket **upper boundaries**; `:1529-1532` clamps to 0.0001. Q16: `s_comment like '%Customer%Complaints%'` → sel 0.0001, card 10 vs true 56. | `src/backend/utils/adt/selfuncs.c:807 mcv_selectivity()` and `:898 histogram_selectivity()`. PostgreSQL estimates `rows=6` per worker (~30) vs the same true 56. | same stage, lower measured cost (1.9x vs 5.6x error) | same stage, lower measured cost |
| Uncorrelated `NOT IN` set construction | trace-level: each parallel scan worker materialises the subquery independently (`readrows: 500000` at 5 workers vs `100000` serial). CUBRID evaluates membership per row via `eval_some_list_eval` (5.09% self) → `tp_value_compare_with_error` — a value-comparison walk of the materialised list. | `src/backend/executor/nodeHash.c` / `nodeHashjoin.c` — `Parallel Hash` built **once, cooperatively** across workers (`rows=11.20 loops=5`, `Buckets: 1024 Batches: 1 Memory Usage: 168kB`) and probed as a hash anti-join (`hash_search_with_hash_value` + `hash_bytes` = 1.89% self). | structural absence (no shared build; no hash probe) | structural absence |
| Per-row scan value materialisation | `src/storage/heap_file.c:10464 heap_attrinfo_read_dbvalues()` (1.86%), `src/object/object_primitive.c mr_data_readval_int()` (1.26%), `src/storage/page_buffer.c` `spage_get_record()` (0.96%), teardown `pr_clear_value()` (2.63%). | `src/backend/executor/execTuples.c:751 tts_buffer_heap_getsomeattrs()` (3.06%) → `:1017 slot_deform_heap_tuple()`; **no teardown symbol exists** — a deformed slot is a flat Datum/isnull array. | same stage, lower measured cost | same stage, lower measured cost |
| Sarg comparison dispatch | `src/query/query_evaluator.c:1666 eval_pred()` (3.87%) → `:2150 eval_pred_comp0()` → `:152 eval_value_rel_cmp()` (3.98%) → `src/object/object_domain.c:10404 tp_value_compare_with_error()` (5.94%), re-dispatched per row and per value. The 8-element `p_size IN` list is eight such walks. | `src/backend/executor/execExpr.c:229 ExecInitQual()` compiles the qual once; `src/backend/executor/execExprInterp.c` `EEOP_SCAN_VAR` / `EEOP_QUAL` / `ExecEvalScalarArrayOp` (2.03%) — the whole `IN` list is **one** specialised opcode. | same stage, lower measured cost | same stage, lower measured cost |
| UTF-8 `LIKE` matcher | `src/base/language_support.c:2831 lang_strmatch_utf8()` (3.32%) with `:2857-2858` `intl_utf8_to_cp()` on **both** operands per character (0.75% + 0.64% visible separately); driver `src/query/string_opfunc.c:5906 qstr_eval_like()` (3.09%). | `src/backend/utils/adt/like.c:132 #define MatchText UTF8_MatchText` (0.72%), `src/backend/utils/adt/like_match.c:84 MatchText()` — byte-by-byte even for multi-byte encodings; `like.c:129-131` advances by raw continuation bytes with no decode. | same stage, lower measured cost (26.10x per evaluation) | same stage, lower measured cost |

**Absence claims, with what was searched.** For "CUBRID has no presorted-DISTINCT
concept" the searched paths were `src/optimizer/` and `src/query/` in the pinned
SHA `607f1ee9`, symbols/patterns `presort`, `aggpresorted`, `agg_sorted`,
`groupby_skip`, `sort_list`, `Q_DISTINCT`, `qdata_process_distinct_or_sort`, and
every call site of `qfile_sort_list`; the only DISTINCT-aggregate early-out found
is the `MIN`/`MAX` special case at `query_aggregate.cpp:76-81`. For "no
`NOT LIKE` → range rewrite" the searched paths were `src/optimizer/query_graph.c`,
`src/optimizer/query_planner.c` and `src/parser/`, patterns `PT_NOT_LIKE`,
`LIKE_LOWER_BOUND`, `LIKE_UPPER_BOUND`, `pt_expand_like`; `PT_LIKE_LOWER_BOUND` /
`PT_LIKE_UPPER_BOUND` appear only on the positive branch
(`query_graph.c:3332-3333`, `:3913-3914`), and the observed plan output confirms
it — the positive form prints as a range, the negated form does not.

## 8. Causal decomposition details

### 8-a. `F_plan` reproduced from the plan text, not asserted

Section 4-d gives the A/B. What makes it an *anchor* rather than a correlation is
that the two PostgreSQL plans differ in exactly one printed line and in no printed
cost, and that the direction of every sub-measurement follows the mechanism:

| quantity | native | controlled | Δ | mechanism |
|---|---|---|---|---|
| worker sort spill | 12,136 kB | 12,040 kB | −0.8% | one fewer sort column in each tuple |
| worker sort completes | 714.856 ms | 607.108 ms | −15.1% | narrower comparison key |
| parallel-phase time/statement | 1.052 s | 0.818 s | **−22.2%** | the saving |
| serial-ish time/statement | 0.147 s | 0.291 s | **+98.0%** | the cost: 27,840 per-group tuplesorts |
| CPU/statement | 3.6721 | 3.1312 core-s | −14.7% | net |
| wall | 1.196902 s | 1.112363 s | **−7.06%** | net |

The saving and the cost are both present, both in the predicted direction, and the
net is `F_plan`. Nothing here is inferred from a cost estimate.

### 8-b. The 36.61x selectivity error, reproduced arithmetically from source constants

Ten non-executing plan dumps against exact `count(*)` on both engines
(`q16-like-probe-cubrid.out`, `q16-like-probe2-cubrid.out`,
`q16-like-groundtruth-*.out`):

| pattern | CUBRID est. sel | est. card | true card | error |
|---|---|---|---|---|
| `not like 'MEDIUM POLISHED%'` | 0.0263974 | 52,795 | 1,933,121 | **36.61x under** |
| `not like 'ZZZZZ%'` | **0.0263974** | 52,795 | 2,000,000 | 37.88x under |
| `not like 'MEDIUM%'` | **0.0263974** | 52,795 | 1,666,123 | 31.56x under |
| `not like 'M%'` | **0.0263974** | 52,795 | 1,666,123 | 31.56x under |
| `not like 'MEDIUM POLISHED'` | **0.0263974** | 52,795 | 1,933,121 | 36.61x under |
| `not like 'M'` | **0.0263974** | 52,795 | 1,933,121 | 36.61x under |
| `not like 'MEDIUM POLISHED_'` | 0.12367 | 247,340 | 1,933,121 | 7.82x under |
| `not like '%MEDIUM POLISHED%'` | 0.999903 | 1,999,805 | 1,933,121 | 1.03x **over** |
| `not like '%M'` | 0.80526 | 1,610,520 | 1,933,121 | 1.20x under |
| `like 'MEDIUM POLISHED%'` | 0 (rewritten to a range) | 1 | 66,879 | 66,879x under |

**Six anchored patterns whose true selectivities span 0.833 to 1.000 receive the
byte-identical estimate 0.0263974, including `'ZZZZZ%'`, a prefix no row has.**
That is the finding: the estimate is pattern-independent, so it is not a data
problem.

The mechanism reproduces to 7 significant digits. Write
`S = matched_mcv_freq + nonmcv_mass × total_non_mcv_sel`, divided by `1 − nullfrac`
(`histogram_cl.cpp:1545-1553`). On `part.p_type` the non-MCV mass factor is
**0.9737** and the MCV mass **0.0263**, both read off the two patterns that match
every value (`LIKE '%'` and `LIKE '_%'` both give 0.99990263 = 0.0263 + 0.9737 ×
0.9999). Then:

| pattern | `pattern_heuristic_selectivity` after the prefix skip | `total_non_mcv_sel` | `S` | printed `NOT LIKE` |
|---|---|---|---|---|
| `'MEDIUM POLISHED%'` | remainder `'%'` → 5.0, clamped to 1.0 (`:1351,:1362-1365`) | 0.9999 (upper clamp `:1533-1536`) | 0.9737 × 0.9999 = 0.97360263 | 1 − 0.97360263 = **0.02639737** ✓ |
| `'MEDIUM POLISHED'` | no wildcard → **return 1.0** (`:1334-1337`) | 0.9999 | 0.97360263 | **0.0263974** ✓ |
| `'MEDIUM POLISHED_'` | remainder `'_'` → `ANY_CHAR_SEL` 0.90 | 0.90 | 0.9737 × 0.90 = 0.876330 | **0.123670** ✓ |
| `'%M'` | no fixed prefix: `'%'`→1.0 then `'M'`→`FIXED_CHAR_SEL` 0.20 | 0.20 | 0.9737 × 0.20 = 0.194740 | **0.805260** ✓ |
| `'%MEDIUM POLISHED%'` | 1.0 × 0.20¹⁵ × 5 = 1.6384e-10 | 0.0001 (lower clamp `:1529-1532`) | 9.737e-05 | **0.999903** ✓ |

All five reconstructions are exact against the printed values. The defect is
`histogram_cl.cpp:1311-1329`, which skips the anchored literal prefix on the
documented assumption that a range predicate covers it — true for `PT_LIKE`
(`q16-like-probe-cubrid.out` shows it rewritten to `p_type range ('MEDIUM
POLISHED' ge_lt 'MEDIUM POLISHEE')`), false for `PT_NOT_LIKE`
(`query_planner.c:9939-9943`), which has no such rewrite. Registered as
**IMP-022**.

**And it cost Q16 nothing.** The 39.24x conjunct error did not change the plan.
This is stated in the card and again here so it is never later read as an effect.

### 8-c. Where the 1.689 s actually goes

The interval series behind `U` and TWU is bucketed at the 1.5-active-unit
threshold, using actual sample timestamp deltas
(`Q16-*-headline-telemetry-intervals-*.json`), and divided by the four statements
of each block:

| configuration | serial-ish (<1.5 units) per statement | parallel per statement | mean units when parallel |
|---|---|---|---|
| CUBRID native | **1.041 s (35.9% of the busy window)** | 1.856 s | 4.498 |
| PostgreSQL `nopresorted` (controlled leg) | **0.291 s (26.2%)** | 0.818 s | 3.422 |
| PostgreSQL native | 0.147 s (12.2%) | 1.052 s | 3.390 |

Against the **plan-controlled** PostgreSQL leg — same aggregation shape, same
27,840 per-group dedups, same 1,186,602 rows:

- **serial phase 1.041 s vs 0.291 s = 3.5773x**
- **parallel phase 1.856 s vs 0.818 s = 2.2689x**

Both phases are slower; the serial one by 1.577x more. The serial differential
alone, 1.041 − 0.291 = **0.750 s**, is **44.4% of Q16's entire 1.689 s gap**.

The CUBRID trace localises the same time independently: `GROUPBY (time: 1471 ...
parallel workers: 3, time: 291..306)` — only ~300 ms of the 1,471 ms group-by is
inside the sort workers, leaving **~1,170 ms** in the post-sort scan/finalize loop,
which is where `qdata_evaluate_aggregate_list()` serializes 1,186,602 operands into
per-group list files and `qdata_finalize_aggregate_list()` sorts 27,840 of them
with duplicate elimination. Two independent instruments, 1.041 s and ~1.17 s, on
the same phase. Registered as **IMP-023**.

### 8-d. Explanations considered and REJECTED, with the number that rejected them

1. **"CUBRID's `count(DISTINCT)` plan shape is wrong."** Rejected by the other
   engine's own switch: forced into CUBRID's shape, PostgreSQL is **1.075998x
   faster** (1.112363 s vs 1.196902 s). `F_plan` = 0.929368x. The shape is fine;
   the implementation of the shape is not.
2. **"CUBRID's parallelism is worse."** Rejected by `F_units` 0.855774x — CUBRID
   runs at **more** active units (U 3.28929 vs 2.81489 controlled, 3.06804 native)
   with a nearly identical peak (5.2129 vs 5.1941) — and by CUBRID's own
   `NO_PARALLEL_SCAN` A/B: 2.6646x speedup for a 17.60% CPU surcharge, 81.0%
   efficiency against U.
3. **"The group-by sort refuses to parallelise" (IMP-015).** Rejected by the
   trace: `GROUPBY ... (parallel workers: 3)` in **both** the native and the
   `NO_PARALLEL_SCAN` run. `sort_check_parallelism()` admitted it. Q16's serial
   phase is the *post-sort* loop, a different code path.
4. **"Hash aggregation was abandoned" (IMP-016 / IMP-017).** Rejected by both
   engines agreeing: CUBRID's plan is `hash: false, sort: true`, and PostgreSQL
   independently costs `GroupAggregate` below `HashAggregate` on the same query.
   Neither engine chose hashing, so neither abandoned it.
5. **"CUBRID is short of buffer memory / re-reading pages" (IMP-002 / IMP-007 /
   IMP-018).** Rejected by 0 physical reads: `/proc/<cub_server>/io` moves 14,912
   bytes of `rchar`, 0 `read_bytes` and 4,096 `write_bytes` across a whole
   four-statement block. Q16's entire working set is resident.
6. **"The cardinality error picked the wrong plan" (IMP-003 / IMP-014 class).**
   Rejected by the plan text: despite a 39.24x under-estimate on the `part`
   conjunct, CUBRID's skeleton is node-for-node the one PostgreSQL chose (4-c).
   The error is real (8-b) and is registered as IMP-022, with **zero** Q16 wall
   time attributed to it.
7. **"The 5× subquery re-execution is the cost."** Bounded and rejected as a
   *wall* explanation: 400,000 redundant supplier rows per statement at the serial
   run's 123 ms per 100,000 rows is ~0.49 core-s of 9.4929 (5.2% of CPU), and the
   five copies run **concurrently**, so the wall effect is near zero. It is real
   and is recorded against IMP-009 as a CPU-efficiency item, explicitly not
   double-counted against IMP-023's serial band.
8. **"PostgreSQL wins because it does less I/O."** Rejected by direction:
   PostgreSQL reads **more** from the OS on Q16 (63.8 MB/statement of `rchar` vs
   CUBRID's 3,728 B), because its external-merge sort spills 12 MB per worker.
   Both engines take zero *device* reads.

### 8-e. What the residual is made of, and what it is not

After `F_plan` is anchored away, `F_cpu` 3.031730x on `F_work` exactly 1.000000x
is the whole story, and the bands partition it (6-d). Ranked by absolute CUBRID
core-seconds above PostgreSQL:

| band | CUBRID − PostgreSQL (core-s/statement) | share of the 5.8217 core-s CPU differential |
|---|---|---|
| D predicate evaluation | +1.3206 | 22.7% |
| E row materialisation | +1.0058 | 17.3% |
| C LIKE matcher | +0.7938 | 13.6% |
| A sort / group-by / DISTINCT list-file | +0.5630 | 9.7% |
| B anti-join membership | +0.4138 | 7.1% |
| F index scan | +0.3158 | 5.4% |
| I / H / G / unclassified | +1.4089 | 24.2% |

Band A being only 9.7% of the CPU differential while owning 44.4% of the **wall**
differential is not a contradiction — it is the point. Band A's excess is
concentrated in the phase that runs at ~1 active unit, so each of its core-seconds
buys 1 second of wall, while bands D/E/C are spread across the 4.5-unit parallel
phase where each core-second buys ~0.22 s. **This is why IMP-023 is ranked first
despite not owning the largest CPU band, and it is stated explicitly so the CPU
shares are never read as wall shares.**

## 9. Improvements

Two new candidates (**IMP-022**, **IMP-023**) and measured Q16 evidence on four
existing ones. The Git ledger was synced (`HEAD` = `origin/main` = `1c9c618`) and
searched by title, both source locations and root cause against all 21 existing
candidates before either ID was allocated; `next_id` advanced IMP-022 → IMP-024.

| Rank | ID | New? | Priority | Q16 band / effect | Evidence type |
|---|---|---|---|---|---|
| 1 | **IMP-023** | **new** | P0 | serial-phase differential 0.750 s of the 1.689 s gap (44.4%); band A 2.6666 vs 2.1036 core-s | direct A/B |
| 2 | IMP-008 | — | P0 | band D 1.5901 vs 0.2695 core-s (5.90x) | profile attribution |
| 3 | IMP-020 | — | P0 | band E 1.1809 vs 0.1751 core-s (6.74x) | profile attribution |
| 4 | IMP-004 | — | P1 | band C 0.8202 vs 0.0264 core-s; 328 ns vs 12.6 ns per evaluation (26.10x) | profile attribution |
| 5 | **IMP-022** | **new** | P1 | 36.61x selectivity error, **0.0000x measured wall effect** | direct A/B |
| — | IMP-003 | — | P0 | `s_comment` leading-wildcard: sel 0.0001, card 10 vs true 56 (5.60x); no wall effect | direct A/B |
| — | IMP-009 | — | P0 | uncorrelated subquery materialised 5× (`readrows` 500,000 vs 100,000); ~0.49 core-s (5.2% of CPU), ~0 wall | direct A/B |

**IMP-023 — `count(DISTINCT x)` under sort-based GROUP BY is one temp list file
per group, finalized single-threaded.** Per group: `qfile_open_list(...,
QFILE_FLAG_DISTINCT, ...)` (`query_aggregate.cpp:98`). Per row: a
`pr_data_writeval_disk_size` + `db_private_alloc` + `data_writeval` +
`qfile_add_item_to_list` + free sequence (`:840-866`) — 1,186,602 of them. Per
group boundary: a full `qfile_sort_list(..., Q_DISTINCT, ...)` → `SORT_ELIM_DUP`
purely to read `list_id_p->tuple_cnt` (`:1403`, `:1428-1431`) — 27,840 of them.
And the whole loop runs in the post-sort phase at ~1 active unit
(`query_executor.c:4784`). PostgreSQL's contrasting mechanism is one
`equalfnOne` call against `pertrans->lastdatum`
(`execExprInterp.c:5792`) when presorted, or an in-memory `tuplesort_begin_datum`
inside the pipelined `GroupAggregate` when not (`nodeAgg.c:848-934`) — and its
sort sits **below** the Gather Merge (`planner.c:8019`) so the aggregate loop
overlaps the workers. Direction: (b) use an in-memory dedup below a memory budget
before falling back to a `qfile` — Q16's groups average 42.62 rows; and (c) for
`PT_COUNT` specifically, a counting hash set needs no sort at all. Sub-item (a),
the presorted-input optimization, is **measured to be worth −7.06% on this query**
by the `F_plan` anchor and is explicitly *not* the recommended first fix.
Lower bound 0.750 s, upper bound 1.041 s per statement. Difficulty medium;
correctness risk medium-low (collation-correct comparison and a real memory bound
for the spill threshold). Upstream precedent: PostgreSQL 16's own
`enable_presorted_aggregate` work, and CUBRID's own `MIN`/`MAX` DISTINCT early-out
at `query_aggregate.cpp:76-81`.

**IMP-022 — anchored `NOT LIKE` drops the literal prefix.** Mechanism, measurement
and arithmetic reconstruction in 8-b. Direction: (a) keep the fixed prefix when the
caller is `PT_NOT_LIKE`; (b) better, estimate `PT_NOT_LIKE` as
`1 − (prefix_range_selectivity × heuristic(remainder))` reusing
`qo_range_selectivity()`; (c) `:1334-1337` should return an *equality* selectivity
for a wildcard-free pattern, not 1.0. Difficulty low; correctness risk none to
results (estimates only) but real plan churn, which is the point of the fix.
Effect range on Q16: **zero seconds** — recorded as a latent plan-space defect,
not a Q16 win. Sibling of IMP-003, not a duplicate: different arm of the same
estimator, different operator branch, opposite direction, and Q16 exhibits **both
at once on two different columns**, which is what separates them.

Effects must **not** be summed. Bands A/C/D/E are disjoint self-% partitions of one
profile, but IMP-023's serial-phase differential and its band-A share describe the
same work from two directions and overlap; IMP-004's band contains the 400,000
redundant `LIKE` evaluations that IMP-009 owns; and IMP-022 changes *how often* the
matcher runs on some other query while IMP-004 changes what each run costs.

## 10. Evidence index

`claim → raw file → formula → evidence type → SHA-256`. Raw root
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q16/`; every artifact's size, hash,
creation command and producing stage is in `reports/Q16/raw-manifest.json`.

| Claim | Raw file | Formula | Type | SHA-256 |
|---|---|---|---|---|
| CUBRID headline 2.886000 s | `Q16-cubrid-headline-block1.json` | median of `measured_times_s` | measurement | `a6b6b3f0e06bee69152a93f11aa290e038f9e2e2e8bf4b4dbaa7701dd1341e59` |
| PostgreSQL headline 1.196902 s | `Q16-postgresql-headline-block1.json` | median of `measured_times_s` | measurement | `3da9a24aa29ee4abb49f53f5b91277174173589bdb74305bbb8fba60f4d7850c` |
| `F_plan` 0.929368x | `Q16-postgresql-nopresorted-headline.json` | `1.112363 / 1.196902` | direct A/B | `db5203bbfc2b5b494b2ca89c449eba1c85610479e1fe9d8cd20baed8bfff2381` |
| `F_plan` isolation: one plan line differs | `q16-plan-est-pg-nopresorted.out` vs `q16-plan-est-pg.out` | textual diff of `Sort Key` | direct A/B | `5d9d9b91fc205489374dfcb989b8d19cc2be93c6ac82f47a6ddc48eeb0fc5120` / `68d0740b31f71a1c439fe87e32d2d13b5392c7bb7a8a6f27c38181ab27e69661` |
| `U_C` 3.28929, TWU 3.2399 | `Q16-cubrid-headline-telemetry-run2.json` | `CPU_block / Σ statement walls` | profile attribution | `c1bac6e0aefde9fd9e258bf65103581d07503c85ddcd4c6b8c535193c48bbd4f` |
| `U_P` 3.06804 | `Q16-postgresql-headline-telemetry-run3.json` | same | profile attribution | `148062d9b7da19d9393bc5a25d50e63c1625437bf061ca68d9dd4fd8f5554e09` |
| `U_P'` 2.81489 | `Q16-postgresql-nopresorted-headline-telemetry.json` | same | profile attribution | `065ba44fe1879b803762a40e4e94905b347f24586153b3e568537e339a3db98d` |
| serial phase 1.041 s / 0.291 s | `Q16-cubrid-headline-telemetry-intervals-run2.json`, `Q16-postgresql-nopresorted-headline-telemetry-intervals.json` | Σ `dt` where `units < 1.5`, ÷ 4 statements | direct A/B | `35878ea387c346790e0e7848aae6bfc3923931635c14a4b730b21079da079771` / `2fbb4ebd154967704e3f6ffb4a76f8a4406d7bdfc8fc1d853b724c47761b3565` |
| card, residual 0.000000000000% | `Q16-causal-card.json` | `F_plan × F_units × F_cpu` vs `R_wall` | derived | `29bf933cc844d881c093ec72d94e03b3d2920200e7dc5665683b8d3eaff6502d` |
| profile bands | `q16-bands.txt` | Σ self-% per band × CPU/statement | profile attribution | `a591a02116bc40894079b892acbfc09f2a9a67240b4bc4fcd1f7ed577ef37ef9` |
| CUBRID flat profile, 0 unknown symbols | `profile-cubrid-flat-nocg.txt` | `perf report --no-children -g none` | profile | `f4231cdd3597e15888e10513a7494b5030c3e769a3584c23af197af634b808b6` |
| PostgreSQL flat profile, 0 unknown symbols | `profile-pg-flat-nocg.txt` | same | profile | `092aecf02f515b3aeb36d285b9a5b4c00bff5a678992dd2c621ba99fe25b0a1f` |
| instructions 64.562e9 vs 26.978e9 per statement | `perf-stat-cubrid.txt`, `perf-stat-pg.txt` | window instructions ÷ (90 s ÷ median) | profile | `2f746fee3a6dec35cdc1eab7b62e04df9d0432e3c2e6bc229def705c0cbe6062` / `a6f41528da58265f2aeb50e60c7c78abae0603ab92fe78bb6cb7eba79989d17f` |
| `F_work` 1.000000x (all four counts) | `q16-groundtruth-cubrid.out`, `q16-groundtruth-pg.out` | exact `count(*)`, both engines | direct A/B | `b3f7517eb693933f98f49b2c64165ed57bb6230c62c69eacb2c221f4e3d13183` / `d21c09bfde31bf0c227fc5b8477550a09346453e653e2a82424208387ed57cde` |
| CUBRID plan shape, est. card 7,564 | `q16-plan-est-cubrid.out` | `SET OPTIMIZATION LEVEL 514`, non-executing | plan | `3e8bec7853e264da3c8eba804274b59478ddcc31beba5fd9c15b26f8cc10cbfa` |
| PostgreSQL actual plan, `Index Searches: 296824` | `q16-plan-act-pg.out` | `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, TIMING)` | plan | `87915d43467055c8833daf63aed283eb4926866110bb677c711f5e8621a8f8f1` |
| controlled-leg actual plan, 3-key sort | `q16-plan-act-pg-nopresorted.out` | same, `enable_presorted_aggregate=off` | plan | `1d73348ea5d81a81a737de291544ff29f0384c0aa009c23cd95309500cad7968` |
| `GROUPBY time 1471` vs `workers 3, 291..306` | `q16-trace-cubrid.out` | `SET TRACE ON` / `SHOW TRACE` | direct A/B | `41a64293023da1257c0cfad421d80f9f6dfa2f74be9755e3a364280913fd0b83` |
| subquery 5× (`readrows` 500,000 vs 100,000) | `q16-trace-cubrid.out` vs `q16-trace-cubrid-noparscan.out` | trace counter diff | direct A/B | `6f3a15a9e561f1d162e612aee12f031008888d234b91016cb2086eb9c3717d74` |
| pattern-independent 0.0263974 (10 probes) | `q16-like-probe-cubrid.out`, `q16-like-probe2-cubrid.out` | non-executing plan dumps | direct A/B | `a4c914629ef2a96a112706b07f7373c2c0ae06757975c8e1d0e6a28fe272a615` / `40169b14f30f948dd1f50e00cbfb812d8e1d173330ea27b2998d06b64977823b` |
| true selectivities for those 10 patterns | `q16-like-groundtruth-pg.out` | exact `count(*)` | direct A/B | `8ea2a80bac384fe9fd406099c0bba9932030d708953a7c5c4fc3ddfe35c9477f` |
| correctness 27,840 rows, ordered | `q16-correctness.json` | SSOT §11 ordered comparator | direct A/B | `8fef0bd67c92d8c84d73ebda378d7de0903180c3fbd2bfc745d84ff5ad40fd46` |
| CUBRID 0 physical reads | `Q16-cubrid-buffer-io-diag.json` | `/proc/<pid>/io` + `/proc/diskstats` deltas | measurement | `16e4801705716ef2c1ea279ebfb351aae7848cee7132e527b0ba601af0a66445` |
| PostgreSQL 0 physical reads | `Q16-postgresql-buffer-io-diag.json` | `blks_read` + `/proc` deltas | measurement | `5b8408acef581d02a74a7a1dea4e0c0b23e7cc5c63dc9706595fe0e17432006d` |
| CUBRID `NO_PARALLEL_SCAN` 7.690000 s | `Q16-cubrid-noparscan-headline.json` | median of 3 | direct A/B | `943b8a04e502fb890e360f1999f8f4b91178c2e93d318a4e012e5d19541a280a` |
| PostgreSQL `noparallel` 4.123853 s | `Q16-postgresql-noparallel-headline.json` | median of 3 | direct A/B (bound) | `2c12a003d07f0c67885d8f0b51b6a7853bfa98e2ad933aa8aa8fec5fcd068c70` |
| preflight all gates PASS | `preflight-Q16.txt` | §14.1 capture | gate | `b0fe35443f80976b755d2db948d5c76b353a67eb742c0832b601a02635dd15dd` |
| post-block gates PASS, no drift | `q16-postcheck.txt` | §10 post-block gate | gate | `0114fdd9b6bc3bfb6008296ab2ff9dc680606b5be61411b2272888ddeb297467` |
| WARM gate parameters, derived from Q16's own probes | `q16-warm-gate-params.txt` | 40-statement convergence probe per engine | derivation | `cc7f874263290c6452918d8fd5313d0f41bad883270942c2942ac1243b3e30c4` |
| CUBRID headline sink (9,205,567 B) | `sink/Q16-cubrid-headline-block1.out` | hashed after the timer stopped | measurement | `fdaf062150297d89ac0130aa5b0278579e913c3de700f0684046ff468c45fbb0` |
| PostgreSQL headline sink (4,269,142 B) | `sink/Q16-postgresql-headline-block1.out` | hashed after the timer stopped | measurement | `2152dca8a844442af8dff7fc9c5eb053e2a887d7c8b314b7269fd1d96c477f43` |

## 11. Notion sync

Per SSOT §21's execution boundary, this worker session runs on the remote
measurement host, has no Notion connector and **made no Notion write**. Its
Notion-adjacent duty ended at committing and pushing the report, raw manifest and
improvement ledger to `origin/main`, and appending one idempotent record with the
full §21 payload to `reports/notion_backfill_pending.jsonl`.

- idempotency key: `campaign_id + QNN + session_id + report_commit + content_fingerprint`
- write path used: **3** (Git backfill record) — paths 1 and 2 are not reachable
  from this session and were not attempted
- the §23 reconciler subagent (or a purpose-spawned one-off) performs the actual
  Notion sync by reading the just-pushed GitHub commit as source of truth
- the §21 markdown rule applies to that write: real newline characters, never the
  two-glyph literal `\n`; never escape `<table>`/`<tr>`/`<td>`, `##` headings or
  code fences; `notion-fetch` the page back afterwards and scan for an isolated
  `n` token or a literal `<`/`&lt;` inside what should be a rendered table
- pending is cleared only after a server-side refetch

## 12. Completion checklist

| § | Item | Status |
|---|---|---|
| 14.1 | identity / schema / ownership / NUMA / cpuset preflight | **DONE** — `preflight-Q16.txt`; all gates PASS, SSOT drift NONE, binaries match the frozen manifest, 8 FK / 8 child B-tree parity, 34 engine TIDs 0 off-cpuset, external load 0.250 core-s/s |
| 14.2 | correctness gate | **DONE** — `result-equivalent-at-SF10`, 27,840 rows, exact ordered sequence, full result sets saved on both engines |
| 14.3 | estimated plans without execution | **DONE** — CUBRID `SET OPTIMIZATION LEVEL 514` (`q16-plan-est-cubrid.out`), PostgreSQL `EXPLAIN (COSTS, VERBOSE, SETTINGS)` (`q16-plan-est-pg.out`), plus four controlled-variant estimates |
| 14.4 | CUBRID WARM + 3 headline runs | **DONE** — 3 gated §12 blocks, WARM proved per block from Q16's own 40-statement convergence probe; block medians 2.886 / 2.887 / 2.869 s (0.6237% spread) |
| 14.5 | PostgreSQL WARM + 3 headline runs | **DONE** — 3 gated §12 blocks; medians 1.196902 / 1.194293 / 1.199570 s (0.4409% spread). Even QNN → PostgreSQL block first |
| 14.6 | actual plans and CUBRID trace in separate non-headline runs | **DONE** — `q16-plan-act-pg.out`, `q16-plan-act-pg-nopresorted.out`, `q16-trace-cubrid.out`, `q16-trace-cubrid-noparscan.out`, each preceded by its own WARM establishment |
| 14.7 | CPU/thread, `/proc` I/O, iostat, NUMA and buffer diagnostics | **DONE** — 3 headline-regime telemetry blocks per engine plus one diagnostic block per engine; `statdump` retained but excluded with an explicit reason |
| 14.8 | separate perf cycles/instructions/call-graph runs | **DONE** — 90 s `perf stat` + 90 s `perf record -g --call-graph dwarf` per engine on verified PID sets; 0 unknown-symbol lines, 0 lost samples |
| 14.9 | CUBRID `file:line` and PostgreSQL counterpart `file:line` | **DONE** — section 7, 11 contrast rows, both sides cited, absence claims record searched paths/symbols/patterns |
| 14.10 | causal multiplier decomposition | **DONE** — section 3-a, residual 0.000000000000%, `F_plan` on a same-engine controlled A/B, no native/controlled denominator mixing |
| 14.11 | improvement registry deduplication and relations | **DONE** — ledger synced and searched against all 21 existing candidates; IMP-022 and IMP-023 allocated, `next_id` → IMP-024; Q16 evidence and relations added to IMP-003, IMP-004, IMP-008, IMP-009, IMP-020; containment notes added to IMP-006 and IMP-015 |
| 14.12 | raw manifest, report, Git commit and Notion sync/backfill | **DONE** — `reports/Q16/raw-manifest.json`, this report, commit pushed to `origin/main`, one idempotent record appended to `reports/notion_backfill_pending.jsonl` (write path 3; §21 execution boundary observed, no Notion write attempted) |
| 14.13 | completion checklist and `QUERY_COMPLETE` | **DONE** — this table; `QUERY_COMPLETE` emitted |
| 14.14 | current GJC session removal and absence verification | performed by the controlling session after this report is durable on `origin/main` |

### §26 query completion gate

| Requirement | Status |
|---|---|
| preflight and correctness status recorded | yes — sections 1 and 2 |
| three valid headline values per completing engine | yes — three per engine per block, three blocks per engine |
| timeout confirmations | n/a — no censoring; the slower engine's median is 2.886 s against a 300 s timeout |
| plan, execution, profile and source contrast sections complete | yes — sections 4, 5, 6, 7 |
| causal card has evidence or explicit `UNMEASURED` | yes — every factor measured, none `UNMEASURED` |
| Git improvement ledger deduplicated and committed | yes — section 9 and `q16-registry-dedup.txt` |
| every claim indexed to raw evidence and checksum | yes — section 10 and `raw-manifest.json` |
| report, manifest and registry committed, pushed, reachable from `origin/main` | yes — see the `report_commit` in `raw-manifest.json` and the backfill record |
| `QUERY_COMPLETE` emitted | yes |
| current session removed and absence verified | performed after this report is durable |

### Carried-forward gaps

1. `F_cost` 3.031730x is attributed by profile bands, not by a controlled A/B — the
   same evidence class as Q12/Q13/Q14's `F_cost`. The bands are disjoint self-%
   partitions of a 0-unknown-symbol profile, but no switch isolates any single one.
2. IMP-023's sub-item (a) (presorted-input DISTINCT) is measured to be worth
   **−7.06%** on Q16, so the candidate's recommended fix is (b)/(c), whose effect
   is bounded (0.750–1.041 s) but not directly A/B-tested; no CUBRID switch exists
   to test it without a code change. Status stays `measured`, not `validated`.
3. IMP-022's Q16 wall effect is exactly zero. Its magnitude is established
   (36.61x, pattern-independent, reproduced from source constants) but no query in
   Q01–Q16 has yet been measured to lose wall time to that specific branch.
4. The 5× uncorrelated-subquery materialisation (IMP-009) is quantified in CPU
   (~0.49 core-s, 5.2%) but its source line was not located in this session; the
   evidence is the trace counter pair, not a code citation.
5. `cubrid statdump` remains unusable for per-statement buffer accounting on this
   server (Q14 finding, reconfirmed on Q16). CUBRID buffer evidence uses
   `/proc/<pid>/io` and `/proc/diskstats`, which are whole-process and cannot be
   split per plan node.
6. PostgreSQL's presorted-aggregate mis-costing (section 4-d) is a real, measured
   PostgreSQL defect surfaced by this campaign's instrument. It is out of scope for
   the CUBRID improvement ledger and is recorded here only, deliberately.

`QUERY_COMPLETE`
