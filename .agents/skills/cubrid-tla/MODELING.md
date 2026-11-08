# Modeling CUBRID in TLA+

Reached from SKILL.md steps 2-4 and 9. The patterns name the code to read, not the answer: every
row of a real refinement map is grounded on the worktree at the reviewed or designed sha with
`tools/code-index/code-index <worktree> body|callers <symbol>`.

## Atomicity: what one step is

- A step is everything between two points where the protection of the touched shared state is
  acquired or released. Two accesses under one held page latch, lock or mutex may be one step; an
  access with no protection (a plain read of a shared flag, a pointer published without a barrier)
  is a step of its own.
- An atomic (`std::atomic`, `ATOMIC_*`) is one step per operation; a read-then-write over two atomic
  operations is two steps unless it is one CAS or fetch-add.
- A condition wait is two steps: release-and-sleep (atomic by POSIX), then wake-and-reacquire.
- PlusCal: one label = one step. A label that spans a latch release is wrong by construction.
- `define` cannot see process-local `variables`; declare state the properties read as globals (P5).

## Patterns

| Primitive | Model as | Code to read |
|---|---|---|
| page latch | per page: `mode \in {"none","read","write"}`, holder set, waiter queue; `fix` waits for compatibility, conditional fix fails instead of waiting; promotion read -> write may fail when another reader holds the page | `pgbuf_fix`, `pgbuf_unfix`, `pgbuf_promote_read_latch`, the `condition` argument (`PGBUF_UNCONDITIONAL_LATCH` / `PGBUF_CONDITIONAL_LATCH`) |
| latch order / deadlock | the order every thread fixes pages in; TLC's deadlock check finds a cycle of unconditional waits | the caller's fix sequence; conditional fix + release-and-retry paths |
| lock manager | per object: granted modes per transaction, compatibility table as a TLA+ function, waiters; timeout and deadlock-victim as fault actions returning an error | `lock_object`, `lock_scan`, the lock compatibility table in `lock_manager.c` |
| MVCC snapshot | snapshot = lowest active MVCCID + set of active ids at snapshot time; visibility = insert id committed and visible, delete id absent or not visible | `mvcc_satisfies_snapshot`, the snapshot builder in `mvcc_table.cpp` |
| vacuum | removes a version only when no snapshot can see it: its threshold is the global oldest visible MVCCID; model every snapshot holder (each scanning thread, each PX worker) as a reader of that threshold | `vacuum_heap_page`, `mvcc_table::get_global_oldest_visible`, `lock_global_oldest_visible` |
| concurrent DML | an environment process inserting, updating (new version + old version marked), deleting rows on the pages the scan visits, committing or aborting nondeterministically | `heap_insert_logical`, `heap_update_logical`, `heap_delete_logical` |
| WAL | page LSN, log flushed-up-to LSN; a page write is enabled only when the log is flushed past the page LSN; crash discards everything not flushed; recovery redo/undo as actions | `logpb_flush_log_for_wal`, page flush in `page_buffer.c` |
| crash / `kill -9` | an action that resets volatile state and leaves durable state; checks then run recovery to completion | recovery entry points in `log_recovery.c` |
| PX workers | leader + worker processes, a shared work source (page or range dispenser), per-worker result buffers, join, error handoff, interrupt | `src/query/parallel/` (`px_worker_manager`, `px_scan/`, `px_interrupt.hpp`) |
| condvar | `examples/condvar-handoff`: release-and-sleep step, spurious wakeup process, `while` re-check | |
| decision table | Init picks every input class; one step computes the result; invariants state the expected output per class | the function and every caller (`callers`) |

- Model when the MVCC snapshot is built relative to every set the scan collects at open (the page bitmap, the leaf chain, the partition list), per isolation level: under READ COMMITTED the statement's first `logtb_get_mvcc_snapshot` builds it, which may run after open. (P13)
- A check that a page is the same page by VPID alone is a reuse hole whenever the page can be freed and reallocated during the protocol: model the free pool with reuse (`file_alloc` takes the lowest free page) and check what the code compares besides the VPID (LSA, key range). (P14)

## Spec traps (SKILL.md step 4)

