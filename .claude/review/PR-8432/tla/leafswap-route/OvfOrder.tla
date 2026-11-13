----------------------------- MODULE OvfOrder -----------------------------
(***************************************************************************)
(* Abstract order model of a CBRD-24094 overflow chain: pages 1..np in     *)
(* chain order, each a set of <<OID, version>> objects, and the separator   *)
(* of every page after the first (the first page is the catch-all: its      *)
(* stored separator is no lower bound, so sep[1] is left free).  The steps  *)
(* are the structural changes of OvfDirChain (insert, split, grow right,    *)
(* remove, page removal, COMPACT merge and redistribution); IndInv is the   *)
(* order invariant the routing relies on, proved by TLAPS in               *)
(* OvfOrder_proofs.tla for any number of pages and objects.                *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS MaxP, Obj, OidVals

ASSUME AssmC == MaxP \in Nat /\ OidVals \subseteq Nat /\ 0 \in OidVals
ASSUME AssmO == \A o \in Obj : o = <<o[1], o[2]>> /\ o[1] \in OidVals

VARIABLES np, cont, sep
vars == <<np, cont, sep>>

Oid(o) == o[1]
Pages == 1..MaxP
AllObjs == UNION {cont[r] : r \in Pages}

\* o would be routed to page r: r owns [sep[r], sep[r+1]), page 1 everything below sep[2]
Owns(r, x) == /\ r \in 1..np
              /\ r = 1 \/ sep[r] <= x
              /\ IF r < np THEN x < sep[r + 1] ELSE TRUE

\* page contents and separators after inserting a page at position r+1
ShiftR(f, r, new, z) == [i \in Pages |-> IF i <= r THEN f[i] ELSE IF i = r + 1 THEN new ELSE IF i - 1 <= np THEN f[i - 1] ELSE z]
\* after removing the page at position r
ShiftL(f, r, z) == [i \in Pages |-> IF i < r THEN f[i] ELSE IF i < np THEN f[i + 1] ELSE z]

FreeFirst(s1, f) == [i \in Pages |-> IF i = 1 THEN s1 ELSE f[i]]

Init == /\ np = 0
        /\ cont = [r \in Pages |-> {}]
        /\ sep = [r \in Pages |-> 0]

\* the key's first overflow page
AddFirst(o, s1) ==
  /\ np = 0 /\ MaxP >= 1
  /\ np' = 1
  /\ cont' = [cont EXCEPT ![1] = {o}]
  /\ sep' = FreeFirst(s1, sep)

\* routed insert into a page with room
Ins(o, r, s1) ==
  /\ o \notin AllObjs
  /\ Owns(r, Oid(o))
  /\ np' = np
  /\ cont' = [cont EXCEPT ![r] = @ \cup {o}]
  /\ sep' = FreeFirst(s1, sep)

\* the routed page r is split: its upper part B moves to a new page r+1 with separator min(B),
\* and o goes to the half that owns it (either half when its OID equals the separator)
SplitIns(o, r, B, m, lo, s1) ==
  /\ o \notin AllObjs
  /\ lo \in BOOLEAN
  /\ Oid(o) < Oid(m) => lo
  /\ Oid(m) < Oid(o) => ~lo
  /\ Owns(r, Oid(o))
  /\ np < MaxP
  /\ B \subseteq cont[r] /\ m \in B /\ cont[r] \ B # {}
  /\ \A b \in B : Oid(m) <= Oid(b)
  /\ \A a \in cont[r] \ B, b \in B : Oid(a) <= Oid(b)
  /\ np' = np + 1
  /\ cont' = ShiftR([cont EXCEPT ![r] = IF lo THEN (@ \ B) \cup {o} ELSE @ \ B], r,
                    IF lo THEN B ELSE B \cup {o}, {})
  /\ sep' = FreeFirst(s1, ShiftR(sep, r, Oid(m), 0))

\* a new rightmost page holding only o, larger than every object of the chain
GrowRight(o, s1) ==
  /\ o \notin AllObjs
  /\ np \in 1..(MaxP - 1)
  /\ \A a \in AllObjs : Oid(a) < Oid(o)
  /\ np' = np + 1
  /\ cont' = [cont EXCEPT ![np + 1] = {o}]
  /\ sep' = FreeFirst(s1, [sep EXCEPT ![np + 1] = Oid(o)])

