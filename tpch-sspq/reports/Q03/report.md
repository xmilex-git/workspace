# TPCH-SSPQ FK campaign — Q03 report

## 3-a. Causal multiplier card

```text
R_wall 1.374233x [wall, median of 3 per engine; PostgreSQL is 1.3742x faster]
= F_plan  0.707996x [plan-shape; same-engine CUBRID A/B, native idx-join vs controlled hash-join]
× F_units 0.851451x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   2.256272x [total query CPU-seconds]

F_cpu 2.256272x [total query CPU-seconds]
= F_work 0.998080x [plan-node tuple touches: 118,590,174 vs 118,818,354]
× F_cost 2.260614x [total-query CPU-seconds per plan-node tuple touch]
```

**`F_plan` is a measured number for Q03, not `UNMEASURED`.** CUBRID's `/*+ USE_HASH */`
hint reproduces PostgreSQL's plan shape *exactly* — the same three sequential scans,
the same two hash joins in the same order, and identical row counts at every node
(section 4). That gives the same-engine controlled A/B section 16 requires: CUBRID's
native index-nested-loop plan is **1.4125x faster than CUBRID's own hash-join plan**
(4.808 s vs 6.791 s), so `F_plan = 0.707996`. Anchor direction is native →
controlled(hash), and `F_units`/`F_cpu` are therefore computed on the **controlled**
cross-engine pair (CUBRID-hash vs PostgreSQL-hash) with controlled denominators on
both sides and no mixing of native and controlled values.

Read in the direction of the loss: PostgreSQL is **1.3742x faster**. CUBRID's own plan
choice is *good* — it earns back **1.4125x** — but at the matched plan shape CUBRID
burns **2.2563x** the CPU for **the same work** (`F_work = 0.9981`), and only 1.1755x
of that is recovered by running at higher parallel utilization (`1/F_units`). Inside
`F_cpu`, work volume is a wash by construction and the entire factor is per-tuple
cost: **424.7 ns vs 187.8 ns per tuple touch**.

Reconstruction: `0.707996 × 0.851451 × 2.256272 = 1.360135` vs headline `1.374233`.
**Residual = −1.0259%.** Measured error budget: within-block relative sd 0.385%
(CUBRID) and 0.042% (PostgreSQL), 0.387% combined in quadrature — which alone does
*not* cover the residual. The remainder is a fully measured regime offset: the
stage-14.7 telemetry runs that supply the CPU numerators are
single-statement-per-connection runs and sit **+0.495%** (CUBRID controlled) and
**+1.537%** (PostgreSQL) above their own headline-regime medians. Their differential
predicts `1.00495/1.01537 − 1 = −1.0259%`, which matches the observed −1.0259% to
**0.000 pp**. The residual is deterministic and explained, and the card is closed.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 0.707996x | plan-node shape | wall-seconds, same engine | `T_C_native / T_C_controlled` = 4.808/6.791 | `Q03-cubrid-headline.json`, `sink/Q03-cubrid-hash-block.out`, `q3-trace-cubrid-hash.out` | direct A/B |
| `F_units` | 0.851451x | active execution units | CPU-seconds / wall-second | `U_P/U_C_ctl`, `U=CPU/T` = 6.28297/7.37914 | `Q03-cubrid-hash-telemetry-run3.json`, `Q03-postgresql-telemetry-run1.json` | profile attribution |
| `F_cpu` | 2.256272x | total query CPU-seconds | per query execution | `CPU_C_ctl/CPU_P` = 50.36/22.32 | same telemetry JSONs | profile attribution |
| `F_work` | 0.998080x | plan-node tuple touches | tuples | `W_C_ctl/W_P` = 118,590,174/118,818,354 | `q3-trace-cubrid-hash.out`, `q3-plan-act-pg.out` | direct A/B |
| `F_cost` | 2.260614x | CPU-seconds per tuple touch | tuple touches | `(CPU_C/W_C)/(CPU_P/W_P)` = 424.7 ns / 187.8 ns | `Q03-causal-card.json` | profile attribution |

`U_C_ctl = 50.36/6.824648 = 7.37914`, `U_P = 22.32/3.552459 = 6.28297`.
No factor double-counts: `F_plan` carries only the same-engine shape effect, `F_units`
only CPU-per-wall-second, `F_work` only the tuple count (which is ~1.0 by
construction, because the controlled anchor equalises it), and `F_cost` the residual
CPU per tuple. `W` is the sum over plan nodes of the tuples each node processed (rows
output plus rows its own filter rejected), each node counted exactly once; the full
per-node derivation is in `Q03-causal-card.json` and reproduced in section 8.

**Descriptive only, not part of the card chain** (native cross-engine pair, kept
because it is what a reader expects to see): `F_units 1.379335`, `F_cpu 0.981631`,
`F_work 0.090610`, `F_cost 10.833611`. In native form the two engines burn almost
identical total CPU (21.91 vs 22.32 core-s) and CUBRID touches **11.0x fewer** tuples
while paying **10.83x more** per tuple. Those numbers are real but they cannot be
multiplied against a numeric `F_plan` without mixing native and controlled
denominators, which section 16 forbids.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q03 |
| SSOT commit | `5912f0654f1e98beea154c7003d372f52a24a9c4` |
| SSOT blob | `6ce8e04da201fd3f5e1b2d3dae42db1534d5b51a` |
| GJC session ID | `gajae_code_ms7i3rb7_gba2sjdp` |
| Raw dir | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q03` |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` |
| CUBRID DB / port | `tpch_sf10_q1` / 1523 (`cub_server` pid 1445555, `cub_master` pid 1433697) |
| PostgreSQL PGDATA / port | `/home/cubrid/pg/pgdata-tpch-sspq` / 5442 (postmaster pid 1433696) |

Both running binaries hash-match the frozen `reports/bootstrap/build-manifest.json`.
Ownership gates (section 10) classified **OK** before and after every measurement
block; the post-block gate (`q3-postcheck.txt`) records 0 orphan `csql`, 0 orphan
`psql`, 0 parallel workers and 0 client backends remaining, satisfying section 13's
"no next run while orphan work remains".

**No SSOT re-pinning occurred during Q03.** `git rev-parse HEAD:tpch-sspq/SSOT.md`
equalled the pinned blob `6ce8e04d…` at preflight and at completion, `HEAD` ==
`origin/main` == `487ff2e` throughout, and the pinned `ssot_commit 5912f065…` is an
ancestor of `HEAD` with an identical `SSOT.md` blob. `SSOT_DRIFT` was never set. The
pinned commit was verified before any action per section 4, including the full read to
EOF.

Query provenance: `queries/q3-cubrid.sql` byte-matches the canonical source
`/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q3.sql`, SHA-256
`15db2d9b8be35e2b5718ce3e4dc969498838bc02bbabcd6e07af52264d6d9a03`. The PostgreSQL
dialect file is **byte-identical** to the canonical CUBRID file (same SHA-256;
`queries/diff/q3.diff` is 0 bytes and `cmp` is clean): Q03 needs zero dialect changes,
including `TO_CHAR(o_orderdate, 'YYYY-MM-DD')`, which both engines accept. No hint,
join reordering, subquery rewrite, extra predicate or semantic cast exists in either
measured file. The `/*+ USE_HASH */` variant used for the plan anchor is a **separate
diagnostic probe file** under `work/Q03`, never a measured dialect file.

Schema: 8 named FKs and 8 corresponding child B-trees verified on both engines with
exact child-column order (including composite `fk_lineitem_partsupp (l_partkey,
l_suppkey)` at key_order 0,1); all PostgreSQL `pg_constraint.convalidated = true`
(8/8/8). Row counts exact-equal on both engines (`customer` 1,500,000, `orders`
15,000,000, `lineitem` 59,986,052). **Q03 exercises the campaign's FK indexes
directly and decisively**: CUBRID's native plan drives the entire query through
`fk_orders_customer` and `fk_lineitem_orders`, and PostgreSQL's forced-NL
counterfactual uses `idx_fk_orders_customer`/`idx_fk_lineitem_orders`. This plan does
not exist under the discarded PK-only schema.

Contract state at measurement time:

- statistics: CUBRID `update_statistics_update_histogram=y`,
  `default_histogram_bucket_count=300` (target). Actual per-column bucket count
  remains **UNMEASURED** (opaque serialized `VARBIT` in `_db_histogram`) — carried
  forward from bootstrap, Q01 and Q02. PostgreSQL standard `ANALYZE`,
  `default_statistics_target=100`, all eight tables last analyzed 2026-07-30 17:54
  (post-FK-creation).
- parallel, `configured node/gather-cap comparison`: CUBRID `parallelism=6`,
  `max_parallel_workers=100`; PostgreSQL `max_parallel_workers_per_gather=5`,
  `max_parallel_workers=5`, `parallel_leader_participation=on`,
  `max_worker_processes=16` (non-binding), `statement_timeout=300000 ms`, `jit=off`.
- buffer/cache, `configured-equal buffer budget`: CUBRID `data_buffer_size=8.0G`,
  PostgreSQL `shared_buffers=8192MB`. **Q03's working set exceeds both budgets**:
  the three referenced relations are 13,369.9 MiB on CUBRID (`lineitem` 10,670.9 +
  `orders` 2,370.1 + `customer` 328.9) and 11,112 MB on PostgreSQL. Unlike Q02, both
  engines self-evict, and the resulting reuse deficit is measured in section 5 and
  attributed in section 9.
- shared memory, `parallel-plan-availability parity`: PostgreSQL
  `dynamic_shared_memory_type=mmap`, verified live with `source=configuration file,
  sourcefile=postgresql.conf:969`, DSM segments present as
  `PGDATA/pg_dynshmem/mmap.*`, `/dev/shm` untouched at 628k of 64000k
  (`q3-shared-memory-verification.txt`). **Section 9 makes recording this
  mandatory for Q03**: PostgreSQL's natural plan contains two `Parallel Hash Join`
  nodes and a `Gather Merge`, and the outer hash spills to 16 batches — exactly the
  case that fails with `could not resize shared memory segment` under the packaged
  `posix` default.
- cpuset/NUMA: SUT+client CPUs `0-15` (node0), collectors CPUs `20-23`. All 34
  engine TIDs verified on `0-15` with **0 off-cpuset** both at preflight and after
  the blocks. `cub_server` 8,620.26 MB node0 / 4.55 MB node1 (99.95% node0);
  postmaster 166.73 MB node0 / 0.60 MB node1. No page migration during the runs.
- **external SUT-set load was NOT within contract at preflight and had to be
  waited out.** See section 5; this is the single most consequential operational
  fact of Q03.

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored.

Q03 has `ORDER BY`, so the ordered result sequence was compared exactly. 10 rows on
both engines (`LIMIT 10`), all fields equal — text, integers, dates, NULLs, row count
and row multiset. Raw decimal text preserved. The 1e-12 relative tolerance was
available but **not needed**: no field required it.

