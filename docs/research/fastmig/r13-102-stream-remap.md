# R13 — 10.2 파티션 식 스트림의 2단 opcode·FUNC_CODE 재매핑이 실제로 필요한 범위 (#523)

Part of xmilex-git/workspace#472. 기준 ref: `origin/release/10.2` = `416bb667c`, `origin/release/11.0` = `44ea22369`, `origin/release/11.4` = `46212adcd`, `origin/develop` = `5cd1de888` (엔진 저장소 `~/dev/cubrid-worktree/develop`). fastmig: `~/dev/cubrid-fastmig` @`14079bfa6`.
정적 조사다. 서버·DB·빌드는 쓰지 않았다. 열거는 awk로 enum과 `case` 줄을 번호 매겨 뽑았고, 산출물은 `.git_ignored_dir/scratch/523/src/`(`op_*.txt`, `func_*.txt`, `map_102_dev.txt`, `wl_ops_num.txt`)에 있다.

## 1. 질문

10.2 출발 파티션 식 스트림(마스터 `SM_PARTITION.values[2]`, R7 §3.1)에 R8의 2단 재매핑(`OPERATOR_TYPE`: 10.2 → 11.x에서 113 이상 +1, 그 뒤 R7의 11.4 → develop 식; `FUNC_CODE`: `F_BENCHMARK` 이후 +5)이 실제로 필요한가? 10.2 `pt_check_partitions`가 허용하는 연산자·함수 가운데 밀리는 구간에 드는 것을 전수로 찾고, 영속 스트림에 나타날 수 있는 것만 낸다.

## 2. 결론

**`OPERATOR_TYPE` 재매핑은 필요하다. `FUNC_CODE` 재매핑은 화이트리스트 기준으로 필요 없다**(단 하나의 구멍으로 `F_BENCHMARK`가 들어올 수 있어 거부 규칙 하나를 둔다).

| 항목 | 판정 | 근거 요지 |
|---|---|---|
| `OPERATOR_TYPE` 10.2 → develop | **필요**. 합성식 `dev = o + (o >= 183 ? 7 : o >= 158 ? 5 : o >= 113 ? 1 : 0)` | 10.2 화이트리스트가 허용해 ARITH 노드로 컴파일되는 서로 다른 `T_*` 149개 중 **46개가 113 이상**이다(+1 23개, +5 10개, +7 13개). 예: `EXTRACT`, `FLOOR`, `ROUND`, `ABS`, `DATE()`, `DATEDIFF`, `ASCII`, `HEX`, `CONV`, `FIND_IN_SET`, `TO_BASE64`, `FROM_TZ`, `CONV_TZ`. 10.2 이름 198개 전부가 이 식으로 develop의 같은 이름 번호에 떨어진다(이름 조인 198/198 일치) |
| ARITH `pred` 유무 판정 | **10.2 번호로 해야 한다** | pred가 있는 opcode는 10.2에서 {18, 113, 135, 160}, 11.4에서 {18, 114, 136, 161}이다. 10.2 바이트를 11.4 번호로 읽으면 10.2 `T_EXTRACT`(114)는 11.4 `T_CASE`로, 10.2 `T_RAND`(136)는 11.4 `T_DECODE`로 보여 **없는 pred offset을 읽는다**. 둘 다 파티션 식에 허용된다 |
| `FUNC_CODE` 10.2 → develop | **화이트리스트 함수는 재매핑 불필요** | 허용 함수 `F_INSERT_SUBSTRING`, `F_ELT`, `F_JSON_*` 25개는 모두 938..962이고 삽입점(`F_REGEXP_COUNT` = 963@11.4) 앞이라 10.2 = 11.4 = develop이다. 11.4 → develop은 `FUNC_CODE` 파일 diff가 없다 |
| `FUNC_CODE` 구멍: `F_BENCHMARK` | **거부 규칙 권고** (추론, [VERIFY] V3) | 함수 인자·연산자 인자 안에 중첩된 *허용 안 된* 함수는 `pt_find_partition_column_count_func`이 `0`을 돌려 거부되지 않는다. `F_BENCHMARK`는 접기에서 빠지고 FUNCTION 노드로 컴파일되므로 이론상 스트림에 963으로 남을 수 있다. develop에서는 968이다 |
| 분석함수용 `PT_*` 코드(`PT_FIRST_VALUE` 이후) | 스트림에 나타나지 않음 | 식 문맥의 함수는 `PT_FUNCTION_HOLDER`를 거쳐야 하고, 문법이 홀더로 감싸는 함수는 ELT·INSERT·JSON·BENCHMARK뿐이다 |
| `DB_TYPE`, `MISC_OPERAND`, `REGU_DATATYPE` | 재매핑 불필요 | `DB_TYPE` 명시 번호 48개가 10.2 = 11.4, `MISC_OPERAND` 12개 동일, `REGU_DATATYPE`은 11.4가 끝에 `TYPE_SP`(16)만 추가 |
| ARITH/FUNCTION/REGU/FUNC_PRED 노드 레이아웃 | 10.2 = 11.4 | `xts_process_arith_type`, `xts_process_function_type`, `xts_process_regu_variable`, `xts_process_func_pred` 본문이 10.2와 11.4에서 글자 단위로 같다 |

