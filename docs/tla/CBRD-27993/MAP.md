# CBRD-27993 — the memo key of an NL inner holds only values fixed for the probe

Model `NlMemoKey.tla`: the memo of an NL inner x between an outer scan o and a later scan y
(`o -> x -> y`), one thread. Engine sha: develop 2dac6ecc2 (worktree `~/dev/cubrid-worktree/CBRD-27993`).
Runtime repro of the defect: develop optdebug 2d928e34b (`CUBRID-develop-2d928e34b`),
`.git_ignored_dir/scratch/cbrd27993/probe1/` — memo on NL `1250 749361`, memo off NL and hash `1381 826674`.

trace-exempt: design spec before the fix is written; the fix's implementation spec refines it and carries the trace validation (cubrid-tla step 9).

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | An NL join whose inner is memoized returns, for every outer row, exactly the inner rows it returns with memoize off. | CBRD-27993 Expected Result ("`memoize_memory_limit=0` 으로 memoize 를 끄면 NL 조인도 이 값이다"); manual `sql/tuning.rst` memoize section (memoize does not change the result) |
| C2 | A key the memo answers from holds exactly the inner rows of that key, or one "no row" entry; a key still being filled is never answered from. | `memoize.cpp` `storage::stop_insert` comment ("a later hit would replay just that part, so its entries are taken out", CBRD-27487) |
| C3 | A correlated subquery whose result the subquery cache reuses returns, for every row that evaluates it, the result it returns with the cache off. | CBRD-25749 (the cache keeps a stored function's result only when it is DETERMINISTIC); probes `.git_ignored_dir/scratch/cbrd27993/sp-sa/`, `sessvar/sq.sql` (develop breaks it); user, round 6 |

## Refinement map (model -> code)

| Model | Code (develop 2dac6ecc2) | One step because |
|---|---|---|
| `os[j]` | the outer columns x's result depends on: those its terms read (`TYPE_CONSTANT` regu vars pointing into o's `val_list`) and those a derived table x reads is made from (its list is rebuilt for every outer row; D24) | data, fixed per outer row |
| `xk[r]` | x row r matches outer value `xk[r]` (x's key range / predicates) | data |
| `yl[r]`, `ys` | y's `val_list` slot after `scan_ptr` (y) ran for x row r; a scan that finds no row leaves the slot as it was | data / single owner (this thread) |
| `Key(y)` | the fix: the key slots chosen when the inner's XASL is generated (`xasl_generation.c`, decision D3), read by `storage::get_key`; develop: `memoize.cpp` `key_maker::operator()` → `storage::m_keyptr_src` at `new_memoize_storage` | chosen once per query plan; the storage is rebuilt at every mainblock execution (`qexec_execute_mainblock_internal`), so enclosing-query correlated values are fixed for its life |
| `Mutant = "key_has_later"` | `xasl_generation.c` `pt_get_mvcc_reev_range_data`: `parser_copy_tree (index_pred->term_exprs[idx])` copies the term's `next` chain, so x's `where_range` holds the WHERE's later terms (`y.k = x.k + 0`, `y.c = x.c`) and `key_maker` takes y's slots | develop defect |
| `Probe` | `memoize.cpp` `storage::get`, `key_changed` branch: `m_last_key = get_key ()`, `equal_range`; `query_executor.c` `qexec_execute_nljoin_with_memoize` | one thread, no shared state |
| `Replay` / `ReplayEnd` | `storage::get`, `has_range` branch: `set_value` of one stored row, then `scan_ptr` (y) runs for it; `ENDED` when `m_current_value_list` is empty | one thread |
| `ScanRow` + `PutRow` | `query_executor.c` `qexec_execute_scan` → `memoize_put` → `storage::put` (`can_insert`, `get_key`, `insert`), then the row goes to `scan_ptr` (y) | one thread: nothing runs between put and y for the same row |
| `PutKey = "reread"` | `storage::put`: `key *k = get_key ()` reads the slots again at every row | develop |
| `PutKey = "probe"` | `storage::put` stores a copy of `m_last_key` | option under decision |
| `ScanSkip` | x row not matching this outer value | |
| `ScanEnd` | `storage::put_nullptr` when `!current_key_joined` | one thread |
| stop branch of `PutRow` / `ScanEnd` | `storage::can_insert` → `stop_insert`: erase `equal_range (m_last_key)` if `current_key_joined`, `insert_stopped = true` | |
| disable branch | `can_insert` sets `disabled`; caller gets `FULL` and frees the storage (`clear_memoize_storage`) | |
| `ev`, `xe[r]` | an enclosing-query value the inner's terms read (`TYPE_CONSTANT` flagged `REGU_VARIABLE_CORRELATED`), and x row r's match on it | data, fixed for one execution of the subquery |
| `NewExec` | the next execution of the subquery holding the NL chain: `qexec_execute_mainblock_internal` opens the scans again, and at the inner's open `new_memoize_storage` frees the old storage (`clear_memoize_storage`) and builds a new one; y's `val_list` slot keeps its value | one thread |
| `EncKey` | whether the enclosing value is a key slot: `FALSE` (D9) | |
| `Mutant = "storage_kept"` | a storage that outlives one execution (not the code: the code rebuilds it) | mutant |
| `sv`, `xv[r]`, `sva[j]` | a session variable x's terms read (`@v`), x row r's match on it, and its value when outer row j was probed | data; `sva` is the ghost the memo-off answer of row j uses |
| `SvAssign` | the select list's `@v := ...` (`PT_DEFINE_VARIABLE`) of the row just joined, before the next outer row's probe | environment, no fairness; enabled only with `SessAssign` |
| `SvGuard` / `NoStorage` | decided TRUE (D18, D22): the generator sets `XASL_NO_MEMOIZE` when the inner's terms read a session variable, so the storage is never built | `disabled` from the start |
| C3 reading of the model | the subquery cache is the same shape: an "outer row" is a row that evaluates the subquery, x is the subquery, the key is its correlated values (`pt_make_sq_cache_key_struct`), the storage lives for one execution of the query block (`sq_get` / `sq_put`). `mutant-sessvar` / `sessvar-guard` are C3's session-variable rule, `mutant-missing-outer` its key completeness | the cache has no split-key path (one result per key), so `mutant-develop` has no C3 counterpart |
| `hitRow`, `hitAfterStop` | ghosts for witnesses | |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `OutputCorrect` | invariant | every finished outer row emitted each matching x row once and nothing else | C1, C3 |
| `StoreSound` | invariant | every key in the memo other than the one being filled is `Complete` | C2 |
| `IndInv` | inductive invariant | `TypeOK`, `OutputCorrect`, `StoreSound`, `CurOut`, `LaterOut`, `RepIdle`, `PhaseIdx`, `DisabledEmpty`, `ScanKey`, `KeySlot`, `SvRow` | C1, C2 |

## Fault model and environment assumptions

| Fault | Modeled as |
|---|---|
| error return | not modeled: an error from `memoize_put`/`get` ends the query (`GOTO_EXIT_ON_ERROR`), no answer to compare |
| interrupt / query cancel | not applicable: ends the query, no answer |
| lock timeout, deadlock victim | not applicable: the memo path runs only when `!mvcc_select_lock_needed` |
| conditional latch failure | not applicable: the memo holds no page |
| OOM | `get_key`/`get_value` returning null is an error return (above) |
| crash / `kill -9` | not applicable: the memo is private memory of one query |
| spurious wakeup | not applicable: no wait |
| concurrent DML, vacuum | not applicable: one statement snapshot; every probe of x sees the same rows (`xk` is fixed) |
| checkpoint, flush, replacement | not applicable: no page held |
| HA log apply | not applicable |
| nested statement (SP SQL) | not modeled: a stored function in x's terms is a key operand, not a scan |
| session variable assignment | `SvAssign` between outer rows when `SessAssign`; develop probe `.git_ignored_dir/scratch/cbrd27993/sessvar/` (memo on 36 rows, off 129) |
| budget reached | `PutRow` / `ScanEnd` stop branch, at any put |
| hit ratio judged low | disable branch, at any put |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-develop` | key has y's slot, put reads it again (develop) | `OutputCorrect` violated: 3 outer rows of one value, 3 x rows; y changes its slot after row 2, so rows 1-2 go under key (v, NULL) and row 3 under (v, 1); outer row 2 probes (v, 1) and replays 1 row of 3 | C1 |
| `mutant-develop-store` | same | `StoreSound` violated | C2 |
| `mutant-missing-outer` | key lacks the outer value | `OutputCorrect` violated | C1, C3 (a subquery cache key missing a correlated value) |
| `mutant-stop-keeps-partial` | `stop_insert` keeps the current key's entries | `OutputCorrect` violated | C1 (CBRD-27487 rule) |
| `mutant-sessvar` | the select list assigns the session variable x's terms read, memoize kept (develop) | `OutputCorrect` violated: a later outer row of the same value replays rows matched under the old `@v` | C1, C3 (D18, D22: `SvGuard`) |
| `mutant-storage-kept` | the storage survives into the next execution while the enclosing value is not a key slot | `OutputCorrect` violated: the second execution replays rows matched under the first execution's enclosing value | C1 (with `EncKey = FALSE`, the rebuild per execution is the protection) |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-hit-row` | a hit replayed a row |
| `witness-hit-after-stop` | a hit was served after inserts stopped |
| `witness-disabled` | the storage was disabled |
| `witness-second-exec-hit` | a hit in the second execution of the subquery |
| `witness-sv-assigned` | the session variable changed between outer rows and the statement finished |

## Decisions

| # | Decision | Round | Evidence |
|---|---|---|---|
| D1 | C1 and C2 are the claims, with budget stop and disable at any put | 1 | all pass cfgs; mutant cfgs |
| D2 | The memoize key is the values from outside the inner that stay fixed for the probe: columns of scans before the inner in join order and enclosing-query correlated values; never a later scan's column, the inner's own column or a subquery result (GLOSSARY `메모이즈 키`) | 1 | `mutant-develop` (later scan in the key breaks C1), `mutant-missing-outer` (outer value missing breaks C1) |
| D3 | The key is chosen when the inner's XASL is generated, carried in the XASL like the correlated subquery cache key; the server's `key_maker` goes | 1 | `NlMemoKey` (key = outer values only) pass; the location is not a model behavior, ADR 0053 |
| D4 | (superseded by D8) The generator collects the key by walking the generated inner XASL and keeping TYPE_CONSTANT slots that point into an outer plan node's `table_info` value_list, plus enclosing-query correlated values (A2), not the optimizer's key segments (A1) | 2 | `mutant-missing-outer`: a segment set that misses a subquery's outer column breaks C1 |
| D5 | `storage::put` keeps reading the key slots (no probe-key reuse): with D2 the slots do not change during a probe | 2 | `NlMemoKey` (`PutKey = "reread"`) pass; `put-probe` pass too, so reuse adds nothing |
| D6 | `pt_get_mvcc_reev_range_data`'s next-chain copy stays out of scope; no issue without a repro | 2 | after D3 memoize no longer reads `where_range`; probes `.git_ignored_dir/scratch/cbrd27993/probe1/` (partition pruning) and `reev/` (UPDATE join MVCC reevaluation under a lock wait) gave develop's right answers; the reev probe has no plan evidence that the range filter was read |
| D7 | The refusals CBRD-27567 added for an inner's correlated subquery (CONNECT BY, GROUP BY, analytic, HAVING subquery; `memoize.cpp` `possible_check` level >= 1) are lifted, as far as the key collection and the nondeterminism check then cover those parts | 2 | user, round 2 |
| D8 | Supersedes D4 (D7 made A2's hand-listed XASL walk cover 24 more regu fields). Where `plan_generation.c` decides `XASL_NO_MEMOIZE` for the NL inner, a key-only `parser_walk_tree` over the parse trees of the terms the inner evaluates collects the PT_NAMEs of outer plan nodes (by spec_id) and maps each to its `table_info` value_list DB_VALUE, as `pt_attribute_to_regu` does; the walk does not stop inside PRIOR | 3 | `mutant-missing-outer`; `set_seg_expr` stops at PRIOR, CONNECT_BY_ROOT, SYS_CONNECT_BY_PATH |
| D9 | Amends D2: enclosing-query correlated values are not key slots. The storage is rebuilt at every execution of the subquery holding the NL chain (`qexec_execute_mainblock_internal` → `new_memoize_storage`), so they are fixed for its life | 3 | `NlMemoKey` (`EncKey = FALSE`) pass; `mutant-storage-kept` breaks C1 without the rebuild; `enc-key` / `enc-key-storage-kept` pass |
| D10 | Under `!NDEBUG` the server keeps the old `key_maker` walk and asserts that every TYPE_CONSTANT it finds pointing into a preceding scan's `val_list` is a key slot, so CTP names a shape the generator missed | 3 | user, round 3 |
| D11 | The nondeterminism check moves to generation: `pt_check_corr_subquery_not_cachable_expr` over the same term parse trees sets `XASL_NO_MEMOIZE`; `memoize.cpp` `nondeterministic_check` goes | 4 | the runtime check walks only `key_maker`'s fields, so D7's lifted parts would hide a RANDOM |
| D12 | A stored function not declared DETERMINISTIC in the inner's terms sets `XASL_NO_MEMOIZE`, in CS and SA alike (not copying the subquery cache's `#if defined (CS_MODE)` guard) | 4 | CBRD-27734 shortcut comment; probe `.git_ignored_dir/scratch/cbrd27993/sp-sa/`: develop's subquery cache caches a NOT DETERMINISTIC function in SA (2 distinct of 10; CS 10 of 10; SA with `NO_SUBQUERY_CACHE` 10 of 10) |
| D13 | The key comes from the terms the inner evaluates only; a select-list subquery attached to the inner adds no slot (its result is not in the memo value and it reruns per replayed row) | 4 | over-keying a stable value keeps C1 (`enc-key`), costs hits only |
| D14 | Level >= 1 refusals in `possible_check`: lifted where they came from `key_maker` reading one spec (no FROM, `spec->next`, bptr/fptr, non-LINK dptr inside the subquery, set-typed val_list, JSON_TABLE / SET / REGUVAL_LIST targets); kept where the subquery reads data outside the statement snapshot (system and MVCC-disabled classes, record/page/key/node info and schema access, METHOD, SHOWSTMT, DBLINK, CLASS_ATTR). Level 0 unchanged | 4 | C1 needs a key's result fixed for the query; the replay does not re-evaluate x's filter subquery |
| D15 | An inner built by `pt_gen_simple_plan` (optimizer off, a non-expression conjunct, more than `OPTIMIZATION_LIMIT` nodes, OOM) has no key and is not memoized | 4 | user, round 4 |
| D16 | `qo_nl_inner_memoize_is_useless` estimates the NDV of the collected key's outer columns, not of a separate term-segment set | 4 | user, round 4 |
| D17 | An inner whose terms read no outer value (empty key) is memoized: every outer row probes the one key; develop refused it (`key_cnt == 0`, since de56265bb) | 5 | an empty key is a key whose value never changes; `NlMemoKey` covers runs where every outer row has one value |
| D18 | (condition superseded by D22) The generator sets `XASL_NO_MEMOIZE` when the inner's terms read a session variable (`PT_EVALUATE_VARIABLE`) and the statement assigns one (`PT_DEFINE_VARIABLE`); in this issue | 5 | `mutant-sessvar` breaks C1, `sessvar-guard` pass; develop probe `.git_ignored_dir/scratch/cbrd27993/sessvar/` memo on 36 rows, off 129 |
| D19 | The correlated subquery cache's two develop defects are fixed in this issue: a NOT DETERMINISTIC stored function is cached in SA (`pt_make_sq_cache_key_struct`'s `#if defined (CS_MODE)` guard; the signature is built in SA too, `pt_stored_procedure_to_regu`), and a subquery reading a session variable the statement assigns is cached | 5 | probes `sp-sa/` (SA 2 distinct of 10, CS 10, SA `NO_SUBQUERY_CACHE` 10) and `sessvar/sq.sql` (cache on sum 24, off 84) |
| D20 | Claim C3 (the correlated subquery cache returns the cache-off result) joins C1 and C2 | 6 | user, round 6 |
| D21 | One parse-tree check serves memoize and the subquery cache: walker callback `pt_check_reuse_unsafe_expr` (renamed from `pt_check_corr_subquery_not_cachable_expr`) and wrapper `pt_is_result_reuse_safe`; it refuses the 8 operators, a stored function not DETERMINISTIC (directive read through `jsp_find_stored_procedure`), and a session-variable read when the statement assigns one. `pt_make_sq_cache_key_struct`'s TYPE_SP check (CS-only) goes | 6 | user, round 6 (name chosen to fit both features; the engine's "volatile" means an operator a fetch does not cache, `qexec_opcode_is_prior_or_volatile`) |
| D22 | Supersedes D18's condition: any session-variable read (`PT_EVALUATE_VARIABLE`) or assignment (`PT_DEFINE_VARIABLE`) in the checked tree refuses result reuse, for memoize and the subquery cache alike; the statement-wide assignment pass goes | 6 | user, round 6 (simplest check). The model's `SvGuard` refuses an inner that reads a session variable; its `SessAssign = FALSE` cfgs stand for inners that read none |
| D23 | The shared check also refuses `INCR`, `DECR`, `EXEC_STATS`, `TRACE_STATS` and `SLEEP` (their result or side effect differs on re-evaluation); `ROW_COUNT` and `LAST_INSERT_ID` stay reusable (fixed for the statement: probe `.git_ignored_dir/scratch/cbrd27993/volatile/` INSERT ... SELECT memo on and off both 97 rows) | 6 | the engine's own lists: `pt_is_shareable_groupby_ref_pre`, `fetch.c` operators a fetch does not cache |
| D24 | The key collection also walks the derived table of every node of the inner plan (`QO_NODE_ENTITY_SPEC (node)->info.spec.derived_table`), and the shared check runs on it when it reads an outer column: a derived table correlated to an outer row is rebuilt for every outer row, so the outer columns it reads are inputs of the inner and its expressions are replayed; an uncorrelated one is made once and memo on and off read the same list (cbrd_25748: a NOT DETERMINISTIC function in an uncorrelated derived inner stays memoized). The optdebug census walks the XASL that makes the list the inner reads (`ACCESS_SPEC_XASL_NODE`) | impl | found by the full CTP on the first build (wrong rows in cbrd_27567 Case 15, cbrd_27602, cbrd_27657, medium fderiv1, 6741): D17 lifted develop's `key_cnt == 0` refusal, which had hidden this input; the model's `os[j]` row already meant "every outer input", the map took only the terms (cubrid-tla P77). develop misses the same input when such an inner also has an outer term (`smoke/s9_derived.sql` D2 on 2d928e34b: memo on 16/8, off 4/4) |

