# TPCH-SSPQ FK campaign — Q13 report

TPC-H Query 13, *Customer Distribution*.

## 3-a. Causal multiplier card

```text
R_wall 2.246313x [wall, median of 3 per engine, contract block1; PostgreSQL is 2.2463x faster]
= F_plan UNMEASURED [plan-shape; NOT 1.0000 — the two plans are structurally
                     unequal (section 4-c) and no single controlled A/B isolates
                     that one difference; its effect is therefore carried INSIDE
                     F_cpu below, and section 8-c bounds how much of F_cpu it is]
× F_units 1.029635x [total-query-CPU/wall correction, cross-checked by TWU]
× F_cpu   2.198437x [total query CPU-seconds]

F_cpu 2.198437x
= F_work 1.000000x [join output rows: 15,337,604 on BOTH engines,
                    independently re-measured by ground-truth queries per engine]
× F_cost 2.198437x [total query CPU-seconds per join output row]
```

| factor | value | event unit | denominator | formula | raw pointer | evidence type |
|---|---|---|---|---|---|---|
| `R_wall` | 2.246313x | wall seconds | median of 3 measured statements, contract block1, per engine | `T_C / T_P` = 11.425999 / 5.086557 | `Q13-cubrid-headline-block1.json`, `Q13-postgresql-headline-block1.json` | direct A/B |
| `F_plan` | **UNMEASURED** | — | — | — | `q13-plan-est-cubrid.out`, `q13-plan-act-pg.out` | structural inequality proved, magnitude bounded not measured (section 8-c) |
| `F_units` | 1.029635x | core-seconds per wall-second | one section-12 4-statement block per engine | `U_P / U_C` = 4.37802 / 4.25201 | `Q13-*-headline-telemetry-run1.json` | direct measurement |
| `F_cpu` | 2.198437x | core-seconds | same telemetry block | `CPU_C / CPU_P` = 194.100 / 88.290 | same | direct measurement |
| `F_work` | 1.000000x | join output rows | one statement | `W_C / W_P` = 15,337,604 / 15,337,604 | `q13-groundtruth-cubrid.out`, `q13-groundtruth-pg.out` (`G4`) | direct A/B |
| `F_cost` | 2.198437x | core-seconds per join output row | one statement | `(CPU_C/W_C)/(CPU_P/W_P)` = 3.1638 µs / 1.4391 µs | derived from the two rows above | direct measurement |

`F_units × F_cpu = 1.029635 × 2.198437 = 2.263589`, which is exactly the telemetry
pair's own wall ratio `45.64900 / 20.16665 = 2.263588`. The identity closes on its own
pair to 4.4e-7.

### Reconstruction residual

`F_units × F_cpu` (2.263589) reconstructs `R_wall` (2.246313) with a residual of
**+0.7691%**. The residual exists because the two factors are measured on the stage-14.7
telemetry blocks while `R_wall` is taken from the stage-14.4/14.5 contract blocks, and
PostgreSQL's telemetry block happened to sit 0.94% below its contract block (5.038688
vs 5.086557 statement median). It is not an unexplained term.

### Error budget, stated before any factor is interpreted

| | contract-block spread | value |
|---|---|---|
| CUBRID, three contract block medians | 11.425999 / 11.446000 / 11.482999 | **0.4980%** |
| PostgreSQL, three contract block medians | 5.086557 / 5.081363 / 5.063415 | **0.4554%** |
| combined budget for a cross-engine ratio | sum | **0.9534%** |

The +0.7691% residual is inside the 0.9534% budget, so the card is closed. Every factor
below is interpreted only where its effect exceeds this budget; the `F_units` factor
(2.96%) clears it by 3.1x and `F_cpu` (119.8%) by 126x.

### Independent reconstruction of `F_cpu` from hardware counters

`F_cpu` is re-derived from `perf stat` alone, without using the sampler at all:

```text
CPU_time = instructions / (IPC × frequency)

F_cpu = (I_C/I_P) × (IPC_P/IPC_C) × (f_P/f_C)
      = 3.121981 × (1.19/1.73) × (2.850/2.779)
      = 2.202355        vs measured 2.198437   →  +0.1782%
```

Two independent instruments (a `/proc`-based CPU sampler on the collector CPUs, and
hardware PMU counters attached to verified PID sets) agree on `F_cpu` to 0.18%.
Note the direction of the two sub-terms: CUBRID retires **3.1220x** the instructions per
statement but at a **1.4538x better IPC** (1.73 vs 1.19). Q13 is not a stall problem on
CUBRID's side — it is an instruction-count problem.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| Query | Q13 — Customer Distribution |
| SSOT commit | `d6e337130915e260bca8277c379915beeac85d09` (pinned) |
| SSOT blob SHA | `510478846bff081d3223d3835069283a7cd2e47b` |
| SSOT drift | **NONE**. `git hash-object SSOT.md` = the pinned blob at session start and at the post-block gate. `HEAD` was `b64cd8972467f1e52c915658aaad25c60ff59999`, two commits ahead of the pinned commit, but `git merge-base --is-ancestor d6e3371 HEAD` is true and both `d6e3371:tpch-sspq/SSOT.md` and `HEAD:tpch-sspq/SSOT.md` resolve to the same blob `510478846bff…` — the two intervening commits are Q12's own report/manifest/backfill deliverables and touch no rule text |
| GJC session ID | `gajae_code_ms9ecbdx_vugn5vtz` (internal `GJC_SESSION_ID` `019fb9de-9c41-7000-9a0c-af412ec99fdb`) |
| Recovery-session provenance | This is a **recovery session** under SSOT §23. A predecessor session (`019fb9db-2f58-7000-90ea-97bec25e319e`) had already produced Q13's stage-14.1 preflight, stage-14.2 correctness gate, stage-14.3 estimated plans and the stage sizing probe. Those artifacts were read and continued, not repeated; the preflight was re-captured under this session's ID and the predecessor's copy is retained as `q13-preflight-predecessor-session.txt`. No headline measurement was inherited — every value in this report was measured by this session |
| Raw root | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q13` (365 artifacts, 7.8 MB, 48 carrying an explicit invalid/excluded reason) |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (includes PR #7441 merge `b334446d6`), checkout `/home/cubrid/dev/tpch-sspq-fk-r1/cubrid-src` |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13`, ELF Build ID `4df41ee21300bf617bccd5e1d5c8522b074ef86e` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` (PostgreSQL 20devel), checkout `/home/cubrid/dev/postgres` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b`, ELF Build ID `5f2cb2987765c612638c278f85cfc85c211fffe1` |
| Build flags | CUBRID RelWithDebInfo, assertions disabled, not stripped; PostgreSQL `--enable-debug --without-llvm`, assertions off, JIT off — frozen `reports/bootstrap/build-manifest.json`, `frozen: true`; both live binary hashes re-verified against it at preflight and post-block |
| Ownership gate | pre-block and post-block **OK** — `cub_master` 1433697, `cub_server` 1612732, postmaster 1433696, all resolving to the campaign prefixes; port 1523 owned by `cub_master`, 5442 by the campaign postmaster |
| cpuset / NUMA | 34 engine TIDs, **0 off-cpuset** before and after; SUT+client CPUs 0-15 (node0), collectors 20-23. `cub_server` private memory 8,830.21 MB on node0 / 1.64 MB on node1 — the buffer pool is node-local |
| External load | 0.282 core-s/s at preflight; every accepted block `CLEAN` under both the per-sample strict rule and the contract-window rule (threshold 6.0, SSOT §9) |
| Query provenance | `queries/q13-cubrid.sql` SHA-256 `4df486b1d76644fa9d425c209e5e7f542470a04beae5296d2df0909c40ea13a9`, **byte-matches** `/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q13.sql` |
| Dialect | `queries/q13-pg.sql` SHA-256 `4df486b1d766…` — **identical to the CUBRID file byte for byte**. `queries/diff/q13.diff` is 0 bytes; `cmp` reports no difference. Zero dialect changes: no hint, no join reordering, no subquery rewrite, no extra predicate, no semantic cast |
| Schema contract | 8 FK / 8 child B-trees per engine, exact column order, all PostgreSQL constraints `convalidated=t` |
| Statistics | histogram-enabled controlled comparison: CUBRID `update_statistics_update_histogram=y`, bucket target 300; PostgreSQL `default_statistics_target=100`, standard `ANALYZE` |
| Parallel/buffer | configured node/gather-cap comparison, configured-equal buffer budget: CUBRID `parallelism=6`, `max_parallel_workers=100`, `data_buffer_size=8.0G`; PostgreSQL `max_parallel_workers_per_gather=5`, `max_parallel_workers=5`, `parallel_leader_participation=on`, `shared_buffers=8192MB` |
| Shared memory | `dynamic_shared_memory_type=mmap`. Load-bearing for Q13: PostgreSQL's chosen plan is a `Gather Merge` over four workers, whose tuple queues live in DSM, and the mmap fault-in of those segments is a *measured* band in its profile (section 6-b, kernel band 1.721 core-s per statement) |
| Charset / collation parity | **verified, and load-bearing for section 7**: CUBRID `orders.o_comment` is `CHARACTER VARYING(79) … COLLATE utf8_bin` under `intl_collation=utf8_bin`; PostgreSQL database `tpch_sspq` is encoding `UTF8` with `datcollate=C`, `datlocprovider=c`, and `o_comment` is `character varying` with the default collation. Both engines therefore run a **UTF-8, deterministic, binary-ordering** LIKE. PostgreSQL is *not* on a single-byte fast path: `like.c:156-161` selects `UTF8_MatchText` whenever `GetDatabaseEncoding() == PG_UTF8`, which is this database |
| Row counts | identical on both engines: customer 1,500,000; orders 15,000,000 |
| Stored size | customer: CUBRID 21,049 × 16 KiB = 328.9 MiB; PostgreSQL heap 281 MB, total 323 MB. orders: CUBRID 151,689 × 16 KiB = 2,370.1 MiB; PostgreSQL heap 2,041 MB, total 2,483 MB |
| Engine block order | Q13 is odd → **CUBRID block first, then PostgreSQL** (SSOT §12) |

Q13's whole working set (customer + orders + the FK index) fits inside both engines'
8192 MB budget. That is why both engines take **zero physical reads** in the measured
regime (section 5-d) and why this query is a pure CPU comparison with no I/O term at all.

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored; both engines completed in ~5-11 s against
a 300 s timeout.

The query has an `ORDER BY`, so the ordered result sequence was compared exactly, subject
only to the SSOT §11 decimal rule. 46 rows on both engines, in the same order, with
identical text/integer/NULL content and identical row multiplicity. `q13-correctness.json`:

```json
{"qnn": "Q13", "ordered": true, "stage": "14.2-correctness-gate",
 "result": {"detail": "46 rows, ordered=True", "status": "result-equivalent-at-SF10"}}
```

