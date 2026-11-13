------------------------- MODULE PxSysopGate_proofs -------------------------
(* TLAPS proof that IndInv is an inductive invariant of the head gate (PR 8424) for any set
   of threads, any task tree and any operation bound, and that it implies C1 (NoForeignSerial)
   and C3 (MutEx). Init => IndInv and IndInv /\ [Next]_vars => IndInv' are the premises of the
   rule INV1; Safe concludes Spec => []IndInv through PTL. *)
EXTENDS PxSysopGate, TLAPS

ASSUME Correct == Mutant = "none" /\ ParentLate = FALSE

LEMMA Basics == /\ NoThr \notin Thr /\ Root # Q /\ Root \in Thr /\ Q \in Thr
                /\ Par[Root] = NoThr /\ Par[Q] = NoThr
  BY Assm DEF NoThr, Root, Q

\* the head's decision
LEMMA BlockHead == \A t \in Thr : Block(t) <=> (owner = NoThr \/ owner = t \/ owner \in Involved)
  BY Correct DEF Block

THEOREM InitInv == Init => IndInv
  BY Assm, Basics DEF Init, IndInv, TypeOK, Labels, Reasons, R_ended, R_late, R_holder, R_cnt, R_depth,
     R_owner, R_q, R_spwait, R_spawn, R_dec, Lv, LvBy, HBy, Running