## Option cfgs

| cfg | Option | Result |
|---|---|---|
| `NlMemoKey` | key = outer values only, put reads the slots again | pass |
| `put-probe` | key = outer values only, put reuses the probe key | pass |
| `overkey-put-probe` | key still has y's slot (develop key), put reuses the probe key | pass: an extra slot is safe once every row of a probe goes under the probe key |
| `enc-key` | the enclosing value is a key slot | pass |
| `enc-key-storage-kept` | the enclosing value is a key slot and the storage outlives an execution | pass: keying the enclosing value is needed only if the storage outlives an execution |
| `sessvar-guard` | the statement assigns the session variable x's terms read; the generator refuses memoize | pass |

## Dead expressions (pass cfg)

| Line | Why never evaluated |
|---|---|
| NlMemoKey.tla:234 | `NewExec` keeps the storage only under `Mutant = "storage_kept"`: dead in every cfg without that mutant |
| NlMemoKey.tla:235, NlMemoKey.tla:236 | `NewExec`'s rebuild branch: dead in `enc-key-storage-kept` (its mutant keeps the storage) and in `sessvar-guard` (one execution) |
| NlMemoKey.tla:241, NlMemoKey.tla:242 | `SvAssign`: enabled only with `SessAssign = TRUE`, dead in every other cfg |
| NlMemoKey.tla:137, NlMemoKey.tla:138, NlMemoKey.tla:147, NlMemoKey.tla:149, NlMemoKey.tla:150, NlMemoKey.tla:151, NlMemoKey.tla:153, NlMemoKey.tla:155, NlMemoKey.tla:156, NlMemoKey.tla:164, NlMemoKey.tla:165, NlMemoKey.tla:166, NlMemoKey.tla:167, NlMemoKey.tla:168, NlMemoKey.tla:173, NlMemoKey.tla:186, NlMemoKey.tla:188, NlMemoKey.tla:189, NlMemoKey.tla:190, NlMemoKey.tla:192, NlMemoKey.tla:193, NlMemoKey.tla:196, NlMemoKey.tla:198, NlMemoKey.tla:199, NlMemoKey.tla:213, NlMemoKey.tla:214, NlMemoKey.tla:216, NlMemoKey.tla:217, NlMemoKey.tla:219, NlMemoKey.tla:220 | `sessvar-guard` only: the guard leaves the storage unbuilt (`disabled` from the start), so the probe's key branch, `Replay`, `ReplayEnd` (and the `Advance` it instantiates), every insert/stop/disable branch of `PutRow` and `ScanEnd` never run; `ScanRow` and `ScanEnd` take the disabled branch |
| NlMemoKey.tla:229, NlMemoKey.tla:230, NlMemoKey.tla:231, NlMemoKey.tla:232, NlMemoKey.tla:237 | `NewExec`: dead in `sessvar-guard`, which runs one execution (`NEX = 1`) |

