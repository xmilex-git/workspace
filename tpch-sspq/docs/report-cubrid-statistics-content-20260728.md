# What CUBRID's UPDATE STATISTICS actually produces

Date 2026-07-28. Verification of an assumption, not a measurement. Nothing was
timed, no plan was read, no bottleneck candidate is nominated (ADR 0005).

Triggered by a challenge to the phrase "statistics parity" in
`report-g1-assets-20260728.md` §5. **The challenge lands.** That wording was an
overstatement and is corrected here and in the source document.

## Conclusion (5 lines)

1. CUBRID's per-column optimizer statistics on this pin are **NDV and nothing
   else** — no min/max, no null count, no frequency distribution. Per index it adds
   keys / partial-key counts / pages / leaf pages / height. Verified in the struct
   definitions and in a live dump of `lineitem` and `orders`.
2. A full histogram + MCV subsystem **does exist** in this pin (`src/optimizer/histogram/`,
   `_db_histogram` catalog, reservoir sampling, HyperLogLog) — so "CUBRID has no
   histograms" is wrong as a statement about the code.
3. But it is **off by default** (`update_statistics_update_histogram=n`) and our
   stage-2 `UPDATE STATISTICS ON ALL CLASSES WITH FULLSCAN` therefore built **zero**
   histograms: `db_histogram` has **0 rows**.
4. With no histogram present, the optimizer's range selectivity is a **compile-time
   constant** — `<`/`<=`/`>`/`>=` return `DEFAULT_COMP_SELECTIVITY` 0.1 and
   `BETWEEN` returns `DEFAULT_BETWEEN_SELECTIVITY` 0.01, quoted below. Equality is
   the one predicate class that is data-driven, via `1/NDV`.
5. PostgreSQL on the same data has null_frac, n_distinct, an MCV list with
   frequencies, a 101-bound histogram and physical correlation per column. So
   **"statistics parity" can only mean "both sides are freshly refreshed and
   non-stale", never "comparable information content".**

## 1. The data structures, field by field

`src/storage/statistics.h` (pin `f30f1c260`), quoted:

```c
 66  typedef struct btree_stats BTREE_STATS;
 67  struct btree_stats
 68  {
 69    BTID btid;
 70    int leafs;			/* number of leaf pages including overflow pages */
 71    int pages;			/* number of total pages */
 72    int height;			/* the height of the B+tree */
 73    int keys;			/* number of keys */
 74    int has_function;		/* is a function index */
 75    TP_DOMAIN *key_type;		/* The key type for the B+tree */
 76    int pkeys_size;		/* pkeys array size */
 77    int *pkeys;			/* partial keys info for example: index (a, b, ..., x) pkeys[0] -> # of {a} pkeys[1] ->
 78  				 * # of {a, b} ... pkeys[pkeys_size-1] -> # of {a, b, ..., x} */
 79    int dedup_idx;		/* support for SUPPORT_DEDUPLICATE_KEY_MODE */
 80  };

 87  typedef struct attr_stats ATTR_STATS;
 88  struct attr_stats
 89  {
 90    int id;
 91    DB_TYPE type;
 92    int n_btstats;		/* number of B+tree statistics information */
 93    BTREE_STATS *bt_stats;	/* pointer to array of BTREE_STATS[n_btstats] */
 94    INT64 ndv;			/* Number of Distinct Values of column */
 95  };

 98  typedef struct class_stats CLASS_STATS;
 99  struct class_stats
100  {
101    unsigned int time_stamp;
102    int heap_num_objects;		/* cardinality of the class; number of instances the class has */
103    int heap_num_pages;		/* number of pages the class occupy */
104    int n_attrs;			/* number of attributes; size of the attr_stats[] */
105    ATTR_STATS *attr_stats;
106  };
```

What that inventory does **not** contain:

