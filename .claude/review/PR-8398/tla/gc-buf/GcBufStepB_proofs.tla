---- MODULE GcBufStepB_proofs ----
(* IndInv /\ A => IndInv' for rows and the appends that do not grow: RowStart, AFull, AChar, AIn, AFail. *)
EXTENDS GcBufCap_proofs

THEOREM S_RowFirst == ASSUME NEW n \in Nodes, NEW v \in 1 .. V, NEW a \in Addr, NEW t \in {"var", "char"}, IndInv, RowStart(n, v), cnt[n] = 0, FirstAt(n, a, t) PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(100), <1>0 DEF NoLeak, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>2. CASE a9 = a
    BY SMTT(100), <2>2, <2>1, <1>0 DEF AOrphan, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(a9 = a)
    BY SMTT(100), <2>3, <2>1, <1>0 DEF AOrphan, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>2. CASE n9 = n
    BY SMTT(100), <2>2, <2>1, <1>0 DEF NCap5, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <2>3, <2>1, <1>0 DEF NCap5, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>2. CASE n9 = n
    BY SMTT(100), <2>2, <2>1, <1>0 DEF NCap8, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <2>3, <2>1, <1>0 DEF NCap8, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, RowStart, FirstAt, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_RowNext == ASSUME NEW n \in Nodes, NEW v \in 1 .. V, IndInv, RowStart(n, v), cnt[n] # 0 PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>2. CASE n9 = n
    BY SMTT(100), <2>2, <2>1, <1>0 DEF NCap4, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <2>3, <2>1, <1>0 DEF NCap4, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, RowStart, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_AFull == ASSUME NEW n \in Nodes, IndInv, Active(n), ~err, pv[n] > 0, AFull(n), ACommon PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>2. CASE n9 = n
    BY SMTT(100), <2>2, <2>1, <1>0 DEF NCap1, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <2>3, <2>1, <1>0 DEF NCap1, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>2. CASE n9 = n
    BY SMTT(100), <2>2, <2>1, <1>0 DEF NCap2, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <2>3, <2>1, <1>0 DEF NCap2, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, AFull, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_AChar == ASSUME NEW n \in Nodes, NEW sp \in 0 .. MinOf(SpareMax, Room(n)), NEW a \in Addr, IndInv, Active(n), ~err, pv[n] > 0, APre(n, sp), ACharAt(n, sp, a), ACommon PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>g1. size[n] \in Nat /\ size[n] <= Max /\ pv[n] \in Nat /\ ps[n] \in Nat /\ icap[n] \in Nat
  BY <1>0, <1>n DEF TypeOK, AllN, NFacts, NIntact, Nodes
<1>1. TypeOK'
  BY SMTT(100), <1>g1, <1>0 DEF TypeOK, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>g1, <1>0 DEF NoOverflow, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>g1, <1>0 DEF NoUseAfterFree, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>g1, <1>0 DEF NoBadFree, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>g1, <1>0 DEF RightHeap, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>g1, <1>0 DEF NoLeak, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>g1, <1>0 DEF NoSlowGrowth, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF AOrphan, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NIntact, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NMem, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF AClamp, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>2. CASE n9 = n
    BY SMTT(100), <1>g1, <2>2, <2>1, <1>0 DEF NLive, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <1>g1, <2>3, <2>1, <1>0 DEF NLive, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>13. R_disj'
  BY SMTT(40), <1>g1, <1>0 DEF R_disj, NDisj, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>g1, <1>0 DEF R_ext, AExt, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF AFree, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF AGrown, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap1, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap2, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap3, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap4, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>2. CASE n9 = n
    BY SMTT(100), <1>g1, <2>2, <2>1, <1>0 DEF NCap5, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <1>g1, <2>3, <2>1, <1>0 DEF NCap5, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap6, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>2. CASE n9 = n
    BY SMTT(100), <1>g1, <2>2, <2>1, <1>0 DEF NCap7, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <1>g1, <2>3, <2>1, <1>0 DEF NCap7, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>2. CASE n9 = n
    BY SMTT(100), <1>g1, <2>2, <2>1, <1>0 DEF NCap8, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <1>g1, <2>3, <2>1, <1>0 DEF NCap8, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>25. R_ph1'
  BY SMTT(40), <1>g1, <1>0 DEF R_ph1, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>g1, <1>0 DEF R_ph2, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>g1, <1>0 DEF R_ph3, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>g1, <1>0 DEF R_ph4, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF WPh5, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF WPh6, TypeOK, ACharAt, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_AIn == ASSUME NEW n \in Nodes, NEW sp \in 0 .. MinOf(SpareMax, Room(n)), IndInv, Active(n), ~err, pv[n] > 0, APre(n, sp), AIn(n, sp), ACommon PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>g1. size[n] \in Nat /\ size[n] <= Max /\ pv[n] \in Nat /\ ps[n] \in Nat /\ icap[n] \in Nat
  BY <1>0, <1>n DEF TypeOK, AllN, NFacts, NIntact, Nodes
<1>1. TypeOK'
  BY SMTT(40), <1>g1, <1>0 DEF TypeOK, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(100), <1>g1, <1>0 DEF NoOverflow, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>g1, <1>0 DEF NoUseAfterFree, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>g1, <1>0 DEF NoBadFree, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>g1, <1>0 DEF RightHeap, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>g1, <1>0 DEF NoLeak, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>g1, <1>0 DEF NoSlowGrowth, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF AOrphan, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NIntact, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NMem, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF AClamp, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NLive, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>g1, <1>0 DEF R_disj, NDisj, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>g1, <1>0 DEF R_ext, AExt, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF AFree, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF AGrown, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>2. CASE n9 = n
    BY SMTT(100), <1>g1, <2>2, <2>1, <1>0 DEF NCap1, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <1>g1, <2>3, <2>1, <1>0 DEF NCap1, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap2, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap3, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap4, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>2. CASE n9 = n
    BY SMTT(100), <1>g1, <2>2, <2>1, <1>0 DEF NCap5, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <1>g1, <2>3, <2>1, <1>0 DEF NCap5, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>2. CASE n9 = n
    BY SMTT(100), <1>g1, <2>2, <2>1, <1>0 DEF NCap6, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <1>g1, <2>3, <2>1, <1>0 DEF NCap6, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap7, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap8, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>g1, <1>0 DEF R_ph1, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>g1, <1>0 DEF R_ph2, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>g1, <1>0 DEF R_ph3, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>g1, <1>0 DEF R_ph4, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF WPh5, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF WPh6, TypeOK, AIn, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_AFail == ASSUME NEW n \in Nodes, NEW sp \in 0 .. MinOf(SpareMax, Room(n)), IndInv, Active(n), ~err, pv[n] > 0, APre(n, sp), AFail(n, sp), ACommon PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>2. CASE n9 = n
    BY SMTT(100), <2>2, <2>1, <1>0 DEF NMem, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <2>3, <2>1, <1>0 DEF NMem, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>2. CASE a9 = str[n]
    BY SMTT(100), <2>2, <2>1, <1>0 DEF AClamp, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(a9 = str[n])
    BY SMTT(100), <2>3, <2>1, <1>0 DEF AClamp, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>2. CASE n9 = n
    BY SMTT(100), <2>2, <2>1, <1>0 DEF NLive, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <2>3, <2>1, <1>0 DEF NLive, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(100), <1>0 DEF R_ext, AExt, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>2. CASE a9 = str[n]
    BY SMTT(100), <2>2, <2>1, <1>0 DEF AFree, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(a9 = str[n])
    BY SMTT(100), <2>3, <2>1, <1>0 DEF AFree, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>2. CASE n9 = n
    BY SMTT(100), <2>2, <2>1, <1>0 DEF NCap1, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <2>3, <2>1, <1>0 DEF NCap1, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>2. CASE n9 = n
    BY SMTT(100), <2>2, <2>1, <1>0 DEF NCap2, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>3. CASE ~(n9 = n)
    BY SMTT(100), <2>3, <2>1, <1>0 DEF NCap2, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
  <2>. QED
    BY <2>2, <2>3
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, AFail, Fail, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv
====
