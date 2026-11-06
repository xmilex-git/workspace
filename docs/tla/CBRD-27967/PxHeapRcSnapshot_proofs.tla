---------------------- MODULE PxHeapRcSnapshot_proofs ----------------------
(* TLAPS proof that IndInv is an inductive invariant of the fix (the snapshot
   exists before any bitmap is collected, and every build is one test-and-build
   step) and that it implies C1 (SameAsSnapshot), C2 (SnapshotStable) and C4
   (WorkerReuses), for statements without a nested statement (~Nested) and
   any number of scans, workers, pages and rows: the premises of the TLA rule
   INV1 (cubrid-tla PROOFS.md). One lemma per action; within it each typing part
   and each conjunct of IndInv is its own step (cubrid-tla P4, P15). *)
EXTENDS PxHeapRcSnapshot, TLAPS
\* timeout: 3600

\* the fix variants: SnapshotAt = "collect" with the leader's build under the mutex,
\* SnapshotAt = "query_start", or REPEATABLE READ; OtherPx either way
ASSUME Fix == CollectNeedsSnap /\ (~LeaderLock => ~LeaderBuilds) /\ Mutant = "none" /\ ~Nested

USE Assm, Fix DEF Rows, Pages, RIdx, PIdx, NoPage

LEMMA RowFacts == \A r \in Rows : r = <<r[1], r[2]>> /\ r[1] \in Scans /\ r[2] \in RIdx
  OBVIOUS
LEMMA PageFacts == \A pg \in Pages : pg = <<pg[1], pg[2]>> /\ pg[1] \in Scans /\ pg[2] \in PIdx
  OBVIOUS

\* ---- Init ----
THEOREM InitInv == Init => IndInv
<1> SUFFICES ASSUME Init PROVE IndInv
  OBVIOUS
<1>1. BoolOK BY DEF Init, BoolOK
<1>2. NatOK BY RowFacts DEF Init, NatOK, IsInit
<1>3. SetOK BY DEF Init, SetOK
<1>4. R_fix BY DEF R_fix

<1>5. R_snap BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_snap, VisibleAt, IsInit, Page, AllDone
<1>6. R_q BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_q, VisibleAt, IsInit, Page, AllDone
<1>7. R_lsnap BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_lsnap, VisibleAt, IsInit, Page, AllDone
<1>8. R_clock BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_clock, VisibleAt, IsInit, Page, AllDone
<1>9. R_order BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_order, VisibleAt, IsInit, Page, AllDone
<1>10. R_home BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_home, VisibleAt, IsInit, Page, AllDone
<1>11. R_init BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_init, VisibleAt, IsInit, Page, AllDone
<1>12. R_gone BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_gone, VisibleAt, IsInit, Page, AllDone
<1>13. R_alloc BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_alloc, VisibleAt, IsInit, Page, AllDone
<1>14. R_vis BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_vis, VisibleAt, IsInit, Page, AllDone
<1>15. R_open BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_open, VisibleAt, IsInit, Page, AllDone
<1>16. R_start BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_start, VisibleAt, IsInit, Page, AllDone
<1>17. R_left BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_left, VisibleAt, IsInit, Page, AllDone
<1>18. R_bitmap BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_bitmap, VisibleAt, IsInit, Page, AllDone
<1>19. R_count BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_count, VisibleAt, IsInit, Page, AllDone
<1>20. R_done BY <1>1, <1>2, <1>3, RowFacts DEF Init, TypeOK, BoolOK, NatOK, SetOK, R_done, VisibleAt, IsInit, Page, AllDone
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LTerminated == IndInv /\ Terminated => IndInv'
<1> SUFFICES ASSUME IndInv, Terminated PROVE IndInv'
  OBVIOUS
<1>1. BoolOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>2. NatOK' BY RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>3. SetOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>13. R_alloc' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>14. R_vis' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>16. R_start' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>18. R_bitmap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>19. R_count' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars, dataVars, scanVars, Terminated
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LUnchanged == IndInv /\ UNCHANGED vars => IndInv'
<1> SUFFICES ASSUME IndInv, UNCHANGED vars PROVE IndInv'
  OBVIOUS
<1>1. TypeOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars

<1>2. R_fix' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>3. R_snap' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>4. R_q' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>5. R_lsnap' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>6. R_clock' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>7. R_order' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>8. R_home' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>9. R_init' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>10. R_gone' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>11. R_alloc' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>12. R_vis' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>13. R_open' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>14. R_start' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>15. R_left' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>16. R_bitmap' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>17. R_count' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>18. R_done' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, vars
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18 DEF IndInv