The `LIMIT 10` boundary was proven non-arbitrary rather than assumed. The unlimited
query returns **114,003** groups on both engines, of which 113,915 have a distinct
`revenue` — so ties exist globally (88 duplicate revenues) and the boundary had to be
checked explicitly rather than argued from uniqueness. It is strictly separated: row
10 is `(52974151, 415367.1195, 1995-02-05, 0)` and row 11 is
`(3778628, 411836.2827, 1995-02-25, 0)`, a gap of 3,531.13 in the leading sort key.
Both engines return the same first 12 rows in the same order
(`q3-boundary-cubrid.out`, `q3-boundary-pg.out`), so `LIMIT 10` is deterministic and
the equivalence is structural, not a coincidence of tie-breaking.

Independent row-count ground truth, used later for `W` and to expose the section 9
trace defect: the full three-way join under all predicates yields **302,114** rows and
**114,003** distinct `l_orderkey` — identical on both engines
(`q3-groundtruth-cubrid.out`, `q3-groundtruth-pg.out`).

Comparator: `harness/correctness_check.py` delegating to the bootstrap-verified
`harness/smoke_check.py` rules.

## 3-b. Headline timings

Regime `single-query-repeat WARM`; metadata connection mode
`single-connection-four-statements` (1 uncounted warmup + 3 measured, one direct
connection, no reconnect/prepare between measured statements, connection
establishment excluded). **Q03 is odd, so the engine-block order is CUBRID block
first, then PostgreSQL block** (section 12). Each statement fully consumed all 10 rows
into a campaign-owned fixed sink under `work/Q03/sink`; content hashes computed after
the timers stopped.

| Field | CUBRID | PostgreSQL |
|---|---|---|
| warmup (uncounted) | 4.767999 s | 3.535973 s |
| measured run 1 | 4.788000 s | 3.500554 s |
| measured run 2 | 4.825000 s | 3.498678 s |
| measured run 3 | 4.808000 s | 3.497684 s |
| **median (headline)** | **4.808000 s** | **3.498678 s** |
| mean | 4.807000 s | 3.498972 s |
| within-block sd | 0.018520 s (0.385%) | 0.001457 s (0.042%) |
| sink bytes | 3987 | 1482 |
| sink SHA-256 | `d3f7537300ce6a2b…` | `738a55c36d5b8205…` |

**Median wall ratio = 1.374233x (CUBRID / PostgreSQL) — PostgreSQL is 1.3742x
faster.** Correctness status `result-equivalent-at-SF10`; censoring status: not
censored (both engines far inside the 300 s timeout). No confidence interval is
claimed from three values.

Controlled-plan anchor, measured in the **same regime** (1 uncounted warmup + 3
measured, one connection) so it is directly comparable to the headline above:
CUBRID `/*+ USE_HASH */` warmup 6.803000 s, measured 6.938999 / 6.791000 / 6.775000 s,
**median 6.791000 s**, mean 6.835000 s, sd 0.090443 s (1.323%).

Measurement-resolution note: `csql` reports elapsed time at 1 ms granularity, so
CUBRID's headline carries ±0.021% quantization at this magnitude, an order of
magnitude below its 0.385% within-block sd; `psql` reports µs.

WARM proof (proved, not assumed):

| Evidence | CUBRID | PostgreSQL |
|---|---|---|
| device `read_bytes` delta across block | 2,535,424 B (2.42 MiB, against 13.09 GiB of `rchar` per statement) | 0 |
| engine buffer counters | LRU zones live and pool conserved at exactly 524,288 pages (8 GiB / 16 KiB) pre and post: `lru1+lru2+lru3` = 200,639+25,029+298,620 → 202,577+25,297+296,414 | `heap_blks_read` +751,088/statement, `heap_blks_hit` +671,296/statement |
| `rchar` per statement | 14,053,622,920 B (13.09 GiB) | 8,694,806,235 B (8.10 GiB) |
| warmup vs median | **−0.83%** (warmup was the *fastest* statement) | +1.07% |
| in-query physical reads | trace `ioread` served from OS page cache; device read 1.36 MiB total | `Buffers: shared read=746768` with device read 0.12 MiB |

Neither engine holds Q03's working set, so `heap_blks_read` and CUBRID's `ioread` are
deliberately **non-zero** here — unlike Q02. That is not a WARM failure: WARM in this
campaign means steady state with no cold-start penalty, and the proof is that (a) both
engines' device reads are ~0, so every miss is served by the OS page cache, (b) the
warmup statement is within −0.83%/+1.07% of the median, with CUBRID's warmup actually
the fastest of its four statements, and (c) statement-to-statement sd is 0.385% and
0.042%. No WARM gate failure occurred, so no run was invalidated or restarted.

**Perfmon counter usability, tightened versus Q02.** Q02 recorded
`Num_data_page_fetches`/`Num_data_page_ioreads` as "frozen". Q03 tested that claim
directly (`q3-perfmon-counter-probe.txt`): the two counters read 15,305,689 /
2,325,951 before a Q03 statement, after one statement and after two statements —
**identical all three times**, while the LRU zone gauges do move. They do change at
some server-internal moment (they read 1,212,814 / 682,963 during the headline block
hours earlier), so the accurate statement is not "frozen" but "advances at moments
unrelated to statement execution, therefore unusable as a per-block gauge". WARM
evidence consequently rests on device `read_bytes`, `/proc/<pid>/io`, the LRU zone
conservation and the trace's per-node `ioread`.

## 4. Plan

The two engines choose **structurally different plans**, and unlike Q02 the difference
can be closed from CUBRID's side with a hint, which is what makes `F_plan` measurable.

CUBRID estimated (`SET OPTIMIZATION LEVEL 514`, verified non-executing: 0.02 s wall,
"There are no results"):

```text
temp(order by)
    subplan: temp(group by)
                 subplan: idx-join (inner join)
                              outer: idx-join (inner join)
                                         outer: sscan class: customer node[0]
                                                    sargs: term[2]           <- c_mktsegment='BUILDING'
                                                    cost: 24799 card 313950
                                         inner: iscan class: orders node[1]
                                                    index: fk_orders_customer term[0]
                                                    sargs: term[3]           <- o_orderdate < 1995-03-15
                                                    cost: 4 card 7246132
                                         cost: 252417 card 1516616
                              inner: iscan class: lineitem node[2]
                                         index: fk_lineitem_orders term[1]
                                         sargs: term[4]                      <- l_shipdate > 1995-03-15
                                         cost: 4 card 32440253
                              cost: 1101704 card 1399146
                 sort: 1 asc
    sort: 2 desc, 3 asc
    cost: 1116907 card 1399146
term[2]: c_mktsegment='BUILDING' (sel 0.2093)
term[3]: o_orderdate range (min inf_lt 1995-03-15) (sel 0.483075) (rank 2)
term[4]: l_shipdate range (1995-03-15 gt_inf max) (sel 0.540797) (rank 2)
```

CUBRID actual (trace, `q3-trace-cubrid.out`; **lineitem counters shown as reported and
then corrected** — see section 9 / IMP-005):

```text
SELECT (time: 5848, fetch: 223568, fetch_time: 49, ioread: 1264)
  SCAN (table: dba.customer) (heap time: 5365, fetch: 1082, ioread: 8)
       (parallel workers: 5, heap time: 5219..5354, readrows: 295632..301237,
        gather: mergeable list)
    SCAN (index: dba.orders.fk_orders_customer) (btree time: 1449, fetch: 3906297,
        ioread: 15103, readkeys: 300275, filteredkeys: 200285, rows: 3004382)
        (lookup time: 1143, rows: 1461923)
      SCAN (index: dba.lineitem.fk_lineitem_orders) (btree time: 3624,
        fetch: 11836168, ioread: 1632632, readkeys: 2923846, filteredkeys: 2923846,
        rows: 11691206) (lookup time: 1977, rows: 604228)
        -> CORRECTED (divide depth-3 counters by 2): fetch 5918084, ioread 816316,
           readkeys 1461923, rows 5845603, lookup rows 302114
  GROUPBY (time: 393, hash: partial, sort: true, page: 4309, ioread: 1250, rows: 114003)
  ORDERBY (time: 90, sort: true, page: 4316, ioread: 1250)
```

PostgreSQL actual (`EXPLAIN ANALYZE BUFFERS VERBOSE TIMING`, `q3-plan-act-pg.out`):

```text
Limit (actual time=3656.444..3769.842 rows=10)
  Buffers: shared hit=675689 read=746768, temp read=153445 written=153640
  Sort (top-N heapsort, 26kB)
    Finalize GroupAggregate (rows=114003)
      Gather Merge (rows=114023)  Workers Planned: 5  Launched: 5
        Partial GroupAggregate (rows=19003.83 loops=6)
          Sort (quicksort 3684kB) Sort Key: l_orderkey, o_orderdate, o_shippriority
            Parallel Hash Join (rows=50352.33 loops=6)
              Hash Cond: (lineitem.l_orderkey = orders.o_orderkey)
              -> Parallel Seq Scan on lineitem (rows=5389041.67 loops=6)
                   Filter: (l_shipdate > '1995-03-15'), Rows Removed: 4608634/loop
              -> Parallel Hash (rows=243653.83 loops=6)
                   Buckets: 262144  Batches: 16  Memory Usage: 6464kB
                   -> Parallel Hash Join (rows=243653.83 loops=6)  Inner Unique: true
                        Hash Cond: (orders.o_custkey = customer.c_custkey)
                        -> Parallel Seq Scan on orders (rows=1214907 loops=6)
                             Filter: (o_orderdate < '1995-03-15'), Removed: 1285093/loop
                        -> Parallel Hash (rows=50046 loops=6)
                             Buckets: 524288  Batches: 1  Memory Usage: 15904kB
                             -> Parallel Seq Scan on customer (rows=50046 loops=6)
                                  Filter: (c_mktsegment = 'BUILDING'), Removed: 199954/loop
Planning Time: 1.717 ms   Execution Time: 3770.201 ms
```

Shape difference, stated precisely:

- **CUBRID** drives from a parallel full scan of `customer` (5 workers, 1,500,000 rows
  read), keeps the 300,275 `BUILDING` rows, probes `orders` through the FK B-tree
  (3,004,382 index entries → 1,461,923 after the date filter), then probes `lineitem`
  through the FK B-tree (5,845,603 corrected index entries → 302,114 after the ship-date
  filter), and finishes with a partial-hash group-by (114,003 groups) and a top-10
  sort. It never touches a row it does not need: **10,766,102** tuple touches total.
- **PostgreSQL** scans all three relations in full and in parallel (1,500,132 +
  15,000,000 + 59,986,054 rows examined), builds `customer` into a single-batch hash
  (15,904 kB), hash-joins `orders` to it (7,289,442 probes → 1,461,923), builds that
  into a 16-batch hash that **spills** (`temp written=153,640` blocks ≈ 1.17 GiB),
  hash-joins the 32,334,250 surviving `lineitem` rows against it (→ 302,114), then
  sorts and partially aggregates *inside each worker* before a `Gather Merge` and a
  finalize step. Total: **118,818,354** tuple touches — **11.0x** CUBRID's.

