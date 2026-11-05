\* timeout: 5400
-------------------------- MODULE PxHashJoin_proofs_proc --------------------------
(* StepInv lemmas: the unit work and the partition flush (W_proc, W_fl);
   each proved per IndInv part, a branching action per branch of its effect (P33). *)
EXTENDS PxHashJoin_proofs_base

LEMMA Step_W_proc == ASSUME IndInv, NEW self \in Workers, W_proc(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_proc(self)
  OBVIOUS
<1>1. IndInv'
  <2>0. \/ /\ pc[self] = "W_proc"
           /\ failed' = ([failed EXCEPT ![self] = "err"])
           /\ uaf' = (uaf \/ freed)
           /\ pc' = ([pc EXCEPT ![self] = "W_err"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_proc"
           /\ Phase = "split"
           /\ PartOf(key[u[self]]) < NP
           /\ uaf' = (uaf \/ freed \/ (Phase = "probe" /\ tableFreed))
           /\ temp' = ([temp EXCEPT ![self][PartOf(key[u[self]])] = temp[self][PartOf(key[u[self]])] \cup {u[self]}])
           /\ pc' = ([pc EXCEPT ![self] = "W_check"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_proc"
           /\ Phase = "split"
           /\ PartOf(key[u[self]]) < NP
           /\ uaf' = (uaf \/ freed \/ (Phase = "probe" /\ tableFreed))
           /\ temp' = ([temp EXCEPT ![self][PartOf(key[u[self]])] = temp[self][PartOf(key[u[self]])] \cup {u[self]}])
           /\ p' = ([p EXCEPT ![self] = PartOf(key[u[self]])])
           /\ ret' = ([ret EXCEPT ![self] = "check"])
           /\ pc' = ([pc EXCEPT ![self] = "W_fl"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, ok, matched, ended>>
        \/ /\ pc[self] = "W_proc"
           /\ Phase = "split"
           /\ ~(PartOf(key[u[self]]) < NP)
           /\ uaf' = (uaf \/ freed \/ (Phase = "probe" /\ tableFreed))
           /\ pc' = ([pc EXCEPT ![self] = "W_check"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_proc"
           /\ Phase = "probe"
           /\ uaf' = (uaf \/ freed \/ (Phase = "probe" /\ tableFreed))
           /\ out' = ([out EXCEPT ![self] = out[self] \cup ProbeOut(u[self])])
           /\ pc' = ([pc EXCEPT ![self] = "W_check"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_proc"
           /\ Phase = "join"
           /\ uaf' = (uaf \/ freed \/ (Phase = "probe" /\ tableFreed))
           /\ out' = ([out EXCEPT ![self] = out[self] \cup {<<u[self], "ctx">>}])
           /\ pc' = ([pc EXCEPT ![self] = "W_check"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. CASE failed'[self] = "err"
      BY <3>1, <1>0, Correct DEF W_proc, IFix, IErr, ErrPc
    <3>2. CASE failed'[self] # "err" /\ Phase = "split" /\ PartOf(key[u[self]]) < NP
      BY <3>2, <1>0, Correct DEF W_proc, IFix, IErr, ErrPc
    <3>3. CASE failed'[self] # "err" /\ Phase = "split" /\ ~(PartOf(key[u[self]]) < NP)
      BY <3>3, <1>0, Correct DEF W_proc, IFix, IErr, ErrPc
    <3>4. CASE failed'[self] # "err" /\ Phase = "probe"
      BY <3>4, <1>0, Correct DEF W_proc, IFix, IErr, ErrPc
    <3>5. CASE failed'[self] # "err" /\ Phase = "join"
      BY <3>5, <1>0, Correct DEF W_proc, IFix, IErr, ErrPc
    <3>6. (failed'[self] = "err") \/ (failed'[self] # "err" /\ Phase = "split" /\ PartOf(key[u[self]]) < NP) \/ (failed'[self] # "err" /\ Phase = "split" /\ ~(PartOf(key[u[self]]) < NP)) \/ (failed'[self] # "err" /\ Phase = "probe") \/ (failed'[self] # "err" /\ Phase = "join")
      BY <1>0, Correct, Assm DEF W_proc, IErr, ErrPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4, <3>5, <3>6
  <2>1. CASE /\ pc[self] = "W_proc"
             /\ failed' = ([failed EXCEPT ![self] = "err"])
             /\ uaf' = (uaf \/ freed)
             /\ pc' = ([pc EXCEPT ![self] = "W_err"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
  <2>2. CASE /\ pc[self] = "W_proc"
             /\ Phase = "split"
             /\ PartOf(key[u[self]]) < NP
             /\ uaf' = (uaf \/ freed \/ (Phase = "probe" /\ tableFreed))
             /\ temp' = ([temp EXCEPT ![self][PartOf(key[u[self]])] = temp[self][PartOf(key[u[self]])] \cup {u[self]}])
             /\ pc' = ([pc EXCEPT ![self] = "W_check"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
      BY <2>2, PartOfType DEF ILocal, IPc, IKey
    <3>13. IStart'
      <4>1. \A w \in Workers : pc'[w] = "W_start" => w # self /\ pc[w] = "W_start"
        BY <2>2 DEF IPc
      <4>2. \A w \in Workers \ {self} : ok'[w] = ok[w] /\ won'[w] = won[w] /\ failed'[w] = failed[w]
        BY <2>2 DEF ILocal, IErr
      <4>. QED
        BY <2>2, <4>1, <4>2 DEF IStart
    <3>14. IDataT'
      <4>1. PartOf(key[u[self]]) \in Parts /\ u[self] \in Units
        BY <2>2, PartOfType DEF IKey, ILocal
      <4>. QED
        BY <2>2, <4>1 DEF IDataT, TempVals
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
  <2>3. CASE /\ pc[self] = "W_proc"
             /\ Phase = "split"
             /\ PartOf(key[u[self]]) < NP
             /\ uaf' = (uaf \/ freed \/ (Phase = "probe" /\ tableFreed))
             /\ temp' = ([temp EXCEPT ![self][PartOf(key[u[self]])] = temp[self][PartOf(key[u[self]])] \cup {u[self]}])
             /\ p' = ([p EXCEPT ![self] = PartOf(key[u[self]])])
             /\ ret' = ([ret EXCEPT ![self] = "check"])
             /\ pc' = ([pc EXCEPT ![self] = "W_fl"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, ok, matched, ended>>
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
      BY <2>3, PartOfType DEF ILocal, IPc, IKey
    <3>13. IStart'
      <4>1. \A w \in Workers : pc'[w] = "W_start" => w # self /\ pc[w] = "W_start"
        BY <2>3 DEF IPc
      <4>2. \A w \in Workers \ {self} : ok'[w] = ok[w] /\ won'[w] = won[w] /\ failed'[w] = failed[w]
        BY <2>3 DEF ILocal, IErr
      <4>. QED
        BY <2>3, <4>1, <4>2 DEF IStart
    <3>14. IDataT'
      <4>1. PartOf(key[u[self]]) \in Parts /\ u[self] \in Units
        BY <2>3, PartOfType DEF IKey, ILocal
      <4>. QED
        BY <2>3, <4>1 DEF IDataT, TempVals
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
  <2>4. CASE /\ pc[self] = "W_proc"
             /\ Phase = "split"
             /\ ~(PartOf(key[u[self]]) < NP)
             /\ uaf' = (uaf \/ freed \/ (Phase = "probe" /\ tableFreed))
             /\ pc' = ([pc EXCEPT ![self] = "W_check"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
      BY <2>4 DEF IDisp, IPc
    <3>11. ICnt'
      BY <2>4 DEF ICnt, IDisp, Handed
    <3>12. ILocal'
      BY <2>4 DEF ILocal, IPc
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
  <2>5. CASE /\ pc[self] = "W_proc"
             /\ Phase = "probe"
             /\ uaf' = (uaf \/ freed \/ (Phase = "probe" /\ tableFreed))
             /\ out' = ([out EXCEPT ![self] = out[self] \cup ProbeOut(u[self])])
             /\ pc' = ([pc EXCEPT ![self] = "W_check"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
      BY <2>5 DEF IDisp, IPc
    <3>11. ICnt'
      BY <2>5 DEF ICnt, IDisp, Handed
    <3>12. ILocal'
      BY <2>5 DEF ILocal, IPc
    <3>13. IStart'
      <4>1. \A w \in Workers : pc'[w] = "W_start" => w # self /\ pc[w] = "W_start"
        BY <2>5 DEF IPc
      <4>2. \A w \in Workers \ {self} : ok'[w] = ok[w] /\ won'[w] = won[w] /\ failed'[w] = failed[w]
        BY <2>5 DEF ILocal, IErr
      <4>. QED
        BY <2>5, <4>1, <4>2 DEF IStart
    <3>14. IDataT'
      <4>1. ProbeOut(u[self]) \subseteq Units \X {"b1", "-"}
        BY <2>5, ProbeOutType DEF ILocal
      <4>. QED
        BY <2>5, <4>1 DEF IDataT, WOutVals
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
  <2>6. CASE /\ pc[self] = "W_proc"
             /\ Phase = "join"
             /\ uaf' = (uaf \/ freed \/ (Phase = "probe" /\ tableFreed))
             /\ out' = ([out EXCEPT ![self] = out[self] \cup {<<u[self], "ctx">>}])
             /\ pc' = ([pc EXCEPT ![self] = "W_check"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
      <4>1. u[self] \in Units
        BY DEF ILocal
      <4>. QED
        BY <2>6, <4>1 DEF IDataT, WOutVals
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

LEMMA Step_W_fl == ASSUME IndInv, NEW self \in Workers, W_fl(self) PROVE IndInv'
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>0. W_fl(self)
  OBVIOUS
<1>1. IndInv'
  <2>0. \/ /\ pc[self] = "W_fl"
           /\ uaf' = (uaf \/ freed)
           /\ failed' = ([failed EXCEPT ![self] = "err"])
           /\ pc' = ([pc EXCEPT ![self] = "W_err"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_fl"
           /\ ret[self] = "merge"
           /\ uaf' = (uaf \/ freed)
           /\ parts' = ([parts EXCEPT ![p[self]] = IF parts[p[self]] # {} THEN parts[p[self]] \cup temp[self][p[self]] ELSE temp[self][p[self]]])
           /\ temp' = ([temp EXCEPT ![self][p[self]] = {}])
           /\ p' = ([p EXCEPT ![self] = p[self] + 1])
           /\ pc' = ([pc EXCEPT ![self] = "W_merge"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, ret, ok, matched, ended>>
        \/ /\ pc[self] = "W_fl"
           /\ ret[self] # "merge"
           /\ uaf' = (uaf \/ freed)
           /\ parts' = ([parts EXCEPT ![p[self]] = IF parts[p[self]] # {} THEN parts[p[self]] \cup temp[self][p[self]] ELSE temp[self][p[self]]])
           /\ temp' = ([temp EXCEPT ![self][p[self]] = {}])
           /\ pc' = ([pc EXCEPT ![self] = "W_check"])
           /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
    <3>1. CASE failed'[self] = "err"
      BY <3>1, <1>0, Correct DEF W_fl, IFix, IErr, ErrPc
    <3>2. CASE failed'[self] # "err" /\ ret[self] = "merge"
      BY <3>2, <1>0, Correct DEF W_fl, IFix, IErr, ErrPc
    <3>3. CASE failed'[self] # "err" /\ ret[self] # "merge"
      BY <3>3, <1>0, Correct DEF W_fl, IFix, IErr, ErrPc
    <3>4. (failed'[self] = "err") \/ (failed'[self] # "err" /\ ret[self] = "merge") \/ (failed'[self] # "err" /\ ret[self] # "merge")
      BY <1>0, Correct, Assm DEF W_fl, IErr, ErrPc
    <3>. QED
      BY <3>1, <3>2, <3>3, <3>4
  <2>1. CASE /\ pc[self] = "W_fl"
             /\ uaf' = (uaf \/ freed)
             /\ failed' = ([failed EXCEPT ![self] = "err"])
             /\ pc' = ([pc EXCEPT ![self] = "W_err"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, out, merged, hasError, mainErr, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
  <2>2. CASE /\ pc[self] = "W_fl"
             /\ ret[self] = "merge"
             /\ uaf' = (uaf \/ freed)
             /\ parts' = ([parts EXCEPT ![p[self]] = IF parts[p[self]] # {} THEN parts[p[self]] \cup temp[self][p[self]] ELSE temp[self][p[self]]])
             /\ temp' = ([temp EXCEPT ![self][p[self]] = {}])
             /\ p' = ([p EXCEPT ![self] = p[self] + 1])
             /\ pc' = ([pc EXCEPT ![self] = "W_merge"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, ret, ok, matched, ended>>
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
      <4>1. p[self] \in Parts /\ Phase = "split"
        BY <2>2 DEF ILocal
      <4>. QED
        BY <2>2, <4>1 DEF IDataT, TempVals
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
  <2>3. CASE /\ pc[self] = "W_fl"
             /\ ret[self] # "merge"
             /\ uaf' = (uaf \/ freed)
             /\ parts' = ([parts EXCEPT ![p[self]] = IF parts[p[self]] # {} THEN parts[p[self]] \cup temp[self][p[self]] ELSE temp[self][p[self]]])
             /\ temp' = ([temp EXCEPT ![self][p[self]] = {}])
             /\ pc' = ([pc EXCEPT ![self] = "W_check"])
             /\ UNCHANGED <<key, pushed, active, next, membufClaimed, owner, cnt, out, merged, hasError, mainErr, failed, intr, cancelled, freed, tableFreed, res, final, fellBack, mb, u, won, tmp, p, ret, ok, matched, ended>>
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
      <4>1. p[self] \in Parts /\ Phase = "split"
        BY <2>3 DEF ILocal
      <4>. QED
        BY <2>3, <4>1 DEF IDataT, TempVals
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
