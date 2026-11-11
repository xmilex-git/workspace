--------------------------- MODULE AsyncReadTrace ---------------------------
(* Trace validation: is a run an instrumented build recorded a behavior of
   AsyncRead?  Each logged event must be the action it names, by that thread,
   on that page, with the logged outcome.  The build does not log a thread's
   moves between its page-buffer calls (which lock it takes, which page it
   turns to, when it wakes, when it starts over) nor the device: those steps are taken here
   only by the thread of the next event, towards that event, and by the
   device only for the page the next event reaps.  Accepted iff TLC reaches
   i = Len(TraceLog). *)
EXTENDS AsyncRead, AsyncReadTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0
Ev == TraceLog[i + 1]
ResOf(e) == IF e.err = 1 THEN "err" ELSE "ok"

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ /\ Ev.a = "ReadAhead"
        /\ bcb[Ev.page] = "absent"
        /\ ReadAhead(Ev.p)
        /\ bcb'[Ev.page] = "io"
     \/ /\ Ev.a = "InlineComplete"
        /\ Ev.page \in sq[Ev.p]
        /\ InlineComplete(Ev.p)
        /\ Ev.page \notin sq'[Ev.p]
        /\ res'[Ev.page] = ResOf(Ev)
     \/ /\ Ev.a = "SubmitNow"
        /\ SubmitNow(Ev.p)
     \/ /\ Ev.a = "Reap"
        /\ Ev.page \in cq[Ev.o]
        /\ res[Ev.page] = ResOf(Ev)
        /\ IF Ev.p = Ev.o
             THEN ReapOwn(Ev.p)
             ELSE pc[Ev.p] = "sleepPage" /\ waitRing[Ev.p] = Ev.o /\ ReapForWaiter(Ev.p)
        /\ Ev.page \notin cq'[Ev.o]
     \/ /\ Ev.a = "IssueRead"
        /\ want[Ev.p] = Ev.page
        /\ IssueRead(Ev.p)
     \/ /\ Ev.a = "SleepOnPage"
        /\ want[Ev.p] = Ev.page
        /\ \/ /\ SleepOnPage(Ev.p)
              /\ waitRing'[Ev.p] = Ev.o
           \/ \* the thread looked the page up again and found it as before
              /\ pc[Ev.p] = "sleepPage"
              /\ waitRing[Ev.p] = Ev.o
              /\ bcb[Ev.page] = "io"
              /\ UNCHANGED vars
     \/ /\ Ev.a = "FixValid"
        /\ want[Ev.p] = Ev.page
        /\ FixValid(Ev.p)
     \/ /\ Ev.a = "Victimize"
        /\ bcb[Ev.page] = "valid"
        /\ Victimize
        /\ bcb'[Ev.page] = "absent"
     \/ /\ Ev.a = "Finish"
        /\ Finish(Ev.p)

\* The unlogged step that takes thread t from where it is towards a fix of page p.
TowardFix(t, p) ==
  \/ pc[t] = "start" /\ NoReadAhead(t)
  \/ pc[t] = "lock" /\ NoLock(t)
  \/ pc[t] = "want" /\ PickPage(t) /\ want'[t] = p
  \/ pc[t] = "sleepPage" /\ WakePage(t)
  \/ pc[t] = "release" /\ ReleaseX(t)
  \/ pc[t] = "finish" /\ Loop(t)
  \/ pc[t] = "done" /\ Reuse(t)

\* ... towards the end of its request (or the start of its next read-ahead call).
TowardEnd(t) ==
  \/ pc[t] = "start" /\ NoReadAhead(t)
  \/ pc[t] = "lock" /\ NoLock(t)
  \/ pc[t] = "want" /\ NoFix(t)
  \/ pc[t] = "sleepPage" /\ WakePage(t)
  \/ pc[t] = "release" /\ ReleaseX(t)

Hidden ==
  /\ i < Len(TraceLog)
  /\ UNCHANGED i
  /\ \/ /\ Ev.a = "ReadAhead"
        /\ pc[Ev.p] \notin {"start", "pf"}
        /\ \/ TowardEnd(Ev.p)
           \/ pc[Ev.p] = "finish" /\ Loop(Ev.p)
           \/ pc[Ev.p] = "done" /\ Reuse(Ev.p)
     \/ /\ Ev.a \in {"IssueRead", "FixValid"}
        /\ ~(pc[Ev.p] = "fix" /\ want[Ev.p] = Ev.page)
        /\ TowardFix(Ev.p, Ev.page)
     \/ /\ Ev.a = "SleepOnPage"
        /\ ~(pc[Ev.p] = "fix" /\ want[Ev.p] = Ev.page)
        /\ ~(pc[Ev.p] = "sleepPage" /\ want[Ev.p] = Ev.page /\ waitRing[Ev.p] = Ev.o /\ bcb[Ev.page] = "io")
        /\ TowardFix(Ev.p, Ev.page)
     \/ /\ Ev.a = "Reap"
        /\ Ev.page \in inflight[Ev.o]
        /\ DeviceComplete
        /\ Ev.page \in cq'[Ev.o]
        /\ res'[Ev.page] = ResOf(Ev)
     \/ /\ Ev.a = "Reap"
        /\ Ev.p = Ev.o
        /\ \/ pc[Ev.p] = "sleepPage" /\ WakePage(Ev.p)
           \/ pc[Ev.p] = "done" /\ Reuse(Ev.p)
     \/ /\ Ev.a = "Finish"
        /\ pc[Ev.p] # "finish"
        /\ \/ TowardEnd(Ev.p)
           \/ pc[Ev.p] = "done" /\ Reuse(Ev.p)

TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
