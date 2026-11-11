--------------------------- MODULE ReadStream ---------------------------
(***************************************************************************)
(* The read stream of a heap full scan: page-list order, a read-ahead      *)
(* window, pages consumed in completion order, a finite frame pool, and    *)
(* consumed pages demoted to the LRU bottom.                               *)
(*                                                                         *)
(* A scan takes pages from its page list into a window; a page not in the  *)
(* buffer gets a read issued at once (staged and submitted in one step,    *)
(* D7).  The scan fixes whichever window page is valid, processes it and   *)
(* unfixes it.  Reaping follows AsyncRead (the owner, or a thread asleep   *)
(* on the page).                                                           *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS Scans,      \* scan threads, each with its own ring, all over the same page list
          Pages,      \* the page list snapshot of the heap
          Vis,        \* pages holding a row the snapshots see (vacuum cannot deallocate them)
          Hot,        \* pages already in the buffer when the scans start
          W,          \* window depth (pages)
          NFrames,    \* frames of the page buffer
          Mutant,     \* "none" or the name of a wrong variant
          MaxErrors,  \* I/O errors the device may return
          MaxDealloc  \* pages vacuum may deallocate

\* apalache-type: Scans Set(Str)
\* apalache-type: Pages Set(Str)
\* apalache-type: Vis Set(Str)
\* apalache-type: Hot Set(Str)
\* apalache-type: W Int
\* apalache-type: NFrames Int
\* apalache-type: Mutant Str
\* apalache-type: MaxErrors Int
\* apalache-type: MaxDealloc Int
\* apalache-type: bcb Str -> Str
\* apalache-type: owner Str -> Str
\* apalache-type: reader Str -> Str
\* apalache-type: bottom Set(Str)
\* apalache-type: inflight Str -> Set(Str)
\* apalache-type: cq Str -> Set(Str)
\* apalache-type: res Str -> Str
\* apalache-type: todo Str -> Set(Str)
\* apalache-type: win Str -> Set(Str)
\* apalache-type: gone Str -> Set(Str)
\* apalache-type: got Str -> Set(Str)
\* apalache-type: fix Str -> Str
\* apalache-type: need Str -> Str
\* apalache-type: pc Str -> Str
\* apalache-type: wantp Str -> Str
\* apalache-type: early Str -> Bool
\* apalache-type: errs Int
\* apalache-type: deallocd Set(Str)
\* apalache-type: uaf Bool
\* apalache-type: dup Bool
\* apalache-type: foreignDemote Bool
\* apalache-type: recycled Bool

\* Apalache: role sets and the two sizes fixed, the fault budgets open.
CInit ==
  /\ Scans = {"s1", "s2"}
  /\ Pages = {"p1", "p2", "p3"}
  /\ Vis = {"p1", "p2"}
  /\ Hot = {"p1"}
  /\ W = 2
  /\ NFrames = 2
  /\ Mutant = "none"
  /\ MaxErrors \in Nat
  /\ MaxDealloc \in Nat

NoScan == "none"
NoPage == "none_page"
HotReader == "hot"

VARIABLES bcb,           \* [Pages -> {"absent","io","valid"}]
          owner,         \* [Pages -> Scans \cup {NoScan}]: whose ring holds the page's read
          reader,        \* [Pages -> Scans \cup {NoScan, HotReader}]: who read the frame's content
          bottom,        \* SUBSET Pages: valid pages at the LRU bottom (first victims)
          inflight,      \* [Scans -> SUBSET Pages]
          cq,            \* [Scans -> SUBSET Pages]
          res,           \* [Pages -> {"ok","err"}]
          todo,          \* [Scans -> SUBSET Pages]: page list not yet taken
          win,           \* [Scans -> SUBSET Pages]: the window (taken, not yet processed)
          gone,          \* [Scans -> SUBSET Pages]: processed (rows returned, or skipped)
          got,           \* [Scans -> SUBSET Pages]: pages whose rows the scan returned
          fix,           \* [Scans -> Pages \cup {NoPage}]: the page the scan holds fixed
          need,          \* [Scans -> Pages \cup {NoPage}]: the page the scan is fixing through a read (pgbuf_fix in progress)
          pc,            \* [Scans -> {"run","sleepPage","sleepFrame","drain","done"}]
          wantp,         \* [Scans -> Pages \cup {NoPage}]: the page a sleeper waits for
          early,         \* [Scans -> BOOLEAN]: the scan ended early (LIMIT, interrupt, error)
          errs,          \* device errors so far
          deallocd,      \* SUBSET Pages: pages vacuum deallocated
          uaf,           \* ghost: a frame under I/O or fixed was taken as a victim
          dup,           \* ghost: a scan processed a page twice
          foreignDemote, \* ghost: a scan demoted a page it did not read
          recycled       \* ghost: a claim took a frame from the LRU bottom

vars == <<bcb, owner, reader, bottom, inflight, cq, res, todo, win, gone, got, fix, need, pc,
          wantp, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>


TypeOK ==
  /\ bcb \in [Pages -> {"absent","io","valid"}]
  /\ owner \in [Pages -> Scans \cup {NoScan}]
  /\ reader \in [Pages -> Scans \cup {NoScan, HotReader}]
  /\ bottom \in SUBSET Pages
  /\ inflight \in [Scans -> SUBSET Pages]
  /\ cq \in [Scans -> SUBSET Pages]
  /\ res \in [Pages -> {"ok","err"}]
  /\ todo \in [Scans -> SUBSET Pages]
  /\ win \in [Scans -> SUBSET Pages]
  /\ gone \in [Scans -> SUBSET Pages]
  /\ got \in [Scans -> SUBSET Pages]
  /\ fix \in [Scans -> Pages \cup {NoPage}]
  /\ need \in [Scans -> Pages \cup {NoPage}]
  /\ pc \in [Scans -> {"run","sleepPage","sleepFrame","drain","done"}]
  /\ wantp \in [Scans -> Pages \cup {NoPage}]
  /\ early \in [Scans -> BOOLEAN]
  /\ errs \in Int /\ errs >= 0 /\ errs <= MaxErrors
  /\ deallocd \in SUBSET Pages
  /\ uaf \in BOOLEAN /\ dup \in BOOLEAN /\ foreignDemote \in BOOLEAN /\ recycled \in BOOLEAN

Init ==
  /\ bcb = [p \in Pages |-> IF p \in Hot THEN "valid" ELSE "absent"]
  /\ owner = [p \in Pages |-> NoScan]
  /\ reader = [p \in Pages |-> IF p \in Hot THEN HotReader ELSE NoScan]
  /\ bottom = {}
  /\ inflight = [s \in Scans |-> {}]
  /\ cq = [s \in Scans |-> {}]
  /\ res = [p \in Pages |-> "ok"]
  /\ todo = [s \in Scans |-> Pages]
  /\ win = [s \in Scans |-> {}]
  /\ gone = [s \in Scans |-> {}]
  /\ got = [s \in Scans |-> {}]
  /\ fix = [s \in Scans |-> NoPage]
  /\ need = [s \in Scans |-> NoPage]
  /\ pc = [s \in Scans |-> "run"]
  /\ wantp = [s \in Scans |-> NoPage]
  /\ early = [s \in Scans |-> FALSE]
  /\ errs = 0
  /\ deallocd = {}
  /\ uaf = FALSE /\ dup = FALSE /\ foreignDemote = FALSE /\ recycled = FALSE

(***************************************************************************)
(* The frame pool                                                          *)
(***************************************************************************)
Used == Cardinality({p \in Pages : bcb[p] # "absent"})
Fixed(p) == \E s \in Scans : fix[s] = p
\* A frame a pgbuf_fix is reading into stays reserved for that fixer until it is fixed.
Reserved(p) == \E s \in Scans : need[s] = p

\* Frames page replacement may take: valid and unfixed.  The mutants add frames
\* under I/O or fixed frames.
Eligible ==
  {v \in Pages : \/ bcb[v] = "valid" /\ ~Fixed(v) /\ ~Reserved(v)
                 \/ Mutant = "victim_in_io" /\ bcb[v] = "io"
                 \/ Mutant = "victim_fixed" /\ bcb[v] = "valid"}

\* The LRU bottom goes first (D15).
Victims == IF Eligible \cap bottom # {} THEN Eligible \cap bottom ELSE Eligible

FrameAvail == Used < NFrames \/ Eligible # {}

\* Claim a frame for page p (absent) for a read by s: a free frame, or a victim's.
TakeFrame(s, p) ==
  \/ /\ Used < NFrames
     /\ bcb' = [bcb EXCEPT ![p] = "io"]
     /\ owner' = [owner EXCEPT ![p] = s]
     /\ reader' = [reader EXCEPT ![p] = s]
     /\ UNCHANGED <<bottom, uaf, recycled>>
  \/ /\ Used >= NFrames
     /\ \E v \in Victims :
          /\ bcb' = [bcb EXCEPT ![p] = "io", ![v] = "absent"]
          /\ owner' = [owner EXCEPT ![p] = s]
          /\ reader' = [reader EXCEPT ![p] = s, ![v] = NoScan]
          /\ bottom' = bottom \ {v}
          /\ uaf' = (uaf \/ bcb[v] = "io" \/ Fixed(v))
          /\ recycled' = (recycled \/ v \in bottom)

(***************************************************************************)
(* Scan actions                                                            *)
(***************************************************************************)

\* Refill: take the next page of the list into the window and issue its read at once
\* (stage + submit in this step, D7).
RefillRead(s) ==
  /\ pc[s] = "run"
  /\ need[s] = NoPage
  /\ Cardinality(win[s]) < W
  /\ \E p \in todo[s] :
       /\ bcb[p] = "absent"
       /\ FrameAvail
       /\ TakeFrame(s, p)
       /\ inflight' = [inflight EXCEPT ![s] = @ \cup {p}]
       /\ todo' = [todo EXCEPT ![s] = @ \ {p}]
       /\ win' = [win EXCEPT ![s] = @ \cup {p}]
  /\ UNCHANGED <<cq, res, gone, got, fix, need, pc, wantp, early, errs, deallocd, dup, foreignDemote>>

\* Refill without a read: the page is in the buffer, under another thread's read, or no
\* frame is free at once (D7a: read-ahead never waits).  The page is only noted.
\* The mutant forgets a page another thread is reading.
RefillNote(s) ==
  /\ pc[s] = "run"
  /\ need[s] = NoPage
  /\ Cardinality(win[s]) < W
  /\ \E p \in todo[s] :
       /\ ~(bcb[p] = "absent" /\ FrameAvail)
       /\ todo' = [todo EXCEPT ![s] = @ \ {p}]
       /\ IF Mutant = "skip_other_io" /\ bcb[p] = "io"
            THEN /\ gone' = [gone EXCEPT ![s] = @ \cup {p}]
                 /\ UNCHANGED win
            ELSE /\ win' = [win EXCEPT ![s] = @ \cup {p}]
                 /\ UNCHANGED gone
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, got, fix, need, pc, wantp, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

\* A window page is not in the buffer (never read, victimized, or its read failed) and
\* the scan needs it: pgbuf_fix reads it through the ring.  The frame is reserved for this
\* fixer from the claim on, as today's read path adds its fix before it lets the BCB go.
ReadNow(s) ==
  /\ pc[s] = "run"
  /\ fix[s] = NoPage
  /\ need[s] = NoPage
  /\ \E p \in win[s] :
       /\ bcb[p] = "absent"
       /\ FrameAvail
       /\ TakeFrame(s, p)
       /\ inflight' = [inflight EXCEPT ![s] = @ \cup {p}]
       /\ need' = [need EXCEPT ![s] = p]
  /\ UNCHANGED <<cq, res, todo, win, gone, got, fix, pc, wantp, early, errs, deallocd, dup, foreignDemote>>

\* The read pgbuf_fix waited for completed: the page is fixed.
FixNeed(s) ==
  /\ pc[s] = "run"
  /\ need[s] # NoPage
  /\ bcb[need[s]] = "valid"
  /\ fix' = [fix EXCEPT ![s] = need[s]]
  /\ need' = [need EXCEPT ![s] = NoPage]
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, todo, win, gone, got, pc, wantp, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

\* The read failed: pgbuf_fix returns the error path; the scan reads the page again.
ReadFailed(s) ==
  /\ pc[s] = "run"
  /\ need[s] # NoPage
  /\ bcb[need[s]] = "absent"
  /\ need' = [need EXCEPT ![s] = NoPage]
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, todo, win, gone, got, fix, pc, wantp, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

\* Mutant: a window page that left the buffer is dropped instead of read again.
DropAbsent(s) ==
  /\ Mutant = "drop_on_victim"
  /\ pc[s] = "run"
  /\ \E p \in win[s] :
       /\ bcb[p] = "absent"
       /\ win' = [win EXCEPT ![s] = @ \ {p}]
       /\ gone' = [gone EXCEPT ![s] = @ \cup {p}]
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, todo, got, fix, need, pc, wantp, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

\* No frame for a page the scan needs: sleep until one is free.  The scan reaps its own
\* ring first: it sleeps only with an empty ring (its own I/O frames could be the victims).
WaitFrame(s) ==
  /\ pc[s] = "run"
  /\ need[s] = NoPage
  /\ fix[s] = NoPage
  /\ \E p \in win[s] : bcb[p] = "absent"
  /\ ~FrameAvail
  /\ inflight[s] \cup cq[s] = {} \/ Mutant = "frame_wait_with_io"
  /\ pc' = [pc EXCEPT ![s] = "sleepFrame"]
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, todo, win, gone, got, fix, need, wantp, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

WakeFrame(s) ==
  /\ pc[s] = "sleepFrame"
  /\ FrameAvail
  /\ pc' = [pc EXCEPT ![s] = "run"]
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, todo, win, gone, got, fix, need, wantp, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

\* Nothing in the window is ready and a window page is under another thread's read:
\* sleep on that page.
SleepOnPage(s) ==
  /\ pc[s] = "run"
  /\ need[s] = NoPage
  /\ fix[s] = NoPage
  /\ \A q \in win[s] : bcb[q] # "valid"
  /\ \E p \in win[s] :
       /\ bcb[p] = "io"
       /\ owner[p] # s
       /\ wantp' = [wantp EXCEPT ![s] = p]
  /\ pc' = [pc EXCEPT ![s] = "sleepPage"]
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, todo, win, gone, got, fix, need, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

WakePage(s) ==
  /\ pc[s] = "sleepPage"
  /\ bcb[wantp[s]] # "io"
  /\ pc' = [pc EXCEPT ![s] = "run"]
  /\ wantp' = [wantp EXCEPT ![s] = NoPage]
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, todo, win, gone, got, fix, need, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

\* Process one CQE of ring o: ok -> valid; err -> the frame goes back.
ReapOne(o, p) ==
  /\ p \in cq[o]
  /\ cq' = [cq EXCEPT ![o] = @ \ {p}]
  /\ bcb' = [bcb EXCEPT ![p] = IF res[p] = "ok" THEN "valid" ELSE "absent"]
  /\ owner' = [owner EXCEPT ![p] = NoScan]
  /\ reader' = [reader EXCEPT ![p] = IF res[p] = "ok" THEN reader[p] ELSE NoScan]

ReapOwn(s) ==
  /\ pc[s] \in {"run", "drain"}
  /\ \E p \in cq[s] : ReapOne(s, p)
  /\ UNCHANGED <<bottom, inflight, res, todo, win, gone, got, fix, need, pc, wantp, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

ReapForWaiter(s) ==
  /\ pc[s] = "sleepPage"
  /\ bcb[wantp[s]] = "io"
  /\ owner[wantp[s]] \in Scans
  /\ \E p \in cq[owner[wantp[s]]] : ReapOne(owner[wantp[s]], p)
  /\ UNCHANGED <<bottom, inflight, res, todo, win, gone, got, fix, need, pc, wantp, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

\* Completion order: fix whichever window page is valid.
Fix(s) ==
  /\ pc[s] = "run"
  /\ need[s] = NoPage
  /\ fix[s] = NoPage
  /\ \E p \in win[s] :
       /\ bcb[p] = "valid"
       /\ fix' = [fix EXCEPT ![s] = p]
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, todo, win, gone, got, need, pc, wantp, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

\* Process the fixed page (return its rows, or skip a deallocated page), unfix it, and
\* demote it to the LRU bottom when this scan read it (D15).
Process(s) ==
  /\ pc[s] = "run"
  /\ fix[s] # NoPage
  /\ dup' = (dup \/ fix[s] \in gone[s])
  /\ gone' = [gone EXCEPT ![s] = @ \cup {fix[s]}]
  /\ got' = [got EXCEPT ![s] = IF fix[s] \in deallocd THEN @ ELSE @ \cup {fix[s]}]
  /\ win' = [win EXCEPT ![s] = IF Mutant = "double_consume" THEN @ ELSE @ \ {fix[s]}]
  /\ fix' = [fix EXCEPT ![s] = NoPage]
  /\ IF reader[fix[s]] = s \/ Mutant = "demote_any"
       THEN /\ bottom' = bottom \cup {fix[s]}
            /\ foreignDemote' = (foreignDemote \/ reader[fix[s]] # s)
       ELSE UNCHANGED <<bottom, foreignDemote>>
  /\ UNCHANGED <<bcb, owner, reader, inflight, cq, res, todo, need, pc, wantp, early, errs, deallocd, uaf, recycled>>

\* LIMIT reached, interrupt or error: the scan stops where it is.  It unfixes what it
\* holds and abandons its window; the mutant keeps the fix.
EarlyEnd(s) ==
  /\ pc[s] \in {"run", "sleepPage", "sleepFrame"}
  /\ ~early[s]
  /\ early' = [early EXCEPT ![s] = TRUE]
  /\ todo' = [todo EXCEPT ![s] = {}]
  /\ win' = [win EXCEPT ![s] = {}]
  /\ fix' = [fix EXCEPT ![s] = IF Mutant = "leak_fix" THEN @ ELSE NoPage]
  /\ need' = [need EXCEPT ![s] = NoPage]
  /\ wantp' = [wantp EXCEPT ![s] = NoPage]
  /\ pc' = [pc EXCEPT ![s] = "drain"]
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, gone, got, errs, deallocd, uaf, dup, foreignDemote, recycled>>

\* The page list is exhausted.
End(s) ==
  /\ pc[s] = "run"
  /\ need[s] = NoPage
  /\ todo[s] = {} /\ win[s] = {} /\ fix[s] = NoPage
  /\ pc' = [pc EXCEPT ![s] = "drain"]
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, todo, win, gone, got, fix, need, wantp, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

\* Back to the thread pool once the own ring is empty (D8).
Finish(s) ==
  /\ pc[s] = "drain"
  /\ inflight[s] \cup cq[s] = {} \/ Mutant = "no_drain"
  /\ pc' = [pc EXCEPT ![s] = "done"]
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, todo, win, gone, got, fix, need, wantp, early, errs, deallocd, uaf, dup, foreignDemote, recycled>>

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
    /\ UNCHANGED <<bcb, owner, reader, bottom, todo, win, gone, got, fix, need, pc, wantp, early, deallocd, uaf, dup, foreignDemote, recycled>>

\* Vacuum deallocates a page none of whose rows any snapshot sees (write latch: unfixed).
Dealloc ==
  /\ Cardinality(deallocd) < MaxDealloc
  /\ \E p \in Pages \ (Vis \cup deallocd) :
       /\ ~Fixed(p)
       /\ deallocd' = deallocd \cup {p}
  /\ UNCHANGED <<bcb, owner, reader, bottom, inflight, cq, res, todo, win, gone, got, fix, need, pc, wantp, early, errs, uaf, dup, foreignDemote, recycled>>

Terminated ==
  /\ \A s \in Scans : pc[s] = "done"
  /\ \A p \in Pages : bcb[p] # "io"
  /\ UNCHANGED vars

ScanStep(s) ==
  \/ RefillRead(s) \/ RefillNote(s) \/ ReadNow(s) \/ FixNeed(s) \/ ReadFailed(s) \/ DropAbsent(s)
  \/ WaitFrame(s) \/ WakeFrame(s) \/ SleepOnPage(s) \/ WakePage(s)
  \/ ReapOwn(s) \/ ReapForWaiter(s) \/ Fix(s) \/ Process(s) \/ End(s) \/ Finish(s)

Next ==
  \/ \E s \in Scans : ScanStep(s) \/ EarlyEnd(s)
  \/ DeviceComplete \/ Dealloc
  \/ Terminated

\* A runnable scan runs; a submitted read completes.
Fairness ==
  /\ \A s \in Scans : WF_vars(ScanStep(s))
  /\ WF_vars(DeviceComplete)

Spec == Init /\ [][Next]_vars /\ Fairness

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)
\* C1: no frame under I/O or fixed is taken as a victim.
NoFrameReuse == ~uaf

\* C3: no page twice; a scan that ran to its end returned every visible page.
AtMostOnce == ~dup
Complete == \A s \in Scans : (pc[s] = "done" /\ ~early[s]) => Vis \subseteq got[s]

\* C4: a scan that ended holds no fix.
NoFixAfterEnd == \A s \in Scans : pc[s] \in {"drain", "done"} => fix[s] = NoPage

\* C5: a scan demotes only pages it read; a page that was in the buffer is never at the bottom.
NoForeignDemotion == ~foreignDemote /\ \A p \in bottom : reader[p] # HotReader

\* C2 / C4 (liveness): every scan gets back to the pool and no frame stays under I/O.
AllComplete == <>[](/\ \A s \in Scans : pc[s] = "done"
                    /\ \A p \in Pages : bcb[p] # "io")

\* Witnesses
NotOutOfOrder == ~(\E s \in Scans : fix[s] # NoPage /\ \E q \in win[s] : bcb[q] = "io")
NotRecycled == ~recycled
NotSkipped == ~(\E s \in Scans : gone[s] \ got[s] # {})
NotSleptOnFrame == ~(\E s \in Scans : pc[s] = "sleepFrame")
NotFullRun == ~(\E s \in Scans : pc[s] = "done" /\ ~early[s])

(***************************************************************************)
(* Inductive invariant                                                     *)
(***************************************************************************)
RingPartition == \A s \in Scans : inflight[s] \cap cq[s] = {}
IoHasOwner == \A p \in Pages : (bcb[p] = "io") <=> (owner[p] # NoScan)
OwnerRingHoldsIo ==
  \A p \in Pages : owner[p] # NoScan => p \in inflight[owner[p]] \cup cq[owner[p]]
RingsHoldOnlyOwned == \A s \in Scans : \A p \in inflight[s] \cup cq[s] : owner[p] = s
ReaderShape ==
  \A p \in Pages : /\ (bcb[p] = "absent") <=> (reader[p] = NoScan)
                   /\ bcb[p] = "io" => reader[p] = owner[p]
BottomShape == \A p \in bottom : bcb[p] = "valid" /\ reader[p] \in Scans
FramePool == Used <= NFrames
ListPartition ==
  \A s \in Scans : /\ todo[s] \cap win[s] = {}
                   /\ todo[s] \cap gone[s] = {}
                   /\ win[s] \cap gone[s] = {}
                   /\ got[s] \subseteq gone[s]
Coverage == \A s \in Scans : ~early[s] => todo[s] \cup win[s] \cup gone[s] = Pages
GotVisible == \A s \in Scans : gone[s] \cap Vis \subseteq got[s]
DeallocShape == deallocd \cap Vis = {}
FixShape ==
  \A s \in Scans : fix[s] # NoPage =>
    /\ pc[s] = "run"
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
    /\ pc[s] = "sleepPage" => wantp[s] \in win[s] /\ fix[s] = NoPage
    /\ pc[s] = "sleepFrame" => inflight[s] \cup cq[s] = {} /\ fix[s] = NoPage
EndShape ==
  \A s \in Scans :
    /\ pc[s] \in {"drain", "done"} => todo[s] = {} /\ win[s] = {}
    /\ pc[s] = "done" => inflight[s] \cup cq[s] = {}

IndInv ==
  /\ TypeOK
  /\ RingPartition
  /\ IoHasOwner
  /\ OwnerRingHoldsIo
  /\ RingsHoldOnlyOwned
  /\ ReaderShape
  /\ BottomShape
  /\ FramePool
  /\ ListPartition
  /\ Coverage
  /\ GotVisible
  /\ DeallocShape
  /\ FixShape
  /\ NeedShape
  /\ SleepShape
  /\ EndShape
  /\ NoFrameReuse
  /\ AtMostOnce
  /\ Complete
  /\ NoFixAfterEnd
  /\ NoForeignDemotion
=============================================================================
