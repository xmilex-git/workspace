# 컴파일 측 호스트 변수 도메인 추론 인벤토리 + 진짜 추론 불가 케이스 분류

- 지도: xmilex-git/workspace#268, 티켓 #270 (연구: 컴파일 측 호스트 변수 도메인 추론 인벤토리)
- 기준: `/home/cubrid/dev/cubrid` 브랜치 `develop`, HEAD `a60c1b9c0` (2026-09-16), 코드 읽기 전용
- 선행: `docs/research/hv-domain-late-binding-exec-sites.md` (#269, 이하 "실행 보고서"). 그 §1(파서)·§3(XASL)은 반복하지 않고 **정정·보강**만 적는다. 실행 측 비용은 그 보고서 §4·§7을 참조.
- 방법: 코드 판독만. 호스트에 `cub_server pr7866fusion2`(다른 티켓의 PR 브랜치 빌드)만 떠 있어 develop 바이너리 실측은 하지 않았다. 코드 판독으로 확정되지 않는 항목은 표에 **[실측 필요]** 로 표시했고, §7 에 탐침(#275)용 csql 스크립트 초안을 붙였다.

---

## 0. 한 줄 요약

`?` 의 기대 도메인(expected domain)은 **세 갈래**에서 결정된다. (1) **시그니처 경로** — `pt_apply_expressions_definition` → `pt_coerce_expr_arguments` → `pt_coerce_expression_argument` 가 짝 인자 타입을 "미러링"해 `tp_domain_resolve_default_w_coll()` 의 **기본 정밀도** 도메인을 준다(컬럼 정밀도·스케일은 안 실림, collation 은 `pt_check_expr_collation` 이 나중에 맞춤). (2) **시그니처 없는 연산자 전용 레거시 경로**(`type_checking.c:9555-9868`) — `PT_CAST`, `PT_ASSIGN`, `PT_IF`, `PT_CASE/DECODE`, `PT_RANGE`, `PT_STR_TO_DATE`, `PT_DATE_ADD/SUB` 등에서만 도달하며, `pt_node_to_db_domain(짝)` 으로 **정밀도까지 포함한** 도메인을 준다. (3) **문장 단위 경로** — INSERT/MERGE 값 리스트(`type_checking.c:8059-8079`, `7932-7953`), `pt_assignment_compatible`(`semantic_check.c:13375-13463`), LIMIT(`xasl_generation.c:11576/11589`), 집합 캐스트(`type_checking.c:8427`), collation 강제(`21644`, `22072`).

**`pt_is_op_hv_late_bind` 연산군은 세 갈래 모두에서 의도적으로 빠져나간다.** `PT_PLUS/PT_MINUS` 는 MAYBE 인자가 있으면 시그니처 적용 자체를 건너뛰고(`type_checking.c:9008-9012`, `9065-9068` → `cannot_use_signature:` 10473), 나머지는 `pt_get_equivalent_type_with_op`(20500)·`pt_infer_common_type`(4828/4869)·`pt_common_type_op`(11291)·`5999` 네 관문이 MAYBE 를 그대로 통과시킨다. 그 결과 `? + 1` 의 `?` 조차 **기대 도메인 없이**(`host_var_expected_domains[i] == UNKNOWN`) 서버로 가고, 식 자체는 `xasl_generation.c:7883` 에서 `DB_TYPE_VARIABLE` 로 XASL 에 박힌다.

**진짜 추론 불가**(바인드 값의 타입을 알아야 답이 정해지는 것)는 다음 셋뿐이다: (a) 짝이 없는 맨 `?`(`SELECT ?`, `? IS NULL`, `WHERE ?`), (b) 양쪽 MAYBE(`? = ?`, `? + ?`, `nvl(?, ?)`), (c) `pt_is_op_hv_late_bind` 연산군에서 **결과 타입이 피연산자 타입의 함수**인 것(`? + 1` 의 INT/DOUBLE/DATE/문자열 연결). 나머지는 모두 컴파일에서 못 박을 규칙이 이미 있거나(현행), 짝 컬럼/시그니처로부터 못 박을 수 있다(정밀도·collation 규칙만 정리하면 됨).

---

## 1. `pt_eval_expr_type` 의 실제 제어 흐름 (실행 보고서 §1.4 정정)

실행 보고서는 `WHERE col = ?` 를 "경로 A: 9555 대칭 연산자 처리" 로 설명했는데, **9555 는 시그니처가 없는 연산자에서만 도달한다.** 근거:

```c
/* type_checking.c:9280-9284 */
if (pt_apply_expressions_definition (parser, &expr) != NO_ERROR) { ... goto error; }
...
/* 9313-9318 */
if (expr != NULL)
  {
    expr = pt_wrap_expr_w_exp_dom_cast (parser, expr);
    node = expr; expr = NULL;
    switch (op) { /* BETWEEN/LIKE 되돌리기, EXTRACT, TIMEDIFF, FROM_TZ ... */ }
    goto error;                                   /* 9552 — 9555 이하로 내려가지 않음 */
  }
if (pt_is_symmetric_op (op))                      /* 9555 — expr == NULL 일 때만 */
```

`pt_apply_expressions_definition`(type_checking.c) 은 `pt_get_expression_definition(op, &def)` 이 실패하면 `*node = NULL` 을 남기고 `NO_ERROR` 를 돌려준다(함수 머리 +17~+20행). 정의가 없는 연산자 = 9870 이하 `switch (op)` 에 케이스가 있는 것들(`PT_IF` 9863, `PT_ASSIGN` 10003, `PT_RANGE` 10043, `PT_STR_TO_DATE` 10060, `PT_DATE_ADD/SUB` 10140, `PT_CAST` 10269, `PT_CASE/DECODE` 10343, `PT_CONNECT_BY_ROOT` 9998 등). `PT_EQ`(정의 3100), `PT_IS_IN`(3695), `PT_LIKE`(617), `PT_BETWEEN`(590), `PT_IS_NULL`(3532), `PT_NVL`(NVL/IFNULL/COALESCE 정의), `PT_PLUS`(1608) 는 모두 정의가 있다.

세 번째 갈래: `PT_PLUS`/`PT_MINUS` 에 MAYBE 인자가 있으면

```c
/* type_checking.c:9008-9012 (PT_MINUS 는 9065-9068 동형) */
if (arg1_type == PT_TYPE_MAYBE || arg2_type == PT_TYPE_MAYBE)
  {
    node->type_enum = PT_TYPE_MAYBE;
    goto cannot_use_signature;        /* 10473: pt_wrap_expr_w_exp_dom_cast 만 하고 error: 로 */
  }
```

즉 **9555-9868 의 레거시 블록(9563 미러, 9685 `a IN (?, ...)`, 9748 MAYBE 잔여 처리)은 시그니처 있는 연산자에는 전부 죽은 코드**다. 이 사실이 §5 표의 (a) 열을 결정한다.

`pt_is_symmetric_op`(6234-6438) 는 **부정 목록**이다: 나열된 연산자(`PT_IS_IN`, `PT_IS_NULL`, `PT_NVL`, `PT_TO_CHAR`, `PT_CAST`, `PT_INST_NUM`, `PT_ADDTIME`, `PT_FROM_TZ` …)만 `false`, 나머지는 `default: return true`(6437-6438). 따라서 `PT_EQ`, `PT_LIKE`, `PT_BETWEEN`, `PT_PLUS` 는 대칭 연산자다.

---

## 2. `expected_domain` 설정 지점 전수

`SET_EXPECTED_DOMAIN` 매크로(type_checking.c:68-82)와 `pt_set_expected_domain`(8626-8640)은 동일 동작: 노드 자신에 대입하고, `or_next` 체인에서 `type_enum == MAYBE && expected_domain == NULL` 인 멤버에만 같은 도메인을 채운다(먼저 쓴 도메인이 남는 first-writer-wins). `pt_preset_hostvar`(8608-8618)는 `pt_hv_consistent_data_type_with_domain`(23839; `data_type` 이 있을 때만 정합) 후 `host_var_expected_domains[index]` 에 기록한다 — auto-param(`index >= host_var_count`)은 기록하지 않는다.

`or_next` 는 DNF 멤버(`PT_EXPR`)와 RANGE 리스트(`PT_BETWEEN_*`, query_rewrite_term.c:2650-2680)에만 걸리며 최적화기(`pt_cnf`/`qo_convert_to_range`) 단계에서 만들어진다. 따라서 매크로의 `or_next` 전파는 (i) 호스트 변수 자체가 DNF 멤버인 `WHERE ? OR ...` 같은 드문 경우, (ii) `mq_translate` 뒤 `pt_semantic_type` 재실행 시 이미 체인이 있는 노드에만 작용한다. `col1 = ? OR col2 = ?` 의 두 `?` 는 서로 다른 노드이고 각자의 `PT_EQ` 안에서 독립적으로 타이핑되므로 **파서 단계 충돌은 없다**(§5 E).

| # | 위치 (type_checking.c 외는 파일 명시) | 함수 | 조건 | 추론 근원 | 도메인 내용 (정밀도/스케일/collation) |
|---|---|---|---|---|---|
| 1 | 4689/4694 | `pt_coerce_expression_argument` | 인자 MAYBE, **late-bind 연산자·서브쿼리가 아님**(4655-4656) | 시그니처 등가 타입 `def_type`(= `pt_get_equivalent_type`; GENERIC NUMBER→DOUBLE, CHAR/STRING→VARCHAR, DATE→DATETIME, DISCRETE→BIGINT, ANY→MAYBE(=no-op), func_type.cpp:2745-2830) | `new_dt` 가 있으면 `pt_data_type_to_db_domain(new_dt)`(ENUM 짝만, 4628-4636), 없으면 `tp_domain_resolve_default_w_coll(type, LANG_SYS_COLLATION, TP_DOMAIN_COLL_LEAVE)`(4676-4680) — **기본 정밀도**(VARCHAR=floating, NUMERIC=(38,0) `tp_Numeric_domain` object_domain.c:308, dbtype_def.h:622/631), collation 은 LEAVE(뒤에 #12 가 확정). 호출자 `pt_coerce_expr_arguments`(5390-5700)는 `arg1_dt/arg2_dt/arg3_dt` 를 항상 NULL 로 넘긴다(5398-5400, 이후 대입 없음). |
| 1' | 4655-4664 | 〃 | 인자 MAYBE 이고 late-bind 식 또는 `PT_SELECT` 서브쿼리 | 〃 | **도메인을 주지 않고 CAST 로 감싼다**; `node->expected_domain = NULL` 로 리셋 → XASL 에서 VARIABLE |
| 2 | 5360-5361 | `pt_coerce_range_expr_arguments` | `col IN ?`(arg2 자체가 HV) | 고정 | `tp_domain_resolve_default(DB_TYPE_SET)` — 원소 도메인 없음 |
| 3 | 7949-7950 | `pt_eval_type` post `PT_MERGE` | `set_host_var == 0`, 값 리스트 HV 이고 expected 아직 NULL | `merge.insert.attr_list` 컬럼 | `pt_node_to_db_domain(attr)` — **컬럼 정밀도·스케일·collation 전부** |
| 4 | 8075-8076 | `pt_eval_type` post `PT_INSERT` | 〃 | `insert.attr_list` 컬럼 | 〃 |
| 5 | 8427 | `pt_wrap_collection_with_cast_op` | 집합 원소 HV MAYBE, `for_collation == false` | 캐스트 대상 원소 타입 `set_data` | `pt_data_type_to_db_domain(set_data)`(정밀도 포함; 호출자 5290-5345 가 원소들 최대 정밀도 계산) |
| 6 | 9571-9573 / 9581-9582 / 9594-9596 / 9604-9605 | `pt_eval_expr_type` 레거시 대칭 미러 | **시그니처 없는** 대칭 연산자, 한쪽 HV·다른쪽 확정 | 짝 인자 `type_enum` | `pt_coerce_value(hv, 짝 type, 짝 data_type)` 로 HV `type_enum/data_type` 을 덮어쓴 뒤 `pt_xasl_type_enum_to_domain(type_enum)` — **type_enum 만**(정밀도 기본) |
| 7 | 9684-9687 / 9705-9708 / 9721-9724 | 〃 비대칭·IN 리스트 | 시그니처 없는 비대칭 연산자(`!PT_DOES_FUNCTION_HAVE_DIFFERENT_ARGS`), arg2/arg3 MAYBE 이고 arg1 numeric/string; `a IN (?, ...)` | arg1 | `pt_node_to_db_domain(arg1)`(정밀도 포함) / IN 원소는 `pt_xasl_type_enum_to_domain` | — **`PT_IS_IN` 은 정의가 있어 여기 도달 못함(죽은 코드)** |
| 8 | 9760-9763 / 9797-9800 / 9812-9815 / 9849-9852 | 〃 MAYBE 잔여 | 시그니처 없고 결과 MAYBE, `!DIFFERENT_ARGS`; `node->expected_domain` 이 numeric/string 이거나 짝이 numeric/string | 부모 기대 도메인 또는 짝 | 부모 도메인 그대로 / `pt_node_to_db_domain(짝)` |
| 9 | 9867-9868 | 〃 `PT_IF` | arg1(조건) MAYBE | 고정 | `tp_domain_resolve_default(DB_TYPE_STRING)` — 조건이 STRING 으로 못 박힘 |
| 10 | 10008-10009 | 〃 `PT_ASSIGN` | arg2 HV, expected NULL | lhs 컬럼 | `pt_node_to_db_domain(arg1)` — 컬럼 정밀도·collation 전부 |
| 11 | 10080-10081 / 10103-10104 | 〃 `PT_STR_TO_DATE` | arg1/arg2 MAYBE | 고정 | VARCHAR 기본 |
| 12 | 10152-10153 / 10159-10160 | 〃 `PT_DATE_ADD/SUB` | arg1/arg2 HV MAYBE | 고정 | `DB_TYPE_STRING` 기본(주석: "가장 일반적인 문자열로 가정") |
| 13 | 10333-10334 | 〃 `PT_CAST` | arg1 HV MAYBE | 캐스트 대상 | `pt_node_to_db_domain(node)` — 대상 타입의 정밀도·collation |
| 14 | 21644 | `pt_coerce_node_collation` `PT_HOST_VAR` | MAYBE 이고 expected NULL | 문맥 collation | `tp_domain_resolve_default_w_coll(VARCHAR/collection, coll_id, TP_DOMAIN_COLL_ENFORCE)` — `pt_preset_hostvar` 호출 없음(22012 에서 나중에) |
| 15 | 22012 | 〃 | HV 에 expected 있음 | — | `pt_preset_hostvar` 만(재등록) |
| 16 | 22072-22073 | 〃 `PT_FUNCTION` 인자 루프 | 인자 HV; expected 있으면 collation 불일치 때만 | 공통 collation | 기존 도메인 복제 후 `codeset/collation_id`, `collation_flag = NORMAL` 덮어씀(22040-22061); 없으면 VARCHAR+ENFORCE |
| 17 | semantic_check.c:13458/13461 | `pt_assignment_compatible` | rhs MAYBE (INSERT 값·UPDATE/ODKU 대입) | 1. `host_var_expected_domains[idx]`(UNKNOWN 아니면 그대로 쓰되 collation 을 lhs 것으로 **덮어씀** 13418-13425 — 캐시 도메인 in-place 수정) 2. `lhs->expected_domain` 3. lhs 기본 도메인(NUMERIC 은 `sci.prec/scale` 반영 13444) + collation 복제 | ENUM lhs 는 `pt_data_type_to_db_domain(lhs->data_type)` |
| 18 | semantic_check.c:15477-15486 | `pt_coerce_insert_values` | HV MAYBE, expected NULL, 컬럼 numeric/string | 컬럼 | `pt_node_to_db_domain(attr)` — `pt_preset_hostvar` 호출 없음(배열 미기록; #4 가 이미 채웠을 것) |
| 19 | xasl_generation.c:11576-11579 / 11589-11592 | `pt_to_index_info` 키 리밋 | LIMIT/키리밋 HV MAYBE | 고정 | `tp_domain_resolve_default(DB_TYPE_BIGINT)` 직접 대입(배열 미기록) |
| 20 | parser_support.c:4798-4825 | `pt_create_param_for_value`(auto-param) | 상수 → HV 치환 | 원본 상수 | `type_enum/data_type/expected_domain` 복사 — 처음부터 확정 |
| 21 | name_resolution.c:11908 | 정적 SQL 슬롯 확장 | — | — | `pt_type_enum_to_db_domain(PT_TYPE_NONE)` = **UNKNOWN 초기값** |

부수 규칙:
- `pt_expr_get_return_type`(type_checking.c) 와 `func_type.cpp:990-992` 는 인자 MAYBE 라도 `expected_domain` 이 있으면 그 타입으로 결과 타입을 계산한다 → **기대 도메인이 있으면 결과 타입 확정이 가능**하다는 뜻(설계에서 재사용 가능).
- `pt_coerce_value_internal` `case PT_HOST_VAR`(19653-19664): `set_host_var == 0` 이면 `type_enum/data_type` 을 덮어쓴다 — #6 경로에서만 쓰이므로 시그니처 경로의 HV 는 **`type_enum` 이 MAYBE 로 남는다**(→ `pt_to_pred_expr` 1548 의 `et_comp->type` 이 `DB_TYPE_NULL`).

---

## 3. `pt_is_op_hv_late_bind` 연산군 — 컴파일 관문과 런타임 결과 타입 규칙

### 3.1 컴파일 측 네 관문 + XASL 한 관문

| 위치 | 동작 |
|---|---|
| type_checking.c:20500-20504 `pt_get_equivalent_type_with_op` | GENERIC 시그니처 + MAYBE 인자 → 등가 타입을 MAYBE 로 둠(일반 연산자는 DOUBLE/VARCHAR 등으로 확정) |
| 4826-4844 `pt_infer_common_type` | 공통 타입 MAYBE 일 때 `!pt_is_op_hv_late_bind` 이면 짝 타입 미러 — late-bind 는 미러 안 함; 4869 부모 기대 도메인도 무시 |
| 11291-11294 `pt_common_type_op` | late-bind + 한쪽 MAYBE → 결과 MAYBE |
| 5999-6003 `pt_apply_expressions_definition` | late-bind + 인자 MAYBE → `expr->type_enum = PT_TYPE_MAYBE` (시그니처 반환 타입 무시) |
| 4655-4664 `pt_coerce_expression_argument` | late-bind **식**이 인자로 쓰이면 기대 도메인 대신 CAST 랩 |
| 20586-20622 `pt_wrap_expr_w_exp_dom_cast` | late-bind 식이 MAYBE 인데 부모가 기대 도메인을 줬으면 CAST 랩 후 `expected_domain = NULL` |
| xasl_generation.c:7881-7889 / 8025-8033 / 8136-8144 | `type_enum == MAYBE` 이고 late-bind 면 `pt_xasl_node_to_domain(node)` → `pt_type_enum_to_db(MAYBE)` = **`DB_TYPE_VARIABLE`**(parse_dbi.c:2420); 비-late-bind MAYBE 는 `node->expected_domain` 사용(7941 은 `assert(false)`) |
| 7932-7945 (단항 -,+ 등), 8079-8087 (`PT_LAST_DAY` 등), 8097 (`PT_ADDDATE/SUBDATE`), 8219-8227 (`PT_IF`) | MAYBE 면 `node->expected_domain`(NULL 가능) |

또 하나: `pt_evaluate_db_value_expr`(13848-13858, 상수 폴딩)는 `typ == DB_TYPE_VARIABLE && late-bind` 일 때 **실제 값 타입으로 결과 타입을 계산**한다 — `pt_common_type(typ1, typ2)` 후 문자열이면 DOUBLE(단, `PLUS && PRM_ID_PLUS_AS_CONCAT` 은 유지). 이것이 컴파일 측에 이미 존재하는 "런타임 규칙의 미러" 이며, execute 직전 확정 규칙의 출발점으로 쓸 수 있다.

### 3.2 연산자별 런타임 규칙과 컴파일 규칙 요구

`fetch_peek_arith`(fetch.c:1314-1319)는 regu 도메인이 VARIABLE 이면 `regu_var->domain = NULL` 로 떼고 `qdata_*` 에 넘긴 뒤 결과 값에서 `tp_domain_resolve_value` 로 되붙인다(4465-4477). 아래 "런타임 규칙" 은 `domain_p == NULL` 일 때의 규칙이다.

| 연산자(군) | 런타임 결과 타입 규칙 (인용) | 컴파일에서 같은 답을 내려면 | **바인드 타입 의존** |
|---|---|---|---|
| `PT_PLUS`(T_ADD) | `qdata_add_dbval` query_opfunc.c:2438-2660: ENUM→SMALLINT/VARCHAR(2456-2495); `PRM_ID_PLUS_AS_CONCAT` 이고 양쪽 CHAR/BIT → `qdata_strcat_dbval`(2498-2504); 문자+숫자 → 스왑 후 문자열을 DOUBLE 로(2520-2536); 날짜+부동/문자 → BIGINT 로 캐스트해 날짜 산술(2538-2542); 문자+문자 → DOUBLE+DOUBLE(2544-2549); 이후 `type1` 디스패치 — INT+INT→INT(오버플로는 **에러**, `qdata_add_int` 757-770, 승격 없음), INT+BIGINT→BIGINT, ×+DOUBLE→DOUBLE, NUMERIC→NUMERIC, DATE+INT→DATE …; `ORACLE_STYLE_EMPTY_STRING` 이면 regu 도메인이 문자열일 때 T_STRCAT 로 취급(fetch.c:1327-1336) | 두 피연산자 타입 → `pt_common_type`(10618) + 13848 의 문자열→DOUBLE/concat 보정 + 날짜+수 규칙(8997-9058 에 이미 있음). 정밀도: INT/BIGINT/DOUBLE 은 고정, NUMERIC 은 `qdata_add_numeric` 결과 정밀도(값 의존 아님, (p,s) 함수), 문자열 연결은 길이 합 | **예** — `? + 1` 은 INT/DOUBLE/DATE/VARCHAR 네 갈래 |
| `PT_MINUS`(T_SUB) | `qdata_subtract_dbval` 4818-: ENUM→SMALLINT, 숫자-문자 → DOUBLE, 날짜-날짜 → BIGINT, 날짜-수 → 날짜 | 〃 (시그니처 1660-1700 에 DATE-DATE→BIGINT 등이 이미 있음) | 예 |
| `PT_TIMES`(T_MUL) | `qdata_multiply_dbval` 5512-: 문자 피연산자는 DOUBLE 로 | 〃 | 예 |
| `PT_DIVIDE`(T_DIV) | `qdata_divide_dbval` 6134-6190: 문자→DOUBLE; `PRM_ID_ORACLE_COMPAT_NUMBER_BEHAVIOR` 이면 정수/정수 → NUMERIC | `pt_common_type_op` 의 DIVIDE 분기(11300 이하 `oracle_compat_number`) 가 이미 같은 규칙 | 예 |
| `PT_MODULUS`(T_MOD) | `db_mod_dbval`(fetch.c:1463) — 피연산자 타입 그대로 | `DIFFERENT_ARGS` 그룹(parse_tree.h:425) — 인자 타입 그대로 | 예 |
| `PT_UNARY_MINUS`(T_UNMINUS) | `qdata_unary_minus_dbval` 6291-: 피연산자 타입 유지(INT_MIN 은 에러) | 인자 타입 = 결과 타입 | 예(단순 전달) |
| `PT_ABS/CEIL/FLOOR/ROUND/TRUNC` | `db_abs_dbval`/`db_floor_dbval`/`db_ceil_dbval`/`db_round_dbval`(fetch.c:1470-1510, 1691-1735) — 인자 타입 유지(ROUND/TRUNC 두 번째 인자는 정수/문자열 포맷) | 인자 타입 = 결과 타입 | 예(단순 전달) |
| `PT_IFNULL/NVL/COALESCE`(T_NVL 3283-3323), `PT_NVL2`(3324-), `PT_NULLIF`(3859-), `PT_LEAST/GREATEST`(3909-) | `regu_var->domain == NULL` 이면 `tp_domain_resolve_value` 두 값 → **`tp_infer_common_domain`**(object_domain.c:11480-11560: 같은 타입 → 그대로, 한쪽 NULL → 다른 쪽, 같은 계열(문자/비트/날짜/집합/숫자) → `tp_more_general_type`, 그 외 → **VARCHAR**; 정밀도는 MAX(p1,p2), NUMERIC 은 기본(38,0), floating 이 하나라도 있으면 floating) 후 `tp_value_cast` | 두 인자 타입 → `tp_infer_common_domain` 과 동일 규칙을 파서 타입으로. 시그니처(NVL: STRING/STRING→STRING, STRING/ANY→VARCHAR)는 런타임과 **다른 답**(INT,INT → 런타임 INT / 시그니처 VARCHAR) | **예**(한쪽이 상수여도 `?` 타입이 다른 계열이면 VARCHAR 폴백) |
| `PT_TO_CHAR`(T_TO_CHAR 2845) | `db_to_char(..., arithptr->domain)` — 결과는 항상 문자열; 첫 인자 타입에 따라 숫자/날짜 포맷 분기 | 결과 VARCHAR 고정(`pt_is_able_to_determine_return_type` 8648 에 이미 포함) — 인자 타입만 미확정 | 결과 아님, **인자 해석만** 의존 |
| `PT_TO_DATE/TO_TIME/TO_TIMESTAMP/TO_DATETIME(_TZ)/TO_TIMESTAMP_TZ` | 결과 타입은 연산자가 결정(T_TO_DATE 2938 등) | 결과 고정, 인자는 VARCHAR 가정 가능 | 아니오 |
| `PT_STR_TO_DATE`(T_STR_TO_DATE 2634) | `db_str_to_date(..., regu_var->domain)` — 포맷 문자열이 상수면 컴파일에서 DATE/TIME/DATETIME 결정(type_checking.c:10108-10139), 포맷이 `?` 면 MAYBE | 포맷이 `?` 인 경우만 불가(값 의존) | 포맷이 `?` 일 때 **값**(타입이 아니라 내용) 의존 |
| `PT_HEX/CONV/ASCII` | `db_hex`/`db_conv`/`db_ascii`(1982-2010) — 결과 VARCHAR/INT 고정 | 결과 고정 | 아니오 |
| `PT_BIT_LENGTH/OCTET_LENGTH/HOURF/MINUTEF/SECONDF` | 결과 INTEGER 고정(시그니처 1690-1705 도 INTEGER) | 결과 고정 | 아니오 |
| `PT_ADDTIME`(T_ADDTIME 2495) | `db_add_time(..., regu_var->domain)` — 첫 인자 타입(TIME/DATETIME/문자열)에 따라 결과 | 인자 타입 함수 | 예 |
| `PT_FROM_TZ/NEW_TIME` | 인자 DATETIME→DATETIMETZ 등(type_checking.c:9546-9549) | 인자 타입 함수 | 예 |
| `PT_EVALUATE_VARIABLE/DEFINE_VARIABLE` | 세션 변수 값 타입(fetch.c:4565: NOT_CONST) | **불가** — 세션 상태 의존 | 값 의존(바인드가 아니라 세션) |

요약: 연산군 39개 중 **결과 타입이 정말 피연산자 타입의 함수인 것**은 산술 6(`+ - * / % 단항-`), 전달형 5(`ABS CEIL FLOOR ROUND TRUNC`), 공통도메인형 7(`IFNULL NVL NVL2 COALESCE NULLIF LEAST GREATEST`), 시간형 3(`ADDTIME FROM_TZ NEW_TIME`), 세션 변수 2. 나머지 16개는 결과 타입이 고정이라 **연산군에 남아 있을 이유가 없다**(인자 `?` 에 시그니처 등가 타입을 기대 도메인으로 주면 끝).

---

## 4. XASL 생성 — VARIABLE 이 만들어지는 정확한 조건 (실행 보고서 §3 보강)

`pt_make_regu_hostvar`(xasl_generation.c:6390-6502) 4단 폴백은 실행 보고서 §3.2 대로다. 보강:

1. 1단 `node->data_type` 은 시그니처 경로에서는 **NULL** 이다(`pt_coerce_expression_argument` 는 `type_enum/data_type` 을 건드리지 않음). 레거시 미러(#6)·auto-param(#20)·`pt_hv_consistent_data_type_with_domain`(data_type 이 이미 있을 때만)에서만 채워진다. 따라서 대부분의 `?` 는 3단 `expected_domain` 으로 도메인을 얻는다.
2. 2단(바인드 값 타입)은 `set_host_var == 1 || typ != DB_TYPE_NULL` — CAS PREPARE(값 없음)에서는 건너뛴다. csql 처럼 값이 먼저 바인딩되는 경우에만 작동.
3. 4단 `pt_xasl_type_enum_to_domain(type_enum)`: MAYBE → VARIABLE; **LOGICAL → INTEGER**(parse_dbi.c:2319-2321) — `CASE WHEN ? THEN` 의 조건 `?` 가 여기 해당(§5 L).
4. 6465-6475: 값이 아직 없으면 `db_value_domain_init(val, exptyp, ...)` 로 슬롯을 선-초기화 — 이 슬롯이 `parser->host_variables[i]` 이고, 이후 `pt_set_host_variables` 가 덮어쓴다.

식 노드: §3.1 표의 7881/8025/8136 규칙. `pt_to_pred_expr`(1548-1558)는 양쪽 `type_enum` 이 같을 때만 `et_comp->type` 을 채우므로 `col = ?`(INTEGER vs MAYBE)는 `DB_TYPE_NULL`, `? = ?`(MAYBE vs MAYBE)는 `DB_TYPE_VARIABLE` — 현재 실행기가 소비하지 않는다(실행 보고서 §3.4).

정렬 스펙(5885-5930): `ORDER BY ?`/`GROUP BY ?` 는 도메인이 VARIABLE 인 HV 면 `MSGCAT_SEMANTIC_NO_ORDERBY_ALLOWED`; 시맨틱 단계에서도 `semantic_check.c:14831-14835` 가 먼저 거부한다.

LIMIT(11565-11600): 키 리밋 HV MAYBE → `expected_domain = BIGINT` 직접 대입; 일반 LIMIT 은 `pt_limit_to_numbering_expr`(parser_support.c:4570-)가 `inst_num()/orderby_num() <= ?`(PT_LE, 4620-4628)로 바꾸고, `PT_INST_NUM/ORDERBY_NUM` 시그니처 반환 BIGINT(type_checking.c:2586-2595)와의 미러로 `?` 가 BIGINT 를 받는다.

---

## 5. 케이스 분류표 (주 산출물)

열 설명 — (a) 오늘 파서가 `?` 와 그 식에 무엇을 추론하는가, (b) XASL `regu->domain`, (c) 컴파일 규칙으로 못 박을 수 있는가(어떤 규칙) / **진짜 추론 불가**인가(execute 직전 확정 규칙), (d) 못 박았을 때 답 변경 위험. "실행 직전" = 바인드 값 도착 후 스캔 전 1회(지도 D-C3).

| # | 케이스 | (a) 파서 추론 | (b) XASL regu 도메인 | (c) 컴파일 확정 가능? / 규칙 | (d) 답 변경 위험 |
|---|---|---|---|---|---|
| A | `SELECT ?` (짝 없는 맨 HV) | 없음. `PT_HOST_VAR` MAYBE(8151), expected NULL, 배열 UNKNOWN. 결과 컬럼 타입도 VARIABLE(`db_query` 컬럼 목록·CAS 마커 `CCI_PARAM_MODE_UNKNOWN`) | 4단 → **VARIABLE**; `SELECT ? FROM t` 는 리스트 파일 도메인 재시도(실행 보고서 §4.5) | **진짜 추론 불가**(문맥 없음). 실행 직전: `domain := tp_domain_resolve_value(bind)`; NULL 바인드는 T 규칙 | 없음(값 그대로). 클라이언트에 알려주는 결과 컬럼 타입이 실행마다 달라지는 것은 현행과 동일 |
| B | `? + ?` | `PT_PLUS` MAYBE 바이패스(9008-9012) → 식 MAYBE, 두 `?` 모두 expected NULL | 식 7883 → VARIABLE, HV 둘 다 VARIABLE | **진짜 추론 불가**. 실행 직전: 두 바인드 타입 → §3.2 PLUS 규칙(13848 미러)으로 결과 도메인 + 피연산자 캐스트 도메인 확정 | 규칙을 `qdata_add_dbval` 과 동일하게 두면 없음. 오버플로 동작(INT+INT 에러)도 유지해야 함 |
| C | `? + 1`, `col + ?` | 동일 바이패스. **`?` 에 기대 도메인 없음**(9748 블록은 도달 불가) → 배열 UNKNOWN, 바인드 값 원형 전달 | 식 VARIABLE, HV VARIABLE | 컴파일 규칙 후보 R-ARITH: `?` ← 짝 타입(INT) 미러 후 결과 = `pt_common_type`. **그러나 이는 답을 바꾼다**(아래). 지도 D-C4 를 적용해 "타입 규칙에 맞는 변경" 으로 채택할지 결정 필요. 대안: `?` 는 미확정으로 두고 실행 직전 B 규칙 | **있음**: 오늘 `'1.5' + 1 = 2.5`(DOUBLE), `'2024-01-01'(DATE 바인드) + 1 = DATE`, `PLUS_AS_CONCAT` 시 `'a' + 'b'`; INT 로 못 박으면 `'1.5'`→2, 3 이 되고 DATE 바인드는 캐스트 에러. `SELECT ? + 1` 의 결과 컬럼 타입도 INT 로 고정됨 |
| D | `? = ?` | `PT_EQ` 시그니처 경로: 양쪽 등가 MAYBE, `pt_infer_common_type` 미러 불가 → 인자 그대로(4575 `def_type == type_enum` 조기 반환), 식 LOGICAL | HV 둘 VARIABLE; `et_comp->type = VARIABLE`(1548) | **진짜 추론 불가**. 실행 직전: 두 바인드 타입 → 비교 도메인 규칙(`eval_value_rel_cmp` query_evaluator.c:219-262 의 3패턴 — 숫자·문자→DOUBLE, 날짜·문자→날짜, 숫자 승격 — 을 그대로) 후 두 HV 를 그 도메인으로 1회 캐스트 | 3패턴 외 조합(INT vs DATE)은 오늘 `tp_value_compare_with_error` 폴백 — 같은 규칙을 쓰면 없음 |
| E | `col1 = ? OR col2 = ?` (컬럼 도메인 다름) | 각 `PT_EQ` 독립 처리: `?1` ← INTEGER 기본, `?2` ← VARCHAR(floating)+col2 collation(22040-22075). `type_enum` 은 MAYBE 유지. `or_next` 는 최적화기에서 `PT_EQ` 노드끼리 걸리므로 HV 간 충돌 없음; RANGE 변환(query_rewrite_term.c:2650-2680) 때 `parser_copy_tree` 가 expected 를 복사 | HV 각각 확정 도메인(3단) | **이미 컴파일 확정**. 남는 문제는 정밀도(NUMERIC 컬럼이면 `?` ← NUMERIC(38,0) — [실측 필요] `tp_value_cast_preserve_domain` 이 스케일을 자르는지) | 없음(현행). NUMERIC 정밀도 규칙을 컬럼 것으로 바꾸면 스케일 보존 쪽으로 **개선** 가능 |
| F | `? IN (1, 2)` (HV 가 왼쪽) | `pt_coerce_range_expr_arguments`(5100-5230): 원소 공통 INTEGER, `pt_common_type_op(MAYBE, IN, INTEGER)` = **DOUBLE**(10645-10649 "numeric & MAYBE → DOUBLE") → `?` ← DOUBLE 기본; 집합은 캐스트 안 함(5223 "numeric & numeric → return"). [실측 필요] | HV DOUBLE; 집합 INTEGER | 컴파일 확정(현행) 이지만 규칙이 거칠다. 개선 규칙 R-IN-L: `?` ← 집합 원소 공통 타입(INTEGER) | 현행 DOUBLE 은 BIGINT 큰 값 정밀도 손실 위험; INTEGER 로 바꾸면 `'1.0'` 바인드가 DOUBLE 1.0 IN (1,2)=참 → INTEGER 1 IN (1,2)=참(동일), `'1.5'` 는 DOUBLE 거짓 → INTEGER 2 참 (**변경**) |
| G | `col IN (?, ?)` | `F_SET` 의 `data_type` 은 `pt_add_type_to_set`(parse_dbi.c) 이 MAYBE 원소를 건너뛰어 NULL → `pt_get_common_collection_type` NONE → 5223 `return expr` — **원소 `?` 에 기대 도메인 없음**(레거시 9685 는 죽은 코드). [실측 필요 — 실행 보고서 §1.4 경로 D 와 상충] | 원소 HV VARIABLE; 인덱스 키면 `btree_coerce_key` 런타임 변환(실행 보고서 §4.8) | 컴파일 확정 가능 — 규칙 R-IN-R: 원소 `?` ← `col` 도메인(E 와 동일 규칙; `pt_wrap_collection_with_cast_op` 8427 경로를 타게 하거나 원소를 직접 순회) | 없음(`col = ?` 와 같은 캐스트 의미). 인덱스 키 변환 생략의 전제 조건(D-C5) |
| H1 | 함수 인자 `?` — 고정 시그니처(`PT_FUNCTION`, func_type.cpp) | MAYBE 는 castable(648-651) → `arg_res.m_type = pt_get_equivalent_type(sig, MAYBE)`(NORMAL→그 타입, NUMBER→DOUBLE, STRING→VARCHAR, DATE→DATETIME) → `apply_argument` 743: **CAST 랩**(기대 도메인 아님) | HV VARIABLE 이 `T_CAST(대상)` 안에; 함수 결과 도메인은 확정 | 컴파일 확정 가능 — 규칙 R-FUNC: CAST 랩 대신 `?` ← 등가 타입 기대 도메인(+ `pt_preset_hostvar`) | 없음(CAST 와 바인드 시 캐스트는 같은 `tp_value_cast`). 단 CAST 실패가 실행 에러 → 바인드 에러로 시점만 이동 |
| H2 | 함수 인자 `?` — GENERIC ANY / `PT_TYPE_MAYBE` 시그니처(`F_SET` 원소, `MEDIAN/PERCENTILE`(1958-1961), `PT_DOES_FUNCTION_HAVE_DIFFERENT_ARGS` 연산자 `MODULUS SUBSTRING LPAD RPAD ADD_MONTHS TO_CHAR TO_NUMBER POWER ROUND TRUNC INSTR LEAST GREATEST FIELD…`) | 등가 타입 MAYBE → 무변경; `DIFFERENT_ARGS` 는 9748-9752 에서 "인자 건드리지 않음" | HV VARIABLE; 함수 결과 MAYBE→VARIABLE(집계는 `qexec_resolve_domains_for_aggregation`) | 시그니처가 인자 타입을 규정하지 않는 것 — 인자별 규칙 필요: 자리별 고정 타입(`SUBSTRING` 2·3번째 INTEGER, `ROUND` 2번째 INTEGER…)은 컴파일 확정 가능; 값 자리(`LEAST(?, ?)`, `MEDIAN(?)`)는 **진짜 추론 불가** → 실행 직전 `tp_infer_common_domain` | 자리별 고정은 없음; 값 자리는 §3.2 공통도메인형과 동일 |
| I | `LIMIT ?` / `OFFSET ?` / 키 리밋 | 리라이트 `inst_num()/orderby_num() <= ?`(PT_LE) 미러 → `?` ← BIGINT 기본; 키 리밋은 11576/11589 BIGINT 직접; `count(*) … LIMIT ?` 는 파생 테이블로(semantic_check.c:14727-14758) | BIGINT | **이미 컴파일 확정** | 없음 |
| J | `INSERT … VALUES (?)` | #4(8075, 컬럼 전체 도메인) → #17 `pt_assignment_compatible`(배열 도메인 우선, collation 을 lhs 로 덮어씀) → #18 보정. 순서: `pt_semantic_check_local PT_INSERT` 가 `pt_semantic_type` 뒤 `pt_coerce_insert_values`(11330-11336) | 컬럼 도메인(정밀도·collation 포함) | **이미 컴파일 확정** | 없음. 주의: #17 13421-13424 가 **캐시된 도메인 객체를 in-place 수정**(`d->codeset/collation_id`)— 설계에서 제거 대상 부작용 |
| K | `UPDATE … SET col = ?` | #10 `PT_ASSIGN`(컬럼 전체 도메인) + `pt_check_assignments`→#17 | 컬럼 도메인 | **이미 컴파일 확정** | 없음 |
| L1 | `CASE WHEN ? THEN a ELSE b` (조건 `?`) | 10345: `pt_coerce_value(arg3, LOGICAL)` → HV `type_enum = LOGICAL`, **expected NULL, 배열 UNKNOWN**(preset 없음) | 4단 `LOGICAL → INTEGER` 도메인; 바인드 값은 원형 → 도메인/값 불일치를 실행기가 흡수 | 컴파일 확정 가능 — 규칙: `?` ← INTEGER(LOGICAL) 기대 도메인 + preset. `PT_IF` 조건(9863-9868)은 STRING 을 주고 있어 **둘을 통일**해야 함 | 문자열 `'true'` 바인드 등 경계 사례 변경 가능(현재도 정의 안 된 동작) |
| L2 | `CASE … THEN ? ELSE 1` / `CASE ? WHEN 1 …`(값 자리·단순 CASE 피비교자) | 10360-10377: 공통 타입 = 다른 분기 타입, 양쪽 MAYBE 면 **VARCHAR 기본**; `pt_coerce_expression_argument` 로 `?` ← 공통 타입(CASE 는 late-bind 아님). 단순 CASE 는 파서가 `PT_EQ` 비교로 풂 → E 규칙 | 확정 | **이미 컴파일 확정**(양쪽 MAYBE 는 VARCHAR 고정 규칙) | 없음 |
| M | `NVL(?, 0)`, `IFNULL/COALESCE(?, c)` | late-bind: 등가 MAYBE, 미러 없음, 식 MAYBE(5999). `?` expected NULL(4575 조기 반환), 배열 UNKNOWN. 부모가 기대 도메인을 주면(`INSERT … VALUES (NVL(?,0))`) 식만 CAST 랩(20586) | 식 7883 VARIABLE, HV VARIABLE; T_NVL 이 `tp_infer_common_domain(값1, 값2)` 로 매 행 | 컴파일 규칙 후보 R-COMMON: `?` ← 짝 상수 타입(INTEGER), 결과 INTEGER. **답 변경** 있음(아래). 대안: 실행 직전 `tp_infer_common_domain(bind, 상수)` 규칙을 그대로 | `NVL('abc', 0)` 오늘 → `tp_infer_common_domain(VARCHAR, INT)` = VARCHAR → `'abc'`; INT 로 못 박으면 캐스트 에러. `NVL(?, 0)` 에 `1.5` 바인드: 오늘 DOUBLE 1.5, 못 박으면 2 |
| N | `? IS NULL` | `PT_IS_NULL` 시그니처 ANY → 등가 MAYBE, 대칭 미러 짝 없음(arg2 NULL) → `?` 무변경 | HV VARIABLE; 술어는 `DB_IS_NULL` 만 봄 | **타입 무관**. 실행 직전 `domain := bind 도메인`(A 와 같은 규칙)으로 충분 | 없음 |
| O | `col LIKE ?` (+ `ESCAPE ?`) | 시그니처 GENERIC CHAR → 등가 VARCHAR → `?` ← VARCHAR(floating, LEAVE) → `pt_check_expr_collation` 이 col collation 으로(22040-22075). `qo_rewrite_like_terms` 가 `like_lower_bound(?)`/`upper_bound(?)` 범위를 만들고 결과 타입은 `arg1->expected_domain`(9130-9136) | VARCHAR + col collation | **이미 컴파일 확정** | 없음 |
| P | `col BETWEEN ? AND ?` | 대칭 미러 → `?` 둘 ← col 타입 기본 도메인; 5470-5490 의 "비-EQ 는 DOUBLE" 규칙은 `PT_VALUE` 인자에만 적용(HV 제외) | col 타입 기본 도메인 | **이미 컴파일 확정**(정밀도 규칙은 E 와 같은 이슈) | 없음 |
| Q | 상관 서브쿼리 안의 `?` (`… WHERE t2.c = ?`, `col = (SELECT ? …)`) | 서브쿼리 내부 식마다 위 규칙 동일. `(SELECT ? …)` 가 식 인자면 `PT_SELECT is_subquery` 분기(4656)로 CAST 랩 | 내부 규칙에 따름; 상관 실행은 outer 행마다 서브 XASL 재실행 → 실행 보고서 §4.7 리스트 스캔 재해소가 outer 행마다 | 케이스별로 위 규칙 적용. "실행 직전 1회" 는 서브쿼리에도 성립(바인드 값은 outer 행과 무관) | 없음 |
| R | `ORDER BY ?` / `GROUP BY ?` | 거부(semantic_check.c:14831, xasl_generation.c:5927; 윈도우 5908) | — | 설계 범위 밖(거부 유지) | — |
| S | `CAST(? AS T)` | #13: `?` ← 대상 도메인(정밀도·collation 포함) + preset | 대상 도메인; T_CAST 는 사실상 no-op | **이미 컴파일 확정** | 없음 |
| T | NULL 바인드 | 파서는 관여 없음(PREPARE 에 값 없음). `pt_set_host_variables`: 기대 도메인이 있으면 `tp_value_cast_preserve_domain`(preserve=true, object_domain.c:10110-10122 "dest 도메인 타입을 DB_NULL_TYPE 로 바꾸지 않음") → **도메인 타입을 가진 NULL**; UNKNOWN 이면 `pr_clone_value` → `DB_TYPE_NULL` | 확정 HV: 도메인 있음 → FAST_PEEK 가능. 미확정 HV: VARIABLE + NULL 값 → 영원히 미해소(실행 보고서 §4.1) | 확정된 HV 는 문제 없음. 미확정(A/B/D/M/N)+NULL 은 **실행 직전에도 바인드 도메인이 없음** → 규칙 필요: `domain := tp_Null_domain`(DB_TYPE_NULL) 로 고정하고 소비자(`fetch_peek_dbval` 5222, `qfile_update_domains_on_type_list`, 집계 도메인 해소)가 DB_TYPE_NULL 을 "확정" 으로 받도록 | 없음(NULL 의미론 불변). `SELECT ?` NULL 바인드의 결과 컬럼 타입은 오늘도 미정 |

분류 집계:
- **이미 컴파일 확정(현행)** — E, I, J, K, L2, O, P, S (+F 는 확정이나 규칙 개선 여지)
- **컴파일 확정 가능, 규칙 추가 필요(답 변경 없음)** — G(R-IN-R), H1(R-FUNC), H2 자리별 고정, L1, N(타입 무관)
- **컴파일 확정 가능하지만 답이 바뀜(D-C4 판단)** — C(R-ARITH), M(R-COMMON), F(R-IN-L)
- **진짜 추론 불가 → XASL 기록 후 실행 직전 확정** — A, B, D, H2 값 자리, (C·M 을 못 박지 않기로 하면 그것들도)
- **실행 직전에도 도메인이 없는 특수** — T(NULL 바인드) → DB_TYPE_NULL 고정 규칙

---

## 6. `pt_set_host_variables` 캐스트 규칙과 클라이언트→서버 기대 도메인 전달

### 6.1 `pt_set_host_variables` (parse_dbi.c:3072-3158)

```c
hv_dom = parser->host_var_expected_domains[i];
if (TP_DOMAIN_TYPE (hv_dom) == DB_TYPE_UNKNOWN || hv_dom->type->id == DB_TYPE_ENUMERATION)
  pr_clone_value (val, hv);                                   /* 3129-3132: 그대로 */
else
  {
    DB_TYPE val_type = db_value_type (val);
    if (tp_value_cast_preserve_domain (val, hv, hv_dom, false, true) != DOMAIN_COMPATIBLE)  /* 3137 */
      { PT_ERRORmf2 (... MSGCAT_SEMANTIC_CANT_COERCE_TO, "host var", ...); return; }
    if (TP_IS_CHAR_TYPE (hv_dom->type->id))
      if (hv_dom->type->id != val_type && (val_type == DB_TYPE_VARCHAR))
        pr_clone_value (val, hv);                              /* 3144-3149: CHAR 기대 + VARCHAR 값 → 캐스트 결과를 버리고 원형 복제 */
  }
parser->flag.set_host_var = 1;
```

- **UNKNOWN 예외**: 기대 도메인이 없으면 드라이버 타입 그대로 — §5 의 A/B/C/D/M/N/G/H2/L1 이 여기 해당.
- **ENUM 예외**: ENUM 컬럼 대입/비교의 `?` 는 캐스트하지 않고 값을 넘긴다(서버 `qdata_*`/비교가 ENUM↔문자열/정수 변환을 맡음; `pt_value_to_db` 1170-1173 이 ENUM 기대 시 `data_type` 재계산).
- **CHAR 계열 복제**: 기대 CHAR(n)·값 VARCHAR 면 **패딩 회피**를 위해 캐스트를 되돌린다 — 즉 `char_col = ?` 의 바인드 값은 VARCHAR 로 남고 regu 도메인은 CHAR → 실행기 `eval_value_rel_cmp` 에서 문자 계열은 `ARE_COMPARABLE` 로 통과하지만 **도메인/값 타입 불일치가 의도적으로 유지되는 지점**이다(설계에서 CHAR 도메인 확정 시 패딩 의미론을 어떻게 할지 결정 필요). `pt_value_to_db`(1147-1150)도 같은 예외(CHAR/VARCHAR, BIT/VARBIT).
- `tp_value_cast_preserve_domain`(object_domain.c:10110-10122) = `tp_value_cast_internal(..., TP_EXPLICIT_COERCION, true, preserve_domain=true)`: NULL 값도 dest 도메인 타입을 유지 → §5 T 의 "도메인 있는 NULL".
- 세션 프리페어(`PREPARE s FROM …; EXECUTE s USING …`) 경로는 `do_cast_host_variables_to_expected_domain`(db_vdb.c:3205-3251) 이 같은 규칙(UNKNOWN/ENUM `continue`, CHAR 복제 대신 `db_value_domain_init(hv, typ, prec, 0)`)을 적용하며 **XASL 생성 전**(db_vdb.c:1082-1096) 에 호출되어 `pt_make_regu_hostvar` 2단(바인드 값 타입)이 작동한다.

### 6.2 기대 도메인이 어디로 전달되는가

| 경로 | 내용 |
|---|---|
| CAS/JDBC PREPARE 응답 | `db_marker_domain`(db_vdb.c:1650-1665) = `marker->expected_domain`(없으면 `pt_node_to_db_domain`) → 드라이버에 파라미터 타입 힌트. UNKNOWN 이면 `CCI_PARAM_MODE_UNKNOWN`. 서버로 가는 것이 아니라 **클라이언트 쪽 힌트**. |
| 세션 프리페어드 스테이트먼트(`PREPARE` 문) | `db_get_prepare_info`/`db_pack_prepare_info`(db_query.c:436-560): `host_variables.vals` 전부 + **`host_var_expected_domains[0 .. size - auto_param_count)`** 를 `or_pack_domain(ptr, dom, 0, 0)` 으로 직렬화(461, 546) → 서버 세션 저장(`csession_create_prepared_statement`) → `EXECUTE` 때 `db_unpack_prepare_info`(631-639) 로 복원해 `parser->host_var_expected_domains` 에 꽂는다(db_vdb.c:3106-3116). 즉 **기대 도메인의 직렬화 포맷·코드는 이미 존재**한다(재사용 가능). auto-param 분은 값이 이미 확정이라 도메인을 싸지 않음. |
| 일반 실행(CAS `ux_execute` → `db_push_values`) | 기대 도메인은 서버로 가지 않는다. 클라이언트 `pt_set_host_variables` 가 캐스트한 **값**만 `or_pack_db_value` 로(network_interface_cl.c:7348-7352) 가고, 도메인은 XASL(`xts_process_regu_variable`, xasl_to_stream.c:5376-5382)에 실린 `regu->domain` 만이다. 따라서 "실행 직전 확정" 을 서버에서 하려면 (i) XASL 에 미확정 HV 목록(인덱스 + 확정 규칙 종류)을 실어 두고 (ii) `xqmgr_execute_query` 가 받은 `dbvals_p` 타입으로 확정해야 하며, 기대 도메인 자체를 서버로 보낼 필요는 없다(값이 이미 캐스트돼 있음). |

---

## 7. 탐침(#275)용 실측 항목 초안

코드 판독으로 확정하지 못한 세 항목. develop 빌드의 csql 세션 프리페어(`PREPARE … EXECUTE … USING`)는 `db_compile_statement` 를 값 없이 태우므로 CAS 와 같은 추론 경로다.

```sql
-- F: ? IN (1,2) 의 ? 가 DOUBLE 로 잡히는가 (BIGINT 큰 값 정밀도)
PREPARE p1 FROM 'SELECT ? IN (9007199254740993, 1)';
EXECUTE p1 USING 9007199254740993;           -- DOUBLE 이면 정밀도 손실로 1(참) 가능성

-- G: col IN (?, ?) 의 ? 가 기대 도메인 없이 가는가 → 문자열 바인드로 관찰
CREATE TABLE t (i INT); INSERT INTO t VALUES (1), (2);
PREPARE p2 FROM 'SELECT * FROM t WHERE i IN (?, ?)';
EXECUTE p2 USING '1', '2';                   -- 기대 도메인 없으면 서버 비교 규칙(문자→DOUBLE)로 참
EXECUTE p2 USING '1.5', '2';                 -- INT 로 못 박혔다면 2 도 매치될 것

-- E/P: NUMERIC 컬럼 비교 ? 의 스케일 보존
CREATE TABLE n (v NUMERIC(10,2)); INSERT INTO n VALUES (1.25);
PREPARE p3 FROM 'SELECT * FROM n WHERE v = ?';
EXECUTE p3 USING 1.25;                       -- NUMERIC(38,0) 로 잘리면 결과 0행
```

서버가 필요하면 `cubrid-server-control` 스킬과 `just port-claim` 으로 전용 인스턴스를 띄운다(다른 티켓의 `pr7866fusion2` 는 쓰지 않는다).

---

## 8. 설계 입력 요약 — #271 이 결정해야 할 것 (우선순위순)

1. **D-C4 적용 범위: C(`? + 1`)·M(`NVL(?, c)`)·F(`? IN (…)`) 를 컴파일에서 못 박을 것인가.** 세 케이스는 못 박으면 답이 바뀐다(§5 (d)). 못 박으면 `pt_is_op_hv_late_bind` 연산군 대부분이 사라지고 실행 직전 확정 대상은 A/B/D/H2 값 자리만 남는다. 못 박지 않으면 실행 직전 확정기가 §3.2 규칙(산술·공통도메인·시간형) 전부를 구현해야 한다. 권고: 결과 타입 고정인 16개 연산자는 연산군에서 즉시 제외(답 변경 없음), 나머지 23개는 이 결정에 따름.
2. **실행 직전 확정 규칙 명세** — 진짜 추론 불가 케이스(A, B, D, H2 값 자리, 그리고 1 에서 남긴 것)에 대해: 입력 = 바인드 값 도메인 벡터, 출력 = HV 도메인·식 결과 도메인·비교 도메인. 재사용할 기존 규칙: `pt_evaluate_db_value_expr` 13848(산술), `tp_infer_common_domain`(공통도메인형), `eval_value_rel_cmp` 3패턴(비교). 서버에서 하려면 XASL 에 "미확정 HV 인덱스 + 규칙 ID" 를 실어야 한다(§6.2).
3. **NULL 바인드 규칙(T)** — 미확정 HV 에 NULL 이 오면 `DB_TYPE_NULL` 도메인으로 고정하고 모든 소비자가 이를 확정으로 취급. 확정 HV 는 `tp_value_cast_preserve_domain` 덕에 이미 도메인 있는 NULL 이다.
4. **정밀도·스케일·collation 규칙 통일** — 시그니처 경로(#1)는 기본 정밀도(NUMERIC(38,0), VARCHAR floating), 레거시·문장 경로(#3,#4,#10,#13,#17)는 컬럼 정밀도를 준다. `col = ?` 의 `?` 에 컬럼 도메인을 주는 단일 규칙("짝이 컬럼이면 컬럼 도메인, 아니면 기본 도메인")으로 통일할지, NUMERIC 스케일 절단 여부([실측 필요])와 함께 결정. 인덱스 키 변환 생략(D-C5)은 `?` 도메인 == 인덱스 컬럼 도메인일 때만 성립하므로 이 결정에 종속.
5. **`col IN (?, ?)` (G) 와 함수 인자 CAST 랩(H1) 을 기대 도메인 방식으로 전환** — 답 변경 없이 VARIABLE 을 없애는 가장 큰 두 덩어리. G 는 인덱스 키 범위 변환 생략의 전제.
6. **CHAR 계열 복제 예외(§6.1)의 처리** — CHAR(n) 기대 도메인에 VARCHAR 값을 그대로 두는 현행을 유지하면 "확정 도메인 == 값 타입" 불변식이 깨진다. 유지(비교기가 문자 계열을 comparable 로 봄)할지, VARCHAR 로 기대 도메인을 낮출지 결정.
7. **`CASE WHEN ?`(L1)·`IF(?, …)` 조건 HV 규칙 통일**(INTEGER vs STRING) 및 `pt_assignment_compatible` 의 캐시 도메인 in-place 수정(13421-13424) 제거.
8. **죽은 코드 정리 범위** — 9555-9868 레거시 블록 중 시그니처 있는 연산자용 부분(9685 `a IN (?, ...)`, 9748 MAYBE 잔여의 대부분)은 도달 불가. 늦은 바인딩 제거 PR 에서 함께 걷어낼지, 별도 커밋으로 분리할지(가역성).
9. **CAS 마커 타입 힌트 영향** — 컴파일 확정이 늘면 `db_marker_domain` 이 드라이버에 돌려주는 타입이 UNKNOWN 에서 구체 타입으로 바뀐다(JDBC `getParameterMetaData`). 호환성 검토 항목.