LEMMA LQueryStart == IndInv /\ QueryStart => IndInv'
<1> SUFFICES ASSUME IndInv, QueryStart PROVE IndInv'
  OBVIOUS
<1>1. BoolOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>2. NatOK' BY RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>3. SetOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>13. R_alloc' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>14. R_vis' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>16. R_start' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>18. R_bitmap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>19. R_count' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, QueryStart
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LLeaderSnap == ASSUME NEW s \in Scans PROVE IndInv /\ LeaderSnap(s) => IndInv'
<1> SUFFICES ASSUME IndInv, LeaderSnap(s) PROVE IndInv'
  OBVIOUS
<1>1. BoolOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>2. NatOK' BY RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>3. SetOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>13. R_alloc' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>14. R_vis' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>16. R_start' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>18. R_bitmap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>19. R_count' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, LeaderSnap
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LOtherBuild == IndInv /\ OtherBuild => IndInv'
<1> SUFFICES ASSUME IndInv, OtherBuild PROVE IndInv'
  OBVIOUS
<1>1. BoolOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>2. NatOK' BY RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>3. SetOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>13. R_alloc' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>14. R_vis' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>16. R_start' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>18. R_bitmap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>19. R_count' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, scanVars, OtherBuild
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LLeaderTest == ASSUME NEW s \in Scans PROVE IndInv /\ LeaderTest(s) => IndInv'
<1> SUFFICES ASSUME IndInv, LeaderTest(s) PROVE IndInv'
  OBVIOUS
<1>1. BoolOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>2. NatOK' BY RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>3. SetOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>13. R_alloc' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>14. R_vis' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>16. R_start' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>18. R_bitmap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>19. R_count' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderBuilds, LeaderTest
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LLeaderWrite == ASSUME NEW s \in Scans PROVE IndInv /\ LeaderWrite(s) => IndInv'
<1> SUFFICES ASSUME IndInv, LeaderWrite(s) PROVE IndInv'
  OBVIOUS
<1>1. BoolOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>2. NatOK' BY RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>3. SetOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>13. R_alloc' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>14. R_vis' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>16. R_start' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>18. R_bitmap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>19. R_count' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, LeaderWrite
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LCollect == ASSUME NEW s \in Scans PROVE IndInv /\ Collect(s) => IndInv'
<1> SUFFICES ASSUME IndInv, Collect(s) PROVE IndInv'
  OBVIOUS
<1>1. BoolOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>2. NatOK' BY RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>3. SetOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>13. R_alloc' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>14. R_vis' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>16. R_start'
  <2>1. started' = started /\ left' = left
    BY DEF Collect
  <2>2. \A x \in Scans : opened[x] => opened'[x]
    BY DEF Collect, IndInv, TypeOK, BoolOK
  <2>. QED BY <2>1, <2>2 DEF IndInv, R_start
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>18. R_bitmap'
  <2> SUFFICES ASSUME NEW r \in Rows, opened'[r[1]], VisibleAt(r, snap)' PROVE home'[r] \in bitmap'[r[1]]
    BY DEF R_bitmap
  <2>1. snap' = snap /\ home' = home /\ insC' = insC /\ delC' = delC /\ alloc' = alloc /\ gone' = gone
    BY DEF Collect, dataVars
  <2>2. VisibleAt(r, snap)
    BY <2>1 DEF VisibleAt
  <2>3. CASE r[1] = s
    <3>1. ~opened[s] /\ ~done[s]
      BY DEF Collect, IndInv, R_open
    <3>2. insC[r] > 0 /\ home[r] # NoPage /\ ~gone[r]
      BY <2>2, <2>3, <3>1 DEF IndInv, R_home, R_vis, VisibleAt
    <3>3. alloc[<<s, home[r]>>] /\ home[r] \in PIdx
      BY <2>3, <3>2, RowFacts DEF IndInv, R_alloc, Page, TypeOK, NatOK
    <3>4. bitmap'[s] = {i \in PIdx : alloc[<<s, i>>]}
      BY DEF Collect, IndInv, TypeOK, SetOK
    <3>. QED BY <2>1, <2>3, <3>3, <3>4
  <2>4. CASE r[1] # s
    <3>1. opened[r[1]] /\ bitmap'[r[1]] = bitmap[r[1]]
      BY <2>4, RowFacts DEF Collect, IndInv, TypeOK, BoolOK, SetOK
    <3>. QED BY <2>1, <2>2, <3>1 DEF IndInv, R_bitmap
  <2>. QED BY <2>3, <2>4
