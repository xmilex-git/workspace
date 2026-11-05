-------------------------- MODULE OvfOrder_proofs --------------------------
(***************************************************************************)
(* TLAPS proof that IndInv (TypeOK and the order conjuncts R_x) is an      *)
(* inductive invariant of OvfOrder for every MaxP, object set and OID set,  *)
(* and that it implies AbsRoutable.  INV1's temporal conclusion is left to  *)
(* the rule (cubrid-tla P2).  Each action lemma first states the action's   *)
(* effect page by page (<1>0), then proves every conjunct from it alone     *)
(* (cubrid-tla P15).                                                       *)
(***************************************************************************)
EXTENDS OvfOrder, TLAPS
USE AssmC DEF Pages

LEMMA OidNat == \A o \in Obj : Oid(o) \in Nat
  BY AssmC, AssmO DEF Oid

LEMMA OidIn == \A o \in Obj : Oid(o) \in OidVals
  BY AssmO DEF Oid

LEMMA SepNat == TypeOK => \A i \in Pages : sep[i] \in Nat
  BY DEF TypeOK

LEMMA ContNat == TypeOK => \A i \in Pages : \A a \in cont[i] : Oid(a) \in Nat
  BY OidNat DEF TypeOK

THEOREM InitInv == Init => IndInv
<1> SUFFICES ASSUME Init PROVE IndInv OBVIOUS
<1>1. TypeOK BY DEF Init, TypeOK, Pages
<1>2. R_shape BY DEF Init, R_shape, Pages
<1>3. R_disj BY DEF Init, R_disj, Pages
<1>4. R_sorted BY DEF Init, R_sorted, Pages
<1>5. R_lower BY DEF Init, R_lower, Pages
<1>6. R_upper BY DEF Init, R_upper, Pages
<1>7. R_mono BY DEF Init, R_mono, Pages
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7 DEF IndInv

THEOREM InvSafe == IndInv => AbsRoutable
<1> SUFFICES ASSUME IndInv, NEW r \in 1..np, NEW a \in cont[r]
             PROVE /\ r = 1 \/ sep[r] <= Oid(a)
                   /\ \A r2 \in Pages : r < r2 /\ r2 <= np => \A b \in cont[r2] : Oid(a) <= Oid(b)
  BY DEF AbsRoutable
<1>0. r \in Pages BY DEF IndInv, TypeOK, Pages
<1>1. r = 1 \/ sep[r] <= Oid(a) BY <1>0 DEF IndInv, R_lower
<1>2. \A r2 \in Pages : r < r2 /\ r2 <= np => \A b \in cont[r2] : Oid(a) <= Oid(b) BY <1>0 DEF IndInv, R_sorted
<1> QED BY <1>1, <1>2

-----------------------------------------------------------------------------
LEMMA AddFirstInv ==
  ASSUME IndInv, NEW o \in Obj, NEW s1 \in OidVals, AddFirst(o, s1)
  PROVE IndInv'
<1> USE OidNat
<1>0. /\ np = 0 /\ np' = 1 /\ 1 \in Pages
      /\ \A i \in Pages : cont'[i] = IF i = 1 THEN {o} ELSE cont[i]
      /\ \A i \in Pages : i >= 2 => sep'[i] = sep[i]
  BY DEF AddFirst, FreeFirst, IndInv, TypeOK, Pages
<1>t. cont' \in [Pages -> SUBSET Obj] /\ sep' \in [Pages -> OidVals]
  BY DEF AddFirst, FreeFirst, IndInv, TypeOK, Pages
<1> HIDE DEF AddFirst
<1>n. np \in 0..MaxP BY DEF IndInv, TypeOK
<1> USE <1>n
<1>1. TypeOK' BY <1>0, <1>t DEF TypeOK, Pages
<1>2. R_shape' BY <1>0 DEF IndInv, R_shape, Pages
<1>3. R_disj' BY <1>0 DEF IndInv, R_disj, R_shape, Pages
<1>4. R_sorted' BY <1>0 DEF IndInv, R_sorted, R_shape, Pages
<1>5. R_lower' BY <1>0 DEF IndInv, R_lower, R_shape, Pages
<1>6. R_upper' BY <1>0 DEF IndInv, R_upper, R_shape, Pages
<1>7. R_mono' BY <1>0 DEF IndInv, R_mono, R_shape, Pages
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7 DEF IndInv

LEMMA InsInv ==
  ASSUME IndInv, NEW o \in Obj, NEW r \in Pages, NEW s1 \in OidVals, Ins(o, r, s1)
  PROVE IndInv'
<1> USE OidNat
<1>0. /\ np' = np /\ r \in 1..np
      /\ r = 1 \/ sep[r] <= Oid(o)
      /\ r < np => Oid(o) < sep[r + 1]
      /\ \A i \in Pages : o \notin cont[i]
      /\ \A i \in Pages : cont'[i] = IF i = r THEN cont[r] \cup {o} ELSE cont[i]
      /\ \A i \in Pages : i >= 2 => sep'[i] = sep[i]
  BY DEF Ins, Owns, FreeFirst, AllObjs, IndInv, TypeOK, Pages
<1>t. cont' \in [Pages -> SUBSET Obj] /\ sep' \in [Pages -> OidVals]
  BY DEF Ins, Owns, FreeFirst, AllObjs, IndInv, TypeOK, Pages
<1> HIDE DEF Ins
<1>n. np \in 0..MaxP BY DEF IndInv, TypeOK
<1> USE <1>n
<1>1. TypeOK' BY <1>0, <1>t DEF IndInv, TypeOK, Pages
<1>2. R_shape' BY <1>0 DEF IndInv, R_shape, Pages
<1>3. R_disj' BY <1>0 DEF IndInv, R_disj, Pages
<1>4. R_sorted'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, r1 < r2, NEW a \in cont'[r1], NEW b \in cont'[r2]
               PROVE Oid(a) <= Oid(b)
    BY DEF R_sorted
  <2>1. CASE a # o /\ b # o
    <3>1. a \in cont[r1] /\ b \in cont[r2] BY <2>1, <1>0
    <3> QED BY <3>1 DEF IndInv, R_sorted
  <2>2. CASE a = o
    \* r1 = r and every page after r starts at or above sep[r+1] > Oid(o)
    <3>1. r1 = r BY <2>2, <1>0
    <3>2. b \in cont[r2] BY <2>2, <3>1, <1>0
    <3>3. r2 <= np BY <3>2 DEF IndInv, R_shape, TypeOK, Pages
    <3>4. sep[r2] <= Oid(b) BY <3>1, <3>2, <3>3 DEF IndInv, R_lower, TypeOK, Pages
    <3>5. sep[r + 1] <= sep[r2] BY <3>1, <3>3, <1>0 DEF IndInv, R_mono, TypeOK, Pages
    <3>6. r < np BY <3>1, <3>3
    <3>7. Oid(o) < sep[r + 1] BY <3>6, <1>0
    <3>8. r + 1 \in Pages /\ sep[r + 1] \in Nat /\ sep[r2] \in Nat BY <3>1, <3>3, SepNat DEF IndInv
    <3>9. Oid(b) \in Nat /\ Oid(o) \in Nat BY <3>2, ContNat, OidNat DEF IndInv
    <3> QED BY <2>2, <3>4, <3>5, <3>7, <3>8, <3>9
  <2>3. CASE b = o /\ a # o
    \* r2 = r and every page before r ends at or below sep[r1+1] <= sep[r] <= Oid(o)
    <3>1. r2 = r /\ a \in cont[r1] BY <2>3, <1>0
    <3>2. r1 + 1 <= np BY <3>1, <1>0
    <3>3. Oid(a) <= sep[r1 + 1] BY <3>1, <3>2 DEF IndInv, R_upper
    <3>4. r # 1 BY <3>1
    <3>5. sep[r] <= Oid(o) BY <3>4, <1>0
    <3>6. r1 + 1 = r \/ (2 <= r1 + 1 /\ r1 + 1 <= r) BY <3>1
    <3>7. sep[r1 + 1] <= sep[r] BY <3>6, <3>1, <1>0 DEF IndInv, R_mono, TypeOK, Pages
    <3>8. sep[r1 + 1] \in Nat /\ sep[r] \in Nat BY <3>1, <3>2, <1>0, SepNat DEF IndInv
    <3>9. Oid(a) \in Nat BY <3>1, ContNat DEF IndInv
    <3> QED BY <2>3, <3>3, <3>5, <3>7, <3>8, <3>9
  <2> QED BY <2>1, <2>2, <2>3
<1>5. R_lower'
  <2> SUFFICES ASSUME NEW i \in Pages, i >= 2, NEW a \in cont'[i] PROVE sep'[i] <= Oid(a)
    BY DEF R_lower
  <2>1. CASE a = o BY <2>1, <1>0
  <2>2. CASE a # o BY <2>2, <1>0 DEF IndInv, R_lower
  <2> QED BY <2>1, <2>2
<1>6. R_upper'
  <2> SUFFICES ASSUME NEW i \in Pages, i + 1 <= np', NEW a \in cont'[i] PROVE Oid(a) <= sep'[i + 1]
    BY DEF R_upper
  <2>0. i + 1 \in Pages /\ i + 1 >= 2 BY <1>0 DEF IndInv, TypeOK, Pages
  <2>1. CASE a = o BY <2>1, <2>0, <1>0, ContNat, SepNat DEF IndInv
  <2>2. CASE a # o BY <2>2, <2>0, <1>0 DEF IndInv, R_upper
  <2> QED BY <2>1, <2>2
<1>7. R_mono' BY <1>0 DEF IndInv, R_mono, TypeOK, Pages
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7 DEF IndInv

LEMMA RemInv ==
  ASSUME IndInv, NEW o \in Obj, NEW r \in Pages, NEW s1 \in OidVals, Rem(o, r, s1)
  PROVE IndInv'
<1> USE OidNat
<1>0. /\ np' = np /\ r \in 1..np /\ cont[r] # {o}
      /\ \A i \in Pages : cont'[i] = IF i = r THEN cont[r] \ {o} ELSE cont[i]
      /\ \A i \in Pages : i >= 2 => sep'[i] = sep[i]
  BY DEF Rem, FreeFirst, IndInv, TypeOK, Pages
<1>t. cont' \in [Pages -> SUBSET Obj] /\ sep' \in [Pages -> OidVals]
  BY DEF Rem, FreeFirst, IndInv, TypeOK, Pages
<1> HIDE DEF Rem
<1>n. np \in 0..MaxP BY DEF IndInv, TypeOK
<1> USE <1>n
<1>1. TypeOK' BY <1>0, <1>t DEF IndInv, TypeOK, Pages
<1>2. R_shape' BY <1>0 DEF IndInv, R_shape, Pages
<1>3. R_disj' BY <1>0 DEF IndInv, R_disj, Pages
<1>4. R_sorted' BY <1>0 DEF IndInv, R_sorted, Pages
<1>5. R_lower' BY <1>0 DEF IndInv, R_lower, Pages
<1>6. R_upper' BY <1>0 DEF IndInv, R_upper, TypeOK, Pages
<1>7. R_mono' BY <1>0 DEF IndInv, R_mono, Pages
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7 DEF IndInv

LEMMA RemPageInv ==
  ASSUME IndInv, NEW o \in Obj, NEW r \in Pages, NEW s1 \in OidVals, RemPage(o, r, s1)
  PROVE IndInv'
<1> USE OidNat
<1>0. /\ np' = np - 1 /\ r \in 1..np /\ np \in 1..MaxP
      /\ \A i \in Pages : cont'[i] = IF i < r THEN cont[i] ELSE IF i < np THEN cont[i + 1] ELSE {}
      /\ \A i \in Pages : i >= 2 => sep'[i] = IF i < r THEN sep[i] ELSE IF i < np THEN sep[i + 1] ELSE 0
  BY DEF RemPage, ShiftL, FreeFirst, IndInv, TypeOK, Pages
<1>t. cont' \in [Pages -> SUBSET Obj] /\ sep' \in [Pages -> OidVals]
  BY DEF RemPage, ShiftL, FreeFirst, IndInv, TypeOK, Pages
<1> HIDE DEF RemPage, ShiftL
<1>n. np \in 0..MaxP BY DEF IndInv, TypeOK
<1> USE <1>n
<1>1. TypeOK' BY <1>0, <1>t DEF IndInv, TypeOK, Pages
<1>2. R_shape'
  <2> SUFFICES ASSUME NEW i \in Pages
               PROVE (i <= np' => cont'[i] # {}) /\ (i > np' => cont'[i] = {} /\ (i >= 2 => sep'[i] = 0))
    BY DEF R_shape
  <2>1. CASE i < r
    <3>1. cont'[i] = cont[i] /\ i <= np' /\ i <= np BY <2>1, <1>0
    <3> QED BY <3>1, <1>0 DEF IndInv, R_shape
  <2>2. CASE i >= r /\ i < np
    <3>1. cont'[i] = cont[i + 1] /\ i + 1 \in Pages /\ i + 1 <= np /\ i <= np' BY <2>2, <1>0
    <3> QED BY <3>1, <1>0 DEF IndInv, R_shape
  <2>3. CASE i >= np
    <3>1. cont'[i] = {} /\ (i >= 2 => sep'[i] = 0) /\ i > np' BY <2>3, <1>0
    <3> QED BY <3>1, <1>0
  <2> QED BY <2>1, <2>2, <2>3
<1>3. R_disj'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, r1 # r2, NEW x \in cont'[r1], x \in cont'[r2] PROVE FALSE
    BY DEF R_disj
  <2> DEFINE f(i) == IF i < r THEN i ELSE i + 1
  <2>1. f(r1) \in Pages /\ x \in cont[f(r1)] /\ f(r2) \in Pages /\ x \in cont[f(r2)] BY <1>0
  <2>2. f(r1) # f(r2) BY <1>0
  <2> QED BY <2>1, <2>2 DEF IndInv, R_disj
<1>4. R_sorted'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, r1 < r2, NEW a \in cont'[r1], NEW b \in cont'[r2]
               PROVE Oid(a) <= Oid(b)
    BY DEF R_sorted
  <2> DEFINE f(i) == IF i < r THEN i ELSE i + 1
  <2>1. f(r1) \in Pages /\ a \in cont[f(r1)] /\ f(r2) \in Pages /\ b \in cont[f(r2)] BY <1>0
  <2>2. f(r1) < f(r2) BY <1>0
  <2> QED BY <2>1, <2>2 DEF IndInv, R_sorted
<1>5. R_lower'
  <2> SUFFICES ASSUME NEW i \in Pages, i >= 2, NEW a \in cont'[i] PROVE sep'[i] <= Oid(a)
    BY DEF R_lower
  <2>1. CASE i < r BY <2>1, <1>0 DEF IndInv, R_lower
  <2>2. CASE i >= r /\ i < np
    <3>1. i + 1 \in Pages /\ a \in cont[i + 1] /\ sep'[i] = sep[i + 1] BY <2>2, <1>0 DEF IndInv, TypeOK, Pages
    <3> QED BY <3>1 DEF IndInv, R_lower
  <2>3. CASE i >= np BY <2>3, <1>0
  <2> QED BY <2>1, <2>2, <2>3
<1>6. R_upper'
  <2> SUFFICES ASSUME NEW i \in Pages, i + 1 <= np', NEW a \in cont'[i] PROVE Oid(a) <= sep'[i + 1]
    BY DEF R_upper
  <2>0. i + 1 \in Pages /\ i + 1 >= 2 /\ i + 2 <= np BY <1>0 DEF IndInv, TypeOK, Pages
  <2>1. CASE i + 1 < r BY <2>1, <2>0, <1>0 DEF IndInv, R_upper
  <2>2. CASE i + 1 = r
    \* page i keeps its objects; its successor is now the old r+1: sep[i+1] <= sep[r+1]
    <3>1. a \in cont[i] BY <2>2, <1>0
    <3>2. Oid(a) <= sep[i + 1] BY <3>1, <2>0 DEF IndInv, R_upper
    <3>3. sep[r] <= sep[r + 1] BY <2>2, <2>0 DEF IndInv, R_mono, TypeOK, Pages
    <3>4. sep'[i + 1] = sep[r + 1] BY <2>2, <2>0, <1>0
    <3>5. sep[r] \in Nat /\ sep[r + 1] \in Nat BY <2>2, <2>0, SepNat DEF IndInv
    <3>6. Oid(a) \in Nat BY <3>1, ContNat DEF IndInv
    <3> QED BY <3>2, <3>3, <3>4, <3>5, <3>6, <2>2
  <2>3. CASE i >= r
    <3>1. a \in cont[i + 1] /\ sep'[i + 1] = sep[i + 2] BY <2>3, <2>0, <1>0
    <3>2. i + 1 \in Pages /\ (i + 1) + 1 <= np BY <2>0
    <3> QED BY <3>1, <3>2 DEF IndInv, R_upper
  <2> QED BY <2>1, <2>2, <2>3
<1>7. R_mono'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, 2 <= r1, r1 <= r2, r2 <= np' PROVE sep'[r1] <= sep'[r2]
    BY DEF R_mono
  <2>1. r2 + 1 \in Pages /\ r2 < np BY <1>0 DEF IndInv, TypeOK, Pages
  <2>2. sep'[r1] = (IF r1 < r THEN sep[r1] ELSE sep[r1 + 1]) /\ sep'[r2] = (IF r2 < r THEN sep[r2] ELSE sep[r2 + 1])
    BY <2>1, <1>0
  <2> QED BY <2>1, <2>2 DEF IndInv, R_mono, TypeOK, Pages
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7 DEF IndInv

LEMMA MergeInv ==
  ASSUME IndInv, NEW r \in Pages, NEW s1 \in OidVals, Merge(r, s1)
  PROVE IndInv'
<1> USE OidNat
<1>0. /\ np' = np - 1 /\ r \in 1..(np - 1) /\ np \in 2..MaxP
      /\ \A i \in Pages : cont'[i] = IF i < r THEN cont[i] ELSE IF i = r THEN cont[r] \cup cont[r + 1]
                                     ELSE IF i < np THEN cont[i + 1] ELSE {}
      /\ \A i \in Pages : i >= 2 => sep'[i] = IF i <= r THEN sep[i] ELSE IF i < np THEN sep[i + 1] ELSE 0
  BY DEF Merge, ShiftL, FreeFirst, IndInv, TypeOK, Pages
<1>t. cont' \in [Pages -> SUBSET Obj] /\ sep' \in [Pages -> OidVals]
  BY DEF Merge, ShiftL, FreeFirst, IndInv, TypeOK, Pages
<1> HIDE DEF Merge, ShiftL
<1>n. np \in 0..MaxP BY DEF IndInv, TypeOK
<1> USE <1>n
<1>1. TypeOK' BY <1>0, <1>t DEF IndInv, TypeOK, Pages
<1>2. R_shape'
  <2> SUFFICES ASSUME NEW i \in Pages
               PROVE (i <= np' => cont'[i] # {}) /\ (i > np' => cont'[i] = {} /\ (i >= 2 => sep'[i] = 0))
    BY DEF R_shape
  <2>1. CASE i < r
    <3>1. cont'[i] = cont[i] /\ i <= np' /\ i <= np BY <2>1, <1>0
    <3> QED BY <3>1, <1>0 DEF IndInv, R_shape
  <2>2. CASE i = r
    <3>1. cont[r] \subseteq cont'[i] /\ i <= np' /\ r <= np BY <2>2, <1>0
    <3> QED BY <3>1, <1>0 DEF IndInv, R_shape
  <2>3. CASE i > r /\ i < np
    <3>1. cont'[i] = cont[i + 1] /\ i + 1 \in Pages /\ i + 1 <= np /\ i <= np' BY <2>3, <1>0
    <3> QED BY <3>1, <1>0 DEF IndInv, R_shape
  <2>4. CASE i > r /\ i >= np
    <3>1. cont'[i] = {} /\ (i >= 2 => sep'[i] = 0) /\ i > np' BY <2>4, <1>0
    <3> QED BY <3>1, <1>0
  <2> QED BY <2>1, <2>2, <2>3, <2>4
<1>m. \A i \in Pages : \A y \in cont'[i] :
        \E k \in Pages : /\ y \in cont[k]
                         /\ i < r => k = i
                         /\ i = r => k \in {r, r + 1}
                         /\ i > r => k = i + 1
  BY <1>0
<1>3. R_disj'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, r1 # r2, NEW x \in cont'[r1], x \in cont'[r2] PROVE FALSE
    BY DEF R_disj
  <2>1. PICK k1 \in Pages : /\ x \in cont[k1] /\ (r1 < r => k1 = r1)
                            /\ (r1 = r => k1 \in {r, r + 1}) /\ (r1 > r => k1 = r1 + 1)
    BY <1>m
  <2>2. PICK k2 \in Pages : /\ x \in cont[k2] /\ (r2 < r => k2 = r2)
                            /\ (r2 = r => k2 \in {r, r + 1}) /\ (r2 > r => k2 = r2 + 1)
    BY <1>m
  <2>3. k1 # k2 BY <2>1, <2>2
  <2> QED BY <2>1, <2>2, <2>3 DEF IndInv, R_disj
<1>4. R_sorted'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, r1 < r2, NEW a \in cont'[r1], NEW b \in cont'[r2]
               PROVE Oid(a) <= Oid(b)
    BY DEF R_sorted
  <2>1. PICK k1 \in Pages : /\ a \in cont[k1] /\ (r1 < r => k1 = r1)
                            /\ (r1 = r => k1 \in {r, r + 1}) /\ (r1 > r => k1 = r1 + 1)
    BY <1>m
  <2>2. PICK k2 \in Pages : /\ b \in cont[k2] /\ (r2 < r => k2 = r2)
                            /\ (r2 = r => k2 \in {r, r + 1}) /\ (r2 > r => k2 = r2 + 1)
    BY <1>m
  <2>3. k1 < k2 BY <2>1, <2>2
  <2> QED BY <2>1, <2>2, <2>3 DEF IndInv, R_sorted
<1>5. R_lower'
  <2> SUFFICES ASSUME NEW i \in Pages, i >= 2, NEW a \in cont'[i] PROVE sep'[i] <= Oid(a)
    BY DEF R_lower
  <2>0. r + 1 \in Pages BY <1>0 DEF Pages
  <2>1. CASE i < r BY <2>1, <1>0 DEF IndInv, R_lower
  <2>2. CASE i = r /\ a \in cont[r] BY <2>2, <1>0 DEF IndInv, R_lower
  <2>3. CASE i = r /\ a \in cont[r + 1]
    <3>1. sep[r + 1] <= Oid(a) BY <2>3, <2>0 DEF IndInv, R_lower
    <3>2. sep[r] <= sep[r + 1] BY <2>3, <2>0, <1>0 DEF IndInv, R_mono
    <3>3. sep'[i] = sep[r] BY <2>3, <1>0
    <3>4. sep[r] \in Nat /\ sep[r + 1] \in Nat BY <2>0, <2>3, SepNat DEF IndInv
    <3>5. Oid(a) \in Nat BY <2>3, <2>0, ContNat DEF IndInv
    <3> QED BY <3>1, <3>2, <3>3, <3>4, <3>5
  <2>4. CASE i > r /\ i < np
    <3>1. i + 1 \in Pages /\ a \in cont[i + 1] /\ sep'[i] = sep[i + 1] BY <2>4, <1>0 DEF Pages
    <3> QED BY <3>1 DEF IndInv, R_lower
  <2>5. CASE i > r /\ i >= np BY <2>5, <1>0
  <2> QED BY <2>1, <2>2, <2>3, <2>4, <2>5, <1>0
<1>6. R_upper'
  <2> SUFFICES ASSUME NEW i \in Pages, i + 1 <= np', NEW a \in cont'[i] PROVE Oid(a) <= sep'[i + 1]
    BY DEF R_upper
  <2>0. i + 1 \in Pages /\ i + 2 \in Pages /\ i + 2 <= np BY <1>0 DEF IndInv, TypeOK, Pages
  <2>1. CASE i < r BY <2>1, <2>0, <1>0 DEF IndInv, R_upper
  <2>2. CASE i = r /\ a \in cont[r]
    <3>1. Oid(a) <= sep[r + 1] BY <2>2, <2>0 DEF IndInv, R_upper
    <3>2. sep[r + 1] <= sep[r + 2] BY <2>2, <2>0 DEF IndInv, R_mono, TypeOK, Pages
    <3>3. sep'[i + 1] = sep[r + 2] BY <2>2, <2>0, <1>0
    <3>4. sep[r + 1] \in Nat /\ sep[r + 2] \in Nat BY <2>2, <2>0, SepNat DEF IndInv
    <3>5. Oid(a) \in Nat BY <2>2, <1>0, ContNat DEF IndInv
    <3> QED BY <3>1, <3>2, <3>3, <3>4, <3>5
  <2>3. CASE i = r /\ a \in cont[r + 1]
    <3>1. sep'[i + 1] = sep[r + 2] BY <2>3, <2>0, <1>0
    <3> QED BY <2>3, <2>0, <3>1 DEF IndInv, R_upper
  <2>4. CASE i > r
    <3>1. a \in cont[i + 1] /\ sep'[i + 1] = sep[i + 2] BY <2>4, <2>0, <1>0
    <3> QED BY <3>1, <2>0 DEF IndInv, R_upper
  <2> QED BY <2>1, <2>2, <2>3, <2>4, <1>0
<1>7. R_mono'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, 2 <= r1, r1 <= r2, r2 <= np' PROVE sep'[r1] <= sep'[r2]
    BY DEF R_mono
  <2>1. r2 + 1 \in Pages /\ r2 < np BY <1>0 DEF IndInv, TypeOK, Pages
  <2>2. sep'[r1] = (IF r1 <= r THEN sep[r1] ELSE sep[r1 + 1]) /\ sep'[r2] = (IF r2 <= r THEN sep[r2] ELSE sep[r2 + 1])
    BY <2>1, <1>0
  <2> QED BY <2>1, <2>2 DEF IndInv, R_mono, TypeOK, Pages
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7 DEF IndInv

LEMMA RedistInv ==
  ASSUME IndInv, NEW r \in Pages, NEW M \in SUBSET Obj, NEW m \in Obj, NEW s1 \in OidVals, Redist(r, M, m, s1)
  PROVE IndInv'
<1> USE OidNat
<1> DEFINE Rest == cont[r + 1] \ M
<1>1a. /\ np' = np /\ r \in 1..(np - 1) /\ r + 1 \in Pages
       /\ M \subseteq cont[r + 1] /\ M # {} /\ m \in Rest
       /\ \A x \in Rest : Oid(m) <= Oid(x)
       /\ \A a \in M, x \in Rest : Oid(a) <= Oid(x)
  BY DEF Redist, IndInv, TypeOK
<1>1b. /\ cont' = [cont EXCEPT ![r] = @ \cup M, ![r + 1] = @ \ M]
       /\ sep' = FreeFirst(s1, [sep EXCEPT ![r + 1] = Oid(m)])
  BY DEF Redist
<1>1c. cont \in [Pages -> SUBSET Obj] /\ sep \in [Pages -> OidVals] BY DEF IndInv, TypeOK
<1>1f. /\ cont'[r] = cont[r] \cup M /\ cont'[r + 1] = Rest
       /\ \A i \in Pages : i # r /\ i # r + 1 => cont'[i] = cont[i]
  BY <1>1a, <1>1b, <1>1c
<1>1d. \A i \in Pages : cont'[i] = IF i = r THEN cont[r] \cup M ELSE IF i = r + 1 THEN Rest ELSE cont[i]
  BY <1>1f
<1>1e. \A i \in Pages : i >= 2 => sep'[i] = IF i = r + 1 THEN Oid(m) ELSE sep[i]
  BY <1>1a, <1>1b, <1>1c DEF FreeFirst
<1>0. /\ np' = np /\ r \in 1..(np - 1) /\ r + 1 \in Pages
      /\ M \subseteq cont[r + 1] /\ M # {} /\ m \in Rest
      /\ \A x \in Rest : Oid(m) <= Oid(x)
      /\ \A a \in M, x \in Rest : Oid(a) <= Oid(x)
      /\ \A i \in Pages : cont'[i] = IF i = r THEN cont[r] \cup M ELSE IF i = r + 1 THEN Rest ELSE cont[i]
      /\ \A i \in Pages : i >= 2 => sep'[i] = IF i = r + 1 THEN Oid(m) ELSE sep[i]
  BY <1>1a, <1>1d, <1>1e
<1>t. cont' \in [Pages -> SUBSET Obj] /\ sep' \in [Pages -> OidVals]
  BY <1>1a, <1>1b, <1>1c, OidIn DEF FreeFirst
<1> HIDE DEF Redist
<1>n. np \in 0..MaxP BY DEF IndInv, TypeOK
<1> USE <1>n
<1>a. sep[r + 1] <= Oid(m) BY <1>0 DEF IndInv, R_lower
<1>b. r + 2 <= np => Oid(m) <= sep[r + 2] BY <1>0 DEF IndInv, R_upper
<1>c. \A a \in M : sep[r + 1] <= Oid(a) BY <1>0 DEF IndInv, R_lower
<1>1. TypeOK' BY <1>0, <1>t DEF IndInv, TypeOK, Pages
<1>2. R_shape' BY <1>0 DEF IndInv, R_shape, Pages
<1>3. R_disj' BY <1>0 DEF IndInv, R_disj, Pages
<1>4. R_sorted'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, r1 < r2, NEW a \in cont'[r1], NEW b \in cont'[r2]
               PROVE Oid(a) <= Oid(b)
    BY DEF R_sorted
  <2>1. CASE r1 = r /\ a \in M /\ r2 = r + 1 BY <2>1, <1>0
  <2>2. CASE r1 = r /\ a \in M /\ r2 # r + 1
    <3>1. b \in cont[r2] /\ r + 1 < r2 BY <2>2, <1>0
    <3> QED BY <3>1, <2>2, <1>0 DEF IndInv, R_sorted
  <2>3. CASE ~(r1 = r /\ a \in M) /\ r2 = r /\ b \in M
    <3>1. a \in cont[r1] /\ r1 < r + 1 BY <2>3, <1>0
    <3> QED BY <3>1, <2>3, <1>0 DEF IndInv, R_sorted
  <2>4. CASE ~(r1 = r /\ a \in M) /\ ~(r2 = r /\ b \in M)
    <3>1. a \in cont[r1] /\ b \in cont[r2] BY <2>4, <1>0
    <3> QED BY <3>1 DEF IndInv, R_sorted
  <2> QED BY <2>1, <2>2, <2>3, <2>4
<1>5. R_lower'
  <2> SUFFICES ASSUME NEW i \in Pages, i >= 2, NEW a \in cont'[i] PROVE sep'[i] <= Oid(a)
    BY DEF R_lower
  <2>1. CASE i = r + 1 BY <2>1, <1>0
  <2>2. CASE i = r /\ a \in M
    <3>1. sep[r] <= sep[r + 1] BY <2>2, <1>0 DEF IndInv, R_mono, R_shape, TypeOK, Pages
    <3>2. sep[r] \in Nat /\ sep[r + 1] \in Nat BY <1>0 DEF IndInv, TypeOK, Pages
    <3> QED BY <3>1, <3>2, <1>c, <2>2, <1>0
  <2>3. CASE i # r + 1 /\ ~(i = r /\ a \in M) BY <2>3, <1>0 DEF IndInv, R_lower
  <2> QED BY <2>1, <2>2, <2>3
<1>6. R_upper'
  <2> SUFFICES ASSUME NEW i \in Pages, i + 1 <= np', NEW a \in cont'[i] PROVE Oid(a) <= sep'[i + 1]
    BY DEF R_upper
  <2>0. i + 1 \in Pages /\ i + 1 >= 2 BY <1>0 DEF IndInv, TypeOK, Pages
  <2>1. CASE i = r /\ a \in M BY <2>1, <2>0, <1>0
  <2>2. CASE i = r /\ a \notin M
    <3>1. a \in cont[r] BY <2>2, <1>0
    <3>2. Oid(a) <= sep[r + 1] BY <3>1, <2>2, <1>0 DEF IndInv, R_upper
    <3>3. sep[r + 1] \in Nat BY <1>0 DEF IndInv, TypeOK, Pages
    <3> QED BY <3>2, <3>3, <1>a, <2>2, <2>0, <1>0, ContNat, SepNat DEF IndInv
  <2>3. CASE i = r + 1
    <3>1. a \in cont[r + 1] /\ r + 2 <= np BY <2>3, <1>0
    <3>2. sep'[i + 1] = sep[r + 2] BY <2>3, <2>0, <1>0
    <3> QED BY <3>1, <3>2, <2>3 DEF IndInv, R_upper
  <2>4. CASE i # r /\ i # r + 1
    <3>1. a \in cont[i] /\ sep'[i + 1] = (IF i + 1 = r + 1 THEN Oid(m) ELSE sep[i + 1]) BY <2>4, <2>0, <1>0
    <3>2. i + 1 <= np /\ sep'[i + 1] = sep[i + 1] BY <3>1, <2>4, <1>0
    <3> QED BY <3>1, <3>2 DEF IndInv, R_upper
  <2> QED BY <2>1, <2>2, <2>3, <2>4
<1>7. R_mono'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, 2 <= r1, r1 <= r2, r2 <= np' PROVE sep'[r1] <= sep'[r2]
    BY DEF R_mono
  <2>1. sep'[r1] = (IF r1 = r + 1 THEN Oid(m) ELSE sep[r1]) /\ sep'[r2] = (IF r2 = r + 1 THEN Oid(m) ELSE sep[r2])
    BY <1>0
  <2>2. sep[r1] \in Nat /\ sep[r2] \in Nat /\ sep[r + 1] \in Nat BY <1>0 DEF IndInv, TypeOK, Pages
  <2>3. CASE r1 = r + 1 /\ r2 = r + 1 BY <2>1, <2>3
  <2>4. CASE r1 = r + 1 /\ r2 > r + 1
    <3>1. Oid(m) <= sep[r + 2] /\ sep[r + 2] <= sep[r2] BY <2>4, <1>b, <1>0 DEF IndInv, R_mono, TypeOK, Pages
    <3>2. sep[r + 2] \in Nat BY <2>4, <1>0, SepNat DEF IndInv
    <3> QED BY <2>1, <2>4, <3>1, <3>2, ContNat, SepNat DEF IndInv
  <2>5. CASE r1 # r + 1 /\ r2 = r + 1
    <3>1. sep[r1] <= sep[r + 1] BY <2>5, <1>0 DEF IndInv, R_mono, TypeOK, Pages
    <3> QED BY <2>1, <2>2, <2>5, <3>1, <1>a
  <2>6. CASE r1 # r + 1 /\ r2 # r + 1
    <3>1. r2 <= np /\ sep'[r1] = sep[r1] /\ sep'[r2] = sep[r2] BY <2>1, <2>6, <1>0
    <3> QED BY <3>1 DEF IndInv, R_mono
  <2> QED BY <2>3, <2>4, <2>5, <2>6
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7 DEF IndInv

LEMMA GrowRightInv ==
  ASSUME IndInv, NEW o \in Obj, NEW s1 \in OidVals, GrowRight(o, s1)
  PROVE IndInv'
<1> USE OidNat
<1>0. /\ np \in 1..(MaxP - 1) /\ np' = np + 1 /\ np + 1 \in Pages
      /\ \A i \in Pages : \A a \in cont[i] : Oid(a) < Oid(o)
      /\ \A i \in Pages : cont'[i] = IF i = np + 1 THEN {o} ELSE cont[i]
      /\ \A i \in Pages : i >= 2 => sep'[i] = IF i = np + 1 THEN Oid(o) ELSE sep[i]
  BY DEF GrowRight, FreeFirst, AllObjs, IndInv, TypeOK, Pages
<1>t. cont' \in [Pages -> SUBSET Obj] /\ sep' \in [Pages -> OidVals]
  BY OidIn DEF GrowRight, FreeFirst, IndInv, TypeOK
<1> HIDE DEF GrowRight
<1>n. np \in 0..MaxP BY DEF IndInv, TypeOK
<1> USE <1>n
<1>1. TypeOK' BY <1>0, <1>t DEF IndInv, TypeOK, Pages
<1>2. R_shape' BY <1>0 DEF IndInv, R_shape, Pages
<1>3. R_disj' BY <1>0 DEF IndInv, R_disj, R_shape, Pages
<1>4. R_sorted'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, r1 < r2, NEW a \in cont'[r1], NEW b \in cont'[r2]
               PROVE Oid(a) <= Oid(b)
    BY DEF R_sorted
  <2>1. CASE r2 = np + 1
    <3>1. b = o /\ a \in cont[r1] BY <2>1, <1>0
    <3>2. Oid(a) < Oid(o) BY <3>1, <1>0
    <3>3. Oid(a) \in Nat BY <3>1, ContNat DEF IndInv
    <3> QED BY <3>1, <3>2, <3>3
  <2>2. CASE r2 # np + 1
    <3>1. b \in cont[r2] BY <2>2, <1>0
    <3>2. r2 <= np BY <3>1 DEF IndInv, R_shape
    <3>3. a \in cont[r1] BY <3>2, <1>0
    <3> QED BY <3>1, <3>3 DEF IndInv, R_sorted
  <2> QED BY <2>1, <2>2
<1>5. R_lower' BY <1>0 DEF IndInv, R_lower, R_shape, Pages
<1>6. R_upper'
  <2> SUFFICES ASSUME NEW i \in Pages, i + 1 <= np', NEW a \in cont'[i] PROVE Oid(a) <= sep'[i + 1]
    BY DEF R_upper
  <2>1. CASE i + 1 = np + 1 BY <2>1, <1>0, ContNat, SepNat DEF IndInv
  <2>2. CASE i + 1 < np + 1 BY <2>2, <1>0 DEF IndInv, R_upper, TypeOK, Pages
  <2> QED BY <2>1, <2>2, <1>0
<1>7. R_mono'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, 2 <= r1, r1 <= r2, r2 <= np' PROVE sep'[r1] <= sep'[r2]
    BY DEF R_mono
  <2>1. CASE r2 = np + 1 /\ r1 <= np
    <3>1. cont[np] # {} BY <1>0 DEF IndInv, R_shape, Pages
    <3>2. PICK a \in cont[np] : TRUE BY <3>1
    <3>3. sep[r1] <= sep[np] BY <2>1, <1>0 DEF IndInv, R_mono, Pages
    <3>4. sep[np] <= Oid(a) BY <2>1, <1>0 DEF IndInv, R_lower, Pages
    <3>5. Oid(a) < Oid(o) BY <1>0 DEF Pages
    <3>6. sep[r1] \in Nat /\ sep[np] \in Nat BY <2>1, <1>0, SepNat DEF IndInv
    <3> QED BY <3>3, <3>4, <3>5, <3>6, <2>1, <1>0, ContNat, SepNat DEF IndInv
  <2>2. CASE r2 <= np BY <2>2, <1>0 DEF IndInv, R_mono
  <2>3. CASE r1 = np + 1 BY <2>3, <1>0
  <2> QED BY <2>1, <2>2, <2>3, <1>0
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7 DEF IndInv

LEMMA SplitInsInv ==
  ASSUME IndInv, NEW o \in Obj, NEW r \in Pages, NEW B \in SUBSET Obj, NEW m \in Obj, NEW lo \in BOOLEAN,
         NEW s1 \in OidVals, SplitIns(o, r, B, m, lo, s1)
  PROVE IndInv'
<1> USE OidNat
<1> DEFINE Low == IF lo THEN (cont[r] \ B) \cup {o} ELSE cont[r] \ B
           Up == IF lo THEN B ELSE B \cup {o}
<1>0. /\ np' = np + 1 /\ r \in 1..np /\ np < MaxP /\ r + 1 \in Pages
      /\ r = 1 \/ sep[r] <= Oid(o)
      /\ r < np => Oid(o) < sep[r + 1]
      /\ \A i \in Pages : o \notin cont[i]
      /\ B \subseteq cont[r] /\ m \in B /\ cont[r] \ B # {}
      /\ \A b \in B : Oid(m) <= Oid(b)
      /\ \A a \in cont[r] \ B, b \in B : Oid(a) <= Oid(b)
      /\ lo => Oid(o) <= Oid(m)
      /\ ~lo => Oid(m) <= Oid(o)
      /\ \A i \in Pages : cont'[i] = IF i < r THEN cont[i] ELSE IF i = r THEN Low ELSE IF i = r + 1 THEN Up
                                     ELSE IF i - 1 <= np THEN cont[i - 1] ELSE {}
      /\ \A i \in Pages : i >= 2 => sep'[i] = IF i <= r THEN sep[i] ELSE IF i = r + 1 THEN Oid(m)
                                              ELSE IF i - 1 <= np THEN sep[i - 1] ELSE 0
  BY DEF SplitIns, Owns, ShiftR, FreeFirst, AllObjs, IndInv, TypeOK, Pages
<1>t. cont' \in [Pages -> SUBSET Obj] /\ sep' \in [Pages -> OidVals]
  BY OidIn DEF SplitIns, ShiftR, FreeFirst, IndInv, TypeOK
<1> HIDE DEF SplitIns, ShiftR
<1>n. np \in 0..MaxP BY DEF IndInv, TypeOK
<1> USE <1>n
<1>a. r # 1 => sep[r] <= Oid(m) BY <1>0 DEF IndInv, R_lower
<1>b. r < np => Oid(m) <= sep[r + 1] BY <1>0 DEF IndInv, R_upper
<1>c. r < np => \A b \in cont[r] : Oid(b) <= sep[r + 1] BY <1>0 DEF IndInv, R_upper
<1>d. \A i \in Pages : i < r => \A a \in cont[i] : Oid(a) <= Oid(o)
  <2> SUFFICES ASSUME NEW i \in Pages, i < r, NEW a \in cont[i] PROVE Oid(a) <= Oid(o) OBVIOUS
  <2>1. i + 1 <= np /\ Oid(a) <= sep[i + 1] BY <1>0 DEF IndInv, R_upper
  <2>2. sep[i + 1] <= sep[r] BY <1>0 DEF IndInv, R_mono, TypeOK, Pages
  <2>3. sep[i + 1] \in Nat /\ sep[r] \in Nat BY <1>0, SepNat DEF IndInv
  <2> QED BY <2>1, <2>2, <2>3, <1>0, ContNat, SepNat DEF IndInv
<1>e. \A i \in Pages : r < i /\ i <= np => \A a \in cont[i] : Oid(o) <= Oid(a)
  <2> SUFFICES ASSUME NEW i \in Pages, r < i, i <= np, NEW a \in cont[i] PROVE Oid(o) <= Oid(a) OBVIOUS
  <2>1. sep[i] <= Oid(a) BY <1>0 DEF IndInv, R_lower
  <2>2. sep[r + 1] <= sep[i] BY <1>0 DEF IndInv, R_mono, TypeOK, Pages
  <2>3. sep[i] \in Nat /\ sep[r + 1] \in Nat BY <1>0 DEF IndInv, TypeOK, Pages
  <2> QED BY <2>1, <2>2, <2>3, <1>0, ContNat, SepNat DEF IndInv
<1>1. TypeOK' BY <1>0, <1>t DEF IndInv, TypeOK, Pages
<1>2. R_shape'
  <2> SUFFICES ASSUME NEW i \in Pages
               PROVE (i <= np' => cont'[i] # {}) /\ (i > np' => cont'[i] = {} /\ (i >= 2 => sep'[i] = 0))
    BY DEF R_shape
  <2>1. CASE i < r
    <3>1. cont'[i] = cont[i] /\ i <= np' /\ i <= np BY <2>1, <1>0
    <3> QED BY <3>1, <1>0 DEF IndInv, R_shape
  <2>2. CASE i = r
    <3>1. cont'[i] = Low BY <2>2, <1>0
    <3>2. i <= np' BY <2>2, <1>0
    <3>3. cont[r] \ B \subseteq Low OBVIOUS
    <3>4. Low # {} BY <3>3, <1>0
    <3> QED BY <3>1, <3>2, <3>4, <1>0
  <2>3. CASE i = r + 1
    <3>1. cont'[i] = Up BY <2>3, <1>0
    <3>2. i <= np' BY <2>3, <1>0
    <3>3. m \in Up BY <1>0
    <3> QED BY <3>1, <3>2, <3>3, <1>0
  <2>4. CASE i > r + 1 /\ i - 1 <= np
    <3>1. cont'[i] = cont[i - 1] /\ i - 1 \in Pages /\ i <= np' BY <2>4, <1>0
    <3> QED BY <3>1, <2>4, <1>0 DEF IndInv, R_shape
  <2>5. CASE i > r + 1 /\ i - 1 > np
    <3>1. cont'[i] = {} /\ (i >= 2 => sep'[i] = 0) /\ i > np' BY <2>5, <1>0
    <3> QED BY <3>1, <1>0
  <2> QED BY <2>1, <2>2, <2>3, <2>4, <2>5
<1>3. R_disj'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, r1 # r2, NEW x \in cont'[r1], x \in cont'[r2] PROVE FALSE
    BY DEF R_disj
  <2> DEFINE g(i) == IF i < r THEN i ELSE IF i <= r + 1 THEN r ELSE i - 1
  <2>1. \A i \in Pages : \A y \in cont'[i] : y = o \/ (g(i) \in Pages /\ y \in cont[g(i)]) BY <1>0
  <2>2. CASE x = o
    <3>1. \A i \in Pages : o \in cont'[i] => i = (IF lo THEN r ELSE r + 1) BY <1>0
    <3> QED BY <3>1, <2>2
  <2>3. CASE x # o
    <3>1. x \in cont[g(r1)] /\ x \in cont[g(r2)] /\ g(r1) \in Pages /\ g(r2) \in Pages BY <2>1, <2>3
    <3>2. CASE g(r1) # g(r2) BY <3>1, <3>2 DEF IndInv, R_disj
    <3>3. CASE g(r1) = g(r2)
      <4>1. (r1 = r /\ r2 = r + 1) \/ (r1 = r + 1 /\ r2 = r) BY <3>3
      <4>2. x \in cont[r] \ B /\ x \in B BY <4>1, <2>3, <1>0
      <4> QED BY <4>2
    <3> QED BY <3>2, <3>3
  <2> QED BY <2>2, <2>3
<1>4. R_sorted'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, r1 < r2, NEW a \in cont'[r1], NEW b \in cont'[r2]
               PROVE Oid(a) <= Oid(b)
    BY DEF R_sorted
  <2>1. CASE r1 < r /\ r2 < r BY <2>1, <1>0 DEF IndInv, R_sorted
  <2>2. CASE r1 < r /\ r2 \in {r, r + 1}
    <3>1. a \in cont[r1] BY <2>2, <1>0
    <3>2. CASE b = o BY <3>1, <3>2, <1>d, <2>2
    <3>3. CASE b # o
      <4>1. b \in cont[r] BY <3>3, <2>2, <1>0
      <4> QED BY <3>1, <4>1, <2>2, <1>0 DEF IndInv, R_sorted
    <3> QED BY <3>2, <3>3
  <2>3. CASE r1 < r /\ r2 > r + 1
    <3>1. a \in cont[r1] /\ b \in cont[r2 - 1] /\ r2 - 1 \in Pages /\ r1 < r2 - 1 BY <2>3, <1>0 DEF Pages
    <3> QED BY <3>1 DEF IndInv, R_sorted
  <2>4. CASE r1 = r /\ r2 = r + 1
    <3>1. CASE a = o /\ b # o BY <3>1, <2>4, <1>0
    <3>2. CASE a # o /\ b = o BY <3>2, <2>4, <1>0, ContNat, SepNat DEF IndInv
    <3>3. CASE a # o /\ b # o BY <3>3, <2>4, <1>0
    <3> QED BY <3>1, <3>2, <3>3, <2>4, <1>0
  <2>5. CASE r1 \in {r, r + 1} /\ r2 > r + 1
    <3>1. b \in cont[r2 - 1] /\ r2 - 1 \in Pages /\ r < r2 - 1 /\ r2 - 1 <= np BY <2>5, <1>0 DEF Pages
    <3>2. CASE a = o BY <3>1, <3>2, <1>e
    <3>3. CASE a # o
      <4>1. a \in cont[r] BY <3>3, <2>5, <1>0
      <4> QED BY <4>1, <3>1 DEF IndInv, R_sorted
    <3> QED BY <3>2, <3>3
  <2>6. CASE r1 > r + 1
    <3>1. a \in cont[r1 - 1] /\ b \in cont[r2 - 1] /\ r1 - 1 \in Pages /\ r2 - 1 \in Pages /\ r1 - 1 < r2 - 1
      BY <2>6, <1>0 DEF Pages
    <3> QED BY <3>1 DEF IndInv, R_sorted
  <2> QED BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6
<1>5. R_lower'
  <2> SUFFICES ASSUME NEW i \in Pages, i >= 2, NEW a \in cont'[i] PROVE sep'[i] <= Oid(a)
    BY DEF R_lower
  <2>1. CASE i < r BY <2>1, <1>0 DEF IndInv, R_lower
  <2>2. CASE i = r
    <3>1. sep'[i] = sep[r] /\ r # 1 BY <2>2, <1>0
    <3>2. CASE a = o BY <3>1, <3>2, <1>0
    <3>3. CASE a # o BY <3>1, <3>3, <2>2, <1>0 DEF IndInv, R_lower
    <3> QED BY <3>2, <3>3
  <2>3. CASE i = r + 1
    <3>1. sep'[i] = Oid(m) BY <2>3, <1>0
    <3> QED BY <3>1, <2>3, <1>0
  <2>4. CASE i > r + 1
    <3>1. i - 1 <= np /\ a \in cont[i - 1] /\ sep'[i] = sep[i - 1] /\ i - 1 \in Pages /\ i - 1 >= 2
      BY <2>4, <1>0 DEF Pages
    <3> QED BY <3>1 DEF IndInv, R_lower
  <2> QED BY <2>1, <2>2, <2>3, <2>4
<1>6. R_upper'
  <2> SUFFICES ASSUME NEW i \in Pages, i + 1 <= np', NEW a \in cont'[i] PROVE Oid(a) <= sep'[i + 1]
    BY DEF R_upper
  <2>0. i + 1 \in Pages /\ i + 1 >= 2 BY <1>0 DEF Pages
  <2>1. CASE i + 1 < r
    <3>1. a \in cont[i] /\ sep'[i + 1] = sep[i + 1] /\ i + 1 <= np BY <2>1, <2>0, <1>0
    <3> QED BY <3>1 DEF IndInv, R_upper
  <2>2. CASE i + 1 = r
    <3>1. a \in cont[i] /\ sep'[i + 1] = sep[r] /\ i + 1 <= np BY <2>2, <2>0, <1>0
    <3> QED BY <3>1, <2>2 DEF IndInv, R_upper
  <2>3. CASE i = r
    <3>1. sep'[i + 1] = Oid(m) BY <2>3, <2>0, <1>0
    <3>2. CASE a = o BY <3>1, <3>2, <2>3, <1>0
    <3>3. CASE a # o
      <4>1. a \in cont[r] \ B BY <3>3, <2>3, <1>0
      <4> QED BY <4>1, <3>1, <1>0
    <3> QED BY <3>2, <3>3
  <2>4. CASE i = r + 1
    <3>1. i + 1 - 1 <= np /\ sep'[i + 1] = sep[r + 1] /\ r < np BY <2>4, <2>0, <1>0
    <3>2. CASE a = o BY <3>1, <3>2, <1>0, ContNat, SepNat DEF IndInv
    <3>3. CASE a # o
      <4>1. a \in cont[r] BY <3>3, <2>4, <1>0
      <4> QED BY <4>1, <3>1, <1>c
    <3> QED BY <3>2, <3>3
  <2>5. CASE i > r + 1
    <3>1. a \in cont[i - 1] /\ sep'[i + 1] = sep[i] /\ i - 1 \in Pages /\ (i - 1) + 1 <= np
      BY <2>5, <2>0, <1>0 DEF Pages
    <3> QED BY <3>1 DEF IndInv, R_upper
  <2> QED BY <2>1, <2>2, <2>3, <2>4, <2>5
<1>7. R_mono'
  <2> SUFFICES ASSUME NEW r1 \in Pages, NEW r2 \in Pages, 2 <= r1, r1 <= r2, r2 <= np' PROVE sep'[r1] <= sep'[r2]
    BY DEF R_mono
  <2> DEFINE S(i) == IF i <= r THEN sep[i] ELSE IF i = r + 1 THEN Oid(m) ELSE sep[i - 1]
  <2>1. sep'[r1] = S(r1) /\ sep'[r2] = S(r2) BY <1>0
  <2>3. CASE r2 <= r BY <2>1, <2>3, <1>0 DEF IndInv, R_mono
  <2>4. CASE r1 <= r /\ r2 = r + 1
    <3>1. r # 1 /\ r <= np BY <2>4, <1>0
    <3>2. sep[r1] <= sep[r] BY <3>1, <2>4 DEF IndInv, R_mono
    <3>3. sep[r] <= Oid(m) BY <3>1, <1>a
    <3>4. sep[r1] \in Nat /\ sep[r] \in Nat BY <2>4, SepNat DEF IndInv
    <3>5. sep'[r1] = sep[r1] /\ sep'[r2] = Oid(m) BY <2>1, <2>4
    <3> QED BY <3>2, <3>3, <3>4, <3>5
  <2>5. CASE r1 <= r /\ r2 > r + 1
    <3>1. sep[r1] <= sep[r2 - 1] BY <2>5, <1>0 DEF IndInv, R_mono, Pages
    <3> QED BY <2>1, <2>5, <3>1
  <2>6. CASE r1 = r + 1 /\ r2 = r + 1 BY <2>1, <2>6
  <2>7. CASE r1 = r + 1 /\ r2 > r + 1
    <3>0. r < np /\ r2 - 1 <= np /\ r2 - 1 \in Pages BY <2>7, <1>0
    <3>1. sep[r + 1] <= sep[r2 - 1] BY <3>0, <2>7, <1>0 DEF IndInv, R_mono
    <3>2. sep[r + 1] \in Nat /\ sep[r2 - 1] \in Nat BY <3>0, <1>0, SepNat DEF IndInv
    <3>3. Oid(m) <= sep[r + 1] BY <3>0, <1>b
    <3>4. sep'[r1] = Oid(m) /\ sep'[r2] = sep[r2 - 1] BY <2>1, <2>7
    <3> QED BY <3>1, <3>2, <3>3, <3>4
  <2>8. CASE r1 > r + 1 BY <2>1, <2>8, <1>0 DEF IndInv, R_mono, Pages
  <2> QED BY <2>3, <2>4, <2>5, <2>6, <2>7, <2>8
<1> QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7 DEF IndInv

-----------------------------------------------------------------------------
THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1>0. np \in Nat /\ \A r \in 1..np : r \in Pages /\ cont[r] \subseteq Obj
  BY DEF IndInv, TypeOK, Pages
<1>1. CASE Next
  <2> PICK s1 \in OidVals :
        \/ \E o \in Obj : AddFirst(o, s1) \/ GrowRight(o, s1)
        \/ \E r \in 1..np :
             \/ \E o \in Obj : Ins(o, r, s1)
             \/ \E o \in cont[r] : Rem(o, r, s1) \/ RemPage(o, r, s1)
             \/ \E o \in Obj, B \in SUBSET cont[r], lo \in BOOLEAN : \E m \in B : SplitIns(o, r, B, m, lo, s1)
             \/ /\ r < np
                /\ \/ Merge(r, s1)
                   \/ \E M \in SUBSET cont[r + 1] : \E m \in cont[r + 1] \ M : Redist(r, M, m, s1)
    BY <1>1 DEF Next
  <2>1. CASE \E o \in Obj : AddFirst(o, s1) \/ GrowRight(o, s1)
    BY <2>1, AddFirstInv, GrowRightInv
  <2>2. CASE \E r \in 1..np : \E o \in Obj : Ins(o, r, s1)
    BY <2>2, <1>0, InsInv
  <2>3. CASE \E r \in 1..np : \E o \in cont[r] : Rem(o, r, s1) \/ RemPage(o, r, s1)
    BY <2>3, <1>0, RemInv, RemPageInv
  <2>4. CASE \E r \in 1..np : \E o \in Obj, B \in SUBSET cont[r], lo \in BOOLEAN : \E m \in B : SplitIns(o, r, B, m, lo, s1)
    BY <2>4, <1>0, SplitInsInv
  <2>5. CASE \E r \in 1..np : r < np /\ Merge(r, s1)
    BY <2>5, <1>0, MergeInv
  <2>6. CASE \E r \in 1..np : r < np /\ \E M \in SUBSET cont[r + 1] : \E m \in cont[r + 1] \ M : Redist(r, M, m, s1)
    <3> PICK r \in 1..np : r < np /\ \E M \in SUBSET cont[r + 1] : \E m \in cont[r + 1] \ M : Redist(r, M, m, s1)
      BY <2>6
    <3> PICK M \in SUBSET cont[r + 1] : \E m \in cont[r + 1] \ M : Redist(r, M, m, s1)
      OBVIOUS
    <3> PICK m \in cont[r + 1] \ M : Redist(r, M, m, s1)
      OBVIOUS
    <3>1. r + 1 \in 1..np BY <1>0
    <3> QED BY <3>1, <1>0, RedistInv
  <2> QED BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6
<1>2. CASE UNCHANGED vars
  <2>1. np' = np /\ cont' = cont /\ sep' = sep BY <1>2 DEF vars
  <2> QED BY <2>1 DEF IndInv, TypeOK, R_shape, R_disj, R_sorted, R_lower, R_upper, R_mono, Pages
<1> QED BY <1>1, <1>2
=============================================================================
