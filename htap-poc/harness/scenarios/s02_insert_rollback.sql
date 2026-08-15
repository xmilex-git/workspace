;autocommit off
-- s02: insert -> rollback. Does the aborted insert appear in the CDC stream
-- at all, and does an ABORT DCL close the txn?
INSERT INTO t_item VALUES ('SKU-ROLLBACK', 99, 1.00);
ROLLBACK;
