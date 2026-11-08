---------------------------- MODULE FoldOomTrace ----------------------------
(* Trace validation: is a run of the instrumented build (TLATRACE lines of one thread: the tracer's bracket thread,
   or a worker serving a CS request) a behavior of FoldOom? Each logged event is the action it names with the
   logged outcome; the thread's successful allocations (lock-free entries, a new block under area_mutex, the
   abort path's allocations) are not logged and may happen in between. Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS FoldOom, FoldOomTraceData, Sequences

CONSTANTS TraceLog, T
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
HatIs(h) == hat[T] = h
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ Ev.a = "Fail" /\ HatIs(Ev.h) /\ MallocFail(T)
     \/ Ev.a = "Gate" /\ Callback(T) /\ ((ap'[T] = "abort") <=> Ev.go = 1)
     \/ Ev.a = "AbortFail" /\ AbortMallocFail(T)
     \/ Ev.a = "Guard" /\ AbortCallback(T)
     \/ Ev.a = "AbortEffect" /\ HatIs(Ev.h) /\ AbortEffect(T)
     \/ Ev.a = "Ret" /\ HatIs(Ev.h) /\ ((err[T] = "unilat") <=> Ev.e = "unilat") /\ Return(T)
     \/ Ev.a = "Enter" /\ EnterServer(T)
     \/ Ev.a = "Exit" /\ ExitServer(T)
     \/ Ev.a = "DispatchIn" /\ DispatchIn(T)
     \/ Ev.a = "DispatchOut" /\ DispatchOut(T)
Hidden ==
  /\ (FastAlloc(T) \/ Lock(T) \/ MallocOk(T) \/ AbortAlloc(T) \/ AbortMallocOk(T))
  /\ UNCHANGED i
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
