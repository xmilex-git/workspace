# CUBRID JIRA Issue Tone and Output Guide

This guide is authoritative for wording, detail level, and markup. The target is the practical depth of CBRD-27041 for improvement work and CBRD-26799 for errors, not a code-level implementation or verification document. For sentence style, the standard is the body of CUBRID PR #8096 (CBRD-24029); the `## 설명 방식` section below adapts it to JIRA.

## Audience and purpose

Write for QA, decision-makers, and developers. The body must let them understand:

- what is wrong or being changed;
- when and whom it affects;
- what behavior or result marks completion.

The body is not a private analysis note, code review walkthrough, or exhaustive test plan. Prefer observable behavior and product scope over code internals.

## JIRA wiki markup

The saved file is pasted directly into jira.cubrid.org. Use JIRA wiki markup, not Markdown.

| Need | Use | Do not use |
|---|---|---|
| Section label | `*Description*` | `# Description`, `## Description` |
| SQL block | `{code:sql} ... {code}` | fenced Markdown code block |
| Shell block | `{code:bash} ... {code}` | fenced Markdown code block |
| Plain output | `{noformat} ... {noformat}` | fenced Markdown code block |
| Bullet | `* item` | Markdown checkbox |
| Numbered step | `# item` | Markdown heading |

Use plain text for function names, parameters, paths, and other identifiers. Do not use Markdown backticks or JIRA `{{...}}` inline monospace.

The JIRA Summary/title is a separate field. Do not place a Markdown title or `[TAG]` title in the body. A proposed Summary may be reported separately.

## Detail boundary

Include:

- the relevant background and impact;
- externally visible behavior and specification;
- the minimal complete reproduction for an error;
- the central implementation concept and affected scope;
- a small set of observable acceptance results.

Exclude from the body unless a fact is essential to understanding the issue:

- function-by-function flows and call graphs;
- data-structure and algorithm walkthroughs;
- source file lists, line numbers, and change counts;
- backtraces and root-cause essays;
- exhaustive edge-case, regression, or unit-test plans;
- implementation alternatives and speculative design;
- repeated summaries of the same fact.

Avoid an internal term when plain Korean says the same thing. When an identifier is necessary for reproduction, result recognition, or accuracy, keep it as-is and gloss it once at first use (see `## 설명 방식`).

## 설명 방식

독자는 이 코드를 모른다고 가정한다. 본문만 읽어도 **원래 어떻게 돌아가는지 → 무엇이 어긋났는지 → 그래서 무엇이 보이는지**를
순서대로 따라갈 수 있어야 한다. 결함이나 요구사항을 바로 들이밀지 않고, 먼저 그 자리의 정상 동작을 한 문단으로 설명한다.

1. **짧은 문장, 한 문장에 사실 하나.** 절이 셋 이상 이어지면 자른다.
2. **합니다체.** 목록 항목, 표, `{noformat}` 그림 안의 라벨은 명사형으로 끝낸다(잠듦, 대기, 질의 오류, Acceptance Criteria 만족).
3. **쉬운 우리말 동사.** 넘겨주다, 잠들다, 깨우다, 챙기다, 바닥나다, 쥐다, 놓다, 한 바퀴 돌다.
   "수행", "처리", "로직", "구조 개선", "최적화" 같은 말은 무엇을 하는지 보이는 동사로 바꾼다.
4. **용어는 처음 나올 때 한 구절로 풀이한다.** 그 다음부터는 그대로 쓴다.
   예: "버퍼 풀에서 victim(재사용할 페이지 프레임)을 찾지 못한 스레드는 대기 큐에 들어가 잠들고, 누군가 victim을 넘겨줘야 깨어납니다."
   역할이 나뉘어 있으면 누가 무엇을 맡는지 나열한다.
5. **숫자는 출처와 함께.** 주기·상한·기본값은 괄호에: (100ms 주기), (기본 300초), (page_flush_interval_in_msecs, 기본 1초, 0이면 무한 대기).
   측정한 값은 "실측"이라고 밝힌다. 측정하지 않은 효과는 쓰지 않는다.
6. **현상은 빌드별로.** 사용자가 보는 결과를 `debug 빌드 : ...` / `release 빌드: ...`로 나눠 적는다. 한쪽만 해당하면 그쪽만 쓴다.
7. **그림.** 순서, 단계, 서로 기다리는 관계가 있으면 `{noformat}` 블록에 텍스트 트리로 그린다.
   트리 기호는 `└ ├ │`, 흐름은 `→`. 한 줄에 한 단계. 조건·수치는 괄호로. 그림은 글로 설명한 것을 한눈에 보여 주는 용도다.
   그림만 두고 글을 빼지 않는다. 코드 발췌는 JIRA 본문에 넣지 않는다(design.md로).
8. **바뀐 것과 바뀌지 않은 것을 같이 쓴다.** `Specification Changes`의 호환성 항목은 보이는 변화를 먼저, 그리고
   "디스크 포맷, 로그, 프로토콜, 시스템 파라미터는 바뀌지 않습니다"처럼 범위를 한 줄로.
9. **길이는 사안 크기에 비례한다.** 한 문장이면 끝나는 결함에 그림이나 배경 문단을 붙이지 않는다.

