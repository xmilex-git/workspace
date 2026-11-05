# TLAPS proofs on this host

Reached from SKILL.md step 6. Shape anchors: `examples/*/<Module>_proofs.tla`.

## What gets proved

The safety claims of the correct variant, for every value of the constants (any number of workers,
any `MaxSpurious`): the premises of the TLA invariance rule INV1, their temporal conclusion, and the
implication:

```tla
---- MODULE <Module>_proofs ----
EXTENDS <Module>, TLAPS
ASSUME Correct == Mutant = "none"

THEOREM InitInv == Init => IndInv
THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
THEOREM InvSafe == IndInv => <Safety1> /\ <Safety2>
THEOREM Safe == Spec => []IndInv
  BY InitInv, StepInv, PTL DEF Spec
====
```

`Safe` with `InvSafe` gives `Spec => []Safety`.

- `PTL` steps prove through LS4 (tlapm 1.6.0-pre): keep the INV1 premises as their own theorems and conclude `Spec => []IndInv` from them `BY InitInv, StepInv, PTL DEF Spec`, so a temporal failure is told apart from a step failure. (P2)
- Liveness is proved only with a fairness (`WF`/`SF`) argument written for it; without one it stays a TLC result inside the cfg bounds, and the report says so.
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
| a step with `PTL` fails, "ls4 not found" | the toolchain in the GC root is older than `tools/tla/tools.nix` | `just tla-install` (P2) |
| a trivial typing goal times out in SMT and Zenon "exhausted search space" | the SMT encoding turns `x = FALSE` into `not (boolify x)`, which loses `x \in BOOLEAN` once integer arithmetic is in the same goal | split `TypeOK` into a boolean part and an integer part and prove them in separate steps (P4) |
| `x' \in BOOLEAN` fails after `~x'` | TLA+ is untyped: `~x'` says nothing about `x'` being a boolean | state the value the action assigns (`x' = FALSE`) (P3) |
| an obligation over `pc = [self \in ProcSet |-> CASE ...]` times out | PlusCal's CASE function literal is heavy for both provers | prove each `pc[p]` value, then `DOMAIN pc = ProcSet`, then the function-set membership from the two; never `DEF Init` in a QED that does not need it |
| `"<op>" not found` in the proof module | the PlusCal translation is stale | run `tools/tla/tla-check`, which translates before proving |
| tlapm exits 0 with obligations failed | `--toolbox` mode reports failures as messages | `tla-check` counts each obligation's final status (P1) |

- A library theorem over an operator parameter (`NatInduction`, `SmallestNatural`) applies only through the Isabelle back end: `DEFINE` the predicate, `HIDE DEF` it, and cite the theorem with `Isa`; where a least element is all the action needs, `\E x \in S : Least(x, S)` in the action instead of `Min(S)` / `CHOOSE` avoids the lemma, and TLC's deadlock check shows one exists. (P21)
- Under `HIDE DEF`, state the equality for the primed term exactly as the goal writes it (`HasAns(cur)' = HasAns(cur)`); a `\A p : Ans(p, s)' = Ans(p, s)` the prover must instantiate under the prime does not prove the goal. (P22)
- A decision table is proved per input as a chain of equalities to record literals (generate the steps), with flags as 0/1 integers, records built instead of `EXCEPT`, boolean assignments written `IF … THEN TRUE ELSE FALSE`, and each fact a step needs taken from the action's definition alone — a cited fact holding a `CASE`, an `\E` or a boolean-valued `IF` makes the step fail in every prover. (P20)

- Parenthesize every `a + b - c` a proof step states: TLA+ binds `-` (precedence 11) tighter than `+` (10), so `qn + 1 - k` is `qn + (1 - k)` and does not match a fact written `(qn + 1) - k` without integer typing in the context. (P30)
- `tla-check` gives each proof module one 1800 s tlapm run: split a proof past about a thousand obligations into modules that `EXTEND` a shared base module (tlapm proves only the theorems of the module it is given), each under the limit, and keep the INV1 theorems in the top module. (P31)
- A PlusCal action with branches is proved through an effect step: state each branch as its guard, every assignment and `UNCHANGED` of the rest, prove their disjunction by one `CASE` per branch condition (a primed predicate such as `failed'[self] = "err"` tells `either` branches apart), then prove each IndInv part from one branch's conjunction with the action's definition left unexpanded. (P33)
- Write an IndInv conjunct that ties a boolean variable to a predicate as `x \in BOOLEAN /\ (x <=> P)`; written `x = (P)` it stays unprovable in SMT and Zenon, even in InitInv. (P34)
- Parenthesize the right side of every `x' = ...` a proof step states: `uaf' = uaf \/ freed` parses as `(uaf' = uaf) \/ freed`, and an `IF c THEN a ELSE b` right side swallows the conjuncts written after it. (P35)
- State in `Assm` what a TLC model value gives for free: a constant set is nonempty, and a sentinel the spec compares with its members is not one (`Workers # {}`, `"none" \notin Workers`); TLAPS reads every constant as an arbitrary set. (P36)
- Fix a failing obligation in a test module that `EXTEND`s the spec and states only that step, then rerun the whole proof once: obligations that fail run to their timeout and set the whole run's wall time, and `--threads` above the free cores only takes CPU from other sessions' provers. (P37)

Every workaround keeps the theorem statement; only the proof is decomposed, and the QED that joins
the parts is itself an obligation. A theorem weakened to make it prove, an `OMITTED` step, or a
property moved from TLAPS to "TLC only" without saying so in MAP.md is not a workaround.

## Strengthening IndInv

The inductive cfg finds a state satisfying IndInv whose successor violates it. Read the state: if
the system cannot reach it, add the conjunct that excludes it (P6), keep IndInv in the main cfg's
INVARIANTS so TLC checks the new conjunct on every reachable state, and re-run. If the system can
reach it, the claim is false: that is a counterexample (SKILL.md step 7).
