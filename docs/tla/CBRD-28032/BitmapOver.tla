--------------------------- MODULE BitmapOver ---------------------------
(***************************************************************************)
(* The overflow lists of a parallel bitmap heap scan: who touches a list's *)
(* header, and when (scan_bitmap_worker::over).                            *)
(*                                                                         *)
(* A worker records the rows whose slot is beyond an entry's width in a    *)
(* list of its own.  When its index step ends it closes the list           *)
(* (end_marks) and leaves the step.  Once every worker left, one worker    *)
(* wins take_over: it appends the other lists to the first one, sorts it   *)
(* (the sort writes a new header over the list's) and reads it.  A worker  *)
(* that ends closes its list only when end_marks did not (it stopped       *)
(* inside its index step).                                                 *)
(*                                                                         *)
(* A worker that fails raises the query's interrupt and never leaves the   *)
(* index step, so no worker passes the wait after a failure.               *)
(*                                                                         *)
(* The claims (C4, C7): a list is closed once; from the moment a worker    *)
(* merges, no other worker touches a list it works on; the merged list     *)
(* holds every list that has rows; a stopped worker's list is closed too.  *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS NW,          \* workers
          MaxFaults,   \* failures (an error or an interrupt) in one run
          Mutant       \* "none" | "close_twice" | "no_end_close" | "no_stop_close" | "skip_list"

W == 1..NW

VARIABLES ph,       \* a worker's step
          has,      \* the worker opened an overflow list (it has rows)
          closed,   \* scan_bitmap_worker::over_closed
          nclose,   \* ghost: times the worker's list was closed
          busy,     \* ghost: the worker inside an append or a sort of the list (0: none)
          taken,    \* m_bm_over_taken
          pending,  \* m_bm_index_pending
          intr,     \* the query's interrupt
          base,     \* the list the others are appended to (0: none)
          cur,      \* the list being appended (0: none)
          app,      \* lists appended
          merged,   \* ghost: lists the sorted list holds
          faults, clash

vars == <<ph, has, closed, nclose, busy, taken, pending, intr, base, cur, app, merged, faults, clash>>

Init ==
  /\ ph = [w \in W |-> "index"] /\ has \in [W -> BOOLEAN]
  /\ closed = [w \in W |-> FALSE] /\ nclose = [w \in W |-> 0] /\ busy = [w \in W |-> 0]
  /\ taken = FALSE /\ pending = NW /\ intr = FALSE /\ base = 0 /\ cur = 0 /\ app = {} /\ merged = {}
  /\ faults = 0 /\ clash = FALSE

\* scan_bitmap_marks::end_marks: the list's last page is fixed by its worker, which closes it
EndMarks(w) ==
  /\ ph[w] = "index" /\ ~intr
  /\ IF has[w] /\ Mutant /= "no_end_close"
       THEN /\ nclose' = [nclose EXCEPT ![w] = @ + 1]
            /\ closed' = [closed EXCEPT ![w] = Mutant /= "close_twice"]
       ELSE UNCHANGED <<nclose, closed>>
  /\ ph' = [ph EXCEPT ![w] = "ended"]
  /\ UNCHANGED <<has, busy, taken, pending, intr, base, cur, app, merged, faults, clash>>

\* input_handler_index::bitmap_leave_index_step
Leave(w) ==
  /\ ph[w] = "ended" /\ pending' = pending - 1 /\ ph' = [ph EXCEPT ![w] = "wait"]
  /\ UNCHANGED <<has, closed, nclose, busy, taken, intr, base, cur, app, merged, faults, clash>>

\* input_handler_index::bitmap_wait_index_step
Pass(w) ==
  /\ ph[w] = "wait" /\ (pending = 0 \/ intr)
  /\ ph' = [ph EXCEPT ![w] = IF intr THEN "close" ELSE "heap"]
  /\ UNCHANGED <<has, closed, nclose, busy, taken, pending, intr, base, cur, app, merged, faults, clash>>

Lists == {l \in W : has[l]}
First(S) == CHOOSE l \in S : \A m \in S : l <= m

\* the worker read its partitions; scan_bitmap_marks::take_over, the compare-and-swap and the choice of the base
Take(w) ==
  /\ ph[w] = "heap" /\ ~intr
  /\ IF taken THEN /\ ph' = [ph EXCEPT ![w] = "close"] /\ UNCHANGED <<taken, base>>
     ELSE /\ taken' = TRUE
          /\ IF Lists = {} THEN /\ ph' = [ph EXCEPT ![w] = "close"] /\ UNCHANGED base
             ELSE /\ base' = First(Lists) /\ ph' = [ph EXCEPT ![w] = "append"]
  /\ UNCHANGED <<has, closed, nclose, busy, pending, intr, cur, app, merged, faults, clash>>

\* a worker in its heap step sees the interrupt
StopHeap(w) ==
  /\ ph[w] = "heap" /\ intr /\ ph' = [ph EXCEPT ![w] = "close"]
  /\ UNCHANGED <<has, closed, nclose, busy, taken, pending, intr, base, cur, app, merged, faults, clash>>

Rest == (Lists \ {base}) \ app

\* qfile_append_list (base, list): both headers are read, the base's is written
AppendBegin(w) ==
  /\ ph[w] = "append" /\ Rest /= {} /\ Mutant /= "skip_list"
  /\ cur' = First(Rest) /\ busy' = [busy EXCEPT ![base] = w, ![First(Rest)] = w]
  /\ ph' = [ph EXCEPT ![w] = "appending"]
  /\ UNCHANGED <<has, closed, nclose, taken, pending, intr, base, app, merged, faults, clash>>

AppendEnd(w) ==
  /\ ph[w] = "appending"
  /\ app' = app \cup {cur} /\ busy' = [busy EXCEPT ![base] = 0, ![cur] = 0] /\ cur' = 0
  /\ ph' = [ph EXCEPT ![w] = "append"]
  /\ UNCHANGED <<has, closed, nclose, taken, pending, intr, base, merged, faults, clash>>

\* qfile_sort_list (base): the list's header is cleared and the sorted list's header copied over it
SortBegin(w) ==
  /\ ph[w] = "append" /\ (Rest = {} \/ Mutant = "skip_list")
  /\ busy' = [busy EXCEPT ![base] = w] /\ ph' = [ph EXCEPT ![w] = "sorting"]
  /\ UNCHANGED <<has, closed, nclose, taken, pending, intr, base, cur, app, merged, faults, clash>>

\* ... and qfile_open_list_scan: the worker reads the list's rows from here
SortEnd(w) ==
  /\ ph[w] = "sorting"
  /\ busy' = [busy EXCEPT ![base] = 0] /\ merged' = app \cup {base}
  /\ ph' = [ph EXCEPT ![w] = "scan"]
  /\ UNCHANGED <<has, closed, nclose, taken, pending, intr, base, cur, app, faults, clash>>

ScanEnd(w) ==
  /\ ph[w] = "scan" /\ ph' = [ph EXCEPT ![w] = "close"]
  /\ UNCHANGED <<has, closed, nclose, busy, taken, pending, intr, base, cur, app, merged, faults, clash>>

\* an error or an interrupt: the worker raises the query's interrupt and ends; in its index step it neither
\* closes its list in end_marks nor leaves the step
Fail(w) ==
  /\ ph[w] \in {"index", "heap", "append", "appending", "sorting", "scan"} /\ faults < MaxFaults
  /\ faults' = faults + 1 /\ intr' = TRUE
  /\ busy' = [l \in W |-> IF busy[l] = w THEN 0 ELSE busy[l]] /\ cur' = IF ph[w] = "appending" THEN 0 ELSE cur
  /\ ph' = [ph EXCEPT ![w] = "close"]
  /\ UNCHANGED <<has, closed, nclose, taken, pending, base, app, merged, clash>>

\* a worker that saw the interrupt in its index step ends the same way
StopIndex(w) ==
  /\ ph[w] \in {"index", "ended"} /\ intr /\ ph' = [ph EXCEPT ![w] = "close"]
  /\ UNCHANGED <<has, closed, nclose, busy, taken, pending, intr, base, cur, app, merged, faults, clash>>

\* scan_bitmap_marks::close_worker
Close(w) ==
  /\ ph[w] = "close"
  /\ IF has[w] /\ ~closed[w] /\ Mutant /= "no_stop_close"
       THEN /\ nclose' = [nclose EXCEPT ![w] = @ + 1]
            /\ clash' = (clash \/ busy[w] \notin {0, w})
       ELSE UNCHANGED <<nclose, clash>>
  /\ ph' = [ph EXCEPT ![w] = "done"]
  /\ UNCHANGED <<has, closed, busy, taken, pending, intr, base, cur, app, merged, faults>>

Finished == (\A w \in W : ph[w] = "done") /\ UNCHANGED vars

Next ==
  \/ \E w \in W : EndMarks(w) \/ Leave(w) \/ Pass(w) \/ Take(w) \/ StopHeap(w) \/ AppendBegin(w) \/ AppendEnd(w)
                  \/ SortBegin(w) \/ SortEnd(w) \/ ScanEnd(w) \/ Fail(w) \/ StopIndex(w) \/ Close(w)
  \/ Finished
Spec == Init /\ [][Next]_vars

Steps == {"index", "ended", "wait", "heap", "append", "appending", "sorting", "scan", "close", "done"}
Merging(w) == ph[w] \in {"append", "appending", "sorting", "scan"}

TypeOK ==
  /\ ph \in [W -> Steps] /\ has \in [W -> BOOLEAN] /\ closed \in [W -> BOOLEAN]
  /\ nclose \in [W -> 0..2] /\ busy \in [W -> 0..NW]
  /\ taken \in BOOLEAN /\ pending \in 0..NW /\ intr \in BOOLEAN
  /\ base \in 0..NW /\ cur \in 0..NW /\ app \subseteq W /\ merged \subseteq W
  /\ faults \in 0..MaxFaults /\ clash \in BOOLEAN

\* a list is closed once
CloseOnce == \A l \in W : nclose[l] <= 1
\* no worker closes a list another worker appends or sorts
NoClash == ~clash
\* one worker merges
OneMerger == Cardinality({w \in W : Merging(w)}) <= 1
\* the lists a worker merges were closed by their workers: no page of them is fixed by another thread
Handed == \A w \in W : Merging(w) => \A l \in Lists : nclose[l] = 1
\* the sorted list holds every list that has rows
AllMerged == \A w \in W : ph[w] = "scan" => merged = Lists
\* at the end every list was closed, a stopped worker's too
AllClosed == (\A w \in W : ph[w] = "done") => \A l \in Lists : nclose[l] = 1

\* witnesses
\* a worker ended (its list is the base) while another worker sorts that list
NotEndedDuringSort == ~(\E m \in W : ph[m] = "sorting" /\ base /= m /\ ph[base] = "done")
\* a worker that stopped inside its index step closed its list as it ended
NotStoppedClosed == ~(\E w \in W : ph[w] = "done" /\ has[w] /\ ~closed[w] /\ nclose[w] = 1)
\* a run that merged two lists and ended
NotMergedTwo == ~((\A w \in W : ph[w] = "done") /\ Cardinality(merged) >= 2)
=============================================================================