Estimate quality: CUBRID's three sargs are all close (`c_mktsegment` sel 0.2093 vs
actual 300,275/1,500,000 = 0.2002, 4.5% high; `o_orderdate` 0.483075 vs
7,289,442/15,000,000 = 0.4860, 0.6% low; `l_shipdate` 0.540797 vs
32,334,250/59,986,052 = 0.5390, 0.3% high). Its final cardinality estimate is
1,399,146 against an actual 302,114 (4.63x over), which comes from assuming
independence between `o_orderdate < D` and `l_shipdate > D` — two strongly
anti-correlated predicates. PostgreSQL makes the *same* independence error
(`rows=629299` partial → 3,146,495 final vs actual 114,003 groups). **Neither engine's
misestimate changes its plan choice here**, and both plans are the better one for
their own engine (below), so this is recorded as a shared modelling limitation and not
raised as a candidate.

Why `F_plan` is numeric, and the counterfactuals in both directions:

| Variant | Plan reached | Wall | Verdict |
|---|---|---|---|
| CUBRID native | 3-level idx-join over `fk_orders_customer`, `fk_lineitem_orders` | **4.808 s** (median of 3) | baseline |
| CUBRID `/*+ USE_HASH */` | **PostgreSQL's exact shape**: 3 sequential scans, 2 hash joins, same order | **6.791 s** (median of 3) | the controlled anchor |
| CUBRID `/*+ USE_MERGE */` | sort-merge join | 11.565 s | worse still |
| CUBRID `/*+ USE_NL */` | plain nested loop | 4.955 s | ≈ native |
| PostgreSQL native | 2 Parallel Hash Joins + partial aggregate | **3.498678 s** (median of 3) | baseline |
| PostgreSQL `enable_hashjoin=off, enable_mergejoin=off` | nested loop, CUBRID's shape | 15.818 s (EXPLAIN ANALYZE) | 4.5x worse than its native |

The anchor is legitimate because the forced-hash CUBRID plan is not merely "hash-join
shaped" — its per-node row counts are **identical** to PostgreSQL's:

| Node | CUBRID `/*+ USE_HASH */` | PostgreSQL native |
|---|---|---|
| `customer` scan rows read | 1,500,000 | 1,500,132 |
| `customer` hash build rows | 300,276 | 300,276 |
| `orders` scan rows read | 15,000,000 | 15,000,000 |
| probes into `customer` hash | 7,289,442 | 7,289,442 |
| `orders` side matched rows | 1,461,923 | 1,461,923 |
| `lineitem` scan rows read | 59,986,052 | 59,986,054 |
| probes into `orders` hash | 32,334,250 | 32,334,250 |
| join output rows | 302,114 | 302,114 |
| groups | 114,003 | 114,003 |

`W_C_controlled / W_P = 0.99808`, i.e. the two plans do the same work to within
0.19%. Both optimizers therefore choose correctly **for their own engine** — CUBRID's
index-NL is 1.4125x better than its own hash plan, PostgreSQL's hash plan is 4.5x
better than its own NL plan — and the remaining 1.9410x gap at matched shape is pure
execution efficiency, which is what section 8 decomposes.

## 5. Execution telemetry

Non-headline diagnostic runs; sampler on CPUs `20-23`, per-TID, weighted by actual
sample timestamp deltas. Three runs per engine and per variant; the
**median-by-wall** run is the recorded one (CUBRID native run 1, PostgreSQL run 1,
CUBRID controlled run 3). All runs are retained in raw.

| Metric | CUBRID native | CUBRID controlled (hash) | PostgreSQL |
|---|---|---|---|
| telemetry walls (3 runs) | **4.810021** / 4.817284 / 4.803071 s | 6.826514 / 6.818392 / **6.824648** s | **3.552459** / 3.541457 / 3.575171 s |
| `executor_cpu` | 21.77 core-s (`parallel-query` 21.23, `transaction` 0.53) | 48.06 core-s | 19.28 core-s (`pg_backend` 3.38, `pg_parallel_worker` 15.90) |
| `auxiliary_query_cpu` | 0.14 core-s (`pgbuf-page-flush` 0.10, `dwb-*` 0.02) | 2.30 core-s | 3.04 core-s (`pg_io_worker` 2.72, `pg_background` 0.32) |
| `total_query_cpu` | **21.91 core-s** | **50.36 core-s** | **22.32 core-s** |
| planned workers | 6 (`parallelism=6`) | 6 | 5 (`Workers Planned: 5`) + leader |
| launched workers | 5 (trace `parallel workers: 5`) | 6 at the outer hash join, nested 2/3/5/6 at inner levels | 5 (`Workers Launched: 5`) + leader = 6 |
| max simultaneous active units | 5.2885 | 12.6248 | 8.0480 |
| time-weighted active units (TWU) | **4.6094** | **7.4110** | **6.3423** |
| serial tail | 0.338 s | 0.677 s | 0.117 s |
| `rchar` | 14,053,622,920 B | 13,594,346,680 B | 8,694,806,235 B |
| read syscalls (`syscr`) | 857,910 | 829,884 | 551,551 |
| `write_bytes` | 29,536,256 B | 739,971,072 B | 2,600,931,328 B (temp spill) |
| device read (sda+sdb) | 1.36 MiB | 0.00 MiB | 0.12 MiB |
| `unattributed_background` | none claimed | none claimed | none claimed |

TWU is an independent cross-check of `U`, not a substitute. Native CUBRID:
`U_C = 21.91/4.810021 = 4.5561` vs TWU 4.6094 (1.17% apart), and `perf` gives a third
independent reading of 4.638 CPUs utilized. Controlled CUBRID:
`U_C_ctl = 7.37914` vs TWU 7.4110 (0.43% apart), `perf` 7.518. PostgreSQL:
`U_P = 6.28297` vs TWU 6.3423 (0.94% apart). No value was derived from a configured
cap and no nominal interval was used for weighting.

**PostgreSQL exceeds its own gather cap, legitimately.** Its TWU of 6.3423 is above
the 6 units of leader + 5 workers because `io_method=worker` adds up to 4 io worker
processes (2.72 core-s, classified auxiliary per section 15, never executor). CUBRID's
controlled plan reaches an even higher TWU of 7.4110 with a max of 12.62, because its
hash join nests parallel operators (the trace shows `parallel workers: 6` at the outer
join with `parallel workers: 2/3/5/6` at inner levels), so it is not bound by a single
gather cap either. This is exactly why section 9 labels the comparison a `configured
node/gather-cap comparison` and forbids inferring execution units from settings: at
matched plan shape CUBRID actually runs **more** concurrent units than PostgreSQL
(`F_units = 0.851451 < 1`) and still loses, because it needs 2.2563x the CPU.

**PostgreSQL's temp spill is real but is not disk I/O**: `write_bytes` 2.60 GB against
a device write of 22.28 MiB, i.e. the 16-batch hash spill lives in the OS page cache.
Its cost is CPU and memory bandwidth on tuples already counted by `F_work`, so it is
not double-counted as an I/O factor.

**Q03's operational headline: the SUT set was contended, and every timed value in this
report was gated on quiescence.** This is a new failure mode for the campaign and is
recorded in full because it changes how the numbers must be read.

- The measurement host is a **podman container**
  (`/proc/1/cgroup` → `libpod_parent/libpod-2dd433b1e760…`) whose `/proc/stat` is
  host-wide. CPU burned by processes outside the container is real contention on CPUs
  `0-15` and is **invisible to `ps`/`pgrep` inside it**.
- At preflight the section 9 gate **FAILED**: external SUT-set load was
  **6.185 core-seconds/second** against the 1.5 threshold (`preflight-Q03.txt`).
  A 20-second per-PID audit accounted for only 0.873 cores from all
  container-visible processes while the host-wide figure on `0-15` was 4.5-6.3 cores,
  so ≥3.7 cores were external and unattributable. The neighbour load was bursty:
  ~6 cores for minutes, then quiet for tens of seconds.
- Per section 9 ("wait"), **no timed run was started while the gate was failing.**
  Load-insensitive stages (correctness, boundary proof, estimated plans, ground-truth
  counts) were completed during the wait; every timed stage was then run through a new
  gate that requires 6 consecutive quiet 2-second samples immediately before the
  block and monitors external load at 4 Hz throughout, rejecting any block whose
  external load crosses 1.5 at any sample.
- Accepted blocks and their measured external load: CUBRID headline mean 0.209 / max
  0.875; PostgreSQL headline mean 0.241 / max 0.832; controlled anchor mean 0.225 /
  max 0.952; all six telemetry runs max 0.561-1.306; all three perf captures max
  0.736-1.014. Every accepted block is `CLEAN`.

Two harness defects were found and fixed while establishing that gate. Both are
recorded because they invalidated intermediate conclusions:

1. **Load-monitor accounting (fixed before any accepted block).** The first monitor
   attributed campaign CPU with incremental per-PID deltas. PostgreSQL forks a backend
   plus 5 parallel workers per statement and reaps them at statement end, so each
   worker's CPU between fork and first discovery, and between last sample and exit,
   was attributed to nobody and appeared as external load. All 8 PostgreSQL attempts
   were rejected by this false positive (`external_max` 4.86-11.03 while
   `external_mean` stayed near 0.8). The fix computes campaign CPU as an **absolute**
   sum with roots (`cub_master`, postmaster) counted via `cutime+cstime` — exactly
   where a reaped child's CPU lands — plus live leaves via `utime+stime`. Calibration
   against a live 4-statement PostgreSQL block (`q3-bgload-monitor-validation.json`):
   host-wide busy peaks at **8.06 cores**, campaign attribution tracks it at **7.96**,
   external stays ≤ **0.80** → `CLEAN`. The pre-fix attempts are retained under
   `raw/Q03/pre-monitor-fix/` with `INVALID.json` and are excluded from every
   calculation. Note the direction of the bias: corrected campaign attribution is
   always ≥ the buggy one, so a pre-fix `CLEAN` verdict cannot become dirty — the
   pre-fix CUBRID block (median 4.790 s) agreed with the accepted post-fix block
   (4.808 s) to 0.4%, and both blocks were nevertheless re-measured under the
   corrected instrument so that both engines carry evidence from the same tool.
2. **`perf report` ran unpinned.** Three consecutive CUBRID perf captures were
   rejected with `external_max` 1.79-2.17. The load trace localised it exactly: the
   over-threshold samples fall at t+68.9 s and t+77.2 s, **after** the driver had
   exited (campaign CPU 0.01), while external load sat at a flat ~1.20 cores — the
   signature of `perf report` decoding a 750 MB dwarf call graph on the SUT set.
   Section 9 assigns collectors to CPUs `20-23`, and `perf record`/`perf stat` were
   already pinned but the two `perf report` invocations were not. After pinning them,
   the same capture passed on the first attempt (`external_max` 0.736). During the
   actual 50-second capture window external load had been 0.20-0.29 in all three
   rejected attempts, so the profiles were never contaminated — but the rejected
   traces are retained as invalid evidence rather than discarded.

## 6. Profile

Non-headline. `perf` attached to verified PID sets, never all-CPU. CUBRID:
`-p 1445555` (`cub_server`; all query worker threads live inside that process, 30-39
TIDs). PostgreSQL: `perf stat` on the discovered leader `1488062` plus exactly its 5
parallel workers `1488063-1488067`; `perf record` on `postmaster 1433696 + leader`,
relying on perf's inherit-on-fork because worker PIDs are transient per statement.
Multi-second statements still cannot fill a window alone, so a driver replayed the
identical statement in one connection (CUBRID 11 repeats, PostgreSQL 15, CUBRID
controlled 8), grouping identical variants per section 24.