10.2 출발에 필요한 재매핑 표(이것이 전부다):

| 10.2 opcode 구간 | develop opcode | 이유 |
|---|---|---|
| 0..112 | 그대로 | 변화 없음 |
| 113..157 | +1 | 11.0 `T_CAST_WRAP` 삽입(10.2 → 11.4 114..158, develop에서 변화 없음) |
| 158..182 | +5 | +1 뒤 11.4 159..183, develop `T_ESTIMATED_*` 4개 삽입으로 +4 |
| 183..197 | +7 | +1 뒤 11.4 184..198, develop +6 (`T_UUID`, `T_UUID_FORMAT` 추가) |
| `FUNC_CODE` 900..962 | 그대로 | 삽입점 앞 |
| `FUNC_CODE` 963 (`F_BENCHMARK`) 이상 | 거부(권고) 또는 +5 | 화이트리스트 밖. 구멍으로만 들어온다 |

## 3. 근거

### 3.1 화이트리스트와 검사 흐름 (10.2)

- `pt_check_partitions`는 파티션 식이 `PT_NAME`이나 `PT_EXPR`가 아니면 거부하고, `PT_EXPR`이면 `pt_find_partition_column_count`로 칼럼 수를 센다. 음수면 거부, 0이면 칼럼 없음, 2 이상이면 거부한다 — `src/parser/semantic_check.c:5770-5794@release/10.2`.
- 연산자 화이트리스트는 `pt_find_partition_column_count`의 `switch`다. `case PT_PLUS:`(:5299)부터 `case PT_CONV_TZ:`(:5452)까지 154개, `PT_RAND`/`PT_RANDOM`은 seed가 있을 때만 허용(:5457-5463), 나머지는 `return -1`(:5466) — `src/parser/semantic_check.c:5280-5470@release/10.2`. `PT_FUNCTION_HOLDER`는 `pt_find_partition_column_count_func`로 넘긴다(:5296-5298). 전체 157개 `case` 라벨 = 연산자 154 + `PT_RAND`·`PT_RANDOM` 2 + `PT_FUNCTION_HOLDER` 1 — 목록은 scratch `wl_102.txt`.
- 함수 화이트리스트: `F_INSERT_SUBSTRING`(:5220)부터 `F_JSON_VALID`(:5244)까지 27개, 그 밖은 `return 0; /* unsupported function */`(:5247) — `src/parser/semantic_check.c:5203-5270@release/10.2`.
- 식의 최종 타입은 정수·날짜시간·문자열 계열만 허용한다(`pt_semantic_type` 뒤 `switch`) — `src/parser/semantic_check.c:5950-5980@release/10.2`. 이 검사는 루트 타입만 보므로 중간 노드(예: `FLOOR`, `ROUND`, `SQRT`)는 결과가 허용 타입으로 캐스트되면 스트림에 남는다(추론).
- 상수 접기는 켜져 있다: `sc_info.donot_fold = false` — `src/parser/semantic_check.c:5952@release/10.2`. 그래서 칼럼을 품지 않은 상수 부분식은 `PT_VALUE`로 접힐 수 있다. 칼럼을 품은 노드는 접히지 않는다(추론, 값을 알 수 없으므로).
- 스트림 생성: `compile_partition_expression` → `pt_semantic_quick_check_node` → `pt_node_to_function_index` → `pt_to_func_pred` → `xts_map_func_pred_to_stream` — `src/query/execute_schema.c:4202-4237, 14027-14030@release/10.2`. 읽기는 `stx_map_stream_to_func_pred` — `src/query/partition.c:2465@release/10.2`.

