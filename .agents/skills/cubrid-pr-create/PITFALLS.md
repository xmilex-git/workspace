# PITFALLS — the rules in SKILL.md and the PRs that produced them

Each `P<n>` is one rule. The **Rule** line is the exact sentence SKILL.md carries at the step named in
**Applies at**; keep the two byte-identical. **Source** is where the lesson lived before it was folded
in here (auto-memory slugs are deleted once absorbed; kept for traceability only).

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule only when no rule fits — then add the sentence to SKILL.md in the same commit.

### P1 — the JIRA title stays
- Rule: An existing JIRA ticket keeps its title, Korean or not: the PR title is `[CBRD-XXXXX] <current JIRA title>` verbatim, and no replacement title is offered unless the user asks for a rename.
- Applies at: Conventions → Title
- Case (2026-09-29, CBRD-27486): English replacement titles were offered for the ticket's Korean title so the PR would read in English; the user: "jira 제목 이미 있지않음?? 그거 써. 제목 왜바꿈?".
- Source: memory:keep-existing-jira-title

### P2 — codestyle before every push
- Rule: Before every push to the engine branch, run CI's formatter over every changed source file and commit its diff: `export PATH=/etc/dev4_skeleton/install/bin:$PATH` (GNU indent 2.2.11, as in CI), then `for f in $(git diff --name-only <pushed-base> HEAD -- 'src/*.c' 'src/*.h' 'src/*.cpp' 'src/*.hpp'); do bash .github/workflows/codestyle.sh $f; done` and `git diff --stat` must be empty (a whitespace-only commit needs no build); in zsh loop over `$(cat list)` or literal names, never `for f in $F`, and treat "no `file~` backups appeared" as the formatter not having run.
- Applies at: Step 5
- Case (2026-10-08, PR 8022): two consecutive heads (55b90f173, f017d559c) failed the `code-style` check on `: tp_value_convert (…)` continuation lines in `query_analytic.cpp` — astyle re-aligns `?:` continuations, which eyeballing the 120-column rule misses; each cost a style-only commit and a CI rerun. The user: "작업끝나면 푸쉬전에 codestyle 검사하고 넣어라 지금도 실패중이다." Host astyle 3.1 reproduced CI's diff exactly.
- Case (2026-10-20, CBRD-27583 7b): `F=$(cat list); for f in $F` did not word-split in zsh, so codestyle.sh got one bogus argument and the "two passes, no change" check was void; a later commit picked up a real indent change.
- Source: memory:run-codestyle-before-push

### P3 — C++ inside a `.c` file is wrapped for indent
- Rule: C++ constructs inside a `.c` file (`template <...>`, `if constexpr`, `std::index_sequence`) make GNU indent lose its declaration state and rewrite every later function, so exactly that block is wrapped in `/* *INDENT-OFF* */` … `/* *INDENT-ON* */` (as `object_primitive.c` does), checked with `indent -l120 -lc120 -st <file>` against the file (never in place) and compared with the develop base to tell the PR's hunks from pre-existing ones, in its own whitespace-only commit.
- Applies at: Step 5
- Case (2026-09-25, #352): `object_domain.c` produced 1461 indent hunks, most in develop code, from one C++ block; the user: "object_domain.c 그 어긋남 유발하는 부분 indent off - indent on 이였나 그걸로 감싸서 잘 되게 해줘". After the wrap the whole file matched indent's output.
- Source: memory:gnu-indent-cpp-in-c-wrap-indent-off
