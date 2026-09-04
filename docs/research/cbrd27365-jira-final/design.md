# CBRD-27365 Design

## 배경

임시 리스트 파일(qfile) 튜플은 `[tuple len 4B][prev len 4B]` 헤더 뒤에 값마다 `[flag 4B][len 4B]` 헤더를 붙이고 값을 8B(`MAX_ALIGNMENT`)로 정렬해 저장했다. 이 포맷은 자기 기술적이라 `type_list` 없이 걸을 수 있었지만 `(INT, BIGINT)` 한 행이 40B, TPC-H Q1 집계 행이 136B다. 스키마(`type_list`)는 리스트별 상수이므로 PostgreSQL MinimalTuple 처럼 컬럼 위치를 스키마에서 캐시하고 튜플에는 길이·널 정보만 두는 구조를 적용할 수 있다.

JIRA 원안은 all-fixed 리스트 한정 + hidden 파라미터였으나, 두 포맷 분기가 모든 접근자에 남는 비용과 테스트 매트릭스 2배를 피하기 위해 고정/가변 혼합 전체 + 파라미터 없음으로 확대했다. 설계 잠금 문서는 ADR 0016(`docs/adr/0016-qfile-tuple-format-pg-style.md`, 개발 저장소 xmilex-git/workspace) 이며 아래는 그 요약과 구현 중 정정이다.

## 설계 요약

- 튜플 포맷 = `[len 4B, bit31=has-null] [prev_len 4B, 역방향 가능 리스트만] [널비트맵 ceil(n/8)B, has-null 시만] [값들: 고정폭은 alignby min(자연 정렬, 4), 가변은 비정렬 + 1B/4B 길이 헤더]`. 단일 포맷, 구 포맷 삭제, 파라미터 없음.
- `type_list` 를 레이아웃 디스크립터로 확장하고 `domp[]` 를 바꾸는 코드가 같은 자리에서 finalize 한다(mutator-owns-finalize). 늦게 확정되는 컬럼은 조립기가 첫 bound 값에서 확정한다.
- 접근자 API(튜플 슬롯 + 위치/값 접근자 + 조립기 + in-place 덮어쓰기 + 도메인 구동 walk)를 신설 `src/query/qfile_tuple_layout.h/.c` 한 곳에 두고 서버·SA·클라이언트(`cursor.c`)가 같은 코드를 쓴다.

## 상세 설계

### 튜플 바이트 포맷

| 영역 | 규칙 |
|---|---|
| `len` | 4B 네트워크 오더. bit31 = has-null, 하위 31비트 = 패딩 포함 튜플 길이(4의 배수). `QFILE_GET_TUPLE_LENGTH` 는 bit31 을 마스킹 |
| `prev_len` | `hdr_size == 8`(`QFILE_FLAG_BACKWARD`) 리스트만. 같은 페이지 내 한 칸 후진(`qfile_scan_prev`, `cursor_prev_tuple`)에만 사용, 페이지 경계는 페이지 헤더 LAST_TUPLE_OFFSET |
| 널비트맵 | has-null 시만 헤더 직후 `ceil(type_cnt/8)`B, 비트 1 = bound. NULL 값은 0바이트 |
| 값 시작 | `data_off[has_null] = ALIGN4(hdr_size + bitmap_size)` (has_null 별 2값) |
| 고정폭(FIXED) | `alignby = min(자연 정렬, 4)`: SHORT/ENUM 2, 나머지 4. BIGINT/DOUBLE 도 4 이며 8B 읽기는 memcpy(`OR_GET_DOUBLE/FLOAT` 도 memcpy 로 변경) |
| 가변(VAR) | `pr_type::has_computed_disk_size()` 타입 전부: 문자열·BIT·NUMERIC·SET·JSON·ELO·OBJECT. 길이 헤더 1B(≤127B, bit7=0) / 4B(bit7=1, `ntohl & 0x7FFFFFFF`); 정렬은 아래 두 부류가 다름 |
| VAR/DIRECT | 문자열·BIT·NUMERIC: 정렬 없음(`alignby` 1), 본문은 `index_writeval` 인코딩, 접근자가 `index_readval` 로 직접 디코드, 비교자는 `index_cmpdisk` |
| VAR/SCRATCH | SET/JSON/ELO/OBJECT(`index_readval` 없음 또는 index 인코딩이 data 인코딩과 다름, D-199-1): `alignby` 4 — ALIGN4 뒤 항상 4B 길이 헤더, 본문(`data_writeval` 이미지)이 튜플 안에서 4B 정렬. 리더·라이터·비교자·`cursor.c` 모두 제자리 (역)직렬화, `data_readval(copy=true)` (D-201-1; 일시 정렬 복사 D-199-2 는 리뷰 A/B +12% 측정으로 폐기) |
| 패딩 | 내용 미정의(디버그 빌드만 0). 피크 트릭 없음 |

