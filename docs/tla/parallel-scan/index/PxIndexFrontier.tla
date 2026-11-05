---------------------------- MODULE PxIndexFrontier ----------------------------
(* The frontier rule of the ascending parallel index scan: what keeps the
   dispatcher from fixing a freed leaf. PxIndexLeafDispatch (ascending) refines
   this module; its latches, keys and workers are abstracted away.

   The dispatcher starts at some leaf, then repeatedly fixes the saved right link
   of the frontier (the last leaf handed out while the chain goes on), which
   becomes the new frontier. The frontier's holder keeps it latched (protected)
   until then. A writer splits a leaf (a free page becomes its right neighbour)
   or merges a leaf's right neighbour into it and frees that page; both need X
   latches on the pages they change, so neither touches a protected frontier.
   Release mutant: the frontier's holder lets it go before its right leaf is
   fixed (before CBRD-27737). *)
EXTENDS Naturals, FiniteSets

CONSTANTS Leaves, Mutant
ASSUME FAssm == /\ IsFiniteSet(Leaves) /\ 0 \notin Leaves
                /\ Mutant \in {"none", "release_frontier"}
NoLeaf == 0

VARIABLES inUse, nxt, started, frontier, current, protected, fixFreed
fvars == <<inUse, nxt, started, frontier, current, protected, fixFreed>>

\* the leaf chain: links run between used leaves, injectively; a free leaf links nowhere
Chain ==
  /\ \A p \in Leaves : inUse[p] /\ nxt[p] # NoLeaf => inUse[nxt[p]]
  /\ \A p, q \in Leaves : inUse[p] /\ inUse[q] /\ nxt[p] = nxt[q] /\ nxt[p] # NoLeaf => p = q
  /\ \A p \in Leaves : ~inUse[p] => nxt[p] = NoLeaf

Init ==
  /\ inUse \in [Leaves -> BOOLEAN]
  /\ nxt \in [Leaves -> Leaves \cup {NoLeaf}]
  /\ Chain /\ \E p \in Leaves : inUse[p]       \* an index has at least one leaf
  /\ started = FALSE /\ frontier = NoLeaf /\ current = NoLeaf
  /\ protected = TRUE
  /\ fixFreed = FALSE

Locked(p) == protected /\ frontier # NoLeaf /\ p = frontier

\* the descent hands out leaf f; it is the frontier unless the chain ends there
Start(f) ==
  /\ ~started /\ inUse[f]
  /\ started' = TRUE
  /\ frontier' = IF nxt[f] = NoLeaf THEN NoLeaf ELSE f
  /\ current' = nxt[f]
  /\ UNCHANGED <<inUse, nxt, protected, fixFreed>>

\* the dispatcher fixes the frontier's saved right link, which becomes the new frontier
Advance ==
  /\ started /\ current # NoLeaf
  /\ (protected \/ Mutant = "release_frontier")
  /\ fixFreed' = (fixFreed \/ ~inUse[current])
  /\ frontier' = IF nxt[current] = NoLeaf THEN NoLeaf ELSE current
  /\ current' = nxt[current]
  /\ protected' = TRUE
  /\ UNCHANGED <<inUse, nxt, started>>

\* release mutant: the frontier's holder lets it go before its right leaf is fixed
Unprotect ==
  /\ Mutant = "release_frontier" /\ protected /\ frontier # NoLeaf
  /\ protected' = FALSE
  /\ UNCHANGED <<inUse, nxt, started, frontier, current, fixFreed>>

Split(l, n) ==
  /\ inUse[l] /\ ~inUse[n] /\ ~Locked(l)
  /\ inUse' = [inUse EXCEPT ![n] = TRUE]
  /\ nxt' = [nxt EXCEPT ![l] = n, ![n] = nxt[l]]
  /\ UNCHANGED <<started, frontier, current, protected, fixFreed>>

Merge(l) ==
  /\ inUse[l] /\ nxt[l] # NoLeaf /\ nxt[l] # l /\ ~Locked(l) /\ ~Locked(nxt[l])
  /\ inUse' = [inUse EXCEPT ![nxt[l]] = FALSE]
  /\ nxt' = [nxt EXCEPT ![l] = nxt[nxt[l]], ![nxt[l]] = NoLeaf]
  /\ UNCHANGED <<started, frontier, current, protected, fixFreed>>

\* release_leaf: the frontier's holder stops early and ends the chain
EndChain ==
  /\ frontier # NoLeaf
  /\ frontier' = NoLeaf /\ current' = NoLeaf
  /\ UNCHANGED <<inUse, nxt, started, protected, fixFreed>>

\* the scan is over and writers are idle: stutter
Done == started /\ current = NoLeaf /\ UNCHANGED fvars

FNext ==
  \/ Advance \/ Unprotect \/ EndChain \/ Done
  \/ \E f \in Leaves : Start(f)
  \/ \E l \in Leaves, n \in Leaves : Split(l, n)
  \/ \E l \in Leaves : Merge(l)

FSpec == Init /\ [][FNext]_fvars

FTypeOK == /\ inUse \in [Leaves -> BOOLEAN] /\ started \in BOOLEAN /\ protected \in BOOLEAN
           /\ fixFreed \in BOOLEAN
           /\ nxt \in [Leaves -> Leaves \cup {NoLeaf}]
           /\ frontier \in Leaves \cup {NoLeaf} /\ current \in Leaves \cup {NoLeaf}

\* C3: the dispatcher never fixes a freed leaf.
NoFreedFix == ~fixFreed

\* inductive invariant (no mutant)
FInv ==
  /\ FTypeOK
  /\ Mutant = "none"
  /\ ~fixFreed /\ protected
  /\ Chain /\ \E p \in Leaves : inUse[p]
  /\ ~started => frontier = NoLeaf /\ current = NoLeaf
  /\ frontier = NoLeaf => current = NoLeaf
  /\ frontier # NoLeaf => started /\ inUse[frontier] /\ current = nxt[frontier] /\ current # NoLeaf
=============================================================================
