----------------------------- MODULE NlMemoKey -----------------------------
(* CBRD-27993: the memo of an NL inner x, between an outer scan o and a later scan y
   (o -> x -> y, one thread). The memo maps a key to the x rows one probe produced; a later
   outer row with the same key replays them instead of scanning x.

   Code (develop 2dac6ecc2):
   - memoize.cpp storage::get        probe: reads the key slots once (m_last_key), looks it up
   - memoize.cpp storage::put        one entry per x row; reads the key slots again (get_key)
   - memoize.cpp storage::put_nullptr "no row" entry when the probe produced none
   - memoize.cpp can_insert / stop_insert   budget: stop inserting, drop the current key's entries;
                                     hit ratio: disable (the executor frees the storage)
   - query_executor.c qexec_execute_scan    x row -> memoize_put -> scan_ptr (y) for that row

   One x row is one step (put, emit, run y for it): one thread runs the whole NL chain, so no
   other step can fall between them. y is modeled only by what it leaves in its val_list slot
   (ys), the value a key slot pointing into y's val_list reads.

   The NL chain may sit in a correlated subquery: ev is the enclosing query's value it reads, and
   NewExec is the next execution of the subquery, which builds a new storage
   (query_executor.c qexec_execute_mainblock_internal -> new_memoize_storage at scan open).

   Open decisions are constants: PutKey (put reads the slots again, or reuses the probe key;
   decided "reread", round 2), EncKey (the enclosing value is a key slot; decided FALSE, round 3),
   SvGuard (no memo when the inner's terms read a session variable, assigned or not; decided TRUE,
   rounds 5-6). SessAssign: the inner's terms read the session variable sv and the select list
   assigns it (`@v := @v + 1`), so sv changes between outer rows (environment, no fairness).
   SessAssign = FALSE cfgs stand for inners that read no session variable: the decided check
   refuses every inner that reads one, so a read without an assignment needs no cfg of its own. Mutant re-enables one
   known-wrong key or rule. *)
EXTENDS Naturals, FiniteSets

CONSTANTS NO, NX, NV, NY, NE, NEX, PutKey, EncKey, SessAssign, SvGuard, Mutant
ASSUME Assm == /\ NO \in Nat \ {0} /\ NX \in Nat \ {0} /\ NV \in Nat \ {0} /\ NY \in Nat \ {0}
               /\ NE \in Nat \ {0} /\ NEX \in Nat \ {0}
               /\ PutKey \in {"reread", "probe"} /\ EncKey \in BOOLEAN
               /\ SessAssign \in BOOLEAN /\ SvGuard \in BOOLEAN
               /\ Mutant \in {"none", "key_has_later", "key_missing_outer", "stop_keeps_partial", "storage_kept"}

\* apalache-type: NO Int
\* apalache-type: NX Int
\* apalache-type: NV Int
\* apalache-type: NY Int
\* apalache-type: NE Int
\* apalache-type: NEX Int
\* apalache-type: PutKey Str
\* apalache-type: EncKey Bool
\* apalache-type: SessAssign Bool
\* apalache-type: SvGuard Bool
\* apalache-type: xv Int -> Int
\* apalache-type: sv Int
\* apalache-type: sva Int -> Int
\* apalache-type: Mutant Str
\* apalache-type: os Int -> Int
\* apalache-type: xk Int -> Int
\* apalache-type: yl Int -> Int
\* apalache-type: xe Int -> Int
\* apalache-type: ev Int
\* apalache-type: ex Int
\* apalache-type: i Int
\* apalache-type: ph Str
\* apalache-type: pos Int
\* apalache-type: ys Int
\* apalache-type: pk Int
\* apalache-type: joined Bool
\* apalache-type: stopped Bool
\* apalache-type: disabled Bool
\* apalache-type: store Int -> (Int -> Int)
\* apalache-type: rep Int -> Int
\* apalache-type: out Int -> (Int -> Int)
\* apalache-type: hitRow Bool
\* apalache-type: hitAfterStop Bool

