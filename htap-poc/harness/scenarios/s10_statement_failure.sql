;autocommit off
-- s10: statement-level failure inside a surviving txn (#42 judgment probe).
-- Stmt 2 is a multi-row INSERT whose 2nd row violates the PK -> the statement
-- fails and is rolled back (internal savepoint), but the txn continues and
-- COMMITs. Committed truth: STF-A(qty=1) and STF-C only. The stream, however,
-- carries the failed statement's partial DML (STF-B, and a second STF-A with
-- qty=3) with no compensation -> phantom row + higher-_version corruption of
-- an existing row. Same root cause as s06, no explicit SAVEPOINT needed.
INSERT INTO t_item VALUES ('SKU-STF-A', 1, 10.00);
INSERT INTO t_item VALUES ('SKU-STF-B', 2, 20.00), ('SKU-STF-A', 3, 30.00);
INSERT INTO t_item VALUES ('SKU-STF-C', 4, 40.00);
COMMIT;
