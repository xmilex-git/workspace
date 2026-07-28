-- tpch-sspq G1 Q1 pilot — PostgreSQL lineitem schema.
--
-- Derived from the LINEITEM block of the canonical CUBRID DDL
-- ~/dev/cubrid/.vscode/TPC-H/scale10/create_tpch_table.sql plus the LINEITEM
-- PRIMARY KEY from create_tpch_index.sql. Every column keeps its declared type
-- meaning and precision; nothing is widened, narrowed or relaxed.
--
-- Type mapping and why each one is meaning-preserving
-- ---------------------------------------------------
--   INTEGER       -> integer       identical: 4-byte signed, same range.
--   DECIMAL(15,2) -> numeric(15,2) `decimal` is a documented alias of `numeric`
--                                  in PostgreSQL, so precision 15 / scale 2 and
--                                  exact decimal arithmetic are preserved.
--                                  NOTE (engine difference, not a conversion
--                                  choice): CUBRID stores DECIMAL as a
--                                  fixed-width packed value while PostgreSQL
--                                  `numeric` is variable-length arbitrary
--                                  precision. The declared semantics match;
--                                  the storage and arithmetic cost do not.
--                                  Rejected alternatives: double precision /
--                                  bigint-scaled — both change the arithmetic
--                                  semantics of Q1's SUM/AVG, so they are out.
--   CHAR(n)       -> character(n)  both are blank-padded fixed length with
--                                  trailing-space-insensitive comparison.
--   DATE          -> date          both are a day-granularity calendar date
--                                  with no time or zone component.
--   VARCHAR(44)   -> varchar(44)   identical: max 44 characters, no padding.
--   NOT NULL      -> NOT NULL      unchanged on all 16 columns.
--
-- Column names are lower-cased. PostgreSQL folds unquoted identifiers to lower
-- case and CUBRID folds them to upper case; both are case-insensitive for
-- unquoted names, so this is presentation only.
--
-- Omitted on purpose for the Q1-only pilot, identically to the CUBRID side:
--   * the other 7 TPC-H tables (Q1 reads lineitem only);
--   * the two LINEITEM FOREIGN KEYs (they reference ORDERS / PARTSUPP, which
--     are not loaded). FKs are not usable by Q1's plan.
--
-- Deliberately NOT set: any storage/statistics override. No fillfactor, no
-- `ALTER TABLE ... SET (parallel_workers = N)`, no per-column STATISTICS
-- target, no UNLOGGED. The table is a plain heap so that the parallel-scan
-- decision is left entirely to the planner.

DROP TABLE IF EXISTS lineitem;

CREATE TABLE lineitem (
    l_orderkey      integer       NOT NULL,
    l_partkey       integer       NOT NULL,
    l_suppkey       integer       NOT NULL,
    l_linenumber    integer       NOT NULL,
    l_quantity      numeric(15,2) NOT NULL,
    l_extendedprice numeric(15,2) NOT NULL,
    l_discount      numeric(15,2) NOT NULL,
    l_tax           numeric(15,2) NOT NULL,
    l_returnflag    character(1)  NOT NULL,
    l_linestatus    character(1)  NOT NULL,
    l_shipdate      date          NOT NULL,
    l_commitdate    date          NOT NULL,
    l_receiptdate   date          NOT NULL,
    l_shipinstruct  character(25) NOT NULL,
    l_shipmode      character(10) NOT NULL,
    l_comment       varchar(44)   NOT NULL
);
