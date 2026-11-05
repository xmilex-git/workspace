------------------------ MODULE ExprProgExec_proofs ------------------------
(* TLAPS proof that IndInv is inductive for the correct variant, for any threads, query ids and number of
   executions, and that it implies the safety claims (the premises of the TLA rule INV1). *)
EXTENDS ExprProgExec, TLAPS

ASSUME Correct == Mutant = "none"

THEOREM InitInv == Init => IndInv
<1> SUFFICES ASSUME Init PROVE IndInv OBVIOUS
<1> USE Assm DEF Init
<1>1. TBool BY DEF TBool
<1>2. TRest BY DEF TRest
<1>3. IState BY DEF IState
<1>. QED BY <1>1, <1>2, <1>3 DEF IndInv

THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct DEF IndInv
<1>1. ASSUME NEW t \in Threads, NEW q \in QIDs, Take(t, q) PROVE IndInv'
  <2>1. TBool' BY <1>1 DEF Take, TBool
  <2>2. TRest' BY <1>1 DEF Take, TRest
  <2>a. cph = "pool" /\ slot = 0 /\ sowner = "none" /\ svalid = FALSE /\ exec \in Nat BY <1>1 DEF Take, IState, TRest
  <2>b. cph' = "run" /\ thr' = t /\ qid' = q /\ exec' = exec + 1 /\ UNCHANGED <<slot, sowner, svalid>> BY <1>1 DEF Take
  <2>3. IState' BY <2>a, <2>b DEF IState
  <2>4. stale' = FALSE /\ xfree' = FALSE BY <1>1 DEF Take
  <2>. QED BY <2>1, <2>2, <2>3, <2>4
<1>2. CASE Row
  <2>0. cph = "run" /\ left > 0 /\ left' = left - 1 /\ UNCHANGED <<cph, exec, thr, qid, sawCollide>> BY <1>2 DEF Row
  <2>1. CASE svalid /\ stamp = qid
    <3>0. UNCHANGED <<pdone, svalid, stamp, slot, sowner, xfree>> /\ stale' = (stale \/ slot # exec) BY <1>2, <2>1 DEF Row
    <3>1. slot = exec BY <2>1 DEF IState
    <3>2. TBool'
      <4>1. stale' = FALSE /\ xfree' = FALSE BY <3>0, <3>1
      <4>2. pdone' \in BOOLEAN /\ svalid' \in BOOLEAN BY <3>0 DEF TBool
      <4>3. sawCollide' \in BOOLEAN BY <2>0 DEF TBool
      <4>. QED BY <4>1, <4>2, <4>3 DEF TBool
    <3>a. left \in 1..MaxRows BY <2>0 DEF TRest
    <3>3. TRest' BY <2>0, <3>0, <3>a DEF TRest
    <3>4. stale' = FALSE /\ xfree' = FALSE BY <3>0, <3>1
    <3>5. IState' BY <2>0, <3>0 DEF IState
    <3>. QED BY <3>2, <3>3, <3>4, <3>5
  <2>2. CASE ~(svalid /\ stamp = qid)
    <3>0. /\ pdone' = TRUE /\ svalid' = TRUE /\ stamp' = qid /\ slot' = exec /\ sowner' = thr
          /\ xfree' = (xfree \/ (slot # 0 /\ sowner # thr)) /\ stale' = stale
      BY <1>2, <2>2 DEF Row
    <3>1. slot # 0 => sowner = thr BY <2>0 DEF IState
    <3>2. TBool'
      <4>1. stale' = FALSE /\ xfree' = FALSE BY <3>0, <3>1
      <4>2. pdone' \in BOOLEAN /\ svalid' \in BOOLEAN BY <3>0 DEF TBool
      <4>3. sawCollide' \in BOOLEAN BY <2>0 DEF TBool
      <4>. QED BY <4>1, <4>2, <4>3 DEF TBool
    <3>a. left \in 1..MaxRows /\ thr \in Threads /\ exec \in 0..MaxExec /\ qid \in QIDs BY <2>0 DEF TRest, IState
    <3>3. TRest' BY <2>0, <3>0, <3>a DEF TRest
    <3>4. stale' = FALSE /\ xfree' = FALSE BY <3>0, <3>1
    <3>5. IState' BY <2>0, <3>0 DEF IState, TRest
    <3>. QED BY <3>2, <3>3, <3>4, <3>5
  <2>. QED BY <2>1, <2>2
<1>3. CASE EndExec
  <2>0. /\ cph = "run" /\ cph' = "pool" /\ thr' = "none" /\ left' = 0 /\ UNCHANGED <<exec, qid, stamp, stale, sawCollide>>
        /\ xfree' = (xfree \/ (slot # 0 /\ sowner # thr)) /\ slot' = 0 /\ sowner' = "none" /\ pdone' = FALSE
        /\ svalid' = FALSE
    BY <1>3 DEF EndExec
  <2>1. slot # 0 => sowner = thr BY <2>0 DEF IState
  <2>2. TBool' BY <2>0, <2>1 DEF TBool
  <2>3. TRest' BY <2>0 DEF TRest
  <2>4. xfree' = FALSE BY <2>0, <2>1
  <2>5. IState' BY <2>0 DEF IState
  <2>. QED BY <2>0, <2>2, <2>3, <2>4, <2>5
<1>4. CASE Done \/ UNCHANGED vars
  <2>0. UNCHANGED vars BY <1>4 DEF Done
  <2>. QED BY <2>0 DEF vars, TBool, TRest, IState
<1>. QED BY <1>1, <1>2, <1>3, <1>4 DEF Next

THEOREM InvSafe == IndInv => NoStaleBind /\ NoCrossThreadFree /\ TypeOK
  BY DEF IndInv, NoStaleBind, NoCrossThreadFree, TypeOK
=============================================================================