Coverage validation against `perf stat`: CUBRID 92,548 samples / 958 resolved symbol
lines / **0 `[unknown]`** / 0 lost; PostgreSQL 104,292 samples / 1,879 lines / **0
`[unknown]`** / 0 lost; CUBRID controlled 151,266 samples / 1,277 lines / **0
`[unknown]`** / 0 lost. Driver completion verified (11 and 8 `csql` result-set markers;
PostgreSQL 150 non-empty sink lines = 15 × 10 rows).

| Metric | CUBRID native | CUBRID controlled | PostgreSQL |
|---|---|---|---|
| cycles (20.0 s window) | 251,689,308,866 | 410,266,084,424 | 75,976,775,811 |
| instructions | 237,384,713,178 | 805,411,097,484 | 147,918,541,246 |
| **IPC** | **0.94** | **1.96** | **1.95** |
| frequency | 2.713 GHz | 2.728 GHz | 2.711 GHz |
| task-clock | 92,776.18 ms | 150,383.55 ms | 28,027.58 ms |
| CPUs utilized | 4.638 | 7.518 | 1.401 (partial set, see below) |
| context-switches | 211,683 | 244,377 | 1,826 |
| instructions per core-second | 2.559e9 | 5.356e9 | 5.278e9 |
| instructions per statement | 56.1e9 | 269.7e9 | 117.8e9 |
| **instructions per tuple touch** | 5,211 | **2,274.3** | **991.4** |

Two caveats, stated rather than smoothed. (a) PostgreSQL's "CPUs utilized" of 1.401 is
**not** its parallel utilization: the leader backend persists across the driver's 15
statements but the 5 parallel workers are per-statement, so the fixed PID set only
covers one statement's workers. Utilization comes from telemetry (TWU 6.3423), not
from this row; IPC and instructions-per-core-second are unaffected because they are
ratios over whatever work the set actually did. (b) PostgreSQL's profile covers its
**executor only** (leader + workers = 19.28 of 22.32 core-s); the 2.72 core-s of io
workers are a separate process set and are excluded, which matters for section 9's
I/O attribution.

**The decisive profile result: CUBRID's IPC deficit is a plan artifact, not an engine
property.** Native CUBRID runs at IPC 0.94 — the signature of stalling on random index
descent and scattered page fetches — but at the matched hash-join shape it runs at
**1.96, statistically identical to PostgreSQL's 1.95**. Therefore `F_cost = 2.2606`
decomposes almost entirely into instruction count, not stalls:
`2.294x (instructions per tuple) × 0.985x (CPU-seconds per instruction) = 2.260`,
matching `F_cost` to three decimals.

Top self cost, CUBRID native (`profile-cubrid-flat.txt`) — the index-NL page-fetch
signature:
`pgbuf_fix_release` **14.71%**, `rep_movs_alternative` [k] **13.83%**,
`spage_get_record` 5.91%, `btree_search_leaf_page` 4.66%, `pgbuf_unfix` 3.97%,
`pgbuf_lru_boost_bcb` 3.49%, `btree_search_nonleaf_page` 2.80%,
`__pthread_mutex_lock` 2.72%, `heap_attrinfo_read_dbvalues` 2.49%,
`or_mvcc_get_repid_and_flags` 2.24%, `__memmove_evex_unaligned_erms` 2.14%,
`pgbuf_unlatch_void_zone_bcb` 1.89%, `filemap_get_read_batch` [k] 1.82%,
`btree_compare_key` 1.45%, `__pthread_mutex_unlock_usercnt` 1.46%,
`__pthread_mutex_trylock` 1.42%, `filemap_read` [k] 0.98%, `pgbuf_get_victim` 0.79%.

Banded (native): buffer-manager fix/unfix/LRU **25.49%** = 5.58 core-s; kernel
page-cache read and copy (`rep_movs_alternative`, `filemap_*`, `xas_*`) **18.07%** =
3.96 core-s; B-tree descent 8.91% = 1.95 core-s; record/attribute extraction 12.45% =
2.73 core-s; mutex 5.60% = 1.23 core-s. **43.56% of CUBRID's native query CPU is spent
getting pages into and out of its buffer pool**, not on join or aggregate work.

Top self cost, CUBRID controlled (`profile-cubrid-hash-flat.txt`) — the
matched-shape comparison basis:
`heap_attrinfo_read_dbvalues` **10.52%**, `rep_movs_alternative` [k] 5.95%,
`fetch_val_list` 3.81%, `__pthread_mutex_lock` 3.26%,
`qdata_generate_tuple_desc_for_valptr_list` 3.04%, `mr_data_readval_numeric` 2.89%,
`qdata_copy_db_value_to_tuple_value` 2.84%,
`parallel_scan::slot_iterator::next_qualified_slot_with_peek` 2.82%,
`__pthread_mutex_unlock_usercnt` 2.64%, `heap_next_1page` 2.56%, `mht_get_hls` 2.20%,
`pgbuf_get_victim_candidates_from_lru` 2.12%, `__memmove_evex_unaligned_erms` 2.11%,
`hjoin_fetch_key` 1.82%, `parallel_query::hash_join::split_task::execute` 1.75%,
`eval_pred_comp0` 1.70%, `qfile_generate_tuple_into_list` 1.51%, `pr_clear_value`
1.40%, `qdata_get_tuple_value_size_from_dbval` 1.23%, `tp_value_compare_with_error`
1.21%, `or_header_size` 1.20%, `heap_scan_get_visible_version` 1.18%.

Top self cost, PostgreSQL (`profile-pg-flat.txt`):
`tts_buffer_heap_getsomeattrs` **21.62%**, `ExecInterpExpr` 8.52%,
`ExecParallelScanHashBucket` 6.59%, `heap_fill_tuple` 5.46%, `ExecParallelHashJoin`
3.75%, `heapgettup_pagemode` 2.70%, `hash_search_with_hash_value` 2.63%,
`next_uptodate_folio` [k] 2.48%, `BufFileReadCommon` 2.40%, `heap_deform_tuple` 2.37%,
`ExecSeqScanWithQualProject` 2.21%, `__memmove_evex_unaligned_erms` 1.86%,
`sts_puttuple` 1.61%, `rep_movs_alternative` [k] 1.58%, `heap_form_minimal_tuple`
1.50%, `heap_compute_data_size` 1.46%, `sts_parallel_scan_next` 1.35%,
`ExecStoreBufferHeapTuple` 1.15%, `LWLockAttemptLock` 1.07%, `heap_getnextslot` 1.04%,
`heap_page_prune_opt` 1.03%.

Banded comparison at **matched plan shape** (each band against its own profile's
denominator: CUBRID whole-process 50.36 core-s, PostgreSQL executor 19.28 core-s):

| Band | CUBRID controlled | PostgreSQL |
|---|---|---|
| intermediate-tuple materialization (`fetch_val_list`, `qdata_*`, `qfile_generate_tuple_into_list`) | **12.43% = 6.26 core-s** | comparable band is spill only (`sts_puttuple`, `BufFileReadCommon`, `sts_parallel_scan_next`) **5.36% = 1.03 core-s** |
| heap access + attribute extraction | `heap_attrinfo_read_dbvalues` 10.52% + `heap_next_1page` 2.56% + `heap_scan_get_visible_version` 1.18% + `or_header_size` 1.20% = 15.46% = 7.79 core-s | `tts_buffer_heap_getsomeattrs` 21.62% + `heap_deform_tuple` 2.37% + `heap_fill_tuple` 5.46% + `heap_compute_data_size` 1.46% + `heap_form_minimal_tuple` 1.50% + `ExecStoreBufferHeapTuple` 1.15% = 33.56% = 6.47 core-s |
| hash join proper | `mht_get_hls` 2.20% + `hjoin_fetch_key` 1.82% + `split_task::execute` 1.75% + `slot_iterator` 2.82% = 8.59% = 4.33 core-s | `ExecParallelScanHashBucket` 6.59% + `ExecParallelHashJoin` 3.75% + `hash_search_with_hash_value` 2.63% + `hash_bytes_uint32` 0.70% = 13.67% = 2.64 core-s |
| kernel I/O on the critical path | `rep_movs_alternative` 5.95% = **3.00 core-s** | `next_uptodate_folio` 2.48% + `rep_movs_alternative` 1.58% = 4.06% = **0.78 core-s** (plus 2.72 core-s in io workers, off the critical path) |
| mutex / lightweight locking | 5.90% = 2.97 core-s | `LWLockAttemptLock` 1.07% = 0.21 core-s |

The single largest identifiable structural difference is the first row: CUBRID spends
6.26 core-s copying intermediate tuples into list-file records where PostgreSQL spends
1.03 core-s, and only because it spills. That 5.23 core-s is 18.7% of the entire
28.04 core-s CPU excess and is the basis of IMP-006.

## 7. Source contrast

