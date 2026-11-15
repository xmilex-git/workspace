# BCB mutex removal — TLA+ map (design, grill in progress)

Design of a page buffer without the per-BCB pthread mutex (`PGBUF_BCB_LOCK`), grilled with
grill-with-tla from 2026-11-15. Base code: develop `4bf2b2e32` (CBRD-27970 merged), whose latch model
is `docs/tla/CBRD-27970-27971/`. Model: `BucketLatch.tla` (plain TLA+, one step = one bucket-latch
critical section). Open choices are constants TLC explores (`PromoteWait`, `WakeAtEnd`).

trace-exempt: design with no implementation yet; the implementation spec will refine this one
(cubrid-tla step 9) and carry the trace validation.

## Settled decisions

| # | Decision | Date |
|---|---|---|
| D1 | Goal: both serial instructions and concurrent contention; acceptance by contention on the perf servers (wall time, TPC-C and read-heavy YCSB), serial `instructions:u` as a no-regression check, write-heavy load must not slow down | 2026-11-15 |
| D2 | Scope: the BCB mutex goes from every path (fix, unfix, WRITE, promotion, waiters, flush, victim, invalidate) | 2026-11-15 |
| D3 | A BCB's state (fix count, latch mode, waiter list, vpid, flush state) changes only under a hash-bucket read-write latch (CAS-based, shared and exclusive modes): a fix holds it shared and raises the count atomically; a victim claim, an invalidation and an identity change hold it exclusive and require no fix and no waiter. A victim search takes a candidate's bucket latch without waiting and moves on when it cannot | 2026-11-15 |
| D4 | Waiters are woken, not granted: the releaser collects the waiters compatible with the latch it leaves (stopping at the first exclusive one) under the bucket latch and wakes them after releasing it; a woken waiter retries the fix from the hash chain | 2026-11-15 |
| D5 | The last unfix leaves only a time-gated use mark; LRU boosts and the VOID→LRU insertion move to the victim scan and the claim (second chance). Buffer hit ratio joins the D1 measurements | 2026-11-15 |
| D6 | Verified as one design (this directory), delivered as staged PRs: READ fix/unfix + claim → waiters → WRITE, promotion, flush → LRU | 2026-11-15 |
| D7 | One model throughout: the protection model of D3/D4 is followed for every part (no mix of models) | 2026-11-15 |
| D8 | A new request does not look at the waiter list (barging); a woken waiter competes like any other request | 2026-11-15 |
| D9 | Every fix and every unfix takes the bucket latch (shared for READ, exclusive otherwise); the develop lock-free READ path is not kept | 2026-11-15 |
| D10 | A flush sets a write-in-progress flag under the bucket latch, copies the page (into the double-write slot; for a temporary page into its write buffer) and clears the flag under the latch; a WRITE fix or a promotion waits while the flag is set, READ fixes do not | 2026-11-15 |
| D11 | A waiter for the write to complete (a WRITE fix, a synchronous flush) sets a write-waiter flag; the end of the write wakes the waiters when it is set | 2026-11-15 |
| D12 | A waiter removes its own entry (woken, timed out, interrupted, spuriously woken) under the exclusive bucket latch and then applies the wake rule to the waiters left (passes the wakeup on); a victim search tries the candidate's bucket latch without waiting and moves on | 2026-11-15 |

## Open decisions

