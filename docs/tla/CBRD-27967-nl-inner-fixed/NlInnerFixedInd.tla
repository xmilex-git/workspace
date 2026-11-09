----------------------------- MODULE NlInnerFixedInd -----------------------------
(* Apalache's inductive check of NlInnerFixed's IndInv on the design (Mutant = "none"). IndInit draws the
   integer variables with Gen (unbounded; IndInv bounds them) and the others from IndInv's sets; NEXT is
   NlInnerFixed's Next. NO and RPP range over every natural >= 1, early stop and both outer heap ranks.
   Checked by Apalache only (EXTENDS Apalache). *)
EXTENDS NlInnerFixed, Apalache

CInit ==
  /\ NO \in Nat /\ NO >= 1 /\ RPP \in Nat /\ RPP >= 1
  /\ EarlyStop \in BOOLEAN /\ HcLow \in BOOLEAN /\ WProg = "normal" /\ Mutant = "none"

IndInit ==
  /\ orow = Gen(1) /\ mr = Gen(1) /\ ip = Gen(1) /\ rr = Gen(1) /\ cpass = Gen(1) /\ mpass = Gen(1)
  /\ wpc = Gen(1) /\ vpc = Gen(1) /\ ifix = Gen(1) /\ mfix = Gen(1)
  /\ lx = Gen(5) /\ ls = Gen(5) /\ held = Gen(2) /\ refix = Gen(2) /\ seen = Gen(6)
  /\ IndInv
=============================================================================
