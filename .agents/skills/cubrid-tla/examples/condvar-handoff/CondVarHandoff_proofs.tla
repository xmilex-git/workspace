------------------------ MODULE CondVarHandoff_proofs ------------------------
(* TLAPS proof that IndInv is inductive for the correct variant and implies
   NoConsumeBeforeReady, for any MaxSpurious (premises of the TLA rule INV1). *)
EXTENDS CondVarHandoff, TLAPS

ASSUME Correct == Mutant = "none"

THEOREM InitInv == Init => IndInv
<1> SUFFICES ASSUME Init PROVE IndInv
  OBVIOUS
<1> USE Assm
<1>a. pc[Waiter] = "W_lock"
  BY DEF Init, ProcSet
<1>b. pc[Signaler] = "S_lock"
  BY DEF Init, ProcSet
<1>c. pc["spurious"] = "X_wake"
  BY DEF Init, ProcSet
<1>d. \A self \in ProcSet : pc[self] \in Labels
  BY DEF Init, ProcSet, Labels
<1>e. pc \in [ProcSet -> Labels]
  <2>1. DOMAIN pc = ProcSet
    BY DEF Init
  <2>. QED
    BY <1>d, <2>1 DEF Init
<1>f. /\ locked = FALSE /\ ready = FALSE /\ sleeping = FALSE /\ badConsume = FALSE
      /\ sleptOnce = FALSE /\ spuriousLeft = MaxSpurious
  BY DEF Init
<1>g. BoolOK
  BY <1>f DEF BoolOK
<1>h. CountOK
  BY <1>f DEF CountOK
<1>. QED
  BY <1>a, <1>b, <1>c, <1>e, <1>f, <1>g, <1>h DEF IndInv, TypeOK, PcOK

THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct DEF IndInv, TypeOK, BoolOK, CountOK, PcOK, ProcSet, Labels
<1>1. CASE W_lock     BY <1>1 DEF W_lock
<1>2. CASE W_check    BY <1>2 DEF W_check
<1>3. CASE W_wait     BY <1>3 DEF W_wait
<1>4. CASE W_wake     BY <1>4 DEF W_wake
<1>5. CASE W_consume  BY <1>5 DEF W_consume
<1>6. CASE S_lock     BY <1>6 DEF S_lock
<1>7. CASE S_set      BY <1>7 DEF S_set
<1>8. CASE S_signal   BY <1>8 DEF S_signal
<1>9. CASE S_unlock   BY <1>9 DEF S_unlock
<1>10. CASE X_wake    BY <1>10 DEF X_wake
<1>11. CASE X_one
  <2>1. CASE sleeping
    \* a sleeping waiter is not Done, so the guard leaves spuriousLeft > 0
    <3>1. pc[Waiter] = "W_wake" /\ spuriousLeft > 0 /\ spuriousLeft \in Nat
      BY <1>11, <2>1 DEF X_one
    <3>2. spuriousLeft' = spuriousLeft - 1 /\ sleeping' = FALSE
          /\ pc' = [pc EXCEPT !["spurious"] = "X_wake"]
          /\ UNCHANGED <<locked, ready, badConsume, sleptOnce>>
      BY <1>11, <2>1 DEF X_one
    <3>3. spuriousLeft' \in 0..MaxSpurious
      BY <3>1, <3>2
    <3>4. pc' \in [ProcSet -> Labels]
      BY <3>2
    <3>5. pc'[Waiter] = pc[Waiter] /\ pc'[Signaler] = pc[Signaler] /\ pc'["spurious"] = "X_wake"
      BY <3>2
    <3>6. BoolOK' /\ CountOK'
      <4>1. BoolOK'
        BY <3>2, Zenon
      <4>. QED
        BY <4>1, <3>3
    <3>7. PcOK'
      BY <3>4, <3>5 DEF PcOK
    <3>8. (~badConsume /\ (pc[Waiter] = "W_consume" => ready) /\ (sleeping => pc[Waiter] = "W_wake"))'
      BY <3>2, <3>5
    <3>. QED
      BY <3>6, <3>7, <3>8
  <2>2. CASE ~sleeping
    BY <1>11, <2>2 DEF X_one
  <2>. QED
    BY <2>1, <2>2
<1>12. CASE Terminating BY <1>12 DEF Terminating, vars
<1>13. CASE UNCHANGED vars BY <1>13 DEF vars
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13
     DEF Next, waiter, signaler, spurious

THEOREM InvSafe == IndInv => NoConsumeBeforeReady
  BY DEF IndInv, NoConsumeBeforeReady
=============================================================================
