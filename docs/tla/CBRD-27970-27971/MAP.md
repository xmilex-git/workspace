# CBRD-27970 + CBRD-27971 — joint fix design, TLA+ ledger

Design spec for one PR that fixes both regressions of the CBRD-26425 atomic latch found by
`docs/tla/CBRD-26425-atomic-latch/` (H1 = CBRD-27970, H4 = CBRD-27971). `AtomicLatch.tla` is that
directory's code model (develop `21c6e635d`; `src/storage/page_buffer.c` is unchanged up to
`953e83256`, 2026-11-06) with the design decisions added as constants. Every settled decision is
written here and in the spec the round it is settled; an open one is a constant TLC explores.

trace-exempt: design spec before the implementation exists; the implementation's spec adds the trace (cubrid-tla step 9)

## Claim and sources

| Claim | Statement | Kind | Source |
|---|---|---|---|
| C1 | `fcnt` equals the fixes the threads hold (or were handed); `latch_mode = PGBUF_NO_LATCH` exactly when `fcnt = 0`; never negative | safety | `docs/tla/CBRD-26425-atomic-latch/MAP.md` C1 |
| C2 | a WRITE latch has exactly one holder and no reader beside it; an idle latch has no holder | safety | same, C2 |
| C3 | `pgbuf_fix (vpid)` returns the BCB of `vpid` | safety | same, C3; CBRD-27970 Expected Result |
| C4 | while a reader or writer waits in the BCB queue, `waiter_exists` is set | safety | same, C4 |
| C5 | a thread holding the BCB mutex never spins in the idle-grant CAS, and the CBRD-27084 heal never fires | safety | same, C5; CBRD-27971 Expected Result |
| C6 | `pgbuf_wakeup_reader_writer`'s CAS never fails | safety | same, C6 |
| C7 | no waiter is stranded; every thread and flusher finishes | safety + liveness | same, C7; CBRD-27971 Expected Result ("backupdb와 loaddb도 끝납니다") |
| C8 | every flush attempt ends by clearing FLUSHING and waking the FLUSH waiters | liveness | same, C8 |
| C9 | a FLUSH waiter never makes a reader wait: a READ fix that finds a READ latch with no reader or writer queued is granted even while a FLUSH waiter is queued | safety (action) | pre-CBRD-26425 code (`58cef8e01f^` `pgbuf_latch_bcb_upon_fix` case 1 tests `pgbuf_is_exist_blocked_reader_writer`, R/W only); adopted with D1 (user, 2026-11-06) |
| C10 | every synchronous flush that finds the page dirty ends, however many readers keep fixing and unfixing it | liveness | the user's fairness question on D1 (2026-11-06: "flush가 무한하게 뒤로 밀려서 공정하지 않은 구현이 되지 않아?"); `pgbuf_bcb_safe_flush_internal` comment (a FLUSH waiter waits only for a writer's unfix or the flush in flight); needs strong fairness of the BCB mutex for the relock after the write (`SpecEndless`), an assumption develop needs too |

## Design decisions

