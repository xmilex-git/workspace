# CondVarHandoff — a waiter wakes exactly when the predicate it waits for holds

Pattern example for the cubrid-tla skill: a mutex + condition variable handoff (`pthread_cond_wait`
loops in CUBRID's daemons, job queues and parallel joins). Code names the roles generically; a real
model names `file:function` and the symbol at each row.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | The waiter consumes only after the signaler published `ready`. | POSIX `pthread_cond_wait`: spurious wakeups may occur, so the predicate is re-checked |
| C2 | The waiter is not left asleep after the signal (no lost wakeup). | POSIX: a signal with no waiter asleep is lost |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| `W_lock` | waiter `pthread_mutex_lock` | |
| `W_check` | `while (!ready)` test | under the mutex |
| `W_wait` | `pthread_cond_wait` release-and-sleep | POSIX makes the release and the sleep atomic |
| `W_wake` | return from `pthread_cond_wait`: wake, then reacquire the mutex | wake and reacquire are one step here because nothing the model checks happens between them |
| `W_consume` | use the data, `pthread_mutex_unlock` | under the mutex |
| `S_lock` / `S_unlock` | signaler lock / unlock | |
| `S_set` | `ready = true` | under the mutex |
| `S_signal` | `pthread_cond_signal` | |
| `X_one` | the OS waking a sleeper spuriously | environment, no fairness |
| `badConsume` | ghost: consumed while `ready` was false | |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` (`BoolOK /\ CountOK`) | invariant | variable types | — |
| `NoConsumeBeforeReady` | invariant | never consume before `ready` | C1 |
| `WaiterFinishes` | liveness, WF on waiter and signaler | the waiter reaches Done | C2 |
| `IndInv` | inductive invariant | implies C1; TLAPS-proved for any `MaxSpurious` | C1 |

## Fault model and environment assumptions

| Item | Modeled as |
|---|---|
| spurious wakeup | `X_one`, any time the waiter sleeps, at most `MaxSpurious` times |
| mutex fairness | none (WF only): an endless run of spurious wakeups lets the waiter retake the mutex forever and starve the signaler, so the wakeups are bounded; C2 is claimed under "finitely many spurious wakeups" |
| signal before wait | covered: the signaler may run first; the waiter then never sleeps |

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-lost-wakeup` | signaler sets and signals without the mutex | deadlock: the signal falls between `W_check` and `W_wait`, the waiter sleeps forever | C2 |
| `mutant-if-not-while` | waiter consumes after a wake without re-checking | `NoConsumeBeforeReady` violated after a spurious wakeup | C1 |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-slept` | the waiter slept at least once and finished with `ready` |

## Dead expressions (pass cfg)

| Line | Why never evaluated |
|---|---|
| CondVarHandoff.tla:150 | `W_wake` branch of `mutant-if-not-while` only |
| CondVarHandoff.tla:156 | `badConsume' = TRUE`: the ghost that flags C1's violation; dead because C1 holds |
| CondVarHandoff.tla:170 | `S_lock` branch of `mutant-lost-wakeup` only |
| CondVarHandoff.tla:188 | `S_unlock` branch of `mutant-lost-wakeup` only |

## Bounds and limits

- TLC: one waiter, one signaler, `MaxSpurious = 2`; TLAPS covers any `MaxSpurious` for C1.
- Apalache (`CondVarHandoff.apalache-indinv.cfg`): IndInv is inductive for every `MaxSpurious \in Nat`, one waiter and one signaler.
- C2 is checked by TLC only, under the bounded-spurious-wakeup assumption above.
- `pthread_cond_broadcast` and several waiters are out of scope for this example.

## Result

- 2026-11-05, `just tla-selftest`, toolchain `rr034sppv8gw9k63ppwwb5028rx2chmf-tla-tools`: `RESULT: OK`.
- TLC: pass 145/92 states (depth 19), scale (`MaxSpurious = 3`) 189/119, inductive 6242/2340; 2 mutants rejected (deadlock, NoConsumeBeforeReady); 1 witness reached.
- TLAPS: 100/100 obligations proved (`CondVarHandoff_proofs.tla`).
- Trace validation: not applicable (pattern example with no code under it).
