# Trace validation

Reached from SKILL.md step 8. Shape anchor: `examples/px-error-handoff/` (`traces/`,
`PxErrorHandoffTrace.tla`, the `witness-trace-ok` and `reject-free-before-join` cfgs).

A trace check asks whether a run of the real build is a behavior of the spec. It is what ties the
refinement map to the code: a map row that is wrong shows up as a run the spec refuses.

## 1. Instrument a scratch worktree

- A worktree of the exact engine sha under review or design, never a peer worktree and never a
  commit: the instrumentation is evidence tooling and is thrown away with the worktree.
- One event per action of the refinement map, emitted **inside the step it records** (under the
  same latch, lock or mutex, or right after the atomic operation), so log order cannot disagree
  with execution order. Events from several threads carry `seq=` from one global
  `std::atomic<uint64_t>` fetch-add done inside the step.
- Line format, anywhere in a log line: `TLATRACE seq=<n> a=<Action> p=<process> <field>=<value>...`;
  `a` is the TLA+ action name, `p` the process id the spec uses, fields are the outcomes the spec
  must match (`err=1`, `page=3`). Write to a dedicated file opened by the instrumented build in the
  run's scratch directory (`er_log_debug` is compiled out of release and interleaves other text).
- Build optdebug through `cubrid-build` with a dedicated prefix; run the scenario through
  `cubrid-server-control` on a claimed port; stop the server and release the port after.

## 2. Record runs that cover the map

Run until every action of the refinement map appears in at least one accepted trace, including the
fault branches (inject the error, the interrupt, the concurrent DML or vacuum the fault table
models). An action no run reaches is listed in MAP.md with the reason (for example, crash).

## 3. Check

```bash
tools/tla/trace2tla <Module>TraceData OkTrace=<run1.log> [Run2=<run2.log> ...] > <dir>/<Module>TraceData.tla
```

`<Module>Trace.tla` EXTENDS the spec and the data module and adds a cursor `i`:

- `Logged`: the next event names an action; that action of that process fires, its outcome matches
  the event's fields, and `i' = i + 1`.
- `Hidden`: actions the build does not log fire with `UNCHANGED i`; keep this set as small as the
  instrumentation allows, since each hidden action widens what the trace can match.
- `TraceNotDone == i < Len(TraceLog)`.

| cfg | Expectation | Meaning |
|---|---|---|
| `<Module>Trace.witness-trace-<run>.cfg` | `violation TraceNotDone` | the whole run is a behavior of the spec |
| `<Module>Trace.reject-<case>.cfg` | `pass` (`CHECK_DEADLOCK FALSE` with a `deadlock-off` reason) | a corrupted run (two events swapped, an event dropped, an outcome flipped) is refused, so the trace spec is not vacuous |

A recorded run the spec refuses is a divergence: find the first event `i` could not consume (the
`reject` cfg's TLC log shows the deepest state) and classify it as a counterexample (SKILL.md step 7).
