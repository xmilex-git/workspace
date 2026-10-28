# PITFALLS — the rules in SKILL.md and the tickets that produced them

Each `P<n>` is one rule. The **Rule** line is the exact sentence SKILL.md carries at the step named in
**Applies at**; keep the two byte-identical. **Source** is where the lesson lived before it was folded
in here (auto-memory slugs are deleted once absorbed; kept for traceability only).

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule only when no rule fits — then add the sentence to SKILL.md in the same commit.

### P1 — nothing reaches JIRA without a per-item ask
- Rule: Nothing is created, commented, attached or linked in JIRA unless the user asked for that specific item; a defect found along the way goes to this repo's own tracker (`gh issue create` on xmilex-git/workspace) and the report names which tracker was used; up to the ask, the work stops at the draft body under `.git_ignored_dir/jira/<KEY>/`.
- Applies at: Output
- Case (2026-09-24, #340): about to file the D7 develop defect in JIRA; the user: "무슨이슈를 올림?? jira에 올리면안되는건알지??". When the user does ask ("내 jira 이슈에 분석내용 comment로 올려", CBRD-27510), the comment matches the body's style — plain Korean, no campaign D-numbers or workspace issue numbers — and goes through `cubrid-jira comment <KEY> --body-file F --from jira` (dry run first, then `--yes`).
- Source: memory:no-jira-posting

### P2 — titles are decided with the user; evidence is develop's
- Rule: For a new ticket, only the title is settled with the user first (English, short, result-style — "after ALTER … rows are missing and rebuild makes segfault"; a regression as `[Regression][<feature>] <result clause>`; drivers `[JDBC] ` / `[CCI] ` in APIS), a read-only JQL duplicate search runs before drafting, and every build cited in *Test Build* or an evidence table is a develop build (a gha-ci archive `builds/develop/<sha>/{debug,release}/CUBRID.tar.gz`, stamp from `strings lib/libcubrid.so.11.5`), never a branch install.
- Applies at: Workflow
- Case (2026-09-28, release triage filing): "나랑 제목만 정하고" — body writing and the upload were handed to one subagent per issue, each with its own draft dir; "제목 초안 빨리 들고와". The JQL search found #350 = CBRD-27492 and #326 = CBRD-27482 already filed.
- Case (2026-10-04, mid-draft): "빌드는 브랜치말고 develop 빌드로만 기록해야해." — a defect reported against a branch build invites "is it your PR?"; the stamp number is not the first-parent commit count.
- Case (2026-10-08, CBRD-27590/27591): "그 cached_scan 기능의 회귀라는 점을 제목에 표시하고, 좀 더 짧게"; Affects Version/s (`versions` in REST) lists every line that reproduced, and *Test Build* lists every build tested, non-reproducing ones included.
- Source: memory:jira-filing-workflow, memory:jira-evidence-develop-builds-only

### P3 — the REST facts
- Rule: Filing uses the proven payload shape (project CBRD; issuetype ids 40 Correct Error, 41 Improve, 47 Development Subject, 126 Internal Management, 171 Refactoring, 10500 Task, 5 Sub-task with `"parent"`; `versions` = Affects Version/s; `customfield_210565` QA Scenario "Not Yet"/"Required"; assignee as the user names it, `ilhansong` only by default), credentials from `~/.config/cubrid-skills/jira.env` (`JIRA_BASE_URL`/`JIRA_USERNAME`/`JIRA_PASSWORD`) or `CUBRID_JIRA_USER`/`CUBRID_JIRA_PASSWORD` passed to curl on stdin (`printf 'user = "%s:%s"\n' … | curl -K -`), never on argv; links via `/rest/api/2/issueLink` with `inwardIssue` = the issue whose page shows the type's outward text (a defect D caused by feature F: `{"type":{"name":"Regress"},"inwardIssue":D,"outwardIssue":F}`), read back on both issues; attachments replaced by POST then `cmp` then DELETE of the old id; the body rendered before filing with POST `/rest/api/1.0/render` (`rendererType: atlassian-wiki-renderer`) to check `code-sql` panels and the `emoticon` count, escaping prose `\{1, 2\}` and `\(*)`.
- Applies at: Workflow
- Case (2026-10-04, CBRD-27557): the swapped link form read "D causes F" and had to be deleted and recreated.
- Case (2026-10-23, CBRD-27759): a `{1, 2}` set literal in prose opened a wiki macro that swallowed the next `{code:sql}` block, and `COUNT (*)` became a star emoticon; inside `{code}` both are fine.
- Case (2026-10-23, CBRD-27730): an Open Correct Error offers only "To Triage" and "Bug Invalid"; "Bug Invalid" resolves it as **Fixed** and the resolution cannot be changed afterwards without the UI or an admin — say so before using it.
- Source: memory:jira-filing-workflow, memory:no-jira-posting

### P4 — design docs in the code's words
- Rule: A design document for this user spells names out (`DOMAIN_PLAN`, `RESOLVED_DOMAIN`, never `dplan`/`dgate`), reuses the code's dominant words and file prefixes (`resolve`, `qexec_`, `scan_`, `stx_build_`), adds no unit-test section, puts every execution-time decision before `qexec_execute_mainblock` and treats mainblock/scan code as read-only, shows where `qexec_execute_mainblock` sits in the XASL tree with the traversal explicit, is one self-contained `.md` in the repo sent with SendUserFile, and answers each finding of the user's own static review in the next version.
- Applies at: Required attachments
- Case (#323, v1 → v4): v1 used `dplan`/`dgate`, had unit tests, a G2 function and range-time resolve; the user: "너무 추상화하지 말고 기존 코드의 표현을 쓰도록".
- Source: memory:design-doc-style-no-abbrev-existing-vocab
