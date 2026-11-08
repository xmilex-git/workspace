# CBRD-27430 A8 — an AREA allocation failure inside the folded server

Map [CAS 폴드 재이식 지도](https://github.com/xmilex-git/workspace/issues/618), ticket
[A8 이식 — 에러/크래시 격리](https://github.com/xmilex-git/workspace/issues/629). The client half's AREAs
(`area_alloc.c`: domains, set references and objects, `DB_VALUE` containers, object and schema templates, object
lists) are process-wide in cub_server. A client process aborts its transaction when one of them cannot grow
(`failure_function = ws_abort_transaction`); the server set the callback to NULL. A8 installs the callback in the
server too, so the folded client half keeps its client semantics (#128 D8), and decides on which thread and in which
half the abort may run.

The map's #620 verdict put A8 outside TLA+ ("primitive evidence"); the user asked for `/cubrid-tla` on this stage
(2026-11-08). The other A8 items — the parser nesting guard, the per-thread alternate signal stack, the abort
handler's single dumper, FATAL→ERROR severities — have no shared mutable state beyond the abort handler's one atomic
flag; they are covered by smoke and the runtime checks in the ticket's resolution, not by this model.

Code: fork branch `cas-fold-v2`, A8 commit `c9cbc3519` on `d5ccd9ad8` (worktree `~/dev/cubrid-worktree/cas-fold-v2`).
Old implementation: `cas-merge` @ `cdb9da11e`, the attribution table's A8 commits `2c675a5980` (callback installed,
gate = a bracket) and `301791dede` (callback moved out of `area_mutex`, in-progress guard); diffs in the tooling
scratch `fold-v2/a8/old-*.diff`. The old gate is the model's `old_a8` mutant.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | An AREA allocation failure never ends a transaction under a server-half executor: a failure while the thread runs the server half (db_on_server > 0) only fails the allocation, and the executor keeps its page fixes and its query in progress. | #128 D8 (OOM outside workspace mutation is a statement error); A3 claim "the fold boundary does what the wire boundary does" — a CS server's AREA failure has no callback (`area_alloc.c` SERVER_MODE `failure_function = NULL`); `qmgr_clear_trans_wakeup` asserts `QUERY_COMPLETED` (`query_manager.c:2327`), `pgbuf_unfix_all` unfixes every page outside a dispatch (`page_buffer.c:3243`) |
| C2 | A failure in the client half of a registered session's bracket (db_on_server = 0, at the top or inside a method dispatch) aborts that session's transaction; the allocation returns NULL with `ER_LK_UNILATERALLY_ABORTED`, and the session lives on. | #128 D8 ("ws_abort_transaction의 서버판 번역", session survives); develop CS `failure_function = ws_abort_transaction` for every client AREA; user decision 2026-11-08 (keep develop's abort on any client-half AREA failure — D8's compile/mutation phase split rested on F4, which missed the callback); A7 C6 (a transaction end inside a dispatch leaves the outer fixes) |
| C3 | Only a registered session's own transaction is ever aborted: a thread with no bracket, and a bracket with no registered client (the server boot's shared context, a session retired after its logout: `tm_Tran_index = NULL_TRAN_INDEX`), only fail the allocation. | #128 D4/D8; old `2c675a5980` (no bracket = fail the allocation); `boot_initialize_client_modules` / `csc_retire_and_delete` brackets (A4, A5) |
| C4 | The failure callback never runs while its thread holds `area_mutex`, so the abort's own allocations never wait on a mutex their thread holds. | old `301791dede` (review blocker: self-deadlock under `area_mutex`) |
| C5 | A failure inside the abort does not start a second abort; it leaves its error and returns. | old `301791dede` (thread-local in-progress guard) |

## Refinement map (model -> code)

Line numbers are at `c9cbc3519`.

| Model | Code | One step because |
|---|---|---|
| `FastAlloc(t)` | `area_alloc` steps 1–2: `hint_block->bitmap.get_entry ()` / the blockset scan (`area_alloc.c:385-420`) | an LF bitmap claim, one atomic |
| `Lock(t)` | `pthread_mutex_lock (&area->area_mutex)` (`area_alloc.c:423`) with every block full | the mutex |
| `MallocOk(t)` | `area_alloc_block` returns a block, `area_insert_block`, `area->hint_block = block`, unlock (`:446-465`) | under `area_mutex` |
| `MallocFail(t)` | `area_alloc_block` (`:317`) or `area_insert_block`'s `area_alloc_blockset` (`:348`) returns NULL after `er_set (ER_OUT_OF_VIRTUAL_MEMORY)`; `area_alloc` unlocks (`:440`, `:456`) — the callback is no longer called inside them | under `area_mutex`; the unlock ends the step |
| `Callback(t)` | `area_call_failure_function` (`:443`, `:458`) → `ws_abort_transaction` (`work_space.c:273`): the SERVER_MODE gate `!csc_bracket_is_active () \|\| tm_Tran_index == NULL_TRAN_INDEX \|\| db_on_server != 0` (`:287`), then `ws_abort_in_progress` (`:292-297`) | thread-local state and the thread's bracket (the csc is the session's, held by `bracket_mutex`, A4) |
| `AbortAlloc`, `AbortMallocOk`, `AbortMallocFail` | an AREA allocation inside `tran_unilaterally_abort` (`transaction_cl.c:558`) → `tran_abort` | as the outer steps |
| `AbortCallback(t)` | `ws_abort_transaction` re-entered: the server gate (the abort's folded server call runs with db_on_server > 0) or `ws_abort_in_progress` returns | thread-local |
| `AbortEffect(t)` | `tran_unilaterally_abort` → `tran_abort`: `ws_abort_mops`, `db_clear_client_query_result`, `tran_server_abort` → folded `xtran_server_abort` → `lock_unlock_all` → `pgbuf_unfix_all` (returns at once inside a dispatch, `page_buffer.c:3243`) and `qmgr_clear_trans_wakeup` (skips a query in progress while a pl session runs, `query_manager.c:2335`); `er_set (ER_LK_UNILATERALLY_ABORTED)` | the session's own state under its bracket; the server half of the abort on this thread |
| `Return(t)` | `area_alloc` returns NULL; the caller's error path (an executor's `qexec_clear_*`, scan close) | thread-local |
| `EnterServer`, `ExitServer` | `enter_server_no_thread_entry` / `exit_server_no_thread_entry` (`network_interface_cl.c`) at db_on_server 0↔1: the executor's query starts and ends with its page fixes | thread-local |
| `DispatchIn`, `DispatchOut` | `method_dispatch` (`query_method.cpp:226`): `db_on_server = 0`, libcas depth 0↔1 | thread-local (A7) |
| `hat` | `db_on_server` and `tm.libcas_depth` of the thread; for a thread with no bracket, the request it serves | |
| `qry`, `lost` | the executor's `QMGR_QUERY_ENTRY::query_status`, its page holders | |
| `free`, `mutex` | the newest block's free entries, `AREA::area_mutex` | |
| `inAbort` | `ws_abort_in_progress` (`static thread_local`) | |
| `aborted` | `tdes->state` of the aborted transactions | |
| roles | `Brackets`: tracer/driver threads in a registered session's bracket; `BootT`: `boot_Shared_client_context`'s bracket at server boot/shutdown, and `csc_retire_and_delete`'s bracket after the logout; `Workers`: CS request workers, daemons, px workers (no bracket, db_on_server = 1 from `network_interface_sr.cpp:125`) | |
| `serverAbort`, `uaf`, `missed`, `wrongAbort`, `selfDeadlock`, `recAbort`, `guardHit`, `outcome`, `outHat` | ghosts | — |

