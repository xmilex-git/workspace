;autocommit off
-- s06: savepoint partial rollback -> commit.
-- SKU-SP1 must survive, SKU-SP2 must not. How does the stream represent
-- the partially-rolled-back middle?
INSERT INTO t_item VALUES ('SKU-SP1', 1, 10.00);
SAVEPOINT sp1;
INSERT INTO t_item VALUES ('SKU-SP2', 2, 20.00);
UPDATE t_item SET qty = 100 WHERE sku = 'SKU-SP1';
ROLLBACK WORK TO SAVEPOINT sp1;
COMMIT;