가변 값 기록은 절대 주소 기준 4B 패딩을 하는 `data_writeval` 을 비정렬 위치에 부르지 않고 `index_writeval`/직접 복사로 하며 "기록 크기 == 계산 크기" 를 assert 한다.

크기: `(INT, BIGINT)` 40→16B(forward 리스트), `(INT, INT)` 40→12B, TPC-H Q1 집계 행 136→60B, `(CHAR(10), VARCHAR(50), NUMERIC(15,2), INT)` 80→48B.

### 역방향 가능 리스트 (`QFILE_FLAG_BACKWARD`)

`qfile_open_list` flag 로 선언하고 `type_list.hdr_size`(4|8) 가 유일한 진실이다. 대상: (A) `XASL_TOP_MOST_XASL` 소유 최종 결과 리스트(CAS scrollable fetch, `qexec_setup_list_id` 의 DML 결과 포함), (B) MERGELIST_PROC outer/inner 자식, (C) 분석함수 group/value 리스트 4지점. 그 외 `qfile_open_list` 호출은 forward-only. 정렬 입력의 `qfile_scan_prev` un-read(list_file.c) 는 save/jump 로 바꿔 forward 유지.

forward 자식 리스트의 raw 튜플을 backward 결과 리스트에 붙이는 경로(UNION/CTE `qfile_copy_tuple`, `qfile_combine_two_list`, 정렬 P 경로 put)는 `qfile_add_tuple_to_list_from(list, tpl, src_hdr_size)` 가 길이 워드만 다시 쓰고 `src+src_hdr` 이후를 그대로 복사한다(`data_off` 차이는 항상 4, D-199-3). 해시조인 파티션·`qfile_duplicate_list` 는 소스 헤더를 상속. `or_unpack_unbound_listid` 는 hdr_size 가 4/8 이 아니면 에러(D-199-10).

### 레이아웃 디스크립터 (`QFILE_TUPLE_VALUE_TYPE_LIST` 확장, `query_list.h`)

```
int type_cnt; uint8 hdr_size; bool finalized; int16 bitmap_size; int16 data_off[2];
int first_non_cached_col; TP_DOMAIN **domp; QFILE_COL_LAYOUT *col;   /* domp 와 한 블록 (qfile_type_list_alloc) */
QFILE_COL_LAYOUT = { int16 off; int16 size; uint8 kind; uint8 var_access; uint8 alignby; uint8 type_id; }  /* 8B */
```