| Axis | Present in `CLASS_STATS` / `ATTR_STATS` / `BTREE_STATS`? |
|---|---|
| row count, page count | yes (`heap_num_objects`, `heap_num_pages`) |
| per-column NDV | yes (`ATTR_STATS.ndv`) |
| per-index keys / partial keys / pages / leafs / height | yes (`BTREE_STATS`) |
| **column min / max** | **no** |
| **column null count or null fraction** | **no** |
| **frequency distribution (bucket / histogram)** | **no** |
| **most-common-values list** | **no** |
| **physical correlation / clustering factor** | **no** |
| **average column width** | **no** |

min/max is not merely unused — it is **not declared**. The only survivor is a
dead macro with zero consumers anywhere in `src/`:

```c
statistics.h:44  #define STATS_MIN_MAX_SIZE    sizeof(DB_DATA)
```
(`grep STATS_MIN_MAX_SIZE src/` returns exactly that one definition line.)

## 2. The histogram subsystem exists — and is a separate structure

The blanket claim "CUBRID does not build histograms" is **false for this pin**.
There is a complete subsystem, and it is recent:

```
src/optimizer/histogram/histogram_builder.{cpp,hpp}
src/optimizer/histogram/histogram_bucketizer.hpp
src/optimizer/histogram/histogram_reader.{cpp,hpp}
src/optimizer/histogram/histogram_sampler_sr.{cpp,hpp}
src/optimizer/histogram/histogram_cl.{cpp,hpp}
src/optimizer/histogram/reservoir_sampler.hpp
src/optimizer/histogram/hyperloglog.hpp
src/storage/statistics_ndv.c
```

MCV admission and sample-based NDV are declared in `statistics.h` itself:

```c
154  extern INT64 stats_estimate_ndv_from_sample (const STATS_NDV_SAMPLE_INPUT * in);
164  extern int stats_analyze_mcv_list (const INT64 * mcv_counts, int num_candidates, double stadistinct,
165  				   double stanullfrac, INT64 samplerows, double totalrows);
```

Histogram payload is a **separate** structure, deliberately not part of
`CLASS_STATS`:

```c
108  typedef struct hist_stats HIST_STATS;
109  struct hist_stats
110  {
111    int n_attrs;			/* number of attributes; size of the histogram[] */
112    int *attr_ids;		/* column id per slot -- consumers must match by id, NOT by the
113  				 * position of the id in CLASS_STATS.attr_stats: that array is not
114  				 * kept in attribute order after schema updates */
115    DB_VALUE **histogram;		/* column histogram , null if not exists */
116    double *null_frequency;	/* column null frequency , 0 if not exists */
117  };
```

and it hangs off the class independently (`src/object/class_object.h`):

```c
786    CLASS_STATS *stats;		/* server statistics, loaded on demand */
787    HIST_STATS *histogram;	/* column histogram, loaded on demand */
```

**Note the consequence: `null_frequency` lives only in `HIST_STATS`.** No
histogram means no null fraction either.

Persistence is a real catalog class plus a view
(`src/object/schema_system_catalog_constants.h`):

```c
56  #define CT_HISTOGRAM_NAME       "_db_histogram"
84  #define CTV_HISTOGRAM_NAME      "db_histogram"
```

### It is new

```
aabba8d1e 2026-05-28 [CBRD-26202] Add Optimizer Histogram Support (#7180)
9f7549946 2026-06-16 [CBRD-26894] Fix core dump in er_message::set_error during histogram stat collection (#7270)
f7432203a 2026-07-15 [CBRD-26936] Replace query-based statistics/histogram sampling with server-side full-scan reservoir sampling (#7286)
10d0aa0e7 2026-07-24 [CBRD-26746] Use histograms for equi-join selectivity and a significance-based MCV admission test (#7508)
```

`git log --diff-filter=A` confirms `src/optimizer/histogram/` first appeared in
`aabba8d1e` (2026-05-28). The pin `f30f1c260` (2026-07-27) contains all four.
`origin/develop` (`8dbc2dc0b`) is **1 commit** ahead of the pin and that commit
touches none of `src/optimizer/`, `src/storage/statistics*` — so on this axis the
pin is current. Nothing newer to pick up.

## 3. It is off by default, and it was off for our load

