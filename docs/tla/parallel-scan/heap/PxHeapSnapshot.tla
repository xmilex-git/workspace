---------------------------- MODULE PxHeapSnapshot ----------------------------
(* The snapshot-level abstraction of the parallel heap scan: what rows the scan
   returns, with page latches abstracted away. A worker reads one page in one
   step, which is sound for row visibility because a page is read under its read
   latch, so no insert, delete or vacuum changes it during the read.

   The scan collects the page bitmap at open and hands every page of it to one
   worker (any partition: ftab_set::split is one of them). A page deallocated
   since the bitmap is skipped. The transaction's MVCC snapshot is taken before
   open (REPEATABLE READ: qexec_execute_query; the candidate fix), or by the
   first worker that starts (READ COMMITTED as the code stands). PxHeapScan.tla
   refines this module. *)
EXTENDS Naturals, FiniteSets

CONSTANTS Workers, NPages, NInit, NNew, VacuumRounds, Isolation, SnapshotPoint, MaxClock
ASSUME AbsAssm ==
  /\ Workers # {} /\ NPages \in Nat \ {0} /\ NInit \in 1..NPages /\ NNew \in Nat /\ VacuumRounds \in Nat
  /\ Isolation \in {"READ_COMMITTED", "REPEATABLE_READ"}
  /\ SnapshotPoint \in {"code", "before_open"}

Pages == 1..NPages
InitRows == 1..NInit
NewRows == (NInit + 1)..(NInit + NNew)
Rows == InitRows \cup NewRows
NoPage == 0
EarlySnapshot == Isolation = "REPEATABLE_READ" \/ SnapshotPoint = "before_open"

VARIABLES alloc, home, insC, delC, gone, clock, snap, bitmap, opened, owner,
          started, left, readCnt, scanDone, rounds
vars == <<alloc, home, insC, delC, gone, clock, snap, bitmap, opened, owner,
          started, left, readCnt, scanDone, rounds>>

VisibleAt(r, t) == insC[r] > 0 /\ insC[r] < t /\ ~(delC[r] > 0 /\ delC[r] < t)
OldestVisible == IF snap > 0 /\ ~scanDone THEN snap ELSE clock
PageEmpty(p) == \A r \in Rows : home[r] = p => gone[r]
Processed == bitmap \ UNION {left[w] : w \in Workers}

Init ==
  /\ alloc = [p \in Pages |-> IF p <= NInit THEN TRUE ELSE FALSE]
  /\ home = [r \in Rows |-> IF r \in InitRows THEN r ELSE NoPage]
  /\ insC = [r \in Rows |-> IF r \in InitRows THEN 1 ELSE 0]
  /\ delC = [r \in Rows |-> 0]
  /\ gone = [r \in Rows |-> FALSE]
  /\ clock = 2
  /\ snap = 0
  /\ bitmap = {}
  /\ opened = FALSE
  /\ owner = [p \in {} |-> CHOOSE w \in Workers : TRUE]
  /\ started = [w \in Workers |-> FALSE]
  /\ left = [w \in Workers |-> {}]
  /\ readCnt = [r \in Rows |-> 0]
  /\ scanDone = FALSE
  /\ rounds = VacuumRounds

\* ---- the scan ----
TakeEarlySnapshot ==            \* qexec_execute_query under REPEATABLE READ; the candidate fix
  /\ EarlySnapshot /\ snap = 0 /\ ~opened
  /\ snap' = clock
  /\ UNCHANGED <<alloc, home, insC, delC, gone, clock, bitmap, opened, owner, started, left, readCnt, scanDone, rounds>>

Open ==
  /\ ~opened /\ (EarlySnapshot => snap > 0)
  /\ opened' = TRUE
  /\ bitmap' = {p \in Pages : alloc[p]}
  /\ \E o \in [{p \in Pages : alloc[p]} -> Workers] : owner' = o
  /\ UNCHANGED <<alloc, home, insC, delC, gone, clock, snap, started, left, readCnt, scanDone, rounds>>

