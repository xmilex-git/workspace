# VERIFY — running examples, checking the render, QA-ing the translation

Nothing in this file is optional. An example that was not run, a trace that was tidied, or a page that
was not rendered is a review round waiting to happen.

## 1. Test server (isolated install, claimed port)

Never reuse another session's server or `~/CUBRID`. Everything below is delegated to a Sonnet
subagent with the delegation contract from `.agents/AGENTS.md`.

```bash
# in the tooling repo
just ports                                   # see existing claims + live listeners
just port-claim <db> <effort>                # e.g. just port-claim mandb cbrd-26722-docs  → cubrid_port_id + broker block
INSTALL_PREFIX=$HOME/release/CUBRID-<ver>.<db> WORKSPACE=/home/cubrid/dev/cubrid just rebuild release <ver>.<db>
```

Environment block — **prefix every later command with it**; an inherited `CUBRID_DATABASES` pointing
at another install makes the start fail with `Database "<db>" is unknown`:

```bash
export CUBRID=$HOME/release/CUBRID-<ver>.<db>
export CUBRID_DATABASES=$CUBRID/databases
export PATH=$CUBRID/bin:$PATH
export LD_LIBRARY_PATH=$CUBRID/lib:${LD_LIBRARY_PATH:-}
```

- Conf: copy the tooling repo's `cubrid.conf` into `$CUBRID/conf/` and set `cubrid_port_id=<claimed>`
  (or use the session conf `just port-claim` generates via `CONF=`). Check feature parameters are
  what the examples assume (`cubrid paramdump <db>`; hidden ones do not print — read the source).
- Create: `mkdir -p $CUBRID_DATABASES/<db> && cd $CUBRID_DATABASES/<db> && cubrid createdb --db-volume-size=512M <db> en_US.utf8`.
- Start/stop **only** through the `cubrid-server-control` skill wrapper (raw `cubrid server` hangs
  under captured output). No broker is needed; csql connects directly.
- Release the claim (`just port-release <db>`) when the PR is merged, not before — review rounds
  re-run examples.
- CTP runs by *any* session kill every `cub_*` of this user (see `docs/agents/port-registry.md`).
  If the server vanished mid-writing, that is why: restart it, re-check data, continue.

## 2. Data and example execution

- Bulk data via catalog cross joins, never recursive CTEs:
  ```sql
  CREATE TABLE large_table (id INT PRIMARY KEY, k INT, pad VARCHAR(200));
  INSERT INTO large_table SELECT ROWNUM, MOD(ROWNUM,100), LPAD('x',200,'x')
    FROM db_class a, db_class b, db_class c, db_class d LIMIT 1000000;
  UPDATE STATISTICS ON large_table WITH FULLSCAN;
  ```
  Check size against the gate you are documenting (`SHOW HEAP CAPACITY OF large_table` → `Num_pages`).
- Capture: `SET TRACE ON;` → the statement with `RECOMPILE` plus the hint under test → `SHOW TRACE;`.
  Save SQL and raw output per example under `.git_ignored_dir/scratch/<effort>/` (never `/tmp`).
- Paste trace **verbatim**. Then write the legend from what was printed, not from memory.
- Log every example in the ticket as a table: doc location → example → label → observed result, so a
  reviewer can diff the manual's block against the capture.

### Pitfalls that turn a planned example into a non-example

- Predicate-less `COUNT(*)` is answered from metadata (noscan) — add a predicate.
- Low-selectivity predicates make the optimizer pick an index when you wanted a heap scan — change the predicate or column.
- Indexes on low-cardinality keys compress to far fewer pages than expected and miss page thresholds — lead with a distinct column.
- `ORDER BY <pk> LIMIT n` becomes an ordered index scan: no sort to show — order by a non-indexed column.
- Simple-projection derived tables are flattened (View Merging): no list scan — force a temp result with `DISTINCT` or `NO_MERGE`.
- `USE_NL` alone may flip the join order; `ORDERED USE_NL` pins the outer table.
- Small partitions are gated per partition — pick the large one or grow the data.
- Features that print a trace block only when active (e.g. MEMOIZE `hit > 0`) need a query that actually triggers them; "no block" is a valid *negative* example.
- Constraints listed in JIRA or the previous draft may have been lifted since — re-test each one on current develop before writing it as a restriction.

## 3. Performance examples

Run each variant at least twice and report the second run; keep the two variants identical except for
the switch (parameter or hint). Report the observed times as-is with the schema and row counts.

## 4. Mechanical sweeps (lead, in the manual clone)

```bash
S=<tooling-repo>/.agents/skills/cubrid-manual-write/scripts
$S/rst-symmetry.sh -d upstream/develop ko/sql/<f>.rst en/sql/<f>.rst   # Δ(headings, anchors, bullets, notes, code/literal blocks, refs) equal
$S/rst-lint.sh     -d upstream/develop ko/sql/<f>.rst en/sql/<f>.rst   # versionadded, tabs, 쿼리, British spelling, unescaped markup, retired names
grep -rn -E -f $S/retired-names.txt ko/ en/                             # "do not document" list → 0 hits in the whole tree
```

- Symmetry: whole-file mode (no `-d`) is the gate for a page you wrote end to end; **delta mode** is the
  gate on a large page with pre-existing ko/en drift (`tuning.rst`, `config.rst` both have some).
  A mismatch means one side gained an element the other did not — add it to the poorer side.
- Lint: HARD findings block; `soft` findings are candidates to eyeball (open lists with "등",
  duplicated particles after an escape, hyphenated `row-by-row` inside a trace block). Append new
  retired names to `scripts/retired-names.txt` as audits retire more surfaces.

## 5. Sphinx build and render check

```bash
cd /home/cubrid/cubrid-manual/ko && make html 2>&1 | tee ../../.git_ignored_dir/scratch/<effort>/sphinx-ko.log | grep -E 'sql/<f>.rst|admin/<f>.rst'
cd /home/cubrid/cubrid-manual/en && make html 2>&1 | tee ../../.git_ignored_dir/scratch/<effort>/sphinx-en.log | grep -E 'sql/<f>.rst|admin/<f>.rst'
```

- Gate: **zero warnings on touched files** in both languages (pre-existing warnings elsewhere are
  noted, not fixed). `sphinx-autobuild` is in `requirements.txt` if you want a live server.
- Render check with Playwright on `_build/html/<page>.html#<anchor>`: every `:ref:` resolves, no raw
  markup leaks (`\`, `**`, `:ref:`), tables have the same geometry as their sibling tables, notes and
  code blocks render as such, math renders. Any anomaly ⇒ fix it and append the rule to STYLE.md §11.
- Structural counts (bullets, notes, code blocks, anchors, headings) are the mechanical ko↔en gate;
  semantic comparison is the QA pass below.

## 6. English QA (3 passes, branch diff only)

- **A. Semantic ko↔en comparison** (Sonnet subagent): paragraph by paragraph — conditions, numbers,
  hint names, `:ref:` targets, note presence. Report each mismatch with both texts.
- **B. Mechanical sweep** (lead, grep): American spelling (beware `parallelism` false positives on
  `-is` patterns), term/hyphen consistency, trace strings verbatim.
- **C. en-only read-through** (Sonnet subagent): grammar and clarity for a reader who never sees ko.

The lead verifies each finding against the files before accepting; findings that would break a
tree-wide convention (e.g. the config.rst unit sentence pattern) are rejected with the reason. Fix by
restoring precision on the poorer side (add the missing `:ref:`/qualifier), not by deleting from the
richer side. One commit for the QA pass.
