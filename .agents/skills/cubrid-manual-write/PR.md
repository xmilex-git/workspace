# PR — upstream conventions for CUBRID/cubrid-manual

## Repos and branches

- Local clone `/home/cubrid/cubrid-manual`: `origin` = the user's fork (`xmilex-git/cubrid-manual`,
  push target), `upstream` = `CUBRID/cubrid-manual` (PR target). `git fetch upstream` before branching.
- **Base is always `develop`** — there is no `release/11.5`-style branch to target for the next version.
  Release-branch copies are separate copycat PRs opened *after* the develop merge (out of scope here;
  see the `cubrid-backport` skill for the engine-side analogue).
- Work branch from `upstream/develop`, named after the key: `cbrd-26722-115-docs`, `cubridman-353-…`.
- Never rewrite a pushed branch during review; add commits.

## Commits

- Semantic units: one per (file, concern) — "parallel.rst: add hash-join and sort sections",
  "config.rst: add memoize_memory_limit (ko/en)". ko and en of the same change go in the same commit.
- Subject: `[<KEY>] <file>: <summary> (ko/en)`. `<KEY>` is the JIRA key the work is tracked under:
  engine key `[CBRD-NNNNN]` when documenting an engine change, `[CUBRIDMAN-NNN]` for manual-only
  issues (both are accepted upstream; recent merged titles use each).
- No tabs, 4-space indentation (repo README).

## The PR

- **One PR, ko+en together**, base `develop`. Title `[<KEY>] <what> (ko/en)`, e.g.
  `[CBRD-26722] Document 11.5 parallel query execution and memoize (ko/en)`.
- Body: JIRA URL on the first line, one or two Korean sentences of scope, a bullet per file with what
  changed, and `Replaces #<n>` / `Closes #<n>` when superseding an earlier draft PR.
- The CI bot posts ko/en preview links — open them and re-check the touched pages before requesting review.

## Self-review gate (all pass before asking the user)

1. Sphinx ko/en both exit 0; **zero warnings on touched files** (logs kept in scratch).
2. `scripts/rst-symmetry.sh` and `scripts/rst-lint.sh` clean on every touched pair.
3. Every audit work-list item is present (grep a marker per item); every "do not document" name has 0 hits.
4. Every example's ticket log row has a captured output; trace blocks in the RST are byte-identical to the captures.
5. Fork pushed; branch rebased on current `upstream/develop`; untouched files unchanged (`git diff --stat upstream/develop`).

## HITL approval (exactly once)

Show the user the final title, body, and `git diff --stat`; open the PR only after an explicit go.
Opening an upstream PR is a public act — it is the second and last human decision of the workflow (the
first was the style/example policy).

## Review response protocol

- **Verify before accepting.** Every factual claim in a review comment — "this constraint no longer
  exists", "the entry is suppressed", "the clamp order is X" — is checked against engine code (and on
  the test server when observable) before the reply. Reviewers were right on most claims in #768 and
  wrong on one (a constraint they proposed deleting was still enforced); the reply cited the checker
  source and a measured 30 s vs 0.2 s comparison, and rewrote the sentence from the user's point of view
  instead of deleting it.
- Accept wording suggestions verbatim when they are the house voice (STYLE.md §1) — then sweep the rest
  of the diff for the same pattern and fix all occurrences, en included.
- One commit per review round per file; reply on every thread with what changed and the commit hash;
  rebuild Sphinx and re-run the sweeps.
- Every correction becomes a bullet in STYLE.md §11 in the same session.
- Track the round in the tracking ticket: reviewer, count, verdicts, commits, remaining threads.

## Done

The map's destination for a documentation effort is **merged**, not opened: watch for approvals,
answer late comments, and record merge commit, final head, and the published URLs
(`https://CUBRID.github.io/cubrid-manual/{ko,en}/develop/<merge-sha>/`). Then release the port claim.
