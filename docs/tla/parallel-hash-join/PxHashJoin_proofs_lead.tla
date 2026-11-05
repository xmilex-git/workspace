\* timeout: 5400
-------------------------- MODULE PxHashJoin_proofs_lead --------------------------
(* StepInv lemmas: leader and user actions and the stuttering cases;
   each proved per IndInv part, a branching action per branch of its effect (P33). *)
EXTENDS PxHashJoin_proofs_base

LEMMA Step_L_push == ASSUME IndInv, L_push PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. L_push
  OBVIOUS
<1>1. IndInv'
  <2> USE <1>0 DEF L_push
  <2>1. IPc'
    BY DEF IPc
  <2>2. IKey'
    BY DEF IKey
  <2>3. IPush'
    BY DEF IPush, IPc
  <2>4. IFix'
    BY DEF IFix
  <2>5. IErr'
    BY DEF IErr, IPc, IPush
  <2>6. IMain'
    BY DEF IMain, IErr, IPc
  <2>7. IIntr'
    BY DEF IIntr, IErr, IPush, IPc
  <2>8. IFree'
    BY DEF IFree, IPush, IPc
  <2>9. IRes'
    BY DEF IRes, IErr, IMain, IPc, IPush
  <2>10. IDisp'
    BY DEF IDisp, IPc
  <2>11. ICnt'
    BY DEF ICnt, IDisp, Handed
  <2>12. ILocal'
    BY DEF ILocal, IPc
  <2>13. IStart'
    BY DEF IStart, IPc
  <2>14. IDataT'
    BY DEF IDataT, TempVals, WOutVals
  <2>15. IMerged'
    BY DEF IMerged, IPc, IPush
  <2>. QED
    BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12, <2>13, <2>14, <2>15
<1>. QED
  BY <1>1

LEMMA Step_L_join == ASSUME IndInv, L_join PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. L_join
  OBVIOUS
<1>1. IndInv'
  <2> USE <1>0 DEF L_join
  <2>1. IPc'
    BY DEF IPc
  <2>2. IKey'
    BY DEF IKey
  <2>3. IPush'
    BY DEF IPush, IPc
  <2>4. IFix'
    BY DEF IFix
  <2>5. IErr'
    BY DEF IErr, IPc, IPush
  <2>6. IMain'
    BY DEF IMain, IErr, IPc
  <2>7. IIntr'
    BY DEF IIntr, IErr, IPush, IPc
  <2>8. IFree'
    BY DEF IFree, IPush, IPc
  <2>9. IRes'
    BY DEF IRes, IErr, IMain, IPc, IPush
  <2>10. IDisp'
    BY DEF IDisp, IPc
  <2>11. ICnt'
    BY DEF ICnt, IDisp, Handed
  <2>12. ILocal'
    BY DEF ILocal, IPc
  <2>13. IStart'
    BY DEF IStart, IPc
  <2>14. IDataT'
    BY DEF IDataT, TempVals, WOutVals
  <2>15. IMerged'
    BY DEF IMerged, IPc, IPush
  <2>. QED
    BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12, <2>13, <2>14, <2>15
<1>. QED
  BY <1>1

LEMMA Step_L_after == ASSUME IndInv, L_after PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. L_after
  OBVIOUS
<1>1. IndInv'
  <2> USE <1>0 DEF L_after
  <2>1. IPc'
    BY DEF IPc
  <2>2. IKey'
    BY DEF IKey
  <2>3. IPush'
    BY DEF IPush, IPc
  <2>4. IFix'
    BY DEF IFix
  <2>5. IErr'
    BY DEF IErr, IPc, IPush
  <2>6. IMain'
    BY DEF IMain, IErr, IPc
  <2>7. IIntr'
    BY DEF IIntr, IErr, IPush, IPc
  <2>8. IFree'
    BY DEF IFree, IPush, IPc
  <2>9. IRes'
    BY DEF IRes, IErr, IMain, IPc, IPush
  <2>10. IDisp'
    BY DEF IDisp, IPc
  <2>11. ICnt'
    BY DEF ICnt, IDisp, Handed
  <2>12. ILocal'
    BY DEF ILocal, IPc
  <2>13. IStart'
    BY DEF IStart, IPc
  <2>14. IDataT'
    BY DEF IDataT, TempVals, WOutVals
  <2>15. IMerged'
    BY DEF IMerged, IPc, IPush
  <2>. QED
    BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12, <2>13, <2>14, <2>15
<1>. QED
  BY <1>1

LEMMA Step_L_free == ASSUME IndInv, L_free PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. L_free
  OBVIOUS
<1>1. IndInv'
  <2> USE <1>0 DEF L_free
  <2>1. IPc'
    BY DEF IPc
  <2>2. IKey'
    BY DEF IKey
  <2>3. IPush'
    BY DEF IPush, IPc
  <2>4. IFix'
    BY DEF IFix
  <2>5. IErr'
    BY DEF IErr, IPc, IPush
  <2>6. IMain'
    BY DEF IMain, IErr, IPc
  <2>7. IIntr'
    BY DEF IIntr, IErr, IPush, IPc
  <2>8. IFree'
    BY DEF IFree, IPush, IPc
  <2>9. IRes'
    BY DEF IRes, IErr, IMain, IPc, IPush
  <2>10. IDisp'
    BY DEF IDisp, IPc
  <2>11. ICnt'
    BY DEF ICnt, IDisp, Handed
  <2>12. ILocal'
    BY DEF ILocal, IPc
  <2>13. IStart'
    BY DEF IStart, IPc
  <2>14. IDataT'
    BY DEF IDataT, TempVals, WOutVals
  <2>15. IMerged'
    BY DEF IMerged, IPc, IPush
  <2>. QED
    BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12, <2>13, <2>14, <2>15
