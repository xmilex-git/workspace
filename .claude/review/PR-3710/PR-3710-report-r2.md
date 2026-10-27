# PR #3710 코드 리뷰 보고서 (2차)

**PR:** [CUBRID/cubrid-testcases#3710](https://github.com/CUBRID/cubrid-testcases/pull/3710)
**제목:** [CBRD-26846] Add new test case for additional aggregate functions on parallel heap scan buildvalue
**작성자:** HyunukLee
**HEAD SHA:** `dd93caaa2` (1차 리뷰 `9c8b6f046` 이후 커밋 1개)
**JIRA:** CBRD-26846 (Improve, Resolved; 엔진 CUBRID/cubrid#7229 `d0b290459` 머지) / 연관: CBRD-26711, CBRD-26982
**TC PR:** sql 이 PR / shell 없음 (private-ex 봇 draft #3384 변경 0파일로 닫힘, `tc/CBRD-26846` 브랜치 없음)
**리뷰 일시:** 2026-10-27
**리뷰 결정:** Approve (review 5661357478, 2026-10-27, 사용자 "전부다 approve해"). 엔진 PR 은 머지돼 게시 없음

> **TL;DR** (Non-blocking): 1차 지적 3건 (AC 누락 시나리오, BIT 머지 데이터, 본문 수정 전 결과)이 모두 반영됐다. 최신 develop `af0a9cdee` optdebug 에서 OK, 답지와 byte 동일, 코어 0. 남은 발견 없음.

## Summary

- **변경 요약**: Case 1/2 에 한 행만 다른 BIT_AND/BIT_OR 추가 (254 / 1), 오류 전파 Case 13-15 (-1172 x2, -1201), 다중 정렬키·NULLS FIRST Case 16, 일부 NULL 컬럼 Case 17
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음

---

## Findings

없음

## JIRA -> Engine PR

| 항목 | PR 상태 (#7229) | 판정 |
|---|---|---|
| AC1 11개 함수가 BUILDVALUE_OPT 에서 동작 | checker 11 case 추가, TC Case 1 trace `gather: buildvalue` | 충족 |
| AC2 병렬 = 직렬 (혼합 집계, 다중 정렬키/NULLS FIRST, PERCENTILE 범위 오류) | TC Case 2-17 | 충족 |
| AC3 크래시/assert 없음, 전체 NULL 컬럼 | TC Case 10, 코어 0 | 충족 |
| 설계: BIT 누적/머지, JSON ARRAYAGG `merge_preserve` 2인자, OBJECTAGG first-wins 신설 함수 | diff 일치 | 충족 |
| 설계: 리스트 기반 집계의 `qfile_copy_list_id`/`qfile_connect_list` 머지, percentile 비율 전파 | diff 일치 (rows 를 읽은 워커만 비율 전파) | 충족 |
| 설계: CUME_DIST/PERCENT_RANK 카운터 합산, 클론 `const_array` 해제 | diff 일치 | 충족 |

엔진 PR 새 발견 없음. 읽은 범위: checker, `db_json.cpp`, `read`/`initialize_node`/`accumulate_node`/`write_finalize` 리스트 머지 경로, `query_aggregate.cpp`. `px_scan_result_handler.cpp` 의 나머지 머지 분기 (BIT/JSON/GROUP_CONCAT 비정렬) 는 훑기만 했다.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| AC1, AC2 혼합 집계, AC3 전체 NULL | Case 1-12 | 통과 |
| AC2 다중 정렬키 / NULLS FIRST | Case 16 | 통과 |
| AC2 PERCENTILE 범위 오류 | Case 13 (상수), 14 (서브쿼리) | 통과 |
| 워커 행 단위 오류 전파 | Case 15 (JSON NULL key, 병렬 trace `gather: buildvalue`) | 통과 |
| BIT 부분값 머지 | Case 1/2 의 254 / 1 | 통과 |

Case 13-15 의 trace 는 오류가 난 그 쿼리의 것이다 (rewritten query 가 일치). 판정: 통과.

## Runtime Verification

- develop `af0a9cdee` gha-ci optdebug (run 40427958294, `libcubrid.so` sha256 `709d9c5a`), `just ctp sql _36_guava/cbrd_26846`, TC `tc/CBRD-26846` `dd93caaa2de8` (provenance): OK 1328ms, `.result` = 답지 (cmp 동일), 코어 0. 서버 로그 오류는 케이스가 의도한 -1204/-1172/-1201 뿐.
- 증거: `.git_ignored_dir/scratch/pr3710/evidence-r2/`. 실행 디렉터리 삭제.
