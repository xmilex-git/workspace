# GAP-AUDIT — from "the engine changed" to a section-level work list

The audit answers one question: **which user-visible surfaces exist in the engine, and what does the
manual say about each?** Its output is the writing ticket's input. Do it before touching RST.

## 1. Inventory the user surface (four surfaces)

Collect every item under each surface, with the code location that proves it.

| Surface | Where the truth is | What to record |
|---|---|---|
| **System parameters** | `src/base/system_parameter.c` (prm definitions: default, lower/upper, flags `PRM_USER_CHANGE`, `PRM_FOR_SESSION`, `PRM_HIDDEN`, `PRM_FOR_QRY_STRING`, `PRM_FORCE_SERVER`) | name, default, range (upper `NULL` ⇒ "없음/none"), unit type, session-settable?, restart-only?, hidden?, boot-time clamps and their order |
| **SQL hints** | parser (`parse_tree_cl.c`, `csql_grammar.y`) — which statements accept it (SELECT only vs SELECT/UPDATE/DELETE) | name, argument, meaning, precedence vs sibling hints, retired old names |
| **Trace / plan output** | trace handlers and dump code (`*_trace_handler.cpp`, `query_dump.c`), JSON and text forms | exact labels and field names, per-worker ranges, **output gates** (printed only when …) |
| **Activation, constraint, and fallback semantics** | eligibility checkers (`*_checker.cpp`, `possible_check`), degree computation, threshold constants | thresholds and formulas, hint-vs-threshold precedence, partial reservation/serial fallback, order-nondeterminism, self-disable rules |

Sources, in order of trust: **engine code** > merged engine PR descriptions > JIRA (link web of the
epic + descendants via the `jira` skill) > existing manual > open drafts. When JIRA and code disagree,
record the discrepancy and go with the code (six such mismatches surfaced in the 11.5 audit, e.g. a
hint that had been reverted, a "hint bypasses threshold" claim that was false).

### Engine PR sweep (how to find what changed since the last documented version)

```bash
cd /home/cubrid/dev/cubrid-worktree/develop
git log <last-release-branch-point>..develop --oneline --grep '<feature-keyword>'   # then read each PR body
git diff <branch-point>..develop -- src/base/system_parameter.c                   # new/renamed parameters
git diff <branch-point>..develop -- src/parser/                                    # new/renamed hints
git grep -n '"<trace label>"' src/                                                 # trace string surface
```

Classify each PR: new surface / constraint lifted ("when does it now apply") / default or activation
rule change / trace-only / internal (no surface) / bugfix (release-note material, not manual). The
"constraint lifted" and "activation rule" rows become the feature page's applicability section.

## 2. Grade the manual against each surface

Vocabulary: **없음** (absent) / **부실·낡음** (present but incomplete or contradicted by the engine) /
**충분** (adequate). For each item record: verdict, current file:line (or where it *should* live), and
what exactly is wrong. Use the `cubrid-manual` skill to grep both `ko/` and `en/`.

Also check open or recently closed manual PRs on the topic: harvest their diff (verbatim, into
`docs/research/`) and grade each hunk **inherit / inherit-after-fix / drop**. Prior drafts are style
and structure donors, not fact sources.

## 3. Placement decisions

- **New page vs section**: default to a section beside the closest sibling feature when the surface is
  small (one parameter + one trace block). Precedent beats taxonomy — find a feature of the same
  *shape* (e.g. an executor cache with no syntax, one size parameter, trace-only observability) and
  sit next to it, in `tuning.rst`, `config.rst`, or the feature page. New page ⇒ toctree + index
  bullets in both languages.
- **Hidden parameters**: no `config.rst` entry (tree convention). Observable behavioral numbers still
  go in the feature prose (STYLE.md §4).
- **Independent features** do not share a page just because they shipped together (memoize is not in
  `parallel.rst`: readers would infer it needs parallelism).

## 3a. Behavior changes woven into existing sections

When an engine change alters behavior the manual already describes (types, errors, timing, plan cache,
driver rules) and no new section is wanted, the audit is per changed rule, not per new surface.

- **Baseline is the last release users run, not develop.** A JIRA "spec change" table compares against
  develop, which may hold unreleased changes. Run each item's example on the release install
  (`~/release/CUBRID-<ver>`) and on the new build with `tools/fast-gate/fast-cs-csql.sh out r <release> p.sql
  n <new> p.sql` (JDBC-only items: `tools/fast-gate/fast-cs-jdbc.sh`) and diff. Classify: **changed** (document),
  **same as release** (drop: the change only undid an unreleased develop state), **defect fix** (release
  note, not manual, unless the manual states the old behavior), **kept from an earlier unreleased change**
  (document the final state in the same sentence).
- **Find every place, then re-run what is there.** Grep `ko/` for the feature's nouns (호스트 변수, 사용자
  정의 변수, the function names, the plandump field names) and read each hit. Re-run every existing example
  on a touched page and in any section that states the changed rule; a stale output is replaced by a
  capture (PITFALLS Rule 2), a now-failing example is rewritten so it shows the new rule.
- **Placement.** The rule goes into the section that defines the feature (the function's own entry, the
  conversion rules, the statement page). Caveats (when an error appears, when a plan is printed, extra
  compiles, what is refused) go into that section's `.. note::`. No new section, no "변경 사항" heading, no
  version names (STYLE.md §3). Link related places with `:ref:` instead of repeating the rule.
- **Scope of edits.** Unchanged meaning keeps its words (PITFALLS Rule 3). A pre-existing inaccuracy is
  fixed only when the change alters that sentence's meaning (CBRD-27583: "SQL_ID is the MD5 of the
  original query" became wrong to leave once SQL_ID varies by bind type; the code hashes the sql hash
  text). Other drift (stale plandump stats format) is recorded as an observation.

Worked example: CBRD-27583 (PR 8213) — 29 develop-relative items reclassified against 11.4.6 into 12
documented changes across 10 ko/en page pairs; audit `.git_ignored_dir/scratch/cbrd27583-manual/audit.md`.

## 4. "Do not document" list

Write down every retired or renamed name found during the sweep (old hint names, renamed parameters,
old trace labels, reverted features, JIRA-only names). The self-review before the PR greps for each
and expects zero hits.

## 5. Output: section-level work list

One numbered item per (file, section) with: what to add/change, the surface items it covers, the code
reference, and which prior-draft hunks it inherits. Group by file and by ticket. Mark items that
require a **runtime confirmation** on the test server (e.g. "is constraint X still enforced?") — the
writing phase re-verifies constraints against the *current* develop; several audited constraints had
been lifted by merges between audit and writing.

## 6. Record decisions

Non-obvious calls (placement, hidden-parameter policy, what to drop) get a decision ID with reason,
trade-off, and rollback path in the audit document, so a reviewer can see why the manual is shaped
that way.

Worked example: `docs/research/manual-gap-audit.md@research/manual-gap-audit` (13-item work list, two
decisions, one inventory correction) and `docs/research/engine-pr-user-surface.md@research/pr-sweep`.