| Item | CUBRID file:line | PostgreSQL file:line | Difference | Class |
|---|---|---|---|---|
| Intermediate tuple handoff between pipelined operators | `src/query/query_executor.c:1255-1259` qexec_end_one_iteration() "generate tuple into list file page" for every output tuple; `src/query/list_file.c:1851` qfile_generate_tuple_into_list(); `src/query/query_opfunc.c:625` qdata_generate_tuple_desc_for_valptr_list() rebuilds the descriptor per tuple; `:356` qdata_copy_db_value_to_tuple_value() memcpy per value; `src/query/fetch.c:4852` fetch_val_list() evaluates every regu variable into DB_VALUEs first; `src/query/query_hash_join.c:4277` probe output path | `src/include/executor/executor.h:322` ExecProcNode() returns `TupleTableSlot *` **by reference**; `src/backend/executor/execTuples.c:1017` slot_deform_heap_tuple() deforms lazily and only up to the highest attribute requested, called from `:751` tts_buffer_heap_getsomeattrs(); `src/backend/executor/nodeHash.c:1774` ExecHashTableInsert() with `:1779` ExecFetchSlotMinimalTuple() materializes **only** where a tuple must be stored | CUBRID copies every tuple crossing every node boundary into a list-file record (descriptor rebuild + per-value size computation + memcpy + clear), then re-decodes it downstream. PostgreSQL passes a slot pointer and materializes only at genuine storage points (hash table, spilling batch). Measured 6.26 vs 1.03 core-s at matched plan shape. | structural absence |
| Parallel-scan trace/statistics merge for a nested-loop subtree | `src/query/parallel/px_scan/px_scan_trace_handler.cpp:492-500` merge_xasl_tree() "for nl join" loop walks `xptr1 = xasl_tree->scan_ptr; xptr1 = xptr1->scan_ptr` calling xasl_merge_stats() once per level; `src/xasl/xasl_iteration.cpp:87` xasl_merge_stats() whose final statement `:205` is `iterate_xasl_tree<bool>(src, merge_stats, true)` — a walk of the **entire subtree**; `src/xasl/xasl_iteration.hpp:189-191` that walk recurses into `scan_ptr`; accumulating fields use `+=` at `xasl_iteration.cpp:120-135`; printed by `src/query/scan_manager.c:8680-8750` | `src/backend/executor/execParallel.c:1173` planstate_tree_walker() visits each PlanState **exactly once**; `:1115` InstrAggNode(planstate->instrument, &instrument[n]) aggregates one worker slot for the node currently visited; `src/backend/executor/instrument.c:232` InstrAggNode() touches only the node handed to it and never re-walks children | Two overlapping traversals both merge the same worker statistics in CUBRID, so a level-k nested-loop scan's counters are reported (k−1) times: measured exactly 2.0000x at depth 3 and 3.0000x at depth 4. PostgreSQL's merge is structurally single-visit. Results are unaffected; only the trace is. | structural absence |
| Data-page buffer-miss read path | `src/storage/page_buffer.c:2211` pgbuf_fix_release() (14.71% of native profile); miss path at `:8464` calls `src/storage/file_io.c:3935` fileio_read() = one synchronous `pread` of exactly one page on the calling query thread. Absence evidence: the multi-page `fileio_read_pages()` `file_io.c:4211` is called only from `src/transaction/log_page_buffer.c:2180` and `src/transaction/log_writer.c:803,1399` (log pages only); the sole `posix_fadvise` is a mount-time whole-volume advise at `file_io.c:3050`; the sole `aio_read` in the tree is inside a `pread()` compatibility shim that immediately calls `aio_suspend` at `file_io.c:3745-3767`; `io_uring`/`libaio`: 0 occurrences | `src/backend/storage/aio/read_stream.c:1030` read_stream_next_buffer() streaming reads for sequential scans; `src/backend/storage/aio/method_worker.c:121` pgaio_worker_ops, `:482` pgaio_worker_submit(), `:687` IoWorkerMain() with `io_method=worker` verified live (4 io worker processes); `src/backend/storage/buffer/freelist.c:442` BAS_BULKREAD ring | CUBRID blocks the query thread for each missed page, so page-cache copy is on the critical path: 3.00 core-s at matched shape, 3.96 core-s natively. PostgreSQL performs the wait and copy in io worker processes: 0.78 core-s inside its executor plus 2.72 core-s off the critical path. | same stage, lower measured cost |
| Buffer retention for a working set larger than the pool | `src/storage/page_buffer.c` victim selection / LRU zones (`pgbuf_get_victim`, `pgbuf_get_victim_candidates_from_lru`, `pgbuf_lru_boost_bcb` in profile) | `src/backend/storage/buffer/freelist.c:442` BAS_BULKREAD confines a large sequential scan to a small ring so it does not evict the rest of the pool | At matched plan shape CUBRID retains 23.0% of a 13.06 GiB working set in its 8 GiB pool; PostgreSQL retains 47.5% of 10.85 GiB in its 8 GiB pool (2.07x more). Same root cause as IMP-002 from Q01, now measured without plan confounding. | same stage, lower measured cost |
| Tuple attribute extraction | `src/storage/heap_file.c:10464` heap_attrinfo_read_dbvalues() materializes each needed attribute into a DB_VALUE before any predicate or projection sees it (10.52% controlled, 2.49% native) | `src/backend/executor/execTuples.c:1017` slot_deform_heap_tuple() deforms in place into the slot's datum/isnull arrays, bounded by `natts` actually requested (21.62% via tts_buffer_heap_getsomeattrs) | Comparable absolute cost at matched shape (7.79 vs 6.47 core-s), and PostgreSQL's is proportionally *larger*. Not a CUBRID-specific defect; recorded so the IMP-006 band is not inflated by lumping attribute extraction into it. | common to both engines |
| Independence assumption for anti-correlated range predicates | CUBRID final estimate card 1,399,146 vs actual 302,114 (4.63x over), from `sel 0.483075 × 0.540797` treated as independent (`q3-plan-est-cubrid.out` term[3], term[4]) | PostgreSQL `rows=629299` partial / 3,146,495 final vs 114,003 actual groups (`q3-plan-act-pg.out`) | Both engines multiply the selectivities of `o_orderdate < D` and `l_shipdate > D` as if independent, and both are wrong in the same direction by a similar factor. Neither misestimate changes its engine's plan choice here. | common to both engines |

## 8. Causal decomposition details

1. **CUBRID's plan choice is correct and worth 1.4125x; the loss is entirely
   execution cost.** `F_plan = 0.707996` is a same-engine A/B: forcing CUBRID onto
   PostgreSQL's shape costs it 6.791 s versus 4.808 s native. The reverse
   counterfactual agrees in direction — forcing PostgreSQL onto CUBRID's shape costs
   it 15.818 s versus 3.770 s (EXPLAIN ANALYZE, 4.5x) — so each optimizer is choosing
   the better plan *for its own engine*, and no plan-choice defect exists on either
   side. This is the first Q in this campaign where the plan factor is a measured
   number rather than `UNMEASURED`.
2. **At matched plan shape the work is identical and the CPU is not.**
   `F_work = 0.998080` (118,590,174 vs 118,818,354 tuple touches, agreeing to 0.19%
   node by node, section 4), so `F_cpu = 2.256272` is per-tuple cost with the plan
   variable removed: **424.7 ns vs 187.8 ns**.
3. **The per-tuple deficit is instruction count, not stalling.** `perf` at matched
   shape: 2,274.3 vs 991.4 instructions per tuple touch (**2.294x**) at essentially
   equal instruction throughput (5.356e9 vs 5.278e9 instructions per core-second,
   1.015x; IPC 1.96 vs 1.95). `2.294 × 0.985 = 2.260 = F_cost` to three decimals.
   Native CUBRID's IPC of 0.94 is a **plan** artifact — random B-tree descent and
   scattered page fetches — and disappears at the matched shape, which is why it must
   not be quoted as an engine property.
4. **Localisation of the instruction excess.** The largest identifiable band is
   intermediate-tuple materialization: 12.43% of profiled self cost = 6.26 core-s
   (`fetch_val_list` 3.81 + `qdata_generate_tuple_desc_for_valptr_list` 3.04 +
   `qdata_copy_db_value_to_tuple_value` 2.84 + `qfile_generate_tuple_into_list` 1.51 +
   `qdata_get_tuple_value_size_from_dbval` 1.23), against PostgreSQL's only comparable
   band of 1.03 core-s, which exists solely because its hash spills. Difference
   5.23 core-s = **18.7%** of the 28.04 core-s excess (IMP-006). Second is
   critical-path kernel I/O: 3.00 vs 0.78 core-s, difference 2.22 core-s = **7.9%**
   (IMP-007). Third is mutex/locking: 2.97 vs 0.21 core-s. Attribute extraction is
   explicitly *not* in the excess — PostgreSQL spends proportionally more there.
5. **Parallel utilization is not CUBRID's problem in Q03 — the opposite.** At matched
   shape CUBRID reaches TWU 7.4110 (max 12.62, nested parallel hash-join operators)
   against PostgreSQL's 6.3423 (leader + 5 workers + up to 4 io workers), so
   `F_units = 0.851451 < 1` and CUBRID is *credited* 1.1755x for concurrency. Its
   native plan is the lower-utilization one (TWU 4.6094, serial tail 0.338 s), and
   even there the native descriptive `F_units` of 1.379 is a **consequence of the plan
   it chose**, not a cap artifact: the cap is 6 and it launched 5 workers.
6. **The trace defect had to be corrected before `W_C_native` could be computed, and
   the correction is independently confirmed.** CUBRID's trace reported the
   `lineitem` level at exactly 2x (11,691,206 index entries and 604,228 lookups against
   a ground truth of 5,845,603 and 302,114). Corrected `ioread` (831,427 pages) × 16 KiB
   = 12.69 GiB matches the independently measured `rchar` of 13.09 GiB per statement to
   3.3%, whereas the uncorrected count implies 25.4 GiB — **1.92x more than the
   measured syscall bytes**, which is impossible. Section 9 / IMP-005 gives the source
   mechanism and a verified depth-4 prediction.
7. **Explanations considered and rejected, with the number that rejected each.**
   - *"CUBRID is slower because it picked the wrong plan."* Rejected: its plan is
     1.4125x **better** than the PostgreSQL-shaped alternative on the same engine, and
     PostgreSQL's plan is 4.5x better than the CUBRID-shaped alternative on its engine.
   - *"CUBRID is slower because it does more work."* Rejected: natively it touches
     **11.0x fewer** tuples (10,766,102 vs 118,818,354) and still loses.
   - *"CUBRID stalls on memory (IPC 0.94 vs 1.95)."* Rejected as an engine property:
     at matched plan shape CUBRID's IPC is **1.96** versus PostgreSQL's 1.95. The
     native IPC collapse is caused by the plan's random access pattern, and it is
     already inside `F_plan`.
   - *"CUBRID's parallelism is inferior."* Rejected: `F_units = 0.851451`, i.e. at
     matched shape CUBRID runs **more** concurrent units (TWU 7.4110 vs 6.3423).
   - *"CUBRID lacks read combining, so it issues many more I/O submissions."*
     Rejected by measurement even though the code fact is real (`fileio_read` reads
     exactly one page; `fileio_read_pages` is log-only): CUBRID moves **17.2 KiB per
     read syscall** (13,594,346,680 B in 829,884 calls) versus PostgreSQL's
     **15.4 KiB** (8,694,806,235 B in 551,551 calls), and PostgreSQL's 551,551 calls
     for ~900,213 block reads average 1.63 blocks per call, not the 16 that
     `io_combine_limit` allows. This sub-hypothesis was removed from IMP-007, which was
     downgraded from P1 to P2 as a result.
   - *"PostgreSQL's 1.17 GiB temp spill is a first-order cost."* Rejected: device
     `write_bytes` is 22.28 MiB against 2.60 GB of `write_bytes` at the process level,
     so the spill lives in the OS page cache; its CPU is already carried by `F_work`
     and counting it as I/O would double-count.
   - *"IMP-001 (NUMERIC aggregate accumulation) applies to Q03."* Rejected as
     material: the same code path runs, but over **302,114** rows here versus
     **59,986,052** in Q01, and no NUMERIC accumulation symbol reaches the 0.3%
     profile cutoff in either Q03 profile. No Q03 relation was added to IMP-001 rather
     than recording a relation the profile does not support.
   - *"The 4.63x final-cardinality misestimate matters."* Rejected: both engines make
     the same independence error on the two anti-correlated date predicates, and
     neither changes plan because of it.

Error budget and closure: residual −1.0259% against a combined within-block relative
sd of 0.387% **plus** the measured single-statement-per-connection regime offsets of
+0.495% (CUBRID controlled) and +1.537% (PostgreSQL), whose differential predicts
−1.0259%. Prediction matches observation to **0.000 pp**, so the residual is accounted
for deterministically rather than absorbed into noise. The card is closed.

## 9. Improvements

Registry state before Q03: `IMP-001`…`IMP-004`, `next_id: IMP-005`. Deduplication: the
Git ledger was searched by title, both source locations and root cause. `IMP-001`
(NUMERIC accumulation, `numeric_opfunc.c:2477`), `IMP-003` (LIKE selectivity,
`histogram_cl.cpp:1427`) and `IMP-004` (UTF-8 LIKE matcher,
`language_support.c:2831`) touch no path Q03 exercises materially. `IMP-002`
(data-buffer replacement, `page_buffer.c`) **is** Q03's root cause for retention, so
Q03 was added to it as a supporting relation with matched-shape evidence rather than
allocating a duplicate ID. Three new IDs were allocated; `next_id` advances to
`IMP-008`. No old-campaign candidate ID was consulted.

