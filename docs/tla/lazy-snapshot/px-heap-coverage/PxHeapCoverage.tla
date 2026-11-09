--------------------------- MODULE PxHeapCoverage ---------------------------
(* The pages a parallel heap scan collects once at open, against the snapshot
   it reads through, other transactions, vacuum and the heap file's own table
   pages.

   input_handler_heap::init_on_main reads the heap file's partial and full
   sector tables once, under the file header's read latch
   (file_get_all_data_sectors), and keeps every allocated data page: the page
   bitmap. Its workers then fix each bitmap page (OLD_PAGE_MAYBE_DEALLOCATED)
   and read it through the statement's MVCC snapshot. Meanwhile:
   - inserts fill heap pages or allocate a free page of the file (file_alloc);
   - vacuum removes rows every live snapshot sees deleted, then deallocates an
     emptied heap page (heap_remove_page_on_vacuum -> file_dealloc);
   - the file manager allocates and frees its own table pages from the same
     sectors (file_perm_dealloc / file_table_append_full_sector_page ->
     file_perm_alloc (FILE_ALLOC_TABLE_PAGE)). A sector leaves the file only at
     file_destroy, which the scan's class lock excludes, so a page never moves
     to another file.
   A page is "free", "heap" (an allocated heap data page) or "ftab" (a file
   table page). Allocation takes any free page: the code takes the first free
   page of the first partial sector, which this over-approximates.

   Decisions are constants:
     SnapshotAt  "worker_start"  READ COMMITTED as develop: the first worker builds it
                 "collect"       the leader builds it right before the collect (PR #8438)
                 "query_start"   REPEATABLE READ: qexec_execute_query built it
     PtypeCheck  a worker skips a bitmap page that is no longer a heap page, as it skips a
                 deallocated one (the fix in PR #8438: pgbuf_ordered_fix returns
                 ER_PB_BAD_PAGEID for it under the page latch). Develop has none: pgbuf_ordered_fix
                 (OLD_PAGE_MAYBE_DEALLOCATED) fixes the reused table page, finds no heap
                 group and hits assert_release (false) (page_buffer.c:12570): optdebug
                 aborts the server, release fails the query with ER_FAILED_ASSERTION.
     Mutant      "none" | "vacuum_ignores_snapshot" | "dealloc_nonempty"
                 | "collect_misses_page" | "no_dealloc_skip" | "collect_without_build" *)
EXTENDS Naturals, FiniteSets

CONSTANTS Workers, NPages, NInit, NNew, VacuumRounds, FtabRounds,
          SnapshotAt, PtypeCheck, Mutant

\* apalache-type: Workers Set(Str)
\* apalache-type: NPages Int
\* apalache-type: NInit Int
\* apalache-type: NNew Int
\* apalache-type: VacuumRounds Int
\* apalache-type: FtabRounds Int
\* apalache-type: SnapshotAt Str
\* apalache-type: PtypeCheck Bool
\* apalache-type: Mutant Str
\* apalache-type: state Int -> Str
\* apalache-type: home Int -> Int
\* apalache-type: insC Int -> Int
\* apalache-type: delC Int -> Int
\* apalache-type: gone Int -> Bool
\* apalache-type: readCnt Int -> Int
\* apalache-type: clock Int
\* apalache-type: snap Int
\* apalache-type: rounds Int
\* apalache-type: ftabs Int
\* apalache-type: qstarted Bool
\* apalache-type: lsnap Str
\* apalache-type: opened Bool
\* apalache-type: bitmap Set(Int)
\* apalache-type: owner Int -> Str
\* apalache-type: started Str -> Bool
\* apalache-type: left Str -> Set(Int)
\* apalache-type: done Bool
\* apalache-type: foreign Bool

ASSUME Assm ==
  /\ Workers # {}
  /\ NPages \in Nat \ {0} /\ NInit \in 1..NPages /\ NNew \in Nat
  /\ VacuumRounds \in Nat /\ FtabRounds \in Nat
  /\ SnapshotAt \in {"worker_start", "collect", "query_start"}
  /\ PtypeCheck \in BOOLEAN
  /\ Mutant \in {"none", "vacuum_ignores_snapshot", "dealloc_nonempty", "collect_misses_page", "no_dealloc_skip",
                 "collect_without_build"}

Pg == 1..NPages
Rows == 1..(NInit + NNew)          \* row r <= NInit starts on page r
IsInit(r) == r <= NInit
NoPage == 0
States == {"free", "heap", "ftab"}

VARIABLES state, home, insC, delC, gone, readCnt, clock, snap, rounds, ftabs,
          qstarted, lsnap, opened, bitmap, owner, started, left, done, foreign
vars == <<state, home, insC, delC, gone, readCnt, clock, snap, rounds, ftabs,
          qstarted, lsnap, opened, bitmap, owner, started, left, done, foreign>>
dataVars == <<state, home, insC, delC, gone, clock, rounds, ftabs>>
scanVars == <<qstarted, lsnap, opened, bitmap, owner, started, left, done, foreign>>

\* a row inserted by a transaction committed before t and not deleted by one
VisibleAt(r, t) == insC[r] > 0 /\ insC[r] < t /\ ~(delC[r] > 0 /\ delC[r] < t)
\* vacuum's threshold: a built snapshot of a running scan holds it back
\* (mvcctable::compute_oldest_visible_mvccid; docs/tla/lazy-snapshot/stmt C4)
OldestVisible == IF Mutant = "vacuum_ignores_snapshot" THEN clock
                 ELSE IF snap > 0 /\ ~done THEN snap ELSE clock
PageEmpty(p) == \A r \in Rows : home[r] = p => gone[r]
\* logtb_get_mvcc_snapshot: test-and-build under m_px_lock_mutex
Build == IF snap = 0 THEN clock ELSE snap

Init ==
  /\ state = [p \in Pg |-> IF p <= NInit THEN "heap" ELSE "free"]
  /\ home = [r \in Rows |-> IF IsInit(r) THEN r ELSE NoPage]
  /\ insC = [r \in Rows |-> IF IsInit(r) THEN 1 ELSE 0]
  /\ delC = [r \in Rows |-> 0]
  /\ gone = [r \in Rows |-> FALSE]
  /\ readCnt = [r \in Rows |-> 0]
  /\ clock = 2
  /\ snap = 0
  /\ rounds = VacuumRounds
  /\ ftabs = FtabRounds
  /\ qstarted = FALSE
  /\ lsnap = "idle"
  /\ opened = FALSE
  /\ bitmap = {}
  /\ owner = [p \in Pg |-> CHOOSE w \in Workers : TRUE]
  /\ started = [w \in Workers |-> FALSE]
  /\ left = [w \in Workers |-> {}]
  /\ done = FALSE
  /\ foreign = FALSE

\* ---- the scan ----
\* qexec_execute_query: logtb_get_mvcc_snapshot when isolation >= REPEATABLE READ
QueryStart ==
  /\ ~qstarted
  /\ qstarted' = TRUE
  /\ snap' = IF SnapshotAt = "query_start" THEN Build ELSE snap
  /\ UNCHANGED <<dataVars, readCnt, lsnap, opened, bitmap, owner, started, left, done, foreign>>

\* PR #8438: init_on_main calls logtb_get_mvcc_snapshot before file_get_all_data_sectors
LeaderSnap ==
  /\ qstarted /\ SnapshotAt = "collect" /\ lsnap = "idle" /\ Mutant # "collect_without_build"
  /\ lsnap' = "built"
  /\ snap' = Build
  /\ UNCHANGED <<dataVars, readCnt, qstarted, opened, bitmap, owner, started, left, done, foreign>>

\* file_get_all_data_sectors under the file header's read latch, then split among workers
Collect ==
  /\ qstarted /\ ~opened
  /\ SnapshotAt = "collect" => lsnap = "built"
  /\ opened' = TRUE
  /\ IF Mutant = "collect_misses_page"
       THEN \E b \in SUBSET {p \in Pg : state[p] = "heap"} : bitmap' = b
       ELSE bitmap' = {p \in Pg : state[p] = "heap"}
  /\ \E o \in [Pg -> Workers] : owner' = o
  /\ UNCHANGED <<dataVars, readCnt, snap, qstarted, lsnap, started, left, done, foreign>>

\* px_scan_task: scan_start_scan -> logtb_get_mvcc_snapshot (builds it when none exists)
Start(w) ==
  /\ opened /\ ~started[w]
  /\ started' = [started EXCEPT ![w] = TRUE]
  /\ left' = [left EXCEPT ![w] = {p \in bitmap : owner[p] = w}]
  /\ snap' = Build
  /\ UNCHANGED <<dataVars, readCnt, qstarted, lsnap, opened, bitmap, owner, done, foreign>>

\* get_next_vpid_with_fix: pgbuf_ordered_fix (OLD_PAGE_MAYBE_DEALLOCATED) under a read latch,
\* then heap_next_1page over the page with the snapshot's visibility check
ReadPage(w, p) ==
  /\ started[w] /\ p \in left[w]
  /\ left' = [left EXCEPT ![w] = @ \ {p}]
  /\ IF state[p] = "heap"
       THEN /\ readCnt' = [r \in Rows |-> IF home[r] = p /\ ~gone[r] /\ VisibleAt(r, snap)
                                          THEN readCnt[r] + 1 ELSE readCnt[r]]
            /\ foreign' = foreign
       ELSE IF state[p] = "free"
       THEN /\ readCnt' = readCnt                  \* ER_PB_BAD_PAGEID: skipped
            /\ foreign' = (foreign \/ Mutant = "no_dealloc_skip")
       ELSE /\ readCnt' = readCnt                  \* a file table page: skipped (fix) or the scan fails
            /\ foreign' = (foreign \/ ~PtypeCheck)
  /\ UNCHANGED <<dataVars, snap, qstarted, lsnap, opened, bitmap, owner, started, done>>

