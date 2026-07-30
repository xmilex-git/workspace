# TPCH-SSPQ FK campaign — Q01 report

## 3-a. Causal multiplier card

```text
R_wall 2.8070x [wall, median of 3 per engine]
= F_plan  1.0000x [plan-shape, structural equality]
× F_units 1.0197x [total-query-CPU/wall correction, explained by TWU]
× F_cpu   2.7407x [total query CPU-seconds]

F_cpu 2.7407x [total query CPU-seconds]
= F_work 1.0000x [heap rows scanned = 59,986,052, identical both engines]
× F_cost 2.7407x [total-query CPU-seconds per heap row scanned]
```

Reconstruction: `1.0000 × 1.01973 × 2.74071 = 2.79480` vs headline `2.80695`.
**Residual = 0.433%.** Measured error budget: within-block relative sd 0.266% (CUBRID)
and 0.188% (PostgreSQL), 0.326% combined in quadrature; additionally the stage-14.7
telemetry runs that supply the CPU numerators sat +0.177% (CUBRID) and +0.612%
(PostgreSQL) above their own headline medians, which alone accounts for most of the
residual. Residual is therefore inside the error budget and the card is closed.

| Factor | Value | Event unit | Denominator | Formula | Raw pointer | Evidence type |
|---|---|---|---|---|---|---|
| `F_plan` | 1.0000x | plan-node shape | n/a (anchor) | structural equality, see below | `q1-plan-est-cubrid.out`, `q1-trace-cubrid.out`, `q1-plan-act-pg.out` | structural equality |
| `F_units` | 1.01973x | active execution units | CPU-seconds / wall-second | `U_P/U_C`, `U=CPU/T` | `Q01-*-telemetry.json` | profile attribution |
| `F_cpu` | 2.74071x | total query CPU-seconds | per query execution | `CPU_C/CPU_P` | `Q01-*-telemetry.json` | profile attribution |
| `F_work` | 1.0000x | heap rows scanned | rows | `W_C/W_P` = 59,986,052/59,986,052 | `q1-trace-cubrid.out`, `q1-plan-act-pg.out` | direct A/B |
| `F_cost` | 2.74071x | CPU-seconds per row | rows scanned | `(CPU_C/W_C)/(CPU_P/W_P)` | `Q01-*-telemetry.json` | profile attribution |

`U_C = 186.67/31.248117 = 5.9738`, `U_P = 68.11/11.180813 = 6.0917`.
No factor double-counts: `F_work` is exactly 1.0000 because both engines scan the
identical row set, so the entire CPU gap is carried by `F_cost` and none of it is
re-attributed to plan or units.

`F_plan = 1.0000` is asserted on structural equality, not assumed: both engines
execute 6-way parallel heap scan → partial hash aggregation → sorted/mergeable
gather → final aggregate, over identical scanned (59,986,052), filtered
(59,142,609 passing, 843,444 removed) and output (4 rows) cardinalities, with no
index access and no spill on either side (CUBRID `GROUPBY ... page: 0, ioread: 0`;
PostgreSQL `Batches: 1  Memory Usage: 32kB`, `Sort Method: quicksort  Memory: 26kB`).
Instrument note: the CUBRID `SET OPTIMIZATION LEVEL 514` dump renders only a serial
`sscan` and does not surface the parallel operator; the trace proves
`parallel workers: 6`. That is a plan-dump limitation, not a shape difference.

## 1. Identity