VARIABLES os,       \* data: outer row j carries outer value os[j] (the column x's terms read)
          xk,       \* data: x row r matches outer value xk[r]
          yl,       \* data: the value y leaves in its slot after running for x row r (0: y found no row, slot kept)
          xe,       \* data: x row r also needs the enclosing query's value to be xe[r]
          ev,       \* the enclosing query's value for this execution of the subquery
          ex,       \* which execution of the subquery
          xv,       \* data: x row r also needs the session variable to be xv[r]
          sv,       \* the session variable's value now
          sva,      \* sva[j]: its value when outer row j was probed (the memo-off answer of row j uses it)
          i,        \* the outer row being joined
          ph,       \* "probe" | "scan" | "replay" | "done"
          pos,      \* next x row of the scan
          ys,       \* y's val_list slot (0 = NULL, before y ever ran)
          pk,       \* storage::m_last_key: the key read at the probe
          joined,   \* storage::current_key_joined
          stopped,  \* storage::insert_stopped
          disabled, \* the storage was disabled and freed
          store,    \* m_key_value_map as counts: store[k][r] entries (k, x row r); r = 0 is the nullptr entry
          rep,      \* m_current_value_list as counts: rows a hit still replays
          out,      \* out[j][r]: how many times x row r was emitted for outer row j
          hitRow,       \* ghost: a hit replayed a row
          hitAfterStop  \* ghost: a hit was served after inserts stopped

vars == <<os, xk, yl, xe, ev, ex, xv, sv, sva, i, ph, pos, ys, pk, joined, stopped, disabled, store, rep, out, hitRow, hitAfterStop>>

Keys == 0..((NV + 1) * (NY + 1) * (NE + 1) - 1)
KeyOf(o, y, e) == (o * (NY + 1) + y) * (NE + 1) + e
KO(k) == (k \div (NE + 1)) \div (NY + 1)
KE(k) == k % (NE + 1)

(* The memoize key (GLOSSARY): the outer value only, chosen when x's XASL is generated (decided
   round 1). Mutant "key_has_later" is develop's key_maker, which also took y's slot that
   pt_get_mvcc_reev_range_data () copied into x's where_range with the WHERE's later terms. *)
Key(y) == KeyOf(IF Mutant = "key_missing_outer" THEN 0 ELSE os[i],
                IF Mutant = "key_has_later" THEN y ELSE 0,
                IF EncKey THEN ev ELSE 0)

\* the memo-off answer: x rows of outer value v under this execution's enclosing value
Expected(v, r) == IF xk[r] = v /\ xe[r] = ev /\ xv[r] = sv THEN 1 ELSE 0
\* the memo-off answer of finished outer row j
ExpectedJ(j, r) == IF xk[r] = os[j] /\ xe[r] = ev /\ xv[r] = sva[j] THEN 1 ELSE 0
\* the x rows a stored key stands for: its enclosing value when keyed, else this execution's
ExpectedK(k, r) == IF xk[r] = KO(k) /\ xe[r] = (IF EncKey THEN KE(k) ELSE ev) /\ xv[r] = sv THEN 1 ELSE 0
\* the storage is never built when the statement assigns a session variable the inner reads
NoStorage == SessAssign /\ SvGuard
Has(k) == \E r \in 0..NX : store[k][r] > 0
YRun(r) == IF yl[r] = 0 THEN ys ELSE yl[r]
PutK == IF PutKey = "reread" THEN Key(ys) ELSE pk
Empty == [k \in Keys |-> [r \in 0..NX |-> 0]]

Init == /\ os \in [1..NO -> 1..NV]
        /\ xk \in [1..NX -> 1..NV]
        /\ yl \in [1..NX -> 0..NY]
        /\ xe \in [1..NX -> 1..NE]
        /\ ev \in 1..NE /\ ex = 1
        /\ xv \in IF SessAssign THEN [1..NX -> 1..NE] ELSE {[r \in 1..NX |-> 1]}
        /\ sv = 1 /\ sva = [j \in 1..NO |-> 1]
        /\ i = 1 /\ ph = "probe" /\ pos = 1 /\ ys = 0 /\ pk = 0
        /\ joined = FALSE /\ stopped = FALSE /\ disabled = NoStorage
        /\ store = Empty
        /\ rep = [r \in 1..NX |-> 0]
        /\ out = [j \in 1..NO |-> [r \in 1..NX |-> 0]]
        /\ hitRow = FALSE /\ hitAfterStop = FALSE

