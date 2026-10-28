---
name: cubrid-jira-issue-write
description: Write a concise, paste-ready CUBRID JIRA issue body in Korean using JIRA wiki markup, plus the design.md/test.md attachments required by company policy at work completion. Uses the official template for Correct Error, Improve/Development/Refactoring, or Internal Management work and keeps developer-only analysis out of the issue body. Use also when a JIRA body already exists and only the design.md/test.md attachments are needed.
---

# CUBRID JIRA Issue Writer

Write a CUBRID JIRA issue that QA, decision-makers, and developers can understand without reading a code-level design document.

Read [`tone_guide.md`](./tone_guide.md) before drafting. It is authoritative for wording, detail level, and JIRA wiki markup. In short: 합니다체; explain normal behavior before the defect or change; gloss every term at first use; give every number its unit, default, or source; short sentences with a real actor as subject; no evaluative words, labels, or closing summaries.

## Output

- Save the paste-ready body under `.git_ignored_dir/jira/<TICKET_KEY>/CBRD-XXXXX-short-slug.md`.
- Use the ticket key from the argument or current branch. Use `CBRD-XXXXX` for an unfiled draft.
- The file extension is `.md`, but its contents are JIRA wiki markup, not Markdown.
- Write only the JIRA Description field body in the file. Do not put the proposed Summary/title in it.
- In the completion message, report the file path, issue type, proposed Summary, and whether `design.md`/`test.md` were written or skipped (with the reason) separately.
- If `.git_ignored_dir/jira/` does not exist, stop and ask the user to create it. The per-ticket directory may be created as needed.
- Nothing is created, commented, attached or linked in JIRA unless the user asked for that specific item; a defect found along the way goes to this repo's own tracker (`gh issue create` on xmilex-git/workspace) and the report names which tracker was used; up to the ask, the work stops at the draft body under `.git_ignored_dir/jira/<KEY>/`. (P1)

The tickets behind each `(P<n>)` are in `PITFALLS.md`; a new lesson goes there as a case under its rule, or as a new rule added to both files in one commit.

## Attachments-only mode

If the JIRA issue already has a Description body — the user says so, provides it, or existing JIRA context shows it — do not draft or rewrite the body. Write only `design.md` and `test.md` per the policy below, using the existing body and available material as input.

## Required attachments: design.md and test.md

Company policy: at work completion, `design.md` and `test.md` must be attached to the JIRA issue.

- Write both files to `.git_ignored_dir/jira/<TICKET_KEY>/design.md` and `.git_ignored_dir/jira/<TICKET_KEY>/test.md`.
- Follow the fixed templates in [`attachment_templates.md`](./attachment_templates.md) exactly. Do not invent alternative section layouts; the uniform template is deliberate token optimization.
- A design document for this user spells names out (`DOMAIN_PLAN`, `RESOLVED_DOMAIN`, never `dplan`/`dgate`), reuses the code's dominant words and file prefixes (`resolve`, `qexec_`, `scan_`, `stx_build_`), adds no unit-test section, puts every execution-time decision before `qexec_execute_mainblock` and treats mainblock/scan code as read-only, shows where `qexec_execute_mainblock` sits in the XASL tree with the traversal explicit, is one self-contained `.md` in the repo sent with SendUserFile, and answers each finding of the user's own static review in the next version. (P4)
- Contents are Markdown, in Korean, point-focused: the consumer on the other side is also an LLM. `design.md` carries the code-level design detail banned from the JIRA body. `test.md` is a QA TC authoring guide for `cubrid-testcases`/`cubrid-testcases-private-ex` — scenarios and pass/fail points, never internal verification records (measurement campaigns, sanitizer/diagnostic builds).
- Skip both files only when, in your judgment, the design is still undecided AND the implementation approach is undecided. If either is settled, write both files. When skipping, state the skip and its reason in the completion message.
- Attach the written files to the issue via the JIRA REST API (credentials in `~/.config/cubrid-skills/jira.env`):

  ```bash
  source ~/.config/cubrid-skills/jira.env
  curl -sS -u "$JIRA_USERNAME:$JIRA_PASSWORD" -X POST \
    -H "X-Atlassian-Token: no-check" \
    -F "file=@.git_ignored_dir/jira/<TICKET_KEY>/design.md" \
    -F "file=@.git_ignored_dir/jira/<TICKET_KEY>/test.md" \
    "$JIRA_BASE_URL/rest/api/2/issue/<TICKET_KEY>/attachments"
  ```

  Verify with `GET .../issue/<TICKET_KEY>?fields=attachment`. For an unfiled draft (`CBRD-XXXXX`), skip the upload and tell the user to attach after filing. The upload itself is a JIRA write and happens only under P1's per-item ask.

## Choose the template by work, not hierarchy

Choose the template that matches the actual work. A Sub-task inherits the template for its work:

- Bug or incorrect behavior: `Correct Error`
- Feature, performance improvement, or refactoring: `Improve Function/Performance, Development Subject, Refactoring`
- Internal administration or a Task that fits neither category: `Internal Management`

Ask only when the issue type cannot be determined from the conversation, source material, or existing JIRA context.

## Templates

Use the labels and order below. Mark section labels with JIRA bold syntax such as `*Description*`.

### Correct Error

```text
*Description*

*Test Build*

*Repro*

*Expected Result*

*Actual Result*

*Additional Information*
```