Default value, `src/base/system_parameter.c`:

```c
5341    {PRM_ID_DEFAULT_HISTOGRAM_BUCKET_COUNT,
5342     PRM_NAME_DEFAULT_HISTOGRAM_BUCKET_COUNT,
...
5346     {false, {.i = 300}},        /* default 300 buckets */
5348     {false, {.i = 1000}},       /* max */
5349     {false, {.i = 4}},          /* min */

5365    {PRM_ID_UPDATE_STATISTICS_UPDATE_HISTOGRAM,
5366     PRM_NAME_UPDATE_STATISTICS_UPDATE_HISTOGRAM,
5367     (PRM_FOR_CLIENT | PRM_FOR_SERVER | PRM_USER_CHANGE),
5368     PRM_BOOLEAN,
5369     PRM_CLEAR_DYNAMIC_FLAG,
5370     {false, {.b = false}},      /* default: FALSE */
5371     {false, {.b = false}},
```

Both call sites that could build a histogram during `UPDATE STATISTICS` are gated
on it. `src/object/schema_manager.c` (the `ON ALL CLASSES` path we used):

```c
4469    if (prm_get_bool_value (PRM_ID_UPDATE_STATISTICS_UPDATE_HISTOGRAM))
4470      {
4471        error = update_histogram_for_all_classes ();
```

`src/query/execute_statement.c` (the per-class path):

```c
4757          if (prm_get_bool_value (PRM_ID_UPDATE_STATISTICS_UPDATE_HISTOGRAM))
4758            {
4759              DB_OBJECT *obj;
4760              PT_HISTOGRAM_INFO histogram_info;
```

Live value in the running measurement server — `cubrid paramdump tpch_sf10_q1`:

```
[C ] default_histogram_bucket_count=300 (300)
[C ] update_statistics_update_histogram=n (n)
[S ] update_statistics_update_histogram=n (n)
```

We never set it. Therefore stage 2's `UPDATE STATISTICS ON ALL CLASSES WITH
FULLSCAN` built no histogram, and the catalog confirms it:

```sql
SELECT count(*) AS histogram_rows FROM db_histogram;
        histogram_rows
======================
                     0
```

For reference, the view's shape (so it is clear what would have been there):

```
 <VClass Name>  db_histogram
 <Attributes>
     class_name           object
     key_attr             CHARACTER VARYING(255)
     with_fullscan        CHARACTER VARYING(32)
     null_frequency       DOUBLE
```

## 4. What is actually stored, dumped from the loaded database

`csql -C -u dba` + `;info stats <class>`. This is a catalog fetch, not a query
execution. Raw: `.git_ignored_dir/g1-assets/raw/stats-probe/`.

The dump routine prints exactly what exists — `src/storage/statistics_cl.c`
`stats_dump()` emits class timestamp / pages / objects / n_attrs, then per
attribute the name, type and `Number of Distinct Values`, then per btree the BTID,
`Cardinality`, partial keys, pages, leafs and height. There is no other field to
print.

### lineitem

```
CLASS STATISTICS
****************
 Class name: lineitem Timestamp: Tue Jul 28 17:31:50 2026
 Total pages in class heap: 682937
 Total objects: 59986052
 Number of attributes: 16
 Attribute: l_receiptdate (date)
    Number of Distinct Values: 2551

 Attribute: l_commitdate (date)
    Number of Distinct Values: 2463

 Attribute: l_shipdate (date)
    Number of Distinct Values: 2525

 Attribute: l_linenumber (integer)
    Number of Distinct Values: 7

 Attribute: l_suppkey (integer)
    Number of Distinct Values: 99830

 Attribute: l_partkey (integer)
    Number of Distinct Values: 1989793

 Attribute: l_orderkey (integer)
    Number of Distinct Values: 14929885
    B+tree statistics:
        BTID: { 2 , 32640 }
        Cardinality: 59986052 (15000000,59986052) , Total pages: 93440 , Leaf pages: 93291 , Height: 3

 Attribute: l_comment (character varying)
    Number of Distinct Values: 34188821
 Attribute: l_shipmode (character)
    Number of Distinct Values: 7
 Attribute: l_shipinstruct (character)
    Number of Distinct Values: 4
 Attribute: l_linestatus (character)
    Number of Distinct Values: 2
 Attribute: l_returnflag (character)
    Number of Distinct Values: 3
 Attribute: l_tax (numeric)
    Number of Distinct Values: 9
 Attribute: l_discount (numeric)
    Number of Distinct Values: 11
 Attribute: l_extendedprice (numeric)
    Number of Distinct Values: 1346407
 Attribute: l_quantity (numeric)
    Number of Distinct Values: 50
