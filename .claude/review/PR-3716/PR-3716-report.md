# PR #3716 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases#3716](https://github.com/CUBRID/cubrid-testcases/pull/3716)
**제목:** [CBRD-27404] Add new test case for parallel index and list scans in sort-merge join inputs
**작성자:** HyunukLee
**HEAD SHA:** `201dfe74e` (base develop)
**JIRA:** CBRD-27404 (Sub-task, Resolved; 부모 CBRD-27152 Improve Function/Performance; 엔진 CUBRID/cubrid#7909, merge `b9275d0bd`, 2026-09-14) / 연관: CBRD-27307 (merge 자체 병렬화, 엔진 #7795 open, 같은 작성자)
**TC PR:** 이 PR 자체 (엔진 머지 뒤의 후속 TC PR, sql 1건 `sql/_36_guava/cbrd_27404/cases/cbrd_27404.sql` + answer). 엔진 PR 의 봇 draft (cubrid-testcases#3470, private-ex#4117, `tc/pr-7909`) 는 변경 0 으로 머지 시점에 닫힘
**리뷰 일시:** 2026-10-13
**리뷰 결정:** #3716 Comment (본문 + 인라인 3건: 70행 suggestion, 45행, 52행) + Greptile 58, 88행 스레드 답글. Finding 4 (NIT, 형식) 는 게시 안 함

> **TL;DR** (Non-blocking): 케이스는 엔진 PR 이 연 경로 (merge 입력의 parallel index / temp scan) 를 trace 로 고정하고, 최신 develop optdebug 에서 18/18 블록 일치, 코어 0 으로 통과한다. 다만 Case 2 의 값 검사는 md5 길이 합이라 사실상 건수만 보고, 인덱스와 temp list 크기가 32페이지 게이트에 2배 미만으로 붙어 있으며, JIRA S1 의 non-covered index 입력이 빠져 있다.

## Summary

- **변경 요약**: 40,000행 테이블 `mj` 의 `USE_MERGE PARALLEL(4)` self-join 3 케이스 (covered index 입력, GROUP BY derived table 의 temp list 입력, nullable 키 index 입력) 를 trace 와 PASS/FAIL 비교로 검사하는 sql 케이스 1건 추가
- **주요 이슈**: Case 2 값 검사가 건수뿐 (1), 페이지 게이트 여유 부족 (2)
- **확인 필요 사항**: S1 (non-covered 입력) 을 뺀 이유 (3), 답이 없는 Greptile 인라인 2건

---

## Findings

### Non-blocking (should consider)

1. `cbrd_27404.sql:70` (77, 80행 동일) -- `sum(length(d1.p) + length(d2.p))` 는 항상 64 x 건수다. `md5()` 는 항상 32자 (probe: `count(distinct length(pad))` = 1) 이고 answer 도 `20000 / 1280000` 이다. `g = mod(rownum * 7, 40000)` 는 0..39999 의 순열이라 각 입력에 g 마다 한 행씩 있다 -> parallel temp scan 이 한 페이지를 두 번 읽고 같은 행 수의 다른 페이지를 건너뛰어도 (행 길이 고정이라 페이지당 행 수 같음) 건수 20000, 합 1280000 이 그대로라 traced 행과 hash join twin (같은 질의를 옛 경로로 돌린 기준 결과) 이 모두 통과한다. `sum(cast(d1.g as bigint) + d2.g)` 로 바꾸면 잡힌다 (g 마다 한 행이라 `d1.p = d2.p` 개수로 값까지 확인 가능). 최신 develop probe: `20000 / 399980000 / 20000`, hash join twin 과 같음.
2. `cbrd_27404.sql:41-45` -- 페이지 게이트 여유가 2배 미만이다. 게이트는 `parallel_scan_page_threshold` (CTP `test_mode` 에서 32) 이고, index 는 b-tree 파일 페이지 수 (`px_scan.cpp` 의 `file_get_num_user_pages`), list 는 `list_id->page_cnt` 로 판정한다.
   - `SHOW INDEX CAPACITY` 실측: `i_mj_k` 40페이지 (1.25배), `i_mj_kn` 37페이지 (1.16배).
   - Case 2 의 g 범위를 절반 (`g < 10000`) 으로 줄이면 MERGELIST 입력의 temp scan parallel 줄이 사라진다 -> list 는 32-64페이지.
   - tc-author 기준은 3배 (#3661, #4312 flaky 이력). b-tree 레코드나 temp tuple 형식이 바뀌면 (예: 453da49c8 CBRD-27365 가 temp tuple 형식을 바꿈) 정상 엔진에서 Case 1, 2 가 NOK 가 되고, trace 가 없는 Case 3 은 직렬끼리의 비교로 조용히 바뀐다.
   - 행과 키 수를 3배 (`limit 120000`, `mod(rownum, 90000)`, `mod(rownum * 7, 120000)`, 범위와 `g <` 도 비례) 로 늘리면 된다. 지금 케이스 실행 8초.
3. 커버리지 -- JIRA S1 (첨부 SQL 은 인덱스에 없는 `v` 를 합산 -> 입력이 non-covered index scan) 이 케이스에도 제외 사유에도 없다. Case 1 은 self-join 이지만 covered 만 본다. 최신 develop probe: Case 1 을 `sum(cast(a.g as bigint) + b.g)` 로 바꾸면 두 입력 모두 `(parallel workers: ?, index time ..., gather: mergeable list) (lookup time: ...)` (worker 가 힙 lookup 을 하는 parallel index scan) 이고 `59504 / 2393772100` 이 `NO_PARALLEL_SCAN` twin 과 같다. lookup 경로는 covered 경로와 다른 코드다.
4. NIT: `evaluate 'Case N: ...'` 대신 `-- Case N` 주석이라 answer 블록에 케이스 이름이 없고, traced 쿼리에 `recompile` 이 없으며, 헤더가 `/*` 36줄이다 (tc-author 형식: `/**`, 20-30줄). 워크스페이스 규칙이라 게시하지 않음 (지금 텍스트는 이 파일에만 있어 plan 캐시 오염 위험은 없음).

## JIRA -> TC

JIRA 첨부 `CBRD-27404_testcase_description.md` 의 시나리오 4개 (I1, L1, N1, S1) 와 AC 3개. 엔진 PR 본문에는 검증 표가 없고 Remarks 가 AC 와 같다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| I1 covered index + 조인 키 범위 | Case 1: 두 입력 `SCAN (index)` 아래 parallel 줄 (answer 39, 44행), 직렬 merge 와 키별 건수 정답 비교 PASS | 충족 |
| L1 GROUP BY derived table (list 입력) | Case 2: 두 입력 `SCAN (temp)` 아래 parallel 줄 (answer 101, 106행), hash join 비교 PASS. 값은 건수만 | 부분 (1) |
| N1 nullable 키 index 입력 | Case 3: PASS, trace 없음. 단일 컬럼 인덱스에 NULL 키가 없다 (`i_mj_kn` Total_value 39604 = 40000 - 396) | 부분 (Greptile 기존 코멘트) |
| S1 대용량 self-join (non-key 합산) | Case 1 은 covered self-join 만 | 부분 (3) |
| AC1 입력 parallel 줄, `ORDERBY sort: true` 유지, MERGELIST 직렬 | answer 36-46, 98-108행 | 충족 |
| AC2 결과 = `NO_PARALLEL_SCAN` / `USE_NL` | Case 1, 3 직렬 merge + 키별 건수 정답, Case 2 hash join. NL 대신 정답 계산은 본문에 이유 (debug 시간) | 충족 |
| AC3 parallel scan CTP 회귀 | 엔진 PR 범위, TC 대상 아님 | 해당 없음 |

TC 파일 검토 (tc-author sql 규칙): 헤더 줄끝 `;` 0, 헤더 안 `--` 0, `server-message` 류 0. trace on/off 2/2, 마지막 off. 세션 변수, 파라미터 변경 없음. 모든 결과가 단일 행 집계라 순서 무관. 끝에 `drop table mj`. 위치: Sub-task (부모 Improve) -> `_36_guava/cbrd_27404` 맞음. 판단 규칙 R1 (trace 토큰). 헤더의 게이트 설명 (index 와 list 모두 `parallel_scan_page_threshold`, 서버 쪽 b-tree 크기 게이트) 과 `NO_PARALLEL_SUBQUERY` 이유 (worker 는 리더의 system operation 중에 `is_under_system_operation()` 로 parallel 을 끔) 는 코드와 맞다. `PARALLEL` 힌트가 optimizer 의 추정치 검사를 건너뛰므로 `update statistics` 가 fullscan 이 아니어도 영향 없다.

수정 전 판별력 (소스 판단, 실행 안 함): b9275d0bd 는 `block_parallel_index_and_temp_in_subtree` 만 지운다. 이 함수는 MERGELIST 입력 (aptr) 의 index spec 과 `TARGET_LIST` spec 에만 `NO_PARALLEL_SCAN` 을 붙였으므로, 수정 전 엔진에서는 answer 39, 44, 101, 106행의 4줄만 빠져 NOK 가 된다. 작성자가 본문에 적은 bf1680a9d (2026-08-08, 머지 부모가 아닌 5주 전 develop) 결과와 일치한다.

판정: 케이스는 엔진 PR 의 경로를 결정적으로 고정하고 최신 develop 에서 통과한다. 1-3 은 회귀 검출력과 견고성 문제로 머지를 막지 않는다.

참고: CBRD-27307 (#7795, 같은 작성자, open) 이 MERGELIST 자체를 병렬화하면 이 answer 의 `MERGELIST` 줄이 바뀐다 -> 그쪽 `tc/pr-7795` (cubrid-testcases#3354) 에 이 answer 갱신이 함께 필요하다.

## Runtime Verification

로컬 컨테이너 CTP, 사용자 결정에 따라 최신 develop optdebug 1회만 실행했다 (수정 전, 직후 빌드는 실행 안 함).

| 실행 | 빌드 | 테스트케이스 | 결과 |
|---|---|---|---|
| `just ctp sql _36_guava/cbrd_27404` | develop `4333ce3a8` gha-ci optdebug ("debug" 슬롯, run 38338963493, `libcubrid.so` sha256 `5454f89a5b27bda7`) | `tc/CBRD-27404` `201dfe74e4e9` (provenance 확인) | OK, 18/18 블록이 answer 와 동일 (diff 없음), 코어 0, 케이스 8초 |
| 리뷰용 probe 1 (커밋 안 함) | 같은 빌드 | `_99_review_adhoc/pr3716probe`, `--testcases-as-is` | placeholder 라 NOK (의도), 코어 0, PASS 행 14/14 |
| 리뷰용 probe 2 (커밋 안 함) | 같은 빌드 | `_99_review_adhoc/pr3716probetwo` | placeholder 라 NOK (의도), 코어 0 |

- probe 1: `SHOW INDEX CAPACITY` (Finding 2), 세 비교문에 trace 를 켜고 각 3회, 바깥 `NO_PARALLEL_SUBQUERY` 변형 (Existing Comments).
- probe 2: S1 형태 non-covered 입력 (Finding 3), Case 2 의 1/2, 1/3 크기 (Finding 2), 키 합 + `d1.p = d2.p` 집계와 hash join twin (Finding 1), pad 길이 분포.
- gha-ci: 실행 안 함 (TC 단독 PR, Greptile 체크만 있음).
- 증거: `.git_ignored_dir/scratch/pr3716/evidence/` (provenance, `.result`, probe SQL 과 결과). 실행 디렉터리는 삭제함.

## Existing Comments

Greptile 인라인 2건 (P2), 작성자 답 없음. 새 코멘트로 다시 달지 않고 해당 스레드에 답하는 것이 맞다.

| 코멘트 | 내용 | 검토 |
|---|---|---|
| 4254104682 (58행) | 비교문 바깥 SELECT 에 `NO_PARALLEL_SUBQUERY` 가 없어 `p` 가 직렬일 수 있음 | 타당. probe: Case 1, 3 비교문에서 `p` 의 `MERGELIST (parallel workers: ?` = subquery executor 가 두 입력을 동시에 만듦 (헤더 33-36행이 trace 가 흔들린다고 적은 상태). 3/3회 입력은 parallel 이었다. 바깥에 힌트를 넣으면 이 줄이 사라지고 입력 parallel 유지 (Case 1 3/3, Case 2, 3 1/1). answer 영향 없음 |
| 4254104689 (88행) | `BETWEEN` 이 NULL 을 먼저 제외 | 타당. 더 근본적으로 단일 컬럼 인덱스에는 NULL 키가 저장되지 않아 (`i_mj_kn` Total_value 39604) index 입력으로는 NULL 이 merge 에 들어갈 수 없다. NULL 그룹 행이 들어가려면 list 입력 (kn 으로 GROUP BY 한 derived table) 이어야 한다 (미실행) |
