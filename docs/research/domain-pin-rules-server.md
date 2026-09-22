# 서버 측 coerce·산술·비교·집계·키 변환 규칙 — 조합별 전수 인벤토리

지도: xmilex-git/workspace#312 · 티켓: #321 · 작성 2026-09-22 · 기준: CUBRID/cubrid `develop` `cad27172b`
짝 티켓: #313(파서 측 규칙, `domain-pin-rules-parser.md`) · #314(서버 지점 전수, `domain-pin-exec-sites.md`).
이 문서는 **무엇으로 변환되는가(규칙)** 만 다룬다. 어디서 결정하는가(지점)는 #314 가, 파서가 무엇을 확정하는가는 #313 이 맡는다.
경험치 렛저(`domain-pin-lessons.md`) 대응은 §7 표에 있다.

인용 표기: `od:NNNN` = `src/object/object_domain.c`, `op:NNNN` = `src/object/object_primitive.c`, `qo:NNNN` = `src/query/query_opfunc.c`,
`no:NNNN` = `src/query/numeric_opfunc.c`, `ar:NNNN` = `src/query/arithmetic.c`, `qe:NNNN` = `src/query/query_evaluator.c`,
`qa:NNNN` = `src/query/query_aggregate.cpp`, `qx:NNNN` = `src/query/query_executor.c`, `lf:NNNN` = `src/query/list_file.c`,
`sm:NNNN` = `src/query/scan_manager.c`, `bt:NNNN` = `src/storage/btree.c`, `fe:NNNN` = `src/query/fetch.c`,
`dm:NNNN` = `src/compat/db_macro.c`, `dt:NNNN` = `src/compat/dbtype_def.h`, `ls:NNNN` = `src/base/language_support.h`.

---

## 0. 한 장 요약 — 서버는 "값의 타입"만 보고 네 겹의 규칙으로 변환한다

```
① 범용 coerce   tp_value_cast_internal (od:6992)          (원 타입 × 목표 타입) 표 + 상태 → 오류 코드 (od:11569)
② 산술          qdata_{add,subtract,multiply,divide}_dbval  값 타입 쌍으로 사전 캐스트 → 타입별 연산 → XASL 도메인으로 결과 coerce (qo:2383)
③ 비교          tp_value_compare_with_error (od:10419)      ARE_COMPARABLE 아니면 방향 규칙으로 임시 강제변환 → 같은 타입 cmpval
④ 집계·정렬·키   누산 도메인 = 첫 값 도메인(qx:21504) / 정렬 = 리스트 컬럼 도메인 cmpdisk 무변환(lf:4289) / 키 = strict-or-keep (sm:1871)
```

핵심 사실 다섯 가지:

1. **서버에는 "슬롯 도메인 → 값" 방향 변환이 없다.** 모든 규칙의 입력은 `DB_VALUE_DOMAIN_TYPE(값)` 이다. XASL 도메인(`regu_var->domain`)은 (a) 산술 **결과** 를 coerce 하는 목표(qo:2383·2728)로, (b) 집계 누산 도메인의 씨앗(`agg_p->domain`, qx:21592)으로, (c) 리스트 컬럼·정렬 키 도메인(lf:7078)으로만 쓰이고, VARIABLE 이면 실행이 값에서 **역으로** 도메인을 채운다(fe:1316·4463). #314 의 43 지점이 전부 이 방향인 이유다.
2. **coerce 표의 큰 규칙은 넷이다.** 숫자↔숫자는 ROUND(반올림)·오버플로 검사(od:7331~7920). 문자→숫자는 `tp_atof`/`tp_atobi`/`tp_atonumeric` 파싱(od:4851~5175): 공백 허용, 남은 문자 있으면 `DOMAIN_INCOMPATIBLE`(-494 `ER_TP_CANT_COERCE`), 범위 밖이면 `DOMAIN_OVERFLOW`(-493 `ER_IT_DATA_OVERFLOW`). 숫자→문자는 묵시 변환 **금지**(`TP_IMPLICIT_COERCION_NOT_ALLOWED`, od:5639: 문자→{문자·날짜·숫자·ENUM} 과 ENUM→문자만 허용). 문자→문자는 절단이면 `DOMAIN_OVERFLOW`(묵시) / `allow_truncated_string` 따라 허용(명시)(od:9195).
3. **산술은 "값 쌍 → 사전 캐스트 → 타입별 연산" 3단이고 결과 타입은 연산자마다 다르다.** 숫자+문자 → 문자를 DOUBLE 로(qo:2536), 날짜+실수/문자 → BIGINT 로(qo:2541), 문자+문자 → 둘 다 DOUBLE(`plus_as_concat` 아닐 때, qo:2547). 정수÷정수는 **정수 절삭**(qo:5718, `oracle_compat_number_behavior` 면 NUMERIC 으로, qo:6173). `DIV`/`MOD` 는 BIGINT 정수 연산(qo:8445). NUMERIC 결과 p/s 는 연산자별 공식(§2.1). ENUM 은 상대가 문자면 이름(VARCHAR), 아니면 서수(SMALLINT)(qo:2461~2470) — 단 `-`·`*`·`/` 는 **항상 서수**(qo:4838).
4. **비교는 ARE_COMPARABLE(같은 타입 또는 CHAR/VARCHAR 쌍, od:79) 이 아니면 매 비교마다 임시 변환한다.** 방향: 문자 vs 숫자 → 둘 다 DOUBLE(od:10524~10556), 문자 vs 날짜 → 문자를 날짜 타입으로(od:10557~10577), 그 외 → `db_type_rank` 순서(od:111)에서 더 일반적인 타입으로(od:10578). 변환 실패는 **오류가 아니라** `er_clear()` 뒤 rank 순서로 GT/LT 를 돌려준다(od:10627·10660 "Not Equal is as close as we can come"). 상수 피연산자는 `REGU_VARIABLE_FETCH_ALL_CONST` 면 첫 비교에서 **제자리** coerce 해서 반복 변환을 줄인다(qe:207).
5. **집계·정렬·키는 "첫 값" 이 도메인을 정한다.** SUM/AVG/MIN/MAX 의 누산 도메인은 첫 비-NULL 값의 도메인(qx:21592·21615); SUM(int) 누산은 INT 범위에서 오버플로 오류(qo:2812). 정렬은 리스트 컬럼 도메인의 `cmpdisk` 로 **무변환** 비교(lf:4289, do_coercion 0)이고 리스트 컬럼 도메인은 첫 튜플의 regu 도메인(lf:7078). 인덱스 키는 값을 인덱스 도메인으로 **strict 변환(손실 없을 때만)** 하고, 실패하면 값 도메인으로 새 setdomain 을 만들어(sm:1985·2102) 비교 때마다 강제변환한다(op:7676→od:10419).

---

## 1. 변환표 — `tp_value_cast_internal` (스코프 1)

### 1.1 진입 규칙 (od:6992~7328)

| 순서 | 규칙 | 근거 |
|---|---|---|
| 1 | `desired_domain == NULL` → `DOMAIN_INCOMPATIBLE`; 도메인 리스트면 `tp_domain_select` 로 값에 가장 맞는 것을 고름(`do_domain_select`) | od:7023~7038 |
| 2 | **NULL 은 항상 성공**: `preserve_domain` 이면 목표 도메인의 NULL(타입·p/s 유지), 아니면 순수 NULL | od:7044~7056 |
| 3 | JSON 원값은 스칼라(DOUBLE/INT/BIGINT/BOOL→INT 또는 "true"/"false"/STRING)로 먼저 벗긴다; MIDXKEY→문자는 인쇄 | od:7058~7130 |
| 4 | **같은 타입**: 비파라미터 도메인이면 클론. NUMERIC 은 p/s 가 같을 때만 클론(다르면 §1.3 으로), OID·JSON(validator 통과) 클론, **CHAR/VARCHAR 는 p/collation 이 달라도 같은 타입이면 §1.5 로 내려간다** | od:7133~7181 |
| 5 | 묵시 모드(`tp_value_coerce`/`tp_value_cast(…, true)`)에서 `TP_IMPLICIT_COERCION_NOT_ALLOWED` 면 `DOMAIN_INCOMPATIBLE`: **문자→(문자·날짜·숫자·ENUM 이외)**, **(문자·ENUM 이외)→문자**, LOB 관련 전부 | od:5639~5646, 7190 |
| 6 | 목표 초기화 `db_value_domain_init(target, type, p, s)` — NUMERIC 은 `DB_DEFAULT_PRECISION(-1)`→40, `DB_DEFAULT_SCALE(-9999)`→0 으로 바꾸고, 잘못된 p/s 면 경고 후 (40,0) | dm:155~197, dt:616~634 |
| 7 | 문자 목표의 collation: `COLL_ENFORCE` 면 문자 원값의 도메인을 복제해 목표 collation 만 덮음(정밀도는 **원값** 것), 컬렉션은 원소마다, 비문자 원값은 **그대로 클론하고 성공**; `COLL_NORMAL` 이면 목표 collation; `COLL_LEAVE` 면 원값 collation 유지 | od:7229~7328 |

