------------------------------ MODULE LazySnapshot ------------------------------
(* A SELECT's MVCC snapshot is not taken when the statement starts. The client
   marks the statement (db_invalidate_mvcc_snapshot_before_statement sets
   tm_Tran_invalidate_snapshot); the statement's first server request carries
   the mark and, under READ COMMITTED, invalidates the transaction's snapshot
   (network_sr.c:924 logtb_invalidate_snapshot_data, which also resets the
   COUNT-star optimization state); the first read that needs a snapshot builds it
   (logtb_get_mvcc_snapshot -> mvcctable::build_mvcc_info). REPEATABLE READ keeps
   the first snapshot until the transaction ends.

   The build is lock-free against commits:
     - the reader's lowest-visible slot is set to MVCCID_ALL_VISIBLE, then to the
       global lowest active MVCCID G it read, so vacuum waits instead of skipping it;
     - it loads the history position, the entry's version, copies the entry's
       active set id by id, loads the COUNT-star statistics, and rechecks the
       entry's version.
   A commit (mvcctable::complete_mvcc, under m_active_trans_mutex) stores a new
   version into the next history entry, publishes its unique statistics, marks
   itself inactive in the current status, copies the current status into the
   entry, publishes the position; after the mutex, it advances G.
   Vacuum computes the oldest visible MVCCID from G and every slot, waiting on a
   slot that holds MVCCID_ALL_VISIBLE, and removes versions deleted below it.

   Counts are abstracted to the set of transactions whose rows they include: a
   COUNT-star result is the set of writers whose statistics deltas it holds; the
   scan result is the set of rows it returns.

   Constants:
     NW         writers (other transactions), each with one MVCCID, one row change
     NInit      rows present before every writer
     H          entries of the status history ring (2048 in the code)
     NStmt      statements of the reader's transaction
     NOps, Prog the reads of each statement, in execution order ("scan" | "count")
     Isolation  "RC" | "RR"
     StatsFix   the fix (CBRD-27967): statistics loaded by the build or late stay
                provisional (COS_LOADING) until a check finds the current status
                version (m_current_trans_status.m_version, raised before a commit
                publishes its statistics) equal to the snapshot's version; otherwise
                the class goes back to COS_TO_LOAD and COUNT-star falls back to a scan
     TornFix    candidate fix: a history entry is marked busy while it is refilled;
                the reader rejects a busy entry at both version loads
     Mutant     "none" | "no_invalidate" | "no_allvisible" | "vacuum_no_wait"
                | "vacuum_ignores_slot" | "no_recheck" | "pos_before_fill"
                | "rr_invalidate" | "busy_stuck" | "build_no_conf" | "late_no_conf"
                | "pos_check" *)
EXTENDS Naturals, FiniteSets

CONSTANTS NW, NInit, H, NStmt, NOps, Prog, Isolation, StatsFix, TornFix, Mutant, VacRounds

\* apalache-type: NW Int
\* apalache-type: NInit Int
\* apalache-type: H Int
\* apalache-type: NStmt Int
\* apalache-type: NOps Int
\* apalache-type: Prog Int -> Str
\* apalache-type: Isolation Str
\* apalache-type: StatsFix Bool
\* apalache-type: TornFix Bool
\* apalache-type: Mutant Str
\* apalache-type: VacRounds Int
\* apalache-type: wpc Int -> Str
\* apalache-type: wid Int -> Int
\* apalache-type: wrow Int -> Int
\* apalache-type: wins Int -> Bool
\* apalache-type: wnx Int -> Int
\* apalache-type: wver Int -> Int
\* apalache-type: wk Int -> Int
\* apalache-type: ins Int -> Int
\* apalache-type: del Int -> Int
\* apalache-type: gone Int -> Bool
\* apalache-type: cmutex Int
\* apalache-type: curVer Int
\* apalache-type: pos Int
\* apalache-type: ver Int -> Int
\* apalache-type: busy Int -> Bool
\* apalache-type: data Int -> Set(Int)
\* apalache-type: cur Set(Int)
\* apalache-type: gstats Set(Int)
\* apalache-type: histv Int -> Set(Int)
\* apalache-type: G Int
\* apalache-type: acked Set(Int)
\* apalache-type: rpc Str
\* apalache-type: stmt Int
\* apalache-type: opi Int
\* apalache-type: flag Bool
\* apalache-type: valid Bool
\* apalache-type: slot Int
\* apalache-type: rg Int
\* apalache-type: rpos Int
\* apalache-type: rver Int
\* apalache-type: rk Int
\* apalache-type: rcopy Set(Int)
\* apalache-type: snapLow Int
\* apalache-type: snapSet Set(Int)
\* apalache-type: cos Str
\* apalache-type: cstats Set(Int)
\* apalache-type: startAcked Set(Int)
\* apalache-type: sver Int
\* apalache-type: snapVer Int
\* apalache-type: badStale Bool
\* apalache-type: badScan Bool
\* apalache-type: badCount Bool
\* apalache-type: badCut Bool
\* apalache-type: snapChanged Bool
\* apalache-type: badOV Bool
\* apalache-type: vpc Str
\* apalache-type: vg Int
\* apalache-type: vov Int
\* apalache-type: OV Int
\* apalache-type: vrounds Int