예 — Correct Error의 `Description` (PR #8096 본문에서 JIRA 범위만 추린 것):

```text
*Description*

버퍼 풀에서 victim(재사용할 페이지 프레임)을 찾지 못한 스레드는 대기 큐에 들어가 잠들고, 누군가 victim을 넘겨줘야 깨어납니다. flush 데몬처럼 사건이 있어야 움직이는 경로가 아무도 대기 스레드를 챙기지 않는 조용한 시점을 대비해, page maintenance 데몬(100ms 주기)이 안전망으로 victim을 넘겨줍니다.

이 안전망이 2017년 도입 이후 한 번도 동작하지 않았습니다. 다른 경로가 우연히 victim을 주지 않으면 대기 스레드는 page_latch_timeout_in_msecs(기본 300초)까지 기다립니다.

{noformat}
victim 탐색 실패 → 대기 큐 등록 → 잠듦
  300초까지 아무도 깨우지 않으면
    debug 빌드  : assert로 서버 abort
    release 빌드: 질의 오류
{noformat}
```

루프 조건이 왜 틀렸는지, 어느 함수를 어떻게 고치는지는 본문이 아니라 design.md에 둔다.

### 단어와 논리 — 사람처럼 읽히는 이유

- **행위자가 있는 문장.** 주어는 스레드, 데몬, 브로커, 응용처럼 실제로 움직이는 것이다. "~되었습니다"처럼 누가 했는지 없는 피동문,
  "동기화 호출이 잦아집니다"처럼 추상 명사가 주어인 문장은 쓰지 않는다.
- **몸으로 그려지는 동사.** 넘겨주다, 잠들다, 깨우다, 챙기다, 바닥나다, 쥐다, 놓다, 몰리다. 추상 동사(수행, 처리, 관리, 보장, 개선, 최적화)는
  무엇을 하는지 보이는 동사로 바꾼다.
- **영어 용어는 영어 그대로, 주변은 우리말.** victim, flush, quota를 희생자·할당량으로 옮기지 않는다.
- **비유는 하나를 골라 끝까지.** "안전망"처럼 도입부에서 꺼낸 말이 결함과 결과까지 꿴다.
- **헤지는 확률적인 자리에만.** "우연히 victim을 주지 않으면", "챙기지 않을 수 있습니다". 확실한 사실에 "~로 보입니다"를 붙이지 않고,
  확률적인 사실을 단정하지 않는다.
- **날짜·횟수·실측치로 말한다.** "오래된 결함"이 아니라 "2017년 도입된 이후 한 번도 동작하지 않았습니다".
- **평가어·꾸밈말·라벨 금지.** 효과적으로, 안정적으로, 명확하게, 일관되게, 적절히, 다양한, 핵심, 주요, 전반적으로, 보장합니다, 이를 통해, ~함으로써.
  "문제:", "원인:", "해결:" 같은 머리표도 붙이지 않는다.
- **접속은 말하듯이.** 그런데, 그래서, 그 결과, 그 사이, 하더라도. 따라서, 또한, 이에 따라, 뿐만 아니라, 결론적으로는 쓰지 않는다.
- **인과 사슬.** 각 문장은 앞 문장이 만든 질문에 답한다. 정상 동작 → 누가 맡는가 → 그들의 한계 → 그래서 무엇이 있다 → 그것이 어긋났다 → 결과.
  한 문단은 인과 한 걸음이고 마지막 문장은 그 걸음의 결과다.
- **독자의 다음 질문을 먼저 막는다.** "그럼 그것만 고치면?", "다른 경로는?", "왜 그 순서?"에 해당 문장 바로 뒤에서 답한다.
- **이전 동작을 수치와 함께 인정한 뒤 바뀐 것을 쓴다.** `Specification Changes`의 각 항목은 "지금은 ~했습니다. 앞으로는 ~합니다" 꼴이다.
- **왜 지금까지 몰랐는지 말한다.** "깨워 줄 주체가 없습니다"처럼 결함이 숨어 있던 이유를 한 문장 둔다.
- **안 한 일은 이유와 처리 계획을 같이.** 범위 밖으로 둔 것은 왜 그런지와 어느 이슈에서 다루는지를 쓴다.
- **메타 서술과 마무리 요약 금지.** "이 이슈에서는", "정리하면", "결론적으로"를 쓰지 않는다. 마지막 문장은 사실로 끝난다.

## Korean style

- Write concise Korean in 합니다체, following `## 설명 방식` above.
- Prefer short paragraphs and natural sentences. Avoid AI-style labels, self-narration, and a repeated `~합니다.` rhythm with the same verb.
- Do not add `Issue Triage`, `AI-Generated Context`, `Summary`, TL;DR, rationale scaffolding, or a tutorial.
- Do not repeat one requirement across `Specification Changes`, `Acceptance Criteria`, and `Definition of done`.
- Do not use emoji or non-BMP characters. Prefer plain ASCII punctuation with Korean text.
- Do not invent facts, thresholds, build versions, performance targets, test results, or implementation choices. Use `N/A` only where the template requires a section but there is no applicable content.

## Portable content

JIRA readers do not share the author's local tooling.

- Do not put `just <recipe>`, personal aliases, private helper functions, or local-only paths in the body.
- Use commands available in the CUBRID/CTP environment, such as `ctp.sh`, `cubrid`, `csql`, `make`, `cmake`, `bash`, or `sh`.
- If a local wrapper was used, write the portable underlying command instead.

## Final check

Before saving, verify:

1. The chosen template matches the work, including for a Sub-task.
2. The body uses JIRA wiki markup and contains no title line.
3. A reader who has never seen the code can say, from `Description` alone, what normally happens, what went wrong or what changes, and what they would see. Every term is glossed at first use; every number carries its unit, default, or source; no sentence chains three or more clauses.
4. Implementation and verification detail stay within the limits in `SKILL.md`.
5. `Repro` is minimally complete for a Correct Error.
6. Specification and performance claims come from supplied evidence.
7. Empty `Additional Information` is omitted; absent specification changes are `N/A`.
8. The same fact is not repeated in multiple sections.
