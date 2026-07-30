-- Use only to roll back a failed bootstrap before measurements exist.
BEGIN;
ALTER TABLE lineitem DROP CONSTRAINT IF EXISTS fk_lineitem_partsupp;
ALTER TABLE lineitem DROP CONSTRAINT IF EXISTS fk_lineitem_orders;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS fk_orders_customer;
ALTER TABLE partsupp DROP CONSTRAINT IF EXISTS fk_partsupp_part;
ALTER TABLE partsupp DROP CONSTRAINT IF EXISTS fk_partsupp_supplier;
ALTER TABLE customer DROP CONSTRAINT IF EXISTS fk_customer_nation;
ALTER TABLE supplier DROP CONSTRAINT IF EXISTS fk_supplier_nation;
ALTER TABLE nation DROP CONSTRAINT IF EXISTS fk_nation_region;
DROP INDEX IF EXISTS idx_fk_lineitem_partsupp;
DROP INDEX IF EXISTS idx_fk_lineitem_orders;
DROP INDEX IF EXISTS idx_fk_orders_customer;
DROP INDEX IF EXISTS idx_fk_partsupp_part;
DROP INDEX IF EXISTS idx_fk_partsupp_supplier;
DROP INDEX IF EXISTS idx_fk_customer_nation;
DROP INDEX IF EXISTS idx_fk_supplier_nation;
DROP INDEX IF EXISTS idx_fk_nation_region;
COMMIT;

