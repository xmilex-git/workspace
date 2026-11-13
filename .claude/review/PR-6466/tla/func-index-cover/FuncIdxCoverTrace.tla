--------------------------- MODULE FuncIdxCoverTrace ---------------------------
(* Trace validation: is a run of the instrumented head build (f1f4f21ea + TLATRACE lines in
   pt_to_class_spec_list, btree_attrinfo_read_dbvalues and eval_key_filter) a behavior of FuncIdxCover?
   One logged Gen event per index scan the query compiles (its plan and XASL decisions), then one
   KeyRead per function result a covered tuple reads from the key and one KfRead per function result a
   key filter reads. Plan and Exec are not logged. TraceIn fixes the query's inputs. *)
EXTENDS FuncIdxCover, FuncIdxCoverTraceData, Sequences

CONSTANTS TraceLog, TraceIn
VARIABLE i
TVars == <<vars, i>>

TInit ==
  /\ Init
  /\ funcIdx = TraceIn.funcIdx /\ argInKey = TraceIn.argInKey /\ useF = TraceIn.useF
  /\ fInSel = TraceIn.fInSel /\ fInSarg = TraceIn.fInSarg /\ fInOuter = TraceIn.fInOuter
  /\ fInJoin = TraceIn.fInJoin /\ mixed = TraceIn.mixed /\ rawArg = TraceIn.rawArg
  /\ extraCol = TraceIn.extraCol /\ heapStmt = TraceIn.heapStmt /\ agg = TraceIn.agg
  /\ domBad = TraceIn.domBad /\ sess = TraceIn.sess /\ negZero = FALSE /\ listfile = TraceIn.listfile
  /\ looseHint = FALSE /\ mro = FALSE
  /\ i = 0

Ev == TraceLog[i + 1]
B(x) == IF x THEN 1 ELSE 0
Logged ==
  /\ i < Len(TraceLog)
  /\ i' = i + 1
  /\ \/ /\ Ev.a = "Gen" /\ Gen
        /\ Ev.func = B(funcIdx) /\ Ev.cover = B(cover) /\ Ev.kf = B(kf)
        /\ Ev.icover = B(icover') /\ Ev.fic = B(fic') /\ Ev.rsel = B(rsel') /\ Ev.loose = B(loose')
     \/ Ev.a = "KeyRead" /\ phase \in {"exec", "done"} /\ rsel /\ UNCHANGED vars
     \/ Ev.a = "KfRead" /\ phase \in {"exec", "done"} /\ rkf /\ UNCHANGED vars
Hidden == (Plan \/ Exec) /\ UNCHANGED i
TSpec == TInit /\ [][Logged \/ Hidden]_TVars

TraceNotDone == i < Len(TraceLog)

In(fi, ak, sel, sarg, outer, rawa, extra, heap, lf, db) ==
  [funcIdx |-> fi, argInKey |-> ak, useF |-> (sel \/ sarg \/ outer), fInSel |-> sel, fInSarg |-> sarg,
   fInOuter |-> outer, fInJoin |-> FALSE, mixed |-> FALSE, rawArg |-> rawa, extraCol |-> extra,
   heapStmt |-> heap, agg |-> FALSE, domBad |-> db, sess |-> FALSE, listfile |-> lf]
\* the queries are in MAP.md, "Trace validation"
CoverIn   == In(TRUE, FALSE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE)
KfIn      == In(TRUE, FALSE, FALSE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE)
HashIn    == In(TRUE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE)
UpdIn     == In(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE)
OuterIn   == In(TRUE, FALSE, TRUE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE)
TzIn      == In(TRUE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE)
PlainIn   == In(FALSE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE)
=============================================================================
