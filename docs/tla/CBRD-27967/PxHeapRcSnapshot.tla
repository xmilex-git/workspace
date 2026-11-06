--------------------------- MODULE PxHeapRcSnapshot ---------------------------
(* CBRD-27967 fix design: the statement's MVCC snapshot and the page bitmaps of
   its parallel heap scans.

   A statement runs one or more parallel heap scans (a partition each, or two
   tables, or scans inside subqueries that px_query workers run at the same
   time). Each scan collects its heap's page bitmap at open and hands every
   bitmap page to one of its workers. All scans of the statement share one
   snapshot (tdes->mvccinfo.snapshot): it is built once, by whichever thread
   calls logtb_get_mvcc_snapshot first, and every reader looks through the same
   pointer.

   Open decisions are constants:
     SnapshotAt  where the snapshot is built before a scan reads
                 "worker_start"  the first worker's scan_start_scan (the code, H1)
                 "collect"       the leader, at open, before the bitmap is collected
                 "query_start"   qexec_execute_query, for every isolation level
     LeaderLock  the leader's build at open is one test-and-build step under
                 m_px_lock_mutex (TRUE) or a test, then a build (FALSE)
     OtherPx     another parallel operator's worker of the same statement may
                 build the snapshot at any time (under the mutex)
     Mutant      "none" | "collect_without_build": the leader requires a valid
                 snapshot before collecting but does not build one
   Environment:
     Nested      an SP in the statement runs SQL from the client, which
                 invalidates the statement's snapshot (READ COMMITTED,
                 network_sr.c:924) for the next builder to rebuild; existing
                 behavior the claims leave out of scope *)
EXTENDS Naturals, FiniteSets

CONSTANTS Scans, Workers, NPages, NInit, NNew, VacuumRounds,
          Isolation, SnapshotAt, LeaderLock, OtherPx, Mutant, Nested

\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: Scans Set(Str)
\* apalache-type: Workers Set(Str)
\* apalache-type: NPages Int
\* apalache-type: NInit Int
\* apalache-type: NNew Int
\* apalache-type: VacuumRounds Int
\* apalache-type: Isolation Str
\* apalache-type: SnapshotAt Str
\* apalache-type: LeaderLock Bool
\* apalache-type: OtherPx Bool
\* apalache-type: Mutant Str
\* apalache-type: Nested Bool
\* apalache-type: alloc <<Str, Int>> -> Bool
\* apalache-type: home <<Str, Int>> -> Int
\* apalache-type: insC <<Str, Int>> -> Int
\* apalache-type: delC <<Str, Int>> -> Int
\* apalache-type: gone <<Str, Int>> -> Bool
\* apalache-type: readCnt <<Str, Int>> -> Int
\* apalache-type: clock Int
\* apalache-type: snap Int
\* apalache-type: rounds Int
\* apalache-type: qstarted Bool
\* apalache-type: otherDone Bool
\* apalache-type: lsnap Str -> Str
\* apalache-type: opened Str -> Bool
\* apalache-type: bitmap Str -> Set(Int)
\* apalache-type: owner Str -> (Int -> Str)
\* apalache-type: started Str -> (Str -> Bool)
\* apalache-type: left Str -> (Str -> Set(Int))
\* apalache-type: done Str -> Bool

ASSUME Assm ==
  /\ Scans # {} /\ Workers # {}
  /\ NPages \in Nat \ {0} /\ NInit \in 1..NPages /\ NNew \in Nat /\ VacuumRounds \in Nat
  /\ Isolation \in {"READ_COMMITTED", "REPEATABLE_READ"}
  /\ SnapshotAt \in {"worker_start", "collect", "query_start"}
  /\ LeaderLock \in BOOLEAN /\ OtherPx \in BOOLEAN
  /\ Mutant \in {"none", "collect_without_build"}
  /\ Nested \in BOOLEAN

PIdx == 1..NPages
Pages == Scans \X PIdx                     \* page <<s, i>>: page i of scan s's heap
RIdx == 1..(NInit + NNew)
Rows == Scans \X RIdx                      \* row <<s, i>>: initial when i <= NInit
\* @type: (<<Str, Int>>) => Bool;
IsInit(r) == r[2] <= NInit
NoPage == 0