- `Description`: Describe the failure situation and its visible impact in one to three short paragraphs. Do not include root-cause analysis, call paths, backtraces, or a proposed code change.
- `Test Build`: Record the exact affected build through patch/revision and commit, for example `CUBRID-11.0.0.0248-b53ae4a` or the exact `cubrid_rel` output. Add the OS only when useful. Never invent missing build data.
- `Repro`: Give the smallest complete copy-paste procedure that reproduces the problem. It may be long when the required schema, SQL, command, or attached program is long. Do not add the developer's broader regression or debugging plan.
- `Expected Result`: State the expected result briefly.
- `Actual Result`: State the observed result and enough comparison data to recognize the failure. Keep implementation analysis out.
- `Additional Information`: Include only material that helps understand or investigate the bug. Omit this section when there is nothing useful to add.

### Improve Function/Performance, Development Subject, Refactoring

```text
*Description*

*Specification Changes*

*Implementation*

*Acceptance Criteria*

*Definition of done*
```

- `Description`: Explain the current limitation, its impact, and the intended improvement in one to three short paragraphs.
- `Specification Changes`: Describe user-visible behavior, supported and excluded cases, settings, compatibility, and other facts needed by QA or manual writers. Use `N/A` when no specification changes exist. There is no fixed length limit when a support matrix, SQL example, or constraint list is necessary.
- `Implementation`: State only the central implementation concept and affected scope in one to three short paragraphs. Do not enumerate function-by-function flow, data structures, file/line changes, pseudocode, internal error paths, or a detailed test design.
- `Acceptance Criteria`: Give at most three observable results that determine whether the work is acceptable. Do not repeat the specification section.
- `Definition of done`: Normally include only `* Acceptance Criteria 만족` and, when applicable, `* QA 테스트 통과` (list items end in noun form; prose is 합니다체, see `tone_guide.md`).

Never invent a performance target. Use a number only when the user or an authoritative source supplied the target and its basis. If a numeric target is essential but missing, ask the user.

### Internal Management

```text
*Description*
```

Explain the purpose and scope in one to three short paragraphs. Do not manufacture specification, implementation, or verification sections for internal work.

## Supporting analysis

Do not create an analysis attachment by default. `design.md` and `test.md` cover design and verification detail; create an additional analysis attachment only when:

- the user requests it;
- existing backtraces, call paths, root-cause analysis, or detailed verification records are worth preserving and do not fit the `design.md`/`test.md` templates; or
- omitting the evidence would leave the responsible developer without necessary context.

Keep it in the ticket directory and reference it briefly from `Additional Information`. Attachments may contain developer-only detail that does not belong in the JIRA body.

## Workflow

0. For a new ticket, only the title is settled with the user first (English, short, result-style — "after ALTER … rows are missing and rebuild makes segfault"; a regression as `[Regression][<feature>] <result clause>`; drivers `[JDBC] ` / `[CCI] ` in APIS), a read-only JQL duplicate search runs before drafting, and every build cited in *Test Build* or an evidence table is a develop build (a gha-ci archive `builds/develop/<sha>/{debug,release}/CUBRID.tar.gz`, stamp from `strings lib/libcubrid.so.11.5`), never a branch install. (P2) Several tickets at once: one subagent per issue, each with its own draft dir under `.git_ignored_dir/jira/`; a workspace issue whose defect is now in JIRA is closed with a comment carrying the key.
1. Resolve the ticket key and issue type. If the issue body already exists, switch to attachments-only mode.
2. Read relevant user material, source code, analysis, and existing JIRA context. Prefer checking available evidence over asking the user.
3. Ask only for missing facts that materially affect correctness, such as the issue type, exact repro, changed specification, or an agreed performance target.
4. Draft the minimum complete body using the appropriate template and `tone_guide.md` (skip in attachments-only mode).
5. Decide whether the design and implementation approach are settled. If settled, write `design.md` and `test.md` from `attachment_templates.md`; otherwise skip both and note the reason.
6. Save the body and any justified attachment, then (under P1's ask) upload `design.md`/`test.md` to the issue via the REST API and verify the attachment list.
   Filing uses the proven payload shape (project CBRD; issuetype ids 40 Correct Error, 41 Improve, 47 Development Subject, 126 Internal Management, 171 Refactoring, 10500 Task, 5 Sub-task with `"parent"`; `versions` = Affects Version/s; `customfield_210565` QA Scenario "Not Yet"/"Required"; assignee as the user names it, `ilhansong` only by default), credentials from `~/.config/cubrid-skills/jira.env` (`JIRA_BASE_URL`/`JIRA_USERNAME`/`JIRA_PASSWORD`) or `CUBRID_JIRA_USER`/`CUBRID_JIRA_PASSWORD` passed to curl on stdin (`printf 'user = "%s:%s"\n' … | curl -K -`), never on argv; links via `/rest/api/2/issueLink` with `inwardIssue` = the issue whose page shows the type's outward text (a defect D caused by feature F: `{"type":{"name":"Regress"},"inwardIssue":D,"outwardIssue":F}`), read back on both issues; attachments replaced by POST then `cmp` then DELETE of the old id; the body rendered before filing with POST `/rest/api/1.0/render` (`rendererType: atlassian-wiki-renderer`) to check `code-sql` panels and the `emoticon` count, escaping prose `\{1, 2\}` and `\(*)`. (P3) `cubrid-jira link --type Relates|Blocks …` covers the simple links; `cubrid-jira update/comment-update` cannot upload attachments. APIS (driver) tickets use the same ids and template with the driver's unreleased version (JDBC-11.4.0, CCI-11.3.0) or `guava`.
7. Verify the structure, JIRA markup, verbosity, template conformance of `design.md`/`test.md`, and absence of invented details before reporting the result.

`grill-with-docs` is not mandatory. Use it only when the user requests it.