`tp_value_cast_internal` 의 반환 상태 → 오류 코드(`tp_domain_status_er_set`, od:11569): `DOMAIN_INCOMPATIBLE` → `ER_TP_CANT_COERCE`(-494, "원타입 → 목표타입"), `DOMAIN_OVERFLOW` → `ER_IT_DATA_OVERFLOW`(-493, 목표 타입), `DOMAIN_ERROR` → `er_errid()` 가 -493 이면 OVERFLOW, 아니면 INCOMPATIBLE 로 **바꿔** 보고(JSON 오류만 원문 유지). 산술·집계 쪽 `tp_value_auto_cast`(od:11404) 는 실패 시 `return_null_on_function_errors=yes` 면 NULL 로 삼킨다.

### 1.2 목표 = 정수·실수 (SHORT/INTEGER/BIGINT/FLOAT/DOUBLE/MONETARY) (od:7331~7920)

| 원 타입 → | SHORT | INTEGER | BIGINT | FLOAT | DOUBLE | MONETARY |
|---|---|---|---|---|---|---|
| SHORT/INT/BIGINT | 범위 검사 후 캐스트, 넘치면 OVERFLOW | 〃 | 〃 | 손실 무검사 캐스트 | 〃 | 〃(기본 통화) |
| FLOAT/DOUBLE/MONETARY | **ROUND** 뒤 범위 검사 → OVERFLOW | 〃 | 〃 | DOUBLE→FLOAT 만 OVERFLOW 검사 | 무검사 | 무검사 |
| NUMERIC | `numeric_db_value_coerce_from_num`: DOUBLE 경유 **ROUND**, 범위 밖 → OVERFLOW(no:6619~6656) | 〃 | BIGINT 는 정수 경유(no:6635) | 〃 | 〃 | 〃 |
| CHAR/VARCHAR | `tp_atof` 파싱: 앞뒤 공백 허용, 남은 문자 → INCOMPATIBLE, ERANGE → OVERFLOW, 그 뒤 **ROUND**·범위 검사 | 〃 | `tp_atobi`: 16진(`0x`)·지수 표기 허용, 소수부는 **반올림**(od:4957 주석) | `tp_atof` | `tp_atof`(범위만) | `tp_atof` |
| ENUMERATION | **서수**(`db_get_enum_short`) | 〃 | 〃 | 〃 | 〃 | 〃 |
| 날짜·시간, BIT, SET, OBJECT, LOB | INCOMPATIBLE | 〃 | 〃 | 〃 | 〃 | 〃 |

주: "1.5 → INTEGER = 2", "2.5 → 3"(ROUND = 반올림, 절삭 아님). 문자 "1.5" → INTEGER 도 2. `' 12 '` 는 12, `'12a'` 는 -494. 정수→FLOAT/DOUBLE 은 BIGINT 정밀도(2^53 초과) 손실을 검사하지 않는다.

### 1.3 목표 = NUMERIC (od:7808~7858, no:6427~6562)

| 원 타입 | 규칙 |
|---|---|
| CHAR/VARCHAR | `tp_atonumeric`→`numeric_coerce_string_to_num`(no:5614): 문자열 자체의 p/s 로 NUMERIC 을 만든 뒤(정밀도 > 40 또는 scale < -214 면 OVERFLOW) **재귀적으로 목표 p/s 로 다시 coerce** |
| SHORT/INT/BIGINT/ENUM | 값의 유효 자릿수 = precision, scale 0 (no:6461~6515) |
| FLOAT/DOUBLE/MONETARY | `numeric_internal_double_to_num(adouble, desired_scale)` — 목표 scale 로 변환 |
| NUMERIC(p/s 다름) | `numeric_coerce_num_to_num`(no:5695): scale 확대는 10^Δ 곱, 축소는 **반올림(half-up, no:5760)**; 유효 자릿수+Δ 가 목표 precision 초과 → `ER_IT_DATA_OVERFLOW` → `DATA_STATUS_TRUNCATED` → OVERFLOW |
| **목표 precision == 40(`DB_DEFAULT_NUMERIC_PRECISION`)** | **값의 p/s 를 그대로 보존**(no:6524~6528; no:5711 "trivial case"). XASL 의 `tp_Numeric_domain`(od:308) 과 파서의 산술 결과 data_type(`DB_DEFAULT_NUMERIC_PRECISION`, tc:11570) 이 이것이다 — 즉 "NUMERIC 결과 도메인" 은 사실상 **floating NUMERIC**. 고정 p/s 도메인으로 coerce 될 때만 L-11 의 scale 덮어쓰기가 일어난다 |

### 1.4 목표 = 날짜·시간 (od:7921~8806)

| 목표 ← 원 타입 | 규칙 |
|---|---|
| DATE ← 문자 | `tp_atodate`(`db_string_to_date`) 파싱 실패 → `DOMAIN_ERROR`(→ -494); ← DATETIME/TIMESTAMP 류: 날짜 부분 절단; ← **숫자: INCOMPATIBLE** |
| TIME ← 문자 | `tp_atotime`; ← **SHORT/INT/BIGINT: `값 % 86400` 초**(od:8713~8727) — 음수 검사 없음; ← FLOAT/DOUBLE/MONETARY: ROUND 뒤 INT 범위 검사 → `% 86400`; ← TIMESTAMP/DATETIME 류: 시간 부분 |
| TIMESTAMP/TZ/LTZ ← 문자·ENUM(문자 경유)·DATE·DATETIME 류 | 파싱 또는 세션 TZ 변환; ← **숫자: INCOMPATIBLE** |
| DATETIME/TZ/LTZ ← 문자·DATE·TIMESTAMP 류·(LTZ 는 TIME 도) | 〃; ← 숫자: INCOMPATIBLE |
| 문자 ← 모든 날짜·시간 | 명시 캐스트만(§1.1-5); `db_*_to_string` 로케일 포맷, 목표 precision 보다 길면 OVERFLOW (od:9351~9445) |

### 1.5 목표 = CHAR/VARCHAR (od:9177~9555)

| 원 타입 | 규칙 |
|---|---|
| CHAR/VARCHAR | `db_char_string_coerce`(codeset 변환·길이 맞춤). **절단(`DATA_STATUS_TRUNCATED`)**: 묵시 coerce 면 항상 OVERFLOW; 명시 캐스트는 `allow_truncated_string=no` 면 OVERFLOW, yes 면 절단 허용; `TP_FORCE_COERCION` 은 항상 허용. 성공 시 collation: LEAVE 가 아니면 목표 collation 으로 덮음. `src == dest` 이고 도메인만 갈아끼울 수 있으면 복사 없이 슬램(`tp_can_steal_string`) |
| ENUMERATION | 이름 문자열로 바꿔 재귀 |
| SHORT/INT/BIGINT | 10진 문자열, 목표 precision 미만이면 OVERFLOW(명시 캐스트만 도달) |
| FLOAT/DOUBLE | `tp_ftoa`/`tp_dtoa`: **유효숫자 7 / 16 자리**(od:5464, `TP_DOUBLE_MANTISA_DECIMAL_PRECISION`=16) 로 `_dtoa` 뒤 `format_floating_point` — 지수 표기는 큰/작은 값에서 나옴. 목표 precision 초과 → OVERFLOW |
| NUMERIC | `numeric_db_value_print` 그대로(scale 자릿수 유지: 1.50 → "1.50") |
| MONETARY | 통화 기호 + `%.2f` 후 뒤 0 제거 |
| 날짜·시간 | §1.4 |
| BIT/VARBIT | 16진 문자열 |
| CLOB/JSON | 문자열화 |
| CHAR 목표의 패딩 | `make_desired_string_db_value`(od:5695) 는 `db_make_char(precision, str, strlen)` — **패딩하지 않고** 길이만 기록; 패딩 의미는 비교(§2.4)와 저장 시 `mr_writeval` 이 맡는다 |