<1>19. R_count'
  <2> SUFFICES ASSUME NEW r \in Rows
               PROVE readCnt'[r] = IF opened'[r[1]] /\ VisibleAt(r, snap)' /\ started'[r[1]][owner'[r[1]][home'[r]]]
                                       /\ home'[r] \notin left'[r[1]][owner'[r[1]][home'[r]]]
                                    THEN 1 ELSE 0
    BY DEF R_count
  <2>1. snap' = snap /\ home' = home /\ insC' = insC /\ delC' = delC /\ readCnt' = readCnt
        /\ started' = started /\ left' = left
    BY DEF Collect, dataVars
  <2>2. CASE r[1] = s
    <3>1. ~opened[s] /\ \A x \in Workers : ~started[s][x]
      BY DEF Collect, IndInv, R_start
    <3>2. readCnt[r] = 0
      BY <2>2, <3>1 DEF IndInv, R_count
    <3>3. owner'[s][home[r]] \in Workers \/ home[r] = NoPage
      <4>0. PICK o \in [PIdx -> Workers] : owner' = [owner EXCEPT ![s] = o]
        BY DEF Collect
      <4>1. owner'[s] \in [PIdx -> Workers]
        BY <4>0 DEF IndInv, TypeOK, SetOK
      <4>2. home[r] \in 0..NPages
        BY RowFacts DEF IndInv, TypeOK, NatOK
      <4>. QED BY <4>1, <4>2
    <3>4. CASE home[r] = NoPage
      <4>1. ~VisibleAt(r, snap)
        BY <3>4 DEF IndInv, R_home, VisibleAt
      <4>. QED BY <2>1, <3>2, <4>1 DEF VisibleAt
    <3>5. CASE owner'[s][home[r]] \in Workers
      BY <2>1, <2>2, <3>1, <3>2, <3>5
    <3>. QED BY <3>3, <3>4, <3>5
  <2>3. CASE r[1] # s
    <3>1. opened'[r[1]] = opened[r[1]] /\ owner'[r[1]] = owner[r[1]]
      BY <2>3, RowFacts DEF Collect, IndInv, TypeOK, BoolOK, SetOK
    <3>. QED BY <2>1, <3>1 DEF IndInv, R_count, VisibleAt
  <2>. QED BY <2>2, <2>3
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Collect
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LStart == ASSUME NEW s \in Scans, NEW w \in Workers PROVE IndInv /\ Start(s, w) => IndInv'
<1> SUFFICES ASSUME IndInv, Start(s, w) PROVE IndInv'
  OBVIOUS
<1>1. BoolOK'
  <2>1. started' = [started EXCEPT ![s] = [started[s] EXCEPT ![w] = TRUE]]
    BY DEF Start
  <2>2. [started[s] EXCEPT ![w] = TRUE] \in [Workers -> BOOLEAN]
    BY DEF IndInv, TypeOK, BoolOK
  <2>3. started' \in [Scans -> [Workers -> BOOLEAN]]
    BY <2>1, <2>2 DEF IndInv, TypeOK, BoolOK
  <2>4. UNCHANGED <<alloc, gone, qstarted, otherDone, opened, done>>
    BY DEF Start, dataVars
  <2>. QED BY <2>3, <2>4 DEF IndInv, TypeOK, BoolOK
