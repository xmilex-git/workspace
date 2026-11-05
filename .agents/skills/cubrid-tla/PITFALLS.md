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

### P2 — no PTL back end
- Rule: tlapm here has no LS4 back end, so a `PTL` step never proves: state the INV1 premises as separate theorems and leave the temporal conclusion to the rule.
- Applies at: PROOFS.md
- Case (2026-11-05, skill build): the textbook `<1>. QED BY <1>1, <1>2, <1>3, PTL DEF Spec` failed with `Executable "ls4" not found`; nixpkgs ships tlaps 1.4.5 without LS4 or an Isabelle/TLA+ heap, and source builds are off limits on this host. `RuleINV1` from `TLAPS.tla` could not be used either (`Operator "RuleINV1" not found`, a crash in `e_anon.ml`).

### P3 — untyped logic: a negation is not a type
- Rule: state the value the action assigns (`x' = FALSE`)
- Applies at: PROOFS.md (table)
- Case (2026-11-05, condvar-handoff): `BoolOK'` would not prove from a step that said `~sleeping'`; the action assigns `sleeping' = FALSE`, and once the step said so the case proved (100/100).

### P4 — SMT cannot mix boolean typing and integers
- Rule: split `TypeOK` into a boolean part and an integer part and prove them in separate steps
- Applies at: PROOFS.md (table); SKILL.md step 4
- Case (2026-11-05, CBRD-27215/27361 expr-prog-exec, page-batch-walk): `TBool'` failed in ExprProgExec until it stood apart from `TRest`, and in PageBatchWalk the steps for `IFix'`/`IChunk'`/`IPhase'` kept failing (13 of 2749 obligations, `--stretch 5`) while `fixed`/`more`/`learned \in BOOLEAN` sat in those conjuncts; split out as `IFixB`/`IChunkB`/`IPhaseB`.
- Case (2026-11-05, condvar-handoff): `ASSUME spuriousLeft = MaxSpurious, MaxSpurious \in Nat, locked = FALSE PROVE spuriousLeft \in 0..MaxSpurious /\ locked \in BOOLEAN` timed out in Z3 (30 s with `--stretch 6`) and Zenon exhausted its search; the captured SMT input encoded `locked = FALSE` as `(not (boolify locked))` with no axiom back to `tla__BOOLEAN`. Each half proved alone.

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
- Rule: A decision table is proved per input as a chain of equalities to record literals (generate the steps), with flags as 0/1 integers, records built instead of `EXCEPT`, boolean assignments written `IF … THEN TRUE ELSE FALSE`, and each fact a step needs taken from the action's definition alone — a cited fact holding a `CASE`, an `\E` or a boolean-valued `IF` makes the step fail in every prover.
- Applies at: PROOFS.md
- Case (2026-11-05, CBRD-27819 cmp-dispatch): one obligation per (client, site, type pair) with the whole decision unfolded timed out (34/843 in 1800 s); `conv = <<a # tgt, b # tgt>>` and `[d EXCEPT !.cmp = ...]` failed even for one concrete pair, and `BY <2>1` failed while `<2>1` held `inst' = CASE ...` although the same equality proved from `DEF Install`. With 0/1 flags, fresh records, a generated literal chain per pair and facts taken one by one from the action, 7652/7652 proved in 866 s.

### P21 — no Isabelle: pick the least element in the action
- Rule: tlapm here has no Isabelle back end, so a library theorem over an operator parameter (`NatInduction`, `SmallestNatural`) never applies: write `\E x \in S : Least(x, S)` in the action instead of `Min(S)` / `CHOOSE`, so the proof only uses the picked element and TLC's deadlock check shows one exists.
- Applies at: PROOFS.md (limits)
- Case (2026-11-05, CBRD-27361 page-batch-walk): `MinExists` by `NatInduction` and then by `SmallestNatural` failed in every prover (`BY ..., NatInduction, Isa` cannot run here); rewriting `Hop`, `Collect`'s first off-page record and the three row emissions as `\E s \in S : Least(s, S) /\ ...` removed the lemma, and the deadlock check of the pass cfgs still shows a least element exists.

### P22 — a hidden definition under a prime needs its own equality
- Rule: Under `HIDE DEF`, state the equality for the primed term exactly as the goal writes it (`HasAns(cur)' = HasAns(cur)`); a `\A p : Ans(p, s)' = Ans(p, s)` the prover must instantiate under the prime does not prove the goal.
- Applies at: PROOFS.md (limits)
- Case (2026-11-05, CBRD-27361 page-batch-walk): with `HIDE DEF Ans, HasAns, AnsIn` the `Env` and `UNCHANGED vars` cases failed for `IFront'` from `\A p \in Pages, s \in Slots : Ans(p, s)' = Ans(p, s)`; stating `\A s \in Slots : Ans(cur, s)' = Ans(cur, s)` and `HasAns(cur)' = HasAns(cur)` proved them.

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
