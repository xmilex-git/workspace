# R7 — 카탈로그·클래스 객체 안의 직렬화 XASL 스트림과 opcode·enum 저장처 전수 조사, 항목별 판정 (11.4 → develop) (#487)

기준: **D** = develop `5b1867174` (`~/dev/cubrid-worktree/develop`), **R** = `origin/release/11.4` `46212adcd` (merge-base `13a115a0e`). 표기 `D:path:line`, `R:path:line`. 앞선 조사는 다시 하지 않고 인용만 한다: R2(값 인코딩, `research/fastmig-r2-heap-record`), R3(클래스 객체, `research/fastmig-r3-class-repr`), R4(카탈로그 테이블, `research/fastmig-r4-catalog-tables`). 판정 기호: (i) 그대로 복사, (ii) Rust 트랜스코딩(평가 없이 노드 순회·번호 재매핑·재인코딩), (iii) 텍스트에서 재생성, (iv) 엔진이 첫 사용 때 텍스트에서 다시 만들므로 비워도 됨.

## 0. 답 (요약)

1. 직렬화된 XASL 스트림이 영속되는 곳은 **세 종류**다. 엔진의 스트림 생성기(`xts_map_func_pred_to_stream`, `xts_map_filter_pred_to_stream`)를 부르는 곳은 `pt_node_to_function_index`(함수 인덱스, 파티션 식)와 `create_or_drop_index_helper`/`do_recreate_filter_index_constr`(필터 인덱스)뿐이다. 읽는 쪽(`stx_map_stream_to_func_pred`/`_filter_pred`)도 `partition.c`, `btree_load.c`, `heap_file.c`, `filter_pred_cache.c`뿐이다 (code-index callers).
   - (a) **파티션 식**: 마스터 클래스 `SM_PARTITION.values[2]`(클래스 객체 partition 하위구조 pvalues)와, 그 사본인 `_db_partition.pvalues`.
   - (b) **필터 인덱스 pred stream**: 제약 property 시퀀스의 optional info `{pred_string, pred_stream, att_ids}`.
   - (c) **함수 인덱스 expr stream**: `{expr_str, expr_stream, col_id, attr_index_start, fi_domain 바이트}`.
   뷰, 트리거, DEFAULT 식에는 스트림이 없다.
