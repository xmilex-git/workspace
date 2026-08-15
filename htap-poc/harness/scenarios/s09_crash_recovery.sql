;autocommit off
-- s09: DML in flight when cub_server is killed (no COMMIT ever sent).
-- Recovery must undo this txn on restart; the question (ticket #44 /
-- ADR 0004 premise 2) is whether an ABORT DCL for it appears in the
-- CDC stream afterwards. Driven by s09_crash_recovery.sh, not by
-- run_scenarios.sh — the session must stay open while the server dies.
INSERT INTO t_item VALUES ('SKU-CRASH-1', 901, 9.01);
INSERT INTO t_item VALUES ('SKU-CRASH-2', 902, 9.02);
UPDATE t_item SET price = price + 0.5 WHERE sku = 'SKU-CRASH-1';
