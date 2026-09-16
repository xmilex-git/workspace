# CUBRID 호스트 변수(`?`) 도메인의 결정·전파·실행 비용 — 전 계층 조사

- 지도: xmilex-git/workspace#268, 티켓 #269 (연구: 서버 실행 경로의 호스트 변수 늦은 바인딩 지점 전수)
- 기준: `/home/cubrid/dev/cubrid` 브랜치 `develop`, HEAD `a60c1b9c0` (2026-09-16)
- 작성: Explore 서브에이전트(읽기 전용 코드 추적), 리드 검수

---

## 0. 한 줄 요약

`?`는 파서에서 **`PT_TYPE_MAYBE`**로 태어나고, 의미분석(`pt_eval_expr_type` / `pt_assignment_compatible`)이 **비교 상대(컬럼)로부터 `expected_domain`을 추론**한다. 추론에 성공하면 XASL의 `REGU_VARIABLE.domain`이 구체 도메인으로 고정되고, 실패하면 `pt_xasl_type_enum_to_domain(PT_TYPE_MAYBE)` → **`DB_TYPE_VARIABLE`** 도메인이 XASL에 그대로 박혀 서버로 직렬화된다. 서버 실행에서 `DB_TYPE_VARIABLE`은 (1) `fetch_peek_dbval()` 인라인 fast-path를 **완전히 차단**하고, (2) `eval_value_rel_cmp()`/`tp_value_compare_with_error()`의 **행마다 타입 비교·강제변환 분기**를 태우며, (3) `qdata_*` 산술에서 도메인 NULL 처리로 인해 **값 기반 도메인 재해석**을 매번 하게 만든다.

---

## 1. 파서 / 시맨틱 계층 (`src/parser/`)

### 1.1 `?` 노드 생성 — 타입 없음

`src/parser/csql_grammar.y:13762-13779` (`host_param_input: '?'`)
```c
PT_NODE *node = parser_new_node (this_parser, PT_HOST_VAR);
node->info.host_var.var_type = PT_HOST_IN;
node->info.host_var.str = pt_makename ("?");
node->info.host_var.index = parser_input_host_index++;
```
`type_enum`은 설정하지 않음(= `PT_TYPE_NONE`).

자동 파라미터화(auto-param)로 생기는 호스트 변수는 `src/parser/parser_support.c:4798-4825` (`pt_create_param_for_value`)에서 만들어지며, 원본 값 노드의 `type_enum`/`expected_domain`/`data_type`을 **그대로 복사**하므로 처음부터 도메인이 고정된다(4807-4809행).

`src/parser/name_resolution.c:11880-11912` — 정적 SQL 파라미터화 경로에서 슬롯 확장:
```c
parser->host_var_expected_domains[parser->host_var_count] = pt_type_enum_to_db_domain (PT_TYPE_NONE);
```
즉 **초기 expected domain은 `DB_TYPE_UNKNOWN`(NONE)** 이다.

### 1.2 MAYBE로 승격되는 지점

`src/parser/type_checking.c:8151-8157` (`pt_eval_type`, post-walk):
```c
case PT_HOST_VAR:
  if (node->type_enum == PT_TYPE_NONE && node->info.host_var.var_type == PT_HOST_IN)
    {
      /* type is not known yet (i.e, compile before bind a value) */
      node->type_enum = PT_TYPE_MAYBE;
    }
  break;
```
`PT_TYPE_MAYBE` → `DB_TYPE_VARIABLE` 매핑은 `src/parser/parse_dbi.c:2420-2421` (`pt_type_enum_to_db`), 역방향은 `parse_dbi.c:2692-2693`.

### 1.3 바인딩 값이 이미 있을 때 (prepare 시점 바인딩)

`src/parser/name_resolution.c:1059-1071` (`pt_bind_type_of_host_var`), 호출부 `name_resolution.c:3730-3732`. `pt_host_var_db_value`(`parse_dbi.c:3160-3175`)는 **`parser->flag.set_host_var`가 1일 때만** 값을 돌려준다. CAS/JDBC의 `PREPARE`는 값이 없으므로 이 경로는 타지 않는다.

### 1.4 `WHERE col = ?` — prepare 시점에 컬럼으로부터 도메인을 추론하는가? → **YES (대칭 연산자 한정)**

