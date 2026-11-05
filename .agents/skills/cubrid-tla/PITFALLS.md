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
- Case (2026-11-05, condvar-handoff): `ASSUME spuriousLeft = MaxSpurious, MaxSpurious \in Nat, locked = FALSE PROVE spuriousLeft \in 0..MaxSpurious /\ locked \in BOOLEAN` timed out in Z3 (30 s with `--stretch 6`) and Zenon exhausted its search; the captured SMT input encoded `locked = FALSE` as `(not (boolify locked))` with no axiom back to `tla__BOOLEAN`. Each half proved alone.

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