ASSUME Assm ==
  /\ NW \in Nat \ {0} /\ NInit \in Nat \ {0} /\ H \in Nat /\ H >= 2 /\ NStmt \in Nat \ {0}
  /\ NOps \in Nat \ {0} /\ \A k \in DOMAIN Prog : Prog[k] \in {"scan", "count"}   \* DOMAIN Prog = 1..NOps (ProgScanCount, ProgCountScan)
  /\ Isolation \in {"RC", "RR"} /\ StatsFix \in BOOLEAN /\ TornFix \in BOOLEAN
  /\ Mutant \in {"none", "no_invalidate", "no_allvisible", "vacuum_no_wait",
                 "vacuum_ignores_slot", "no_recheck", "pos_before_fill", "rr_invalidate", "busy_stuck",
                 "build_no_conf", "late_no_conf", "pos_check"}
  /\ VacRounds \in Nat

\* statement programs (a TLC cfg cannot write a sequence)
ProgScanCount == [k \in 1..2 |-> IF k = 1 THEN "scan" ELSE "count"]
ProgCountScan == [k \in 1..2 |-> IF k = 1 THEN "count" ELSE "scan"]

W == 1..NW                          \* writer w gets one MVCCID (wid[w]) and changes one row
Ids == 1..NW                        \* MVCCIDs, in assignment order
Rows == 1..(NInit + NW)             \* row NInit + w is the row writer w may insert
Ent == 0..(H - 1)
NoRow == 0
AllV == NW + 100                    \* MVCCID_ALL_VISIBLE in a slot
Max(a, b) == IF a >= b THEN a ELSE b
\* compute_lowest_active_mvccid over a completed set: the first id not completed (ids not
\* yet assigned count as active)
LowestActive(S) == IF \E i \in Ids : i \notin S THEN CHOOSE i \in Ids : i \notin S /\ \A j \in Ids : j < i => j \in S
                   ELSE NW + 1     \* (documentation; WAdvance takes any lower bound of it)

VARIABLES wpc, wid, wrow, wins, wnx, wver, wk, ins, del, gone,
          cmutex, curVer, pos, ver, busy, data, cur, gstats, histv, G, acked,
          rpc, stmt, opi, flag, valid, slot, rg, rpos, rver, rk, rcopy,
          snapLow, snapSet, cos, cstats, startAcked, sver, snapVer,
          badStale, badScan, badCount, badCut, snapChanged, badOV,
          vpc, vg, vov, OV, vrounds
wVars == <<wpc, wid, wrow, wins, wnx, wver, wk, ins, del>>
tVars == <<cmutex, curVer, pos, ver, busy, data, cur, gstats, histv, G, acked>>
rVars == <<rpc, stmt, opi, flag, valid, slot, rg, rpos, rver, rk, rcopy,
           snapLow, snapSet, cos, cstats, startAcked, sver, snapVer>>
\* @type: <<Bool, Bool, Bool, Bool, Bool, Bool>>;
gVars == <<badStale, badScan, badCount, badCut, snapChanged, badOV>>
vVars == <<vpc, vg, vov, OV, vrounds, gone>>
vars == <<wVars, tVars, rVars, gVars, vVars>>

\* ---- visibility through the reader's snapshot ----
CommittedIn(i) == i < snapLow \/ i \in snapSet
\* mvcc_satisfies_snapshot: inserted by a committed writer (or before all) and not deleted by one
Visible(r) == ((ins[r] = 0 /\ r <= NInit) \/ (ins[r] > 0 /\ CommittedIn(ins[r])))
              /\ ~(del[r] > 0 /\ CommittedIn(del[r]))
\* what a scan returns: visible versions vacuum has not removed
ScanResult == {r \in Rows : Visible(r) /\ ~gone[r]}
IdealRows == {r \in Rows : Visible(r)}
\* the writers whose changes the snapshot includes
SnapWriters == {w \in W : wid[w] > 0 /\ CommittedIn(wid[w])}
\* what COUNT-star holds: the writers whose statistics deltas were loaded
CountWriters(S) == {w \in W : wid[w] \in S}
\* the snapshot's committed set as a set of ids
SnapIds == {i \in Ids : CommittedIn(i)}

Kind(k) == IF Isolation = "RR" /\ k = "count" THEN "scan" ELSE k   \* RR: COUNT-star optimization off
HasCount == \E k \in 1..NOps : Kind(Prog[k]) = "count"

Init ==
  /\ wpc = [w \in W |-> "begin"] /\ wid = [w \in W |-> 0] /\ wrow = [w \in W |-> NoRow]
  /\ wins = [w \in W |-> FALSE] /\ wnx = [w \in W |-> 0] /\ wver = [w \in W |-> 0] /\ wk = [w \in W |-> 1]
  /\ ins = [r \in Rows |-> 0] /\ del = [r \in Rows |-> 0] /\ gone = [r \in Rows |-> FALSE]
  /\ cmutex = 0 /\ curVer = 0 /\ pos = 0
  /\ ver = [e \in Ent |-> 0] /\ busy = [e \in Ent |-> FALSE]
  /\ data = [e \in Ent |-> {}]
  /\ cur = {} /\ gstats = {} /\ histv = [v \in 0..NW |-> {}] /\ G = 1 /\ acked = {}
  /\ rpc = "idle" /\ stmt = 1 /\ opi = 1 /\ flag = FALSE /\ valid = FALSE /\ slot = 0
  /\ rg = 0 /\ rpos = 0 /\ rver = 0 /\ rk = 1 /\ rcopy = {}
  /\ snapLow = 0 /\ snapSet = {} /\ cos = "not" /\ cstats = {} /\ startAcked = {} /\ sver = 0 /\ snapVer = 0
  /\ badStale = FALSE /\ badScan = FALSE /\ badCount = FALSE /\ badCut = FALSE /\ snapChanged = FALSE /\ badOV = FALSE
  /\ vpc = "idle" /\ vg = 0 /\ vov = 0 /\ OV = 1 /\ vrounds = VacRounds

