-- tpch-sspq G1 asset — CUBRID schema for the seven tables other than LINEITEM.
--
-- Verbatim extract of the REGION / NATION / PART / SUPPLIER / PARTSUPP /
-- CUSTOMER / ORDERS blocks of the canonical
-- ~/dev/cubrid/.vscode/TPC-H/scale10/create_tpch_table.sql (ADR 0004), plus the
-- matching PRIMARY KEYs from create_tpch_index.sql. No type, precision or
-- nullability change. Column order is the canonical order.
--
-- LINEITEM IS DELIBERATELY ABSENT, INCLUDING FROM THE DROP LIST.
-- It was loaded during the Q1 pilot under this same pinned build and must never
-- be dropped or reloaded (12,254 MB, 59,986,052 rows). Re-running this file
-- rebuilds the other seven tables only.
--
-- Index parity rule (fixed by the Q1 pilot, see docs/report-g1-q1-pilot-*.md
-- section 7): PRIMARY KEYs only. Every FOREIGN KEY in create_tpch_index.sql is
-- omitted, on BOTH engines, because CUBRID materialises a btree for a foreign
-- key while PostgreSQL does not -- keeping the FKs would hand CUBRID indexes
-- PostgreSQL has no counterpart for. Omitting them symmetrically removes an
-- asymmetry instead of creating one. No secondary index is created on either
-- engine.
--
-- Deliberately NOT set: no reuse_oid, no partitioning, no per-table
-- parallelism/storage override. Plain heap tables so the parallel-execution
-- decision is left entirely to the optimizer.

DROP TABLE IF EXISTS ORDERS;
DROP TABLE IF EXISTS PARTSUPP;
DROP TABLE IF EXISTS CUSTOMER;
DROP TABLE IF EXISTS SUPPLIER;
DROP TABLE IF EXISTS PART;
DROP TABLE IF EXISTS NATION;
DROP TABLE IF EXISTS REGION;

CREATE TABLE REGION (
    R_REGIONKEY  INTEGER       NOT NULL,
    R_NAME       CHAR(25)      NOT NULL,
    R_COMMENT    VARCHAR(152)
);

CREATE TABLE NATION (
    N_NATIONKEY  INTEGER       NOT NULL,
    N_NAME       CHAR(25)      NOT NULL,
    N_REGIONKEY  INTEGER       NOT NULL,
    N_COMMENT    VARCHAR(152)
);

CREATE TABLE PART (
    P_PARTKEY     INTEGER       NOT NULL,
    P_NAME        VARCHAR(55)   NOT NULL,
    P_MFGR        CHAR(25)      NOT NULL,
    P_BRAND       CHAR(10)      NOT NULL,
    P_TYPE        VARCHAR(25)   NOT NULL,
    P_SIZE        INTEGER       NOT NULL,
    P_CONTAINER   CHAR(10)      NOT NULL,
    P_RETAILPRICE DECIMAL(15,2) NOT NULL,
    P_COMMENT     VARCHAR(23)   NOT NULL
);

CREATE TABLE SUPPLIER (
    S_SUPPKEY   INTEGER       NOT NULL,
    S_NAME      CHAR(25)      NOT NULL,
    S_ADDRESS   VARCHAR(40)   NOT NULL,
    S_NATIONKEY INTEGER       NOT NULL,
    S_PHONE     CHAR(15)      NOT NULL,
    S_ACCTBAL   DECIMAL(15,2) NOT NULL,
    S_COMMENT   VARCHAR(101)  NOT NULL
);

CREATE TABLE PARTSUPP (
    PS_PARTKEY    INTEGER       NOT NULL,
    PS_SUPPKEY    INTEGER       NOT NULL,
    PS_AVAILQTY   INTEGER       NOT NULL,
    PS_SUPPLYCOST DECIMAL(15,2) NOT NULL,
    PS_COMMENT    VARCHAR(199)  NOT NULL
);

CREATE TABLE CUSTOMER (
    C_CUSTKEY    INTEGER       NOT NULL,
    C_NAME       VARCHAR(25)   NOT NULL,
    C_ADDRESS    VARCHAR(40)   NOT NULL,
    C_NATIONKEY  INTEGER       NOT NULL,
    C_PHONE      CHAR(15)      NOT NULL,
    C_ACCTBAL    DECIMAL(15,2) NOT NULL,
    C_MKTSEGMENT CHAR(10)      NOT NULL,
    C_COMMENT    VARCHAR(117)  NOT NULL
);

CREATE TABLE ORDERS (
    O_ORDERKEY      INTEGER       NOT NULL,
    O_CUSTKEY       INTEGER       NOT NULL,
    O_ORDERSTATUS   CHAR(1)       NOT NULL,
    O_TOTALPRICE    DECIMAL(15,2) NOT NULL,
    O_ORDERDATE     DATE          NOT NULL,
    O_ORDERPRIORITY CHAR(15)      NOT NULL,
    O_CLERK         CHAR(15)      NOT NULL,
    O_SHIPPRIORITY  INTEGER       NOT NULL,
    O_COMMENT       VARCHAR(79)   NOT NULL
);
