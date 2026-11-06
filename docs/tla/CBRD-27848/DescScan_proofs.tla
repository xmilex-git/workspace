--------------------------- MODULE DescScan_proofs ---------------------------
(* TLAPS proof that IndInv is an inductive invariant of DescScan for every N, W and Top, and that it implies
   Complete (C1) and the descending order of what Read returns.  Each action lemma proves every conjunct of IndInv
   in its own step (cubrid-tla P15). *)
EXTENDS DescScan, TLAPS
USE Assm

THEOREM InitInv == Init => IndInv
<1> SUFFICES ASSUME Init PROVE IndInv OBVIOUS
<1>1. TypeOK BY DEF Init, TypeOK
<1>2. R_start BY DEF Init, R_start
<1>3. R_scan BY DEF Init, R_scan
<1>4. R_done BY DEF Init, R_done
<1>5. R_cur BY DEF Init, R_cur
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF IndInv

THEOREM InvSafe == IndInv => Complete
  BY DEF IndInv, R_done, Complete

-----------------------------------------------------------------------------
LEMMA StartInv == IndInv /\ Start => IndInv'
<1> SUFFICES ASSUME IndInv, Start PROVE IndInv' OBVIOUS
<1>0. PICK x \in 0..Top : /\ NoWBetween(x, Top + 1) /\ g' = x
                         /\ pc = "start" /\ pc' = "scan"
                         /\ emitted' = emitted /\ hasCur' = hasCur /\ cpos' = cpos
  BY DEF Start
<1>a. emitted = {} /\ ~hasCur BY <1>0 DEF IndInv, R_start
<1>1. TypeOK'
  <2>1. g' \in 0..N BY <1>0
  <2>2. emitted' \in SUBSET (1..N) /\ hasCur' \in BOOLEAN /\ cpos' \in 0..N BY <1>0 DEF IndInv, TypeOK
  <2> QED BY <1>0, <2>1, <2>2 DEF TypeOK
<1>2. R_start' BY <1>0 DEF R_start
<1>3. R_scan'
  <2>1. {i \in W : x < i} = {}
    <3> SUFFICES ASSUME NEW i \in W, x < i PROVE FALSE OBVIOUS
    <3>1. i \in 1..Top OBVIOUS
    <3> QED BY <3>1, <1>0 DEF NoWBetween
  <2> QED BY <1>0, <1>a, <2>1 DEF R_scan
<1>4. R_done' BY <1>0 DEF R_done
<1>5. R_cur' BY <1>0, <1>a DEF R_cur
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF IndInv

LEMMA ReadInv == IndInv /\ Read => IndInv'
<1> SUFFICES ASSUME IndInv, Read PROVE IndInv' OBVIOUS
<1>t. g \in 0..N /\ cpos \in 0..N /\ emitted \in SUBSET (1..N) /\ hasCur \in BOOLEAN BY DEF IndInv, TypeOK
<1>r. /\ pc = "scan" /\ pc' = "scan" /\ g >= 1
      /\ emitted' = IF g \in W THEN emitted \cup {g} ELSE emitted
      /\ hasCur' = TRUE /\ cpos' = g
      /\ \E y \in 0..(g - 1) : NoWBetween(y, g) /\ g' = y
  BY DEF Read
<1>x. PICK x \in 0..(g - 1) : NoWBetween(x, g) /\ g' = x
  BY <1>r
<1>0. /\ NoWBetween(x, g) /\ g' = x /\ x \in 0..(g - 1)
      /\ pc = "scan" /\ pc' = "scan" /\ g >= 1
      /\ emitted' = IF g \in W THEN emitted \cup {g} ELSE emitted
      /\ hasCur' = TRUE /\ cpos' = g
  BY <1>r, <1>x
