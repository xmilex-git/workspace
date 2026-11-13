# PR #6466 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#6466](https://github.com/CUBRID/cubrid/pull/6466)
**제목:** [CBRD-25984] Support covered index scan and key filter on function indexes
**작성자:** HyunukLee
**HEAD SHA:** `05b46aefe` (develop merge-base `4e389935d`)
**JIRA:** CBRD-25984 (Improve, Open) / 연관: CBRD-26266 (Relates)
**TC PR:** CUBRID/cubrid-testcases#3865 (`tc/pr-6466` `059fbce8e`) / CUBRID/cubrid-testcases-private-ex#4551 (draft, `57910d7f4`)
**리뷰 일시:** 2026-11-04
**리뷰 결정:** 엔진 PR Request changes (top-level + greptile 스레드 답글 2) / TC #3865 Comment (MRO 꼴 추가) / TC #4551 리뷰 없음(draft)

> **TL;DR** (Blocking): greptile 이 짚은 MRO(다중 범위 최적화) 경로가 실제로 깨집니다. 함수 인덱스 `(i, j, sqrt(d))` 에서 `select j, sqrt(d) from t where i in (1, 2) order by j limit 5` 가 develop 에서는 5행, 이 PR 에서는 `Query execution failure`(-495)입니다. 그 스레드는 아직 답이 없고, TC 에 이 꼴이 없습니다.

## Summary

- **변경 요약**: 함수 인덱스 키에 저장된 함수 결과를 예약 attr id `FUNC_INDEX_RESULT_ATTRID`(-2)로 읽어, 함수식을 쓰는 질의도 커버드 인덱스 스캔과 키 필터를 쓴다.
- **주요 이슈**: MRO + 커버링에서 질의 실패(기존 greptile 스레드, 재현 확인).
- **확인 필요 사항**: 비커버링 키 필터에 대한 PR 본문 문장, JIRA Implementation 절 갱신.

---

## Findings

### Non-blocking (should consider)

- TC `sql/_36_guava/cbrd_25984/cases/cbrd_25984.sql` — MRO 를 타는 꼴(`where <선행 키> in (...) order by <다음 키> limit N` 또는 `for orderby_num () <= N`)이 없다. 그래서 이 PR 의 CI 가 위 실패를 잡지 못했다. 고친 뒤 이 꼴과 `NO_COVERING_IDX` 대조를 넣는 것이 맞다.
- TC 같은 파일 머리 주석 23·37행에 `;` 가 있다(`... PASS / FAIL; plans are dumped ...`, `Sizing: 20 rows are enough; every scan ...`). 이번 답안은 영향 없음.

### Questions for the author

- JIRA Implementation 절이 헤드 코드와 다르다. 적힌 `pt_get_func_index_cover_arg`, `pt_add_func_index_result_col`, `pt_get_func_index_result_col`, `pt_retype_func_index_result_slot`, `qo_seg_used_only_in_covering_func_index`, `cover_func_result` 는 헤드에 하나도 없다(`rg` 0건). "함수 인자가 일반 키 컬럼으로도 존재하면 라우팅하지 않는다" 는 `74326dd77`(인자가 키에 있는 `(d1, sqrt(d1))` 도 키에서 읽음)과 반대다.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Q2, Q4 가 커버드 + 키 범위/필터 | TC 재기준선 `(covers)`, `filtr:` / 로컬 `(covers) filtr: term[0]` | 충족 |
| 커버링 결과가 `NO_COVERING_IDX` 와 항상 같음 | cbrd_25984 PASS, 로컬 병렬 커버링 NUMERIC 합 같음 | 부분 (MRO 꼴은 질의 실패) |
| 비함수 인덱스·CONNECT BY·skip scan 회귀 없음 | CI sql·medium·shell OK | 충족 |
| GROUP BY/집계 정확(비커버링 폴백) | 로컬 `count(*), max(j)` 가 `sargs` 폴백, 결과 같음 | 충족 |
| 요구사항 2 "키 필터 사용 가능" | 커버링일 때만. 비커버링 `select p ...` 는 develop 처럼 `sargs` | 부분 (greptile P2) |
| Implementation 절 | 함수명·라우팅 조건이 헤드와 다름 | 부분 (Question 1) |

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 커버링+키 필터(2컬럼/단일/다중 인자), 금지 꼴, UPDATE/DELETE/FOR UPDATE, `(d1, sqrt(d1))`, 클릭 카운터·CONNECT BY·merge/hash 입력 | #3865 `cbrd_25984` | 통과 |
| 기존 답안 재기준선 9건(플랜 주석만) | #3865 diff: `(covers)`, `sargs` -> `filtr`, `covered: true` 만 바뀜 | 통과 |
| shell `bug_bts_7459` 플랜 주석 | #4551 `result.txt` 2줄 | 통과 |
| MRO + 커버링 | 없음 | 누락 (Non-blocking 1) |

## Runtime Verification

- CI gha-ci run 41765316148 (head `05b46aefe`, debug, `tc/pr-6466` `059fbce8e` / private-ex `57910d7f4`): sql 17721·medium 975·shell 3538 모두 OK.
- 로컬 SA (CI debug tarball head vs develop `4e389935d`): `(i, j, sqrt(d))` 2000행, `i in (1, 2)` + `order by j` 의 `for orderby_num () <= 5`, `limit 5`, `and sqrt(d) > 10 ... limit 5` 세 문장이 head 에서 `index: idx_t term[0] (covers) (multi_range_opt)` 로 계획되고 `Query execution failure #22217`. `NO_COVERING_IDX` 는 5행. develop 은 `(multi_range_opt)` 비커버링으로 5행(셋째 문장은 develop debug 가 `pt_ordbynum_to_key_limit_multiple_ranges` assert — develop 에도 있는 결함).
- 로컬 review-only CTP (CS 모드, JDBC): 같은 두 MRO 문장이 head `Error:-495`, develop 5행. 40만 행 `(i, sqrt(d))` 병렬 커버링(trace `parallel workers` 3줄, `covered: true` 3줄)은 `sum(cast(round(r, 3) as numeric(38,3)))` 161908874.181, `max` 632.4547414637667, 383904행으로 `NO_COVERING_IDX` 와 같음.
- 원인: `scan_dump_key_into_tuple ()`(`scan_manager.c:8864-8865`)가 `btree_attrinfo_read_dbvalues ()` 에 `func_index_col_id` 로 `-1` 을 넘겨, `FUNC_INDEX_RESULT_ATTRID` 분기(`btree.c:20606`)를 건너뛰고 일반 attr 목록에서 찾다 실패한다. 병렬 leaf walker 는 `isidp->indx_cov.func_index_col_id` 를 넘긴다.

## Existing Comments

| 코멘트 | 상태 |
|---|---|
| greptile P1 `btree.c:20612` MRO 에서 함수 인덱스 조회 실패 | 답 없음. 위 재현으로 확인(Blocking) |
| greptile P2 `xasl_generation.c:16147` 비커버링 키 필터는 여전히 막힘 | 답 없음. 비커버링 `select p from t where i = 1 and sqrt(d) > 44` 는 head·develop 모두 `sargs: term[0]`. PR 본문 "키 필터 식은 커버링 여부와 무관하게" 와 다름 |
