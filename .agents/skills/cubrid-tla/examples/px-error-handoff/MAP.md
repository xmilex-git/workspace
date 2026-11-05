# PxErrorHandoff — a worker error reaches the leader, and nothing touches freed worker state

Pattern example for the cubrid-tla skill: the leader/worker error handoff that cubrid-pr-review P5
states (the leader adopts a worker's error only after its wait for every worker, in its own
thread). The code column names the roles generically; a real model names `file:function` and
the symbol at each row.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A worker's error reaches the leader's error context; no error is lost or invented. | cubrid-pr-review P5 |
| C2 | The leader frees worker state only after every worker has stopped touching it, including when the leader itself fails. | cubrid-pr-review P5 |
| C3 | The query finishes. | — (liveness of any query) |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `W_wait` | worker thread start, blocked until the leader starts the scan | the start handshake is one mutex-protected flag |
| `W_run` (either-branch) | worker scan loop: normal end / error / sees interrupt | the error branch writes only the worker's own holder; the interrupt flag is atomic |
| `W_done` | worker's done counter increment and notify | done under the join mutex |
| `L_spawn` | leader starts workers | |
| `L_work` | leader's own part of the query, which may fail and set the interrupt | |
| `L_join` | leader waits until the done count equals the worker count | condition wait on the join mutex |
| `L_adopt` | leader moves a holder's error into its thread-local error context | runs in the leader thread after the join |
| `L_free` | leader frees worker state (holders, buffers) | |
| `uaf` | ghost: a worker writes after `L_free` | |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `NoLostError` | invariant | finished leader reports an error iff it or a worker failed | C1 |
| `NoUseAfterFree` | invariant | no worker write after free | C2 |
| `LeaderFinishes` | liveness, WF per process | the leader reaches Done | C3 |
| `IndInv` | inductive invariant | implies `NoLostError` and `NoUseAfterFree`; TLAPS-proved for any worker set | C1, C2 |

## Fault model

| Fault | Modeled as |
|---|---|
| worker error | `W_run` error branch, any worker, any time after start |
| leader error | `L_work` error branch, sets the interrupt |
| interrupt observed | `W_run` third branch, enabled once interrupted |
| crash / kill -9 | not modeled: the process dies with every thread; no state survives to be misused |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-early-adopt` | leader adopts once any worker is done | `NoLostError` violated | C1 |
| `mutant-no-join-on-error` | leader skips the join after its own error | `NoUseAfterFree` violated | C2 |
| `mutant-lost-done-on-interrupt` | a worker that stops on the interrupt returns without counting itself done | deadlock: the leader waits in `L_join` forever | C3 |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-worker-error` | leader finished with a worker's error and no error of its own |
| `witness-leader-error` | leader finished on its own error while a worker had already completed normally |
| `witness-trace-ok` | recorded run `traces/ok.log` (events out of file order, sorted by `seq`) is a behavior of the spec |
| `reject-free-before-join` | recorded run `traces/free-before-join.log` is refused at `L_join` |

## Dead expressions (pass cfg)

| Line | Why never evaluated |
|---|---|
| PxErrorHandoff.tla:139 | `uaf' = TRUE` in `W_run`: the ghost that flags C2's violation; dead because C2 holds |
| PxErrorHandoff.tla:152 | `uaf' = TRUE` in `W_done`: same ghost |
| PxErrorHandoff.tla:158 | `W_done` skipping the done count: `mutant-lost-done-on-interrupt` only |
| PxErrorHandoff.tla:179 | `goto L_free` of `mutant-no-join-on-error` only |

## Bounds and limits

- TLC: 3 workers in the pass cfg, 4 in the scale cfg (2 in mutants, witnesses and the inductive check); TLAPS covers any worker set for C1 and C2.
- C3 is checked by TLC only (no PTL back end for TLAPS on this host).
- The model trusts that the done count and the holders are written under the join mutex; a code change that moves either out of it invalidates the `W_done` row above.

## Result

- 2026-11-05, `just tla-selftest`, toolchain `rr034sppv8gw9k63ppwwb5028rx2chmf-tla-tools`: `RESULT: OK`.
- TLC: pass 2346/697 states (depth 15), scale 17762/3985 (depth 18), inductive 3392/960; 3 mutants rejected (NoLostError, NoUseAfterFree, deadlock); 2 witnesses and 1 recorded trace reached; 1 corrupted trace refused.
- TLAPS: 60/60 obligations proved (`PxErrorHandoff_proofs.tla`).
- No engine build: the traces in `traces/` are hand-written examples of the event format, not recordings.