\* the leader's join of its workers
Finish ==
  /\ opened /\ ~done
  /\ \A w \in Workers : started[w] /\ left[w] = {}
  /\ done' = TRUE
  /\ UNCHANGED <<dataVars, readCnt, snap, qstarted, lsnap, opened, bitmap, owner, started, left, foreign>>

\* ---- other transactions, vacuum, the file manager ----
\* heap_insert and its commit: into a heap page, or into a free page file_alloc gives the heap
Insert(r, p) ==
  /\ ~IsInit(r) /\ insC[r] = 0 /\ state[p] \in {"heap", "free"}
  /\ state' = [state EXCEPT ![p] = "heap"]
  /\ home' = [home EXCEPT ![r] = p]
  /\ insC' = [insC EXCEPT ![r] = clock]
  /\ clock' = clock + 1
  /\ UNCHANGED <<delC, gone, readCnt, snap, rounds, ftabs, scanVars>>

\* heap_delete and its commit
Delete(r) ==
  /\ insC[r] > 0 /\ delC[r] = 0
  /\ delC' = [delC EXCEPT ![r] = clock]
  /\ clock' = clock + 1
  /\ UNCHANGED <<state, home, insC, gone, readCnt, snap, rounds, ftabs, scanVars>>

\* vacuum_heap_page under the page's write latch
VacuumRows(p) ==
  /\ rounds > 0 /\ state[p] = "heap"
  /\ rounds' = rounds - 1
  /\ gone' = [r \in Rows |-> gone[r] \/ (home[r] = p /\ delC[r] > 0 /\ delC[r] < OldestVisible)]
  /\ UNCHANGED <<state, home, insC, delC, readCnt, clock, snap, ftabs, scanVars>>