**경로 A: `pt_eval_expr_type`의 대칭 연산자 처리** — `src/parser/type_checking.c:9555-9607`
```c
if (pt_is_symmetric_op (op))
  {
    if (arg1_hv && arg2_type != PT_TYPE_NONE && arg2_type != PT_TYPE_MAYBE)
      { ...
        (void) pt_coerce_value (parser, arg1, arg1, arg2_type, arg2->data_type);
        arg1_type = arg1->type_enum;
        d = pt_xasl_type_enum_to_domain (arg1_type);
        SET_EXPECTED_DOMAIN (arg1, d);
        pt_preset_hostvar (parser, arg1);
      }
    if (arg2_hv && arg1_type != PT_TYPE_NONE && arg1_type != PT_TYPE_MAYBE)
      { /* 대칭: col = ? 에서 ?가 arg2 */ ... }
  }
```
`pt_is_symmetric_op`은 `type_checking.c:6234`. `PT_EQ/NE/GT/GE/LT/LE`가 포함된다.

`pt_coerce_value` → `pt_coerce_value_internal`(`type_checking.c:19575`)의 `case PT_HOST_VAR`(19653-19664):
```c
case PT_HOST_VAR:
  /* binding of host variables may be delayed ... assume each host variable is typeless */
  if (parser->flag.set_host_var == 0)
    {
      dest->type_enum = desired_type;                       /* ← MAYBE 탈출 */
      dest->data_type = parser_copy_tree_list (parser, data_type);
      return NO_ERROR;
    }
  [[fallthrough]];
```
즉 **바인딩 전(prepare)에는 호스트 변수 노드의 `type_enum`/`data_type`을 컬럼 타입으로 덮어쓴다.** 이후 `SET_EXPECTED_DOMAIN` + `pt_preset_hostvar`가 전역 배열에도 기록한다. 값이 이미 바인딩된 상태(`set_host_var == 1`)에서는 `tp_value_cast`를 수행하되 `type_checking.c:19713-19720`에서 **노드 타입은 바꾸지 않고 리턴**한다(`PRM_ID_HOSTVAR_LATE_BINDING == false`일 때).

**경로 B: 할당 호환성 — `pt_assignment_compatible`** — `src/parser/semantic_check.c:13375-13463` (`INSERT ... VALUES (?)`, `UPDATE SET c = ?`). 우선순위(13409-13411): 1. `host_var_expected_domains[index]` 2. lhs expected domain 3. lhs 타입 기본 도메인. `pt_set_expected_domain (rhs, d)`(13458) + `pt_preset_hostvar`(13461).

**경로 C: INSERT / MERGE 값 리스트** — `type_checking.c:8059-8079`(INSERT), `7932-7953`(MERGE). `parser->flag.set_host_var == 0`일 때만 `attr_list` 도메인을 `?`에 부여.

**경로 D: 비대칭 연산자 / IN 리스트** — `type_checking.c:9673-9727`. `a IN (?, ?, ...)`는 9685-9714에서 `arg1_type`으로 `pt_coerce_value` + `pt_preset_hostvar`.

**경로 E: 시그니처 기반 강제** — `type_checking.c:4653-4694` (`pt_coerce_expression_argument`)
```c
if (node->type_enum == PT_TYPE_MAYBE)
  {
    if ((node->node_type == PT_EXPR && pt_is_op_hv_late_bind (node->info.expr.op)) || ...)
      { /* wrap with cast, instead of setting expected domain */
        node->expected_domain = NULL;   /* ← 의도적으로 VARIABLE 유지 */
      }
    else
      { ... SET_EXPECTED_DOMAIN (node, d); }
    if (node->node_type == PT_HOST_VAR)
      pt_preset_hostvar (parser, node);
  }
```

### 1.5 `pt_set_expected_domain` / `pt_preset_hostvar` / `pt_hv_consistent_data_type_with_domain`

- `type_checking.c:8608-8618` `pt_preset_hostvar`: `pt_hv_consistent_data_type_with_domain` 후 `host_var_expected_domains[index] = hv_node->expected_domain` (auto-param은 전역 배열 미사용).
- `type_checking.c:8626-8640` `pt_set_expected_domain`: 노드 자신 + **`or_next` 체인**에도 전파(MAYBE이고 아직 NULL인 경우만).
- `type_checking.c:23839-23893` `pt_hv_consistent_data_type_with_domain` → `pt_update_host_var_data_type`: `data_type`을 `expected_domain`과 일치. **`data_type`이 NULL이면 no-op**.
- 매크로 `SET_EXPECTED_DOMAIN`: `type_checking.c:68-82`.

### 1.6 언제 MAYBE/VARIABLE로 남는가

