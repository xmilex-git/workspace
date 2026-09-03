-- CBRD-27365 smoke — 임시 리스트 파일(qfile) 튜플 포맷을 한 번씩 건드리는 경량 csql 스크립트.
-- 목표 1분 이내. 실행/비교: run_smoke.sh (csql 출력의 "(N sec)" 타이밍을 제거한 뒤 expected.out 과 diff).
-- 항목: [1] NULL 혼합 정렬  [2] 고정/가변 혼합 GROUP BY  [3] 늦은 도메인(DB_TYPE_VARIABLE→확정) UNION
--       [4] 오버플로 튜플(>16K)  [5] CONNECT BY ISLEAF/ISCYCLE/parent_pos  [6] 해시조인 USE_HASH
--       [7] 머지조인 USE_MERGE(hidden 파라미터 on)  [8] 분석함수 group/value 리스트  [9] ORDERBY_NUM/ROWNUM in-place
--       [10] SET/JSON 가변 값  [11] DISTINCT(list unify)  [12] 64+ 컬럼 튜플
--       역방향 커서는 csql로 불가 → ScrollSmoke.java (JDBC TYPE_SCROLL_INSENSITIVE) 로 별도 1회.

DROP TABLE IF EXISTS t_mix;
DROP TABLE IF EXISTS t_dim;
DROP TABLE IF EXISTS t_tree;
DROP TABLE IF EXISTS t_seq;

CREATE TABLE t_mix (
  id   INT PRIMARY KEY,
  i2   SMALLINT,
  b8   BIGINT,
  d8   DOUBLE,
  f4   FLOAT,
  n    NUMERIC(20,4),
  c5   CHAR(5),
  v    VARCHAR(100),
  bt   BIT(16),
  vb   BIT VARYING(64),
  dt   DATE,
  dtm  DATETIME,
  s    SET(INT),
  j    JSON
);

-- 20행. id%3=0 → 일부 NULL, id%7=0 → id 외 전부 NULL, 나머지는 전부 bound.
-- id 는 실체 테이블(t_seq)을 경유해 생성한다: ROWNUM 이 파생 서브쿼리 컬럼에 남긴 채
-- "INST_NUM()/ROWNUM not allowed in this context" 표식이 JSON_OBJECT 인자에서 걸리기 때문
-- (CUBRID 기존 제약, CBRD-27365 대상 아님).
CREATE TABLE t_seq (id INT);
INSERT INTO t_seq SELECT ROWNUM FROM db_class LIMIT 20;
INSERT INTO t_mix
SELECT id,
       CASE WHEN id % 7 = 0 THEN NULL WHEN id % 3 = 0 THEN NULL ELSE id % 4 END,
       CASE WHEN id % 7 = 0 THEN NULL ELSE 4000000000 + id END,
       CASE WHEN id % 7 = 0 THEN NULL WHEN id % 3 = 0 THEN NULL ELSE id * 1.5 END,
       CASE WHEN id % 7 = 0 THEN NULL ELSE id * 0.25 END,
       CASE WHEN id % 7 = 0 THEN NULL ELSE id * 1234.5678 END,
       CASE WHEN id % 7 = 0 THEN NULL WHEN id % 3 = 0 THEN NULL ELSE 'c' || id END,
       CASE WHEN id % 7 = 0 THEN NULL ELSE REPEAT('v', id) END,
       CASE WHEN id % 7 = 0 THEN NULL ELSE B'1010101010101010' END,
       CASE WHEN id % 7 = 0 THEN NULL WHEN id % 3 = 0 THEN NULL ELSE B'1' END,
       CASE WHEN id % 7 = 0 THEN NULL ELSE DATE'2026-01-01' + id END,
       CASE WHEN id % 7 = 0 THEN NULL WHEN id % 3 = 0 THEN NULL ELSE DATETIME'2026-01-01 00:00:00.000' + id END,
       CASE WHEN id % 7 = 0 THEN NULL ELSE {id, id + 100} END,
       CASE WHEN id % 7 = 0 THEN NULL WHEN id % 3 = 0 THEN NULL ELSE JSON_OBJECT('k', id, 'arr', JSON_ARRAY(id, 'x')) END
FROM t_seq;

CREATE TABLE t_dim (id INT, name VARCHAR(20));
INSERT INTO t_dim VALUES (1,'one'),(2,'two'),(3,'three'),(4,NULL),(5,'five'),(2,'two-dup'),(NULL,'nullkey');

CREATE TABLE t_tree (id INT, pid INT, name VARCHAR(10));
INSERT INTO t_tree VALUES (1,NULL,'root'),(2,1,'a'),(3,1,'b'),(4,2,'aa'),(5,2,'ab'),(6,3,'ba'),(7,4,'aaa'),(8,7,'cyc');
-- 사이클: 7 → 8 → 7
UPDATE t_tree SET pid = 8 WHERE id = 7;

-- [1] NULL 혼합 정렬 (고정폭 NULL 컬럼이 앞에 오는 튜플)
SELECT id, i2, b8, d8, f4, n, c5, v, bt, vb, dt, dtm FROM t_mix ORDER BY d8 DESC NULLS LAST, id;

