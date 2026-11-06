# PITFALLS — the rules in SKILL.md and the runs that produced them

Each `P<n>` is one rule. The **Rule** line is the exact sentence SKILL.md (or the reference file
named in **Applies at**) carries; keep the two byte-identical (`tools/skills/check-pitfalls-drift.sh
.agents/skills/cubrid-tla`). **Case** is the run or user correction that paid for the rule.

Adding a case: one `Case (YYYY-MM-DD):` line under the rule it confirms, in the session that hit it.
A new rule only when no rule fits — then add the sentence to the skill in the same commit.

## Toolchain

### P1 — tools are judged by tla-check, never by their exit status
- Rule: TLC and tlapm run only through `tools/tla/tla-check`, whose verdict is read per cfg and per obligation, never from a tool's exit status.
- Applies at: SKILL.md Toolchain; PROOFS.md
- Case (2026-11-05, skill build): the nix JDK 21 behind `tlc` died with `UnsatisfiedLinkError ... /usr/lib/jvm/java-1.8.0-openjdk/jre/lib/amd64/libnet.so` because CUBRID shells export `LD_LIBRARY_PATH` with Java 8's libs; `env -u LD_LIBRARY_PATH` through the `~/.local/bin/env` shim then printed nothing and exited 0. `tla-check` runs Java and tlapm through `/usr/bin/env -u LD_LIBRARY_PATH -u JAVA_HOME -u CLASSPATH -u JAVA_TOOL_OPTIONS`.
- Case (2026-11-05, px-error-handoff): `tlapm --toolbox 0 0` exited 0 while two obligations had `@!!status:failed` from every prover. `tla-check` now takes each obligation's last settled status and requires proved = `@!!count`.

### P2 — the temporal conclusion goes through LS4
- Rule: `PTL` steps prove through LS4 (tlapm 1.6.0-pre): keep the INV1 premises as their own theorems and conclude `Spec => []IndInv` from them `BY InitInv, StepInv, PTL DEF Spec`, so a temporal failure is told apart from a step failure.
- Applies at: PROOFS.md
- Case (2026-11-05, tlapm 1.6.0-pre smoke): with the release build re-linked by nix (`tools/tla/tlapm-next.nix`; the binaries need glibc 2.38, the host has 2.28), `THEOREM Spec => []Inv` `BY <1>1, <1>2, PTL DEF Spec` proved through LS4.
- Case (2026-11-05, skill build, tlapm 1.4.5 — superseded): the textbook `<1>. QED BY <1>1, <1>2, <1>3, PTL DEF Spec` failed with `Executable "ls4" not found`; nixpkgs ships tlaps 1.4.5 without LS4 or an Isabelle/TLA+ heap, and source builds are off limits on this host. `RuleINV1` from `TLAPS.tla` could not be used either (`Operator "RuleINV1" not found`, a crash in `e_anon.ml`).

### P3 — untyped logic: a negation is not a type
- Rule: state the value the action assigns (`x' = FALSE`)
- Applies at: PROOFS.md (table)
- Case (2026-11-05, condvar-handoff): `BoolOK'` would not prove from a step that said `~sleeping'`; the action assigns `sleeping' = FALSE`, and once the step said so the case proved (100/100).

### P4 — SMT cannot mix boolean typing and integers
- Rule: when such a step times out, split `TypeOK` into a boolean part and an integer part and prove them in separate steps
- Applies at: PROOFS.md (table)
- Case (2026-11-05, CBRD-27215/27361 expr-prog-exec, page-batch-walk): `TBool'` failed in ExprProgExec until it stood apart from `TRest`, and in PageBatchWalk the steps for `IFix'`/`IChunk'`/`IPhase'` kept failing (13 of 2749 obligations, `--stretch 5`) while `fixed`/`more`/`learned \in BOOLEAN` sat in those conjuncts; split out as `IFixB`/`IChunkB`/`IPhaseB`.
- Case (2026-11-05, condvar-handoff): `ASSUME spuriousLeft = MaxSpurious, MaxSpurious \in Nat, locked = FALSE PROVE spuriousLeft \in 0..MaxSpurious /\ locked \in BOOLEAN` timed out in Z3 (30 s with `--stretch 6`) and Zenon exhausted its search; the captured SMT input encoded `locked = FALSE` as `(not (boolify locked))` with no axiom back to `tla__BOOLEAN`. Each half proved alone.
- Case (2026-11-06, rule review, tlapm 1.6.0-pre): the condvar goal above, verbatim, proved at once (`probe16`, 5 s for four goals); both cases above ran on 1.4.5, so the split is now the fallback for a timeout, not a step every TypeOK takes.

### P18 — tla-check is replaced, never rewritten in place
- Rule: Change `tools/tla/tla-check` by writing a new file and renaming it over the old one: bash reads a running script from its open file, so an in-place rewrite corrupts the runs other sessions have in flight.
- Applies at: SKILL.md Toolchain
- Case (2026-11-05, parallel scan): `tools/tla/tla-check` was edited in place (the `expect: refinement` and P9 checks) while this session's heap run and other sessions' TLAPS runs were executing it; a running bash re-reads its script at the byte offset it left, so a size change can run a partial line. Later edits write a new file and `mv` it over.

