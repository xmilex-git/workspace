# G1 asset completion — 8-table load on both engines + q2–q22 dialect

Date 2026-07-28. Follows `report-g1-q1-pilot-20260728.md`. Closes the two G1
prerequisites that the pilot left open: the remaining seven tables on both
engines, and the PostgreSQL Engine Dialect for q2–q22.

**This stage prepared assets. Nothing was measured.** No timing was taken, no
stream was run, no plan was interpreted. Bottleneck candidates remain
un-nominated (ADR 0005).

## 1. What was done

| # | Step | Result |
|---|---|---|
| 1 | 7 tables loaded on both engines | all row counts exact, 0 failures |
| 2 | Index parity, PK only | 8 tables × exactly 1 unique btree on both engines, 0 FK |
| 3 | Type parity documented + probed | 1 real divergence found (`CHAR_LENGTH`), unreachable by q1–q22 |
| 4 | Row counts reconciled | 3-way agreement: source `wc -l` = CUBRID = PostgreSQL = SF10 standard |
| 5 | Statistics refreshed on both | CUBRID 17:30:54→17:31:51, PostgreSQL 17:31:58→17:32:00 |
| 6 | q2–q22 dialect derived | 11 lines changed across 11 files, 2 substitution kinds |
| 7 | `EXPLAIN` smoke on all 22 PG statements | all planned, `revenue0` cleaned up |

lineitem was **not** touched on either engine: it was loaded under this same
pinned build during the pilot and is excluded from every DDL file and load script
in this stage, enforced by a pre-flight guard that greps the comment-stripped DDL
for the name and aborts.

## 2. Row counts — 8 tables, both engines, measured with `count(*)`

Raw: `.git_ignored_dir/g1-assets/raw/{cubrid,pg}-counts.txt`

| Table | source `wc -l` | CUBRID | PostgreSQL | SF10 standard | Match |
|---|---|---|---|---|---|
| region | 5 | 5 | 5 | 5 (fixed) | yes |
| nation | 25 | 25 | 25 | 25 (fixed) | yes |
| supplier | 100,000 | 100,000 | 100,000 | 10,000 × SF = 100,000 | yes |
| customer | 1,500,000 | 1,500,000 | 1,500,000 | 150,000 × SF = 1,500,000 | yes |
| part | 2,000,000 | 2,000,000 | 2,000,000 | 200,000 × SF = 2,000,000 | yes |
| partsupp | 8,000,000 | 8,000,000 | 8,000,000 | 800,000 × SF = 8,000,000 | yes |
| orders | 15,000,000 | 15,000,000 | 15,000,000 | 1,500,000 × SF = 15,000,000 | yes |
| lineitem | 59,986,052 | 59,986,052 | 59,986,052 | ≈6,000,000 × SF, data-dependent | yes (reference value, unchanged) |
| **total** | **86,586,077** | **86,586,077** | **86,586,077** | | |

The seven fixed-cardinality tables hit the SF10 standard counts exactly. lineitem
is the one table whose count is data-dependent rather than a fixed multiple of SF;
59,986,052 is the pilot's established reference value and it is unchanged, as
required.

Structural verification came free with the load: the loaddb→CSV converter asserts
an exact field count on every line and aborts otherwise, so its `converted rows=N`
equals `wc -l` for each file, and `COPY N` equals that in turn. On the CUBRID side
`loaddb` reported `Total N object(s) inserted, 0 object(s) failed` for all seven.

## 3. Index parity — PK only, one btree per table, no FK anywhere

Raw: `.git_ignored_dir/g1-assets/raw/{cubrid-indexes,cubrid-index-summary,pg-indexes,pg-constraints}.txt`

| Table | CUBRID index | PostgreSQL index | Key columns | Unique | Same |
|---|---|---|---|---|---|
| region | `pk_region_r_regionkey` | `region_pkey` | `(r_regionkey)` | both | yes |
| nation | `pk_nation_n_nationkey` | `nation_pkey` | `(n_nationkey)` | both | yes |
| supplier | `pk_supplier_s_suppkey` | `supplier_pkey` | `(s_suppkey)` | both | yes |
| customer | `pk_customer_c_custkey` | `customer_pkey` | `(c_custkey)` | both | yes |
| part | `pk_part_p_partkey` | `part_pkey` | `(p_partkey)` | both | yes |
| partsupp | `pk_partsupp_ps_partkey_ps_suppkey` | `partsupp_pkey` | `(ps_partkey, ps_suppkey)` | both | yes |
| orders | `pk_orders_o_orderkey` | `orders_pkey` | `(o_orderkey)` | both | yes |
| lineitem | `pk_lineitem_l_orderkey_l_linenumber` | `lineitem_pkey` | `(l_orderkey, l_linenumber)` | both | yes |
| **count** | **8 indexes** | **8 indexes** | | | |