\* the snapshot exists before the statement's first open
QuerySnapshot == Isolation = "REPEATABLE_READ" \/ SnapshotAt = "query_start"
\* the leader builds the snapshot at open, before collecting (the fix)
LeaderBuilds == SnapshotAt = "collect" /\ Mutant = "none"
\* the leader collects only once a snapshot exists
CollectNeedsSnap == QuerySnapshot \/ SnapshotAt = "collect"

VARIABLES alloc, home, insC, delC, gone, readCnt, clock, snap, rounds,
          qstarted, otherDone, lsnap, opened, bitmap, owner, started, left, done
vars == <<alloc, home, insC, delC, gone, readCnt, clock, snap, rounds,
          qstarted, otherDone, lsnap, opened, bitmap, owner, started, left, done>>
dataVars == <<alloc, home, insC, delC, gone, clock>>
scanVars == <<lsnap, opened, bitmap, owner, started, left, done>>

\* @type: (<<Str, Int>>) => <<Str, Int>>;
Page(r) == <<r[1], home[r]>>

\* @type: (<<Str, Int>>, Int) => Bool;
VisibleAt(r, t) == insC[r] > 0 /\ insC[r] < t /\ ~(delC[r] > 0 /\ delC[r] < t)
AllDone == \A s \in Scans : done[s]
OldestVisible == IF snap > 0 /\ ~AllDone THEN snap ELSE clock
\* @type: (<<Str, Int>>) => Bool;
PageEmpty(pg) == \A r \in Rows : r[1] = pg[1] /\ home[r] = pg[2] => gone[r]
\* the snapshot build under m_px_lock_mutex: one test-and-build step
Build == IF snap = 0 THEN clock ELSE snap

Init ==
  /\ alloc = [pg \in Pages |-> pg[2] <= NInit]
  /\ home = [r \in Rows |-> IF IsInit(r) THEN r[2] ELSE NoPage]
  /\ insC = [r \in Rows |-> IF IsInit(r) THEN 1 ELSE 0]
  /\ delC = [r \in Rows |-> 0]
  /\ gone = [r \in Rows |-> FALSE]
  /\ readCnt = [r \in Rows |-> 0]
  /\ clock = 2
  /\ snap = 0
  /\ rounds = VacuumRounds
  /\ qstarted = FALSE
  /\ otherDone = ~OtherPx
  /\ lsnap = [s \in Scans |-> "idle"]
  /\ opened = [s \in Scans |-> FALSE]
  /\ bitmap = [s \in Scans |-> {}]
  /\ owner = [s \in Scans |-> [i \in PIdx |-> CHOOSE w \in Workers : TRUE]]
  /\ started = [s \in Scans |-> [w \in Workers |-> FALSE]]
  /\ left = [s \in Scans |-> [w \in Workers |-> {}]]
  /\ done = [s \in Scans |-> FALSE]

\* ---- the statement ----
\* qexec_execute_query: logtb_get_mvcc_snapshot before qexec_execute_mainblock
QueryStart ==
  /\ ~qstarted
  /\ qstarted' = TRUE
  /\ snap' = IF QuerySnapshot THEN Build ELSE snap
  /\ UNCHANGED <<dataVars, readCnt, rounds, otherDone, scanVars>>

\* the leader's build at open (the fix), as one step under the mutex
LeaderSnap(s) ==
  /\ qstarted /\ LeaderBuilds /\ LeaderLock /\ lsnap[s] = "idle"
  /\ lsnap' = [lsnap EXCEPT ![s] = "built"]
  /\ snap' = Build
  /\ UNCHANGED <<dataVars, readCnt, rounds, qstarted, otherDone, opened, bitmap, owner, started, left, done>>

\* the same build without the mutex: the test ...
LeaderTest(s) ==
  /\ qstarted /\ LeaderBuilds /\ ~LeaderLock /\ lsnap[s] = "idle"
  /\ lsnap' = [lsnap EXCEPT ![s] = IF snap = 0 THEN "saw_invalid" ELSE "built"]
  /\ UNCHANGED <<dataVars, readCnt, snap, rounds, qstarted, otherDone, opened, bitmap, owner, started, left, done>>

