--------------------------- MODULE BitmapScan ---------------------------
(***************************************************************************)
(* The whole-range batch of an index scan (D25..D33, D36): what PostgreSQL *)
(* calls a parallel bitmap heap scan.                                      *)
(*                                                                         *)
(* Index phase: the workers of the parallel index scan take leaf pages     *)
(* and record every OID that passes the key conditions in one shared       *)
(* sector bitmap, each mark an atomic OR.  The bitmap is exact (a bit per  *)
(* slot) when it fits the memory bound; otherwise, and for a slot beyond   *)
(* the bitmap's width, only the page is marked.  When every index worker   *)
(* has finished, the heap phase starts: a heap worker takes a sector and   *)
(* reads its marked rows; on a page marked as a whole it reads every row   *)
(* and checks the index condition again.  It returns the rows its snapshot *)
(* sees and the data filter accepts.                                       *)
(*                                                                         *)
(* The claim (C6): every row the scan must return is returned exactly      *)
(* once, and nothing else is returned.                                     *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS IdxWorkers,   \* workers of the index phase
          HeapWorkers,  \* workers of the heap phase
          Mutant,       \* "none" or one of the wrong variants below
          MaxErrors     \* errors or interrupts in a run

\* Mutant: "no_barrier" | "nonatomic_or" | "sector_twice" | "no_heap_visibility" | "late_sector_list"
\*         | "no_recheck" | "both_paths" | "no_release" | "no_freed_skip" | "fix_freed"

\* apalache-type: IdxWorkers Set(Str)
\* apalache-type: HeapWorkers Set(Str)
\* apalache-type: Mutant Str
\* apalache-type: MaxErrors Int
\* apalache-type: lossy Bool
\* apalache-type: leafTodo Set(Str)
\* apalache-type: leafOf Str -> Str
\* apalache-type: pend Str -> Set(Str)
\* apalache-type: bm Set(Str)
\* apalache-type: pagebm Set(Str)
\* apalache-type: ldr Str -> Str
\* apalache-type: ld Str -> Set(Str)
\* apalache-type: idone Str -> Bool
\* apalache-type: secTodo Set(Str)
\* apalache-type: secOf Str -> Str
\* apalache-type: work Str -> (Str -> Int)
\* apalache-type: held Str -> Str
\* apalache-type: freed Set(Str)
\* apalache-type: out Str -> Int
\* apalache-type: gone Set(Str)
\* apalache-type: aborted Bool
\* apalache-type: errs Int
\* apalache-type: dropped Bool
\* apalache-type: skipped Bool
\* apalache-type: rechecked Bool

CInit ==
  /\ IdxWorkers = {"i1", "i2"}
  /\ HeapWorkers = {"h1", "h2"}
  /\ Mutant = "none"
  /\ MaxErrors \in Nat

(***************************************************************************)
(* The table and its index, small enough to enumerate:                     *)
(*   page p1 (sector s1)                                                   *)
(*     r1  visible, accepted by the data filter; its OID is in two leaves  *)
(*         (an old and a new key of the same row)                          *)
(*     r2  visible, accepted                                               *)
(*   page p2 (sector s2)                                                   *)
(*     r3  visible, accepted                                               *)
(*     r4  deleted before the snapshot (vacuum may remove it); its index   *)
(*         entry is still there                                            *)
(*     r6  visible, accepted by the data filter, but outside the key       *)
(*         range: it has no index entry in the scanned leaves              *)
(*     r7  visible, rejected by the data filter; its slot number is beyond *)
(*         the bitmap's width, so marking it marks the whole page          *)
(*   page p3 (sector s2)                                                   *)
(*     r8  deleted before the snapshot, its index entry still there; the   *)
(*         only row of its page: once vacuum removed it, the page may be   *)
(*         deallocated while the scan runs                                 *)
(*   page p9 (sector s9, not in the sector list)                           *)
(*     r5  inserted after the sector list was taken; invisible to the      *)
(*         snapshot, unless the sector list was taken before the snapshot  *)
(*         (the mutant)                                                    *)
(***************************************************************************)
Rows == {"r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8"}
Leaves == {"l1", "l2", "l3"}
ListedSectors == {"s1", "s2"}
ListedPages == {"p1", "p2", "p3"}
NoLeaf == "no_leaf"
NoSector == "no_sector"
NoRow == "no_row"
NoPage == "no_page"

EntriesOf(l) == IF l = "l1" THEN {"r1", "r2"} ELSE IF l = "l2" THEN {"r1", "r3", "r7"} ELSE {"r4", "r5", "r8"}
PageOf(r) == IF r \in {"r1", "r2"} THEN "p1" ELSE IF r = "r5" THEN "p9" ELSE IF r = "r8" THEN "p3" ELSE "p2"
SectorOf(r) == IF r \in {"r1", "r2"} THEN "s1" ELSE IF r = "r5" THEN "s9" ELSE "s2"
Wide == {"r7"}
IdxRows == {"r1", "r2", "r3", "r4", "r5", "r7", "r8"}
Vis == IF Mutant = "late_sector_list" THEN {"r1", "r2", "r3", "r5", "r6", "r7"} ELSE {"r1", "r2", "r3", "r6", "r7"}
DataOk == {"r1", "r2", "r3", "r4", "r5", "r6", "r8"}
\* The rows sharing a bitmap word with row r (one word per page here).
WordRows(r) == {q \in Rows : PageOf(q) = PageOf(r)}

\* The rows the scan must return.
Expected == (Vis \cap DataOk) \cap IdxRows

VARIABLES lossy,      \* fixed when the scan opens: the exact bitmap does not fit the bound, pages only
          leafTodo,   \* leaves not yet handed to an index worker
          leafOf,     \* [IdxWorkers -> Leaves \cup {NoLeaf}]: the leaf a worker is reading
          pend,       \* [IdxWorkers -> SUBSET Rows]: entries of that leaf not yet examined
          bm,         \* the shared bitmap's row bits
          pagebm,     \* the shared bitmap's whole-page bits
          ldr, ld,    \* mutant only: the row a worker is marking and the word it loaded
          idone,      \* [IdxWorkers -> BOOLEAN]: the worker has finished the index phase
          secTodo,    \* listed sectors not yet handed to a heap worker
          secOf,      \* [HeapWorkers -> ListedSectors \cup {NoSector}]: the sector a heap worker scans
          work,       \* [HeapWorkers -> [Rows -> Nat]]: rows of that sector still to look at
          held,       \* [HeapWorkers -> ListedPages \cup {NoPage}]: the marked page a worker keeps fixed while it reads its rows
          freed,      \* listed pages vacuum emptied and deallocated since the sector list was taken
          out,        \* [Rows -> Nat]: times a row was returned
          gone,       \* rows vacuum removed
          aborted,    \* an error or interrupt ended the scan
          errs,
          dropped,    \* ghost: an OID outside the sector list was dropped
          skipped,    \* ghost: a marked row was skipped at the heap (removed or invisible)
          rechecked   \* ghost: the index condition rejected a row of a whole-page mark

vars == <<freed, held, lossy, leafTodo, leafOf, pend, bm, pagebm, ldr, ld, idone, secTodo, secOf, work, out, gone, aborted, errs,
          dropped, skipped, rechecked>>

TypeOK ==
  /\ lossy \in BOOLEAN
  /\ leafTodo \in SUBSET Leaves
  /\ leafOf \in [IdxWorkers -> Leaves \cup {NoLeaf}]
  /\ pend \in [IdxWorkers -> SUBSET Rows]
  /\ bm \in SUBSET Rows
  /\ pagebm \in SUBSET ListedPages
  /\ ldr \in [IdxWorkers -> Rows \cup {NoRow}]
  /\ ld \in [IdxWorkers -> SUBSET Rows]
  /\ idone \in [IdxWorkers -> BOOLEAN]
  /\ secTodo \in SUBSET ListedSectors
  /\ secOf \in [HeapWorkers -> ListedSectors \cup {NoSector}]
  /\ work \in [HeapWorkers -> [Rows -> 0..4]]
  /\ held \in [HeapWorkers -> ListedPages \cup {NoPage}]
  /\ freed \in SUBSET ListedPages
  /\ \A h \in HeapWorkers : \A r \in Rows : work[h][r] <= 2
  /\ out \in [Rows -> 0..8]
  /\ gone \in SUBSET Rows
  /\ aborted \in BOOLEAN
  /\ errs \in Int /\ errs >= 0 /\ errs <= MaxErrors
  /\ dropped \in BOOLEAN /\ skipped \in BOOLEAN /\ rechecked \in BOOLEAN

Init ==
  /\ lossy \in BOOLEAN
  /\ leafTodo = Leaves
  /\ leafOf = [w \in IdxWorkers |-> NoLeaf]
  /\ pend = [w \in IdxWorkers |-> {}]
  /\ bm = {}
  /\ pagebm = {}
  /\ ldr = [w \in IdxWorkers |-> NoRow]
  /\ ld = [w \in IdxWorkers |-> {}]
  /\ idone = [w \in IdxWorkers |-> FALSE]
  /\ secTodo = ListedSectors
  /\ secOf = [h \in HeapWorkers |-> NoSector]
  /\ work = [h \in HeapWorkers |-> [r \in Rows |-> 0]]
  /\ held = [h \in HeapWorkers |-> NoPage]
  /\ freed = {}
  /\ out = [r \in Rows |-> 0]
  /\ gone = {}
  /\ aborted = FALSE
  /\ errs = 0
  /\ dropped = FALSE /\ skipped = FALSE /\ rechecked = FALSE

(***************************************************************************)
(* Index phase                                                             *)
(***************************************************************************)

\* The leaf dispatcher hands a leaf to one worker.
TakeLeafL(w, l) ==
  /\ ~aborted /\ ~idone[w] /\ leafOf[w] = NoLeaf
  /\ l \in leafTodo
  /\ leafTodo' = leafTodo \ {l}
  /\ leafOf' = [leafOf EXCEPT ![w] = l]
  /\ pend' = [pend EXCEPT ![w] = EntriesOf(l)]
  /\ UNCHANGED <<freed, held, lossy, bm, pagebm, ldr, ld, idone, secTodo, secOf, work, out, gone, aborted, errs, dropped, skipped,
                 rechecked>>

TakeLeaf(w) == \E l \in leafTodo : TakeLeafL(w, l)

\* One entry of the leaf.  An OID whose page is in a listed sector is recorded in the shared bitmap by one
\* atomic OR: its row bit, or its page bit when the bitmap holds pages only or the slot is beyond the width.
\* Any other OID is dropped (D30).  The leaf may already tell that a row is invisible, then it is not recorded.
MarkRow(w, r) ==
  /\ ~aborted
  /\ r \in pend[w]
  /\ pend' = [pend EXCEPT ![w] = @ \ {r}]
  /\ \/ /\ SectorOf(r) \in ListedSectors /\ (lossy \/ r \in Wide)
        /\ pagebm' = pagebm \cup {PageOf(r)}
        /\ UNCHANGED <<bm, dropped>>
     \/ /\ SectorOf(r) \in ListedSectors /\ ~lossy /\ r \notin Wide /\ Mutant # "nonatomic_or"
        /\ bm' = bm \cup {r}
        /\ UNCHANGED <<pagebm, dropped>>
     \/ /\ SectorOf(r) \notin ListedSectors
        /\ dropped' = TRUE
        /\ UNCHANGED <<bm, pagebm>>
     \/ /\ r \notin Vis
        /\ UNCHANGED <<bm, pagebm, dropped>>
  /\ UNCHANGED <<freed, held, lossy, leafTodo, leafOf, ldr, ld, idone, secTodo, secOf, work, out, gone, aborted, errs, skipped,
                 rechecked>>

Mark(w) == \E r \in pend[w] : MarkRow(w, r)

\* Mutant only: the OR as a load and a store.
MarkLoad(w) ==
  /\ ~aborted /\ Mutant = "nonatomic_or" /\ ldr[w] = NoRow
  /\ \E r \in pend[w] :
       /\ SectorOf(r) \in ListedSectors /\ ~lossy /\ r \notin Wide
       /\ pend' = [pend EXCEPT ![w] = @ \ {r}]
       /\ ldr' = [ldr EXCEPT ![w] = r]
       /\ ld' = [ld EXCEPT ![w] = bm \cap WordRows(r)]
  /\ UNCHANGED <<freed, held, lossy, leafTodo, leafOf, bm, pagebm, idone, secTodo, secOf, work, out, gone, aborted, errs, dropped,
                 skipped, rechecked>>

MarkStore(w) ==
  /\ ~aborted /\ ldr[w] # NoRow
  /\ bm' = (bm \ WordRows(ldr[w])) \cup ld[w] \cup {ldr[w]}
  /\ ldr' = [ldr EXCEPT ![w] = NoRow]
  /\ ld' = [ld EXCEPT ![w] = {}]
  /\ UNCHANGED <<freed, held, lossy, leafTodo, leafOf, pend, pagebm, idone, secTodo, secOf, work, out, gone, aborted, errs, dropped,
                 skipped, rechecked>>

EndLeaf(w) ==
  /\ ~aborted /\ leafOf[w] # NoLeaf /\ pend[w] = {} /\ ldr[w] = NoRow
  /\ leafOf' = [leafOf EXCEPT ![w] = NoLeaf]
  /\ UNCHANGED <<freed, held, lossy, leafTodo, pend, bm, pagebm, ldr, ld, idone, secTodo, secOf, work, out, gone, aborted, errs,
                 dropped, skipped, rechecked>>

\* No leaf is left: the worker's part of the index phase is over.
IdxFinish(w) ==
  /\ ~aborted /\ ~idone[w] /\ leafOf[w] = NoLeaf /\ leafTodo = {}
  /\ idone' = [idone EXCEPT ![w] = TRUE]
  /\ UNCHANGED <<freed, held, lossy, leafTodo, leafOf, pend, bm, pagebm, ldr, ld, secTodo, secOf, work, out, gone, aborted, errs,
                 dropped, skipped, rechecked>>

(***************************************************************************)
(* Heap phase                                                              *)
(***************************************************************************)

\* How often the heap worker of sector s looks at row r: every row of a page marked as a whole, the marked
\* rows of the other pages.
ExamCount(s, r) ==
  IF SectorOf(r) # s THEN 0
  ELSE IF PageOf(r) \in pagebm THEN (IF Mutant = "both_paths" /\ r \in bm THEN 2 ELSE 1)
  ELSE IF r \in bm THEN 1 ELSE 0

\* A heap worker takes a sector.  Not before every index worker has finished: until then the bitmap may
\* still grow (D33).
TakeSectorS(h, s) ==
  /\ ~aborted /\ secOf[h] = NoSector
  /\ (\A w \in IdxWorkers : idone[w]) \/ Mutant = "no_barrier"
  /\ s \in secTodo
  /\ secTodo' = IF Mutant = "sector_twice" THEN secTodo ELSE secTodo \ {s}
  /\ secOf' = [secOf EXCEPT ![h] = s]
  /\ work' = [work EXCEPT ![h] = [r \in Rows |-> ExamCount(s, r)]]
  /\ UNCHANGED <<freed, held, lossy, leafTodo, leafOf, pend, bm, pagebm, ldr, ld, idone, out, gone, aborted, errs, dropped, skipped,
                 rechecked>>

TakeSector(h) == \E s \in secTodo : TakeSectorS(h, s)

\* One row: a row that is gone or that the snapshot does not see is skipped; a row of a whole-page mark must
\* pass the index condition again; the others go through the data filter.
LookupRow(h, r) ==
  /\ ~aborted
  /\ work[h][r] > 0
  /\ held[h] = PageOf(r)
  /\ work' = [work EXCEPT ![h][r] = @ - 1]
  /\ IF (r \in gone \/ r \notin Vis) /\ Mutant # "no_heap_visibility"
       THEN skipped' = TRUE /\ UNCHANGED <<out, rechecked>>
       ELSE IF PageOf(r) \in pagebm /\ r \notin IdxRows /\ Mutant # "no_recheck"
              THEN rechecked' = TRUE /\ UNCHANGED <<out, skipped>>
              ELSE /\ out' = IF r \in DataOk THEN [out EXCEPT ![r] = @ + 1] ELSE out
                   /\ UNCHANGED <<skipped, rechecked>>
  /\ UNCHANGED <<freed, held, lossy, leafTodo, leafOf, pend, bm, pagebm, ldr, ld, idone, secTodo, secOf, gone, aborted, errs, dropped>>

Lookup(h) == \E r \in Rows : LookupRow(h, r)

\* A marked page is fixed once, before its rows are read, and kept until the last of them: a row lookup fixes
\* its page as one that must exist (heap_prepare_object_page), and heap_next_1page walks the slots of the page
\* the scan cache holds.  The worker lets the page go itself when the rows are exhausted.
MarkedPages == pagebm \cup {PageOf(r) : r \in bm}
SectorOfPage(p) == IF p = "p1" THEN "s1" ELSE "s2"
FixPageP(h, p) ==
  /\ ~aborted /\ secOf[h] # NoSector
  /\ held[h] = NoPage \/ Mutant = "no_release"
  /\ p \in MarkedPages /\ SectorOfPage(p) = secOf[h] /\ held[h] # p
  /\ p \notin freed \/ Mutant = "fix_freed"
  /\ \E r \in Rows : PageOf(r) = p /\ work[h][r] > 0
  /\ held' = [held EXCEPT ![h] = p]
  /\ UNCHANGED <<freed, lossy, leafTodo, leafOf, pend, bm, pagebm, ldr, ld, idone, secTodo, secOf, work, out, gone, aborted, errs,
                 dropped, skipped, rechecked>>

FixPage(h) == \E p \in ListedPages : FixPageP(h, p)

\* A marked page that is gone when the worker comes to fix it: every row it held was removed by vacuum, so no
\* row of it is visible to the snapshot, and the worker passes it.
SkipFreedPageP(h, p) ==
  /\ ~aborted /\ secOf[h] # NoSector /\ Mutant # "no_freed_skip"
  /\ p \in MarkedPages /\ p \in freed /\ SectorOfPage(p) = secOf[h]
  /\ \E r \in Rows : PageOf(r) = p /\ work[h][r] > 0
  /\ work' = [work EXCEPT ![h] = [r \in Rows |-> IF PageOf(r) = p THEN 0 ELSE work[h][r]]]
  /\ skipped' = TRUE
  /\ UNCHANGED <<freed, held, lossy, leafTodo, leafOf, pend, bm, pagebm, ldr, ld, idone, secTodo, secOf, out, gone, aborted, errs,
                 dropped, rechecked>>

SkipFreedPage(h) == \E p \in ListedPages : SkipFreedPageP(h, p)

ReleasePage(h) ==
  /\ ~aborted /\ held[h] # NoPage /\ Mutant # "no_release"
  /\ \A r \in Rows : PageOf(r) = held[h] => work[h][r] = 0
  /\ held' = [held EXCEPT ![h] = NoPage]
  /\ UNCHANGED <<freed, lossy, leafTodo, leafOf, pend, bm, pagebm, ldr, ld, idone, secTodo, secOf, work, out, gone, aborted, errs,
                 dropped, skipped, rechecked>>

EndSector(h) ==
  /\ ~aborted /\ secOf[h] # NoSector
  /\ \A r \in Rows : work[h][r] = 0
  /\ held[h] = NoPage \/ Mutant = "no_release"
  /\ secOf' = [secOf EXCEPT ![h] = NoSector]
  /\ UNCHANGED <<freed, held, lossy, leafTodo, leafOf, pend, bm, pagebm, ldr, ld, idone, secTodo, work, out, gone, aborted, errs,
                 dropped, skipped, rechecked>>

(***************************************************************************)
(* Environment                                                             *)
(***************************************************************************)

\* Vacuum removes a row no snapshot sees any more; its index entry may still be there.
VacuumRow(r) ==
  /\ r \in Rows \ (Vis \cup gone)
  /\ gone' = gone \cup {r}
  /\ UNCHANGED <<freed, held, lossy, leafTodo, leafOf, pend, bm, pagebm, ldr, ld, idone, secTodo, secOf, work, out, aborted, errs,
                 dropped, skipped, rechecked>>

Vacuum == \E r \in Rows : VacuumRow(r)

\* Vacuum deallocates a page it emptied.  Not a page a scan holds fixed: the deallocation takes the page's latch.
FreePageP(p) ==
  /\ p \in ListedPages \ freed
  /\ \A r \in Rows : PageOf(r) = p => r \in gone
  /\ \A h \in HeapWorkers : held[h] # p
  /\ freed' = freed \cup {p}
  /\ UNCHANGED <<held, lossy, leafTodo, leafOf, pend, bm, pagebm, ldr, ld, idone, secTodo, secOf, work, out, gone, aborted, errs,
                 dropped, skipped, rechecked>>

FreePage == \E p \in ListedPages : FreePageP(p)

\* An error or interrupt on any worker ends the scan: every worker stops, the bitmap is released.
Abort ==
  /\ ~aborted /\ errs < MaxErrors
  /\ aborted' = TRUE
  /\ errs' = errs + 1
  /\ leafOf' = [w \in IdxWorkers |-> NoLeaf]
  /\ pend' = [w \in IdxWorkers |-> {}]
  /\ bm' = {}
  /\ pagebm' = {}
  /\ ldr' = [w \in IdxWorkers |-> NoRow]
  /\ ld' = [w \in IdxWorkers |-> {}]
  /\ secOf' = [h \in HeapWorkers |-> NoSector]
  /\ work' = [h \in HeapWorkers |-> [r \in Rows |-> 0]]
  \* the worker's cleanup lets go of a page it was reading as a whole
  /\ held' = IF Mutant = "no_release" THEN held ELSE [h \in HeapWorkers |-> NoPage]
  /\ UNCHANGED <<freed, lossy, leafTodo, idone, secTodo, out, gone, dropped, skipped, rechecked>>

Finished ==
  /\ ~aborted
  /\ \A w \in IdxWorkers : idone[w]
  /\ secTodo = {}
  /\ \A h \in HeapWorkers : secOf[h] = NoSector

Terminated == (Finished \/ aborted) /\ UNCHANGED vars

IdxStep(w) == TakeLeaf(w) \/ Mark(w) \/ MarkLoad(w) \/ MarkStore(w) \/ EndLeaf(w) \/ IdxFinish(w)
HeapStep(h) == TakeSector(h) \/ FixPage(h) \/ SkipFreedPage(h) \/ Lookup(h) \/ ReleasePage(h) \/ EndSector(h)

Next ==
  \/ \E w \in IdxWorkers : IdxStep(w)
  \/ \E h \in HeapWorkers : HeapStep(h)
  \/ Vacuum \/ FreePage \/ Abort \/ Terminated

Fairness ==
  /\ \A w \in IdxWorkers : WF_vars(IdxStep(w))
  /\ \A h \in HeapWorkers : WF_vars(HeapStep(h))

Spec == Init /\ [][Next]_vars /\ Fairness

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)

\* C6, safety half: no row is returned twice and no row that must not be returned is returned.
NoExtraRow == \A r \in Rows : out[r] <= (IF r \in Expected THEN 1 ELSE 0)

\* C6, completeness half: a scan that ran to its end returned every row it must.
AllRowsReturned == Finished => \A r \in Expected : out[r] = 1

\* The scan ends (or is aborted).
Ends == <>(Finished \/ aborted)

\* C4 for the whole-range batch: a scan that ended, finished or stopped, holds no heap page.
NoPageHeld == (Finished \/ aborted) => \A h \in HeapWorkers : held[h] = NoPage

\* Witnesses
NotMixedPage == ~("p2" \in pagebm /\ "r3" \in bm)
NotRechecked == ~rechecked
NotDropped == ~dropped
NotSkipped == ~skipped
NotFinished == ~Finished
NotPagesOnlyFinished == ~(lossy /\ Finished)
NotPageHeld == \A h \in HeapWorkers : held[h] = NoPage
\* No worker reads a page vacuum deallocated.
NoFreedPageHeld == \A h \in HeapWorkers : held[h] \notin freed
NotFinishedPastFreedPage == ~(Finished /\ "p3" \in freed /\ "p3" \in pagebm)

(***************************************************************************)
(* Inductive invariant                                                     *)
(***************************************************************************)
\* A row bit is set only for an index entry of a listed sector whose slot the bitmap holds; a page bit only
\* for a listed page.  The load-and-store variables are the mutant's.
MarksShape ==
  /\ \A r \in bm : SectorOf(r) \in ListedSectors /\ r \notin Wide /\ r \in IdxRows
  /\ lossy => bm = {}
  /\ \A w \in IdxWorkers : ldr[w] = NoRow /\ ld[w] = {}
Covered(r) == r \in bm \/ PageOf(r) \in pagebm
\* An index worker reads a leaf exactly while it has entries pending or is between its last entry and EndLeaf.
LeafShape ==
  /\ \A w \in IdxWorkers : (leafOf[w] = NoLeaf => pend[w] = {}) /\ (idone[w] => leafOf[w] = NoLeaf)
  /\ \A w \in IdxWorkers : leafOf[w] # NoLeaf => (leafOf[w] \notin leafTodo /\ pend[w] \subseteq EntriesOf(leafOf[w]))
\* The phase barrier: a heap worker has a sector, or a sector was handed out, only after the index phase.
Barrier == ((\E h \in HeapWorkers : secOf[h] # NoSector) \/ secTodo # ListedSectors) => \A w \in IdxWorkers : idone[w]
\* Once the index phase is over no leaf is left and nothing is pending: the bitmap is final.
IndexOver == (\A w \in IdxWorkers : idone[w]) => leafTodo = {}
\* Every visible row whose entry has been examined is marked, by its row bit or its page bit.
\* (Stated on the leaves: a leaf that is neither waiting nor being read has been examined.)
LeafDone(l) == l \notin leafTodo /\ \A w \in IdxWorkers : leafOf[w] # l
Examined(r, l) == r \in EntriesOf(l) /\ (LeafDone(l) \/ \E w \in IdxWorkers : leafOf[w] = l /\ r \notin pend[w])
VisibleMarked ==
  ~aborted => \A r \in Vis : \A l \in Leaves : Examined(r, l) => Covered(r)
\* A row is looked at in one place at a time, only in the sector it is on, and only when it is marked.
WorkShape ==
  /\ \A h \in HeapWorkers : secOf[h] = NoSector => \A r \in Rows : work[h][r] = 0
  /\ \A h \in HeapWorkers : \A r \in Rows :
       work[h][r] > 0 => (SectorOf(r) = secOf[h] /\ work[h][r] = 1 /\ Covered(r))
  /\ \A h1, h2 \in HeapWorkers : (h1 # h2 /\ secOf[h1] # NoSector) => secOf[h1] # secOf[h2]
  /\ \A h \in HeapWorkers : secOf[h] # NoSector => secOf[h] \notin secTodo
\* A row's fate: returned at most once; still to look at or already decided, never both.
RowOnce ==
  \A r \in Rows :
    /\ out[r] <= 1
    /\ out[r] = 1 => r \in Expected /\ SectorOf(r) \notin secTodo /\ \A h \in HeapWorkers : work[h][r] = 0
    /\ (r \in Expected /\ ~aborted) =>
         \A h \in HeapWorkers : secOf[h] = SectorOf(r) => work[h][r] + out[r] = 1
    /\ (r \in Expected /\ ~aborted /\ SectorOf(r) \notin secTodo /\ \A h \in HeapWorkers : secOf[h] # SectorOf(r)
        /\ \A w \in IdxWorkers : idone[w])
         => out[r] = 1
\* Visible rows are on listed sectors (D30's assumption: the snapshot is taken before the sector list).
VisibleListed == \A r \in Vis : SectorOf(r) \in ListedSectors
\* Vacuum removes only what no snapshot sees.
GoneInvisible == gone \cap Vis = {}
AbortShape == aborted => (\A h \in HeapWorkers : secOf[h] = NoSector) /\ (\A w \in IdxWorkers : leafOf[w] = NoLeaf)

\* A held page is a marked page of the sector the worker scans.
HeldShape ==
  \A h \in HeapWorkers :
    held[h] # NoPage => (secOf[h] # NoSector /\ SectorOfPage(held[h]) = secOf[h] /\ held[h] \in MarkedPages)

\* A freed page holds only rows vacuum removed, and nobody holds it fixed.
FreedShape ==
  /\ \A p \in freed : \A r \in Rows : PageOf(r) = p => r \in gone
  /\ NoFreedPageHeld

IndInv ==
  /\ TypeOK
  /\ MarksShape
  /\ LeafShape
  /\ Barrier
  /\ IndexOver
  /\ VisibleMarked
  /\ WorkShape
  /\ RowOnce
  /\ VisibleListed
  /\ AbortShape
  /\ GoneInvisible
  /\ NoExtraRow
  /\ AllRowsReturned
  /\ HeldShape
  /\ NoPageHeld
  /\ FreedShape
=============================================================================