- `PromoteWait`: a promotion that is not alone either releases its READ and waits for WRITE
  (develop's `PGBUF_PROMOTE_SHARED_READER`, today the waiting promoter is queued first) or fails with
  `ER_PAGE_LATCH_PROMOTE_FAIL` so the caller re-fixes WRITE (every caller has that path). With D8 the
  waiting variant breaks C9 (`probe-true-*`).
- `WakeAtEnd`: a waiter blocked only by a write in progress, whose blocker was a READ holder, is woken
  either because the releaser that leaves it so sets the write-waiter flag ("flag") or because the end
  of a write always applies the wake rule when the list is not empty ("always"); D11 alone ("none")
  strands it (`probe-false-none`).
- The bucket latch's identity: the existing per-bucket `hash_mutex` replaced by the read-write latch
  (1M buckets, `HASH_SIZE_BITS 20`).

## Prior art (public)

PostgreSQL development branch (`~/dev/postgres` at `b0392c26bd3`, 2026-10-30), `src/backend/storage/buffer/bufmgr.c`:

- One 64-bit buffer state word holds refcount (18 bits), usage count (4), flags (12, among them the
  header spinlock bit `BM_LOCKED`, `BM_IO_IN_PROGRESS`, `BM_LOCK_HAS_WAITERS`, `BM_LOCK_WAKE_IN_PROGRESS`),
  share-lock count (18), a share-exclusive bit and an exclusive bit (`buf_internals.h`; content locks
  moved into the word by `fcb9c977aa5`, 2026-01-15). Pin, unpin and content lock are CAS loops on it.
- Content lock modes SHARE, SHARE_EXCLUSIVE (conflicts with itself and EXCLUSIVE), EXCLUSIVE. Writing a
  buffer out and setting hint bits require SHARE_EXCLUSIVE (`82467f627bd`, 2026-03-10), so the write no
  longer copies the page (`41d3d64e87a`, 2026-03-27): readers proceed during the I/O, an exclusive
  locker waits for it.
- Waiters: `BufferLockAcquire` queues itself, retries, sleeps; `BufferLockWakeup` collects waiters
  under the header spinlock and wakes them after; a woken waiter retries the CAS (no hand-off, barging
  allowed). The wait list lives in the buffer descriptor under `BM_LOCKED`.
- Lookup takes the buffer-mapping partition lock shared, eviction exclusive; usage count is bumped at
  pin and decremented by the clock sweep.

## Claim and sources

| Claim | Statement | Kind | Source |
|---|---|---|---|
| C1 | `fcnt` equals the number of holders (the loader of a claimed BCB included) and the latch is idle exactly when `fcnt = 0` | safety | CBRD-27970-27971 C1; `pgbuf_unlatch_bcb_upon_unfix` header |
| C2 | a WRITE latch has one holder and no reader beside it | safety | CBRD-27970-27971 C2; `PGBUF_LATCH_WRITE` |
| C3 | `pgbuf_fix (vpid)` returns the BCB of `vpid` and the BCB keeps `vpid` while it is held | safety | CBRD-27970-27971 C3; `pgbuf_fix` contract |
| C4 | nothing changes a page while a flush copies it: no WRITE holder while the write-in-progress flag is set, and the copy is the page as it was when the flag was set | safety | D10; `pgbuf_bcb_flush_with_wal` (today the copy is made under the BCB mutex with no WRITE holder) |
| C5 | the latest change of every page is on disk or in the BCB holding the page (a victim never takes a dirty or written page; a failed copy leaves the page dirty) | safety | `PGBUF_BCB_INVALID_VICTIM_CANDIDATE_MASK` comment; `pgbuf_bcb_flush_with_wal` "if writing fails, we revert changes" |
| C6 | a waiter entry belongs to a thread asleep on it, waiting for the page the BCB still holds | safety | D12 |
| C7 | a BCB nobody holds and no flush copies never keeps waiters of whom none is woken while no thread is on its way to fix that page; every worker finishes (liveness) | safety + liveness | CBRD-27970-27971 C7; `pgbuf_wakeup_reader_writer` "how it works" |
| C8 | a page is held by at most one BCB | safety | hash chain contract (`pgbuf_search_hash_chain`) |
| C9 | a promotion that had to wait hands over a page nobody changed since the promoter's READ | safety | `pgbuf_promote_read_latch_release`: the waiting promoter "register as first blocker" and a second promoter fails (`ER_PAGE_LATCH_PROMOTE_FAIL`); btree callers continue after a successful promotion without re-reading |

## Properties

| Property | Claims | Checked by |
|---|---|---|
| `FcntExact` | C1 | TLC invariant |
| `Exclusive` | C2 | TLC invariant |
| `SamePage` | C3 | TLC invariant |
| `NoWriteDuringCopy` | C4 | TLC invariant |
| `NoLostUpdate` | C5 | TLC invariant |
| `NoStaleWaiter` | C6 | TLC invariant |
| `NoStrandedWaiter`, `Termination` | C7 | TLC invariant; TLC liveness (own cfg) |
| `UniqueResident` | C8 | TLC invariant |
| `PromoteStable` | C9 | TLC invariant |

## Refinement map (model -> code to change)

Design: the rows name the develop `4bf2b2e32` sites each action replaces in `src/storage/page_buffer.c`.

| Model | Code | One step because |
|---|---|---|
| bucket latch, `exh` | `PGBUF_BUFFER_HASH.hash_mutex` → read-write latch (CAS word, shared count + exclusive owner) | — |
| `vpid`, `mode`, `fcnt`, `dirty`, `writing`, `wwait`, `touched` | `bufptr->vpid`, `atomic_latch`, `flags` (`PGBUF_BCB_DIRTY_FLAG`, `PGBUF_BCB_FLUSHING_TO_DISK_FLAG`, a new write-waiter flag), `hit_age` | changed only under the bucket latch of the BCB's page; under the shared latch only the latch word by CAS |
| waiter list `inq`, `wm`, `tk`, `posted` | `bufptr->next_wait_thrd`, `thread_p->request_latch_mode`, `resume_status` | exclusive bucket latch; the wakeup itself is the waiter's semaphore |
| `FixShared` | `pgbuf_fix` READ: `pgbuf_search_hash_chain` under the shared latch + `atomic_latch` CAS (replaces `pgbuf_lockfree_fix_ro` and the BCB trylock) | shared section: one CAS on the word, the chain and vpid stable under the shared latch |
| `FixExcl` | `pgbuf_fix` WRITE, the READ that must wait, the miss (`pgbuf_latch_bcb_upon_fix`, `pgbuf_block_bcb`), `pgbuf_bcb_safe_flush_internal` (synchronous flush) | exclusive section |
| `MissClaim`, `MissGiveUp` | `pgbuf_claim_bcb_for_fix` → `pgbuf_get_victim` (`pgbuf_get_victim_from_lru_list`: candidate bucket latch tried without waiting) | the candidate's latch is held only for the check and the unlink |
| `LoadEnd` | end of `pgbuf_claim_bcb_for_fix` read, `pgbuf_unlock_page` | exclusive section |
| `Promote` | `pgbuf_promote_read_latch_release` | exclusive section |
| `Unfix` | `pgbuf_unfix` (replaces `pgbuf_lockfree_unfix_ro` and `pgbuf_unlatch_bcb_upon_unfix` under the BCB mutex) | shared or exclusive section; posting only reads the list |
| `WakeRetry`, `Timeout`, `Leave` | `pgbuf_timed_sleep`, `pgbuf_timed_sleep_error_handling` → remove own entry, pass the wakeup on | exclusive section |
| `Copy`, `CopyEnd`, `DaemonStart` | `pgbuf_bcb_flush_with_wal` (copy, `dwb_set_data_on_next_slot`), `pgbuf_bcb_mark_was_flushed` / `_was_not_flushed`, `pgbuf_wake_flush_waiters`; daemon = `pgbuf_flush_victim_candidates` | start and end are exclusive sections; the copy runs with the flag set and no latch |
| `Invalidate` | `pgbuf_invalidate_bcb` callers | exclusive section |

## Fault model

| Fault | Modeled? | Where / why not |
|---|---|---|
| error return | yes | conditional fix failure (`Rc`, `Wc`), promotion failure (`PromoteWait = FALSE`), page copy error (`MaxErr`) |
| interrupt / query cancel | yes | `Timeout` covers both: the waiter removes its entry and retries or fails |
| lock timeout, deadlock victim | yes (latch timeout) | `Timeout` |
| conditional latch failure | yes | `Rc`, `Wc`, the victim search's no-wait try (`CandLatchOk`) |
| OOM | n/a | nothing is allocated (waiter entries are per thread) |
| crash / `kill -9` | n/a | volatile buffer state |
| spurious wakeup | yes | `WakeRetry(t, TRUE)`, budget `MaxSpur` |
| concurrent DML | yes | WRITE holders change pages (`Unfix` of a WRITE) |
| vacuum | n/a | fixes through the same paths |
| checkpoint, page flush, page replacement | yes | synchronous flush (`C`), the flush daemon, victim claim |
| page read error after a claim | not yet | open: the waiters on a loading BCB and its identity on a read error |
| HA log apply | n/a | no protocol difference |
| fairness | weak fairness per process step; none on faults | a WRITE waiter can lose to newcomers (D8); termination holds because every worker has a finite budget |