1. **`pt_is_op_hv_late_bind(op)`가 true인 연산자** — `type_checking.c:20525-20571`: `PT_PLUS, PT_MINUS, PT_TIMES, PT_DIVIDE, PT_MODULUS, PT_ABS, PT_CEIL, PT_FLOOR, PT_ROUND, PT_TRUNC, PT_UNARY_MINUS, PT_IFNULL, PT_NVL, PT_NVL2, PT_COALESCE, PT_NULLIF, PT_LEAST, PT_GREATEST, PT_TO_CHAR, PT_TO_DATE, PT_TO_DATETIME, PT_STR_TO_DATE, PT_HEX, PT_CONV, PT_ASCII, PT_ADDTIME, PT_FROM_TZ, PT_NEW_TIME, PT_HOURF/MINUTEF/SECONDF, PT_BIT_LENGTH, PT_OCTET_LENGTH, PT_EVALUATE_VARIABLE, PT_DEFINE_VARIABLE` 등. 주석(20517-20523): "leave its HV arguments as TYPE_MAYBE ... wrapped with cast rather then its result type be forced to an expected domain".
2. **양쪽이 모두 MAYBE** — `? = ?`, `? + ?`.
3. **`PT_DOES_FUNCTION_HAVE_DIFFERENT_ARGS(op)`** — `type_checking.c:9748-9752`: 인자를 건드리지 않음.
4. **SELECT 리스트의 맨 `?`** — `SELECT ? FROM t`: 비교 상대가 없어 추론 불가.
5. `type_checking.c:9756-9760` 이하에서 `node->expected_domain`이 numeric/string일 때만 arg1에 전파되므로 date/time·collection 등은 남는다.
6. `func_type.cpp:990-992`에서 함수 결과 타입을 인자 `expected_domain`으로 역산하는 보완이 있으나 부분적.

### 1.7 실행 시점 강제 변환 — `db_push_values` / `pt_set_host_variables`

`src/compat/db_vdb.c:1901-1927` → `src/parser/parse_dbi.c:3092-3155`:
```c
hv_dom = parser->host_var_expected_domains[i];
if (TP_DOMAIN_TYPE (hv_dom) == DB_TYPE_UNKNOWN || hv_dom->type->id == DB_TYPE_ENUMERATION)
  pr_clone_value (val, hv);                         /* ← 도메인 미추론: 값 그대로 */
else if (tp_value_cast_preserve_domain (val, hv, hv_dom, false, true) != DOMAIN_COMPATIBLE)
  { PT_ERRORmf2 (... MSGCAT_SEMANTIC_CANT_COERCE_TO, "host var", ...); return; }
```
`hv_dom`이 UNKNOWN이면 값은 드라이버가 준 타입 그대로 서버로 간다 → 서버는 `DB_TYPE_VARIABLE` regu domain과 임의 타입 값을 만난다.

- `do_cast_host_variables_to_expected_domain` — `db_vdb.c:3205-3251` 세션 버전(UNKNOWN/ENUM은 `continue`). 호출부 `db_vdb.c:1087`(subsession prepare, XASL 생성 **전**), `3592`, `3754`.
- `pt_bind_values_to_hostvars` — `name_resolution.c:3838-3851`: **XASL 캐시 OFF일 때만**(`db_vdb.c:2343`) `?`를 상수로 치환하고 재-resolve/재-type.
- 값→노드 타입: `parse_dbi.c:1100-1190` (`pt_value_to_db`의 `PT_HOST_VAR` 분기), `pt_bind_type_from_dbval`(3052-3057), `value->expected_domain = hv_dom;`(1180).

---

## 2. CAS / 브로커 계층

### 2.1 PREPARE — 타입 정보 없음

`src/broker/cas_execute.c:622` `ux_prepare()` → `db_compile_statement()`만 호출, 바인드 값 없음 → `set_host_var == 0`으로 시맨틱/XASL 생성.

프리페어 응답의 마커 정보 — `cas_execute.c:3483-3532`: `db_marker_domain(param)` → `db_vdb.c:1650-1665`는 `marker->expected_domain`(없으면 `pt_node_to_db_domain`). **CAS가 드라이버에 돌려주는 파라미터 타입 = `expected_domain`.** 추론 실패 시 VARIABLE/NULL → `CCI_PARAM_MODE_UNKNOWN`. PL/CSQL 동일: `src/method/method_callback.cpp:649-669`.

### 2.2 EXECUTE — 타입 있는 값이 도착

`cas_execute.c:1025` `ux_execute()`: `make_bind_value`(1076, → 3289-3320 → `netval_to_dbval` 3881, **드라이버 CAS type byte로 DB_VALUE 생성**) → `set_host_variables`(1082, → 10317 → `db_push_values`). `ux_execute_all`(1357), `ux_execute_call`(1710), `ux_execute_array`(2147) 동일.

