--------------------------- MODULE BitmapShare ---------------------------
(***************************************************************************)
(* How the workers of the heap step of a parallel bitmap heap scan share   *)
(* the pages of the partitions (scan_bitmap_marks::take_partitions, load,  *)
(* take_chunk; the heap step of task::execute in px_scan_task.cpp).        *)
(*                                                                         *)
(* A worker takes a run of partitions: the partitions that follow each     *)
(* other while their marked pages fit one table.  It loads their pages     *)
(* into its own table and puts them on offer.  It takes them a chunk at a time, and *)
(* so does every worker that found no partition left: the pages of a key   *)
(* range that lie in one partition are read by all workers.  A chunk is    *)
(* copied under the table's mutex, and nothing is on offer while the table *)
(* is loaded again.  A worker that finds nothing on offer leaves when no   *)
(* worker may load a partition any more.                                   *)
(*                                                                         *)
(* The claims (C15, C6): every marked page is read by one worker, once;    *)
(* no chunk is copied from a table being loaded; a table never gets more   *)
(* pages than it holds; every worker ends.                                 *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS NW,       \* workers
          NP,       \* partitions
          PP,       \* marked pages of a partition that got a mark
          K,        \* pages of a chunk
          CAP,      \* pages a table holds; PP <= CAP
          Mutant    \* "none" | "no_unshare" | "no_lock" | "share_early" | "early_leave" | "no_cap" | "no_cas"

W == 1..NW
P == 1..NP
Pages(m) == {<<p, i>> : p \in m, i \in 1..PP}

VARIABLES marksIn,  \* the partitions that got a mark
          nextPart, \* m_bm_next_part
          loaders,  \* m_bm_loaders
          ph,       \* a worker: "enter" | "take" | "cas" | "unshare" | "load" | "share" | "own" | "leave" | "help" | "check" | "done"
          first,    \* m_bm_next_part as it read it
          part,     \* the run it took: from this partition
          pend,     \* ... to the one before this
          tbl,      \* the marked partitions whose pages its table holds
          loading,  \* its table is being loaded
          shN,      \* share_n
          shNext,   \* share_next
          hi,       \* helping: the worker whose table it asks next
          any,      \* ... it got a chunk in this pass
          seen,     \* mutant no_lock: share_next as read before it is written; 0: nothing read
          reads,    \* how often each page was read
          helped,   \* a page was read by a worker that did not load it
          badCopy   \* a chunk was copied from a table being loaded

vars == <<marksIn, nextPart, loaders, ph, first, part, pend, tbl, loading, shN, shNext, hi, any, seen, reads, helped, badCopy>>

Init ==
  /\ marksIn \in SUBSET P
  /\ nextPart = 1 /\ loaders = 0
  /\ ph = [w \in W |-> "enter"] /\ first = [w \in W |-> 1] /\ part = [w \in W |-> 1] /\ pend = [w \in W |-> 1]
  /\ tbl = [w \in W |-> {}]
  /\ loading = [w \in W |-> FALSE] /\ shN = [w \in W |-> 0] /\ shNext = [w \in W |-> 0]
  /\ hi = [w \in W |-> 1] /\ any = [w \in W |-> FALSE] /\ seen = [w \in W |-> 0]
  /\ reads = [g \in Pages(marksIn) |-> 0] /\ helped = FALSE /\ badCopy = FALSE

\* scan_bitmap_marks::enter_partitions
Enter(w) ==
  /\ ph[w] = "enter"
  /\ loaders' = loaders + 1 /\ ph' = [ph EXCEPT ![w] = "take"]
  /\ UNCHANGED <<marksIn, nextPart, first, part, pend, tbl, loading, shN, shNext, hi, any, seen, reads, helped, badCopy>>

\* the marked pages of the partitions from f to the one before l
Weight(f, l) == PP * Cardinality({p \in f..(l - 1) : p \in marksIn})

\* scan_bitmap_marks::take_partitions, the loop over m_bm_part_pages: partitions without a mark add nothing
RunEnd(f) ==
  IF Mutant = "no_cap" THEN NP + 1
  ELSE CHOOSE l \in f..(NP + 1) : Weight(f, l) <= CAP /\ (l = NP + 1 \/ Weight(f, l + 1) > CAP)

\* ... m_bm_next_part is read
Take(w) ==
  /\ ph[w] = "take"
  /\ first' = [first EXCEPT ![w] = nextPart] /\ ph' = [ph EXCEPT ![w] = "cas"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, part, pend, tbl, loading, shN, shNext, hi, any, seen, reads, helped, badCopy>>

\* ... compare_exchange: the run is this worker's when nobody moved the counter; a run without a mark is the end
Cas(w) ==
  /\ ph[w] = "cas"
  /\ IF nextPart = first[w] \/ Mutant = "no_cas"
       THEN /\ nextPart' = RunEnd(first[w])
            /\ part' = [part EXCEPT ![w] = first[w]] /\ pend' = [pend EXCEPT ![w] = RunEnd(first[w])]
            /\ ph' = [ph EXCEPT ![w] = IF Weight(first[w], RunEnd(first[w])) > 0 THEN "unshare" ELSE "leave"]
       ELSE ph' = [ph EXCEPT ![w] = "take"] /\ UNCHANGED <<nextPart, part, pend>>
  /\ UNCHANGED <<marksIn, loaders, first, tbl, loading, shN, shNext, hi, any, seen, reads, helped, badCopy>>

RunMarks(w) == {p \in part[w]..(pend[w] - 1) : p \in marksIn}

\* scan_bitmap_marks::load, under the table's mutex: nothing is on offer
Unshare(w) ==
  /\ ph[w] = "unshare"
  /\ IF Mutant = "no_unshare" THEN UNCHANGED <<shN, shNext>>
     ELSE shN' = [shN EXCEPT ![w] = IF Mutant = "share_early" THEN PP * Cardinality(RunMarks(w)) ELSE 0] /\ shNext' = [shNext EXCEPT ![w] = 0]
  /\ loading' = [loading EXCEPT ![w] = TRUE] /\ tbl' = [tbl EXCEPT ![w] = {}]
  /\ ph' = [ph EXCEPT ![w] = "load"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, first, part, pend, hi, any, seen, reads, helped, badCopy>>

\* ... the table is cleared, filled from every worker's entries and records, and sorted, outside the mutex
Load(w) ==
  /\ ph[w] = "load"
  /\ tbl' = [tbl EXCEPT ![w] = RunMarks(w)] /\ loading' = [loading EXCEPT ![w] = FALSE]
  /\ ph' = [ph EXCEPT ![w] = "share"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, first, part, pend, shN, shNext, hi, any, seen, reads, helped, badCopy>>

\* ... under the mutex: its pages are on offer
Share(w) ==
  /\ ph[w] = "share"
  /\ shN' = [shN EXCEPT ![w] = PP * Cardinality(tbl[w])]
  /\ ph' = [ph EXCEPT ![w] = "own"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, first, part, pend, tbl, loading, shNext, hi, any, seen, reads, helped, badCopy>>

Min(a, b) == IF a < b THEN a ELSE b

\* the pages of a table in file order: the j-th is a page of its ((j - 1) \div PP + 1)-th partition
Slots(from) == 1..(PP * Cardinality(tbl[from]))
PageAt(from, j) ==
  <<CHOOSE p \in tbl[from] : Cardinality({q \in tbl[from] : q < p}) = (j - 1) \div PP, ((j - 1) % PP) + 1>>

\* the pages of the chunk that starts at `at` in the table of `from`
Chunk(from, at) == {PageAt(from, j) : j \in ((at + 1)..Min(at + K, shN[from])) \cap Slots(from)}

\* scan_bitmap_marks::take_chunk, under the mutex of the table of `from`: the chunk is copied and share_next moves
Copy(w, from, at) ==
  /\ badCopy' = (badCopy \/ loading[from] \/ tbl[from] = {})
  /\ reads' = [g \in DOMAIN reads |-> IF g \in Chunk(from, at) THEN reads[g] + 1 ELSE reads[g]]
  /\ helped' = (helped \/ (w /= from /\ Chunk(from, at) /= {}))
  /\ shNext' = [shNext EXCEPT ![from] = Min(at + K, shN[from])]

Offered(from) == shNext[from] < shN[from]

\* a worker reads the pages of its own table
OwnChunk(w) ==
  /\ ph[w] = "own" /\ Offered(w) /\ (Mutant /= "no_lock" \/ seen[w] = 0)
  /\ IF Mutant = "no_lock"
       THEN seen' = [seen EXCEPT ![w] = shNext[w] + 1] /\ UNCHANGED <<reads, helped, badCopy, shNext>>
       ELSE Copy(w, w, shNext[w]) /\ UNCHANGED seen
  /\ UNCHANGED <<marksIn, nextPart, loaders, ph, first, part, pend, tbl, loading, shN, hi, any>>

\* mutant no_lock: the copy with the place read before
LateCopy(w, from) ==
  /\ Mutant = "no_lock" /\ seen[w] /= 0
  /\ (ph[w] = "own" /\ from = w) \/ (ph[w] = "help" /\ from = hi[w])
  /\ Copy(w, from, seen[w] - 1) /\ seen' = [seen EXCEPT ![w] = 0]
  /\ any' = [any EXCEPT ![w] = any[w] \/ ph[w] = "help"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, ph, first, part, pend, tbl, loading, shN, hi>>

\* ... none is left: the next partition
OwnDone(w) ==
  /\ ph[w] = "own" /\ seen[w] = 0 /\ (~Offered(w) \/ Mutant = "early_leave")
  /\ ph' = [ph EXCEPT ![w] = "take"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, first, part, pend, tbl, loading, shN, shNext, hi, any, seen, reads, helped, badCopy>>

\* scan_bitmap_marks::leave_partitions
Leave(w) ==
  /\ ph[w] = "leave"
  /\ loaders' = loaders - 1 /\ ph' = [ph EXCEPT ![w] = "help"]
  /\ hi' = [hi EXCEPT ![w] = 1] /\ any' = [any EXCEPT ![w] = FALSE]
  /\ UNCHANGED <<marksIn, nextPart, first, part, pend, tbl, loading, shN, shNext, seen, reads, helped, badCopy>>

\* a worker without a partition takes a chunk of the table it asks
HelpChunk(w) ==
  /\ ph[w] = "help" /\ hi[w] <= NW /\ Offered(hi[w]) /\ (Mutant /= "no_lock" \/ seen[w] = 0)
  /\ IF Mutant = "no_lock"
       THEN seen' = [seen EXCEPT ![w] = shNext[hi[w]] + 1] /\ UNCHANGED <<reads, helped, badCopy, shNext, any>>
       ELSE Copy(w, hi[w], shNext[hi[w]]) /\ any' = [any EXCEPT ![w] = TRUE] /\ UNCHANGED seen
  /\ UNCHANGED <<marksIn, nextPart, loaders, ph, first, part, pend, tbl, loading, shN, hi>>

\* ... nothing on offer there: the next table
HelpNext(w) ==
  /\ ph[w] = "help" /\ hi[w] <= NW /\ ~Offered(hi[w]) /\ seen[w] = 0
  /\ hi' = [hi EXCEPT ![w] = hi[w] + 1]
  /\ UNCHANGED <<marksIn, nextPart, loaders, ph, first, part, pend, tbl, loading, shN, shNext, any, seen, reads, helped, badCopy>>

\* ... every table was asked: again when a chunk was got
HelpPass(w) ==
  /\ ph[w] = "help" /\ hi[w] > NW
  /\ ph' = [ph EXCEPT ![w] = IF any[w] THEN "help" ELSE "check"]
  /\ hi' = [hi EXCEPT ![w] = 1] /\ any' = [any EXCEPT ![w] = FALSE]
  /\ UNCHANGED <<marksIn, nextPart, loaders, first, part, pend, tbl, loading, shN, shNext, seen, reads, helped, badCopy>>

\* scan_bitmap_marks::loaders_left: nothing was on offer; it ends when no worker may put pages on offer
Check(w) ==
  /\ ph[w] = "check"
  /\ ph' = [ph EXCEPT ![w] = IF loaders > 0 THEN "help" ELSE "done"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, first, part, pend, tbl, loading, shN, shNext, hi, any, seen, reads, helped, badCopy>>

AllDone == \A w \in W : ph[w] = "done"

Finished == AllDone /\ UNCHANGED vars

Next ==
  \/ \E w \in W : \/ Enter(w) \/ Take(w) \/ Cas(w) \/ Unshare(w) \/ Load(w) \/ Share(w) \/ OwnChunk(w) \/ OwnDone(w)
                  \/ Leave(w) \/ HelpChunk(w) \/ HelpNext(w) \/ HelpPass(w) \/ Check(w)
                  \/ \E from \in W : LateCopy(w, from)
  \/ Finished

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ marksIn \subseteq P /\ nextPart \in 1..(NP + 1) /\ loaders \in 0..NW
  /\ ph \in [W -> {"enter", "take", "cas", "unshare", "load", "share", "own", "leave", "help", "check", "done"}]
  /\ first \in [W -> 1..(NP + 1)] /\ part \in [W -> 1..(NP + 1)] /\ pend \in [W -> 1..(NP + 1)]
  /\ tbl \in [W -> SUBSET P] /\ loading \in [W -> BOOLEAN]
  /\ shN \in [W -> 0..(NP * PP)] /\ shNext \in [W -> 0..(NP * PP)]
  /\ hi \in [W -> 1..(NW + 1)] /\ any \in [W -> BOOLEAN] /\ seen \in [W -> 0..(NP * PP + 1)]
  /\ reads \in [Pages(marksIn) -> 0..(NW + 1)] /\ helped \in BOOLEAN /\ badCopy \in BOOLEAN

\* C15
ReadOnce == \A g \in DOMAIN reads : reads[g] <= 1
CopyStable == ~badCopy
\* the pages of a run fit the table of the worker that loads them
RunFits == \A w \in W : PP * Cardinality(tbl[w]) <= CAP
\* C6
AllRead == AllDone => \A g \in DOMAIN reads : reads[g] = 1
\* a worker that may still load a partition is counted
Counted == loaders = Cardinality({w \in W : ph[w] \in {"take", "cas", "unshare", "load", "share", "own", "leave"}})

NotHelped == ~helped
NotAllDone == ~AllDone
NotRun == \A w \in W : Cardinality(tbl[w]) <= 1
=============================================================================
