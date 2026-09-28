# tc/pr-8022 변경 설명 — 도메인·collation 사전 확정 (CUBRID/cubrid#8022)

지도: [xmilex-git/workspace#312](https://github.com/xmilex-git/workspace/issues/312) · 티켓: [#345](https://github.com/xmilex-git/workspace/issues/345)(#346 합침) · 엔진 PR: [CUBRID/cubrid#8022](https://github.com/CUBRID/cubrid/pull/8022) · TC PR: [CUBRID/cubrid-testcases#3588](https://github.com/CUBRID/cubrid-testcases/pull/3588) · 작성 2026-09-28

- **비교 범위**: testcases develop `669fbd6d9` 대 `tc/pr-8022` `1fda5883e`. 이 브랜치는 CI 자동화의 초기화 커밋(`c5c331fea`, 내용 없음) 위에 캠페인 커밋 32개를 얹은 것이다. 트리는 캠페인 브랜치 `dpin-tc`(`5ca2aa2d3`)와 같다.
- **바뀐 파일은 62개다.**
  - 기존 케이스를 고친 것이 22개다: `.answer` 11 · `.answer_cci` 10 · `.sql` 1.
  - 새로 더한 것이 40개다: 케이스 20과 그 답 20, 모두 `sql/_07_misc/domain_*` 아래다.
  - 지운 기존 파일은 없다.
- `cubrid-testcases-private-ex` 의 `tc/pr-8022`([#4258](https://github.com/CUBRID/cubrid-testcases-private-ex/pull/4258))는 PR CI 의 shell 결과로 두 커밋(`6542a06f6`·`fb242a0ed`, 파일 9개)을 받았다. 설명은 §4 다.
- **답의 기준**: 원칙은 "답은 develop 과 같다"(P0)이다. develop 과 다른 답은 모두 사용자가 승인한 스펙 변경이나 없어진 develop 결함이다. 문장별 develop 답과 새 답, 매뉴얼 문장은 [스펙 변경 문서](https://github.com/xmilex-git/workspace/blob/main/docs/research/domain-pin-spec-changes.md)(§ 번호로 아래에 인용)에 있다.
- 오류 코드:
  - -1118 `ER_ARG_CAN_NOT_BE_CASTED_TO_DESIRED_DOMAIN`
  - -1384 `ER_QPROC_SESSION_VARIABLE_TYPE`(이 PR 이 새로 만든 코드)
  - -456 `ER_QPROC_INCOMPATIBLE_TYPES`
  - -454 `ER_QPROC_INVALID_DATATYPE`
  - -181 `ER_TP_CANT_COERCE`
  - -1150 collation 불일치

## 0. 한눈에

| 구분 | 파일 | 바뀐 답 블록 | 근거 |
|---|---|---|---|
| 문자열 컬럼·식의 MEDIAN/PERCENTILE 은 DOUBLE → 날짜·시간 문자열은 -1118 | `.answer` 9 (케이스 9) | 31 | D-335-10, 스펙 변경 §2 |
| 문장이 읽는 세션변수는 한 타입 → 다른 타입 대입은 실행 전 -1384 | `.answer` 1 (`bug_bts_6605`) | 1 | #366 U3, 스펙 변경 §9 |
| 같은 prepare 의 반복 실행이 상수를 바꾸지 않는다(develop 의 "known bug" -181 이 없어짐) | `.sql` 1 + `.answer` 1 (`cbrd_24598`) | 2 | #352 허용 diff(사용자 승인 2026-09-25), 스펙 변경 §3 |
| 위 10건의 CCI 답(`sql_by_cci` 스위트용) | `.answer_cci` 10 | 32 | #345(#335·#366 인계) |
| 새 케이스 — 캠페인이 바꾼 실행 경로마다 develop 답을 고정하고, 스펙 변경 자리는 새 답을 고정 | 케이스 20 + 답 20 | — | #330·#338~#368 |

## 1. 답이 바뀐 기존 케이스

### 1.1 문자열 컬럼·식을 받는 MEDIAN/PERCENTILE 은 DOUBLE (D-335-10, 스펙 변경 §2) — 9 케이스, 31 블록

- **develop**: 문자열 컬럼이나 식을 받는 MEDIAN·PERCENTILE_CONT·PERCENTILE_DISC 의 결과 타입을 **첫 값**으로 정했다. DOUBLE → DATETIME → TIME 순으로 시도해, 날짜 문자열이 든 컬럼은 DATETIME 결과를 냈다.
- **이 PR**: 값이 없는 문자열 인자(컬럼, 계산식)의 결과 타입은 **타입으로** 정한다. 문자열은 DOUBLE 이다. 매뉴얼의 PERCENTILE 규칙("숫자로 변환되는 문자열")과 Oracle·PostgreSQL 이 같은 규칙이다(D-335-10, 사용자 결정 2026-09-24). 그래서 날짜·시간 문자열 값은 DOUBLE 로 바뀌지 않고 -1118 이 된다.
- 값을 가진 인자(문자열 리터럴·호스트 변수·세션변수)는 전처럼 값으로 분류한다(D-328-06).
- 아래 블록의 `c12`·`c13`·`c14`·`s`·`to_char(col4, …)` 는 날짜·시간 문자열을 담은 문자열 컬럼 또는 식이다.

#### `sql/_13_issues/_14_1h/answers/bug_bts_13916.answer`
- 블록 97: `select a,median(c12) from median_t group by a order by 1;`
  - develop: `a    median(c12) / 1     2055-07-02 12:30:30.555 / 2     2012-02-02 02:02:02.222` …(4행)
  - 새 답: `Error:-1118`
- 블록 98: `select a,c12,median(c12) over(partition by a) from  median_t order by 1,2;`
  - develop: `a    c12    median(c12) over (partition by a) / 1     2011-1-1 1:1:1.111     2055-07-02 12:30:30.555 / 1     2099-12-31 23:59:59.999     2055-07-02 12:30:30.555` …(12행)
  - 새 답: `Error:-1118`
- 블록 127: `select a,median(c12) from median_t group by a order by 1,2;`
  - develop: `a    median(c12) / 1     2055-07-02 12:30:30.555 / 2     2012-02-02 02:02:02.222` …(5행)
  - 새 답: `Error:-1118`

#### `sql/_26_features_920/issue_11087_median/answers/11087.answer`
- 블록 27: `select a,median(c12) over(partition by a) from median_t order by 1,2;`
  - develop: `a    median(c12) over (partition by a) / 1     2055-07-02 12:30:30.555 / 1     2055-07-02 12:30:30.555` …(12행)
  - 새 답: `Error:-1118`
- 블록 72: `select a,median(c12) from median_t group by a order by 1,2;`
  - develop: `a    median(c12) / 1     2055-07-02 12:30:30.555 / 2     2012-02-02 02:02:02.222` …(4행)
  - 새 답: `Error:-1118`
- 블록 120: `select a,median(c12) over(partition by a) from median_t order by 1,2;`
  - develop: `a    median(c12) over (partition by a) / 1     2055-07-02 12:30:30.555 / 1     2055-07-02 12:30:30.555` …(16행)
  - 새 답: `Error:-1118`
- 블록 138: `select a,median(c12) from median_t group by a order by 1,2;`
  - develop: `a    median(c12) / 1     2055-07-02 12:30:30.555 / 2     2012-02-02 02:02:02.222` …(5행)
  - 새 답: `Error:-1118`

#### `sql/_26_features_920/issue_11087_median/answers/11087_1.answer`
- 블록 28: `select  median(c12)  from median_1;`
  - develop: `median(c12) / 2013-03-20 15:03:03.333`
  - 새 답: `Error:-1118`
- 블록 31: `select  median(a),  median(c1), median(c2), median(c3), median(c4), median(c5), median(c6), median(c7), median(c8), median(c9), median(c10), median(c11), median(c12), median(c13), median(c14)  from median_1;`
  - develop: `median(a)    median(c1)    median(c2)    median(c3)    median(c4)    median(c5)    median(c6)    median(c7)    median(c8)    median(c9)    median(c10)    median(c11)    median(c12)    median(c13)    m`
  - 새 답: `Error:-1118`
- 블록 45: `select  a, median(c12) over(partition by a)  from median_1 order by 1;`
  - develop: `a    median(c12) over (partition by a) / 1     2055-07-02 12:30:30.555 / 1     2055-07-02 12:30:30.555` …(12행)
  - 새 답: `Error:-1118`
- 블록 49: `select  a, c1,c2, median(c14) over(partition by a), median(c13) over(partition by c1), median(c12) over(partition by c2)  from median_1 order by 1,2,3;`
  - develop: `a    c1    c2    median(c14) over (partition by a)    median(c13) over (partition by c1)    median(c12) over (partition by c2) / 1     1     1     12:00:00     1.0     2011-01-01 01:01:01.111 / 1     ` …(12행)
  - 새 답: `Error:-1118`

#### `sql/_26_features_920/issue_11087_median/answers/11087_3.answer`
- 블록 47: `select  median(c12)  from median_p order by 1;`
  - develop: `median(c12) / 2099-12-31 23:59:59.999`
  - 새 답: `Error:-1118`
- 블록 50: `select  median(a),  median(c1), median(c2), median(c3), median(c4), median(c5), median(c6), median(c7), median(c8), median(c9), median(c10), median(c11), median(c12), median(c13), median(c14)  from median_p order by 1,2,`
  - develop: `median(a)    median(c1)    median(c2)    median(c3)    median(c4)    median(c5)    median(c6)    median(c7)    median(c8)    median(c9)    median(c10)    median(c11)    median(c12)    median(c13)    m`
  - 새 답: `Error:-1118`
- 블록 64: `select  a, median(c12) over(partition by a)  from median_p order by 1,2;`
  - develop: `a    median(c12) over (partition by a) / 1     2055-07-02 12:30:30.555 / 1     2055-07-02 12:30:30.555` …(31행)
  - 새 답: `Error:-1118`
- 블록 68: `select  a, c1,c2, median(c14) over(partition by a), median(c13) over(partition by c1), median(c12) over(partition by c2)  from median_p order by 1,2;`
  - develop: `a    c1    c2    median(c14) over (partition by a)    median(c13) over (partition by c1)    median(c12) over (partition by c2) / 1     1     1     12:00:00     1.0     2011-01-01 01:01:01.111 / 1     ` …(31행)
  - 새 답: `Error:-1118`

#### `sql/_26_features_920/issue_11087_median/answers/11743.answer`
- 블록 10: `select median(i), median(a), median(b), median(c), median(c) from x;`
  - develop: `median(i)    median(a)    median(b)    median(c)    median(c) / 5.0     5.0     5.0     2013-10-05 00:00:00.0     2013-10-05 00:00:00.0`
  - 새 답: `Error:-1118`
- 블록 12: `select median(i), median(a), median(b), median(c), median(c) from x;`
  - develop: `median(i)    median(a)    median(b)    median(c)    median(c) / 6.0     6.0     6.0     2013-10-06 00:00:00.0     2013-10-06 00:00:00.0`
  - 새 답: `Error:-1118`

#### `sql/_27_banana_qa/issue_11088_percentile_cont/_01_aggregate_function/answers/_00_from_dev.answer` — 문장 수(213)와 블록 수(211)가 달라 문장은 답의 열 머리로 적는다
- 블록 27 (열 머리): `a    percentile_cont( cast(0.5 as double)) within group (order by c12) over (partition by a)`
  - develop: `a    percentile_cont( cast(0.5 as double)) within group (order by c12) over (partition by a) / 1     2055-07-02 12:30:30.555 / 1     2055-07-02 12:30:30.555` …(12행)
  - 새 답: `Error:-1118`
- 블록 72 (열 머리): `a    percentile_cont( cast(0.5 as double)) within group (order by c12)`
  - develop: `a    percentile_cont( cast(0.5 as double)) within group (order by c12) / 1     2055-07-02 12:30:30.555 / 2     2012-02-02 02:02:02.222` …(4행)
  - 새 답: `Error:-1118`
- 블록 120 (열 머리): `a    percentile_cont( cast(0.2 as double)) within group (order by c12) over (partition by a)`
  - develop: `a    percentile_cont( cast(0.2 as double)) within group (order by c12) over (partition by a) / 1     2028-10-19 10:24:48.888 / 1     2028-10-19 10:24:48.888` …(16행)
  - 새 답: `Error:-1118`
- 블록 138 (열 머리): `a    percentile_cont( cast(0.2 as double)) within group (order by c12)`
  - develop: `a    percentile_cont( cast(0.2 as double)) within group (order by c12) / 1     2028-10-19 10:24:48.888 / 2     2012-02-02 02:02:02.222` …(5행)
  - 새 답: `Error:-1118`
- 블록 155 (열 머리): `a    percentile_cont( cast(a/5.0 as double)) within group (order by c12) over (partition by a)`
  - develop: `a    percentile_cont( cast(a/5.0 as double)) within group (order by c12) over (partition by a) / 1     2028-10-19 10:24:48.888 / 1     2028-10-19 10:24:48.888` …(16행)
  - 새 답: `Error:-1118`
- 블록 173 (열 머리): `a    percentile_cont( cast(a/5.0 as double)) within group (order by c12)`
  - develop: `a    percentile_cont( cast(a/5.0 as double)) within group (order by c12) / 1     2028-10-19 10:24:48.888 / 2     2012-02-02 02:02:02.222` …(5행)
  - 새 답: `Error:-1118`

#### `sql/_27_banana_qa/issue_11088_percentile_cont/_01_aggregate_function/answers/_08_expression.answer`
- 블록 51: `select col5, percentile_cont(0.3) within group (order by to_char(col4, 'HH24:MI:SS.FF DD/MM/YYYY')) p_cont from p_cont_v group by col5 having max(col1)<20 order by 1, 2;`
  - develop: `col5    p_cont / 20     1990-10-11 11:23:34.123 / 30     1992-05-16 18:35:34.123` …(9행)
  - 새 답: `Error:-1118`

#### `sql/_27_banana_qa/issue_11089_percentile_disc/_01_aggregate_function/answers/_00_from_dev.answer` — 문장 수(213)와 블록 수(211)가 달라 문장은 답의 열 머리로 적는다
- 블록 27 (열 머리): `a    percentile_disc( cast(0.5 as double)) within group (order by c12) over (partition by a)`
  - develop: `a    percentile_disc( cast(0.5 as double)) within group (order by c12) over (partition by a) / 1     2011-01-01 01:01:01.111 / 1     2011-01-01 01:01:01.111` …(12행)
  - 새 답: `Error:-1118`
- 블록 72 (열 머리): `a    percentile_disc( cast(0.5 as double)) within group (order by c12)`
  - develop: `a    percentile_disc( cast(0.5 as double)) within group (order by c12) / 1     2011-01-01 01:01:01.111 / 2     2012-02-02 02:02:02.222` …(4행)
  - 새 답: `Error:-1118`
- 블록 120 (열 머리): `a    percentile_disc( cast(0.2 as double)) within group (order by c12) over (partition by a)`
  - develop: `a    percentile_disc( cast(0.2 as double)) within group (order by c12) over (partition by a) / 1     2011-01-01 01:01:01.111 / 1     2011-01-01 01:01:01.111` …(16행)
  - 새 답: `Error:-1118`
- 블록 138 (열 머리): `a    percentile_disc( cast(0.2 as double)) within group (order by c12)`
  - develop: `a    percentile_disc( cast(0.2 as double)) within group (order by c12) / 1     2011-01-01 01:01:01.111 / 2     2012-02-02 02:02:02.222` …(5행)
  - 새 답: `Error:-1118`
- 블록 155 (열 머리): `a    percentile_disc( cast(a/5.0 as double)) within group (order by c12) over (partition by a)`
  - develop: `a    percentile_disc( cast(a/5.0 as double)) within group (order by c12) over (partition by a) / 1     2011-01-01 01:01:01.111 / 1     2011-01-01 01:01:01.111` …(16행)
  - 새 답: `Error:-1118`
- 블록 173 (열 머리): `a    percentile_disc( cast(a/5.0 as double)) within group (order by c12)`
  - develop: `a    percentile_disc( cast(a/5.0 as double)) within group (order by c12) / 1     2011-01-01 01:01:01.111 / 2     2012-02-02 02:02:02.222` …(5행)
  - 새 답: `Error:-1118`

#### `sql/_27_banana_qa/issue_11089_percentile_disc/_01_aggregate_function/answers/_08_expression.answer`
- 블록 51: `select col5, percentile_disc(0.3) within group (order by to_char(col4, 'HH24:MI:SS.FF DD/MM/YYYY')) p_disc from p_disc_v group by col5 having max(col1)<20 order by 1, 2;`
  - develop: `col5    p_disc / 20     1990-10-11 11:23:34.123 / 30     1991-10-10 11:23:34.123` …(9행)
  - 새 답: `Error:-1118`


### 1.2 문장이 읽는 세션변수는 문장 동안 한 타입 (#366 U3, 스펙 변경 §9) — `bug_bts_6605`, 1 블록

- 케이스는 `set @a = 0;`(INTEGER) 뒤에 `@a := (@a + (a + a) / (a * 2)) * (c * 10) + 1` 을 계산한다. `c` 는 FLOAT 컬럼이라 대입식의 타입은 FLOAT 이다. 이 문장은 `@a` 를 읽기도 한다.
- **develop**: 행마다 값으로 타입을 정해, 행별 값(`5.0`, `19.0`, `41.0`, `43.0`)을 냈다.
- **이 PR**: 문장이 읽는 세션변수의 타입은 게이트가 실행 전에 정한다. 실행 시작 값의 타입과 문장 안 대입식의 타입을 합친다. CAST 없이 다른 타입(INTEGER 와 FLOAT)이 되면 실행 전 -1384 `Session variable @a would hold integer and float within a statement that reads it; cast the value to one type.` 이고, 변수 값은 그대로 남는다. 사용자 결정 U3(2026-09-26)이다: "행단위 타입평가 코드를 아예 없애기 위해 … gate 에서 세션변수에 다른타입을 넣으려 하면 에러".
- 같은 파일의 나머지 문장은 답이 바뀌지 않았다.

#### `sql/_13_issues/_12_1h/answers/bug_bts_6605.answer`
- 블록 37: `select /*+ recompile */ a, @a := (@a + (a + a) / (a * 2)) * (c * 10) + 1 from (select * from t order by a desc) order by a desc;`
  - develop: `a    @a := (@a+(a+a)/(a*2))*(c*10)+1 / 4     5.0 / 3     19.0` …(4행)
  - 새 답: `Error:-1384`

### 1.3 같은 prepare 를 다시 실행해도 앞 실행의 바인드가 상수를 바꾸지 않는다 (#352, 스펙 변경 §3) — `cbrd_24598`, 2 블록 + 케이스 주석

- **문장**:
  ```sql
  prepare q from 'select decode (?, '''', c, NULL, c, -1) from …';
  execute q using 'A';
  execute q using 1;
  execute q using 'A';   -- 블록 3
  prepare p from 'select decode (?, '''', c, NULL, c, ''Z'') from table ({''X''}) …';
  execute p using 1;
  execute p using 'A';   -- 블록 5
  ```
- **develop**: 세 번째 `execute q using 'A'` 와 다섯 번째 `execute p using 'A'` 가 -181 이었다. 원인은 이렇다.
  - 앞 실행의 INTEGER 바인드가 캐시된 XASL 의 리터럴 `''` 를 제자리에서 DOUBLE 로 바꿨다(S-09).
  - 그 바뀐 리터럴이 힙 전환으로 다음 실행까지 남았다(S-39).
  - 그래서 다음 실행의 `'A'` 가 DOUBLE 로 변환되지 못했다.
  - 케이스는 이 자리에 "error : temporary / known bug" 라고 적어 두었다.
- **이 PR**: 제자리 coerce 가 없다. 게이트가 상수를 실행마다 자기 값으로 한 번 변환하고 리터럴 `''` 는 그대로 남는다. 그래서 두 실행이 첫 실행과 같이 답한다: 블록 3 은 `-1`, 블록 5 는 `Z`.
- `.sql` 의 바뀐 곳은 이 두 문장 위의 주석 두 곳뿐이다. "known bug" 를 원인 설명으로 바꿨고, 문장은 그대로다.
- 이 케이스에는 `.answer_cci` 가 없다.

### 1.4 CCI 답 10건 (#345, #335·#366 인계)

- 위 1.1·1.2 의 10 케이스는 `sql_by_cci` 스위트용 `.answer_cci` 도 가진다. 이 스위트는 PR CI 가 돌리지 않는다.
- 바뀐 답 블록 32개는 모두 오류 한 줄(`Error:-1118` / `Error:-1384`)이다. CCI 답의 오류 블록 형식은 JDBC 답과 같다.
- 그래서 같은 블록 위치로 옮겼다. 각 블록이 같은 문장인지는 두 파일의 열 머리 줄이 같은지로 확인했다. 숫자 표기가 다른 결과 블록(CCI 는 DOUBLE 을 소수 16자리로 찍는다)은 건드리지 않았다.
- 파일: `bug_bts_6605` · `bug_bts_13916` · `11087` · `11087_1` · `11087_3` · `11743` · `issue_11088_percentile_cont/_01_aggregate_function/_00_from_dev`·`_08_expression` · `issue_11089_percentile_disc/_01_aggregate_function/_00_from_dev`·`_08_expression`.

## 2. 새로 더한 케이스 20개 (`sql/_07_misc/domain_*`)

- 이 PR 이 바꾼 실행 경로마다 케이스를 더했다. 게이트, fetch, 비교, 리스트·집계, 인덱스 키, 해시 스캔, collation, PL/CSQL 이 그 경로다.
- 답은 **develop 과 같은 답**이 원칙이다. 각 케이스를 더한 티켓이 develop 설치본으로 같은 문장을 돌려 답을 맞췄다(케이스 커밋 메시지와 티켓 해소 기록).
- 스펙 변경 자리만 새 답이고, 해당하는 절 이름과 develop 답을 함께 적었다.
- 괄호 안 숫자는 케이스의 문장 수다.
- 케이스 둘(`branch_collations`, `list_aggregate_probes`)이 남기던 세션변수는 #357 이 케이스 안에서 지우게 고쳤다. 같은 CQT 연결을 쓰는 뒤 케이스가 누수로 실패하던 문제다.

### 2.1 `domain_fetch_gate/` — 게이트 결정과 fetch

- **`fetch_gate_probes`** (78, #340·#366)
  - 고정하는 것: fetch 가 열린 도메인을 모두 게이트에서 읽고 값에서 정하지 않는다(S-01~S-06, S-11).
  - 절: [CAST] 집합 연산의 `CAST(? AS uncertain)`·사용자 CAST · [NOVAL] NULL 바인드(값 없는 결정) · [S5] 세션변수 · [ADDTIME] 세션변수 문자열의 게이트 분류 · [TOPN] 열린 정렬 키 · [GCONCAT] CHAR 바인드의 GROUP_CONCAT · [PCT] percentile 비율과 스칼라 부분질의 · [MYSQL] `compat_mode=mysql`.
  - 답: develop 과 같다. **[S5] 만 새 답**이다: 문장 안에서 세션변수에 다른 타입을 넣으면 실행 전 -1384 다(#366 U3). develop 은 행 값으로 타입을 바꿨다.
- **`fetch_gate_bind_reads`** (54, #340 → #345)
  - #340 의 카운터 판독 케이스 `fetch_gate_counters` 에서 카운터 줄 45개와 그 답 블록 45개를 뺀 것이다. 카운터는 이 PR 에서 지웠다(D-368-09).
  - 절: [CH-concat] 파생 테이블을 거친 `concat(?, ?)` · [CH-plus] 문자열 `? + ?` · [CH-strcol] `s + ?` · [CV]/[CV-char] `ifnull(s|c, ?)` · [GC] `group_concat(?)`·`max(concat(?, ?))` · [SV-str]/[SV-fmt]/[SV-char]/[S5f] 문자열·포맷·CHAR 세션변수 · [N-nullbind] 값 없는 결정 · [N-slot] 슬롯 읽기 · [N-union] `CAST(? AS uncertain)` · [N-topn] 열린 정렬 키 · [N-sv-same]/[N-sv-change] 타입을 지키는/바꾸는 세션변수 · [N-addtime] · [N-gconcat] · [N-pct].
  - 답: develop 과 같다. **[N-sv-change] 만 새 답**(-1384, #366)이다.
- **`session_variable_types`** (53, #366)
  - 고정하는 것: 문장이 읽는 세션변수는 문장 동안 한 타입이다.
  - 절: [U1] 대입만/읽기만 하는 문장 · [U2] 행에서 NULL 인 열도 열의 타입을 준다 · [U3] CAST 없는 다른 타입은 실행 전 오류이고 변수 값은 그대로 · [U4] 같은 codeset·collation 문자열은 한 타입, collation 이 다르면 다른 타입 · [READ] 읽기 위의 비교·IN·정렬 키·GROUP BY·분석 · [CLASS] 문자열의 부류는 실행 시작 값의 것.
  - 답: **[U3]·[U4] 의 다른 타입 문장(-1384)과 [CLASS] 가 새 답**(스펙 변경 §9, D-366-06)이다. 나머지는 develop 과 같다.
- **`constant_errors`** (154, #367·#368)
  - 고정하는 것: 상수(리터럴, 바인드 위 상수 부분트리, 컴파일러가 상수 피연산자에 씌운 CAST)의 계산·변환 실패는 행과 무관하게 실행 전 오류다(사용자 결정 (가), 2026-09-27). 바인드는 `concat(?, '')` 로 감싸 서버가 계산·변환하게 했다.
  - 절:
    - [EVAL] 계산 실패(D-367-01) · [CMP] 비교로 변환되지 않는 항의 상수 쪽(D-367-02, -181) · [INTERP] DOUBLE·DATETIME·TIME 어느 것도 받지 않는 MEDIAN/PERCENTILE 값(D-367-04, -1118).
    - 각 [...-ROWS] 는 같은 문장을 행 위에서 되풀이한다.
    - [GUARD]·[GUARD-NESTED] 는 상수 조건이 모든 행을 그 상수에서 떼어 놓는 자리다: CASE·IF·DECODE 의 안 쓰이는 가지, COALESCE·NVL2 의 상수 첫 피연산자, AND/OR 의 상수 앞 항, 중첩 조건(D-367-07, D-368-03).
    - [VOLATILE] 세션변수 조건은 상수 조건이 아니다.
    - [KEEP] 행이 값을 변환·비교하는 자리(대입, LEAD/LAG 기본값, FIELD 는 rank 로 답)는 develop 답이다(D-367-05).
  - 답: **[EVAL]·[CMP]·[INTERP] 의 행 없는 문장과 [VOLATILE] 이 새 답**(스펙 변경 §10)이다. 이 문장들은 행 0개, 안 쓰이는 CASE 가지, 단락되는 AND 아래에서도 실행 전 오류를 낸다. develop 은 그 상수를 계산하는 첫 행에서만 오류를 냈다. [...-ROWS]·[GUARD]·[GUARD-NESTED]·[KEEP] 은 develop 과 같다.
- **`common_value_constants`** (109, #364)
  - 고정하는 것: 상수 부분트리(`CAST(? AS T)`, 그 안의 게이트 의존 노드) 위의 공통값 노드(COALESCE·NVL·IFNULL·NVL2·NULLIF·LEAST·GREATEST)는 게이트가 평가한 부분트리의 값으로 정한다. develop 이 피연산자 값을 접던 것과 같은 방식이다.
  - 절: [CAST] NULL CAST 피연산자 · [NESTED] 중첩·사슬 · [CONSUMER] 그 결정을 기다리는 노드·항·키·집계 · [SAME] 결과 NULL·산술 NULL·NULL 리터럴·맨 슬롯·값 있는 상수 · [ROW] 행이 주는 피연산자 · [PX] 병렬 힙 스캔(131072행).
  - 답: develop 과 같다. **[ROW] 만 새 답**이다: 행이 주는 피연산자는 모든 행에서 계획 도메인이다. develop 은 첫 행 값으로 노드 타입을 정해 답이 힙 순서에 따라 달랐다(D-340-01, D-364-05, 스펙 변경 §8).
- **`precast_plan`** (57, #368 D-368-02·06)
  - 고정하는 것: 산술 사전 캐스트, SUM/AVG 누적, ORDERBY_NUM 상한이 행 전에 계획된다.
  - 절: 컴파일된 노드(숫자 옆 문자열, 변환되지 않는 문자열, NULL 피연산자) · 날짜 옆 숫자·문자열 · ENUM 의 이름/서수 · 게이트가 타입을 정하는 바인드 · SUM/AVG 아래 문자열 세션변수 · ORDERBY_NUM 상한과 LIMIT offset+count · 문자열 컬럼을 숫자에 더하는 필터 인덱스 스트림. `return_null_on_function_errors` 켜기/끄기를 모두 본다.
  - 답: 전부 develop 과 같다.
- **`scope_once_conversion`** (41, #368 D-368-01·07)
  - 고정하는 것: 상관 값은 외부 행마다 한 번, 상수 피연산자는 실행마다 한 번 변환한다.
  - 절: INT/문자열 외부 값 대 BIGINT 내부 · 외부 문자열을 바꾸는 산술 노드 · 상관 부분질의 · 세 겹 중첩 스캔 · 외부 NULL · 변환되지 않는 외부 문자열 · 산술·SUM/AVG 아래 문자열 바인드 · 변환되지 않는 바인드(`return_null_on_function_errors` 두 값) · 상관 부분질의 집계 아래 상관 값.
  - 답: 전부 develop 과 같다.
- **`to_number_domain`** (24, #368 리뷰 ② R2-07)
  - 고정하는 것: TO_NUMBER 는 노드 도메인을 컴파일된 채로 두고, 값이 precision·scale 을 가진다. develop 은 값마다 노드 도메인에 썼다.
  - 절: 상수 포맷 · 행마다 다른 포맷 · 바인드 포맷 · ORDER BY·SUM·MAX 아래 TO_NUMBER · TO_NUMBER 전에 prepare 하고 뒤에 실행한 NUMERIC CAST.
  - 답: 전부 develop 과 같다.
- **`alter_filter_index_recompile`** (31, #368 D-368-05, develop 결함 #359)
  - 고정하는 것: 필터 인덱스 술어만 읽는 컬럼을 `ALTER … MODIFY` 로 바꾸면, 술어를 새 타입으로 다시 컴파일하고 인덱스를 재구축한다. develop 도 키 컬럼을 바꿀 때는 이렇게 한다.
  - 절: 변경 전·후와 새 행 뒤의 필터 인덱스가 담는 행, 카탈로그 `db_index.filter_expression` · 술어가 읽는 키 컬럼 · 컬럼 위 함수 인덱스.
  - 답: 행 답은 develop 과 같다. **`filter_expression` 은 새 답**이다. develop 은 옛 모양 `[dba.fr_t].c+1=1` 을 남겼고, 새 답은 ` cast([dba.fr_t].c as double)+ cast(1 as double)=1` 이다(스펙 변경 §11).

### 2.2 `domain_list_aggregate/` — 리스트·정렬·그룹·집계·분석

- **`list_aggregate_probes`** (180, #341·#357·#366·#367)
  - 고정하는 것: 리스트 파일은 계획 도메인으로 열고, 정렬·GROUP BY 위치·리스트 스캔은 계획을 읽는다. 집계·분석은 첫 행 전에 계획으로 셋업한다.
  - 절: [LIST] 파생 테이블·집합 연산·정렬의 바인드 열 · [SORT] ORDER BY/DISTINCT · [GROUP] GROUP BY 키와 집계 · [AGG] BUILDVALUE 집계 · [ANALYTIC] · [LSCAN] 리스트 스캔 · [HJOIN] 해시 조인 · [GBNUM]/[GBNUM2] GROUPBY_NUM · [NOVAL] NULL 바인드 · [SV] 문장 안에서 타입이 바뀌는 세션변수 · [CLASS] 첫 읽기 전에 내용이 부류를 바꾸는 세션변수 위 MEDIAN · [NULLSTART] 시작 때 NULL 인 세션변수 위 집계 · [NUMDISC] 여러 precision NUMERIC 의 PERCENTILE_DISC/MEDIAN · [LISTS] · [LEADLAG] NULL 피연산자 위 LEAD/LAG · [UNCLASS] 어느 부류도 받지 않는 바인드·리터럴 위 MEDIAN · [SETOP] 집합 연산·CTE 열.
  - 답: develop 과 같다. 새 답은 넷이다.
    - [SETOP]: 가지의 바인드 타입이 다른 집합 연산·CTE 열은 행과 무관하게 실행 전 -456 이다. develop 은 두 가지 모두 행이 있을 때만 거부했다(D-341-14, 사용자 결정 (나), 스펙 변경 §5).
    - [SV]: -1384(#366).
    - [CLASS]: 문자열 부류는 실행 시작 값의 것이다(#366). develop 은 첫 값의 것을 썼다.
    - [UNCLASS]: 행이 없어도 -1118 이다(#367). develop 은 첫 행에서 냈다.
- **`analytic_interpolation_keys`** (89, #362·#366·#344)
  - 고정하는 것: 분석 MEDIAN/PERCENTILE 의 문자열 피연산자 정렬 키 부류(DOUBLE·DATETIME·TIME)를 셋업이 정렬 전에 정한다. develop 은 정렬이 비교한 첫 값 쌍으로 정했다.
  - 절: [DERIVED] 파생 테이블 열로 본 문자열 바인드 · [SETOP] 집합 연산의 문자열 열 · [DIRECT] 직접 준 바인드·리터럴(정렬 키 없음) · [SESSION]/[SESSION_CHANGED] 세션변수 · [COMPILED] 문자열 컬럼 · [SHARED] 정렬을 공유하는 다른 함수의 문자열 키.
  - 답: develop 과 같다. 새 답은 둘이다.
    - [SHARED](D-362-01, 사용자 결정 (가), 스펙 변경 §7): 상수나 숫자 위 MEDIAN 과 정렬을 공유하는 다른 함수의 문자열 ORDER BY 키는 자기 도메인으로 비교한다. develop 은 첫 값의 부류로 비교해 `'b'` 는 오류, `'10'`·`'9'` 는 숫자로 비교했다.
    - [SETOP] 의 첫 값 `'01:00:00'`(D-335-10·D-344-02): 집합 연산의 문자열 열은 타입으로 DOUBLE 이라 날짜·시간 문자열은 -1118 이다. develop 은 첫 값으로 열을 TIME 으로 정하고 `'abc'` 에서 실패했다.

### 2.3 `domain_compare/` — 비교

- **`compare_element_probes`** (51, #352)
  - 고정하는 것: IN/SOME/ALL 원소 비교는 행 전에 정한다. 리스트 열·스칼라는 비교 기록, 상수 집합은 게이트가 원소마다 결정·변환 1회, 행이 계산하는 컬렉션은 원소 키 표를 쓴다(D-352-03·07).
  - 절: [LITERAL] · [BIND] · [FUNCTION] 집합 함수 · [ATTRIBUTE] 집합 속성 · [LIST] 부분질의 리스트 열.
  - 답: 전부 develop 과 같다.
- **`compare_outside_terms`** (140, #354)
  - 고정하는 것: 술어 항 밖의 비교도 행 전에 정한다.
  - 절: [COLLECTION] 이종 컬렉션의 원소 순서·비교·산술·CAST · [JSON] 다른 JSON 타입 스칼라 · [ARITH] FIELD·NULLIF·LEAST·GREATEST · [LIMIT] 행 수 대 0, 두 ORDERBY_NUM 항의 상한 · [PARTITION] 다른 타입 상수의 pruning · [MERGE] 머지 조인 · [STREAM] 필터 인덱스 술어·함수 인덱스 식.
  - 답: 전부 develop 과 같다.

### 2.4 `domain_index_key/` — 인덱스 검색 키

- **`index_key_probes`** (203, #342)
  - 고정하는 것: 검색 키는 행 전에 만든 키 계획을 따른다. 인덱스 스캔마다 `USING INDEX NONE` 의 같은 질의와 짝을 지었다.
  - 절:
    - [SINGLE] 단일 컬럼 키: INT·BIGINT(double 정밀도 너머)·NUMERIC·문자열(CHAR 인덱스와 VARCHAR 값, 인덱스에 없는 collation)·날짜·시간.
    - [MULTI] 복합 키의 strict 변환 또는 값 유지 · [DESC] 내림차순 컬럼 · [LIST] 타입이 다른 키 리스트·range 리스트의 정렬·중복 제거·병합.
    - [CORRELATED] 조인·상관 키 · [ISS] 인덱스 스킵 스캔 · [MRO] 다중 범위 최적화.
  - 답: 전부 develop 과 같다.
- **`index_key_domains`** (91, #342)
  - 고정하는 것: 인덱스 스캔이 싣는 B-tree 키 도메인이 스캔 open 때 B-tree 루트 헤더와 맞는다.
  - 절: [OBJECT] 타입 있는·일반 OBJECT 컬럼 · [PARTITION] range·hash 파티션 · [HIERARCHY] 하위 클래스까지 훑는 상위 클래스 인덱스 · [KINDS] PK·unique·함수·내림차순 인덱스. 끝의 DROP TABLE 은 권한 카탈로그의 단일 컬럼 OBJECT 인덱스로 grant 를 지운다.
  - 답: 전부 develop 과 같다.

### 2.5 `domain_hash_scan/`, `domain_collation_gate/`, `domain_plcsql_slot/`, `domain_conversion_contract/`

- **`hash_scan_build_keys`** (229, #356)
  - 고정하는 것: 해시 리스트 스캔은 빌드 키마다 복사·변환을 첫 빌드 행 전에 정한다. 각 질의의 trace 가 해시 리스트 스캔임을 보인다.
  - 절: [FIXED] 키 타입 쌍마다 한 셀 · [BIND] 바인드 위 키 · 외부 행마다 다시 여는 스캔 · 바인드가 collation 을 주는 프로브 키 · [SESSION VARIABLE] · [CONNECT BY] 계층 스캔 · JSON 빌드 키 · [REFUSED] 변환이 거부하는 빌드 값.
  - 답: 전부 develop 과 같다.
- **`branch_collations`** (68, #343)
  - 고정하는 것: 게이트가 모든 문자열 collation 을 정한다. 행이 고르는 가지도 포함한다.
  - 절: A 바인드·리터럴 인덱스의 ELT · B 행이 인덱스를 주는 ELT(바인드·세션변수의 다른 collation 가지) · C 병합되지 않는 collation · D 문자열 가지가 셋보다 많은 ELT · E·G 컴파일러가 가지를 맞추는 CASE·IF·DECODE · F 한 collation 가지.
  - 답: develop 과 같다. **B 만 새 답**이다(D-343-01, 사용자 결정 (다), MySQL 의 ELT 와 같음, 스펙 변경 §6). 가지 collation 을 문장 하나의 도메인으로 병합하고, 고른 값이 모두 그 도메인을 받는다. develop 은 행마다 자기 가지의 collation 을 붙였고, 첫 행의 가지가 정렬 타입을 정했다.
  - C 는 develop 시점 그대로다: 행이 병합 불가를 만나면 오류(-1150)이고, 행이 없으면 오류가 없다.
- **`collation_gate_probes`** (44, #338)
  - 고정하는 것: collation 축 탐침(#322 의 A~F).
  - 절: A 리터럴과 ENUM 형제 · B NULL·문자열 바인드 위 group_concat · C PREPARE 뒤 SET NAMES · D PREPARE 뒤 ALTER … COLLATE · E 문자셋이 섞인 다중 행 VALUES 바인드 · F 환경.
  - 답: 전부 develop 과 같다. B 의 NULL 바인드는 develop optdebug 가 assert 로 멈추는 자리다. develop release 와 이 PR 의 답은 NULL 이다(스펙 변경 §11).
- **`plcsql_slot_gate`** (166줄, 답 블록 26, #339)
  - 고정하는 것: PL/CSQL 정적 SQL 의 `?` 는 JDBC `?` 와 같은 슬롯이다(D-336-B). 게이트는 선언 타입이 아니라 PL 이 보낸 값의 도메인을 쓴다. PL 은 CHAR 를 VARCHAR 로, TIMESTAMP 를 DATETIME 으로, NUMERIC 을 값의 자릿수로, NULL 은 타입 없이 보낸다.
  - 절: A 맨 `?` 의 도메인 · B NULL · C 슬롯 위 산술·함수·공통값 · D 컬럼 옆 비교·대입(develop 클라이언트 캐스트) · E 집계·집합 연산 · F PL 식 안의 내장 함수 · G 최상위 LIMIT 슬롯. 파생 테이블 안 슬롯 LIMIT 과 슬롯 FIELD 인자는 develop 결함 #351 이라 빠졌다.
  - 답: 전부 develop 과 같다. 줄 수보다 답 블록이 적은 것은 PL/CSQL 프로시저 본문의 여러 줄이 문장 하나(블록 하나)이기 때문이다.
- **`conversion_contract`** (145, #330 D-328-02~07, #335)
  - 고정하는 것: 변환 셀 계약.
  - 절: R1 VARCHAR→CHAR(3) 절단(`allow_truncated_string` 두 값) · R3 실수·문자열 피연산자의 날짜 산술(BIGINT·반올림) · R4 KEEP 뒤 INT 대 TIME 동등 비교(순차 대 인덱스) · R5 값 내용에 따른 결과 · R6 오류를 내는 파서(날짜 키, NUMERIC 오버플로)의 KEEP 경로.
  - 답: develop 과 같다. **R5 의 두 문장만 새 답**이다(D-335-10). `SELECT median(s), typeof(median(s)) FROM tm` 을 `s varchar(30)` 에 날짜 문자열(`'2024-01-01 10:00:00'`…)·시간 문자열(`'01:00:00'`…)을 넣고 돌린다. develop 은 각각 `datetime`·`time` 으로 답했고, 새 답은 -1118 이다. 숫자 문자열(`'1.5'`…)의 MEDIAN 은 develop 과 같은 DOUBLE 이다.

## 3. 검증

- 이 브랜치의 tree(`5ca2aa2d3`)로 로컬 컨테이너 CTP 를 돌렸다. 엔진은 PR 머리 `c3b4dad4b` 다.
  - optdebug: sql 17482/17482 · medium 975/975(`sql-20260928T072344Z-3311400`).
  - release: sql 17482/17482 · medium 975/975(`sql-20260928T072542Z-3391397`).
  - 둘 다 고정 배치였고 코어는 0이다.
  - upstream shell 수정 뒤 머리 `4abc28ea1` 에서도 같다(게이트 E): optdebug `sql-20260928T094530Z-3879671`, release `sql-20260928T094551Z-3912725`, 둘 다 17482/17482 · medium 975/975, 코어 0.
- develop 과의 A/B 는 #344 에서 했다. 캠페인 케이스 14개와 답이 바뀐 upstream 케이스 16개를 develop·캠페인의 optdebug·release 로 csql -S 에서 돌렸고(124작업), develop 과 다른 자리는 위의 스펙 변경뿐이었다(스펙 변경 문서 머리). 그 뒤 게이트마다 같은 문장의 출력이 기준 출력과 같은지 확인했다: 이 PR 머리의 optdebug·release 도 128작업 IDENTICAL 이다.
- PR CI(`/run all`, gha-ci 런 [36392174174](https://github.com/CUBRID/cubrid/actions/runs/36392174174))는 이 `tc/pr-8022` 로 sql·medium·shell 을 돈다.

## 4. private-ex `tc/pr-8022` — shell 케이스 5개, 파일 9개 (#345 게이트 E)

PR CI(`/run all`, [36392174174](https://github.com/CUBRID/cubrid/actions/runs/36392174174), debug)의 shell 스위트가 develop 이 통과하는 11 케이스를 실패했다. 캠페인 탓 6 케이스는 엔진에서 고쳤다(`4abc28ea1`: `cbrd_24905`·`cubrid_262`·`bug_bts_14584`·`issue_10753_charset_conversion`·`cubrid_typesupport`·`cbrd_25035`, 그리고 `cbrd_20149_ddl`·`_xasl` 의 sha1·SQL_ID 줄 — 스펙 변경 문서 §10·§14, D-345-04~07). 나머지는 승인된 변경의 결과라 케이스를 고쳤다. 커밋은 둘이다: `6542a06f6`(아래 4.1·4.2), `fb242a0ed`(4.3).

### 4.1 `shell/_10_plcsql/cbrd_25749/cases/test3.answer` — 4줄 (#341 S-23, 스펙 변경 §11)

- 문장(`;trace on`, tbl 은 4행):
  - 3.2 `select (select max(pl_csql_int(col1)) from tbl) from tbl order by col2;` — `pl_csql_int` 는 NOT DETERMINISTIC 이고, 부질의는 비상관이다.
  - 3.4 `select (select max(pl_csql_int2(col1)) from tbl) from tbl order by col2;` — `pl_csql_int2` 는 DETERMINISTIC 이다.
- 바뀐 줄: 두 문장마다 트레이스의 `FUNC (time:?, fetch:?, ioread:?, calls: N)` 두 줄(바깥 SELECT 와 SUBQUERY 의 SELECT), 88·93·171·176 행이다.
- develop 답은 `calls: 5` 다. 부질의의 `max(pl(col1))` 을 4행에 대해 누적하기 전에 `qexec_resolve_domains_for_aggregation` 이 첫 행의 인자를 한 번 더 계산해 도메인을 정했다. develop 도 BENCHMARK 함수에서만 이 계산을 피한다.
- 새 답은 `calls: 4` 다. 집계 도메인은 게이트가 계획에서 첫 행 전에 셋업하고(#341, 감사표 S-23), 인자는 행마다 한 번 계산한다.
- 질의 결과(3,3,3,3)와 SUBQUERY_CACHE 계획 줄은 그대로다.

### 4.2 `shell/_05_addition/bug_xdbms_sus18/cases/test3.java` — 세 번째 실행 (#367 (가), 스펙 변경 §10)

- 문장(JDBC prepare 한 번, 네 번 실행): `select x.a from xoo x where x.a = to_number(?) and x.a = ?`. xoo 는 (1, '111'), (2, '222') 두 행이고 인덱스가 없다.
- 세 번째 실행의 바인드는 ('1x', '10') 이다.
  - develop: 두 행 모두 `x.a = ?` 가 거짓이다. `to_number('1x')` 를 계산하지 않아 0행이고 오류가 없다.
  - 새 답: `to_number(?)` 는 상수 부분트리다. 게이트가 행 전에 계산해 -834(`There are some mismatches between source string "1x" and format string "default" given in to_number().`)를 낸다. 행 값이 막는 단락도 예외가 아니다(사용자 결정 (가)).
- 바꾼 곳: `rs = stmt.executeQuery();` 한 줄을 try/catch 로 감쌌다.
  - -834 면 아무것도 출력하지 않는다. 오류가 나지 않으면 `3 no error` 를 출력해 NOK 가 된다. 새 동작을 고정하기 위해서다.
  - 다른 오류는 그대로 던져 바깥 catch 가 스택을 출력한다(NOK).
- 케이스의 판정(`output` 이 비어 있으면 OK)과 첫째·둘째·넷째 실행은 그대로다. 넷째 실행은 실패한 실행 뒤에도 같은 prepare 가 동작하는지를 본다(원 결함 XDBMS SUS18).

### 4.3 `cbrd_20149_*` plandump 의 메모리 줄 — 파일 7개 (#342)

- 케이스는 `cubrid plandump` 출력을 답과 비교한다. `format_plandump` 는 메모리 줄의 숫자를 자리마다 0 으로 가린다(`sed '/memory/I s/[0-9*]/0/g'`). 그래서 10 KB 를 넘으면 `0.00 KB` 가 `00.00 KB` 가 된다.
- 엔진 PR 의 XASL 스트림은 인덱스 스캔마다 B-tree 키 도메인 8바이트를 싣는다(`xasl_to_stream.c`, 서버가 로드 때 인덱스 키 계획을 여기서 도출한다, #342).
- 실측(stand-alone, 같은 문장, develop `e1c3db198` 대 `4abc28ea1`, 캐시가 계획마다 잡는 크기 `xcache_entry_get_entrysize`): 달라진 것은 스트림 길이뿐이다(구조체 크기·SQL 텍스트 길이 같음).
  - `cbrd_20149_ddl` test4 와 `_xasl` 다섯 파일의 덤프에 남은 두 계획(DROP TABLE 이 내부에서 실행하는 `_db_auth` 조회·삭제, 인덱스 스캔 각 2개): 5,331 → 5,347 바이트, 4,980 → 4,996 바이트. develop 의 합이 10,240 바이트 바로 아래(10,208~10,239)라 32바이트가 10 KB 를 넘겼다.
  - `cbrd_20149_filter`(계획 21개, `max_plan_cache_clones=10`): 인덱스 스캔이 있는 조회문 14개가 8바이트씩 크다. 사용률은 클론 메모리도 세고, 클론 하나는 `XASL_NODE` 크기(1,328 → 1,344 바이트, 로드용 포인터 `domain_plan`·`limit_compare`)와 스트림 길이의 3배로 잡힌다. 합해 약 780 바이트(0.001%p 미만)이고, develop 의 사용률이 반올림 경계 0.235% 바로 아래라 0.23% 가 0.24% 가 되었다.
- 바뀐 줄:

| 파일 | 줄 | develop | 새 답 |
|---|---|---|---|
| `cbrd_20149_ddl/cases/test4.answer` (`drop table if exists tx, ty;` 뒤의 plandump — 권한 내부 문장 2개가 캐시에 있다) | 20·22 `Current Memory (cache)`·`Total Memory` | `0.00 KB` | `00.00 KB` |
| `cbrd_20149_xasl/cases/bug_2062.sql.answer`·`bug_2737.sql.answer`·`bug_bts_12782.sql.answer`·`bug_bts_14236.sql.answer`·`bug_bts_17953.sql.answer` (각 SQL 파일을 실행한 뒤의 plandump) | 20·22 같은 두 줄 | `0.00 KB` | `00.00 KB` |
| `cbrd_20149_filter/cases/test.answer` (필터 인덱스 문장 뒤의 plandump, 캐시 항목 21개) | 24 `Usage Percent` | `0.23%` | `0.24%` |

- 다른 줄은 그대로다. sha1·SQL_ID·`sql hash text` 는 develop 과 같다(엔진 PR 이 캐시 키 접미사 `;host_var_cnt=` 를 없앴다, D-345-04). `Current Memory (clone)`·`Max Plan Size`·항목 수·통계도 같다.
- 같은 케이스의 나머지 answer 파일은 develop 에서도 이미 10 KB 를 넘었거나(`bug_bts_17386` 은 develop 답이 `00.00 KB`), 넘지 않아 그대로다.

### 4.4 검증

- 엔진 `4abc28ea1` optdebug 로 로컬 컨테이너 shell(`just ctp shell … PR=8022`)을 돌렸다.
  - 11 케이스 중 엔진 수정 대상 6 케이스가 통과했다. `issue_10753_charset_conversion` 은 1~13 단계가 통과했다. 14 단계 `make_locale failed` 는 로컬 러너가 로케일 컴파일을 건너뛰는 탓이다(develop `e1c3db198` 도 같은 로컬 러너에서 같다).
  - 위 5 케이스는 TC 수정(`fb242a0ed`) 뒤 다시 돌렸다: 5/5 통과, 코어 0(`shell-20260928T095810Z-4146027`). `cbrd_20149_xasl` 은 39 단계가 모두 OK 다.
- PR CI 둘째 런([36406721542](https://github.com/CUBRID/cubrid/actions/runs/36406721542), 엔진 `4abc28ea1`, 이 두 커밋 위의 `tc/pr-8022`)은 sql·medium·shell 이 모두 통과했다.
- 바뀐 줄마다의 이유는 TC PR #4258 에 인라인 리뷰로도 달았다(사용자 지시, 리뷰 5337193291, 20개). `cbrd_20149_filter` 의 사용률은 클론 메모리도 센다. 클론 하나는 `XASL_NODE` 크기(엔진 PR 이 로드용 포인터 둘을 더해 1,328 → 1,344 바이트)와 스트림 길이의 3배로 잡히므로, 스트림 증가(인덱스 스캔 1개당 8바이트)와 함께 약 780 바이트가 늘었다(stand-alone 실측, 계획 21개).
