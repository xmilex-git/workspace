---------------------------- MODULE FkParentUnlocked ----------------------------
(* PR 8198 (CBRD-27463) at fbaae2592: a child's foreign-key existence check takes no lock on the
   parent row; a parent DELETE delete-marks the PK key, then reads the children (phase 1), waits out
   their writers with no child locked (phase 2), then locks, re-checks and acts (phase 3), or runs
   the RESTRICT check in place.  One parent key P, one child table, writers Writers, deleter D.
   Map: MAP.md. *)
EXTENDS Naturals, FiniteSets

CONSTANTS Writers, D, NS, K, Action, Mutant, InitChild
\* Mutant values: "none", "lock_parent_s" (develop: the check holds S on the parent row),
\* "check_before_entry", "scan_before_mark", "lock_before_wait" (before 39631cfe9),
\* "heap_after_index" (before a9f1fefef), "no_seen_filter", "no_inserter_compare" (before fbaae2592),
\* "exclude_inserting" (CBRD-27464 enumeration without the parent row lock)

NT == "none"
Old == "old"
Trans == Writers \cup {D}
Slots == 1..NS
Free == [used |-> FALSE, ref |-> FALSE, ins |-> NT, prevIns |-> NT, hasPrev |-> FALSE,
         prevHasPrev |-> FALSE, del |-> NT]
NoEntry == [present |-> FALSE, ins |-> NT, del |-> NT]

VARIABLES row, entry, pkey, parentX, parentS, xlock, tstate,
          pc, cur, kind, nstmt, stIns, stUpd, tIns, tUpd,
          pcD, coll, insr, p2, p3, held, kept, cc, waitOn, waitLock, curS, p1w,
          heapFirstViol, victims, skippedOther, waitNew, gen, p1gen

wvars == <<pc, cur, kind, nstmt, stIns, stUpd, tIns, tUpd>>
dvars == <<pcD, coll, insr, p2, p3, held, kept, cc, waitOn, waitLock, curS, p1w>>
vars == <<row, entry, pkey, parentX, parentS, xlock, tstate, wvars, dvars, heapFirstViol, victims, skippedOther, waitNew, gen, p1gen>>