### 3.2 PT 연산자 → XASL `OPERATOR_TYPE` (10.2)

- `pt_to_regu_variable`의 연산자 `switch`(`src/parser/xasl_generation.c:7589-8990@release/10.2`)에서 각 `case PT_x:` 뒤 `pt_make_regu_arith (..., T_y, ...)`를 짝지었다. 대표 줄: `PT_RAND` → `T_RAND` :7927-7928, `PT_ASCII` → `T_ASCII` :8138-8139, `PT_EXTRACT` → `T_EXTRACT` :8680-8681, `PT_CONV_TZ` → `T_CONV_TZ` :8799-8800. 예외적 매핑: `PT_DIV`→`T_INTDIV`, `PT_MOD`→`T_INTMOD`, `PT_MODULUS`→`T_MOD`, `PT_DAYOFMONTH`→`T_DAY`, `PT_CHAR_TO_BLOB`→`T_BIT_TO_BLOB`, `PT_BLOB_LENGTH`/`PT_CLOB_LENGTH`→`T_LOB_LENGTH`, `PT_CAST`→`T_CAST` 또는 `T_CAST_NOFAIL`.
- ARITH가 아닌 것: `PT_SCHEMA`, `PT_DATABASE`, `PT_VERSION`은 컴파일 때 문자열 상수로 바뀐다 — `src/parser/xasl_generation.c:7832-7900@release/10.2`. `PT_BLOB_FROM_FILE`, `PT_CLOB_FROM_FILE`은 이 `switch`에 `T_*` 짝이 없다(scratch `pt2t.txt`; 추론: 화이트리스트에 있으나 ARITH로 나오지 않는다).
- 화이트리스트 연산자 156개 중 ARITH가 아닌 5개를 뺀 151개가 서로 다른 `T_*` 149개로 컴파일된다(`T_DAY`·`T_BIT_TO_BLOB`·`T_LOB_LENGTH`를 두 PT가 공유, `PT_CAST`는 `T_CAST`·`T_CAST_NOFAIL` 둘). 113 미만이 103개(`T_CAST`=111, `T_CAST_NOFAIL`=112 포함), 113 이상이 46개다.

113 이상으로 컴파일되는 화이트리스트 연산자 전수(46개; 10.2 번호 → 11.4 → develop, develop 값은 이름 조인으로 확인):

