# SQL pitfalls — seven rules and the cases behind them

Every rule here once let a wrong, empty or flaky case through. Read the whole file before writing a
case (Step 3) and walk it again before saving.

**The check.** Step 3 ends with `<rundir>/pitfalls.md`: one line per rule per `.sql` file, written
after reading that rule's cases:

```
| rule | file | verdict | evidence |
| 1 | cbrd_<N>_index.sql | clear | Case 5 answer: key range (a>= ? and a<= ?) or (a>= ? and a<= ?), two ranges |
| 2 | cbrd_<N>_index.sql | hit → Case 15 reworked | rank() read one key, all ranks 1 |
| 6 | cbrd_<N>_index.sql | n/a | no parameter set |
```

`clear` needs evidence (an answer token, a probe log); a bare yes is not a verdict. A `hit` is fixed
before the file is saved.

**Adding a case.** A miss that a reviewer, a bot, or a three-point run exposes gets one line under
its rule in the same commit that fixes it:
`CBRD-N (date, caught by <reviewer|greptile|pre OK|fix NOK|dev run>): <what was written> → <what
actually ran or was missed> → <fix>`. Lines older than this file carry only what the old rule said.
A new rule only when no rule fits; a reviewer's find is the first thing to re-check next time, so
the "caught by" part is never dropped.

---

## Rule 1 — The server runs the shape the case claims (positive control)

A case that claims a shape — stays serial, stays parallel, reads the index, reads overlapping
ranges, reads keys spread over the index — names the answer line that proves the server saw that
shape: the number of ranges in `key range:`, the `rewritten query` line, `INDEX SCAN` against
`agl:`/`noscan`, `min_max_only: true`, `skip order by: true`, `ANALYTIC (sort: false)`, the
`parallel workers` line, `PARTITION`. When no answer line shows it, a control probe does: the same
data under the opposite setting (no ORDER BY, `PARALLEL(n)`, the hint dropped) must change the
result, and the PR body records the probe. The claim is otherwise hollow, and the three-point run
still says OK (the shell analogue is the first check of every shell case; GLOSSARY "양성 대조").

The usual reason the shape never arrives: **the client rewrites constants before the server sees
the query.** Overlapping constant ranges are merged into one, a constant LIKE becomes `=`, `BETWEEN`
or `IS NOT NULL`, MIN/MAX over an indexed column with no range becomes an aggregate lookup
(`noscan`, `agl:`) that opens no scan. A shape that must reach the server as written is bound as a
host variable (`prepare st from '... where (a between ? and ? or a between ? and ?) ...'; execute st
using 10, 100, 50, 200;`).

- CBRD-26722 (2026-10-13, caught by reviewer): overlapping OR ranges as constants in three cases →
  the client merged them, the answer's `key range` showed disjoint ranges, no parallel scan ever read
  an overlap → host variables through `prepare`/`execute using`; one shape (descending index) then
  exposed an engine defect (rows read twice), filed as CBRD-27593, which carries that case.
- CBRD-26722 (2026-10-13, caught by reviewer): `min(a), max(a) from t_idx` under `PARALLEL(4)` as
  the "MIN/MAX keeps the index scan serial" check → `noscan` (`agl: i_a`), no index scan at all → a
  range on the indexed column (`where a >= 0 using index i_a`), which is a min/max-only index scan
  (`min_max_only: true`) that stays serial. CBRD-26931 had the other side: a case that needs the
  *heap* scan keeps the MIN/MAX column unindexed.
- CBRD-27181: a constant LIKE pattern never reaches the matcher (`qo_rewrite_like_terms`) → a case
  about LIKE evaluation keeps its patterns in a table column (join) or in the select list.
- CBRD-26722: `USING INDEX` must be the last clause, after WHERE, so it cannot be combined with
  GROUP BY or ORDER BY (-493). May-2026 points ignore `USING INDEX` on a narrow 2-column table and
  scan the heap while develop honors it → `FROM t FORCE INDEX (idx)` when an old point must read the
  index; the heap twin uses `IGNORE INDEX (idx)`.
