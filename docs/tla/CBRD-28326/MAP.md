# CBRD-28326 — bitmap heap scan for scans that lock (TLA+ ledger)

Scope (the user, 2026-11-24): every scan that today looks its rows up in key order because it locks them
becomes a bitmap heap scan candidate: the select phase that locks (REPEATABLE READ, `mvcc_reevaluate_at_force=no`,
join or partitioned UPDATE/DELETE, LIMIT/ORDER BY UPDATE, the client-side UPDATE/DELETE of a class with triggers),
SELECT ... FOR UPDATE, and the force phase of an UPDATE/DELETE that locks at force (it locks the list's rows in the
select's output order). This supersedes the JIRA body of 2026-11-24, which kept the locking scans in key order.

trace-exempt: design before implementation (CBRD-28326 has no code yet); the refinement map names the CBRD-28032 code
the design would reuse.

## Claim and sources

| Claim | Kind | Sentence | Source | Status |
|---|---|---|---|---|
| C1 | safety | A statement never holds a page latch while it waits for a row lock. | locator_sr.c `locator_lock_object_unless_ours` (unfix before LK_UNCOND_LOCK), heap_file.c `heap_init_get_context`/`heap_clean_get_context`; a latch wait is outside lock_manager's waits-for graph | confirmed round 2 (Q3) |
| C2 | safety | Two serial bitmap heap steps that lock rows never make a lock cycle with each other through row locks alone (no claim on cycles with key-order or other-index plans, on their frequency, or on global deadlock freedom). | the heap step's order key is (slot >= 640, volid, pageid, slotid) in every session: scan_manager.c:7845 VSID sort, page = sector index x 64 + offset, :7663 page sort inside a loaded unit, :7450 wide slots to the over list read last, :7753 its sort | confirmed round 2 (Q2) |
| C3 | safety | Concurrent runs give a history develop allows: at RC a deleted row and a row whose last version left the range are skipped (C3a `NoBadKeep`), a kept row's SET is computed from its last version (C3b `NoLostUpdate`); above RC a row changed after the snapshot fails the statement, never skipped (C3c `RrConflictKept`). Rows that enter the range after the snapshot are not candidates. Same outcome under the same timing is not promised. | locator_sr.c:15640 `must_recompute`, :15436 `locator_has_isolation_conflict`; CBRD-27653 (read skew allowed at RC) | confirmed round 2 (Q3 ii) |
| C4 | safety | On an HA server an UPDATE that assigns a unique-index column succeeds or fails as the key-order write does. | btree.c:32538 `is_ha_enabled`, :34300 -975; D1 | confirmed round 2 (Q1 a) |
| C5 | safety | An assignment that reads ROWNUM, INST_NUM, ORDERBY_NUM, a serial or a session variable assignment gives every row the value the key order gives. | D4 | confirmed round 2 (Q4) |
| C6 | equivalence | On fixed data with no concurrent writer, a row-local assignment gives every primary key the same new value, the same affected rows and the same error as develop. | Q3 i | confirmed round 2 |

## Decisions

| # | Decision | Round | Model |
|---|---|---|---|
| D1 | On an HA server an UPDATE that assigns a column of a unique index (the primary key included) keeps key order; decided when it runs (HA is the server's, the assigned columns the statement's). Reason for the JIRA: HA refuses an intermediate duplicate of a multi-row update (-975), so the write order decides success; heap order fails where key order succeeds and the reverse. | 2 (Q1 a) | ForceOrder `KeyOrder`, `mutant-heap-ha-unique` |
| D2 | A lock cycle between a bitmap heap step and a key-order or other-index plan is accepted: develop already has it between plans of two indexes and between a heap scan and an index scan (probe below); it is detected within `deadlock_detection_interval_in_secs` (1 s) and the victim's transaction is aborted (-72). | 2 (Q2) | BitmapLockOrder `witness-mixed-victim` |
| D3 | The contract of "the same result" is C6 for fixed data and C3 for concurrent runs. | 2 (Q3) | both modules |
| D4 | A block whose assignments or WHERE read ROWNUM, INST_NUM, ORDERBY_NUM, a serial or a session variable assignment keeps key order. Reason for the JIRA: the order becomes stored data (develop numbers the rows in key order, `UPDATE t SET seq = ROWNUM ... USING INDEX` is a numbering idiom). | 2 (Q4) | ForceOrder `mutant-heap-numbering` |
| D5 | The order-visible effects of the locking scans (row trigger order on the client DML path, SELECT ... FOR UPDATE row order, the row of the first error, the rows left locked by a failed statement, the rows reached before lock escalation) go into the JIRA as items the implementation must decide; this ticket specifies them, it does not implement them. | 2 (Q5) | round 3 |
| D6 | D1 is decided by the server when the statement runs (HA is a server setting; a client conf is no evidence of it), for every UPDATE that assigns a column of a unique index, the primary key and MERGE's UPDATE included. EXPLAIN may show `(bitmap heap scan)` while an HA server writes in key order; the trace's `bitmap heap lookup` line shows what ran. | 3 (Q1) | ForceOrder `KeyOrder` (HA is a constant: where it is read is not modeled) |
| D7 | D4 is decided by the optimizer from the statement tree, with the operators `pt_reev_check_row_local` refuses (INST_NUM, ROWNUM, ORDERBY_NUM, NEXT_VALUE, CURRENT_VALUE, DEFINE_VARIABLE); plan and execution agree. | 3 (Q2) | ForceOrder `KeyOrder` |
| D8 | Row trigger order on the client DML path is unspecified, as the row order of a SELECT without ORDER BY; trigger logic that needs an order puts ORDER BY in the statement. Develop already changes it with the chosen index. | 3 (Q3) | not modeled (no claim) |
| D9 | The rows changed, their values and success are the same (C6, D1, D4); SELECT ... FOR UPDATE row order without ORDER BY, the first error reported when rows fail for different reasons, the rows left locked after a failed statement, and the rows locked before lock escalation may differ. | 3 (Q4) | not modeled (no claim) |

## Develop probe 2026-11-24 (D2)

optdebug `~/optdebug/CUBRID-develop-030b650ff`, DB `dl28326` (scratch `.git_ignored_dir/scratch/cbrd28326/probe/`, `setup.sql`, `dl.sh`):
t(id PK, k, v, ...), rows id 1 (k=2, v=1) then id 2 (k=1, v=2) in heap order; indexes i_t_k(k), i_t_v(v).
T0 updates id 2 and holds; T2 `UPDATE t SET c = c + 1 WHERE k BETWEEN 1 AND 2 USING INDEX i_t_k(+)` (key order:
id 2, id 1) queues; T1 locks id 1 first and queues on id 2; T0 commits. Plans confirmed by trace.
- T1 = `UPDATE t SET c = c + 1 WHERE c >= 0` (heap scan): T1 `ERROR: Your transaction ... has been unilaterally
  aborted by the system` (-72), T2 `2 rows affected (1.07 s)`.
- T1 = `UPDATE t SET c = c + 1 WHERE v BETWEEN 1 AND 2 USING INDEX i_t_v(+)`: same, T2 1.04 s.
lockdb before T0's commit: T2 holds X on id 2 and waits S on T0's transaction lock; T1 holds X on id 1, waits X on id 2.

## Develop HA probe 2026-11-24 (D1)

Same install, single-node heartbeat (ha_mode=on, ha_node_list=g28326@<host>, `cubrid changemode` reports active;
scratch `.git_ignored_dir/scratch/cbrd28326/probe/ha.sql`, `ha/rev.sql`). h(id PK, k, u UNIQUE), heap order id 1
(k=2, u=1), id 2 (k=1, u=2), index i_h_k(k). SA mode reads ha_mode as off (`;get ha_mode` -> "off"), so an SA run
does not reach the HA check.
- `UPDATE h SET u = u + 1 WHERE k BETWEEN 1 AND 2 USING INDEX i_h_k(+)` (INDEX SCAN, key order id 2, id 1): 2 rows
  affected. `... WHERE k + 0 BETWEEN 1 AND 2` (TABLE SCAN, heap order id 1, id 2): `ERROR: Current version of
  replication does not allow changing multiple rows with a single UPDATE statement which can violate the UNIQUE
  constraint.` (-975), rows unchanged.
- `SET u = u - 1`: the index (key order) fails with the same error; the table scan (heap order) gives 2 rows affected
  (u 0 and 1).

## External review 2026-11-24 (pasted by the user, at b52b26697c)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| R1 | HA: order decides success of a multi-row UPDATE of a unique column | CONFIRMED static and on a develop HA server (both directions, probe above) | btree.c:32538 `is_ha_enabled`, :34300 `ER_REPL_MULTI_UPDATE_UNIQUE_VIOLATION`; query_executor.c:17710 MULTI_ROW_UPDATE; non-HA checks at statement end (`is_unique_multi_update`), so order-free there. Reviewer's model `.git_ignored_dir/scratch/28326-force-review/docs/tla/CBRD-28326/HAOrder.tla` RESULT: OK. Applies to the narrow RC path too (force follows the list order). Round 2 Q1 |
| R2 | contract: lost SET, deleted, left range, new in range, RR conflict | ACCEPTED, model gap | per-row code, order-free: locator_sr.c:15640 `must_recompute`, :15436 `locator_has_isolation_conflict`; BitmapLockOrder models only accept/skip. Round 2 Q3, model next round |
| R3 | lock path and watchers | CONFIRMED mapping of C1 | heap_file.c:29646 scan cache watcher -> home watcher; locator_sr.c:15267 home unfix, heap_file.c:29602 fwd unfix, then LK_UNCOND_LOCK; :15421 refix after grant. Lock time, mode and life are not changed by any option (X at mark, no FOR UPDATE lock, other lifetimes: not proposed). Transient (statement-scoped) row locks exist (`locator_statement_ends_row_locks`): the model's 2PL-to-commit is stronger |
| R4 | lock cycles with other plans; order of common rows | CONFIRMED, C2 narrowed | see C2 sources; develop's order is per-buffer OID order when a session sets `index_scan_in_oid_order` (scan_manager.c:2575, PRM_FOR_SESSION). Round 2 Q2 |
| R5 | settle wait/write passes | STRUCK | both passes scan the same materialized list (query_executor.c `scan_targets:` reopens it; `assert (settle.next == settle.rows.size ())` :18321); the bitmap changes the list's order once, before either pass; nothing sorts or dedups between them |
| R6 | cached plan, ordered consumers | CONFIRMED as stated; no new hole | lock need per execution: query_executor.c:37069 (isolation, session `mvcc_reevaluate_at_force`, PRM_FOR_SESSION: test.md's "restart" is wrong); LIMIT -> inst_num/orderby_num (type_checking.c:7686-7731) refused by query_planner.c:3956; merge outer key_order :3885; px refuses FOR_UPDATE and DML (px_scan_checker.cpp:488,675) |
| R7 | row triggers, expressions | CONFIRMED | row triggers -> client DML (execute_statement.c:10229, 11622) -> lock at select (xasl_generation.c:26629): the narrow scope does not change trigger order (the ticket sentence is wrong there). RANDOM etc. are row-local (lock at force); serial, ROWNUM, session var, subquery -> lock at select (xasl_generation.c:25849); SP refused in both scopes (query_planner.c:3944, E48 of CBRD-28032) |
| R8 | verification inputs | ACCEPTED as the smoke/TC plan | no decision |

## Refinement map

| Model step | Code (CBRD-28032 b52b26697c) | One step because |
|---|---|---|
| `SFix` | scan_manager.c `scan_next_index_bitmap` → `scan_fix_bitmap_heap_page` | the page read latch is the protection of the row read |
| `STry` (granted) | locator_sr.c `locator_lock_and_get_object_internal` LK_COND_LOCK | one lock manager call under the page latch |
| `STry` (refused) | `locator_lock_object_unless_ours`: `pgbuf_ordered_unfix (home_page_watcher)` then LK_UNCOND_LOCK | unfix and the start of the blocking wait happen with no shared state read between |
| `SWait` | lock_manager.c grant to the waiter; `heap_prepare_get_context` then refixes (next `SFix`) | the grant is one lock manager step |
| `SEval` | `locator_get_settled_last_version` + scan reevaluation (`mvcc_reev_data`, range/key/data filter); reject → `lock_unlock_object_donot_move_to_non2pl` | under the page latch fixed by the preceding step |
| `SCommit` | transaction end releases the row locks (2PL) | |
| `WLock`/`WWait` | `locator_update_force`/`heap_update` row X lock of a single-row UPDATE | |
| `WLatch`/`WMod` | `heap_update` write latch, new version, unfix | one page write under the write latch |
| `Victim` | lock_manager.c `lock_select_deadlock_victim` (holder, active, less log, closer timeout, youngest); the victim's transaction is aborted (-72, develop probe) | |
| `SEval` conflict arm | locator_sr.c `locator_has_isolation_conflict` above RC | same step as the last-version read |
| `SEval` recompute | locator_sr.c:15640 `must_recompute` -> `locator_mvcc_reev_cond_and_assignment` | same step |
| `WMod` delete | heap_delete under the write latch | one page write |
| ForceOrder `Force` | query_executor.c qexec_execute_update `scan_targets` loop -> `locator_attribute_info_force`; btree.c unique check per key insert (HA) | one row of the force phase, one thread, no other writer |
| `OrdOf(s,k)` heap | `scan_bitmap_marks` partitions over VSID-sorted sectors, `w->order` sorted by page, over-width list sorted (`qfile_sort_list` Q_DISTINCT) | the order is fixed before the heap step starts |

## Fault table

| Fault | Modeled | Note |
|---|---|---|
| lock timeout, deadlock victim | yes | `Victim` on any lock-wait cycle |
| conditional latch failure | n/a | the heap step fixes unconditionally (`scan_fix_bitmap_heap_page`) |
| concurrent DML | yes | `W` moves WRow's key out of range |
| error return, interrupt, OOM, crash | not yet | |
| vacuum | not yet | CBRD-28032 BitmapHash covers a page vacuum deallocated |
| nested statement | n/a | a block with `PT_METHOD_CALL` is refused by `qo_plan_decide_bitmap_heap` |

## Mutants

| Mutant | Claim | Removes |
|---|---|---|
| BitmapLockOrder keep_latch | C1 | the home page unfix before the blocking lock wait |
| BitmapLockOrder unsorted | C2 | the VSID sort of the sectors (B's heap order differs from A's) |
| BitmapLockOrder no_reev | C3 | the range reevaluation on the last version (C3a) |
| BitmapLockOrder stale_set | C3 | the recompute of SET on the last version (C3b, lost update) |
| BitmapLockOrder rr_skip | C3 | the serialization conflict above RC (C3c) |
| ForceOrder heap_ha_unique | C4 | D1 |
| ForceOrder heap_numbering | C5 | D4 |
| ForceOrder (C6) | C6 | C6 holds by the per-row code with no order-dependent input: `PlainSame` is a conjunct of IndInv; the mutants that break it are D1/D4's, whose inputs are the order-dependent ones |

## Witnesses

| Witness | Outcome |
|---|---|
| BitmapLockOrder witness-mixed-victim | a heap-order and a key-order statement make a lock cycle (a victim) |
| BitmapLockOrder witness-rejected | a row the writer moved out of range is rejected and unlocked |
| BitmapLockOrder witness-deleted-skip | a row the writer deleted is skipped |
| BitmapLockOrder witness-recomputed | a row the writer bumped gets c = 11 (recomputed from the last version) |
| BitmapLockOrder witness-rr-conflict | above RC a changed row fails the statement |
| BitmapLockOrder witness-done | all three finish |
| ForceOrder witness-heap-plain | a row-local UPDATE is written in heap order |
| ForceOrder witness-heap-unique-no-ha | without HA a unique-column UPDATE is written in heap order and succeeds |

## Dead expressions

| Expression | Why dead |
|---|---|
| BitmapLockOrder.tla:173 BitmapLockOrder.tla:174 BitmapLockOrder.tla:175 BitmapLockOrder.tla:176 (`SEval` conflict arm) | the serialization conflict arm runs only with Iso = "rr"; it fires in `rr`, `witness-rr-conflict`, `mutant-rr-skip` is its removal |
| BitmapLockOrder.tla:240 BitmapLockOrder.tla:241 BitmapLockOrder.tla:242 BitmapLockOrder.tla:243 BitmapLockOrder.tla:244 BitmapLockOrder.tla:245 (`Victim` body) | in the same-plan cfgs (main, rr, today, scale-3) no lock cycle forms: that is C2. It fires in `mixed`, `witness-mixed-victim`, `mutant-unsorted` |
| ForceOrder.tla:69 ForceOrder.tla:70 (`Force` duplicate arm) | an intermediate duplicate needs the heap order on an HA unique-column UPDATE, which D1 forbids: it fires only in `mutant-heap-ha-unique` (C4) |

## Bounds

BitmapLockOrder: NR = 2 rows on one page, two locking UPDATEs, one single-row writer (move, bump or delete), RC and
RR; scale NR = 3. Row locks are held to the statement's end (commit); the code's transient (statement-scoped) row
locks end no later, so the model's waits are a superset. ForceOrder: N = 2 rows, scale N = 3, HA and non-HA.
Apalache: IndInv of both modules for every WRow, plan pair, isolation and HA value (CInit).

## Result

2026-11-24 record run after round 3 (D6..D9, HA probe): `RESULT: OK`, run dir `.git_ignored_dir/scratch/tla/CBRD-28326-20261124-190555-2687805` (round 2 run: `CBRD-28326-20261124-183254-2426601`, same specs and cfgs).
BitmapLockOrder: main 1619/929 states depth 19; rr 1371/747; today 1418/829; mixed 1925/1122; scale-3 2027/1157 depth 25;
5 mutants and 6 witnesses as expected. ForceOrder: main 12/9 depth 3, no-ha 12/9, scale-3 15/12; 2 mutants, 2 witnesses.
Apalache: `BitmapLockOrder.apalache-indinv` (54 s), `ForceOrder.apalache-indinv` (6 s) pass over CInit
(every WRow, plan pair, isolation, HA value). TLAPS 요청 없음. Trace validation: trace-exempt (no implementation).
spec sha256: BitmapLockOrder.tla eb08e410c3f0449f1a71d240edcec844cad77a1855ddc6b5ea85ea729f8a543d,
ForceOrder.tla 1cc4f622a06bfd080e2870889510f787b505b62db68437dde56af2aef7d6f452.
Engine sha the map reads: CBRD-28032 b52b26697c; develop probe on 030b650ff optdebug.
