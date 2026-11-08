# DomainDecided — the compiler decides every slot, the server follows (CBRD-27817)

Code: branch `CBRD-27817` at `446bdc2c6` (15 commits on develop `2d928e34b`), worktree
`~/dev/cubrid-worktree/CBRD-27817`. The model covers every commit of the branch against develop:

| Commit | What it changes | Model |
|---|---|---|
| `df9572105` | accumulator domains decided for every aggregate; hash aggregation lists opened with them | site `row` (a slot read at the row is decided) |
| `6d88178f2` | row-time type checks XASL generation already settled dropped | site `row` |
| `194434140` | `qdata_strcat_dbval`: a number first operand adds by its node's decision | site `row` |
| `d7a512453` | LEAST/GREATEST, oracle_style empty-string concatenation pick their converter without the value's type | site `row` |
| `c197ece74` | a subquery's list read by IN / ANY takes its column's collation; a hash join key is never LEAVE | site `list` |
| `b12f28e81` | row paths: the fallbacks for a variable or missing domain dropped; the expression-program decline decided from the kernel type | site `row`, `Decide` |
| `29d7d78a7` | a decided comparison is never missing at the row (`eval_compare_values_resolved`) | site `row` |
| `d09dfe5cb` | a tuple write checks a column of no domain only in debug builds | site `row` |
| `90a55c197` | a scalar subquery's value list takes its list column's domain | site `single` |
| `0ee79ba5b` | a regu value list (`TYPE_REGU_VAR_LIST`) carries no domain (NULL), the stream packs the type first | site `box` |
| `747c420a6` | an unpacked plan with a domain left to the values is refused (`ER_QPROC_DOMAIN_UNRESOLVED`), release too | `Load` (load check) |
| `268530210` | CUME_DIST / PERCENT_RANK keys carry their ORDER BY items' domains | site `key` |
| `a5d36a72e` | GROUP BY skip compares its keys in their decided domains (not `tp_value_compare`) | site `row` |
| `1151dbf4b` | hash join prehash: the key collation flag test becomes a debug assert | site `row` |
| `446bdc2c6` | a GROUP BY's output list (`after_groupby_list`) is sorted in its output columns' domains (ELT over branches of other collations left LEAVE; found by the load check in CTP `cbrd_27510/17_branch_collations`) | site `key` |

