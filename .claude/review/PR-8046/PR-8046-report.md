# PR #8046 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8046](https://github.com/CUBRID/cubrid/pull/8046)
**제목:** [CBRD-27492] Fix MERGE hanging forever in the parallel sort of its internal GROUP BY
**작성자:** shparkcubrid
**HEAD SHA:** `9ed7c4a22` (develop merge-base `0d0809963`, 커밋 2개)
**JIRA:** CBRD-27492 (Correct Error, Confirmed) / 연관: CBRD-27496
**TC PR:** CUBRID/cubrid-testcases#3599 (`tc/pr-8046` `0cd186eb2`) / cubrid-testcases-private-ex `tc/pr-8046` (PR 없음, develop 대비 변경 없음)
**리뷰 일시:** 2026-10-01
**리뷰 결정:** 엔진 PR #8046 Approve + 코멘트 / TC PR #3599 Approve (코멘트 없음). 2026-10-01 제출: review 5376190637 (#8046), 5376190957 (#3599)

> **TL;DR** (Non-blocking): 결함은 고쳐졌다. MERGE가 만든 SELECT는 계획 단계에서 병렬이 꺼지고, sysop(system operation, 트랜잭션 안의 원자 구간) 안에서는 `compute_parallel_degree()`(병렬도 결정 함수)가 직렬을 돌려준다. CI와 base/head A/B 실행이 교착이 사라진 것을 확인한다. 남은 것은 Non-blocking 하나다. 병렬 index scan은 이 판정을 거치지 않는데, PR 설명은 "모든 병렬 결정"을 막는다고 적었다.

## Summary

- **변경 요약**: `PT_SELECT_INFO_IS_MERGE_QUERY` SELECT는 `xasl->parallelism = 0`. 현재 트랜잭션이 sysop 안이면 `compute_parallel_degree()`가 0(직렬)을 반환
- **주요 이슈**: 병렬 index scan(`scan_start_parallel_index_scan`)은 게이트 밖에 있어 PR 설명의 적용 범위와 다름(MERGE 범위는 scan checker가 막음)
- **확인 필요 사항**: CBRD-27496을 같은 결함으로 연결하고 함께 해결 처리할지, 회귀 원인에 CBRD-27326도 적을지

---

## Findings

### Non-blocking (should consider)

1. `src/query/parallel/px_parallel.cpp:45-47` — 병렬 index scan은 `compute_parallel_degree()`를 거치지 않고 워커를 예약한다. 주석("the check gates every parallel degree decision")과 PR 본문("워커를 띄우는 모든 결정이 이 함수를 지나므로")은 이와 다르다.
   - 근거: `px_scan.cpp:1380-1414`는 `num_parallel_threads = spec->num_parallel_threads`로 차수를 정하고 `try_reserve_workers()`를 바로 부른다. 이 워커도 결과 list file을 써서(`px_scan_result_handler.cpp:246`) 같은 temp 파일 경로를 탄다.
   - MERGE 범위는 문제없다. `px_scan_checker`가 MERGE 하위 XASL(서버 실행 계획)의 모든 spec에 `ACCESS_SPEC_FLAG_NO_PARALLEL_SCAN`을 강제한다.
   - 요청: 설명 범위를 정정하거나, index scan 경로에도 같은 판정을 넣는다(작성자 선택).
2. `src/query/parallel/px_parallel.cpp:204` — namespace 끝에 변경과 무관한 빈 줄이 추가됐다. (NIT)

### Questions for the author

1. CBRD-27496(QA 보고, 원인 커밋 CBRD-27326으로 bisect)은 같은 결함이다. base에서는 같은 스택으로 멈췄고, head에서는 13만 행 MERGE가 끝났다(Runtime Verification B). PR 본문과 JIRA에 연결하고 함께 해결 처리하는지 확인이 필요하다. 회귀 원인도 두 커밋이 겹친다. CBRD-27177은 해시 포기 뒤 정렬을 병렬 대상에 넣었고, CBRD-27326은 정렬 진입 문턱을 2048에서 256 페이지로 낮췄다. PR 본문의 "CBRD-27177 이후"에 CBRD-27326도 함께 적는 것이 정확하다.

## JIRA -> Engine PR

승인 기준: (1) JIRA Expected Result가 JIRA 재현 조건 그대로 충족된다. (2) design.md의 변경 항목이 구현됐거나, 이탈한 이유가 PR에 적혀 있다. (3) design.md의 미정 항목이 해소됐거나, 남은 이유가 적혀 있다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| Expected Result (기본 conf 15만 행, test_mode 1만 행) | test_result.md T2 69.1s 150000 rows, T1 8.6s 10000 rows, A/B에서도 head 통과 | 충족 |
| design 변경 1: MERGE SELECT `parallelism = 0` | 그대로 구현 | 충족 |
| design 변경 2, 3: 정렬/hash join 착수 지점 가드 | `compute_parallel_degree()` 한 곳으로 이동, PR 본문에 사유 | 충족 (design.md 본문은 갱신 안 됨) |
| design 미정: 동기화 계약 주석 | 주석 추가 | 충족 |
| design 미정: 병렬 subquery/scan 가드 감사 | subquery는 도달 불가로 설명, heap/list scan은 게이트 경유 | 부분 (Finding 1, index scan) |