\* facts every action lemma uses
LEMMA HolderFacts == ASSUME IndInv PROVE
  /\ \A u \in Thr : Lv(u) \in Nat /\ (Lv(u) = 0 <=> (h[u] = 0 /\ pc[u] \notin {"inc", "rel"}))
  /\ owner = NoThr => (\A u \in Thr : Lv(u) = 0) /\ cnt = 0 /\ depth = 0
  /\ \A u \in Thr : h[u] > 0 => h[u] <= depth
  /\ (pc[Root] = "spwait" /\ h[Root] > 0) => owner = Root
  /\ \A u \in Thr : (Lv(u) > 0 /\ u # Q) => u = owner
  <1> USE Basics DEF IndInv, TypeOK, Labels
  <1>1. \A u \in Thr : Lv(u) \in Nat /\ (Lv(u) = 0 <=> (h[u] = 0 /\ pc[u] \notin {"inc", "rel"}))
    BY DEF Lv
  <1>2. owner = NoThr => (\A u \in Thr : Lv(u) = 0)
    <2> SUFFICES ASSUME owner = NoThr, NEW u \in Thr PROVE Lv(u) = 0
      OBVIOUS
    <2>1. ~(Lv(u) > 0)
      BY DEF R_holder
    <2>. QED
      BY <1>1, <2>1
  <1>3. owner = NoThr => cnt = 0 /\ depth = 0
    BY DEF R_cnt, R_depth, LvBy, HBy
  <1>4. \A u \in Thr : h[u] > 0 => h[u] <= depth
    <2> SUFFICES ASSUME NEW u \in Thr, h[u] > 0 PROVE h[u] <= depth
      OBVIOUS
    <2>1. Lv(u) > 0
      BY <1>1
    <2>2. u = owner \/ (u = Q /\ owner = Root)
      BY <2>1 DEF R_holder
    <2>3. owner # NoThr
      BY <2>2
    <2>4. depth = h[owner] + (IF owner = Root THEN h[Q] ELSE 0)
      BY <2>3 DEF R_depth, HBy
    <2>. QED
      BY <2>2, <2>4
  <1>5. (pc[Root] = "spwait" /\ h[Root] > 0) => owner = Root
    BY <1>1 DEF R_holder
  <1>6. \A u \in Thr : (Lv(u) > 0 /\ u # Q) => u = owner
    BY DEF R_holder
  <1>. QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6

LEMMA L_Want == ASSUME IndInv, NEW t \in Thr, Want(t) PROVE IndInv'
  <1> USE Basics DEF IndInv, TypeOK, Labels
  <1>1. pc[t] = "ready" /\ pc' = [pc EXCEPT ![t] = "acq"]
        /\ UNCHANGED <<owner, cnt, depth, h, late, decn, reason, spawnOK, decH, reent>>
        /\ ops' \in [Thr -> Nat]
    BY DEF Want
  <1>2. \A u \in Thr : Lv(u)' = Lv(u) /\ (Running(u)' <=> Running(u))
    BY <1>1 DEF Lv, Running
  <1>3. pc'[Root] = "spwait" <=> pc[Root] = "spwait"
    BY <1>1
  <1>. QED
    BY <1>1, <1>2, <1>3 DEF R_ended, R_late, R_holder, R_cnt, R_depth, R_owner, R_q, R_spwait, R_spawn,
       R_dec, LvBy, HBy, RunKids

LEMMA L_Acq == ASSUME IndInv, NEW t \in Thr, Acq(t) PROVE IndInv'
  <1> USE Basics DEF IndInv, TypeOK, Labels
  <1>1. /\ pc[t] = "acq" /\ Lockable(t)
        /\ owner' = (IF owner = NoThr THEN t ELSE owner) /\ cnt' = cnt + 1
        /\ pc' = [pc EXCEPT ![t] = "inc"]
        /\ reent' \in BOOLEAN
        /\ UNCHANGED <<depth, h, late, decn, reason, spawnOK, decH, ops>>
    BY DEF Acq, AcqEffect
  <1>2. Lv(t) = h[t] /\ Lv(t)' = h[t] + 1 /\ \A u \in Thr \ {t} : Lv(u)' = Lv(u)
    BY <1>1 DEF Lv
  <1>3. \A u \in Thr : Running(u)' <=> Running(u)
    BY <1>1 DEF Running
  <1>4. pc'[Root] = "spwait" <=> pc[Root] = "spwait"
    BY <1>1
  <1>5. CASE owner = NoThr
    <2>1. \A u \in Thr : Lv(u) = 0 /\ h[u] = 0
      BY <1>5, HolderFacts DEF Lv
    <2>2. owner' = t /\ cnt' = 1 /\ depth = 0
      BY <1>1, <1>5, HolderFacts
    <2>3. R_holder' /\ R_owner'
      BY <1>2, <2>1, <2>2 DEF R_holder, R_owner
    <2>4. R_cnt'
      BY <1>2, <2>1, <2>2 DEF R_cnt, LvBy
    <2>5. R_depth'
      BY <1>1, <2>1, <2>2 DEF R_depth, HBy
    <2>. QED
      BY <1>1, <1>3, <1>4, <2>3, <2>4, <2>5 DEF R_ended, R_late, R_q, R_spwait, R_spawn, R_dec, Running
  <1>6. CASE owner = t
    <2>1. owner' = t
      BY <1>1, <1>6
    <2>2. R_holder' /\ R_owner'
      BY <1>2, <1>4, <2>1, <1>6 DEF R_holder, R_owner
    <2>3. R_cnt'
      <3>1. cnt = Lv(t) + (IF t = Root THEN Lv(Q) ELSE 0)
        BY <1>6 DEF R_cnt, LvBy
      <3>2. t # Q => Lv(Q)' = Lv(Q)
        BY <1>2
      <3>. QED
        BY <1>1, <1>2, <2>1, <3>1, <3>2, HolderFacts DEF R_cnt, LvBy
    <2>4. R_depth'
      BY <1>1, <2>1, <1>6 DEF R_depth, HBy
    <2>. QED
      BY <1>1, <1>3, <1>4, <2>2, <2>3, <2>4 DEF R_ended, R_late, R_q, R_spwait, R_spawn, R_dec, Running
  <1>7. CASE owner # NoThr /\ owner # t
    <2>1. owner = Root /\ pc[Root] = "spwait" /\ owner' = Root
      BY <1>1, <1>7 DEF Lockable, Involved
    <2>2. h[Root] > 0
      BY <2>1, HolderFacts DEF R_owner, Lv
    <2>3. t = Q
      <3>1. Running(t)
        BY <1>1 DEF Running
      <3>2. t # Root
        BY <1>1, <2>1
      <3>. QED
        BY <2>1, <2>2, <3>1, <3>2 DEF R_spwait
    <2>4. R_holder' /\ R_owner'
      BY <1>2, <1>4, <2>1, <2>3, HolderFacts DEF R_holder, R_owner
    <2>5. R_cnt'
      BY <1>1, <1>2, <2>1, <2>3, HolderFacts DEF R_cnt, LvBy
    <2>6. R_depth'
      BY <1>1, <2>1 DEF R_depth, HBy
    <2>. QED
      BY <1>1, <1>3, <1>4, <2>4, <2>5, <2>6 DEF R_ended, R_late, R_q, R_spwait, R_spawn, R_dec, Running
  <1>. QED
    BY <1>5, <1>6, <1>7

LEMMA L_Inc == ASSUME IndInv, NEW t \in Thr, Inc(t) PROVE IndInv'
  <1> USE Basics DEF IndInv, TypeOK, Labels
  <1>1. /\ pc[t] = "inc" /\ pc' = [pc EXCEPT ![t] = "ready"]
        /\ depth' = depth + 1 /\ h' = [h EXCEPT ![t] = @ + 1]
        /\ late' \in [Thr -> Nat] /\ late'[t] <= late[t] + 1 /\ \A u \in Thr \ {t} : late'[u] = late[u]
        /\ UNCHANGED <<owner, cnt, ops, decn, reason, spawnOK, decH, reent>>
    BY DEF Inc
  <1>2. \A u \in Thr : Lv(u)' = Lv(u)
    BY <1>1 DEF Lv
  <1>3. \A u \in Thr : Running(u)' <=> Running(u)
    BY <1>1 DEF Running
  <1>4. pc'[Root] # "spwait" /\ pc[Root] # "spwait" => (pc'[Root] = "spwait" <=> pc[Root] = "spwait")
    OBVIOUS
  <1>5. pc'[Root] = "spwait" <=> pc[Root] = "spwait"
    BY <1>1
  <1>6. t = owner \/ (t = Q /\ owner = Root /\ pc[Root] = "spwait")
    BY <1>1 DEF R_holder, Lv
  <1>7. R_depth'
    <2>1. owner # NoThr
      BY <1>6
    <2>. QED
      BY <1>1, <1>6, <2>1 DEF R_depth, HBy
  <1>8. R_spwait'
    <2>1. pc'[Root] = "spwait" => h'[Root] = h[Root]
      BY <1>1
    <2>. QED
      BY <1>1, <1>3, <1>5, <2>1 DEF R_spwait
  <1>9. R_late'
    BY <1>1 DEF R_late
  <1>. QED
    BY <1>1, <1>2, <1>3, <1>5, <1>7, <1>8, <1>9 DEF R_ended, R_holder, R_cnt, R_owner, R_q, R_spawn, R_dec,
       LvBy, Running