## Modeling

### P5 — PlusCal `define` sees globals only
- Rule: `define` cannot see process-local `variables`; declare state the properties read as globals
- Applies at: MODELING.md (Atomicity)
- Case (2026-11-05, condvar-handoff): the first translation stopped at "Missing label" (a statement after an `if ... goto` needs its own label), and the witness predicate read the waiter's local `sleptOnce`, which a `define` cannot reference; `sleptOnce` became a global.

### P6 — strengthen IndInv, never the spec
- Rule: An inductive-cfg counterexample from a state the system cannot reach means IndInv is too weak: strengthen IndInv, never the spec, and keep IndInv in the main cfg's INVARIANTS so TLC confirms the strengthened conjunct on every reachable state.
- Applies at: SKILL.md step 6; PROOFS.md
- Case (2026-11-05, condvar-handoff): the inductive cfg started from `pc[w] = "Done" /\ sleeping` and took `spuriousLeft` to -1. No run reaches a finished waiter that sleeps; the conjunct `sleeping => pc[Waiter] = "W_wake"` excluded it and the main cfg now checks IndInv on all 92 reachable states.
- Case (2026-11-06, parallel-hash-join): the inductive cfg started from a worker at the mutant-only label `W_cas_write` and from `pc[w] = "W_fl" /\ p[w] = NP`; no run of the correct variant reaches either, so IndInv's worker labels drop the three mutant-only labels and gain `pc[w] = "W_fl" => p[w] < NP`.

### P7 — a liveness counterexample through an unfair lock is an assumption question
- Rule: A liveness counterexample in the correct model that loops through an unfair lock retake is a fairness assumption to state in MAP.md (and to put to the user when it is a design question), never a reason to weaken the property.
- Applies at: SKILL.md step 5
- Case (2026-11-05, condvar-handoff): `WaiterFinishes` failed on the correct model: endless spurious wakeups let the waiter retake the mutex each time, so the signaler's `await ~locked` was enabled only intermittently and weak fairness did not force it. The model bounds spurious wakeups (`MaxSpurious`) and MAP.md records the assumption.

### P8 — environment processes must be able to end
- Rule: An environment process that loops (an OS, vacuum, a DML stream) must be able to end when the system ends, or TLC reports a false deadlock.
- Applies at: SKILL.md step 4
- Case (2026-11-05, condvar-handoff): the spurious-wakeup process `while TRUE do await sleeping` blocked forever after the waiter finished, so `Terminating` was never enabled and the correct model reported "Deadlock reached". It now loops while the waiter is not Done.

## Checking, proving and reproducing

### P9 — a hole found in the code stays a failing pass cfg
- Rule: A hole confirmed in the code stays a failing `\* expect: pass` cfg of the code as it stands, so the directory reports `RESULT: FAILED` until the code is fixed; the candidate fix gets its own pass cfg, and the code cfg's expectation is never flipped to make the directory pass.
- Applies at: SKILL.md step 7; enforced by `tools/tla/tla-check` (only mutant and witness cfgs may expect an error)
- Case (2026-11-05, parallel scan): `docs/tla/parallel-scan/heap/PxHeapScan.cfg` (READ COMMITTED, the code) fails `SameAsSnapshot` (H1) and `index/PxIndexLeafDispatch.desc.cfg` fails `StableOnce` (H2); both stay `expect: pass`, the candidate fixes are `fix-snapshot-before-open.cfg` and `desc-fix.cfg`, and both directories report `RESULT: FAILED` until the engine is fixed.

### P10 — TLC names a broken refinement by its location
- Rule: A mutant that only the refinement mapping catches is expected as `\* expect: refinement`: TLC reports a broken refinement as "Action property line N ... of module <Abstract> is violated", by location, not by the PROPERTY's name.
- Applies at: SKILL.md "The directory a verified model needs"; MODELING.md (Refinement)
- Case (2026-11-05, parallel scan heap): the `reread_page` mutant only breaks `AbsSpec`; TLC exited 13 with "Action property line 130, col 17 to line 130, col 29 of module PxHeapSnapshot is violated", which `tla-check` read as `violation line` until it learned `expect: refinement`.

### P11 — every exit path of the protocol is an action
- Rule: Before the model is final, list the callers of every protocol entry point in the mapped code (code-index `callers`) and give each exit path (LIMIT, error, interrupt, reset, the end of a range) an action or a fault-table row saying why it is not modeled.
- Applies at: SKILL.md step 2
- Case (2026-11-05, parallel scan index): the dispatcher model passed every cfg before a re-read of `px_scan_index_leaf_page_dispatcher.cpp` found `release_leaf` (5 callers: LIMIT, reset, overflow drain) and `signal_chain_ended` (6 call sites), which end the chain while a worker holds the frontier. `W_stop` and the mutant `stop_keeps_chain` (`NoFreedFix` violated) were added; the abstract spec gained `EndChain` and its TLAPS proof a lemma.

