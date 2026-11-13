---- MODULE GcBufStepA_proofs ----
(* IndInv /\ A => IndInv' for the actions that allocate nothing: OInit, MergeDone, WRun,
   WClear, ExtFree, Terminating and the stuttering step. *)
EXTENDS GcBufCap_proofs

THEOREM S_OInit == ASSUME IndInv, OInit PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, OInit, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_MergeDone == ASSUME IndInv, MergeDone PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, MergeDone, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_WRun == ASSUME NEW w \in Workers, IndInv, WRun(w) PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, WRun, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_WClear == ASSUME NEW w \in Workers, IndInv, WClear(w) PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, WClear, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_ExtFree == ASSUME NEW a \in Addr, IndInv, ExtFreeA(a) PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, ExtFreeA, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_Term == ASSUME IndInv, Terminating PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, Terminating, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_Stutter == ASSUME IndInv, UNCHANGED vars PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, vars, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv
====
