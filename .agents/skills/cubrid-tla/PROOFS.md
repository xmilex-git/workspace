# TLAPS proofs — only on an explicit request

TLAPS runs only when the user's own message asks for a proof ("TLAPS", "증명해줘", "명확히 검증해줘"); a generic "TLA+로 검증", a skill, a ticket or a review step is not that request, and without it no proof module is written and the report says TLAPS 요청 없음. (P48)

Reached from SKILL.md step 6 when that request exists. Shape anchors: `examples/*/<Module>_proofs.tla`.
What a proof adds over the Apalache check: the role sets (`Workers`) become arbitrary, not fixed.

## What gets proved

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

- `PTL` steps prove through LS4: keep the INV1 premises as their own theorems and conclude `Spec => []IndInv` from them `BY InitInv, StepInv, PTL DEF Spec`. (P2)
- Liveness is proved only with a fairness (`WF`/`SF`) argument written for it; otherwise it stays a TLC result inside the cfg bounds, and the report says so.
- TLC never loads the proof module, so `Correct` cannot leak into a mutant cfg.
- A TLAPS proof of an abstract spec reaches the code-level model only through a refinement PROPERTY TLC checks inside its bounds; the report says per claim what it has. (P16)

## Writing `StepInv`

```tla
THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'  OBVIOUS
<1> USE Assm, Correct DEF IndInv, TypeOK, ...
<1>1. CASE Action1             BY <1>1 DEF Action1
<1>2. ASSUME NEW self \in Workers, WorkerAction(self) PROVE IndInv'  BY <1>2 DEF WorkerAction
<1>k. CASE UNCHANGED vars      BY <1>k DEF vars
<1>. QED  BY <1>1, ..., <1>k DEF Next, ...
```

One case per action; a case that fails is split further, first by the action's branches, then by stating the facts it needs as numbered steps. Every workaround below keeps the theorem statement and decomposes only the proof; a weakened theorem, an `OMITTED` step, or a property moved to "TLC only" without saying so in MAP.md is not a workaround.

- Each conjunct of IndInv beyond `TypeOK` is named (`R_x == ...`) and proved in its own step; one step over the whole conjunction times out. (P15)
- A branching action is proved through an effect step: one `CASE` per branch condition, then each IndInv part from one branch's conjunction with the action left unexpanded. (P33)
- When a typing step times out, split `TypeOK` into a boolean part and an integer part and prove them in separate steps. (P4)
- A step states the value the action assigns (`x' = FALSE`, never `~x'`), and a conjunct tying a boolean to a predicate is written `x \in BOOLEAN /\ (x <=> P)`, never `x = (P)`. (P3)
- Parenthesize every primed right side (`uaf' = (uaf \/ freed)`), every `a + b - c` (`-` binds tighter than `+`), and every quantifier followed by more conjuncts on its line. (P35)
- A step comparing a variable with `<` or `<=` has that variable's type in scope (`USE np \in 0..MaxP` per lemma); structural assumptions stay out of the module's global `USE`. (P38)
- `Assm` states what a TLC model value gives for free: a constant set is nonempty, and a sentinel is not one of its members. (P36)
- A decision table is proved per input as a chain of equalities to record literals (generated), with flags as 0/1 integers, records built instead of `EXCEPT`, and each cited fact free of `CASE`, `\E` and boolean-valued `IF`. (P20)
- A library theorem over an operator parameter (`NatInduction`, `SmallestNatural`) applies only through Isabelle: `DEFINE` the predicate, `HIDE DEF` it, cite the theorem with `Isa`. (P21)
- Under `HIDE DEF`, state the equality for the primed term exactly as the goal writes it (`HasAns(cur)' = HasAns(cur)`). (P22)
- An obligation over `pc = [self \in ProcSet |-> CASE ...]` is proved per `pc[p]` value, then `DOMAIN pc = ProcSet`, then the function-set membership from the two.
- A step that proves only with one back end pins it with its timeout (`BY ... Z3T(30)`), as the TLAPS community does for reproducible proofs.

## Running tlapm

- Proofs are written and judged on tlapm 1.6.0-pre (`tlapm --version` prints `efe4f2d`); an obligation that times out there is split, never settled by an older log. (P46)
- A toolchain install during a run invalidates it: `tla-check --prove` fails a run whose proof logs carry different `TLAPM version` lines, and the run is repeated. (P41)
- `tools/tla/tla-check --workers` is sized to the free cores for a module of more than a few hundred obligations, and a module that needs longer carries a `\* timeout: <seconds>` line. (P39)
- A proof past about a thousand obligations is split into modules that `EXTEND` a shared base module, each under the 1800 s limit, with the INV1 theorems in the top module. (P31)
- A failing obligation is fixed in a test module that `EXTEND`s the spec and states only that step, then the whole proof reruns once. (P37)
- A tlapm run ending `rc=3` with obligations "to be proved" crashed: read the `Error:` line; a double prime (`Exp(outer'[x])'`) and `Lemma!n` over an ASSUME/PROVE lemma crash 1.6. (P49)
- `"<op>" not found` in the proof module means a stale PlusCal translation: `tla-check` translates before proving. tlapm exits 0 with failed obligations; `tla-check` counts each obligation's final status (P1).