\* ---------------- writers ----------------
\* logtb_get_current_mvccid: get_new_mvccid at the first change. Writer w gets MVCCID w: any
\* order of assignment against the order of begins, which over-approximates the code's
WBegin(w) ==
  /\ wpc[w] = "begin"
  /\ wid' = [wid EXCEPT ![w] = w]
  /\ wpc' = [wpc EXCEPT ![w] = "op"]
  /\ UNCHANGED <<wrow, wins, wnx, wver, wk, ins, del, tVars, rVars, gVars, vVars>>

\* heap_insert of its own row, or heap_delete of a row nobody else deleted (the row lock)
WOp(w) ==
  /\ wpc[w] = "op"
  /\ \/ /\ ins' = [ins EXCEPT ![NInit + w] = wid[w]] /\ del' = del
        /\ wrow' = [wrow EXCEPT ![w] = NInit + w] /\ wins' = [wins EXCEPT ![w] = TRUE]
     \/ \E r \in 1..NInit :
          /\ del[r] = 0 /\ del' = [del EXCEPT ![r] = wid[w]] /\ ins' = ins
          /\ wrow' = [wrow EXCEPT ![w] = r] /\ wins' = wins
  /\ wpc' = [wpc EXCEPT ![w] = "lock"]
  /\ UNCHANGED <<wid, wnx, wver, wk, gone, tVars, rVars, gVars, vpc, vg, vov, OV, vrounds>>

\* complete_mvcc: std::unique_lock (m_active_trans_mutex)
WLock(w) ==
  /\ wpc[w] = "lock" /\ cmutex = 0
  /\ cmutex' = w /\ wpc' = [wpc EXCEPT ![w] = "start"]
  /\ UNCHANGED <<wid, wrow, wins, wnx, wver, wk, ins, del, curVer, pos, ver, busy, data,
                 cur, gstats, histv, G, acked, rVars, gVars, vVars>>

\* next_trans_status_start: the next entry gets a fresh version before its data
WStart(w) ==
  LET nx == (pos + 1) % H IN
  /\ wpc[w] = "start" /\ curVer < NW          \* each writer commits once: curVer <= NW
  /\ curVer' = curVer + 1
  /\ ver' = [ver EXCEPT ![nx] = curVer + 1]
  /\ busy' = [busy EXCEPT ![nx] = TornFix]
  /\ wnx' = [wnx EXCEPT ![w] = nx] /\ wver' = [wver EXCEPT ![w] = curVer + 1]
  /\ histv' = [histv EXCEPT ![curVer + 1] = cur]
  /\ wpc' = [wpc EXCEPT ![w] = "stats"]
  /\ UNCHANGED <<wid, wrow, wins, wk, ins, del, cmutex, pos, data, cur, gstats, G, acked,
                 rVars, gVars, vVars>>

\* logtb_tran_update_all_global_unique_stats
WStats(w) ==
  /\ wpc[w] = "stats"
  /\ gstats' = gstats \cup {wid[w]}
  /\ wpc' = [wpc EXCEPT ![w] = "inactive"]
  /\ UNCHANGED <<wid, wrow, wins, wnx, wver, wk, ins, del, cmutex, curVer, pos, ver, busy, data,
                 cur, histv, G, acked, rVars, gVars, vVars>>

\* m_current_trans_status.m_active_mvccs.set_inactive_mvccid: the commit point
WInactive(w) ==
  /\ wpc[w] = "inactive"
  /\ cur' = cur \cup {wid[w]}
  /\ histv' = [histv EXCEPT ![wver[w]] = cur \cup {wid[w]}]
  /\ wk' = [wk EXCEPT ![w] = 1]
  /\ wpc' = [wpc EXCEPT ![w] = IF Mutant = "pos_before_fill" THEN "pos" ELSE "fill"]
  /\ UNCHANGED <<wid, wrow, wins, wnx, wver, ins, del, cmutex, curVer, pos, ver, busy, data,
                 gstats, G, acked, rVars, gVars, vVars>>

\* next_tran_status_finish: m_active_mvccs.copy_to, id by id
WFill(w) ==
  LET nx == wnx[w]
      k == wk[w] IN
  /\ wpc[w] = "fill"
  /\ data' = [data EXCEPT ![nx] = IF k \in cur THEN @ \cup {k} ELSE @ \ {k}]
  /\ wk' = [wk EXCEPT ![w] = k + 1]
  /\ wpc' = [wpc EXCEPT ![w] = IF k = NW THEN (IF Mutant = "pos_before_fill" THEN "unlock" ELSE "pos") ELSE "fill"]
  /\ UNCHANGED <<wid, wrow, wins, wnx, wver, ins, del, cmutex, curVer, pos, ver, busy, cur, gstats,
                 histv, G, acked, rVars, gVars, vVars>>

\* m_trans_status_history_position.store (next_index)
WPos(w) ==
  /\ wpc[w] = "pos"
  /\ pos' = wnx[w]
  /\ busy' = IF Mutant = "busy_stuck" THEN busy ELSE [busy EXCEPT ![wnx[w]] = FALSE]
  /\ wpc' = [wpc EXCEPT ![w] = IF Mutant = "pos_before_fill" THEN "fill" ELSE "unlock"]
  /\ UNCHANGED <<wid, wrow, wins, wnx, wver, wk, ins, del, cmutex, curVer, ver, data, cur, gstats,
                 histv, G, acked, rVars, gVars, vVars>>