LEMMA L_Dec == ASSUME IndInv, NEW t \in Thr, Dec(t) PROVE IndInv'
  <1> USE Basics DEF IndInv, TypeOK, Labels
  <1>1. /\ pc[t] = "ready" /\ h[t] > 0 /\ pc' = [pc EXCEPT ![t] = "rel"]
        /\ depth' = depth - 1 /\ h' = [h EXCEPT ![t] = @ - 1]
        /\ late' = (IF late[t] > 0 THEN [late EXCEPT ![t] = @ - 1] ELSE late)
        /\ UNCHANGED <<owner, cnt, ops, decn, reason, spawnOK, decH, reent>>
    BY DEF Dec
  <1>2. depth >= h[t] /\ depth \in Nat
    BY <1>1, HolderFacts
  <1>3. \A u \in Thr : Lv(u)' = Lv(u)
    BY <1>1 DEF Lv
  <1>4. \A u \in Thr : Running(u)' <=> Running(u)
    BY <1>1 DEF Running
  <1>5. pc'[Root] = "spwait" <=> pc[Root] = "spwait"
    BY <1>1
  <1>6. t = owner \/ (t = Q /\ owner = Root /\ pc[Root] = "spwait")
    BY <1>1 DEF R_holder, Lv
  <1>7. R_depth'
    BY <1>1, <1>6 DEF R_depth, HBy
  <1>8. R_spwait'
    <2>1. pc'[Root] = "spwait" => h'[Root] = h[Root]
      BY <1>1
    <2>. QED
      BY <1>1, <1>4, <1>5, <2>1 DEF R_spwait
  <1>9. R_late' /\ R_ended'
    BY <1>1 DEF R_late, R_ended
  <1>10. TypeOK'
    BY <1>1, <1>2
  <1>. QED
    BY <1>1, <1>3, <1>4, <1>5, <1>7, <1>8, <1>9, <1>10 DEF R_holder, R_cnt, R_owner, R_q, R_spawn, R_dec,
       LvBy, Running

