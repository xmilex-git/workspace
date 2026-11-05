----------------------------- MODULE PxHeapScan -----------------------------
(* Parallel heap scan (develop e98bdd885) against concurrent INSERT, DELETE and
   vacuum's empty-page removal.

   The leader collects the heap file's data-page bitmap when the scan opens
   (scan_open_parallel_heap_scan -> manager::open -> input_handler_heap::
   init_on_main -> file_get_all_data_sectors) and splits it among the workers.
   Each worker walks its own pages in order: it releases its current page, then
   fixes the next one (OLD_PAGE_MAYBE_DEALLOCATED: a page deallocated since the
   bitmap is skipped), and reads the rows visible to the transaction's MVCC
   snapshot while it holds the read latch.

   Snapshot: under READ COMMITTED the snapshot is built by the first
   logtb_get_mvcc_snapshot of the statement; a parallel heap scan's leader never
   calls it before open, so the first worker's scan_start_scan builds it.
   Under REPEATABLE READ qexec_execute_query builds it before any scan opens.

   Rows: each row commits its insert (and maybe its delete) in one step; clock
   orders commits. Vacuum removes a row whose delete committed before every
   live snapshot, then deallocates a page left empty: it X-latches the page's
   chain neighbours first and the page last (heap_remove_page_on_vacuum). *)
EXTENDS Naturals, FiniteSets

CONSTANTS Workers, NPages, NInit, NNew, VacuumRounds, Isolation, SnapshotPoint, Mutant
ASSUME Assm ==
  /\ Workers # {} /\ NPages \in Nat \ {0} /\ NInit \in 1..NPages /\ NNew \in Nat /\ VacuumRounds \in Nat
  /\ Isolation \in {"READ_COMMITTED", "REPEATABLE_READ"}
  /\ SnapshotPoint \in {"code", "before_open"}   \* "before_open": the candidate fix
  /\ Mutant \in {"none", "hold_current_while_fixing_next", "no_dealloc_skip", "reread_page"}

Pages == 1..NPages
InitRows == 1..NInit                 \* row i starts on page i
NewRows == (NInit + 1)..(NInit + NNew)
Rows == InitRows \cup NewRows
NoPage == 0

