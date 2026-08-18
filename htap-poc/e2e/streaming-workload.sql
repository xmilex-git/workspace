;autocommit off
-- E2E #40 streaming workload: run AFTER the connector has entered streaming
-- (write resume, ADR 0005 checklist step 6). Covers I/U/D x COMMIT/ABORT and
-- every §7.7 convergence case. savepoint partial rollback is excluded by
-- decision (ADR 0004 — known limitation).

-- [T1] committed insert + update of a snapshot-era row (barrier gap check)
INSERT INTO t_order VALUES (3, 'carol', 7.7700, DATETIME'2026-08-16 11:00:00.000');
UPDATE t_order SET customer = 'bob-streamed' WHERE id = 2;
COMMIT;

-- [T2] ABORT: none of this may ever reach ClickHouse
INSERT INTO t_order VALUES (99, 'ghost', 1.0000, NULL);
UPDATE t_order SET customer = 'never' WHERE id = 1;
DELETE FROM t_item WHERE sku = 'SKU-A';
ROLLBACK;

-- [T3] same-PK multiple updates in one txn -> converge to the last (§7.7 I->U)
UPDATE t_item SET price = 21.00 WHERE sku = 'SKU-A';
UPDATE t_item SET price = 22.00 WHERE sku = 'SKU-A';
UPDATE t_item SET price = 23.00 WHERE sku = 'SKU-A';
COMMIT;

-- [T4] insert -> delete in one txn -> no row (§7.7)
INSERT INTO t_order VALUES (4, 'dave', 4.0000, DATETIME'2026-08-16 11:04:00.000');
DELETE FROM t_order WHERE id = 4;
COMMIT;

-- [T5] delete -> insert in one txn -> the new row (§7.7)
DELETE FROM t_item WHERE sku = 'SKU-B';
INSERT INTO t_item VALUES ('SKU-B', 77, 0.50);
COMMIT;

-- [T6] PK change -> old PK tombstone + new PK insert (§7.7)
UPDATE t_order SET id = 5 WHERE id = 3;
COMMIT;

-- [T7] insert and delete across two committed txns -> no row
INSERT INTO t_item VALUES ('SKU-C', 1, 9.99);
COMMIT;
DELETE FROM t_item WHERE sku = 'SKU-C';
COMMIT;

-- [T8] #58 type corpus, streaming path: boundary I/U/D + NULL flips
INSERT INTO t_typecorpus VALUES (5, -32768, -9223372036854775808,
  -9999999999999999999999999999.9999999999, -99999999999.9999,
  1.175494e-38, 2.2250738585072014e-308,
  'a', '', DATE'1600-01-01', TIME'00:00:00',
  TIMESTAMP'1970-01-01 09:00:01', DATETIME'1900-01-01 00:00:00.000', 'red');
INSERT INTO t_typecorpus VALUES (6, 32767, 9223372036854775807,
  9999999999999999999999999999.9999999999, 99999999999.9999,
  3.402823e+38, 1.7976931348623157e+308,
  '0123456789', REPEAT('y', 255), DATE'9999-12-31', TIME'23:59:59',
  TIMESTAMP'2038-01-19 12:14:07', DATETIME'2299-12-31 23:59:59.999', 'blue');
INSERT INTO t_typecorpus VALUES (7, NULL, NULL, NULL, NULL, NULL, NULL,
  NULL, NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO t_typecorpus VALUES (8, 1, 1, 1, 1, 1, 1, 'gone', 'gone',
  DATE'2026-01-01', TIME'01:02:03',
  TIMESTAMP'2026-01-01 01:02:03', DATETIME'2026-01-01 01:02:03.004', 'red');
COMMIT;
-- boundary flip: min row -> max values (every column through cond⊕changed merge)
UPDATE t_typecorpus SET v_short = 32767, v_bigint = 9223372036854775807,
  v_num = 9999999999999999999999999999.9999999999, v_num2 = 99999999999.9999,
  v_float = 3.402823e+38, v_double = 1.7976931348623157e+308,
  v_char = '한글패딩', v_varchar = '유니코드로 갱신', v_date = DATE'2028-02-29',
  v_time = TIME'23:59:59', v_ts = TIMESTAMP'2038-01-19 12:14:07',
  v_dtm = DATETIME'2299-12-31 23:59:59.999', v_enum = 'green' WHERE id = 5;
-- values -> NULL and NULL -> values
UPDATE t_typecorpus SET v_short = NULL, v_bigint = NULL, v_num = NULL,
  v_num2 = NULL, v_float = NULL, v_double = NULL, v_char = NULL,
  v_varchar = NULL, v_date = NULL, v_time = NULL, v_ts = NULL, v_dtm = NULL,
  v_enum = NULL WHERE id = 6;
UPDATE t_typecorpus SET v_varchar = '', v_num = 0.0000000001,
  v_dtm = DATETIME'1900-01-01 00:00:00.000' WHERE id = 7;
DELETE FROM t_typecorpus WHERE id = 8;
COMMIT;
-- aborted corpus txn: must never land
INSERT INTO t_typecorpus VALUES (99, 9, 9, 9, 9, 9, 9, 'ghost', 'ghost',
  DATE'2026-01-01', TIME'09:09:09',
  TIMESTAMP'2026-01-01 09:09:09', DATETIME'2026-01-01 09:09:09.009', 'blue');
UPDATE t_typecorpus SET v_varchar = 'never' WHERE id = 5;
ROLLBACK;
