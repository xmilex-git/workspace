------------------------ MODULE PxHeapSnapshot_proofs ------------------------
(* TLAPS proof that IndInv is an inductive invariant of the early-snapshot
   variant (REPEATABLE READ, or the snapshot taken before open) and implies
   SameAsSnapshot, for any number of workers, pages and rows: the premises of
   the TLA rule INV1 (cubrid-tla PROOFS.md). Each action proves the boolean,
   integer and set typing and the rest of the invariant apart (cubrid-tla P4). *)
EXTENDS PxHeapSnapshot, TLAPS

ASSUME Early == EarlySnapshot

USE AbsAssm, Early DEF Rows, InitRows, NewRows, Pages, NoPage

\* ---- Init ----
THEOREM InitInv == Init => IndInv
<1> SUFFICES ASSUME Init PROVE TypeOK /\ RestInv
  BY DEF IndInv
<1>1. BoolOK
  BY DEF TypeOK, Init, BoolOK
<1>2. NatOK
  BY DEF TypeOK, Init, NatOK
<1>3. SetOK
  BY DEF TypeOK, Init, SetOK
<1>4. RestInv
  BY DEF Init, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4 DEF TypeOK

\* ---- one lemma per action ----
LEMMA LTerminated == IndInv /\ Terminated => IndInv'
<1> SUFFICES ASSUME TypeOK, RestInv, Terminated PROVE TypeOK' /\ RestInv'
  BY DEF IndInv
<1>1. BoolOK' BY DEF TypeOK, Terminated, vars, BoolOK
<1>2. NatOK' BY DEF TypeOK, Terminated, vars, NatOK
<1>3. SetOK' BY DEF TypeOK, Terminated, vars, SetOK
<1>4. RestInv' BY DEF Terminated, vars, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt
<1>. QED BY <1>1, <1>2, <1>3, <1>4 DEF TypeOK

LEMMA LUnchanged == IndInv /\ UNCHANGED vars => IndInv'
<1> SUFFICES ASSUME TypeOK, RestInv, UNCHANGED vars PROVE TypeOK' /\ RestInv'
  BY DEF IndInv
<1>1. BoolOK' BY DEF TypeOK, vars, BoolOK
<1>2. NatOK' BY DEF TypeOK, vars, NatOK
<1>3. SetOK' BY DEF TypeOK, vars, SetOK
<1>4. RestInv' BY DEF vars, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt
<1>. QED BY <1>1, <1>2, <1>3, <1>4 DEF TypeOK

LEMMA LTakeEarlySnapshot == IndInv /\ TakeEarlySnapshot => IndInv'
<1> SUFFICES ASSUME TypeOK, RestInv, TakeEarlySnapshot PROVE TypeOK' /\ RestInv'
  BY DEF IndInv
<1> USE DEF TakeEarlySnapshot
<1>1. BoolOK' BY DEF TypeOK, BoolOK
<1>2. NatOK' BY DEF TypeOK, NatOK
<1>3. SetOK' BY DEF TypeOK, SetOK
<1>4. RestInv' BY DEF TypeOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, NatOK, BoolOK, SetOK
<1>. QED BY <1>1, <1>2, <1>3, <1>4 DEF TypeOK

LEMMA LOpen == IndInv /\ Open => IndInv'
<1> SUFFICES ASSUME TypeOK, RestInv, Open PROVE TypeOK' /\ RestInv'
  BY DEF IndInv
<1> USE DEF Open
<1>1. BoolOK' BY DEF TypeOK, BoolOK
<1>2. NatOK' BY DEF TypeOK, NatOK
<1>3. SetOK' BY DEF TypeOK, SetOK
<1>4. \A r \in Rows : VisibleAt(r, snap) => home[r] \in bitmap'
  BY DEF TypeOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, NatOK, BoolOK, SetOK
<1>5. RestInv'
  BY <1>4 DEF TypeOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, NatOK, BoolOK, SetOK
<1>. QED BY <1>1, <1>2, <1>3, <1>5 DEF TypeOK

LEMMA LFinish == IndInv /\ Finish => IndInv'
<1> SUFFICES ASSUME TypeOK, RestInv, Finish PROVE TypeOK' /\ RestInv'
  BY DEF IndInv
<1> USE DEF Finish
<1>1. BoolOK' BY DEF TypeOK, BoolOK
<1>2. NatOK' BY DEF TypeOK, NatOK
<1>3. SetOK' BY DEF TypeOK, SetOK
<1>4. RestInv' BY DEF TypeOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, NatOK, BoolOK, SetOK
<1>. QED BY <1>1, <1>2, <1>3, <1>4 DEF TypeOK

