# PR #8353 재리뷰 보고서 (r2)

**PR:** [CUBRID/cubrid#8353](https://github.com/CUBRID/cubrid/pull/8353)
**제목:** [CBRD-27862] A B-tree node search of a single-column integral index compares key images
**작성자:** soheejung-cs
**HEAD SHA:** `f36182bbf` (이전 리뷰 6b0ca5566 APPROVE -> 69fca24fc에서 dismissed)
**JIRA:** CBRD-27862 / 후속 CBRD-27900(다른 정수형 검색 키)
**TC PR:** CUBRID/cubrid-testcases#3969 (`315fab74e`) / private-ex#4679 (빈 draft)
**리뷰 일시:** 2026-11-05
**리뷰 결정:** 엔진 Approve(5779594855), TC #3969 Approve(5779594955)

> **TL;DR** (Non-blocking): 새 커밋 fde931c33은 HyunukLee 지적대로 leaf 키 오프셋을 `btree_leaf_record_key_offset ()` 하나로 묶고, debug에서 이미지 비교 답을 `btree_compare_bound_key ()` 답과 대조하는 assert를 넣었다. 이 assert가 켜진 optdebug CI 전 suite가 통과한다. TC는 내가 요청한 `coalesce` 가 반영됐다.

## Summary

- **변경 요약(r1 이후)**: 오프셋 헬퍼 공유, debug 대조 assert(`btree_integral_search_key_check`), 본문 적용 범위(SHORT는 SHORT 검색 키일 때만) 보강.
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음

---

## Findings

없음

- 확인한 것: 판독기의 단계별 `or_advance` 4번이 한 번으로 바뀌어도 레코드 길이 검사는 그대로. leaf 대조는 `btree_compare_bound_key (..., bound->compares, ...)`로 else 분기의 `btree_compare_search_key`와 같은 함수(래퍼)다. non-leaf는 `nonleaf_compares`로 else 분기와 같다.

## TC PRs

- #3969: 9151fea4b에서 rng_* 다섯 검사 양쪽 `coalesce (sum (id), 0)` 반영(내 r1 요청). 답안 변화 없음.
- HyunukLee의 TC 스레드 2건(CLASS_OID 분기 상속 케이스, 같은 트랜잭션 안 INSID/DELID)은 TC에 답이 없다. 작성자는 엔진 스레드에 debug assert로 그 경우를 돌렸다고 답했다. HyunukLee 스레드라 내가 다시 올리지 않는다.
- 판정: Approve.

## Runtime Verification

- gha-ci run 41812044809 (head f36182bbf, optdebug, tc 315fab74e): sql 17,730 / medium 975 / shell 3,540 모두 pass. 새 debug 대조 assert가 전 suite에서 한 번도 안 남.
- 새로 돌린 것 없음.