<1>. QED
  BY <1>1

LEMMA Step_L_fallback == ASSUME IndInv, L_fallback PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. L_fallback
  OBVIOUS
<1>1. IndInv'
  <2> USE <1>0 DEF L_fallback
  <2>1. IPc'
    BY DEF IPc
  <2>2. IKey'
    BY DEF IKey
  <2>3. IPush'
    BY DEF IPush, IPc
  <2>4. IFix'
    BY DEF IFix
  <2>5. IErr'
    BY DEF IErr, IPc, IPush
  <2>6. IMain'
    BY DEF IMain, IErr, IPc
  <2>7. IIntr'
    BY DEF IIntr, IErr, IPush, IPc
  <2>8. IFree'
    BY DEF IFree, IPush, IPc
  <2>9. IRes'
    BY DEF IRes, IErr, IMain, IPc, IPush
  <2>10. IDisp'
    BY DEF IDisp, IPc
  <2>11. ICnt'
    BY DEF ICnt, IDisp, Handed
  <2>12. ILocal'
    BY DEF ILocal, IPc
  <2>13. IStart'
    BY DEF IStart, IPc
  <2>14. IDataT'
    BY DEF IDataT, TempVals, WOutVals
  <2>15. IMerged'
    BY DEF IMerged, IPc, IPush
  <2>. QED
    BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12, <2>13, <2>14, <2>15
<1>. QED
  BY <1>1

LEMMA Step_U_cancel == ASSUME IndInv, U_cancel PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. U_cancel
  OBVIOUS
<1>1. IndInv'
  <2> USE <1>0 DEF U_cancel
  <2>1. IPc'
    BY DEF IPc
  <2>2. IKey'
    BY DEF IKey
  <2>3. IPush'
    BY DEF IPush, IPc
  <2>4. IFix'
    BY DEF IFix
  <2>5. IErr'
    BY DEF IErr, IPc, IPush
  <2>6. IMain'
    BY DEF IMain, IErr, IPc
  <2>7. IIntr'
    <3>1. CASE UNCHANGED <<intr, cancelled>>
      BY <3>1 DEF IIntr, IErr, IPush, IPc
    <3>2. CASE pc[Leader] # "Done" /\ cancelled' = TRUE /\ intr' = TRUE
      BY <3>2 DEF IIntr, IPc
    <3>. QED
      BY <3>1, <3>2
  <2>8. IFree'
    BY DEF IFree, IPush, IPc
  <2>9. IRes'
    <3>1. pc'[Leader] = pc[Leader] /\ UNCHANGED <<res, fellBack, final, hasError, mainErr>>
      BY DEF IPc
    <3>. QED
      BY <3>1 DEF IRes
  <2>10. IDisp'
    BY DEF IDisp, IPc
  <2>11. ICnt'
    BY DEF ICnt, IDisp, Handed
  <2>12. ILocal'
    BY DEF ILocal, IPc
  <2>13. IStart'
    BY DEF IStart, IPc
  <2>14. IDataT'
    BY DEF IDataT, TempVals, WOutVals
  <2>15. IMerged'
    BY DEF IMerged, IPc, IPush
  <2>. QED
    BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12, <2>13, <2>14, <2>15
<1>. QED
  BY <1>1

LEMMA Step_Terminating == ASSUME IndInv, Terminating PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended, pc>>
  BY DEF Terminating, vars
<1> USE <1>0
<1>1. IPc'
  BY DEF IPc
<1>2. IKey'
  BY DEF IKey
<1>3. IPush'
  BY DEF IPush
<1>4. IFix'
  BY DEF IFix
<1>5. IErr'
  BY DEF IErr
<1>6. IMain'
  BY DEF IMain
<1>7. IIntr'
  BY DEF IIntr
<1>8. IFree'
  BY DEF IFree
<1>9. IRes'
  BY DEF IRes
<1>10. IDisp'
  BY DEF IDisp
<1>11. ICnt'
  BY DEF ICnt, Handed
<1>12. ILocal'
  BY DEF ILocal
<1>13. IStart'
  BY DEF IStart
<1>14. IDataT'
  BY DEF IDataT, TempVals, WOutVals
<1>15. IMerged'
  BY DEF IMerged
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15

LEMMA Step_Unchanged == ASSUME IndInv, UNCHANGED vars PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended, pc>>
  BY DEF vars
<1> USE <1>0
<1>1. IPc'
  BY DEF IPc
<1>2. IKey'
  BY DEF IKey
<1>3. IPush'
  BY DEF IPush
<1>4. IFix'
  BY DEF IFix
<1>5. IErr'
  BY DEF IErr
<1>6. IMain'
  BY DEF IMain
<1>7. IIntr'
  BY DEF IIntr
<1>8. IFree'
  BY DEF IFree
<1>9. IRes'
  BY DEF IRes
<1>10. IDisp'
  BY DEF IDisp
<1>11. ICnt'
  BY DEF ICnt, Handed
<1>12. ILocal'
  BY DEF ILocal
<1>13. IStart'
  BY DEF IStart
<1>14. IDataT'
  BY DEF IDataT, TempVals, WOutVals
<1>15. IMerged'
  BY DEF IMerged
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15

=============================================================================
