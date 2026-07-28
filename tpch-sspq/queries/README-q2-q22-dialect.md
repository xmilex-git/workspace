# q2–q22 — Engine Dialect derivation

Canonical Query Set: `~/dev/cubrid/.vscode/TPC-H/scale10/queries/q1…q22.sql`
(ADR 0004), generated with `qgen -d` (default substitution values). Q1's
derivation is in `README-q1-dialect.md`; this file covers the remaining 21.

`qN-cubrid.sql` is a byte-for-byte copy of the canonical file — verified with
`diff -q` for all 22 plus the three q15 split files. `qN-pg.sql` is the
PostgreSQL Engine Dialect. `diff/qN.diff` is the exact transformation.

## Summary: 11 of 22 files changed, 2 kinds of substitution, 11 lines total

| Substitution | Files | Changed lines |
|---|---|---|
| `DATE_ADD(DATE 'd', INTERVAL n UNIT)` → `date 'd' + interval 'n' unit` | q4, q5, q6, q10, q12, q14, q15, q20, q15_create_view | 1 each |
| `[value]` → `"value"` | q11 | 2 |

**Verbatim, zero changes:** q2, q3, q7, q8, q9, q13, q16, q17, q18, q19, q21, q22,
q15_select, q15_drop_view. Their `diff/*.diff` files are empty, which is the
strongest available statement that no conversion was needed.

Nothing else is touched anywhere: no join reordering, no subquery flattening, no
CTE conversion, no hint, no added or removed `LIMIT`, no predicate rewriting, no
`set` of any planner knob inside a query file. Degree of parallelism stays a
server-level setting on both engines (`parallelism=6` /
`max_parallel_workers_per_gather=6`), as in the pilot.

## 1. `DATE_ADD` → interval addition

`DATE_ADD(d, INTERVAL n UNIT)` is a MySQL-compatible CUBRID builtin PostgreSQL
does not have. The replacement is the TPC-H specification's own wording for these
predicates (`date '1993-07-01' + interval '3' month`), so it is syntax-forced
rather than a rewrite. Same operand literal, same operation, same unit.

Both sides' constant folding was measured before the substitution was applied
(raw: `.git_ignored_dir/g1-assets/raw/probe2-{cubrid,pg}.txt`):

| Query | CUBRID `DATE_ADD(...)` | PostgreSQL `date … + interval …` | Same instant |
|---|---|---|---|
| q4 | `10/01/1993` | `1993-10-01 00:00:00` | yes |
| q5, q6, q12, q20 | `01/01/1995` | `1995-01-01 00:00:00` | yes |
| q10 | `01/01/1994` | `1994-01-01 00:00:00` | yes |
| q14 | `10/01/1995` | `1995-10-01 00:00:00` | yes |
| q15 | `04/01/1996` | `1996-04-01 00:00:00` | yes |

(The two engines print dates differently — CUBRID `MM/DD/YYYY`, PostgreSQL ISO —
which is display only. The instants match.)

Same recorded type nuance as Q1: CUBRID's `DATE_ADD(DATE …)` returns `DATE`, so
CUBRID compares `DATE < DATE`. In PostgreSQL `date + interval` is typed
`timestamp`, so the comparison is `date < timestamp`; the planner folds the right
side to midnight and promotes each date column to a timestamp at midnight.
Because every column involved (`o_orderdate`, `l_shipdate`, `l_receiptdate`) is a
pure `date` with no time component, the qualifying row set is identical. Left as
the interval form rather than "fixed" to `date 'd' + n` for the same reason as
Q1: the interval form is the spec wording.

## 2. `[value]` → `"value"` (q11 only)

CUBRID accepts MS-SQL-style bracket-delimited identifiers; PostgreSQL uses
double quotes. `value` needs quoting on both engines because it collides with a
keyword. Same identifier, same spelling, same case — a delimiter swap, applied in
both places it occurs (the `select` alias and the `order by`).

## 3. Judgment calls — things that looked like they needed conversion and did not

Each of these was probed against the real loaded schema *before* deciding, rather
than assumed (raw: `.git_ignored_dir/g1-assets/raw/probe2-pg.txt`).

