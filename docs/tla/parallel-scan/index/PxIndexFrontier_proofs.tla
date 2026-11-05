----------------------- MODULE PxIndexFrontier_proofs -----------------------
(* TLAPS proof that FInv is an inductive invariant of the frontier rule (no
   mutant) and implies NoFreedFix, for any finite set of leaves: the premises of
   the TLA rule INV1 (cubrid-tla PROOFS.md). *)
EXTENDS PxIndexFrontier, TLAPS

ASSUME NoMutant == Mutant = "none"

USE FAssm, NoMutant DEF NoLeaf

THEOREM InitInv == Init => FInv
  BY DEF Init, FInv, FTypeOK, Chain

LEMMA LStart == ASSUME NEW f \in Leaves PROVE FInv /\ Start(f) => FInv'
  BY DEF FInv, FTypeOK, Chain, Start

LEMMA LAdvance == FInv /\ Advance => FInv'
  BY DEF FInv, FTypeOK, Chain, Advance

LEMMA LUnprotect == FInv /\ Unprotect => FInv'
  BY DEF FInv, Unprotect

LEMMA LEndChain == FInv /\ EndChain => FInv'
  BY DEF FInv, FTypeOK, Chain, EndChain

LEMMA LDone == FInv /\ Done => FInv'
  BY DEF FInv, FTypeOK, Chain, Done, fvars

LEMMA LUnchanged == FInv /\ UNCHANGED fvars => FInv'
  BY DEF FInv, FTypeOK, Chain, fvars

LEMMA LSplit == ASSUME NEW l \in Leaves, NEW n \in Leaves PROVE FInv /\ Split(l, n) => FInv'
<1> SUFFICES ASSUME FInv, Split(l, n) PROVE FInv'
  OBVIOUS
<1>1. l # n /\ l # frontier /\ n # frontier
  BY DEF FInv, FTypeOK, Split, Locked
<1>2. \A p \in Leaves : nxt[p] # n
  BY DEF FInv, FTypeOK, Chain, Split
<1>3. FTypeOK'
  BY DEF FInv, FTypeOK, Split
<1>4. Chain'
  <2>1. \A p \in Leaves : inUse'[p] /\ nxt'[p] # NoLeaf => inUse'[nxt'[p]]
    BY <1>1 DEF FInv, FTypeOK, Chain, Split
  <2>2. \A p, q \in Leaves : inUse'[p] /\ inUse'[q] /\ nxt'[p] = nxt'[q] /\ nxt'[p] # NoLeaf => p = q
    BY <1>1, <1>2 DEF FInv, FTypeOK, Chain, Split
  <2>3. \A p \in Leaves : ~inUse'[p] => nxt'[p] = NoLeaf
    BY <1>1 DEF FInv, FTypeOK, Chain, Split
  <2>. QED BY <2>1, <2>2, <2>3 DEF Chain
<1>5. \E p \in Leaves : inUse'[p]
  BY DEF FInv, FTypeOK, Split
<1>6. frontier' # NoLeaf => started' /\ inUse'[frontier'] /\ current' = nxt'[frontier'] /\ current' # NoLeaf
  BY <1>1 DEF FInv, FTypeOK, Split
<1>. QED
  BY <1>3, <1>4, <1>5, <1>6 DEF FInv, Split

LEMMA LMerge == ASSUME NEW l \in Leaves PROVE FInv /\ Merge(l) => FInv'
<1> SUFFICES ASSUME FInv, Merge(l) PROVE FInv'
  OBVIOUS
<1> DEFINE r == nxt[l]
<1>1. r \in Leaves /\ r # l /\ inUse[r] /\ l # frontier /\ r # frontier
  BY DEF FInv, FTypeOK, Chain, Merge, Locked
<1>2. nxt[r] # r /\ (nxt[r] # NoLeaf => inUse[nxt[r]])
  BY <1>1 DEF FInv, FTypeOK, Chain, Merge
<1>3. \A p \in Leaves : p # l => nxt[p] # r
  BY <1>1 DEF FInv, FTypeOK, Chain, Merge
<1>4. frontier # NoLeaf => current # r
  BY <1>1, <1>3 DEF FInv, FTypeOK
<1>5. FTypeOK'
  BY <1>1 DEF FInv, FTypeOK, Merge
<1>6. Chain'
  <2>1. \A p \in Leaves : inUse'[p] /\ nxt'[p] # NoLeaf => inUse'[nxt'[p]]
    BY <1>1, <1>2, <1>3 DEF FInv, FTypeOK, Chain, Merge
  <2>2. \A p, q \in Leaves : inUse'[p] /\ inUse'[q] /\ nxt'[p] = nxt'[q] /\ nxt'[p] # NoLeaf => p = q
    BY <1>1, <1>2, <1>3 DEF FInv, FTypeOK, Chain, Merge
  <2>3. \A p \in Leaves : ~inUse'[p] => nxt'[p] = NoLeaf
    BY <1>1 DEF FInv, FTypeOK, Chain, Merge
  <2>. QED BY <2>1, <2>2, <2>3 DEF Chain
<1>7. \E p \in Leaves : inUse'[p]
  BY <1>1 DEF FInv, FTypeOK, Merge
<1>8. frontier' # NoLeaf => started' /\ inUse'[frontier'] /\ current' = nxt'[frontier'] /\ current' # NoLeaf
  BY <1>1, <1>4 DEF FInv, FTypeOK, Merge
<1>. QED
  BY <1>5, <1>6, <1>7, <1>8 DEF FInv, Merge

THEOREM StepInv == FInv /\ [FNext]_fvars => FInv'
<1> SUFFICES ASSUME FInv, [FNext]_fvars PROVE FInv'
  OBVIOUS
<1>1. CASE FNext
  BY <1>1, LStart, LAdvance, LUnprotect, LEndChain, LDone, LSplit, LMerge DEF FNext
<1>2. CASE UNCHANGED fvars
  BY <1>2, LUnchanged
<1>. QED
  BY <1>1, <1>2

THEOREM InvSafe == FInv => NoFreedFix
  BY DEF FInv, NoFreedFix
=============================================================================