Independent ground-truth cardinalities were re-measured separately on each engine with
dialect-neutral SQL copied verbatim from the canonical query text. **All ten agree
exactly across engines**, which is what licenses `F_work = 1.000000` in the card:

| id | meaning | CUBRID | PostgreSQL |
|---|---|---|---|
| `G0` | customer rows | 1,500,000 | 1,500,000 |
| `G0` | orders rows | 15,000,000 | 15,000,000 |
| `G1` | orders surviving `o_comment not like '%special%requests%'` | 14,837,583 | 14,837,583 |
| `G2` | orders removed by that predicate | 162,417 | 162,417 |
| `G3` | distinct `o_custkey` among kept orders | 999,979 | 999,979 |
| `G4` | **join output rows** (the `F_work` event) | **15,337,604** | **15,337,604** |
| `G5` | inner groups on `c_custkey` | 1,500,000 | 1,500,000 |
| `G6` | customers with `c_count = 0` | 500,021 | 500,021 |
| `G7` | final groups on `c_count` | 46 | 46 |
| `G8` | max `c_count` | 45 | 45 |

`G4 = 15,337,604 = G1 (14,837,583) + G6 (500,021)` — every kept order contributes one row
and every order-less customer contributes one null-extended row. The identity holds
exactly, so the two engines are not merely returning the same 46 output rows, they are
processing the same intermediate multiset.

## 3-b. Headline timings

Regime: **single-query-repeat WARM**. Connection mode
**`single-connection-four-statements`** — one direct connection, one uncounted warmup,
three measured statements, no prepare/pool/reconnect between them, connection
establishment excluded, every statement fully consuming all rows into a campaign-owned
sink under `work/Q13` with no terminal rendering. CUBRID uses `csql -C` direct ad-hoc
execution; PostgreSQL one `psql` Unix-socket connection on the simple-query protocol.

| | statement 1 | statement 2 | statement 3 | median | mean | sd |
|---|---|---|---|---|---|---|
| **CUBRID** (block1, headline) | 11.425999 | 11.461000 | 11.388999 | **11.425999 s** | 11.425333 | 0.036005 |
| **PostgreSQL** (block1, headline) | 5.085249 | 5.105513 | 5.086557 | **5.086557 s** | 5.092440 | 0.011341 |

**Median wall ratio: 2.246313x — PostgreSQL faster.** Mean ratio 2.243587x, so the median
is not an artifact of the choice of statistic. Three values per engine; no confidence
interval is claimed from three values (SSOT §12).

Uncounted warmup statements: CUBRID 11.435000 s, PostgreSQL 5.126248 s — 0.08% and 0.78%
above their own block medians, i.e. each block is already on its level at the first
measured statement.

Sinks: CUBRID 9,079 bytes SHA-256 `4f1edcbc693d…`; PostgreSQL 1,554 bytes SHA-256
`b15358853923…`. The byte counts differ because `csql` writes a bordered result table and
`psql -A -t` writes unaligned tuples only; content equivalence is section 2's gate.
Per-statement client wall includes result transfer and the sink write, while client
formatting/transfer CPU stays in `auxiliary_query_cpu` and is never attributed to the
executor.

### All three blocks per engine

| block | CUBRID median | PostgreSQL median |
|---|---|---|
| 1 (**headline**) | **11.425999** | **5.086557** |
| 2 | 11.446000 | 5.081363 |
| 3 | 11.482999 | 5.063415 |
| spread | **0.4980%** | **0.4554%** |

All six contract blocks were accepted on **attempt 1** with a `CLEAN` load verdict under
both the strict per-sample rule and the contract-window rule. Blocks 2 and 3 are retained
as stability evidence and are marked non-headline in the manifest.

### WARM proof

WARM is proved, not assumed. Gate parameters were derived from **this query's own**
40-statement convergence probes rather than inherited (`q13-warm-gate-params.txt`):

| | probe steady state | half-split trend | trailing spread | first converged at |
|---|---|---|---|---|
| CUBRID | 11.434 s | +0.1570% | 0.3761% | statement 12 |
| PostgreSQL | 5.049427 s | +0.1485% | 0.3533% | statement 12 |

Chosen: `WARM_STATEMENTS=20` (1.67x the observed convergence point), `WINDOW=6`;
`LEVEL_TOL` 0.010 both engines; `SPREAD_SANITY` 0.020 (CUBRID) and 0.015 (PostgreSQL).
Each tolerance is above this query's own measured stationary statistic by 6-7x and far
below the 13.17% half-split trend the campaign's warming reference series produces.

The headline blocks' own warm establishment reported **CONVERGED** for both engines at
statement 18 of 20, and the certified steady states (CUBRID 11.377, PostgreSQL from the
same stage) sit within 0.43% of the block medians actually measured.

Unlike Q04, Q11 and Q12, Q13 shows **no level shift between blocks and no decay curve**:
the 40-statement CUBRID probe spans 11.332-11.587 s with no monotone segment, and section
5-d shows why — the working set is resident, so there is no residency state to gain or
lose. Here WARM means *proved-stationary **and** zero-miss*, which is a stronger condition
than any previous query in this campaign reached.

## 4. Plan

### 4-a. CUBRID native (estimated, SQL `SET OPTIMIZATION LEVEL 514`, non-executing)

```text
                                 -- inner block --
temp(group by)
    subplan: idx-join (left outer join)
                 outer: sscan
                            class: customer node[0]
                            cost:  24799 card 1500000
                 inner: iscan
                            class: orders node[1]
                            index: fk_orders_customer term[0]
                            sargs: term[1]
                            cost:  4 card 14998500
                 cost:  1112308 card 14998500
    sort:  1 asc
    cost:  1171780 card 14998500

                                 -- outer block --
temp(order by)
    subplan: temp(group by)
                 subplan: sscan
                              class: c_orders node[0]
                              cost:  5947 card 1500000
                 sort:  1 asc
                 cost:  11533 card 1500000
    sort:  2 desc, 1 desc
    cost:  17119 card 1500000
```

`term[1]` is `[dba.orders].o_comment not like '%special%requests%' (sel 0.9999)` — a sarg
term evaluated on the *inner* of the nested loop, i.e. once per matched order row.

### 4-b. PostgreSQL native (`EXPLAIN ANALYZE, BUFFERS, VERBOSE, SETTINGS`)

```text
Sort  (actual time=5074.709..5326.718 rows=46.00 loops=1)
  Sort Method: quicksort  Memory: 26kB
  Buffers: shared hit=19503684
  ->  HashAggregate  (actual time=5074.670..5326.682 rows=46.00 loops=1)
        Group Key: count(orders.o_orderkey)
        Batches: 1  Memory Usage: 32kB
        ->  Finalize GroupAggregate  (actual time=33.563..5148.518 rows=1500000.00 loops=1)
              Group Key: customer.c_custkey
              ->  Gather Merge  (actual time=33.517..4883.868 rows=1500000.00 loops=1)
                    Workers Planned: 4      Workers Launched: 4
                    ->  Partial GroupAggregate  (actual time=0.389..4443.987 rows=300000.00 loops=5)
                          Group Key: customer.c_custkey
                          ->  Nested Loop Left Join  (actual time=0.115..4201.661 rows=3067520.80 loops=5)
                                ->  Parallel Index Only Scan using customer_pkey on customer
                                      (actual time=0.053..26.903 rows=300000.00 loops=5)
                                      Heap Fetches: 0    Index Searches: 1    Buffers: shared hit=4129
                                ->  Index Scan using idx_fk_orders_customer on orders
                                      (actual time=0.002..0.013 rows=9.89 loops=1500000)
                                      Index Cond: (orders.o_custkey = customer.c_custkey)
                                      Filter: ((orders.o_comment)::text !~~ '%special%requests%'::text)
                                      Index Searches: 1500000   Buffers: shared hit=19499552
Planning Time: 1.063 ms
Execution Time: 5326.882 ms
```

### 4-c. Shape comparison — why `F_plan` is `UNMEASURED` and not `1.0000`

Operator for operator, the two plans agree on **everything except the access path to
`customer` and, as a direct consequence, the grouping method**:

| stage | CUBRID | PostgreSQL | same? |
|---|---|---|---|
| driving relation | `customer`, 1,500,000 rows | `customer`, 1,500,000 rows | yes |
| join method | `idx-join (left outer join)` — index nested loop | `Nested Loop Left Join` | **yes** |
| inner access | `iscan orders.fk_orders_customer` | `Index Scan using idx_fk_orders_customer` | **yes** |
| `o_comment` predicate | `sargs: term[1]` on the inner | `Filter` on the inner index scan | **yes** |
| join output | 15,337,604 rows | 15,337,604 rows | **yes** (ground truth `G4`) |
| **`customer` access path** | **`sscan` — heap sequential scan, 21,049 pages, unordered** | **`Parallel Index Only Scan using customer_pkey`, 4,129 buffers, `Heap Fetches: 0`, ordered on `c_custkey`** | **NO** |
| **inner `GROUP BY c_custkey`** | **`temp(group by)` + `sort: 1 asc` — materialise all 15,337,604 join rows into a temp file (20,861 pages = 326 MiB) and sort them** | **`Partial GroupAggregate` — streams directly off the index order, no Sort node anywhere in the plan** | **NO** |
| outer `GROUP BY c_count` | `temp(group by)`, 1 ms | `HashAggregate`, 32 kB, `Batches: 1` | different, but 46 groups — immaterial |
| final `ORDER BY` | `temp(order by)` | `Sort`, quicksort, 26 kB | different, but 46 rows — immaterial |
| execution units | 5 parallel workers on the customer scan, 2 on the temp rescan | 4 workers launched + participating leader | near-equal (section 5-c) |

The two `NO` rows are **one root cause, not two**: PostgreSQL's index-only scan is chosen
*because* its ordering is useful, and that ordering is what lets the grouping stream. SSOT
§16 permits a numeric `F_plan` only on structural equality or direct controlled evidence.
There is no structural equality here, and no single controlled A/B isolates this one
difference (section 8-c explains exactly why each candidate anchor fails), so `F_plan` is
recorded as `UNMEASURED`. `F_units` and `F_cpu` are therefore both computed on the
**native** cross-engine pair, with no controlled denominator mixed in, and the plan-shape
effect is carried inside `F_cpu` where section 8-c bounds it.

### 4-d. Controlled variants (each through the same section-12 block regime and load gate)