### 1.6 목표 = ENUMERATION (od:9617~9938)

| 원 타입 | 규칙 |
|---|---|
| SHORT/INT/BIGINT | **서수**; USHORT 범위 밖 → INCOMPATIBLE; 원소 수 초과 → INCOMPATIBLE; 0 → "특수 오류 값"(빈 ENUM) |
| FLOAT/DOUBLE/NUMERIC/MONETARY | **`floor` 뒤 서수**(od:9660~9705) — 정수 변환이 ROUND 인 것과 다름 |
| CHAR/VARCHAR | 목표 codeset 으로 변환 뒤 **목표 ENUM 도메인의 collation** 으로 원소 이름과 비교(`QSTR_COMPARE`, CHAR 면 trailing space 무시); 못 찾고 빈 문자열 → 특수 오류 값, 아니면 INCOMPATIBLE |
| 날짜·시간·BIT·LOB | 문자열로 만든 뒤 이름 비교 |
| ENUMERATION | 목표 도메인 원소가 0 이면 클론(파서가 만드는 "원소 없는 ENUM 도메인", #313 B14); 이름이 있으면 이름으로, 없으면 서수로 재매핑 |

### 1.7 strict 변환 `tp_value_coerce_strict` (od:5744~6990) — 인덱스 키 전용

목표가 **숫자·날짜·시간이 아니면 실패**(od:5766). 정수 목표는 소수부가 있으면(`modf != 0`) 실패, 범위 밖 실패; NUMERIC→정수는 `numeric_is_fraction_part_zero` 필요(no:6819); NUMERIC 목표는 **정수·NUMERIC·문자만**(DOUBLE/FLOAT → 실패, od:6205); DATE ← DATETIME 은 **time == 0 일 때만**(od:6311); 문자 → 숫자/날짜는 파싱 뒤 같은 strict 검사. 오류 코드를 세팅하지 않고 `ER_FAILED` 만 돌려준다(호출자가 "손실 있음 → 값 도메인 유지" 로 해석, §4).

### 1.8 NULL·타입 없음·VARIABLE

- NULL 은 어떤 조합에서도 성공(§1.1-2). 산술은 한쪽이 NULL 이면 결과 NULL 로 조기 반환(qo:2481·4829); 비교는 `total_order` 에 따라 NULL<값 또는 UNKNOWN(od:10440).
- 목표가 `DB_TYPE_VARIABLE`/`DB_TYPE_NULL` 도메인이면 `default: DOMAIN_INCOMPATIBLE`(od:10028) — 그래서 산술은 XASL 도메인이 VARIABLE 이면 **도메인을 떼어 NULL 로 호출**하고(fe:1316) 결과 값에서 도메인을 다시 채운다(fe:4463); 결과가 NULL 이면 VARIABLE 유지.

---

## 2. 산술·비교 (스코프 2)

### 2.1 산술 — 사전 캐스트 → 타입별 연산 → 결과 coerce

**공통 뼈대**(`qdata_add_dbval` qo:2438, `subtract` qo:4818, `multiply` qo:5512, `divide` qo:6134): ① XASL 도메인이 `DB_TYPE_NULL` 이면 아무것도 안 함. ② ENUM 처리. ③ 값 타입 쌍으로 사전 캐스트(`tp_value_auto_cast`, 실패 → -494/-493 또는 `return_null_on_function_errors` 면 NULL). ④ 왼쪽 값 타입으로 디스패치(`qdata_add_int_to_dbval` 류) → 오른쪽 타입으로 2차 디스패치. ⑤ 결과를 XASL 도메인으로 `tp_value_coerce`(qo:2383) — 실패는 오류(assert_release).

| 조합(값 타입) | `+` | `-` | `*` | `/` | `DIV`/`MOD` |
|---|---|---|---|---|---|
| 정수×정수 | 더 넓은 쪽 정수(SHORT+SHORT → SHORT, INT 관여 → INT, BIGINT 관여 → BIGINT; qo:1703~1900), 오버플로 -3009 `ER_QPROC_OVERFLOW_ADDITION` | 같은 규칙 | 같은 규칙 | **정수 절삭 몫**(qo:5718·5735), 0 나누기 -3013; `oracle_compat_number_behavior=yes` 면 둘 다 NUMERIC 으로 캐스트 뒤 NUMERIC 나눗셈(qo:6173) | 둘 다 BIGINT 로 모아 계산; `DIV` 결과는 **왼쪽 피연산자의 정수 타입**(SHORT/INT/BIGINT, qo:8490~8520), `INTMOD` 는 BIGINT; 피연산자가 정수 아니면 -3007 `ER_QPROC_INVALID_DATATYPE`. `MOD` 함수(`db_mod_dbval` ar:1965)는 별개: INT%INT→INT, INT%DOUBLE→DOUBLE(`fmod`), INT%NUMERIC→NUMERIC, 문자→DOUBLE 캐스트 |
| 정수×NUMERIC | 정수를 NUMERIC(자릿수,0) 으로 → NUMERIC 덧셈(§2.1.1) | 〃 | 〃 (레거시 `numeric_db_value_mul`) | 〃 (레거시 `numeric_db_value_div`, scale ≥ 9 로 올림) | 위 |
| NUMERIC×NUMERIC | **확장 경로** `float_numeric_db_value_add`(no:2536): scale=max, prec=max(정수부)+scale, 40 초과면 반올림 | 〃 sub | `float_numeric_db_value_mul`: prec=p1+p2(+1), scale=s1+s2, 40 초과 → scale 축소·반올림(no:6057) | `float_numeric_db_value_div`(no:3347): **결과 precision 40 으로 채워 scale = 40 − 정수부 자릿수**, 상한 `DB_MAX_NUMERIC_SCALE`(252) | 위 |
| 정수/NUMERIC × FLOAT/DOUBLE | **DOUBLE**(NUMERIC 은 DOUBLE 로 변환, qo:2106) | 〃 | 〃 | 〃 | 위 |
| × MONETARY | MONETARY(통화 유지) | 〃 | 〃 | 〃 | INVALID_DATATYPE |
| 숫자 × 문자 | 문자 → **DOUBLE**(qo:2536) → DOUBLE 연산 | 〃(qo:4859) | 〃 | 〃 | 문자 → -3007 (DIV) / `MOD` 함수는 DOUBLE |
| 문자 × 문자 | `plus_as_concat=yes`(기본) 면 **접합**(qo:2472, BIT 도); 아니면 둘 다 DOUBLE | 둘 다 DOUBLE | 〃 | 〃 | — |
| 날짜·시간 × 정수 | **날짜 타입 유지**: DATE+n → DATE(일), TIME+n → TIME(초), TIMESTAMP+n → TIMESTAMP(초), DATETIME+n → DATETIME(ms); 교환 가능(qo:2523 순서 뒤집기) | DATE−n → DATE 등 | INVALID_DATATYPE | INVALID_DATATYPE(qo:6253) | INVALID_DATATYPE |
| 날짜·시간 × 실수/NUMERIC/문자 | 오른쇽을 **BIGINT 로 ROUND 캐스트**(qo:2541) → 위 규칙. 문자는 `tp_atobi` 파싱(날짜 문자열이면 -494) | 실수는 BIGINT; **문자는 왼쪽 타입이 TIME 이면 TIME, 아니면 둘 다 DATETIME 으로**(qo:4877~4907) → 날짜−날짜 규칙 | — | — | — |
| 날짜 × 날짜 | INVALID_DATATYPE | **DATE−DATE → INTEGER(일)**(qo:4790), TIME−TIME → INTEGER(초)(qo:4113), TIMESTAMP−TIMESTAMP → INTEGER(초)(qo:4178), **DATETIME−DATETIME → BIGINT(ms)**(qo:3502·4456); 서로 다른 날짜 타입은 위 캐스트 규칙으로 맞춤 | — | — | — |
| ENUM × X | 상대가 문자/BIT 면 **이름(VARCHAR)**, 아니면 **서수(SMALLINT)**(qo:2461) → 위 규칙 | **항상 서수**(qo:4838) | 〃 | 〃 | 서수 |
| SET 류 | 같은 타입이면 그 타입, 다르면 MULTISET 합(qo:2627) | 차집합 | — | — | — |
| `-x` (qo:6291) | INT/BIGINT 는 최솟값이면 -3010, FLOAT/DOUBLE 부호 반전, 문자 → DOUBLE 로 캐스트 뒤 반전, NUMERIC 부호 비트 |

#### 2.1.1 NUMERIC 결과 p/s 의 두 경로

| 경로 | 언제 | 결과 p/s |
|---|---|---|
| 레거시 `numeric_db_value_{add,sub,mul,div}` (no:2415·2691·2968·3186) | 한쪽이 **정수에서 변환된 NUMERIC** 일 때(qo:846·5183·5831) | add/sub: scale = max, prec = max(p 조정) + 자리올림 1, 38 초과 시 `numeric_prec_scale_when_overflow` 로 (38, max scale) 재맞춤; mul: p1+p2+1, s1+s2; **div: scale = max(s1,s2) 를 최소 9(`DB_LEGACY_DEFAULT_NUMERIC_DIVISION_SCALE`, dt:634)로 올리고** 반올림, prec 40 초과 → -493 |
| 확장 `float_numeric_db_value_*` (no:2536·3037·3347) | **둘 다 NUMERIC 값**일 때(qo:2073·3975·5415·6045) | 유효 자릿수로 prec 계산, 40 초과면 scale 을 깎아 반올림(no:6057); div 는 prec 40 을 채우는 scale |
| 파서 측 결과 도메인 | `+`/`-`: NUMERIC(40,0) = **floating**(tc:11570~11573); `*`: p1+p2, scale 0; `/`: (별도 행) | 서버가 계산한 p/s 를 §1.3 규칙(precision 40 → 값 p/s 보존)으로 **그대로 통과**시킨다. 결과 표기 자릿수는 서버 공식이 정한다 |

즉 "`1.10 + ?`(NUMERIC 바인드) 의 결과 표기" 는 서버 공식이 정하고, XASL 도메인은 관여하지 않는다(#313 A12 의 서버 측 실체).

#### 2.1.2 산술 결과 coerce 의 실제 효과

`qdata_coerce_result_to_domain(result, regu_var->domain)`(qo:2383·2728·6288) 는 XASL 도메인이 **확정 타입**일 때만 의미가 있다: 예 `int_col + 1` 도메인 INTEGER 이면 INT 결과 그대로; `int_col + 1.5` 도메인 NUMERIC(40,0)=floating 이면 통과; `date_col + ?` 도메인 DATE 이면 결과 DATE 통과. 늦은 바인딩(VARIABLE) 이면 fe:1316 이 도메인을 떼어 **coerce 없음** → 결과 타입 = 위 표. 고정 p/s NUMERIC 컬럼에 INSERT 되는 경로에서만 §1.3 의 축소 반올림이 일어난다.

### 2.2 비교 — `tp_value_compare_with_error` (od:10419) 와 진입점

**진입**: `eval_value_rel_cmp`(qe:152) → 상수 RHS 사전 coerce(qe:207: 숫자 vs 문자 → 문자를 DOUBLE, 날짜 vs 문자 → 문자를 날짜 타입, 숫자 vs 숫자 → 더 일반적 타입으로 **제자리** 변환; 실패는 무시) → `tp_value_compare_with_error(v1, v2, do_coercion=1, total_order)`. IN(집합)은 원소마다 같은 함수(qe:370), IN(서브쿼리 리스트)도 같다(qe:603). `can_compare=false` 면 `V_ERROR`(-494 또는 -1509 `ER_QSTR_INCOMPATIBLE_COLLATIONS`), `DB_UNK` 면 UNKNOWN.

| 값 타입 쌍 | 임시 변환 방향 | 비고 |
|---|---|---|
| 같은 타입, CHAR↔VARCHAR | 변환 없음(`ARE_COMPARABLE`, od:79) | CHAR vs VARCHAR 는 §2.4 패딩 규칙 |
| 문자 vs 숫자 | **둘 다 DOUBLE**(od:10524~10556) | `'1' = 1` 참, `'01' = 1` 참, `'1.0' = 1` 참; `'a' = 1` → 변환 실패 → 아래 "실패" 규칙 |
| 문자 vs 날짜·시간 | 문자를 **날짜 쪽 타입**으로 | `'2024-01-01' = date_col` |
| 숫자 vs 숫자(다른 타입) | `db_type_rank`(od:111: NULL<SHORT<INT<BIGINT<**NUMERIC<FLOAT<DOUBLE**<MONETARY<SET…<TIME<DATE<TIMESTAMP…<DATETIME…<OID…<CHAR<VARCHAR<…<BIT<…) 에서 **더 일반적인 쪽**으로 | INT vs NUMERIC → NUMERIC; NUMERIC vs FLOAT → **FLOAT**(정밀도 손실); BIGINT vs DOUBLE → DOUBLE(2^53 손실) |
| 날짜 vs 날짜(다른 타입) | rank 가 높은 쪽(DATE<TIMESTAMP<DATETIME) | DATE vs DATETIME → DATETIME |
| ENUM vs X | ENUM 은 rank 표에 없어 0 → **항상 ENUM 이 변환**: 상대가 숫자면 서수, 문자면 이름(**ENUM 의 collation·codeset 을 목표 도메인에 심음**, od:10600~10608) | `enum_col = ?` 의 실행 의미(#313 B13): 정수 바인드 = 서수, 문자 바인드 = 이름 |
| 문자 vs 문자, collation 다름 | 변환 없음 → 공통 collation `LANG_RT_COMMON_COLL`(ls:65): 같으면 그것, 한쪽이 coercible(바이너리·시스템 기본)이면 다른 쪽, 둘 다 coercible 이면 ISO 바이너리 우선, 둘 다 비-coercible 이면 **-1509 오류** | 이것이 `? = ?`(둘 다 LANG_SYS 바이너리) 가 실행에서 값 collation 으로 비교되는 실체(#313 K4) |
| 문자 vs 문자, codeset 다름 | ENUM 경로가 아니면 `common_coll = -1` → -1509 | |
| SET vs SET | `tp_set_compare` | |
| OBJECT vs OID | 클라이언트만; 서버는 `assert_release` | |
| **변환 실패** | `er_clear()` 하고 **rank 순서로 GT/LT**(od:10627·10660, 10679~10696): 결과는 "같지 않음" 이지만 `<`/`>` 판정은 타입 순서 — `'a' < 1` 은 문자 rank > DOUBLE rank 로 **거짓**, `'a' > 1` **참**. `can_compare` 가 주어졌으면(eval 경로) -494 오류로 승격(od:10693) | 정렬(total_order) 경로는 오류 없이 순서만 |

### 2.3 상수 사전 coerce 의 함정 (qe:207~262)

`REGU_VARIABLE_FETCH_ALL_CONST` 인 RHS(호스트 변수·리터럴)는 **첫 비교에서 제자리(in-place) 변환**된다: `int_col = ?` 에 `'5'` 바인드 → 첫 행에서 `?` 값이 DOUBLE 5.0 으로 바뀌고 이후 행은 INT vs DOUBLE(rank) 비교. `REGU_VARIABLE_CLEAR_AT_CLONE_DECACHE` 면 private heap 을 0 으로 바꿔 변환한다(L-46 의 소유 스레드 문제의 근원). LHS 는 `#if 0` 으로 꺼져 있어 `? = int_col` 은 매 행 변환.

### 2.4 문자열 비교의 collation·패딩 (op:11464·12590)

| 규칙 | 근거 |
|---|---|
| VARCHAR↔VARCHAR: `QSTR_COMPARE(collation, …, ti)` 에서 `ti = ignore_trailing_space` 파라미터(기본 no) → **trailing space 를 구분**(`'a' ≠ 'a '`) | op:11471·11529 |
| CHAR↔CHAR: `QSTR_CHAR_COMPARE(…, ti=true)` → **패딩 무시**(`'a' = 'a  '`) | op:12594·12651 |
| **CHAR↔VARCHAR**: `ignore_trailing_space=no` 면 한쪽이 VARCHAR 이므로 `ti=false` → trailing space **구분**(op:12644~12648). CHAR(5) 컬럼 값 `'a    '` vs VARCHAR 바인드 `'a'` → **다름** | #313 B7 의 실행 의미 |
| 비교 collation 은 호출자가 넘긴 것: 비교식은 `tp_value_compare_with_error` 의 공통 collation(§2.2), 인덱스는 `key_domain->collation_id`(bt:22110), 정렬·리스트는 컬럼 도메인 collation(lf:865), MIN/MAX 는 누산 도메인 collation(qa:495) | |
| codeset 이 다르면 `DB_UNK` | op:11497 |
| LIKE: `LANG_RT_COMMON_COLL(src, pattern)`(string_opfunc.c:4545), 카테고리·codeset 다르면 오류 | |

### 2.5 ENUM 서수·라벨 (op:14431, od:9617)

ENUM↔ENUM 비교는 **서수만**(`mr_cmpval_enumeration`, 이름·collation 무시). ENUM 을 문자로 바꾸면 이름+ENUM collation, 숫자로 바꾸면 서수. 산술은 §2.1 마지막 행. 정수→ENUM 은 서수(범위 밖 -494), 실수→ENUM 은 **floor**, 문자→ENUM 은 ENUM collation 으로 이름 매칭.

---

## 3. 집계·분석·정렬 (스코프 3)

### 3.1 누산 도메인 결정 — `qexec_resolve_domains_for_aggregation` (qx:21504)

`agg_p->domain` 은 XASL(파서 data_type). `opr_dbtype == VARIABLE` 이거나 collation 플래그가 NORMAL 이 아니면 **첫 비-NULL 값**으로 갱신(qx:21585~21600): SUM/AVG 에 문자 값 → **DOUBLE**; GROUP_CONCAT 에 비문자 → VARCHAR; 그 외 → 값 도메인. 그 다음 누산 도메인:

| 함수 | 누산 도메인 `value_dom` | 결과 도메인 | 비고 |
|---|---|---|---|
| COUNT/COUNT(*) | BIGINT | BIGINT | 항상 |
| MIN/MAX/BIT_AND/OR/XOR | `agg_p->domain`(첫 값 또는 파서 타입) | 같음 | 새 값이 다른 타입이면 `db_value_coerce` 로 누산 도메인에 맞춤(qa:700); 비교는 누산 도메인 `cmpval` + 그 collation |
| SUM/AVG, 값이 숫자 | `agg_p->domain` 이 NUMERIC **또는 값이 NUMERIC** → **NUMERIC(40,0)=floating**; 값이 FLOAT → DOUBLE; 그 외 → **값 타입 기본 도메인**(qx:21615~21630) | SUM: 누산 도메인을 `agg_p->domain` 으로 최종 캐스트(qa:2268); AVG: **항상 DOUBLE**(qa:2160·2170) | **SUM(int_col) 누산은 INTEGER** → `qdata_sum_acc_add_dbv` 가 `OR_CHECK_INT_OVERFLOW` 로 -3009(qo:2812~2820). SUM(bigint) 은 BIGINT 오버플로, SUM(numeric) 은 57자리 워드 누산 뒤 40자리로 반올림(qo:4575), SUM(double) 은 DOUBLE |
| SUM/AVG, 값이 비숫자 | `agg_p->domain`(첫 값 도메인) | 〃 | 문자면 DOUBLE 로 갱신됐으므로 DOUBLE 누산; 날짜면 `qdata_add_dbval(date, date)` → -3007 |
| STDDEV/VARIANCE 류 | DOUBLE, DOUBLE(제곱) | DOUBLE | 값을 매 행 DOUBLE 로 coerce(qa:635) |
| GROUP_CONCAT | `agg_p->domain`(VARCHAR 기본) | VARCHAR | |
| MEDIAN/PERCENTILE_CONT/DISC | `opr_dbtype` 이 숫자·날짜·시간이면 그대로; 그 외(문자·VARIABLE)는 값을 **DOUBLE → DATETIME → TIME 순으로 캐스트 시도**(qx:21716~21730), 전부 실패 → -1117 `ER_ARG_CAN_NOT_BE_CASTED_TO_DESIRED_DOMAIN` "DOUBLE, DATETIME or TIME" | CONT/MEDIAN: 숫자류 → **DOUBLE**(qo:9368~9392), 날짜류 → 보간된 같은 날짜 타입; DISC: 값 타입 | `median(varchar_col)` 이 `'1'`·`'2024-01-01'`·`'10:00'` 에 따라 DOUBLE/DATETIME/TIME 로 갈리는 실체(#313 F17) |
| JSON_ARRAYAGG/OBJECTAGG | JSON | JSON | |

`*resolved = 0`(값이 NULL) 이면 다음 행에서 다시 시도 — 첫 비-NULL 행이 도메인을 정한다. DISTINCT/정렬 리스트 파일 컬럼이 VARIABLE 이면 첫 값 도메인(보간 함수는 캐스트 후 도메인)으로 채운다(qx:21762~21775).

### 3.2 누산 시 값 변환 (qa:476)

- MIN/MAX: 첫 값은 누산 도메인으로 `db_value_coerce`(타입 다르면), 이후 값은 누산 도메인 `cmpval(acc, value, do_coercion=1)` — 값 타입이 다르면 cmpval 안에서 §2.2 규칙(정확히는 `pr_type->cmpval` 이 같은 타입을 전제하므로 다른 타입은 **정의되지 않은 비교**; 파서가 같은 타입을 보장해야 한다).
- SUM/AVG: 첫 값 `copy_operator` → 누산 도메인으로 coerce; 이후 값은 `SUM_ACC_IS_SUPPORTED_TYPE`(NUMERIC/SHORT/INT/BIGINT/DOUBLE/FLOAT) 이면 누산기, 아니면 `qdata_add_dbval(acc, value, value_dom)`(§2.1). 누산기 활성 중 다른 sum_type 도착 → assert + -3005 `ER_QPROC_INVALID_XASLNODE`(qo:2798) — **한 그룹 안에서 값 타입이 바뀌면 오류**(늦은 바인딩 `sum(?)` 에 INT·DOUBLE 이 섞인 UNION 등).

### 3.3 정렬 키·리스트 컬럼 (lf:4234·7066, qx:21176)

| 규칙 | 근거 |
|---|---|
| 리스트 파일 컬럼 도메인 = XASL regu 도메인; VARIABLE 이면 **첫 튜플의 regu 도메인**(값에서 fe:4463 이 채운 것)으로 확정, 그 뒤 튜플은 **값 타입으로 그대로 기록**(`qdata_copy_db_value_to_tuple_value` 가 값의 `pr_type->data_writeval`, qo:375~384) — 컬럼 도메인과 다른 타입이 오면 읽기(컬럼 도메인 `readval`)와 불일치 | lf:7066~7080, qo:361 |
| 정렬 비교 = 컬럼 도메인의 `data_cmpdisk(do_coercion=0, total_order=1)` — **변환 없음**, collation 은 컬럼 도메인 | lf:4289·4338 |
| ORDER BY/GROUP BY 정렬 키 도메인이 VARIABLE 이거나 collation 플래그가 NORMAL 아니면 출력 리스트 같은 위치의 regu 도메인으로 교체 | qx:21189~21203, 21223 |
| 보간 함수(MEDIAN/PERCENTILE) 정렬 키 `use_cmp_dom`: 첫 값에 DOUBLE→DATETIME→TIME 캐스트를 시도해 `cmp_dom` 을 정하고 이후 값을 그 도메인으로 캐스트해 비교 | lf:7335~7375, qo:9877 |
| UNION/집합 연산의 두 리스트 타입 통일 `qfile_unify_types`: 한쪽 VARIABLE(튜플 0) 이면 다른 쪽 채택, NULL 이면 다른 쪽, 다르면 **-3020 `ER_QPROC_INCOMPATIBLE_TYPES`**(가변 문자열·JSON 의 정밀도 차이만 허용), collation 플래그 NORMAL 아니면 -1509 | lf:890~950 |
| 리스트 튜플 값 비교(`qfile_compare_tuple_values`, DISTINCT 등) = 컬럼 도메인 `cmpval(do_coercion=0)` + 컬럼 collation | lf:865 |

즉 **정렬·그룹·DISTINCT 에는 값 변환이 0 회**이고, 도메인 불일치는 비교 결과가 아니라 기록/판독 불일치로 나타난다(#314 S-13~S-20 의 삭제 근거).

---

## 4. 인덱스 키 (스코프 4)

### 4.1 다중 컬럼 키 — `scan_dbvals_to_midxkey` (sm:1871) 의 strict-or-keep

| 단계 | 규칙 | 근거 |
|---|---|---|
| 1 | 각 키 값을 `fetch_peek_dbval`; NULL 이면 범위 없음(ISS 첫 컬럼만 NULL 허용) | sm:1943~1957 |
| 2 | 값 타입이 `tp_valid_indextype` 아니면 -494 | sm:1962 |
| 3 | 문자 값의 `is_max_string` 이면 MAX_COLUMN 표시 후 중단 | sm:1969~1978 |
| 4 | **값 타입 ≠ 인덱스 컬럼 타입** → `tp_value_coerce_strict(val, idx_dom)`(§1.7): 성공 → 변환된 값 사용(`has_coerced_values`); **실패 → `need_new_setdomain`** | sm:1985~2005 |
| 5 | 같은 타입이고 NUMERIC/CHAR/BIT 면 `tp_domain_match_ignore_order(EXACT)` 로 **p/s·길이·collation 까지** 비교, 다르면 `need_new_setdomain` | sm:2010~2020 |
| 6 | `need_new_setdomain` 이면 **각 값의 자기 도메인**(`tp_domain_resolve_value`) 으로 새 setdomain 을 만들고(is_desc 만 인덱스 것) 나머지 컬럼은 인덱스 도메인 복사; `prebuilt_midxkey_domains[range_idx]` 에 캐시(첫 컬럼이 NULL 도메인이었으면 재구성) | sm:2098~2150 |
| 7 | 부분 키는 `btree_coerce_key`(bt:18053) 가 min/max 규칙으로 NULL 원소를 채움(내림차순 컬럼이면 min/max 반전, CASE 1~4) | bt:18124~18190 |

결과: **strict 변환이 성공하면 키 도메인 = 인덱스 도메인**(비교 무변환). 실패(예 INT 컬럼에 1.5, VARCHAR(10) 컬럼에 다른 collation 문자열, NUMERIC(10,2) 컬럼에 NUMERIC(5,3) 값)하면 키 도메인 = 값 도메인이고, B+tree 비교 `pr_midxkey_compare_element`(op:7676) 가 원소마다 `tp_value_compare_with_error(do_coercion=1)`(§2.2) 을 호출한다 — **행(페이지 원소)마다 임시 변환**. 그 변환 실패는 §2.2 의 "rank 순서 GT/LT" 로 흡수돼 조용히 빈 범위가 된다.

### 4.2 단일 컬럼 키

`scan_regu_key_to_index_key`(sm:2328): 키 값을 `fetch_copy_dbval` 로 **그대로**(변환 없음) 복사, prefix 인덱스면 문자열 절단. `btree_coerce_key` 는 호출되지 않는다(호출처는 sm:2273 midxkey 경로만). 비교는 `btree_compare_key`(bt:22008): `TP_ARE_COMPARABLE_KEY_TYPES`(같은 타입·CHAR/VARCHAR·BIT/VARBIT·OID/OBJECT, `object_domain.h:353`) 이고 **collation 이 같으면** `key_domain->type->cmpval(…, key_domain->collation_id)`(인덱스 collation, 무변환); 아니면 `tp_value_compare_with_error(do_coercion)`(§2.2) — INT 인덱스에 DOUBLE 키 → **인덱스 키(INT)가 매 비교마다 DOUBLE 로 변환**. 범위 끝점 순서 검사 `scan_key_compare`(sm:1521) 도 같은 함수(do_coercion 1).

### 4.3 값 p/s 가 키 기술에 미치는 영향

- NUMERIC 인덱스 컬럼: 값 p/s 가 다르면(예 NUMERIC(10,2) 컬럼, 값 NUMERIC(3,1)) strict `numeric_db_value_coerce_to_num` 은 정밀도 손실이 없으면 성공(no:6211) → 키 도메인 = 인덱스. 손실(scale 축소로 반올림 필요) 이면 값 도메인 유지 → 비교마다 NUMERIC↔NUMERIC 임시 변환.
- CHAR(n) 인덱스에 VARCHAR 값: strict 는 문자 목표를 거부(od:5766) → **항상 값 도메인(VARCHAR)** → `mr_cmpval_char/string` 의 CHAR↔VARCHAR 규칙(§2.4: trailing space 구분) — 인덱스 스캔과 순차 스캔이 같은 결과를 내는 이유는 둘 다 같은 cmpval 을 쓰기 때문.
- collation 다른 문자 값: strict 거부 → 값 collation 유지 → `btree_compare_key` 의 "collation 다르면 not comparable" → `tp_value_compare_with_error` 공통 collation 규칙(§2.2).
- ISS 첫 컬럼: NULL 허용, 도메인은 인덱스 것(sm:1949·2117) — L-45(e).
- KEYLIMIT: `scan_check_user_given_keylimit_overflow`(sm:880) 가 NUMERIC/정수 값을 검사 — 슬롯 도메인이 아니라 값 타입을 본다(L-49).

---

## 5. 파서 규칙과의 일치·불일치 — 규칙표(#317)가 통일해야 할 지점 (스코프 5)

#313 의 조합 번호를 재사용한다. **일치** = 파서가 확정한 타입을 서버가 그대로 받아 같은 결과; **불일치** = 같은 조합을 파서(리터럴/컬럼 경우)와 서버(값 경우)가 다르게 본다.

| # | 조합 | 파서(컴파일) | 서버(실행, 값 기준) | 판정 | DOUBLE/VARCHAR 공통 타입 적용 시 |
|---|---|---|---|---|---|
| A1 | `int_col + 1` | INTEGER | INT+INT → INT, 오버플로 -3009 | 일치 | — |
| A2 | `int_col + 1.5` | NUMERIC(40,0)=floating | INT→NUMERIC(자릿수,0) + NUMERIC(2,1) → 레거시 add: NUMERIC(max+1, 1) | 일치(표기는 서버 공식) | — |
| A3 | `int_col + '1'` | DOUBLE | 문자→DOUBLE, INT+DOUBLE → DOUBLE | 일치 | — |
| A5 | `int_col + ?` | MAYBE | 값 타입: INT→INT(오버플로 오류), 1.1→DOUBLE, '1'→DOUBLE, 날짜→**INT 가 왼쪽이면 순서 뒤집어 날짜+정수 = 날짜**(qo:2523) | **불일치의 실체**: 컴파일은 못 정하고 서버는 값마다 다른 타입 | 슬롯 DOUBLE: INT 바인드 → 2.0 표기, BIGINT 큰 값 2^53 정밀도 손실(§1.2 정수→DOUBLE 무검사), 날짜 바인드 → -494(DOUBLE 로 변환 불가) → **답안 변경** 3종 |
| A6 | `int_col / ?` | MAYBE | INT÷INT → **절삭 정수**(oracle_compat 아니면); INT÷DOUBLE → DOUBLE | 불일치 | DOUBLE: `7/2` 3 → 3.5 **의미 변경**(L-12) — `/` 는 별도 행 필수 |
| A7 | `int_col DIV ?`, `MOD ?` | 슬롯 BIGINT | BIGINT 정수 연산, 결과 INT(입력 전부 INT 이하) 또는 BIGINT | 일치 | — |
| A8 | `? + ?` | MAYBE | 문자+문자 **접합**(plus_as_concat), 숫자+숫자 값 타입, 문자+숫자 DOUBLE | 불일치 | DOUBLE 고정: 접합 불가('a'+'b' → -494) |
| A9/A10 | `date_col + ?` | `CAST(? AS BIGINT)`, DATE | DATE+BIGINT → DATE | 일치 | — |
| A11 | `date_col - ?` | MAYBE | 값: 정수 → DATE; DOUBLE → BIGINT ROUND → DATE; 문자 → **DATETIME 파싱 → DATETIME−DATETIME = BIGINT(ms)**(qo:4884); DATE 값 → **INTEGER(일)** | 불일치(결과 타입이 DATE/INT/BIGINT 셋으로 갈림) | DOUBLE 고정: 날짜 바인드 -494 → 날짜 차 계산은 명시 CAST 필요 — 답안 변경 |
| A12 | `numeric_col(10,2) + ?` | MAYBE | NUMERIC+INT → 레거시 add NUMERIC(p,2); NUMERIC+NUMERIC → 확장 add; NUMERIC+DOUBLE → **DOUBLE**(qo:2106) | 불일치(표기 `2.20` vs `2.2`) | DOUBLE: NUMERIC 컬럼 산술이 전부 DOUBLE 표기로 — 답안 변경 다수(L-11 의 "다른 모양") |
| A13 | `enum_col + ?` | MAYBE | 문자 바인드 → 이름 접합(plus_as_concat), 숫자 → 서수+숫자 | 불일치 | 서수 승격 후 DOUBLE (L-10): 문자 바인드 접합 의미 소실 → 답안 변경 |
| A14 | `-?`, `round(?, 2)` | MAYBE | 값 타입 유지(문자는 DOUBLE) | 불일치 | DOUBLE: NUMERIC 바인드 p/s 손실(`round(12.345, 2)` → 12.35 DOUBLE 표기) |
| B1/B2 | `int_col = 1.5` / `> 1.5` | `=` INT 캐스트(1.5→2!), `>` DOUBLE | 서버 같은 타입 비교 / INT vs DOUBLE → INT 를 DOUBLE 로 | 파서 결정 그대로 | — (`= 1.5` 가 `= 2` 로 폴딩되는 현행은 규칙표 답안 변경 후보) |
| B4/B5 | `int_col = ?`, `< ?` | 슬롯 INTEGER(CAS 가 캐스트) | 서버에 INT 로 도착하면 무변환; CAS 캐스트가 안 된 경로(PL/CSQL 맨 `?`, L-16)면 §2.2: 1.5 → INT 를 DOUBLE 로 올려 비교(`int_col = 1.5` 거짓, `< 1.5` 는 1 참) | 일치(정상 경로) / 불일치(맨 `?`) | 미러 유지면 변화 없음; **게이트 변환이 ROUND(§1.2) 라서 `int_col = ?` 에 1.5 → 2 와 비교** — 규칙표가 "미러 캐스트는 strict(소수부 있으면 오류)" 로 할지 결정 필요 |
| B7 | `char_col(5) = ?` | CHAR 기본 도메인, VARCHAR 값 유지 | CHAR vs VARCHAR: `ti=false` → **trailing space 구분**(§2.4); 인덱스도 값 도메인 VARCHAR 유지(§4.3) | 일치(둘 다 구분) | VARCHAR 고정이면 현행과 같음(값이 이미 VARCHAR). 규칙표가 "CHAR 컬럼 미러 = CHAR 로 패딩" 을 택하면 `'a' = 'a  '` 참으로 변화 |
| B8 | `? = ?` | MAYBE | 문자 vs 숫자 → 둘 다 DOUBLE(`'1' = 1` 참, `'01' = 1` 참); 문자 vs 문자 → 값 collation 공통(LANG_SYS 둘이면 바이너리) | 불일치 | VARCHAR 고정: `'01' = 1` → 문자 비교 거짓 — 답안 변경(MySQL 도 DOUBLE 비교이므로 #315 T 대조 필요) |
| B13 | `enum_col = ?` | `TO_ENUMERATION_VALUE(?)`, VARIABLE | §1.6: 정수 → 서수, 실수 → **floor** 서수, 문자 → 이름(ENUM collation) | 불일치 | VARCHAR 고정: 정수 3 → '3' → 이름 매칭 실패 → -494(또는 이름이 '3' 인 원소) — **조용한 오답 위험**(L-06) |
| B14 | `enum_col < ?` | 원소 없는 ENUM 도메인 | 서버: ENUM vs 숫자 → 서수 비교, ENUM vs 문자 → **이름 사전식**(ENUM collation) | 불일치 | 서수 승격 규칙 필요(L-10) |
| B19 | `int_col IN (SELECT ? …)` | 서브쿼리 컬럼 MAYBE | 리스트 컬럼 도메인 = 첫 튜플 값 타입; 비교는 §2.2 값 쌍 | 불일치 | 서브쿼리 슬롯 컬럼 확정 필요 |
| B25 | `int_col = bigint_col`, `char_col = varchar_col` | 캐스트 없음 | INT vs BIGINT → INT 를 BIGINT 로 매 행; CHAR vs VARCHAR 무변환(패딩 규칙) | 파서가 서버에 위임 | 규칙표가 "컬럼 쌍은 컴파일 캐스트" 로 옮길지 결정(행당 변환 0 회 목표) |
| B26/B27 | `str_col = 1` / `str_col = int_col` | 리터럴 → VARCHAR 캐스트 / 둘 다 DOUBLE | 서버 문자 vs 숫자 → DOUBLE | **B26 불일치**: 파서는 `str_col = '1'`(문자 비교: `'01'` 불일치), 서버 격자·B27 은 DOUBLE(`'01' = 1` 참) | 규칙표: 문자 vs 숫자 비교의 단일 규칙(DOUBLE 또는 문자) |
| U9 | `COALESCE(?, 1)` | MAYBE | 서버 COALESCE 는 `domain == NULL` 이면 두 값에서 `tp_infer_common_domain`(od:11480): 같은 부류면 rank 높은 쪽, 부류 다르면 **VARCHAR**; 'a' 바인드 → VARCHAR 'a' | 불일치 | DOUBLE: 'a' 바인드 → -494 |
| F13 | `sum(?)`, `min(?)` | MAYBE | 첫 비-NULL 값 도메인(§3.1); 문자 값이면 SUM 은 DOUBLE; 그룹 안 타입 혼합 → -3005 | 불일치 | DOUBLE: `sum(?)` INT 바인드 → 2.0 표기; MIN/MAX(?) 문자 → VARCHAR 고정이면 현행과 같음 |
| F15 | `sum(int_col)` | INTEGER | 누산 INTEGER → **INT 범위 오버플로 -3009**(qo:2812); BIGINT 승격 없음 | 일치(둘 다 INT) | — (이 문서 이전 기록 "서버가 BIGINT/NUMERIC 승격" 은 **틀림**; #313 F15 비고 정정 대상) |
| F14 | `avg(?)` | `CAST(? AS DOUBLE)` | 누산 DOUBLE, 결과 DOUBLE | 일치 | — |
| F16/F17 | `median(?)`, `median(varchar_col)` | MAYBE | 값을 DOUBLE→DATETIME→TIME 순 캐스트, 결과 CONT 는 DOUBLE/날짜 | 불일치 | 인자·정렬 키 DOUBLE 고정: 날짜 문자열 입력 -1117 → 답안 변경(L-21) |
| S1 | `SELECT ?` | MAYBE | 리스트 컬럼 = 값 타입, 메타 (0,0) | 불일치 | VARCHAR 고정: 숫자 바인드 결과가 문자로 — 답안 변경(L-23) |
| S9 | `ORDER BY ?` | MAYBE | 정렬 키 도메인 = 출력 리스트 같은 위치 regu 도메인(값에서 확정), 무변환 cmpdisk | 불일치 | 확정 도메인이면 서버 규칙 그대로 |
| S11/S12 | auto-param `int_col = to_number('3')` | 슬롯 NUMERIC, 값 INT | 키: 값 INT ≠ 슬롯 NUMERIC → §4.1 strict 성공(INT→NUMERIC) 또는 값 도메인 → L-22 의 키 인코딩 갈림 | 불일치 | 게이트가 값을 계획 도메인으로 실제 변환하면 소멸(D-M4) |
| K4/K5 | `? = ?`, `concat(?, ?)` collation | LANG_SYS+LEAVE | 실행: `LANG_RT_COMMON_COLL` — 둘 다 coercible(LANG_SYS)면 ISO 바이너리 우선 → 결국 **바이너리 비교** | 일치(결과) / 불일치(결정 시점) | 규칙표 (a)/(b)/(c) 중 택일 — 서버 결정은 값 collation 이 다를 때만 의미 |

**DOUBLE/VARCHAR 공통 타입이 값을 바꾸는 대표 사례**(위 표에서 추출, 답안 변경 판정 입력):
1. 정수 바인드의 표기 `1 + ? → 2.0`, `sum(?) → 2.0`, `SELECT ? → '1'`.
2. 정수 나눗셈 `7 / ?` 3 → 3.5(의미 변경, `/` 별도 행으로 방어).
3. BIGINT 큰 값(> 2^53) 의 DOUBLE 정밀도 손실 — 서버 coerce 는 이를 **검사하지 않는다**(§1.2).
4. 날짜 바인드 `date_col + ?`, `date_col - ?`, `hour(?)` → -494(DOUBLE 은 날짜로 변환 불가) — CAST 요구로 답안 변경.
5. 문자 바인드 `? + ?` 접합, `coalesce(?, 1)` 'a', `enum_col = ?` 이름 → -494 또는 조용한 오답.
6. NUMERIC 컬럼 산술 `numeric_col + ?` 의 표기(`2.20` → `2.2`)와 p/s.
7. 문자 vs 숫자 비교 `? = ?`, `'01' = 1` — VARCHAR 고정이면 문자 비교로.
8. `int_col = ?` 에 1.5: 현행 CAS 캐스트 -494 vs 게이트 ROUND 2 — 규칙표가 "미러 캐스트는 strict" 인지 정해야 함.

---

## 6. 결론 — 규칙표(#317)·아키텍처(#318)에 넘기는 서버 측 사실

1. **게이트 변환 함수는 `tp_value_cast_internal` 하나로 충분하지만 모드를 정해야 한다.** 묵시(`tp_value_coerce`) 는 숫자→문자를 거부하고 문자 절단을 오류로 본다; 명시(`tp_value_cast(…, false)`) 는 허용 폭이 넓다. 정수 목표는 **ROUND** 이므로 "미러 캐스트에서 소수부 손실은 오류" 를 원하면 `tp_value_coerce_strict` 계열(현재 숫자·날짜 목표만, 오류 코드 없음)을 확장해야 한다.
2. **NUMERIC 계획 도메인은 precision 40(`DB_DEFAULT_NUMERIC_PRECISION`) 이 "값 p/s 보존" 을 뜻한다.** 게이트가 NUMERIC 슬롯을 변환할 때 이 도메인을 쓰면 L-11 재발이 없고, 고정 p/s 를 쓰면 반올림·오버플로가 값에서 일어난다.
3. **산술 결과 타입은 서버 공식이 정하고 XASL 도메인은 결과를 coerce 만 한다.** 계획이 "결과 도메인" 을 확정하려면 §2.1 표를 그대로 컴파일 시 타입 함수로 옮겨야 하며, 특히 `/`(정수 절삭·oracle_compat)·NUMERIC p/s 공식·날짜 산술(DATE±n=DATE, 날짜−날짜=INT/BIGINT)·ENUM(`+` 는 상대 따라 이름/서수, 나머지는 서수)은 별도 행이 필요하다.
4. **비교의 임시 변환은 값 쌍이 같은 타입이면 0 회다.** 게이트가 슬롯 값을 컬럼 타입으로 맞추면 §2.2 의 방향 규칙·`er_clear` 폴백·상수 제자리 coerce(qe:207, L-46 의 원인)가 전부 불필요해진다. 남는 것은 컬럼 vs 컬럼(B25)·문자 collation 공통 규칙(LANG_RT_COMMON_COLL) 두 가지다.
5. **집계는 첫 값이 도메인을 정하므로 계획이 SUM/MIN/MAX/MEDIAN 의 인자 도메인을 주면 qx:21504 전체가 컴파일 시 계산 가능하다.** SUM 의 누산 타입 = 인자 타입(INT 오버플로 포함)이 현행이며 승격이 없다 — 규칙표가 SUM(int) 의 결과 타입을 바꿀지(답안 변경) 결정.
6. **인덱스 키의 strict-or-keep 은 "손실 없으면 인덱스 도메인, 있으면 값 도메인" 이고 후자는 원소 비교마다 변환한다.** 게이트가 키 슬롯을 인덱스 컬럼 도메인으로 미리 변환(손실 시 오류 또는 빈 범위로 판정)하면 `prebuilt_midxkey_domains`·`need_new_setdomain`·`btree_compare_key` 의 폴백 경로(L-45 a~g)가 삭제 가능하다. 단일 컬럼 키는 지금 변환이 전혀 없어 INT 인덱스에 DOUBLE 값이 오면 **인덱스 쪽이** 매 비교 변환된다 — 계획의 키 변환 항목에 포함해야 한다.
7. **정렬·리스트는 변환 0 회이며 도메인이 곧 인코딩이다.** 계획이 리스트 컬럼·정렬 키 도메인을 주면 lf:7066·qx:21176·21223 은 삭제되고, 값 타입 ≠ 컬럼 도메인은 assert 로 승격할 수 있다(L-22 불변식).

---

## 7. 경험치 렛저 대응표

| L | 이 문서에서 다룬 곳 |
|---|---|
| L-11 (NUMERIC 슬롯 고정 p/s → scale 덮어쓰기) | §1.1-6(`db_value_domain_init` 의 DEFAULT→(40,0)), §1.3(precision 40 = 값 p/s 보존, 고정 p/s 만 반올림), §2.1.1(NUMERIC 결과 공식 두 경로), §5 A2·A12, §6-2 |
| L-12 (`+`/`-` 정수 고정 절단, `/` DOUBLE 절삭 의미) | §1.2(정수 목표는 ROUND), §2.1 표 `/`·`DIV`·`MOD` 행(정수 절삭·oracle_compat), §2.1 ENUM 행(`+` vs `-*/` 갈림), §5 A5·A6·A7·A13, §6-3 |
| L-22 (auto-param 슬롯 도메인 ≠ 값 → 키 인코딩 갈림) | §4.1 strict-or-keep(값 타입 ≠ 인덱스 타입일 때 두 갈래), §4.3, §3.3(리스트 기록은 값 타입·판독은 컬럼 도메인), §5 S11/S12, §6-7 |
| L-45 (인덱스 키 변환 7항목) | (a) §4.1 단계 4~6 전략이 값마다 재결정됨; (b) §4.1 단계 6 `prebuilt_midxkey_domains` 캐시; (c) key1/key2 가 같은 `range_idx` 캐시 공유(sm:2394·2426); (d) §4.1 단계 7 min/max 반전 규칙·§4.2 `scan_key_compare`; (e) §4.3 ISS 첫 컬럼; (f) 인덱스 도메인은 `btree_domainp`(bt:18053 인자) — XASL 에 실을 바이트 동일; (g) §4.1 단계 6 캐시 소유 — §6-6 |
| L-49 (플랜 도메인을 믿는 소비자) | §4.3 KEYLIMIT, §2.1.2(산술 결과 coerce 는 확정 도메인만), §1.8(VARIABLE 목표는 INCOMPATIBLE) |
| L-51 (행당 비용 지점의 규칙 측면) | §2.2 임시 변환 방향·실패 폴백, §2.3 상수 제자리 coerce, §3.1 첫 값 도메인, §3.3 리스트 도메인 재시도(`is_domain_resolved`), §4.1~4.2 키 비교 폴백, §1.8 VARIABLE 탈착·복원(fe:1316·4463), U9 `tp_infer_common_domain` |
| L-06 (에러→값 전환은 값 A/B) | §5 B13(ENUM 정수 바인드 → 이름 매칭 조용한 오답), §2.2 변환 실패의 `er_clear` GT/LT 폴백 |
| L-10 (문맥 없는 슬롯 기본 하나 → ENUM/SET 깨짐) | §1.6, §2.1 ENUM 행, §2.5, §5 A13·B13·B14 |
| L-21 (MEDIAN/PERCENTILE 정렬 키) | §3.1 보간 행, §3.3 `use_cmp_dom`, §5 F16/F17 |
| L-23 (답안 변경 목록) | §5 마지막 단락 1~8 |
| L-46 (게이트 값의 소유 스레드) | §2.3(`REGU_VARIABLE_CLEAR_AT_CLONE_DECACHE` 제자리 coerce 의 private heap 전환), §3.1(qx:21708 같은 전환) |
