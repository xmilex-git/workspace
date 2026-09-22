# 클라이언트 파서의 타입·도메인·collation 결정 규칙 — 전수 인벤토리

지도: xmilex-git/workspace#312 · 티켓: #313 · 작성 2026-09-22 · 기준: CUBRID/cubrid `develop` `cad27172b`
짝 티켓: #321(서버 측 coerce·산술·비교·집계·키 변환 규칙) — 이 문서는 **클라이언트 파서(prepare 시점)** 만 다룬다.
경험치 렛저(`domain-pin-lessons.md`) 대응은 맨 끝 §7 표에 있다.

인용 표기: `tc:NNNN` = `src/parser/type_checking.c`, `fc:NNNN` = `src/parser/func_type.cpp`, `xg:NNNN` = `src/parser/xasl_generation.c`,
`sc:NNNN` = `src/parser/semantic_check.c`, `pd:NNNN` = `src/parser/parse_dbi.c`, `ps:NNNN` = `src/parser/parser_support.c`,
`ap:NNNN` = `src/optimizer/rewriter/query_rewrite_auto_parameterize.c`, `mc:NNNN` = `src/method/method_callback.cpp`,
`vdb:NNNN` = `src/compat/db_vdb.c`, `nr:NNNN` = `src/parser/name_resolution.c`.

---

## 0. 한 장 요약 — 파서가 타입을 정하는 파이프라인

```
pt_semantic_type (tc:19337)
  └ parser_walk_tree(pre=pt_eval_type_pre tc:7213, post=pt_eval_type tc:7850)   ← 잎부터 후위 순회
       PT_HOST_VAR(IN, type NONE) → PT_TYPE_MAYBE                                  tc:8125
       PT_EXPR  → pt_eval_expr_type (tc:8852)
            ① 연산자별 선처리(PLUS/MINUS/BETWEEN/LIKE/IN/TO_CHAR…)               tc:8960~9200
            ② pt_apply_expressions_definition (tc:5862): 시그니처 표(tc:303~4551)에서 best overload
                 → pt_coerce_expr_arguments (tc:5390) / pt_coerce_range_expr_arguments (tc:4994)
                    → pt_infer_common_type (tc:4799) → pt_common_type_op (tc:11284) → pt_common_type (tc:10618)
                    → pt_coerce_expression_argument (tc:4551): CAST 래핑 또는 expected_domain 부여
                 → 결과 타입 = pt_expr_get_return_type (tc:6038); 늦은 바인딩 연산자면 MAYBE 유지 (tc:5978)
            ③ pt_check_expr_collation (tc:22340)  ← 타입 축과 별개의 collation 축
            ④ 시그니처가 없는 연산자(IF/CASE/DECODE/CAST/ASSIGN/STR_TO_DATE/DATE_ADD…)는 ⑤의 switch 로 직접
            ⑤ 대칭 연산자 짝 미러링(tc:9555~9640) · MAYBE 결과의 expected_domain 하향(tc:9748~9860) · 개별 switch(tc:9861~10515)
            ⑥ pt_upd_domain_info (tc:11423): p/s·collation_flag → data_type
            ⑦ pt_wrap_expr_w_exp_dom_cast (tc:20586): MAYBE 결과 + expected_domain 이면 CAST 래핑
       PT_FUNCTION → pt_eval_function_type (tc:12442) → func_type::Node (fc:868~1345) 또는 구 집계 경로 (fc:1472)
       PT_INSERT/PT_MERGE: VALUES 의 `?` ← 컬럼 도메인 (tc:8020, 7935)
       PT_UNION/PT_CTE/VALUES 다중행: pt_check_union_compatibility (sc:2671) / values query (sc:2766)
  └ 상수 폴딩 (pt_fold_constants_*; static sql 이면 생략)                           tc:19390
optimizer: qo_auto_parameterize (ap:41) — WHERE/HAVING/… 의 리터럴을 auto-param 슬롯으로   (타입 결정 **이후**)
xasl_generation: pt_make_regu_hostvar (xg:6391) — 슬롯 regu 의 도메인 폴백 순서
execute: db_push_values → pt_set_host_variables (pd:3072) — 바인드 값을 expected domain 으로 캐스트(클라이언트 측)
```

핵심 사실 세 가지:

1. **슬롯의 타입은 `expected_domain` 한 필드로만 전달된다**(`PT_NODE.expected_domain` → `parser->host_var_expected_domains[idx]`, tc:8608). 이 값이 NULL 이면 슬롯은 `PT_TYPE_MAYBE` → XASL 에서 `DB_TYPE_VARIABLE` 도메인(pd:2420, xg:6462)으로 남고 실행이 값을 보고 정한다(= 늦은 바인딩).
2. **"늦은 바인딩 연산자" 목록(`pt_is_op_hv_late_bind`, tc:20524)이 규칙의 갈림길이다.** 이 목록의 연산자는 인자가 하나라도 MAYBE 면 결과도 MAYBE 로 두고(tc:11293, tc:5978) 인자에 expected_domain 을 주지 않는다(tc:4830, tc:20498). 산술 `+ - * / MOD`, `ABS/CEIL/FLOOR/ROUND/TRUNC/-x`, 세션변수 `@v` 읽기/쓰기, `TO_CHAR`, `TO_DATE…` 계열, `ADDTIME/FROM_TZ/NEW_TIME/STR_TO_DATE`, `IFNULL/NVL/NVL2/COALESCE/NULLIF/LEAST/GREATEST`, `HEX/CONV/ASCII`, `HOUR/MINUTE/SECOND`, `BIT_LENGTH/OCTET_LENGTH` 가 여기 속한다.
3. **도메인 축과 collation 축은 코드가 다르다.** MAYBE 슬롯의 collation 은 `LANG_SYS_COLLATION`(= 로케일 charset 의 **바이너리** collation, `language_support.h:278`) + `TP_DOMAIN_COLL_LEAVE` 플래그로 시작하고(tc:8570, tc:4672, tc:20893), 문자열 형제가 있으면 `pt_coerce_node_collation` 이 `COLL_ENFORCE` 로 덮는다(tc:21620). 리터럴은 클라이언트 collation(`lang_get_client_collation`, language_support.c:2779)을 받는다. 즉 슬롯의 기본 collation 은 리터럴의 기본 collation 과 **다르다**.

---

## 1. 타입 결정 규칙 (스코프 1)

### 1.1 공통 타입 격자 `pt_common_type` (tc:10618~11274)

두 타입의 공통 타입. 순서대로 적용된다.

| 우선순위 | 조건 | 결과 | 위치 |
|---|---|---|---|
| 1 | 같은 타입 | 그 타입 (단 ENUM×ENUM → **VARCHAR**) | tc:10622 |
| 2 | 숫자 × 문자열(CHAR/VARCHAR/BIT) | **DOUBLE** | tc:10635 |
| 3 | 문자열 × JSON | VARCHAR | tc:10640 |
| 4 | 숫자 × **MAYBE** | **DOUBLE** | tc:10645 |
| 5 | 표(아래) | | tc:10650~11250 |
| 6 | 표에 없음: 한쪽 MAYBE → **MAYBE**; 한쪽 NULL/NA → 다른 쪽 | | tc:11255~11272 |

표(5)의 요지:

- 숫자끼리: SMALLINT < INTEGER < BIGINT < FLOAT < DOUBLE, NUMERIC 은 정수와 만나면 NUMERIC, FLOAT/DOUBLE 과 만나면 DOUBLE, **MONETARY 는 모든 숫자를 이긴다**(tc:10659, 10850). LOGICAL 은 숫자에 흡수(tc:11165).
- 정수 × 날짜/시간 → **날짜/시간 쪽**(tc:10736~10800). TIMESTAMP/TIME/DATE × 정수는 `compat_mode=mysql` 이면 정수 쪽(tc:10935, 11030, 11055).
- 문자열 × 날짜/시간 → **날짜/시간 쪽**(tc:11090, 11110; CHAR/VARCHAR 만, BIT 제외).
- 날짜 계열끼리: DATE < TIMESTAMP < DATETIME, LTZ/TZ 는 TZ 쪽으로 승격(tc:10860~11020).
- CHAR × VARCHAR → **VARCHAR**; CHAR/VARCHAR × ENUM → VARCHAR(tc:11100, 11127).
- BIT × VARBIT → VARBIT. 컬렉션끼리 → **MULTISET**(tc:11150). OBJECT×OBJECT 만 OBJECT.
- ENUM × 숫자/VARCHAR → **상대 타입**(tc:11205): ENUM 은 숫자 문맥에서 서수, 문자 문맥에서 문자열로 취급된다. ENUM × 그 밖 → `pt_common_type(VARCHAR, x)`.

### 1.2 연산자 보정 `pt_common_type_op` (tc:11284~11421)

| 연산자 | 보정 | 위치 |
|---|---|---|
| 늦은 바인딩 연산자 + 한쪽 MAYBE | 결과 **MAYBE**(격자 4 의 DOUBLE 을 무시) | tc:11293 |
| `/` | `oracle_compat_number_behavior=yes` 이고 둘 다 이산 정수면 **NUMERIC** | tc:11304 |
| `-`, `*` | 문자열 × 숫자 → **NONE**(PLUS 와 달리 접합 의미 없음 → 오류) ; SEQUENCE → MULTISET | tc:11315 |
| `IFNULL` | 결과 MAYBE 면 **VARCHAR** — 단 IFNULL 은 비대칭 연산자라 `pt_infer_common_type` 을 타지 않으므로 이 보정은 **사실상 도달하지 않는다**(실제 규칙은 1.5 "결과가 MAYBE 인 노드의 하향 전파") | tc:11330 |
| `COALESCE` | 한쪽 MAYBE → 다른 쪽 타입(둘 다 MAYBE/NULL 이면 MAYBE); 날짜 혼합이면 DATETIME — 위와 같은 이유로 슬롯 결정에는 쓰이지 않고 상수 폴딩·재귀식 경로에서만 | tc:11336 |
| `IN` | MAYBE 면 알려진 쪽 타입 | tc:11373 |
| 논리 결과 + 비논리 연산자 | INTEGER | tc:11398 |
| 비교 + 숫자 × JSON | JSON | tc:11403 |

### 1.3 시그니처 표 `pt_get_expression_definition` (tc:303~4551) 와 적용 (tc:5862)

각 연산자는 `{arg1,arg2,arg3,return}` 오버로드 목록을 갖는다. 인자 타입 종류(`pt_arg_type`)는 NORMAL(구체 타입) 또는 GENERIC. GENERIC 의 "가장 넓은 타입"은 `pt_get_equivalent_type`(fc:2745)이 정한다:

| GENERIC | 동치 판정(fc:1344) | 동치가 아닐 때 강제 타입(fc:2790~2840) |
|---|---|---|
| ANY | 모두 | 인자 타입 그대로(LOGICAL→INTEGER) |
| PRIMITIVE | 원시형 | 인자 타입 |
| NUMBER | 숫자·ENUM | **DOUBLE**(ENUM 은 SMALLINT) |
| DISCRETE_NUMBER | SHORT/INT/BIGINT·ENUM | **BIGINT** |
| STRING / CHAR / STRING_VARYING | 문자열(·ENUM) | **VARCHAR** |
| BIT | BIT/VARBIT | VARBIT |
| DATE / DATETIME | 날짜부 있는 타입 / 날짜시간 | **DATETIME** |
| SCALAR | ENUM·숫자·문자·날짜 | 인자 타입(그 밖 NONE) |
| SEQUENCE / LOB / QUERY / JSON_* | 각 부류 | NONE(캐스트 없음) |

오버로드 선택(tc:5920~5960): 세 인자 모두 동치인 첫 오버로드; 없으면 동치 개수가 최대인 **첫** 오버로드. NULL 리터럴 인자는 `does_op_specially_treat_null_arg`(tc:5815) 연산자가 아니면 결과 NULL(tc:5900).

주요 연산자의 오버로드(모두 tc):

| 연산자 | 오버로드 | 결과 |
|---|---|---|
| `+` (1608) | NUMBER+NUMBER→NUMBER; `plus_as_concat=yes` 면 CHAR+CHAR→**STRING_VARYING**, BIT+BIT→BIT; SEQ+SEQ→SEQ | 날짜+숫자/문자열은 시그니처 전에 선처리(1.5) |
| `-` (1654) | NUMBER-NUMBER; DATE-DATE→**BIGINT**; TIME-TIME→BIGINT; SEQ-SEQ | |
| `*` (1578) | NUMBER*NUMBER; SEQ*SEQ→MULTISET | |
| `/`, `%`(MODULUS) (1558) | NUMBER,NUMBER→NUMBER(1개) | 이산÷이산은 1.2 의 oracle 보정 |
| `DIV`, `MOD` (1538) | DISCRETE,DISCRETE→DISCRETE(1개) | 비이산 인자는 **BIGINT 캐스트** |
| 단항 `-` (3474) | NUMBER→NUMBER | |
| `= <> <=>` (3100) | ANY,ANY→LOGICAL | 캐스트 방향은 1.4 |
| `< <= > >=` (3069) | PRIMITIVE,PRIMITIVE / LOB,LOB → LOGICAL | |
| `BETWEEN` (590) | ANY,ANY,ANY→LOGICAL | |
| `LIKE` (617) | CHAR,CHAR[,CHAR]→LOGICAL | 숫자 인자는 VARCHAR 캐스트 |
| `IN` (3695) | ANY,SET / ANY,QUERY → LOGICAL | 1.6 |
| `IFNULL/NVL/COALESCE` (3120) | STRING×STRING→STRING, STRING×ANY→VARCHAR, BIT×BIT, BIT×ANY→VARCHAR, NUMBER×NUMBER→NUMBER, NUMBER×ANY→**VARCHAR**, DATE×DATE→DATE, DATE×ANY→VARCHAR, TIME×TIME, TIME×ANY→VARCHAR, SEQ×SEQ, SEQ×ANY→VARCHAR, LOB×LOB, LOB×ANY→VARCHAR, ANY×ANY→ANY(15개) | 인자 부류가 다르면 **VARCHAR** 로 수렴 |
| `NULLIF/LEAST/GREATEST` (3266) | ANY,ANY→ANY | 재귀식은 `recursive_type` 로 공통 타입 유지 (tc:5680) |
| `NVL2` (3286) | 위와 같은 패턴 3인자 | |
| `CONCAT/SYS_CONNECT_BY_PATH` (1317), `\|\|`(STRCAT 2133), `CONCAT_WS` | CHAR…→STRING_VARYING | 숫자·날짜 인자는 VARCHAR 캐스트 |
| `TO_CHAR` (3489) | (NUMBER,STRING,STRING) / (DATETIME,STRING,STRING) / (NUMBER,STRING,INTEGER) / (DATETIME,STRING,INTEGER) → VARCHAR | 늦은 바인딩 연산자 → `?` 인자는 MAYBE 로 남김 |
| `TO_NUMBER` (2376) | STRING,STRING,INTEGER→**NUMERIC** | |
| `TO_DATE` (2253), `TO_DATETIME[_TZ]`, `TO_TIME…` | STRING,STRING,{STRING\|INTEGER}→고정 날짜 타입 | 늦은 바인딩 연산자 |
| `ADDTIME` (1013) | 12개 NORMAL 오버로드(DATETIME/LTZ/TZ/TIMESTAMP…×TIME) | 늦은 바인딩 연산자 → MAYBE 인자면 동치 오버로드 없음 → 첫 오버로드 |
| `FROM_TZ` (4404) | (DATETIME 계열,VARCHAR)→같은 계열 / (DATETIME,VARCHAR)→DATETIMETZ | |
| `DATE_FORMAT` (1452) | (STRING\|DATETIME, STRING, INTEGER)→VARCHAR | |
| `LPAD/RPAD` (1843) | CHAR,INTEGER,CHAR→VARCHAR | |
| `HOUR/MINUTE/SECOND` (1810) | STRING_VARYING→INTEGER / TIME→INTEGER | 늦은 바인딩 연산자 |
| `UNIX_TIMESTAMP` (3748) | STRING / DATE / () → INTEGER | |
| `CHR` (698) | NUMBER,INTEGER→VARCHAR | 결과 collation 은 arg2 값(tc:22711) |
| `@v` 읽기 `PT_EVALUATE_VARIABLE` (3945) | CHAR → **MAYBE** | 항상 MAYBE(값을 봐야 함) |
| `@v := x` `PT_DEFINE_VARIABLE` (3961) | (CHAR,STRING) / (CHAR,NUMBER) → **MAYBE** | 쓰기 값의 타입은 노드에 남지만 결과는 MAYBE |

시그니처가 **없는**(직접 처리) 연산자: `IF`(tc:9863), `CASE/DECODE`(tc:10343), `CAST`(tc:10269), `ASSIGN`(tc:10000), `STR_TO_DATE`(tc:10058), `DATE_ADD/SUB`(tc:10146), `EXTRACT`, `FIELD`, `RANGE`, `EXISTS`, `TIMEDIFF` 등.

결과 타입 결정 `pt_expr_get_return_type`(tc:6038): NORMAL 이면 그 타입. GENERIC 이면 **MAYBE 인자에 expected_domain 이 있으면 그 도메인 타입으로 치환한 뒤**(tc:6055~6085) STRING 계열은 문자열 인자들의 `pt_common_type`, NUMBER/ANY/DATE 계열은 대칭 연산자일 때 인자들의 `pt_common_type`, 아니면 arg1 타입.

### 1.4 인자 캐스트 방향 `pt_coerce_expr_arguments` (tc:5390~5760)

1. 대칭 연산자(`pt_is_symmetric_op`, tc:6234~6438 — **예외 목록에 없는 모든 연산자**가 대칭이다. 예외(비대칭) 목록: `IFNULL/NVL/NVL2/COALESCE`, `TO_CHAR/TO_DATE/TO_NUMBER/…`, `ABS/ROUND/TRUNC/CHR`, `ADDTIME/FROM_TZ/NEW_TIME/TO_*_TZ`, `CONCAT/CONCAT_WS`(STRCAT 은 대칭), `CAST`, `TRIM/LPAD/RPAD/SUBSTRING/REPLACE/POSITION/INSTR…`, 날짜 추출 함수, 세션변수, `IS_IN/IS_NOT_IN`, `EXTRACT`, `TO_ENUMERATION_VALUE` 등)는 `pt_infer_common_type`(tc:4799)로 세 인자의 공통 타입을 잡는다. 비대칭 연산자는 인자마다 `pt_get_equivalent_type_with_op`(tc:20498)의 결과만 적용하며(MAYBE 는 늦은 바인딩 연산자면 MAYBE 유지), 공통 타입 계산이 없다. 늦은 바인딩 연산자가 아니면 **MAYBE 인자에 알려진 상대 타입을 미러**(tc:4830~4845), 그래도 MAYBE 면 상위 노드의 expected_domain 을 씀(tc:4870).
2. **비교/범위 연산에서 "컬럼 vs 리터럴"**(tc:5540~5600): 리터럴을 **컬럼 타입으로** 캐스트한다. 단 컬럼이 NUMERIC 이 아닌 숫자형이고 `=` 가 아니면 리터럴을 **DOUBLE** 로(tc:5566: `int_col > 1.5` 의 정확성). 컬럼이 ENUM 이면 제외(ENUM 은 1.7). 문자 컬럼 vs 문자 리터럴은 컬럼 타입(CHAR 컬럼 = 'a' → CHAR)(tc:5595).
3. 비교 연산자는 **숫자끼리·문자끼리는 캐스트하지 않는다**(`PT_ARE_COMPARABLE`, tc:5620~5640) → INT 컬럼 = BIGINT 컬럼, CHAR = VARCHAR 는 실행 시 값 비교로 넘어간다. 범위 연산자는 `PT_ARE_COMPARABLE_NO_CHAR`(문자끼리는 캐스트)(tc:5610).
4. 컬렉션 공통 타입이면 상수만 `pt_coerce_value` 로 변환하고 식은 건드리지 않는다(tc:5645~5680).
5. 시그니처가 NORMAL 타입을 요구하면 공통 타입과 무관하게 그 타입으로(tc:5680, 5695, 5750).
6. 실제 변환 `pt_coerce_expression_argument`(tc:4551): 인자가 MAYBE 이고 (늦은 바인딩 연산자 결과 | 서브쿼리) 이면 **CAST 로 감싼다**(tc:4650, 이때 안쪽 expected_domain 은 NULL 로 초기화되어 XASL 에서 VARIABLE). 그 밖의 MAYBE 는 **expected_domain 부여**(`tp_domain_resolve_default_w_coll(type, LANG_SYS_COLLATION, COLL_LEAVE)`, tc:4672) 후 `pt_preset_hostvar`. 구체 타입 인자는 CAST 래핑(NUMERIC 은 기본 p/s 38,15 tc:4587; VARCHAR 는 FLOATING 정밀도 tc:4592). `return_null_on_function_errors=yes` 면 CAST 에 NOFAIL 플래그(tc:4722).

### 1.5 `pt_eval_expr_type` 의 연산자별 선처리·후처리 (tc:8852~10541)