- An index scan with no key range cannot be forced: `USING INDEX` is ignored and the heap is
  scanned. `FORCE INDEX` with a predicate only on a non-leading column of a composite index falls
  back to a heap scan; `INDEX_SS` reads every key, including keys with a NULL leading column.
- CBRD-27041: `ORDER BY` on the tested table's primary key let the optimizer read through the index
  and skip the sort, bypassing the heap-scan path under test → heap-path cases use a table without an
  index or order by a non-indexed column.
- CBRD-27100: a parallel index scan opens only under a buildvalue or mergeable-list gather (an
  aggregate without GROUP BY); a case that wants the index line keeps that shape.
- Hints apply per query block: a reference twin puts `no_parallel_scan` on every block (derived
  tables, subqueries), not only the outermost, or the twin is not serial.
- CBRD-27299: an outer-join case must not null-reject the inner side — `y.a is not null` turns the
  LEFT JOIN into an inner join and moves its ON terms into the residual set, so the ON path is no
  longer tested. A parallel hash join is sql-observable: under `test_mode` its floor is 2 pages and
  the trace shows `PROBE` with a `parallel workers` line.
- CBRD-27299 Case 10: a case that checks that sibling blocks stay parallel puts the tainted block
  (e.g. an undeclared function) in a **later** derived table, not the first: the main thread runs the
  first block itself, so a checker that misses that position changes neither the trace nor the
  result. The parallel subquery executor exists only with 2 or more clean sibling blocks.
- A path with no trace token (CREATE INDEX, a page-copy branch) is proved under gdb or by
  `er_log_debug` counts: verify.md §6a.
