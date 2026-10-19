# PR #3710 코드 리뷰 보고서

**PR:** [CUBRID/cubrid-testcases#3710](https://github.com/CUBRID/cubrid-testcases/pull/3710)
**제목:** [CBRD-26846] Add new test case for additional aggregate functions on parallel heap scan buildvalue
**작성자:** HyunukLee
**HEAD SHA:** `9c8b6f046` (base develop, 커밋 1개, 2026-10-12)
**JIRA:** CBRD-26846 (Improve Function/Performance, Resolved; 엔진 CUBRID/cubrid#7229, merge `d0b290459`, 2026-07-02) / 연관: CBRD-26711 (기반 기능, TC #3527 머지됨), CBRD-26982 (같은 작성자 형제 TC #3711, 다른 리뷰어)
**TC PR:** 이 PR 자체 (엔진 머지 뒤의 후속 TC PR, sql 1건 `sql/_36_guava/cbrd_26846`). 엔진 PR 의 봇 draft (cubrid-testcases#2833, private-ex#3384) 는 변경 없이 닫힘
**리뷰 일시:** 2026-10-13
**리뷰 결정:** #3710 Comment (본문 + 인라인 3건: 82, 115, 125행). 엔진 공유 머지 함수 언급과 tc-author 형식 지적은 게시 안 함

> **TL;DR** (Non-blocking): 케이스는 결정적이고 최신 develop optdebug 에서 OK, 코어 0 이다. 다만 JIRA AC 가 명시한 "다중 정렬키/NULLS FIRST" 와 "PERCENTILE 범위 오류" 가 빠졌고, BIT_AND/BIT_OR 는 워커 부분값이 모두 같아 머지 연산을 실제로 검사하지 못한다.

## Summary

- **변경 요약**: 10,000행 (109 페이지) 테이블에서 신규 11개 집계를 `PARALLEL(8)` 쪽과 `NO_PARALLEL_SCAN` 쪽으로 한 문장 안에서 비교하고 (`PASS`/`FAIL`), trace 로 병렬 쪽 `gather: buildvalue` 를 고정하는 sql 케이스 12개 추가
- **주요 이슈**: AC 시나리오 2건과 워커 오류 전파 경로 미포함 / BIT_AND, BIT_OR 데이터가 머지 결함을 가림
- **확인 필요 사항**: 본문의 "draft, 수정 전 빌드 검증 안 함" 문구 (PR 은 draft 가 아님)

---

## Findings

용어: BUILDVALUE_OPT 는 GROUP BY 없는 집계에서 각 워커가 자기 몫의 부분 집계를 만들고 `write_finalize()` 가 메인 XASL 로 합치는 병렬 heap 스캔 결과 모드다 (trace 의 `gather: buildvalue`). 쌍둥이 쿼리는 같은 집계를 옛 경로 (`NO_PARALLEL_SCAN`) 로 돌려 결과를 비교하는 기준 쿼리다.

### Non-blocking (should consider)

1. 커버리지 -- JIRA AC 2번이 "다중 정렬키/NULLS FIRST, PERCENTILE 범위 오류 케이스 포함" 을 요구하고 엔진 PR 검증 목록에도 있지만 케이스가 없다. 엔진 커밋이 새로 넣은 워커 행 단위 오류 전파 (`px_scan_task.cpp` 의 `write()` 실패 -> `ERROR_INTERRUPTED_FROM_WORKER_THREAD`) 와 JSON_OBJECTAGG NULL key 오류도 어느 케이스도 지나가지 않는다 -> 이 전파가 회귀해 병렬 쪽이 오류 대신 값을 돌려줘도 이 TC 는 통과한다. 일부 NULL 컬럼 (Case 10 은 전부 NULL) 의 리스트 경로도 없다. 최신 develop 프로브 (같은 테이블 모양, 1회) 결과, 모두 결정적인 병렬/직렬 쌍으로 쓸 수 있다:
   - `cume_dist(50, '0000000005') within group (order by cola, colb desc)`, `percent_rank(20) within group (order by pnull desc nulls first)` (pnull = 7행마다 NULL): PASS, 병렬 쪽 `gather: buildvalue`
   - `percentile_cont(1.5)`, `percentile_disc((select 1.5 from db_root))`: 병렬, 직렬 모두 `Error:-1172`, 병렬 쪽 trace `gather: buildvalue` (워커에서 오류)
   - `json_objectagg(case when id = 5000 then null else to_char(id) end, cola)`: 양쪽 `Error:-1201`
   - pnull 의 `median`, `percentile_disc ... desc`, `percentile_cont`, `group_concat(distinct ... order by)`: PASS
2. `cbrd_26846.sql:81-84` (와 Case 1 68행) -- `bit_and(cola)`, `bit_or(cola)` 는 `cola = id % 100` 이라 한 페이지 (약 92개 연속 id) 안에 이미 63 과 64 (또는 0) 가 들어 있다 -> 어떤 워커 부분값도 AND = 0, OR = 127 로 같다. 같은 값끼리는 AND, OR 어느 연산으로 합쳐도 결과가 같으므로, BIT_AND 머지가 OR 로 바뀌거나 BIT_AND/BIT_OR 의 한 워커 부분값만 빠뜨려도 0 / 127 로 PASS 한다. BIT_XOR 는 `bit_xor(id)` 로 부분값이 달라 괜찮다. 한 행만 다르게 하면 머지가 드러난다: `bit_and(case when id = 5000 then 254 else 255 end)`, `bit_or(case when id = 5000 then 1 else 0 end)` -> 최신 develop 254 / 1, PASS, `gather: buildvalue`.

### Questions for the author

3. PR 본문 -- "수정 전 빌드 검증은 아직 하지 않았습니다(draft)" 인데 PR 은 draft 가 아니다 (리뷰 요청 4명). 검증 표는 최신 develop `aea2cdf05` 한 줄뿐이다. 소스로 보면 수정 전 (`d0b290459^`) 은 checker 의 `is_buildvalue_opt_supported_function()` 가 11개 함수를 거절해 `CANNOT_BUILDVALUE_OPT` -> 병렬 쪽 trace 가 `gather: row by row` 가 되므로 12개 케이스 모두 trace 블록에서 NOK 가 날 것이다 (결과 `PASS` 는 같음). 수정 전/후 결과를 본문에 채울지, draft 문구를 지울지, 1 에서 뺀 AC 항목의 제외 이유를 적을지.

## JIRA -> TC

AC 3개, 엔진 PR 검증 목록, 첨부 `CBRD-26846_testcases.sql` 16개 검사를 케이스에 대응시켰다 (`test.md`, `test_result.md` 는 첨부 없음, 성능 xlsx 2개는 범위 밖).

| 시나리오 | 근거 | 판정 |
|---|---|---|
| AC1 11개 함수가 BUILDVALUE_OPT 에서 동작, 올바른 값 | Case 1 (값을 직접 출력, 수식으로 검증: median 49.5, percentile_cont(0.3) 29.7, cume_dist(50) 0.51) + `gather: buildvalue` | 충족 |
| AC2 병렬 = 직렬 | Case 2-12 쌍둥이 비교 | 충족 |
| AC2 혼합 집계 (COUNT/MIN/MAX/SUM/BIT_*/MEDIAN/CUME_DIST) | Case 1, 2, 11 | 충족 |
| AC2 다중 정렬키 / NULLS FIRST | 없음 | 미충족 (1) |
| AC2 PERCENTILE 범위 오류 | 없음 | 미충족 (1) |
| AC3 크래시 없음, 전체 NULL 컬럼 | Case 10, 실행 코어 0 | 충족 |
| 첨부 testcases.sql (1)-(16) | Case 2-12 에 모두 대응 | 충족 |
| GROUP_CONCAT 세 경로 (ORDER BY / DISTINCT / 없음) | Case 4, 5, 6 | 충족 |
| JSON_OBJECTAGG 중복 key first-wins | Case 12 (`JSON_ARRAY` 아님 + key 수) | 충족 |
| BIT_* 부분값 머지 | Case 1, 2 | 부분 (2) |
| 워커 오류 전파, JSON NULL key 오류, 일부 NULL | 없음 | 미충족 (1) |

TC 파일 검토 (tc-author sql 규칙): 위치 `_36_guava` 는 Improve 유형에 맞다. 헤더에 줄 끝 `;`, `--`, CQT 제어어 없음. `evaluate 'Case N` 1-12 연속, `set trace on/off` 각 1회이고 마지막 `show trace` 뒤에 off, 모든 trace 쿼리에 `recompile`, 세션 변수와 파라미터 변경 없음, 테이블 정리, 식별자에 숫자 없음, DOUBLE 은 `numeric(12,4)` 캐스팅, 답지 있음. 순서가 정해지지 않는 결과 (JSON 원소 순서, ORDER BY 없는 GROUP_CONCAT, 중복 key 생존 값) 는 길이와 타입만 비교해 결정적이다. 109 페이지는 test_mode 임계 32 페이지의 3.4배. 헤더가 55줄 (tc-author 기준 20-30줄) 이고 `/*` + 한 칸 들여쓰기지만 팀 공통 규칙이 아니라 게시하지 않는다. 겹침: cbrd_26711 은 기존 함수만, 형제 #3711 은 식 안의 MEDIAN/GROUP_CONCAT 한 건뿐이라 중복 없음.

판정: 케이스 자체는 맞고 결정적이며 수정 전 엔진을 trace 로 구분한다 (소스 기준 판단). AC 시나리오 2건 누락 (1) 과 BIT 데이터 (2) 는 회귀 검출력 문제로 머지를 막지는 않는다.

## Runtime Verification

- 실행: `BUILD=<dev-4333ce3a8> TC_REF=tc/CBRD-26846 CTP_KEEP_COPIES=1 CTP_HANG_SECS=900 just ctp sql _36_guava/cbrd_26846`
- 빌드: develop `4333ce3a8` (현재 develop head), gha-ci optdebug ("debug" 슬롯, run 38338963493), `11.5.0.2667-4333ce3`, `libcubrid.so` sha256 `5454f89a5b27bda7...`
- 테스트케이스: `tc/CBRD-26846` = `9c8b6f046541` (provenance 확인)
- 결과: OK (1/1, `.result` 가 `.answer` 와 바이트 단위로 같음, 12개 블록 모두 `PASS` 와 `gather: buildvalue`), 코어 0, 케이스 8초
- 프로브 (리뷰 전용, 커밋 안 함): `_99_review_adhoc/pr3710` 을 같은 설치본에서 1회. 결과는 Finding 1, 2 (P1-P6, 코어 0)
- 수정 전 / 수정 빌드는 사용자 결정으로 돌리지 않았다. 수정 전 NOK 는 소스 기준 판단이다 (Finding 3).
- TC 저장소 CI 는 Greptile 만 있음 (gha-ci 없음)
- 증거: `.git_ignored_dir/scratch/pr3710/evidence/` (provenance, `.result`, summary_info, 프로브 `.sql`/`.result`)

## Existing Comments

greptile-apps 요약 코멘트 1건 ("보고할 결함이 없어 병합해도 괜찮아 보입니다", 9c8b6f04 기준), 인라인 없음, 리뷰 없음. 미답 코멘트 없음.
