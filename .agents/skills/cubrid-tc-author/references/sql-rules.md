# SQL testcase rules (CTP `sql` suite)

Work in the TC worktree that [pr-and-jira.md](pr-and-jira.md) §1 creates (`~/dev/cubrid-tc-worktree/cbrd_<N>`
in merged mode, the `tc/pr-<PR>` worktree in open mode). Model files to imitate, on cubrid-testcases
develop: `sql/_36_guava/cbrd_27465/cases/cbrd_27465.sql` (reference twins, trace tokens),
`sql/_36_guava/cbrd_26711/cases/cbrd_26711.sql` (serial twins, error cases),
`sql/_36_guava/cbrd_27568/cases/cbrd_27568.sql` (parallel scan under test_mode).

This file is the **form** of a case file. Everything learned the hard way — what the server really
runs, data that exposes a wrong path, thresholds, three-point drift, coverage, session and CTP
parsing — is [sql-pitfalls.md](sql-pitfalls.md): read it before writing, walk its seven rules before
saving, and leave `<rundir>/pitfalls.md` as its record.

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

-- <one line per table: why this shape and size, and the margin over every threshold it must clear>
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
2. **No line ends with `;`** inside the header or any comment (pitfalls Rule 7). Check:
   `sed -n '1,/\*\//p' <file> | /usr/bin/grep -c ';[[:space:]]*$'` must print `0`.
3. **No `--` inside `/** */`**, and no `server-message`, `autocommit` or `holdcas` followed by
   `on`/`off` (pitfalls Rule 7): reword it.
4. No workspace issue numbers, decision ids, map names, developer names. Issue keys (`CBRD-N`) and
   engine PR numbers are fine.
5. An engine function named in a comment must exist (pitfalls Rule 7). An abort whose position
   varies between runs is described by its shape and every case number that has it (pitfalls Rule 4).
6. English, `*  ` two-space indent after the star, as the model files.

## Setup

7. One `drop table if exists a, b, c;` first; `create` + `insert` per table with a one-line `--`
   comment saying why this shape and its margin over every threshold it must clear (pitfalls Rule 3);
   `update statistics on <tables> with fullscan;` once; `set trace on;` once.
8. Table and column names contain **no digits** (`t_outer`, `col_a`); no table alias equal to a
   column name (pitfalls Rule 7).

## Cases

9. Two blank lines, then `evaluate 'Case N: <what>; result = <twin>';` — single quotes, no double
   quotes or apostrophes inside, numbered from 1 without gaps. A `;` inside the quotes is fine.
10. Every tested query: one line, `/*+ recompile <hints> */`. `recompile` makes each `show trace`
    print its own plan; without it a plan left by an earlier case can be printed (pitfalls Rule 6).
    Exception: a case that tests plan invalidation or clone reuse runs the same text without `recompile`,
    when the text exists only in this file and its first run compiles over this file's own tables and
    functions. `show trace` after a cached run prints the session's last compiled plan text, so judge by
    the Trace Statistics tokens and say why in a `--` comment (CBRD-27299 hash-join Case 9: dropping and
    restoring PARALLEL_ENABLE recompiles the cached plan on post and develop alike).
11. Each case = tested query → `show trace;` → the **reference twin** (same query, old path forced:
    `NO_UNNEST` in the subquery, `parallel(0)`, `no_parallel_scan` on every query block, or the
    parameter set to 0/off and back). The two result blocks must be identical. A twin is what catches
    a wrong value; a trace token alone passes a wrong value (cbrd_26711 design). Rule R5 (no switch
    exists): write the expected literal result and say in the header that the pre-fix build also passes.
12. Output **groups or rows with `order by`**, not one total; `count(*)` alone is fine only for an
    all-or-nothing check (0 vs all). The data behind it follows pitfalls Rule 2.
13. Assert the new path by a **token** in the trace (CTP masks digits). If the token appears only
    when something happened at runtime (`MEMOIZE` prints only with hits), design the data so it must
    happen (repeated keys).
14. **Every claim names its proof** (pitfalls Rule 1): a case that says a shape stays serial, stays
    parallel, reads the index, reads overlapping ranges or reads keys in order points at the answer
    line that shows the server ran that shape (`key range:` with the claimed number of ranges,
    `INDEX SCAN` not `agl:`, `min_max_only: true`, `skip order by: true`, the parallel line or its
    absence), or at a control probe recorded in the PR body. A constant the client rewrites before
    the server sees it is bound as a host variable (`prepare` / `execute using`).
15. Error cases: the error block (`Error:-NNN`) is the result; still run the twin so the error comes
    from the same place in both (pitfalls Rule 2).
16. A DML statement under test is followed by a select of its target rows before any cleanup, equal
    to the select after the twin DML (pitfalls Rule 2).

## Cleanup — the session must be as it was (pitfalls Rule 6)

17. `set trace off;` right after the last `show trace` the file needs, with the leak comment, before
    any later query.
18. `deallocate variable @a, @b;` for every `@name` the file defines (`grep -o '@[a-z_]*' <file> | sort -u`).
19. `set system parameters '<name>=default';` for every parameter the file set.
20. `deallocate prepare <name>;` for every `prepare`; drop every serial / view / procedure / trigger created.
21. End with one `drop table ...;` listing every table.

## Checklist before saving (each line is a command or a yes/no)

- `sed -n '1,/\*\//p' <file> | /usr/bin/grep -c ';[[:space:]]*$'` → `0`
- `/usr/bin/grep -c '^ \*.*--' <file>` → `0` (no `--` in the header)
- `sed -n '1,/\*\//p' <file> | /usr/bin/grep -ciE '(server-message|autocommit|holdcas)[[:space:]]+(on|off)'` → `0`
- `/usr/bin/grep -o "evaluate 'Case [0-9]*" <file>` → consecutive numbers from 1
- `/usr/bin/grep -c 'set trace on' <file>` = `/usr/bin/grep -c 'set trace off' <file>` and the last
  `set trace` in the file is `off`
- every traced `select` has `recompile` (or a `--` comment for the rule 10 plan-cache exception); every
  multi-row select has `order by`
- every `@var` deallocated; every `set system parameters` has a `=default` later; every `prepare`
  deallocated; every table dropped
- no digits in identifiers; no float printed unrounded
- the twin exists for every tested query, or the header says "pre-fix build also passes (correctness TC)"
- header 20–30 lines, `Coverage:` rows = `evaluate` count
- every `evaluate` line's claim has its proof: the answer token named in `<rundir>/pitfalls.md`
  (Rule 1 row) or a control probe in the PR body
- every plan, parallel or hash decision that rests on an estimate or a page count states its margin in
  the setup comment: an estimate ≥5x above or ≤1/5 of its threshold, a page count ≥3x its threshold
- `<rundir>/pitfalls.md` has a row for each of the seven rules per file, every `clear` with evidence
