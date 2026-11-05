\* timeout: 5400
-------------------------- MODULE PxHashJoin_proofs_base --------------------------
(* Shared base of the TLAPS proof (PROOFS.md P31: one module per tlapm run under the 1800 s limit):
   the correct-variant assumption, helper lemmas, InitInv and InvSafe. *)
EXTENDS PxHashJoin, TLAPS

ASSUME Correct == Mutant = "none"

LEMMA ProbeOutType == \A v \in Units : ProbeOut(v) \subseteq Units \X {"b1", "-"}
  BY DEF ProbeOut, Units

LEMMA PartOfType == \A k \in KeyVals : PartOf(k) \in 0..NP /\ (PartOf(k) < NP => PartOf(k) \in Parts)
  BY Assm DEF PartOf, H, KeyVals, Parts

THEOREM InitInv == Init => IndInv
<1> SUFFICES ASSUME Init PROVE IndInv
  OBVIOUS
<1> USE Assm, Correct DEF IndInv, ProcSet, WLabels, LLabels, ULabels, ErrPc, PostJoin, Returned, ErrVals, Units, Parts, KeyVals
<1>1. /\ \A w \in Workers : pc[w] = "W_start"
      /\ pc[Leader] = "L_push"
      /\ pc[User] = "U_cancel"
      /\ DOMAIN pc = ProcSet
      /\ pc \in [ProcSet -> {"W_start", "L_push", "U_cancel"}]
  BY DEF Init
<1>0. /\ key \in [Units -> KeyVals] /\ (Phase = "join" => key = [v \in Units |-> "k1"])
      /\ pushed = {} /\ active = {} /\ next = NM + 1 /\ membufClaimed = FALSE /\ owner = "none"
      /\ cnt = [v \in Units |-> 0] /\ temp = [w \in Workers |-> [q \in Parts |-> {}]]
      /\ parts = [q \in Parts |-> {}] /\ out = [w \in Workers |-> {}] /\ merged = {}
      /\ hasError = FALSE /\ mainErr = "none" /\ failed = [w \in Workers |-> "none"]
      /\ intr = FALSE /\ cancelled = FALSE /\ freed = FALSE /\ tableFreed = FALSE /\ uaf = FALSE
      /\ res = "none" /\ final = "none" /\ fellBack = FALSE
      /\ mb = [w \in Workers |-> 0] /\ u = [w \in Workers |-> 1] /\ won = [w \in Workers |-> FALSE]
      /\ tmp = [w \in Workers |-> 0] /\ p = [w \in Workers |-> 0] /\ ret = [w \in Workers |-> "check"]
      /\ ok = [w \in Workers |-> FALSE] /\ matched = [w \in Workers |-> FALSE] /\ ended = [w \in Workers |-> FALSE]
  BY DEF Init
<1> USE <1>0
<1>2. IPc
  BY <1>1 DEF IPc
<1>3. IKey
  BY <1>1 DEF IKey
<1>4. IPush
  BY <1>1 DEF IPush, IPc
<1>5. IFix
  BY <1>1 DEF IFix
<1>6. IErr
  BY <1>1 DEF IErr, IPc, IPush
<1>7. IMain
  BY <1>1 DEF IMain, IErr, IPc
<1>8. IIntr
  BY <1>1 DEF IIntr, IErr, IPush, IPc
<1>9. IFree
  <2>1. ~(pc[Leader] \in {"L_fallback", "Done"}) /\ freed = FALSE /\ tableFreed = FALSE /\ uaf = FALSE
    BY <1>1
  <2>. QED
    BY <2>1 DEF IFree
<1>10. IRes
  BY <1>1 DEF IRes, IErr, IMain, IPc, IPush
<1>11. IDisp
  <2>1. next \in (NM + 1)..(NU + 1)
    BY Assm
  <2>2. mb \in [Workers -> -1..(NM + 1)] /\ \A w \in Workers : mb[w] = 0
    BY Assm
  <2>3. owner = "none" /\ membufClaimed = FALSE /\ \A w \in Workers : w # owner
    BY Assm
  <2>4. membufClaimed \in BOOLEAN /\ owner \in Workers \cup {"none"} /\ (membufClaimed <=> owner # "none")
    BY <2>3
  <2>5. /\ NM = 0 => ~membufClaimed
        /\ \A w \in Workers : w # owner => mb[w] \in {-1, 0}
        /\ owner # "none" => mb[owner] \in 1..(NM + 1)
        /\ \A w \in Workers : mb[w] = -1 /\ NM > 0 => membufClaimed
    BY <2>2, <2>3
  <2>. QED
    BY <2>1, <2>2, <2>4, <2>5 DEF IDisp
<1>12. ICnt
  BY DEF ICnt, Handed
<1>13. ILocal
  BY <1>1 DEF ILocal, IPc
<1>14. IStart
  BY <1>1 DEF IStart, IPc
<1>15. IDataT
  BY <1>1 DEF IDataT, TempVals, WOutVals
<1>16. IMerged
  BY <1>1 DEF IMerged, IPc, IPush
<1>. QED
  BY <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16

=============================================================================