판정: 충족. 티켓 의도(MERGE가 끝나고 건수가 직렬과 같음)는 달성됐다. 리뷰어 판단: sysop과 엮인 작업 중에는 병렬 질의를 하지 않는 것이 근본적으로 맞는 처리이고, MERGE의 SELECT를 직렬로 막는 것도 맞다.

## TC PRs

승인 기준: 검증 시나리오 각각이 JIRA test.md에 있거나, TC PR 두 개(cubrid-testcases, cubrid-testcases-private-ex) 중 하나에라도 언급돼 있으면 통과.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| T1 UPDATE 1만 행 (test_mode) | test.md T1, #3599 Case 1 | 통과 |
| T2 기본 conf 15만 행 | test.md T2 | 통과 |
| T3 parallelism=1 직렬 기준 | test.md T3 | 통과 |
| T4 재시작부터 3회 | test.md T4 | 통과 |
| T5 UPDATE+INSERT | test.md T5, #3599 Case 2 | 통과 |
| X1 USING derived table + ORDER BY (정렬 게이트) | #3599 Case 3 (test.md에는 없음) | 통과 |
| X2 USING derived table + USE_HASH (hash join 게이트) | #3599 Case 4 (test.md에는 없음) | 통과 |
| 결정적 재현 (재시작 직후 + 클라이언트 타임아웃) | test.md 실행 레시피 (TC 배치: private-ex shell) | 통과 |

- #3599 내용: `sql/_36_guava/cbrd_27492` 4 cases다. 헤더 주석에 세미콜론이 없고, answer가 head 실행의 `.result`와 바이트 단위로 같다. sql 카테고리에서는 앞선 케이스가 남긴 temp 파일 때문에 결함이 가려질 수 있다. 이 한계는 TC PR 본문에 적혀 있다.
- private-ex `tc/pr-8046`: develop 대비 변경이 없고 PR도 없다(봇의 PR 생성 실패, TC Merge Gate: "holds nothing develop lacks"). 엔진 PR 본문이 예고한 결정적 shell TC는 test.md 레시피로 갈음한다.

판정: 통과.

## Runtime Verification

이 리뷰는 CUBRID 빌드와 리뷰용 TC 실행을 허용한다. 이미 있는 증거는 다시 돌리지 않았다.

- CI (gha-ci): debug/release 빌드 통과. sql/medium 통과(run 36686232790), shell 통과(run 36817553367 rerun). sql shard 09는 `9ed7c4a22` + `tc/pr-8046` `0cd186eb2` 조합이고, `cbrd_27492.sql`이 ok(6800ms)였다.
- 로컬 A/B: CI debug 슬롯의 tarball 두 개(base `0d0809963`, head `9ed7c4a22`)를 CTP 컨테이너에서 돌렸다. 둘 다 실제로는 optdebug 빌드이고 `libcubrid.so` 해시가 서로 다르다. 실행마다 새 서버이고 parallelism=4, test_mode=yes다. 5개 실행은 2026-10-01 06:41-06:48 UTC에 동시에 돌았다.

| 실행 | 내용 | base | head |
|---|---|---|---|
| A | 새 TC `_36_guava/cbrd_27492` (`tc/pr-8046`) | 첫 MERGE에서 멈춤, hang watchdog(ctp-run이 무출력 shard의 스택을 남기고 멈춤, 150s)이 중단 | OK (10.9s), `.result`가 answer와 바이트 단위로 같음 |
| B | CBRD-27496 재현 SQL (첨부 repro.sh 그대로, review-only 임시 케이스) | 첫 MERGE에서 멈춤, watchdog(300s)이 중단 | 끝남. MERGE 131072 rows, si 200-500의 v가 102-105로 갱신 |
| C | `_06_merge_statement` 50 cases, `_20_adhoc_merge_1.sql` 포함 | (실행 안 함: develop에서 멈추는 것으로 알려짐) | 50/50 OK |

- A, B base의 스택은 같다. 리더는 `sort_listfile` <- `qexec_groupby` <- `qexec_execute_update` <- `qexec_execute_merge`에서 기다린다. 워커 1개는 `rmutex_lock` <- `log_tdes::lock_topop` <- `log_sysop_start` <- `disk_reserve_sectors(TEMP)` <- `file_create` <- `sort_run_flush`에서 막혔고, 나머지 워커는 `file_tempcache_lock_tran_entry`에서 기다린다. A base에서 MERGE 트랜잭션은 lock 10010개(t2 행 X_LOCK 10000개)를 쥐고 대기자는 없었다. JIRA 본문의 스택, lock 상태와 같고, CBRD-27496이 같은 결함임을 보여준다(Question 1).
- B head의 NOK는 placeholder answer 때문이다. `.result`의 건수가 위 판정의 근거다.
- 정리: 실행 디렉터리와 내려받은 빌드는 지웠다. 스택, provenance, `.result`는 `.git_ignored_dir/scratch/pr8046/evidence/`에 있다.