| variant | switch | resulting plan | wall (median of 3) | vs its native | U | TWU |
|---|---|---|---|---|---|---|
| CUBRID native | — | as 4-a | 11.425999 | 1.0000x | 4.25201 | 4.2459 |
| CUBRID `noparscan` | `/*+ NO_PARALLEL_SCAN */`, **outer block only** | estimated plan **identical to native apart from the hint text** | 11.621000 | 1.0171x | 4.22187 | 4.2233 |
| CUBRID `noparscan2` | same hint on **both** blocks | estimated plan **identical to native apart from the hint text**; fully serial | 47.388998 | **4.1475x** | 1.00238 | 1.0022 |
| PostgreSQL native | — | as 4-b | 5.086557 | 1.0000x | 4.37802 | 4.4629 |
| PostgreSQL `noparallel` | `max_parallel_workers_per_gather=0` | **Hash Right Join + HashAggregate, serial** | 13.678316 | 2.6891x | 0.99788 | 0.9953 |
| PostgreSQL `nonestloop` | `enable_nestloop=off` | **byte-identical plan to `noparallel`** | 13.676278 | 2.6887x | 0.99723 | 0.9957 |

Three things this table settles:

1. **The first CUBRID units anchor is void, and the plan text proves it.** `/*+
   NO_PARALLEL_SCAN */` written on the outer `select` reached only the outer block;
   `diff`ing `q13-plan-est-cubrid-noparscan.out` against the native plan shows the two
   files differ **in the hint text alone**, so the inner block's 5-worker `customer` scan
   was untouched. The measured 1.0171x is the cost of serialising the outer block's
   1.5M-row temp rescan and nothing else. It is reported as measured rather than dropped,
   and a corrected both-blocks variant (`noparscan2`, whose estimated plan is likewise
   identical to native apart from the hint text) was launched; see the stage-4 note.
2. **PostgreSQL's two switches produce the same plan and agree to 0.0149%** (13.676278 vs
   13.678316). That is a strong internal consistency check: what changed the time is the
   *plan*, not either switch, because two different switches that select the same plan
   select the same cost.
3. **PostgreSQL deprived of its ordered parallel path is slower than CUBRID.** 13.678 s
   against CUBRID's 11.426 s — CUBRID is 1.1972x *faster* on that shape. Q13's 2.2463x is
   therefore not a statement that PostgreSQL's executor is uniformly better; it is a
   statement about one specific plan being available to one engine.
4. **The corrected CUBRID units anchor closes to 0.057%.** With the hint on both blocks
   CUBRID runs fully serial — measured `U` **1.00238**, TWU 1.0022 — at 47.388998 s, a
   **4.1475x** serialisation cost. Since `T = CPU / U`, the serialisation cost is
   *predicted* by the independently measured CPU and unit counts:

   ```text
   T_serial / T_parallel = (CPU_ser/CPU_par) × (U_par/U_ser)
                         = (189.670/194.100) × (4.25201/1.00238)
                         = 0.977177 × 4.241923
                         = 4.145143      vs measured 47.388998/11.425999 = 4.147485
                         →  agreement +0.0565%
   ```

   Two consequences. First, CUBRID's `U` of 4.25201 is real concurrency, not a sampler
   artefact — a serial run of the same statement measures 1.00238 on the same instrument.
   Second, **CUBRID's parallelism is nearly free in CPU terms**: going from 1 unit to 4.25
   units costs only 2.34% more total CPU (194.100 vs 189.670 core-s). Whatever Q13's
   problem is, it is not parallel-execution overhead.

## 5. Execution telemetry

### 5-a. Node-level time, CUBRID trace (`SET TRACE ON`, non-headline)

```text
SELECT (time: 13357, fetch: 3102540, fetch_time: 342, ioread: 0)
  SCAN (temp time: 169, fetch: 2218, ioread: 0, readrows: 1500000, rows: 1500000)
       (parallel workers: 2, temp time: 166..169, readrows: 741468..758532, gather: mergeable list)
  GROUPBY (time: 1, hash: partial, sort: true, page: 0, ioread: 0, rows: 46)
  ORDERBY (time: 0, sort: true, page: 20861, ioread: 0)
  SUBQUERY (uncorrelated)
    SELECT (time: 13187, fetch: 3100222, fetch_time: 342, ioread: 0)
      SCAN (table: dba.customer), (heap time: 10982, fetch: 868, ioread: 0, readrows: 0, rows: 0)
           (parallel workers: 5, heap time: 10735..10969, readrows: 295632..301237, gather: mergeable list)
        SCAN (index: dba.orders.fk_orders_customer), (btree time: 9205, fetch: 19504609,
              ioread: 0, readkeys: 1499999, filteredkeys: 999982, rows: 15000000)
              (lookup time: 7802, rows: 14837583)
      GROUPBY (time: 2202, hash: partial, sort: true, page: 20861, ioread: 0, rows: 1500000)
```

Reading, with the trace's own caveats applied:

- `ioread: 0` at **every** node. Zero physical reads, independently confirmed in 5-d.
- the inner block is 13,187 ms of the traced 13,357 ms; within it the scan/join subtree is
  10,982 ms and the **inner `GROUP BY` is 2,202 ms — 16.4857% of traced wall**;
- `rows: 15000000` from the B-tree and `lookup … rows: 14837583` after the heap lookup
  applies `o_comment not like …`: 15,000,000 − 14,837,583 = 162,417, exactly ground truth
  `G2`. The predicate is evaluated **15,000,000 times per statement**;
- `ORDERBY (… page: 20861 …)` on a **46-row** sort is impossible and is a known
  instrument defect, not a measurement: it is the inner `GROUPBY`'s temp page count
  re-reported at an ancestor node. This is a fresh instance of **IMP-005** (trace
  statistics merged once per `scan_ptr` level and again by the whole-subtree walk) and is
  recorded as such in section 9. No number in this report is taken from that field.

### 5-b. Node-level time, PostgreSQL

`Execution Time` 5,326.882 ms, `Planning Time` 1.063 ms. Cumulative node times:

| node | actual time (ms) | increment over its child |
|---|---|---|
| `Parallel Index Only Scan customer_pkey` | 26.903 (per worker avg) | — |
| `Nested Loop Left Join` | 4,201.661 | +4,174.8 |
| `Partial GroupAggregate` | 4,443.987 | **+242.3** |
| `Gather Merge` | 4,883.868 | +439.9 |
| `Finalize GroupAggregate` | 5,148.518 | +264.7 |
| `HashAggregate` + `Sort` | 5,326.718 | +178.2 |

The whole grouping apparatus — partial aggregate, gather-merge, final aggregate — costs
PostgreSQL **946.9 ms** and contains **no sort of the 15.3M-row stream at all**; the only
`Sort Method` reported anywhere is a 26 kB quicksort of the final 46 rows. CUBRID's
equivalent inner grouping alone is 2,202 ms *plus* a 326 MiB temp materialisation.

### 5-c. CPU accounting (SSOT §15, median-U telemetry run per engine)

| | CUBRID (run1) | PostgreSQL (run1) |
|---|---|---|
| `executor_cpu` | **193.840** core-s | **88.290** core-s |
| `auxiliary_query_cpu` | **0.260** core-s | **0.000** core-s |
| `total_query_cpu` | **194.100** core-s | **88.290** core-s |
| `unattributed_background` | none observed | none observed |
| block wall `t_block` | 45.64900 s | 20.16665 s |
| `U = total_query_cpu / t_block` | **4.25201** | **4.37802** |
| TWU (actual sample timestamp deltas) | **4.2459** | **4.4629** |
| max simultaneous active units | 5.3223 | 4.7943 |
| planned workers | 6 configured cap; trace reports **5** on the customer scan, **2** on the temp rescan | `Workers Planned: 4` |
| launched workers | same as above (CUBRID reports launched workers only) | `Workers Launched: 4` (+ participating leader = 5 units) |
| serial tail | 0.113 s | 0.115 s |
| per-statement CPU | **48.4559** core-s | **22.0595** core-s |

Executor/auxiliary classification, per bucket:

| CUBRID bucket | core-s | PostgreSQL bucket | core-s |
|---|---|---|---|
| `executor:cub_server:parallel-query` | 185.52 | `executor:pg_parallel_worker:postgres` | 78.38 |
| `executor:cub_server:transaction` | 8.30 | `executor:pg_backend:postgres` (leader) | 9.91 |
| `executor:cub_server:coordinator` | 0.01 | — | — |
| `executor:cub_server:connections` | 0.01 | — | — |
| `auxiliary:*` (vacuum-master, dwb-flush/sync, pgbuf-maintain/flush-con, log-clock, deadlock-detect) | 0.26 | none | 0.00 |

Three-run stability: CUBRID `U` 4.25201 / 4.25392 / 4.24478 (spread 0.215%), total CPU
194.100 / 194.940 / 193.490 (0.748%); PostgreSQL `U` 4.37802 / 4.38303 / 4.35961 (0.535%),
total CPU 88.290 / 88.790 / 87.860 (1.054%). The median-`U` run is the reported one for
each engine (SSOT §15).

TWU is an independent cross-check on `U` and not a substitute for it: CUBRID 4.2459 vs
4.25201 (0.14% apart), PostgreSQL 4.4629 vs 4.37802 (1.94% apart). Both are weighted by
actual sample timestamp deltas, never by the nominal interval. `perf stat`'s wholly
independent "CPUs utilized" reading — 4.285 for CUBRID, 4.436 for PostgreSQL — agrees with
both to within 0.8% and 1.3%.

**`F_units` is 1.029635x and that is the whole parallelism story for Q13.** Both engines
run at essentially the same number of active units. This query is not a parallelism
finding.

### 5-d. Buffer, `/proc` I/O, iostat and NUMA (stage 14.7, non-headline)

Per statement over one WARM-established, load-gated 4-statement block:

| | CUBRID | PostgreSQL |
|---|---|---|
| `/proc/<server>/io` `read_bytes` | **0** | **0** |
| `/proc/<server>/io` `syscr` | 203 | 11,565.5 |
| engine physical-read counter | `Num_data_page_ioreads` delta **0** | `pg_stat_database.blks_read` delta **0** |
| engine logical-read counter | `Num_data_page_fetches` **22,649,042** per statement (isolated traced statement, section 5-e) | `blks_hit` **19,505,873** per statement |
| device read | 0.012 MiB across the whole block, on a device the server did not read from | 0.016 MiB, likewise |
| NUMA | `cub_server` private 8,830.21 MB node0 / 1.64 MB node1 | postmaster private 150.70 MB node0 / 0.51 MB node1 |

**Both engines take zero physical reads.** This is the cleanest WARM proof in the campaign
so far: it is not "proved stationary", it is "provably nothing left to read". Every
comparison in this report is therefore free of any I/O term, and the ~48.9 MiB of device
*writes* seen in the CUBRID window is not attributable to `cub_server`, whose own
`write_bytes` is 2,048 B per statement.

One instrument failed and is recorded rather than hidden: in the *diagnostic block*, every
server-wide `Num_data_page_*` counter showed a **zero delta** across four statements
(`Q13-cubrid-buffer-io-diag.json`), while the same counter moved by 22.6M for a single
isolated traced statement in the serial/parallel probe. The diagnostic-block reading is
therefore discarded as invalid, and the probe reading is used. This reproduces the same
statdump-versus-pooled-parallel-worker defect Q12 recorded.