| # | Construct | Where | Decision | Evidence |
|---|---|---|---|---|
| 1 | `TO_CHAR(o_orderdate, 'YYYY-MM-DD')` | q3, q18 | **keep verbatim** | PostgreSQL has `to_char(date, text)` with the same format model. Both engines return `1996-01-02` for `o_orderkey = 1`. Not a spec construct — the canonical set added it, presumably to normalise CUBRID's `MM/DD/YYYY` default output — but it is portable as written, so removing it would be an unforced change. |
| 2 | q3/q18 `group by o_orderdate` / `order by o_orderdate` while `o_orderdate` is also an output alias for the `TO_CHAR` expression | q3, q18 | **keep verbatim** | Name resolution differs in principle (PostgreSQL resolves an ambiguous `GROUP BY` name to the *input* column and an `ORDER BY` name to the *output* column), but it cannot change results here: `'YYYY-MM-DD'` is a lossless day-granularity rendering, so grouping by the text and grouping by the date partition identically, and lexicographic order of ISO dates equals chronological order. Measured rather than argued — on `o_orderkey < 500000` the group count is **2406** three ways: as written on PostgreSQL, with an explicit `group by orders.o_orderdate` on PostgreSQL, and as written on CUBRID. Recorded because it is the one place in the set where an alias shadows a base column. |
| 3 | `SUBSTRING(c_phone, 1, 2)` — 3-argument comma form | q22 | **keep verbatim** | PostgreSQL accepts the comma form and resolves it on `bpchar` through the implicit `bpchar→text` cast; returns `text`. Both engines give `'25'` for `c_custkey = 1` and the Q22-shaped `IN` selects 179,755 rows on both. The standard `SUBSTRING(x FROM 1 FOR 2)` form was **not** substituted in: it would be a change with no forcing reason. |
| 4 | `LIMIT n` | q2 (100), q3 (10), q10 (20), q18 (100), q21 (100) | **keep verbatim** | PostgreSQL supports `LIMIT n` natively. The TPC-H spec's own wording is "first n rows", which each engine spells its own way; the canonical set already chose `LIMIT`, and it is valid on both, so it stays. No `LIMIT` was added to or removed from any query. |
| 5 | Leading-dot numeric literals `.06 - 0.01` | q6 | **keep verbatim** | PostgreSQL parses `.06`; folds to `0.05` / `0.07`. |
| 6 | `extract(year from …)` | q7, q8, q9 | **keep verbatim** | Standard on both. Return type differs (PostgreSQL `numeric`, CUBRID integer) but the value is an integral year, and it is used only for grouping and ordering, so no result can change. |
| 7 | `create view revenue0 (supplier_no, total_revenue) as …` | q15 | **keep verbatim, 3 statements** | PostgreSQL supports a column list in `CREATE VIEW`. **Converting q15 to a CTE is prohibited** — the view structure is what is being compared, and a CTE would change the optimisation problem on both engines. The canonical set ships the split files `q15_create_view` / `q15_select` / `q15_drop_view`; the dialect ships the same three so the harness executes three statements, and only the view body's `DATE_ADD` changed. Verified in the smoke run: create → `EXPLAIN` select → drop, and `revenue0` gone afterwards. |
| 8 | `left outer join … on` with a predicate in the `ON` clause | q13 | **keep verbatim** | Standard on both; the `not like` stays inside `ON`, where moving it to `WHERE` would change outer-join semantics. |
| 9 | `count(distinct ps_suppkey)` | q16 | **keep verbatim** | Standard on both. |
| 10 | `ps_suppkey not in (subquery)` | q16 | **keep verbatim** | Left as `NOT IN`. Rewriting to `NOT EXISTS` is a semantic-adjacent optimisation (they differ on NULLs) and would be a plan-changing rewrite, which is out of scope for a dialect. |
| 11 | Correlated scalar subqueries and `exists` / `not exists` | q4, q17, q20, q21, q22 | **keep verbatim** | Standard on both; flattening is explicitly not a dialect change. |
| 12 | Bare `db_root` dual-table idiom | — | not applicable | Only used in this stage's throwaway probes, never in a query file. |

## 4. Smoke check (parse/plan only — no timing)

`EXPLAIN` on all 22 PostgreSQL statements against the loaded 8-table schema: all
22 planned successfully, q15 through the create → explain → drop sequence, and
`revenue0` was confirmed dropped afterwards. Plan text is archived under
`.git_ignored_dir/g1-assets/raw/pg-explain/` for G2 to classify — this stage
does not read anything into it. No `EXPLAIN ANALYZE`, no execution, no timing:
timing is G1's job and pre-judging plan shape is prohibited by ADR 0005.

The CUBRID side was not re-validated by execution here: `qN-cubrid.sql` is
byte-identical to the canonical set, which ADR 0004 already accepts as the CUBRID
dialect, and CUBRID has no execution-free `EXPLAIN`. First execution of q2–q22 on
CUBRID happens in G1.