WUnlock(w) ==
  /\ wpc[w] = "unlock"
  /\ cmutex' = 0 /\ wpc' = [wpc EXCEPT ![w] = "advance"]
  /\ UNCHANGED <<wid, wrow, wins, wnx, wver, wk, ins, del, curVer, pos, ver, busy, data,
                 cur, gstats, histv, G, acked, rVars, gVars, vVars>>

\* after the mutex: recompute the lowest active from the entry it published, keep it only
\* if the entry still holds its version, advance_oldest_active (CAS max)
WAdvance(w) ==
  /\ wpc[w] = "advance"
  /\ IF ver[wnx[w]] = wver[w]
       THEN \E g \in 1..(NW + 1) : (\A i \in Ids : i < g => i \in data[wnx[w]]) /\ G' = Max(G, g)
       ELSE G' = G
  /\ wpc' = [wpc EXCEPT ![w] = "ack"]
  /\ UNCHANGED <<wid, wrow, wins, wnx, wver, wk, ins, del, cmutex, curVer, pos, ver, busy, data,
                 cur, gstats, histv, acked, rVars, gVars, vVars>>

\* LOG_COMMIT flushed, the client has its answer
WAck(w) ==
  /\ wpc[w] = "ack"
  /\ acked' = acked \cup {w} /\ wpc' = [wpc EXCEPT ![w] = "done"]
  /\ UNCHANGED <<wid, wrow, wins, wnx, wver, wk, ins, del, cmutex, curVer, pos, ver, busy, data,
                 cur, gstats, histv, G, rVars, gVars, vVars>>

\* ---------------- the reader ----------------
rUnch == <<wVars, tVars, gone, vpc, vg, vov, OV, vrounds>>

\* compile (pt_class_pre_fetch marks COUNT-star classes COS_TO_LOAD), then db_execute_statement
\* sets tm_Tran_invalidate_snapshot (READ COMMITTED)
StmtBegin ==
  /\ rpc = "idle" /\ stmt <= NStmt
  /\ cos' = IF HasCount /\ cos # "loaded" THEN "to_load" ELSE cos
  /\ flag' = ((Isolation = "RC" \/ Mutant = "rr_invalidate") /\ Mutant # "no_invalidate")
  /\ startAcked' = IF Isolation = "RC" \/ stmt = 1 THEN acked ELSE startAcked
  /\ sver' = IF Isolation = "RC" \/ stmt = 1 THEN ver[pos] ELSE sver
  /\ rpc' = "exec"
  /\ UNCHANGED <<stmt, opi, valid, slot, rg, rpos, rver, rk, rcopy, snapLow, snapSet, cstats, snapVer, gVars, rUnch>>

\* the statement's first request: net_server_request -> logtb_invalidate_snapshot_data
Exec ==
  /\ rpc = "exec"
  /\ IF flag /\ valid
       THEN valid' = FALSE /\ cos' = "not"          \* logtb_tran_reset_count_optim_state
       ELSE UNCHANGED <<valid, cos>>
  /\ flag' = FALSE /\ opi' = 1 /\ rpc' = "op"
  /\ UNCHANGED <<stmt, slot, rg, rpos, rver, rk, rcopy, snapLow, snapSet, cstats, startAcked, sver, snapVer, gVars, rUnch>>

\* a read on a valid snapshot: a heap or index scan
ScanRead ==
  /\ rpc = "op" /\ opi <= NOps /\ valid
  /\ \/ Kind(Prog[opi]) = "scan"
  /\ badScan' = (badScan \/ ScanResult # IdealRows)
  /\ badStale' = (badStale \/ ~(startAcked \subseteq SnapWriters))
  /\ opi' = opi + 1
  /\ UNCHANGED <<rpc, stmt, flag, valid, slot, rg, rpos, rver, rk, rcopy, snapLow, snapSet, cos, cstats,
                 startAcked, sver, snapVer, badCount, badCut, snapChanged, badOV, rUnch>>

\* a read that needs the snapshot and finds none: logtb_get_mvcc_snapshot -> build_mvcc_info
NeedBuild ==
  /\ rpc = "op" /\ opi <= NOps /\ ~valid
  /\ cos' = IF Kind(Prog[opi]) = "count" /\ cos # "loaded" THEN "to_load" ELSE cos
  /\ rpc' = "b_slot"
  /\ UNCHANGED <<stmt, opi, flag, valid, slot, rg, rpos, rver, rk, rcopy, snapLow, snapSet, cstats,
                 startAcked, sver, snapVer, gVars, rUnch>>

\* qexec_evaluate_aggregates_optimize on a valid snapshot: answer from the loaded statistics;
\* the code before the fix also loads them late here when they are not loaded (CBRD-26571)
CountRead ==
  /\ rpc = "op" /\ opi <= NOps /\ valid /\ Kind(Prog[opi]) = "count"
  /\ StatsFix => cos = "loaded"
  /\ LET st == IF cos = "loaded" THEN cstats ELSE gstats IN
       /\ cstats' = st /\ cos' = "loaded"
       /\ badCount' = (badCount \/ CountWriters(st) # SnapWriters)
  /\ opi' = opi + 1
  /\ UNCHANGED <<rpc, stmt, flag, valid, slot, rg, rpos, rver, rk, rcopy, snapLow, snapSet, startAcked, sver, snapVer,
                 badStale, badScan, badCut, snapChanged, badOV, rUnch>>

\* the build: the slot first (MVCCID_ALL_VISIBLE when it holds none)
BSlot ==
  /\ rpc = "b_slot"
  /\ slot' = IF slot = 0 /\ Mutant # "no_allvisible" THEN AllV ELSE slot
  /\ rpc' = "b_readg"
  /\ UNCHANGED <<stmt, opi, flag, valid, rg, rpos, rver, rk, rcopy, snapLow, snapSet, cos, cstats,
                 startAcked, sver, snapVer, gVars, rUnch>>

