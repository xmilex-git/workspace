# PR #753 수확: [CBRD-26722] Expand parallel heap scan to parallel scan (index, heap, list)

> Wayfinder 티켓 [#150](https://github.com/xmilex-git/workspace/issues/150) 산출물.
> 11.5 통합 문서화 PR(맵 [#144](https://github.com/xmilex-git/workspace/issues/144))의 집필 티켓(#152/#153)이 참조하는 **PR #753 최종 diff 원본**이다.

## 메타데이터

- **Upstream PR**: https://github.com/CUBRID/cubrid-manual/pull/753 — `[CBRD-26722] Expand parallel heap scan to parallel scan (index, heap, list)`
- **상태**: 통합 PR로 대체하기 위해 클로즈됨 (이 티켓에서, 사용자 승인 하에)
- **head**: `xmilex-git/cubrid-manual` `parallel_scan_all` @ `70ecd073004aca90666ecc83170336bae15eae2f` (단일 커밋, merge-base `48bf39a` 위)
- **base**: `CUBRID/cubrid-manual` `develop`
- **수확 시점 develop**: `68bc9a4` (CUBRIDMAN-348 — 이 diff의 6개 파일과 무관, 충돌 없음)
- **변경 규모**: 6 files, +524 −359

| 파일 | 변경 |
|---|---|
| `en/sql/parallel.rst` | +432 상당 재작성 (heap→heap/list/index 확장, NO_PARALLEL_SCAN) |
| `ko/sql/parallel.rst` | +427 상당 재작성 (동일) |
| `en/sql/tuning.rst` | 힌트 표 갱신 (10줄) |
| `ko/sql/tuning.rst` | 힌트 표 갱신 (10줄) |
| `en/admin/config.rst` | 1줄 (파라미터 서술) |
| `ko/admin/config.rst` | 1줄 (동일) |

## 사용 지침

- 이 diff는 **문체·구성의 계승 원본**이다 — 갭 감사([#148](https://github.com/xmilex-git/workspace/issues/148), `docs/research/manual-gap-audit.md@research/manual-gap-audit`)가 판정한 "수정 후 계승 5건"의 원문이 여기 있다.
- 갭 감사·스타일 가이드(#149)의 판정이 이 diff와 충돌하면 **감사·가이드가 우선**한다 (예: versionadded 금지 등).
- 새 작업 브랜치는 `/home/cubrid/cubrid-manual`의 `cbrd-26722-115-docs` (origin/develop `68bc9a4`에서 분기).

## 최종 diff (verbatim)

```diff
diff --git a/en/admin/config.rst b/en/admin/config.rst
index 66e8ff263..3b5e1d0d6 100644
--- a/en/admin/config.rst
+++ b/en/admin/config.rst
@@ -746,7 +746,7 @@ The following are parameters related to the memory used by the database server o
 
     **max_parallel_workers** is a parameter that sets the maximum number of parallel query worker threads that can be executed simultaneously across the entire server. The default value is **100**, the minimum value is **0**, and the maximum value is **1000**.
 
-    If this parameter is set to **0**, the parallel query feature is disabled. When set to **2 or higher**, various parallel processing features such as Parallel Heap Scan, Parallel Subquery Execution, Parallel Hash Join, and Parallel Sort can be used.
+    If this parameter is set to **0**, the parallel query feature is disabled. When set to **2 or higher**, various parallel processing features such as Parallel Scan (heap/list/index), Parallel Subquery Execution, Parallel Hash Join, and Parallel Sort can be used.
 
     The server manages parallel query execution through a **global worker pool**. Even when multiple sessions simultaneously request parallel queries or complex parallel operations are performed within a single session, the total number of active parallel workers across the entire server cannot exceed the **max_parallel_workers** value.
 
diff --git a/en/sql/parallel.rst b/en/sql/parallel.rst
index 1e83bba06..fd967f967 100644
--- a/en/sql/parallel.rst
+++ b/en/sql/parallel.rst
@@ -11,7 +11,12 @@ Overview
 
 Parallel queries provide the following key features:
 
-*   **Parallel Heap Scan**: Multiple worker threads divide and scan heap regions, improving large table scanning performance.
+*   **Parallel Scan**: Multiple worker threads divide and scan the input data (heap, temporary list, or index), improving large input scanning performance. Three scan flavors are supported:
+
+    *   **Parallel Heap Scan**: Heap pages of a table are partitioned by **sector** and scanned in parallel.
+    *   **Parallel List Scan**: A temporary result list (list file) that has spilled to disk is partitioned by **sector** and scanned in parallel.
+    *   **Parallel Index Scan**: Workers cooperate through a shared cursor to walk the leaf pages of a B+tree index from left to right (or right to left).
+
 *   **Parallel Subquery Execution**: Independent subqueries (uncorrelated subqueries) are processed simultaneously by individual workers, improving query response time.
 *   **Parallel Hash Join**: Parallelizes both the build and probe phases, improving response time during hash join operations.
 *   **Parallel Sort**: Divides data to be sorted among multiple worker threads, sorts in parallel, then merges the results, improving sort response time.
@@ -24,226 +29,294 @@ Parallel query execution can be controlled through system parameters and SQL hin
 *   Setting the :ref:`parallelism <parallelism>` parameter to 2 or higher enables the optimizer to determine parallel query execution during query processing.
 *   Use the **PARALLEL** ( *degree* ) hint to explicitly specify the degree of parallelism for each query. *degree* is the number of workers to use and must be an integer value of 2 or higher. Hint-specified values take precedence over the parallelism parameter setting.
 *   The :ref:`max_parallel_workers <max_parallel_workers>` parameter sets the maximum number of parallel worker threads that can be executed simultaneously across the entire server (default: 100).
+*   The **NO_PARALLEL_SCAN** hint disables every parallel scan flavor (heap, list, and index) within the query block. When used together with the **PARALLEL** hint, **NO_PARALLEL_SCAN** takes precedence.
 
 .. note::
 
     The max_parallel_workers and parallelism parameters are set to default values of 100 and 4 respectively, so you can use parallel queries without additional configuration.
 
-.. _parallel-heap-scan:
-
-Parallel Heap Scan
-------------------
+.. _parallel-scan:
 
-Parallel Heap Scan is a feature that improves heap table scanning performance by using multiple worker threads when scanning large amounts of data. Performance can be significantly improved over single-threaded heap scanning, especially when selectivity is low (typically 0.05 or less) and processing large amounts of data.
+Parallel Scan
+-------------
 
-Heap Scan Overview
-^^^^^^^^^^^^^^^^^^
+Parallel Scan splits a single scan input across multiple worker threads that process it concurrently. CUBRID supports parallel scan over three input kinds, all sharing the same parallel execution framework:
 
-Parallel heap scan divides large tables into logical units for simultaneous scanning by multiple worker threads, with each worker thread independently scanning assigned pages while processing filter conditions (predicates). The processed results are collected through a result queue, and the main thread integrates these results to generate the final result and returns it to the user.
+*   **Heap**: heap pages of a table — pre-partitioned across workers by **sector**
+*   **List**: pages of a temporary (on-disk) result list file — pre-partitioned across workers by **sector**
+*   **Index**: leaf pages of a B+tree index — workers cooperate through a shared **cursor**, walking left to right (or right to left)
 
-The **NO_PARALLEL_HEAP_SCAN** hint can be used to disable parallel heap scan. When used together with the **PARALLEL** hint, the **NO_PARALLEL_HEAP_SCAN** hint takes precedence.
+Each worker thread independently scans its assigned region while evaluating filter predicates, and the processed results are passed to the main thread through a result queue and integrated into the final result.
 
 .. note::
 
-    The actual degree of parallelism for parallel heap scan is automatically optimized by throughput rules within the user-configured upper limit. For more details, see :ref:`parallel-query-throughput-rules`.
+    The actual degree of parallelism is automatically optimized by throughput rules within the user-configured upper limit. For more details, see :ref:`parallel-query-throughput-rules`.
 
-Constraints
-^^^^^^^^^^^
+Common Constraints
+^^^^^^^^^^^^^^^^^^
 
-If any of the following conditions apply, parallel heap scan is not supported and executes in single-threaded mode:
+Regardless of the scan flavor, parallel scan is not applied and falls back to single-threaded execution if any of the following conditions hold:
 
 *   Statements that do not support concurrent processing
 
-    *    When using stored procedures (JavaSP, PL/CSQL)
-
-    *    When referencing session variables
-  
-    *    When using Recursive CTE or Connect By clauses
-  
-    *    When using CUBRID object DBMS specific features
+    *    Stored procedures (JavaSP, PL/CSQL) or Serial usage
+    *    References to session variables
+    *    Recursive CTE or Connect By clauses
+    *    CUBRID object DBMS specific features
 
-*   Cases requiring exclusive lock (X-LOCK) acquisition
+*   Operations requiring exclusive lock (X-LOCK) acquisition
 
     *    SELECT ... FOR UPDATE clause
-    *    When using incr() function
+    *    Use of the incr() function
     *    update, delete, merge statements
 
-*   When not the first (driving) table in a JOIN
-*   When it is a correlated subquery
-*   When reading data through index scan
-
-.. note::
-
-    The default values of the max_parallel_workers and parallelism parameters provide defaults that allow parallel queries without additional settings. Performance can be further optimized by modifying these values in the cubrid.conf file according to system resources and application workload. ::
+*   The scan is not the first (driving) table in a JOIN
+*   Correlated subqueries
+*   The scan is the direct outer/inner input of a sort-merge join (applies to every scan flavor)
+*   The **NO_PARALLEL_SCAN** hint is specified
 
-        # cubrid.conf
-        max_parallel_workers=200  # default: 100
-        parallelism=8             # default: 4
+Each scan flavor has additional, flavor-specific constraints. See the corresponding subsections below.
 
 .. code-block:: sql
 
-    -- Examples where parallel heap scan is not applied
+    -- Examples where parallel scan is not applied
 
-    -- Disabled by hint
-    SELECT /*+ NO_PARALLEL_HEAP_SCAN */ * 
+    -- Disabled by hint (covers every scan flavor)
+    SELECT /*+ NO_PARALLEL_SCAN */ *
     FROM large_table;
 
-    -- When using index scan
-    SELECT /*+ PARALLEL(4) */ * 
-    FROM large_table 
-    WHERE indexed_column = 100 using index idx_large_table_indexed_column;
-
     -- SELECT FOR UPDATE
-    SELECT /*+ PARALLEL(4) */ * 
-    FROM large_table 
+    SELECT /*+ PARALLEL(4) */ *
+    FROM large_table
     FOR UPDATE;
 
     -- Using session variables
     SET @user_id = 123;
-    SELECT /*+ PARALLEL(4) */ * 
-    FROM orders 
+    SELECT /*+ PARALLEL(4) */ *
+    FROM orders
     WHERE customer_id = @user_id;
 
     -- Using SERIAL
-    SELECT /*+ PARALLEL(4) */ *, order_seq.NEXT_VALUE 
+    SELECT /*+ PARALLEL(4) */ *, order_seq.NEXT_VALUE
     FROM orders;
 
-Heap Scan Performance Considerations
-^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
+.. _parallel-heap-scan:
 
-Parallel heap scan has significant performance improvements in the following cases:
+Parallel Heap Scan
+^^^^^^^^^^^^^^^^^^
 
-*   When large table data needs to be scanned (more effective with more table pages)
-*   When selectivity is low (approximately 0.05 or less)
-*   When sufficient CPU cores are available
-*   When CPU processing is the bottleneck rather than disk I/O
+Parallel Heap Scan statically partitions the heap pages of a table by sector and lets workers scan their partitions concurrently. It can yield a large speedup over single-threaded heap scan, especially when selectivity is low (typically 0.05 or less).
 
-On the other hand, performance may degrade in the following cases:
+Heap scan has no additional flavor-specific restrictions beyond the :ref:`common constraints <parallel-scan>` listed above.
 
-*   When scanning small table data
-*   When index scan is more efficient
-*   When system resources (CPU, memory) are insufficient
+.. code-block:: sql
 
-When using parallel queries, the :ref:`max_parallel_workers <max_parallel_workers>` parameter should be set appropriately to prevent system resource contention. It is generally recommended to set it to the level of the actual physical CPU core count.
+    -- Parallel heap scan
+    SELECT /*+ PARALLEL(8) */ *
+    FROM large_table
+    WHERE status = 'active';
 
-Heap Scan Optimization (Mergeable List)
-^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
+    -- Parallel heap scan over a partitioned table
+    SELECT /*+ PARALLEL(8) */ *
+    FROM sales_partitioned
+    WHERE sale_date BETWEEN '2024-01-01' AND '2024-12-31';
+
+    -- INSERT SELECT (bulk copy)
+    INSERT INTO archive_orders
+    SELECT /*+ PARALLEL(8) */ *
+    FROM orders
+    WHERE order_date < '2023-01-01';
 
-Parallel heap scan operates with "mergeable list" optimization when certain conditions are met. In this method, each worker thread does not pass temporary results to the main thread but directly returns the final processed results to the main thread, significantly improving processing performance.
+.. _parallel-list-scan:
 
-Especially when processing large amounts of data (approximately 10 million records or more) with 8 or more cores, it shows much faster performance than the row-by-row method (receiving results one by one from each thread).
+Parallel List Scan
+^^^^^^^^^^^^^^^^^^
 
-**Constraints**
+Parallel List Scan statically partitions a temporary on-disk result list (list file) — produced by a subquery, derived table, or other intermediate operator — across workers by **sector**, and they read it concurrently. The partitioning mechanism itself is identical to parallel heap scan; the only difference is that the input is a temporary file rather than a table heap. It is effective when an upper operator must rescan a large intermediate result.
 
-When the following conditions are met, the mergeable list optimization is not applied and row-by-row processing is used:
+**Additional list-scan constraints**
 
-*   When the heap scan includes conditions that cannot be evaluated while scanning the target table
-*   When performing hash aggregation (hash group by)
-*   When there is a stored procedure (JavaSP or PL/CSQL) in the select-list
-*   When ROWNUM is used
-*   When performing topn_sort (sorting to extract top N)
-*   When there is a LIMIT clause
-*   When result_cache is enabled
+Parallel list scan is not applied — and falls back to a single-threaded list scan — if any of the following hold:
 
-**Representative Application Examples**
+*   The temporary list resides only in the in-memory buffer and has not spilled to a disk temp file (no sectors to partition — small lists fall back automatically).
+*   The upper XASL consumes results in row-by-row mode (a query shape that admits neither mergeable list nor BUILDVALUE; see :ref:`result-collection-modes`).
+*   The list scan sits inside the auxiliary input subtree (subquery, CTE, etc.) of a sort-merge join.
 
 .. code-block:: sql
 
-    -- Simple table full scan without join
-    SELECT /*+ PARALLEL(8) */ *
-    FROM large_table
-    WHERE status = 'active';
+    -- Typical pattern that benefits from parallel list scan:
+    -- the inner subquery materialises a list, which the outer
+    -- query then re-aggregates.
+    SELECT /*+ PARALLEL(8) */ region, COUNT(*)
+    FROM (
+        SELECT region, customer_id
+        FROM orders o, customers c
+        WHERE o.customer_id = c.id
+    ) t
+    GROUP BY region;
 
-    -- Table full scan followed by ORDER BY
-    SELECT /*+ PARALLEL(8) */ *
-    FROM large_table
-    WHERE created_date > '2024-01-01'
-    ORDER BY id;
+.. _parallel-index-scan:
 
-    -- Parallel heap scan in uncorrelated subquery
-    SELECT *
+Parallel Index Scan
+^^^^^^^^^^^^^^^^^^^
+
+Parallel Index Scan lets multiple workers cooperatively walk the leaf pages of a B+tree index through a shared cursor. The vertical descent (root → leaf entry) is performed serially by the main thread; the subsequent leaf traversal, OID fetching, and predicate evaluation are parallelised across workers. Each worker grabs one leaf page, processes its keys independently, and only briefly synchronises to obtain the next leaf.
+
+**Additional index-scan constraints**
+
+Parallel index scan is not applied — and falls back to a single-threaded index scan — if any of the following hold:
+
+*   The scan uses an index-driven traversal optimisation that changes how the tree is entered or walked:
+
+    *   ISS (Index Skip Scan)
+    *   ILS (Index Loose Scan)
+    *   KEYLIMIT clause
+    *   ORDERBY_SKIP / GROUPBY_SKIP / ORDERBY_DESC / GROUPBY_DESC
+    *   USE_DESC_INDEX hint
+    *   **filtered index** (a *function index*, however, is unaffected)
+    *   MIN/MAX single-key scan (min_max scan)
+
+*   The upper XASL imposes row-by-row semantics on the index scan through ROWNUM, ANALYTIC SKIP SORT, or ANALYTIC LIMIT OPT.
+*   The upper XASL consumes results in row-by-row mode (a query shape that admits neither mergeable list nor BUILDVALUE; see :ref:`result-collection-modes`).
+*   The index scan sits inside the auxiliary input subtree (subquery, CTE, etc.) of a sort-merge join.
+
+.. code-block:: sql
+
+    -- Typical case where parallel index scan applies
+    -- (covering / simple range over a large index)
+    CREATE INDEX idx_orders_status ON orders(status, order_date);
+
+    SELECT /*+ PARALLEL(8) */ order_id, order_date
     FROM orders
-    WHERE customer_id IN (
-        SELECT /*+ PARALLEL(8) */ customer_id
-        FROM customers
-        WHERE region = 'Asia'
-    );
+    WHERE status = 'completed' USING INDEX idx_orders_status;
 
-    -- Apply parallel heap scan to each sub-SELECT in UNION statement
-    SELECT /*+ PARALLEL(8) */ order_id, customer_id, order_date
-    FROM orders_2023
-    WHERE status = 'completed'
-    UNION
-    SELECT /*+ PARALLEL(8) */ order_id, customer_id, order_date
-    FROM orders_2024
+    -- Parallel index scan is NOT applied
+    -- (USE_DESC_INDEX hint forces single-threaded index scan)
+    SELECT /*+ PARALLEL(8) USE_DESC_INDEX */ *
+    FROM orders
     WHERE status = 'completed';
 
-    -- Parallel heap scan on partitioned table
-    SELECT /*+ PARALLEL(8) */ *
-    FROM sales_partitioned
-    WHERE sale_date BETWEEN '2024-01-01' AND '2024-12-31';
+.. note::
 
-    -- INSERT SELECT statement (copying large amounts of data)
-    INSERT INTO archive_orders
-    SELECT /*+ PARALLEL(8) */ *
-    FROM orders
-    WHERE order_date < '2023-01-01';
+    Because the tree descent is serial on the main thread and the leaf traversal is cooperative, parallel index scan pays off when the index has enough leaf pages. On small indexes the synchronisation cost can outweigh the speedup; the throughput rules (:ref:`parallel-query-throughput-rules`) guard against this.
+
+Performance Considerations
+^^^^^^^^^^^^^^^^^^^^^^^^^^
+
+Parallel scan delivers the largest gains in the following cases:
+
+*   Large inputs (tables, lists, indexes) — the more pages, the better
+*   Low selectivity (≈ 0.05 or less) for heap and index scans
+*   Sufficient CPU cores are available
+*   CPU processing — not disk I/O — is the bottleneck
+
+Conversely, performance can regress in these cases:
+
+*   The input has only a small number of pages
+*   A single-threaded index scan is already fast enough (e.g., short range / point lookup)
+*   System resources (CPU, memory) are scarce
+
+When using parallel queries, set the :ref:`max_parallel_workers <max_parallel_workers>` parameter so that workers do not contend excessively for system resources. A value close to the number of physical CPU cores is usually a good starting point.
+
+.. _result-collection-modes:
+
+Result Collection Modes
+^^^^^^^^^^^^^^^^^^^^^^^
+
+Once parallel scan is enabled, the way the main thread collects worker results depends on the query shape and is one of the three modes below. The mode appears as the **gather** field in the SQL trace.
+
+*   **mergeable list**: each worker builds its own temporary result list and the main thread uses those lists directly without merging. This has the lowest synchronisation cost and is usually the fastest mode.
+*   **buildvalue**: each worker computes a partial aggregate and the main thread combines the partials into the final aggregate. Used for simple aggregate queries (see :ref:`buildvalue-optimization`).
+*   **row-by-row**: the main thread receives one row at a time. Applies when neither of the other two modes can be used. It has the broadest applicability but the highest synchronisation cost.
+
+.. note::
+
+    The row-by-row mode is observed **only with parallel heap scan**. Parallel list scan and parallel index scan fall back to single-threaded execution for query shapes that would require row-by-row (see the additional constraints in their respective sections), so ``gather: row-by-row`` only appears in heap-scan traces.
+
+**When mergeable list is not chosen**
+
+Mergeable list is replaced by another mode if any of the following hold:
+
+*   The scan carries predicates that cannot be evaluated while scanning (deferred to an upper operator).
+*   Hash group-by is performed.
+*   The select-list contains a stored procedure (JavaSP or PL/CSQL).
+*   ROWNUM is used.
+*   topn_sort (sort to extract the top N) is performed.
+*   There is a LIMIT clause.
+*   result_cache is enabled.
+
+.. _buildvalue-optimization:
+
+BUILDVALUE Optimization
+^^^^^^^^^^^^^^^^^^^^^^^
+
+When the SELECT list consists solely of supported aggregate functions and there are no per-row semantics such as ROWNUM, parallel scan applies the **BUILDVALUE optimization**. In this mode, each worker computes a partial aggregate over its scanned region and ships it to the main thread, which then combines the partials into the final result. Because workers exchange the smallest possible amount of data, this is the fastest mode for simple aggregate queries.
+
+**Supported aggregate functions**
 
-COUNT Optimization
-""""""""""""""""""
+The BUILDVALUE optimization applies when the SELECT list uses only the following aggregate functions:
 
-Parallel heap scan provides special optimization mechanisms for **COUNT(\*)**, **COUNT(column)**, and **COUNT(DISTINCT column)** aggregate functions, which are the most frequently used. This method works by having each worker thread first calculate intermediate counts within their scanned range, and then finally summing the results.
+*   **COUNT(\*)**, **COUNT(column)**, **COUNT(DISTINCT column)**
+*   **MIN(column)**, **MAX(column)**
+*   **SUM(column)**, **AVG(column)**
+*   **STDDEV(column)**, **STDDEV_POP(column)**, **STDDEV_SAMP(column)**
+*   **VARIANCE(column)**, **VAR_POP(column)**, **VAR_SAMP(column)**
 
-**Conditions for COUNT Optimization**
+**Conditions**
 
-COUNT-specific optimization is applied when all of the following conditions are met:
+In addition to using only the supported aggregates, all of the following must hold:
 
-*   Contains only **COUNT(\*)**, **COUNT(column)**, or **COUNT(DISTINCT column)** aggregate functions
-*   No ROWNUM or stored procedures in the condition clause
-*   Simple query without other joins or subqueries
+*   The SELECT list contains only the supported aggregate functions (no non-aggregate output columns).
+*   The query has no ROWNUM and no stored procedures in its predicates.
+*   The query is simple — no joins or subqueries combined with the aggregate.
 
-**COUNT Optimization Operation**
+**Scope**
 
-*   **COUNT(\*)**: Each worker increments a simple counter, and finally the main thread sums all worker counts
-*   **COUNT(column)**: Each worker counts only non-NULL values, and finally the main thread sums all worker counts
-*   **COUNT(DISTINCT column)**: Each worker stores values in a separate list file to remove duplicates and passes them on, and the main thread merges all lists received from workers to calculate the total DISTINCT count
+The BUILDVALUE optimization is independent of the scan flavor and can be applied to:
 
-**COUNT Optimization Examples**
+*   Parallel heap scan
+*   Parallel list scan
+*   Parallel index scan
+
+**Examples**
 
 .. code-block:: sql
 
-    -- COUNT(*) optimization
+    -- COUNT family
     SELECT /*+ PARALLEL(8) */ COUNT(*)
     FROM large_table
     WHERE status = 'active';
 
-    -- COUNT(column) optimization
-    SELECT /*+ PARALLEL(8) */ COUNT(customer_id)
+    SELECT /*+ PARALLEL(8) */ COUNT(DISTINCT customer_id)
+    FROM orders;
+
+    -- Arithmetic aggregates (heap, list, or index scan)
+    SELECT /*+ PARALLEL(8) */ SUM(amount), AVG(amount), MAX(amount)
     FROM orders
     WHERE order_date > '2024-01-01';
 
-    -- COUNT(DISTINCT) optimization
-    SELECT /*+ PARALLEL(8) */ COUNT(DISTINCT customer_id)
-    FROM orders;
+    -- Variance / standard deviation
+    SELECT /*+ PARALLEL(8) */ STDDEV(price), VARIANCE(price)
+    FROM products;
 
-    -- Usage in UPDATE STATISTICS
+    -- UPDATE STATISTICS internally benefits from BUILDVALUE optimization as well
     UPDATE STATISTICS ON large_table WITH FULLSCAN;
 
 .. note::
 
-    COUNT optimization is a specialized optimization for simple aggregation. When used with other aggregate functions (SUM, AVG, etc.) or when complex joins are included, it is not applied and processing uses the general parallel heap scan method (mergeable list or row-by-row).
+    If the SELECT list mixes the supported aggregates with other expressions (e.g., plain columns, unsupported aggregate functions) or is combined with GROUP BY, the BUILDVALUE optimization is not applied and the query is processed in the mergeable list or row-by-row mode instead.
 
-Heap Scan SQL Trace
-^^^^^^^^^^^^^^^^^^^^
+Scan SQL Trace
+^^^^^^^^^^^^^^
 
-When parallel heap scan is performed, parallel processing details are additionally output in the :ref:`SQL trace <query-profiling>` results.
+When parallel scan is performed, parallel processing details are added to the :ref:`SQL trace <query-profiling>` output.
 
 .. code-block:: sql
 
     csql> ;trace on
 
-    SELECT /*+ PARALLEL(4) RECOMPILE */ count(*) 
-    FROM large_table 
+    SELECT /*+ PARALLEL(4) RECOMPILE */ count(*)
+    FROM large_table
     WHERE status = 'active';
 
 ::
@@ -251,30 +324,30 @@ When parallel heap scan is performed, parallel processing details are additional
     Trace Statistics:
         SELECT (time: 2405, fetch: 143277, fetch_time: 1287, ioread: 123467)
             SCAN (table: dba.large_table), (heap time: 2395, fetch: 143277, ioread: 123467, readrows: 0, rows: 0)
-                 (parallel workers: 8, heap time: 2390..2395, readrows: 1249989..1250011, 
+                 (parallel workers: 8, heap time: 2390..2395, readrows: 1249989..1250011,
                   rows: 1249989..1250011, gather: mergeable list)
 
-The description of parallel heap scan trace output items is as follows:
+The parallel scan trace fields are:
+
+*   **parallel workers**: number of worker threads used.
+*   **heap time / list time / index time**: per-worker scan time range (min..max, milliseconds). The label changes with the scan flavor.
+*   **readrows**: per-worker range of rows read (min..max).
+*   **rows**: per-worker range of rows produced (min..max).
+*   **gather**: how worker results were collected.
 
-*   **parallel workers**: Number of worker threads used
-*   **heap time**: Range of heap scan time for each worker (min..max, milliseconds)
-*   **readrows**: Range of rows read by each worker (min..max)
-*   **rows**: Range of rows returned by each worker (min..max)
-*   **gather**: Result collection method
-    
-    * **mergeable list**: Optimized method that directly uses each worker's results without separate merging
-    * **row-by-row**: Basic method that collects and merges each worker's results one by one
-    * **count**: COUNT-specific optimization method where each worker performs local counting and merges final results
+    *   **mergeable list**: per-worker lists are used directly without merging.
+    *   **buildvalue**: per-worker partial aggregates are combined (replaces the legacy ``count`` label).
+    *   **row-by-row**: rows are collected one at a time (heap scan only).
 
-When the **gather** item shows **mergeable list** or **count**, it indicates that parallel heap scan optimization is applied, showing better performance.
+When **gather** shows **mergeable list** or **buildvalue**, the query took the lowest-synchronisation path.
 
 .. note::
 
-    The time and number of rows for parallel workers are displayed as ranges (min..max), and ideally all workers should perform similar amounts of work. If the range is wide, you may suspect data distribution or system resource contention issues.
+    Per-worker times and row counts appear as min..max ranges. Ideally all workers do similar amounts of work; a wide range hints at uneven data distribution or system resource contention.
 
-**COUNT Optimization Trace Information Example**
+**BUILDVALUE optimization trace example**
 
-When COUNT optimization is applied, **gather: count** is displayed:
+When BUILDVALUE optimization is applied, **gather: buildvalue** is shown. Because only one aggregate row is produced overall, per-worker ``rows`` is reported as 0.
 
 .. code-block:: sql
 
@@ -289,9 +362,26 @@ When COUNT optimization is applied, **gather: count** is displayed:
         SELECT (time: 1500, fetch: 1, fetch_time: 10, ioread: 100000)
             SCAN (table: dba.large_table), (heap time: 1490, fetch: 100000, ioread: 100000, readrows: 0, rows: 0)
                  (parallel workers: 8, heap time: 1485..1490, readrows: 1250000..1250000,
-                  rows: 0..0, gather: count)
+                  rows: 0..0, gather: buildvalue)
+
+**Parallel index scan trace example**
+
+.. code-block:: sql
+
+    csql> ;trace on
 
-COUNT optimization shows rows as 0 because the result is a single row, and the actual count result is returned through the aggregate function.
+    SELECT /*+ PARALLEL(4) RECOMPILE */ order_id, order_date
+    FROM orders
+    WHERE status = 'completed' USING INDEX idx_orders_status;
+
+::
+
+    Trace Statistics:
+        SELECT (time: 980, fetch: 51200, fetch_time: 410, ioread: 0)
+            SCAN (table: dba.orders, index: idx_orders_status),
+                 (key time: 970, fetch: 51200, ioread: 0, readkeys: 1, filteredkeys: 0,
+                  rows: 0, parallel workers: 4, key time: 965..970, rows: 312500..312500,
+                  gather: mergeable list)
 
 .. _parallel-subquery-execution:
 
@@ -362,7 +452,6 @@ Parallel execution of subqueries is not applied if any of the following conditio
     -- Examples where parallel execution is not applied
 
     -- Using NO_PARALLEL_SUBQUERY hint
-    -- Two subqueries exist, but parallel execution is disabled by hint
     SELECT /*+ NO_PARALLEL_SUBQUERY */ *
     FROM orders
     WHERE customer_id IN (
@@ -373,7 +462,6 @@ Parallel execution of subqueries is not applied if any of the following conditio
     );
 
     -- When there are references between CTEs
-    -- cte2 references cte1, so they are not independent
     WITH cte1 AS (
         SELECT * FROM table1
     ),
@@ -383,7 +471,6 @@ Parallel execution of subqueries is not applied if any of the following conditio
     SELECT * FROM cte2;
 
     -- Using JSON_TABLE
-    -- When JSON_TABLE is included, parallel execution is not applied even with 2+ subqueries
     SELECT *
     FROM orders,
     JSON_TABLE(json_column, '$[*]' COLUMNS(id INT PATH '$.id')) AS jt
@@ -395,7 +482,6 @@ Parallel execution of subqueries is not applied if any of the following conditio
     );
 
     -- When stored procedure is included in condition clause
-    -- Two subqueries exist, but one contains a stored procedure, so no parallel execution
     SELECT *
     FROM orders
     WHERE customer_id IN (
@@ -490,26 +576,26 @@ While parallel query execution dramatically reduces query response time, it also
 
 The actual degree of parallelism for each parallel operation is determined by the following factors:
 
-*   Throughput rules such as table size and number of partitions
+*   Throughput rules based on the size of the input (table, list, or index)
 *   Values explicitly specified by **PARALLEL** hints
 *   Upper limit set by the :ref:`parallelism <parallelism>` parameter
 *   Global worker pool size set by the :ref:`max_parallel_workers <max_parallel_workers>` parameter
 
 The degree of parallelism calculated by throughput rules cannot exceed the :ref:`parallelism <parallelism>` parameter value. The degree of parallelism specified by hints can exceed the :ref:`parallelism <parallelism>` parameter value but cannot exceed the maximum value (the smaller of 32 or the number of system cores).
 
-Heap Scan Throughput Rules
-^^^^^^^^^^^^^^^^^^^^^^^^^^^
+Scan Throughput Rules
+^^^^^^^^^^^^^^^^^^^^^
 
-The degree of parallelism for parallel heap scan is determined by the number of pages in the target table to be scanned.
+The degree of parallelism for parallel scan (heap, list, or index) is determined by the same rule based on the page count of the scan input. Heap scan uses the table's heap page count, list scan uses the temporary list page count, and index scan uses the index leaf page count.
 
 **Activation Condition**
 
-*   Activated when the target table has 4,096 or more pages (approximately 64MB when db_page_size is 16K)
-*   If this condition is not met, parallel heap scan is not activated even if the **PARALLEL** hint is present
+*   Activated when the input has 2,048 or more pages (approximately 32 MB when db_page_size is 16K).
+*   If this condition is not met, parallel scan is not activated even if the **PARALLEL** hint is present.
 
 **Degree Determination**
 
-The degree of parallelism is determined according to the number of pages in the table as follows:
+The degree of parallelism is determined according to the page count as follows:
 
 .. csv-table::
    :header: "Number of Pages", "Throughput", "Throughput Rule Calculation"
@@ -529,7 +615,7 @@ The degree of parallelism is determined according to the number of pages in the
    "4,194,304", "64.0 GB", "13"
    "8,388,608", "128.0 GB", "14"
 
-Starting from 2,048 pages, the degree of parallelism calculated by throughput rule increases by 1 each time the number of pages doubles from the previous increase threshold.
+Starting from 2,048 pages, the degree of parallelism calculated by the throughput rule increases by 1 each time the page count doubles from the previous threshold.
 
 **The degree of parallelism determined by throughput rules cannot exceed the** :ref:`parallelism <parallelism>` **parameter value:**
 
@@ -537,13 +623,13 @@ Starting from 2,048 pages, the degree of parallelism calculated by throughput ru
 
 For example, when parallelism=4 (default):
 
-*   Page count 4,096 → throughput rule calculates 2 → MIN(2, 4) = **2** applied
+*   Page count 2,048 → throughput rule calculates 2 → MIN(2, 4) = **2** applied
 
-*   Page count 65,536 → throughput rule calculates 6 → MIN(6, 4) = **4** applied (cannot exceed parallelism)
+*   Page count 65,536 → throughput rule calculates 7 → MIN(7, 4) = **4** applied (cannot exceed parallelism)
 
 .. note::
 
-    When the degree of parallelism is explicitly specified using the **PARALLEL** hint, the throughput rules are not applied and the hint value is used.
+    Even when the degree of parallelism is explicitly specified using the **PARALLEL** hint, the activation condition (2,048 or more pages) still applies. After activation, the hint value takes precedence in determining the degree of parallelism.
 
 **Example**
 
@@ -551,25 +637,25 @@ For example, when parallelism=4 (default):
 
     -- Create table and insert data
     CREATE TABLE large_table (c1 INT);
-    
+
     INSERT INTO large_table
     WITH RECURSIVE cte (n) AS (
-        SELECT 1 
-        UNION ALL 
+        SELECT 1
+        UNION ALL
         SELECT n + 1 FROM cte WHERE n < 2000
     )
     SELECT ROWNUM FROM cte a, cte b, cte c LIMIT 2200000;
-    
+
     UPDATE STATISTICS ON large_table WITH FULLSCAN;
-    
+
     -- Check table statistics
     -- Total pages in class heap: 4215 (approximately 66MB when db_page_size is 16K)
     -- Total objects: 2200000
-    
+
     -- When parallelism parameter is set to 4
-    -- Page count 4215 is 4,096 or more, so degree of parallelism 2 is automatically applied
+    -- Page count 4215 is at least 2,048, so degree of parallelism 3 is automatically applied
     SELECT COUNT(*) FROM large_table;
-    
+
     -- Explicit specification with hint
     SELECT /*+ PARALLEL(8) */ COUNT(*) FROM large_table;
 
@@ -634,8 +720,8 @@ Throughput Performance Considerations
 
 Optimization through parallel query throughput rules:
 
-*   Prevents unnecessary parallel execution on small tables to reduce overhead
-*   Automatically adjusts the degree of parallelism proportional to table size
+*   Prevents unnecessary parallel execution on small inputs to reduce overhead
+*   Automatically adjusts the degree of parallelism proportional to input size
 *   Prevents system resource contention due to excessive parallel execution
 *   Concentrates parallel resources on queries with significant benefits
 
@@ -645,5 +731,3 @@ Recommended Settings:
 *   **parallelism**: Set considering the number of physical cores in the system (usually 4~8 is appropriate)
 *   In environments with many large tables, set **max_parallel_workers** value high
 *   In environments with many small tables, using default values is recommended
-
-
diff --git a/en/sql/tuning.rst b/en/sql/tuning.rst
index 60d962c5b..ae222f075 100644
--- a/en/sql/tuning.rst
+++ b/en/sql/tuning.rst
@@ -937,7 +937,7 @@ Using hints can affect the performance of query execution. You can allow the que
     NO_HASH_LIST_SCAN |
     NO_LOGGING |
     PARALLEL (<degree>) |
-    NO_PARALLEL_HEAP_SCAN |
+    NO_PARALLEL_SCAN |
     NO_PARALLEL_SUBQUERY |
     RECOMPILE |
     QUERY_CACHE
@@ -1009,19 +1009,19 @@ The following hints can be specified in **UPDATE**, **DELETE** and **SELECT** st
 
 .. _parallel-hint:
 
-*   **PARALLEL** ( *degree* ): This is a hint to enable parallel query execution (parallel heap scan, parallel subquery execution, parallel hash join, parallel sort) and specify the degree of parallelism. *degree* must be an integer value of 0 or higher, indicating the number of worker threads to use for parallel processing. When set to 0 or 1, parallel processing is disabled. For more details, see :ref:`parallel-query`.
+*   **PARALLEL** ( *degree* ): This is a hint to enable parallel query execution (parallel scan over heap/list/index inputs, parallel subquery execution, parallel hash join, parallel sort) and specify the degree of parallelism. *degree* must be an integer value of 0 or higher, indicating the number of worker threads to use for parallel processing. When set to 0 or 1, parallel processing is disabled. For more details, see :ref:`parallel-query`.
 
     .. code-block:: sql
 
         SELECT /*+ PARALLEL(4) */ * FROM large_table WHERE condition;
 
-.. _no-parallel-heap-scan:
+.. _no-parallel-scan:
 
-*   **NO_PARALLEL_HEAP_SCAN**: This is a hint to disable parallel heap scan. For more details, see :ref:`parallel-query`.
+*   **NO_PARALLEL_SCAN**: This is a hint to disable every parallel scan flavor (heap, list, and index) within the query block. For more details, see :ref:`parallel-query`.
 
     .. code-block:: sql
 
-        SELECT /*+ NO_PARALLEL_HEAP_SCAN */ * FROM large_table WHERE condition;
+        SELECT /*+ NO_PARALLEL_SCAN */ * FROM large_table WHERE condition;
 
 .. _no-parallel-subquery:
 
diff --git a/ko/admin/config.rst b/ko/admin/config.rst
index 987742cd5..233dfcecb 100644
--- a/ko/admin/config.rst
+++ b/ko/admin/config.rst
@@ -745,7 +745,7 @@ CUBRID 설치 시 생성되는 기본 데이터베이스 환경 설정 파일(**
 
     **max_parallel_workers**\ 는 서버 전체에서 동시에 실행할 수 있는 병렬 질의 워커(parallel query worker) 스레드의 최대 개수를 설정하는 파라미터이다. 기본값은 **100**\ 이며, 최소값은 **0**, 최대값은 **1000**\ 이다.
 
-    이 파라미터가 **0**\ 으로 설정되면 병렬 질의 기능이 비활성화된다. **2 이상**\ 으로 설정하면 병렬 힙 스캔(Parallel Heap Scan), 병렬 부질의 실행(Parallel Subquery Execution), 병렬 해시 조인(Parallel Hash Join), 병렬 정렬(Parallel Sort) 등 다양한 병렬 처리 기능을 사용할 수 있다.
+    이 파라미터가 **0**\ 으로 설정되면 병렬 질의 기능이 비활성화된다. **2 이상**\ 으로 설정하면 병렬 스캔(Parallel Scan; 힙/리스트/인덱스), 병렬 부질의 실행(Parallel Subquery Execution), 병렬 해시 조인(Parallel Hash Join), 병렬 정렬(Parallel Sort) 등 다양한 병렬 처리 기능을 사용할 수 있다.
 
     서버는 **전역 워커 풀(worker pool)**\ 을 통해 병렬 질의 실행 작업을 관리한다. 다수의 세션이 동시에 병렬 질의를 요청하거나 단일 세션 내에서 복합적인 병렬 연산이 수행되더라도 서버 전체에서 활성화된 병렬 워커의 총합은 **max_parallel_workers** 값을 초과할 수 없다.
 
diff --git a/ko/sql/parallel.rst b/ko/sql/parallel.rst
index 72788b77d..41ebb748d 100644
--- a/ko/sql/parallel.rst
+++ b/ko/sql/parallel.rst
@@ -11,242 +11,311 @@ CUBRID는 대량의 데이터를 효율적으로 처리하기 위해 병렬 질
 
 병렬 질의는 다음과 같은 주요 기능을 제공한다:
 
-*   **병렬 힙 스캔(Parallel Heap Scan)**: 여러 워커 스레드가 힙 리전을 나누어 스캔하여 대용량 테이블 탐색 속도 성능을 향상시킨다. 
-*   **병렬 부질의 실행(Parallel Uncorrelated Subquery Execution)**: 서로 독립적인 부질의 (uncorrelated subquery)들을 워커들이 각자 맡아 동시에 처리하여 질의의 응답 속도를 개선한다.
+*   **병렬 스캔(Parallel Scan)**: 여러 워커 스레드가 입력 데이터(힙, 임시 리스트, 인덱스)를 나누어 스캔하여 대용량 탐색의 성능을 향상시킨다. 스캔 종류에 따라 다음 세 가지로 세분화된다.
+
+    *   **병렬 힙 스캔(Parallel Heap Scan)**: 테이블의 힙 페이지를 섹터(sector) 단위로 분할하여 워커들이 동시에 스캔한다.
+    *   **병렬 리스트 스캔(Parallel List Scan)**: 부질의 등으로 생성되어 디스크에 떨어진 임시 결과 리스트(list file)를 섹터(sector) 단위로 분할하여 워커들이 동시에 스캔한다.
+    *   **병렬 인덱스 스캔(Parallel Index Scan)**: B+트리 인덱스의 리프 페이지 체인을 워커들이 공유 커서로 협력하여 좌→우(또는 우→좌)로 진행하면서 스캔한다.
+
+*   **병렬 부질의 실행(Parallel Uncorrelated Subquery Execution)**: 서로 독립적인 부질의(uncorrelated subquery)들을 워커들이 각자 맡아 동시에 처리하여 질의의 응답 속도를 개선한다.
 *   **병렬 해시 조인(Parallel Hash Join)**: 빌드(build) 단계와 프로브(probe) 단계를 병렬화하여, 해시 조인 연산시 응답 속도를 개선한다.
 *   **병렬 정렬(Parallel Sort)**: 정렬할 데이터를 분할하여 여러 워커 스레드를 통해 정렬한 후 병합하는 과정을 병렬로 수행하여 정렬 응답 속도를 개선한다.
 
 설정 방법
 ^^^^^^^^^
 
-병렬 질의 실행은 시스템 파라미터와 SQL 힌트를 통해 제어할 수 있다. 
+병렬 질의 실행은 시스템 파라미터와 SQL 힌트를 통해 제어할 수 있다.
 
 *   :ref:`parallelism <parallelism>` 파라미터를 2 이상으로 설정하면, 옵티마이저가 질의 수행시 병렬 질의 실행 여부를 판단할 수 있게 활성화된다.
 *   **PARALLEL** ( *degree* ) 힌트를 사용하여 쿼리별로 병렬 처리 정도를 명시적으로 지정할 수 있다. *degree* 는 사용할 워커수이며, 2 이상의 정수 값이어야 한다. 힌트로 지정한 값은 parallelism 파라미터 설정보다 우선한다.
 *   :ref:`max_parallel_workers <max_parallel_workers>` 파라미터는 서버 전체에서 동시에 실행 가능한 병렬 워커 스레드의 최대 개수를 설정한다(기본값: 100).
+*   **NO_PARALLEL_SCAN** 힌트는 해당 쿼리 블록의 모든 병렬 스캔(힙/리스트/인덱스)을 비활성화한다. **PARALLEL** 힌트와 같이 사용하는 경우에는 **NO_PARALLEL_SCAN** 이 우선 적용된다.
 
 .. note::
 
     max_parallel_workers와 parallelism 파라미터는 기본값이 각각 100과 4로 설정되어 있어 별도 설정 없이도 병렬 질의를 사용할 수 있다.
 
-.. _parallel-heap-scan:
-
-병렬 힙 스캔
-------------
+.. _parallel-scan:
 
-병렬 힙 스캔(Parallel Heap Scan)은 대량의 데이터를 스캔할 때 여러 워커 스레드를 사용하여 힙 테이블의 스캔 성능을 향상시키는 기능이다. 
-특히, 선택도(selectivity)가 낮은 경우(일반적으로 0.05 이하) 대량의 데이터를 처리하는 속도가 단일 스레드 방식의 힙 스캔보다 성능이 크게 향상될 수 있다.
+병렬 스캔
+---------
 
-힙 스캔 개요
-^^^^^^^^^^^^
+병렬 스캔(Parallel Scan)은 단일 스캔 입력을 여러 워커 스레드가 분할하여 동시에 처리하는 기능이다. CUBRID는 다음 세 가지 입력에 대해 병렬 스캔을 지원하며, 모두 동일한 병렬 실행 프레임워크를 공유한다.
 
-병렬 힙 스캔은 대량의 테이블을 논리적 단위로 나누어 여러 워커 스레드가 동시에 스캔하고, 각 워커 스레드는 할당된 페이지를 독립적으로 스캔하면서 필터링 조건(predicate)를 처리한다. 
-처리된 결과는 결과 큐(result queue)를 통해 수집되며, 메인 스레드는 이 결과를 통합하여 최종 결과를 생성하고 사용자에게 반환한다.
+*   **힙(Heap)**: 테이블의 힙 페이지 — **섹터** 단위로 워커들에게 사전 분할
+*   **리스트(List)**: 디스크로 떨어진 임시 결과 리스트 파일 — **섹터** 단위로 워커들에게 사전 분할
+*   **인덱스(Index)**: B+트리 리프 페이지 — 공유 **커서**\를 통해 워커들이 협력적으로 좌→우(또는 우→좌) 진행
 
-**NO_PARALLEL_HEAP_SCAN** 힌트를 사용하면 병렬 힙 스캔을 비활성화할 수 있다. **PARALLEL** 힌트와 같이 사용하는 경우에는 **NO_PARALLEL_HEAP_SCAN** 힌트가 우선된다.
+각 워커 스레드는 할당된 영역을 독립적으로 스캔하면서 필터링 조건(predicate)을 평가하고, 처리한 결과는 결과 큐를 통해 메인 스레드에 전달되어 최종 결과로 통합된다.
 
 .. note::
 
-    병렬 힙 스캔의 실제 병렬 처리 수준은 사용자가 설정한 상한값 내에서 처리량 규칙에 의해 자동으로 최적화된다. 자세한 내용은 :ref:`parallel-query-throughput-rules`\ 를 참고한다.
+    실제 병렬 처리 수준은 사용자가 설정한 상한값 내에서 처리량 규칙에 의해 자동으로 최적화된다. 자세한 내용은 :ref:`parallel-query-throughput-rules`\ 를 참고한다.
 
-제약 조건
-^^^^^^^^^^^^^^^^^^
+공통 제약 조건
+^^^^^^^^^^^^^^
 
-다음 조건 중 하나라도 해당되면 병렬 힙 스캔이 지원되지 않으며, 단일 스레드 방식으로 실행된다.:
+다음 조건 중 하나라도 해당되면 스캔 종류와 무관하게 병렬 스캔이 적용되지 않으며, 단일 스레드 방식으로 실행된다.
 
-*   동시성 처리를 지원하지 않는 구문이 포함된 경우 
+*   동시성 처리를 지원하지 않는 구문이 포함된 경우
 
     *    저장프로시저(JavaSP, PL/CSQL), Serial 사용시
-
     *    세션 변수를 참조시
-  
     *    Recursive CTE 또는 Connect By 구문 사용시
-  
     *    CUBRID 오브젝트 DBMS 전용 기능 사용시
 
-*   배타적 잠금(X-LOCK) 획득이 필요한 경우  
+*   배타적 잠금(X-LOCK) 획득이 필요한 경우
 
-    *    SELECT ... FOR UPDATE 구문  
-    *    incr() 함수 사용시  
-    *    update, delete, merge 구문  
+    *    SELECT ... FOR UPDATE 구문
+    *    incr() 함수 사용시
+    *    update, delete, merge 구문
 
-*   JOIN문에서 첫번째로 드라이빙되는 테이블이 아닌 경우 
-*   상관 부질의(correlated subquey)인 경우
-*   인덱스 스캔(index scan)을 통해 데이터를 읽는 경우
+*   JOIN문에서 첫번째로 드라이빙되는 테이블이 아닌 경우
+*   상관 부질의(correlated subquery)인 경우
+*   소트 머지 조인의 외부/내부 입력으로 사용되는 스캔 (모든 스캔 종류)
+*   **NO_PARALLEL_SCAN** 힌트가 명시된 경우
 
-.. note::
-
-    max_parallel_workers와 parallelism 파라미터의 기본값은 별도의 설정 없이도 병렬 질의를 사용할 수 있도록 기본값을 제공한다. 시스템 리소스나 응용프로그램의 워크로드에 따라 cubrid.conf 파일의 해당 값을 수정하여 성능을 추가로 최적화할 수 있다. ::
-
-        # cubrid.conf
-        max_parallel_workers=200  # 기본값: 100
-        parallelism=8             # 기본값: 4
+스캔 종류별로 추가 제약이 있다. 아래 각 절을 참고한다.
 
 .. code-block:: sql
 
-    -- 병렬 힙 스캔이 적용되지 않는 예
+    -- 병렬 스캔이 적용되지 않는 예
 
-    -- 힌트로 비활성화
-    SELECT /*+ NO_PARALLEL_HEAP_SCAN */ * 
+    -- 힌트로 비활성화 (모든 스캔 종류)
+    SELECT /*+ NO_PARALLEL_SCAN */ *
     FROM large_table;
 
-    -- 인덱스 스캔 사용 시
-    SELECT /*+ PARALLEL(4) */ * 
-    FROM large_table 
-    WHERE indexed_column = 100 using index idx_large_table_indexed_column;
-
     -- SELECT FOR UPDATE
-    SELECT /*+ PARALLEL(4) */ * 
-    FROM large_table 
+    SELECT /*+ PARALLEL(4) */ *
+    FROM large_table
     FOR UPDATE;
 
     -- 세션 변수 사용
     SET @user_id = 123;
-    SELECT /*+ PARALLEL(4) */ * 
-    FROM orders 
+    SELECT /*+ PARALLEL(4) */ *
+    FROM orders
     WHERE customer_id = @user_id;
 
     -- SERIAL 사용
-    SELECT /*+ PARALLEL(4) */ *, order_seq.NEXT_VALUE 
+    SELECT /*+ PARALLEL(4) */ *, order_seq.NEXT_VALUE
     FROM orders;
 
-힙 스캔 성능 고려사항
-^^^^^^^^^^^^^^^^^^^^^
+.. _parallel-heap-scan:
+
+병렬 힙 스캔
+^^^^^^^^^^^^
+
+병렬 힙 스캔(Parallel Heap Scan)은 테이블의 힙 페이지를 섹터(sector) 단위로 워커들에게 정적으로 분배하여 동시 스캔하는 기능이다. 특히 선택도(selectivity)가 낮은 경우(일반적으로 0.05 이하) 단일 스레드 방식의 힙 스캔보다 응답 속도가 크게 향상될 수 있다.
+
+힙 스캔에 한정되는 추가 제약은 없다. 위에서 설명한 :ref:`공통 제약 <parallel-scan>`\ 만 적용된다.
+
+.. code-block:: sql
+
+    -- 병렬 힙 스캔 예
+    SELECT /*+ PARALLEL(8) */ *
+    FROM large_table
+    WHERE status = 'active';
+
+    -- 파티션 테이블의 병렬 힙 스캔
+    SELECT /*+ PARALLEL(8) */ *
+    FROM sales_partitioned
+    WHERE sale_date BETWEEN '2024-01-01' AND '2024-12-31';
+
+    -- INSERT SELECT 문 (대용량 데이터 복사)
+    INSERT INTO archive_orders
+    SELECT /*+ PARALLEL(8) */ *
+    FROM orders
+    WHERE order_date < '2023-01-01';
+
+.. _parallel-list-scan:
+
+병렬 리스트 스캔
+^^^^^^^^^^^^^^^^
+
+병렬 리스트 스캔(Parallel List Scan)은 부질의나 derived table 등 중간 단계에서 디스크 임시 파일(temp file)로 떨어진 결과 리스트를 섹터(sector) 단위로 워커들에게 정적으로 분배하여 동시 스캔하는 기능이다. 분할 메커니즘 자체는 힙 스캔과 동일하며, 입력이 테이블 힙 대신 임시 파일이라는 점만 다르다. 상위 연산이 큰 임시 결과를 다시 스캔해야 할 때 효과적이다.
+
+**리스트 스캔 추가 제약**
+
+다음 조건 중 하나라도 해당되면 병렬 리스트 스캔이 적용되지 않으며, 단일 스레드 리스트 스캔으로 실행된다.
+
+*   임시 리스트가 메모리 버퍼에만 존재하고 디스크 임시 파일로 떨어지지 않은 경우 (분할할 섹터가 없음 — small list 자동 fallback)
+*   상위 XASL이 결과를 한 행씩 받아가는 row-by-row 모드로 동작하는 경우 (mergeable list 와 BUILDVALUE 모두 적용 불가한 형태의 쿼리)
+*   소트 머지 조인의 보조 입력 트리(서브쿼리/CTE 등) 안에 위치한 리스트 스캔
+
+.. code-block:: sql
+
+    -- 병렬 리스트 스캔이 적용되는 전형적인 패턴
+    -- 내부 derived table 결과 리스트를 외부에서 다시 집계
+    SELECT /*+ PARALLEL(8) */ region, COUNT(*)
+    FROM (
+        SELECT region, customer_id
+        FROM orders o, customers c
+        WHERE o.customer_id = c.id
+    ) t
+    GROUP BY region;
+
+.. _parallel-index-scan:
+
+병렬 인덱스 스캔
+^^^^^^^^^^^^^^^^
+
+병렬 인덱스 스캔(Parallel Index Scan)은 B+트리 인덱스의 리프 페이지 체인을 여러 워커가 공유 커서를 통해 협력적으로 진행하면서 읽는 기능이다. 인덱스 진입(루트→리프 수직 탐색)은 메인 스레드가 단일 스레드로 수행하며, 그 이후의 리프 순회와 OID 페치/필터 평가가 워커들에 의해 병렬로 수행된다. 워커는 리프 한 페이지를 잡으면 그 안의 키들을 독립적으로 처리하고, 다음 리프를 얻기 위해서만 짧게 동기화한다.
+
+**인덱스 스캔 추가 제약**
+
+다음 조건 중 하나라도 해당되면 병렬 인덱스 스캔이 적용되지 않으며, 단일 스레드 인덱스 스캔으로 실행된다.
+
+*   리프 순서·진입 방식에 의존하는 인덱스 최적화가 적용된 경우
+
+    *   ISS(Index Skip Scan)
+    *   ILS(Index Loose Scan)
+    *   KEYLIMIT 절
+    *   ORDERBY_SKIP / GROUPBY_SKIP / ORDERBY_DESC / GROUPBY_DESC
+    *   USE_DESC_INDEX 힌트
+    *   **filtered index** 사용 (단, *function index*\는 영향을 받지 않음)
+    *   MIN/MAX 단일 키 조회 (min_max scan)
+
+*   상위 XASL이 인덱스 스캔에 ROWNUM, ANALYTIC SKIP SORT, ANALYTIC LIMIT OPT 등 row-by-row 의미를 강제하는 경우
+*   상위 XASL이 결과를 한 행씩 받아가는 row-by-row 모드로 동작하는 경우 (mergeable list 와 BUILDVALUE 모두 적용 불가한 형태의 쿼리)
+*   소트 머지 조인의 보조 입력 트리(서브쿼리/CTE 등) 안에 위치한 인덱스 스캔
+
+.. code-block:: sql
+
+    -- 병렬 인덱스 스캔이 적용되는 전형적인 예
+    -- (커버링 또는 단순 범위 조건의 인덱스 풀 스캔)
+    CREATE INDEX idx_orders_status ON orders(status, order_date);
+
+    SELECT /*+ PARALLEL(8) */ order_id, order_date
+    FROM orders
+    WHERE status = 'completed' USING INDEX idx_orders_status;
 
-병렬 힙 스캔은 다음과 같은 경우에 성능 향상 효과가 크다:
+    -- 병렬 인덱스 스캔이 적용되지 않는 예
+    -- (USE_DESC_INDEX 힌트 → 단일 스레드 인덱스 스캔)
+    SELECT /*+ PARALLEL(8) USE_DESC_INDEX */ *
+    FROM orders
+    WHERE status = 'completed';
+
+.. note::
+
+    병렬 인덱스 스캔은 메인 스레드의 인덱스 진입과 워커들의 리프 동기화 비용이 존재하기 때문에, 인덱스의 리프 페이지 수가 충분히 많을 때 효과가 크다. 작은 인덱스에서는 동기화 비용이 절감 효과를 상쇄할 수 있으며, 이를 막기 위해 처리량 규칙(:ref:`parallel-query-throughput-rules`)이 함께 적용된다.
+
+성능 고려사항
+^^^^^^^^^^^^^
+
+병렬 스캔은 다음과 같은 경우에 성능 향상 효과가 크다.
 
-*   대용량의 테이블 데이터를 스캔해야 하는 경우 (테이블의 페이지 수가 많을수록 효과적)  
-*   선택도(selectivity)가 낮은 경우 (약 0.05 이하)
+*   대용량 입력(테이블/리스트/인덱스)을 스캔해야 하는 경우 (페이지 수가 많을수록 효과적)
+*   힙/인덱스 스캔에서 선택도가 낮은 경우 (약 0.05 이하)
 *   CPU 코어가 충분히 사용 가능한 경우
 *   디스크 I/O보다 CPU 처리가 병목인 경우
 
-반면, 다음과 같은 경우에는 오히려 성능이 저하될 수 있다:
+반면, 다음과 같은 경우에는 오히려 성능이 저하될 수 있다.
 
-*   소량의 테이블 데이터를 스캔하는 경우
-*   인덱스 스캔이 더 효율적인 경우
+*   소량의 입력만 스캔하는 경우
+*   인덱스 스캔이 단일 스레드로 충분히 효율적인 경우(예: 짧은 범위 점 조회)
 *   시스템 리소스(CPU, 메모리)가 부족한 경우
 
 병렬 질의 사용 시에는 :ref:`max_parallel_workers <max_parallel_workers>` 파라미터를 적절히 설정하여 시스템 리소스 경쟁을 방지해야 한다. 일반적으로 실제 물리 CPU 코어 수 수준으로 설정하는 것을 권장한다.
 
-힙 스캔 최적화 (Mergeable List)
-^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
+.. _result-collection-modes:
+
+스캔 결과 수집 모드
+^^^^^^^^^^^^^^^^^^^
+
+병렬 스캔이 활성화된 경우, 워커가 처리한 결과를 메인 스레드가 수집하는 방식은 쿼리 형태에 따라 다음 세 가지 중 하나로 결정된다. 모드는 SQL 트레이스의 **gather** 항목으로 확인할 수 있다.
 
-병렬 힙 스캔은 특정 조건을 만족하는 경우 "mergeable list" 방식으로 최적화되어 동작한다. 이 방식에서는 각 워커 스레드가 생성한 임시 결과를 메인 스레드에 전달하지 않고, 직접 처리한 최종 결과를 메인 스레드에 반환하여 처리 성능을 크게 향상시킨다.
+*   **mergeable list**: 각 워커가 자신의 임시 결과 리스트를 만들고, 메인 스레드는 워커별 리스트를 병합 없이 그대로 출력에 사용한다. 워커 간 동기화 비용이 가장 적어 일반적으로 가장 빠르다.
+*   **buildvalue**: 워커들이 부분 집계값을 계산하여 메인 스레드에 전달하면, 메인 스레드가 최종 집계값을 결합하여 반환한다. 단순 집계 질의에 특화된 모드이다(:ref:`buildvalue-optimization` 참고).
+*   **row-by-row**: 메인 스레드가 한 행씩 순서대로 받아 처리한다. 다른 두 모드를 적용할 수 없는 경우에 사용된다. 적용 가능 범위가 가장 넓지만 동기화 비용이 가장 크다.
 
-특히 약 1,000만 건 이상의 대용량 데이터를 8개 이상의 코어로 처리할 때, row-by-row 방식(각 스레드로부터 결과를 한 건씩 받아 처리 방식)보다 훨씬 빠른 성능을 보인다.
+.. note::
+
+    row-by-row 모드는 **힙 스캔에서만** 나타난다. 리스트 스캔과 인덱스 스캔은 row-by-row 모드가 필요한 쿼리 형태에서는 단일 스레드로 회귀하므로(위 추가 제약 참고), 트레이스의 ``gather: row-by-row`` 표기는 힙 스캔에서만 관찰된다.
 
-**제약 조건**
+**mergeable list 가 적용되지 않는 조건**
 
-다음 조건을 만족하는 경우 mergeable list 최적화가 적용되지 않으며, row-by-row 방식으로 처리된다:  
+다음 조건 중 하나라도 해당되면 mergeable list 가 아닌 다른 모드(buildvalue 또는 row-by-row)로 처리된다.
 
-*   대상 테이블을 스캔하며 평가할 수 없는 조건절이 힙스캔에 포함되는 경우
+*   대상 입력을 스캔하면서 평가할 수 없는 조건절(상위 단계로 미루어진 predicate)이 포함되는 경우
 *   해시 집계(hash group by)를 수행하는 경우
-*   select-list에 저장프로시저 (JavaSP 또는 PL/CSQL)가 있는 경우
+*   select-list에 저장프로시저(JavaSP 또는 PL/CSQL)가 있는 경우
 *   ROWNUM을 사용한 경우
-*   topn_sort(상위 N개를 추출을 위한 정렬)를 수행하는 경우
+*   topn_sort(상위 N개 추출을 위한 정렬)를 수행하는 경우
 *   LIMIT 절이 있는 경우
 *   result_cache가 활성화되어 있는 경우
 
-**대표적인 적용 예시**
-
-.. code-block:: sql
-
-    -- 조인이 없는 단순 테이블 full scan
-    SELECT /*+ PARALLEL(8) */ *
-    FROM large_table
-    WHERE status = 'active';
-
-    -- 테이블 full scan 후 ORDER BY
-    SELECT /*+ PARALLEL(8) */ *
-    FROM large_table
-    WHERE created_date > '2024-01-01'
-    ORDER BY id;
+.. _buildvalue-optimization:
 
-    -- 비상관 부질의에서의 병렬 힙 스캔
-    SELECT *
-    FROM orders
-    WHERE customer_id IN (
-        SELECT /*+ PARALLEL(8) */ customer_id
-        FROM customers
-        WHERE region = 'Asia'
-    );
+BUILDVALUE 최적화
+^^^^^^^^^^^^^^^^^
 
-    -- UNION 문의 각 하위 SELECT에 병렬 힙 스캔 적용
-    SELECT /*+ PARALLEL(8) */ order_id, customer_id, order_date
-    FROM orders_2023
-    WHERE status = 'completed'
-    UNION
-    SELECT /*+ PARALLEL(8) */ order_id, customer_id, order_date
-    FROM orders_2024
-    WHERE status = 'completed';
+SELECT 리스트가 지원되는 집계 함수만으로 구성되고 ROWNUM 등 row 단위 의미가 없는 경우, 병렬 스캔은 **BUILDVALUE 최적화**\를 적용한다. 이 모드에서는 각 워커가 자신이 스캔한 범위의 부분 집계값을 계산하여 메인 스레드에 전달하고, 메인 스레드는 부분 집계들을 결합하여 최종값을 만든다. 워커 간 데이터 전달량이 가장 적어 단순 집계 질의에서 가장 빠른 동작 모드이다.
 
-    -- 파티션 테이블의 병렬 힙 스캔
-    SELECT /*+ PARALLEL(8) */ *
-    FROM sales_partitioned
-    WHERE sale_date BETWEEN '2024-01-01' AND '2024-12-31';
+**지원 집계 함수**
 
-    -- INSERT SELECT 문 (대용량 데이터 복사)
-    INSERT INTO archive_orders
-    SELECT /*+ PARALLEL(8) */ *
-    FROM orders
-    WHERE order_date < '2023-01-01';
+다음 집계 함수만 사용된 SELECT 리스트에 BUILDVALUE 최적화가 적용된다.
 
-COUNT 최적화
-""""""""""""
+*   **COUNT(\*)**, **COUNT(column)**, **COUNT(DISTINCT column)**
+*   **MIN(column)**, **MAX(column)**
+*   **SUM(column)**, **AVG(column)**
+*   **STDDEV(column)**, **STDDEV_POP(column)**, **STDDEV_SAMP(column)**
+*   **VARIANCE(column)**, **VAR_POP(column)**, **VAR_SAMP(column)**
 
-병렬 힙 스캔은 집계 함수 중 사용 빈도가 가장 높은 **COUNT(\*)**, **COUNT(column)**, **COUNT(DISTINCT column)** 연산에 대해 특별한 최적화 매커니즘을 제공한다. 
-이 방식은 각 워커 스레드가 자신이 스캔한 범위 내에서 중간 카운트를 먼저 계산하고, 최종적으로 결과를 합산하는 방식으로 동작한다.
+**적용 조건**
 
-**COUNT 최적화가 적용되는 조건**
+위 집계 함수 사용에 더해 다음 조건을 모두 만족해야 한다.
 
-다음 조건을 모두 만족하는 경우 COUNT 전용 최적화가 적용된다:
+*   SELECT 리스트가 위에 나열된 집계 함수만 포함 (집계 외 출력 컬럼이 없을 것)
+*   조건절에 ROWNUM, 저장프로시저가 없을 것
+*   다른 조인이나 부질의가 결합되지 않은 단순 쿼리
 
-*   **COUNT(\*)**, **COUNT(column)**, **COUNT(DISTINCT column)** 집계 함수만 포함
-*   조건절에 ROWNUM, 저장프로시저가 없는 경우
-*   다른 조인이나 부질의가 없는 단순 쿼리
+**적용 범위**
 
-**COUNT 최적화 동작 방식**
+BUILDVALUE 최적화는 스캔 종류와 무관하게 적용 가능하다.
 
-*   **COUNT(\*)**: 각 워커가 간단한 카운터를 증가시키고, 최종적으로 메인스레드가 모든 워커의 카운트를 합산
-*   **COUNT(column)**: 각 워커가 NULL이 아닌 값만 카운트하고, 최종적으로 메인스레드가 모든 워커의 카운트를 합산
-*   **COUNT(DISTINCT column)**: 각 워커가 별도의 리스트 파일에 값을 저장하여 중복을 제거하여 전달하고, 메인스레드는 모든 워커에서 전달된 리스트를 병합후 전체 DISTINCT 개수 계산
+*   병렬 힙 스캔
+*   병렬 리스트 스캔
+*   병렬 인덱스 스캔
 
-**COUNT 최적화 예제**
+**예제**
 
 .. code-block:: sql
 
-    -- COUNT(*) 최적화
+    -- COUNT 계열
     SELECT /*+ PARALLEL(8) */ COUNT(*)
     FROM large_table
     WHERE status = 'active';
 
-    -- COUNT(column) 최적화
-    SELECT /*+ PARALLEL(8) */ COUNT(customer_id)
+    SELECT /*+ PARALLEL(8) */ COUNT(DISTINCT customer_id)
+    FROM orders;
+
+    -- 산술 집계 (HEAP/LIST/INDEX 모두 가능)
+    SELECT /*+ PARALLEL(8) */ SUM(amount), AVG(amount), MAX(amount)
     FROM orders
     WHERE order_date > '2024-01-01';
 
-    -- COUNT(DISTINCT) 최적화
-    SELECT /*+ PARALLEL(8) */ COUNT(DISTINCT customer_id)
-    FROM orders;
+    -- 분산/표준편차
+    SELECT /*+ PARALLEL(8) */ STDDEV(price), VARIANCE(price)
+    FROM products;
 
-    -- UPDATE STATISTICS에서의 활용
+    -- UPDATE STATISTICS도 내부적으로 BUILDVALUE 최적화의 혜택을 받는다
     UPDATE STATISTICS ON large_table WITH FULLSCAN;
 
 .. note::
 
-    COUNT 최적화는 단순 집계에 특화된 최적화로 다른 집계 함수(SUM, AVG 등)와 함께 사용되거나 복잡한 조인이 포함된 경우에는 적용되지 않으며, 일반적인 병렬 힙 스캔 방식(mergeable list 또는 row-by-row)을 사용하여 처리된다.
+    SELECT 리스트에 위 집계 외의 표현식(예: 일반 컬럼, 미지원 집계 함수)이 함께 포함되거나 GROUP BY가 결합되면 BUILDVALUE 최적화는 적용되지 않으며, mergeable list 또는 row-by-row 모드로 처리된다.
 
-힙 스캔 SQL 트레이스
-^^^^^^^^^^^^^^^^^^^^
+스캔 SQL 트레이스
+^^^^^^^^^^^^^^^^^
 
-병렬 힙 스캔이 수행되면 :ref:`SQL 트레이스 <query-profiling>`\ 결과에 병렬 처리 상세 정보가 추가로 출력된다.
+병렬 스캔이 수행되면 :ref:`SQL 트레이스 <query-profiling>` 결과에 병렬 처리 상세 정보가 추가로 출력된다.
 
 .. code-block:: sql
 
     csql> ;trace on
 
-    SELECT /*+ PARALLEL(4) RECOMPILE */ count(*) 
-    FROM large_table 
+    SELECT /*+ PARALLEL(4) RECOMPILE */ count(*)
+    FROM large_table
     WHERE status = 'active';
 
 ::
@@ -254,30 +323,30 @@ COUNT 최적화
     Trace Statistics:
         SELECT (time: 2405, fetch: 143277, fetch_time: 1287, ioread: 123467)
             SCAN (table: dba.large_table), (heap time: 2395, fetch: 143277, ioread: 123467, readrows: 0, rows: 0)
-                 (parallel workers: 8, heap time: 2390..2395, readrows: 1249989..1250011, 
+                 (parallel workers: 8, heap time: 2390..2395, readrows: 1249989..1250011,
                   rows: 1249989..1250011, gather: mergeable list)
 
-병렬 힙 스캔의 트레이스 출력 항목에 대한 설명은 다음과 같다:
+병렬 스캔의 트레이스 출력 항목은 다음과 같다.
 
 *   **parallel workers**: 사용된 워커 스레드의 수
-*   **heap time**: 각 워커의 힙 스캔 소요 시간 범위 (최소..최대, 밀리초)
+*   **heap time / list time / index time**: 각 워커의 스캔 소요 시간 범위 (최소..최대, 밀리초). 스캔 종류에 따라 항목 이름이 달라진다.
 *   **readrows**: 각 워커가 읽은 행 수 범위 (최소..최대)
 *   **rows**: 각 워커가 반환한 행 수 범위 (최소..최대)
 *   **gather**: 결과 수집 방식
-    
-    * **mergeable list**: 최적화된 방식으로, 각 워커의 결과를 별도 병합 없이 직접 사용
-    * **row-by-row**: 기본 방식으로, 각 워커의 결과를 한 건씩 수집하여 병합
-    * **count**: COUNT 전용 최적화 방식으로, 각 워커가 로컬 카운트를 수행하고 최종 결과를 병합
 
-**gather** 항목에 **mergeable list** 또는 **count** 가 표시된 경우, 병렬 힙 스캔 최적화가 적용되어 더 나은 성능을 보인다는 의미이다.
+    *   **mergeable list**: 워커별 리스트를 병합 없이 직접 사용
+    *   **buildvalue**: 워커별 부분 집계를 결합 (구 ``count`` 표시를 대체)
+    *   **row-by-row**: 한 건씩 수집하여 병합 (힙 스캔에서만 나타남)
+
+**gather** 항목에 **mergeable list** 또는 **buildvalue** 가 표시된 경우, 동기화 비용이 적은 최적 경로로 실행되었음을 의미한다.
 
 .. note::
 
     병렬 워커들의 시간과 행 수가 범위(최소..최대)로 표시되며, 이상적으로는 모든 워커가 비슷한 양의 작업을 수행해야 한다. 범위가 크게 벌어진다면 데이터 분포나 시스템 리소스 경합 문제를 의심해볼 수 있다.
 
-**COUNT 최적화 추적 정보 예제**
+**BUILDVALUE 최적화 추적 정보 예제**
 
-COUNT 최적화가 적용되면 **gather: count** 가 표시된다:
+BUILDVALUE 최적화가 적용되면 **gather: buildvalue** 가 표시되며, 단일 집계 결과만 반환되므로 worker별 ``rows`` 는 0으로 출력된다.
 
 .. code-block:: sql
 
@@ -292,9 +361,26 @@ COUNT 최적화가 적용되면 **gather: count** 가 표시된다:
         SELECT (time: 1500, fetch: 1, fetch_time: 10, ioread: 100000)
             SCAN (table: dba.large_table), (heap time: 1490, fetch: 100000, ioread: 100000, readrows: 0, rows: 0)
                  (parallel workers: 8, heap time: 1485..1490, readrows: 1250000..1250000,
-                  rows: 0..0, gather: count)
+                  rows: 0..0, gather: buildvalue)
+
+**병렬 인덱스 스캔 트레이스 예제**
+
+.. code-block:: sql
+
+    csql> ;trace on
+
+    SELECT /*+ PARALLEL(4) RECOMPILE */ order_id, order_date
+    FROM orders
+    WHERE status = 'completed' USING INDEX idx_orders_status;
+
+::
 
-COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 실제 카운트 결과는 집계 함수를 통해 반환된다.
+    Trace Statistics:
+        SELECT (time: 980, fetch: 51200, fetch_time: 410, ioread: 0)
+            SCAN (table: dba.orders, index: idx_orders_status),
+                 (key time: 970, fetch: 51200, ioread: 0, readkeys: 1, filteredkeys: 0,
+                  rows: 0, parallel workers: 4, key time: 965..970, rows: 312500..312500,
+                  gather: mergeable list)
 
 .. _parallel-subquery-execution:
 
@@ -357,7 +443,7 @@ COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 
 *   derived table(인라인 뷰) 등에 의해 부질의 간 참조가 존재하는 경우
 *   Object DBMS 기능을 사용하는 경우 (path expression 등)
 *   JSON_TABLE이나 SET 타입 테이블의 스캔이 포함된 경우
-*   부질의 조건절에 저장 프로시저가 포함된 경우 
+*   부질의 조건절에 저장 프로시저가 포함된 경우
 *   상관 부질의인 경우
 
 .. code-block:: sql
@@ -365,7 +451,6 @@ COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 
     -- 병렬 실행이 적용되지 않는 예
 
     -- NO_PARALLEL_SUBQUERY 힌트 사용
-    -- 2개의 부질의가 있지만 힌트로 병렬 실행 비활성화
     SELECT /*+ NO_PARALLEL_SUBQUERY */ *
     FROM orders
     WHERE customer_id IN (
@@ -376,7 +461,6 @@ COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 
     );
 
     -- CTE 간 참조가 있는 경우
-    -- cte2가 cte1을 참조하므로 독립적이지 않음
     WITH cte1 AS (
         SELECT * FROM table1
     ),
@@ -386,7 +470,6 @@ COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 
     SELECT * FROM cte2;
 
     -- JSON_TABLE 사용
-    -- JSON_TABLE이 포함되면 부질의가 2개 이상 있어도 병렬 실행 안 됨
     SELECT *
     FROM orders,
     JSON_TABLE(json_column, '$[*]' COLUMNS(id INT PATH '$.id')) AS jt
@@ -398,7 +481,6 @@ COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 
     );
 
     -- 저장 프로시저가 조건절에 포함된 경우
-    -- 2개의 부질의가 있지만 하나에 저장 프로시저가 있어 병렬 실행 안 됨
     SELECT *
     FROM orders
     WHERE customer_id IN (
@@ -441,7 +523,7 @@ COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 
 부질의 추적 정보
 ^^^^^^^^^^^^^^^^
 
-부질의의 병렬 실행이 수행되면 :ref:`SQL 트레이스 <query-profiling>`\에 결과에 병렬 처리 상세 정보가 추가로 출력된다. 
+부질의의 병렬 실행이 수행되면 :ref:`SQL 트레이스 <query-profiling>`\에 결과에 병렬 처리 상세 정보가 추가로 출력된다.
 
 .. code-block:: sql
 
@@ -493,26 +575,26 @@ COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 
 
 각 병렬 연산의 실제 병렬 처리 수준은 다음 요인에 따라 결정된다:
 
-*   테이블 크기, 파티션 개수 등의 처리량 규칙
+*   테이블/리스트/인덱스 크기 등의 처리량 규칙
 *   **PARALLEL** 힌트로 명시적으로 지정된 값
 *   :ref:`parallelism <parallelism>` 파라미터로 설정된 상한값
 *   :ref:`max_parallel_workers <max_parallel_workers>` 파라미터로 설정된 전역 워커 풀 크기
 
 처리량 규칙으로 계산된 병렬 처리 수준은 :ref:`parallelism <parallelism>` 파라미터 값을 초과할 수 없다. 힌트로 지정된 병렬 처리 수준은 :ref:`parallelism <parallelism>` 파라미터 값을 초과할 수 있지만 최대값(32 또는 시스템 코어 수 중 작은 값)은 초과할 수 없다.
 
-힙 스캔 처리량 규칙
-^^^^^^^^^^^^^^^^^^^
+스캔 처리량 규칙
+^^^^^^^^^^^^^^^^
 
-병렬 힙 스캔의 병렬 처리 수준은 스캔 대상 테이블의 페이지 수에 따라 결정된다.
+병렬 스캔(힙/리스트/인덱스)의 병렬 처리 수준은 스캔 대상의 페이지 수에 따라 동일한 규칙으로 결정된다. 힙 스캔은 테이블 힙 페이지 수를, 리스트 스캔은 임시 리스트 페이지 수를, 인덱스 스캔은 인덱스 리프 페이지 수를 기준으로 한다.
 
 **활성화 조건**
 
-*   스캔 대상 테이블의 페이지 수가 4,096개 이상일 때 활성화된다 (약 64MB, db_page_size가 16K일 때)
-*   이 조건을 만족하지 않으면 **PARALLEL** 힌트가 있어도 병렬 힙 스캔이 활성화되지 않는다
+*   스캔 대상의 페이지 수가 2,048개 이상일 때 활성화된다 (약 32MB, db_page_size가 16K일 때)
+*   이 조건을 만족하지 않으면 **PARALLEL** 힌트가 있어도 병렬 스캔이 활성화되지 않는다
 
 **처리 수준 결정**
 
-병렬 처리 수준은 테이블의 페이지 수에 따라 다음과 같이 결정된다:
+병렬 처리 수준은 페이지 수에 따라 다음과 같이 결정된다.
 
 .. csv-table::
    :header: "페이지 수", "처리량", "처리량 규칙 계산값"
@@ -540,13 +622,13 @@ COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 
 
 예를 들어, parallelism=4 (기본값)로 설정된 경우:
 
-*   페이지 수 4,096개 → 처리량 규칙 계산값 2 → MIN(2, 4) = **2** 적용
+*   페이지 수 2,048개 → 처리량 규칙 계산값 2 → MIN(2, 4) = **2** 적용
 
-*   페이지 수 65,536개 → 처리량 규칙 계산값 6 → MIN(6, 4) = **4** 적용 (parallelism 초과 불가)
+*   페이지 수 65,536개 → 처리량 규칙 계산값 7 → MIN(7, 4) = **4** 적용 (parallelism 초과 불가)
 
 .. note::
 
-    **PARALLEL** 힌트로 병렬 수준을 명시적으로 지정한 경우, 처리량 규칙이 적용되지 않고 힌트 값이 사용된다.
+    **PARALLEL** 힌트로 병렬 수준을 명시적으로 지정한 경우에도, 활성화 조건(페이지 수 2,048 이상)은 동일하게 적용된다. 활성화된 이후의 병렬 수준 결정에서는 힌트 값이 우선한다.
 
 **예제**
 
@@ -554,25 +636,25 @@ COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 
 
     -- 테이블 생성 및 데이터 삽입
     CREATE TABLE large_table (c1 INT);
-    
+
     INSERT INTO large_table
     WITH RECURSIVE cte (n) AS (
-        SELECT 1 
-        UNION ALL 
+        SELECT 1
+        UNION ALL
         SELECT n + 1 FROM cte WHERE n < 2000
     )
     SELECT ROWNUM FROM cte a, cte b, cte c LIMIT 2200000;
-    
+
     UPDATE STATISTICS ON large_table WITH FULLSCAN;
-    
+
     -- 테이블 통계 확인
     -- Total pages in class heap: 4215 (약 66MB, db_page_size가 16K일 때)
     -- Total objects: 2200000
-    
+
     -- parallelism 파라미터가 4로 설정된 경우
-    -- 페이지 수 4215는 4,096 이상이므로 병렬 처리 수준 2가 자동 적용됨
+    -- 페이지 수 4215는 2,048 이상이므로 병렬 처리 수준 3이 자동 적용됨
     SELECT COUNT(*) FROM large_table;
-    
+
     -- 힌트로 명시적 지정
     SELECT /*+ PARALLEL(8) */ COUNT(*) FROM large_table;
 
@@ -597,10 +679,10 @@ COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 
 부질의 처리량 규칙
 ^^^^^^^^^^^^^^^^^^
 
-부질의(Subquery)의 병렬 실행은 복수의 부질의가 서로의 결과를 참조하지 않는 독립적인 구조일때 활성화된다. 
+부질의(Subquery)의 병렬 실행은 복수의 부질의가 서로의 결과를 참조하지 않는 독립적인 구조일때 활성화된다.
 
 *   부질의 병렬 실행시 처리 수준은 2로 고정되어 적용된다. 예를 들어, 한 쿼리 내에 독립적인 부질의가 4개가 존재하더라도, 시스템은 2개의 병렬 워커를 할당하여 처리한다.
-*   각 부질의의 병렬 실행 여부는 "처리량 규칙"에 의해 결정된다. 
+*   각 부질의의 병렬 실행 여부는 "처리량 규칙"에 의해 결정된다.
 *   여러 독립적인 부질의가 존재하는 경우 병렬 실행의 효과가 크다
 
 .. code-block:: sql
@@ -637,8 +719,8 @@ COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 
 
 병렬 질의 처리량 규칙을 통한 최적화:
 
-*   작은 테이블에 대한 불필요한 병렬 실행을 방지하여 오버헤드를 줄인다
-*   테이블 크기에 비례하여 병렬 처리 수준을 자동으로 조정한다
+*   작은 입력에 대한 불필요한 병렬 실행을 방지하여 오버헤드를 줄인다
+*   입력 크기에 비례하여 병렬 처리 수준을 자동으로 조정한다
 *   과도한 병렬 실행으로 인한 시스템 자원 경쟁을 방지한다
 *   효과가 큰 쿼리에 집중적으로 병렬 자원을 할당한다
 
@@ -648,4 +730,3 @@ COUNT 최적화는 결과 행이 하나이므로 rows가 0으로 표시되며, 
 *   **parallelism**: 시스템의 물리 코어 수를 고려하여 설정 (보통 4~8 정도가 적절)
 *   대용량 테이블이 많은 환경에서는 **max_parallel_workers** 값을 높게 설정
 *   소규모 테이블이 많은 환경에서는 기본값 사용을 권장
-
diff --git a/ko/sql/tuning.rst b/ko/sql/tuning.rst
index 80a39a46f..8051145c8 100644
--- a/ko/sql/tuning.rst
+++ b/ko/sql/tuning.rst
@@ -942,7 +942,7 @@ SQL 힌트
     NO_HASH_LIST_SCAN |
     NO_LOGGING |
     PARALLEL (<degree>) |
-    NO_PARALLEL_HEAP_SCAN |
+    NO_PARALLEL_SCAN |
     NO_PARALLEL_SUBQUERY |
     RECOMPILE
 
@@ -1015,19 +1015,19 @@ SQL 힌트는 주석에 더하기 기호(+)를 함께 사용하여 지정한다.
 
 .. _parallel-hint:
 
-*   **PARALLEL** ( *degree* ): 병렬 질의 실행(병렬 힙 스캔, 병렬 부질의 실행, 병렬 해시 조인, 병렬 정렬)을 활성화하고 병렬 처리 정도를 지정하는 힌트이다. *degree* 는 0 이상의 정수 값이어야 하며, 병렬로 처리할 워커 스레드의 수를 의미한다. 0이나 1로 지정할 경우 병렬 처리 기능이 비활성화된다. 자세한 내용은 :ref:`parallel-query`\를 참고한다.
+*   **PARALLEL** ( *degree* ): 병렬 질의 실행(병렬 스캔(힙/리스트/인덱스), 병렬 부질의 실행, 병렬 해시 조인, 병렬 정렬)을 활성화하고 병렬 처리 정도를 지정하는 힌트이다. *degree* 는 0 이상의 정수 값이어야 하며, 병렬로 처리할 워커 스레드의 수를 의미한다. 0이나 1로 지정할 경우 병렬 처리 기능이 비활성화된다. 자세한 내용은 :ref:`parallel-query`\를 참고한다.
 
     .. code-block:: sql
 
         SELECT /*+ PARALLEL(4) */ * FROM large_table WHERE condition;
 
-.. _no-parallel-heap-scan:
+.. _no-parallel-scan:
 
-*   **NO_PARALLEL_HEAP_SCAN**: 병렬 힙 스캔을 사용하지 않도록 하는 힌트이다. 자세한 내용은 :ref:`parallel-query`\를 참고한다.
+*   **NO_PARALLEL_SCAN**: 해당 쿼리 블록의 모든 병렬 스캔(힙/리스트/인덱스)을 사용하지 않도록 하는 힌트이다. 자세한 내용은 :ref:`parallel-query`\를 참고한다.
 
     .. code-block:: sql
 
-        SELECT /*+ NO_PARALLEL_HEAP_SCAN */ * FROM large_table WHERE condition;
+        SELECT /*+ NO_PARALLEL_SCAN */ * FROM large_table WHERE condition;
 
 .. _no-parallel-subquery:
 
```