### P12 — a dead expression needs a code reason or a larger bound
- Rule: A dead expression that maps to code is explained by the code fact that makes it unreachable (`file:line`), or the model grows until it fires; "not reached at these bounds" counts only after a larger bound leaves it dead too, and MAP.md names that bound.
- Applies at: SKILL.md step 5
- Case (2026-11-05, parallel scan index): `D_saved` (resume from the saved leaf whose LSA is unchanged) never fired. The reason is in the code: every split or merge that breaks the left leaf's link to the last leaf rewrites that leaf's prev link (`btree.c:24083 btree_set_vpid_previous_vpid`, logged), so its LSA always changes. The reroot-ends-the-chain branch stayed dead with `WriterOps` 3, 4 and 5; MAP.md names the layout it needs and the bound checked.

### P13 — when the snapshot is built
- Rule: Model when the MVCC snapshot is built relative to every set the scan collects at open (the page bitmap, the leaf chain, the partition list), per isolation level: under READ COMMITTED the statement's first `logtb_get_mvcc_snapshot` builds it, which may run after open.
- Applies at: MODELING.md (Patterns)
- Case (2026-11-05, parallel scan heap H1): under READ COMMITTED the leader collects the page bitmap at `manager::open` and the first worker's `scan_start_scan` builds the snapshot afterwards (`qexec_execute_query` builds it early only for REPEATABLE READ and up). A transaction committing in between has rows on a page outside the bitmap that its snapshot can see: TLC found it in 17 steps; the probe build returned 5004 rows, 4 of them from a committed 2000-row transaction, in 5 of 5 runs.

### P14 — a VPID is not an identity
- Rule: A check that a page is the same page by VPID alone is a reuse hole whenever the page can be freed and reallocated during the protocol: model the free pool with reuse (`file_alloc` takes the lowest free page) and check what the code compares besides the VPID (LSA, key range).
- Applies at: MODELING.md (Patterns)
- Case (2026-11-05, parallel scan index H2): descending `fix_prev_leaf` trusts `next_vpid == m_last_leaf_vpid`. The last leaf handed out was merged into its left neighbour, freed, and reused by that neighbour's split (`btree_alloc page=13742` right after `btree_merge right=13742`); the scan skipped the 136 keys moved there. The model found it only after the free pool allowed reuse.

### P15 — prove a large IndInv conjunct by conjunct
- Rule: Name each conjunct of IndInv beyond `TypeOK` (`R_x == ...`), prove each in its own step with `TypeOK`, its parts and every `R_` in the DEF list, and join them in the QED; one step over the whole conjunction times out.
- Applies at: PROOFS.md
- Case (2026-11-05, parallel scan heap): `PxHeapSnapshot_proofs.tla` timed out on `RestInv'` as one goal for `ReadPage` and `VacuumPage`; with the fourteen named conjuncts `R_early` .. `R_done` proved one by one and `TypeOK`'s parts in every DEF list, all 278 obligations proved.

### P16 — what a TLAPS proof covers
- Rule: A TLAPS proof of an abstract spec counts for the code-level model only through a refinement PROPERTY that TLC checks on that model's cfgs, inside their bounds; the report says per claim which it has: TLAPS on the abstract spec plus TLC refinement, TLC only, or neither.
- Applies at: SKILL.md step 10
- Case (2026-11-05, parallel scan): heap C1 is TLAPS-proved on `PxHeapSnapshot` (early snapshot) and tied to the latch-level `PxHeapScan` by TLC refinement in 2- and 3-worker cfgs; index C3 is TLAPS-proved on `PxIndexFrontier` and tied by TLC refinement to the ascending dispatcher; index C1 and every liveness claim are TLC only.

### P17 — a runtime reproduction logs the interleaving
- Rule: A hole's runtime reproduction logs the structural events of the counterexample (TLATRACE at the snapshot, alloc, free and fix sites the trace passes through), so a run shows the interleaving happened and not only a wrong answer; a run without those events counts neither for nor against the hole.
- Applies at: TRACE.md (Reproducing a hole); SKILL.md step 7
- Case (2026-11-05, parallel scan index H2): of three runs with the same delay, one returned 474416 / 1125355077360 instead of 474552 / 1126000376280; its TLATRACE lines showed `btree_merge left=13744 right=13742`, `btree_alloc page=13742`, `link_trusted last=changed`, while the other two runs' bulk loads had laid out the leaves so that no merge hit the last leaf. statdump counters stayed 0 throughout and could not tell the runs apart.
- Case (2026-11-05, parallel scan probes): a race did not hold vacuum back because csql auto-committed the scanning session; `--no-auto-commit` fixed it. A rebuild of the probe install under a running server left a master the wrapper could not stop.

### P19 — no negative integers in a cfg
- Rule: A TLC cfg cannot write a negative integer: put a natural constant in the cfg and build the value set from it in the spec.
- Applies at: SKILL.md step 4
- Case (2026-11-05, CBRD-27819 cmp-dispatch): `CONSTANTS Vals = {-10, -5, 0, 5, 10}` stopped every cfg with `ConfigFileException ... expecting }`; `MaxV = 10` with `Vals == {v \in -MaxV..MaxV : v % 5 = 0}` in the spec ran.