- **PLUS**(tc:8960~9050): 한쪽 MAYBE → 결과 **MAYBE**, 시그니처 건너뜀(`cannot_use_signature`, tc:9010 → 7 단계 `pt_wrap_expr_w_exp_dom_cast` 만). 날짜+숫자/문자열/ENUM/MAYBE 는 상대를 **BIGINT** 로 캐스트하고 결과=날짜 타입(ADD_DATE 문법 설탕, tc:9022~9060; MAYBE 상대는 CAST 래핑 → 슬롯은 VARIABLE 유지). `compat_mode=mysql` 이면 이 규칙 없음.
- **MINUS**(tc:9063~9100): 한쪽 MAYBE → MAYBE. 날짜-숫자/ENUM → BIGINT 캐스트, 결과 날짜.
- **BETWEEN**(tc:9101): `BETWEEN(a, AND(b,c))` 를 3인자로 펼쳐 공통 타입을 잡고 되돌림(tc:9330). **LIKE**: escape 동일(tc:9124, 9345).
- **IN with 1 element** → `=`/`<>` 로 재작성(tc:9160).
- **TO_CHAR**(tc:9190~9250): 문자열 1인자 `to_char(str)` 는 인자로 치환; 숫자 1인자는 arg3 로케일 플래그를 `intl_number_lang` 으로 교체.
- **대칭 연산자 짝 미러링**(tc:9555~9640, 시그니처 적용 **실패** 즉 `expr == NULL` 경로에서만 실행 — 시그니처가 있는 연산자는 1.4 가 담당): `?` 를 상대 타입으로 `pt_coerce_value`(set_host_var=0 이면 type_enum·data_type 만 바꿈, tc:19640) 하고 expected_domain = `pt_xasl_type_enum_to_domain(상대 type_enum)` — **상대의 p/s·collation 을 버린 기본 도메인**(xg:2251). 단항 `-?`/`PRIOR ?` 안의 슬롯도 같은 처리.
- **비대칭 연산자**(tc:9663~9730, 역시 시그니처가 없는 연산자에서만): arg2/arg3 가 MAYBE 이고 arg1 이 숫자/문자열이면 arg1 의 **완전한 도메인**(`pt_node_to_db_domain`, p/s·collation 포함) 을 준다. (tc:9690 의 `a IN (?, ?)` 원소 처리는 IN 에 시그니처가 있어 실제로는 1.6 경로가 담당한다.)
- **결과가 MAYBE 인 노드의 하향 전파**(tc:9748~9860): `pt_is_able_to_determine_return_type`(tc:8648) 연산자는 MAYBE 를 NONE 으로 되돌려 switch 로 진입. 그 밖은 arg1/arg2 가 MAYBE 일 때 (a) 노드의 expected_domain 이 숫자/문자열이면 그것을 인자에 내려주고, (b) 아니면 상대 인자가 숫자/문자열이면 상대의 **완전한 도메인**을(`PT_NAME` 파생 테이블 컬럼이면 CAST 래핑 tc:9790). 이 경로도 시그니처가 없거나 적용에 실패한 연산자에서만 실행되므로, 시그니처가 있는 늦은 바인딩 연산자(`IFNULL(?, 1)`, `COALESCE(?, 'a')`, `TO_CHAR(?, 'fmt')`, `ADDTIME(?, t)` …)의 슬롯은 **MAYBE 로 남는다**(1.4-6: `pt_coerce_expression_argument` 가 `def_type == MAYBE` 로 no-op).
- **IF**(tc:9863): 조건 `?` → **STRING** 도메인(!); 두 분지가 모두 MAYBE 면 노드 expected_domain 또는 **VARCHAR**; 한쪽만 MAYBE 면 다른 쪽; 둘 다 구체면 `tp_more_general_type`(DB 쪽 일반성) 로 선택 후 **가변 크기 타입으로**(CHAR→VARCHAR, CBRD-22431 tc:9948); 두 분지 CAST.
- **FIELD**(tc:9958): 결과 INTEGER; 인자 부류가 섞이면 arg3 타입(CHAR→VARCHAR)으로 NOFAIL 캐스트.
- **ASSIGN**(`SET c = ?`, tc:10000): `?` 에 컬럼의 완전한 도메인. 리터럴은 `pt_coerce_value_explicit`.
- **STR_TO_DATE**(tc:10058): arg1 MAYBE → VARCHAR 도메인; 포맷 리터럴을 보고 결과 TIME/DATE/DATETIME/DATETIMETZ, 포맷이 `?` 면 결과 **MAYBE**.
- **DATE_ADD/SUB**(tc:10146): arg1/arg2 슬롯 → **STRING** 도메인, 결과 VARCHAR(arg1 이 슬롯이면). 단위가 시간 단위면 arg2 BIGINT 캐스트, 아니면 CHAR 캐스트.
- **CAST**(tc:10269): `CAST(? AS T)` 의 슬롯 → **T 의 완전한 도메인**(tc:10330). COLLATE 수식어만 있는 CAST 는 인자 data_type/expected_domain 에서 타입을 만들어 붙임.
- **CASE/DECODE**(tc:10343): `recursive_type`(왼쪽/오른쪽 재귀 사슬의 공통값) 또는 `pt_common_type_op`; 한쪽 MAYBE 면 다른 쪽, **둘 다 MAYBE 면 VARCHAR**(tc:10395); 컬렉션이면 캐스트 없이 타입 전파; 모든 분지를 공통 타입으로 CAST. `? WHEN ?` 의 조건 슬롯은 `pt_coerce_value(…, LOGICAL)`(tc:10345).
- **EXTRACT**(tc:9400~9530): 문자열 리터럴은 TIME→DATE→TIMESTAMP→DATETIME 순 시도. MAYBE 는 INTEGER 결과 확정.
- **정밀도**(`pt_upd_domain_info`, tc:11423): 한쪽이 MAYBE 면 `TP_FLOATING_PRECISION_VALUE`(tc:11477, 11562, 11720); NUMERIC 산술 결과는 `+ -` 는 (38,15) 기본, `* / % POWER` 도 기본(38,15) — 즉 **컴파일 NUMERIC 결과 p/s 는 항상 (38,15) 또는 FLOATING**, 서버가 실제 p/s 를 계산(#321). 문자열 접합/`CONCAT/FIELD` 는 FLOATING.

### 1.6 IN·서브쿼리·컬렉션 `pt_coerce_range_expr_arguments` (tc:4994~5385)

- `a IN (subquery)`: 서브쿼리 select list 를 DISTINCT 로 만들고 단일 컬럼 검사, 공통 타입으로 arg1 캐스트 + select list 를 `pt_wrap_select_list_with_cast_op`. 숫자끼리·MAYBE 면 캐스트 없음(tc:5060).
- `a IN (v1, v2, …)`(컬렉션 상수/함수): 원소들의 공통 타입(`pt_get_common_collection_type` tc:4902, MAYBE 원소 무시·숫자는 한 부류) 과 arg1 의 공통 타입으로 arg1 을 캐스트; 원소가 두 부류 이상이면 컬렉션 전체를 CAST 로 감싼다(tc:5300, 원소 p/s·collation 은 최대값/큰 codeset 우선 tc:5230~5290). 원소 `?` 는 `pt_wrap_collection_with_cast_op` 에서 expected_domain 을 받는다(tc:8377).
- `a IN ?`(슬롯 하나가 집합): 슬롯 expected = **SET** 기본 도메인(tc:5340).

### 1.7 ENUM (tc:23226~23480, fc:1344)

- `enum_col = const` / `enum_col IN (...)` / `enum_col IN (subquery)` 는 시그니처 전에 `pt_fix_enumeration_comparison` 이 상수·서브쿼리 컬럼을 `PT_TO_ENUMERATION_VALUE` 로 감싼다(인덱스 보존). `?` 상수도 대상(`PT_IS_CONST`) → 슬롯은 `TO_ENUMERATION_VALUE(?)` 안에서 MAYBE 로 남는다.
- 그 밖 비교(`enum_col < ?`)는 대칭 미러링으로 슬롯 type_enum = ENUMERATION, expected_domain = **원소 목록 없는 ENUM 기본 도메인**(tc:9600, xg:2251) → 바인드 때 캐스트를 건너뛴다(pd:3110: ENUM 도메인이면 `pr_clone_value`).
- 시그니처 동치: ENUM 은 NUMBER/DISCRETE/STRING/CHAR 모두와 동치(fc:1370~1400) 이지만 `pt_get_equivalent_type` 은 ENUM 을 항상 변환 대상으로 본다(fc:2760: NUMBER→SMALLINT, STRING→VARCHAR).
- 격자: ENUM×숫자→숫자, ENUM×문자→VARCHAR, ENUM×MAYBE→MAYBE(→ `e1 + ?` 는 늦은 바인딩).

### 1.8 CHAR/VARCHAR/NCHAR/BIT/SET 취급

- NCHAR 계열은 파서에 별도 type_enum 이 없다(CHAR/VARCHAR 에 charset 만 다름). CHAR 는 결과 타입에서 거의 항상 **VARCHAR 로 승격**(pt_common_type, `pt_to_variable_size_type` tc:23920, 함수 결과 fc:1055, UNION sc:350).
- BIT 는 숫자와 공통 타입 DOUBLE(격자 2 — `PT_IS_STRING_TYPE` 이 BIT 포함), 날짜와는 NONE.
- 컬렉션은 "캐스트하지 않고 타입을 전파"가 원칙(tc:5645, tc:10405, `pt_propagate_types` tc:6452). 컬렉션 안의 `?` 만 expected_domain 을 받는다.

### 1.9 함수(PT_FUNCTION) — `func_type::Node` (fc:868~1345) 와 구 집계 경로 (fc:1472)

- 새 경로(`pt_is_function_new_type_checking` fc:2899): 시그니처 표(fc:44~375). 선택: 모든 인자가 동치(`cmp_types_equivalent`)인 첫 시그니처, 없으면 **castable 한 첫 시그니처**(fc:940~957). **MAYBE 는 무엇에든 castable**(fc:648) → `avg(?)` 는 첫 시그니처 NUMBER 로 매칭되어 **`CAST(? AS DOUBLE)` 래핑**(fc:743; 슬롯 expected_domain 은 주지 않음). 결과 타입이 인자 인덱스(`{0,…}`)이면 그 인자의 타입, MAYBE 이면 expected_domain 타입(fc:990).
  - `SUM`: `{0,{NUMBER}}, {0,{MAYBE}}, SET/MULTISET/SEQ` → `sum(?)` 결과 **MAYBE**. `MIN/MAX/FIRST/LAST_VALUE`: SCALAR → `?` 결과 MAYBE. `AVG/STDDEV/VAR*`: DOUBLE. `COUNT`: BIGINT. `MEDIAN/PERCENTILE_CONT/DISC`: `{MAYBE,{NUMBER}}, {0,{DATETIME}}, {MAYBE,{STRING}}, {0,{MAYBE}}` → 숫자·문자 입력이어도 결과 **MAYBE**(값을 봐야 함, fc:62~90 주석). `LEAD/LAG`: 인자 타입. `NTILE`: INTEGER. `GROUP_CONCAT`: VARCHAR/VARBIT(ENUM 은 첫 시그니처로 순서 보존). `ELT`: VARCHAR. JSON 계열 고정.
  - 문자열 결과는 항상 가변 길이 + FLOATING 정밀도(fc:1055).
- 구 경로(집계 함수 일부, fc:1472): `AVG/STDDEV…` 비숫자 인자를 DOUBLE 로 CAST(MAYBE 는 그대로); `SUM` 비숫자 → DOUBLE(ENUM 은 INTEGER) CAST; `BIT_AND…` → BIGINT; `MIN/MAX/…` 는 검사만; `GROUP_CONCAT` 분리자 검사; `NTILE` 비이산 → DOUBLE CAST.

### 1.10 UNION / CTE / 다중 행 VALUES (sc:2180~2900)

- `pt_union_compatible`(sc:2180): 양쪽 MAYBE 면 "호환"으로 간주하고 **아무것도 정하지 않는다**(sc:2198). 한쪽만 MAYBE 는 `pt_common_type` → MAYBE(격자 6) 또는 문자열이면 문자열(sc:2620). 리터럴 쪽만 캐스트 대상.
- 공통 타입 정리 `pt_update_compatible_info`(sc:334): CHAR→**VARCHAR**, BIT→VARBIT, 정밀도는 최대(리터럴 DEFAULT 면 DEFAULT); **NUMERIC 은 항상 (38,15)**; 컬렉션은 손대지 않음.
- 캐스트 적용 `pt_to_compatible_cast`(sc:2403) → `pt_wrap_select_list_with_cast_op`(tc:8250): 슬롯 원소는 `pt_wrap_with_cast_op` 로 감싸질 뿐 expected_domain 은 받지 않는다(CAST 안 슬롯은 VARIABLE).
- VALUES 다중 행: `pt_get_values_query_compatible_info`(sc:745) 가 행 쌍마다 같은 로직. 두 번째 행이 `?` 뿐이면(MAYBE) 첫 행 타입과 MAYBE → 위 규칙으로 **MAYBE 유지**(L-18 의 원인: 열 도메인이 열린 채 리스트 파일로).
- INSERT VALUES(단일 행) / MERGE INSERT: `?` ← 컬럼 도메인(tc:8020, 7935; sc:15477 은 INSERT 의 값 리스트를 다시 확인).
- UPDATE SET / MERGE UPDATE: `pt_assignment_compatible`(sc:13320): 우선순위 ① 이미 있는 `host_var_expected_domains[idx]` ② lhs.expected_domain ③ lhs 기본 도메인(NUMERIC 은 lhs p/s, 문자열은 lhs collation 덮어씀)(sc:13405~13460).

---

## 2. 슬롯 규칙 (스코프 2)

### 2.1 슬롯의 종류와 생성 시점

| 종류 | 생성 | 인덱스 | expected_domain 초기값 |
|---|---|---|---|
| 사용자 `?` | 파서 | `0..host_var_count-1` | `pt_type_enum_to_db_domain(PT_TYPE_NONE)`(= NULL 타입 도메인, nr:11908) |
| auto-param 리터럴 | `qo_auto_parameterize`(ap:41; limit ap:129, keylimit ap:293, MERGE 대입 view_transform.c:15627) — 타입 검사·폴딩 **뒤** | `host_var_count + k` | 리터럴 노드의 `type_enum/data_type/expected_domain` 을 복사(ps:4798~4805); `host_var_expected_domains` 에는 **안 들어간다**(tc:8613) |
| PL/CSQL 정적 SQL 의 `?` | `is_parsing_static_sql`(vdb:474) 로 컴파일한 뒤 마커별 도메인을 PL 서버에 보고(mc:650~670) | 사용자 `?` 와 같음 | 사용자 `?` 와 같음; NULL 이면 `pt_node_to_db_domain(marker)`(MAYBE→VARIABLE) |

auto-param 대상(ap:41~125): WHERE/HAVING/START WITH/CONNECT BY/after-CB/MERGE UPDATE WHERE 의 CNF/DNF 항에서 **LHS 가 속성·함수 인덱스 식·INST_NUM·ORDERBY_NUM** 이고 연산자가 `= > >= < <= LIKE ASSIGN`(RHS), `BETWEEN`(양쪽), `RANGE`(각 범위 양끝, 컬렉션 제외) 일 때 **NULL 이 아닌 상수**. LIMIT/KEYLIMIT 상수. static sql·`is_skip_auto_parameterize` 이면 생략(query_rewrite.c:503).
→ 결론: auto-param 슬롯의 도메인은 **폴딩 후 리터럴 자신의 도메인**이며 컬럼과 무관하다. 타입 검사 때 리터럴이 컬럼 타입으로 CAST 래핑되어 폴딩됐으면 그 결과 값의 도메인(예: `int_col = 3.5` 는 컬럼 INT 가 `=` 라 3.5 가 INT 로 폴딩 시도 → tp_value_cast 실패 시 CAST 노드가 남고 auto-param 되지 않음). L-22 의 `to_number('3')`: 식 결과 타입 NUMERIC(38,15) 이나 폴딩된 db_value 의 도메인이 다를 수 있음(`pt_dbval_to_value` 가 만든 값 vs `data_type` 복사, tc:19790~19810) → 슬롯 `data_type` ≠ 값 타입.

### 2.2 기대 도메인 추론 — 문맥별 결과

아래 "결과"는 사용자 `?` 의 `host_var_expected_domains[idx]` 에 남는 값. `LEAVE` = collation_flag TP_DOMAIN_COLL_LEAVE.

| 문맥 | 슬롯 결과 | 근거 |
|---|---|---|
| `col op ?` (비교·범위, op 시그니처 있음) | 컬럼 타입 미러(`pt_infer_common_type` 미러 → `pt_coerce_expression_argument`): **기본 도메인 + LANG_SYS_COLLATION + LEAVE**(p/s 는 기본; 문자열은 FLOATING) | tc:4830, 4672 |
| `col = ?` 에서 col 이 ENUM | `TO_ENUMERATION_VALUE(?)` 안, 슬롯 MAYBE(VARIABLE) | tc:23300 |
| `enum_col < ?` | ENUM 기본 도메인(원소 없음) → 바인드 캐스트 생략 | tc:9600, pd:3110 |
| `col + ?`, `col - ?`, `col * ?`, `col / ?`, `col DIV ?` | **MAYBE**(늦은 바인딩; 결과도 MAYBE) — 단 결과 MAYBE 노드가 상위에서 expected_domain 을 받으면 CAST 래핑(tc:20586) | tc:9010, 11293 |
| `date_col + ?` | `CAST(? AS BIGINT)` 래핑, 슬롯 VARIABLE | tc:9022 |
| `? + ?`, `? op 리터럴`(산술) | MAYBE; `plus_as_concat` 과 무관하게 실행이 값으로 결정 | tc:9010 |
| `SELECT ?` | MAYBE → regu 도메인 VARIABLE | xg:6462 |
| `CAST(? AS T)` | T 의 완전한 도메인 | tc:10330 |
| `INSERT … VALUES (?)`, MERGE INSERT | 컬럼의 완전한 도메인(`pt_node_to_db_domain`) | tc:8020 |
| `UPDATE SET col = ?` | 컬럼 도메인(우선순위 ①②③) | sc:13405 |
| `WHERE col IN (?, ?)` | 원소 공통 타입이 없어(`pt_get_common_collection_type` 은 MAYBE 를 무시) 컬럼과 비교할 공통 타입 = 컬럼 타입 → 컬렉션 CAST 래핑 안에서 원소 슬롯에 컬럼 타입의 expected_domain(`pt_wrap_collection_with_cast_op`) | tc:5106, 8377 |
| `WHERE col IN ?` | SET 기본 도메인 | tc:5340 |
| `? IN (1, 2)` | arg1 MAYBE 에 컬렉션 공통 타입 미러 | tc:5106 |
| `col LIKE ?`, `? LIKE 'a%'` | CHAR generic → 상대 문자 타입 미러, 아니면 VARCHAR + LEAVE; escape 도 동일 | tc:617, 4672 |
| `IF(?, a, b)` | 조건 슬롯 **STRING** 도메인 | tc:9866 |
| `IF(c, ?, ?)`, `CASE … THEN ? ELSE ?`, `DECODE(x, k, ?, ?)` | **VARCHAR**(둘 다 MAYBE) / 다른 분지 타입 / 상위 expected_domain | tc:9940, 10395 |
| `IFNULL(?, 1)`, `NVL(?, 'a')`, `COALESCE(?, col)` | 비대칭 + 늦은 바인딩 → 슬롯 **MAYBE**, 결과 **MAYBE**(tc:5978; 오버로드는 ANY×ANY 가 선택되어 상대도 캐스트 없음). 결과 MAYBE 노드가 상위에서 expected_domain 을 받으면 `CAST(IFNULL(…) AS …)` 래핑(tc:20586). 문자 형제가 있으면 collation 축에서 슬롯이 VARCHAR+ENFORCE 로 확정(3.3) | tc:3120, 5978 |
| `NULLIF/LEAST/GREATEST(?, …)` | 늦은 바인딩 → MAYBE | tc:20549 |
| `to_char(?, 'fmt')`, `to_char(?, ?)` | 늦은 바인딩 → 슬롯 MAYBE; 결과 VARCHAR. 값 슬롯의 부류(숫자/날짜)는 실행이 결정 | tc:3489, 20540 |
| `to_date(?, ?)`, `str_to_date(?, ?)` | 늦은 바인딩 → MAYBE(STR_TO_DATE 는 arg1 VARCHAR·arg2 VARCHAR 도메인 부여, 포맷 `?` 면 결과 MAYBE) | tc:10080~10110 |
| `date_add(?, INTERVAL ? DAY)` | 둘 다 **STRING** 도메인, 결과 VARCHAR | tc:10148 |
| `addtime(?, ?)`, `from_tz(?, ?)`, `new_time(?, ?, ?)` | 늦은 바인딩 → MAYBE(첫 오버로드 기준 결과 타입: ADDTIME DATETIME, FROM_TZ 는 결과 MAYBE) | tc:1013, 4404 |
| `hour(?)`, `bit_length(?)` | 늦은 바인딩; 결과는 NORMAL INTEGER 로 확정 | tc:1810 |
| `substr(?, 1, 2)`, `lpad(?, 3)`, `concat(?, 'a')`, `upper(?)` | CHAR/STRING generic → **VARCHAR + LANG_SYS_COLLATION + LEAVE**; 문자 형제가 있으면 `pt_coerce_node_collation` 이 형제 collation 으로 **ENFORCE** | tc:4672, 21620 |
| `concat(?, ?)` | 둘 다 VARCHAR+LEAVE, 결과 collation_flag LEAVE(실행에서 값의 collation) | tc:22400~22470, 11447 |
| `? \|\| ?` | STRCAT 은 시그니처 있음 → VARCHAR+LEAVE(PLUS 와 다름) | tc:2133 |
| `abs(?)`, `round(?, 2)`, `-?` | 늦은 바인딩 → MAYBE | tc:20530 |
| `sum(?)`, `min(?)`, `max(?)` | MAYBE, 결과 MAYBE | fc:120, 148 |
| `avg(?)`, `stddev(?)` | `CAST(? AS DOUBLE)` 래핑, 슬롯 VARIABLE | fc:743 |
| `median(?)`, `percentile_cont(?) …` | MAYBE 결과 MAYBE(값·정렬 키 모두 실행) | fc:62~146 |
| `group_concat(?, ',')` | CHAR generic 첫 매칭 → VARCHAR 캐스트 래핑 | fc:158 |
| `@v := ?` | `PT_DEFINE_VARIABLE` 늦은 바인딩 → 슬롯 MAYBE; 결과 MAYBE | tc:3961 |
| `@v` 읽기 | 결과 MAYBE; expected_domain 이 있으면 `CAST(@v AS domain)` 래핑(tc:20600, 세션변수는 cast_type 을 도메인에서 만듦) | tc:3945 |
| `LIMIT ?`, `KEYLIMIT ?` | BIGINT(`pt_limit_to_numbering_expr` 로 `INST_NUM() <= ?` 재작성 후 비교 미러 → BIGINT; keylimit 은 xg:11587 직접) | tc:7290, xg:11587 |
| `ORDER BY ?`, `GROUP BY ?` | 정렬 키 슬롯은 MAYBE(VARIABLE) — 서버가 값 보고 정함(#321) | xg:5907 |
| 파생 테이블 컬럼이 `?` (`SELECT * FROM (SELECT ?) t WHERE t.c = 1`) | PT_NAME MAYBE → CAST 래핑(비교 상대 타입) | tc:9790 |
| VALUES 2행 이후의 `?` | MAYBE(1.10) | sc:2198 |
| UNION 양쪽이 `?` | MAYBE(1.10) | sc:2198 |
| PL/CSQL 정적 SQL 의 `?` | 위와 동일한 파서 규칙; MAYBE 면 PL 에 **VARIABLE(NULL 타입)** 로 보고되어 PL 이 자기 정적 타입을 버린다 | mc:650~670 |

### 2.3 슬롯 도메인의 소비 — XASL 생성 `pt_make_regu_hostvar` (xg:6391~6510)

regu 도메인 결정 순서:
1. 노드의 `data_type`(대칭 미러링·CAST 가 붙여 준 것) → `pt_xasl_node_to_domain`(xg:6413).
2. 바인드 값이 이미 있으면(`set_host_var==1` 또는 auto-param 처럼 값이 NULL 이 아니면) **값의 타입**(문자열은 값의 codeset/collation/precision 까지)(xg:6418~6445).
3. `expected_domain`(xg:6450).
4. `type_enum` → MAYBE 는 **DB_TYPE_VARIABLE**(xg:6462, pd:2420).

그리고 값이 아직 없으면(prepare) 값 DB_VALUE 를 그 도메인으로 **미리 초기화**(`db_value_domain_init`, xg:6480); 값이 있는데 타입/collation 이 다르면 **클라이언트에서 `tp_value_cast`**(xg:6490). 식 노드의 regu 도메인은 늦은 바인딩 연산자면 노드 도메인(MAYBE→VARIABLE), 아니면 expected_domain(xg:7885, 7940, 8030, 8080, 8100, 8145, 8222).

### 2.4 바인드 시 캐스트 `pt_set_host_variables` (pd:3072~3136)

사용자 `?` 마다 `host_var_expected_domains[i]` 로 `tp_value_cast_preserve_domain`(값의 p/s 보존, L-11 대응). 도메인이 UNKNOWN(NULL 타입)·ENUM 이면 복제만. 문자 도메인인데 값이 VARCHAR 이면 **원 값을 유지**(pd:3128: CHAR 도메인에 VARCHAR 값 → 패딩하지 않음; L-23 trailing space 의미). 실패하면 `-494 Cannot coerce host var to type …`(pd:3120). 이 함수는 CAS 의 `db_push_values`(vdb:1901, cas_execute.c:10323)에서 호출된다 — 즉 **현재는 클라이언트(CAS)가 값을 변환**하고 서버는 변환된 값을 받는다(D-M4 와 정반대).

`hostvar_late_binding=yes`(기본 no)면 실행 시 값을 알고 재컴파일할 때 `?` 를 값 노드로 치환(nr:3790, vdb:2343)해 리터럴처럼 타입을 정한다.

---

## 3. collation 규칙 (스코프 3)

### 3.1 coercibility 레벨 `pt_get_collation_info` (tc:20857~21058)

| 노드 | collation 출처 | 레벨 | can_force_cs |
|---|---|---|---|
| data_type 있는 문자 노드 | data_type.collation | 아래 노드 종류별 | LEAVE 플래그면 true |
| expected_domain 있는 노드 | 도메인 collation | 노드 종류별 | LEAVE 면 true |
| **MAYBE** 노드(도메인 없음) / 문자 PT_VALUE(data_type 없음) | **LANG_SYS_COLLATION**(바이너리) | | MAYBE 면 **true** |
| COLLATE 수식어 | 수식어 | NOT_COERC(0) | false |
| PT_VALUE | | L4(바이너리/BIN_COERC/COERC) | |
| **PT_HOST_VAR** | | **FULLY_COERC**, true | |
| `@v` 읽기/쓰기 | | FULLY_COERC | |
| 접힌 CAST(`CAST_SHOULD_FOLD`) | 안쪽 노드의 레벨을 상속 | | 안쪽이 비문자면 true |
| `USER/DATABASE/VERSION…` | | L3 | |
| 식·서브쿼리·함수·메서드 | | L2(바이너리/BIN/일반) | |
| 파생 스펙 컬럼 | | L2 | |
| 입력 파라미터 PT_NAME | | L5 | |
| 컬럼(PT_NAME/PT_DOT_) | | **L1**(ISO_BIN/BIN/일반) | |

### 3.2 병합 `pt_common_collation` (tc:22175~22337)

`MORE_COERCIBLE(a,b)` = (a.can_force_cs && !b.can_force_cs) || (a.level > b.level && 같은 can_force_cs). 규칙:
- 두 인자 collation 이 다르고 **레벨·can_force_cs 가 같으면 오류**(-1150 계열 `MSGCAT_SEMANTIC_COLLATION_OP_ERROR`).
- 더 coercible 한 쪽이 상대 collation 을 받는다. codeset 변환은 `INTL_CAN_COERCE_CS` 가 허용하거나 can_force_cs 일 때만.
- 3인자는 2인자 결과와 같은 규칙을 한 번 더.

### 3.3 식의 collation `pt_check_expr_collation` (tc:22340~22930)

1. `pt_is_op_w_collation`(tc:20760) 연산자만; `PT_PLUS` 는 `plus_as_concat=yes` 일 때만. BETWEEN 은 arg1 이 문자/MAYBE 이고 범위식이 아닐 때만. MINUS 는 컬렉션일 때만.
2. 인자별 정보 수집: 문자 타입 또는 **MAYBE**(집합 expected_domain 이 아닌) 인자가 대상. `can_force_cs==false` 인 인자 수 = `args_having_coll`, 그 collation 이 후보 공통 collation.
3. 비교 연산자에 COLLATE 수식어가 있으면 모든 문자 인자를 수식어 collation 으로 강제(codeset 다르면 오류)(tc:22550).
4. 대상 인자가 2개 이상이고 collation 이 다르거나 MAYBE/need_coerce 가 있으면 `pt_common_collation` 으로 공통 collation(tc:22640).
5. **coerce_arg**(tc:22650~22740): MAYBE 인자 또는 need_coerce 인자는 `args_having_coll > 0` 일 때 `pt_coerce_node_collation` 으로 감싼다. MAYBE 의 래핑 타입은 `pt_wrap_type_for_collation`(tc:23602: 컬렉션 형제의 문자 원소 타입, 아니면 **VARCHAR**).
   - `pt_coerce_node_collation`(tc:21526): HOST_VAR MAYBE 이고 expected_domain 없음 → **expected_domain = VARCHAR + 공통 collation + `COLL_ENFORCE`**(tc:21620); 도메인이 이미 있으면 (NAME/EXPR/SELECT 등) `CAST(x AS VARCHAR COLLATE c)` 래핑(ENFORCE); PT_VALUE 는 data_type 의 collation 만 바꿈.
6. **결과 collation**(coerce_result, tc:22700~22920): `CHR/CLOB_TO_CHAR` 는 arg2 값; COLLATE 수식어면 수식어. `COALESCE/NVL/NVL2/IFNULL/GREATEST/LEAST/NULLIF` 결과가 MAYBE 이고 문자 형제가 있으면 결과를 `CAST(expr AS <형제 문자 타입> COLLATE c)` 로 감쌈(`is_wrapped_res_for_coll`). `PLUS` 결과 MAYBE 는 `args_having_coll>0` 일 때만. 문자열 함수(`CONCAT/…/IF/CONNECT_BY_ROOT/PRIOR/QPRIOR/INDEX_PREFIX`) 결과는 `args_having_coll>0` 이면 공통 collation 으로 강제(MAYBE 결과면 VARCHAR CAST).
   - `args_having_coll == 0`(모든 문자 인자가 슬롯/MAYBE)이면 **아무것도 정하지 않는다** → 결과 data_type 의 collation_flag 는 `pt_upd_domain_info` 가 LEAVE 로 둠(tc:11447: 인자 중 하나라도 NORMAL 이면 NORMAL) → **실행이 값의 collation 으로 결정**(L-47 의 "LEAVE 계약").
7. CASE/DECODE 는 `pt_check_recursive_expr_collation`(tc:22935): 사슬 전체에서 가장 coercible 한 쪽으로 통일, 같은 레벨 충돌은 오류.
8. `pt_fix_arguments_collation_flag`(tc:23698): 시그니처의 모든 오버로드가 문자 타입만 허용하는 인자 자리의 CAST 인자는 ENFORCE → NORMAL 로 승격(연산자에 들어가는 순간 확정).

### 3.4 함수의 collation (fc:1157~1300, fc:1060~1100, fc:2425)

- 새 경로: 인자 시그니처가 문자 부류(STRING/CHAR/PRIMITIVE/ANY/SCALAR)이고 동치 타입이 문자/MAYBE 이면 `pt_get_collation_info` 로 공통 collation 누적(`pt_common_collation`, 충돌은 `INCOMPATIBLE` 로 다음 시그니처 시도). JSON 인자 함수는 UTF8 바이너리 강제. **비 MAYBE 문자 인자가 하나라도 있으면 `m_collation_action=NORMAL`, 전부 MAYBE 면 LEAVE**(fc:1270~1280). 인자 적용 때 공통 collation 과 다르면 `pt_coerce_node_collation`(fc:750). 결과(fc:1077~1098): LEAVE 면 결과 data_type 에 LEAVE 플래그(실행 결정), 아니면 결과를 공통 collation 으로 강제.
- 구 경로 `pt_check_function_collation`(fc:2425): 인자 순회로 공통 collation 을 잡고 다른 인자를 coerce; 모든 인자가 MAYBE/CAST-MAYBE 면 결과 LEAVE.
- 집합 생성 함수(`F_SET/…`)는 `pt_add_type_to_set` 으로 원소 data_type 갱신; `pt_node_to_db_domain` 은 컬렉션 원소의 LEAVE 를 **NORMAL 로 확정**(pd:2262 주석: 원소는 실행 결정 경로가 없다).

### 3.5 리터럴·세션변수·리스트 컬럼·연산자 결과

- 문자 리터럴: 파서가 클라이언트 collation(`intl_collation` 파라미터 → `lang_get_client_collation`)을 data_type 에 붙임(L4). 리터럴 옆에 컬럼(L1)이 오면 컬럼 collation 이 이긴다.
- MAYBE 슬롯: 시작은 LANG_SYS_COLLATION(**바이너리**) + LEAVE(=can_force_cs). 형제 문자 노드가 있으면 그 collation 으로 **ENFORCE** 되어 컴파일 확정(tc:21620). 형제가 전부 슬롯이면 미확정(LEAVE) → 실행이 값의 collation(바인드 값은 CAS 가 클라이언트 charset/collation 으로 만듦).
- `@v` 읽기: FULLY_COERC, 결과 MAYBE → 형제 문자 노드가 있으면 `CAST(@v AS VARCHAR COLLATE c)`.
- 리스트(서브쿼리/파생) 컬럼: L2. 슬롯이 컬럼으로 나오면 MAYBE 컬럼(VARIABLE 도메인).
- 연산자 결과: 위 3.3-6. 함수 결과: 3.4.
- `LANG_SYS_COLLATION ≠ 클라이언트 collation` 이므로 `SET NAMES … COLLATE x` 뒤에도 슬롯의 기본은 바이너리이다. `charset/collation` 의 결정 축과 값의 codeset 변환(`INTL_CAN_COERCE_CS`)은 분리되어 있다.

### 3.6 `SET NAMES` / `ALTER … COLLATE` 와 prepared 문 (재컴파일 트리거)

- `do_set_names`(execute_statement.c:18956)는 `intl_collation` 시스템 파라미터만 바꾼다. prepared 문(CAS `srv_handle`, SQL-level `PREPARE`)을 **무효화하지 않는다**. 플랜 캐시 키(XASL sha1)는 재작성된 질의 텍스트로 만들어지며 텍스트 출력은 `LANG_SYS_COLLATION` 이 아닌 collation 만 인쇄(parse_tree_cl.c:9222, 12146) → 같은 문장이 다른 클라이언트 collation 에서 다른 리터럴 collation 을 갖는데도 텍스트가 같으면 **같은 캐시 항목**을 쓴다(L-25 의 i18n LIKE 1행 소실 경로).
- 스키마 변경(`ALTER … COLLATE` 포함)은 서버 XASL 캐시를 클래스 OID 로 무효화(`xcache_remove_by_oid` xasl_cache.c:2074) → 실행 시 `ER_QPROC_INVALID_XASLNODE` 로 CAS 가 재준비(cas_execute.c:1188, 1502, vdb:2277~2294). 클라이언트 측 파스 트리는 재컴파일된다.
- 값 의존 재컴파일: `EXECUTE PREPARE` 는 `hostvar_peeking` 이 켜져 있고 XASL 에 `LIKE_RECOMPILE_CANDIDATE`/limit 플래그가 있으면 바인드 값을 넣어 다시 파싱해 재컴파일 여부를 정한다(vdb:3139, 3150, ps:10254).

---

## 4. 조합별 분류표 — 현행 결과와 사전 확정 가능성 (스코프 4)

분류: **C** = 컴파일에서 확정(값 없이 결정) · **G** = 게이트에서 바인드 값의 타입을 보고 확정 가능(값 하나로 결정, 행 불필요) · **A** = 애매(현재 값·행마다 결정하거나 상위 문맥이 없어 규칙이 결과를 정함).
"DOUBLE/VARCHAR 적용 시 변화"는 A 부류에 D-M2(숫자→DOUBLE, 문자→VARCHAR) 를 적용했을 때 현행과 결과가 달라지는 대표 사례.

### 4.1 산술

| # | 조합 | 현행 결과 타입 | 분류 | DOUBLE/VARCHAR 적용 시 변화 |
|---|---|---|---|---|
| A1 | `int_col + 1` | INTEGER(격자) | C | — |
| A2 | `int_col + 1.5` | NUMERIC(38,15)→서버 p/s | C | — |
| A3 | `int_col + '1'` | DOUBLE(격자 2) | C | 이미 DOUBLE |
| A4 | `int_col - '1'`, `* '1'` | 오류(tc:11315) | C | — |
| A5 | `int_col + ?` | **MAYBE**(늦은 바인딩); 실행이 값 타입으로 산술(정수 바인드→INT, 1.1→DOUBLE, '1'→DOUBLE, 날짜→날짜+일) | **A** | 슬롯 DOUBLE 고정 → 결과 DOUBLE: `1+1`→`2.0` 표기, BIGINT 큰 값 정밀도 손실, `plus_as_concat` 접합 불가(L-12·L-13) |
| A6 | `int_col / ?` | MAYBE; 실행: 정수÷정수 = 정수 절삭(oracle_compat 아니면) | A | DOUBLE 이면 `7/2`→`3.5`(현행 3) — **의미 변경**(L-12) |
| A7 | `int_col DIV ?`, `MOD ?` | 시그니처 DISCRETE → 슬롯 **BIGINT**(늦은 바인딩 연산자가 아님) | C | — |
| A8 | `? + ?`, `? + 1` | MAYBE; 값 타입 결정('a'+'b' 접합 / 1+2 정수 / 2.7+1=3.7) | A | DOUBLE 고정: 접합 불가, `1+1`→`2.0` |
| A9 | `date_col + ?` | `CAST(? AS BIGINT)`, 결과 DATE | C(슬롯 VARIABLE 이나 캐스트 계획 확정) | — |
| A10 | `? + date_col` | 동일(PLUS 가환) | C | — |
| A11 | `date_col - ?` | 숫자/ENUM 만 BIGINT; `?` 는 MAYBE → 실행 결정(날짜-날짜=BIGINT vs 날짜-정수=날짜) | A | DOUBLE 이면 날짜 바인드 불가 → 답안 변경(날짜 차 계산은 CAST 필요) |
| A12 | `numeric_col(10,2) + ?` | MAYBE; 실행 NUMERIC 산술 | A | DOUBLE: `1.10+?`→DOUBLE 표기(`2.2` vs `2.20`) |
| A13 | `enum_col + ?` | MAYBE(격자 ENUM×MAYBE); 실행: 값 타입에 따라 서수+정수/실수/접합 | A | 서수 승격 후 DOUBLE(L-10 "의미 갈림 제거") |
| A14 | `-?`, `abs(?)`, `round(?, 2)`, `ceil(?)` | MAYBE | A | DOUBLE: `round(?,2)` 로 정수 바인드 → `3.0`; NUMERIC 바인드 p/s 손실 |
| A15 | `bit_col + 1` | DOUBLE(BIT 도 STRING) | C | — |
| A16 | `? DIV ?` | 둘 다 BIGINT | C | — |

### 4.2 비교·범위·IN·LIKE

| # | 조합 | 현행 | 분류 | 변화 |
|---|---|---|---|---|
| B1 | `int_col = 1.5` | 리터럴 INT 로 캐스트 시도 → `=` 는 컬럼 타입(tc:5555) | C | — |
| B2 | `int_col > 1.5` | 리터럴 **DOUBLE**(tc:5566) | C | — |
| B3 | `int_col = '1'` | 리터럴 → INT 캐스트 | C | — |
| B4 | `int_col = ?` | 슬롯 **INTEGER 기본 도메인**(미러); 바인드 시 CAS 가 캐스트(1.5 바인드 → -494 or 절삭? `tp_value_cast_preserve_domain` 실패 → -494) | G | 규칙표가 "미러" 를 유지하면 변화 없음 |
| B5 | `int_col < ?` | 슬롯 INTEGER(미러; B2 의 DOUBLE 규칙은 리터럴에만) | G | 1.5 바인드 시 -494 / 절삭 → 규칙표 결정 필요(리터럴과 비대칭) |
| B6 | `varchar_col = ?` | VARCHAR + LEAVE, collation 은 컬럼 collation 으로 ENFORCE | C | — |
| B7 | `char_col(5) = ?` | CHAR 기본 도메인(정밀도 FLOATING) + 컬럼 collation; VARCHAR 값 바인드 → 원 값 유지(pd:3128) → trailing space 의미 | G | VARCHAR 고정이면 `'a' = 'a  '` 판정 변화(L-23) |
| B8 | `? = ?` | 둘 다 MAYBE, 비교 실행 결정(값 타입 갈림: '1'=1 → DOUBLE 비교) | A | VARCHAR 고정: `'1' = 1` → 문자열 비교 (`'1'='1'` 참, `'01'=1` 거짓; 현행 참) |
| B9 | `? = 1` | 슬롯 INTEGER 미러 | G | — |
| B10 | `? = 'a'` | 슬롯 VARCHAR + 리터럴 collation | C | — |
| B11 | `date_col = ?` | 슬롯 DATE 기본 도메인 | G | — |
| B12 | `date_col = '2024-01-01'` | 리터럴 → DATE(컬럼 타입) | C | — |
| B13 | `enum_col = ?` | `TO_ENUMERATION_VALUE(?)`, 슬롯 VARIABLE; 실행이 값 타입(정수=서수, 문자=이름) | A | VARCHAR 고정이면 정수 바인드가 문자 `'3'` 로 → 이름 비교 → **조용한 오답**(L-06) → 규칙표 ENUM 행 별도 |
| B14 | `enum_col < ?` | 슬롯 ENUM 도메인(원소 없음), 캐스트 생략, 실행이 서수/사전식 결정 | A | L-10: 서수 승격 규칙 필요 |
| B15 | `int_col IN (1, '2', ?)` | 컬렉션 공통 타입(원소 1·'2' 두 부류 → CAST 래핑), `?` 원소는 컬럼 타입 | C/G | — |
| B16 | `int_col IN ?` | SET 도메인 | G | 원소 타입은 값 |
| B17 | `? IN (1, 2)` | 슬롯 INTEGER 미러 | G | — |
| B18 | `? IN ('a', 1)` | 원소 공통 DOUBLE → 슬롯 DOUBLE | C | — |
| B19 | `int_col IN (SELECT ? …)` | 서브쿼리 컬럼 MAYBE → 캐스트 없음(tc:5060), 실행 | A | 서브쿼리 슬롯 컬럼 도메인 확정 필요 |
| B20 | `varchar_col LIKE ?` | VARCHAR + 컬럼 collation | C | — |
| B21 | `? LIKE ?` | 둘 다 VARCHAR + LANG_SYS(바이너리) + LEAVE → 실행이 값 collation | A | VARCHAR 는 이미; collation 은 §5 |
| B22 | `int_col LIKE ?` | 컬럼 VARCHAR 캐스트, 슬롯 VARCHAR | C | — |
| B23 | `int_col BETWEEN ? AND ?` | 둘 다 INTEGER 미러 | G | — |
| B24 | `? BETWEEN 1 AND 10` | INTEGER 미러(3인자 공통) | G | — |
| B25 | `int_col = bigint_col`, `char_col = varchar_col` | 캐스트 없음(`PT_ARE_COMPARABLE`) → 실행 비교 | C(서버 규칙 #321) | — |
| B26 | `str_col = 1` | 리터럴 → 컬럼 타입 VARCHAR(tc:5555: 컬럼 vs 리터럴은 컬럼 타입) | C | 격자(DOUBLE)와 다름 — 규칙표 명시 필요 |
| B27 | `str_col = int_col` | 공통 DOUBLE → 양쪽 DOUBLE 캐스트 | C | — |

### 4.3 공통값(UNION/CASE/COALESCE/VALUES)

| # | 조합 | 현행 | 분류 | 변화 |
|---|---|---|---|---|
| U1 | `SELECT 1 UNION SELECT '2'` | DOUBLE(격자) | C | — |
| U2 | `SELECT int_col UNION SELECT ?` | MAYBE 유지(sc:2198~2623: 문자열만 미러) | A | 첫 arm 타입 미러가 자연스러움(규칙표: VALUES/UNION 위치 미러, L-18) |
| U3 | `SELECT ? UNION SELECT ?` | MAYBE | A | VARCHAR 고정(문맥 없음) |
| U4 | `VALUES (1), (?)` | MAYBE(같은 로직) | A | 첫 행 미러 |
| U5 | `VALUES (?), (2)` | MAYBE(첫 행이 `?`) | A | 두 번째 행 타입 |
| U6 | `CASE WHEN c THEN ? ELSE ? END` | VARCHAR(tc:10395) | C(규칙이 정함) | 이미 VARCHAR |
| U7 | `CASE WHEN c THEN ? ELSE 1 END` | INTEGER(한쪽 MAYBE → 다른 쪽), `?` INTEGER 캐스트 | C | — |
| U8 | `CASE ? WHEN ? THEN 1 END` | 비교 `? = ?` 부류(B8) | A | |
| U9 | `COALESCE(?, 1)`, `NVL(?, 1)` | 슬롯 MAYBE, 결과 **MAYBE**(ANY×ANY 오버로드, 늦은 바인딩); 실행이 값 타입으로 결정('a' 바인드면 'a' 반환) | A | 슬롯 DOUBLE: 'a' 바인드 → 오류(현행 'a' 반환) — 또는 규칙표가 "알려진 형제 타입 미러" 를 택하면 INTEGER |
| U10 | `COALESCE(?, ?)` | 결과 MAYBE | A | VARCHAR |
| U11 | `IFNULL(?, ?)` | 결과 MAYBE, 슬롯 MAYBE(pt_common_type_op 의 IFNULL→VARCHAR 보정은 도달하지 않음) | A | 슬롯·결과 VARCHAR 확정 |
| U12 | `IFNULL(?, 1)`, `IFNULL(?, 'a')` | 슬롯 MAYBE, 결과 MAYBE; 문자 형제가 있으면 collation 축에서만 슬롯 VARCHAR ENFORCE(3.3) | A | L-23 `ifnull(?, 1)` 기본 타입 답안 변경(형제 미러 vs DOUBLE) |
| U13 | `COALESCE(CAST(? AS DATETIME), ?, …)` | 첫 인자 DATETIME 확정, 나머지 슬롯 MAYBE; 결과 DATETIME 이지만 `pt_upd_domain_info` 가 문자 형제 없이도 collation_flag 를 옮기는 경로(L-19) | A | 비문자 결과 도메인의 collation 플래그 제거 규칙 |
| U14 | `LEAST(?, 3)`, `GREATEST(?, 'b')` | 늦은 바인딩 → MAYBE | A | DOUBLE/VARCHAR 로 부류 고정 |
| U15 | `IF(?, 1, 2)` | 조건 STRING(!) | C | 규칙표: 조건 슬롯은 LOGICAL/INTEGER 가 맞음(답안 변경 후보) |
| U16 | `INSERT t(int_c) SELECT ?` | INSERT-SELECT: select list 슬롯은 VALUES 규칙을 타지 않음 → MAYBE(L-41) | A | 대상 컬럼 미러 |

### 4.4 함수·집계·문자열

| # | 조합 | 현행 | 분류 | 변화 |
|---|---|---|---|---|
| F1 | `to_char(?, 'YYYY-MM-DD')` | 슬롯 MAYBE, 결과 VARCHAR; 실행이 값 부류(숫자/날짜)로 포맷 해석 | A | NUMBER 고정 시 날짜 바인드 -494(L-17) → 규칙표 "포맷 리터럴에서 추론 / 형제 인자 / 모호 오류" |
| F2 | `to_char(?, ?)` | 둘 다 MAYBE | A | 위와 같음, 포맷도 값 |
| F3 | `to_char(int_col, ?)` | 포맷 슬롯 MAYBE(늦은 바인딩; STRING 부류지만 부여 안 함) | A→G | VARCHAR 확정 가능 |
| F4 | `to_number(?)`, `to_number(?, ?)` | 늦은 바인딩 아님 → 슬롯 VARCHAR+LEAVE, 결과 NUMERIC(38,15)(폴딩되면 값 타입, L-22) | C | 결과 표기: NUMERIC vs 값 INTEGER 불일치 정리 |
| F5 | `to_date(?, 'fmt')`, `str_to_date(?, ?)` | 슬롯 VARCHAR(STR_TO_DATE 는 명시 부여), 결과 DATE/…/MAYBE(포맷 `?`) | C/A | 포맷 `?` 면 결과 MAYBE → 규칙표: 포맷은 리터럴 요구 또는 DATETIME 기본 |
| F6 | `date_add(?, INTERVAL 1 DAY)` | 슬롯 STRING, 결과 VARCHAR | C(문자열 결과라는 규칙) | 결과 VARCHAR 는 이미; 값 부류 확정은 게이트 |
| F7 | `addtime(?, ?)`, `from_tz(?, ?)`, `new_time(?, ?, ?)` | MAYBE; 실행이 값 부류로 오버로드 선택 | A | 값 부류(날짜) 게이트 확정; 시그니처 불일치 -889/-621 회피 규칙(L-17) |
| F8 | `hour(?)`, `bit_length(?)` | 슬롯 MAYBE, 결과 INTEGER | A(슬롯) | VARCHAR 고정 시 TIME 바인드 → 문자열 파싱(현행 TIME 직접) |
| F9 | `substr(?, 1, 2)`, `upper(?)`, `trim(?)`, `lpad(?, 3, ?)` | 슬롯 VARCHAR+LANG_SYS+LEAVE(형제 문자 없으면 collation 미확정) | C(타입)/A(collation) | — |
| F10 | `concat(?, ?)`, `? \|\| ?` | VARCHAR, 결과 collation LEAVE | C/A | — |
| F11 | `concat(?, int_col)` | int_col → VARCHAR 캐스트, `?` VARCHAR | C | — |
| F12 | `rtrim(? + ?, ?)` | `? + ?` MAYBE(PLUS) 가 CHAR generic 인자 → `CAST(?+? AS VARCHAR)` 래핑(늦은 바인딩 결과) | A | 내부 슬롯은 규칙 A8 |
| F13 | `sum(?)`, `min(?)`, `max(?)` | 결과 MAYBE, 누산기 도메인 실행 결정(L-43) | A | DOUBLE/VARCHAR 부류 고정 |
| F14 | `avg(?)` | `CAST(? AS DOUBLE)`, 결과 DOUBLE | C | — |
| F15 | `sum(int_col)` | INTEGER(data_type 복사); 서버 누산도 INTEGER 로 INT 오버플로 -3009, 승격 없음(#321 §5 F15 정정) | C | — |
| F16 | `median(?)`, `percentile_cont(0.5) WITHIN GROUP (ORDER BY ?)` | 결과 MAYBE, 정렬 키 MAYBE | A | 인자·정렬 키 모두 DOUBLE(문자열 입력은 CAST 요구, L-21) |
| F17 | `median(varchar_col)` | 결과 **MAYBE**(시그니처 `{MAYBE,{STRING}}`) | A(슬롯 없이도!) | 값이 숫자면 DOUBLE, 날짜면 DATE — 규칙표: 문자열 입력은 오류 또는 DOUBLE |
| F18 | `group_concat(?, ',')` | `CAST(? AS VARCHAR)` | C | — |
| F19 | `lead(?)`, `nth_value(?, 2)` | MAYBE | A | |
| F20 | `elt(?, 'a', 'b')` | 인덱스 DISCRETE 캐스트 | C | — |
| F21 | `json_extract(?, '$.a')` | JSON_DOC generic: MAYBE castable → `CAST(? AS JSON)` | C | — |

### 4.5 슬롯 단독·세션변수·PL·LIMIT

| # | 조합 | 현행 | 분류 | 변화 |
|---|---|---|---|---|
| S1 | `SELECT ?` | MAYBE → VARIABLE; 컬럼 메타 `(0,0)`; 값 타입이 결과 | A | VARCHAR 고정(L-23) |
| S2 | `SELECT ? FROM t WHERE 1 = 0` | 미실행 → 메타 미확정(L-24) | A | 컴파일 확정이면 해소 |
| S3 | `@v := ?` | 슬롯 MAYBE, 결과 MAYBE; 세션변수는 값 타입을 저장 | A | 규칙표 세션변수 행(저장 타입/VARCHAR) |
| S4 | `@v` 읽기 단독 | MAYBE | A | 위 |
| S5 | `@v + 1`, `to_char(@d)`, `addtime(@v, t)`, `concat('a', lpad(@i, 3))` | 늦은 바인딩 → MAYBE; 형제가 정하는 자리에서 CAST(@v AS …)로 강제(경로마다 다름, L-15) | A | 세션변수 읽기 타입 결정 규칙 |
| S6 | PL/CSQL `SELECT … WHERE c = ?` (정적 SQL) | 파서 규칙 그대로; 슬롯 MAYBE 면 PL 에 NULL 타입 보고 → PL 이 인자 정적 타입을 버리고 값 그대로 바인드(L-16) | A | prepare 시 선언 타입 전달 여부(#317/#318) |
| S7 | `LIMIT ?`, `LIMIT ?, ?` | BIGINT(재작성 후 비교 미러) | C | — |
| S8 | `KEYLIMIT ?` | BIGINT(xg:11587) | C | — |
| S9 | `ORDER BY ?`, `GROUP BY ?` | 정렬 키 MAYBE | A | 서버가 값 보고(#321) |
| S10 | `SELECT * FROM (SELECT ? AS c) t WHERE t.c = 1` | `CAST(t.c AS INTEGER)` 래핑 | C | 파생 컬럼 슬롯 자체는 VARIABLE |
| S11 | `int_col = to_number('3')`(auto-param) | 리터럴 폴딩 값 도메인 vs 식 data_type NUMERIC 불일치(L-22) | A | 값 타입 = 슬롯 도메인 불변식 |
| S12 | `WHERE int_col = 3`(auto-param) | 슬롯 도메인 = 값 INTEGER; 컬럼 미러가 아니라 **값 도메인** | C | 규칙표: auto-param 은 값 도메인 유지 vs 컬럼 미러 |
| S13 | `WHERE str_col = 'abc'`(auto-param) | 값 도메인: CHAR(3)? — 리터럴은 VARCHAR/CHAR 판단 후 폴딩 시 컬럼 타입으로 캐스트(B26) → CHAR 컬럼이면 CHAR 값 | C | — |

---

## 5. collation 조합 분류

| # | 조합 | 현행 | 분류 | 비고 |
|---|---|---|---|---|
| K1 | `col(coll A) = 'x'`(리터럴 coll B) | A(L1 > L4) | C | |
| K2 | `col(A) = ?` | `?` VARCHAR + **A ENFORCE** | C | 컴파일 고정 → `ALTER … COLLATE` 뒤 재컴파일(xcache 무효화)로 갱신 |
| K3 | `'x' = ?` | `?` ← 리터럴 collation(클라이언트) | C | |
| K4 | `? = ?` | 둘 다 LANG_SYS(바이너리)+LEAVE → 실행이 값 collation | **A** | 규칙표: (a) 클라이언트 collation 고정 (b) 게이트 확정 (c) LEAVE 유지 |
| K5 | `concat(?, ?)`, `upper(?)` | 결과 LEAVE | A | 위 |
| K6 | `col(A) = col(B)` 같은 레벨 | **오류** | C | |
| K7 | `expr(A) = col(B)` | col(L1) 이김 | C | |
| K8 | `COALESCE(?, col(A))` | 결과 `CAST(… AS VARCHAR COLLATE A)`, `?` A ENFORCE | C | |
| K9 | `CASE … THEN ? ELSE col(A)` | 재귀 collation: A | C | |
| K10 | `col(A) IN (?, ?)` | 원소 슬롯 A | C | |
| K11 | `? IN ('a', 'b')` | 리터럴 collation | C | |
| K12 | `SET NAMES … COLLATE x` 뒤 prepared `col LIKE ?` | 슬롯은 prepare 때 컬럼 collation 고정; 리터럴 인쇄가 LANG_SYS 기준이라 캐시 키 동일 | C(의도 여부는 #322) | L-25 |
| K13 | `percentile_cont(0.5) WITHIN GROUP (ORDER BY varchar_col)` | 정렬 키 비교 도메인은 실행(`cmp_dom` 지연) | A | L-21 |
| K14 | 리스트 컬럼 `SELECT ? UNION SELECT 'a'` | 문자열 미러 → VARCHAR, collation 은 리터럴 | C | |
| K15 | `COALESCE(CAST(? AS DATETIME), ?)` 결과 | 비문자 결과에 collation 플래그 잔존 가능 | A | L-19 |
| K16 | 컬렉션 원소 슬롯 `{?, 'a'}` | 원소 LEAVE 는 pd:2262 에서 NORMAL 로 확정 | C | |

---

## 6. 결론 — 규칙표(#317)가 답해야 할 "애매" 부류 목록

파서 인벤토리에서 **A(애매)** 로 남는 것은 결국 여섯 부류다. 나머지는 이미 컴파일(C) 또는 값 타입 하나로(G) 확정된다.

1. **늦은 바인딩 연산자의 슬롯**(`pt_is_op_hv_late_bind` 목록 전부): 산술 `+ - * /`·단항·`ROUND/TRUNC/ABS/CEIL/FLOOR`, `IFNULL/NVL/NVL2/COALESCE/NULLIF/LEAST/GREATEST`, `TO_CHAR/TO_DATE…/STR_TO_DATE/ADDTIME/FROM_TZ/NEW_TIME`, `HOUR/MINUTE/SECOND/BIT_LENGTH/OCTET_LENGTH/HEX/CONV/ASCII`, 세션변수. 이 목록을 **비우는 것**(모든 연산자를 미러/DOUBLE/VARCHAR 로 확정)이 D-M2 의 실체다. 연산자별로 `/`·`DIV`·`MOD` 는 정수 절삭 의미 때문에 `+ - *` 와 다른 행이어야 한다(A6·L-12).
2. **문맥 없는 슬롯**: `SELECT ?`, `? op ?`, `? op 리터럴`(산술만; 비교는 미러), `CASE ? WHEN ?`, `UNION/VALUES 양쪽 ?`, `ORDER BY ?`, `INSERT … SELECT ?`, 서브쿼리 컬럼 `?`. 문자 VARCHAR / 숫자 DOUBLE 의 갈림을 "표현 수단 제거"(PG) 로 볼지 규칙표가 정한다.
3. **ENUM/SET/컬렉션/객체**: `enum = ?`(TO_ENUMERATION_VALUE 안 VARIABLE), `enum < ?`(원소 없는 ENUM 도메인), `enum + ?`, `col IN ?`(SET). 미러 금지·서수 승격 행이 따로 필요(L-10).
4. **세션변수·PL/CSQL 인자**: 읽기 타입(저장 타입 vs VARCHAR 고정), PL 선언 타입 전달(PG `param_types`). 파서만 고쳐서는 안 잡힌다(L-32).
5. **함수 시그니처가 값을 요구하는 것**: `TO_CHAR` 값 슬롯(포맷 리터럴에서 추론 가능), `MEDIAN/PERCENTILE`(문자열 입력도 결과 MAYBE — 슬롯 없이도 애매), `ADDTIME/FROM_TZ/NEW_TIME` 오버로드, `SUM/MIN/MAX(?)`, `LEAD/LAG(?)`.
6. **collation 축**: 형제가 전부 슬롯인 문자 식(`? = ?`, `concat(?, ?)`, `upper(?)`)의 LEAVE 계약, 비문자 결과의 collation 플래그 잔존(L-19), 보간 정렬 키(L-21), `SET NAMES` 와 캐시 키(L-25). 슬롯 기본 collation 이 **바이너리(LANG_SYS_COLLATION)** 이지 클라이언트 collation 이 아니라는 점을 규칙표가 먼저 명시해야 한다(#322).

컴파일 확정(C) 이면서도 **현행 규칙 자체가 비직관적**이라 답안 변경 후보로 규칙표에 올릴 것: `IF(?, …)` 조건 슬롯 STRING(U15), `IFNULL` 둘 다 MAYBE → VARCHAR 이지만 한쪽 리터럴이면 MAYBE(U11·U12), 대칭 미러가 컬럼의 p/s·collation 을 버림(2.2 첫 행, `pt_xasl_type_enum_to_domain`) vs 비대칭 연산자는 완전한 도메인(비일관), `int_col < 1.5` 리터럴 DOUBLE vs `int_col < ?` INTEGER(B2·B5), auto-param 슬롯이 컬럼이 아니라 값 도메인(S12), UNION 의 NUMERIC 공통 p/s 를 (38,15) 로 고정(sc:334), CHAR 컬럼 `= ?` 의 VARCHAR 값 유지(B7).

---

## 7. 경험치 렛저 대응표

| L | 이 문서에서 다룬 곳 |
|---|---|
| L-10 (문맥 없는 슬롯 기본 하나로 → ENUM/SET/컬렉션 깨짐) | §1.7, §4.2 B13·B14, §4.5 S1, §6-2·3 |
| L-11 (NUMERIC 슬롯 고정 p/s) | §1.5 정밀도(11477: MAYBE→FLOATING), §2.4(`tp_value_cast_preserve_domain`), §4.1 A12 |
| L-12 (`+`/`-` 정수 고정 → 절단, `/` DOUBLE → 절삭 의미) | §4.1 A5·A6·A7, §6-1 |
| L-13 (`? + ?` 산술 고정 vs 접합, `? + 1`) | §1.5 PLUS, §4.1 A8 |
| L-14 (VARCHAR + 시스템 collation 승격 → 충돌; 도메인 축 ≠ collation 축) | §0-3, §3.3-5(ENFORCE 경로), §3.5, §5 K2·K4 |
| L-15 (세션변수 읽기 타입, 경로마다 다름) | §1.3 EVALUATE/DEFINE, §2.2 `@v` 행, §4.5 S3~S5 |
| L-16 (PL/CSQL 맨 `?`) | §2.1 표 3행, §4.5 S6 |
| L-17 (GENERIC 인자 일괄 고정 → `to_char(?, …)` 26건) | §1.3 TO_CHAR/ADDTIME/FROM_TZ, §4.4 F1~F7, §6-5 |
| L-18 (다중 행 VALUES `?`) | §1.10, §4.3 U4·U5 |
| L-19 (`coalesce(cast(? …), ?)` collation 플래그) | §4.3 U13, §5 K15 |
| L-20 (KEYLIMIT/LIMIT 슬롯) | §2.2 LIMIT 행, §4.5 S7·S8 |
| L-21 (MEDIAN/PERCENTILE 정렬 키) | §1.9, §4.4 F16·F17, §5 K13 |
| L-22 (auto-param 슬롯 도메인 ≠ 값) | §2.1 auto-param 단락, §4.5 S11·S12 |
| L-23 (답안 변경 목록: `SELECT ?`, `CASE ? WHEN ?`, `ifnull(?,1)`, CHAR `= ?`) | §4.3 U6~U12, §4.2 B7, §4.5 S1, §6 마지막 단락 |
| L-24 (미실행 문장 메타) | §4.5 S2 |
| L-25 (prepared 슬롯 collation 고정, `SET NAMES`) | §3.6, §5 K12 |
| E (PG 대조: param_types, 리터럴은 슬롯 아님, float8 preferred, unknown→text, collation 3단계) | §2.1(auto-param 은 PG 에 없음), §3.1(coercibility 8단계 vs PG 3단계), §6-2·4 |
