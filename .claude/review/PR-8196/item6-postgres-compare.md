# PR 8196 항목 6 — PostgreSQL 실행기(Volcano)와의 차이·한계

작성: 6번 세션, 2026-10-21.
대상: CUBRID/cubrid#8196 head `908bdc5af` (develop merge-base `c966fabc6`). 비교 대상: `~/dev/postgres` `26a3c0a45cc` (master, `REL_19_BETA1-1025`, 2026-09-18). 아래 줄 번호는 각 커밋 기준이다.

## TL;DR

PostgreSQL 실행기는 계획 트리 전체가 "한 번 부르면 한 행"을 돌려주는 끌어오기(Volcano) 방식이다. 이 PR 은 CUBRID 블록 하나 안의 "힙 스캔 → 필터 → 집계·투영·해시 GROUP BY" 구간만 페이지 청크를 밀어넣는 벡터 실행으로 바꿨다. 그래서 스캔·집계 위주 질의에서는 PG 보다 앞서지만, 조인과 블록 경계에서 끊긴다.
실행으로 확인한 한계 중 PR 본문에 없는 것은 네 가지다: 분할 테이블은 배치를 전혀 타지 않는다. 산술이 든 필터는 계산값을 읽는 곳이 없어도 거절된다. ALTER 한 테이블, 이동된 레코드가 있는 페이지, 동시 갱신이 걸린 페이지는 행 경로로 간다. 해시 병합은 칸이 64개로 묶여 있어 칸 하나가 예산보다 커진다(32KB 예산에서 칸 하나 약 0.79MB). Blocking 은 없다.
PR 본문의 "database-reference" 는 PostgreSQL 이 아니다. 주석의 식별자가 PG 소스에 하나도 없다.

## 1. Volcano 와 Datum — PG 에서 무엇이고, 여기서 무엇에 대응하나

### 1.1 Volcano: PG 의 반복자 실행 모델

- 이름은 Graefe 의 Volcano 질의 실행 시스템에서 왔다. 연산자마다 open, next, close 를 두는 반복자 모델이다. PG 소스에는 "Volcano" 라는 낱말이 없다(`rg -i volcano src doc` 0건). PG 는 이것을 "demand-pull pipeline" 이라 부른다(`src/backend/executor/README:6-10`).
- PG 에서의 모양:
  - 계획 트리(Plan)를 같은 모양의 실행 상태 트리(PlanState)로 만든다: `ExecInitNode`. 실행은 `ExecProcNode`, 정리는 `ExecEndNode` 이다(`src/backend/executor/execProcnode.c` 머리 주석 1-70).
  - `ExecProcNode(node)` 를 한 번 부르면 다음 행 하나(TupleTableSlot) 또는 NULL 이 나온다. 노드마다 함수 포인터 `node->ExecProcNode` 를 거친다(`src/include/executor/executor.h:321-328`).
  - 조인 노드는 자식의 `ExecProcNode` 를 불러 행을 끌어온다. 스캔 노드는 행 하나마다 가져오기, `ExecQual`(필터), `ExecProject`(출력 계산)를 한다(`src/include/executor/execScan.h:161, 224, 235`).
  - Sort, Hash, 해시 Agg, Material 은 입력을 다 받은 뒤 내보내는 막는 노드(blocking node)다. Hash 와 BitmapIndexScan 은 행이 아니라 해시 표나 비트맵을 통째로 넘긴다(`MultiExecProcNode`, execProcnode.c:488).
  - 병렬은 Volcano 의 exchange 연산자 자리에 Gather/Gather Merge 를 둔다.
- PG 는 벡터화 대신 행 하나의 비용을 줄이는 쪽으로 간다:
  - 가시성은 페이지 단위로 판정한다(`heap_prepare_pagescan`, heapam.c:619).
  - 컬럼은 필요한 것까지만 해체한다(`slot_getsomeattrs`, tuptable.h:376).
  - 식 해석기는 computed goto 로 단계를 넘긴다(execExprInterp.c:91, 470).
  - 비싼 질의는 LLVM JIT 로 식과 해체를 기계어로 만든다(`llvmjit_expr.c:79`, `llvmjit_deform.c:34`, GUC `jit_above_cost`).

### 1.2 CUBRID develop 에서 대응하는 것

CUBRID 는 트리 전체가 반복자가 아니다. 블록(XASL 노드) 안에서는 끌어오고, 블록 사이는 리스트 파일로 물질화한다(중간 결과를 임시 파일에 다 써 둔다).