\* crt_status_lowest_active = m_current_status_lowest_active_mvccid
BReadG ==
  /\ rpc = "b_readg"
  /\ rg' = G
  /\ rpc' = IF slot = AllV \/ (slot = 0 /\ Mutant = "no_allvisible") THEN "b_setslot" ELSE "b_pos"
  /\ UNCHANGED <<stmt, opi, flag, valid, slot, rpos, rver, rk, rcopy, snapLow, snapSet, cos, cstats,
                 startAcked, sver, snapVer, gVars, rUnch>>

\* oldest_active_set (slot, crt_status_lowest_active)
BSetSlot ==
  /\ rpc = "b_setslot"
  /\ slot' = rg /\ rpc' = "b_pos"
  /\ UNCHANGED <<stmt, opi, flag, valid, rg, rpos, rver, rk, rcopy, snapLow, snapSet, cos, cstats,
                 startAcked, sver, snapVer, gVars, rUnch>>

BPos ==
  /\ rpc = "b_pos"
  /\ rpos' = pos /\ rpc' = "b_ver"
  /\ UNCHANGED <<stmt, opi, flag, valid, slot, rg, rver, rk, rcopy, snapLow, snapSet, cos, cstats,
                 startAcked, sver, snapVer, gVars, rUnch>>

\* trans_status.m_version.load ()
BVer ==
  /\ rpc = "b_ver"
  /\ IF TornFix /\ busy[rpos]
       THEN rpc' = "b_readg" /\ UNCHANGED <<rver, rk, rcopy>>
       ELSE rver' = ver[rpos] /\ rk' = 1 /\ rcopy' = {} /\ rpc' = "b_copy"
  /\ UNCHANGED <<stmt, opi, flag, valid, slot, rg, rpos, snapLow, snapSet, cos, cstats,
                 startAcked, sver, snapVer, gVars, rUnch>>

\* copy_to (THREAD_UNSAFE), id by id
BCopy ==
  /\ rpc = "b_copy"
  /\ rcopy' = IF rk \in data[rpos] THEN rcopy \cup {rk} ELSE rcopy
  /\ rk' = rk + 1
  /\ rpc' = IF rk = NW THEN "b_stats" ELSE "b_copy"
  /\ UNCHANGED <<stmt, opi, flag, valid, slot, rg, rpos, rver, snapLow, snapSet, cos, cstats,
                 startAcked, sver, snapVer, gVars, rUnch>>

\* logtb_load_global_statistics_to_tran: a class marked COS_TO_LOAD is loaded and becomes
\* COS_LOADED at once, so a retry of the loop keeps it; StatsFix: it becomes COS_LOADING, and a
\* retry of the loop loads a COS_LOADING class again
BStats ==
  /\ rpc = "b_stats"
  /\ IF cos = "to_load" \/ cos = "loading"
       THEN /\ cstats' = gstats
            /\ cos' = (IF StatsFix THEN "loading" ELSE "loaded")
       ELSE UNCHANGED <<cstats, cos>>
  /\ rpc' = "b_check"
  /\ UNCHANGED <<stmt, opi, flag, valid, slot, rg, rpos, rver, rk, rcopy, snapLow, snapSet,
                 startAcked, sver, snapVer, gVars, rUnch>>

\* the version recheck; the snapshot becomes valid
BCheck ==
  /\ rpc = "b_check"
  /\ IF Mutant = "no_recheck" \/ (ver[rpos] = rver /\ ~(TornFix /\ busy[rpos]))
       THEN /\ valid' = TRUE /\ snapLow' = rg /\ snapSet' = rcopy
            /\ snapVer' = rver
            /\ badCut' = (badCut \/ ~(\E v \in 0..NW : v <= curVer /\ histv[v] = {i \in Ids : i < rg \/ i \in rcopy}))
            /\ snapChanged' = (snapChanged \/ (Isolation = "RR" /\ stmt > 1))
            /\ rpc' = IF StatsFix THEN "b_conf" ELSE "op"
       ELSE /\ rpc' = "b_readg"
            /\ UNCHANGED <<valid, snapLow, snapSet, snapVer, badCut, snapChanged>>
  /\ UNCHANGED <<stmt, opi, flag, slot, rg, rpos, rver, rk, rcopy, cos, cstats, startAcked, sver,
                 badStale, badScan, badCount, badOV, rUnch>>

\* the version the statistics are checked against: the current status version, raised by
\* next_trans_status_start before a commit publishes its statistics (pos_check: the version of
\* the entry at the history position, which an in-flight commit has not replaced yet)
StatsVer == IF Mutant = "pos_check" THEN ver[pos] ELSE curVer

\* logtb_confirm_global_statistics after the build loop: COS_LOADING becomes COS_LOADED only if no
\* commit raised the status version since the snapshot's entry
BConf ==
  /\ rpc = "b_conf"
  /\ cos' = IF cos = "loading"
             THEN (IF Mutant = "build_no_conf" \/ StatsVer = snapVer THEN "loaded" ELSE "to_load")
             ELSE cos
  /\ rpc' = "op"
  /\ UNCHANGED <<stmt, opi, flag, valid, slot, rg, rpos, rver, rk, rcopy, snapLow, snapSet, cstats,
                 startAcked, sver, snapVer, gVars, rUnch>>

