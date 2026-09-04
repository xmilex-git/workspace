# CBRD-27365 Test

## 검증 포인트

- 임시 리스트를 거치는 모든 경로(ORDER BY, GROUP BY, DISTINCT, UNION, IN 서브쿼리, 파생 테이블 재스캔, 해시 조인, 머지 조인, 분석 함수, CONNECT BY, 재귀 CTE, 커서 fetch)에서 질의 결과가 변경 전과 동일하다.
- NULL 이 고정 컬럼 사이에 끼는 행(첫 NULL 이후 컬럼 위치 계산), 전 컬럼 NULL 행, 빈 문자열('')과 NULL 의 구분이 정확하다. 재발 시 잡아야 할 결함: 첫 NULL 고정 컬럼 뒤 값이 2바이트 밀려 읽히던 버그(CHAR '' 커서 오버런, ENUM 인덱스 0x8000).
- 가변 길이 값의 1B/4B 길이 헤더 경계(127/128/129B), 4KB 이상 값, 페이지를 넘는 오버플로 튜플(20~30KB 값) 이 정렬·집계·UNION·재스캔에서 손상 없이 왕복한다.
- 고정 타입 전 종(SHORT/INT/BIGINT/FLOAT/DOUBLE/DATE/TIME/TIMESTAMP/DATETIME/ENUM/MONETARY)과 가변 취급 타입(CHAR/VARCHAR/NCHAR/BIT/BIT VARYING/NUMERIC)이 정렬 키·그룹 키·DISTINCT 키로 정확히 비교된다. 재발 결함: NUMERIC 컬럼 값 0x0800000000000001 류의 오독(늦은 도메인 확정).
- 호스트 변수 컬럼이 NULL 로 시작한 뒤 bound 값이 오는 리스트(CASE WHEN ... THEN ? ELSE NULL), 재귀 CTE 비재귀부 NULL 호스트 변수가 정확한 값과 타입으로 나온다. 재귀 CTE 에서 서버가 abort 하지 않는다.
- ORDER SIBLINGS BY 문자열 키 정렬 순서가 변경 전과 동일하고("1.10" 과 "1.2" 형제 순서), START WITH 없는 다중 루트 CONNECT BY 를 DELETE ... WHERE id IN (계층 서브쿼리) 로 실행할 때 에러(-495) 없이 성공한다.
- ORDERBY_NUM/INST_NUM(ROWNUM)/CONNECT_BY_ISLEAF/CONNECT_BY_ISCYCLE 이 가변 컬럼 뒤에 있는 열에서도 정확하다(in-place 덮어쓰기).
- SET/MULTISET/SEQUENCE/JSON 컬럼(256B 초과 컬렉션 포함)이 정렬 키·DISTINCT·UNION 에서 정확하다.
- 64컬럼을 넘는 리스트(널 비트맵 9B 이상)에서 65번째 이후 컬럼의 NULL 판정과 값이 정확하다.
- JDBC scrollable 커서(TYPE_SCROLL_INSENSITIVE)의 previous()/absolute()/last() 가 전 행을 정확히 돌려준다(역방향 가능 리스트의 prev_len).
- 임시 리스트 페이지 수가 변경 전보다 감소한다(SHOW TRACE 의 임시 리스트 SCAN `page:` 값, 또는 100만 행 (INT, BIGINT) 정렬의 정렬 데이터 페이지 -26%).

## TC 배치

