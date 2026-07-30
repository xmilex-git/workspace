-- Campaign: tpch-sspq-fk-r1-20260730
-- PostgreSQL does not create referencing-column indexes for FOREIGN KEY.
-- The explicit btrees below mirror the eight CUBRID FK indexes exactly.
-- Apply only after the SSOT schema preflight reports no conflicting objects.

BEGIN;

ALTER TABLE nation
  ADD CONSTRAINT fk_nation_region
  FOREIGN KEY (n_regionkey) REFERENCES region (r_regionkey);
CREATE INDEX idx_fk_nation_region
  ON nation USING btree (n_regionkey);

ALTER TABLE supplier
  ADD CONSTRAINT fk_supplier_nation
  FOREIGN KEY (s_nationkey) REFERENCES nation (n_nationkey);
CREATE INDEX idx_fk_supplier_nation
  ON supplier USING btree (s_nationkey);

ALTER TABLE customer
  ADD CONSTRAINT fk_customer_nation
  FOREIGN KEY (c_nationkey) REFERENCES nation (n_nationkey);
CREATE INDEX idx_fk_customer_nation
  ON customer USING btree (c_nationkey);

ALTER TABLE partsupp
  ADD CONSTRAINT fk_partsupp_supplier
  FOREIGN KEY (ps_suppkey) REFERENCES supplier (s_suppkey);
CREATE INDEX idx_fk_partsupp_supplier
  ON partsupp USING btree (ps_suppkey);

ALTER TABLE partsupp
  ADD CONSTRAINT fk_partsupp_part
  FOREIGN KEY (ps_partkey) REFERENCES part (p_partkey);
CREATE INDEX idx_fk_partsupp_part
  ON partsupp USING btree (ps_partkey);

ALTER TABLE orders
  ADD CONSTRAINT fk_orders_customer
  FOREIGN KEY (o_custkey) REFERENCES customer (c_custkey);
CREATE INDEX idx_fk_orders_customer
  ON orders USING btree (o_custkey);

ALTER TABLE lineitem
  ADD CONSTRAINT fk_lineitem_orders
  FOREIGN KEY (l_orderkey) REFERENCES orders (o_orderkey);
CREATE INDEX idx_fk_lineitem_orders
  ON lineitem USING btree (l_orderkey);

ALTER TABLE lineitem
  ADD CONSTRAINT fk_lineitem_partsupp
  FOREIGN KEY (l_partkey, l_suppkey)
  REFERENCES partsupp (ps_partkey, ps_suppkey);
CREATE INDEX idx_fk_lineitem_partsupp
  ON lineitem USING btree (l_partkey, l_suppkey);

COMMIT;

