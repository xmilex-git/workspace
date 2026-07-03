-- 2A-3 hash-join robust-parity query set (leader verification; NOT product code)
-- golden: tpch_sf10 HASHJOIN(o_orderkey<200000) count=200360
-- Serial = PARALLEL(1); Parallel = PARALLEL(8). Server env decides WM gate.

-- Q1 tpch inner hash join, robust aggregates
SELECT /*+ USE_HASH(o,l) PARALLEL(8) */ count(*), sum(cast(o.o_orderkey as numeric(38,0))), min(l.l_linenumber), max(l.l_linenumber)
FROM orders o, lineitem l WHERE o.o_orderkey=l.l_orderkey AND o.o_orderkey<200000;

-- Q1s serial reference
SELECT /*+ USE_HASH(o,l) PARALLEL(1) */ count(*), sum(cast(o.o_orderkey as numeric(38,0))), min(l.l_linenumber), max(l.l_linenumber)
FROM orders o, lineitem l WHERE o.o_orderkey=l.l_orderkey AND o.o_orderkey<200000;

-- Q2 larger selectivity (more partitions / spill)
SELECT /*+ USE_HASH(o,l) PARALLEL(8) */ count(*), sum(cast(l.l_partkey as numeric(38,0)))
FROM orders o, lineitem l WHERE o.o_orderkey=l.l_orderkey AND o.o_orderkey<2000000;

-- Q3 LEFT outer hash join (NULL last-partition path)
SELECT /*+ USE_HASH(o,l) PARALLEL(8) */ count(*), sum(cast(o.o_orderkey as numeric(38,0)))
FROM orders o LEFT OUTER JOIN lineitem l ON o.o_orderkey=l.l_orderkey WHERE o.o_orderkey<200000;