\* ... then the build, over whatever another thread built in between
LeaderWrite(s) ==
  /\ lsnap[s] = "saw_invalid"
  /\ lsnap' = [lsnap EXCEPT ![s] = "built"]
  /\ snap' = clock
  /\ UNCHANGED <<dataVars, readCnt, rounds, qstarted, otherDone, opened, bitmap, owner, started, left, done>>

\* manager::open -> input_handler_heap::init_on_main: file_get_all_data_sectors, split
Collect(s) ==
  /\ qstarted /\ ~opened[s]
  /\ LeaderBuilds => lsnap[s] = "built"
  /\ CollectNeedsSnap => snap > 0
  /\ opened' = [opened EXCEPT ![s] = TRUE]
  /\ bitmap' = [bitmap EXCEPT ![s] = {i \in PIdx : alloc[<<s, i>>]}]
  /\ \E o \in [PIdx -> Workers] : owner' = [owner EXCEPT ![s] = o]
  /\ UNCHANGED <<dataVars, readCnt, snap, rounds, qstarted, otherDone, lsnap, started, left, done>>

\* px_scan_task: scan_start_scan -> logtb_get_mvcc_snapshot under m_px_lock_mutex
Start(s, w) ==
  /\ opened[s] /\ ~started[s][w]
  /\ started' = [started EXCEPT ![s][w] = TRUE]
  /\ left' = [left EXCEPT ![s][w] = {i \in bitmap[s] : owner[s][i] = w}]
  /\ snap' = Build
  /\ UNCHANGED <<dataVars, readCnt, rounds, qstarted, otherDone, lsnap, opened, bitmap, owner, done>>

\* one bitmap page read under its read latch; a deallocated page is skipped
ReadPage(s, w, i) ==
  /\ started[s][w] /\ i \in left[s][w]
  /\ left' = [left EXCEPT ![s][w] = @ \ {i}]
  /\ readCnt' = [r \in Rows |->
                   IF r[1] = s /\ home[r] = i /\ alloc[<<s, i>>] /\ ~gone[r] /\ VisibleAt(r, snap)
                   THEN readCnt[r] + 1 ELSE readCnt[r]]
  /\ UNCHANGED <<dataVars, snap, rounds, qstarted, otherDone, lsnap, opened, bitmap, owner, started, done>>

Finish(s) ==
  /\ opened[s] /\ ~done[s]
  /\ \A w \in Workers : started[s][w] /\ left[s][w] = {}
  /\ done' = [done EXCEPT ![s] = TRUE]
  /\ UNCHANGED <<dataVars, readCnt, snap, rounds, qstarted, otherDone, lsnap, opened, bitmap, owner, started, left>>

\* another parallel operator's worker of the same statement builds the snapshot
OtherBuild ==
  /\ qstarted /\ ~otherDone
  /\ otherDone' = TRUE
  /\ snap' = Build
  /\ UNCHANGED <<dataVars, readCnt, rounds, qstarted, scanVars>>

\* an SP's SQL, sent by the client, invalidates the statement's snapshot (logtb_invalidate_snapshot_data)
NestedInvalidate ==
  /\ Nested /\ qstarted /\ ~AllDone /\ snap > 0
  /\ snap' = 0
  /\ UNCHANGED <<dataVars, readCnt, rounds, qstarted, otherDone, scanVars>>

\* ---- other transactions and vacuum ----
\* @type: (<<Str, Int>>, Int) => Bool;
Insert(r, i) ==
  /\ ~IsInit(r) /\ insC[r] = 0
  /\ alloc' = [alloc EXCEPT ![<<r[1], i>>] = TRUE]
  /\ home' = [home EXCEPT ![r] = i]
  /\ insC' = [insC EXCEPT ![r] = clock]
  /\ clock' = clock + 1
  /\ UNCHANGED <<delC, gone, readCnt, snap, rounds, qstarted, otherDone, scanVars>>