| PG | CUBRID develop | 비고 |
|---|---|---|
| Plan / PlanState 트리 | XASL_NODE 트리 + XASL_STATE | 블록 = BUILDLIST_PROC, BUILDVALUE_PROC 등 |
| SeqScan 의 `ExecProcNode` | `scan_next_scan` (scan_manager.c:8784) | 한 번에 한 행. 값은 블록의 `val_list` 칸으로 읽는다 |
| NestLoop 이 안쪽 `ExecProcNode` 를 부름 | `scan_ptr` 사슬. 바깥은 `qexec_intprt_fnc`, 안쪽은 `qexec_execute_scan` (query_executor.c:20069-20089 의 func_vector) | |
| `ExecQual` | 스캔의 data filter (`eval_data_filter`), 컴파일된 필터 (`expr_compile.c`) | |
| `ExecProject` 후 위로 반환 | `qexec_end_one_iteration` (query_executor.c:1135): 블록의 리스트 파일에 튜플을 쓰거나 집계에 누산 | 위로 돌려주지 않고 물질화 |
| Material, SubqueryScan, 조인 입력 | 블록의 `aptr_list` 를 먼저 실행해 리스트 파일(QFILE_LIST_ID)로 물질화 (query_executor.c:19601-19720) | 블록 경계 = 물질화 |
| 그룹 없는 Agg | BUILDVALUE_PROC | |
| 해시 Agg / 정렬 Group | BUILDLIST + `agg_hash_context`. 넘치면 `qexec_groupby` 정렬 | |
| Hash + HashJoin | HASHJOIN_PROC. 두 입력 모두 aptr 리스트로 먼저 물질화 | |
| Gather (exchange) | px_scan 워커 + 결과 핸들러 | |
| MinimalTuple (물질화된 행) | QFILE 튜플 | |

### 1.3 이 PR 이 바꾼 자리

- 바뀐 곳은 `qexec_intprt_fnc` 의 행 루프("`scan_next_scan` 한 행 → `qexec_end_one_iteration`")의 앞이다. 블록이 조건을 만족하면 `qexec_batch_scan` (query_executor.c:12454)이 행 루프 대신 돈다. 이 함수는 페이지의 청크를 "평가 노드(필터와 피연산자) → 끝 노드(집계, 해시 GROUP BY, 투영)" 사슬에 밀어넣는다(`expr_chunk_push`, expr_batch.h 의 "Chunks between nodes").
- 즉 Volcano 의 끌어오기를 블록 하나의 맨 아래 파이프라인에서만 밀어넣기로 뒤집은 것이다. 블록 경계(리스트 파일)와 조인 위로는 여전히 행 하나씩이다. 조인 아래 스캔은 필터만 청크로 돌리고, 행은 한 줄씩 내준다(`scan_batch_iter_next`, scan_manager.c:8607).
- PG 코어에는 이에 해당하는 것이 없다. PG 의 페이지 모드는 가시성까지만 페이지 단위이고, 필터와 집계는 행마다 돈다.

### 1.4 Datum

- **PG 의 Datum**: `typedef uint64_t Datum;` (src/include/postgres.h:59-70. master 에서 8바이트로 고정됐다).
  - 값 타입(int4, int8, float8, date, bool 등)은 Datum 안에 값 자체가 들어 있다.
  - 참조 타입(text, numeric, bytea 등)은 포인터다. 압축이나 TOAST 가 아니면 핀이 잡힌 버퍼 페이지 안을 그대로 가리킨다.
  - Datum 에는 타입도 NULL 표시도 없다. 타입은 TupleDesc 나 식의 결과 타입이 말하고, NULL 은 따로 둔 bool 이 말한다(`tts_isnull`, `NullableDatum`).
  - 한 행의 컬럼들은 슬롯의 `tts_values[]`/`tts_isnull[]` 배열에 든다(tuptable.h:120-133). 컬럼은 앞에서부터 차례로 해체한다(`slot_deform_heap_tuple`, execTuples.c:1017). 고정 위치(`attcacheoff`)는 첫 NULL 이나 첫 가변 길이 컬럼 전까지만 쓸 수 있다(execTuples.c:1157).
- **CUBRID 의 DB_VALUE** (src/compat/dbtype_def.h:1166-1171): 도메인 정보(타입, 정밀도, 스케일, codeset, collation, NULL 표시) + 값 공용체 + `need_clear` 로 되어 있다. head optdebug 바이너리를 gdb 로 재면 `sizeof(DB_VALUE)=64`, 도메인 12바이트, 값 40바이트다.
  - DB_VALUE 는 PG 의 (Datum + isnull + 타입 OID + typmod + collation) 을 한 덩어리로 든, 스스로 설명하는 값이다.
  - 행 경로에서 `heap_attrinfo_read_dbvalues` (heap_file.c:11577)가 레코드를 DB_VALUE 로 해체한다. 이것이 PG 의 슬롯 해체에 해당하고, XASL 의 `val_list` 칸들이 `tts_values` 역할을 한다.
- **이 PR 의 벡터 원소**: 청크의 컬럼 배열이다(expr_batch.c 머리 주석).
  - 정수, DATE, double 은 날 값으로 둔다. NUMERIC(정밀도 18 이하)은 int64 계수와 스케일 바이트로 둔다. 원소마다 NULL 바이트가 붙는다.
  - 타입 꼬리표가 없는 열 방향 배열이라 PG 의 Datum 보다도 작다.
  - "pointed" 컬럼은 레코드 안 위치(`HEAP_RAW_LOCATOR`)만 들고 있다가 쓸 때 읽는다. PG 의 참조형 Datum 이 페이지 안을 가리키는 것과 같은 무복사 방식이다.