### 5-e. Serial vs parallel page fixes — a *negative* result that bounds IMP-010

One traced native (parallel) statement and one traced `/*+ NO_PARALLEL_SCAN */` statement,
each bracketed by `/proc/<cub_server>/io` and `statdump`:

| | parallel | serial | delta |
|---|---|---|---|
| `Num_data_page_fetches` | 22,649,042 | 22,648,891 | **−0.00067%** |
| `Num_data_page_ioreads` | 1 | 0 | — |
| `/proc` `read_bytes` | 0 | 0 | 0 |

IMP-010 (a heap scan's pages land in the *middle* of the shared LRU when the scan runs on
pooled parallel-query workers, so going parallel discards scan resistance and re-reads
pages) **does not fire on Q13**, and this is the first query in the campaign that can say
so with a controlled measurement. The reason is now explicit: IMP-010's damage is
re-reading, and there is nothing to re-read when the working set is resident and physical
reads are zero. This bounds IMP-010 to the working-set-exceeds-pool regime rather than
weakening it, and is recorded against IMP-010 in section 9.

## 6. Profile

Non-headline. `perf record -F 999 -g --call-graph dwarf` attached to a **verified PID set**
(never all-CPU), 90 s window, 24 repeats in one connection per engine, both pre-warmed
through the same convergence gate. CUBRID: one `cub_server` PID (1612732, 30 TIDs — every
query worker thread lives inside that process). PostgreSQL: `perf stat` attached to the
**postmaster before the client connection existed**, so inherit-on-fork counts the leader
and every statement's parallel workers and nothing that pre-dates the attach.

Sample-coverage validation against `perf stat`:

| | samples | lost | flat lines | `[unknown]` lines | task-clock | CPUs utilized | cycles | instructions | IPC | GHz |
|---|---|---|---|---|---|---|---|---|---|---|
| CUBRID | 391,556 | 0 | 726 | **0** | 385,701.03 ms | 4.285 | 1.0719e12 | 1.8553e12 | **1.73** | 2.779 |
| PostgreSQL | 137,461 | 0 | 1,280 | **0** | 399,212.38 ms | 4.436 | 1.1377e12 | 1.3511e12 | **1.19** | 2.850 |

Zero unresolved symbols on both sides, zero lost samples, and the sampler's `U` agrees
with `perf stat`'s CPUs-utilized to 0.8%/1.3% (section 5-c). Absolute core-seconds below
are the band percentage applied to the **per-statement** CPU from section 5-c (48.4559 and
22.0595 core-s), because the two 90 s windows contain different numbers of statements
(7.96 and 18.10) and raw window totals are not comparable.

### 6-a. CUBRID resolved-symbol bands (84.67% banded at the 0.3% cutoff)

| band | self % | core-s/stmt | top symbols |
|---|---|---|---|
| **A. UTF-8 LIKE predicate** | **33.01** | **15.995** | `lang_strmatch_utf8` 16.91, `qstr_eval_like` 7.40, `intl_utf8_to_cp` 3.53, `intl_nextchar_utf8` 1.77, `intl_utf8_to_cp@plt` 1.10, `intl_nextchar_utf8@plt` 0.63, `db_string_like` 0.41, `eval_pred` 1.26 |
| B. buffer fix/unfix and its mutexes | 21.07 | 10.210 | `pgbuf_fix_release` 13.86, `pgbuf_unfix` 3.49, `pgbuf_replace_watcher` 1.07, `__pthread_mutex_trylock` 0.98, `__pthread_mutex_unlock_usercnt` 0.86, `__pthread_mutex_lock` 0.47, `pgbuf_ordered_fix_release` 0.34 |
| C. record → `DB_VALUE` decode | 17.16 | 8.315 | `spage_get_record` 4.00, `heap_attrinfo_read_dbvalues` 2.89, `or_mvcc_get_repid_and_flags` 2.48, `mr_readval_string_internal` 1.51, `fetch_val_list` 1.28, `heap_prepare_get_context` 1.01, `qdata_generate_tuple_desc_for_valptr_list` 0.89, `pr_clear_value` 0.77, `heap_init_get_context` 0.68, `qdata_get_tuple_value_size_from_dbval` 0.51, `spage_get_record_data` 0.45, `qdata_copy_db_value_to_tuple_value` 0.38, `or_header_size` 0.31 |
| D. aggregation / hash group-by | 5.12 | 2.481 | `qexec_hash_gby_agg_tuple` 1.28, `mht_get` 0.82, `qdata_agg_hkey_compare` 0.79, `mht_get_hash_number` 0.64, `qdata_evaluate_aggregate_list` 0.63, `qdata_hash_agg_hkey` 0.57, `mht_rem` 0.39 |
| E. B-tree descent | 2.39 | 1.158 | `btree_search_nonleaf_page` 0.74, `btree_search_leaf_page` 0.51, `btree_compare_key` 0.42, `btree_record_process_objects` 0.38, `btree_select_visible_object_for_range_scan` 0.34 |
| F. scan + parallel-scan plumbing | 2.10 | 1.018 | `scan_next_scan_local` 0.76, `parallel_scan::result_handler<1>::write` 0.69, `qexec_execute_scan` 0.34, `parallel_scan::task<1,0>::drain_slot_oids` 0.31 |
| G. runtime / TLS / alloc / misc | 3.82 | 1.851 | `__tls_init` 0.96, `__tls_get_addr` 0.90, `malloc` 0.58, `tp_value_compare_with_error` 0.50, `__memmove_evex_unaligned_erms` 0.48, `logtb_find_isolation` 0.40 |
| **banded total** | **84.67** | **41.028** | remainder is the sub-0.3% tail: 726 flat lines, no `[unknown]`, no single symbol above the cutoff |

The call graph attributes band A unambiguously to the query's one data filter:

```text
lang_strmatch_utf8  <- qstr_eval_like <- db_string_like <- eval_pred <- eval_pred
  <- eval_data_filter <- scan_next_index_lookup_heap (inlined)
  <- scan_next_index_scan (inlined) <- scan_next_scan_local <- scan_next_scan
  <- qexec_execute_scan
  <- parallel_scan::task<(RESULT_TYPE)1,(SCAN_TYPE)0>::drain_slot_oids
  <- parallel_scan::task<…>::loop <- ::execute
  <- cubthread::worker_pool_impl<false>::core_impl::worker_impl::execute_current_task
```

16.90 of the 16.91 percentage points of `lang_strmatch_utf8` sit under that single stack.

### 6-b. PostgreSQL resolved-symbol bands (86.84% banded at the 0.3% cutoff)

| band | self % | core-s/stmt | top symbols |
|---|---|---|---|
| **A. UTF-8 LIKE predicate** | **12.57** | **2.773** | `UTF8_MatchText` 12.20, `textnlike` 0.37 |
| B. buffer pin/unpin, lookup, LWLock | 31.76 | 7.006 | `hash_search_with_hash_value` 10.19, `PinBuffer` 7.74, `LWLockAttemptLock` 6.69, `StartReadBuffer` 1.13, `LockBufferInternal` 1.07, `LWLockRelease` 1.06, `GetPrivateRefCountEntrySlow` 0.94, `UnpinBufferNoOwner` 0.87, `hash_bytes` 0.86, `BufferLockUnlock` 0.63, `ResourceOwnerForget` 0.58 |
| C. heap access / HOT prune / visibility | 22.19 | 4.895 | `heap_page_prune_opt` 12.77, `heap_hot_search_buffer` 6.75, `tts_buffer_heap_getsomeattrs` 1.74, `heapam_index_fetch_tuple` 0.58, `HeapTupleSatisfiesVisibility` 0.35 |
| D. generic expression evaluation | 5.33 | 1.176 | `ExecInterpExpr` 4.10, `check_stack_depth` 0.90, `FunctionCall2Coll` 0.33 |
| E. B-tree descent | 3.31 | 0.730 | `_bt_compare` 1.60, `_bt_readpage` 0.60, `_bt_binsrch` 0.40, `index_getnext_tid` 0.36, `_bt_check_compare` 0.35 |
| F. executor plumbing + aggregation | 3.88 | 0.856 | `ExecNestLoop` 0.93, `ExecAgg` 0.92, `__memcmp_evex_movbe` 0.73, `MemoryContextReset` 0.57, `ExecScan` 0.42, `shm_mq_send_bytes` 0.31 |
| G. kernel — mmap DSM fault-in and worker fork/exit | 7.80 | 1.721 | `next_uptodate_folio` 3.19, `folios_put_refs` 1.12, `folio_remove_rmap_ptes` 1.11, `filemap_map_pages` 0.93, `_compound_head` 0.89, `zap_present_ptes` 0.56 |
| **banded total** | **86.84** | **19.156** | remainder is the sub-0.3% tail: 1,280 flat lines, no `[unknown]` |

Band G is the cost of `dynamic_shared_memory_type=mmap` plus 24 statements' worth of
worker fork/exit inside a 90 s window; it is a **PostgreSQL-side overhead** that the
campaign's own contract (SSOT §9) introduces, and it is counted against PostgreSQL, not
excused.

### 6-c. Band-by-band, in absolute core-seconds per statement

| band | CUBRID | PostgreSQL | delta | ratio |
|---|---|---|---|---|
| **UTF-8 LIKE predicate** | **15.995** | **2.773** | **+13.222** | **5.7685x** |
| buffer fix/pin machinery | 10.210 | 7.006 | +3.204 | 1.4573x |
| record decode (CUBRID) vs heap access + prune (PostgreSQL) | 8.315 | 4.895 | +3.420 | 1.6987x |
| aggregation / grouping | 2.481 | 0.856 (F, incl. `ExecAgg`) | +1.625 | — |
| B-tree descent | 1.158 | 0.730 | +0.428 | 1.5863x |
| generic expression dispatch | 1.26% → 0.611 | 1.176 | −0.565 | 0.5196x |
| kernel | not observed above cutoff | 1.721 | −1.721 | — |
| **total per statement** | **48.4559** | **22.0595** | **+26.3964** | **2.1984x** |

Because the "LIKE band" boundary can be drawn in two defensible places, both bracketings
are given rather than the flattering one:

| bracketing | CUBRID | PostgreSQL | band ratio | share of the 26.3964 core-s gap |
|---|---|---|---|---|
| tight — matcher symbols only on both sides | 31.75% = 15.385 | 12.57% = 2.773 | **5.5483x** | **47.78%** |
| wide — plus each engine's generic per-row expression dispatch | 33.01% = 15.995 | 17.00% = 3.750 | **4.2653x** | **46.39%** |

**Under either bracketing, the UTF-8 LIKE predicate is ~46-48% of Q13's entire CPU gap,
at a 4.27x-5.55x band ratio.** That single band is the largest term in this query by a
wide margin.

