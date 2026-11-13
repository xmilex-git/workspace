------------------------- MODULE FuncIdxCover_proofs -------------------------
(* TLAPS proof of the INV1 premises for the head variant (Mutant = "none") under the environment without
   signed-zero results (NegZero = FALSE; FuncIdxCover.negzero.cfg is the hole that environment excludes). *)
EXTENDS FuncIdxCover, TLAPS

ASSUME Correct == Mutant = "none" /\ NegZero = FALSE
ASSUME Assm == NR \in Nat /\ NR >= 1

Inv1 == Equiv /\ CoverWhenSafe /\ RouteWhenSafe /\ KfWhenSafe /\ PlainCover /\ NoFAsDevelop

THEOREM InitInv == Init => IndInv
  BY Assm DEF Init, IndInv, TypeOK, InputOK, Planned

LEMMA PlanStep == IndInv /\ Plan => IndInv'
<1> SUFFICES ASSUME IndInv, Plan PROVE IndInv'
  OBVIOUS
<1>1. TypeOK'
  BY DEF IndInv, TypeOK, Plan, CoverD, CoverHead, CoverDev, KfD, M, ArgRef, MixedRaw, OnlyInF, Cover0, Routable,
         KeyExact, OtherOK
<1>2. InputOK'
  BY DEF IndInv, InputOK, Plan
<1>3. (Planned => (cover = CoverD /\ kf = KfD(CoverD)))'
  BY DEF Plan, Planned, CoverD, CoverHead, CoverDev, KfD, M, ArgRef, MixedRaw, OnlyInF, Cover0, Routable, KeyExact,
         OtherOK
<1>4. (phase \in {"exec", "done"} => TRUE)'
  OBVIOUS
<1>. QED
  BY <1>1, <1>2, <1>3 DEF IndInv, Plan

LEMMA GenStep == IndInv /\ Gen => IndInv'
<1> SUFFICES ASSUME IndInv, Gen PROVE IndInv'
  OBVIOUS
<1>1. TypeOK'
  BY DEF IndInv, TypeOK, Gen, Uncover, FicD, M, ArgRef, Routable
<1>2. InputOK'
  BY DEF IndInv, InputOK, Gen
<1>3. (Planned => (cover = CoverD /\ kf = KfD(CoverD)))'
  BY DEF IndInv, Gen, Planned, CoverD, CoverHead, CoverDev, KfD, M, ArgRef, MixedRaw, OnlyInF, Cover0, Routable,
         KeyExact, OtherOK
<1>4. (phase \in {"exec", "done"} =>
       (/\ icover = (cover /\ ~Uncover)
        /\ loose = (looseHint /\ cover /\ (~Uncover \/ M("loose_kept")))
        /\ fic = FicD
        /\ rsel = (FicD /\ cover /\ ~Uncover /\ ~listfile /\ ~agg)
        /\ rkf = (kf /\ FicD)))'
  BY DEF Gen, Uncover, FicD, M, ArgRef, Routable
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4 DEF IndInv, Gen

LEMMA ExecStep == IndInv /\ Exec => IndInv'
<1> SUFFICES ASSUME IndInv, Exec PROVE IndInv'
  OBVIOUS
<1>1. TypeOK'
  BY DEF IndInv, TypeOK, Exec, ErrD, AbortD, RowOK, ArgAvail, M
<1>2. InputOK'
  BY DEF IndInv, InputOK, Exec
<1>3. (Planned => (cover = CoverD /\ kf = KfD(CoverD)))'
  BY DEF IndInv, Exec, Planned, CoverD, CoverHead, CoverDev, KfD, M, ArgRef, MixedRaw, OnlyInF, Cover0, Routable,
         KeyExact, OtherOK
<1>4. (phase \in {"exec", "done"} =>
       (/\ icover = (cover /\ ~Uncover)
        /\ loose = (looseHint /\ cover /\ (~Uncover \/ M("loose_kept")))
        /\ fic = FicD
        /\ rsel = (FicD /\ cover /\ ~Uncover /\ ~listfile /\ ~agg)
        /\ rkf = (kf /\ FicD)))'
  BY DEF IndInv, Exec, Uncover, FicD, M, ArgRef, Routable
<1>5. (phase = "done" => (ok = [r \in Rows |-> RowOK(r)] /\ err = ErrD /\ abort = AbortD))'
  BY DEF Exec, RowOK, ArgAvail, ErrD, AbortD, M
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF IndInv, Exec

LEMMA StutterStep == IndInv /\ UNCHANGED vars => IndInv'
  BY DEF IndInv, TypeOK, InputOK, Planned, vars, CoverD, CoverHead, CoverDev, KfD, M, ArgRef, MixedRaw, OnlyInF,
         Cover0, Routable, KeyExact, OtherOK, Uncover, FicD, RowOK, ArgAvail, ErrD, AbortD, Rows

THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
  BY PlanStep, GenStep, ExecStep, StutterStep DEF Next

LEMMA RowsOK == ASSUME IndInv, phase = "done", NEW r \in Rows PROVE RowOK(r)
<1> USE Correct
<1>1. stale[r] => (domBad \/ sess)
  BY DEF IndInv, InputOK
<1>. QED
  BY <1>1 DEF IndInv, Planned, RowOK, ArgAvail, CoverD, CoverHead, CoverDev, KfD, M, ArgRef, MixedRaw, OnlyInF, Cover0,
         Routable, KeyExact, OtherOK, Uncover, FicD, TypeOK, InputOK

THEOREM InvSafe == IndInv => Inv1
<1> SUFFICES ASSUME IndInv PROVE Inv1
  OBVIOUS
<1> USE Correct
<1>1. Equiv
  <2> SUFFICES ASSUME phase = "done" PROVE (\A r \in Rows : ok[r]) /\ ~err /\ ~abort
    BY DEF Equiv
  <2>1. \A r \in Rows : ok[r]
    BY RowsOK DEF IndInv
  <2>2. ~err
    BY DEF IndInv, Planned, ErrD, CoverD, CoverHead, KfD, M, Routable, FicD, Uncover, TypeOK
  <2>3. ~abort
    BY DEF IndInv, Planned, AbortD, M, Uncover, TypeOK
  <2>. QED
    BY <2>1, <2>2, <2>3
<1>2. CoverWhenSafe
  BY DEF CoverWhenSafe, IndInv, Planned, Safe, CoverD, CoverHead, M, ArgRef, MixedRaw, OnlyInF, Cover0, Routable,
         KeyExact, OtherOK, TypeOK
<1>3. RouteWhenSafe
  BY DEF RouteWhenSafe, IndInv, Planned, Safe, CoverD, CoverHead, M, ArgRef, MixedRaw, OnlyInF, Cover0, Routable,
         KeyExact, OtherOK, Uncover, FicD, TypeOK
<1>4. KfWhenSafe
  BY DEF KfWhenSafe, IndInv, Planned, KfD, M, Routable, KeyExact, TypeOK
<1>5. PlainCover
  BY DEF PlainCover, IndInv, Planned, CoverD, CoverHead, M, ArgRef, TypeOK
<1>6. NoFAsDevelop
  BY DEF NoFAsDevelop, IndInv, Planned, CoverD, CoverHead, CoverDev, M, ArgRef, MixedRaw, OnlyInF, Cover0, Routable,
         TypeOK
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6 DEF Inv1

THEOREM SpecSafe == Spec => []IndInv
  BY InitInv, StepInv, PTL DEF Spec
=============================================================================
