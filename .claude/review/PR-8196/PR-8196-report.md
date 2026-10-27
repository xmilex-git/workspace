# PR #8196 코드 리뷰 보고서

**PR:** [CUBRID/cubrid#8196](https://github.com/CUBRID/cubrid/pull/8196)
**제목:** [CBRD-27361] Page batch execution: heap scans in chunks, vector filters, hash GROUP BY merge and hash join runtime filter
**작성자:** soheejung-cs
**HEAD SHA:** `908bdc5af` (develop merge-base `c966fabc6`)
**JIRA:** CBRD-27361 (Improve Function/Performance, Open) / 연관: 없음
**TC PR:** CUBRID/cubrid-testcases#3791 (`tc/pr-8196` `20f030b6f`, draft, 52파일) / CUBRID/cubrid-testcases-private-ex#4469 (`tc/pr-8196` `8ee3462ca`, draft, 47파일)
**리뷰 일시:** 2026-10-21
**리뷰 결정:** 엔진 PR #8196 Request changes (+ Greptile 4322136746 스레드 답글) / TC PR cubrid-testcases#3791 Comment / cubrid-testcases-private-ex#4469 리뷰 없음

> **TL;DR** (Blocking): 새 해시 GROUP BY 잔여분 병합이 부분 집계 튜플을 잘못 읽어, 집계 함수가 11개 이상인 GROUP BY 가 해시 축출을 겪으면 release 는 `Internal system failure`, optdebug 는 assert 로 서버가 죽는다(기본 설정, develop 정상). Greptile 이 지적한 배치 GROUP BY 캐시의 축출 그룹 잔존도 오답으로 재현됐다.

## Summary

- **변경 요약**: 힙 스캔을 페이지 청크 단위 배열 연산으로 바꾸고(집계·투영·해시 GROUP BY·조인 바깥 필터), 해시 GROUP BY 잔여분 해시 병합·그룹 slab·해시 조인 런타임 필터를 추가
- **주요 이슈**: `query_aggregate.cpp:4182` 부분 집계 튜플 NULL 비트맵 크기 오산 -> GROUP BY 오류/서버 abort, 배치 GROUP BY 캐시 오답(기존 Greptile 코멘트)
- **확인 필요 사항**: JIRA 의 hidden 파라미터 on/off 부재, 런타임 필터로 병렬 해시 조인 TC 5건이 원래 경로를 잃은 점, JIRA 범위 밖 기능(런타임 필터·해시 병합·slab)의 티켓/PR 분리

---

## Findings

### Blocking (must fix)

- `src/query/query_aggregate.cpp:4182` — 새 `qdata_load_agg_hkey_from_tuple()` 이 부분 집계 튜플(해시 축출로 partial list 에 나간 그룹: 키 + 집계마다 value/value2/count 3열 + tuple_count)을 키 개수만으로 걷는다 -> NULL 비트맵 크기를 키 열 수로 계산해 열이 33개 이상이면 키 시작 위치가 어긋남 -> 잔여분 병합(`qexec_gby_merge_split_list()`, 병렬은 `qexec_gby_px_split_list()`)이 쓰레기 키를 읽는다. 결과는 release `ERROR: Internal system failure`, optdebug(assert 가 켜진 최적화 빌드) `qfile_tuple_layout.h:1005` assert(SIGABRT, 서버 재기동). 페이지 배치와 무관한 일반 GROUP BY 경로라 JIRA 의 "게이트 불충족 질의 결과 불변" 도 깨진다. 같은 파일의 기존 `qdata_load_agg_hentry_from_tuple()` 은 전체 열 수를 넘긴다.
  ```c
  qfile_tuple_walk_init (&walk, tuple, hdr_size, key->val_count);                               /* 4182, 새 함수 */
  qfile_tuple_walk_init (&walk, tuple, hdr_size, key->val_count + 3 * value->func_count + 1);   /* 4087, 기존 */
  ```
  재현(기본 conf): 키 1개 + 집계 11개(`count(*)`, `sum(i)`, `sum(i + 0..8)`) GROUP BY, 5038그룹 300000행 -> head 오류 / develop 5038행. 집계 10개(열 32개)는 head 도 정상. 재현 SQL: `.git_ignored_dir/scratch/pr8196/evidence/repro-hash-merge-11aggs.sql`.

### Non-blocking (should consider)

- `src/query/query_hash_join.c:4673` — 런타임 필터(해시 조인의 작은 입력 키로 다른 입력의 가장 바깥 스캔 행을 미리 거르는 기능)를 끌 방법이 없다 -> JIRA DoD 의 hidden 파라미터 on/off 미충족, 기존 병렬 해시 조인 TC 가 원래 경로를 유지할 수단도 없음(아래 TC PRs 참조). 힌트나 hidden 파라미터 하나가 필요해 보인다.
- 서버 코드 신규 할당/해제 규약 — 추가된 줄에 맨 `free()` 45곳(예: `query_executor.c` `qexec_gby_merge_free_list` 주변, `query_aggregate.cpp` slab 해제), 맨 `malloc`/`calloc`/`realloc` 51곳(예: `scan_manager.c:8254` `hsidp->batch = (EXPR_BATCH *) malloc (...)`). `reference.md` 규약은 `free_and_init()` / `db_private_alloc()`. develop `query_executor.c` 는 `free_and_init` 123 : 맨 `free` 9.
- 주석 8곳(`expr_batch.c:43`, `expr_batch.h:43,133,182`, `query_aggregate.hpp:189`, `query_executor.c:5578,11692`, `query_hash_join.c:4673`) — "database-reference 참고:" 로 외부 코드베이스의 내부 심볼(`ColumnBuilder::Build`, `PpNodeUseColumnInfo`, `InvalidateRowsByFilter`, `RowPos`, `ExAggr`, `NumberAccum`, `exaggr_apply`)을 한국어 혼용으로 인용 -> 그 소스 없이는 주석을 이해할 수 없음(주석 단독 이해 규칙).
- `src/query/query_executor.c:5782,5788` — 병합 표 초기 크기 `calloc (1024, ...)` / `t->mask = 1023` 가 이름 없는 상수.

### Questions for the author

- `query_hash_join.c` 런타임 필터, `query_executor.c` 잔여분 해시 병합·병렬 병합, `query_aggregate.cpp` 그룹 slab 은 CBRD-27361 본문·설계 문서에 없는 기능이다. PR 본문이 제안한 6개 리뷰 단위대로 티켓/PR 을 나눌 계획인지?
- GROUP BY trace 에서 병렬 정렬의 `(parallel workers: ...)` 줄과 JSON `PARALLEL GROUPBY` 블록이 사라졌다(`cbrd_20865`, `hash_agg_query_profile` 답안). 병렬 해시 병합의 워커 수·시간은 어디서 보이는지?

## JIRA -> Engine PR

기준: Expected Result(Acceptance Criteria)가 재현 조건에서 성립하고, 설계 문서(`DESIGN_VECTOR_SCAN_AGG.md`, design.md/test.md 첨부는 없음)의 변경이 구현되며, DoD 가 충족되면 승인.

| 항목 | PR 상태 | 판정 |
|---|---|---|
| AC1 lineitem 필터 스캔 2배 이상 | PR 본문 F01-F15 직렬 기하평균 0.37 (CI 수정 전 빌드) | 충족 |
| AC2 Q01/Q06/Q15 개선, TPC-H 22 정합 | PR 본문 Q1 0.27, Q6 0.41, Q15 0.55, 22개 결과 동일 | 충족 |
| AC3 게이트 불충족 질의 플랜·결과·성능 불변 | 집계 11개 이상 GROUP BY 오류(Blocking 1), 런타임 필터가 해시 조인 플랜을 바꿈 | 미충족 |
| AC4 스캔 중 UPDATE/vacuum 동시성 퍼저 | PR 본문은 RR 2세션 재현뿐. 리뷰 smoke 의 RC 미커밋 DML 동시 집계는 develop 과 동일 | 부분 |
| DoD hidden 파라미터 on/off | 파라미터 추가 없음 | 미충족 (Non-blocking 1) |
| DoD CTP 전수 + 게이트 경계 화이트박스 TC | CI 전수 통과, shell `cbrd_27361` 은 GROUP BY 없는 집계만 | 부분 |
| DoD 성능 수치 JIRA 기록 | PR 본문에만 있음 | 부분 |
| 설계: 워커 루프 삽입, 직렬 확대, 가시성 일괄 판정, 화이트리스트 게이트 | 구현(`heap_page_collect_visible()`, `scan_batch_*`, 거절 사유 trace) | 충족 |
| 범위 밖: 런타임 필터, 해시 병합, slab | 티켓에 없음 | 질문 |

연관 이슈: 없음. 판정: **미충족** (AC3, DoD hidden 파라미터).

## TC PRs

기준: 엔진 PR 검증 항목과 JIRA test.md(없음)의 시나리오가 TC PR 에 있으면 통과.

| 시나리오 | 근거 | 판정 |
|---|---|---|
| 그룹 없는 집계: 타입·필터·바인드·overflow·ALTER·거절 모양 | private-ex `cbrd_27361/batch_agg.sql` + coverage digest | 통과 |
| CI 대응 수정 7건(cbrd_26431, cbrd_27215, cbrd_24668, _t4_14_blank_value_1, _03_partition_num, heavy_outerjoin, sum_gby) | 기존 TC, CI run 39374265629 통과 | 통과 |
| 런타임 필터 병렬 차수 변화 | `cbrd_26311_degree.sh` 기대값 4 -> 2 | 통과 |
| 해시 GROUP BY 배치 노드(키 바이트 캐시, LRU 축출) | 없음 (`batch_agg.sql` 은 GROUP BY 를 "행 경로" 로만 확인) | 미흡 |
| 잔여분 해시 병합(DISTINCT, respect_order=no, 압축, 병렬) | trace 답안 갱신뿐 | 미흡 |
| 런타임 필터 정합(INNER/SEMI/LEFT/ANTI, NULL 키, 타입) | 없음 (PR 본문 21질의는 로컬) | 미흡 |
| 문자열·IN·OR·SUBSTRING 리프, 조인 바깥 필터 | `batch_agg.sql` 일부(IN, OR, NOT, LIKE), SUBSTRING 없음 | 부분 |

TC 파일 검토: 답안 변경은 모두 trace 줄이며 결과값 변경은 없음(PR 본문 주장과 일치), 헤더 주석에 `;` 없음. 다만 런타임 필터 때문에 병렬 해시 조인 전용 케이스 5건이 그 경로를 잃은 채 답안만 갱신됐다: `cbrd_25717_nm_skew_join`(Case 3 skew build 작업 분배), `cbrd_25717_empty_input`, `cbrd_25717_during_join_predicates`, `cbrd_27561` 2건. 리뷰 재실행에서 skew Case 3 은 필터가 100000행 중 99599행을 버려 SPLIT/PARALLEL 없이 메모리 해시 조인으로 끝남(develop: SPLIT 13분할, memory+file). 판정: **보완 필요** (해시 GROUP BY·병합·런타임 필터 TC 추가, 병렬 해시 조인 케이스의 원래 경로 유지).

## Runtime Verification

- CI: gha-ci run 39374265629, head `908bdc5af`(debug=optdebug), `tc/pr-8196`(testcases `20f030b6f`, private-ex `8ee3462ca`) — sql 17592, medium 975, shell 3390 통과. `Check TC PRs` 만 실패(TC PR draft).
- 리뷰 smoke (gha-ci tarball, CTP 아님): head optdebug(`libcubrid.so` sha256 `1dcabf9f`), head release, develop `c966fabc6` optdebug(`409b4b10`), 각자 새 DB, `data_buffer_size=512M`.
  - 집계·필터 73모양 x 직렬/`parallel(4)` (NUMERIC·정수·DATE·문자열·CHAR 리프, IN/NOT IN NULL, OR/NOT, 두 컬럼, 상수 범위 밖, 문자열 상수 강제변환): head = develop.
  - 미커밋 UPDATE/DELETE/INSERT 중 직렬·병렬 집계, GROUP BY, 조인: head = develop.
  - Blocking 1: head release 오류, head optdebug SIGABRT(`qexec_gby_merge_split_list` -> `qdata_load_agg_hkey_from_tuple`, bt `evidence/core-gw1009-bt.txt`), develop 정상. 집계 수 경계 10/11 확인.
  - Greptile 4322136746: `max_agg_hash_size=64K` 에서 가변 길이 키 GROUP BY head 직렬 300000행 중 3행 유실·73그룹 오답, `parallel(4)` 41그룹 오답, 고정 길이 키는 정답, develop 정답. 기본 2M 에서는 이번 시도로 재현 못함.
- 실행하지 않은 것: CTP 재실행(CI 증거로 대체). vacuum 동시성·페이지 해제는 1번세션(2번 항목), 성능은 2번세션(3번 항목), CHAR 는 3번 세션(4번 항목), LIKE 바이트 경로는 4번 세션(5번 항목), PostgreSQL 비교는 6번 세션(6번 항목)이 따로 리뷰한다.

## Existing Comments

| 코멘트 | 요지 | 리뷰 확인 |
|---|---|---|
| Greptile 4322136746 `query_executor.c:11913` | 다중 축출 시 `qexec_gby_cache_evicted()` 가 옮겨진 항목을 못 지움 | 오답 재현 (위 Runtime Verification) |
| Greptile 4322136755 `query_executor.c:7039` | `out_partials` 할당 실패 시 정리에서 NULL 역참조 | 코드상 성립 |
| Greptile 4322136765 `expr_batch.c:3680` | FALLBACK 시 필터 부작용 반복 | 코드상 성립, 시리얼 NEXTVAL 은 배치 거절로 미재현 |
| Greptile 4322136772 `expr_batch.c:3471` | NULL NUMERIC 셀 미초기화 읽기 | 코드상 성립, 값은 쓰이지 않음 |

네 건 모두 작성자 답변 없음.
