# SQL testcase rules (CTP `sql` suite)

Work in the TC worktree that [pr-and-jira.md](pr-and-jira.md) §1 creates (`~/dev/cubrid-tc-worktree/cbrd_<N>`
in merged mode, the `tc/pr-<PR>` worktree in open mode). Model files to imitate, on cubrid-testcases
develop: `sql/_36_guava/cbrd_27465/cases/cbrd_27465.sql` (reference twins, trace tokens),
`sql/_36_guava/cbrd_26711/cases/cbrd_26711.sql` (serial twins, error cases),
`sql/_36_guava/cbrd_27568/cases/cbrd_27568.sql` (parallel scan under test_mode).

## How CTP runs the file — facts every rule below follows from

- **One connection per shard, cases back to back.** Whatever a case leaves in the session
  (trace on, a traced plan with no `show trace`, session variables, changed parameters) hits the
  next case. Incidents: trace left on in `cbrd_24876` made `cbrd_27485` print a foreign plan
  (2026-10-06); 7 leaked variables pushed a later case over the 20-variable limit (-1071, 2026-09-26).
- **A statement ends at a line that ends with `;`** — comments are not parsed. A `/** */` header
  line ending in `;` becomes a statement and prints `Error:-493` (cbrd_27465, 2026-09-22). A `;` in
  the middle of a line is harmless. A whole line starting with `--` is dropped before parsing.
- **CTP masks every digit** in the plan, the trace statistics, the first `rewritten query` line and
  in error messages: `parallel workers: 4` → `?`, `idx_col2` → `idx_col?`, `rows: 100` → `?`.
  Result rows are **not** masked. So a trace can only assert **tokens** (`MEMOIZE`, `gather: buildvalue`,
  `NESTED LOOPS (semi join)`, `method: hybrid`, `PARTITION`), never a count. Counts need a shell TC.
- **No `.answer` → the case is skipped and the run still says PASSED.** Seed a wrong placeholder
  answer so the case runs NOK and writes its `.result` (see verify.md §2).
