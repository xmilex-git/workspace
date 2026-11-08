------------------------- MODULE DomainDecidedTrace -------------------------
(* Trace validation: is a run of the instrumented build (SA mode: XASL generation, unpack and execution in one
   process, one global seq) a behavior of DomainDecided? Each logged event is the action it names with the
   logged outcome: a Compile event's annotation is the one the spec's compiler gives its (site, class); a Load
   event unpacks a slot some earlier Compile produced with that annotation (a cached plan may load many times);
   a Decide event's decision is the spec's for its side and input class. Slots of site "row" and the executor
   are not logged (Hidden: Exec). Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS DomainDecided, DomainDecidedTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ /\ Ev.a = "Compile"
        /\ Compile(Ev.site, Ev.cls)
        /\ Ann(Ev.site, Ev.cls) = Ev.ann
     \/ /\ Ev.a = "Load"
        /\ \E e \in compiled : e.site = Ev.site /\ e.ann = Ev.ann /\ Load(e)
     \/ /\ Ev.a = "Decide"
        /\ Decide(Ev.p, Ev.conv = 1)
        /\ Decline(Ev.p, Ev.conv = 1) = (Ev.decl = 1)
Hidden == (\E e \in loaded : Exec(e)) /\ UNCHANGED i
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
