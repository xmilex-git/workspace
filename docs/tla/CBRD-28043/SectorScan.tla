--------------------------- MODULE SectorScan ---------------------------
(***************************************************************************)
(* The serial heap full scan in sector order (CBRD-28043).                 *)
(*                                                                         *)
(* At open the scan takes the statement's snapshot, then collects the      *)
(* file's sector list: every page the file table marks allocated, the      *)
(* file table pages included, read under the file header latch.  Outside  *)
(* the latch it removes the file table pages it saw (D4).  It then walks   *)
(* the list in page order: it releases the page it holds, fixes the next   *)
(* listed page as "maybe deallocated", skips a page that is no longer a    *)
(* heap page of this table, and otherwise returns the rows of the page its *)
(* snapshot sees.  A rewind walks the same list again (D5).                *)
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
\*         | "no_visibility" | "rewind_keep_cur" | "no_dedup_assert_heap"

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
\* apalache-type: pc Str
\* apalache-type: cur Int
\* apalache-type: held Int
\* apalache-type: readCur Bool
\* apalache-type: out Int -> Int
\* apalache-type: aborted Bool
\* apalache-type: errs Int
\* apalache-type: rew Int
\* apalache-type: badFix Bool
\* apalache-type: wasFreed Set(Int)
\* apalache-type: skippedFreed Bool
\* apalache-type: skippedForeign Bool
\* apalache-type: reusedRead Bool

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
          list,      \* the scan's sector list (pages)
          ftabSnap,  \* the file table pages seen with the list
          pc,        \* scan step
          cur,       \* the listed page the walk is at (0 = before the first)
          held,      \* the page the scan holds (0 = none)
          readCur,   \* the rows of page cur were read
          out,       \* row -> times returned in this pass (capped at 2)
          aborted,   \* the scan stopped on an error
          errs,      \* errors so far
          rew,       \* rewinds so far
          badFix,    \* ghost: a page that is not a heap page was read as one
          wasFreed,  \* ghost: pages freed after the list was taken
          skippedFreed,   \* ghost: the walk skipped a freed page
          skippedForeign, \* ghost: the walk skipped a page reused as a file table page
          reusedRead      \* ghost: the walk read a page freed and reallocated after the list

vars == <<ptype, rows, live, nextRow, grown, snapVis, list, ftabSnap, pc, cur, held, readCur, out,
          aborted, errs, rew, badFix, wasFreed, skippedFreed, skippedForeign, reusedRead>>
scanVars == <<snapVis, list, ftabSnap, pc, cur, held, readCur, out, aborted, errs, rew, badFix,
              wasFreed, skippedFreed, skippedForeign, reusedRead>>
envVars == <<ptype, rows, live, nextRow, grown>>

Pages == 1..N
Rows == 1..MaxRow
PcValues == {"open", "snapped", "dedup", "snaplate", "pick", "release", "fix", "read", "end", "done"}

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
  /\ pc = "open"
  /\ cur = 0
  /\ held = 0
  /\ readCur = FALSE
  /\ out = [r \in Rows |-> 0]
  /\ aborted = FALSE
  /\ errs = 0
  /\ rew = 0
  /\ badFix = FALSE
  /\ wasFreed = {}
  /\ skippedFreed = FALSE
  /\ skippedForeign = FALSE
  /\ reusedRead = FALSE

IsLowestFree(p) == ptype[p] = "free" /\ \A q \in Pages : ptype[q] = "free" => p <= q

(*************************** the environment ******************************)

\* insert + commit of one row into a heap page with room (page write latch: not the held page)
InsertInto(p) ==
  /\ nextRow <= MaxRow
  /\ ptype[p] = "heap" /\ p # held /\ Cardinality(rows[p]) < Cap
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
  /\ r \in {1, 3} /\ r \in live /\ r \in rows[p] /\ p # held
  /\ live' = live \ {r}
  /\ UNCHANGED <<ptype, rows, nextRow, grown>>
  /\ UNCHANGED scanVars

\* vacuum removes a deleted version no active snapshot sees (environment assumption A1)
Vacuum(r, p) ==
  /\ r \in rows[p] /\ r \notin live /\ r \notin snapVis /\ p # held
  /\ rows' = [rows EXCEPT ![p] = @ \ {r}]
  /\ UNCHANGED <<ptype, live, nextRow, grown>>
  /\ UNCHANGED scanVars

\* vacuum frees a heap page it emptied (file_dealloc under the header write latch)
FreePage(p) ==
  /\ ptype[p] = "heap" /\ rows[p] = {} /\ p # held
  /\ ptype' = [ptype EXCEPT ![p] = "free"]
  /\ wasFreed' = IF pc \in {"open", "snapped"} THEN wasFreed ELSE wasFreed \cup {p}
  /\ UNCHANGED <<rows, live, nextRow, grown>>
  /\ UNCHANGED <<snapVis, list, ftabSnap, pc, cur, held, readCur, out, aborted, errs, rew, badFix,
                 skippedFreed, skippedForeign, reusedRead>>

\* the file table grows by one page, taken from the first partial sector (file_manager.c:5025)
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

(****************************** the scan **********************************)

\* the statement's snapshot (before the list; after it in mutant late_snapshot)
TakeSnapshot ==
  /\ \/ Mutant # "late_snapshot" /\ pc = "open" /\ pc' = "snapped"
     \/ Mutant = "late_snapshot" /\ pc = "snaplate" /\ pc' = "pick"
  /\ snapVis' = live
  /\ UNCHANGED <<list, ftabSnap, cur, held, readCur, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead>>
  /\ UNCHANGED envVars

\* file_get_all_data_sectors: the header read latch blocks every alloc and dealloc, so one step
CollectList ==
  /\ \/ Mutant # "late_snapshot" /\ pc = "snapped"
     \/ Mutant = "late_snapshot" /\ pc = "open"
  /\ list' = {p \in Pages : ptype[p] # "free"}
  /\ ftabSnap' = {p \in Pages : ptype[p] = "ftab"}
  /\ pc' = "dedup"
  /\ UNCHANGED <<snapVis, cur, held, readCur, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead>>
  /\ UNCHANGED envVars

\* the file table pages leave the list after the header latch is released (D4)
Dedup ==
  /\ pc = "dedup"
  /\ list' = IF Mutant = "no_dedup_assert_heap" THEN list ELSE list \ ftabSnap
  /\ pc' = IF Mutant = "late_snapshot" THEN "snaplate" ELSE "pick"
  /\ UNCHANGED <<snapVis, ftabSnap, cur, held, readCur, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead>>
  /\ UNCHANGED envVars

\* the next listed page after cur, from the list, never from the held page's link
Pick ==
  /\ pc = "pick"
  /\ LET after == {p \in list : IF Mutant = "revisit" THEN p >= cur ELSE p > cur}
     IN IF after = {}
        THEN /\ pc' = "end"
             /\ UNCHANGED <<cur, readCur>>
        ELSE /\ \E p \in after : (\A q \in after : p <= q) /\ cur' = p
             /\ readCur' = FALSE
             /\ pc' = "release"
  /\ UNCHANGED <<snapVis, list, ftabSnap, held, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead>>
  /\ UNCHANGED envVars

\* the held page goes before the next one is fixed (a scan holding a page while it waits deadlocks with vacuum)
Release ==
  /\ pc = "release"
  /\ held' = 0
  /\ pc' = "fix"
  /\ UNCHANGED <<snapVis, list, ftabSnap, cur, readCur, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead>>
  /\ UNCHANGED envVars

\* pgbuf_ordered_fix (OLD_PAGE_MAYBE_DEALLOCATED): a freed page comes back as not fixed; another page type is skipped (D6)
Fix ==
  /\ pc = "fix"
  /\ IF ptype[cur] = "heap"
     THEN /\ held' = cur
          /\ pc' = "read"
          /\ UNCHANGED <<badFix, skippedFreed, skippedForeign>>
     ELSE IF ptype[cur] = "free"
     THEN /\ IF Mutant = "fix_freed"
             THEN /\ badFix' = TRUE /\ held' = cur /\ pc' = "read"
             ELSE /\ UNCHANGED <<badFix, held>> /\ pc' = "pick"
          /\ skippedFreed' = TRUE
          /\ UNCHANGED skippedForeign
     ELSE /\ IF Mutant \in {"assert_heap", "no_dedup_assert_heap"}
             THEN /\ badFix' = TRUE /\ held' = cur /\ pc' = "read"
             ELSE /\ UNCHANGED <<badFix, held>> /\ pc' = "pick"
          /\ skippedForeign' = TRUE
          /\ UNCHANGED skippedFreed
  /\ UNCHANGED <<snapVis, list, ftabSnap, cur, readCur, out, aborted, errs, rew, wasFreed, reusedRead>>
  /\ UNCHANGED envVars

\* the rows of the held page the snapshot sees, page latch held: one step
Read ==
  /\ pc = "read"
  /\ LET got == IF Mutant = "no_visibility" THEN rows[cur] ELSE rows[cur] \cap snapVis
     IN out' = [r \in Rows |-> IF r \in got THEN IF out[r] >= 2 THEN 2 ELSE out[r] + 1 ELSE out[r]]
  /\ readCur' = TRUE
  /\ reusedRead' = (reusedRead \/ cur \in wasFreed)
  /\ pc' = "pick"
  /\ UNCHANGED <<snapVis, list, ftabSnap, cur, held, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign>>
  /\ UNCHANGED envVars

\* the scan ends (S_END or an error): its page goes
Finish ==
  /\ pc = "end"
  /\ held' = IF Mutant = "no_release" THEN held ELSE 0
  /\ pc' = "done"
  /\ UNCHANGED <<snapVis, list, ftabSnap, cur, readCur, out, aborted, errs, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead>>
  /\ UNCHANGED envVars

\* an error or an interrupt anywhere in the walk
Abort ==
  /\ pc \in {"pick", "release", "fix", "read"}
  /\ errs < MaxErrors
  /\ errs' = errs + 1
  /\ aborted' = TRUE
  /\ pc' = "end"
  /\ UNCHANGED <<snapVis, list, ftabSnap, cur, held, readCur, out, rew, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead>>
  /\ UNCHANGED envVars

\* the scan opened again with the same snapshot walks the same list (D5)
Rewind ==
  /\ pc = "done" /\ ~aborted /\ rew < MaxRewind
  /\ rew' = rew + 1
  /\ cur' = IF Mutant = "rewind_keep_cur" THEN cur ELSE 0
  /\ readCur' = FALSE
  /\ out' = [r \in Rows |-> 0]
  /\ pc' = "pick"
  /\ UNCHANGED <<snapVis, list, ftabSnap, held, aborted, errs, badFix, wasFreed,
                 skippedFreed, skippedForeign, reusedRead>>
  /\ UNCHANGED envVars

ScanStep == TakeSnapshot \/ CollectList \/ Dedup \/ Pick \/ Release \/ Fix \/ Read \/ Finish

\* nothing left to do (the environment's budget is spent): stutter instead of a false deadlock
Idle == pc = "done" /\ UNCHANGED vars

Next == Env \/ ScanStep \/ Abort \/ Rewind \/ Idle

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
  /\ pc \in PcValues
  /\ cur \in 0..N
  /\ held \in 0..N
  /\ readCur \in BOOLEAN
  /\ out \in [Rows -> 0..2]
  /\ aborted \in BOOLEAN
  /\ errs \in Int /\ 0 <= errs /\ errs <= MaxErrors
  /\ rew \in Int /\ 0 <= rew /\ rew <= MaxRewind
  /\ badFix \in BOOLEAN
  /\ wasFreed \in SUBSET Pages
  /\ skippedFreed \in BOOLEAN
  /\ skippedForeign \in BOOLEAN
  /\ reusedRead \in BOOLEAN

\* C1: nothing the snapshot does not see is returned ...
NoExtraRow == \A r \in Rows : out[r] > 0 => r \in snapVis
\* C1: ... and everything it sees is, when the pass ends without an error
AllRowsReturned == (pc = "done" /\ ~aborted) => \A r \in snapVis : out[r] >= 1
\* C2
NoDuplicate == \A r \in Rows : out[r] <= 1
\* C3
NoPageHeld == pc = "done" => held = 0
\* C5
NoForeignRead == ~badFix
\* C4
Ends == <>(pc = "done")

(******************************* witnesses ********************************)
NotFinished == ~(pc = "done" /\ ~aborted)
NotRewoundFinished == ~(pc = "done" /\ ~aborted /\ rew >= 1)
NotSkippedFreed == ~skippedFreed
NotSkippedForeign == ~skippedForeign
NotReusedRead == ~reusedRead
\* a row deleted after the snapshot is still returned
NotDeletedAfterSnapReturned == ~(\E r \in snapVis : r \notin live /\ out[r] = 1 /\ pc = "done")
\* a row inserted before the snapshot into a page allocated before the list is returned
NotNewPageRowReturned == ~(\E r \in snapVis : r >= 4 /\ out[r] = 1 /\ ~(r \in rows[2] \/ r \in rows[5]))
NotAborted == ~(pc = "done" /\ aborted)

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

\* the scan's phases and what each allows
ScanShape ==
  /\ pc \in {"open", "snapped"} => (list = {} /\ ftabSnap = {} /\ cur = 0 /\ held = 0 /\ ~readCur
                                    /\ ~aborted /\ errs = 0 /\ rew = 0 /\ wasFreed = {})
  /\ pc = "open" => snapVis = {}
  /\ pc = "dedup" => (cur = 0 /\ held = 0 /\ ~readCur /\ ~aborted /\ errs = 0 /\ rew = 0
                      /\ 1 \in ftabSnap /\ ftabSnap \subseteq list)
  /\ pc \in {"snaplate"} => FALSE
  /\ \A r \in Rows : out[r] > 0 => pc \in {"pick", "release", "fix", "read", "end", "done"}
  /\ ftabSnap \subseteq {p \in Pages : ptype[p] = "ftab"}
  /\ pc \in {"pick", "release", "fix", "read", "end", "done"} => list \cap ftabSnap = {}
  /\ pc \in {"pick", "release", "fix", "read", "end", "done"} => 1 \in ftabSnap
  /\ cur # 0 => cur \in list
  /\ held # 0 => (ptype[held] = "heap" /\ held <= cur /\ held \in list)
  /\ pc = "fix" => held = 0
  /\ pc \in {"release", "fix"} => (~readCur /\ cur # 0)
  /\ pc = "read" => (held = cur /\ ~readCur /\ cur # 0)
  /\ pc = "done" => held = 0
  /\ readCur => cur # 0
  /\ ~badFix
  /\ aborted => errs >= 1

\* the snapshot's rows stay where they were, on heap pages of the list
SnapRowsStay ==
  /\ \A r \in snapVis : r < nextRow
  /\ \A r \in snapVis : \E p \in Pages : r \in rows[p] /\ ptype[p] = "heap"
  /\ pc = "dedup" => \A r \in snapVis : \A p \in Pages : r \in rows[p] => (p \in list /\ p \notin ftabSnap)
  /\ pc \in {"pick", "release", "fix", "read", "end", "done"} =>
       \A r \in snapVis : \A p \in Pages : r \in rows[p] => p \in list

\* what this pass returned: exactly the snapshot's rows on the pages behind the walk
OutExact ==
  /\ \A r \in Rows : r \notin snapVis => out[r] = 0
  /\ \A r \in snapVis : \A p \in Pages : r \in rows[p] =>
        out[r] = IF p < cur \/ (p = cur /\ readCur) THEN 1 ELSE 0
  /\ pc = "pick" /\ cur # 0 /\ ~readCur => \A r \in snapVis : r \notin rows[cur]
  /\ (pc \in {"end", "done"} /\ ~aborted) =>
        (/\ \A p \in list : p <= cur
         /\ (cur # 0 /\ ~readCur) => \A r \in snapVis : r \notin rows[cur])

IndInv ==
  /\ TypeOK
  /\ RowsWellFormed
  /\ ScanShape
  /\ SnapRowsStay
  /\ OutExact
  /\ NoExtraRow
  /\ AllRowsReturned
  /\ NoDuplicate
  /\ NoPageHeld
  /\ NoForeignRead
=============================================================================
