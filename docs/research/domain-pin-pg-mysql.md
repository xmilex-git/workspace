# PostgreSQL·MySQL 의 미확정 타입·혼합 타입·collation 결정 규칙 — CUBRID 대조표

지도: xmilex-git/workspace#312 · 티켓: #315 · 작성 2026-09-22 · 리드 직접 조사
기준 소스: PostgreSQL `REL_17_STABLE`(`github.com/postgres/postgres`), MySQL `8.0` 브랜치(`github.com/mysql/mysql-server`) — 로컬 소스가 없어 GitHub raw 를 읽었다.
CUBRID 현행은 `docs/research/domain-pin-rules-parser.md`(#313, `tc:`/`fc:`/`pd:` 표기 그대로) 와 `docs/research/domain-pin-exec-sites.md`(#314) 를 인용한다.

인용 표기: `pc:NNNN` = `src/backend/parser/parse_coerce.c`, `pp:` = `parser/parse_param.c`, `pcl:` = `parser/parse_collate.c`, `pf:` = `parser/parse_func.c`,
`pe:` = `parser/parse_expr.c`, `an:` = `parser/analyze.c`, `tcop:` = `tcop/postgres.c`, `plc:` = `utils/cache/plancache.c`, `prep:` = `commands/prepare.c`,
`eei:` = `executor/execExprInterp.c`, `pgtype:` = `include/catalog/pg_type.dat`, `pgcast:` = `include/catalog/pg_cast.dat`, `int.c:` = `utils/adt/int.c`.
MySQL: `mi:` = `sql/item.cc`, `mih:` = `sql/item.h`, `mf:` = `sql/item_func.cc`, `mfh:` = `sql/item_func.h`, `mc:` = `sql/item_cmpfunc.cc`,
`mfld:` = `sql/field.cc`, `mfldh:` = `sql/field.h`, `msp:` = `sql/sql_prepare.cc`, `msr:` = `sql/sql_resolver.cc`; 매뉴얼은 8.0 Reference Manual 절 이름.

---

## 0. 한 장 요약

| 물음 | PostgreSQL | MySQL | CUBRID 현행(#313) | 새 지도(D-M1~M4)와의 거리 |
|---|---|---|---|---|
| 슬롯 타입을 **언제** 정하나 | **파스 분석 1회**. 미확정이면 PREPARE/Parse 에서 오류 (`pp:309`, `tcop:745`) | prepare 에서 문맥으로 확정(`mi:3755`), **execute 마다 실제 값 타입과 대조**해 비호환이면 **재준비**(`msp:2779`) | 컴파일에서 `expected_domain` 이 정해지면 그때, 아니면 MAYBE→실행이 값을 보고(#313 §0) | PG 와 같은 1-결정(컴파일) + 값 변환 1회(Bind) = **2-지점 모델 그대로**. MySQL 은 3-지점(실행 재준비) → D-M3 반례 |
| 값을 **어디서** 변환하나 | 서버 Bind 단계에서 `param_types[i]` 의 typinput 으로 1회(`tcop:1822~1885`); 실행기는 타입 일치만 검사(`eei:2563`) | execute 에서 `data_type_actual → data_type` 변환(`mih:4661~4685`) | CAS(클라이언트) `pt_set_host_variables`(pd:3072) | D-M4(서버 게이트 1회) = PG Bind 와 동형 |
| 값 타입에 따라 **의미**가 갈릴 수 있나 | **불가능**: 플랜은 `param_types` 로 고정, 값은 그 타입의 Datum 으로만 존재 | 가능하지만 억제: 비호환 값은 재준비(플랜이 바뀜)로 흡수(`msp:2790~2810`) | 가능(늦은 바인딩 연산자 전부) | 목적지 "경험치 (f)" = PG |
| 문맥 없는 슬롯(`SELECT ?`, `? + ?`) | **오류** "could not determine data type of parameter"(드라이버가 타입을 보내지 않으면) | 함수 기본형: 산술 **DOUBLE**(`mfh:820`), 그 밖 **VARCHAR**(`mih:1224`, `mih:1383`) | MAYBE(실행 결정) | 새 지도 DOUBLE/VARCHAR = **MySQL 의 기본형 규칙과 동일** |
| 숫자 혼합의 공통 타입 | 카테고리 안 **preferred = float8**(`pgtype:225`) 이 있을 때만 float8; int×numeric 은 **numeric**(`pc:1431~1443`, `pgcast:18~20`) | INT×INT→BIGINT, DECIMAL 섞이면 DECIMAL, REAL 섞이면 DOUBLE(`mf:1477~1506`) | SMALLINT<INT<BIGINT<FLOAT<DOUBLE, NUMERIC×정수→NUMERIC(tc:10650~) | 세 DB 모두 **정확 타입끼리는 DOUBLE 로 가지 않는다** → DOUBLE 은 "부류가 갈리는 조합"의 폴백으로만(§4) |
| 문자 × 숫자 | 산술·비교 모두 **오류**(unknown 리터럴만 상대 타입으로 입력 파싱) | 비교·산술 **DOUBLE**(`mi:9339~9351`, `mih:139~146`; 매뉴얼 "Type Conversion") | 비교 시그니처 후 실행 값 비교, `pt_common_type` 격자 2 = DOUBLE(tc:10635) | 새 지도의 DOUBLE 은 MySQL·CUBRID 격자와 같은 편 |
| 정수 나눗셈 `/` | int/int → **int 절삭**(`int.c:862`) | int/int → **DECIMAL**(`mf:2472~2476`) | 정수 절삭(oracle 호환 시 NUMERIC, tc:11304) | 두 DB 모두 `/` 를 산술 공통 타입과 **다른 행**으로 둔다(L-12 지지) |
| unknown 리터럴만 있는 UNION/CASE | **text**(`pc:1457`) | 리터럴은 타입이 있어 해당 없음 | MAYBE 슬롯끼리 → MAYBE | VARCHAR 폴백 = PG unknown→text 와 동형 |
| collation 결정 | 파스 분석에서 4-상태(`pcl:58~61`), 충돌은 **컴파일 오류**(사용 지점에서) | resolve 에서 7-derivation 병합(`mfldh:179~187`, `mi:2429`), 충돌은 오류/NONE | 8-레벨 + LEAVE(실행 결정) | 두 DB 모두 **실행에 collation 을 미루지 않는다** → LEAVE 계약 제거(#322) 근거 |
| auto-param(리터럴→슬롯) | 없음 | 없음 | 있음(ap:41), 슬롯 도메인 = 리터럴 값 도메인 | 대응물 없음. L-22 는 CUBRID 고유 문제 |

결론 한 줄: **결정 시점·값 변환 위치·"값이 의미를 못 바꾼다" 는 PG 의 모델을, 문맥 없는 슬롯의 DOUBLE/VARCHAR 기본형은 MySQL 의 규칙을 따르는 것**이 새 지도다. 반례는 §4.

---

## 1. PostgreSQL

### 1.1 unknown 리터럴과 파라미터의 정체

- 따옴표 리터럴은 `UNKNOWNOID` 로 시작한다. `can_coerce_type` 은 unknown 을 **어떤 타입으로든** 강제 가능으로 본다(`pc:590~594`). 실제 변환은 `coerce_type` 이 대상 타입의 **typinput** 을 호출해 상수를 새로 만든다(`pc:233~250`, 주석: `int4` 의 typinput 은 "1.2" 를 거부하지만 float→int 캐스트는 반올림한다 — 즉 리터럴 파싱과 타입 캐스트는 다른 함수).
- 파라미터 `$n` 은 드라이버가 타입 OID 를 보내면 그 타입(`pp:99~116` 고정 파라미터), 0 을 보내면 `UNKNOWNOID` 로 시작한다(`pp:131~160`). 파스 분석 중 어떤 연산자/함수가 그 Param 을 타입 T 로 강제하려 하면 `variable_coerce_param_hook` 이 **처음 한 번만** `param_types[n] = T` 로 기록하고, 두 번째 사용이 다른 타입이면 `inconsistent types deduced for parameter $n` 오류(`pp:186~226`). 분석이 끝난 뒤 남아 있는 unknown 은 `could not determine data type of parameter $n`(`pp:296~311`, `tcop:735~745`; SQL `PREPARE` 도 같은 경로 `prep:117`).
- 결과: **슬롯의 타입은 파스 분석 한 번으로 확정되고, 확정 못 하면 컴파일 오류**. 실행이 값을 보고 정하는 경로가 없다.

### 1.2 공통 타입 `select_common_type` (`pc:1348`)

UNION/INTERSECT/EXCEPT(`an:2141~2204`), VALUES(`an:1592`), CASE 결과(`pe:1732`), COALESCE(`pe:2232`), GREATEST/LEAST(`pe:2282`), IN 리스트(`pe:1187`), ARRAY(`pe:2101`) 가 모두 이 한 함수를 쓴다.

1. 모두 같은 타입이면 그 타입(`pc:1367~1383`; 도메인 타입이 살아남는 유일한 경로).
2. 첫 non-unknown 타입을 후보로 잡고, 다음 타입이 **다른 카테고리**면 오류 `"%s types %s and %s cannot be matched"`(`pc:1414~1429`). 카테고리는 `pg_type.typcategory`(숫자 N, 문자 S, 날짜 D …).
3. 같은 카테고리면: 후보가 **preferred 가 아니고**, 후보→새 타입은 implicit 강제 가능인데 반대는 불가일 때만 새 타입으로 옮긴다(`pc:1431~1443`). preferred 타입은 한번 잡히면 유지.
4. 전부 unknown 이면 **text**(`pc:1457~1458`, 주석: "a decision has to be made now" — 실행 시 unknown 변환은 없다).

카테고리별 preferred(`pgtype`): N=**float8**(225), S=**text**(83), D=**timestamptz**(308), T=interval(315), B=bool(36), V=varbit(340).
숫자 캐스트 격자(`pgcast:18~20` 주석): implicit 방향은 `int2→int4→int8→numeric→float4→float8`, 역방향은 assignment 전용. 따라서:

| 조합 | 결과 | 이유 |
|---|---|---|
| int4 ∪ int8 | int8 | int4→int8 implicit, 역 불가 |
| int4 ∪ numeric | **numeric** | numeric 은 preferred 가 아니지만 int4→numeric 만 implicit |
| numeric ∪ float8 | float8 | numeric→float8 implicit + float8 preferred |
| int4 ∪ float4 | float4 | 후보를 옮긴 뒤 float8 이 안 나오면 그대로 |
| text ∪ int4 | **오류** | 카테고리 S≠N |
| 'abc' ∪ 'def' | text | 전부 unknown |

typmod(정밀도·길이) 는 모든 입력이 같을 때만 유지, 하나라도 다르면 -1(무제한)(`pc:1650~1680`) — CUBRID 의 UNION NUMERIC (38,15) 고정(sc:334)과 다른 정책이다.

### 1.3 연산자·함수 해소에서 unknown 과 preferred (`pf:1063`)

`int4_col + '1.5'` 처럼 한쪽이 unknown 이면 먼저 **알려진 쪽 타입을 unknown 에 그대로 대입**해 정확 일치 후보를 찾고(`pf:1360~1392` 주석, `binary_oper_exact`), `int4 + int4` 가 선택되어 `'1.5'` 는 `int4in` 에서 **오류**. 후보가 여럿 남으면 (a) 정확 일치 수, (b) 강제가 필요한 자리에서 **같은 카테고리의 preferred 타입**을 받는 후보(`pf:1160~1170`; 7.4 부터 교차 카테고리 preferred 는 무시), (c) unknown 자리는 다른 인자의 카테고리를 따르고 그 안의 preferred 우선(`pf:1228~1240`). 즉 `int4 + numeric` 은 (a) 에서 `numeric + numeric`(정확 1) 이 이겨 **numeric**, float8 은 float8 인자가 실제로 있을 때만 결과가 된다. **문자 타입 컬럼 vs 숫자**(`text_col = 1`) 는 카테고리가 달라 후보가 없어 오류.

정수 나눗셈은 `int4div` 가 **절삭**(`int.c:862~896`), numeric 나눗셈은 결과 scale 을 `select_div_scale` 이 정한다(`numeric.c:9831`). `/` 의 결과 타입은 인자 타입의 연산자 오버로드가 정하므로 별도 "공통 타입" 규칙이 없다.

### 1.4 Bind·실행: 값이 의미를 바꿀 수 없는 구조

- `exec_bind_message`(`tcop:1631`)는 파라미터마다 `ptype = psrc->param_types[paramno]`(`tcop:1822`)의 typinput/typreceive 를 호출해 **그 타입의 Datum 을 만든다**(`tcop:1885`, `1944`). 클라이언트는 텍스트/바이너리 바이트만 보내고, 변환은 서버 Bind 단계 1회다.
- 실행기의 `ExecEvalParamExtern`(`eei:2540`)은 `prm->ptype == op->d.param.paramtype` 이 아니면 `"type of parameter %d (%s) does not match that when preparing the plan (%s)"` 오류(`eei:2563`) — 실행 중 값 타입은 **검사 대상이지 결정 입력이 아니다**.
- 플랜 캐시: `CompleteCachedPlan` 이 `param_types` 를 복사해 소스에 고정(`plc:374`, `456~457`). Bind 값은 `choose_custom_plan`(`plc:1054`)이 **generic/custom 플랜 선택**과 custom 플랜의 상수 폴딩에만 쓴다(`plc:898~906` 주석). 값이 타입·의미를 바꾸는 경로는 없다. 이것이 렛저 E 의 "값 타입에 따른 의미 분기가 구조적으로 불가능" 의 실체다.

### 1.5 collation derivation (`pcl:`)

- 4 상태: `COLLATE_NONE`(비문자) / `COLLATE_IMPLICIT` / `COLLATE_CONFLICT` / `COLLATE_EXPLICIT`(`pcl:58~61`). Var·Const·**Param** 은 타입이 collatable 이면 그 타입의 기본 collation 을 **IMPLICIT** 로 낸다(`pcl:538~563`; Param 의 collation 은 `param_types` 의 타입 기본값 = DB 기본 collation).
- 병합(`merge_collation_state`, `pcl:780`): 강한 상태가 이김(EXPLICIT > CONFLICT > IMPLICIT > NONE). IMPLICIT 끼리 다르면 **DEFAULT collation 이 진다**(`pcl:815~820`); 둘 다 non-default 면 즉시 오류가 아니라 **CONFLICT 로 올려두고** 부모가 collation 을 실제로 쓸 때(비교·정렬·집합 연산·함수 인자) 오류(`pcl:827~838`, `471~475`, `222~228`: `collation mismatch between implicit collations`). EXPLICIT 끼리 다르면 즉시 오류(`pcl:850~855`).
- 결과: **슬롯의 collation 은 컴파일에서 DB 기본으로 확정되고, 컬럼(non-default IMPLICIT) 옆에서는 컬럼 collation 이 이긴다.** 실행에 넘기는 "미정" 상태가 없다. 세션 파라미터로 클라이언트 collation 을 바꾸는 개념(CUBRID `SET NAMES … COLLATE`)이 없어 L-25 부류의 캐시 키 문제도 없다.

---

## 2. MySQL 8.0

### 2.1 숫자 혼합·문자×숫자

- 산술(`Item_num_op::set_numeric_type`, `mf:1477~1506`): 두 인자의 `numeric_context_result_type` 이 하나라도 REAL 이면 **DOUBLE**, 아니면 하나라도 DECIMAL 이면 DECIMAL, 둘 다 INT 면 BIGINT. `numeric_context_result_type` 은 **문자열을 REAL 로 본다**(`mih:139~146`) → `'3' + 1` 은 DOUBLE. 날짜형은 소수부 유무로 INT/DECIMAL.
- 나눗셈(`Item_func_div::resolve_type`, `mf:2453~2485`): INT_RESULT 면 **DECIMAL 로 바꾼다**(`mf:2472~2476`, `div_precincrement` 로 scale 증가). `DIV` 는 정수, `MOD` 는 `mf:2652`.
- 비교(`item_cmp_type`, `mi:9339~9351`): 같은 부류면 그 부류(문자끼리는 문자 비교, 정수끼리는 정수), INT/DECIMAL 조합은 DECIMAL, **그 밖 전부 REAL(double)**. `Item_bool_func2::resolve_type` 이 인자 둘의 `cmp_context` 를 이 값으로 고정(`mc:647~649`). 매뉴얼 "Type Conversion in Expression Evaluation" 의 규칙 목록("In all other cases, the arguments are compared as floating-point (double-precision) numbers … a comparison of string and numeric operands takes place as a comparison of floating-point numbers") 과 일치. TIMESTAMP/DATETIME **컬럼** vs 상수는 상수를 날짜로 변환(`convert_constant_arg`, `mc:672~677`; IN 은 예외).
- UNION 결과 타입은 `field_types_merge_rules` 표(`mfld:251`, `Field::field_type_merge` `mfld:1240`): DECIMAL×정수→DECIMAL, DECIMAL×FLOAT/DOUBLE→DOUBLE, 숫자×TIMESTAMP/문자→VARCHAR.
- 매뉴얼이 명시한 부작용: "Comparisons between floating-point numbers and large integer values are approximate because the integer is converted to floating-point" — DOUBLE 비교의 정밀도 손실(§4 반례 (d)).

### 2.2 collation coercibility

- 7 단계 derivation(`mfldh:179~187`): EXPLICIT=0 < NONE=1 < IMPLICIT=2 < SYSCONST=3 < COERCIBLE=4 < NUMERIC=5 < IGNORABLE=6. 매뉴얼 "Collation Coercibility in Expressions": COLLATE 절 0, 서로 다른 collation 접합 1, 컬럼/루틴 파라미터/지역변수 2, 시스템 상수 3, 리터럴 4, 숫자·시간 값 5, NULL 6. 규칙: **낮은 값이 이긴다**; 같으면 둘 다 Unicode(또는 둘 다 비 Unicode)면 오류, 한쪽만 Unicode 면 Unicode 쪽으로 변환.
- `DTCollation::aggregate`(`mi:2429~2510`): EXPLICIT 끼리 다르면 오류; charset 이 다르면 binary 우선 → superset 변환 허용 플래그 → coercible 변환 허용 플래그 순, 안 되면 `DERIVATION_NONE`(사용 지점에서 "Illegal mix of collations"); 같은 charset·같은 derivation·다른 collation 이면 `_bin` 이 이기고 둘 다 `_bin`(패딩/비패딩)이면 NONE.
- 파라미터: `Item_param::fix_fields` 가 값 없을 때 **연결 기본 collation**(`default_charset()`)을 준다(`mi:3701~3709`); 문맥 전파 시 형제의 collation 을 받는다(`mi:3781~3785`: VARCHAR 최대 길이 + `type.m_collation`). LIKE 는 인자 공통 collation 의 VARCHAR 로 전파(`mc:691~696`). 세션변수 `@v` 읽기는 **prepare 시점의 저장 값 타입·collation** 을 그대로 쓰고 IMPLICIT(`mf:6735~6790`).

### 2.3 prepared statement 파라미터 — 3-속성 모델과 재준비

`Item_param` 은 세 타입을 갖는다(`mih:4661~4685`): (1) `data_type()` = 문맥(CAST·연산자·형제)이 정한 **해소 타입**, (2) `data_type_source()` = 프로토콜/유저변수가 준 값 타입, (3) `data_type_actual()` = 변환 후 실제 타입. 흐름:

1. **prepare**: 각 연산자의 `resolve_type` 이 슬롯에 타입을 전파한다. 공통 헬퍼 `param_type_uses_non_param_inner`(`mf:558~605`): 인자 중 **타입 있는 첫 인자**를 기준으로 나머지 슬롯에 같은 타입을 주고, 전부 슬롯이면 함수별 기본형 `def` 를 준다. 기본형: 산술 `Item_func_numhybrid::default_data_type` = **DOUBLE**(`mfh:820`; 두 인자 모두 슬롯이면 `resolve_type` 이 미루고 `msr:5429~5430` 등이 기본형 전파), 비교·문자 함수·SELECT 리스트·ORDER BY = **VARCHAR**(`mih:1224~1236`, `mih:1383~1387`, `msr:4614~4615`, `4729~4730`; `Item_int_func` 주석 "VARCHAR is the best default" `mfh:~989`), LIMIT/OFFSET = LONGLONG **pinned**(`msr:903~918`), LIKE = VARCHAR + 비교 collation(`mc:691~696`). 인자 자리에 슬롯을 금지하는 함수도 있다(`param_type_is_rejected`, `mf:535~545`, `ER_INVALID_PARAMETER_USE`).
   `propagate_type`(`mi:3755~3800`): 정수 부류→LONGLONG(부호 포함), DECIMAL→**(65,30) 최대 정밀도**, FLOAT/DOUBLE→DOUBLE, 문자·ENUM·SET→**VARCHAR 최대 길이 + 형제 collation**, BLOB→BLOB, JSON/GEOMETRY 고정. 즉 **컬럼을 미러하되 p/s·길이는 버리고 최대치로** 잡는다(CUBRID 대칭 미러가 p/s·collation 을 버리는 것과 비슷하되 collation 은 보존).
2. **execute**: `insert_params` 가 값을 넣고(`msp:699~810`; 문자열은 actual VARCHAR + 클라이언트 charset `msp:768~770`) `check_parameter_types`(`msp:2779~2890`) 가 해소 타입 vs actual 을 대조한다 — inherited(CAST 안, `mih:4649`)·pinned(`mih:4660`)·NULL 은 항상 통과; **문자열 값은 어떤 해소 타입에도 변환으로 수용**(단 정수 해소 타입에 정수 범위 밖 문자열이 오면 DECIMAL 로 **재준비**, `msp:2811~2840` 주석의 `'18446744073709551615'` 예), 정수 해소 타입은 정수 값만(부호 일치), DECIMAL 은 정수/DECIMAL 만, DOUBLE 은 정수/DECIMAL/DOUBLE 을 수용하고 그 밖은 `false` → `ask_to_reprepare`(`msp:2207`) 로 **문장을 다시 준비**한다(그때 `fix_fields` 가 actual 타입으로 슬롯 타입을 잡는다, `mi:3701~3750`).
3. 결과: 슬롯 타입은 prepare 에서 정해지지만 **실행이 값 타입을 보고 플랜을 바꿀 수 있다**(재준비). 값이 실행 중 의미를 갈라놓지는 않지만, 결정 지점이 3곳(prepare·execute 대조·재준비)이다.

---

## 3. 항목별 대조표 — CUBRID 현행과 갈리는 곳

| # | 항목 | PG | MySQL | CUBRID 현행(#313) | 새 지도가 택할 편 / 근거 |
|---|---|---|---|---|---|
| T1 | 슬롯 타입 확정 시점 | 파스 분석 1회, 미확정 = 오류 | prepare(문맥/기본형) + execute 대조 + 재준비 | 컴파일(expected_domain) 또는 실행(MAYBE) | **PG**: 컴파일 1회. 미확정 슬롯은 오류 대신 DOUBLE/VARCHAR 폴백(MySQL) — 오류(PG)로 갈지 규칙표 결정(#317, 답안 변경 항목) |
| T2 | 바인드 값 변환 위치 | 서버 Bind(typinput) 1회 | 서버 execute(actual→resolved) | **CAS(클라이언트)** pd:3072 | **PG**(D-M4). 클라이언트는 바이트만 보낸다 |
| T3 | 실행 중 값 타입 검사 | 타입 불일치 = 오류(`eei:2563`) | 재준비 | 값 타입으로 도메인 결정(S-01~S-43, #314) | PG: 게이트 뒤 "값 타입 = 계획 도메인" 불변식 + assert(L-22·L-49) |
| T4 | `col op ?` (비교) | `$n` = col 타입(정확 일치 후보) | col 타입 미러(p/s·길이는 최대) | col 기본 도메인 미러(p/s·collation 버림, LEAVE) | 셋 다 미러. **p/s 유지 여부**만 다름 — 규칙표 행(L-11: 캐스트는 타입만, 값 p/s 보존) |
| T5 | `int_col < 1.5` / `int_col < ?` | 리터럴 numeric → `int4 < numeric` 오버로드(정확 비교) / `$n` = int4 | 리터럴 DECIMAL 비교 / `?` = BIGINT | 리터럴 DOUBLE(tc:5566) / `?` INTEGER(B2·B5) | 두 DB 모두 **리터럴과 슬롯의 타입이 다르다**(리터럴은 자기 타입, 슬롯은 컬럼 미러). CUBRID 의 비일관은 "리터럴이 DOUBLE" 쪽. 규칙표는 리터럴 행과 슬롯 행을 분리 |
| T6 | `col + ?` (산술) | `$n` = col 타입 | `?` = col 타입 (`param_type_uses_non_param`) | **MAYBE**(늦은 바인딩, tc:9010) | **미러**(두 DB). `i1 - ?` 에 1.1 바인드 → 절단은 PG/MySQL 도 동일(정수 슬롯) — L-12 의 "조용한 오답" 은 두 DB 의 정상 동작. 규칙표가 미러(정수) vs DOUBLE 중 택일하고 답안 변경으로 기록 |
| T7 | `? + ?`, `? + 1` | 오류(미확정) / `$n` = int4 | 둘 다 **DOUBLE**(`mfh:820`) / `?` = 리터럴 타입 | MAYBE; 접합 가능(plus_as_concat) | MySQL: DOUBLE 폴백. 접합 의미(L-13) 는 두 DB 모두 없음 → 표현 수단 제거 + 매뉴얼 |
| T8 | `/` `DIV` `MOD` | int/int 절삭, 오버로드별 | int/int → DECIMAL, DIV 정수 | 절삭(oracle 모드 NUMERIC) | 두 DB 모두 `/` 가 `+ - *` 와 **다른 행**. DOUBLE 공통 타입을 `/` 에 적용하면 세 DB 어디와도 다른 의미가 된다(L-12) |
| T9 | 문자 × 숫자 비교 | **오류**(카테고리 불일치) | DOUBLE 비교 | 격자 2 DOUBLE(tc:10635), 비교는 값 비교 | MySQL/CUBRID 편(DOUBLE). PG 처럼 오류로 갈 수 없음(호환) |
| T10 | 문자 × 숫자 산술 | 오류 | DOUBLE | `-`/`*` 는 NONE(오류), `+` 는 접합 | 규칙표 결정. MySQL 을 따르면 DOUBLE, `+` 접합은 별도 파라미터 의미 |
| T11 | UNION/CASE/COALESCE/VALUES 공통값 | `select_common_type` 한 함수, 카테고리 다르면 **오류**, 전부 unknown → text | 병합 표(VARCHAR 수렴), 슬롯 기본 VARCHAR | 시그니처(IFNULL 부류 다르면 VARCHAR), MAYBE 슬롯은 실행 | 두 DB 모두 **한 함수/표로 컴파일 확정**. 슬롯만 있으면 VARCHAR(MySQL) = 새 지도 VARCHAR 폴백. 다중 행 VALUES 의 `?` 는 첫 행 타입 미러(PG `an:1592`, MySQL `msr:5429` 는 기본형) → L-18 |
| T12 | IN 리스트 `col IN (?, ?)` | LHS 타입이 우선(`pe:1180~1187` 주석) | LHS 타입 미러 | 컬럼 타입 expected_domain(tc:5106) | 일치 |
| T13 | `SELECT ?`, `ORDER BY ?` | 오류 | VARCHAR(`msr:4729`, `4614`) | MAYBE(VARIABLE) | MySQL VARCHAR 폴백. 답안 변경(L-23) |
| T14 | `LIMIT ?` | int8 (`$n` = bigint) | LONGLONG pinned | BIGINT(tc:7290) | 일치 |
| T15 | 함수 인자 슬롯(`to_char(?, 'fmt')`) | 오버로드 해소: unknown 은 알려진 인자 카테고리·preferred → `to_char(numeric,text)`/`(timestamp,text)` 둘 다 남으면 **ambiguous 오류** | 함수별 `resolve_type` 이 기본형 지정(대개 VARCHAR) | 늦은 바인딩 MAYBE | PG: 모호하면 오류·명시 CAST. MySQL: 함수별 기본형 표. 규칙표 §6-5 는 **함수 시그니처별 기본형 행**(L-17) + 모호 시 오류 중 택일 |
| T16 | NULL 바인드 | `param_types` 타입의 NULL(typed NULL) | 모든 해소 타입에 수용(`msp:2794`) | 계약별 상이(L-16) | typed NULL 수용(두 DB 일치) |
| T17 | ENUM | ENUM 은 자기 타입, 숫자와 비교 불가(오류) | ENUM 슬롯 → VARCHAR(`mi:3781`), 정수 문맥은 서수 | TO_ENUMERATION_VALUE 안 VARIABLE / 원소 없는 ENUM | 두 DB 모두 "값 타입에 따라 서수/사전식 갈림" 없음. MySQL: 문자 미러. L-10 행 |
| T18 | 세션변수 읽기 | 없음(PG 세션변수는 `current_setting` text) | prepare 시점 저장 타입·collation, 재대입은 다음 prepare 에서 | 항상 MAYBE(tc:3945) | MySQL 모델 = "저장 타입 + 플랜 stale" 문제(L-15) 를 그대로 가진다(재준비로 흡수). 규칙표 결정 |
| T19 | PL 인자 | 드라이버/PL 이 `param_types` 를 보낸다(SPI 는 선언 타입 전달) | 루틴 파라미터 = coercibility 2, 타입 선언 | 맨 `?`(L-16) | PG `param_types` 모델(선언 타입 전달) |
| T20 | auto-param | 없음 | 없음 | 리터럴 값 도메인 슬롯 | 대응물 없음. 게이트가 값을 계획 도메인으로 변환하면 L-22 소멸 |
| T21 | 슬롯 collation 기본 | 타입 기본(DB 기본) IMPLICIT, 컬럼(non-default)이 이김 | 연결 기본 collation, 형제가 있으면 형제 것 | LANG_SYS(바이너리) + LEAVE, 형제가 있으면 ENFORCE | 두 DB 모두 **컴파일 확정**. 기본이 "바이너리" 인 DB 는 없다(#322 입력) |
| T22 | collation 충돌 | 컴파일 오류(사용 지점) | resolve 오류/NONE | -1150 컴파일 오류 | 일치 |
| T23 | 결과 collation 의 실행 결정 | 없음 | 없음 | LEAVE 계약(형제가 전부 슬롯) | **제거 근거**(L-47) |
| T24 | `SET NAMES` 와 prepared 문 | 개념 없음 | `character_set_connection` 은 prepare 시점에 리터럴·슬롯에 박힘, 재준비 때 재적용 | 캐시 키 텍스트가 collation 을 생략 인쇄(L-25) | MySQL 도 "prepare 시점 고정". 재컴파일 트리거는 규칙표 |
| T25 | 미실행 문장 컬럼 메타 | 컴파일 확정이라 없음 | 컴파일 확정이라 없음 | (0,0)/VARIABLE 잔존(L-24) | 컴파일 확정이면 소멸 |

---

## 4. DOUBLE/VARCHAR 공통 타입 — 근거와 반례

**근거**

- (a) MySQL 은 "부류가 갈리는 조합"을 전부 DOUBLE 로 비교·연산한다(§2.1, 매뉴얼 명문). CUBRID `pt_common_type` 격자 2·4 도 이미 DOUBLE 이다(tc:10635, 10645). 즉 DOUBLE 은 CUBRID 격자의 **기존 답을 슬롯까지 확장**하는 것이다.
- (b) PG 의 숫자 카테고리 preferred 가 float8, 문자 카테고리 preferred 가 text 이고 unknown 만 있으면 text 다(§1.2). "애매하면 float8/text" 는 PG 의 카테고리 규칙과 같은 방향이다.
- (c) 문맥 없는 슬롯의 기본형이 MySQL 은 산술 DOUBLE·그 밖 VARCHAR(§2.3) — 새 지도의 폴백과 **정확히 같다**.

**반례·주의 (규칙표 #317 이 행으로 답해야 할 것)**

- (d) **정확 타입끼리는 어느 DB 도 DOUBLE 로 가지 않는다**: PG `int4 ∪ numeric` = numeric, `int4 + numeric` = numeric; MySQL INT×DECIMAL = DECIMAL, UNION 도 DECIMAL. DOUBLE 을 "숫자 전부의 공통 타입" 으로 적용하면 BIGINT 정밀도·NUMERIC 표기(L-11)가 세 DB 어디와도 다른 답이 된다. → DOUBLE 은 **부류가 갈리거나(문자×숫자) 문맥이 없을 때**의 폴백으로 한정(D-M2 "애매한 것들" 의 정의).
- (e) **슬롯은 형제를 미러하는 것이 두 DB 의 첫 규칙**이고 DOUBLE/VARCHAR 는 형제가 없을 때만이다(PG `pf:1360~1392`, MySQL `mf:558~605`). `int_col = ?` 에 문자열 바인드 → PG 는 int4 typinput, MySQL 은 정수 해소 타입에 문자열 수용(변환). MySQL 매뉴얼이 "문자 vs 숫자 비교는 double" 이라 한 것은 **컬럼끼리/리터럴** 얘기지 슬롯이 아니다. MySQL 이 `'18446744073709551615'` 문자열 바인드에 재준비까지 하는 이유(`msp:2802~2810` 주석)가 바로 "슬롯을 DOUBLE 로 비교하면 정수 컬럼 비교가 틀린다" 다.
- (f) **`/` 는 별도 행**: PG 절삭, MySQL DECIMAL. 산술 공통 타입 DOUBLE 을 `/` 에 그대로 쓰면 CUBRID 정수 절삭 의미가 깨진다(L-12 회귀의 재현). `DIV`/`MOD` 는 두 DB 모두 정수 유지.
- (g) **문맥 없는 슬롯 = 오류(PG) vs 기본형(MySQL)**: PG 는 드라이버가 타입을 보내므로(`param_types`) 실무에서는 드라이버 타입이 곧 슬롯 타입이다. CUBRID 드라이버(JDBC/CCI)는 prepare 때 타입을 보내지 않고 execute 때 값과 함께 보낸다 → PG 모델을 온전히 옮기려면 **프로토콜 변경**(prepare 에 타입 힌트) 이 필요하다. 그 전까지는 MySQL 기본형(DOUBLE/VARCHAR)이 유일한 현실적 선택이고, PL/CSQL 은 정적 타입을 알고 있으므로 PG `param_types` 모델을 그대로 적용할 수 있다(L-16·T19).
- (h) **재준비는 3번째 결정 지점**: MySQL 은 값 타입이 해소 타입과 비호환이면 재준비한다. D-M3(결정 2곳) 아래서는 재준비 대신 **게이트 변환 실패 = 오류**(PG typinput 실패와 동형)여야 한다. "문자열 값은 어떤 타입에도 변환 수용" 은 두 DB 공통(PG typinput, MySQL `msp:2811`) → 게이트의 VARCHAR→계획 도메인 변환은 허용, 실패는 -494 부류 오류(bind 시점이 아니라 **게이트 시점**으로 이동, L-23 답안 변경).
- (i) **collation**: DOUBLE/VARCHAR 는 타입 축이고 collation 축은 별개(L-14). 두 DB 모두 슬롯 collation 을 컴파일에서 **DB/연결 기본**으로 확정하고 non-default 형제가 이긴다. CUBRID 의 "기본 = LANG_SYS 바이너리" 는 어느 DB 에도 없다; VARCHAR 폴백을 채택하면 그 collation 을 **클라이언트(연결) collation** 으로 둘지 LANG_SYS 로 둘지가 #322 의 첫 행이다. 실행 결정(LEAVE) 은 두 DB 모두 없다.
- (j) **typmod/p·s**: PG 는 공통 typmod 가 다르면 -1(무제한), MySQL 슬롯은 최대 정밀도(65,30)/최대 길이. CUBRID 가 NUMERIC 슬롯을 (38,15) 로 고정하면 값 scale 이 깎인다(L-11) → 캐스트는 타입만, p/s 는 값 보존(`tp_value_cast_preserve_domain` 유지) 이 두 DB 관행과 맞다.

---

## 5. 2-지점 모델(컴파일 + 서버 게이트)의 근거

- PG 가 정확히 이 모형이다: 결정 = 파스 분석(`param_types`), 변환 = Bind(`tcop:1822~1944`), 실행 = 검사만(`eei:2563`). 플랜 캐시는 값과 무관한 generic 플랜을 유지하고 값은 플랜 **선택**에만 쓴다(`plc:1054`). PX 워커에 해당하는 병렬 워커도 같은 `ParamListInfo` 를 직렬화해 상속받을 뿐 결정하지 않는다(D-M3 의 "워커는 계획 상속").
- MySQL 은 결정 지점이 하나 더 있다(execute 대조·재준비). 이는 드라이버가 prepare 에 타입을 보내지 않는 프로토콜의 대가다 — CUBRID 도 같은 프로토콜 제약을 가지므로, **재준비 대신 기본형(DOUBLE/VARCHAR) + 게이트 변환 실패 오류**로 3번째 지점을 없애는 것이 새 지도의 선택이다. 그 비용은 "문맥 없는 슬롯에 예상 밖 타입을 바인드하면 오류 또는 DOUBLE/VARCHAR 의미" 이며 답안 변경으로 기록한다.

---

## 6. 경험치 렛저·#313 애매 부류 대응표

| 항목 | 이 문서에서 |
|---|---|
| L-10 (ENUM/SET 기본 하나로) | T17 — 두 DB 모두 값 타입 분기 없음, MySQL 은 문자 미러 |
| L-11 (NUMERIC p/s) | §4 (d)(j), T4 |
| L-12 (`+ -` 정수 고정, `/` 절삭) | T6, T8, §4 (f) |
| L-13 (`? + ?` 접합) | T7 |
| L-14 (도메인 축 ≠ collation 축) | §1.5, §2.2, §4 (i), T21~T23 |
| L-15 (세션변수) | T18 |
| L-16 (PL 맨 `?`) | T19, §4 (g) |
| L-17 (함수 인자 일괄 고정) | T15 |
| L-18 (다중 행 VALUES) | T11 |
| L-22 (auto-param) | T20 |
| L-23 (답안 변경: 오류 시점 이동) | §4 (h), T13 |
| L-24 (미실행 문장) | T25 |
| L-25 (`SET NAMES`) | T24 |
| L-47 (LEAVE 계약) | T23, §4 (i) |
| L-49 (플랜 도메인을 믿는 소비자) | T3 |
| 렛저 E (PG 요지) | §1 전체 — 재확인, 추가로 "`int+numeric` 은 numeric" 과 "unknown 리터럴은 typinput 으로 파싱(캐스트가 아님)" 을 보강 |
| #313 §6-1 늦은 바인딩 연산자 | T6·T7·T15: 두 DB 모두 미러 → 기본형 순서, 실행 결정 없음 |
| #313 §6-2 문맥 없는 슬롯 | T7·T13, §4 (c)(g) |
| #313 §6-3 ENUM/컬렉션 | T17 |
| #313 §6-4 세션변수·PL | T18·T19 |
| #313 §6-5 값 요구 함수 | T15 |
| #313 §6-6 collation | §1.5, §2.2, T21~T24 |
