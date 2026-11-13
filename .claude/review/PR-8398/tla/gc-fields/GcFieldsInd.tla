------------------------------- MODULE GcFieldsInd -------------------------------
(* Apalache's inductive check of GcFields' IndInv on the candidate fix (Fix = "prec", SepFix). IndInit draws
   the value records with Gen (integer fields unbounded, ValR then bounds them) and every other variable from
   TypeOK's finite sets, and keeps the states IndInv admits; NEXT is GcFields' Next. Constants are those of
   GcFields.cfg. Checked by Apalache only (EXTENDS Apalache). *)
EXTENDS GcFields, Apalache

CInit ==
  /\ MaxP = 9 /\ Max = 3 /\ VSz = 2 /\ VP = 2 /\ R = 3 /\ P = 2 /\ G = 1 /\ Workers = {"w1"}
  /\ AggTypes = {"C", "VC", "B", "VB"} /\ Css = {"u", "k"} /\ UColls = {1} /\ KColls = {2} /\ DomColl = 1
  /\ Thresh = 2 /\ Oracles = {TRUE, FALSE} /\ Modes = {"serial", "px"} /\ Mutant = "none" /\ Fix = "prec"
  /\ SepFix = TRUE

IndInit ==
  /\ sepv = Gen(1) /\ dev = Gen(2) /\ pr = Gen(2) /\ outv = Gen(2)
  /\ IndInv
=============================================================================
