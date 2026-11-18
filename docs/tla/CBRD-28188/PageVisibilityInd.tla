--------------------------- MODULE PageVisibilityInd ---------------------------
(* Apalache's inductive check of PageVisibility's IndInv. IndInit draws every variable with Gen and keeps the
   states IndInv admits; NEXT is PageVisibility's Next. The role sets stay fixed (two transactions, one data page
   and the header page, two slots); MaxCrash is 2 (one above the TLC cfgs; Apalache needs a constant id range). Checked by Apalache only. *)
EXTENDS PageVisibility, Apalache

CInit ==
  /\ Tx = {"r", "t1"} /\ R = "r" /\ NoTx = "none" /\ DataPages = {"d"} /\ HdrPage = "h" /\ NS = 2
  /\ Reps = {1, 2} /\ Repids = {1} /\ Mutant = "none"
  /\ MaxCrash = 2 /\ MaxId = 4

IndInit ==
  /\ rec = Gen(2) /\ owner = Gen(2) /\ before = Gen(2) /\ maxm = Gen(2)
  /\ st = Gen(2) /\ tid = Gen(2) /\ nextId = Gen(1) /\ done = Gen(4) /\ cmt = Gen(4)
  /\ snap = Gen(4) /\ crashes = Gen(1)
  /\ IndInv
=============================================================================
