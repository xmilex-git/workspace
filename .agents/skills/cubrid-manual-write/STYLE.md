# STYLE — house style for cubrid-manual prose, RST, and examples

Normative text is kept in Korean where the rule is about Korean prose (the wording the manual owner
confirmed); headings and glue are English. This file supersedes
`docs/research/manual-style-guide.md@research/manual-style-guide`. Review corrections and render
anomalies are recorded as cases in [PITFALLS.md](PITFALLS.md), in the same session they are found.

Precedence: manual's existing text > the manual's `docs/STYLE_GUIDE.ko.md` (notation standard, CUBRIDMAN-343) > this file > earlier PRs/drafts. Engine code > everything for facts.

## 1. Language and tone

### Korean (ko is the original; en mirrors it)

- **한다체.** 모든 본문 문장은 `-다`로 끝난다. 합니다체·명령형(~하십시오) 금지.
  - 기능 정의: "X(English Name)은/는 …하는 기능이다."
  - 조건·폴백: "다음 조건 중 하나라도 해당되면 …이 적용되지 않으며, 단일 스레드 방식으로 실행된다." / "다음 조건을 모두 만족해야 한다."
  - 기본값: "기본값은 \*\*100\*\*\ 이며, 최소값은 \*\*0\*\*, 최대값은 \*\*1000\*\*\ 이다."
  - 상호 참조: "자세한 내용은 :ref:\`section-anchor\`\ 를 참고한다."
  - 권장: "…하는 것을 권장한다."
- **"질의"만 사용한다 — "쿼리" 금지** (리뷰어 교정, 전역 적용).
- 영문 기술 용어는 첫 등장에 "한글(English)" 병기 — "선택도(selectivity)", "임시 결과 리스트(list file)". 번역이 어색한 것(gather, BUILDVALUE, row-by-row)은 영문 그대로.
- 닫힌 목록에 막연한 "등"을 붙이지 않는다.
- 개발자 전용 내부 용어(if_pred, XASL 등)는 사용자 언어로 풀어 쓴다 — "대상 테이블을 스캔하며 평가할 수 없는 조건절".
- 목록 도입 문장은 마침표로 끝낸다(콜론 아님).
- 구어체 엔진 은어 금지 — "디스크에 떨어진" ✕ → 비본질이면 삭제, 본질이면 "저장된/저장되지 않은".

### English

- Present-tense declaratives, paragraph-for-paragraph with ko. "Parallel Scan splits a single scan input across multiple worker threads that process it concurrently."
- **American spelling** (optimize, parallelize, synchronization). Inherited British forms are corrected, not kept.
- Conditions: "X is not applied — and falls back to a single-threaded scan — if any of the following hold:"
- Use "aggregate function", not bare "aggregate", as the noun.

## 2. Document and section structure

- File head keeps `:meta-keywords:` / `:meta-description:`.
- Heading levels: `*` over+under (only `*_index.rst` toctree wrappers) → `=` (H1) → `-` (H2) → `^` (H3). Do not use `"`. Underline at least as wide as the title (generous for Hangul).
- Below `^`, use **bold-line pseudo-headings** instead of real headings: `**활성화 조건**`, `**예제**`, `**Additional list-scan constraints**`.
- Anchors: concepts/sections kebab-case `.. _parallel-hash-join:`; **parameter anchors are the snake_case parameter name** `.. _memoize_memory_limit:`. Anchor sits directly above its heading (or bold parameter line), blank lines around. Renamed hint → rename the anchor, never leave the old one.
- Canonical order inside a feature section: intro → common constraints → per-kind subsections (anchor + intro + "추가 제약" pseudo-heading + bullets + SQL example + optional note) → performance considerations ("효과가 크다" list → "저하될 수 있다" list) → optimization subsections → trace/profiling subsection → (page end) throughput/activation rules.
- New page ⇒ also register in `{en,ko}/sql/index.rst` summary bullets and the `*_index.rst` toctree. Prefer a new **section** next to a sibling feature over a new page when the surface is one parameter plus a trace block (precedent: MEMOIZE sits beside SUBQUERY CACHE in `tuning.rst`).
- Section titles drop context already given by the parent ("병렬 질의 처리" → "병렬 실행").

## 3. RST rules

