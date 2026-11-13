------------------------------ MODULE AnaStream ------------------------------
(* PR 8359 (CBRD-27683) head 3501715f1: the analytic functions of one evaluation group put their rows out
   as they are sorted (qexec_analytic_put_next -> qexec_analytic_add_tuple -> qexec_analytic_stream_add_row),
   and the rows of a function whose value is final only at the end of its group wait in a memory area of
   max_agg_hash_size (AreaMax rows here) and then in two list files (tuples, INT row values) until
   qexec_analytic_stream_flush puts them out. One leader thread; no shared state. The reference is the
   existing path (develop), modeled as its answer RefOut. Every action is a row of MAP.md's refinement map. *)
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS NR, NP, NK, AreaMax, MaxF, SkipFlags, Faults, Mutant

Kinds == {"RN", "RK", "DR", "CO", "CP", "NT", "PR"}
\* RN ROW_NUMBER, RK RANK, DR DENSE_RANK (PARTITION BY p ORDER BY k); CO COUNT(*) OVER (PARTITION BY p ORDER BY k);
\* CP COUNT(*) OVER (PARTITION BY p); NT NTILE, PR PERCENT_RANK (PARTITION BY p ORDER BY k)
FinalAtRow == {"RN", "RK", "DR"}
HasRowVal == {"RN", "RK", "DR", "PR"}
Aggs == {"CO", "CP"}
KeysOf(f) == IF f = "CO" THEN 2 ELSE 1

Row == [p : 1..NP, k : 1..NK]
Le(a, b) == a.p < b.p \/ (a.p = b.p /\ a.k <= b.k)
Sorted(s) == \A j \in 1..(Len(s) - 1) : Le(s[j], s[j + 1])
Inputs == UNION {{s \in [1..n -> Row] : Sorted(s)} : n \in 0..NR}
FSets == {f \in SUBSET Kinds : f # {} /\ Cardinality(f) <= MaxF}
Min(a, b) == IF a < b THEN a ELSE b
MaxOf(S) == CHOOSE x \in S : \A y \in S : y <= x

VARIABLES
  rows, F, skip,           \* input: sorted rows, the evaluation group's functions, SKIP_SORT flag of the xasl with SELECT ROWNUM
  streaming,               \* qexec_analytic_can_stream
  pc, ret, i, ended, err,
  grp, skc, rk, dr, cnt, sv,
  area, spill, spillVals, valsInMem, files, fl,
  out, inum

vars == <<rows, F, skip, streaming, pc, ret, i, ended, err, grp, skc, rk, dr, cnt, sv,
          area, spill, spillVals, valsInMem, files, fl, out, inum>>

Waits == (F \ FinalAtRow) # {}
\* qexec_analytic_can_stream: every function streams; the waiting ones end their groups at the same keys
CanStream ==
  /\ Mutant = "keys" \/ Cardinality({KeysOf(f) : f \in F \ FinalAtRow}) <= 1

\* qexec_analytic_eval_instnum_pred (develop 36c7433d8, CBRD-27989): a selected inst_num () is evaluated at the
\* intermediate stage only when this group skipped its sort (analytic_state->is_skip_sort); a skip-sort group returns
\* before qexec_analytic_can_stream, so a streaming group never does. Mutant base-xasl-flag is the old base
\* (953e83256), which read the xasl's SKIP_SORT flag that an earlier, index-ordered group set
IntermStage == skip /\ Mutant = "base-xasl-flag"

\* ---- the reference: the existing path's answer (develop) ----
Part(j) == {m \in 1..Len(rows) : rows[m].p = rows[j].p}
RefVal(j, f) ==
  IF f = "RN" THEN <<"v", Cardinality({m \in Part(j) : m <= j}), 0>>
  ELSE IF f = "RK" THEN <<"v", 1 + Cardinality({m \in Part(j) : rows[m].k < rows[j].k}), 0>>
  ELSE IF f = "DR" THEN <<"v", Cardinality({rows[m].k : m \in {m2 \in Part(j) : rows[m2].k <= rows[j].k}}), 0>>
  ELSE IF f = "CO" THEN <<"v", Cardinality({m \in Part(j) : rows[m].k <= rows[j].k}), 0>>
  ELSE IF f = "CP" THEN <<"v", Cardinality(Part(j)), 0>>
  ELSE IF f = "NT" THEN <<"nt", Cardinality({m \in Part(j) : m < j}), Cardinality(Part(j))>>
  ELSE <<"pr", Cardinality({m \in Part(j) : rows[m].k < rows[j].k}), Cardinality(Part(j))>>
\* the old base with the xasl flag evaluated inst_num () at the intermediate stage for every row and wrote the
\* output after the sort, so every row read the last number (measured: 12 rows -> ROWNUM 12 on every row)
RefRownum(j) == IF IntermStage THEN Len(rows) ELSE j
RefOut(j) == [id |-> j, v |-> [f \in F |-> RefVal(j, f)], rn |-> RefRownum(j)]

\* ---- the head's values at qexec_analytic_stream_put_row ----
Val(f, rec, r, n) ==
  IF f \in FinalAtRow THEN <<"v", rec.rv[f], 0>>
  ELSE IF f = "NT" THEN <<"nt", r, n>>
  \* sort_key_tuple_position = row - row_vals[j]; the function reads group_tuple_position - sort_key_tuple_position
  ELSE IF f = "PR" THEN <<"pr", r - (r - rec.rv["PR"]), n>>
  ELSE <<"v", sv[f], 0>>
\* inst_num () is evaluated at the group stage (put_row) unless the xasl's SKIP_SORT flag moves it to the
\* intermediate stage (qexec_analytic_eval_instnum_pred), which runs at the top of each put_next row
GroupStageRownum == ~IntermStage /\ Mutant # "rownum-at-add"
OutRow(rec, r, n) == [id |-> rec.id, v |-> [f \in F |-> Val(f, rec, r, n)],
                      rn |-> IF GroupStageRownum THEN inum + 1 ELSE inum]
NextInum == IF GroupStageRownum THEN inum + 1 ELSE inum

SpillRec(m) == [id |-> spill[m], rv |-> IF Mutant = "vals-skew" THEN spillVals[1] ELSE spillVals[m]]
FlushRec(r) ==
  IF Mutant = "spill-first"
  THEN IF r < Len(spill) THEN SpillRec(r + 1) ELSE area[r - Len(spill) + 1]
  ELSE IF r < Len(area) THEN area[r + 1] ELSE SpillRec(r - Len(area) + 1)

ZeroSv == [f \in F \cap Aggs |-> 0]

Init ==
  /\ rows \in Inputs
  /\ F \in FSets
  /\ skip \in SkipFlags
  /\ streaming = (CanStream /\ Len(rows) > 0)
  \* the existing path is the reference: it writes RefOut
  /\ pc = IF streaming THEN "key" ELSE "done"
  /\ out = IF streaming THEN <<>> ELSE [j \in 1..Len(rows) |-> RefOut(j)]
  /\ ret = "add" /\ i = 1 /\ ended = FALSE /\ err = FALSE
  /\ grp = 0 /\ skc = 0 /\ rk = 0 /\ dr = 0 /\ cnt = 0
  /\ sv = ZeroSv
  /\ area = <<>> /\ spill = <<>> /\ spillVals = <<>> /\ valsInMem = <<>> /\ files = 0 /\ fl = 0
  /\ inum = 0

First == i = 1
PChg == ~First /\ rows[i].p # rows[i - 1].p
KChg == ~First /\ ~PChg /\ rows[i].k # rows[i - 1].k

(* put_next, from the inst_num () check at the top of the row to the end of the per-function loop: a waiting
   function whose group ended (the partition for all, the sort key for CO) keeps its value
   (qexec_analytic_stream_finalize_group) and sets group_ended; start_group resets the counters *)
Key ==
  /\ pc = "key"
  /\ LET e == (PChg /\ Waits) \/ (KChg /\ "CO" \in F)
     IN /\ ended' = e
        /\ sv' = [f \in DOMAIN sv |-> IF PChg \/ (KChg /\ f = "CO") THEN cnt ELSE sv[f]]
        /\ grp' = IF First \/ PChg THEN 0 ELSE grp
        /\ skc' = IF First \/ PChg \/ KChg THEN 0 ELSE skc
        /\ cnt' = IF First \/ PChg THEN 0 ELSE cnt
        /\ dr' = IF First \/ PChg THEN 0 ELSE dr
        /\ inum' = IF IntermStage THEN inum + 1 ELSE inum
        /\ pc' = IF e /\ Mutant # "flush-after-add" THEN "flush" ELSE "add"
        /\ ret' = "add"
  /\ UNCHANGED <<rows, F, skip, streaming, i, err, rk, fl, area, spill, spillVals, valsInMem, files, out>>

(* a fault ends the query; nothing reads the counters afterwards, so they are reset (abstraction, MAP.md) *)
ResetCounters ==
  /\ grp' = 0 /\ skc' = 0 /\ rk' = 0 /\ dr' = 0 /\ cnt' = 0 /\ sv' = ZeroSv /\ ended' = FALSE

(* qexec_analytic_add_tuple + qexec_analytic_stream_add_row: evaluate the row, compute its row values, and put it
   out (no waiting function), keep it in the area (until AreaMax), or append it to the spill list files *)
Add ==
  /\ pc = "add"
  /\ LET g == grp + 1
         s == skc + 1
         newKey == First \/ PChg \/ KChg
         r == IF newKey THEN grp + 1 ELSE rk
         d == IF newKey THEN dr + 1 ELSE dr
         rv == [f \in F \cap HasRowVal |->
                  IF f = "RN" THEN g ELSE IF f = "RK" THEN r ELSE IF f = "DR" THEN d
                  ELSE IF Mutant = "pr-pos" THEN g ELSE g - s]
         rec == [id |-> i, rv |-> rv]
         nxt == IF i = Len(rows) THEN "end" ELSE "key"
         toArea == Mutant = "no-cap" \/ (files = 0 /\ Len(area) < AreaMax)
         opened == IF files = 0 THEN (IF F \cap HasRowVal # {} THEN 2 ELSE 1) ELSE files
     IN \/ /\ grp' = g /\ skc' = s /\ rk' = r /\ dr' = d /\ cnt' = cnt + 1
           /\ i' = i + 1
           /\ UNCHANGED <<ended, sv, err>>
           /\ \/ /\ ~Waits
                 /\ out' = Append(out, OutRow(rec, 0, 0))
                 /\ inum' = NextInum
                 /\ pc' = nxt
                 /\ UNCHANGED <<area, spill, spillVals, valsInMem, files, ret, fl>>
              \/ /\ Waits /\ toArea
                 /\ area' = Append(area, rec)
                 /\ inum' = IF Mutant = "rownum-at-add" THEN inum + 1 ELSE inum
                 /\ UNCHANGED <<spill, spillVals, valsInMem, files, out>>
                 /\ IF ended /\ Mutant = "flush-after-add"
                    THEN pc' = "flush" /\ ret' = nxt /\ fl' = 0
                    ELSE pc' = nxt /\ UNCHANGED <<ret, fl>>
              \/ /\ Waits /\ ~toArea
                 /\ files' = opened
                 /\ spill' = Append(spill, i)
                 /\ spillVals' = Append(spillVals, rv)
                 /\ valsInMem' = IF Mutant = "vals-in-memory" THEN Append(valsInMem, rv) ELSE valsInMem
                 /\ inum' = IF Mutant = "rownum-at-add" THEN inum + 1 ELSE inum
                 /\ UNCHANGED <<area, out>>
                 /\ IF ended /\ Mutant = "flush-after-add"
                    THEN pc' = "flush" /\ ret' = nxt /\ fl' = 0
                    ELSE pc' = nxt /\ UNCHANGED <<ret, fl>>
        \* qfile_open_list / qfile_add_*_to_list / the immediate put_row fails: the row is not added, the query ends
        \/ /\ Faults
           /\ err' = TRUE /\ pc' = "err"
           /\ files' = IF Waits /\ ~toArea THEN opened ELSE files
           /\ ResetCounters
           /\ UNCHANGED <<i, area, spill, spillVals, valsInMem, out, inum, ret, fl>>
  /\ UNCHANGED <<rows, F, skip, streaming>>

(* qexec_analytic_stream_flush, one row: fetch the kept tuple (area first, then the spill list with its row
   values from the INT list), qexec_analytic_stream_put_row writes it to the output file *)
Put ==
  /\ pc = "flush"
  /\ LET n == Len(area) + Len(spill)
         rec == FlushRec(fl)
     IN /\ n > 0
        /\ \/ /\ out' = Append(out, OutRow(rec, fl, n))
              /\ inum' = NextInum
              /\ fl' = fl + 1
              /\ pc' = IF fl + 1 = n THEN "flushend" ELSE "flush"
              /\ UNCHANGED err
           \* fetch_val_list, the output insert or the spill scan fails: the loop stops
           \/ /\ Faults
              /\ err' = TRUE /\ pc' = "flushend"
              /\ UNCHANGED <<out, inum, fl>>
  /\ UNCHANGED <<rows, F, skip, streaming, ret, i, ended, grp, skc, rk, dr, cnt, sv,
                 area, spill, spillVals, valsInMem, files>>

(* the end of qexec_analytic_stream_flush: area_used = 0, qexec_analytic_stream_drop_spill; an error goes up *)
FlushEnd ==
  /\ pc = "flushend"
  /\ area' = <<>> /\ spill' = <<>> /\ spillVals' = <<>> /\ valsInMem' = <<>>
  /\ files' = IF Mutant = "flush-no-drop" THEN files ELSE 0
  /\ fl' = 0
  /\ pc' = IF err THEN "err" ELSE ret
  /\ IF err THEN ResetCounters ELSE UNCHANGED <<grp, skc, rk, dr, cnt, sv, ended>>
  /\ UNCHANGED <<rows, F, skip, streaming, ret, i, err, out, inum>>

(* qexec_execute_analytic after sort_listfile: the waiting functions end their last group and the rows go out *)
End ==
  /\ pc = "end"
  /\ sv' = [f \in DOMAIN sv |-> cnt]
  /\ IF Waits /\ Mutant # "no-flush-at-end"
     THEN pc' = "flush" /\ ret' = "done" /\ fl' = 0
     ELSE pc' = "done" /\ UNCHANGED <<ret, fl>>
  /\ UNCHANGED <<rows, F, skip, streaming, i, ended, err, grp, skc, rk, dr, cnt,
                 area, spill, spillVals, valsInMem, files, out, inum>>

(* qexec_clear_analytic_state -> qexec_analytic_stream_clear, on the normal end and on an error *)
Clear ==
  /\ pc \in {"done", "err"}
  /\ files' = IF Mutant = "clear-no-drop" THEN files ELSE 0
  /\ area' = <<>> /\ spill' = <<>> /\ spillVals' = <<>> /\ valsInMem' = <<>>
  /\ pc' = "cleared"
  /\ ResetCounters
  /\ UNCHANGED <<rows, F, skip, streaming, ret, i, err, fl, out, inum>>

Terminated == pc = "cleared" /\ UNCHANGED vars

Next == Key \/ Add \/ Put \/ FlushEnd \/ End \/ Clear \/ Terminated
Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* ---- properties ----
TypeOK ==
  /\ pc \in {"key", "add", "flush", "flushend", "end", "done", "err", "cleared"}
  /\ files \in 0..2
  /\ i \in 1..(NR + 1)

\* C1: every row put out so far is the existing path's row at that place: the same row, values and ROWNUM
OutPrefix == Len(out) <= Len(rows) /\ \A j \in 1..Len(out) : out[j] = RefOut(j)
\* C1: a run without an error puts out every row
Complete == (pc = "cleared" /\ ~err) => Len(out) = Len(rows)
\* C2: the waiting rows in memory (tuples and row values) stay within max_agg_hash_size
MemBound == Len(area) + Len(valsInMem) <= AreaMax
\* C3: the spill list files exist only while rows are spilled, and none is left after the clear
SpillFiles == pc # "err" => ((files = 0) <=> (Len(spill) = 0))
NoLeak == pc = "cleared" => files = 0
\* C6: every run ends
Terminates == <>(pc = "cleared")

\* ---- witnesses (expected violated: the outcome is reachable) ----
NotSpillRead == ~(pc \in {"flush", "flushend"} /\ ~err /\ fl > Len(area) /\ Len(spill) > 0 /\ F \cap HasRowVal # {})
NotNtFlush == ~(pc \in {"flush", "flushend"} /\ fl > 0 /\ "NT" \in F)
NotEndFlush == ~(pc \in {"flush", "flushend"} /\ fl > 0 /\ ret = "done")
NotErrFiles == ~(pc = "err" /\ files > 0)
NotImmediate == ~(streaming /\ ~Waits /\ Len(out) > 0)
NotExisting == ~(~streaming /\ Len(rows) > 0)
NotMixedWait == ~(pc = "flushend" /\ ~err /\ F \cap FinalAtRow # {} /\ F \cap Aggs # {} /\ Len(spill) > 0)

\* ---- inductive invariant ----
PFirst(j) == j = 1 \/ rows[j].p # rows[j - 1].p
KChgAt(j) == j > 1 /\ rows[j].p = rows[j - 1].p /\ rows[j].k # rows[j - 1].k
KFirst(j) == PFirst(j) \/ KChgAt(j)
\* Key at row j sets group_ended
E(j) == j > 1 /\ ((rows[j].p # rows[j - 1].p /\ Waits) \/ (KChgAt(j) /\ "CO" \in F))
RNv(j) == RefVal(j, "RN")[2]
RKv(j) == RefVal(j, "RK")[2]
DRv(j) == RefVal(j, "DR")[2]
SKCv(j) == Cardinality({m \in Part(j) : m <= j /\ rows[m].k = rows[j].k})
RVof(j) == [f \in F \cap HasRowVal |-> IF f = "RN" THEN RNv(j) ELSE IF f = "RK" THEN RKv(j)
                                       ELSE IF f = "DR" THEN DRv(j) ELSE RefVal(j, "PR")[2]]
\* the value Key steps for rows 2..j left in stream_value
SvAt(f, j) == LET S == {m \in 2..j : rows[m].p # rows[m - 1].p \/ (f = "CO" /\ KChgAt(m))}
              IN IF S = {} THEN 0 ELSE RNv(MaxOf(S) - 1)
\* the first row of the waiting group row j belongs to
GStart(j) == MaxOf({m \in 1..j : m = 1 \/ E(m)})

\* rows b..i-1 wait in order, area first, the spill list from the area's last row on
Buffered(b) ==
  LET n == i - b IN
  /\ n >= 0
  /\ area = [m \in 1..Min(n, AreaMax) |-> [id |-> b + m - 1, rv |-> RVof(b + m - 1)]]
  /\ spill = [m \in 1..(n - Min(n, AreaMax)) |-> b + AreaMax + m - 1]
  /\ spillVals = [m \in 1..Len(spill) |-> RVof(spill[m])]

\* the counters after row j was added
CountersAt(j) ==
  /\ grp = IF j = 0 THEN 0 ELSE RNv(j)
  /\ cnt = grp
  /\ skc = IF j = 0 THEN 0 ELSE SKCv(j)
  /\ rk = IF j = 0 THEN 0 ELSE RKv(j)
  /\ dr = IF j = 0 THEN 0 ELSE DRv(j)
  /\ ended = (j > 0 /\ E(j))
\* the counters after Key at row j reset them
CountersKeyed(j) ==
  /\ grp = IF PFirst(j) THEN 0 ELSE RNv(j - 1)
  /\ cnt = grp
  /\ skc = IF KFirst(j) THEN 0 ELSE SKCv(j - 1)
  /\ rk = IF j = 1 THEN 0 ELSE RKv(j - 1)
  /\ dr = IF PFirst(j) THEN 0 ELSE DRv(j - 1)
  /\ ended = E(j)
Zeroed == grp = 0 /\ skc = 0 /\ rk = 0 /\ dr = 0 /\ cnt = 0 /\ sv = ZeroSv /\ ended = FALSE
Empty == area = <<>> /\ spill = <<>> /\ spillVals = <<>>

Active ==
  /\ i \in 1..(Len(rows) + 1)
  /\ pc \in {"key", "add"} => i <= Len(rows)
  /\ pc = "end" => i = Len(rows) + 1
  /\ fl \in IF pc = "flush" THEN 0..(NR - 1) ELSE IF pc = "flushend" THEN 0..NR ELSE {0}
  /\ err \in IF pc = "flushend" THEN BOOLEAN ELSE {FALSE}
  /\ ret = IF pc \in {"flush", "flushend"} /\ i = Len(rows) + 1 THEN "done" ELSE "add"
  /\ LET b == Len(out) - (IF pc \in {"flush", "flushend"} THEN fl ELSE 0) + 1
         n == i - b
     IN /\ b >= 1
        /\ Buffered(b)
        /\ files = IF Len(spill) = 0 THEN 0 ELSE IF F \cap HasRowVal # {} THEN 2 ELSE 1
        /\ ~Waits => n = 0
        /\ (Waits /\ pc # "add" /\ i > 1) => b = GStart(i - 1)
        /\ (Waits /\ pc = "add") => b = (IF i = 1 \/ E(i) THEN i ELSE GStart(i - 1))
        /\ pc \in {"flush", "flushend"} => (Waits /\ n > 0 /\ (i <= Len(rows) => E(i)))
        /\ pc = "flush" => fl < n
        /\ pc = "flushend" => (IF err THEN fl < n ELSE fl = n)
  /\ IF pc \in {"key", "end"}
     THEN CountersAt(i - 1) /\ sv = [f \in F \cap Aggs |-> SvAt(f, i - 1)]
     ELSE IF i <= Len(rows)
     THEN CountersKeyed(i) /\ sv = [f \in F \cap Aggs |-> SvAt(f, i)]
     ELSE CountersAt(i - 1) /\ sv = [f \in F \cap Aggs |-> RNv(Len(rows))]

StreamInv ==
  /\ pc \in {"key", "add", "flush", "flushend", "end", "done", "err", "cleared"}
  /\ \E o \in 0..Len(rows) : out = [j \in 1..o |-> RefOut(j)]
  /\ inum = Len(out)
  /\ IF pc \in {"key", "add", "flush", "flushend", "end"} THEN Active
     ELSE IF pc = "done"
     THEN /\ i = Len(rows) + 1 /\ Len(out) = Len(rows) /\ err = FALSE /\ fl = 0
          /\ ret = IF Waits THEN "done" ELSE "add"
          /\ Empty /\ files = 0
          /\ CountersAt(Len(rows)) /\ sv = [f \in F \cap Aggs |-> RNv(Len(rows))]
     ELSE IF pc = "err"
     THEN /\ i \in 1..(Len(rows) + 1) /\ err = TRUE /\ fl = 0 /\ ret \in {"add", "done"}
          /\ \/ Empty
             \/ Buffered(Len(out) + 1)
          /\ files \in 0..2
          /\ Zeroed
     ELSE /\ i \in 1..(Len(rows) + 1) /\ err \in BOOLEAN /\ fl = 0 /\ ret \in {"add", "done"}
          /\ Empty /\ files = 0 /\ Zeroed
          /\ ~err => (Len(out) = Len(rows) /\ i = Len(rows) + 1)

IndInv ==
  /\ rows \in Inputs
  /\ F \in FSets
  /\ skip = FALSE
  /\ skip \in SkipFlags
  /\ streaming = (CanStream /\ Len(rows) > 0)
  /\ valsInMem = <<>>
  /\ IF streaming THEN StreamInv
     ELSE /\ pc \in {"done", "cleared"} /\ out = [j \in 1..Len(rows) |-> RefOut(j)]
          /\ i = 1 /\ ret = "add" /\ err = FALSE /\ fl = 0 /\ inum = 0
          /\ Empty /\ files = 0 /\ Zeroed
=============================================================================
