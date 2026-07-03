;trace on
SELECT /*+ USE_HASH(o,l) PARALLEL(8) */ count(*), sum(cast(o.o_orderkey as numeric(38,0))) FROM orders o LEFT OUTER JOIN lineitem l ON o.o_orderkey=l.l_orderkey WHERE o.o_orderkey<200000;
SELECT /*+ USE_HASH(o,l) PARALLEL(1) */ count(*), sum(cast(o.o_orderkey as numeric(38,0))) FROM orders o LEFT OUTER JOIN lineitem l ON o.o_orderkey=l.l_orderkey WHERE o.o_orderkey<200000;
SELECT count(*),sum(cast(o_orderkey as numeric(38,0))),min(o_orderkey),max(o_orderkey) FROM (SELECT /*+ PARALLEL(8) */ DISTINCT o_orderkey FROM orders);