| 개념 | PG | CUBRID develop | 이 PR |
|---|---|---|---|
| 값 하나 | Datum 8B + isnull 1B, 타입은 밖에 | DB_VALUE 64B, 타입·NULL 포함 | 벡터 원소(int64, double, date, NUMERIC 계수+스케일) + NULL 바이트 |
| 한 행의 컬럼들 | 슬롯 `tts_values[]`/`tts_isnull[]` (행 방향) | `val_list` 의 DB_VALUE 들 | 청크의 컬럼 배열 (열 방향) |
| 페이지 안 레코드를 가리킴 | `HeapTupleData.t_data`, 참조형 Datum (핀 유지) | RECDES PEEK (래치 유지) | `EXPR_BATCH_ROW.recdes` PEEK, pointed 컬럼 |
| 페이지의 가시 행 목록 | `rs_vistuples[]` | 없음 (행마다 판정) | `rows[]` |
| 필터를 통과한 행 | 없음 (행마다 `ExecQual`) | 없음 | `sel[]` (선택 벡터) |
| 컬럼 찾기 | 앞에서부터 차례로 해체 | 고정 영역 + 가변 오프셋 표로 바로 감 | 같은 레코드 형식, 레이아웃은 청크마다 한 번 |

## 2. 축별 비교

| 축 | PostgreSQL | 이 PR | 뜻 |
|---|---|---|---|
| 실행 단위 | 한 행. 노드마다 함수 포인터 호출 | 블록 맨 아래만 청크(8KB ÷ 행당 바이트, `EXPR_BATCH_CHUNK_BYTES`), 그 위는 행 | 스캔·집계에 이득이 몰린다 |
| 가시성 | `heap_prepare_pagescan`: 공유 잠금으로 한 번에 판정. 페이지가 PD_ALL_VISIBLE 이면 행별 판정을 생략(heapam.c:672). master 는 일괄 판정 함수 `HeapTupleSatisfiesMVCCBatch` | `heap_page_collect_visible` (heap_file.c:8196): 레코드마다 MVCC 헤더를 읽는다. 페이지 단위 all-visible 표시는 없다(CUBRID 구조) | 판정 못 하는 레코드를 만나면 페이지 나머지를 행 경로로 보낸다(§3 N3). PG 에는 이 되돌림이 없다 |
| 페이지 보유 | 핀과 내용 잠금이 따로다. 판정이 끝나면 잠금을 풀고 핀만 쥔다(heapam.c:701). 레코드 삭제·조각 모음은 cleanup lock(배타 잠금 + 다른 핀 없음, bufmgr.c:6677-6689)이 있어야 한다 | 페이지 fix 가 곧 래치다. 배치는 읽기 래치를 쥔 채 청크를 평가·소비한다. 조인 아래에서는 살아남은 레코드를 복사하고 페이지를 놓는다(scan_manager.c:8707-8718) | 복사는 PR 이 새로 들인 비용이 아니다(§6). 놓았다 다시 잡을 때의 dealloc·vacuum 문제는 항목 2 |
| 식 평가 | 모든 식을 같은 단계 배열로 해석하고, 필요하면 JIT. 적용 범위에 구멍이 없다 | 컴파일러가 정한 리프·스텝을 배열 위 타입별 루프로 다시 구현한 허용 목록. 목록 밖이면 행마다 컴파일된 필터(ROW term)로 돌리거나 계획 전체를 거절 | 술어 모양이 조금만 바뀌어도 성능이 뚝 떨어진다(§3 N1-N3). 같은 의미를 두 경로가 구현하므로 결과 차이 위험이 있다. PR 의 CI 대응 수정 8건이 그 예다(PR 본문 Remarks) |
| NUMERIC | 가변 길이 10000진 자릿수. 비교는 `cmp_numerics` (numeric.c:2529), SUM 은 자리올림을 미루는 `NumericSumAccum` (381). int8 SUM/AVG 만 int128 (5448) | 정밀도 18 이하는 int64 계수로 비교·누산 | 같은 일에 PG 보다 싸다. develop 행 경로에서 NUMERIC 비교가 비싼 것이 이 PR 이득의 큰 몫이다(§5 perf) |
| 해시 집계가 넘칠 때 | 이미 있는 그룹만 계속 갱신하고, 새 그룹이 될 행은 해시 비트로 나눈 파티션(4-1024개)에 쏟는다. 파티션마다 HLL 로 크기를 추정하고, 또 넘치면 재귀로 다시 나눈다(nodeAgg.c:197-227, 298-317, 2084, 3074, 3217). 메모리가 hash_mem 안에 머문다 | develop: LRU 로 그룹을 내쫓고, 선택도가 나쁘면 해시를 포기하고 정렬한다. PR: 남은 리스트를 키 해시로 칸 나눠 칸마다 표로 접는다(`qexec_gby_hash_merge`, query_executor.c:7118) | 생각은 PG 의 spill 과 같다. 다만 칸은 최대 64개이고 재귀가 없다(§3 N4) |
| 메모리 관리 | 해시 행은 Bump 문맥에 두고(nodeAgg.c:2043), 파티션마다 문맥을 통째로 리셋한다. 그룹을 하나씩 내쫓지 않아 해제 목록이 없다 | 그룹 slab 은 LRU 로 내쫓긴 그룹을 해제 목록에 돌려 재사용한다. 병합 표는 1MB 블록 아레나를 칸마다 되감는다 | 문맥 통째 리셋은 PG 와 같은 방식. 해제 목록은 CUBRID 가 그룹을 하나씩 내쫓기 때문에 필요하다 |
| 해시 조인 필터 | 런타임/블룸 필터가 없다(`rg -i "bloom\|runtime filter" src/backend/executor` 0건). 비슷한 것은 안쪽이 비면 바깥 스캔을 생략하는 것뿐이다(nodeHashjoin.c:360). CUBRID develop 에도 있다(query_executor.c:19644-19680 의 표) | INNER·SEMI, 키 1개, 정수·DATE, 먼저 돈 입력 2^20 행 이하, 대상은 분할 테이블이 아닌 단일 클래스(query_hash_join.c:4685, 4734, 4752, 4826). 정확 집합이고 블룸이 아니다. 떨어뜨리는 비율이 낮아도 끄지 않는다(`hjoin_rtf_pass` 4981-5006 은 세기만 함) | PG 보다 한 걸음 더 갔다 |
| 관찰 | EXPLAIN ANALYZE 가 노드마다 보여 준다 | `;plan detail` 일 때만 스캔 줄에 `batch pages`/`batch: no (사유)` 가 나온다 | 분할 테이블은 사유조차 안 나온다(§3 N1) |
| 끄는 스위치 | 실행 전략마다 GUC 가 있다(`enable_hashagg`, `enable_memoize`, `enable_parallel_hash`, `jit` 등, guc_parameters.dat:865-1042, 1452) | 새 전략 세 가지에 스위치가 없다 | §3 N5 |

