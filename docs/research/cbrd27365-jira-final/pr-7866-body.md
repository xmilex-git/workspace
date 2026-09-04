<http://jira.cubrid.org/browse/CBRD-27365>

### Purpose

임시 리스트 파일(qfile)의 튜플 포맷을 교체합니다.

기존 포맷은 값마다 `[flag 4B][len 4B]` 헤더를 붙이고 값을 8B 경계에 정렬하므로 `(INT, BIGINT)` 한 행이 40B, TPC-H Q1 집계 행이 136B였습니다. 리스트 스키마(`type_list`)는 실행 계획에서 상수인데도 튜플이 자기 기술적이어서 그 비용을 매 행마다 냈습니다.

PostgreSQL MinimalTuple과 같은 구조의 단일 포맷 — `[len 4B(bit31=has-null)] [prev_len 4B, 역방향 가능 리스트만] [널비트맵, NULL 있을 때만] [고정 값은 자연 정렬(최대 4B), 가변 값은 비정렬 + 1B/4B 길이 헤더]` — 으로 바꾸고 컬럼 위치는 `type_list`에서 미리 계산합니다. 같은 행이 16B, 60B가 됩니다. 구 포맷은 삭제하고 on/off 파라미터는 두지 않습니다.

### Implementation

`src/query/qfile_tuple_layout.h/.c`(신설, cs/sa/cubrid 등록): 튜플 슬롯(`QFILE_TUPLE_RECORD` 확장 — 디스크립터 bind + 위치 캐시), 위치/값 접근자 `qfile_slot_locate`/`qfile_slot_read_value`, in-place `qfile_slot_overwrite_value`, 튜플 조립기 `qfile_tuple_size`/`qfile_tuple_fill`(size→fill 2패스), 도메인 구동 순차 deform `qfile_tuple_walk_*`, 레이아웃 계산 `qfile_type_list_finalize`. 서버와 클라이언트 `cursor.c`가 같은 코드를 씁니다.

`query_list.h`: `QFILE_TUPLE_VALUE_TYPE_LIST`에 레이아웃 디스크립터(`hdr_size`, `bitmap_size`, `data_off[2]`, `first_non_cached_col`, 컬럼별 8B `QFILE_COL_LAYOUT`)를 추가했습니다. `col[]`은 `domp[]`와 한 블록으로 할당합니다. 구 포맷의 `QFILE_TUPLE_VALUE_HEADER_*`/`QFILE_GET_TUPLE_VALUE_*` 매크로군은 삭제했습니다.

`list_file.c`: `domp`를 바꾸는 모든 지점(`qfile_open_list`, `qfile_update_domains_on_type_list`, `qfile_unify_types` 등)에서 finalize를 호출합니다. 미확정(`DB_TYPE_VARIABLE`) 컬럼은 조립기가 첫 bound 값에서 확정합니다. `QFILE_FLAG_BACKWARD`로 역방향 가능 리스트(최종 결과, MERGELIST 자식, 분석함수 group/value)만 `prev_len`을 갖고, 정렬 입력의 `qfile_scan_prev` un-read는 save/jump로 바꿨습니다. 정렬 레코드 `P_sort_key` 본문은 키 컬럼만의 미니 튜플이며 비교자는 접근자를 재사용합니다(고정 키 fast path, 가변 키 `index_cmpdisk`).

`fetch.c`, `query_evaluator.c`, `query_executor.c`, `query_opfunc.c`, `query_hash_join.c`, `query_aggregate.cpp`, `query_analytic.cpp`, `px_scan_result_handler.cpp`, `px_hash_join_task_manager.cpp`, `method_scan.cpp`, `pl_query_cursor.cpp`, `cursor.c`: 튜플 리더는 `QFILE_TUPLE_RECORD *`를 받아 접근자로 읽고, 라이터는 조립기로 수렴했습니다(`qfile_fast_*` 3함수, `qfile_add_item_to_list`, `fetch_peek_dbval_pos`의 구 포맷 구현은 삭제; TYPE_POSITION 전용 fetch는 슬롯 기반으로 복원).

`object_representation.c/h`: `or_pack_listid`에 `hdr_size` int 1개를 추가했습니다(`or_listid_length` 8→9 int). `OR_GET_FLOAT/DOUBLE`은 memcpy로 바꿨습니다.

`object_primitive.c/h`: `pr_type`에 `index_cmpdisk` getter/setter를 추가했습니다. `query_executor.c`의 ORDER SIBLINGS BY 계층 인덱스 문자열 타입은 `data_cmpdisk`와 함께 `index_cmpdisk`도 덮어쓰며, `bf2df_str_compare`의 경계 밖 1바이트 읽기를 수정했습니다.

### Remarks

임시 리스트가 작아지면서 리스트 페이지 수로 내리는 실행기 결정(병렬 정렬/해시조인 워커 수 임계, 해시조인 in-memory 판정, 빌드측 tie-break)이 같은 데이터에서 달라질 수 있어 CTP sql 7건의 플랜 텍스트가 바뀝니다. 엔진 임계는 이 PR에서 건드리지 않고 TC 입력 확대로 원래 경로를 유지합니다(tc PR). 클라이언트/서버는 lockstep 업그레이드 전제이며 혼합 버전 방어는 두지 않습니다.