### 2.3 플랜 캐시 키에 호스트 변수 타입이 들어가는가? → **아니오**

`src/query/execute_statement.c:108` `CUSTOM_PRINT_4_SHA_COMPUTE = PT_CONVERT_RANGE | PT_PRINT_QUOTES | PT_PRINT_USER | PT_PRINT_HOST_VAR_COUNT | PT_PRINT_DBLINK_INFO`. `do_prepare_select`(15263-15274)가 SHA1 계산. `PT_PRINT_HOST_VAR_COUNT`(`parse_tree_cl.c:3099-3120`)는 `";bind_var_cnt=<n>"` **개수만**. 캐시 비교는 `xasl_cache.c:691` SHA1 만. 안전장치: `print_type_ambiguity`(`parse_tree.h:3972`)가 서면 `cannot_prepare = 1`(15281-15285; 9939, 11321, 11982, 18329 동형).

### 2.4 XASL에 도메인이 실려 서버로 간다

`xasl_to_stream.c:5376-5382` (`xts_process_regu_variable`): 도메인을 regu 앞에 pack. `TYPE_POS_VALUE` payload는 인덱스뿐(5507-5509 / `stream_to_xasl.c:5803-5805`). 서버 언패킹 시 `regu->original_domain = domain`(`stream_to_xasl.c:6843-6845`). → **VARIABLE 도메인이 캐시된 XASL에 박혀 모든 실행에 재사용.**

### 2.5 재컴파일 트리거들 (값 기반, 타입 기반 아님)

`pt_recompile_for_like_optimizations`(`parser_support.c:10254-10274`), `pt_recompile_for_limit_optimizations`(10298-10356), `HV_PRED_PLAN_UNPEEKED`(`execute_statement.c:15324-15333`; `db_vdb.c:2228-2273` `histogram_bind_fingerprint`/`do_replan_statement_with_bind_peek`), 서버측 `xcache_find_sha1`(`xasl_cache.c:850-872`) `XCACHE_ENTRY_RECOMPILED_REQUESTED`. **어느 것도 타입 불일치로는 트리거되지 않는다.**

---

## 3. XASL 생성 (`src/parser/xasl_generation.c`)

### 3.1 `PT_HOST_VAR` → `TYPE_POS_VALUE` — 9608-9610 (`pt_to_regu_variable`) → `pt_make_regu_hostvar`.

### 3.2 `pt_make_regu_hostvar` — 도메인 결정 4단 폴백 — 6390-6502
1. `node->data_type` → `pt_xasl_node_to_domain` (6412-6416)
2. 실제 바인딩 값의 도메인(`set_host_var == 1 || typ != DB_TYPE_NULL`; CHAR면 codeset/collation/precision/scale 복사) (6418-6447)
3. `node->expected_domain` (6449-6454)
4. `pt_xasl_type_enum_to_domain (node->type_enum)` → MAYBE면 **DB_TYPE_VARIABLE** (6456-6459; `xasl_generation.c:2250-2256` → `parse_dbi.c:1529` → `2420-2421`)

이어서 6465-6491: prepare 시점(값 없음)에는 `db_value_domain_init (val, exptyp, ...)`로 호스트 변수 슬롯 선-초기화; `exptyp == DB_TYPE_VARIABLE`이면 무의미. 값이 있고 타입/collation 불일치면 `tp_value_cast`.

### 3.3 `DB_TYPE_VARIABLE` 명시 사용처
- 28565 — `pt_to_cume_dist_percent_rank_regu_variable` (`TYPE_REGU_VAR_LIST`)
- 5889-5916 — sort spec: `GROUP BY ?`/`ORDER BY ?` 금지(`MSGCAT_SEMANTIC_NO_ORDERBY_ALLOWED`)

### 3.4 술어 생성 — `et_comp->type`이 NULL이 되는 경우 — 1548-1558 (`pt_to_pred_expr`)
```c
if (arg1 && arg2 && (arg1->type_enum == arg2->type_enum))
  data_type = pt_node_to_db_type (arg1);
else
  data_type = DB_TYPE_NULL;	/* let the back end figure it out */
```
`pt_make_pred_term_comp`(1334-1356) `et_comp->type = data_type;`(1350). `col(INTEGER) = ?(MAYBE)`면 `DB_TYPE_NULL`. `eval_fnc`(`query_evaluator.c:2614`)의 `single_node_type`으로 나가지만 현재 호출부(`scan_manager.c:3283, 3342, 3403, 3633-3647, 3948, 4058`)에서 **소비하지 않는다** — 최적화 여지.