- csql 스크립트 + answer 로 판정되는 10건은 `cubrid-testcases`(sql): 첨부 `cbrd27365-tcs.zip` 의 `tc01_null_mix.sql` ~ `tc10_inplace.sql`. 각 파일은 CTP sql 케이스 형식(문장마다 `;`, 마지막 DROP)이며 동봉된 `*.answer.develop`(변경 전 develop 빌드 출력) 이 기대 답안이다(tc08 만 예외, 주의사항 참조). 배치 위치는 TC PR CUBRID/cubrid-testcases#3420(`tc/pr-7866`)의 `sql/_36_guava/cbrd_27365/cases/cbrd_27365_1.sql` ~ `cbrd_27365_10.sql`(CTP 답안 `answers/*.answer` 는 PR 빌드 출력으로 생성, tc08 외 9건은 develop 빌드 출력과 바이트 동일). zip 의 tc04/tc06/tc07/tc09 는 CTP 반입 시 문법 오류 문장(CONNECT BY 의 WHERE 위치, 윈도 프레임, 분석함수형 GROUP_CONCAT, SEQUENCE 정렬, 집합 리터럴 안의 함수 호출, 다중 인자 COUNT(DISTINCT))을 유효 문장으로 고쳤다(#201).
- JDBC 역방향 커서(첨부 `ScrollSmoke.java`, 인자 `<jdbc-url> <user> <password>`, 표준출력을 `expected_scroll.out` 과 비교)와 임시 페이지 수 감소 확인(SHOW TRACE 판독)은 `cubrid-testcases-private-ex`(shell).
- 플랜 텍스트 유지가 목적인 기존 케이스(cbrd_23665, cbrd_24148, cbrd_25382_1/_5, cbrd_25447, cbrd_25519, join_orderby_skip)는 새 TC 가 아니라 기존 TC 의 입력 확대·데이터 재설계 대상이다(주의사항 참조).

## 실행 레시피

### DB 파라미터

N/A — 기본값으로 충분하다. 임시 페이지 수 감소를 확인하는 shell TC 만 아래를 권장한다.

```
# cubrid.conf (서버 재기동 필요)
sort_buffer_size=2M          # 정렬이 임시 볼륨으로 넘어가도록 작게 유지 (페이지 수 비교의 전제)
temp_file_memory_size_in_pages=4   # 리스트가 메모리에 머물지 않고 페이지로 나가게 함
# 세션에서 SET TRACE ON; 질의; SHOW TRACE; 로 임시 리스트 SCAN 의 page: 값을 읽는다 (SET SYSTEM PARAMETERS 불필요)
```

### 셋업 SQL

tc01(NULL 혼합)과 tc08(늦은 도메인)의 셋업을 그대로 옮긴다. 나머지 8건의 셋업은 첨부 zip 의 각 `.sql` 앞부분에 있다.

```sql
-- tc01: 고정/가변 혼합 9컬럼, NULL 이 첫 고정 컬럼(a)·마지막 가변 컬럼(h)·전 컬럼에 섬, 빈 문자열 행 포함
DROP TABLE IF EXISTS t01;
CREATE TABLE t01 (id INT, a INT, b BIGINT, c DOUBLE, d CHAR(4), e VARCHAR(100), f NUMERIC(12,3), g DATE, h VARCHAR(10));
INSERT INTO t01 VALUES (1, 10, 100, 1.5, 'ab', 'alpha', 1.250, DATE'2024-01-01', 'x');
INSERT INTO t01 VALUES (2, NULL, 200, 2.5, 'cd', 'beta', 2.250, DATE'2024-01-02', 'y');
INSERT INTO t01 VALUES (3, 30, NULL, 3.5, NULL, 'gamma', 3.250, NULL, NULL);
INSERT INTO t01 VALUES (4, 40, 400, NULL, 'gh', NULL, NULL, DATE'2024-01-04', 'w');
INSERT INTO t01 VALUES (5, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO t01 VALUES (6, 60, 600, 6.5, '', '', 0, DATE'2024-01-06', '');
INSERT INTO t01 VALUES (7, 70, 700, 7.5, 'ij', 'eta', 7.250, DATE'2024-01-07', NULL);
INSERT INTO t01 VALUES (8, NULL, 800, 8.5, 'kl', 'theta', NULL, DATE'2024-01-08', 'v');

-- tc08: 호스트 변수 컬럼이 NULL 로 시작하는 리스트
DROP TABLE IF EXISTS t08;
CREATE TABLE t08 (id INT, flag INT, v VARCHAR(20));
INSERT INTO t08 VALUES (1, 0, 'a'), (2, 0, 'b'), (3, 1, 'c'), (4, 1, 'd'), (5, 0, NULL), (6, 1, 'f');

-- 페이지 수 감소 확인용 (shell): 100만 행 (INT, BIGINT)
DROP TABLE IF EXISTS t_sz;
CREATE TABLE t_sz (i INT, b BIGINT);
INSERT INTO t_sz SELECT ROWNUM, ROWNUM * 1000 FROM db_class a, db_class b, db_class c, db_class d LIMIT 1000000;
```

### 실행 SQL