\* @type: (<<Str, Int>>) => Bool;
Delete(r) ==
  /\ insC[r] > 0 /\ delC[r] = 0
  /\ delC' = [delC EXCEPT ![r] = clock]
  /\ clock' = clock + 1
  /\ UNCHANGED <<alloc, home, insC, gone, readCnt, snap, rounds, qstarted, otherDone, scanVars>>

\* @type: (<<Str, Int>>) => Bool;
VacuumRows(pg) ==
  /\ rounds > 0 /\ alloc[pg]
  /\ rounds' = rounds - 1
  /\ gone' = [r \in Rows |-> gone[r] \/ (r[1] = pg[1] /\ home[r] = pg[2] /\ delC[r] > 0 /\ delC[r] < OldestVisible)]
  /\ UNCHANGED <<alloc, home, insC, delC, readCnt, clock, snap, qstarted, otherDone, scanVars>>

\* @type: (<<Str, Int>>) => Bool;
VacuumPage(pg) ==
  /\ rounds > 0 /\ alloc[pg] /\ PageEmpty(pg)
  /\ rounds' = rounds - 1
  /\ alloc' = [alloc EXCEPT ![pg] = FALSE]
  /\ UNCHANGED <<home, insC, delC, gone, readCnt, clock, snap, qstarted, otherDone, scanVars>>

\* the statement is over: stutter
Terminated == AllDone /\ otherDone /\ UNCHANGED vars

ScanStep ==
  \/ QueryStart
  \/ \E s \in Scans : \/ LeaderSnap(s) \/ LeaderTest(s) \/ LeaderWrite(s) \/ Collect(s) \/ Finish(s)
                      \/ \E w \in Workers : Start(s, w) \/ \E i \in PIdx : ReadPage(s, w, i)

Next ==
  \/ Terminated
  \/ ScanStep
  \/ OtherBuild
  \/ NestedInvalidate
  \/ \E r \in Rows, i \in PIdx : Insert(r, i)
  \/ \E r \in Rows : Delete(r)
  \/ \E pg \in Pages : VacuumRows(pg) \/ VacuumPage(pg)

Spec == Init /\ [][Next]_vars
FairSpec == Spec /\ WF_vars(ScanStep) /\ WF_vars(OtherBuild)

\* ---- properties ----
\* Boolean, integer and set typing apart for tlapm's SMT encoding (cubrid-tla P4).
BoolOK ==
  /\ alloc \in [Pages -> BOOLEAN] /\ gone \in [Rows -> BOOLEAN]
  /\ qstarted \in BOOLEAN /\ otherDone \in BOOLEAN
  /\ opened \in [Scans -> BOOLEAN] /\ done \in [Scans -> BOOLEAN]
  /\ started \in [Scans -> [Workers -> BOOLEAN]]
NatOK ==
  /\ home \in [Rows -> 0..NPages]
  /\ insC \in [Rows -> Nat] /\ delC \in [Rows -> Nat] /\ readCnt \in [Rows -> Nat]
  /\ clock \in Nat /\ snap \in Nat /\ rounds \in Nat
SetOK ==
  /\ lsnap \in [Scans -> {"idle", "saw_invalid", "built"}]
  /\ bitmap \in [Scans -> SUBSET PIdx]
  /\ owner \in [Scans -> [PIdx -> Workers]]
  /\ left \in [Scans -> [Workers -> SUBSET PIdx]]
TypeOK == BoolOK /\ NatOK /\ SetOK

\* C1: each scan returns exactly the rows of its heap visible to the snapshot, each once.
SameAsSnapshot ==
  \A s \in Scans : done[s] => \A r \in Rows : r[1] = s => readCnt[r] = IF VisibleAt(r, snap) THEN 1 ELSE 0

