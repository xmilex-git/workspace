--------------------------- MODULE BatchChain ---------------------------
(***************************************************************************)
(* Two batched lookup levels under one first scan (nl_join_batch): what a  *)
(* level's batch must hold so that it may stay open while the level above  *)
(* moves to its next row.  One level in full is BatchJoin; here a level is *)
(* only "hold rows, close, replay them in order".                          *)
(*                                                                         *)
(* Level 0 is the first scan: it reads root rows 1..N0.  Level 1 holds     *)
(* root rows; when its batch closes it replays them: the root value goes   *)
(* back into the first scan's value list (reg0) and the level's scan       *)
(* returns the row's children, each one into its own value list (reg1).    *)
(* Level 2 holds the rows level 1 hands down; when its batch closes it     *)
(* replays them and each returns its matches.  Level 2 is a join step, or  *)
(* the index lookup of a correlated subquery of level 1's row: both are    *)
(* "something that runs once per row of level 1 and reads the value lists  *)
(* above it".                                                              *)
(*                                                                         *)
(* A replay of level 2 runs in the middle of level 1's replay.  What it    *)
(* writes into reg0 is what level 1's scan reads for its next child.       *)
(*                                                                         *)
(* The claim (C8, for a chain): the statement returns the same rows, the   *)
(* same number of times and in the same order as with no batch.            *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS N0,        \* root rows
          F1,        \* most children of a root row
          M2,        \* most matches of a (root, child) row
          Cap1,      \* rows that close the batch of level 1
          Cap2,      \* rows that close the batch of level 2
          UpperEnd,  \* TRUE: level 2 closes when the children of level 1's current row end
          Prefix,    \* TRUE: a row held by level 2 carries the root value too (every value list above it)
          Restore,   \* what the value lists above hold when a replay of level 2 ends: "saved" (what they held when
                     \* the batch closed, put back) | "last" (the last replayed row)
          Mutant     \* "none" | "bottom_up" | "late_close"

VARIABLES fan, mat,              \* the data: children of a root, matches of a (root, child)
          next0,                 \* the next root row of the first scan
          b1, n1, ph1, i1, c1,   \* level 1: held roots, their number, phase, row replayed, its next child (0: not open)
          b2r, b2c, g2r, n2,     \* level 2: held root value (0 when not held), child, the root it really is (ghost)
          ph2, i2, m2,           \*          phase, row replayed, its next match (0: not open)
          endFlushed2,           \* level 2 closed after the first scan ended
          reg0, reg1,            \* the value lists of the first scan and of level 1
          sv0, sv1,              \* what they held when the batch of level 2 closed
          emitted, last, badOrder

vars == <<fan, mat, next0, b1, n1, ph1, i1, c1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg0, reg1,
          sv0, sv1, emitted, last, badOrder>>

Roots == 1..N0
Kids == 1..F1
Valid == {t \in Roots \X Kids \X (1..M2) : t[2] <= fan[t[1]] /\ t[3] <= mat[<<t[1], t[2]>>]}
Less(a, b) == \/ a[1] < b[1]
              \/ a[1] = b[1] /\ a[2] < b[2]
              \/ a[1] = b[1] /\ a[2] = b[2] /\ a[3] < b[3]
None == <<0, 0, 0>>

Init ==
  /\ fan \in [Roots -> 0..F1]
  /\ mat \in [Roots \X Kids -> 0..M2]
  /\ \A r \in Roots, c \in Kids : c > fan[r] => mat[<<r, c>>] = 0
  /\ next0 = 1
  /\ b1 = [k \in 1..Cap1 |-> 0] /\ n1 = 0 /\ ph1 = "collect" /\ i1 = 0 /\ c1 = 0
  /\ b2r = [k \in 1..Cap2 |-> 0] /\ b2c = [k \in 1..Cap2 |-> 0] /\ g2r = [k \in 1..Cap2 |-> 0] /\ n2 = 0
  /\ ph2 = "collect" /\ i2 = 0 /\ m2 = 0 /\ endFlushed2 = FALSE
  /\ reg0 = 0 /\ reg1 = 0 /\ sv0 = 0 /\ sv1 = 0
  /\ emitted = {} /\ last = None /\ badOrder = FALSE

Quiet == ph1 = "collect" /\ ph2 = "collect"
\* a batch that is full closes in the call that added its last row: nothing above moves first ("late_close": it may)
Full2 == Mutant /= "late_close" /\ ph2 = "collect" /\ n2 = Cap2
Row1Ended == ph1 = "replay" /\ c1 >= 1 /\ c1 > fan[b1[i1]]

\* the first scan reads a row; level 1 holds it
ReadRoot ==
  /\ Quiet /\ ~Full2 /\ next0 <= N0 /\ n1 < Cap1
  /\ reg0' = next0
  /\ b1' = [b1 EXCEPT ![n1 + 1] = next0]
  /\ n1' = n1 + 1 /\ next0' = next0 + 1
  /\ UNCHANGED <<fan, mat, ph1, i1, c1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg1, sv0, sv1, emitted, last, badOrder>>

Close1 ==
  /\ Quiet /\ ~Full2 /\ n1 > 0 /\ (n1 = Cap1 \/ next0 > N0)
  /\ ph1' = "replay" /\ i1' = 1 /\ c1' = 0
  /\ UNCHANGED <<fan, mat, next0, b1, n1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg0, reg1, sv0, sv1, emitted, last, badOrder>>

\* a held root becomes the current row of the first scan again
Open1 ==
  /\ ph1 = "replay" /\ ph2 = "collect" /\ ~Full2 /\ c1 = 0 /\ i1 <= n1
  /\ reg0' = b1[i1] /\ c1' = 1
  /\ UNCHANGED <<fan, mat, next0, b1, n1, ph1, i1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg1, sv0, sv1, emitted, last, badOrder>>

\* level 1's scan returns a child; level 2 holds the row: the child, and with Prefix what the first scan's
\* value list holds now
Fetch1 ==
  /\ ph1 = "replay" /\ ph2 = "collect" /\ c1 >= 1 /\ c1 <= fan[b1[i1]] /\ n2 < Cap2
  /\ reg1' = c1
  /\ b2r' = [b2r EXCEPT ![n2 + 1] = IF Prefix THEN reg0 ELSE 0]
  /\ b2c' = [b2c EXCEPT ![n2 + 1] = c1]
  /\ g2r' = [g2r EXCEPT ![n2 + 1] = b1[i1]]
  /\ n2' = n2 + 1 /\ c1' = c1 + 1
  /\ UNCHANGED <<fan, mat, next0, b1, n1, ph1, i1, ph2, i2, m2, endFlushed2, reg0, sv0, sv1, emitted, last, badOrder>>

End1Row ==
  /\ Row1Ended /\ ph2 = "collect" /\ ~Full2 /\ (UpperEnd => n2 = 0)
  /\ i1' = i1 + 1 /\ c1' = 0
  /\ UNCHANGED <<fan, mat, next0, b1, n1, ph1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg0, reg1, sv0, sv1, emitted, last, badOrder>>

End1Batch ==
  /\ ph1 = "replay" /\ ph2 = "collect" /\ ~Full2 /\ c1 = 0 /\ i1 > n1
  /\ b1' = [k \in 1..Cap1 |-> 0] /\ n1' = 0 /\ ph1' = "collect" /\ i1' = 0
  /\ UNCHANGED <<fan, mat, next0, c1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg0, reg1, sv0, sv1, emitted, last, badOrder>>

\* level 2 closes: its batch is full, or (UpperEnd) level 1's row has no more children, or the first scan ended
\* and nothing above still holds rows.  "bottom_up": at the end of the first scan level 2 is emptied once,
\* whatever level 1 still holds
Close2 ==
  /\ ph2 = "collect" /\ n2 > 0
  /\ \/ n2 = Cap2
     \/ UpperEnd /\ Row1Ended
     \/ IF Mutant = "bottom_up" THEN next0 > N0 /\ ~endFlushed2 /\ (ph1 = "collect" \/ c1 = 0)
                                ELSE next0 > N0 /\ n1 = 0 /\ ph1 = "collect"
  /\ ph2' = "replay" /\ i2' = 1 /\ m2' = 0
  /\ endFlushed2' = (endFlushed2 \/ next0 > N0)
  /\ sv0' = reg0 /\ sv1' = reg1
  /\ UNCHANGED <<fan, mat, next0, b1, n1, ph1, i1, c1, b2r, b2c, g2r, n2, reg0, reg1, emitted, last, badOrder>>

\* a held row becomes the current row again: the child, and with Prefix the root
Open2 ==
  /\ ph2 = "replay" /\ m2 = 0 /\ i2 <= n2
  /\ reg1' = b2c[i2]
  /\ reg0' = IF Prefix THEN b2r[i2] ELSE reg0
  /\ m2' = 1
  /\ UNCHANGED <<fan, mat, next0, b1, n1, ph1, i1, c1, b2r, b2c, g2r, n2, ph2, i2, endFlushed2, sv0, sv1, emitted, last, badOrder>>

\* the row path returns a match of the row; the output reads the value lists
Emit2 ==
  /\ ph2 = "replay" /\ m2 >= 1 /\ m2 <= mat[<<g2r[i2], b2c[i2]>>]
  /\ LET t == <<reg0, reg1, m2>> IN
       /\ emitted' = emitted \cup {t}
       /\ badOrder' = (badOrder \/ ~Less(last, t))
       /\ last' = t
  /\ m2' = m2 + 1
  /\ UNCHANGED <<fan, mat, next0, b1, n1, ph1, i1, c1, b2r, b2c, g2r, n2, ph2, i2, endFlushed2, reg0, reg1, sv0, sv1>>

End2Row ==
  /\ ph2 = "replay" /\ m2 >= 1 /\ m2 > mat[<<g2r[i2], b2c[i2]>>]
  /\ i2' = i2 + 1 /\ m2' = 0
  /\ UNCHANGED <<fan, mat, next0, b1, n1, ph1, i1, c1, b2r, b2c, g2r, n2, ph2, endFlushed2, reg0, reg1, sv0, sv1, emitted, last, badOrder>>

End2Batch ==
  /\ ph2 = "replay" /\ m2 = 0 /\ i2 > n2
  /\ b2r' = [k \in 1..Cap2 |-> 0] /\ b2c' = [k \in 1..Cap2 |-> 0] /\ g2r' = [k \in 1..Cap2 |-> 0]
  /\ n2' = 0 /\ ph2' = "collect" /\ i2' = 0
  /\ reg0' = IF Restore = "saved" /\ Prefix THEN sv0 ELSE reg0
  /\ reg1' = IF Restore = "saved" THEN sv1 ELSE reg1
  /\ UNCHANGED <<fan, mat, next0, b1, n1, ph1, i1, c1, m2, endFlushed2, sv0, sv1, emitted, last, badOrder>>

Done == Quiet /\ next0 > N0 /\ n1 = 0 /\ (n2 = 0 \/ (Mutant = "bottom_up" /\ endFlushed2 /\ n2 < Cap2))

Finished == Done /\ UNCHANGED vars

Next == ReadRoot \/ Close1 \/ Open1 \/ Fetch1 \/ End1Row \/ End1Batch \/ Close2 \/ Open2 \/ Emit2 \/ End2Row
        \/ End2Batch \/ Finished

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

TypeOK ==
  /\ fan \in [Roots -> 0..F1] /\ mat \in [Roots \X Kids -> 0..M2]
  /\ next0 \in 1..(N0 + 1)
  /\ b1 \in [1..Cap1 -> 0..N0] /\ n1 \in 0..Cap1 /\ ph1 \in {"collect", "replay"} /\ i1 \in 0..(Cap1 + 1)
  /\ c1 \in 0..(F1 + 1)
  /\ b2r \in [1..Cap2 -> 0..N0] /\ b2c \in [1..Cap2 -> 0..F1] /\ g2r \in [1..Cap2 -> 0..N0] /\ n2 \in 0..Cap2
  /\ ph2 \in {"collect", "replay"} /\ i2 \in 0..(Cap2 + 1) /\ m2 \in 0..(M2 + 1)
  /\ endFlushed2 \in BOOLEAN /\ reg0 \in 0..N0 /\ reg1 \in 0..F1 /\ sv0 \in 0..N0 /\ sv1 \in 0..F1
  /\ emitted \subseteq ((0..N0) \X (0..F1) \X (1..M2)) /\ last \in ((0..N0) \X (0..F1) \X (0..M2))
  /\ badOrder \in BOOLEAN

NoExtra == emitted \subseteq Valid
InOrder == ~badOrder
AllReturned == Done => emitted = Valid
ArrayBound == n1 <= Cap1 /\ n2 <= Cap2
Terminates == <>Done

\* with UpperEnd a batch of level 2 never holds more than the children of one row of level 1
FanBound == n2 <= F1

\* witnesses
NotSpan == ~(\E i, j \in 1..n2 : g2r[i] /= g2r[j])
NotNested == ~(ph2 = "replay" /\ ph1 = "replay" /\ c1 >= 1 /\ c1 <= fan[b1[i1]])
NotDone == ~(Done /\ emitted /= {})
=============================================================================
