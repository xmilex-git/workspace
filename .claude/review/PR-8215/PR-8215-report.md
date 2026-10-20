# PR #8215 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8215](https://github.com/CUBRID/cubrid/pull/8215)
**제목:** [CBRD-27670] Skip a partition with no value when merging MIN/MAX across partitions
**작성자:** beyondykk9
**HEAD SHA:** `5805911` (develop merge-base `423e57f`)
**JIRA:** CBRD-27670 (Correct Error, Analysis) / 연관: CBRD-24436 (Regress 원인), workspace #442 (최초 보고)
**TC PR:** CUBRID/cubrid-testcases#3813 (`tc/pr-8215` `7ace4ff`, 변경 파일 없음) / cubrid-testcases-private-ex#4498 (`5a36b00`, 변경 파일 없음)
**리뷰 일시:** 2026-10-20
**리뷰 결정:** 엔진 PR Approve (인라인 코멘트 없음) / TC PR #3813, #4498 리뷰 없음

> **TL;DR** (Non-blocking): #442에서 제기한 문제(값이 없는 파티션이 있으면 인덱스 MIN이 NULL이나 틀린 값을 냄)는 해결되었다. merge-base/head optdebug A/B에서 #442의 모든 재현이 SA/CS 모두 고쳐졌고, #442 밖의 7가지 형태도 head에서 정상이다. 엔진 코드 지적은 없다. 회귀 TC는 없지만 (TC 판정 미충족) 작성자에게 요청하지 않기로 했다.

## Summary

- **변경 요약**: `qdata_evaluate_aggregate_hierarchy` (파티션별 인덱스 MIN/MAX 값을 하나로 합치는 함수)에서 파티션 결과가 NULL이면 비교하지 않고 건너뜀
- **주요 이슈**: 없음 (엔진 코드)
- **확인 필요 사항**: 없음

---

## Issue #442

#442 본문과 코멘트의 항목별 결과. 원인: 인덱스 MIN/MAX 최적화 (CBRD-24436, WHERE 없는 MIN/MAX를 각 파티션 인덱스의 첫/끝 키로 구함)가 파티션 결과를 `tp_value_compare (..., total_order=true)` (NULL을 가장 작은 값으로 보는 비교)로 합쳐서, 값이 없는 파티션의 NULL이 최소값을 덮어씀.

| #442 항목 | merge-base `423e57f` | head `5805911` | 판정 |
|---|---|---|---|
| 본문 repro: p2, p4 비어 있음 `min(i), max(i)` | NULL, 25 | 1, 25 | 해결 |
| 본문 repro: 35 추가 후 (p2만 비어 있음) | 25, 35 | 1, 35 | 해결 |
| 코멘트: 인덱스 컬럼이 모두 NULL인 파티션 (`pn`) | 25, 25 | 1, 25 | 해결 |
| c71 타입: DATETIMELTZ, VARCHAR `utf8_en_ci` MIN | NULL, NULL | 2019-01-01, 'a' | 해결 |
| SA와 CS 모두 재현 | SA = CS (틀림) | SA = CS (정상) | 해결 |
| 미확인 항목: WHERE 있는 MIN (`i is not null`, `i < 30`, `i > 0`, `j > 0`) | 정상 | 정상 | 영향 없음 (최적화 경로 밖) |
| 제안한 수정: 병합에서 NULL 누적값을 건너뜀 | - | 그대로 채택 | 일치 |

#442 밖의 형태도 head에서 모두 정상: list 파티션 가운데 빈 파티션 (`'x'` -> `'b'`), DESC 인덱스 (NULL -> 1), 복합 인덱스 `(i, j)`에서 첫 컬럼이 NULL인 키만 있는 파티션 (25 -> 1), 삭제된 키만 남은 파티션 (MVCC (다중 버전 동시성 제어) 상 안 보이는 키, 25 -> 1), 모든 파티션이 빈 경우 (NULL 유지), 첫 파티션이 빈 경우와 hash 파티션 (변화 없음). 매 형태마다 head 결과가 전체 스캔 기준값 (`min(i+0)` 등)과 같다.

수정이 #442 전체를 덮는 이유: 파티션 결과가 NULL이 되는 경우는 `btree_find_min_or_max_key`가 보이는 non-NULL 첫 컬럼 키를 못 찾은 경우뿐이므로 (빈 파티션, 모두 NULL, 모두 삭제), NULL을 "값 없음"으로 건너뛰는 것이 정확하다. total order 비교로 병합하는 곳은 이 함수의 두 줄뿐이고 호출자는 `qexec_evaluate_partition_aggregates` 하나다. MAX 쪽 변경은 동작이 같다 (total order에서 NULL은 `DB_GT`가 될 수 없음, all-NULL 마지막 파티션에서 base/head 모두 MAX 9).

## Findings

없음

## JIRA -> Engine PR

JIRA에 `design.md`/`test.md` 첨부가 없어 (Analysis 상태) Expected Result와 Additional Information만 기준으로 삼았다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result: 첫 SELECT `1, 25` | head SA/CS `1, 25` (base `NULL, 25`) | 충족 |
| Expected Result: 두 번째 SELECT `1, 35` | head SA/CS `1, 35` (base `25, 35`) | 충족 |
| Additional: all-NULL 파티션 `pn` -> `1, 25` | head `1, 25` (base `25, 25`) | 충족 |
| Additional: WHERE 있으면 정상 | base/head 모두 `1` | 충족 |

같은 결함을 다루는 다른 JIRA 이슈는 찾지 못했다 (JQL `text ~ partition AND text ~ min`, 2022 이후). CBRD-24436은 원인 이슈다.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| `pt` p2, p4 비어 있음 | TC 없음 (test.md 없음, #3813/#4498 변경 없음) | 미충족 |
| `pt` p2 비어 있음 | TC 없음 | 미충족 |
| `pn` p2의 i가 모두 NULL | TC 없음 | 미충족 |
| list 파티션 `pv` varchar | TC 없음 | 미충족 |
| 모든 파티션이 빈 `pt` | TC 없음 | 미충족 |

TC Merge Gate 봇은 두 저장소 모두 "no TC branch"로 머지를 허용하고 있다. 판정: 미충족 (회귀 TC 필요).

## Runtime Verification

- 빌드: merge-base `423e57f` optdebug (gha-ci develop tarball, run 39352860104, `libcubrid.so` sha256 `0dae08dd`), head `5805911` optdebug (로컬 `just build debug`, sha256 `c30268fe`). 둘 다 `data_buffer_size=512M`.
- Smoke (fresh DB, `fast-sa.sh` csql -S / `fast-cs.sh` csql -C): `s1_issue`, `s2_allnull`, `s3_types`, `s4_edge` 4개 파일. base는 위 표대로 틀리고, head는 모든 쿼리가 기대값 및 전체 스캔 기준값과 같다. SA와 CS 결과가 동일. 근거: `.git_ignored_dir/scratch/pr8215/evidence/`.
- Targeted CTP sql A/B (`just ctp sql`, testcases `tc/pr-8215` `7ace4ff` = develop, pinned `data_buffer_size=512M`): 파티션 테이블에 WHERE 없는 MIN/MAX 문장이 있는 11개 dir, 728건. base/head 모두 PASSED (fail 0, core 0). 기존 정답 중 버그 값을 담은 것은 없다.
- gha-ci: 미실행 (`/run all` 없음). build/test_sql/test_medium 결과 없음.
