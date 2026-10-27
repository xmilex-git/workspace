# PR #3707 코드 리뷰 보고서 (2차)

**PR:** [CUBRID/cubrid-testcases#3707](https://github.com/CUBRID/cubrid-testcases/pull/3707)
**제목:** [CBRD-27205] Add new test case for parallel scan with correlated derived tables
**작성자:** HyunukLee
**HEAD SHA:** `fcbf271ea` (1차 리뷰 `203c1614f` 이후 커밋 3개)
**JIRA:** CBRD-27205 (Sub-task, Resolved; 엔진 CUBRID/cubrid#7794 `46e0abd95` 머지) / 연관: CBRD-27291 (선행)
**TC PR:** sql 이 PR / shell 없음 (private-ex 봇 draft #3990 변경 0파일로 닫힘, `tc/CBRD-27205` 브랜치 없음)
**리뷰 일시:** 2026-10-27
**리뷰 결정:** Approve (review 5661357344, 2026-10-27, 사용자 "전부다 approve해"). 엔진 PR 은 머지돼 게시 없음

> **TL;DR** (Non-blocking): 1차 지적 3건 (Case 5 해시 집계, heap 쪽 두 분기 미검사, 본문 수정 전 결과)과 Greptile 3건이 모두 반영됐다. 최신 develop `af0a9cdee` optdebug 에서 OK, 답지와 byte 동일, 코어 0. 남은 발견 없음.

## Summary

- **변경 요약**: Case 5 에 `no_hash_aggregate` (trace `hash: false`), 인덱스 없는 `t27205` 로 heap 체인 끝 cached scan Case 11, row-by-row fallback 직렬 Case 12 추가, 기존 Case 11 -> 13. Case 8/9/13 trace, Case 10 `count(distinct k)` 보강
- **주요 이슈**: 없음
- **확인 필요 사항**: 없음

---

## Findings

없음

## JIRA -> Engine PR

| 항목 | PR 상태 (#7794) | 판정 |
|---|---|---|
| Expected: 상관 파생 테이블 병렬 = 직렬 | TC Case 2-6, 11, 13 PASS (develop) | 충족 |
| 설계: 워커 행별 dptr 실행 (`qexec_execute_dptr_list` 공용화, 직렬 4곳 + 워커) | diff 일치 | 충족 |
| 설계: 행 종료 정리를 `qexec_clear_scan_all_lists` 로 통일 (sort GROUP BY stale list 결함) | diff 일치, TC Case 10/13 | 충족 |
| 설계: checker `dptr_subtree_worker_safe`, 중첩 병렬 `parallelism = 1` | diff 일치, TC Case 7-9 직렬 trace | 충족 |
| 설계: row-by-row + 비연결 dptr 직렬 (`nonlinked_dptr ||`) | diff 일치, TC Case 12 | 충족 |
| 설계: 체인 끝 inner heap cached scan (`inner_cached_scan`) | diff 일치, TC Case 11 | 충족 |
| 설계: `px_scan.cpp` 의 `XASL_TO_BE_CACHED` 강등 제거 | 이 diff 에 없음. 머지 직전 `46e0abd95^` 에 이미 MERGEABLE 예외가 있어 CBRD-27291 쪽 변경으로 보임 | 해당 없음 (본문 서술만) |
| AC4 parallel scan CTP 회귀 없음 | 엔진 PR CI | 충족 |

엔진 PR 새 발견 없음 (diff 전체 689줄 정독).

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| P1-P5, N1-N3, R1-R2 (JIRA 첨부 설명) | Case 2-10, 13 | 통과 |
| 실버그 2 inner heap cached scan | Case 11 (trace: 바깥 o heap 병렬, 체인 끝 t heap) | 통과 |
| row-by-row fallback + 비연결 dptr 직렬 | Case 12 | 통과 |

Case 11 기대값 검산: o.k 1..1000 마다 t 50행, 합 = 100 x (1+...+500) = 12525000. 수정 전 `a0026f929` 결과는 본문 검증 표에 있음 (Case 10 은 -458 오류로 수정 전을 가름). 판정: 통과.

## Runtime Verification

- develop `af0a9cdee` gha-ci optdebug (run 40427958294, `libcubrid.so` sha256 `709d9c5a`), `just ctp sql _36_guava/cbrd_27205`, TC `tc/CBRD-27205` `fcbf271eace5` (provenance): OK 4655ms, `.result` = 답지 (cmp 동일), 코어 0, assert 0.
- 증거: `.git_ignored_dir/scratch/pr3707/evidence-r2/`. 실행 디렉터리 삭제.