<1>2. NatOK' BY RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>3. SetOK'
  <2>1. left' = [left EXCEPT ![s] = [left[s] EXCEPT ![w] = {i \in bitmap[s] : owner[s][i] = w}]]
    BY DEF Start
  <2>2. {i \in bitmap[s] : owner[s][i] = w} \in SUBSET PIdx
    BY DEF IndInv, TypeOK, SetOK
  <2>3. [left[s] EXCEPT ![w] = {i \in bitmap[s] : owner[s][i] = w}] \in [Workers -> SUBSET PIdx]
    BY <2>2 DEF IndInv, TypeOK, SetOK
  <2>4. left' \in [Scans -> [Workers -> SUBSET PIdx]]
    BY <2>1, <2>3 DEF IndInv, TypeOK, SetOK
  <2>5. UNCHANGED <<lsnap, bitmap, owner>>
    BY DEF Start
  <2>. QED BY <2>4, <2>5 DEF IndInv, TypeOK, SetOK
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>13. R_alloc' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>14. R_vis' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>16. R_start' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>18. R_bitmap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>19. R_count'
  <2> SUFFICES ASSUME NEW r \in Rows
               PROVE readCnt'[r] = IF opened'[r[1]] /\ VisibleAt(r, snap)' /\ started'[r[1]][owner'[r[1]][home'[r]]]
                                       /\ home'[r] \notin left'[r[1]][owner'[r[1]][home'[r]]]
                                    THEN 1 ELSE 0
    BY DEF R_count
  <2>0. snap > 0
    BY DEF Start, IndInv, R_snap
  <2>1. snap' = snap /\ home' = home /\ insC' = insC /\ delC' = delC /\ readCnt' = readCnt
        /\ opened' = opened /\ owner' = owner
    BY <2>0 DEF Start, dataVars, Build
  <2>2. CASE r[1] = s /\ opened[s] /\ VisibleAt(r, snap) /\ owner[s][home[r]] = w
    <3>1. home[r] \in bitmap[s]
      BY <2>2 DEF IndInv, R_bitmap
    <3>2. home[r] \in left'[s][w]
      BY <2>2, <3>1 DEF Start, IndInv, TypeOK, SetOK
    <3>3. ~started[s][w]
      BY DEF Start
    <3>4. readCnt[r] = 0
      BY <2>2, <3>3 DEF IndInv, R_count
    <3>. QED BY <2>1, <2>2, <3>2, <3>4
  <2>3. CASE ~(r[1] = s /\ opened[s] /\ VisibleAt(r, snap) /\ owner[s][home[r]] = w)
    <3>1. CASE r[1] # s
      <4>1. started'[r[1]] = started[r[1]] /\ left'[r[1]] = left[r[1]]
        BY <3>1, RowFacts DEF Start, IndInv, TypeOK, BoolOK, SetOK
      <4>. QED BY <2>1, <4>1 DEF IndInv, R_count, VisibleAt
    <3>2. CASE r[1] = s /\ ~(opened[s] /\ VisibleAt(r, snap))
      BY <2>1, <3>2 DEF IndInv, R_count, VisibleAt
    <3>3. CASE r[1] = s /\ opened[s] /\ VisibleAt(r, snap) /\ owner[s][home[r]] # w
      <4>1. home[r] \in PIdx
        BY <3>3, RowFacts DEF IndInv, R_home, VisibleAt, TypeOK, NatOK
      <4>2. owner[s][home[r]] \in Workers
        BY <4>1 DEF IndInv, TypeOK, SetOK
      <4>3. started'[s][owner[s][home[r]]] = started[s][owner[s][home[r]]]
             /\ left'[s][owner[s][home[r]]] = left[s][owner[s][home[r]]]
        BY <3>3, <4>2 DEF Start, IndInv, TypeOK, BoolOK, SetOK
      <4>. QED BY <2>1, <3>3, <4>3 DEF IndInv, R_count, VisibleAt
    <3>. QED BY <2>3, <3>1, <3>2, <3>3
  <2>. QED BY <2>2, <2>3
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Start
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LReadPage == ASSUME NEW s \in Scans, NEW w \in Workers, NEW i \in PIdx PROVE IndInv /\ ReadPage(s, w, i) => IndInv'
<1> SUFFICES ASSUME IndInv, ReadPage(s, w, i) PROVE IndInv'
  OBVIOUS
