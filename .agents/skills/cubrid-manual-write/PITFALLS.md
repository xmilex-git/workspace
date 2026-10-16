# PITFALLS — five rules and the review rounds behind them

Every rule here once cost a review round on an upstream PR or a user correction. STYLE.md says how
the manual is written; this file says where drafts went wrong anyway. Read the whole file before
writing (Phase 3) and walk it again before every push (the first PR push and every review round).

**The check.** Before each push, write `<scratch>/<effort>/pitfalls.md`: one row per rule per touched
ko/en file pair, written after reading that rule's cases:

```
| rule | file | verdict | evidence |
| 1 | pl/pl_tuning.rst | hit → fixed | "서버에서 평가하는 내장 함수" read as a subset; every built-in path calls setConnectionRequired(); 9 forms rejected on release |
| 2 | sql/schema/stored_routine_stmt.rst | clear | unloaddb sentence carries the `unloaddb -s` excerpt (scratch/man772/unload/man772_schema) |
| 4 | sql/parallel.rst | n/a | no ko prose added |
```

`clear` needs evidence (a code path, a capture file, the sibling lines compared); a bare yes is not a
verdict. A `hit` is fixed before the push.

**Adding a case.** A miss that a reviewer, a bot, or the user exposes gets one line under its rule in
the same session that fixes it:
`PR #N (KEY, date, caught by <reviewer|approver|greptile|user>): <what was written> → <what was
wrong> → <fix>`. A new rule only when no rule fits; the "caught by" part is never dropped, because a
reviewer's find is what our own check missed. Cases from before this file carry only what the old
lesson said.

---

## Rule 1 — Every claim has the code's scope, in the user's terms