| `OPERATOR_TYPE` | PT 연산자 | 10.2 | 11.4 | develop | 합성 이동 |
|---|---|---|---|---|---|
| `T_EXTRACT` | `PT_EXTRACT` | 114 | 115 | 115 | +1 |
| `T_FLOOR` | `PT_FLOOR` | 116 | 117 | 117 | +1 |
| `T_CEIL` | `PT_CEIL` | 117 | 118 | 118 | +1 |
| `T_POWER` | `PT_POWER` | 119 | 120 | 120 | +1 |
| `T_ROUND` | `PT_ROUND` | 120 | 121 | 121 | +1 |
| `T_LOG` | `PT_LOG` | 121 | 122 | 122 | +1 |
| `T_EXP` | `PT_EXP` | 122 | 123 | 123 | +1 |
| `T_SQRT` | `PT_SQRT` | 123 | 124 | 124 | +1 |
| `T_TRUNC` | `PT_TRUNC` | 124 | 125 | 125 | +1 |
| `T_ABS` | `PT_ABS` | 125 | 126 | 126 | +1 |
| `T_STRCAT` | `PT_STRCAT` | 130 | 131 | 131 | +1 |
| `T_RAND` | `PT_RAND` | 136 | 137 | 137 | +1 |
| `T_RANDOM` | `PT_RANDOM` | 138 | 139 | 139 | +1 |
| `T_DATE` | `PT_DATEF` | 143 | 144 | 144 | +1 |
| `T_TIME` | `PT_TIMEF` | 144 | 145 | 145 | +1 |
| `T_DATEDIFF` | `PT_DATEDIFF` | 145 | 146 | 146 | +1 |
| `T_TIMEDIFF` | `PT_TIMEDIFF` | 146 | 147 | 147 | +1 |
| `T_BIT_TO_BLOB` | `PT_BIT_TO_BLOB`, `PT_CHAR_TO_BLOB` | 151 | 152 | 152 | +1 |
| `T_BLOB_TO_BIT` | `PT_BLOB_TO_BIT` | 152 | 153 | 153 | +1 |
| `T_CHAR_TO_CLOB` | `PT_CHAR_TO_CLOB` | 153 | 154 | 154 | +1 |
| `T_CLOB_TO_CHAR` | `PT_CLOB_TO_CHAR` | 154 | 155 | 155 | +1 |
| `T_LOB_LENGTH` | `PT_BLOB_LENGTH`, `PT_CLOB_LENGTH` | 155 | 156 | 156 | +1 |
| `T_TYPEOF` | `PT_TYPEOF` | 156 | 157 | 157 | +1 |
| `T_ADDTIME` | `PT_ADDTIME` | 162 | 163 | 167 | +5 |
| `T_BIN` | `PT_BIN` | 163 | 164 | 168 | +5 |
| `T_FINDINSET` | `PT_FINDINSET` | 164 | 165 | 169 | +5 |
| `T_HEX` | `PT_HEX` | 165 | 166 | 170 | +5 |
| `T_ASCII` | `PT_ASCII` | 166 | 167 | 171 | +5 |
| `T_CONV` | `PT_CONV` | 167 | 168 | 172 | +5 |
| `T_INET_ATON` | `PT_INET_ATON` | 168 | 169 | 173 | +5 |
| `T_INET_NTOA` | `PT_INET_NTOA` | 169 | 170 | 174 | +5 |
| `T_TO_BASE64` | `PT_TO_BASE64` | 180 | 181 | 185 | +5 |
| `T_FROM_BASE64` | `PT_FROM_BASE64` | 181 | 182 | 186 | +5 |
| `T_DBTIMEZONE` | `PT_DBTIMEZONE` | 184 | 185 | 191 | +7 |
| `T_SESSIONTIMEZONE` | `PT_SESSIONTIMEZONE` | 185 | 186 | 192 | +7 |
| `T_TZ_OFFSET` | `PT_TZ_OFFSET` | 186 | 187 | 193 | +7 |
| `T_NEW_TIME` | `PT_NEW_TIME` | 187 | 188 | 194 | +7 |
| `T_FROM_TZ` | `PT_FROM_TZ` | 188 | 189 | 195 | +7 |
| `T_TO_DATETIME_TZ` | `PT_TO_DATETIME_TZ` | 189 | 190 | 196 | +7 |
| `T_TO_TIMESTAMP_TZ` | `PT_TO_TIMESTAMP_TZ` | 190 | 191 | 197 | +7 |
| `T_UTC_TIMESTAMP` | `PT_UTC_TIMESTAMP` | 191 | 192 | 198 | +7 |
| `T_CURRENT_DATETIME` | `PT_CURRENT_DATETIME` | 193 | 194 | 200 | +7 |
| `T_CURRENT_TIMESTAMP` | `PT_CURRENT_TIMESTAMP` | 194 | 195 | 201 | +7 |
| `T_CURRENT_DATE` | `PT_CURRENT_DATE` | 195 | 196 | 202 | +7 |
| `T_CURRENT_TIME` | `PT_CURRENT_TIME` | 196 | 197 | 203 | +7 |
| `T_CONV_TZ` | `PT_CONV_TZ` | 197 | 198 | 204 | +7 |


### 3.3 enum 번호