<1>1. BoolOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>2. NatOK' BY RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>3. SetOK'
  <2>1. left' = [left EXCEPT ![s] = [left[s] EXCEPT ![w] = left[s][w] \ {i}]]
    BY DEF ReadPage
  <2>2. [left[s] EXCEPT ![w] = left[s][w] \ {i}] \in [Workers -> SUBSET PIdx]
    BY DEF IndInv, TypeOK, SetOK
  <2>3. left' \in [Scans -> [Workers -> SUBSET PIdx]]
    BY <2>1, <2>2 DEF IndInv, TypeOK, SetOK
  <2>4. UNCHANGED <<lsnap, bitmap, owner>>
    BY DEF ReadPage
  <2>. QED BY <2>3, <2>4 DEF IndInv, TypeOK, SetOK
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>13. R_alloc' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>14. R_vis' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>16. R_start' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>18. R_bitmap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>19. R_count'
  <2> SUFFICES ASSUME NEW r \in Rows
               PROVE readCnt'[r] = IF opened'[r[1]] /\ VisibleAt(r, snap)' /\ started'[r[1]][owner'[r[1]][home'[r]]]
                                       /\ home'[r] \notin left'[r[1]][owner'[r[1]][home'[r]]]
                                    THEN 1 ELSE 0
    BY DEF R_count
  <2>1. snap' = snap /\ home' = home /\ insC' = insC /\ delC' = delC /\ alloc' = alloc /\ gone' = gone
        /\ opened' = opened /\ owner' = owner /\ started' = started
    BY DEF ReadPage, dataVars
  <2>2. started[s][w] /\ i \in left[s][w] /\ i \in bitmap[s] /\ owner[s][i] = w /\ opened[s] /\ ~done[s]
    BY DEF ReadPage, IndInv, R_left, R_start, R_done
  <2>3. CASE r[1] = s /\ home[r] = i /\ VisibleAt(r, snap)
    <3>1. ~gone[r] /\ alloc[<<s, i>>]
      BY <2>2, <2>3, RowFacts DEF IndInv, R_vis, R_alloc, R_home, VisibleAt, Page
    <3>2. readCnt[r] = 0
      BY <2>2, <2>3 DEF IndInv, R_count
    <3>3. readCnt'[r] = readCnt[r] + 1
      BY <2>3, <3>1 DEF ReadPage
    <3>4. i \notin left'[s][w]
      BY <2>2 DEF ReadPage, IndInv, TypeOK, SetOK
    <3>5. opened'[r[1]] /\ VisibleAt(r, snap)' /\ started'[r[1]][owner'[r[1]][home'[r]]]
          /\ home'[r] \notin left'[r[1]][owner'[r[1]][home'[r]]]
      BY <2>1, <2>2, <2>3, <3>4 DEF VisibleAt
    <3>6. readCnt'[r] = 1
      BY <3>2, <3>3
    <3>. QED BY <3>5, <3>6
  <2>4. CASE r[1] = s /\ home[r] = i /\ ~VisibleAt(r, snap)
    <3>1. readCnt'[r] = readCnt[r]
      BY <2>4 DEF ReadPage
    <3>. QED BY <2>1, <2>4, <3>1 DEF IndInv, R_count, VisibleAt
  <2>5. CASE ~(r[1] = s /\ home[r] = i)
    <3>1. readCnt'[r] = readCnt[r]
      BY <2>5 DEF ReadPage
    <3>2. CASE opened[r[1]] /\ VisibleAt(r, snap)
      <4>1. home[r] \in bitmap[r[1]] /\ home[r] \in PIdx
        BY <3>2, RowFacts DEF IndInv, R_bitmap, TypeOK, SetOK
      <4>2. owner[r[1]][home[r]] \in Workers
        BY <4>1, RowFacts DEF IndInv, TypeOK, SetOK
      <4>3. (home[r] \in left'[r[1]][owner[r[1]][home[r]]]) = (home[r] \in left[r[1]][owner[r[1]][home[r]]])
        BY <2>5, <4>1, <4>2, RowFacts DEF ReadPage, IndInv, TypeOK, SetOK
      <4>. QED BY <2>1, <3>1, <4>3 DEF IndInv, R_count, VisibleAt
    <3>3. CASE ~(opened[r[1]] /\ VisibleAt(r, snap))
      BY <2>1, <3>1, <3>3 DEF IndInv, R_count, VisibleAt
    <3>. QED BY <3>2, <3>3
  <2>. QED BY <2>3, <2>4, <2>5
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, ReadPage
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LFinish == ASSUME NEW s \in Scans PROVE IndInv /\ Finish(s) => IndInv'
<1> SUFFICES ASSUME IndInv, Finish(s) PROVE IndInv'
  OBVIOUS
<1>1. BoolOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>2. NatOK' BY RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>3. SetOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>13. R_alloc' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>14. R_vis' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>16. R_start' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>18. R_bitmap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>19. R_count' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, dataVars, Finish
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LInsert == ASSUME NEW r \in Rows, NEW i \in PIdx PROVE IndInv /\ Insert(r, i) => IndInv'
<1> SUFFICES ASSUME IndInv, Insert(r, i) PROVE IndInv'
  OBVIOUS
<1>1. BoolOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>2. NatOK' BY RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>3. SetOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>13. R_alloc' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>14. R_vis' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>16. R_start' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>18. R_bitmap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>19. R_count'
  <2> SUFFICES ASSUME NEW x \in Rows
               PROVE readCnt'[x] = IF opened'[x[1]] /\ VisibleAt(x, snap)' /\ started'[x[1]][owner'[x[1]][home'[x]]]
                                       /\ home'[x] \notin left'[x[1]][owner'[x[1]][home'[x]]]
                                    THEN 1 ELSE 0
    BY DEF R_count
  <2>1. insC[r] = 0 /\ readCnt[r] = 0 /\ snap <= clock
    BY DEF Insert, IndInv, R_count, R_snap, VisibleAt
  <2>2. CASE x = r
    <3>1. ~VisibleAt(r, snap)'
      BY <2>1 DEF Insert, VisibleAt, IndInv, TypeOK, NatOK
    <3>. QED BY <2>1, <2>2, <3>1 DEF Insert
  <2>3. CASE x # r
    <3>1. VisibleAt(x, snap)' = VisibleAt(x, snap) /\ home'[x] = home[x] /\ readCnt'[x] = readCnt[x]
      BY <2>3 DEF Insert, VisibleAt, IndInv, TypeOK, BoolOK, NatOK
    <3>2. opened' = opened /\ started' = started /\ left' = left /\ owner' = owner /\ snap' = snap
      BY DEF Insert, scanVars
    <3>. QED BY <3>1, <3>2 DEF IndInv, R_count
  <2>. QED BY <2>2, <2>3
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, Insert
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LDelete == ASSUME NEW r \in Rows PROVE IndInv /\ Delete(r) => IndInv'
<1> SUFFICES ASSUME IndInv, Delete(r) PROVE IndInv'
  OBVIOUS