\* heap_remove_page_on_vacuum: re-checks the page is empty under its write latch, then file_dealloc
VacuumPage(p) ==
  /\ rounds > 0 /\ state[p] = "heap"
  /\ PageEmpty(p) \/ Mutant = "dealloc_nonempty"
  /\ rounds' = rounds - 1
  /\ state' = [state EXCEPT ![p] = "free"]
  /\ UNCHANGED <<home, insC, delC, gone, readCnt, clock, snap, ftabs, scanVars>>

\* file_perm_alloc (FILE_ALLOC_TABLE_PAGE): the partial or full table grows into a free page
FtabAlloc(p) ==
  /\ ftabs > 0 /\ state[p] = "free"
  /\ ftabs' = ftabs - 1
  /\ state' = [state EXCEPT ![p] = "ftab"]
  /\ UNCHANGED <<home, insC, delC, gone, readCnt, clock, snap, rounds, scanVars>>

\* file_perm_dealloc of a merged table page
FtabFree(p) ==
  /\ state[p] = "ftab"
  /\ state' = [state EXCEPT ![p] = "free"]
  /\ UNCHANGED <<home, insC, delC, gone, readCnt, clock, snap, rounds, ftabs, scanVars>>

Terminated == done /\ UNCHANGED vars

ScanStep ==
  \/ QueryStart \/ LeaderSnap \/ Collect \/ Finish
  \/ \E w \in Workers : Start(w) \/ \E p \in Pg : ReadPage(w, p)

Next ==
  \/ Terminated
  \/ ScanStep
  \/ \E r \in Rows, p \in Pg : Insert(r, p)
  \/ \E r \in Rows : Delete(r)
  \/ \E p \in Pg : VacuumRows(p) \/ VacuumPage(p) \/ FtabAlloc(p) \/ FtabFree(p)

Spec == Init /\ [][Next]_vars
FairSpec == Spec /\ WF_vars(ScanStep)

\* ---- properties ----
BoolOK ==
  /\ gone \in [Rows -> BOOLEAN] /\ qstarted \in BOOLEAN /\ opened \in BOOLEAN
  /\ started \in [Workers -> BOOLEAN] /\ done \in BOOLEAN /\ foreign \in BOOLEAN
NatOK ==
  /\ home \in [Rows -> 0..NPages]
  /\ insC \in [Rows -> Nat] /\ delC \in [Rows -> Nat] /\ readCnt \in [Rows -> Nat]
  /\ clock \in Nat /\ snap \in Nat /\ rounds \in Nat /\ ftabs \in Nat