```sql
-- tc01: 첫 고정 컬럼 NULL 행 뒤의 가변 컬럼 읽기, 정렬키·값 양쪽의 NULL, 빈 문자열 vs NULL
SELECT * FROM t01 ORDER BY a, id;
SELECT * FROM t01 ORDER BY e DESC, id;
SELECT a, d, e, h FROM t01 WHERE a IS NULL ORDER BY id;
SELECT a, COUNT(*), SUM(b), MAX(e), MIN(d) FROM t01 GROUP BY a ORDER BY a;
SELECT DISTINCT a, h FROM t01 ORDER BY a, h;
SELECT id, e FROM t01 WHERE a IS NULL UNION ALL SELECT id, h FROM t01 WHERE b IS NULL ORDER BY 1, 2;
SELECT id, d, e, h, d IS NULL, e = '', h IS NULL FROM t01 WHERE id IN (5, 6) ORDER BY id;

-- tc08: 늦은 도메인 확정 (기대: 값이 각 실행의 ? 타입으로 나옴, 서버 생존)
PREPARE s1 FROM 'SELECT id, CASE WHEN flag = 1 THEN ? ELSE NULL END AS hv FROM t08 ORDER BY id';
EXECUTE s1 USING 12345;
EXECUTE s1 USING 'text-value';
EXECUTE s1 USING 1.5;
DEALLOCATE PREPARE s1;
PREPARE s3 FROM 'SELECT CASE WHEN flag = 1 THEN ? ELSE NULL END AS hv, COUNT(*), MAX(v) FROM t08 GROUP BY hv ORDER BY hv';
EXECUTE s3 USING 42;
EXECUTE s3 USING 'grp';
DEALLOCATE PREPARE s3;
-- 재귀 CTE 공용 리스트: 기대 n=1..5, hv = NULL,7,7,7,7 / NULL,'seven'x4 / NULL,7.25x4
PREPARE s6 FROM 'WITH RECURSIVE c (n, hv) AS (SELECT 1, ? FROM db_root UNION ALL SELECT n + 1, COALESCE(hv, ?) FROM c WHERE n < 5) SELECT n, hv FROM c ORDER BY n';
EXECUTE s6 USING NULL, 7;
EXECUTE s6 USING NULL, 'seven';
EXECUTE s6 USING NULL, 7.25;
DEALLOCATE PREPARE s6;
-- 기대: n=1..6, hv = NULL,50,50,50,50,50 ; hv IS NULL = 1,0,0,0,0,0
PREPARE s7 FROM 'WITH RECURSIVE c (n, hv) AS (SELECT 1, ? FROM db_root UNION ALL SELECT n + 1, COALESCE(hv, ?) FROM c WHERE n < 6 AND (hv IS NULL OR hv < 100)) SELECT n, hv, hv IS NULL FROM c ORDER BY n';
EXECUTE s7 USING NULL, 50;
DEALLOCATE PREPARE s7;

-- CONNECT BY 다중 루트 DELETE (tc04, 기대: 에러 없이 13행 삭제 후 COUNT 0)
DELETE FROM t04 WHERE id IN (SELECT id FROM t04 CONNECT BY PRIOR id = pid ORDER SIBLINGS BY name);
SELECT COUNT(*) FROM t04;

-- 페이지 수 감소 (shell): SHOW TRACE 의 임시 리스트 SCAN page: 값 또는 통계
SET TRACE ON;
SELECT i, b FROM t_sz ORDER BY b DESC;
SHOW TRACE;
```

## 시나리오