- `OPERATOR_TYPE`: 10.2는 `T_CAST_NOFAIL`(112) 다음이 `T_CASE`(113) — `src/storage/storage_common.h:802-803@release/10.2`. 11.0부터 그 사이에 `T_CAST_WRAP`이 들어간다 — `src/storage/storage_common.h:803-804@release/11.0`, `:807-808@release/11.4`, `:778-779@develop`. 명시 `=` 없이 0부터 센다. 이름 수: 10.2 198, 11.0 199, 11.4 199, develop 206. 11.0과 11.4는 이름·번호가 같다.
- 10.2 → 11.4: 0..112 이름·번호 동일, 10.2 113..197 = 11.4 114..198(이름 동일) — 기계 비교 결과(scratch `op_10.2.txt` / `op_11.4.txt`).
- 11.4 → develop: R7 §1.1 식(`159..183 +4`, `184..198 +6`); fastmig `opcode::to_develop`이 같은 식이다 — `crates/ondisk/src/partition_stream/opcode.rs:40-49@14079bfa6`.
- 합성식 검증: 10.2 이름 198개 모두에 대해 `o + (o>=113) → R7 식`이 develop의 같은 이름 번호와 같다(198/198, scratch `map_102_dev.txt`). 경계: 10.2 `T_INDEX_CARDINALITY` 157 → 158, `T_EVALUATE_VARIABLE` 158 → 163, `T_SYS_GUID` 182 → 187, `T_SLEEP` 183 → 190.
- pred offset을 쓰는 opcode: `T_CASE || T_DECODE || T_PREDICATE || T_IF` — `src/query/xasl_to_stream.c:5161@release/10.2`, `:5500@release/11.4`. 번호: 10.2 `T_IF` 18, `T_CASE` 113, `T_DECODE` 135, `T_PREDICATE` 160 / 11.4 18, 114, 136, 161 / develop 18, 114, 136, 165.
- 10.2 번호 114 = `T_EXTRACT`(`storage_common.h:804@release/10.2`), 136 = `T_RAND`. 둘 다 화이트리스트 연산자의 컴파일 결과다(`PT_EXTRACT` :8680, `PT_RAND` seed 있음 :7927).
- `FUNC_CODE`: 10.2 `FUNC_TYPE`은 `PT_MIN` = 900부터, `F_JSON_VALID` 962, `F_BENCHMARK` 963 — `src/storage/storage_common.h:893-939@release/10.2`. 11.0에서 `F_REGEXP_COUNT..F_REGEXP_SUBSTR` 5개가 963..967에 들어가 `F_BENCHMARK` 968 — `src/storage/storage_common.h:930-932@release/11.0`. 11.4/develop은 `src/compat/db_function.hpp:65-67`이고 두 파일이 같다(`diff` 0). 900..962 구간 63개 이름·번호는 10.2 = 11.4.
- `DB_TYPE`: 명시 `= N` 48개가 10.2(`src/compat/dbtype_def.h:669-722@release/10.2`)와 11.4(`:692-745@release/11.4`)에서 같다.
- `MISC_OPERAND`: 12개 동일 — `src/query/string_opfunc.h:121@release/10.2` 블록과 11.4 블록 비교.
- `REGU_DATATYPE`: 10.2 16개(`src/query/regu_var.hpp:62@release/10.2`), 11.4는 끝에 `TYPE_SP`(16) 추가(`:64@release/11.4`). 앞 번호 이동 없음.

### 3.4 `F_BENCHMARK` 구멍 (추론)

- 문법은 식 안의 `ELT`, `INSERT`, JSON 함수, `BENCHMARK`를 `parser_make_expr_with_func`로 `PT_FUNCTION_HOLDER(PT_FUNCTION)`에 감싼다 — `src/parser/csql_grammar.y:24541-24557, 17109-17113@release/10.2`.
- 중첩 인자가 `PT_FUNCTION_HOLDER`면 `pt_find_partition_column_count` → `pt_find_partition_column_count_func` → 허용 안 된 함수는 `return 0`(:5247). 호출 측은 `ret < 0`일 때만 거부한다(:5480-5540) 또는 `ret > 0`일 때만 더한다(:5261). 그래서 칼럼을 품지 않은 `BENCHMARK(...)`가 인자 자리에 있으면 거부되지 않는다.
- `F_BENCHMARK`는 접기를 막는다(`pt_fold_constants_pre`/`_post`) — `src/parser/type_checking.c:7689-7693, 7734-7738@release/10.2`. FUNCTION regu로 컴파일된다 — `src/parser/xasl_generation.c:6245, 6330@release/10.2`(`pt_function_to_regu`의 결과 타입 `switch`).
- 따라서 `PARTITION BY HASH (CONCAT(c, BENCHMARK(1, 1)))` 같은 식이 10.2에서 만들어질 수 있다고 추론한다(최종 타입 검사를 통과하는지는 [VERIFY] V3).

