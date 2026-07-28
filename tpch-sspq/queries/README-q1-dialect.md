# Q1 — Engine Dialect derivation

Canonical Query Set entry: `~/dev/cubrid/.vscode/TPC-H/scale10/queries/q1.sql`
(ADR 0004). Copied verbatim to `q1-cubrid.sql`; `q1-pg.sql` is the PostgreSQL
Engine Dialect derived from it.

## Diff

```diff
--- q1-cubrid.sql
+++ q1-pg.sql
@@ -13,7 +13,7 @@
 from
 	lineitem
 where
-	l_shipdate <= DATE_SUB(DATE '1998-12-01', INTERVAL 90 DAY)
+	l_shipdate <= date '1998-12-01' - interval '90' day
 group by
```

One line. Nothing else in the statement is touched: identical select list,
identical aggregate expressions and argument order, identical `group by`,
identical `order by`, no `limit`, no hint, no join or subquery rewrite.

## Why that one line

`DATE_SUB(d, INTERVAL n DAY)` is a MySQL-compatible CUBRID builtin that
PostgreSQL does not have. The replacement is the interval-subtraction form used
by the TPC-H specification text for Q1 (`date '1998-12-01' - interval '90' day`),
so it is syntax-forced, not a rewrite:

* Same operand: the literal `date '1998-12-01'`.
* Same operation: subtract a 90-day interval.
* Same result instant: `1998-09-02`.

### Recorded type nuance

CUBRID's `DATE_SUB(DATE …, INTERVAL … DAY)` returns `DATE`, so CUBRID compares
`DATE <= DATE`. In PostgreSQL `date - interval` is typed `timestamp`, so the
comparison is `date <= timestamp`: the planner constant-folds the right side to
`1998-09-02 00:00:00` and promotes each `l_shipdate` to a timestamp at midnight.
Because `l_shipdate` is a pure `date` column with no time component, the
qualifying row set is bit-for-bit the same as comparing against `date
'1998-09-02'`.

This is left as-is rather than "fixed" to `date '1998-12-01' - 90` (which would
stay in `date` domain) because the interval form is the spec wording, and the
per-row promotion is an integer multiply that is immaterial next to Q1's numeric
aggregation. Verified empirically — see `equivalence check` below.

## Equivalence checks run

| Check | Result |
|---|---|
| `date '1998-12-01' - interval '90' day` folds to | `1998-09-02 00:00:00` |
| Row count under the interval form vs `date '1998-12-01' - 90` | recorded in the pilot report |
| Q1 result rows CUBRID vs PostgreSQL | recorded in the pilot report |

## Not part of the dialect

No `parallel` hint, no `/*+ ... */`, no `set` of any planner knob inside the
query file. Degree of parallelism is configured at the server level on both
engines (`parallelism=6` / `max_parallel_workers_per_gather=6`) so that the
statement text stays identical to the canonical one apart from the diff above.
