--------------------------- MODULE GcBufCap_proofs ---------------------------
(* Base of GcBuf_proofs: the correct variant, the per-node and per-address groups of IndInv's
   conjuncts the step proofs instantiate, and the arithmetic of qstr_reserve's capacity rule
   (IsNewCap) under Assm. *)
EXTENDS GcBuf, TLAPS

ASSUME Correct == Mutant = "none"

NFacts(n) == NIntact(n) /\ NMem(n) /\ NLive(n) /\ NCap1(n) /\ NCap2(n) /\ NCap3(n) /\ NCap4(n)
             /\ NCap5(n) /\ NCap6(n) /\ NCap7(n) /\ NCap8(n)
AFacts(a) == AOrphan(a) /\ AClamp(a) /\ AFree(a) /\ AGrown(a)
AllN == \A n \in Nodes : NFacts(n)
AllA == \A a \in Addr : AFacts(a)

\* the new capacity holds the request and stays within the chain or the limit
THEOREM CapBasic ==
  ASSUME NEW need \in 1 .. Limit, NEW c, IsNewCap(c, need)
  PROVE  /\ c \in Nat /\ need <= c /\ c <= Limit
         /\ c \in Caps \cup {Limit}
<1> USE Assm
<1>1. PICK p \in Caps : IsP2(p, need) /\ c = (IF p > Limit THEN MaxOf(need, Limit) ELSE p)
  BY DEF IsNewCap
<1>2. p \in Nat /\ need <= p
  BY <1>1 DEF IsP2
<1>3. CASE p > Limit
  BY <1>1, <1>2, <1>3 DEF MaxOf, Limit
<1>4. CASE ~(p > Limit)
  BY <1>1, <1>2, <1>4 DEF Limit
<1>. QED
  BY <1>3, <1>4

\* C4: the capacity is less than twice the request, or the chain's first size
THEOREM CapTwice ==
  ASSUME NEW need \in 1 .. Limit, NEW c, IsNewCap(c, need)
  PROVE  c <= MaxOf(Base, 2 * need - 1)
<1> USE Assm
<1>1. PICK p \in Caps : IsP2(p, need) /\ c = (IF p > Limit THEN MaxOf(need, Limit) ELSE p)
  BY DEF IsNewCap
<1>2. p \in Nat /\ need <= p /\ \A q \in Caps : need <= q => p <= q
  BY <1>1 DEF IsP2
<1>3. p <= MaxOf(Base, 2 * need - 1)
  <2>1. CASE p = Base
    BY <2>1 DEF MaxOf
  <2>2. CASE p # Base
    <3>1. p > Base
      BY <2>2, <1>2
    <3>2. PICK a \in Caps : 2 * a = p
      BY <3>1
    <3>3. a < need
      <4>1. a \in Nat /\ a < p
        BY <3>2, <3>1
      <4>. QED
        BY <4>1, <1>2
    <3>. QED
      BY <3>2, <3>3 DEF MaxOf
  <2>. QED
    BY <2>1, <2>2
<1>4. CASE p > Limit
  BY <1>1, <1>2, <1>3, <1>4 DEF MaxOf, Limit
<1>5. CASE ~(p > Limit)
  BY <1>1, <1>3, <1>5
<1>. QED
  BY <1>4, <1>5

\* C3: a request past a chain capacity h gets at least 2 h, or the limit
THEOREM CapDouble ==
  ASSUME NEW need \in 1 .. Limit, NEW c, IsNewCap(c, need), NEW h \in Caps, h < need
  PROVE  2 * h <= c \/ c = Limit
<1> USE Assm
<1>1. PICK p \in Caps : IsP2(p, need) /\ c = (IF p > Limit THEN MaxOf(need, Limit) ELSE p)
  BY DEF IsNewCap
<1>2. p \in Nat /\ need <= p /\ h \in Nat
  BY <1>1 DEF IsP2
<1>3. 2 * h <= p
  BY <1>2
<1>. QED
  BY <1>1, <1>3 DEF MaxOf, Limit
=============================================================================