\* qexec_evaluate_aggregates_optimize, statistics not loaded on a valid snapshot (CBRD-26571):
\* load them late as COS_LOADING ...
CountLate ==
  /\ StatsFix /\ rpc = "op" /\ opi <= NOps /\ valid /\ Kind(Prog[opi]) = "count" /\ cos # "loaded"
  /\ cstats' = gstats /\ cos' = "loading" /\ rpc' = "c_conf"
  /\ UNCHANGED <<stmt, opi, flag, valid, slot, rg, rpos, rver, rk, rcopy, snapLow, snapSet,
                 startAcked, sver, snapVer, gVars, rUnch>>

\* ... and confirm them against the snapshot's version: answer from them, or fall back to a scan
CountConf ==
  /\ rpc = "c_conf"
  /\ IF Mutant = "late_no_conf" \/ StatsVer = snapVer
       THEN /\ cos' = "loaded"
            /\ badCount' = (badCount \/ CountWriters(cstats) # SnapWriters)
            /\ UNCHANGED <<badScan, badStale>>
       ELSE /\ cos' = "to_load"
            /\ badScan' = (badScan \/ ScanResult # IdealRows)
            /\ badStale' = (badStale \/ ~(startAcked \subseteq SnapWriters))
            /\ UNCHANGED badCount
  /\ opi' = opi + 1 /\ rpc' = "op"
  /\ UNCHANGED <<stmt, flag, valid, slot, rg, rpos, rver, rk, rcopy, snapLow, snapSet, cstats,
                 startAcked, sver, snapVer, badCut, snapChanged, badOV, rUnch>>

StmtEnd ==
  /\ rpc = "op" /\ opi > NOps
  /\ stmt' = stmt + 1
  /\ rpc' = IF stmt = NStmt THEN "tend" ELSE "idle"
  /\ UNCHANGED <<opi, flag, valid, slot, rg, rpos, rver, rk, rcopy, snapLow, snapSet, cos, cstats,
                 startAcked, sver, snapVer, gVars, rUnch>>

\* commit of the reader: the snapshot and the slot go (logtb_complete_mvcc, reset_transaction_lowest_active)
TEnd ==
  /\ rpc = "tend"
  /\ valid' = FALSE /\ slot' = 0 /\ cos' = "not" /\ rpc' = "end"
  /\ UNCHANGED <<stmt, opi, flag, rg, rpos, rver, rk, rcopy, snapLow, snapSet, cstats,
                 startAcked, sver, snapVer, gVars, rUnch>>

\* ---------------- vacuum ----------------
vUnch == <<wVars, tVars, rVars, gVars>>

\* compute_oldest_visible_mvccid: G first ...
VReadG ==
  /\ vpc = "idle" /\ vrounds > 0
  /\ vg' = G /\ vpc' = "slot" /\ vrounds' = vrounds - 1
  /\ UNCHANGED <<vov, OV, gone, vUnch>>

\* ... then the reader's slot, waiting while it holds MVCCID_ALL_VISIBLE
VSlot ==
  /\ vpc = "slot"
  /\ slot # AllV \/ Mutant = "vacuum_no_wait"
  /\ vov' = IF slot # 0 /\ slot # AllV /\ slot < vg /\ Mutant # "vacuum_ignores_slot" THEN slot ELSE vg
  /\ vpc' = "store"
  /\ UNCHANGED <<vg, OV, vrounds, gone, vUnch>>

\* update_global_oldest_visible: m_oldest_visible.store (asserted never to move back)
VStore ==
  /\ vpc = "store"
  /\ OV' = vov /\ vpc' = "idle"
  /\ badOV' = (badOV \/ vov < OV)
  /\ UNCHANGED <<vg, vov, vrounds, gone, wVars, tVars, rVars, badStale, badScan, badCount, badCut, snapChanged>>

\* vacuum_heap_page: a version deleted below the threshold is removed
VRemove(r) ==
  /\ del[r] > 0 /\ del[r] < OV /\ ~gone[r]
  /\ gone' = [gone EXCEPT ![r] = TRUE]
  /\ UNCHANGED <<vpc, vg, vov, OV, vrounds, vUnch>>

Done == rpc = "end" /\ \A w \in W : wpc[w] = "done"
Terminated == Done /\ UNCHANGED vars

WStep(w) == WBegin(w) \/ WOp(w) \/ WLock(w) \/ WStart(w) \/ WStats(w) \/ WInactive(w) \/ WFill(w)
            \/ WPos(w) \/ WUnlock(w) \/ WAdvance(w) \/ WAck(w)
RStep == StmtBegin \/ Exec \/ ScanRead \/ NeedBuild \/ CountRead \/ BSlot \/ BReadG \/ BSetSlot \/ BPos
         \/ BVer \/ BCopy \/ BStats \/ BCheck \/ BConf \/ CountLate \/ CountConf \/ StmtEnd \/ TEnd
VStep == VReadG \/ VSlot \/ VStore \/ \E r \in Rows : VRemove(r)

Next == Terminated \/ RStep \/ VStep \/ \E w \in W : WStep(w)
Spec == Init /\ [][Next]_vars
FairSpec == Spec /\ WF_vars(RStep) /\ \A w \in W : WF_vars(WStep(w))