### 3.5 인덱스 키 / ISS
- 키 상수성: 10593, 10715, 10745-10746, 10986, 11018, 11237, 11330, 11346 — `is_constant &= (PT_VALUE || PT_HOST_VAR)`. **호스트 변수는 상수 키**로 취급.
- `pt_to_key_info`의 `case PT_HOST_VAR` — 10904.
- ISS 레인지 `pt_create_iss_range` 10422-10450(호출 12243, 12251) — 인덱스 첫 컬럼 실제 도메인 사용.
- 호스트 변수 인덱스 수집 walker 13200, 13213-13215 (`PT_HOST_VAR_IDX_INFO`, 서브쿼리 결과 캐시).

---

## 4. 서버 실행 — **행마다 지불하는 비용**

### 4.1 ★ 최대 핫스팟: `fetch_peek_dbval()` 인라인 fast-path 차단

`src/query/fetch.h:56-96` 인라인 진입점: `REGU_VARIABLE_FAST_PEEK`이면 `TYPE_POS_VALUE`는 `vd->dbval_ptr + val_pos`(71-73) 즉시 반환, 아니면 `fetch_peek_dbval_slow`.

플래그를 세우는 유일한 곳 — `src/query/fetch.c:5264-5277`: 조건에 `TP_DOMAIN_TYPE (regu_var->domain) != DB_TYPE_VARIABLE`(5273) 포함. 바로 위 5222-5228:
```c
if (*peek_dbval != NULL && !DB_IS_NULL (*peek_dbval))
  if (TP_DOMAIN_TYPE (regu_var->domain) == DB_TYPE_VARIABLE || TP_DOMAIN_COLLATION_FLAG (...) != TP_DOMAIN_COLL_NORMAL)
    regu_var->domain = tp_domain_resolve_value (*peek_dbval, NULL);
```
**동작:**
- 바인딩 값이 non-NULL이면 첫 fetch에서 해소 → 이후 fast-path. 비용 1회/실행.
- 바인딩 값이 **NULL이면** 도메인이 영원히 VARIABLE → **FAST_PEEK가 절대 안 서고 모든 행이 `fetch_peek_dbval_slow()` + 대형 switch**.
- **XASL 클론 디캐시마다 원복** — `query_executor.c:1519` `regu_var->domain = regu_var->original_domain;`(VARIABLE로), `1536` `REGU_VARIABLE_CLEAR_FLAG (FAST_PEEK)`. → **실행마다 첫 행은 무조건 slow path.** 짧은 결과셋 고빈도 OLTP prepared statement에서 전부 지불.
- `fetch_peek_dbval_slow`의 `TYPE_POS_VALUE` 분기 — `fetch.c:4745-4757`.

### 4.2 ★ 술어 평가: `eval_value_rel_cmp()` — 행마다 타입 비교

`query_evaluator.c:2150-2186` `eval_pred_comp0()`(`eval_fnc`가 2630에서 선택) — 매 행 lhs/rhs fetch 후 `eval_value_rel_cmp`(152-266):
- `REGU_VARIABLE_FETCH_ALL_CONST`(219) 검사 → `vtype1 != vtype2`(223) **행마다**; 불일치면 `REGU_VARIABLE_CLEAR_AT_CLONE_DECACHE` 시 private heap 스왑(229) + 3패턴(numeric←char → DOUBLE 243, date←char 249, numeric 승격 256) `tp_value_coerce` in-place.
- 3패턴 외(`INTEGER col = ?(DATE)`, `CHAR col = ?(INT)`)는 **매 행 `tp_value_compare_with_error`(276)의 느린 강제변환**.

`tp_value_compare_with_error` — `object_domain.c:10419~`; 10474-10476 / 10519-10560: `vtype1 != vtype2 && !ARE_COMPARABLE` → temp DB_VALUE 2개 + `tp_value_coerce`(문자열이면 private heap 할당) + 정리, **행마다**.

다른 행 단위 호출: `query_evaluator.c:370, 501, 603, 741, 754, 836, 978, 1154`(집합/리스트 술어), `1965`(`eval_pred` T_COMP), `2065`(ALSM), `2186`.

### 4.3 ★ 산술: `fetch_peek_arith()` — 행마다 도메인 탈착/재해석