<1>0. /\ delC' = [delC EXCEPT ![r] = clock] /\ clock' = clock + 1 /\ insC[r] > 0 /\ delC[r] = 0
      /\ UNCHANGED <<alloc, home, insC, gone, readCnt, snap, rounds, qstarted, otherDone>>
      /\ UNCHANGED <<lsnap, opened, bitmap, owner, started, left, done>>
  BY DEF Delete, scanVars
<1>v. \A x \in Rows : VisibleAt(x, snap)' = VisibleAt(x, snap)
  <2> SUFFICES ASSUME NEW x \in Rows PROVE VisibleAt(x, snap)' = VisibleAt(x, snap)
    OBVIOUS
  <2>1. CASE x = r
    BY <1>0, <2>1 DEF VisibleAt, IndInv, TypeOK, NatOK, R_snap
  <2>2. CASE x # r
    BY <1>0, <2>2 DEF VisibleAt, IndInv, TypeOK, NatOK
  <2>. QED BY <2>1, <2>2
<1>1. BoolOK' BY <1>0 DEF IndInv, TypeOK, BoolOK
<1>2. NatOK' BY <1>0 DEF IndInv, TypeOK, NatOK
<1>3. SetOK' BY <1>0 DEF IndInv, TypeOK, SetOK
<1>4. R_fix' BY <1>0, <1>v DEF IndInv, R_fix
<1>5. R_snap' BY <1>0, <1>v DEF IndInv, R_snap, TypeOK, NatOK, BoolOK
<1>6. R_q' BY <1>0, <1>v DEF IndInv, R_q
<1>7. R_lsnap' BY <1>0, <1>v DEF IndInv, R_lsnap
<1>8. R_clock' BY <1>0, <1>v DEF IndInv, R_clock, TypeOK, NatOK, BoolOK
<1>9. R_order' BY <1>0, <1>v DEF IndInv, R_order, R_clock, TypeOK, NatOK, BoolOK
<1>10. R_home' BY <1>0, <1>v DEF IndInv, R_home, TypeOK, NatOK, BoolOK
<1>11. R_init' BY <1>0, <1>v DEF IndInv, R_init, TypeOK, NatOK, BoolOK
<1>12. R_gone' BY <1>0, <1>v DEF IndInv, R_gone, TypeOK, NatOK, BoolOK
<1>13. R_alloc' BY <1>0, <1>v DEF IndInv, R_alloc, Page
<1>14. R_vis' BY <1>0, <1>v DEF IndInv, R_vis
<1>15. R_open' BY <1>0, <1>v DEF IndInv, R_open
<1>16. R_start' BY <1>0, <1>v DEF IndInv, R_start
<1>17. R_left' BY <1>0, <1>v DEF IndInv, R_left
<1>18. R_bitmap' BY <1>0, <1>v DEF IndInv, R_bitmap
<1>19. R_count' BY <1>0, <1>v DEF IndInv, R_count
<1>20. R_done' BY <1>0, <1>v DEF IndInv, R_done
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LVacuumRows == ASSUME NEW pg \in Pages PROVE IndInv /\ VacuumRows(pg) => IndInv'
<1> SUFFICES ASSUME IndInv, VacuumRows(pg) PROVE IndInv'
  OBVIOUS
<1>1. BoolOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>2. NatOK'
  <2>1. rounds > 0 /\ rounds' = rounds - 1
    BY DEF VacuumRows
  <2>2. UNCHANGED <<home, insC, delC, readCnt, clock, snap>>
    BY DEF VacuumRows, scanVars
  <2>. QED BY <2>1, <2>2 DEF IndInv, TypeOK, NatOK
