# Inductive invariant: the Apalache check

Reached from SKILL.md step 6. Shape anchor: `examples/condvar-handoff/CondVarHandoff.apalache-indinv.cfg`.

## The three conditions and where each is checked

An inductive invariant `IndInv` proves the safety claims through three conditions (Lamport, "Using TLC
to Check Inductive Invariance"; Apalache's IndInit / IndNext / IndProp):

| Condition | Checked by |
|---|---|
| `Init => IndInv` and IndInv holds on every reachable state | the main cfg: `IndInv` is in its INVARIANTS |
| `IndInv /\ Next => IndInv'` | `<Module>.apalache-<n>.cfg` (below) |
| `IndInv => Safety` | Every safety property of the claims is a named conjunct of IndInv, so the inductive check reaches the claims without a proof. (P64) |

## The cfg

```
\* expect: pass
\* apalache: --cinit=CInit --length=1
INIT IndInv
NEXT Next
INVARIANT IndInv
```

- `CInit` (in the spec, after the PlusCal translation) fixes the role sets to string literals
  (`Workers = {"w1", "w2"}`) and leaves the integer bounds open (`MaxSpurious \in Nat`,
  `NU \in Nat /\ NU >= 1`): set sizes stay fixed, integer sizes are unbounded.
- Apalache types every CONSTANT and VARIABLE. The PlusCal translator drops comments, so the spec
  states each type once as `\* apalache-type: <name> <type>` (`pc Str -> Str`,
  `temp Str -> (Int -> Set(<<Int, Str>>))`) and `tools/tla/apalache-types` writes them into the
  run-dir copy. An untyped name fails the cfg with `rc=255` and the name in the log.
- A counterexample (`got=[violation IndInv]`) is the pair of states in the run dir's
  `apalache-<cfg>/out/**/violation1.tla`: a CTI. Classify it as below.
- The inductive check is the Apalache cfg; a TLC inductive cfg is written only when IndInv's types do not fit Apalache. (P42)

## Writing IndInv

`IndInv` is a list of named conjuncts, one `  /\ Name` per line (apalache-split reads that list).
Its first version already carries the well-formedness conjuncts every protocol needs: each index
field in range, each idle handler's fields reset, each message in the shape its sender builds,
each queue holding only what its phase allows, each record not yet in use equal to its initial
value. Nearly every CTI of a first draft is a well-formedness gap.

- An Apalache IndInv binds every variable before a conjunct reads it, every operator over a record or tuple carries a `\* @type:` line, and a pair of strings is a record, never a tuple. (P52)
- Apalache leaves a function applied outside its domain unconstrained: IndInv bounds every field it uses as an index before a conjunct applies it. (P61)
- An Apalache IndInit draws a record-valued variable with `Gen` in a `<Module>Ind.tla` that EXTENDS the spec and `Apalache`, and TypeOK states its domain and field ranges as predicates (`DOMAIN dev = Nodes`, `x.p \in 1..MaxP`), never `dev \in [Nodes -> [p: Int, ...]]`: Int fields fail with "set map over an infinite set", and finite field ranges make Apalache enumerate the whole record set. (P71)
- Every CONSTANTS and VARIABLES declaration carries its first name on the keyword's line, or `tools/tla/apalache-types` leaves the block untyped. (P47)
- Apalache takes no `Seq(_)` and no `a..b` with a non-constant bound: a program is a function over `1..N` with `N` a constant, and a variable-bounded range is written as inequalities over a constant range. (P59) Apalache's own workarounds: `range(a, b) == {x \in Nmin..Nmax : a <= x /\ x <= b}`, and `Gen(n)` from the `Apalache` module for a bounded sequence.

## Iterating

```bash
# every group at once, in the background; N ≈ conjuncts / 6
for k in $(seq 1 8); do TMO=1200 tools/tla/apalache-split docs/tla/X X.apalache-indinv $k/8 > .git_ignored_dir/scratch/tla/X-grp$k.out 2>&1 & done
# a group that timed out: 8 transition parts of its conjuncts (Found 76 transitions in its log)
for k in $(seq 0 7); do TF="0->0|1->($(seq -s '|' $k 8 75))" TMO=1200 tools/tla/apalache-split docs/tla/X X.apalache-indinv 1/1 Inv22 Inv23 > .git_ignored_dir/scratch/tla/X-tf$k.out 2>&1 & done
# after a fix: only the changed conjuncts
tools/tla/apalache-split docs/tla/X X.apalache-indinv 1/1 Inv7 Inv12
```

Each job prints one verdict line (`PASS <conjuncts> <secs>s`, `CTI <conjuncts>` + State0 → State1 diff, `ERROR ... timeout`); classify a group as soon as its line appears, never after the slowest one. SKILL.md step 6 "Time budget" is the full procedure.

- The inductive check is iterated with `tools/tla/apalache-split`, one background job per group of conjuncts, from an IndInv whose first version already holds the well-formedness conjuncts (index fields in range, idle handlers reset, messages in their sender's shape, queues holding only what their phase allows); after a fix only the changed conjuncts rerun, and `tla-check`'s run is the record. (P62) A stronger IndInv keeps every other group's pass; a weakened conjunct reruns them all. An IndInv too large for one Apalache run is recorded as several `apalache-<n>` cfgs, each INVARIANT a part of IndInv under `INIT IndInv` of the whole; tla-check runs them in parallel beside the TLC cfgs.
- A conjunct too slow for one Apalache run is split by transition (`TF=` on apalache-split, `search.transitionFilter` on a part cfg), the parts together covering every transition; a part's timeout is never a pass. (P63) The log's `Found N transitions` gives the count; transition `k` is `Next_si_000k` in `--write-intermediate=true`'s `XX_OutTransitionFinderPass.tla`, which names the slow action. `search.invariant.mode=after` trades memory for fewer SMT queries, `z3.sat.threads=<n>` parallelizes Z3 (both via `--tuning-options=`).

## Classifying a CTI

The pre-state of a CTI need not be reachable: IndInv over-approximates the reachable states.

- The system cannot reach the pre-state → A CTI from a state the system cannot reach means IndInv is too weak: strengthen IndInv, never the spec, and keep IndInv in the main cfg's INVARIANTS so TLC confirms the new conjunct on every reachable state. (P6)
- The system can reach it → the claim is false: a counterexample (SKILL.md step 7).

## TLC fallback (`<Module>.inductive-<n>.cfg`)

```
\* expect: pass
\* deadlock-off: starts from every IndInv state, including finished ones
INIT IndInv
NEXT Next
INVARIANT IndInv
CHECK_DEADLOCK FALSE
```

- TLC enumerates `INIT IndInv` conjunct by conjunct: bind each variable just before the conjuncts that constrain it, write `x \in SUBSET W` (never `x \subseteq W`), keep the constants below the main cfg's, and when the enumeration still does not finish, probe with a randomized `IInit` (`RandomSubset`, `RandomSetOfSubsets`) whose pass is a probe, never the record. (P23) The `Randomization` module's `RandomSubset(k, S)` draws `k` elements of `S` per evaluation; a dozen runs that find no CTI, and one that finds a planted weakening, are the probe's evidence.