| ID | Root cause | Priority | Category | Status | Evidence type | Effect |
|---|---|---|---|---|---|---|
| `IMP-006` | Every intermediate join result tuple is materialized into a list-file page via a per-value DB_VALUE→tuple copy, where PostgreSQL passes a `TupleTableSlot` by reference | **P1** | intermediate-result | `measured` | profile attribution | 6.26 vs 1.03 core-s; **18.7% of the 28.04 core-s matched-shape CPU excess** |
| `IMP-007` | Every data-page buffer miss is a synchronous single-page `pread` on the query thread, so page-cache copy sits on the executor's critical path | **P2** | buffer/IO | `measured` | profile attribution | 3.00 vs 0.78 core-s critical-path; **7.9% of the excess**; 3.96 of 21.91 core-s natively |
| `IMP-005` | Parallel-scan trace statistics for a nested-loop subtree are merged once per `scan_ptr` level *and* by the whole-subtree walk, so a level-k scan is counted (k−1) times | **P2** | parallelism | `measured` | direct A/B | Diagnosability only, zero runtime effect; exactly **2.0000x** at depth 3 and **3.0000x** at depth 4 |
| `IMP-002` | (existing, Q01) Data-buffer replacement retains far less of a working set larger than the pool than PostgreSQL's ring strategy | P3 | buffer/IO | `observed` | upper bound | Q03 relation added: retains **23.0%** of 13.06 GiB vs PostgreSQL **47.5%** of 10.85 GiB at matched plan shape (**2.07x**) |

**Ranking justification.** `IMP-006` outranks `IMP-007` on measured share of the
matched-shape CPU excess (18.7% vs 7.9%) and on generality — every multi-node plan in
the workload pays the materialization cost, whereas `IMP-007` only bites when the
working set exceeds the buffer pool (true for Q03's 13.06 GiB against an 8 GiB pool,
false for Q02's 1.86 GiB). `IMP-007` outranks `IMP-006` on cost-effectiveness: its
first step is an advisory `posix_fadvise` reusing machinery that already exists
(CBRD-22319), while `IMP-006` is a structural executor change — which is why
`IMP-006`'s cheap sub-step (caching the tuple descriptor instead of rebuilding it per
tuple, 3.04% of profiled cost on its own) is called out separately. `IMP-005` is last
on runtime effect, which is zero, but is recorded at P2 rather than P3 because it is a
prerequisite for trusting the others: Q03's own `W_C_native` would have been wrong by
1.54x had the trace been believed. The three effects are **not summed**: `IMP-006` and
`IMP-007` are disjoint profile bands (verified disjoint by symbol), `IMP-002` reduces
the *number* of misses while `IMP-007` reduces the *cost per* miss, and part of the
1.68x byte difference against PostgreSQL belongs to `IMP-002`, not `IMP-007`.

### IMP-006 — intermediate tuples are copied into list files instead of passed by reference

- **Mechanism, CUBRID.** For each tuple crossing a node boundary CUBRID calls
  `fetch_val_list()` (`src/query/fetch.c:4852`) to evaluate every regu variable into
  DB_VALUEs, `qdata_generate_tuple_desc_for_valptr_list()`
  (`src/query/query_opfunc.c:625`) to rebuild a tuple descriptor, computes each value's
  on-tuple size, memcpy's each value into the list-file page via
  `qdata_copy_db_value_to_tuple_value()` (`:356`) driven by
  `qfile_generate_tuple_into_list()` (`src/query/list_file.c:1851`, called per output
  tuple at `src/query/query_executor.c:1255-1259` and from the hash-join probe at
  `src/query/query_hash_join.c:4277`), then clears the DB_VALUEs. Every downstream node
  re-reads and re-decodes that record.
- **Mechanism, PostgreSQL.** `ExecProcNode()`
  (`src/include/executor/executor.h:322`) returns a pointer to the child's
  `TupleTableSlot`; attributes are deformed lazily and only as far as requested
  (`src/backend/executor/execTuples.c:1017` `slot_deform_heap_tuple`, from `:751`).
  A copy happens only where a node must retain the tuple — the hash table stores a
  `MinimalTuple` (`src/backend/executor/nodeHash.c:1774`/`:1779`) and a spilling batch
  writes to a `SharedTuplestore`.
- **Why the direction follows.** The two plans do provably identical work
  (`F_work = 0.998`), so the 2.294x instruction-per-tuple gap must come from
  per-tuple overhead, and the largest band with **no PostgreSQL counterpart** is the
  copy itself: PostgreSQL pays 1.03 core-s only because its hash spills, while CUBRID
  pays 6.26 core-s unconditionally.
- **Evidence event and denominator.** CPU-seconds in the materialization band per
  statement; denominator 118,590,174 CUBRID vs 118,818,354 PostgreSQL tuple touches
  (0.19% apart). Raw: `profile-cubrid-hash-flat.txt`, `profile-pg-flat.txt`,
  `Q03-cubrid-hash-telemetry-run3.json`, `Q03-postgresql-telemetry-run1.json`.
- **Effect range.** Upper bound 6.26 core-s; difference against PostgreSQL's
  comparable band 5.23 core-s = 18.7% of the 28.04 core-s matched-shape excess. No
  wall-clock claim is made for CUBRID's native plan, where the band is smaller because
  the plan materializes 10,766,102 touches instead of 118,590,174.
- **Implementation direction.** Give `BUILDLIST_PROC` a streaming output mode that
  hands the parent a value-array view instead of calling
  `qfile_generate_tuple_into_list` (`query_executor.c:1255`), and let the hash-join
  probe (`query_hash_join.c:4277`) emit that view directly to an order-consuming
  parent. Cheap first step in the same direction: cache the tuple descriptor across
  tuples rather than rebuilding it per tuple (`query_opfunc.c:625`), 3.04% of profiled
  cost on its own.
- **Correctness/regression risk.** High for the full change — list-file records carry
  the tuple format that sort, group-by, hash join, subquery cache and the client
  protocol all decode, and a referenced tuple's lifetime must outlive the parent's use
  of it. The descriptor-caching sub-step is low risk and independently testable.
- **Validation criteria.** (1) controlled-plan `total_query_cpu` below 40 core-s with
  byte-identical output vs `sink/Q03-cubrid-hash-block.out`; (2) qdata/qfile band below
  6% of profiled self cost; (3) Q01–Q22 results byte-identical; (4) native Q03 median
  wall ≤ 4.808 s; (5) for the sub-step alone,
  `qdata_generate_tuple_desc_for_valptr_list` below 0.5%.
- **Priority.** **P1** — largest measured share (18.7%) of the matched-shape CPU
  excess and the most general, but not P0 because the fix is structural and no direct
  A/B yet proves the recoverable wall-clock share.
- **Difficulty.** **High** — list files are the universal currency between XASL nodes,
  so pass-by-reference pipelining is an executor-structure change.
