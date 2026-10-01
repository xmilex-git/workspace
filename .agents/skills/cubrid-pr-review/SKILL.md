---
name: cubrid-pr-review
description: "Review a CUBRID pull request together with its JIRA ticket and its two TC PRs, and write a code review report. Use this when the user shares a CUBRID GitHub PR link or asks to review CUBRID code changes."
argument-hint: "<pr-url>"
allowed-tools: Bash(gh *), Bash(git *), Bash(jq *), Bash(scripts/*), Bash(cubrid-jira *), Bash(curl *), Read, Write, Edit, Glob, Grep, Skill, Workflow, mcp__plugin_oh-my-claudecode_t__lsp_diagnostics, mcp__plugin_oh-my-claudecode_t__lsp_diagnostics_directory, mcp__plugin_oh-my-claudecode_t__lsp_hover, mcp__plugin_oh-my-claudecode_t__lsp_goto_definition, mcp__plugin_oh-my-claudecode_t__lsp_find_references, mcp__plugin_oh-my-claudecode_t__lsp_document_symbols
---

# CUBRID PR Reviewer

Review a CUBRID engine pull request as one unit with what it answers to, and produce a concise Korean review report. The unit is:

- the engine PR (the diff and its description),
- its JIRA ticket (the body, the attachments `design.md` / `test.md` / `test_result.md`, and linked issues),
- its two **TC PRs**: the bot-created `tc/pr-<N>` branches in `CUBRID/cubrid-testcases` and `CUBRID/cubrid-testcases-private-ex` (the term is defined in the repo's `CONTEXT.md`).

The report gives three verdicts: findings on the engine PR, the JIRA -> engine PR approval, and the TC approval. CUBRID is a multi-threaded, open-source RDBMS with a large C/C++ codebase, so reviews focus on correctness, memory safety, and concurrency.

## When to Use

- User shares a CUBRID GitHub PR URL (e.g., `https://github.com/CUBRID/cubrid/pull/6950`)
- User says "review this PR", "PR 리뷰", "코드 리뷰 부탁", "리뷰해줘"
- User requests LSP/clangd analysis of PR changes
- Even if the user just pastes a CUBRID PR link without explicit instructions, this skill applies.

## Arguments

- `/cubrid-pr-review <pr-url>` — Review the given PR
- `/cubrid-pr-review` — Ask the user for a PR URL

## Output Format

Write the report to `.claude/review/PR-<NUMBER>/PR-<NUMBER>-report.md` in the repo root (or current directory). The report is **local-only** — never post it to GitHub. A second artifact, `PR-<NUMBER>-comments.md`, holds the post-ready review comments rendered in CUBRID human-reviewer voice (see `voice-guide.md` and Step 6), one section per PR that gets a review (the engine PR and each TC PR). It is generated after the grill and is the only thing meant to be pasted into a GitHub review, and only after explicit user confirmation.

### Language Rules

- **Section headers (`##`)**: English
- **Subsection headers (`###`)**: English (Note: `cubrid-jira-issue-write` uses Korean `###`; for review reports we keep `###` English to match the Findings category names like `Blocking (must fix)`.)
- **Body text**: Korean
- **Tables**: Korean content, English column headers OK
- **Code snippets, function names, file paths**: keep as-is

### Character Restrictions

- **NO emoji** (no checkmarks, crosses, rockets, warnings, etc.) (These examples appear here only as illustrations of what NOT to put in the report.)
- **NO non-BMP Unicode** or special symbols (no Unicode arrows, check/cross marks, stars, bullets like `●`/`■`)
- Use ASCII alternatives: `->` / `<-` instead of arrows, `[x]`/`[ ]` for checkboxes, `*`/`-` for bullets
- **Reason**: matches house style across `cubrid-pr-create` and `cubrid-jira-issue-write`, and avoids encoding issues if the report is later pasted into a ticket comment.

### Length Budget

- **Hard cap: 80 lines** from the title through `## Findings` for typical PRs, **200 lines** for large multi-module PRs. The JIRA -> Engine PR, TC PRs and Runtime Verification sections add their tables on top; the whole report stays under 200 lines.
- If the report would exceed 80 lines, first try to compress: drop low-signal findings, shorten code excerpts to the smallest illustrative span, collapse adjacent items. Going over 96 lines is permitted only when the PR has 5+ Blocking findings.

### Report Template

```markdown
# PR #<NUMBER> 코드 리뷰 보고서

**PR:** [<OWNER>/<REPO>#<NUMBER>](https://github.com/<OWNER>/<REPO>/pull/<NUMBER>)
**제목:** <PR title>
**작성자:** <author>
**HEAD SHA:** `<head_sha>` (develop merge-base `<sha>`)
**JIRA:** <CBRD-XXXXX (type, status)> / 연관: <linked issues, 없으면 없음>
**TC PR:** <CUBRID/cubrid-testcases#N (`tc/pr-<NUMBER>` sha)> / <CUBRID/cubrid-testcases-private-ex#M, 또는 PR 없음 + 변경 여부>
**리뷰 일시:** <today's date>
**리뷰 결정:** <grill에서 정한 PR별 리뷰 이벤트: 엔진 PR, TC PR 각각>

> **TL;DR** (<Verdict>): 1-3 문장으로 결론과 핵심 이슈 1-2개.

## Summary

- **변경 요약**: 한 줄로 PR이 무엇을 바꾸는지
- **주요 이슈**: 가장 중요한 1-2 항목 (없으면 "없음")
- **확인 필요 사항**: 작성자가 확인/응답해야 할 질문 (없으면 "없음")

---

## Findings

<see Findings Rules below. 발견 사항이 전혀 없으면 이 섹션 본문을 `없음` 한 줄로 대체하고 아래 세 subsection은 모두 생략한다. 일부 카테고리만 비어 있다면 채워진 카테고리만 남기고 비어 있는 subsection은 통째로 생략한다.>

### Blocking (must fix)
<버그, 메모리/동시성 안전성 위반 등 머지 전에 반드시 수정되어야 하는 항목.>

### Non-blocking (should consider)
<수정을 권하지만 머지를 막지는 않는 사항.>

### Questions for the author
<작성자에게 확인이 필요한 질문.>

## JIRA -> Engine PR
<Approval Criteria의 JIRA 기준 문장, 항목별 표, 판정 한 줄. JIRA 없으면 섹션 생략.>

## TC PRs
<Approval Criteria의 TC 기준 문장, 시나리오별 표, TC 파일 검토 한두 줄, 판정 한 줄.>

## Runtime Verification
<재사용한 CI 증거와 새로 돌린 실행(빌드 sha와 종류, 테스트케이스 ref, 결과). 새로 돌린 것이 없으면 CI 증거만.>

## Existing Comments
<PR에 달려 있고 작성자/메인테이너 답변이 없는 top-level 코멘트(`in_reply_to_id == null` 인 것 중 author/maintainer 답글이 없는 것)만 짧은 표로 정리. 없으면 섹션 생략.>
```

### Top-of-Report Summary Rules

The `> **TL;DR**` blockquote and `## Summary` block are **required** for every report. They exist so a reader can decide in 20 seconds whether the PR is shippable.

- **TL;DR carries the verdict.** TL;DR 라벨은 `**TL;DR**` 뒤 괄호 안에 `Blocking` / `Non-blocking` / `작성자 확인 필요` 중 하나로 적고, 그 뒤 1-3 문장 평문 한국어로 핵심 이슈를 요약한다. 같은 결론을 Summary에 다시 쓰지 않는다.
- **Summary bullets**: 각 항목 한 줄. 자세한 내용은 `## Findings`에서 풀어 쓴다.
- 사소한 PR(주석/typo)에서도 TL;DR 한 줄은 항상 포함한다.

### Findings Rules

This is the single source of truth for how findings are written. The template above just refers here.

- **Signal over volume.** 발견 사항이 없으면 본문을 `없음` 한 줄로 끝낸다. 채우기용 항목을 만들지 않는다. 30줄짜리 보고서가 300줄짜리 보고서보다 낫다. TL;DR과 Summary는 본문의 **요약**이지 본문 자체가 아니다 — 같은 문장을 그대로 복붙하지 않는다.
- **One sentence per finding** is the default — `파일:라인 + 한 문장 설명 + 근거 코드/진단`. 코드 인용은 1-5줄로 충분하다.
- **Every finding needs evidence**: 코드 스니펫(파일:라인)이나 LSP/clangd 진단. "might be wrong" 같은 모호한 지적은 금지.
- **Only flag issues introduced by this PR.** 이미 존재하던 문제, 이미 다른 코멘트에서 지적된 항목, 수정되지 않은 라인은 제외한다.
- **Skip what CI catches.** 포맷팅, astyle, cppcheck 경고 등 CI가 잡는 항목은 보고하지 않는다.

### Approval Criteria

Single source of truth for the two verdicts besides the findings. Each gets its own table in the report.

**JIRA -> Engine PR.** The PR meets its ticket when all three hold:

1. The JIRA Expected Result holds under the JIRA repro conditions. Cite the evidence: the PR's verification table, `test_result.md`, CI, or a run from Step 3c.
2. Every change `design.md` lists is implemented, or the PR states why it departs.
3. Every open item (`미정`) in `design.md` is resolved, or the PR states why it stays open.

Write one row per Expected Result, design change and open item: `| 항목 | PR 상태 | 판정 |`, where 판정 is `충족`, `부분` (name the finding) or `미충족`. Name every linked issue that describes the same defect, and say whether this PR resolves it. Without a JIRA ticket, omit the section.

**TC.** The scenario list is the rows of the engine PR's verification table plus the scenarios in JIRA `test.md`. A scenario passes when it appears in JIRA `test.md` or is mentioned by either TC PR (in its body or in a changed file). Write one row per scenario: `| 시나리오 | 근거 | 판정 |`.

Then read each TC PR's changed files:
- every changed case has a matching answer,
- header comments carry no `;` (CTP splits statements on it),
- the PR body's pass/fail claims match the evidence.

A TC PR with no change (an empty draft, or a branch the bot left without a PR) needs no review of its own once every scenario passes elsewhere.

### Plain Language

The report is read by the PR author under time pressure — and the author may be a recent hire who hasn't memorized every acronym in the module. Write so a junior engineer who can read C/C++ but hasn't lived in this file can act on the report in one pass.

- **One idea per sentence.** Short, declarative Korean. If a finding needs three sentences, the second and third belong as evidence (code excerpt) — not as more prose.
- **Lead with the defect, then the cause, then the consequence.** "에러 경로에서 `pgbuf_unfix` 누락 -> 페이지 핀이 영구히 잠긴 채 남아 다른 트랜잭션이 해당 페이지를 잡을 수 없음" beats "전반적으로 살펴보니 ... 가능성이 있어 보입니다." The consequence clause is what tells the author *why* this is blocking, not just *what* is wrong.
- **No hedging or filler.** Drop "~인 것 같습니다", "혹시", "전반적으로", "본 리뷰에서는". State the fact: "에러 경로에서 `pgbuf_unfix` 누락."
- **Keep code identifiers as-is.** Function names, file paths, macros stay in their original English form inside backticks. Don't translate them.
- **Show, don't summarize.** When a finding hinges on a few lines of code, paste those lines (1-5 lines) instead of describing them.
- **Gloss CUBRID-internal terms on first use.** On the first mention of an internal-only concept in the report (`OOS`, `pgbuf_*`, `recdes`, `OR_VAR_*`, "6곳 룰", build-mode names like `SERVER_MODE`/`SA_MODE`, latch protocols), add a one-clause aside in parentheses: "`pgbuf_unfix` (페이지 버퍼 핀 해제)", "6곳 룰 (새 에러 코드는 `error_code.h`, `error_code.c` 등 6개 파일을 모두 갱신해야 함)", "`SERVER_MODE` (서버 프로세스 빌드 모드)". After the first gloss, use the term raw. Universal C/DB vocabulary (`malloc`, `mutex`, `assert`) does not need glossing. If `reference.md` already has the long-form explanation, gloss in one clause and link by name.

### Voice: report vs. post-ready comments

Two artifacts, two voices — do not mix them:

- **`PR-<NUMBER>-report.md`** (analysis, local-only): the terse, declarative **Plain Language** style above — defect -> cause -> consequence, no hedging. For the reviewer/maintainer to assess shippability.
- **`PR-<NUMBER>-comments.md`** (post-ready, Step 6): the CUBRID human-reviewer voice defined in **`voice-guide.md`** — question / assertion / suggestion endings (`~지 않나요?`, `~인 것 같습니다`, `~는 어떨까요?`), `NIT:` for minor items, identifiers kept English, no AI tells / emoji / English verdict labels. The hedged tone that Plain Language bans in the report is *expected* here, because these are the words the author actually reads.

`voice-guide.md` is the single source of truth for comment voice. When the two conflict, Plain Language governs the report and `voice-guide.md` governs the comments.

## Execution Steps

### Step 1: Setup

Parse the PR URL with the helper script and capture metadata in one shot:

```bash
scripts/check-prereqs.sh "$PR_URL"
```

The script prints JSON with `owner`, `repo`, `number`, `head_sha`, `base_ref`, `title`, `body`, `author`, `state`, `draft`. If it exits non-zero, surface the message and stop. If the PR is not open, or is marked draft, warn the user once and ask whether to proceed before continuing.

### Step 2: Gather Context (parallel)

Run these in parallel. Downloads and scratch files go under `.git_ignored_dir/scratch/pr<NUMBER>/` of the tooling repo, never `/tmp`.

1. **PR diff:** `gh pr diff <NUMBER> -R <OWNER>/<REPO>`. If `gh pr diff` returns empty or fails, surface the error and stop — there is nothing to review.
2. **Existing PR comments**:
   ```bash
   gh api "repos/<OWNER>/<REPO>/pulls/<NUMBER>/comments" --jq '.[] | {id, user: .user.login, path, line: .original_line, in_reply_to_id, body}'
   gh api "repos/<OWNER>/<REPO>/issues/<NUMBER>/comments" --jq '.[] | {id, user: .user.login, body}'
   ```
3. **JIRA** (if the PR title contains `CBRD-XXXXX`): invoke `/jira CBRD-XXXXX` for the ticket body and its links. Download its attachments (`design.md`, `test.md`, `test_result.md`, repro scripts) with `cubrid-jira attachment CBRD-XXXXX --out .git_ignored_dir/scratch/pr<NUMBER>/jira-CBRD-XXXXX`. Do the same for each linked issue that may describe the same defect.
4. **TC PRs**: for each of `CUBRID/cubrid-testcases` and `CUBRID/cubrid-testcases-private-ex`:
   ```bash
   gh pr list -R <TC_REPO> --head tc/pr-<NUMBER> --state all --json number,title,state,isDraft,headRefOid,url
   gh pr view <TC_PR> -R <TC_REPO> --json body,files,commits,comments,reviews
   gh pr diff <TC_PR> -R <TC_REPO>
   ```
   With no PR, compare the branch: `gh api repos/<TC_REPO>/compare/develop...tc/pr-<NUMBER> --jq '{ahead_by, files: [.files[].filename]}'`. The engine PR's "TC Merge Gate" bot comment also states each TC branch's state.
5. **CI evidence**: `gh pr checks <NUMBER> -R <OWNER>/<REPO>`. Per-case results live on the gha-ci artifact server (`runtime.md`).
6. **Read `reference.md`** (sibling file in this skill's directory) for CUBRID-specific review knowledge: error-code six-place rule, memory/error-handling conventions, lock/page-buffer/WAL/MVCC protocols, build-mode guards, key data structures, false-positive guidance. If `reference.md` is missing on this checkout, warn the user once and proceed using only the review categories listed in Step 3 below — do not invent CUBRID-specific rules.
7. **Read any CLAUDE.md / AGENTS.md** in directories containing changed files. Use Glob to walk ancestor directories of each changed file looking for these context files.
8. **Read `voice-guide.md`** (sibling file) for the CUBRID human-reviewer tone applied when rendering post-ready comments in Step 6. If `voice-guide.md` is missing, render comments in the report's Plain Language style instead and note the fallback once.

### Step 3: Review

Read the **full functions** surrounding each diff hunk, not just the hunk. Trace call chains where it matters. Aim for **signal**: prefer reading one suspicious function carefully over skimming ten safe ones. Investigate broadly, report narrowly — deep reading is for filtering findings, not justifying long reports.

Focus on these high-signal categories for CUBRID. One sentence each — the detailed sub-checklists live in `reference.md`:

- **Logic & correctness**: did the change introduce a wrong branch, a missing error path, or an uninitialized read?
- **Memory safety**: are CUBRID's allocator/free-and-init conventions followed and are all error paths leak-free?
- **Concurrency & thread safety**: is shared state protected, and is lock/latch ordering preserved across all paths?
- **Architecture vs JIRA intent**: does the implementation match the ticket's stated goal, and are build-mode guards (`SERVER_MODE`/`SA_MODE`/`CS_MODE`) and updated callers correct?
- **Claims vs code**: every claim the PR description makes about coverage ("all paths", "every decision", "no effect on X") is checked against the code, and a false one becomes a finding.

If the diff touches the SQL parser, broker protocol, or CCI client interface, also check buffer/integer overflow and unchecked input. Skip generic security checklists otherwise.

Fill the Approval Criteria tables while reading. The JIRA rows come from `design.md` and `test.md` read against the diff; the TC rows come from `test.md` and the TC PRs.

**LSP analysis (optional).** If `compile_commands.json` is available, run `lsp_diagnostics` on changed files for clangd warnings on changed lines, `lsp_hover`/`lsp_goto_definition` on suspicious types, and `lsp_find_references` if a function signature changed. Skip silently if LSP is unavailable.

If `reference.md` is present and flags a rule (e.g., new error code -> 6 places), don't restate the rule body — link to it by name and point to the file:line that needs updating.

### Step 3b: Sanity Check (mandatory)

After the main review pass, run a focused sanity scan over the diff yourself. This repository keeps source reading with the lead (the division of labor in its CLAUDE.md), so the scan is not delegated. It is mandatory and cannot be skipped — it catches convention violations that `codestyle.sh` and CI do not enforce. Inputs: the full PR diff, the `reference.md` "Comment & Convention Hygiene" section, and any `CLAUDE.md` from directories of changed files.

The scan checks **only** these categories (logic/concurrency/memory belong to the main review):

1. **Stale file:line references in comments** — any new comment that pairs a filename with a line number. Flag with: "`<file>:<line>` — 주석에 파일명+라인번호 참조 금지. 심볼 이름으로 교체 필요."
2. **Incomprehensible comments** — comments that only make sense at write-time ("added for the refactor", "fixes last week's bug") or require opening another file to understand.
3. **License header on new files** — every new `.c`/`.h`/`.cpp`/`.hpp` file must have the standard license header.
4. **Commented-out code blocks** — `#if 0` or large `/* ... */` dead code blocks in new code.
5. **`#include` order violations** — `config.h` must come first, then system, then CUBRID headers.
6. **Magic numbers** — bare numeric literals (other than 0, 1, -1, NULL) without a named constant.

Merge its hits (file:line + one sentence) into the main report's Findings section under the appropriate severity:
- Stale file:line refs and incomprehensible comments -> **Non-blocking (should consider)**
- Missing license header -> **Blocking (must fix)**
- Commented-out code, include order, magic numbers -> **Non-blocking (should consider)**

With no hits, no sanity items appear in the report.

### Step 3c: Runtime Verification (permitted)

Building CUBRID and running TCs for the review is permitted without asking. That covers the PR head, its develop merge-base, CI build tarballs, the TC PRs' cases, a linked ticket's repro as a review-only case, and the CTP dirs the PR claims to fix. Posting to GitHub or JIRA still needs the user's confirmation.

Reuse evidence before producing it: CI statuses and the gha-ci artifact server answer most "does it pass" questions. Run only what that evidence lacks, typically:
- fail-before on the merge-base and pass-after on the head, each on a fresh server,
- a linked ticket's repro,
- a scenario the PR claims but CI does not cover.

The runs follow the repository's execution rules: runtime work goes to the delegated worker that this repo's CLAUDE.md names, and every CTP run goes through `just ctp` containers. Recipes, artifact-server paths and cleanup are in `runtime.md`.

Completion: every Expected Result row and every TC scenario row has evidence (CI, the author's attached result, or a run), and the Runtime Verification section names each source with its build sha, build type and testcase ref.

### Step 4: Filter

Drop findings that are:

- **Pre-existing** (not introduced by this PR)
- **Already raised** in existing PR comments
- **Stylistic** (formatting, naming) unless CLAUDE.md mandates it — but **never drop Step 3b sanity findings** (comment hygiene, license headers, include order, etc.); those exist precisely because CI does not catch them
- **On unmodified lines**
- **Out of the PR's stated scope** — don't critique the design of code the PR didn't intend to change, even if the diff exposed it

Every surviving finding needs a code snippet or diagnostic as evidence.

### Step 5: Write the Report

1. **Draft the TL;DR + Summary first.** Write the verdict label and conclusion before the body — this forces a clear stance and reveals whether the rest of the report supports it.
2. **Write Findings tightly.** One sentence per item. Group as Blocking / Non-blocking / Questions, omitting any subsection that has no items. If no category has any items, replace the section body with a single `없음` line and omit all three subsections.
3. **Fill JIRA -> Engine PR, TC PRs and Runtime Verification** per Approval Criteria and Step 3c. Omit JIRA -> Engine PR only when there is no JIRA ticket; add Existing Comments only if useful.
4. **Save** to `PR-<NUMBER>-report.md` in the repo root (or cwd).
5. **Print** four things so the user can sanity-check the call at a glance: (1) the saved file path, (2) the verdict label extracted from the TL;DR (`Blocking` / `Non-blocking` / `작성자 확인 필요`), (3) the TL;DR sentence(s) without the label prefix, (4) the JIRA and TC verdicts.

## Example Output

A short finished report looks like this — use it as a shape anchor, not a template to fill out verbatim. The example below is about 40 lines, well under half the budget; for a typical PR this is plenty.

```markdown
# PR #6950 코드 리뷰 보고서

**PR:** [CUBRID/CUBRID#6950](https://github.com/CUBRID/CUBRID/pull/6950)
**제목:** [CBRD-26583] Re-enable OOS OID replacement in heap records
**작성자:** xmilex-git
**HEAD SHA:** `abc1234` (develop merge-base `def5678`)
**JIRA:** CBRD-26583 (Improve, Confirmed) / 연관: 없음
**TC PR:** CUBRID/cubrid-testcases#3001 (`tc/pr-6950` `aaa1111`) / cubrid-testcases-private-ex#4001 (빈 draft)
**리뷰 일시:** 2026-05-06
**리뷰 결정:** 엔진 PR Request changes / TC PR #3001 Approve

> **TL;DR** (Blocking): `heap_record_replace_oos_oids` 에러 경로에서 `pgbuf_unfix` 누락으로 페이지 핀 누수 가능. 해당 한 곳만 고치면 머지 가능.

## Summary

- **변경 요약**: heap 레코드의 OOS OID 치환 로직을 `feat/oos`에 다시 활성화
- **주요 이슈**: `heap_file.c:12345` 에러 경로 페이지 핀 누수
- **확인 필요 사항**: 없음

---

## Findings

### Blocking (must fix)
- `src/storage/heap_file.c:12345` — `er_set` 후 `goto exit` 전에 `pgbuf_unfix(thread_p, page_p)` 누락. 해당 함수 진입에서 `pgbuf_fix` 했으므로 모든 종료 경로에서 unfix 필요. 근거: 같은 함수 line 12302의 정상 종료 경로에는 unfix 존재.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result (OOS 레코드 갱신 후 OID 일치) | test_result.md T1 | 충족 |
| design 변경 1: 치환 재활성화 | 구현, 에러 경로 누수 | 부분 (Blocking 1) |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| T1 OOS 레코드 갱신 | test.md T1, #3001 | 통과 |

## Runtime Verification

- CI: build/sql/medium 통과(run 123), `cbrd_26583.sql` ok. 새로 돌린 실행 없음.
```

(Existing Comments was omitted because no unresolved top-level comments existed. `Non-blocking` and `Questions for the author` subsections are also omitted because they had no items.)

## Mandatory: Grill the Review (`grilling` + `domain-modeling`)

Every review report goes through a grill with the user before anything is rendered for posting. Single-pass reviews drift toward weak evidence ("might be wrong" hedges), pre-existing-issue leakage, mis-scoped findings, and verdicts that don't match the findings. The grill is where the reviewer's decisions get made.

Run it by invoking two skills with the Skill tool: `grilling` (the interview loop) and `domain-modeling` (the glossary discipline). `grill-with-docs` composes the same pair, but it is user-invoked only (`disable-model-invocation`), so this skill calls the two directly.

- **Design tree**: the reviewer's decisions.
  - For each finding: keep, drop, severity, wording.
  - The JIRA -> Engine PR verdict and the TC verdict.
  - The review event for the engine PR and for each TC PR (Approve / Comment / Request changes).
  - What gets posted.
- **Rounds**: ask each round's frontier at once, numbered, in Korean. Give each question a recommended answer and the SQL or code it hinges on. A verdict question waits until the findings it depends on are settled.
- **Facts are yours**: what the code does, what CI showed, whether a scenario reproduces. Look it up or run it (Step 3c) instead of asking.
- **domain-modeling**: when a round settles a term (a CUBRID-internal concept the report glosses, or review vocabulary such as TC PR), write it to the repo's `CONTEXT.md` at once. That file is a glossary only.
- **Review angle** (check every round):
  - each finding has file:line evidence with no hedging,
  - nothing pre-existing, CI-caught or out of scope leaked in,
  - the TL;DR label matches the findings,
  - both approval tables have evidence in every row,
  - the length budget holds,
  - no emoji or non-BMP characters,
  - every CUBRID-internal term is glossed on first use,
  - every blocking finding states defect -> cause -> impact.

Completion: the frontier is empty and the user has confirmed. Then revise the report in place, drop what the grill dropped, and fill the `**리뷰 결정:**` header line. The only skip is the user saying "skip grill" (or "no grill", "just push it") in the message that triggered this skill.

## Step 6: Render Post-Ready Comments (voice-guide)

After the grill finalizes `PR-<NUMBER>-report.md`, convert the surviving findings into review comments a CUBRID maintainer could paste as-is, following `voice-guide.md`. Save them to `PR-<NUMBER>-comments.md` in the same `PR-<NUMBER>/` directory, with one section per PR that gets a review (the engine PR and each TC PR). Put the review event (Approve / Comment / Request changes) above each section's bodies as metadata, never inside a body. Do **not** auto-post to GitHub — posting is outward-facing and requires explicit user confirmation. After saving, print the comments file path.

Mapping from report to comments:

- Each **Blocking / Question** finding -> one comment. Lead with `file:line` (inline target), then a 1-3 line body ending in a human reviewer ending: a real bug is short and assertive (`~해야 하는 것으로 보입니다`), a doubt is a question (`~지 않나요?`), a proposal is a suggestion (`~는 어떨까요?`). Cite an existing function / macro / pattern instead of explaining abstractly; attach a short reproducible SQL or a ` ```suggestion ` block when it helps.
- Each **Non-blocking** finding -> a `NIT:` comment (`NIT:` is the only severity label allowed in comment bodies).
- **Existing Comments** the report listed as unresolved: do **not** re-post a near-duplicate. Note in `PR-<NUMBER>-comments.md` that they should be answered as a reply on the existing thread instead.
- Optional top-level comment: one short paragraph summarizing the PR in plain human tone (no `##` headers, no verdict label, no lane / meta terms), followed by `확인 부탁드립니다` and `추가로 논의가 필요해 보이는 항목` groupings for documentation / scope items. Requests about the JIRA ticket (linking a duplicate, recording a regression cause) go here as asks to the author; this skill never writes to JIRA.

Before saving, run the `voice-guide.md` Section 7 self-checklist (no English headers in bodies, no `Why:` / `Fix:` labels, every comment ends in a human ending, identifiers English, only `NIT:` as a label, no emoji / `LGTM` / `Strongly recommend`, no lane / meta terms, no comment body over 6 lines).

Posting, once the user confirms: one review per PR, with `commit_id` set to that PR's head SHA. Each inline `line` must sit inside a diff hunk of that PR (`side: "RIGHT"` for added lines). Write the payload under `.git_ignored_dir/scratch/pr<NUMBER>/`:

```bash
gh api -X POST repos/<OWNER>/<REPO>/pulls/<N>/reviews --input <payload.json>
# payload: {"commit_id": "<head sha>", "event": "APPROVE|COMMENT|REQUEST_CHANGES", "body": "<top-level>",
#           "comments": [{"path": "<file>", "line": <n>, "side": "RIGHT", "body": "<comment>"}]}
```