(* --algorithm PxHeapScan
variables
  alloc = [p \in Pages |-> p <= NInit],
  home = [r \in Rows |-> IF r \in InitRows THEN r ELSE NoPage],
  insC = [r \in Rows |-> IF r \in InitRows THEN 1 ELSE 0],   \* commit time of the insert, 0 = none
  delC = [r \in Rows |-> 0],                                  \* commit time of the delete, 0 = none
  gone = [r \in Rows |-> FALSE],                              \* removed by vacuum
  clock = 2,
  snap = 0,                       \* the transaction's snapshot time, 0 = not built
  bitmap = {},                    \* pages collected at open
  opened = FALSE,
  readers = [p \in Pages |-> {}], \* read-latch holders
  vx = {},                        \* pages vacuum holds X-latched
  readCnt = [r \in Rows |-> 0],   \* times a worker returned the row
  readDealloc = FALSE,            \* ghost: a worker read a deallocated page
  scanDone = FALSE;

define
  Min(S) == CHOOSE x \in S : \A y \in S : x <= y
  VisibleAt(r, t) == insC[r] > 0 /\ insC[r] < t /\ ~(delC[r] > 0 /\ delC[r] < t)
  \* Pages of worker w: ftab_set::split gives each worker a contiguous run of the bitmap.
  Rank(p) == Cardinality({q \in bitmap : q < p})
  WorkerIds == CHOOSE f \in [Workers -> 0..(Cardinality(Workers) - 1)] :
                 \A a, b \in Workers : a # b => f[a] # f[b]
  Mine(w) == {p \in bitmap : (Rank(p) * Cardinality(Workers)) \div Cardinality(bitmap) = WorkerIds[w]}
  Release(rd, c, w) == IF c = NoPage THEN rd ELSE [rd EXCEPT ![c] = @ \ {w}]
  \* vacuum may remove a row whose delete committed before every live snapshot
  OldestVisible == IF snap > 0 /\ ~scanDone THEN snap ELSE clock
  Neighbours(p) == {q \in Pages : alloc[q] /\ q # p /\ (q = p - 1 \/ q = p + 1)}
  Free(p) == readers[p] = {} /\ p \notin vx
  PageEmpty(p) == \A r \in Rows : home[r] = p => gone[r]

  TypeOK == /\ alloc \in [Pages -> BOOLEAN] /\ home \in [Rows -> Pages \cup {NoPage}]
            /\ readers \in [Pages -> SUBSET Workers] /\ vx \subseteq Pages
            /\ readCnt \in [Rows -> Nat] /\ snap \in Nat /\ clock \in Nat
  \* C1: the scan returns exactly the rows visible to its snapshot, each once.
  SameAsSnapshot == scanDone =>
                      \A r \in Rows : readCnt[r] = IF VisibleAt(r, snap) THEN 1 ELSE 0
  NoDuplicate == \A r \in Rows : readCnt[r] <= 1
  \* C3: no worker reads a page vacuum has deallocated.
  NoDeallocatedRead == ~readDealloc
  ScanFinishes == <>scanDone
  \* witnesses
  NotVacuumDeallocDuringScan == ~(opened /\ ~scanDone /\ \E p \in bitmap : ~alloc[p])
  NotNewPageDuringScan == ~(opened /\ ~scanDone /\ \E p \in Pages \ bitmap : alloc[p])
end define;

\* ---- the scan ----
fair process leader = "leader"
begin
  L_snapshot:
    if Isolation = "REPEATABLE_READ" \/ SnapshotPoint = "before_open" then
      snap := clock;                     \* qexec_execute_query: logtb_get_mvcc_snapshot
    end if;
  L_open:
    bitmap := {p \in Pages : alloc[p]};  \* manager::open -> file_get_all_data_sectors
    opened := TRUE;
  L_join:
    await \A w \in Workers : pc[w] = "Done";
    scanDone := TRUE;
end process;

fair process worker \in Workers
variables cur = NoPage, todo = {};
begin
  W_start:
    await opened;
    todo := Mine(self);
    if snap = 0 then snap := clock end if;   \* scan_start_scan -> logtb_get_mvcc_snapshot (under m_px_lock_mutex)
  W_next:
    while todo # {} do
      \* release the current page first (CBRD-27723), unless the mutant keeps it
      if Mutant # "hold_current_while_fixing_next" then
        readers := Release(readers, cur, self) || cur := NoPage;
      end if;
  W_fix:
      with p = Min(todo) do
        await p \notin vx;               \* pgbuf_ordered_fix waits on an X latch
        \* reread_page: the page stays in the list once (a split that hands a page to two workers)
        todo := IF Mutant = "reread_page" /\ readCnt = [r \in Rows |-> 0] THEN todo ELSE todo \ {p};
        if alloc[p] then
          readers := [Release(readers, cur, self) EXCEPT ![p] = @ \cup {self}] || cur := p;
        elsif Mutant = "no_dealloc_skip" then
          readers := Release(readers, cur, self) || readDealloc := TRUE || cur := NoPage;
        else
          \* ER_PB_BAD_PAGEID: deallocated since the bitmap, skip
          readers := Release(readers, cur, self) || cur := NoPage;
        end if;
      end with;
  W_read:
      if cur # NoPage then
        readCnt := [r \in Rows |->
                      IF home[r] = cur /\ ~gone[r] /\ VisibleAt(r, snap) THEN readCnt[r] + 1 ELSE readCnt[r]];
      end if;
    end while;
  W_end:
    readers := Release(readers, cur, self) || cur := NoPage;
end process;

\* ---- the environment: other transactions and vacuum ----
process inserter = "inserter"
begin
  I_loop:
    while \E r \in NewRows : insC[r] = 0 do
      with r \in {x \in NewRows : insC[x] = 0}, p \in Pages do
        await Free(p);                   \* heap_insert: X latch on the target page
        alloc[p] := TRUE || home[r] := p || insC[r] := clock;
        clock := clock + 1;
      end with;
    end while;
end process;

process deleter = "deleter"
begin
  D_loop:
    while \E r \in Rows : insC[r] > 0 /\ delC[r] = 0 do
      either
        with r \in {x \in Rows : insC[x] > 0 /\ delC[x] = 0} do
          await Free(home[r]);
          delC[r] := clock;
          clock := clock + 1;
        end with;
      or
        goto Done;
      end either;
    end while;
end process;

\* Vacuum runs at most VacuumRounds passes during the scan: an endless retry of the same page
\* would starve the worker waiting for it, which no fairness on the scan can exclude.
process vacuum = "vacuum"
variables target = NoPage, rounds = VacuumRounds;
begin
  V_loop:
    while rounds > 0 do
      rounds := rounds - 1;
      either
        \* remove dead rows on a page
        with p \in {q \in Pages : alloc[q] /\ Free(q)} do
          gone := [r \in Rows |-> gone[r] \/ (home[r] = p /\ delC[r] > 0 /\ delC[r] < OldestVisible)];
        end with;
      or
        \* empty page removal: neighbours first, then the page
        with p \in {q \in Pages : alloc[q] /\ PageEmpty(q) /\ Free(q)} do
          await \A q \in Neighbours(p) : Free(q);
          vx := Neighbours(p) || target := p;
        end with;
  V_page:
        \* re-latch the page, re-check it (spage_number_of_records, waiters) and give up when it no
        \* longer qualifies or for any other reason (pgbuf_has_any_waiters, a failed fix)
        await Free(target);
        either
          if PageEmpty(target) then
            alloc[target] := FALSE;      \* file_dealloc
          end if;
        or
          skip;
        end either;
        vx := {} || target := NoPage;
      or
        skip;                            \* an idle pass: nothing to do on this heap
      end either;
    end while;
end process;
end algorithm; *)
\* BEGIN TRANSLATION
VARIABLES alloc, home, insC, delC, gone, clock, snap, bitmap, opened, readers, 
          vx, readCnt, readDealloc, scanDone, pc

(* define statement *)
Min(S) == CHOOSE x \in S : \A y \in S : x <= y
VisibleAt(r, t) == insC[r] > 0 /\ insC[r] < t /\ ~(delC[r] > 0 /\ delC[r] < t)

Rank(p) == Cardinality({q \in bitmap : q < p})
WorkerIds == CHOOSE f \in [Workers -> 0..(Cardinality(Workers) - 1)] :
               \A a, b \in Workers : a # b => f[a] # f[b]
Mine(w) == {p \in bitmap : (Rank(p) * Cardinality(Workers)) \div Cardinality(bitmap) = WorkerIds[w]}
Release(rd, c, w) == IF c = NoPage THEN rd ELSE [rd EXCEPT ![c] = @ \ {w}]

OldestVisible == IF snap > 0 /\ ~scanDone THEN snap ELSE clock
Neighbours(p) == {q \in Pages : alloc[q] /\ q # p /\ (q = p - 1 \/ q = p + 1)}
Free(p) == readers[p] = {} /\ p \notin vx
PageEmpty(p) == \A r \in Rows : home[r] = p => gone[r]

TypeOK == /\ alloc \in [Pages -> BOOLEAN] /\ home \in [Rows -> Pages \cup {NoPage}]
          /\ readers \in [Pages -> SUBSET Workers] /\ vx \subseteq Pages
          /\ readCnt \in [Rows -> Nat] /\ snap \in Nat /\ clock \in Nat

SameAsSnapshot == scanDone =>
                    \A r \in Rows : readCnt[r] = IF VisibleAt(r, snap) THEN 1 ELSE 0
NoDuplicate == \A r \in Rows : readCnt[r] <= 1

NoDeallocatedRead == ~readDealloc
ScanFinishes == <>scanDone

NotVacuumDeallocDuringScan == ~(opened /\ ~scanDone /\ \E p \in bitmap : ~alloc[p])
NotNewPageDuringScan == ~(opened /\ ~scanDone /\ \E p \in Pages \ bitmap : alloc[p])

VARIABLES cur, todo, target, rounds

vars == << alloc, home, insC, delC, gone, clock, snap, bitmap, opened, 
           readers, vx, readCnt, readDealloc, scanDone, pc, cur, todo, target, 
           rounds >>

ProcSet == {"leader"} \cup (Workers) \cup {"inserter"} \cup {"deleter"} \cup {"vacuum"}

Init == (* Global variables *)
        /\ alloc = [p \in Pages |-> p <= NInit]
        /\ home = [r \in Rows |-> IF r \in InitRows THEN r ELSE NoPage]
        /\ insC = [r \in Rows |-> IF r \in InitRows THEN 1 ELSE 0]
        /\ delC = [r \in Rows |-> 0]
        /\ gone = [r \in Rows |-> FALSE]
        /\ clock = 2
        /\ snap = 0
        /\ bitmap = {}
        /\ opened = FALSE
        /\ readers = [p \in Pages |-> {}]
        /\ vx = {}
        /\ readCnt = [r \in Rows |-> 0]
        /\ readDealloc = FALSE
        /\ scanDone = FALSE
        (* Process worker *)
        /\ cur = [self \in Workers |-> NoPage]
        /\ todo = [self \in Workers |-> {}]
        (* Process vacuum *)
        /\ target = NoPage
        /\ rounds = VacuumRounds
        /\ pc = [self \in ProcSet |-> CASE self = "leader" -> "L_snapshot"
                                        [] self \in Workers -> "W_start"
                                        [] self = "inserter" -> "I_loop"
                                        [] self = "deleter" -> "D_loop"
                                        [] self = "vacuum" -> "V_loop"]

L_snapshot == /\ pc["leader"] = "L_snapshot"
              /\ IF Isolation = "REPEATABLE_READ" \/ SnapshotPoint = "before_open"
                    THEN /\ snap' = clock
                    ELSE /\ TRUE
                         /\ snap' = snap
              /\ pc' = [pc EXCEPT !["leader"] = "L_open"]
              /\ UNCHANGED << alloc, home, insC, delC, gone, clock, bitmap, 
                              opened, readers, vx, readCnt, readDealloc, 
                              scanDone, cur, todo, target, rounds >>

L_open == /\ pc["leader"] = "L_open"
          /\ bitmap' = {p \in Pages : alloc[p]}
          /\ opened' = TRUE
          /\ pc' = [pc EXCEPT !["leader"] = "L_join"]
          /\ UNCHANGED << alloc, home, insC, delC, gone, clock, snap, readers, 
                          vx, readCnt, readDealloc, scanDone, cur, todo, 
                          target, rounds >>

L_join == /\ pc["leader"] = "L_join"
          /\ \A w \in Workers : pc[w] = "Done"
          /\ scanDone' = TRUE
          /\ pc' = [pc EXCEPT !["leader"] = "Done"]
          /\ UNCHANGED << alloc, home, insC, delC, gone, clock, snap, bitmap, 
                          opened, readers, vx, readCnt, readDealloc, cur, todo, 
                          target, rounds >>

leader == L_snapshot \/ L_open \/ L_join

W_start(self) == /\ pc[self] = "W_start"
                 /\ opened
                 /\ todo' = [todo EXCEPT ![self] = Mine(self)]
                 /\ IF snap = 0
                       THEN /\ snap' = clock
                       ELSE /\ TRUE
                            /\ snap' = snap
                 /\ pc' = [pc EXCEPT ![self] = "W_next"]
                 /\ UNCHANGED << alloc, home, insC, delC, gone, clock, bitmap, 
                                 opened, readers, vx, readCnt, readDealloc, 
                                 scanDone, cur, target, rounds >>

W_next(self) == /\ pc[self] = "W_next"
                /\ IF todo[self] # {}
                      THEN /\ IF Mutant # "hold_current_while_fixing_next"
                                 THEN /\ /\ cur' = [cur EXCEPT ![self] = NoPage]
                                         /\ readers' = Release(readers, cur[self], self)
                                 ELSE /\ TRUE
                                      /\ UNCHANGED << readers, cur >>
                           /\ pc' = [pc EXCEPT ![self] = "W_fix"]
                      ELSE /\ pc' = [pc EXCEPT ![self] = "W_end"]
                           /\ UNCHANGED << readers, cur >>
                /\ UNCHANGED << alloc, home, insC, delC, gone, clock, snap, 
                                bitmap, opened, vx, readCnt, readDealloc, 
                                scanDone, todo, target, rounds >>

W_fix(self) == /\ pc[self] = "W_fix"
               /\ LET p == Min(todo[self]) IN
                    /\ p \notin vx
                    /\ todo' = [todo EXCEPT ![self] = IF Mutant = "reread_page" /\ readCnt = [r \in Rows |-> 0] THEN todo[self] ELSE todo[self] \ {p}]
                    /\ IF alloc[p]
                          THEN /\ /\ cur' = [cur EXCEPT ![self] = p]
                                  /\ readers' = [Release(readers, cur[self], self) EXCEPT ![p] = @ \cup {self}]
                               /\ UNCHANGED readDealloc
                          ELSE /\ IF Mutant = "no_dealloc_skip"
                                     THEN /\ /\ cur' = [cur EXCEPT ![self] = NoPage]
                                             /\ readDealloc' = TRUE
                                             /\ readers' = Release(readers, cur[self], self)
                                     ELSE /\ /\ cur' = [cur EXCEPT ![self] = NoPage]
                                             /\ readers' = Release(readers, cur[self], self)
                                          /\ UNCHANGED readDealloc
               /\ pc' = [pc EXCEPT ![self] = "W_read"]
               /\ UNCHANGED << alloc, home, insC, delC, gone, clock, snap, 
                               bitmap, opened, vx, readCnt, scanDone, target, 
                               rounds >>

W_read(self) == /\ pc[self] = "W_read"
                /\ IF cur[self] # NoPage
                      THEN /\ readCnt' = [r \in Rows |->
                                            IF home[r] = cur[self] /\ ~gone[r] /\ VisibleAt(r, snap) THEN readCnt[r] + 1 ELSE readCnt[r]]
                      ELSE /\ TRUE
                           /\ UNCHANGED readCnt
                /\ pc' = [pc EXCEPT ![self] = "W_next"]
                /\ UNCHANGED << alloc, home, insC, delC, gone, clock, snap, 
                                bitmap, opened, readers, vx, readDealloc, 
                                scanDone, cur, todo, target, rounds >>

W_end(self) == /\ pc[self] = "W_end"
               /\ /\ cur' = [cur EXCEPT ![self] = NoPage]
                  /\ readers' = Release(readers, cur[self], self)
               /\ pc' = [pc EXCEPT ![self] = "Done"]
               /\ UNCHANGED << alloc, home, insC, delC, gone, clock, snap, 
                               bitmap, opened, vx, readCnt, readDealloc, 
                               scanDone, todo, target, rounds >>

worker(self) == W_start(self) \/ W_next(self) \/ W_fix(self)
                   \/ W_read(self) \/ W_end(self)

I_loop == /\ pc["inserter"] = "I_loop"
          /\ IF \E r \in NewRows : insC[r] = 0
                THEN /\ \E r \in {x \in NewRows : insC[x] = 0}:
                          \E p \in Pages:
                            /\ Free(p)
                            /\ /\ alloc' = [alloc EXCEPT ![p] = TRUE]
                               /\ home' = [home EXCEPT ![r] = p]
                               /\ insC' = [insC EXCEPT ![r] = clock]
                            /\ clock' = clock + 1
                     /\ pc' = [pc EXCEPT !["inserter"] = "I_loop"]
                ELSE /\ pc' = [pc EXCEPT !["inserter"] = "Done"]
                     /\ UNCHANGED << alloc, home, insC, clock >>
          /\ UNCHANGED << delC, gone, snap, bitmap, opened, readers, vx, 
                          readCnt, readDealloc, scanDone, cur, todo, target, 
                          rounds >>

inserter == I_loop

D_loop == /\ pc["deleter"] = "D_loop"
          /\ IF \E r \in Rows : insC[r] > 0 /\ delC[r] = 0
                THEN /\ \/ /\ \E r \in {x \in Rows : insC[x] > 0 /\ delC[x] = 0}:
                                /\ Free(home[r])
                                /\ delC' = [delC EXCEPT ![r] = clock]
                                /\ clock' = clock + 1
                           /\ pc' = [pc EXCEPT !["deleter"] = "D_loop"]
                        \/ /\ pc' = [pc EXCEPT !["deleter"] = "Done"]
                           /\ UNCHANGED <<delC, clock>>
                ELSE /\ pc' = [pc EXCEPT !["deleter"] = "Done"]
                     /\ UNCHANGED << delC, clock >>
          /\ UNCHANGED << alloc, home, insC, gone, snap, bitmap, opened, 
                          readers, vx, readCnt, readDealloc, scanDone, cur, 
                          todo, target, rounds >>

deleter == D_loop

V_loop == /\ pc["vacuum"] = "V_loop"
          /\ IF rounds > 0
                THEN /\ rounds' = rounds - 1
                     /\ \/ /\ \E p \in {q \in Pages : alloc[q] /\ Free(q)}:
                                gone' = [r \in Rows |-> gone[r] \/ (home[r] = p /\ delC[r] > 0 /\ delC[r] < OldestVisible)]
                           /\ pc' = [pc EXCEPT !["vacuum"] = "V_loop"]
                           /\ UNCHANGED <<vx, target>>
                        \/ /\ \E p \in {q \in Pages : alloc[q] /\ PageEmpty(q) /\ Free(q)}:
                                /\ \A q \in Neighbours(p) : Free(q)
                                /\ /\ target' = p
                                   /\ vx' = Neighbours(p)
                           /\ pc' = [pc EXCEPT !["vacuum"] = "V_page"]
                           /\ gone' = gone
                        \/ /\ TRUE
                           /\ pc' = [pc EXCEPT !["vacuum"] = "V_loop"]
                           /\ UNCHANGED <<gone, vx, target>>
                ELSE /\ pc' = [pc EXCEPT !["vacuum"] = "Done"]
                     /\ UNCHANGED << gone, vx, target, rounds >>
          /\ UNCHANGED << alloc, home, insC, delC, clock, snap, bitmap, opened, 
                          readers, readCnt, readDealloc, scanDone, cur, todo >>

V_page == /\ pc["vacuum"] = "V_page"
          /\ Free(target)
          /\ \/ /\ IF PageEmpty(target)
                      THEN /\ alloc' = [alloc EXCEPT ![target] = FALSE]
                      ELSE /\ TRUE
                           /\ alloc' = alloc
             \/ /\ TRUE
                /\ alloc' = alloc
          /\ /\ target' = NoPage
             /\ vx' = {}
          /\ pc' = [pc EXCEPT !["vacuum"] = "V_loop"]
          /\ UNCHANGED << home, insC, delC, gone, clock, snap, bitmap, opened, 
                          readers, readCnt, readDealloc, scanDone, cur, todo, 
                          rounds >>

vacuum == V_loop \/ V_page

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == leader \/ inserter \/ deleter \/ vacuum
           \/ (\E self \in Workers: worker(self))
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ WF_vars(leader)
        /\ \A self \in Workers : WF_vars(worker(self))

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION

\* Vacuum always finishes removing a page once the page is free; nothing else of vacuum is fair.
FairSpec == Spec /\ WF_vars(V_page)

(* Refinement: this latch-level scan implements the snapshot-level scan of
   PxHeapSnapshot. A worker's pages still to read are its todo list plus the
   page it has fixed but not read yet; W_fix of an allocated page is a
   stuttering step, W_read (or W_fix skipping a deallocated page) is ReadPage. *)
OwnerMap == [p \in bitmap |-> CHOOSE w \in Workers : p \in Mine(w)]
LeftMap == [w \in Workers |->
              IF pc[w] = "W_start" THEN {}
              ELSE todo[w] \cup (IF pc[w] = "W_read" /\ cur[w] # NoPage THEN {cur[w]} ELSE {})]
AbsRounds == rounds + (IF pc["vacuum"] = "V_page" THEN 1 ELSE 0)
Abs == INSTANCE PxHeapSnapshot
         WITH owner <- OwnerMap, started <- [w \in Workers |-> pc[w] # "W_start"],
              left <- LeftMap, rounds <- AbsRounds, MaxClock <- 0
AbsSpec == Abs!Spec
=============================================================================