LEMMA L_Rel == ASSUME IndInv, NEW t \in Thr, Rel(t) PROVE IndInv'
  <1> USE Basics DEF IndInv, TypeOK, Labels
  <1>1. /\ pc[t] = "rel" /\ pc' = [pc EXCEPT ![t] = "ready"]
        /\ cnt' = cnt - 1 /\ owner' = (IF cnt = 1 THEN NoThr ELSE owner)
        /\ UNCHANGED <<depth, h, late, ops, decn, reason, spawnOK, decH, reent>>
    BY DEF Rel
  <1>2. Lv(t) = h[t] + 1 /\ Lv(t)' = h[t] /\ \A u \in Thr \ {t} : Lv(u)' = Lv(u)
    BY <1>1 DEF Lv
  <1>3. \A u \in Thr : Running(u)' <=> Running(u)
    BY <1>1 DEF Running
  <1>4. pc'[Root] = "spwait" <=> pc[Root] = "spwait"
    BY <1>1
  <1>5. t = owner \/ (t = Q /\ owner = Root /\ pc[Root] = "spwait")
    BY <1>1, <1>2 DEF R_holder
  <1>6. CASE t = owner /\ cnt = 1
    <2>1. owner' = NoThr /\ cnt' = 0
      BY <1>1, <1>6
    <2>2. Lv(t) = 1 /\ h[t] = 0 /\ (t = Root => Lv(Q) = 0)
      BY <1>2, <1>6, HolderFacts DEF R_cnt, LvBy
    <2>3. \A u \in Thr : Lv(u)' = 0
      <3> SUFFICES ASSUME NEW u \in Thr PROVE Lv(u)' = 0
        OBVIOUS
      <3>1. CASE u = t
        BY <1>2, <2>2, <3>1
      <3>2. CASE u # t
        <4>1. Lv(u) = 0
          BY <1>6, <2>2, <3>2, HolderFacts DEF R_holder
        <4>. QED
          BY <1>2, <3>2, <4>1
      <3>. QED
        BY <3>1, <3>2
    <2>4. depth = 0
      BY <1>6, <2>2, HolderFacts DEF R_depth, HBy, Lv
    <2>5. TypeOK'
      BY <1>1, <2>1
    <2>6. R_holder' /\ R_owner' /\ R_cnt' /\ R_depth'
      BY <1>1, <2>1, <2>3, <2>4 DEF R_holder, R_owner, R_cnt, R_depth, LvBy, HBy
    <2>7. \A u \in Thr : h'[u] = 0
      <3> SUFFICES ASSUME NEW u \in Thr PROVE h'[u] = 0
        OBVIOUS
      <3>1. Lv(u)' = 0 /\ h'[u] = h[u] /\ h[u] \in Nat
        BY <1>1, <2>3
      <3>. QED
        BY <3>1 DEF Lv
    <2>8. R_ended' /\ R_late' /\ R_spawn' /\ R_dec'
      BY <1>1 DEF R_ended, R_late, R_spawn, R_dec
    <2>9. R_q' /\ R_spwait'
      BY <1>1, <1>3, <1>4 DEF R_q, R_spwait
    <2>. QED
      BY <2>5, <2>6, <2>8, <2>9, <1>1
  <1>7. CASE t = owner /\ cnt # 1
    <2>1. owner' = t /\ cnt' = cnt - 1
      BY <1>1, <1>7
    <2>2. t = Root => Lv(Q) = 0
      BY <1>1, HolderFacts DEF R_holder
    <2>3. cnt = Lv(t) + (IF t = Root THEN Lv(Q) ELSE 0) /\ Lv(t) >= 2
      BY <1>2, <1>7, <2>2, HolderFacts DEF R_cnt, LvBy
    <2>4. Lv(t)' >= 1
      BY <1>2, <2>3
    <2>5. t # Q => Lv(Q)' = Lv(Q)
      BY <1>2
    <2>6. R_holder' /\ R_owner'
      BY <1>2, <1>4, <2>1, <2>4, <1>7 DEF R_holder, R_owner
    <2>7. R_cnt'
      BY <1>2, <2>1, <2>2, <2>3, <2>5, HolderFacts DEF R_cnt, LvBy
    <2>8. R_depth'
      BY <1>1, <2>1, <1>7 DEF R_depth, HBy
    <2>9. TypeOK'
      <3>1. cnt >= 2 /\ cnt \in Nat
        BY <2>3, HolderFacts
      <3>. QED
        BY <1>1, <2>1, <3>1
    <2>. QED
      BY <1>1, <1>3, <1>4, <2>6, <2>7, <2>8, <2>9 DEF R_ended, R_late, R_q, R_spwait, R_spawn, R_dec
  <1>8. CASE t # owner
    <2>1. t = Q /\ owner = Root /\ pc[Root] = "spwait"
      BY <1>5, <1>8
    <2>2. Lv(Root) >= 1 /\ cnt = Lv(Root) + Lv(Q) /\ cnt >= 2
      BY <1>2, <2>1, HolderFacts DEF R_owner, R_cnt, LvBy
    <2>3. owner' = Root /\ cnt' = cnt - 1 /\ Lv(Root)' = Lv(Root)
      BY <1>1, <1>2, <2>1, <2>2
    <2>4. R_holder' /\ R_owner'
      BY <1>2, <1>4, <2>1, <2>3 DEF R_holder, R_owner
    <2>5. R_cnt'
      <3>1. Lv(Q)' = Lv(Q) - 1 /\ Lv(Q) >= 1
        BY <1>2, <2>1
      <3>2. LvBy(owner)' = Lv(Root)' + Lv(Q)'
        BY <2>3 DEF LvBy
      <3>3. Lv(Root) \in Nat /\ Lv(Q) \in Nat
        BY HolderFacts
      <3>. QED
        BY <1>1, <2>2, <2>3, <3>1, <3>2, <3>3 DEF R_cnt
    <2>6. R_depth'
      BY <1>1, <2>3, <2>1 DEF R_depth, HBy
    <2>7. TypeOK'
      BY <1>1, <2>2, <2>3
    <2>. QED
      BY <1>1, <1>3, <1>4, <2>4, <2>5, <2>6, <2>7 DEF R_ended, R_late, R_q, R_spwait, R_spawn, R_dec
  <1>. QED
    BY <1>6, <1>7, <1>8