-- [2] 고정/가변 혼합 GROUP BY (NULL 그룹 포함, 집계 튜플 in-place 누산)
SELECT i2, COUNT(*), COUNT(v), SUM(b8), AVG(d8), MIN(v), MAX(c5), SUM(n) FROM t_mix GROUP BY i2 ORDER BY i2 NULLS FIRST;

-- [3] 늦은 도메인: 첫 브랜치는 NULL만 → DB_TYPE_VARIABLE 로 열리고 두 번째 브랜치에서 확정
SELECT x, LENGTH(x) FROM (SELECT NULL AS x FROM t_mix WHERE id <= 3 UNION ALL SELECT v FROM t_mix WHERE id BETWEEN 4 AND 9) u ORDER BY x NULLS FIRST;

-- [4] 오버플로 튜플 (40,000B > 16K 페이지) 정렬 통과
SELECT id, LENGTH(big), SUBSTR(big, 39995, 10) FROM (SELECT id, REPEAT('x', 39999) || CAST(id AS VARCHAR) AS big FROM t_mix WHERE id <= 3) o ORDER BY id DESC;

-- [5] CONNECT BY: ISLEAF/ISCYCLE/parent_pos in-place 덮어쓰기 경로
SELECT LEVEL, id, pid, name, CONNECT_BY_ISLEAF, CONNECT_BY_ISCYCLE, SYS_CONNECT_BY_PATH(name, '/') AS path
FROM t_tree START WITH pid IS NULL CONNECT BY NOCYCLE PRIOR id = pid ORDER SIBLINGS BY id;

-- [6] 해시조인 (NULL 키·중복 키 포함)
SELECT /*+ USE_HASH RECOMPILE */ m.id, m.v, d.name FROM t_mix m INNER JOIN t_dim d ON m.i2 = d.id ORDER BY m.id, d.name;
SELECT /*+ USE_HASH RECOMPILE */ m.id, d.name FROM t_mix m LEFT OUTER JOIN t_dim d ON m.i2 = d.id ORDER BY m.id, d.name;

-- [7] 머지조인 (MERGELIST outer/inner 리스트 = backward 대상, hidden 파라미터로 활성화)
SET SYSTEM PARAMETERS 'optimizer_enable_merge_join=yes';
SELECT /*+ USE_MERGE RECOMPILE */ m.id, m.v, d.name FROM t_mix m INNER JOIN t_dim d ON m.i2 = d.id ORDER BY m.id, d.name;
SET SYSTEM PARAMETERS 'optimizer_enable_merge_join=no';

-- [8] 분석함수: 파티션(NULL 파티션 포함)·정렬키·LAG
SELECT id, i2, SUM(b8) OVER (PARTITION BY i2 ORDER BY id) AS rs,
       ROW_NUMBER() OVER (ORDER BY d8 DESC NULLS LAST, id) AS rn,
       LAG(v) OVER (ORDER BY id) AS prev_v,
       NTILE(3) OVER (ORDER BY id) AS nt
FROM t_mix ORDER BY id;

-- [9] ORDERBY_NUM / ROWNUM(inst_num) in-place 재기록
SELECT id, v FROM t_mix ORDER BY v NULLS LAST FOR ORDERBY_NUM() BETWEEN 3 AND 6;
SELECT ROWNUM AS rn, id FROM (SELECT id FROM t_mix ORDER BY id DESC) x WHERE ROWNUM <= 4;

-- [10] SET / JSON 가변 값이 정렬 리스트를 통과
SELECT id, s, j FROM t_mix WHERE id BETWEEN 1 AND 8 ORDER BY id DESC;

-- [11] DISTINCT (list unify) + NULL
SELECT DISTINCT i2, c5 IS NULL AS c5null FROM t_mix ORDER BY 1 NULLS FIRST, 2;

-- [12] 64+ 컬럼 튜플 (비트맵 2워드 이상)
SELECT id,
 i2 AS c01,i2 AS c02,i2 AS c03,i2 AS c04,i2 AS c05,i2 AS c06,i2 AS c07,i2 AS c08,i2 AS c09,i2 AS c10,
 v  AS c11,v  AS c12,v  AS c13,v  AS c14,v  AS c15,v  AS c16,v  AS c17,v  AS c18,v  AS c19,v  AS c20,
 b8 AS c21,b8 AS c22,b8 AS c23,b8 AS c24,b8 AS c25,b8 AS c26,b8 AS c27,b8 AS c28,b8 AS c29,b8 AS c30,
 d8 AS c31,d8 AS c32,d8 AS c33,d8 AS c34,d8 AS c35,d8 AS c36,d8 AS c37,d8 AS c38,d8 AS c39,d8 AS c40,
 c5 AS c41,c5 AS c42,c5 AS c43,c5 AS c44,c5 AS c45,c5 AS c46,c5 AS c47,c5 AS c48,c5 AS c49,c5 AS c50,
 n  AS c51,n  AS c52,n  AS c53,n  AS c54,n  AS c55,n  AS c56,n  AS c57,n  AS c58,n  AS c59,n  AS c60,
 dt AS c61,dt AS c62,dt AS c63,dt AS c64,dt AS c65,dt AS c66,dt AS c67,dt AS c68,dt AS c69,dt AS c70
FROM t_mix WHERE id IN (1, 3, 7, 20) ORDER BY id DESC;

DROP TABLE t_mix;
DROP TABLE t_dim;
DROP TABLE t_tree;
DROP TABLE t_seq;