2. 세 스트림 모두 엔진이 텍스트에서 다시 만드는 경로가 **없다**. 읽을 때마다 스트림을 그대로 unpack한다 (D:src/query/partition.c:2880-2893, D:src/query/filter_pred_cache.c:409, D:src/storage/heap_file.c:18474). 그래서 (iv)는 어느 스트림에도 적용할 수 없다.
3. 스트림이 쓰는 노드 부분집합(FUNC_PRED, PRED_EXPR_WITH_CONTEXT, PRED_EXPR/EVAL_TERM, REGU_VARIABLE, ARITH_TYPE, FUNCTION_TYPE, ATTR_DESCR, REGU_VALUE_LIST, cache_attrinfo, DB_VALUE)의 **노드 레이아웃은 11.4와 develop에서 바이트가 같다**. `xasl_to_stream.c`/`stream_to_xasl.c` diff hunk는 XASL_NODE, proc, access spec, val_list, aggregate, analytic에만 있다 (§2.2).
4. 바뀐 것은 **값**이다.
   - ① `ARITH_TYPE.opcode`(OPERATOR_TYPE): 11.4 번호 0..158은 그대로, **159..183은 +4, 184..198은 +6** (§1.1).
   - ② `or_put_value`로 들어간 상수 DB_VALUE: CHAR·NUMERIC은 R2 규칙으로 재인코딩한다.
   - ③ NCHAR/VARNCHAR(26/27) 도메인이나 상수는 develop에 경로가 없으므로 거부한다.
   - ④ 컨테이너 타입: 11.4는 CHAR, develop은 VARCHAR (4fcf6f6c4, CBRD-27163, PR #7858).
   - 도메인 패킹(`or_put_domain`)은 11.4가 쓰는 범위(scale 0..38, collation 플래그)에서 바이트가 같다.
5. **파티션 식 스트림은 (ii) Rust 트랜스코딩**으로 판정한다. 값 길이가 바뀌면 내부 오프셋이 전부 밀리므로 제자리 패치는 불가하다. 11.4 문법으로 파싱한 뒤 develop 레이아웃으로 다시 직렬화해야 한다. 공유 노드(같은 offset을 가리키는 cache_attrinfo 등)는 공유된 채로 유지해야 한다.
   - (iii)은 엔진 컴파일러(`compile_partition_expression` → 파서·semantic check·XASL 생성)가 필요하다. 게다가 develop 의미(예: `DB_DEFAULT_NUMERIC_PRECISION` 15→38)로 다시 컴파일되면 **이미 배치된 행의 라우팅이 달라질 수 있어** 택하지 않는다.
6. **필터·함수 인덱스 스트림**은 "G5(#486)에 의해 제외: 도착 카탈로그에 쓰지 않고 DDL을 대신 출력"한다. 참고로 형태 차이는 파티션과 같다. 함수 인덱스에는 CHAR 컨테이너에 든 packed `fi_domain`이 하나 더 있다.
7. **텍스트로만 저장되고 사용 시 컴파일되는 것**: 트리거 condition/action(`_db_trigger`), 뷰 query spec(클래스 객체 ORC_QUERY_SPEC + `_db_query_spec.spec`), 파티션 `pexpr`(`SELECT expr FROM [cls]`), 필터 `pred_string`, 함수 `expr_str`. 이들은 (i) 복사다. 컴파일된 형태는 어디에도 영속되지 않는다. 트리거는 `eval_condition`/`eval_action`에서 처음 쓸 때 `compile_trigger_activity`로 컴파일된다.
8. **enum 번호 비교**: 차이는 세 가지뿐이다. OPERATOR_TYPE(위 4-①), DB_DEFAULT_EXPR_TYPE(끝에 13 `SYSGUID`, 14 `UUIDV4`, 15 `UUIDV7` 추가, 0..12 동일), DB_TYPE(26/27 이름만 `_DEPRECATED`, 번호 동일). 다음은 모두 같다: FUNC_CODE, MISC_OPERAND, REGU_DATATYPE, REL_OP, BOOL_OP, TYPE_PRED_EXPR, QL_FLAG, DB_TRIGGER_EVENT/TIME/ACTION/STATUS, SM_FOREIGN_KEY_ACTION, DB_AUTH, DB_CONSTRAINT_TYPE, DB_PARTITION_TYPE/PT_PARTITION_TYPE, LANG_COLL_*, SP_TYPE/MODE/LANG enum, sp_directive 0..2. `PT_OP_TYPE`은 **어디에도 영속되지 않는다**.
9. DEFAULT/ON UPDATE 식은 속성 property `"default_expr"`(int, 또는 `{T_TO_CHAR(=103, 두 선 동일), DB_DEFAULT_EXPR_TYPE, format}` 시퀀스)와 `"update_default"`(int)로 저장된다. **(i) 바이트 그대로**다.
10. 범위 밖 위험 하나를 확인했다 [정적 판독, VERIFY]. NUMERIC 키 HASH 파티션의 해시 함수가 바뀌어(`DB_NUMERIC_BUF_SIZE` 16→17, `mht_get_hash_number`) 같은 키가 다른 파티션 번호로 갈 수 있다. 그러면 행 배치 보존과 develop의 pruning이 어긋난다 (§3.8, Open Q1).

## 1. enum 번호 차이 (정확한 위치)

### 1.1 OPERATOR_TYPE (`src/storage/storage_common.h`, 명시적 `=` 없음)

R:storage_common.h:694(T_ADD)..892(T_CONV_TZ)는 0..198로 199개, D:storage_common.h:665..870은 0..205로 206개다. 차이는 끼어든 7개뿐이다(diff 그대로).

| 11.4 번호 | 11.4 이름 | develop 번호 | 비고 |
|---|---|---|---|
| 0..158 | T_ADD … T_CHAR_TO_CLOB(154) … T_INDEX_CARDINALITY(158) | 같음 | **불변**. T_IF 18, T_TO_CHAR 103, T_CASE 114, T_DECODE 136 |
| — | — | 159..162 | **삽입**: T_ESTIMATED_TABLE_ROWS, _AVG_ROW_LENGTH, _DATA_LENGTH, _DATA_FREE (D:827 부근) |
| 159..183 | T_EVALUATE_VARIABLE … T_SYS_GUID | **+4** (163..187) | T_PREDICATE 161→165 |
| — | — | 188, 189 | **삽입**: T_UUID, T_UUID_FORMAT (D:853-854) |
| 184..198 | T_SLEEP … T_CONV_TZ | **+6** (190..204) | |
| — | — | 205 | **추가**: T_COLLECTION_TO_STRING (D:870) |

이슈 본문의 "T_CHAR_TO_CLOB 이후 밀림"은 정정이 필요하다. 처음으로 밀리는 것은 11.4의 159번(`T_EVALUATE_VARIABLE`)이다.

재매핑 식: `new = old + (old >= 184 ? 6 : old >= 159 ? 4 : 0)`.

파티션 식에서 허용되는 연산자(`pt_find_partition_column_count`, D:src/parser/semantic_check.c:5508) 가운데 밀리는 것이 실제로 있다. ADDTIME, BIN, FINDINSET, HEX, ASCII, CONV, INET_ATON/NTOA, TO_BASE64/FROM_BASE64, DBTIMEZONE, SESSIONTIMEZONE, NEW_TIME, FROM_TZ, TO_DATETIME_TZ, TO_TIMESTAMP_TZ, CONV_TZ이다. 따라서 재매핑은 이론상의 문제가 아니다.

### 1.2 DB_DEFAULT_EXPR_TYPE (`src/compat/dbtype_def.h`)

| | 11.4 (R:1204-1219) | develop (D:1262-1281) |
|---|---|---|
| 0..12 | NONE, SYSDATE, SYSDATETIME, SYSTIMESTAMP, UNIX_TIMESTAMP, USER, CURR_USER, CURRENTDATETIME, CURRENTTIMESTAMP, CURRENTTIME, CURRENTDATE, SYSTIME, FORMATTED_SYSDATE | 같음 |
| 13..15 | — | SYSGUID, UUIDV4, UUIDV7 (끝에 추가) |

11.4 값은 모두 develop에서 같은 의미다. 재매핑은 필요 없다.

### 1.3 그 밖의 enum (11.4와 develop의 열거 목록 비교)

| enum | 위치(D) | 결과 |
|---|---|---|
| DB_TYPE | dbtype_def.h | 26/27 `DB_TYPE_NCHAR`/`VARNCHAR` → `_DEPRECATED`(번호 동일). pack/unpack 분기는 삭제(bb8f3cbda #6420). 나머지 번호 동일 |
| FUNC_CODE | src/compat/db_function.hpp | 파일 diff 0 |
| MISC_OPERAND | src/query/string_opfunc.h:124 | 동일 |
| REGU_DATATYPE | src/query/regu_var.hpp:67 | 동일. 플래그 비트는 0x40/0x80(`FETCH_ALL_CONST`/`NOT_CONST`) 삭제. 11.4 writer가 이 둘이 없다고 assert하므로 스트림에 나타나지 않는다. 새 비트 0x1000/0x2000/0x8000은 load 때 파생되며 직렬화되지 않는다 (D:regu_var.hpp:168-185) |
| REL_OP, BOOL_OP, TYPE_PRED_EXPR, QL_FLAG | src/xasl/xasl_predicate.hpp | 동일. diff는 load 때 파생되는 포인터 필드뿐이고 "stream unchanged" 주석이 있다 (D:xasl_predicate.hpp:115-129) |
| DB_TRIGGER_STATUS/EVENT/TIME/ACTION | dbtype_def.h:357-418 | 동일 |
| DB_PARTITION_TYPE / PT_PARTITION_TYPE | storage_common.h:1238-1243 / parse_tree.h:1364-1369 | 동일(0 HASH, 1 RANGE, 2 LIST). `partition_type`에는 PT 값이 그대로 들어간다 (D:execute_schema.c:16358) |
| SM_FOREIGN_KEY_ACTION, DB_AUTH, DB_CONSTRAINT_TYPE | | 동일 |
| LANG_COLL_* (built-in collation id) | src/base/language_support.h:107-118 | 동일 |
| SP_TYPE_ENUM, SP_MODE_ENUM, SP_LANG_ENUM | src/sp/sp_constants.hpp:129-147 | 동일. `SP_SQL_DATA_ACCESS_TYPE` 신규(새 칼럼 `sql_data_access`, R4) |
| sp_directive (비트) | src/sp/sp_catalog.hpp:95-98 | 0x0, 0x1, 0x2 동일, 0x4 `PARALLEL_ENABLE` 추가 |
| PT_OP_TYPE | parse_tree.h:1554 | **영속되지 않음**. 클래스 객체·카탈로그 쓰기 경로에서 PT_* 연산자를 int로 저장하는 곳이 없다(rg). 저장되는 연산자 코드는 default_expr의 `T_TO_CHAR`(OPERATOR_TYPE) 하나뿐이다 |

## 2. 스트림 형식과 11.4 → develop 차이

### 2.1 컨테이너와 헤더

- 스트림은 `[int header_size=0][int body_size]` 뒤에 body가 오고, body는 offset `xasl_stream_make_align(8)`에서 시작한다. 전체 길이는 `8 + body_size`다 (D:src/query/xasl_to_stream.c:380-433, 443-497; R:375, 438). develop의 map 함수 diff는 디버그용 `memset`과 `xts_id_serial`(XASL_NODE 전용)뿐이다.
- 부모는 자식을 **int offset**으로 가리키고(`xts_save_*` 반환값), 같은 포인터를 두 번 저장하면 같은 offset을 쓴다(visited ptr). 모든 노드는 `XASL_STREAM_ALIGN_UNIT` 정렬 위치에 놓인다 (D:xasl_to_stream.c:7907-7913, D:src/xasl/xasl_stream.hpp:109-112).
- 컨테이너 DB_VALUE:

| 스트림 | 11.4 | develop | 근거 |
|---|---|---|---|
| 파티션 values[2] | `db_make_char(size, …, LANG_SYS_CODESET)` R:src/query/execute_schema.c:15511 | `db_make_varchar` D:src/query/execute_schema.c:16447 | 4fcf6f6c4 #7858 |
| 필터 pred_stream (seq[1]) | `db_make_char` R:src/object/class_object.c:842 | `db_make_varchar` D:src/object/class_object.c:847 | 〃 |
| 함수 expr_stream (seq[1]) | `db_make_char` R:class_object.c:8436 | `db_make_varchar` D:class_object.c:8336 | 〃 |
| 함수 fi_domain (seq[4], `or_pack_domain` 바이트) | `db_make_char` R:class_object.c:8446 | **여전히 `db_make_char`** D:class_object.c:8346 | — |

develop reader는 CHAR와 VARCHAR를 모두 받는다 (D:src/query/partition.c:2884 `DB_IS_STRING`, D:src/base/object_representation_sr.c:1799/4090 `case DB_TYPE_VARCHAR`). 하지만 develop에서 CHAR는 새 인코딩(가변+압축, R2)으로 해석되므로 **11.4 CHAR 바이트를 그대로 둘 수는 없다**. 11.4 CHAR(n) 원소는 `STR_SIZE(n, codeset)`까지 공백으로 채워져 있다 (R:src/object/object_primitive.c `mr_writeval_char_internal`). 따라서 Rust는 원소 바이트 중 스트림 자체 길이 `8 + body_size`만 취해 develop VARCHAR로 다시 쓴다. VARCHAR writer의 LZ4 압축 여부는 reader가 헤더로 구분하므로 비압축으로 써도 된다 (R2 표).

### 2.2 노드 레이아웃 (스트림이 쓰는 부분집합)

| 노드 | 직렬화 필드(순서) | diff |
|---|---|---|
| FUNC_PRED | regu off, cache_attrinfo off (D:xasl_to_stream.c:3269-3288) | 없음 |
| PRED_EXPR_WITH_CONTEXT | pred off, num_attrs, attrids int-array off, cache off (D:3239-3266) | 없음 |
| cache_attrinfo | int 0 하나 (D:3291-3302) | 없음 |
| REGU_VARIABLE | packed domain, type, flags, vfetch_to off, xasl off, type별 값 (D:5381, R:5279) | writer의 assert 2줄 삭제만 (D:stream_to_xasl.c:5688-5745는 load 때 파생되는 필드만 추가) |
| ARITH_TYPE | packed domain, value off, **opcode**, left/right/third off, misc_operand, opcode ∈ {T_CASE, T_DECODE, T_PREDICATE, T_IF}이면 pred off (D:5562-5611, R:5462; reader D:stream_to_xasl.c:5987-6085, R:5769) | 내용 없음(`memset`, `plan_item`만) |
| FUNCTION_TYPE | value off, ftype(FUNC_CODE), operand list off (D:5707-5728) | 없음 |
| ATTR_DESCR | id(attid), type(DB_TYPE), cache off (D:5526-5542) | 없음 |
| PRED/EVAL_TERM(comp/alsm/like/rlike) | rel_op, DB_TYPE 등 | load 때 파생되는 포인터만 (D:stream_to_xasl.c:4510, 4559) |
| DB_VALUE | `or_pack_db_value` → `or_put_value(collapse_null=0, include_domain=1, classoids=1)` → packed domain + `data_writeval` + 4B 패딩 (D:src/object/object_representation.c:4819-4899, 5052-5064, 5570; R:4982) | 값 인코딩 차이(R2) |

`val_list`에 도메인이 추가된 것(D:xasl_to_stream.c:5370-5374)은 XASL_NODE 전용이라 이 스트림들에는 나타나지 않는다. 파티션·인덱스 식은 서브쿼리를 허용하지 않으므로 REGU의 `xasl` offset은 0이다.

### 2.3 값·도메인 차이

- 상수 DB_VALUE: CHAR(고정 → 가변+LZ4)와 NUMERIC(16B 2의 보수 → 3B 헤더 + 크기 가변)을 재인코딩한다. 규칙은 R2 §2이고, 값 길이가 달라진다.
- 도메인 패킹:
  - scale: 11.4는 `scale < 255`면 직접 쓴다 (R:object_representation.c:2939). develop은 0..127이면 직접 쓰고, 그 밖과 음수는 0xFF 플래그 뒤에 int를 둔다 (D:2777). develop reader는 0xFF일 때만 확장 int를 읽는다 (D:3443). 11.4 scale(NUMERIC ≤ 38, datetime 계열 ≤ 9)은 직접 영역에 있으므로 **바이트가 같다**.
  - collation: collation int의 ENFORCE/LEAVE 플래그를 쓰는 writer는 두 선이 같다 (R:3084, D:2919). develop `unpack_domain`이 플래그를 해석하도록 고쳐졌을 뿐이다.
  - `DB_DEFAULT_SCALE`이 −1 → −9999로 바뀐 것은 메모리 상수다. 11.4 writer가 음수 scale을 쓰면 carrier가 깨지므로 영속 스트림에는 나타날 수 없다.
- 26/27 도메인과 상수: develop `unpack_domain`/`or_packed_domain_size`에서 case가 삭제됐다 (diff). 해당 스트림은 디코드할 수 없다 → **거부**(R3 A2와 일치).
- develop의 `stx_index_stream_rejected`(D:src/query/stream_to_xasl.c:303-314; be683e04c #8022)는 인덱스 스트림 안에 VARIABLE 도메인의 TYPE_POS_VALUE(호스트 변수)가 있으면 거부한다. DDL 식에는 호스트 변수가 없으므로 11.4 스트림에는 해당하지 않는다 [VERIFY는 런타임으로].

### 2.4 트랜스코더 명세 (파티션 식, (ii))

1. 입력: R3 표 2.3의 partition 요소 pvalues(SEQUENCE). 마스터(`pname == NULL`)의 원소는 `[0]` 키 칼럼 이름(VARCHAR), `[1]` hash size(INT) 또는 NULL, `[2]` 스트림이다 (D:execute_schema.c:16413-16452).
2. `[2]`를 11.4 CHAR 규칙으로 디코드한 뒤 앞 `8 + body_size` 바이트를 취한다.
3. 11.4 문법으로 루트(FUNC_PRED)부터 offset을 따라 파싱한다. visited offset → 노드 맵으로 공유를 보존한다. ARITH의 pred 유무는 **11.4 번호**(T_PREDICATE=161)로 판정한다.
4. 변환: opcode는 §1.1 식으로 바꾸고, 상수 CHAR/NUMERIC은 develop writer 규칙으로 재인코딩한다. 26/27 도메인이나 값이 있으면 중단한다(거부).
5. develop 규칙으로 다시 직렬화한다: 노드마다 정렬된 위치, 공유 노드는 한 번만, 헤더 `[0][body_size]`.
6. VARCHAR로 `[2]`에 다시 넣는다. 같은 sequence가 `_db_partition.pvalues`(마스터 행)에 복사되므로, ct 재생성(R4 요약 4)이 새 클래스 객체에서 그대로 가져가게 한다 (D:src/storage/catalog_class.c:5705-5707, R:5432).
7. 자체 검증: 다시 파싱해 노드 수·공유 수·opcode 집합이 일치하는지 본다(평가는 하지 않는다).

## 3. 항목별 판정표

| # | 항목 | 저장 위치 | 좌표 | 형태 | 11.4→develop 차이 | 판정 | 근거 |
|---|---|---|---|---|---|---|---|
| 3.1 | **파티션 식 스트림** | 클래스 객체 partition 하위구조(마스터) pvalues[2]; `_db_partition.pvalues`(마스터 행) | 쓰기 R:execute_schema.c:15501-15511 / D:16437-16447; 읽기 R:partition.c:2453-2466 / D:2880-2893; ct D:catalog_class.c:5707 | 스트림(+ pexpr 텍스트) | 컨테이너 CHAR→VARCHAR, opcode 재매핑, CHAR/NUMERIC 상수 재인코딩, 노드 레이아웃은 동일 | **(ii)** | 엔진은 매번 values[2]를 직접 unpack한다(텍스트에서 재생성하는 경로 없음). (iii)은 `compile_partition_expression`(D:execute_schema.c:5395-5431, 파서·semantic·XASL 생성)이 필요하고 develop 의미로 바뀔 위험이 있다 |
| 3.2 | 파티션 식 텍스트 `pexpr` | partition 하위구조 pexpr; `_db_partition.pexpr` | R:execute_schema.c:15460-15461 / D:16396-16397; ct D:catalog_class.c:5702 | 텍스트 `SELECT expr FROM [cls]` | 없음 | (i) | 클라이언트 DDL(ALTER/SHOW)에서만 파싱 |
| 3.3 | 파티션 값(RANGE/LIST 경계, HASH size) | 각 partition pvalues; `_db_partition.pvalues` | D:execute_schema.c:16455-16483 | DB_VALUE 시퀀스 | 키 타입이 CHAR/NUMERIC이면 값 재인코딩 | (i), CHAR/NUMERIC 원소만 값 재인코딩 | R3 C4 |
| 3.4 | 파티션 타입 | partition 하위구조 ptype, `class_partition_type` | D:execute_schema.c:16355-16365 | enum int | ptype 동일. `class_partition_type`은 develop 신규 필드 | (i). 신규 필드는 R3 규칙 | R3 §2.3 |
| 3.5 | **필터 인덱스 pred stream** | 클래스 객체 properties 제약 seq optional info `{pred_string, pred_stream, att_ids}` | R:class_object.c:805-860 / D:810-868; server 읽기 D:object_representation_sr.c:1755; 평가 D:filter_pred_cache.c:409, btree_load.c:1334/1526/7486 | 텍스트 + 스트림 | 3.1과 같은 차이 | **G5(#486)에 의해 제외**: 도착 카탈로그에 쓰지 않고 DDL을 대신 출력. `pred_string`은 DDL 생성에 쓴다 | `do_recreate_filter_index_constr`는 ALTER 때만 실행 |
| 3.6 | **함수 인덱스 expr stream + fi_domain** | 제약 seq optional info `{expr_str, expr_stream, col_id, attr_index_start, fi_domain}` | R:class_object.c:8409-8450 / D:8309-8350; server D:object_representation_sr.c:4105; 평가 D:heap_file.c:18474/18611, btree_load.c:1345/1546/7500 | 텍스트 + 스트림 + packed domain(CHAR) | 3.1과 같음. fi_domain은 CHAR 컨테이너 재인코딩(도메인 바이트 자체는 같음) | **G5(#486)에 의해 제외**: DDL 출력. `expr_str` 사용 | `_db_index_key.func`/`_db_index.filter_expression`은 텍스트만 담는다 (D:catalog_class.c:2440-2540) |
| 3.7 | DEFAULT 식 | 속성 property `"default_expr"` = int(DB_DEFAULT_EXPR_TYPE) 또는 seq `{int T_TO_CHAR, int type, string format}` | writer R:transform_cl.c:4635 / D:4636-4720; client reader R:3096 / D:3107-3163; server reader R:object_representation_sr.c:2615 / D:2568-2640 | enum 번호 + 텍스트 | 없음(T_TO_CHAR=103 동일, 0..12 동일, format VARCHAR 동일) | (i) | §1.2; transform_cl.c의 해당 영역 diff 0 |
| 3.8 | ON UPDATE 식 | 속성 property `"update_default"` int | D:transform_cl.c:4724-4745, 3102-3105; server D:object_representation_sr.c:2646 | enum 번호 | 없음 | (i) | §1.2 |
| 3.9 | 속성 기본값 자체 | attributes 하위구조 default/original value, catalog DISK_ATTR 뒤 | R3 §2.2, §3 | DB_VALUE | CHAR/NUMERIC 재인코딩 | R3 C4/E1 | — |
| 3.10 | `_db_attribute.default_value` | ct 행 | R4 §2 | 텍스트(catcls가 클래스 객체에서 만든 문자열) | 칼럼 폭 255→2048 | R4 ct 재생성 규칙(엔진 컴파일러 불필요) | R4 요약 4 |
| 3.11 | **트리거 condition/action** | `_db_trigger.condition`, `.action`(string) | 쓰기 R:trigger_manager.c:1098/1119 / D:1091/1112; 읽기 R:1365/1409 / D:1363/1407 | 텍스트 | 없음 | (i) | 컴파일은 사용 시 `eval_condition`/`eval_action` → `compile_trigger_activity` (D:trigger_manager.c:4739, 4941; R:4713, 4915). 컴파일 결과는 영속되지 않는다 |
| 3.12 | 트리거 enum | `_db_trigger.status, event, condition_type, condition_time, action_type, action_time`(int), `priority`(double) | D:trigger_manager.c:1041-1106 | enum 번호 | 없음(§1.3) | (i). 행 레이아웃은 R4 규칙(새 칼럼 created/updated_time) | — |
| 3.13 | 트리거 참조 OID | 클래스 객체 triggers set, `db_root.triggers`, `_db_user.triggers` | R3 F2, R4 요약 7 | OID | `_db_trigger` 행 재배치 여부에 따름 | R3/R4 규칙 | — |
| 3.14 | **뷰 query spec** | 클래스 객체 ORC_QUERY_SPEC 하위구조(문자열 1개); `_db_query_spec.spec` | D:transform_cl.c:2777-2801 (R:2770) | 텍스트 | 없음(`_db_query_spec.invalidated_time` 칼럼 추가, R4) | (i) | 컴파일된 형태가 저장되지 않으며 사용할 때 mq 변환한다 |
| 3.15 | serial / auto_increment | `_db_serial` 행; 클래스 객체 속성 flag `SM_ATTFLAG_AUTO_INCREMENT` | R4 §2, R3 OQ3 | 값(NUMERIC) + 텍스트 | NUMERIC 재인코딩, `start_val` 등 새 칼럼 | R4 규칙. 스트림·enum 문제 없음 | — |
| 3.16 | SP 메타 | `_db_stored_procedure.sp_type, lang, directive, return_type(DB_TYPE), sql_data_access(신규)`; `_args.data_type, mode, default_value(텍스트)` | D:sp/sp_constants.hpp:129-155, sp_catalog.hpp:95-98 | enum 번호 + 텍스트 | 번호 동일 | (i). 새 칼럼은 R4 규칙 | §1.3 |
| 3.17 | **PL/CSQL 컴파일 코드** | `_db_stored_procedure_code.stype, otype(int), scode(재작성 PL/CSQL 텍스트), ocode(컴파일된 jar 바이트, varchar)` | D:jsp_cl.cpp:1271-1274 (R:1242), D:sp_catalog.cpp:840-866 | 버전 의존 바이너리 | PL 런타임 변경(51파일), SpLib `public static` 선언 340개는 두 선이 같음(라인 집합 비교) | (i) 복사 [PLAUSIBLE]. 실패하면 도착 엔진에서 `ALTER PROCEDURE … COMPILE`(`alter_stored_procedure_code`, D:jsp_cl.cpp:1815, scode 재컴파일, **엔진 필요**) | Open Q4 |
| 3.18 | DB_TYPE 번호 | 클래스 객체 속성 type id, packed domain, `_db_attribute.data_type`, `_db_domain.data_type`, DISK_ATTR.type, SP data_type, 스트림 ATTR_DESCR.type·comp type | §1.3 | enum 번호 | 26/27만 해당 | (i). 26/27은 거부 | R3 A2 |
| 3.19 | collation id / codeset | domain, `_db_domain.collation_id`, `_db_class.collation_id` | D:language_support.h:107-118 | 번호 | 없음 | (i) | — |
| 3.20 | `db_root.timezone_checksum`, `_db_collation.checksum` | 카탈로그 행 | 부팅 검사 D:src/transaction/boot_sr.c:2498-2527 | 체크섬 문자열 | `timezones/` diff 0 | (i). 도착 install이 기본 tz/locale 라이브러리여야 함 | — |
| 3.21 | representation 디렉터리 | catalog DISK_ATTR.type, BT_STATS.has_function | R3 §3 | 번호, 플래그 | DB_TYPE 동일 | R3 E 규칙(재생성) | 스트림 없음 |
| 3.22 | HASH 파티션 행 배치 (스트림 아님) | 사용자 힙 행이 어느 partition 클래스에 있는가 | `mht_get_hash_number` R:src/base/memory_hash.c:2313 / D:2339; 호출 D:partition.c:1255, 1306 (R:1246, 1297) | 암묵적(해시 결과) | NUMERIC: 11.4는 16B 버퍼의 4워드 XOR, develop은 17B 버퍼(`DB_NUMERIC_BUF_SIZE` R:dbtype_def.h:595 → D:647)의 4워드 XOR ^ byte16. 같은 값이라도 바이트 정렬이 1B 밀려 해시가 달라진다(de7bc5ec2 #6486) | 판정 보류 → Open Q1 | 정적 판독. 런타임 확인 전 [VERIFY] |

## 4. 판정 근거 정리

- **(iv)가 없는 이유**: 세 스트림의 reader는 모두 저장된 바이트를 그대로 `stx_map_stream_to_*`에 넘긴다. 텍스트에서 재컴파일하는 함수(`do_recreate_filter_index_constr`, `do_recreate_func_index_constr`, `pt_node_to_partition_info`)는 클라이언트 DDL(ALTER) 경로에서만 불린다 (code-index callers). develop upgradedb의 `sm_force_write_all_classes`도 SM_CLASS 안의 스트림 바이트를 그대로 다시 쓴다(R4 요약 4).
- **(ii)를 파티션에 택하는 이유**: 노드 레이아웃이 같으므로 번호 재매핑과 값 재인코딩만으로 develop reader가 받는 바이트를 만들 수 있다. 결과도 11.4 컴파일 의미(결과 도메인 포함)를 유지하므로 이미 배치된 행과 일치한다. 다만 develop **평가기**가 같은 opcode·도메인에서 11.4와 같은 값을 내는지는 별개 문제다(Open Q2).
- **트리거·뷰·SP 텍스트 (i)**: 형태는 그대로 복사하면 된다. 다만 텍스트가 develop에서 컴파일되는지(11.4에만 있는 이름·문법)는 바이트 문제가 아니라 의미 문제이므로 Open Q3으로 넘긴다.

## 5. Open questions

1. **NUMERIC 키 HASH 파티션**(3.22): develop은 같은 키 값을 다른 파티션 번호로 보낼 수 있다. 확인되면 배치 보존 원칙과 충돌한다. 선택지는 셋이다: (a) pre-check에서 거부, (b) 해당 테이블만 행을 develop 해시로 재분배(배치 보존 예외), (c) 마이그레이션 뒤 엔진에서 `ALTER … REORGANIZE`. 결정 전에 런타임 확인이 필요하다: 11.4에서 `PARTITION BY HASH(numeric_col)`에 행을 넣고, develop 빌드에서 같은 값이 어느 파티션으로 가는지 비교한다. CHAR 키도 develop 메모리 표현(패딩 길이)이 같은지 같은 방식으로 확인해야 한다.
2. 트랜스코딩한 파티션 스트림이 develop에서 로드(`domain_plan_stream_compares`, VARIABLE 도메인 처리)와 평가를 통과하는지, 그리고 모든 행이 develop pruning 결과와 일치하는지 런타임으로 확인해야 한다. T1 기준 DB에는 밀리는 opcode(예: `HASH(ASCII(c))`, `RANGE(… CONV_TZ …)`)와 CHAR/NUMERIC 상수를 쓰는 파티션 식을 넣어야 재매핑이 검증된다.
3. 뷰·트리거·PL/CSQL 텍스트가 11.4 전용 이름(`db_serial`, `db_user`, `db_trigger`, `db_authorizations`, `db_trig` 등 R4 §1 이름 변경)이나 NCHAR 리터럴을 참조하면 develop에서 처음 쓸 때 실패한다. Rust는 SQL을 컴파일할 수 없다. 이름 단위 pre-check 경고로 할지, 마이그레이션 뒤 엔진으로 전부 컴파일하는 검증으로 할지 정해야 한다.
4. PL/CSQL `ocode`(jar)를 그대로 복사했을 때 develop PL 서버에서 로드·실행되는지 확인해야 한다 [PLAUSIBLE: SpLib 공개 선언 집합이 같음]. 실패하면 마이그레이션 뒤 `ALTER PROCEDURE … COMPILE`이 엔진 의존 예외가 된다.
5. NCHAR/VARNCHAR가 도메인이나 상수로 들어 있는 파티션 스트림은 R3 OQ1(NCHAR 처리 방침)과 같은 결정을 따른다(최소안은 거부).

## 6. Sources

- 엔진: develop `5b1867174`, `origin/release/11.4` `46212adcd`.
  - 파일: `src/query/xasl_to_stream.c`, `src/query/stream_to_xasl.c`, `src/xasl/xasl_stream.{hpp,cpp}`, `src/xasl/xasl_predicate.hpp`, `src/xasl/xasl_unpack_info.hpp`, `src/query/regu_var.hpp`, `src/storage/storage_common.h`, `src/compat/dbtype_def.h`, `src/compat/db_function.hpp`, `src/query/string_opfunc.h`, `src/object/object_representation.c`, `src/object/class_object.c`, `src/object/transform_cl.c`, `src/base/object_representation_sr.c`, `src/query/execute_schema.c`, `src/query/partition.c`, `src/storage/catalog_class.c`, `src/object/trigger_manager.c`, `src/sp/{sp_constants.hpp,sp_catalog.hpp,sp_catalog.cpp,jsp_cl.cpp}`, `src/base/memory_hash.c`, `src/base/language_support.h`, `src/parser/semantic_check.c`, `src/parser/parse_tree.h`, `pl_engine/pl_server/.../SpLib.java`.
- 커밋/PR: 4fcf6f6c4 #7858 (CBRD-27163, 스트림 컨테이너 CHAR→VARCHAR), be683e04c #8022 (CBRD-27510, 인덱스 스트림 VARIABLE 거부·load 때 파생 필드), de7bc5ec2 #6486 (CBRD-26006, NUMERIC 17B·도메인 scale 인코딩·해시), bb8f3cbda #6420 (CBRD-24156, NCHAR 제거), 1f1263217 #6443 (제약 시퀀스·partition 타입).
- 앞선 조사: R2, R3, R4 문서(위 브랜치).