### P20 — decision tables: literal chains, no poisoned facts
- Rule: A decision table is proved per input as a chain of equalities to record literals (generate the steps), with flags as 0/1 integers, records built instead of `EXCEPT`, and each fact a step needs taken from the action's definition alone — a cited fact holding a `CASE`, an `\E` or a boolean-valued `IF` makes the step fail in every prover.
- Applies at: PROOFS.md
- Case (2026-11-05, CBRD-27819 cmp-dispatch): one obligation per (client, site, type pair) with the whole decision unfolded timed out (34/843 in 1800 s); `conv = <<a # tgt, b # tgt>>` and `[d EXCEPT !.cmp = ...]` failed even for one concrete pair, and `BY <2>1` failed while `<2>1` held `inst' = CASE ...` although the same equality proved from `DEF Install`. With 0/1 flags, fresh records, a generated literal chain per pair and facts taken one by one from the action, 7652/7652 proved in 866 s.
- Case (2026-11-06, parallel sort merge queue): ghost updates written `poolOver' = (poolOver \/ inf >= PoolSize)` and `err' = (err \/ ~tok[t])` left `poolOver' = FALSE` / `err' = TRUE` unprovable in SMT and Zenon (timeouts on one-line goals); the same updates as `IF inf >= PoolSize THEN TRUE ELSE poolOver` proved at once.
- Case (2026-11-06, rule review, tlapm 1.6.0-pre): the goal `poolOver' = FALSE` from `poolOver' = (poolOver \/ inf >= PoolSize)`, verbatim, proved at once (`probe16`); the `IF … THEN TRUE ELSE` clause left the rule.

### P21 — higher-order library theorems need Isa
- Rule: A library theorem over an operator parameter (`NatInduction`, `SmallestNatural`) applies only through the Isabelle back end: `DEFINE` the predicate, `HIDE DEF` it, and cite the theorem with `Isa`.
- Applies at: PROOFS.md (limits)
- Case (2026-11-05, tlapm 1.6.0-pre smoke): `\E m \in Nat : Q(m) /\ \A j \in 0 .. m-1 : ~Q(j)` with `Q(x) == x \in S` hidden proved `BY <2>1, SmallestNatural, Isa` (Isabelle2025); cited without the hidden predicate it failed.
- Case (2026-11-05, CBRD-27361 page-batch-walk, tlapm 1.4.5 without Isabelle — superseded, the `Least` workaround was dropped from the rule on 1.6): `MinExists` by `NatInduction` and then by `SmallestNatural` failed in every prover (`BY ..., NatInduction, Isa` cannot run here); rewriting `Hop`, `Collect`'s first off-page record and the three row emissions as `\E s \in S : Least(s, S) /\ ...` removed the lemma, and the deadlock check of the pass cfgs still shows a least element exists.

### P22 — a hidden definition under a prime needs its own equality
- Rule: Under `HIDE DEF`, state the equality for the primed term exactly as the goal writes it (`HasAns(cur)' = HasAns(cur)`); a `\A p : Ans(p, s)' = Ans(p, s)` the prover must instantiate under the prime does not prove the goal.
- Applies at: PROOFS.md (limits)
- Case (2026-11-05, CBRD-27361 page-batch-walk): with `HIDE DEF Ans, HasAns, AnsIn` the `Env` and `UNCHANGED vars` cases failed for `IFront'` from `\A p \in Pages, s \in Slots : Ans(p, s)' = Ans(p, s)`; stating `\A s \in Slots : Ans(cur, s)' = Ans(cur, s)` and `HasAns(cur)' = HasAns(cur)` proved them.
- Case (2026-11-06, parallel-hash-join): with 2 workers and 1 unit the probe-phase `INIT IndInv` passed 33 million initial states before its 20-min timeout; the join phase (no membuf, keys fixed) finished 31 million in 15 min and the split phase with 1 worker 2.1 million in 48 s, so the check runs as two cfgs.

### P23 — INIT IndInv must enumerate
- Rule: TLC enumerates `INIT IndInv` conjunct by conjunct: bind each variable just before the conjuncts that constrain it, have the actions reset values no later phase reads to a constant, and keep the inductive cfg's constants smaller than the main cfg's, or the initial states never finish.
- Applies at: SKILL.md step 6
- Case (2026-11-05, CBRD-27361 page-batch-walk): `INIT IndInv` with `TypeOK` first spent 7 min on 656 448 initial states at NP = 1, NS = 3 and ran past 10 min for the iter mode; IndInv rewritten in binding order, the chunk slots zeroed outside a chunk (`ClearChunk`) and NS = 2 / NP = 2, NS = 1 brought each inductive cfg to 4-6 s. RtfLifecycle's `TypeOK`-first IndInv also ran past 10 min, and `bkeys \subseteq Keys` could not be enumerated at all (`\in SUBSET`).