### 3.5 fastmig 현재 상태

- `transcode_partition_stream`은 `(V11_4, Develop)` 외 쌍을 거부한다 — `crates/ondisk/src/partition_stream/mod.rs:31-47@14079bfa6`.
- `VersionLine`은 `V11_4`, `Develop` 둘뿐이다 — `crates/ondisk/src/version_line.rs:10-15@14079bfa6`.
- 파서의 opcode 범위·pred 판정은 `VersionLine`별 상수다(`opcode_count` 199/206, `T_PREDICATE` 161/165, `T_CASE` 114 고정) — `crates/ondisk/src/partition_stream/opcode.rs:13-36@14079bfa6`; 사용처 `read.rs:269, 280`.
- FUNCTION 노드의 `ftype`은 읽고 그대로 쓴다(재매핑·범위 검사 없음) — `crates/ondisk/src/partition_stream/read.rs:306-316@14079bfa6`. 11.4 → develop에서는 맞다(FUNC_CODE 동일).
- `to_develop::map_tree`가 ARITH opcode에 `opcode::to_develop`을 적용한다 — `crates/ondisk/src/partition_stream/to_develop.rs:81-85@14079bfa6`.

## 4. fastmig에 대한 함의

1. **10.2 출발을 지원할 때 `ondisk::partition_stream`이 할 일**(10.2를 여는 티켓, R8 D10):
   - `VersionLine::V10_2`(또는 10.2..11.3 공통이 아니라 *10.2만*) 추가. `opcode.rs`에 10.2 상수: `opcode_count = 198`, `T_IF 18`, `T_CASE 113`, `T_DECODE 135`, `T_PREDICATE 160`. **11.4 상수를 10.2 바이트에 쓰면 `EXTRACT`/`RAND(seed)` 식에서 파싱이 어긋난다.**
   - `to_develop`에 출발 라인 인자를 주고, 10.2면 위 합성식(2절 표)을 적용한다. 11.0..11.3은 11.4와 `OPERATOR_TYPE` 번호가 같으므로(11.0 = 11.4 확인) 1단 없이 R7 식만 적용한다(11.1..11.3은 11.0 = 11.4 사이에 끼어 있으므로 같다고 추론; [VERIFY] V5).
   - `FUNCTION.ftype`: 10.2면 `ftype >= 963`(`F_BENCHMARK` 이상)을 **거부**한다(권고). 대안은 +5 재매핑이지만 그런 파티션은 실사용에서 의미가 없다. 900..962는 그대로 둔다.
   - 그 밖의 스트림 내용(10.2 상수 문자열의 LZO 압축, CHAR/NUMERIC 상수 재인코딩, 컨테이너 CHAR → VARCHAR)은 이 티켓 범위 밖이며 R8 §2.8/§2.12와 R7 §2.4가 다룬다. 노드 레이아웃은 10.2 = 11.4이므로 파서 구조는 그대로 쓴다.
