--------------------------- MODULE SectorScan ---------------------------
(***************************************************************************)
(* The sector-based heap scan (CBRD-28043).                                *)
(*                                                                         *)
(* At open every query heap scan takes the statement's snapshot, then      *)
(* collects the file's page bitmap: every page the file table marks        *)
(* allocated, the file table pages included, read under the file header   *)
(* latch.  Outside the latch it removes the file table pages it saw (D4).  *)
(* From the bitmap's page count it decides once whether the scan runs in  *)
(* parallel (two workers here) or serially (one), and both walk the same  *)
(* bitmap in file order (D9): a worker takes the next page from the shared *)
(* cursor, releases the page it holds, fixes the taken page as "maybe      *)
(* deallocated", skips a page that is no longer a heap page of this table, *)
(* and otherwise returns the rows of the page its snapshot sees.  The scan *)
(* ends when every worker has ended (the manager's join).  A rewind walks  *)
(* the same bitmap again with the same decision (D5, D13).                 *)
(*                                                                         *)
(* Meanwhile other transactions insert rows (into a page with room or into *)
(* a newly allocated page: the lowest free page, as file_perm_alloc takes  *)
(* the first partial sector), delete rows, vacuum removes rows no active  *)
(* snapshot sees and frees a heap page it emptied, and the file table may *)
(* grow by one page taken the same way.                                    *)
(*                                                                         *)
(* Claims (MAP.md): C1 every row the start snapshot sees is returned and   *)
(* no other row; C2 no row twice; C3 no page held when the scan ends; C4   *)
(* the scan ends; C5 a page that is not a heap page of this table is never *)
(* read as one.                                                            *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS N,          \* pages of the file, in file order 1..N; page 1 is the file header (a file table page)
          MaxRow,     \* row ids 1..MaxRow; rows 1..3 exist at the start
          Cap,        \* rows a heap page holds
          MaxRewind,  \* rewinds of the scan (inner of a nested loop)
          MaxErrors,  \* errors or interrupts in a run
          Mutant      \* "none" or one wrong variant below

\* Mutant: "late_snapshot" | "revisit" | "no_release" | "fix_freed" | "assert_heap"
\*         | "no_visibility" | "rewind_keep_cur" | "no_dedup_assert_heap" | "no_shared_cursor"

\* apalache-type: N Int
\* apalache-type: MaxRow Int
\* apalache-type: Cap Int
\* apalache-type: MaxRewind Int
\* apalache-type: MaxErrors Int
\* apalache-type: Mutant Str
\* apalache-type: ptype Int -> Str
\* apalache-type: rows Int -> Set(Int)
\* apalache-type: live Set(Int)
\* apalache-type: nextRow Int
\* apalache-type: grown Bool
\* apalache-type: snapVis Set(Int)
\* apalache-type: list Set(Int)
\* apalache-type: ftabSnap Set(Int)
\* apalache-type: phase Str
\* apalache-type: mode Str
\* apalache-type: taken Int
\* apalache-type: wpc Int -> Str
\* apalache-type: cur Int -> Int
\* apalache-type: held Int -> Int
\* apalache-type: out Int -> Int
\* apalache-type: aborted Bool
\* apalache-type: errs Int
\* apalache-type: rew Int
\* apalache-type: badFix Bool
\* apalache-type: wasFreed Set(Int)
\* apalache-type: skippedFreed Bool
\* apalache-type: skippedForeign Bool
\* apalache-type: reusedRead Bool
\* apalache-type: readBy Set(Int)

CInit ==
  /\ N = 5
  /\ MaxRow = 5
  /\ Cap = 2
  /\ MaxRewind \in Nat
  /\ MaxErrors \in Nat
  /\ Mutant = "none"

VARIABLES ptype,     \* page -> "heap" | "ftab" | "free"
          rows,      \* page -> the row versions on it
          live,      \* rows inserted and not deleted (committed)
          nextRow,   \* id of the next inserted row
          grown,     \* the file table has grown by a page
          snapVis,   \* rows the scan's snapshot sees
          list,      \* the scan's page bitmap (pages)
          ftabSnap,  \* the file table pages seen with the bitmap
          phase,     \* "open" | "snapped" | "dedup" | "snaplate" | "decide" | "walk" | "done"
          mode,      \* "none" until the decision, then "serial" | "parallel"
          taken,     \* the shared cursor: the last listed page handed to a worker (0 = none)
          wpc,       \* worker -> "idle" | "pick" | "release" | "fix" | "read" | "end" | "done"
          cur,       \* worker -> the page it took (0 = none)
          held,      \* worker -> the page it holds (0 = none)
          out,       \* row -> times returned in this pass (capped at 2)
          aborted,   \* the scan stopped on an error
          errs,      \* errors so far
          rew,       \* rewinds so far
          badFix,    \* ghost: a page that is not a heap page was read as one
          wasFreed,  \* ghost: pages freed after the bitmap was taken
          skippedFreed,   \* ghost: a worker skipped a freed page
          skippedForeign, \* ghost: a worker skipped a page reused as a file table page
          reusedRead,     \* ghost: a worker read a page freed and reallocated after the bitmap
          readBy          \* ghost: workers that read a page in this run

vars == <<ptype, rows, live, nextRow, grown, snapVis, list, ftabSnap, phase, mode, taken, wpc, cur, held, out,
          aborted, errs, rew, badFix, wasFreed, skippedFreed, skippedForeign, reusedRead, readBy>>
scanVars == <<snapVis, list, ftabSnap, phase, mode, taken, wpc, cur, held, out, aborted, errs, rew, badFix,
              wasFreed, skippedFreed, skippedForeign, reusedRead, readBy>>
envVars == <<ptype, rows, live, nextRow, grown>>

Pages == 1..N
Rows == 1..MaxRow
W == {1, 2}
PhaseValues == {"open", "snapped", "dedup", "snaplate", "decide", "walk", "done"}
WpcValues == {"idle", "pick", "release", "fix", "read", "end", "done"}
HeldPages == {held[w] : w \in W}
\* the worker took a page whose rows it has not read yet
Pending(w) == wpc[w] \in {"release", "fix", "read"}

(* the table at the start:                                                 *)
(*   page 1 file header (file table page)                                  *)
(*   page 2 heap: r1 live                                                  *)
(*   page 3 heap: r2 deleted before the scan (vacuum may remove it, then   *)
(*          free the page)                                                 *)
(*   page 4 free (reserved sector, not allocated)                          *)
(*   page 5 heap: r3 live                                                  *)
(*   page 6.. free (scale)                                                 *)
Init ==
  /\ ptype = [p \in Pages |-> IF p = 1 THEN "ftab" ELSE IF p \in {2, 3, 5} THEN "heap" ELSE "free"]
  /\ rows = [p \in Pages |-> IF p = 2 THEN {1} ELSE IF p = 3 THEN {2} ELSE IF p = 5 THEN {3} ELSE {}]
  /\ live = {1, 3}
  /\ nextRow = 4
  /\ grown = FALSE
  /\ snapVis = {}
  /\ list = {}
  /\ ftabSnap = {}
  /\ phase = "open"
  /\ mode = "none"
  /\ taken = 0
  /\ wpc = [w \in W |-> "idle"]
  /\ cur = [w \in W |-> 0]
  /\ held = [w \in W |-> 0]
  /\ out = [r \in Rows |-> 0]
  /\ aborted = FALSE
  /\ errs = 0
  /\ rew = 0
  /\ badFix = FALSE
  /\ wasFreed = {}
  /\ skippedFreed = FALSE
  /\ skippedForeign = FALSE
  /\ reusedRead = FALSE
  /\ readBy = {}

IsLowestFree(p) == ptype[p] = "free" /\ \A q \in Pages : ptype[q] = "free" => p <= q

(*************************** the environment ******************************)

\* insert + commit of one row into a heap page with room (page write latch: not a held page)
InsertInto(p) ==
  /\ nextRow <= MaxRow
  /\ ptype[p] = "heap" /\ p \notin HeldPages /\ Cardinality(rows[p]) < Cap
  /\ rows' = [rows EXCEPT ![p] = @ \cup {nextRow}]
  /\ live' = live \cup {nextRow}
  /\ nextRow' = nextRow + 1
  /\ UNCHANGED <<ptype, grown>>
  /\ UNCHANGED scanVars

\* insert + commit of one row into a new heap page: file_alloc (header write latch) takes the lowest free page
InsertNewPage(p) ==
  /\ nextRow <= MaxRow
  /\ IsLowestFree(p)
  /\ ptype' = [ptype EXCEPT ![p] = "heap"]
  /\ rows' = [rows EXCEPT ![p] = {nextRow}]
  /\ live' = live \cup {nextRow}
  /\ nextRow' = nextRow + 1
  /\ UNCHANGED grown
  /\ UNCHANGED scanVars

\* delete + commit of a row that existed at the start (a row inserted during the scan is invisible to it
\* either way; deleting it adds states, not cases): the version stays on its page until vacuum
Delete(r, p) ==
  /\ r \in {1, 3} /\ r \in live /\ r \in rows[p] /\ p \notin HeldPages
  /\ live' = live \ {r}
  /\ UNCHANGED <<ptype, rows, nextRow, grown>>
  /\ UNCHANGED scanVars

\* vacuum removes a deleted version no active snapshot sees (environment assumption A1)
Vacuum(r, p) ==
  /\ r \in rows[p] /\ r \notin live /\ r \notin snapVis /\ p \notin HeldPages
  /\ rows' = [rows EXCEPT ![p] = @ \ {r}]
  /\ UNCHANGED <<ptype, live, nextRow, grown>>
  /\ UNCHANGED scanVars

\* vacuum frees a heap page it emptied (file_dealloc under the header write latch)
FreePage(p) ==
  /\ ptype[p] = "heap" /\ rows[p] = {} /\ p \notin HeldPages
  /\ ptype' = [ptype EXCEPT ![p] = "free"]
  /\ wasFreed' = IF phase \in {"open", "snapped"} THEN wasFreed ELSE wasFreed \cup {p}
  /\ UNCHANGED <<rows, live, nextRow, grown>>
  /\ UNCHANGED <<snapVis, list, ftabSnap, phase, mode, taken, wpc, cur, held, out, aborted, errs, rew, badFix,
                 skippedFreed, skippedForeign, reusedRead, readBy>>

\* the file table grows by one page, taken from the first partial sector (file_manager.c:5025, :6468)
GrowFtab(p) ==
  /\ ~grown
  /\ IsLowestFree(p)
  /\ ptype' = [ptype EXCEPT ![p] = "ftab"]
  /\ grown' = TRUE
  /\ UNCHANGED <<rows, live, nextRow>>
  /\ UNCHANGED scanVars

Env ==
  \/ \E p \in Pages : InsertInto(p) \/ InsertNewPage(p) \/ FreePage(p) \/ GrowFtab(p)
  \/ \E r \in Rows, p \in Pages : Delete(r, p) \/ Vacuum(r, p)

(****************************** the open **********************************)

\* the statement's snapshot (before the bitmap; after it in mutant late_snapshot)
TakeSnapshot ==
  /\ \/ Mutant # "late_snapshot" /\ phase = "open" /\ phase' = "snapped"
     \/ Mutant = "late_snapshot" /\ phase = "snaplate" /\ phase' = "decide"
  /\ snapVis' = live
  /\ UNCHANGED <<list, ftabSnap, mode, taken, wpc, cur, held, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead, readBy>>
  /\ UNCHANGED envVars

\* file_get_all_data_sectors: the header read latch blocks every alloc and dealloc, so one step
CollectList ==
  /\ \/ Mutant # "late_snapshot" /\ phase = "snapped"
     \/ Mutant = "late_snapshot" /\ phase = "open"
  /\ list' = {p \in Pages : ptype[p] # "free"}
  /\ ftabSnap' = {p \in Pages : ptype[p] = "ftab"}
  /\ phase' = "dedup"
  /\ UNCHANGED <<snapVis, mode, taken, wpc, cur, held, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead, readBy>>
  /\ UNCHANGED envVars

\* the file table pages leave the bitmap after the header latch is released (D4)
Dedup ==
  /\ phase = "dedup"
  /\ list' = IF Mutant = "no_dedup_assert_heap" THEN list ELSE list \ ftabSnap
  /\ phase' = IF Mutant = "late_snapshot" THEN "snaplate" ELSE "decide"
  /\ UNCHANGED <<snapVis, ftabSnap, mode, taken, wpc, cur, held, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead, readBy>>
  /\ UNCHANGED envVars

\* parallel or serial, decided once from the bitmap's page count (any outcome: the count is not modeled)
Decide ==
  /\ phase = "decide"
  /\ \E m \in {"serial", "parallel"} :
       /\ mode' = m
       /\ wpc' = [w \in W |-> IF w = 1 \/ m = "parallel" THEN "pick" ELSE "idle"]
  /\ phase' = "walk"
  /\ UNCHANGED <<snapVis, list, ftabSnap, taken, cur, held, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead, readBy>>
  /\ UNCHANGED envVars

(****************************** the walk **********************************)

\* the next listed page after the shared cursor, taken atomically (the serial scan's cursor, the parallel
\* workers' sector sets); an error elsewhere stops the worker
Pick(w) ==
  /\ phase = "walk" /\ wpc[w] = "pick"
  /\ IF aborted
     THEN /\ wpc' = [wpc EXCEPT ![w] = "end"]
          /\ UNCHANGED <<taken, cur>>
     ELSE LET base == IF Mutant = "no_shared_cursor" THEN cur[w] ELSE taken
              after == {p \in list : IF Mutant = "revisit" THEN p >= base ELSE p > base}
          IN IF after = {}
             THEN /\ wpc' = [wpc EXCEPT ![w] = "end"]
                  /\ UNCHANGED <<taken, cur>>
             ELSE \E p \in after :
                    /\ \A q \in after : p <= q
                    /\ cur' = [cur EXCEPT ![w] = p]
                    /\ taken' = IF Mutant = "no_shared_cursor" THEN (IF p > taken THEN p ELSE taken) ELSE p
                    /\ wpc' = [wpc EXCEPT ![w] = "release"]
  /\ UNCHANGED <<snapVis, list, ftabSnap, phase, mode, held, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead, readBy>>
  /\ UNCHANGED envVars

\* the held page goes before the next one is fixed (holding a page while waiting deadlocks with vacuum)
Release(w) ==
  /\ phase = "walk" /\ wpc[w] = "release"
  /\ held' = [held EXCEPT ![w] = 0]
  /\ wpc' = [wpc EXCEPT ![w] = "fix"]
  /\ UNCHANGED <<snapVis, list, ftabSnap, phase, mode, taken, cur, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead, readBy>>
  /\ UNCHANGED envVars

\* pgbuf_ordered_fix (OLD_PAGE_MAYBE_DEALLOCATED): a freed page and a page allocated again as another type
\* both come back as not fixed (pgbuf_ordered_unfix_reused_page ()) and are skipped
Fix(w) ==
  /\ phase = "walk" /\ wpc[w] = "fix"
  /\ LET p == cur[w] IN
       IF ptype[p] = "heap"
       THEN /\ held' = [held EXCEPT ![w] = p]
            /\ wpc' = [wpc EXCEPT ![w] = "read"]
            /\ UNCHANGED <<badFix, skippedFreed, skippedForeign>>
       ELSE IF ptype[p] = "free"
       THEN /\ IF Mutant = "fix_freed"
               THEN /\ badFix' = TRUE /\ held' = [held EXCEPT ![w] = p] /\ wpc' = [wpc EXCEPT ![w] = "read"]
               ELSE /\ UNCHANGED <<badFix, held>> /\ wpc' = [wpc EXCEPT ![w] = "pick"]
            /\ skippedFreed' = TRUE
            /\ UNCHANGED skippedForeign
       ELSE /\ IF Mutant \in {"assert_heap", "no_dedup_assert_heap"}
               THEN /\ badFix' = TRUE /\ held' = [held EXCEPT ![w] = p] /\ wpc' = [wpc EXCEPT ![w] = "read"]
               ELSE /\ UNCHANGED <<badFix, held>> /\ wpc' = [wpc EXCEPT ![w] = "pick"]
            /\ skippedForeign' = TRUE
            /\ UNCHANGED skippedFreed
  /\ UNCHANGED <<snapVis, list, ftabSnap, phase, mode, taken, cur, out, aborted, errs, rew, wasFreed, reusedRead,
                 readBy>>
  /\ UNCHANGED envVars

\* the rows of the held page the snapshot sees, page latch held: one step
Read(w) ==
  /\ phase = "walk" /\ wpc[w] = "read"
  /\ LET p == cur[w]
         got == IF Mutant = "no_visibility" THEN rows[p] ELSE rows[p] \cap snapVis
     IN /\ out' = [r \in Rows |-> IF r \in got THEN IF out[r] >= 2 THEN 2 ELSE out[r] + 1 ELSE out[r]]
        /\ reusedRead' = (reusedRead \/ p \in wasFreed)
  /\ readBy' = readBy \cup {w}
  /\ wpc' = [wpc EXCEPT ![w] = "pick"]
  /\ UNCHANGED <<snapVis, list, ftabSnap, phase, mode, taken, cur, held, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign>>
  /\ UNCHANGED envVars

\* the worker ends (the bitmap is done or the scan is stopping): its page goes
Finish(w) ==
  /\ phase = "walk" /\ wpc[w] = "end"
  /\ held' = IF Mutant = "no_release" THEN held ELSE [held EXCEPT ![w] = 0]
  /\ wpc' = [wpc EXCEPT ![w] = "done"]
  /\ UNCHANGED <<snapVis, list, ftabSnap, phase, mode, taken, cur, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead, readBy>>
  /\ UNCHANGED envVars

\* an error or an interrupt in a worker; the others stop at their next pick (the parallel interrupt)
Abort(w) ==
  /\ phase = "walk" /\ wpc[w] \in {"pick", "release", "fix", "read"}
  /\ errs < MaxErrors
  /\ errs' = errs + 1
  /\ aborted' = TRUE
  /\ wpc' = [wpc EXCEPT ![w] = "end"]
  /\ UNCHANGED <<snapVis, list, ftabSnap, phase, mode, taken, cur, held, out, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead, readBy>>
  /\ UNCHANGED envVars

\* the scan ends when every worker has ended (the manager joins its workers)
Join ==
  /\ phase = "walk"
  /\ \A w \in W : wpc[w] \in {"done", "idle"}
  /\ phase' = "done"
  /\ UNCHANGED <<snapVis, list, ftabSnap, mode, taken, wpc, cur, held, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead, readBy>>
  /\ UNCHANGED envVars

\* the scan opened again with the same snapshot walks the same bitmap with the same decision (D5, D13)
Rewind ==
  /\ phase = "done" /\ ~aborted /\ rew < MaxRewind
  /\ rew' = rew + 1
  /\ taken' = IF Mutant = "rewind_keep_cur" THEN taken ELSE 0
  /\ cur' = [w \in W |-> 0]
  /\ wpc' = [w \in W |-> IF w = 1 \/ mode = "parallel" THEN "pick" ELSE "idle"]
  /\ out' = [r \in Rows |-> 0]
  /\ readBy' = {}
  /\ phase' = "walk"
  /\ UNCHANGED <<snapVis, list, ftabSnap, mode, held, aborted, errs, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead>>
  /\ UNCHANGED envVars

ScanStep ==
  \/ TakeSnapshot \/ CollectList \/ Dedup \/ Decide \/ Join
  \/ \E w \in W : Pick(w) \/ Release(w) \/ Fix(w) \/ Read(w) \/ Finish(w)

\* nothing left to do (the environment's budget is spent): stutter instead of a false deadlock
Idle == phase = "done" /\ UNCHANGED vars

Next == Env \/ ScanStep \/ (\E w \in W : Abort(w)) \/ Rewind \/ Idle

Spec == Init /\ [][Next]_vars /\ WF_vars(ScanStep)

(****************************** properties ********************************)

OnSomePage(r) == \E p \in Pages : r \in rows[p]

TypeOK ==
  /\ ptype \in [Pages -> {"heap", "ftab", "free"}]
  /\ rows \in [Pages -> SUBSET Rows]
  /\ live \in SUBSET Rows
  /\ nextRow \in Int /\ 4 <= nextRow /\ nextRow <= MaxRow + 1
  /\ grown \in BOOLEAN
  /\ snapVis \in SUBSET Rows
  /\ list \in SUBSET Pages
  /\ ftabSnap \in SUBSET Pages
  /\ phase \in PhaseValues
  /\ mode \in {"none", "serial", "parallel"}
  /\ taken \in 0..N
  /\ wpc \in [W -> WpcValues]
  /\ cur \in [W -> 0..N]
  /\ held \in [W -> 0..N]
  /\ out \in [Rows -> 0..2]
  /\ aborted \in BOOLEAN
  /\ errs \in Int /\ 0 <= errs /\ errs <= MaxErrors
  /\ rew \in Int /\ 0 <= rew /\ rew <= MaxRewind
  /\ badFix \in BOOLEAN
  /\ wasFreed \in SUBSET Pages
  /\ skippedFreed \in BOOLEAN
  /\ skippedForeign \in BOOLEAN
  /\ reusedRead \in BOOLEAN
  /\ readBy \in SUBSET W

\* C1: nothing the snapshot does not see is returned ...
NoExtraRow == \A r \in Rows : out[r] > 0 => r \in snapVis
\* C1: ... and everything it sees is, when the pass ends without an error
AllRowsReturned == (phase = "done" /\ ~aborted) => \A r \in snapVis : out[r] >= 1
\* C2
NoDuplicate == \A r \in Rows : out[r] <= 1
\* C3
NoPageHeld == phase = "done" => \A w \in W : held[w] = 0
\* C5
NoForeignRead == ~badFix
\* C4
Ends == <>(phase = "done")

(******************************* witnesses ********************************)
NotFinished == ~(phase = "done" /\ ~aborted)
NotSerialFinished == ~(phase = "done" /\ ~aborted /\ mode = "serial")
NotParallelFinished == ~(phase = "done" /\ ~aborted /\ mode = "parallel" /\ readBy = W)
NotRewoundFinished == ~(phase = "done" /\ ~aborted /\ rew >= 1)
NotSkippedFreed == ~skippedFreed
NotSkippedForeign == ~skippedForeign
NotReusedRead == ~reusedRead
\* a row deleted after the snapshot is still returned
NotDeletedAfterSnapReturned == ~(\E r \in snapVis : r \notin live /\ out[r] = 1 /\ phase = "done")
\* a row inserted before the snapshot into a page allocated before the bitmap is returned
NotNewPageRowReturned == ~(\E r \in snapVis : r >= 4 /\ out[r] = 1 /\ ~(r \in rows[2] \/ r \in rows[5]))
NotAborted == ~(phase = "done" /\ aborted)

(************************** inductive invariant ***************************)

\* well-formedness of the table
RowsWellFormed ==
  /\ \A p \in Pages : ptype[p] # "heap" => rows[p] = {}
  /\ \A p, q \in Pages : p # q => rows[p] \cap rows[q] = {}
  /\ \A p \in Pages : \A r \in rows[p] : r < nextRow
  /\ \A p \in Pages : Cardinality(rows[p]) <= Cap
  /\ \A r \in live : OnSomePage(r)
  /\ \A r \in live : r < nextRow
  /\ ptype[1] = "ftab"
  /\ \A p \in Pages : (p # 1 /\ ptype[p] = "ftab") => grown

\* the open's phases and what each allows
OpenShape ==
  /\ phase \in {"open", "snapped", "dedup", "decide"} =>
       (/\ mode = "none" /\ taken = 0 /\ ~aborted /\ errs = 0 /\ rew = 0 /\ readBy = {}
        /\ \A w \in W : wpc[w] = "idle" /\ cur[w] = 0 /\ held[w] = 0)
  /\ phase \in {"open", "snapped"} => (list = {} /\ ftabSnap = {} /\ wasFreed = {})
  /\ phase = "open" => snapVis = {}
  /\ phase = "dedup" => (1 \in ftabSnap /\ ftabSnap \subseteq list)
  /\ phase = "snaplate" => FALSE
  /\ phase \in {"decide", "walk", "done"} => (list \cap ftabSnap = {} /\ 1 \in ftabSnap)
  /\ phase \in {"walk", "done"} => mode \in {"serial", "parallel"}
  /\ ftabSnap \subseteq {p \in Pages : ptype[p] = "ftab"}
  /\ \A r \in Rows : out[r] > 0 => phase \in {"walk", "done"}
  /\ ~badFix
  /\ aborted => errs >= 1

\* the workers
WalkShape ==
  /\ mode = "serial" => (wpc[2] = "idle" /\ cur[2] = 0 /\ held[2] = 0)
  /\ mode = "parallel" => \A w \in W : wpc[w] # "idle"
  /\ phase \in {"walk", "done"} => wpc[1] # "idle"
  /\ phase = "done" => \A w \in W : wpc[w] \in {"done", "idle"}
  /\ \A w \in W : wpc[w] = "idle" => (cur[w] = 0 /\ held[w] = 0)
  /\ \A w \in W : cur[w] # 0 => (cur[w] \in list /\ cur[w] <= taken)
  /\ \A w \in W : held[w] # 0 => (ptype[held[w]] = "heap" /\ held[w] \in list /\ held[w] <= cur[w])
  /\ \A w \in W : wpc[w] \in {"release", "fix", "read"} => cur[w] # 0
  /\ \A w \in W : wpc[w] = "fix" => held[w] = 0
  /\ \A w \in W : wpc[w] = "read" => held[w] = cur[w]
  /\ \A w \in W : wpc[w] = "done" => held[w] = 0
  /\ cur[1] # 0 /\ cur[2] # 0 => cur[1] # cur[2]
  /\ taken # 0 => taken \in list
  /\ \A w \in W : (wpc[w] \in {"end", "done"} /\ ~aborted) => \A p \in list : p <= taken

\* the snapshot's rows stay where they were, on heap pages of the bitmap
SnapRowsStay ==
  /\ \A r \in snapVis : r < nextRow
  /\ \A r \in snapVis : \E p \in Pages : r \in rows[p] /\ ptype[p] = "heap"
  /\ phase = "dedup" => \A r \in snapVis : \A p \in Pages : r \in rows[p] => (p \in list /\ p \notin ftabSnap)
  /\ phase \in {"decide", "walk", "done"} => \A r \in snapVis : \A p \in Pages : r \in rows[p] => p \in list

\* what this pass returned: the snapshot's rows on the pages handed out and read; without an error, exactly those
\* (an error ends a worker with its taken page unread)
OutExact ==
  /\ \A r \in Rows : r \notin snapVis => out[r] = 0
  /\ \A r \in snapVis : \A p \in Pages : r \in rows[p] =>
        /\ (\E w \in W : Pending(w) /\ cur[w] = p) => out[r] = 0
        /\ p > taken => out[r] = 0
        /\ ~aborted => out[r] = IF p <= taken /\ ~(\E w \in W : Pending(w) /\ cur[w] = p) THEN 1 ELSE 0

IndInv ==
  /\ TypeOK
  /\ RowsWellFormed
  /\ OpenShape
  /\ WalkShape
  /\ SnapRowsStay
  /\ OutExact
  /\ NoExtraRow
  /\ AllRowsReturned
  /\ NoDuplicate
  /\ NoPageHeld
  /\ NoForeignRead
=============================================================================
