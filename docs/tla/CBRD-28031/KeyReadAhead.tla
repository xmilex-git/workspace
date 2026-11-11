---------------------------- MODULE KeyReadAhead ----------------------------
(* CBRD-28031 D6: a parallel index scan worker on one leaf page looks up the heap rows of the leaf's qualifying
   keys in key order. When its read-ahead window fires (fewer than H OIDs ahead hinted), it evaluates the
   next keys of the leaf ahead of the lookups (key range, key filter, visibility), keeps them in a queue, and
   hints the heap pages of the next D OIDs in lookup order across keys. When the queue is empty the next key
   is evaluated by the lookups themselves. Positions are the leaf's qualifying OIDs in lookup order, 0-based;
   pages are not modeled (`ReadAhead` is the window over one OID sequence). An overflow page's OIDs are a
   sequence of their own (a `ReadAhead` buffer). *)
EXTENDS Integers

CONSTANTS NK, MaxO, D, ErrAt, CountAt, Mutant
\* NK keys on the leaf page, 0..MaxO qualifying OIDs a key (0: the key fails the range, filter or visibility),
\* D the window (SCAN_INDEX_READ_AHEAD_DISTANCE), ErrAt: "defer" (a key whose key filter raises an error stops
\* the look-ahead and is evaluated again when the lookups reach it) or "early" (raised at the look-ahead),
\* CountAt: "eval" or "consume" (when the key's trace counters are added)

VARIABLES nOid, base, errKey, phase, ev, ck, co, hf, slotKey, alloc, freed, counted, consumedKeys, raised,
          ended, orderOk, pairOk, leadOk, errOk, endOk, lastPos

vars == <<nOid, base, errKey, phase, ev, ck, co, hf, slotKey, alloc, freed, counted, consumedKeys, raised,
          ended, orderOk, pairOk, leadOk, errOk, endOk, lastPos>>

\* apalache-type: NK Int
\* apalache-type: MaxO Int
\* apalache-type: D Int
\* apalache-type: ErrAt Str
\* apalache-type: CountAt Str
\* apalache-type: Mutant Str
\* apalache-type: nOid Int -> Int
\* apalache-type: base Int -> Int
\* apalache-type: errKey Int
\* apalache-type: phase Str
\* apalache-type: ev Int
\* apalache-type: ck Int
\* apalache-type: co Int
\* apalache-type: hf Int
\* apalache-type: slotKey Int
\* apalache-type: alloc Set(Int)
\* apalache-type: freed Set(Int)
\* apalache-type: counted Set(Int)
\* apalache-type: consumedKeys Set(Int)
\* apalache-type: raised Bool
\* apalache-type: ended Bool
\* apalache-type: orderOk Bool
\* apalache-type: pairOk Bool
\* apalache-type: leadOk Bool
\* apalache-type: errOk Bool
\* apalache-type: endOk Bool
\* apalache-type: lastPos Int

\* Apalache: the bounds of the main cfg
CInit ==
  /\ NK = 4
  /\ MaxO = 2
  /\ D = 4
  /\ ErrAt = "defer"
  /\ CountAt = "consume"
  /\ Mutant = "none"

H == D \div 2
Keys == 1..NK
Min(x, y) == IF x < y THEN x ELSE y
Max(x, y) == IF x > y THEN x ELSE y

\* position of OID j (1-based) of key k; base[k] is the number of OIDs of the keys before k
Pos(k, j) == base[k] + j - 1
\* positions evaluated: every OID of keys 1..ev
EvalEnd == base[ev + 1]
\* the first key the look-ahead may not pass: an erroring key under "defer", or past the leaf
Barrier == IF ErrAt = "defer" /\ errKey > 0 THEN errKey ELSE NK + 1

BaseWf == base[1] = 0 /\ \A k \in Keys : base[k + 1] = base[k] + nOid[k]

TypeOK ==
  /\ nOid \in [Keys -> 0..MaxO]
  /\ base \in [1..(NK + 1) -> 0..(NK * MaxO)]
  /\ errKey \in 0..NK
  /\ phase \in {"fresh", "check", "eval", "look", "next", "stopped", "done", "error"}
  /\ ev \in 0..NK
  /\ ck \in 1..(NK + 1)
  /\ co \in 1..(MaxO + 1)
  /\ hf \in 0..(NK * MaxO)
  /\ slotKey \in 0..NK
  /\ alloc \in SUBSET Keys
  /\ freed \in SUBSET Keys
  /\ counted \in SUBSET Keys
  /\ consumedKeys \in SUBSET Keys
  /\ raised \in BOOLEAN
  /\ ended \in BOOLEAN
  /\ orderOk \in BOOLEAN
  /\ pairOk \in BOOLEAN
  /\ leadOk \in BOOLEAN
  /\ errOk \in BOOLEAN
  /\ endOk \in BOOLEAN
  /\ lastPos \in -1..(NK * MaxO)

Init ==
  /\ nOid \in [Keys -> 0..MaxO]
  /\ base \in [1..(NK + 1) -> 0..(NK * MaxO)]
  /\ BaseWf
  /\ errKey \in 0..NK
  /\ phase = "fresh"
  /\ ev = 0
  /\ ck = 1
  /\ co = 1
  /\ hf = 0
  /\ slotKey = 0
  /\ alloc = {}
  /\ freed = {}
  /\ counted = {}
  /\ consumedKeys = {}
  /\ raised = FALSE
  /\ ended = FALSE
  /\ orderOk = TRUE
  /\ pairOk = TRUE
  /\ leadOk = TRUE
  /\ errOk = TRUE
  /\ endOk = TRUE
  /\ lastPos = -1

\* evaluate_slot of key k (its value copied, pr_clear_value owed), by the look-ahead or by the lookups
Evaluated(k) ==
  /\ ev' = k
  /\ alloc' = alloc \cup {k}
  /\ counted' = IF CountAt = "eval" THEN counted \cup {k} ELSE counted
  /\ slotKey' = IF Mutant = "slot_key_latest" THEN k ELSE slotKey
  /\ ended' = IF Mutant = "end_at_eval" /\ k = NK THEN TRUE ELSE ended
  /\ endOk' = (endOk /\ (Mutant = "end_at_eval" /\ k = NK => ck > NK))

\* scan_next_slot: the next key; queued (evaluated ahead) or read now. The lookups reaching an erroring key
\* raise its error (scan_next_slot -> evaluate_slot (ahead = false) -> stop_at_error)
Fresh ==
  /\ phase = "fresh"
  /\ IF ck > NK
       THEN /\ phase' = "done"
            /\ UNCHANGED <<ev, alloc, counted, slotKey, ended, endOk, raised, hf>>
     ELSE IF ev >= ck
       THEN /\ phase' = "check"
            /\ UNCHANGED <<ev, alloc, counted, slotKey, ended, endOk, raised, hf>>
     ELSE IF errKey = ck
       THEN /\ phase' = "error"
            /\ raised' = TRUE
            /\ UNCHANGED <<ev, alloc, counted, slotKey, ended, endOk, hf>>
       ELSE /\ Evaluated(ck)
            /\ phase' = "check"
            \* m_ahead_hinted = 0: a key read now starts a new sequence
            /\ hf' = Pos(ck, 1)
            /\ UNCHANGED raised
  /\ UNCHANGED <<nOid, base, errKey, ck, co, freed, consumedKeys, orderOk, pairOk, leadOk, errOk, lastPos>>

\* process_oid -> read_ahead before the lookup of OID co of key ck: the window fires when fewer than H OIDs
\* ahead are hinted; a key with no visible leaf OID is drained at once (no lookup, no read_ahead)
Check ==
  /\ phase = "check"
  /\ LET p == Pos(ck, co) IN
       phase' = IF co > nOid[ck] THEN "next"
                ELSE IF (IF Mutant = "late_window" THEN p >= hf ELSE p + H >= hf) THEN "eval"
                ELSE "look"
  /\ UNCHANGED <<nOid, base, errKey, ev, ck, co, hf, slotKey, alloc, freed, counted, consumedKeys, raised, ended,
                 orderOk, pairOk, leadOk, errOk, endOk, lastPos>>

\* evaluate_ahead: the next key of the leaf, while the window is short of D OIDs from the current one
EvalAhead ==
  /\ phase = "eval"
  /\ ev + 1 < Barrier
  /\ ev < NK
  /\ EvalEnd < Pos(ck, co) + D
  /\ IF ErrAt = "early" /\ errKey = ev + 1
       THEN /\ phase' = "error"
            /\ raised' = TRUE
            \* every lookup before the erroring key happened
            /\ errOk' = (errOk /\ ck = errKey)
            /\ UNCHANGED <<ev, alloc, counted, slotKey, ended, endOk>>
       ELSE /\ Evaluated(ev + 1)
            /\ UNCHANGED <<phase, raised, errOk>>
  /\ UNCHANGED <<nOid, base, errKey, ck, co, hf, freed, consumedKeys, orderOk, pairOk, leadOk, lastPos>>

\* the window is complete (D OIDs, the barrier or the leaf's end): its pages go to the OS (m_ahead_hinted)
WindowDone ==
  /\ phase = "eval"
  /\ ~(ev + 1 < Barrier /\ ev < NK /\ EvalEnd < Pos(ck, co) + D)
  /\ phase' = "look"
  /\ hf' = Max(hf, Min(EvalEnd, Pos(ck, co) + D))
  /\ UNCHANGED <<nOid, base, errKey, ev, ck, co, slotKey, alloc, freed, counted, consumedKeys, raised, ended,
                 orderOk, pairOk, leadOk, errOk, endOk, lastPos>>

\* process_oid for OID co of key ck; the key it reads (covering, GROUP BY skip) is ck's
Look ==
  /\ phase = "look"
  /\ LET p == Pos(ck, co) IN
       /\ orderOk' = (orderOk /\ p = lastPos + 1)
       /\ lastPos' = p
       /\ leadOk' = (leadOk /\ hf > Min(Pos(Barrier, 1) - 1, p + H))
  /\ pairOk' = (pairOk /\ (IF Mutant = "slot_key_latest" THEN slotKey ELSE ck) = ck)
  /\ co' = co + 1
  /\ phase' = "check"
  /\ UNCHANGED <<nOid, base, errKey, ev, ck, hf, slotKey, alloc, freed, counted, consumedKeys, raised, ended, errOk,
                 endOk>>

\* the key's OIDs are drained: its value is cleared, the walker moves to the next key
NextKey ==
  /\ phase = "next"
  /\ freed' = freed \cup {ck}
  /\ consumedKeys' = consumedKeys \cup {ck}
  /\ counted' = IF CountAt = "consume" THEN counted \cup {ck} ELSE counted
  /\ ck' = ck + 1
  /\ co' = 1
  /\ phase' = "fresh"
  /\ ended' = IF ck = NK THEN TRUE ELSE ended
  /\ UNCHANGED <<nOid, base, errKey, ev, hf, slotKey, alloc, raised, orderOk, pairOk, leadOk, errOk, endOk, lastPos>>

\* LIMIT reached, interrupt, an error elsewhere, or this worker's error: the walker is reset (cleanup_on_reset,
\* set_overflow_page, set_page) and every queued key value is cleared
Stop ==
  /\ phase \in {"fresh", "check", "eval", "look", "next", "error"}
  /\ phase' = "stopped"
  /\ freed' = IF Mutant = "leak_queue" THEN freed \cup ({ck} \cap alloc) ELSE alloc
  /\ UNCHANGED <<nOid, base, errKey, ev, ck, co, hf, slotKey, alloc, counted, consumedKeys, raised, ended, orderOk,
                 pairOk, leadOk, errOk, endOk, lastPos>>

Done == phase \in {"stopped", "done"} /\ UNCHANGED vars

Next == Fresh \/ Check \/ EvalAhead \/ WindowDone \/ Look \/ NextKey \/ Stop \/ Done

Spec == Init /\ [][Next]_vars

(* ---------------- claims ---------------- *)

\* C1: the worker looks up its leaf's qualifying OIDs once each, in key order
WorkerOrder == orderOk
\* C7: a lookup reads the key value of its own key
KeyPairing == pairOk
\* C3 (worker): every OID from the current one to H ahead, up to the leaf's end or an erroring key, was in a
\* hinted window before its lookup
WorkerLead == leadOk
\* C8: once the walker stops, every key value copied by an evaluation was cleared, and none twice
NoKeyLeak == phase \in {"stopped", "done"} => freed = alloc
\* C9: a key filter error is raised only when the lookups reach its key, as without the look-ahead
ErrorInOrder == errOk
\* C10: the trace counters count the keys whose rows were looked up, as without the look-ahead
CountsConsumed == phase \in {"stopped", "done"} => counted = consumedKeys
\* C11: the leaf's range end is signaled only after the last queued key was drained
EndAfterDrain == endOk

\* witness: a key is evaluated ahead while an earlier key is still being looked up
NotQueued == ~(phase = "look" /\ ev > ck)

Live == {"fresh", "check", "eval", "look", "next"}

\* well-formedness of the cursors: evaluation runs ahead of the lookups and never past an erroring key
CursorWf ==
  /\ ck <= ev + 1
  /\ phase \in {"check", "eval", "look", "next"} => ck <= NK /\ ck <= ev
  /\ ck <= NK => co <= nOid[ck] + 1
  /\ phase \in {"eval", "look"} => co <= nOid[ck]
  /\ phase = "next" => co = nOid[ck] + 1
  /\ ErrAt = "defer" /\ errKey > 0 => ev < errKey /\ ck <= errKey
  /\ phase = "done" => ck = NK + 1
  /\ phase = "error" => ck <= NK

\* the last lookup is the one before the cursor
LastWf == phase \in Live => lastPos = IF ck > NK THEN base[NK + 1] - 1 ELSE base[ck] + co - 2

\* the hint frontier never passes what was evaluated
HfWf == hf >= 0 /\ hf <= EvalEnd

\* before a lookup the window covers H OIDs ahead, or the barrier
LookLead == phase = "look" => hf > Min(Pos(Barrier, 1) - 1, Pos(ck, co) + H)

AllocWf ==
  /\ alloc = {k \in Keys : k <= ev}
  /\ consumedKeys = {k \in Keys : k < ck}
  /\ phase # "stopped" => freed = consumedKeys
  /\ CountAt = "consume" => counted = consumedKeys
  /\ Mutant = "none" => slotKey = 0 /\ ended = (ck > NK)

IndInv ==
  /\ TypeOK
  /\ BaseWf
  /\ CursorWf
  /\ LastWf
  /\ HfWf
  /\ LookLead
  /\ AllocWf
  /\ WorkerOrder
  /\ KeyPairing
  /\ WorkerLead
  /\ ErrorInOrder
  /\ EndAfterDrain
  /\ NoKeyLeak
  /\ CountsConsumed

=============================================================================
