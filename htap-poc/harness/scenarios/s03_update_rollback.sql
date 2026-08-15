;autocommit off
-- s03: update -> rollback (row from s01)
UPDATE t_item SET qty = 999 WHERE sku = 'SKU-0001';
ROLLBACK;