\* an object removed from a page that keeps others
Rem(o, r, s1) ==
  /\ r \in 1..np /\ o \in cont[r] /\ cont[r] # {o}
  /\ np' = np
  /\ cont' = [cont EXCEPT ![r] = @ \ {o}]
  /\ sep' = FreeFirst(s1, sep)

\* the last object of a page removed: the page leaves the chain, its directory entry with it
RemPage(o, r, s1) ==
  /\ r \in 1..np /\ cont[r] = {o}
  /\ np' = np - 1
  /\ cont' = ShiftL(cont, r, {})
  /\ sep' = FreeFirst(s1, ShiftL(sep, r, 0))

\* COMPACT: all of page r+1 appended to page r
Merge(r, s1) ==
  /\ r \in 1..(np - 1)
  /\ np' = np - 1
  /\ cont' = ShiftL([cont EXCEPT ![r] = @ \cup cont[r + 1]], r + 1, {})
  /\ sep' = FreeFirst(s1, ShiftL(sep, r + 1, 0))

\* COMPACT: a prefix M of page r+1 appended to page r; the separator of r+1 raised to its new
\* first OID (the code backs off to a strict OID boundary; the order invariant does not need it)
Redist(r, M, m, s1) ==
  /\ r \in 1..(np - 1)
  /\ M \subseteq cont[r + 1] /\ M # {}
  /\ m \in cont[r + 1] \ M
  /\ \A x \in cont[r + 1] \ M : Oid(m) <= Oid(x)
  /\ \A a \in M, x \in cont[r + 1] \ M : Oid(a) <= Oid(x)
  /\ np' = np
  /\ cont' = [cont EXCEPT ![r] = @ \cup M, ![r + 1] = @ \ M]
  /\ sep' = FreeFirst(s1, [sep EXCEPT ![r + 1] = Oid(m)])

Next ==
  \E s1 \in OidVals :
    \/ \E o \in Obj : AddFirst(o, s1) \/ GrowRight(o, s1)
    \/ \E r \in 1..np :
         \/ \E o \in Obj : Ins(o, r, s1)
         \/ \E o \in cont[r] : Rem(o, r, s1) \/ RemPage(o, r, s1)
         \/ \E o \in Obj, B \in SUBSET cont[r], lo \in BOOLEAN : \E m \in B : SplitIns(o, r, B, m, lo, s1)
         \/ /\ r < np
            /\ \/ Merge(r, s1)
               \/ \E M \in SUBSET cont[r + 1] : \E m \in cont[r + 1] \ M : Redist(r, M, m, s1)

Spec == Init /\ [][Next]_vars

(***************************************************************************)
TypeOK ==
  /\ np \in 0..MaxP
  /\ cont \in [Pages -> SUBSET Obj]
  /\ sep \in [Pages -> OidVals]

R_shape == \A r \in Pages : (r <= np => cont[r] # {}) /\ (r > np => cont[r] = {} /\ (r >= 2 => sep[r] = 0))
R_disj == \A r1, r2 \in Pages : r1 # r2 => cont[r1] \cap cont[r2] = {}
\* the chain is globally OID-ordered
R_sorted == \A r1, r2 \in Pages : r1 < r2 => \A a \in cont[r1], b \in cont[r2] : Oid(a) <= Oid(b)
\* a separator is a lower bound of its page (first page excepted) ...
R_lower == \A r \in Pages : r >= 2 => \A a \in cont[r] : sep[r] <= Oid(a)
\* ... and an upper bound of the page before it
R_upper == \A r \in Pages : r + 1 <= np => \A a \in cont[r] : Oid(a) <= sep[r + 1]
\* separators do not descend after the catch-all
R_mono == \A r1, r2 \in Pages : 2 <= r1 /\ r1 <= r2 /\ r2 <= np => sep[r1] <= sep[r2]

IndInv == TypeOK /\ R_shape /\ R_disj /\ R_sorted /\ R_lower /\ R_upper /\ R_mono

\* C1 in the abstract: the page owning an object's OID range is at or after the object's page, and
\* every page in between starts at or above the object, so the step-back reaches it
AbsRoutable ==
  \A r \in 1..np : \A a \in cont[r] :
    /\ r = 1 \/ sep[r] <= Oid(a)
    /\ \A r2 \in Pages : r < r2 /\ r2 <= np => \A b \in cont[r2] : Oid(a) <= Oid(b)

\* TLC instances of the constants
MCObj2 == (1..2) \X (1..2)
MCObj3 == (1..3) \X (1..2)
MCOids2 == 0..2
MCOids3 == 0..3
=============================================================================