Min(S) == CHOOSE x \in S : \A y \in S : x <= y
Active(t) == t \in Trans /\ tstate[t] = "active"
ActiveOther(t, self) == Active(t) /\ t # self
Committed(t) == t = Old \/ (t \in Trans /\ tstate[t] = "committed")
AllVisible(t) == t = Old
\* mvcc_satisfies_delete on an index entry or heap header, seen by transaction self
CanDelete(r) == Committed(r.ins) /\ ~Committed(r.del) /\ ~ActiveOther(r.del, NT) /\ r.del = NT
DelInProgress(r, self) == ActiveOther(r.del, self)
InsInProgress(r, self) == ActiveOther(r.ins, self) /\ r.del = NT
\* entry accepted by locator_satisfies_child_of_locked_parent
ChildOfLocked(e) == e.present /\ (CanDelete(e) \/ DelInProgress(e, D) \/
                                   (InsInProgress(e, D) /\ Mutant # "exclude_inserting"))
\* locator_satisfies_child_being_written / restrict entry
BeingWritten(e) == e.present /\ (ActiveOther(e.ins, D) \/ ActiveOther(e.del, D))
\* locator_is_other_row
OtherRow(s) == insr[s] # NT /\ row[s].used /\ ~AllVisible(row[s].ins) /\ row[s].ins # insr[s]
               /\ ~row[s].hasPrev /\ Mutant # "no_inserter_compare"
Stamper(s, self) == IF ActiveOther(row[s].del, self) THEN row[s].del
                    ELSE IF ActiveOther(row[s].ins, self) THEN row[s].ins ELSE NT

Init ==
  /\ row = [s \in Slots |-> IF s = 1 /\ InitChild THEN [Free EXCEPT !.used = TRUE, !.ref = TRUE, !.ins = Old] ELSE Free]
  /\ entry = [s \in Slots |-> IF s = 1 /\ InitChild THEN [NoEntry EXCEPT !.present = TRUE, !.ins = Old] ELSE NoEntry]
  /\ pkey = "live" /\ parentX = NT /\ parentS = {} /\ xlock = [s \in Slots |-> NT]
  /\ tstate = [t \in Trans |-> "active"]
  /\ pc = [w \in Writers |-> "start"] /\ cur = [w \in Writers |-> 0] /\ kind = [w \in Writers |-> NT]
  /\ nstmt = [w \in Writers |-> 0] /\ stIns = [w \in Writers |-> {}] /\ stUpd = [w \in Writers |-> {}]
  /\ tIns = [w \in Writers |-> {}] /\ tUpd = [w \in Writers |-> {}]
  /\ pcD = "d_lock" /\ coll = {} /\ insr = [s \in Slots |-> NT] /\ p2 = {} /\ p3 = {} /\ held = {}
  /\ kept = {} /\ cc = FALSE /\ waitOn = NT /\ waitLock = 0 /\ curS = 0 /\ p1w = {}
  /\ heapFirstViol = FALSE /\ victims = 0 /\ skippedOther = FALSE /\ waitNew = FALSE
  /\ gen = [s \in Slots |-> 0] /\ p1gen = [s \in Slots |-> 0]

----------------------------------------------------------------------------------------------
\* undo helpers
UndoIns(r, e, S) == <<[s \in Slots |-> IF s \in S THEN Free ELSE r[s]],
                      [s \in Slots |-> IF s \in S THEN NoEntry ELSE e[s]]>>
UndoUpd(r, S) == [s \in Slots |-> IF s \in S
                     THEN [r[s] EXCEPT !.ins = r[s].prevIns, !.hasPrev = r[s].prevHasPrev] ELSE r[s]]

\* ---------------- writers ----------------
WStart(w) ==
  /\ pc[w] = "start" /\ tstate[w] = "active"
  /\ \/ \E s \in Slots : ~row[s].used /\ cur' = [cur EXCEPT ![w] = s] /\ kind' = [kind EXCEPT ![w] = "ins"]
                         /\ pc' = [pc EXCEPT ![w] = "ins_heap"]
     \/ \E s \in Slots, k \in {"upd", "updfk"} :
          /\ row[s].used /\ row[s].ref /\ ~Committed(row[s].del) /\ row[s].ins # w /\ s \notin tIns[w]
          /\ cur' = [cur EXCEPT ![w] = s] /\ kind' = [kind EXCEPT ![w] = k] /\ pc' = [pc EXCEPT ![w] = "upd_acq"]
  /\ UNCHANGED <<row, entry, pkey, parentX, parentS, xlock, tstate, nstmt, stIns, stUpd, tIns, tUpd, dvars,
                 heapFirstViol, victims, skippedOther, waitNew>>

WEnd(w) == \* the transaction ends before its next statement
  /\ pc[w] = "start" /\ pc' = [pc EXCEPT ![w] = "fin"]
  /\ UNCHANGED <<row, entry, pkey, parentX, parentS, xlock, tstate, cur, kind, nstmt, stIns, stUpd, tIns, tUpd, dvars,
                 heapFirstViol, victims, skippedOther, waitNew>>

\* locator_insert_force: heap insert (stamp), then the FK index entry, then the check
WInsHeap(w) ==
  /\ pc[w] = "ins_heap" /\ ~row[cur[w]].used
  /\ row' = [row EXCEPT ![cur[w]] = [Free EXCEPT !.used = TRUE, !.ref = TRUE, !.ins = w]]
  /\ stIns' = [stIns EXCEPT ![w] = @ \cup {cur[w]}] /\ tIns' = [tIns EXCEPT ![w] = @ \cup {cur[w]}]
  /\ pc' = [pc EXCEPT ![w] = IF Mutant = "check_before_entry" THEN "chk" ELSE "ins_entry"]
  /\ UNCHANGED <<entry, pkey, parentX, parentS, xlock, tstate, cur, kind, nstmt, stUpd, tUpd, dvars,
                 heapFirstViol, victims, skippedOther, waitNew>>
WInsHeapLost(w) == \* the slot was taken since WStart: pick again
  /\ pc[w] = "ins_heap" /\ row[cur[w]].used /\ pc' = [pc EXCEPT ![w] = "start"]
  /\ UNCHANGED <<row, entry, pkey, parentX, parentS, xlock, tstate, cur, kind, nstmt, stIns, stUpd, tIns, tUpd,
                 dvars, heapFirstViol, victims, skippedOther, waitNew>>
WInsEntry(w) ==
  /\ pc[w] = "ins_entry"
  /\ entry' = [entry EXCEPT ![cur[w]] = [present |-> TRUE, ins |-> w, del |-> NT]]
  /\ pc' = [pc EXCEPT ![w] = IF Mutant = "check_before_entry" THEN "stmt_end" ELSE "chk"]
  /\ UNCHANGED <<row, pkey, parentX, parentS, xlock, tstate, cur, kind, nstmt, stIns, stUpd, tIns, tUpd, dvars,
                 heapFirstViol, victims, skippedOther, waitNew>>

\* locator_update_force after the select phase locked the row: acquire X with no active other stamp
WUpdAcq(w) ==
  /\ pc[w] = "upd_acq" /\ xlock[cur[w]] = NT /\ Stamper(cur[w], w) = NT
  /\ xlock' = [xlock EXCEPT ![cur[w]] = w]
  /\ pc' = [pc EXCEPT ![w] =
        IF ~row[cur[w]].used \/ ~row[cur[w]].ref \/ Committed(row[cur[w]].del) THEN "stmt_end"
        ELSE IF kind[w] = "updfk" /\ Mutant = "heap_after_index" THEN "chk" ELSE "upd_stamp"]
  /\ UNCHANGED <<row, entry, pkey, parentX, parentS, tstate, cur, kind, nstmt, stIns, stUpd, tIns, tUpd, dvars,
                 heapFirstViol, victims, skippedOther, waitNew>>
\* heap_update_logical: the new version stamps the header; the FK index entry is kept (key unchanged)
WUpdStamp(w) ==
  /\ pc[w] = "upd_stamp"
  /\ LET r == row[cur[w]] IN
       row' = [row EXCEPT ![cur[w]] = [r EXCEPT !.prevIns = r.ins, !.prevHasPrev = r.hasPrev, !.ins = w,
                                                 !.hasPrev = TRUE]]
  /\ stUpd' = [stUpd EXCEPT ![w] = @ \cup {cur[w]}] /\ tUpd' = [tUpd EXCEPT ![w] = @ \cup {cur[w]}]
  /\ pc' = [pc EXCEPT ![w] = IF kind[w] = "updfk" /\ Mutant # "heap_after_index" THEN "chk" ELSE "stmt_end"]
  /\ UNCHANGED <<entry, pkey, parentX, parentS, xlock, tstate, cur, kind, nstmt, stIns, tIns, dvars,
                 heapFirstViol, victims, skippedOther, waitNew>>