## 3. 발견 사항 (PR 이 새로 들인 것만)

### Blocking

없음.

### Non-blocking

**N1. 분할(파티션) 테이블은 직렬·병렬 모두 배치를 타지 않고, trace 에 이유도 나오지 않는다**

- 근거:
  - `qexec_batch_eligible` 와 `qexec_batch_filter_eligible` 은 `spec->parts != NULL` 이면 거절한다(query_executor.c:11622, 11649).
  - px 워커도 같은 함수로 거른다(px_scan_task.cpp:473, 498).
  - 런타임 필터 대상도 분할 테이블은 뺀다(query_hash_join.c:4752).
  - 어느 쪽도 `batch_why_not` 을 남기지 않아 `;plan detail` 에 아무 줄이 없다.
- 실행: 같은 40만 행을 일반 테이블 `t1` 과 해시 4분할 테이블 `pt` 에 넣고 `select sum(n) ... where n < 10` 을 돌렸다.
  - t1: `batch pages: 1858 (row path: 0)`, heap time 47ms.
  - pt: batch 표시 없음, heap time 386ms.
- PG 는 분할 테이블도 Append 아래 파티션마다 보통 SeqScan 으로 읽으므로 같은 경로를 탄다.
- PR 본문의 "지금 배치가 거절하는 모양" 목록에도 이 경우는 없다. 큰 테이블일수록 분할하는 경우가 많아 적용 범위에 미치는 영향이 크다.
- 제안: 파티션 블록마다 배치를 여는 것이 이 PR 범위 밖이라면, 최소한 거절 사유를 trace 에 남기고 본문의 거절 목록에 적는다.

**N2. 산술이 든 필터는 계산값을 읽는 곳이 없어도 모두 거절된다**

- 근거:
  - `eb_build_filter` 는 `expr_scan_pred_has_share()` 가 참이면 거절한다(expr_batch.c:1509-1512). 이 함수는 컴파일된 필터의 `n_share > 0` 이다(expr_compile.c:3501-3504).
  - 그런데 `n_share` 는 필터가 공유용으로 *내놓은* 산술 노드의 수다. 공유할 수 있는 노드는 읽는 쪽이 있든 없든 등록된다(expr_compile.c:3185-3217).
  - 실제로 연결된 소비자 수는 소비자 프로그램 쪽의 `n_shared` 다(expr_compile.c:5105, 6081). 소비자는 `expr_share_attach` 에서 필터의 `n_share` 를 보고 연결한다(expr_compile.c:1654).
- 실행: 아래 셋 모두 `batch: no (the filter shares computed values with other programs)` 였다.
  - `count(*) from t1 where n + 1 < 10` (계산값을 읽는 곳이 없음): heap 339ms.
  - `sum(a) from t1 where a + 1 < 10`: heap 218ms.
  - `sum(a) from t1 where n + 1 < 10`: heap 408ms.
  - 비교: 같은 테이블의 `n < 10` 배치는 47ms 였다.
- PR 본문은 이 거절을 "필터가 계산한 값을 출력·키가 함께 읽는 경우"로 설명한다. 실제 조건은 그보다 넓어서, 컬럼에 산술을 한 비교가 모두 빠진다(`a + 1 < 10`, `price * (1 - discount) > x` 같은 모양).
- PG 는 식 모양과 상관없이 같은 해석기와 JIT 를 쓴다.
- 제안: 거절 조건을 "소비자 프로그램이 실제로 연결됨"으로 좁힐 수 있는지 검토한다. 다만 계획을 만드는 시점에 모든 소비자의 연결이 끝나 있는지는 확인하지 않았다.

**N3. ALTER 한 테이블, 이동된(relocated) 레코드가 있는 페이지, 동시 갱신이 걸린 페이지는 행 경로로 간다 (PG 에는 없는 성능 절벽)**