Start(w) ==
  /\ opened /\ ~started[w]
  /\ started' = [started EXCEPT ![w] = TRUE]
  /\ left' = [left EXCEPT ![w] = {p \in bitmap : owner[p] = w}]
  /\ snap' = IF snap = 0 THEN clock ELSE snap
  /\ UNCHANGED <<alloc, home, insC, delC, gone, clock, bitmap, opened, owner, readCnt, scanDone, rounds>>

ReadPage(w, p) ==
  /\ started[w] /\ p \in left[w]
  /\ left' = [left EXCEPT ![w] = @ \ {p}]
  /\ readCnt' = [r \in Rows |->
                   IF alloc[p] /\ home[r] = p /\ ~gone[r] /\ VisibleAt(r, snap) THEN readCnt[r] + 1 ELSE readCnt[r]]
  /\ UNCHANGED <<alloc, home, insC, delC, gone, clock, snap, bitmap, opened, owner, started, scanDone, rounds>>

Finish ==
  /\ opened /\ ~scanDone
  /\ \A w \in Workers : started[w] /\ left[w] = {}
  /\ scanDone' = TRUE
  /\ UNCHANGED <<alloc, home, insC, delC, gone, clock, snap, bitmap, opened, owner, started, left, readCnt, rounds>>

\* ---- other transactions and vacuum ----
Insert(r, p) ==
  /\ r \in NewRows /\ insC[r] = 0
  /\ alloc' = [alloc EXCEPT ![p] = TRUE]
  /\ home' = [home EXCEPT ![r] = p]
  /\ insC' = [insC EXCEPT ![r] = clock]
  /\ clock' = clock + 1
  /\ UNCHANGED <<delC, gone, snap, bitmap, opened, owner, started, left, readCnt, scanDone, rounds>>

Delete(r) ==
  /\ insC[r] > 0 /\ delC[r] = 0
  /\ delC' = [delC EXCEPT ![r] = clock]
  /\ clock' = clock + 1
  /\ UNCHANGED <<alloc, home, insC, gone, snap, bitmap, opened, owner, started, left, readCnt, scanDone, rounds>>

VacuumRows(p) ==
  /\ rounds > 0 /\ alloc[p]
  /\ rounds' = rounds - 1
  /\ gone' = [r \in Rows |-> gone[r] \/ (home[r] = p /\ delC[r] > 0 /\ delC[r] < OldestVisible)]
  /\ UNCHANGED <<alloc, home, insC, delC, clock, snap, bitmap, opened, owner, started, left, readCnt, scanDone>>

VacuumIdle ==
  /\ rounds > 0 /\ rounds' = rounds - 1
  /\ UNCHANGED <<alloc, home, insC, delC, gone, clock, snap, bitmap, opened, owner, started, left, readCnt, scanDone>>

VacuumPage(p) ==
  /\ rounds > 0 /\ alloc[p] /\ PageEmpty(p)
  /\ rounds' = rounds - 1
  /\ alloc' = [alloc EXCEPT ![p] = FALSE]
  /\ UNCHANGED <<home, insC, delC, gone, clock, snap, bitmap, opened, owner, started, left, readCnt, scanDone>>