\* locator_check_foreign_key -> xbtree_find_unique_fk_existence: no lock on a committed parent;
\* waits out an active deleter (btree_key_wait_out_conflicting_writer)
AfterChk(w) == IF kind[w] = "ins" THEN (IF Mutant = "check_before_entry" THEN "ins_entry" ELSE "stmt_end")
               ELSE IF Mutant = "heap_after_index" THEN "upd_stamp" ELSE "stmt_end"
WChkPass(w) ==
  /\ pc[w] = "chk" /\ pkey = "live"
  /\ IF Mutant = "lock_parent_s" THEN parentX = NT /\ parentS' = parentS \cup {w} ELSE UNCHANGED parentS
  /\ pc' = [pc EXCEPT ![w] = AfterChk(w)]
  /\ UNCHANGED <<row, entry, pkey, parentX, xlock, tstate, cur, kind, nstmt, stIns, stUpd, tIns, tUpd, dvars,
                 heapFirstViol, victims, skippedOther, waitNew>>
StmtRollback(w) ==
  /\ LET u == UndoIns(row, entry, stIns[w]) IN
       /\ row' = UndoUpd(u[1], stUpd[w] \ stIns[w]) /\ entry' = u[2]
  /\ tIns' = [tIns EXCEPT ![w] = @ \ stIns[w]] /\ tUpd' = [tUpd EXCEPT ![w] = @ \ stUpd[w]]
  /\ stIns' = [stIns EXCEPT ![w] = {}] /\ stUpd' = [stUpd EXCEPT ![w] = {}]