Both sides are btree, both unique, same key columns in the same order, all
ascending, and **nothing else exists on either engine**. CUBRID per-table summary
from `db_index`:

```
  class_name       n_indexes   n_pk   n_fk   n_unique
  'customer'               1      1      0          1
  'lineitem'               1      1      0          1
  'nation'                 1      1      0          1
  'orders'                 1      1      0          1
  'part'                   1      1      0          1
  'partsupp'               1      1      0          1
  'region'                 1      1      0          1
  'supplier'               1      1      0          1
```

`n_fk = 0` everywhere is the operative check: CUBRID materialises a btree for a
foreign key, so any FK would show up here. PostgreSQL side, `pg_constraint` over
schema `public` holds 8 rows of `contype = 'p'` and **zero** of `contype = 'f'`
(the remaining 59 of the 67 rows are `contype = 'n'`, the not-null constraints
PostgreSQL records for `NOT NULL` columns — they are not indexes).

All 8 foreign keys in the canonical `create_tpch_index.sql` are therefore omitted
on both engines. This is the pilot's rule extended from 1 table to 8: it removes
an asymmetry rather than creating one, because keeping the FKs would have handed
CUBRID 8 indexes PostgreSQL has no counterpart for.

## 4. Type parity

Full argument, per-type table and probe results: `schema/README-type-parity.md`.
The seven new tables introduce **no type that lineitem had not already used** —
only wider `CHAR`/`VARCHAR` lengths — so the pilot's mapping carried over
unchanged: `INTEGER`→`integer`, `DECIMAL(15,2)`→`numeric(15,2)`,
`CHAR(n)`→`character(n)`, `VARCHAR(n)`→`varchar(n)`, `DATE`→`date`, `NOT NULL`
kept, `r_comment`/`n_comment` left nullable.

Probed on the loaded data rather than asserted. Everything that selects rows
agrees exactly on both engines:

| Probe | CUBRID | PostgreSQL |
|---|---|---|
| `r_name = 'ASIA'` on `CHAR(25)` (21 pad blanks vs 4-char literal) | 1 | 1 |
| `c_mktsegment = 'BUILDING'` on `CHAR(10)` | 300,276 | 300,276 |
| `l_shipmode IN ('MAIL','SHIP') AND l_shipdate < date '1994-01-01'` (Q12 shape) | 4,774,713 | 4,774,713 |
| `SUBSTRING(c_phone,1,2) IN ('13','31','23')` on `CHAR(15)` (Q22 shape) | 179,755 | 179,755 |
| `SUM(ps_supplycost)` over `DECIMAL(15,2)` | 199756.76 | 199756.76 |

Two divergences found, both recorded rather than patched:

* **`CHAR_LENGTH` on `CHAR(n)`** — CUBRID returns the declared length (25),
  PostgreSQL returns the blank-stripped length (4). Real semantic difference, but
  **no query in q1–q22 applies any length or trim function to any column**, so it
  is unreachable. It is written down because a future addition to the query set
  must not use one on a `CHAR` column without re-deciding.
* **Decimal division / `AVG` scale** — CUBRID carries more fractional digits than
  PostgreSQL's `numeric` division (`100.00*5/3`: 37 digits vs 16; `AVG`:
  504.4362626262626 vs 504.4362626262626263). Exact operations like `SUM` agree
  bit for bit. This reaches Q14, Q17 and Q22's output/threshold, so **G1's result
  comparison for those three must compare at a fixed scale, not as raw text.**

## 5. Statistics freshness parity

| | CUBRID | PostgreSQL |
|---|---|---|
| command | `UPDATE STATISTICS ON ALL CLASSES WITH FULLSCAN` | `ANALYZE VERBOSE` (whole database) |
| started | 2026-07-28 17:30:54.335 | 2026-07-28 17:31:58.319 |
| finished | 2026-07-28 17:31:51.639 | 2026-07-28 17:32:00.836 |
| wall | 57.14 s | 2.41 s |
| scope | all classes, all 8 tables | all 8 tables (+ catalogs) |
| method | full scan | sample, 30,000 rows per table |

Both were run after the loads and after the PKs, on the same data state, before
anything else. Per-table `last_analyze` (PostgreSQL) and per-table index
cardinality (CUBRID) confirm all eight were covered on both sides:

```
CUBRID  SHOW INDEX cardinality        PostgreSQL  reltuples (estimate)
region        5                       region              5
nation       25                       nation             25
supplier    100000                    supplier       100000
customer   1500000                    customer      1499783
part       2000000                    part          1999936
partsupp   8000000                    partsupp      8001290
orders    15000000                    orders       15001073
lineitem  59986052                    lineitem     59988188
```