```

### orders

```
 Class name: orders Timestamp: Tue Jul 28 17:31:05 2026
 Total pages in class heap: 151689
 Total objects: 15000000
 Number of attributes: 9
 Attribute: o_shippriority (integer)
    Number of Distinct Values: 1
 Attribute: o_orderdate (date)
    Number of Distinct Values: 2398
 Attribute: o_custkey (integer)
    Number of Distinct Values: 992718
 Attribute: o_orderkey (integer)
    Number of Distinct Values: 14929885
    B+tree statistics:
        BTID: { 33 , 29888 }
        Cardinality: 15000000 (15000000) , Total pages: 15565 , Leaf pages: 15545 , Height: 3
 Attribute: o_comment (character varying)
    Number of Distinct Values: 13954843
 Attribute: o_clerk (character)
    Number of Distinct Values: 10056
 Attribute: o_orderpriority (character)
    Number of Distinct Values: 5
 Attribute: o_totalprice (numeric)
    Number of Distinct Values: 11962043
 Attribute: o_orderstatus (character)
    Number of Distinct Values: 3
```

Three observations, all factual:

* **Only the PK's leading column carries B+tree statistics.** 15 of lineitem's 16
  columns and 8 of orders' 9 have NDV and nothing else — a direct consequence of
  the PK-only index parity rule, not of the statistics command.
* **NDV is an estimate even under `WITH FULLSCAN`.** Exact distinct counts were
  measured for comparison with `count(distinct …)`
  (`.git_ignored_dir/g1-assets/raw/stats-probe/exact-distinct.txt`):

  | column | exact `count(distinct)` | CUBRID NDV | error | PG `n_distinct` |
  |---|---|---|---|---|
  | `lineitem.l_orderkey` | 15,000,000 | 14,929,885 | −0.47 % | — |
  | `lineitem.l_partkey` | 2,000,000 | 1,989,793 | −0.51 % | — |
  | `lineitem.l_suppkey` | 100,000 | 99,830 | −0.17 % | — |
  | `lineitem.l_shipdate` | 2,526 | 2,525 | −0.04 % | 2,513 |
  | `lineitem.l_quantity` | 50 | 50 | exact | 50 |
  | `orders.o_orderkey` | 15,000,000 | 14,929,885 | −0.47 % | — |
  | `orders.o_custkey` | 999,982 | 992,718 | −0.73 % | — |
  | `orders.o_orderdate` | 2,406 | 2,398 | −0.33 % | 2,406 |
  | `orders.o_clerk` | 10,000 | 10,056 | **+0.56 %** | — |

  The *table* cardinality `heap_num_objects` is exact (59,986,052 / 15,000,000);
  per-column NDV is not, and `o_clerk` shows the error is two-sided. The estimator
  is `stats_estimate_ndv_from_sample` (`src/storage/statistics_ndv.c`; "Population
  NDV is extrapolated from a uniform sample's distinct/singleton counts",
  `statistics.h`). So `WITH FULLSCAN` refers to the heap scan, not to exact
  per-column distinct counting. Small-domain columns land exactly (`l_quantity` 50,
  `l_linenumber` 7, `o_orderstatus` 3). The magnitudes here are sub-1 %.
* **For an indexed column two numbers exist and the optimizer takes the smaller.**
  `orders.o_orderkey` has `ATTR_STATS.ndv` 14,929,885 and an exact B+tree
  `Cardinality: 15000000`. `qo_index_cardinality()` returns
  `MIN (ndv, info->cum_stats.pkeys[0])` under the comment "Choose the better NDV of
  the two" (`query_planner.c:11119-11120`), i.e. 14,929,885 — the estimated value
  rather than the exact key count. Stated as observed behaviour, not as a defect.

## 5. PostgreSQL's per-column statistics on the same data

`default_statistics_target = 100`. `pg_stats`, raw at
`.git_ignored_dir/g1-assets/raw/stats-probe/pg-stats.txt`:

```
 tablename |    attname    | null_frac | n_distinct | mcv_len | mcf_len | hist_len | correlation  | avg_width
