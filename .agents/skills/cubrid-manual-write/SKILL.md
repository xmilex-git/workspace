---
name: cubrid-manual-write
description: Author or update CUBRID user-manual pages (RST, ko+en) for an upstream CUBRID/cubrid-manual PR, including weaving an engine behavior change into the existing sections — audit what the engine exposes vs what the manual says, write in the manual's house style, run every example on a real server and paste the output verbatim, verify the Sphinx render, and open one ko+en PR against develop. Use when asked to document an engine feature, parameter, hint, or trace output in cubrid-manual, to "write/update the manual", "매뉴얼 작성/집필/문서화", "RST 작성", or to prepare/respond to a cubrid-manual PR. For merely reading the manual to answer a question, use the cubrid-manual skill instead.
---

# CUBRID Manual Writing (LLM contributor rulebook)

**Boundary with `cubrid-manual`:** that skill *consumes* the manual (search `en/`/`ko/` RST to answer
questions). This skill *produces* it: the rules for changing `/home/cubrid/dev/cubrid-manual` and getting
the change merged upstream. Use `cubrid-manual` inside this skill whenever you need to look something up.

Every rule here was paid for by a review round or a user correction on upstream PRs
[#768](https://github.com/CUBRID/cubrid-manual/pull/768) (CBRD-26722, 11.5 parallel query + memoize) and
[#772](https://github.com/CUBRID/cubrid-manual/pull/772) (CBRD-27299, PARALLEL_ENABLE). The misses that
got past the rules anyway are the cases in [PITFALLS.md](PITFALLS.md): read it before writing, walk it
before every push.
Where a rule and this file disagree with the tree's own precedent, **the manual's existing text wins**;
where they disagree with the engine code, **the code wins**.

## Ground rules

1. **Code is the source of truth.** JIRA, design docs, earlier PRs, and even the current manual can be
   stale. Every parameter default/range, hint name, trace label, threshold, and constraint you write is
   verified in the engine checkout (`/home/cubrid/dev/cubrid-worktree/develop`, `system_parameter.c`,
   parser, trace handlers; look symbols up with `tools/code-index/code-index`) before it goes in.
2. **No example without an execution.** Every SQL block was run on a server you control; every trace or
   conf output is the captured text, unrounded and unedited. See [VERIFY.md](VERIFY.md).
3. **ko first, en mirrors it** paragraph for paragraph (same anchors, bullets, notes, code blocks).
4. **Surgical diffs.** Touch only the sections the audit lists. Record anything else you notice as an
   observation, not an edit.
5. **HITL is scarce.** Ask the user only for taste (style/example policy, once) and for the go-ahead
   before opening the PR. Everything else is decided from evidence.

## Workflow

Work the phases in order; each has a checklist in its reference file.

| Phase | Do | Reference |
|---|---|---|
| 0. Ticket | The manual work is tracked by a CUBRIDMAN issue: if none exists, create one (Task, priority Minor, English summary, a one- or two-sentence Korean description, as CUBRIDMAN-312) and link it `Relates` to the CBRD issue (CBRD-27583 → CUBRIDMAN-357, user 2026-10-29). | `cubrid-jira-issue-write` step 6 (payload, link, read-back) |
| 1. Audit | Inventory the user surface (parameters, hints, trace, activation/fallback semantics) from JIRA link web + engine PR sweep + code; grade the manual `없음`/`부실·낡음`/`충분`; decide placement by precedent; emit a section-level work list. A behavior change to sections that already exist: classify each change against the last release, not develop, and weave it into those sections (§3a). | [GAP-AUDIT.md](GAP-AUDIT.md) |
| 2. Environment | Claim a port (`just port-claim <db> <effort>`), isolated install via `INSTALL_PREFIX`, create the db, start it through `cubrid-server-control`. | [VERIFY.md](VERIFY.md) §1 |
| 3. Write ko | Follow the templates and vocabulary rules; grep the manual before coining any term. | [STYLE.md](STYLE.md), [PITFALLS.md](PITFALLS.md) |
| 4. Run examples | Generate data with catalog cross joins, capture traces verbatim, log SQL+output per example in the ticket. | [VERIFY.md](VERIFY.md) §2–3 |
| 5. Mirror en | Paragraph-level mirror, American spelling; then `scripts/rst-symmetry.sh -d <base> ko/<f> en/<f>`. | [STYLE.md](STYLE.md) §8 |
| 6. Verify | `scripts/rst-lint.sh`, Sphinx build with zero warnings on touched files, Playwright render check of every touched ko/en page (`scripts/render-check.js` + screenshots of new blocks), 3-pass en QA; walk the pitfall rules into `<scratch>/<effort>/pitfalls.md`. | [VERIFY.md](VERIFY.md) §4–6, [PITFALLS.md](PITFALLS.md) |
| 7. PR | Semantic commits, one ko+en PR to `develop`, user approval before opening, code-first review responses; every round starts and ends with `scripts/review-sweep.sh <pr>`. | [PR.md](PR.md) |

## Quick start

```bash
S=<tooling-repo>/.agents/skills/cubrid-manual-write/scripts      # this skill's scripts
cd /home/cubrid/dev/cubrid-manual && git fetch upstream && git switch -c <jira-key>-docs upstream/develop
# ... audit, write ko, run examples, mirror en ...
$S/rst-symmetry.sh -d upstream/develop ko/sql/foo.rst en/sql/foo.rst   # ko/en structural delta must match
$S/rst-lint.sh     -d upstream/develop ko/sql/foo.rst en/sql/foo.rst   # house-style sweeps on added lines
# Sphinx build (venv, both languages): VERIFY.md §5 — expect no warning on sql/foo.rst
```

Both scripts also run without `-d` (whole-file mode) — the right gate for a page you wrote end to end.

## Delegation

Builds and the ko↔en semantic comparison are delegated using the harness-specific worker policy
in `.agents/AGENTS.md` (Codex: Luna/max, fast when supported; Claude Code: Sonnet/xhigh via the
`Workflow` tool). Include the delegation execution contract from
`.agents/AGENTS.md` verbatim, the scratch rule (`.git_ignored_dir/scratch/`, never `/tmp`), and the
`cubrid-server-control` requirement in every delegation prompt. The lead keeps: the audit verdicts,
the prose, the mechanical sweeps, the PR, and the example runs on the built install (server
start/stop, data generation, query/trace capture), which are smoke per that file's division of labor.

## Worked example (provenance)

The 11.5 journey that produced this skill: map
[workspace#144](https://github.com/xmilex-git/workspace/issues/144); gap audit
`docs/research/manual-gap-audit.md@research/manual-gap-audit`; engine PR sweep
`docs/research/engine-pr-user-surface.md@research/pr-sweep`; original style guide
`docs/research/manual-style-guide.md@research/manual-style-guide` (superseded by [STYLE.md](STYLE.md));
merged result CUBRID/cubrid-manual#768 (`sql/parallel.rst`, `sql/tuning.rst`, `admin/config.rst`, ko+en).
