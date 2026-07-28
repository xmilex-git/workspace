-- tpch-sspq G1 asset — PostgreSQL PRIMARY KEYs for the seven tables other than
-- lineitem. Derived one-for-one from the "Primary Keys" section of the canonical
-- ~/dev/cubrid/.vscode/TPC-H/scale10/create_tpch_index.sql, minus the LINEITEM
-- line (already built during the Q1 pilot as lineitem_pkey).
--
-- Same key columns in the same order as the CUBRID side. PostgreSQL implements a
-- PRIMARY KEY as a unique btree, which is what CUBRID does too, so the resulting
-- index sets match one for one.
--
-- Applied AFTER the COPY, matching the CUBRID side's loaddb-then-index order.
--
-- The FOREIGN KEY section of create_tpch_index.sql is omitted in full, on both
-- engines. Rationale in remaining7-pg.sql's header.

ALTER TABLE region   ADD PRIMARY KEY (r_regionkey);
ALTER TABLE nation   ADD PRIMARY KEY (n_nationkey);
ALTER TABLE part     ADD PRIMARY KEY (p_partkey);
ALTER TABLE supplier ADD PRIMARY KEY (s_suppkey);
ALTER TABLE partsupp ADD PRIMARY KEY (ps_partkey, ps_suppkey);
ALTER TABLE customer ADD PRIMARY KEY (c_custkey);
ALTER TABLE orders   ADD PRIMARY KEY (o_orderkey);