LEMMA L_D1 == ASSUME IndInv, NEW t \in Thr, D1(t) PROVE IndInv'
  <1> USE Basics DEF IndInv, TypeOK, Labels, Reasons
  <1>1. /\ pc[t] = "ready"
        /\ UNCHANGED <<owner, cnt, depth, h, late, reent>>
        /\ ops' \in [Thr -> Nat]
    BY DEF D1
  <1>2. CASE depth = 0
    <2>1. /\ decn' = [decn EXCEPT ![t] = "par"] /\ reason' = [reason EXCEPT ![t] = "free"]
          /\ spawnOK' = [spawnOK EXCEPT ![t] = TRUE] /\ decH' = [decH EXCEPT ![t] = h[t]] /\ pc' = pc
      BY <1>2 DEF D1
    <2>2. h[t] = 0
      BY <1>2, HolderFacts
    <2>3. pc[Root] = "spwait" /\ h[Root] > 0 => FALSE
      BY <1>2, HolderFacts
    <2>. QED
      BY <1>1, <2>1, <2>2, <2>3 DEF R_ended, R_late, R_holder, R_cnt, R_depth, R_owner, R_q, R_spwait, R_spawn,
         R_dec, Lv, LvBy, HBy, Running
  <1>3. CASE depth # 0
    <2>1. /\ pc' = [pc EXCEPT ![t] = "d2"] /\ spawnOK' = [spawnOK EXCEPT ![t] = FALSE]
          /\ UNCHANGED <<decn, reason, decH>>
      BY <1>3 DEF D1
    <2>2. \A u \in Thr : Lv(u)' = Lv(u) /\ (Running(u)' <=> Running(u))
      BY <1>1, <2>1 DEF Lv, Running
    <2>3. pc'[Root] = "spwait" <=> pc[Root] = "spwait"
      BY <1>1, <2>1
    <2>. QED
      BY <1>1, <2>1, <2>2, <2>3 DEF R_ended, R_late, R_holder, R_cnt, R_depth, R_owner, R_q, R_spwait, R_spawn,
         R_dec, LvBy, HBy
  <1>. QED
    BY <1>2, <1>3