| Id | Decision | Status | Evidence |
|---|---|---|---|
| D1 | CBRD-27971: a synchronous flusher queued as `PGBUF_LATCH_FLUSH` does not set `waiter_exists` (`pgbuf_bcb_safe_flush_internal`); `waiter_exists` is raised only for a reader or writer (one queues, or a conditional request is refused) and every clear site already tests readers and writers only; the idle-grant CAS keeps expecting `waiter_exists == false`. Rejected: keep the observed bit in the idle grant (JIRA body draft), which leaves C9 violated | settled (user, 2026-11-06) | `FlushBit = FALSE`, `Code ∋ "H4"`: `scale-3t-2f` pass (2153508 distinct, depth 57); rejected option: `mutant-opta-convoy` violation `NoFlushConvoy` depth 23 (f1 writing, t3 re-dirties, t1 READ, f2 queues FLUSH and sets the bit, t2's READ fix blocks in case 1) |
| D2 | CBRD-27970: after the lock-free CAS succeeds, re-read `bufptr->vpid`; on a mismatch undo the fix and take the slow path. The fix pins the BCB (`fcnt > 0`), so the re-read is stable. Rejected: a generation count in the latch word (only 15 spare bits, it wraps; every claim, victimize and invalidate must bump it) | settled (user, 2026-11-06) | `ext-torn` pass; `mutant-code-h1` violation `SamePage` depth 20 |
| D3 | PR scope: H1 and H4 only; H2 and A (CBRD-27739), H3 (CBRD-27370) and E (not filed) stay as the code has them. Checked twice: `pr-*` cfgs keep them (`Code = {"H4","H2","H3","A","E"}`) with their triggers bounded off (`Faults` without `latch_intr` and `early_err`, `MaxHold = 1`) but FLUSH interrupts and I/O errors on; the other pass cfgs compose with their candidate fixes (`Code = {"H4"}`) | settled (user, 2026-11-06) | `pr-all` pass (2740946 distinct, depth 61), `pr-ext-flush` pass (163234, 41; fires `FzIrm` and the I/O error), `pr-ext-torn` pass (103688, 51); `pr-3t-2f` timed out at 1800 s under host load 115+, rerun with a longer timeout |
| D4 | claims: C1–C8 carried over from the CBRD-26425 model unchanged, C9 with D1, C10 added | settled (user, 2026-11-06) | Claim table |
| D5 | C10's environment: endless readers (`Endless`), strong fairness on the relock after the flush write (`SpecEndless`); contrast mutant `flush_needs_idle` (a READ latch makes the flusher retry) | settled (user, 2026-11-06) | `endless` pass (27599 distinct, depth 59); `mutant-flush-needs-idle` liveness violation of `FlushProgress` (depth 59) |
| D6 | delete CBRD-27084's two `waiter_exists` clears that existed for FLUSH waiters: the end of `pgbuf_wake_flush_waiters` and the interrupt removal in `pgbuf_block_bcb (PGBUF_LATCH_FLUSH)`; with D1 no FLUSH waiter raises the bit, and a stale bit a conditional reject or a latch timeout leaves is cleared by the next last unfix (`pgbuf_wakeup_reader_writer`) | settled (user, 2026-11-06) | with both clears off, `ext-flush` (fires `FzIrm`) and `all-2f` pass (run 2026-11-06, before the knob was folded into the spec) |
| D7 | keep CBRD-27084's heal in `pgbuf_latch_bcb_upon_fix` (debug assert, release clear): it never fires (C5) and keeps an unknown future leak from becoming a spin | settled (user, 2026-11-06) | `NoSpin` in every pass cfg |
| D8 | verification: the instrument patch and repro scripts of the two JIRA issues on develop optdebug and on the fix optdebug (fail-before `lf_aba` / `idle_spin`; pass-after: no such line, the H1 undo path traced, SELECT, backupdb and loaddb finish), release and optdebug builds, CTP sql and medium; no new CTP TC, since both windows open only with injected delays (reason written in JIRA) | settled (user, 2026-11-06) | — |
| D9 | H1 undo: always under the BCB mutex through the existing `pgbuf_unlatch_bcb_upon_unfix` (last-unfix handling, wakeup, LRU, async flush), with the vpid re-read before the holder entry is allocated. Rejected: a lock-free decrement first (`pgbuf_lockfree_unfix_ro` decrements the debug pgbuf tracker, which `pgbuf_fix` increments only after the return, so it would be a second copy of the CAS loop) | settled (user, 2026-11-06) | both variants passed `ext-torn` bounds (`undo-locked-ext-torn` 324808 distinct, `ext-torn` 323612); the spec keeps the locked one |
| D10 | no performance measurement: the re-read is one load of `vpid` (BCB offset 44) on the cache line the CAS on `atomic_latch` (offset 56) just took exclusive, and D1 lets more readers take the lock-free path; the PR and the report say "not measured" with these reasons | settled (user, 2026-11-06) | — |
| D11 | one engine PR: branch and title keyed `CBRD-27970` (title verbatim from JIRA), body links both issues with one section each; CBRD-27971 gets a comment pointing to the PR | settled (user, 2026-11-06) | — |


## Refinement map (model -> code)

Code at `21c6e635d` (unchanged to `953e83256`), `src/storage/page_buffer.c`. Every row of
`docs/tla/CBRD-26425-atomic-latch/MAP.md` "Refinement map" holds here unchanged, with the callers of
the entry points listed there; the rows below are the ones this design adds or changes.

| Model | Code (after the fix) | One step because |
|---|---|---|
| `LfRecheck` | `pgbuf_lockfree_fix_ro`, after the successful `compare_exchange_weak`: re-read `bufptr->vpid` (D2) and compare with `vpid`, before `pgbuf_find_thrd_holder` / `pgbuf_allocate_thrd_holder_entry` | a plain read of a field no thread writes while `fcnt > 0` (victim claim and invalidation need `fcnt == 0` under the BCB mutex); the CAS that made `fcnt > 0` acquired the claimer's release (MAP of CBRD-26425, "Memory order") |
| `LfRecheck` → `uf_lock` → `UfUnl` → `Wk` → `UfAsync` | mismatch: `PGBUF_BCB_LOCK`, `pgbuf_unlatch_bcb_upon_unfix (thread_p, bufptr, NO_ERROR)` (D9), return NULL so `pgbuf_fix` takes the slow path | the existing BCB-mutex unlatch rows; no holder entry and no pgbuf tracker entry exist yet |
| `FzDec` (blocking branch) | `pgbuf_bcb_safe_flush_internal`: decide immediate flush / block from `latch_mode` and FLUSHING under the BCB mutex; block with `pgbuf_block_bcb (…, PGBUF_LATCH_FLUSH, 0, false)` without touching `waiter_exists` (D1, `FlushBit = FALSE`) | under the BCB mutex; `latch_mode` changes only under it (the lock-free paths change `fcnt` of a READ latch only), so the decision needs no CAS |
| `Block` / `pgbuf_block_bcb` | `assert (waiter_exists)` holds for READ and WRITE requests only (D1) | — |
| `MFix` idle grant, claim branch | unchanged: the CAS expects `waiter_exists == false` (`Code ∋ "H4"`); true now, since only a reader or writer raises the bit and none waits at an idle latch (C7) | under the BCB mutex |
| `WakeFlushWaiters` | `pgbuf_wake_flush_waiters` without its trailing `set_waiter_exists (…, false)` (D6) | under the BCB mutex |
| `FzIrm` | `pgbuf_block_bcb (PGBUF_LATCH_FLUSH)` interrupt removal without its `set_waiter_exists (…, false)` (D6) | under the BCB mutex |
| `Begin` for `Endless` | a reader session that keeps fixing the page READ (C10's environment, no code row of its own) | thread-local |
| `fbit` | ghost: the bit was raised by a FLUSH waiter and no reader or writer raised it since; only the rejected option (`FlushBit = TRUE`) sets it | — |

## Properties

| Property | Claims | Checked by |
|---|---|---|
| `FcntExact` | C1 | TLC invariant |
| `Refines` (`PageLatch!Spec`) | C2, C4 | TLC refinement; `PageLatch`'s `IndInv` (with `Exclusive`, `WaiterBit`) inductive by `PageLatch.inductive-indinv` |
| `SamePage` | C3 | TLC invariant |
| `NoSpin` | C5 | TLC invariant |
| `NoDoubleLock` | C6 | TLC invariant |
| `NoStrandedWaiter`, `AllDone` | C7 | TLC invariant; TLC liveness (weak fairness per thread and flusher, deadlock check on) |
| `AllDone`, deadlock check | C8 | a FLUSH waiter never woken leaves its flusher short of `Done` |
| `NoFlushConvoy` | C9 | TLC action property |
| `FlushProgress` | C10 | TLC liveness under `SpecEndless` (strong fairness of the relock after the flush write) |

## Fault model

The CBRD-26425 fault table holds unchanged (error returns, interrupts, latch timeout, conditional
latch failure, OOM n/a, crash n/a, spurious wakeup, concurrent DML, vacuum n/a, checkpoint / page flush /
replacement, invalidation, torn reads, several BCBs, memory order argued, SA mode n/a,
`pgbuf_simple_fix` n/a by contract, holder watchers n/a, HA n/a). This design splits the fault switch
per kind (`Faults`) so the PR state can keep the holes it does not fix (D3):

| Fault | Composition cfgs (`Code = {"H4"}`) | PR cfgs (`Code = {"H4","H2","H3","A","E"}`) |
|---|---|---|
| latch timeout / interrupt of a R/W waiter (`latch_intr`) | on where `MaxTimeouts > 0` | off: it opens H2 and A (CBRD-27739) |
| interrupt of a FLUSH waiter (`flush_intr`) | on | on (`pr-ext-flush`, `pr-all`, `pr-3t-2f`): D6 removes the clear in this path |
| error before the flush write (`early_err`) | on where `MaxErr > 0` | off: it opens E |
| flush write error (`io_err`) | on where `MaxErr > 0` | on (`pr-ext-flush`, `pr-all`) |
| a READ holder's WRITE re-fix | `MaxHold = 2` cfgs | off (`MaxHold = 1`): it opens H3 (CBRD-27370) |
| endless readers (C10) | — | `endless` (`Endless = {t2}`, no faults) |

Fairness: weak fairness on every thread, flusher and the post-flush daemon; none on faults. C10 adds
strong fairness on `Lock(p, "fl_relock", "fl_done")`: a pthread mutex is not FIFO, and a flush that
cannot relock after its write never clears FLUSHING. develop needs the same assumption (its readers
also take the BCB mutex to queue), and D1 lowers the mutex traffic (more readers stay lock-free).

## Mutants

| Mutant cfg | Re-enables | Claim | Expect |
|---|---|---|---|
| `mutant-lf-unfix-last` | lock-free unfix of the last fix | C1 | violation `FcntExact` |
| `mutant-lf-any-mode` | lock-free fix on a WRITE latch | C2 | refinement |
| `mutant-lf-no-vpid-check` | lock-free fix without any vpid check | C3 | violation `SamePage` |
| `mutant-code-h1` | the code: vpid checked only before the CAS (CBRD-27970) | C3 | violation `SamePage` |
| `mutant-block-no-bit` | queue a reader or writer without raising `waiter_exists` | C4 | refinement |
| `mutant-code-h4` | the code: FLUSH waiters raise `waiter_exists` and the idle grant expects it clear (CBRD-27971) | C5 | violation `NoSpin` |
| `mutant-lf-fix-ignores-bit` | lock-free fix while a waiter is queued | C6 | violation `NoDoubleLock` |
| `mutant-unlatch-no-wakeup` | last unfix does not wake the queue | C7 | violation `NoStrandedWaiter` |
| `mutant-flerr-no-wake` | the I/O error path does not wake the FLUSH waiters | C8 | deadlock |
| `mutant-opta-convoy` | the rejected D1 option: FLUSH waiters raise the bit, the idle grant keeps it; checks only `NoFlushConvoy`, since with D6 this option also trips the CBRD-27084 heal (`NoSpin`, depth 20): D6 holds only together with D1 | C9 | violation `NoFlushConvoy` |
| `mutant-flush-needs-idle` | a READ latch makes a synchronous flusher retry instead of flushing | C10 | liveness |

CBRD-26425's `mutant-flush-wake-no-clear` and `mutant-flush-intr-no-clear` are gone: D6 deletes the
clears they removed, and with D1 nothing depends on them (`noreconcile-*` runs, D6).

## Witnesses

| Witness cfg | Outcome shown reachable |
|---|---|
| `witness-join-past-flush-waiter` | (D1) a reader joins a READ latch while a FLUSH waiter is queued |
| `witness-idle-grant-past-flush-waiter` | (D1) the H4 interleaving — a FLUSH waiter queued on an idle latch — ends in an idle grant |
| `witness-flush-wait-at-idle` | a FLUSH waiter is queued on an idle latch |
| `witness-recheck-miss` | (D2) the ABA of H1 happens and the post-CAS re-check catches it |
| `witness-woken-from-queue` | a queued waiter is handed the latch by the waker |
| `witness-timed-out-gave-up` | a waiter times out and runs the error handler |
| `witness-promoted-by-wait` | a promoter waits at the queue head and is granted WRITE |
| `witness-lock-free-shared` | two readers share a latch through the lock-free fix |
| `witness-wait-on-handoff` | a FLUSH waiter is queued while the BCB sits in the post-flush queue |
| `witness-io-error` | a flush write fails and its flusher relocks to restore DIRTY and wake the waiters |
| `witness-flush-intr` | an interrupted FLUSH waiter removes itself from the queue |
| `witness-reclaim-after-inval` | a page is invalidated and the BCB is claimed again |
| `PageLatch.witness-shared` | the abstract latch has two readers |
## Dead expressions (pass cfgs)

Never evaluated in **any** pass cfg (`all-2f`, `all-3t`, `cond-read-3t`, `endless`, `ext-flush`, `ext-torn`, `main`, `pr-3t-2f`, `pr-all`, `pr-ext-flush`, `pr-ext-torn`, `promote-3t`, `refix-3t`, `scale-3t-2f`):

| Line | Why |
|---|---|
| `AtomicLatch.tla:134` | the `Go` body, which TLC counts at its call sites; every live call site evaluates it |
| `AtomicLatch.tla:246` | the H4 spin branch of `MFix` (claim): with D1 no FLUSH waiter raises `waiter_exists`, so an idle latch never carries it (`NoSpin` in every pass cfg); `mutant-code-h4` fires it |
| `AtomicLatch.tla:247` | same H4 spin branch (claim) |
| `AtomicLatch.tla:256` | the H4 spin branch of the idle grant, unreachable for the same reason; `mutant-code-h4` fires it |
| `AtomicLatch.tla:257` | same H4 spin branch (idle grant) |
| `AtomicLatch.tla:347` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |
| `AtomicLatch.tla:349` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |
| `AtomicLatch.tla:356` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |
| `AtomicLatch.tla:359` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |
| `AtomicLatch.tla:360` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |
| `AtomicLatch.tla:366` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |
| `AtomicLatch.tla:368` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |
| `AtomicLatch.tla:374` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |
| `AtomicLatch.tla:376` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |
| `AtomicLatch.tla:380` | the `Release` body, counted at its call sites like `Go` |
| `AtomicLatch.tla:402` | the H2 split of `EhLoop` and `EhLk` (CBRD-27739) and its wrapper: `pr-*` cfgs keep H2 with `latch_intr` off (D3), composition cfgs fix H2 |
| `AtomicLatch.tla:404` | the H2 split of `EhLoop` and `EhLk` (CBRD-27739) and its wrapper: `pr-*` cfgs keep H2 with `latch_intr` off (D3), composition cfgs fix H2 |
| `AtomicLatch.tla:405` | the H2 split of `EhLoop` and `EhLk` (CBRD-27739) and its wrapper: `pr-*` cfgs keep H2 with `latch_intr` off (D3), composition cfgs fix H2 |
| `AtomicLatch.tla:406` | the H2 split of `EhLoop` and `EhLk` (CBRD-27739) and its wrapper: `pr-*` cfgs keep H2 with `latch_intr` off (D3), composition cfgs fix H2 |
| `AtomicLatch.tla:421` | the H2 split of `EhLoop` and `EhLk` (CBRD-27739) and its wrapper: `pr-*` cfgs keep H2 with `latch_intr` off (D3), composition cfgs fix H2 |
| `AtomicLatch.tla:422` | the H2 split of `EhLoop` and `EhLk` (CBRD-27739) and its wrapper: `pr-*` cfgs keep H2 with `latch_intr` off (D3), composition cfgs fix H2 |
| `AtomicLatch.tla:423` | the H2 split of `EhLoop` and `EhLk` (CBRD-27739) and its wrapper: `pr-*` cfgs keep H2 with `latch_intr` off (D3), composition cfgs fix H2 |
| `AtomicLatch.tla:424` | the H2 split of `EhLoop` and `EhLk` (CBRD-27739) and its wrapper: `pr-*` cfgs keep H2 with `latch_intr` off (D3), composition cfgs fix H2 |
| `AtomicLatch.tla:444` | the `fcnt < 0` branch of `UfUnl` (`negFcnt` ghost): reached only through H3, whose trigger (a READ holder's WRITE re-fix) the `pr-*` cfgs bound off (`MaxHold = 1`) and the composition cfgs fix |
| `AtomicLatch.tla:483` | the `doubleLock` violation ghost of `WkCas` (`mutant-lf-fix-ignores-bit` fires it) |
| `AtomicLatch.tla:484` | same `doubleLock` branch |
| `AtomicLatch.tla:509` | the `"E"` branch of `StartFlush` (an early flush error leaves FLUSHING set): `pr-*` cfgs keep E with `early_err` off (D3), composition cfgs fix E |
| `AtomicLatch.tla:510` | same `"E"` branch |
| `AtomicLatch.tla:541` | the `flush_needs_idle` mutant branch of `FzDec` (`mutant-flush-needs-idle`) |
| `AtomicLatch.tla:561` | the `flerr_no_wake` mutant branch of `FlDone` (`mutant-flerr-no-wake`) |
| `AtomicLatch.tla:652` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |
| `AtomicLatch.tla:653` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |
| `AtomicLatch.tla:654` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |
| `AtomicLatch.tla:657` | the H2 split of `EhLoop` and `EhLk` (CBRD-27739) and its wrapper: `pr-*` cfgs keep H2 with `latch_intr` off (D3), composition cfgs fix H2 |
| `AtomicLatch.tla:663` | `TimedOut`, `ToChk`, `ToSet`, `ToRetry` (hole A, CBRD-27739) and their wrappers: `pr-*` cfgs keep A with `latch_intr` off (D3), composition cfgs fix A (the timed-out branch re-locks like `Timeout`) |

Live in some pass cfg, dead only where that cfg's bounds remove the feature (flushers, the page flush daemon, flush errors, invalidation, latch timeouts, FLUSH interrupts, promotion, conditional fix, a third thread, re-fix, torn reads, two pages, H1's ABA). Every line maps to code that runs; "live in" names the pass cfgs that evaluate it:

| Line | Expression | Live in | Dead in |
|---|---|---|---|
| `AtomicLatch.tla:101` | `FbitKeep == fbit' = (fbit /\ word'.w)` | ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:197` | `ELSE hold' = [hold EXCEPT ![t] = @ - 1] /\ Go(t, "uf_lock")` | ext-torn, main, pr-all, pr-ext-torn | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-ext-flush, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:215` | `/\ mtx' = p /\ Go(p, to)` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:216` | `/\ UNCHANGED <<word, vpid, q, req, reqf, resumed, promoter, hold, want` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:222` | `/\ word' = nw` | ext-torn, main, refix-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, scale-3t-2f |
| `AtomicLatch.tla:223` | `/\ q' = Append(q, t)` | ext-torn, main, refix-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, scale-3t-2f |
| `AtomicLatch.tla:224` | `/\ req' = [req EXCEPT ![t] = rq[t]] /\ reqf' = [reqf EXCEPT ![t] = rf]` | ext-torn, main, refix-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, scale-3t-2f |
| `AtomicLatch.tla:225` | `/\ resumed' = [resumed EXCEPT ![t] = FALSE]` | ext-torn, main, refix-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, scale-3t-2f |
| `AtomicLatch.tla:226` | `/\ mtx' = None /\ Go(t, "wait")` | ext-torn, main, refix-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, scale-3t-2f |
| `AtomicLatch.tla:228` | `Grant(t, nw) == /\ word' = nw /\ hold' = [hold EXCEPT ![t] = @ + 1]` | ext-torn, main | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:229` | `/\ mtx' = None /\ Go(t, "use")` | ext-torn, main | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:231` | `Reject(t, nw) == /\ word' = nw /\ mtx' = None /\ Go(t, "idle")` | cond-read-3t | all-2f, all-3t, endless, ext-flush, ext-torn, main, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:244` | `THEN /\ vpid' = want[t] /\ valid' = TRUE` | ext-flush, ext-torn, main, pr-all, pr-ext-flush, pr-ext-torn | all-2f, all-3t, cond-read-3t, endless, pr-3t-2f, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:248` | `ELSE /\ Grant(t, Word(rq[t], w0.w, 1)) /\ UNCHANGED spin` | ext-flush, ext-torn, main, pr-all, pr-ext-flush, pr-ext-torn | all-2f, all-3t, cond-read-3t, endless, pr-3t-2f, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:249` | `/\ UNCHANGED <<q, req, reqf, resumed, promoter>>` | ext-flush, ext-torn, main, pr-all, pr-ext-flush, pr-ext-torn | all-2f, all-3t, cond-read-3t, endless, pr-3t-2f, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:250` | `ELSE /\ word' = w0 /\ mtx' = None /\ Go(t, "idle")` | ext-torn, main, pr-all, pr-ext-torn | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-ext-flush, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:251` | `/\ UNCHANGED <<vpid, valid, q, req, reqf, resumed, promoter, hold, spi` | ext-torn, main, pr-all, pr-ext-torn | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-ext-flush, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:266` | `THEN Reject(t, w0) /\ UNCHANGED <<q, req, reqf, resumed, promoter, hol` | cond-read-3t | all-2f, all-3t, endless, ext-flush, ext-torn, main, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:267` | `ELSE Block(t, [w0 EXCEPT !.w = bitOn], 1) /\ UNCHANGED <<promoter, hol` | all-3t, cond-read-3t, ext-torn, main, pr-3t-2f, pr-all, promote-3t, refix-3t, scale-3t-2f | all-2f, endless, ext-flush, pr-ext-flush, pr-ext-torn |
| `AtomicLatch.tla:270` | `/\ UNCHANGED <<q, req, reqf, resumed, promoter>>` | ext-torn, main, refix-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, scale-3t-2f |
| `AtomicLatch.tla:274` | `/\ UNCHANGED <<q, req, reqf, resumed, promoter>>` | ext-torn, main, refix-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, scale-3t-2f |
| `AtomicLatch.tla:277` | `/\ UNCHANGED <<q, req, reqf, resumed, promoter, hold>>` | cond-read-3t, main, pr-all | all-2f, all-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:281` | `/\ hold' = [hold EXCEPT ![t] = 0]` | ext-torn, main, refix-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, scale-3t-2f |
| `AtomicLatch.tla:282` | `/\ UNCHANGED promoter` | ext-torn, main, refix-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, scale-3t-2f |
| `AtomicLatch.tla:295` | `THEN mtx' = None /\ Go(t, "idle") /\ UNCHANGED <<word, q, req, reqf, r` | main, pr-all, promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:296` | `ELSE /\ word' = [word EXCEPT !.m = "W"] /\ mtx' = None /\ Go(t, "idle"` | main, pr-all, promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:297` | `/\ UNCHANGED <<q, req, reqf, resumed, promoter, hold>>` | main, pr-all, promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:299` | `THEN mtx' = None /\ Go(t, "idle") /\ UNCHANGED <<word, q, req, reqf, r` | promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, main, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:301` | `/\ word' = [word EXCEPT !.f = @ - hold[t],` | main, pr-all, promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:303` | `/\ q' = <<t>> \o q` | main, pr-all, promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:304` | `/\ req' = [req EXCEPT ![t] = "W"] /\ reqf' = [reqf EXCEPT ![t] = hold[` | main, pr-all, promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:305` | `/\ resumed' = [resumed EXCEPT ![t] = FALSE]` | main, pr-all, promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:306` | `/\ promoter' = [promoter EXCEPT ![t] = TRUE]` | main, pr-all, promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:307` | `/\ hold' = [hold EXCEPT ![t] = 0]` | main, pr-all, promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:308` | `/\ mtx' = None /\ Go(t, "wait")` | main, pr-all, promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:309` | `/\ UNCHANGED <<vpid, want, rq, cnd, lw, ehg, wi, budget, toLeft, dirty` | main, pr-all, promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:331` | `/\ toLeft' = toLeft - 1` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:332` | `/\ promoter' = [promoter EXCEPT ![t] = FALSE]` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:334` | `THEN /\ hold' = [hold EXCEPT ![t] = reqf[t]] /\ Go(t, "use") /\ UNCHAN` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:335` | `ELSE /\ req' = [req EXCEPT ![t] = "N"] /\ Go(t, "to_lock") /\ UNCHANGE` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:336` | `/\ UNCHANGED <<word, mtx, vpid, q, reqf, resumed, want, rq, cnd,` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:386` | `THEN Release(t, "idle") /\ UNCHANGED q` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:388` | `THEN q' = RemoveAll(q, t) /\ Release(t, "idle")` | all-3t, ext-flush, main | all-2f, cond-read-3t, endless, ext-torn, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:389` | `ELSE q' = Tail(q) /\ mtx' = mtx /\ Go(t, "eh_loop")` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:390` | `/\ UNCHANGED <<word, vpid, req, reqf, resumed, promoter, hold, want, r` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:399` | `THEN Release(t, "idle") /\ UNCHANGED <<word, q, resumed, ehg>>` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:407` | `ELSE /\ UNCHANGED ehg` | all-3t, ext-flush, main | all-2f, cond-read-3t, endless, ext-torn, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:409` | `THEN /\ word' = [word EXCEPT !.f = @ + reqf[c]]` | all-3t | all-2f, cond-read-3t, endless, ext-flush, ext-torn, main, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:410` | `/\ q' = Tail(q) /\ resumed' = [resumed EXCEPT ![c] = TRUE]` | all-3t | all-2f, cond-read-3t, endless, ext-flush, ext-torn, main, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:411` | `/\ Go(t, "eh_loop") /\ UNCHANGED mtx` | all-3t | all-2f, cond-read-3t, endless, ext-flush, ext-torn, main, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:412` | `ELSE Release(t, "idle") /\ UNCHANGED <<word, q, resumed>>` | all-3t, ext-flush, main | all-2f, cond-read-3t, endless, ext-torn, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:413` | `/\ UNCHANGED <<vpid, req, reqf, promoter, hold, want, rq, cnd,` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:456` | `WkEnd(t) == /\ word' = IF RWWaiting THEN word ELSE [word EXCEPT !.w = ` | all-3t, cond-read-3t, pr-3t-2f, promote-3t, refix-3t, scale-3t-2f | all-2f, endless, ext-flush, ext-torn, main, pr-all, pr-ext-flush, pr-ext-torn |
| `AtomicLatch.tla:465` | `THEN q' = RemoveAt(q, wi[t]) /\ UNCHANGED <<word, wi, lw, pc>>` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:467` | `THEN wi' = [wi EXCEPT ![t] = @ + 1] /\ UNCHANGED <<word, q, lw, pc>>` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:472` | `THEN wi' = [wi EXCEPT ![t] = @ + 1] /\ UNCHANGED <<word, q, lw, pc>>` | all-3t, cond-read-3t, pr-3t-2f, refix-3t, scale-3t-2f | all-2f, endless, ext-flush, ext-torn, main, pr-all, pr-ext-flush, pr-ext-torn, promote-3t |
| `AtomicLatch.tla:473` | `ELSE WkEnd(t) /\ UNCHANGED <<q, wi, lw>>` | all-3t, cond-read-3t, pr-3t-2f, promote-3t, refix-3t, scale-3t-2f | all-2f, endless, ext-flush, ext-torn, main, pr-all, pr-ext-flush, pr-ext-torn |
| `AtomicLatch.tla:497` | `IN /\ q' = SelectSeq(q, LAMBDA e : ~isF(e))` | ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, main, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:498` | `/\ resumed' = [e \in Procs \|-> IF e \in Range(q) /\ isF(e) THEN TRUE ` | ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, main, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:499` | `/\ UNCHANGED <<word, fbit>>` | ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, main, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:505` | `\/ /\ flushing' = TRUE /\ dirty' = FALSE /\ async' = FALSE` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:506` | `/\ Release(p, "fl_io") /\ UNCHANGED <<errLeft, word, q, resumed, fbit>` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:507` | `\/ /\ errLeft > 0 /\ errLeft' = errLeft - 1 /\ "early_err" \in Faults` | ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, main, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:513` | `/\ async' = FALSE /\ UNCHANGED <<flushing, dirty>>` | ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, main, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:536` | `THEN Release(f, "fz_next") /\ UNCHANGED <<word, q, req, resumed, flush` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:538` | `THEN StartFlush(f, "fz_next") /\ UNCHANGED req` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:543` | `THEN Release(f, "fz_next") /\ UNCHANGED <<word, q, req, resumed, flush` | ext-flush, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, main, pr-3t-2f, pr-all, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:545` | `/\ word' = [word EXCEPT !.w = IF FlushBit THEN TRUE ELSE @]` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:546` | `/\ fbit' = IF FlushBit /\ ~word.w THEN TRUE ELSE fbit` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:547` | `/\ async' = (async \/ ~flushing)` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:548` | `/\ q' = Append(q, f) /\ req' = [req EXCEPT ![f] = "F"]` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:549` | `/\ resumed' = [resumed EXCEPT ![f] = FALSE]` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:550` | `/\ Release(f, "fz_wait") /\ UNCHANGED <<flushing, dirty, errLeft>>` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:551` | `/\ UNCHANGED <<vpid, reqf, promoter, hold, want, rq, cnd, lw, ehg, wi,` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:558` | `/\ flushing' = FALSE` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:559` | `/\ dirty' = (dirty \/ ioErr[p])` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:563` | `/\ ioErr' = [ioErr EXCEPT ![p] = FALSE]` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:565` | `/\ UNCHANGED <<vpid, req, reqf, promoter, hold, want, rq, cnd, lw, ehg` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:574` | `/\ \/ /\ Go(p, "fl_relock") /\ UNCHANGED <<ioErr, errLeft, pfPend>>` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:575` | `\/ /\ errLeft > 0 /\ errLeft' = errLeft - 1 /\ "io_err" \in Faults` | ext-flush, pr-all, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, main, pr-3t-2f, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:576` | `/\ ioErr' = [ioErr EXCEPT ![p] = TRUE] /\ Go(p, "fl_relock") /\ UNCHAN` | ext-flush, pr-all, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, main, pr-3t-2f, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:577` | `\/ /\ p \in Daemons /\ ~pfPend /\ pfPend' = TRUE` | ext-flush, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, main, pr-3t-2f, pr-all, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:578` | `/\ Go(p, "fz_next") /\ UNCHANGED <<ioErr, errLeft>>` | ext-flush, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, main, pr-3t-2f, pr-all, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:579` | `/\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold,` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:588` | `/\ pfPend' = FALSE /\ flushing' = FALSE` | ext-flush, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, main, pr-3t-2f, pr-all, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:590` | `/\ UNCHANGED <<mtx, vpid, req, reqf, promoter, hold, want, rq, cnd, lw` | ext-flush, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, main, pr-3t-2f, pr-all, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:603` | `/\ envLeft' = envLeft - 1 /\ valid' = FALSE /\ dirty' = FALSE` | ext-flush, ext-torn, pr-ext-flush, pr-ext-torn | all-2f, all-3t, cond-read-3t, endless, main, pr-3t-2f, pr-all, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:604` | `/\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold,` | ext-flush, ext-torn, pr-ext-flush, pr-ext-torn | all-2f, all-3t, cond-read-3t, endless, main, pr-3t-2f, pr-all, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:610` | `/\ toLeft' = toLeft - 1 /\ Go(f, "fz_ilock")` | ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:611` | `/\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold,` | ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:620` | `/\ q' = q2` | ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:621` | `/\ UNCHANGED word    \* D6: the CBRD-27084 clear after the removal is ` | ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:622` | `ELSE UNCHANGED <<q, word>>` | ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:624` | `/\ UNCHANGED <<vpid, req, reqf, resumed, promoter, hold, want, rq, cnd` | ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:629` | `/\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold,` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:634` | `/\ budget' = [budget EXCEPT ![f] = @ - 1]` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:636` | `/\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold,` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:650` | `PrFix(t) == PrFix_(t) /\ UNCHANGED extra0 /\ fbit' = IF pc'[t] = "wait` | main, pr-all, promote-3t | all-2f, all-3t, cond-read-3t, endless, ext-flush, ext-torn, pr-3t-2f, pr-ext-flush, pr-ext-torn, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:655` | `Eh(t) == Eh_(t) /\ UNCHANGED extra` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:656` | `EhLoop(t) == EhLoop_(t) /\ UNCHANGED extra` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:662` | `Timeout(t) == Timeout_(t) /\ UNCHANGED extra` | all-3t, ext-flush, ext-torn, main | all-2f, cond-read-3t, endless, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:664` | `FzIrm(f) == FzIrm_(f) /\ UNCHANGED extra0 /\ FbitKeep` | ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:665` | `FzWait(f) == FzWait_(f) /\ UNCHANGED extra` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:666` | `FzNext(f) == FzNext_(f) /\ UNCHANGED extra` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:667` | `FzIntr(f) == FzIntr_(f) /\ UNCHANGED extra` | ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush | all-2f, all-3t, cond-read-3t, endless, ext-torn, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f |
| `AtomicLatch.tla:668` | `Lock(p, from, to) == Lock_(p, from, to) /\ UNCHANGED extra` | all-2f, endless, ext-flush, main, pr-3t-2f, pr-all, pr-ext-flush, scale-3t-2f | all-3t, cond-read-3t, ext-torn, pr-ext-torn, promote-3t, refix-3t |
| `AtomicLatch.tla:688` | `/\ UNCHANGED vars` | all-2f, all-3t, cond-read-3t, ext-flush, ext-torn, main, pr-3t-2f, pr-all, pr-ext-flush, pr-ext-torn, promote-3t, refix-3t, scale-3t-2f | endless |

## Bounds and what the model does not cover

One BCB. Main cfg: 2 threads, 1 flusher, 2 pages, 2 operations and 2 holds per thread, 1 latch
timeout, conditional WRITE fix and promotion. The scale cfg (`scale-3t-2f`) goes one size up in
threads and flushers (3 threads, 2 flushers, 1 page, no timeout); `all-3t`, `cond-read-3t`,
`promote-3t` and `refix-3t` cover three threads with timeouts, conditional reads, promotion and
re-fixes one feature at a time, as the CBRD-26425 model's scale did not fit this host's load
(that cfg, 3 threads × 2 flushers × 2 pages × timeouts × promotion, took 9532 s unloaded).
C10 is checked with one endless reader beside one finite thread and two flushers. Not covered,
as in the CBRD-26425 model: several BCBs beyond `TornReads`, memory order (argued there), the
holder-entry allocation failure, SA mode, `pgbuf_simple_fix`. IndInv: `PageLatch`'s (C2, C4) by
TLC's inductive cfg; TLAPS 요청 없음 (cubrid-tla P48). Trace validation: trace-exempt (design
before implementation, line at the top); the implementation's spec adds it (cubrid-tla step 9).

## Result

Run 2026-11-06 16:16 KST, `tools/tla/tla-check --workers 8 --heap 16g docs/tla/CBRD-27970-27971`, run dir
`.git_ignored_dir/scratch/tla/CBRD-27970-27971-20261106-161619-645823`. Last line: `RESULT: OK`. Model of develop `21c6e635d` (`page_buffer.c` unchanged to `953e83256`)
with D1–D11 applied; TLAPS 요청 없음; trace-exempt (design spec). 14 pass cfgs, 11 mutants rejected, 13
witnesses reached (12 AtomicLatch + `PageLatch.witness-shared`), IndInv inductive (`PageLatch.inductive-indinv`).

| cfg | expect | got | states (generated/distinct) | depth | time |
|---|---|---|---|---|---|
| `AtomicLatch.all-2f` | pass | pass | 94926/36758 | 40 | 7s |
| `AtomicLatch.all-3t` | pass | pass | 161997/72205 | 42 | 9s |
| `AtomicLatch` | pass | pass | 9583162/3751488 | 60 | 422s |
| `AtomicLatch.cond-read-3t` | pass | pass | 148570/63774 | 42 | 9s |
| `AtomicLatch.endless` | pass | pass | 75268/27599 | 59 | 11s |
| `AtomicLatch.ext-flush` | pass | pass | 621806/215200 | 40 | 25s |
| `AtomicLatch.ext-torn` | pass | pass | 627684/324808 | 51 | 33s |
| `AtomicLatch.mutant-block-no-bit` | refinement | refinement | 10907/3879 | 7 | 5s |
| `AtomicLatch.mutant-code-h1` | violation SamePage | violation SamePage | 929184/342757 | 20 | 42s |
| `AtomicLatch.mutant-code-h4` | violation NoSpin | violation NoSpin | 25826/10624 | 18 | 6s |
| `AtomicLatch.mutant-flerr-no-wake` | deadlock | deadlock | 469353/167499 | 30 | 10s |
| `AtomicLatch.mutant-flush-needs-idle` | liveness | liveness | 2501/1155 | 12 | 5s |
| `AtomicLatch.mutant-lf-any-mode` | refinement | refinement | 18771/6530 | 8 | 6s |
| `AtomicLatch.mutant-lf-fix-ignores-bit` | violation NoDoubleLock | violation NoDoubleLock | 936938/400993 | 26 | 12s |
| `AtomicLatch.mutant-lf-no-vpid-check` | violation SamePage | violation SamePage | 781668/289639 | 19 | 25s |
| `AtomicLatch.mutant-lf-unfix-last` | violation FcntExact | violation FcntExact | 10419/3646 | 7 | 4s |
| `AtomicLatch.mutant-opta-convoy` | violation NoFlushConvoy | violation NoFlushConvoy | 812828/273372 | 22 | 10s |
| `AtomicLatch.mutant-unlatch-no-wakeup` | violation NoStrandedWaiter | violation NoStrandedWaiter | 110114/39016 | 12 | 7s |
| `AtomicLatch.pr-3t-2f` | pass | pass | 18676535/5894196 | 59 | 820s |
| `AtomicLatch.pr-all` | pass | pass | 7195016/2741230 | 61 | 241s |
| `AtomicLatch.pr-ext-flush` | pass | pass | 470648/163234 | 41 | 19s |
| `AtomicLatch.pr-ext-torn` | pass | pass | 208884/103468 | 51 | 10s |
| `AtomicLatch.promote-3t` | pass | pass | 1347770/574127 | 68 | 52s |
| `AtomicLatch.refix-3t` | pass | pass | 18174019/7469024 | 76 | 803s |
| `AtomicLatch.scale-3t-2f` | pass | pass | 6786960/2153508 | 57 | 354s |
| `AtomicLatch.witness-flush-intr` | violation NotFlushIntrRemoved | violation NotFlushIntrRemoved | 4675/2164 | 9 | 1s |
| `AtomicLatch.witness-flush-wait-at-idle` | violation NotFlushWaitAtIdle | violation NotFlushWaitAtIdle | 1693/874 | 10 | 1s |
| `AtomicLatch.witness-idle-grant-past-flush-waiter` | violation NotIdleGrantPastFlushWaiter | violation NotIdleGrantPastFlushWaiter | 392/235 | 8 | 1s |
| `AtomicLatch.witness-io-error` | violation NotIoErrDone | violation NotIoErrDone | 1550/857 | 8 | 1s |
| `AtomicLatch.witness-join-past-flush-waiter` | violation NotJoinPastFlushWaiter | violation NotJoinPastFlushWaiter | 482047/166149 | 21 | 8s |
| `AtomicLatch.witness-lock-free-shared` | violation NotLockFreeShared | violation NotLockFreeShared | 28958/9982 | 9 | 3s |
| `AtomicLatch.witness-promoted-by-wait` | violation NotPromotedByWait | violation NotPromotedByWait | 735712/268062 | 19 | 9s |
| `AtomicLatch.witness-recheck-miss` | violation NotRecheckMiss | violation NotRecheckMiss | 733786/267536 | 19 | 9s |
| `AtomicLatch.witness-reclaim-after-inval` | violation NotReclaimedAfterInval | violation NotReclaimedAfterInval | 1305/466 | 5 | 2s |
| `AtomicLatch.witness-timed-out-gave-up` | violation NotTimedOutGaveUp | violation NotTimedOutGaveUp | 30711/10686 | 9 | 3s |
| `AtomicLatch.witness-wait-on-handoff` | violation NotWaitOnHandoff | violation NotWaitOnHandoff | 81158/31152 | 17 | 3s |
| `AtomicLatch.witness-woken-from-queue` | violation NotWokenFromQueue | violation NotWokenFromQueue | 155807/55739 | 13 | 4s |
| `PageLatch` | pass | pass | 1254/188 | 6 | 1s |
| `PageLatch.inductive-indinv` | pass | pass | 1568/204 | 1 | 1s |
| `PageLatch.witness-shared` | violation NotShared | violation NotShared | 97/60 | 4 | 1s |

Spec sha256 (from `summary.txt`):

```
45b8667e01490381b92d8906698cfa8c5aa61630c0059533400139b5d7c6000b  AtomicLatch.tla
3a0af78a07e982e2a74e02a0bcccb31ea3c11f2467b41bdd1312fb0be248ed0e  PageLatch.tla
a2c0c2bed0ca0365e0c0b7e87b9cf0397b964fb38050a2e91ae441b26bf38a7f  AtomicLatch.all-2f.cfg
b5b0fbdda1a759d65eec3be945811f294bcd094481247a5a1a6bfd6a80b14f70  AtomicLatch.all-3t.cfg
7398b2ea79d54e097e7ba8ea1f1efb0c1d3acd5982d65d479a5d032c4b9a6f59  AtomicLatch.cfg
489c44936ad37d3c83ff6d6d3ba7fd90ce38e615191cc69acaaf74779eb48de8  AtomicLatch.cond-read-3t.cfg
0f9ec917cffaedf336238436acaa4efa09bc7e9a0d90892dec7815b593e0402e  AtomicLatch.endless.cfg
87d647846123ecc29d65a5c7a6ae360d14a3e6c146685a6cd2b8108b705e3b72  AtomicLatch.ext-flush.cfg
4b78cfee7bfbd271a0994cf8ef2ac7ab449b9f9e858b9a4971a965b7eaafd0c8  AtomicLatch.ext-torn.cfg
859922e441710d87c3f7a976ace2a081f03ae4d0a16ef991a1eaaba768298371  AtomicLatch.mutant-block-no-bit.cfg
6ec35e9b590d20014f2a89203bf9f6fc35979d40eb958e49a2b59846652af5de  AtomicLatch.mutant-code-h1.cfg
83ea9813ba04d7c9af9b113bff67d14d8e7c12b536daa7e0cdb9acab9bc8c702  AtomicLatch.mutant-code-h4.cfg
5e3202cc9e9799b539f48a6e07febb7c36c7cac414d01c1bb5d908c1571a0e1c  AtomicLatch.mutant-flerr-no-wake.cfg
73b5a98f8a595f4b649f1e86c3189915ecf49fbc1b4aaa0b32e05db78ce32d53  AtomicLatch.mutant-flush-needs-idle.cfg
c20933e9d67d16b0e754e87254f292daac1a7c86e92f4238dcef2c2f0294a656  AtomicLatch.mutant-lf-any-mode.cfg
33ba07a53b2893637424e8d688abc338579c9437a6b50abeeaf2ae08f7b8850a  AtomicLatch.mutant-lf-fix-ignores-bit.cfg
fcc358ebe722545e1f7b0a886dc50a1687c376cd8671d6f44d1875600d594457  AtomicLatch.mutant-lf-no-vpid-check.cfg
1c0fa0a114d4b920f6ab4f9fd303dda97599d962ebb1f7f738aa0190a3a9c4e0  AtomicLatch.mutant-lf-unfix-last.cfg
a604e9c6d8e65ad9f654fc9de0c933ba4025df4a62d80d67fbc4262ef5ddf489  AtomicLatch.mutant-opta-convoy.cfg
e1d89ca393176e7f4b1e9139fcc05a4688cd0a996ef6e74b02f3a2c2e08d33b2  AtomicLatch.mutant-unlatch-no-wakeup.cfg
c97b1b5ea02a027d04cf5f381438a902f16ac9db5bdad7dcecbafb423e15489c  AtomicLatch.pr-3t-2f.cfg
7afdb71266b5a12c53497049c5dc8b3e9882c17c48caebbb06d0ccc1d0be96a5  AtomicLatch.pr-all.cfg
2d5e2a9ae5437a5d09f86899826f362c67fdf9934416382db07938da5c9516dc  AtomicLatch.pr-ext-flush.cfg
f1d3d3c3a193d6e027b5423a3dd0d7b52d17372bd9aed922f54bb9507bcaae69  AtomicLatch.pr-ext-torn.cfg
84ce2e0a409ea9d6ebc4a2440e67b70cbb3f810b8b45d66642b3fb940900845e  AtomicLatch.promote-3t.cfg
63eedf0c54f44574874a28c54a25aec3b85bd1c629144b9e59bfd309bb22ac34  AtomicLatch.refix-3t.cfg
7bf33192d8c6e2b5b235282e4d1e6eba70aa8a58a427483a22652b046de0c6f2  AtomicLatch.scale-3t-2f.cfg
9a389421620f0451f0bd0537f23a7e0221c6f20235360a3a0bccc9f388af6e43  AtomicLatch.witness-flush-intr.cfg
6442563dce5881bf70f471f356dd4b672f038b37df812026eed4a083e9ce446b  AtomicLatch.witness-flush-wait-at-idle.cfg
3768bab8a57cec06be05e3e8ec3a144f29ab0242b2914f0e9671d62dc03b36b6  AtomicLatch.witness-idle-grant-past-flush-waiter.cfg
c58b428457246585145d00c96634ef6e7d5c980208eccb39ea6f658cebe7c4e8  AtomicLatch.witness-io-error.cfg
27b5262aaa43f04e4650671d9ad4a31c8e1be7375659189ac64bb1867d800450  AtomicLatch.witness-join-past-flush-waiter.cfg
41b968f007b091d4f29ed74d966517a16e961912f6609b5da3b75259bf9ad5b7  AtomicLatch.witness-lock-free-shared.cfg
c6ba9edce781b6c610df098b08645b5c1b079dd81009fc9f10856bc103dc0fed  AtomicLatch.witness-promoted-by-wait.cfg
514e9477de561fd639b2f3b29a81698c98f4b0b488127a8a0e66007c0b815a81  AtomicLatch.witness-recheck-miss.cfg
94bac6a7608ca583093f8ff1bec99fbd7a2b2189c357a8d9d6cfd32dea37c187  AtomicLatch.witness-reclaim-after-inval.cfg
32fb1fa2dd8dc540d36449dfaa4872891c77adacab90299faf34032120f29a16  AtomicLatch.witness-timed-out-gave-up.cfg
a88a01fd7598c3d34533f15474b07926c096afbafa8e3aa653655c61dd595402  AtomicLatch.witness-wait-on-handoff.cfg
8c37a45528f84a229846f256b74ba4965631377b0f4bbd353bec0c16d694642c  AtomicLatch.witness-woken-from-queue.cfg
1be1db598f7ba0dac32f05b949a2affc35ef8f69e1a07c0eac35892c9b540b5c  PageLatch.cfg
75797c0276498272e7b0ebe48d1b1e78405cbe8989711b95346e507d01b2c79e  PageLatch.inductive-indinv.cfg
f7e358ad7391527abd319eaa20ee1a7cc535b88d0c585681a6e2579664131a8d  PageLatch.witness-shared.cfg
```
