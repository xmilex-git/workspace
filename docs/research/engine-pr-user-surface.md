# 11.4 이후 엔진 PR 사용자 표면 매핑 (parallel query · memoize)

- 티켓: [#147](https://github.com/xmilex-git/workspace/issues/147) (맵: #144)
- 기준: CUBRID/cubrid `develop`, 11.4 분기점 `13a115a0e` (2025-05-08, [CBRD-26048] #6158) 이후 머지 커밋
- 방법: 로컬 엔진 클론(`/home/cubrid/dev/cubrid`) `git log 13a115a0e..develop --grep 'parallel|memoize'` 스윕(87건 중 CI/무관 제외 후 분류) + `git diff 13a115a0e..develop`로 시스템 파라미터·힌트·trace 문자열 표면 추출. 앵커 PR은 커밋 본문 전문 확인.
- 제외(지시): histogram/통계 계열(CBRD-26936 #7286, CBRD-26959 #7476, CBRD-26761 #7136, CBRD-27041 #7441), parallel index **build**(CBRD-26678 #7011, CBRD-26799 #7176, CBRD-27071 #7504).

핵심 사실: **parallel query 실행 스택 전체(heap scan, hash join, sort, subquery)와 memoize가 모두 11.4 분기 이후 develop에 머지**되었다. 즉 11.5 매뉴얼 관점에서 아래 표면 전부가 신규 문서화 대상이다.

## 1. 사용자 표면 총괄

### 1-A. 시스템 파라미터 (11.4 → develop 신규)

| 파라미터 | 기본값 | 범위/성격 | 도입/변경 PR |
|---|---|---|---|
| `parallelism` | **4** (26311에서 2→4) | 서버+클라이언트, FORCE_SERVER. 세션 SET 불가(USER_CHANGE 없음). 자동 병렬 실행의 기본 degree | #6141 도입, #6674 개정 |
| `max_parallel_workers` | **100** (26311에서 32→100), max 1000 | 서버 전용. 병렬 워커 풀 상한 | #6141 도입, #6674 개정 |
| `parallel_scan_page_threshold` | 2048 | **HIDDEN**. 이 페이지 수 미만이면 병렬 스캔 비활성 (구명 `parallel_heap_scan_page_threshold`, #7062에서 개명) | #6674, #7062 |
| `parallel_index_scan_page_threshold` | 32 | **HIDDEN**, FORCE_SERVER | #7062/#7516 |
| `parallel_hash_join_page_threshold` | 2048 | **HIDDEN** | #6674 |
| `parallel_sort_page_threshold` | 2048 | **HIDDEN** | #6674 |
| `memoize_memory_limit` | **2MB** | **세션 SET 가능**(USER_CHANGE, FOR_SESSION, SIZE_UNIT). **0이면 memoize 완전 비활성** (`memoize.cpp:1046-1051`) | #6555 |

HIDDEN 파라미터는 매뉴얼 표면이 아닐 수 있으나(관례 확인 필요) 동작 설명("작은 테이블은 병렬화되지 않음")에는 필요.

### 1-B. 힌트 (전부 신규)

| 힌트 | 의미 | 도입 PR |
|---|---|---|
| `PARALLEL(N)` | 병렬 degree 명시. 시스템 코어 수로 클램프(#6758), 파서에서 PRM_MAX_PARALLELISM 클램프. #7516 이후 인덱스 스캔에서 자동 활성 상한(metric)을 우회하되, 서버측 실측 페이지 수가 threshold 미만이면 직렬 강등 | #6141 |
| `NO_PARALLEL_SCAN` | 병렬 스캔(heap/index/list) 비활성. **#7062에서 `NO_PARALLEL_HEAP_SCAN`에서 개명** — 구 이름은 더 이상 없음 | #6141→#7062 |
| `NO_PARALLEL_HASH_JOIN` | 병렬 해시 조인 비활성 (SELECT/UPDATE/DELETE) | #6247 |
| `NO_PARALLEL_SUBQUERY` | 비상관 서브쿼리 병렬 실행 비활성 | #6336 (CBRD-26200) |

memoize에는 **힌트가 없다** (파서/옵티마이저에 memoize 관련 코드 없음). 제어 수단은 `memoize_memory_limit` 뿐.

### 1-C. Trace/플랜 관찰 표면 (SET TRACE ON)

- 스캔: `parallel heap` / `parallel temp` 스캔 유형 표기, `(parallel workers: N, time, fetch, fetch_time, ioread)` 라인, `executed_parallelism` (#6141, #7062).
- 인덱스 병렬 스캔: json에 `covered`/`iss`/`loose`/`mro`/`topnsort`/`count_only`/`lookup` 플래그 (#7062, #7223).
- 정렬: GROUP BY / ORDER BY / `PARALLEL ANALYTIC` 노드에 `parallel workers`, per-worker min/max `time`/`pages`/`ioreads` (#7173).
- 해시 조인: PROBE 단계에 `num_parallel_threads` (#6247, #7068).
- MEMOIZE: `MEMOIZE (time, hit, miss, size KB, enabled)` — 텍스트/json 모두. hit==0이면 출력 자체가 생략됨 (#6555 도입, #7018 출력 억제).

## 2. PR별 판정

### 2-A. 핵심 기능 (사용자 표면: 신규 기능 + 힌트/파라미터/trace)

| CBRD | PR | 내용 → 표면 |
|---|---|---|
| CBRD-25447 | #6141 (+리팩터 #6512) | parallel heap scan 도입 → `PARALLEL(N)`/`NO_PARALLEL_HEAP_SCAN` 힌트, `parallelism`/`max_parallel_workers`, trace |
| CBRD-25728 | #5694 | ORDER BY 병렬 정렬 → trace의 orderby parallel workers |
| CBRD-25717 | #6247 | PARALLEL HASH JOIN → `NO_PARALLEL_HASH_JOIN` 힌트, PROBE trace |
| CBRD-26104 | #6235 (+리팩터 #6442) | 비상관 서브쿼리 병렬 실행 |
| CBRD-26345 | #6555, #6652 | **memoize 도입** (NL join 내측 캐시, PostgreSQL Memoize 모델) → `memoize_memory_limit`(0=off), MEMOIZE trace. 힌트 없음, 플랜 표기 없음 — 실행기 런타임 기능 |
| CBRD-26722 | #7062 | heap→**heap/index/list 3종 병렬 스캔으로 일반화** → 힌트 개명 `NO_PARALLEL_SCAN`, 파라미터 개명 `parallel_scan_page_threshold` + `parallel_index_scan_page_threshold` 신설, trace `parallel temp` |

### 2-B. 제약 해제 (기존엔 직렬 강등되던 형태가 병렬화됨 — "언제 병렬이 되는가" 문서의 소재)

| CBRD | PR | 해제된 제약 |
|---|---|---|
| CBRD-26095 | #6220 | INSERT ... SELECT 도 parallel heap scan |
| CBRD-26100 | #6222 | select list에 SP 있으면 row-by-row 경로로 병렬 유지 |
| CBRD-26522 | #6806 | 구동 테이블 heap scan인 **NL join을 워커별 평가로 병렬화** (mergeable-list) |
| CBRD-26707 | #7040 | NOT EXISTS·필터 서브쿼리 존재 시에도 mergeable list 허용 |
| CBRD-26711 | #7049 | buildvalue 집계에 AVG/SUM 추가 |
| CBRD-26846 | #7229 | buildvalue 집계 확장: BIT_AND/OR/XOR, MEDIAN, GROUP_CONCAT, JSON_ARRAYAGG/OBJECTAGG, PERCENTILE_CONT/DISC, CUME_DIST, PERCENT_RANK (+워커 행 단위 에러가 직렬과 동일하게 전파) |
| CBRD-26982 | (직접 커밋 c01876ac0) | agg_cnt==valptr_cnt 제약 제거 — 비 1:1 집계 출력도 병렬 gather |
| CBRD-26795 | #7173 | 병렬 정렬 확장: SORT_GROUP_BY, SORT_ANALYTIC, SORT_ORDER_WITH_LIMIT (+내부: work-stealing 분배, 큐 기반 2-way 머지) |
| CBRD-26848 | #7223 | ORDER BY col LIMIT N의 topn_sort가 병렬 스캔 경로에서도 동작 |
| CBRD-26931 | #7316 | 비상관 **스칼라** 서브쿼리 내측 스캔 병렬화 (TPC-H Q15 회귀 12.2s→24.2s의 복구) |
| CBRD-27060 | #7467 | **filtered index** 스캔 병렬 허용 (직렬 강제 게이트 제거) |
| CBRD-27135 | #7567 | **ROWNUM(inst_num) 쿼리 병렬 스캔**: 투영 전용 ROWNUM은 머지 시 1..N 재부여, WHERE ROWNUM<=N은 공유 원자 카운터+머지 위치 재스탬프 |
| CBRD-27177 | #7625 | hash GROUP BY가 런타임에 sort GROUP BY로 강등돼도 병렬 정렬 사용 가능 |

### 2-C. 기본 동작·활성화 규칙 변경 (힌트 없이도 체감되는 변화)

| CBRD | PR | 변화 |
|---|---|---|
| CBRD-26199 | #6335, #6352 | 비상관 서브쿼리 병렬 degree를 2로 고정 |
| CBRD-26206 | #6340 | 술어에 SP 있으면 서브쿼리 병렬 비활성 (제약 **추가**) |
| CBRD-26311 | #6674 | 처리량 기반 활성화 규칙 도입 + 기본값 개정: `parallelism` 2→4, `max_parallel_workers` 32→100, scan threshold 128→2048, hash join/sort threshold 신설 |
| CBRD-26481 | #6758 | `PARALLEL(N)` 힌트를 시스템 코어 수로 제한 |
| CBRD-26013 | #6778 | 요청 병렬도 > 가용 워커여도 직렬 강등 대신 가용 워커로 실행 |
| CBRD-27100 | #7516 | 인덱스 병렬 스캔 활성화를 이중 게이트로: 무힌트 자동 결정은 **모든** key range 술어 선택도가 histogram 산출일 때만 후보(휴리스틱 폴백이면 비활성), `PARALLEL(N)`은 metric·auto-cap 우회, 실행 직전 서버가 실측 페이지 수 < `parallel_scan_page_threshold`면 직렬 폴백 |
| CBRD-26574 | #6877 | memoize 비활성 조건(1000회 시도 후 hit율<50%) 충족 시 즉시 해제 — "비활성 후에도 느려짐" 체감 제거 |

### 2-D. Trace 전용 표면

| CBRD | PR | 변화 |
|---|---|---|
| CBRD-26114 | #6241 | 파티션 테이블에서 누락되던 parallel heap scan trace 출력 |
| CBRD-26839 | #7219 | 워커 통계 미수집 시에도 zero-stats trace 방출 |
| CBRD-26681 | #7018 | memoize 미사용(hit==0) 시 MEMOIZE 항목 trace에서 제외 |
| CBRD-27184 | #7672 | 병렬 스캔 하의 NLJ trace 중복 집계 수정 (depth-k NLJ가 (k-1)배로 보고되던 것) |
| CBRD-26930 | #7289 | 병렬 정렬 degree를 실예약 워커 수로 클램프 — trace의 worker 수가 실제와 일치 |

### 2-E. 사용자 표면 없음 (내부 성능/구조)

CBRD-26370 #6606·CBRD-26431 #6710 (COUNT buildvalue), CBRD-26615 #6911 (I/O), CBRD-26648 #6949 (partial hash aggregate), CBRD-26666 #6981·CBRD-26719 #7068·CBRD-26900 #7269 (hash join 내부), CBRD-26244 #6379, CBRD-26171 #6308, CBRD-26178 #6323/#6858, CBRD-26194 #6328, CBRD-25447 #6512·CBRD-26104 #6442 (리팩터).

### 2-F. 버그픽스 (신규 표면 없음 — 크래시/hang/누수/정합성)

CBRD-26088/26090/26137/26161/26195/26210/26355/26373/26385/26413/26465/26479(×3)/26670/26863/26904/26927/26947/26965/27217, CBRD-25717 #6628 (PL/CSQL 해시조인 오답). 매뉴얼 소재 아님(릴리스 노트 소관).

## 3. 매뉴얼 함의 (요약)

1. **문서화 필수 표면**: `PARALLEL(N)`·`NO_PARALLEL_SCAN`·`NO_PARALLEL_HASH_JOIN`·`NO_PARALLEL_SUBQUERY` 힌트 4종, `parallelism`·`max_parallel_workers`·`memoize_memory_limit` 파라미터 3종(HIDDEN 4종은 관례 확인), trace 출력 형식.
2. **"언제 병렬이 되는가"**: 2-B의 제약 해제 목록 + 2-C의 활성화 규칙(#6674, #7516)이 그대로 적용 조건 절의 뼈대. 특히 #7516의 histogram 전제(무힌트 인덱스 병렬)와 서버측 threshold 폴백은 사용자 관점 반직관 포인트.
3. **memoize**: 힌트·플랜 표기 없음, 세션 파라미터 1개(0=off)와 trace가 유일한 표면 — 문서 분량은 작고 tuning/config 배치가 자연스러움(#144 미정 사항에 근거 제공).
4. 구명 `NO_PARALLEL_HEAP_SCAN`·`parallel_heap_scan_page_threshold`는 develop에 존재하지 않음 — 문서에 등장하면 안 됨.