### P24 — a guard and its access are two steps
- Rule: A guard and the shared-state access it protects are two steps when the code reads them apart (an interrupt check, then a lookup of shared memory): a mutant that survives the coarser step is the signal to split it.
- Applies at: SKILL.md step 5
- Case (2026-11-05, CBRD-27361 runtime-filter): `release_before_drain` (the filter freed before `wait_for_workers`) survived while `WRow` checked the interrupt and probed the filter in one step, since a stopped worker then never probed; split into `WRow` (the check) and `WProbe` (`hjoin_rtf_pass`), the mutant reads the freed filter.

### P25 — a loop bound every iteration advances
- Rule: A worker loop is bounded by a counter every iteration advances (its share of the input), never by one only some iterations advance, or TLC reports a false liveness counterexample.
- Applies at: SKILL.md step 4
- Case (2026-11-05, CBRD-27361 runtime-filter): `LeaderFinishes` failed on the correct model: a worker whose filter the sample took off counted no rows, so `rows[w] < MaxRows` never stopped its row loop and `WEnd` was never continuously enabled; a per-worker `left` budget fixed it.

### P26 — a narrow window waits for its precondition
- Rule: A hole whose window is a few instructions wide is reproduced by an injection at the window that waits, polling the shared state, until the counterexample's precondition holds (bounded, traced), and then runs the real step; the load that creates the precondition runs for the whole bound.
- Applies at: SKILL.md step 7
- Case (2026-11-05, CBRD-26425 atomic latch H1): `pgbuf_lockfree_fix_ro` held its window between the vpid check and the CAS open until the BCB held another page whose latch word equalled the loaded one; the first run closed it unmatched after 30 s (`matched=0`) because the buffer churn (8 scans, 0.3 s) ended long before the page could age out; with two sessions churning for the whole bound it matched in 2 s, the real CAS succeeded on page 1|3992 for a fix of 1|641, and the caller asserted in `pgbuf_check_page_ptype`.

### P27 — a crash state is the code's write
- Rule: A crash fault's intermediate state is the exact page write of the function that performs the first half, read in that function (a replace that re-inserts in order, a move that shifts), never the caller's comment.
- Applies at: SKILL.md step 3
- Case (2026-11-06, CBRD-24094 leaf swap): the first crash model put the removed leaf object in the first overflow page's last slot, from `btree_replace_first_oid_with_ovfl_oid`'s comment ("swap ... with last object"); two injected crashes recovered cleanly. `btree_record_replace_object` removes the old object and re-inserts the new one in OID order (`btree.c:38577`); with that write the model found H2 (an object above page 2's separator left in page 1), reproduced on the third run.

### P28 — a stop the capacity checks forbid is a model error
- Rule: A counterexample that needs the scan or buffer to stop where the code's capacity checks forbid it is a model error: derive a stop or overflow condition from the code's arithmetic (what the check counts, what it reserves) before a hole is reported.
- Applies at: SKILL.md step 7
- Case (2026-11-06, CBRD-27401 scan resume): the model let a key-start iteration stop with no chain object accepted (anchor NULL) and TLC found a lost row without COMPACT; the runtime attempt stopped before the key instead (`n_before=0`), because the key-start check reserves the leaf objects plus one full overflow page (`btree.c:30774`, `btree.c:29694`). The stop now needs an accepted object, the vacuum-only path passes, and H1 needs COMPACT.

### P29 — stop only your own processes
- Rule: Stop only the processes your own runner started, by the pid it recorded; other sessions run tlapm and TLC on this host at the same time, so never kill by pattern or by a pid read from `ps`.
- Applies at: SKILL.md Toolchain
- Case (2026-11-06, CBRD-24094): a `pkill -f` pattern for this session's tlapm killed its own shell, and a follow-up `kill` of a tlapm pid read from `pgrep -fl` stopped another session's `PxHashJoin_proofs` run (5번 세션), which had to be redone.

### P30 — `-` binds tighter than `+`
- Rule: Parenthesize every `a + b - c` a proof step states: TLA+ binds `-` (precedence 11) tighter than `+` (10), so `qn + 1 - k` is `qn + (1 - k)` and does not match a fact written `(qn + 1) - k` without integer typing in the context.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel sort merge queue): `Cardinality(Q') = qn + 1 - k` failed in every prover while `<2>x` proved `Cardinality(Q') = (qn + 1) - k`; tlapm printed the two differently, `qn + 1 - KOf(...)` against `(qn + 1) - KOf(...)`. Writing `(qn + 1) - k` in the step proved it.

### P31 — split a large proof into modules
- Rule: `tla-check` gives each proof module one 1800 s tlapm run: split a proof past about a thousand obligations into modules that `EXTEND` a shared base module (tlapm proves only the theorems of the module it is given), each under the limit, and keep the INV1 theorems in the top module.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel sort merge queue): one module with 2850 obligations stopped at 1931 proved after 1800 s (rc=124) although every lemma had proved in partial runs; a test module `B EXTENDS A` reported only B's obligation. Split into `_base` (helpers, InitInv), `_main`, `_task`, `_disp`, `_tc` and the top module with StepInv, InvSafe and Safe.

