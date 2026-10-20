# PR #8188 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8188](https://github.com/CUBRID/cubrid/pull/8188)
**제목:** [CBRD-27651] Fix the server crash when a parallel hash join worker evaluates a function call in the join condition
**작성자:** youngjinj
**HEAD SHA:** `60b6acc88` (develop merge-base `4adcd4090`, 현재 develop `1dceac8ad` 에 충돌 없이 merge 됨)
**JIRA:** CBRD-27651 (Correct Error, Develop, Minor) / 연관: CBRD-25717 (병렬 해시 조인 도입, 원인 줄을 넣은 변경) (design.md, test.md 첨부 없음)
**TC PR:** CUBRID/cubrid-testcases#3783 (`tc/pr-8188` `050c15fb5`) / cubrid-testcases-private-ex#4461 (`tc/pr-8188` `b8074d297`, 변경 없는 빈 draft)
**리뷰 일시:** 2026-10-19
**리뷰 결정:** 엔진 PR Approve (2026-10-19 게시 review 5567675276, inline 없음, 본문에 private-ex #4461 닫기 요청) / TC #3783 승인 판정, 게시는 사용자 확인 대기 / private-ex #4461 리뷰 없음

> **TL;DR** (Non-blocking): 막을 결함이 없다. `TYPE_FUNC` 사본이 원본 함수 노드를 복사하도록 고쳐 JIRA repro 의 서버 종료가 사라졌고(merge-base 종료, head 200000), 사본 해제 분기 3개로 워커 사본의 상수, REGEXP 패턴, RLIKE 패턴이 모두 해제되는 것을 메모리 모니터로 확인했다.

## Summary

- **변경 요약**: `cubxasl::spawner` (병렬 해시 조인 워커마다 조인 조건 사본을 만드는 클래스)의 `TYPE_FUNC` 분기가 `dest` 대신 `src` 의 함수 노드를 복사하고, 사본 해제 함수 `cached_entry_deleter` 에 `regu_variable_list_node` 상수, `FUNCTION_TYPE` `tmp_obj`, `PRED_EXPR` RLIKE `compiled_regex` 해제를 더한다
- **주요 이슈**: 없음
- **확인 필요 사항**: private-ex #4461 은 변경이 없으므로 닫으면 TC Merge Gate 가 풀린다

---

## Findings

없음

## JIRA -> Engine PR

기준: design.md/test.md 가 없으므로 JIRA 본문의 "제안 수정 1, 2" (AS-IS / TO-BE 코드)를 설계로 본다. 미정 항목은 없다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result: Line 4, 5 모두 200000 | merge-base 는 Line 5 에서 서버 종료(core frame 0 `qdata_evaluate_function`, JIRA 스택과 같음), head 는 200000 | 충족 |
| 제안 수정 1: `TYPE_FUNC` 분기가 `src->value.funcp` 복사 | `xasl_spawner.cpp:341`, TO-BE 와 같음 | 충족 |
| 제안 수정 2: 함수 인자 목록에 복제한 상수 해제 | `xasl_spawner.hpp:275-286` | 충족 |
| 제안 수정 2: REGEXP_* 사본의 `tmp_obj` 해제 | `xasl_spawner.hpp:287-295`. head 메모리 모니터 `query_opfunc.c:7445/7446` 0 B | 충족 |
| 제안 수정 2: RLIKE 사본의 `compiled_regex` 해제 | `xasl_spawner.hpp:296-305`. merge-base 는 질의당 144 B 누적, head 0 B | 충족 |

연관 이슈: CBRD-25717 (Relates) 은 원인 줄을 넣은 변경이다. 같은 결함을 기술한 다른 링크 이슈는 없다.

## TC PRs

기준: 엔진 PR 에 검증 표가 없고 test.md 도 없으므로, PR 본문의 두 문제(함수 노드 NULL, RLIKE 패턴 미해제)와 해제 3종을 시나리오로 본다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 함수(ELT) 조인 조건, 병렬 probe (이슈 질의) | #3783 Case 1, Case 4 (LEFT OUTER JOIN ON 절) | 통과 |
| 함수(ELT) 조인 조건, 병렬 파티션 | Case 5 | 통과 |
| REGEXP_* (`tmp_obj` 패턴 + 상수 인자 해제) | Case 2 (probe), Case 6, 7 (파티션, ON 절) | 통과 |
| RLIKE 패턴 해제 | Case 3 (경로 실행. 누수는 결과에 드러나지 않는다고 본문에 명시) | 통과 |

TC 파일 검토:
- `sql/_13_issues/_26_2h/cases/cbrd_27651.sql` 과 answer 가 짝을 이루고, header 주석에 `;` 가 없다. 위치도 Correct Error 규칙에 맞다.
- 케이스마다 병렬 결과와 `no_parallel_hash_join` 결과를 함께 남기고, `show trace` 로 병렬 실행을 보인다(숫자는 CTP 가 마스킹).
- 본문의 "수정 없는 빌드에서 Case 1 서버 종료로 NOK" 주장은 merge-base 실행과 일치한다(Case 1 부터 `Error:-190`, 코어 1개).
- private-ex #4461 은 변경이 없다. 닫으면 되고 따로 리뷰할 것이 없다.

판정: #3783 승인.

## Runtime Verification

- CI(gha-ci): build debug/release pass.
  - 38878706095 sql(TC `050c15fb5`): 전체 pass. shard 03 이 head `60b6acc88` optdebug 로 `cbrd_27651` ok(657ms). medium 도 pass.
  - shell: 38878706095 에서 2건 fail(`cbrd_27077`, `bug_bts_4321_2`), 그 2건만 다시 돈 39077121036 에서 pass.
- 빌드는 CI optdebug tarball 을 썼다.
  - head: 11.5.0.2684-60b6acc, libcubrid.so sha256 `cba44a6b`
  - merge-base: 11.5.0.2683-4adcd40, `4a60dfc5`
- smoke(csql -C, job 마다 새 DB 와 서버, install 기본 conf):
  - JIRA repro: merge-base Line 5 서버 종료, head 200000 / 200000.
  - 함수 형태 6종(ELT 상수 문자열 인자, 부질의 인자, IN 목록, JSON_EXTRACT/JSON_OBJECT, REGEXP_REPLACE, REGEXP_LIKE): head 병렬 결과 = 직렬 결과.
  - `enable_memory_monitoring=yes` + `cubrid memmon`: RLIKE 병렬 질의 1회 / 6회 뒤 `string_regex.cpp:279` 가 merge-base 144 B / 864 B, head 0 B / 0 B. REGEXP_LIKE 는 head 에서 0 B.
  - 상관 부질의 안의 해시 조인을 직렬 -> 병렬 순서로 실행해 원본 `tmp_obj` 가 채워진 채 사본을 만드는 경우를 찾았으나, 상관 부질의에서는 해시 조인이 병렬로 실행되지 않아 도달하지 않는다.
- TC A/B(`just ctp sql _13_issues/_26_2h/cases/cbrd_27651.sql`, PR=8188, tc `050c15fb5`):
  - merge-base: NOK. Case 1 에서 서버 종료, 이후 모든 문장 `Error:-190`. 코어 frame 0 `qdata_evaluate_function` <- `hjoin_eval_pred`.
  - head: OK. result 가 answer 와 같다(294줄).