Callers of the protocol entry points: `area_call_failure_function` — `area_create` (`:222`, `:229`, before
`area_mutex` is initialized), `area_alloc` (`:443`, `:458`, after `pthread_mutex_unlock`); census of the
`failure_function` call sites: these four only (`area_alloc_block` and `area_alloc_blockset` no longer call it).
`area_alloc` — `classobj_make_template`, `tp_domain_new`, `pr_make_ext_value`, `make_template`,
`obt_make_assignment`, `col_new`, `set_make_reference`, `ml_ext_alloc_link`, `ml_ext_add` (code-index `callers`).
`ws_abort_transaction` — only through `failure_function`. Exit paths: the server gate (no bracket, no registered
client, server half), the guard, `db_Disable_modifications` (sets the OOM error, no abort; HA read-only client
type, B3), the abort; all return to `area_alloc`, which returns NULL.

## Properties

| Name | Kind | Claim |
|---|---|---|
| `NoServerHalfAbort` | invariant | C1 |
| `NoUseAfterRelease` | invariant | C1 (the executor's error path or end reads its fixes and query entry) |
| `ClientOomAborts` | invariant | C2 |
| `Isolation` | invariant | C3 |
| `NoSelfDeadlock` | invariant | C4 |
| `NoRecursiveAbort` | invariant | C5 |
| `IndInv` | invariant (inductive) | all, with the structural lemmas (mutex holder, phases, errors per phase, roles) |

## Fault model

| Fault | Modeled | Where / why not |
|---|---|---|
| malloc failure growing an AREA | yes | `MallocFail`, `AbortMallocFail`, at every allocation of every role and half, up to `MaxFaults` per run |
| malloc failure in `area_create` | no (code fact) | every `area_create` runs at boot (`*_area_init`, A5: shared client modules at server boot) inside `boot_Shared_client_context`'s bracket, whose `tm_Tran_index` is `NULL_TRAN_INDEX` (BootT): the callback returns |
| OOM outside AREAs (`db_private_alloc`, `malloc` in the parser) | no | no callback: the caller's error path (#128 D3, statement error) |
| interrupt, lock timeout, deadlock victim during the abort | no | `tran_abort` cannot be interrupted out of; a victim's own abort is A3's |
| `db_Disable_modifications` (HA read-only client) | no | sets `ER_OUT_OF_VIRTUAL_MEMORY` and returns: no state change; process-wide until B3 moves it to the session |
| crash / `kill -9` | no | process memory |
| a session retired while its thread fails | no (A4) | the retirement waits for `bracket_mutex`; the retiring thread's own bracket has no registered client (BootT) |
| px worker allocations | yes (as Workers) | no bracket, db_on_server = 0 |
| concurrent allocations from the same AREA | yes | all roles share `free` and `mutex` |

## Mutants

| Mutant | cfg | Re-enables | Rejected by |
|---|---|---|---|
| `old_a8` | `mutant-old-a8` | the old gate: any bracket (C1) | `NoServerHalfAbort` |
| `old_a8` | `mutant-old-a8-uaf` | the same, its consequence (C1) | `NoUseAfterRelease` |
| `no_registered` | `mutant-no-registered` | no `tm_Tran_index` check (C3) | `Isolation` |
| `no_bracket` | `mutant-no-bracket` | no `csc_bracket_is_active` check (C3) | `Isolation` |
| `null` | `mutant-null` | `failure_function = NULL` in SERVER_MODE, as before A8 (C2) | `ClientOomAborts` |
| `cb_under_mutex` | `mutant-cb-under-mutex` | the callback inside `area_alloc_block` under `area_mutex`, as develop (C4) | `NoSelfDeadlock` |
| `no_guard` | `mutant-no-guard` | no `ws_abort_in_progress` (C5) | `NoRecursiveAbort` |

## Witnesses

| cfg | Outcome |
|---|---|
| `witness-client-abort` | a client-half failure aborts its session's transaction |
| `witness-dispatch-abort` | a failure inside a method dispatch aborts it while the outer executor keeps its fixes |
| `witness-server-error` | a server-half failure is a NULL allocation with the transaction active |
| `witness-guarded` | a failure inside the abort hits the guard and the abort completes |
| `witness-unregistered-error` | a boot bracket or a worker failure returns NULL and aborts nothing |

## Counterexamples (correct variant) and their classification

| # | cfg | Trace | Class |
|---|---|---|---|
| 1 | `apalache-indinv` | a worker in `malloc` with `err = "unilat"` | IndInv too weak: added `ap ∈ {none, lock, malloc} ⇒ err = none` and `err = unilat ⇒ ap = ret ∧ RightGate` |
| 2 | `mutant-no-bracket` (first run passed) | — | surviving mutant: every server thread starts with db_on_server = 1 (`network_interface_sr.cpp:125`) and only a bracket thread drops it to 0, so the gate's db_on_server test alone already refuses a thread with no bracket. The bracket test is still needed, first: `tm_Tran_index` is `csc_tm ()->tran_index`, and `csc_current ()` asserts (and returns NULL in release) on a thread with no bracket. The mutant now models that read (`noCtx`, part of `Isolation`); `DbOnServer(t)` gives workers db_on_server > 0 (a worker run logged `h=server`) |

## Findings

| # | Finding | Evidence | Disposition |
|---|---|---|---|
| H1 | The old A8 gate (any bracket) aborts the transaction from the server half, under the running executor: the abort's client-half work and its folded `xtran_server_abort` (`pgbuf_unfix_all` outside a dispatch, `qmgr_clear_trans_wakeup` on the query in progress) run below an executor that resumes afterwards. | `mutant-old-a8`, `mutant-old-a8-uaf`; runtime fail-before on the instrumented build with `CUBRID_TLA_A8_OLD_GATE=1`: `SELECT SET{id, v} FROM a7t` with a "Set objects" failure in the server half (`heap_classrepr_get` → `or_unpack_set` → `col_new` inside `scan_open_index_scan`) logs `Gate go=1` in the server half, then SIGSEGV in `mspace_free` ← `ws_free_class_memory` ← `ws_decache` ← `ws_abort_mops` ← `tran_abort` (core 32428), and the auto-restarted server repeats it as an assert in `ws_decache` (core 32759); the run is accepted by the `old_a8` mutant and refused by the correct spec (`reject-oldgate`). Same run on the A8 gate: `Gate go=0`, the statement fails with -3, no core (`witness-trace-server`) | fixed in `c9cbc3519`: the gate requires db_on_server == 0 |
| H2 | The old gate also aborts on a bracket with no registered client: at server boot (`boot_Shared_client_context`) the folded abort would run `xtran_server_abort` on the boot thread's transaction index. | `mutant-no-registered` (no runtime run: needs a failure during boot's `showstmt_metadata_init`) | fixed: `tm_Tran_index == NULL_TRAN_INDEX` returns |
| D1 | develop defect, not A8's: a client-half AREA failure while a class is decoded (`tf_disk_to_class` → `disk_to_attribute`: a domain or a property-list set that cannot be allocated) is not checked; the decoder reads on with a NULL domain and asserts in `or_get_int` / `or_advance` (optdebug). | instrumented runs with the first client-half allocation failing: cores with the abort (`client`, `guard` runs) and with no callback at all (`CUBRID_TLA_A8_NULL_GATE=1`, core 29506, the same stack) — the decoder, not the abort | out of A8's scope (#128 D1/D7: a client-half crash is server-grade); the same code crashes a CS client today. Reported in the ticket's resolution |

## Dead expressions

| Expression | Why |
|---|---|
| `FoldOom.tla:190` (`AbortAlloc`'s `mutex = t` branch) | mutant-only branch (`cb_under_mutex`) |
| `FoldOom.tla:208` (`recAbort' = TRUE`) | mutant-only branch (`no_guard`) |

## Bounds

Main: NB=2 bracket threads, HasBoot, NW=1, Block=2, MaxAllocs=2, MaxFaults=2, MaxMoves=3. Scale: NB=3. The
inductive check (Apalache) fixes NB, NW, HasBoot, MaxAllocs=2 and MaxMoves=3 (codomains of per-thread functions)
and ranges over every Block > 0 and MaxFaults.

## Trace validation

Instrumented scratch worktree `~/dev/cubrid-worktree/cas-fold-v2-tla8` at `c9cbc3519` (patch: tooling scratch
`fold-v2/a8/instrument.py`, `instrumented.diff`), optdebug install `CUBRID-cas-fold-v2-tla8`, runs through
`fold-v2/a8/trace/run.sh` on the smoke database (claimed port 1701). The injection reproduces `area_alloc`'s failing
slow path (lock, `er_set (ER_OUT_OF_VIRTUAL_MEMORY)`, unlock, callback, NULL) on the tracer thread from its case's
compile to its commit, filtered by the thread's half (`CUBRID_TLA_A8_HAT`) and AREA; events are logged at the
decision points (`Gate go=` at the gate's two exits, `AbortEffect` after `tran_unilaterally_abort`, `Ret` with the
error the caller sees). Successful allocations are hidden steps; the abort's own server calls are not logged as
half changes.

| cfg | Run | Events | Outcome of the run |
|---|---|---|---|
| `witness-trace-client` | `SELECT CAST(id AS VARCHAR(78)) FROM a7t`, a "Domains" failure in the client half (class cache warmed by a PRE statement) | 12 | `Gate go=1`, abort in the client half, compile fails with -72 (unilaterally aborted), session logs out, no core |
| `witness-trace-server` | `SELECT SET{id, v} FROM a7t ORDER BY id`, a "Set objects" failure in the server half | 37 | `Gate go=0`, the statement fails with -3, transaction not aborted, no core |
| `witness-trace-dispatch` | `SELECT a7f (2)` (PL/CSQL with static SQL), a failure in the callback's client half | 64 | `Gate go=1` inside the dispatch, routine fails (-889), outer executor resumes and ends, no core |
| `witness-trace-worker` | CS csql `SELECT SET{id, v} FROM a7t` after the tracer ended, a "Set objects" failure on a thread with no bracket (`p=99`) | 3 | `Gate go=0` (`h=server`: db_on_server = 1), csql gets -3, no core |
| `witness-trace-oldgate-mutant` (Mutant `old_a8`) | the server run with `CUBRID_TLA_A8_OLD_GATE=1` | 33 | `Gate go=1` in the server half, then the H1 cores |
| `reject-gate-flipped` | the client run with `Gate go=1` changed to `go=0` | — | refused |
| `reject-oldgate` | the old-gate run under the correct spec | — | refused |

Not reached by a run: `AbortMallocFail` / `AbortCallback` (the guard): with two consecutive failures armed, the abort
itself made no AREA allocation (no `AbortFail` event); the second failure hit the class re-fetch after the abort
(defect D1). C5 rests on the model and the code (`ws_abort_in_progress`). `Lock`, `MallocOk`, `FastAlloc`,
`AbortAlloc`, `AbortMallocOk` are hidden steps.

## Result

- Date: 2026-11-09. `tools/tla/tla-check docs/tla/CBRD-27430-A8` → `RESULT: OK`, run dir
  `.git_ignored_dir/scratch/tla/CBRD-27430-A8-20261109-004816-60436`.
- Per cfg (distinct states / depth for TLC):

```
FoldOom.apalache-indinv expect=[pass] got=[pass] apalache 9s
FoldOom expect=[pass] got=[pass] states=1008340/282099 depth=29 20s dead-expr-lines=190,208
FoldOom.mutant-cb-under-mutex expect=[violation NoSelfDeadlock] got=[violation NoSelfDeadlock] states=8/7 depth=5 1s
FoldOom.mutant-no-bracket expect=[violation Isolation] got=[violation Isolation] states=43/37 depth=7 1s
FoldOom.mutant-no-guard expect=[violation NoRecursiveAbort] got=[violation NoRecursiveAbort] states=1482/847 depth=8 1s
FoldOom.mutant-no-registered expect=[violation Isolation] got=[violation Isolation] states=139/103 depth=10 1s
FoldOom.mutant-null expect=[violation ClientOomAborts] got=[violation ClientOomAborts] states=80/66 depth=5 1s
FoldOom.mutant-old-a8-uaf expect=[violation NoUseAfterRelease] got=[violation NoUseAfterRelease] states=11673/5300 depth=10 2s
FoldOom.mutant-old-a8 expect=[violation NoServerHalfAbort] got=[violation NoServerHalfAbort] states=4822/2414 depth=9 1s
FoldOom.scale-nb3 expect=[pass] got=[pass] states=38780086/8466735 depth=35 514s dead-expr-lines=190,208
FoldOom.witness-client-abort expect=[violation NotClientAbort] got=[violation NotClientAbort] states=3820/1981 depth=8 2s
FoldOom.witness-dispatch-abort expect=[violation NotDispatchAbort] got=[violation NotDispatchAbort] states=35554/14747 depth=11 1s
FoldOom.witness-guarded expect=[violation NotGuarded] got=[violation NotGuarded] states=9731/4501 depth=9 2s
FoldOom.witness-server-error expect=[violation NotServerError] got=[violation NotServerError] states=761/471 depth=7 1s
FoldOom.witness-unregistered-error expect=[violation NotUnregisteredError] got=[violation NotUnregisteredError] states=1434/800 depth=7 1s
FoldOomTrace.reject-gate-flipped expect=[pass] got=[pass] states=44/32 depth=10 1s
FoldOomTrace.reject-oldgate expect=[pass] got=[pass] states=287/194 depth=37 2s
FoldOomTrace.witness-trace-client expect=[violation TraceNotDone] got=[violation TraceNotDone] states=75/58 depth=19 1s
FoldOomTrace.witness-trace-dispatch expect=[violation TraceNotDone] got=[violation TraceNotDone] states=537/366 depth=71 1s
FoldOomTrace.witness-trace-oldgate-mutant expect=[violation TraceNotDone] got=[violation TraceNotDone] states=289/196 depth=38 2s
FoldOomTrace.witness-trace-server expect=[violation TraceNotDone] got=[violation TraceNotDone] states=306/210 depth=42 1s
FoldOomTrace.witness-trace-worker expect=[violation TraceNotDone] got=[violation TraceNotDone] states=12/12 depth=8 1s
```

- TLAPS: not used. The user allowed it "if needed"; every claim is decided by one thread's state plus `area_mutex`,
  IndInv is inductive by Apalache over every Block > 0 and MaxFaults, and the scale cfg (NB=3, 8,466,735 distinct
  states) adds no interaction a proof over unbounded threads would cover.
- Spec sha256 (from the run's summary):

```
ec9505c0ed07379b794ff0f9ede629862af5aafff0c462884257bc9855c4718c  FoldOom.tla
997bc0871adaf2e3d160d5ec91edc3e7dd0fc7c84e7864c2b21aa14f91ba8851  FoldOomTrace.tla
ce5d6debbfcd680e50df1876b5a059d7a6ecac5ac69f897055ea1b77a353c1b4  FoldOomTraceData.tla
c125b833db849703bad4a87e5bc559c44349d966bfcf8a9439802e30d0bc967b  FoldOom.apalache-indinv.cfg
42ddec12c20e818eb0390eec6de2d688a7ebdfb844da506e3003420061855e3e  FoldOom.cfg
8d8d12f9da9f30e62ed39dde83a114bdd3355e46967f72318fe504ff8c8822d9  FoldOom.mutant-cb-under-mutex.cfg
3bd71a143644dab18cbf2e7bfa7afcc3165b578d704e8b3a0f676284248b6bbc  FoldOom.mutant-no-bracket.cfg
d26ad73f60ad2c849e7b0723c4bde881c108db649d7c11cc1bce1c7e021f37ad  FoldOom.mutant-no-guard.cfg
bf403a449348ead8abd1a07dc9421101dbf7feec0e198f627ceb65b9d927f3a5  FoldOom.mutant-no-registered.cfg
4569d767378d1a48d42a1f716316cffa5ba8c4f04e07d10e687ed56e1841d2f2  FoldOom.mutant-null.cfg
ff2c3aea24c9d194abc70f74e74136af792c5064d72cf29d95fec47412719ae0  FoldOom.mutant-old-a8-uaf.cfg
56f3761ed37e36c16ebf619702e93570331291a37ff176ed0d0410af4e38149e  FoldOom.mutant-old-a8.cfg
8887389fa2f0a3acdc37f733ed15134cbc50198bb6b982748dcf68c909c49260  FoldOom.scale-nb3.cfg
be1dc3a515c8da855144bde7d4ede9ba02361fc9d594bb9c2a5b1d3846e33730  FoldOom.witness-client-abort.cfg
f47090d28a082e291d32d951b6a119aec298e05aafa23d3c8879cb9a5c92a9ab  FoldOom.witness-dispatch-abort.cfg
8e511c4e3898e9b853eb1e5d4445abf9ae71bac2e083681e5a40fc8b2be1c4f4  FoldOom.witness-guarded.cfg
adfc56a1d9c81388dc07de470305261f72774db0c8a9d720e1646767877957f2  FoldOom.witness-server-error.cfg
ad348be4cf62db4abe9dcb1007558437af5a7eac127405fd37cb5ee7abd98aa0  FoldOom.witness-unregistered-error.cfg
52af2e54c1fa9a40db5ae2c04b6ea8c36b70021fad2e472faa913ae2aa23c099  FoldOomTrace.reject-gate-flipped.cfg
9fb525f15840f19b26f61fa6d73f9eddd454bd32626af47c5f1a589f743eecc3  FoldOomTrace.reject-oldgate.cfg
f30235e2643989d1e490343fd9f388c580938e5e0910fe9663db6d86d2ce5617  FoldOomTrace.witness-trace-client.cfg
c18359008a6ddd44138a6c24183e294e739aa19bd5adb832ae87099ba5f65c45  FoldOomTrace.witness-trace-dispatch.cfg
a51cc7d51518861750cb2b0b95869fc0a94ec9e57f6a6ba92dbf9fd9f2ec6d6a  FoldOomTrace.witness-trace-oldgate-mutant.cfg
9dfd4975154a358a9c70d3b82759aa21c8b714868ec43b1bdf9014db9253fa73  FoldOomTrace.witness-trace-server.cfg
70278a89a8ae17053c091d1d86751783b6239c1974952b31979c5645d22f1e76  FoldOomTrace.witness-trace-worker.cfg
e0d5774ef70be26e522def1f05201863dd9de393b5cb042c9f7aec23bb354c55  MAP.md
```

- Engine: `cas-fold-v2` `c9cbc3519`. Trace runs on the instrumented optdebug build of that sha (libcubrid
  `120d87d3c2ca6e53…`); gate builds optdebug `739cb1c48594331d…`, release `aa0cd1b41c565c3f…`.
