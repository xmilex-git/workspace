# Trace validation

Reached from SKILL.md steps 7 and 8. Shape anchor: `examples/px-error-handoff/` (`traces/`,
`PxErrorHandoffTrace.tla`, the `witness-trace-ok` and `reject-free-before-join` cfgs). The method is
the one of Cirstea, Kuppe, Loillier and Merz, "Validating Traces of Distributed Programs Against TLA+
Specifications" (2024): the run constrains the spec, and TLC asks whether some behavior consumes it.

Every model of code that exists is tied to it by trace validation: an instrumented build of the exact sha records runs the trace spec accepts and a corrupted run it refuses; only a design with no implementation or a pattern example carries `trace-exempt: <reason>` in MAP.md. (P50)

## 1. Instrument a scratch worktree

- A worktree of the exact engine sha, never a peer worktree and never a commit: the instrumentation
  is evidence tooling, thrown away with the worktree.
- One event per action of the refinement map, emitted **inside the step it records** (under the
  same latch, lock or mutex, or right after the atomic), with `seq=` from one global
  `std::atomic<uint64_t>` fetch-add done inside the step, so log order cannot disagree with
  execution order.
- An event for a step that starts another thread (`push_task`, `pthread_create`, a signal) is emitted before that start, or the started thread's first event lands ahead of it. (P32)
- Line format, anywhere in a log line: `TLATRACE seq=<n> a=<Action> p=<process> <field>=<value>...`.
  Log every outcome the spec can match (`err=1`, `page=3`, the chosen index): the fewer values the
  spec has to guess, the smaller its search — the paper's runs with events only exploded where runs
  with events and values finished. Write to a dedicated file in the run's scratch directory
  (`er_log_debug` is compiled out of release and interleaves other text).
- The instrumentation diff only adds lines: before the build `git diff | grep -E '^-[^-]'` prints nothing, and a bulk edit (`sed s/A/B/`) is applied to the added lines only, never to the file. (P78)
- Build optdebug through `cubrid-build` with a dedicated prefix; run through `cubrid-server-control`
  on a claimed port; stop the server and release the port after. Stop the server before rebuilding
  its install (a server on a rebuilt install leaves a master the wrapper cannot stop).

## 2. Record runs that cover the map

Run until every action of the refinement map appears in at least one accepted trace, fault branches
included (inject the error, the interrupt, the concurrent DML or vacuum the fault table models). An
action no run reaches is listed in MAP.md with the reason (crash, for example).

- A trace file the server holds open is truncated (`: > trace.log`), never deleted, and a per-key dump switch (`CUBRID_TLA_DUMP_KEY`) is off on a server that a checkdb or another whole-index pass reads: a deleted file keeps taking the events unseen, and a dump per scanned key fills the disk. (P75)

## 3. Check

```bash
tools/tla/trace2tla <Module>TraceData OkTrace=<run1.log> [Run2=<run2.log> ...] > <dir>/<Module>TraceData.tla
```

`<Module>Trace.tla` EXTENDS the spec and the data module and adds a cursor `i`:

- `Logged`: `LET e == TraceLog[i + 1]` names an action; that action of process `e.p` fires, its outcome matches `e`'s fields, and `i' = i + 1`.
- `Hidden`: actions the build does not log fire with `UNCHANGED i`; keep the set as small as the instrumentation allows, since each hidden action widens what the trace can match.
- `TraceNotDone == i < Len(TraceLog)`.
- A trace spec builds the values an event leaves open from the event's own fields, never by filtering the spec's whole input set per event: under `-coverage` such a filter advances about one event a minute. (P51)
- Every trace cfg runs with `CHECK_DEADLOCK FALSE` (`deadlock-off: trace`): a branch of the unlogged nondeterminism that dead-ends is not a deadlock while another branch consumes the run, and the first unconsumed event is read from TLC's depth line. (P53)
- A witness-trace cfg carries `\* tlc: -difftrace` (tla-check passes that line's options to TLC) and a `\* timeout:` sized to the run: TLC prints the accepted run as its counterexample, every state in full unless told to print only the changed variables. (P80)

| cfg | Expectation | Meaning |
|---|---|---|
| `<Module>Trace.witness-trace-<run>.cfg` | `violation TraceNotDone` | the whole run is a behavior of the spec |
| `<Module>Trace.reject-<case>.cfg` | `pass` | a corrupted run (two events swapped, an event dropped, an outcome flipped) is refused, so the trace spec is not vacuous |

A recorded run the spec refuses is a divergence. TLC's `The depth of the complete state graph search is d` line gives the deepest cursor: with no hidden steps event `d` is the first the spec could not consume (`i` starts at 0 at depth 1); with hidden steps, truncate the log to bisect. Classify the divergence like a counterexample (SKILL.md step 7).

## 4. Reproducing a hole

A TLC counterexample in the correct model is a hole only after a run of the build takes the same steps.

- A hole's runtime reproduction logs the structural events of the counterexample (TLATRACE at the snapshot, alloc, free and fix sites), so a run shows the interleaving happened and not only a wrong answer. (P17)
- Widen a narrow window with an env-gated delay on the scratch worktree (`CUBRID_TLA_<WHAT>_DELAY_MS`, read once, default off) at the step the counterexample waits in.
- A hole whose window is a few instructions wide is reproduced by an injection at the window that waits, polling the shared state, until the counterexample's precondition holds, while the load that creates the precondition runs for the whole bound. (P26)
- An env-gated delay at a shared step holds the racing session too: its statements carry a hint that keeps them off the delayed path, and both sessions' elapsed times are read before a run counts. (P54)
- An injected fault lands on the first matching step, often a cache fill the model does not name: warm the caches before arming, and rerun the injection with the modeled reaction switched off before blaming the modeled step for a crash. (P57)
- A session that must hold a snapshot (to keep vacuum from removing rows) runs `csql --no-auto-commit`.
- A layout the counterexample needs (a merge of the last leaf handed out, a reused page) depends on the load: log the page ids and count only the runs whose events show the layout.