- `col[]` 은 `domp[]` 와 한 블록으로 할당해 기존 `free(domp)` 8곳 무수정. `type_id` 는 PR-3 에서 `domp[i]->type->id` 의존 로드 체인 제거용으로 캐시(D-200-10).
- `qfile_type_list_finalize(tl)`: 순수·멱등. `first_non_cached_col = min(첫 VAR 컬럼, off > 32767 인 첫 컬럼)`. 미확정 `DB_TYPE_VARIABLE` 컬럼은 VAR 로 계산. 호출 지점은 `domp` 를 바꾸는 모든 곳: `qfile_open_list`, `qfile_update_domains_on_type_list`, `qfile_unify_types`, DISTINCT 집계/분석함수 리스트 도메인 확정 4곳, 해시 GROUP BY 부분 리스트 2곳, RETURN_GENERATED_KEYS, px `update_domains_on_type_list_by_val_list`, 클라이언트 `or_unpack_unbound_listid`(D-196-7). 복제는 memcpy 상속. `qfile_open_list_scan` 의 디버그 교차검증(저장 레이아웃 == 재계산)이 누락을 잡는다.
- **늦은 도메인 확정(D-199-13)**: regu 도메인이 VARIABLE 인 동안에도 bound 값이 기록되므로 "확정 전 값은 NULL" 전제는 거짓이었다. 조립기 size 패스가 VARIABLE 컬럼에 bound 값이 오면 `tp_domain_resolve_value(val)` 로 `domp[col]` 을 바꾸고 재finalize 한다. 따라서 레이아웃은 구성상 첫 bound 값 전에 확정된다. `qfile_unify_types` 의 `assert_release(tuple_cnt == 0)` 는 이 불변식(VARIABLE 동안 기록된 값은 전부 NULL 0바이트)으로 제거(D-192-1). 재귀 CTE 공용 리스트 최적화는 `qfile_type_list_is_resolved()` 일 때만 켜고 아니면 기존 반복별 복사 경로(D-192-2).
- wire: `or_pack_listid` 에 int 1개(`hdr_size`) 추가, `or_listid_length` 8→9 int. 디스크립터 본체는 양쪽 재계산.
- 스레드 계약: 디스크립터는 `QFILE_LIST_ID` 소유 스레드만 접근. px XASL_SNAPSHOT 리더와 해시 GROUP BY 스필 로더는 `qfile_tuple_walk_init(walk, tpl, hdr_size, type_cnt)` + `qfile_tuple_walk_read_value` 의 도메인 구동 순차 deform 을 쓴다(open 시 고정되는 `hdr_size`/`type_cnt` 만 읽음, D-199-9).

### 접근자 API (`src/query/qfile_tuple_layout.h/.c`, cs·sa·cubrid 세 타깃)

