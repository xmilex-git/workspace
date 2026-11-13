---------------------------- MODULE StrShareTrace ----------------------------
(* Trace validation: is a run of the instrumented PR head a behavior of
   StrShare? Every Assign event (heap_attrinfo_set_converted on a string or
   bit string of the column's family, not NULL) must be an Assign step whose
   value and column have the logged relations - types, codesets, collation
   equality, need_clear, precision classes, length and size against the
   column - and whose branch (sh) and error (er) are the ones the spec computes;
   every Build event (locator_allocate_copy_area_by_attr_info after such an
   assignment) must be a Build step. Who holds a shared buffer is not logged:
   the spec chooses it, among the holders reachable with reevaluation off. *)
EXTENDS StrShare, StrShareTraceData, Sequences

CONSTANT TraceLog
VARIABLE i
TVars == <<vars, i>>

TInit == Init /\ i = 0

LenRel(e, v, d) == CASE e.ln = "lt" -> v.len < d.p
                     [] e.ln = "eq" -> v.len = d.p
                     [] OTHER -> v.len > d.p

\* the column the event names
ColMatches(e, d) ==
  /\ d.t = e.ct
  /\ (d.p = MaxPrec) <=> (e.cm = 1)
  /\ IsChar(d.t) => d.cs = e.ccs

\* the value the event names, against that column, and the outcome the spec computes for it
ValMatches(e, v, d) ==
  /\ v.t = e.vt /\ v.pt = e.pt
  /\ IsChar(d.t) => /\ v.cs = e.vcs
                    /\ (v.co = d.co) <=> (e.co = 1)
                    /\ (Size(v) <= d.p) <=> (e.sz = 1)
  /\ v.nc <=> (e.nc = 1)
  /\ (v.p = 0) <=> (e.un = 1)
  /\ (v.p = d.p) <=> (e.pe = 1)
  /\ (v.p > MaxPrec) <=> (e.po = 1)
  /\ LenRel(e, v, d)
  /\ Shares(v, d) <=> (e.sh = 1)
  /\ ((IF Shares(v, d) THEN Setval(v).err ELSE Cast(v, d).err) # NoErr) <=> (e.er = 1)

\* the candidates an event leaves open: its types, codesets and need_clear are fixed; the
\* collation, precision, length and width are chosen and then checked by ValMatches
TCols(e) ==
  {Col(e.ct, pr, IF e.cm = 1 THEN MaxPrec ELSE 2) :
     pr \in {q \in (IF IsChar(e.ct) THEN ColPairs ELSE {BitPair}) : IsChar(e.ct) => q.cs = e.ccs}}
TVals(e) ==
  {Val(e.vt, e.pt, pr, p, l, w, e.nc = 1) :
     pr \in {q \in (IF IsChar(e.ct) THEN ValPairs ELSE {BitPair}) : IsChar(e.ct) => q.cs = e.vcs},
     p \in ValPrecs, l \in Lens, w \in (IF IsChar(e.ct) /\ e.vcs \in {"u", "e"} THEN BOOLEAN ELSE {FALSE})}

Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ LET e == TraceLog[i + 1] IN
     \/ /\ e.a = "Assign"
        /\ row < Rows /\ ncol < NCols
        /\ \E d \in TCols(e) : ColMatches(e, d) /\ \E v \in TVals(e) : ValMatches(e, v, d) /\ AssignWith(v, d)
     \/ e.a = "Build" /\ Build

TSpec == TInit /\ [][Logged]_TVars

TraceNotDone == i < Len(TraceLog)
=============================================================================
