# Branch, PR, reviewer, JIRA comment

## §1 Branch per mode (do this before Step 3; the case is written inside this worktree)

**Merged mode** — a 후속 TC PR from the fork, one per issue:

```bash
# sql → cubrid-testcases; shell → cubrid-testcases-private-ex (both have remotes origin=CUBRID, fork=xmilex-git)
cd ~/dev/cubrid-tc-worktree/develop      # or ~/dev/cubrid-tc-ex-worktree/develop
git fetch -q origin develop
git worktree add -b cbrd_<N> ../cbrd_<N> origin/develop
# ... write the case there (Step 3), verify (Step 4), then:
git -C ../cbrd_<N> add sql/<dir>/cases sql/<dir>/answers        # shell: shell/<dir>
git -C ../cbrd_<N> commit -q -m "[CBRD-<N>] Add sql testcase for <English summary>" -m "<2-4 lines: what the case pins and how it is judged>"
git -C ../cbrd_<N> push -u fork cbrd_<N>
```

The commit message ends with the attribution trailer the harness prescribes for this session.

**Open mode** — the TC rides the bot's branch of the engine PR:

1. Wait until `git ls-remote origin refs/heads/tc/pr-<PR>` exists **and** its head is the bot's
   "chore: Initialize TC branch" commit (the bot creates the branch by API first and force-pushes the
   commit about a minute later; pushing before that rejects the bot's push and no draft PR is made —
   2026-10-07 #8120; recovery: `gh run rerun <run> -R CUBRID/cubrid --failed`).
2. `git fetch origin +refs/heads/tc/pr-<PR>:refs/remotes/origin/tc/pr-<PR>` then
   `git worktree add ../tc-pr-<PR> origin/tc/pr-<PR>`; write, verify, commit as above;
   `git push origin HEAD:tc/pr-<PR>` (pushing to this upstream branch is the one allowed exception
   to the fork-only rule — it already exists and belongs to the engine PR).
3. The TC PR already exists as the bot's draft (`[CBRD-x] Draft: TC changes for PR CUBRID/cubrid#<PR>`):
   `gh pr list -R CUBRID/cubrid-testcases --head tc/pr-<PR> --json number,url`. Edit its title and body
   (§2–§3) with `gh pr edit <n> -R <repo> --title ... --body-file ...`; leave draft status to the engine PR owner.

## §2 Title

`[CBRD-<N>] Add sql testcase for <what the case pins, English, lower case after the first word>`
(`shell testcase` for shell). R3 in merged mode opens two PRs, sql in cubrid-testcases and shell in
private-ex: each title names its own suite, each body links the other in its first lines, and §4 picks
each PR's reviewer afresh (the first request raises that member's load by one; CBRD-27100). The JIRA
title is not reused here — the TC PR names the test, not the fix.

## §3 Body — 합니다체, the user's own TC PR form (cubrid-testcases#3552), tone_guide rules

Read `.agents/skills/cubrid-pr-create/tone_guide.md` first: Korean prose, facts the diff supports,
no filler, no padded sections. Save the body as `<rundir>/tc-pr-body.md`; `pr-body.md` already holds
the engine PR's body (judge.md §1) and must not be overwritten. Template (every `<...>` filled, every section kept):

