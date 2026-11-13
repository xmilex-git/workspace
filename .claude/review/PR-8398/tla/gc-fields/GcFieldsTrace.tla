---------------------------- MODULE GcFieldsTrace ----------------------------
(* Trace validation of GcFields: a run of the instrumented build (traces/tlatrace-fields.patch on
   ea06eca48 for Side = "pr", on 0661d2c12 for Side = "dev"), normalized by traces/post.py, is a
   behavior of the spec when every logged event is taken by its action and leaves the logged side's
   node with the logged fields. The run supplies the inputs (string2, spare bytes, full) and the
   results; the spec supplies everything else, the other side included.
   Hidden steps: Write (the output row is written and the node cleared), nothing else. *)
EXTENDS GcFields, GcFieldsTraceData, Sequences

CONSTANTS TraceLog, Side

VARIABLE i

tvars == <<vars, i>>

CsName(c) == IF c = 5 THEN "u" ELSE IF c = 4 THEN "k" ELSE IF c = 1 THEN "raw" ELSE IF c = 3 THEN "i" ELSE "n"
CmpName(c) == IF c = 0 THEN "ny" ELSE IF c = -1 THEN "un" ELSE "ok"

\* the string2 an App event logged
EvV(e) ==
  IF e.vnul = 1 THEN NullV(e.vt)
  ELSE [t |-> e.vt, p |-> e.vp, sz |-> e.vsz, ln |-> IF e.vt \in Chars THEN e.vln ELSE e.vsz,
        lc |-> e.vlc, zp |-> Unk, zl |-> Unk, cs |-> CsName(e.vcs), co |-> e.vco, nul |-> FALSE,
        cmp |-> CmpName(e.vcmp)]

\* the logged side's node holds the logged result fields
Match(x, e) ==
  /\ x.t = e.rt
  /\ x.nul = (e.rnul = 1)
  /\ ~x.nul => /\ x.p = e.rp /\ x.sz = e.rsz /\ x.lc = e.rlc
               /\ (x.t \in Chars => x.ln = e.rln)
               /\ x.cs = CsName(e.rcs) /\ x.co = e.rco /\ x.cmp = CmpName(e.rcmp)
After1(n) == IF Side = "dev" THEN dev'[n] ELSE pr'[n]

TQuery(e) ==
  /\ e.a = "Query" /\ Live /\ ph \in {"idle", "out"} /\ \A w \in Workers : wph[w] = "idle"
  /\ \E t \in AggTypes :
       /\ at' = t
       /\ sepv' = IF e.sepnul = 1 THEN NullV(t) ELSE Empty(t)
       /\ dev' = [n \in Nodes |-> NullV(t)] /\ pr' = [n \in Nodes |-> NullV(t)]
  /\ mode' = e.mode
  /\ fresh' = [n \in Nodes |-> TRUE] /\ ph' = "idle" /\ wph' = [w \in Workers |-> "idle"]
  /\ ocnt' = FALSE /\ rows' = [n \in Nodes |-> 0] /\ passes' = 0 /\ grp' = 0
  /\ UNCHANGED <<ora, dcs, errd, outv, written, assertF, staleW, seen>>

\* finalize_node's worker value: the clone's accumulator, or its cut to the logged bytes
MVal(x, e) == IF x.sz = e.vsz THEN x ELSE Trunc(x, e.vsz, IF x.t \in Chars THEN e.vln ELSE e.vsz)

TApp(e) ==
  /\ e.a = "App"
  /\ IF e.full = 1
     THEN Full(e.p, e.w, e.k)
     ELSE \E g1, g2 \in BOOLEAN :
            IF e.k = "mval"
            THEN AppStep("o", e.w, "mval", MVal(dev[e.w], e), MVal(pr[e.w], e), e.sp, g1, g2)
            ELSE AppStep(e.p, e.w, e.k, EvV(e), EvV(e), e.sp, g1, g2)
  /\ Match(After1(e.p), e)
  /\ errd'[Side] = (e.err = 1)

TClone(e) == e.a = "Clone" /\ MergeClone(e.w) /\ Match(After1("o"), e)

TRehome(e) ==
  /\ e.a = "Rehome"
  /\ IF e.dir = "borrow" THEN Borrow ELSE Restore /\ Match(After1("o"), e)

TFin(e) == e.a = "Fin" /\ Fin /\ Match(After1("o"), e)

Logged ==
  /\ i < Len(TraceLog)
  /\ LET e == TraceLog[i + 1] IN TQuery(e) \/ TApp(e) \/ TClone(e) \/ TRehome(e) \/ TFin(e)
  /\ i' = i + 1

Hidden == Write /\ UNCHANGED i

TInit == Init /\ i = 0
TNext == Logged \/ Hidden
TSpec == TInit /\ [][TNext]_tvars

TraceNotDone == i < Len(TraceLog)
=============================================================================