- **Upstream precedent.** Partial: `5795b1ab6 [CBRD-26900]` (evaluate after-join
  predicates in the probe loop, #7269) and `cb2c79715 [CBRD-26648]` (partial aggregate
  with hash table, #6949) both reduce work on this edge without removing the copy. No
  direct precedent for pass-by-reference pipelining.

### IMP-007 — every buffer miss is a synchronous single-page read on the query thread

- **Mechanism, CUBRID.** `pgbuf_fix_release()`
  (`src/storage/page_buffer.c:2211`) looks the page up; on a miss it calls
  `fileio_read()` (`:8464`) which performs one `pread` of exactly one 16 KiB page
  (`src/storage/file_io.c:3935`) on the calling query thread and blocks. Structural
  absence, with searched paths recorded: multi-page `fileio_read_pages()`
  (`file_io.c:4211`) is called only from `log_page_buffer.c:2180` and
  `log_writer.c:803,1399`; the only `posix_fadvise` is a mount-time whole-volume advise
  (`file_io.c:3050`); the only `aio_read` sits inside a `pread()` shim that immediately
  calls `aio_suspend` (`file_io.c:3745-3767`); `io_uring` and `libaio` do not appear.
- **Mechanism, PostgreSQL.** Sequential scans pull from a `ReadStream`
  (`src/backend/storage/aio/read_stream.c:1030`) and submit through `io_method=worker`,
  so an io worker process (`method_worker.c:482`/`:687`) performs the wait and copy
  while the executor continues.
- **Why the direction follows.** The cost is not eliminable but it is movable: 3.00
  core-s of kernel copy sits inside CUBRID's query threads against 0.78 core-s inside
  PostgreSQL's executor, with PostgreSQL's remaining 2.72 core-s overlapped in io
  workers.
- **Evidence event and denominator.** CPU-seconds of kernel page copy/lookup charged
  to executor threads; denominator = bytes read from outside the pool per statement
  (12.66 GiB CUBRID controlled, 8.10 GiB PostgreSQL, both from `/proc/<pid>/io rchar`).
- **Effect range.** 2.22 core-s of critical-path CPU at matched shape (7.9% of the
  excess); up to 3.96 of 21.91 core-s in the native plan. Explicitly an **upper bound
  on what asynchrony could move**, not a wall-clock prediction: PostgreSQL spends
  0.432 core-s per GiB read in total against CUBRID's 0.221, so a naive port of the
  io-worker design would *increase* total CPU.
- **Rejected sub-hypothesis.** "CUBRID lacks read combining, so it issues far more I/O
  submissions" — refuted by 17.2 KiB per read syscall (CUBRID) vs 15.4 KiB
  (PostgreSQL), and PostgreSQL averaging 1.63 blocks per call rather than 16. Removed
  from the candidate; priority downgraded P1 → P2.
- **Implementation direction.** (1) per-scan `posix_fadvise(POSIX_FADV_WILLNEED)`
  reusing the existing parameter machinery (`file_io.c:3050`); (2) batch the miss path
  with the existing `fileio_read_pages()` for sequential scans, justified by call
  overhead only; (3) genuine async data-page I/O only if (1) and (2) prove
  insufficient.
- **Correctness/regression risk.** Low for (1) (advisory); medium for (2) — must not
  cross volume/extent boundaries, must respect page validation and the double-write
  buffer (`page_buffer.c:8454` `dwb_read_page` precedes `fileio_read` on the same
  path); high for (3).
- **Validation criteria.** (1) kernel band below 3% of profiled self cost at matched
  shape with unchanged bytes read and controlled median wall below 6.5 s; (2) native
  median wall no worse than 4.808 s; (3) `total_query_cpu` does not increase;
  (4) `/proc` `syscr` recorded before and after so any submission-count claim is
  measured; (5) Q01–Q22 results unchanged.
- **Priority.** **P2**, downgraded from P1 after the combining hypothesis was refuted.
- **Difficulty.** **Medium-to-high** overall; step (1) alone is low.
- **Upstream precedent.** Yes for readahead: `a05cfaa59 [CBRD-22319]` "add system
  parameter for read ahead fadvise" (#1282) introduced exactly the machinery step (1)
  extends. None for data-page read batching or async data-page I/O.

### IMP-005 — parallel-scan trace statistics count nested-loop levels (depth−1) times

- **Mechanism, CUBRID.** Each parallel worker executes a private XASL clone; on
  completion `merge_xasl_tree()`
  (`src/query/parallel/px_scan/px_scan_trace_handler.cpp:492-500`) folds it into the
  coordinator's tree, iterating the `scan_ptr` chain and calling `xasl_merge_stats()`
  per level. `xasl_merge_stats()` (`src/xasl/xasl_iteration.cpp:87`) does **not** merge
  one node: its final statement (`:205`) is
  `iterate_xasl_tree<bool>(src, merge_stats, true)`, which recurses through `scan_ptr`
  (`src/xasl/xasl_iteration.hpp:189-191`) and merges every node in the subtree by
  `header.id` with `+=` (`xasl_iteration.cpp:120-135`). Level 2 is therefore merged
  once, level 3 twice, level 4 three times — level k, (k−1) times. Introduced by
  `0c6088ab3 [CBRD-26722]` (#7062), an ancestor of the pinned build.
- **Mechanism, PostgreSQL.** `planstate_tree_walker()`
  (`src/backend/executor/execParallel.c:1173`) visits each `PlanState` exactly once and
  calls `InstrAggNode()` once per worker slot for that node (`:1115`); the merge
  primitive (`src/backend/executor/instrument.c:232`) never re-walks children, so no
  node can be reached by two overlapping traversals.
- **Measurement — four independent observations.** (1) Q03 full scale: `lineitem`
  11,691,206 index entries and 604,228 lookups reported vs ground truth 5,845,603 and
  302,114 (**2.0000x**), while depth 2 is exact at 1,461,923 on both engines.
  (2) Serial control (index outer scan, no parallel scan): every level exact —
  1,079 / 5,422 / 21,847 / 1,056. (3) Same slice with a parallel outer scan forced by
  `c_custkey-0<5000`: depth 2 still exact, depth 3 exactly 2x (10,844 / 43,694 /
  2,112). (4) **Falsifiable prediction of the code reading, tested and confirmed**: a
  depth-4 chain must report 3x — measured depth-3 `lineitem` 17,810 vs 8,905
  (2.0000x) and depth-4 `partsupp` 26,715 vs 8,905 (**3.0000x**).
- **Effect range.** Diagnosability only; zero runtime effect. Magnitude exactly
  (depth−1) for depth ≥ 2 under a parallel outer scan. Whether the factor depends on
  worker count is **UNMEASURED** (all observations at `parallelism=6`, 5 launched
  workers); the code path implies it does not, since the duplication comes from
  traversal overlap rather than from the number of merged workers.
- **Implementation direction.** In `px_scan_trace_handler.cpp:492-500` remove the
  double traversal: either extract a single-node `merge_one_node()` from
  `xasl_merge_stats` and call it per level, or keep subtree semantics and drop the
  caller's `scan_ptr` loop. The `dptr_list` loop at `:496-499` needs the same review.
- **Correctness/regression risk.** Very low — trace/statistics fields only, feeding no
  plan decision, result or cost model. The regression risk is under-counting, which is
  why the serial control must reproduce byte-equal counters.
- **Validation criteria.** (1) the parallel depth-3 probe reports 5,422 / 21,847 /
  1,056, byte-equal to the serial control; (2) the depth-4 probe reports 8,905 not
  26,715; (3) Q03's trace reports 5,845,603 and 302,114, matching PostgreSQL's
  302,114; (4) Q02's correlated-subquery `MEMOIZE`/`SUBQUERY_CACHE` totals unchanged,
  proving the `dptr` path was not broken; (5) no result or timing change.
- **Priority.** **P2** — no runtime cost, but it is a precondition for trusting
  parallel-plan evidence, and it is the cheapest, lowest-risk fix in the registry.
- **Difficulty.** **Low** — a one-loop change.
- **Upstream precedent.** Yes, same class and same subsystem, all ancestors of the
  pinned build: `85984d18d [CBRD-26839]` (#7219), `2be90e6dd [CBRD-26704]` (#7043),
  `34fc7779a [CBRD-26681]` (#7018).

None of the three is marked `validated`: no correctness evidence for a fix exists yet.
Full fields in `reports/improvement-registry.json`.

## 10. Evidence index

Format: `claim → raw file → formula → evidence type → SHA-256`.
All paths are under `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q03/`; byte sizes and
full hashes for all **74** artifacts are in `reports/Q03/raw-manifest.json`.

| Claim | Raw file | Formula / basis | Evidence type | SHA-256 |
|---|---|---|---|---|
| preflight: ownership OK, 34 TIDs 0 off-cpuset, 8FK/8-btree, row counts, contract values, provenance, **external load 6.185 FAIL** | `preflight-Q03.txt` | direct capture | direct A/B | see manifest |
| post-block ownership OK, 0 orphans, 34 TIDs 0 off-cpuset, pool conserved 524,288 pages | `q3-postcheck.txt` | direct capture | direct A/B | see manifest |
| Q03 `result-equivalent-at-SF10`, 10 rows ordered | `q3-correctness.json` | ordered sequence compare, 1e-12 relative on numerics | direct A/B | see manifest |
| `LIMIT 10` boundary strictly separated (row 10 415367.1195 vs row 11 411836.2827), 114,003 groups, 113,915 distinct revenues | `q3-boundary-cubrid.out`, `q3-boundary-pg.out` | LIMIT 12 + unlimited counts | direct A/B | see manifest |
| join ground truth 302,114 rows / 114,003 groups, identical both engines | `q3-groundtruth-cubrid.out`, `q3-groundtruth-pg.out` | `count(*)`, `count(distinct l_orderkey)` | direct A/B | see manifest |
| CUBRID estimated plan, non-executing (0.02 s, no rows), 3-level idx-join on FK indexes | `q3-plan-est-cubrid.out`, `q3-plan-est-cubrid.time` | `SET OPTIMIZATION LEVEL 514` | direct A/B | see manifest |
| PostgreSQL estimated plan + live `Settings:` | `q3-plan-est-pg.out` | `EXPLAIN (COSTS, VERBOSE, SETTINGS)` | direct A/B | see manifest |
| CUBRID 3 headline values, median 4.808000 s, warmup −0.83%, pool conserved | `Q03-cubrid-headline.json` | median of 3 measured statements | direct A/B | see manifest |
| CUBRID sink, 4 statements × 10 rows fully consumed, 3987 B | `Q03-cubrid-headline.out` | per-statement `(N sec)` lines | direct A/B | `d3f7537300ce6a2b…` |
| PostgreSQL 3 headline values, median 3.498678 s, `heap_blks_read` +751,088/statement | `Q03-postgresql-headline.json` | median of 3 measured statements | direct A/B | see manifest |
| PostgreSQL sink, 4 statements × 10 rows fully consumed, 1482 B | `Q03-postgresql-headline.out` | `\timing` per statement | direct A/B | `738a55c36d5b8205…` |
| both headline blocks measured under external load ≤ 1.5 (`CLEAN`, max 0.875 / 0.832) | `Q03-cubrid-bgload.json`, `Q03-postgresql-bgload.json` | host-wide SUT busy minus absolute campaign CPU, 4 Hz | direct A/B | see manifest |
| load-monitor calibration: host peak 8.06 cores, campaign attribution 7.96, external ≤ 0.80 | `q3-bgload-monitor-validation.json` | live 4-statement PG block | direct A/B | see manifest |
| CUBRID actual plan/trace: `parallel workers: 5`, FK B-trees, GROUPBY 114,003, depth-3 counters 2x | `q3-trace-cubrid.out` | `SET TRACE ON` + `SHOW TRACE` | direct A/B | see manifest |
| PostgreSQL actual plan: `Workers Launched: 5`, `Batches: 16`, `temp written=153640`, 302,114 join rows | `q3-plan-act-pg.out` | `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, TIMING)` | direct A/B | see manifest |
| **controlled anchor**: CUBRID `/*+ USE_HASH */` reaches PostgreSQL's shape with identical per-node counts | `q3-trace-cubrid-hash.out`, `q3-plan-est-cubrid-hash.out` | `SET TRACE ON` + hint | direct A/B | see manifest |
| controlled anchor timings, same regime: median 6.791000 s | `Q03-cubrid-hash-block.out` | 1 warmup + 3 measured, one connection | direct A/B | see manifest |
| join-method counterfactuals: USE_HASH 7.767 / USE_MERGE 11.565 / USE_NL 4.955 s | `q3-plan-ab-cubrid.out` | wall per statement, one connection | direct A/B | see manifest |
| reverse counterfactual: PostgreSQL forced to NL shape = 15,818 ms (4.5x its native) | `q3-plan-act-pg-nl.out` | `EXPLAIN ANALYZE` under GUC | direct A/B | see manifest |
| CUBRID native `total_query_cpu` 21.91 core-s, TWU 4.6094, tail 0.338 s | `Q03-cubrid-telemetry-run1.json` | per-TID ticks / `SC_CLK_TCK`, actual dt weighting | profile attribution | see manifest |
| PostgreSQL `total_query_cpu` 22.32 core-s (io workers 2.72 auxiliary), TWU 6.3423 | `Q03-postgresql-telemetry-run1.json` | per-TID ticks, actual dt weighting | profile attribution | see manifest |
| CUBRID controlled `total_query_cpu` 50.36 core-s, TWU 7.4110, max 12.62 | `Q03-cubrid-hash-telemetry-run3.json` | per-TID ticks, actual dt weighting | profile attribution | see manifest |
| telemetry reproducibility (3 runs per engine/variant) and +0.495%/+1.537% regime offsets | `Q03-{cubrid,postgresql,cubrid-hash}-telemetry-run{1,2,3}.json` | wall vs headline median | profile attribution | see manifest |
| CUBRID native IPC 0.94, 4.638 CPUs utilized | `perf-stat-cubrid.txt` | `instructions/cycles`, `task-clock/elapsed` | profile attribution | see manifest |
| CUBRID controlled IPC 1.96, 7.518 CPUs utilized | `perf-stat-cubrid-hash.txt` | `instructions/cycles` | profile attribution | see manifest |
| PostgreSQL IPC 1.95, executor-only PID set | `perf-stat-pg.txt` | `instructions/cycles` | profile attribution | see manifest |
| CUBRID native bands: buffer manager 25.49%, kernel page I/O 18.07%, 0 unresolved symbols | `profile-cubrid-flat.txt` | `perf report` self% | profile attribution | see manifest |
| CUBRID controlled bands: materialization 12.43%, kernel copy 5.95%, 0 unresolved symbols | `profile-cubrid-hash-flat.txt` | `perf report` self% | profile attribution | see manifest |
| PostgreSQL bands: deform/form 33.56%, spill 5.36%, kernel 4.06%, 0 unresolved symbols | `profile-pg-flat.txt` | `perf report` self% | profile attribution | see manifest |
| call paths for `pgbuf_fix_release`, `qfile_generate_tuple_into_list`, `ExecParallelHashJoin` | `profile-cubrid-callgraph.txt`, `profile-cubrid-hash-callgraph.txt`, `profile-pg-callgraph.txt` | dwarf call graph | profile attribution | see manifest |
| perf coverage: 92,548 / 104,292 / 151,266 samples, 0 lost, 0 `[unknown]` | `perf-record-cubrid.log`, `perf-record-pg.log`, `perf-record-cubrid-hash.log` | `perf record` stderr | profile attribution | see manifest |
| perf drivers consumed all rows (11 / 15 / 8 statements) | `Q03-cubrid-perf.out`, `Q03-postgresql-perf.out`, `Q03-cubrid-hash-perf.out` | statement result markers | direct A/B | see manifest |
| perf captures ran under external load ≤ 1.5 (`CLEAN`) | `perf-cubrid-bgload.json`, `perf-postgresql-bgload.json`, `perf-cubrid-hash-bgload.json` | 4 Hz load trace | direct A/B | see manifest |
| **IMP-005**: serial control exact (1,079/5,422/21,847/1,056) | `q3-doubling-trace.out` vs `q3-doubling-groundtruth.out` | trace counters vs `count(*)` ground truth | direct A/B | see manifest |
| **IMP-005**: parallel outer scan makes depth-3 exactly 2x (10,844/43,694/2,112) | `q3-doubling-parallel-trace.out` | same slice, parallel scan forced by `c_custkey-0<5000` | direct A/B | see manifest |
| **IMP-005**: predicted and confirmed depth-4 = 3x (26,715 vs 8,905) | `q3-doubling-depth4-trace.out` vs `q3-doubling-depth4-groundtruth.out` | (depth−1) prediction from the merge code | direct A/B | see manifest |
| `dynamic_shared_memory_type=mmap` live, `/dev/shm` 628k of 64000k, DSM file-backed; PG plan contains 2 Parallel Hash Joins + Gather Merge | `q3-shared-memory-verification.txt`, `q3-plan-act-pg.out` | direct capture | direct A/B | see manifest |
| perfmon `Num_data_page_*` unusable per block (identical across 0/1/2 statements) | `q3-perfmon-counter-probe.txt` | `cubrid statdump -c` before/after statements | direct A/B | see manifest |
| card factors, `W` per-node derivation, residual −1.0259% vs predicted −1.0259% | `Q03-causal-card.json` | section 16 formulas | profile attribution | see manifest |
| rejected perf attempts (collector overhead, `perf report` unpinned) | `perf-cubrid-bgload-attempt{1,2,3}-REJECTED.json` | load trace localised to post-driver window | direct A/B | see manifest (valid=false) |
| superseded pre-monitor-fix attempts, excluded from all calculations | `pre-monitor-fix/` + `INVALID.json` + `NOTE.md` | see section 5 | invalid | see manifest (valid=false) |

Not promoted (dispensable work per section 19): the raw `perf-*.data` files
(782 MB CUBRID native, 877 MB PostgreSQL, 1,219 MB CUBRID controlled). The derived
`perf stat`, flat and dwarf call-graph reports plus the `perf record` coverage logs are
promoted instead; the manifest records this decision under `not_promoted`.

## 11. Notion sync

**Status: `NOTION_OUT_OF_WORKER_SCOPE` → idempotent Git backfill record written
(write path 3 only).**

Section 21's execution boundary is explicit: this GJC/tmux worker session runs on the
remote build host, has no Notion connector, and **must never attempt a Notion write**.
Its Notion-adjacent duty ends at committing and pushing this report, manifest and
registry to `origin/main`. Accordingly:

1. *official Notion connector* — **not attempted** (forbidden for the worker; also not
   exposed to this session's tool set).
2. *logged-in Aside browser* — **not attempted** (forbidden for the worker).
3. *idempotent Git backfill record* — **written**: appended to
   `reports/notion_backfill_pending.jsonl`, keyed on
   `campaign_id + QNN + session_id + report_commit + content_fingerprint`, carrying the
   section 21 required query fields with the same field names as this report.
   `content_fingerprint` follows the Q01/Q02 convention: sha256 of this `report.md` at
   `report_commit`. The record is written only after the report, manifest and registry
   are durable on `origin/main`, so the key it carries is stable. `pending_cleared` is
   `false`.

This satisfies the section 26 gate item ("Notion relations are synced **or** an
idempotent backfill record is durable") without a Notion call. Pending is **not**
cleared: clearing requires a server-side refetch, which only a Notion-capable subagent
may perform. Per the section 21 execution boundary the actual mirror write —
operational state, the Q01–Q22 row, and one page per improvement candidate at the
section 21 content-depth floor — is performed by a dedicated Notion-capable subagent
dispatched during section 23 reconciliation, reading the pushed commit as source of
truth. Sections 3-a, 3-b, 4, 6, 7, 8 and 9 of this report are written to be that
mirror's source, including the full factor table, both engines' plan shapes with a
per-node row-count comparison, both engines' top-cost symbols, `file:line` on both
sides of every contrast, the rejected explanations with their rejecting numbers, and
the complete section 18 content for `IMP-005`, `IMP-006` and `IMP-007`.

## 12. Completion checklist

- [x] preflight and correctness status recorded (section 1, section 2), including the
      preflight external-load **FAIL** and the wait it forced
- [x] three valid headline values for each completing engine (both completed; neither
      censored), every accepted block verified `CLEAN` against the section 9 external
      load threshold at 4 Hz
- [x] timeout confirmations — not applicable, neither engine censored
- [x] plan, execution, profile and source contrast sections complete
- [x] causal multiplier card has evidence for every factor, with **`F_plan` measured
      (0.707996) via a same-engine controlled A/B** whose per-node row counts match
      PostgreSQL's to 0.19%; residual −1.0259% matches its measured prediction to
      0.000 pp
- [x] Git improvement ledger deduplicated and committed (`IMP-005`, `IMP-006`,
      `IMP-007` with the full section 18 field set including priority, category,
      difficulty, upstream precedent and ranking justification; `IMP-002` extended with
      a Q03 relation and matched-shape evidence; `next_id: IMP-008`). One candidate
      (`IMP-007`) was **narrowed and downgraded P1 → P2** when its read-combining
      sub-hypothesis was refuted by syscall measurement, and the refutation is recorded
      rather than dropped
- [x] every claim indexed to raw evidence and checksum (74 artifacts; 3 invalid load
      traces and the superseded `pre-monitor-fix/` set retained with `INVALID.json` and
      excluded from all calculations)
- [x] report, manifest and registry committed, pushed and reachable from `origin/main`
- [x] `QUERY_COMPLETE` emitted by the worker session
- [ ] **current session removed and absence verified — OUTSTANDING, control-plane
      action.** This worker *is* the Q03 session: tmux session
      `gajae_code_ms7i3rb7_gba2sjdp`. Self-removal would terminate the worker mid-turn
      and make the mandated dual absence check unobservable, so it is deliberately NOT
      claimed here. Per section 22 steps 7-9 and the section 23 `QUERY_COMPLETE`
      action, removal and absence verification are performed from outside this session,
      before any Q04 session is created:

      ```
      gjc session remove gajae_code_ms7i3rb7_gba2sjdp
      gjc session status gajae_code_ms7i3rb7_gba2sjdp      # expect: absent
      tmux has-session -t gajae_code_ms7i3rb7_gba2sjdp     # expect: non-zero exit
      # if remove refuses a live session, exact-target fallback (never by pattern):
      tmux kill-session -t gajae_code_ms7i3rb7_gba2sjdp
      ```

      The Q02 session `gajae_code_ms7esqu3_mj3cgscn` was verified absent at the start
      of this query by both checks (`gjc session status` →
      `gjc_tmux_session_not_found`, `tmux has-session` → exit 1), so the section 22
      "never two measurement sessions concurrently" rule held throughout Q03.

Harness changes made during Q03 (all under `harness/`, section 5 allowlist):

- `harness/bgload_monitor.py` (new) — during-run external SUT-set load trace, the
  missing half of the section 9 gate. Campaign CPU is an absolute sum with roots
  counted via `cutime+cstime`, so reaped per-statement backends and parallel workers
  are attributed rather than leaking into the external residual. Calibrated against a
  live PostgreSQL parallel block.
- `harness/wait_quiet.py` (new) — the pre-run half of the gate, shared by both runners
  so there is one gate implementation rather than two.
- `harness/measure_block.sh` (new) — gated headline-block runner: wait for quiescence,
  monitor throughout, accept only `CLEAN` blocks, retain rejected attempts as evidence.
- `harness/gated_run.sh` (new) — the same gate for the diagnostic stages (telemetry,
  perf).
- `harness/perf_run.sh` — pinned both `perf report` invocations to the collector CPUs
  (they are collectors per section 9, and unpinned dwarf decoding put ~1.2 cores on the
  SUT set); replaced the Q02-specific `query like '%p_size = 15%'` leader lookup with a
  QNN-agnostic one; added optional variant SQL/tag arguments for controlled-plan
  profiling and made driver sink/err paths variant-aware.
- `harness/telemetry_run.py` — added optional explicit SQL file and variant tag so a
  controlled-plan variant can be telemetered without touching the canonical query
  files, with variant-tagged output paths and `variant`/`query_file` recorded in the
  result JSON.

Known carried-forward gaps, explicitly recorded rather than silently omitted:

- CUBRID actual histogram bucket count remains `UNMEASURED` (opaque `VARBIT` catalog);
  target 300 is configured and verified. Q03's estimates are accurate on all three
  sargs, so this gap does not bind here.
- CUBRID's accumulating perfmon page counters are worse than "frozen": they advance at
  moments unrelated to statement execution (`q3-perfmon-counter-probe.txt`), so they
  are unusable as a per-block gauge. WARM evidence uses device `read_bytes`,
  `/proc/<pid>/io`, LRU zone conservation and the trace's per-node `ioread` instead.
- The stage-14.7 CPU numerators come from single-statement-per-connection telemetry
  runs, which sit +0.495%/+1.537% above the headline-regime medians. The effect on the
  card is quantified, predicted and closed rather than removed; a future harness change
  could sample CPU inside the headline block itself.
- `reports/bootstrap/build-manifest.json` pins `ssot_commit 1d6a5ea6…` while this query
  is pinned at `5912f065…`. The intervening SSOT changes touched the buffer/cache
  contract (already applied), the Notion execution boundary, the improvement-candidate
  quality bar and the shared-memory contract — no engine SHA, schema, statistics,
  parallel-worker or timing term — so no bootstrap finding is invalidated.
- **The measurement host is shared and contended.** Q03 is the first query measured
  under a bursty external neighbour load of up to ~6.3 cores on the 16-CPU SUT set,
  invisible from inside the container. Every timed value here is gated and verified
  `CLEAN`, but the practical consequence for Q04–Q22 is that block acceptance now
  depends on host conditions rather than on operator judgement. Concretely: the first
  CUBRID gate had to wait out roughly two minutes of sustained ~6-core neighbour load
  before it could start; under the corrected monitor both headline blocks and all six
  telemetry runs were accepted on their first attempt, while the perf captures were
  rejected three times before `perf report` was pinned to the collector CPUs and then
  passed first time. The gate, not the operator, decides.
- `F_plan` is measured for Q03 because a hint reproduces the contrasting shape with
  identical row counts. That will not generalise to every query; where no such anchor
  exists, `F_plan` must still be written `UNMEASURED` as in Q02.
- The CUBRID databases live under a repository-internal `.git_ignored_dir`; this is the
  reused SF10 dataset and moving it would be a destructive action outside the cleanup
  manifest, so it was left untouched and only recorded.
