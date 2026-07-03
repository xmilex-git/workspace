;trace on
SELECT /*+ USE_HASH(o,l) PARALLEL(8) */ count(*) FROM orders o, lineitem l WHERE o.o_orderkey=l.l_orderkey AND o.o_orderkey<200000;
SELECT /*+ USE_HASH(o,l) PARALLEL(8) */ count(*) FROM orders o, lineitem l WHERE o.o_orderkey=l.l_orderkey AND o.o_orderkey<2000000;
