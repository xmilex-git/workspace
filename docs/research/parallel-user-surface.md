# 11.5 Parallel Query — 사용자 가시 표면 인벤토리

리서치 티켓: [#145](https://github.com/xmilex-git/workspace/issues/145) (맵 [#144](https://github.com/xmilex-git/workspace/issues/144))
추적 범위: JIRA CBRD-25143 링크망 + 자손 이슈 전체 (histogram·parallel index build(CBRD-26678/27071) 제외).
교차 검증: 엔진 클론 `/home/cubrid/dev/cubrid` develop (`5862371ba`, 2026-08 기준). **JIRA 서술과 코드가 다를 때는 코드를 진실로 삼았고, 그런 지점은 ⚠️로 명시했다.**

추적한 이슈: CBRD-25143(우산) — 25447(parallel heap scan)·25997·26011·26012·26095·26370·26465·26522·26615·26648·26707·26711, 25391(parallel sort) — 25728·25731·26765·26795, 25717(parallel hash join), 25977(worker manager) — 26013, 26104(parallel subquery) — 26178·26194·26199·26200·26206·26670, 26170(성능) — 26171·26174·26244, 26311(실행 규칙), 26722(parallel scan 일반화: heap/list/index), 26848(topn_sort), 26035(SP, Postponed), 26793(group locking, Open — 미구현).

---

## 1. 시스템 파라미터

정의 위치: `src/base/system_parameter.c:5145-5217`. 6개 전부 **PRM_USER_CHANGE 플래그가 없으므로 `SET SYSTEM PARAMETERS`로 온라인/세션 변경 불가** — cubrid.conf에 설정하고 서버 재시작해야 반영된다 (`PRM_USER_CAN_CHANGE`, system_parameter.c:939).

| 파라미터 | 타입 | 기본값 | 최소 | 최대 | 플래그 | 출처 |
|---|---|---|---|---|---|---|
| `parallelism` | INT | 4 | 0 | 32 (`PRM_MAX_PARALLELISM`, system_parameter.h:710) | SERVER·CLIENT·FORCE_SERVER (비히든) | system_parameter.c:5145 |
| `max_parallel_workers` | INT | 100 | 0 | 1000 | SERVER (비히든) | system_parameter.c:5157 |
| `parallel_scan_page_threshold` | INT | 2048 | 0 | INT_MAX | SERVER·**HIDDEN** | system_parameter.c:5169 |
| `parallel_index_scan_page_threshold` | INT | 32 | 0 | INT_MAX | CLIENT·SERVER·FORCE_SERVER·**HIDDEN** | system_parameter.c:5181 |
| `parallel_hash_join_page_threshold` | INT | 2048 | 0 | INT_MAX | SERVER·**HIDDEN** | system_parameter.c:5193 |
| `parallel_sort_page_threshold` | INT | 2048 | 0 | INT_MAX | SERVER·**HIDDEN** | system_parameter.c:5205 |

의미:

- **parallelism** — 하나의 병렬 연산에 허용하는 병렬 처리 수준 상한. 0이면 병렬 실행 전면 비활성화. 서버 기동 시 두 번 자동 클램프된다: 시스템 CPU 코어 수 초과 시 코어 수로, `max_parallel_workers` 초과 시 그 값으로 (system_parameter.c:10154-10167). CBRD-26311에서 기본값 2→4, 최대 MIN(32, 코어 수)로 변경.
- **max_parallel_workers** — 서버 전역 병렬 워커 스레드 풀 크기 (CBRD-25977). 모든 병렬 질의가 이 풀에서 워커를 예약(reserve)/반납한다. CBRD-26311에서 기본값 32→100, 최대 128→1000으로 변경.
- **parallel_scan_page_threshold** — heap/list 스캔 대상 페이지 수가 이 값 미만이면 병렬 스캔 비활성 (px_parallel.cpp:76-77,136-140).
  - ⚠️ JIRA CBRD-26722는 "min 2048"과 "heap/list/index가 동일 임계값 공유"라고 기술하지만, **코드의 최소값은 0**이고 **index scan은 별도 파라미터를 쓴다** (아래).
- **parallel_index_scan_page_threshold** — 인덱스 스캔 전용 임계값. 다른 것과 달리 **클라이언트(CAS/csql) 옵티마이저**가 평가한다: 드라이빙 테이블이 인덱스 스캔일 때 `metric = ceil(선택도 × 인덱스 페이지 수)`가 이 값 미만이면 병렬 차단 (src/optimizer/plan_generation.c:3229-3238). 선택도가 히스토그램 통계에서 왔을 때만(`QO_TERM_SEL_FROM_HISTOGRAM`) 자동 병렬을 허용하고, 아니면 fail-safe로 차단한다 (plan_generation.c:3212-3218).
- **parallel_hash_join_page_threshold** — 해시 조인 입력 중 작은 쪽 페이지 수 기준 (CBRD-26311).
- **parallel_sort_page_threshold** — 정렬 입력 페이지 수 기준 (CBRD-26311).

**test_mode=y일 때의 자동 오버라이드** (system_parameter.c:10169-10195; QA용, CBRD-26311): 각 임계값이 기본값 그대로면 `parallel_scan_page_threshold=32`, `parallel_hash_join_page_threshold=0`, `parallel_sort_page_threshold=0`으로 강제. `parallel_index_scan_page_threshold`는 test_mode 오버라이드가 없다.

이름 변천 (JIRA로만 확인 가능, 코드에는 최종 이름만 존재): `parallel_heap_scan_threads` → `parallelism` (CBRD-26104), `parallel_heap_scan_page_threshold` → `parallel_scan_page_threshold` (CBRD-26722).

---

## 2. SQL 힌트

힌트 테이블: `src/parser/csql_grammar.y:23979-23982`. 현존하는 병렬 힌트는 정확히 4개다.

| 힌트 | 적용 문 | 동작 | 출처 |
|---|---|---|---|
| `PARALLEL(n)` | SELECT, DELETE, UPDATE | 병렬 처리 수준 지정. n은 0..32로 클램프(`PRM_MAX_PARALLELISM`). n=0/1이면 병렬 비활성화. n≥2면 임계값 규칙을 무시하고 강제하되, 코어 수·대상 페이지 수·워커 풀 잔량으로 재클램프됨 | scanner_support.c:760-830, px_parallel.cpp:146-163 |
| `NO_PARALLEL_SCAN` | SELECT | heap/list/index 3종 병렬 스캔을 모두 비활성화 | csql_grammar.y:23979, scanner_support.c:748 |
| `NO_PARALLEL_SUBQUERY` | SELECT | uncorrelated subquery 병렬 실행만 비활성화 (CBRD-26200) | csql_grammar.y:23980 |
| `NO_PARALLEL_HASH_JOIN` | SELECT | 파티션 해시 조인의 병렬 수행만 비활성화 → 단일 스레드 해시 조인 (CBRD-25717) | csql_grammar.y:23981 |

주의 사항:

- **`NO_PARALLEL_HEAP_SCAN`은 더 이상 존재하지 않는다** — CBRD-26722에서 `NO_PARALLEL_SCAN`으로 대체·확장되었다. 초기 이슈(CBRD-25447, 25717)의 예제 쿼리에 나오는 `no_parallel_heap_scan` 표기는 개발 중간 시점 기준이며 현재 파서에 없다.
- ⚠️ **`NLJ_KEEP_HEAP_PAGE_PINNED` 힌트는 develop에 존재하지 않는다.** JIRA CBRD-26522는 이 힌트 추가를 Specification Changes로 기술하고 실제로 PR #6806(커밋 a4b37fd80)에서 추가되었으나, CBRD-26747(fixed scan 기본화)을 거쳐 **CBRD-26905 revert(커밋 1bc2c8bc9)에서 힌트가 제거**되었다. 코드가 진실: 문서화 대상이 아니다.
- `PARALLEL(n)`이 힌트로 지정되면 `parallelism` 파라미터 상한은 무시하지만 최대값(32)·코어 수는 넘을 수 없다 (CBRD-26311; px_parallel.cpp:146-158). 인덱스 스캔의 경우 힌트가 옵티마이저 metric 검사도 우회한다 (plan_generation.c:3182-3192).

---

## 3. SQL Trace / Plan 출력 (SET TRACE ON; TEXT·JSON 모두 지원)

### 3.1 병렬 스캔 (heap / list(temp) / index) — SCAN 노드 하위 서브라인

`src/query/parallel/px_scan/px_scan_trace_handler.cpp:188-320`:

```
SCAN (table: ...), (heap time: ..., fetch: ..., ioread: ..., readrows: ..., rows: ...)
     (parallel workers: N, heap|temp|index time: min..max, readrows: min..max, rows: min..max[, topnsort: true], gather: mergeable list|row by row|buildvalue)
```

- `heap`/`temp`/`index`는 스캔 타입별 라벨. min..max는 워커별 분포.
- index 스캔은 `readkeys`, `filteredkeys`와 `covered/count_only/mro/iss/loose` 불리언, 비커버링이면 후행 `(lookup time: min..max, rows: min..max)`를 추가 출력.
- `gather:` 값 3종 = 결과 수집 모드: `mergeable list`(워커별 임시 리스트 연결, CBRD-25997), `row by row`(메인이 한 행씩 수신), `buildvalue`(집계 부분누산, CBRD-26711; CBRD-26370의 "count" 라벨에서 개명).
- `topnsort: true`가 parallel workers 라인과 동시 출력될 수 있다 (CBRD-26848).
- JSON 모드 라벨: `"parallel heap" | "parallel temp" | "parallel index"` (px_scan_trace_handler.cpp:314-320).

### 3.2 병렬 해시 조인 — HASHJOIN 노드 (CBRD-25717)

`src/query/query_dump.c:3833(HASHJOIN 헤더), 4236(SPLIT), 4241(PARALLEL), 4150-4230(BUILD/PROBE)`:

```
HASHJOIN (time: ..., fetch: ..., fetch_time: ..., ioread: ..., parallel workers: N)
  SPLIT (time: ..., fetch: ..., ioread: ..., partitions: P)
  PARALLEL (time: ..., fetch: ..., ioread: ...)
    BUILD (time: min..max, fetch: ..., ioread: ..., rows: ..., method: ...)
    PROBE (time: min..max, fetch: ..., ioread: ..., readrows: ..., readkeys: ..., rows: ...)
         (parallel workers: N, time: min..min, readrows: min..max, readkeys: min..max, rows: min..max)
  SUBQUERY (uncorrelated) ...
```

11.4 대비 해시 조인 trace 형식 변화(병렬 여부와 무관하게 적용, CBRD-25717 Specification): `PARTITIONING`→`SPLIT` 개명, `part_time/build_time/probe_time/fetch_time/skew` 항목 제거, Outer/Inner 조회를 `SUBQUERY (uncorrelated)`로 분리, `OUTER`/`INNER` 노드 제거, BUILD의 `build: inner/outer`·PROBE의 `max_collisions` 제거.

### 3.3 병렬 부질의 — SUBQUERY 노드 (CBRD-26104)

`query_dump.c:3794,4020,4360`:

```
SUBQUERY (uncorrelated)
         (parallel workers: N, time: ..., fetch: ..., fetch_time: ..., ioread: ...)
```

MERGELIST 노드에도 동일 형식의 `MERGELIST (parallel workers: N, ...)` 출력이 있다 (query_dump.c:3812).

### 3.4 병렬 정렬 — ORDERBY / GROUPBY / ANALYTIC 서브라인 (CBRD-25728, 26795)

`query_dump.c:3931-4003` (TEXT), 3372-3471 (JSON):

```
ORDERBY (time: ..., sort: true, page: ..., ioread: ...)
        (parallel workers: N, time: min..max, page: min..max, ioread: min..max)
GROUPBY (time: ..., hash: true|partial|false, sort: ..., readrows: ..., rows: ...)
        (parallel workers: N, time: min..max, page: min..max, ioread: min..max)
ANALYTIC #k (time: ..., ...)
        (parallel workers: N, time: min..max, page: min..max, ioread: min..max)
```

- JSON 키: `"PARALLEL ORDERBY"`, `"PARALLEL GROUPBY"`, `"PARALLEL ANALYTIC"`, 값 안에 `"parallel workers"` (query_dump.c:3383,3420,3466).
- GROUPBY의 `hash: partial`은 병렬 스캔+해시 부분 집계(CBRD-26648)에서 나오는 새 값.
- ⚠️ CBRD-25391 초기 기술의 `P_ORDER` 노드는 구현되지 않았다 — 실제 출력은 위의 `(parallel workers: ...)` 서브라인 형식이다 (CBRD-25728 Specification Changes가 최종형).

### 3.5 기타 관측 표면

- `SHOW THREADS`에 병렬 워커(px worker)가 노출된다. 워커는 demand-spawn 방식이라 개수·RUN/FREE 상태가 비결정적이다 (CBRD-26311 comment 2026-07-08).

---

## 4. 적용 조건 · 제약 · 미적용 케이스

### 4.1 병렬 수준(degree) 결정 규칙 — `parallel_query::compute_parallel_degree` (px_parallel.cpp:36-191)

- **시스템 코어가 2개 이하면 병렬 실행 전면 비활성** (px_parallel.cpp:67-70).
- 임계값 게이트: 대상 페이지 수 < 해당 `*_page_threshold` → 비활성 (힌트가 없을 때).
- 자동 degree = `floor(log2(pages / threshold)) + 2`, 즉 임계값의 2배마다 1씩 증가 (2048페이지=2, 4096=3, 8192=4, ...; CBRD-26311의 처리량 표와 코드 일치, px_parallel.cpp:166-187). 상한: `parallelism` 파라미터.
- 힌트 degree(≥2)는 임계값 게이트와 `parallelism` 상한을 무시하되 코어 수·페이지 수로 클램프 (px_parallel.cpp:146-158).
  - ⚠️ CBRD-26311 A/C의 "병렬 처리량 기준을 만족하지 않으면 힌트가 있어도 병렬 실행하지 않는다"는 서술은 **스캔/해시조인/정렬 경로 코드와 다르다**: 코드는 힌트가 있으면 임계값 검사를 건너뛴다 (px_parallel.cpp:141-158에서 threshold 체크가 hint 분기보다 먼저지만 hint_degree ≥ 2면 threshold 실패 케이스에 도달하기 전에 개별 caller가 힌트 degree를 전달해 auto-compute를 우회). 단 **인덱스 스캔은 예외** — 옵티마이저 metric 검사는 힌트가 우회하지만 "서버가 실제 인덱스 크기로 재게이트"한다 (plan_generation.c:3134-3135).
- **부질의(SUBQUERY) degree는 2로 고정** (메인+워커; CBRD-26199, px_parallel.cpp:88-111). 힌트로도 올릴 수 없고, `parallel(0)`/`parallel(1)`로만 끌 수 있다.
- **부분 예약**: 워커 풀 잔량이 요청보다 적으면 가능한 만큼만 할당해 부분 병렬 실행, 0이면 단일 스레드 (CBRD-26013). 질의 전체의 degree 합은 `parallelism`을 넘을 수 있으나 `max_parallel_workers`는 초과 불가 (CBRD-26311).
- 병렬 실행 실패 시 항상 단일 스레드로 failback (CBRD-25717 등).

### 4.2 병렬 스캔 공통 차단 조건 (heap/list/index; CBRD-26722 Specification + CBRD-26465)

`NO_PARALLEL_SCAN`·`PARALLEL(0)` 힌트, CTE recursive part·correlated subquery(dptr)·CONNECT BY·bptr/fptr scope, `selected_upd_list` 존재(INCR/DECR), stored procedure(TYPE_SP) 포함 scope, SELECT 이외 문(UNION 등 셋 연산의 최상위·INSERT/UPDATE/DELETE — 단 4.5 참고), `select c1 from (t1, t2)` 형태, JOIN의 첫 테이블이 아닌 spec, 시스템 카탈로그/클래스, 파티션 테이블, mvcc_disabled_class, SELECT FOR UPDATE, select-list와 filter가 모두 없는 스캔, 조건절 부질의, 페이지 수 임계값 미만, MERGELIST_PROC 서브트리의 index/temp 스캔, MERGE/OBJFETCH/BUILD_SCHEMA_PROC·XASL_MULTI_UPDATE_AGG, XASL_SKIP_ORDERBY_LIST. **세션 변수·serial 사용 질의도 차단** (CBRD-26465). ROWNUM(instnum)·XASL_ANALYTIC_SKIP_SORT·XASL_ANALYTIC_USES_LIMIT_OPT는 **인덱스 spec에 한해** 차단.

### 4.3 인덱스 스캔 전용 차단 (CBRD-26722)

MIN/MAX 최적화(MRO), ISS/ILS(skip/loose scan), 사용자 KEYLIMIT, orderby_skip/groupby_skip/orderby_desc/groupby_desc, 내림차순 순회(use_desc_index), filtered index(함수 인덱스는 허용), AGL, NULL midxkey 발생. 추가로 옵티마이저 단계에서: PARALLEL 힌트가 없으면 선택도가 히스토그램 기반이 아닐 때 차단, `parallelism<=1`이면 차단 (plan_generation.c:3212-3252).

### 4.4 결과 수집 모드 지원 매트릭스 (CBRD-26722)

| Result mode | HEAP | LIST | INDEX |
|---|---|---|---|
| mergeable list | O | O | O |
| row by row (XASL_SNAPSHOT) | O | X | X |
| buildvalue (집계) | O | O | O |

LIST 전용: 리스트가 디스크로 flush되지 않고 membuf에만 있으면 단일 스레드 회귀.

### 4.5 병렬 스캔이 적용되는 패턴 (CBRD-25447, 26011, 26095, 26722)

단순 TABLE FULL SCAN, JOIN 첫 테이블이 heap/list/index 스캔, uncorrelated subquery, CTE non-recursive part, 병렬화 가능한 인덱스 범위 스캔. UNION/INTERSECTION/DIFFERENCE의 **하위 SELECT** (CBRD-26011), **INSERT ... SELECT의 SELECT부** (CBRD-26095 — 단 VALUES 절의 scalar subquery는 제외, CBRD-26465). NL join의 드라이빙 테이블이 병렬 heap scan 가능하면 조인 평가까지 워커에서 수행 (CBRD-26522; JAVASP·set scan spec·JSON_TABLE 후행 테이블이면 불가). GROUP BY 해시 부분 집계 (CBRD-26648), BUILDVALUE 집계 COUNT/MIN/MAX/SUM/AVG/STDDEV*/VAR* 및 DISTINCT 변형 (CBRD-26370, 26711), EXISTS/NOT EXISTS·IN(subquery)·scalar subquery가 있는 필터 (CBRD-26707), ORDER BY LIMIT의 topn_sort (CBRD-26848).

### 4.6 병렬 해시 조인 제약 (CBRD-25717)

Click counter 함수(INCR/DECR, WITH INCREMENT FOR)가 있으면 해시 조인 자체가 불가(NL 등으로 대체). 병렬 degree는 분할 파티션 개수를 초과할 수 없다 (CBRD-26311). 요청 병렬 수준이 풀 크기를 초과하면 단일 스레드 수행.

### 4.7 병렬 부질의(uncorrelated subquery) 제약 (CBRD-26104, 26206, 26670)

미적용: top-level XASL에 연결되지 않은 부질의, CTE recursive part·CTE 간 참조, aptr 간 참조(뷰를 해시 조인하는 경우 포함), path expression, dblink, method, set scan spec, SHOW 문, JSON_TABLE, RECORD_INFO/PAGE_INFO/sampling scan, select-list의 scalar subquery·WHERE 조건 내 subquery. **조건절 포함 어디든 JAVASP/PLCSQL이 있으면 차단** (CBRD-26206), **분석함수 인자 안의 세션 변수도 차단** (CBRD-26670). 어떤 aptr이 다른 aptr의 종료를 기다려야 하는 의존 구조면 병렬 포기 (CBRD-26104 comment).

### 4.8 병렬 정렬 적용 범위 (CBRD-25391, 25728, 26795)

지원: ORDER BY, GROUP BY 정렬 단계, 분석함수(OVER) 정렬 단계, ORDER BY+LIMIT(topnsort 임계 2MB 초과 시). 행 수가 병렬도 이하이거나 입력 0건이면 단일 스레드 폴백. SORT_LIMIT 플랜(top-N early stop)은 병렬 인덱스 스캔과 결합하지 않음 (plan_generation.c:3101-3104). CREATE INDEX의 정렬 병렬화는 본 인벤토리 범위 밖(CBRD-26678).

### 4.9 미구현/미해결 (문서화 금지 대상)

- CBRD-26793 (병렬 워커 group locking) — Open, 미구현.
- CBRD-26035 (SP 포함 질의의 mergeable-list) — Postponed.
- CBRD-25391 자체는 Confirmed/Unresolved 상태지만 하위 25728(ORDER BY)은 Closed, 26795(GROUP BY/ANALYTIC/LIMIT 확장)는 Develop 상태 — **26795 범위는 릴리스 노트·매뉴얼 반영 전 머지 여부 재확인 필요.** (trace 코드에는 PARALLEL GROUPBY/ANALYTIC 출력이 이미 존재하므로 머지된 것으로 보이나, JIRA 상태가 Develop이므로 명시 확인 권장.)

---

## 5. 11.4 대비 기본 동작 변화

1. **병렬 실행이 기본 활성.** `parallelism` 기본 4, 임계값 기본 2048페이지(≈32MB) — 힌트 없이도 대량 테이블 스캔·해시 조인·정렬·부질의가 자동 병렬화된다 (CBRD-26311).
2. **ORDER BY 없는 질의의 행 순서가 달라질 수 있다.** 병렬 스캔/mergeable list가 페이지 소비 순서를 바꾸므로 결과 집합 순서가 비결정적이 된다 — 기존 TC 답지 다수가 이 이유로 갱신됨 (CBRD-25447 comment 2025-02-18, CBRD-26722 comment 2026-05-28).
3. **해시 조인 trace 형식이 병렬 여부와 무관하게 변경** (SPLIT 개명, OUTER/INNER 제거 등 — §3.2, CBRD-25717).
4. **`UPDATE STATISTICS ... WITH FULLSCAN`이 병렬 count(distinct) 경로를 탄다** (CBRD-26370).
5. **병렬 정렬로 임시 파일(temp volume) 사용량이 증가**할 수 있다 (CBRD-25728 comment 2025-09-24).
6. **`SHOW THREADS` 출력에 px 워커가 추가**되고 개수가 비결정적 (CBRD-26311 comment).
7. **서버 스레드 엔트리 수 증가**: 기존 `(2×max_clients)+vacuum+데몬`에 병렬 워커 풀 분이 추가 할당 (CBRD-25977 comment 2025-03-21).
8. GROUP BY 집계가 병렬 스캔에 연결되면 hash aggregate 크기 한도를 넘어도 해시 집계로 수행 (`hash: partial`; CBRD-26648 comment 2026-06-26).

---

## 부록 — JIRA ↔ 코드 불일치 요약 (코드가 진실)

| # | JIRA 서술 | 코드 사실 | 근거 |
|---|---|---|---|
| 1 | CBRD-26722: `parallel_scan_page_threshold` min 2048 | min 0 | system_parameter.c:5177 |
| 2 | CBRD-26722: heap/list/index가 단일 임계값 공유 | index는 별도 `parallel_index_scan_page_threshold`(기본 32, 옵티마이저 평가) | system_parameter.c:5181, plan_generation.c:3229 |
| 3 | CBRD-26522: `NLJ_KEEP_HEAP_PAGE_PINNED` 힌트 추가 | 커밋 1bc2c8bc9(CBRD-26905 revert)에서 제거되어 현존하지 않음 | csql_grammar.y 힌트 테이블, git log -S |
| 4 | CBRD-25391: trace에 `P_ORDER` 노드 | `(parallel workers: N, ...)` 서브라인 형식으로 구현 | query_dump.c:3995, CBRD-25728 |
| 5 | CBRD-26311 A/C: 임계값 미달이면 힌트가 있어도 병렬 안 함 | 스캔/조인/정렬은 힌트(≥2)가 임계값을 우회; 인덱스만 서버 재게이트 | px_parallel.cpp:146-158, plan_generation.c:3134 |
| 6 | CBRD-26370: trace 라벨 `count` | CBRD-26711에서 `buildvalue`로 개명 | px_scan_trace_handler.cpp:193 |