- 근거:
  - 레코드의 표현(representation)이 계획의 표현과 다르면, 그 청크와 페이지 나머지를 행 경로로 보낸다(`eb_layout_rows`, expr_batch.c:3144-3158).
  - REC_HOME 이 아닌 레코드(이동, overflow)를 만나도 `heap_page_collect_visible` 이 S_DOESNT_FIT 을 돌려준다(heap_file.c:8263).
  - 스냅샷보다 새 레코드(보이는 버전이 로그에 있음)도 마찬가지다(heap_file.c:8282).
- 실행 (40만 행, 1858쪽):
  - `ALTER TABLE t3 ADD COLUMN z int` 후: `batch pages: 1 (row path: 1857, last: a record of another representation)`, heap 511-587ms. 같은 데이터인 t1 의 배치는 64ms.
  - 1/3 행의 VARCHAR 를 늘려 이동시키고 커밋한 뒤: `batch pages: 133 (row path: 1855, ...)`. 서버를 재시작한 뒤에도 같았다.
  - 다른 세션이 1% 행(4000행, 페이지마다 약 2행)을 갱신하고 커밋하기 전: `batch pages: 2 (row path: 1856, ...)`, heap 536ms.
- 뜻:
  - ALTER 는 기존 레코드를 다시 쓰지 않는다. 그래서 그 테이블은 행이 갱신될 때까지 사실상 계속 배치 밖에 있다. 이동된 레코드도 그대로 남는다.
  - 동시 갱신은 1% 만으로 거의 모든 페이지를 빼낸다. OLTP 갱신과 분석이 한 테이블에 섞이면 이득이 사라진다.
- PG 에는 페이지를 되돌려 보내는 경로 자체가 없다. 모든 버전이 힙 튜플이라 페이지 모드는 갱신과 상관없이 돈다(heapam.c:525-600). ADD COLUMN 은 슬롯 해체가 빠진 컬럼을 기본값으로 채운다(`slot_getmissingattrs`, execTuples.c:2151).
- PR 본문은 "로그 버전·이동·overflow 레코드는 그 청크부터 페이지 끝까지 행 경로"라고 적었다. 그러나 ALTER 경우와, 갱신 비율이 작아도 거의 전 페이지가 빠진다는 점은 없다.
- 제안: 범위를 넓히는 일은 이 PR 밖이어도 된다. 대신 본문에 ALTER 와 동시 갱신의 영향을 적는다. PG 와의 차이를 줄이는 방향은 두 가지다: 옛 표현 레코드만 따로 해체하는 것, 그리고 판정 못 하는 레코드 하나만 행 경로로 보내는 것.

**N4. 해시 GROUP BY 잔여분 병합: 칸은 최대 64개이고 재귀가 없어서 칸 하나가 예산보다 커진다**

- 근거:
  - `n_parts = MIN(bytes / budget, 64)` 이다(query_executor.c:7179-7184, 상한은 5584).
  - 주석에도 "the partitions are few, and may outgrow the budget rather than multiply" 라고 적혀 있다(5582-5583). 그러나 넘는 정도에 상한은 없다.
  - 칸 표의 아레나(5680)와 해시 칸 배열(5811)은 상한 없이 자란다. 넘친 칸을 다시 나누지 않는다.
- 실행 (`max_agg_hash_size=32K`, 직렬, 40만 행, 그룹 98,164개):
  - trace: `hash merge partitions: 64, groups (est.): 99364`.
  - SA 모드에서 gdb 로 칸마다 표 크기를 읽었다(`qexec_gby_mtable_rewind` 에 중단점).
  - 칸당 그룹은 1,484-1,622개였다. 아레나 사용량은 최대 739,632B, 해시 칸 배열은 4,096 × 16B 였다. 합쳐 칸 하나가 약 0.79MB 로, 예산 32KB 의 약 24배다. 그룹 하나에 약 456B 가 든다.
- 규모 환산 (그룹당 456B, 기본 예산 2MB, 직렬):
  - 칸 64개가 예산을 다 채우는 지점은 약 28만 그룹이다.
  - 그보다 많으면 칸 하나가 전체의 1/64 가 된다. 2천만 그룹이면 칸 하나가 약 142MB 로 예산의 71배다.
  - 병렬 병합이면 워커 수만큼의 칸이 동시에 메모리에 있다.
  - develop 은 같은 입력을 외부 정렬로 처리했다. 그 메모리는 `sort_buffer_size` 로 묶인다.
- PG 는 넘친 파티션을 재귀로 다시 나눠 hash_mem 안에 둔다. nodeAgg.c:197-227 의 표현으로 "if a batch does exceed hash_mem, it must be spilled recursively" 다.
- 제안(가장 작은 수정): 예상 칸 크기 `bytes / n_parts` 가 예산의 몇 배를 넘으면 병합하지 않고 기존 정렬에 맡긴다. 한 줄 조건이면 된다. 재귀로 다시 나누는 것은 그다음 일이다.

**N5. 새 실행 전략 세 가지(페이지 배치, 해시 병합, 런타임 필터)를 끌 방법이 없다**