<1>3. SetOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>13. R_alloc' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>14. R_vis'
  <2> SUFFICES ASSUME NEW r \in Rows, VisibleAt(r, snap)', ~done'[r[1]] PROVE ~gone'[r]
    BY DEF R_vis
  <2>1. snap' = snap /\ insC' = insC /\ delC' = delC /\ done' = done
    BY DEF VacuumRows, scanVars
  <2>2. ~gone[r] /\ VisibleAt(r, snap)
    BY <2>1 DEF IndInv, R_vis, VisibleAt
  <2>3. snap > 0
    BY <2>2 DEF VisibleAt, IndInv, TypeOK, NatOK
  <2>4. r[1] \in Scans /\ ~done[r[1]]
    BY <2>1, RowFacts
  <2>5. ~AllDone
    BY <2>4 DEF AllDone
  <2>6. OldestVisible = snap
    BY <2>3, <2>5 DEF OldestVisible
  <2>. QED BY <2>2, <2>6 DEF VacuumRows, VisibleAt
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>16. R_start' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>18. R_bitmap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>19. R_count' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, OldestVisible, VacuumRows
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LVacuumPage == ASSUME NEW pg \in Pages PROVE IndInv /\ VacuumPage(pg) => IndInv'
<1> SUFFICES ASSUME IndInv, VacuumPage(pg) PROVE IndInv'
  OBVIOUS
<1>1. BoolOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>2. NatOK'
  <2>1. rounds > 0 /\ rounds' = rounds - 1
    BY DEF VacuumPage
  <2>2. UNCHANGED <<home, insC, delC, readCnt, clock, snap>>
    BY DEF VacuumPage, scanVars
  <2>. QED BY <2>1, <2>2 DEF IndInv, TypeOK, NatOK
<1>3. SetOK' BY DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>4. R_fix' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>5. R_snap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>6. R_q' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>7. R_lsnap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>8. R_clock' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>9. R_order' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>10. R_home' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>11. R_init' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>12. R_gone' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>13. R_alloc'
  <2> SUFFICES ASSUME NEW r \in Rows, home'[r] # NoPage, ~gone'[r] PROVE alloc'[Page(r)']
    BY DEF R_alloc
  <2>1. home' = home /\ gone' = gone /\ alloc' = [alloc EXCEPT ![pg] = FALSE] /\ PageEmpty(pg)
    BY DEF VacuumPage
  <2>2. alloc[Page(r)]
    BY <2>1 DEF IndInv, R_alloc
  <2>3. Page(r) \in Pages /\ Page(r)' = Page(r)
    BY <2>1, RowFacts DEF IndInv, TypeOK, NatOK, Page
  <2>4. Page(r) # pg
    <3>1. CASE Page(r) = pg
      <4>1. r[1] = pg[1] /\ home[r] = pg[2]
        BY <3>1, PageFacts DEF Page
      <4>2. gone[r]
        BY <2>1, <4>1 DEF PageEmpty
      <4>. QED BY <2>1, <4>2
    <3>. QED BY <3>1
  <2>. QED BY <2>1, <2>2, <2>3, <2>4 DEF IndInv, TypeOK, BoolOK
<1>14. R_vis' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>15. R_open' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>16. R_start' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>17. R_left' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>18. R_bitmap' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>19. R_count' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>20. R_done' BY <1>1, <1>2, <1>3, RowFacts, PageFacts DEF IndInv, TypeOK, BoolOK, NatOK, SetOK, R_fix, R_snap, R_q, R_lsnap, R_clock, R_order, R_home, R_init, R_gone, R_alloc, R_vis, R_open, R_start, R_left, R_bitmap, R_count, R_done, VisibleAt, Build, IsInit, Page, AllDone, scanVars, PageEmpty, VacuumPage
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA LNested == IndInv /\ NestedInvalidate => IndInv'
  BY DEF NestedInvalidate


\* ---- the INV1 premises ----
THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1>1. CASE Terminated BY <1>1, LTerminated
<1>2. CASE QueryStart BY <1>2, LQueryStart
<1>3. CASE \E s \in Scans : LeaderSnap(s) \/ LeaderTest(s) \/ LeaderWrite(s) \/ Collect(s) \/ Finish(s)
  BY <1>3, LLeaderSnap, LLeaderTest, LLeaderWrite, LCollect, LFinish
<1>4. CASE \E s \in Scans, w \in Workers : Start(s, w) \/ \E i \in PIdx : ReadPage(s, w, i)
  BY <1>4, LStart, LReadPage