WChkFail(w) == \* ER_FK_INVALID: the parent is gone
  /\ pc[w] = "chk" /\ pkey = "gone"
  /\ StmtRollback(w) /\ pc' = [pc EXCEPT ![w] = "stmt_end"]
  /\ UNCHANGED <<pkey, parentX, parentS, xlock, tstate, cur, kind, nstmt, dvars, heapFirstViol, victims, skippedOther, waitNew>>
\* fault: the statement fails (interrupt, unique violation, savepoint rollback) while it waits or after its work
WStmtFault(w) ==
  /\ pc[w] \in {"chk", "stmt_end"} /\ (stIns[w] # {} \/ stUpd[w] # {})
  /\ StmtRollback(w) /\ pc' = [pc EXCEPT ![w] = "stmt_end"]
  /\ UNCHANGED <<pkey, parentX, parentS, xlock, tstate, cur, kind, nstmt, dvars, heapFirstViol, victims, skippedOther, waitNew>>
\* READ COMMITTED: the statement gives its row lock back (CBRD-27034)
WStmtEnd(w) ==
  /\ pc[w] = "stmt_end"
  /\ xlock' = [s \in Slots |-> IF xlock[s] = w THEN NT ELSE xlock[s]]
  /\ nstmt' = [nstmt EXCEPT ![w] = @ + 1]
  /\ stIns' = [stIns EXCEPT ![w] = {}] /\ stUpd' = [stUpd EXCEPT ![w] = {}]
  /\ pc' = [pc EXCEPT ![w] = IF nstmt[w] + 1 < K THEN "start" ELSE "fin"]
  /\ UNCHANGED <<row, entry, pkey, parentX, parentS, tstate, cur, kind, tIns, tUpd, dvars,
                 heapFirstViol, victims, skippedOther, waitNew>>
WCommit(w) ==
  /\ pc[w] = "fin" /\ tstate' = [tstate EXCEPT ![w] = "committed"] /\ pc' = [pc EXCEPT ![w] = "done"]
  /\ parentS' = parentS \ {w}
  /\ UNCHANGED <<row, entry, pkey, parentX, xlock, cur, kind, nstmt, stIns, stUpd, tIns, tUpd, dvars,
                 heapFirstViol, victims, skippedOther, waitNew>>
WAbortCore(w) ==
  /\ LET u == UndoIns(row, entry, tIns[w]) IN
       /\ row' = UndoUpd(u[1], tUpd[w] \ tIns[w]) /\ entry' = u[2]
  /\ tstate' = [tstate EXCEPT ![w] = "aborted"] /\ pc' = [pc EXCEPT ![w] = "done"]
  /\ xlock' = [s \in Slots |-> IF xlock[s] = w THEN NT ELSE xlock[s]] /\ parentS' = parentS \ {w}
  /\ tIns' = [tIns EXCEPT ![w] = {}] /\ tUpd' = [tUpd EXCEPT ![w] = {}]
  /\ stIns' = [stIns EXCEPT ![w] = {}] /\ stUpd' = [stUpd EXCEPT ![w] = {}]
WAbort(w) == pc[w] = "fin" /\ WAbortCore(w)
  /\ UNCHANGED <<pkey, parentX, cur, kind, nstmt, dvars, heapFirstViol, victims, skippedOther, waitNew>>

\* ---------------- parent DELETE (locator_check_primary_key_delete) ----------------
DUnchangedW == UNCHANGED <<wvars, parentS>>
AfterCollect == IF Action = "restrict" /\ cc THEN "d_rcheck"
                ELSE IF Mutant = "lock_before_wait" THEN "d_p3" ELSE "d_p2"
DLock ==
  /\ pcD = "d_lock" /\ parentS \ {D} = {} /\ parentX = NT
  /\ parentX' = D /\ pcD' = IF Mutant = "scan_before_mark" THEN "d_collect" ELSE "d_mark"
  /\ UNCHANGED <<row, entry, pkey, xlock, tstate, coll, insr, p2, p3, held, kept, cc, waitOn, waitLock, curS, p1w,
                 heapFirstViol, victims, skippedOther, waitNew>> /\ DUnchangedW
\* btree_mvcc_delete in locator_add_or_remove_index_internal, under the PK leaf latch
DMark ==
  /\ pcD = "d_mark" /\ pkey' = "marked"
  /\ pcD' = IF Mutant = "scan_before_mark" THEN AfterCollect ELSE "d_collect"
  /\ UNCHANGED <<row, entry, parentX, xlock, tstate, coll, insr, p2, p3, held, kept, cc, waitOn, waitLock, curS, p1w,
                 heapFirstViol, victims, skippedOther, waitNew>> /\ DUnchangedW
\* phase 1: locator_collect_children_of_key -> locator_scan_fk_key (one leaf, under its latch)
DCollect ==
  /\ pcD = "d_collect"
  /\ LET c == IF Action = "cascade" THEN {s \in Slots : ChildOfLocked(entry[s])}
              ELSE {s \in Slots : BeingWritten(entry[s])}
         ccv == Action = "restrict" /\ \E s \in Slots : entry[s].present /\ CanDelete(entry[s])
     IN /\ coll' = c /\ cc' = ccv
        /\ insr' = [s \in Slots |-> IF s \in c /\ ActiveOther(entry[s].ins, D) THEN entry[s].ins ELSE NT]
        /\ p2' = c /\ p3' = c
        /\ p1w' = {t \in Writers : \E s \in c : row[s].ins = t \/ row[s].del = t \/ entry[s].ins = t}
                    \cap {t \in Writers : Active(t)}
        /\ pcD' = IF Mutant = "scan_before_mark" THEN "d_mark"
                  ELSE IF Action = "restrict" /\ ccv THEN "d_rcheck"
                  ELSE IF Mutant = "lock_before_wait" THEN "d_p3" ELSE "d_p2"
  /\ UNCHANGED <<row, entry, pkey, parentX, xlock, tstate, held, kept, waitOn, waitLock, curS,
                 heapFirstViol, victims, skippedOther, waitNew>> /\ DUnchangedW
\* phase 2: locator_wait_out_collected_writers -> locator_wait_out_child_writer (peek, no lock)
\* the entry at s was inserted by w after phase 1 read the key (a new row, or a reused slot)
NewcomerSlot(s, w) == entry[s].present /\ entry[s].ins = w /\ (s \notin coll \/ insr[s] # w)
UnstampedHolderOk(s) == \A w \in Writers : (xlock[s] = w /\ row[s].ins # w) => pc[w] \in {"upd_stamp", "stmt_end"}
DP2 ==
  /\ pcD = "d_p2"
  /\ IF p2 = {} THEN /\ pcD' = IF Action = "restrict" THEN "d_rcheck" ELSE "d_p3"
                     /\ UNCHANGED <<p2, waitOn, curS, heapFirstViol, skippedOther, waitNew>>
     ELSE LET s == Min(p2) IN
       /\ curS' = s
       /\ (Stamper(s, D) = NT \/ ~row[s].used \/ OtherRow(s)) => waitNew' = waitNew
       /\ heapFirstViol' = (heapFirstViol \/ ~UnstampedHolderOk(s))
       /\ IF ~row[s].used \/ OtherRow(s)
            THEN p2' = p2 \ {s} /\ pcD' = "d_p2" /\ UNCHANGED waitOn
                 /\ skippedOther' = (skippedOther \/ OtherRow(s))
          ELSE IF Stamper(s, D) = NT THEN p2' = p2 \ {s} /\ pcD' = "d_p2" /\ UNCHANGED <<waitOn, skippedOther>>
          ELSE waitOn' = Stamper(s, D) /\ pcD' = "d_p2wait" /\ UNCHANGED <<p2, skippedOther>>
               /\ waitNew' = NewcomerSlot(s, Stamper(s, D))
  /\ UNCHANGED <<row, entry, pkey, parentX, xlock, tstate, coll, insr, p3, held, kept, cc, waitLock, p1w, victims>>
  /\ DUnchangedW
DP2Wait ==
  /\ pcD = "d_p2wait" /\ ~Active(waitOn) /\ pcD' = "d_p2" /\ waitOn' = NT
  /\ UNCHANGED <<row, entry, pkey, parentX, xlock, tstate, coll, insr, p2, p3, held, kept, cc, waitLock, curS, p1w,
                 heapFirstViol, victims, skippedOther, waitNew>> /\ DUnchangedW
\* RESTRICT in place: locator_check_restrict_in_place -> btree_find_foreign_key / btree_fk_object_does_exist
Seen(s) == s \in coll /\ (insr[s] = NT \/ insr[s] = entry[s].ins)
Deferred(s) == entry[s].present /\
   ( DelInProgress(entry[s], D)
   \/ (InsInProgress(entry[s], D) /\ (Seen(s) \/ Mutant = "no_seen_filter")) )
DRCheck ==
  /\ pcD = "d_rcheck"
  /\ IF \E s \in Slots : entry[s].present /\ CanDelete(entry[s])
       THEN LET s == Min({x \in Slots : entry[x].present /\ CanDelete(entry[x])}) IN
            IF xlock[s] \in {NT, D} THEN pcD' = "d_fail" /\ UNCHANGED <<waitOn, waitLock, waitNew>>
            ELSE waitOn' = xlock[s] /\ waitLock' = s /\ pcD' = "d_rwait" /\ waitNew' = FALSE
     ELSE IF \E s \in Slots : Deferred(s)
       THEN LET s == Min({x \in Slots : Deferred(x)}) IN
            /\ waitOn' = IF DelInProgress(entry[s], D) THEN entry[s].del ELSE entry[s].ins
            /\ waitLock' = 0 /\ pcD' = "d_rwait"
            /\ waitNew' = NewcomerSlot(s, IF DelInProgress(entry[s], D) THEN entry[s].del ELSE entry[s].ins)
     ELSE pcD' = "d_commit" /\ UNCHANGED <<waitOn, waitLock, waitNew>>
  /\ UNCHANGED <<row, entry, pkey, parentX, xlock, tstate, coll, insr, p2, p3, held, kept, cc, curS, p1w,
                 heapFirstViol, victims, skippedOther>> /\ DUnchangedW
DRWait ==
  /\ pcD = "d_rwait"
  /\ IF waitLock # 0 THEN xlock[waitLock] # waitOn ELSE ~Active(waitOn)
  /\ pcD' = "d_rcheck" /\ waitOn' = NT /\ waitLock' = 0
  /\ UNCHANGED <<row, entry, pkey, parentX, xlock, tstate, coll, insr, p2, p3, held, kept, cc, curS, p1w,
                 heapFirstViol, victims, skippedOther, waitNew>> /\ DUnchangedW
\* phase 3: locator_keep_referring_children -> locator_gathered_row_gone, locator_lock_gathered_child
DP3 ==
  /\ pcD = "d_p3"
  /\ IF p3 = {} THEN pcD' = "d_act" /\ UNCHANGED <<p3, xlock, held, curS>>
     ELSE LET s == Min(p3) IN
       IF insr[s] # NT /\ (~row[s].used \/ OtherRow(s))
         THEN p3' = p3 \ {s} /\ UNCHANGED <<xlock, held, curS>> /\ pcD' = "d_p3"
       ELSE /\ xlock[s] \in {NT, D} /\ xlock' = [xlock EXCEPT ![s] = D] /\ held' = held \cup {s}
            /\ curS' = s /\ pcD' = "d_p3read" /\ UNCHANGED p3
  /\ UNCHANGED <<row, entry, pkey, parentX, tstate, coll, insr, p2, kept, cc, waitOn, waitLock, p1w,
                 heapFirstViol, victims, skippedOther, waitNew>> /\ DUnchangedW
DP3Read ==
  /\ pcD = "d_p3read" /\ LET s == curS IN
     IF Stamper(s, D) # NT
       THEN waitOn' = Stamper(s, D) /\ pcD' = "d_p3wait" /\ UNCHANGED <<xlock, held, kept, p3>>
     ELSE IF ~row[s].used \/ ~row[s].ref \/ Committed(row[s].del)
       THEN xlock' = [xlock EXCEPT ![s] = NT] /\ held' = held \ {s} /\ p3' = p3 \ {s} /\ pcD' = "d_p3"
            /\ UNCHANGED <<waitOn, kept>>
     ELSE kept' = kept \cup {s} /\ p3' = p3 \ {s} /\ pcD' = "d_p3" /\ UNCHANGED <<waitOn, xlock, held>>
  /\ UNCHANGED <<row, entry, pkey, parentX, tstate, coll, insr, p2, cc, waitLock, curS, p1w,
                 heapFirstViol, victims, skippedOther, waitNew>> /\ DUnchangedW
DP3Wait ==
  /\ pcD = "d_p3wait" /\ ~Active(waitOn) /\ pcD' = "d_p3read" /\ waitOn' = NT
  /\ UNCHANGED <<row, entry, pkey, parentX, xlock, tstate, coll, insr, p2, p3, held, kept, cc, waitLock, curS, p1w,
                 heapFirstViol, victims, skippedOther, waitNew>> /\ DUnchangedW
DAct == \* CASCADE: delete every kept child (its FK entry is delete-marked with it)
  /\ pcD = "d_act"
  /\ row' = [s \in Slots |-> IF s \in kept THEN [row[s] EXCEPT !.del = D] ELSE row[s]]
  /\ entry' = [s \in Slots |-> IF s \in kept THEN [entry[s] EXCEPT !.del = D] ELSE entry[s]]
  /\ pcD' = "d_commit"
  /\ UNCHANGED <<pkey, parentX, xlock, tstate, coll, insr, p2, p3, held, kept, cc, waitOn, waitLock, curS, p1w,
                 heapFirstViol, victims, skippedOther, waitNew>> /\ DUnchangedW
DCommit ==
  /\ pcD = "d_commit" /\ tstate' = [tstate EXCEPT ![D] = "committed"] /\ pkey' = "gone"
  /\ parentX' = NT /\ xlock' = [s \in Slots |-> IF xlock[s] = D THEN NT ELSE xlock[s]] /\ pcD' = "d_done"
  /\ UNCHANGED <<row, entry, coll, insr, p2, p3, held, kept, cc, waitOn, waitLock, curS, p1w,
                 heapFirstViol, victims, skippedOther, waitNew>> /\ DUnchangedW
DAbortCore ==
  /\ row' = [s \in Slots |-> IF row[s].del = D THEN [row[s] EXCEPT !.del = NT] ELSE row[s]]
  /\ entry' = [s \in Slots |-> IF entry[s].del = D THEN [entry[s] EXCEPT !.del = NT] ELSE entry[s]]
  /\ tstate' = [tstate EXCEPT ![D] = "aborted"] /\ pkey' = IF pkey = "marked" THEN "live" ELSE pkey
  /\ parentX' = NT /\ xlock' = [s \in Slots |-> IF xlock[s] = D THEN NT ELSE xlock[s]] /\ pcD' = "d_done"
DFail == pcD = "d_fail" /\ DAbortCore
  /\ UNCHANGED <<coll, insr, p2, p3, held, kept, cc, waitOn, waitLock, curS, p1w, heapFirstViol, victims,
                 skippedOther, waitNew>> /\ DUnchangedW

\* ---------------- waits and the deadlock detector ----------------
BlockedOn(t) ==
  IF t = D THEN
     CASE pcD = "d_lock" -> parentS \ {D}
       [] pcD \in {"d_p2wait", "d_p3wait"} -> IF Active(waitOn) THEN {waitOn} ELSE {}
       [] pcD = "d_rwait" -> IF waitLock # 0 THEN (IF xlock[waitLock] = waitOn THEN {waitOn} ELSE {})
                             ELSE IF Active(waitOn) THEN {waitOn} ELSE {}
       [] pcD = "d_p3" /\ p3 # {} -> IF xlock[Min(p3)] \notin {NT, D} THEN {xlock[Min(p3)]} ELSE {}
       [] OTHER -> {}
  ELSE CASE pc[t] = "upd_acq" -> ({xlock[cur[t]]} \cup {Stamper(cur[t], t)}) \cap (Trans \ {t})
         [] pc[t] = "chk" -> IF (pkey = "marked" /\ Active(D)) \/ (Mutant = "lock_parent_s" /\ parentX = D)
                             THEN {D} ELSE {}
         [] OTHER -> {}
InCycle(t) == \E u \in Trans : u # t /\ u \in BlockedOn(t) /\
                (t \in BlockedOn(u) \/ \E v \in Trans \ {t, u} : v \in BlockedOn(u) /\ t \in BlockedOn(v))
Victim == \E t \in Trans : InCycle(t) /\ Active(t) /\ victims' = victims + 1 /\
  IF t = D THEN DAbortCore /\ UNCHANGED <<coll, insr, p2, p3, held, kept, cc, waitOn, waitLock, curS, p1w,
                                         heapFirstViol, skippedOther, waitNew>> /\ DUnchangedW
  ELSE WAbortCore(t) /\ UNCHANGED <<pkey, parentX, cur, kind, nstmt, dvars, heapFirstViol, skippedOther, waitNew>>

Done == pcD = "d_done" /\ \A w \in Writers : pc[w] = "done"
NextCore ==
  \/ \E w \in Writers : WStart(w) \/ WEnd(w) \/ WInsHeap(w) \/ WInsHeapLost(w) \/ WInsEntry(w) \/ WUpdAcq(w) \/ WUpdStamp(w)
                         \/ WChkPass(w) \/ WChkFail(w) \/ WStmtFault(w) \/ WStmtEnd(w) \/ WCommit(w) \/ WAbort(w)
  \/ DLock \/ DMark \/ DCollect \/ DP2 \/ DP2Wait \/ DRCheck \/ DRWait \/ DP3 \/ DP3Read \/ DP3Wait \/ DAct
  \/ DCommit \/ DFail \/ Victim
  \/ (Done /\ UNCHANGED <<row, entry, pkey, parentX, parentS, xlock, tstate, wvars, dvars, heapFirstViol, victims,
                         skippedOther, waitNew>>)
\* ghosts: a row's generation moves on every heap write; p1gen is the generation phase 1 saw
Next == NextCore
  /\ gen' = [s \in Slots |-> IF row'[s] = row[s] THEN gen[s] ELSE gen[s] + 1]
  /\ p1gen' = IF pcD = "d_collect" /\ pcD' # "d_collect" THEN gen ELSE p1gen
Spec == Init /\ [][Next]_vars

----------------------------------------------------------------------------------------------
\* C1: no committed child refers to a deleted parent
NoOrphan == tstate[D] = "committed" =>
  \A s \in Slots : ~(row[s].used /\ row[s].ref /\ Committed(row[s].ins) /\ ~Committed(row[s].del))
\* C3: the existence check holds no lock on the parent row
NoParentRowLock == parentS = {}
\* C4: the parent statement never waits for a writer that waits on its mark and came after phase 1
NoNewcomerWait == ~(pcD \in {"d_p2wait", "d_rwait"} /\ waitNew /\ Active(waitOn))
\* C5: the writer of a row unchanged since phase 1 is never waited for while another child is locked
NoP1WaitHoldingChild == ~(pcD = "d_p3wait" /\ Active(waitOn) /\ held \ {curS} # {}
                          /\ curS \in coll /\ gen[curS] = p1gen[curS])
\* C6: phase 2 never passes a row whose X holder is blocked before stamping it
HeapFirst == ~heapFirstViol
TypeOK == /\ pkey \in {"live", "marked", "gone"} /\ parentX \in {NT, D}
          /\ \A s \in Slots : xlock[s] \in Trans \cup {NT}
\* witnesses
NotCascadeOfWaitedInsert == ~(pcD = "d_done" /\ tstate[D] = "committed" /\ Action = "cascade"
                              /\ \E s \in Slots : row[s].used /\ row[s].del = D /\ row[s].ins \in Writers)
NotRestrictCommit == ~(pcD = "d_done" /\ tstate[D] = "committed" /\ Action = "restrict")
NotRestrictFail == ~(pcD = "d_done" /\ tstate[D] = "aborted" /\ victims = 0)
NotVictim == victims = 0
NotSlotReuseSkip == ~skippedOther
NotChildCommittedBeforeParentGone == ~(\E w \in Writers : tstate[w] = "committed" /\ tIns[w] # {} /\ pkey = "gone")
=============================================================================
