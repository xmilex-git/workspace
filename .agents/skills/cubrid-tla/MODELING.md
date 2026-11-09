# Modeling CUBRID primitives

Reached from SKILL.md steps 2 and 9. Each pattern names the code to read, not the answer: every row
of a real refinement map is grounded on the worktree at the reviewed or designed sha with
`tools/code-index/code-index <worktree> body|callers <symbol>`.

## Patterns

| Primitive | Model as | Code to read |
|---|---|---|
| page latch | per page: `mode \in {"none","read","write"}`, holder set, waiter queue; `fix` waits for compatibility, a conditional fix fails instead of waiting; promotion read -> write may fail when another reader holds the page | `pgbuf_fix`, `pgbuf_unfix`, `pgbuf_promote_read_latch`, `PGBUF_UNCONDITIONAL_LATCH` / `PGBUF_CONDITIONAL_LATCH` |
| latch order / deadlock | the order every thread fixes pages in; TLC's deadlock check finds a cycle of unconditional waits | the caller's fix sequence; conditional fix + release-and-retry paths |
| lock manager | per object: granted modes per transaction, compatibility table as a TLA+ function, waiters; timeout and deadlock victim as fault actions returning an error | `lock_object`, `lock_scan`, the compatibility table in `lock_manager.c` |
| MVCC snapshot | lowest active MVCCID + set of active ids at snapshot time; visibility = insert id committed and visible, delete id absent or not visible | `mvcc_satisfies_snapshot`, the snapshot builder in `mvcc_table.cpp` |
| vacuum | removes a version only when no snapshot can see it (threshold = global oldest visible MVCCID); every snapshot holder (each scanning thread, each PX worker) is a reader of that threshold | `vacuum_heap_page`, `mvcc_table::get_global_oldest_visible`, `lock_global_oldest_visible` |
| concurrent DML | an environment process inserting, updating (new version + old marked), deleting rows on the pages the scan visits, committing or aborting nondeterministically | `heap_insert_logical`, `heap_update_logical`, `heap_delete_logical` |
| WAL | page LSN, log flushed-up-to LSN; a page write is enabled only when the log is flushed past the page LSN; crash discards everything not flushed; recovery redo/undo as actions | `logpb_flush_log_for_wal`, page flush in `page_buffer.c` |
| crash / `kill -9` | an action that resets volatile state and keeps durable state; checks then run recovery to completion | recovery entry points in `log_recovery.c` |
| PX workers | leader + worker processes, a shared work source (page or range dispenser), per-worker result buffers, join, error handoff, interrupt | `src/query/parallel/` (`px_worker_manager`, `px_scan/`, `px_interrupt.hpp`) |
| condvar | `examples/condvar-handoff`: release-and-sleep step, spurious-wakeup process, `while` re-check | |
| decision table | Init picks every input class; one step computes the result; invariants state the expected output per class | the function and every caller (`callers`) |

- Model when the MVCC snapshot is built relative to every set the scan collects at open (page bitmap, leaf chain, partition list), per isolation level: under READ COMMITTED the statement's first `logtb_get_mvcc_snapshot` builds it, which may run after open. (P13)
- A page identified by VPID alone is a reuse hole whenever it can be freed and reallocated during the protocol: model the free pool with reuse and check what the code compares besides the VPID (LSA, key range). (P14)

## Refinement

When an abstract spec `Abs` (a design-level `docs/tla/<key>/` spec) exists, the implementation spec
states how its variables produce `Abs`'s variables and checks `Abs`'s behavior as a property:

```tla
AbsVars == INSTANCE Abs WITH result <- <<rows the leader has returned>>, done <- (pc[Leader] = "Done")
AbsSpec == AbsVars!Spec
```

The main cfg lists `PROPERTY AbsSpec`. Every implementation step is an `Abs` step or leaves `Abs`'s
variables unchanged; a step that changes them in a way `Abs` forbids is an action-property
violation. A mutant whose step breaks the mapping shows the check is live: A mutant that only the refinement mapping catches is expected as `\* expect: refinement`: TLC reports a broken refinement by location, not by the PROPERTY's name. (P10)
