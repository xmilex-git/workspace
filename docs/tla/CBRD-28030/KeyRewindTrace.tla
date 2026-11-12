--------------------------- MODULE KeyRewindTrace ---------------------------
(* Trace validation of KeyRewind with Fix = "start": one index scan of an instrumented build (CBRD-28030-instr,
   the fix plus TLATRACE lines), across its sessions.  Logged: the scan start with the mark it found (Start,
   stale), the leaf record and each overflow page put into the OID buffer (LeafFill, PageFill, with their object
   counts), the hard-capacity stop (Interrupt), the resume in the overflow chain (KeyResume, the page), the end
   of a key (KeyDone), the soft-capacity stop (SoftStop), the end of the range (EndScan), the next
   btree_range_scan call of a started scan (Call), the rewinds (Rewind: BTREE_RESET_SCAN; Flip: bts_reset_scan
   of the index MIN/MAX scan), and the row the scan returned (Row, its buffer position).  The run's key
   structure (leaf objects, page sizes) replaces the model's uniform sizes; each session's range and matching
   object come from the run (traces/convert.py).  Not logged and deterministic: the consumer reading a
   non-matching OID, the move to the next key, the resume at the current key, a session ending without a row. *)
EXTENDS KeyRewind, KeyRewindTraceData, Sequences

CONSTANTS TraceLog, TraceRlo, TraceRhi, TraceM, TraceLeaf, TraceNPg, TracePg
VARIABLE i
TVars == <<vars, i>>

RECURSIVE SumSeq(_, _)
SumSeq(s, n) == IF n = 0 THEN 0 ELSE s[n] + SumSeq(s, n - 1)
TLeafOf(k) == TraceLeaf[k]
TPgCnt(k, p) == TracePg[k][p]
TNPg(k) == TraceNPg[k]
TKeyLen(k) == TraceLeaf[k] + SumSeq(TracePg[k], TraceNPg[k])
RECURSIVE TBase(_)
TBase(k) == IF k = 1 THEN 0 ELSE TBase(k - 1) + TKeyLen(k - 1)
TPageStart(k, p) == TBase(k) + TraceLeaf[k] + SumSeq(TracePg[k], p - 1)
TAnchorNext(k, a) ==
  (CHOOSE p \in 1..TraceNPg[k] : TPageStart(k, p) < a /\ a <= TPageStart(k, p) + TracePg[k][p]) + 1
TBufMax == CAP + SumSeq(TraceLeaf, NK)

TInit ==
  /\ rlo = TraceRlo
  /\ rhi = TraceRhi
  /\ M = TraceM
  /\ j = 1
  /\ bpc = "locate"
  /\ started = FALSE /\ ck = 1 /\ kcons = FALSE /\ flag = FALSE
  /\ anchor = 0 /\ lastvis = 0 /\ ovp = 0 /\ pg = 1
  /\ buf = 0 /\ cons = 0 /\ bufv = [x \in 1..BufMax |-> 0]
  /\ ex = RangeFirst(1)
  /\ bad = FALSE /\ lost = FALSE /\ nopos = FALSE
  /\ res = [s \in 1..NOut |-> "none"]
  /\ hitIn = [s \in 1..NOut |-> "none"]
  /\ resumed = FALSE
  /\ nread = 0
  /\ i = 0

Ev == TraceLog[i + 1]
Bit(b) == IF b THEN 1 ELSE 0

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "Start" /\ Start /\ Ev.stale = Bit(flag)
     \/ Ev.a = "LeafFill" /\ LeafFill /\ ck = Ev.key /\ LeafOf(ck) = Ev.n
     \/ Ev.a = "PageFill" /\ PageFill /\ ck = Ev.key /\ pg = Ev.pg /\ PgCnt(ck, pg) = Ev.n
     \/ Ev.a = "Interrupt" /\ Interrupt /\ ck = Ev.key /\ pg = Ev.pg /\ PgCnt(ck, pg) = Ev.n /\ buf = Ev.buf
     \/ Ev.a = "KeyResume" /\ KeyResume /\ ck = Ev.key /\ pg' = Ev.pg
     \/ Ev.a = "KeyDone" /\ KeyDone /\ ck = Ev.key
     \/ Ev.a = "SoftStop" /\ SoftStop /\ ck = Ev.key /\ buf = Ev.buf
     \/ Ev.a = "EndScan" /\ EndScan
     \/ Ev.a = "Call" /\ NextIter
     \/ Ev.a = "Rewind" /\ Rewind /\ Ev.flag = Bit(flag)
     \/ Ev.a = "Flip" /\ Flip /\ Ev.flag = Bit(flag)
     \/ Ev.a = "Row" /\ Consume /\ bpc' = "stopped" /\ cons' = Ev.pos

Hidden ==
  /\ i < Len(TraceLog)
  /\ UNCHANGED i
  /\ \/ ResumeKey
     \/ Advance
     \/ Consume /\ bpc' # "stopped"
     \/ EndNoMatch

TNext == Logged \/ Hidden
TSpec == TInit /\ [][TNext]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