`fetch.c:1314-1319`: VARIABLE이면 `original_domain = regu_var->domain; regu_var->domain = NULL;`(qdata_*에 NULL 전달). 계산 후 `fetch.c:4465-4477`: `tp_domain_resolve_value (arithptr->value)`로 `regu_var->domain = arithptr->domain = resolved_dom`. 에러 경로 4601-4605 원복. `original_domain`은 `arith_list_node` 별도 필드(`regu_var.hpp:130-131`)로 클론 디캐시마다 복원 → `c1 + ?`(`pt_is_op_hv_late_bind(PT_PLUS)`)는 **매 실행의 매 행** 이 분기를 통과.

도메인 NULL의 `qdata_add_dbval` — `query_opfunc.c:2438-2560`: 값에서 type1/type2 읽기, ENUM 캐스팅, `PRM_ID_PLUS_AS_CONCAT` 검사, 스왑, `tp_domain_resolve_default(DOUBLE/BIGINT)` + `tp_value_auto_cast` — **행마다**. `qdata_subtract/multiply_dbval` 동형. `fetch.c:863-866`에도 행마다 VARIABLE 검사(`T_STRCAT`/`T_ADD` empty-string).

### 4.4 REGUVAL_LIST (VALUES 질의) — `fetch.c:5236-5241` 매 행 `tp_domain_resolve_value`, 5242-5258 head regu와 타입/collation 호환성 검사 매 행.

### 4.5 리스트 파일 / 튜플 디스크립터 — 해소될 때까지 매 튜플

`query_executor.c:991-997` `is_domain_resolved == false`면 `qfile_update_domains_on_type_list`(`list_file.c:7045-7096`): regu 도메인이 VARIABLE이면 `is_domain_resolved = false`로 되돌려 **다음 튜플에 재시도** → 끝까지 VARIABLE이면(`SELECT ? FROM t` NULL 바인딩) **모든 튜플마다 valptr 전체 순회**. 관련 `list_file.c:910-922`(병합), `4505-4512`(정렬 `sort_f` 선택).

### 4.6 집계 / 분석 함수
- `query_aggregate.cpp:3307-3310` — interpolation 값마다 `agg_p->domain` VARIABLE 검사·해소.
- `query_analytic.cpp:51-59` fast-path 게이트 `opr_dbtype != DB_TYPE_VARIABLE`; 188-191, 255, 284, 428, 696-768 VARIABLE 분기.
- `query_executor.c:1355-1381` buildvalue 집계 결과 도메인 해소(그룹 단위); `21192, 21251, 21276, 21318-21341, 21404, 21439, 21556, 21593-21624, 21780, 27786` group-by/agg/sort 도메인 해소(스캔 시작 또는 그룹 단위). `qexec_resolve_domains_for_aggregation`(21411~).

### 4.7 리스트 스캔의 "HV late binding" 해소
`scan_manager.c:8206-8299` `resolve_domains_on_list_scan()`(주석 8213 "used in context of HV late binding"): `TYPE_POSITION` regu의 VARIABLE 도메인과 `et_comp.lhs/rhs`(8286-8297, `resolve_domain_on_regu_operand` 8318~) 해소. **스캔 오픈 단위**(중첩 루프 조인은 outer 행마다).

### 4.8 인덱스 키 레인지 — 스캔 오픈(= 중첩 루프 outer 행)마다
`scan_manager.c:2670-2699` `curr_keyno == -1`에서 `scan_regu_key_to_index_key`(2328-2470): 단일 컬럼 키는 `fetch_copy_dbval`만(2399-2415, 2447-2463; 인덱스 도메인 강제변환 없음). MIDXKEY는 `scan_dbvals_to_midxkey`(1873~)에서 `tp_value_coerce_strict`(2021), `tp_domain_resolve_value`(2035, 2097), `btree_coerce_key`(2273). `btree_coerce_key` — `btree.c:18053`, 비-MIDXKEY 18236-18272(`tp_more_general_type` → `tp_value_coerce` / `tp_value_coerce_strict`).

**키 비교는 노드/키마다** — `btree.c:22100-22121`: 3중 `TP_ARE_COMPARABLE_KEY_TYPES` + 문자열 collation 검사 → 통과 시 `key_domain->type->cmpval`, 아니면 `tp_value_compare_with_error`. 호스트 변수 키가 인덱스 도메인으로 안 맞춰져 있으면 **모든 키 비교가 일반 비교 경로**.

키 리밋 강제변환 `scan_manager.c:1189-1215`(→ BIGINT), 호출 `scan_init_index_key_limit`(3553, 3887, 4944) 스캔 오픈 단위.

