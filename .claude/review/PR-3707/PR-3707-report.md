# PR #3707 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases#3707](https://github.com/CUBRID/cubrid-testcases/pull/3707)
**제목:** [CBRD-27205] Add new test case for parallel scan with correlated derived tables
**작성자:** HyunukLee
**HEAD SHA:** `203c1614f` (base develop, 커밋 1개)
**JIRA:** CBRD-27205 (Sub-task, Resolved; 부모 CBRD-27152 Improve Function/Performance, Confirmed; 엔진 CUBRID/cubrid#7794, squash merge `46e0abd95`, 2026-09-22) / 연관: CBRD-27291 (선행 조건)
**TC PR:** 이 PR 자체 (엔진 머지 뒤의 후속 TC PR, sql 1건 `sql/_36_guava/cbrd_27205/{cases,answers}`). 엔진 PR 의 봇 draft (cubrid-testcases#3353, private-ex#3990, `tc/pr-7794`) 는 변경 0파일로 2026-09-22 닫힘
**리뷰 일시:** 2026-10-13
**리뷰 결정:** #3707 Comment (본문 + 인라인 2건: 120행 Case 5, 82행 heap 쪽 분기 + develop 프로브 SQL). Greptile 3건은 본문에서 스레드 답변 요청, 형식 지적은 게시 안 함

> **TL;DR** (Non-blocking): 최신 develop optdebug (`4333ce3a8`) 에서 OK, 코어 0, `.result` 가 답지와 바이트 단위로 같다. 케이스는 JIRA 첨부 TC 11개를 CTP 용으로 옮긴 것이고, Case 2, 5 의 trace 와 Case 10 의 행별 비교가 수정 전 엔진을 가른다 (소스 판단, 실측 아님). Case 5 는 "sort GROUP BY" 라고 적혀 있지만 답지상 해시 집계로 돌고, 엔진 PR 이 heap scan 쪽에 넣은 두 분기는 어느 케이스도 지나지 않는다.

## Summary

- **변경 요약**: 바깥 인덱스 스캔 + FROM 절 상관 파생 테이블 질의 11개를 `PARALLEL(4)` 와 `NO_PARALLEL_SCAN` 으로 실행해 `<=>` 와 상수로 PASS/FAIL 을 내는 sql 케이스 1건과 답지
- **주요 이슈**: Case 5 의 해시 집계 (`hash: true`) / heap scan 경로 미검사 / Greptile 미답 지적 3건
- **확인 필요 사항**: PR 본문의 "(draft)", "수정 전 빌드 검증은 아직" 문구 (PR 은 이미 리뷰 요청 상태)

---

## Findings

### Non-blocking (should consider)

1. `cbrd_27205.sql:117-122` (헤더 33행, PR 본문 커버리지 5행) -- Case 5 를 "sort GROUP BY inside the derived table" 라고 부르지만, 파생 테이블에 `no_hash_aggregate` 가 없어 답지 130행이 `GROUPBY (time: ?, hash: true, sort: true, ...)` 다. `hash: true` 는 해시 집계가 모든 행을 받아들였다는 뜻 (`query_dump.c` 의 `HS_ACCEPT_ALL`) 이다. 정렬 기반 GROUP BY 를 쓰는 Case 11 에는 trace 가 없으므로 (Greptile 기존 지적), 이 파일에서 "병렬 워커 안에서 정렬 기반 GROUP BY 를 도는 비연결 dptr" 을 trace 로 보여주는 케이스가 없다. 비연결 dptr 은 값으로 참조되지 않고 바깥 행마다 다시 실행되는 상관 서브쿼리 (`XASL_LINK_TO_REGU_VARIABLE` 가 없는 `dptr_list` 항목) 를 말한다. Case 5 파생 테이블에 `/*+ no_hash_aggregate */` 를 넣으면 trace 가 Case 10 처럼 `hash: false, sort: true` 로 바뀌고 Case 11 경로의 병렬 증거가 된다 (develop 실행은 확인 안 함). 넣지 않는다면 헤더와 본문의 이름을 바꾸면 된다.
2. 커버리지 -- 비연결 dptr 케이스 9개 (2-9, 11) 가 모두 `using index ix_o27205(+)` 로 바깥 인덱스 스캔에 고정돼 있고, 계획은 모두 `NESTED LOOPS (INDEX SCAN o, TABLE SCAN (d))` 라 스캔 체인의 마지막이 파생 테이블 리스트 스캔이다 (답지 57-59, 115-117, 165-167행). 그래서 엔진 PR 이 heap 쪽에 넣은 두 분기를 어떤 케이스도 지나지 않는다.
   - `px_scan_task.cpp`: 체인에 dptr 이 있으면 체인 마지막 inner heap scan 을 fixed scan 대신 cached scan (페이지를 워커 로컬로 복사해 읽어 래치를 잡지 않는 heap scan) 으로 연다 (`inner_cached_scan`). JIRA 첨부 테스트 설명이 "검수 중 잡은 실버그 2. per-row dptr 실행 간 fixed-page guard" 로 꼽은 결함이다.
   - `px_scan_checker.cpp`: row-by-row fallback (결과를 합칠 수 없을 때 워커가 행 단위로 넘기는 모드) 에서 비연결 dptr 이 있으면 heap spec 도 `ACCESS_SPEC_FLAG_NO_PARALLEL_SCAN` (`nonlinked_dptr ||`). PR 본문 설명대로 이 모드의 워커는 after_join/if 술어를 dptr 실행 전에 평가한다. 인덱스 spec 은 수정 전부터 이 분기에서 직렬이었으므로, 새 조건은 heap 바깥 스캔에서만 의미가 있다.
   - 두 분기 중 하나가 회귀해도 이 TC 는 통과한다. develop `4333ce3a8` 프로브 (CTP 2회 동일, 코어 0, `scratch/pr3707/probe-heap/notes.md`): A 는 인덱스 없는 t27205 (500행) 를 `ordered use_nl` 로 체인 끝에 둔 모양에서 바깥 o 가 `gather: buildvalue` 병렬이고 체인 끝이 t heap scan, 결과 150000 / 37575000 = 직렬. B 는 `rownum <= 100000` 을 둔 집계에서 바깥 heap 이 직렬 (dptr 없는 대조군은 `gather: row by row`), 3000 / 4501500 = 직렬. 분기 도달은 trace + 코드 조건 판단이며 breakpoint 확인은 아니다. B 는 수정 전도 직렬이라 `nonlinked_dptr ||` 회귀만 지킨다.
3. PR 본문 -- "수정 전 빌드 검증은 아직 하지 않았습니다(draft)" 인데 PR 은 draft 가 아니고 리뷰어가 지정돼 있다. 검증 표에는 최신 develop `aea2cdf05` 한 줄뿐이다. 소스로 판단하면 수정 전 (`46e0abd95^`) 에서는 Case 2, 5 의 `parallel workers` 줄이 사라지고 (옛 checker 가 비연결 dptr 이면 `CANNOT_PARALLEL_SCAN`), Case 10 은 행 값이 틀리거나 (JIRA 첨부: 3000행 중 2999행 불일치) optdebug 에서 `qmgr_get_page_type` assert 로 서버가 중단될 수 있다 (엔진 PR 본문). 나머지 8케이스는 양쪽 다 직렬이라 수정 전에도 PASS 다. 실측은 하지 않았다 (사용자 결정). 본문 커버리지 8, 9행의 "직렬" 도 케이스가 확인하지 않는다 (Greptile 기존 지적).

## JIRA -> TC

JIRA 본문 AC, 첨부 `CBRD-27205_testcase_description.md` (양성 P1-P5, 음성 N1-N3, 회귀 R1-R2, 검수 중 실버그 3건), 엔진 PR 본문 Implementation 을 케이스에 대응시켰다. JIRA 에 `design.md` / `test.md` / `test_result.md` 는 없다.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| P1 기본 상관 파생 테이블 count(*) | Case 2 (trace `gather: buildvalue`, 상수 3000) | 충족 |
| P2 행 반환, P3 내부 조인, P5 스칼라 집계 | Case 3, 4, 6 (병렬 = 직렬, 상수) | 충족 (trace 없음, 같은 계획 모양은 Case 2) |
| P4 파생 테이블 안 sort GROUP BY | Case 5 (trace 는 `hash: true`) | 부분 (1) |
| N1 serial `NEXT_VALUE` 직렬 | Case 7 (trace 에 `parallel workers` 없음) | 충족 |
| N2 `@v :=`, N3 PL 함수 직렬 | Case 8, 9 (합계만) | 부분 (Greptile) |
| R1 select-list sort GROUP BY 비그룹키 집계 | Case 10 (trace `mergeable list`, 행별 비교) | 충족 (Greptile 보강 제안) |
| R2 같은 GROUP BY 를 상관 파생 테이블로 | Case 11 (trace 없음) | 부분 (Greptile) |
| 실버그 1 코디네이터 빈 리스트 -> 0행 | Case 2, 4, 6, 11 상수 | 충족 |
| 실버그 2 inner heap scan cached scan | 없음 | 미충족 (2) |
| row-by-row fallback + 비연결 dptr 직렬 | 없음 | 미충족 (2) |
| dptr 안 중첩 병렬 계획 시점 차단 (`parallelism = 1`) | Case 5 GROUPBY 에 병렬 줄 없음 | 구분 못 함: 실행당 4행이라 차단이 없어도 직렬 |
| checker 거부 (analytic, CONNECT BY, ISS/ILS/keylimit, CTE/MERGE) | 없음 | 미포함: 결과가 같아 trace 로만 보임, 본문 미기재 |
| AC4 parallel scan CTP 회귀 없음 | 엔진 PR CI 범위 | 해당 없음 |

TC 파일 검토 (tc-author sql 규칙): 헤더에 줄 끝 `;`, `--`, CQT 제어어 없음. `evaluate 'Case 1..11'` 연속, `set trace on/off` 각 4회이고 마지막은 off, 추적 질의는 모두 `recompile`. `@v27205` 해제, 함수/serial/테이블 정리. 문장 58개 = 답지 블록 58개. 크기 여유: b-tree 109 / heap 121 페이지 대 임계값 32 (3.4배, 3.8배, 규칙 3배 이상). 배치: Sub-task 는 부모 유형 (Improve) 을 따르므로 `_36_guava` 가 맞다. 헤더 48줄과 식별자의 숫자는 tc-author 자체 규칙 (20-30줄, 숫자 금지) 과 다르지만 팀 공통 규칙이 아니고 마스킹 후에도 `ix_i?_k` / `ix_i?_k?` 가 구분돼 게시하지 않는다. 겹치는 기존 TC 없음 (`_36_guava` 에서 dptr / correlated 검색, cbrd_27568 은 집계 피연산자 쪽).

판정: 케이스는 최신 develop 에서 결정적으로 통과하고, 소스상 Case 2, 5, 10 이 수정 전 엔진을 가른다. 1, 2 와 Greptile 3건은 회귀 검출력 문제이며 머지를 막지 않는다.

## Runtime Verification

| 빌드 | 테스트케이스 | 결과 |
|---|---|---|
| develop `4333ce3a8` (gha-ci run 38338963493, optdebug "debug" 슬롯, `libcubrid.so` sha256 `5454f89a5b27bda7...`) | `tc/CBRD-27205` `203c1614f520` (provenance.txt) | OK 1/1 (`cbrd_27205.sql:ok 3595ms`), 코어 0, `.result` = 답지 (diff 없음) |

- 실행: `BUILD=<install> TC_REF=tc/CBRD-27205 CTP_KEEP_COPIES=1 CTP_HANG_SECS=900 just ctp sql _36_guava/cbrd_27205`, 컨테이너 고정 파라미터 `parallelism=4 max_parallel_workers=100 data_buffer_size=512M`.
- 답지 생성 빌드 `aea2cdf05` 이후 develop 커밋 9개, 출력 차이 없음.
- 수정 전 (`46e0abd95^`), 수정 직후 (`46e0abd95`) 빌드와 gha-ci 는 사용자 결정으로 돌리지 않았다. 수정 전 판별력은 Finding 3 의 소스 판단이다. 결정성은 1회 실행 + 작성자 보고 (CTP Fail:0 x2) 뿐이다.
- 증거: `.git_ignored_dir/scratch/pr3707/evidence/` (provenance, `.result`, summary_info, 실행 로그). 실행 디렉터리와 빈 코어 디렉터리는 삭제했다.

## Existing Comments

| 코멘트 | 위치 | 내용 | 상태 |
|---|---|---|---|
| greptile 4254097438 | `cbrd_27205.sql:166` | Case 8, 9 는 합계만 비교해 직렬 실행을 확인하지 않음, trace 추가 요청 | 미답, 타당 (JIRA 첨부 설명도 음성 3건을 "trace 로 병렬 미발동 확인" 이라 적음) |
| greptile 4254097443 | `cbrd_27205.sql:209` | Case 11 에 trace 가 없어 직렬로 바뀌어도 PASS | 미답, 타당 (Finding 1 과 같이 보면 정렬 GROUP BY 병렬 증거가 파일에 없음) |
| greptile 4254097447 | `cbrd_27205.sql:198` | Case 10 이 키 누락과 중복을 함께 놓칠 수 있음 | 미답, 타당하나 낮음 (`count(distinct k)` 한 줄로 막힘) |
