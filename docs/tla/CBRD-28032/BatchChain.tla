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
(* The claim (C9, for a chain): the statement returns the same rows, the   *)
(* same number of times and in the same order as with no batch.            *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS N0,        \* root rows
          F1,        \* most children of a root row
          M2,        \* most matches of a (root, child) row
          Cap1,      \* rows that close the batch of level 1
          Cap2,      \* rows that close the batch of level 2
          UpperEnd,  \* TRUE: level 2 closes when the children of level 1's current row end
          BatchEnd,  \* TRUE: level 2 closes when level 1 has replayed the last row of its batch
          Pass1,     \* TRUE: level 1 may let a root row through without holding it (its scan is not read ahead, or
                     \* it backed off), whenever it holds none: the end of that row closes nothing below
          Prefix,    \* TRUE: a row held by level 2 carries the root value too (every value list above it)
          Restore,   \* what the value lists above hold when a replay of level 2 ends: "saved" (what they held when
                     \* the batch closed, put back) | "last" (the last replayed row)
          Kind,      \* level 2 is an "inner" join step (or a subquery lookup: every match), a "semi" join step (the
                     \* first match) or an "anti" join step (the row once, when it has no match)
          Win,       \* rows of a batch of level 2 whose pages may be named to the OS and not yet looked up
          MaxErrors, \* errors, interrupts and early stops in a run
          Mutant     \* "none" | "bottom_up" | "late_close" | "name_all" | "keep_on_error" | "pass_no_end" | "pass_drain"

VARIABLES pr,                    \* the root row passing through level 1 unheld (0: none)
          g2p,                   \* level 2: the held row came through such a pass (ghost)
          fan, mat,              \* the data: children of a root, matches of a (root, child)
          next0,                 \* the next root row of the first scan
          b1, n1, ph1, i1, c1,   \* level 1: held roots, their number, phase, row replayed, its next child (0: not open)
          b2r, b2c, g2r, n2,     \* level 2: held root value (0 when not held), child, the root it really is (ghost)
          ph2, i2, m2,           \*          phase, row replayed, its next match (0: not open)
          endFlushed2,           \* level 2 closed after the first scan ended
          reg0, reg1,            \* the value lists of the first scan and of level 1
          sv0, sv1,              \* what they held when the batch of level 2 closed
          named,                 \* rows of level 2's batch whose pages were named to the OS
          errs, stopped,         \* errors so far; the statement stopped on one
          emitted, last, badOrder

vars == <<pr, g2p, fan, mat, next0, b1, n1, ph1, i1, c1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg0, reg1,
          sv0, sv1, named, errs, stopped, emitted, last, badOrder>>

Roots == 1..N0
Kids == 1..F1
Valid == CASE Kind = "inner" -> {t \in Roots \X Kids \X (1..M2) : t[2] <= fan[t[1]] /\ t[3] <= mat[<<t[1], t[2]>>]}
           [] Kind = "semi" -> {t \in Roots \X Kids \X {1} : t[2] <= fan[t[1]] /\ mat[<<t[1], t[2]>>] >= 1}
           [] OTHER -> {t \in Roots \X Kids \X {0} : t[2] <= fan[t[1]] /\ mat[<<t[1], t[2]>>] = 0}
Min(a, b) == IF a < b THEN a ELSE b
Max(a, b) == IF a > b THEN a ELSE b
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
  /\ pr = 0 /\ g2p = [k \in 1..Cap2 |-> FALSE]
  /\ b2r = [k \in 1..Cap2 |-> 0] /\ b2c = [k \in 1..Cap2 |-> 0] /\ g2r = [k \in 1..Cap2 |-> 0] /\ n2 = 0
  /\ ph2 = "collect" /\ i2 = 0 /\ m2 = 0 /\ endFlushed2 = FALSE
  /\ reg0 = 0 /\ reg1 = 0 /\ sv0 = 0 /\ sv1 = 0
  /\ named = 0 /\ errs = 0 /\ stopped = FALSE
  /\ emitted = {} /\ last = None /\ badOrder = FALSE

Quiet == ph1 = "collect" /\ ph2 = "collect"
\* a batch that is full closes in the call that added its last row: nothing above moves first ("late_close": it may)
Full2 == Mutant /= "late_close" /\ ph2 = "collect" /\ n2 = Cap2
CurRoot == IF pr > 0 THEN pr ELSE b1[i1]
Row1Ended == ph1 = "replay" /\ c1 >= 1 /\ c1 > fan[CurRoot]

\* the first scan reads a row; level 1 holds it
ReadRoot ==
  /\ Quiet /\ ~Full2 /\ next0 <= N0 /\ n1 < Cap1
  /\ reg0' = next0
  /\ b1' = [b1 EXCEPT ![n1 + 1] = next0]
  /\ n1' = n1 + 1 /\ next0' = next0 + 1
  /\ UNCHANGED <<pr, g2p, fan, mat, ph1, i1, c1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg1, sv0, sv1, emitted, last, badOrder, named, errs, stopped>>

\* the first scan reads a row and level 1 lets it through without holding it (level 1 holds none): the row is
\* inside level 1's row path at once
PassRoot ==
  /\ Pass1 /\ Quiet /\ ~Full2 /\ next0 <= N0 /\ n1 = 0
  /\ reg0' = next0 /\ pr' = next0 /\ next0' = next0 + 1
  /\ ph1' = "replay" /\ c1' = 1
  /\ UNCHANGED <<g2p, fan, mat, b1, n1, i1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg1, sv0, sv1, emitted, last, badOrder, named, errs, stopped>>

\* the row that passed has no more children: level 1 returns the end of its outer row and ends nothing below
\* ("pass_drain": the batch of level 2 is joined first, as when level 1 ended a batch of its own)
PassEnd ==
  /\ Row1Ended /\ pr > 0 /\ ph2 = "collect" /\ ~Full2 /\ (UpperEnd \/ Mutant = "pass_drain" => n2 = 0)
  /\ pr' = 0 /\ ph1' = "collect" /\ c1' = 0
  /\ UNCHANGED <<g2p, fan, mat, next0, b1, n1, i1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg0, reg1, sv0, sv1, emitted, last, badOrder, named, errs, stopped>>

Close1 ==
  /\ Quiet /\ ~Full2 /\ n1 > 0 /\ (n1 = Cap1 \/ next0 > N0)
  /\ ph1' = "replay" /\ i1' = 1 /\ c1' = 0
  /\ UNCHANGED <<pr, g2p, fan, mat, next0, b1, n1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg0, reg1, sv0, sv1, emitted, last, badOrder, named, errs, stopped>>

\* a held root becomes the current row of the first scan again
Open1 ==
  /\ ph1 = "replay" /\ pr = 0 /\ ph2 = "collect" /\ ~Full2 /\ c1 = 0 /\ i1 <= n1
  /\ reg0' = b1[i1] /\ c1' = 1
  /\ UNCHANGED <<pr, g2p, fan, mat, next0, b1, n1, ph1, i1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg1, sv0, sv1, emitted, last, badOrder, named, errs, stopped>>

\* level 1's scan returns a child; level 2 holds the row: the child, and with Prefix what the first scan's
\* value list holds now
Fetch1 ==
  /\ ph1 = "replay" /\ ph2 = "collect" /\ c1 >= 1 /\ c1 <= fan[CurRoot] /\ n2 < Cap2
  /\ reg1' = c1
  /\ b2r' = [b2r EXCEPT ![n2 + 1] = IF Prefix THEN reg0 ELSE 0]
  /\ b2c' = [b2c EXCEPT ![n2 + 1] = c1]
  /\ g2r' = [g2r EXCEPT ![n2 + 1] = CurRoot]
  /\ g2p' = [g2p EXCEPT ![n2 + 1] = (pr > 0)]
  /\ n2' = n2 + 1 /\ c1' = c1 + 1
  /\ UNCHANGED <<pr, fan, mat, next0, b1, n1, ph1, i1, ph2, i2, m2, endFlushed2, reg0, sv0, sv1, emitted, last, badOrder, named, errs, stopped>>

End1Row ==
  /\ Row1Ended /\ pr = 0 /\ ph2 = "collect" /\ ~Full2 /\ (UpperEnd => n2 = 0)
  /\ i1' = i1 + 1 /\ c1' = 0
  /\ UNCHANGED <<pr, g2p, fan, mat, next0, b1, n1, ph1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg0, reg1, sv0, sv1, emitted, last, badOrder, named, errs, stopped>>

End1Batch ==
  /\ ph1 = "replay" /\ ph2 = "collect" /\ ~Full2 /\ pr = 0 /\ c1 = 0 /\ i1 > n1 /\ (BatchEnd => n2 = 0)
  /\ b1' = [k \in 1..Cap1 |-> 0] /\ n1' = 0 /\ ph1' = "collect" /\ i1' = 0
  /\ UNCHANGED <<pr, g2p, fan, mat, next0, c1, b2r, b2c, g2r, n2, ph2, i2, m2, endFlushed2, reg0, reg1, sv0, sv1, emitted, last, badOrder, named, errs, stopped>>

\* level 2 closes: its batch is full, or (UpperEnd) level 1's row has no more children, or the first scan ended
\* and nothing above still holds rows.  "bottom_up": at the end of the first scan level 2 is emptied once,
\* whatever level 1 still holds
Close2 ==
  /\ ph2 = "collect" /\ n2 > 0
  /\ \/ n2 = Cap2
     \/ UpperEnd /\ Row1Ended
     \/ BatchEnd /\ ph1 = "replay" /\ pr = 0 /\ c1 = 0 /\ i1 > n1
     \/ Mutant = "pass_drain" /\ pr > 0 /\ Row1Ended
     \/ IF Mutant = "bottom_up" THEN next0 > N0 /\ ~endFlushed2 /\ (ph1 = "collect" \/ c1 = 0)
                                ELSE Mutant /= "pass_no_end" /\ next0 > N0 /\ n1 = 0 /\ ph1 = "collect"
  /\ ph2' = "replay" /\ i2' = 1 /\ m2' = 0
  /\ endFlushed2' = (endFlushed2 \/ next0 > N0)
  /\ sv0' = reg0 /\ sv1' = reg1
  \* the first window is named when the batch closes ("name_all": the whole batch)
  /\ named' = IF Mutant = "name_all" THEN n2 ELSE Min(n2, Win)
  /\ UNCHANGED <<pr, g2p, fan, mat, next0, b1, n1, ph1, i1, c1, b2r, b2c, g2r, n2, reg0, reg1, emitted, last, badOrder, errs, stopped>>

\* a held row becomes the current row again: the child, and with Prefix the root
Open2 ==
  /\ ph2 = "replay" /\ m2 = 0 /\ i2 <= n2
  /\ reg1' = b2c[i2]
  /\ reg0' = IF Prefix THEN b2r[i2] ELSE reg0
  /\ m2' = 1
  \* the window moves with the lookups
  /\ named' = Max(named, Min(n2, i2 - 1 + Win))
  /\ UNCHANGED <<pr, g2p, fan, mat, next0, b1, n1, ph1, i1, c1, b2r, b2c, g2r, n2, ph2, i2, endFlushed2, sv0, sv1, emitted, last, badOrder, errs, stopped>>

\* the row path returns a match of the row; the output reads the value lists
Emit2 ==
  /\ ph2 = "replay" /\ m2 >= 1
  /\ CASE Kind = "inner" -> m2 <= mat[<<g2r[i2], b2c[i2]>>]
       [] Kind = "semi" -> m2 = 1 /\ mat[<<g2r[i2], b2c[i2]>>] >= 1
       [] OTHER -> m2 = 1 /\ mat[<<g2r[i2], b2c[i2]>>] = 0
  /\ LET t == <<reg0, reg1, IF Kind = "anti" THEN 0 ELSE m2>> IN
       /\ emitted' = emitted \cup {t}
       /\ badOrder' = (badOrder \/ ~Less(last, t))
       /\ last' = t
  /\ m2' = m2 + 1
  /\ UNCHANGED <<pr, g2p, fan, mat, next0, b1, n1, ph1, i1, c1, b2r, b2c, g2r, n2, ph2, i2, endFlushed2, reg0, reg1, sv0, sv1, named, errs, stopped>>

End2Row ==
  /\ ph2 = "replay" /\ m2 >= 1
  /\ CASE Kind = "inner" -> m2 > mat[<<g2r[i2], b2c[i2]>>]
       [] Kind = "semi" -> m2 = 2 \/ mat[<<g2r[i2], b2c[i2]>>] = 0
       [] OTHER -> m2 = 2 \/ mat[<<g2r[i2], b2c[i2]>>] >= 1
  /\ i2' = i2 + 1 /\ m2' = 0
  /\ UNCHANGED <<pr, g2p, fan, mat, next0, b1, n1, ph1, i1, c1, b2r, b2c, g2r, n2, ph2, endFlushed2, reg0, reg1, sv0, sv1, emitted, last, badOrder, named, errs, stopped>>

End2Batch ==
  /\ ph2 = "replay" /\ m2 = 0 /\ i2 > n2
  /\ b2r' = [k \in 1..Cap2 |-> 0] /\ b2c' = [k \in 1..Cap2 |-> 0] /\ g2r' = [k \in 1..Cap2 |-> 0]
  /\ g2p' = [k \in 1..Cap2 |-> FALSE]
  /\ n2' = 0 /\ ph2' = "collect" /\ i2' = 0 /\ named' = 0
  /\ reg0' = IF Restore = "saved" /\ Prefix THEN sv0 ELSE reg0
  /\ reg1' = IF Restore = "saved" THEN sv1 ELSE reg1
  /\ UNCHANGED <<pr, fan, mat, next0, b1, n1, ph1, i1, c1, m2, endFlushed2, sv0, sv1, emitted, last, badOrder, errs, stopped>>

\* an error, an interrupt or an early stop anywhere: the statement ends and every batch forgets its rows
\* ("keep_on_error": they stay for the next execution of the cached plan)
Abort ==
  /\ ~stopped /\ errs < MaxErrors
  /\ errs' = errs + 1 /\ stopped' = TRUE
  /\ IF Mutant = "keep_on_error"
       THEN UNCHANGED <<pr, g2p, b1, n1, ph1, i1, c1, b2r, b2c, g2r, n2, ph2, i2, m2, named>>
       ELSE /\ b1' = [k \in 1..Cap1 |-> 0] /\ n1' = 0 /\ ph1' = "collect" /\ i1' = 0 /\ c1' = 0
            /\ b2r' = [k \in 1..Cap2 |-> 0] /\ b2c' = [k \in 1..Cap2 |-> 0] /\ g2r' = [k \in 1..Cap2 |-> 0]
            /\ n2' = 0 /\ ph2' = "collect" /\ i2' = 0 /\ m2' = 0 /\ named' = 0
            /\ pr' = 0 /\ g2p' = [k \in 1..Cap2 |-> FALSE]
  /\ UNCHANGED <<fan, mat, next0, endFlushed2, reg0, reg1, sv0, sv1, emitted, last, badOrder>>

Done == \/ stopped
        \/ Quiet /\ next0 > N0 /\ n1 = 0 /\ (n2 = 0 \/ (Mutant = "bottom_up" /\ endFlushed2 /\ n2 < Cap2))

Finished == Done /\ UNCHANGED vars

Step == ReadRoot \/ PassRoot \/ PassEnd \/ Close1 \/ Open1 \/ Fetch1 \/ End1Row \/ End1Batch \/ Close2 \/ Open2 \/ Emit2 \/ End2Row
        \/ End2Batch

Next == (~stopped /\ Step) \/ Abort \/ Finished

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

TypeOK ==
  /\ pr \in 0..N0 /\ g2p \in [1..Cap2 -> BOOLEAN]
  /\ fan \in [Roots -> 0..F1] /\ mat \in [Roots \X Kids -> 0..M2]
  /\ next0 \in 1..(N0 + 1)
  /\ b1 \in [1..Cap1 -> 0..N0] /\ n1 \in 0..Cap1 /\ ph1 \in {"collect", "replay"} /\ i1 \in 0..(Cap1 + 1)
  /\ c1 \in 0..(F1 + 1)
  /\ b2r \in [1..Cap2 -> 0..N0] /\ b2c \in [1..Cap2 -> 0..F1] /\ g2r \in [1..Cap2 -> 0..N0] /\ n2 \in 0..Cap2
  /\ ph2 \in {"collect", "replay"} /\ i2 \in 0..(Cap2 + 1) /\ m2 \in 0..(M2 + 1)
  /\ endFlushed2 \in BOOLEAN /\ reg0 \in 0..N0 /\ reg1 \in 0..F1 /\ sv0 \in 0..N0 /\ sv1 \in 0..F1
  /\ emitted \subseteq ((0..N0) \X (0..F1) \X (0..M2)) /\ last \in ((0..N0) \X (0..F1) \X (0..M2))
  /\ badOrder \in BOOLEAN
  /\ named \in 0..Cap2 /\ errs \in 0..MaxErrors /\ stopped \in BOOLEAN

NoExtra == emitted \subseteq Valid
InOrder == ~badOrder
AllReturned == (Done /\ ~stopped) => emitted = Valid
\* pages named to the OS and not yet looked up stay within the window
WinBound == ph2 = "replay" => named - (i2 - 1) <= Win
\* a statement that ended holds no row: the plan is cached and runs again
NoneHeld == stopped => (n1 = 0 /\ n2 = 0)
ArrayBound == n1 <= Cap1 /\ n2 <= Cap2
Terminates == <>Done

\* with UpperEnd a batch of level 2 never holds more than the children of one row of level 1
FanBound == n2 <= F1

\* witnesses
NotSpan == ~(\E i, j \in 1..n2 : g2r[i] /= g2r[j])
NotNested == ~(ph2 = "replay" /\ ph1 = "replay" /\ c1 >= 1 /\ c1 <= fan[CurRoot])
\* level 2 holds rows of two root rows that both went through level 1 unheld, while level 1 holds nothing
NotPassSpan == ~(n1 = 0 /\ \E i, j \in 1..n2 : g2r[i] /= g2r[j] /\ g2p[i] /\ g2p[j])
\* a held batch of level 1 ended while level 2 held rows that came through a pass before it
NotPassThenHeld == ~(\E i, j \in 1..n2 : g2p[i] /\ ~g2p[j])
NotDone == ~(Done /\ ~stopped /\ emitted /= {})
NotStoppedHeld == ~(stopped /\ emitted /= {})
NotSecondWindow == ~(ph2 = "replay" /\ named > Win)
=============================================================================
