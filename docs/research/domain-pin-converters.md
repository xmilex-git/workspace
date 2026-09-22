# 변환기 표·GATE placeholder·`domain_resolve` 케이스 본문 — 확정안 (#325)

지도 xmilex-git/workspace#312 · 티켓 #325 · 작성 2026-09-22 · 기준 엔진 `develop cad27172b`
입력: 인터페이스 정본 `domain-pin-interface.md` v4(D-323-01~18, **고정 — 이 문서는 그 안의 내용만 채운다**), 규칙표 `domain-pin-rule-table.md`(D-317·D-322·D-327), 서버 규칙 `domain-pin-rules-server.md`(#321 §1~§4), 렛저 `domain-pin-lessons.md`. 인용 표기는 #321 과 같다(`od:` object_domain.c, `no:` numeric_opfunc.c, `qo:` query_opfunc.c, `fe:` fetch.c, `qx:` query_executor.c, `sm:` scan_manager.c, `pd:` parse_dbi.c, `tc:` type_checking.c, `so:` string_opfunc.c, `ar:` arithmetic.c).

이 문서가 채우는 자리(#325 본문 1~5): (1) `domain_lookup_converter` 표의 내용, (2) `domain_resolve` 케이스 본문의 출처와 이관 규칙, (3) GATE 슬롯 placeholder 도메인, (4) 규칙표 S4/S5 "실행 중 세션변수 타입 변경" 값 A/B, (5) 상관 복합 키 원소 `strict_conv` 의 출처. 슬롯 ID 순서·게이트 의존 목록·`val_pos` 다중 참조·상수 부분트리 캐시·실행 플래그 로드 이전은 #323 이 답했으므로 다루지 않는다.

---

## 0. 결정 목록 (D-325-01~12 — 2026-09-22 사용자 승인, #325 코멘트 "결정 기록" 이 정본)

| # | 결정 | 한 줄 근거 |
|---|---|---|
| D-325-01 | **변환 모드는 셋**: 대입(ASSIGN, 현행 `tp_value_cast` 명시 모드 = 반올림·인쇄·절단 검사) · 비교(COMPARE, 현행 `tp_value_coerce_strict` 그대로) · 피연산자(OPERAND, 비교 모드 + NUMERIC ← 실수 허용). `DOMAIN_CTX` 9종은 이 셋으로 사상된다(§1) | 세 현행 함수(`tp_value_cast_preserve_domain`·`tp_value_coerce_strict`·`tp_value_auto_cast`)의 의미를 함수 단위로 옮긴다(D-327-10). 비교와 키가 같은 모드여야 인덱스 스캔과 순차 스캔의 답이 같다(#321 §4.3) |
| D-325-02 | **CAST 노드가 소비자인 슬롯은 대입 모드**: 사용자 `CAST(? AS T)` 와 컴파일 시그니처 CAST(`date_col + ?` 의 `CAST(? AS BIGINT)`, `int_col DIV ?`, `avg(?)` 의 `CAST(? AS DOUBLE)`) 아래의 슬롯은 `domain_lookup_converter (값 타입, T, DOMAIN_CTX_ASSIGN)`. CAST 노드 자신은 그 피연산자에 항등 | CAST 실행은 오늘 `qdata_cast_to_domain` → `tp_value_cast (…, false)`(qo:2402, 반올림)이고 규칙표 A7·A9 는 "현행 · 답안 변경 —" 이다. strict 로 하면 `date_col + ?` 1.5 → -494 가 §7 에 없는 답안 변경이 된다 |
| D-325-03 | **표 원소 = 셀 함수(leaf), 구현은 혼합**: `tp_value_cast_internal`(od:6992~10080, 내부 `case` 171개)과 `tp_value_coerce_strict`(od:5743~6990, 110개)의 "목표 타입 switch → 원 타입 switch" 안쪽 본문이 leaf 가 된다. **숫자×숫자·문자→숫자 부류**(§2.1·§2.2, 약 150셀)는 `template <typename SRC, typename DST, DOMAIN_CONVERT_MODE MODE>` 특수화로 쓰고 표의 그 영역은 컴파일 시점에 생성한다(`index_sequence`; 빠진 셀 = 컴파일 오류). **문자·날짜·ENUM·컬렉션·JSON 셀**은 본문을 `tp_value_convert_<원>_to_<목표>[_strict]` 정적 함수로 **object_domain.c 안에서 기계적으로 추출**한다. 두 큰 함수는 switch 를 유지한 채 같은 leaf 를 부른다(동작 불변 리팩토링 커밋 1개, 단독으로 양 빌드 green + optdebug CTP sql 전수 무 diff). object_domain.c 는 `LANGUAGE CXX` 로 컴파일되며(cubrid/CMakeLists.txt:654) `.c` 안 템플릿 선례가 있다(xasl_to_stream.c:113, crypt_opfunc.c:91) | P6(변환 의미의 구현은 한 벌). 런타임 비용은 두 방식이 같다(셀 = 비제네릭 함수 하나, 간접 호출 1회); 템플릿은 공식형 숫자 셀의 본문 수를 줄이고 셀 누락을 컴파일이 잡는 데만 쓴다 — 고유 로직 셀에 템플릿은 이득이 없다(사용자 결정 2026-09-22) |
| D-325-04 | **leaf 본문에 타입 switch 없음** — 검수 규칙: leaf 는 (원 타입, 목표 타입)이 고정된 함수이고 `DB_VALUE_TYPE (src)` 를 읽어 분기하지 않는다. 허용되는 유일한 내부 분기는 목표 도메인 **파라미터**(NUMERIC p/s 가 40 인지, codeset 이 같은지, CHAR 길이) 검사 뿐. `tp_value_cast_internal`·`tp_value_cast`·`tp_value_coerce`·`db_value_coerce` 호출은 leaf 에서 금지(재귀 셀 §2.6 은 leaf 끼리 직접 호출) | #323 리뷰 R4 / cpp-perf-rules A61·BR-06 |
| D-325-05 | **표 = 정적 3차원 배열** `domain_convert_table[3][DB_TYPE_LAST + 1][DB_TYPE_LAST + 1]`(41×41×3×8B ≈ 40KB `.rodata`, designated initializer, 빈 셀은 `tp_value_convert_incompatible`). 조회는 로드·게이트·휘발 항목에서만 — 행 루프는 항목에 고정된 포인터를 부른다 | 단순함 우선. 압축 인덱스(사용 타입 20종)는 측정 뒤 변형(escape hatch) |
| D-325-06 | **항등의 뜻**: `domain_lookup_converter` 는 원 타입 == 목표 타입이고 목표가 비파라미터 타입이면 NULL. 파라미터 타입(NUMERIC·CHAR/VARCHAR·BIT·ENUM·컬렉션)은 같은 타입이라도 leaf 를 돌려주고, leaf 가 p/s·codeset·collation 이 이미 같으면 복제만 한다(현행 no:5711 "trivial case"·od:10156 early exit 과 같다) | 시그니처가 원 **도메인**이 아니라 원 **타입**만 받으므로(D-323-02) 파라미터 비교는 leaf 안에서 |
| D-325-07 | **반환은 `TP_DOMAIN_STATUS`, `er_set` 은 호출자**: leaf 는 상태만 돌려주고(COMPATIBLE / INCOMPATIBLE / OVERFLOW), 실패 정책은 항목(`DOMAIN_PLAN_ITEM.fail[]`)을 읽은 호출자(게이트·행 kernel)가 적용한다 — ERROR 는 `tp_domain_status_er_set`(-494/-493 현행 코드), NULL 은 typed NULL(파라미터 no 면 ERROR), KEEP 은 원 값 유지 + KEEP_LAZY 재확정. 오류를 깊은 곳에서 세팅하는 셀(날짜 파싱 `db_string_to_*`, JSON)만 DOMAIN_ERROR 를 낼 수 있고 §2.7 에 열거한다 | KEEP·NULL 경로에 `er_clear` 폴백을 남기지 않는다(P6). `tp_value_coerce_strict` 는 오늘도 오류를 세팅하지 않는다(od:5744) |
| D-325-08 | **NULL 원 값은 leaf 밖에서**: 게이트(상수 1회)·행 kernel 은 `DB_IS_NULL (src)` 이면 leaf 를 부르지 않고 목표 도메인의 typed NULL(`db_value_domain_init`)을 만든다 — 오늘 `tp_value_cast_preserve_domain (…, preserve_domain = true)`(pd:3110) 의 의미 | NULL 검사는 어차피 평가 경로에 있다; leaf 를 단순하게 |
| D-325-09 | **GATE 슬롯 placeholder = `DB_TYPE_VARIABLE` 도메인(`tp_Variable_domain`) + `REGU_VARIABLE_GATE` 비트**, collation_flag NORMAL. NULL 도메인은 쓰지 않는다 | 경계 (a) 가 "GATE 비트 없는 VARIABLE/LEAVE" 를 거부하므로 자연스러운 짝(D-323-09). 스트림 팩은 오늘도 VARIABLE 도메인을 실어 왔다(변경 0). NULL 도메인은 `tp_value_cast_internal` 의 `default: DOMAIN_INCOMPATIBLE`(od:10028) 자리라 "값 없음" 과 "미확정" 이 섞인다 |
| D-325-10 | **휘발 피연산자(세션변수 읽기)의 행 값 타입이 게이트 시점과 다르면** 항목의 마지막 (원 타입, leaf) 쌍을 스캔 스크래치에 두고 타입이 바뀐 행에서만 표를 다시 조회한다(분기 1, switch 0). 목표 도메인·실패 정책은 게이트 1회로 불변. 비교 문맥의 휘발 값은 KEEP 이 불가능하므로 실패 = ERROR(-494) | `@v := '1'; @v := @v + 1` 은 행 1 이 VARCHAR, 행 2 부터 INTEGER — 게이트 타입 고정이면 §7 이 약속한 `2,3,4` 가 -494 가 된다(§5 P-S3). KEEP 은 비교 도메인 재확정 = 행당 결정이라 금지 |
| D-325-11 | **리스트 컬럼(`SELECT @v`·`SELECT ?` 결과 컬럼)의 게이트/행 변환 실패 정책 = `return_null_on_function_errors` 를 따른다**(산술·함수 인자와 같은 부류) — 규칙표 X1 에 "리스트 컬럼" 열 추가 제안 | 실측 P-S1: develop 은 default -494, `yes` 면 NULL(§5). 현행이 파라미터를 보고 있었다 |
| D-325-12 | **규칙표 S4/S5 "실행 중 타입 변경" 행의 답안 변경 판정 입력** = §5 표(P-S1~P-S10 develop 실측 vs 설계 예측). 판정은 사용자 | D-323-18 |

---

## 1. 문맥 → 모드 사상

`DOMAIN_CTX`(인터페이스 §1.3, 9종)는 표의 첫 인덱스인 **모드** 셋으로 줄어든다. 모드는 "실패를 어떻게 정의하는가" 만 다르고 성공 시 값은 같다.

| 모드 | 현행 함수 | `DOMAIN_CTX` | 정수 목표 ← 소수 | NUMERIC 목표 ← FLOAT/DOUBLE/MONETARY | 문자 목표 ← 숫자·날짜 | 문자 목표 ← 문자(길이 초과) | DATE ← DATETIME |
|---|---|---|---|---|---|---|---|
| **ASSIGN**(대입) | `tp_value_cast (…, implicit = false)` = `tp_value_cast_preserve_domain`(pd:3110)·`qdata_cast_to_domain`(qo:2402) | `DOMAIN_CTX_ASSIGN`, **CAST 소비자**(D-325-02) | **반올림**(od:7331~) | 허용(`numeric_db_value_coerce_to_num`, no:6427) | 인쇄(od:9177~) | `allow_truncated_string` 따라 절단/OVERFLOW(od:9195) | 절단(od:7921~) |
| **COMPARE**(비교·키) | `tp_value_coerce_strict`(od:5743) | `DOMAIN_CTX_COMPARE`, `DOMAIN_CTX_KEY_ELEM` | 실패(`modf != 0`) | **실패**(od:6205 — 값 도메인 유지 → KEEP) | 인쇄(문자 목표는 strict 개념이 없다 — B6·B10 현행 클라이언트 캐스트와 같다) | 변환 없음(비교 목표는 floating VARCHAR) | 실패(time ≠ 0) |
| **OPERAND**(피연산자) | `tp_value_auto_cast`(od:11404) 의 자리에 strict 를 넣은 것(D-317-10 "산술 strict") | `DOMAIN_CTX_ARITH`, `_FUNC_ARG`, `_AGG`, `_ANALYTIC`, `_COMMON_VALUE`, `_LIST_COLUMN` | 실패 | **허용**(값 p/s 보존 — A5'·A12; §2.2) | 인쇄 | 변환 없음 | 실패 |

- COMPARE 와 KEY_ELEM 이 한 모드인 이유: 인덱스 키 strict-or-keep(sm:1985)과 술어 비교(qe:220)가 같은 성공/실패 판정을 내려야 인덱스 스캔과 순차 스캔의 답이 같다(#321 §4.3, 실측 B30 "전 셀 일치").
- OPERAND 가 COMPARE 와 다른 셀은 **NUMERIC ← FLOAT/DOUBLE/MONETARY 하나뿐**이다(§2.2). `numeric_col + ?` DOUBLE 바인드(A5'·A12)는 성공해야 하고, `numeric_col = ?` 는 실패 → KEEP → 비교 도메인 DOUBLE(현행 rank)이어야 한다.
- 문자 목표(F6 `substr(?)`, B6 `varchar_col = ?`, U6 `CASE … THEN ? ELSE ?`)는 세 모드 모두 인쇄 셀이다 — 오늘 문자 컬럼 형제 슬롯만 클라이언트가 명시 캐스트하던 것(#323 P-3)과 같다.
- 게이트 확정 슬롯(값 타입이 곧 도메인)의 변환기는 항등(NULL)이고, 게이트 의존 노드의 피연산자 변환기는 `domain_resolve` 가 낸 결과 도메인에 대해 OPERAND 모드로 조회한다(`? + ?` INT·DOUBLE → DOUBLE, conv[0] = int→double).

---

## 2. 변환기 표 — 셀 부류와 leaf

원 타입 축(바인드·행·세션변수 값이 실제로 가질 수 있는 것): SHORT INTEGER BIGINT FLOAT DOUBLE MONETARY NUMERIC · CHAR VARCHAR · BIT VARBIT · DATE TIME TIMESTAMP TIMESTAMPTZ TIMESTAMPLTZ DATETIME DATETIMETZ DATETIMELTZ · ENUMERATION · SET MULTISET SEQUENCE · OBJECT/OID · JSON · BLOB CLOB. 목표 타입 축은 계획 도메인이 가질 수 있는 같은 집합. NULL 원 값은 D-325-08. 아래 표의 "leaf" 는 D-325-03 의 추출 함수 이름이고 괄호는 오늘 그 본문이 있는 자리다.

### 2.1 숫자 → 숫자

| 원 → 목표 | ASSIGN | COMPARE / OPERAND | leaf |
|---|---|---|---|
| SHORT→INTEGER→BIGINT, 정수→FLOAT/DOUBLE/MONETARY | 무검사 캐스트 | 같음(BIGINT→DOUBLE 2^53 손실은 세 모드 모두 무검사 — 현행 od:7700·6100) | `tp_value_convert_<정수>_to_<넓은 타입>` |
| BIGINT→INTEGER→SHORT | 범위 검사 → OVERFLOW | 같음 | `…_narrow` |
| FLOAT/DOUBLE/MONETARY → SHORT/INTEGER/BIGINT | **ROUND** 뒤 범위(od:7360~7480) | **strict**: `modf != 0` → INCOMPATIBLE, 범위 밖 → OVERFLOW(od:5800~6060) | `…_to_integer` / `…_to_integer_strict` |
| NUMERIC → SHORT/INTEGER/BIGINT | `numeric_db_value_coerce_from_num`(no:6574, ROUND) | `numeric_db_value_coerce_from_num_strict`(no:6776) | 기존 함수 그대로(래퍼) |
| 정수/ENUM(서수)/NUMERIC → NUMERIC(dst) | `numeric_db_value_coerce_to_num`(no:6427): precision 40 이면 **값 p/s 보존**, 고정 p/s 면 `numeric_coerce_num_to_num`(half-up, 초과 → OVERFLOW) | COMPARE: 같은 함수, 손실이 있으면 INCOMPATIBLE(no:6211 규칙) · OPERAND: ASSIGN 과 같음 | `tp_value_convert_number_to_numeric[_strict]` |
| FLOAT/DOUBLE/MONETARY → NUMERIC(dst) | `numeric_internal_real_to_num`(no:4915): `_dtoa` 16자리로 값의 p/s 도출(1.5 → NUMERIC(2,1)), dst_scale 까지 0 채움; precision 40 이면 그대로, 고정 p/s 면 num_to_num | COMPARE: **INCOMPATIBLE**(strict 표 od:6205) · OPERAND: ASSIGN 과 같음 | `tp_value_convert_real_to_numeric` (COMPARE 셀은 `tp_value_convert_incompatible`) |
| DOUBLE→FLOAT | 범위 검사 | 같음 | |

### 2.2 문자 → 숫자 (파싱)

| 원 → 목표 | 공통 | ASSIGN | COMPARE / OPERAND | leaf |
|---|---|---|---|---|
| CHAR/VARCHAR → SHORT/INTEGER | `tp_atof`(od:4851): 앞뒤 공백 허용, 남은 문자 → INCOMPATIBLE, ERANGE → OVERFLOW | 파싱값 **ROUND** | 파싱값 `modf != 0` → INCOMPATIBLE | `tp_value_convert_string_to_integer[_strict]` |
| → BIGINT | `tp_atobi`(od:4957: 16진·지수 허용) | 소수부 반올림 | 소수부 → INCOMPATIBLE(od:6330 `numeric_is_fraction_part_zero` 규칙) | `…_to_bigint[_strict]` |
| → FLOAT/DOUBLE/MONETARY | `tp_atof` | 범위만 | 같음 | `…_to_double` |
| → NUMERIC(dst) | `tp_atonumeric` → `numeric_coerce_string_to_num`(no:5614): 문자열 자체의 p/s → 목표 p/s 로 재 coerce | 반올림 | strict 는 오늘 `tp_value_coerce`(od:6459)를 다시 탄다 → leaf 로 펴서 "손실 → INCOMPATIBLE" | `…_to_numeric[_strict]` |

### 2.3 → 문자 (인쇄) — 세 모드 동일

| 원 → CHAR/VARCHAR(dst) | 규칙 | leaf |
|---|---|---|
| SHORT/INTEGER/BIGINT | 10진 문자열; 목표 precision 미만이면 OVERFLOW(od:9260) | `tp_value_convert_integer_to_string` |
| FLOAT/DOUBLE | `tp_ftoa`/`tp_dtoa` 유효숫자 7/16(od:5464) | `…_real_to_string` |
| NUMERIC | `numeric_db_value_print`(scale 자릿수 유지 `1.50`) | `…_numeric_to_string` |
| MONETARY | 통화 기호 + `%.2f` | |
| 날짜·시간 | `db_*_to_string` 로케일 포맷(od:9351~9445) | `…_<날짜타입>_to_string` |
| BIT/VARBIT | 16진 | |
| ENUMERATION | **이름 + ENUM collation**(od:9420) | `…_enumeration_to_string` |
| JSON/CLOB | 문자열화 | |
| 목표 collation·codeset | 인쇄 결과는 목표 도메인의 codeset·collation 으로 만든다(`db_make_char (precision, …)`, 패딩 없음 od:5695) | |

### 2.4 문자 → 문자 (collation 축 셀, #322 C1·C12)

| 조건 | 규칙 | 모드 차이 | leaf |
|---|---|---|---|
| codeset 같고 collation 다름 | **복제 + 라벨만** 교체(`pr_clone_value` + `db_string_put_cs_and_collation`) — 원 값은 const 이므로 `tp_value_slam_domain`/`tp_can_steal_string`(od:9186) 제자리 경로는 쓰지 않는다 | 없음 | `tp_value_convert_string_relabel` |
| codeset 다름 | `db_char_string_coerce`(od:9195) 로 재코딩; 변환 불가 → INCOMPATIBLE(-622 계열은 게이트 collation 병합 단계 `domain_resolve` 가 낸다, 표는 재코딩만) | ASSIGN: 절단이면 `allow_truncated_string` 따라 OVERFLOW(현행 명시 캐스트 의미 od:9200) · COMPARE/OPERAND: 목표가 floating VARCHAR 라 절단 없음 | `…_string_recode[_assign]` |
| 같은 codeset·collation, VARCHAR→CHAR(n) | **항등 유지**(D-327-01, pd:3128 의 의미: 값·collation 모두 원 값) — CHAR↔VARCHAR trailing space 비교 규칙 현행(#321 §2.4) | ASSIGN 은 오늘도 바인드 시점엔 원 값 유지, 저장 시 `mr_writeval` 이 패딩 — 표는 항등, 절단 검사는 저장 경로 현행 | NULL(항등) |
| CHAR→VARCHAR | 항등(trailing space 는 값에 있음) | | NULL |

### 2.5 날짜·시간

| 원 → 목표 | ASSIGN | COMPARE / OPERAND | leaf |
|---|---|---|---|
| CHAR/VARCHAR → DATE/TIME/TIMESTAMP*/DATETIME* | `tp_atodate`·`tp_atotime`·`db_string_to_*`·세션 TZ(od:7921~8806); 실패 → DOMAIN_ERROR(→ -494 재사상, §2.7) | 같음(strict 도 파싱 뒤 같은 검사 od:6270~) | `tp_value_convert_string_to_<날짜타입>` |
| DATETIME*/TIMESTAMP* → DATE | 절단 | **time == 0 일 때만**(od:6311), 아니면 INCOMPATIBLE → 비교는 KEEP(DATE vs DATETIME 은 rank 로 DATETIME 비교 = 현행 — 오늘 `date_col = ?` 에는 클라이언트 캐스트가 없다, #323 P-3) | `…_to_date[_strict]` |
| DATE → DATETIME*/TIMESTAMP*, TIMESTAMP ↔ DATETIME, TZ ↔ LTZ | 확대·세션 TZ 변환 | 같음 | |
| SHORT/INTEGER/BIGINT → TIME | `값 % 86400` 초(od:8713) | **INCOMPATIBLE**(strict 표에 없음 od:6270; 비교는 KEEP → TIME vs INT 는 rank 비교 = 현행) | `…_integer_to_time` (COMPARE/OPERAND 는 incompatible) |
| FLOAT/DOUBLE → TIME | ROUND → 위 | INCOMPATIBLE | |
| 숫자 → DATE/TIMESTAMP*/DATETIME* | INCOMPATIBLE(od:7940) | 같음 | `tp_value_convert_incompatible` |

### 2.6 ENUM · BIT · 컬렉션 · 객체 · JSON · LOB

| 원 → 목표 | 규칙(세 모드 동일 — strict 개념 없음) | leaf |
|---|---|---|
| SHORT/INTEGER/BIGINT → ENUM(dst) | **서수**; USHORT 밖·원소 수 초과 → INCOMPATIBLE; 0 → 특수 오류 값(od:9640~9660) | `tp_value_convert_integer_to_enumeration` |
| FLOAT/DOUBLE/NUMERIC/MONETARY → ENUM | **`floor` 뒤 서수**(od:9660~9705 — 정수 목표의 ROUND 와 다름) | `…_real_to_enumeration` |
| CHAR/VARCHAR → ENUM | 목표 codeset 변환 → **ENUM 도메인 collation** 으로 이름 매칭(CHAR 면 trailing space 무시); 없음 → INCOMPATIBLE, 빈 문자열 → 특수 값(od:9710~9800) | `…_string_to_enumeration` |
| 날짜·BIT·LOB → ENUM | 문자열화 뒤 이름 매칭(od:9820, leaf 끼리 직접 호출 — `tp_value_cast_internal` 재귀 금지) | |
| ENUM → ENUM | 목표 원소 0 이면 복제(파서의 원소 없는 ENUM 도메인, #313 B14); 이름 → 서수 재매핑 | |
| ENUM → 숫자 | 서수 SHORT 뒤 §2.1 | `…_enumeration_to_<숫자>` |
| CHAR/VARCHAR → BIT/VARBIT | 16진 파싱(od:9990~); 절단 규칙 ASSIGN 만 | |
| SET/MULTISET/SEQUENCE ↔ | 같은 도메인이면 항등, 아니면 `set_coerce`(od:9161, 묵시 플래그는 ASSIGN 에서만 false) | `tp_value_convert_collection` |
| OBJECT/OID | 클라이언트만 — 서버 leaf 는 `tp_value_convert_incompatible`(오늘도 `assert_release`) | |
| JSON → 스칼라 | 벗기기(od:7058~7130) — 원 타입 JSON 의 모든 셀이 먼저 이것을 거친다 | `tp_value_convert_json_to_<T>` |
| BLOB/CLOB | ASSIGN 만(문자 ↔ CLOB), 나머지 incompatible | |

### 2.7 반환 상태와 실패 정책 결합

- leaf 반환: `DOMAIN_COMPATIBLE` / `DOMAIN_INCOMPATIBLE` / `DOMAIN_OVERFLOW` / `DOMAIN_ERROR`(아래 셀만).
- 호출자(게이트 K 1회 · 행 kernel R · 스코프 S · 휘발 V) 는 항목의 `fail[i]` 로: **ERROR** → `tp_domain_status_er_set (status, …, src, dst_domain)`(od:11569: INCOMPATIBLE → -494 `ER_TP_CANT_COERCE` "원타입 → 목표타입", OVERFLOW → -493 `ER_IT_DATA_OVERFLOW`, DOMAIN_ERROR 는 -493 이면 OVERFLOW 아니면 INCOMPATIBLE 로 재사상) — 오늘과 같은 코드·메시지; **NULL** → 목표 typed NULL(`return_null_on_function_errors` no 면 ERROR 경로; DOMAIN_ERROR 셀은 오늘 `tp_value_auto_cast` 처럼 `er_clear` 1회 — 게이트·행 모두 실패한 그 호출에서만); **KEEP** → 원 값 유지 + KEEP_LAZY 슬롯 `domain_resolve (DOMAIN_CTX_COMPARE, …)` 1회(게이트) — COMPARE 모드 leaf 는 오류를 세팅하지 않으므로 `er_clear` 없음.
- DOMAIN_ERROR 를 낼 수 있는 셀(오류를 안에서 세팅): 문자 → 날짜·시간 파싱(`db_string_to_*` 가 er_set), JSON 검증, `set_coerce`, codeset 재코딩. 이들은 COMPARE 모드에서 KEEP 정책과 만나면 안 된다 — 문자 → 날짜 비교(`date_col = ?` 문자 바인드 B11)는 실패 정책이 ERROR(-494 현행)이므로 충돌 없음. 검수 항목: KEEP 정책 항목의 leaf 가 DOMAIN_ERROR 셀이면 로드 경계 (a) 에서 assert.

### 2.8 `domain_converter_name` (덤프)

leaf 포인터 → 이름 정적 배열 `domain_convert_names[]`(`{fn, "string_to_integer_strict"}` …), 선형 탐색(덤프 전용). 이름은 leaf 함수 이름에서 `tp_value_convert_` 를 뗀 것.

---

## 3. `domain_resolve` 케이스 본문 — 출처와 이관 규칙 (P6)

`domain_resolve (ctx, opcode, operands, n, consumer_domain, &result, &needs_gate)` 는 순수 함수다. 아래 표의 "원 자리" 는 값 격자가 오늘 사는 곳이고, "이관" 은 그 규칙을 어떻게 옮기며 원 자리는 무엇이 남는지다. **NUMERIC 결과 p/s 는 옮기지 않는다** — 산술 결과 도메인은 floating NUMERIC(40,0)(tc:11570, `tp_Numeric_domain` od:308)이고 p/s 는 값 연산(`numeric_db_value_*`·`float_numeric_db_value_*`)이 정하므로(#321 §2.1.1) `domain_resolve` 는 p/s 를 계산하지 않는다.

| ctx / opcode | 규칙(#321) | 원 자리 | 이관 |
|---|---|---|---|
| ARITH `T_ADD`·`T_SUB`·`T_MUL`·`T_DIV` | 사전 캐스트 격자: 숫자×문자 → 문자 DOUBLE; 문자×문자 → `plus_as_concat` 이면 접합(VARCHAR, `+` 만) 아니면 DOUBLE; 날짜×실수/문자 → BIGINT(`+`), `-` 는 문자 → TIME/DATETIME 파싱 → 날짜−날짜; 정수×NUMERIC → NUMERIC; ×DOUBLE → DOUBLE; ×MONETARY → MONETARY; 날짜±정수 → 날짜; 날짜−날짜 → INTEGER(일/초)·BIGINT(ms); ENUM `+` 는 상대 문자면 이름 아니면 서수, `- * /` 는 서수; 컬렉션 합/차 | qo:2438~2560(add), 4818~4910(sub), 5512~5560(mul), 6134~6260(div) 의 `tp_value_auto_cast` 사전 캐스트 블록 + ENUM 블록 qo:2461·4838 | 격자를 `domain_resolve` 케이스로 옮기고 결과 도메인 + 좌·우 변환기(OPERAND 모드)를 낸다. `qdata_*_dbval` 의 사전 캐스트 블록은 삭제하고 값 타입 dispatch(S-08)만 남긴다 — 들어오는 값은 계획 도메인과 같다는 불변식(assert) |
| ARITH `T_INTDIV`·`T_MOD` | 둘 다 BIGINT 정수 연산; DIV 결과 = 왼쪽 정수 타입, INTMOD BIGINT; 비정수 → -3007 | qo:8445~8520 | 케이스로; 오류는 로드 시 경계 (a) 로 앞당기지 않는다(값 의존 아님, 컴파일이 이미 CAST) |
| ARITH `T_UNMINUS`·`T_ABS`·`T_CEIL`·`T_FLOOR`·`T_ROUND`·`T_TRUNC` | 결과 = 인자 타입; 문자 → DOUBLE(`tp_value_str_auto_cast_to_number` od:11435) | ar:96·265·580·2350·3360 첫머리 switch | 결과 도메인 규칙만 케이스로(값 연산은 그대로) |
| ARITH 결과 → XASL 도메인(A17) | 통과 | qo:2383 `qdata_coerce_result_to_domain` | 컴파일 확정 도메인이므로 호출 유지, VARIABLE 탈착(fe:1316)·복원(fe:4603)만 삭제(#323 §7) |
| COMPARE | 방향 표: 문자 vs 숫자 → 둘 다 DOUBLE; 문자 vs 날짜 → 문자를 날짜 타입으로; 그 외 `tp_more_general_type`(rank od:111) 상위; ENUM 은 상대 쪽(이름은 ENUM collation·codeset); 문자 vs 문자 → `LANG_RT_COMMON_COLL` | od:10524~10608(`tp_value_compare_with_error` 의 coercion 블록) | 방향 규칙을 **순수 헬퍼** `tp_value_compare_common_domain (vtype1, vtype2, …)` 로 뽑아 `tp_value_compare_with_error` 와 `domain_resolve` 가 함께 쓴다(함수 본체는 남는다 — 인터페이스 §7 "남는 것"; 규칙 두 벌은 만들지 않는다). 결과 = 비교 도메인 + conv[0]/conv[1](COMPARE 모드) |
| COMMON_VALUE(NVL/COALESCE/NVL2/NULLIF/LEAST/GREATEST/CASE 게이트 확정) | 같은 부류면 rank 상위, 부류 다르면 VARCHAR | od:11480 `tp_infer_common_domain` | 함수 자체를 `domain_resolve` 케이스로 이동, fe:3306~3961 호출(S-04) 삭제. U7 사슬(D-327-07)은 컴파일이 `recursive_type` 으로 미러하므로 여기는 게이트 확정 사슬(U10)만 |
| AGG(함수별) | COUNT → BIGINT; MIN/MAX/BIT_* → 인자 도메인; SUM/AVG 숫자 → NUMERIC 이면 floating NUMERIC, FLOAT → DOUBLE, 그 외 값 타입(SUM 결과 = 인자 타입, AVG 결과 DOUBLE); SUM/AVG 문자 → DOUBLE; GROUP_CONCAT 비문자 → VARCHAR; STDDEV/VARIANCE → DOUBLE; MEDIAN/PERCENTILE → 숫자·날짜면 그대로, 그 외 게이트 값 타입에 DOUBLE→DATETIME→TIME 순(F7; 컬럼 문자 인자 F10 은 RESIDUAL); JSON_* → JSON | qx:21504~21630(`qexec_resolve_domains_for_aggregation`), qx:21716~21730 | 함수 삭제(#323 §7) 후 규칙은 케이스로; 결과 = 누산 도메인(value_dom) + 결과 도메인 + 인자 변환기(OPERAND) |
| ANALYTIC | AGG 와 같은 함수 규칙 + LEAD/LAG/FIRST/NTH_VALUE → 인자 도메인, NTILE → INTEGER | qn:188~259 | 같음 |
| FUNC_ARG(값 부류 오버로드가 있는 함수, 규칙표 F4·F1·F3) | `ADDTIME`: 왼쪽 문자 → 파싱되면 DATETIME(TZ)/TIME, 아니면 VARCHAR; DATETIME* → 같은 타입; TIME → TIME(so:7302~7420) · `TO_CHAR` → VARCHAR 고정 · `STR_TO_DATE`: 포맷 토큰으로 DATE/TIME/DATETIME(so:22482) · `HOURF/MINUTEF/SECONDF/UNIX_TIMESTAMP/EXTRACT/DATEDIFF/BIT_LENGTH/OCTET_LENGTH` → INTEGER 고정 · `TIMEDIFF` → TIME · `FROM_TZ/NEW_TIME/TO_*_TZ` → 시그니처 결과 타입 고정 · `HEX/CONV/ASCII` → VARCHAR/INTEGER 고정 | 각 함수 구현 첫머리의 결과 타입 switch | 결과 타입이 **고정**인 함수는 케이스가 상수 한 줄; 값 부류로 갈리는 것은 `ADDTIME`·`STR_TO_DATE`(포맷 슬롯일 때) 둘뿐 — 그 결과 규칙을 케이스로 옮기고 함수 구현의 결과 타입 결정은 그대로 둔다(함수는 값을 만들 때 어차피 타입을 정한다; 도메인 해석기는 **미리** 같은 답을 낸다 — 일치는 게이트 CTP 셀 F4 로 확인) |
| LIST_COLUMN | 생산자 항목 ALIAS(#323) — 규칙 없음; 집합 연산 `qfile_unify_types` 의 "다르면 -3020, 가변 문자열 p 차이만 허용" 검사는 컴파일 확정 도메인끼리 로드 경계 (a) 에서 | lf:890~950 | 로드 검사로 이동 |
| collation(문자 결과 전부) | `LANG_RT_COMMON_COLL`(ls:65): 같으면 그것 / 한쪽 coercible 이면 다른 쪽 / 둘 다 coercible 이면 ISO 바이너리 / 둘 다 비-coercible → -1150 / codeset 불가 → -622 | 매크로 그대로 | 케이스가 매크로를 호출; 오류 코드 불변(D-322-01) |

`needs_gate`: 로드는 `val_type = DB_TYPE_NULL` 인 피연산자(GATE 슬롯·게이트 의존 자식)가 하나라도 있으면 true 를 돌려주고 결과를 채우지 않는다.

---

## 4. 상관 복합 키 원소 `strict_conv` (인터페이스 §5)

`domain_plan_key_elem.strict_conv = domain_lookup_converter (원소 regu 의 계획 도메인 타입, index_elem, DOMAIN_CTX_KEY_ELEM)` = COMPARE 모드 leaf. range open 마다 원소별로 호출해 성공이면 `index_elem`, 실패면 `keep_elem` 을 고른다(결정 0). 단일 컬럼 키(B30)도 같은 leaf 를 스캔 준비에서 1회 부른다 — 현행 "단일 컬럼은 변환 없음, 인덱스 쪽이 매 비교 변환"(#321 §4.2)이 "값 쪽 1회 strict, 실패 시 값 도메인 키 + 계획된 원소 변환기" 로 바뀌며 답은 같다(B30 실측).

---

## 5. 규칙표 S4/S5 "실행 중 세션변수 타입 변경" — 값 A/B (D-323-18 판정 입력)

A = develop `cad27172b` optdebug 실측(2026-09-22, `dpin_probe`, `.git_ignored_dir/scratch/312-325/probe/out-optdebug.txt`·`out-optdebug-nullonerr.txt`, 코어·assert 0). B = 이 설계의 예측(§1 모드 + D-325-10·11). 테이블 `tv(i int)` 3행, 각 블록은 `SET @v` 뒤 SELECT 하나가 읽고 재대입한다. `yes` = `return_null_on_function_errors=yes`.

| # | 문장 | 규칙 행 | A (default) | A (yes) | B (default) | B (yes) | 판정 입력 |
|---|---|---|---|---|---|---|---|
| P-S1 | `SET @v=1; SELECT @v, (@v := 'x') FROM tv` | S5 리스트 컬럼 | -494 (character → integer) | `(1,'x')`, `(NULL,'x')`, `(NULL,'x')` | 게이트 도메인 INT(초기값); 행 2 `'x'`→INT 실패 → -494 | NULL(D-325-11) | **불변** |
| P-S2 | `SET @v=1; SELECT (@v := @v + 1), (@v := '2.5') FROM tv` | S4 리터럴 미러 | `(2,'2.5')`, `(4,'2.5')`, `(4,'2.5')` — 행 2 부터 `'2.5'+1 = 3.5` 가 INT 리스트 컬럼에 반올림 기록되는 **조용한 오답** | 같음 | INT 미러; 행 2 `'2.5'`→INT strict 실패 → -494 | 행 2 부터 NULL | **답안 변경 후보**(조용한 오답 → 오류/NULL, P7 ③ 부류) |
| P-S3 | `SET @v='1'; SELECT @v := @v + 1 FROM tv` | S4 | `2.0e+00, 3.0e+00, 4.0e+00`(DOUBLE) | 같음 | `2, 3, 4`(INT) — 행 1 VARCHAR→INT, 행 2 부터 INT 항등(D-325-10) | 같음 | §7 기재(표기) — 이미 목록 |
| P-S4 | `SET @v=1; SELECT (@v := date'2024-01-01'), @v + 1 FROM tv` | S4 | -494 (varying → double) | `('01/01/2024', NULL)` ×3 | INT 미러; `'01/01/2024'`→INT 실패 → -494 | NULL | **불변** |
| P-S5 | `SET @v=1; SELECT i, i = @v, (@v := '1.5') FROM tv` | S4 비교 미러 | `(1,1)`, `(2,0)`, `(3,0)` | 같음 | 행 2 `'1.5'`→INT strict 실패, 휘발은 KEEP 불가 → -494(D-325-10) | -494(비교는 파라미터 무관) | **답안 변경 후보**(값 → 오류) |
| P-S6 | `SET @v=1; SELECT typeof(@v), (@v := 'x'), typeof(@v) FROM tv` | S5 | `('integer','x','character (-1)')`, 이후 `('character (-1)', …)` | 같음 | `typeof` 인자는 any → 변환 없음, 값 타입 그대로 | 같음 | **불변** |
| P-S7 | `SET @v='2024-01-02'; SELECT to_char(@v, 'YYYY/MM/DD'), (@v := 12345) FROM tv` | S4 F1 | "Invalid format" 오류 | 같음 | DATETIME 미러: 행 1 `'2024/01/02'`, 행 2 `12345`→DATETIME 실패 → -494 | 행 2 NULL | §7 기재(S4 to_char 재포맷) — 오류 시점이 행 1 → 행 2 로 |
| P-S8 | `SET @v=1; SELECT sum(@v), max(@v := concat('a', i)) FROM tv` | S5 집계 | -494 (varying → double) | -494 (파라미터 무관) | 누산 INT; 행 2 `'a1'`→INT 실패 → -494 | NULL → `sum = 1` | default 불변 / **yes 답안 변경 후보**(오류 → 값) |
| P-S9 | `SET @v=1; SELECT @v, (@v := 9223372036854775807) FROM tv` | S5 | -493 (integer overflow) | `(1, …)`, `(NULL, …)` ×2 | BIGINT→INT strict 범위 → -493 | NULL | **불변** |
| P-S10 | `SET @v=1; SELECT (@v + 1), (@v := 4611686018427387904) FROM tv` | S4 | -493 | -493 | INT 미러; 행 2 BIGINT→INT → -493 | NULL | default 불변 / **yes 답안 변경 후보**(오류 → NULL) |

요약: 불변 5(P-S1·S4·S6·S9, P-S8/S10 default) · §7 기존 행 2(P-S3·S7) · **신규 판정 필요 4**(P-S2 조용한 오답 → 오류, P-S5 값 → 오류, P-S8·P-S10 의 `yes` 모드 오류 → NULL/값). 판정은 사용자(D-325-12).

---

## 6. 규칙표 대응 (행 → 모드·셀)

| 규칙 행 | 모드 | 셀 | 비고 |
|---|---|---|---|
| A5·A6·A8'·U2·S4 정수 미러 | OPERAND | §2.1 real→integer strict, §2.2 string→integer strict | §7 답안 변경(-494) 그대로 |
| A5'·A12 NUMERIC/DOUBLE 미러 | OPERAND | §2.1 real→numeric(값 p/s), number→numeric | A12 표기 변경 목록 |
| A7 DIV/MOD, A9 `date_col + ?` | **ASSIGN**(CAST 소비자, D-325-02) | real→bigint ROUND | 답 불변("현행 —") |
| A3' `str_col × ?` DOUBLE | OPERAND | string→double | -181 → -494, `yes` 면 NULL(§7) |
| A13' ENUM `× ?` SMALLINT | OPERAND | real→short strict | §7 |
| B4·B5·B9 `int_col = ?` | COMPARE + KEEP | real→integer strict, string→integer strict | 1.5 → KEEP → 비교 DOUBLE |
| B6 `varchar_col = ?` | COMPARE | §2.3 인쇄 | 현행 클라이언트 캐스트와 같음 |
| B7 `char(n)_col = ?` | COMPARE | §2.4 항등 | D-327-01 |
| B11 `date_col = ?` | COMPARE, 정책 ERROR | string→date 파싱 | 숫자 -494 현행 |
| B13·B14 ENUM 비교 | COMPARE, 정책 ERROR | §2.6 → ENUM | 실수 floor, 범위 밖 -494 |
| B30·B31 키 | COMPARE(KEY_ELEM) | §4 | 인덱스 = 순차 |
| B33 auto-param | 리터럴 도메인이라 대부분 항등; `to_number('3')` NUMERIC 슬롯 ← INT 값은 number→numeric(값 p/s) | | L-22 불변식 |
| B34 LIMIT/KEYLIMIT BIGINT | ASSIGN(현행 `tp_value_cast` 의미, 문자 파싱 허용) | string→bigint | |
| U0 대입 | ASSIGN | 전부 | 반올림 2, 날짜 ← 숫자 -494 |
| U7·U13 공통값 미러 | OPERAND | 형제 타입 셀 | |
| F1·F1-T·F3·F5·F6 | OPERAND(값 슬롯 미러) | string→datetime/time, 인쇄 | |
| F7 집계 인자 | 게이트 확정 → 항등; 누산기 변환기는 `domain_resolve (AGG)` 결과에 OPERAND | | |
| S4·S5 | OPERAND(리스트 컬럼·산술), COMPARE(비교) + D-325-10 | | §5 |
| §6 C1·C12 ENFORCE | 세 모드 공통 §2.4 relabel/recode | | -622 는 병합 단계 |

---

## 7. 검수 항목(구현 게이트에 넣는 것)

1. **leaf 에 타입 switch 없음**(D-325-04): `tp_value_convert_*` 본문에서 `switch (DB_VALUE_TYPE`·`switch (original_type`·`tp_value_cast`·`tp_value_coerce`·`db_value_coerce` 호출 0 — grep 게이트.
2. **두 큰 함수의 동작 불변**: 추출 커밋은 `tp_value_cast_internal`·`tp_value_coerce_strict` 의 switch 구조를 유지하고 본문만 leaf 호출로 바꾼다; 그 커밋 단독으로 양 빌드 green + CTP sql 전수(optdebug) 무 diff.
3. **모드 표의 빈 셀은 전부 `tp_value_convert_incompatible`**(NULL 아님) — NULL 은 항등(D-325-06). 정적 검사: 표 초기화 뒤 `NULL` 셀 수 == 항등 셀 수.
4. KEEP 정책 항목의 leaf 가 DOMAIN_ERROR 셀(§2.7)이면 로드 경계 (a) assert.
5. 게이트 뒤 불변식: 상수 참조 `DB_VALUE_DOMAIN_TYPE (vals[ref]) == TP_DOMAIN_TYPE (RESOLVED (…)->domain)` 이거나 KEEP 기록(인터페이스 §3.1 6).
6. F4 함수 결과 도메인 = 함수가 실제로 만든 값의 타입 — 게이트 CTP 셀 F4(`addtime`·`str_to_date` 포맷 슬롯)에서 assert 로 확인.

---

## 8. cpp-perf-rules 대응

| 규칙 | 이 문서 |
|---|---|
| BR-06·A61 | leaf = (원×목표×모드) 고정 함수, 행 루프는 항목 포인터 호출; 휘발 항목만 타입 변경 행에서 표 재조회(분기 1) — D-325-04·10 |
| BR-04·A59 | 모드·leaf 선택은 로드(C 항목)·게이트(G 항목) 1회; NULL 검사는 kernel 준비 지점이 아니라 값마다(값 의존) — D-325-08 |
| MEM-05 | 표 40KB 는 `.rodata`, 조회는 로드·게이트만 — 행 캐시 라인 무관(D-325-05) |
| ALLOC-01 | leaf 는 목표 값 하나만 만든다(`db_make_*`/`pr_clone_value`); 문자 relabel 은 복제 1회, 제자리 슬램 금지(§2.4) |
| 규약 3(안전 > 성능) | 반환은 상태, `er_set` 은 정책을 아는 호출자(D-325-07) |
| PHYS-02 | leaf 프로토타입은 새 헤더 `object/object_domain_convert.h`(object_domain.c 와 `query/domain_resolver.c` 만 포함) — `object_domain.h` 의 CCD 를 늘리지 않는다 |

---

## 9. 렛저 대응

| L | 이 문서 |
|---|---|
| L-11 | §2.1 precision 40 = 값 p/s 보존, 고정 p/s 만 반올림(no:6524) |
| L-12 | §1 정수 목표 strict(OPERAND) vs ROUND(ASSIGN·CAST), D-325-02 |
| L-15·L-32 | §5, D-325-10·11 |
| L-22·L-49 | §7 5 불변식, B33 |
| L-45 | §4 |
| L-06 | §5 P-S2·P-S5 는 값 A/B 로 판정 입력 |
| L-51 | §3 원 자리 삭제 열 |
