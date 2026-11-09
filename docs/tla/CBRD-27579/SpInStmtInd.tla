------------------------------ MODULE SpInStmtInd ------------------------------
(* Apalache's inductive check of SpInStmt's IndInv for the design (Off = {}). IndInit draws every
   variable with Gen and keeps the states IndInv admits; NEXT is SpInStmt's Next. The role sets and
   sizes stay fixed (N = 2 rows, MaxD = 2 levels, K = 2 SQL per SP, all tops, both modes); the
   integer contents (row versions, positions, budgets) range over every integer IndInv admits. *)
EXTENDS SpInStmt, Apalache

CInit == /\ N = 2 /\ MaxD = 2 /\ K = 2 /\ Off = {}
         /\ Tops = AllTops /\ Modes = {"CS", "SA"}

IndInit ==
  /\ mode = Gen(1) /\ top = Gen(1) /\ acc = Gen(1) /\ pos = Gen(1) /\ ph = Gen(1) /\ dep = Gen(1)
  /\ err = Gen(1) /\ trig = Gen(1) /\ tempOk = Gen(1) /\ snapOk = Gen(1) /\ abortPend = Gen(1)
  /\ failed = Gen(1)
  /\ heap = Gen(2) /\ copy = Gen(2) /\ emitted = Gen(2) /\ req = Gen(2) /\ left = Gen(2)
  /\ prep = Gen(9) /\ bad = Gen(11) /\ ev = Gen(17)
  /\ DOMAIN heap = Rows /\ DOMAIN copy = Rows /\ DOMAIN req = Depths /\ DOMAIN left = Depths
  /\ DOMAIN prep = Leaf
  /\ IndInv
=============================================================================
