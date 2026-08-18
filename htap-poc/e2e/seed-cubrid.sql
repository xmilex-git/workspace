-- E2E #40: pre-snapshot state. Executed under the operator write stop
-- (ADR 0005 checklist step 1) — after this script NOTHING writes to the
-- captured tables until verify-e2e.sh confirms streaming has begun.
-- Recreating the tables gives the run a deterministic classoid->schema state.
DROP TABLE IF EXISTS t_order;
DROP TABLE IF EXISTS t_item;

CREATE TABLE t_order (
  id         INT PRIMARY KEY,
  customer   VARCHAR(64),
  amount     DECIMAL(15,4),
  created_at DATETIME
);

CREATE TABLE t_item (
  sku   VARCHAR(32) PRIMARY KEY,
  qty   INT,
  price DECIMAL(10,2)
);

-- snapshot content; id=2 / SKU-A / SKU-B are also the barrier-boundary rows the
-- streaming workload touches first (gap check: snapshot row + CDC update must
-- converge to the CDC value, _version 0 < any counter)
INSERT INTO t_order VALUES (1, 'alice', 100.0000, DATETIME'2026-08-16 10:00:00.000');
INSERT INTO t_order VALUES (2, 'bob',    20.5000, DATETIME'2026-08-16 10:01:00.000');
INSERT INTO t_item  VALUES ('SKU-A', 10,   19.99);
INSERT INTO t_item  VALUES ('SKU-B',  5, 2500.00);

-- #58 type-mapping boundary corpus — supported types only (see connector
-- docs/type-support.md; MONETARY/BIT/TZ/collections/LOB/JSON are excluded).
-- DATE values stay >= 1583: CUBRID's pre-Gregorian day arithmetic is Julian
-- while Debezium epoch-days are proleptic Gregorian (measured 2-day skew at
-- year 1). DATETIME/TIMESTAMP stay inside DateTime64(3) [1900, 2299].
DROP TABLE IF EXISTS t_typecorpus;
CREATE TABLE t_typecorpus (
  id        INT PRIMARY KEY,
  v_short   SMALLINT,
  v_bigint  BIGINT,
  v_num     NUMERIC(38,10),
  v_num2    NUMERIC(15,4),
  v_float   FLOAT,
  v_double  DOUBLE,
  v_char    CHAR(10),
  v_varchar VARCHAR(255),
  v_date    DATE,
  v_time    TIME,
  v_ts      TIMESTAMP,
  v_dtm     DATETIME,
  v_enum    ENUM('red','green','blue')
);
-- snapshot-path rows: minima / maxima / zero+unicode+leap / all-NULL
INSERT INTO t_typecorpus VALUES (1, -32768, -9223372036854775808,
  -9999999999999999999999999999.9999999999, -99999999999.9999,
  1.175494e-38, 2.2250738585072014e-308,
  'a', '', DATE'1600-01-01', TIME'00:00:00',
  TIMESTAMP'1970-01-01 09:00:01', DATETIME'1900-01-01 00:00:00.000', 'red');
INSERT INTO t_typecorpus VALUES (2, 32767, 9223372036854775807,
  9999999999999999999999999999.9999999999, 99999999999.9999,
  3.402823e+38, 1.7976931348623157e+308,
  '0123456789', REPEAT('x', 255), DATE'9999-12-31', TIME'23:59:59',
  TIMESTAMP'2038-01-19 12:14:07', DATETIME'2299-12-31 23:59:59.999', 'blue');
INSERT INTO t_typecorpus VALUES (3, 0, 0, 0, 0.0001, 0, 0,
  '한글패딩', '유니코드 문자열 — quotes ''single'' "double" 세미콜론; 백슬래시 \',
  DATE'2028-02-29', TIME'12:00:00',
  TIMESTAMP'2026-08-16 10:00:00', DATETIME'2026-08-16 10:00:00.001', 'green');
INSERT INTO t_typecorpus VALUES (4, NULL, NULL, NULL, NULL, NULL, NULL,
  NULL, NULL, NULL, NULL, NULL, NULL, NULL);