- **`.. versionadded::` / `.. versionchanged::` are forbidden** — zero occurrences in the tree; versions live in branches. If a version must be named, say it in prose.
- Escape after inline markup when a particle/letter follows: `` :ref:`parallel-query`\ 를 ``, `**100**\ 이며`. After editing escapes, sweep for duplicated particles (`` `\에 결과에 `` type typos) — `scripts/rst-lint.sh` flags candidates.
- Parameter links are explicit-text refs `` :ref:`max_parallel_workers <max_parallel_workers>` ``; section refs whose title matches are bare `` :ref:`parallel-query` ``.
- SQL input: `.. code-block:: sql`. Trace, plan, csql, conf **output: bare `::` literal block** (no language tag). Conf snippets: "다음은 … 예제이다. ::" then indented literal.
- `.. note::` for caveats and interpretation (several in a row allowed, nested at the parameter's indent). `.. warning::` only for data-loss-grade issues.
- Bullets `*` + 3 spaces (`*   `), nested by 4 spaces. Bold: feature/parameter/hint/trace-field names and key numbers (`**2 이상**`). Italic: metavariables (*degree*).
- Tables: config summaries are grid tables; new tables use `.. csv-table::` with `:header:`/`:widths:`. **No empty cells** — verify the upper bound in `system_parameter.c`; if `upper == NULL` write ko `없음` / en `none`, never invent INT_MAX.
- No tab characters (repo README rule; 4 spaces).

## 4. Parameter template (`admin/config.rst`)

A new parameter is written in **three places**: ① the `.. _cubrid-conf:` master table (Category / Applied / Session / Type / Default / Dynamic Change — applied-to and dynamic-change live only in the table, never restated in prose) ② the category's type/range grid table ③ the body entry, placed beside its closest sibling. Body template (from the merged `memoize_memory_limit` entry):

```rst
.. _memoize_memory_limit:

**memoize_memory_limit**

    **memoize_memory_limit**\ 는 :ref:`MEMOIZE <memoize>` 최적화가 캐시 하나에 사용할 수 있는 메모리 크기를 설정하기 위한 파라미터이다. 값 뒤에 B, K, M으로 단위를 붙일 수 있으며, 각각 Bytes, Kilobytes, Megabytes를 의미한다. 단위를 생략하면 바이트 단위가 적용된다. 기본값은 **2,097,152** (2M) 바이트이며, 최소값은 **0**\ 이다.

    이 파라미터가 **0**\ 으로 설정되면 MEMOIZE 최적화가 비활성화된다. … 다음과 같이 세션 단위로도 변경할 수 있다. ::

        SET SYSTEM PARAMETERS 'memoize_memory_limit=0';

    .. note::

        …
```

- Special values (0 / 1 / 2+) each get an explicit sentence ("0 이상의 정수이며, 0이나 1로 지정하면 비활성화된다").
- Restart-only parameters (no `PRM_USER_CHANGE`) say so: "cubrid.conf에 설정한 뒤 재시작해야 적용된다(SET SYSTEM PARAMETERS 불가)".
- Multi-stage clamps are written as an ordered list in application order (e.g. ① core count ② `max_parallel_workers`), never merged into "크면 낮추어 적용된다".
- Defaults that may change are **not** hard-coded in feature pages — the feature page links the config entry.
- Hidden parameters (`PRM_HIDDEN`) get **no** config entry (tree convention: 154 hidden, 5 legacy documented). Their *behavioral numbers* that a user can observe (e.g. 2,048-page gate, 500-row gate) are still written in the feature page prose, with the exact code path confirmed so the scope is right.

## 5. Hint template (`sql/tuning.rst`)

Three places: ① the syntax literal block in the `SQL 힌트` section (pipe-separated) ② an anchored bullet entry in the correct statement group (SELECT-only vs SELECT/UPDATE/DELETE — check the parser) ③ a mention in the feature page.

```rst
.. _no-parallel-hash-join:

*   **NO_PARALLEL_HASH_JOIN**: 해당 질의 블록에서 병렬 해시 조인을 사용하지 않도록 하는 힌트이다. 해시 조인 자체는 유지되고 병렬화만 비활성화된다. **PARALLEL** 힌트와 같이 사용하는 경우에는 **NO_PARALLEL_HASH_JOIN** 이 우선 적용된다. 자세한 내용은 :ref:`parallel-query`\를 참고한다.

    .. code-block:: sql

        SELECT /*+ NO_PARALLEL_HASH_JOIN */ o.order_id, t.category
        FROM orders o JOIN large_table t ON o.order_id = t.id;
```

- Formula: "…하는/…하지 않도록 하는 힌트이다." Arguments italic (*degree*) with "*degree* 는 …이며".
- Only hints the parser actually accepts appear in examples. A feature with **no hint** says so and names the only control ("끄는 방법은 `memoize_memory_limit=0`이 유일하다").

## 6. Trace / profiling notation

- Input: `.. code-block:: sql` with `csql> ;trace on` on one line, blank line, then prompt-less SQL (add `RECOMPILE` alongside the hint under test). The csql prompt appears only on session commands.
- Output: separate `::` block holding the `Trace Statistics:` tree. **No result set.**
- After the output, a bold-term bullet legend: `*   **parallel workers**: …` (nesting allowed); interpretation in `.. note::`.
- **Quote trace strings exactly as emitted**: `temp time` (not "list time"), `row by row` (space; the predicate form row-by-row is fine in prose), `buildvalue` (not the retired `gather: count`). Never invent fields (`key time`) — read the trace handler source and the captured output.
- State the **output gate** of a block, not an unobservable field value: MEMOIZE prints only when `hit > 0`; "enabled: false" is never visible because the entry disappears. Verify in the dump code before describing what a user "sees".
- Map scan kinds to labels explicitly: 힙→`heap time`, 리스트→`temp time`, 인덱스→`index time`.

## 7. Example policy

- **Every example is executed before inclusion** on the claimed server (see VERIFY.md). Unexecuted examples are forbidden.
- Dataset: ad-hoc synthetic schema (`large_table`, `orders`, `customers`, …) with a self-contained setup block (CREATE TABLE + bulk INSERT + `UPDATE STATISTICS ON …` , expected size as a comment like `-- Total pages in class heap: 17245`). `demodb` is too small for threshold-gated features.
  - **Bulk generation: never recursive CTE (slow). Use catalog cross joins:** `INSERT INTO large_table SELECT … FROM db_class a, db_class b, db_class c LIMIT 10000000;` — and the setup block shown in the manual uses the same form. Use `MOD(ROWNUM, n)`, not the infix form.
- Setup block appears once per page (with the activation-rule example); other examples reuse the schema.
- **Trace numbers are the captured originals** — no rounding, tidying, or invention.
- First line of every example block is one intent comment: `-- 병렬 스캔이 적용되지 않는 예`. No second comment restating the obvious.
- Show positive/negative pairs (applied / not applied).
- An example meant to show a trace block must actually produce it (e.g. MEMOIZE with `hit > 0`; NLJ may need `ORDERED USE_NL`, not `USE_NL` alone).

## 8. ko/en symmetry

- Paragraph-level mirror: same file paths, anchors, section order, examples, bold/`:ref:` placement. Anchors are shared (language-independent targets).
- Finish ko first, then write en from it.
- Known asymmetry defects to avoid: en-only constraint bullets, list items present in one language only, notes present in one language only.
- On completion run `scripts/rst-symmetry.sh -d <base-ref> ko/<file> en/<file>` — the ko and en deltas of bullets, notes, code blocks, literal blocks, refs, anchors, headings must match (whole-file mode for a page written end to end). Fix by adding to the poorer side, not deleting from the richer.

## 9. Vocabulary discipline (before writing any noun or verb)

1. `grep -rn '<word>' /home/cubrid/dev/cubrid-manual/ko` — if the manual already names the concept, **use that exact term and `:ref:` it** ("병합" → **View Merging** / "머지(merge)" per the `view_merge` section).
2. Zero precedents ⇒ do not coin it. Rephrase with existing vocabulary ("서브라인/라인" → "항목", "병렬 처리 상세 정보", "~가 추가로 출력된다"). If a new term is truly required, ask the user first.
3. "실체화(materialization)" is not manual vocabulary: describe a non-merged derived table as "병합되지 않는 derived table에서 임시 결과 리스트가 생성된다" and mention the **NO_MERGE** hint as the standard way to force it.
4. Suspected developer/colloquial jargon → same grep test; zero hits ⇒ rewrite.

## 10. Review pitfalls

Where drafts went wrong despite the rules above (each case a review round on #152, #768 or #772) is
kept in [PITFALLS.md](PITFALLS.md): five rules with their cases, walked before every push. A new
review correction becomes a case line there, not a rule here, unless it changes how the manual is
written in general.