2. **T1 기준 DB(10.2 출발)를 만들 때**: 세 구간을 하나씩 덮는 파티션 식을 넣어야 재매핑이 검증된다. 예: `+1` — `HASH(EXTRACT(YEAR FROM d))`, `RANGE(FLOOR(i/10))`; `+5` — `HASH(ASCII(c))`, `LIST(HEX(i))`; `+7` — `RANGE(CONV_TZ(dt, ...))` 또는 `HASH(TO_CHAR(FROM_TZ(dt, 'UTC')))`; pred 판정 — `HASH(RAND(i))`는 의미 없는 배치를 만들므로 `EXTRACT`로 충분하다.
3. **P9 11.5 릴리스 직전 반영(#528)**: 11.4 → develop 식이 바뀌면(develop에 새 `T_*` 삽입) 10.2 합성식의 2단도 같이 바뀐다. 합성식을 별도 상수로 두지 말고 `10.2 → 11.4` 1단 함수와 기존 `to_develop`을 합성해 쓰는 편이 반영 지점을 하나로 만든다.

## 5. [VERIFY] 목록

| # | 주장 | 확인 probe | 기대값 |
|---|---|---|---|
| V1 | 10.2 `HASH(EXTRACT(YEAR FROM d))` 파티션의 마스터 스트림에 ARITH opcode 114가 있고 pred offset이 없다 | 10.2 install(현재 없음)에서 테이블 생성 → `pvalues[2]` 바이트 덤프 → fastmig 파서에 10.2 상수로 파싱 | opcode 114, ARITH 노드 크기에 pred 칸 없음, 노드 수 일치 |
| V2 | 같은 스트림을 11.4 상수로 파싱하면 실패하거나 다른 트리가 나온다(회귀 방지) | V1 덤프를 `parse(V11_4, ..)`에 넣는다 | `DecodeError` 또는 canonical 불일치 |
| V3 | 10.2가 `PARTITION BY HASH (CONCAT(c, BENCHMARK(1,1)))`를 받아들이고 스트림에 FUNCTION ftype 963이 남는다 | 10.2 csql에서 DDL 실행, 성공 시 `pvalues[2]` 덤프 | 성공하면 ftype 963 노드 1개; 실패하면 구멍 없음(거부 규칙은 그대로 무해) |
| V4 | 10.2 → develop 합성식으로 트랜스코드한 스트림이 develop에서 로드되고 모든 행이 같은 파티션으로 판정된다 | 10.2 출발 T1 DB(위 4.2의 식들)를 migrate → develop에서 `SELECT ... FROM t__p__pN` 행 수와 pruning 결과 비교 | 파티션별 행 수 동일, develop pruning 결과 = 저장 배치 |
| V5 | 11.1, 11.2, 11.3의 `OPERATOR_TYPE`이 11.4와 이름·번호가 같다 | `git show origin/release/11.{1,2,3}:src/storage/storage_common.h`를 같은 awk로 번호 매겨 11.4와 `diff` | diff 0 (199개) |
| V6 | 칼럼 없는 nilary 연산자(`CURRENT_DATE`, `DBTIMEZONE`, `UTC_TIMESTAMP` 등, 10.2 184..196)가 접히지 않고 스트림에 남는지 | 10.2에서 `RANGE(DATEDIFF(d, CURRENT_DATE))` 같은 식 생성 → 스트림 덤프 | 남으면 opcode 195 등이 보이고 +7 재매핑 대상; 접히면 상수 DB_VALUE. 어느 쪽이든 재매핑 표는 그대로 맞다 |

## 6. 새 질문

정확히 서술할 수 있는 것:
- **10.2 partition_stream 지원 task**: `VersionLine::V10_2` 추가, `opcode.rs` 10.2 상수, `to_develop`의 출발 라인별 1단 재매핑, `ftype >= 963` 거부, V1·V2·V4 확인. 10.2 install이 없으므로 10.2 빌드·설치가 선행이다(R8의 10.2 출발 범위 결정을 따름).
- **11.0..11.3 `OPERATOR_TYPE` 동일성 확인**(V5): 정적 awk 비교 한 번으로 끝난다.

아직 흐린 것:
- 10.2 상수 문자열(LZO)과 CHAR/NUMERIC 상수의 10.2 인코딩이 11.4 디코더로 그대로 읽히는지 — R8 §2.8 범위, 파티션 스트림 관점에서 별도 확인이 필요한지 아직 모른다.
- develop 평가기가 10.2 컴파일 의미(결과 도메인, NUMERIC 기본 정밀도 등)의 스트림을 10.2와 같은 값으로 평가하는지 — R7 Open Q2와 같은 질문이 10.2에서는 간격이 더 넓다.
