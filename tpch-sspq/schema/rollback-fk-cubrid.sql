-- Use only to roll back a failed bootstrap before measurements exist.
ALTER TABLE LINEITEM DROP FOREIGN KEY fk_lineitem_partsupp;
ALTER TABLE LINEITEM DROP FOREIGN KEY fk_lineitem_orders;
ALTER TABLE ORDERS DROP FOREIGN KEY fk_orders_customer;
ALTER TABLE PARTSUPP DROP FOREIGN KEY fk_partsupp_part;
ALTER TABLE PARTSUPP DROP FOREIGN KEY fk_partsupp_supplier;
ALTER TABLE CUSTOMER DROP FOREIGN KEY fk_customer_nation;
ALTER TABLE SUPPLIER DROP FOREIGN KEY fk_supplier_nation;
ALTER TABLE NATION DROP FOREIGN KEY fk_nation_region;