<1>s. emitted = {i \in W : g < i} BY <1>0 DEF IndInv, R_scan
<1>1. TypeOK' BY <1>0, <1>t DEF TypeOK
<1>2. R_start' BY <1>0 DEF R_start
<1>3. R_scan'
  <2>1. emitted' = {i \in W : x < i}
    <3>1. ASSUME NEW i \in W, x < i, i < g PROVE FALSE BY <3>1, <1>0 DEF NoWBetween
    <3>2. \A i \in W : x < i <=> (g < i \/ i = g) BY <3>1, <1>0, <1>t
    <3> QED BY <3>2, <1>0, <1>s, <1>t
  <2> QED BY <1>0, <2>1 DEF R_scan
<1>4. R_done' BY <1>0 DEF R_done
<1>5. R_cur' BY <1>0, <1>t DEF R_cur
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF IndInv

LEMMA EndInv == IndInv /\ End => IndInv'
<1> SUFFICES ASSUME IndInv, End PROVE IndInv' OBVIOUS
<1>0. /\ pc = "scan" /\ g = 0 /\ pc' = "done"
      /\ g' = g /\ emitted' = emitted /\ hasCur' = hasCur /\ cpos' = cpos
  BY DEF End
<1>s. emitted = {i \in W : g < i} BY <1>0 DEF IndInv, R_scan
<1>w. {i \in W : 0 < i} = W
  <2> SUFFICES ASSUME NEW i \in W PROVE 0 < i OBVIOUS
  <2>1. i \in 1..Top OBVIOUS
  <2> QED BY <2>1
<1>1. TypeOK' BY <1>0 DEF IndInv, TypeOK
<1>2. R_start' BY <1>0 DEF R_start
<1>3. R_scan' BY <1>0 DEF R_scan
<1>z. emitted = {i \in W : 0 < i} BY <1>0, <1>s
<1>4. R_done' BY <1>0, <1>z, <1>w DEF R_done
<1>5. R_cur' BY <1>0 DEF R_cur
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF IndInv

LEMMA RepositionInv == IndInv /\ Reposition => IndInv'
<1> SUFFICES ASSUME IndInv, Reposition PROVE IndInv' OBVIOUS
<1>t. g \in 0..N /\ cpos \in 0..N /\ emitted \in SUBSET (1..N) /\ hasCur \in BOOLEAN BY DEF IndInv, TypeOK
<1>0. PICK x \in 0..(cpos - 1) : /\ NoWBetween(x, cpos) /\ g' = x
                                /\ pc = "scan" /\ hasCur /\ pc' = "scan"
                                /\ emitted' = emitted /\ hasCur' = hasCur /\ cpos' = cpos
  BY DEF Reposition
<1>c. g < cpos /\ NoWBetween(g, cpos) BY <1>0 DEF IndInv, R_cur
<1>s. emitted = {i \in W : g < i} BY <1>0 DEF IndInv, R_scan
<1>1. TypeOK' BY <1>0, <1>t DEF TypeOK
<1>2. R_start' BY <1>0 DEF R_start
<1>3. R_scan'
  <2>1. \A i \in W : x < i <=> g < i
    <3>1. ASSUME NEW i \in W, x < i, i <= g PROVE FALSE BY <3>1, <1>0, <1>c, <1>t DEF NoWBetween
    <3>2. ASSUME NEW i \in W, g < i, i <= x PROVE FALSE BY <3>2, <1>0, <1>c, <1>t DEF NoWBetween
    <3> QED BY <3>1, <3>2, <1>0, <1>t
  <2> QED BY <1>0, <1>s, <2>1 DEF R_scan
<1>4. R_done' BY <1>0 DEF R_done
<1>5. R_cur' BY <1>0, <1>t DEF R_cur
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF IndInv

LEMMA ShiftInv == IndInv /\ Shift => IndInv'
<1> SUFFICES ASSUME IndInv, Shift PROVE IndInv' OBVIOUS
<1>t. g \in 0..N /\ cpos \in 0..N /\ emitted \in SUBSET (1..N) /\ hasCur \in BOOLEAN BY DEF IndInv, TypeOK
<1>0. PICK x \in 0..N : /\ NoWBetween(x, g + 1) /\ NoWBetween(g, x + 1)
                       /\ (hasCur => x < cpos) /\ g' = x
                       /\ pc = "scan" /\ pc' = "scan"
                       /\ emitted' = emitted /\ hasCur' = hasCur /\ cpos' = cpos
  BY DEF Shift
