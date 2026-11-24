--------------------------- MODULE BitmapLockOrder ---------------------------
(* CBRD-28326: a scan that locks the rows it reads (SELECT ... FOR UPDATE, the select phase of an UPDATE or
   DELETE that locks at select, or the force phase that locks the list's rows in the order the select wrote
   them) run as a bitmap heap scan. The rows are locked in the heap step's order (file order) instead of the
   index's key order. The lock's time, mode and life stay as they are.

   Code (CBRD-28032 head b52b26697c):
   - scan_manager.c scan_next_index_bitmap      heap step: fixes the page of the next recorded row
                                                (scan_fix_bitmap_heap_page), calls scan_next_index_lookup_heap
   - scan_manager.c scan_next_index_lookup_heap mvcc_select_lock_needed: locator_lock_and_get_object_with_evaluation
                                                with the scan's range, key and data filters (UPDDEL_MVCC_COND_REEVAL)
   - heap_file.c heap_init_get_context          the scan cache's fixed page moves to the home watcher
   - locator_sr.c locator_lock_and_get_object_internal   LK_COND_LOCK first; on failure
                                                locator_lock_object_unless_ours unfixes the home page,
                                                heap_clean_get_context the forward page, then LK_UNCOND_LOCK;
                                                then heap_prepare_get_context fixes again and rereads the last version
   - locator_sr.c locator_lock_and_get_object_with_evaluation   RC: reevaluation of the filters and, with
                                                must_recompute, of the assignments on the last version;
                                                locator_has_isolation_conflict above RC
   - scan_manager.c scan_bitmap_marks           the heap step's order key is (slot >= 640, volid, pageid, slotid)
   - lock_manager.c deadlock detection          a cycle of lock waits gets a victim whose transaction is aborted
                                                (ER_LK_UNILATERALLY_ABORTED, develop probe 2026-11-24); a page
                                                latch wait is not in the waits-for graph

   Two locking UPDATE statements A and B (SET c = c + 1) both read rows 1..NR (one page). The plan of each is
   "key" (key order) or "heap" (bitmap heap step). Rows have key order 1..NR and heap order NR..1. Both take
   their snapshot before anything runs (every row has c = 0 and is in range in it). W is a single-row writer
   (UPDATE or DELETE by primary key) of WRow: it locks the row, write-latches the page and either moves the
   row's key out of the range ("move"), adds 10 to c ("bump") or deletes the row ("delete").

   Iso: "rc" (READ COMMITTED: a row changed after the snapshot is reevaluated on its last version) or "rr"
   (REPEATABLE READ and above: such a row is a serialization conflict, the statement fails).

   Mutant re-enables one wrong ordering or missing check:
   - keep_latch  the statement keeps its page latch while it waits for the row lock
   - no_reev     the statement keeps a row without reevaluating the range on the last version
   - stale_set   the statement writes the value computed from its snapshot version (no recompute)
   - rr_skip     above RC, a changed row is skipped as RC does instead of failing the statement
   - unsorted    B's heap step order differs from A's (sectors not sorted) *)
EXTENDS Naturals, FiniteSets

CONSTANTS NR, WRow, PlanA, PlanB, Iso, Mutant

\* apalache-type: NR Int
\* apalache-type: WRow Int
\* apalache-type: PlanA Str
\* apalache-type: PlanB Str
\* apalache-type: Iso Str
\* apalache-type: Mutant Str
\* apalache-type: pc Str -> Str
\* apalache-type: pos Str -> Int
\* apalache-type: owner Int -> Str
\* apalache-type: wl Str -> Int
\* apalache-type: readers Set(Str)
\* apalache-type: wlatch Str
\* apalache-type: wkind Str
\* apalache-type: inr Int -> Bool
\* apalache-type: del Int -> Bool
\* apalache-type: cval Int -> Int
\* apalache-type: lastw Int -> Str
\* apalache-type: marked Str -> Set(Int)
\* apalache-type: rejected Set(Int)
\* apalache-type: bad Bool
\* apalache-type: lost Bool
\* apalache-type: rrbad Bool
\* apalache-type: victims Set(Str)

