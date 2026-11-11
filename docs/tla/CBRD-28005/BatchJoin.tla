--------------------------- MODULE BatchJoin ---------------------------
(***************************************************************************)
(* The batched nested-loop join as implemented (nl_join_batch): one join   *)
(* step, inner and left outer joins, the outer order kept.  The design it  *)
(* was cut from (rows that span batches, semi and anti joins, the free     *)
(* order mode) is BatchJoinDesign.                                         *)
(*                                                                         *)
(* The inner scan holds the outer rows that reach it.  For a held row the  *)
(* inner index is read at once and its OIDs are stored (a "read" row), or  *)
(* nothing is read (a "deferred" row: a key memoize holds, a null join     *)
(* value, more OIDs than one OID buffer).  When the stored OIDs reach the  *)
(* batch's target, the stored rows reach their bound, a row did not fit or *)
(* the outer scan ends, the batch is closed: the heap pages of the stored  *)
(* OIDs are named to the OS and the held rows are joined in the order they *)
(* came.  Each one's values are put back into the outer's value list and   *)
(* the unchanged row path runs: memoize answers, or the scan takes the     *)
(* row's stored OIDs, or (a deferred row) the scan reads the index itself. *)
(* A row that arrives while nothing is held and the inner scan cannot be   *)
(* read ahead is joined at once (a "passed" row).                          *)
(*                                                                         *)
(* The claim (C8): the join returns the same rows, the same number of      *)
(* times and in the same order as the row-at-a-time join; an outer row     *)
(* with no match leaves a left outer join exactly once.  The plan is       *)
(* cached: a later execution starts with nothing held.                     *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS BufCap,     \* OIDs of one OID buffer of the inner scan (D24); the batch's array holds twice as many
          MaxOuter,   \* outer rows a batch stores (D28, in rows instead of bytes)
          Mutant,     \* "none" or one of the wrong variants below
          MaxErrors,  \* errors, interrupts and early stops in a run
          MaxExec     \* executions of the cached plan

\* Mutant: "no_restore" | "stale_slice" | "partial_as_complete" | "no_flush" | "no_close_at_half"
\*         | "replay_any_order" | "keep_batch"

\* apalache-type: BufCap Int
\* apalache-type: MaxOuter Int
\* apalache-type: Mutant Str
\* apalache-type: MaxErrors Int
\* apalache-type: MaxExec Int
\* apalache-type: jt Str
\* apalache-type: pass Set(<<Str, Int>>)
\* apalache-type: phase Str
\* apalache-type: next Int
\* apalache-type: kind Int -> Str
\* apalache-type: cur Int
\* apalache-type: valrow Int
\* apalache-type: slice Int
\* apalache-type: how Str
\* apalache-type: todo Set(<<Int, Int>>)
\* apalache-type: out <<Int, Int>> -> Int
\* apalache-type: memo Str
\* apalache-type: cached Set(Str)
\* apalache-type: cval Str -> Set(Int)
\* apalache-type: errs Int
\* apalache-type: exec Int

CInit ==
  \* the index holds 8 entries and the outer side 5 rows: a larger buffer or bound behaves as 8 and 5
  /\ BufCap \in 1..8
  /\ MaxOuter \in 1..5
  /\ Mutant = "none"
  /\ MaxErrors \in Nat
  /\ MaxExec \in Nat /\ MaxExec >= 1

(***************************************************************************)
(* The two sides, small enough to enumerate:                               *)
(*   outer rows 1..5 in outer order, join keys k1 k2 k1 k3 k2              *)
(*   the inner index holds three entries for k1, one for k2, none for k3   *)
(* Which inner rows the snapshot sees and the data filter accepts (pass)   *)
(* and the join type are chosen freely at the start.                       *)
(***************************************************************************)
N == 5
OuterIds == 1..N
Keys == {"k1", "k2", "k3"}
MaxLen == 3
Pos == 1..MaxLen
KeyOf(o) == IF o = 1 \/ o = 3 THEN "k1" ELSE IF o = 2 \/ o = 5 THEN "k2" ELSE "k3"
EntryCount(k) == IF k = "k1" THEN 3 ELSE IF k = "k2" THEN 1 ELSE 0
Entries == {e \in Keys \X Pos : e[2] <= EntryCount(e[1])}
JoinTypes == {"inner", "left"}
\* A join row: <<o, i>> is outer row o with the inner row of entry i; <<o, 0>> is the outer row NULL-extended.
AllItems == OuterIds \X (0..MaxLen)
\* @type: (<<Int, Int>>) => Int;
Rank(x) == x[1] * 10 + x[2]

VARIABLES jt, pass,   \* fixed for the plan
          phase,    \* "collect" | "replay" | "done" | "stopped"
          next,     \* the outer row that arrives next
          kind,     \* [OuterIds -> "none" | "read" | "defer"]: the rows the batch holds
          cur,      \* the row inside the row path (0: none)
          valrow,   \* the outer row whose values the outer's value list holds
          slice,    \* the row whose stored OIDs the inner scan was handed and has not taken (0: none)
          how,      \* how the row inside the row path was answered: "none" | "memo" | "slice" | "scan"
          todo,     \* join rows of the open row not yet returned
          out,      \* [AllItems -> Nat]: times a join row was returned in this execution
          memo,     \* memoize: "on" | "off" | "dropped" (gave up in this execution)
          cached, cval,   \* the keys memoize holds and their matches
          errs, exec

cfgv == <<jt, pass>>
vars == <<jt, pass, phase, next, kind, cur, valrow, slice, how, todo, out, memo, cached, cval, errs, exec>>

NumEntries(o) == EntryCount(KeyOf(o))
Matches(k) == {i \in Pos : <<k, i>> \in pass}
BatchRows == {o \in OuterIds : kind[o] # "none"}
Min(a, b) == IF a <= b THEN a ELSE b
\* OIDs stored for a read row: all of the key's.  (The mutant stores what one buffer holds and calls it all.)
SliceLen(o) == IF Mutant = "partial_as_complete" THEN Min(NumEntries(o), BufCap) ELSE NumEntries(o)
Cnt(o) == IF kind[o] = "read" THEN SliceLen(o) ELSE 0
Used == Cnt(1) + Cnt(2) + Cnt(3) + Cnt(4) + Cnt(5)

\* What the join returns for outer row o whose inner matches are B.
\* @type: (Int, Set(Int)) => Set(<<Int, Int>>);
Emits(o, B) == {<<o, i>> : i \in B} \cup (IF jt = "left" /\ B = {} THEN {<<o, 0>>} ELSE {})
\* The row-at-a-time join.
RefItems(o) == Emits(o, Matches(KeyOf(o)))
Ref == UNION {RefItems(o) : o \in OuterIds}

TypeOK ==
  /\ jt \in JoinTypes /\ pass \in SUBSET Entries
  /\ phase \in {"collect", "replay", "done", "stopped"}
  /\ next \in 1..(N + 1)
  /\ kind \in [OuterIds -> {"none", "read", "defer"}]
  /\ cur \in 0..N
  /\ valrow \in 0..N
  /\ slice \in 0..N
  /\ how \in {"none", "memo", "slice", "scan"}
  /\ todo \in SUBSET AllItems
  /\ out \in [AllItems -> 0..3]
  /\ memo \in {"on", "off", "dropped"}
  /\ cached \in SUBSET Keys
  /\ cval \in [Keys -> SUBSET Pos]
  /\ errs \in Int /\ errs >= 0 /\ errs <= MaxErrors
  /\ exec \in Int /\ exec >= 1 /\ exec <= MaxExec

Init ==
  /\ jt \in JoinTypes /\ pass \in SUBSET Entries
  /\ phase = "collect"
  /\ next = 1
  /\ kind = [o \in OuterIds |-> "none"]
  /\ cur = 0 /\ valrow = 0 /\ slice = 0 /\ how = "none"
  /\ todo = {}
  /\ out = [x \in AllItems |-> 0]
  /\ memo \in {"on", "off"}
  /\ cached = {}
  /\ cval = [k \in Keys |-> {}]
  /\ errs = 0
  /\ exec = 1

(***************************************************************************)
(* Collecting a batch                                                      *)
(***************************************************************************)

\* The outer row that arrives is held.  A read row's key has no more entries than one OID buffer, and it is
\* taken only while the stored OIDs are fewer than one buffer: the array of two buffers always has room.
\* Any row may be held deferred.
AddOuter(k) ==
  /\ phase = "collect" /\ next <= N
  /\ Cardinality(BatchRows) < MaxOuter
  /\ Mutant # "no_close_at_half" => Used < BufCap
  /\ k = "read" => (NumEntries(next) <= BufCap \/ Mutant = "partial_as_complete")
  /\ kind' = [kind EXCEPT ![next] = k]
  /\ valrow' = next
  /\ next' = next + 1
  /\ UNCHANGED <<cfgv, phase, cur, slice, how, todo, out, memo, cached, cval, errs, exec>>

\* The row path for the outer row v whose values are current, with the scan's untaken OIDs s (the row they
\* were read for, 0: none).  Memoize answers a key it holds and the scan is not started; otherwise the scan
\* takes the OIDs it was handed, or reads the index.  A miss may be stored by memoize.
Hit(v) == memo = "on" /\ KeyOf(v) \in cached
SliceM(r) == {i \in Pos : i <= SliceLen(r) /\ <<KeyOf(r), i>> \in pass}
\* @type: (Int, Int) => Set(Int);
Answer(v, s) == IF Hit(v) THEN cval[KeyOf(v)] ELSE IF s # 0 THEN SliceM(s) ELSE Matches(KeyOf(v))
RunRow(v, s) ==
  /\ todo' = Emits(v, Answer(v, s))
  /\ how' = IF Hit(v) THEN "memo" ELSE IF s # 0 THEN "slice" ELSE "scan"
  /\ slice' = IF Hit(v) THEN s ELSE 0
  /\ IF memo = "on" /\ ~Hit(v)
       THEN \/ /\ cached' = cached \cup {KeyOf(v)}
               /\ cval' = [cval EXCEPT ![KeyOf(v)] = Answer(v, s)]
            \/ UNCHANGED <<cached, cval>>
       ELSE UNCHANGED <<cached, cval>>

\* A row that arrives while nothing is held is joined at once: the row path, with whatever the scan holds.
PassRow ==
  /\ phase = "collect" /\ next <= N /\ BatchRows = {}
  /\ phase' = "replay"
  /\ cur' = next /\ valrow' = next
  /\ next' = next + 1
  /\ RunRow(next, slice)
  /\ UNCHANGED <<cfgv, kind, out, memo, errs, exec>>

\* The batch is closed (full, a row that did not fit, the stored rows' bound, the outer scan's end, or earlier:
\* the first batches of a join are small).  The pages of the stored OIDs are named to the OS.
\* (The mutant forgets the rows held when the outer scan ends.)
CloseBatch ==
  /\ phase = "collect" /\ BatchRows # {}
  /\ phase' = IF Mutant = "no_flush" /\ next > N THEN "done" ELSE "replay"
  /\ UNCHANGED <<cfgv, next, kind, cur, valrow, slice, how, todo, out, memo, cached, cval, errs, exec>>

(***************************************************************************)
(* Joining the held rows                                                   *)
(***************************************************************************)

\* The first held row becomes the current outer row again: its values are put back, the inner scan is rewound
\* and handed the row's stored OIDs (none for a deferred row), and the row path runs.
OpenRow ==
  /\ phase = "replay" /\ cur = 0
  /\ \E o \in BatchRows :
       /\ Mutant # "replay_any_order" => \A p \in BatchRows : o <= p
       /\ cur' = o
       /\ LET v == IF Mutant = "no_restore" THEN valrow ELSE o
              s == IF kind[o] = "read" THEN o ELSE IF Mutant = "stale_slice" THEN slice ELSE 0
          IN  /\ valrow' = v
              /\ RunRow(v, s)
  /\ UNCHANGED <<cfgv, phase, next, kind, out, memo, errs, exec>>

\* One join row of the open row is returned, in index order.
EmitOne ==
  /\ phase = "replay" /\ cur # 0
  /\ \E x \in todo :
       /\ \A y \in todo : Rank(x) <= Rank(y)
       /\ todo' = todo \ {x}
       /\ out' = [out EXCEPT ![x] = @ + 1]
  /\ UNCHANGED <<cfgv, phase, next, kind, cur, valrow, slice, how, memo, cached, cval, errs, exec>>

\* The open row is finished.  OIDs it left untaken (memoize answered) are not the next row's.
RowDone ==
  /\ phase = "replay" /\ cur # 0 /\ todo = {}
  /\ kind' = [kind EXCEPT ![cur] = "none"]
  /\ cur' = 0
  /\ how' = "none"
  /\ slice' = IF Mutant = "stale_slice" THEN slice ELSE 0
  /\ UNCHANGED <<cfgv, phase, next, valrow, todo, out, memo, cached, cval, errs, exec>>

EndBatch ==
  /\ phase = "replay" /\ cur = 0 /\ BatchRows = {}
  /\ phase' = IF next > N THEN "done" ELSE "collect"
  /\ UNCHANGED <<cfgv, next, kind, cur, valrow, slice, how, todo, out, memo, cached, cval, errs, exec>>

(***************************************************************************)
(* Environment                                                             *)
(***************************************************************************)

\* Memoize gives up (its hit ratio or its memory bound) and frees what it stored.
MemoDrop ==
  /\ phase \in {"collect", "replay"} /\ memo = "on"
  /\ memo' = "dropped"
  /\ cached' = {}
  /\ cval' = [k \in Keys |-> {}]
  /\ UNCHANGED <<cfgv, phase, next, kind, cur, valrow, slice, how, todo, out, errs, exec>>

\* An error or interrupt ends the execution, or its consumer stops asking (LIMIT): rows may still be held.
Stop ==
  /\ phase \in {"collect", "replay"} /\ errs < MaxErrors
  /\ phase' = "stopped"
  /\ errs' = errs + 1
  /\ UNCHANGED <<cfgv, next, kind, cur, valrow, slice, how, todo, out, memo, cached, cval, exec>>

\* The cached plan runs again: the scans are opened anew and the rows the last execution held are freed.
Restart ==
  /\ phase \in {"done", "stopped"} /\ exec < MaxExec
  /\ exec' = exec + 1
  /\ phase' = "collect"
  /\ next' = 1
  /\ kind' = IF Mutant = "keep_batch" THEN kind ELSE [o \in OuterIds |-> "none"]
  /\ cur' = 0 /\ valrow' = 0 /\ slice' = 0 /\ how' = "none"
  /\ todo' = {}
  /\ out' = [x \in AllItems |-> 0]
  /\ memo' \in {"on", "off"}
  /\ cached' = {}
  /\ cval' = [k \in Keys |-> {}]
  /\ UNCHANGED <<cfgv, errs>>

Terminated == phase \in {"done", "stopped"} /\ UNCHANGED vars

Step == AddOuter("read") \/ AddOuter("defer") \/ PassRow \/ CloseBatch \/ OpenRow \/ EmitOne \/ RowDone
          \/ EndBatch
Next == Step \/ MemoDrop \/ Stop \/ Restart \/ Terminated
Spec == Init /\ [][Next]_vars /\ WF_vars(Step)

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)

\* C8: no join row the row-at-a-time join does not return, and none twice.
NoExtra == \A x \in AllItems : out[x] <= (IF x \in Ref THEN 1 ELSE 0)
\* C8: a join that ran to its end returned every row.
AllReturned == phase = "done" => \A x \in Ref : out[x] = 1
\* C8: a row is returned only after every row before it (outer order, then index order).
InOrder == \A x \in AllItems : \A y \in AllItems :
             (out[x] >= 1 /\ y \in Ref /\ Rank(y) < Rank(x)) => out[y] >= 1
\* The stored OIDs fit the batch's array of two OID buffers.
ArrayBound == Used <= 2 * BufCap
Ends == <>(phase \in {"done", "stopped"})

\* Witnesses
NotMemoHit == how # "memo"
NotSliceTaken == how # "slice"
NotDeferScan == ~(how = "scan" /\ cur # 0 /\ kind[cur] = "defer")
NotPassed == ~(cur # 0 /\ kind[cur] = "none")
NotUntakenSlice == ~(how = "memo" /\ slice # 0)
NotDropHeld == ~(memo = "dropped" /\ how = "scan" /\ cur # 0 /\ kind[cur] = "defer")
NotNullRow == ~(jt = "left" /\ \E o \in OuterIds : out[<<o, 0>>] = 1)
NotFlush == ~(phase = "replay" /\ next > N /\ cur = 0 /\ BatchRows # {})
NotDone == phase # "done"
NotStoppedHeld == ~(phase = "stopped" /\ BatchRows # {})
NotSecondDone == ~(exec = 2 /\ phase = "done")

(***************************************************************************)
(* Inductive invariant                                                     *)
(***************************************************************************)
Live == phase \in {"collect", "replay", "done"}

BatchShape ==
  Live =>
    /\ \A o \in OuterIds : kind[o] # "none" => o < next
    /\ \A o \in OuterIds : \A p \in OuterIds : (kind[o] # "none" /\ o < p /\ p < next) => kind[p] # "none"
    /\ \A o \in OuterIds : kind[o] = "read" => NumEntries(o) <= BufCap
    /\ Cardinality(BatchRows) <= MaxOuter
    /\ Used <= 2 * BufCap
    /\ phase = "collect" => cur = 0
    /\ phase = "done" => (next = N + 1 /\ BatchRows = {} /\ cur = 0)
    /\ cur = 0 => (todo = {} /\ how = "none" /\ slice = 0)
    /\ cur # 0 =>
         /\ phase = "replay" /\ valrow = cur /\ cur < next /\ how # "none"
         /\ kind[cur] # "none" => \A p \in BatchRows : cur <= p
         /\ kind[cur] = "none" => (BatchRows = {} /\ cur = next - 1)
    /\ slice # 0 => (slice = cur /\ kind[cur] = "read" /\ how = "memo")

CacheOk ==
  /\ \A k \in cached : cval[k] = Matches(k)
  /\ memo # "on" => cached = {}

\* What each outer row has given: a finished row everything, a held row nothing, the open row what is not
\* in todo.
RowsGiven ==
  Live => \A x \in AllItems :
    IF x[1] = cur
      THEN /\ out[x] <= 1
           /\ ~(out[x] = 1 /\ x \in todo)
           /\ (out[x] = 1 \/ x \in todo) <=> x \in RefItems(cur)
      ELSE /\ x \notin todo
           /\ out[x] = (IF x[1] < next /\ kind[x[1]] = "none" /\ x \in RefItems(x[1]) THEN 1 ELSE 0)

\* The open row returns its join rows in index order.
RowOrder ==
  Live => \A x \in todo : \A y \in AllItems : (y[1] = cur /\ out[y] >= 1) => Rank(y) < Rank(x)

IndInv ==
  /\ TypeOK
  /\ BatchShape
  /\ CacheOk
  /\ RowsGiven
  /\ RowOrder
  /\ NoExtra
  /\ AllReturned
  /\ InOrder
  /\ ArrayBound
=============================================================================