LEMMA LVacuumIdle == IndInv /\ VacuumIdle => IndInv'
<1> SUFFICES ASSUME TypeOK, RestInv, VacuumIdle PROVE TypeOK' /\ RestInv'
  BY DEF IndInv
<1> USE DEF VacuumIdle
<1>1. BoolOK' BY DEF TypeOK, BoolOK
<1>2. NatOK' BY DEF TypeOK, NatOK
<1>3. SetOK' BY DEF TypeOK, SetOK
<1>4. RestInv' BY DEF RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt
<1>. QED BY <1>1, <1>2, <1>3, <1>4 DEF TypeOK

LEMMA LStart == ASSUME NEW w \in Workers PROVE IndInv /\ Start(w) => IndInv'
<1> SUFFICES ASSUME TypeOK, RestInv, Start(w) PROVE TypeOK' /\ RestInv'
  BY DEF IndInv
<1> USE DEF Start
<1>1. BoolOK' BY DEF TypeOK, BoolOK
<1>2. NatOK' BY DEF TypeOK, NatOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
<1>3. SetOK' BY DEF TypeOK, SetOK
<1>4. snap' = snap /\ opened
  BY DEF TypeOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, NatOK
<1>5. \A r \in Rows : readCnt'[r] =
        IF opened' /\ VisibleAt(r, snap)' /\ started'[owner'[home'[r]]] /\ home'[r] \notin left'[owner'[home'[r]]]
        THEN 1 ELSE 0
  <2> SUFFICES ASSUME NEW r \in Rows
               PROVE readCnt[r] =
                       IF opened /\ VisibleAt(r, snap) /\ started'[owner[home[r]]]
                          /\ home[r] \notin left'[owner[home[r]]]
                       THEN 1 ELSE 0
    BY <1>4 DEF VisibleAt
  <2>1. CASE opened /\ VisibleAt(r, snap) /\ owner[home[r]] = w
    <3>1. home[r] \in bitmap
      BY <2>1 DEF RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
    <3>2. home[r] \in left'[w]
      BY <2>1, <3>1 DEF TypeOK, SetOK
    <3>3. ~started[w]
      BY <2>1, <3>2 DEF RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
    <3>. QED
      BY <2>1, <3>2, <3>3 DEF RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
  <2>2. CASE ~(opened /\ VisibleAt(r, snap) /\ owner[home[r]] = w)
    BY <2>2 DEF TypeOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, SetOK
  <2>. QED
    BY <2>1, <2>2
<1>6. RestInv'
  BY <1>4, <1>5 DEF TypeOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, NatOK, BoolOK, SetOK
<1>. QED BY <1>1, <1>2, <1>3, <1>6 DEF TypeOK

LEMMA LReadPage == ASSUME NEW w \in Workers, NEW p \in Pages PROVE IndInv /\ ReadPage(w, p) => IndInv'
<1> SUFFICES ASSUME TypeOK, RestInv, ReadPage(w, p) PROVE TypeOK' /\ RestInv'
  BY DEF IndInv
<1> USE DEF ReadPage
<1>1. BoolOK' BY DEF TypeOK, BoolOK
<1>2. NatOK' BY DEF TypeOK, NatOK
<1>3. SetOK' BY DEF TypeOK, SetOK
<1>4. ~scanDone /\ owner[p] = w /\ p \in bitmap /\ opened
  BY DEF TypeOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, SetOK
<1>5. \A r \in Rows : readCnt'[r] =
        IF opened /\ VisibleAt(r, snap) /\ started[owner[home[r]]] /\ home[r] \notin left'[owner[home[r]]]
        THEN 1 ELSE 0
  <2> SUFFICES ASSUME NEW r \in Rows
               PROVE readCnt'[r] =
                       IF opened /\ VisibleAt(r, snap) /\ started[owner[home[r]]]
                          /\ home[r] \notin left'[owner[home[r]]]
                       THEN 1 ELSE 0
    OBVIOUS
  <2>1. CASE home[r] = p /\ VisibleAt(r, snap)
    <3>1. insC[r] > 0 /\ ~gone[r] /\ alloc[p]
      BY <2>1, <1>4 DEF TypeOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, NatOK
    <3>2. readCnt[r] = 0
      BY <2>1, <1>4 DEF RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
    <3>. QED
      BY <2>1, <3>1, <3>2, <1>4 DEF TypeOK, SetOK
  <2>2. CASE home[r] = p /\ ~VisibleAt(r, snap)
    BY <2>2 DEF RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
  <2>3. CASE home[r] # p
    <3>1. readCnt'[r] = readCnt[r]
      BY <2>3
    <3>2. CASE opened /\ VisibleAt(r, snap)
      <4>1. home[r] \in bitmap
        BY <3>2 DEF RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
      <4>2. (home[r] \notin left'[owner[home[r]]]) = (home[r] \notin left[owner[home[r]]])
        BY <2>3, <4>1 DEF TypeOK, SetOK
      <4>. QED
        BY <3>1, <4>2 DEF RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
    <3>3. CASE ~(opened /\ VisibleAt(r, snap))
      BY <3>1, <3>3 DEF RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
    <3>. QED
      BY <3>2, <3>3
  <2>. QED
    BY <2>1, <2>2, <2>3
<1>6. R_early' /\ R_snap' /\ R_clock' /\ R_order' /\ R_home'
  BY DEF R_early, R_snap, R_clock, R_order, R_home, RestInv
<1>7. R_gone' /\ R_alloc' /\ R_vis' /\ R_open' /\ R_bitmap' /\ R_done'
  BY <1>4 DEF R_gone, R_alloc, R_vis, R_open, R_bitmap, R_done, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt
<1>8. R_start' /\ R_left'
  BY <1>4 DEF R_start, R_left, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, TypeOK, SetOK
<1>9. R_count'
  BY <1>4, <1>5 DEF R_count, VisibleAt
<1>10. RestInv'
  BY <1>6, <1>7, <1>8, <1>9 DEF RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
<1>. QED BY <1>1, <1>2, <1>3, <1>10 DEF TypeOK

LEMMA LInsert == ASSUME NEW r \in Rows, NEW p \in Pages PROVE IndInv /\ Insert(r, p) => IndInv'
<1> SUFFICES ASSUME TypeOK, RestInv, Insert(r, p) PROVE TypeOK' /\ RestInv'
  BY DEF IndInv
<1> USE DEF Insert
<1>1. BoolOK' BY DEF TypeOK, BoolOK
<1>2. NatOK' BY DEF TypeOK, NatOK
<1>3. SetOK' BY DEF TypeOK, SetOK
<1>4. insC[r] = 0 /\ delC[r] = 0 /\ home[r] = NoPage /\ readCnt[r] = 0 /\ clock > 0
  BY DEF RestInv, R_order, R_home, R_count, R_snap, TypeOK, NatOK, VisibleAt
<1>5. ~VisibleAt(r, snap)' /\ \A x \in Rows \ {r} : VisibleAt(x, snap)' = VisibleAt(x, snap)
  BY <1>4 DEF VisibleAt, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, R_snap, TypeOK, NatOK
<1>6. R_early' /\ R_snap' /\ R_clock' /\ R_order'
  BY <1>4 DEF R_early, R_snap, R_clock, R_order, RestInv, TypeOK, NatOK
<1>7. R_home' /\ R_gone' /\ R_alloc'
  BY <1>4 DEF R_home, R_gone, R_alloc, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, TypeOK, NatOK, BoolOK, SetOK
<1>8. R_vis' /\ R_open' /\ R_start' /\ R_left' /\ R_bitmap' /\ R_done'
  BY <1>4, <1>5 DEF R_vis, R_open, R_start, R_left, R_bitmap, R_done, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
<1>9. R_count'
  <2> SUFFICES ASSUME NEW x \in Rows
               PROVE readCnt[x] =
                       IF opened /\ VisibleAt(x, snap)' /\ started[owner[home'[x]]] /\ home'[x] \notin left[owner[home'[x]]]
                       THEN 1 ELSE 0
    BY DEF R_count
  <2>1. CASE x = r
    BY <2>1, <1>4, <1>5
  <2>2. CASE x # r
    BY <2>2, <1>5 DEF RestInv, R_count, TypeOK, SetOK
  <2>. QED
    BY <2>1, <2>2
