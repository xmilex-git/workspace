# PR #8364 코드 리뷰 보고서 (r3)

**PR:** [CUBRID/cubrid#8364](https://github.com/CUBRID/cubrid/pull/8364)
**제목:** [CBRD-27870] A BUILDVALUE whose output reads a column of its scan keeps its rows on the serial row loop
**작성자:** soheejung-cs
**HEAD SHA:** `f65d0c0fa` (develop merge-base `e98bdd885`; r2 이후 수정 커밋 `b05e88633`)
**JIRA:** CBRD-27870 (Correct Error, Open) / 연관: CBRD-27361 (Regress)
**TC PR:** CUBRID/cubrid-testcases#3985 (`tc/pr-8364` `37a909eac`) / CUBRID/cubrid-testcases-private-ex#4695 (`80bd19835`, r1 승인 뒤 develop merge만)
**리뷰 일시:** 2026-11-06
**리뷰 결정:** 엔진 PR Request changes(인라인 3, 5794917472) + r1 Blocking 스레드 해소 답글(4488354996) / TC #3985 Comment(5794918400) / TC #4695 리뷰 없음(r1 Approve 유지)

> **TL;DR** (Blocking): r1 assert 는 `b05e88633` 에서 해소됐지만, 그 수정과 병렬 제외가 숨은 컬럼 값을 얻으려고 develop 의 집계 빠른 길(MIN/MAX 인덱스·통계, count-only)과 병렬 스캔을 이 블록에서 끈다. 두 형태 모두 #8196 이전에도 NULL 이라 회귀 범위 밖이고, release 100만 행 ODKU MAX 가 develop 1.31G -> 4.0G instructions 가 된다. 빠른 길과 병렬은 develop 대로 두고 페이지 배치 제외와 행마다 복사만 남기라고 요청했다.

## Summary

- **변경 요약**: 출력이 자기 스캔 컬럼을 읽는 BUILDVALUE 에 `XASL_OUTPUT_READS_SCAN` 을 세우고, 배치·병렬·count-only·집계 빠른 길을 끄며, 행마다 복사(`qexec_keep_last_row`)해 출력 직전 돌려놓는다(`qexec_restore_last_row`).
- **주요 이슈**: 집계 빠른 길과 병렬 스캔 제외(Blocking 1).
- **확인 필요 사항**: 없음(빠른 길에서 값이 필요하면 별도 이슈).

---

## Findings

### Blocking (must fix)

1. `src/parser/xasl_generation.c:21062`, `src/query/query_executor.c:14570`, `src/query/parallel/px_scan/px_scan_checker.cpp:969` -- 플래그 블록은 `agg_optimized` 를 생성 단계에서 내려 `qexec_evaluate_aggregates_optimize` (인덱스 끝·통계로 MIN/MAX/COUNT 를 끝내는 빠른 길)를 못 타고, count-only 인덱스 스캔과 병렬 스캔도 못 탄다 -> 소스 행을 모두 직렬로 돈다. 두 경로의 숨은 컬럼 NULL 은 #8196 이전부터라 이 회귀의 범위 밖인데, 그 값을 위해 develop 의 최적화를 버린다.
   - release, SA, `g` 인덱스가 있는 100만 행: `insert into tt (id) select max(s.g) + 1 from big s on duplicate key update c = s.c` -> develop `e98bdd885` 1.309G/1.310G/1.314G instructions:u(csql 기동만 1.30G), `c` NULL. head 3.98G/4.02G/4.01G(기동만 1.25G), `c` = `'v999739'`(스캔 마지막 행, MAX 행의 `'v1000000'` 아님).
   - 요청: 빠른 길(위 해제, count-only 의 `!XASL_OUTPUT_READS_SCAN`, debug assert)과 병렬(`CANNOT_PARALLEL_SCAN`)은 develop 대로 두고, 페이지 배치 제외(#8196 이전 직렬과 같음)와 행마다 복사만 남긴다. TC Case 6, 8 답안도 따라 바뀐다.

### Non-blocking (should consider)

2. `src/query/query_executor.c:810-812`, `src/parser/xasl_generation.c:288` -- 새 static prototype 이 정의 순서와 다르다(P8). 세 함수는 `qexec_end_buildvalueblock_iterations` 앞(20987-21082)에 정의됐는데 선언은 그 뒤에 있고, `pt_buildvalue_output_reads_scan` 은 `pt_to_buildlist_proc`/`pt_to_buildvalue_proc` 사이(20816)에 정의됐는데 선언은 288 에 있다. NIT.

## JIRA -> Engine PR

| 항목 | PR 상태 | 판정 |
|---|---|---|
| 재현 두 개가 'g2', (1, 'g2') | head release SA: `'g2'`, `1, 'g2'` | 충족 |
| 표의 형태가 #8196 이전 직렬 값과 같음 | CI optdebug sql 통과(Case 5-8), release Case 8 세 문장 `'h3'` | 충족(빠른 길 형태는 #8196 이전 NULL 과 다름, Blocking 1) |
| 병렬 대상 소스에서도 마지막 행 값 | Case 6 OK, 병렬을 꺼서 얻음 | 부분 (Blocking 1, 사용자 결정으로 이 항목은 NULL 유지 요청) |
| GROUP BY 소스는 그룹 첫 행 | Case 5 OK (CI) | 충족 |
| debug 에서 `function_based_index_select_basic_subquery_001` 통과 | run 42006019072 sql pass | 충족 |
| CTP sql·medium·shell 통과 | sql·medium pass, shell 1 NOK `locks_count`(flake, 아래) | 부분 (rerun 필요) |
| 설계: r1 assert 해소 | 생성 단계(`pt_to_buildvalue_proc`)에서 해제 | 충족 |
| 범위: #8196 회귀만 고침, 다른 최적화 유지 | 빠른 길·병렬까지 끔 | 미충족 (Blocking 1) |

설계 문서(`design.md`/`test.md`) 첨부는 없다(r1 과 같음, 게시하지 않음).

## TC PRs

| 시나리오 | 근거 | 판정 |
|---|---|---|
| ODKU 숨은 컬럼(필터·집계 컬럼·인덱스/힙·조인·GROUP BY) | #3985 Case 5 | 통과 |
| 병렬 대상 소스(trace) | #3985 Case 6 | 통과 |
| SELECT 목록 상관 서브쿼리 | #3985 Case 7 | 통과 |
| 집계 빠른 길(WHERE 없는 MAX·MIN, 키 범위 COUNT(*)) | #3985 Case 8, CI optdebug pass | 통과(엔진 수정 뒤 답안 재조정 필요) |
| #8211 shell 칸 13 원래 형태 | #4695, run 42006019072 shell 에서 `cbrd_27336_forms` OK | 통과 |

- #3985: r2 NIT(머리 주석 `;`)를 `7ac371ed2` 가 고쳤고 답안은 그대로다. 본문의 "debug 빌드에서도 같은 출력으로 통과" 는 이제 CI 와 맞다.
- #4695: r1 Approve(`c7ac1b4cf`) 뒤 develop merge 만 있고 `cbrd_27336` 파일 변화 없음.

## TLA+ Verification

TLA+ 검증: 실패(결함 H1) -- `.claude/review/PR-8364/tla/bv-last-row/` (`BvLastRow`, head `f65d0c0fa` = `Mutant "none"`, 요청한 수정 = `Mutant "fix"`)
- 속성 (head / fix): C1 equivalence(직렬·배치 자리는 마지막 통과 행, 빠른 길·count-only·병렬은 develop 처럼 NULL; JIRA, grill Q6) 통과/통과 / C2 safety(놓은 페이지·해제된 버퍼 안 읽음) 통과/통과 / C3 safety(이미지 = 서버 집계, debug assert 없음; r1) 통과/통과 / C4 safety(복사 실패가 NULL 로 안 바뀜) 통과/통과 / C5 safety(`last_row` 누수·이중 해제 없음) 통과/통과 / C6 equivalence(플래그 없는 블록은 develop 경로) 통과/통과 / C7 liveness(최종 clear 도달) 통과/통과, TLC 만 / C8 equivalence(플래그 블록도 develop 의 집계 빠른 길·병렬 유지, 배치만 거절; grill Q3, Q6) 실패/통과. C1-C6 과 fix 의 C8 은 TLAPS 921/921 로 N 전 범위
- 결함: H1 head 의 code cfg 2개(`BvLastRow`, `scale-4-rows`)가 C8 위반(depth 3). 런타임 재현: release 100만 행 ODKU MAX develop 1.31G vs head 4.0G instructions:u. 후보 수정 cfg(`fix-candidate`, `scale-4-rows-fix`) 통과
- mutant: 13개 모두 위반 검출(merge-base 의 C1·C2 fail-before, r1 head 서버 해제 C3, 첫 head 스캔 뒤 복사 C2, 배치 가드 제거 C1, restore NULL 누락 C2, `pr_clone_value` C4, 이중 해제·누수 C5, 모든 블록 플래그 C6, 오류 경로 clear 누락 C7, head 자체 C8) / 살아남은 mutant: 없음
- 경계: 소스 3행, scale 4행, 입력 64조합; IndInv 귀납성은 Apalache 로 head·fix 각각 N 전 범위; TLAPS 는 safety, liveness C7 은 TLC 경계 안에서만
- trace validation: 계측 optdebug 빌드(`bb86bdc9...`) SA run 5건 수용, 손상 3건 거부. `RowKeepFail`·경로 count·gather 는 trace 없음
- 모델 밖: 슬롯 여러 개·`scan_ptr` 조인, CONNECT BY, 행 단위 병렬, 동시 DML·vacuum(PR 이 latch·lock 을 더하지 않음)
- 반례: H1 하나, 런타임 재현됨
- `RESULT: FAILED (2)` (run `bv-last-row-20261106-113442-3715985`; 실패는 H1 code cfg 둘뿐)

## Runtime Verification

- gha-ci run 42006019072 (head `f65d0c0fa`, optdebug, `tc/pr-8364` `37a909eac`): sql pass(17746), medium pass(975), shell NOK 1 -- `_24_apricot/_06_key_locking/locks_count` 의 Overflow Key Test 1-3 이 `lockdb` 잠금 수 `0, 0`. 이 케이스는 `insert ... values` 와 `sleep 1~3` 에 맞춘 `cubrid lockdb` 시점 검사로, 이 PR 이 바꾼 집계 경로를 타지 않는다. 최근 200개 run 중 이 run 에서만 실패 -> flake, `/run rerun 42006019072` 대상.
- head release CI tarball (`libcubridsa.so` sha256 `0c768756...`), SA: Case 8 의 ODKU MAX·MIN·키 범위 COUNT(*) 세 문장 `'h3'`, JIRA 재현 `'g2'`, `1, 'g2'`.
- release CI tarball develop `e98bdd885` (`libcubridsa.so` `f1647e1a...`) vs head (`0c768756...`), SA, 100만 행 ODKU MAX `perf stat instructions:u` 3회: develop 1.309G/1.310G/1.314G(기동만 1.30G), `c` NULL; head 3.98G/4.02G/4.01G(기동만 1.25G), `c` `'v999739'`.
- 계측 optdebug 빌드(`f65d0c0fa` + TLATRACE, `libcubridsa.so` `bb86bdc9...`), SA: trace 5 run(ODKU 힙 필터, 통과 행 없음, WHERE 없는 MIN 인덱스, MAX fast, COUNT 배치)의 결과 `'b'`, NULL, `'z'` 가 기대값.
- fail-before 는 r1 의 develop debug 실행(NULL)과 CI 를 재사용했다.
