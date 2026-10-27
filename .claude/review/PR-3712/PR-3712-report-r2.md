# PR #3712 코드 리뷰 보고서 (2차)

**PR:** [CUBRID/cubrid-testcases#3712](https://github.com/CUBRID/cubrid-testcases/pull/3712)
**제목:** [CBRD-27060] Add new test case for parallel index scan on filtered indexes
**작성자:** HyunukLee
**HEAD SHA:** `7a694ad38` (1차 리뷰 `bb3ada018` 이후 커밋 2개)
**JIRA:** CBRD-27060 (Improve, Resolved; 엔진 CUBRID/cubrid#7467 `25d3f4d3f` 머지) / 연관: CBRD-26722
**TC PR:** sql 이 PR / shell 없음 (private-ex 봇 draft #3645 변경 0파일로 닫힘, `tc/CBRD-27060` 브랜치 없음)
**리뷰 일시:** 2026-10-27
**리뷰 결정:** Approve (review 5661357578, 2026-10-27, 사용자 "전부다 approve해"). 엔진 PR 은 머지돼 게시 없음

> **TL;DR** (Non-blocking): 1차 지적 3건 (헤더 autocommit 문구, list-scan 경로, 수정 전 결과)과 Greptile 라벨 지적이 모두 반영됐다. 최신 develop `af0a9cdee` optdebug 에서 OK, 답지와 byte 동일, 코어 0. 남은 발견 없음.

## Summary

- **변경 요약**: 헤더 `(auto-commit disabled)` 로 첫 drop 블록 복구 (블록 71 = 문장 71), 행 반환 Case 8/16 과 `gather: mergeable list` trace 2개 추가, Case 4/12 라벨 정정, covering 인덱스 `idx_flt_cov`
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음

---

## Findings

없음

## JIRA -> Engine PR

| 항목 | PR 상태 (#7467) | 판정 |
|---|---|---|
| 설계: `check<false>` 의 filtered-index 게이트, `is_filtered_index()`, 전용 include 2개 제거 | diff 일치 (단일 파일, 순수 삭제) | 충족 |
| 전제: 엔트리 레벨 MVCC pre-filter 가 leaf / overflow 두 수집 경로에 있음 | `25d3f4d3f` 의 `collect_oid_callback`, `ovf_collect_oid_callback` 가 `snapshot_fnc` 로 거름 | 충족 |
| AC1 covering / non-covering / 전범위 / 부분 범위 / desc / list-scan 병렬 = 직렬 | TC Case 1-8, 9-16 | 충족 |
| AC2 필터 이탈 UPDATE 후 stale 엔트리 | TC Case 9-16 (열린 트랜잭션) | 충족 |
| AC3 회귀 없음 | 엔진 PR CI | 충족 |

엔진 PR 새 발견 없음.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| AC1 각 경로 | Case 1-8 + 플랜 trace 8개 | 통과 |
| AC1 행 반환 (list-scan) | Case 8/16, trace `gather: mergeable list` | 통과 |
| AC2 stale 엔트리 | Case 9-16 | 통과 |

`autocommit` 문자열은 단독 `autocommit off;` / `autocommit on;` 두 줄에만 남았다. 판정: 통과.

## Runtime Verification

- develop `af0a9cdee` gha-ci optdebug (run 40427958294, `libcubrid.so` sha256 `709d9c5a`), `just ctp sql _36_guava/cbrd_27060`, TC `tc/CBRD-27060` `7a694ad380d1` (provenance): OK 6492ms, `.result` = 답지 (cmp 동일), 코어 0.
- 증거: `.git_ignored_dir/scratch/pr3712/evidence-r2/`. 실행 디렉터리 삭제.
