--------------------------- MODULE BatchJoinDesign ---------------------------
(***************************************************************************)
(* The batched nested-loop join (D19..D24, D28).                           *)
(*                                                                         *)
(* The join collects outer rows; for each it walks the inner index and     *)
(* puts the OIDs into the OID buffer.  When the buffer is full, or the     *)
(* stored outer rows reach their bound, or the outer side ends, the batch  *)
(* is closed: the heap rows of the whole buffer are read at once (page     *)
(* order, read hints), and the join rows are emitted.  An outer row whose  *)
(* OIDs do not fit continues in the next batch.  Memoize is checked for    *)
(* every outer row before the index is walked.                             *)
(*                                                                         *)
(* The claim (C8): the join returns the same rows, the same number of      *)
(* times, as the row-at-a-time join; in order-kept mode in the same order; *)
(* an outer row with no match leaves a left outer join exactly once.       *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS BufCap,     \* OIDs the OID buffer holds (D24)
          MaxOuter,   \* outer rows a batch stores (D28, in rows instead of bytes)
          Mutant,     \* "none" or one of the wrong variants below
          MaxErrors   \* errors or interrupts in a run

\* Mutant: "no_carry" | "no_last" | "resume_next_outer" | "resume_partition_start" | "free_emit"
\*         | "memo_partial" | "hit_by_reference"

\* apalache-type: BufCap Int
\* apalache-type: MaxOuter Int
\* apalache-type: Mutant Str
\* apalache-type: MaxErrors Int
\* apalache-type: jt Str
\* apalache-type: mode Str
\* apalache-type: pass Set(<<Str, Int>>)
\* apalache-type: phase Str
\* apalache-type: next Int
\* apalache-type: resume Int
\* apalache-type: accRow Int
\* apalache-type: acc Set(Int)
\* apalache-type: kind Int -> Str
\* apalache-type: lo Int -> Int
\* apalache-type: hi Int -> Int
\* apalache-type: hitm Int -> Set(Int)
\* apalache-type: todo Set(<<Int, Int>>)
\* apalache-type: out <<Int, Int>> -> Int
\* apalache-type: memoOn Bool
\* apalache-type: cached Set(Str)
\* apalache-type: cval Str -> Set(Int)
\* apalache-type: errs Int

CInit ==
  \* the index holds 8 entries and the outer side 5 rows: a larger buffer or bound behaves as 8 and 5
  /\ BufCap \in 1..8
  /\ MaxOuter \in 1..5
  /\ Mutant = "none"
  /\ MaxErrors \in Nat

(***************************************************************************)
(* The two sides, small enough to enumerate:                               *)
(*   outer rows 1..5 in outer order, join keys k1 k2 k1 k3 k2              *)
(*   the inner index holds three entries for k1 (the first in partition    *)
(*   p1, the other two in partition p2), one for k2, none for k3           *)
(* Which inner rows the snapshot sees and the data filter accepts (pass)   *)
(* is chosen freely at the start, and so are the join type and the order   *)
(* mode: both are fixed when the plan is generated (D22).                  *)
(***************************************************************************)
N == 5
OuterIds == 1..N
Keys == {"k1", "k2", "k3"}
MaxLen == 3
Pos == 1..MaxLen
KeyOf(o) == IF o = 1 \/ o = 3 THEN "k1" ELSE IF o = 2 \/ o = 5 THEN "k2" ELSE "k3"
EntryCount(k) == IF k = "k1" THEN 3 ELSE IF k = "k2" THEN 1 ELSE 0
\* The first entry of the partition that entry i of key k is in.
PartStart(k, i) == IF k = "k1" /\ i >= 2 THEN 2 ELSE 1
Entries == {e \in Keys \X Pos : e[2] <= EntryCount(e[1])}
JoinTypes == {"inner", "left", "semi", "anti"}
Modes == {"ordered", "free"}
\* A join row: <<o, i>> is outer row o with the inner row of entry i; <<o, 0>> is the outer row alone
\* (NULL-extended in a left outer join, the row itself in a semi or anti join).
AllItems == OuterIds \X (0..MaxLen)
\* @type: (<<Int, Int>>) => Int;
Rank(x) == x[1] * 10 + x[2]

VARIABLES jt, mode, pass,   \* fixed at the start
          phase,    \* "collect" | "emit" | "done" | "aborted"
          next,     \* the outer row to collect next
          resume,   \* entries of row `next` that earlier batches already took
          accRow,   \* the outer row that continues from an earlier batch (0: none)
          acc,      \* its matches found in earlier batches
          kind,     \* [OuterIds -> "none" | "hit" | "scan"]: the rows of the open batch
          lo, hi,   \* a scan row's entries lo+1..hi are in the OID buffer
          hitm,     \* a hit row's copy of the memoized matches
          todo,     \* join rows of the closed batch not yet emitted
          out,      \* [AllItems -> Nat]: times a join row was emitted
          memoOn, cached, cval,   \* memoize: enabled, keys stored, their matches
          errs

cfgv == <<jt, mode, pass>>
vars == <<jt, mode, pass, phase, next, resume, accRow, acc, kind, lo, hi, hitm, todo, out, memoOn, cached, cval, errs>>

NumEntries(o) == EntryCount(KeyOf(o))
Matches(k) == {i \in Pos : <<k, i>> \in pass}
MatchesUpTo(o, h) == {i \in Pos : i <= h /\ <<KeyOf(o), i>> \in pass}
BatchRows == {o \in OuterIds : kind[o] # "none"}
Used == (hi[1] - lo[1]) + (hi[2] - lo[2]) + (hi[3] - lo[3]) + (hi[4] - lo[4]) + (hi[5] - lo[5])
Min(a, b) == IF a <= b THEN a ELSE b

\* What a join emits for outer row o from the matches B, when matches were (P) or were not found for the row
\* before, and the row's entries end here (end) or not.
\* @type: (Int, Set(Int), Bool, Bool) => Set(<<Int, Int>>);
Emits(o, B, P, end) ==
  IF jt = "inner" THEN {<<o, i>> : i \in B}
  ELSE IF jt = "left" THEN {<<o, i>> : i \in B} \cup (IF end /\ B = {} /\ ~P THEN {<<o, 0>>} ELSE {})
  ELSE IF jt = "semi" THEN (IF B # {} /\ ~P THEN {<<o, 0>>} ELSE {})
  ELSE (IF end /\ B = {} /\ ~P THEN {<<o, 0>>} ELSE {})

\* The row-at-a-time join: everything outer row o gives once its first h entries are processed.
Pref(o, h) == LET B == MatchesUpTo(o, h)
                  e == (h = NumEntries(o))
              IN  Emits(o, B, FALSE, e)
RefItems(o) == Pref(o, NumEntries(o))
Ref == UNION {RefItems(o) : o \in OuterIds}

TypeOK ==
  /\ jt \in JoinTypes /\ mode \in Modes /\ pass \in SUBSET Entries
  /\ phase \in {"collect", "emit", "done", "aborted"}
  /\ next \in 1..(N + 1)
  /\ resume \in 0..MaxLen
  /\ accRow \in 0..N
  /\ acc \in SUBSET Pos
  /\ kind \in [OuterIds -> {"none", "hit", "scan"}]
  /\ lo \in [OuterIds -> 0..MaxLen]
  /\ hi \in [OuterIds -> 0..MaxLen]
  /\ hitm \in [OuterIds -> SUBSET Pos]
  /\ todo \in SUBSET AllItems
  /\ out \in [AllItems -> 0..3]
  /\ memoOn \in BOOLEAN
  /\ cached \in SUBSET Keys
  /\ cval \in [Keys -> SUBSET Pos]
  /\ errs \in Int /\ errs >= 0 /\ errs <= MaxErrors

Init ==
  /\ jt \in JoinTypes /\ mode \in Modes /\ pass \in SUBSET Entries
  /\ phase = "collect"
  /\ next = 1 /\ resume = 0 /\ accRow = 0 /\ acc = {}
  /\ kind = [o \in OuterIds |-> "none"]
  /\ lo = [o \in OuterIds |-> 0]
  /\ hi = [o \in OuterIds |-> 0]
  /\ hitm = [o \in OuterIds |-> {}]
  /\ todo = {}
  /\ out = [x \in AllItems |-> 0]
  /\ memoOn \in BOOLEAN
  /\ cached = {}
  /\ cval = [k \in Keys |-> {}]
  /\ errs = 0

(***************************************************************************)
(* Collecting a batch                                                      *)
(***************************************************************************)
CanAdd == next <= N /\ Cardinality(BatchRows) < MaxOuter /\ Used < BufCap

\* The next outer row joins the batch.  A memoized key takes a copy of its matches and no buffer space;
\* otherwise the row's index entries go into the OID buffer, as many as fit.  A row that does not fit stays
\* the next row, and the entries taken so far are remembered.
AddOuter ==
  /\ phase = "collect" /\ CanAdd
  /\ LET o == next
         k == KeyOf(o)
         n == NumEntries(o)
         take == Min(n - resume, BufCap - Used)
         upto == resume + take
     IN  IF memoOn /\ k \in cached /\ resume = 0
           THEN /\ kind' = [kind EXCEPT ![o] = "hit"]
                /\ hitm' = [hitm EXCEPT ![o] = cval[k]]
                /\ next' = next + 1
                /\ UNCHANGED <<lo, hi, resume>>
           ELSE /\ kind' = [kind EXCEPT ![o] = "scan"]
                /\ lo' = [lo EXCEPT ![o] = resume]
                /\ hi' = [hi EXCEPT ![o] = upto]
                /\ UNCHANGED hitm
                /\ IF upto = n \/ Mutant = "resume_next_outer"
                     THEN next' = next + 1 /\ resume' = 0
                     ELSE /\ next' = next
                          /\ resume' = IF Mutant = "resume_partition_start" THEN PartStart(k, upto + 1) - 1 ELSE upto
  /\ UNCHANGED <<cfgv, phase, accRow, acc, todo, out, memoOn, cached, cval, errs>>

\* Matches of a batch row among the entries this batch holds.
ScanM(o) == {i \in Pos : lo[o] < i /\ i <= hi[o] /\ <<KeyOf(o), i>> \in pass}
\* Matches of the row found in earlier batches.
Prior(o) == IF o = accRow /\ Mutant # "no_carry" THEN acc ELSE {}
\* The row's entries end in this batch.
Complete(o) == hi[o] = NumEntries(o) \/ Mutant = "no_last"

ItemsOf(o) ==
  IF kind[o] = "hit"
    THEN LET B == IF Mutant = "hit_by_reference" THEN (IF KeyOf(o) \in cached THEN cval[KeyOf(o)] ELSE {})
                  ELSE hitm[o]
         IN  Emits(o, B, FALSE, TRUE)
    ELSE LET B == ScanM(o)
             P == Prior(o) # {}
             e == Complete(o)
         IN  Emits(o, B, P, e)

\* Rows whose result is memoized at the end of the batch, and the result: every row whose entries end in
\* this batch, also one that began in an earlier batch (D35).
Storable == {o \in OuterIds : kind[o] = "scan" /\ hi[o] = NumEntries(o)}
StoreVal(o) == IF Mutant = "memo_partial" THEN ScanM(o) ELSE ScanM(o) \cup (IF o = accRow THEN acc ELSE {})

\* The batch is closed: the heap rows of the OID buffer are read (in page order, with read hints), the join
\* rows are worked out, finished rows are memoized, and the matches of a row that continues are carried over.
CloseBatch ==
  /\ phase = "collect" /\ ~CanAdd /\ BatchRows # {}
  /\ todo' = UNION {ItemsOf(o) : o \in BatchRows}
  /\ IF memoOn
       THEN /\ cached' = cached \cup {KeyOf(o) : o \in Storable}
            /\ cval' = [k \in Keys |-> IF \E o \in Storable : KeyOf(o) = k
                                         THEN UNION {StoreVal(o) : o \in {s \in Storable : KeyOf(s) = k}}
                                         ELSE cval[k]]
       ELSE UNCHANGED <<cached, cval>>
  /\ IF \E o \in OuterIds : o = next /\ kind[o] = "scan"
       THEN /\ accRow' = next
            /\ acc' = ScanM(next) \cup (IF next = accRow THEN acc ELSE {})
       ELSE accRow' = 0 /\ acc' = {}
  /\ phase' = "emit"
  /\ UNCHANGED <<cfgv, next, resume, kind, lo, hi, hitm, out, memoOn, errs>>

\* One join row leaves.  In order-kept mode it is the first one in outer order, then index order; otherwise
\* any (the heap rows were read in page order).
EmitOne ==
  /\ phase = "emit"
  /\ \E x \in todo :
       /\ (mode = "ordered" /\ Mutant # "free_emit") => \A y \in todo : Rank(x) <= Rank(y)
       /\ todo' = todo \ {x}
       /\ out' = [out EXCEPT ![x] = @ + 1]
  /\ UNCHANGED <<cfgv, phase, next, resume, accRow, acc, kind, lo, hi, hitm, memoOn, cached, cval, errs>>

EndBatch ==
  /\ phase = "emit" /\ todo = {}
  /\ kind' = [o \in OuterIds |-> "none"]
  /\ lo' = [o \in OuterIds |-> 0]
  /\ hi' = [o \in OuterIds |-> 0]
  /\ hitm' = [o \in OuterIds |-> {}]
  /\ phase' = IF next > N THEN "done" ELSE "collect"
  /\ UNCHANGED <<cfgv, next, resume, accRow, acc, todo, out, memoOn, cached, cval, errs>>

(***************************************************************************)
(* Environment                                                             *)
(***************************************************************************)

\* Memoize gives up (its hit ratio or its memory bound) and frees what it stored, between two outer rows.
MemoDrop ==
  /\ phase = "collect" /\ memoOn
  /\ memoOn' = FALSE
  /\ cached' = {}
  /\ cval' = [k \in Keys |-> {}]
  /\ UNCHANGED <<cfgv, phase, next, resume, accRow, acc, kind, lo, hi, hitm, todo, out, errs>>

\* An error or interrupt ends the join; the rows already emitted are discarded with the failed statement.
Abort ==
  /\ phase \in {"collect", "emit"} /\ errs < MaxErrors
  /\ phase' = "aborted"
  /\ errs' = errs + 1
  /\ UNCHANGED <<cfgv, next, resume, accRow, acc, kind, lo, hi, hitm, todo, out, memoOn, cached, cval>>

Terminated == phase \in {"done", "aborted"} /\ UNCHANGED vars

Step == AddOuter \/ CloseBatch \/ EmitOne \/ EndBatch
Next == Step \/ MemoDrop \/ Abort \/ Terminated
Spec == Init /\ [][Next]_vars /\ WF_vars(Step)

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)

\* C8: no join row the row-at-a-time join does not return, and none twice.
NoExtra == \A x \in AllItems : out[x] <= (IF x \in Ref THEN 1 ELSE 0)
\* C8: a join that ran to its end returned every row.
AllReturned == phase = "done" => \A x \in Ref : out[x] = 1
\* C8, order-kept mode: a row leaves only after every row before it.
InOrder == mode = "ordered" => \A x \in AllItems : \A y \in AllItems :
             (out[x] >= 1 /\ y \in Ref /\ Rank(y) < Rank(x)) => out[y] >= 1
Ends == <>(phase \in {"done", "aborted"})

\* Witnesses
NotSpanned == resume = 0
NotThreeBatches == \A o \in OuterIds : ~(kind[o] = "scan" /\ lo[o] > 0 /\ hi[o] < NumEntries(o))
NotHit == \A o \in OuterIds : kind[o] # "hit"
NotDropWithHit == memoOn \/ \A o \in OuterIds : kind[o] # "hit"
NotDone == phase # "done"
NotNullRow == ~(jt = "left" /\ \E o \in OuterIds : out[<<o, 0>>] = 1)
NotCarriedMatch == ~(phase = "collect" /\ accRow # 0 /\ acc # {})

(***************************************************************************)
(* Inductive invariant                                                     *)
(***************************************************************************)
Live == phase \in {"collect", "emit", "done"}
Has(x) == out[x] = 1

BatchShape ==
  Live =>
    /\ \A o \in OuterIds : kind[o] = "none" => (lo[o] = 0 /\ hi[o] = 0 /\ hitm[o] = {})
    /\ \A o \in OuterIds : kind[o] = "hit" =>
         (lo[o] = 0 /\ hi[o] = 0 /\ o < next /\ hitm[o] = Matches(KeyOf(o)))
    /\ \A o \in OuterIds : kind[o] = "scan" =>
         /\ lo[o] <= hi[o] /\ hi[o] <= NumEntries(o) /\ o <= next
         /\ o < next => hi[o] = NumEntries(o)
         /\ o = next => (hi[o] < NumEntries(o) /\ hi[o] > 0 /\ resume = hi[o] /\ Used = BufCap)
         /\ lo[o] > 0 => (lo[o] < NumEntries(o) /\ \A p \in OuterIds : p < o => kind[p] = "none")
    /\ \A o \in OuterIds : \A p \in OuterIds : (kind[o] # "none" /\ o < p /\ p < next) => kind[p] # "none"
    /\ Used <= BufCap /\ Cardinality(BatchRows) <= MaxOuter
    /\ next = N + 1 => resume = 0
    /\ \A o \in OuterIds : o = next =>
         /\ resume < NumEntries(o) \/ resume = 0
         /\ (resume > 0 /\ kind[o] = "none") => BatchRows = {}
         /\ resume = 0 => kind[o] = "none"
    /\ phase = "done" => (next = N + 1 /\ BatchRows = {})
    /\ phase # "emit" => todo = {}
    /\ phase = "emit" => (BatchRows # {} /\ \A x \in todo : kind[x[1]] # "none")

AccShape ==
  /\ phase = "collect" =>
       /\ \A o \in OuterIds : (kind[o] = "scan" /\ lo[o] > 0) => (accRow = o /\ acc = MatchesUpTo(o, lo[o]))
       /\ \A o \in OuterIds : (o = next /\ kind[o] = "none" /\ resume > 0) =>
            (accRow = o /\ acc = MatchesUpTo(o, resume))
       /\ \A o \in OuterIds : accRow = o =>
            (kind[o] = "scan" /\ lo[o] > 0) \/ (o = next /\ kind[o] = "none" /\ resume > 0)
       /\ accRow = 0 => acc = {}
  /\ phase = "emit" =>
       /\ \A o \in OuterIds : (o = next /\ kind[o] = "scan") => (accRow = o /\ acc = MatchesUpTo(o, resume))
       /\ (\A o \in OuterIds : ~(o = next /\ kind[o] = "scan")) => (accRow = 0 /\ acc = {})

CacheOk ==
  /\ \A k \in cached : cval[k] = Matches(k)
  /\ ~memoOn => cached = {}

\* What a row has given so far.
After(o) == IF kind[o] = "hit" THEN NumEntries(o) ELSE hi[o]
RowCount == Live => \A x \in AllItems : out[x] <= 1
\* A row outside the open batch: everything if it is finished, its first `resume` entries if it continues.
RowIdle ==
  Live => \A x \in AllItems :
    kind[x[1]] = "none" =>
      (Has(x) <=> IF x[1] < next THEN x \in RefItems(x[1])
                  ELSE (x[1] = next /\ resume > 0 /\ x \in Pref(x[1], resume)))
\* A row of the batch being collected: what it gave before this batch.
RowCollect ==
  phase = "collect" => \A x \in AllItems :
    kind[x[1]] # "none" => (Has(x) <=> (lo[x[1]] > 0 /\ x \in Pref(x[1], lo[x[1]])))
\* A row of the closed batch: emitted or still to emit, never both.
RowEmit ==
  phase = "emit" => \A x \in AllItems :
    kind[x[1]] # "none" =>
      /\ ~(Has(x) /\ x \in todo)
      /\ (Has(x) \/ x \in todo) <=> x \in Pref(x[1], After(x[1]))

OrderInv ==
  (mode = "ordered" /\ phase = "emit") =>
    \A x \in todo : \A y \in AllItems : out[y] >= 1 => Rank(y) < Rank(x)

IndInv ==
  /\ TypeOK
  /\ BatchShape
  /\ AccShape
  /\ CacheOk
  /\ RowCount
  /\ RowIdle
  /\ RowCollect
  /\ RowEmit
  /\ OrderInv
  /\ NoExtra
  /\ AllReturned
  /\ InOrder
=============================================================================