LEMMA L_D2 == ASSUME IndInv, NEW t \in Thr, D2(t) PROVE IndInv'
  <1> USE Basics DEF IndInv, TypeOK, Labels, Reasons
  <1>1. /\ pc[t] = "d2" /\ pc' = [pc EXCEPT ![t] = "ready"]
        /\ reason' = [reason EXCEPT ![t] = Reason(t)]
        /\ decn' = [decn EXCEPT ![t] = IF Block(t) THEN "serial" ELSE "par"]
        /\ spawnOK' = [spawnOK EXCEPT ![t] = ~Block(t)]
        /\ decH' = [decH EXCEPT ![t] = IF Block(t) THEN 0 ELSE h[t]]
        /\ UNCHANGED <<owner, cnt, depth, h, late, ops, reent>>
    BY DEF D2
  <1>2. Block(t) <=> (owner = NoThr \/ owner = t \/ owner \in Involved)
    BY BlockHead
  <1>3. ~Block(t) => h[t] = 0
    <2> SUFFICES ASSUME ~Block(t), h[t] > 0 PROVE FALSE
      OBVIOUS
    <2>1. Lv(t) > 0
      BY DEF Lv
    <2>. QED
      BY <1>2, <2>1 DEF R_holder, Involved
  <1>4. R_dec'
    <2>1. Block(t) => Reason(t) \in {"empty", "self", "pl"}
      BY <1>2 DEF Reason
    <2>2. ~Block(t) => Reason(t) = "other"
      BY <1>2 DEF Reason
    <2>. QED
      BY <1>1, <2>1, <2>2 DEF R_dec
  <1>5. R_spawn'
    BY <1>1, <1>3 DEF R_spawn
  <1>6. R_spwait'
    <2>1. (pc[Root] = "spwait" /\ h[Root] > 0 /\ t = Q) => Block(t)
      BY <1>2, HolderFacts DEF Involved
    <2>2. \A u \in Thr : Running(u)' <=> Running(u)
      BY <1>1 DEF Running
    <2>3. pc'[Root] = "spwait" <=> pc[Root] = "spwait"
      BY <1>1
    <2>4. spawnOK'[Q] => spawnOK[Q] \/ (t = Q /\ ~Block(t))
      BY <1>1
    <2>. QED
      BY <1>1, <2>1, <2>2, <2>3, <2>4 DEF R_spwait
  <1>7. \A u \in Thr : Lv(u)' = Lv(u) /\ (Running(u)' <=> Running(u))
    BY <1>1 DEF Lv, Running
  <1>8. TypeOK'
    BY <1>1 DEF Reason
  <1>. QED
    BY <1>1, <1>4, <1>5, <1>6, <1>7, <1>8 DEF R_ended, R_late, R_holder, R_cnt, R_depth, R_owner, R_q, LvBy, HBy

LEMMA L_Spawn == ASSUME IndInv, NEW t \in Thr, NEW c \in Thr, Spawn(t, c) PROVE IndInv'
  <1> USE Basics DEF IndInv, TypeOK, Labels
  <1>1. /\ pc[t] = "ready" /\ spawnOK[t] /\ h[t] = decH[t] /\ Par[c] = t /\ pc[c] = "idle"
        /\ pc' = [pc EXCEPT ![c] = "ready"]
        /\ UNCHANGED <<owner, cnt, depth, h, late, ops, decn, reason, spawnOK, decH, reent>>
    BY DEF Spawn
  <1>2. c # Root /\ c # Q /\ c # t /\ h[c] = 0
    BY <1>1 DEF R_ended
  <1>3. \A u \in Thr : Lv(u)' = Lv(u)
    BY <1>1, <1>2 DEF Lv
  <1>4. pc'[Root] = pc[Root] /\ pc'[Q] = pc[Q]
    BY <1>1, <1>2
  <1>5. ~(pc[Root] = "spwait" /\ h[Root] > 0)
    <2> SUFFICES ASSUME pc[Root] = "spwait", h[Root] > 0 PROVE FALSE
      OBVIOUS
    <2>1. Running(t) /\ t # Root
      BY <1>1 DEF Running
    <2>2. t = Q
      BY <2>1 DEF R_spwait
    <2>. QED
      BY <1>1, <2>2 DEF R_spwait
  <1>6. \A u \in Thr \ {c} : Running(u)' <=> Running(u)
    BY <1>1 DEF Running
  <1>. QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6 DEF R_ended, R_late, R_holder, R_cnt, R_depth, R_owner, R_q,
       R_spwait, R_spawn, R_dec, LvBy, HBy, Running

