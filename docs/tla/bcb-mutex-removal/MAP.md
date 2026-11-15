# BCB mutex removal — TLA+ map (design, grill in progress)

Design of a page buffer without the per-BCB pthread mutex (`PGBUF_BCB_LOCK`), grilled with
grill-with-tla from 2026-11-15. Base code: develop `4bf2b2e32` (CBRD-27970 merged), whose latch model
is `docs/tla/CBRD-27970-27971/`. No model yet: the spec is written once the latch structure
(open decisions below) is settled; open choices then become constants TLC explores.

## Settled decisions

| # | Decision | Date |
|---|---|---|
| D1 | Goal: both serial instructions and concurrent contention; acceptance by contention on the perf servers (wall time, TPC-C and read-heavy YCSB), serial `instructions:u` as a no-regression check, write-heavy load must not slow down | 2026-11-15 |
| D2 | Scope: the BCB mutex goes from every path (fix, unfix, WRITE, promotion, waiters, flush, victim, invalidate) | 2026-11-15 |
| D3 | A BCB's state (fix count, latch mode, waiter list, vpid, flush state) changes only under a hash-bucket read-write latch (CAS-based, shared and exclusive modes): a fix holds it shared and raises the count atomically; a victim claim, an invalidation and an identity change hold it exclusive and require no fix and no waiter. A victim search takes a candidate's bucket latch without waiting and moves on when it cannot | 2026-11-15 |
| D4 | Waiters are woken, not granted: the releaser collects the waiters compatible with the latch it leaves (stopping at the first exclusive one) under the bucket latch and wakes them after releasing it; a woken waiter retries the fix from the hash chain | 2026-11-15 |
| D5 | The last unfix leaves only a time-gated use mark; LRU boosts and the VOID→LRU insertion move to the victim scan and the claim (second chance). Buffer hit ratio joins the D1 measurements | 2026-11-15 |
| D6 | Verified as one design (this directory), delivered as staged PRs: READ fix/unfix + claim → waiters → WRITE, promotion, flush → LRU | 2026-11-15 |

## Open decisions

- Flush: how a page copy for the write is kept apart from a WRITE holder, and whether a writer waits
  for an in-flight write (analysis in progress).
- A woken waiter versus a newcomer (barging), the bucket latch's identity (the existing per-bucket
  `hash_mutex` or a new array) and its granularity, whether an unfix without waiters takes the bucket
  latch.

## Claim and sources

To be written from the CBRD-27970-27971 claims C1–C9 (fix count exact, latch exclusivity, same page,
waiter bit, no stranded waiter, flush progress) plus the claims D3–D5 add.
