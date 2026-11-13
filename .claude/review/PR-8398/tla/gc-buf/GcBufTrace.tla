------------------------------ MODULE GcBufTrace ------------------------------
(* Trace validation: is a run the instrumented build of ea06eca48 recorded a behavior of
   GcBuf? Each logged event must be the action it names, by that node, with the logged
   outcome (the buffer address, the capacity, the size). Every action the runs reach is
   logged, so no hidden step is allowed. Accepted iff TLC reaches i = Len(TraceLog). *)
EXTENDS GcBuf, GcBufTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
\* Ev is read once per step (TLC evaluates TraceLog again at every reference)
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ LET Ev == TraceLog[i + 1] IN
     \/ Ev.a = "OInit" /\ OInit
     \/ Ev.a = "RowStart" /\ Ev.v \in 1 .. V /\ RowStart(Ev.p, Ev.v)
        /\ (Ev.first = 1 => cnt[Ev.p] = 0 /\ str'[Ev.p] = Ev.addr /\ typ'[Ev.p] = Ev.t)
        /\ (Ev.first = 0 => cnt[Ev.p] > 0)
     \/ Ev.a = "AppendCall" /\ AppendCall(Ev.p)
        /\ str'[Ev.p] = Ev.addr /\ icap'[Ev.p] = Ev.cap /\ size'[Ev.p] = Ev.size /\ ps'[Ev.p] = Ev.sp
        /\ (Ev.r = "inplace" \/ Ev.r = "none" => str'[Ev.p] = str[Ev.p])
        /\ (Ev.r = "grow" \/ Ev.r = "replace" => str'[Ev.p] # str[Ev.p])
     \/ Ev.a = "ZeroAppend" /\ ZeroAppend(Ev.p)
        /\ str'[Ev.p] = Ev.addr /\ icap'[Ev.p] = Ev.cap /\ size'[Ev.p] = Ev.size
     \/ Ev.a = "Coerce" /\ Coerce(Ev.p) /\ str'[Ev.p] = Ev.addr
     \/ Ev.a = "StartPar" /\ StartPar /\ str'["o"] = Ev.addr
     \/ Ev.a = "Restore" /\ Restore /\ str'["o"] = Ev.addr
     \/ Ev.a = "WRun" /\ WRun(Ev.p)
     \/ Ev.a = "WMerge" /\ WMerge(Ev.p)
        /\ (Ev.k = "empty" => cnt[Ev.p] = 0)
        /\ (Ev.k = "append" => merger' = Ev.p /\ str["o"] = Ev.addr)
        /\ (Ev.k = "clone" => str'["o"] = Ev.addr /\ cnt["o"] = 0)
     \/ Ev.a = "MergeDone" /\ MergeDone
     \/ Ev.a = "WClear" /\ WClear(Ev.p) /\ str[Ev.p] = Ev.addr
     \/ Ev.a = "OEnd" /\ OEnd /\ str["o"] = Ev.addr
        /\ (Ev.k = "moveout" => Ev.addr \in ext')
        /\ (Ev.k = "clear" => ext' = ext)
     \/ Ev.a = "ExtFree" /\ ExtFreeA(Ev.addr)
TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
