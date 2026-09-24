# 타입 규칙표 — 도메인·변환의 확정 시점과 변환기 계획 (정본)

지도: xmilex-git/workspace#312 · 티켓: #317(타입 축) · 짝 티켓: #322(collation 축 — §6, D-322-01~04) · 작성 2026-09-22 · 기준 엔진: `develop` `cad27172b`.
입력: `domain-pin-asis-matrix.md`(전수 실측, 부록 A1~A4) · `domain-pin-rules-parser.md`(#313) · `domain-pin-rules-server.md`(#321) · `domain-pin-exec-sites.md`(#314) · `domain-pin-pg-mysql.md`(#315) · `domain-pin-lessons.md`(렛저).
결정 기록(사용자 답변 원문·근거·예시): #317 코멘트 "결정 기록 1라운드"(D-317-01~09), "2라운드"(D-317-10~15), "3라운드"(D-317-16~24); collation 축은 #322 코멘트 "결정 기록 1라운드"(D-322-01~03), "2라운드"(D-322-04); 탐침(#319) 뒤 개정은 #327 코멘트 "결정 기록"(D-327-01~11, 2026-09-22 — R-1~R-11 전건 승인, 정본은 이 개정판). collation 실측: `.git_ignored_dir/scratch/dpin-322/probe-develop-collation.md`(A~F, develop `cad27172b` release/optdebug).

이 표는 **"어떤 조합이 어떤 도메인이 되는가"** 와 **"그것을 누가 언제 확정하고, 값은 누가 언제 변환하는가"** 를 한 행에 적는다. 아키텍처(#318)·인터페이스(#323)·변환기 티켓(신규)은 이 표를 입력으로 삼고, 여기 없는 규칙은 구현 중 코멘트로 만들지 않고 이 표를 개정해 사용자 승인을 받는다(L-01).

---

## 0. 상위 원칙 (P0~P6)

| # | 원칙 | 결정 | 한 줄 근거 |
|---|---|---|---|
| **P0** | **현행 답 유지.** 규칙표는 답을 바꾸는 표가 아니라 현행 답을 "어느 지점에서 확정하는가" 를 정하는 표다. 예외는 크래시·assert 가 나는 동작(§5)뿐. | D-317-14·15·24 | 사용자 결정. 이전 캠페인 483건 실패 중 정당한 변경 270건이 전부 "규칙을 바꿔서" 생긴 것 |
| **P1** | **형제 미러 → 철회(D-336-B, 2026-09-24).** 컴파일은 슬롯(호스트 변수·세션변수 읽기)의 타입을 만들지 않는다. 컴파일 도메인은 develop 이 이미 클라이언트에서 캐스트하는 자리(비교·대입의 기대 도메인, `host_var_expected_domains[]`; ENUM·ENFORCE collation 자리는 제외 — F-336-01)뿐이고, 그 밖의 슬롯은 전부 GATE 로 서버 게이트가 바인드 값의 도메인을 쓴다. 소비자 도메인 우선(D-327-11)도 함께 철회. (원문: 슬롯의 도메인은 같은 식에서 타입이 알려진 형제를 따른다 — 산술·함수·공통값·집계로 확장, 소비자 도메인 우선.) | D-336-A·B (사용자 2026-09-24: "전부 develop 과 동일 작동, domain 만 gate 에서") | 형제 미러는 develop 의 값 의존 답을 바꾼다(#336 게이트 런 CTP 110건 전부 그 자리) |
| **P2** | **게이트 확정.** 형제가 부류를 못 정하는 자리(형제가 전부 슬롯 / 집계·분석 인자 / ENUM 산술 / 값 요구 함수 인자 / 형제 없는 세션변수)는 컴파일이 "게이트 확정" 으로 표시만 하고 서버 게이트가 바인드 값의 타입으로 **실행당 1회** 확정한다. 행마다 정하는 늦은 바인딩은 전부 삭제. **게이트 의존 상향 전파**: 게이트 확정 식을 피연산자로 가진 노드(`abs(?) + 1`, `(? + ?) + 1`, `coalesce(?, ?) + 1`)도 게이트 의존 노드 — G1 이 생산자 우선 순서로 현행 격자를 1회 적용해 확정한다(D-327-08; 목록 형태·순회는 #323). 게이트 변환 실패의 의미는 문맥별 현행(§4 X1, D-327-10). | D-317-02·12·13·D-327-08·10 | `? + ?` 접합·`enum + ?`·`addtime(?, …)` 등 현행 답 유지 |
| **P3** | **피연산자 3부류 변환 시점.** ① 상수 부류(리터럴 → 컴파일 폴딩, 슬롯 → 게이트 1회) ② 행 의존 부류(컬럼·컬럼 식 → 계획된 변환기로 행마다) ③ 상관 부류(외부 행 값·비상관 서브쿼리 결과 → 스코프 진입 시 계획된 변환기를 1회 적용해 실행 임시값에; 결정은 없다, D-323-08). **④ 휘발 부류**(세션변수·난수·serial 등 `FETCH_NOT_CONST` 연산자: 도메인은 게이트 1회, 값은 행마다 읽어 계획된 변환기, D-323-18 — 인터페이스 정본 `domain-pin-interface.md` §2). | D-317-17·D-323-08·18 | `int_col > 1.5`: 1.5 는 1회, int_col 은 행마다 |
| **P4** | **행당 결정 0회, 변환은 계획된 변환기만.** 비교·범위·키·산술·집계·함수 인자마다 (도메인, 피연산자별 변환기 ID 또는 게이트 슬롯 참조)를 계획에 고정. 실행은 타입 판정(`tp_value_compare_with_error` rank, `tp_value_cast_internal` switch, `qdata_*` 2단 디스패치)을 타지 않고 변환기를 바로 부른다. 변환 방향·도메인은 현행 서버 표(#321 §1·§2)를 그대로 옮긴다. | D-317-16·19 | 분기 예측. 행당 변환 0 이 목표가 아님(Destination 정정) |
| **P5** | **상태는 XASL_STATE, 플랜 불변.** 게이트·스코프당 변환값은 `vd.dbval_ptr[]`(슬롯) 와 계획 슬롯 ID 로 인덱싱되는 게이트 표(XASL_STATE 확장)에 두고, aptr/dptr 는 같은 상태를 공유, PX 는 깊은 복사를 상속. 플랜 안의 DB_VALUE 를 실행이 쓰지 않는다. | D-317-18 | L-42·L-46, `px_query_executor.cpp:48` deep copy |
| **P6** | **중복 메커니즘 제거.** 새 경로가 대체하는 현행 코드(`FETCH_ALL_CONST` 제자리 coerce, rank 판정·`er_clear` 폴백, `need_new_setdomain`/`prebuilt_midxkey_domains`, `resolve_domains_on_list_scan`, 집계 첫 값 대기, 산술 도메인 탈착·복원, `original_domain` 복원)는 남기지 않는다. | D-317-24 | 같은 기능 두 코드 금지 |
| **P7** | **답안 변경 판정.** 규칙표 행에서 기계적으로 도출되고 ① 값 타입으로 의미가 갈리던 동작 제거 ② 오류 시점 이동 ③ 늦은 바인딩 삭제로 오류가 값이 되는 개선 중 하나일 때만 허용. 에러→값은 값 A/B, `silent` 최우선, escape hatch 없음(복구 = 명시 CAST). | D-317-09 | L-06·L-23 |

---

## 1. 확정 시점 부호와 피연산자 부류

- **C** = 컴파일 확정(파서가 도메인을 정하고 변환 계획에 싣는다). **G** = 게이트 확정(바인드 값 타입으로 실행당 1회). **X** = 실행 결정 잔존(컬럼 값 내용에 의존, 슬롯 없이도 갈림 — 삭제 대상 아님, 명시).
- 피연산자: **K** = 상수 부류(리터럴 = 컴파일 폴딩 / 슬롯 = 게이트 1회), **R** = 행 의존(계획된 변환기, 행마다), **S** = 상관(스코프당 1회).
- 변환기 표기 `A→B` 는 (원 타입 A, 목표 B) 고정 함수. `—` 는 변환 없음.

---

## 2. 규칙표 — 산술

비교 도메인·연산 도메인·변환 방향은 **현행 격자**(실측 §3.1, #313 §1.1, #321 §2.1) 그대로다. 표의 "도메인" 열이 그 격자의 결과이고, 이 문서가 새로 정하는 것은 **확정 시점·부류·변환기** 열이다.

| # | 조합 | 도메인(현행 격자) | 확정 | 피연산자·변환기 | 결과 | 답안 변경 |
|---|---|---|---|---|---|---|
| A1 | `int_col + 1` | INTEGER | C | R int —, K 폴딩 | int | — |
| A2 | `int_col + 1.5` | **NUMERIC**(현행; DOUBLE 아님, D-317-23) | C | R int→numeric, K 폴딩 numeric | numeric floating(p/s 는 현행 서버 공식 통과) | — |
| A3 | `int_col + '1'`, `str_col ± num` | DOUBLE | C | R int→double / R str→double | double | — |
| A3' | `str_col * ?`, `str_col / ?`, `str_col % ?` | **DOUBLE**(컴파일이 이미 `CAST(str_col AS DOUBLE)` 시그니처 캐스트를 만든다 — #319 §3.2) → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | R str→double, K 게이트 값→double(실패 정책 = 파라미터, X1) | double | 오류 코드 -181 → -494(P7 ②); `return_null_on_function_errors=yes` 면 NULL 유지 (D-327-03·10) — **철회(D-336-A)**: 답 불변(develop) |
| A3'' | `str_col + ?`, `str_col − ?` | 게이트 확정(P2, 현행 값 격자 — `cannot_use_signature` 라 형제 CAST 없음) | G | K 게이트 | 현행 | — (D-327-03). #336 F-336-01: collation 축이 슬롯에 남기는 VARCHAR **ENFORCE** 기대 도메인은 클라이언트 캐스트에서 collation 만 강제하고 타입은 값 그대로 두므로 계획도 게이트 슬롯이다(`enum_col ± ?`·`ifnull(char_col, ?)` 도 같다) |
| A5 | `int_col + ?` | **INTEGER 미러**(P1) → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | R int —, K 게이트: 값→INT **strict**(소수부 손실 -494, 문자 파싱, 날짜 -494) | int | **있음**: 소수·날짜·문자(비숫자) 바인드 → -494 (현행 값 타입 산술: 1.1 → NUMERIC 2.1, date → date+1). D-317-01·10 — **철회(D-336-A)**: 답 불변(develop) |
| A5' | `numeric_col + ?`, `double_col + ?` | NUMERIC floating / DOUBLE 미러 → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | K 게이트 값→numeric(값 p/s 보존)/double | 현행 표기 유지(`2.20`) | 정수·문자 바인드 → 변환(값 같음); 날짜 → -494 — **철회(D-336-A)**: 답 불변(develop) |
| A6 | `int_col / ?` | INTEGER 미러 → **정수 절삭** → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | 위와 같음 | int(`7/2`=3) | 소수 바인드 → -494 — **철회(D-336-A)**: 답 불변(develop) |
| A7 | `int_col DIV ?`, `MOD ?` | BIGINT(현행 시그니처) | C | K 게이트 값→bigint | 현행 | — |
| A8 | `? + ?`, `? − ?` … | **게이트 확정**(P2): 값 격자(문자·문자 = 접합, 숫자 = 값 타입, 문자·숫자 = DOUBLE, 날짜·숫자 = 날짜, 문자·날짜 = -494) | G | K 게이트(도메인·변환기 채움) | 현행 그대로 | — |
| A8' | `? + 1`, `? − 1` | INTEGER 미러(리터럴 형제) → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | K 게이트 값→INT strict | int | 문자 `'1.0'` → 2(현행 DOUBLE 2.0 표기 변경), 1.5 → -494, DATE → -494(현행 date+1). **있음** — 규모 재확인 뒤 유지(D-327-09: CTP 65곳, §7) — **철회(D-336-A)**: 답 불변(develop) |
| A8'' | `(? + ?) + 1`, `abs(?) + 1`, `coalesce(?, ?) + 1` — 게이트 확정 식 + 형제 | **게이트 의존 노드**: 안쪽 G 결과 도메인과 형제로 현행 격자 → G1 이 생산자 우선 1회(형제 미러는 직접 슬롯 인자에만) | G | K 게이트(안쪽 → 바깥 순) | 현행(`abs(?) + 1` 1.5 → 2.5) | — (D-327-08; 목록·순회는 #323) |
| A9 | `date_col + ?`, `? + date_col` | `CAST(? AS BIGINT)`(현행) | C | K 게이트 값→bigint | date | — |
| A11 | `date_col − ?` | 현행: 정수→DATE, DATE→INT(일), 문자→DATETIME 파싱 후 BIGINT(ms) — 값 타입으로 갈림 | **G** | K 게이트 | 현행 | — (P0; "값에 따라 의미 갈림" 이지만 현행 유지 결정) |
| A12 | `numeric_col(10,2) + ?` | NUMERIC floating 미러 → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | K 게이트 값→numeric(p/s 보존) | `2.20` 유지 | DOUBLE 바인드 → NUMERIC(현행 DOUBLE 결과) 표기 변경 가능 → 목록 — **철회(D-336-A)**: 답 불변(develop) |
| A13 | `enum_col + ?`, `enum_col − ?` | **게이트 확정**: 문자 바인드 → 이름(VARCHAR 접합), 숫자·날짜 → 서수 SMALLINT + 값 격자 | G | K 게이트, R enum→varchar 또는 enum→short 변환기(게이트가 선택) | 현행(`'Cancel-a'`, `2`, date+서수) | — (D-317-12; `*`·`/`·`%` 는 A13' 로 분리 D-327-04) |
| A13' | `enum_col * ?`, `enum_col / ?`, `enum_col % ?` | **SMALLINT 미러**(컴파일이 이미 `CAST(enum_col AS SMALLINT)` 서수 캐스트를 만든다 — #319 §3.2) → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | R enum→short, K 게이트 값→short strict(실패 정책 = 파라미터, X1) | 현행 서수 산술 | #319 §3.2 실측 diff(NULL → 값, double → smallint 표기)는 답안 변경 → §7 (D-327-04) — **철회(D-336-A)**: 답 불변(develop) |
| A14 | `−?`, `abs(?)`, `round(?, n)`, `ceil/floor/trunc(?)` | 게이트 확정(값 타입; 문자 → DOUBLE) | G | K 게이트 | 현행 | — |
| A15 | `int_col + numeric_col`, `str_col + int_col` 등 컬럼×컬럼 | 현행 격자 | C | R·R 변환기 고정(int→numeric, str→double …) | 현행 | — (실행 디스패치만 제거, D-317-19) |
| A16 | `bigint_col + double_col` | DOUBLE(현행, 2^53 손실 현행) | C | R bigint→double | 현행 | — |
| A17 | 산술 결과 → XASL 도메인 coerce(`qdata_coerce_result_to_domain`) | 결과 도메인은 C 로 확정된 연산 도메인; NUMERIC 은 floating 통과(p/s 는 서버 공식) | C | 결과 변환기 —(통과) | 현행 | — |

## 3. 규칙표 — 비교·범위·IN·LIKE·인덱스 키

비교 도메인·변환 방향 = 현행 서버 표(#321 §2.2, 실측 §3.3): 문자 vs 숫자 → 둘 다 DOUBLE, 문자 vs 날짜 → 문자를 날짜로, 숫자끼리·날짜끼리 → rank 상위, BIGINT vs DOUBLE → DOUBLE(손실 현행), CHAR vs VARCHAR → 변환 없음(trailing space 구분), ENUM → 상대 쪽(숫자면 서수, 문자면 이름), 변환 실패 → 현행 rank GT/LT 판정(오류 아님). 이것을 **비교 도메인 표**로 옮기고, 각 술어에 (비교 도메인, 좌·우 변환기)를 계획에 싣는다.

| # | 조합 | 슬롯 도메인 | 비교 도메인·변환기 | 확정 | 결과 | 답안 변경 |
|---|---|---|---|---|---|---|
| B1 | `int_col = 1.5` | (리터럴, auto-param DOUBLE) | 현행: `=` 는 컬럼 타입 시도 → 실패 시 INT vs NUMERIC/DOUBLE 값 비교 → 0행 | C | 0행(반올림 없음) | — |
| B2 | `int_col > 1.5` | DOUBLE(tc:5566) | 비교 DOUBLE, **R int→double 행마다**, K 1.5 — | C | 현행 | — (경계 조정 **철회**, D-317-16) |
| B3 | `str_col = 1` | 리터럴 → 컬럼 타입 VARCHAR `'1'` | 문자 비교, 인덱스 사용 | C | 현행 0행 | — (D-317-03 ①) |
| B3' | `str_col = 1.00`, `= 1.0e0`, `= 1.0f` | 양쪽 DOUBLE | R str→double, K 폴딩; **순차 스캔** | C | 현행 1행 | — (D-317-03 ②, 표기법에 따라 인덱스 사용이 갈리는 현행을 문서화) |
| B4 | `int_col = ?` | INTEGER 미러 | K 게이트 **strict-or-keep**: 손실 없으면 INT 로 변환(비교 INT, 변환기 —), 손실(1.5)이면 값 유지 + 비교 도메인을 현행 표(DOUBLE)로 게이트 확정 + R int→double | C(슬롯)/G(손실 시 비교 도메인) | `'1.0'` → 1행, 1.5 → 0행 | — (D-317-10·16) |
| B5 | `int_col < ?` 1.5 | INTEGER 미러 | 위와 같음 → 비교 DOUBLE, R int→double | C/G | 1행 | — |
| B6 | `varchar_col = ?` | VARCHAR + 컬럼 collation | 정수·numeric 바인드 → 게이트 문자화 → 문자 비교 | C | 현행(정수 1 → `'1'` ≠ `'1.0'`) | — |
| B7 | `char(n)_col = ?` | **CHAR(n) 미러(현행) + 컬럼 collation** | CHAR↔VARCHAR 현행 규칙(trailing space 구분) | C | 리터럴 바인드 현행 1행 유지; VARCHAR(20) 값이 NULL 이던 현행은 결함 → 게이트의 CHAR 변환이 VARCHAR 값의 원 값을 유지(pd:3128 의미)해 값 | 결함 소멸 1건. D-317-04 의 VARCHAR 미러는 **D-327-01 로 철회**(탐침 §3.2: VARCHAR 미러 + trailing-space 구분 = 1행 → 0행, silent P0 위반) |
| B8 | `? = ?`, `? < ?` | 게이트 확정 | 게이트가 값 격자로 비교 도메인·변환기 채움(문자·숫자 → DOUBLE) | G | 현행(`'01' = 1` 참) | — (D-317-02) |
| B9 | `? = 1`, `? BETWEEN 1 AND 10`, `? IN (1, 2)` | INTEGER 미러 | K 게이트 strict-or-keep | C/G | 현행 | — |
| B10 | `? = 'a'`, `? LIKE 'a%'`, `col LIKE ?` | VARCHAR + 리터럴/컬럼 collation | K 게이트 문자화 | C | 현행 | — |
| B11 | `date_col = ?` | DATE 미러 | K 게이트 값→date(문자 파싱; 숫자 -494 현행) | C | 현행 | — |
| B13 | `enum_col = ?`, `<> ?`, `IN (?, …)` | **컬럼의 ENUM 도메인(원소 포함)** | K 게이트: 현행 ENUM 변환 표(정수→서수, 문자→이름(ENUM collation), 실수→floor, 범위 밖 -494); 비교 서수 | C | 현행 | — (D-317-12) |
| B14 | `enum_col < ?` | ENUM 도메인 | 위와 같음(서수 비교) | C | 현행; TIME 바인드 2행은 결함 → 값 A/B 로 확정 후 -494 | 결함 1건 (D-335-06·08: 바인드 캐스트는 클라이언트가 develop 처럼 하고 ENUM 은 캐스트하지 않는다(CUBRIDSUS-9007) — #336 은 ENUM 도메인 슬롯을 게이트 슬롯으로 두어 불변식만 지키고, 이 결함은 게이트 ENUM 변환기(dpin-14, 실행 측 비교 변환)에서 고친다) |
| B15 | `int_col IN (1, '2', ?)` | 원소 공통 타입(현행 컬렉션 CAST) 미러 | K 게이트 | C | 현행 | — |
| B16 | `int_col IN ?`(집합 바인드) | SET 기본 도메인(현행) | 원소는 게이트 확정 | G | 현행 | — |
| B19 | `int_col IN (SELECT ? …)` | 서브쿼리 컬럼 `?` = 게이트 확정 → 리스트 컬럼 도메인 게이트 표에 | G | 현행 | — |
| B25 | `int_col = bigint_col`, `char_col = varchar_col`, `str_col = int_col`, `bigint_col = double_col` | 컬럼×컬럼: 현행 비교 표 | C, **R·R 변환기 고정**(int→bigint / — / str→double·int→double / bigint→double) | C | 현행 | — (D-317-20: rank 판정 제거) |
| B26 | `t1.int_col < t2.dbl_col`(조인 키), 상관 서브쿼리 값 | 비교 DOUBLE | **S**: 외부 값은 range/스캔 open 시 1회, 내부 R int→double 행마다 | C | 현행 | — |
| B30 | 인덱스 키(단일 컬럼): `int_col = ?` 1.5, `int_col > 1.5` | 키 도메인 = 값 도메인(현행 strict-or-keep) | K 게이트 1회(strict 성공 시 인덱스 도메인, 실패 시 값 도메인), B+tree 원소 비교 = 계획된 **R idx_elem→double 변환기**(`btree_compare_key` 의 comparable 판정·`tp_value_compare_with_error` 폴백 제거) | C/G | 현행(실측: 인덱스/순차 스캔 답 전 셀 일치) | — (P4·P6) |
| B31 | 인덱스 키(다중 컬럼, midxkey) | 원소마다 strict-or-keep, 실패 원소만 값 도메인 | 게이트가 setdomain 을 1회 확정(현행 `need_new_setdomain`/`prebuilt_midxkey_domains` 대체), 원소 변환기 고정; 상관 키는 range open 시 S | C/G | 현행 | — |
| B32 | ISS 첫 컬럼, KEYLIMIT, MRO/top-N 정렬 도메인 | #314 G-05·L-44·L-45(e) 그대로: 인덱스 스키마에서 시딩, 오름차순 사본 | C | 현행 | — (#323 키 변환 계획) |
| B33 | auto-param 슬롯(`int_col = 3`, `int_col > 1.5`, `int_col = to_number('3')`) | 리터럴 규칙 결과 도메인(INTEGER / DOUBLE / NUMERIC floating) | K 게이트가 값을 그 도메인으로 변환 → "값 타입 = 계획 도메인" 불변식 | C | 현행(플랜 `c = ?:0` 동일) | — (D-317-08) (D-335-07·08: auto-param 은 develop 의 컴파일 꼬리 캐스트 그대로 — 값과 슬롯의 타입·collation 이 같으면 변환하지 않는다; 컬렉션 리터럴을 변환하면 develop 의 NULL 저장 답이 바뀐다, 그 결함은 #347) |
| B34 | `LIMIT ?`, `LIMIT ?, ?`, `KEYLIMIT ?`, `orderby_num() <= ?` | BIGINT(현행) | K 게이트 값→bigint(문자 파싱 허용, 날짜 -494 현행) | C | 현행 | — |

## 4. 규칙표 — 대입·공통값·집계·함수·세션변수·PL·기타

| # | 조합 | 도메인 | 확정 | 부류·변환기 | 결과 | 답안 변경 |
|---|---|---|---|---|---|---|
| U0 | `INSERT col ← ?`, `UPDATE SET col = ?`, MERGE INSERT/UPDATE — 대입 대상 도메인은 VALUES/SET 식 안의 슬롯까지 **소비자 도메인 우선**으로 닿는다(`VALUES (IFNULL(?, 0))` decimal(10,5) → decimal, D-327-11) | 컬럼의 완전한 도메인(현행) | C | K 게이트: 현행 대입 캐스트(정수 ← 1.5 **반올림 2**, 문자 파싱, 날짜 ← 숫자 -494) | 현행 | `INSERT int_col ← ?` DATE 바인드가 오류 없이 0행이던 현행은 결함 → -494 (D-317-15 정정) |
| U2 | `SELECT int_col UNION SELECT ?`, `(VALUES (1), (?))` | 알려진 가지의 공통 타입 미러 → INTEGER → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | K 게이트 값→int strict | **int**(현행 DOUBLE `1.0`) | **있음**: 표기 `1.0`→`1`, 문자·날짜 바인드 -494 (D-317-07) — **철회(D-336-A)**: 답 불변(develop) |
| U3 | `SELECT ? UNION SELECT ?`, `(VALUES (?), (?))` | 게이트 확정; NULL·NULL 은 VARCHAR NULL 도메인 (#337 구현: D-336-A 의 develop 격자대로 NULL 바인드는 NULL 타입 — 리스트 컬럼도 NULL 타입이고 답은 develop release 와 같다) | G | 게이트 표 → 리스트 컬럼 도메인 | 현행(NULL·NULL 은 assert D6 → 값) | 결함 소멸 |
| U4 | `(VALUES (timestamp'…'), (?))`, `INSERT … VALUES (dtt'…'), (?)` | 첫 알려진 행 미러 → TIMESTAMP/DATETIME → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | K 게이트 | 값(현행 **항상 -494**) | **오류 → 값**(개선, L-18) — **철회(D-336-A)**: 답 불변(develop) |
| U6 | `CASE WHEN c THEN ? ELSE ? END`, `IF(c, ?, ?)`, `DECODE(x, k, ?, ?)` | 현행 VARCHAR(둘 다 슬롯이면) — P2 로는 게이트 확정이 맞으나 **현행이 컴파일 VARCHAR** 이므로 현행 유지 | C | K 게이트 문자화 | 현행 | — |
| U7 | `CASE … THEN ? ELSE 1`, `COALESCE(?, 1)`, `IFNULL(?, 'a')`, `NVL2`, `NULLIF(?, x)`, `LEAST/GREATEST(?, x)` | 알려진 형제의 공통 타입 미러(현행 시그니처: 부류 다르면 VARCHAR). 사슬(COALESCE/LEAST/GREATEST/NULLIF/CASE 중첩)은 이진이 아니라 `recursive_type`(tc:5680)의 **사슬 전체 공통 타입**을 형제로 본다(`greatest(?, 3, 'b')` → VARCHAR, D-327-07); 소비자 도메인이 있으면 그것이 우선(D-327-11) → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | K 게이트 | `COALESCE(?, 1)` 정수 → int; 문자 `'a'` → -494(현행 VARCHAR `'a'`) | **있음** (D-317-07; `bug_3256`·`cbrd_24598` 부류) — **철회(D-336-A)**: 답 불변(develop) |
| U8 | `CASE ? WHEN ? …`, `DECODE(?, ?, …)` | 조건 슬롯끼리 → 게이트 확정(값 격자 비교) | G | 게이트 | 현행 | — |
| U10 | `COALESCE(?, ?)`, `IFNULL(?, ?)` | 게이트 확정 | G | 게이트 | 현행 | — |
| U13 | `COALESCE(CAST(? AS DATETIME), CAST(? AS DATETIME), ?)` | 형제 DATETIME 미러; 비문자 결과 도메인에 collation 플래그 금지 → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | K 게이트 | 현행 값; optdebug assert(L-19) 소멸 | 결함 소멸 — **철회(D-336-A)**: 답 불변(develop) |
| U16 | `INSERT t(c) SELECT ?`, MERGE 소스 `SELECT ? v` | 대상 컬럼 미러 → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | K 게이트 | 현행 값; 날짜 바인드 0행 → -494 | 결함 소멸 — **철회(D-336-A)**: 답 불변(develop) |
| U17 | 파생 테이블 컬럼 `?`(`SELECT * FROM (SELECT ? c) t WHERE t.c = 1`), CTE `?`, 재귀 CTE 시드 `?`, 스칼라 서브쿼리 `(SELECT ?)` | 게이트 확정 → 리스트 컬럼 도메인 게이트 표; 소비 측 비교는 상관 부류 S (#337 구현: 리스트 위치·값 포인터가 생산자 칸을 ALIAS 로 읽는다) | G | 게이트·S | 현행(`t.c = 1` 의 `CAST(t.c AS INTEGER)` 래핑 유지) | — |
| F1 | `to_char(?, '<날짜 포맷 리터럴>')` | DATETIME(포맷 추론) → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | K 게이트 값→datetime(문자 파싱) | 현행(숫자 바인드는 현행도 오류) | — (D-317-13) — **철회(D-336-A)**: 답 불변(develop) |
| F1-T | `to_char(?, '<시간 토큰만 있는 포맷>')` | TIME(포맷 추론 — 시간 토큰만이면 DATETIME 미러가 TIME 바인드를 -494 로 만든다, #319 D-319-04) → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | K 게이트 값→time | 현행 | — (D-327-05) — **철회(D-336-A)**: 답 불변(develop) |
| F1' | `to_char(?, '<숫자 포맷 리터럴>')` | NUMERIC floating(값 p/s 보존) → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | K 게이트 | 숫자 바인드 현행; 문자 `'1.0'` 바인드는 게이트가 NUMERIC 파싱 후 포맷 적용 → 현행(`'1.0'` 그대로)과 표기 다를 수 있음 | **후보** → 값 A/B 후 목록 — **철회(D-336-A)**: 답 불변(develop) |
| F2 | `to_char(?, ?)`, `to_char(col, ?)`, `to_char(?)` | 게이트 확정(값 슬롯·포맷 슬롯) | G | 게이트 | 현행; `to_char(dtt, ?)` BIGINT assert(D5) → 오류 | 결함 소멸 |
| F3 | `str_to_date(?, 'fmt')`, `str_to_date(s, ?)`, `to_date(?, 'fmt')`, `to_number(?)` | 값 슬롯 VARCHAR(현행 명시 부여), 포맷 슬롯 VARCHAR; 결과는 포맷 리터럴이면 C, 포맷 슬롯이면 G | C/G | K 게이트 문자화 | 현행 | — |
| F4 | `addtime(?, x)`, `from_tz(?, …)`, `new_time(?, …)`, `hour/minute/second(?)`, `unix_timestamp(?)`, `extract(… from ?)`, `datediff/timediff(?, …)` | 게이트 확정(값 부류로 오버로드) | G | 게이트 | 현행(`addtime(?, time)` 문자 → VARCHAR 결과, `hour('1.0')` = 0 유지) | — (D-317-13) |
| F5 | `date_add(?, INTERVAL n unit)`, `adddate(?, n)` | 현행 STRING 도메인·VARCHAR 결과 | C | K 게이트 문자화 | 현행 | — |
| F6 | `substr/upper/trim/lpad/concat/replace/translate/position/find_in_set/insert/elt/field(?)` 문자 인자 | VARCHAR(현행 CHAR generic) + collation(#322) | C | K 게이트 문자화 | 현행 | — |
| F7 | `sum(?)`, `min(?)`, `max(?)`, `count(distinct ?)`, `avg(?)`, `median(?)`, `percentile_* … order by ?`, `lead/lag/first_value/nth_value(?)`, `ntile(?)`, `group_concat(?)` | 게이트 확정 → 누산기·정렬 키 도메인을 게이트 표에(첫 값 대기 코드 삭제) (#337 구현: 첫 행 전에 계획에서 셋업한다. 첫 값 경로는 삭제 티켓까지 소스에 남지만 조건이 거짓이다 — #338 collation·#340 문자 MEDIAN 캐스케이드 몫 제외; D4 는 `ER_TP_CANT_COERCE`) | G | 게이트 | 현행(`sum(?)` TIME 누산까지) ; `group_concat(?)` NULL(D2)·`sum(?) over` 날짜(D4)·`group_concat(s + ?)`(D3) assert → 오류/값 | 결함 소멸 |
| F8 | `sum(int_col + ?)`, `sum(i) … having sum(i) > ?` | 미러(INTEGER; `having` 은 sum 결과 타입) | C | K 게이트 | 현행(INT 오버플로 오류 포함) | — |
| F9 | `sum(int_col)` | INTEGER 누산, 승격 없음(현행) | C | — | 현행 | — (승격은 후속) |
| F10 | `median(varchar_col)`, `percentile_cont … order by varchar_col` | **DOUBLE**(D-335-10, 사용자 선택 2026-09-24: 게이트가 값을 갖지 않는 문자 인자는 타입으로 — 매뉴얼 PERCENTILE_CONT/DISC "숫자로 변환되는 문자열", Oracle 숫자 변환; 옛 X "값 내용으로 DOUBLE→DATETIME→TIME" 폐기. `func_type.cpp` `pt_eval_function_type_aggregate` 문자 비상수 인자 → DOUBLE) | C | R 문자→DOUBLE ASSIGN(현행 `tp_value_cast`; 첫 비NULL 값 실패 -1118 "DOUBLE", 이후 행 현행 -181) | 숫자 문자열·'abc'(-1118)·혼합(-181) 현행; **날짜·시간 문자열 컬럼 DATETIME/TIME → -1118** | **있음** → §7 (D-335-10) |
| F11 | `GROUP BY ?`, `ORDER BY ?`, `IF(?, a, b)` | 컴파일 오류(현행 문법) | C | — | 현행 | — |
| F4' | `addtime(str_col, ?)`, `addtime(? \|\| 'x', ?)` — 왼쪽 문자가 게이트가 값을 갖지 않는 문자열(컬럼·계산식) | **VARCHAR**(D-335-10: 매뉴얼 표 4행 "날짜/시간 문자열 → VARCHAR" = 컴파일 시그니처 STRING+x → VARCHAR; arg2 MAYBE 라도 MAYBE 로 올리지 않음 `type_checking.c` `pt_apply_expressions_definition`; 게이트 의존 문자 식은 해석기가 VARCHAR). 존 문자열은 `db_add_time` 이 VARCHAR 도메인을 받아 DATETIMETZ 결과를 문자열(존 포함)로 렌더 | C/G | — | 현행(존 없는 문자열 VARCHAR); 존 문자열 컬럼은 develop optdebug `assert (domain == result_type)` → 문자열 | 결함 소멸(CTP 0건) (D-335-10) |
| F10' | `median(? + ?)`(`plus_as_concat` 문자 바인드), `median(coalesce(?, ?))` 문자 — 인자가 문자 결과를 내는 게이트 의존 식(문자 컬럼·고정 문자 식은 F10) | **DOUBLE**(D-335-10: 해석기가 값 없는 문자 피연산자를 DOUBLE 로; 실행은 게이트 노드의 값 없는 피연산자(`TYPE_DBVAL`·`TYPE_POS_VALUE`·세션변수 읽기가 아닌 것)에서 같은 DOUBLE — dpin-14 가 게이트 표를 읽을 때까지의 미러) | G | 게이트 | 숫자 내용 현행; 날짜 내용 → -1118(CTP 0건) | 셀만 → §7 (D-335-10) |
| S1 | `SELECT ?`, `SELECT typeof(?)` | 게이트 확정 | G | 게이트 | 현행(바인드 타입 그대로) | — |
| S2 | `SELECT ? FROM t WHERE 1 = 0`, `LIMIT 0` 컬럼 메타 | 게이트가 안 돌면 미확정(현행) | — | — | 현행 | — (후속 티켓, D-317-15) |
| S3 | `@v := ?`, `@v := x` | 값 저장(현행; 날짜는 문자열로 저장되는 현행 유지) | — | — | 현행 | — |
| S4 | `@v` 읽기 — 형제 있음(`@v + 1`, `c_int = @v`, `to_char(@v, fmt)`) | 형제 미러(슬롯 취급, L-32); 값은 휘발(행마다 읽음, `@v := @v + 1` 현행 의미 유지) — **실행 중 저장 타입이 바뀌면** 미러 도메인으로의 변환 실패 정책(X1) 적용 — **판정 완료(D-325-12)**: 값 A/B 는 `domain-pin-converters.md` §5, 변환이 실패하는 행은 오류/NULL(P-S2 조용한 오답 4 → -494/NULL, P-S5 비교 (2,0) → -494 — 휘발 값은 KEEP 불가 D-325-10, P-S10 `yes` 오버플로 오류 → NULL) → §7 → **게이트 확정(값 도메인, develop 격자) — D-336-B(2026-09-24)** | G | K 게이트 값→미러 도메인(문자 파싱; 실패 -494) | `@v := '1.0'; @v + 1` → **INTEGER 2**(현행 DOUBLE 2.0); `to_char(@v, 날짜 포맷)` 은 비날짜 문자열 통과 → 오류, 저장 문자열 재포맷('01/02/2024' → '2024-01-02') | **있음**(표기·to_char) (D-317-05·D-327-05) — **철회(D-336-A)**: 답 불변(develop) |
| S5 | `@v` 읽기 — 형제 없음(`SELECT @v`, `sum(@v)`) | 게이트 확정(초기 저장값 타입); 값은 휘발 — 실행 중 저장 타입이 바뀌면 게이트 도메인으로 변환(실패 정책 X1; 타입이 바뀐 행에서만 표 재조회 D-325-10) — **판정 완료(D-325-12)**: P-S1·S6·S9 불변, P-S8 `sum(@v)` 은 `yes` 모드에서 오류 → 값(`domain-pin-converters.md` §5) | G | 게이트 | 현행 | **있음**(`yes` 모드 P-S8) |
| S6 | PL/CSQL 정적 SQL 의 `?` | **선언 타입** = 알려진 형제(PG param_types); NULL 은 typed NULL | C | K 게이트 | 현행 값(이전 캠페인 33건 결함 해소) | — (D-317-06) |
| S7 | 세션변수·PL 인자·auto-param 을 "슬롯" 정의에 포함 | — | — | — | — | 게이트가 다루는 슬롯 = 사용자 `?` + auto-param + 세션변수 읽기 + PL 인자 |
| X1 | 게이트 변환 **실패 정책**(`return_null_on_function_errors`) | 문맥별 현행: 산술·함수 인자(A·F·U7 등 현행이 `tp_value_auto_cast` 를 타던 자리)는 파라미터를 따름(yes → 슬롯 값 NULL, 오류 없음); 대입(U0)은 항상 -494(현행 바인드 시점 캐스트 `pt_set_host_variables` 는 파라미터를 안 본다); 비교(B)는 strict-or-keep 이라 오류 없음(휘발 값만 KEEP 불가 → -494, D-325-10); **리스트 컬럼**(`SELECT ?`·`SELECT @v` 결과 컬럼)은 산술·함수 인자와 같이 파라미터를 따름(D-325-11, 실측 P-S1: default -494 / `yes` NULL) | G/C | 계획 항목의 실패 정책 열(-494 / NULL / keep, D-325-07: leaf 는 상태만 반환, 정책은 호출자). 한 `?` 의 다중 참조는 참조별 계획 슬롯에만 NULL, 공유 `vd.dbval_ptr[]` 원 값 불변(#323) | 현행(CTP C5 `s1 / ?` cfg_null_on_errors NULL 유지) | — (D-327-10) — **삭제(D-336-B)**: 컴파일 미러가 없으므로 미러 실패 정책도 없다; 대입(U0) 캐스트 실패는 develop 그대로 |

## 5. 이 PR 에서 고치는 결함(P0 의 예외)과 후속으로 보내는 것

**고친다(크래시·assert·조용한 0행)**: 실측 §1 D2·D3·D4·D5·D6·D7, L-19(§6 C15), `INSERT int_col ← ?` DATE 0행, `char(n)_col = ?` VARCHAR 값 NULL(CHAR 미러 유지, 게이트 CHAR 변환에서 — D-327-01), `enum_col < ?` TIME 2행(값 A/B 뒤). 새 경로가 대체하는 자리에서 자연히 사라지거나, 게이트 CTP 에서 드러나면 이 PR 안에서 수정.
**후속으로 뺀 결함(D-322-04)**: D1 `coalesce/nullif/case(enum_col, ?)` — optdebug 는 prepare 시 csql assert, release 는 정상 오류 -494 라 크래시 기준에 걸리지 않고 파서 래핑 타입 선택을 바꾸는 별건. 방향(리터럴 경로와 같게: VARCHAR + ENUM collation)만 확정, 작업은 xmilex-git/workspace#326.
**후속 티켓(현행이 이상하지만 규칙과 무관)**: 미실행 문장 메타(L-24), `str_col = 1` vs `= 1.00` 인덱스 갈림, UNION NUMERIC (38,15), `int_col = 1.5` 0행 vs `< 1.5`, `SET @v = date` 문자열 저장, SUM(int) 승격, `extract(… from time)` 쓰레기 값, `hour('1.0')` = 0.

## 6. collation 축 (짝 티켓 #322, D-322-01~04)

**원칙**: 도메인 축과 collation 축은 코드가 다르지만(L-14) **확정 지점은 같다** — 컴파일 또는 게이트, 게이트 뒤 결정 0. 문자 형제(컬럼·리터럴·CAST·ENUM 컬럼)가 있으면 컴파일이 형제 collation 으로 ENFORCE(현행 `pt_coerce_node_collation`), 형제가 전부 슬롯이면 **게이트 확정**(D-322-01): 게이트가 바인드 값들의 collation 에 현행 실행 병합 규칙 `LANG_RT_COMMON_COLL`(같으면 그것 / 한쪽 coercible 이면 다른 쪽 / 둘 다 coercible 이면 ISO 바이너리 / 둘 다 비-coercible 이면 -1150 / codeset 변환 불가 -622)을 실행당 1회 적용해 슬롯·연산자 결과·리스트 컬럼·누산기 collation 을 게이트 표에 넣는다. coercibility 8-레벨(#313 §3.1)·컴파일 병합 `pt_common_collation`·실행 병합 규칙 자체는 **변경 없음** — 실행 병합의 위치만 행 평가 → 게이트. `TP_DOMAIN_COLL_LEAVE` 는 XASL 에서 사라진다(계획 도메인의 collation_flag 는 항상 NORMAL 이거나 게이트 슬롯 참조) → #314 §4 의 쌍 조건 26곳은 타입 축과 함께 삭제(G-04 충족). 슬롯의 기본 collation 이 `LANG_SYS`(로케일 바이너리)이지 클라이언트 collation 이 아니라는 현행(#313 §3.5)은 게이트 확정 아래에서 "바인드 값이 가져오는 collation(CAS 가 세션 collation 으로 만듦)" 으로 대체되며 관찰 가능한 답은 같다(실측 A2 `COLL.hv_after_set_names`, 프로브 C1·C3·C5).

| # | 조합 | collation | 확정 | 근거·현행 | 답안 변경 |
|---|---|---|---|---|---|
| C1 | `col(A) = ?`, `col LIKE ?`, `col IN (?, ?)`, `col BETWEEN ? AND ?`, `INSERT col ← ?`, `substr(col, ?)`·`replace(col, ?, ?)` 등 문자 컬럼 형제 | 슬롯 VARCHAR + **A ENFORCE**(D-317-04 와 한 결정) | C | K2·K10·B6·B7·B20 | — |
| C2 | `'x' = ?`, `? IN ('a', 'b')`, `? LIKE 'a%'`, `concat(?, 'a')` 리터럴 형제 | 리터럴 collation(prepare 시점 클라이언트 collation) ENFORCE | C | K3·K11·B10; 프로브 C2·C4: prepare 뒤 `SET NAMES` 해도 리터럴·미러 슬롯 고정 | — |
| C3 | `? = ?`, `? LIKE ?`, `concat(?, ?)`, `? + ?`(plus_as_concat), `? \|\| ?`, `upper/trim/lpad(?)`, `to_char(?)`, `greatest/least(?, ?)`, `nullif(?, ?)`, `case when ? = ? then ? else ? end`, `decode(?, ?, ?)`, `insert/replace/translate/substring_index/find_in_set/position(?, ?)` — 형제 전부 슬롯 | **게이트 확정**: 값 collation 병합, 실패 -1150/-622 | G | K4·K5·B21·F9·F10; 실측 A2 `COLL.*`; `issue_12129_HV_collation` 21건의 현행 답(값 collation 표기·혼합 charset -1150) 유지 | 없음 — -1150/-622 시점만 행 평가 → 게이트(P7 ②) |
| C4 | 중첩 식 `s1 LIKE ? + ?`, `rtrim(? + ?, ?)`, `find_in_set(s1, ? + ?)`, `position(s1 in ? + ?)` | 안쪽 `? + ?` 는 C3(게이트) → 바깥 형제 collation 으로 **계획된 CAST**(현행 `CAST(expr AS VARCHAR COLLATE c)` 래핑 자리). 하향 전파 없음 | G+C | D-322-02; `_03_plus`·`_12_like`·`_14_find_in_set` 의 `_euckr + _utf8` -1150 유지 | 없음 |
| C5 | `COALESCE(?, col(A))`, `IFNULL(?, col)`, `CASE … THEN ? ELSE col(A)`, `NULLIF(?, col)`, `GREATEST(?, col)` | 슬롯 A ENFORCE, 결과 A(현행 `is_wrapped_res_for_coll` 래핑) | C | K8·K9; 실측 A2 `COLL.coalesce_hv_col`·`case_hv_col` = `utf8_en_cs` | — |
| C6 | `COALESCE(enum_col, ?)`, `NULLIF(enum_col, ?)`, `CASE … ELSE ?`(ENUM 형제) | **후속 #326** — 방향: 리터럴 경로(`coalesce(e, 'x')` = VARCHAR + ENUM collation, 프로브 A1)와 같게 슬롯 VARCHAR + ENUM collation ENFORCE. 이 PR 은 현행(release -494; optdebug prepare assert D1) 유지 | C(후속) | D-322-04; 프로브 A1·A2 | 후속(오류 → 값, 결함 소멸) |
| C7 | `enum_col + ?` 문자 바인드(A13 게이트 확정 → 이름 접합) | 결과 VARCHAR + **ENUM 컬럼 collation**(컴파일에 알려짐) | G(타입)/C(collation) | 프로브 A1 `e + 'x'` = `utf8_en_ci`; #321 §2.1 ENUM→문자 = 이름 + ENUM collation | — |
| C8 | 리스트 컬럼 — `SELECT ? UNION SELECT 'a'`(문자 가지 있음) / `SELECT ? UNION SELECT ?`, 파생 테이블·CTE·스칼라 서브쿼리 `?` | 문자 가지 collation 미러(C) / 게이트 표(G) | C/G | K14·U3·U17; `qfile_unify_types` 의 collation 플래그 -1509 분기 삭제 | — |
| C9 | 다중 행 VALUES `(values (?), (?))`, `INSERT … VALUES (?), (?)` | 게이트가 열마다 1회 병합(현행 "첫 행과 비교" S-06 대체), 실패 -1150 | G | G-08(2); 프로브 E2 `_utf8`+`_euckr` = "Context requires compatible collations" | 없음(시점만) |
| C10 | 집계·분석 `group_concat(?)`, `min/max(?)`, `count(distinct ?)`, `lead/lag/first_value(?)`, `percentile_* … order by ?` | 누산기·distinct/정렬 리스트 collation 을 게이트 표에서; 바인드 전부 NULL 이면 결과 NULL(collation NULL) | G | F7; 프로브 B1·B2 release `NULL`/`'a' utf8_bin`. D2(optdebug 서버 assert qx:1375 = 누산 도메인 LEAVE 플래그)는 LEAVE 소멸로 자연 해소 | 결함 소멸(D2 서버 크래시 → NULL) |
| C11 | `group_concat(col + ?)`, `group_concat(s1)`, `min(col)` 컬럼 형제 | 컬럼 collation | C | `_04_group_concat`(`i1 + ?` 는 타입 축 A5 INTEGER 미러 → 문자 바인드 -494 는 타입 축 답안 변경) | — |
| C12 | 세션변수 `@v` 읽기(`SET @v = 'x' COLLATE c` 저장 collation 포함) | 형제 있으면 ENFORCE(게이트가 값 codeset 변환), 없으면 게이트 확정(저장 값 collation) | C/G | S4·S5·L-32; `_07_session_var`·`_12_like` 세션변수 블록 현행 유지 | 없음 |
| C13 | PL/CSQL 정적 SQL 의 `?`(PL 이 만든 값) | 문자 형제 있으면 ENFORCE, 없으면 게이트 확정 | C/G | S6·L-32 — 탐침(#319)에서 PL 값 collation 확인 | — |
| C14 | 보간 정렬 키 `percentile_cont … ORDER BY varchar_col`, `median(varchar_col)` | 정렬 키 collation = 컬럼 collation(컴파일). 타입은 F10 DOUBLE(D-335-10; 분석 정렬 키 `cmp_dom` 도 컴파일 도메인) | C | K13·L-21 | — |
| C15 | 비문자 결과 도메인 — `COALESCE(CAST(? AS DATETIME), CAST(? AS DATETIME), ?)`, 산술·날짜 함수 결과, 비문자 게이트 슬롯 | **collation 0 + NORMAL, 플래그 없음**(게이트 표의 비문자 항목에 collation 칸 없음). `pt_upd_domain_info` 가 인자 플래그를 비문자 결과로 옮기는 경로는 이 PR 결함 수정 | C | K15·U13·L-19 | 결함 소멸(optdebug assert → 값) |
| C16 | 인덱스 키 `varchar_col(A) = ?`, `LIKE ?` | 슬롯 A ENFORCE 이므로 키 collation = 인덱스 collation(strict 성공). 명시 `COLLATE` 로 다른 collation 을 바인드하면 현행 strict 실패 → 값 collation 키 + 공통 collation 비교(B30 계획된 변환기) | C/G | B30·#321 §4.2 | — |
| C17 | `COLLATE` 수식어 `? = ? COLLATE c`, `col COLLATE c = ?` | 수식어 collation 강제(codeset 다르면 컴파일 오류) | C | #313 §3.3-3 | — |
| C18 | 재컴파일 트리거 | `SET NAMES … COLLATE` 는 prepared 문 무효화 없음(리터럴·ENFORCE 슬롯은 prepare 고정, 게이트 슬롯은 값 따라 세션 반영); `ALTER … COLLATE` 는 xcache 무효화로 재컴파일. 새 트리거·캐시 키 변경 없음 | — | D-322-03; 프로브 C1~C5·D1·D2 | 없음 |

**귀결(아키텍처 #318·인터페이스 #323·변환기 #325 입력)**: (1) 게이트 표 항목 = 슬롯 ID → (도메인, collation) 한 쌍 — collation 축을 별도 표로 두지 않는다. (2) 삭제 목록에 #314 §4 26곳(연산자 결과 2·REGUVAL_LIST 1·리스트 컬럼 11·집계 9·빠른 경로 차단 3)을 추가하고, `qfile_unify_types`·`qexec_end_one_iteration` 의 collation 플래그 분기도 함께. (3) 오류 코드 불변(-1150·-622·-1509), 시점만 게이트. (4) 후속(Out of scope): 플랜 캐시 키 텍스트가 LANG_SYS 와 같은 리터럴 collation 을 생략 인쇄해 다른 세션 collation 의 같은 문장이 같은 캐시 항목을 쓰는 문제(#313 §3.6, 리터럴 축) · D1 ENUM 형제 #326.

## 7. 답안 변경 목록 — **전면 철회(D-336-A, 2026-09-24)**; 아래 표는 이력(원제: 확정 — 탐침 #319 CTP sql 111건·셀 §3 을 개정 규칙으로 재분류, D-327-02·09)

**철회 기록**: #336 의 게이트 런(`sql-20260923T185234Z-2646995`, NOK 111 → 110)이 이 표의 행을 케이스별 SQL 로 실측·보고한 뒤 사용자가 답안 변경 전부를 기각했다(D-336-A; `docs/research/domain-pin-slot-gate-design.md`). 이제 **모든 행이 불변 목표**다: TC expected 갱신은 0 건이고 게이트 CTP 는 sql 17468/17468·medium 975/975 다. 아래 표의 "변경" 열은 더 이상 적용되지 않는다. (원문: TC expected 갱신은 이 목록의 행만 대상으로 하고 구현 게이트 CTP 에서 건별로 확인한다(값 A/B, `silent` 최우선 L-06). "불변 목표" 는 답안 변경이 **아니며** 게이트 CTP 에서 diff 가 나면 회귀다.)

| 부류 | 규칙 행 | 변경 | 근거 원칙 | 탐침 CTP(#319 §4) · 예상 TC |
|---|---|---|---|---|
| 정수 형제 산술에 소수·비숫자 문자 바인드 | A5·A5'·A6·A8'·U2·S4 | 값 → -494(게이트 strict; 프로토타입의 silent 반올림 C3 은 한계, expected 는 -494 기준) | P7 ① | C3(12곳: `_07_plus`·`_08_minus`·`_04_divide/number_number`, `_12_common/agg_group_by·distinct`, `group_concat(i1 + ?)`), `bug_bts_4562`·`bug_bts_6605` 소수 블록 |
| **`? + n` 날짜 바인드**(관용구 "날짜 + n일") | A8'·A5 | 날짜 → -494; DATE 컬럼 대입 `values (? + 4)` 는 **prepare 시점** 컴파일 오류(오류 문장 위치 이동, L-23) | P7 ①② | **65곳**: C1(58 — `issue_5765_timezone_support` `date_format/time_format/to_char(? + 1, ?)` 13 로케일 × dt/ts)·C6(4 — `_07_plus/_08_minus/date_number` + cfg_null)·C14(3 — `insert_value`). 릴리스 노트: 날짜 산술은 `? + INTERVAL`/명시 CAST (D-327-09) |
| **넓은 바인드 축소** | A5·A8'·S4·U2 | BIGINT 2^53+·DOUBLE 1.79E308 → 오버플로(-730/-458)·-494; `@v := bigint; @v + 1` INT 오버플로; `sum(i + ?)` INT 오버플로(리터럴 `sum(i + 1)` 과 같음); `limit 0 + ?` 조용한 0행 → -494 | P7 ①③ | C4(4 — `_06_times`·`_07_plus/number_number`, `host_variables_bingding_002`, `_12_common/union`)·C13(`20567_limit_1`) (D-327-02) |
| 숫자 형제 산술 표기 | A5·A5'·A8'·U2·S4·A12 | `x.0` → `x`, DOUBLE/NUMERIC 값 타입 → 형제 타입 | P7 ① | C2(23 — `_15_host_variable/_04~_08`, `_12_common/*`, `_07_misc/_02_prameter_bind`, `bug_bts_4565`·`8743`·`12326`, `cbrd_20968`, CTE `x + ?`) |
| 문자 컬럼 `×÷%` 슬롯 | A3' | 오류 코드 -181 → -494; 날짜·bit·set 바인드 NULL → -494, monetary → double 표기 | P7 ①② | C5 오류 코드 3곳(`_04_divide·_05_modulus·_06_times/string_string`); **`*_cfg_null_on_errors` 3곳은 NULL 유지 = 불변 목표**(D-327-03·10) |
| ENUM `×÷%` 슬롯 | A13' | #319 §3.2 diff: NULL → 값, double → smallint 표기 | P7 ① | 셀만(CTP 없음) (D-327-04) |
| 공통값 미러 | U2·U4·U7 | `1.0` → `1`, 부류 다른 바인드 -494(`ifnull(?, 1)` 날짜 C7), 다중 행 VALUES/UNION 오류 → 값(C9, 값 A/B 완료 §4.1), `1 + ?` BIT NULL → -494(C8), `nvl(i, ?) between …` INT 미러 → B25 격자 파급 -181/-494(C15) | P7 ①③ | `bug_3256`·`cbrd_24598`·`bug_bts_4565`·`_07_multi_values_clause/01_values·06_types`·`bug_bts_13523`·`cbrd_20769_exp` |
| 세션변수 형제 미러 | S4 | `@v + 1` 표기 `2.0` → `2`; `to_char(@v, 날짜 포맷)` 비날짜 문자열 통과 → 오류, 저장 문자열 재포맷 | P7 ① | `_07_session_var` 일부 블록 (D-327-05) |
| **세션변수 실행 중 타입 변경** | S4·S5 | P-S2 `(@v := @v + 1), (@v := '2.5')` 조용한 오답(4) → -494/NULL; P-S5 `i = @v, (@v := '1.5')` (2,0) → -494; `return_null_on_function_errors=yes` 에서 P-S8 `sum(@v)` 오류 → 값, P-S10 `@v + 1` 오버플로 오류 → NULL | P7 ①③ | 셀만(`domain-pin-converters.md` §5 A/B, CTP 없음) (D-325-10~12) |
| `to_char(?, 시간 포맷)` | F1-T | TIME 바인드 유지(DATETIME 미러였다면 -494 였을 자리 — 변경 없음, 행만 신설) | — | — (D-327-05) |
| U13 결과 타입 | U13 | `coalesce(cast(? as datetime), cast(? as datetime), ?)` 문자 바인드 결과 VARCHAR → DATETIME | P7 ① | 셀 U13 (D-327-06) |
| `to_char(?, 숫자 포맷)` 문자 바인드 | F1' | 후보 | 값 A/B | — |
| 결함 소멸 | §5 | assert/0행 → 오류 또는 값 | P7 ③ | — |
| 오류 코드·트레이스 | — | 게이트 시점 오류는 -494 계열 유지; `?:0` 플랜 텍스트 유지 | P7 ② | `cbrd_25374`·`cbrd_24906_2` 부류는 텍스트 불변 목표 |
| **타입 조합 거부 오류 시점**(D-335-02) | A 행 G(게이트 의존 노드) | 슬롯 값 타입 조합을 연산자가 받지 못하고 develop 이 계산 때 오류(-454 `ER_QPROC_INVALID_DATATYPE`)를 내던 경우 → 게이트가 실행 전에 같은 오류: **0행·선택 안 된 CASE 분기에서도 오류**(develop 은 계산하지 않으면 무오류). develop 이 오류 없이 NULL 을 내던 조합(`DATETIME − TIME` 등)은 NULL 유지. 같은 규칙으로 `+` 의 문자·비트 첫 피연산자가 `db_string_concatenate` 에서 받는 거부(-621·-622)와 `%`·부호·ABS/CEIL/FLOOR 의 거부(-454)도 게이트에서(#335). 함수(F 행)·집계의 오류는 시점 불변 | P7 ② | develop 실측 `? + ?` DATE+DATE: 1행 -454 · 0행 무오류 · 미선택 CASE 0; `DATETIME − TIME` NULL(#335 develop-probe) |
| collation 충돌 시점 | C3·C4·C9 | -1150/-622 가 행 평가 → 게이트(코드 불변, 값 없음) | P7 ② | `issue_12129_HV_collation` 21건은 답 불변 목표(이전 캠페인 19건 diff 는 회귀로 분류) |
| collation 결함 소멸 | C10·C15 | D2 서버 assert → NULL, L-19 assert → 값 | P7 ③ | — |
| **문자 컬럼·식의 MEDIAN/PERCENTILE 정적 DOUBLE**(D-335-10) | F10·F10'·F4' | 날짜·시간 문자열을 담은 문자 컬럼의 MEDIAN/PERCENTILE_CONT/PERCENTILE_DISC(집계·분석): DATETIME/TIME 값 → -1118(첫 비NULL 값; 이후 행 -181 은 현행). 숫자 문자열·'abc'(-1118)·혼합(-181) 불변. ADDTIME 문자 컬럼은 0건 — 존 문자열 컬럼은 develop optdebug assert 자리 → VARCHAR 문자열(결함 소멸). 리터럴·바인드·세션변수 인자는 값 분류 그대로(불변) | P7 ①③ | CTP sql 10건(게이트 `sql-20260923T154508Z-2465048` 실측, 전부 이 부류): `issue_11087_median/11087·11087_1·11087_3·11743`(`median(c12)`·`median(c)` 날짜 문자열 컬럼), `_14_1h/bug_bts_13916`(뒷부분 `median(c12)`), `issue_11088_percentile_cont/_01_aggregate_function/_00_from_dev·_08_expression`, `issue_11089_percentile_disc/_01_aggregate_function/_00_from_dev·_08_expression`(`order by c12`, `order by to_char(col4, 'HH24:MI:SS.FF DD/MM/YYYY')` 날짜 문자열 **식**), `_07_misc/domain_conversion_contract/conversion_contract` R5 (D-335-10, [결정](https://github.com/xmilex-git/workspace/issues/335#issuecomment-5797393992)) |

**불변 목표(탐침 diff 였지만 개정 규칙에서는 답이 그대로여야 하는 것)**: C10 세션변수 재작성 텍스트(계획된 변환기는 텍스트를 바꾸지 않는다, L-50) · C11 `INSERT decimal VALUES (IFNULL(?, 0))` 12.34568 유지(소비자 도메인 우선, D-327-11) · C12 재귀 CTE `median(m) over()` double 유지(UNION/VALUES 미러는 호스트 변수 가지만, #319 F-6) · C5 `*_cfg_null_on_errors` NULL 유지(X1, D-327-10) · B7 `char_col = ?` 1행(D-327-01) · 중첩 게이트 식 `abs(?) + 1` 등 현행 값(A8'', D-327-08).

## 8. 렛저 대응표

| L | 이 표에서 |
|---|---|
| L-10 | B13·B14·A13, P2 |
| L-11 | A2·A5'·A12·F1'(NUMERIC floating, 값 p/s 보존) |
| L-12 | A5·A6·A7·D-317-10(산술 strict, `/` 절삭) |
| L-13 | A8(게이트 확정, 접합 유지 — 매뉴얼 변경 없음) |
| L-14 | §6 원칙·C1~C5(도메인 축과 확정 지점 공유, 하향 전파 없음 D-322-02) |
| L-15 | S3·S4·S5·§7 실행 중 타입 변경(D-325-10~12) |
| L-32 | S7·§6 C12·C13 |
| L-16 | S6 |
| L-17 | F1·F1'·F2·F4 |
| L-18 | U4·U3 |
| L-19 | U13·§6 C15 |
| L-20 | B34 |
| L-21 | F7·F10 |
| L-22 | B33 |
| L-23 | §7 |
| L-24 | S2(후속) |
| L-25 | §6 C2·C18(D-322-03; 캐시 키 리터럴 문제는 후속) |
| L-42·L-46 | P5 |
| L-45 | B30·B31·B32 |
| L-47 | §6 원칙(LEAVE 폐기)·C3·C8·C10, 귀결 (2) |
| L-49 | B33 불변식 |
| L-51 | P6 삭제 목록 |
| L-50 | S4·§7 불변 목표 C10(계획된 변환기는 재작성 텍스트를 바꾸지 않음) |
| L-06 | §7 불변 목표(탐침 silent 4종 C3·C10·C11·C12 전부 원인 특정·규칙 반영) |