LEMMA L_Join == ASSUME IndInv, NEW t \in Thr, JoinStart(t) \/ JoinEnd(t) PROVE IndInv'
  <1> USE Basics DEF IndInv, TypeOK, Labels
  <1>1. /\ pc[t] \in {"ready", "join"} /\ pc' = [pc EXCEPT ![t] = IF pc[t] = "ready" THEN "join" ELSE "ready"]
        /\ UNCHANGED <<owner, cnt, depth, h, late, ops, decn, reason, spawnOK, decH, reent>>
    BY DEF JoinStart, JoinEnd
  <1>2. \A u \in Thr : Lv(u)' = Lv(u) /\ (Running(u)' <=> Running(u))
    BY <1>1 DEF Lv, Running
  <1>3. pc'[Root] = "spwait" <=> pc[Root] = "spwait"
    BY <1>1
  <1>. QED
    BY <1>1, <1>2, <1>3 DEF R_ended, R_late, R_holder, R_cnt, R_depth, R_owner, R_q, R_spwait, R_spawn,
       R_dec, LvBy, HBy

LEMMA L_Finish == ASSUME IndInv, NEW t \in Thr, Finish(t) PROVE IndInv'
  <1> USE Basics DEF IndInv, TypeOK, Labels
  <1>1. /\ pc[t] = "ready" /\ h[t] = 0 /\ pc' = [pc EXCEPT ![t] = "done"]
        /\ UNCHANGED <<owner, cnt, depth, h, late, ops, decn, reason, spawnOK, decH, reent>>
    BY DEF Finish
  <1>2. \A u \in Thr : Lv(u)' = Lv(u)
    BY <1>1 DEF Lv
  <1>3. \A u \in Thr : Running(u)' => Running(u)
    BY <1>1 DEF Running
  <1>4. pc'[Root] = "spwait" <=> pc[Root] = "spwait"
    BY <1>1
  <1>5. R_q'
    <2>1. CASE t = Q
      BY <1>1, <2>1 DEF R_q, Running
    <2>2. CASE t # Q
      BY <1>1, <1>4, <2>2 DEF R_q, Running
    <2>. QED
      BY <2>1, <2>2
  <1>. QED
    BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF R_ended, R_late, R_holder, R_cnt, R_depth, R_owner, R_spwait, R_spawn,
       R_dec, LvBy, HBy

LEMMA L_SpCall == ASSUME IndInv, SpCall PROVE IndInv'
  <1> USE Basics DEF IndInv, TypeOK, Labels, Reasons
  <1>1. /\ pc[Root] = "ready" /\ pc[Q] \in {"idle", "done"}
        /\ (h[Root] > 0 => \A c \in Thr \ {Root, Q} : ~Running(c))
        /\ pc' = [pc EXCEPT ![Root] = "spwait", ![Q] = "ready"]
        /\ ops' \in [Thr -> Nat]
        /\ spawnOK' = [spawnOK EXCEPT ![Q] = FALSE] /\ decn' = [decn EXCEPT ![Q] = "none"]
        /\ reason' = [reason EXCEPT ![Q] = "none"] /\ decH' = [decH EXCEPT ![Q] = 0]
        /\ UNCHANGED <<owner, cnt, depth, h, late, reent>>
    BY DEF SpCall
  <1>2. h[Q] = 0 /\ Lv(Q) = 0
    BY <1>1 DEF R_ended, Lv
  <1>3. \A u \in Thr : Lv(u)' = Lv(u)
    BY <1>1, <1>2 DEF Lv
  <1>4. \A u \in Thr \ {Q} : Running(u)' <=> Running(u)
    BY <1>1 DEF Running
  <1>5. R_holder'
    BY <1>1, <1>2, <1>3 DEF R_holder
  <1>6. R_spwait'
    BY <1>1, <1>4 DEF R_spwait, Running
  <1>. QED
    BY <1>1, <1>2, <1>3, <1>5, <1>6 DEF R_ended, R_late, R_cnt, R_depth, R_owner, R_q, R_spawn, R_dec,
       LvBy, HBy, Running