## 7. Source contrast

| Item | CUBRID `file:line` | PostgreSQL `file:line` | Difference | Class |
|---|---|---|---|---|
| (1) Per-character UTF-8 LIKE comparison | `src/base/language_support.c:2852-2908` — the match loop calls `intl_utf8_to_cp()` on **both** operands (`:2857`, `:2858`) to build codepoints, then maps each through the collation weight table `weight_ptr[cp1]`/`weight_ptr[cp2]` (`:2877`, `:2893`) before comparing (`:2901`). `utf8_bin` is a binary collation whose weight for every codepoint is the codepoint itself, yet the loop still pays two decodes and two table lookups per character; there is no `memcmp`/byte-lockstep path and no ASCII fast path in the function | `src/backend/utils/adt/like.c:128-134` — for UTF-8 PostgreSQL compiles a **dedicated** specialization: `#define NextChar(p, plen) do { (p)++; (plen)--; } while ((plen) > 0 && (*(p) & 0xC0) == 0x80)` and `#define MatchText UTF8_MatchText`, i.e. character advance is a pointer increment plus a continuation-byte test on raw bytes — no decode, no table, no call. The general multibyte path it deliberately avoids is at `:96-98` (`pg_mblen_with_len`, `wchareq`) | CUBRID decodes and weight-maps both operands per character even for a binary collation; PostgreSQL compares raw bytes and only advances by character | **structural absence** |
| (2) Candidate-position search for `%pattern%` | `src/base/language_support.c:2831-2908` is re-entered per candidate start position from `qstr_eval_like`; every candidate position pays the full decode+weight loop from its first character | `src/backend/utils/adt/like_match.c:174-185` — the `%` scan tests `GETCHAR(*t) == firstpat`, **one byte compare per text byte**, and only calls `MatchText` recursively on a byte hit; `:366-372` further documents using `NextByte` rather than `NextChar` mid-match because "we must already have matched at least one byte of the character" | CUBRID has no cheap byte-level candidate rejection; PostgreSQL rejects non-candidates with a single byte compare | **structural absence** |
| (3) Admitting an index scan whose only value is ordering | `src/optimizer/query_planner.c:9239-9246` — a `QO_SCANMETHOD_INDEX_GROUPBY_SCAN` plan **is** generated when the node has no sargable terms but the query has a `GROUP BY` and `qo_validate_index_for_groupby()` passes. It is handed straight to `qo_check_plan_on_info()`, which at `:6014-6019` releases it if `plan->plan_un.scan.index->head->groupby_skip` is false. That flag is written **only** at `:1172-1175`, inside `qo_top_plan_new()`, and **only when the final top plan is itself `QO_PLANTYPE_SCAN`**. So whenever the query contains a join, the flag is still false at admission time, the plan is released at birth, and `qo_generate_seq_scan()` at `:9283` supplies the only surviving access path | `src/backend/optimizer/path/indxpath.c:965-966` — `if (index_clauses != NIL \|\| useful_pathkeys != NIL \|\| useful_predicate \|\| index_only_scan)` creates the index path **because the ordering is useful**, with no restriction to single-relation queries, and `:984-1003` creates the parallel variant of the same path with the same `useful_pathkeys` | CUBRID tests a flag that cannot yet be true at the point of the test; PostgreSQL tests the property itself | **structural absence** |
| (4) The same optimization's own `ORDER BY` twin, inside CUBRID | `src/optimizer/query_planner.c:6006-6012` — the `ORDER BY` arm of the *same function* reads `!(plan->top_rooted ? plan->plan_un.scan.index->head->orderby_skip : qo_plan_is_orderby_skip_candidate (plan))`, i.e. it has a **pre-top-rooted candidate predicate** (`:12559-12610`, which computes the sort list on the spot via `qo_plan_compute_iscan_sort_list()` at `:12603`). The `GROUP BY` arm at `:6015` has no such branch | — | This is an asymmetry **within CUBRID**, not between engines: the fix already exists three lines above the defect | **same stage, lower measured cost** (the `ORDER BY` path survives admission; the `GROUP BY` path does not) |
| (5) Propagating an index order through a join | `src/optimizer/query_planner.c:12271-12291` — `qo_plan_compute_iscan_sort_list()` **does** walk down a join (`case QO_PLANTYPE_JOIN: plan = plan->plan_un.join.outer;`), so CUBRID is architecturally able to read an ordering off a join's outer side; `:12310` then requires that leaf to satisfy `qo_is_interesting_order_scan()`. In Q13 the leaf is `sscan customer`, because item (3) already deleted the index alternative | `src/backend/optimizer/path/pathkeys.c:1294-1318` — `build_join_pathkeys()` returns the outer path's pathkeys unchanged for every join type **except** `JOIN_FULL`/`JOIN_RIGHT`/`JOIN_RIGHT_ANTI` (`:1303-1306`). Q13's join is `LEFT`, so the order survives; `src/backend/optimizer/util/pathnode.c:2420` stores it on the `NestPath` | Both engines can carry an order through a nested loop. Only PostgreSQL still has an ordered path to carry, because CUBRID discarded it at item (3) | **common to both engines** |
| (6) Consuming a pre-existing order in the grouping node | `src/query/query_executor.c:16605-16609` — the sort-free grouping routine `qexec_groupby_index()` is reachable only when `xasl->spec_list->indexptr->groupby_skip` is set, i.e. only when **this XASL's own first access spec** is an index scan carrying the flag; a join's XASL cannot satisfy that. `src/optimizer/query_planner.c:1192` is the consequence: `plan = qo_sort_new (plan, QO_UNORDERED, SORT_GROUPBY)` — an unconditional sort | `src/backend/optimizer/plan/planner.c:7959-8003` — `make_ordered_path()` returns the path **unchanged** when `pathkeys_count_contained_in()` says it is already sorted, inserting no Sort node at all; `:7436-7446` then builds `create_agg_path(..., AGG_SORTED, ...)` on top of it | CUBRID's streaming group-by is bound to a single access spec; PostgreSQL's is bound to a path property | **structural absence** |
| (7) Buffer fix / pin cost per page | `src/storage/page_buffer.c` `pgbuf_fix_release` — 13.86% self, plus `pgbuf_unfix` 3.49%, `pgbuf_replace_watcher` 1.07% and 2.31% of libpthread mutex traffic underneath them (`__pthread_mutex_trylock/lock/unlock_usercnt`), 10.210 core-s per statement | `src/backend/storage/buffer/bufmgr.c` `PinBuffer` 7.74%, `StartReadBuffer` 1.13%, `UnpinBufferNoOwner` 0.87% plus `hash_search_with_hash_value` 10.19% and `LWLockAttemptLock` 6.69%, 7.006 core-s per statement | For an **equal number of page fixes at the matched node** (19,504,609 vs 19,499,552, 1.000259x) CUBRID spends 1.4573x the CPU | **same stage, lower measured cost** |
| (8) Row materialisation | `src/storage/heap_file.c` `heap_attrinfo_read_dbvalues` 2.89%, `heap_prepare_get_context` 1.01%, `heap_init_get_context` 0.68%; `src/storage/slotted_page.c` `spage_get_record` 4.00%; `src/object/object_representation.c` `or_mvcc_get_repid_and_flags` 2.48%, `or_header_size` 0.31%; `src/object/object_primitive.c` `pr_clear_value` 0.77%; `mr_readval_string_internal` 1.51% — 8.315 core-s per statement building and tearing down typed `DB_VALUE`s | `src/backend/executor/execTuples.c` `tts_buffer_heap_getsomeattrs` 1.74% deforms into a flat `Datum`/`isnull` array with cached attribute offsets and **no per-value teardown**; the rest of PostgreSQL's 4.895 core-s band is `heap_page_prune_opt` 12.77% and `heap_hot_search_buffer` 6.75%, which are MVCC maintenance CUBRID does elsewhere | 1.6987x, but the two bands are not the same work — see section 8-c's explicit caveat | **same stage, lower measured cost** |

Searches performed for claims of absence, recorded per SSOT §17:
`grep -rn` over `src/base/language_support.c`, `src/base/intl_support.c` and
`src/query/string_opfunc.c` for `memcmp`, `bin`, `fast`, `ascii`, `lockstep`, `byte` in the
neighbourhood of `lang_strmatch_utf8`/`qstr_eval_like` — **no byte-lockstep or binary-
collation fast path exists**; the only branch on collation type inside the matcher is
`lang_coll->built_in && ignore_trailing_space` at `:2843`, which selects a *different
weight table*, not a different algorithm. For item (3), `groupby_skip` was traced through
every one of its 20 occurrences in `src/optimizer/` and `src/parser/` (`query_planner.c`,
`plan_generation.c`, `query_graph.c/.h`, `xasl_generation.c`); the flag is written in
exactly one place, `query_planner.c:1174`.

## 8. Causal decomposition details

### 8-a. What actually happens, in order

Both engines execute the same logical shape: read all 1,500,000 `customer` rows in
`c_custkey` order or not, probe `orders` through the FK index once per customer
(1,500,000 index searches, ~9.89 matches each), apply
`o_comment not like '%special%requests%'` to all 15,000,000 matched order rows, produce
15,337,604 join rows, group them into 1,500,000 per-customer counts, then group those into
46 distinct counts and sort.

The work is identical and independently verified identical (section 2). Both engines fix
essentially the same number of pages at the matched node (19,504,609 vs 19,499,552) and
both take zero physical reads. They differ in what each unit of that work costs.

### 8-b. Where the 2.246313x actually goes

`R_wall 2.246313x = F_units 1.029635x × F_cpu 2.198437x`. The units term is 2.96% and
essentially closed: both engines run ~4.25-4.44 active units, both confirmed by three
instruments. **97% of the gap is `F_cpu`, and `F_work = 1.000000` exactly, so all of
`F_cpu` is `F_cost` — CPU per identical unit of work.**

Per statement, CUBRID spends 48.4559 core-s against PostgreSQL's 22.0595, a gap of
26.3964 core-s. The profile assigns it:

| contributor | core-s of the gap | share | supporting evidence |
|---|---|---|---|
| **UTF-8 LIKE matcher** | **+12.245 to +13.222** | **46.4%-47.8%** | section 6-c both bracketings; source contrast items (1)-(2) |
| buffer fix/pin machinery | +3.204 | 12.1% | section 6-c; equal page-fix counts at the matched node |
| row materialisation vs heap access | +3.420 | 13.0% | section 6-c, with the caveat in 8-c |
| grouping (the plan-shape term) | +1.625 profiled; 2,202 ms of 13,357 ms traced wall | ~6% of CPU, 16.5% of traced wall | section 5-a; the 1.5617x controlled A/B below |
| B-tree descent | +0.428 | 1.6% | section 6-c |
| everything else incl. PostgreSQL-side kernel/DSM cost | remainder | ~20% | sub-cutoff tail on both sides |

