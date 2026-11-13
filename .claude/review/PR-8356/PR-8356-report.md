# PR #8356 코드 리뷰 보고서 (2차)

**PR:** [CUBRID/cubrid#8356](https://github.com/CUBRID/cubrid/pull/8356)
**제목:** [CBRD-27866] Walk the partitions of a partitioned nested-loop inner per outer row instead of rerunning the outer for each partition
**작성자:** shparkcubrid
**HEAD SHA:** `14e1aea9c` (1차 `60058202c` 이후 커밋 1개, develop merge-base `e98bdd885`)
**JIRA:** CBRD-27866 (Develop) / 연관: CBRD-27566(중복, 포함), CBRD-27928, CBRD-27958(Won't Do 로 Resolved), CBRD-27908
**TC PR:** CUBRID/cubrid-testcases#3975 (`d362cdc2`, 1차 Approve 그대로) / cubrid-testcases-private-ex#4684 (ready, `10d781549`)
**리뷰 일시:** 2026-11-08 (1차 2026-11-06, 엔진 COMMENT 5794418992, TC #3975 APPROVE 5794419397)
**리뷰 결정:** 엔진 PR Approve (1차 확인 문단 + `tran_info` rerun 한 줄) / TC #3975 Approve 유지(새 리뷰 없음) / private-ex #4684 Approve(본문 없음); 리터럴 SIGABRT 와 CBRD-27958 본문 정정은 게시 안 함; TLA+ trace 는 1차 계측 빌드 재사용

> **TL;DR** (Non-blocking): 1차의 Q1, Q2, NIT, 상수 제안, 본문 정정이 모두 반영되거나 답변됐다. Q1 답변(develop 도 `ri` 인덱스로는 그 행을 못 찾음)은 merge-base 빌드에서 바인드 조회 `'@'` -> 0행으로 확인했다. 새 커밋 `14e1aea9c` 는 동작을 바꾸지 않는다. 엔진 PR 과 private-ex #4684 를 승인할 수 있다.

## Summary

- **새 커밋**: 캐시 개수 `4` 를 `PARTITION_SCAN_CACHE_COUNT` 로 묶고, `xasl_iteration.cpp` 의 trace 병합 조건에서 중복 OR 항을 뺐다.
- **1차 질문**: Q1 은 develop 도 같은 상태에서 인덱스 조회가 행을 놓치는 것으로 확인, Q2 는 본문에 범위 밖 키 동작을 적음.
- **CI**: sql/medium 통과, shell NOK 1건(`issue_21654_server_side_loaddb/tran_info`)은 loaddb 폴링 타이밍 TC 로 이 PR 과 무관.

---

## Findings

없음

1차 지적의 처리:

| 1차 항목 | 처리 | 확인 |
|---|---|---|
| Q1 `issue_9495_synctool` 448행(키 6개) 누락 | 원인 정정(문자열 키라 행 단위 프루닝 아님, 외부 조인 inner 가 `ri` idx-join), answer 유지, CBRD-27958 Won't Do, TC 스크립트 주석(10d781549) | merge-base 에서 `execute st using '@'` -> `ri` 인덱스 스캔 0행, `'AE'` -> 64행. head 의 외부 조인은 `ri` idx-join 646행, `using index none` 이면 1088행 |
| Q2 범위 밖 키 전 파티션 순회 | 의도한 동작, 본문 Implementation 에 기술 | 본문 17행 확인 |
| NIT `xasl_iteration.cpp:185` | `XASL_IS_PER_OUTER_ROW (src_node)` 만 봄 | 유일한 설정 지점 `gen_outer` (plan_generation.c:2826-2831)가 FOLLOWING_JOIN 을 함께 붙이거나 이미 SEMI/ANTI; 이 플래그를 지우는 곳은 `qdump_print_xasl` 뿐이고 두 플래그를 같이 지움 |
| 캐시 개수 `4` | `PARTITION_SCAN_CACHE_COUNT` (xasl.h) 9곳 사용 | 남은 맨 숫자 `4` 없음(4MB 상한 상수만) |
| 본문 `cbrd_27548_no_partition` 문장 | Remarks 에서 삭제 | 확인 |
| greptile 4439624078 스레드 | 작성자가 현재 동작 답글(4489906055) | 확인 |

참고(범위 밖, 게시 안 함): 같은 synccolldb -f 상태에서 리터럴 `select count(*) from t where s1 = '@'` 는 merge-base 와 head optdebug 서버 모두 SIGABRT 로 죽는다(head 스택: `tp_domain_find_charbit` assert <- `or_unpack_domain` <- `stx_build_regu_variable` <- `xcache_find_xasl_id_for_execute`). develop 에서 이미 나는 결함이고 CBRD-27958 이 이 DB 상태를 지원 밖으로 정리했다.

## JIRA -> Engine PR

`design.md` / `test.md` 첨부가 없어 JIRA 본문의 Acceptance Criteria 와 DoD 로 대신한다.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| AC 1단계: 블록 반복이 outer 를 다시 실행하지 않음 | TC 카운터 develop 480/180/960 -> 60; 1차 fail-before/pass-after; TLA+ C1 | 충족 |
| AC 2단계: 키 비반복 경우 파티션 전환 비용 감소 | `scan_switch_index_partition` 빠른 전환, PR 실측(memo 거부 1.11배 수용) | 충족(PR 실측만) |
| AC 3단계: 파티션 키 조인은 행마다 1개 파티션 | 파티션이 있는 키는 그 파티션만; 범위 밖 키는 develop 상수 프루닝과 같이 전 파티션(본문 기술) | 충족 |
| 결과 행 develop 과 동일 | CI sql/medium 통과(14e1aea9c), 1차 대조 프로브 0줄 차이; `issue_9495` 차이는 지원 밖 DB 상태(develop 인덱스 조회도 0행, CBRD-27958 Won't Do) | 충족 |
| 비파티션·파티션 outer·클래스 계층 실행 불변 | 1차와 같음 | 충족 |
| DoD: TC 추가, answer 갱신 | `cbrd_27866` 18 case, sql answer 13건, shell answer 2건 | 충족 |
| DoD: 단계별 실측 결과 첨부 | PR 본문에만 있고 JIRA 첨부 없음 | 부분(보고서 기록만) |
| 연관 CBRD-27566 / CBRD-27928 / CBRD-27958 | 포함 / 파티션 inner 해결 / Won't Do(본문은 옛 원인 "같은 프루닝을 조인 값에도 적용" 그대로) | 충족 |

판정: 충족.

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 블록 반복 / 행 단위 / 파티션 outer x inner / 병렬 outer / FOR UPDATE (JIRA DoD) | `cbrd_27866` Case 1, 3, 6, 14, 15 | 통과 |
| 키 반복, 파티션 키 조인, range/list, 연쇄, semi/anti, 외부 조인 NULL 행, 잠금, 클래스 계층, rownum/GROUP BY | Case 1-13 | 통과 |
| 서브쿼리 재실행, 프루닝 없는 외부 조인 | Case 17, 18 | 통과 |
| 지원 밖 collation 상태의 외부 조인 | private-ex `issue_9495_synctool` (주석 + answer) | 통과 |

- #3975: 1차 이후 변경 없음(`d362cdc2`), Approve 유지.
- #4684: `8acfff9e..10d781549` 는 `.sh` 주석 6줄뿐. CI shell(tc `10d781549`)에서 `bug_bts_9491`, `issue_9495_synctool` 통과, 로컬 head optdebug 에서도 PASS. 본문 설명이 실측(448행, 키 6개)과 맞음.

판정: #3975 승인 유지, #4684 승인 가능.

## TLA+ Verification

TLA+ 검증: 통과(1차 모델 재사용) — `.claude/review/PR-8356/tla/per-row-partition-walk/`
- 속성 C1-C6 은 1차와 같음(모두 TLC 통과, IndInv 는 Apalache). TLAPS: 요청 없음.
- 재사용 근거: `60058202c..14e1aea9c` 는 `query_executor.c` 에서 `qexec_free_partition_scan_caches` 의 `4` -> `PARTITION_SCAN_CACHE_COUNT`(값 4), `scan_manager.c` 에서 `scan_switch_index_attr_caches` 의 같은 치환, `xasl_iteration.cpp` 의 PX trace 통계 병합 조건만 바꾼다. 모델의 동작(Open, Reset, Enter, OpenRow, Loop)이 대응하는 함수는 전처리 후 토큰이 같다. trace 병합 조건은 모델 밖이고, 위 NIT 확인으로 판정이 같다.
- mutant: 8개 모두 위반 검출 / 살아남은 mutant: 없음
- trace validation: 1차 계측 빌드(60058202c, libcubrid `4df0508b`) 수용 4건, 거부 1건. 계측 함수가 바뀌지 않아 14e1aea9c 로 다시 빌드하지 않음
- `RESULT: OK` (run `per-row-partition-walk-20261106-093844-3079880`, 1차)

## Runtime Verification

- CI: gha-ci run 42178733654(head 14e1aea9c optdebug/release, tc `d362cdc2` / `10d781549`): sql 17747, medium 975 통과. shell 3549 중 NOK 1건 `_35_cherry/issue_21654_server_side_loaddb/tran_info` (shard 33). trace: loaddb 실행 중 `tranlist` 와 `show transaction tables` 를 5번 폴링해 loaddb 행을 찾는 1번 검사가 실패. 1차 run 42006718581(60058202c)에서는 통과했고, 최근 shell 이 돈 run 50개 중 이 run 에서만 실패. `/run rerun 42178733654` 대상.
- Q1 대조 프로브(review-only shell, `issue_9495_synctool` 복사본 + probe.sql, CI tarball optdebug, CS): merge-base e98bdd885(libcubrid `e29d8438`) / head 14e1aea9c(`517809a9`).
  - 외부 조인 count: base 1088(inner seq scan, 인덱스 힌트 무시) / head 646(`ri` idx-join), `using index none` 은 둘 다 1088.
  - `prepare ... where s1 = ?`: base, head 모두 `'@'` 0행, `'AE'` 64행(`ri` 인덱스 스캔).
  - 리터럴 `where s1 = '@'`: base, head 모두 서버 SIGABRT(위 참고).
  - head 에서 TC 전체 PASS, core 0(리터럴 문장 뺀 2차 실행).
- 증거: `.git_ignored_dir/scratch/pr8356/evidence/r2/`

## Existing Comments

| 코멘트 | 상태 |
|---|---|
| xmilex-git Q1 4487960941, Q2 4487960945, NIT 4487960948, 상수 4487960954 | 작성자 답글·반영 완료(4489905218, 4489905419, 4489905635, 4489905839) |
| greptile 4439624078 | 작성자 현재 동작 답글(4489906055) |
| jihyekim-0 4476503330, 4477276131 | 리뷰어가 60058202c 에서 재확인 완료(4487907488, 4487973444) |