- 근거: diff 가 읽는 시스템 파라미터는 기존 것 4개뿐이다(`agg_hash_respect_order`, `ignore_trailing_space`, `max_agg_hash_size`, `max_recursion_sql_depth`). 새 파라미터도 새 힌트도 없다. `src/base`, `src/parser` 는 바뀌지 않았다.
- PG 는 실행 전략마다 끄는 GUC 를 둔다(`enable_hashagg`, `enable_memoize`, `enable_parallel_hash`, `jit` 등).
- 현장에서 결과나 성능 문제가 의심될 때, 배치만 끄고 비교할 수단이 없다. 이 PR 의 CI 대응에서 develop 과 결과가 다른 경우가 8건 나왔다. 그것을 보면 행 경로를 강제하는 스위치는 진단 도구로도 쓸모가 있다.
- 제안: 서버 파라미터 하나로 `scan_batch_open*`, `qexec_gby_hash_merge`, `hjoin_rtf_first_input` 의 입구를 막는다.

### Questions

**Q1. "database-reference" 는 어떤 엔진의 어느 버전인가?**

- PR 주석에 나오는 식별자를 `~/dev/postgres` 전체에서 찾았다(`rg -w`). 결과는 0건이다.
  - 식별자: `PpNodeUseColumnInfo`, `ColumnBuilder::Build`, `InvalidateRowsByFilter`, `RowPos`, `ExAggr`, `NumberAccum`, `exaggr_apply`, 그리고 "NUMBER sum".
  - 위치: expr_batch.h:43, 133, 182, expr_batch.c:43, query_aggregate.hpp:189, query_executor.c:5578, 11692, query_hash_join.c:4673.
- NUMBER 는 Oracle 호환 엔진에서 쓰는 타입 이름이다. 즉 "database-reference" 는 PostgreSQL 이 아니다. 이 호스트에는 그 소스도 바이너리도 없다.
- 같은 꼬리표는 develop 에도 이미 하나 있다(expr_compile.c:2315, 이전 PR). 그러니 이 PR 에서 시작된 관행은 아니다.
- 리뷰어가 근거를 따라가 볼 수 없다. 그래서 주석에 엔진 이름과 버전을 쓸지, 주석에서 빼고 PR 본문에만 둘지 물어볼 만하다.
- 그 엔진이 공개 소스가 아니라면, 그 엔진의 내부 식별자를 CUBRID 공개 코드 주석에 남겨도 되는지도 확인이 필요하다. 이것은 판단을 묻는 질문이고, 문제가 있다는 주장은 아니다.

**Q2. TPC-H "reference 대비" 수치는 무엇과 비교한 것인가?**

- PR 본문의 수치: "같은 호스트의 database-reference 대비", 병렬 합 PR 91.1초 / ref 142.6초, 직렬 합 325.6초 / 319.0초. 엔진, 버전, 설정(병렬도 6 말고는)이 없어 다시 재 볼 수 없다.
- 이 호스트(ilhansong_data3)에 PostgreSQL 18.6 TPC-H SF10 이 있기는 하다(`~/databases/pg-tpch`, 포트 55432). 하지만 2026-10-12 trace 오버헤드 측정용으로 만든 것이고 이 PR 과는 관계가 없다.
- 그 측정값은 호스트가 포화된 상태에서 병렬 워커 4개로 잰 것이다. q17 15.8초, q20 24.6초, q18 89.9초다(`scratch/pg-tpch/summary.md`). 본문은 Q20 을 "reference 가 앞서는 곳"으로 들었는데, PR 의 Q20 은 1.88초라 이 PG 와 맞지 않는다. 따라서 본문의 reference 는 이 PG 가 아니다.
- 이 수치는 머지 판단의 근거로 쓰지 않는 것이 맞다. 남긴다면 엔진, 버전, 설정을 적어 달라고 요청할 만하다.

**Q3. 청크를 조인 위나 블록 경계 너머로 넘길 계획이 있는가? (결함이 아니라 범위 확인)**

- TPC-H 표에서 이득은 스캔·집계·런타임 필터 질의에 몰려 있다. Q1 0.27, Q6 0.45/0.41, Q12 0.52/0.46, Q15 0.53/0.55, Q18 0.61/0.49 다.
- 조인 위주 질의의 직렬 값은 0.94-1.06 이다(Q3 1.03, Q7 1.06, Q9 1.06).
- §1.3 의 구조에서 예상되는 모양이다. 다음 단계가 있는지만 묻는 것이다.

## 4. 이 PR 이 PG 보다 앞선 점

- 스캔 → 필터 → 집계 구간의 벡터 실행. PG 코어에는 없다.
- NUMERIC 을 int64 계수로 비교하고 누산한다. PG 의 numeric 은 가변 길이 자릿수 연산이다.
- 레코드 형식(고정 영역 + 가변 오프셋 표) 덕에, 쓰는 컬럼만 바로 가리킨다. PG 는 앞 컬럼부터 차례로 해체한다.
- 해시 조인 런타임 필터. PG 에는 없다.
- (이 PR 범위 밖이지만 TPC-H 비교에 영향이 있다) 상관 부질의 결과 캐시. PG 는 상관 스칼라 부질의를 행마다 다시 실행한다. 이 호스트의 PG 측정 노트(`scratch/pg-tpch/notes.md`)를 보면 s06 이 PG 227초, CUBRID 0.125초다.