The instruction-count reconstruction corroborates the shape of this: CUBRID retires
3.1220x the instructions per statement at 1.4538x the IPC (section 3-a). A 3.12x
instruction ratio for provably identical work is a per-row code-path finding, and the
profile says nearly half of it is one function.

### 8-c. Bounding the plan-shape term, and why it is not `F_plan`

The grouping difference is real and it was measured directly, but not as `F_plan`.

**Direct same-engine A/B on CUBRID** (`q13-gbo-*-cubrid.out`, five repeats each, each side
load-gated, medians shown). Every side produces the same 1,500,000 groups over the same
1,500,000 `customer` rows with the same aggregate and the same output:

| side | statement | estimated plan | median |
|---|---|---|---|
| A | `select c_custkey, count(*) from customer group by c_custkey` | `iscan pk_customer_c_custkey (covers)` + **`/* ---> skip GROUP BY */`** | **0.883 s** |
| B | `select c_custkey, count(*) from customer, region where r_regionkey = 0 group by c_custkey` | **`temp(group by)` + `sort: 1 asc`** over `nl-join`/`sscan customer` | **1.379 s** |
| B′ | B with `/*+ USE_IDX(customer pk_customer_c_custkey) */` | **byte-identical plan text to B** | **1.371 s** |
| C | `select count(*) from customer, region where r_regionkey = 0` | `nl-join`, no temp, no sort | 0.671 s |
| D | `select count(*) from customer` | `sscan`, answered from statistics | 0.001 s |

Adding **one 1-row cross join** — which cannot change the grouping work — costs
**1.5617x** and flips the plan from streaming to materialise-and-sort. B′ is the runtime
confirmation of source-contrast item (3): an explicit positive index hint **cannot** reach
the streaming plan, because the plan is released inside `qo_check_plan_on_info()` before
`qo_node_using_index_forced()` at `query_planner.c:9277` ever gets to suppress the
sequential scan. D is reported but is **not** a usable baseline — 0.001 s means CUBRID
answered `count(*)` from catalog statistics, so the (B−A)−(C−D) subtraction is not
available and is not attempted.

**Direct same-engine A/B on PostgreSQL** (`q13-groupby-ab-*-pg.out`), the mirror
experiment, where `offset 0` blocks subquery pull-up:

| side | plan | median |
|---|---|---|
| A | `GroupAggregate` over `Index Only Scan using customer_pkey` | 523.773 ms |
| B | `HashAggregate` over the same scan | 904.450 ms |

PostgreSQL pays **1.7268x** for losing the same optimization. So the mechanism is worth a
comparable multiple on both engines; CUBRID's problem is not that streaming grouping is
less valuable to it, it is that CUBRID cannot choose it.

**Why none of this is `F_plan`:**

- The CUBRID A/B is on an *isolated 1.5M-group aggregate*, not on Q13. It sizes the
  mechanism, it does not decompose Q13's wall.
- The PostgreSQL `noparallel`/`nonestloop` variants change join method **and** grouping
  method **and** parallelism simultaneously (section 4-d), so their 2.6891x cannot be
  attributed to the shape alone.
- Nothing available forces PostgreSQL to keep the index nested loop while losing only the
  ordering, and nothing available gives CUBRID the ordered path at all — that absence is
  the finding.

The honest bound from Q13's own trace is therefore: the inner `GROUP BY` is **2,202 ms of
13,357 ms traced wall, 16.4857%**, and PostgreSQL's entire equivalent grouping apparatus is
946.9 ms with no 15.3M-row sort. That band is what source-contrast items (3)-(6) would
address. It is a real, well-localised ~16% — and it is **not** Q13's dominant term.

### 8-d. Explanations considered and REJECTED, with the number that rejected each

1. **"PostgreSQL wins Q13 because it parallelises and CUBRID does not."** REJECTED.
   `F_units = 1.029635x`. CUBRID's trace reports `parallel workers: 5` on the driving scan;
   PostgreSQL reports `Workers Launched: 4` plus a participating leader. Measured active
   units: CUBRID `U` 4.25201 / TWU 4.2459 / peak 5.3223; PostgreSQL `U` 4.37802 / TWU
   4.4629 / peak 4.7943. `perf stat` independently reports 4.285 vs 4.436 CPUs utilized.
   The units term explains 2.96% of a 124.6% gap. A controlled same-engine serialisation
   of CUBRID (`noparscan2`, hint on both blocks) measures `U` 1.00238 against the native
   4.25201 and reproduces the resulting wall ratio to 0.057% (section 4-d item 4), so the
   unit counts are not in doubt from either direction.
2. **"CUBRID re-reads pages that PostgreSQL keeps resident (IMP-002/IMP-010/IMP-018)."**
   REJECTED, twice over. `/proc/<server>/io read_bytes` is **0** for both engines,
   `Num_data_page_ioreads` delta is 0, `pg_stat_database.blks_read` delta is 0, and the
   serial-vs-parallel probe puts CUBRID's page fixes within **0.00067%** of each other
   (22,649,042 vs 22,648,891). Q13's working set is resident in both 8192 MB budgets.
   There is no I/O term in this query at all.
3. **"CUBRID does more work — more rows, more page fixes."** REJECTED. Ground truth `G0`-`G8`
   is identical on both engines including the 15,337,604-row join output, and the matched
   node's page fixes agree to 1.000259x. Whole-statement page fixes differ more
   (22,649,042 vs 19,505,873 = 1.161140x), and that 1.16x is honestly *part* of the story —
   but it cannot produce a 2.198x CPU ratio on its own, and section 6-c shows the CPU is
   concentrated in a band (the LIKE matcher) that runs the same 15,000,000 times on both
   engines.
4. **"It is the 15.3M-row temp materialisation and sort."** REJECTED as the *dominant*
   cause, retained as a real ~16% contributor. The trace puts the inner `GROUP BY` at
   2,202 ms of 13,357 ms; the profile puts CUBRID's whole aggregation band at 5.12% =
   2.481 core-s of 48.4559. Both readings say the same thing: this is a sixth of the
   problem, not the problem. Section 8-c gives it its own controlled A/B rather than
   folding it into a factor.
5. **"CUBRID is memory-stalled / cache-hostile on this access pattern."** REJECTED, and
   the counter runs the *other* way: CUBRID's IPC is **1.73** against PostgreSQL's
   **1.19**. CUBRID's pipelines are better fed; it simply issues 3.1220x the instructions.
6. **"The LIKE gap is a collation/charset artifact — PostgreSQL is on a byte path and
   CUBRID on a Unicode path."** REJECTED, and this was checked before the band was
   interpreted. `tpch_sspq` is encoding **UTF8**, so `like.c:156-161` routes to
   `UTF8_MatchText`, not the `SB_MatchText` single-byte path; CUBRID's column is
   `COLLATE utf8_bin` under `intl_collation=utf8_bin`. Both engines run a UTF-8,
   deterministic, binary-ordering LIKE over the same bytes. The difference is that
   PostgreSQL wrote a UTF-8 specialization that compares raw bytes
   (`like.c:128-134`, `like_match.c:174-185`) and CUBRID decodes both operands to
   codepoints and weight-maps them per character (`language_support.c:2852-2908`) even
   though `utf8_bin`'s weight function is the identity.
7. **"PostgreSQL's plan is simply better, so CUBRID's executor is fine."** REJECTED. When
   PostgreSQL is denied its ordered parallel path it takes **13.678 s**, i.e. CUBRID is
   **1.1972x faster** than PostgreSQL on the shape CUBRID is confined to. The plan is worth
   a lot, but the executor gap is real and separable, and it is where 46-48% of the CPU
   difference lives.

### 8-e. What is left, and in what order

Fixing the LIKE matcher (IMP-004) addresses 12.245-13.222 core-s of the 26.3964 core-s
gap. If that band were brought to PostgreSQL's absolute cost, CUBRID's per-statement CPU
would fall from 48.4559 to ~35.2-36.2 core-s and, at an unchanged `U` of 4.25201, wall
would fall from 11.426 s to ~8.3-8.5 s — `R_wall` ~1.63-1.67x instead of 2.2463x. That is
a projection, marked as such, not a measurement.

Fixing the group-by-skip admission gap (new IMP-021) addresses a further ~16.5% of
CUBRID's traced wall. The two are independent: one is an executor per-character cost, the
other an optimizer plan-space defect.

## 9. Improvements

Ledger synced and searched before allocation. The dedup search is recorded in
`q13-registry-dedup.txt`: four searches over all 20 existing candidates by root-cause
title, by CUBRID source location, by PostgreSQL source location and by root cause, for
the terms `group by skip`, `groupby_skip`, `interesting order`, `pathkeys`, `sort group
by`, `qo_check_plan_on_info`, `INDEX_GROUPBY_SCAN`, `streaming aggregate`.

### New candidate

**IMP-021 (P1, optimizer, difficulty medium).** *A group-by-skip index scan plan is
released at birth whenever the query contains a join, because
`qo_check_plan_on_info()` tests a flag that is only written after top-plan rooting —
while the `ORDER BY` twin six lines above it tests a candidate predicate instead.*

- **Mechanism, CUBRID side.** For a query with `GROUP BY` and no sargable term on the
  grouping column, `query_planner.c:9239-9246` deliberately creates a
  `QO_SCANMETHOD_INDEX_GROUPBY_SCAN` plan whose only value is the ordering it supplies,
  and passes it to `qo_check_plan_on_info()`. That function releases it at `:6014-6019`
  unless `plan->plan_un.scan.index->head->groupby_skip` is already true. The flag is
  written in exactly one place — `:1172-1175`, inside `qo_top_plan_new()` — and only when
  the final top plan is `QO_PLANTYPE_SCAN`. During bottom-up join enumeration the plan is
  not top-rooted and the top plan is not a scan, so the flag is false, the plan dies, and
  `qo_generate_seq_scan()` at `:9283` becomes the only access path for that relation.
  Downstream, `:1192` inserts an unconditional `qo_sort_new(plan, QO_UNORDERED,
  SORT_GROUPBY)` and `query_executor.c:16605-16609` can never reach the sort-free
  `qexec_groupby_index()`. The machinery to carry an order through a join already exists
  and is unused: `qo_plan_compute_iscan_sort_list()` walks a join's outer side at
  `:12279-12281`.
- **Contrasting mechanism, PostgreSQL side.** `indxpath.c:965-966` admits an index path
  when `useful_pathkeys != NIL` even with zero index clauses, and `:984-1003` admits its
  parallel twin; `pathkeys.c:1294-1318` preserves the outer's pathkeys across every join
  type except FULL/RIGHT/RIGHT_ANTI; `pathnode.c:2420` stores them on the `NestPath`;
  `planner.c:7959-8003` then adds **no** Sort when `pathkeys_count_contained_in()` is
  already satisfied, and `:7436-7446` builds `AGG_SORTED` on top. PostgreSQL tests the
  ordering property; CUBRID tests a flag that cannot yet be set.
