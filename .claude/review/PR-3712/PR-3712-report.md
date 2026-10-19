# PR #3712 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases#3712](https://github.com/CUBRID/cubrid-testcases/pull/3712)
**제목:** [CBRD-27060] Add new test case for parallel index scan on filtered indexes
**작성자:** HyunukLee
**HEAD SHA:** `bb3ada018` (base develop, 파일 2개: `sql/_36_guava/cbrd_27060/{cases,answers}`)
**JIRA:** CBRD-27060 (Improve Function/Performance, Resolved; 엔진 CUBRID/cubrid#7467, squash merge `25d3f4d3f`, 2026-08-07) / 연관: CBRD-26722 (병렬 인덱스 스캔 도입)
**TC PR:** 이 PR 자체 (엔진 머지 뒤 후속 TC PR, sql 1건). 엔진 PR 봇 draft (cubrid-testcases#3062, private-ex#3645, `tc/pr-7467`) 는 변경 0건으로 2026-08-07 닫힘
**리뷰 일시:** 2026-10-13
**리뷰 결정:** #3712 Comment (본문 + 인라인 2건: 27행 suggestion, 146행 list-scan 제안) + Greptile 183행 스레드 답글. 인덱스 여유, 첨부 TC (5)/(12), 형식 지적은 게시 안 함

> **TL;DR** (Non-blocking): 최신 develop optdebug (`4333ce3a8`) 에서 OK, 코어 0. 비교 케이스 14개의 `PARALLEL(8)` 쪽이 실제로 병렬 인덱스 스캔으로 도는 것도 프로브로 확인했다. 다만 헤더 27행의 "autocommit off" 문구 때문에 CTP 가 첫 문장 `drop table if exists ft` 를 실행하지 않고 답지에도 그 블록이 빠져 있다. 또 JIRA AC 가 명시한 행 반환 (list-scan) 경로가 케이스에 없다.

## Summary

- **변경 요약**: filtered index 3종 (단일, desc, 다중 컬럼) 에서 `PARALLEL(8)` 과 `NO_PARALLEL_SCAN` (일부는 heap 스캔까지) 의 집계를 `<=>` 로 비교해 PASS/FAIL 을 찍는 14 케이스와, 병렬 경로를 고정하는 trace 5블록 추가. 필터 이탈 UPDATE 를 열린 트랜잭션에서 실행해 stale 엔트리 (vacuum 전까지 남는 옛 인덱스 엔트리) 경로를 밟는다.
- **주요 이슈**: 헤더 문구로 첫 drop 미실행 (1), list-scan 경로 미포함 (2)
- **확인 필요 사항**: 수정 전 빌드 결과 (본문은 "아직 하지 않음 (draft)" 인데 PR 은 ready 상태)

---

## Findings

### Non-blocking (should consider)

1. `cbrd_27060.sql:27` -- 헤더에 `(autocommit off)` 가 있다. CQT (CTP 의 SQL 케이스 실행기) 의 `ConsoleBO.isPropOff` 는 문장 전체에서 `autocommit\s+off\s*;?` 를 `find()` 로 찾고, `/* */` 헤더는 첫 문장에 붙어 간다 -> 첫 문장 `drop table if exists ft;` 는 실행되지 않고 `conn.setAutoCommit(false)` 만 실행된다 (CTP `db90747`).
   - 근거: 문장 59개 중 단독 `autocommit off;` / `autocommit on;` 2개는 블록을 남기지 않으므로 57블록이어야 하는데 답지는 56블록이다. 답지는 `0, 40000, ...` 으로 시작하고, 같은 setup 을 헤더 없이 돌린 프로브는 `0, 0, 40000` 으로 시작한다.
   - 영향: (a) drop 가드가 죽어 있어 케이스 시작 시 `ft` 가 남아 있으면 (앞선 실행 중단 등) `create table ft` 가 실패하고 답지 전체가 어긋난다. (b) autocommit 이 헤더 설명과 달리 파일 처음부터 꺼져 있다. (c) 답지가 빠진 블록을 고정하므로, 헤더를 다듬어 문구가 사라지는 순간 블록 수가 바뀌어 NOK 가 된다.
   - 수정: 27행을 `open transaction with auto-commit disabled, ...` 처럼 바꾸고 답지 맨 앞에 `0` 블록 하나를 추가. 같은 패턴의 선례: CBRD-27299 (server-message on).
2. 커버리지 -- JIRA AC 1 과 엔진 PR 검증 목록이 "행 반환 (list-scan) 경로" 를 명시하지만, 14 케이스와 trace 5블록이 모두 집계라 buildvalue gather (워커별 집계를 합치는 병렬 수집) 만 지난다. mergeable list gather (워커별 결과 리스트를 합치는 수집) 는 이 TC 로 검사되지 않는다. 최신 develop 프로브: `select count(*), sum(cast(x as bigint)) from (select /*+ no_merge PARALLEL(8) */ id x from ft where del = 0 and grp between 0 and 30000 using index idx_flt(+)) t` -> trace `gather: mergeable list`, UPDATE 전 `30000 / 450015000`, 후 `27000 / 405021000`, `NO_PARALLEL_SCAN` 쌍과 동일. UPDATE 전후 한 쌍씩이면 AC 행이 채워진다. `ORDER BY` 로 행을 직접 찍는 형태는 병렬 sort 줄이 실행마다 달라질 수 있어 (tc-author sql 규칙 16) derived table + 집계 형태가 맞다.

### Questions for the author

3. PR 본문 "수정 전 빌드 검증은 아직 하지 않았습니다 (draft)" -- PR 은 draft 가 아니다. 소스 판단 (실행 아님): 수정 전 엔진은 `is_filtered_index` 게이트가 XASL (실행 계획) 생성 단계 (`px_scan_checker.cpp` `check<false> (ACCESS_SPEC_TYPE *)`, `{sa,cs}`) 에서 `CANNOT_PARALLEL_SCAN` 을 세워 filtered index 스캔을 모두 직렬로 돌린다. 따라서 PASS 14줄은 그대로 PASS 이고, trace 5블록의 `(parallel workers: ?, ..., gather: buildvalue)` 줄만 빠져 NOK 가 될 것이다. 수정 전 결과를 채울지, 이 판단을 본문에 적을지.

## JIRA -> TC

JIRA 첨부는 TC SQL 1개뿐 (`design.md` / `test.md` / `test_result.md` 없음). AC, DoD, 엔진 PR 검증 목록, 첨부 TC 17개 검사를 케이스에 대응시켰다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| AC1 covering | Case 2, 4, 9, 11 + Plan 2, 5 | 충족 |
| AC1 non-covering | Case 1, 8 + Plan 1 | 충족 |
| AC1 전범위 (WHERE 가 필터에 흡수, key range 0개) | Case 4-6, 11-13, Plan `INDEX SCAN (dba.ft.idx_flt) ()` | 충족 |
| AC1 부분 key range | Case 1, 3, 7, 8, 10, 14 | 충족 |
| AC1 desc 키 | Case 3, 5, 10, 12 + Plan 3 | 충족 |
| AC1 행 반환 (list-scan) 경로 | 없음 (모두 집계) | 미충족 (2) |
| AC2 필터 이탈 UPDATE 후 stale 엔트리 | Case 8-14, 열린 트랜잭션 + rollback | 충족 |
| AC3 기존 병렬 / 비 filtered 경로 회귀 없음 | 기존 병렬 인덱스 스캔 TC 와 CI 몫 | 범위 밖 |
| DoD covering 병렬 카운트 36000 | "Plan after the UPDATE" 가 36000 과 병렬 trace 를 함께 고정 | 충족 |
| 엔진 PR 검증: overflow OID chain | 키 0/1/2 x 1000 엔트리, `Num_ovf_page` 9 (프로브) | 충족 |
| 엔진 PR 검증: 다중 컬럼 NULL 선두 컬럼 | Case 7, 14 + Plan 4 | 충족 |
| 첨부 TC 17개 검사 | 14 케이스로 대응. (3) 은 Case 1 에 합침, (5)/(12) 비 covering vs heap 대조는 빠짐 (본문은 1건만 설명) | 부분 (영향 작음: Case 2/9 가 heap 대조 유지) |

TC 파일 검토 (tc-author sql 규칙): 배치는 Improve 이므로 `_36_guava/cbrd_27060` 이 맞다. 헤더 줄 끝 `;` 0, `--` 없음, Case 1-14 연속, `set trace on` 2 = `off` 2 이고 마지막은 off, trace 쿼리는 모두 `recompile`, 세션 변수와 파라미터 변경 없음, rollback + `autocommit on` + drop 으로 정리, 답지 있음. 출력은 모두 한 행 집계라 순서 문제가 없고 trace 숫자는 마스킹된다. 인덱스 크기는 `idx_flt` / `idx_flt_desc` 49페이지 (leaf 39 + non-leaf 1 + ovf 9), `idx_flt_mc` 77페이지로 임계 32 의 1.5 / 2.4배다. tc-author 의 3배 기준보다 작지만 CREATE INDEX 일괄 적재라 실행마다 같고, 줄면 trace 5블록이 NOK 로 알리므로 finding 으로 올리지 않았다.

판정: 케이스는 엔진 PR 이 연 경로 (filtered index 병렬 인덱스 스캔, stale 엔트리 사전 필터) 를 실제로 지나고 최신 develop 에서 결정적으로 통과한다. 1, 2 는 머지를 막지 않는다.

## Runtime Verification

| 실행 | 빌드 | 테스트케이스 | 결과 |
|---|---|---|---|
| 케이스 | gha-ci develop `4333ce3a8` optdebug (debug 슬롯, run 38338963493, `libcubrid.so` sha256 `5454f89a5b27bda7`) | `tc/CBRD-27060` @ `bb3ada018` | OK (1/1, 8.9초), 코어 0, `.result` 가 답지와 byte 동일 (56블록), 서버 로그 assert 0 |
| 프로브 (리뷰 전용, 커밋 안 함) | 같은 설치 | as-is `_99_review_adhoc/pr3712` | 비교 쿼리 14개 모두 `PARALLEL(8)` 쪽 `gather: buildvalue`, 쌍둥이는 직렬. list 경로 `gather: mergeable list`, 병렬 = 직렬 (30 -> 27행, 30000 -> 27000). `SHOW INDEX CAPACITY` 49 / 49 / 77 페이지 |

- 수정 전 / 직후 빌드는 사용자 결정으로 돌리지 않았다 (최신 develop optdebug 1회만). 수정 전 판정은 소스 기반이다 (3).
- CTP `db90747`, 컨테이너 이미지 `cubridci@sha256:79a344fc...`, pinned `parallelism=4`, `max_parallel_workers=100`, test_mode 임계 32페이지.
- `summary.info` 의 `hasAnswer=false` 는 다른 실행의 OK 6,440건에서도 같은 값이라 건너뜀 신호가 아니다. 이 케이스는 `okList`, `shouldRun=true` 다.
- 증거: `.git_ignored_dir/scratch/pr3712/evidence/` (provenance, `.result`, 프로브 SQL / 결과, 서버 로그).

## Existing Comments

| 코멘트 | 내용 | 상태 |
|---|---|---|
| greptile-apps P2, `cbrd_27060.sql:183` | Case 9/12/13 비교 쿼리에 병렬 trace 가 없어 직렬로 돌아도 PASS | 작성자 답 없음. 프로브상 현재 develop 에서는 14개 모두 병렬. 회귀 감지용 trace 추가는 작성자 판단 |
