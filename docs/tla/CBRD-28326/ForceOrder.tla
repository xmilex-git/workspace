----------------------------- MODULE ForceOrder -----------------------------
(* CBRD-28326: which statements must write their rows in key order although their scan could be a bitmap heap
   scan. One UPDATE over rows 1..N (key order 1..N, heap order N..1), no concurrent writer; the force phase writes
   the select's list in the list's order (query_executor.c qexec_execute_update, scan_targets loop).

   The statement's assignment is one of
   - "plain"      SET c = c + 1                 a row-local value (xasl_generation.c pt_reev_check_row_local)
   - "unique"     SET u = u + 1, u UNIQUE, the values overlap (u = N+1-r: row r moves onto row r-1's old value)
   - "numbering"  SET seq = ROWNUM               likewise INST_NUM, ORDERBY_NUM, serial NEXT_VALUE, @v := @v + 1
   HA: the server runs with HA. A MULTI_ROW_UPDATE then refuses every intermediate duplicate of a unique key
   (btree.c btree_key_insert_new_object -> ER_REPL_MULTI_UPDATE_UNIQUE_VIOLATION, -975); without HA the unique
   check of a multi-row update is made once, at the statement's end (btree.c is_unique_multi_update).

   Decided (round 2, the user 2026-11-24): an HA server writes a statement that assigns a unique-index column in key
   order (D1); an assignment that reads a numbering or a sequence keeps key order (D4); every other statement may
   use the heap order (D3, fixed data: the same value for every row).

   Mutant re-enables one wrong ordering:
   - heap_ha_unique  an HA server writes a unique-column UPDATE in heap order
   - heap_numbering  a numbering assignment is written in heap order *)
EXTENDS Naturals

CONSTANTS N, HA, Mutant

\* apalache-type: N Int
\* apalache-type: HA Bool
\* apalache-type: Mutant Str
\* apalache-type: kind Str
\* apalache-type: n Int
\* apalache-type: u Int -> Int
\* apalache-type: c Int -> Int
\* apalache-type: seq Int -> Int
\* apalache-type: failed Bool

Rows == 1..N
Kinds == {"plain", "unique", "numbering"}

ASSUME Assm == N \in Nat \ {0, 1} /\ HA \in BOOLEAN /\ Mutant \in {"none", "heap_ha_unique", "heap_numbering"}

CInit == N = 2 /\ HA \in BOOLEAN /\ Mutant = "none"

VARIABLES kind, n, u, c, seq, failed
vars == <<kind, n, u, c, seq, failed>>

\* the plan's write order: key order where the decisions require it, otherwise the bitmap heap step's
KeyOrder ==
  \/ (kind = "unique" /\ HA /\ Mutant /= "heap_ha_unique")
  \/ (kind = "numbering" /\ Mutant /= "heap_numbering")

ForceRow(i) == IF KeyOrder THEN i ELSE N + 1 - i

OldU(r) == N + 1 - r

Init ==
  /\ kind \in Kinds
  /\ n = 0
  /\ u = [r \in Rows |-> OldU(r)]
  /\ c = [r \in Rows |-> 0]
  /\ seq = [r \in Rows |-> 0]
  /\ failed = FALSE

(* one row of the force phase: locator_attribute_info_force -> heap_update and the index key changes *)
Force ==
  LET r == ForceRow(n + 1)
      dup == kind = "unique" /\ HA /\ \E o \in Rows : o /= r /\ u[o] = u[r] + 1
  IN
  /\ n < N /\ ~failed
  /\ IF dup
       THEN /\ failed' = TRUE
            /\ UNCHANGED <<n, u, c, seq>>
       ELSE /\ n' = n + 1
            /\ u' = IF kind = "unique" THEN [u EXCEPT ![r] = @ + 1] ELSE u
            /\ c' = IF kind = "plain" THEN [c EXCEPT ![r] = @ + 1] ELSE c
            /\ seq' = IF kind = "numbering" THEN [seq EXCEPT ![r] = n + 1] ELSE seq
            /\ UNCHANGED failed
  /\ UNCHANGED kind

Done == (failed \/ n = N) /\ UNCHANGED vars

Next == Force \/ Done

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
TypeOK ==
  /\ kind \in Kinds
  /\ n \in 0..N
  /\ u \in [Rows -> 1..(N + 1)]
  /\ c \in [Rows -> 0..1]
  /\ seq \in [Rows -> 0..N]
  /\ failed \in BOOLEAN

(* C4: on an HA server a unique-column UPDATE succeeds exactly when the key-order write succeeds (it does here) *)
SameSuccess == ~failed

(* C5: a numbering assignment gives every row the number the key order gives *)
NumberingSame == kind = "numbering" /\ n = N => \A r \in Rows : seq[r] = r

(* C6: a row-local assignment on fixed data gives every row the same value and writes every row *)
PlainSame == kind = "plain" /\ n = N => \A r \in Rows : c[r] = 1

\* witnesses: the heap order is taken where no decision forbids it
NotHeapPlain == ~(kind = "plain" /\ n = N /\ ~KeyOrder)
NotHeapUniqueNoHa == ~(kind = "unique" /\ ~HA /\ n = N /\ ~KeyOrder)

-----------------------------------------------------------------------------
Written(r) == \E i \in 1..N : i <= n /\ ForceRow(i) = r

Pos(r) == IF KeyOrder THEN r ELSE N + 1 - r

WrittenShape ==
  /\ \A r \in Rows : u[r] = IF kind = "unique" /\ Written(r) THEN OldU(r) + 1 ELSE OldU(r)
  /\ \A r \in Rows : c[r] = IF kind = "plain" /\ Written(r) THEN 1 ELSE 0
  /\ \A r \in Rows : seq[r] = IF kind = "numbering" /\ Written(r) THEN Pos(r) ELSE 0

IndInv ==
  /\ TypeOK
  /\ WrittenShape
  /\ SameSuccess
  /\ NumberingSame
  /\ PlainSame
=============================================================================
