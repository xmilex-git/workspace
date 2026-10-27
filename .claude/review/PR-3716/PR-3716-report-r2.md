# PR #3716 코드 리뷰 보고서 (2차)

**PR:** [CUBRID/cubrid-testcases#3716](https://github.com/CUBRID/cubrid-testcases/pull/3716)
**제목:** [CBRD-27404] Add new test case for parallel index and list scans in sort-merge join inputs
**작성자:** HyunukLee
**HEAD SHA:** `cc6695a3a` (1차 리뷰 `201dfe74e` 이후 커밋 2개: `c4a1fbf71`, `cc6695a3a`)
**JIRA:** CBRD-27404 (Sub-task, Resolved; 엔진 CUBRID/cubrid#7909 `b9275d0bd` 머지) / 연관: CBRD-27307 (#7795 `4781495f0`, 2026-10-26 develop 머지)
**TC PR:** sql 이 PR / shell 없음 (private-ex 봇 draft #4117 변경 0파일로 닫힘, `tc/CBRD-27404` 브랜치 없음)
**리뷰 일시:** 2026-10-27
**리뷰 결정:** Approve (review 5661357672, 2026-10-27, 사용자 "전부다 approve해"). 엔진 PR 은 머지돼 게시 없음

> **TL;DR** (Blocking): 1차 지적 3건과 Greptile 2건은 모두 반영됐다. 그런데 답지가 최신 develop `af0a9cdee` 에서 NOK 다. 10-23 머지된 CBRD-27727 과 10-26 머지된 #7795 가 trace 7줄을 바꿨고, 작성자가 10-23 에 약속한 답지 재생성이 아직 없다.

## Summary

- **변경 요약**: 1차 이후 데이터 3배 (120000행, 인덱스 113/109페이지), Case 2/4 체크섬을 키 합과 `d1.p = d2.p` 건수로 교체, Case 3 trace 추가, non-covered 입력 Case 5 추가, 비교문 바깥 `NO_PARALLEL_SUBQUERY`
- **주요 이슈**: develop 답지 불일치 (값과 PASS 행은 같음)
- **확인 필요 사항**: 재생성한 답지에서 Case 2 `GROUPBY` 병렬 줄이 실행마다 같은지

---

## Findings

### Blocking (must fix)

1. `answers/cbrd_27404.answer` -- develop `af0a9cdee` optdebug 에서 diff 5 hunk, 23줄. 값과 PASS 5행은 같다.
   - `MERGELIST` 5줄 -> `MERGELIST (parallel merge workers: ?)`: #7795 (CBRD-27307) 가 merge 자체를 병렬화했다. 작성자 10-23 코멘트가 예고한 변화다.
   - Case 2 의 두 GROUP BY 파생 테이블 아래 `(parallel workers: ?, time: ?..?, page: ?..?, ioread: ?..?)` 2줄 추가: CBRD-27727 (`0bbd04149`) 이 heap 병렬 스캔이 해시 집계를 포기한 GROUP BY 의 정렬도 병렬로 돌리게 했다 (`hash: partial`).
   - 이대로 머지하면 develop CTP 에서 이 케이스가 매번 NOK 다.

### Questions for the author

2. Case 2 의 GROUPBY 병렬 줄은 정렬 입력 크기와 워커가 남긴 partial 수에 따라 붙는다 (CBRD-27727). 재생성한 답지를 2-3회 돌려 같은지 확인할지, 이 줄이 이 TC 의 대상이 아니므로 파생 테이블에 `no_hash_aggregate` 를 넣어 흔들림을 없앨지.

## JIRA -> Engine PR

| 항목 | PR 상태 (#7909) | 판정 |
|---|---|---|
| 설계: `block_parallel_index_and_temp_in_subtree` 선언/정의/호출 제거 | diff 41줄 삭제, 일치 | 충족 |
| 설계: merge 자신의 `outer_spec_list`/`inner_spec_list` 차단 유지 | MERGELIST case 의 `ACCESS_SPEC_FLAG_NO_PARALLEL_SCAN` 유지 | 충족 |
| AC1 입력 trace 에 parallel 줄, ORDERBY sort 유지, MERGELIST 직렬 | TC Case 1-5 trace. "MERGELIST 직렬" 은 이후 #7795 가 바꿨다 (이 PR 범위 밖) | 충족 |
| AC2 결과 = `NO_PARALLEL_SCAN` / `USE_NL` | TC PASS 5행 (NL 대신 키별 건수 정답, 이유 본문에 있음) | 충족 |
| AC3 parallel scan CTP 회귀 없음 | 엔진 PR CI | 충족 |

엔진 PR 새 발견 없음. 엔진 PR 은 2026-09-14 머지됐다.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| I1 covered index 입력 | Case 1 | 통과 |
| L1 GROUP BY 파생 테이블 list 입력 | Case 2 (키 합 + `d1.p = d2.p` 건수) | 통과 |
| N1 nullable 키 | Case 3 (index, trace), Case 4 (NULL 그룹이 list 입력에 들어감) | 통과 |
| S1 non-covered 입력 | Case 5 (`lookup time`) | 통과 |

1차 Finding 1-3 과 Greptile 4254104682 / 4254104689 반영 확인. 크기: 인덱스 3.5배, list 85/110페이지 (2.7/3.4배). 판정: 내용 통과, 답지 재생성 필요.

## Runtime Verification

- develop `af0a9cdee` gha-ci optdebug (run 40427958294, `libcubrid.so` sha256 `709d9c5a`), `just ctp sql _36_guava/cbrd_27404`, TC `tc/CBRD-27404` `cc6695a3a8a4` (provenance): **NOK**, 코어 0, assert 0. diff 는 위 1번.
- 증거: `.git_ignored_dir/scratch/pr3716/evidence-r2/` (result, answer, diff, provenance). 실행 디렉터리 삭제.
