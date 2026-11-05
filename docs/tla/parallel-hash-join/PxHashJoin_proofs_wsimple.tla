\* timeout: 5400
-------------------------- MODULE PxHashJoin_proofs_wsimple --------------------------
(* StepInv lemmas: the mutant-only labels and the worker actions with one or two branches (W_start, W_err, W_swap, W_rearm, W_end);
   each proved per IndInv part, a branching action per branch of its effect (P33). *)
EXTENDS PxHashJoin_proofs_base

LEMMA Step_W_cas_write == ASSUME IndInv, NEW self \in Workers, W_cas_write(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_cas_write(self)
  OBVIOUS
<1>1. IndInv'
  BY <1>0 DEF W_cas_write, IPc   \* a mutant-only label: the correct variant never stands there
<1>. QED
  BY <1>1

LEMMA Step_W_fa_write == ASSUME IndInv, NEW self \in Workers, W_fa_write(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_fa_write(self)
  OBVIOUS
<1>1. IndInv'
  BY <1>0 DEF W_fa_write, IPc   \* a mutant-only label: the correct variant never stands there
<1>. QED
  BY <1>1

LEMMA Step_W_fl_write == ASSUME IndInv, NEW self \in Workers, W_fl_write(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_fl_write(self)
  OBVIOUS
<1>1. IndInv'
  BY <1>0 DEF W_fl_write, IPc   \* a mutant-only label: the correct variant never stands there
<1>. QED
  BY <1>1

LEMMA Step_W_start == ASSUME IndInv, NEW self \in Workers, W_start(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_start(self)
  OBVIOUS
<1>1. IndInv'
  <2>0. \/ /\ pc[self] = "W_start"
           /\ self \in pushed
           /\ pc' = ([pc EXCEPT ![self] = "W_check"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    BY <1>0, Correct DEF W_start, IFix
  <2>1. CASE /\ pc[self] = "W_start"
             /\ self \in pushed
             /\ pc' = ([pc EXCEPT ![self] = "W_check"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
      BY <2>1 DEF IStart, IPc
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
  <2>. QED
    BY <2>0, <2>1
<1>. QED
  BY <1>1

LEMMA Step_W_err == ASSUME IndInv, NEW self \in Workers, W_err(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_err(self)
  OBVIOUS
<1>1. IndInv'
  <2>0. \/ /\ pc[self] = "W_err"
           /\ hasError' = (TRUE)
           /\ uaf' = (uaf \/ freed)
           /\ won' = ([won EXCEPT ![self] = ~hasError])
           /\ pc' = ([pc EXCEPT ![self] = "W_swap"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, tmp, p, ret, ok, matched, ended>>
    BY <1>0, Correct DEF W_err, IFix
  <2>1. CASE /\ pc[self] = "W_err"
             /\ hasError' = (TRUE)
             /\ uaf' = (uaf \/ freed)
             /\ won' = ([won EXCEPT ![self] = ~hasError])
             /\ pc' = ([pc EXCEPT ![self] = "W_swap"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, tmp, p, ret, ok, matched, ended>>
    <3>1. IPc'
      BY <2>1 DEF IPc
    <3>2. IKey'
      BY <2>1 DEF IKey
    <3>3. IPush'
      BY <2>1 DEF IPush, IPc
    <3>4. IFix'
      BY <2>1 DEF IFix
    <3>5. IErr'
      <4>1. failed[self] # "none" /\ ~won[self]
        BY <2>1 DEF IErr
      <4>2. ~hasError => \A x \in Workers : ~won[x]
        BY DEF IErr
      <4>3. hasError => \E x \in Workers : won[x] /\ x # self
        BY <4>1 DEF IErr
      <4>. QED
        BY <2>1, <4>1, <4>2, <4>3 DEF IErr, IPc
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
  <2>. QED
    BY <2>0, <2>1
<1>. QED
  BY <1>1

LEMMA Step_W_swap == ASSUME IndInv, NEW self \in Workers, W_swap(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_swap(self)
  OBVIOUS
<1>1. IndInv'
  <2>0. \/ /\ pc[self] = "W_swap"
           /\ won[self]
           /\ uaf' = (uaf \/ freed)
           /\ mainErr' = (failed[self])
           /\ pc' = ([pc EXCEPT ![self] = "W_rearm"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_swap"
           /\ ~won[self]
           /\ uaf' = (uaf \/ freed)
           /\ pc' = ([pc EXCEPT ![self] = "W_rearm"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. CASE won[self]
      BY <3>1, <1>0, Correct DEF W_swap, IFix
    <3>2. CASE ~won[self]
      BY <3>2, <1>0, Correct DEF W_swap, IFix
    <3>3. (won[self]) \/ (~won[self])
      BY <1>0, Correct, Assm DEF W_swap, IErr, ErrPc
    <3>. QED
      BY <3>1, <3>2, <3>3
  <2>1. CASE /\ pc[self] = "W_swap"
             /\ won[self]
             /\ uaf' = (uaf \/ freed)
             /\ mainErr' = (failed[self])
             /\ pc' = ([pc EXCEPT ![self] = "W_rearm"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
  <2>2. CASE /\ pc[self] = "W_swap"
             /\ ~won[self]
             /\ uaf' = (uaf \/ freed)
             /\ pc' = ([pc EXCEPT ![self] = "W_rearm"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
  <2>. QED
    BY <2>0, <2>1, <2>2
<1>. QED
  BY <1>1

LEMMA Step_W_rearm == ASSUME IndInv, NEW self \in Workers, W_rearm(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_rearm(self)
  OBVIOUS
<1>1. IndInv'
  <2>0. \/ /\ pc[self] = "W_rearm"
           /\ intr' = (TRUE)
           /\ pc' = ([pc EXCEPT ![self] = "W_cleanup"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    BY <1>0, Correct DEF W_rearm, IFix
  <2>1. CASE /\ pc[self] = "W_rearm"
             /\ intr' = (TRUE)
             /\ pc' = ([pc EXCEPT ![self] = "W_cleanup"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
  <2>. QED
    BY <2>0, <2>1
<1>. QED
  BY <1>1

LEMMA Step_W_end == ASSUME IndInv, NEW self \in Workers, W_end(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_end(self)
  OBVIOUS
<1>1. IndInv'
  <2>0. \/ /\ pc[self] = "W_end"
           /\ active' = (active \ {self})
           /\ uaf' = (uaf \/ freed)
           /\ pc' = ([pc EXCEPT ![self] = "Done"])
           /\ UNCHANGED <<key, pushed, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    BY <1>0, Correct DEF W_end, IFix
  <2>1. CASE /\ pc[self] = "W_end"
             /\ active' = (active \ {self})
             /\ uaf' = (uaf \/ freed)
             /\ pc' = ([pc EXCEPT ![self] = "Done"])
             /\ UNCHANGED <<key, pushed, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. IPc'
      BY <2>1 DEF IPc
    <3>2. IKey'
      BY <2>1 DEF IKey
    <3>3. IPush'
      <4>1. self \in pushed
        BY <2>1 DEF IPush, IPc
      <4>. QED
        BY <2>1, <4>1 DEF IPush, IPc
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
  <2>. QED
    BY <2>0, <2>1
<1>. QED
  BY <1>1

=============================================================================