\* C2: once built, the statement's snapshot never changes (one snapshot per statement);
\* for statements without a nested statement (Nested = FALSE).
SnapshotStable == [][snap # 0 => snap' = snap]_vars

\* C4: a heap worker never builds the snapshot; it reuses the one the leader built
\* (statements without a nested statement; with one, a late worker may rebuild it).
WorkerReuses == [][\A s \in Scans, w \in Workers : Start(s, w) => snap # 0]_vars

\* C3: every scan of the statement finishes.
StatementFinishes == <>AllDone

\* ---- inductive invariant of the fix (SnapshotAt = "collect", LeaderLock, Mutant = "none") ----
R_fix == CollectNeedsSnap /\ (~LeaderLock => ~LeaderBuilds) /\ Mutant = "none" /\ ~Nested
R_snap == clock > 0 /\ snap <= clock /\ (\A s \in Scans : opened[s] => snap > 0)
R_q == ~qstarted => snap = 0 /\ (\A s \in Scans : ~opened[s] /\ lsnap[s] = "idle")
R_lsnap == \A s \in Scans : lsnap[s] # "saw_invalid" /\ (lsnap[s] = "built" => snap > 0)
R_clock == \A r \in Rows : insC[r] < clock /\ delC[r] < clock
R_order == \A r \in Rows : delC[r] > 0 => insC[r] > 0 /\ insC[r] < delC[r]
R_home == \A r \in Rows : (insC[r] > 0) = (home[r] # NoPage)
R_init == \A r \in Rows : IsInit(r) => insC[r] = 1 /\ home[r] = r[2]
R_gone == \A r \in Rows : gone[r] => delC[r] > 0
R_alloc == \A r \in Rows : home[r] # NoPage /\ ~gone[r] => alloc[Page(r)]
R_vis == \A r \in Rows : VisibleAt(r, snap) /\ ~done[r[1]] => ~gone[r]
R_open == \A s \in Scans : ~opened[s] => bitmap[s] = {} /\ ~done[s]
R_start == \A s \in Scans : \A w \in Workers :
             (~opened[s] => ~started[s][w]) /\ (~started[s][w] => left[s][w] = {})
R_left == \A s \in Scans : \A w \in Workers : left[s][w] \subseteq {i \in bitmap[s] : owner[s][i] = w}
R_bitmap == \A r \in Rows : opened[r[1]] /\ VisibleAt(r, snap) => home[r] \in bitmap[r[1]]
R_count == \A r \in Rows : readCnt[r] =
             IF opened[r[1]] /\ VisibleAt(r, snap) /\ started[r[1]][owner[r[1]][home[r]]]
                /\ home[r] \notin left[r[1]][owner[r[1]][home[r]]]
             THEN 1 ELSE 0
R_done == \A s \in Scans : done[s] => \A w \in Workers : started[s][w] /\ left[s][w] = {}

IndInv == TypeOK /\ R_fix /\ R_snap /\ R_q /\ R_lsnap /\ R_clock /\ R_order /\ R_home /\ R_init
          /\ R_gone /\ R_alloc /\ R_vis /\ R_open /\ R_start /\ R_left /\ R_bitmap /\ R_count /\ R_done

\* ---- witnesses ----
\* a page allocated after a scan's open holds a committed row
NotRowOnNewPage == ~\E r \in Rows : opened[r[1]] /\ home[r] # NoPage /\ home[r] \notin bitmap[r[1]] /\ insC[r] > 0
\* another operator built the snapshot before any leader did
NotOtherBuiltFirst == ~(otherDone /\ OtherPx /\ snap > 0 /\ \A s \in Scans : lsnap[s] = "idle" /\ ~opened[s])
\* vacuum deallocated a bitmap page while its scan was running
NotDeallocDuringScan == ~\E s \in Scans, i \in PIdx : i \in bitmap[s] /\ ~alloc[<<s, i>>] /\ ~done[s]
\* every scan finished, each having read a row
NotAllScansRead == ~(AllDone /\ \A s \in Scans : \E r \in Rows : r[1] = s /\ readCnt[r] = 1)

\* Apalache: role sets fixed, page and row counts fixed, vacuum rounds and the clock open
CInit ==
  /\ Scans = {"s1", "s2"} /\ Workers = {"w1", "w2"}
  /\ NPages = 2 /\ NInit = 1 /\ NNew = 1 /\ VacuumRounds \in Nat
  /\ Isolation = "READ_COMMITTED" /\ SnapshotAt = "collect" /\ LeaderLock = TRUE /\ OtherPx = TRUE
  /\ Mutant = "none" /\ Nested = FALSE
=============================================================================