| ID | 시나리오 | 파라미터/데이터 조건 | 판정 기준 |
| --- | --- | --- | --- |
| T1 | NULL 혼합(첫 고정 컬럼 NULL, 전 컬럼 NULL, 빈 문자열) | tc01_null_mix.sql | 출력이 tc01_null_mix.answer.develop 과 바이트 동일 |
| T2 | 고정 전 타입 + 가변 127/128/129B 경계 + 4KB 가변 | tc02_fixed_var_mix.sql | tc02 answer.develop 과 동일 |
| T3 | 오버플로 튜플(20~30KB 값) 정렬·집계·UNION·재스캔 | tc03_overflow.sql | tc03 answer.develop 과 동일 (RIGHT(v1,3) 등 끝 바이트 일치) |
| T4 | CONNECT BY: ORDER SIBLINGS BY 문자열, 다중 루트 DELETE IN, ISLEAF/ISCYCLE | tc04_connect_by.sql | tc04 answer.develop 과 동일, DELETE 가 에러 없이 성공 |
| T5 | 해시 조인 키 INT/VARCHAR/NUMERIC/복합, 외부 조인 NULL 확장 | tc05_hash_join.sql (3,000행 x 2) | tc05 answer.develop 과 동일 |
| T6 | 분석 함수 정렬키(가변·NULL), PERCENTILE/MEDIAN, GROUP_CONCAT OVER | tc06_analytic.sql | tc06 answer.develop 과 동일 |
| T7 | SET/MULTISET/SEQUENCE/JSON 컬럼, 256B 초과 컬렉션 정렬키 | tc07_set_json.sql | tc07 answer.develop 과 동일 |
| T8 | 늦은 도메인: 호스트 변수 NULL 시작 컬럼, 재귀 CTE 공용 리스트 | tc08_late_domain.sql | 출력이 tc08_late_domain.answer.pr2b-fix 와 동일, 서버 생존(err 로그에 assert/abort 없음) |
| T9 | 73컬럼 리스트, 컬럼 1/65/72 NULL, 70컬럼 DISTINCT | tc09_wide.sql | tc09 answer.develop 과 동일 |
| T10 | ORDERBY_NUM/ROWNUM/ISLEAF/ISCYCLE 이 가변 컬럼 뒤 | tc10_inplace.sql | tc10 answer.develop 과 동일 |
| T11 | JDBC scrollable 커서 previous/absolute/last | ScrollSmoke.java, 임의 100행 테이블 | 표준출력이 expected_scroll.out 과 동일 |
| T12 | 임시 페이지 수 감소 | t_sz 100만 행 ORDER BY b DESC, sort_buffer_size=2M | SHOW TRACE 임시 리스트 SCAN 의 page: 가 변경 전 빌드 대비 20% 이상 감소 (참고: 정렬 데이터 페이지 19,047 → 14,041) |
| T13 | 기존 플랜 텍스트 케이스 유지 | cbrd_23665, cbrd_24148, cbrd_25382_1/_5, cbrd_25447, cbrd_25519, join_orderby_skip | 입력 확대 뒤 변경 전/후 빌드 모두 기존 answer 통과 |

## 주의사항

- tc08 (6)(7) 재귀 CTE 문장은 변경 전 develop 빌드에서 서버가 abort 하므로(`qfile_unify_types` assert_release) `.answer.develop` 은 그 지점에서 끊긴다. tc08 의 기대 답안은 `tc08_late_domain.answer.pr2b-fix` 를 쓴다. 나머지 9건은 두 빌드 출력이 바이트 동일하다.
- 플랜 텍스트(SET TRACE ON / SHOW TRACE 의 `parallel workers`, `BUILD method: hybrid|memory`, `hash temp(h)|(m)`) 는 리스트 페이지 수로 결정되며 이 변경으로 같은 데이터에서 달라질 수 있다. 결과 집합이 아닌 플랜 텍스트를 판정에 쓰는 TC 는 리스트 페이지 수가 임계(병렬 임계 기본 2048 페이지, 해시 조인 in-memory 는 `page_cnt*16KB <= 메모리 한도`)를 확실히 넘거나 넘지 않도록 행 수를 잡는다. T13 의 7 케이스는 입력 확대(6건)와 빌드/프로브 데이터 재설계(cbrd_25382_1: t_bigint 쪽 행 수를 더 적게) 로 원래 플랜을 복원한다.
- 해시 조인·병렬 실행 결과의 행 순서는 비결정적이므로 모든 판정 SQL 에 ORDER BY 를 둔다(첨부 TC 는 전부 포함).
- 준비 문장의 BIT_AND/BIT_OR/BIT_XOR 결과 타입이 BIGINT 로 통일되어 기존 `agg_group_by` 답안이 갱신된다. 이는 의도된 정정이다.
- ORDER SIBLINGS BY 문자열 형제 순서, 정렬 동치 클래스 내 순서는 변경 전과 같아야 하며, 다르면 결함이다(정렬 비교자 라우팅 회귀).