<1>10. RestInv'
  BY <1>6, <1>7, <1>8, <1>9 DEF RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
<1>. QED BY <1>1, <1>2, <1>3, <1>10 DEF TypeOK

LEMMA LDelete == ASSUME NEW r \in Rows PROVE IndInv /\ Delete(r) => IndInv'
<1> SUFFICES ASSUME TypeOK, RestInv, Delete(r) PROVE TypeOK' /\ RestInv'
  BY DEF IndInv
<1> USE DEF Delete
<1>1. BoolOK' BY DEF TypeOK, BoolOK
<1>2. NatOK' BY DEF TypeOK, NatOK
<1>3. SetOK' BY DEF TypeOK, SetOK
<1>4. \A x \in Rows : VisibleAt(x, snap)' = VisibleAt(x, snap)
  BY DEF TypeOK, VisibleAt, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, NatOK
<1>5. RestInv'
  BY <1>4 DEF TypeOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, NatOK, BoolOK, SetOK
<1>. QED BY <1>1, <1>2, <1>3, <1>5 DEF TypeOK

LEMMA LVacuumRows == ASSUME NEW p \in Pages PROVE IndInv /\ VacuumRows(p) => IndInv'
<1> SUFFICES ASSUME TypeOK, RestInv, VacuumRows(p) PROVE TypeOK' /\ RestInv'
  BY DEF IndInv
