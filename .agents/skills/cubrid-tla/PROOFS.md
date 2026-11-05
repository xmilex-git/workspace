# TLAPS proofs on this host

Reached from SKILL.md step 6. Shape anchors: `examples/*/<Module>_proofs.tla`.

## What gets proved

The safety claims of the correct variant, for every value of the constants (any number of workers,
any `MaxSpurious`), as the premises of the TLA invariance rule INV1 plus the implication:

```tla
---- MODULE <Module>_proofs ----
EXTENDS <Module>, TLAPS
ASSUME Correct == Mutant = "none"

THEOREM InitInv == Init => IndInv
THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
THEOREM InvSafe == IndInv => <Safety1> /\ <Safety2>
====
```

INV1 turns the first two into `Spec => []IndInv`; the third gives `Spec => []Safety`.

- tlapm here has no LS4 back end, so a `PTL` step never proves: state the INV1 premises as separate theorems and leave the temporal conclusion to the rule. (P2)
- Liveness is not proved; it stays a TLC result inside the cfg bounds, and the report says so.
- The proof module is never loaded by TLC; the `Correct` assumption cannot leak into a mutant cfg.

## Writing `StepInv`

```tla
THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct DEF IndInv, TypeOK, ...
<1>1. CASE Action1             BY <1>1 DEF Action1
<1>2. ASSUME NEW self \in Workers, WorkerAction(self) PROVE IndInv'
  BY <1>2 DEF WorkerAction
...
<1>k. CASE UNCHANGED vars      BY <1>k DEF vars
<1>. QED  BY <1>1, ..., <1>k DEF Next, ...
```

One case per action; a case that fails is split further, first by the action's `either` / `IF`
branches, then by stating the facts it needs as numbered steps.

- Name each conjunct of IndInv beyond `TypeOK` (`R_x == ...`), prove each in its own step with `TypeOK`, its parts and every `R_` in the DEF list, and join them in the QED; one step over the whole conjunction times out. (P15)

## tlapm 1.4.5 on this host: limits and the sound workaround

| Symptom | Cause | Workaround |
|---|---|---|
| a step with `PTL` fails, "ls4 not found" | no PTL back end | INV1 premises as theorems (P2) |
| a trivial typing goal times out in SMT and Zenon "exhausted search space" | the SMT encoding turns `x = FALSE` into `not (boolify x)`, which loses `x \in BOOLEAN` once integer arithmetic is in the same goal | split `TypeOK` into a boolean part and an integer part and prove them in separate steps (P4) |
| `x' \in BOOLEAN` fails after `~x'` | TLA+ is untyped: `~x'` says nothing about `x'` being a boolean | state the value the action assigns (`x' = FALSE`) (P3) |
| an obligation over `pc = [self \in ProcSet |-> CASE ...]` times out | PlusCal's CASE function literal is heavy for both provers | prove each `pc[p]` value, then `DOMAIN pc = ProcSet`, then the function-set membership from the two; never `DEF Init` in a QED that does not need it |
| `"<op>" not found` in the proof module | the PlusCal translation is stale | run `tools/tla/tla-check`, which translates before proving |
| tlapm exits 0 with obligations failed | `--toolbox` mode reports failures as messages | `tla-check` counts each obligation's final status (P1) |

- tlapm here has no Isabelle back end, so a library theorem over an operator parameter (`NatInduction`, `SmallestNatural`) never applies: write `\E x \in S : Least(x, S)` in the action instead of `Min(S)` / `CHOOSE`, so the proof only uses the picked element and TLC's deadlock check shows one exists. (P21)
- Under `HIDE DEF`, state the equality for the primed term exactly as the goal writes it (`HasAns(cur)' = HasAns(cur)`); a `\A p : Ans(p, s)' = Ans(p, s)` the prover must instantiate under the prime does not prove the goal. (P22)
- A decision table is proved per input as a chain of equalities to record literals (generate the steps), with flags as 0/1 integers, records built instead of `EXCEPT`, boolean assignments written `IF … THEN TRUE ELSE FALSE`, and each fact a step needs taken from the action's definition alone — a cited fact holding a `CASE`, an `\E` or a boolean-valued `IF` makes the step fail in every prover. (P20)

Every workaround keeps the theorem statement; only the proof is decomposed, and the QED that joins
the parts is itself an obligation. A theorem weakened to make it prove, an `OMITTED` step, or a
property moved from TLAPS to "TLC only" without saying so in MAP.md is not a workaround.

## Strengthening IndInv

The inductive cfg finds a state satisfying IndInv whose successor violates it. Read the state: if
the system cannot reach it, add the conjunct that excludes it (P6), keep IndInv in the main cfg's
INVARIANTS so TLC checks the new conjunct on every reachable state, and re-run. If the system can
reach it, the claim is false: that is a counterexample (SKILL.md step 7).
