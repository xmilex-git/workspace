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

### 0b. 셀 계약 보완 (D-328-01~07 — 2026-09-22 사용자 승인, #328 코멘트 "결정 기록" 이 정본; #325 정적 리뷰 S1·R1~R6)

ADR 0022 의 원칙(3 모드 · 공유 leaf · 정적 표 · 상태 반환)은 그대로이고, 아래는 그 안의 계약 보완이다. 소스 사실 F-328-01~12 와 develop 실측(§7b)은 #328 해소 코멘트에 있다.

| # | 결정 | 한 줄 근거 |
|---|---|---|
| D-328-01 (S1) | **leaf 검수 범위 = 도달 가능한 호출 경로 전체.** `numeric_db_value_coerce_from_num[_strict]`(no:6574·6776)의 목표 타입 `case` 본문은 `numeric_coerce_num_to_<double\|float\|short\|int\|bigint>[_strict] (src, scale, out) → 상태` 로, `numeric_db_value_coerce_to_num`(no:6427)의 원 타입 `case` 본문은 `numeric_coerce_<double\|float\|short\|int\|bigint>_to_num (…)` 으로 뽑는다(타입 고정 하위 연산). 세 래퍼는 switch 를 유지한 채 하위 연산을 부르고(동작 불변), leaf 는 하위 연산을 **직접** 부른다(래퍼 호출 금지). 검수는 §7-1 의 grep 대상을 leaf + `numeric_coerce_*` 하위 연산 본문으로 넓히고, leaf 별 피호출 함수 목록을 §7-1 표에 정적으로 적어 리뷰에서 본다(호출 그래프 도구 자동화는 하지 않는다) | ADR 0022 Consequences(S1) 가 추출·공유까지 잠갔다; 남은 것은 경계와 검수 방식. 범위는 #329 본문에 편집 |
| D-328-02 (R1) | **절단 셀은 `DOMAIN_TRUNCATED` 를 돌려주고, 수용 여부는 항목이 정한다.** (a) VARCHAR→CHAR(n) 항등은 COMPARE/OPERAND 모드에만(B7·D-327-01 의 뜻). (b) ASSIGN 의 절단 셀 3종(문자→문자(n)·문자→비트(n)·비트→비트(n), od:9100·9166·9201)은 `db_char_string_coerce`/`db_bit_string_coerce` 로 변환한 값을 target 에 남긴 채 절단이면 **`DOMAIN_TRUNCATED`**(`TP_DOMAIN_STATUS` 에 값 하나 추가, leaf 만 돌려준다)를 반환한다. 두 큰 함수는 자기 `coercion_mode` 로 오늘처럼 사상한다(FORCE → COMPATIBLE, 명시 → `allow_truncated_string` yes → COMPATIBLE / no → OVERFLOW + clear, 묵시 → OVERFLOW + clear) — 동작 불변. (c) 게이트·행 kernel 은 항목 플래그 **`DOMAIN_PLAN_TRUNCATE_OK`**(로드가 원 자리에서 정한다: FORCE 자리 = 사용자 `T_CAST` 와 STRICT 플래그 없는 `T_CAST_WRAP` 의 컬럼·세션변수·식 피연산자, fe:3162~3170) 면 TRUNCATED 를 수용하고, 그 밖(대입 U0 · STRICT 시그니처 CAST qx:13952·qo:6913 · **`CAST(? AS T)` 아래 슬롯** = 오늘의 바인드 캐스트 pd:3119) 은 게이트가 1회 읽은 `allow_truncated_string` 으로 yes → 수용 / no → OVERFLOW 로 항목 실패 정책(-493 / NULL) | 오늘 사용자 CAST 노드는 `tp_value_cast_force`(FORCE) 라 컬럼·세션변수·식은 설정과 무관하게 절단되고, 호스트 변수는 클라이언트 바인드 캐스트(명시)가 설정을 본다 — 두 답을 다 지킨다(P0). "ASSIGN = 전부 명시" 로 두면 `CAST(str_col AS CHAR(3))` 이 no 에서 -493 이 되는 답안 변경. 대안(슬롯도 TRUNCATE_OK 로 통일 = 호스트 변수 답안 변경 1건)은 채택하지 않음 |
| D-328-03 (R2) | **피연산자별 목표 도메인**: `RESOLVED_DOMAIN` 에 `const TP_DOMAIN *operand_domain[3]` 을 추가한다. `conv[i]` 는 항상 `operand_domain[i]` 에 대해 조회하고 `domain` 은 결과 도메인만 뜻한다. `domain_resolve` 는 둘 다 채운다. §3 격자에 "피연산자 목표" 열(날짜±정수 = 날짜 그대로 · SHORT/INT/BIGINT 그대로 · 실수/문자만 BIGINT; 날짜−날짜 = 그대로·그대로 → INTEGER/BIGINT; 비교 = 비교 도메인 양쪽). 항목 56B → 80B. 인터페이스 v4 에는 필드 한 줄 추가(D-323 재론 아님) | 날짜 덧셈 kernel 은 DATE 와 정수를 따로 받는다(qo:2353~2374) — 결과 도메인으로 조회하면 INT→DATE 가 INCOMPATIBLE 이 된다 |
| D-328-04 (R3) | **G 노드 안 사전 캐스트의 모드 = ASSIGN**(현행 `tp_value_auto_cast` = `tp_value_cast (…, false)` 명시 = ROUND, od:11404; 실패 정책은 X1 대로 `return_null_on_function_errors`). 날짜×실수/문자 → BIGINT, 숫자×문자 → DOUBLE, 문자×문자 → DOUBLE 이 그것이다. **OPERAND(strict) 는 컴파일이 목표를 정한 미러 슬롯**(A5·A8'·U2·S4 정수 미러, A5'·A12 NUMERIC 미러, F/U 값 슬롯)에만 쓴다. §1 의 "게이트 의존 노드의 피연산자 변환기는 OPERAND" 는 "격자가 정한 모드(사전 캐스트 = ASSIGN, 같은 부류 상향 = 무검사 확대)" 로 고친다 | A8 "현행 그대로": 날짜 산술의 BIGINT 캐스트는 A7·A9(CAST 소비자, D-325-02)와 A8 이 한 규칙(어디서나 ROUND). 실측 `date + 1.5` → +2, `+ 2.5` → +3, `+ 0.4` → +0, `+ '1.5'` → +2. 모드는 셋 그대로, 사상만 바뀐다 |
| D-328-05 (R4) | **strict-or-keep 은 판정, KEEP 뒤 비교 변환기는 ASSIGN 셀.** ① KEEP 판정(게이트 상수 1회 · 상관 키 range open · 키 원소) = COMPARE 모드 leaf(strict) 의 성공/실패. ② KEEP 뒤 실제 비교 = `domain_resolve (COMPARE)` 가 비교 방향 헬퍼(rank od:111)로 비교 도메인을 정하고 행 kernel 의 `conv[0]/conv[1]` 은 그 비교 도메인에 대해 ASSIGN 셀로 조회한다 — 현행 `tp_value_compare_with_error` 의 `tp_value_coerce`(od:10624, 묵시)와 도달 가능한 셀(같은 부류 확대 · INT→TIME %86400 · 문자·숫자 → DOUBLE)에서 같다(묵시/명시 차이는 문자 절단·숫자→문자 금지뿐이고 비교 목표는 floating VARCHAR 라 도달 불가). §2.5 INT→TIME COMPARE 셀은 incompatible 그대로. 인덱스 키는 §4 대로 ① 실패 원소가 `keep_elem`, 인덱스 쪽 비교가 ② | INT 3600 vs TIME 01:00:00 은 ① 실패(od:6270 strict 에 INT→TIME 없음) → KEEP → ② TIME 방향(rank 에서 TIME 이 INT 뒤) INT→TIME 성공(od:8713) → 동등 = 현행(실측 `time_col = ?` 3600·90000 → 1행, 순차 = 인덱스) |
| D-328-06 (R5) | **값 분류는 게이트의 별도 함수, `domain_resolve` 는 타입만 본다.** 게이트는 값 부류 오버로드 자리(F7 MEDIAN/PERCENTILE 슬롯 · F4 STR_TO_DATE 포맷 슬롯 · ADDTIME 왼쪽 문자 슬롯)에 대해 `domain_resolve` 전에 `domain_classify_value (ctx, opcode, arg_index, const DB_VALUE *) → DB_TYPE`(domain_resolver.c, 서버 전용, 게이트에서만 1회)을 부르고 결과를 `DOMAIN_OPERAND.val_type` 으로 넣는다. 분류 규칙 = 오늘 그 함수의 첫머리 그대로: MEDIAN/PERCENTILE → DOUBLE→DATETIME→TIME 순 파싱 시도(qx:21713~21735, 파싱은 D-328-07 의 상태 전용 코어), STR_TO_DATE → `db_check_time_date_format`(so:22578~22602), ADDTIME 문자 → 존 있으면 DATETIMETZ 아니면 VARCHAR(so:7335~7396), 실패 → 함수의 현행 오류 코드. 변환기는 **원 값 타입 → 분류 목표**로 조회한다(D-335-04 정정 — `val_type` 은 해석기가 목표를 고르는 입력일 뿐, 그것으로 조회하면 항등이 된다: MEDIAN 문자 '1.5' → DOUBLE 은 VARCHAR→DOUBLE ASSIGN 셀 = 오늘의 명시 캐스트 qx:21721). 휘발 값은 D-325-10 대로 타입이 바뀐 행에서만 재분류. F10(컬럼 인자)은 D-335-10 으로 컴파일 DOUBLE(값 분류 없음) | `DOMAIN_OPERAND` 에 값을 넣으면 해석기 순수성(할당 0·er_set 0)이 깨지고 로드 호출과 시그니처가 갈린다. 실측: `median(@m)` '1.5' → DOUBLE · '01:00:00' → TIME · 'abc' → MEDIAN 오류; `addtime(@a, time)` 문자 → VARCHAR, 존 문자열 → DATETIMETZ, 'abc' → time 변환 오류 |
| D-328-07 (R6) | **COMPARE 모드가 닿는 파서는 상태 전용 코어로 쪼갠다.** (a) 날짜 계열 4 코어(`db_date_parse_date/time/datetime_parts/timestamp` 와 `db_string_to_*_ex` 진입, db_date.c) + `numeric_coerce_string_to_num`(`analyze_numeric_string` 오버플로 포함, no:5628~5663)을 "상태만 돌려주는 코어 + `er_set` 하는 기존 이름의 래퍼" 로 나누고(기존 호출자는 래퍼 = 동작 불변), leaf 는 코어만 부른다. (b) D-325-07 의 DOMAIN_ERROR 셀은 JSON 검증·`set_coerce`·codeset 재코딩만 남고 정책 ERROR 자리에만 온다(§7-4 로드 assert 유지). (c) 게이트: KEEP 직후 optdebug `assert (er_errid () == NO_ERROR)` + §7b 수용 사례(날짜 키 파싱 성공/실패 · NUMERIC 오버플로 KEEP · 상관 키 문자→날짜 실패)를 CTP 셀로. od:6971 의 `er_clear` 는 leaf 추출 커밋에서 사라진다. escape hatch: leaf 안 `er_stack_push/pop`(P6 취지와 어긋나 채택 안 함) | KEEP 경로에 "오류를 세팅했다가 버리는" 길을 남기지 않는다(P6·D-325-07). 범위는 #329/#330 본문에 편집 |