The index cardinalities above are exact on the CUBRID side because they come from
the B+tree key count; PostgreSQL's `reltuples` are sampled estimates. **The
wall-time gap (57 s vs 2.4 s) is a difference in what the two commands do, not a
performance observation** — it is a full heap scan versus a 30,000-row sample and
must not be quoted as an engine comparison.

> **CORRECTION (2026-07-28, same day).** The heading of this section originally
> read "Statistics parity" and that was an overstatement. A follow-up
> investigation — `docs/report-cubrid-statistics-content-20260728.md` — established
> from the pinned source and from a live dump that CUBRID's per-column optimizer
> statistics here are **NDV only**: no min/max, no null fraction, no frequency
> distribution and no MCV list. The histogram subsystem exists in this build but is
> gated behind `update_statistics_update_histogram`, which defaults to `n` and was
> not set, so `db_histogram` holds **0 rows**. Per-column NDV is also
> sample-extrapolated rather than exact even under `WITH FULLSCAN`.
>
> What this section may be read as claiming is only **statistics freshness
> parity**: each engine's own standard command was run on the same data at the same
> point in the load sequence, so neither side is stale and neither was given a
> non-default statistics configuration. It does **not** claim that the two engines
> hold comparable statistics, nor that their optimizers have comparable information
> for selectivity estimation. G4 must treat that asymmetry as a stated precondition
> of its own output; see that report's §6 and §8.

## 6. Query dialect — q2 through q22

Full derivation, per-construct rationale and judgment log:
`queries/README-q2-q22-dialect.md`. Diffs: `queries/diff/qN.diff`.

11 of 22 files changed; **11 changed lines in total**; 2 kinds of substitution.

| Substitution | Files | Why it is syntax-forced |
|---|---|---|
| `DATE_ADD(DATE 'd', INTERVAL n UNIT)` → `date 'd' + interval 'n' unit` | q4 q5 q6 q10 q12 q14 q15 q20 (+ `q15_create_view`) | MySQL-compatible CUBRID builtin with no PostgreSQL equivalent; the replacement is the TPC-H spec's own wording. All 5 distinct foldings verified equal on both engines. |
| `[value]` → `"value"` | q11 (2 lines) | CUBRID accepts MS-SQL bracket identifiers, PostgreSQL uses double quotes. Same identifier. |

**Zero changes:** q2 q3 q7 q8 q9 q13 q16 q17 q18 q19 q21 q22, `q15_select`,
`q15_drop_view` — their diffs are empty files.

All 22 `qN-cubrid.sql` are byte-identical to the canonical set (`diff -q`
verified, including the three q15 split files). q15 keeps its **3-statement view
structure; no CTE conversion** — `create view revenue0 (…)` / `select` /
`drop view revenue0`.

### Judgment calls that needed a decision

Each was probed against the loaded schema before deciding, not assumed:

1. `TO_CHAR(o_orderdate,'YYYY-MM-DD')` (q3, q18) — **kept**; PostgreSQL has the
   same function and format model, both return `1996-01-02`.
2. q3/q18 alias shadowing: `o_orderdate` is simultaneously a base column and the
   output alias of the `TO_CHAR` expression, and PostgreSQL resolves `GROUP BY`
   names to input columns but `ORDER BY` names to output columns — **kept**; group
   count is 2406 three ways (as written on PG, explicit `orders.o_orderdate` on
   PG, as written on CUBRID).
3. `SUBSTRING(c_phone, 1, 2)` 3-arg comma form (q22) — **kept**; PostgreSQL
   accepts it on `bpchar`, same result, so switching to `FROM … FOR …` would be an
   unforced change.
4. `LIMIT n` (q2 q3 q10 q18 q21) — **kept**; native in PostgreSQL. None added, none
   removed.
5. `.06 - 0.01` leading-dot literals (q6) — **kept**; PostgreSQL parses them.
6. `extract(year from …)` (q7 q8 q9) — **kept**; return type differs (`numeric` vs
   integer) but it is only grouped and ordered on.
7. q15 view vs CTE — **view kept, 3 statements**; a CTE would change the
   optimisation problem on both engines, which is out of scope for a dialect.
8. q13's `not like` inside the `ON` clause of the left outer join — **kept in
   `ON`**; moving it to `WHERE` would change outer-join semantics.
9. q16's `not in (subquery)` — **kept as `NOT IN`**; `NOT EXISTS` differs on NULLs
   and is a plan-changing rewrite.
10. Correlated subqueries / `exists` / `not exists` (q4 q17 q20 q21 q22) —
    **kept**; flattening is not a dialect change.

## 7. Smoke check — parse/plan only

