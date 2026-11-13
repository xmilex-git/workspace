--------------------------- MODULE FoldTextTrace ---------------------------
(* Trace validation: is a run of the instrumented head build (3599b53b4 + TLATRACE in db_compile_statement_local,
   pt_fold_union and db_recompile_for_bind_signature, MAP.md "Trace validation") a behavior of FoldText? Every field
   is a comparison the build made itself: same (the node a fold returned already had the set operation's text), ok
   (the node pt_compile / mq_translate returned has the saved text; the recompile found a text), pre (the node had
   the saved text before the restore). Hidden: a compile or translate that returns the same node, the parse
   choices, NoRecompile, Reset. *)
EXTENDS FoldText, FoldTextTraceData, Sequences, TLC

CONSTANTS TraceLog
VARIABLE t
TVars == <<vars, t>>

TInit == Init /\ t = 0
Ev == TraceLog[t + 1]
B(x) == x = 1

Logged ==
  /\ t < Len(TraceLog)
  /\ t' = t + 1
  /\ \/ /\ Ev.a = "Parse" /\ Parse /\ n' = Ev.dim /\ (k' = 1) = B(Ev.first)
     \/ /\ Ev.a = "Fold" /\ B(Ev.nothing) /\ FoldNothing
     \/ /\ Ev.a = "Fold" /\ ~B(Ev.nothing) /\ (FoldTop \/ FoldSub) /\ lastSame' = B(Ev.same)
     \/ /\ Ev.a = "NewTop" /\ Ev.by = "compile" /\ topFolded /\ Compiled /\ (top = saved) = B(Ev.ok)
     \/ /\ Ev.a = "NewTop" /\ Ev.by = "translate" /\ Translate /\ top' \in {Own(n), [t |-> VId, l |-> VId]}
        /\ (top' = saved) = B(Ev.ok)
     \/ /\ Ev.a = "Restore" /\ Restore /\ (top = saved) = B(Ev.pre)
     \/ /\ Ev.a = "Recompile" /\ Recompile /\ (rec' = "ok") = B(Ev.ok) /\ n = Ev.dim

Hidden ==
  /\ UNCHANGED t
  /\ \/ ~topFolded /\ Compiled
     \/ Translate /\ top' = top /\ seen' = seen
     \/ NoRecompile
     \/ Reset

TSpec == TInit /\ [][Logged \/ Hidden]_TVars
TraceNotDone == t < Len(TraceLog)
=============================================================================
