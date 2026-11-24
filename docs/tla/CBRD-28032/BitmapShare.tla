--------------------------- MODULE BitmapShare ---------------------------
(***************************************************************************)
(* How the workers of the heap step of a parallel bitmap heap scan share   *)
(* the pages of a partition (scan_bitmap_marks::take_partition, load,      *)
(* take_chunk; the heap step of task::execute in px_scan_task.cpp).        *)
(*                                                                         *)
(* A worker takes a partition that got a mark, loads its pages into its    *)
(* own table and puts them on offer.  It takes them a chunk at a time, and *)
(* so does every worker that found no partition left: the pages of a key   *)
(* range that lie in one partition are read by all workers.  A chunk is    *)
(* copied under the table's mutex, and nothing is on offer while the table *)
(* is loaded again.  A worker that finds nothing on offer leaves when no   *)
(* worker may load a partition any more.                                   *)
(*                                                                         *)
(* The claims (C15, C6): every marked page is read by one worker, once;    *)
(* no chunk is copied from a table being loaded; every worker ends.        *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS NW,       \* workers
          NP,       \* partitions
          PP,       \* marked pages of a partition that got a mark
          K,        \* pages of a chunk
          Mutant    \* "none" | "no_unshare" | "no_lock" | "share_early" | "early_leave"

W == 1..NW
P == 1..NP
Pages(m) == {<<p, i>> : p \in m, i \in 1..PP}

VARIABLES marksIn,  \* the partitions that got a mark
          nextPart, \* m_bm_next_part
          loaders,  \* m_bm_loaders
          ph,       \* a worker: "enter" | "take" | "unshare" | "load" | "share" | "own" | "leave" | "help" | "check" | "done"
          part,     \* the partition it took
          tbl,      \* the partition whose pages its table holds; 0: none
          loading,  \* its table is being loaded
          shN,      \* share_n
          shNext,   \* share_next
          hi,       \* helping: the worker whose table it asks next
          any,      \* ... it got a chunk in this pass
          seen,     \* mutant no_lock: share_next as read before it is written; 0: nothing read
          reads,    \* how often each page was read
          helped,   \* a page was read by a worker that did not load it
          badCopy   \* a chunk was copied from a table being loaded

vars == <<marksIn, nextPart, loaders, ph, part, tbl, loading, shN, shNext, hi, any, seen, reads, helped, badCopy>>

Init ==
  /\ marksIn \in SUBSET P
  /\ nextPart = 1 /\ loaders = 0
  /\ ph = [w \in W |-> "enter"] /\ part = [w \in W |-> 0] /\ tbl = [w \in W |-> 0]
  /\ loading = [w \in W |-> FALSE] /\ shN = [w \in W |-> 0] /\ shNext = [w \in W |-> 0]
  /\ hi = [w \in W |-> 1] /\ any = [w \in W |-> FALSE] /\ seen = [w \in W |-> 0]
  /\ reads = [g \in Pages(marksIn) |-> 0] /\ helped = FALSE /\ badCopy = FALSE

\* scan_bitmap_marks::enter_partitions
Enter(w) ==
  /\ ph[w] = "enter"
  /\ loaders' = loaders + 1 /\ ph' = [ph EXCEPT ![w] = "take"]
  /\ UNCHANGED <<marksIn, nextPart, part, tbl, loading, shN, shNext, hi, any, seen, reads, helped, badCopy>>

\* scan_bitmap_marks::take_partition: one fetch_add; a partition without a mark is passed
Take(w) ==
  /\ ph[w] = "take"
  /\ nextPart' = nextPart + 1
  /\ IF nextPart > NP THEN ph' = [ph EXCEPT ![w] = "leave"] /\ UNCHANGED part
     ELSE IF nextPart \in marksIn THEN ph' = [ph EXCEPT ![w] = "unshare"] /\ part' = [part EXCEPT ![w] = nextPart]
     ELSE UNCHANGED <<ph, part>>
  /\ UNCHANGED <<marksIn, loaders, tbl, loading, shN, shNext, hi, any, seen, reads, helped, badCopy>>

\* scan_bitmap_marks::load, under the table's mutex: nothing is on offer
Unshare(w) ==
  /\ ph[w] = "unshare"
  /\ IF Mutant = "no_unshare" THEN UNCHANGED <<shN, shNext>>
     ELSE shN' = [shN EXCEPT ![w] = IF Mutant = "share_early" THEN PP ELSE 0] /\ shNext' = [shNext EXCEPT ![w] = 0]
  /\ loading' = [loading EXCEPT ![w] = TRUE] /\ tbl' = [tbl EXCEPT ![w] = 0]
  /\ ph' = [ph EXCEPT ![w] = "load"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, part, hi, any, seen, reads, helped, badCopy>>

\* ... the table is cleared, filled from every worker's entries and records, and sorted, outside the mutex
Load(w) ==
  /\ ph[w] = "load"
  /\ tbl' = [tbl EXCEPT ![w] = part[w]] /\ loading' = [loading EXCEPT ![w] = FALSE]
  /\ ph' = [ph EXCEPT ![w] = "share"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, part, shN, shNext, hi, any, seen, reads, helped, badCopy>>

\* ... under the mutex: its pages are on offer
Share(w) ==
  /\ ph[w] = "share"
  /\ shN' = [shN EXCEPT ![w] = PP]
  /\ ph' = [ph EXCEPT ![w] = "own"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, part, tbl, loading, shNext, hi, any, seen, reads, helped, badCopy>>

Min(a, b) == IF a < b THEN a ELSE b

\* the pages of the chunk that starts at `at` in the table of `from`
Chunk(from, at) == {<<tbl[from], i>> : i \in (at + 1)..Min(at + K, shN[from])}

\* scan_bitmap_marks::take_chunk, under the mutex of the table of `from`: the chunk is copied and share_next moves
Copy(w, from, at) ==
  /\ badCopy' = (badCopy \/ loading[from] \/ tbl[from] = 0)
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
  /\ UNCHANGED <<marksIn, nextPart, loaders, ph, part, tbl, loading, shN, hi, any>>

\* mutant no_lock: the copy with the place read before
LateCopy(w, from) ==
  /\ Mutant = "no_lock" /\ seen[w] /= 0
  /\ (ph[w] = "own" /\ from = w) \/ (ph[w] = "help" /\ from = hi[w])
  /\ Copy(w, from, seen[w] - 1) /\ seen' = [seen EXCEPT ![w] = 0]
  /\ any' = [any EXCEPT ![w] = any[w] \/ ph[w] = "help"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, ph, part, tbl, loading, shN, hi>>

\* ... none is left: the next partition
OwnDone(w) ==
  /\ ph[w] = "own" /\ seen[w] = 0 /\ (~Offered(w) \/ Mutant = "early_leave")
  /\ ph' = [ph EXCEPT ![w] = "take"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, part, tbl, loading, shN, shNext, hi, any, seen, reads, helped, badCopy>>

\* scan_bitmap_marks::leave_partitions
Leave(w) ==
  /\ ph[w] = "leave"
  /\ loaders' = loaders - 1 /\ ph' = [ph EXCEPT ![w] = "help"]
  /\ hi' = [hi EXCEPT ![w] = 1] /\ any' = [any EXCEPT ![w] = FALSE]
  /\ UNCHANGED <<marksIn, nextPart, part, tbl, loading, shN, shNext, seen, reads, helped, badCopy>>

\* a worker without a partition takes a chunk of the table it asks
HelpChunk(w) ==
  /\ ph[w] = "help" /\ hi[w] <= NW /\ Offered(hi[w]) /\ (Mutant /= "no_lock" \/ seen[w] = 0)
  /\ IF Mutant = "no_lock"
       THEN seen' = [seen EXCEPT ![w] = shNext[hi[w]] + 1] /\ UNCHANGED <<reads, helped, badCopy, shNext, any>>
       ELSE Copy(w, hi[w], shNext[hi[w]]) /\ any' = [any EXCEPT ![w] = TRUE] /\ UNCHANGED seen
  /\ UNCHANGED <<marksIn, nextPart, loaders, ph, part, tbl, loading, shN, hi>>

\* ... nothing on offer there: the next table
HelpNext(w) ==
  /\ ph[w] = "help" /\ hi[w] <= NW /\ ~Offered(hi[w]) /\ seen[w] = 0
  /\ hi' = [hi EXCEPT ![w] = hi[w] + 1]
  /\ UNCHANGED <<marksIn, nextPart, loaders, ph, part, tbl, loading, shN, shNext, any, seen, reads, helped, badCopy>>

\* ... every table was asked: again when a chunk was got
HelpPass(w) ==
  /\ ph[w] = "help" /\ hi[w] > NW
  /\ ph' = [ph EXCEPT ![w] = IF any[w] THEN "help" ELSE "check"]
  /\ hi' = [hi EXCEPT ![w] = 1] /\ any' = [any EXCEPT ![w] = FALSE]
  /\ UNCHANGED <<marksIn, nextPart, loaders, part, tbl, loading, shN, shNext, seen, reads, helped, badCopy>>

\* scan_bitmap_marks::loaders_left: nothing was on offer; it ends when no worker may put pages on offer
Check(w) ==
  /\ ph[w] = "check"
  /\ ph' = [ph EXCEPT ![w] = IF loaders > 0 THEN "help" ELSE "done"]
  /\ UNCHANGED <<marksIn, nextPart, loaders, part, tbl, loading, shN, shNext, hi, any, seen, reads, helped, badCopy>>

AllDone == \A w \in W : ph[w] = "done"

Finished == AllDone /\ UNCHANGED vars

Next ==
  \/ \E w \in W : \/ Enter(w) \/ Take(w) \/ Unshare(w) \/ Load(w) \/ Share(w) \/ OwnChunk(w) \/ OwnDone(w)
                  \/ Leave(w) \/ HelpChunk(w) \/ HelpNext(w) \/ HelpPass(w) \/ Check(w)
                  \/ \E from \in W : LateCopy(w, from)
  \/ Finished

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ marksIn \subseteq P /\ nextPart \in 1..(NP + NW + 1) /\ loaders \in 0..NW
  /\ ph \in [W -> {"enter", "take", "unshare", "load", "share", "own", "leave", "help", "check", "done"}]
  /\ part \in [W -> 0..NP] /\ tbl \in [W -> 0..NP] /\ loading \in [W -> BOOLEAN]
  /\ shN \in [W -> 0..PP] /\ shNext \in [W -> 0..PP]
  /\ hi \in [W -> 1..(NW + 1)] /\ any \in [W -> BOOLEAN] /\ seen \in [W -> 0..(PP + 1)]
  /\ reads \in [Pages(marksIn) -> 0..(NW + 1)] /\ helped \in BOOLEAN /\ badCopy \in BOOLEAN

\* C15
ReadOnce == \A g \in DOMAIN reads : reads[g] <= 1
CopyStable == ~badCopy
\* C6
AllRead == AllDone => \A g \in DOMAIN reads : reads[g] = 1
\* a worker that may still load a partition is counted
Counted == loaders = Cardinality({w \in W : ph[w] \in {"take", "unshare", "load", "share", "own", "leave"}})

NotHelped == ~helped
NotAllDone == ~AllDone
=============================================================================