A constraint, threshold or applicability rule covers exactly what the engine code covers. A qualifier
that narrows it (a relative clause that reads as "only some") and a blanket that widens it ("the whole
query falls back") are the same defect. Derive the scope from the checking function, verify it on the
server, and write it as what the user observes and what the user does.

- When a prohibition covers a whole class, say **all** (ko "모두"), give one example per syntactic
  form, and name the allowed complement, each form compiled or run on the test server.
- Say how far a restriction reaches: which part falls back, which part is judged separately.
- Non-applicability lists are exhaustive over SQL-expressible, user-observable conditions taken from
  the eligibility check function; internal plan shapes are left out.

Cases:
- PR #772 (CBRD-27299, 2026-10-16, caught by reviewer): "서버에서 평가하는 내장 함수 … 사용할 수
  없다" → read as "only some built-ins"; `ParseTreeConverter` calls `setConnectionRequired()` on every
  built-in path (`visitFunction_call`, `visitIdentifier`, `visitSyntaxed_call_*`) → "내장 함수 호출은
  모두" with parenthesized / no-parenthesis / dedicated-syntax examples plus the allowed operators;
  9 forms rejected and the operator set compiled and called on a release build.
- PR #772 (CBRD-27299, 2026-09-11, caught by reviewer): parallel-scan bullet named only predicates
  → the per-scan rule also applies inside subqueries and inline views; subquery bullet did not say
  which subquery is excluded → the one holding the function, independent ones judged separately (not
  "others unaffected": `mark_sp_blocks_recursive` propagates to enclosing subqueries).
- PR #768 (CBRD-26722, round 2, caught by reviewer): "~와 같은 일부 경우" → full list from memoize
  `possible_check` and `px_scan_checker`, each item code-verified.
- PR #768 (CBRD-26722, round 2, caught by reviewer): "동일한 규칙" for rules over different input
  metrics (scan pages vs larger list pages) → "같은 형태의 규칙" / "a rule of the same shape".
- PR #768 (CBRD-26722, round 2, caught by reviewer): hidden constant left out → observable
  thresholds documented with their code-confirmed scope (`MIN_TUPLES_FOR_PARALLEL_SORT=500`, ORDER
  BY+LIMIT only); multi-stage clamps listed in application order (① core count ② max_parallel_workers);
  blank upper-bound cell → bound read from `system_parameter.c` (upper NULL → ko 없음 / en none).
- PR #768 (CBRD-26722, round 1, caught by reviewer): reviewer proposed deleting the "driving table of
  a join" constraint → `px_scan_checker.cpp` still enforced it → kept, rewritten from the user's view
  with the ORDERED/USE_HASH hints that change it.
- #152 (caught by user): an engine gate ("selectivity comes from a histogram") folded into a bullet
  as an internal condition → its own sentence: what the user observes, then the action (**UPDATE
  STATISTICS**).
- #768 era (caught by reviewer): over-qualified feature names → plain feature name, restrictions in
  prose.

## Rule 2 — What the user sees is shown as captured output

A sentence saying a tool, view or trace "shows / writes / returns" something carries the captured
output that shows where and in what form. Every example shows what its intent comment says, every
value it prints is explained by the surrounding text, and a feature that behaves differently on
different paths gets one example per path.

Cases:
- PR #772 (CBRD-27299, 2026-09-11, caught by reviewer): "**unloaddb**\는 이 속성을 스키마 파일에
  출력한다" with no excerpt → the reader cannot tell where or in what form → `unloaddb -s` schema-file
  excerpt plus the position (after AUTHID, after DETERMINISTIC when both are declared).
- PR #772 (CBRD-27299, 2026-09-10, caught by greptile): new `is_parallel_enabled` column in the
  `DB_STORED_PROCEDURE` table, but the page's `SELECT *` output was the old capture → every example on
  the page that reads a changed view or table is re-run and re-pasted.
- PR #772 (CBRD-27299, 2026-09-11, caught by reviewer): example comment said the function was in a
  predicate; the example put it in a subquery → the comment names what the example shows.
- PR #772 (CBRD-27299, 2026-09-11, caught by reviewer): one PL/CSQL example for a property that
  Java and PL/CSQL reject at different times (PL/CSQL at CREATE, Java at the call) → one captured
  example per language.
- PR #772 (CBRD-27299, 2026-09-11, caught by reviewer): `target` described as the target name while
  the example printed NULL for PL/CSQL → the description covers NULL for PL/CSQL routines.
- PR #772 (CBRD-27299, 2026-09-11, caught by reviewer): parallel trace showed FUNC time 7502 above
  the serial 6140 and above its own SELECT time, unexplained → say which field to compare (SELECT
  time) and why the other grows (summed over workers).
- PR #768 (CBRD-26722, round 2, caught by reviewer): MEMOIZE `enabled: false` described as visible
  → the entry is not printed at all; describe the output gate (`hit > 0`).

## Rule 3 — New text takes its siblings' shape; unchanged meaning keeps its words

A new bullet takes the grammatical form of the bullets beside it (noun phrase, "~시", full sentence),
a new section takes the heading level of its sibling sections, and a constraint sits in the section
that matches its scope. When an existing bullet is split or extended, the part whose meaning does not
change keeps its original words, so the diff shows only the new meaning. Compare against the sibling
lines in each language separately: ko and en lists can use different forms.

Cases:
- PR #772 (CBRD-27299, 2026-10-16, caught by reviewer): en nested bullet written as a sentence
  ("Stored functions … are evaluated in predicates.") among noun-phrase siblings ("Serial usage",
  "References to session variables") → "A stored function … evaluated in a predicate."
- PR #772 (CBRD-27299, 2026-10-16, caught by reviewer): splitting "저장프로시저(JavaSP, PL/CSQL),
  Serial 사용시" reworded the unchanged half to "Serial을 사용하는 경우" → "Serial 사용시", the
  original words and the siblings' "~시" form.
- PR #772 (CBRD-27299, 2026-09-11, caught by reviewer): new `pl_tuning.rst` section underlined with
  `-` while its sibling "… 사용" sections use `=` → the siblings' level.
- PR #772 (CBRD-27299, 2026-09-11, caught by reviewer): the element-type rule for collection return
  types, which applies to every routine option, sat in the PARALLEL_ENABLE section → moved to the
  common CREATE FUNCTION property text.
- PR #768 (CBRD-26722, caught by reviewer): section titles repeated the parent's context ("병렬 질의
  처리") → "병렬 실행".

## Rule 4 — ko reads as the manual's Korean

Use the manual's existing vocabulary (grep before writing a noun, STYLE.md §9) and the upstream
notation standard `docs/STYLE_GUIDE.ko.md` in the manual clone (CUBRIDMAN-343; the Greptile bot
reviews against it). A particle after an English word follows its Korean reading. Comments inside ko
code blocks are Korean.

Cases:
- PR #772 (CBRD-27299, 2026-09-11, caught by reviewer): "PARALLEL_ENABLE으로" → "PARALLEL_ENABLE로"
  (이네이블, ㄹ final → 로).
- PR #772 (CBRD-27299, 2026-09-11, caught by reviewer): English intent comments in three ko code
  blocks ("-- Prepare data for a parallel scan.") → Korean.
- PR #768 (CBRD-26722, round 1, caught by reviewer): engine slang "디스크에 떨어진" → deleted when
  incidental, "저장된/저장되지 않은" when essential; the en sentence follows.
- PR #768 (CBRD-26722, round 2, caught by reviewer): escape edits left duplicated particles
  (":ref:`…`\에 결과에") → swept with `scripts/rst-lint.sh`.
- PR #768 (CBRD-26722, caught by reviewer): "쿼리" → "질의" everywhere (lint HARD check).
- #152 (caught by user): coined "서브라인/라인" (no precedent) → "항목", "병렬 처리 상세 정보";
  "실체화(materialization)" → described against View Merging with the **NO_MERGE** hint; "병합" →
  **View Merging** / "머지(merge)" with :ref:`view_merge`.

## Rule 5 — Every review comment gets a reply, wherever it was posted

A review round collects comments from all three places GitHub keeps them (PR.md, "Review response
protocol") and ends when every comment by someone other than the author has a reply that names the
change and the commit, or the reason for not changing. Each correction also lands as a case line in
this file in the same session.

Cases:
- PR #772 (CBRD-27299, 2026-10-16, caught by approver): a reviewer's conversation-tab comment
  (2026-09-11, asking for an unloaddb output example) went unanswered for five weeks while every
  inline thread had a reply → the round's sweep also lists issue comments and review bodies.
- PR #772 (CBRD-27299, round 1 of 2026-09-14, found in round 2): 11 corrections applied, none
  recorded as a lesson, so round 2 started from the old rules → the cases above, added with the
  round-2 fixes.