### P32 — emit before you start a thread
- Rule: An event for a step that starts another thread (`push_task`, `pthread_create`, a signal) is emitted before that start, or the started thread's first event can land ahead of it and the run diverges from the spec.
- Applies at: TRACE.md
- Case (2026-11-06, parallel sort merge queue): `MDispatch` was logged after `sort_merge_queue_try_dispatch` returned, so in one run (merge 2 failing at once) the task's `TMerge` came before its own `MDispatch` and the trace could not be accepted; logging inside `try_dispatch` before `push_task` (and the callback's `TComplete` there too) made all six runs accepted.

### P33 — prove a large action through its branch effects
- Rule: A PlusCal action with branches is proved through an effect step: state each branch as its guard, every assignment and `UNCHANGED` of the rest, prove their disjunction by one `CASE` per branch condition (a primed predicate such as `failed'[self] = "err"` tells `either` branches apart), then prove each IndInv part from one branch's conjunction with the action's definition left unexpanded.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel-hash-join): with `DEF W_claim` (six branches) unfolded in every part's step, `IDisp'`, `ICnt'` and `ILocal'` timed out even at `--stretch 6`, and the six-way effect disjunction stated in one step still failed; with one `CASE` per branch condition it proved in a single test-module run, and the parts then proved branch by branch.

### P34 — a boolean conjunct is an iff
- Rule: Write an IndInv conjunct that ties a boolean variable to a predicate as `x \in BOOLEAN /\ (x <=> P)`; written `x = (P)` it stays unprovable in SMT and Zenon, even in InitInv.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel-hash-join): `freed = (pc[Leader] \in {"L_fallback", "Done"})` failed in InitInv at every stretch although `pc[Leader] = "L_push"` and `freed = FALSE` were facts of the step; with `freed \in BOOLEAN /\ (freed <=> ...)` (and the same for `tableFreed`, `membufClaimed`, `final`, the `L_push` test) the step proved.

### P35 — parenthesize a primed right side
- Rule: Parenthesize the right side of every `x' = ...` a proof step states: `uaf' = uaf \/ freed` parses as `(uaf' = uaf) \/ freed`, and an `IF c THEN a ELSE b` right side swallows the conjuncts written after it.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel-hash-join): the hand-written effect steps of `W_check`, `W_err`, `W_swap` and `W_pclean` failed in every prover; the generator wrote `uaf' = uaf \/ freed` and `mainErr' = IF won[self] THEN failed[self] ELSE mainErr` followed by `/\ UNCHANGED <<...>>`. With every right side in parentheses they proved.

### P36 — Assm states what model values give TLC
- Rule: State in `Assm` what a TLC model value gives for free: a constant set is nonempty, and a sentinel the spec compares with its members is not one (`Workers # {}`, `"none" \notin Workers`); TLAPS reads every constant as an arbitrary set.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel-hash-join): InitInv's `(pc[Leader] = "L_push" <=> pushed # Workers)` is false for `Workers = {}`, and the dispenser conjunct `\A w \in Workers : w # owner => mb[w] \in {-1, 0}` with `owner = "none"` needs `"none" \notin Workers`; both held in every TLC run because the cfg's workers are model values.

### P37 — iterate a failing step in a test module
- Rule: Fix a failing obligation in a test module that `EXTEND`s the spec and states only that step, then rerun the whole proof once: obligations that fail run to their timeout and set the whole run's wall time, and `--threads` above the free cores only takes CPU from other sessions' provers.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel-hash-join): three whole-module reruns of about 1850 obligations at 32 threads ran 3000 s, 3000 s (both stopped by the timeout) and 2028 s (stopped by another session) while other sessions ran tlapm and TLC on the host; the `W_claim` effect that failed in all three proved in one run of a test module `T EXTENDS PxHashJoin` holding that step alone.

### P38 — an integer comparison needs its type in scope
- Rule: A step that compares a variable with `<` or `<=` needs that variable's type in its context: when `IndInv` stays folded, `USE` a fact such as `np \in 0..MaxP` in each action lemma; keep a structural assumption (`o = <<o[1], o[2]>>`) out of the module's global `USE` and cite it only in the lemma that needs it.
- Applies at: PROOFS.md
- Case (2026-11-06, CBRD-24094 ovf-dir): `OvfOrder_proofs` stuck at 858/930 even at `--stretch 12` (tlapm 1.4.5 and 1.6.0-pre alike); `r < np BY r1 = r, r2 <= np` timed out because `np`'s type lived only in the folded `IndInv`, and `USE AssmO` (the tuple shape of every object) stalled Z3 on unrelated steps. With `<1>n. np \in 0..MaxP` used per lemma, `AssmO` cited only in `OidNat`/`OidIn`, and small `SepNat`/`ContNat` lemmas, 1257/1257 proved in 54 s.

### P39 — a large proof module needs `--workers`
- Rule: Size `tools/tla/tla-check --workers` to the free cores for a proof module of more than a few hundred obligations: `--workers` is also tlapm's `--threads` (default 4) and the proof runs under a fixed 1800 s timeout, so at the default a large module ends as a timeout, not a verdict; check `nproc` and the load average first, and give a module that needs longer a `\* timeout: <seconds>` line in its proof file.
- Applies at: SKILL.md (Toolchain)
- Case (2026-11-06, CBRD-27361 page-batch-walk): `tla-check --stretch 3` on `PageBatchWalk_proofs` (3673 obligations) ran tlapm with `--threads 4` and was 26 min into its 30-min limit when stopped; the same proof at 16 threads had finished in 31 min. Rerun with `--workers 24 --stretch 2` at load average 32 on 64 CPUs. That rerun proved 1737 of 3679 obligations, none failed, before the 1800 s limit cut it at load average 93; the proof file now carries `\* timeout: 7200`.

