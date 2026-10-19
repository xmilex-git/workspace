# PR #3708 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases#3708](https://github.com/CUBRID/cubrid-testcases/pull/3708)
**제목:** [CBRD-27292] Add new test case for constant-output parallel scans
**작성자:** HyunukLee
**HEAD SHA:** `7d461dc8b` (커밋 1개, develop merge-base `a4c009983`)
**JIRA:** CBRD-27292 (Sub-task, Resolved; 부모 CBRD-27152 Improve Function/Performance) / 엔진 CUBRID/cubrid#7767, squash merge `45aa81034` (2026-09-01, xmilex-git Approve)
**TC PR:** 이 PR 자체 (엔진 머지 뒤 후속 TC PR, sql 1건 `sql/_36_guava/cbrd_27292`). 엔진 PR 의 봇 TC PR cubrid-testcases#3323 (`tc/pr-7767`) 은 2026-09-01 머지 (`cbrd_25447` 답지 1줄), private-ex#3958 은 변경 없이 닫힘
**리뷰 일시:** 2026-10-13
**리뷰 결정:** #3708 Approve (본문 + 인라인 2건: 인덱스 스캔 케이스 제안, HAVING 1=1 설명). Greptile 스레드 답글 없음

> **TL;DR** (Non-blocking): 4개 케이스가 엔진 PR 이 바꾼 경로를 trace 토큰과 병렬 = 직렬 비교로 확인하고, 최신 develop optdebug (`4333ce3a8`) 에서 OK (결과 = 답지, 코어 0) 다. 같은 조건 제거로 바뀐 인덱스 스캔 상수 출력 경로는 케이스가 없고, 헤더의 HAVING 1=1 설명은 develop 동작과 다르다.

## Summary

- **변경 요약**: 상수 출력 스캔 (pred, rest regu list 가 둘 다 빈 스펙) 의 heap / list 병렬 mergeable list gather 와, 집계 없는 BUILDVALUE 의 row by row gather 를 병렬 = 직렬 비교와 함께 보는 sql 케이스 1건 (Case 1-4) 추가
- **주요 이슈**: 인덱스 스캔 상수 출력 미포함 (1)
- **확인 필요 사항**: 헤더/본문의 HAVING 1=1 설명 (2), 본문의 수정 전 빌드 결과 (3)

---

## Findings

용어: pred / rest regu list (스캔이 술어 평가용 / 나머지 출력용으로 읽는 컬럼 목록), `CANNOT_LIST_MERGE` (px_scan checker 가 워커 결과 리스트 병합을 막는 플래그), mergeable list / row by row (워커 결과를 리스트째 합치는 gather / 한 행씩 넘기는 gather), BUILDVALUE (결과가 한 행인 XASL 처리 노드).

### Non-blocking (should consider)

1. 커버리지 -- 인덱스 스캔 상수 출력. 엔진 diff 가 지운 조건은 `TARGET_CLASS` 분기 안에 있어 heap 과 인덱스 스펙 모두에 걸렸다 (`px_scan_checker.cpp`, `45aa81034^` 424-427행). 수정 전에는 이 플래그가 서면 인덱스 스펙이 `ACCESS_SPEC_FLAG_NO_PARALLEL_SCAN` 으로 직렬이 된다 (같은 파일 908-911행). 엔진 PR 본문도 "list/index를 직렬로 강등" 이라 적는다. 케이스는 heap (Case 1) 과 list (Case 2) 만 본다. 최신 develop 프로브: 300,000행 int 인덱스에서
   ```sql
   insert into rp select /*+ recompile parallel(4) */ 1 from tk force index (idx_k) where k > 0;
   ```
   -> `SCAN (index: dba.tk.idx_k) ... (parallel workers: ?, ..., covered: true, gather: mergeable list)`, 병렬/직렬 모두 300000행, 값 전부 1. 같은 형태의 Case 5 면 지운 조건의 세 분기를 모두 덮는다. 수정 전 직렬은 코드 판단이며 실행하지 않았다.
