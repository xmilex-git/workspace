# PITFALLS — the rules and the runs that produced them

Each `P<n>` is one rule. The **Rule** line is the exact sentence SKILL.md carries; keep the two
byte-identical (`tools/skills/check-pitfalls-drift.sh .agents/skills/jira`). **Case** is the run that
paid for the rule.

### P1 — retry a failing cubrid-jira after upgrading it
- Rule: A `cubrid-jira` subcommand that fails with a JQL or HTTP error is retried once after `uv tool install --force git+https://github.com/vimkim/cubrid-jira`, before any workaround: an install older than upstream `2b87ad6` talks to `http://jira.cubrid.org`, whose https redirect double-encodes the query.
- Applies at: SKILL.md step 6
- Case (2026-11-09, PR 8432 review): `cubrid-jira attachment CBRD-27973 --list` failed with `JQL search failed (HTTP 400): ... The character '%' is a reserved JQL character ... (line 1, character 5)`. The install was `be4baac` with `JIRA_BASE = "http://jira.cubrid.org"`; `curl -sI` showed the 302 `location` carrying `jql=key+%253D+CBRD-27973`. The review worked around it through `cubrid_jira.http.fetch_issue`; `uv tool install --force git+https://github.com/vimkim/cubrid-jira` (to `e4747af`, which defaults to https) fixed `attachment` for both CBRD-27973 and CBRD-27972.
