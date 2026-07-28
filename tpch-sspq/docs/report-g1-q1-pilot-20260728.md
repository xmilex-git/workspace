# G1 Q1 pilot — first measured Q1 wall times, both engines

2026-07-28. Scope: **Q1 only**. Purpose is to get the first real wall-time
numbers on the two pinned builds and to prove the G1 measurement path works
end to end. This is not G1 itself — G1 needs all 22 queries and AB/BA
interleaving (ADR 0005).

Raw evidence: `~/dev/workspace/.git_ignored_dir/tpch-sspq/g1-q1-pilot/`
(`raw/`, `plans/`, `logs/`). Paths are listed per item below.

## 1. Result summary

| | CUBRID 11.5.0 `f30f1c260` | PostgreSQL 20devel `5713b437a` |
|---|---|---|
| Warmup (not aggregated) | 34.930 s | 8.947 s |
| Stream 1 | 34.654 s | 8.995 s |
| Stream 2 | 34.835 s | 8.965 s |
| Stream 3 | 34.609 s | 8.962 s |
| **mean of 3** | **34.699 s** | **8.974 s** |
| min / max | 34.609 / 34.835 s | 8.962 / 8.995 s |
| sd (n=3) | 0.120 s | 0.018 s |
| cv | 0.34 % | 0.20 % |
| engine-reported statement time (stream 1) | 34.631 s (csql) | 8.987 s (psql `\timing`) |
| result rows | 4 | 4 |
| target DOP | `parallelism=6` | `max_parallel_workers_per_gather=6` |
| **parallelism actually applied** | **yes — `parallel workers: 6`** | **yes — `Workers Launched: 6`** |
| timeout (300 s) hit | no | no |

**CUBRID / PostgreSQL = 3.867x** on the mean of 3 warm streams.

Wall time is measured outside the client process (`date +%s.%N` around the whole
`csql` / `psql` invocation), so it includes client start-up and result
formatting. The engine-reported statement times above agree with it to within
~30 ms on both sides, so the wrapper overhead is not material at this scale.

### Warm verification (ADR 0006)

Physical device reads over each stream, from `/proc/diskstats` sda
sectors-read delta:

| stream | CUBRID | PostgreSQL |
|---|---|---|
| warmup | 0.1 MiB | 0.0 MiB |
| 1 | 0.0 MiB | 11.8 MiB |
| 2 | 0.0 MiB | 0.9 MiB |
| 3 | 0.2 MiB | 0.0 MiB |

All six aggregated streams are warm. The largest single value, 11.8 MiB on PG
stream 1, is 0.13 % of the 8,790 MiB heap it scans. Both engines served the scan
from OS page cache; neither engine's own buffer holds the table (see §5).

## 2. Result-value cross-check

All 4 rows, all 8 measures, both engines, same group keys in the same order:

* `sum_qty`, `sum_base_price`, `sum_disc_price`, `sum_charge`, `count_order`
  — **exact digit-for-digit match** on all 4 groups.
* `avg_qty`, `avg_price`, `avg_disc` — agree to a relative difference of
  **≤ 2.1e-16** on all 12 values.

The `avg` difference is presentation, not arithmetic: CUBRID returns `avg` as a
16-significant-digit double in scientific notation
(`2.550097510300710e+01`) while PostgreSQL returns `numeric`
(`25.5009751030070973`). Agreement is at CUBRID's full printed precision.

`count_order` totals 59,142,609 = the qualifying row count, and
59,986,052 − 59,142,609 = 843,443 rows are excluded by the `l_shipdate`
predicate. PG's plan independently confirms this: `Rows Removed by Filter:
120492` × 7 processes ≈ 843,443.

Raw: `raw/cubrid/run{1,2,3}.out`, `raw/pg/run{1,2,3}.out`.

## 3. Parallelism evidence

**CUBRID** — `plans/cubrid-q1-plan-trace.txt`, `;plan detail` + `;trace on text`:

```
Query Plan:
  SORT (group by)
    TABLE SCAN (dba.lineitem)

