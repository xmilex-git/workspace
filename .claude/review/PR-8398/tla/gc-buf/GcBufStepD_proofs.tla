---- MODULE GcBufStepD_proofs ----
(* IndInv /\ A => IndInv' for copies and the parallel scan: Coerce, StartPar, Restore, WMerge, OEnd, ErrEnd. *)
EXTENDS GcBufCap_proofs

THEOREM S_Coerce == ASSUME NEW n \in Nodes, NEW a \in Addr, IndInv, Coerce(n), CopyTo(n, a, Ctx(n), Ctx(n)) PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, Coerce, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_StartPar0 == ASSUME IndInv, StartPar, str["o"] = 0 PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, StartPar, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_StartParA == ASSUME NEW a \in Addr, IndInv, StartPar, str["o"] # 0, CopyTo("o", a, "h0", "coord") PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, StartPar, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_Restore0 == ASSUME IndInv, Restore, str["o"] = 0 PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, Restore, Rehome, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_RestoreA == ASSUME NEW a \in Addr, IndInv, Restore, str["o"] # 0, CopyTo("o", a, "coord", "h0") PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, Restore, Rehome, CopyTo, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_WMergeNone == ASSUME NEW w \in Workers, IndInv, WMerge(w), cnt[w] = 0 \/ size[w] = 0 PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_WMergeApp == ASSUME NEW w \in Workers, IndInv, WMerge(w), ~(cnt[w] = 0 \/ size[w] = 0), cnt["o"] > 0 PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, WMerge, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_WMergeClone == ASSUME NEW w \in Workers, NEW a \in Addr, IndInv, WMerge(w), ~(cnt[w] = 0 \/ size[w] = 0), ~(cnt["o"] > 0), CloneAt(w, a) PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, WMerge, CloneAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_OEnd == ASSUME IndInv, OEnd PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, OEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_ErrEnd == ASSUME IndInv, ErrEnd PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, ErrEnd, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv
====
