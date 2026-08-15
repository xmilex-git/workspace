;autocommit off
-- s07: trigger-driven DML. The t_order insert fires trg_order_audit which
-- inserts into t_audit. Does the audit insert surface as TRIGGER_INSERT
-- (dml_type=3) or a plain INSERT, and inside the same txn?
INSERT INTO t_order VALUES (1, 'alice', 123.4567, SYSDATETIME);
COMMIT;
