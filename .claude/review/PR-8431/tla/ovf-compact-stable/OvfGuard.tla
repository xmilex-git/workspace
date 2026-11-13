------------------------------ MODULE OvfGuard ------------------------------
(***************************************************************************)
(* The argument of PR #8431 (CBRD-27972) in five booleans, for the         *)
(* inductive check.  A range scan suspended in a key (spc = "susp") loses  *)
(* a row only if a leaf swap moves an object it has not returned; that     *)
(* needs a COMPACT pull during the suspension (u), which OvfScanStable     *)
(* checks through the refinement GuardRefined.  A pull needs a stable leaf *)
(* object (ls); a stable object during the suspension is protected from    *)
(* vacuum (lp: the leaf holds an object vacuum keeps); a swap needs the    *)
(* leaf's only object removed, so it needs ~lp.                            *)
(***************************************************************************)
EXTENDS Naturals

CONSTANTS AMutant

\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: AMutant Str
\* apalache-type: spc Str
\* apalache-type: u Bool
\* apalache-type: ls Bool
\* apalache-type: lp Bool
\* apalache-type: lost Bool

ASSUME AMutant \in {"none", "no_guard"}

VARIABLES spc,  \* "idle" | "susp" | "done"
  u,    \* a COMPACT pull ran during this suspension
  ls,   \* the leaf record holds a stable object
  lp,   \* the leaf record holds an object vacuum keeps while the scan lives
  lost  \* a swap moved an object the scan had not returned

vars == <<spc, u, ls, lp, lost>>

Susp == spc = "susp"

Init == spc = "idle" /\ u = FALSE /\ ls \in BOOLEAN /\ lp = FALSE /\ lost = FALSE

Start ==
  /\ spc = "idle"
  /\ \E s \in {"susp", "done"}, p \in BOOLEAN :
       /\ spc' = s
       /\ lp' = p
       /\ p => s = "susp"
       /\ (s = "susp" /\ ls) => p
  /\ u' = FALSE /\ ls' = ls /\ lost' = lost

Pull ==
  /\ AMutant = "no_guard" \/ ls
  /\ u' = (u \/ Susp)
  /\ UNCHANGED <<spc, ls, lp, lost>>

\* MVCC transitions, inserts, removals of objects outside the leaf
Env ==
  /\ spc # "done"
  /\ UNCHANGED <<spc, u, lost>>
  /\ \E a \in BOOLEAN, p \in BOOLEAN :
       /\ ls' = a
       /\ lp' = p
       /\ lp => p
       /\ p => Susp
       /\ (Susp /\ a) => p

\* the leaf record's only object removed (the leaf swap, or the key's last object)
Swap ==
  /\ spc # "done"
  /\ ~lp
  /\ UNCHANGED <<spc, u>>
  /\ \E l \in BOOLEAN, a \in BOOLEAN, p \in BOOLEAN :
       /\ lost' = l
       /\ ls' = a
       /\ lp' = p
       /\ lost => l
       /\ l # lost => (Susp /\ u)
       /\ p => Susp
       /\ (Susp /\ a) => p

Resume ==
  /\ Susp
  /\ \E s \in {"susp", "done"} :
       /\ spc' = s
       /\ lp' = IF s = "susp" THEN lp ELSE FALSE
  /\ u' = FALSE
  /\ UNCHANGED <<ls, lost>>

End == spc = "done" /\ UNCHANGED vars

Next == Start \/ Pull \/ Env \/ Swap \/ Resume \/ End

Spec == Init /\ [][Next]_vars

CInit == AMutant = "none"

(***************************************************************************)
TypeOK == spc \in {"idle", "susp", "done"} /\ u \in BOOLEAN /\ ls \in BOOLEAN /\ lp \in BOOLEAN /\ lost \in BOOLEAN
NoLost == ~lost
UProt == u => lp
LsProt == (Susp /\ ls) => lp
USusp == u => Susp
LpSusp == lp => Susp

IndInv ==
  /\ TypeOK
  /\ NoLost
  /\ UProt
  /\ LsProt
  /\ USusp
  /\ LpSusp

\* witness
NotPulledWhileSusp == ~u
=============================================================================