- **튜플 슬롯** = 기존 `QFILE_TUPLE_RECORD` 확장 `{tpl, size, tl, nvalid, fast_limit, off, has_null, data_off}`. bind 는 레코드를 채우는 스캔이 한다(filler-owns-bind: `qfile_retrieve_tuple` 이 `&scan_id->list_id.type_list` 로, `cursor_open`, 인덱스 스캔 multi-range 레코드, D-189-4). 튜플 교체는 `qfile_slot_set_tuple` 단일 setter 이며 위치 캐시는 지연 시작(`nvalid = -1`, 첫 접근자가 `qfile_slot_start` 로 has-null·첫 NULL·`fast_limit`·`off` 계산, D-199-7). 걷기 시작 오프셋은 `qfile_prefix_end()` = 첫 NULL/비캐시 컬럼 직전 컬럼의 비정렬 끝(NULL 컬럼은 패딩을 쓰지 않으므로 `col[lim].off` 가 아님 — CTP 크래시 2종의 공통 원인이었다).
- **위치** `qfile_slot_locate(rec, col, &len, &is_null)`: 상수 오프셋 접두 컬럼은 `ALWAYS_INLINE` 1 로드, 그 뒤는 out-of-line `qfile_slot_locate_walk` 의 접두 증분 + `nvalid/off` 캐시(PR-3 항목 6). raw 역참조는 FIXED 컬럼(해시키 INT, 분석함수 카운터, `QEXEC_MERGE_PVALS` NULL 판정)만 허용(D-199-11).
- **값** `qfile_slot_read_value(rec, col, dom, v, copy, &is_null)`: 레이아웃은 bind 된 디스크립터, 디코딩은 호출자 도메인(fetch 는 `pos_descr.dom`, 해시조인은 `fetch_info` 도메인, D-196-3). kind/var_access 별 `data_readval`/`index_readval` 분기 내장(SCRATCH 본문은 4B 정렬돼 제자리 디코드). NULL 이면 DB_VALUE 불변. 일괄 접근자는 별도로 두지 않음(슬롯 캐시로 순차 루프가 O(n), D-196-10).
- **리더 진입점**: `fetch_peek_dbval`/`fetch_copy_dbval`/`fetch_val_list`/`qdata_evaluate_function`(+helper 16)/`fetch_args_peek`/`qexec_gby_agg_tuple`/`qexec_analytic_add_tuple`/`qexec_build_agg_hkey` 가 raw `QFILE_TUPLE` 대신 `QFILE_TUPLE_RECORD *` 를 받는다. `eval_pred` 는 tpl 파라미터가 없어 무변경. TYPE_POSITION 전용 `fetch_peek_dbval_pos` 는 삭제 후 PR-3 에서 슬롯판으로 복원(regu 리스트를 순차 walk 1회로 읽음, D-182-8 정정).
- **조립기** `qfile_tuple_col_src[] {val | (data, len, is_null)}` → `qfile_tuple_size(tl, src, n, &has_null, f_len)` → `qfile_tuple_fill(tl, src, n, out, size, f_len)` 2패스 `static inline`. size 패스가 컬럼 `type_id` 로 본문 길이를 계산해 `f_len` 에 넘기고 fill 은 재계산하지 않는다(한 블록 할당, PR-3 항목 5). 라이터 전 지점 수렴: 4 디스크립터 경로(`qdata_generate_tuple_desc_for_valptr_list`/`qdata_copy_valptr_list_to_tuple` 등), `qfile_fast_intint/intval/val_tuple_to_list` 3함수(삭제), 페이지 밖 조립 5곳, 머지 라이터(`qfile_merge_tuple_add_list` 통합, T_MERGE O(n²)→O(n)), DISTINCT 집계/분석함수/px GROUP_CONCAT·보간 리스트의 raw 항목 라이터 5곳(`qfile_add_item_to_list` 삭제 → `qfile_add_values_tuple_to_list`, D-199-5). 0컬럼 디스크립터(INSERT ... SELECT 내부 블록)는 `n == 0` 허용.
- **in-place** `qfile_slot_overwrite_value(rec, col, val)`: assert(값 non-NULL, 기존 열 non-NULL, 도메인 일치, 디스크 크기 == 저장 길이), release 는 `ER_FAILED`. DIRECT 컬럼도 길이 불변이면 허용. 대상 5지점: orderby_num 3(`qdata_copy_db_value_to_tuple_value` 헤더 재기록 → 본문 전용), inst_num(px_scan_instnum), CONNECT BY ISLEAF/ISCYCLE/parent_pos(44B 상수).
- **해시조인** 선두 키(고정 오프셋 직접 읽기 4벌)와 **분석함수** 2필드(`DB_ALIGN(disksize, 8)` stride) → 위치 접근자. 머지 조인 비교 `qexec_cmp_tpl_vals_merge` 는 두 스캔 슬롯 + 컬럼 인덱스 배열(D-199-12).
- **release 가드**: 폭/인코딩 불일치는 `ER_QPROC_INVALID_DATATYPE`(D-191-3), `cursor_prev_tuple` 은 forward-only 리스트를 release 에서도 거부(D-191-7).

### 정렬 레코드

