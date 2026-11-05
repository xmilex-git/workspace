------------------------ MODULE PxErrorHandoff_proofs ------------------------
(* TLAPS proof that IndInv is an inductive invariant of the correct variant
   and implies the safety properties, for any set of workers. With
   Init => IndInv and IndInv /\ [Next]_vars => IndInv' the TLA rule INV1 gives
   Spec => []IndInv; the three theorems are its premises plus the
   implication, which is all Z3 and Zenon can check without a PTL back end. *)
EXTENDS PxErrorHandoff, TLAPS

ASSUME Correct == Mutant = "none"

THEOREM InitInv == Init => IndInv
  BY Assm DEF Init, IndInv, TypeOK, PcOK, ProcSet, WLabels, LLabels

THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct DEF IndInv, TypeOK, PcOK, ProcSet, WLabels, LLabels
<1>1. CASE L_spawn
  BY <1>1 DEF L_spawn
<1>2. CASE L_work
  <2>1. CASE /\ pc' = [pc EXCEPT ![Leader] = "L_join"]
             /\ UNCHANGED <<interrupted, leaderErr, leaderFailed>>
             /\ UNCHANGED <<started, done, holder, failed, freed, uaf>>
    BY <2>1, <1>2 DEF L_work
  <2>2. CASE /\ interrupted' = TRUE /\ leaderErr' = "err" /\ leaderFailed' = TRUE
             /\ pc' = [pc EXCEPT ![Leader] = "L_join"]
             /\ UNCHANGED <<started, done, holder, failed, freed, uaf>>
    BY <2>2, <1>2 DEF L_work
  <2>. QED
    BY <1>2, <2>1, <2>2 DEF L_work
<1>3. CASE L_join
  BY <1>3 DEF L_join
<1>4. CASE L_adopt
  BY <1>4 DEF L_adopt
<1>5. CASE L_free
  BY <1>5 DEF L_free
<1>6. ASSUME NEW self \in Workers, W_wait(self) PROVE IndInv'
  BY <1>6 DEF W_wait
<1>7. ASSUME NEW self \in Workers, W_run(self) PROVE IndInv'
  <2> USE <1>7
  <2>1. pc[self] = "W_run" /\ pc' = [pc EXCEPT ![self] = "W_done"]
        /\ UNCHANGED <<started, done, leaderErr, leaderFailed, freed>>
    BY DEF W_run
  <2>2. pc[Leader] \notin {"L_adopt", "L_free", "Done"} /\ ~freed
    BY <2>1
  <2>3. CASE UNCHANGED <<interrupted, holder, failed, uaf>>
    BY <2>1, <2>2, <2>3
  <2>4. CASE /\ uaf' = uaf
             /\ failed' = [failed EXCEPT ![self] = TRUE]
             /\ holder' = [holder EXCEPT ![self] = "err"]
             /\ interrupted' = TRUE
    BY <2>1, <2>2, <2>4
  <2>. QED
    BY <2>1, <2>2, <2>3, <2>4 DEF W_run
<1>8. ASSUME NEW self \in Workers, W_done(self) PROVE IndInv'
  BY <1>8 DEF W_done
<1>9. CASE Terminating
  BY <1>9 DEF Terminating, vars
<1>10. CASE UNCHANGED vars
  BY <1>10 DEF vars
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10 DEF Next, leader, worker

THEOREM InvSafe == IndInv => NoUseAfterFree /\ NoLostError
  BY DEF IndInv, NoUseAfterFree, NoLostError
=============================================================================