\* ---------------- properties ----------------
\* C1: a statement's snapshot includes every writer whose commit was acknowledged before
\* the statement began (before the transaction's first statement, REPEATABLE READ)
NoStaleRead == ~badStale
\* C2: every scan of a statement returns exactly what the statement's snapshot sees
ScanMatchesSnapshot == ~badScan
\* C3: COUNT-star answers for the same snapshot as the statement's scans
CountMatchesSnapshot == ~badCount
\* C4: a snapshot is the committed set at one instant (a value the current status held)
ConsistentCut == ~badCut
\* C5: REPEATABLE READ: one snapshot for the whole transaction
RRStable == ~snapChanged
\* C7: vacuum's threshold never moves back (the assert in update_global_oldest_visible)
OVMonotone == ~badOV
\* C6: the reader's transaction ends
ReaderEnds == <>(rpc = "end")

\* ---------------- inductive invariant of the fixes (StatsFix, TornFix, Mutant = "none") ----------------
WPhases == {"begin", "op", "lock", "start", "stats", "inactive", "fill", "pos", "unlock", "advance", "ack", "done"}
Locked == {"start", "stats", "inactive", "fill", "pos", "unlock"}
InFlight == {"stats", "inactive", "fill", "pos"}
AfterInactive == {"fill", "pos", "unlock", "advance", "ack", "done"}
AfterStats == {"inactive", "fill", "pos", "unlock", "advance", "ack", "done"}
Published == {"unlock", "advance", "ack", "done"}
BuildPh == {"b_slot", "b_readg", "b_setslot", "b_pos", "b_ver", "b_copy", "b_stats", "b_check"}
AfterReadG == {"b_setslot", "b_pos", "b_ver", "b_copy", "b_stats", "b_check"}
AfterVer == {"b_copy", "b_stats", "b_check"}
RPhases == {"idle", "exec", "op", "tend", "end", "b_conf", "c_conf"} \cup BuildPh
SlotSet(x) == x # 0 /\ x # AllV

BoolOK ==
  /\ wins \in [W -> BOOLEAN] /\ gone \in [Rows -> BOOLEAN] /\ busy \in [Ent -> BOOLEAN]
  /\ flag \in BOOLEAN /\ valid \in BOOLEAN
  /\ badStale \in BOOLEAN /\ badScan \in BOOLEAN /\ badCount \in BOOLEAN /\ badCut \in BOOLEAN
  /\ snapChanged \in BOOLEAN /\ badOV \in BOOLEAN
NatOK ==
  /\ wid \in [W -> 0..NW] /\ wrow \in [W -> 0..(NInit + NW)] /\ wnx \in [W -> Ent] /\ wver \in [W -> 0..NW]
  /\ wk \in [W -> 1..(NW + 1)] /\ ins \in [Rows -> 0..NW] /\ del \in [Rows -> 0..NW]
  /\ cmutex \in 0..NW /\ curVer \in 0..NW /\ pos \in Ent /\ ver \in [Ent -> 0..NW] /\ G \in 1..(NW + 1)
  /\ stmt \in 1..(NStmt + 1) /\ opi \in 1..(NOps + 1) /\ slot \in Nat /\ rg \in Nat /\ rpos \in Ent
  /\ rver \in 0..NW /\ rk \in 1..(NW + 1) /\ snapLow \in Nat /\ sver \in 0..NW /\ snapVer \in 0..NW
  /\ vg \in Nat /\ vov \in Nat /\ OV \in Nat /\ vrounds \in Nat
SetOK ==
  /\ wpc \in [W -> WPhases] /\ data \in [Ent -> SUBSET Ids]
  /\ cur \in SUBSET Ids /\ gstats \in SUBSET Ids /\ histv \in [0..NW -> SUBSET Ids]
  /\ acked \in SUBSET W /\ startAcked \in SUBSET W /\ rpc \in RPhases /\ rcopy \in SUBSET Ids
  /\ snapSet \in SUBSET Ids /\ cos \in {"not", "to_load", "loading", "loaded"} /\ cstats \in SUBSET Ids
  /\ vpc \in {"idle", "slot", "store"}
TypeOK == BoolOK /\ NatOK /\ SetOK

I_fix == StatsFix /\ TornFix /\ Mutant = "none"
\* writers and the status history
I_wid == \A w \in W : (wpc[w] = "begin") = (wid[w] = 0) /\ (wid[w] # 0 => wid[w] = w)
I_mutex == \A w \in W : (wpc[w] \in Locked) = (cmutex = w)
I_cur == \A i \in Ids : (i \in cur) = (\E w \in W : wid[w] = i /\ wpc[w] \in AfterInactive)
I_gst == \A i \in Ids : (i \in gstats) = (\E w \in W : wid[w] = i /\ wpc[w] \in AfterStats)
I_hist == /\ histv[curVer] = cur
          /\ \A v1, v2 \in 0..NW : v1 <= v2 /\ v2 <= curVer => histv[v1] \subseteq histv[v2]
I_ent == \A e \in Ent : ver[e] <= curVer /\ (~busy[e] => ver[e] <= ver[pos] /\ data[e] = histv[ver[e]])
I_pos == ~busy[pos]
I_cv == /\ (\E w \in W : wpc[w] \in InFlight) => curVer = ver[pos] + 1
        /\ (\A w \in W : wpc[w] \notin InFlight) => curVer = ver[pos]
I_fly == \A w \in W : wpc[w] \in InFlight => wver[w] = curVer /\ ver[wnx[w]] = curVer /\ busy[wnx[w]] /\ wnx[w] # pos
I_busy == \A e \in Ent : busy[e] => \E w \in W : wpc[w] \in InFlight /\ wnx[w] = e
I_fill == \A w \in W :
            /\ wpc[w] = "fill" => wk[w] \in 1..NW /\ \A j \in Ids : j < wk[w] => (j \in data[wnx[w]] <=> j \in cur)
            /\ wpc[w] = "pos" => data[wnx[w]] = cur
I_pub == \A w \in W : wpc[w] \in Published =>
           /\ 1 <= wver[w] /\ wver[w] <= ver[pos] /\ wid[w] \in histv[wver[w]]
           /\ (wpc[w] \in {"unlock", "advance"} /\ ver[wnx[w]] = wver[w] => ~busy[wnx[w]])
I_G == \A i \in Ids : i < G => i \in histv[ver[pos]]
I_acked == /\ \A w \in acked : wpc[w] = "done"
           /\ startAcked \subseteq acked
\* the reader
I_iso == /\ Isolation = "RR" => ~flag
         /\ Isolation = "RC" /\ rpc = "exec" => flag
I_build == /\ rpc \in BuildPh => ~valid /\ 1 <= opi /\ opi <= NOps /\ 1 <= stmt /\ stmt <= NStmt
           /\ rpc \in {"b_conf", "c_conf"} => valid /\ 1 <= opi /\ opi <= NOps
I_stmt == /\ rpc \in {"tend", "end"} => stmt = NStmt + 1
          /\ rpc \in {"idle", "exec", "op", "b_conf", "c_conf"} => 1 <= stmt /\ stmt <= NStmt
I_ops == /\ rpc = "op" /\ opi > 1 => valid
         /\ rpc \in {"idle", "exec"} /\ stmt > 1 => valid
         /\ rpc \in {"idle", "exec"} /\ stmt = 1 => ~valid /\ slot = 0
         /\ Isolation = "RR" /\ stmt > 1 => rpc \notin BuildPh /\ (rpc = "op" => valid)
I_slotA == /\ slot = AllV => rpc \in {"b_readg", "b_setslot"}
           /\ rpc = "b_setslot" => slot = AllV
           /\ rpc = "b_readg" => slot # 0
I_slot == SlotSet(slot) => 1 <= slot /\ slot <= G /\ OV <= slot
I_slotv == valid => SlotSet(slot) /\ slot <= snapLow
I_slotb == rpc \in AfterReadG \ {"b_setslot"} => SlotSet(slot) /\ slot <= rg
I_rg == rpc \in AfterReadG => rg <= G /\ \A i \in Ids : i < rg => i \in histv[ver[pos]]
I_rgb == rpc = "b_setslot" => OV <= rg /\ (vpc = "store" => vov <= rg)
I_rpos == rpc \in {"b_ver"} \cup AfterVer =>
            /\ ver[rpos] >= sver /\ \A i \in Ids : i < rg => i \in histv[ver[rpos]]
I_rver == rpc \in AfterVer =>
            /\ rver >= sver /\ rver <= ver[pos] /\ ver[rpos] >= rver
            /\ \A i \in Ids : i < rg => i \in histv[rver]
            /\ (ver[rpos] = rver => ~busy[rpos])
I_copy == rpc = "b_copy" =>
            /\ rk \in 1..NW /\ \A j \in rcopy : j < rk
            /\ (ver[rpos] = rver => \A j \in Ids : j < rk => (j \in rcopy <=> j \in histv[rver]))
I_copied == rpc \in {"b_stats", "b_check"} => (ver[rpos] = rver => rcopy = histv[rver])
I_snap == valid => /\ snapSet = histv[snapVer] /\ snapVer <= ver[pos] /\ snapLow <= G
                   /\ \A i \in Ids : i < snapLow => i \in snapSet
I_sver == /\ sver <= ver[pos]
          /\ \A w \in startAcked : wver[w] <= sver
          /\ valid /\ (rpc # "exec" \/ Isolation = "RR") => snapVer >= sver
I_cos == /\ cos = "loaded" => valid /\ cstats = snapSet
         /\ cos = "loading" => rpc \in BuildPh \cup {"b_conf", "c_conf"}
         /\ rpc = "c_conf" => cos = "loading"
         /\ rpc = "b_check" /\ cos = "loading" /\ curVer = rver => cstats = histv[rver]
         /\ rpc \in {"b_conf", "c_conf"} /\ cos = "loading" /\ curVer = snapVer => cstats = snapSet
\* vacuum
I_ov == 1 <= OV /\ OV <= G
I_vac == vpc \in {"slot", "store"} => OV <= vg /\ vg <= G
I_vst == vpc = "store" => OV <= vov /\ vov <= vg /\ (SlotSet(slot) => vov <= slot)
I_gone == \A r \in Rows : gone[r] => del[r] > 0 /\ del[r] < OV
I_ghost == ~badStale /\ ~badScan /\ ~badCount /\ ~badCut /\ ~snapChanged /\ ~badOV

IndInv == TypeOK /\ I_fix /\ I_wid /\ I_mutex /\ I_cur /\ I_gst /\ I_hist /\ I_ent /\ I_pos /\ I_cv
          /\ I_fly /\ I_busy /\ I_fill /\ I_pub /\ I_G /\ I_acked /\ I_iso /\ I_build /\ I_stmt /\ I_ops
          /\ I_slotA /\ I_slot /\ I_slotv /\ I_slotb /\ I_rg /\ I_rgb /\ I_rpos /\ I_rver /\ I_copy
          /\ I_copied /\ I_snap /\ I_sver /\ I_cos /\ I_ov /\ I_vac /\ I_vst /\ I_gone /\ I_ghost

\* Apalache: the writer count, rows, ring and program fixed, the vacuum budget open
CInit ==
  /\ NW = 2 /\ NInit = 1 /\ H = 2 /\ NStmt = 2 /\ NOps = 2 /\ Prog = ProgScanCount
  /\ Isolation \in {"RC", "RR"} /\ StatsFix = TRUE /\ TornFix = TRUE /\ Mutant = "none" /\ VacRounds \in Nat
=============================================================================
