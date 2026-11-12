--------------------------- MODULE ReadAheadTrace ---------------------------
(* Trace validation of ReadAhead: one serial index scan of an instrumented build (Fill: a new OID buffer with the
   heap page of each OID; Check: the window decision before a lookup, with the pages handed to the OS; Look: the
   lookup). The buffers' pages come from the run (Pg); the racy residency check takes the logged hinted set. *)
EXTENDS ReadAhead, ReadAheadTraceData, Sequences

CONSTANTS TraceLog, Pg
VARIABLE i
TVars == <<vars, i>>

TInit ==
  /\ size = [k \in 1..NB |-> Len(Pg[k])]
  /\ page = [k \in 1..NB |-> [j \in Pos |-> IF j < Len(Pg[k]) THEN Pg[k][j + 1] ELSE 1]]
  /\ b = 0
  /\ curr = -1
  /\ phase = "fill"
  /\ next = INF
  /\ resident = {}
  /\ served = [k \in 1..NB |-> {}]
  /\ hinted = {}
  /\ lookedIn = [k \in 1..NB |-> 0]
  /\ orderOk = TRUE
  /\ boundsOk = TRUE
  /\ dist = 0
  /\ toldEnd = [k \in 1..NB |-> 0]
  /\ i = 0

Ev == TraceLog[i + 1]

WinStart == Max(next, curr)
WinStop == Min(N, curr + NextDist)
WinPages == {page[b][j] : j \in {x \in Pos : WinStart <= x /\ x < WinStop}}

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ /\ Ev.a = "Fill"
        /\ Fill
        /\ size[b'] = Ev.n
        /\ next' = IF Ev.next = -1 THEN INF ELSE Ev.next
     \/ /\ Ev.a = "Check" /\ Ev.fired = 0
        /\ curr = Ev.curr
        /\ ~(curr + H >= next)
        /\ Check({})
     \/ /\ Ev.a = "Check" /\ Ev.fired = 1
        /\ curr = Ev.curr
        /\ curr + H >= next
        /\ WinStart = Ev.start
        /\ WinStop = Ev.stop
        /\ Ev.hinted \subseteq WinPages
        /\ ((Ev.skip = 1) <=> (Cardinality(WinPages) <= 1 /\ WinStart = curr))
        /\ Check(Ev.hinted)
     \/ /\ Ev.a = "Look"
        /\ curr = Ev.curr
        /\ page[b][curr] = Ev.pg
        /\ Look

\* not logged: the scan stopping before a buffer's end (the next event is the next buffer's Fill)
Hidden == StopEarly /\ UNCHANGED i

TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
