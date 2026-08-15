;autocommit off
-- s01: plain insert -> commit (t_item avoids the t_order trigger)
INSERT INTO t_item VALUES ('SKU-0001', 10, 19.99);
INSERT INTO t_item VALUES ('SKU-0002', 5, 2500.00);
COMMIT;