`P_sort_key` 본문 = 키 컬럼만의 정방향 미니 튜플(hdr 4). `qfile_initialize_sort_key_info` 가 `key_tl` 을 만들어 `SORTKEY_INFO` 에 넣고(빈 `SORTKEY_INFO` 도 초기화, D-190-13) 비교자는 SORT_REC 전용 슬롯 2개. `A_sort_key` 는 `offset[]`·0=NULL 규약 유지, 전체 튜플 재조립은 출력 리스트의 `type_list` 순서로(D-199-4). 비교 함수 `sort_f = qfile_col_cmpdisk_function(col, dom)`: FIXED→`data_cmpdisk`, DIRECT→`index_cmpdisk`(신설 getter), SCRATCH→4B 정렬 본문을 그대로 `data_cmpdisk`(D-201-1; 일시 복사 D-199-6 폐기). `qfile_compare_partial_sort_record`: 전 키가 상수 접두 FIXED 이고 두 튜플에 NULL 이 없으면 `col[i].off` 직접 비교 fast path(D-193-4), 가변(DIRECT) 키는 두 커서 tier(PR-3 항목 4), 그 외는 noinline 일반 경로. `data_cmpdisk` 를 덮어쓰는 특수 타입은 `index_cmpdisk` 도 덮어써야 한다 — ORDER SIBLINGS BY 계층 인덱스 문자열 타입 `bf2df_str_type` 이 유일한 예(D-199-14); 그 비교자 `bf2df_str_compare` 의 경계 밖 1바이트 읽기(구 포맷 0 패딩이 숨김)도 수정(D-191-1). `external_sort.c` 는 포맷 무관.

### 부수 정정

- BIT_AND/BIT_OR/BIT_XOR 누산기 도메인 BIGINT 통일(조립기 프로브가 잡은 기존 불일치, D-190-12).
- `qfile_type_list_copy` 는 열리지 않은 소스 list_id(오류 종료 경로) 를 FORWARD 로 취급(D-199-10 보정).
- `qfile_type_list_is_resolved()` 는 런타임 술어라 `!NDEBUG` 가드 밖(release 빌드 실패 원인, D-193-1).

### PR 구성

upstream PR 은 하나(`CBRD-27365-pr3` → develop, 25커밋). 개인 fork 내부 단계: PR-1a 슬롯 도입·fetch 시그니처(기계적) → PR-1b 리더 접근자 치환·디스크립터·wire(포맷 불변) → PR-2a 조립기·라이터 수렴·정렬 레코드·backward 분류(포맷 불변) → PR-2b 포맷 교체·구 포맷 삭제 → PR-3 성능 후속(가변 키 비교자, size→fill `f_len`·`type_id`, TYPE_POSITION 전용 fetch 복원, locate 인라인 분리).

## 대안 검토

- JIRA 원안(all-fixed 전용 + hidden 파라미터): 접근자마다 포맷 분기, 테스트 매트릭스 2배, 가변 컬럼 리스트가 대부분이라 효과 범위 작음 → 기각.
- `tuple_alignby` 8 항상 / 리스트별 {4,8}: +4~12B/튜플, 후자는 늦은 도메인 특수 규칙 필요 → 상수 4.
- 가변 값 두 부류(SET 등만 4B 정렬 + 4B 헤더): 초기에는 "포맷 규칙 둘" 이라 기각하고 리더 스크래치를 택했으나, PR 리뷰 A/B(JSON 400B 200k 행 분석함수 물질화, +12% wall / +17.6% instructions)로 값마다의 복사·힙 할당 비용이 확인돼 채택으로 번복(D-201-1).
- 슬롯 소유 스크래치(설계 D-182-10): 스캔이 채우는 스택 레코드가 clear 를 부르지 않아 누수 → 일시 복사로 폐기(D-199-2).
- `or_buf` 정렬 계약 완화(`OR_GET_INT` memcpy 화)로 스크래치 제거: 힙·B-tree 공용 계약 → 범위 밖.
- 역방향 판별을 `QFILE_FLAG_RESULT_FILE` 로: "결과 캐시 가능" 표식이라 부적합.
- P_sort_key 를 raw 크기로 조립(PR-3 항목 7): 측정 편차 안 → 미채택.
- 첫 정렬키 Datum 호이스팅(PG `SortTuple.datum1`), 임계를 행 수/바이트 기준으로 재설계: 별도 이슈.

## 영향 범위