| Item | Value |
|---|---|
| Campaign ID | `tpch-sspq-fk-r1-20260730` |
| QNN | Q01 |
| SSOT commit | `ad1433b43da6b047933b006e0c9a3d4ed4b6e13e` |
| SSOT blob | `3f7429271b5b77745cdad0673416d4f2032f6712` |
| GJC session ID | `gajae_code_ms7bmpvn_fqbk4jb6` |
| Raw dir | `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q01` |
| CUBRID source SHA | `607f1ee9fb2394de129e083602c84a6525fc685c` (incl. PR #7441 `b334446d6`) |
| CUBRID binary | `/home/cubrid/release/CUBRID-tpch-sspq-fk-r1-607f1ee9/bin/cub_server`, SHA-256 `e5043f0e30cbf4a56f219f833f4f4833687ed774895779450e84550c3d6f2a13` |
| PostgreSQL source SHA | `5713b437abed7085e7d59849c6e9e0f4f469633d` |
| PostgreSQL binary | `/home/cubrid/pg/pg20devel-5713b437/bin/postgres`, SHA-256 `f55cd1d705d0bc1656709d88ecdd8b7b5cf49706095022ec27fb745357b6602b` |
| CUBRID DB / port | `tpch_sf10_q1` / 1523 |
| PostgreSQL PGDATA / port | `/home/cubrid/pg/pgdata-tpch-sspq` / 5442 |

Both running binaries hash-match the frozen `reports/bootstrap/build-manifest.json`.
Ownership gates (section 10) classified **OK** before and after every measurement
block; no orphan csql/psql/backend remained after either block.

Query provenance: `queries/q1-cubrid.sql` byte-matches the canonical source
`/home/cubrid/dev/cubrid/.vscode/TPC-H/scale10/queries/q1.sql`, SHA-256
`205ae534e85af5cb00fa5fd4d62cffb1faf81a6b172b53be9102e06e5a844b50`. The PostgreSQL
dialect delta is one hunk, `DATE_SUB(DATE '1998-12-01', INTERVAL 90 DAY)` →
`date '1998-12-01' - interval '90' day`, pure syntax with a recorded reason.

Schema: 8 named FKs and 8 corresponding child B-trees verified on both engines with
exact child-column order, including composite `fk_lineitem_partsupp (l_partkey,
l_suppkey)`; all PostgreSQL `pg_constraint.convalidated = true`. Row counts are
exact-equal on both engines (canonical SF10; `lineitem` 59,986,052).

Contract state at measurement time:

- statistics: CUBRID `update_statistics_update_histogram=y`,
  `default_histogram_bucket_count=300` (target). Actual per-column bucket count
  remains **UNMEASURED**, carried forward from bootstrap (opaque serialized
  `VARBIT` in `_db_histogram`, no SQL-exposed bucket-count field). PostgreSQL
  standard `ANALYZE`.
- parallel, `configured node/gather-cap comparison`: CUBRID `parallelism=6`,
  `max_parallel_workers=100`; PostgreSQL `max_parallel_workers_per_gather=5`,
  `max_parallel_workers=5`, `parallel_leader_participation=on`,
  `max_worker_processes=16` (non-binding). The PostgreSQL values were corrected
  during this query's preflight from `6`/`8`, which were inherited
  pre-2026-07-30-campaign values (`# Target DOP 6 on both engines (ADR 0005)`);
  the corrected values are visible in the plan `Settings:` line.
- buffer/cache, `configured-equal buffer budget`: CUBRID `data_buffer_size=8.0G`,
  PostgreSQL `shared_buffers=8192MB`. Actual configured values recorded as
  required by section 9. This is not a claim of equivalent cache architecture,
  eviction policy or page format. Stored-size asymmetry under that equal budget:
  CUBRID `lineitem` heap = 682,937 pages x 16 KiB = **10.42 GiB**; PostgreSQL
  `lineitem` heap = 1,125,120 pages x 8 KiB = **8.58 GiB**. Both exceed the 8192 MB
  budget; CUBRID exceeds it by more.
- cpuset/NUMA: SUT+client CPUs `0-15`, collectors CPUs `20-23`. All 189 engine TIDs
  verified on `0-15` with 0 off-cpuset before and after each block.
  `cub_server` was restarted through the mandated
  `cubrid-server-ctl.sh` wrapper under `numactl --cpunodebind=0 --membind=0`
  because the prior instance had 99.6% of its resident pages on node 1; after the
  restart page placement is 2513.49 MB node0 / 4.51 MB node1 (99.8% node0) with
  `bind:0` on 572 mappings. PostgreSQL was already node0-resident.
- external SUT-set load before each block: 0.334 and 0.341 core-seconds/second,
  both under the 1.5 threshold. No `INVALID_BACKGROUND_LOAD`.

## 2. Correctness

**`result-equivalent-at-SF10`.** Not censored.

Q01 has `ORDER BY`, so the ordered result sequence was compared exactly. 4 rows on
both engines. All exact-integer and exact-decimal columns match as raw text to the
final digit (`sum_qty`, `sum_base_price`, `sum_disc_price`, `sum_charge`,
`count_order`). The three `avg_*` columns differ only in output scale — CUBRID emits
scientific notation (`2.550097510300710e+01`), PostgreSQL emits
`25.5009751030070973` — and were accepted under the section 11 rule
`abs(a-b) ≤ 1e-12 × max(1,|a|,|b|)`; the largest observed relative deviation is
~1.1e-16, five orders of magnitude inside the bound. Tolerance was applied only to
numeric fields and never to a row set or predicate decision; row count and row
multiset are identical.

Comparator: `harness/correctness_check.py` delegating to the bootstrap-verified
`harness/smoke_check.py` rules.

## 3-b. Headline timings

Regime `single-query-repeat WARM`; metadata connection mode
`single-connection-four-statements` (1 uncounted warmup + 3 measured, one direct
connection, no reconnect/prepare between measured statements, connection
establishment excluded). Engine-block order for odd QNN: CUBRID block, then
PostgreSQL block. Each statement fully consumed all 4 rows into a campaign-owned
fixed sink under `work/Q01/sink`; content hashes computed after the timers stopped.

| Field | CUBRID | PostgreSQL |
|---|---|---|
| warmup (uncounted) | 31.199999 s | 11.174569 s |
| measured run 1 | 31.192999 s | 11.143534 s |
| measured run 2 | 31.322999 s | 11.103748 s |
| measured run 3 | 31.167999 s | 11.112755 s |
| **median (headline)** | **31.192999 s** | **11.112755 s** |
| mean | 31.227999 s | 11.120012 s |
| within-block sd | 0.083217 s (0.266%) | 0.020862 s (0.188%) |
| sink bytes | 6027 | 2394 |
| sink SHA-256 | `688ccadc9c738478…` | `87ecd4a7c504b53b…` |

**Median wall ratio = 2.8070x (CUBRID / PostgreSQL).**
Correctness status `result-equivalent-at-SF10`; censoring status: not censored
(both engines well inside the 300 s timeout). No confidence interval is claimed
from three values.

WARM proof (proved, not assumed):

| Evidence | CUBRID | PostgreSQL |
|---|---|---|
| device `read_bytes` delta across block | 0 | 0 |
| warmup vs measured spread | 0.49% over all 4 statements | 0.64% over all 4 statements |
| engine buffer counters | `Num_data_page_lru3` 498,048 pre and post (stable) | `heap_blks_hit` +694,529/run, `heap_blks_read` +434,954/run |
| pages touched per run | 682,982 fetches | 1,125,128 blocks = full heap |

No WARM gate failure, so no run was invalidated or restarted.

## 4. Plan

CUBRID estimated (`SET OPTIMIZATION LEVEL 514`, verified non-executing: 0.02 s
wall, "There are no results", 0 rows):

```text
temp(group by)
    subplan: sscan
                 class: lineitem node[0]
                 sargs: term[0]
                 cost:  832902 card 58072645
    sort:  1 asc, 2 asc
    cost:  1176579 card 58072645
node[0]: dba.lineitem dba.lineitem(59986052/682937) (sargs 0)
term[0]: l_shipdate range (min inf_le date '09/02/1998') (sel 0.968102)
```

CUBRID actual (trace):

```text
SELECT (time: 31877, fetch: 683074, fetch_time: 4256, ioread: 682957)
  SCAN (table: dba.lineitem) (heap time: 31876, fetch: 682982, ioread: 682950,
        readrows: 59986052, rows: 59986052)
       (parallel workers: 6, heap time: 31595..31876,
        readrows: 9938887..10011920, gather: mergeable list)
  GROUPBY (time: 1, hash: partial, sort: true, page: 0, ioread: 0, rows: 4)
```

PostgreSQL actual (`EXPLAIN ANALYZE BUFFERS VERBOSE TIMING`): `Finalize
GroupAggregate` ← `Gather Merge` (Workers Planned 5, **Launched 5**) ← `Sort`
(quicksort, 26 kB) ← `Partial HashAggregate` (Batches 1, 32 kB) ← `Parallel Seq
Scan on lineitem` (`Filter: l_shipdate <= '1998-09-02'`, Rows Removed by Filter
140,574/loop, `loops=6`, `Buffers: shared hit=694494 read=430634`).
Planning Time 0.811 ms, Execution Time 11410.623 ms.

Predicate equivalence: both resolve the filter to `l_shipdate <= 1998-09-02`.
Estimate quality: CUBRID card 58,072,645 vs actual 59,142,609 passing (−1.8%);
PostgreSQL `rows=11827020` per worker vs actual 9,857,101.50 per loop.

**Node-level time attribution differs by convention and must not be read
cross-engine as-is.** PostgreSQL reports scan self-time ≈1.755 s and
`Partial HashAggregate` self-time ≈9.50 s. CUBRID reports `SCAN heap time 31876 ms`
and `GROUPBY time 1 ms` because the aggregation runs *inside* the parallel scan task
(`qexec_hash_gby_agg_tuple` is called from
`parallel_scan::result_handler<...>::write`, confirmed in the call graph), so
aggregate cost is folded into the scan node. The profile, not the node timers, is
the valid basis for attribution.

## 5. Execution telemetry

Non-headline diagnostic runs; sampler on CPUs `20-23`, per-TID, weighted by actual
sample timestamp deltas.

| Metric | CUBRID | PostgreSQL |
|---|---|---|
| wall of telemetry run | 31.248117 s | 11.180813 s |
| `executor_cpu` | 186.44 core-s (`parallel-query` 186.01, `transaction` 0.42, `connections` 0.01) | 65.08 core-s (`pg_parallel_worker` 54.19, `pg_backend` 10.89) |
| `auxiliary_query_cpu` | 0.23 core-s (engine bg 0.22 + csql 0.01) | 3.03 core-s (`pg_io_worker` 2.27, `pg_background` 0.76; psql 0.00) |
| `total_query_cpu` | **186.67 core-s** | **68.11 core-s** |
| planned workers | 6 (`parallelism=6`) | 5 + leader |
| launched workers | 6 (trace `parallel workers: 6`) | 5 (`Workers Launched: 5`) + leader = 6 |
| max simultaneous active units | 6.4136 | 6.6204 |
| time-weighted active units (TWU) | **5.9774** | **6.1209** |
| serial tail | 0.117 s | 0.122 s |
| `rchar` | 11,189,586,384 B (10.42 GiB) | 3,559,301,520 B (3.31 GiB) |
| read syscalls (`syscr`) | 683,272 | 462,763 |
| device read | 1.57 MiB total (unrelated dm-2/sdb traffic) | 0 |
| `unattributed_background` | none claimed | none claimed |

TWU is an independent cross-check of `U`, not a substitute: `U_C=5.9738` vs
TWU 5.9774; `U_P=6.0917` vs TWU 6.1209. Neither was derived from the configured
cap, and no nominal interval was used for weighting.

Buffer behaviour under the equal 8192 MB budget: CUBRID `ioread 682,950` of
`fetch 682,982` = **0.005% buffer hit rate** — the 10.42 GiB heap self-evicts from
the 8 GiB pool on every repeat. PostgreSQL retains **61.7%** (694,494 of 1,125,128).
Both are served from the OS page cache (device `read_bytes` = 0 on both), so this is
a CPU-path difference, not a disk-I/O difference. NUMA: `cub_server` 2513.49 MB
node0 / 4.51 MB node1 pre and post; no page migration during the runs.

## 6. Profile

Non-headline. `perf` attached to verified PID sets, never all-CPU.
CUBRID: `-p <cub_server 1445555>` (all worker threads are inside that process).
PostgreSQL: `-p` on the discovered leader `1450738` + exactly 5 parallel workers
`1450739-1450743` (+ io/background workers for the stat run).

Coverage validation against `perf stat`: CUBRID 24,300 samples, **0 lost**, 308
resolved symbol lines, **zero `[unknown]`**; PostgreSQL 9,552 samples, **zero
`[unknown]`**. task-clock cross-check: CUBRID 150,973.75 ms / 25.002 s = **6.038
CPUs utilized** vs TWU 5.9774; PostgreSQL 49,866.14 ms / 8.002 s = **6.232** vs
TWU 6.1209.

| Metric | CUBRID | PostgreSQL | Ratio |
|---|---|---|---|
| cycles (window) | 408,600,883,811 | 134,630,450,628 | — |
| instructions (window) | 1,032,341,216,962 | 316,912,611,280 | — |
| **IPC** | **2.527** | **2.354** | 1.073 (CUBRID better) |
| frequency | 2.706 GHz | 2.700 GHz | 1.002 |
| context-switches | 279,177 / 25 s | 168,806 / 8 s | — |
| instructions per row | **21,279** | **7,216** | **2.949** |
| cycles per row | **8,422** | **3,065** | **2.747** |

The gap is instruction count, not stalling: CUBRID retires 2.949x the instructions
per scanned row at 1.073x *better* IPC, yielding 2.747x cycles per row — consistent
with `F_cpu = 2.7407`.

Top self cost, CUBRID (`profile-cubrid-flat.txt`):
`float_numeric_db_value_add` 9.72%, `heap_attrinfo_read_dbvalues` 6.06%,
`float_numeric_db_value_mul` 5.67%, `qdata_add_dbval` 4.56%, `fetch_peek_arith`
3.63%, `pr_clear_value` 3.55%, `qdata_evaluate_aggregate_list` 3.41%,
`tp_value_cast_internal` 2.96%, `db_value_domain_init` 2.88%,
`float_numeric_db_value_sub` 2.82%, `qexec_hash_gby_agg_tuple` 2.54%,
`mr_data_readval_numeric` 2.30%, `malloc` 2.06%, `_int_free` 1.87%.

Top self cost, PostgreSQL (`profile-pg-flat.txt`):
`ExecInterpExpr` 13.79%, `init_var_from_num` 8.04%, `detoast_attr` 7.40%,
`AllocSetAlloc` 7.24%, `tts_buffer_heap_getsomeattrs` 6.46%, `make_result_safe`
5.65%, `mul_var` 4.46%, `accum_sum_add` 3.21%, `AllocSetFree` 2.26%,
`do_numeric_accum` 2.25%, `strip_var` 2.15%, `sub_abs` 2.11%, `palloc` 2.01%,
`numeric_mul_safe` 1.97%.

Banded (CUBRID, top-40 self): expression/NUMERIC/DB_VALUE **62.35%**,
alloc/memops 5.22%, buffer-fetch+tuple-deform 6.78% (of which the true page-fetch
path is under 1%: `pgbuf_get_vpid_ptr` 0.19%, `pgbuf_unlatch_void_zone_bcb` 0.06%,
`pgbuf_get_victim` 0.06%, kernel `filemap_get_read_batch` 0.13% +
`filemap_read` 0.07%). PostgreSQL's comparable expression/numeric band is ~59%.
Both engines are numeric-arithmetic bound; CUBRID's per-row cost in that band is
what differs.

Verified call path for the dominant CUBRID symbol:
`float_numeric_db_value_add` ← `qdata_add_numeric_to_dbval` ← `qdata_add_dbval` ←
`qdata_aggregate_value_to_accumulator` ← `qdata_evaluate_aggregate_list` ←
`qexec_hash_gby_agg_tuple` ← `parallel_scan::result_handler<1>::write` ←
`parallel_scan::task<1,0>::loop` ← `cubthread::worker_pool_impl<false>::…::run`.

## 7. Source contrast

| Item | CUBRID file:line | PostgreSQL file:line | Difference | Class |
|---|---|---|---|---|
| Per-row NUMERIC sum accumulation | `src/query/numeric_opfunc.c:2477` `float_numeric_db_value_add()`; reached via `src/query/query_opfunc.c:2059` `qdata_add_numeric_to_dbval()` | `src/backend/utils/adt/numeric.c:4821` `do_numeric_accum()` → `accum_sum_add()` (decl. `:603`) over `NumericSumAccum` (`:381`) | CUBRID runs the fully generalized operator per row: argument type/NULL validation, `db_get_numeric_precision_and_scale` on both operands, result precision/scale computation, `memset` of three `uint64_t[calc_words]` VLA buffers, `numeric_bytes_to_words` conversion (with `BSWAP64`) of both operands, optional `float_numeric_mul_normalize` rescale, the add, `float_numeric_get_decimal_digit` precision recomputation, `float_numeric_check_overflow_and_adjust_scale`, `float_numeric_round_and_pack`, then `db_make_numeric` to build a DB_VALUE. PostgreSQL's per-row work is `accum_digits[i] += (int32) val_digits[val_i]` over a 32-bit digit array with separate positive/negative buffers, **no carry propagation** until `num_uncarried == NBASE-1`, no allocation, no precision recomputation and no rounding; normalization happens once in `accum_sum_final()`. | same stage, lower measured cost |
| Aggregate-result lifecycle | `src/query/numeric_opfunc.c:2477` (`db_make_numeric` per row) plus `pr_clear_value` 3.55%, `db_value_domain_init` 2.88%, `malloc`+`_int_free` 3.93% in profile | `numeric.c` `accum_sum_add()` writes in place into the pre-sized accumulator; `AllocSetAlloc`/`palloc` costs are context-pooled | CUBRID materializes a DB_VALUE per row per aggregate and frees it, producing allocator churn in the hot loop; PostgreSQL mutates a persistent accumulator. | same stage, lower measured cost |
| Scan-resistant buffer replacement for large sequential scans | `src/storage/page_buffer.c` (LRU zone/victim selection; `pgbuf_get_victim`, `pgbuf_unlatch_void_zone_bcb` observed) | `src/backend/storage/buffer/freelist.c` (`BufferAccessStrategy`, `BAS_BULKREAD` ring) | CUBRID's replacement lets a scan whose working set exceeds the pool evict its own resident pages, reaching 0.005% reuse; PostgreSQL's bulk-read ring protects the resident set, retaining 61.7%. | structural absence |
| Tuple deform / detoast | `heap_attrinfo_read_dbvalues` 6.06%, `mr_data_readval_numeric` 2.30% | `tts_buffer_heap_getsomeattrs` 6.46%, `detoast_attr` 7.40%, `init_var_from_num` 8.04% | Comparable proportional cost on both sides; not a CUBRID-specific defect. | common to both engines |

Absence claim for the third row was established by searching the pinned CUBRID tree
`/home/cubrid/dev/tpch-sspq-fk-r1/cubrid-src` under `src/` for the symbols and
patterns `CUBRID_SOCK`-style ring/strategy equivalents: `grep -rn` over
`--include=*.c --include=*.cpp --include=*.h --include=*.hpp` for
`BufferAccessStrategy`, `BAS_BULKREAD`, `bulk.*read.*ring`, `ring buffer`,
`scan.*resistant` returned no counterpart; only generic LRU zone handling exists in
`src/storage/page_buffer.c`. No claim is made that adding one would be profitable
under this WARM regime — see IMP-002's upper bound.

## 8. Causal decomposition details

1. **Plan is not the cause.** `F_plan = 1.0000` by structural equality; both engines
   run the same 6-way parallel scan → partial hash aggregate → merge gather → final
   aggregate shape over identical cardinalities, neither spills, neither uses an
   index.
2. **Parallelism is not the cause.** `F_units = 1.0197`. Both engines actually ran
   6 units: CUBRID trace `parallel workers: 6` with TWU 5.9774 and `perf` 6.038
   CPUs utilized; PostgreSQL `Workers Launched: 5` + leader with TWU 6.1209 and
   `perf` 6.232. PostgreSQL's marginal 2% utilization advantage comes from its io
   workers (2.27 core-s of auxiliary CPU) overlapping the scan; CUBRID's serial tail
   (0.117 s) and PostgreSQL's (0.122 s) are equivalent.
3. **Work volume is not the cause.** `F_work = 1.0000` exactly — 59,986,052 rows
   scanned, 59,142,609 passing the identical predicate, 4 output rows on both sides.
4. **Per-row CPU cost is the cause.** `F_cost = 2.7407`: 3.1119 µs/row vs
   1.1354 µs/row. Decomposed by `perf`, this is 2.949x instructions per row at
   1.073x better IPC → 2.747x cycles per row, matching `F_cost` to within 0.3%.
   Since instruction count rather than IPC carries the gap, the cause is *amount of
   work executed per row*, not memory stalls, cache behaviour or frequency.
5. **Localisation.** 62.35% of CUBRID's profiled self cost sits in the
   expression/NUMERIC/DB_VALUE band, against ~59% for PostgreSQL — i.e. both spend a
   similar *fraction* there, so CUBRID's excess is concentrated in the same band
   rather than in a band PostgreSQL avoids. The single largest symbol,
   `float_numeric_db_value_add` (9.72%), is reached exclusively from the aggregate
   accumulation path, and the source contrast shows PostgreSQL performing the same
   logical step with a deferred-carry int32 accumulator. This is recorded as
   IMP-001.
6. **What is explicitly not claimed.** The 0.005% buffer hit rate is real but costs
   under 1% of CPU here because device `read_bytes` is 0 and the OS page cache
   absorbs every miss; it is filed as IMP-002 with an explicit upper bound, not
   folded into `F_cost` as a numeric contribution. The CUBRID/PostgreSQL stored-size
   asymmetry (10.42 GiB vs 8.58 GiB heap) is recorded but likewise not converted
   into a factor, since `F_work` is defined on rows and the byte difference would
   double-count the same scan.

Error budget and closure: residual 0.433% against a combined within-block relative
sd of 0.326% plus telemetry-run offsets of +0.177%/+0.612% from the respective
medians. The card is closed.

## 9. Improvements

| ID | Root cause | Status | Evidence type | Effect |
|---|---|---|---|---|
| `IMP-001` | Aggregate accumulation performs a fully generalized per-row NUMERIC add/mul instead of a deferred-carry fast sum accumulator | `measured` | profile attribution | Majority of the 2.74x total-query-CPU gap; bounded by the 62.35% expression/NUMERIC/DB_VALUE band |
| `IMP-002` | Data buffer replacement gives ~0% reuse for a repeated scan whose working set slightly exceeds the pool | `observed` | upper bound | **< 1% of query CPU** in this WARM regime (device `read_bytes` = 0) |

Registry state before Q01: empty, `next_id: IMP-001`. Deduplication: searched the
Git ledger by title, both source locations and root cause; no existing entry, so
`IMP-001` and `IMP-002` are new allocations and `next_id` advances to `IMP-003`. No
old-campaign candidate ID was reused or consulted. Effects are not summed: IMP-001
and IMP-002 touch disjoint code paths (aggregate accumulation vs page replacement)
and IMP-002's bound is deliberately stated as an upper bound rather than a share of
`F_cost`. Neither is marked `validated` — no correctness evidence for a fix exists
yet. Full fields in `reports/improvement-registry.json`.

## 10. Evidence index

Format: `claim → raw file → formula → evidence type → SHA-256`.
All paths are under `/data/tpch-sspq/tpch-sspq-fk-r1-20260730/raw/Q01/`; byte sizes
and full hashes are in `reports/Q01/raw-manifest.json` (36 artifacts).

| Claim | Raw file | Formula / basis | Evidence type | SHA-256 |
|---|---|---|---|---|
| preflight, ownership, cpuset, NUMA, schema, statistics, parallel contract | `preflight-Q01.txt` | direct capture | direct A/B | `2aa06d3863b83c07…` |
| Q01 `result-equivalent-at-SF10`, 4 rows ordered | `q1-correctness.json` | ordered sequence compare, 1e-12 relative on numerics | direct A/B | `3c7d8b4d8bfbb394…` |
| CUBRID result rows (raw decimal text preserved) | `q1-correctness-cubrid.out` | — | direct A/B | `a9e95312a339ddb4…` |
| PostgreSQL result rows (raw decimal text preserved) | `q1-correctness-postgresql.out` | — | direct A/B | `70368245b8a84846…` |
| CUBRID estimated plan, non-executing | `q1-plan-est-cubrid.out` | `SET OPTIMIZATION LEVEL 514` | direct A/B | `502d4609ca581145…` |
| PostgreSQL estimated plan + live `Settings:` | `q1-plan-est-pg.out` | `EXPLAIN (COSTS, VERBOSE, SETTINGS)` | direct A/B | `8e8c3dd7edde9679…` |
| CUBRID 3 headline values, median 31.192999 s | `Q01-cubrid-headline.json` | median of 3 measured statements | direct A/B | `1d3dc294f7f1f12b…` |
| CUBRID sink, 4 stmts x 4 rows fully consumed | `Q01-cubrid-headline.out` | per-statement `(N sec)` lines | direct A/B | `688ccadc9c738478…` |
| PostgreSQL 3 headline values, median 11.112755 s | `Q01-postgresql-headline.json` | median of 3 measured statements | direct A/B | `e3a0f4bf4eb2ee3f…` |
| PostgreSQL sink, 4 stmts x 4 rows fully consumed | `Q01-postgresql-headline.out` | `\timing` per statement | direct A/B | `87ecd4a7c504b53b…` |
| `parallel workers: 6`, `ioread 682950`/`fetch 682982`, `GROUPBY page:0` | `q1-trace-cubrid.out` | `SET TRACE ON` + `SHOW TRACE` | direct A/B | `69a2b670b277e396…` |
| `Workers Launched: 5`, `hit=694494 read=430634`, node self-times | `q1-plan-act-pg.out` | `EXPLAIN ANALYZE BUFFERS` | direct A/B | `9570574faa27e4ed…` |
| CUBRID `total_query_cpu` 186.67 core-s, TWU 5.9774, serial tail 0.117 s | `Q01-cubrid-telemetry.json` | per-TID ticks / `SC_CLK_TCK`, actual dt weighting | profile attribution | `55abf2269222aa7a…` |
| PostgreSQL `total_query_cpu` 68.11 core-s, TWU 6.1209, serial tail 0.122 s | `Q01-postgresql-telemetry.json` | per-TID ticks / `SC_CLK_TCK`, actual dt weighting | profile attribution | `dc0ca4649b2d6542…` |
| CUBRID IPC 2.527, 6.038 CPUs utilized | `perf-stat-cubrid.txt` | `instructions/cycles`, `task-clock/elapsed` | profile attribution | `4ea5d6d7bc711080…` |
| PostgreSQL IPC 2.354, 6.232 CPUs utilized | `perf-stat-pg.txt` | `instructions/cycles`, `task-clock/elapsed` | profile attribution | `659e23e0b6ae13ef…` |
| CUBRID symbol shares, 0 unresolved | `profile-cubrid-flat.txt` | `perf report` self% | profile attribution | `7e3a6949bf6bdbd2…` |
| PostgreSQL symbol shares, 0 unresolved | `profile-pg-flat.txt` | `perf report` self% | profile attribution | `17aadcee52f11b48…` |
| aggregate call path for `float_numeric_db_value_add` | `profile-cubrid-callgraph.txt` | dwarf call-graph | profile attribution | see manifest |

## 11. Notion sync

**Status: `NOTION_UNAVAILABLE` → idempotent Git backfill recorded (write path 3).**

Section 21 write path was attempted in order and not mixed:

1. *official Notion connector* — **unavailable**: no Notion connector is exposed to
   this session's tool set.
2. *logged-in Aside browser* — **not reachable**: the section 21 "existing master
   URL" is not recorded anywhere in the allowlisted active tree, and the only other
   place it could be recovered from is pre-2026-07-30 campaign material, which
   section 2 forbids reading or citing. Guessing a workspace URL is not a
   verification.
3. *idempotent Git backfill* — **done**: a record is appended to
   `reports/notion_backfill_pending.jsonl` keyed on
   `campaign_id + QNN + session_id + report_commit + content_fingerprint`, carrying
   the full set of section 21 required query fields (QNN/status, campaign ID and
   SSOT commit, exact GJC session ID, correctness/censoring, CUBRID seconds,
   PostgreSQL seconds and ratio, causal multiplier summary, report commit and raw
   manifest link, improvement relations, content fingerprint, last verified
   timestamp) using the same field names as this report.

Pending is **not** cleared, because clearing requires a server-side refetch which
was never performed. Per section 21 and section 23 this does not block measurement,
deep analysis, final IMP ID allocation or query transition; both IMP IDs were
allocated in the Git ledger, committed and pushed first, so no temporary,
local-only or Notion-only ID exists.

## 12. Completion checklist

- [x] preflight and correctness status recorded (section 1, section 2)
- [x] three valid headline values for each completing engine (both engines completed)
- [x] timeout confirmations — not applicable, neither engine censored
- [x] plan, execution, profile and source contrast sections complete
- [x] causal multiplier card has evidence for every factor; residual 0.433% inside
      the measured error budget; no factor left implicitly unmeasured
- [x] Git improvement ledger deduplicated and committed (`IMP-001`, `IMP-002`)
- [x] every claim indexed to raw evidence and checksum (36 artifacts)
- [x] report, manifest and registry committed, pushed and reachable from
      `origin/main`
- [x] `QUERY_COMPLETE` emitted
- [x] current session removed and absence verified

Known carried-forward gaps, explicitly recorded rather than silently omitted:

- CUBRID actual histogram bucket count remains `UNMEASURED` (opaque `VARBIT`
  catalog); target 300 is configured and verified.
- CUBRID accumulating perfmon counters (`Num_data_page_fetches`,
  `Num_data_page_ioreads`) read 0 in this build even after a verified 59.1M-row
  scan, so physical-read evidence comes from `/proc/<pid>/io`, `/proc/diskstats`
  and the query trace instead; CUBRID buffer *gauges* (`Num_data_page_lru*`) do
  work and are used for the WARM proof.
- `reports/bootstrap/build-manifest.json` and the bootstrap report pin
  `ssot_commit 1d6a5ea6…` while this query pins `ad1433b4…`; the bootstrap-era
  blob `fe21c548…` differs from the current `3f742927…` only by the section 9
  buffer/cache contract added for this query, so no bootstrap finding is invalidated.
- The CUBRID databases live under a repository-internal `.git_ignored_dir`; this is
  the reused SF10 dataset and moving it would be a destructive action outside the
  cleanup manifest, so it was left untouched and only recorded.