Rows == 1..NR
Stmts == {"A", "B"}
Procs == {"A", "B", "W"}
None == "none"
Plans == {"key", "heap"}
Mutants == {"none", "keep_latch", "no_reev", "stale_set", "rr_skip", "unsorted"}
WKinds == {"move", "bump", "delete"}
SPc == {"fix", "try", "wait", "eval", "commit", "done", "victim", "failed"}
WPc == {"lock", "wait", "latch", "mod", "commit", "done", "victim"}
Ended == {"done", "victim", "failed"}

ASSUME Assm == /\ NR \in Nat \ {0, 1} /\ WRow \in 1..NR /\ PlanA \in Plans /\ PlanB \in Plans
               /\ Iso \in {"rc", "rr"} /\ Mutant \in Mutants

CInit == /\ NR = 2 /\ WRow \in 1..2 /\ PlanA \in Plans /\ PlanB \in Plans /\ Iso \in {"rc", "rr"}
         /\ Mutant = "none"

VARIABLES pc, pos, owner, wl, readers, wlatch, wkind, inr, del, cval, lastw, marked, rejected, bad, lost, rrbad,
          victims
vars == <<pc, pos, owner, wl, readers, wlatch, wkind, inr, del, cval, lastw, marked, rejected, bad, lost, rrbad,
          victims>>

Plan(s) == IF s = "A" THEN PlanA ELSE PlanB

\* the row at position k of statement s's lock order
OrdOf(s, k) ==
  IF Plan(s) = "key" THEN k
  ELSE IF Mutant = "unsorted" /\ s = "B" THEN k
  ELSE NR + 1 - k

Row(s) == OrdOf(s, pos[s])

\* the last version of r is not the one s's snapshot sees (every snapshot is taken before anything runs)
Changed(s, r) == lastw[r] \notin {None, s}

\* lock manager's waits-for graph: lock waits only (a latch wait is not in it)
WaitsFor(p, q) == pc[p] = "wait" /\ wl[p] \in Rows /\ owner[wl[p]] = q

InCycle(p) ==
  \E q \in Procs : WaitsFor(p, q) /\ (WaitsFor(q, p) \/ \E u \in Procs : WaitsFor(q, u) /\ WaitsFor(u, p))

Release(p) == [r \in Rows |-> IF owner[r] = p THEN None ELSE owner[r]]

Init ==
  /\ pc = [p \in Procs |-> IF p = "W" THEN "lock" ELSE "fix"]
  /\ pos = [p \in Procs |-> 1]
  /\ owner = [r \in Rows |-> None]
  /\ wl = [p \in Procs |-> 0]
  /\ readers = {}
  /\ wlatch = None
  /\ wkind \in WKinds
  /\ inr = [r \in Rows |-> TRUE]
  /\ del = [r \in Rows |-> FALSE]
  /\ cval = [r \in Rows |-> 0]
  /\ lastw = [r \in Rows |-> None]
  /\ marked = [p \in Procs |-> {}]
  /\ rejected = {}
  /\ bad = FALSE
  /\ lost = FALSE
  /\ rrbad = FALSE
  /\ victims = {}

Fixed == <<wkind, inr, del, cval, lastw, marked, rejected, bad, lost, rrbad>>