-----------+---------------+-----------+------------+---------+---------+----------+--------------+-----------
 lineitem  | l_quantity    |         0 |         50 |      50 |      50 |        0 |  0.019839268 |         5
 lineitem  | l_shipdate    |         0 |       2513 |      19 |      19 |      101 | -0.012172227 |         4
 orders    | o_orderdate   |         0 |       2406 |      16 |      16 |      101 |  0.004217461 |         4
 orders    | o_orderstatus |         0 |          3 |       3 |       3 |        0 |   0.47509933 |         2
```

`hist_len = 0` on `l_quantity` and `o_orderstatus` is not an absence of
information — the whole domain fits in the MCV list (50 of 50, 3 of 3), so a
histogram would be redundant. Actual contents:

```
    attname    |                  mcv_first4                   |                 mcf_first4                  |            hist_first3             |             hist_last3
---------------+-----------------------------------------------+---------------------------------------------+------------------------------------+------------------------------------
 o_orderdate   | {1996-06-20,1998-01-13,1993-03-29,1998-02-15} | {0.0009,0.0009,0.00083333335,0.00083333335} | {1992-01-01,1992-01-23,1992-02-15} | {1998-06-16,1998-07-11,1998-08-02}
 o_orderstatus | {F,O,P}                                       | {0.49026668,0.48376667,0.025966667}         |                                    |