- **컴포넌트**: 39파일 +3,769/−2,795. `list_file.c`, `query_executor.c`, `query_opfunc.c`, `query_hash_join.c`, `px_scan_result_handler.cpp`/`px_hash_join_task_manager.cpp`/`px_scan_slot_iterator_list.cpp`, `query_aggregate.cpp`, `query_analytic.cpp`, `query_evaluator.c`, `fetch.c`, `cursor.c`, `scan_manager.c`, `method_scan.cpp`, `pl_query_cursor.cpp`, `network_interface_sr.cpp`, `object_representation.c/h`, `object_primitive.c/h`, `xasl_generation.c`, 신설 `qfile_tuple_layout.{h,c}`(cs/sa/cubrid CMakeLists 등록). 힙 레코드·영속 디스크 포맷 무변경.
- **호환성**: lockstep 업그레이드만. `or_pack_listid` +4B. 혼합 버전 방어 없음(구·신 바이너리 혼합은 오독 또는 hdr_size 에러). CAS/JDBC/CCI 무변경.
- **성능**(같은 호스트 release A/B, TPC-H SF10 parallelism=6, develop 8e355ff59 기준): 결과 동치 22/22. 행당 비용은 PR-3 뒤 A 동등(perf 심볼: 정렬 비교자 S2 17.0→9.0 vs A 7.2, 라이터군 S1 13.8→10.6 vs A 10.5, 리더 M1 11.7→7.7 vs A 8.8). 임시 페이지 감소 21~57%(M1 27,193→11,656). 잔여 회귀(Q13/Q16 +10%, M2 +13%, M3 +16%)는 전부 **페이지 수 기반 병렬도**(`compute_parallel_degree(num_pages)` vs `parallel_{scan,index_scan,hash_join,sort}_page_threshold` 기본 2048) 하향 때문이며, 임계를 1024 로 내리면 A 수준으로 복원됨을 실험으로 확인(D-193-5). 임계 기본값 조정은 이 PR 에 포함하지 않는다 — 병렬 진입 임계 재조정은 CUBRID/cubrid PR #7817(CBRD-27326, parallel scan 진입 임계 4MB) 에서 별도로 다루기로 결정(2026-09-04).
- **플랜 텍스트 부수효과**: 임시 리스트 축소로 페이지 수 기반 실행기 결정(병렬 정렬/해시조인 임계, 해시조인 in-memory 판정 `page_cnt*DB_PAGESIZE <= mem_limit`, JOIN_INNER 빌드측 tie-break "tuple_cnt 같으면 page_cnt 작은 쪽")이 같은 데이터에서 다르게 내려질 수 있다. CTP sql 7 케이스(cbrd_23665, cbrd_24148, cbrd_25382_1/_5, cbrd_25447, cbrd_25519, join_orderby_skip)가 해당하며 엔진 무수정. TC PR(tc/pr-7866, #201)에서 병렬 임계(test_mode: 2페이지)·in-memory 판정은 입력 확대(행 수·튜플 폭)로 원래 경로를 복원했고, 복원이 불가능한 두 곳은 답안을 갱신했다: (1) all-INT 빌드 입력의 hybrid 는 새 포맷에서 in-memory 크기(페이지)와 hybrid 크기(튜플 위치 12B/행)가 거의 같아 8M 기본값 아래 창이 사실상 사라지므로 join_orderby_skip 4곳·cbrd_25382_1 #6 은 `memory` 로; (2) cbrd_25382_1 #3/#4 의 빌드측 tie-break 는 테스트 라벨("-> int")이 기대한 대로 INT 리스트가 빌드가 되므로 그 결과를 답안으로 채택.
- **알려진 한계**: `off > 32767` 컬럼부터 상수 오프셋 캐시 포기(속도만 저하). SCRATCH 타입(SET/JSON/ELO/OBJECT) 값마다 패딩 0~3B + 짧은 값(≤127B)의 헤더 +3B. 정렬 비교가 문자열 계열에서 `index_cmpdisk` 경유라 동치 클래스 내 순서가 구 포맷과 다를 수 있음(결과 동치는 CTP·TPC-H 로 확인).