Advance == /\ i' = i + 1
           /\ ph' = IF i = NO THEN "done" ELSE "probe"

(* storage::get, key_changed branch (set_key_changed () ran when the outer row advanced). *)
Probe == /\ ph = "probe"
         /\ joined' = FALSE /\ pos' = 1
         /\ IF disabled
              THEN /\ ph' = "scan"
                   /\ UNCHANGED <<pk, rep, hitRow, hitAfterStop>>
              ELSE LET k == Key(ys) IN
                   /\ pk' = k
                   /\ IF ~Has(k)
                        THEN /\ ph' = "scan"
                             /\ UNCHANGED <<rep, hitRow, hitAfterStop>>
                        ELSE /\ ph' = "replay"
                             \* a nullptr entry answers ENDED: no row
                             /\ rep' = IF store[k][0] > 0 THEN [r \in 1..NX |-> 0]
                                       ELSE [r \in 1..NX |-> store[k][r]]
                             /\ hitAfterStop' = (hitAfterStop \/ stopped)
                             /\ UNCHANGED hitRow
         /\ sva' = [sva EXCEPT ![i] = sv]
         /\ UNCHANGED <<os, xk, yl, xe, ev, ex, xv, sv, i, ys, stopped, disabled, store, out>>

(* storage::get, has_range branch: set_value () of one stored row, then y runs for it. *)
Replay == /\ ph = "replay"
          /\ \E r \in 1..NX :
               /\ rep[r] > 0
               /\ rep' = [rep EXCEPT ![r] = @ - 1]
               /\ out' = [out EXCEPT ![i][r] = @ + 1]
               /\ ys' = YRun(r)
          /\ hitRow' = TRUE
          /\ UNCHANGED <<os, xk, yl, xe, ev, ex, xv, sv, sva, i, ph, pos, pk, joined, stopped, disabled, store, hitAfterStop>>

ReplayEnd == /\ ph = "replay"
             /\ \A r \in 1..NX : rep[r] = 0
             /\ Advance
             /\ UNCHANGED <<os, xk, yl, xe, ev, ex, xv, sv, sva, pos, ys, pk, joined, stopped, disabled, store, rep, out, hitRow, hitAfterStop>>

ScanSkip == /\ ph = "scan" /\ pos <= NX /\ Expected(os[i], pos) = 0
            /\ pos' = pos + 1
            /\ UNCHANGED <<os, xk, yl, xe, ev, ex, xv, sv, sva, i, ph, ys, pk, joined, stopped, disabled, store, rep, out, hitRow, hitAfterStop>>

