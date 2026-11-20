--------------------------- MODULE BatchMemo ---------------------------
(***************************************************************************)
(* A join step that memoizes and holds its rows for its correlated         *)
(* subquery (QEXEC_SQ_BATCH of a step with memoize_storage).               *)
(*                                                                         *)
(* An outer row whose key memoize holds is answered at once: its rows go   *)
(* out without being held.  An outer row whose key memoize does not hold   *)
(* is scanned and its rows are held; the batch closes after the last row   *)
(* of an outer row once it holds Cap rows, or when the outer rows end.     *)
(* When the batch is joined its rows go out in the order they were held    *)
(* and the keys of its outer rows are stored in memoize.                   *)
(*                                                                         *)
(* Before an outer row is looked up in memoize, the rows held are joined   *)
(* first when the batch holds rows of the same key (the key is stored      *)
(* then, and the row is a hit as in the join taken a row at a time) or     *)
(* when memoize already holds the key (its rows would go out ahead of the  *)
(* rows held for earlier outer rows).                                      *)
(*                                                                         *)
(* The claims: (C9) the rows go out in the outer order, each once; (C11)   *)
(* memoize answers exactly the outer rows it answers in the join taken a   *)
(* row at a time (every outer row whose key an earlier outer row had).     *)
(***************************************************************************)
EXTENDS Integers, FiniteSets, Sequences

CONSTANTS N,       \* outer rows
          K,       \* keys
          F,       \* most rows of the step for one outer row
          Cap,     \* rows that close the batch
          Mutant   \* "none" | "no_has_key" | "no_seen" | "no_end"

VARIABLES key, fan,     \* the data: the key of an outer row, the rows of a key
          next,         \* the outer row that arrives next
          held,         \* the rows held, in the order they were held: <<outer row, row>>
          memo,         \* keys memoize holds
          hits,         \* outer rows memoize answered
          emitted, last, badOrder

vars == <<key, fan, next, held, memo, hits, emitted, last, badOrder>>

Outer == 1..N
Rows(o) == {<<o, r>> : r \in 1..fan[key[o]]}
Valid == UNION {Rows(o) : o \in Outer}
HeldKeys == {key[held[i][1]] : i \in 1..Len(held)}
Less(a, b) == a[1] < b[1] \/ (a[1] = b[1] /\ a[2] < b[2])
None == <<0, 0>>
\* the outer rows memoize answers in the join taken a row at a time
RefHits == {o \in Outer : \E p \in 1..(o - 1) : key[p] = key[o]}

Init ==
  /\ key \in [Outer -> 1..K] /\ fan \in [1..K -> 0..F]
  /\ next = 1 /\ held = <<>> /\ memo = {} /\ hits = {}
  /\ emitted = {} /\ last = None /\ badOrder = FALSE

\* rows leave: s is in the order they leave
Out(s) ==
  /\ emitted' = emitted \cup {s[i] : i \in 1..Len(s)}
  /\ last' = IF Len(s) = 0 THEN last ELSE s[Len(s)]
  /\ badOrder' = (badOrder \/ (Len(s) > 0 /\ last /= None /\ ~Less(last, s[1]))
                  \/ (\E i \in 1..Len(s) : s[i] \in emitted))

RowSeq(o) == [r \in 1..fan[key[o]] |-> <<o, r>>]

\* the rows held must be joined before the next outer row is looked up
MustJoin ==
  /\ next <= N /\ Len(held) > 0
  /\ \/ (Mutant /= "no_seen" /\ key[next] \in HeldKeys)
     \/ (Mutant /= "no_has_key" /\ key[next] \in memo)

Full == Len(held) >= Cap

\* the batch is joined: its rows leave in the order held, the keys of its outer rows are stored
Join ==
  /\ Len(held) > 0
  /\ MustJoin \/ Full \/ (next > N /\ Mutant /= "no_end")
  /\ Out(held)
  /\ memo' = memo \cup HeldKeys
  /\ held' = <<>>
  /\ UNCHANGED <<key, fan, next, hits>>

\* memoize answers the outer row: its rows leave at once
Hit ==
  /\ next <= N /\ ~MustJoin /\ ~Full /\ key[next] \in memo
  /\ Out(RowSeq(next))
  /\ hits' = hits \cup {next}
  /\ next' = next + 1
  /\ UNCHANGED <<key, fan, held, memo>>

\* the outer row is scanned: its rows are held; a row with none stores its key when the batch is joined, as its
\* key is among the batch's then.  (A row with no row is held as a row of its own in the code: a key with none.)
Miss ==
  /\ next <= N /\ ~MustJoin /\ ~Full /\ key[next] \notin memo
  /\ IF fan[key[next]] = 0
       THEN /\ memo' = memo \cup {key[next]} /\ held' = held
       ELSE /\ held' = held \o RowSeq(next) /\ memo' = memo
  /\ next' = next + 1
  /\ UNCHANGED <<key, fan, hits, emitted, last, badOrder>>

Done == next > N /\ (Len(held) = 0 \/ Mutant = "no_end")
Finished == Done /\ UNCHANGED vars

Next == Join \/ Hit \/ Miss \/ Finished
Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

TypeOK ==
  /\ key \in [Outer -> 1..K] /\ fan \in [1..K -> 0..F]
  /\ next \in 1..(N + 1)
  /\ held \in Seq(Outer \X (1..F)) /\ Len(held) <= Cap + F
  /\ memo \subseteq 1..K /\ hits \subseteq Outer
  /\ emitted \subseteq (Outer \X (1..F)) /\ badOrder \in BOOLEAN

NoExtra == emitted \subseteq Valid
InOrder == ~badOrder
AllReturned == Done => emitted = Valid
SameHits == Done => hits = RefHits
\* a key is stored only when all the rows of its outer row have left or are leaving
HeldInOrder == \A i, j \in 1..Len(held) : i < j => Less(held[i], held[j])

\* witnesses
NotHitBehindHeld == ~(Len(held) > 0 /\ next <= N /\ key[next] \in memo /\ key[next] \notin HeldKeys)
NotSameKeyHeld == ~(Len(held) > 0 /\ next <= N /\ key[next] \in HeldKeys)
NotDone == ~(Done /\ emitted /= {} /\ hits /= {})
=============================================================================
