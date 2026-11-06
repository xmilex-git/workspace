------------------------------ MODULE DescScan ------------------------------
(* The design CBRD-27848 settles, as the abstract spec DescTree must refine.
   A descending index range scan reads key values from its start downward.  W are the keys the scan must return
   (visible to its snapshot, in range, passing the key filter): every one of them stays in the index for the
   whole scan.  Every key above Top is out of range; a key another transaction inserted there after the scan's
   snapshot can still land below the scan's position.  g is the value of the next record to read (0: none left).
   Other transactions may insert or vacuum keys outside W and split or merge leaves; to the scan that only moves
   the next record to read across values that hold no key of W (Shift).
   Repositioning: a scan that lost its place locates the last key it read again and continues below it
   (btree_range_scan_resume, and fix_prev_leaf's normal path); a scan that has returned nothing yet restarts from
   the root (btree_range_scan_start), which is what the special case does after CBRD-27848. *)
EXTENDS Naturals, FiniteSets

CONSTANTS N, W, Top

ASSUME Assm == /\ N \in Nat
               /\ Top \in 0..N
               /\ W \subseteq 1..Top

VARIABLES pc, g, emitted, hasCur, cpos
vars == <<pc, g, emitted, hasCur, cpos>>

\* no key of W lies strictly between a and b
NoWBetween(a, b) == \A i \in W : ~(a < i /\ i < b)

TypeOK ==
  /\ pc \in {"start", "scan", "done"}
  /\ g \in 0..N
  /\ emitted \in SUBSET (1..N)
  /\ hasCur \in BOOLEAN
  /\ cpos \in 0..N

Init == pc = "start" /\ g = 0 /\ emitted = {} /\ hasCur = FALSE /\ cpos = 0

\* the start stands below every key of W above it
Start ==
  /\ pc = "start"
  /\ \E x \in 0..Top : NoWBetween(x, Top + 1) /\ g' = x
  /\ pc' = "scan"
  /\ UNCHANGED <<emitted, hasCur, cpos>>

\* read the record g: it becomes the current key, and is returned when in W; the next record lies below it
Read ==
  /\ pc = "scan" /\ g >= 1
  /\ \E x \in 0..(g - 1) : NoWBetween(x, g) /\ g' = x
  /\ emitted' = IF g \in W THEN emitted \cup {g} ELSE emitted
  /\ hasCur' = TRUE
  /\ cpos' = g
  /\ UNCHANGED pc

End ==
  /\ pc = "scan" /\ g = 0
  /\ pc' = "done"
  /\ UNCHANGED <<g, emitted, hasCur, cpos>>

\* locate the current key again and continue below it
Reposition ==
  /\ pc = "scan" /\ hasCur
  /\ \E x \in 0..(cpos - 1) : NoWBetween(x, cpos) /\ g' = x
  /\ UNCHANGED <<pc, emitted, hasCur, cpos>>

\* another transaction changes the records around the next one to read, never a key of W
Shift ==
  /\ pc = "scan"
  /\ \E x \in 0..N :
       /\ NoWBetween(x, g + 1) /\ NoWBetween(g, x + 1)
       /\ (hasCur => x < cpos)
       /\ g' = x
  /\ UNCHANGED <<pc, emitted, hasCur, cpos>>

\* nothing returned yet: restart from the root
RestartBeforeFirstKey ==
  /\ pc = "scan" /\ emitted = {}
  /\ pc' = "start" /\ hasCur' = FALSE /\ g' = 0
  /\ UNCHANGED <<emitted, cpos>>

Terminated == pc = "done" /\ UNCHANGED vars

Next == Start \/ Read \/ End \/ Reposition \/ Shift \/ RestartBeforeFirstKey \/ Terminated

Spec == Init /\ [][Next]_vars

---------------------------------------------------------------------------
\* C1: what is returned is exactly W, each key returned below every key returned before it
Complete == pc = "done" => emitted = W
Descending == [][Read /\ g \in W => \A i \in emitted : g < i]_vars

R_start == pc = "start" => emitted = {} /\ ~hasCur
R_scan == pc = "scan" => emitted = {i \in W : g < i}
R_done == pc = "done" => emitted = W
R_cur == (pc = "scan" /\ hasCur) => g < cpos /\ NoWBetween(g, cpos)

IndInv == TypeOK /\ R_start /\ R_scan /\ R_done /\ R_cur

\* witness
NotReturnedAll == ~(pc = "done" /\ emitted # {})
=============================================================================