```

101 histogram bounds = 100 equi-depth buckets, and the bounds carry the real
domain endpoints (`1992-01-01` … `1998-08-02`), which is exactly the min/max
CUBRID does not store.

## 6. Axis-by-axis comparison

| Axis | CUBRID (pin, as configured) | PostgreSQL (as configured) |
|---|---|---|
| table row count | exact (`heap_num_objects` 59,986,052) | sampled estimate (`reltuples` 59,988,188) |
| table page count | yes (`heap_num_pages`) | yes (`relpages`) |
| per-column NDV | yes, **sample-extrapolated** | yes, sample-extrapolated (`n_distinct`) |
| per-column null fraction | **no** (only in `HIST_STATS`, absent) | yes (`null_frac`) |
| per-column min / max | **no** (not declared) | effectively yes (histogram end bounds) |
| per-column frequency distribution | **no** (0 histograms built) | yes, 100 equi-depth buckets |
| per-column MCV + frequencies | **no** (0 histograms built) | yes (`most_common_vals` / `_freqs`) |
| per-column physical correlation | **no** | yes (`correlation`) |
| per-column average width | **no** | yes (`avg_width`) |
| per-index keys / partial keys | yes (`keys`, `pkeys[]`) | via `pg_stats` + index NDV |
| per-index pages / leafs / height | yes | `relpages` on the index relation |
| columns with any index-level stats | **1 of 16** (lineitem), 1 of 9 (orders) | all |
| refresh command used | `UPDATE STATISTICS ON ALL CLASSES WITH FULLSCAN` | `ANALYZE VERBOSE` |
| histogram machinery in the build | **present but disabled by default** | always on |

## 7. Where selectivity is actually computed, and with what

Facts only, quoted. No inference about consequences for any specific query.

Constants, `src/optimizer/query_planner.h:113-121`:

```c
113  #define DEFAULT_NULL_SELECTIVITY (double) 0.01
114  #define DEFAULT_EXISTS_SELECTIVITY (double) 0.1
115  #define DEFAULT_SELECTIVITY (double) 0.1
116  #define DEFAULT_EQUAL_SELECTIVITY (double) 0.001
117  #define DEFAULT_EQUIJOIN_SELECTIVITY (double) 0.001
118  #define DEFAULT_COMP_SELECTIVITY (double) 0.1
119  #define DEFAULT_BETWEEN_SELECTIVITY (double) 0.01
120  #define DEFAULT_IN_SELECTIVITY (double) 0.01
121  #define DEFAULT_RANGE_SELECTIVITY (double) 0.1
```

Dispatch is `qo_expr_selectivity()` (`query_planner.c:9848`), reached from
`qo_analyze_term()` (`query_graph.c:2790`).

**Equality — data-driven.** `qo_equal_selectivity()`, `query_planner.c:10241-10274`:

```c
10251	  histogram_get_equal_selectivity (lhs, host_var, &selectivity, &success);
10252	  if (success)
10253	    {
10254	      break;
10255	    }
10256	  [[fallthrough]];
...
10264	  lhs_icard = qo_index_cardinality (env, lhs);
10265	  if (lhs_icard != 0)
10266	    {
10267	      selectivity = (1.0 / lhs_icard);
10268	    }
10269	  else
10270	    {
10271	      selectivity = DEFAULT_EQUAL_SELECTIVITY;
10272	    }
```

`qo_index_cardinality()` is where NDV enters (`query_planner.c:11113-11135`):

```c
11113	  if (info->ndv > 0)
11114	    {
11115	      int ndv = (info->ndv > INT_MAX) ? INT_MAX : info->ndv;
11117	      if (info->cum_stats.is_indexed == true && info->cum_stats.pkeys[0] > 0)
11118		{
11119		  /* Choose the better NDV of the two. */
11120		  return MIN (ndv, info->cum_stats.pkeys[0]);
11121		}
11122	      return ndv;
11123	    }
11125	  if (info->cum_stats.is_indexed != true)
11126	    {
11127	      return 0;
11128	    }
11134	  /* return number of the first partial-key of the index on the attribute shown in the expression */
11135	  return info->cum_stats.pkeys[0];
```

So `col = const` uses `1/NDV`, and falls to the constant 0.001 only when the
column has neither NDV nor an index.

**`<` `<=` `>` `>=` — constant when no histogram.** `qo_comp_selectivity()`,
`query_planner.c:10624`:

```c
10624	  return success ? selectivity : DEFAULT_COMP_SELECTIVITY;
```

`success` is set only by `histogram_get_comp_selectivity()` (lines 10541-10553 for
`attr op const`, 10582-10597 for `const op attr`). With no histogram stored,
`histogram_get_equal_selectivity`/`_comp_selectivity` return early with
`*success = false` — `src/optimizer/histogram/histogram_cl.cpp:857-862`:

```c
  hist::HistogramReader histogram_reader;
  if (!histogram_init_reader_from_lhs (lhs, histogram_reader))
    {
      *success = false;
      return;
    }