- `test_mode=yes` in CTP's `sql.conf` lowers thresholds: `parallel_scan_page_threshold` 32 pages
  (≈100,000 rows of `(int, int)` is enough for a parallel heap scan), parallel sort / hash-join
  thresholds 0 → raised to 2 pages by `compute_parallel_degree` (an input list must span 2+ pages).
  Data sized at the threshold flakes, and heap placement changes page counts between builds: give
  every page threshold ≥3× margin (#3661: 64k vs 32k
  `max_hash_list_scan_size`; #4312: 500 rows = 1 page fell under the 2-page floor).
- **A constant LIKE pattern never reaches the matcher**: `qo_rewrite_like_terms` turns it into `=`,
  `BETWEEN` or `IS NOT NULL`. A case about LIKE evaluation keeps its patterns in a table column (join)
  or in the select list (CBRD-27181).
- **ESCAPE twins**: a twin for escape semantics replaces the escape character in both target and
  pattern with a multi-byte character absent from the data (replacing it only in the pattern changes
  `!!`). The old loop decides "last escape" by the next byte, so a multi-byte escape at the end is never
  trailing: trailing-escape shapes get literal values (CBRD-27181).
- **Never** put a binary-collation pattern whose escaped byte is followed by a trailing escape in the
  same literal run: `lang_strmatch_binary` asserts (`size1 == 0 || size2 == 0`) on optdebug, and develop
  still reaches it with ESCAPE '_' or '%' (found on CBRD-27181, a separate defect).
- **Invalid byte sequences**: a varchar column drops a truncated last character on insert; build the
  bytes with `from_base64()` at evaluation time (there is no `unhex()`; `hex()` prints them).
- **Heap order is not insertion order.** A later INSERT fills free space left in earlier pages, and
  the placement differs between builds (CBRD-27177: 1701 vs 1710 distinct keys among the first 2000
  rows scanned). A property that depends on the first N rows read (hash aggregation giving up, LIMIT
  without ORDER BY) must hold in any order, e.g. by capping how many rows repeat a key.
- **Estimates move with sampling and heap placement.** Statistics and histograms are built from
  samples, and record placement in the heap differs between builds and runs, so an estimated row count
  or selectivity is never exact. Any case whose expected plan or parallel decision depends on an
  estimate keeps it far from the threshold on both sides: at least 5x above (or 1/5 below) the
  threshold, never near it, with uniform data so no single page or sample decides it. Use
  `update statistics on <t> with fullscan` where the build allows, and run every point 3 times
  before trusting it (user, 2026-10-08, CBRD-27100 histograms).
- A recursive CTE stops at 2000 rows (`cte_max_recursions`); generate big tables by cross join:
  `insert into t select rownum, mod(rownum, 6) from db_class a, db_class b, db_class c, db_class d limit 100000;`

## File skeleton (copy, then fill)

```sql
/**
 *  This test case verifies CBRD-<N>: <what must hold, one sentence>.
 *
 *  <2-4 lines: what the engine did before, what the fix decides.>
 *
 *  <2-4 lines: how it is judged — the reference twin (NO_UNNEST / parallel(0) / no_parallel_scan /
 *  parameter off) whose result block must equal the tested block, and the trace token that proves
 *  the new path. Note that CTP masks digits so only tokens are asserted.>
 *
 *  Coverage:
 *    Case 1:  <repro>; result = <twin>
 *    Case 2:  ...
 */

drop table if exists t_outer, t_inner;

-- <one line per table: why this shape and size>
create table t_outer (a int primary key, k int);
insert into t_outer select rownum, mod(rownum, 6) from db_class a, db_class b, db_class c, db_class d limit 100000;
create table t_inner (k int primary key, v int);
insert into t_inner values (0, 10), (1, 20), (2, 30);
update statistics on t_outer, t_inner with fullscan;

set trace on;


evaluate 'Case 1: <what>; result = parallel(0)';
select /*+ recompile */ k, count(*) from t_outer o, t_inner i where i.k = o.k group by k order by k;
show trace;
select /*+ recompile parallel(0) */ k, count(*) from t_outer o, t_inner i where i.k = o.k group by k order by k;


evaluate 'Case 2: ...';
...
show trace;
-- trace goes off before the last query that no show trace reads: its plan would stay in the
-- session and the next case's first show trace over a cached plan would print it
set trace off;
<last twin query>;

set system parameters '<param>=default';
drop table t_outer, t_inner;
```

## Header (the `/** */` block)

1. 20–30 lines: sentence of what is verified → before/after in 2–4 lines → how judged in 2–4 lines
   → `Coverage:` with one `Case N:` line each. The engine-internal narrative and develop's numbers
   go to the PR body, not here (user, 2026-09-30 #3611; QA lint caps headers, CUBRIDQA-1481).
2. **No line ends with `;`** inside the header or any comment. Check:
   `sed -n '1,/\*\//p' <file> | /usr/bin/grep -c ';[[:space:]]*$'` must print `0`.
3. **No `--` inside `/** */`** — CTP drops that line and the block breaks.
4. No workspace issue numbers, decision ids, map names, developer names. Issue keys (`CBRD-N`) and
   engine PR numbers are fine.
5. An engine function named in a comment must exist: `tools/code-index/code-index ~/dev/cubrid-worktree/develop definition <name>`
   (#3642 named a function that does not exist).
6. English, `*  ` two-space indent after the star, as the model files.

## Setup

7. One `drop table if exists a, b, c;` first; `create` + `insert` per table with a one-line `--`
   comment saying why this shape; `update statistics on <tables> with fullscan;` once; `set trace on;` once.
8. Table and column names contain **no digits** (`t_outer`, `col_a`): masking turns `t2` into `t?`
   and two tables can become indistinguishable in the answer. A table alias equal to a column name
   fails with -494.
9. Data gives every group a **different row count** and a count that equals no group's average:
   a wrong memo key or a dropped group then changes the output (#3655 bot: totals 108 and 24 hid
   a missing `o0.g` in the key because the groups averaged out).
10. Float-producing aggregates (`AVG`, `STDDEV*`, `VAR*`) are wrapped: `round(avg(v), 2)` or
    compared as integers. The CCI driver prints floats with another precision, and this avoids a
    second `.answer_cci` (cbrd_26711 needed one; user decision 2026-10-08: no CCI runs here).
11. Row and key size come from incompressible values: concatenated `sha2(...,512)` hex or `BIT(n)`.
    Never rely on CHAR padding: develop stores CHAR as variable-length and compressed
    (CBRD-26663/26956), and CHAR is capped at 2048 bytes (CBRD-26799).
12. `USING INDEX` must be the last clause, after WHERE, so it cannot be combined with GROUP BY or
    ORDER BY (-493). Force an index with `FROM t FORCE INDEX (idx)` and build the heap twin with
    `IGNORE INDEX (idx)`.
13. A parallel index scan opens only under a buildvalue or mergeable-list gather (an aggregate without
    GROUP BY). An `int` sum over 100k rows overflows (-458): sum `cast(k as bigint)` (CBRD-27100).
14. To get the default (non-histogram) selectivity on a build that keeps histograms, end the range at a
    subquery (`k > (select c from t_bound)`); every point then estimates it the same way (CBRD-27100).
15. An overflow key is longer than DB_PAGESIZE/8 (2,048 bytes on 16K pages). `repeat(md5(...))` compresses
    to a short key; join distinct md5 values with `group_concat` after raising `group_concat_max_len`.
16. **The answer comes from the post point, but CI runs develop.** Before writing traced queries, run
    the planned shapes with a placeholder answer on pre, post and dev, and trace only shapes whose
    post and dev output match. Shapes that moved after mid-2026: GROUPBY lines (readrows, parallel sort
    lines), hash joins, the parallelism of an outer index scan keyed by a subquery, and the `IS NOT NULL`
    CBRD-27058 (e23a9e513) adds to a MIN/MAX subquery with WHERE in `rewritten query` (CBRD-26931).
17. MIN/MAX over an indexed column reads one key (`noscan`, `agl:`) and opens no scan; a case that needs
    the scan keeps that column unindexed.
18. **Execution counts in sql**: put `(select s.next_value from db_root) * 0` in the subquery and read
    the serial's current value as a result row (rows are not masked) — CBRD-26931 counted +4 per query
    (one per worker) before the fix and +1 after.
19. Hints apply per query block: a reference twin puts `no_parallel_scan` on every block (derived
    tables, subqueries), not only the outermost.
20. **Row placement for branches that need a neighbour on the same page**: size rows so exactly two fit a
    page (two rows + unfill ≤ page < three rows), e.g. a skipped row then the key row, and prove the
    placement with gdb branch counts. csql cannot print OIDs of a REUSE_OID table, and develop's heap
    capacity output counts the header page (3001 vs 3000) (CBRD-26799).
21. **Keys longer than a sort page** (~16 KB) never fit the sort buffer, so every parallel worker's first
    row takes the long-record path: build them from ~136 SHA-512 digests with `group_concat` (raise
    `group_concat_max_len`; its ORDER BY takes only the argument or a position) and set them by UPDATE
    after the load so home slots stay put (CBRD-26799).
22. `FORCE INDEX` with a predicate only on a non-leading column of a composite index falls back to a
    heap scan; `INDEX_SS` reads every key, including keys with a NULL leading column.
23. **Hash GROUP BY internals** (CBRD-27177): each group's first row (all list columns) goes to the main
    sort input, and partial results (key + accumulators) of groups with 2+ rows go to the partial list;
    both sorts print one shared `parallel workers` line. Hash memory counts the first row and the key, so
    a wide column in the key counts twice; to grow only the main sort input, read the wide column with
    `count(col)`. Prove margins with variants: a 1/3-size table that still prints the parallel line
    proves a 3x page margin, a 6x-wider key that still prints `hash: true` proves the memory margin;
    first check that the detector line has no other source.
24. An index scan with no key range cannot be forced: `USING INDEX` is ignored and the heap is scanned.
    IN-list elements use values present in the data; an absent value can make a histogram estimate
    fall back (CBRD-27100).
25. `ORDER BY` on the tested table's primary key lets the optimizer read through the index and skip the
    sort, which bypasses a heap-scan path (CBRD-27041 hid its result change this way). Heap-path cases
    use a table without an index or order by a non-indexed column.
26. Many paths, header ≤ 30 lines: group close shapes as several test/twin pairs inside one case
    (CBRD-27041: 18 cases → 15).

## Cases

11. Two blank lines, then `evaluate 'Case N: <what>; result = <twin>';` — single quotes, no double
    quotes or apostrophes inside, numbered from 1 without gaps. A `;` inside the quotes is fine.
12. Every tested query: one line, `/*+ recompile <hints> */`. `recompile` makes each `show trace`
    print its own plan; without it a plan left by an earlier case can be printed (cbrd_27509, 2026-09-30).
13. Each case = tested query → `show trace;` → the **reference twin** (same query, old path forced:
    `NO_UNNEST` in the subquery, `parallel(0)`, `no_parallel_scan`, or the parameter set to 0/off and
    back). The two result blocks must be identical. A twin is what catches a wrong value; a trace
    token alone passes a wrong value (cbrd_26711 design). Rule R5 (no switch exists): write the
    expected literal result and say in the header that the pre-fix build also passes.
14. Output **groups or rows with `order by`**, not one total (rule 9). `count(*)` alone is fine only
    for an all-or-nothing check (0 vs all).
15. Assert the new path by a **token** in the trace (rule: masked digits). If the token appears only
    when something happened at runtime (`MEMOIZE` prints only with hits), design the data so it must
    happen (repeated keys).
16. Error cases: the error block (`Error:-NNN`) is the result; still run the twin so the error comes
    from the same place in both (cbrd_26711 cases 19/22: an error raised in a serial fallback would
    pass a parallel-merge bug).
17. Partition, NULL key, empty input, and the parameter-off fallback are separate cases when the
    diff has a branch for them (judge.md §3).
18. A case that would hit a **known develop assert on optdebug** (CTP CI is optdebug) is left out with
    the exclusion reason naming the JIRA key (CBRD-27572 kept GROUP BY subqueries out of cbrd_27567).

## Cleanup — the session must be as it was

19. `set trace off;` right after the last `show trace` the file needs, with the leak comment, before
    any later query.
20. `deallocate variable @a, @b;` for every `@name` the file defines (`grep -o '@[a-z_]*' <file> | sort -u`).
21. `set system parameters '<name>=default';` for every parameter the file set.
22. `deallocate prepare <name>;` for every `prepare`; drop every serial / view / procedure / trigger created.
23. End with one `drop table ...;` listing every table.

## Checklist before saving (each line is a command or a yes/no)

- `sed -n '1,/\*\//p' <file> | /usr/bin/grep -c ';[[:space:]]*$'` → `0`
- `/usr/bin/grep -c '^ \*.*--' <file>` → `0` (no `--` in the header)
- `/usr/bin/grep -o "evaluate 'Case [0-9]*" <file>` → consecutive numbers from 1
- `/usr/bin/grep -c 'set trace on' <file>` = `/usr/bin/grep -c 'set trace off' <file>` and the last
  `set trace` in the file is `off`
- every traced `select` has `recompile`; every multi-row select has `order by`
- every `@var` deallocated; every `set system parameters` has a `=default` later; every table dropped
- no digits in identifiers; no float printed unrounded
- the twin exists for every tested query, or the header says "pre-fix build also passes (correctness TC)"
- header 20–30 lines, `Coverage:` rows = `evaluate` count
- every plan, parallel or hash decision that rests on an estimate or a page count states its margin in
  `Setup:`: an estimate ≥5x above or ≤1/5 of its threshold, a page count ≥3x its threshold