## 5. 실행한 검증

- **빌드**: CI tarball head `908bdc5af` optdebug(`.../builds/pr/908bdc5af.../debug/CUBRID.tar.gz`). 버전 문자열은 `CUBRID 11.5.0 (11.5.0.2736) optdebug`, `lib/libcubrid.so` sha256 은 `1dcabf9fe7abbfc8...` 로 시작한다. 자기 scratch 에 풀어 썼다. release 빌드와 merge-base 빌드는 쓰지 않았다.
- **서버**:
  - 포트 1715 를 `just port-claim i6db` 로 잡고, `cubrid-server-control` 로 기동·정지했다.
  - conf 는 캠페인 conf(`data_buffer_size=512M`)를 썼다. N4 를 잴 때만 `max_agg_hash_size=32K` 를 더했다.
  - 끝난 뒤 서버를 멈추고 `cubrid service stop`(master 정지)과 `just port-release i6db` 를 했다. 스모크 DB 와 설치본은 지웠다.
- **데이터**:
  - `t1(id int, a int, n numeric(15,2), d date, v varchar(40), c char(10))` 40만 행(1858쪽).
  - `pt`: 같은 행을 해시 4분할로.
  - `t2`: t1 복사본(이동 레코드 시험). `t3`: t1 복사본(ALTER 시험).
  - `h(k, x)`: 40만 행, 무작위 키 10만 개.
- **질의**: 모두 `/*+ parallel(0) */` 로 직렬 실행했다. `;plan detail` + `SET TRACE ON` + `SHOW TRACE` 로 trace 를 읽었다. 스크립트는 `.git_ignored_dir/scratch/pr8196-item6/sh/*.sql`, 출력은 `out/*.out` 에 있다.
- **결과**: heap time 은 trace 의 ms 값이고 한 번 실행한 값이다. 호스트에 다른 세션 부하가 있으므로 크기의 차이만 본다.

| 경우 | 질의 (`select sum(n) from ...` 꼴) | trace | heap ms |
|---|---|---|---|
| 기준 | t1 `n < 10` | batch pages 1858 (row path 0) | 47 |
| VARCHAR LIKE | t1 `v like '%5%'` | batch pages 1858 | 53 |
| LIKE 에 `_` | t1 `v like '%5_%'` | batch: no (the data filter is interpreted) | 205 |
| 함수 | t1 `upper(v) = 'VAL5'` | batch: no (the data filter is interpreted) | 530 |
| 산술 | t1 `n + 1 < 10` | batch: no (the filter shares computed values ...) | 218 |
| 산술, 읽는 곳 없음 | `count(*)` ... t1 `n + 1 < 10` | 같음 | 339 |
| NUMERIC MIN | `min(n)` ... t1 `a < 500` | batch: no (a MIN/MAX operand type ...) | 183 |
| DISTINCT | `count(distinct a)` ... t1 | batch: no (an aggregate the batch does not take ...) | 173 |
| 분할 테이블 | pt `n < 10` | (표시 없음) | 386 |
| 동시 갱신 1% (커밋 전) | t1 `n < 10` | batch pages 2 (row path 1856, last: ... a log version) | 536 |
| 이동 레코드 | t2 `n < 10` | batch pages 133 (row path 1855) | 528 |
| ALTER ADD COLUMN | t3 `n < 10` | batch pages 1 (row path 1857, last: a record of another representation) | 511-587 |
| 해시 병합 (예산 32KB) | h `group by k` | hash merge partitions: 64, groups (est.): 99364 | GROUPBY 1011 |

- **gdb**: 서버를 멈추고 SA 모드 `csql -S` 를 `timeout 180 gdb -batch` 아래에서 돌렸다. rewind 가 65번 걸렸다(64칸 + 마지막 1번). 칸당 그룹은 최대 1,622개, 아레나는 최대 739,632B 였다.
- **perf**: `perf record -e cpu-clock:u -p <cub_server>` 로 t3 ALTER 질의를 6번 돌리며 찍었다.
  - 행 경로로 되돌아간 페이지에서 배치를 시도한 몫(`scan_batch_collect_chunk`)은 샘플의 3.9% 다.
  - 대부분은 develop 과 같은 행 경로다(`scan_next_heap_scan_rows` 84%). 그 안에서는 NUMERIC 비교(`numeric_db_value_compare` 단독 10.5%)가 크다.
- **정적 확인**: PG 소스에서 `rg` 로 volcano, bloom/runtime filter, reference 식별자를 찾았다. 모두 0건이다.
- **빌드·CTP**: 돌리지 않았다. 코드를 바꾸지 않는 리뷰 항목이고, 결과값 정합은 항목 1(CI) 범위다.

## 6. 오판으로 확인되어 뺀 것