### 4.9 호스트 변수 배열이 서버까지 오는 길
```
qmgr_execute_query (network_interface_cl.c:7313) → or_pack_db_value 루프 (7348-7352)  ← 값의 실제 타입 패킹
  → xqmgr_execute_query (query_manager.c:1304) → or_unpack_db_value (1437) / dbvals_p (1427-1441)
    → qmgr_process_query (1583) → qexec_execute_query (1237)
      → xasl_state.vd.dbval_cnt / dbval_ptr (query_executor.c:17578-17579)
```
`val_descr`: `query_executor.h:77-78`. 병렬 복제 `xasl_spawner.cpp:895-906`, `query_executor.c:3692-3732`. 서브쿼리 결과 캐시 키 `query_executor.c:28970`.

**즉 `regu->domain`(컴파일 타임, 캐시된 XASL)과 `vd->dbval_ptr[i]`(런타임, 드라이버 타입)가 독립적으로 도착하며, 둘의 불일치를 매 행 재확인하는 것이 현재 구조다.**

---

## 5. 이미 존재하는 "실행 전 도메인 고정" 시도들

| 위치 | 하는 일 | 한계 |
|---|---|---|
| `parse_dbi.c:3092-3155` `pt_set_host_variables` | `host_var_expected_domains[i]`로 `tp_value_cast_preserve_domain` | UNKNOWN이면 `pr_clone_value` 우회(3129-3132) |
| `db_vdb.c:3205-3251` `do_cast_host_variables_to_expected_domain` | 세션 전체 캐스팅, `set_host_var = 1` | UNKNOWN/ENUM `continue`(3223-3227) |
| `db_vdb.c:1082-1096` | subsession prepared에서 XASL 생성 **전** 캐스팅 | `is_subsession_for_prepared`만 |
| `type_checking.c:8608-8618` `pt_preset_hostvar` | expected_domain → 전역 배열 + data_type 동기화 | 호출되는 곳에서만 |
| `type_checking.c:23839-23893` | `data_type`을 `expected_domain`과 일치 | `data_type == NULL`이면 no-op |
| `xasl_generation.c:6465-6491` | prepare 시 슬롯 `db_value_domain_init(exptyp)` | VARIABLE이면 무의미 |
| `scan_manager.c:8206-8299` `resolve_domains_on_list_scan` | 리스트 스캔 regu VARIABLE 해소 | 스캔 오픈 단위, 리스트 스캔 한정 |
| `fetch.c:5222-5227`, `4465-4477`, `5236-5241` | 첫 값에서 `tp_domain_resolve_value` | 클론 디캐시마다 원복(`query_executor.c:1519`) |
| `list_file.c:7045-7096` | 리스트 타입 도메인 해소 | 실패 시 매 튜플 재시도 |
| `db_vdb.c:2228-2273`, `3597-3660`, `3752-3770` | 바인드 값 기반 플랜 replan | 값 기반, 타입 기반 아님 |
| `name_resolution.c:3838-3851` `pt_bind_values_to_hostvars` | `?`를 상수로 치환 후 재-type | XASL 캐시 OFF 전용(`db_vdb.c:2343`) |
| `PRM_ID_HOSTVAR_LATE_BINDING` | `system_parameter.c:1795-1796`, `type_checking.c:19714` | 노드를 PT_VALUE로 접을지만 제어 |
| `PRM_ID_HOSTVAR_PEEKING` | `type_checking.c:17875-17876`, `parser_support.c:10265` | 값 peeking(상수 폴딩/LIKE), 도메인 고정 아님 |

---

## 6. 설계가 손대야 할 파일 / 함수 목록

**A. 도메인 추론 확대 (prepare 시점)** — `type_checking.c` `pt_eval_expr_type` 9555-9607, 9673-9727, 9748-9860, `pt_coerce_expression_argument` 4653-4694, `pt_is_op_hv_late_bind` 20525-20571, `pt_preset_hostvar` 8608, `pt_set_expected_domain` 8626; `semantic_check.c` `pt_assignment_compatible` 13375-13463, 15477-15486; `name_resolution.c` 1059, 11908; `func_type.cpp` 990-992.

**B. 바인드 타입 ↔ prepare 연결(참고)** — `cas_execute.c` 622, 1025-1082, 3289, 3881, 3483-3532; `db_vdb.c` 1901, 1548, 1650; `parse_dbi.c` 3092; `db_query.c` 418, 461, 546, 631-639, 721-723(`host_var_expected_domains` 이미 패킹됨 — 재사용 가능); `db_query.h:158`.