\* the scan is over: stutter (the counterpart of PlusCal's Terminating)
Terminated == scanDone /\ UNCHANGED vars

Next ==
  \/ Terminated
  \/ TakeEarlySnapshot \/ Open \/ Finish \/ VacuumIdle
  \/ \E w \in Workers : Start(w) \/ \E p \in Pages : ReadPage(w, p)
  \/ \E r \in Rows, p \in Pages : Insert(r, p)
  \/ \E r \in Rows : Delete(r)
  \/ \E p \in Pages : VacuumRows(p) \/ VacuumPage(p)

Spec == Init /\ [][Next]_vars

\* ---- properties ----
\* Boolean and integer typing apart: tlapm 1.4.5's SMT cannot mix them (cubrid-tla P4).
BoolOK == /\ alloc \in [Pages -> BOOLEAN] /\ gone \in [Rows -> BOOLEAN]
          /\ opened \in BOOLEAN /\ scanDone \in BOOLEAN /\ started \in [Workers -> BOOLEAN]
NatOK == /\ insC \in [Rows -> Nat] /\ delC \in [Rows -> Nat] /\ readCnt \in [Rows -> Nat]
         /\ clock \in Nat /\ snap \in Nat /\ rounds \in Nat
SetOK == /\ home \in [Rows -> Pages \cup {NoPage}] /\ bitmap \subseteq Pages
         /\ owner \in [bitmap -> Workers] /\ left \in [Workers -> SUBSET Pages]
TypeOK == BoolOK /\ NatOK /\ SetOK

\* C1: the scan returns exactly the rows visible to its snapshot, each once.
SameAsSnapshot == scanDone => \A r \in Rows : readCnt[r] = IF VisibleAt(r, snap) THEN 1 ELSE 0

\* Inductive invariant of the early-snapshot variant (REPEATABLE READ, or the fix).
\* The rest of the inductive invariant, one named conjunct each so a proof can take them one by one.
R_early == EarlySnapshot
R_snap == clock > 0 /\ snap <= clock /\ (opened => snap > 0)
R_clock == \A r \in Rows : insC[r] < clock /\ delC[r] < clock
R_order == \A r \in Rows : delC[r] > 0 => insC[r] > 0 /\ insC[r] < delC[r]
R_home == \A r \in Rows : (insC[r] > 0) = (home[r] # NoPage)
R_gone == \A r \in Rows : gone[r] => delC[r] > 0
\* a row that is still there lives on an allocated page
R_alloc == \A r \in Rows : home[r] # NoPage /\ ~gone[r] => alloc[home[r]]
\* a row visible to the snapshot is not removed before the scan ends
R_vis == \A r \in Rows : VisibleAt(r, snap) /\ ~scanDone => ~gone[r]
R_open == ~opened => bitmap = {} /\ ~scanDone
R_start == \A w \in Workers : (~opened => ~started[w]) /\ (~started[w] => left[w] = {})
R_left == \A w \in Workers : left[w] \subseteq {p \in bitmap : owner[p] = w}
\* a row visible to the snapshot was on an allocated page at open, so it is in the bitmap
R_bitmap == \A r \in Rows : opened /\ VisibleAt(r, snap) => home[r] \in bitmap
\* a visible row is counted once its page is handed to a started worker and no longer left
R_count == \A r \in Rows : readCnt[r] =
             IF opened /\ VisibleAt(r, snap) /\ started[owner[home[r]]] /\ home[r] \notin left[owner[home[r]]]
             THEN 1 ELSE 0
R_done == scanDone => \A w \in Workers : started[w] /\ left[w] = {}
RestInv == R_early /\ R_snap /\ R_clock /\ R_order /\ R_home /\ R_gone /\ R_alloc /\ R_vis
           /\ R_open /\ R_start /\ R_left /\ R_bitmap /\ R_count /\ R_done

IndInv == TypeOK /\ RestInv

\* TLC's inductiveness check enumerates IndInv over bounded types; constraints follow each variable.
IndInitTLC ==
  /\ opened \in BOOLEAN /\ scanDone \in BOOLEAN /\ (scanDone => opened)
  /\ clock \in 2..MaxClock /\ snap \in 0..clock /\ (opened => snap > 0)
  /\ rounds \in 0..VacuumRounds
  /\ insC \in [Rows -> 0..(clock - 1)]
  /\ delC \in [Rows -> 0..(clock - 1)] /\ \A r \in Rows : delC[r] > 0 => insC[r] > 0 /\ insC[r] < delC[r]
  /\ home \in [Rows -> Pages \cup {NoPage}] /\ \A r \in Rows : (insC[r] > 0) = (home[r] # NoPage)
  /\ gone \in [Rows -> BOOLEAN] /\ \A r \in Rows : gone[r] => delC[r] > 0
  /\ alloc \in [Pages -> BOOLEAN] /\ \A r \in Rows : home[r] # NoPage /\ ~gone[r] => alloc[home[r]]
  /\ bitmap \in SUBSET Pages
  /\ owner \in [bitmap -> Workers]
  /\ started \in [Workers -> BOOLEAN]
  /\ left \in [Workers -> SUBSET Pages]
  /\ readCnt \in [Rows -> 0..1]
  /\ IndInv

\* witness: a page allocated after open holds a row
NotRowOnNewPage == ~(opened /\ \E r \in Rows : home[r] # NoPage /\ home[r] \notin bitmap)
=============================================================================
