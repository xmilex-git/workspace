-- tpch-sspq G1 asset — PostgreSQL schema for the seven tables other than
-- lineitem.
--
-- Derived from the REGION / NATION / PART / SUPPLIER / PARTSUPP / CUSTOMER /
-- ORDERS blocks of the canonical CUBRID DDL
-- ~/dev/cubrid/.vscode/TPC-H/scale10/create_tpch_table.sql (ADR 0004). Same
-- tables, same column order, same nullability. Continues the type mapping fixed
-- by schema/lineitem-pg.sql in the Q1 pilot; the full per-type argument with the
-- empirical checks is in schema/README-type-parity.md.
--
--   INTEGER       -> integer        4-byte signed, identical range.
--   DECIMAL(15,2) -> numeric(15,2)  `decimal` is a documented alias of
--                                   `numeric`; precision 15 / scale 2 and exact
--                                   decimal arithmetic preserved.
--   CHAR(n)       -> character(n)   blank-padded fixed length, trailing-space-
--                                   insensitive comparison on both engines.
--   VARCHAR(n)    -> varchar(n)     max n characters, no padding.
--   DATE          -> date           day granularity, no time, no zone.
--   NOT NULL      -> NOT NULL       unchanged; the two nullable canonical
--                                   columns (r_comment, n_comment) stay
--                                   nullable.
--
-- No new type appears in these seven tables: the set is exactly the set already
-- mapped for lineitem plus wider CHAR/VARCHAR lengths.
--
-- LINEITEM IS DELIBERATELY ABSENT, INCLUDING FROM THE DROP LIST -- it was loaded
-- during the Q1 pilot and must never be dropped or reloaded.
--
-- Index parity rule: PRIMARY KEYs only (see remaining7-pk-pg.sql). All TPC-H
-- FOREIGN KEYs are omitted on both engines because CUBRID materialises a btree
-- for a foreign key and PostgreSQL does not.
--
-- Deliberately NOT set: no fillfactor, no ALTER TABLE ... SET
-- (parallel_workers = N), no per-column STATISTICS target, no UNLOGGED, no
-- tablespace. Plain heaps so the parallel-scan decision is left to the planner.

DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS partsupp;
DROP TABLE IF EXISTS customer;
DROP TABLE IF EXISTS supplier;
DROP TABLE IF EXISTS part;
DROP TABLE IF EXISTS nation;
DROP TABLE IF EXISTS region;

CREATE TABLE region (
    r_regionkey  integer       NOT NULL,
    r_name       character(25) NOT NULL,
    r_comment    varchar(152)
);

CREATE TABLE nation (
    n_nationkey  integer       NOT NULL,
    n_name       character(25) NOT NULL,
    n_regionkey  integer       NOT NULL,
    n_comment    varchar(152)
);

CREATE TABLE part (
    p_partkey     integer       NOT NULL,
    p_name        varchar(55)   NOT NULL,
    p_mfgr        character(25) NOT NULL,
    p_brand       character(10) NOT NULL,
    p_type        varchar(25)   NOT NULL,
    p_size        integer       NOT NULL,
    p_container   character(10) NOT NULL,
    p_retailprice numeric(15,2) NOT NULL,
    p_comment     varchar(23)   NOT NULL
);

CREATE TABLE supplier (
    s_suppkey   integer       NOT NULL,
    s_name      character(25) NOT NULL,
    s_address   varchar(40)   NOT NULL,
    s_nationkey integer       NOT NULL,
    s_phone     character(15) NOT NULL,
    s_acctbal   numeric(15,2) NOT NULL,
    s_comment   varchar(101)  NOT NULL
);

CREATE TABLE partsupp (
    ps_partkey    integer       NOT NULL,
    ps_suppkey    integer       NOT NULL,
    ps_availqty   integer       NOT NULL,
    ps_supplycost numeric(15,2) NOT NULL,
    ps_comment    varchar(199)  NOT NULL
);

CREATE TABLE customer (
    c_custkey    integer       NOT NULL,
    c_name       varchar(25)   NOT NULL,
    c_address    varchar(40)   NOT NULL,
    c_nationkey  integer       NOT NULL,
    c_phone      character(15) NOT NULL,
    c_acctbal    numeric(15,2) NOT NULL,
    c_mktsegment character(10) NOT NULL,
    c_comment    varchar(117)  NOT NULL
);

CREATE TABLE orders (
    o_orderkey      integer       NOT NULL,
    o_custkey       integer       NOT NULL,
    o_orderstatus   character(1)  NOT NULL,
    o_totalprice    numeric(15,2) NOT NULL,
    o_orderdate     date          NOT NULL,
    o_orderpriority character(15) NOT NULL,
    o_clerk         character(15) NOT NULL,
    o_shippriority  integer       NOT NULL,
    o_comment       varchar(79)   NOT NULL
);
