-------------------------- MODULE KeyReadAheadTrace --------------------------
(* Trace validation of KeyReadAhead: one parallel index scan worker on one leaf of an instrumented build, from
   WLeaf to the clear of its queue (WClear). Every next_key call is logged (WKey: ahead or not, its result, the
   keys it read), and so are the queue's pops (WPop), the resume after a stopped look-ahead (WResume, the keys it
   skipped), the windows (WWin), a read_ahead that returned at once after the stop (WEnded) or before the next
   window (WNoWin), and the lookups (WLook). The leaf's keys, the rejected ones and the erroring one come from the
   run; the window's decision (Check) and the move to the next key (NextKey) are not logged and deterministic. *)
EXTENDS KeyReadAhead, KeyReadAheadTraceData, Sequences

CONSTANTS TraceLog, TraceNOid, TraceBase, TraceRej, TraceErrKey, TraceCov
VARIABLE i
TVars == <<vars, i>>

TInit ==
  /\ nOid = [k \in Keys |-> TraceNOid[k]]
  /\ base = [k \in 1..(NK + 1) |-> TraceBase[k]]
  /\ rej = TraceRej
  /\ cov = TraceCov
  /\ errKey = TraceErrKey
  /\ phase = "fresh"
  /\ ev = 0
  /\ ck = 1
  /\ co = 1
  /\ hf = 0
  /\ aend = FALSE
  /\ errAhead = FALSE
  /\ windowed = FALSE
  /\ evals = [k \in Keys |-> 0]
  /\ rk = [k \in Keys |-> 0]
  /\ slotKey = 0
  /\ alloc = {}
  /\ freed = {}
  /\ counted = {}
  /\ consumedKeys = {}
  /\ raised = FALSE
  /\ ended = FALSE
  /\ orderOk = TRUE
  /\ pairOk = TRUE
  /\ leadOk = TRUE
  /\ errOk = TRUE
  /\ endOk = TRUE
  /\ lastPos = -1
  /\ i = 0

Ev == TraceLog[i + 1]

\* the keys a lookup next_key call read: the rejected ones, then the key it returned (a range end is a key read
\* past the leaf's last key)
LookupRead ==
  IF Ev.res = "LEAF" THEN NK - ev ELSE IF Ev.res = "END" THEN NK - ev + 1 ELSE ck' - ev

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ /\ Ev.a = "WKey" /\ Ev.ahead = 0 /\ Fresh
        /\ Ev.rk = LookupRead
        /\ IF Ev.res = "Q" THEN phase' = "check" /\ ck' > ev /\ nOid[ck'] = Ev.n
           ELSE IF Ev.res = "ERR" THEN phase' = "error"
           ELSE phase' = "done"
     \/ /\ Ev.a = "WPop" /\ Fresh
        /\ phase' = "check" /\ ck' <= ev /\ nOid[ck'] = Ev.n /\ Ev.rk = ck' - ck + 1
     \/ Ev.a = "WResume" /\ phase = "fresh" /\ aend /\ Ev.sk = ev - ck + 1 /\ UNCHANGED vars
     \/ /\ Ev.a = "WKey" /\ Ev.ahead = 1 /\ EvalAhead
        /\ Ev.rk = ev' - ev
        /\ IF Ev.res = "Q" THEN ~aend' /\ nOid[ev'] = Ev.n
           ELSE aend' /\ errAhead' = (Ev.res = "ERR")
     \/ /\ Ev.a = "WWin"
        /\ WindowDone
        /\ Ev.pos = Min(EvalEnd, Pos(ck, co) + D) - Pos(ck, co)
     \/ Ev.a = "WEnded" /\ phase = "look" /\ aend /\ UNCHANGED vars
     \/ Ev.a = "WNoWin" /\ phase = "look" /\ ~aend /\ ~cov /\ UNCHANGED vars
     \/ Ev.a = "WLook" /\ Look
     \* logged when scan_next_slot's own loop moves on after a key's OIDs were drained
     \/ Ev.a = "WNext" /\ phase = "fresh" /\ UNCHANGED vars
     \/ Ev.a = "WClear" /\ (Stop \/ (phase = "done" /\ UNCHANGED vars))

\* not logged: the window decision before a lookup, and the move to the next key after the last OID of one
Hidden == (Check \/ NextKey) /\ UNCHANGED i

TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