develop 과의 기능 차이: 이 7건은 모두 현행 답을 보존하는 계약이다(신규 답안 변경 0). 실행 중(mainblock 안) 도메인 결정도 추가하지 않는다 — 잔존하는 실행 중 판정은 이전에 잠긴 것뿐(휘발 값의 타입 변경 행 재조회 D-325-10, F10 컬럼 인자 — 2026-09-24 D-335-10 으로 컴파일 DOUBLE 이 되어 잔존 판정 없음, 상관 키 원소의 계획된 strict 변환기 적용 §4).

---

## 1. 문맥 → 모드 사상

`DOMAIN_CTX`(인터페이스 §1.3, 9종)는 표의 첫 인덱스인 **모드** 셋으로 줄어든다. 모드는 "실패를 어떻게 정의하는가" 만 다르고 성공 시 값은 같다.

| 모드 | 현행 함수 | `DOMAIN_CTX` · 자리 | 목표 도메인(조회 키, D-328-03) | 정수 목표 ← 소수 | NUMERIC 목표 ← FLOAT/DOUBLE/MONETARY | 문자 목표 ← 숫자·날짜 | 문자 목표 ← 문자(길이 초과) | DATE ← DATETIME |
|---|---|---|---|---|---|---|---|---|
| **ASSIGN**(대입) | `tp_value_cast (…, implicit = false)` = `tp_value_cast_preserve_domain`(pd:3110)·`qdata_cast_to_domain`(qo:2402)·`tp_value_auto_cast`(od:11404)·사용자 CAST 의 `tp_value_cast_force`(fe:3170 — 절단 3셀만 다르다, D-328-02) | `DOMAIN_CTX_ASSIGN`, **CAST 소비자**(D-325-02), **G 노드 사전 캐스트**(ARITH 격자, D-328-04), **KEEP 뒤 비교 변환**(D-328-05) | 대입 대상 · CAST 목표 · 격자의 피연산자 목표 · 비교 도메인 | **반올림**(od:7331~) | 허용(`numeric_db_value_coerce_to_num`, no:6427) | 인쇄(od:9177~) | 절단 값 + `DOMAIN_TRUNCATED` → 수용은 항목 플래그 `TRUNCATE_OK` 또는 `allow_truncated_string`(D-328-02) | 절단(od:7921~) |
| **COMPARE**(비교·키) | `tp_value_coerce_strict`(od:5743) | `DOMAIN_CTX_COMPARE`, `DOMAIN_CTX_KEY_ELEM` — **KEEP 판정만**(D-328-05) | 형제 미러 도메인 · 키 원소 도메인 | 실패(`modf != 0`) | **실패**(od:6205 — 값 도메인 유지 → KEEP) | 인쇄(문자 목표는 strict 개념이 없다 — B6·B10 현행 클라이언트 캐스트와 같다) | 변환 없음(비교 목표는 floating VARCHAR) | 실패(time ≠ 0) |
| **OPERAND**(피연산자) | `tp_value_auto_cast`(od:11404) 의 자리에 strict 를 넣은 것(D-317-10 "산술 strict") | `DOMAIN_CTX_ARITH`·`_FUNC_ARG`·`_AGG`·`_ANALYTIC`·`_COMMON_VALUE`·`_LIST_COLUMN` 의 **컴파일 미러 슬롯**(A5·A8'·U2·S4·A5'·A12·F/U 값 슬롯 — D-328-04) | 컴파일이 정한 미러 도메인 | 실패 | **허용**(값 p/s 보존 — A5'·A12; §2.2) | 인쇄 | 변환 없음 | 실패 |

- COMPARE 와 KEY_ELEM 이 한 모드인 이유: 인덱스 키 strict-or-keep(sm:1985)과 술어 비교(qe:220)가 같은 성공/실패 판정을 내려야 인덱스 스캔과 순차 스캔의 답이 같다(#321 §4.3, 실측 B30 "전 셀 일치").
- OPERAND 가 COMPARE 와 다른 셀은 **NUMERIC ← FLOAT/DOUBLE/MONETARY 하나뿐**이다(§2.2). `numeric_col + ?` DOUBLE 바인드(A5'·A12)는 성공해야 하고, `numeric_col = ?` 는 실패 → KEEP → 비교 도메인 DOUBLE(현행 rank)이어야 한다.
- 문자 목표(F6 `substr(?)`, B6 `varchar_col = ?`, U6 `CASE … THEN ? ELSE ?`)는 세 모드 모두 인쇄 셀이다 — 오늘 문자 컬럼 형제 슬롯만 클라이언트가 명시 캐스트하던 것(#323 P-3)과 같다.
- 게이트 확정 슬롯(값 타입이 곧 도메인)의 변환기는 항등(NULL)이고, 게이트 의존 노드의 피연산자 변환기는 `domain_resolve` 가 낸 **피연산자별 목표 도메인**(`operand_domain[i]`, D-328-03)에 대해 **격자가 정한 모드**로 조회한다 — 사전 캐스트(날짜×실수/문자 → BIGINT, 숫자×문자 → DOUBLE, 문자×문자 → DOUBLE)는 ASSIGN(현행 `tp_value_auto_cast` = ROUND, 실패 정책 X1), 같은 부류 상향은 무검사 확대(`? + ?` INT·DOUBLE → 목표 (DOUBLE, DOUBLE), conv[0] = int→double), 날짜×정수는 둘 다 그대로(qo:2353 kernel 이 SHORT/INT/BIGINT 를 따로 받는다)(D-328-04).
- KEEP 뒤 비교(D-328-05): COMPARE 모드 leaf 는 KEEP 판정(무손실 검사)에만 쓴다. KEEP 이 난 항목은 `domain_resolve (COMPARE)` 가 비교 방향 헬퍼로 비교 도메인을 정하고 행 kernel 의 conv[0]/conv[1] 은 그 비교 도메인에 대해 ASSIGN 셀로 조회한다 = 현행 `tp_value_compare_with_error` 의 `tp_value_coerce`(od:10624; 도달 셀에서 명시와 동일). 실측: `time_col = ?` INT 3600·90000 → 1행(순차 = 인덱스), `int_col = ?` 1.5 → 0행, `'2'` → 1행.
- **바인드 값 캐스트의 자리(D-335-08, #335 — ADR 0021 정정)**: 호스트 변수 값은 게이트가 아니라 **클라이언트가 문장마다** develop 호출 자리에서 `tp_value_cast_preserve_domain`(= 이 표의 ASSIGN 셀)으로 캐스트하고, 게이트는 값을 바꾸지 않는다(GATE 슬롯의 도메인만 기록). 이유는 리터럴·바인드 문장의 XASL 공유(F-335-04)와 클라이언트 전용 객체 변환(F-335-05). 위 표의 COMPARE·OPERAND 를 호스트 변수에 쓰는 것은 dpin-10 의 미러 슬롯부터다. 기록: strict NUMERIC → 정수·실수 셀(`numeric_db_value_coerce_from_num_strict` 와 하위 연산)은 develop 그대로 **항상 실패**한다(끝의 `return ER_FAILED;`) — KEEP 판정에는 무해하지만 OPERAND 가 미러 슬롯에 쓰이기 전(A5' `double_col + ?` NUMERIC 바인드 "변환(값 같음)")에 무손실 판정 leaf 가 필요하다. 컬렉션 셀은 COMPARE 에서 실패하며 `er_set` 을 남긴다(R6 범위 밖, KEEP assert 크래시 F-335-02). 셀을 직접 부르는 호출자는 `tp_value_cast_internal` 앞단의 같은 타입 처리(OID·같은 p/s 의 NUMERIC·JSON 검증 등 — 표 칸이 비어 있다)를 함께 옮겨야 한다(F-335-05의 OID 실패).
- ENUM + 문자(`plus_as_concat=no`)의 ENUM 피연산자는 현행 두 단계(이름 문자열 → DOUBLE, qo:2513~2565)를 한 셀로 합친 표 밖 leaf 하나를 해석기가 `conv` 로 지정한다(D-335-05). 표 칸 (ENUM, DOUBLE) 은 서수 그대로다(ENUM + 숫자·A13').
- 사용자 CAST 노드(T_CAST, STRICT 플래그 없는 T_CAST_WRAP)는 오늘 FORCE 모드(fe:3170)라 절단만 다르다: 표에는 셀이 하나(ASSIGN)이고 절단 수용은 항목 플래그 `DOMAIN_PLAN_TRUNCATE_OK` 가 맡는다(D-328-02). 슬롯이 그 아래에 있으면 오늘의 바인드 캐스트(명시, pd:3119)와 같이 `allow_truncated_string` 을 따른다.

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
| → NUMERIC(dst) | `tp_atonumeric` → `numeric_coerce_string_to_num`(no:5614): 문자열 자체의 p/s → 목표 p/s 로 재 coerce — 파서는 **상태 전용 코어**로 분리해 오버플로 `er_set` 을 래퍼에만 남긴다(D-328-07) | 반올림 | strict 는 오늘 `tp_value_coerce`(od:6459)를 다시 탄다 → leaf 로 펴서 "손실 → INCOMPATIBLE" | `…_to_numeric[_strict]` |

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
| codeset 다름 | `db_char_string_coerce`(od:9195) 로 재코딩; 변환 불가 → INCOMPATIBLE(-622 계열은 게이트 collation 병합 단계 `domain_resolve` 가 낸다, 표는 재코딩만) | ASSIGN: 절단이면 절단 값 + `DOMAIN_TRUNCATED`(아래 행) · COMPARE/OPERAND: 목표가 floating VARCHAR 라 절단 없음 | `…_string_recode[_assign]` |
| 같은 codeset·collation, VARCHAR→CHAR(n) | **COMPARE/OPERAND: 항등**(D-327-01, pd:3128 의 의미: 값·collation 모두 원 값) — CHAR↔VARCHAR trailing space 비교 규칙 현행(#321 §2.4; 실측 `char3_col = ?` 'ab'·'ab ' → 1행, 'abcd' → 0행) | **ASSIGN: 현행 캐스트 본문**(od:9177~9209 `db_char_string_coerce`; 절단이면 절단 값 + `DOMAIN_TRUNCATED`, 결과는 CHAR(n) 값 + 목표 collation 라벨) — 사용자 `CAST(? AS CHAR(n))`·대입 U0 이 여기(D-328-02) | 정책·항목에서 원 값 유지(COMPARE/OPERAND, B7) / 고정 문자 셀(ASSIGN) |
| **절단 셀 3종**(문자→문자(n) od:9201 · 문자→비트(n) od:9100 · 비트→비트(n) od:9166) | leaf 는 절단 값을 target 에 남기고 **`DOMAIN_TRUNCATED`** 를 돌려준다(`TP_DOMAIN_STATUS` 에 값 하나 추가, leaf 만 반환). 두 큰 함수는 자기 `coercion_mode` 로 사상 — FORCE → COMPATIBLE, 명시 → `allow_truncated_string` yes → COMPATIBLE / no → OVERFLOW + clear, 묵시 → OVERFLOW + clear(동작 불변). 게이트·행 kernel: 항목 플래그 `DOMAIN_PLAN_TRUNCATE_OK`(FORCE 자리 — 사용자 T_CAST·STRICT 플래그 없는 T_CAST_WRAP 의 컬럼·세션변수·식 피연산자, fe:3162~3170) 면 수용; 그 밖(대입 U0 · STRICT 시그니처 CAST qx:13952·qo:6913 · `CAST(? AS T)` 아래 슬롯 = 오늘의 바인드 캐스트 pd:3119) 은 게이트가 1회 읽은 `allow_truncated_string` 으로 yes → 수용 / no → OVERFLOW 로 실패 정책(D-328-02). 실측: `CAST(@s AS CHAR(3))` 'abcdef' → 'abc'(양 설정), `INSERT CHAR(3) ← @s` no → -493 / yes → 'abc' | ASSIGN 만 | 위 leaf |
| CHAR→VARCHAR | 정책이 원 값 유지를 선택할 수 있음(trailing space 는 값에 있음); 일반 타입 변환 조회는 문자 leaf | | 계획 항등 / 고정 문자 셀 |

`domain_lookup_converter`는 원 **타입**과 목표 도메인만 받는다(D-325-06). 따라서 이 절의 B7 항등은 정책·항목의 원 값 유지 결정이며, 일반 표의 VARCHAR→CHAR 셀을 NULL로 만드는 규칙이 아니다(D-327-01). 같은 타입의 문자·비트도 표에는 leaf가 있고, leaf에서 목표 파라미터가 이미 일치하면 복제한다. 문자 타입·길이 변경이 필요하면 현행 변환 본문을 거쳐 길이 검사와 절단을 보존한다. 같은 타입·precision·codeset에서 collation만 바꾸는 경로는 복제 후 라벨만 바꾼다.

### 2.5 날짜·시간

| 원 → 목표 | ASSIGN | COMPARE / OPERAND | leaf |
|---|---|---|---|
| CHAR/VARCHAR → DATE/TIME/TIMESTAMP*/DATETIME* | `tp_atodate`·`tp_atotime`·`db_string_to_*`·세션 TZ(od:7921~8806); 파서는 **상태 전용 코어**(D-328-07)라 실패 → INCOMPATIBLE(`er_set` 은 호출자의 실패 정책, -494 현행 코드) | 같음(strict 도 파싱 뒤 같은 검사 od:6270~; od:6971 의 `er_clear` 는 사라진다) | `tp_value_convert_string_to_<날짜타입>` |
| DATETIME*/TIMESTAMP* → DATE | 절단 | **time == 0 일 때만**(od:6311), 아니면 INCOMPATIBLE → 비교는 KEEP(DATE vs DATETIME 은 rank 로 DATETIME 비교 = 현행 — 오늘 `date_col = ?` 에는 클라이언트 캐스트가 없다, #323 P-3) | `…_to_date[_strict]` |
| DATE → DATETIME*/TIMESTAMP*, TIMESTAMP ↔ DATETIME, TZ ↔ LTZ | 확대·세션 TZ 변환 | 같음 | |
| SHORT/INTEGER/BIGINT → TIME | `값 % 86400` 초(od:8713) | **INCOMPATIBLE**(strict 표에 없음 od:6270 → KEEP 판정 실패); KEEP 뒤 비교 변환은 ASSIGN 셀 `…_integer_to_time` 이라 INT 3600 = TIME 01:00:00 이 동등(D-328-05, 실측 1행 · 90000 도 1행) | `…_integer_to_time` (COMPARE/OPERAND 는 incompatible) |
| FLOAT/DOUBLE → TIME | ROUND → 위 | INCOMPATIBLE | |
| 숫자 → DATE/DATETIME* | INCOMPATIBLE | 같음 | `tp_value_convert_incompatible` |
| 숫자 → TIMESTAMP* | 현행 INTEGER 대입 변환(ROUND·범위 검사) 후 음수가 아니면 timestamp 구성 | INCOMPATIBLE | `…_to_timestamp*` |

숫자→TIMESTAMP*는 기존 `tp_value_cast_internal`의 default가 INTEGER 변환을 거치는 지원 경로다. 이전 표에서 DATE/DATETIME과 함께 incompatible로 묶은 설명을 현행 답 보존(D-317-03)에 맞춰 바로잡았다. 고유 셀 추출 시 기준/후보에서 `3600` 및 `1.5`의 CAST 결과가 같음을 확인했다. 변환 규칙을 새로 추가한 것이 아니다.

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

- leaf 반환: `DOMAIN_COMPATIBLE` / `DOMAIN_INCOMPATIBLE` / `DOMAIN_OVERFLOW` / `DOMAIN_TRUNCATED`(절단 셀 3종만, 값은 target 에 있음 — D-328-02) / `DOMAIN_ERROR`(아래 셀만).
- 호출자(게이트 K 1회 · 행 kernel R · 스코프 S · 휘발 V) 는 항목의 `fail[i]` 로: **ERROR** → `tp_domain_status_er_set (status, …, src, dst_domain)`(od:11569: INCOMPATIBLE → -494 `ER_TP_CANT_COERCE` "원타입 → 목표타입", OVERFLOW → -493 `ER_IT_DATA_OVERFLOW`, DOMAIN_ERROR 는 -493 이면 OVERFLOW 아니면 INCOMPATIBLE 로 재사상) — 오늘과 같은 코드·메시지; **NULL** → 목표 typed NULL(`return_null_on_function_errors` no 면 ERROR 경로; DOMAIN_ERROR 셀은 오늘 `tp_value_auto_cast` 처럼 `er_clear` 1회 — 게이트·행 모두 실패한 그 호출에서만); **KEEP** → 원 값 유지 + KEEP_LAZY 슬롯 `domain_resolve (DOMAIN_CTX_COMPARE, …)` 1회(게이트) — COMPARE 모드 leaf 는 오류를 세팅하지 않으므로 `er_clear` 없음; KEEP 직후 optdebug `assert (er_errid () == NO_ERROR)`(D-328-07); **TRUNCATED** → 항목 `DOMAIN_PLAN_TRUNCATE_OK` 또는 게이트가 읽은 `allow_truncated_string` 이면 수용(값은 이미 target), 아니면 OVERFLOW 로 위 정책(D-328-02).
- DOMAIN_ERROR 를 낼 수 있는 셀(오류를 안에서 세팅): JSON 검증, `set_coerce`, codeset 재코딩 — 문자 → 날짜·시간 파싱과 문자 → NUMERIC 은 D-328-07 의 상태 전용 코어로 옮겨 이 목록에서 빠진다. 남은 셀은 COMPARE 모드에서 KEEP 정책과 만나면 안 된다 — 문자 → 날짜 비교(`date_col = ?` 문자 바인드 B11)는 실패 정책이 ERROR(-494 현행)이므로 충돌 없음. 검수 항목: KEEP 정책 항목의 leaf 가 DOMAIN_ERROR 셀이면 로드 경계 (a) 에서 assert.

### 2.8 `domain_converter_name` (덤프)

leaf 포인터 → 이름 정적 배열 `domain_convert_names[]`(`{fn, "string_to_integer_strict"}` …), 선형 탐색(덤프 전용). 이름은 leaf 함수 이름에서 `tp_value_convert_` 를 뗀 것.

---

## 3. `domain_resolve` 케이스 본문 — 출처와 이관 규칙 (P6)

`domain_resolve (ctx, opcode, operands, n, consumer_domain, &result, &needs_gate)` 는 순수 함수다. 아래 표의 "원 자리" 는 값 격자가 오늘 사는 곳이고, "이관" 은 그 규칙을 어떻게 옮기며 원 자리는 무엇이 남는지다. **NUMERIC 결과 p/s 는 옮기지 않는다** — 산술 결과 도메인은 floating NUMERIC(40,0)(tc:11570, `tp_Numeric_domain` od:308)이고 p/s 는 값 연산(`numeric_db_value_*`·`float_numeric_db_value_*`)이 정하므로(#321 §2.1.1) `domain_resolve` 는 p/s 를 계산하지 않는다.

`domain_resolve` 의 출력은 결과 도메인(`domain`)과 **피연산자별 목표 도메인**(`operand_domain[i]`, D-328-03)이며 `conv[i]` 는 후자에 대해 조회한다. 값 부류 오버로드 자리(AGG MEDIAN/PERCENTILE 슬롯 · FUNC_ARG STR_TO_DATE 포맷 슬롯·ADDTIME 문자 슬롯)의 `val_type` 은 게이트가 먼저 `domain_classify_value (ctx, opcode, arg_index, value)` 로 분류해 넣는다(D-328-06) — 해석기는 여전히 타입만 본다.

| ctx / opcode | 규칙(#321) | 피연산자 목표 · 모드(D-328-03·04·05·06) | 원 자리 | 이관 |
|---|---|---|---|---|
| ARITH `T_ADD`·`T_SUB`·`T_MUL`·`T_DIV` | 사전 캐스트 격자: 숫자×문자 → 문자 DOUBLE; 문자×문자 → `plus_as_concat` 이면 접합(VARCHAR, `+` 만) 아니면 DOUBLE; 날짜×실수/문자 → BIGINT(`+`), `-` 는 문자 → TIME/DATETIME 파싱 → 날짜−날짜; 정수×NUMERIC → NUMERIC; ×DOUBLE → DOUBLE; ×MONETARY → MONETARY; 날짜±정수 → 날짜; 날짜−날짜 → INTEGER(일/초)·BIGINT(ms); ENUM `+` 는 상대 문자면 이름 아니면 서수, `- * /` 는 서수; 컬렉션 합/차. **사전 캐스트 뒤 typed dispatch 의 거부·값 없음(D-335-02, #335)**: dispatcher 에 helper 가 없는 첫 피연산자는 거부(-454) — 덧셈은 늘, `- * /` 는 `return_null_on_function_errors` 가 아니면(이면 값 없음); 컬렉션×비컬렉션은 늘 거부; 두 번째 피연산자에 case 가 없는 typed helper 는 오류 없이 값 없음(`DATETIME − TIME`, 숫자 × 비트), 날짜 덧셈만 dispatcher 처럼 거부; 덧셈의 문자·비트 첫 피연산자는 `db_string_concatenate` — 문자×비트 -622 `ER_QSTR_INCOMPATIBLE_CODE_SETS`, 문자·비트가 아닌 상대 -621 `ER_QSTR_INVALID_DATA_TYPE`; NULL 피연산자는 타입을 보기 전에 값 없음 | 좌·우 각각: 사전 캐스트 격자의 목표 — 날짜×실수/문자 → (날짜 그대로, BIGINT) · 날짜×SHORT/INT/BIGINT → (그대로, 그대로; qo:2353 kernel 이 정수를 따로 받는다) · 숫자×문자 → (숫자 그대로, DOUBLE) · 문자×문자 → (DOUBLE, DOUBLE) · 날짜−날짜 → (그대로, 그대로) → INTEGER/BIGINT · 같은 부류 → rank 상위로 (확대, 확대). **모드 = ASSIGN**(현행 `tp_value_auto_cast` ROUND, 실패 정책 X1; D-328-04) | qo:2438~2560(add), 4818~4910(sub), 5512~5560(mul), 6134~6260(div) 의 `tp_value_auto_cast` 사전 캐스트 블록 + ENUM 블록 qo:2461·4838 | 격자를 `domain_resolve` 케이스로 옮기고 결과 도메인 + 좌·우 목표 + 변환기를 낸다. `qdata_*_dbval` 의 사전 캐스트 블록은 삭제하고 값 타입 dispatch(S-08)만 남긴다 — 들어오는 값은 피연산자 목표와 같다는 불변식(assert) |
| ARITH `T_INTDIV`·`T_INTMOD`(`DIV`·`MOD` 키워드, xg:8337~8341) | 둘 다 BIGINT 정수 연산; DIV 결과 = 왼쪽 정수 타입, INTMOD BIGINT; 비정수 → -3007 | (BIGINT, BIGINT) — 컴파일 시그니처 CAST 가 이미 있어 항등 | qo:8445~8520 | 케이스로; 오류는 로드 시 경계 (a) 로 앞당기지 않는다(값 의존 아님, 컴파일이 이미 CAST) |
| ARITH `T_MOD`(`%`·`MOD()` 함수, `PT_MODULUS`, 늦은 바인딩 대상; #335) | `db_mod_dbval`(ar:1965): 문자 첫 피연산자는 DOUBLE(`db_mod_string`), 두 번째 피연산자는 숫자·문자(문자 → DOUBLE). 결과: MONETARY 가 있으면 MONETARY, DOUBLE(문자 포함)이 있으면 DOUBLE, FLOAT 첫 → NUMERIC 상대면 DOUBLE 아니면 FLOAT, NUMERIC 첫 → FLOAT 상대면 DOUBLE 아니면 NUMERIC, 정수 첫 → FLOAT·NUMERIC 상대는 그 타입, 아니면 정수 rank 상위. 그 밖의 쌍은 거부(-454), `return_null_on_function_errors` 면 값 없음 | 문자 → DOUBLE(ASSIGN), 그 밖 그대로 | ar:1965~ `db_mod_<type>` | 케이스로(#335) |
| ARITH `T_UNMINUS`·`T_ABS`·`T_CEIL`·`T_FLOOR`·`T_ROUND`·`T_TRUNC` | 결과 = 인자 타입; 문자 → DOUBLE(`tp_value_str_auto_cast_to_number` od:11435); ROUND/TRUNC 는 날짜 → DATE, 그 밖은 DOUBLE 시도(실패는 값 단위); 부호·ABS/CEIL/FLOOR 의 숫자·문자 아닌 인자는 거부(-454), `return_null_on_function_errors` 면 값 없음 | 인자 목표 = 결과(문자 → DOUBLE 은 ASSIGN) | ar:96·265·580·2350·3360 첫머리 switch | 결과 도메인 규칙만 케이스로(값 연산은 그대로) |
| ARITH 결과 → XASL 도메인(A17) | 통과 | — | qo:2383 `qdata_coerce_result_to_domain` | 컴파일 확정 도메인이므로 호출 유지, VARIABLE 탈착(fe:1316)·복원(fe:4603)만 삭제(#323 §7) |
| COMPARE | 방향 표: 문자 vs 숫자 → 둘 다 DOUBLE; 문자 vs 날짜 → 문자를 날짜 타입으로; 그 외 `tp_more_general_type`(rank od:111) 상위; ENUM 은 상대 쪽(이름은 ENUM collation·codeset); 문자 vs 문자 → `LANG_RT_COMMON_COLL` | (비교 도메인, 비교 도메인). ① KEEP 판정은 COMPARE 셀(strict), ② KEEP 뒤 행 비교 변환기는 ASSIGN 셀(= 현행 `tp_value_coerce` od:10624; D-328-05) | od:10524~10608(`tp_value_compare_with_error` 의 coercion 블록) | 방향 규칙을 **순수 헬퍼** `tp_value_compare_common_domain (vtype1, vtype2, …)` 로 뽑아 `tp_value_compare_with_error` 와 `domain_resolve` 가 함께 쓴다(함수 본체는 남는다 — 인터페이스 §7 "남는 것"; 규칙 두 벌은 만들지 않는다). 결과 = 비교 도메인 + conv[0]/conv[1] |
| COMMON_VALUE(NVL/COALESCE/NVL2/NULLIF/LEAST/GREATEST/CASE 게이트 확정) | 같은 부류면 rank 상위, 부류 다르면 VARCHAR | 각 인자 → 공통 도메인(OPERAND) | od:11480 `tp_infer_common_domain` | 함수 자체를 `domain_resolve` 케이스로 이동, fe:3306~3961 호출(S-04) 삭제. U7 사슬(D-327-07)은 컴파일이 `recursive_type` 으로 미러하므로 여기는 게이트 확정 사슬(U10)만 |
| AGG(함수별) | COUNT → BIGINT; MIN/MAX/BIT_* → 인자 도메인; SUM/AVG 숫자 → NUMERIC 이면 floating NUMERIC, FLOAT → DOUBLE, 그 외 값 타입(SUM 결과 = 인자 타입, AVG 결과 DOUBLE); SUM/AVG 문자 → DOUBLE; GROUP_CONCAT 비문자 → VARCHAR; STDDEV/VARIANCE → DOUBLE; MEDIAN/PERCENTILE → 숫자·날짜면 그대로, 그 외 게이트가 `domain_classify_value` 로 DOUBLE→DATETIME→TIME 순 파싱 시도해 정한 타입(F7, D-328-06; 실측 '1.5' → DOUBLE·'01:00:00' → TIME·'abc' → MEDIAN 오류; 값 없는 문자 인자(컬럼·계산식)는 DOUBLE — F10·F10', D-335-10, 변환기 문자→DOUBLE ASSIGN); JSON_* → JSON | 인자 → 누산 도메인(OPERAND; MEDIAN/PERCENTILE 슬롯의 문자 → 분류 타입은 ASSIGN = 오늘의 `tp_value_cast (…, false)` qx:21721) | qx:21504~21630(`qexec_resolve_domains_for_aggregation`), qx:21716~21730 | 함수 삭제(#323 §7) 후 규칙은 케이스로; 결과 = `domain` 함수 도메인(결과가 캐스트되는 자리) + `operand_domain[0]`/`conv[0]` 누산 도메인(인자 값의 변환 목표); value2 는 함수 상수라 로드가 `domain_plan_acc` 에(#333 정정, 인터페이스 §1.3 AGG/ANALYTIC 읽기) |
| ANALYTIC | 현행 `query_analytic.cpp` 늦은 바인딩 규칙(D-335-01 정정 — 집계 규칙과 다르다, F-333-05): COUNT → BIGINT, AVG/STDDEV/VAR → DOUBLE, SUM 숫자 → 값 도메인 아니면 DOUBLE, MEDIAN/PERCENTILE_CONT 숫자 → DOUBLE 아니면 값 도메인, 그 외(NTILE·LEAD/LAG/FIRST/NTH_VALUE·MAX/MIN 포함) → 값 도메인 | 같음 | qn:188~259 | 같음 |
| FUNC_ARG(값 부류 오버로드가 있는 함수, 규칙표 F4·F1·F3) | `ADDTIME`: 왼쪽 문자 **값**(바인드·리터럴·세션변수) → **존이 있으면 DATETIMETZ, 아니면 VARCHAR**; 값 없는 문자(컬럼·계산식) → VARCHAR(D-335-10, 존은 문자열 안에)(시간 문자열·날짜 문자열 모두; 파싱 실패 → `ER_TIME_CONVERSION`, so:7335~7396 — #325 초판의 "파싱되면 DATETIME/TIME" 은 오기); DATETIME* → 같은 타입; TIME → TIME(so:7302~7420) · `TO_CHAR` → VARCHAR 고정 · `STR_TO_DATE`: 포맷 토큰으로 DATE/TIME/DATETIME/DATETIMETZ(`db_check_time_date_format`, so:22578~22602) · `HOURF/MINUTEF/SECONDF/UNIX_TIMESTAMP/EXTRACT/DATEDIFF/BIT_LENGTH/OCTET_LENGTH` → INTEGER 고정 · `TIMEDIFF` → TIME · `NEW_TIME`: DATETIME → DATETIME, TIME → TIME, 그 밖 -621(so:28216) · `FROM_TZ`: DATETIME → DATETIMETZ, 그 밖 -621(so:28381) · `TO_*_TZ` → 시그니처 결과 타입 고정 · `HEX/CONV` → VARCHAR, `ASCII` → SMALLINT(`db_make_short`) 고정 — **#335 정정**: `TO_CHAR` 는 숫자·날짜 → VARCHAR, 문자는 그대로 돌려준다(so:12587), 그 밖 -621 · 값 복사 `@v := x`(`T_DEFINE_VARIABLE`)·`PRIOR`·`CONNECT_BY_ROOT`·`QPRIOR`, 목표가 VARIABLE 인 `CAST`·`CAST_NOFAIL`·`CAST_WRAP` → 인자 도메인 · NULL 첫 인자(ADDTIME·STR_TO_DATE·NEW_TIME·FROM_TZ·CONV 는 아무 인자)는 값 없음(fetch_peek_arith) | 시그니처 인자 도메인(OPERAND); 값 부류 자리는 `domain_classify_value` 결과(D-328-06) 를 `val_type` 으로 — ADDTIME 문자 슬롯은 분류 결과가 VARCHAR 면 항등, STR_TO_DATE 포맷 슬롯은 분류만(값은 문자 그대로) | 각 함수 구현 첫머리의 결과 타입 switch | 결과 타입이 **고정**인 함수는 케이스가 상수 한 줄; 값 부류로 갈리는 것은 `ADDTIME`·`STR_TO_DATE`(포맷 슬롯일 때) 둘뿐 — 그 결과 규칙을 케이스로 옮기고 함수 구현의 결과 타입 결정은 그대로 둔다(함수는 값을 만들 때 어차피 타입을 정한다; 도메인 해석기는 **미리** 같은 답을 낸다 — 일치는 게이트 CTP 셀 F4 로 확인) |
| LIST_COLUMN | 생산자 항목 ALIAS(#323) — 규칙 없음; 집합 연산 `qfile_unify_types` 의 "다르면 -3020, 가변 문자열 p 차이만 허용" 검사는 컴파일 확정 도메인끼리 로드 경계 (a) 에서 | 생산자 도메인(항등) | lf:890~950 | 로드 검사로 이동 |
| collation(문자 결과 전부) | `LANG_RT_COMMON_COLL`(ls:65): 같으면 그것 / 한쪽 coercible 이면 다른 쪽 / 둘 다 coercible 이면 ISO 바이너리 / 둘 다 비-coercible → -1150 / codeset 불가 → -622 | — | 매크로 그대로 | 케이스가 매크로를 호출; 오류 코드 불변(D-322-01) |

`needs_gate`: 로드는 `val_type = DB_TYPE_NULL` 인 피연산자(GATE 슬롯·게이트 의존 자식)가 하나라도 있으면 true 를 돌려주고 결과를 채우지 않는다.

**게이트 의존 노드의 해석 완결성(#335, 2026-09-23 사용자 지적 — "애매한 경우는 실행에 맡긴다" 철회)**: G1 4단계는 게이트 의존 노드마다 셋 중 하나로 답한다 — 결과 도메인 / 실행 전 오류 / "값 없음". "실행에 맡김"은 답이 아니다(해석기는 모르는 연산자에 `ER_QPROC_DOMAIN_UNRESOLVED` 를 돌려주고 G1 은 optdebug assert + release 오류로 멈춘다 — 추측하지 않는다).
- **대상**: 컴파일이 결과 타입을 VARIABLE 로 남긴 산술·함수 노드 — 늦은 바인딩 목록(`pt_is_op_hv_late_bind` 39개: 인자 하나라도 MAYBE 면 결과 MAYBE, tc:5999)과 GENERIC_ANY 복사(PRIOR·CONNECT_BY_ROOT·QPRIOR) — 중 모든 피연산자의 타입을 게이트가 아는 것(GATE 슬롯·게이트 의존 노드·컴파일 확정 도메인), 그리고 인자가 게이트 의존인 집계·분석 함수. 결과가 컴파일 확정인 노드는 게이트 노드가 아니다(CAST 등).
- **피연산자 타입**: 값을 가진 피연산자(바인드·리터럴)는 **값의 타입**이다 — 실행이 값으로 계산하기 때문이다. 컴파일 도메인이 정해진 비-GATE 바인드의 값 타입이 계획 도메인과 다르던 F-335-06(#335 진단 224건)은 #336 이 닫았다: 사용자 `?` 의 계획 도메인은 **클라이언트가 실제로 캐스트하는 도메인**(`host_var_expected_domains[]`)이고, 캐스트하지 않는 슬롯 — 기대 도메인 없음, ENUM 도메인(CUBRIDSUS-9007), 타입을 못 받은 LIMIT 사본, 그리고 **ENFORCE 플래그 도메인**(collation 축의 형제 collation: `tp_value_cast_internal` 은 문자 값의 collation 만 바꾸고 타입은 두므로 `str_col + ?`·`enum_col + ?`·`ifnull(char_col, ?)` 의 값은 원 타입으로 온다, F-336-01) — 는 GATE 슬롯이다(`pt_make_regu_hostvar`). 게이트 카운터 `Num_domain_bind_plan_mismatch` 가 이 불변식을 실행마다 세고(CHAR↔VARCHAR 는 D-327-01 의 원 값 유지라 같은 부류), optdebug 는 위반에 assert 한다.
- **오류 시점**: 산술 문맥(ARITH)의 거부는 실행 전 오류(D-335-02, 0행·미선택 분기 포함). 함수·집계·분석의 오류(인자 타입·분류 실패)는 develop 처럼 계산할 때 나고, 슬롯에는 "값 없음"을 기록한다. 게이트가 보는 NULL 값(바인드·리터럴)은 산술 문맥에서 NULL 타입이다(연산자가 타입을 보기 전에 값 없음을 낸다).
- **값 없는 문자 인자는 타입으로(D-335-10, 옛 X 폐기)**: 값으로 부류가 갈리는 인자(ADDTIME 왼쪽 문자, MEDIAN/PERCENTILE 문자 인자)가 게이트가 값을 갖지 않는 문자열(컬럼·계산식)이면 ADDTIME 은 VARCHAR(컴파일 시그니처 그대로, `db_add_time` 은 VARCHAR 도메인에서 존 결과를 문자열로), MEDIAN/PERCENTILE 은 DOUBLE(컴파일 `func_type.cpp` 문자 비상수 → DOUBLE; 게이트 의존 문자 식은 해석기가 DOUBLE, 변환기 문자→DOUBLE ASSIGN). 실행은 컴파일 도메인이 고정이면 캐스케이드를 돌지 않고(`qexec_resolve_domains_for_aggregation`·`qdata_evaluate_analytic_func` 첫값 `default:`, 분석 정렬 키 `cmp_dom`) 게이트 노드의 값 없는 피연산자에서는 DOUBLE 로 1회 캐스트한다. 규칙표 F10·F4'·F10'·§7.
- **이관(명시)**: 세션변수 읽기(S5)에 의존하는 노드 → dpin-10(#336); 파생 소비자 — 값 포인터(`TYPE_CONSTANT`: 리스트 컬럼·상관 값)와 리스트 위치(`TYPE_POSITION`), VARIABLE 로 남은 서브쿼리 결과 — 에 의존하는 노드 → dpin-11(#337). 값 포인터는 생산자가 준 타입을 싣고 컴파일 도메인이 그것을 설명하지 못할 수 있다(**F-335-07**: 재귀 CTE 의 `x + ?` 에서 CTE 컬럼 `x` 는 첫 가지대로 INTEGER, 재귀 가지 값은 DOUBLE — #335 게이트 r3 의 유일한 그림자 불일치). 두 경우 모두 그 노드와 위 노드는 #335 에서 게이트 노드가 아니다(로드가 "모르는 피연산자"로 제외).

---

## 4. 상관 복합 키 원소 `strict_conv` (인터페이스 §5)

`domain_plan_key_elem.strict_conv = domain_lookup_converter (원소 regu 의 계획 도메인 타입, index_elem, DOMAIN_CTX_KEY_ELEM)` = COMPARE 모드 leaf. range open 마다 원소별로 호출해 성공이면 `index_elem`, 실패면 `keep_elem` 을 고른다(결정 0). 단일 컬럼 키(B30)도 같은 leaf 를 스캔 준비에서 1회 부른다 — 현행 "단일 컬럼은 변환 없음, 인덱스 쪽이 매 비교 변환"(#321 §4.2)이 "값 쪽 1회 strict, 실패 시 값 도메인 키 + 계획된 원소 변환기" 로 바뀌며 답은 같다(B30 실측).

---

## 5. 규칙표 S4/S5 "실행 중 세션변수 타입 변경" — 값 A/B (D-323-18 판정 입력)

**철회(D-336-A·E, 2026-09-24)**: 아래 B 열의 -494/NULL 예측은 적용하지 않는다. 세션변수의 타입이 실행 중 바뀐 행은 develop 의 늦은 해석(값 타입)으로 계산해 답이 develop 과 같다(P-S2 = 4, P-S5 = (2,0), P-S8·S10 = develop 값). 게이트는 실행 시작 시 저장값 도메인으로 노드를 확정하고, 바뀐 뒤의 행만 `volatile_changed` 로 늦은 해석에 돌아간다(dpin-14 가 표 재조회로 대체).

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

1. **leaf 와 그 호출 경로에 타입 switch 없음**(D-325-04, D-328-01): grep 대상 = `tp_value_convert_*` 본문 + `numeric_coerce_*` 타입 고정 하위 연산 본문(numeric_opfunc.c) — `switch (DB_VALUE_TYPE`·`switch (DB_VALUE_DOMAIN_TYPE`·`switch (original_type`·`tp_value_cast`·`tp_value_coerce`·`db_value_coerce`·`numeric_db_value_coerce_*`(래퍼) 호출 0. leaf 별 피호출 함수 목록(정적, #329/#330 이 채운다):

   | leaf 부류 | 허용 피호출 함수 |
   |---|---|
   | 숫자×숫자 | `tp_value_convert_number<SRC,DST,MODE>` → `tp_numeric_value<T>::get/make`, `tp_numeric_overflow<DST>`, `tp_numeric_from_num<DST,STRICT>` → `numeric_coerce_num_to_<double\|float\|monetary\|short\|int\|bigint>[_strict]`; NUMERIC 목표는 `numeric_coerce_value_to_num<SRC>` → `numeric_internal_double_to_num`/`numeric_internal_float_to_num`, `numeric_coerce_int_to_num`/`numeric_coerce_bigint_to_num`, `numeric_coerce_num_to_num`. 공통은 `OR_CHECK_*_OVERFLOW`, `ROUND`/`modf`/`modff`, `db_get_*`/`db_make_*`, NUMERIC 버퍼·부호·precision/scale 헬퍼. 기존 dispatch 래퍼 호출 없음 |
   | 문자→숫자 | `tp_atof`·`tp_atobi`, `numeric_coerce_string_to_num_status` → `analyze_numeric_string`/`determine_prec_scale`/`numeric_coerce_dec_str_to_num`, 위 숫자 하위 연산. 기존 진입점은 NUMERIC 파서의 오류 보고 래퍼를 호출한 뒤 같은 NUMERIC 셀을 공유한다 |
   | →문자 인쇄 | `tp_ftoa_char/varchar`·`tp_dtoa_char/varchar` → 원 타입 고정 `tp_ftoa_buffer`·`tp_dtoa_buffer`(기존 공개 출력 함수도 공유), `numeric_db_value_print`, `db_*_to_string`, `tp_make_char/varchar_conversion` → `db_make_char/varchar`·`db_char_string_coerce` |
   | 문자→문자·비트 | `db_char_string_coerce`, `db_bit_string_coerce`, `db_string_put_cs_and_collation`, `pr_clone_value` |
   | 문자→날짜·시간 | `tp_ato*_core` → `db_date_parse_*_core`·`db_string_to_*_ex_core`; 날짜 인코딩·timestamp decode·세션 TZ의 직접 도달 경로까지 `date_conversion_error`를 전달한다. 37개 코어의 계산 본문을 기존 오류 보고 진입점과 공유하며, leaf는 보고 래퍼를 부르지 않는다(D-328-07). |
   | ENUM·컬렉션·JSON·LOB | `tp_finish_enumeration_conversion`·`tp_enumeration_to_varchar`·`db_make_enumeration`; ENUM→숫자는 고정 숫자 생성자 또는 `numeric_coerce_value_to_num<DB_TYPE_ENUMERATION>`; `set_copy`·`set_coerce`·`tp_domain_compatible`; `tp_json_unwrap_scalar`·`db_json_*`; `db_*lob_to_*`·`bfmt_print`·`qstr_hex_to_bin`; 다른 고정 셀의 공통 코어(직접 호출). JSON 내부 값 종류 분기는 JSON payload 해석이며 DB_VALUE 타입이나 목표 도메인을 다시 선택하지 않는다. |

   목록 밖의 함수를 leaf 가 부르면 리뷰에서 잡는다(호출 그래프 도구는 쓰지 않는다).
2. **두 큰 함수의 동작 불변**: 추출 커밋은 `tp_value_cast_internal`·`tp_value_coerce_strict` 의 switch 구조를 유지하고 본문만 leaf 호출로 바꾼다; 그 커밋 단독으로 양 빌드 green + CTP sql 전수(optdebug) 무 diff.
3. **모드 표의 빈 셀은 전부 `tp_value_convert_incompatible`**(NULL 아님) — NULL 은 항등(D-325-06). 정적 검사: 표 초기화 뒤 `NULL` 셀 수 == 항등 셀 수.
4. KEEP 정책 항목의 leaf 가 DOMAIN_ERROR 셀(§2.7: JSON·`set_coerce`·codeset 재코딩)이면 로드 경계 (a) assert; 게이트·range open 의 KEEP 직후 optdebug `assert (er_errid () == NO_ERROR)`(D-328-07). 날짜·NUMERIC 파서의 `er_set` 래퍼를 leaf 가 부르면 grep 게이트(1)가 잡는다.
5. 게이트 뒤 불변식: 상수 참조 `DB_VALUE_DOMAIN_TYPE (vals[ref]) == TP_DOMAIN_TYPE (RESOLVED (…)->domain)` 이거나 KEEP 기록(인터페이스 §3.1 6).
6. F4 함수 결과 도메인 = 함수가 실제로 만든 값의 타입 — 게이트 CTP 셀 F4(`addtime`·`str_to_date` 포맷 슬롯)에서 assert 로 확인; `domain_classify_value` 의 답과 함수 첫머리의 답이 같다는 assert 도 같은 자리(D-328-06).
7. **`DOMAIN_TRUNCATED` 는 leaf 만 돌려준다**(D-328-02): 두 큰 함수와 게이트·행 kernel 밖으로 새어 나가지 않는다 — `tp_domain_status_er_set` 에 TRUNCATED 가 도달하면 assert. 로드: `DOMAIN_PLAN_TRUNCATE_OK` 는 사용자 `T_CAST`·STRICT 플래그 없는 `T_CAST_WRAP` 의 비슬롯 피연산자 항목에만 켜진다(슬롯·대입·STRICT 항목은 0) — 정적 검사.
8. **`operand_domain[i]` 불변식**(D-328-03): 게이트 뒤 모든 항목에서 `conv[i] == NULL` 이면 `operand_domain[i]` 의 타입 == 피연산자 값 타입, 아니면 `conv[i]` 의 (원, 목표) == (값 타입, `operand_domain[i]` 타입) — optdebug assert.
9. **수용 사례 §7b 를 sql TC 로 `dpin-tc` 에 추가**(#330 게이트): 현행 답 = expected.

### 7b. 수용 사례 (A = develop `cad27172b` optdebug 실측 2026-09-22, `.git_ignored_dir/scratch/312-328/probe/cell-contract-cases.sql` → `out-optdebug.txt`; 세션변수 = 클라이언트 캐스트 없이 서버가 보는 값. B = 이 계약의 예측. 코어·assert·잔류 오류 0)

| 결정 | 사례 | A(develop) | B | 판정 |
|---|---|---|---|---|
| D-328-02 | `CAST(@s AS CHAR(3))` 'abcdef', `allow_truncated_string` no / yes | 'abc' / 'abc'(character(3)) | TRUNCATE_OK 항목 → 'abc' 양쪽 | 불변 |
| D-328-02 | `INSERT tc(c3 CHAR(3)) ← @s` 'abcdef', no / yes | -493 Data overflow / 'abc' | STRICT 항목 → 파라미터 → -493 / 'abc' | 불변 |
| D-328-02 | `CAST(? AS CHAR(3))` **호스트 변수** 'abcdef', no / yes | 바인드 캐스트 오류(pd:3122) / 'abc' (정적 — csql 은 바인드 불가) | 슬롯 항목(TRUNCATE_OK 0) → -493 / 'abc' | 불변(오류 코드·시점만 게이트로) |
| D-328-02 (B7) | `char3_col = @s` 'ab' / 'ab ' / 'abcd' | 1행 / 1행 / 0행 | COMPARE 항등 → 같음 | 불변 |
| D-328-04 | `date'2024-01-01' + @r` 1.5 / 2.5 / 0.4 / '1.5' ; `- @r` 1.5 | 01/03 / 01/04 / 01/01 / 01/03 ; 12/30/2023 | ASSIGN(ROUND) BIGINT 사전 캐스트 | 불변 |
| D-328-04 | `d + @r` 1.5(컬럼, A9) ; `datetime + 1.5` ; `time + 1.5` | +2일 ; +2ms ; +2초 | 같음 | 불변 |
| D-328-04 (X1) | `date + @r` 'abc', default / `return_null_on_function_errors=yes` ; yes 에서 1.5 | -494 character→bigint / NULL ; 01/03 | 실패 정책 파라미터 | 불변 |
| D-328-05 | `t = @k` 3600 / 90000, `USING INDEX NONE` / `it(+)` | 1행(01:00:00) 전부(순차 = 인덱스) ; `3600 = time'01:00:00'` = 1, 90000 도 1 | strict INT→TIME 실패 → KEEP → ASSIGN `integer_to_time` %86400 → 동등 | 불변 |
| D-328-05 | `i = @k` 1.5 / 1.0 / '1.5' / '2', 순차·인덱스 ; `t > 3600` | 0 / 1 / 0 / 1(i=2) 양쪽 ; i=2 양쪽 | KEEP → DOUBLE 비교 / INT 항등 / 문자·숫자 DOUBLE / 파싱 | 불변 |
| D-328-06 | `median(s)` '1.5','2.5','3.5' / 날짜시각 문자 / 시각 문자 / '1.5','01:00:00' 혼합 / 'abc' | 2.5 DOUBLE / DATETIME / 02:00:00 TIME / -494(첫 값 DOUBLE 고정 뒤 실패) / MEDIAN 도메인 오류 | F10 컬럼: D-335-10 정적 DOUBLE — 날짜시각·시각 문자 → -1118, 나머지 그대로 | **변경 §7**(D-335-10) |
| D-328-06 | `median(@m)` '1.5' / '01:00:00' / 'abc' | 1.5 DOUBLE / 01:00:00 TIME / MEDIAN 도메인 오류 | 게이트 `domain_classify_value` → DOUBLE / TIME / 오류 | 불변 |
| D-328-06 | `str_to_date(x, @f)` '%H:%i:%s' / '%Y-%m-%d' / '%Y-%m-%d %H:%i:%s' | TIME / DATE / DATETIME | 분류 = `db_check_time_date_format` | 불변 |
| D-328-06 | `addtime(@a, time)` '2024-01-01 10:00:00' / '10:00:00' / '… Asia/Seoul' / 'abc' ; `addtime(datetime, time)` ; `addtime(time, time)` | VARCHAR(26) / VARCHAR(11) / DATETIMETZ / time 변환 오류 ; DATETIME ; TIME | 분류 = F-08 격자(§3 교정) | 불변 |
| D-328-07 | `d = @g` 'garbage' 순차·인덱스 ; '2024-01-02' | -494 character→date 양쪽 ; i=2 양쪽 | B11 정책 ERROR(파서 코어 상태 → 호출자 -494) | 불변 |
| D-328-07 | `n = @g` 42자리 문자열 / 1e30 / '1.5' / 1.5, 순차·인덱스 | 0행(오류 없음) / 0행 / i=2 / i=2 양쪽 | 문자·숫자 → DOUBLE 비교, NUMERIC 파서 미도달; 실수 vs NUMERIC KEEP → DOUBLE | 불변 |
| D-328-07 | 상관 키 `tc.d = ts.s`('garbage' 포함) 인덱스/순차 ; `tc.n = ts.s`(42자리 포함) | -494 varying→date 양쪽 ; -494 varying→double 양쪽 | 컴파일 CAST(문자 컬럼 → 날짜/DOUBLE) 가 정책 ERROR — KEEP 미도달 | 불변 |

KEEP 경로에서 날짜 파서·NUMERIC 파서에 실제로 도달하는 모양(상수 슬롯의 `date_col = ?` 문자 바인드는 정책 ERROR, 상관 키는 컴파일 CAST)은 develop 에서 나오지 않았다 — D-328-07 (c) 의 잔류 오류 게이트는 그래서 assert 로 두고, CTP 셀은 위 표를 그대로 고정한다.

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
