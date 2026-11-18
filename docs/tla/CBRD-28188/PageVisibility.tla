---------------------------- MODULE PageVisibility ----------------------------
(***************************************************************************)
(* CBRD-28188: heap_page_collect_visible () answers a REC_HOME record from  *)
(* its first word (representation + MVCC flags) before decoding its header. *)
(* On a page whose HEAP_CHAIN.max_mvccid precedes the snapshot's lowest     *)
(* active MVCCID an inserted record is a row and a deleted one is skipped;  *)
(* elsewhere a record with no MVCC id and the expected representation is a  *)
(* row.  Every other record takes the header decode and snapshot_fnc (),    *)
(* the walk develop runs for every record.                                  *)
(*                                                                         *)
(* State-shaped: a writer's record change and its chain update happen under *)
(* one page write latch (one step); one call of heap_page_collect_visible () *)
(* reads the chain and the records under one read latch (one step).          *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets, TLC

CONSTANTS Tx, R, NoTx, DataPages, HdrPage, NS, Reps, Repids, MaxCrash, MaxId, Mutant

\* apalache-type: Tx Set(Str)
\* apalache-type: R Str
\* apalache-type: NoTx Str
\* apalache-type: DataPages Set(Str)
\* apalache-type: HdrPage Str
\* apalache-type: NS Int
\* apalache-type: Reps Set(Int)
\* apalache-type: Repids Set(Int)
\* apalache-type: MaxCrash Int
\* apalache-type: MaxId Int
\* apalache-type: Mutant Str

VARIABLES rec, owner, before, maxm, st, tid, nextId, done, cmt, snap, crashes

\* apalache-type: rec Str -> (Int -> {in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int})
\* apalache-type: owner Str -> (Int -> Str)
\* apalache-type: before Str -> (Int -> {in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int})
\* apalache-type: maxm Str -> Int
\* apalache-type: st Str -> Str
\* apalache-type: tid Str -> Int
\* apalache-type: nextId Int
\* apalache-type: done Set(Int)
\* apalache-type: cmt Set(Int)
\* apalache-type: snap {has: Bool, low: Int, done: Set(Int)}
\* apalache-type: crashes Int

vars == <<rec, owner, before, maxm, st, tid, nextId, done, cmt, snap, crashes>>

Pages == DataPages \cup {HdrPage}
Slots == 1..NS
Ids == 1..MaxId
Empty == [in |-> FALSE, rel |-> FALSE, ins |-> 0, del |-> 0, prev |-> FALSE, rep |-> 1]
Base  == [in |-> TRUE, rel |-> FALSE, ins |-> 0, del |-> 0, prev |-> FALSE, rep |-> 1]
RecSet == [in : BOOLEAN, rel : BOOLEAN, ins : 0..MaxId, del : 0..MaxId, prev : BOOLEAN, rep : Reps]
NoSnap == [has |-> FALSE, low |-> 0, done |-> {}]

(* mvcc_table: the first MVCCID not completed (m_current_status_lowest_active_mvccid) *)
LowNow == CHOOSE i \in 1..(MaxId + 1) :
            /\ i <= nextId /\ (i = nextId \/ i \notin done)
            /\ \A j \in 1..(MaxId + 1) : j < i => j \in done

(* the vacuum threshold: no version a live snapshot can still see is removed *)
OldestVis == IF snap.has /\ st[R] = "active" /\ snap.low < LowNow THEN snap.low ELSE LowNow

(*************************** develop's decision ****************************)
(* mvcc_is_id_in_snapshot (): below lowest_active is completed, else the   *)
(* snapshot's view of the id                                               *)
\* @type: ({has: Bool, low: Int, done: Set(Int)}, Int) => Bool;
InSnapIn(sn, id) == ~(id < sn.low) /\ id \notin sn.done
InSnap(id) == InSnapIn(snap, id)
(* MVCC_IS_REC_INSERTED_BY_ME / DELETED_BY_ME: the scanner's own id        *)
ByMeOf(own, id) == id > 0 /\ own = id
ByMe(id) == ByMeOf(tid[R], id)

(* mvcc_satisfies_snapshot (); an all-visible header never calls it       *)
\* @type: ({has: Bool, low: Int, done: Set(Int)}, Int, {in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}) => Str;
DevResIn(sn, own, r) ==
  IF r.del = 0
  THEN IF r.ins = 0 THEN "sat"
       ELSE IF ByMeOf(own, r.ins) THEN "sat"
       ELSE IF InSnapIn(sn, r.ins) THEN "new"
       ELSE "sat"
  ELSE IF ByMeOf(own, r.del) THEN "old"
       ELSE IF r.ins > 0 /\ InSnapIn(sn, r.ins) THEN "new"
       ELSE IF InSnapIn(sn, r.del) THEN "sat"
       ELSE "old"

(* heap_page_collect_visible ()'s header walk: REC_RELOCATION ends the     *)
(* chunk; TOO_OLD skipped; TOO_NEW skipped without a previous version, an  *)
(* exception with one; SATISFIED a row of a decoded representation, or an  *)
(* exception                                                                *)
\* @type: ({has: Bool, low: Int, done: Set(Int)}, Int, {in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}) => Str;
DevDecideIn(sn, own, r) ==
  IF ~r.in THEN "empty"
  ELSE IF r.rel THEN "exc"
  ELSE LET res == DevResIn(sn, own, r) IN
       IF res = "old" THEN "skip"
       ELSE IF res = "new" THEN (IF r.prev THEN "exc" ELSE "skip")
       ELSE IF r.rep \in Repids THEN "row" ELSE "exc"
\* @type: ({in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}) => Str;
DevDecide(r) == DevDecideIn(snap, tid[R], r)

(***************************** the change (D) ******************************)
(* page_precedes_snapshot: snapshot_fnc == mvcc_satisfies_snapshot, a     *)
(* HEAP_CHAIN in slot 0 (not the header page), max_mvccid precedes        *)
(* lowest_active_mvccid                                                    *)
Precedes(a, b) == IF Mutant = "judge_le" THEN a <= b ELSE a < b
\* @type: (Str, Int, {has: Bool, low: Int, done: Set(Int)}) => Bool;
PassedIn(p, m, sn) == \/ p \in DataPages /\ Precedes(m, sn.low)
                      \/ Mutant = "judge_header" /\ p = HdrPage
Passed(p) == PassedIn(p, maxm[p], snap)

(* (word & word_mask) == word_want; word_want is repids[0] or the          *)
(* representation of a row the header walk accepted: one of Repids         *)
\* @type: ({in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}, Int) => Bool;
RepOk(r, w) == Mutant = "no_repid" \/ r.rep = w
\* @type: (Bool, {in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}, Int) => Bool;
WordRowIn(ps, r, w) ==
  IF ps THEN r.del = 0 /\ RepOk(r, w)
  ELSE IF Mutant = "no_insid_bit" THEN r.del = 0 /\ RepOk(r, w)
  ELSE r.ins = 0 /\ r.del = 0 /\ RepOk(r, w)
(* page_precedes_snapshot && (word & delid_bit) != 0 *)
\* @type: (Bool, {in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}) => Bool;
WordDelIn(ps, r) == (ps \/ Mutant = "skip_del_any_page") /\ r.del # 0
\* @type: (Str, {in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}, Int) => Bool;
WordRow(p, r, w) == LET ps == Passed(p) IN WordRowIn(ps, r, w)
\* @type: (Str, {in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}) => Bool;
WordDel(p, r) == LET ps == Passed(p) IN WordDelIn(ps, r)

\* @type: (Bool, {has: Bool, low: Int, done: Set(Int)}, Int, {in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}, Int) => Str;
FastDecideIn(ps, sn, own, r, w) ==
  IF ~r.in THEN "empty"
  ELSE IF r.rel THEN "exc"
  ELSE IF Mutant = "always_decode" THEN DevDecideIn(sn, own, r)
  ELSE IF WordRowIn(ps, r, w) THEN "row"
  ELSE IF WordDelIn(ps, r) THEN "skip"
  ELSE DevDecideIn(sn, own, r)
\* @type: (Str, {in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}, Int) => Str;
FastDecide(p, r, w) == LET ps == Passed(p) IN FastDecideIn(ps, snap, tid[R], r, w)

(* C2: a record the word can answer for is not decoded *)
\* @type: (Str, {in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}, Int) => Bool;
Decoded(p, r, w) == r.in /\ ~r.rel /\ (Mutant = "always_decode" \/ ~(WordRow(p, r, w) \/ WordDel(p, r)))
\* @type: (Str, {in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}, Int) => Bool;
Answerable(p, r, w) ==
  r.in /\ ~r.rel /\ IF Passed(p) THEN (r.del # 0 \/ r.rep = w) ELSE (r.ins = 0 /\ r.del = 0 /\ r.rep = w)

Scanning == st[R] = "active" /\ snap.has

(******************************** writers **********************************)
IdOf(t) == IF tid[t] = 0 THEN nextId ELSE tid[t]
CanWrite(t, p, s) == st[t] = "active" /\ owner[p][s] \in {NoTx, t} /\ IdOf(t) <= MaxId
TakeId(t) == /\ tid' = [tid EXCEPT ![t] = IdOf(t)]
             /\ nextId' = IF tid[t] = 0 THEN nextId + 1 ELSE nextId
Own(t, p, s) == /\ owner' = [owner EXCEPT ![p][s] = t]
                /\ before' = IF owner[p][s] = NoTx THEN [before EXCEPT ![p][s] = rec[p][s]] ELSE before
(* heap_page_update_chain_after_mvcc_op (): the header page has no chain  *)
Raise(p, id) == maxm' = IF p \in DataPages /\ maxm[p] < id THEN [maxm EXCEPT ![p] = id] ELSE maxm

(* heap_insert_logical () -> heap_mvcc_log_insert (); also a REC_ASSIGN_ADDRESS *)
(* filled in place (catcls_insert_instance (), ER_HEAP_NODATA_NEWADDRESS):    *)
(* heap_update_home () logs it RVHF_UPDATE_NOTIFY_VACUUM, an MVCC op          *)
Insert(t, p, s) ==
  /\ CanWrite(t, p, s) /\ ~rec[p][s].in
  /\ \E r \in Reps :
       rec' = [rec EXCEPT ![p][s] = [in |-> TRUE, rel |-> FALSE, ins |-> IdOf(t), del |-> 0, prev |-> FALSE, rep |-> r]]
  /\ TakeId(t) /\ Own(t, p, s) /\ Raise(p, IdOf(t))
  /\ UNCHANGED <<st, done, cmt, snap, crashes>>

(* heap_delete_home () -> heap_mvcc_log_delete (); heap_delete_relocation () *)
(* raises the home page by heap_mvcc_log_home_no_change ()                  *)
Delete(t, p, s) ==
  /\ CanWrite(t, p, s) /\ rec[p][s].in /\ rec[p][s].del = 0
  /\ rec' = [rec EXCEPT ![p][s].del = IdOf(t)]
  /\ TakeId(t) /\ Own(t, p, s)
  /\ IF Mutant = "reloc_no_home_raise" /\ rec[p][s].rel THEN UNCHANGED maxm ELSE Raise(p, IdOf(t))
  /\ UNCHANGED <<st, done, cmt, snap, crashes>>

(* heap_update_home (), heap_update_relocation (), heap_update_bigone () with *)
(* an MVCC op: the new version may move to a forward page or come back home; *)
(* the home page is raised (heap_log_update_physical (NOTIFY_VACUUM),       *)
(* heap_mvcc_log_home_no_change ())                                          *)
Update(t, p, s) ==
  /\ CanWrite(t, p, s) /\ rec[p][s].in /\ rec[p][s].del = 0
  /\ \E r \in Reps, rl \in BOOLEAN :
       rec' = [rec EXCEPT ![p][s] = [in |-> TRUE, rel |-> rl, ins |-> IdOf(t), del |-> 0, prev |-> TRUE, rep |-> r]]
  /\ TakeId(t) /\ Own(t, p, s)
  /\ IF Mutant = "no_raise_update" \/ (Mutant = "reloc_no_home_raise" /\ (rec[p][s].rel \/ rec'[p][s].rel))
     THEN UNCHANGED maxm ELSE Raise(p, IdOf(t))
  /\ UNCHANGED <<st, done, cmt, snap, crashes>>

(* UPDATE_INPLACE_OLD_MVCCID (heap_object_upgrade_domain (), under SCH_M): *)
(* the record keeps its ids and may move between home and a forward page;  *)
(* RVHF_UPDATE, no chain update                                            *)
InplaceOld(t, p, s) ==
  /\ CanWrite(t, p, s) /\ rec[p][s].in /\ rec[p][s].del = 0
  /\ \E r \in Reps, rl \in BOOLEAN :
       rec' = [rec EXCEPT ![p][s].rel = rl, ![p][s].rep = r]
  /\ Own(t, p, s)
  /\ UNCHANGED <<maxm, st, tid, nextId, done, cmt, snap, crashes>>

(* mutant only: an in-place update with the current MVCCID on a REC_HOME   *)
(* record, RVHF_UPDATE (no chain update); develop has no such writer on an  *)
(* MVCC class (MAP.md: census of UPDATE_INPLACE_CURRENT_MVCCID)            *)
InplaceCurHome(t, p, s) ==
  /\ Mutant = "inplace_current_home"
  /\ CanWrite(t, p, s) /\ rec[p][s].in /\ ~rec[p][s].rel /\ rec[p][s].del = 0
  /\ rec' = [rec EXCEPT ![p][s].ins = IdOf(t), ![p][s].prev = FALSE]
  /\ TakeId(t) /\ Own(t, p, s)
  /\ UNCHANGED <<maxm, st, done, cmt, snap, crashes>>

(* logtb_complete_mvcc (): the id is completed; the locks go *)
Commit(t) ==
  /\ st[t] = "active"
  /\ st' = [st EXCEPT ![t] = "committed"]
  /\ done' = IF tid[t] > 0 THEN done \cup {tid[t]} ELSE done
  /\ cmt' = IF tid[t] > 0 THEN cmt \cup {tid[t]} ELSE cmt
  /\ owner' = [p \in Pages |-> [s \in Slots |-> IF owner[p][s] = t THEN NoTx ELSE owner[p][s]]]
  /\ before' = [p \in Pages |-> [s \in Slots |-> IF owner[p][s] = t THEN Empty ELSE before[p][s]]]
  /\ UNCHANGED <<rec, maxm, tid, nextId, snap, crashes>>

(* a rollback undoes record by record (heap_rv_undo_*, heap_rv_mvcc_undo_delete) *)
(* while its id is active, then completes the id; the chain is not lowered     *)
AbortStart(t) ==
  /\ st[t] = "active" /\ st' = [st EXCEPT ![t] = "aborting"]
  /\ UNCHANGED <<rec, owner, before, maxm, tid, nextId, done, cmt, snap, crashes>>
Undo(t, p, s) ==
  /\ st[t] = "aborting" /\ owner[p][s] = t
  /\ rec' = [rec EXCEPT ![p][s] = before[p][s]]
  /\ owner' = [owner EXCEPT ![p][s] = NoTx]
  /\ before' = [before EXCEPT ![p][s] = Empty]
  /\ UNCHANGED <<maxm, st, tid, nextId, done, cmt, snap, crashes>>
AbortDone(t) ==
  /\ st[t] = "aborting" /\ \A p \in Pages, s \in Slots : owner[p][s] # t
  /\ st' = [st EXCEPT ![t] = "aborted"]
  /\ done' = IF tid[t] > 0 THEN done \cup {tid[t]} ELSE done
  /\ UNCHANGED <<rec, owner, before, maxm, tid, nextId, cmt, snap, crashes>>

(* vacuum_heap_record (): a committed delete below the threshold removes the *)
(* record, a committed insert below it loses INSID and the previous version; *)
(* max_mvccid is not touched                                                 *)
Vacuum(p, s) ==
  /\ rec[p][s].in /\ owner[p][s] = NoTx
  /\ \/ /\ rec[p][s].del > 0 /\ rec[p][s].del \in cmt /\ rec[p][s].del < OldestVis
        /\ rec' = [rec EXCEPT ![p][s] = Empty]
     \/ /\ rec[p][s].del = 0 /\ rec[p][s].ins > 0 /\ rec[p][s].ins \in cmt /\ rec[p][s].ins < OldestVis
        /\ rec' = [rec EXCEPT ![p][s].ins = 0, ![p][s].prev = FALSE]
  /\ UNCHANGED <<owner, before, maxm, st, tid, nextId, done, cmt, snap, crashes>>

(***************************** the scanner *********************************)
(* logtb_get_mvcc_snapshot (): a statement's snapshot under READ COMMITTED, *)
(* or one rebuilt by a nested statement (P55)                               *)
TakeSnap ==
  /\ st[R] = "active"
  /\ snap' = [has |-> TRUE, low |-> LowNow, done |-> done]
  /\ UNCHANGED <<rec, owner, before, maxm, st, tid, nextId, done, cmt, crashes>>
DropSnap ==
  /\ snap.has /\ snap' = NoSnap
  /\ UNCHANGED <<rec, owner, before, maxm, st, tid, nextId, done, cmt, crashes>>

(* one call of heap_page_collect_visible () on page p under its read latch: *)
(* it reads and changes nothing the model holds, so it is a stuttering step *)
(* here; its answers are FastDecide () over the page in the state it reads *)
(* (EquivNow, NoDecodeWhenAnswered), and the trace spec checks a logged    *)
(* call's answers against them                                             *)
ScanCall(p) ==
  /\ Scanning
  /\ UNCHANGED vars

(* a crash: recovery rolls the losers back and every id is completed; redo *)
(* of an MVCC op re-raises the chain (heap_page_rv_chain_update ()), so a   *)
(* page's max_mvccid is what it was.  The scanner starts a new transaction. *)
Crash ==
  /\ crashes < MaxCrash
  /\ rec' = [p \in Pages |-> [s \in Slots |-> IF owner[p][s] # NoTx THEN before[p][s] ELSE rec[p][s]]]
  /\ owner' = [p \in Pages |-> [s \in Slots |-> NoTx]]
  /\ before' = [p \in Pages |-> [s \in Slots |-> Empty]]
  /\ st' = [t \in Tx |-> IF t = R THEN "active" ELSE IF st[t] \in {"active", "aborting"} THEN "aborted" ELSE st[t]]
  /\ done' = done \cup {tid[t] : t \in {u \in Tx : tid[u] > 0}}
  /\ tid' = [tid EXCEPT ![R] = 0]
  /\ snap' = NoSnap
  /\ crashes' = crashes + 1
  /\ UNCHANGED <<maxm, nextId, cmt>>

(* every transaction has ended: the system stops (not a deadlock) *)
Finished ==
  /\ \A t \in Tx : st[t] \in {"committed", "aborted"}
  /\ UNCHANGED vars

Init ==
  /\ rec \in [Pages -> [Slots -> {Empty, Base}]]
  /\ owner = [p \in Pages |-> [s \in Slots |-> NoTx]]
  /\ before = [p \in Pages |-> [s \in Slots |-> Empty]]
  /\ maxm = [p \in Pages |-> 0]
  /\ st = [t \in Tx |-> "active"]
  /\ tid = [t \in Tx |-> 0]
  /\ nextId = 1
  /\ done = {}
  /\ cmt = {}
  /\ snap = NoSnap
  /\ crashes = 0

Next ==
  \/ \E t \in Tx, p \in Pages, s \in Slots :
       Insert(t, p, s) \/ Delete(t, p, s) \/ Update(t, p, s) \/ InplaceOld(t, p, s) \/ InplaceCurHome(t, p, s)
       \/ Undo(t, p, s)
  \/ \E t \in Tx : Commit(t) \/ AbortStart(t) \/ AbortDone(t)
  \/ \E p \in Pages, s \in Slots : Vacuum(p, s)
  \/ TakeSnap \/ DropSnap
  \/ \E p \in Pages : ScanCall(p)
  \/ Crash
  \/ Finished

Spec == Init /\ [][Next]_vars

(******************************* properties ********************************)
TypeOK ==
  /\ rec \in [Pages -> [Slots -> RecSet]]
  /\ owner \in [Pages -> [Slots -> Tx \cup {NoTx}]]
  /\ before \in [Pages -> [Slots -> RecSet]]
  /\ maxm \in [Pages -> 0..MaxId]
  /\ st \in [Tx -> {"active", "aborting", "committed", "aborted"}]
  /\ tid \in [Tx -> 0..MaxId] /\ nextId \in 1..(MaxId + 1) /\ done \subseteq Ids /\ cmt \subseteq done
  /\ crashes \in 0..MaxCrash

(* C1: every record of every page the scanner can read is answered as     *)
(* develop's walk answers it, for every word_want                          *)
EquivNow ==
  Scanning => \A p \in Pages, s \in Slots, w \in Repids : FastDecide(p, rec[p][s], w) = DevDecide(rec[p][s])
(* C2: a record the first word can answer for is not decoded *)
NoDecodeWhenAnswered ==
  Scanning => \A p \in Pages, s \in Slots, w \in Repids : Answerable(p, rec[p][s], w) => ~Decoded(p, rec[p][s], w)

(* witnesses: outcomes that must be reachable *)
FastIdRow(p) == \E s \in Slots, w \in Repids :
                  rec[p][s].in /\ ~rec[p][s].rel /\ rec[p][s].ins > 0 /\ WordRow(p, rec[p][s], w)
NotFastIdRow == ~(Scanning /\ \E p \in DataPages : Passed(p) /\ FastIdRow(p))
NotFastDel == ~(Scanning /\ \E p \in Pages, s \in Slots : rec[p][s].in /\ ~rec[p][s].rel /\ WordDel(p, rec[p][s]))
NotFailedOwnPage == ~(Scanning /\ \E p \in DataPages, s \in Slots : ~Passed(p) /\ rec[p][s].in /\ ByMe(rec[p][s].ins))
NotPassedAfterCrash == ~(Scanning /\ crashes > 0 /\ \E p \in DataPages : Passed(p) /\ FastIdRow(p))
NotMovedHomeFast == ~(Scanning /\ \E p \in DataPages, s \in Slots :
                        Passed(p) /\ rec[p][s].in /\ ~rec[p][s].rel /\ rec[p][s].ins > 0 /\ before[p][s].rel)

(****************************** inductive invariant ******************************)
Live == {"active", "aborting"}
\* @type: ({in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}) => Set(Int);
IdsOf(r) == {r.ins, r.del} \ {0}
\* @type: ({in: Bool, rel: Bool, ins: Int, del: Int, prev: Bool, rep: Int}) => Bool;
WellFormedRec(r) ==
  /\ r.ins \in 0..MaxId /\ r.del \in 0..MaxId /\ r.rep \in Reps
  /\ r.in \in BOOLEAN /\ r.rel \in BOOLEAN /\ r.prev \in BOOLEAN
  /\ ~r.in => (r.ins = 0 /\ r.del = 0 /\ ~r.rel /\ ~r.prev /\ r.rep = 1)

(* every field in range (Apalache draws the variables freely) *)
TypeInd ==
  /\ DOMAIN rec = Pages /\ DOMAIN owner = Pages /\ DOMAIN before = Pages /\ DOMAIN maxm = Pages
  /\ \A p \in Pages : DOMAIN rec[p] = Slots /\ DOMAIN owner[p] = Slots /\ DOMAIN before[p] = Slots
  /\ \A p \in Pages, s \in Slots :
       WellFormedRec(rec[p][s]) /\ WellFormedRec(before[p][s]) /\ owner[p][s] \in Tx \cup {NoTx}
  /\ \A p \in Pages : maxm[p] \in 0..MaxId
  /\ DOMAIN st = Tx /\ DOMAIN tid = Tx
  /\ \A t \in Tx : st[t] \in {"active", "aborting", "committed", "aborted"} /\ tid[t] \in 0..MaxId
  /\ nextId \in 1..(MaxId + 1) /\ done \subseteq Ids /\ cmt \subseteq done
  /\ snap.has \in BOOLEAN /\ snap.low \in 0..(MaxId + 1) /\ snap.done \subseteq Ids
  /\ crashes \in 0..MaxCrash
  /\ MaxId = Cardinality(Tx) + MaxCrash

(* ids are handed out once, in order *)
IdsAllocated ==
  /\ \A i \in done : i < nextId
  /\ \A t \in Tx : tid[t] < nextId
  /\ \A t, u \in Tx : t # u /\ tid[t] > 0 => tid[t] # tid[u]
  /\ \A p \in Pages, s \in Slots : \A i \in IdsOf(rec[p][s]) \cup IdsOf(before[p][s]) : i < nextId

(* a live transaction's id is not completed; an ended one's is, committed or not *)
StatusIds ==
  /\ \A t \in Tx : st[t] \in Live /\ tid[t] > 0 => tid[t] \notin done
  /\ \A t \in Tx : st[t] = "committed" /\ tid[t] > 0 => tid[t] \in cmt
  /\ \A t \in Tx : st[t] = "aborted" /\ tid[t] > 0 => tid[t] \in done \ cmt
  /\ \A i \in Ids : i < nextId /\ i \notin done => \E t \in Tx : tid[t] = i /\ st[t] \in Live

(* the X lock: only a live transaction holds a record, and only a held record has an undo image *)
OwnerOk ==
  \A p \in Pages, s \in Slots :
    /\ owner[p][s] # NoTx => st[owner[p][s]] \in Live
    /\ owner[p][s] = NoTx => before[p][s] = Empty

(* an id on a record is committed, or the id of the transaction holding the record;  *)
(* the undo image holds committed ids only                                           *)
RecIds ==
  \A p \in Pages, s \in Slots :
    /\ \A i \in IdsOf(rec[p][s]) : i \in cmt \/ (owner[p][s] # NoTx /\ i = tid[owner[p][s]])
    /\ \A i \in IdsOf(before[p][s]) : i \in cmt

(* the claim's premise: max_mvccid bounds every id the page holds or may restore *)
IdBound ==
  \A p \in DataPages, s \in Slots :
    \A i \in IdsOf(rec[p][s]) \cup IdsOf(before[p][s]) : i <= maxm[p]

(* a snapshot sees every id below its lowest_active as completed *)
SnapOk ==
  snap.has =>
    /\ snap.low >= 1 /\ snap.low <= nextId
    /\ snap.done \subseteq done
    /\ \A i \in Ids : i < snap.low => i \in snap.done

IndInv ==
  /\ TypeInd
  /\ IdsAllocated
  /\ StatusIds
  /\ OwnerOk
  /\ RecIds
  /\ IdBound
  /\ SnapOk
  /\ EquivNow
  /\ NoDecodeWhenAnswered

(* t1 and t2 play the same role *)
WriterSym == Permutations(Tx \ {R})
=============================================================================