Trace Statistics:
  SELECT (time: 35888, fetch: 683119, fetch_time: 6927, ioread: 682944)
    SCAN (table: dba.lineitem), (heap time: 35887, fetch: 683027, ioread: 682937,
          readrows: 59986052, rows: 59986052)
         (parallel workers: 6, heap time: 35435..35886,
          readrows: 9938887..10011920, rows: 9938887..10011920,
          gather: mergeable list)
    GROUPBY (time: 0, hash: partial, sort: true, page: 0, ioread: 0, rows: 4)
```

6 workers, each reading 9,938,887–10,011,920 rows (sum = 59,986,052), gathered
as a mergeable list. Optimizer cost 868,407 / card 5,998,605 for the plan; the
`l_shipdate` sarg is estimated at selectivity 0.1 against 59,986,052 actual
qualifying-side rows, i.e. the estimate is ~10x low — noted for G4, not acted on.

**PostgreSQL** — `plans/pg-q1-explain-analyze.txt`,
`EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)`:

```
Finalize GroupAggregate (actual time=9143.726..9146.605 rows=4.00 loops=1)
  -> Gather Merge   Workers Planned: 6   Workers Launched: 6
       -> Sort (Sort Method: quicksort  Memory: 26kB)
            -> Partial HashAggregate (Batches: 1  Memory Usage: 32kB)
                 -> Parallel Seq Scan on public.lineitem
                    (actual time=0.096..962.932 rows=8448944.14 loops=7)
                    Filter: (l_shipdate <= '1998-09-02 00:00:00'::timestamp)
                    Rows Removed by Filter: 120492
