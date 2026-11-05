# CBRD-26425 atomic latch — TLA+ map

Model of the page-buffer atomic latch introduced by CBRD-26425 (PR #6704, merge `58cef8e01f`,
2026-01-14) as it stands on develop `21c6e635d` (2026-11-05), after the follow-ups that touched it:
CBRD-26657 (#6969), CBRD-27084 (#7487, `e8b961468`: waiter_exists reconcile + idle heal),
CBRD-26908/26941 (fix/unfix counters), CBRD-27512 (`pgbuf_timed_sleep` interrupt).

- `AtomicLatch.tla` — code-level model: the 64-bit word, the BCB mutex, the lock-free READ fix and
  unfix, the wait queue, latch timeout, wakeup, promotion, flush waiters, the flush daemon's
  post-flush hand-off, flush errors, the FLUSH waiter's interrupt, page invalidation, and (with
  `TornReads`) a lock-free path that lands on a BCB holding another page. `Code` selects which of
  the six holes (H1–H4, A, E, below) are kept as the code has them; `Code = {}` is the candidate fix.
- `PageLatch.tla` — the latch semantics without the encoding (mode, holders, waiter bit, queued
  readers/writers, page). `AtomicLatch` refines it (`PROPERTY Refines`); its `IndInv` is proved by
  TLAPS (`PageLatch_proofs.tla`).

## Claim and sources

| Claim | Statement | Kind | Source |
|---|---|---|---|
| C1 | `fcnt` equals the number of fixes the threads hold (or were handed), and `latch_mode = PGBUF_NO_LATCH` exactly when `fcnt = 0`; it never goes negative | safety | `pgbuf_unlatch_bcb_upon_unfix` header ("If FixCount becomes 0 … set LatchMode = NO_LATCH"); `pgbuf_wakeup_reader_writer` assert `latch_mode == PGBUF_NO_LATCH && fcnt == 0`; the pre-atomic code it replaced (`58cef8e01f^`) kept fcnt under the BCB mutex; PR #6704 purpose: replace the BCB mutex by an atomic latch for performance (same semantics) |
| C2 | a WRITE latch has exactly one holder and no reader beside it; an idle latch has no holder | safety | page latch semantics (`PGBUF_LATCH_WRITE` / `PGBUF_LATCH_READ` in `page_buffer.h`); PR #6704 purpose |
| C3 | `pgbuf_fix (vpid)` returns the BCB of `vpid` | safety | `pgbuf_fix` contract (`page_buffer.h`), callers cast the result to the page of `vpid` |
| C4 | while a reader or writer waits in the BCB queue, `waiter_exists` is set (the lock-free paths rely on it to stay off) | safety | `pgbuf_lockfree_fix_ro` / `pgbuf_lockfree_unfix_ro` guards; comment at `pgbuf_wake_flush_waiters` ("all waiter_exists transitions are bcb-mutex-protected"); CBRD-27084 PR description |
| C5 | a thread holding the BCB mutex never spins in the idle-grant CAS, and the CBRD-27084 heal never fires | safety | CBRD-27084 PR #7487 description (livelock: idle grant force-expects `waiter_exists == false`); comment at `pgbuf_latch_bcb_upon_fix` ("diag builds: catch any future leak at its first victim") |
| C6 | `pgbuf_wakeup_reader_writer`'s CAS never fails, so it never re-runs `thread_lock_entry` on an entry it already holds | safety | code shape at `pgbuf_wakeup_reader_writer` (`thread_lock_entry` inside the CAS `do … while`); POSIX: a default mutex relocked by its owner deadlocks |
| C7 | no waiter is stranded: an idle latch with a free BCB mutex has no queued reader/writer, and every thread and flusher finishes | safety + liveness | `pgbuf_unlatch_bcb_upon_unfix` header ("wake up the threads on the BCB waiting queue"); `pgbuf_wakeup_reader_writer` "how it works" comment |
| C8 | every flush attempt ends by clearing FLUSHING and waking the FLUSH waiters — success, I/O error, an error before the write, or the post-flush daemon's turn — and a failed attempt leaves the page DIRTY | liveness | `pgbuf_bcb_flush_with_wal` "how this works" comment ("if writing fails, we revert changes (restore dirty flag and oldest_unflush_lsa)"; "lock bcb again, clear is flushing status, wake up of threads waiting for flush"); `PGBUF_BCB_INVALID_VICTIM_CANDIDATE_MASK` comment ("bcb's that are in the process of being flushed cannot be victimized. flush must succeed!") |

## Refinement map (model -> code)

Code at `21c6e635d`, `src/storage/page_buffer.c`.

