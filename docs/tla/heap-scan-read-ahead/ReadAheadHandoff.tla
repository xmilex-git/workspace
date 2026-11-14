------------------------- MODULE ReadAheadHandoff -------------------------
(***************************************************************************)
(* Handing the pages a loader read ahead to the scan (CBRD-28043).         *)
(*                                                                         *)
(* A loader thread reads the pages the serial walk reaches next into the   *)
(* buffer, at most Depth pages ahead of the walk.  The walk fixes the      *)
(* pages in file order, one at a time, and reads a page itself when it is  *)
(* not in the buffer.  Between the loader's read and the walk's fix the    *)
(* page may be evicted; the walk then reads it again.  Option is how the   *)
(* loader protects a page until the walk takes it:                         *)
(*   "none"      no protection (where the page sits in the LRU list is not *)
(*               modeled: it changes how likely an eviction is, not        *)
(*               whether it can happen)                                    *)
(*   "fcnt_pin"  the loader raises the page's fix count without a latch,   *)
(*               the walk lowers it after its own fix                      *)
(*   "latch_pin" the loader keeps a read latch until the walk has passed   *)
(*               the page                                                  *)
(*   "handoff"   the loader fixes the page with a read latch and hands the *)
(*               fix (its holder entry) over to the walk's thread, which   *)
(*               unfixes it when it has read the page                      *)
(*   "flag"      the loader marks the page "do not evict", the walk's fix  *)
(*               clears the mark                                           *)
(*                                                                         *)
(* Beside them a writer wants the write latch of some page, another thread *)
(* needs one BCB for a page outside the table, and pages that nothing      *)
(* protects are evicted.  The walk may stop before the last page (a LIMIT, *)
(* an error) and may stand still for any time (it waits for its client).   *)
(*                                                                         *)
(* Claims (MAP.md): C10 a page nobody latches has fix count 0; C11 when    *)
(* the walk and its loader have ended no page is left protected; C12 a     *)
(* writer gets its latch and another thread gets a BCB even while the walk *)
(* stands still; C13 the walk and the loader end.                          *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS N,       \* pages of the table 1..N, in file order
          Depth,   \* pages the loader is ahead of the walk at most
          Bcbs,    \* BCBs of the buffer
          Option,  \* "none" | "fcnt_pin" | "latch_pin" | "handoff" | "flag"
          Mutant   \* "none" | "stop_keeps" | "cleanup_before_join" | "loader_ignores_stop"

\* apalache-type: N Int
\* apalache-type: Depth Int
\* apalache-type: Bcbs Int
\* apalache-type: Option Str
\* apalache-type: Mutant Str
\* apalache-type: inBuf Int -> Bool
\* apalache-type: pin Int -> Bool
\* apalache-type: avoid Int -> Bool
\* apalache-type: lrl Int -> Bool
\* apalache-type: wl Int -> Bool
\* apalache-type: walk Int
\* apalache-type: spc Str
\* apalache-type: lpc Str
\* apalache-type: lpage Int
\* apalache-type: lcur Int
\* apalache-type: loaded Set(Int)
\* apalache-type: reread Bool
\* apalache-type: wpc Str
\* apalache-type: wpage Int
\* apalache-type: opc Str

CInit ==
  /\ N = 3
  /\ Depth \in 1..2
  /\ Bcbs = 3
  /\ Option \in {"none", "flag"}
  /\ Mutant = "none"

VARIABLES inBuf,   \* page -> in the buffer
          pin,     \* page -> fix count raised by the loader, no latch
          avoid,   \* page -> marked "do not evict"
          lrl,     \* page -> a read latch the loader took is held ("latch_pin": by the loader, "handoff": by the walk)
          wl,      \* page -> the writer holds the write latch
          walk,    \* the last page the walk fixed (0 = none)
          spc,     \* the walk: "run" | "stopping" | "done"
          lpc,     \* the loader: "idle" | "load" | "off"
          lpage,   \* the page the loader is reading (0 = none)
          lcur,    \* the next page the loader takes
          loaded,  \* ghost: pages the loader put into the buffer
          reread,  \* ghost: the walk read a page the loader had put into the buffer
          wpc,     \* the writer: "idle" | "want" | "hold" | "done"
          wpage,   \* the page the writer wants (0 = none)
          opc      \* the other thread: "want" | "done" (it keeps its BCB)

vars == <<inBuf, pin, avoid, lrl, wl, walk, spc, lpc, lpage, lcur, loaded, reread, wpc, wpage, opc>>

P == 1..N
NoPage == [p \in P |-> FALSE]

Free == Bcbs - Cardinality({p \in P : inBuf[p]}) - (IF opc = "done" THEN 1 ELSE 0) - (IF lpc = "load" THEN 1 ELSE 0)

Init ==
  /\ inBuf = NoPage
  /\ pin = NoPage
  /\ avoid = NoPage
  /\ lrl = NoPage
  /\ wl = NoPage
  /\ walk = 0
  /\ spc = "run"
  /\ lpc = "idle"
  /\ lpage = 0
  /\ lcur = 1
  /\ loaded = {}
  /\ reread = FALSE
  /\ wpc = "idle"
  /\ wpage = 0
  /\ opc = "want"

---------------------------------------------------------------------------
\* The loader.

\* The walk passed the loader's next page, or the page is in the buffer: nothing to read.
LSkip ==
  /\ lpc = "idle" /\ spc = "run" /\ lcur <= N
  /\ lcur <= walk \/ inBuf[lcur]
  /\ lcur' = lcur + 1
  /\ UNCHANGED <<inBuf, pin, avoid, lrl, wl, walk, spc, lpc, lpage, loaded, reread, wpc, wpage, opc>>

\* Takes a BCB for its next page and reads it (the page is buffer-locked meanwhile: the walk waits for it).
LPick ==
  /\ lpc = "idle" /\ spc = "run" /\ lcur <= N
  /\ lcur > walk /\ lcur <= walk + Depth
  /\ ~inBuf[lcur]
  /\ ~(wpc = "hold" /\ wpage = lcur)
  /\ Free > 0
  /\ lpc' = "load"
  /\ lpage' = lcur
  /\ lcur' = lcur + 1
  /\ UNCHANGED <<inBuf, pin, avoid, lrl, wl, walk, spc, loaded, reread, wpc, wpage, opc>>

\* The page enters the buffer with the protection Option gives, also when the walk stopped meanwhile.
LInstall ==
  /\ lpc = "load"
  /\ inBuf' = [inBuf EXCEPT ![lpage] = TRUE]
  /\ pin' = IF Option = "fcnt_pin" THEN [pin EXCEPT ![lpage] = TRUE] ELSE pin
  /\ lrl' = IF Option \in {"latch_pin", "handoff"} THEN [lrl EXCEPT ![lpage] = TRUE] ELSE lrl
  /\ avoid' = IF Option = "flag" THEN [avoid EXCEPT ![lpage] = TRUE] ELSE avoid
  /\ loaded' = loaded \cup {lpage}
  /\ lpc' = "idle"
  /\ lpage' = 0
  /\ UNCHANGED <<wl, walk, spc, lcur, reread, wpc, wpage, opc>>

\* "latch_pin": the loader lets a latch go once the walk passed the page or stopped.
LRelease(p) ==
  /\ Option = "latch_pin"
  /\ lrl[p]
  /\ walk >= p \/ spc # "run"
  /\ lrl' = [lrl EXCEPT ![p] = FALSE]
  /\ UNCHANGED <<inBuf, pin, avoid, wl, walk, spc, lpc, lpage, lcur, loaded, reread, wpc, wpage, opc>>

LOff ==
  /\ lpc = "idle" /\ spc # "run"
  /\ Mutant # "loader_ignores_stop"
  /\ Option = "latch_pin" => \A p \in P : ~lrl[p]
  /\ lpc' = "off"
  /\ UNCHANGED <<inBuf, pin, avoid, lrl, wl, walk, spc, lpage, lcur, loaded, reread, wpc, wpage, opc>>

Loader == LSkip \/ LPick \/ LInstall \/ (\E p \in P : LRelease(p)) \/ LOff

---------------------------------------------------------------------------
\* The walk: fix, read and unfix the next page in one step (it holds no page between two steps).

ScanFix ==
  /\ spc = "run" /\ walk < N
  /\ LET p == walk + 1 IN
       /\ ~wl[p]
       /\ ~(lpc = "load" /\ lpage = p)
       /\ inBuf[p] \/ Free > 0
       /\ inBuf' = [inBuf EXCEPT ![p] = TRUE]
       /\ reread' = (reread \/ (~inBuf[p] /\ p \in loaded))
       /\ avoid' = [avoid EXCEPT ![p] = FALSE]
       /\ pin' = [pin EXCEPT ![p] = FALSE]
       /\ lrl' = IF Option = "handoff" THEN [lrl EXCEPT ![p] = FALSE] ELSE lrl
       /\ walk' = p
  /\ UNCHANGED <<wl, spc, lpc, lpage, lcur, loaded, wpc, wpage, opc>>

\* The walk ends: after the last page, or before it (a LIMIT, an error).
ScanStop ==
  /\ spc = "run"
  /\ spc' = "stopping"
  /\ UNCHANGED <<inBuf, pin, avoid, lrl, wl, walk, lpc, lpage, lcur, loaded, reread, wpc, wpage, opc>>

\* After the loader has ended, whatever it left protected is let go.
ScanCleanup ==
  /\ spc = "stopping"
  /\ lpc = "off" \/ Mutant = "cleanup_before_join"
  /\ avoid' = IF Mutant = "stop_keeps" THEN avoid ELSE NoPage
  /\ pin' = IF Mutant = "stop_keeps" THEN pin ELSE NoPage
  /\ lrl' = IF Option = "handoff" THEN NoPage ELSE lrl
  /\ spc' = "done"
  /\ UNCHANGED <<inBuf, wl, walk, lpc, lpage, lcur, loaded, reread, wpc, wpage, opc>>

Scan == ScanFix \/ ScanStop \/ ScanCleanup

---------------------------------------------------------------------------
\* The environment.

Evict(p) ==
  /\ inBuf[p]
  /\ ~pin[p] /\ ~avoid[p] /\ ~lrl[p] /\ ~wl[p]
  /\ inBuf' = [inBuf EXCEPT ![p] = FALSE]
  /\ UNCHANGED <<pin, avoid, lrl, wl, walk, spc, lpc, lpage, lcur, loaded, reread, wpc, wpage, opc>>

Evictor == \E p \in P : Evict(p)

WWant(w) ==
  /\ wpc = "idle"
  /\ wpc' = "want"
  /\ wpage' = w
  /\ UNCHANGED <<inBuf, pin, avoid, lrl, wl, walk, spc, lpc, lpage, lcur, loaded, reread, opc>>

WGrant ==
  /\ wpc = "want"
  /\ ~lrl[wpage]
  /\ ~(lpc = "load" /\ lpage = wpage)
  /\ inBuf[wpage] \/ Free > 0
  /\ inBuf' = [inBuf EXCEPT ![wpage] = TRUE]
  /\ wl' = [wl EXCEPT ![wpage] = TRUE]
  /\ wpc' = "hold"
  /\ UNCHANGED <<pin, avoid, lrl, walk, spc, lpc, lpage, lcur, loaded, reread, wpage, opc>>

WRelease ==
  /\ wpc = "hold"
  /\ wl' = [wl EXCEPT ![wpage] = FALSE]
  /\ wpc' = "done"
  /\ UNCHANGED <<inBuf, pin, avoid, lrl, walk, spc, lpc, lpage, lcur, loaded, reread, wpage, opc>>

Writer == (\E w \in P : WWant(w)) \/ WGrant \/ WRelease

OFix ==
  /\ opc = "want"
  /\ Free > 0
  /\ opc' = "done"
  /\ UNCHANGED <<inBuf, pin, avoid, lrl, wl, walk, spc, lpc, lpage, lcur, loaded, reread, wpc, wpage>>

AllDone == spc = "done" /\ lpc = "off" /\ wpc = "done" /\ opc = "done"
Idle == AllDone /\ UNCHANGED vars

Next == Loader \/ Scan \/ Evictor \/ Writer \/ OFix \/ Idle

Others == Loader \/ Evictor \/ Writer \/ OFix

\* Every thread is fair.
Spec == Init /\ [][Next]_vars /\ WF_vars(Scan) /\ WF_vars(Loader) /\ WF_vars(Evictor) /\ WF_vars(Writer) /\ WF_vars(OFix)

\* The walk is not: it may stand still for any time (it waits for its client), and it may never stop.
\* Once it has stopped it finishes its cleanup (one call, no client in between).
SpecStill == Init /\ [][Next]_vars /\ WF_vars(Loader) /\ WF_vars(Evictor) /\ WF_vars(Writer) /\ WF_vars(OFix)
             /\ WF_vars(ScanCleanup)

---------------------------------------------------------------------------
\* Properties.

TypeOK ==
  /\ inBuf \in [P -> BOOLEAN]
  /\ pin \in [P -> BOOLEAN]
  /\ avoid \in [P -> BOOLEAN]
  /\ lrl \in [P -> BOOLEAN]
  /\ wl \in [P -> BOOLEAN]
  /\ walk \in 0..N
  /\ spc \in {"run", "stopping", "done"}
  /\ lpc \in {"idle", "load", "off"}
  /\ lpage \in 0..N
  /\ lcur \in 1..(N + 1)
  /\ loaded \in SUBSET P
  /\ reread \in BOOLEAN
  /\ wpc \in {"idle", "want", "hold", "done"}
  /\ wpage \in 0..N
  /\ opc \in {"want", "done"}

\* C10: a page nobody latches has fix count 0 (what every fix assumes).
IdleHasNoFix == \A p \in P : pin[p] => (lrl[p] \/ wl[p])

\* C11: when the walk and its loader have ended, no page is left protected.
Protected == {p \in P : pin[p] \/ avoid[p] \/ lrl[p]}
NoProtectionLeft == (spc = "done" /\ lpc = "off") => Protected = {}

\* The buffer never holds more pages than it has BCBs.
BufferBound == Free >= 0

\* A mark protects: the walk never reads a marked page again.
MarkHolds == Option = "flag" => ~reread

\* C12, with the walk standing still.
WriterEnds == <>(wpc = "done")
OtherEnds == <>(opc = "done")

\* C13.
Ends == <>AllDone

\* Bookkeeping.
Shape ==
  /\ (lpc = "load") = (lpage # 0)
  /\ lpc = "load" => (~inBuf[lpage] /\ lpage < lcur /\ lpage \notin loaded)
  /\ (wpc \in {"want", "hold", "done"}) = (wpage # 0)
  /\ \A p \in P : wl[p] = (wpc = "hold" /\ wpage = p)
  /\ \A p \in P : wl[p] => inBuf[p]
  /\ \A p \in P : (pin[p] \/ avoid[p] \/ lrl[p]) => (inBuf[p] /\ p \in loaded)
  /\ \A p \in loaded : p < lcur
  /\ \A p \in P : pin[p] => Option = "fcnt_pin"
  /\ \A p \in P : lrl[p] => Option = "latch_pin"
  /\ \A p \in P : avoid[p] => Option = "flag"
  /\ \A p \in P : (avoid[p] \/ pin[p]) => p > walk
  /\ \A p \in P : avoid[p] => p <= walk + Depth
  /\ lpc = "load" => (lpage > walk /\ lpage <= walk + Depth)
  /\ lpc = "off" => spc # "run"
  /\ spc = "done" => (lpc = "off" /\ \A p \in P : ~avoid[p] /\ ~pin[p])
  /\ reread => Option # "flag"
  /\ (Option = "flag" /\ spc # "done") => \A p \in loaded : p > walk => avoid[p]
  /\ Depth >= 1

IndInv ==
  /\ TypeOK
  /\ BufferBound
  /\ NoProtectionLeft
  /\ MarkHolds
  /\ Shape

\* Witnesses.
NotReread == ~reread
NotAllDone == ~AllDone
NotStoppedEarly == ~(AllDone /\ walk < N)
NotMarked == \A p \in P : ~avoid[p]
=============================================================================