- **"행 경로로 되돌린 페이지가 develop 행 경로보다 훨씬 비싸다"**: t3 가 511ms, 행 경로 LIKE 질의가 200ms 인 것을 보고 의심했다. perf 로 보니 배치 시도 몫은 3.9% 이고, 나머지는 develop 과 같은 행 경로였다. NUMERIC 비교가 LIKE 보다 비쌀 뿐이다. 또 같은 t3 에서 처음부터 배치를 거절하는 `v like '%5_%'` 는 200ms 로 t1(206ms)과 같았다. 그러니 옛 표현을 해체하는 비용도 아니다.
- **"조인 아래 필터 반복자의 레코드 복사가 PG 대비 새 비용"**: develop 행 경로도 이 경우 레코드마다 복사하거나(HEAP_SCAN_READ_COPY), 페이지 사본을 읽는다(HEAP_SCAN_READ_LOCAL_CACHE, merge-base heap_file.h:131-138). PR 은 살아남은 행만 복사하므로 develop 보다 적게 복사한다. PG 와의 차이는 핀이 없는 CUBRID 버퍼 관리 구조에서 온다.
- **"Chao1 표본이 그룹 수를 낮게 잡아 칸이 너무 적어진다"**: 해시를 포기하는 시점에 표가 쏟아낸 첫 튜플들은 표본 앞쪽에 한 번씩만 나온다. 이것이 추정을 키우는 쪽으로 작용해서, 낮게 잡히는 구체적인 입력을 만들지 못했다(실행 확인은 하지 않았다).

## 7. 확인하지 못한 것

- develop(merge-base) 빌드와의 시간 A/B 는 하지 않았다. heap time 비교는 같은 빌드 안에서 배치와 행 경로의 차이만 본 것이다.
- 병렬(px) 경로에서 N1 과 N3 을 재현하지 않았다. 같은 `qexec_batch_eligible`, `heap_page_collect_visible` 을 쓴다는 것을 코드로만 확인했다.
- N4 의 큰 규모(수천만 그룹)에서 실제 메모리를 재지 않았다. 32KB 예산 스모크에서 얻은 그룹당 바이트로 환산만 했다.
- 런타임 필터의 비용을 재지 않았다. 떨어뜨리는 비율이 낮을 때의 비용과, 병렬 워커가 행마다 공유 카운터 두 개에 원자 덧셈을 하는 비용(query_hash_join.c:4987, 5004)이 그것이다. 뒤쪽은 항목 3(cpp-perf-rules) 범위와 겹친다.
- PostgreSQL 은 실행하지 않았다. 비교는 소스 기준이다. `~/databases/pg-tpch` 서버는 띄우지 않았다.
- "database-reference" 엔진의 정체와, 그 엔진으로 잰 TPC-H 수치는 확인하지 못했다.

## 8. PR 코멘트 초안 (2026-10-21 사용자 승인으로 게시함: COMMENT 리뷰 https://github.com/CUBRID/cubrid/pull/8196#pullrequestreview-5598417203 , 게시한 문구는 `item6-comments.md`)

1. (N1) 분할 테이블은 `qexec_batch_eligible`/`qexec_batch_filter_eligible` 의 `spec->parts != NULL` 조건(query_executor.c:11622, 11649) 때문에 직렬·병렬 모두 배치 밖입니다. trace 에도 사유가 남지 않습니다. 40만 행 해시 4분할 테이블에서 `sum(n) where n < 10` 은 heap 386ms 였고, 같은 데이터의 일반 테이블은 배치로 47ms 였습니다. 범위 밖이라면 거절 사유를 trace 와 본문의 거절 목록에 남겨 주시면 좋겠습니다.
2. (N2) `expr_scan_pred_has_share()` 는 필터가 공유용으로 내놓은 노드 수(`n_share`)를 보므로, 읽는 쪽이 없어도 산술이 든 필터는 모두 거절됩니다. 예를 들어 `select count(*) from t where n + 1 < 10` 이 `batch: no (the filter shares computed values with other programs)` 입니다. 실제로 연결된 소비자(`n_shared`)가 있을 때만 거절하도록 좁힐 수 있을까요?
3. (N3) `ALTER TABLE ... ADD COLUMN` 뒤에는 기존 레코드가 옛 표현이라 거의 모든 페이지가 행 경로로 갑니다(`row path: 1857/1858, last: a record of another representation`). 다른 세션이 1% 행만 갱신 중이어도 1856/1858 쪽이 행 경로였습니다. 본문의 적용 범위 설명에 이 두 경우를 넣어 주시면 좋겠습니다.
4. (N4) `qexec_gby_hash_merge` 는 칸을 최대 64개로 묶고 다시 나누지 않습니다. 그래서 칸 하나가 `max_agg_hash_size` 의 몇십 배까지 자랍니다(32KB 예산, 그룹 98K 에서 칸 하나 약 0.79MB, 약 24배). 그룹 수에 비례해 끝없이 커지므로, `bytes / n_parts` 가 예산의 일정 배수를 넘으면 기존 정렬에 맡기는 조건을 제안드립니다.
5. (N5) 페이지 배치, 해시 병합, 런타임 필터를 끄는 파라미터가 없습니다. 현장에서 결과나 성능을 진단할 때 행 경로와 비교할 수 있도록 스위치 하나를 두는 것을 제안드립니다.
6. (Q1, Q2) 주석과 본문의 "database-reference" 는 어떤 엔진의 어느 버전인가요? TPC-H "reference 대비" 수치를 잰 설정도 함께 알려 주시면 좋겠습니다.
