\* timeout: 5400
-------------------------- MODULE PxHashJoin_proofs_rest --------------------------
(* StepInv lemmas: the worker cleanup path (W_cleanup, W_merge, W_pclean);
   each proved per IndInv part, a branching action per branch of its effect (P33). *)
EXTENDS PxHashJoin_proofs_base

LEMMA Step_W_cleanup == ASSUME IndInv, NEW self \in Workers, W_cleanup(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_cleanup(self)
  OBVIOUS
<1>1. IndInv'
  <2>0. \/ /\ pc[self] = "W_cleanup"
           /\ Phase = "split"
           /\ ok[self]
           /\ failed[self] = "none"
           /\ p' = ([p EXCEPT ![self] = 0])
           /\ pc' = ([pc EXCEPT ![self] = "W_merge"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_cleanup"
           /\ ~(Phase = "split" /\ ok[self] /\ failed[self] = "none")
           /\ pc' = ([pc EXCEPT ![self] = "W_pclean"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. CASE Phase = "split" /\ ok[self] /\ failed[self] = "none"
      BY <3>1, <1>0, Correct DEF W_cleanup, IFix
    <3>2. CASE ~(Phase = "split" /\ ok[self] /\ failed[self] = "none")
      BY <3>2, <1>0, Correct DEF W_cleanup, IFix
    <3>3. (Phase = "split" /\ ok[self] /\ failed[self] = "none") \/ (~(Phase = "split" /\ ok[self] /\ failed[self] = "none"))
      BY <1>0, Correct, Assm DEF W_cleanup, IErr, ErrPc
    <3>. QED
      BY <3>1, <3>2, <3>3
  <2>1. CASE /\ pc[self] = "W_cleanup"
             /\ Phase = "split"
             /\ ok[self]
             /\ failed[self] = "none"
             /\ p' = ([p EXCEPT ![self] = 0])
             /\ pc' = ([pc EXCEPT ![self] = "W_merge"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, ret, ok, matched, ended>>
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
  <2>2. CASE /\ pc[self] = "W_cleanup"
             /\ ~(Phase = "split" /\ ok[self] /\ failed[self] = "none")
             /\ pc' = ([pc EXCEPT ![self] = "W_pclean"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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

LEMMA Step_W_merge == ASSUME IndInv, NEW self \in Workers, W_merge(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_merge(self)
  OBVIOUS
<1>1. IndInv'
  <2>0. \/ /\ pc[self] = "W_merge"
           /\ p[self] < NP
           /\ temp[self][p[self]] = {}
           /\ p' = ([p EXCEPT ![self] = p[self] + 1])
           /\ pc' = ([pc EXCEPT ![self] = "W_merge"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_merge"
           /\ p[self] < NP
           /\ temp[self][p[self]] # {}
           /\ ret' = ([ret EXCEPT ![self] = "merge"])
           /\ pc' = ([pc EXCEPT ![self] = "W_fl"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ok, matched, ended>>
        \/ /\ pc[self] = "W_merge"
           /\ ~(p[self] < NP)
           /\ pc' = ([pc EXCEPT ![self] = "W_pclean"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. CASE p[self] < NP /\ temp[self][p[self]] = {}
      BY <3>1, <1>0, Correct DEF W_merge, IFix
    <3>2. CASE p[self] < NP /\ temp[self][p[self]] # {}
      BY <3>2, <1>0, Correct DEF W_merge, IFix
    <3>3. CASE ~(p[self] < NP)
      BY <3>3, <1>0, Correct DEF W_merge, IFix
    <3>4. (p[self] < NP /\ temp[self][p[self]] = {}) \/ (p[self] < NP /\ temp[self][p[self]] # {}) \/ (~(p[self] < NP))
      BY <1>0, Correct, Assm DEF W_merge, IErr, ErrPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4
  <2>1. CASE /\ pc[self] = "W_merge"
             /\ p[self] < NP
             /\ temp[self][p[self]] = {}
             /\ p' = ([p EXCEPT ![self] = p[self] + 1])
             /\ pc' = ([pc EXCEPT ![self] = "W_merge"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, ret, ok, matched, ended>>
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
  <2>2. CASE /\ pc[self] = "W_merge"
             /\ p[self] < NP
             /\ temp[self][p[self]] # {}
             /\ ret' = ([ret EXCEPT ![self] = "merge"])
             /\ pc' = ([pc EXCEPT ![self] = "W_fl"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ok, matched, ended>>
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
  <2>3. CASE /\ pc[self] = "W_merge"
             /\ ~(p[self] < NP)
             /\ pc' = ([pc EXCEPT ![self] = "W_pclean"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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

LEMMA Step_W_pclean == ASSUME IndInv, NEW self \in Workers, W_pclean(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_pclean(self)
  OBVIOUS
<1>1. IndInv'
  <2>0. \/ /\ pc[self] = "W_pclean"
           /\ Phase = "split"
           /\ temp' = ([temp EXCEPT ![self] = [q \in Parts |-> {}]])
           /\ pc' = ([pc EXCEPT ![self] = "W_end"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_pclean"
           /\ Phase = "probe"
           /\ pc' = ([pc EXCEPT ![self] = "W_end"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_pclean"
           /\ Phase = "join"
           /\ pc' = ([pc EXCEPT ![self] = "W_end"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. CASE Phase = "split"
      BY <3>1, <1>0, Correct DEF W_pclean, IFix, IDataT
    <3>2. CASE Phase = "probe"
      <4>1. /\ out' = [out EXCEPT ![self] = out[self] \cup (IF Mutant = "preserved_build" /\ ok[self] /\ ~matched[self] THEN {<<0, "b1">>} ELSE {})]
            /\ tableFreed' = (tableFreed \/ Mutant = "worker_frees_table")
            /\ pc' = [pc EXCEPT ![self] = "W_end"]
            /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, merged, hasError, mainErr, failed, intr, cancelled, freed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
        BY <3>2, <1>0 DEF W_pclean
      <4>2. (IF Mutant = "preserved_build" /\ ok[self] /\ ~matched[self] THEN {<<0, "b1">>} ELSE {}) = {}
        BY Correct
      <4>3. out' = [out EXCEPT ![self] = out[self]]
        BY <4>1, <4>2
      <4>4. out' = out
        BY <4>3 DEF IDataT
      <4>5. tableFreed' = tableFreed
        BY <4>1, Correct DEF IFree
      <4>6. pc[self] = "W_pclean"
        BY <1>0 DEF W_pclean
      <4>. QED
        BY <3>2, <4>1, <4>4, <4>5, <4>6
    <3>3. CASE Phase = "join"
      BY <3>3, <1>0, Correct DEF W_pclean, IFix, IDataT
    <3>4. (Phase = "split") \/ (Phase = "probe") \/ (Phase = "join")
      BY <1>0, Correct, Assm DEF W_pclean, IErr, ErrPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4
  <2>1. CASE /\ pc[self] = "W_pclean"
             /\ Phase = "split"
             /\ temp' = ([temp EXCEPT ![self] = [q \in Parts |-> {}]])
             /\ pc' = ([pc EXCEPT ![self] = "W_end"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
  <2>2. CASE /\ pc[self] = "W_pclean"
             /\ Phase = "probe"
             /\ pc' = ([pc EXCEPT ![self] = "W_end"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
  <2>3. CASE /\ pc[self] = "W_pclean"
             /\ Phase = "join"
             /\ pc' = ([pc EXCEPT ![self] = "W_end"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, uaf, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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

=============================================================================