One behavior is one client session: compilations into the plan cache, unpacks of cached plans, executions.
The change has no concurrency of its own: every step is a function of the plan and the values on one thread
(see the fault model).

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | The executor never reads a domain left to the value (a variable type, or a LEAVE / ENFORCE collation) at the row: every slot it reads carries a decided domain and comparison. | CBRD-27817 body, Description ("CBRD-27583 이후 컴파일은 모든 자리에 도메인과 비교를 주므로 이 갈래들은 닿지 않습니다"); ADR 0028 ("서버는 실행 중에 타입을 정하지 않는다"); user decision 2026-11-08 (compiler decides, server follows) |
| C2 | Every domain the server unpacks is decided (a type and a NORMAL collation); a regu value list carries none (a NULL pointer). | CBRD-27817 Acceptance Criteria 1 ("NORMAL이 아닌 도메인이 CTP sql, medium 전체에서 0개"); user decision 2026-11-08 ("null로 … 0x0으로 두자") |
| C3 | XASL serialization never packs a NULL domain (`or_put_domain` dereferences it). | `object_representation.c:2577` (`domain->built_in_index`); the change's `xasl_to_stream.c:5803` assert |
| C4 | XASL generation and the server take the same expression-program decision for an arithmetic node, so the image the client writes is the program the server would compile. | develop `expr_compile.c:9148` / `9225` debug assert (`expr_image_same_prog`, #8196); the counterexample found 2026-11-08 (`a0c7cf389` decided from `result_conv`, a server-only field) |
| C5 | Every slot answers as in develop: the change alters only domains no row path reads and removes fallbacks no plan reaches. | CBRD-27817 Specification Changes ("결과, 오류, 정렬 순서는 바뀌지 않습니다") |
| C6 | No plan the compiler produces is refused at load: a statement develop runs keeps running. | ADR 0028 / CLAUDE.md ("A statement that runs on develop keeps running"); CBRD-27817 Specification Changes |
| C7 | The load check lets no domain left to the values reach the executor (refused with ER_QPROC_DOMAIN_UNRESOLVED in release builds too). | user decision 2026-11-08 (Q1: "-1383 at load, release error"); GLOSSARY "미확정 도메인 오류" |

## Refinement map (model -> code)

| Model | Code (`0ee79ba5b`) | One step because |
|---|---|---|
| `Compile(s, c)` | XASL generation on the client (SA: the same process): `xasl_generation.c` `pt_make_regu_subquery` 9339 (single tuple) / 9373 (list), `pt_to_outlist` 17407 (single tuple) / 17423 (list), `pt_to_cume_dist_percent_rank_regu_variable` 32620 (box); packed by `xasl_to_stream.c:xts_process_regu_variable` (5803) | the parser's private tree on one thread; no shared state |
| site `key` | sort keys whose domain the parse tree gave: CUME_DIST / PERCENT_RANK keys (`xasl_generation.c` after `pt_agg_orderby_to_sort_list`: `pos_descr.dom = pt_xasl_node_to_domain (ORDER BY item)`; read by no one, `query_aggregate.cpp:271` skips the sort, the comparison reads the ORDER BY item regu's domain, 2835) and a GROUP BY's output list keys (`pt_to_buildlist_proc`: `pt_set_sort_list_domains (after_groupby_list, NULL, g_outptr_list)`; the list carries them as its sort list, `qfile_open_list`) | pure |
| `c` (class) | `left` when the parse-tree domain (`pt_xasl_node_to_domain`) is `DB_TYPE_VARIABLE` or its collation flag is not NORMAL, `fixed` else | input class |
| `Ann` / `AnnDev` | the domain the slot carries after generation: list `pt_reader_domain (regu->domain, domain_list_column_of (xasl, 0))`; single `value_list->dom = regu->domain`; box `NULL`. develop: the list kept the ENFORCE domain, the value list `pt_make_val_list`'s parse-tree domain, the box `tp_domain_resolve_default (DB_TYPE_VARIABLE)` | pure |
| `PacksDomain` | `xts_process_regu_variable`: type first, then the domain unless `TYPE_REGU_VAR_LIST`; `xts_sizeof_regu_variable` alike | pure |
| `Load(e)`, `Undecided`, `refused` | `stream_to_xasl.c:stx_unpack_domain` (every domain the stream holds; counts `n_undecided` by `stx_domain_is_decided`: a variable type or a LEAVE / ENFORCE collation, in itself or an element's), `stx_build_regu_variable` (`domain = NULL` for a container), `stx_build_xasl_node` (`single_tuple`), `stx_build_aggregate_type` (sort list); the check in `stx_map_stream_to_xasl` refuses the plan (`ER_QPROC_DOMAIN_UNRESOLVED`, debug `assert (false)`), on both entries: `xcache_find_xasl_id_for_execute` and `qmgr_process_query` (an uncached stream: `update_at_server`, `do_insert_at_server`, `do_select_internal`, `do_execute_do`) | the unpacking thread's private copy; the check runs after the whole plan is unpacked, before it is returned |
| `Exec(e)`, `ReadAtRow` | a plain regu / position / comparison: `fetch_peek_dbval`, `eval_compare_values_resolved` (`query_evaluator.c:427` `assert (compare != NULL)`). A list read by IN / ANY: `eval_some_list_eval` (`query_evaluator.c:936`) reads `type_list.domp[0]` and compares with the decided `compare`. A scalar subquery: `qdata_get_single_tuple_from_list_id` (`query_executor.c:18508`, `22649`) reads `type_list.domp[i]`. A container: `qdata_calculate_aggregate_cume_dist_percent_rank` reads its elements' domains (`query_aggregate.cpp:2835`); the DISTINCT / ORDER BY list (`qdata_aggregate_list_domain`) is skipped for CUME_DIST / PERCENT_RANK (`query_aggregate.cpp:271`) | one row on one thread |
| `Decide(side, conv)`, `Decline` | `expr_compile.c:expr_compile_node_impl` 5958-5959: decline when `coerce_result` and (`rtype` not a number or `tp_value_find_converter (ktype, exec_domain, DOMAIN_CONVERT_IMPLICIT) == NULL`); `ktype` from `expr_arith_decided` (`2538`: generation computes it from the operand domains, the server reads `decided.arith`). `cli` = `env.at_generation`, `srv` = the debug recompile in `expr_valptr_prog_settle` / `expr_scan_pred_settle` | pure function of the node |
| `conv` | whether `tp_value_find_converter (ktype, exec_domain, IMPLICIT)` finds a converter | input class |
| mutant `decline_server_field` | `a0c7cf389`'s `arith->result_conv == NULL`: `result_conv` is set only by `stx_build_arith_type` (`stream_to_xasl.c`), NULL at generation | — |
| `bad`, `crash`, `diff`, `listBindRan` | ghosts: an optdebug assert at the row read (`assert (compare != NULL)`, the position-domain asserts); a SIGSEGV in `or_put_domain`; an answer other than develop's; a list of a bound subquery ran | — |
| `Done` | the session ends | — |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `NoUndecidedRead` | invariant | `~bad` | C1 |
| `CompiledDecided` | invariant | every compiled slot is decided; a box carries `none` | C2 |
| `NoNullPack` | invariant | `~crash` | C3 |
| `ImageSame` | invariant | two decisions of the same input class agree | C4 |
| `SameAnswer` | invariant | `~diff` | C5 |
| `NoRefusal` | invariant | `~refused` | C6 |
| `LoadDecided` | invariant | no loaded slot is undecided | C7 |
| `IndInv` | inductive invariant | every compiled slot is `Ann` of its inputs, every decision `Decline` of its inputs, and C1-C7 | C1-C7 |

## Fault model and environment assumptions

| Item | Modeled as |
|---|---|
| error return | not applicable: an `or_unpack_domain` or allocation failure fails the unpack before any slot runs (`stx_build_regu_variable` returns NULL); a conversion failure at the row is a value's error, the same in develop |
| interrupt / query cancel | not applicable: a cancelled statement runs no further row; no decision is taken at the row |
| lock timeout, deadlock victim, conditional latch failure | not applicable: no decision reads a lock or a latch |
| OOM | not applicable: as error return |
| crash / `kill -9` | not applicable: no durable state; the plan cache is volatile |
| spurious wakeup | not applicable: no condition wait |
| concurrent DML, vacuum, checkpoint | not applicable: they change values, not domains or decisions; a schema change recompiles (develop's XASL cache invalidation) |
| HA log apply | not applicable: the applier compiles with the same binary |
| parallel workers | each worker runs a deep clone of the unpacked plan (`xcache` clones) and reads the same decided domains; no worker writes a domain |
| client/server version mix | not modeled: the XASL stream order changed (type before domain), as CBRD-27583's stream change did; a client and a server of different develop builds are out of scope |
| plan reuse | modeled: `Load` may run many times per `Compile` (a cached plan, a prepared statement executed twice) |

No liveness claim: a session is a finite sequence of steps; the main cfg checks deadlock freedom up to `Done`.

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-no-boundary-row-left` | XASL generation leaves a slot the executor reads to its value, and no load check (develop's debug-only counts) | `NoUndecidedRead` violated | C1 |
| `mutant-pre-list` | without `c197ece74`: the list regu of a bound subquery keeps ENFORCE | `CompiledDecided` violated | C2 |
| `mutant-pre-single` | without `90a55c197`: the scalar subquery's value list keeps `MAX(?)`'s VARIABLE domain | `CompiledDecided` violated | C2 |
| `mutant-pre-key` | without `268530210` / `446bdc2c6`: a CUME_DIST key keeps the host variable's VARIABLE domain, an output list key the ELT's LEAVE | `CompiledDecided` violated | C2 |
| `mutant-box-variable` | without `0ee79ba5b`: the container carries develop's VARIABLE domain | `CompiledDecided` violated | C2 |
| `mutant-box-pack-always` | `0ee79ba5b`'s NULL domain without the type-first stream: `or_put_domain (NULL)` | `NoNullPack` violated | C3 |
| `mutant-decline-server-field` | `a0c7cf389`: the decline reads `result_conv` | `ImageSame` violated (the CS crash of 2026-11-08: `set @double_var = 123.456; set @int_var = 10; select @double_var - @int_var from db_root;` on a fresh server) | C4 |
| `mutant-label-read` | an executor path reads a list regu's own domain instead of the list's column domain and the decided comparison | `SameAnswer` violated | C5 |
| `mutant-row-left` | XASL generation leaves a slot to its value; the load check refuses the plan | `NoRefusal` violated (the statement develop ran fails with -1383) | C6 |
| `mutant-no-boundary-pre-single` | without `90a55c197` and without the load check | `LoadDecided` violated | C7 |

Surviving mutants: none. The guard each claim relies on has a mutant above; the pass cfg holds without them.

## Witnesses

| cfg | Outcome reached |
|---|---|
| `witness-list-bind-ran` | a list of a bound subquery (`c in (select ? union select ?)`) is compiled, loaded and run |
| `witness-declined-both-sides` | both sides decline an arithmetic node that has no converter |
| `witness-container-loaded` | a CUME_DIST / PERCENT_RANK container is unpacked with no domain |
| `witness-refused` | under `row_left` (a compiler that leaves a slot undecided), the load check refuses the plan |

## Dead expressions

| Line | Expression | Why the pass cfgs never evaluate it |
|---|---|---|
| `DomainDecided.tla:142` | `refused' = TRUE /\ UNCHANGED loaded` (the load check refuses) | a mutant-only branch: with `Mutant = "none"` the compiler decides every slot (C2), so no loaded slot is undecided; `mutant-row-left` and `witness-refused` evaluate it. In the code, the census of 2026-11-08 (CTP sql + medium on the scope build) found no undecided domain left after the fixes, and the gates below ran no -1383 |

## Bounds

Main: `NComp = 3` (compilations and decisions), `NLoad = 3`. Scale: 4 and 4. Every site × class pair the
compiler meets and both decision inputs are enumerated at the main bound. IndInv's inductiveness is checked by
Apalache for every value of `NComp` and `NLoad`.

## Trace validation

Instrumented build: `446bdc2c6` + TLATRACE (`src/query/tla_trace.h`; events in `pt_make_regu_subquery`,
`pt_to_outlist`, `pt_to_cume_dist_percent_rank_regu_variable`, the CUME_DIST / PERCENT_RANK key loop,
`stx_build_regu_variable`, `stx_build_xasl_node` single tuple, `stx_build_aggregate_type` sort list,
`expr_compile_node_impl` decline taken and not taken), optdebug, worktree `rowpath-x` detached at `446bdc2c6` plus the
patch (scratch, not committed), libcubridsa `dc55b16cc8b1e77d`. SA mode: generation, unpack and execution in one
process, one global `seq`.

| Run | Scenario | Events | Result |
|---|---|---|---|
| `run1` | bound subquery IN, scalar subqueries (`GROUP_CONCAT(?)`, `MAX(col)`), CUME_DIST / PERCENT_RANK with binds, session-variable and NUMERIC arithmetic | 27 | accepted (`witness-trace-run1`) |
| `run2` | the develop A/B smoke `q.sql` (317 result lines, diff 0 against develop) | 118 | accepted (`witness-trace-run2`) |
| `run3` | GROUP BY skip (`q_gskip.sql`: ci collation keys, ROLLUP, DESC, LIMIT, parallel) and CUME_DIST / PERCENT_RANK over it | 33 | accepted (`witness-trace-run3`) |
| `run4` | CTP `cbrd_27510/17_branch_collations.sql` (ELT over branches of other collations, GROUP BY over it; the statement the load check refused before `446bdc2c6`) | 5 | accepted (`witness-trace-run4`) |
| `corrupt-single-variable` | run1 with a value list loaded VARIABLE (develop's behavior) | — | refused (`reject-single-variable`) |
| `corrupt-key-variable` | run1 with a CUME_DIST key loaded VARIABLE (before `268530210`) | — | refused (`reject-key-variable`) |
| `corrupt-client-declines` | run1 with the client declining a node the server compiles (`a0c7cf389`) | — | refused (`reject-client-declines`) |

Actions no run reaches: the refusal branch of `Load` (no compiled plan is undecided, see Dead expressions); `Decide`
with `conv = 0` (no number kernel type lacks an implicit converter into a number domain in these statements;
`witness-declined-both-sides` reaches it in the model); `Compile` / `Load` of site `row` and `Exec` are not logged
(Hidden: `Exec`); the row reads are covered by CTP sql 17743 and medium 975 under the optdebug asserts.

## Counterexamples

| cfg | Classification |
|---|---|
| — | none on the correct variant |

The model's first draft read a list regu's domain at the row (`ReadAtRow = {list, row}`); `eval_some_list_eval`
(`query_evaluator.c:936`) reads the list's column domain and the decided comparison instead, so the map was
corrected before any result was recorded.

## Result

2026-11-08, `tools/tla/tla-check docs/tla/CBRD-27817` → `RESULT: OK`, run dir
`.git_ignored_dir/scratch/tla/CBRD-27817-20261108-190927-3926308`. TLAPS 요청 없음 (no proof module).

| cfg | Result |
|---|---|
| `DomainDecided` | pass, 17812 states / 3466 distinct, depth 8; dead line 142 (Dead expressions) |
| `scale-4` | pass, 144719 / 21353, depth 10; dead line 142 |
| `apalache-indinv` | pass (IndInv inductive for every `NComp`, `NLoad`) |
| 10 mutants | each violates its expected invariant |
| 4 witnesses | each reached |
| `witness-trace-run1` / `run2` / `run3` / `run4` | accepted (27 / 118 / 33 / 5 events) |
| `reject-single-variable` / `reject-key-variable` / `reject-client-declines` | refused |

Spec sha256 in the run dir's `summary.txt`. Engine `446bdc2c6`; trace build libcubridsa `dc55b16cc8b1e77d`
(optdebug + TLATRACE).
