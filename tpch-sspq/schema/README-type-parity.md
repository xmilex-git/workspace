# Type parity — CUBRID canonical DDL → PostgreSQL

The Canonical Query Set's schema is the CUBRID DDL
`~/dev/cubrid/.vscode/TPC-H/scale10/create_tpch_table.sql` (ADR 0004). This file
records, for all eight tables, what each CUBRID column type was mapped to on the
PostgreSQL side and **why that mapping preserves meaning and precision** — plus
the places where the two engines genuinely differ, which are recorded rather than
papered over.

Scope: `schema/lineitem-{cubrid,pg}.sql` (Q1 pilot) and
`schema/remaining7-{cubrid,pg}.sql` + `schema/remaining7-pk-{cubrid,pg}.sql`
(this stage). The type set is identical across the two: the seven remaining
tables introduce no type that lineitem had not already used, only wider
`CHAR`/`VARCHAR` lengths.

## 1. The mapping

| CUBRID | PostgreSQL | Where used | Meaning preserved because |
|---|---|---|---|
| `INTEGER` | `integer` | every key, `p_size`, `o_shippriority`, `ps_availqty` | Both are 4-byte signed with range −2,147,483,648 … 2,147,483,647. TPC-H's widest key at SF10 is `l_orderkey` ≤ 60,000,000, well inside it. |
| `DECIMAL(15,2)` | `numeric(15,2)` | all money/quantity columns | `decimal` is a documented alias of `numeric` in PostgreSQL. Declared precision 15, scale 2 and **exact** decimal arithmetic are both kept. |
| `CHAR(n)` | `character(n)` | `r_name`, `n_name`, `p_mfgr`, `p_brand`, `p_container`, `s_name`, `s_phone`, `c_phone`, `c_mktsegment`, `o_orderstatus`, `o_orderpriority`, `o_clerk`, `l_returnflag`, `l_linestatus`, `l_shipinstruct`, `l_shipmode` | Both are fixed length, blank-padded on store, and **trailing-space-insensitive in comparison** (SQL `PAD SPACE`). Verified, section 3. |
| `VARCHAR(n)` | `varchar(n)` | all `*_comment`, `p_name`, `p_type`, `s_address`, `c_name`, `c_address` | Both cap at n characters and neither pads. |
| `DATE` | `date` | `o_orderdate`, `l_shipdate`, `l_commitdate`, `l_receiptdate` | Both are day-granularity calendar dates with no time and no zone component. |
| `NOT NULL` | `NOT NULL` | as declared | Unchanged on every column. The only two nullable canonical columns, `r_comment` and `n_comment`, stay nullable on both sides. |

Rejected alternatives for `DECIMAL(15,2)`, for the record: `double precision`
(binary floating point — changes the result of Q1/Q5/Q6/Q9's `SUM` and of Q17/Q22's
`AVG`) and scale-shifted `bigint` (changes division semantics in Q14/Q17). Both
are out because they alter arithmetic, not just storage.

Column names are lower-cased on the PostgreSQL side. PostgreSQL folds unquoted
identifiers to lower case, CUBRID folds them to upper case, and both are
case-insensitive for unquoted names, so this is presentation only.

## 2. Declared-semantics parity is not storage parity

Two differences are inherent to the engines, not consequences of the mapping.
They are recorded here so no later report mistakes them for a setup error.

* **`DECIMAL` storage.** CUBRID stores `DECIMAL(15,2)` as a fixed-width packed
  value. PostgreSQL `numeric` is variable-length arbitrary precision. Declared
  precision and scale match; per-value storage width and arithmetic cost do not.
