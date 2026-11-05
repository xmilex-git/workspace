-------------------------- MODULE PageLatch_proofs --------------------------
(* TLAPS proof that IndInv is inductive for the page latch and implies the
   write latch's exclusion and the waiter_exists rule, for any set of threads
   and pages (premises of the TLA rule INV1). AtomicLatch.tla reaches these
   claims through its refinement PROPERTY, inside its TLC bounds. *)
EXTENDS PageLatch, TLAPS

THEOREM InitInv == Init => IndInv
  BY PLAssm DEF Init, IndInv, TypeOK, Exclusive, WaiterBit, HoldOrWait, Modes, Waiting

THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1> USE PLAssm DEF IndInv, TypeOK, Exclusive, WaiterBit, HoldOrWait, Modes, Waiting
<1>1. ASSUME NEW t \in T, NEW m \in {"R", "W"}, Acquire(t, m) PROVE IndInv'
  BY <1>1 DEF Acquire
<1>2. ASSUME NEW t \in T, NEW m \in {"R", "W"}, Enqueue(t, m) PROVE IndInv'
  <2>1. CASE m = "R"
    BY <1>2, <2>1 DEF Enqueue
  <2>2. CASE m # "R"
    BY <1>2, <2>2 DEF Enqueue
  <2>. QED
    BY <2>1, <2>2
<1>3. ASSUME NEW t \in T, NEW m \in {"R", "W"}, NEW p \in Pages, EvictAcquire(t, m, p) PROVE IndInv'
  BY <1>3 DEF EvictAcquire
<1>4. ASSUME NEW t \in T, Join(t) PROVE IndInv'
  BY <1>4 DEF Join
<1>5. ASSUME NEW t \in T, Upgrade(t) PROVE IndInv'
  BY <1>5 DEF Upgrade
<1>6. ASSUME NEW t \in T, Release(t) PROVE IndInv'
  <2>1. CASE holders \ {t} = {}
    BY <1>6, <2>1 DEF Release
  <2>2. CASE holders \ {t} # {}
    <3>1. mode' = mode /\ holders' = holders \ {t} /\ holders' # {}
      BY <1>6, <2>2 DEF Release
    <3>2. UNCHANGED <<bit, QR, QW, page>>
      BY <1>6 DEF Release
    <3>3. mode # "N"
      BY <1>6 DEF Release
    <3>. QED
      BY <3>1, <3>2, <3>3
  <2>. QED
    BY <2>1, <2>2
<1>7. ASSUME NEW t \in T, ReleaseEnqueue(t) PROVE IndInv'
  <2>1. holders' # {}
    BY <1>7 DEF ReleaseEnqueue
  <2>. QED
    BY <1>7, <2>1 DEF ReleaseEnqueue
<1>8. ASSUME NEW t \in T, GrantR(t) PROVE IndInv'
  BY <1>8 DEF GrantR
<1>9. ASSUME NEW t \in T, GrantW(t) PROVE IndInv'
  BY <1>9 DEF GrantW
<1>10. ASSUME NEW t \in T, Leave(t) PROVE IndInv'
  BY <1>10 DEF Leave
<1>11. CASE SetBit
  BY <1>11 DEF SetBit
<1>12. CASE ClearBit
  BY <1>12 DEF ClearBit
<1>13. CASE UNCHANGED vars
  BY <1>13 DEF vars
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13 DEF Next

THEOREM InvSafe == IndInv => Exclusive /\ WaiterBit
  BY DEF IndInv
=============================================================================