LEMMA L_SpRet == ASSUME IndInv, SpRet PROVE IndInv'
  <1> USE Basics DEF IndInv, TypeOK, Labels
  <1>1. /\ pc[Root] = "spwait" /\ pc[Q] = "done" /\ pc' = [pc EXCEPT ![Root] = "ready"]
        /\ UNCHANGED <<owner, cnt, depth, h, late, ops, decn, reason, spawnOK, decH, reent>>
    BY DEF SpRet
  <1>2. h[Q] = 0 /\ Lv(Q) = 0 /\ \A u \in Thr : Lv(u)' = Lv(u)
    BY <1>1 DEF R_ended, Lv
  <1>3. R_holder'
    <2> SUFFICES ASSUME NEW u \in Thr, Lv(u)' > 0 PROVE u = owner'
      BY DEF R_holder
    <2>1. Lv(u) > 0 /\ u # Q
      BY <1>2
    <2>. QED
      BY <1>1, <2>1, HolderFacts
  <1>4. \A u \in Thr \ {Root} : Running(u)' <=> Running(u)
    BY <1>1 DEF Running
  <1>5. R_q' /\ R_spwait'
    BY <1>1, <1>4 DEF R_q, R_spwait, Running
  <1>. QED
    BY <1>1, <1>2, <1>3, <1>5 DEF R_ended, R_late, R_cnt, R_depth, R_owner, R_spawn, R_dec, LvBy, HBy

THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1>1. ASSUME NEW t \in Thr, Step(t) PROVE IndInv'
  <2>1. CASE Want(t)   BY <2>1, L_Want
  <2>2. CASE Acq(t)    BY <2>2, L_Acq
  <2>3. CASE Inc(t)    BY <2>3, L_Inc
  <2>4. CASE Dec(t)    BY <2>4, L_Dec
  <2>5. CASE Rel(t)    BY <2>5, L_Rel
  <2>6. CASE D1(t)     BY <2>6, L_D1
  <2>7. CASE D2(t)     BY <2>7, L_D2
  <2>8. CASE \E c \in Thr : Spawn(t, c)  BY <2>8, L_Spawn
  <2>9. CASE JoinStart(t) \/ JoinEnd(t)  BY <2>9, L_Join
  <2>10. CASE Finish(t)  BY <2>10, L_Finish
  <2>11. CASE t = Root /\ SpCall  BY <2>11, L_SpCall
  <2>12. CASE t = Root /\ SpRet   BY <2>12, L_SpRet
  <2>. QED
    BY <1>1, <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, <2>9, <2>10, <2>11, <2>12 DEF Step
<1>2. CASE Terminating
  BY <1>2 DEF Terminating, vars, IndInv, TypeOK, R_ended, R_late, R_holder, R_cnt, R_depth, R_owner, R_q,
     R_spwait, R_spawn, R_dec, Lv, LvBy, HBy, Running, Involved
<1>3. CASE UNCHANGED vars
  BY <1>3 DEF vars, IndInv, TypeOK, R_ended, R_late, R_holder, R_cnt, R_depth, R_owner, R_q,
     R_spwait, R_spawn, R_dec, Lv, LvBy, HBy, Running, Involved
<1>. QED
  BY <1>1, <1>2, <1>3 DEF Next

THEOREM InvSafe == IndInv => NoForeignSerial /\ MutEx
  <1> SUFFICES ASSUME IndInv PROVE NoForeignSerial /\ MutEx
    OBVIOUS
  <1> USE Basics DEF IndInv, TypeOK
  <1>1. NoForeignSerial
    BY DEF R_dec, NoForeignSerial
  <1>2. \A t \in Thr : InSys(t) <=> Lv(t) > 0
    BY DEF InSys, Lv
  <1>3. MutEx
    BY <1>2 DEF MutEx, R_holder, Active
  <1>. QED
    BY <1>1, <1>3

THEOREM Safe == Spec => []IndInv
  BY InitInv, StepInv, PTL DEF Spec
=============================================================================