- **Quantified expected effect, mapped to a named band.** Direct same-engine A/B:
  **1.5617x** (0.883 → 1.379 s) on an isolated 1,500,000-group aggregate where the only
  change is one 1-row cross join. On Q13 itself the addressable band is the inner
  `GROUPBY` node, **2,202 ms of 13,357 ms traced wall (16.4857%)** plus its 20,861-page
  (326 MiB) temp materialisation; profile band D is 5.12% = 2.481 core-s per statement.
  PostgreSQL's mirror A/B values the same optimization at **1.7268x** (523.773 →
  904.450 ms), so the effect is not CUBRID-specific pessimism.
- **Implementation direction.** Mirror `:6007-6008` in the `GROUP BY` arm: replace
  `!plan->plan_un.scan.index->head->groupby_skip` at `:6015` with
  `!(plan->top_rooted ? plan->plan_un.scan.index->head->groupby_skip :
  qo_plan_is_groupby_skip_candidate (plan))`, adding the candidate predicate as the exact
  analogue of `qo_plan_is_orderby_skip_candidate()` (`:12559-12610`) — it already has the
  `group_by` parameter it needs, since `qo_plan_compute_iscan_sort_list()` accepts one.
  Then let `qo_top_plan_new()` set the flag on the surviving plan as it does today.
- **Validation criteria.** (1) Q13's CUBRID estimated plan shows an ordered `customer`
  access with `/* ---> skip GROUP BY */` and no `sort: 1 asc` above the join, and the
  20,861 temp pages go to zero in the trace; (2) result equivalence re-proved by the
  §11 gate — 46 rows, exact ordered match; (3) the A/B in section 8-c collapses toward
  1.0x; (4) no regression on Q01-Q12's plans, since the change only *admits* a plan that
  the existing cost model may still reject; (5) the left-outer-join null-extension
  semantics must be preserved — the ordering comes from the *outer* (preserved) side, and
  `query_planner.c:12621-12628` already documents the RIGHT-outer restriction that the new
  predicate must respect, exactly as `build_join_pathkeys()` does at `pathkeys.c:1303-1306`.
- **Correctness/regression risk.** Medium. The change admits plans, it does not force
  them, and the group-by-skip execution path (`qexec_groupby_index()`) is long-standing
  and already exercised by single-table queries. The specific hazard is an ordering claim
  that a join type does not actually preserve; the validation criteria pin that.
- **Relations.** Predecessor: none. Alternatives: none in the ledger. Containment: distinct
  from IMP-015 (which is about the sort-based group-by running single-threaded once it
  exists) and from IMP-016/IMP-017 (which are about hash aggregation being abandoned).
  IMP-021 is about the sort never being needed in the first place. Affected queries: Q13
  (measured). Any Q01-Q22 query grouping on a key an index already orders, behind a join,
  is a candidate — not asserted for any query that has not been measured.
- **Priority justification.** P1, not P0: the measured band is 16.4857% of CUBRID's traced
  Q13 wall, which is real and localised but roughly a third of what IMP-004 is worth on the
  same query (46-48% of the CPU gap).
- **Difficulty justification.** Medium: a localized predicate addition whose analogue
  already exists in the same function, but it needs a correct join-type guard.
- **Upstream precedent.** Yes, and it is in this very source tree: **CBRD-26906**, cited in
  the comment at `query_planner.c:9257-9260` ("an interesting-order (group-by / order-by
  skip) index scan also means the hinted index is usable, so a positive index hint that
  only provides ordering (no key-range) still suppresses the sequential scan below"), is
  the same class of change — teaching the planner that an index whose only contribution is
  ordering is still a real alternative. IMP-021 extends that reasoning from the hint path
  to the admission path.
- Status: **measured**.

### Existing candidates given a Q13 relation and Q13 evidence (no new ID)

- **IMP-004** (P1, expression/type) — *UTF-8 LIKE matcher decodes both operands to
  codepoints per character through non-inlined PLT calls and maps each codepoint through a
  collation weight table, with no byte-lockstep comparison and no ASCII fast path.*
  **Q13 is by a wide margin its largest measurement and should raise it to P0 at the next
  ledger review.** 33.01% of CUBRID's Q13 CPU (15.995 core-s per statement) against
  PostgreSQL's 12.57% (2.773 core-s) — a **5.5483x** band ratio on the tight bracketing and
  4.2653x on the wide one, contributing **46.4%-47.8% of Q13's entire 26.3964 core-s CPU
  gap**. The predicate is evaluated 15,000,000 times per statement (trace: B-tree
  `rows: 15000000`, lookup `rows: 14837583`, difference 162,417 = ground truth `G2`).
  Q13 also adds two source facts the earlier queries did not have: the profile shows
  `intl_utf8_to_cp@plt` (1.10%) and `intl_nextchar_utf8@plt` (0.63%) as *separate PLT
  symbols*, i.e. the per-character decode is genuinely not inlined; and
  `language_support.c:2843-2846` proves the only collation-dependent branch inside the
  matcher selects a different **weight table**, never a different algorithm — so
  `utf8_bin`, whose weight function is the identity, still pays two decodes and two table
  lookups per character. Charset/collation parity with PostgreSQL was verified before this
  attribution (section 1, section 8-d item 6).
- **IMP-013** (P1, buffer/IO) — Q13 confirms it under the cleanest possible conditions:
  **equal page-fix counts at the matched node** (19,504,609 vs 19,499,552, 1.000259x) and
  **zero physical reads on both sides**, yet CUBRID spends 10.210 core-s per statement in
  `pgbuf_fix_release`/`pgbuf_unfix`/`pgbuf_replace_watcher` plus 2.31 percentage points of
  libpthread mutex traffic, against PostgreSQL's 7.006 core-s — **1.4573x**. Every previous
  measurement of IMP-013 was confounded by differing miss counts; this one is not.
- **IMP-020** (P0, expression/type + storage) — band C, 17.16% = 8.315 core-s per statement
  (`spage_get_record`, `heap_attrinfo_read_dbvalues`, `or_mvcc_get_repid_and_flags`,
  `mr_readval_string_internal`, `pr_clear_value`, `qdata_copy_db_value_to_tuple_value`)
  against PostgreSQL's `tts_buffer_heap_getsomeattrs` at 1.74%. **Caveat recorded rather
  than glossed:** the 1.6987x in section 6-c compares CUBRID's decode band against
  PostgreSQL's whole heap-access band, and 19.52 of PostgreSQL's 22.19 percentage points
  are `heap_page_prune_opt` + `heap_hot_search_buffer`, which are MVCC maintenance rather
  than tuple deforming. On the narrow comparison — CUBRID's 8.315 core-s of decode against
  PostgreSQL's `tts_buffer_heap_getsomeattrs` 0.384 core-s — the ratio is far larger, but
  the two are not exact functional equivalents either, so **no single number is claimed**;
  the defensible statement is that CUBRID's per-row materialisation band is 8.315 core-s
  per statement for 15,337,604 rows = 542 ns/row.
- **IMP-005** (P2, parallelism) — new instance. The Q13 trace reports
  `ORDERBY (time: 0, sort: true, page: 20861, ioread: 0)` for a **46-row** sort; 20,861 is
  the inner `GROUPBY`'s temp page count re-reported at an ancestor node. Confirms the
  merge-once-per-`scan_ptr`-level-and-again-per-subtree defect on a new plan shape.
- **IMP-010** (P1, buffer/IO + parallelism) — **bounded by a negative result**, recorded
  because it is evidence. Parallel vs serial page fixes differ by 0.00067% (22,649,042 vs
  22,648,891) with zero physical reads on both. IMP-010's damage mechanism is re-reading;
  Q13 has nothing to re-read. This narrows IMP-010's scope to the
  working-set-exceeds-pool regime rather than weakening the finding.
- **IMP-002 / IMP-018** — explicitly **not** given a Q13 relation. Both are about buffer
  retention failures, and Q13 measured zero physical reads on both engines; there is no
  retention failure here to relate them to.

### Ranking, against the measured bands

1. **IMP-004** — 46.4%-47.8% of the CPU gap, one function, and PostgreSQL's own source
   shows the fix shape (a UTF-8 specialization that advances by pointer increment and
   compares bytes). Highest measured value, clearest precedent.
2. **IMP-013** — 12.1% of the gap, now measured free of any miss-count confound.
3. **IMP-020** — 13.0% of the gap by the band comparison, but the band boundaries are not
   exact functional equivalents, so it is ranked below IMP-013 despite the larger nominal
   delta.
4. **IMP-021** (new) — 16.5% of CUBRID's traced wall, a distinct optimizer defect with a
   three-line analogue already in the same function, and a 1.5617x direct A/B.
5. **IMP-005** — instrumentation correctness, no wall-clock value.

## 10. Evidence index

Format: `claim → raw file → formula → evidence type → SHA-256`. All paths relative to
`/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q13/`; SHA-256 values are in
`reports/Q13/raw-manifest.json`, which is the authoritative checksum list for every
artifact named here.

