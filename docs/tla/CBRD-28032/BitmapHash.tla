--------------------------- MODULE BitmapHash ---------------------------
(***************************************************************************)
(* The bitmap heap scan of CBRD-28032 as designed on 2026-11-18 (MAP.md    *)
(* E1..E29).                                                               *)
(*                                                                         *)
(* Index step: the workers of the parallel index scan take leaves in key   *)
(* order and record every OID that passes the key conditions.  A worker    *)
(* keeps a hash table of page entries of its own (E21, E22).  Partitions   *)
(* are ranges of heap position; their number is fixed when the scan starts *)
(* from the heap's page count, so that one partition's pages fit a table   *)
(* (E30).  Until its table is full a worker keeps every page in it; from   *)
(* then on the table holds the lowest partition only: the other entries    *)
(* leave as temp records (E27), and so does every later mark outside the   *)
(* lowest partition.  An OID whose slot number is beyond the entry's width *)
(* goes to the worker's over-width list instead (E20).                     *)
(*                                                                         *)
(* Heap step, after every index worker has finished: a heap worker takes a *)
(* partition, ORs every worker's table entries and records of that range   *)
(* into one table (the same page meets by its hash key), and reads the     *)
(* marked pages, each once.  A table too large for one level of partitions *)
(* (TwoLevel) has wider partitions: the worker keeps the lowest part and   *)
(* hands the rest on as a new partition.  The over-width lists are put     *)
(* together and looked up apart (E25).                                     *)
(*                                                                         *)
(* Claims: C6 (every row the scan must return is returned exactly once,    *)
(* nothing else), C4 (a scan that ended holds no page), C7 (a merge of     *)
(* leaves during the index step loses no key), C8 (a row inserted after    *)
(* the snapshot is not returned).                                          *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS IdxWorkers,   \* workers of the index step
          HeapWorkers,  \* workers of the heap step
          Mutant,       \* "none" or one of the wrong variants below
          MaxErrors,    \* errors or interrupts in a run
          TwoLevel,     \* the table is too large for one level of partitions: a heap worker divides its partition once more
          Rebuild       \* environment: a nested statement may rebuild the statement's snapshot (CBRD-27579)

\* Mutant: "no_flush" | "no_barrier" | "evict_lost" | "no_or" | "unit_twice" | "no_redivide" | "no_heap_visibility"
\*         | "drop_over" | "over_twice" | "release_frontier" | "no_release" | "no_freed_skip" | "fix_freed"

\* apalache-type: IdxWorkers Set(Str)
\* apalache-type: HeapWorkers Set(Str)
\* apalache-type: Mutant Str
\* apalache-type: MaxErrors Int
\* apalache-type: Rebuild Bool
\* apalache-type: snap Int
\* apalache-type: ent Str -> Set(Str)
\* apalache-type: leafTodo Set(Str)
\* apalache-type: alive Set(Str)
\* apalache-type: leafOf Str -> Str
\* apalache-type: pend Str -> Set(Str)
\* apalache-type: lastDisp Str
\* apalache-type: fheld Str
\* apalache-type: TwoLevel Bool
\* apalache-type: sw Str -> Bool
\* apalache-type: store Str -> (Str -> Set(Str))
\* apalache-type: over Str -> Set(Str)
\* apalache-type: idone Str -> Bool
\* apalache-type: taken Set(Set(Str))
\* apalache-type: runits Set(Set(Str))
\* apalache-type: redo Set(Str)
\* apalache-type: cur Str -> Set(Str)
\* apalache-type: onOver Str -> Bool
\* apalache-type: overDone Bool
\* apalache-type: fresh Str -> Bool
\* apalache-type: work Str -> (Str -> Int)
\* apalache-type: held Str -> Str
\* apalache-type: freed Set(Str)
\* apalache-type: out Str -> Int
\* apalache-type: gone Set(Str)
\* apalache-type: aborted Bool
\* apalache-type: errs Int

CInit ==
  /\ IdxWorkers = {"i1", "i2"}
  /\ HeapWorkers = {"h1", "h2"}
  /\ Mutant = "none"
  /\ MaxErrors \in Nat
  /\ Rebuild = FALSE
  /\ TwoLevel \in BOOLEAN

(***************************************************************************)
(* The table and its index, small enough to enumerate.  The heap is four   *)
(* quarters q1..q4 in file order; a partition is a run of quarters.        *)
(*   page p1 (q1)  r1  visible; its OID is in two leaves (an old and a new *)
(*                     key of the same row)                                *)
(*   page p2 (q2)  r2  visible                                             *)
(*   page p3 (q3)  r3  visible                                             *)
(*   page p4 (q4)  r6  visible                                             *)
(*                 r7  visible; its slot number is beyond the entry's      *)
(*                     width (over-width list); its OID is in two leaves   *)
(*   page p5 (q4)  r8  deleted before the snapshot, the only row of its    *)
(*                     page: once vacuum removed it the page may be        *)
(*                     deallocated while the scan runs                     *)
(*   page p9 (q4)  r5  inserted after the snapshot, on a page of a sector  *)
(*                     the heap got after the sector list was taken (it    *)
(*                     falls into the nearest partition, E26)              *)
(***************************************************************************)
Rows == {"r1", "r2", "r3", "r5", "r6", "r7", "r8"}
Leaves == {"l1", "l2", "l3"}
Quarters == {"q1", "q2", "q3", "q4"}
Pages == {"p1", "p2", "p3", "p4", "p5", "p9"}
StoreIds == {"tbl", "stg", "h2", "c2", "c3", "c4"}
NoLeaf == "no_leaf"
NoPage == "no_page"

LNum(l) == IF l = "l1" THEN 1 ELSE IF l = "l2" THEN 2 ELSE 3
QNum(q) == IF q = "q1" THEN 1 ELSE IF q = "q2" THEN 2 ELSE IF q = "q3" THEN 3 ELSE 4
Ent0(l) == IF l = "l1" THEN {"r1", "r2"} ELSE IF l = "l2" THEN {"r1", "r3", "r7"} ELSE {"r5", "r6", "r7", "r8"}
PageOf(r) ==
  IF r = "r1" THEN "p1" ELSE IF r = "r2" THEN "p2" ELSE IF r = "r3" THEN "p3"
  ELSE IF r \in {"r6", "r7"} THEN "p4" ELSE IF r = "r8" THEN "p5" ELSE "p9"
QOf(r) == IF r = "r1" THEN "q1" ELSE IF r = "r2" THEN "q2" ELSE IF r = "r3" THEN "q3" ELSE "q4"
Wide == {"r7"}
\* the rows the snapshot s sees: 1 is the statement's snapshot, 2 a snapshot rebuilt while the scan runs
Vis(s) == IF s = 2 THEN {"r1", "r2", "r3", "r5", "r6", "r7"} ELSE {"r1", "r2", "r3", "r6", "r7"}

\* The rows the scan must return: those of the statement's snapshot.
Expected == Vis(1)

\* The quarters of the partition a full table keeps, and the temp records a mark of quarter q goes to otherwise.
Mem == IF TwoLevel THEN {"q1", "q2"} ELSE {"q1"}
ChainFor(q) == IF TwoLevel THEN "h2" ELSE IF q = "q2" THEN "c2" ELSE IF q = "q3" THEN "c3" ELSE "c4"
\* The partitions the heap step starts from: one quarter each, or one half each when the table needs two levels.
Units == IF TwoLevel THEN {{"q1", "q2"}, {"q3", "q4"}} ELSE {{"q1"}, {"q2"}, {"q3"}, {"q4"}}

VARIABLES snap,       \* the snapshot rows are judged by
          ent,        \* [Leaves -> SUBSET Rows]: the entries a leaf holds now
          leafTodo,   \* leaves not yet handed to an index worker
          alive,      \* leaves in the chain: a leaf merged into its left neighbour leaves it
          leafOf,     \* [IdxWorkers -> Leaves \cup {NoLeaf}]: the leaf a worker reads (and keeps latched)
          pend,       \* [IdxWorkers -> SUBSET Rows]: entries of that leaf not yet examined
          lastDisp,   \* the last leaf handed out
          fheld,      \* the frontier leaf kept latched after its worker finished it, until the next leaf is fixed
          sw,         \* [IdxWorkers -> BOOLEAN]: the worker's table was full once and holds the lowest partition only since
          store,      \* [IdxWorkers -> [StoreIds -> SUBSET Rows]]: table ("tbl"), records not yet written ("stg"), temp records by partition
          over,       \* [IdxWorkers -> SUBSET Rows]: the worker's over-width list
          idone,      \* [IdxWorkers -> BOOLEAN]: the worker has finished the index step
          taken,      \* partitions handed to a heap worker
          runits,     \* partitions handed on by a worker that kept only the lowest part of its own
          redo,       \* the records of those partitions
          cur,        \* [HeapWorkers -> SUBSET Quarters]: the partition a heap worker reads ({}: none)
          onOver,     \* [HeapWorkers -> BOOLEAN]: the worker looks up the over-width lists
          overDone,   \* the over-width lists were taken
          fresh,      \* [HeapWorkers -> BOOLEAN]: the worker has not fixed a page of its partition yet
          work,       \* [HeapWorkers -> [Rows -> Nat]]: rows still to look at
          held,       \* [HeapWorkers -> Pages \cup {NoPage}]: the marked page a worker keeps fixed
          freed,      \* pages vacuum emptied and deallocated
          out,        \* [Rows -> Nat]: times a row was returned
          gone,       \* rows vacuum removed
          aborted,    \* an error or interrupt ended the scan
          errs

vars == <<snap, ent, leafTodo, alive, leafOf, pend, lastDisp, fheld, sw, store, over, idone, taken, runits, redo, cur,
          onOver, overDone, fresh, work, held, freed, out, gone, aborted, errs>>

idxVars == <<ent, leafTodo, alive, leafOf, pend, lastDisp, fheld>>
partVars == <<sw, store, over>>
heapVars == <<taken, runits, redo, cur, onOver, overDone, fresh, work, held>>

TypeOK ==
  /\ snap \in {1, 2}
  /\ ent \in [Leaves -> SUBSET Rows]
  /\ leafTodo \in SUBSET Leaves
  /\ alive \in SUBSET Leaves
  /\ leafOf \in [IdxWorkers -> Leaves \cup {NoLeaf}]
  /\ pend \in [IdxWorkers -> SUBSET Rows]
  /\ lastDisp \in Leaves \cup {NoLeaf}
  /\ fheld \in Leaves \cup {NoLeaf}
  /\ sw \in [IdxWorkers -> BOOLEAN]
  /\ store \in [IdxWorkers -> [StoreIds -> SUBSET Rows]]
  /\ over \in [IdxWorkers -> SUBSET Rows]
  /\ idone \in [IdxWorkers -> BOOLEAN]
  /\ taken \in SUBSET (SUBSET Quarters)
  /\ runits \in SUBSET (SUBSET Quarters)
  /\ redo \in SUBSET Rows
  /\ cur \in [HeapWorkers -> SUBSET Quarters]
  /\ onOver \in [HeapWorkers -> BOOLEAN]
  /\ overDone \in BOOLEAN
  /\ fresh \in [HeapWorkers -> BOOLEAN]
  /\ work \in [HeapWorkers -> [Rows -> 0..10]]
  /\ held \in [HeapWorkers -> Pages \cup {NoPage}]
  /\ freed \in SUBSET Pages
  /\ out \in [Rows -> 0..8]
  /\ gone \in SUBSET Rows
  /\ aborted \in BOOLEAN
  /\ errs \in Int /\ errs >= 0 /\ errs <= MaxErrors

Init ==
  /\ snap = 1
  /\ ent = [l \in Leaves |-> Ent0(l)]
  /\ leafTodo = Leaves
  /\ alive = Leaves
  /\ leafOf = [w \in IdxWorkers |-> NoLeaf]
  /\ pend = [w \in IdxWorkers |-> {}]
  /\ lastDisp = NoLeaf
  /\ fheld = NoLeaf
  /\ sw = [w \in IdxWorkers |-> FALSE]
  /\ store = [w \in IdxWorkers |-> [s \in StoreIds |-> {}]]
  /\ over = [w \in IdxWorkers |-> {}]
  /\ idone = [w \in IdxWorkers |-> FALSE]
  /\ taken = {}
  /\ runits = {}
  /\ redo = {}
  /\ cur = [h \in HeapWorkers |-> {}]
  /\ onOver = [h \in HeapWorkers |-> FALSE]
  /\ overDone = FALSE
  /\ fresh = [h \in HeapWorkers |-> FALSE]
  /\ work = [h \in HeapWorkers |-> [r \in Rows |-> 0]]
  /\ held = [h \in HeapWorkers |-> NoPage]
  /\ freed = {}
  /\ out = [r \in Rows |-> 0]
  /\ gone = {}
  /\ aborted = FALSE
  /\ errs = 0

(***************************************************************************)
(* Index step: leaves                                                      *)
(***************************************************************************)

Latched(l) == l = fheld \/ \E w \in IdxWorkers : leafOf[w] = l

\* The dispatcher hands the next leaf of the chain to one worker.  The leaf is fixed before the frontier (the
\* last leaf handed out, kept latched by its worker) is let go.
TakeLeafL(w, l) ==
  /\ ~aborted /\ ~idone[w] /\ leafOf[w] = NoLeaf
  /\ l \in leafTodo /\ \A m \in leafTodo : LNum(l) <= LNum(m)
  /\ leafTodo' = leafTodo \ {l}
  /\ leafOf' = [leafOf EXCEPT ![w] = l]
  /\ pend' = [pend EXCEPT ![w] = ent[l]]
  /\ lastDisp' = l
  /\ fheld' = NoLeaf
  /\ UNCHANGED <<snap, ent, alive, partVars, idone, heapVars, freed, out, gone, aborted, errs>>

TakeLeaf(w) == \E l \in leafTodo : TakeLeafL(w, l)

\* The worker has examined every entry of its leaf.  When the leaf is the frontier and the chain goes on, its
\* latch stays until the next leaf is fixed: a merge could otherwise move that leaf's keys into this one.
EndLeaf(w) ==
  /\ ~aborted /\ leafOf[w] # NoLeaf /\ pend[w] = {}
  /\ fheld' = IF leafOf[w] = lastDisp /\ leafTodo # {} /\ Mutant # "release_frontier" THEN leafOf[w] ELSE fheld
  /\ leafOf' = [leafOf EXCEPT ![w] = NoLeaf]
  /\ UNCHANGED <<snap, ent, leafTodo, alive, pend, lastDisp, partVars, idone, heapVars, freed, out, gone, aborted, errs>>

\* No leaf is left and the records it gathered are written: the worker's part of the index step is over.
IdxFinish(w) ==
  /\ ~aborted /\ ~idone[w] /\ leafOf[w] = NoLeaf /\ leafTodo = {}
  /\ store[w]["stg"] = {} \/ Mutant = "no_flush"
  /\ idone' = [idone EXCEPT ![w] = TRUE]
  /\ UNCHANGED <<snap, idxVars, partVars, heapVars, freed, out, gone, aborted, errs>>

\* Environment: another transaction's delete and vacuum merge leaf r into its left neighbour l.  The merge
\* latches both leaves, so it waits for a reader of either and for the frontier's latch.
MergeLR(l, r) ==
  /\ ~aborted
  /\ l \in alive /\ r \in alive /\ LNum(l) < LNum(r) /\ r \in leafTodo
  /\ \A m \in alive : ~(LNum(l) < LNum(m) /\ LNum(m) < LNum(r))
  /\ ~Latched(l) /\ ~Latched(r)
  /\ ent' = [ent EXCEPT ![l] = ent[l] \cup ent[r], ![r] = {}]
  /\ leafTodo' = leafTodo \ {r}
  /\ alive' = alive \ {r}
  /\ UNCHANGED <<snap, leafOf, pend, lastDisp, fheld, partVars, idone, heapVars, freed, out, gone, aborted, errs>>

Merge == \E l, r \in Leaves : MergeLR(l, r)

(***************************************************************************)
(* Index step: marks                                                       *)
(***************************************************************************)

\* The table when it holds the lowest partition only: the other entries leave as records.  A record waits in
\* the worker's memory ("stg") until a batch of them is written to the temp pages of their partitions.
Arranged(st, lost) ==
  [s \in StoreIds |->
     IF s = "tbl" THEN {r \in st["tbl"] : QOf(r) \in Mem}
     ELSE IF s = "stg" THEN st[s] \cup (IF lost THEN {} ELSE {r \in st["tbl"] : QOf(r) \notin Mem})
     ELSE st[s]]
Written(st) ==
  [s \in StoreIds |->
     IF s = "tbl" THEN st[s]
     ELSE IF s = "stg" THEN {}
     ELSE st[s] \cup {r \in st["stg"] : ChainFor(QOf(r)) = s}]

\* The worker's table is full for the first time: from here on it holds the lowest partition only (E30).
Switch(w) ==
  /\ ~aborted /\ ~idone[w] /\ ~sw[w]
  /\ sw' = [sw EXCEPT ![w] = TRUE]
  /\ store' = [store EXCEPT ![w] = Arranged(store[w], Mutant = "evict_lost")]
  /\ UNCHANGED <<snap, idxVars, over, idone, heapVars, freed, out, gone, aborted, errs>>

\* The worker writes the records it gathered to the temp pages of their partitions: whenever the batch is full,
\* and before it leaves the index step.
Flush(w) ==
  /\ ~aborted /\ ~idone[w] /\ store[w]["stg"] # {}
  /\ store' = [store EXCEPT ![w] = Written(store[w])]
  /\ UNCHANGED <<snap, idxVars, sw, over, idone, heapVars, freed, out, gone, aborted, errs>>

\* One entry of the leaf.  The leaf may already tell that a row is invisible, then it is not recorded.  A slot
\* beyond the width goes to the over-width list; a page of the lowest partition to the table (one OR into the
\* page's entry); any other page to the records the worker gathers.
MarkRow(w, r) ==
  /\ ~aborted
  /\ r \in pend[w]
  /\ pend' = [pend EXCEPT ![w] = @ \ {r}]
  /\ \/ /\ r \in Wide
        /\ over' = [over EXCEPT ![w] = @ \cup {r}]
        /\ UNCHANGED store
     \/ /\ r \notin Wide /\ (~sw[w] \/ QOf(r) \in Mem)
        /\ store' = [store EXCEPT ![w]["tbl"] = @ \cup {r}]
        /\ UNCHANGED over
     \/ /\ r \notin Wide /\ sw[w] /\ QOf(r) \notin Mem
        /\ store' = [store EXCEPT ![w]["stg"] = @ \cup {r}]
        /\ UNCHANGED over
     \/ /\ r \notin Vis(snap)
        /\ UNCHANGED <<store, over>>
  /\ UNCHANGED <<snap, ent, leafTodo, alive, leafOf, lastDisp, fheld, sw, idone, heapVars, freed, out, gone, aborted, errs>>

Mark(w) == \E r \in pend[w] : MarkRow(w, r)

(***************************************************************************)
(* Heap step                                                               *)
(***************************************************************************)

Barrier == (\A w \in IdxWorkers : idone[w]) \/ Mutant = "no_barrier"

\* How many tables and record sets hold row r: loading a partition ORs them into one entry.
\* The heap step reads tables and temp pages; a record still in a worker's memory is not among them.
Loadable == StoreIds \ {"stg"}
Held(r) == \E w \in IdxWorkers : \E s \in Loadable : r \in store[w][s]
ExamCount(r) ==
  IF Mutant = "no_or" THEN Cardinality({w \in IdxWorkers : r \in store[w]["tbl"]})
                           + Cardinality({w \in IdxWorkers : \E s \in Loadable \ {"tbl"} : r \in store[w][s]})
  ELSE IF Held(r) THEN 1 ELSE 0

\* A heap worker takes a partition.  Not before every index worker has finished: until then the tables and the
\* records still grow, and so may the count.
TakeUnitU(h, u) ==
  /\ ~aborted /\ cur[h] = {} /\ ~onOver[h]
  /\ Barrier
  /\ u \in Units \ taken
  /\ taken' = IF Mutant = "unit_twice" THEN taken ELSE taken \cup {u}
  /\ cur' = [cur EXCEPT ![h] = u]
  /\ fresh' = [fresh EXCEPT ![h] = TRUE]
  /\ work' = [work EXCEPT ![h] = [r \in Rows |-> IF QOf(r) \in u THEN ExamCount(r) ELSE 0]]
  /\ UNCHANGED <<snap, idxVars, partVars, idone, runits, redo, onOver, overDone, held, freed, out, gone, aborted, errs>>

TakeUnit(h) == \E u \in Units : TakeUnitU(h, u)

\* A partition another worker handed on: its records are the ones that worker wrote out.
TakeRedoU(h, u) ==
  /\ ~aborted /\ cur[h] = {} /\ ~onOver[h]
  /\ u \in runits
  /\ runits' = runits \ {u}
  /\ redo' = {r \in redo : QOf(r) \notin u}
  /\ cur' = [cur EXCEPT ![h] = u]
  /\ fresh' = [fresh EXCEPT ![h] = TRUE]
  /\ work' = [work EXCEPT ![h] = [r \in Rows |-> IF r \in redo /\ QOf(r) \in u THEN 1 ELSE 0]]
  /\ UNCHANGED <<snap, idxVars, partVars, idone, taken, onOver, overDone, held, freed, out, gone, aborted, errs>>

TakeRedo(h) == \E u \in runits : TakeRedoU(h, u)

\* The partition does not fit the worker's table: it keeps the lowest quarter and writes the rest out as a
\* new partition.
LowQ(u) == CHOOSE q \in u : \A p \in u : QNum(q) <= QNum(p)
Divide(h) ==
  /\ ~aborted /\ fresh[h] /\ held[h] = NoPage
  /\ TwoLevel /\ Cardinality(cur[h]) > 1
  /\ LET keep == {LowQ(cur[h])}
         rest == cur[h] \ keep
         moved == {r \in Rows : work[h][r] > 0 /\ QOf(r) \in rest}
     IN  /\ cur' = [cur EXCEPT ![h] = keep]
         /\ runits' = runits \cup {rest}
         /\ redo' = redo \cup (IF Mutant = "no_redivide" THEN {} ELSE moved)
         /\ work' = [work EXCEPT ![h] = [r \in Rows |-> IF r \in moved THEN 0 ELSE work[h][r]]]
  /\ UNCHANGED <<snap, idxVars, partVars, idone, taken, onOver, overDone, fresh, held, freed, out, gone, aborted, errs>>

\* The over-width lists: one worker takes them all, sorted and without duplicates.
OverCount(r) ==
  IF Mutant = "drop_over" THEN 0
  ELSE IF Mutant = "over_twice" THEN Cardinality({w \in IdxWorkers : r \in over[w]})
  ELSE IF \E w \in IdxWorkers : r \in over[w] THEN 1 ELSE 0
TakeOver(h) ==
  /\ ~aborted /\ cur[h] = {} /\ ~onOver[h] /\ ~overDone
  /\ Barrier
  /\ overDone' = TRUE
  /\ onOver' = [onOver EXCEPT ![h] = TRUE]
  /\ fresh' = [fresh EXCEPT ![h] = FALSE]
  /\ work' = [work EXCEPT ![h] = [r \in Rows |-> OverCount(r)]]
  /\ UNCHANGED <<snap, idxVars, partVars, idone, taken, runits, redo, cur, held, freed, out, gone, aborted, errs>>

Active(h) == cur[h] # {} \/ onOver[h]

\* A marked page is fixed once, before its rows are read, and kept until the last of them.
FixPageP(h, p) ==
  /\ ~aborted /\ Active(h)
  /\ held[h] = NoPage \/ Mutant = "no_release"
  /\ held[h] # p
  /\ p \notin freed \/ Mutant = "fix_freed"
  /\ \E r \in Rows : PageOf(r) = p /\ work[h][r] > 0
  /\ held' = [held EXCEPT ![h] = p]
  /\ fresh' = [fresh EXCEPT ![h] = FALSE]
  /\ UNCHANGED <<snap, idxVars, partVars, idone, taken, runits, redo, cur, onOver, overDone, work, freed, out, gone, aborted, errs>>

FixPage(h) == \E p \in Pages : FixPageP(h, p)

\* A marked page that is gone when the worker comes to fix it: every row it held was removed by vacuum.
SkipFreedPageP(h, p) ==
  /\ ~aborted /\ Active(h) /\ Mutant # "no_freed_skip"
  /\ p \in freed
  /\ \E r \in Rows : PageOf(r) = p /\ work[h][r] > 0
  /\ work' = [work EXCEPT ![h] = [r \in Rows |-> IF PageOf(r) = p THEN 0 ELSE work[h][r]]]
  /\ fresh' = [fresh EXCEPT ![h] = FALSE]
  /\ UNCHANGED <<snap, idxVars, partVars, idone, taken, runits, redo, cur, onOver, overDone, held, freed, out, gone, aborted, errs>>

SkipFreedPage(h) == \E p \in Pages : SkipFreedPageP(h, p)

\* One marked row of the held page: a row that is gone or that the snapshot does not see is skipped.
LookupRow(h, r) ==
  /\ ~aborted
  /\ work[h][r] > 0
  /\ held[h] = PageOf(r)
  /\ work' = [work EXCEPT ![h][r] = @ - 1]
  /\ IF (r \in gone \/ r \notin Vis(snap)) /\ Mutant # "no_heap_visibility"
       THEN UNCHANGED out
       ELSE out' = [out EXCEPT ![r] = @ + 1]
  /\ UNCHANGED <<snap, idxVars, partVars, idone, taken, runits, redo, cur, onOver, overDone, fresh, held, freed, gone, aborted, errs>>

Lookup(h) == \E r \in Rows : LookupRow(h, r)

ReleasePage(h) ==
  /\ ~aborted /\ held[h] # NoPage /\ Mutant # "no_release"
  /\ \A r \in Rows : PageOf(r) = held[h] => work[h][r] = 0
  /\ held' = [held EXCEPT ![h] = NoPage]
  /\ UNCHANGED <<snap, idxVars, partVars, idone, taken, runits, redo, cur, onOver, overDone, fresh, work, freed, out, gone, aborted,
                 errs>>

EndUnit(h) ==
  /\ ~aborted /\ Active(h)
  /\ \A r \in Rows : work[h][r] = 0
  /\ held[h] = NoPage \/ Mutant = "no_release"
  /\ cur' = [cur EXCEPT ![h] = {}]
  /\ onOver' = [onOver EXCEPT ![h] = FALSE]
  /\ fresh' = [fresh EXCEPT ![h] = FALSE]
  /\ UNCHANGED <<snap, idxVars, partVars, idone, taken, runits, redo, overDone, work, held, freed, out, gone, aborted, errs>>

(***************************************************************************)
(* Environment                                                             *)
(***************************************************************************)

\* Vacuum removes a row no snapshot sees any more; its index entry may still be there.
VacuumRow(r) ==
  /\ r \in Rows \ (Vis(1) \cup Vis(2) \cup gone)
  /\ gone' = gone \cup {r}
  /\ UNCHANGED <<snap, idxVars, partVars, idone, heapVars, freed, out, aborted, errs>>

Vacuum == \E r \in Rows : VacuumRow(r)

\* Vacuum deallocates a page it emptied.  Not a page a scan holds fixed: the deallocation takes the page's latch.
FreePageP(p) ==
  /\ p \in Pages \ freed
  /\ \A r \in Rows : PageOf(r) = p => r \in gone
  /\ \A h \in HeapWorkers : held[h] # p
  /\ freed' = freed \cup {p}
  /\ UNCHANGED <<snap, idxVars, partVars, idone, heapVars, out, gone, aborted, errs>>

FreePage == \E p \in Pages : FreePageP(p)

\* A nested statement rebuilds the statement's snapshot (the environment the claims exclude, CBRD-27579).
RebuildSnap ==
  /\ Rebuild /\ ~aborted /\ snap = 1
  /\ snap' = 2
  /\ UNCHANGED <<idxVars, partVars, idone, heapVars, freed, out, gone, aborted, errs>>

\* An error or interrupt on any worker ends the scan: every worker stops, tables, records and lists are released.
Abort ==
  /\ ~aborted /\ errs < MaxErrors
  /\ aborted' = TRUE
  /\ errs' = errs + 1
  /\ leafOf' = [w \in IdxWorkers |-> NoLeaf]
  /\ pend' = [w \in IdxWorkers |-> {}]
  /\ fheld' = NoLeaf
  /\ store' = [w \in IdxWorkers |-> [s \in StoreIds |-> {}]]
  /\ over' = [w \in IdxWorkers |-> {}]
  /\ runits' = {}
  /\ redo' = {}
  /\ cur' = [h \in HeapWorkers |-> {}]
  /\ onOver' = [h \in HeapWorkers |-> FALSE]
  /\ fresh' = [h \in HeapWorkers |-> FALSE]
  /\ work' = [h \in HeapWorkers |-> [r \in Rows |-> 0]]
  /\ held' = IF Mutant = "no_release" THEN held ELSE [h \in HeapWorkers |-> NoPage]
  /\ UNCHANGED <<snap, ent, leafTodo, alive, lastDisp, sw, idone, taken, overDone, freed, out, gone>>

Finished ==
  /\ ~aborted
  /\ \A w \in IdxWorkers : idone[w]
  /\ Units \subseteq taken
  /\ runits = {}
  /\ overDone
  /\ \A h \in HeapWorkers : ~Active(h)

Terminated == (Finished \/ aborted) /\ UNCHANGED vars

IdxStep(w) == TakeLeaf(w) \/ Mark(w) \/ Switch(w) \/ Flush(w) \/ EndLeaf(w) \/ IdxFinish(w)
HeapStep(h) ==
  TakeUnit(h) \/ TakeRedo(h) \/ Divide(h) \/ TakeOver(h) \/ FixPage(h) \/ SkipFreedPage(h) \/ Lookup(h) \/ ReleasePage(h)
  \/ EndUnit(h)

Next ==
  \/ \E w \in IdxWorkers : IdxStep(w)
  \/ \E h \in HeapWorkers : HeapStep(h)
  \/ Merge \/ Vacuum \/ FreePage \/ RebuildSnap \/ Abort \/ Terminated

\* A worker that could double the count for ever, or divide for ever, does not: both are bounded by the model
\* (the count stops at 4, a partition at one quarter), so weak fairness on the worker's step is enough.
Fairness ==
  /\ \A w \in IdxWorkers : WF_vars(TakeLeaf(w) \/ Mark(w) \/ Flush(w) \/ EndLeaf(w) \/ IdxFinish(w))
  /\ \A h \in HeapWorkers :
       WF_vars(TakeUnit(h) \/ TakeRedo(h) \/ TakeOver(h) \/ FixPage(h) \/ SkipFreedPage(h) \/ Lookup(h) \/ ReleasePage(h)
               \/ EndUnit(h))

Spec == Init /\ [][Next]_vars /\ Fairness

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)

\* C6, C8, safety half: no row is returned twice and no row that must not be returned is returned.
NoExtraRow == \A r \in Rows : out[r] <= (IF r \in Expected THEN 1 ELSE 0)

\* C6, C7, completeness half: a scan that ran to its end returned every row it must.
AllRowsReturned == Finished => \A r \in Expected : out[r] = 1

\* The scan ends (or is aborted).
Ends == <>(Finished \/ aborted)

\* C4: a scan that ended, finished or stopped, holds no heap page and no leaf.
NoPageHeld == (Finished \/ aborted) => (\A h \in HeapWorkers : held[h] = NoPage) /\ fheld = NoLeaf

\* No worker reads a page vacuum deallocated.
NoFreedPageHeld == \A h \in HeapWorkers : held[h] \notin freed

(***************************************************************************)
(* Inductive invariant                                                     *)
(***************************************************************************)

Pending(h, r) == work[h][r] > 0
UnitTaken(r) == \A u \in Units : QOf(r) \in u => u \in taken
ToMark(r) == (\E l \in leafTodo : r \in ent[l]) \/ (\E w \in IdxWorkers : r \in pend[w])
InStore(r) == \E w \in IdxWorkers : \E s \in StoreIds : r \in store[w][s]
InOver(r) == \E w \in IdxWorkers : r \in over[w]

SnapKept == ~Rebuild => snap = 1

\* A scan that was stopped holds nothing.
AbortedShape ==
  aborted =>
    /\ \A w \in IdxWorkers : leafOf[w] = NoLeaf /\ pend[w] = {} /\ over[w] = {}
                              /\ \A s \in StoreIds : store[w][s] = {}
    /\ fheld = NoLeaf /\ runits = {} /\ redo = {}
    /\ \A h \in HeapWorkers : cur[h] = {} /\ ~onOver[h] /\ held[h] = NoPage /\ \A r \in Rows : work[h][r] = 0

\* The leaves not yet handed out are those after the last one handed out.
LeafOrder ==
  /\ leafTodo \subseteq alive
  /\ lastDisp = NoLeaf => leafTodo = alive /\ fheld = NoLeaf /\ \A w \in IdxWorkers : leafOf[w] = NoLeaf
  /\ lastDisp # NoLeaf =>
       /\ lastDisp \in alive \ leafTodo
       /\ \A l \in leafTodo : LNum(l) > LNum(lastDisp)
       /\ \A l \in alive \ leafTodo : LNum(l) <= LNum(lastDisp)

LeafHeld ==
  /\ \A w \in IdxWorkers : leafOf[w] # NoLeaf => leafOf[w] \in alive \ leafTodo
  /\ \A w \in IdxWorkers : leafOf[w] = NoLeaf => pend[w] = {}
  /\ fheld # NoLeaf => fheld = lastDisp /\ leafTodo # {} /\ ~aborted

\* While the chain goes on, the last leaf handed out is latched: no merge moves keys into a leaf already read.
FrontierLatched == ~aborted /\ leafTodo # {} /\ lastDisp # NoLeaf => Latched(lastDisp)

IdxDone ==
  \A w \in IdxWorkers : idone[w] => leafTodo = {} /\ leafOf[w] = NoLeaf /\ store[w]["stg"] = {}

\* A slot within the width is marked in a table or a record, a slot beyond it goes to the list.
StoreKinds ==
  \A w \in IdxWorkers : over[w] \subseteq Wide /\ \A s \in StoreIds : store[w][s] \cap Wide = {}

\* A row the scan must return is still ahead in the index, or it is recorded.
Recorded ==
  ~aborted => \A r \in Expected : ToMark(r) \/ (IF r \in Wide THEN InOver(r) ELSE InStore(r))

VacuumOnlyDead ==
  /\ gone \cap (Vis(1) \cup Vis(2)) = {}
  /\ \A p \in freed : \A r \in Rows : PageOf(r) = p => r \in gone

Counts == \A r \in Rows : out[r] \in {0, 1} /\ \A h \in HeapWorkers : work[h][r] \in {0, 1}

\* What a heap worker reads: one partition, or part of one, or the lists; nobody else reads the same.
HeapShape ==
  /\ taken \subseteq Units
  /\ \A h \in HeapWorkers :
       /\ cur[h] # {} => ~onOver[h] /\ \E u \in taken : cur[h] \subseteq u
       /\ onOver[h] => overDone
       /\ held[h] # NoPage => (cur[h] # {} \/ onOver[h]) /\ ~aborted
       /\ \A g \in HeapWorkers : g # h => cur[h] \cap cur[g] = {} /\ ~(onOver[h] /\ onOver[g])
       /\ \A u \in runits : cur[h] \cap u = {}
  /\ \A u \in runits : u # {} /\ \E t \in taken : u \subseteq t
  /\ \A u \in runits : \A v \in runits : u # v => u \cap v = {}

WorkShape ==
  \A h \in HeapWorkers : \A r \in Rows :
    Pending(h, r) =>
      /\ out[r] = 0 /\ r \notin redo
      /\ IF onOver[h] THEN r \in Wide /\ overDone ELSE r \notin Wide /\ QOf(r) \in cur[h] /\ UnitTaken(r)
      /\ \A g \in HeapWorkers : g # h => ~Pending(g, r)

RedoShape ==
  \A r \in redo : out[r] = 0 /\ r \notin Wide /\ UnitTaken(r) /\ \E u \in runits : QOf(r) \in u

\* A row that was returned is not handed to any worker again.
Returned ==
  \A r \in Rows : out[r] = 1 => r \in Expected /\ (IF r \in Wide THEN overDone ELSE UnitTaken(r))

\* A row the scan must return is waiting for its partition (or the lists) to be taken, is in a worker's hands,
\* was handed on, or was returned.
Owed ==
  ~aborted =>
    \A r \in Expected :
      \/ out[r] = 1
      \/ \E h \in HeapWorkers : Pending(h, r)
      \/ r \in redo
      \/ IF r \in Wide THEN ~overDone ELSE ~UnitTaken(r)

IndInv ==
  /\ TypeOK
  /\ SnapKept
  /\ AbortedShape
  /\ LeafOrder
  /\ LeafHeld
  /\ FrontierLatched
  /\ IdxDone
  /\ StoreKinds
  /\ Recorded
  /\ VacuumOnlyDead
  /\ Counts
  /\ HeapShape
  /\ WorkShape
  /\ RedoShape
  /\ Returned
  /\ Owed
  /\ NoExtraRow
  /\ AllRowsReturned
  /\ NoPageHeld
  /\ NoFreedPageHeld

\* Witnesses
NotFinished == ~Finished
Spilled == \E w \in IdxWorkers : \E s \in Loadable \ {"tbl"} : store[w][s] # {}
NotSpilledRun == ~(Finished /\ Spilled)
NotRowSkipped == ~(\E h \in HeapWorkers : \E r \in Rows : work[h][r] > 0 /\ held[h] = PageOf(r) /\ r \notin Vis(snap))
NotHandedOn == redo = {}
NotMergedRun == ~(Finished /\ alive # Leaves)
NotPageHeld == \A h \in HeapWorkers : held[h] = NoPage
NotFinishedPastFreedPage == ~(Finished /\ "p5" \in freed)
NotOverLooked == out["r7"] = 0
NotSwitchedRun == ~(Finished /\ \A w \in IdxWorkers : sw[w])
NotMixedRun == ~(Finished /\ (\E w \in IdxWorkers : sw[w]) /\ (\E w \in IdxWorkers : ~sw[w] /\ store[w]["tbl"] # {}))
NotStagedAtBarrier == ~(\E w \in IdxWorkers : idone[w] /\ store[w]["stg"] # {})
NotInMemoryRun == ~(Finished /\ \A w \in IdxWorkers : ~sw[w])
=============================================================================