`EXPLAIN` (no `ANALYZE`) on all 22 PostgreSQL statements against the loaded
8-table schema: **all 22 planned successfully.** q15 ran as create view →
`EXPLAIN` select → drop view, and `revenue0` was confirmed gone afterwards
(`pg_class` count 0). Plan text archived at
`.git_ignored_dir/g1-assets/raw/pg-explain/` for G2. Nothing in those plans is
read or classified here.

The CUBRID side was not re-validated by execution: `qN-cubrid.sql` is
byte-identical to the canonical set that ADR 0004 already accepts, and CUBRID has
no execution-free `EXPLAIN`. First q2–q22 execution on CUBRID is G1's.

## 8. Load record

| | CUBRID | PostgreSQL |
|---|---|---|
| target | `tpch_sf10_q1` @ `.git_ignored_dir/tpch-sspq/cubrid-databases` (private `databases.txt`) | `tpch_sspq` @ port 5442, `PGDATA=~/pg/pgdata-tpch-sspq` |
| schema DDL | `schema/remaining7-cubrid.sql` | `schema/remaining7-pg.sql` |
| PK DDL | `schema/remaining7-pk-cubrid.sql` | `schema/remaining7-pk-pg.sql` |
| loader | `cubrid loaddb -S -u dba -l -v -c 100000 --no-statistics` per table (same flags as the pilot) | `\copy … FROM STDIN WITH (FORMAT csv)` per table, `statement_timeout=0` |
| source→loader path | canonical `.load` read directly | canonical `.load` → CSV via `loadfile-to-csv-generic.pl` |
| load window | 17:24:31 → 17:29:59 | 17:11:08 → 17:23:44 |
| PK build | 17:29:59 → 17:30:37 (37.2 s, all 7) | 11.0 s (all 7) |
| on-disk after | 20 GB (db dir) | 20 GB (PGDATA) |

Per-table load walls, CUBRID: region 2.98 s, nation 2.97 s, supplier 4.18 s,
customer 22.16 s, part 26.29 s, partsupp 1:24.75, orders 3:01.24. **These are
load times, not query measurements**, and the two engines' loaders are not
comparable (standalone `loaddb` versus client-side `COPY` through a Perl
converter). They are recorded for reproducibility only.

PostgreSQL heap/index sizes after the load
(`.git_ignored_dir/g1-assets/raw/pg-sizes.txt`): lineitem 8793 MB + 1285 MB,
orders 2042 MB + 321 MB, partsupp 1368 MB + 171 MB, part 320 MB + 43 MB,
customer 281 MB + 32 MB, supplier 18 MB + 2208 kB, nation/region 8192 bytes each.

`/home` (sda1) has 1.4 T free, so both datasets stay on the same physical disk as
required, with room to spare.

### The converter

The pilot's `loadfile-to-csv.pl` was hardcoded to lineitem's "8 bare numerics then
8 quoted strings" layout. The other seven tables **interleave** bare and quoted
fields (`nation`: `0 'ALGERIA' 0 '…'`; `orders`:
`1 369001 'O' 186600.18 '1996-01-02' …`), so position-based splitting does not
apply. `loadfile-to-csv-generic.pl` tokenises left to right instead, handles `''`
escapes, asserts an exact field count per line and that the line is fully
consumed, and rejects a non-numeric bare field — so converting a file structurally
verifies it.

Provenance check: on 200,000 lineitem rows the generic converter's output is
**byte-identical** (`cmp`) to the pilot's converter. The two loads therefore share
one conversion semantics.

## 9. State after this stage

* Both engines hold all 8 TPC-H SF10 tables with identical row counts and
  identical index sets, statistics refreshed on both.
* `queries/` holds all 22 queries in both dialects plus diffs and two derivation
  READMEs.
* Both servers are left **running** (CUBRID `tpch_sf10_q1` pid 46396 via the
  control wrapper; PostgreSQL pid 43415 on port 5442).
* **G1's prerequisites are closed.** G1 itself — AB/BA interleaved streams with
  warmup, warm verification by physical-read counters, paired sd — has not
  started.

### Carried into G1

* Q14/Q17/Q22 result comparison must normalise decimal scale (§4).
* Warm-verification threshold (1% / 100 MiB) still needs G1's measured
  distribution to be fixed; the pilot's 6 streams are too few.
* The `parallelism=6` ↔ `max_parallel_workers_per_gather=6` DOP setting and the
  8 GB ↔ 8 GB buffer pairing are unchanged from the pilot and still provisional as
  a *rule* (README pending decisions).
* PostgreSQL `max_parallel_workers = 8` with `max_worker_processes = 16` — above
  the target DOP of 6, so not a constraint, but it is the value in force.
