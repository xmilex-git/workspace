---
name: cubrid-pr-create
description: Open a GitHub pull request for the CUBRID project. Use this when the user wants to create a PR for their CUBRID changes.
---

# CUBRID PR Creator

Create GitHub pull requests for the CUBRID project in the author's hand-written style: concise, factual, no filler.

## When to Use

- User says "create pr", "make pr", "PR 만들어", "PR 올려", "풀리퀘"
- User wants to push changes and open a PR against CUBRID/CUBRID or a fork

## Arguments

- `/cubrid-pr-create CBRD-26583` — Use this JIRA ticket number
- `/cubrid-pr-create CBRD-26583 feat/oos` — Ticket + base branch
- `/cubrid-pr-create` — Interactive: detect from branch name or ask

## Conventions

### Title

```
[CBRD-XXXXX] <JIRA ticket title, verbatim>
```

- JIRA ticket number **required**. Extract from branch name (e.g., `cbrd-26583-oos-compact` → `CBRD-26583`) or ask.
- Description = the **JIRA ticket title as-is**. Do not compose a new one. Get it via `/jira CBRD-XXXXX`; if the ticket cannot be fetched, ask the user for the ticket title.
- An existing JIRA ticket keeps its title, Korean or not: the PR title is `[CBRD-XXXXX] <current JIRA title>` verbatim, and no replacement title is offered unless the user asks for a rename. (P1)

### Body

**Read [tone_guide.md](./tone_guide.md) before drafting. It is the single source of truth for body style.** In short:

- JIRA link (`http://jira.cubrid.org/browse/CBRD-XXXXX`) at the very top, then a one-sentence summary ("~하는 PR입니다.") when Purpose runs two paragraphs or more.
- Write for a reviewer who has never seen this code: normal behavior → the defect → what the user sees (debug / release), then the fix. Short sentences, one fact each, 합니다체, plain Korean verbs, every term glossed at first use, every number with its unit/default/source.
- `### Purpose` — always. Scale with the change: one sentence for a one-function fix, up to three paragraphs plus text diagrams (annotated code excerpt, `└ ├ │` call tree) for a mechanism-level fix.
- `### Implementation` — numbered by concern (not by file), each with a bold one-line heading, "what + why", and a note on how untouched paths behave. Omit for one-or-two-function fixes.
- `### Remarks` — bullets, when any apply: 동작 변화 (what is visible and what is unchanged), TODO with its follow-up issue, review-aid commits to drop before merge.
- A 6-line body with a one-sentence Purpose is a normal, correct PR. Never pad.

## Execution Steps

### Step 1: Gather Context

Run in parallel:

1. `git status` — check for uncommitted changes
2. `git branch -vv` — current branch and tracking info
3. `git remote -v` — available remotes

If there are uncommitted changes, warn the user and ask whether to proceed or commit first.

### Step 2: Determine PR Parameters

1. **JIRA ticket**: from arguments, branch name (`cbrd-XXXXX`/`CBRD-XXXXX`), or ask.
2. **Base branch**: if not specified, detect:
   - `feat/oos*` branches → base `feat/oos`
   - `CBRD-*` branches → base `develop`
   - `cubvec/*` branches → base `cubvec/cubvec`
   - Otherwise ask.
3. **Target repo**: default `CUBRID/CUBRID`.
4. **Source**: user's fork remote (typically `xmilex` for `xmilex-git/cubrid`). Head ref format: `<github-user>:<branch>`.

### Step 3: Analyze Changes

1. `git fetch <upstream-remote> <base-branch>`
2. `git log --oneline <upstream>/<base>..HEAD`
3. `git diff <upstream>/<base>...HEAD --stat`, then read the full diff.
4. If a JIRA ticket was identified, fetch context with `/jira CBRD-XXXXX`.

### Step 4: Draft PR Content

1. Read [tone_guide.md](./tone_guide.md) and match the example closest in scale to this diff.
2. Draft title + body. Write only what the diff supports — nothing speculative.
3. Run the tone_guide self-check.
4. **Show the draft to the user and get confirmation before creating.** Single pass; revise only on user feedback. Run `/grill-with-docs` only if the user explicitly asks for it.

### Step 5: Push and Create PR

Run every command of this step inside the engine worktree (`cd <worktree>`; `.github/workflows/codestyle.sh` is the engine repo's script). `<pushed-base>` is the last pushed head, or for a first push `git merge-base HEAD origin/develop`. Run the formatter before showing the draft (Step 4), so the body describes the commits that will be pushed.

0. Before every push to the engine branch, run CI's formatter over every changed source file and commit its diff: `export PATH=/etc/dev4_skeleton/install/bin:$PATH` (GNU indent 2.2.11, as in CI), then `for f in $(git diff --name-only <pushed-base> HEAD -- 'src/*.c' 'src/*.h' 'src/*.cpp' 'src/*.hpp'); do bash .github/workflows/codestyle.sh $f; done` and `git diff --stat` must be empty (a whitespace-only commit needs no build); in zsh loop over `$(cat list)` or literal names, never `for f in $F`, and treat "no `file~` backups appeared" as the formatter not having run. (P2)
   C++ constructs inside a `.c` file (`template <...>`, `if constexpr`, `std::index_sequence`) make GNU indent lose its declaration state and rewrite every later function, so exactly that block is wrapped in `/* *INDENT-OFF* */` … `/* *INDENT-ON* */` (as `object_primitive.c` does), checked with `indent -l120 -lc120 -st <file>` against the file (never in place) and compared with the develop base to tell the PR's hunks from pre-existing ones, in its own whitespace-only commit. (P3)
1. Push: `git push <fork-remote> <branch> -u` (skip if already pushed). The push target is the user's fork, never `CUBRID/cubrid` directly.
2. Create:
   ```bash
   gh pr create --repo CUBRID/CUBRID \
     --draft \
     --base <base-branch> \
     --head <user>:<branch> \
     --assignee xmilex-git \
     --title "[CBRD-XXXXX] Title" \
     --body "$(cat <<'EOF'
   http://jira.cubrid.org/browse/CBRD-XXXXX

   <한 문장 요약 (Purpose가 두 문단 이상일 때)>

   ### Purpose

   한국어 산문...
   EOF
   )"
   ```
3. Print the resulting PR URL.

The PRs behind each `(P<n>)` are in `PITFALLS.md`; a new lesson goes there as a case under its rule, or as a new rule added to both files in one commit.

## Tips

- If a PR already exists for the branch, show it instead of creating a duplicate.
- For multi-commit PRs, summarize the overall change rather than listing each commit message.
- Always use heredoc for the body to handle multi-line Korean text correctly.
- Size reference corpus: [`pr-corpus/`](./pr-corpus/) — 76 hand-written PRs (#4432–#6911), one file per PR with diff summary + verbatim body. Use it to judge how long a body of a given diff size should be; for sentence style and structure, tone_guide.md (standard: PR #8096) wins.