SetOK ==
  /\ state \in [Pg -> States] /\ lsnap \in {"idle", "built"}
  /\ bitmap \in SUBSET Pg /\ owner \in [Pg -> Workers]
  /\ left \in [Workers -> SUBSET Pg]
TypeOK == BoolOK /\ NatOK /\ SetOK

\* C1: once the scan has both its bitmap and its snapshot, the bitmap holds the page of
\* every row the snapshot sees.
Coverage == opened /\ snap > 0 => \A r \in Rows : VisibleAt(r, snap) => home[r] \in bitmap
\* C2: while the scan runs, no row its snapshot sees is removed, and its page stays an
\* allocated heap page (not deallocated, not reused as a table page).
NoLoss == snap > 0 /\ ~done => \A r \in Rows : VisibleAt(r, snap) => ~gone[r] /\ state[home[r]] = "heap"
\* C3: every bitmap page a worker fixes is a heap page of its heap or a deallocated page
\* it skips; never a page the file reused for something else.
HeapOnly == ~foreign
\* C4: the scan returns exactly the rows the snapshot sees, each once.
SameAsSnapshot == done => \A r \in Rows : readCnt[r] = IF VisibleAt(r, snap) THEN 1 ELSE 0
\* C5: the scan finishes.
ScanFinishes == <>done

\* ---- inductive invariant of the fix (snapshot before the collect, ptype check) ----
R_fix == SnapshotAt # "worker_start" /\ PtypeCheck /\ Mutant = "none"
R_snap == clock > 0 /\ snap <= clock /\ (opened => snap > 0)
R_q == ~qstarted => snap = 0 /\ ~opened /\ lsnap = "idle"
R_qs == qstarted /\ SnapshotAt = "query_start" => snap > 0
R_lsnap == lsnap = "built" => snap > 0
R_clock == \A r \in Rows : insC[r] < clock /\ delC[r] < clock
R_order == \A r \in Rows : delC[r] > 0 => insC[r] > 0 /\ insC[r] < delC[r]
R_home == \A r \in Rows : (insC[r] > 0) = (home[r] # NoPage)
R_init == \A r \in Rows : IsInit(r) => insC[r] = 1 /\ home[r] = r
R_gone == \A r \in Rows : gone[r] => delC[r] > 0
R_alloc == \A r \in Rows : home[r] # NoPage /\ ~gone[r] => state[home[r]] = "heap"
R_vis == \A r \in Rows : VisibleAt(r, snap) /\ ~done => ~gone[r]
R_open == ~opened => bitmap = {} /\ ~done
R_start == \A w \in Workers : (~opened => ~started[w]) /\ (~started[w] => left[w] = {})
R_left == \A w \in Workers : left[w] \subseteq {p \in bitmap : owner[p] = w}
R_bitmap == \A r \in Rows : opened /\ VisibleAt(r, snap) => home[r] \in bitmap
R_count == \A r \in Rows : readCnt[r] =
             IF opened /\ VisibleAt(r, snap) /\ started[owner[home[r]]] /\ home[r] \notin left[owner[home[r]]]
             THEN 1 ELSE 0
R_done == done => \A w \in Workers : started[w] /\ left[w] = {}
R_foreign == ~foreign

IndInv == TypeOK /\ R_fix /\ R_snap /\ R_q /\ R_qs /\ R_lsnap /\ R_clock /\ R_order /\ R_home /\ R_init
          /\ R_gone /\ R_alloc /\ R_vis /\ R_open /\ R_start /\ R_left /\ R_bitmap /\ R_count
          /\ R_done /\ R_foreign

\* ---- witnesses ----
\* a bitmap page vacuum deallocated is now a file table page while the scan runs
NotFtabReuse == ~(opened /\ ~done /\ \E p \in bitmap : state[p] = "ftab")
\* vacuum deallocated a bitmap page while the scan runs
NotDeallocDuringScan == ~(opened /\ ~done /\ \E p \in bitmap : state[p] = "free")
\* a committed row lives on a page allocated after the collect
NotRowOnNewPage == ~(opened /\ \E r \in Rows : home[r] # NoPage /\ home[r] \notin bitmap /\ insC[r] > 0)
\* the scan finished having returned a row
NotReadRow == ~(done /\ \E r \in Rows : readCnt[r] = 1)

\* Apalache: the worker set fixed, page and row counts fixed, budgets open
CInit ==
  /\ Workers = {"w1", "w2"} /\ NPages = 3 /\ NInit = 2 /\ NNew = 1
  /\ VacuumRounds \in Nat /\ FtabRounds \in Nat
  /\ SnapshotAt = "collect" /\ PtypeCheck = TRUE /\ Mutant = "none"
=============================================================================
