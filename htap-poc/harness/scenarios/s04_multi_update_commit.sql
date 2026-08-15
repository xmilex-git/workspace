;autocommit off
-- s04: same-PK multiple updates in one txn -> commit.
-- Each UPDATE touches ONLY price — this is the full-image probe:
-- do changed columns contain all columns or just price? what lands in
-- cond columns (PK only? full before-image? all_in_cond dependent)?
UPDATE t_item SET price = 21.00 WHERE sku = 'SKU-0001';
UPDATE t_item SET price = 22.00 WHERE sku = 'SKU-0001';
UPDATE t_item SET price = 23.00 WHERE sku = 'SKU-0001';
COMMIT;
