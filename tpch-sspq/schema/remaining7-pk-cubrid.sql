-- tpch-sspq G1 asset — CUBRID PRIMARY KEYs for the seven tables other than
-- LINEITEM. Verbatim from the "Primary Keys" section of the canonical
-- ~/dev/cubrid/.vscode/TPC-H/scale10/create_tpch_index.sql, minus the LINEITEM
-- line (already built during the Q1 pilot as
-- pk_lineitem_l_orderkey_l_linenumber).
--
-- Applied AFTER loaddb, not before: the pilot established that order for
-- LINEITEM and it is kept here so all eight tables were indexed the same way.
--
-- The FOREIGN KEY section of create_tpch_index.sql is omitted in full, on both
-- engines. Rationale in remaining7-cubrid.sql's header.

ALTER TABLE REGION   ADD PRIMARY KEY (R_REGIONKEY);
ALTER TABLE NATION   ADD PRIMARY KEY (N_NATIONKEY);
ALTER TABLE PART     ADD PRIMARY KEY (P_PARTKEY);
ALTER TABLE SUPPLIER ADD PRIMARY KEY (S_SUPPKEY);
ALTER TABLE PARTSUPP ADD PRIMARY KEY (PS_PARTKEY, PS_SUPPKEY);
ALTER TABLE CUSTOMER ADD PRIMARY KEY (C_CUSTKEY);
ALTER TABLE ORDERS   ADD PRIMARY KEY (O_ORDERKEY);