### P40 — a quantifier swallows the conjuncts after it
- Rule: In a conjunct list, a quantifier written `/\ \A x \in S : P(x) /\ Q` takes every later conjunct on the line into its body: parenthesize it, `/\ (\A x \in S : P(x)) /\ Q`, or put it last.
- Applies at: PROOFS.md
- Case (2026-11-06, parallel sort merge queue): a step `/\ \A t \in Tasks : tpc[t] \in {"idle", "done"} /\ Q = {} /\ sleeping = FALSE` put `Q = {}` inside the `\A`; a later `AfterStage' => Q' = {} BY <1>3, <1>4` failed in SMT, Zenon and Isabelle until the quantifier was parenthesized.

### P41 — one toolchain per run
- Rule: A toolchain install during a run swaps the tools under it: with `--prove`, `tools/tla/tla-check` fails a run whose proof logs carry different `TLAPM version` lines, and that run is rerun, never judged.
- Applies at: SKILL.md (Toolchain)
- Case (2026-11-06, parallel sort merge queue): the tools link moved from tlapm 1.4.5 to 1.6.0-pre at 01:31 during a 01:12 run; three proof modules logged `TLAPM version 1.4.5` and two `efe4f2d`, `Safe` failed with `ls4 not found`, and the 1.4.5 modules failed steps that had proved before. The rerun on one toolchain proved `Safe`.
- Case (2026-11-06, rule review): the check moved into `tla-check` (with `--prove`, different `TLAPM version` lines across a run's proof logs fail it), so no session reads the lines by hand.

### P42 — the symbolic inductive check comes first
- Rule: The inductive check is the Apalache cfg; write a TLC inductive cfg only when IndInv's types do not fit Apalache: Apalache checks every value of the integer constants in seconds, where TLC's `INIT IndInv` enumeration takes minutes at small constants and a failed TLAPS step tells only that the provers gave up.
- Applies at: SKILL.md step 6
- Case (2026-11-06, parallel hash join): the 2-worker TLC inductive cfg enumerated 31 072 256 initial states in 15 min (26 min under load), and each IndInv strengthening (W_fl with p = NP, mutant-only labels) was found that way before a TLAPS round of up to 40 min per module; Apalache 0.62.4 checks CondVarHandoff's IndInv for every `MaxSpurious \in Nat` in 5 s and rejects a weakened IndInv in the same time.
- Case (2026-11-06, rule review): with TLAPS on request only (P48) the TLC inductive cfg no longer feeds a proof; P45 asked for both checks, and the TLC one cost up to 1 319 s where Apalache answers for every integer value, so the TLC cfg became the fallback for types Apalache cannot express.

### P43 — a wait's return branches each name their lock
- Rule: Map each return branch of a wait separately and name the lock it holds: a primitive that returns unlocked (`thread_suspend_timeout_wakeup_and_unlock_entry`) gets one row per branch of its caller, and a branch that does not re-lock is split at each shared read and write, never copied from the branch that does.
- Applies at: SKILL.md step 2
- Case (2026-11-06, CBRD-26425 atomic latch): the first model gave `pgbuf_timed_sleep`'s timeout one step under the entry lock, like its interrupt branch (page_buffer.c:7397 re-locks). The TIMEDOUT branch does not: it reads `resume_status` at 7420, may `goto try_again` (7428), writes `NO_LATCH` at 7436 and calls `thread_unlock_entry` on a lock it does not hold at 7437. Splitting it found hole A (CBRD-27739 cause A): a grant between the read and the write leaks fcnt (runtime: page 1|769 READ-blocked, S2's entry mutex `__nusers = 4294967293`, assert at thread_entry.cpp:270 on stop).

### P44 — the scope is the change's diff
- Rule: Before the report, give every function a hunk of the verified change touches, and every path between its acquire and release points (error returns, interrupts, hand-offs, invalidation, lock-free lookups), a map row or a fault-table row carrying the code fact that excludes it; "not covered" is never a report line.
- Applies at: SKILL.md step 2
- Case (2026-11-06, CBRD-26425 atomic latch): the first report listed the flush errors, the FLUSH waiter interrupt, the post-flush hand-off, invalidation and `pgbuf_search_hash_chain_no_bcb_lock` as not covered; the user asked why. Modeling them found hole E: `pgbuf_bcb_flush_with_wal` returns on a TDE or DWB error after `pgbuf_bcb_mark_is_flushing` (page_buffer.c:10986, 10998) with FLUSHING set and DIRTY cleared and wakes no FLUSH waiter (TLC deadlock at depth 17; optdebug assert `LSA_ISNULL(oldest_unflush_lsa) || dirty` on the next unfix).