Execution Time: 9146.733 ms
```

`Workers Planned: 6` and `Workers Launched: 6` — the request was fully granted,
so no `Workers Launched < target DOP` case arises here. 7 processes participate
(leader + 6). Per-worker buffer counts are within 0.4 % of each other
(159,304–159,962 reads), i.e. the scan split evenly.

Both engines therefore reach the target DOP of 6. Under the label rules still
pending in the README, Q1 classifies as **parallel on both engines** — it is not
a PG-only Parallel case.

## 4. Configuration evidence

| Parameter | CUBRID | PostgreSQL |
|---|---|---|
| target DOP | `parallelism=6` — `paramdump`: `[C*] parallelism=6 (4)`, `[S*] parallelism=6 (4)` | `max_parallel_workers_per_gather=6` |
| worker pool | `max_parallel_workers=100` (default, not binding) | `max_parallel_workers=8`, `max_worker_processes=16` |
| buffer | `data_buffer_size=8.0G` (`data_buffer_pages=524288`) | `shared_buffers=8GB` (`1048576` × 8 kB) |
| page / block | 16 K | 8 K |
| sort / work mem | `sort_buffer_size=2.0M` | `work_mem=4MB` |
| statement timeout | none — manual cancel past 300 s (not needed) | `statement_timeout=300s` |
| JIT | n/a | `off` (build is `--without-llvm`; set explicitly) |

Evidence files: `raw/cubrid-paramdump-tpch_sf10_q1.txt`,
`raw/pg-settings-nondefault.txt`, `raw/pg-settings-parallel-relevant.txt`.

**On the 8 G buffer figure.** The instruction was to set PG `shared_buffers` to
`tpch_sf10_v2`'s `data_buffer_size`. `cubrid paramdump tpch_sf10_v2` under the
build that operated it reports `data_buffer_size=8.0G` (server default is
512.0 M) — captured in `raw/cubrid-paramdump-tpch_sf10_v2-q19build.txt`. So the
mirrored value is **8 G, not the 512 M in the stock conf file**, and both engines
were set to 8 G. This is still provisional; the parameter-correspondence rule
remains a pending decision. Note that 8 G does not hold either engine's copy of
the table (§5), so for Q1 both engines stream the table past their buffer and
the OS page cache is what makes the run warm.

`sort_buffer_size` ↔ `work_mem` were left at their defaults and are immaterial
for Q1: CUBRID reports `GROUPBY (… page: 0, ioread: 0)` and PG sorts 4 rows in
26 kB. They will matter for other queries.

Core pinning: every server and client process was started under
`taskset -c 0-15` (node0). No stray `cub_master` existed at measurement time;
the one left by the failed boot in §6 was stopped before any load or run.

## 5. Physical shape of the same 60 M rows

| | CUBRID | PostgreSQL |
|---|---|---|
| rows loaded | 59,986,052 | 59,986,052 |
| table pages touched by a full Q1 scan | 682,937 × 16 K = **10,671 MiB** | 1,125,128 × 8 K = **8,790 MiB** |
| index size | — (included below) | 1,285 MiB |
| total for the table | 12,254 MiB permanent data (25 volumes) | 10,078 MiB |

CUBRID reads ~21 % more bytes to answer the same query. Recorded as an observed
counter fact only; no bottleneck is attributed to it here — cause attribution is
reserved for G2–G4 per the README rule.

Evidence: `raw/cubrid-spacedb.txt`, `logs/pg-load/06-size.log`, and the
`ioread` / `Buffers: shared read` figures in the two plan files.

## 6. Blocker found and resolved: `tpch_sf10_v2` is unreadable by the pin

The pinned measurement build **cannot open `~/databases/tpch_sf10_v2`**:

```
catalog_class.c:4898 ERROR CODE = -64 ... Unknown class "db_root".
boot_sr.c:2751 ERROR CODE = -113 ... Unable to restart/initialize the database server.
```

Cause is an on-disk CHAR/VARCHAR format change, established as follows:

| Fact | Evidence |
|---|---|
| The DB was written by build `4cfc837` | `~/release/CUBRID-q19-4cfc837/log/cubrid_utility.log:17` — `cubrid createdb -r -F /home/cubrid/databases/tpch_sf10_v2 -L …/log --db-volume-size=256M --log-volume-size=512M tpch_sf10_v2 en_US.utf8`, 26-07-23 18:37:31 |
| `83b29b02c` CBRD-26663 *CHAR/VARCHAR unified variable-length storage* | ancestor of **both** `4cfc837` and `f30f1c260` |
| `a9fca9002` CBRD-26956 *"Full revert of CBRD-26663; VARCHAR restored to the byte_size header"* | in `f30f1c260`, **not** in `4cfc837` |
| The failure is exactly a VARCHAR catalog decode | `catcls_get_server_compat_info()` → `catcls_find_class_oid_by_class_name(…, "db_root", …)`; the key is the VARCHAR `class_name` in `_db_class`. The revert touches `object_representation.h`, `object_representation_sr.c`, `object_primitive.c` |
| The volumes are healthy | control test: the same volumes boot under the creating build `4cfc837` → `++ cubrid server start: success`, `Server tpch_sf10_v2 (rel 11.5.0, pid 4148480)`. Stopped again immediately |

So the dataset is not corrupt and the pin is not misconfigured; the two are
format-incompatible in both directions. Keeping the pin (ADR 0002) means the
CUBRID data has to be reloaded by the pinned build. There is no migration path
for a storage-format revert.

**Consequence for this pilot:** a fresh CUBRID database `tpch_sf10_q1` was
created by the pinned build with the *same* geometry and locale as
`tpch_sf10_v2` (`--db-volume-size=256M --log-volume-size=512M`, `en_US.utf8`,
16 K pages) and loaded with lineitem only. `~/databases` and `~/CUBRID` were not
touched: the new database lives under
`.git_ignored_dir/tpch-sspq/cubrid-databases/` with its own `databases.txt`, so
the shared `~/databases/databases.txt` is unmodified.

**Consequence for G1:** the full 8-table reload under the pinned build is now a
G1 prerequisite, alongside the PG load of the other 7 tables. `tpch_sf10_v2`
should be treated as belonging to the retired `4cfc837` build, not as a G1
asset.

## 7. Load and conversion record

### PostgreSQL lineitem

Schema `schema/lineitem-pg.sql`, derived from the LINEITEM block of the
canonical `create_tpch_table.sql` + the LINEITEM PK from
`create_tpch_index.sql`. Type mapping and the rationale for each choice are in
the file's header comment. In short: `INTEGER`→`integer`,
`DECIMAL(15,2)`→`numeric(15,2)` (documented alias, exact precision/scale kept;
`double precision` and scaled `bigint` were rejected because they change Q1's
`SUM`/`AVG` semantics), `CHAR(n)`→`character(n)`, `DATE`→`date`,
`VARCHAR(44)`→`varchar(44)`, `NOT NULL` kept on all 16 columns.

The source is a CUBRID `loaddb` file, not a COPY file, so it was converted with
`.git_ignored_dir/scratch/loadfile-to-csv.pl`: 8 bare numerics then 8
single-quoted strings per line, split on the exact 3-byte sequence `' '`,
re-emitted as CSV with values double-quoted. The script aborts on any line that
does not yield exactly 8 + 8 fields, so the run is a structural check of the
whole file — it reported `converted rows=59986052` with no violation. Leading
and trailing spaces inside `l_comment` are preserved; commas and colons inside
`l_comment` are handled by the CSV quoting.

`COPY 59986052`. `statement_timeout` was set to 0 for the load only, so the
300 s measurement rule could not truncate it.

### CUBRID lineitem

`schema/lineitem-cubrid.sql` is a verbatim extract of the canonical LINEITEM
block. `cubrid loaddb -S -u dba -l -v -c 100000 --no-statistics`:
`Total 59986052 object(s) inserted, 0 object(s) failed`, 17:54 wall.

### Row-count reconciliation

| Source | lineitem rows |
|---|---|
| `wc -l lineitem.load` | 59,986,052 |
| CUBRID `tpch_sf10_v2` (reference, read under build `4cfc837`) | 59,986,052 |
| CUBRID `tpch_sf10_q1` (new, pinned build) | 59,986,052 |
| PostgreSQL `tpch_sspq` | 59,986,052 |

All four agree.

### Indexes and statistics — completed before any warmup or measured stream

| | CUBRID | PostgreSQL |
|---|---|---|
| index created | `pk_lineitem_l_orderkey_l_linenumber`, BTREE, unique, `(l_orderkey, l_linenumber)`, cardinality 59,986,052 | `lineitem_pkey`, btree, unique, `(l_orderkey, l_linenumber)`, 1,285 MB |
| index count on lineitem | 1 | 1 |
| built at | 14:44:08 → 14:45:44 | 14:44:19 → 14:44:39 (19.7 s) |
| statistics | `UPDATE STATISTICS ON ALL CLASSES WITH FULLSCAN`, 14:45:44 → 14:47:26, exit 0 | `ANALYZE VERBOSE lineitem`, `last_analyze = 14:44:39.903915`, 503 ms |
| first warmup stream | 14:51 | 14:56 |

The index sets are **identical**: exactly one btree, the primary key, on the
same two columns in the same order, and nothing else on either engine.

`create_tpch_index.sql` also declares two LINEITEM foreign keys
(`L_ORDERKEY`→`ORDERS`, `(L_PARTKEY, L_SUPPKEY)`→`PARTSUPP`). Both are omitted,
on both engines, because ORDERS and PARTSUPP are not loaded in a Q1-only pilot.
This omission is symmetric and removes an asymmetry rather than creating one:
CUBRID materialises an index for a foreign key while PostgreSQL does not, so
creating the FKs would have given CUBRID two indexes PostgreSQL lacks. Neither
FK is usable by Q1's plan.

Evidence: `raw/cubrid-lineitem-indexes.txt` (`SHOW INDEX FROM lineitem` +
`db_index`/`db_index_key`), `raw/pg-lineitem-indexes.txt` (`pg_indexes`,
`\di+`, `pg_constraint`), `raw/pg-lineitem-stats.txt`,
`logs/cubrid-load/0{3,4}-*.log`, `logs/pg-load/0{4,5}-*.log`.

## 8. Query dialect

One line changed, `queries/q1-cubrid.sql` → `queries/q1-pg.sql`:

```diff
-	l_shipdate <= DATE_SUB(DATE '1998-12-01', INTERVAL 90 DAY)
+	l_shipdate <= date '1998-12-01' - interval '90' day
```

`DATE_SUB` is a MySQL-compatible CUBRID builtin with no PostgreSQL equivalent;
the replacement is the interval form used by the TPC-H specification text for
Q1. Same literal, same operation, same resulting instant `1998-09-02`. Nothing
else is touched — same select list, same aggregate expressions, same `group
by`/`order by`, no hint, no `limit`, no rewrite. Rationale and the recorded type
nuance (CUBRID compares `DATE ≤ DATE`; PG's `date - interval` is `timestamp`, so
PG compares `date ≤ timestamp`) are in `queries/README-q1-dialect.md`.

Verified empirically rather than argued:
`date '1998-12-01' - interval '90' day` folds to `1998-09-02 00:00:00`, and both
the interval form and the in-domain `date '1998-12-01' - 90` form select
**59,142,609** rows out of 59,986,052 — identical.
Raw: `raw/pg-q1-date-equivalence.txt`.

## 9. Caveats on these numbers

1. **Q1 only, one query, n=3.** The sd values (0.120 s / 0.018 s) are Q1's
   within-engine repeat noise on one machine state. They are *not* the paired
   AB/BA sd that G2's cut margin needs — that requires interleaved streams,
   which this pilot does not do.
2. **No AB/BA interleaving.** CUBRID's three streams ran back to back, then
   PG's. Any slow drift in machine state is not cancelled.
3. **Buffer parity is provisional.** 8 G on both sides was mirrored from
   `tpch_sf10_v2`'s operating value, not derived from a settled rule, and it is
   smaller than either engine's copy of the table.
4. **Background load was present.** The agent runtime itself (`bun`, ~70 % of
   one core, not pinned) was running during the streams. Load average at the
   start of the CUBRID set was 9.74. Both engines were measured under the same
   kind of background, but this is not a quiet machine.
5. **PostgreSQL is a development snapshot** (20devel). Per ADR 0002 these
   numbers must not be quoted as release PostgreSQL performance.
6. **Dataset provenance is still unverified** — no TPC-H kit, so dbgen seed and
   kit version remain unknown (ADR 0004). Both engines were loaded from the same
   `lineitem.load`, so they are consistent with each other regardless.
7. **Deviation from the stated coordinate**: the CUBRID DB is `tpch_sf10_q1`
   (lineitem only), not `tpch_sf10_v2`. Forced — see §6.

## 10. What this pilot settles for the pending decisions

* **Parallel-classification label rule** — Q1 needs no special label:
  `Workers Launched` equals the target DOP on PG, and CUBRID reports
  `parallel workers: 6`. The `Workers Launched < target DOP` case did not occur,
  so that sub-rule is still undecided.
* **Warm verification threshold** — the provisional 1 % / 100 MiB gate is
  comfortably met: the worst aggregated stream read 11.8 MiB, 0.13 % of its
  scan. Six data points is too few to fix the threshold; the shape supports the
  provisional value.
* **`taskset` pin size** — `taskset -c 0-15` (node0, 16 cores) held 7 PG
  processes and 7 CUBRID threads without a launch shortfall on either engine.
* **Stray `cub_master`** — none were present. The count of 4 in
  `ENVIRONMENT.md` is stale.

Not settled here: the parameter-correspondence rule, the G2 cut margin, and the
paired AB/BA sd.