- CBRD-27664 (2026-10-19, caught by the lead's smoke): a GROUP BY skip inside a correlated subquery
  written as `where g = outer.k group by g` → the trace showed `SORT (group by)` with `hash: true`:
  a key bound by equality leaves nothing to skip → a range `g between outer.k and outer.k + 3`,
  checked for `group by nosort: true` in the subquery's plan.

## Rule 2 — The data must change the output when the path is wrong

Choose data so a lost row, a doubled row, a wrong key or a wrong order changes a result row. A
total that averages out, a single key, a 0-row DML, or a float printed by the driver passes a broken
path.

- Every group gets a **different row count**, and a count that equals no group's average; #3655
  (greptile): totals 108 and 24 hid a missing `o0.g` in the memo key because the groups averaged out.
- Output **groups or rows with `order by`**, not one total; `count(*)` alone only for an
  all-or-nothing check (0 vs all).
- CBRD-26722 (2026-10-08, caught by greptile): the order-skip and `rank()` queries read one key
  (`a >= 3999 and b = 5`), every row `(3999, 5)`, every rank 1 → a serial fallback lost to a parallel
  scan would still pass; widening to `a >= 3961` (one or two leaves) still came back in index order
  3/3 → distinct keys spread over the whole index with different row counts per key
  (`a >= 0 and mod(a, 400) = 1 and b <= 2`), proved by a control probe: the same scan without ORDER
  BY or the analytic under `PARALLEL(4)` prints the parallel line and returns keys out of order
  (5/6 on post, 6/6 on dev). Any "stays serial for an ordering reason" case (ORDER BY skip, analytic
  skip sort, KEYLIMIT, ROWNUM) is built this way.
- Float-producing aggregates (`AVG`, `STDDEV*`, `VAR*`) are wrapped (`round(avg(v), 2)`) or
  compared as integers: the CCI driver prints floats with another precision (cbrd_26711 needed a
  second `.answer_cci`; user decision 2026-10-08: no CCI runs here).
- A token that appears only when something happened at runtime (`MEMOIZE` prints only with hits)
  needs data that makes it happen (repeated keys).
- CBRD-26931 Case 8 (greptile): a DML statement under test is followed by a select of its target
  rows **before any cleanup**, and that block must equal the select after the twin DML; an
  affected-row count alone passes a wrong value with the same count. A DML WHERE that matches 0 rows
  proves only the trace line (a NULL subquery value also matches 0 rows): every DML gets at least one
  statement whose matched rows depend on the exact value.
- cbrd_26711 cases 19/22: an error case still runs the twin so the error comes from the same place
  in both; an error raised in a serial fallback would pass a parallel-merge bug.
- CBRD-26931: **execution counts in sql** — put `(select s.next_value from db_root) * 0` in the
  subquery and read the serial's current value as a result row (rows are not masked): +4 per query
  (one per worker) before the fix, +1 after.
- CBRD-27181 ESCAPE twins: a twin for escape semantics replaces the escape character in both target
  and pattern with a multi-byte character absent from the data (replacing it only in the pattern
  changes `!!`). The old loop decides "last escape" by the next byte, so a multi-byte escape at the
  end is never trailing: trailing-escape shapes get literal values.
- Invalid byte sequences: a varchar column drops a truncated last character on insert; build the
  bytes with `from_base64()` at evaluation time (there is no `unhex()`; `hex()` prints them).
- CBRD-27664 (2026-10-19): a group order the outer query cannot see (thousands of groups summed into
  one row) is made visible by weighing each group by its position: `rownum r` in a middle derived
  table and `sum(r * key)` outside it (`rownum * col` in one expression is rejected); a probe with the
  opposite order must print a different sum.

## Rule 3 — Stay far from every threshold, estimate and placement

Under CTP `test_mode=yes` lowers thresholds: `parallel_scan_page_threshold` 32 pages (≈100,000 rows
of `(int, int)`), parallel sort / hash-join thresholds 0 → raised to 2 pages by
`compute_parallel_degree`. Data sized at a threshold flakes, heap placement changes page counts
between builds, and estimates come from samples: every page threshold gets ≥3x margin, every
estimate ≥5x above or ≤1/5 below its threshold, with uniform data so no single page or sample
decides it, `update statistics on <t> with fullscan` where the build allows, and every point run 3
times before it is trusted (user, 2026-10-08, CBRD-27100). The margin is stated in the `Setup:`
comment of the file.

- #3661: 64k vs 32k `max_hash_list_scan_size` flaked; #4312: 500 rows = 1 page fell under the
  2-page floor.
- CBRD-27177: **heap order is not insertion order** — a later INSERT fills free space left in
  earlier pages, and the placement differs between builds (1701 vs 1710 distinct keys among the first
  2000 rows scanned). A property that depends on the first N rows read (hash aggregation giving up,
  LIMIT without ORDER BY) must hold in any order, e.g. by capping how many rows repeat a key.
- Row and key size come from incompressible values: concatenated `sha2(...,512)` hex or `BIT(n)`.
  Never rely on CHAR padding: develop stores CHAR as variable-length and compressed
  (CBRD-26663/26956), and CHAR is capped at 2048 bytes (CBRD-26799).
- CBRD-27100: an `int` sum over 100k rows overflows (-458): sum `cast(k as bigint)`. To get the
  default (non-histogram) selectivity on a build that keeps histograms, end the range at a subquery
  (`k > (select c from t_bound)`); every point then estimates it the same way. IN-list elements use
  values present in the data; an absent value can make a histogram estimate fall back.
- An overflow key is longer than DB_PAGESIZE/8 (2,048 bytes on 16K pages). `repeat(md5(...))`
  compresses to a short key; join distinct md5 values with `group_concat` after raising
  `group_concat_max_len`.
- CBRD-26799: **row placement for branches that need a neighbour on the same page** — size rows so
  exactly two fit a page (two rows + unfill ≤ page < three rows), e.g. a skipped row then the key
  row, and prove the placement with gdb branch counts. csql cannot print OIDs of a REUSE_OID table,
  and develop's heap capacity output counts the header page (3001 vs 3000).
- CBRD-26799: **keys longer than a sort page** (~16 KB) never fit the sort buffer, so every parallel
  worker's first row takes the long-record path: build them from ~136 SHA-512 digests with
  `group_concat` (its ORDER BY takes only the argument or a position) and set them by UPDATE after
  the load so home slots stay put.
- CBRD-27177 **hash GROUP BY internals**: each group's first row (all list columns) goes to the main
  sort input, and partial results (key + accumulators) of groups with 2+ rows go to the partial list;
  both sorts print one shared `parallel workers` line. Hash memory counts the first row and the key,
  so a wide column in the key counts twice; to grow only the main sort input, read the wide column
  with `count(col)`. Prove margins with variants: a 1/3-size table that still prints the parallel
  line proves a 3x page margin, a 6x-wider key that still prints `hash: true` proves the memory
  margin; first check that the detector line has no other source.
- A recursive CTE stops at 2000 rows (`cte_max_recursions`); generate big tables by cross join:
  `insert into t select rownum, mod(rownum, 6) from db_class a, db_class b, db_class c, db_class d limit 100000;`

## Rule 4 — The three points give the same answer, or the file says which point cannot

**The answer comes from the post point, but CI runs develop.** Before writing traced queries, run
the planned shapes with a placeholder answer on pre, post and dev, and trace only shapes whose post
and dev output match. A shape that a known develop assert kills on optdebug is left out with the
JIRA key as the reason. A shape that only the **post** point cannot run (an assert or defect that
develop fixed later, a syntax that changed after the fix) is not left out: it goes into a
develop-only file `cbrd_<N>_<topic>.sql` whose answer comes from develop (verify.md §5), and the PR
body shows what post did with it. A result the fix itself changed against the issue's promise is
verify.md §6b.

- CBRD-26722 (2026-10-13, caught by reviewer): the overflow OID chain path the engine PR added
  (`px_scan_index_overflow_*`) asserted on the post point (`overflow_chain_pool::try_publish`,
  relaxed on develop by CBRD-26863) → every index was kept at 50 rows a key, so no case reached the
  PR's own new code → `cbrd_26722_index_overflow.sql`, develop-only, answer from develop, post's
  assert recorded in the PR body.
- CBRD-27100 (user, 2026-10-08): `ANALYZE TABLE ... UPDATE HISTOGRAM` became `UPDATE STATISTICS`
  (532ce4b6d) after the fix → develop-only histogram file; pre and post rows read "해당 없음".
- Shapes that moved after mid-2026 (trace only shapes whose post and dev output match): GROUPBY
  lines (readrows, parallel sort lines), hash joins, the parallelism of an outer index scan keyed by a
  subquery, the `IS NOT NULL` CBRD-27058 (e23a9e513) adds to a MIN/MAX subquery with WHERE in
  `rewritten query` (CBRD-26931), the outer `SCAN (temp ...)` parallel line over a large hash-join or
  analytic result list (printed by Sep-2026 points only), `EXISTS` rewritten into a semi join on
  develop (CBRD-27299). Keep traced join and analytic results small, and use scalar correlated
  subqueries instead of `EXISTS`.
- Under a mergeable-list gather, `ORDER BY` over a small result prints the parallel sort line only
  when the merged list spans 2+ pages, which depends on how many workers returned rows and changes
  run to run: check gathered rows through a derived table with aggregates outside, or keep the sorted
  list well above 2 pages.
- CBRD-26722: on May-2026 points a 3-level nested derived query over a parallel heap scan prints
  `fetch: -?` in its top SELECT line where develop prints a count: trace list shapes at 2 levels.
- CBRD-27572: GROUP BY subqueries assert on develop optdebug → kept out of cbrd_27567 with the key
  as the reason.
- CBRD-27181: a binary-collation pattern whose escaped byte is followed by a trailing escape makes
  `lang_strmatch_binary` assert (`size1 == 0 || size2 == 0`) on optdebug, and develop still reaches
  it with ESCAPE '_' or '%' → never in the same literal run.
- A pre-build abort whose position varies between runs (cross-thread free: Case 3 in one run, Case
  11 in the next, CBRD-27299) is described in the header by its shape and every case number that has
  the shape, never by one case number.

## Rule 5 — Coverage comes from the code, and new code always has a case

The coverage list (judge.md §3–§4) is read from the diff: every branch, every boundary, both sides
of every guard. A file or function the PR **adds** must have a case or a develop-only file; the
reviewer opens the new file first. The only exclusion reasons a row may carry: unobservable from
SQL (with why), nondeterministic (R6), timing-only, a develop assert that kills CI (JIRA key). "The
post point asserts" is not one — that is Rule 4's develop-only file.

- CBRD-26722 (2026-10-13, caught by reviewer): row R108 "overflow OID chains" excluded as "post
  asserts by a race" → the PR's own new files went untested → develop-only file (Rule 4).
- CBRD-27181 (user, 2026-10-08): the TC followed the attached test plan, depth tested at 150/300
  but not at the code's own 256/257, memchr candidate retry and escape forms untested → boundaries
  are read from the code, the issue's scenarios are an input, never the list.
- Partition, NULL key, empty input, and the parameter-off fallback are separate cases when the diff
  has a branch for them.
- Many paths and a header capped at 30 lines: group close shapes as several test/twin pairs inside
  one case (CBRD-27041: 18 cases → 15).
- CBRD-27664 (2026-10-19, caught by the A/B bench, scenarios 6 and 25): the TC had GROUP_CONCAT only
  without SEPARATOR → a SEPARATOR left a regu in the scan regu list that the new path reads (develop
  reads it only for hash aggregation), so the operand landed in the group key slot → when the diff
  starts reading an existing XASL list on a new path, each aggregate takes every argument form
  (SEPARATOR, ORDER BY, DISTINCT, two arguments), with an int and a string operand.

## Rule 6 — The session leaves as it came

CTP runs **one connection per shard, cases back to back**: whatever a case leaves in the session
(trace on, a traced plan with no `show trace`, session variables, changed parameters, prepared
statements) hits the next case, and a plan left by an earlier case can be printed by this one's
`show trace`. The cleanup block of sql-rules.md is the mechanical list.

- 2026-10-06: trace left on in `cbrd_24876` made `cbrd_27485` print a foreign plan.
- 2026-09-26: 7 leaked session variables pushed a later case over the 20-variable limit (-1071).
- cbrd_27509 (2026-09-30): a traced query without `recompile` printed a plan left by an earlier case.
- The last traced query of a file: `set trace off` goes right after the last `show trace`, before
  any later query, or the last plan stays in the session and the next case's first `show trace` over
  a cached plan prints it.

## Rule 7 — CTP reads the file its own way

- **A statement ends at a line that ends with `;`** — comments are not parsed. A `/** */` header
  line ending in `;` becomes a statement and prints `Error:-493` (cbrd_27465, 2026-09-22). A `;` in
  the middle of a line is harmless. A whole line starting with `--` is dropped before parsing, so
  `--` inside `/** */` breaks the block.
- **CQT runs a statement as a control command** when its text contains `server-message`,
  `autocommit` or `holdcas` followed by `on` or `off` anywhere (`ConsoleBO.isPropOn/isPropOff`). The
  `/** */` header travels with the first statement, so a header saying "server-message on" silently
  skips the first `drop table`: the result has one block fewer than the statements (CBRD-27299).
- **CTP masks every digit** in the plan, the trace statistics, the first `rewritten query` line and
  in error messages: `parallel workers: 4` → `?`, `idx_col2` → `idx_col?`, `rows: 100` → `?`.
  Result rows are **not** masked. A trace can only assert **tokens** (`MEMOIZE`, `gather:
  buildvalue`, `NESTED LOOPS (semi join)`, `method: hybrid`, `PARTITION`), never a count; counts need
  a shell TC. Identifiers carry no digits (`t2` → `t?` makes two tables indistinguishable).
- **No `.answer` → the case is skipped and the run still says PASSED.** Seed a wrong placeholder
  answer so the case runs NOK and writes its `.result` (verify.md §2).
- A table alias equal to a column name fails with -494.
- #3642: an engine function named in a comment must exist
  (`tools/code-index/code-index ~/dev/cubrid-worktree/develop definition <name>`).