(* storage::put and can_insert at one x row. Exactly one of insert, stop (the budget is used
   up: stop_insert drops the current key's entries), disable (the hit ratio is judged low), or
   nothing (disabled or already stopped). *)
PutRow(r) ==
  \/ /\ disabled
     /\ UNCHANGED <<joined, stopped, disabled, store>>
  \/ /\ ~disabled /\ stopped
     /\ UNCHANGED <<joined, stopped, disabled, store>>
  \/ /\ ~disabled /\ ~stopped
     /\ store' = [store EXCEPT ![PutK][r] = @ + 1]
     /\ joined' = TRUE
     /\ UNCHANGED <<stopped, disabled>>
  \/ /\ ~disabled /\ ~stopped
     /\ stopped' = TRUE
     /\ store' = IF joined /\ Mutant # "stop_keeps_partial"
                   THEN [store EXCEPT ![pk] = [x \in 0..NX |-> 0]]
                   ELSE store
     /\ UNCHANGED <<joined, disabled>>
  \/ /\ ~disabled
     /\ disabled' = TRUE /\ store' = Empty
     /\ UNCHANGED <<joined, stopped>>

ScanRow == /\ ph = "scan" /\ pos <= NX /\ Expected(os[i], pos) = 1
           /\ PutRow(pos)
           /\ out' = [out EXCEPT ![i][pos] = @ + 1]
           /\ ys' = YRun(pos)
           /\ pos' = pos + 1
           /\ UNCHANGED <<os, xk, yl, xe, ev, ex, xv, sv, sva, i, ph, pk, rep, hitRow, hitAfterStop>>

(* storage::put_nullptr at the end of x's scan for this outer row. *)
ScanEnd == /\ ph = "scan" /\ pos = NX + 1
           /\ \/ /\ (disabled \/ joined \/ stopped)
                 /\ UNCHANGED <<stopped, disabled, store>>
              \/ /\ ~disabled /\ ~joined /\ ~stopped
                 /\ store' = [store EXCEPT ![PutK][0] = @ + 1]
                 /\ UNCHANGED <<stopped, disabled>>
              \/ /\ ~disabled /\ ~joined /\ ~stopped
                 /\ stopped' = TRUE
                 /\ UNCHANGED <<disabled, store>>
              \/ /\ ~disabled /\ ~joined
                 /\ disabled' = TRUE /\ store' = Empty
                 /\ UNCHANGED stopped
           /\ pos' = 1
           /\ Advance
           /\ UNCHANGED <<os, xk, yl, xe, ev, ex, xv, sv, sva, ys, pk, joined, rep, out, hitRow, hitAfterStop>>

(* The next execution of the subquery holding the NL chain: qexec_execute_mainblock_internal opens
   the scans again and new_memoize_storage frees the old storage and builds a new one. y's slot
   keeps its last value. *)
NewExec == /\ ph = "done" /\ ex < NEX
           /\ ex' = ex + 1
           /\ ev' \in 1..NE
           /\ i' = 1 /\ ph' = "probe" /\ pos' = 1
           /\ out' = [j \in 1..NO |-> [r \in 1..NX |-> 0]]
           /\ IF Mutant = "storage_kept"
                THEN UNCHANGED <<store, joined, stopped, disabled>>
                ELSE /\ store' = Empty
                     /\ joined' = FALSE /\ stopped' = FALSE /\ disabled' = NoStorage
           /\ UNCHANGED <<os, xk, yl, xe, xv, sv, sva, ys, pk, rep, hitRow, hitAfterStop>>

(* The select list's `@v := ...` of the row just joined, before the next outer row's probe. *)
SvAssign == /\ SessAssign /\ ph = "probe"
            /\ sv' \in 1..NE
            /\ UNCHANGED <<os, xk, yl, xe, ev, ex, xv, sva, i, ph, pos, ys, pk, joined, stopped, disabled, store, rep, out, hitRow, hitAfterStop>>

Done == ph = "done" /\ UNCHANGED vars

Next == Probe \/ Replay \/ ReplayEnd \/ ScanSkip \/ ScanRow \/ ScanEnd \/ NewExec \/ SvAssign \/ Done

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* Properties *)

TypeOK == /\ os \in [1..NO -> 1..NV]
          /\ xk \in [1..NX -> 1..NV]
          /\ yl \in [1..NX -> 0..NY]
          /\ xe \in [1..NX -> 1..NE]
          /\ ev \in 1..NE /\ ex \in 1..NEX
          /\ xv \in [1..NX -> 1..NE] /\ sv \in 1..NE /\ sva \in [1..NO -> 1..NE]
          /\ i \in 1..(NO + 1)
          /\ ph \in {"probe", "scan", "replay", "done"}
          /\ pos \in 1..(NX + 1)
          /\ ys \in 0..NY
          /\ pk \in Keys
          /\ joined \in BOOLEAN /\ stopped \in BOOLEAN /\ disabled \in BOOLEAN
          /\ store \in [Keys -> [0..NX -> 0..(NO * NEX)]]
          /\ rep \in [1..NX -> 0..NO]
          /\ out \in [1..NO -> [1..NX -> 0..NO]]
          /\ hitRow \in BOOLEAN /\ hitAfterStop \in BOOLEAN

(* C1: every finished outer row got exactly the x rows the NL join gives with memoize off. *)
OutputCorrect == \A j \in 1..NO : j < i => \A r \in 1..NX : out[j][r] = ExpectedJ(j, r)

(* C2: a key the memo answers from holds exactly the x rows of its outer value, or the one
   "no row" entry when there are none. The key a probe is still filling is exempt. *)
Complete(k) == \/ ~Has(k)
               \/ /\ store[k][0] = 1
                  /\ \A r \in 1..NX : store[k][r] = 0 /\ ExpectedK(k, r) = 0
               \/ /\ store[k][0] = 0
                  /\ \A r \in 1..NX : store[k][r] = ExpectedK(k, r)
StoreSound == \A k \in Keys : (ph = "scan" /\ k = pk) \/ Complete(k)

(* Witnesses, each expected violated *)
NotHitRow == ~hitRow
NotHitAfterStop == ~hitAfterStop
NotDisabled == ~disabled
NotSecondExecHit == ~(ex > 1 /\ hitRow)
NotSvChangedAndDone == ~(ph = "done" /\ \E j \in 1..NO : sva[j] # 1)

-----------------------------------------------------------------------------
(* Inductive invariant: the claims plus what each phase holds. *)

\* the outer row being joined has emitted what its phase says
CurOut == i <= NO =>
            /\ ph = "probe" => \A r \in 1..NX : out[i][r] = 0
            /\ ph = "scan" => \A r \in 1..NX : out[i][r] = IF r < pos THEN Expected(os[i], r) ELSE 0
            /\ ph = "replay" => \A r \in 1..NX : out[i][r] + rep[r] = Expected(os[i], r)
LaterOut == \A j \in 1..NO : j > i => \A r \in 1..NX : out[j][r] = 0
RepIdle == ph # "replay" => \A r \in 1..NX : rep[r] = 0
PhaseIdx == /\ (ph = "done") = (i = NO + 1)
            /\ ph # "scan" => pos = 1
DisabledEmpty == disabled => store = Empty
\* the key being filled is the probe's key of this outer value, holding the rows scanned so far
ScanKey == ph = "scan" /\ ~disabled =>
             /\ pk = Key(ys)
             /\ KO(pk) = os[i]
             /\ store[pk][0] = 0
             /\ \A r \in 1..NX : store[pk][r] = IF ~stopped /\ r < pos THEN Expected(os[i], r) ELSE 0
             /\ joined => \E r \in 1..NX : r < pos /\ Expected(os[i], r) = 1
             /\ ~stopped /\ (\E r \in 1..NX : r < pos /\ Expected(os[i], r) = 1) => joined
KeySlot == i <= NO => Key(ys) = KeyOf(os[i], 0, IF EncKey THEN ev ELSE 0)
\* the session variable holds still from a probe to the end of its outer row
SvRow == /\ ph \in {"scan", "replay"} => sva[i] = sv
         /\ ~SessAssign => sv = 1 /\ (\A r \in 1..NX : xv[r] = 1) /\ (\A j \in 1..NO : sva[j] = 1)
         /\ NoStorage => disabled

IndInv ==
  /\ TypeOK
  /\ OutputCorrect
  /\ StoreSound
  /\ CurOut
  /\ LaterOut
  /\ RepIdle
  /\ PhaseIdx
  /\ DisabledEmpty
  /\ ScanKey
  /\ KeySlot
  /\ SvRow

(* Apalache: the sizes are fixed (they are function domains); every data value and state is open. *)
CInit == /\ NO = 3 /\ NX = 3 /\ NV = 2 /\ NY = 1 /\ NE = 2 /\ NEX = 2
         /\ PutKey = "reread" /\ EncKey = FALSE /\ SessAssign = FALSE /\ SvGuard = TRUE /\ Mutant = "none"
=============================================================================
