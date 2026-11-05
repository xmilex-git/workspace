\* timeout: 5400
-------------------------- MODULE PxHashJoin_proofs_claim --------------------------
(* StepInv lemmas: the worker loop top and the unit claim (W_check, W_claim);
   each proved per IndInv part, a branching action per branch of its effect (P33). *)
EXTENDS PxHashJoin_proofs_base

LEMMA Step_W_check == ASSUME IndInv, NEW self \in Workers, W_check(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_check(self)
  OBVIOUS
<1>1. IndInv'
  <2>0. \/ /\ pc[self] = "W_check"
           /\ hasError
           /\ uaf' = (uaf \/ freed)
           /\ pc' = ([pc EXCEPT ![self] = "W_cleanup"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_check"
           /\ ~hasError
           /\ intr
           /\ uaf' = (uaf \/ freed)
           /\ failed' = ([failed EXCEPT ![self] = "intr"])
           /\ intr' = (FALSE)
           /\ pc' = ([pc EXCEPT ![self] = "W_err"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_check"
           /\ ~hasError
           /\ ~intr
           /\ uaf' = (uaf \/ freed)
           /\ pc' = ([pc EXCEPT ![self] = "W_claim"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. CASE hasError
      BY <3>1, <1>0, Correct DEF W_check, IFix
    <3>2. CASE ~hasError /\ intr
      BY <3>2, <1>0, Correct DEF W_check, IFix
    <3>3. CASE ~hasError /\ ~intr
      BY <3>3, <1>0, Correct DEF W_check, IFix
    <3>4. (hasError) \/ (~hasError /\ intr) \/ (~hasError /\ ~intr)
      BY <1>0, Correct, Assm DEF W_check, IErr, ErrPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4
  <2>1. CASE /\ pc[self] = "W_check"
             /\ hasError
             /\ uaf' = (uaf \/ freed)
             /\ pc' = ([pc EXCEPT ![self] = "W_cleanup"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. IPc'
      BY <2>1 DEF IPc
    <3>2. IKey'
      BY <2>1 DEF IKey
    <3>3. IPush'
      BY <2>1 DEF IPush, IPc
    <3>4. IFix'
      BY <2>1 DEF IFix
    <3>5. IErr'
      BY <2>1 DEF IErr, IPc, IPush
    <3>6. IMain'
      BY <2>1 DEF IMain, IErr, IPc
    <3>7. IIntr'
      BY <2>1 DEF IIntr, IErr, IPush, IPc
    <3>8. IFree'
      BY <2>1 DEF IFree, IPush, IPc
    <3>9. IRes'
      BY <2>1 DEF IRes, IErr, IMain, IPc, IPush
    <3>10. IDisp'
      BY <2>1 DEF IDisp, IPc
    <3>11. ICnt'
      BY <2>1 DEF ICnt, IDisp, Handed
    <3>12. ILocal'
      BY <2>1 DEF ILocal, IPc
    <3>13. IStart'
      <4>1. \A w \in Workers : pc'[w] = "W_start" => w # self /\ pc[w] = "W_start"
        BY <2>1 DEF IPc
      <4>2. \A w \in Workers \ {self} : ok'[w] = ok[w] /\ won'[w] = won[w] /\ failed'[w] = failed[w]
        BY <2>1 DEF ILocal, IErr
      <4>. QED
        BY <2>1, <4>1, <4>2 DEF IStart
    <3>14. IDataT'
      BY <2>1 DEF IDataT, TempVals, WOutVals
    <3>15. IMerged'
      <4>1. pc[Leader] \notin Returned
        <5>1. self \in pushed /\ pc[self] # "Done"
          BY <2>1 DEF IPush, IPc
        <5>2. self \in active
          BY <5>1 DEF IPush
        <5>. QED
          BY <5>2 DEF IPush
      <4>. QED
        BY <2>1, <4>1 DEF IMerged, IPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15
  <2>2. CASE /\ pc[self] = "W_check"
             /\ ~hasError
             /\ intr
             /\ uaf' = (uaf \/ freed)
             /\ failed' = ([failed EXCEPT ![self] = "intr"])
             /\ intr' = (FALSE)
             /\ pc' = ([pc EXCEPT ![self] = "W_err"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. IPc'
      BY <2>2 DEF IPc
    <3>2. IKey'
      BY <2>2 DEF IKey
    <3>3. IPush'
      BY <2>2 DEF IPush, IPc
    <3>4. IFix'
      BY <2>2 DEF IFix
    <3>5. IErr'
      BY <2>2 DEF IErr, IPc, IPush
    <3>6. IMain'
      BY <2>2 DEF IMain, IErr, IPc
    <3>7. IIntr'
      BY <2>2 DEF IIntr, IErr, IPush, IPc
    <3>8. IFree'
      BY <2>2 DEF IFree, IPush, IPc
    <3>9. IRes'
      BY <2>2 DEF IRes, IErr, IMain, IPc, IPush
    <3>10. IDisp'
      BY <2>2 DEF IDisp, IPc
    <3>11. ICnt'
      BY <2>2 DEF ICnt, IDisp, Handed
    <3>12. ILocal'
      BY <2>2 DEF ILocal, IPc
    <3>13. IStart'
      <4>1. \A w \in Workers : pc'[w] = "W_start" => w # self /\ pc[w] = "W_start"
        BY <2>2 DEF IPc
      <4>2. \A w \in Workers \ {self} : ok'[w] = ok[w] /\ won'[w] = won[w] /\ failed'[w] = failed[w]
        BY <2>2 DEF ILocal, IErr
      <4>. QED
        BY <2>2, <4>1, <4>2 DEF IStart
    <3>14. IDataT'
      BY <2>2 DEF IDataT, TempVals, WOutVals
    <3>15. IMerged'
      <4>1. pc[Leader] \notin Returned
        <5>1. self \in pushed /\ pc[self] # "Done"
          BY <2>2 DEF IPush, IPc
        <5>2. self \in active
          BY <5>1 DEF IPush
        <5>. QED
          BY <5>2 DEF IPush
      <4>. QED
        BY <2>2, <4>1 DEF IMerged, IPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15
  <2>3. CASE /\ pc[self] = "W_check"
             /\ ~hasError
             /\ ~intr
             /\ uaf' = (uaf \/ freed)
             /\ pc' = ([pc EXCEPT ![self] = "W_claim"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. IPc'
      BY <2>3 DEF IPc
    <3>2. IKey'
      BY <2>3 DEF IKey
    <3>3. IPush'
      BY <2>3 DEF IPush, IPc
    <3>4. IFix'
      BY <2>3 DEF IFix
    <3>5. IErr'
      BY <2>3 DEF IErr, IPc, IPush
    <3>6. IMain'
      BY <2>3 DEF IMain, IErr, IPc
    <3>7. IIntr'
      BY <2>3 DEF IIntr, IErr, IPush, IPc
    <3>8. IFree'
      BY <2>3 DEF IFree, IPush, IPc
    <3>9. IRes'
      BY <2>3 DEF IRes, IErr, IMain, IPc, IPush
    <3>10. IDisp'
      BY <2>3 DEF IDisp, IPc
    <3>11. ICnt'
      BY <2>3 DEF ICnt, IDisp, Handed
    <3>12. ILocal'
      BY <2>3 DEF ILocal, IPc
    <3>13. IStart'
      <4>1. \A w \in Workers : pc'[w] = "W_start" => w # self /\ pc[w] = "W_start"
        BY <2>3 DEF IPc
      <4>2. \A w \in Workers \ {self} : ok'[w] = ok[w] /\ won'[w] = won[w] /\ failed'[w] = failed[w]
        BY <2>3 DEF ILocal, IErr
      <4>. QED
        BY <2>3, <4>1, <4>2 DEF IStart
    <3>14. IDataT'
      BY <2>3 DEF IDataT, TempVals, WOutVals
    <3>15. IMerged'
      <4>1. pc[Leader] \notin Returned
        <5>1. self \in pushed /\ pc[self] # "Done"
          BY <2>3 DEF IPush, IPc
        <5>2. self \in active
          BY <5>1 DEF IPush
        <5>. QED
          BY <5>2 DEF IPush
      <4>. QED
        BY <2>3, <4>1 DEF IMerged, IPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15
  <2>. QED
    BY <2>0, <2>1, <2>2, <2>3
<1>. QED
  BY <1>1

LEMMA Step_W_claim == ASSUME IndInv, NEW self \in Workers, W_claim(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_claim(self)
  OBVIOUS
<1>1. IndInv'
  <2>0. \/ /\ pc[self] = "W_claim"
           /\ mb[self] = 0
           /\ NM = 0
           /\ mb' = ([mb EXCEPT ![self] = -1])
           /\ pc' = ([pc EXCEPT ![self] = "W_claim"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_claim"
           /\ mb[self] = 0
           /\ NM # 0
           /\ membufClaimed
           /\ mb' = ([mb EXCEPT ![self] = -1])
           /\ uaf' = (uaf \/ freed)
           /\ pc' = ([pc EXCEPT ![self] = "W_claim"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_claim"
           /\ mb[self] = 0
           /\ NM # 0
           /\ ~membufClaimed
           /\ mb' = ([mb EXCEPT ![self] = 1])
           /\ membufClaimed' = (TRUE)
           /\ owner' = (self)
           /\ uaf' = (uaf \/ freed)
           /\ pc' = ([pc EXCEPT ![self] = "W_claim"])
           /\ UNCHANGED <<key, pushed, active, next, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_claim"
           /\ mb[self] >= 1
           /\ mb[self] <= NM
           /\ cnt' = ([cnt EXCEPT ![mb[self]] = cnt[mb[self]] + 1])
           /\ mb' = ([mb EXCEPT ![self] = mb[self] + 1])
           /\ u' = ([u EXCEPT ![self] = mb[self]])
           /\ uaf' = (uaf \/ freed)
           /\ pc' = ([pc EXCEPT ![self] = "W_proc"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_claim"
           /\ mb[self] # 0
           /\ ~(mb[self] >= 1 /\ mb[self] <= NM)
           /\ next <= NU
           /\ cnt' = ([cnt EXCEPT ![next] = cnt[next] + 1])
           /\ next' = (next + 1)
           /\ u' = ([u EXCEPT ![self] = next])
           /\ uaf' = (uaf \/ freed)
           /\ pc' = ([pc EXCEPT ![self] = "W_proc"])
           /\ UNCHANGED <<key, pushed, active, membufClaimed, owner, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_claim"
           /\ mb[self] # 0
           /\ ~(mb[self] >= 1 /\ mb[self] <= NM)
           /\ ~(next <= NU)
           /\ ok' = ([ok EXCEPT ![self] = TRUE])
           /\ uaf' = (uaf \/ freed)
           /\ pc' = ([pc EXCEPT ![self] = "W_cleanup"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, matched, ended>>
    <3>1. CASE mb[self] = 0 /\ NM = 0
      BY <3>1, <1>0, Correct DEF W_claim, IFix
    <3>2. CASE mb[self] = 0 /\ NM # 0 /\ membufClaimed
      BY <3>2, <1>0, Correct DEF W_claim, IFix
    <3>3. CASE mb[self] = 0 /\ NM # 0 /\ ~membufClaimed
      BY <3>3, <1>0, Correct DEF W_claim, IFix
    <3>4. CASE mb[self] >= 1 /\ mb[self] <= NM
      BY <3>4, <1>0, Correct DEF W_claim, IFix
    <3>5. CASE mb[self] # 0 /\ ~(mb[self] >= 1 /\ mb[self] <= NM) /\ next <= NU
      BY <3>5, <1>0, Correct DEF W_claim, IFix
    <3>6. CASE mb[self] # 0 /\ ~(mb[self] >= 1 /\ mb[self] <= NM) /\ ~(next <= NU)
      BY <3>6, <1>0, Correct DEF W_claim, IFix
    <3>7. (mb[self] = 0 /\ NM = 0) \/ (mb[self] = 0 /\ NM # 0 /\ membufClaimed) \/ (mb[self] = 0 /\ NM # 0 /\ ~membufClaimed) \/ (mb[self] >= 1 /\ mb[self] <= NM) \/ (mb[self] # 0 /\ ~(mb[self] >= 1 /\ mb[self] <= NM) /\ next <= NU) \/ (mb[self] # 0 /\ ~(mb[self] >= 1 /\ mb[self] <= NM) /\ ~(next <= NU))
      BY <1>0, Correct, Assm DEF W_claim, IErr, ErrPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7
  <2>1. CASE /\ pc[self] = "W_claim"
             /\ mb[self] = 0
             /\ NM = 0
             /\ mb' = ([mb EXCEPT ![self] = -1])
             /\ pc' = ([pc EXCEPT ![self] = "W_claim"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. IPc'
      BY <2>1 DEF IPc
    <3>2. IKey'
      BY <2>1 DEF IKey
    <3>3. IPush'
      BY <2>1 DEF IPush, IPc
    <3>4. IFix'
      BY <2>1 DEF IFix
    <3>5. IErr'
      BY <2>1 DEF IErr, IPc, IPush
    <3>6. IMain'
      BY <2>1 DEF IMain, IErr, IPc
    <3>7. IIntr'
      BY <2>1 DEF IIntr, IErr, IPush, IPc
    <3>8. IFree'
      BY <2>1 DEF IFree, IPush, IPc
    <3>9. IRes'
      BY <2>1 DEF IRes, IErr, IMain, IPc, IPush
    <3>10. IDisp'
      BY <2>1 DEF IDisp, IPc
    <3>11. ICnt'
      BY <2>1 DEF ICnt, IDisp, Handed
    <3>12. ILocal'
      BY <2>1 DEF ILocal, IPc
    <3>13. IStart'
      <4>1. \A w \in Workers : pc'[w] = "W_start" => w # self /\ pc[w] = "W_start"
        BY <2>1 DEF IPc
      <4>2. \A w \in Workers \ {self} : ok'[w] = ok[w] /\ won'[w] = won[w] /\ failed'[w] = failed[w]
        BY <2>1 DEF ILocal, IErr
      <4>. QED
        BY <2>1, <4>1, <4>2 DEF IStart
    <3>14. IDataT'
      BY <2>1 DEF IDataT, TempVals, WOutVals
    <3>15. IMerged'
      <4>1. pc[Leader] \notin Returned
        <5>1. self \in pushed /\ pc[self] # "Done"
          BY <2>1 DEF IPush, IPc
        <5>2. self \in active
          BY <5>1 DEF IPush
        <5>. QED
          BY <5>2 DEF IPush
      <4>. QED
        BY <2>1, <4>1 DEF IMerged, IPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15
  <2>2. CASE /\ pc[self] = "W_claim"
             /\ mb[self] = 0
             /\ NM # 0
             /\ membufClaimed
             /\ mb' = ([mb EXCEPT ![self] = -1])
             /\ uaf' = (uaf \/ freed)
             /\ pc' = ([pc EXCEPT ![self] = "W_claim"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. IPc'
      BY <2>2 DEF IPc
    <3>2. IKey'
      BY <2>2 DEF IKey
    <3>3. IPush'
      BY <2>2 DEF IPush, IPc
    <3>4. IFix'
      BY <2>2 DEF IFix
    <3>5. IErr'
      BY <2>2 DEF IErr, IPc, IPush
    <3>6. IMain'
      BY <2>2 DEF IMain, IErr, IPc
    <3>7. IIntr'
      BY <2>2 DEF IIntr, IErr, IPush, IPc
    <3>8. IFree'
      BY <2>2 DEF IFree, IPush, IPc
    <3>9. IRes'
      BY <2>2 DEF IRes, IErr, IMain, IPc, IPush
    <3>10. IDisp'
      BY <2>2 DEF IDisp, IPc
    <3>11. ICnt'
      <4>1. owner # "none" /\ owner # self /\ owner' = owner /\ mb'[owner] = mb[owner]
        BY <2>2 DEF IDisp
      <4>2. \A v \in Units : Handed(v)' = Handed(v)
        BY <2>2, <4>1 DEF Handed
      <4>. QED
        BY <2>2, <4>2 DEF ICnt
    <3>12. ILocal'
      BY <2>2 DEF ILocal, IPc
    <3>13. IStart'
      <4>1. \A w \in Workers : pc'[w] = "W_start" => w # self /\ pc[w] = "W_start"
        BY <2>2 DEF IPc
      <4>2. \A w \in Workers \ {self} : ok'[w] = ok[w] /\ won'[w] = won[w] /\ failed'[w] = failed[w]
        BY <2>2 DEF ILocal, IErr
      <4>. QED
        BY <2>2, <4>1, <4>2 DEF IStart
    <3>14. IDataT'
      BY <2>2 DEF IDataT, TempVals, WOutVals
    <3>15. IMerged'
      <4>1. pc[Leader] \notin Returned
        <5>1. self \in pushed /\ pc[self] # "Done"
          BY <2>2 DEF IPush, IPc
        <5>2. self \in active
          BY <5>1 DEF IPush
        <5>. QED
          BY <5>2 DEF IPush
      <4>. QED
        BY <2>2, <4>1 DEF IMerged, IPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15
  <2>3. CASE /\ pc[self] = "W_claim"
             /\ mb[self] = 0
             /\ NM # 0
             /\ ~membufClaimed
             /\ mb' = ([mb EXCEPT ![self] = 1])
             /\ membufClaimed' = (TRUE)
             /\ owner' = (self)
             /\ uaf' = (uaf \/ freed)
             /\ pc' = ([pc EXCEPT ![self] = "W_claim"])
             /\ UNCHANGED <<key, pushed, active, next, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. IPc'
      BY <2>3 DEF IPc
    <3>2. IKey'
      BY <2>3 DEF IKey
    <3>3. IPush'
      BY <2>3 DEF IPush, IPc
    <3>4. IFix'
      BY <2>3 DEF IFix
    <3>5. IErr'
      BY <2>3 DEF IErr, IPc, IPush
    <3>6. IMain'
      BY <2>3 DEF IMain, IErr, IPc
    <3>7. IIntr'
      BY <2>3 DEF IIntr, IErr, IPush, IPc
    <3>8. IFree'
      BY <2>3 DEF IFree, IPush, IPc
    <3>9. IRes'
      BY <2>3 DEF IRes, IErr, IMain, IPc, IPush
    <3>10. IDisp'
      BY <2>3 DEF IDisp, IPc
    <3>11. ICnt'
      <4>1. owner = "none" /\ owner' = self /\ mb'[self] = 1
        BY <2>3 DEF IDisp
      <4>2. \A v \in Units : Handed(v)' = Handed(v)
        BY <2>3, <4>1 DEF Handed
      <4>. QED
        BY <2>3, <4>2 DEF ICnt
    <3>12. ILocal'
      BY <2>3 DEF ILocal, IPc
    <3>13. IStart'
      <4>1. \A w \in Workers : pc'[w] = "W_start" => w # self /\ pc[w] = "W_start"
        BY <2>3 DEF IPc
      <4>2. \A w \in Workers \ {self} : ok'[w] = ok[w] /\ won'[w] = won[w] /\ failed'[w] = failed[w]
        BY <2>3 DEF ILocal, IErr
      <4>. QED
        BY <2>3, <4>1, <4>2 DEF IStart
    <3>14. IDataT'
      BY <2>3 DEF IDataT, TempVals, WOutVals
    <3>15. IMerged'
      <4>1. pc[Leader] \notin Returned
        <5>1. self \in pushed /\ pc[self] # "Done"
          BY <2>3 DEF IPush, IPc
        <5>2. self \in active
          BY <5>1 DEF IPush
        <5>. QED
          BY <5>2 DEF IPush
      <4>. QED
        BY <2>3, <4>1 DEF IMerged, IPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15
  <2>4. CASE /\ pc[self] = "W_claim"
             /\ mb[self] >= 1
             /\ mb[self] <= NM
             /\ cnt' = ([cnt EXCEPT ![mb[self]] = cnt[mb[self]] + 1])
             /\ mb' = ([mb EXCEPT ![self] = mb[self] + 1])
             /\ u' = ([u EXCEPT ![self] = mb[self]])
             /\ uaf' = (uaf \/ freed)
             /\ pc' = ([pc EXCEPT ![self] = "W_proc"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, won, tmp, p, ret, ok, matched, ended>>
    <3>1. IPc'
      BY <2>4 DEF IPc
    <3>2. IKey'
      BY <2>4 DEF IKey
    <3>3. IPush'
      BY <2>4 DEF IPush, IPc
    <3>4. IFix'
      BY <2>4 DEF IFix
    <3>5. IErr'
      BY <2>4 DEF IErr, IPc, IPush
    <3>6. IMain'
      BY <2>4 DEF IMain, IErr, IPc
    <3>7. IIntr'
      BY <2>4 DEF IIntr, IErr, IPush, IPc
    <3>8. IFree'
      BY <2>4 DEF IFree, IPush, IPc
    <3>9. IRes'
      BY <2>4 DEF IRes, IErr, IMain, IPc, IPush
    <3>10. IDisp'
      <4>1. owner = self
        BY <2>4 DEF IDisp
      <4>. QED
        BY <2>4, <4>1 DEF IDisp, IPc
    <3>11. ICnt'
      <4>1. owner = self /\ mb[self] \in 1..NM /\ mb'[self] = mb[self] + 1 /\ owner' = owner
        BY <2>4 DEF IDisp
      <4>2. \A v \in Units : Handed(v)' = IF v = mb[self] THEN 1 ELSE Handed(v)
        BY <2>4, <4>1 DEF Handed
      <4>3. Handed(mb[self]) = 0
        BY <4>1 DEF Handed
      <4>. QED
        BY <2>4, <4>1, <4>2, <4>3 DEF ICnt
    <3>12. ILocal'
      <4>1. mb[self] \in Units
        BY <2>4 DEF IDisp
      <4>. QED
        BY <2>4, <4>1 DEF ILocal, IPc
    <3>13. IStart'
      <4>1. \A w \in Workers : pc'[w] = "W_start" => w # self /\ pc[w] = "W_start"
        BY <2>4 DEF IPc
      <4>2. \A w \in Workers \ {self} : ok'[w] = ok[w] /\ won'[w] = won[w] /\ failed'[w] = failed[w]
        BY <2>4 DEF ILocal, IErr
      <4>. QED
        BY <2>4, <4>1, <4>2 DEF IStart
    <3>14. IDataT'
      BY <2>4 DEF IDataT, TempVals, WOutVals
    <3>15. IMerged'
      <4>1. pc[Leader] \notin Returned
        <5>1. self \in pushed /\ pc[self] # "Done"
          BY <2>4 DEF IPush, IPc
        <5>2. self \in active
          BY <5>1 DEF IPush
        <5>. QED
          BY <5>2 DEF IPush
      <4>. QED
        BY <2>4, <4>1 DEF IMerged, IPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15
  <2>5. CASE /\ pc[self] = "W_claim"
             /\ mb[self] # 0
             /\ ~(mb[self] >= 1 /\ mb[self] <= NM)
             /\ next <= NU
             /\ cnt' = ([cnt EXCEPT ![next] = cnt[next] + 1])
             /\ next' = (next + 1)
             /\ u' = ([u EXCEPT ![self] = next])
             /\ uaf' = (uaf \/ freed)
             /\ pc' = ([pc EXCEPT ![self] = "W_proc"])
             /\ UNCHANGED <<key, pushed, active, membufClaimed, owner, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, won, tmp, p, ret, ok, matched, ended>>
    <3>1. IPc'
      BY <2>5 DEF IPc
    <3>2. IKey'
      BY <2>5 DEF IKey
    <3>3. IPush'
      BY <2>5 DEF IPush, IPc
    <3>4. IFix'
      BY <2>5 DEF IFix
    <3>5. IErr'
      BY <2>5 DEF IErr, IPc, IPush
    <3>6. IMain'
      BY <2>5 DEF IMain, IErr, IPc
    <3>7. IIntr'
      BY <2>5 DEF IIntr, IErr, IPush, IPc
    <3>8. IFree'
      BY <2>5 DEF IFree, IPush, IPc
    <3>9. IRes'
      BY <2>5 DEF IRes, IErr, IMain, IPc, IPush
    <3>10. IDisp'
      <4>1. next' \in (NM + 1)..(NU + 1)
        BY <2>5 DEF IDisp
      <4>. QED
        BY <2>5, <4>1 DEF IDisp, IPc
    <3>11. ICnt'
      <4>1. next \in (NM + 1)..NU /\ (owner # "none" => mb'[owner] = mb[owner])
        BY <2>5 DEF IDisp
      <4>2. \A v \in Units : Handed(v)' = IF v = next THEN 1 ELSE Handed(v)
        BY <2>5, <4>1 DEF Handed
      <4>3. Handed(next) = 0
        BY <4>1 DEF Handed
      <4>. QED
        BY <2>5, <4>1, <4>2, <4>3 DEF ICnt
    <3>12. ILocal'
      <4>1. next \in Units
        BY <2>5 DEF IDisp
      <4>. QED
        BY <2>5, <4>1 DEF ILocal, IPc
    <3>13. IStart'
      <4>1. \A w \in Workers : pc'[w] = "W_start" => w # self /\ pc[w] = "W_start"
        BY <2>5 DEF IPc
      <4>2. \A w \in Workers \ {self} : ok'[w] = ok[w] /\ won'[w] = won[w] /\ failed'[w] = failed[w]
        BY <2>5 DEF ILocal, IErr
      <4>. QED
        BY <2>5, <4>1, <4>2 DEF IStart
    <3>14. IDataT'
      BY <2>5 DEF IDataT, TempVals, WOutVals
    <3>15. IMerged'
      <4>1. pc[Leader] \notin Returned
        <5>1. self \in pushed /\ pc[self] # "Done"
          BY <2>5 DEF IPush, IPc
        <5>2. self \in active
          BY <5>1 DEF IPush
        <5>. QED
          BY <5>2 DEF IPush
      <4>. QED
        BY <2>5, <4>1 DEF IMerged, IPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15
  <2>6. CASE /\ pc[self] = "W_claim"
             /\ mb[self] # 0
             /\ ~(mb[self] >= 1 /\ mb[self] <= NM)
             /\ ~(next <= NU)
             /\ ok' = ([ok EXCEPT ![self] = TRUE])
             /\ uaf' = (uaf \/ freed)
             /\ pc' = ([pc EXCEPT ![self] = "W_cleanup"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, matched, ended>>
    <3>1. IPc'
      BY <2>6 DEF IPc
    <3>2. IKey'
      BY <2>6 DEF IKey
    <3>3. IPush'
      BY <2>6 DEF IPush, IPc
    <3>4. IFix'
      BY <2>6 DEF IFix
    <3>5. IErr'
      BY <2>6 DEF IErr, IPc, IPush
    <3>6. IMain'
      BY <2>6 DEF IMain, IErr, IPc
    <3>7. IIntr'
      BY <2>6 DEF IIntr, IErr, IPush, IPc
    <3>8. IFree'
      BY <2>6 DEF IFree, IPush, IPc
    <3>9. IRes'
      BY <2>6 DEF IRes, IErr, IMain, IPc, IPush
    <3>10. IDisp'
      BY <2>6 DEF IDisp, IPc
    <3>11. ICnt'
      BY <2>6 DEF ICnt, IDisp, Handed
    <3>12. ILocal'
      BY <2>6 DEF ILocal, IPc
    <3>13. IStart'
      <4>1. \A w \in Workers : pc'[w] = "W_start" => w # self /\ pc[w] = "W_start"
        BY <2>6 DEF IPc
      <4>2. \A w \in Workers \ {self} : ok'[w] = ok[w] /\ won'[w] = won[w] /\ failed'[w] = failed[w]
        BY <2>6 DEF ILocal, IErr
      <4>. QED
        BY <2>6, <4>1, <4>2 DEF IStart
    <3>14. IDataT'
      BY <2>6 DEF IDataT, TempVals, WOutVals
    <3>15. IMerged'
      <4>1. pc[Leader] \notin Returned
        <5>1. self \in pushed /\ pc[self] # "Done"
          BY <2>6 DEF IPush, IPc
        <5>2. self \in active
          BY <5>1 DEF IPush
        <5>. QED
          BY <5>2 DEF IPush
      <4>. QED
        BY <2>6, <4>1 DEF IMerged, IPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6, <3>7, <3>8, <3>9, <3>10, <3>11, <3>12, <3>13, <3>14, <3>15
  <2>. QED
    BY <2>0, <2>1, <2>2, <2>3, <2>4, <2>5, <2>6
<1>. QED
  BY <1>1

=============================================================================