| claim | raw file | formula | evidence type |
|---|---|---|---|
| `R_wall` 2.246313x | `Q13-cubrid-headline-block1.json`, `Q13-postgresql-headline-block1.json` | `median(measured_times_s)` ratio | direct A/B |
| block spreads 0.4980% / 0.4554% | `Q13-{engine}-headline-block{1,2,3}.json` | `(max−min)/median` of the three block medians | direct measurement |
| every block accepted attempt 1, `CLEAN` | `Q13-{engine}-bgload-block{1,2,3}.json` | `verdict`, `external_max` | direct measurement |
| WARM gate derivation | `q13-warm-gate-params.txt`, `q13-convergence-{cubrid,pg}.json` | half-split trend, trailing spread over 40 statements | direct measurement |
| correctness `result-equivalent-at-SF10` | `q13-correctness.json`, `q13-correctness-{cubrid,postgresql}.out` | ordered exact compare, 46 rows | direct A/B |
| ground truth `G0`-`G8` identical | `q13-groundtruth-cubrid.out`, `q13-groundtruth-pg.out` | independent per-engine `count(*)`/`count(distinct)` | direct A/B |
| `F_work = 1.000000` | same, row `G4` | 15,337,604 / 15,337,604 | direct A/B |
| `F_units`, `F_cpu`, `U`, TWU, executor/auxiliary split | `Q13-{engine}-headline-telemetry-run{1,2,3}.json`, `…-intervals-run{1,2,3}.json` | `U=CPU/t_block`; TWU by actual sample timestamp deltas | direct measurement |
| CUBRID estimated plan | `q13-plan-est-cubrid.out`, `.sql`, `.time` | SQL `SET OPTIMIZATION LEVEL 514`, non-executing | plan text |
| PostgreSQL estimated plan | `q13-plan-est-pg.out`, `.sql` | `EXPLAIN (COSTS, VERBOSE, SETTINGS)` | plan text |
| CUBRID node times, 15,000,000 predicate evaluations, 20,861 temp pages | `q13-trace-cubrid.out`, `q13-trace-cubrid.sql` | `SET TRACE ON` / `SHOW TRACE` | direct measurement |
| PostgreSQL node times, 19,503,684 buffers, `Heap Fetches: 0` | `q13-plan-act-pg.out`, `q13-plan-act-pg.sql` | `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, TIMING)` | direct measurement |
| zero physical reads, both engines | `Q13-cubrid-buffer-io-diag.json`, `Q13-postgresql-buffer-io-diag.json`, `q13-{engine}-io-{mid,post}.txt` | `read_bytes` delta; `blks_read` delta; `Num_data_page_ioreads` delta | direct measurement |
| statdump zero-delta instrument failure | `q13-cubrid-statdump-{pre,mid,post}.txt` | delta across 4 statements = 0 while a single traced statement moves 22.6M | invalid artifact, recorded |
| serial vs parallel page fixes 0.00067% apart | `q13-serial-statdump-{parallel,serial}-{pre,post}.txt`, `q13-serial-io-*` | `Num_data_page_fetches` delta | direct A/B |
| CUBRID profile bands, 0 unknown symbols | `profile-cubrid-flat.txt`, `profile-cubrid-callgraph.txt`, `perf-stat-cubrid.txt`, `perf-record-cubrid.log` | `perf report -F overhead,symbol --percent-limit 0.3`; band % × per-statement CPU | profile attribution |
| PostgreSQL profile bands, 0 unknown symbols | `profile-pg-flat.txt`, `profile-pg-callgraph.txt`, `perf-stat-pg.txt`, `perf-record-pg.log` | same | profile attribution |
| `F_cpu` reconstructed from PMU counters to +0.1782% | `perf-stat-cubrid.txt`, `perf-stat-pg.txt` | `(I_C/I_P)×(IPC_P/IPC_C)×(f_P/f_C)` | direct measurement |
| group-by-skip capability probe | `q13-groupby-skip-probe.out`, `.sql` | 5 estimated plans; `/* ---> skip GROUP BY */` present without a join, absent with one | plan text |
| CUBRID mechanism A/B 1.5617x, hint-immunity | `q13-gbo-{a,b,bp,c,d}-cubrid.out`, `q13-gbo-plan-cubrid.out` | median of 5 per side; B/A | direct A/B |
| PostgreSQL mirror A/B 1.7268x | `q13-groupby-ab-{a,b}-pg.out`, `q13-groupby-ab-plan-pg.out` | median of 5 per side | direct A/B |
| controlled variant blocks | `Q13-cubrid-noparscan-*.json`, `Q13-postgresql-{noparallel,nonestloop}-*.json`, `q13-plan-est-{cubrid-noparscan,pg-noparallel,pg-nonestloop}.out`, `q13-plan-act-pg-{noparallel,nonestloop}.out` | same section-12 block regime and load gate as native | direct A/B |
| charset/collation parity | section 1 row; `q13-preflight`/live catalog reads recorded in `preflight-Q13.txt` | `pg_database.datcollate`, `show create table orders` | configuration verification |
| identity, ownership, cpuset, FK/index gate, statistics, query provenance | `preflight-Q13.txt` (this session), `q13-preflight-predecessor-session.txt` | see file | configuration verification |
| post-block ownership / cpuset / orphan re-verification | `q13-postcheck.txt` | see file | configuration verification |

## 11. Notion sync

**Not performed by this session, by contract.** SSOT §21's execution boundary states that
the GJC/tmux worker session runs on the remote build host, has no Notion connector, and
**must never attempt a Notion write**; its Notion-adjacent duty ends at committing and
pushing the report, manifest and improvement ledger to `origin/main`. No Notion tool call
was issued at any point in this session.

Write path used: **path 3 of 3** — an idempotent record appended to
`reports/notion_backfill_pending.jsonl`, carrying the full section-21 payload (causal
multiplier card with the factor table, headline timings, plan comparison for both engines,
profiling top-cost symbols for both engines, the full source contrast with `file:line` on
both sides, the causal decomposition narrative including rejected explanations and the
numbers that rejected them, and every improvement candidate with its complete section-18
content). Write paths are not mixed: paths 1 and 2 were not attempted.

Idempotency key, per SSOT §21:
`campaign_id + QNN + session_id + report_commit + content_fingerprint`.

The pending record must be cleared only after a server-side refetch by the section-23
reconciler subagent or a purpose-spawned catch-up subagent with Notion tool access,
reading the pushed GitHub commit as source of truth. This session does not clear it.

## 12. Completion checklist

| SSOT §26 gate | Status |
|---|---|
| preflight and correctness status recorded | **yes** — `preflight-Q13.txt` (re-captured under this session's ID), `q13-correctness.json`, `result-equivalent-at-SF10` |
| three valid headline values for each completing engine | **yes** — three measured statements per engine in contract block1, plus two further accepted blocks per engine as stability evidence; all six accepted on attempt 1 with `CLEAN` load verdicts |
| timeout confirmations if censored | **n/a** — not censored; 11.43 s and 5.09 s against a 300 s timeout |
| plan, execution, profile and source contrast sections complete | **yes** — sections 4, 5, 6, 7; both profiles have zero `[unknown]` symbols and zero lost samples |
| causal multiplier card has evidence or explicit `UNMEASURED` factors | **yes** — `F_units`, `F_cpu`, `F_work`, `F_cost` measured with unit/denominator/formula/pointer/evidence-type; `F_plan` explicitly `UNMEASURED` with the reason stated and the magnitude bounded in section 8-c |
| reconstruction residual shown and inside the error budget | **yes** — +0.7691% against a 0.9534% budget stated before interpretation |
| Git improvement ledger deduplicated and committed | **yes** — `q13-registry-dedup.txt` records the four searches over all 20 prior candidates; IMP-021 allocated; Q13 relations and evidence added to IMP-004, IMP-005, IMP-010, IMP-013, IMP-020 |
| Notion relations synced **or** an idempotent backfill record durable | **backfill record durable** — write path 3; §21 forbids this session from writing to Notion |
| every claim indexed to raw evidence and checksum | **yes** — section 10 plus `reports/Q13/raw-manifest.json` |
| report, manifest and registry committed, pushed, reachable from `origin/main` | **yes** — see the identity line in the backfill record for the exact `report_commit` |
| `QUERY_COMPLETE` emitted | **yes** |
| current session removed and absence verified | **owed by the controller.** A GJC session cannot remove itself, and this session was explicitly instructed not to. SSOT §22 steps 7-8 (`gjc session remove <exact-id>`, then absence verified with **both** `gjc session status gajae_code_ms9ecbdx_vugn5vtz` and `tmux has-session -t gajae_code_ms9ecbdx_vugn5vtz`) are the transition owner's step, and only then may the Q14 session be created |

### Stage ledger

| stage | status |
|---|---|
| 14.1 identity/schema/ownership/NUMA/cpuset preflight | complete, re-captured under this session's ID |
| 14.2 correctness gate | complete — `result-equivalent-at-SF10`, 46 rows, plus ten cross-engine ground-truth cardinalities |
| 14.3 estimated plans without execution | complete — both engines, plus five capability probes and four variant plans |
| 14.4 CUBRID WARM + 3 headline runs | complete — three blocks, all accepted attempt 1 |
| 14.5 PostgreSQL WARM + 3 headline runs | complete — three blocks, all accepted attempt 1 |
| 14.6 actual plans and CUBRID trace, non-headline | complete — `SET TRACE ON`/`SHOW TRACE`, `EXPLAIN ANALYZE BUFFERS`, four controlled variants |
| 14.7 CPU/thread, `/proc` I/O, iostat, NUMA, buffer diagnostics | complete — three telemetry runs per engine plus one diagnostic block per engine |
| 14.8 perf cycles/instructions/call-graph | complete — verified PID sets, 0 unknown symbols, 0 lost samples, coverage validated against `perf stat` |
| 14.9 CUBRID and PostgreSQL `file:line` | complete — eight-row source contrast with citations on both sides |
| 14.10 causal multiplier decomposition | complete — card, residual, error budget, independent PMU reconstruction |
| 14.11 improvement registry deduplication and relations | complete — IMP-021 allocated, five existing candidates given Q13 relations, two explicitly excluded |
| 14.12 raw manifest, report, Git commit, Notion backfill | complete — write path 3 only |
| 14.13 completion checklist and `QUERY_COMPLETE` | complete |
| 14.14 session removal and absence verification | owed by the controller (see above) |

### Late-arriving artifact

The corrected CUBRID units anchor `noparscan2` (the `/*+ NO_PARALLEL_SCAN */` hint applied
to **both** query blocks, whose estimated plan is identical to native apart from the hint
text) completed both its contract block and its telemetry run: WARM steady state
**47.140999 s**, block median **47.388998 s**, `U` **1.00238**, TWU 1.0022, total query CPU
189.670 core-s, accepted on attempt 1 with a `CLEAN` load verdict. Section 4-d item 4 uses
it to close the units identity to **0.057%** and to show that CUBRID's parallelism costs
only 2.34% extra CPU. The first `noparscan` variant's void status is documented in
section 4-d with the plan-text proof.

### Invalid / excluded artifacts, preserved as evidence

- `INVALID-overlapped-q13-convergence-cubrid.{log,bgload.json}` plus a `.README`
  explaining the cause: a predecessor session left a detached tmux session running the
  CUBRID convergence probe, which overlapped this session's preflight `COUNT(*)` sweep on
  the same SUT cpuset. Both were terminated, orphan and ownership state was re-verified
  clean (`csql=0 psql=0`, no PostgreSQL parallel workers, no CUBRID transactions), and the
  probe was re-run from scratch. Nothing from that attempt feeds any reported number.
- `q13-cubrid-statdump-{pre,mid,post}.txt` — zero delta on every `Num_data_page_*` counter
  across the four-statement diagnostic block, while a single isolated traced statement in
  the serial/parallel probe moved `Num_data_page_fetches` by 22,649,042. The diagnostic
  reading is discarded as an instrument failure; the probe reading is used. Same defect
  Q12 recorded.
- `Q13-cubrid-noparscan-*` — retained and reported, but **void as a units anchor**: the
  hint reached only the outer query block, proved by `diff`ing its estimated plan against
  native. Superseded by `noparscan2`.
- The `ORDERBY … page: 20861` field in `q13-trace-cubrid.out` — a fresh IMP-005 instance,
  excluded from every calculation.

`QUERY_COMPLETE`
