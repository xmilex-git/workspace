# 묵시적 형변환 AS-IS 전수 실측 — 규칙표(#317) 결정의 근거

지도: xmilex-git/workspace#312 · 티켓: #317 · 작성 2026-09-22 · 기준: CUBRID/cubrid `develop` `cad27172b` **optdebug**(`.git_ignored_dir/scratch/dpin/install-optdebug`), `csql -S`(standalone) 실측.
입력: #313(파서 규칙)·#321(서버 규칙)·#315(PG/MySQL) 문서, 렛저 `domain-pin-lessons.md`, 이전 캠페인 CTP 실패 diff 100건.
부록(자동 생성 전수표): `domain-pin-asis-matrix/A1-type-pairs.md`(17×17 타입 쌍 × 상황 × 경로), `A2-trouble-classes.md`(집계·분석·함수·다중 행·세션변수), `A3-autoparam-index-key.md`(순수 리터럴 auto-param vs 호스트 변수 인덱스 키), `A4-prev-campaign-ctp-diffs.md`(이전 캠페인 실패 100건 diff).
탐침 스크립트·원본 출력: `.git_ignored_dir/scratch/dpin-317/probe/`(gen.py·gen2.py·gen3.py·run_resumable.py·parse.py·matrix*.py, `*.out/*.err/*.crashes`).

이 문서가 답하는 것: (1) 지금 CUBRID 가 타입 조합·상황·경로별로 **어떻게 변환하는가**(AS-IS 표), (2) 후보 원칙(형제 미러 → 문맥 없으면 DOUBLE/VARCHAR)을 적용하면 셀이 **어떻게 바뀌는가**, (3) **이전에 되던 질의 중 무엇이 깨지는가**(이전 캠페인 CTP diff 로 실증). 결정은 §5 의 질문으로 사용자가 한다.

---

## 0. 한 장 요약

측정 규모: 타입 17종(null·string·char·short·int·bigint·numeric·float·double·monetary·date·time·timestamp·datetime·bit·enum·set) × 상황 6종(산술 6연산·비교·인덱스 키 비교·대입·공통값·슬롯 문맥 40여 종) × 경로 5종(컬럼×컬럼 / 컬럼×리터럴 / 컬럼×`?` / `?`×`?` / 리터럴×리터럴) = 라벨 17,267개. 그중 optdebug assert 로 건너뛴 라벨 37개(§1).

핵심 발견 10가지:

1. **비교의 "형제 미러" 는 새 규칙이 아니라 현행이다.** `col = ?` 는 이미 컬럼 타입으로 슬롯을 확정하고 CAS 가 값을 캐스트한다. 그래서 `varchar_col = ?` 에 정수 1 을 바인드하면 문자 비교(`'1' ≠ '1.0'`, 거짓)인데, 같은 조합의 컬럼×컬럼·`?`×`?`·numeric 리터럴은 DOUBLE 비교(참)다(§3.3).
2. **늦은 바인딩이 남아 있는 곳은 산술·함수 인자·공통값·집계 자리다.** 이 자리의 `?` 는 값 타입으로 결정되며 결과는 컬럼×컬럼 격자와 같다(값이 그 타입이면). 즉 "형제 미러" 를 산술까지 확장하면 `int_col + ?`(1.1 바인드) 가 현행 NUMERIC 2.1 → INTEGER 로 바뀐다(§3.2·§4 Q1).
3. **리터럴 종류에 따라 규칙이 다르다.** `str_col = 1`(정수 리터럴) 은 리터럴을 VARCHAR 로 캐스트해 문자 비교(거짓, 인덱스 사용), `str_col = 1.00 / 1.0e0 / 1.0f` 는 양쪽을 DOUBLE 로 캐스트해 수치 비교(참, **인덱스 포기 → 순차 스캔**). 호스트 변수는 어느 타입이든 컬럼 미러(거짓, 인덱스 사용)(§3.4).
4. **auto-param 과 호스트 변수는 인덱스 키 경로에서 같은 모양(`c = ?:0`)이지만 슬롯 도메인이 다르다**: auto-param 은 리터럴 규칙을 거친 뒤의 값 도메인, 호스트 변수는 컬럼 미러 도메인. 캐스트가 붙은 리터럴(`cast(1.00 as numeric)`, 함수 결과)은 auto-param 대상이 아니라 식으로 남는다. 인덱스 스캔과 순차 스캔의 답이 갈리는 셀은 **없었다**(§3.4).
5. **정수 컬럼 미러 캐스트는 손실 시 반올림하지 않는다(비교)**: `int_col = ?` 에 1.5 → 0행(2 가 아님), `<` 1.5 → 1행. 반면 **대입은 반올림**: `INSERT int_col ← 1.5` → 2 (리터럴·호스트 변수 동일)(§3.5).
6. **값 타입에 따라 오류/NULL/값이 갈리는 현행 사례**: `int_col + ?` 에 BIT·SET·시간 바인드 → 오류 아닌 **NULL**(컬럼×컬럼은 오류); `INSERT int_col ← ?`(DATE 바인드) → csql SA 에서 오류 없이 **0행**(리터럴은 컴파일 오류) — **정정(#358)**: 실제는 -494(`Cannot coerce host var to type integer`, csql·JDBC). 이 탐침 파서가 EXECUTE 의 stderr 오류를 라벨에 붙이지 못했다; `coalesce(?, 1)` 은 바인드 부류가 다르면 결과가 VARCHAR 로 바뀜(§3.6).
7. **집계·분석 슬롯은 전부 첫 값 타입**: `sum(?)`·`min(?)`·`max(?) over()`·`lead(?)`·`median(?)` 결과 타입 = 바인드 타입; `sum(?)` 에 DATE → 오류, TIME → TIME 누산(10:00:01 그대로)(§3.7). GROUP BY `?`·ORDER BY `?` 는 문법 오류(컴파일 거부, 자유 문맥 아님).
8. **세션변수는 쓰기 타입을 기억하고 읽기는 값 타입으로 산술한다**: `@v := 1` 뒤 `@v + 1` = INTEGER 2, `@v := '1.0'` 뒤 = DOUBLE 2.0, `@v := date` 뒤 `@v + 1` → 오류(`'01/02/2024'` 문자열로 저장됨 — `SET @v = date'…'` 가 **VARCHAR 로 저장**)(§3.9).
9. **`str_to_date(s, ?)`·`to_char(?, fmt)`·`addtime(?,?)`·`from_tz(?,…)` 는 값 부류로 오버로드가 정해진다**: `to_char(?, 'YYYY-MM-DD')` 는 문자·날짜 바인드만 성공, 숫자 바인드 → "Invalid format"; `to_char(?, '9,999.99')` 는 반대. `from_tz(?, …)` 는 DATETIME 바인드만 성공(§3.8).
10. **develop 자체 optdebug assert 12종**(37 라벨)이 슬롯·NULL·문자열 결과 도메인에서 나온다 — 규칙표와 무관하게 별건 결함(§1). PL/CSQL 은 SA 모드에서 실행 불가라 이전 캠페인 증거(#296·#301·#310)만 인용한다.

---

## 1. develop 결함 후보 (optdebug assert, 규칙표 이전에 별건)

| # | 재현(라벨) | assert | 비고 |
|---|---|---|---|
| D1 | `coalesce(enum_col, ?)` 바인드 타입 무관(16종 전부) | `type_checking.c:22826 pt_check_expr_collation: PT_HAS_COLLATION(expr_wrap_type)` | ENUM 형제 + MAYBE 슬롯의 결과 collation 래핑 |
| D2 | `group_concat(?)` NULL 바인드 | `query_executor.c:1375 qexec_end_one_iteration: TP_DOMAIN_COLLATION_FLAG(agg_node->domain) == NORMAL` | L-47 LEAVE 플래그가 누산 도메인에 남음 |
| D3 | `group_concat(s + ? order by 1)` 문자·숫자·날짜 바인드(9종) | `object_primitive.c:10996 mr_readval_string_internal: false` | 리스트 컬럼 도메인 ≠ 기록 값 타입(L-22·#321 §3.3) |
| D4 | `sum(?) over (partition by g)` 문자날짜·DATE·DATETIME·TIME 바인드 | `query_executor.c:23654 qexec_analytic_add_tuple: er_errid() != NO_ERROR` | 분석 누산 오류가 오류 코드 없이 실패(L-43) |
| D5 | `to_char(dtt_col, ?)` BIGINT 바인드 | `string_opfunc.c:25792 db_check_or_create_null_term_string: QSTR_IS_ANY_CHAR` | 포맷 슬롯이 문자 아닌 값을 받음(L-17). #358: release 는 csql·cub_server SIGSEGV, dpin 도 같다 → [#363](https://github.com/xmilex-git/workspace/issues/363) |
| D6 | `select ? union all select ?` NULL·NULL, 재귀 CTE 시드 `?` NULL | `list_file.c:913 qfile_unify_types: list_id1_p->tuple_cnt == 0` | 양쪽 VARIABLE 리스트 통일(L-18·L-48) |
| D7 | `enum_col IN (NULL, NULL)` | `dbtype_function.i:678 db_get_enum_short: type == DB_TYPE_ENUMERATION` | ENUM 비교에 NULL 상수(L-10) |

전부 release 에서는 assert 가 빠져 조용한 오답·오류로 이어질 수 있다(L-03). 코어 33개: `install-optdebug/log/coredump/`.

---

## 2. 방법

- 표 `tt`(1행: 모든 타입 컬럼, 값은 "1 계열" — 숫자 1, 문자 `'1.0'`, date 2024-01-02, time 10:00:01, ts/dtt 2024-01-02 10:00:01, bit B'1', enum `'1.0'`(서수 1), set {1,2}), `tk`(3행, 컬럼별 인덱스 + `(c_int, c_string)` 복합 인덱스), `tn`(`tk` 와 같은 데이터, 인덱스 없음), `ta`(대입용), `tg`(그룹 5행), `tv`, `tc`(collation).
- 경로: 컬럼×컬럼(`c_a op c_b`), 컬럼×리터럴(캐스트 식 리터럴), 컬럼×`?`(`PREPARE … EXECUTE USING :h_b`; `:h_b` 는 `SELECT CAST(...) INTO :h_b` 로 만든 타입 값), `?`×`?`, 리터럴×리터럴(상수 폴딩). 인덱스 키는 `SET OPTIMIZATION LEVEL 513` 으로 재작성 질의·스캔 종류를 함께 기록.
- 비교 셀은 `= / <` 진리값. 값이 "변환되면 같고 문자로는 다른" 쌍(`1` vs `'1.0'`, date vs datetime 00:00 등)을 골라 **어느 쪽으로 변환됐는지** 진리값으로 읽는다.
- 한계: SQL-level `PREPARE/EXECUTE`(csql) 경로 = CAS 경로와 같은 `pt_set_host_variables` 캐스트를 탄다(#313 §2.4). JDBC 메타데이터·PL/CSQL·collation `SET NAMES` 후 재컴파일은 미측정.
- 한계(#358 정정): 파서(`parse.py`)가 EXECUTE 의 stderr 오류를 그 라벨에 붙이지 못한 곳이 있다 — T28·T29 의 "오류 없이 0행" 은 실제로 -494·-181 이었다. 이 표의 `∅`·"오류 없이" 셀은 재현으로 확인하고 쓴다.

---

## 3. AS-IS 매트릭스 (요약판 — 전수는 부록 A1~A3)

표기: 셀 = 결과 타입(=값) / `ERR` / `NULL`. 행 = a(왼쪽), 열 = b(오른쪽).

### 3.1 산술 — 컬럼 op 컬럼 (컴파일 격자 = 사용자 AS-IS 표의 확장)

`+`:

| a \ b | string | short | int | bigint | numeric | float | double | monetary | date/time/ts/dtt | bit | enum | set |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **string** | varchar(접합 `'1.01.0'`) | double | double | double | double | double | double | monetary | **날짜 쪽**(문자를 정수로 파싱 → +1일/초) | varchar(접합) | varchar(접합) | ERR |
| **short/int/bigint** | double | short/int/bigint(넓은 쪽) | | | numeric | float | double | monetary | 날짜 쪽 | ERR | 정수(서수) | ERR |
| **numeric** | double | numeric | numeric | numeric | numeric | **double** | double | monetary | 날짜 쪽 | ERR | numeric | ERR |
| **float** | double | float | float | float | double | float | double | monetary | 날짜 쪽 | ERR | float | ERR |
| **double** | double | double | double | double | double | double | double | monetary | 날짜 쪽 | ERR | double | ERR |
| **monetary** | monetary | monetary(모든 숫자를 이김) | | | | | | monetary | 날짜 쪽 | ERR | monetary | ERR |
| **date/time/ts/dtt** | 날짜 쪽 | 날짜 쪽 | | | | | | 날짜 쪽 | **ERR**(날짜+날짜) | ERR | 날짜 쪽 | ERR |
| **bit** | varchar | ERR | | | | | | ERR | ERR | varbit | ERR | ERR |
| **enum** | varchar(이름 접합) | 정수(서수) | | | numeric | float | double | monetary | 날짜 쪽 | ERR | **smallint** | ERR |
| **set** | ERR | ERR | | | | | | ERR | ERR | ERR | ERR | set |

`-`, `*`, `/`: string×string·string×숫자 → **double**(접합 없음, `-`·`*` 도 오류 아닌 double — #313 §1.2 의 "NONE" 은 리터럴 폴딩 경로에서만), 숫자끼리는 `+` 와 같은 격자, **정수÷정수 = 정수 절삭**(`7/2` = 3, `typeof` integer), numeric÷정수 = numeric(scale 확장), 날짜−숫자 = 날짜, **date−date = bigint**, 날짜−문자 = ERR, 날짜×·÷ = ERR, enum−문자 = double(서수), enum 은 `-*/` 에서 항상 서수. `DIV`/`MOD`: 정수만, 결과 왼쪽 정수 타입.

### 3.2 산술 — 슬롯 경로 (`col op ?`, `? op ?`)

값 타입이 3.1 의 b 열과 같으면 **결과도 같다**(늦은 바인딩 = 값 타입으로 격자 재적용). 다른 점만:

| 조합 | 컬럼×컬럼 | `col op ?` / `? op ?` | 의미 |
|---|---|---|---|
| 숫자 컬럼 + BIT/SET 바인드, 시간 − 시간, 문자÷날짜 등 | ERR | **NULL**(오류 없음) | 값 타입에 따라 오류→NULL 로 갈림 |
| `? + ?` 문자·문자 | varchar 접합 | varchar 접합(`'1.01.0'`) | `plus_as_concat` 유지 |
| `int_col + ?` 1.1 / `int_col − ?` 1.1 | (리터럴 1.1 도) numeric 2.1 / −0.1 | numeric 2.1 / −0.1 | 절단 없음 — 값 타입 산술 |
| `int_col / ?` 2 | integer 절삭 | integer 절삭 | `/` 도 값 타입 |
| `? + 1` 정수 바인드 | — | integer 2 | 리터럴 형제가 있어도 값 타입(정수) |
| `? + 1` 문자 `'1.0'` | — | double 2.0 | |
| `? + 1` DATE | — | date(+1일) | |
| BIGINT 2^53+1 `+ 0.0` | — | numeric 9007199254740993.0(정확) | 값 타입이 NUMERIC 이라 손실 없음 |
| `enum_col + ?` 문자 / 정수 / 1.1 | varchar 이름접합 / 정수 / — | varchar `'Yes1.0'` / **varchar `2`** / varchar `2.50` | 결과 타입이 VARCHAR 로 승격돼 있음(collation 축) |

### 3.3 비교 (`=` / `<`) — 변환 방향

| 경로 | 문자 vs 숫자 | char vs varchar | 숫자 vs 숫자 | 문자 vs 날짜 | 숫자 vs 날짜 | enum vs 숫자 / 문자 | 근거 |
|---|---|---|---|---|---|---|---|
| 컬럼 = 컬럼 | **DOUBLE**(`'1.0' = 1` 참) | 패딩 구분(`'1.0  ' ≠ '1.0'`) | rank 상위(참) | ERR(coerce) | ERR / int vs time·ts 는 초·epoch 로 변환 | 서수 / 이름 (참) | #321 §2.2 |
| 컬럼 = 리터럴 | **정수 리터럴 → 컬럼 타입**(`str = 1` → `'1'`, 거짓) · **numeric/double/float 리터럴 → 양쪽 DOUBLE**(참) | 리터럴 CHAR 캐스트(참) | 컬럼 타입(`int = 1.5` → 0행, 반올림 없음; `int < 1.5` → DOUBLE) | 리터럴 파싱(ERR) | ERR | 서수/이름 | #313 §1.4-2, tc:5566 |
| 컬럼 = `?` | **컬럼 미러**: `str = ?` 정수·numeric 바인드 → 문자 비교 **거짓**; `int = ?` `'1.0'` → 1 (참); `int = ?` 1.5 → **0행**, `<` 1.5 → 1행 | `char(5) = ?` VARCHAR(20) 값 → **NULL**, 리터럴 `'1.0'` 바인드 → 참(재확인 필요) | 참 | `date = ?` 문자 → ·(측정 누락) / `str = ?` date → 거짓 | `int = ?` DATE → **ERR**(hv-coerce) | `enum = ?` 정수=서수, 문자=이름, **1.5 → floor 서수(참)** | #313 §2.4 |
| `?` = `?` | DOUBLE(참) | 패딩 구분(거짓) | 참 | ERR | ERR | 서수/이름 | 값 격자 |

### 3.4 인덱스 키 비교 — 리터럴(auto-param) vs 호스트 변수 (부록 A3)

| 컬럼 \ 상대 | `'1.0'` 문자 | `1` 정수 | `1.00` numeric / `1.0e0` double / `1.0f` | `9007199254740993` bigint | `1.5` | date/time/ts/dtt 리터럴 | `?` 바인드(모든 타입) |
|---|---|---|---|---|---|---|---|
| **string** | iscan `?:0` 1/1 | iscan `?:0` **0/0**(`'1'`) | **sscan `cast(c_string as double)= …` 1/1** | iscan 0/0 | iscan 0/0 | iscan 0/0 | iscan `?:0`, 컬럼 미러 → 숫자 바인드 0/0 |
| **int** | iscan 1/1 | iscan 1/1 | iscan 1/1 | iscan 0/0 | iscan **0/0** | ERR(coerce) | iscan; DATE 바인드 ERR |
| **numeric** | iscan 1/1 | iscan 1/1 | iscan 1/1 | ERR(coerce, 범위) | iscan 0/0 | ERR(no-op) | iscan |
| **date** | ERR(파싱) | ERR | ERR(no-op) | ERR | ERR | iscan 1/1(ts·dtt 도 1/1) | iscan(문자 바인드 포함) |
| **enum** | iscan 1/1 | iscan 1/1 | **1.5 → 1/1**(floor 서수) | iscan `c_enum=9007…` 0/0 | 1/1 | iscan `c_enum=date …` 0/0 | iscan; date 바인드 0/0 |
| **enum `<`** | **sscan `cast(c_enum as varchar) < …`** | sscan `cast(c_enum as integer) < 1` | sscan cast | | | ERR | iscan(ENUM 도메인, 서수) |

- 재작성 질의는 auto-param 도 호스트 변수도 `c = ?:0` 로 같다. 차이는 슬롯 도메인(auto-param = 리터럴 규칙 결과의 값 도메인, 호스트 변수 = 컬럼 미러)이며 **모든 셀에서 인덱스 스캔과 순차 스캔의 카운트가 일치**했다.
- 복합 키 `(c_int, c_string)`: 문자·정수·numeric·double·bigint 리터럴/바인드 모두 iscan, 카운트 일치; 날짜 바인드 ERR(hv-coerce)·날짜 리터럴 컴파일 ERR.
- `LIMIT 1.5`/`LIMIT '2'`/`KEYLIMIT 1.5` 리터럴은 **문법 오류**; `LIMIT ?` 는 문자 `'1.0'`·정수·numeric·double 수용, DATE·TIME 바인드 ERR.

### 3.5 대입 (INSERT 컬럼 ← 값)

| 컬럼 \ 값 | `'1.0'` | 1 | 1.5 | date | time | bit |
|---|---|---|---|---|---|---|
| int/bigint/numeric/double | 1 / 1.00 | 1 | **2 (반올림)** | 리터럴 ERR / **`?` 는 오류 없이 0행**(csql SA) → 정정(#358): `?` 도 -494 | 같음 | 같음 |
| string | `'1.0'` | `'1'` | `'1.5'` | `'01/02/2024'` | `'10:00:01 AM'` | `'8'` |
| date | 리터럴 ERR(파싱) / `?` 0행 | ERR / 0행 | | 값 | ERR | |
| time | `12:00:01 AM`(정수 1 → 1초) | 같음 | | ERR / 0행 | 값 | |
| timestamp | ERR / 0행 | `09:00:01 AM 01/01/1970`(epoch) | | `12:00:00 01/02/2024` | | |
| enum | `'1.0'`(이름) | `'1.0'`(서수 1) | `'1.0'`(floor) | ERR | | ERR |

### 3.6 공통값 (COALESCE / CASE / UNION)

| 조합 | COALESCE(col, col) | CASE col ELSE col | col UNION ALL col | COALESCE(col, `?`) / COALESCE(`?`, `?`) | col UNION ALL `?` |
|---|---|---|---|---|---|
| 숫자 × 숫자 | 격자(int×numeric → numeric) | 격자 | **double**(정수 UNION numeric 도 double — sc:334) | 값 격자와 같음 | **double** |
| 문자 × 숫자 | **varchar**(`'1'`) | varchar | varchar(`'1.0'`) | **varchar**(`coalesce(int_col, ?)` 에 문자 바인드 → `'1'`) | varchar |
| 날짜 × 숫자/문자 | varchar | varchar | **ERR**(coerce) | varchar | ERR |
| date × ts/dtt | ts / dtt | | ERR | ts/dtt | |
| enum × any | (D1 assert) | | | (D1 assert) | |

즉 COALESCE/CASE 는 부류가 다르면 VARCHAR 로 수렴하고, UNION 은 숫자끼리 DOUBLE·날짜 섞이면 오류다.

### 3.7 집계·GROUP BY·분석 (부록 A2 `AGG.*`)

| 문맥 | 컬럼(타입별) | 슬롯 `?`(바인드 타입별) |
|---|---|---|
| `sum` | int → **INT 오버플로 오류**(2147483647+3), bigint/numeric/double 유지, 문자·날짜 ERR, enum → int(서수) | 결과 = 바인드 타입(int 5, bigint, num(10,2) 7.50, double), 문자 `'1.0'` → **double** 5.0, `'2024-01-02'` → ERR, DATE → ERR, **TIME → time 10:00:01**, DATETIME → datetime |
| `sum … group by` | 같음 | 같음(그룹별) |
| `avg` | int → 오버플로 오류(합 단계), 그 외 double | double; 날짜·시간 ERR |
| `min/max` | 컬럼 타입 | 바인드 타입 그대로(문자·날짜 포함) |
| `median` / `percentile_cont … order by x` | 숫자 → double, date/dtt → 같은 타입, **varchar 컬럼 → 값 내용으로 갈림**(`'1','2'` → 1.5 double; `'2024-01-01'` → datetime; 혼합 → ERR) | 바인드 타입: 숫자 → double, 문자 `'1.0'` → double, `'2024-01-02'` → **datetime**, date → date |
| `count(distinct ?)` | | 1 (타입 무관) |
| `group_concat` | varchar | 문자열화; NULL 바인드 → **D2 assert** |
| `group_concat(s + ? …)` | | 문자·숫자·날짜 바인드 → **D3 assert** |
| `sum(?) over (partition by)` | | 숫자 OK; 문자날짜·DATE·TIME·DATETIME → **D4 assert** |
| `max(?) over()`, `lead(?)`, `first_value(?)` | | 바인드 타입 그대로 |
| `ntile(?)` | | 정수·numeric·double OK, 문자날짜/날짜 ERR, bigint 범위 ERR |
| `group by ?`, `order by ?`, `?, sum(i) … group by 1` | | **컴파일 오류**("can not be a GROUP BY/ORDER BY") — 자유 문맥 슬롯이 아님 |
| `having sum(i) > ?` | | 미러(sum 결과 타입) — int 바인드 ERR overflow 는 `sum(i)` 오버플로 때문 |
| `sum(i + ?)` | | int 바인드 → **INT 오버플로 오류**(2147483647+1), 문자 → double, numeric → numeric, DATETIME → datetime 누산(!) |
| `select ?` UNION 혼합 → `sum(x)` | | int∪double, int∪문자 → **ERR incompatible types**(qfile_unify_types) |

### 3.8 함수 인자 슬롯 (부록 A2 `FN.*`)

| 함수 | 바인드 타입별 현행 결과 |
|---|---|
| `str_to_date(?, '%Y-%m-%d')` | 문자 `'2024-01-02'` → date; **정수 1 → date 0001-01-01**; 그 외 → 오류(잘못된 인자) |
| `str_to_date('…', ?)` 포맷 슬롯 | 포맷이 아닌 값 → 오류(정상) |
| `select v from (select str_to_date(sd, ?) v …) where v > date'…'` | 포맷 바인드 시 파생 컬럼 비교 — 이 표본에서는 포맷 값 문제로 미측정(#276 별건 기록: `*variable*` CAST -181) |
| `to_char(?, 'YYYY-MM-DD')` | 문자·DATE·DATETIME OK, **숫자 → "Invalid format"**, TIME ERR |
| `to_char(?, '9,999.99')` | 숫자 OK(`' 1.00'`), **문자 `'1.0'` → `'1.0'` 그대로(포맷 무시)**, 날짜 ERR |
| `to_char(?)` | 전부 문자열화 |
| `to_char(dtt_col, ?)` 포맷 슬롯 | 문자 → Invalid format(값이 포맷 아님), 숫자 → "Empty string not allowed", **BIGINT → D5 assert** |
| `to_date(?, 'YYYY-MM-DD')`, `to_date(?, ?)` | 문자날짜만 OK |
| `to_number(?)` | 정수·bigint → numeric; 문자 `'1.0'`·numeric·double → **오류**(포맷 불일치) |
| `addtime(?, time)` | 문자 → **varchar** 결과(`'01:00:01 AM'`), 숫자 → ERR, DATE → datetime, TIME → time, DATETIME → datetime |
| `from_tz(?, 'Asia/Seoul')`, `new_time(?, …)` | **DATETIME 바인드만 성공**; 문자·DATE 포함 전부 ERR (L-17) |
| `date_add(?, interval 1 day)` | 문자날짜 → **varchar** `'01/03/2024'`, DATE → varchar, 숫자 → ERR |
| `hour(?)` | 문자 `'1.0'` → 0(!), 숫자 → ERR, TIME/TS/DTT → 10 |
| `extract(year from ?)` | DATE 2024, **TIME → 32765**(쓰레기), 숫자·문자 ERR |
| `trunc(?, 'default')` | 숫자 → 숫자, DATE·DATETIME → date, 문자날짜 → ERR |
| `round(?, 1)` | 결과 = 바인드 타입(int 1, numeric 1.50, **bigint 9007199254740992** — 손실) |
| `abs/ceil(?)` | 바인드 타입; 문자 → double |
| `ifnull(?, 1)` | int/bigint/numeric/double 유지, **문자·날짜·bit 바인드 → varchar**(`'01/02/2024'`) |
| `nullif(?, '1.0')` | 문자 형제 → 결과 **varchar**(`'9007199254740993'`, `'01/02/2024'`) |
| `greatest(?, 3, 'b')` | 전부 **char `'b'`**(문자 비교) |
| `least(?, '2', 1)` | 전부 varchar `'1'` |
| `coalesce(cast(? as datetime), cast(? as datetime), ?)` NULL,NULL,x | 결과 = x 의 타입(문자 → varchar) |
| `if(?, 'T', 'F')` | **문법 오류**(조건에 `?` 단독 불가) — #313 U15 는 `IF(? = ?, …)` 류에만 해당 |
| `case ? when ? then 'first' when 2 …` | 전부 `'first'`(같은 값) |
| `case ? when 1 then 'one' when '1.0' then 'str' else 'else'` | 문자 `'1.0'` → `'one'`(DOUBLE 비교), int → `'one'`, bigint/numeric/double → `'else'`, DATE·TIME → ERR |
| `decode(?, '', 'E', null, 'N', -1)` | 전부 컴파일 ERR(`'E'` 를 double 로 캐스트 — 형제 -1 이 결과 타입을 정함) |
| `decode(?, '', 'E', null, 'N', 'Z')` | NULL → `'N'`, 그 외 `'Z'`, DATE·DATETIME → ERR(`''` 를 날짜로) |
| `i in (1, '2', ?)` | 2 (타입 무관) ; `? in {1,2,3}` 문자·int → 5, 그 외 0 |
| `s like ?` | int 바인드 → 1(`'1'`), 그 외 0 ; `? like ?` 전부 1 |
| `concat(?, ?)` | 문자열화, collation **utf8_bin** |
| `rtrim(? + ?, '0')` | 문자 → `'1.01.'`, 정수 → `'2'`, DATE ERR, TIME/DTT → NULL |
| `repeat(? + ?, abs(?))` | 문자 → `'1.01.0'`, int → `'2'`, bigint → overflow, 날짜 ERR |
| `field(?, 1, '1.0', 1.5)` | 문자 `'1.0'` → 1, int → 1, numeric/double → 3, 그 외 0 |
| `elt(?, 'a', 'b')` | numeric 1.50 → `'b'`(반올림 2) |
| `limit ?` / `limit ?, ?` / `keylimit ?` | 문자·숫자 OK(문자 `'1.0'` → 1), DATE·TIME ERR; numeric 1.50 → **1행**(절삭/반올림?) |
| `date_col - ?` | 문자날짜 → **bigint −86400000**(ms), int → date, DATE → **int −1**(일), TIME → NULL |
| `datetime_col - ?` | 문자날짜 → bigint, int → datetime, DATE → bigint(ms) |
| `enum_col = ?` / `<> ?` / `< ?` | int 1 → 서수 1(1행), 문자 `'1.0'` → 이름(0행 — 이름은 Yes/No/Cancel), numeric 1.5 → floor 1(1행); `< ?` bigint → 3행(서수 < 큰 수), DATE → ERR |
| `insert tg(e) values (?)` | int/numeric/double → `'Yes'`, 문자 `'1.0'`·DATE → ERR(이름 없음) |

### 3.9 다중 행 VALUES·UNION·INSERT…SELECT·MERGE·CTE (부록 A2 `MR.*`)

| 문맥 | 현행 |
|---|---|
| `(values (timestamp'…'), (?)) v(x)` | **전부 ERR coerce**(어떤 바인드든) — L-18 의 근원 |
| `(values (1), (?))` / `(values (?), (2))` | 결과 **double**(숫자·문자 바인드), 날짜 ·(측정 누락) |
| `(values (?), (?))` | 바인드 타입 그대로 |
| `insert into tv(dtt) values (datetime'…'), (?)` | 문자날짜·DATE·DATETIME → 2행, 그 외 → 0행(오류 없음) |
| `select i … union all select ?` | **double**(정수·문자·numeric) |
| `select ? … union all select ?` | 바인드 타입; NULL·NULL → **D6 assert** |
| `insert into tv(i) select ?` | 문자 `'1.0'` → 1, numeric 1.50 → 2, bigint → overflow ERR, DATE → ERR |
| `merge … using (select ? v …)` | INSERT…SELECT 와 같음 |
| `select * from (select ? c) t where t.c = 1` | 문자 → `'1.0'` 1행, int → 1행, numeric/double/bigint → **0행**(CAST(t.c AS INTEGER) 래핑 후 값 비교), DATE → ERR |
| `select (select ?) + 1` | 값 타입 산술(문자 → 2.0 double) |
| `with c as (select ? v) select v + 1` | 값 타입 |
| 재귀 CTE `select ? union all select n + 1` | int/double OK, 문자·numeric → **ERR incompatible**, NULL → D6 assert |
| `update set i = ?` / `i = i + ?` | 컬럼 미러 / 늦은 바인딩 |

### 3.10 세션변수 (부록 A2 `SV2.*`, A1 `SV.*`)

| `SET @v = x` 의 x | 저장 타입 | `@v + 1` | `@v = 1` / `= '1.0'` / `c_int = @v` | `to_char(@v)` | `addtime(@v, time)` | `sum(@v)` |
|---|---|---|---|---|---|---|
| `'1.0'` | varchar | **double** 2.0 | 1 / 1 / 1 | `'1.0'` | `'01:00:01 AM'`(문자열) | double |
| `'2024-01-02'` | varchar | ERR coerce | ERR | `'2024-01-02'` | `'01:00:00.000 AM 01/02/2024'` | ERR |
| 1 (int) | integer | int 2 | 1 / 0 / 1 | `'1'` | ERR | int |
| 1.50 numeric | numeric(10,2) | numeric 2.50 | 0 / 0 / 0 | `'1'`(포맷 없음) | ERR | numeric |
| `date'…'` | **varchar** `'01/02/2024'` | ERR coerce | ERR | `'01/02/2024'` | 문자열 결과 | ERR |
| `time'…'`, ts, dtt | varchar | ERR | ERR | 문자열 | 문자열 | ERR |
| B'1' | varchar `'8'` | double 9.0 | 0 | `'8'` | `'01:00:08 AM'` | double 40 |

- `SET @v = date'…'` 가 **문자열로 저장**되는 것이 L-15 (a)(c)(d) 의 뿌리다(쓰기 노드는 타입을 기억하지만 세션변수 저장은 문자열).
- `select @a := @v + i` 뒤 `typeof(@a)` = 산술 결과 타입(double/int/…). `select @w := ?` 는 바인드 타입 그대로.

### 3.11 슬롯 문맥별 (부록 A1 `SLOT.*`)

| 문맥 | 바인드 타입별 현행 |
|---|---|
| `select ?` | 바인드 타입 그대로(varchar/char(5)/short/int/bigint/num(10,2)/float/double/monetary/date/time/ts/dtt/bit/sequence) |
| `sum(?)`, `min(?)` | 바인드 타입 그대로(TIME·DATETIME·BIT·SET 까지 "누산") |
| `avg(?)` | double; 날짜·시간·bit·set ERR |
| `median(?)` | 숫자·문자 → double, 날짜·시간 → 같은 타입, bit·set ERR |
| `-?`, `abs(?)`, `round(?,1)` | 바인드 타입(문자 → double), 날짜 ERR |
| `ifnull(?, 1)` | 숫자 → 바인드 타입, 문자·날짜·bit → varchar |
| `? + 1` | 바인드 타입 산술(문자 → double, DATE → date+1) |
| `7 / ?` | 정수 → int 절삭, 문자 → double, 날짜 → NULL |
| `enum_col + ?` | 결과 **varchar**(정수 2 → `'2'`) |
| `enum_col = ?` | 서수/이름/floor; `enum_col < ?` 문자·정수 → 0행, **TIME 바인드 → 2행(!)**, DATE·TS·DTT → ERR |
| `c_int in (?, 5)`, `between ? and 5` | 문자·숫자·enum OK, DATE/DTT/BIT/SET ERR, TIME/TS 0행 |
| `c_int in (select ?)` | 문자·숫자 1행 |
| `insert ta(c_int) select ?` | 문자·숫자·enum 1, 날짜·bit·set **0행(오류 없음)** |
| `limit ?` | 문자·숫자 OK, 날짜 ERR |
| `order by ?` | 컴파일 오류 |
| `group_concat(?)` | 문자열화; BIT → ERR codeset; SET → ERR |
| `select ? union all select ?` | 바인드 타입 |
| `(values (1),(?))` | double |

---

## 4. 후보 원칙을 적용하면 — 셀별 TO-BE 와 깨지는 것

후보 원칙(1라운드 추천안): **P1** 슬롯은 같은 식에서 타입이 알려진 형제를 미러한다. **P2** 형제가 전부 슬롯이면 산술 → DOUBLE, 그 밖 → VARCHAR. **P3** 컬럼·리터럴끼리의 현행 격자(3.1·3.3 컬럼×컬럼·컬럼×리터럴)는 건드리지 않는다. **P4** 게이트는 값을 계획 도메인으로 1회 변환하고 실패는 오류(-494 계열). 표의 "깨짐" 은 이전 캠페인 CTP diff(부록 A4) 에서 같은 부류가 실제로 깨진 TC 를 인용한다(이전 캠페인 규칙은 `?+?`→NUMERIC/DOUBLE, 세션변수 VARCHAR 등 일부가 다르지만 부류는 같다).

| # | 현행(AS-IS 셀) | P1~P4 적용 후 | 답안 변경 여부·깨지는 질의(TC) |
|---|---|---|---|
| T1 | `int_col + ?` 1.1 → numeric 2.1 (3.2) | 미러 → INTEGER 슬롯, 게이트 1.1→INT 변환: **strict 면 -494 / 현행 캐스트 규칙이면 1(반올림)** → 2 | **의미 변경**. 이전 캠페인 diff: `bug_bts_4562` `2 3`→`2 3.0`(그쪽은 DOUBLE 로 갔음), `bug_bts_6605`·`cbrd_22683` 표기 `1`→`1.0`. 미러(INTEGER)로 가면 표기는 유지되고 소수 바인드만 깨짐(L-12 의 절단) → **2라운드 Q(손실 정책)** |
| T2 | `int_col + ?` DATE 바인드 → date+1 (3.2) | INTEGER 슬롯 → DATE 값 변환 불가 → **-494** | 깨짐: `late_binding_001/002`(enum + date/time 바인드 6블록 → -494), `prepare_002`(`e1 + ?` datetime) — **CAST 요구로 답안 변경** |
| T3 | `int_col / ?` 2 → 3(절삭) | 미러(INTEGER) → 절삭 유지 | 변화 없음(P2 DOUBLE 은 `? / ?` 에만) |
| T4 | `? + ?` 문자 → 접합 `'1.01.0'`; 정수 → int | P2: DOUBLE 슬롯 → 문자 바인드 `'a'` → -494, `'1.0'` → 2.0, 정수 → **2.0 표기** | 깨짐: `bug_bts_8136`(`?:1 + ?:2` 문자 → -494), `_03_plus.sql`(`xy` 접합 → -494), `bug_bts_13523`(`'abc' + ?` → `abc2`… 접합 의미), `_14_find_in_set`·`_15_position`(`s1 in ? + ?` 접합 → -494), `bug_bts_12256`(`2`→`2.0`). 매뉴얼 `plus_as_concat` 절 1줄(L-13) |
| T5 | `? = ?` 문자 vs 숫자 → DOUBLE 참 (3.3) | P2: VARCHAR 슬롯 → 문자 비교(`'01' = 1` 거짓) | 깨짐 후보: `_01_case_hostvar`·`_02_decode_hostvar`(`case ? when ?` 타입 일치 비교 → 문자 비교로 `first`→`else`, -181 → 값) — 이전 캠페인 diff 그대로 |
| T6 | `select ?` 메타 = 바인드 타입 (3.11) | P2: VARCHAR | 표기 변경 없음(값은 문자열화), JDBC 메타 타입 변경(L-31) |
| T7 | `varchar_col = ?` 정수 바인드 → 문자 비교 거짓 (3.3) | 그대로(현행이 이미 미러) | 변화 없음 |
| T8 | `str_col = 1.00`(numeric 리터럴) → DOUBLE 비교, **인덱스 포기**; `str_col = 1` → 문자 비교, 인덱스 사용 (3.4) | P3: 그대로 | 변화 없음. 규칙표에 "리터럴 종류별 두 행" 으로 명시만(Q3) |
| T9 | `int_col = ?` 1.5 → 0행, `<` 1.5 → 1행 (3.3) | 미러(INTEGER) + 게이트 변환: **strict** 면 -494(현행 0행에서 오류로), **현행 캐스트(ROUND)** 면 `= 2` 로 1행(조용한 오답) | **둘 다 답안 변경** — 2라운드 Q(손실 정책). 현행 CAS 캐스트는 실패 시 값 유지(keep) 라 0행 |
| T10 | `char(5)_col = ?` VARCHAR 값 → NULL(!)/리터럴 → 참 (3.3) | VARCHAR 미러 + 컬럼 collation, 패딩 안 함 → trailing space 구분 | 현행 CHAR 컬럼 `= ?` 의 NULL 은 결함 후보(별건); 규칙표 Q4 |
| T11 | `enum_col + ?` 문자 → 이름 접합, 정수 → `'2'`(varchar) (3.2) | 서수 승격 → SMALLINT 형제 → 정수 미러; 문자 바인드 → -494 | 깨짐: `late_binding_001`(`e1 + '-a'` → `Cancel-a` 접합 → -494), `prepare_002`(`e1 + ?` 5열 → -494), `trac_344_02/03`(-494) — 이전 캠페인 diff 그대로 |
| T12 | `enum_col = ?` 정수=서수/문자=이름/1.5=floor (3.3) | ENUM 도메인 유지 + 게이트 `tp_value_cast` 표(§1.6): 정수→서수, 문자→이름, 실수→floor | 변화 없음(값 타입 갈림은 변환 함수의 입력 규칙이라 허용할지 **Q7-2라운드**); `enum_col < ?` TIME 바인드 2행은 결함 후보 — 정정(#358): 리터럴 `enum_col < time'…'` 도 2행(ENUM 라벨 → TIME, 부록 A3 `cast(c_enum as time)` 2/2) — 슬롯 결함 아님, [#360](https://github.com/xmilex-git/workspace/issues/360) |
| T13 | `coalesce(int_col, ?)` 문자 바인드 → varchar `'1'` (3.6) | 형제 미러 → INTEGER, `'a'` 바인드 → -494 | 깨짐: `bug_3256`(`ifnull(?, 1)` DATE 바인드 → -494 4블록), `bug_bts_9953`(`trunc(?, 'default')`), `cbrd_24598`(`decode(?, '', c, null, c, -1)` -181 → 값) |
| T14 | `case ? when ? …` (3.8) | 조건 슬롯끼리 VARCHAR 비교 | `_01_case_hostvar`·`_02_decode_hostvar` `first`→`else` |
| T15 | `sum(?)` = 바인드 타입, TIME 누산까지 (3.7) | P2: `sum(?)` DOUBLE, `min/max(?)` VARCHAR, `median(?)` DOUBLE | 깨짐: `bug_bts_13653`·`bug_bts_13916`·`bug_bts_16039`(median/percentile 문자열 입력 -494 — 이전 캠페인은 CAST 요구), `_18_host_vars`(분석함수 표기 `5.700000000000002`→`5.7`) |
| T16 | `sum(i + ?)` int 바인드 → INT 오버플로 오류 (3.7) | 미러 유지(INTEGER) → 그대로 | 변화 없음(SUM(int) 승격은 별건) |
| T17 | `to_char(?, 'YYYY-MM-DD')` 문자·날짜 OK, 숫자 ERR (3.8) | 포맷 리터럴 추론(날짜 포맷 → DATETIME 슬롯) → 숫자 바인드 -494(현행도 ERR), 문자 `'2024-01-02'` → DATETIME 변환 후 포맷 | 깨짐 후보: 문자 바인드가 포맷과 안 맞는 TC(현행은 그대로 출력). 이전 캠페인: `to_char(?, ?)` 26건 -494(NUMBER 고정 탓) — 포맷 추론이면 회피(#309) |
| T18 | `addtime(?, time)` 문자 → **varchar 결과** (3.8) | 시그니처 기본 인자형(DATETIME) → 문자 `'1.0'` → -494, 결과 datetime | 깨짐: `bug_bts_5860_1`(addtime -621 → 값, 이전 캠페인은 반대 방향) |
| T19 | `from_tz(?, …)` DATETIME 만 (3.8) | 그대로(이미 하나) | 변화 없음 |
| T20 | `date_add(?, interval 1 day)` 결과 varchar (3.8) | 그대로(문자열 결과 규칙) | 변화 없음 |
| T21 | `(values (ts'…'), (?))` → 항상 ERR (3.9) | 첫 행 미러 → TIMESTAMP 슬롯 → 정상 동작 | **오류 → 값**(개선). L-18 |
| T22 | `(values (1), (?))`·`i UNION ALL ?` → double (3.9) | 형제 미러 → INTEGER | **표기 변경** `1.0`→`1`(이전 캠페인 반대 방향 `bug_bts_4565` `6.0`→`6`) |
| T23 | `select ? union all select ?` NULL → D6 assert | P2 VARCHAR | 결함 소멸 |
| T24 | `@v := date` 가 VARCHAR 저장, `@v + 1` ERR (3.10) | Q5(a): 읽기를 슬롯 취급(형제 미러) + 게이트 변환 → `'01/02/2024'` → INTEGER 변환 실패 -494(현행도 ERR); `@v := '1.0'` 뒤 `@v + 1` double 2.0 → **INTEGER 2** | 깨짐: `bug_bts_4562`(`@int_var + @timestamp_var`), `bug_bts_14877`(`@a := @a + t.a` 표기 `20`→`20.0` 는 이전 캠페인의 DOUBLE 규칙), `_07_session_var`(`@v + ?` 표기·typeof `integer`→`varchar`), `cbrd_25567`·`bug_bts_7503`(플랜 텍스트에 `cast(@v as …)` 노출) |
| T25 | PL/CSQL 맨 `?` (SA 미측정) | Q6(a) 선언 타입 전달 | 이전 캠페인 diff: `bfn_type_cast2`(-889 → NULL 값), `bfn_string_field`(3→0 조용한 오답), `bfn_type_format`(NUMERIC scale 절단), `to_char/to_date/…`(`The argument specifying the language must be a string literal` — 리터럴을 `?` 로 넘긴 탓), `check_add_func_return`("string does not fit"), `test_tcl`(CAS 사망) — 선언 타입 전달로 전부 해소 대상 |
| T26 | HV collation 19건(`_28_features_930/issue_12129_HV_collation`) | 짝 티켓 #322 | 참고만: 이전 캠페인은 `-1150/-622` 오류가 값으로 바뀌거나(개선) collation 표기가 `utf8_bin`→`iso88591_bin` 으로 바뀜(회귀) |
| T27 | `int_col = ?` 에 `'1.0'` → 1(참) (3.3) | 미러 + 게이트 문자→INT 파싱: `'1.0'` → 1 (현행 `tp_atobi` 반올림 규칙) | 변화 없음 |
| T28 | `INSERT int_col ← ?` DATE → 오류 없이 0행 (3.5) | 게이트 변환 실패 → -494 | **오류로 바뀜**(개선, 결함 후보) — 정정(#358): 현행이 이미 -494, 변화 없음 |
| T29 | `insert ta(c_int) select ?` 날짜 → 0행 (3.11) | 대상 컬럼 미러 → -494 | 같음 — 정정(#358): 현행이 이미 -181(`Cannot coerce value of domain "date" to domain "integer"`) |
| T30 | `LIMIT ?` 문자 `'1.0'` → 1행 | BIGINT 미러(현행) | 변화 없음 |

정리: P1(형제 미러) 만으로 바뀌는 셀은 **산술·함수 인자·공통값·집계 자리의 슬롯**이고, 바뀌는 방향은 두 가지뿐이다 — (i) 값 타입이 형제와 다른 부류(문자·날짜)일 때 **오류(-494)로**, (ii) 형제가 정수인데 소수를 바인드할 때 **손실 정책**(strict 오류 / 반올림 / 값 유지) 이 답을 정한다. P2(DOUBLE/VARCHAR 폴백) 가 바뀌는 셀은 `? op ?`·`select ?`·`? = ?`·`sum/min/max/median(?)`·`coalesce(?, ?)`·`case ? when ?` 이고 이전 캠페인 diff 에서 R7(46건)·R8(2건) 이 이 부류다. 이전 캠페인 483건 중 R1(153)·R2(60) 는 (i) 의 "오류로" 이고, R4/R6/R9/R14/R5/R10(213건) 은 프로토타입 결함이라 이번 규칙과 무관하다.

---

## 5. 렛저 대응표 (L-10~L-25, 이 문서에서 다룬 곳)

| L | 위치 |
|---|---|
| L-10 ENUM/SET 기본 하나로 | §3.2·3.3·3.4 enum 행, §4 T11·T12, 결함 D1·D7 |
| L-11 NUMERIC p/s | §3.2(`1.10 + ?`→numeric 2.1, BIGINT+0.0 정확), §3.8 round(bigint 손실), T1 |
| L-12 `+ -` 정수 고정 / `/` 절삭 | §3.1·3.2(`/` 절삭 유지, `int_col − ?` 1.1 = −0.1), T1·T3·T9 |
| L-13 `? + ?` 접합 | §3.2, T4 |
| L-14 도메인 축 ≠ collation 축 | §3.8 concat collation utf8_bin, T26(#322 로) |
| L-15 세션변수 | §3.10(date 가 varchar 로 저장), T24 |
| L-16 PL/CSQL | T25(이전 캠페인 diff 인용, SA 미측정) |
| L-17 GENERIC 인자 일괄 고정 | §3.8 to_char/addtime/from_tz/new_time 행, T17·T18·T19, D5 |
| L-18 다중 행 VALUES | §3.9, T21·T22, D6 |
| L-19 coalesce cast 체인 collation | §3.8 `coalesce_cast_chain` 행(결과 = x 타입) |
| L-20 LIMIT/KEYLIMIT | §3.4·3.11 limit 행, T30 |
| L-21 MEDIAN/PERCENTILE 정렬 키 | §3.7 median/percentile 행(문자 컬럼이 값 내용으로 갈림), T15 |
| L-22 auto-param 도메인 ≠ 값 | §3.4(캐스트 식 리터럴은 auto-param 아님; `c = ?:0` 형태 동일) |
| L-23 답안 변경 목록 | §4 전체 |
| L-24 미실행 문장 | §3.11 `select ? … where 1 = 0` → 0행(메타 미측정, csql) |
| L-25 SET NAMES | 부록 A2 `COLL.*`: `set names utf8 collate utf8_en_ci` 뒤 새 prepare 의 `?` collation 은 utf8_en_ci(리터럴과 같음) — 기존 prepared 문 재컴파일은 미측정 |
