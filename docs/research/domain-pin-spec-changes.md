# 도메인·collation 사전 확정 — 스펙 변경과 매뉴얼 명기 사항

지도: xmilex-git/workspace#312 · 티켓: #344(dpin-18) · 작성 2026-09-27
비교: develop `c63a3b993` 대 dpin `4b55eaaf9`(#367 까지). #344 의 커밋 A(`949578827`)는 서식만 바꾸고, 커밋 B(`e4f86135a`, D-344-02)는 §3a 의 한 자리를 develop 오류 코드로 되돌린다.
실측: csql -S(SA) — 캠페인 TC 14개, 답이 바뀐 upstream TC 16개, 추가 문장 1파일을 develop·dpin 의 optdebug·release 로 돌렸다(`.git_ignored_dir/scratch/312-344/probe/sc`, 124작업). develop 과 다른 곳은 아래 목록의 자리뿐이다. optdebug 와 release 는 같은 답이고, 달랐던 것은 develop optdebug 가 assert 로 멈춘 세 파일(§11)과 optdebug 파서의 모호 구문 덤프뿐이다. CTP 는 오류 코드만 비교하므로, 오류 문구만 다른 자리(§13)는 CTP 답에 나타나지 않는다.

이 문서는 JIRA 글과 매뉴얼 개정의 입력이다. 매뉴얼 PR 은 지도 밖이다(사용자 2026-09-26). 각 절의 "매뉴얼" 줄이 적어야 할 문장이다.

## 0. 한눈에

원칙은 "답은 develop 과 같다"(P0, D-336-A 사용자 결정 "전부 develop 과 동일 작동, domain 만 gate 에서")이다. 도메인과 collation 을 실행 전 게이트에서 한 번 정하게 바꾸면서 답이 달라진 곳은 둘뿐이다. 하나는 사용자가 하나씩 승인한 결정이고, 다른 하나는 develop 결함(크래시, 조용한 오답)이 없어진 자리다.

| # | 바뀌는 것 | 결정 | CTP 답 변경 |
|---|---|---|---|
| 1 | 연산자가 받지 않는 타입 조합(-454)은 행이 없어도, 안 쓰인 CASE 가지여도 실행 전 오류다 | [D-335-02](https://github.com/xmilex-git/workspace/issues/335#issuecomment-5791817639) | 0 |
| 2 | 문자 컬럼·식을 받는 MEDIAN/PERCENTILE 은 DOUBLE 이다(날짜·시간 문자열 → -1118). 문자 컬럼을 받는 ADDTIME 은 VARCHAR 다 | [D-335-10](https://github.com/xmilex-git/workspace/issues/335#issuecomment-5797393992) | 10 케이스 |
| 3 | 같은 prepare 를 다시 실행해도 앞 실행의 바인드가 상수를 바꾸지 않는다 | [#352](https://github.com/xmilex-git/workspace/issues/352#issuecomment-5825942555) `cbrd_24598` | 1 케이스 |
| 4 | 리스트 파일을 거친 문자 결과 열의 precision 표시가 최대 길이다 | [D-338-03](https://github.com/xmilex-git/workspace/issues/338#issuecomment-5811764399) | 0 |
| 5 | 집합 연산·CTE 열의 가지 타입이 다르면 행과 무관하게 실행 전 -456 이다 | [D-341-14](https://github.com/xmilex-git/workspace/issues/341#issuecomment-5831630885) | 0(캠페인 TC) |
| 6 | 행이 고르는 ELT 가지들의 collation 을 병합한다 | [D-343-01](https://github.com/xmilex-git/workspace/issues/343#issuecomment-5835671943) | 0(캠페인 TC) |
| 7 | MEDIAN 과 정렬을 공유하는 다른 분석 함수의 문자 정렬 키는 자기 도메인으로 비교한다 | [D-362-01](https://github.com/xmilex-git/workspace/issues/362#issuecomment-5846234354) | 0(캠페인 TC) |
| 8 | 공통값 노드의 행 의존 피연산자는 힙 순서와 무관하게 계획 도메인이다 | [D-364-05](https://github.com/xmilex-git/workspace/issues/364#issuecomment-5846701545)(사용자 확인 (가)) | 0(캠페인 TC) |
| 9 | 문장이 읽는 세션변수는 문장 동안 한 타입이다. 다른 타입은 실행 전 -1384 다 | [#366](https://github.com/xmilex-git/workspace/issues/366#issuecomment-5847984723) U1~U4 | 1 케이스(`bug_bts_6605`) |
| 10 | 상수의 계산·변환 실패는 행과 무관하게 실행 전 오류다. 데이터로 닿지 않는 상수는 develop 답이다 | [#367](https://github.com/xmilex-git/workspace/issues/367#issuecomment-5852725558) (가)·D-367-07 | 0(캠페인 TC) |
| 11 | develop 결함이 없어진다: 분석 첫 값 변환 실패의 조용한 0행, 정렬 키를 CHAR 로 읽기, optdebug assert 셋 | D-337-06·#362·F-341-06 | 0 |

바뀌지 않는 것은 §14 에 적었다. 파라미터는 바뀌지 않는다. `hostvar_late_binding` 은 그대로 동작한다([D-344-01](https://github.com/xmilex-git/workspace/issues/344#issuecomment-5853038619)). 새 오류 코드와 통계는 §15, 매뉴얼 개정 목록은 §16 이다.

---

## 1. 타입 조합 거부는 실행 전 오류 (D-335-02)

연산자가 받지 않는 타입 조합(DATE + DATE, DATE × 수, TIME × DATE 등)의 -454 를 게이트가 실행 전에 같은 코드·문구로 낸다. develop 은 그 식을 계산하는 행에서만 냈다.

```sql
create table g4 (i int);
insert into g4 values (1), (2);
prepare b_zero from 'select ? + ? from g4 where i = 99';
execute b_zero using date'2024-01-02', date'2024-01-03';
prepare b_case from 'select case when i = 99 then ? * ? else 0 end from g4 order by i';
execute b_case using date'2024-01-02', 2;
```

| 문장 | develop | 새 답 |
|---|---|---|
| `b_zero`(결과 행 0) | 결과 없음 | -454 `Invalid data type referenced.` |
| `b_case`(행이 고르지 않는 가지) | `0`, `0` | -454 |
| `select ? + ? from g4` (행 있음) | -454 | -454 |
| `? - ?` 에 DATETIME, TIME | NULL, NULL | NULL, NULL(오류 없는 NULL 조합은 그대로) |

- 매뉴얼: "연산자가 받지 않는 타입 조합의 오류는 질의를 실행하기 전에 난다. 결과 행이 없거나 그 식이 CASE 의 선택되지 않는 가지에 있어도 오류다."

## 2. 문자 컬럼·식의 MEDIAN/PERCENTILE 은 DOUBLE, ADDTIME 은 VARCHAR (D-335-10)

값이 없는 문자 인자(컬럼, 계산식)의 결과 타입을 내용이 아니라 타입으로 정한다.
- MEDIAN·PERCENTILE_CONT·PERCENTILE_DISC 의 문자 인자는 DOUBLE 이다. 매뉴얼의 PERCENTILE 규칙("숫자로 변환되는 문자열")과 같다.
- ADDTIME 의 문자 인자는 VARCHAR 결과다(매뉴얼 `datetime_fn.rst` 표).
- develop 은 첫 값을 DOUBLE → DATETIME → TIME 순으로 시도해 타입을 정했다.
- 값을 가진 인자(문자 리터럴·호스트 변수·세션변수)는 전처럼 값으로 분류한다(D-328-06).

```sql
create table tm (s varchar(30));
insert into tm values ('2024-01-01 10:00:00'), ('2024-01-03 10:00:00');
select median(s), typeof(median(s)) from tm;
delete from tm; insert into tm values ('01:00:00'), ('03:00:00');
select median(s), typeof(median(s)) from tm;
delete from tm; insert into tm values ('1.5'), ('2.5'), ('3.5');
select median(s), typeof(median(s)) from tm;
```

| 내용 | develop | 새 답 |
|---|---|---|
| 날짜·시각 문자열 | `10:00:00.000 AM 01/02/2024` `'datetime'` | -1118 `The argument of "MEDIAN" can not be coerced to desired domain "DOUBLE".` |
| 시간 문자열 | `02:00:00 AM` `'time'` | -1118 |
| 숫자 문자열 | `2.5` `'double'` | `2.5` `'double'` |
| `'abc'` | -1118 | -1118(문구 "DOUBLE") |

- 첫 값이 변환되지 않으면 -1118 이고, 뒤 행의 값이 변환되지 않으면 -181 이다(develop 과 같은 시점).
- 결과 열의 타입이 준비 시점에 DOUBLE 로 정해진다. 그래서 csql 은 이 열을 숫자 열처럼 오른쪽에 붙여 보인다.
- 분석 함수도 같다. `median(c12) over (partition by a)`(날짜 문자열 컬럼)는 develop 의 날짜 값 대신 -1118 이다.
  - 게이트 의존 문자 식(`median(coalesce(?, s)) over ()`)의 날짜 내용도 -1118 이다(정렬 단계, #362 F-362-03).
  - 집합 연산 열의 첫 값도 -1118 이다(#344 D-344-02, §3a).
- ADDTIME: 존이 붙은 문자열 컬럼(`addtime(varchar_col, ...)`)은 develop optdebug 가 assert 로 멈추던 자리이고, 지금은 VARCHAR 로 답한다. CTP 에는 이 모양이 없다.
- CTP 답 변경(`cb1bdc413`): `issue_11087_median/11087·11087_1·11087_3·11743`, `_14_1h/bug_bts_13916`, `issue_11088_percentile_cont/_01_aggregate_function/_00_from_dev·_08_expression`, `issue_11089_percentile_disc/_01_aggregate_function/_00_from_dev·_08_expression`, `_07_misc/domain_conversion_contract/conversion_contract`(10건·33블록, 전부 날짜·시간 값 → `Error:-1118`).
- 매뉴얼: "MEDIAN·PERCENTILE_CONT·PERCENTILE_DISC 의 인자가 문자열 컬럼이나 문자열 식이면 DOUBLE 로 변환해 계산한다. 숫자로 변환되지 않는 값은 오류다. 문자열 상수·호스트 변수·세션변수는 값에 따라 DOUBLE·DATETIME·TIME 중 하나로 계산한다." ADDTIME 표는 이미 이 규칙이다.

## 3. 반복 실행이 앞 실행의 바인드에 끌려가지 않는다 (#352, `cbrd_24598`)

```sql
prepare q from 'select decode (?, '''', c, NULL, c, -1) from table ({1}) as t (c)';
execute q using 'A';   -- -1
execute q using 1;     -- 1
execute q using 'A';   -- develop: -181 Cannot coerce value of domain "character" to domain "double" / 새 답: -1
prepare p from 'select decode (?, '''', c, NULL, c, ''Z'') from table ({''X''}) as t (c)';
execute p using 1;     -- 'Z'
execute p using 'A';   -- develop: -181 / 새 답: 'Z'
```

- develop 은 앞 실행의 INT 바인드가 캐시된 XASL 의 리터럴 `''` 을 제자리에서 DOUBLE 로 바꿔 두었다(S-09). 그래서 다음 실행의 `'A'` 가 DOUBLE 로 바뀌지 않아 실패했다. 케이스가 "known bug" 로 적어 둔 자리다.
- 지금은 게이트가 상수를 실행마다 자기 값으로 변환하므로 세 번째 실행이 첫 실행과 같다.
- CTP 답 변경: `_13_issues/_23_1h/cbrd_24598`(`de2e2b767`, 사용자 승인 2026-09-25).
- 매뉴얼: 없음(결함 수정).

### 3a. 집합 연산 열 위 분석 MEDIAN 의 첫 값 (#344 D-344-02 — develop 답으로 되돌림)

스펙 변경이 아니다. 캠페인 중간(#341~#367)에 develop 과 달라졌던 자리를 #344 가 develop 오류 코드로 되돌렸고, 기록으로만 남긴다.

```sql
create table t (i int); insert into t values (1), (2), (3);
prepare q from 'select median(dt.x) over () from (select ? x from t where i = 1 union all select ? x from t where i > 1) dt';
execute q using 'abc', 'abc';
```

- develop 은 -1118 이다. #344 전 dpin 은 -181(`character` → `double`)이었고, 커밋 B(`e4f86135a`) 뒤에는 -1118("DOUBLE")이다. 집계형 `select median(dt.x) from (...) dt` 와 같다.
- `'01:00:00'`, `'abc'` 는 D-335-10 대로 -1118 이다. develop 은 첫 값으로 TIME 을 정하고 `'abc'` 에서 -181 이었다.
- TC: `_07_misc/domain_list_aggregate/analytic_interpolation_keys` [SETOP](`0ec0a812f`)가 이 답을 고정한다. `'01:00:00'` 첫 값만 D-335-10 의 답이고 나머지는 develop 답이다.

## 4. 리스트 파일을 거친 문자 결과 열의 precision (D-338-03)

게이트가 정한 문자 결과의 precision 은 값이 정한다(floating). VARCHAR 는 1073741823, CHAR 는 -1 로 표시된다. 피연산자 도메인이 길이를 정하는 규칙(CONCAT 의 합, CAST, SUBSTRING/TRIM 의 원천, MD5/SHA1/UUID 의 고정 길이)만 그 길이다.

```sql
prepare c_prec from 'select typeof(v) from (select upper(?) v from db_root union all select lower(?) from db_root) x';
execute c_prec using 'a', 'b';
-- develop: 'character varying (1)' ×2 / 새 답: 'character varying (1073741823)' ×2
```

- 값·비교·정렬·collation·오류는 바뀌지 않는다. 바뀌는 것은 집합 연산처럼 리스트 파일을 거친 열의 `typeof()`·결과 열 메타데이터의 precision 표시뿐이다. VARCHAR 는 실제 길이만큼 저장한다.
- 사용자 승인(2026-09-24): "결과만 똑바로 나오면 뭐 길이는 어차피 1GB 꽉채워쓰지도 않아서 괜찮은거아냐??"
- #358 이 적은 공통값 노드의 예(`typeof(coalesce(cast(? as datetime), cast(? as datetime), ?))` 에 VARCHAR(20) 바인드)는 #364 뒤 develop 과 같다. 둘 다 `character varying (20)` 이다. #364(D-364-01)가 공통값 노드를 상수 부분트리 값의 도메인으로 접게 바꿨기 때문이다(SA 실측).
- 매뉴얼: "집합 연산(UNION 등)·CTE 의 문자열 결과 열 정밀도는 가지 값의 길이가 아니라 최대 길이로 표시될 수 있다."

## 5. 집합 연산·CTE 열의 가지 타입 불일치는 실행 전 -456 (D-341-14)

두 가지가 모두 바인드여서 컴파일이 열 타입을 정하지 못할 때, 게이트가 가지마다 정한 도메인을 develop `qfile_unify_types` 와 같은 규칙으로 비교한다. 다르면 행과 무관하게 실행 전에 -456 이다. develop 은 두 가지에 모두 행이 있을 때만 -456 을 냈다. 한쪽 가지가 비면 다른 가지의 타입이었다.

```sql
create table la_so (i int); insert into la_so values (1);
prepare q from 'select ? x from la_so where i = 1 union all select ? from la_so where i > 5';
execute q using 1, 'a';
```

| 문장(`la_so` 1행) | develop | 새 답 |
|---|---|---|
| 위 `q`(뒤 가지가 빈다) 에 `1`, `'a'` | `1` | -456 `Data type references are incompatible.` |
| 같은 `q` 에 `'a'`, `1` | `'a'` | -456 |
| 두 가지 모두 비는 `where i > 5 union all … where i > 5` 에 `1`, `'a'` | 결과 없음 | -456 |
| `difference`, CTE(`with cte(x) as (… union all …)`) 같은 모양 | 한 가지의 타입 | -456 |
| 두 가지 모두 행이 있는 `1`, `'a'` | -456 | -456 |
| `1`, `2` · `'a'`, `'bcd'` · `1`, NULL | 값 | 값(같은 타입·가변 문자열·NULL 가지는 전처럼 합친다) |

- 사용자 결정 (나)(2026-09-25).
- 매뉴얼: "집합 연산과 CTE 의 가지가 서로 다른 타입의 값을 내면, 한쪽 가지의 결과 행이 없어도 오류다."

## 6. 행이 고르는 ELT 가지의 collation 병합 (D-343-01)

ELT 의 인덱스가 행마다 바뀌고 문자 가지의 collation 이 서로 다를 때를 다룬다.
- 게이트가 가지 collation 을 develop 의 병합 규칙(coercibility, `LANG_RT_COMMON_COLL`)으로 합쳐 문장에 하나로 정한다. 행이 고른 값은 그 도메인으로 바뀐다. 합칠 수 없으면 실행 전 -1150 이다.
- develop 은 행마다 고른 가지의 collation 을 두었고, 정렬·DISTINCT 는 첫 행이 고른 가지의 collation 을 따랐다.
- 인덱스가 바인드·리터럴이면 게이트가 가지를 한 번 고르므로 develop 답 그대로다. CASE·IF·DECODE 는 develop 이 컴파일에서 맞추므로 해당 없다.
- 사용자 결정 (다) "MySQL 방식"(2026-09-26).

```sql
create table dbc_t (a int); insert into dbc_t values (1), (2), (3), (4);
set names utf8 collate utf8_en_ci;
set @dbc_bin = _utf8'B' collate utf8_bin;
prepare b1 from 'select a, elt(2 - a % 2, ?, @dbc_bin) v, collation(elt(2 - a % 2, ?, @dbc_bin)) c from dbc_t order by a';
execute b1 using 'a', 'a';
prepare b3 from 'select v, collation(v) c from (select elt(1 + a % 2, ?, @dbc_bin) v from dbc_t order by a) d order by v, c';
execute b3 using 'a';
prepare b5 from 'select distinct elt(1 + a % 2, ?, @dbc_bin) v from dbc_t order by 1';
execute b5 using 'b';
set @dbc_cs = _utf8'B' collate utf8_en_cs;
prepare b6 from 'select elt(2 - a % 2, ?, @dbc_cs) v from dbc_t order by a';
execute b6 using 'a';
```

| 문장 | develop | 새 답 |
|---|---|---|
| `b1` 의 `c` 열 | `utf8_en_ci`, `utf8_bin`, `utf8_en_ci`, `utf8_bin` | 모두 `utf8_en_ci` |
| `b3` 의 순서 | `B`, `B`, `a`, `a`(첫 행 `'B'` 의 utf8_bin) | `a`, `a`, `B`, `B` |
| `b5` | `'B'`, `'b'` | `'B'`(utf8_en_ci 에서 한 값) |
| 숫자 가지 `elt(2 - a % 2, ?, ?)` 에 `'a'`, `2` 의 `collation` | 숫자 행 `utf8_bin` | `utf8_en_ci` |
| `b6`(병합 불가 utf8_en_ci·utf8_en_cs) | 행을 답함 | 실행 전 -1150 `Context requires compatible collations.` |

- 매뉴얼(ELT): "선택 인덱스가 행마다 달라지는 ELT 의 문자열 결과 collation 은 문자열 인자들의 collation 을 병합한 하나이다. 병합할 수 없으면 오류다."

## 7. MEDIAN 과 정렬을 공유하는 분석 함수의 문자 정렬 키 (D-362-01)

숫자·상수 인자 MEDIAN/PERCENTILE 과 정렬을 공유하는 다른 분석 함수의 문자 ORDER BY 키는 자기 도메인으로 비교한다. MEDIAN 이 없을 때와 같은 답이다. develop 은 그 키도 MEDIAN 의 첫 값 부류로 비교했다.

```sql
create table ai_t (i int, p int, s varchar(20), n int, y varchar(20));
insert into ai_t values (1, 1, '1.5', 10, 'b'), (2, 1, '2.5', 9, 'a'), (3, 2, '3.5', 8, 'c'), (4, 2, '10', 7, '10'), (5, 2, '9', 6, '9');
select i, median(1) over () m, row_number() over (order by y) r from ai_t order by i;
select i, median(1) over () m, row_number() over (order by s) r from ai_t order by i;
```

- 첫 문장: develop 은 -1118(`The argument of "ROW_NUMBER" can not be coerced to desired domain "DOUBLE, DATETIME or TIME".`), 새 답은 `row_number() over (order by y)` 와 같은 행이다.
- 둘째 문장: develop 은 `'10'`·`'9'` 를 숫자 순서로, 새 답은 문자열 순서로 센다.
- RANK·DENSE_RANK 도 같다.
- 사용자 결정 (가)(2026-09-26).
- 매뉴얼: 없음. 이전 동작이 결함이었다.

## 8. 공통값 노드의 행 의존 피연산자 (D-364-05)

COALESCE·NVL·IFNULL·NVL2·NULLIF·LEAST·GREATEST 의 피연산자를 행이 줄 때, 결과 타입은 힙 순서와 무관하게 계획 도메인이다. develop 은 첫 비NULL 결과 행의 값으로 노드 타입을 붙박았다. 그래서 첫 행의 컬럼이 NULL 이면 뒤 행에서 오류가 나거나 값이 잘렸다.

```sql
create table cv_t (k int, d date, dt datetime);
insert into cv_t values (1, null, null), (2, date'2024-01-05', datetime'2024-01-05 10:00:00');
prepare q from 'select k, typeof(coalesce(cast(? as datetime), dt, ?)), coalesce(cast(? as datetime), dt, ?) from cv_t order by k';
execute q using null, 1, null, 1;
execute q using null, date'2024-01-02', null, date'2024-01-02';
```

| 바인드 | develop | 새 답 |
|---|---|---|
| `(NULL, 1)` | -181 `Cannot coerce value of domain "datetime" to domain "integer"`(둘째 행) | `'character varying (1073741823)'` `'1'` / `'10:00:00.000 AM 01/05/2024'` |
| `(NULL, date'2024-01-02')` | `'date'` `01/02/2024` / `01/05/2024`(DATETIME 을 DATE 로 자름) | `'datetime'` `12:00:00.000 AM 01/02/2024` / `10:00:00.000 AM 01/05/2024` |

- 값 행이 먼저 오면(`cv_r`: 행 순서만 반대) develop 도 새 답과 같다.
- JDBC 문자열 바인드는 첫 행이 NULL 일 때 develop `character (-1)` 이고, 새 답은 `character varying (1073741823)` 이다.
- 사용자 확인 (가) "현행 유지"(2026-09-26).
- 매뉴얼: 없음(결과 타입이 행 순서에 따라 달라지지 않게 된 것).

## 9. 문장이 읽는 세션변수는 문장 동안 한 타입 (#366, U1~U4)

문장이 **읽는** 세션변수의 타입은 게이트가 실행 전에 정한다.
- 타입은 실행 시작 값의 타입과 문장 안 대입식의 타입을 합친 것이다(열이 그 행에서 NULL 이어도 열의 타입).
- CAST 없이 다른 타입이 되면 실행 전 -1384 `ER_QPROC_SESSION_VARIABLE_TYPE` 이고, 변수 값은 그대로 남는다. 숫자끼리도 같다(INT 와 FLOAT, INT 와 BIGINT).
- 같은 codeset·collation 의 문자열은 길이·CHAR/VARCHAR 와 무관하게 한 타입이고, collation 이 다르면 다른 타입이다.
- 대입만 하는 문장·읽기만 하는 문장은 develop 답 그대로다.
- develop 은 행마다 값으로 타입을 정했다.

```sql
set @a = 0;
select a, @a := (@a + (a + a) / (a * 2)) * (c * 10) + 1 from (select * from t order by a desc) order by a desc;   -- c FLOAT
set @v = 1;
select @v := @v + 1, @v := '2.5' from fg_t order by i;
select @v;
set @w = 'x';
select @w := 1, @w + 1 from fg_t order by i;
set @sv_m = 'a';
select @sv_m := s collate utf8_en_ci, @sv_m from sv_t order by k;
```

| 문장 | develop | 새 답 |
|---|---|---|
| `bug_bts_6605`(첫 문장) | `5.0`, `19.0`, `41.0`, `43.0` | -1384 `Session variable @a would hold integer and float within a statement that reads it; cast the value to one type.` |
| `@v := @v + 1, @v := '2.5'` 뒤 `select @v` | 행들, `'2.5'` | -1384, `1` |
| `@w := 1, @w + 1`(시작 `'x'`) | -181 | -1384(`character collate utf8_bin and integer`) |
| `@sv_m := s collate utf8_en_ci`(시작 utf8_bin) | 행 | -1384(collation 이 다른 문자열) |
| `@a := cast(… as int)` | 값 | 값(CAST 가 한 타입으로 맞춘다) |

- 내용이 부류를 정하는 자리(MEDIAN/PERCENTILE, ADDTIME 왼쪽, STR_TO_DATE 포맷)는 실행 시작 값의 부류다(D-366-06). 행은 다시 분류하지 않는다.
  - `set @m = '1.5'; select median(@m), typeof(median(@m)) from (select (@m := '01:00:00') x from db_root) d, la_sv;`: develop 은 `01:00:00 AM` `'time'`, 새 답은 -181(`character varying` → `double`)이다.
  - STR_TO_DATE 포맷 변수를 파생 테이블이 `'%Y-%m-%d'` 에서 `'%Y-%m-%d %H:%i:%s'` 로 바꾸면 시작 포맷의 DATE 가 된다(develop DATETIME, 탐침만).
- 게이트가 보지 못한 쓰기(문장이 부른 저장 프로시저가 바꾼 변수)의 다른 타입 값도 -1384 다(develop 은 새 값, 탐침만).
- CTP 답 변경: upstream `_13_issues/_12_1h/bug_bts_6605` 1문장(사용자 U3 승인). 캠페인 TC `fetch_gate_probes` [S5], `fetch_gate_counters` [N-sv-change], `list_aggregate_probes` [CLASS], `analytic_interpolation_keys` [SESSION_CHANGED]. 새 TC `session_variable_types` 가 규칙을 고정한다.
- 매뉴얼(세션변수): "한 문장 안에서 읽는 세션변수는 그 문장 동안 한 타입을 가진다. 문장이 그 변수에 다른 타입의 값을 대입하면(CAST 없이) 실행 전에 오류다. 같은 문자셋·collation 의 문자열은 길이와 무관하게 같은 타입이다."

## 10. 상수의 계산·변환 오류는 실행 전 (#367 (가), D-367-07)

상수(리터럴·바인드·상수 부분트리, 컴파일이 상수 피연산자에 씌운 암시적 CAST 포함)의 계산·변환이 실패하면 행과 무관하게 실행 전 오류다. 행 0개, 행이 고르는 안 쓰인 분기, 행 값이 막는 단락에서도 그렇다. develop 은 그 식을 처음 계산하는 행에서 오류를 냈다.

```sql
-- ce_t: a = 1, 2, 3 (NULL 없음), c int / ce_e: 빈 테이블
prepare q from 'select a, case when a > 0 then a else cast(concat(?, '''') as int) end from ce_t order by a';
execute q using 'abc';
prepare q from 'select a from ce_t where a < 0 and c = 100 / (? - ?)';
execute q using 1, 1;
prepare q from 'select a, a + concat(?, '''') from ce_e';
execute q using 'abc';
prepare q from 'select a from ce_e where c = concat(?, '''')';
execute q using 'abc';
prepare q from 'select median(?) from ce_e';
execute q using 'abc';
```

| 문장 | develop | 새 답 |
|---|---|---|
| CASE 의 안 쓰인 가지(모든 a > 0) | `1`, `2`, `3` | -181 |
| AND 뒤 항의 `100 / (? - ?)` 에 (1, 1) | 0행 | -539(0 으로 나누기) |
| 빈 테이블의 `a + concat(?, '')`·`greatest(a, …)`·`nullif(a, …)` | 0행 | -181 |
| 인덱스 없는 열의 `c = concat(?, '')`·`c in (1, concat(?, ''))`(빈 테이블·걸러진 행) | 0행 | -181 |
| 0행의 `median(?)` 에 `'abc'`, `median('abc')`, `median(B'0001')`, `median(?) over ()`, `percentile_cont(0.5) within group (order by ?)`, 세션변수 `'abc'` | NULL(또는 0행) | -1118 |

- 인덱스 키 자리의 상수는 develop 도 스캔을 열 때 -181 이다(답 불변). 앞 컬럼이 NULL 인 복합 키, 닿지 않는 스캔에서만 달라진다(D-367-03).
- **데이터로 닿지 않는 상수는 develop 답이다(D-367-07, 사용자 "develop 답 유지").** 상수 조건이 어떤 데이터로도 그 상수에 닿지 않게 막으면 오류를 내지 않는다. 해당하는 조건은 다음과 같다.
  - CASE·IF·DECODE 의 상수 조건
  - 도메인이 정해진 COALESCE·NVL·IFNULL·NVL2 의 상수 첫 피연산자
  - AND/OR 의 상수 앞 항
  - 블록의 상수 조건
  - 최상위 블록의 상수 LIMIT
- 가드 예:
  - `case when ? = 0 then 0 else 100 / ? end` 에 (0, 0) → `0`
  - `order by a limit ?, ?+?` 에 `''` 셋 → 0행
  - upstream timezone 4파일의 `if(utc_time()-current_time>0, timediff(…), timediff(…))`
  - SA 실측에서 이 5파일은 develop 과 같다.
- 도메인이 열린 COALESCE·NVL2(`coalesce(?, cast(concat(?, '') as int), a)`)는 가드가 아니다. develop 이 첫 행에서 모든 피연산자를 읽기 때문이다. 그래서 0행에서만 develop 무오류 → -181 이다.
- 행이 계산하는 실패는 develop 시점 그대로다(D-367-05). 해당하는 것은 DML 대입, LEAD/LAG 기본값·오프셋, 열 값이 원인인 오류, 항 밖 비교(FIELD·NULLIF·LEAST·GREATEST·LIMIT)의 순위 답이다.
- CTP 답 변경: upstream 0. 캠페인 TC `list_aggregate_probes` [UNCLASS] 1문장(`median('abc') … where i > 5` NULL → -1118), 새 TC `constant_errors`(develop 과 다른 21문장).
- 매뉴얼: "상수(리터럴·호스트 변수·그 식)의 계산이나 변환이 실패하면 질의를 실행하기 전에 오류가 난다. 결과 행이 없거나 그 식이 선택되지 않는 가지에 있어도 그렇다. 다만 상수 조건 때문에 어떤 데이터로도 계산되지 않는 식(예: `CASE WHEN 1 = 0 THEN …`)은 오류를 내지 않는다."

## 11. develop 결함이 없어지는 자리 (P0 예외 — 크래시·조용한 오답)

| 자리 | develop | 새 답 | 근거 |
|---|---|---|---|
| 분석 첫 값이 변환되지 않을 때(`sum(?) over (partition by g)` 에 DATE 바인드) | release: 오류 없이 0행, optdebug: `qexec_analytic_add_tuple` assert | -181 `Cannot coerce value of domain "date" to domain "double"` | D-337-06(D4) |
| `group_concat(?)` 에 NULL 바인드 | optdebug `qexec_end_one_iteration` collation 플래그 assert(release 는 NULL) | NULL | D2, F-341-06 |
| `select ? union all select ?` 에 NULL·NULL, 재귀 CTE 시드 NULL | optdebug `qfile_unify_types` assert(release 는 답) | NULL·값 | D6, D-337-07 |
| 세션변수 숫자 값·파생 열 DOUBLE/DATE 바인드 위 분석 MEDIAN 의 정렬 키(`set @v = 1.5; select median(@v) over (partition by p) …`) | 정렬 키를 CHAR 로 읽어 -1118, 같은 문장을 다른 바인드 타입으로 다시 실행하면 optdebug `or_advance` assert | 값 | #362 ②(dpin 은 #341·#355 부터) |
| PX 워커가 클론 풀의 앞 실행 누산기 도메인으로 누적(정수 바인드 뒤 문자 바인드) | 결과 타입이 틀림 | 맞는 타입 | D-340-09(CBRD-27484 와 같은 풀) |

- develop optdebug 는 SA 실측에서 `collation_gate_probes`(D2)·`list_aggregate_probes` [SETOP](D6)·D4 문장에서 멈췄다. 코어는 원인을 적고 지웠다.
- 매뉴얼: 없음.

## 12. develop 결함으로 남는 것 (지도 밖, P0 로 보존)

이 PR 은 다음을 고치지 않는다(지도 Out of scope). 답은 develop 과 같다.
- [#347](https://github.com/xmilex-git/workspace/issues/347) 문자 원소가 섞인 컬렉션 리터럴 INSERT 가 NULL 을 저장한다.
- [#349](https://github.com/xmilex-git/workspace/issues/349) 바인드 경로 오답 4곳.
- [#351](https://github.com/xmilex-git/workspace/issues/351) PL/CSQL 정적 SQL 재작성 2곳(-889).
- [#353](https://github.com/xmilex-git/workspace/issues/353) `enum_col IN (NULL, NULL)` optdebug assert.
- [#359](https://github.com/xmilex-git/workspace/issues/359) 필터 인덱스 술어 스트림이 ALTER 뒤 옛 타입이다.
- [#361](https://github.com/xmilex-git/workspace/issues/361) 해시 리스트 스캔 빌드 키 셋.
- [#363](https://github.com/xmilex-git/workspace/issues/363) `to_char(날짜, ?)` 에 문자열 아닌 포맷 바인드가 오면 서버가 죽는다.
- [#365](https://github.com/xmilex-git/workspace/issues/365) `median(@u := s) over ()` 에서 XASL 생성이 assert/SIGSEGV 로 멈춘다.
- [#326](https://github.com/xmilex-git/workspace/issues/326) ENUM 형제 collation.
- [#360](https://github.com/xmilex-git/workspace/issues/360) 비직관 규칙 10가지.

## 13. 오류 코드는 같고 문구만 다른 자리

CTP 는 오류 코드만 비교하므로 답 파일에는 드러나지 않는다. JIRA 글에 적을 사항이다.

| 자리 | develop 문구 | 새 문구 |
|---|---|---|
| 문자 컬럼·식 MEDIAN/PERCENTILE 의 -1118(D-335-10) | `…desired domain "DOUBLE, DATETIME or TIME".`(집계) / `"DOUBLE, DATETIME, TIME"`(분석) | `…desired domain "DOUBLE".` |
| 분류하지 못한 값 인자의 분석 -1118(`median(dt.x) over ()` 의 파생 열 바인드 등) | `"DOUBLE, DATETIME, TIME"` | `"DOUBLE, DATETIME or TIME"`(집계와 같은 문구) |
| `limit ?, ?` 에 `'c'`, `2`(`20567_limit_SELECT_hostvar_2`) | -181 `Cannot coerce value of domain "character" to domain "double".` | -181 `Cannot coerce value of domain "bigint" to domain "character".` |
| `where coalesce(cast(? as datetime), ?, k) = 1` 에 날짜 바인드(JDBC) | -181 문구가 세션의 앞 실행에 따라 `"character varying" → "double"` 또는 `"integer"` | 늘 `"integer"`(#364 F-364-03) |

## 14. 바뀌지 않는 것

아래는 답이 develop 과 같다는 것을 SA A/B·CTP 전수로 확인했다.
- 타입 격자: 산술·비교·공통값·집계의 결과 타입, 변환 방향, 손실 정책(비교 strict-or-keep, 대입 반올림), `return_null_on_function_errors`.
- 바인드 캐스트: develop 이 기대 도메인으로 바인드를 캐스트하던 자리는 클라이언트에서 develop 규칙대로 한다(D-335-08).
- 게이트는 나머지 슬롯의 도메인을 바인드 값의 타입으로 develop 격자대로 정한다(D-336-A·B).
- collation: coercibility·병합 규칙·`SET NAMES`/`ALTER … COLLATE` 재컴파일·플랜 캐시 키는 그대로다(D-322-03). -1150/-622 의 시점도 develop 과 같다(행이 계산하는 병합). 예외는 ELT(§6)와 상수(§10)다.
- 플랜: 바인드 피크 재계획과 LIKE/LIMIT 값 의존 재컴파일의 플랜 모양은 그대로다(D-318-05).
- 인덱스 키: 단일 컬럼 키는 값 그대로 쓰고, 복합 키는 strict-or-keep 이다(develop 답, #342).
- PL/CSQL 정적 SQL 의 `?` 는 JDBC `?` 와 같은 슬롯이다. 선언 타입은 쓰지 않는다(D-339-01, develop 답).
- `hostvar_late_binding`: 그대로 동작한다([D-344-01](https://github.com/xmilex-git/workspace/issues/344#issuecomment-5853038619)).
  - 켜면 XASL 캐시를 쓰지 않는 경로(`max_plan_cache_entries=0` 등)에서 `?` 가 바인드 값의 리터럴로 치환된다. SA 실측 플랜 텍스트는 `where ts.s='1'`, `tn.i+time '10:00:01 AM'` 이었다.
  - 캐시 경로에서는 auto-param 만 꺼진다.
  - on/off × 캐시/무캐시 모두 develop 과 dpin 의 답이 같다(`.git_ignored_dir/scratch/312-344/probe/hv2`).
- 단위 테스트는 이 캠페인에서 돌리지 않았다(사용자 지시 2026-09-22).

## 15. 새 오류 코드·통계

| 코드 | 이름 | 문구(en_US) | 언제 |
|---|---|---|---|
| -1383 | `ER_QPROC_DOMAIN_UNRESOLVED` | `Domain of a query node is unresolved at %1$s (query %2$s, node %3$d, domain %4$s).` | 내부 경계다. 게이트가 정했어야 할 도메인이 없으면 optdebug 는 assert, release 는 이 오류로 멈춘다. 사용자에게 보이면 결함이다(CTP 전수에서 0). develop 이 -1381·-1382 를 먼저 써서 -1383 이다(#357). |
| -1384 | `ER_QPROC_SESSION_VARIABLE_TYPE` | `Session variable @%1$s would hold %2$s and %3$s within a statement that reads it; cast the value to one type.` | §9 |

`ER_LAST_ERROR` 는 -1385 다. ko_KR 문구도 추가했다.

통계(`SET @collect_exec_stats = 1` 뒤 `SHOW EXEC STATISTICS ALL`, perfmon)는 10개다.

| 이름 | 뜻 | 기대값 |
|---|---|---|
| `Num_domain_resolve_fetch` | fetch 가 값에서 도메인을 정한 횟수 | 0 |
| `Num_domain_coerce_compare` | 비교가 타입이 다른 두 값의 도메인을 값에서 정한 횟수 | 0(계획이 답하지 않는 top-N 키만 셈, 실측 0) |
| `Num_domain_resolve_list` | 리스트·정렬 키 도메인을 값에서 정한 횟수 | 0 |
| `Num_domain_resolve_agg` | 집계·분석 도메인을 첫 값에서 정한 횟수 | 0 |
| `Num_domain_key_coerce` | 인덱스 키 변환을 값에서 정한 횟수 | 0(계획 밖 B-tree 검색만) |
| `Num_domain_px_resolve` | PX 워커가 도메인을 정한 횟수 | 0 |
| `Num_domain_restore_clone` | 실행 뒤 플랜 노드 도메인을 되돌린 횟수 | 0 |
| `Num_domain_gate_convert` | 게이트가 값을 변환한 횟수(값 × 실행) | 상수 수 × 실행 |
| `Num_domain_bind_plan_mismatch` | 바인드 값 타입 ≠ 계획 도메인 | 0 |
| `Num_planned_convert` | 행에서 계획된 변환기를 부른 횟수 | 행 × 변환 |

- 매뉴얼(통계 목록): 위 10개를 추가한다. 앞의 7개는 "0 이어야 정상"인 진단 통계다.

## 16. 매뉴얼에 적을 곳 (요약)

| 쪽 | 적을 것 | 절 |
|---|---|---|
| 집계·분석 함수 MEDIAN·PERCENTILE_CONT·PERCENTILE_DISC | 문자열 컬럼·식 인자는 DOUBLE, 상수·호스트 변수·세션변수는 값으로 분류 | §2 |
| 문자열 함수 ELT | 행마다 달라지는 선택의 결과 collation 병합, 병합 불가 오류 | §6 |
| 세션변수(SET, `@v :=`) | 문장 안 한 타입, 다른 타입 대입은 실행 전 오류, 같은 문자셋·collation 문자열은 한 타입 | §9 |
| 집합 연산·CTE | 가지 타입 불일치는 빈 가지여도 오류, 문자열 결과 정밀도 표시 | §5·§4 |
| 오류 처리(연산자·형변환) | 타입 조합 거부와 상수 계산·변환 실패는 실행 전 오류, 상수 조건으로 닿지 않는 식은 예외 | §1·§10 |
| 오류 코드 목록 | -1383, -1384 | §15 |
| 통계 목록 | `Num_domain_*` 9개 + `Num_planned_convert` | §15 |
