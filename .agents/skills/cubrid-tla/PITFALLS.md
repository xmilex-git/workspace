# PITFALLS — the rules and the runs that produced them

Each `P<n>` is one rule. The **Rule** line is the exact sentence SKILL.md or the reference file named in
**Applies at** carries; keep the two byte-identical (`tools/skills/check-pitfalls-drift.sh
.agents/skills/cubrid-tla`). **Case** is the run or user correction that paid for the rule, compressed
to what a reader needs to recognize the same situation. Sections follow the route in SKILL.md; the
TLAPS rules sit last because that path runs only on an explicit request (P48).

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule only when no rule fits — then the sentence goes into the skill in the same commit. Rule
numbers are stable (other skills, ADRs and `tools/tla/*` cite them); a rule folded into another keeps a
line under "Folded" at the end.

## Toolchain

### P1 — tools are judged by tla-check, never by their exit status
- Rule: TLC, Apalache and tlapm run only through `tools/tla/tla-check`, whose verdict is read per cfg and per obligation, never from a tool's exit status.
- Applies at: SKILL.md Toolchain; PROOFS.md
- Case (2026-11-05): the nix JDK behind `tlc` died with `UnsatisfiedLinkError ... java-1.8.0-openjdk/.../libnet.so` because CUBRID shells export Java 8's `LD_LIBRARY_PATH`; `env -u LD_LIBRARY_PATH` through the `~/.local/bin/env` shim printed nothing and exited 0. tla-check runs Java and tlapm through `/usr/bin/env -u LD_LIBRARY_PATH -u JAVA_HOME -u CLASSPATH -u JAVA_TOOL_OPTIONS`.
- Case (2026-11-05, px-error-handoff): `tlapm --toolbox 0 0` exited 0 with two obligations `@!!status:failed`; tla-check now requires proved = `@!!count`.

### P18 — tla-check is replaced, never rewritten in place
- Rule: `tools/tla/tla-check` is changed by writing a new file and renaming it over the old one: bash reads a running script from its open file.
- Applies at: SKILL.md Toolchain
- Case (2026-11-05, parallel scan): an in-place edit while this session's heap run and other sessions' TLAPS runs were executing it; bash re-reads at the byte offset it left, so a size change runs a partial line.

### P29 — stop only your own processes
- Rule: Stop only the processes your own runner started, by the pid it recorded; other sessions run TLC and tlapm on this host.
- Applies at: SKILL.md Toolchain
- Case (2026-11-06, CBRD-24094): `pkill -f` for this session's tlapm killed its own shell, and a `kill` of a pid read from `pgrep -fl` stopped another session's `PxHashJoin_proofs` run, redone from scratch.

### P41 — one toolchain per run
- Rule: A toolchain install during a run invalidates it: `tla-check --prove` fails a run whose proof logs carry different `TLAPM version` lines, and the run is repeated.
- Applies at: PROOFS.md (Running tlapm); enforced by tla-check
- Case (2026-11-06, parallel sort merge queue): the tools link moved from tlapm 1.4.5 to 1.6.0-pre at 01:31 during a 01:12 run; three modules logged 1.4.5 and two `efe4f2d`, `Safe` failed with `ls4 not found`. The rerun on one toolchain proved it.