<1>s. emitted = {i \in W : g < i} BY <1>0 DEF IndInv, R_scan
<1>1. TypeOK' BY <1>0, <1>t DEF TypeOK
<1>2. R_start' BY <1>0 DEF R_start
<1>3. R_scan'
  <2>1. \A i \in W : x < i <=> g < i
    <3>1. ASSUME NEW i \in W, x < i, i <= g PROVE FALSE BY <3>1, <1>0, <1>t DEF NoWBetween
    <3>2. ASSUME NEW i \in W, g < i, i <= x PROVE FALSE BY <3>2, <1>0, <1>t DEF NoWBetween
    <3> QED BY <3>1, <3>2, <1>0, <1>t
  <2> QED BY <1>0, <1>s, <2>1 DEF R_scan
<1>4. R_done' BY <1>0 DEF R_done
<1>5. R_cur'
  <2> SUFFICES ASSUME hasCur PROVE x < cpos /\ NoWBetween(x, cpos) BY <1>0 DEF R_cur
  <2>c. g < cpos /\ NoWBetween(g, cpos) BY <1>0 DEF IndInv, R_cur
  <2>1. x < cpos BY <1>0
  <2>2. ASSUME NEW i \in W, x < i, i < cpos PROVE FALSE
    <3>1. CASE i <= g BY <3>1, <2>2, <1>0, <1>t DEF NoWBetween
    <3>2. CASE g < i BY <3>2, <2>2, <2>c DEF NoWBetween
    <3> QED BY <3>1, <3>2, <1>t
  <2> QED BY <2>1, <2>2 DEF NoWBetween
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF IndInv

LEMMA RestartInv == IndInv /\ RestartBeforeFirstKey => IndInv'
<1> SUFFICES ASSUME IndInv, RestartBeforeFirstKey PROVE IndInv' OBVIOUS
<1>0. /\ pc = "scan" /\ emitted = {} /\ pc' = "start" /\ hasCur' = FALSE /\ g' = 0
      /\ emitted' = emitted /\ cpos' = cpos
  BY DEF RestartBeforeFirstKey
<1>1. TypeOK' BY <1>0 DEF IndInv, TypeOK
<1>2. R_start' BY <1>0 DEF R_start
<1>3. R_scan' BY <1>0 DEF R_scan
<1>4. R_done' BY <1>0 DEF R_done
<1>5. R_cur' BY <1>0 DEF R_cur
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF IndInv

LEMMA StutterInv == IndInv /\ UNCHANGED vars => IndInv'
  BY DEF IndInv, TypeOK, R_start, R_scan, R_done, R_cur, vars

THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv' OBVIOUS
<1>1. CASE Start BY <1>1, StartInv
<1>2. CASE Read BY <1>2, ReadInv
<1>3. CASE End BY <1>3, EndInv
<1>4. CASE Reposition BY <1>4, RepositionInv
<1>5. CASE Shift BY <1>5, ShiftInv
<1>6. CASE RestartBeforeFirstKey BY <1>6, RestartInv
<1>7. CASE Terminated BY <1>7, StutterInv DEF Terminated
<1>8. CASE UNCHANGED vars BY <1>8, StutterInv
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8 DEF Next

THEOREM Safe == Spec => []IndInv
  BY InitInv, StepInv, PTL DEF Spec

\* what Read returns lies below everything returned before it
LEMMA DescStep == IndInv => (Read /\ g \in W => \A i \in emitted : g < i)
  BY DEF IndInv, R_scan, Read

THEOREM DescendingSafe == Spec => Descending
  BY Safe, DescStep, PTL DEF Descending
=============================================================================