```

so the return value is the flat constant `0.1`, and **NDV is not consulted on this
path**. The `attr op attr` case has no histogram path at all
(`query_planner.c:10523-10525`):

```c
10523	case PC_ATTR:
10524	  /* TODO: add histogram selectivity */
10525	  break;
```

**`BETWEEN` — constant unconditionally.** `qo_between_selectivity()`,
`query_planner.c:10636-10646`:

```c
static double
qo_between_selectivity (QO_ENV * env, PT_NODE * pt_expr)
{
  PT_NODE *and_node;
  and_node = pt_expr->info.expr.arg2;
  QO_ASSERT (env, and_node->node_type == PT_EXPR);
  QO_ASSERT (env, pt_is_between_range_op (and_node->info.expr.op));
  return DEFAULT_BETWEEN_SELECTIVITY;
}
```

There is no histogram probe and no statistics lookup in this function at all.

**`PT_RANGE`** does probe the histogram per range operator and falls back
explicitly (`query_planner.c:10834-10845`):

```c
10834	  if (!(success1 && success2))
10835	    {
10836	      if (op_type == PT_BETWEEN_INF_LT || op_type == PT_BETWEEN_INF_LE || op_type == PT_BETWEEN_GE_INF
10837		  || op_type == PT_BETWEEN_GT_INF)
10838		{
10839		  selectivity = DEFAULT_COMP_SELECTIVITY;
10840		}
10841	      else
10842		{
10843		  selectivity = DEFAULT_BETWEEN_SELECTIVITY;
10844		}
10845	    }
```

with `PT_BETWEEN_EQ_NA` (a `range (const =)`) routed to `1/lhs_icard`, i.e. NDV,
at lines 10872-10884.

**`LIKE`** uses `qo_like_selectivity()` / `PRM_ID_LIKE_TERM_SELECTIVITY`
(`query_planner.c:9932-9942`).

Statement of fact, no inference: for a single-column inequality against a
constant, the value the CUBRID optimizer uses in this configuration is
independent of the column's data — it is 0.1 (or 0.01 for a bounded range) —
whereas the equality case scales with measured NDV. Whether and where that
matters is a G4 observation to be made from measured plans, not asserted here.

## 8. Corrected definition of "statistics parity"

The stage-2 report's §5 heading and the phrase "statistics parity" are replaced by
this scoped claim:

> **Statistics freshness parity.** Both engines' optimizer statistics were
> refreshed with each engine's own standard command, on the same data, at the same
> point in the load sequence, before any warmup or measured stream. Neither side is
> stale, and neither side was given a non-default statistics configuration.

It explicitly does **not** claim, and must never be read as claiming:

* that the two engines hold comparable statistics;
* that the two optimizers have comparable information to estimate selectivity;
* that a plan-shape or row-estimate difference observed in G4 is attributable to
  the query, the schema or the engine's algorithms rather than to this asymmetry.

## 9. Consequences for the gates

* **G4 must state this asymmetry as a precondition of its own output.** Its
  "statistics parity" step was specified as "CUBRID `UPDATE STATISTICS` ↔ PG
  `ANALYZE`". That makes both sides fresh; it does not make them equivalent. Any
  estimated-vs-actual row comparison in G4 has to be read against §6.
* **A defensible option exists and is not exercised here.** Setting
  `update_statistics_update_histogram=yes` (plus
  `default_histogram_bucket_count`, default 300 vs PostgreSQL's 100 buckets) and
  re-running `UPDATE STATISTICS` would give CUBRID histograms, MCVs and null
  fractions. That is a **configuration change to the measured system** and a
  deviation from CUBRID's default posture, so it is a decision for the gate owner,
  not something to slip in. Recorded as an open decision; nothing was changed.
* **No re-measurement is invalidated.** The Q1 pilot number stands: this report
  changes documentation wording, not the database or the binaries. Both servers
  were left running throughout; only catalog reads and `paramdump` were issued.

## Evidence index

| Artefact | Path |
|---|---|
| `;info stats lineitem` | `.git_ignored_dir/g1-assets/raw/stats-probe/cubrid-info-stats-lineitem.txt` |
| `;info stats orders` | `.git_ignored_dir/g1-assets/raw/stats-probe/cubrid-info-stats-orders.txt` |
| `pg_stats` extract | `.git_ignored_dir/g1-assets/raw/stats-probe/pg-stats.txt` |
| struct definitions | `~/dev/wt-tpch-sspq/src/storage/statistics.h:66-117` |
| parameter defaults | `~/dev/wt-tpch-sspq/src/base/system_parameter.c:5341-5371` |
| histogram gates | `src/object/schema_manager.c:4469`, `src/query/execute_statement.c:4757` |
| selectivity constants | `src/optimizer/query_planner.h:113-121` |
| selectivity code | `src/optimizer/query_planner.c:10189-10899`, `11076-11136` |
| histogram early-out | `src/optimizer/histogram/histogram_cl.cpp:857-862` |
