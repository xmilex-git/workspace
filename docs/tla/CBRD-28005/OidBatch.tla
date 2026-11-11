--------------------------- MODULE OidBatch ---------------------------
(***************************************************************************)
(* The OID batch fetch of an index scan: the scanning thread accumulates   *)
(* OIDs from the index in key order, issues the reads of their heap pages  *)
(* while earlier reads are in flight, and processes each page's pending    *)
(* OIDs as one chunk.  Order = "free": whichever page is ready first.      *)
(* Order = "key": the page of the smallest pending key only.               *)
(*                                                                         *)
(* OIDs are 1..NOids in key order; odd OIDs live on page p1, even ones on  *)
(* p2, so a page is needed again by a later OID.  Buffer, ring and reaping *)
(* follow AsyncRead and ReadStream.                                        *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS Scans,      \* index scans (threads), each with its own ring, over the same key range
          NOids,      \* OIDs the key range yields
          W,          \* window depth (heap pages with pending OIDs)
          B,          \* OID batch capacity (pending OIDs)
          NFrames,    \* frames of the page buffer
          Order,      \* "free" | "key"
          Mutant,     \* "none" or the name of a wrong variant
          MaxErrors,  \* I/O errors the device may return
          MaxVac      \* rows vacuum may remove (0 or 1)

\* apalache-type: Scans Set(Str)
\* apalache-type: NOids Int
\* apalache-type: W Int
\* apalache-type: B Int
\* apalache-type: NFrames Int
\* apalache-type: Order Str
\* apalache-type: Mutant Str
\* apalache-type: MaxErrors Int
\* apalache-type: MaxVac Int
\* apalache-type: bcb Str -> Str
\* apalache-type: owner Str -> Str
\* apalache-type: inflight Str -> Set(Str)
\* apalache-type: cq Str -> Set(Str)
\* apalache-type: res Str -> Str
\* apalache-type: nextk Str -> Int
\* apalache-type: pend Str -> Set(Int)
\* apalache-type: win Str -> Set(Str)
\* apalache-type: gone Str -> Set(Int)
\* apalache-type: got Str -> Set(Int)
\* apalache-type: fix Str -> Str
\* apalache-type: need Str -> Str
\* apalache-type: pc Str -> Str
\* apalache-type: wantp Str -> Str
\* apalache-type: early Str -> Bool
\* apalache-type: errs Int
\* apalache-type: vac Set(Int)
\* apalache-type: uaf Bool
\* apalache-type: dup Bool
\* apalache-type: ordViol Bool

\* Apalache: sizes fixed, the error budget open.
CInit ==
  /\ Scans = {"s1", "s2"}
  /\ NOids = 3
  /\ W = 2
  /\ B = 2
  /\ NFrames = 1
  /\ Order = "free"
  /\ Mutant = "none"
  /\ MaxErrors \in Nat
  /\ MaxVac = 1

\* The same with the key-order mode.
CInitKey ==
  /\ Scans = {"s1", "s2"}
  /\ NOids = 3
  /\ W = 2
  /\ B = 2
  /\ NFrames = 1
  /\ Order = "key"
  /\ Mutant = "none"
  /\ MaxErrors \in Nat
  /\ MaxVac = 1

NoScan == "none"
NoPage == "none_page"
Pages == {"p1", "p2"}
Oids == {o \in 1..4 : o <= NOids}
PageOf(o) == IF o % 2 = 0 THEN "p2" ELSE "p1"
\* The row vacuum may remove: no snapshot sees it (its index entry is still there).
VacOid == 2
Vis == Oids \ {VacOid}

VARIABLES bcb,        \* [Pages -> {"absent","io","valid"}]
          owner,      \* [Pages -> Scans \cup {NoScan}]
          inflight,   \* [Scans -> SUBSET Pages]
          cq,         \* [Scans -> SUBSET Pages]
          res,        \* [Pages -> {"ok","err"}]
          nextk,      \* [Scans -> 1..NOids+1]: the next key the index scan will read
          pend,       \* [Scans -> SUBSET Oids]: accumulated, not yet processed
          win,        \* [Scans -> SUBSET Pages]: heap pages of the pending OIDs
          gone,       \* [Scans -> SUBSET Oids]: processed (row returned, or skipped)
          got,        \* [Scans -> SUBSET Oids]: rows returned
          fix,        \* [Scans -> Pages \cup {NoPage}]
          need,       \* [Scans -> Pages \cup {NoPage}]: page a pgbuf_fix is reading (frame reserved)
          pc,         \* [Scans -> {"run","sleepPage","sleepFrame","drain","done"}]
          wantp,      \* [Scans -> Pages \cup {NoPage}]
          early,      \* [Scans -> BOOLEAN]
          errs,       \* device errors so far
          vac,        \* SUBSET Oids: rows vacuum removed
          uaf,        \* ghost: a frame under I/O, fixed or reserved was taken as a victim
          dup,        \* ghost: an OID was processed twice
          ordViol     \* ghost: in key order, an OID was processed after a larger one

vars == <<bcb, owner, inflight, cq, res, nextk, pend, win, gone, got, fix, need, pc, wantp,
          early, errs, vac, uaf, dup, ordViol>>

TypeOK ==
  /\ bcb \in [Pages -> {"absent","io","valid"}]
  /\ owner \in [Pages -> Scans \cup {NoScan}]
  /\ inflight \in [Scans -> SUBSET Pages]
  /\ cq \in [Scans -> SUBSET Pages]
  /\ res \in [Pages -> {"ok","err"}]
  /\ nextk \in [Scans -> 1..5]
  /\ pend \in [Scans -> SUBSET Oids]
  /\ win \in [Scans -> SUBSET Pages]
  /\ gone \in [Scans -> SUBSET Oids]
  /\ got \in [Scans -> SUBSET Oids]
  /\ fix \in [Scans -> Pages \cup {NoPage}]
  /\ need \in [Scans -> Pages \cup {NoPage}]
  /\ pc \in [Scans -> {"run","sleepPage","sleepFrame","drain","done"}]
  /\ wantp \in [Scans -> Pages \cup {NoPage}]
  /\ early \in [Scans -> BOOLEAN]
  /\ errs \in Int /\ errs >= 0 /\ errs <= MaxErrors
  /\ vac \in SUBSET Oids
  /\ uaf \in BOOLEAN /\ dup \in BOOLEAN /\ ordViol \in BOOLEAN

Init ==
  /\ bcb = [p \in Pages |-> "absent"]
  /\ owner = [p \in Pages |-> NoScan]
  /\ inflight = [s \in Scans |-> {}]
  /\ cq = [s \in Scans |-> {}]
  /\ res = [p \in Pages |-> "ok"]
  /\ nextk = [s \in Scans |-> 1]
  /\ pend = [s \in Scans |-> {}]
  /\ win = [s \in Scans |-> {}]
  /\ gone = [s \in Scans |-> {}]
  /\ got = [s \in Scans |-> {}]
  /\ fix = [s \in Scans |-> NoPage]
  /\ need = [s \in Scans |-> NoPage]
  /\ pc = [s \in Scans |-> "run"]
  /\ wantp = [s \in Scans |-> NoPage]
  /\ early = [s \in Scans |-> FALSE]
  /\ errs = 0
  /\ vac = {}
  /\ uaf = FALSE /\ dup = FALSE /\ ordViol = FALSE

(***************************************************************************)
(* The frame pool (as in ReadStream, without the LRU bottom)               *)
(***************************************************************************)
Used == Cardinality({p \in Pages : bcb[p] # "absent"})
Fixed(p) == \E s \in Scans : fix[s] = p
Reserved(p) == \E s \in Scans : need[s] = p
Eligible == {v \in Pages : bcb[v] = "valid" /\ ~Fixed(v) /\ ~Reserved(v)}
FrameAvail == Used < NFrames \/ Eligible # {}

TakeFrame(s, p) ==
  \/ /\ Used < NFrames
     /\ bcb' = [bcb EXCEPT ![p] = "io"]
     /\ owner' = [owner EXCEPT ![p] = s]
  \/ /\ Used >= NFrames
     /\ \E v \in Eligible :
          /\ bcb' = [bcb EXCEPT ![p] = "io", ![v] = "absent"]
          /\ owner' = [owner EXCEPT ![p] = s]

(***************************************************************************)
(* What the scan may process now                                           *)
(***************************************************************************)
\* The smallest pending key (0 when nothing is pending).
MinPend(s) == IF pend[s] = {} THEN 0 ELSE CHOOSE o \in pend[s] : \A q \in pend[s] : o <= q
KeyOrdered == Order = "key" /\ Mutant # "completion_order_in_key_mode"
\* Pages whose processing the scan is waiting for: every window page, or only the page of
\* the smallest pending key.
Wanted(s) == IF KeyOrdered
               THEN {p \in win[s] : pend[s] # {} /\ p = PageOf(MinPend(s))}
               ELSE win[s]
\* The OIDs one fix of page p processes: all pending OIDs of the page, or the smallest key only.
Chunk(s, p) == IF KeyOrdered
                 THEN {o \in pend[s] : o = MinPend(s) /\ PageOf(o) = p}
                 ELSE {o \in pend[s] : PageOf(o) = p}

(***************************************************************************)
(* Scan actions                                                            *)
(***************************************************************************)
CanAccumulate(s) ==
  /\ pc[s] = "run"
  /\ need[s] = NoPage
  /\ nextk[s] <= NOids
  /\ Cardinality(pend[s]) < B
  /\ PageOf(nextk[s]) \in win[s] \/ Cardinality(win[s]) < W

\* Accumulate the next OID from the index and issue its heap page's read at once.
AccumulateRead(s) ==
  /\ CanAccumulate(s)
  /\ PageOf(nextk[s]) \notin win[s]
  /\ bcb[PageOf(nextk[s])] = "absent"
  /\ FrameAvail
  /\ TakeFrame(s, PageOf(nextk[s]))
  /\ inflight' = [inflight EXCEPT ![s] = @ \cup {PageOf(nextk[s])}]
  /\ pend' = [pend EXCEPT ![s] = @ \cup {nextk[s]}]
  /\ win' = [win EXCEPT ![s] = @ \cup {PageOf(nextk[s])}]
  /\ nextk' = [nextk EXCEPT ![s] = @ + 1]
  /\ UNCHANGED <<cq, res, gone, got, fix, need, pc, wantp, early, errs, vac, uaf, dup, ordViol>>

\* Accumulate without a read: the page is already in the window, in the buffer, under
\* another thread's read, or no frame is free at once (D7a).  The mutant leaves a page that
\* is already valid out of the window ("nothing to read").
AccumulateNote(s) ==
  /\ CanAccumulate(s)
  /\ ~(PageOf(nextk[s]) \notin win[s] /\ bcb[PageOf(nextk[s])] = "absent" /\ FrameAvail)
  /\ pend' = [pend EXCEPT ![s] = @ \cup {nextk[s]}]
  /\ win' = [win EXCEPT ![s] =
               IF Mutant = "skip_valid_page" /\ bcb[PageOf(nextk[s])] = "valid" /\ PageOf(nextk[s]) \notin win[s]
                 THEN @ ELSE @ \cup {PageOf(nextk[s])}]
  /\ nextk' = [nextk EXCEPT ![s] = @ + 1]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, gone, got, fix, need, pc, wantp, early, errs, vac, uaf, dup, ordViol>>

\* A wanted page is not in the buffer: pgbuf_fix reads it through the ring; the frame is
\* reserved for this fixer.
ReadNow(s) ==
  /\ pc[s] = "run"
  /\ fix[s] = NoPage
  /\ need[s] = NoPage
  /\ \E p \in Wanted(s) :
       /\ bcb[p] = "absent"
       /\ FrameAvail
       /\ TakeFrame(s, p)
       /\ inflight' = [inflight EXCEPT ![s] = @ \cup {p}]
       /\ need' = [need EXCEPT ![s] = p]
  /\ UNCHANGED <<cq, res, nextk, pend, win, gone, got, fix, pc, wantp, early, errs, vac, uaf, dup, ordViol>>

FixNeed(s) ==
  /\ pc[s] = "run"
  /\ need[s] # NoPage
  /\ bcb[need[s]] = "valid"
  /\ fix' = [fix EXCEPT ![s] = need[s]]
  /\ need' = [need EXCEPT ![s] = NoPage]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, pend, win, gone, got, pc, wantp, early, errs, vac, uaf, dup, ordViol>>

ReadFailed(s) ==
  /\ pc[s] = "run"
  /\ need[s] # NoPage
  /\ bcb[need[s]] = "absent"
  /\ need' = [need EXCEPT ![s] = NoPage]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, pend, win, gone, got, fix, pc, wantp, early, errs, vac, uaf, dup, ordViol>>

\* Mutant: a window page that left the buffer is dropped with its pending OIDs.
DropAbsent(s) ==
  /\ Mutant = "drop_on_victim"
  /\ pc[s] = "run"
  /\ fix[s] = NoPage /\ need[s] = NoPage
  /\ \E p \in win[s] :
       /\ bcb[p] = "absent"
       /\ win' = [win EXCEPT ![s] = @ \ {p}]
       /\ gone' = [gone EXCEPT ![s] = @ \cup {o \in pend[s] : PageOf(o) = p}]
       /\ pend' = [pend EXCEPT ![s] = {o \in @ : PageOf(o) # p}]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, got, fix, need, pc, wantp, early, errs, vac, uaf, dup, ordViol>>

\* No frame for a wanted page: sleep until one is free, with an empty ring only (D7b).
WaitFrame(s) ==
  /\ pc[s] = "run"
  /\ need[s] = NoPage
  /\ fix[s] = NoPage
  /\ \E p \in Wanted(s) : bcb[p] = "absent"
  /\ ~FrameAvail
  /\ inflight[s] \cup cq[s] = {}
  /\ pc' = [pc EXCEPT ![s] = "sleepFrame"]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, pend, win, gone, got, fix, need, wantp, early, errs, vac, uaf, dup, ordViol>>

WakeFrame(s) ==
  /\ pc[s] = "sleepFrame"
  /\ FrameAvail
  /\ pc' = [pc EXCEPT ![s] = "run"]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, pend, win, gone, got, fix, need, wantp, early, errs, vac, uaf, dup, ordViol>>

\* No wanted page is ready and one is under another thread's read: sleep on it.
SleepOnPage(s) ==
  /\ pc[s] = "run"
  /\ need[s] = NoPage
  /\ fix[s] = NoPage
  /\ \A q \in Wanted(s) : bcb[q] # "valid"
  /\ \E p \in Wanted(s) :
       /\ bcb[p] = "io"
       /\ owner[p] # s
       /\ wantp' = [wantp EXCEPT ![s] = p]
  /\ pc' = [pc EXCEPT ![s] = "sleepPage"]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, pend, win, gone, got, fix, need, early, errs, vac, uaf, dup, ordViol>>

WakePage(s) ==
  /\ pc[s] = "sleepPage"
  /\ bcb[wantp[s]] # "io"
  /\ pc' = [pc EXCEPT ![s] = "run"]
  /\ wantp' = [wantp EXCEPT ![s] = NoPage]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, pend, win, gone, got, fix, need, early, errs, vac, uaf, dup, ordViol>>

\* A completion only changes the BCB (D17).
ReapOne(o, p) ==
  /\ p \in cq[o]
  /\ cq' = [cq EXCEPT ![o] = @ \ {p}]
  /\ bcb' = [bcb EXCEPT ![p] = IF res[p] = "ok" THEN "valid" ELSE "absent"]
  /\ owner' = [owner EXCEPT ![p] = NoScan]

ReapOwn(s) ==
  /\ pc[s] \in {"run", "drain"}
  /\ \E p \in cq[s] : ReapOne(s, p)
  /\ UNCHANGED <<inflight, res, nextk, pend, win, gone, got, fix, need, pc, wantp, early, errs, vac, uaf, dup, ordViol>>

ReapForWaiter(s) ==
  /\ pc[s] = "sleepPage"
  /\ bcb[wantp[s]] = "io"
  /\ owner[wantp[s]] \in Scans
  /\ \E p \in cq[owner[wantp[s]]] : ReapOne(owner[wantp[s]], p)
  /\ UNCHANGED <<inflight, res, nextk, pend, win, gone, got, fix, need, pc, wantp, early, errs, vac, uaf, dup, ordViol>>

\* Fix a wanted page that is ready.
Fix(s) ==
  /\ pc[s] = "run"
  /\ need[s] = NoPage
  /\ fix[s] = NoPage
  /\ \E p \in Wanted(s) :
       /\ bcb[p] = "valid"
       /\ fix' = [fix EXCEPT ![s] = p]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, pend, win, gone, got, need, pc, wantp, early, errs, vac, uaf, dup, ordViol>>

\* Process the chunk of the fixed page (rows returned; a vacuumed row skipped) and unfix.
\* The page leaves the window when no pending OID is left on it.
Process(s) ==
  /\ pc[s] = "run"
  /\ fix[s] # NoPage
  /\ LET ch == Chunk(s, fix[s])
         left == IF Mutant = "double_process" THEN pend[s] ELSE pend[s] \ ch
     IN /\ dup' = (dup \/ ch \cap gone[s] # {})
        /\ ordViol' = (ordViol \/ (Order = "key" /\ \E o \in ch : \E g \in gone[s] : o < g))
        /\ gone' = [gone EXCEPT ![s] = @ \cup ch]
        /\ got' = [got EXCEPT ![s] = @ \cup (ch \ vac)]
        /\ pend' = [pend EXCEPT ![s] = left]
        /\ win' = [win EXCEPT ![s] = {p \in @ : \E o \in left : PageOf(o) = p}]
  /\ fix' = [fix EXCEPT ![s] = NoPage]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, need, pc, wantp, early, errs, vac, uaf>>

EarlyEnd(s) ==
  /\ pc[s] \in {"run", "sleepPage", "sleepFrame"}
  /\ ~early[s]
  /\ early' = [early EXCEPT ![s] = TRUE]
  /\ pend' = [pend EXCEPT ![s] = {}]
  /\ win' = [win EXCEPT ![s] = {}]
  /\ fix' = [fix EXCEPT ![s] = IF Mutant = "leak_fix" THEN @ ELSE NoPage]
  /\ need' = [need EXCEPT ![s] = NoPage]
  /\ wantp' = [wantp EXCEPT ![s] = NoPage]
  /\ pc' = [pc EXCEPT ![s] = "drain"]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, gone, got, errs, vac, uaf, dup, ordViol>>

End(s) ==
  /\ pc[s] = "run"
  /\ need[s] = NoPage
  /\ nextk[s] > NOids /\ pend[s] = {} /\ fix[s] = NoPage
  /\ pc' = [pc EXCEPT ![s] = "drain"]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, pend, win, gone, got, fix, need, wantp, early, errs, vac, uaf, dup, ordViol>>

Finish(s) ==
  /\ pc[s] = "drain"
  /\ inflight[s] \cup cq[s] = {} \/ Mutant = "no_drain"
  /\ pc' = [pc EXCEPT ![s] = "done"]
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, pend, win, gone, got, fix, need, wantp, early, errs, vac, uaf, dup, ordViol>>

(***************************************************************************)
(* Environment                                                             *)
(***************************************************************************)
DeviceComplete ==
  \E s \in Scans : \E p \in inflight[s] :
    /\ inflight' = [inflight EXCEPT ![s] = @ \ {p}]
    /\ cq' = [cq EXCEPT ![s] = @ \cup {p}]
    /\ \/ /\ res' = [res EXCEPT ![p] = "ok"]
          /\ UNCHANGED errs
       \/ /\ errs < MaxErrors
          /\ res' = [res EXCEPT ![p] = "err"]
          /\ errs' = errs + 1
    /\ UNCHANGED <<bcb, owner, nextk, pend, win, gone, got, fix, need, pc, wantp, early, vac, uaf, dup, ordViol>>

\* Vacuum removes the row no snapshot sees (write latch on its page: nobody has it fixed).
Vacuum ==
  /\ Cardinality(vac) < MaxVac
  /\ VacOid \in Oids /\ VacOid \notin vac
  /\ ~Fixed(PageOf(VacOid))
  /\ vac' = vac \cup {VacOid}
  /\ UNCHANGED <<bcb, owner, inflight, cq, res, nextk, pend, win, gone, got, fix, need, pc, wantp, early, errs, uaf, dup, ordViol>>

Terminated ==
  /\ \A s \in Scans : pc[s] = "done"
  /\ \A p \in Pages : bcb[p] # "io"
  /\ UNCHANGED vars

ScanStep(s) ==
  \/ AccumulateRead(s) \/ AccumulateNote(s) \/ ReadNow(s) \/ FixNeed(s) \/ ReadFailed(s) \/ DropAbsent(s)
  \/ WaitFrame(s) \/ WakeFrame(s) \/ SleepOnPage(s) \/ WakePage(s)
  \/ ReapOwn(s) \/ ReapForWaiter(s) \/ Fix(s) \/ Process(s) \/ End(s) \/ Finish(s)

Next ==
  \/ \E s \in Scans : ScanStep(s) \/ EarlyEnd(s)
  \/ DeviceComplete \/ Vacuum
  \/ Terminated

Fairness ==
  /\ \A s \in Scans : WF_vars(ScanStep(s))
  /\ WF_vars(DeviceComplete)

Spec == Init /\ [][Next]_vars /\ Fairness

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)
\* C6: no OID twice; a scan that ran to the end returned every visible row.
AtMostOnce == ~dup
Complete == \A s \in Scans : (pc[s] = "done" /\ ~early[s]) => Vis \subseteq got[s]

\* C7: in key order no OID is processed after a larger one.
KeyOrder == ~ordViol

\* C4: a scan that ended holds no fix.
NoFixAfterEnd == \A s \in Scans : pc[s] \in {"drain", "done"} => fix[s] = NoPage

\* C2 / C4 (liveness)
AllComplete == <>[](/\ \A s \in Scans : pc[s] = "done"
                    /\ \A p \in Pages : bcb[p] # "io")

\* Witnesses
NotRevisited == ~(\E s \in Scans : fix[s] # NoPage /\ \E o \in gone[s] : PageOf(o) = fix[s])
NotVacSkipped == ~(\E s \in Scans : gone[s] \ got[s] # {})
NotAccumulatedInFlight == ~(\E s \in Scans : inflight[s] # {} /\ Cardinality(pend[s]) >= 2)
NotHeldBackByOrder ==
  ~(\E s \in Scans : /\ pc[s] = "run" /\ pend[s] # {}
                     /\ bcb[PageOf(MinPend(s))] # "valid"
                     /\ \E p \in win[s] : p # PageOf(MinPend(s)) /\ bcb[p] = "valid")
NotFullRun == ~(\E s \in Scans : pc[s] = "done" /\ ~early[s])

(***************************************************************************)
(* Inductive invariant                                                     *)
(***************************************************************************)
RingPartition == \A s \in Scans : inflight[s] \cap cq[s] = {}
IoHasOwner == \A p \in Pages : (bcb[p] = "io") <=> (owner[p] # NoScan)
OwnerRingHoldsIo ==
  \A p \in Pages : owner[p] # NoScan => p \in inflight[owner[p]] \cup cq[owner[p]]
RingsHoldOnlyOwned == \A s \in Scans : \A p \in inflight[s] \cup cq[s] : owner[p] = s
FramePool == Used <= NFrames
\* The window is exactly the pages of the pending OIDs.
WinMatchesPend == \A s \in Scans : win[s] = {p \in Pages : \E o \in pend[s] : PageOf(o) = p}
KeyShape ==
  \A s \in Scans : /\ nextk[s] >= 1 /\ nextk[s] <= NOids + 1
                   /\ \A o \in pend[s] \cup gone[s] : o < nextk[s]
                   /\ pend[s] \cap gone[s] = {}
                   /\ got[s] \subseteq gone[s]
                   /\ Cardinality(pend[s]) <= B
Coverage ==
  \A s \in Scans : ~early[s] => \A o \in Oids : o < nextk[s] => o \in pend[s] \cup gone[s]
GotVisible == \A s \in Scans : gone[s] \cap Vis \subseteq got[s]
VacShape == vac \subseteq {VacOid}
\* In key order everything processed is smaller than everything pending.
OrderShape ==
  Order = "key" => \A s \in Scans : \A g \in gone[s] : \A o \in pend[s] : g < o
FixShape ==
  \A s \in Scans : fix[s] # NoPage =>
    /\ pc[s] = "run"
    /\ need[s] = NoPage
    /\ fix[s] \in win[s]
    /\ bcb[fix[s]] = "valid"
NeedShape ==
  \A s \in Scans : need[s] # NoPage =>
    /\ pc[s] = "run"
    /\ fix[s] = NoPage
    /\ need[s] \in win[s]
SleepShape ==
  \A s \in Scans :
    /\ (pc[s] = "sleepPage") <=> (wantp[s] # NoPage)
    /\ pc[s] = "sleepPage" => wantp[s] \in win[s] /\ fix[s] = NoPage /\ need[s] = NoPage
    /\ pc[s] = "sleepFrame" => inflight[s] \cup cq[s] = {} /\ fix[s] = NoPage /\ need[s] = NoPage
EndShape ==
  \A s \in Scans :
    /\ pc[s] \in {"drain", "done"} => pend[s] = {} /\ win[s] = {} /\ need[s] = NoPage
    /\ pc[s] = "done" => inflight[s] \cup cq[s] = {}
    /\ (pc[s] \in {"drain", "done"} /\ ~early[s]) => nextk[s] > NOids

IndInv ==
  /\ TypeOK
  /\ RingPartition
  /\ IoHasOwner
  /\ OwnerRingHoldsIo
  /\ RingsHoldOnlyOwned
  /\ FramePool
  /\ WinMatchesPend
  /\ KeyShape
  /\ Coverage
  /\ GotVisible
  /\ VacShape
  /\ OrderShape
  /\ FixShape
  /\ NeedShape
  /\ SleepShape
  /\ EndShape
  /\ ~uaf
  /\ AtMostOnce
  /\ KeyOrder
  /\ Complete
  /\ NoFixAfterEnd
=============================================================================