### P45 — verified means run, not written
- Rule: A model is a result only once `tools/tla/tla-check` has run it to `RESULT: OK`: TLC on the main and scale cfgs, every mutant rejected, every witness reached, IndInv inductive (Apalache, or TLC where Apalache cannot type IndInv), TLAPS proving the INV1 theorems when the user asked for a proof (P48), and trace validation where step 8 requires it; a spec written but not run, or run without a proof the user asked for, is reported as 미완, never as verified.
- Applies at: SKILL.md step 10
- Case (2026-11-06, PR #8356 review, per-row partition walk): the model and its cfgs were written and the first TLC passes were in when the user asked mid-turn: "tla+ 모델링만 하는게 아니라 그걸로 검증까지해야하는건 알고있지?" The review's TLA+ step stays open until the inductive checks and the TLAPS proof run to `RESULT: OK`.

### P46 — tlapm 1.6.0-pre is the prover
- Rule: Proofs are written and judged on tlapm 1.6.0-pre, whose `tlapm --version` and proof-log `TLAPM version` line print the build hash `efe4f2d`, not `1.6`: 1.6's SMT encoding times out on steps 1.4.5 proved (ADR 0045), so a timeout is split into named-conjunct lemmas that carry their own type facts, never settled by an older log or a 1.4.5 run.
- Applies at: SKILL.md (Toolchain), PROOFS.md
- Case (2026-11-06, PR #8356 review): the user asked "1.6버전으로 하고잇는건알고잇지?" before the proof was written; `.git_ignored_dir/tla/tools/bin/tlapm --version` printed `efe4f2d`, and ADR 0045 records 1.4.5-proved obligations that time out on 1.6 (`ExprProgExec_proofs` 23:87, `PxHeapSnapshot_proofs` 118:5 and 196:3).

### P47 — a declaration keyword carries its first name
- Rule: Write every CONSTANTS and VARIABLES declaration with its first name on the keyword's line (`VARIABLES kind, prune,`): `tools/tla/apalache-types` rewrites only a block whose keyword line already holds a name, so a bare `VARIABLES` line leaves every variable untyped and the Apalache cfg fails with `Expected a type annotation for VARIABLE <name>` (rc=255).
- Applies at: PROOFS.md (Apalache)
- Case (2026-11-06, PR #8356 review): `PartWalk.tla` declared `VARIABLES` on a line of its own with one commented name per line below; `PartWalk.apalache-indinv` failed at `PartWalk.tla:78` with `Expected a type annotation for VARIABLE memoOn` although all 31 `apalache-type` lines were present. With `VARIABLES kind, prune, home, data, outer,` on one line the script wrote all 31 `@type` annotations.

### P48 — TLAPS only on an explicit request
- Rule: TLAPS runs only when the user's own message explicitly asks for a proof ("TLAPS", "증명해줘", "명확히 검증해줘"): then `tools/tla/tla-check --prove` proves every proof module and requires one; otherwise no proof module is written, step 6 ends at the inductive cfgs, and the report says TLAPS 요청 없음. A generic "TLA+로 검증", a skill, a ticket or a review step never counts as that request.
- Applies at: SKILL.md (Toolchain), steps 6 and 10; PROOFS.md; cubrid-pr-review Step 3d; grill-with-tla; enforced by `tools/tla/tla-check --prove`
- Case (2026-11-06, rule review): of 124 tla-check runs, tlapm took 26 214 s against 22 866 s for every TLC cfg together (parallel-hash-join alone: 7 proof modules, 11 371 s in sequence), 19 of 47 rules existed to get proofs through, and every code defect in this file (P13, P14, P27, P43, P44 cases) came from a TLC counterexample or deadlock. The user decided: "내가 명확히 검증해줘 라고 하지 않는 이상 TLAPS는 빼자 ... 명확히 검증해달라고 하면 TLAPS도 포함". ADR 0046.

### P49 — a crashed tlapm run proves nothing
- Rule: A tlapm run that ends with `rc=3` and its obligations left "to be proved" crashed before proving: read the log's `Error:` / `ending abnormally` line first. On 1.6 a prime over an expression that already holds a prime (`Exp(outer'[x])'`; write `(Exp(outer[x]))'`) aborts level checking with an `e_levels.ml` assertion, and `Lemma!n` cannot name a conjunct of an ASSUME/PROVE lemma (`Cannot resolve !4`): name the conclusion as an operator and cite the lemma with `DEF` of it.
- Applies at: PROOFS.md (tlapm 1.6.0-pre limits)
- Case (2026-11-06, PR #8356 review, `PartWalk_proofs`): a `SUFFICES` stating `em'[x] = Exp(outer'[x])'` turned a 439-obligation run into `rc=3` with 298 proved and every later step "to be proved"; the log held `tlapm ending abnormally with File "src/expr/e_levels.ml", line 502 ... Assertion failed`. `(Exp(outer[x]))'` proved all 439. In the same module `<1>2. ORFacts!1 /\ ... BY ORFacts` stopped tlapm at parse with `Cannot resolve !4`; an operator `ORConcl` for the lemma's conclusion, cited `BY ORFacts DEF ORConcl`, proved 735/735.