* **Statistics information content — narrowed, but not closed.** This bullet was
  rewritten twice on 2026-07-28. First it framed the gap as a mere
  sampling-vs-fullscan fidelity difference, which understated it
  (`docs/report-cubrid-statistics-content-20260728.md`). Then CUBRID's optimizer
  histogram was deliberately enabled (ADR 0008,
  `docs/report-cubrid-histogram-enabled-20260728.md`). Current measured state:
  * **CUBRID now has** per-column histograms (300 equi-depth buckets), an MCV list
    with frequencies, and `null_frequency` — for **61 of 61** columns across the 8
    tables, all built `WITH FULLSCAN`. This is a **departure from the CUBRID
    default**: `update_statistics_update_histogram` ships as `no`.
  * **CUBRID still lacks** physical `correlation` and `avg_width` (neither concept
    exists in the source), and an exact domain min/max — the lowest bucket is an
    open `(-inf, hi]`, so the minimum is unrecoverable, and the maximum is not
    always exact (`l_shipdate` tops out at 1998-11-29 against an actual
    1998-12-01). PostgreSQL's `histogram_bounds` endpoints *are* the observed
    min/max.
  * MCV values live inside the opaque `_db_histogram.histogram_values` BIT VARYING
    blob, readable only via `SHOW HISTOGRAM <t>`; PostgreSQL exposes them as
    ordinary `pg_stats` array columns.
  * Bucket counts are **not aligned**: CUBRID `default_histogram_bucket_count=300`
    vs PostgreSQL `default_statistics_target=100`, and the two parameters do not
    mean the same thing (PG's target also sets the 300×target sample size).
  * Per-column NDV remains sample-extrapolated on both engines. CUBRID's *table*
    cardinality is exact (59,986,052); PostgreSQL's `reltuples` is an estimate
    (59,988,188).
  Both sides were refreshed at the same point in the same state. This is now
  **freshness parity plus the same information class for range/equality
  estimation**, but not full information parity. G4 must state the four remaining
  gaps and the bucket-count asymmetry as preconditions of its plan/row-estimate
  comparison.

## 3. Empirically verified, not asserted

Run against the loaded 8-table datasets on both engines. Raw output:
`.git_ignored_dir/g1-assets/raw/probe-{cubrid,pg}.txt`.

| Probe | CUBRID | PostgreSQL | Verdict |
|---|---|---|---|
| `r_name = 'ASIA'` on `CHAR(25)` — 21 pad blanks vs a 4-char literal | 1 | 1 | **same** — both pad-insensitive |
| `c_mktsegment = 'BUILDING'` on `CHAR(10)` | 300,276 | 300,276 | **same** |
| `l_shipmode IN ('MAIL','SHIP') AND l_shipdate < date '1994-01-01'` on `CHAR(10)` (Q12 shape) | 4,774,713 | 4,774,713 | **same** |
| `SUBSTRING(c_phone,1,2) IN ('13','31','23')` on `CHAR(15)` (Q22 shape) | 179,755 | 179,755 | **same** |
| `SUM(ps_supplycost)` over `DECIMAL(15,2)` | 199756.76 | 199756.76 | **same** |
| `CHAR_LENGTH(r_name)` on `CHAR(25)` holding `'ASIA'` | 25 | 4 | **differs** |
| `100.00 * 5 / 3` | 166.6666666666666666666666666666666666667 | 166.6666666666666667 | **differs in scale** |
| `AVG(ps_supplycost)` | 504.4362626262626 | 504.4362626262626263 | **differs in scale** |

### The two divergences, and why they do not change any of q1–q22

**`CHAR_LENGTH` on a `CHAR(n)`.** CUBRID counts the pad and returns the declared
length 25; PostgreSQL treats `bpchar` as its trailing-blank-stripped text value
and returns 4. This is a real semantic difference — but no query in the Canonical
Query Set applies `CHAR_LENGTH`, `LENGTH`, `OCTET_LENGTH` or `TRIM` to any column,
so none of q1–q22 can observe it. Recorded because any future query added to the
set must not use length functions on a `CHAR` column without re-deciding this.

`SUBSTRING` is the one string function the set does apply to a `CHAR` column
(`c_phone`, Q22). It is unaffected: both engines return `'25'` for
`SUBSTRING(c_phone,1,2)` on `c_custkey = 1`, and the Q22-shaped `IN` predicate
selects the same 179,755 rows on both. Positions 1–2 sit inside the significant
prefix, so the pad-stripping difference cannot reach them.

**Decimal division scale.** Exact-value operations agree bit for bit (`SUM` above).
Division and `AVG` do not: CUBRID carries more fractional digits than
PostgreSQL's `numeric` division, which PostgreSQL caps relative to the operand
scale. The values agree to every digit PostgreSQL produces; CUBRID simply prints
further. This reaches three queries' **output formatting** — Q14
(`100.00 * sum(...) / sum(...)`), Q17 (`sum(...) / 7.0`) and Q22's `AVG` in the
subquery threshold — and it is an engine difference, so it is **not** corrected in
the dialect. Consequence for G1: result comparison for Q14/Q17/Q22 must compare at
a fixed scale rather than as raw text. Q22's `AVG` sits inside a `>` threshold
rather than in the output, so a scale difference there could in principle move a
boundary row; whether it actually does is a G1 result-equality observation, not
something to pre-judge here.

## 4. Index parity

Fixed by the Q1 pilot and applied identically to all eight tables: **primary keys
only.** Every TPC-H foreign key in `create_tpch_index.sql` is omitted on *both*
engines, because CUBRID materialises a btree for a foreign key and PostgreSQL does
not — keeping them would give CUBRID eight indexes PostgreSQL has no counterpart
for. Omitting them symmetrically removes an asymmetry instead of creating one. No
secondary index exists on either side. Verified in
`docs/report-g1-assets-20260728.md`.
