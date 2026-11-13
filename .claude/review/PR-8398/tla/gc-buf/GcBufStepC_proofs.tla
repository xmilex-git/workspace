---- MODULE GcBufStepC_proofs ----
(* IndInv /\ A => IndInv' for the growth through qstr_reserve and the spare bytes: AGrow, ZIn, ZGrow, ZFail. *)
EXTENDS GcBufCap_proofs

THEOREM S_AGrow == ASSUME NEW n \in Nodes, NEW sp \in 0 .. MinOf(SpareMax, Room(n)), NEW a \in Addr, NEW c \in CapCands, IndInv, Active(n), ~err, pv[n] > 0, APre(n, sp), AGrowAt(n, sp, a, c), ACommon PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>g1. size[n] \in Nat /\ size[n] <= Max /\ pv[n] \in Nat /\ ps[n] \in Nat /\ icap[n] \in Nat
  BY <1>0, <1>n DEF TypeOK, AllN, NFacts, NIntact, Nodes
<1>g2. NeedOf(n, sp) \in 1 .. Limit /\ ReqOf(n, sp) = NeedOf(n, sp)
  BY <1>g1 DEF APre, NeedOf, ReqOf, AddOf, Room, Trunc, MinOf, Limit
<1>g3. IsNewCap(c, NeedOf(n, sp))
  BY <1>g2 DEF AGrowAt, GrowAt, CapRule
<1>g4. c \in Nat /\ NeedOf(n, sp) <= c /\ c <= Limit /\ c \in Caps \cup {Limit}
  BY <1>g2, <1>g3, CapBasic DEF Limit
<1>g5. c <= MaxOf(Base, 2 * NeedOf(n, sp) - 1)
  BY <1>g2, <1>g3, CapTwice DEF Limit
<1>g6. (str[n] # 0 /\ grown[str[n]]) => (2 * heap[str[n]] <= c \/ c = Limit) /\ ReqOf(n, sp) > heap[str[n]]
  <2> SUFFICES ASSUME str[n] # 0, grown[str[n]] PROVE (2 * heap[str[n]] <= c \/ c = Limit) /\ ReqOf(n, sp) > heap[str[n]]
    OBVIOUS
  <2>0. ps[n] = 0
    BY <1>n, <1>g1 DEF AllN, NFacts, NCap5
  <2>1. icap[n] = heap[str[n]] /\ (ibuf[n] = str[n] \/ ps[n] > 0)
    BY <1>n DEF AllN, NFacts, NCap2
  <2>2. Cap0(n) = heap[str[n]]
    BY <2>1 DEF Cap0
  <2>3. ReqOf(n, sp) > heap[str[n]]
    BY <2>2 DEF AGrowAt
  <2>4. heap[str[n]] \in Caps /\ heap[str[n]] < NeedOf(n, sp)
    BY <2>3, <1>a, <1>0, <1>g2 DEF AllA, AFacts, AGrown, TypeOK, Addr, Limit
  <2>. QED
    BY <2>3, <2>4, <1>g2, <1>g3, CapDouble DEF Limit
<1>1. TypeOK'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF TypeOK, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF NoOverflow, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF NoUseAfterFree, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF NoBadFree, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF RightHeap, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF NoLeak, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF NoSlowGrowth, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF AOrphan, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NIntact, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NMem, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF AClamp, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NLive, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF R_disj, NDisj, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF R_ext, AExt, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF AFree, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF AGrown, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap1, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap2, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap3, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap4, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap5, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap6, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap7, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap8, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF R_ph1, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF R_ph2, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF R_ph3, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF R_ph4, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF WPh5, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF WPh6, TypeOK, AGrowAt, GrowAt, CapRule, APre, ACommon, Cap0, Room, Trunc, AddOf, NeedOf, ReqOf, SpareOf, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_ZIn == ASSUME NEW n \in Nodes, IndInv, Active(n), ~err, ps[n] > 0, ps' = [ps EXCEPT ![n] = 0], ZCommon, ZIn(n) PROVE IndInv'
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
  BY SMTT(40), <1>g1, <1>0 DEF TypeOK, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>g1, <1>0 DEF NoOverflow, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>g1, <1>0 DEF NoUseAfterFree, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>g1, <1>0 DEF NoBadFree, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>g1, <1>0 DEF RightHeap, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>g1, <1>0 DEF NoLeak, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>g1, <1>0 DEF NoSlowGrowth, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF AOrphan, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NIntact, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NMem, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF AClamp, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NLive, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>g1, <1>0 DEF R_disj, NDisj, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>g1, <1>0 DEF R_ext, AExt, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF AFree, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF AGrown, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap1, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap2, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap3, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap4, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap5, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap6, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap7, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF NCap8, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>g1, <1>0 DEF R_ph1, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>g1, <1>0 DEF R_ph2, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>g1, <1>0 DEF R_ph3, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>g1, <1>0 DEF R_ph4, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF WPh5, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <1>g1, <2>1, <1>0 DEF WPh6, TypeOK, ZIn, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_ZGrow == ASSUME NEW n \in Nodes, NEW a \in Addr, NEW c \in CapCands, IndInv, Active(n), ~err, ps[n] > 0, ps' = [ps EXCEPT ![n] = 0], ZCommon, ZGrowAt(n, a, c) PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>g1. size[n] \in Nat /\ size[n] <= Max /\ pv[n] \in Nat /\ ps[n] \in Nat /\ icap[n] \in Nat
  BY <1>0, <1>n DEF TypeOK, AllN, NFacts, NIntact, Nodes
<1>g2. ZNeed(n) = Limit /\ ZReq(n) = ZNeed(n)
  BY <1>g1, <1>n DEF AllN, NFacts, NCap5, ZNeed, ZReq, Limit
<1>g3. IsNewCap(c, ZNeed(n))
  BY <1>g2 DEF ZGrowAt, GrowAt, CapRule, Limit
<1>g4. c \in Nat /\ ZNeed(n) <= c /\ c <= Limit /\ c \in Caps \cup {Limit}
  BY <1>g2, <1>g3, CapBasic DEF Limit
<1>g5. c <= MaxOf(Base, 2 * ZNeed(n) - 1)
  BY <1>g2, <1>g3, CapTwice DEF Limit
<1>g6. (str[n] # 0 /\ grown[str[n]]) => (2 * heap[str[n]] <= c \/ c = Limit) /\ ZReq(n) > heap[str[n]]
  <2> SUFFICES ASSUME str[n] # 0, grown[str[n]] PROVE (2 * heap[str[n]] <= c \/ c = Limit) /\ ZReq(n) > heap[str[n]]
    OBVIOUS
  <2>0. TRUE
    OBVIOUS
  <2>1. icap[n] = heap[str[n]] /\ (ibuf[n] = str[n] \/ ps[n] > 0)
    BY <1>n DEF AllN, NFacts, NCap2
  <2>2. TRUE
    OBVIOUS
  <2>3. ZReq(n) > heap[str[n]]
    BY <2>1 DEF ZGrowAt
  <2>4. heap[str[n]] \in Caps /\ heap[str[n]] < ZNeed(n)
    BY <2>3, <1>a, <1>0, <1>g2 DEF AllA, AFacts, AGrown, TypeOK, Addr, Limit
  <2>. QED
    BY <2>3, <2>4, <1>g2, <1>g3, CapDouble DEF Limit
<1>1. TypeOK'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF TypeOK, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF NoOverflow, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF NoUseAfterFree, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF NoBadFree, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF RightHeap, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF NoLeak, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF NoSlowGrowth, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF AOrphan, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NIntact, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NMem, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF AClamp, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NLive, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF R_disj, NDisj, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF R_ext, AExt, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF AFree, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF AGrown, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap1, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap2, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap3, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap4, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap5, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap6, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap7, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF NCap8, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF R_ph1, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF R_ph2, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF R_ph3, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <1>0 DEF R_ph4, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF WPh5, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <1>g1, <1>g2, <1>g3, <1>g4, <1>g5, <1>g6, <2>1, <1>0 DEF WPh6, TypeOK, ZGrowAt, GrowAt, CapRule, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv

THEOREM S_ZFail == ASSUME NEW n \in Nodes, IndInv, Active(n), ~err, ps[n] > 0, ps' = [ps EXCEPT ![n] = 0], ZCommon, ZFail(n) PROVE IndInv'
<1> USE Assm, Correct
<1>0. TypeOK /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth /\ NoOrphan /\ Intact /\ MemBound /\ Clamped /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8 /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6
  BY DEF IndInv
<1>n. AllN
  BY <1>0 DEF AllN, NFacts, Intact, MemBound, R_live, R_cap1, R_cap2, R_cap3, R_cap4, R_cap5, R_cap6, R_cap7, R_cap8
<1>a. AllA
  BY <1>0 DEF AllA, AFacts, NoOrphan, Clamped, R_free, R_grown
<1>1. TypeOK'
  BY SMTT(40), <1>0 DEF TypeOK, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>2. NoOverflow'
  BY SMTT(40), <1>0 DEF NoOverflow, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>3. NoUseAfterFree'
  BY SMTT(40), <1>0 DEF NoUseAfterFree, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>4. NoBadFree'
  BY SMTT(40), <1>0 DEF NoBadFree, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>5. RightHeap'
  BY SMTT(40), <1>0 DEF RightHeap, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>6. NoLeak'
  BY SMTT(40), <1>0 DEF NoLeak, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>7. NoSlowGrowth'
  BY SMTT(40), <1>0 DEF NoSlowGrowth, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>8. NoOrphan'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AOrphan(a9)'
    BY DEF NoOrphan
  <2>1. AOrphan(a9)
    BY <1>0 DEF NoOrphan
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AOrphan, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>9. Intact'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NIntact(n9)'
    BY DEF Intact
  <2>1. NIntact(n9)
    BY <1>0 DEF Intact
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NIntact, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>10. MemBound'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NMem(n9)'
    BY DEF MemBound
  <2>1. NMem(n9)
    BY <1>0 DEF MemBound
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NMem, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>11. Clamped'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AClamp(a9)'
    BY DEF Clamped
  <2>1. AClamp(a9)
    BY <1>0 DEF Clamped
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AClamp, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>12. R_live'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NLive(n9)'
    BY DEF R_live
  <2>1. NLive(n9)
    BY <1>0 DEF R_live
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NLive, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>13. R_disj'
  BY SMTT(40), <1>0 DEF R_disj, NDisj, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>14. R_ext'
  BY SMTT(40), <1>0 DEF R_ext, AExt, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>15. R_free'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AFree(a9)'
    BY DEF R_free
  <2>1. AFree(a9)
    BY <1>0 DEF R_free
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AFree, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>16. R_grown'
  <2> SUFFICES ASSUME NEW a9 \in Addr PROVE AGrown(a9)'
    BY DEF R_grown
  <2>1. AGrown(a9)
    BY <1>0 DEF R_grown
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF AGrown, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>17. R_cap1'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap1(n9)'
    BY DEF R_cap1
  <2>1. NCap1(n9)
    BY <1>0 DEF R_cap1
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap1, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>18. R_cap2'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap2(n9)'
    BY DEF R_cap2
  <2>1. NCap2(n9)
    BY <1>0 DEF R_cap2
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap2, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>19. R_cap3'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap3(n9)'
    BY DEF R_cap3
  <2>1. NCap3(n9)
    BY <1>0 DEF R_cap3
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap3, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>20. R_cap4'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap4(n9)'
    BY DEF R_cap4
  <2>1. NCap4(n9)
    BY <1>0 DEF R_cap4
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap4, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>21. R_cap5'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap5(n9)'
    BY DEF R_cap5
  <2>1. NCap5(n9)
    BY <1>0 DEF R_cap5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap5, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>22. R_cap6'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap6(n9)'
    BY DEF R_cap6
  <2>1. NCap6(n9)
    BY <1>0 DEF R_cap6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap6, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>23. R_cap7'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap7(n9)'
    BY DEF R_cap7
  <2>1. NCap7(n9)
    BY <1>0 DEF R_cap7
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap7, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>24. R_cap8'
  <2> SUFFICES ASSUME NEW n9 \in Nodes PROVE NCap8(n9)'
    BY DEF R_cap8
  <2>1. NCap8(n9)
    BY <1>0 DEF R_cap8
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF NCap8, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>25. R_ph1'
  BY SMTT(40), <1>0 DEF R_ph1, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>26. R_ph2'
  BY SMTT(40), <1>0 DEF R_ph2, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>27. R_ph3'
  BY SMTT(40), <1>0 DEF R_ph3, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>28. R_ph4'
  BY SMTT(40), <1>0 DEF R_ph4, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>29. R_ph5'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh5(w9)'
    BY DEF R_ph5
  <2>1. WPh5(w9)
    BY <1>0 DEF R_ph5
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh5, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>30. R_ph6'
  <2> SUFFICES ASSUME NEW w9 \in Workers PROVE WPh6(w9)'
    BY DEF R_ph6
  <2>1. WPh6(w9)
    BY <1>0 DEF R_ph6
  <2>. QED
    BY SMTT(40), <2>1, <1>0 DEF WPh6, TypeOK, ZFail, Fail, ZCommon, ZNeed, ZReq, InPlace, R_disj, NDisj, R_ext, AExt, R_live, NLive, R_free, AFree, Loc, Active, Ctx, Nodes, Addr, Limit, MaxOf, MinOf, Bools, Phases, WPhases, Heaps, SeenTags, HeapAF, HpAF, FillAF, GrownAF, BadFree, WrongHeap, CopyOf, ReadsFreed, Owned, Live, R_ph1, R_ph2, R_ph3, R_ph4
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29, <1>30 DEF IndInv
====
