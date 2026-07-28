-- tpch-sspq G1 Q1 pilot — CUBRID lineitem schema.
-- Verbatim extract of the LINEITEM block from the canonical
-- ~/dev/cubrid/.vscode/TPC-H/scale10/create_tpch_table.sql, plus the LINEITEM
-- PRIMARY KEY from create_tpch_index.sql. No type or precision change.
--
-- Omitted on purpose for the Q1-only pilot:
--   * the other 7 TPC-H tables (Q1 reads lineitem only);
--   * the two LINEITEM FOREIGN KEYs (they reference ORDERS / PARTSUPP, which
--     are not loaded). FKs are not usable by Q1's plan.

DROP TABLE IF EXISTS LINEITEM;

CREATE TABLE LINEITEM (
    L_ORDERKEY      INTEGER       NOT NULL,
    L_PARTKEY       INTEGER       NOT NULL,
    L_SUPPKEY       INTEGER       NOT NULL,
    L_LINENUMBER    INTEGER       NOT NULL,
    L_QUANTITY      DECIMAL(15,2) NOT NULL,
    L_EXTENDEDPRICE DECIMAL(15,2) NOT NULL,
    L_DISCOUNT      DECIMAL(15,2) NOT NULL,
    L_TAX           DECIMAL(15,2) NOT NULL,
    L_RETURNFLAG    CHAR(1)       NOT NULL,
    L_LINESTATUS    CHAR(1)       NOT NULL,
    L_SHIPDATE      DATE          NOT NULL,
    L_COMMITDATE    DATE          NOT NULL,
    L_RECEIPTDATE   DATE          NOT NULL,
    L_SHIPINSTRUCT  CHAR(25)      NOT NULL,
    L_SHIPMODE      CHAR(10)      NOT NULL,
    L_COMMENT       VARCHAR(44)   NOT NULL
);