```markdown
- Issue: http://jira.cubrid.org/browse/CBRD-<N>
- Engine PR: https://github.com/CUBRID/cubrid/pull/<PR> (`develop`, `<fix sha 9>`, <merge date>)

## 개요

<2-3 문단: 수정 전 동작과 문제, 엔진 PR이 바꾼 것. 사용자 관점의 용어로.>

- **파일:** `sql/<dir>/cases/cbrd_<N>.sql`
- **정답:** `sql/<dir>/answers/cbrd_<N>.answer` (CTP 생성, 직후 빌드 optdebug)
- **판별:** <sql|shell|둘 다>, 근거 <한 줄>. <R5일 때: 정합성 TC라 직전 빌드도 통과하며, 결과가 전후 동일함을 확인하는 것이 목적입니다.>

## 설계

- **<굵은 머리말>** <판정 방법: 참조 쌍둥이와 trace 토큰, 마스킹 때문에 숫자를 쓰지 않는 이유>
- **<데이터>** <크기와 임계값, 그룹별 건수가 다르게 한 이유>
- **<정리>** <trace off, 파라미터 복원>

## 커버리지 (<K> 케이스)

| 케이스 | 시나리오 | 기대 | develop(직전) |
|---|---|---|---|
| 1 | <...> | <...> | <직전 빌드의 답 또는 "동일"> |

## 검증 (optdebug, CTP `sql` 단일 디렉터리)

| 지점 | 커밋 | 결과 |
|---|---|---|
| 직전 | `<sha 9>` (<merge_commit>^) | NOK — <어느 케이스가 어떻게 달랐는지 한 줄> |
| 직후 | `<sha 9>` | OK ×3 |
| 최신 develop | `<sha 9>` (<날짜>) | OK |
```

Write what the table shows; a "직전 OK" row in an R5 PR gets the sentence from `판별`.

