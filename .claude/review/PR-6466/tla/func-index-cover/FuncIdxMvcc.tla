----------------------------- MODULE FuncIdxMvcc -----------------------------
(* PR #6466 (CBRD-25984) at f1f4f21ea: a function index scan that reads F from the key (covered projection, or
   the key filter of a non-covered scan) while another transaction updates the row and vacuum cleans up.
   One row. Update k (1..NU) creates version k+1: it inserts the index entry of version k+1 and marks the
   entry of the current head version deleted by k (btree_insert, btree_mvcc_delete), then commits or rolls
   back. Each version has its own F value; Fv[v] is whether that value passes the query predicate. Entry v
   holds F of version v in its key. The reader takes a snapshot (the head version vs at that moment), walks
   the entries in key order (one entry per step, under its leaf latch), applies the key filter to the key,
   checks the entry's MVCC ids against the snapshot (btree_select_visible_object_for_range_scan), and returns
   either the key (covered) or the snapshot version read from the heap (non-covered). *)
EXTENDS Naturals

CONSTANTS NU, Mutant
\* apalache-type: NU Int
\* apalache-type: Mutant Str

Upd == 1..NU
Ver == 1..(NU + 1)
Mutants == {"none", "no_snapshot", "heap_latest", "vac_early"}
ASSUME NU \in Nat /\ NU >= 1 /\ Mutant \in Mutants

VARIABLES fv, covered, kfOn,
  status, next, cur, head, ent, delBy, gone,
  rphase, vs, pos, ret, dup, lost
\* apalache-type: fv Int -> Bool
\* apalache-type: covered Bool
\* apalache-type: kfOn Bool
\* apalache-type: status Int -> Str
\* apalache-type: next Int
\* apalache-type: cur Int
\* apalache-type: head Int
\* apalache-type: ent Int -> Bool
\* apalache-type: delBy Int -> Int
\* apalache-type: gone Int -> Bool
\* apalache-type: rphase Str
\* apalache-type: vs Int
\* apalache-type: pos Int
\* apalache-type: ret Int -> Bool
\* apalache-type: dup Bool
\* apalache-type: lost Bool

vars == <<fv, covered, kfOn, status, next, cur, head, ent, delBy, gone, rphase, vs, pos, ret, dup, lost>>

M(x) == Mutant = x