- An environment process that loops (an OS, vacuum, a DML stream) must be able to end when the system ends, or TLC reports a false deadlock. (P8)
- A worker loop is bounded by a counter every iteration advances (its share of the input), never by one only some iterations advance, or TLC reports a false liveness counterexample. (P25)
- A TLC cfg cannot write a negative integer: put a natural constant in the cfg and build the value set from it in the spec. (P19)
- A CASE whose guards can hold together is a nondeterministic choice in TLA+, not TLC's first-match: an ordered decision is an IF ... ELSE IF chain, and a CASE keeps only guards that exclude each other or end in OTHER. (P56)
- An action that assigns a variable and also lists it in UNCHANGED is enabled only where the two agree, and TLC reports nothing: after editing UNCHANGED lists in bulk, check each action that assigns the variable, and a mutant that survives where a counterexample was expected first gets a reachability probe of its precondition states. (P58)
- A constant that is a statement's program or any sequence is a function over `1..N` with `N` its own constant, substituted in the cfg from a spec operator (`Prog <- ProgScanCount`), and a range bounded by a variable is written as inequalities (`0 <= v /\ v <= curVer`, `\E v \in 0..NW : v <= curVer /\ ...`): a TLC cfg cannot write a sequence, and Apalache rejects `Seq(_)` and any `a..b` whose bound is not a constant, in ASSUME and in IndInv alike. (P59)
- Write `COUNT-star` (never `COUNT(*)`) in a spec's comments, `\*` lines included: the `(*` opens a nested block comment and SANY reports an EOF or an open comment far below it. (P60)

## Fault checklist (SKILL.md step 3)

Answer each row in MAP.md's fault table as modeled, or not applicable with the reason.

| Fault | Where it can fire |
|---|---|
| error return | every call in the mapped code that returns an error code |
| interrupt / query cancel | every loop that checks `logtb_is_interrupted` or the PX interrupt |
| lock timeout, deadlock victim | every unconditional lock request |
| conditional latch failure | every `PGBUF_CONDITIONAL_LATCH` fix and every promotion |
| OOM | every allocation whose failure path the change touches |
| crash / `kill -9` | between any two durable writes; for temp files, between create and cleanup |
| spurious wakeup | every condition wait |
| concurrent DML | every page or object the scanned set covers |
| vacuum | every version a snapshot of the change can read |
| checkpoint, page flush, page replacement | every page fixed without being pinned across the step |
| HA log apply | replicated state the change reads on a slave |
| nested statement (SP SQL from the client) | the READ COMMITTED statement snapshot the change reads |

- A model that reads the READ COMMITTED statement snapshot gives the fault table a row for a nested statement (an SP's SQL sent by the client) that invalidates and rebuilds it mid-statement (`network_sr.c` `logtb_invalidate_snapshot_data`), and a claim that the snapshot stays put names that row's scope. (P55)

- A crash fault's intermediate state is the exact page write of the function that performs the first half, read in that function (a replace that re-inserts in order, a move that shifts), never the caller's comment. (P27)

## Fairness

- Weak fairness on a process: if a step stays enabled, it eventually runs. A mutex retake that is
  enabled only intermittently is not covered; a lock or latch is not fair unless the code queues
  waiters in order.
- Environment processes (vacuum, DML, the OS) get no fairness unless the claim needs their
  progress; then MAP.md says so.
- TLC refuses SYMMETRY together with PROPERTY in this repo's check: liveness is unsound under it.

## Refinement

When an abstract spec `Abs` (a design-level `docs/tla/<key>/` spec) exists, the implementation spec
states how its variables produce `Abs`'s variables and checks `Abs`'s behavior as a property:

```tla
AbsVars == INSTANCE Abs WITH result <- <<rows the leader has returned>>, done <- (pc[Leader] = "Done")
AbsSpec == AbsVars!Spec
```

The main cfg lists `PROPERTY AbsSpec`. Every implementation step must be an `Abs` step or leave
`Abs`'s variables unchanged (a stuttering step); a step that changes them in a way `Abs` forbids is
reported as an action-property violation. A mutant whose implementation step breaks the mapping
shows the check is live; expect it as `\* expect: refinement` (P10).