**Inline design comments** — one review (event `COMMENT`) on the TC PR, 합니다체, **plain text**:
a short title line, a blank line, one paragraph; no inline code, no bold (the GitHub Android app
clips paragraphs holding inline code — #3590, 2026-09-28). Case-file lines carry the design reason
("왜 이 데이터·힌트인가"); answer lines carry what the pre-fix build printed there. Anchor only
facts verified in `results.md`.

```bash
gh api -X POST repos/CUBRID/<repo>/pulls/<n>/reviews --input review.json
# review.json: {"event":"COMMENT","body":"","comments":[{"path":"sql/.../cbrd_<N>.sql","line":<n>,"side":"RIGHT","body":"<title>\n\n<paragraph>"}, ...]}
```

A 504 from this POST can still have created the review: `gh api repos/CUBRID/<repo>/pulls/<n>/reviews`
before posting again.

## §4 Reviewer — exactly one, from the team

Team (reviewer pool; the author `xmilex-git` is excluded): `shparkcubrid`, `HyunukLee`,
`soheejung-cs`, `youngjinj`, `Hamkua`, `jihyekim-0` (user, 2026-10-08).

The reviewer is a team member **who reviewed the engine PR**, and among them the one with the
**fewest pending review requests now** (user, 2026-10-08). Load alone sent TC PRs to people who never
saw the fix; participation alone sent every TC PR to shparkcubrid, who already had 12 open requests.

```bash
cd /home/cubrid/dev/workspace
# 1. candidates: team members with review comments or reviews on the engine PR (count = participation)
{ gh api repos/CUBRID/cubrid/pulls/<PR>/comments --paginate -q '.[].user.login';
  gh api repos/CUBRID/cubrid/pulls/<PR>/reviews  --paginate -q '.[].user.login'; } \
  | /usr/bin/grep -xE 'shparkcubrid|HyunukLee|soheejung-cs|youngjinj|Hamkua|jihyekim-0' | sort | uniq -c | sort -rn
# 2. load: pending review requests on open PRs in the engine repo and both TC repos
for repo in CUBRID/cubrid CUBRID/cubrid-testcases CUBRID/cubrid-testcases-private-ex; do
  gh pr list -R $repo --state open --limit 500 --json reviewRequests -q '.[].reviewRequests[] | select(.login != null) | .login'
done | /usr/bin/grep -xE 'shparkcubrid|HyunukLee|soheejung-cs|youngjinj|Hamkua|jihyekim-0' | sort | uniq -c | sort -n
# 3. tie-break: who approved the engine PR
gh api repos/CUBRID/cubrid/pulls/<PR>/reviews --paginate -q '.[] | select(.state=="APPROVED") | .user.login' | sort -u
```

1. Candidates = the team members listed by command 1 (at least one review or review comment on the
   engine PR). Nobody from the team reviewed it → every team member is a candidate.
2. Pick the candidate with the **fewest pending review requests** summed over the three repos
   (a member with no request counts 0; `uniq -c` omits them).
3. Tie → the one with more participation on the engine PR (command 1); still tied → the one who
   **APPROVED** it; still tied → the first in the team list order above.
4. Record the candidates, the counts and the choice in `<rundir>/reviewer.md` (the PR body does not
   mention them).
5. `gh pr edit <tc-pr> -R CUBRID/<repo> --add-reviewer <login>`; verify with
   `gh pr view <tc-pr> -R CUBRID/<repo> --json reviewRequests`.

## §5 JIRA comment — three kinds only

Post a JIRA comment **only** for: (1) "성능 TC 필요" — out of scope, performance only (R4), **or** a
correctness TC PR (R5) for an issue whose goal is performance (its acceptance criteria name a time,
I/O or memory target): the PR covers the results, the comment says which performance TC is still
needed (user, 2026-10-08, CBRD-27181); (2) no TC possible (R6); (3) latest-develop regression
(verify.md §6). Any other TC PR gets **no** JIRA comment — the reviewer request is the notification.
Any other JIRA write is forbidden.

For kind (1) with a PR, the comment opens with one line naming the TC path and what it checks, then
the performance part of the R4 template below (CBRD-27181 comment 4776759 is the model).

Style: `.agents/skills/cubrid-jira-issue-write/tone_guide.md` — 한다체, JIRA wiki markup
(`*제목*`, `{code:sql}`, `{noformat}`, `* 항목`), plain text identifiers (no backticks, no `{{ }}`),
**only issue keys and commit hashes** — no workspace issue numbers, no local tool or path names,
no run ids.

Templates (fill, save as `<rundir>/jira-comment.txt`):

```
*TC 작성 판단*
이 이슈의 변경은 <함수/경로>의 <시간|I/O|메모리>만 바꾸고, 질의 결과와 실행 계획·trace 문자열은 수정 전후가 같다 (<fix sha 9>와 그 부모 <pre sha 9>의 optdebug 빌드에서 확인).
정합성 TC로는 변경을 판별할 수 없어 CTP 테스트케이스를 추가하지 않는다.
필요한 것은 성능 TC다: <무엇을 어떤 데이터로 재서 어떤 비율을 기대하는지 2-3줄>. 실행 시간 기반 TC는 공용 회귀 환경에서 흔들리므로 전용 성능 환경에서 측정하는 쪽이 맞다.
```

```
*TC 작성 판단*
이 이슈는 <관측 조건: 기존 shell 테스트가 쓰는 수단으로는 결정적으로 일으킬 수 없는 경합 | ...>에서만 드러나 CTP sql·shell 테스트케이스로 결정적으로 판별할 수 없다 (<pre sha 9> / <fix sha 9> optdebug 빌드에서 <무엇을> 시도; 공유 비교 지점을 썼으면 수정 커밋과의 관계를 함께 적는다).
테스트케이스를 추가하지 않는다. <대안이 있으면 한 줄>.
```

```
*최신 develop 회귀*
CBRD-<N>의 테스트케이스가 수정 커밋 <fix sha 9>에서는 통과하고 그 부모 <pre sha 9>에서는 의도대로 실패하지만, develop <dev sha 9>에서는 <코어|assert|결과 차이>가 난다.
{noformat}
<assert line or result diff, ≤10 lines>
{noformat}
재현 질의:
{code:sql}
<SQL>
{code}
테스트케이스 PR은 이 회귀가 정리될 때까지 보류한다.
```

Post (dry run first, then send; record the comment URL in `results.md`):

```bash
cubrid-jira comment CBRD-<N> --body-file <rundir>/jira-comment.txt --from jira          # prints what would be sent
cubrid-jira comment CBRD-<N> --body-file <rundir>/jira-comment.txt --from jira --yes
```
