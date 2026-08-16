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