<1> USE DEF VacuumRows
<1>1. BoolOK' BY DEF TypeOK, BoolOK
<1>2. NatOK' BY DEF TypeOK, NatOK
<1>3. SetOK' BY DEF TypeOK, SetOK
<1>4. \A r \in Rows : gone'[r] /\ ~gone[r] => ~VisibleAt(r, snap) \/ scanDone
  <2> SUFFICES ASSUME NEW r \in Rows, gone'[r], ~gone[r], ~scanDone PROVE ~VisibleAt(r, snap)
    OBVIOUS
  <2>1. delC[r] > 0 /\ delC[r] < OldestVisible
    BY DEF TypeOK, BoolOK
  <2>2. CASE snap > 0
    <3>1. OldestVisible = snap
      BY <2>2 DEF OldestVisible
    <3>. QED
      BY <2>1, <2>2, <3>1 DEF VisibleAt, TypeOK, NatOK
  <2>3. CASE snap = 0
    BY <2>3 DEF VisibleAt, TypeOK, NatOK
  <2>. QED
    BY <2>2, <2>3 DEF TypeOK, NatOK
<1>5. RestInv'
  BY <1>4 DEF TypeOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, NatOK, BoolOK, SetOK
<1>. QED BY <1>1, <1>2, <1>3, <1>5 DEF TypeOK

LEMMA LVacuumPage == ASSUME NEW p \in Pages PROVE IndInv /\ VacuumPage(p) => IndInv'
<1> SUFFICES ASSUME TypeOK, RestInv, VacuumPage(p) PROVE TypeOK' /\ RestInv'
  BY DEF IndInv
<1> USE DEF VacuumPage
<1>1. BoolOK' BY DEF TypeOK, BoolOK
<1>2. NatOK' BY DEF TypeOK, NatOK
<1>3. SetOK' BY DEF TypeOK, SetOK
<1>4. RestInv' BY DEF TypeOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, PageEmpty, VisibleAt, NatOK, BoolOK, SetOK
<1>. QED BY <1>1, <1>2, <1>3, <1>4 DEF TypeOK

\* ---- the INV1 premises ----
THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1>1. CASE Next
  BY <1>1, LTerminated, LTakeEarlySnapshot, LOpen, LFinish, LVacuumIdle, LStart, LReadPage, LInsert,
     LDelete, LVacuumRows, LVacuumPage DEF Next
<1>2. CASE UNCHANGED vars
  BY <1>2, LUnchanged
<1>. QED
  BY <1>1, <1>2

THEOREM InvSafe == IndInv => SameAsSnapshot
<1> SUFFICES ASSUME IndInv, scanDone, NEW r \in Rows
             PROVE readCnt[r] = IF VisibleAt(r, snap) THEN 1 ELSE 0
  BY DEF SameAsSnapshot
<1>1. opened /\ \A w \in Workers : started[w] /\ left[w] = {}
  BY DEF IndInv, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
<1>2. CASE VisibleAt(r, snap)
  <2>1. home[r] \in bitmap /\ owner[home[r]] \in Workers
    BY <1>1, <1>2 DEF IndInv, TypeOK, SetOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
  <2>. QED
    BY <1>1, <1>2, <2>1 DEF IndInv, TypeOK, SetOK, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
<1>3. CASE ~VisibleAt(r, snap)
  BY <1>3 DEF IndInv, RestInv, R_early, R_snap, R_clock, R_order, R_home, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done
<1>. QED
  BY <1>2, <1>3
=============================================================================
