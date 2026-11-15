# BCB mutex removal — TLA+ map (design, verified)

Design of a page buffer without the per-BCB pthread mutex (`PGBUF_BCB_LOCK`), grilled with
grill-with-tla from 2026-11-15. Base code: develop `4bf2b2e32` (CBRD-27970 merged), whose latch model
is `docs/tla/CBRD-27970-27971/`. Model: `BucketLatch.tla` (plain TLA+, one step = one bucket-latch
critical section). The options not taken stay as constants for the comparison cfgs (`PromoteWait`, `WakeAtEnd`).

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
| D13 | A promotion that is not alone (or meets a write in progress) fails with `ER_PAGE_LATCH_PROMOTE_FAIL` and the caller re-fixes WRITE; no promotion waits (`PromoteWait = FALSE`; the waiting variant breaks C9 under D8, `mutant-promote-wait`) | 2026-11-15 |
| D14 | Whoever leaves a waiter blocked only by a write in progress — the last unfix, a failed promotion releasing its READ, a waiter leaving the list — sets the write-waiter flag, so the end of the write wakes it (`WakeAtEnd = "flag"`; the flag set only by waiters strands one, `mutant-wake-none`) | 2026-11-15 |
| D12 | A waiter removes its own entry (woken, timed out, interrupted, spuriously woken) under the exclusive bucket latch and then applies the wake rule to the waiters left (passes the wakeup on); a victim search tries the candidate's bucket latch without waiting and moves on | 2026-11-15 |
| D15 | A failed page read of a claim empties the BCB under the exclusive bucket latch and wakes every waiter on it; each removes its own entry, sees the BCB no longer holds its page and searches the chain again (D7 applied to the read error: D4 and D12 unchanged; develop's waiters wait on the hash anchor until the read ends) | 2026-11-16 |

## Settled by TLC (history)

- `PromoteWait`: a promotion that is not alone either releases its READ and waits for WRITE
  (develop's `PGBUF_PROMOTE_SHARED_READER`, today the waiting promoter is queued first) or fails with
  `ER_PAGE_LATCH_PROMOTE_FAIL` so the caller re-fixes WRITE (every caller has that path). With D8 the
  waiting variant breaks C9 (`probe-true-*`).
- `WakeAtEnd`: a waiter blocked only by a write in progress, whose blocker was a READ holder, is woken
  either because the releaser that leaves it so sets the write-waiter flag ("flag") or because the end
  of a write always applies the wake rule when the list is not empty ("always"); D11 alone ("none")
  strands it (`probe-false-none`).
- The bucket latch is the existing per-bucket `hash_mutex` replaced by the read-write latch
  (1M buckets, `HASH_SIZE_BITS 20`).

## Open decisions

None.

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
| C6 | a waiter entry belongs to a thread asleep on it, waiting for the page the BCB still holds, or for no page once the read of that page failed (the waiter then removes its entry and searches the chain again) | safety | D12; D15 |
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

## Mutants

Each re-enables one wrong ordering or missing guard; the cfg's bounds are the main cfg's with
`MaxSpur = 1` unless noted.

| Mutant cfg | Re-enables | Claim | Expect |
|---|---|---|---|
| `mutant-claim-ignores-fix` | a victim taken while fixed | C1 | violation `FcntExact` |
| `mutant-write-ignores-readers` | WRITE granted beside READ holders | C2 | violation `Exclusive` |
| `mutant-pin-after-latch` | the chain lookup under the latch, the fix-count CAS after releasing it | C3 | violation `SamePage` |
| `mutant-write-ignores-writing` | WRITE fix and in-place promotion while the write-in-progress flag is set | C4 | violation `NoWriteDuringCopy` |
| `mutant-claim-dirty` | a dirty page taken as a victim | C5 | violation `NoLostUpdate` |
| `mutant-flerr-no-redirty` | a failed copy leaves the page clean | C5 | violation `NoLostUpdate` |
| `mutant-claim-ignores-waiters` | a victim taken while it has waiters | C6 | violation `NoStaleWaiter` |
| `mutant-timeout-no-remove` | a timed-out waiter leaves its entry behind | C6 | violation `NoStaleWaiter` |
| `mutant-unfix-no-post` | the last unfix wakes nobody | C7 | violation `NoStrandedWaiter` |
| `mutant-flend-no-post` | the end of a write wakes nobody | C7 | violation `NoStrandedWaiter` |
| `mutant-leave-no-pass` | a waiter leaving the list does not pass the wakeup on | C7 | violation `NoStrandedWaiter` |
| `mutant-wake-none` | `WakeAtEnd = "none"`: only waiters that saw the write set the flag (option not taken, D14) | C7 | violation `NoStrandedWaiter` |
| `mutant-victim-wait` | the victim search waits for the candidate's bucket latch, each thread walking its own LRU order (NP = 4, MaxOps = 1, Ops = {"R"}, no faults, no daemon) | C7 | deadlock |
| `mutant-miss-no-latch` | a miss looks for a victim without holding its bucket latch | C8 | violation `UniqueResident` |
| `mutant-loaderr-no-post` | a failed page read leaves the waiters on the emptied BCB asleep (NP = 3, MaxOps = 1, Ops = {"R", "W"}, no other fault, no daemon) | C7 | violation `NoStrandedWaiter` |
| `mutant-promote-wait` | `PromoteWait = TRUE`: a promotion releases its READ and waits (option not taken, D13) | C9 | violation `PromoteStable` |

## Witnesses

| Witness cfg | Reachable outcome |
|---|---|
| `witness-barged` | a READ is granted while a WRITE waiter is queued (D8) |
| `witness-write-waits-for-copy` | a WRITE fix waits for a write in progress (D10) |
| `witness-flush-waiter` | a synchronous flush waits on the page (D11) |
| `witness-reclaimed` | a miss takes a victim and loads the page |
| `witness-copy-failed` | a page copy fails (C5's error path) |
| `witness-timed-out-retry` | a worker holds a page after a latch timeout happened |

## Dead expressions

TLC reports per cfg the sub-expressions it never evaluated. Every line below is a branch another cfg
fires (named), a mutant-only or comparison-only branch, or one call site of an operator whose other
call sites fire (TLC counts an operator body once per call site). None maps to code that is unreachable.

| Lines | Where | Why dead in that cfg | Fired by |
|---|---|---|---|
| BucketLatch.tla:230 BucketLatch.tla:231 BucketLatch.tla:232 | `FixShared`, the `pin_after_latch` branch | mutant only | `mutant-pin-after-latch` |
| BucketLatch.tla:247 BucketLatch.tla:248 BucketLatch.tla:249 BucketLatch.tla:250 BucketLatch.tla:251 | `Pin` | a step of the mutant `pin_after_latch` only | `mutant-pin-after-latch` |
| BucketLatch.tla:256 BucketLatch.tla:257 BucketLatch.tla:258 BucketLatch.tla:259 BucketLatch.tla:260 BucketLatch.tla:261 BucketLatch.tla:262 BucketLatch.tla:263 | `Enqueue` body | the call site in `Promote`'s waiting branch (`PromoteWait = TRUE`, comparison only); the `FixExcl` call sites fire in every pass cfg | `mutant-promote-wait` |
| BucketLatch.tla:159 | `Post` body | the call site in `LoadErr` (`MaxErr = 0`) or `Promote` (no `"P"`) in `env` and `cond` | `BucketLatch` |
| BucketLatch.tla:278 BucketLatch.tla:279 | `FixExcl`, a conditional READ (`Rc`) that fails on a WRITE holder | `Ops` has no `"Rc"` | `BucketLatch.cond` |
| BucketLatch.tla:293 BucketLatch.tla:294 | `FixExcl`, a conditional WRITE (`Wc`) that fails | `Ops` has no `"Wc"` | `BucketLatch.cond` |
| BucketLatch.tla:300 BucketLatch.tla:301 BucketLatch.tla:305 BucketLatch.tla:306 BucketLatch.tla:307 BucketLatch.tla:308 BucketLatch.tla:309 BucketLatch.tla:310 BucketLatch.tla:311 BucketLatch.tla:312 BucketLatch.tla:314 BucketLatch.tla:315 | `FixExcl`, the synchronous flush (`C`) | `cond` has no `"C"` | `BucketLatch` |
| BucketLatch.tla:370 BucketLatch.tla:371 BucketLatch.tla:372 | `MissGiveUp` | `liveness` (`MaxOps = 1`): every miss finds a victim | `BucketLatch` |
| BucketLatch.tla:396 BucketLatch.tla:399 BucketLatch.tla:400 BucketLatch.tla:401 BucketLatch.tla:403 BucketLatch.tla:404 BucketLatch.tla:405 | `LoadErr` | `MaxErr = 0` in `env` and `cond` | `BucketLatch` |
| BucketLatch.tla:414 BucketLatch.tla:415 BucketLatch.tla:417 BucketLatch.tla:418 BucketLatch.tla:419 BucketLatch.tla:423 BucketLatch.tla:424 BucketLatch.tla:425 BucketLatch.tla:426 BucketLatch.tla:427 BucketLatch.tla:429 BucketLatch.tla:431 BucketLatch.tla:436 | `Promote` | `env` and `cond` have no `"P"` | `BucketLatch` |
| BucketLatch.tla:432 BucketLatch.tla:433 BucketLatch.tla:434 | `Promote`, the waiting branch | `PromoteWait = TRUE` only (D13, comparison) | `mutant-promote-wait` |
| BucketLatch.tla:471 | `WakeRetry`, the spurious branch | `MaxSpur = 0` | `BucketLatch.env` |
| BucketLatch.tla:502 BucketLatch.tla:503 | `Copy`, the copy error | `MaxErr = 0` in `env` and `cond` | `BucketLatch` |
| BucketLatch.tla:519 BucketLatch.tla:520 | `CopyEnd`, the error branch | `MaxErr = 0` in `env` and `cond` | `BucketLatch` |
| BucketLatch.tla:564 BucketLatch.tla:565 BucketLatch.tla:566 BucketLatch.tla:567 | `Invalidate` | `MaxEnv = 0` | `BucketLatch.env` |

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
| `LoadErr` | `pgbuf_claim_bcb_for_fix` read failure (`fileio_read` NULL, `tde_decrypt_data_page` error) → `pgbuf_put_bcb_into_invalid_list`, `pgbuf_unlock_page`; the waiters are now on the BCB (develop keeps them on the hash anchor's page lock until the read ends) | exclusive section |
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
| conditional latch failure | yes | `Rc`, `Wc` (cfg `cond`), the victim search's no-wait try (`CandLatchOk`) |
| OOM | n/a | nothing is allocated (waiter entries are per thread) |
| crash / `kill -9` | n/a | volatile buffer state |
| spurious wakeup | yes | `WakeRetry(t, TRUE)`, budget `MaxSpur` |
| concurrent DML | yes | WRITE holders change pages (`Unfix` of a WRITE) |
| vacuum | n/a | fixes through the same paths |
| checkpoint, page flush, page replacement | yes | synchronous flush (`C`), the flush daemon, victim claim |
| page read error after a claim | yes | `LoadErr` (budget `MaxErr`, shared with the copy error): the BCB leaves the chain empty and every waiter on it is woken (D15) |
| HA log apply | n/a | no protocol difference |
| fairness | weak fairness per process step; none on faults | a WRITE waiter can lose to newcomers (D8); termination holds because every worker has a finite budget |

## Result

2026-11-16, `tools/tla/tla-check --workers 8 docs/tla/bcb-mutex-removal` → **RESULT: OK**
(run dir `.git_ignored_dir/scratch/tla/bcb-mutex-removal-20261116-040414-603034`).
`BucketLatch.tla` sha256 `67baff7e2ab1965d000a69a7fe9cfa110f951c6dbbba52cedd165ca083735416`, `BucketLatchInd.tla` sha256 `126390b5f425fd2c65bd61439d2ac1c3465cfa4e35d5ba4847a75243763a4277`.

| cfg | Constants | States (generated/distinct) | Depth | Time |
|---|---|---|---|---|
| `BucketLatch` | NT 2, NB 2, NP 3, NK 2, MaxOps 2, Ops R W P C, 1 timeout, 1 I/O error, daemon | 108,661,607 / 43,364,976 | 55 | 2397 s |
| `BucketLatch.env` | Ops R W C, 1 timeout, 1 spurious wakeup, 1 invalidation | 127,102,807 / 50,084,602 | 51 | 2545 s |
| `BucketLatch.cond` | Ops R W Rc Wc, 1 timeout | 24,498,653 / 9,739,153 | 46 | 491 s |
| `BucketLatch.scale-3t` | NT 3, MaxOps 1 | 30,339,406 / 10,870,401 | 44 | 619 s |
| `BucketLatch.liveness` | FairSpec, `Termination`, MaxOps 1 | 72,111 / 34,708 | 27 | 5 s |
| 16 mutants | each fails as expected (15 invariant violations, `victim-wait` deadlock) | 427 – 1,545,638 | 6 – 14 | ≤ 18 s |
| 6 witnesses | each reached | 457 – 15,394 | 5 – 8 | ≤ 2 s |
| `BucketLatchInd.apalache-indinv` | Apalache, `IndInv` inductive (15 conjuncts, every claim's invariant among them), constants by `CInit` | — | 1 step | 3685 s |

TLAPS 요청 없음. trace-exempt (above): a design, no implementation yet.