| Model | Code | One step because |
|---|---|---|
| `word` | `bufptr->atomic_latch` (`PGBUF_ATOMIC_LATCH_IMPL`: `latch_mode`, `waiter_exists`, `fcnt`) | every change is one CAS on the 64-bit word |
| `mtx` | `PGBUF_BCB_LOCK` / `PGBUF_BCB_UNLOCK` (`bufptr->mutex`) | — |
| `vpid` | `bufptr->vpid` | written only under the BCB mutex with `fcnt = 0` and an empty queue (victim claim) |
| `valid` | the BCB is reachable in the hash chain under `vpid`: FALSE after `pgbuf_invalidate_bcb` (`pgbuf_delete_from_hash_chain`, `pgbuf_put_bcb_into_invalid_list`) until a claim reuses it | under the BCB mutex (and the bucket mutex) |
| `ioErr`, `pfPend` | the flush in flight failed; the BCB sits in `pgbuf_Pool.flushed_bcbs` with FLUSHING set | flusher-local; the queue is consumed under the BCB mutex |
| `errLeft`, `envLeft` | fault budgets (flush errors, invalidations) | — |
| `q`, `req`, `reqf`, `resumed`, `promoter` | `bufptr->next_wait_thrd` chain; `thread_p->request_latch_mode`, `request_fix_count`, `resume_status`, `wait_for_latch_promote` | queue changes under the BCB mutex; `req` / `resumed` changes under the waiter's entry lock (`thread_lock_entry`) |
| `hold` | `holder->fix_count` (thread-local holder entry) | thread-owned |
| `dirty`, `flushing`, `async` | `PGBUF_BCB_DIRTY_FLAG`, `PGBUF_BCB_FLUSHING_TO_DISK_FLAG`, `PGBUF_BCB_ASYNC_FLUSH_REQ` | `pgbuf_bcb_update_flags` under the BCB mutex |
| `Begin` | `pgbuf_fix` entry (`pgbuf_fix_release`/`_debug`), `pgbuf_promote_read_latch` entry | thread-local choice |
| `LfLoad` | `pgbuf_lockfree_fix_ro`: `pgbuf_search_hash_chain_no_bcb_lock` + `get_impl` + the mode/waiter/fcnt test | the hash search and the load read unprotected state; the vpid test after them is split off (`LfVpid`). The walk takes neither the bucket mutex nor a BCB mutex: with `TornReads` it may return a BCB that holds another page (a BCB moved to another chain mid-walk, or a vpid compare torn against the claimer's write); BCBs are a static array, so the pointer is never freed |
| `LfVpid` | `pgbuf_lockfree_fix_ro`: `bufptr->vpid.pageid != vpid->pageid ...` | a plain read with no protection; with `TornReads` it may pass for another page (two separate 4-byte reads) |
| `LfCas` | `pgbuf_lockfree_fix_ro`: `compare_exchange_weak` fcnt+1, then holder `fix_count++` | one CAS; the holder update is thread-local |
| `LfRecheck` | candidate fix for H1 (re-read `bufptr->vpid` after the CAS; the fix now pins the BCB) | absent in the code (`Code ∋ "H1"` skips it) |
| `Use` | `pgbuf_fix` returns `pgptr` (`fast_path:` or the end of the slow path) | — |
| `Lock(m_lock → m_fix)` | `pgbuf_search_hash_chain` → `PGBUF_BCB_LOCK`, or `pgbuf_claim_bcb_for_fix` | mutex acquire |
| `MFix` | `pgbuf_latch_bcb_upon_fix`: CBRD-27084 heal check, the CAS loop (idle grant, case 1, 2-1, 2-2, 3), then grant / conditional reject / `pgbuf_block_bcb` → `pgbuf_timed_sleep` (`thread_lock_entry`, `PGBUF_BCB_UNLOCK`); not-resident branch = `pgbuf_claim_bcb_for_fix` victim + idle grant with `buf_lock_acquired` | all under the BCB mutex; the CAS loop decides only from the word and thread-owned state, so it is one step at its successful CAS; enqueue and unlock happen with the waiter's entry lock held |
| `PrFix` | `pgbuf_promote_read_latch_release` (SHARED_READER): in-place promote, fail, or `pgbuf_block_bcb (…, as_promote = true)` | under the BCB mutex |
| `Woken` | `pgbuf_timed_sleep` returns `NO_ERROR` with `THREAD_PGBUF_RESUMED`; caller allocates the holder with `request_fcnt` | the waiter's entry lock |
| `Timeout` | `pgbuf_timed_sleep`, interrupt (`r == NO_ERROR`, not resumed): `thread_lock_entry` again (7397), re-check `resume_status`, `request_latch_mode = PGBUF_NO_LATCH` (7406); with `"A"` fixed, also the timed-out branch, re-locked the same way | under the entry lock; disabled while a waker holds that lock (`EntryLocked`) |
| `TimedOut` | `"A"`: `thread_suspend_timeout_wakeup_and_unlock_entry` returns `ER_CSS_PTHREAD_COND_TIMEDOUT` after `thread_p->unlock ()` (`thread_entry.cpp:600`) | the timed wait itself ends under the entry lock; everything after it in this branch runs without it |
| `ToChk` | `"A"`: `if (thread_p->resume_status == THREAD_PGBUF_RESUMED)` (7420) → success; else `logtb_is_current_active` (7426) | an unprotected read |
| `ToRetry` | `"A"`: `goto try_again` → `thread_p->resume_status = THREAD_PGBUF_SUSPENDED` (7392), sleep again | an unprotected write: a grant between `ToChk` and here is wiped |
| `ToSet` | `"A"`: `thread_p->request_latch_mode = PGBUF_NO_LATCH` (7436), `thread_unlock_entry` of an entry lock it does not hold (7437) | an unprotected write: a grant between `ToChk` and here is dropped |
| `Eh` | `pgbuf_timed_sleep_error_handling` cases 1–3 (queue removal) | under the BCB mutex |
| `EhLoop` | case 3 loop: `get_impl`, test `curr_thrd_entry->request_latch_mode` (no entry lock), CAS `fcnt += request_fix_count` | the CAS; H2 keeps the entry-lock re-check as its own step `EhLk` |
| `EhLk` | case 3 loop: `thread_lock_entry (curr_thrd_entry)`, re-test `request_latch_mode`, dequeue + `pgbuf_wakeup` or `thread_unlock_entry` + break | entry lock section |
| `Unfix` | `pgbuf_unfix`: `pgbuf_unlatch_thrd_holder` then `pgbuf_lockfree_unfix_ro` (READ, no waiter, fcnt ≠ 1) | the lock-free CAS; holder decrement is thread-local |
| `Lock(uf_lock → uf_unl)`, `UfUnl` | `PGBUF_BCB_LOCK`, `pgbuf_unlatch_bcb_upon_unfix` fcnt−1 CAS (NO_LATCH at 0; the `fcnt < 0` assert branch → `negFcnt`) | under the BCB mutex |
| `Wk`, `WkCas` | `pgbuf_wakeup_reader_writer`: per waiter, skip NO_LATCH/FLUSH, `thread_lock_entry`, re-test, CAS grant, `pgbuf_wakeup`; the final `waiter_exists` reconcile (`WkEnd`) | under the BCB mutex; the load and the CAS are split so a concurrent lock-free CAS would show as `doubleLock` |
| `UfAsync` | `pgbuf_bcb_is_async_flush_request` → `pgbuf_bcb_safe_flush_force_unlock (…, false)` | under the BCB mutex |
| `StartFlush` | `pgbuf_bcb_flush_with_wal` up to `PGBUF_BCB_UNLOCK` (11012): `pgbuf_bcb_mark_is_flushing` (FLUSHING on, DIRTY off), the page copy (`tde_encrypt_data_page`, `dwb_set_data_on_next_slot`), which may return an error at 10986 / 10998 with the BCB still locked (`"E"`); the fix does what the I/O error path does (11079–11088) | under the BCB mutex |
| `FzDec` | `pgbuf_bcb_safe_flush_internal (synchronous = true)` from `pgbuf_flush_seq_list` (checkpoint), `pgbuf_flush_all_helper` (`xbtree_load_index`, `log_final`, backup's `pgbuf_flush_all_unfixed`, …): immediate flush, or `waiter_exists = TRUE` + `pgbuf_block_bcb (PGBUF_LATCH_FLUSH)`; a flusher in `Daemons` is `pgbuf_flush_victim_candidates` / `pgbuf_flush_neighbor_safe`, which skip a page they cannot flush now | under the BCB mutex |
| `FlIo` | `pgbuf_bcb_flush_with_wal` after the unlock: WAL + `fileio_write` / `dwb_add_page`; an error (11077) or, for the page flush daemon under victim pressure, `pgbuf_Pool.flushed_bcbs->produce` + post-flush wakeup without relocking (11098) | the write runs with no BCB mutex: any fix, write and re-dirty interleave here |
| `Lock(fl_relock → fl_done)`, `FlDone` | `PGBUF_BCB_LOCK`, `pgbuf_bcb_mark_was_flushed` or, on error, `pgbuf_bcb_mark_was_not_flushed (was_dirty)`, `pgbuf_wake_flush_waiters` (+ CBRD-27084 reconcile) | under the BCB mutex |
| `PostFlush` | `pgbuf_assign_flushed_pages` (post-flush daemon): `PGBUF_BCB_LOCK`, maybe `pgbuf_assign_direct_victim` (the victim waiter claims the BCB later, `MFix`), `pgbuf_bcb_mark_was_flushed`, `pgbuf_wake_flush_waiters` | under the BCB mutex; weak fairness (the daemon runs on its wakeup and its period) |
| `Inval` | `pgbuf_invalidate` (after the last unfix: `fcnt == 0`, not `pgbuf_bcb_avoid_victim`), `pgbuf_invalidate_all` (after its flush), `pgbuf_copy_temp_page_to_area_and_discard` (not `pgbuf_is_bcb_fixed_by_any`, not flushing, no async request; a dirty page is discarded) → `pgbuf_invalidate_bcb` | under the BCB mutex; a fault-like environment step (budget `MaxEnv`) |
| `FzIntr`, `Lock(fz_ilock → fz_irm)`, `FzIrm` | `pgbuf_block_bcb (PGBUF_LATCH_FLUSH)` after `thread_suspend_wakeup_and_unlock_entry` without RESUMED: `PGBUF_BCB_LOCK`, remove itself, reconcile `waiter_exists`, `ER_INTERRUPTED` | the wake is an interrupt fault; the removal is under the BCB mutex |
| `FzWait`, `FzNext` | the FLUSH waiter resumes; the flusher's next page | thread-local |

Callers of the entry points (code-index `callers`): `pgbuf_lockfree_fix_ro` ← `pgbuf_fix` only;
`pgbuf_lockfree_unfix_ro` ← `pgbuf_unfix` only; `pgbuf_latch_bcb_upon_fix` ← `pgbuf_fix`;
`pgbuf_block_bcb` ← `pgbuf_latch_bcb_upon_fix`, `pgbuf_promote_read_latch`,
`pgbuf_bcb_safe_flush_internal`; `pgbuf_timed_sleep_error_handling` ← `pgbuf_timed_sleep`;
`pgbuf_wake_flush_waiters` ← `pgbuf_bcb_flush_with_wal` (both exits), `pgbuf_assign_flushed_pages` (post-flush daemon).
`pgbuf_invalidate_bcb` ← `pgbuf_invalidate`, `pgbuf_invalidate_all`, `pgbuf_copy_temp_page_to_area_and_discard`
(and `pgbuf_unfix_debug` under `CUBRID_DEBUG` only); `pgbuf_bcb_flush_with_wal` ← `pgbuf_flush_victim_candidates`,
`pgbuf_flush_neighbor_safe` (page flush daemon), `pgbuf_bcb_safe_flush_internal`; `pgbuf_bcb_safe_flush_internal`
← `pgbuf_flush_seq_list`, `pgbuf_bcb_safe_flush_force_unlock`, `pgbuf_bcb_safe_flush_force_lock`.
Exit paths: conditional reject (`Reject`), latch timeout (`Timeout`, `TimedOut`…`ToSet`), interrupt
(`Timeout`, `FzIntr`), promotion fail (`PrFix`), fcnt underflow (`negFcnt`), flush errors before the
write (`StartFlush`) and of the write (`FlIo` → `FlDone`), post-flush hand-off (`FlIo` → `PostFlush`),
invalidation (`Inval`).

## Properties

| Property | Claims | Where | Checked by |
|---|---|---|---|
| `FcntExact` | C1 | `AtomicLatch.tla` | TLC invariant |
| `Refines` (`PageLatch!Spec`) | C2, C4 | `AtomicLatch.tla` → `PageLatch.tla` | TLC refinement; `PageLatch`'s `Exclusive`, `WaiterBit` proved by TLAPS |
| `SamePage` | C3 | `AtomicLatch.tla` | TLC invariant |
| `NoSpin` | C5 | `AtomicLatch.tla` | TLC invariant |
| `NoDoubleLock` | C6 | `AtomicLatch.tla` | TLC invariant |
| `NoStrandedWaiter`, `AllDone` | C7 | `AtomicLatch.tla` | TLC invariant, TLC liveness (weak fairness per thread and flusher; deadlock check on) |
| `AllDone`, deadlock check | C8 | `AtomicLatch.tla` | a FLUSH waiter that is never woken leaves its flusher short of `Done`: TLC reports the deadlock (every other process done) or the liveness violation |

## Fault model

| Fault | Modeled? | Where / why not |
|---|---|---|
| error return | yes: conditional reject, promotion fail, fcnt underflow branch; flush errors at both points they can occur — before the write with the BCB locked (`tde_encrypt_data_page` `ER_TDE_CIPHER_IS_NOT_LOADED`, `dwb_set_data_on_next_slot` ← `dwb_acquire_next_slot` `ER_DWB_DISABLED` / wait errors: `StartFlush`) and of the write (`fileio_write`, `dwb_add_page`: `FlIo` → `FlDone`), budget `MaxErr` | holder-entry allocation failure (`assert (false)` "must not occur") not modeled |
| interrupt / query cancel | yes | `Timeout` is the interrupted wake (`r == NO_ERROR`, not resumed, re-locked); `TimedOut`…`ToSet` is the timed-out wake as the code has it (`"A"`); `FzIntr` → `FzIrm` is the FLUSH waiter's interrupt in `pgbuf_block_bcb` |
| lock timeout, deadlock victim | yes (as latch timeout) | page latches have no deadlock detector; the latch timeout is the victim mechanism (`Timeout`, budget `MaxTimeouts`) |
| conditional latch failure | yes | `fixWc`, `fixRc` ops; `PrFix` fail branches |
| OOM | n/a | the protocol allocates nothing but holder entries (pre-allocated per thread) |
| crash / `kill -9` | n/a | the latch word and queue are volatile; recovery rebuilds the buffer pool empty |
| spurious wakeup | yes | a wakeup without `RESUMED` is the interrupt path (`Timeout`) |
| concurrent DML | yes | any thread fixes WRITE and re-dirties the page (`UfUnl` sets `dirty`) |
| vacuum | n/a | vacuum fixes pages through the same `pgbuf_fix`/`pgbuf_unfix`; `PGBUF_BCB_TO_VACUUM_FLAG` only steers LRU placement |
| checkpoint, page flush, page replacement | yes | flushers (`FzDec` = checkpoint / `pgbuf_flush_all` / backup, `FlIo` = the I/O window), the page flush daemon (`Daemons`) and its post-flush hand-off (`PostFlush`, direct victim), async flush on unfix, victim claim in `MFix` |
| page invalidation, deallocation | yes | `Inval` (the three callers of `pgbuf_invalidate_bcb`); the BCB is reused for any page by a later claim (`MFix` from `valid = FALSE`) |
| concurrent rehash under the lock-free walk, torn vpid read | yes, over-approximated | `TornReads = TRUE`: `LfLoad` / `LfVpid` may accept a BCB that holds another page or none; checked in `fix-ext-torn` and `witness-reclaim-after-inval` bounds |
| several BCBs | partly | one BCB carries every interleaving of its own word, queue and vpid; a second BCB adds only the hash walk landing on the wrong BCB, which `TornReads` covers. Latch order across pages is the caller's (`pgbuf_ordered_fix` and the latch timeout as the deadlock breaker) and was not changed by PR #6704 |
| memory order | argued, not modeled | TLC runs every step sequentially consistent; see "Memory order" below |
| SA mode | n/a | `pgbuf_block_bcb` and `pgbuf_timed_sleep` compile to nothing in SA; the parallel-query files that could add threads compile only into the server (code-index `{server}`), so one thread owns the buffer pool |
| `pgbuf_simple_fix` (temp pages) | n/a by contract | it adds to `fcnt` with `NO_LATCH` and "Cannot be mixed with general FIX(LATCH)" (its header). Mixing breaks the old code too (a latched unfix then leaves `fcnt > 0`, so the latch is never released), so it is not a regression of this PR; its callers (`qfile_put_next_sort_item`, `file_destroy`, `file_sector_map_dealloc_temp`) touch temp pages that the same thread owns |
| holder watchers (`pgbuf_ordered_fix`) | n/a | the watcher list lives in the thread's holder entry; ordered fix reaches the latch only through `pgbuf_fix` / `pgbuf_unfix` with conditional modes (`fixRc`, `fixWc`) and was not changed by PR #6704 |
| HA log apply | n/a | no latch-protocol difference |
| fairness | weak fairness on every thread and flusher; none on `Timeout` (a fault) | the BCB mutex is not FIFO; termination holds because every process has a finite budget |

## Mutants

| Mutant cfg | Re-enables | Claim | Expect |
|---|---|---|---|
| `mutant-lf-unfix-last` | lock-free unfix of the last fix (drops `fcnt ≠ 1`) | C1 | violation `FcntExact` |
| `mutant-lf-any-mode` | lock-free fix on a WRITE latch | C2 | refinement |
| `mutant-lf-no-vpid-check` | lock-free fix without any vpid check | C3 | violation `SamePage` |
| `mutant-block-no-bit` | queue a waiter without setting `waiter_exists` | C4 | refinement |
| `mutant-flush-wake-no-clear` | `pgbuf_wake_flush_waiters` before CBRD-27084 (no reconcile) | C5 | violation `NoSpin` |
| `mutant-lf-fix-ignores-bit` | lock-free fix while a waiter is queued | C6 | violation `NoDoubleLock` |
| `mutant-unlatch-no-wakeup` | last unfix does not wake the queue | C7 | violation `NoStrandedWaiter` |
| `mutant-flerr-no-wake` | the I/O error path does not wake the FLUSH waiters | C8 | deadlock |
| `mutant-flush-intr-no-clear` | an interrupted FLUSH waiter leaves `waiter_exists` set | C5 | violation `NoSpin` (the CBRD-27084 heal fires) |

## Findings

Every counterexample below was read step by step; each step maps to a code site of the table
above and no protection forbids the interleaving (classification: **hole**, not model error).

Trackers: H1 = CBRD-27970, H4 = CBRD-27971 (filed 2026-11-06); H2 = CBRD-27739 cause B and
A = CBRD-27739 cause A (both in its comment of 2026-10-27); H3 = CBRD-27370; E is not filed.

### H1 — lock-free READ fix can return another page (ABA on the latch word)

`pgbuf_lockfree_fix_ro` checks `bufptr->vpid` before its CAS and never after. The CAS compares only
`{latch_mode, waiter_exists, fcnt}`, which can return to the same value after the BCB was released,
victimized and claimed for another page.

`AtomicLatch.code-h1` (`SamePage`, depth 20): t1 holds p1 READ `(R,0,1)` → t2 `LfLoad` loads
`(R,0,1)`, `LfVpid` sees p1 → t1 unfixes `(N,0,0)` → t1 fixes p2: the clean, unfixed BCB is claimed
for p2 and latched `(R,0,1)` → t2 `LfCas` `(R,0,1)→(R,0,2)` succeeds → `pgbuf_fix (p1)` returns p2.
Fix (`LfRecheck`, `fix-all`): after the CAS the BCB is pinned, so re-read `bufptr->vpid`; on a
mismatch unfix and fall back to the slow path.

**Runtime reproduction (confirmed)** — Instrumented optdebug build of `21c6e635d` (scratch worktree `tla-latch-repro`, env-gated TLATRACE + delay injection, patch `.git_ignored_dir/scratch/tla-latch-repro-instrument.patch`, never committed), CS mode, `page_latch_timeout_in_msecs=2000`, `lock_timeout=10`; scripts and traces in `.git_ignored_dir/scratch/tla-latch-run/`. libcubrid `8f2845ef…`, `data_buffer_size=16M`, `h1.sh`: session B's READ fix of t's PK root 1|641 held 3 s (injection), session A's lock-free fix of 1|641 loaded `(R,0,1)` and passed the vpid check; the injection kept that window open until the BCB held another page with the same word (`lf_window_close … matched=1 now=1|3992`); the real CAS then succeeded: `lf_aba want=1|641 got=1|3992 fcnt=2`. A's statement compile (`catalog_fetch_btree_statistics`, `root_vpid = 1|641`) asserted in `pgbuf_check_page_ptype` on the heap page it got (`core.transaction.2189383`). A release build has no ptype assert: the caller reads the other page.

### H2 — latch timeout handler leaks a fix count

`pgbuf_timed_sleep_error_handling` case 3 reads the next waiter's `request_latch_mode` without its
entry lock, CASes `fcnt += request_fix_count`, and only then locks the entry and re-checks. If that
waiter timed out in between, the handler breaks out without undoing the add. The pre-atomic code
(`58cef8e01f^`) added after the re-check.

`AtomicLatch.code-h2` (`FcntExact`, depth 17): t1 holds READ → t2 asks WRITE and queues → t3 asks
READ and queues behind it → t2 times out, takes the mutex, is head, removes itself → t2 `EhLoop`
adds t3's 1 (`fcnt` 2) → t3 times out (`request_latch_mode = NO_LATCH`) → t2 `EhLk` sees NO_LATCH,
breaks. `fcnt` stays one above the holders forever: the page never becomes idle, every WRITE fix
of it times out, it can never be victimized.
Fix: test under `thread_lock_entry` first, CAS after (the old order; `fix-all`, `fix-all-3t`).

**Runtime reproduction (confirmed)** — Instrumented optdebug build of `21c6e635d` (scratch worktree `tla-latch-repro`, env-gated TLATRACE + delay injection, patch `.git_ignored_dir/scratch/tla-latch-repro-instrument.patch`, never committed), CS mode, `page_latch_timeout_in_msecs=2000`, `lock_timeout=10`; scripts and traces in `.git_ignored_dir/scratch/tla-latch-run/`. libcubrid `69f2882b…`, `h2.sh`: S1's READ fix held 8 s (injection; it also held t2's heap header 1|769), S2 `UPDATE t2` queued for WRITE on 1|769, S3 `SELECT` queued for READ behind it, 800 ms injected between the handler's CAS and its `thread_lock_entry`. Trace: `latch_timeout 1|769` (S2) → `eh_cas 1|769 add=1 fcnt=2` → `latch_timeout 1|769` (S3, 190 ms later) → `eh_leak 1|769 req=0 fcnt=2`. After S1 finished, every later statement on t2 failed with `timed out waiting on READ on page 1|769` (a new UPDATE, then a plain SELECT 20 s later), while other tables answered: the leaked count plus the stale `waiter_exists` block t2's header page for good, readers included.

### H3 — a READ holder's WRITE fix sets `fcnt = 1`

`pgbuf_latch_bcb_upon_fix` sub-case 2-2 (holder alone on a READ latch asks WRITE) sets
`new_impl.impl.fcnt = 1` while `holder->fix_count++`; with h read fixes the word says 1 and the holder
h+1. The pre-atomic code did `fcnt++`, and in debug builds refused the request (`assert (false)`,
`ER_FAILED`: "nested write mode fix … must not occur").

`AtomicLatch.code-h3` (`FcntExact`, depth 9): t1 fixes READ `(R,0,1)`, then `pgbuf_fix (WRITE)` on
the same page → `(W,0,1)`, `hold` 2. The first unfix idles the latch while t1 still holds a fix
(C2 broken), the second underflows. Fix: `fcnt + 1` (`fix-all`). Open: whether any caller issues
such a fix (the old code treated it as a contract violation).

**Runtime reproduction: none (open question).** The instrumented build traced every hit of this branch (`h3_upgrade`) and of `promote_needed`; across the H1, H2 and H4 runs neither fired. H3 stays a question: its code cfg fails, and no caller reaching it is known.

### H4 — idle grant spins while a FLUSH waiter is queued (residual of CBRD-27084)

The idle-grant CAS in `pgbuf_latch_bcb_upon_fix` force-expects `waiter_exists == false`. A synchronous
flusher that finds the page being flushed sets `waiter_exists` and queues as `PGBUF_LATCH_FLUSH`
while the latch is `NO_LATCH`. The CBRD-27084 heal only fires on an empty queue, so the next fixer
CASes forever holding the BCB mutex; the flushing thread can never relock the BCB to finish.

`AtomicLatch.code-h4` (`NoSpin`, depth 19): f2 (flush daemon) marks flushing, clears DIRTY, unlocks
for the write → t2 fixes WRITE, updates, unfixes (DIRTY again) → f1 (`pgbuf_flush_all` /
checkpoint, synchronous) sees DIRTY + FLUSHING → `waiter_exists = 1`, queues FLUSH, latch `NO_LATCH`
→ t1 fixes the page → idle grant CAS fails forever with the BCB mutex held. Pre-atomic code granted
an idle latch regardless of flush waiters.
Fix: the idle grant keeps the observed `waiter_exists` (`fix-all`, `fix-all-2f`).

**Runtime reproduction (confirmed)** — Instrumented optdebug build of `21c6e635d` (scratch worktree `tla-latch-repro`, env-gated TLATRACE + delay injection, patch `.git_ignored_dir/scratch/tla-latch-repro-instrument.patch`, never committed), CS mode, `page_latch_timeout_in_msecs=2000`, `lock_timeout=10`; scripts and traces in `.git_ignored_dir/scratch/tla-latch-run/`. libcubrid `d8a8ddc1…`, `h4c.sh`: a 20 s I/O window injected only for page 1|705 (t's first heap page). `cubrid backupdb -C` → `pgbuf_flush_all_unfixed` began flushing 1|705 (`flush_io_begin 1|705`); an UPDATE re-dirtied it; `cubrid loaddb -C -i --no-logging-index` on a 1M-row table (parallel build, so `xbtree_load_index` runs `pgbuf_flush_all`) queued as FLUSH waiter: `flush_wait 1|705 latch=0 w=1 fcnt=0 flushing=1`; a `SELECT` on t then spun: `idle_spin 1|705 latch=0 w=1 fcnt=0 queue_empty=0`, 87–94 % CPU, gdb `pgbuf_latch_bcb_upon_fix` ← `pgbuf_ordered_fix` ← `heap_prepare_object_page`. At +20 s the backup thread finished its I/O and blocked for good in `pthread_mutex_lock` ← `pgbuf_bcbmon_lock` ← `pgbuf_bcb_flush_with_wal`; loaddb stayed suspended in `pgbuf_block_bcb` ← `pgbuf_flush_all`. `cubrid server stop` timed out; SIGTERM ended the server. Either side can be any synchronous `pgbuf_bcb_safe_flush_internal` caller — `pgbuf_flush_all` (loaddb `--no-logging-index` parallel build, the CBRD-27084 entry; `log_final`), `pgbuf_flush_all_unfixed` (backup), `pgbuf_flush_seq_list` (checkpoint) — against any in-flight flush of an unfixed page; in this run backup's flush was in flight and loaddb's waited. A serial index build is demoted to the logged path and never calls `pgbuf_flush_all` (first attempts with a 2000-row table showed no flush at all).

### A — a timed-out waiter checks and gives up without its entry lock (CBRD-27739 cause A)

`thread_suspend_timeout_wakeup_and_unlock_entry` returns `ER_CSS_PTHREAD_COND_TIMEDOUT` after
unlocking the entry (`thread_entry.cpp:600`). `pgbuf_timed_sleep`'s branch then reads `resume_status`
(7420), may `goto try_again` (7428, which writes `resume_status = SUSPENDED` at 7392 and sleeps again
without the lock), writes `request_latch_mode = PGBUF_NO_LATCH` (7436) and calls `thread_unlock_entry`
on a lock it does not hold (7437). A waker (`pgbuf_wakeup_reader_writer`) that takes the entry lock in
between hands the waiter the latch (fcnt added, dequeued, RESUMED); the waiter then drops it. Present
in 11.4.6 as well (the user's CBRD-27739 analysis, comment 4777306); the interrupt branch above it
(7397) re-locks and is correct.

`AtomicLatch.code-a` (`FcntExact`, depth 16): t1 fixes WRITE → t2 asks WRITE and queues → t1 takes
the mutex to unfix → t2 times out (`TimedOut`), reads `resume_status` unlocked: not resumed (`ToChk`)
→ t1's unfix idles the latch and its waker hands t2 WRITE (`(W,1,1)`, t2 RESUMED, dequeued) → t2's
`try_again` writes SUSPENDED (`ToRetry`) and sleeps: the grant is lost, the latch is WRITE with no holder.
The other order (`ToSet`, the `NO_LATCH` write after the grant) is the one the runtime run took.
Fix: re-take the entry lock first, as the interrupt branch does (`Timeout`; every fix cfg).

**Runtime reproduction (confirmed)** — the instrumented build above plus a precondition-waiting window
at 7420 (P26): libcubrid `4bd26fa2…`, `ha.sh`, trace `trace-a.log`. S1's scan of t2 holds 1|769 READ
(2.5 s injected hold), S2 `UPDATE t2` queues WRITE on 1|769 and times out at 2 s: `to_chk 1|769
resumed=0` → `wk_grant 1|769 mode=2 latch=2 fcnt=1` (S1's unfix hands S2 WRITE) → `to_window_close
resumed=1 latch=2 fcnt=1` → `latch_timeout 1|769 req=2 resumed=1` (S2 writes NO_LATCH anyway and
fails). Then a new `UPDATE t2` and a plain `SELECT count(*) FROM t2` both fail with "timed out waiting
on READ on page 1|769"; `SELECT count(*) FROM t` answers. At `cubrid server stop` the optdebug server
aborts in `cubthread::entry::clear_resources` (`thread_entry.cpp:270`, `pthread_mutex_destroy
(&th_entry_lock)` fails): S2's entry mutex has `__nusers = 4294967293`, one decrement for each of its
three timed-out branches' `thread_unlock_entry` of a lock it did not hold (core
`core.cub_server.2383521`). The same unlock, when a waker holds that entry lock, releases the waker's
lock.

### E — an error before the flush write leaves FLUSHING set and DIRTY cleared

`pgbuf_bcb_flush_with_wal` sets FLUSHING and clears DIRTY (`pgbuf_bcb_mark_is_flushing`, 10972), then
returns on a `tde_encrypt_data_page` (10986) or `dwb_set_data_on_next_slot` (10998) error with the BCB
locked, without `pgbuf_bcb_mark_was_not_flushed`, without clearing `oldest_unflush_lsa` and without
waking the FLUSH waiters. Nothing clears FLUSHING afterwards (`pgbuf_bcb_mark_was_flushed` runs only
after a write). Not a regression of PR #6704 (the function's error paths are unchanged); it strands
FLUSH waiters, which the atomic latch also counts in `waiter_exists`.

`AtomicLatch.code-e` (deadlock, depth 17): t1 fixes WRITE on a dirty page → f1 (synchronous flush)
finds it write-latched, sets ASYNC_FLUSH_REQ and queues as FLUSH waiter → t1's unfix starts the
requested flush → the page copy fails: FLUSHING on, DIRTY off → f2 finds the page clean and moves on →
f1 is never woken. Fix: on that error do what the I/O error path does (11079–11088):
`pgbuf_bcb_mark_was_not_flushed (was_dirty)`, restore `oldest_unflush_lsa`, `pgbuf_wake_flush_waiters`
(`fix-ext-flush`).

**Runtime reproduction (confirmed for the optdebug consequence)** — libcubrid `4bd26fa2…`, `he.sh`: the
first flush of 1|705 (t's first heap page, dirtied by an UPDATE) returns `ER_TDE_CIPHER_IS_NOT_LOADED`
right after `pgbuf_bcb_mark_is_flushing` (injected once, the same return the TDE path takes):
`flush_early_err 1|705 was_dirty=1 flushing=1 dirty=0`. In the same second the next zero-fcnt unfix
of 1|705 aborted the optdebug server at the assert of `pgbuf_unlatch_bcb_upon_unfix` (develop line 6789,
line 6859 in the instrumented build: `LSA_ISNULL (&bufptr->oldest_unflush_lsa)
|| pgbuf_bcb_is_dirty (bufptr)`; core `core.transaction.2384841`: flags `0x4402001f` = FLUSHING without
DIRTY, `oldest_unflush_lsa = 10499|12080`). The release-build consequence the model shows (a FLUSH
waiter never woken, checkpoint and `pgbuf_flush_all` stuck) was not run. Whether the TDE or DWB error
occurs on a running server without injection (cipher not loaded for an encrypted page, DWB disabled
or its slot wait failing) was not reproduced: a question.

### Earlier unattributed core (H2 run)

`core.cub_server.2127221` (the H2 server at stop) asserted in `cubbase::resource_tracker::pop_track`
← `cubthread::entry::end_resource_tracks` on entry `0x7f72f48f1b18`, the thread that ran H2's
`eh_cas` / `eh_leak` in `trace-h2.log`: the shutdown check of that thread's tracked resources, on the
thread whose handler leaked the fix count.

## Witnesses

| Witness cfg | Outcome shown reachable |
|---|---|
| `witness-woken-from-queue` | a queued waiter is handed the latch by the waker |
| `witness-timed-out-gave-up` | a waiter times out and runs the error handler |
| `witness-recheck-miss` | (fix) the ABA of H1 happens and the post-CAS re-check catches it |
| `witness-promoted-by-wait` | a promoter waits at the queue head and is granted WRITE |
| `witness-lock-free-shared` | two readers share a latch through the lock-free fix |
| `witness-flush-wait-at-idle` | a FLUSH waiter is queued on an idle latch (H4's precondition) under the fix |
| `witness-wait-on-handoff` | a FLUSH waiter is queued while the BCB sits in the post-flush queue (woken by `PostFlush`) |
| `witness-io-error` | a flush write fails and its flusher relocks to restore DIRTY and wake the waiters |
| `witness-flush-intr` | an interrupted FLUSH waiter removes itself from the queue |
| `witness-reclaim-after-inval` | a page is invalidated and the BCB is claimed again |
| `PageLatch.witness-shared` | the abstract latch has two readers |

## Dead expressions (pass cfg)

Never evaluated in **any** pass cfg (fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f): code-variant branches, mutant branches and violation ghosts:

| Line | Why |
|---|---|
| `AtomicLatch.tla:227`, `AtomicLatch.tla:228`, `AtomicLatch.tla:237`, `AtomicLatch.tla:238` | the H4 spin branches of `MFix` (claim and idle grant), taken only with `Code` containing "H4" (`code-h4`) |
| `AtomicLatch.tla:326`, `AtomicLatch.tla:328`, `AtomicLatch.tla:335`, `AtomicLatch.tla:338`, `AtomicLatch.tla:339`, `AtomicLatch.tla:345`, `AtomicLatch.tla:347`, `AtomicLatch.tla:353`, `AtomicLatch.tla:355`, `AtomicLatch.tla:631`, `AtomicLatch.tla:632`, `AtomicLatch.tla:633`, `AtomicLatch.tla:642` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` and their wrappers: the timed-out branch as the code has it, only with `Code` containing "A" (`code-a`); the fix re-locks the entry (`Timeout`) |
| `AtomicLatch.tla:381`, `AtomicLatch.tla:383`, `AtomicLatch.tla:384`, `AtomicLatch.tla:385`, `AtomicLatch.tla:400`, `AtomicLatch.tla:401`, `AtomicLatch.tla:402`, `AtomicLatch.tla:403`, `AtomicLatch.tla:636` | the H2 split CAS of `EhLoop` and `EhLk` (with its wrapper), only with `Code` containing "H2" (`code-h2`) |
| `AtomicLatch.tla:423` | the `fcnt < 0` branch of `UfUnl` (`negFcnt` violation ghost; reached with H3, `code-h3`) |
| `AtomicLatch.tla:462`, `AtomicLatch.tla:463` | the `doubleLock` violation ghost of `WkCas` (reached by `mutant-lf-fix-ignores-bit`) |
| `AtomicLatch.tla:490`, `AtomicLatch.tla:491` | the `"E"` branch of `StartFlush` (an early flush error leaves FLUSHING set), only with `Code` containing "E" (`code-e`) |
| `AtomicLatch.tla:538` | the `flerr_no_wake` mutant branch of `FlDone` (`mutant-flerr-no-wake`) |
| `AtomicLatch.tla:118`, `AtomicLatch.tla:359` | the `Go` / `Release` bodies, which TLC counts at their call sites; every call site that is live elsewhere evaluates them, these are the instances above that never fire in the fix |

Live in some pass cfg, dead only where that cfg's bounds remove the feature (flushers, the page flush
daemon, flush errors, invalidation, timeouts, promotion, conditional fix, a third thread, re-fix, torn
reads). Every line here maps to code that runs; the "live in" column names the pass cfgs that evaluate it:

| Line | Expression | Live in | Dead in |
|---|---|---|---|
| `AtomicLatch.tla:196` | `/\ mtx' = p /\ Go(p, to)` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:197` | `/\ UNCHANGED <<word, vpid, q, req, reqf, resumed, promoter, ` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:203` | `/\ word' = nw` | fix-all, fix-ext-torn, fix-refix-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, scale-3t-2f |
| `AtomicLatch.tla:204` | `/\ q' = Append(q, t)` | fix-all, fix-ext-torn, fix-refix-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, scale-3t-2f |
| `AtomicLatch.tla:205` | `/\ req' = [req EXCEPT ![t] = rq[t]] /\ reqf' = [reqf EXCEPT ` | fix-all, fix-ext-torn, fix-refix-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, scale-3t-2f |
| `AtomicLatch.tla:206` | `/\ resumed' = [resumed EXCEPT ![t] = FALSE]` | fix-all, fix-ext-torn, fix-refix-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, scale-3t-2f |
| `AtomicLatch.tla:207` | `/\ mtx' = None /\ Go(t, "wait")` | fix-all, fix-ext-torn, fix-refix-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, scale-3t-2f |
| `AtomicLatch.tla:209` | `Grant(t, nw) == /\ word' = nw /\ hold' = [hold EXCEPT ![t] =` | fix-all, fix-ext-torn | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:210` | `/\ mtx' = None /\ Go(t, "use")` | fix-all, fix-ext-torn | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:212` | `Reject(t, nw) == /\ word' = nw /\ mtx' = None /\ Go(t, "idle` | fix-cond-read-3t | fix-all, fix-all-2f, fix-all-3t, fix-ext-flush, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:225` | `THEN /\ vpid' = want[t] /\ valid' = TRUE` | fix-all, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:229` | `ELSE /\ Grant(t, Word(rq[t], w0.w, 1)) /\ UNCHANGED spin` | fix-all, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:230` | `/\ UNCHANGED <<q, req, reqf, resumed, promoter>>` | fix-all, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:231` | `ELSE /\ word' = w0 /\ mtx' = None /\ Go(t, "idle")` | fix-all, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:232` | `/\ UNCHANGED <<vpid, valid, q, req, reqf, resumed, promoter,` | fix-all, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:247` | `THEN Reject(t, w0) /\ UNCHANGED <<q, req, reqf, resumed, pro` | fix-cond-read-3t | fix-all, fix-all-2f, fix-all-3t, fix-ext-flush, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:248` | `ELSE Block(t, [w0 EXCEPT !.w = bitOn], 1) /\ UNCHANGED <<pro` | fix-all, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f | fix-all-2f, fix-ext-flush |
| `AtomicLatch.tla:251` | `/\ UNCHANGED <<q, req, reqf, resumed, promoter>>` | fix-all, fix-ext-torn, fix-refix-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, scale-3t-2f |
| `AtomicLatch.tla:255` | `/\ UNCHANGED <<q, req, reqf, resumed, promoter>>` | fix-all, fix-ext-torn, fix-refix-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, scale-3t-2f |
| `AtomicLatch.tla:258` | `/\ UNCHANGED <<q, req, reqf, resumed, promoter, hold>>` | fix-all, fix-cond-read-3t, scale-3t-2f | fix-all-2f, fix-all-3t, fix-ext-flush, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:262` | `/\ hold' = [hold EXCEPT ![t] = 0]` | fix-all, fix-ext-torn, fix-refix-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, scale-3t-2f |
| `AtomicLatch.tla:263` | `/\ UNCHANGED promoter` | fix-all, fix-ext-torn, fix-refix-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-promote-3t, scale-3t-2f |
| `AtomicLatch.tla:274` | `THEN mtx' = None /\ Go(t, "idle") /\ UNCHANGED <<word, q, re` | fix-all, fix-promote-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:275` | `ELSE /\ word' = [word EXCEPT !.m = "W"] /\ mtx' = None /\ Go` | fix-all, fix-promote-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:276` | `/\ UNCHANGED <<q, req, reqf, resumed, promoter, hold>>` | fix-all, fix-promote-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:278` | `THEN mtx' = None /\ Go(t, "idle") /\ UNCHANGED <<word, q, re` | fix-promote-3t | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:280` | `/\ word' = [word EXCEPT !.f = @ - hold[t],` | fix-all, fix-promote-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:282` | `/\ q' = <<t>> \o q` | fix-all, fix-promote-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:283` | `/\ req' = [req EXCEPT ![t] = "W"] /\ reqf' = [reqf EXCEPT ![` | fix-all, fix-promote-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:284` | `/\ resumed' = [resumed EXCEPT ![t] = FALSE]` | fix-all, fix-promote-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:285` | `/\ promoter' = [promoter EXCEPT ![t] = TRUE]` | fix-all, fix-promote-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:286` | `/\ hold' = [hold EXCEPT ![t] = 0]` | fix-all, fix-promote-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:287` | `/\ mtx' = None /\ Go(t, "wait")` | fix-all, fix-promote-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:288` | `/\ UNCHANGED <<vpid, want, rq, cnd, lw, ehg, wi, budget, toL` | fix-all, fix-promote-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:310` | `/\ toLeft' = toLeft - 1` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:311` | `/\ promoter' = [promoter EXCEPT ![t] = FALSE]` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:313` | `THEN /\ hold' = [hold EXCEPT ![t] = reqf[t]] /\ Go(t, "use")` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:314` | `ELSE /\ req' = [req EXCEPT ![t] = "N"] /\ Go(t, "to_lock") /` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:315` | `/\ UNCHANGED <<word, mtx, vpid, q, reqf, resumed, want, rq, ` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:365` | `THEN Release(t, "idle") /\ UNCHANGED q` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:367` | `THEN q' = RemoveAll(q, t) /\ Release(t, "idle")` | fix-all, fix-all-3t, fix-ext-flush, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:368` | `ELSE q' = Tail(q) /\ mtx' = mtx /\ Go(t, "eh_loop")` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:369` | `/\ UNCHANGED <<word, vpid, req, reqf, resumed, promoter, hol` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:378` | `THEN Release(t, "idle") /\ UNCHANGED <<word, q, resumed, ehg` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:386` | `ELSE /\ UNCHANGED ehg` | fix-all, fix-all-3t, fix-ext-flush, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:388` | `THEN /\ word' = [word EXCEPT !.f = @ + reqf[c]]` | fix-all-3t, scale-3t-2f | fix-all, fix-all-2f, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:389` | `/\ q' = Tail(q) /\ resumed' = [resumed EXCEPT ![c] = TRUE]` | fix-all-3t, scale-3t-2f | fix-all, fix-all-2f, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:390` | `/\ Go(t, "eh_loop") /\ UNCHANGED mtx` | fix-all-3t, scale-3t-2f | fix-all, fix-all-2f, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:391` | `ELSE Release(t, "idle") /\ UNCHANGED <<word, q, resumed>>` | fix-all, fix-all-3t, fix-ext-flush, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:392` | `/\ UNCHANGED <<vpid, req, reqf, promoter, hold, want, rq, cn` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:435` | `WkEnd(t) == /\ word' = IF RWWaiting THEN word ELSE [word EXC` | fix-all-3t, fix-cond-read-3t, fix-promote-3t, fix-refix-3t, scale-3t-2f | fix-all, fix-all-2f, fix-ext-flush, fix-ext-torn |
| `AtomicLatch.tla:444` | `THEN q' = RemoveAt(q, wi[t]) /\ UNCHANGED <<word, wi, lw, pc` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:446` | `THEN wi' = [wi EXCEPT ![t] = @ + 1] /\ UNCHANGED <<word, q, ` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:451` | `THEN wi' = [wi EXCEPT ![t] = @ + 1] /\ UNCHANGED <<word, q, ` | fix-all-3t, fix-cond-read-3t, fix-refix-3t, scale-3t-2f | fix-all, fix-all-2f, fix-ext-flush, fix-ext-torn, fix-promote-3t |
| `AtomicLatch.tla:452` | `ELSE WkEnd(t) /\ UNCHANGED <<q, wi, lw>>` | fix-all-3t, fix-cond-read-3t, fix-promote-3t, fix-refix-3t, scale-3t-2f | fix-all, fix-all-2f, fix-ext-flush, fix-ext-torn |
| `AtomicLatch.tla:477` | `IN /\ q' = q2` | fix-ext-flush | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:478` | `/\ resumed' = [e \in Procs \|-> IF e \in Range(q) /\ isF(e) ` | fix-ext-flush | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:479` | `/\ word' = IF ~noClear /\ ~(\E i \in 1..Len(q2) : req[q2[i]]` | fix-ext-flush | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:486` | `\/ /\ flushing' = TRUE /\ dirty' = FALSE /\ async' = FALSE` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:487` | `/\ Release(p, "fl_io") /\ UNCHANGED <<errLeft, word, q, resu` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:488` | `\/ /\ errLeft > 0 /\ errLeft' = errLeft - 1` | fix-ext-flush | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:494` | `/\ async' = FALSE /\ UNCHANGED <<flushing, dirty>>` | fix-ext-flush | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:517` | `THEN Release(f, "fz_next") /\ UNCHANGED <<word, q, req, resu` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:519` | `THEN StartFlush(f, "fz_next") /\ UNCHANGED req` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:521` | `THEN Release(f, "fz_next") /\ UNCHANGED <<word, q, req, resu` | fix-ext-flush | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:523` | `/\ word' = [word EXCEPT !.w = TRUE]` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:524` | `/\ async' = (async \/ ~flushing)` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:525` | `/\ q' = Append(q, f) /\ req' = [req EXCEPT ![f] = "F"]` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:526` | `/\ resumed' = [resumed EXCEPT ![f] = FALSE]` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:527` | `/\ Release(f, "fz_wait") /\ UNCHANGED <<flushing, dirty, err` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:528` | `/\ UNCHANGED <<vpid, reqf, promoter, hold, want, rq, cnd, lw` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:535` | `/\ flushing' = FALSE` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:536` | `/\ dirty' = (dirty \/ ioErr[p])` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:540` | `/\ ioErr' = [ioErr EXCEPT ![p] = FALSE]` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:542` | `/\ UNCHANGED <<vpid, req, reqf, promoter, hold, want, rq, cn` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:551` | `/\ \/ /\ Go(p, "fl_relock") /\ UNCHANGED <<ioErr, errLeft, p` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:552` | `\/ /\ errLeft > 0 /\ errLeft' = errLeft - 1` | fix-ext-flush | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:553` | `/\ ioErr' = [ioErr EXCEPT ![p] = TRUE] /\ Go(p, "fl_relock")` | fix-ext-flush | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:554` | `\/ /\ p \in Daemons /\ ~pfPend /\ pfPend' = TRUE` | fix-ext-flush | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:555` | `/\ Go(p, "fz_next") /\ UNCHANGED <<ioErr, errLeft>>` | fix-ext-flush | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:556` | `/\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promo` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:565` | `/\ pfPend' = FALSE /\ flushing' = FALSE` | fix-ext-flush | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:567` | `/\ UNCHANGED <<mtx, vpid, req, reqf, promoter, hold, want, r` | fix-ext-flush | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:580` | `/\ envLeft' = envLeft - 1 /\ valid' = FALSE /\ dirty' = FALS` | fix-ext-flush, fix-ext-torn | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:581` | `/\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promo` | fix-ext-flush, fix-ext-torn | fix-all, fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-promote-3t, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:587` | `/\ toLeft' = toLeft - 1 /\ Go(f, "fz_ilock")` | fix-all, fix-ext-flush, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:588` | `/\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promo` | fix-all, fix-ext-flush, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:597` | `/\ q' = q2` | fix-all, fix-ext-flush, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:598` | `/\ word' = IF Mutant # "flush_intr_no_clear"` | fix-all, fix-ext-flush, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:601` | `ELSE UNCHANGED <<q, word>>` | fix-all, fix-ext-flush, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:603` | `/\ UNCHANGED <<vpid, req, reqf, resumed, promoter, hold, wan` | fix-all, fix-ext-flush, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:608` | `/\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promo` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:613` | `/\ budget' = [budget EXCEPT ![f] = @ - 1]` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:615` | `/\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promo` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:629` | `PrFix(t) == PrFix_(t) /\ UNCHANGED extra` | fix-all, fix-promote-3t | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-flush, fix-ext-torn, fix-refix-3t, scale-3t-2f |
| `AtomicLatch.tla:634` | `Eh(t) == Eh_(t) /\ UNCHANGED extra` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:635` | `EhLoop(t) == EhLoop_(t) /\ UNCHANGED extra` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:641` | `Timeout(t) == Timeout_(t) /\ UNCHANGED extra` | fix-all, fix-all-3t, fix-ext-flush, fix-ext-torn, scale-3t-2f | fix-all-2f, fix-cond-read-3t, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:643` | `FzIrm(f) == FzIrm_(f) /\ UNCHANGED extra` | fix-all, fix-ext-flush, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:644` | `FzWait(f) == FzWait_(f) /\ UNCHANGED extra` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:645` | `FzNext(f) == FzNext_(f) /\ UNCHANGED extra` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:646` | `FzIntr(f) == FzIntr_(f) /\ UNCHANGED extra` | fix-all, fix-ext-flush, scale-3t-2f | fix-all-2f, fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |
| `AtomicLatch.tla:647` | `Lock(p, from, to) == Lock_(p, from, to) /\ UNCHANGED extra` | fix-all, fix-all-2f, fix-ext-flush, scale-3t-2f | fix-all-3t, fix-cond-read-3t, fix-ext-torn, fix-promote-3t, fix-refix-3t |

## Bounds and limits

| cfg | Threads | Flushers | Pages | MaxOps | MaxHold | Timeouts | Ops | Code |
|---|---|---|---|---|---|---|---|---|
| `AtomicLatch` (the code) | 2 | 1 | 2 | 2 | 2 | 1 | fixR fixW fixWc promote | H1–H4 |
| `code-h1`, `code-h3` | 2 | 1 | 2 | 2 | 2 | 1 | fixR fixW fixWc promote | one hole |
| `code-h2` | 3 | 0 | 1 | 1 | 1 | 2 | fixR fixW | H2 |
| `code-h4` | 2 | 2 | 1 | 1 | 1 | 0 | fixR fixW | H4 |
| `fix-all` | 2 | 1 | 2 | 2 | 2 | 1 | fixR fixW fixWc promote | none |
| `fix-all-3t` / `fix-all-2f` | as `code-h2` / `code-h4` | | | | | | | none |
| `fix-refix-3t` | 3 | 0 | 1 | 2 | 2 | 0 | fixR fixW | none |
| `fix-cond-read-3t` | 3 | 0 | 1 | 1 | 1 | 0 | fixR fixW fixRc | none |
| `fix-promote-3t` | 3 | 0 | 1 | 2 | 1 | 0 | fixR promote | none |
| `scale-3t-2f` | 3 | 2 | 2 | 1 | 2 | 2 | fixR fixW fixWc promote | none |
| `code-a` | 2 | 0 | 1 | 1 | 1 | 1 | fixR fixW | A |
| `code-e` | 1 | 2 (sync) | 1 | 1 | 1 | 0 | fixW | E (`MaxErr` 1, dirty at start) |
| `fix-ext-flush` and its mutants, witnesses | 2 | 2 (f2 daemon) | 1 | 1 | 1 | 1 | fixR fixW | none (`MaxErr` 1, `MaxEnv` 1) |
| `fix-ext-torn`, `witness-reclaim-after-inval` | 2 | 0 | 2 | 2 | 2 | 1 | fixR fixW | none (`MaxEnv` 1, `TornReads`) |
| `PageLatch` | T = 3 | | 2 | | | | | |

H2 needs three threads and two timeouts, H4 two flushers, C6 three threads with re-fixes: each
fix cfg covers the bounds its hole or claim needs; no single cfg combines them all (state space).

Not modeled: the latch order across BCBs (the caller's, unchanged by PR #6704), the holder entry's
watcher list, `PGBUF_LATCH_INVALID` as a word value (an invalidated BCB is `valid = FALSE` with an
idle word, which is what `pgbuf_invalidate_bcb` leaves), the holder-entry allocation failure, SA
mode and `pgbuf_simple_fix` (fault table). TLAPS covers only `PageLatch` (C2, C4 for any number of
threads and pages); C1, C3, C5–C8 and every liveness claim are TLC results inside the bounds above.

## Memory order

TLC runs every step sequentially consistent. That is sound for the latch word and argued here for
the plain data around it (code at `21c6e635d`):

- Every read-modify-write of `atomic_latch` is a CAS with `memory_order_acq_rel` / `acquire`
  (`set_latch`, `add_fcnt`, `set_waiter_exists`, `set_latch_and_add_fcnt` at 1389–1457, and the CAS
  loops at 2907, 6524, 6775, 7320, 7638, 7829, 7901, 8942); loads are `acquire`. A single atomic
  object has one modification order and an RMW always reads the latest value in it, so the word
  behaves as the model's one variable whatever the orders.
- The plain stores of the whole word — claim (8563) and victimize (8748), both under the BCB mutex —
  write over `(NO_LATCH, *, 0)`. No lock-free CAS can succeed against that value (both lock-free
  paths require `READ` and `fcnt > 0`), so a store never hides a concurrent CAS. `copy_bcb` (1369) has no
  caller (rg), and the initialization (5688) runs before any other thread reaches the BCB.
- `bufptr->vpid` is a plain field read by the lock-free fix with no lock while a claimer may write
  it: a data race whose outcomes (a torn or stale compare) are what `TornReads` admits. The H1 fix
  re-reads `vpid` after the successful CAS: that CAS reads a value in the release sequence of the
  claimer's latching CAS (acquire / release), so the claimer's `vpid` write happens before the
  re-read, and no thread writes `vpid` while `fcnt > 0`.
- The page contents a lock-free reader sees: its acquire CAS reads from the release sequence that
  starts at the grant it joins, which acquired the last WRITE holder's releasing unfix CAS.
- `next_wait_thrd`, `request_latch_mode`, `request_fix_count`, `resume_status` are read and written
  under the BCB mutex or the entry lock everywhere except the paths the model splits (`"A"`, `"H2"`).

## Result

Run 2026-11-06 05:03–07:50 KST, `tools/tla/tla-check --workers 48 --heap 40g`, run dir
`.git_ignored_dir/scratch/tla/CBRD-26425-atomic-latch-20261106-050351-2459743`, engine `21c6e635d`.

Last line: `RESULT: FAILED (16)`. Seven are the code cfgs (`AtomicLatch`, `code-a`, `code-e`,
`code-h1`..`code-h4`), which fail by design on the confirmed holes (P9). The other nine are the pass
cfgs, every one `got=[pass]`, refused only because this file still carried the dead-expression
section of the pre-extension model; the section above was regenerated from this run, and every
dead line of the nine is now named here (the same `AtomicLatch.tla:<n>` grep tla-check applies).
Rerun with this file on the unchanged specs, 07:54 (`.git_ignored_dir/scratch/tla/CBRD-26425-atomic-latch-20261106-075416-2506890`):
the seven code cfgs fail as above, all eight non-scale pass cfgs print `PASS` (dead expressions
explained), and the nine mutants `PASS`. It was stopped at 08:15 inside `scale-3t-2f` when the session
ended, so it printed no `RESULT` line; `scale-3t-2f`'s pass is the 05:03 run's (9532 s), and every
dead line of that run is named in the section above. The ten witnesses and `PageLatch` are the 05:03 run's.

| cfg | expect | got | states (generated/distinct) | depth | time |
|---|---|---|---|---|---|
| `AtomicLatch` | pass | violation FcntExact | 10762/4151 | 9 | 3s |
| `AtomicLatch.code-a` | pass | violation FcntExact | 1256/778 | 18 | 3s |
| `AtomicLatch.code-e` | pass | deadlock | 2088/1084 | 19 | 2s |
| `AtomicLatch.code-h1` | pass | violation SamePage | 720478/264869 | 20 | 11s |
| `AtomicLatch.code-h2` | pass | violation FcntExact | 21004/10012 | 19 | 4s |
| `AtomicLatch.code-h3` | pass | violation FcntExact | 15411/5765 | 9 | 3s |
| `AtomicLatch.code-h4` | pass | violation NoSpin | 34187/13817 | 21 | 3s |
| `AtomicLatch.fix-all-2f` | pass | pass | 94926/36758 | 40 | 5s |
| `AtomicLatch.fix-all-3t` | pass | pass | 161997/72205 | 42 | 8s |
| `AtomicLatch.fix-all` | pass | pass | 9757758/3829316 | 60 | 174s |
| `AtomicLatch.fix-cond-read-3t` | pass | pass | 148570/63774 | 42 | 7s |
| `AtomicLatch.fix-ext-flush` | pass | pass | 631122/218808 | 41 | 14s |
| `AtomicLatch.fix-ext-torn` | pass | pass | 625924/323612 | 52 | 16s |
| `AtomicLatch.fix-promote-3t` | pass | pass | 1347770/574127 | 68 | 27s |
| `AtomicLatch.fix-refix-3t` | pass | pass | 18174019/7469024 | 76 | 303s |
| `AtomicLatch.mutant-block-no-bit` | refinement | refinement | 5077/2002 | 7 | 3s |
| `AtomicLatch.mutant-flerr-no-wake` | deadlock | deadlock | 447688/160277 | 30 | 4s |
| `AtomicLatch.mutant-flush-intr-no-clear` | violation NoSpin | violation NoSpin | 242141/90415 | 23 | 3s |
| `AtomicLatch.mutant-flush-wake-no-clear` | violation NoSpin | violation NoSpin | 50137/20069 | 25 | 3s |
| `AtomicLatch.mutant-lf-any-mode` | refinement | refinement | 14957/5550 | 9 | 4s |
| `AtomicLatch.mutant-lf-fix-ignores-bit` | violation NoDoubleLock | violation NoDoubleLock | 944310/403811 | 30 | 5s |
| `AtomicLatch.mutant-lf-no-vpid-check` | violation SamePage | violation SamePage | 624932/231727 | 19 | 10s |
| `AtomicLatch.mutant-lf-unfix-last` | violation FcntExact | violation FcntExact | 4424/1785 | 7 | 2s |
| `AtomicLatch.mutant-unlatch-no-wakeup` | violation NoStrandedWaiter | violation NoStrandedWaiter | 72096/26014 | 12 | 4s |
| `AtomicLatch.scale-3t-2f` | pass | pass | 404500886/119440820 | 61 | 9532s |
| `AtomicLatch.witness-flush-intr` | violation NotFlushIntrRemoved | violation NotFlushIntrRemoved | 5300/2694 | 11 | 2s |
| `AtomicLatch.witness-flush-wait-at-idle` | violation NotFlushWaitAtIdle | violation NotFlushWaitAtIdle | 2924/1515 | 13 | 2s |
| `AtomicLatch.witness-io-error` | violation NotIoErrDone | violation NotIoErrDone | 3224/1764 | 10 | 2s |
| `AtomicLatch.witness-lock-free-shared` | violation NotLockFreeShared | violation NotLockFreeShared | 20000/7497 | 9 | 2s |
| `AtomicLatch.witness-promoted-by-wait` | violation NotPromotedByWait | violation NotPromotedByWait | 600479/218682 | 19 | 7s |
| `AtomicLatch.witness-recheck-miss` | violation NotRecheckMiss | violation NotRecheckMiss | 598931/218268 | 19 | 6s |
| `AtomicLatch.witness-reclaim-after-inval` | violation NotReclaimedAfterInval | violation NotReclaimedAfterInval | 1892/777 | 8 | 2s |
| `AtomicLatch.witness-timed-out-gave-up` | violation NotTimedOutGaveUp | violation NotTimedOutGaveUp | 25093/9271 | 10 | 3s |
| `AtomicLatch.witness-wait-on-handoff` | violation NotWaitOnHandoff | violation NotWaitOnHandoff | 111956/42816 | 19 | 3s |
| `AtomicLatch.witness-woken-from-queue` | violation NotWokenFromQueue | violation NotWokenFromQueue | 123792/45146 | 13 | 4s |
| `PageLatch` | pass | pass | 1254/188 | 6 | 1s |
| `PageLatch.inductive-indinv` | pass | pass | 1568/204 | 1 | 2s |
| `PageLatch.witness-shared` | violation NotShared | violation NotShared | 793/182 | 5 | 1s |
| `PageLatch_proofs.tla` | proof | 70/70 proved | | | |

Spec sha256 (from `summary.txt`):

```
f78eacc05b84663c1aeccff9822c96f6eae19e7210aabc15f19cfec0540e7ca1  AtomicLatch.tla
3a0af78a07e982e2a74e02a0bcccb31ea3c11f2467b41bdd1312fb0be248ed0e  PageLatch.tla
4c8f2d12e1551cb76bb0642f6615f215161bd49f026dc955f78db0fc199bc777  PageLatch_proofs.tla
9bf4fc9a06078edeaaff16ba8b8597ac2fe82933593cb278a12b00da0c13e4d3  AtomicLatch.cfg
29f818ffe12e56f3cc1fb974b332f644fcf00ea582e5552e83a7a23e06869ef5  AtomicLatch.code-a.cfg
a039e45cb0d899b836f21e66ff74b0e4149ba92036116e9586a7f75cd8613f30  AtomicLatch.code-e.cfg
abafbf96c30f9fd480b12caeb5ebb845b96e49d196994434383d91ff90fce036  AtomicLatch.code-h1.cfg
0728d34784e4238580402fc5ddbdcb442106df21939f5ca85ec5e6777837a871  AtomicLatch.code-h2.cfg
345fa5e0cab72e26ae4483717e03068baf956c8a87257eaaa7e8a8716a56a458  AtomicLatch.code-h3.cfg
94f5c9501896e1904fefd14ac12eea57d0afd05908455db87cfb3d9481c662dc  AtomicLatch.code-h4.cfg
f08c9d3903384eabae7f074447a586a4081f86e0cd92a6dca3688b47322da1e0  AtomicLatch.fix-all-2f.cfg
53fa41edc8f09bc9e602abfec9da050898871499ca2bd874793aa278c7c304cd  AtomicLatch.fix-all-3t.cfg
ddb4b4f08494f22c4bfead86168b5b41bcfc6160a8c8646edbc9eba64725b0a2  AtomicLatch.fix-all.cfg
ee1896df17b5c6ff98cc376402abae0ddea9a702b5503c60c11073b31cb6bef6  AtomicLatch.fix-cond-read-3t.cfg
e2b732e109881d7d096653d35a9a509f9edaab4bcb062d0e895ab4db4a660077  AtomicLatch.fix-ext-flush.cfg
0cc5ff7c35d9f5afaba3b778f8735f56c96a28553617ae763ab391862ae110d3  AtomicLatch.fix-ext-torn.cfg
06d14f84384790c8398a1885d78cf05b370a80f2ca712ad332be3a229414c597  AtomicLatch.fix-promote-3t.cfg
3986ae137e75ab25e1b0c467bfb4f168c31c385e0bef3fafd38b57746328f551  AtomicLatch.fix-refix-3t.cfg
d62a575ce3a7b5e0835b9964f1a70cf20d2e11d45791ce3a9b32a7591ebb0a9f  AtomicLatch.mutant-block-no-bit.cfg
fcefbaf4ece46a89690f363c796946849fa52c249312a716723cae9b3cfa6275  AtomicLatch.mutant-flerr-no-wake.cfg
845f6320ad94646a5fc21bfb817a958c07e17c49ddd764e417c96607420a243c  AtomicLatch.mutant-flush-intr-no-clear.cfg
efb1d72e1bc1af2efab2bf686e8aabcc42da9b98ef4a96d7f5a2b615e68cc55b  AtomicLatch.mutant-flush-wake-no-clear.cfg
dec1240e0d01e1a38214c5ef7686d0681dcb4adc1e0eb6fb8efdc87f8a98695b  AtomicLatch.mutant-lf-any-mode.cfg
02a80bc15cf43372a7350894bf40c38238811cd041ffda43a535da38926fe079  AtomicLatch.mutant-lf-fix-ignores-bit.cfg
4fcb9a10b34cadec8ce018435de8b75962d7e079702b6c77549de3cbaf8e5453  AtomicLatch.mutant-lf-no-vpid-check.cfg
9ee5fc162524153f0ff7ac65d9cab7fffc1fcef91de6a1097f27710048ee4393  AtomicLatch.mutant-lf-unfix-last.cfg
3d90be53384ee7363ef706cca2e7b78cc88a816795cd18630aa89b885fc4f3fa  AtomicLatch.mutant-unlatch-no-wakeup.cfg
29cb2325f2f3d5636525253d6a54957985708698c94ebc342e606c6592176158  AtomicLatch.scale-3t-2f.cfg
707a2e1d55a86668aaa9674189f0475491935c7fa6b8d8df113e42b4d338adbe  AtomicLatch.witness-flush-intr.cfg
11750554b7ec8c55b5b97338a6d4d6584df3c7bffb3ffda0de19eb9e1125fdcd  AtomicLatch.witness-flush-wait-at-idle.cfg
3f9022d77d46ca3755cf2daa974279597c77e96fd318480649ee4b069d0c21de  AtomicLatch.witness-io-error.cfg
fd42dfd5edeadc64057e51028fb6586fe6de9b66e30b8134a12caead27f06baf  AtomicLatch.witness-lock-free-shared.cfg
352f21707d1e96db08462b75643d0bb1488fd811d85659aa4b5cb5681a871a98  AtomicLatch.witness-promoted-by-wait.cfg
73f4cf023c2fcd3ab6fc1c4ad5059cb8da0dd350c3c20b8ba84f9c6c32fa4c60  AtomicLatch.witness-recheck-miss.cfg
f76dad20937d26917b6fe29ddbbf88f6d3409c52ca72680f7b7fbb022598202a  AtomicLatch.witness-reclaim-after-inval.cfg
20af54a2077d3b8b6a79a341ae070115218068a07ead14bfc80db71b15da2544  AtomicLatch.witness-timed-out-gave-up.cfg
e571af312efcd8072293467874908782672baa86aa3ac5514e7c12c62be07fac  AtomicLatch.witness-wait-on-handoff.cfg
4e822577c529c84f6eb8bceebf599bfaee6dc4fc82890c59ad5e4ea484c11ced  AtomicLatch.witness-woken-from-queue.cfg
1be1db598f7ba0dac32f05b949a2affc35ef8f69e1a07c0eac35892c9b540b5c  PageLatch.cfg
75797c0276498272e7b0ebe48d1b1e78405cbe8989711b95346e507d01b2c79e  PageLatch.inductive-indinv.cfg
f7e358ad7391527abd319eaa20ee1a7cc535b88d0c585681a6e2579664131a8d  PageLatch.witness-shared.cfg
```

Runtime reproductions (optdebug builds of `21c6e635d` with the instrument patch, scratch worktree
`tla-latch-repro`): H1 on libcubrid `8f2845ef…`, H2 on `69f2882b…` (its stop core attributed above), H4 on
`d8a8ddc1…`, A and E on `4bd26fa2175f33ab…`
(`~/optdebug/CUBRID-tla-latch`). Trace validation of the full protocol was not run; each hole's
reproduction logs the structural events of its counterexample instead (Findings).
