----------------------------- MODULE NlInnerFixedInd -----------------------------
(* Apalache's inductive check of NlInnerFixed's IndInv on the design (Mutant = "none"). IndInit draws the
   integer variables with Gen (unbounded; IndInv bounds them) and the others from IndInv's sets; NEXT is
   NlInnerFixed's Next. NO and MR1 range over every natural >= 1, R1, R2 and MR2 over every natural (an
   empty page), with early stop and both outer heap ranks.
   Checked by Apalache only (EXTENDS Apalache). *)
EXTENDS NlInnerFixed, Apalache

CInit ==
  /\ NO \in Nat /\ NO >= 1 /\ R1 \in Nat /\ R2 \in Nat /\ MR1 \in Nat /\ MR1 >= 1 /\ MR2 \in Nat
  /\ EarlyStop \in BOOLEAN /\ HcLow \in BOOLEAN /\ WProg = "normal" /\ Mutant = "none"

IndInit ==
  /\ orow = Gen(1) /\ mr = Gen(1) /\ mp = Gen(1) /\ ip = Gen(1) /\ rr = Gen(1) /\ cpass = Gen(1) /\ mpass = Gen(1)
  /\ wpc = Gen(1) /\ vpc = Gen(1) /\ ifix = Gen(1) /\ mfix = Gen(1)
  /\ lx = Gen(6) /\ ls = Gen(6) /\ held = Gen(2) /\ refix = Gen(2) /\ seen = Gen(6)
  /\ IndInv
\* IndInv's conjuncts in three groups, one Apalache cfg each (group 2 split by transition): together IndInv
IndGrp1 == TypeOK /\ IFixBound /\ ILatchR /\ INoS /\ IRPos
IndGrp2 == NoWaitCycle /\ MFixBound /\ ILatchW /\ IExcl /\ ICopy
IndGrp3 == LevelRelease /\ NoStale /\ ILatchV /\ IRHeld
=============================================================================