2. `cbrd_27292.sql:33-35` -- 헤더는 "a constant HAVING such as 1=1 is removed by the rewriter, which turns Case 3 back into the BUILDLIST of Case 1" 이라 한다. 최신 develop 에서 `select /*+ recompile parallel(4) */ 1 from t27292 having 1=1;` 은 WHERE 없이도 1행, `rewritten query: ... having ? <> ?`, `gather: row by row` 로 BUILDVALUE 가 유지됐다 (#7767 리뷰 때 측정도 같았다: `SELECT 1 FROM t1 HAVING 1 = 1` -> 1행, row by row). JIRA 테스트 설명이 든 실제 이유는 recompile 없이 `select 1 from t` 의 캐시된 plan 을 공유하는 것이다. 케이스 동작에는 영향이 없고 설명만 틀려 다음 수정자를 오도한다. PR 본문 "HAVING 선택" 문장도 같다.

### Questions for the author

3. PR 본문 -- 검증 표에 수정 전 빌드 행이 없고 "(draft)" 라 적혀 있으나 PR 은 draft 가 아니고 리뷰 요청 상태다. 코드 판단: Case 1 (heap row by row), Case 2 (list 직렬, temp `SCAN` 아래 parallel 줄 없음), Case 4 (집계 없는 BUILDVALUE 가 mergeable list) 는 수정 전 빌드에서 trace 가 달라 NOK, Case 3 은 수정 전에도 빈 pred+rest 강등으로 row by row 라 OK 다. Case 3 은 두 변경 중 BUILDVALUE 쪽만 되돌리는 회귀를 지키는 케이스라는 점과 수정 전 결과를 본문에 채울지.

## JIRA -> TC

시나리오는 JIRA 첨부 `CBRD-27292_testcase_description.md` (A/B/C/C3), AC 3개, 엔진 diff 분기. 엔진 PR 에 검증 표는 없다.

| 항목 | TC 상태 | 판정 |
|---|---|---|
| (A) `PARALLEL` 상수 출력 trace `gather: mergeable list` | Case 1 (INSERT ... SELECT 의 subquery 로 실행, 답지 43행) | 충족 |
| (B) / AC1 병렬 = 직렬 (행 수, 값) | Case 1, 2: 양쪽 1000행, 병렬쪽 값 = 1. 직렬쪽 값 검사 없음 (Greptile 기존 코멘트) | 충족 |
| (C) 집계 없는 BUILDVALUE (`SYS_TIMESTAMP`) row by row, 1행 | Case 3 | 충족 (수정 전에도 통과, 3) |
| (C3) 술어 경로 `WHERE id > 0 HAVING 1=1` row by row, 1행 | Case 4 (#7767 리뷰 요청 사항) | 충족 |
| AC2 ROWNUM, Java SP 정상 | 이 PR 밖: `cbrd_25447` 6번 (SP, row by row 유지), 19번 (`null ... limit 2`, #3323 에서 mergeable list) | 충족 (기존 TC) |
| AC3 CTP 회귀 | 엔진 PR CI | 해당 없음 |
| diff: `TARGET_CLASS` heap 조건 제거 | Case 1 | 충족 |
| diff: `TARGET_CLASS` 인덱스 (같은 조건) | 없음 | 미충족 (1) |
| diff: `TARGET_LIST` 조건 제거 | Case 2 | 충족 |
| diff: `BUILDVALUE_PROC` 무조건 `CANNOT_LIST_MERGE` | Case 3, 4 | 충족 |

TC 파일 검토 (tc-author sql 규칙):
- 배치: Sub-task -> 부모 Improve 이므로 `_36_guava/cbrd_27292` 가 맞다. 모든 케이스에 답지가 있다.
- 헤더 줄끝 `;` 0, `--` 0, CQT 제어어 (`server-message` 등 on/off) 0. `evaluate 'Case 1-4'` 연속. trace on/off 4/4, 마지막 off. 추적 쿼리 전부 `recompile`. 테이블 4개 정리.
- 결정성: heap 145 페이지 (프로브 `show heap capacity`, 본문과 일치) 로 test_mode 임계 32 의 4.5배. 병렬 판단은 실제 페이지 수 (`heap_get_num_data_pages`, list 는 `list_id->page_cnt`) 라 통계와 무관하다. worker 수는 마스킹되고, 출력은 집계와 PASS/FAIL 이라 행 순서와 무관하다.
- 로컬 규칙과 다른 점 (헤더 36줄 > 30, 테이블명에 숫자) 은 trace 에 테이블이 하나뿐이라 실패 사례가 없어 제외했다.

#3323 과의 관계: `cbrd_25447` 19번은 `limit 2` heap 상수 출력의 trace 토큰만 보고, 이 PR 은 list 스캔, 전체 스캔의 병렬 = 직렬, 집계 없는 BUILDVALUE 를 더한다. 겹침은 trace 토큰 하나이고 헤더와 본문이 관계를 밝힌다. 엔진 PR Remarks 가 말한 두 경로 회귀 TC 는 #3323 에 없었고 이 PR 이 처음 넣는다.

판정: 케이스는 맞고 결정적이며 최신 develop 에서 통과한다. 인덱스 분기 누락 (1) 은 회귀 검출 범위 문제로 머지를 막지 않는다.

## Runtime Verification

| 실행 | 빌드 | 테스트케이스 | 결과 |
|---|---|---|---|
| 케이스 | gha-ci develop `4333ce3a8` optdebug ("debug" 슬롯, run 38338963493, `libcubrid.so` sha256 `5454f89a5b27bda7`) | `tc/CBRD-27292` `7d461dc8b` (provenance 확인) | OK 1/1, `.result` = 답지 (diff 0), 코어 0, 314 ms |
| 프로브 (리뷰 전용, 커밋 안 함) | 같은 빌드 | develop + `_99_review_adhoc/pr3708probe` | heap 145 페이지, HAVING 1=1 (2), 인덱스 상수 출력 (1), 코어 0 |

- 명령: `BUILD=<install> TC_REF=tc/CBRD-27292 CTP_KEEP_COPIES=1 CTP_HANG_SECS=900 just ctp sql _36_guava/cbrd_27292` (컨테이너, test_mode=yes, parallelism=4, max_parallel_workers=100).
- 수정 전 / 직후 빌드는 사용자 결정으로 돌리지 않았다. 수정 전 동작은 코드 판단이다 (1, 3).
- 답지 생성 빌드 `aea2cdf05` 와 `4333ce3a8` 사이 9커밋, `src/query/parallel/px_scan` 변경 없음.
- gha-ci: TC 단독 PR 이라 실행 없음.
- 증거: `.git_ignored_dir/scratch/pr3708/evidence/{main,probe}/` (provenance, `.result`, summary). 실행 디렉터리와 빈 코어 디렉터리는 삭제했다.

## Existing Comments

| 작성자 | 위치 | 내용 | 상태 |
|---|---|---|---|
| greptile-apps (P2) | `cbrd_27292.sql:61` | Case 1, 2 가 직렬 결과 `rs27292` 의 값을 확인하지 않음, `where one <=> 1` = 1000 추가 제안 | 작성자 답 없음. 지적은 맞고 Case 마다 한 줄로 해결된다. 중복 게시하지 않음 |