(* scan_fix_bitmap_heap_page / the key-order lookup's heap fix: read latch on the page *)
SFix(s) ==
  /\ pc[s] = "fix" /\ wlatch = None
  /\ readers' = readers \cup {s}
  /\ pc' = [pc EXCEPT ![s] = "try"]
  /\ UNCHANGED <<pos, owner, wl, wlatch, victims>> /\ UNCHANGED Fixed

(* locator_lock_and_get_object_internal: LK_COND_LOCK; on failure locator_lock_object_unless_ours unfixes the
   home page and waits (LK_UNCOND_LOCK) *)
STry(s) ==
  LET r == Row(s) IN
  /\ pc[s] = "try"
  /\ IF owner[r] \in {None, s}
       THEN /\ owner' = [owner EXCEPT ![r] = s]
            /\ pc' = [pc EXCEPT ![s] = "eval"]
            /\ UNCHANGED <<wl, readers>>
       ELSE /\ wl' = [wl EXCEPT ![s] = r]
            /\ pc' = [pc EXCEPT ![s] = "wait"]
            /\ readers' = IF Mutant = "keep_latch" THEN readers ELSE readers \ {s}
            /\ UNCHANGED owner
  /\ UNCHANGED <<pos, wlatch, victims>> /\ UNCHANGED Fixed

(* granted after the wait; heap_prepare_get_context fixes the page again (SFix) *)
SWait(s) ==
  /\ pc[s] = "wait" /\ wl[s] \in Rows /\ owner[wl[s]] = None
  /\ owner' = [owner EXCEPT ![wl[s]] = s]
  /\ wl' = [wl EXCEPT ![s] = 0]
  /\ pc' = [pc EXCEPT ![s] = IF s \in readers THEN "eval" ELSE "fix"]
  /\ UNCHANGED <<pos, readers, wlatch, victims>> /\ UNCHANGED Fixed

(* the last version, locked: above RC a version changed after the snapshot fails the statement
   (locator_has_isolation_conflict); at RC a deleted row or one whose last version fails the range is skipped and
   unlocked, otherwise c is computed again from the last version (must_recompute) *)
SEval(s) ==
  LET r == Row(s)
      conflict == Iso = "rr" /\ Changed(s, r) /\ Mutant /= "rr_skip"
      keep == ~del[r] /\ (inr[r] \/ Mutant = "no_reev")
      newc == IF Mutant = "stale_set" THEN 1 ELSE cval[r] + 1
  IN
  /\ pc[s] = "eval"
  /\ IF conflict
       THEN /\ pc' = [pc EXCEPT ![s] = "failed"]
            /\ owner' = Release(s)
            /\ readers' = readers \ {s}
            /\ UNCHANGED <<pos, marked, rejected, bad, lost, rrbad, cval, lastw>>
       ELSE /\ marked' = IF keep THEN [marked EXCEPT ![s] = @ \cup {r}] ELSE marked
            /\ rejected' = IF keep THEN rejected ELSE rejected \cup {r}
            /\ bad' = (bad \/ (keep /\ ~inr[r]))
            /\ lost' = (lost \/ (keep /\ newc /= cval[r] + 1))
            /\ rrbad' = (rrbad \/ (keep /\ Iso = "rr" /\ Changed(s, r)))
            /\ cval' = IF keep THEN [cval EXCEPT ![r] = newc] ELSE cval
            /\ lastw' = IF keep THEN [lastw EXCEPT ![r] = s] ELSE lastw
            /\ owner' = IF keep THEN owner ELSE [owner EXCEPT ![r] = None]
            /\ readers' = readers \ {s}
            /\ pos' = [pos EXCEPT ![s] = @ + 1]
            /\ pc' = [pc EXCEPT ![s] = IF pos[s] = NR THEN "commit" ELSE "fix"]
  /\ UNCHANGED <<wl, wlatch, wkind, inr, del, victims>>

SCommit(s) ==
  /\ pc[s] = "commit"
  /\ owner' = Release(s)
  /\ pc' = [pc EXCEPT ![s] = "done"]
  /\ UNCHANGED <<pos, wl, readers, wlatch, victims>> /\ UNCHANGED Fixed

WLock ==
  /\ pc["W"] = "lock"
  /\ IF owner[WRow] = None
       THEN /\ owner' = [owner EXCEPT ![WRow] = "W"]
            /\ pc' = [pc EXCEPT !["W"] = "latch"]
            /\ UNCHANGED wl
       ELSE /\ wl' = [wl EXCEPT !["W"] = WRow]
            /\ pc' = [pc EXCEPT !["W"] = "wait"]
            /\ UNCHANGED owner
  /\ UNCHANGED <<pos, readers, wlatch, victims>> /\ UNCHANGED Fixed

WWait ==
  /\ pc["W"] = "wait" /\ owner[WRow] = None
  /\ owner' = [owner EXCEPT ![WRow] = "W"]
  /\ wl' = [wl EXCEPT !["W"] = 0]
  /\ pc' = [pc EXCEPT !["W"] = "latch"]
  /\ UNCHANGED <<pos, readers, wlatch, victims>> /\ UNCHANGED Fixed

(* heap_update / heap_delete: write latch on the row's page *)
WLatch ==
  /\ pc["W"] = "latch" /\ readers = {} /\ wlatch = None
  /\ wlatch' = "W"
  /\ pc' = [pc EXCEPT !["W"] = "mod"]
  /\ UNCHANGED <<pos, owner, wl, readers, victims>> /\ UNCHANGED Fixed

WMod ==
  /\ pc["W"] = "mod"
  /\ inr' = IF wkind = "move" THEN [inr EXCEPT ![WRow] = FALSE] ELSE inr
  /\ del' = IF wkind = "delete" THEN [del EXCEPT ![WRow] = TRUE] ELSE del
  /\ cval' = IF wkind = "bump" THEN [cval EXCEPT ![WRow] = @ + 10] ELSE cval
  /\ lastw' = [lastw EXCEPT ![WRow] = "W"]
  /\ wlatch' = None
  /\ pc' = [pc EXCEPT !["W"] = "commit"]
  /\ UNCHANGED <<pos, owner, wl, readers, wkind, marked, rejected, bad, lost, rrbad, victims>>

WCommit ==
  /\ pc["W"] = "commit"
  /\ owner' = Release("W")
  /\ pc' = [pc EXCEPT !["W"] = "done"]
  /\ UNCHANGED <<pos, wl, readers, wlatch, victims>> /\ UNCHANGED Fixed

(* lock_manager.c: a cycle of lock waits; the victim's transaction is rolled back and its locks released *)
Victim(p) ==
  /\ InCycle(p)
  /\ victims' = victims \cup {p}
  /\ owner' = Release(p)
  /\ wl' = [wl EXCEPT ![p] = 0]
  /\ readers' = readers \ {p}
  /\ pc' = [pc EXCEPT ![p] = "victim"]
  /\ UNCHANGED <<pos, wlatch>> /\ UNCHANGED Fixed

Terminated == \A p \in Procs : pc[p] \in Ended

Next ==
  \/ \E s \in Stmts : SFix(s) \/ STry(s) \/ SWait(s) \/ SEval(s) \/ SCommit(s)
  \/ WLock \/ WWait \/ WLatch \/ WMod \/ WCommit
  \/ \E p \in Procs : Victim(p)
  \/ (Terminated /\ UNCHANGED vars)

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
TypeOK ==
  /\ pc \in [Procs -> SPc \cup WPc]
  /\ \A s \in Stmts : pc[s] \in SPc
  /\ pc["W"] \in WPc
  /\ pos \in [Procs -> 1..(NR + 1)]
  /\ owner \in [Rows -> Procs \cup {None}]
  /\ wl \in [Procs -> 0..NR]
  /\ readers \in SUBSET Stmts
  /\ wlatch \in {None, "W"}
  /\ wkind \in WKinds
  /\ inr \in [Rows -> BOOLEAN]
  /\ del \in [Rows -> BOOLEAN]
  /\ cval \in [Rows -> 0..12]
  /\ lastw \in [Rows -> Procs \cup {None}]
  /\ marked \in [Procs -> SUBSET Rows]
  /\ rejected \in SUBSET Rows
  /\ bad \in BOOLEAN
  /\ lost \in BOOLEAN
  /\ rrbad \in BOOLEAN
  /\ victims \in SUBSET Procs

(* C1: no statement holds a page latch while it waits for a row lock (a latch wait is invisible to the
   deadlock detector, so such a wait could hang both sides) *)
NoLatchWhileWait == \A s \in Stmts : pc[s] = "wait" => s \notin readers

(* C2: two statements whose plans both lock in the heap step's order never make a lock cycle with each other *)
SamePlanNoVictim == PlanA = PlanB => victims = {}

(* C3a: at RC a statement never keeps a row whose last version left the range *)
NoBadKeep == ~bad

(* C3b: a statement writes c from the last version it locked, never from its snapshot (no lost update) *)
NoLostUpdate == ~lost

(* C3c: above RC a statement never writes a row another transaction changed after its snapshot *)
RrConflictKept == ~rrbad

\* witnesses
NoVictim == victims = {}
NotRejected == rejected = {}
NotBothDone == ~(pc["A"] = "done" /\ pc["B"] = "done" /\ pc["W"] = "done")
NotRecomputed == ~(\E r \in Rows : cval[r] = 11)
NotConflict == ~(\E s \in Stmts : pc[s] = "failed")
NotDeletedSkip == ~(\E r \in Rows : del[r] /\ r \in rejected)

-----------------------------------------------------------------------------
(* inductive invariant; Mutant = "none" *)
WaitShape ==
  /\ \A p \in Procs : (pc[p] = "wait") <=> (wl[p] \in Rows)
  /\ \A s \in Stmts : pc[s] = "wait" => wl[s] = Row(s) /\ owner[wl[s]] /= s
  /\ pc["W"] = "wait" => wl["W"] = WRow /\ owner[WRow] /= "W"

PosShape ==
  /\ \A s \in Stmts : pc[s] \in {"fix", "try", "wait", "eval"} => pos[s] \in 1..NR
  /\ \A s \in Stmts : pc[s] = "commit" => pos[s] = NR + 1
  /\ pos["W"] = 1

LatchShape ==
  /\ \A s \in readers : pc[s] \in {"try", "eval"}
  /\ \A s \in Stmts : pc[s] \in {"try", "eval"} => s \in readers
  /\ wlatch = "W" => pc["W"] = "mod" /\ readers = {}
  /\ pc["W"] = "mod" => wlatch = "W"

(* a statement owns only rows of its order before its position, or the row at its position, granted after a wait
   (then fixing the page again) or evaluated *)
OwnedPrefix ==
  \A r \in Rows : \A s \in Stmts :
    owner[r] = s =>
      /\ pc[s] \in {"fix", "try", "wait", "eval", "commit"}
      /\ \E k \in 1..NR : OrdOf(s, k) = r /\ (k < pos[s] \/ (k = pos[s] /\ pc[s] \in {"fix", "try", "eval"}))

EvalOwns == \A s \in Stmts : pc[s] = "eval" => owner[Row(s)] = s

WOwns ==
  /\ \A r \in Rows : owner[r] = "W" => r = WRow /\ pc["W"] \in {"latch", "mod", "commit"}
  /\ pc["W"] \in {"latch", "mod", "commit"} => owner[WRow] = "W"

NoOwnerEnded == \A r \in Rows : owner[r] \notin {p \in Procs : pc[p] \in Ended}

(* W changes only WRow; c grows by one per statement that passed the row and by 10 for a committed bump *)
Passed(s, r) == \E k \in 1..NR : OrdOf(s, k) = r /\ k < pos[s]

Bumped(r) == r = WRow /\ wkind = "bump" /\ pc["W"] \in {"commit", "done"}

WriteShape ==
  /\ \A r \in Rows : r /= WRow => inr[r] /\ ~del[r] /\ lastw[r] /= "W"
  /\ ~inr[WRow] => wkind = "move" /\ pc["W"] \in {"commit", "done"}
  /\ del[WRow] => wkind = "delete" /\ pc["W"] \in {"commit", "done"}
  /\ \A r \in Rows : cval[r] <= (IF Passed("A", r) THEN 1 ELSE 0) + (IF Passed("B", r) THEN 1 ELSE 0)
                                 + (IF Bumped(r) THEN 10 ELSE 0)

NoSamePlanCycle == PlanA = PlanB => \A p \in Procs : ~InCycle(p)

IndInv ==
  /\ TypeOK
  /\ WaitShape
  /\ PosShape
  /\ LatchShape
  /\ OwnedPrefix
  /\ EvalOwns
  /\ WOwns
  /\ NoOwnerEnded
  /\ WriteShape
  /\ NoLatchWhileWait
  /\ NoSamePlanCycle
  /\ SamePlanNoVictim
  /\ NoBadKeep
  /\ NoLostUpdate
  /\ RrConflictKept
=============================================================================