### P46 — tlapm 1.6.0-pre is the prover
- Rule: Proofs are written and judged on tlapm 1.6.0-pre (`tlapm --version` prints `efe4f2d`); an obligation that times out there is split, never settled by an older log.
- Applies at: PROOFS.md (Running tlapm)
- Case (2026-11-06, PR #8356 review): the user asked "1.6버전으로 하고잇는건알고잇지?"; ADR 0045 records 1.4.5-proved obligations that time out on 1.6 (`ExprProgExec_proofs` 23:87, `PxHeapSnapshot_proofs` 118:5, 196:3).

### P48 — TLAPS only on an explicit request
- Rule: TLAPS runs only when the user's own message asks for a proof ("TLAPS", "증명해줘", "명확히 검증해줘"); a generic "TLA+로 검증", a skill, a ticket or a review step is not that request, and without it no proof module is written and the report says TLAPS 요청 없음.
- Applies at: SKILL.md Toolchain; PROOFS.md; cubrid-pr-review Step 3d; grill-with-tla; enforced by `tla-check --prove`
- Case (2026-11-06, rule review): over 124 tla-check runs tlapm took 26 214 s against 22 866 s for every TLC cfg together (parallel-hash-join alone: 7 proof modules, 11 371 s); 19 of 47 rules existed to get proofs through; every code defect in this file (P13, P14, P27, P43, P44) came from a TLC counterexample or deadlock. The user: "내가 명확히 검증해줘 라고 하지 않는 이상 TLAPS는 빼자". ADR 0046.

### P69 — `--only` takes the cfg name without `.cfg`
- Rule: `tools/tla/tla-check --only` matches cfg names without `.cfg` (`--only 'X'`, `--only 'X.mutant-*'`); `--only 'X.cfg'` matches nothing and prints only the completeness lines.
- Applies at: Toolchain
- Case (2026-11-09, PR 8431 review): `--only 'OvfScanStable.cfg'` ran no cfg and ended `RESULT: PARTIAL` with only the MAP/trace completeness FAILs; `--only 'OvfScanStable'` ran the main cfg.

## Step 2 — refinement map

### P11 — every exit path of the protocol is an action
- Rule: Before the model is final, list the callers of every protocol entry point (code-index `callers`) and give each exit path (LIMIT, error, interrupt, reset, the end of a range) an action or a fault-table row.
- Applies at: SKILL.md step 2
- Case (2026-11-05, parallel scan index): every cfg passed before a re-read of `px_scan_index_leaf_page_dispatcher.cpp` found `release_leaf` (5 callers: LIMIT, reset, overflow drain) and `signal_chain_ended` (6 sites), which end the chain while a worker holds the frontier. `W_stop` and the mutant `stop_keeps_chain` were added.

### P43 — a wait's return branches each name their lock
- Rule: Each return branch of a wait is its own row naming the lock it holds on return; a branch that returns unlocked is split at every shared read and write.
- Applies at: SKILL.md step 2
- Case (2026-11-06, CBRD-26425 atomic latch): `pgbuf_timed_sleep`'s TIMEDOUT branch was first modeled like its interrupt branch (one step under the entry lock, page_buffer.c:7397 re-locks). It does not re-lock: it reads `resume_status` at 7420, writes `NO_LATCH` at 7436 and unlocks a lock it does not hold at 7437. Split, it found hole A (CBRD-27739 cause A): a grant between the read and the write leaks fcnt (runtime: `__nusers = 4294967293`, assert at thread_entry.cpp:270).

### P44 — the scope is the change's diff
- Rule: Every function the change's diff touches, and every path between its acquire and release points, has a map row or a fault-table row with the code fact that excludes it; "not covered" is never a report line.
- Applies at: SKILL.md step 2
- Case (2026-11-06, CBRD-26425): the first report listed flush errors, the FLUSH waiter interrupt, the post-flush hand-off, invalidation and `pgbuf_search_hash_chain_no_bcb_lock` as not covered; the user asked why. Modeling them found hole E: `pgbuf_bcb_flush_with_wal` returns on a TDE or DWB error after `pgbuf_bcb_mark_is_flushing` (page_buffer.c:10986, 10998) with FLUSHING set, DIRTY cleared and no FLUSH waiter woken (TLC deadlock at depth 17; optdebug assert on the next unfix).

### P70 — a write into the cached plan outlives the execution
- Rule: A write into a cached plan (an XASL clone's flag or field, reused by later executions and other transactions) is shared state across executions: it gets a map row, the model runs one plan across at least two executions, and a fallback the change takes for one execution is checked not to carry into the next.
- Applies at: SKILL.md step 2
- Case (2026-11-09, PR #8438 H3 fix, `docs/tla/lazy-snapshot/stmt`): the map row for `CountConf` said "still not `COS_LOADED` -> a scan answers" and left out `agg_ptr->flag.agg_optimized = false` (`query_executor.c` `qexec_evaluate_aggregates_optimize`), a write into the cached XASL clone; every claim was about the answer, so TLC passed. The reviewer measured `SELECT COUNT(*)` 300x on 2M rows at 0.23 s on develop and 6.76 s on the PR with 4 writers on another table, still 6.70 s after the writers stopped, until a restart. develop already does this on one path: one REPEATABLE READ execution turns `agl: pk_t_id` into a heap scan for every later READ COMMITTED execution, in a new session too (optdebug develop `2d928e34b`, libcubrid `1e706e05…`).

### P24 — a guard and its access are two steps
- Rule: A guard and the shared-state access it protects are two steps when the code reads them apart; a mutant that survives the coarser step is the signal to split it.
- Applies at: SKILL.md step 2
- Case (2026-11-05, CBRD-27361 runtime-filter): `release_before_drain` survived while `WRow` checked the interrupt and probed the filter in one step; split into `WRow` and `WProbe` (`hjoin_rtf_pass`), the mutant reads the freed filter.

### P13 — when the snapshot is built
- Rule: Model when the MVCC snapshot is built relative to every set the scan collects at open (page bitmap, leaf chain, partition list), per isolation level: under READ COMMITTED the statement's first `logtb_get_mvcc_snapshot` builds it, which may run after open.
- Applies at: MODELING.md (Patterns)
- Case (2026-11-05, parallel scan heap H1): the leader collects the page bitmap at `manager::open`; the first worker's `scan_start_scan` builds the snapshot afterwards (`qexec_execute_query` builds it early only for REPEATABLE READ and up). A transaction committing in between has visible rows on pages outside the bitmap: TLC found it in 17 steps; the probe build returned 5004 rows (4 from a committed 2000-row transaction) in 5 of 5 runs.

### P14 — a VPID is not an identity
- Rule: A page identified by VPID alone is a reuse hole whenever it can be freed and reallocated during the protocol: model the free pool with reuse and check what the code compares besides the VPID (LSA, key range).
- Applies at: MODELING.md (Patterns)
- Case (2026-11-05, parallel scan index H2): descending `fix_prev_leaf` trusted `next_vpid == m_last_leaf_vpid`; the last leaf was merged into its left neighbour, freed and reused by that neighbour's split (`btree_alloc page=13742` right after `btree_merge right=13742`), and the scan skipped 136 keys. The model found it only once the free pool allowed reuse.

### P73 — an excluded field names the check that sees it
- Rule: A field or value class a model leaves out as "checked at runtime" names a runtime check that observes it; a diff of query output does not see a field no reader prints (precision, a compression cache, a length cache).
- Applies at: SKILL.md step 2
- Case (2026-11-09, PR 8398 review `GcBuf` → `GcFields`): GcBuf's MAP.md excluded the accumulator's value fields as "a decision table over value classes, checked at runtime" by a develop-vs-head output diff. A reviewer found `db_string_append` leaving precision `TP_FLOATING_PRECISION_VALUE` where develop leaves the maximum; csql prints no precision, so the diff could not see it. The field model `GcFields` (dev and pr side by side, every field) fails `AccEq` on `ea06eca48` (`mutant-float-prec`) and also found an `oracle_style_empty_string` + parallel scan + `SEPARATOR ''` heap abort (value2 made on heap 0 by the merge, freed by the coordinator).

## Step 3 — fault model

### P27 — a crash state is the code's write
- Rule: A crash fault's intermediate state is the exact page write of the function that performs the first half, read in that function, never the caller's comment.
- Applies at: SKILL.md step 3
- Case (2026-11-06, CBRD-24094 leaf swap): the first crash model followed `btree_replace_first_oid_with_ovfl_oid`'s comment ("swap ... with last object") and two injected crashes recovered cleanly. `btree_record_replace_object` re-inserts in OID order (`btree.c:38577`); with that write the model found H2 (an object above page 2's separator left in page 1), reproduced on the third run.

### P55 — the READ COMMITTED snapshot has a nested-statement fault
- Rule: A model that reads the READ COMMITTED statement snapshot has a fault row for a nested statement (SP SQL from the client) that invalidates and rebuilds it mid-statement (`network_sr.c` `logtb_invalidate_snapshot_data`).
- Applies at: SKILL.md step 3
- Case (2026-11-06, CBRD-27967 design): C2 ("one snapshot per statement") and a worker-side assert built on it were settled in grilling without that row; `select /*+ parallel(4) */ f27967(b.id) ...` (the function runs a SELECT) logged one `snapshot_built` per SP call after `L_open snapshot_valid=1`. The assert was dropped and C2/C4 scoped to statements without a nested statement.

## Step 4 — spec traps

### P5 — PlusCal `define` sees globals only
- Rule: `define` sees globals only: state the properties read is declared as a global variable.
- Applies at: SKILL.md step 4
- Case (2026-11-05, condvar-handoff): the witness predicate read the waiter's local `sleptOnce`; it became a global. (Also: a statement after `if ... goto` needs its own label.)

### P8 — environment processes must be able to end
- Rule: An environment process that loops (the OS, vacuum, a DML stream) must be able to end when the system ends, or TLC reports a false deadlock.
- Applies at: SKILL.md step 4
- Case (2026-11-05, condvar-handoff): the spurious-wakeup process `while TRUE do await sleeping` blocked forever after the waiter finished; "Deadlock reached" on the correct model. It now loops while the waiter is not Done.

### P25 — a loop bound every iteration advances
- Rule: A worker loop is bounded by a counter every iteration advances, never by one only some iterations advance, or TLC reports a false liveness counterexample.
- Applies at: SKILL.md step 4
- Case (2026-11-05, CBRD-27361 runtime-filter): a worker whose filter the sample took off counted no rows, so `rows[w] < MaxRows` never ended its loop and `LeaderFinishes` failed; a per-worker `left` budget fixed it.

### P19 — a cfg holds only simple values
- Rule: A cfg writes only simple values (naturals, strings, model values and sets of them); a negative number, a sequence or a function is a spec operator substituted in the cfg with `Name <- Op`.
- Applies at: SKILL.md step 4
- Case (2026-11-05, CBRD-27819 cmp-dispatch): `CONSTANTS Vals = {-10, -5, 0, 5, 10}` stopped every cfg with `ConfigFileException ... expecting }`; `MaxV = 10` with `Vals == {v \in -MaxV..MaxV : v % 5 = 0}` ran.
- Case (2026-11-09, lazy-snapshot): `Prog = <<"scan", "count">>` in a cfg stopped TLC at the cfg line; `Prog <- ProgScanCount` over a spec operator ran. The Toolbox's generated `MC.tla` uses the same substitution for every non-simple constant.

### P56 — overlapping CASE guards are a choice, not an order
- Rule: An ordered decision is an IF ... ELSE IF chain: a CASE whose guards can hold together is a CHOOSE, and TLC's first-match hides the arm Apalache or Isabelle may take.
- Applies at: SKILL.md step 4
- Case (2026-11-07, CBRD-27430 A3 `FoldBoundary`): `Exit` set the RR-lock mirror with `CASE e = "unilat" -> FALSE [] ... [] k = "hint" -> ~rrMirror`; TLC took the first true arm and every cfg passed, Apalache took the `hint` arm on a victim's exit and violated IndInv. (Specifying Systems 16.1.4 defines CASE as CHOOSE; TLC and TLAPS's SMT back end evaluate it as nested IF, Isabelle as CHOOSE — Merz, tlaplus group 2023.)

### P58 — a variable both assigned and UNCHANGED narrows an action
- Rule: A variable both assigned and listed in UNCHANGED silently narrows the action to where the two agree; after a bulk UNCHANGED edit, check each action that assigns the variable.
- Applies at: SKILL.md step 4
- Case (2026-11-09, map #618 B1a `Handoff`): `latest` added to every UNCHANGED list that named `mFreed` also landed in `SCrash`, which sets `latest' = 0`; the crash then fired only before the first HELLO, the main cfg passed 40 M states, coverage saw `SCrash` fire, and `mutant-cancel-by-db` ran 60 levels without a counterexample. A reachability probe of the counterexample's precondition came back unreachable and bisecting it pointed at `SCrash`.

### P60 — `(*` inside a comment opens a block comment
- Rule: Comments say `COUNT-star`, never `COUNT(*)`: `(*` opens a nested block comment and SANY reports the EOF far below it.
- Applies at: SKILL.md step 4
- Case (2026-11-09, lazy-snapshot): `COUNT(*)` in a header comment and a `\*` line gave "EOF reached, possibly open comment starting around line 468" on a 470-line module.

### P59 — Apalache: no `Seq(_)`, no variable-bounded range
- Rule: Apalache takes no `Seq(_)` and no `a..b` with a non-constant bound: a program is a function over `1..N` with `N` a constant, and a variable-bounded range is written as inequalities over a constant range.
- Applies at: SKILL.md step 4; INDUCTIVE.md
- Case (2026-11-09, lazy-snapshot): Apalache failed in turn on `Prog \in Seq(...)` in ASSUME, on `1..NOps` in ASSUME, on `0..curVer` in `I_hist`, and on an untyped six-boolean tuple in UNCHANGED, before reaching the inductive check. Apalache's known-issues page documents both limits with the same workarounds (`range(a,b) == {x \in Nmin..Nmax : a <= x /\ x <= b}`, `Gen(n)`).

### P47 — a declaration keyword carries its first name
- Rule: Every CONSTANTS and VARIABLES declaration carries its first name on the keyword's line, or `tools/tla/apalache-types` leaves the block untyped.
- Applies at: SKILL.md step 4; INDUCTIVE.md
- Case (2026-11-06, PR #8356 review `PartWalk`): a bare `VARIABLES` line with one commented name per line below failed Apalache with `Expected a type annotation for VARIABLE memoOn` although all 31 `apalache-type` lines were present.

### P72 — pass a name, not an expression, to a multi-reference parameter
- Rule: An operator whose body reads a parameter more than once takes a name, never a compound expression: the call site binds the expression in a LET and passes the name, because TLC's `-coverage` and Apalache's InlinePass copy the argument per reference, which multiplies through nested calls.
- Applies at: SKILL.md step 4
- Case (2026-11-09, PR 8398 review `GcFields`): `AppStep(..., CutV(x, res, adj, cnt), ...)` with its value parameter read in several branches ran TLC out of heap under `-coverage`, and Apalache's InlinePass ran out of 12 GB on the same calls; `Feed` binding `LET v == CutV(...) IN AppStep(..., v, v, ...)` fixed both.

## Step 5 — check, then hunt

### P12 — a dead expression needs a code reason or a larger bound
- Rule: A dead expression that maps to code is explained by the code fact that makes it unreachable (`file:line`), or the model grows until it fires; "not reached at these bounds" counts only after a larger bound leaves it dead too.
- Applies at: SKILL.md step 5
- Case (2026-11-05, parallel scan index): `D_saved` (resume from the saved leaf whose LSA is unchanged) never fired; the code reason is `btree.c:24083 btree_set_vpid_previous_vpid` (every split or merge that breaks the link rewrites the leaf's prev link, logged). The reroot branch stayed dead at `WriterOps` 3, 4 and 5; MAP.md names the layout it needs and the bound checked.

### P7 — a liveness counterexample through an unfair lock is an assumption question
- Rule: A liveness counterexample that loops through an unfair lock retake is a fairness assumption to state in MAP.md (and to put to the user when it is a design question), never a reason to weaken the property.
- Applies at: SKILL.md step 5; grill-with-tla
- Case (2026-11-05, condvar-handoff): endless spurious wakeups let the waiter retake the mutex each time, so the signaler's `await ~locked` was enabled only intermittently; the model bounds spurious wakeups (`MaxSpurious`) and MAP.md records the assumption.

### P10 — TLC names a broken refinement by its location
- Rule: A mutant that only the refinement mapping catches is expected as `\* expect: refinement`: TLC reports a broken refinement by location, not by the PROPERTY's name.
- Applies at: SKILL.md (directory); MODELING.md (Refinement); enforced by tla-check
- Case (2026-11-05, parallel scan heap): the `reread_page` mutant only breaks `AbsSpec`; TLC exited 13 with "Action property line 130, col 17 to line 130, col 29 of module PxHeapSnapshot is violated".

### P67 — an extended model re-reads the inherited environment
- Rule: A model extended from another inherits its environment assumptions (the snapshot's objects are never removed); when the extension adds a writer the assumption does not cover (physical deletes of an MVCC-disabled class), restate the assumption for that writer, and read a mutant that passes in under a thousand distinct states as vacuous before reporting it.
- Applies at: SKILL.md step 5
- Case (2026-11-09, PR 8431 review, `OvfScanStable` over `OvfScanResume`): `mutant-no-class-check` (compact an MVCC-disabled class's index) passed in 884 distinct states, because the inherited `Env` never removed an object the scan's snapshot saw, which no snapshot protects without MVCC. With physical deletes allowed the fixed variant showed a loss with no COMPACT step (a develop path), and the class claim was restated as `NoCompactNoMvcc`, which the mutant then violated.

### P68 — liveness in its own cfg
- Rule: A liveness PROPERTY runs in its own cfg at the smallest bound that still reaches the behavior, never beside the invariants and a refinement PROPERTY in the main cfg: the tableau check slows TLC by an order of magnitude or more.
- Applies at: SKILL.md step 4
- Case (2026-11-09, PR 8431 review): the main cfg with `PROPERTY ScanFinishes GuardRefined` ran at about 12 k states/min; without `ScanFinishes` (refinement kept, `VIEW` on) it ran at about 600 k states/min and finished 917,557 distinct states in 545 s, while the separate liveness cfg at the same bound reached 165 k distinct states in 13 minutes.

### P74 — a mutant survived by a second protection removes both
- Rule: A mutant that survives because a second code site restores the property removes both protections, and MAP.md names the second site at `file:line`: the claim then holds by either one.
- Applies at: SKILL.md step 5
- Case (2026-11-09, PR 8398 review `GcFields`): `mutant-compress-mid` (compress the accumulator between appends) passed in 56,113 distinct states: `db_string_fix_string_size` remakes the value through `qstr_make_typed_string`, and `db_make_db_char` resets `compressed_size` (dbtype_function.i:1109), so a stale cache never reaches the write. With `FixSize` also keeping the cache the mutant fails `NoStaleWrite`.

## Step 6 — inductive invariant

### P64 — the safety claims are conjuncts of IndInv
- Rule: Every safety property of the claims is a named conjunct of IndInv, so the inductive check reaches the claims without a proof.
- Applies at: SKILL.md step 6; INDUCTIVE.md
- Case (2026-11-09, rule review): with TLAPS on request only (P48) the link from IndInv to the claims rested on `InvSafe`, which no longer runs by default; Apalache's inductive recipe (IndInit / IndNext / IndProp) and Lamport's note both make `IndInv => Safety` its own condition, trivially met when Safety is a conjunct.

### P62 — the inductive check is iterated by group, from a well-formed IndInv
- Rule: The inductive check is iterated with `tools/tla/apalache-split`, one background job per group of conjuncts, from an IndInv whose first version already holds the well-formedness conjuncts (index fields in range, idle handlers reset, messages in their sender's shape, queues holding only what their phase allows); after a fix only the changed conjuncts rerun, and `tla-check`'s run is the record.
- Applies at: SKILL.md step 6; INDUCTIVE.md
- Case (2026-11-09, map #618 B1a `HandoffInd`): from 04:17 to 08:15 the check went through one single run and four rounds of 7–10 groups; each round was read only after its slowest group ended (48–59 min, while most ended in 7–25), every passed group was rerun, and the 4–7 CTIs per round were mostly well-formedness the first IndInv lacked (an idle handler holding a finished cancel's fields, a HELLO with stray fields, a RESYNC queued behind an unanswered HELLO, a SESSION_END for a session still registered).

### P63 — a conjunct too slow for one run is split by transition
- Rule: A conjunct too slow for one Apalache run is split by transition (`TF=` on apalache-split, `search.transitionFilter` on a part cfg), the parts together covering every transition; a part's timeout is never a pass.
- Applies at: SKILL.md step 6; INDUCTIVE.md
- Case (2026-11-09, map #618 B1a): `Inv22` and `Inv23` (nested quantifiers over wire-queue positions) each timed out at 10 800 s; Inv22's log showed 40 of 76 transitions checked, most in 2–5 min, one over 50 min. `TF='0->0|1->(0|1)'` checked 2 transitions in 81 s; the pair reran as 8 parallel parts (transition index mod 8).

### P6 — strengthen IndInv, never the spec
- Rule: A CTI from a state the system cannot reach means IndInv is too weak: strengthen IndInv, never the spec, and keep IndInv in the main cfg's INVARIANTS so TLC confirms the new conjunct on every reachable state.
- Applies at: SKILL.md step 6; INDUCTIVE.md
- Case (2026-11-05, condvar-handoff): the inductive cfg started from `pc[w] = "Done" /\ sleeping` and took `spuriousLeft` to -1; `sleeping => pc[Waiter] = "W_wake"` excluded it.
- Case (2026-11-06, parallel-hash-join): CTIs from a mutant-only label and from `pc[w] = "W_fl" /\ p[w] = NP`; IndInv drops the mutant-only labels and gains `pc[w] = "W_fl" => p[w] < NP`. (Konnov and Merz, tlaplus group 2025: a CTI's pre-state need not be reachable; an unreachable one means the invariant is too weak.)

### P42 — the symbolic inductive check comes first
- Rule: The inductive check is the Apalache cfg; a TLC inductive cfg is written only when IndInv's types do not fit Apalache.
- Applies at: SKILL.md (directory, step 6); INDUCTIVE.md
- Case (2026-11-06, parallel hash join): the 2-worker TLC inductive cfg enumerated 31 072 256 initial states in 15 min (26 under load); Apalache checks CondVarHandoff's IndInv for every `MaxSpurious \in Nat` in 5 s and rejects a weakened IndInv in the same time. With TLAPS on request only, the TLC cfg (up to 1 319 s) became the fallback.

### P52 — Apalache IndInv binds its variables and types its record and tuple operators
- Rule: An Apalache IndInv binds every variable before a conjunct reads it, every operator over a record or tuple carries a `\* @type:` line, and a pair of strings is a record, never a tuple.
- Applies at: INDUCTIVE.md
- Case (2026-11-06, PR #8378 review `StrShare`): `Annotation required ... ((a, a) => Seq(a))` at pair literals, `Cannot apply pr to the argument "cs"` until 22 `@type` lines over six `@typeAlias` records were added, and `borrows' is used before it is assigned` while IndInv read `\A b \in borrows` before binding it.
- Case (2026-11-06, CBRD-27967 `PxHeapRcSnapshot`): `IsInit(r) == r[2] <= NInit` failed Snowcat (`Cannot apply r to the argument 2`) because `r[2]` alone fits a tuple, a sequence and a function; `\* @type: (<<Str, Int>>) => Bool;` on each operator taking a row fixed it.

### P61 — Apalache leaves an out-of-domain application unconstrained
- Rule: Apalache leaves a function applied outside its domain unconstrained: IndInv bounds every field it uses as an index before a conjunct applies it.
- Applies at: INDUCTIVE.md
- Case (2026-11-09, map #618 B1a `HandoffInd`): CTIs at State0 that no action could build — `bCh[dch]` with `dch = 0`, `bCh[x.gen]` with `gen` out of range — until a `FieldsOK` conjunct bounded every index field. `Positions(q) == 1..Len(q)` was refused and `DOMAIN q` needed `\* @type: (Seq($msg)) => Set(Int);`.

### P23 — TLC's INIT IndInv must enumerate
- Rule: TLC enumerates `INIT IndInv` conjunct by conjunct: bind each variable just before the conjuncts that constrain it, write `x \in SUBSET W` (never `x \subseteq W`), keep the constants below the main cfg's, and when the enumeration still does not finish, probe with a randomized `IInit` (`RandomSubset`, `RandomSetOfSubsets`) whose pass is a probe, never the record.
- Applies at: INDUCTIVE.md (TLC fallback)
- Case (2026-11-05, CBRD-27361 page-batch-walk): `TypeOK`-first IndInv spent 7 min on 656 448 initial states and ran past 10 min; rewritten in binding order with the chunk slots zeroed outside a chunk and smaller constants, 4–6 s. RtfLifecycle's `bkeys \subseteq Keys` could not be enumerated at all. Lamport's note ("Using TLC to Check Inductive Invariance", 2018) prescribes the same ordering, the `SUBSET` form, and `Randomization` for the models enumeration cannot reach.

### P71 — Apalache draws record variables with Gen
- Rule: An Apalache IndInit draws a record-valued variable with `Gen` in a `<Module>Ind.tla` that EXTENDS the spec and `Apalache`, and TypeOK states its domain and field ranges as predicates (`DOMAIN dev = Nodes`, `x.p \in 1..MaxP`), never `dev \in [Nodes -> [p: Int, ...]]`: Int fields fail with "set map over an infinite set", and finite field ranges make Apalache enumerate the whole record set.
- Applies at: INDUCTIVE.md
- Case (2026-11-09, PR 8398 review `GcFields`): `dev \in [Nodes -> ValT]` with finite field ranges made Apalache enumerate 207,360,000 records; with `Int` fields it stopped on "Found a set map over an infinite set of CellTFrom(Int)". `GcFieldsInd.tla` with `IndInit == sepv = Gen(1) /\ dev = Gen(2) /\ pr = Gen(2) /\ outv = Gen(2) /\ IndInv` and `ValR` range predicates in TypeOK reached the inductive check (the B1a `HandoffInd` shape).

## Step 7 — counterexamples and holes

### P28 — a stop the capacity checks forbid is a model error
- Rule: A counterexample that stops the scan or buffer where the code's capacity checks forbid it is a model error: derive the stop condition from the code's arithmetic first.
- Applies at: SKILL.md step 7
- Case (2026-11-06, CBRD-27401 scan resume): the model let a key-start iteration stop with no chain object accepted and TLC found a lost row without COMPACT; the runtime attempt stopped before the key (`n_before=0`), because the key-start check reserves the leaf objects plus one overflow page (`btree.c:30774`, `btree.c:29694`).

### P9 — a hole found in the code stays a failing pass cfg
- Rule: A hole confirmed in the code stays a failing `\* expect: pass` cfg, so the directory reports `RESULT: FAILED` until the code is fixed; the candidate fix gets its own cfg, and the code cfg's expectation is never flipped.
- Applies at: SKILL.md step 7; enforced by tla-check (only mutant and witness cfgs may expect an error)
- Case (2026-11-05, parallel scan): `heap/PxHeapScan.cfg` fails `SameAsSnapshot` (H1) and `index/PxIndexLeafDispatch.desc.cfg` fails `StableOnce` (H2); the fixes are `fix-snapshot-before-open.cfg` and `desc-fix.cfg`.

### P17 — a runtime reproduction logs the interleaving
- Rule: A hole's runtime reproduction logs the structural events of the counterexample (TLATRACE at the snapshot, alloc, free and fix sites), so a run shows the interleaving happened and not only a wrong answer.
- Applies at: SKILL.md step 7; TRACE.md
- Case (2026-11-05, parallel scan index H2): of three runs with the same delay one returned a wrong sum; its TLATRACE lines showed `btree_merge left=13744 right=13742`, `btree_alloc page=13742`, `link_trusted last=changed`; the other two runs' layouts never merged the last leaf. statdump counters stayed 0 throughout.
- Case (2026-11-07, CBRD-27430 A5): a SHOW after another session's teardown destroyed the heap returned the right rows on the pre-fix build (freed lea memory stayed readable); a probe logging `init heap=`, `destroy heap=`, `read heap=` with the thread showed four reads after the destroy. A plan-cache key hole showed no wrong answer with `CAST(... AS DATETIMETZ)` (computed per run) but did with the literal `DATETIMETZ '...'` folded at compile.

### P26 — a narrow window waits for its precondition
- Rule: A hole whose window is a few instructions wide is reproduced by an injection at the window that waits, polling the shared state, until the counterexample's precondition holds, while the load that creates the precondition runs for the whole bound.
- Applies at: TRACE.md (Reproducing a hole)
- Case (2026-11-05, CBRD-26425 H1): `pgbuf_lockfree_fix_ro` held its window until the BCB held another page whose latch word equalled the loaded one; with 8 scans of 0.3 s the churn ended long before the page aged out (`matched=0` after 30 s); with two sessions churning for the whole bound it matched in 2 s and the caller asserted in `pgbuf_check_page_ptype`.

### P54 — an env-gated delay holds the racing session too
- Rule: An env-gated delay at a shared step holds the racing session too: its statements carry a hint that keeps them off the delayed path, and both sessions' elapsed times are read before a run counts.
- Applies at: TRACE.md (Reproducing a hole)
- Case (2026-11-06, CBRD-27967): `CUBRID_TLA_PX_OPEN_DELAY_MS=5000` after `scan_open_parallel_heap_scan`; session B's `insert into t select * from src` was itself a parallel heap scan, waited the same 5 s and committed after A ended (`5000 0 1` three times). With `/*+ no_parallel_scan */` in B: `5003 4 0` 3/3.

### P57 — an injected fault lands on the first matching step
- Rule: An injected fault lands on the first matching step, often a cache fill the model does not name: warm the caches before arming, and rerun the injection with the modeled reaction switched off before blaming the modeled step for a crash.
- Applies at: TRACE.md (Reproducing a hole)
- Case (2026-11-09, map #618 A8 `FoldOom`): failing the first client-half AREA allocation hit `tf_disk_to_class` decoding `_db_synonym` and the server asserted in `or_get_int`; the same injection with the callback disabled crashed on the same stack (the decoder ignores the failed allocation — a develop defect). With the class cache warmed by a PRE statement the failure landed in the compile's domain allocation and gave the modeled abort.

## Step 8 — trace validation

### P50 — trace validation is part of every model of code
- Rule: Every model of code that exists is tied to it by trace validation: an instrumented build of the exact sha records runs the trace spec accepts and a corrupted run it refuses; only a design with no implementation or a pattern example carries `trace-exempt: <reason>` in MAP.md.
- Applies at: SKILL.md step 8; TRACE.md; enforced by tla-check
- Case (2026-11-06, PR #8356 CBRD-27866): the per-row partition walk touched a lock only through a re-granted IS_LOCK, yet four recorded runs found three model errors (a re-executed subquery builds a new memo, ANTI re-entered after its row, the first outer row rewound twice) and one behavior the PR did not state (an out-of-range range key walks every partition). The user: "trace validation은 필수로 해서 커밋+푸쉬좀". ADR 0047.

### P32 — emit before you start a thread
- Rule: An event for a step that starts another thread (`push_task`, `pthread_create`, a signal) is emitted before that start, or the started thread's first event lands ahead of it.
- Applies at: TRACE.md
- Case (2026-11-06, parallel sort merge queue): `MDispatch` logged after `try_dispatch` returned; in one run the task's `TMerge` came first and the trace could not be accepted.

### P51 — a trace spec builds its candidates from the event
- Rule: A trace spec builds the values an event leaves open from the event's own fields, never by filtering the spec's whole input set per event: under `-coverage` such a filter advances about one event a minute.
- Applies at: TRACE.md
- Case (2026-11-06, PR #8378 review `str-share`): filtering ~1 800 `CharVals` per Assign and re-reading `TraceLog[i + 1]` in every conjunct reached depth 53 in 4 min over a 600-event run; with `TCols(e)` / `TVals(e)` built from the event (~100 candidates) and `LET e == TraceLog[i + 1]`, the run was accepted in 405 s.

### P53 — trace cfgs run without the deadlock check
- Rule: Every trace cfg runs with `CHECK_DEADLOCK FALSE` (`deadlock-off: trace`): a branch of the unlogged nondeterminism that dead-ends is not a deadlock while another branch consumes the run, and the first unconsumed event is read from TLC's depth line.
- Applies at: TRACE.md
- Case (2026-11-06, PR #8364 review `bv-last-row`): six booleans chosen in `Init` and logged only by their effects; all five `witness-trace-*` cfgs failed `got=[deadlock] depth=1` on initial states the first event contradicts. With the deadlock check off each run was accepted and the three corrupted runs still refused. The 2024 trace-validation paper gives the general reason: a state with no matching successor may still be matched elsewhere, so the constrained spec is never checked for deadlock.

### P75 — truncate a live trace file, keep key dumps off a checkdb
- Rule: A trace file the server holds open is truncated (`: > trace.log`), never deleted, and a per-key dump switch (`CUBRID_TLA_DUMP_KEY`) is off on a server that a checkdb or another whole-index pass reads: a deleted file keeps taking the events unseen, and a dump per scanned key fills the disk.
- Applies at: TRACE.md
- Case (2026-11-09, PR 8432 review `leafswap-route`): `rm -f trace.log` before a repro left `cub_server` writing to the unlinked inode, so the script's wait for a `Swap` event timed out on an empty file until the server restarted; later `cubrid checkdb -C --check-btree-entries` against a server started with `CUBRID_TLA_DUMP_KEY=1` dumped every key it scanned (1.9 GB in a few minutes) until it was stopped; restarted without the dump variable and run with `-i` naming `dba.t5`, checkdb finished at once.

## Step 10 — report

### P45 — verified means run, not written
- Rule: A model is a result only once `tools/tla/tla-check` has run it to `RESULT: OK`; a spec written but not run, or run without a proof the user asked for, is reported as 미완, never as verified.
- Applies at: SKILL.md step 10; cubrid-pr-review Step 3d
- Case (2026-11-06, PR #8356 review): the cfgs were written and the first TLC passes in when the user asked "tla+ 모델링만 하는게 아니라 그걸로 검증까지해야하는건 알고있지?"

### P16 — what a TLAPS proof covers
- Rule: A TLAPS proof of an abstract spec reaches the code-level model only through a refinement PROPERTY TLC checks inside its bounds; the report says per claim what it has.
- Applies at: SKILL.md step 10; PROOFS.md
- Case (2026-11-05, parallel scan): heap C1 is proved on `PxHeapSnapshot` and tied to the latch-level `PxHeapScan` by TLC refinement in 2- and 3-worker cfgs; index C1 and every liveness claim are TLC only.

## TLAPS — only on an explicit request (P48)

### P2 — the temporal conclusion goes through LS4
- Rule: `PTL` steps prove through LS4: keep the INV1 premises as their own theorems and conclude `Spec => []IndInv` from them `BY InitInv, StepInv, PTL DEF Spec`.
- Applies at: PROOFS.md
- Case (2026-11-05): on tlapm 1.4.5 (nixpkgs, no LS4) the QED failed with `Executable "ls4" not found`; on 1.6.0-pre re-linked by nix (`tools/tla/tlapm-next.nix`) it proved. ADR 0045.

### P3 — untyped logic: state the value, and a boolean conjunct is an iff
- Rule: A step states the value the action assigns (`x' = FALSE`, never `~x'`), and a conjunct tying a boolean to a predicate is written `x \in BOOLEAN /\ (x <=> P)`, never `x = (P)`.
- Applies at: PROOFS.md
- Case (2026-11-05, condvar-handoff): `BoolOK'` would not prove from `~sleeping'`; `sleeping' = FALSE` proved it.
- Case (2026-11-06, parallel-hash-join, formerly P34): `freed = (pc[Leader] \in {"L_fallback", "Done"})` failed in InitInv at every stretch although both sides were facts of the step; `freed \in BOOLEAN /\ (freed <=> ...)` proved.

### P4 — SMT cannot mix boolean typing and integers
- Rule: When a typing step times out, split `TypeOK` into a boolean part and an integer part and prove them in separate steps.
- Applies at: PROOFS.md
- Case (2026-11-05, CBRD-27215/27361, condvar-handoff, tlapm 1.4.5): `TBool'` failed until it stood apart from `TRest`; the SMT input encoded `locked = FALSE` as `(not (boolify locked))` with no axiom back to `tla__BOOLEAN`. On 1.6.0-pre the same goal proved at once, so the split is the fallback for a timeout, not a step every TypeOK takes.

### P15 — prove a large IndInv conjunct by conjunct
- Rule: Each conjunct of IndInv beyond `TypeOK` is named (`R_x == ...`) and proved in its own step; one step over the whole conjunction times out.
- Applies at: PROOFS.md
- Case (2026-11-05, parallel scan heap): `RestInv'` as one goal timed out for `ReadPage` and `VacuumPage`; fourteen named conjuncts proved one by one, 278/278.

### P20 — decision tables: literal chains, no poisoned facts
- Rule: A decision table is proved per input as a chain of equalities to record literals (generated), with flags as 0/1 integers, records built instead of `EXCEPT`, and each cited fact free of `CASE`, `\E` and boolean-valued `IF`.
- Applies at: PROOFS.md
- Case (2026-11-05, CBRD-27819 cmp-dispatch): one obligation per (client, site, type pair) with the decision unfolded timed out (34/843 in 1800 s); `BY <2>1` failed while `<2>1` held `inst' = CASE ...`. With 0/1 flags, fresh records and a generated chain, 7652/7652 in 866 s.

### P21 — higher-order library theorems need Isa
- Rule: A library theorem over an operator parameter (`NatInduction`, `SmallestNatural`) applies only through Isabelle: `DEFINE` the predicate, `HIDE DEF` it, cite the theorem with `Isa`.
- Applies at: PROOFS.md
- Case (2026-11-05, tlapm 1.6.0-pre smoke): `\E m \in Nat : Q(m) /\ \A j \in 0 .. m-1 : ~Q(j)` with `Q` hidden proved `BY <2>1, SmallestNatural, Isa`; cited without the hidden predicate it failed. (On 1.4.5 without Isabelle the spec had to be rewritten with `\E s \in S : Least(s, S)`.)

### P22 — a hidden definition under a prime needs its own equality
- Rule: Under `HIDE DEF`, state the equality for the primed term exactly as the goal writes it (`HasAns(cur)' = HasAns(cur)`).
- Applies at: PROOFS.md
- Case (2026-11-05, CBRD-27361 page-batch-walk): `\A p, s : Ans(p, s)' = Ans(p, s)` did not prove `IFront'` for the `Env` and `UNCHANGED` cases; `HasAns(cur)' = HasAns(cur)` stated outright did.

### P31 — split a large proof into modules
- Rule: A proof past about a thousand obligations is split into modules that `EXTEND` a shared base module, each under the 1800 s limit, with the INV1 theorems in the top module.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel sort merge queue): one module of 2850 obligations stopped at 1931 proved after 1800 s although every lemma had proved in partial runs; tlapm proves only the module it is given, so `_base`, `_main`, `_task`, `_disp`, `_tc` and the top module each fit.

### P33 — prove a large action through its branch effects
- Rule: A branching action is proved through an effect step: one `CASE` per branch condition, then each IndInv part from one branch's conjunction with the action left unexpanded.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel-hash-join): with `DEF W_claim` (six branches) unfolded in every part, `IDisp'`, `ICnt'`, `ILocal'` timed out at `--stretch 6`; one `CASE` per branch condition (`failed'[self] = "err"` tells `either` branches apart) proved in one test-module run.

### P35 — parenthesize
- Rule: Parenthesize every primed right side (`uaf' = (uaf \/ freed)`), every `a + b - c` (`-` binds tighter than `+`), and every quantifier followed by more conjuncts on its line.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel-hash-join): `uaf' = uaf \/ freed` parses as `(uaf' = uaf) \/ freed`, and an `IF ... THEN ... ELSE` right side swallowed the `/\ UNCHANGED` after it; every effect step failed until parenthesized.
- Case (2026-11-06, parallel sort merge queue, formerly P30): `Cardinality(Q') = qn + 1 - k` is `qn + (1 - k)` (`-` precedence 11, `+` 10) and did not match the fact `(qn + 1) - k`.
- Case (2026-11-06, parallel sort merge queue, formerly P40): `/\ \A t \in Tasks : tpc[t] \in {...} /\ Q = {} /\ sleeping = FALSE` put `Q = {}` inside the `\A`; a later `AfterStage' => Q' = {}` failed in every prover.

### P36 — Assm states what model values give TLC
- Rule: `Assm` states what a TLC model value gives for free: a constant set is nonempty, and a sentinel is not one of its members.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel-hash-join): `(pc[Leader] = "L_push" <=> pushed # Workers)` is false for `Workers = {}`, and `w # owner => mb[w] \in {-1, 0}` with `owner = "none"` needs `"none" \notin Workers`; both held in TLC only because the cfg's workers are model values.

### P37 — iterate a failing step in a test module
- Rule: A failing obligation is fixed in a test module that `EXTEND`s the spec and states only that step, then the whole proof reruns once.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel-hash-join): three whole-module reruns of ~1850 obligations ran 3000, 3000 and 2028 s (timeouts, another session's stop); the `W_claim` effect proved in one run of `T EXTENDS PxHashJoin` holding that step alone. (Merz, tlaplus group: long batch proofs flake on timeout handling in parallel checking.)

### P38 — an integer comparison needs its type in scope
- Rule: A step comparing a variable with `<` or `<=` has that variable's type in scope (`USE np \in 0..MaxP` per lemma); structural assumptions stay out of the module's global `USE`.
- Applies at: PROOFS.md
- Case (2026-11-06, CBRD-24094 `OvfOrder_proofs`): stuck at 858/930 even at `--stretch 12`; `r < np BY r1 = r, r2 <= np` timed out because `np`'s type lived in the folded `IndInv`, and a global `USE AssmO` stalled Z3 on unrelated steps. Per-lemma type facts and `AssmO` cited only where needed: 1257/1257 in 54 s.

### P39 — a large proof module needs `--workers`
- Rule: `tools/tla/tla-check --workers` is sized to the free cores for a module of more than a few hundred obligations, and a module that needs longer carries a `\* timeout: <seconds>` line.
- Applies at: PROOFS.md
- Case (2026-11-06, CBRD-27361 page-batch-walk): `PageBatchWalk_proofs` (3673 obligations) at the default 4 threads was 26 min into its limit when stopped; at 16 threads it had taken 31 min; at `--workers 24` under load average 93 the 1800 s limit cut it at 1737 proved, so the file carries `\* timeout: 7200`.

### P49 — a crashed tlapm run proves nothing
- Rule: A tlapm run ending `rc=3` with obligations "to be proved" crashed: read the `Error:` line; a double prime (`Exp(outer'[x])'`) and `Lemma!n` over an ASSUME/PROVE lemma crash 1.6.
- Applies at: PROOFS.md
- Case (2026-11-06, PR #8356 `PartWalk_proofs`): a `SUFFICES` with `Exp(outer'[x])'` turned a 439-obligation run into `rc=3` (`e_levels.ml line 502 Assertion failed`); `(Exp(outer[x]))'` proved all 439. `ORFacts!1` stopped parsing with `Cannot resolve !4`; an operator for the lemma's conclusion cited with `DEF` proved 735/735.

### P65 — a proof starts after the fix is decided, scoped to the changed claims
- Rule: A proof starts only after the fix is decided, and for a model past about thirty variables it proves the claims the change touches on an abstract spec that the code-level model refines by a TLC PROPERTY, not every claim on the whole model.
- Applies at: PROOFS.md
- Case (2026-11-09, lazy-snapshot `LazySnapshot`: 51 variables, 36 IndInv conjuncts, 35 actions): the proof of a candidate H3 fix (statistics stored in each history entry) reached 4716/4993 and was dropped when the fix became a version check; the decided fix's module grew to 15337 obligations, one full run took over an hour at load average 96, its first run failed 161 writer-action steps, and the user stopped the proof, leaving TLC, Apalache and trace validation as the record. Only C3 changed; the same model's px-heap-coverage sibling (about 20 variables) proved 1613/1613 in 16 minutes.

### P66 — a generated per-action proof cites only what the step reads
- Rule: A generated per-action proof states each changed variable's type and the action's effect facts as numbered steps and cites only those the step reads, never `DEF IndInv, TypeOK` with every conjunct, and is tried on a few lemmas (an action that writes shared history, the fix's own actions) before the whole module runs.
- Applies at: PROOFS.md
- Case (2026-11-09, lazy-snapshot): a generator citing the whole IndInv and TypeOK in every step failed 1119 of 4692 obligations on SMT internal timeouts in a 99-minute run, and its frame steps without `IndInv` in the DEF list failed even for conjuncts the action leaves alone; with per-variable type steps and narrow citation a 9-lemma trial proved 4630/4656, then 4097/4103 after hand case splits (the reader's entry is or is not the one a commit starts; history monotonicity at `v2 = curVer + 1`).

## Folded

- P30 (`-` binds tighter than `+`) and P40 (a quantifier swallows later conjuncts) → P35.
- P34 (a boolean conjunct is an iff) → P3.

## Sources outside this repo

- Lamport, "Using TLC to Check Inductive Invariance" (2018): the three INV1 conditions, conjunct ordering for `INIT Inv`, `Randomization` — P23, P64.
- Apalache docs, "Running the Tool" (IndInit / IndNext / IndProp, `--cinit`), "Tuning" (`search.transitionFilter`, `search.invariantFilter`, `search.invariant.mode`, `z3.sat.threads`), "Known issues" (`a..b`, `Seq`) — P59, P63, P64.
- Cirstea, Kuppe, Loillier, Merz, "Validating Traces of Distributed Programs Against TLA+ Specifications" (2024) and `tlaplus/Examples` `EWD998ChanTrace` — TRACE.md shape, P51, P53.
- tlaplus Google group: CASE semantics (Merz, 2023) — P56; CTI pre-states (Konnov, Merz, 2025) — P6; reproducible TLAPS proofs (backend + timeout pinning) — PROOFS.md.