**C. 플랜 캐시 키 / 재컴파일(참고; 지도 D-C3로 시그니처 분기는 기각)** — `execute_statement.c` 108, 9927-9944, 11309-11325, 11970-11986, 15266-15285, 18318-18333; `parse_tree_cl.c:3099-3120`; `parse_tree.h:957, 3972`; `xasl_cache.c` 872, 675-810; `parser_support.c` 10254, 10298.

**D. XASL 생성** — `xasl_generation.c` `pt_make_regu_hostvar` 6390-6502, `pt_xasl_type_enum_to_domain` 2250, `pt_to_pred_expr` 1548-1558, `pt_make_pred_term_comp` 1334, sort spec 5889-5916, key_info `is_constant` 10593/10715/10986/11237; `parse_dbi.c` 2420, 1529; `xasl_to_stream.c:5376-5382` / `stream_to_xasl.c:6843-6845`.

**E. 서버 실행 핫스팟(제거 대상)** — `fetch.h:56-96`, `fetch.c:5264-5277, 5222-5227, 5236-5241, 4465-4477, 1314-1319, 863-866, 4745-4757`; `query_evaluator.c:152-266, 2150-2186, 2590-2656`; `object_domain.c:10419-10560, 3147, 5729`; `query_executor.c:1519, 1536, 991-997`; `list_file.c:7045-7096, 4505-4512, 910-922`; `query_opfunc.c:2438-2560` 및 형제 `qdata_*`; `scan_manager.c:8206-8299, 2328-2470, 1873-2280`; `btree.c:22100-22121, 18053-18272`; `regu_var.hpp:174, 178-204`; `query_aggregate.cpp:3307`; `query_analytic.cpp:51-59, 188-191`.

---

## 7. 결론: "도메인을 실행 전에 못 박으면 사라지는 행 단위 검사" (구체 목록)

1. `fetch.c:5273` — `TYPE_POS_VALUE`가 **첫 행부터** 인라인 fast-path(`fetch.h:71-73`) → 함수 호출 + 대형 switch 제거(특히 NULL 바인딩과 **모든 클론 디캐시 후 첫 행**).
2. `fetch.c:5222-5227` `tp_domain_resolve_value` — 실행마다 1회, 클론 재사용 빈도만큼 반복.
3. `query_evaluator.c:219-262` `vtype1 != vtype2` 분기 + `tp_value_coerce` + private-heap 스왑 — 타입 동일 보장 시 전 블록 제거.
4. `object_domain.c:10474-10560` `tp_value_compare_with_error`의 temp DB_VALUE 강제변환 — **행마다 힙 할당 가능**. 도메인 고정 시 `ARE_COMPARABLE` 즉시 통과.
5. `fetch.c:1316-1319` + `4465-4477` — 산술 regu 도메인 탈착/재해석, **매 행**.
6. `query_opfunc.c:2438~` `qdata_*` — `domain_p == NULL`로 매 행 값 기반 타입 결정.
7. `fetch.c:5236-5258` — REGUVAL_LIST 매 행 도메인 해소 + 호환성 검사.
8. `list_file.c:7045-7096` — 해소 실패 시 매 튜플 valptr 전체 순회.
9. `btree.c:22100-22121` — 매 키 비교의 3중 `TP_ARE_COMPARABLE_KEY_TYPES` + 불일치 시 일반 비교 폴백.
10. `query_executor.c:1519, 1536` — 클론 디캐시마다 `domain = original_domain`(VARIABLE 원복) + FAST_PEEK 클리어. 도메인이 확정이면 원복 자체가 불필요.

### 리드 주석(지도 결정과의 대조)
- 서브에이전트가 제안한 "바인드 타입 시그니처를 플랜 캐시 키(`PT_PRINT_HOST_VAR_COUNT` 자리)에 넣기"는 지도 D-C3(시그니처 분기 기각)로 채택하지 않는다. 채택 방향은 컴파일 시 `pt_make_regu_hostvar`가 VARIABLE을 만들지 않게 하는 것(§7 마지막 항 (c))과, 진짜 추론 불가만 XASL에 기록해 execute 직전 확정하는 것이다.
- §4.1의 "NULL 바인딩이면 영원히 VARIABLE"과 §4.5의 "매 튜플 재시도"는 컴파일 확정이 없으면 execute 직전 확정으로도 해결되지 않는(값이 NULL이라 바인드 도메인도 없는) 케이스라, 설계 티켓(#272)에서 "NULL 바인드의 도메인 = 기대 도메인 또는 NULL 도메인 고정" 규칙을 명시해야 한다.
