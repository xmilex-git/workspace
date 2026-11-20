--------------------------- MODULE BitmapRefix ---------------------------
(***************************************************************************)
(* One heap page of the heap step of a parallel bitmap heap scan, read     *)
(* slot by slot (slot_iterator_index::next_bitmap_row).                    *)
(*                                                                         *)
(* The page is fixed, and each marked slot is read in slot order.  A row   *)
(* the snapshot sees is handed to the block above.  When the scan copies   *)
(* its rows (bitmap_keep_page is false) the page is let go with the row    *)
(* and fixed again for the next slot; when the block above reads the row   *)
(* in place, the page stays fixed until its last slot.  The page is let go *)
(* at its last slot, on an error, and when the scan is closed.             *)
(*                                                                         *)
(* The claims (C4, C1): no page is fixed while the block above works on a  *)
(* copied row; a row read in place stays on a fixed page; a slot is read   *)
(* on a fixed page only; nothing stays fixed when the page is finished;    *)
(* every marked row the snapshot sees is returned once.                    *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS NS,          \* slots of the page
          Keep,        \* INDX_SCAN_ID::bitmap_keep_page
          MaxFaults,
          Mutant       \* "none" | "no_unfix" | "unfix_peek" | "no_refix" | "end_holds" | "stop_holds"

S == 1..NS

VARIABLES marked,   \* slots the index step marked
          vis,      \* slots whose row the snapshot sees and the filter passes
          st,       \* "start" | "row" (looking for the next slot) | "with" (the block above works on a row) | "end" | "err" | "stopped"
          next,     \* m_bm_next_slot
          fixed,    \* the page is fixed by this worker
          pageOn,   \* m_bm_page_on
          unfixed,  \* m_bm_unfixed
          gone,     \* the page was deallocated
          out, badRead, faults

vars == <<marked, vis, st, next, fixed, pageOn, unfixed, gone, out, badRead, faults>>

Init ==
  /\ marked \in SUBSET S /\ vis \in SUBSET S
  /\ st = "start" /\ next = 1 /\ fixed = FALSE /\ pageOn = FALSE /\ unfixed = FALSE /\ gone = FALSE
  /\ out = {} /\ badRead = FALSE /\ faults = 0

\* vacuum deallocates a page no transaction sees a row of, while nobody has it fixed
Dealloc ==
  /\ ~fixed /\ ~gone /\ vis = {} /\ st \in {"start", "row", "with"}
  /\ gone' = TRUE
  /\ UNCHANGED <<marked, vis, st, next, fixed, pageOn, unfixed, out, badRead, faults>>

\* slot_iterator_index::read_page: leaf_slot_walker::fix_bitmap_page
Start ==
  /\ st = "start"
  /\ IF gone THEN /\ st' = "end" /\ UNCHANGED <<fixed, pageOn>>
     ELSE /\ st' = "row" /\ fixed' = TRUE /\ pageOn' = TRUE
  /\ UNCHANGED <<marked, vis, next, unfixed, gone, out, badRead, faults>>

StartFail ==
  /\ st = "start" /\ faults < MaxFaults
  /\ faults' = faults + 1 /\ st' = "err"
  /\ UNCHANGED <<marked, vis, next, fixed, pageOn, unfixed, gone, out, badRead>>

Rem == {s \in marked : s >= next}
Min(T) == CHOOSE s \in T : \A t \in T : s <= t

\* no slot is left: the page is let go
EndPage ==
  /\ st = "row" /\ Rem = {}
  /\ fixed' = (fixed /\ Mutant = "end_holds") /\ pageOn' = FALSE /\ st' = "end"
  /\ UNCHANGED <<marked, vis, next, unfixed, gone, out, badRead, faults>>

Refixes == unfixed /\ Mutant /= "no_refix"

\* the page let go with the last row cannot be fixed again
RefixFail ==
  /\ st = "row" /\ Rem /= {} /\ Refixes /\ faults < MaxFaults
  /\ faults' = faults + 1 /\ pageOn' = FALSE /\ st' = "err"
  /\ UNCHANGED <<marked, vis, next, fixed, unfixed, gone, out, badRead>>

\* ... or it was deallocated meanwhile
RefixGone ==
  /\ st = "row" /\ Rem /= {} /\ Refixes /\ gone
  /\ pageOn' = FALSE /\ st' = "end"
  /\ UNCHANGED <<marked, vis, next, fixed, unfixed, out, gone, badRead, faults>>

\* the next marked slot: the page is fixed again when it was let go, and the row is read
Row ==
  /\ st = "row" /\ Rem /= {} /\ ~(Refixes /\ gone)
  /\ LET s == Min(Rem)
         fx == Refixes \/ fixed
         letgo == IF Keep THEN Mutant = "unfix_peek" ELSE Mutant /= "no_unfix"
     IN /\ next' = s + 1 /\ badRead' = (badRead \/ ~fx)
        /\ IF s \in vis
             THEN /\ out' = out \cup {s} /\ st' = "with"
                  /\ fixed' = (fx /\ ~letgo) /\ unfixed' = (letgo \/ (unfixed /\ ~Refixes))
             ELSE /\ fixed' = fx /\ unfixed' = (unfixed /\ ~Refixes) /\ UNCHANGED <<out, st>>
  /\ UNCHANGED <<marked, vis, pageOn, gone, faults>>

\* reading the row fails: the page is let go
RowFail ==
  /\ st = "row" /\ Rem /= {} /\ ~unfixed /\ faults < MaxFaults
  /\ faults' = faults + 1 /\ fixed' = FALSE /\ pageOn' = FALSE /\ st' = "err"
  /\ UNCHANGED <<marked, vis, next, unfixed, gone, out, badRead>>

\* the block above is done with the row and asks for the next
Consumed ==
  /\ st = "with" /\ st' = "row"
  /\ UNCHANGED <<marked, vis, next, fixed, pageOn, unfixed, gone, out, badRead, faults>>

\* the scan is closed with rows left (a LIMIT, an error above, an interrupt)
Stop ==
  /\ st \in {"row", "with"}
  /\ fixed' = (fixed /\ Mutant = "stop_holds") /\ pageOn' = FALSE /\ st' = "stopped"
  /\ UNCHANGED <<marked, vis, next, unfixed, gone, out, badRead, faults>>

Finished == st \in {"end", "err", "stopped"} /\ UNCHANGED vars

Next == Dealloc \/ Start \/ StartFail \/ EndPage \/ RefixFail \/ RefixGone \/ Row \/ RowFail \/ Consumed \/ Stop
        \/ Finished
Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ marked \subseteq S /\ vis \subseteq S /\ out \subseteq S
  /\ st \in {"start", "row", "with", "end", "err", "stopped"} /\ next \in 1..(NS + 1)
  /\ fixed \in BOOLEAN /\ pageOn \in BOOLEAN /\ unfixed \in BOOLEAN /\ gone \in BOOLEAN
  /\ badRead \in BOOLEAN /\ faults \in 0..MaxFaults

\* no page is fixed while the block above works on a copied row
CopyNotHeld == (st = "with" /\ ~Keep) => ~fixed
\* a row read in place is on a fixed page
PeekHeld == (st = "with" /\ Keep) => fixed
\* a slot is read on a fixed page
ReadFixed == ~badRead
\* nothing stays fixed when the page is finished, failed or closed
NoPageHeld == st \in {"end", "err", "stopped"} => ~fixed
\* the flags say what is fixed
Flags == /\ fixed => (pageOn /\ ~unfixed)
         /\ unfixed => (pageOn \/ st \in {"end", "err", "stopped"})
\* every marked row the snapshot sees is returned
NoExtra == out \subseteq (marked \cap vis)
AllReturned == (st = "end" /\ ~gone) => out = marked \cap vis

\* witnesses
\* the page was let go with a row and fixed again for a later row
NotRefixed == ~(st = "with" /\ Cardinality(out) >= 2)
\* a page deallocated before it is read ends at once
NotGoneEnd == ~(st = "end" /\ gone)
\* the scan is closed while the block above holds a row
NotStoppedWithRow == ~(st = "stopped" /\ out /= {} /\ next <= NS)
=============================================================================
