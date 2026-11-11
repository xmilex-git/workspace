-------------------------- MODULE KeyReadAheadTrace --------------------------
(* Trace validation of KeyReadAhead: one parallel index scan worker on one leaf of an instrumented build, from
   WLeaf to the clear of its queue (WClear) or the range's end (WStop). The keys' OID counts come from the run
   (every WEval, ahead or not, in key order); the window's decision (Check) is not logged and is deterministic. *)
EXTENDS KeyReadAhead, KeyReadAheadTraceData, Sequences

CONSTANTS TraceLog, TraceNOid, TraceBase
VARIABLE i
TVars == <<vars, i>>

TInit ==
  /\ nOid = [k \in Keys |-> TraceNOid[k]]
  /\ base = [k \in 1..(NK + 1) |-> TraceBase[k]]
  /\ errKey = 0
  /\ phase = "fresh"
  /\ ev = 0
  /\ ck = 1
  /\ co = 1
  /\ hf = 0
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

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "WEval" /\ Ev.ahead = 0 /\ phase = "fresh" /\ ev < ck /\ nOid[ck] = Ev.n /\ Fresh
     \/ Ev.a = "WPop" /\ phase = "fresh" /\ ev >= ck /\ nOid[ck] = Ev.n /\ Fresh
     \/ Ev.a = "WNoWin" /\ phase = "look" /\ UNCHANGED vars
     \/ Ev.a = "WEval" /\ Ev.ahead = 1 /\ nOid[ev + 1] = Ev.n /\ EvalAhead
     \/ Ev.a = "WEvalStop" /\ phase = "eval" /\ ev = NK /\ UNCHANGED vars
     \/ /\ Ev.a = "WWin"
        /\ WindowDone
        /\ Ev.pos = Min(EvalEnd, Pos(ck, co) + D) - Pos(ck, co)
     \/ Ev.a = "WLook" /\ Look
     \* logged only when scan_next_slot's own loop moves on; the slot iterator's move is not logged
     \/ Ev.a = "WNext" /\ phase = "fresh" /\ UNCHANGED vars
     \/ Ev.a = "WClear" /\ Stop
     \/ Ev.a = "WStop" /\ Ev.why = "end" /\ ck > NK /\ Fresh

\* not logged: the window decision before a lookup, and the move to the next key after the last OID of one
Hidden == (Check \/ NextKey) /\ UNCHANGED i

TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
