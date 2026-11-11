--------------------------- MODULE AsyncRead ---------------------------
(***************************************************************************)
(* Asynchronous page reads into the page buffer through per-thread         *)
(* io_uring rings: who completes (reaps) an I/O whose issuer is blocked.   *)
(*                                                                         *)
(* A thread may read a page ahead (stage an SQE, maybe defer the submit),  *)
(* then block on a lock X another thread holds; that other thread may      *)
(* need the very page whose I/O sits in the first thread's ring.  The      *)
(* design question is which threads may reap a ring (Reaper) and whether   *)
(* a thread may sleep with staged, unsubmitted SQEs.                       *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS Threads,      \* worker threads, each owning one ring
          Pages,        \* heap pages a scan may read
          Reaper,       \* "owner_only" | "any_waiter" | "daemon"
          Mutant,       \* "none" | "block_with_staged" | "victim_in_io" | "drop_on_interrupt" | "no_drain"
          MaxErrors,    \* I/O errors the device may return in a run
          MaxVictims,   \* page replacements of a valid page in a run
          MaxRounds     \* times a thread starts over (the next read-ahead and fix of a request, or its next request)

\* apalache-type: Threads Set(Str)
\* apalache-type: Pages Set(Str)
\* apalache-type: Reaper Str
\* apalache-type: Mutant Str
\* apalache-type: MaxErrors Int
\* apalache-type: MaxVictims Int
\* apalache-type: MaxRounds Int
\* apalache-type: bcb Str -> Str
\* apalache-type: owner Str -> Str
\* apalache-type: sq Str -> Set(Str)
\* apalache-type: inflight Str -> Set(Str)
\* apalache-type: cq Str -> Set(Str)
\* apalache-type: res Str -> Str
\* apalache-type: pc Str -> Str
\* apalache-type: want Str -> Str
\* apalache-type: lockX Str
\* apalache-type: intr Str -> Bool
\* apalache-type: errs Int
\* apalache-type: victims Int
\* apalache-type: uaf Bool
\* apalache-type: reapedOther Bool
\* apalache-type: ra Set(Str)
\* apalache-type: hit Bool
\* apalache-type: retried Bool
\* apalache-type: round Str -> Int
\* apalache-type: waitRing Str -> Str

\* Apalache: role sets fixed, integer budgets open.
CInit ==
  /\ Threads = {"t1", "t2"}
  /\ Pages = {"p1", "p2"}
  /\ Reaper = "any_waiter"
  /\ Mutant = "none"
  /\ MaxErrors \in Nat
  /\ MaxVictims \in Nat
  /\ MaxRounds \in Nat

NoThread == "none_thread"
NoPage == "none_page"

\* pc values of a thread
\*   start      may read pages ahead (stage SQEs)
\*   pf         inside a read-ahead call with at least one page claimed: claim more, submit now or defer (batch mode)
\*   lock       acquire lock X (a latch or lock the scan needs)
\*   waitX      asleep on X
\*   want       pick the page to fix
\*   fix        fixing want[t]: valid -> got it; absent -> issue it; io -> wait
\*   sleepPage  asleep on a page whose I/O another thread's ring holds
\*   release    release X
\*   finish     end of the query: submit what is staged, drain the own ring
\*   done       back in the thread pool (not running); the pool may hand the thread its next request

VARIABLES bcb,        \* [Pages -> {"absent","io","valid"}]: BCB state of the page's frame
          owner,      \* [Pages -> Threads \cup {NoThread}]: whose ring holds the page's I/O
          sq,         \* [Threads -> SUBSET Pages]: staged SQEs, not yet submitted
          inflight,   \* [Threads -> SUBSET Pages]: submitted, the device has not completed
          cq,         \* [Threads -> SUBSET Pages]: CQEs posted, not reaped
          res,        \* [Pages -> {"ok","err"}]: result of the page's last completed I/O
          pc,         \* [Threads -> pc values]
          want,       \* [Threads -> Pages \cup {NoPage}]
          lockX,      \* Threads \cup {NoThread}
          intr,       \* [Threads -> BOOLEAN]: interrupt already delivered (one per thread)
          errs,       \* device errors returned so far
          victims,    \* page replacements so far
          uaf,        \* ghost: a frame was reused while an I/O into it was in flight
          reapedOther,\* ghost: a thread reaped another thread's ring
          ra,         \* ghost: pages whose frame was claimed by a read ahead (cleared when the page is read again or replaced)
          hit,        \* ghost: a thread fixed a page whose frame a read ahead filled
          retried,    \* ghost: a page whose read failed was issued again and later fixed
          round,      \* [Threads -> Nat]: times the thread started over
          waitRing    \* [Threads -> Threads \cup {NoThread}]: the ring a thread asleep on a page reaps (read when it found the page under I/O)

vars == <<bcb, owner, sq, inflight, cq, res, pc, want, lockX, intr, errs, victims,
          uaf, reapedOther, ra, hit, retried, round, waitRing>>

PCs == {"start","pf","lock","waitX","want","fix","sleepPage","release","finish","done"}

TypeOK ==
  /\ bcb \in [Pages -> {"absent","io","valid"}]
  /\ owner \in [Pages -> Threads \cup {NoThread}]
  /\ sq \in [Threads -> SUBSET Pages]
  /\ inflight \in [Threads -> SUBSET Pages]
  /\ cq \in [Threads -> SUBSET Pages]
  /\ res \in [Pages -> {"ok","err"}]
  /\ pc \in [Threads -> PCs]
  /\ want \in [Threads -> Pages \cup {NoPage}]
  /\ lockX \in Threads \cup {NoThread}
  /\ intr \in [Threads -> BOOLEAN]
  /\ errs \in Int /\ errs >= 0 /\ errs <= MaxErrors
  /\ victims \in Int /\ victims >= 0 /\ victims <= MaxVictims
  /\ uaf \in BOOLEAN /\ reapedOther \in BOOLEAN /\ hit \in BOOLEAN /\ retried \in BOOLEAN
  /\ ra \in SUBSET Pages
  /\ round \in [Threads -> Int]
  /\ \A t \in Threads : round[t] >= 0 /\ round[t] <= MaxRounds
  /\ waitRing \in [Threads -> Threads \cup {NoThread}]

Init ==
  /\ bcb = [p \in Pages |-> "absent"]
  /\ owner = [p \in Pages |-> NoThread]
  /\ sq = [t \in Threads |-> {}]
  /\ inflight = [t \in Threads |-> {}]
  /\ cq = [t \in Threads |-> {}]
  /\ res = [p \in Pages |-> "ok"]
  /\ pc = [t \in Threads |-> "start"]
  /\ want = [t \in Threads |-> NoPage]
  /\ lockX = NoThread
  /\ intr = [t \in Threads |-> FALSE]
  /\ errs = 0 /\ victims = 0
  /\ uaf = FALSE /\ reapedOther = FALSE /\ hit = FALSE /\ retried = FALSE
  /\ ra = {}
  /\ round = [t \in Threads |-> 0]
  /\ waitRing = [t \in Threads |-> NoThread]

\* A thread that is running (not asleep, not in the pool) can enter its own ring.
Running(t) == pc[t] \notin {"waitX","sleepPage","done"}

(***************************************************************************)
(* Thread actions                                                          *)
(***************************************************************************)

\* Read ahead: claim the frame (BCB -> io, owned by t) and stage an SQE.  One call claims any number of pages.
ReadAhead(t) ==
  /\ pc[t] \in {"start", "pf"}
  /\ \E p \in Pages :
       /\ bcb[p] = "absent"
       /\ bcb' = [bcb EXCEPT ![p] = "io"]
       /\ owner' = [owner EXCEPT ![p] = t]
       /\ sq' = [sq EXCEPT ![t] = @ \cup {p}]
       /\ ra' = ra \cup {p}
  /\ pc' = [pc EXCEPT ![t] = "pf"]
  /\ UNCHANGED <<inflight, cq, res, want, lockX, intr, errs, victims, uaf, reapedOther, hit, retried, round, waitRing>>

NoReadAhead(t) ==
  /\ pc[t] = "start"
  /\ pc' = [pc EXCEPT ![t] = "lock"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

\* A read-ahead call submits what it staged before it returns (D7): staged SQEs never
\* outlive the call.  Only the mutant leaves the call with SQEs staged (batch mode).
SubmitNow(t) ==
  /\ pc[t] = "pf"
  /\ inflight' = [inflight EXCEPT ![t] = @ \cup sq[t]]
  /\ sq' = [sq EXCEPT ![t] = {}]
  /\ pc' = [pc EXCEPT ![t] = "lock"]
  /\ UNCHANGED <<bcb, owner, cq, res, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

\* A page claimed in this call is completed inside the call without the ring: its image was in the
\* double write buffer (ok), or its request could not be staged (err: the frame goes back).
InlineComplete(t) ==
  /\ pc[t] = "pf"
  /\ \E p \in sq[t] :
       /\ sq' = [sq EXCEPT ![t] = @ \ {p}]
       /\ owner' = [owner EXCEPT ![p] = NoThread]
       /\ \/ /\ bcb' = [bcb EXCEPT ![p] = "valid"]
             /\ res' = [res EXCEPT ![p] = "ok"]
             /\ UNCHANGED errs
          \/ /\ errs < MaxErrors
             /\ bcb' = [bcb EXCEPT ![p] = "absent"]
             /\ res' = [res EXCEPT ![p] = "err"]
             /\ errs' = errs + 1
  /\ UNCHANGED <<inflight, cq, pc, want, lockX, intr, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

DeferSubmit(t) ==
  /\ Mutant = "block_with_staged"
  /\ pc[t] = "pf"
  /\ pc' = [pc EXCEPT ![t] = "lock"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

\* io_uring_submit of the staged SQEs, from any running state.
Submit(t) ==
  /\ Running(t)
  /\ sq[t] # {}
  /\ inflight' = [inflight EXCEPT ![t] = @ \cup sq[t]]
  /\ sq' = [sq EXCEPT ![t] = {}]
  /\ UNCHANGED <<bcb, owner, cq, res, pc, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

TakeX(t) ==
  /\ pc[t] = "lock"
  /\ lockX = NoThread
  /\ lockX' = t
  /\ pc' = [pc EXCEPT ![t] = "want"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

\* The thread needs no lock another thread may hold.
NoLock(t) ==
  /\ pc[t] = "lock"
  /\ pc' = [pc EXCEPT ![t] = "want"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

\* Going to sleep on X.  The rule: nothing staged may stay behind a sleeping thread.
BlockOnX(t) ==
  /\ pc[t] = "lock"
  /\ lockX \notin {NoThread, t}
  /\ sq[t] = {} \/ Mutant = "block_with_staged"
  /\ pc' = [pc EXCEPT ![t] = "waitX"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

WakeX(t) ==
  /\ pc[t] = "waitX"
  /\ lockX = NoThread
  /\ lockX' = t
  /\ pc' = [pc EXCEPT ![t] = "want"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

PickPage(t) ==
  /\ pc[t] = "want"
  /\ \E p \in Pages : want' = [want EXCEPT ![t] = p]
  /\ pc' = [pc EXCEPT ![t] = "fix"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

\* The thread fixes none of the pages this time.
NoFix(t) ==
  /\ pc[t] = "want"
  /\ pc' = [pc EXCEPT ![t] = "release"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

\* The page is in the buffer: fix it.  hit: a read ahead filled its frame.
FixValid(t) ==
  /\ pc[t] = "fix"
  /\ bcb[want[t]] = "valid"
  /\ pc' = [pc EXCEPT ![t] = "release"]
  /\ want' = [want EXCEPT ![t] = NoPage]
  /\ hit' = (hit \/ want[t] \in ra)
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, lockX, intr, errs, victims, uaf, reapedOther, ra, retried, round, waitRing>>

\* The page is not in the buffer: claim the frame and submit its read at once.
IssueRead(t) ==
  /\ pc[t] = "fix"
  /\ bcb[want[t]] = "absent"
  /\ bcb' = [bcb EXCEPT ![want[t]] = "io"]
  /\ owner' = [owner EXCEPT ![want[t]] = t]
  /\ inflight' = [inflight EXCEPT ![t] = @ \cup sq[t] \cup {want[t]}]
  /\ sq' = [sq EXCEPT ![t] = {}]
  /\ retried' = (retried \/ res[want[t]] = "err")
  /\ ra' = ra \ {want[t]}
  /\ UNCHANGED <<cq, res, pc, want, lockX, intr, errs, victims, uaf, reapedOther, hit, round, waitRing>>

\* The page's I/O is in another thread's ring: sleep on the BCB (the same rule on staged SQEs).
\* The thread remembers the ring it read from the page's entry: that is the ring it reaps.
SleepOnPage(t) ==
  /\ pc[t] = "fix"
  /\ bcb[want[t]] = "io"
  /\ owner[want[t]] # t
  /\ sq[t] = {} \/ Mutant = "block_with_staged"
  /\ pc' = [pc EXCEPT ![t] = "sleepPage"]
  /\ waitRing' = [waitRing EXCEPT ![t] = owner[want[t]]]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round>>

\* Woken, the thread looks the page up again: its I/O completed (valid), failed (absent, to be issued
\* again), or the page is by now under another thread's read.
WakePage(t) ==
  /\ pc[t] = "sleepPage"
  /\ bcb[want[t]] # "io" \/ owner[want[t]] # waitRing[t]
  /\ pc' = [pc EXCEPT ![t] = "fix"]
  /\ waitRing' = [waitRing EXCEPT ![t] = NoThread]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round>>

ReleaseX(t) ==
  /\ pc[t] = "release"
  /\ lockX' = IF lockX = t THEN NoThread ELSE lockX
  /\ pc' = [pc EXCEPT ![t] = "finish"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

\* End of the query.  The own ring is drained unless a daemon reaps it.
Finish(t) ==
  /\ pc[t] = "finish"
  /\ sq[t] = {}
  /\ \/ Reaper = "daemon"
     \/ Mutant = "no_drain"
     \/ inflight[t] \cup cq[t] = {}
  /\ pc' = [pc EXCEPT ![t] = "done"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

\* The request goes on: the thread starts over (next read-ahead, next fix) without leaving for the pool,
\* so without draining.
Loop(t) ==
  /\ pc[t] = "finish"
  /\ round[t] < MaxRounds
  /\ round' = [round EXCEPT ![t] = @ + 1]
  /\ pc' = [pc EXCEPT ![t] = "start"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, waitRing>>

\* The pool hands the thread its next request.
Reuse(t) ==
  /\ pc[t] = "done"
  /\ round[t] < MaxRounds
  /\ round' = [round EXCEPT ![t] = @ + 1]
  /\ pc' = [pc EXCEPT ![t] = "start"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, waitRing>>

\* Query interrupt (or an error raised on the thread) while it waits.
\* The thread leaves its wait, releases X if it holds it, and goes to finish;
\* the mutant leaves for the pool at once, abandoning staged and in-flight I/O.
Interrupt(t) ==
  /\ pc[t] \in {"waitX","sleepPage","fix","lock"}
  /\ ~intr[t]
  /\ intr' = [intr EXCEPT ![t] = TRUE]
  /\ lockX' = IF lockX = t THEN NoThread ELSE lockX
  /\ want' = [want EXCEPT ![t] = NoPage]
  /\ waitRing' = [waitRing EXCEPT ![t] = NoThread]
  /\ pc' = [pc EXCEPT ![t] = IF Mutant = "drop_on_interrupt" THEN "done" ELSE "finish"]
  /\ UNCHANGED <<bcb, owner, sq, inflight, cq, res, errs, victims, uaf, reapedOther, ra, hit, retried, round>>

(***************************************************************************)
(* Reaping: process one CQE of ring o.  The completion runs the BCB        *)
(* callback: ok -> valid, err -> absent (frame back, readers issue again); *)
(* the frame's owner is cleared and sleepers on the BCB are woken.         *)
(***************************************************************************)
ReapOne(o, p) ==
  /\ p \in cq[o]
  /\ cq' = [cq EXCEPT ![o] = @ \ {p}]
  /\ bcb' = [bcb EXCEPT ![p] = IF res[p] = "ok" THEN "valid" ELSE "absent"]
  /\ owner' = [owner EXCEPT ![p] = NoThread]

\* The owner reaps its own ring whenever it runs (waiting on its own page, submitting, finishing).
ReapOwn(t) ==
  /\ Running(t)
  /\ \E p \in cq[t] : ReapOne(t, p)
  /\ UNCHANGED <<sq, inflight, res, pc, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

\* A thread asleep on a page reaps the ring it found the page in (under that ring's completion mutex).
\* It reaps whatever that ring holds, also when its own page has been completed in the meantime.
ReapForWaiter(t) ==
  /\ Reaper = "any_waiter"
  /\ pc[t] = "sleepPage"
  /\ waitRing[t] \in Threads
  /\ \E p \in cq[waitRing[t]] : ReapOne(waitRing[t], p)
  /\ reapedOther' = TRUE
  /\ UNCHANGED <<sq, inflight, res, pc, want, lockX, intr, errs, victims, uaf, ra, hit, retried, round, waitRing>>

(***************************************************************************)
(* Environment                                                             *)
(***************************************************************************)

\* The device completes a submitted read, posting a CQE (ok, or an error within the budget).
DeviceComplete ==
  \E t \in Threads : \E p \in inflight[t] :
    /\ inflight' = [inflight EXCEPT ![t] = @ \ {p}]
    /\ cq' = [cq EXCEPT ![t] = @ \cup {p}]
    /\ \/ /\ res' = [res EXCEPT ![p] = "ok"]
          /\ UNCHANGED errs
       \/ /\ errs < MaxErrors
          /\ res' = [res EXCEPT ![p] = "err"]
          /\ errs' = errs + 1
    /\ UNCHANGED <<bcb, owner, sq, pc, want, lockX, intr, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

\* A completion daemon reaps any ring.
DaemonReap ==
  /\ Reaper = "daemon"
  /\ \E o \in Threads : \E p \in cq[o] : ReapOne(o, p)
  /\ UNCHANGED <<sq, inflight, res, pc, want, lockX, intr, errs, victims, uaf, reapedOther, ra, hit, retried, round, waitRing>>

\* Page replacement takes an unfixed valid frame.  The mutant also takes a frame under I/O:
\* the frame is reused while the device still writes into it.
Victimize ==
  /\ victims < MaxVictims
  /\ \E p \in Pages :
       \/ /\ bcb[p] = "valid"
          /\ bcb' = [bcb EXCEPT ![p] = "absent"]
          /\ ra' = ra \ {p}
          /\ UNCHANGED <<owner, sq, inflight, cq, uaf>>
       \/ /\ Mutant = "victim_in_io"
          /\ bcb[p] = "io"
          /\ bcb' = [bcb EXCEPT ![p] = "absent"]
          /\ uaf' = TRUE
          /\ ra' = ra \ {p}
          /\ UNCHANGED <<owner, sq, inflight, cq>>
  /\ victims' = victims + 1
  /\ UNCHANGED <<res, pc, want, lockX, intr, errs, reapedOther, hit, retried, round, waitRing>>

\* Every thread is back in the pool and nothing is under I/O: stutter instead of a deadlock.
Terminated ==
  /\ \A t \in Threads : pc[t] = "done"
  /\ \A p \in Pages : bcb[p] # "io"
  /\ UNCHANGED vars

ThreadStep(t) ==
  \/ ReadAhead(t) \/ NoReadAhead(t) \/ InlineComplete(t) \/ SubmitNow(t) \/ DeferSubmit(t) \/ Submit(t)
  \/ TakeX(t) \/ NoLock(t) \/ BlockOnX(t) \/ WakeX(t) \/ PickPage(t) \/ NoFix(t) \/ FixValid(t) \/ IssueRead(t)
  \/ SleepOnPage(t) \/ WakePage(t) \/ ReleaseX(t) \/ Finish(t)
  \/ ReapOwn(t) \/ ReapForWaiter(t) \/ Loop(t) \/ Reuse(t)

Next ==
  \/ \E t \in Threads : ThreadStep(t) \/ Interrupt(t)
  \/ DeviceComplete \/ DaemonReap \/ Victimize
  \/ Terminated

Fairness ==
  /\ \A t \in Threads : WF_vars(ThreadStep(t))
  /\ WF_vars(DeviceComplete)
  /\ WF_vars(DaemonReap)

Spec == Init /\ [][Next]_vars /\ Fairness

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)

\* C1: a frame is never reused while an I/O into it is in flight.
NoFrameReuseInIO == ~uaf

\* C2 (liveness): every thread gets back to the pool and no frame stays under I/O.
AllComplete == <>[](/\ \A t \in Threads : pc[t] = "done"
                    /\ \A p \in Pages : bcb[p] # "io")

\* Witnesses
NotReapedOther == ~reapedOther
NotHit == ~hit
NotRetried == ~retried

(***************************************************************************)
(* Inductive invariant                                                     *)
(***************************************************************************)
\* An I/O is in exactly one place: staged, in flight or posted, in its owner's ring,
\* and the frame is under I/O exactly while it is.
RingPartition ==
  \A t \in Threads : sq[t] \cap inflight[t] = {} /\ sq[t] \cap cq[t] = {} /\ inflight[t] \cap cq[t] = {}
IoHasOwner ==
  \A p \in Pages : (bcb[p] = "io") <=> (owner[p] # NoThread)
OwnerRingHoldsIo ==
  \A p \in Pages : owner[p] # NoThread => p \in sq[owner[p]] \cup inflight[owner[p]] \cup cq[owner[p]]
RingsHoldOnlyOwned ==
  \A t \in Threads : \A p \in sq[t] \cup inflight[t] \cup cq[t] : owner[p] = t
WaitersWantAPage ==
  \A t \in Threads : pc[t] \in {"fix","sleepPage"} => want[t] \in Pages
\* D7: SQEs are staged only inside a read-ahead call.
StagedOnlyInsideReadAhead ==
  \A t \in Threads : sq[t] # {} => pc[t] = "pf"
\* A thread remembers a ring exactly while it sleeps on a page, and never its own.
WaitRingShape ==
  \A t \in Threads : IF pc[t] = "sleepPage" THEN waitRing[t] \in Threads \ {t} ELSE waitRing[t] = NoThread
LockHolderShape ==
  lockX # NoThread => pc[lockX] \in {"want","fix","sleepPage","release"}

IndInv ==
  /\ TypeOK
  /\ RingPartition
  /\ IoHasOwner
  /\ OwnerRingHoldsIo
  /\ RingsHoldOnlyOwned
  /\ WaitersWantAPage
  /\ StagedOnlyInsideReadAhead
  /\ LockHolderShape
  /\ WaitRingShape
  /\ NoFrameReuseInIO
=============================================================================