## Bounds and limits

- TLC: 3 outer rows, 3 x rows, 2 outer values, 1 y value (+NULL), 2 enclosing values, 2 executions, every data assignment; scale: 4 outer rows. (A scale of 4 outer rows, 3 x rows and 2 y values ran under 90 k states/min and was stopped.)
- Session-variable cfgs (`sessvar-guard`, `mutant-sessvar`, `witness-sv-assigned`): 3 outer rows, 2 x rows, 1 execution. At 3 x rows and 2 executions `sessvar-guard` passed 15 M distinct states at depth 29 without ending and was stopped.
- Apalache (`apalache-indinv`): IndInv inductive at the main cfg's sizes for every data value and state (sizes are function domains, fixed), with `SessAssign = FALSE`.
- One memoized inner. Several memoized inners in one chain, parallel workers and partition block renewal are not modeled.

## Result

- 2026-11-10, `tools/tla/tla-check docs/tla/CBRD-27993/`: `RESULT: OK`, run dir `.git_ignored_dir/scratch/tla/CBRD-27993-20261110-130842-2300886`, toolchain `/nix/store/mcnrlar201f0kiwhaz2d8pfxhbl6h3zb-tla-tools`.
- TLC pass cfgs (distinct states, depth): `NlMemoKey` 1 786 076 / 32; `scale-4` 6 005 612 / 42; `put-probe` 1 786 076 / 32; `overkey-put-probe` 1 698 816 / 32; `enc-key` 1 793 644 / 32; `enc-key-storage-kept` 2 351 372 / 32; `sessvar-guard` 262 144 / 16.
- 6 mutants rejected (`mutant-develop`, `mutant-develop-store`, `mutant-missing-outer`, `mutant-stop-keeps-partial`, `mutant-storage-kept`, `mutant-sessvar`); 5 witnesses reached.
- Apalache `apalache-indinv`: IndInv inductive at the main cfg's sizes (164 s).
- TLAPS: not requested (P48).
- Spec sha256: `NlMemoKey.tla` 74902a715ee53f42a977e57859e1534ffbf054d56d5fe78f4b4b23bdba85e882 (cfg hashes in the run dir's `summary.txt`).
- Engine: develop 2dac6ecc2 (code read); runtime probes on develop optdebug 2d928e34b. Trace validation: trace-exempt (design spec before implementation; the implementation spec refines it).