\* the snapshot sees an update when it committed before the reader started; updates run one at a time, so
\* those are exactly the committed updates below the head version the reader saw
InSnap(k) == k \in Upd /\ k < vs /\ status[k] = "committed"
Visible(e) ==
  IF M("no_snapshot") THEN ent[e]
  ELSE ent[e] /\ (e = 1 \/ InSnap(e - 1)) /\ ~(delBy[e] # 0 /\ InSnap(delBy[e]))
\* the heap version the scan reads for the row's OID
HeapVer == IF M("heap_latest") THEN head ELSE vs

Init ==
  /\ fv \in [Ver -> BOOLEAN] /\ covered \in BOOLEAN /\ kfOn \in BOOLEAN
  /\ status = [k \in Upd |-> "none"] /\ next = 1 /\ cur = 0 /\ head = 1
  /\ ent = [e \in Ver |-> e = 1] /\ delBy = [e \in Ver |-> 0] /\ gone = [e \in Ver |-> FALSE]
  /\ rphase = "idle" /\ vs = 1 /\ pos = 1 /\ ret = [e \in Ver |-> FALSE] /\ dup = FALSE /\ lost = FALSE

(* ---- updater: heap_update + btree_update (insert new key, MVCC-delete old key), commit, rollback ---- *)
Begin ==
  /\ cur = 0 /\ next \in Upd
  /\ status' = [status EXCEPT ![next] = "active"]
  /\ ent' = [ent EXCEPT ![next + 1] = TRUE]
  /\ delBy' = [delBy EXCEPT ![head] = next]
  /\ cur' = next /\ next' = next + 1
  /\ UNCHANGED <<fv, covered, kfOn, head, gone, rphase, vs, pos, ret, dup, lost>>
Commit ==
  /\ cur # 0
  /\ status' = [status EXCEPT ![cur] = "committed"]
  /\ head' = cur + 1 /\ cur' = 0
  /\ UNCHANGED <<fv, covered, kfOn, next, ent, delBy, gone, rphase, vs, pos, ret, dup, lost>>
Abort ==
  /\ cur # 0
  /\ status' = [status EXCEPT ![cur] = "aborted"]
  /\ ent' = [ent EXCEPT ![cur + 1] = FALSE]
  /\ delBy' = [delBy EXCEPT ![head] = 0]
  /\ cur' = 0
  /\ UNCHANGED <<fv, covered, kfOn, next, head, gone, rphase, vs, pos, ret, dup, lost>>

(* ---- vacuum: an entry and its heap version go once their delete committed before every active snapshot ---- *)
Vacuum(e) ==
  /\ ent[e] /\ delBy[e] # 0 /\ status[delBy[e]] = "committed"
  /\ (rphase # "scan" \/ InSnap(delBy[e]) \/ M("vac_early"))
  /\ ent' = [ent EXCEPT ![e] = FALSE] /\ gone' = [gone EXCEPT ![e] = TRUE]
  /\ UNCHANGED <<fv, covered, kfOn, status, next, cur, head, delBy, rphase, vs, pos, ret, dup, lost>>

(* ---- reader ---- *)
Start ==
  /\ rphase = "idle" /\ rphase' = "scan" /\ vs' = head /\ pos' = 1
  /\ UNCHANGED <<fv, covered, kfOn, status, next, cur, head, ent, delBy, gone, ret, dup, lost>>

\* one entry under its leaf latch: key filter on the key (F of entry pos), snapshot check, output
KfPass(e) == ~kfOn \/ fv[e]
Out(e) == IF covered THEN e ELSE HeapVer
\* the data filter of a non-covered scan, or of a covered scan without key filter, reads the output value
DataPass(e) == kfOn \/ fv[Out(e)]
Scan ==
  /\ rphase = "scan" /\ pos \in Ver
  /\ IF Visible(pos) /\ KfPass(pos) /\ DataPass(pos)
       THEN /\ ret' = [ret EXCEPT ![Out(pos)] = TRUE]
            /\ dup' = (dup \/ ret[Out(pos)])
            /\ lost' = (lost \/ gone[Out(pos)])
       ELSE UNCHANGED <<ret, dup, lost>>
  /\ pos' = pos + 1
  /\ UNCHANGED <<fv, covered, kfOn, status, next, cur, head, ent, delBy, gone, rphase, vs>>
Finish ==
  /\ rphase = "scan" /\ pos = NU + 2 /\ rphase' = "done"
  /\ UNCHANGED <<fv, covered, kfOn, status, next, cur, head, ent, delBy, gone, vs, pos, ret, dup, lost>>

Next == Begin \/ Commit \/ Abort \/ (\E e \in Ver : Vacuum(e)) \/ Start \/ Scan \/ Finish
Spec == Init /\ [][Next]_vars

(* ---- properties ---- *)
\* the answer develop gives (heap scan, F from the snapshot version): the row once iff its snapshot version passes
ResultOK == rphase = "done" => ((\A e \in Ver : ret[e] = (e = vs /\ fv[vs])) /\ ~dup /\ ~lost)
\* nothing returned is wrong even before the scan ends
NoWrongRow == rphase # "idle" => ((\A e \in Ver : ret[e] => (e = vs /\ fv[vs])) /\ ~dup /\ ~lost)

TypeOK ==
  /\ fv \in [Ver -> BOOLEAN] /\ covered \in BOOLEAN /\ kfOn \in BOOLEAN
  /\ status \in [Upd -> {"none", "active", "committed", "aborted"}]
  /\ next \in 1..(NU + 1) /\ cur \in 0..NU /\ head \in Ver
  /\ ent \in [Ver -> BOOLEAN] /\ delBy \in [Ver -> 0..NU] /\ gone \in [Ver -> BOOLEAN]
  /\ rphase \in {"idle", "scan", "done"} /\ vs \in Ver /\ pos \in 1..(NU + 2)
  /\ ret \in [Ver -> BOOLEAN] /\ dup \in BOOLEAN /\ lost \in BOOLEAN

\* updates run one at a time, in order
U1 == \A k \in Upd : (k >= next) => status[k] = "none"
U2 == \A k \in Upd : (k < next) => status[k] # "none"
U3 == (cur # 0) => (cur = next - 1 /\ status[cur] = "active")
U4 == \A k \in Upd : (status[k] = "active") => k = cur
U5 == head <= next
U6 == (head # 1) => status[head - 1] = "committed"
U7 == \A k \in Upd : (status[k] = "committed") => k + 1 <= head
U8 == \A k \in Upd : (head <= k /\ k < next /\ k # cur) => status[k] = "aborted"
R_upd == U1 /\ U2 /\ U3 /\ U4 /\ U5 /\ U6 /\ U7 /\ U8
\* index entries: the head entry is alive and deleted only by the active update; an entry above the head is
\* the active update's; an entry below the head was deleted by a committed update with only rollbacks between
E1 == ent[head] /\ ~gone[head] /\ delBy[head] = cur
E2 == (cur # 0) => (ent[cur + 1] /\ ~gone[cur + 1])
E3 == \A e \in Ver : (e > head /\ ent[e]) => (cur # 0 /\ e = cur + 1)
E4 == \A e \in Ver : (e > head) => (delBy[e] = 0 /\ ~gone[e])
E5 == \A e \in Ver : (e < head /\ ent[e]) =>
        (/\ delBy[e] \in Upd /\ status[delBy[e]] = "committed" /\ e <= delBy[e]
         /\ \A k \in Upd : (e <= k /\ k < delBy[e]) => status[k] = "aborted")
E6 == \A e \in Ver : (e > 1 /\ e <= head /\ ent[e]) => status[e - 1] = "committed"
R_ent == E1 /\ E2 /\ E3 /\ E4 /\ E5 /\ E6
\* the reader: its snapshot version stays alive while it scans, and what it returned is right so far
D1 == (rphase = "idle") => (pos = 1 /\ (\A e \in Ver : ~ret[e]) /\ ~dup /\ ~lost)
D2 == (rphase # "idle") => vs <= head
D3 == (rphase # "idle") => ((vs # 1) => status[vs - 1] = "committed")
D4 == (rphase = "scan") => (ent[vs] /\ ~gone[vs] /\ (delBy[vs] = 0 \/ delBy[vs] >= vs))
D5 == (rphase # "idle") => (\A e \in Ver : ret[e] => (e = vs /\ fv[vs] /\ vs < pos))
D6 == (rphase # "idle") => (~dup /\ ~lost)
D7 == (rphase # "idle" /\ vs < pos /\ fv[vs]) => ret[vs]
D8 == (rphase = "done") => pos = NU + 2
R_read == D1 /\ D2 /\ D3 /\ D4 /\ D5 /\ D6 /\ D7 /\ D8

IndInv == TypeOK /\ R_upd /\ R_ent /\ R_read

(* ---- witnesses ---- *)
\* the reader returns the version an update committed after its snapshot had already deleted
NotOldVersionRead == ~(rphase = "done" /\ ret[vs] /\ delBy[vs] # 0 /\ status[delBy[vs]] = "committed")
\* the reader passes over the entry of a version its snapshot cannot see
NotNewEntrySkipped == ~(rphase = "done" /\ vs < NU + 1 /\ ent[vs + 1] /\ status[vs] = "committed")
\* the same, by the key filter of a non-covered scan (the path commit 0cb8b988a opens)
NotNonCoverKfOldVersion == ~(rphase = "done" /\ kfOn /\ ~covered /\ ret[vs] /\ delBy[vs] # 0 /\ status[delBy[vs]] = "committed")
NotVacuumed == ~(\E e \in Ver : gone[e])
NotAborted == ~(\E k \in Upd : status[k] = "aborted")

CInit == NU = 2 /\ Mutant = "none"
=============================================================================