<1>5. CASE OtherBuild BY <1>5, LOtherBuild
<1>6. CASE \E r \in Rows, i \in PIdx : Insert(r, i) BY <1>6, LInsert
<1>7. CASE \E r \in Rows : Delete(r) BY <1>7, LDelete
<1>8. CASE \E pg \in Pages : VacuumRows(pg) \/ VacuumPage(pg) BY <1>8, LVacuumRows, LVacuumPage
<1>9. CASE UNCHANGED vars BY <1>9, LUnchanged
<1>10. CASE NestedInvalidate BY <1>10, LNested
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10 DEF Next, ScanStep

THEOREM Safe == Spec => []IndInv
  BY InitInv, StepInv, PTL DEF Spec

\* C1
THEOREM InvSafe == IndInv => SameAsSnapshot
<1> SUFFICES ASSUME IndInv, NEW s \in Scans, done[s], NEW r \in Rows, r[1] = s
             PROVE readCnt[r] = IF VisibleAt(r, snap) THEN 1 ELSE 0
  BY DEF SameAsSnapshot
<1>1. opened[s] /\ \A x \in Workers : started[s][x] /\ left[s][x] = {}
  BY DEF IndInv, R_open, R_done
<1>2. CASE VisibleAt(r, snap)
  <2>1. home[r] \in bitmap[s] /\ home[r] \in PIdx
    BY <1>1, <1>2 DEF IndInv, R_bitmap, TypeOK, SetOK
  <2>2. owner[s][home[r]] \in Workers
    BY <2>1 DEF IndInv, TypeOK, SetOK
  <2>. QED BY <1>1, <1>2, <2>1, <2>2 DEF IndInv, R_count
<1>3. CASE ~VisibleAt(r, snap)
  BY <1>3 DEF IndInv, R_count
<1>. QED BY <1>2, <1>3

\* C2: every step keeps a built snapshot
THEOREM StepStable == IndInv /\ [Next]_vars => [snap # 0 => snap' = snap]_vars
<1> SUFFICES ASSUME IndInv, [Next]_vars, snap # 0 PROVE snap' = snap
  OBVIOUS
<1> USE DEF IndInv, Build
<1>1. CASE Terminated BY <1>1 DEF Terminated, vars
<1>2. CASE QueryStart BY <1>2 DEF QueryStart
<1>3. CASE \E s \in Scans : LeaderSnap(s) \/ LeaderTest(s) \/ LeaderWrite(s) \/ Collect(s) \/ Finish(s)
  <2> PICK s \in Scans : LeaderSnap(s) \/ LeaderTest(s) \/ LeaderWrite(s) \/ Collect(s) \/ Finish(s)
    BY <1>3
  <2>1. ~LeaderWrite(s)
    BY DEF LeaderWrite, R_lsnap
  <2>. QED BY <2>1 DEF LeaderSnap, LeaderTest, Collect, Finish
<1>4. CASE \E s \in Scans, w \in Workers : Start(s, w) \/ \E i \in PIdx : ReadPage(s, w, i)
  BY <1>4 DEF Start, ReadPage
<1>5. CASE OtherBuild BY <1>5 DEF OtherBuild
<1>6. CASE \E r \in Rows, i \in PIdx : Insert(r, i) BY <1>6 DEF Insert
<1>7. CASE \E r \in Rows : Delete(r) BY <1>7 DEF Delete
<1>8. CASE \E pg \in Pages : VacuumRows(pg) \/ VacuumPage(pg) BY <1>8 DEF VacuumRows, VacuumPage
<1>9. CASE UNCHANGED vars BY <1>9 DEF vars
<1>10. CASE NestedInvalidate BY <1>10 DEF NestedInvalidate
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10 DEF Next, ScanStep

\* C4: a heap worker reuses the snapshot the leader built
THEOREM StepReuse == IndInv /\ [Next]_vars => [\A s \in Scans, w \in Workers : Start(s, w) => snap # 0]_vars
  BY DEF IndInv, TypeOK, NatOK, R_snap, Start

THEOREM ReuseSafe == Spec => WorkerReuses
<1>1. IndInv /\ [Next]_vars => [\A s \in Scans, w \in Workers : Start(s, w) => snap # 0]_vars
  BY StepReuse
<1>. QED BY <1>1, Safe, PTL DEF Spec, WorkerReuses

THEOREM StableSafe == Spec => SnapshotStable
<1>1. IndInv /\ [Next]_vars => [snap # 0 => snap' = snap]_vars
  BY StepStable
<1>. QED BY <1>1, Safe, PTL DEF Spec, SnapshotStable
=============================================================================
