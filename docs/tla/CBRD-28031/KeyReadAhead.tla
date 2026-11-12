---------------------------- MODULE KeyReadAhead ----------------------------
(* CBRD-28031 D6: a parallel index scan worker on one leaf page looks up the heap rows of the leaf's qualifying
   keys in key order. When its read-ahead window fires (fewer than H OIDs ahead hinted), it evaluates the
   next keys of the leaf ahead of the lookups (key range, key filter, visibility), keeps the qualifying ones in a
   queue, and hints the heap pages of the next D OIDs in lookup order across keys. When the queue is empty the
   next key is evaluated by the lookups themselves. A key the key range or the key filter rejects is passed in the
   same evaluation, with no queue entry (D10). A worker whose scan has no heap lookup (a covering index) does
   none of this (D11). The OIDs evaluated ahead of the lookups stay within Cap, the OIDs a serial scan's OID buffer
   holds (index_scan_oid_buffer_size, D12). Positions are the leaf's qualifying OIDs in lookup order, 0-based; pages are not modeled
   (`ReadAhead` is the window over one OID sequence). An overflow page's OIDs are a sequence of their own (a
   `ReadAhead` buffer). *)
EXTENDS Integers

CONSTANTS NK, MaxO, D, W0, Cap, ErrAt, CountAt, Mutant
\* NK keys on the leaf page, 0..MaxO visible OIDs a key, the window: W0 OIDs at first (SCAN_INDEX_READ_AHEAD_INITIAL),
\* every next whole one twice the one before, up to D (SCAN_INDEX_READ_AHEAD_DISTANCE); the distance is the
\* worker scan's and is kept from leaf to leaf (D13, D16),
\* ErrAt: "defer" (a key whose key filter raises an error stops the look-ahead and is evaluated again when the
\* lookups reach it) or "early" (raised at the look-ahead), CountAt: "eval" or "consume" (when the key's trace
\* counters are added)

VARIABLES nOid, base, rej, cov, errKey, phase, ev, ck, co, hf, aend, errAhead, windowed, evals, rk, slotKey,
          alloc, freed, counted, consumedKeys, raised, ended, orderOk, pairOk, leadOk, errOk, endOk, lastPos,
          dist, look0

vars == <<nOid, base, rej, cov, errKey, phase, ev, ck, co, hf, aend, errAhead, windowed, evals, rk, slotKey,
          alloc, freed, counted, consumedKeys, raised, ended, orderOk, pairOk, leadOk, errOk, endOk, lastPos,
          dist, look0>>

\* apalache-type: NK Int
\* apalache-type: MaxO Int
\* apalache-type: D Int
\* apalache-type: W0 Int
\* apalache-type: Cap Int
\* apalache-type: ErrAt Str
\* apalache-type: CountAt Str
\* apalache-type: Mutant Str
\* apalache-type: nOid Int -> Int
\* apalache-type: base Int -> Int
\* apalache-type: rej Set(Int)
\* apalache-type: cov Bool
\* apalache-type: errKey Int
\* apalache-type: phase Str
\* apalache-type: ev Int
\* apalache-type: ck Int
\* apalache-type: co Int
\* apalache-type: hf Int
\* apalache-type: aend Bool
\* apalache-type: errAhead Bool
\* apalache-type: windowed Bool
\* apalache-type: evals Int -> Int
\* apalache-type: rk Int -> Int
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
\* apalache-type: dist Int
\* apalache-type: look0 Int

\* Apalache: the bounds of the main cfg
CInit ==
  /\ NK = 4
  /\ MaxO = 2
  /\ D = 4
  /\ W0 = 1
  /\ Cap = 4
  /\ ErrAt = "defer"
  /\ CountAt = "consume"
  /\ Mutant = "none"

\* the lead of the current window: the next one is told when this many OIDs of it are left
H == dist \div 2
Min(x, y) == IF x < y THEN x ELSE y
\* the window after the current one (dist: the last whole window of the worker's scan; 0: none yet)
ND == IF Mutant = "fixed" THEN D ELSE IF dist = 0 THEN W0 ELSE Min(2 * dist, D)
\* the OIDs a window may evaluate ahead of the lookup: the window, or the OID buffer's bound (ISCAN_OID_BUFFER_COUNT)
CapWin == Min(D, Cap)
Win == IF Mutant = "no_cap" THEN ND ELSE Min(ND, Cap)
\* the OIDs from the current one a window is sure to cover
Lead == Min(H, Cap - 1)
Keys == 1..NK
Max(x, y) == IF x > y THEN x ELSE y

\* position of OID j (1-based) of key k; base[k] is the number of OIDs of the keys before k
Pos(k, j) == base[k] + j - 1
\* positions evaluated: every OID of keys 1..ev
EvalEnd == base[ev + 1]
\* the first key the look-ahead may not pass: an erroring key under "defer", or past the leaf
Barrier == IF ErrAt = "defer" /\ errKey > 0 THEN errKey ELSE NK + 1
\* n is the first key from `from` on that the key range and the key filter do not reject, or NK + 1
FirstKept(n, from) ==
  /\ n \in from..(NK + 1)
  /\ n = NK + 1 \/ n \notin rej
  /\ \A j \in Keys : from <= j /\ j < n => j \in rej
\* one more evaluation (or read_keys count) of the keys lo..hi
\* @type: (Int -> Int, Int, Int) => (Int -> Int);
Bump(f, lo, hi) == [j \in Keys |-> IF lo <= j /\ j <= hi THEN Min(f[j] + 1, 3) ELSE f[j]]

BaseWf == base[1] = 0 /\ \A k \in Keys : base[k + 1] = base[k] + nOid[k]
\* a rejected key has no OID to look up; an erroring key is not rejected (its key filter raises)
KeysWf == (\A k \in rej : nOid[k] = 0) /\ errKey \notin rej

TypeOK ==
  /\ nOid \in [Keys -> 0..MaxO]
  /\ base \in [1..(NK + 1) -> 0..(NK * MaxO)]
  /\ rej \in SUBSET Keys
  /\ cov \in BOOLEAN
  /\ errKey \in 0..NK
  /\ phase \in {"fresh", "check", "eval", "look", "next", "stopped", "done", "error"}
  /\ ev \in 0..NK
  /\ ck \in 1..(NK + 1)
  /\ co \in 1..(MaxO + 1)
  /\ hf \in 0..(NK * MaxO)
  /\ aend \in BOOLEAN
  /\ errAhead \in BOOLEAN
  /\ windowed \in BOOLEAN
  /\ evals \in [Keys -> 0..3]
  /\ rk \in [Keys -> 0..3]
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
  /\ dist \in 0..D
  /\ look0 \in 0..(2 * D)

Init ==
  /\ nOid \in [Keys -> 0..MaxO]
  /\ base \in [1..(NK + 1) -> 0..(NK * MaxO)]
  /\ BaseWf
  /\ rej \in SUBSET Keys
  /\ cov \in BOOLEAN
  /\ errKey \in 0..NK
  /\ KeysWf
  /\ phase = "fresh"
  /\ ev = 0
  /\ ck = 1
  /\ co = 1
  /\ hf = 0
  /\ aend = FALSE
  /\ errAhead = FALSE
  /\ windowed = FALSE
  /\ evals = [k \in Keys |-> 0]
  /\ rk = [k \in Keys |-> 0]
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
  \* the leaves before this one: look0 lookups, every OID told was looked up, the distance they reached
  /\ dist \in 0..D
  /\ look0 \in 0..(2 * D)
  /\ 3 * dist <= 2 * look0 + W0

\* next_key returned key k qualified (its value copied, pr_clear_value owed), to the look-ahead or to the lookups
Evaluated(k) ==
  /\ ev' = k
  /\ alloc' = alloc \cup {k}
  /\ counted' = IF CountAt = "eval" THEN counted \cup {k} ELSE counted
  /\ slotKey' = IF Mutant = "slot_key_latest" THEN k ELSE slotKey
  /\ ended' = IF Mutant = "end_at_eval" /\ k = NK THEN TRUE ELSE ended
  /\ endOk' = (endOk /\ (Mutant = "end_at_eval" /\ k = NK => ck > NK))

\* scan_next_slot: the next key, popped from the queue (the rejected keys before it were passed when it was
\* evaluated ahead; their read_keys come with it), or, the queue empty, read by the lookups (next_key, ahead =
\* false) from the slot the look-ahead stopped at (m_ahead_slot; the keys it passed add m_ahead_skipped_keys) or
\* from the current slot. The lookups reaching an erroring key raise its error (stop_at_error)
Fresh ==
  /\ phase = "fresh"
  /\ \E n \in 1..(NK + 1) :
       /\ FirstKept(n, ck)
       /\ consumedKeys' = consumedKeys \cup {j \in Keys : j < n}
       /\ IF n <= ev
            THEN \* m_ahead.pop_front
                 /\ ck' = n
                 /\ phase' = "check"
                 /\ rk' = Bump(rk, ck, n)
                 /\ UNCHANGED <<ev, alloc, counted, slotKey, ended, endOk, raised, hf, evals, aend>>
          ELSE /\ evals' = Bump(evals, ev + 1, Min(n, NK))
               /\ rk' = IF Mutant = "skip_count_lost" THEN Bump(rk, ev + 1, Min(n, NK)) ELSE Bump(rk, ck, Min(n, NK))
               /\ aend' = FALSE
               /\ IF n = NK + 1
                    THEN /\ ck' = NK + 1
                         /\ phase' = "done"
                         /\ ended' = TRUE
                         /\ ev' = NK
                         /\ UNCHANGED <<alloc, counted, slotKey, endOk, raised, hf>>
                  ELSE IF n = errKey
                    THEN /\ ck' = n
                         /\ phase' = "error"
                         /\ raised' = TRUE
                         /\ ev' = n - 1
                         /\ UNCHANGED <<alloc, counted, slotKey, ended, endOk, hf>>
                    ELSE /\ ck' = n
                         /\ Evaluated(n)
                         /\ phase' = "check"
                         \* m_ahead_hinted = 0: a key read now starts a new sequence
                         /\ hf' = Pos(n, 1)
                         /\ UNCHANGED raised
  /\ UNCHANGED <<look0, dist, nOid, base, rej, cov, errKey, co, errAhead, windowed, freed, orderOk, pairOk, leadOk, errOk,
                 lastPos>>

\* before the lookup of OID co of key ck: a covering scan looks nothing up (process_oid's covering path: no
\* read_ahead); read_ahead returns at once after the look-ahead stopped (m_ahead_end); otherwise the window fires
\* when fewer than H OIDs ahead are hinted. A key with no visible leaf OID is drained at once
Check ==
  /\ phase = "check"
  /\ LET p == Pos(ck, co) IN
       phase' = IF co > nOid[ck] THEN "next"
                ELSE IF cov /\ Mutant # "covering_window" THEN "look"
                ELSE IF aend THEN "look"
                ELSE IF (IF Mutant = "late_window" THEN p >= hf ELSE p + H >= hf) THEN "eval"
                ELSE "look"
  /\ UNCHANGED <<look0, dist, nOid, base, rej, cov, errKey, ev, ck, co, hf, aend, errAhead, windowed, evals, rk, slotKey, alloc,
                 freed, counted, consumedKeys, raised, ended, orderOk, pairOk, leadOk, errOk, endOk, lastPos>>

\* evaluate_ahead -> next_key (ahead = true), while the window is short of D OIDs from the current one: the keys
\* the key range or the key filter rejects are passed (cleared at once, no queue entry) up to the next key that
\* qualifies, which is queued; when none is left before the leaf's end or an erroring key (cleared, read again
\* by the lookups), the look-ahead stops there (m_ahead_end, m_ahead_slot, m_ahead_skipped_keys) and the window
\* goes to the OS
EvalAhead ==
  /\ phase = "eval"
  /\ ~aend
  /\ EvalEnd < Pos(ck, co) + Win
  /\ \E n \in 1..(NK + 1) :
       /\ FirstKept(n, ev + 1)
       /\ IF ErrAt = "early" /\ n = errKey
            THEN /\ phase' = "error"
                 /\ raised' = TRUE
                 \* every lookup before the erroring key happened
                 /\ errOk' = (errOk /\ ck = errKey)
                 /\ evals' = Bump(evals, ev + 1, n)
                 /\ UNCHANGED <<ev, alloc, counted, slotKey, ended, endOk, hf, aend, errAhead, windowed>>
          ELSE IF n <= NK /\ n # errKey
            THEN /\ evals' = Bump(evals, ev + 1, n)
                 /\ alloc' = IF Mutant = "queue_rejected" THEN alloc \cup {j \in Keys : ev < j /\ j <= n}
                             ELSE alloc \cup {n}
                 /\ ev' = n
                 /\ counted' = IF CountAt = "eval" THEN counted \cup {n} ELSE counted
                 /\ slotKey' = IF Mutant = "slot_key_latest" THEN n ELSE slotKey
                 /\ ended' = IF Mutant = "end_at_eval" /\ n = NK THEN TRUE ELSE ended
                 /\ endOk' = (endOk /\ (Mutant = "end_at_eval" /\ n = NK => ck > NK))
                 /\ windowed' = TRUE
                 /\ UNCHANGED <<phase, raised, errOk, hf, aend, errAhead>>
          ELSE \* n = NK + 1 (the leaf's end) or n = errKey: stop
               /\ evals' = Bump(evals, ev + 1, Min(n, NK))
               /\ errAhead' = (n = errKey)
               /\ IF Mutant = "no_stop_mark"
                    THEN UNCHANGED <<ev, aend>>
                    ELSE /\ ev' = n - 1
                         /\ aend' = TRUE
               /\ windowed' = TRUE
               /\ UNCHANGED <<phase, hf, alloc, counted, slotKey, ended, endOk, raised, errOk>>
  /\ UNCHANGED <<look0, dist, nOid, base, rej, cov, errKey, ck, co, rk, freed, consumedKeys, orderOk, pairOk, leadOk, lastPos>>

\* the window is complete (ND OIDs, or the look-ahead stopped, or the OID buffer is full): its pages go to the OS
\* (scan_index_read_ahead: ahead_next, ahead_distance)
WindowDone ==
  /\ phase = "eval"
  /\ aend \/ EvalEnd >= Pos(ck, co) + Win
  /\ phase' = "look"
  /\ hf' = Max(hf, Min(EvalEnd, Pos(ck, co) + ND))
  \* a window cut short (the leaf's end, the OID buffer's bound) does not make the next one larger
  /\ dist' = IF EvalEnd >= Pos(ck, co) + ND THEN ND ELSE dist
  /\ windowed' = TRUE
  /\ UNCHANGED <<look0, nOid, base, rej, cov, errKey, ev, ck, co, aend, errAhead, evals, rk, slotKey, alloc, freed, counted,
                 consumedKeys, raised, ended, orderOk, pairOk, leadOk, errOk, endOk, lastPos>>

\* process_oid for OID co of key ck; the key it reads (covering, GROUP BY skip) is ck's
Look ==
  /\ phase = "look"
  /\ LET p == Pos(ck, co) IN
       /\ orderOk' = (orderOk /\ p = lastPos + 1)
       /\ lastPos' = p
       /\ leadOk' = (leadOk /\ (cov \/ hf > Min(Pos(Barrier, 1) - 1, p + Lead)))
  /\ pairOk' = (pairOk /\ (IF Mutant = "slot_key_latest" THEN slotKey ELSE ck) = ck)
  /\ co' = co + 1
  /\ phase' = "check"
  /\ UNCHANGED <<look0, dist, nOid, base, rej, cov, errKey, ev, ck, hf, aend, errAhead, windowed, evals, rk, slotKey, alloc, freed,
                 counted, consumedKeys, raised, ended, errOk, endOk>>

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
  /\ UNCHANGED <<look0, dist, nOid, base, rej, cov, errKey, ev, hf, aend, errAhead, windowed, evals, rk, slotKey, alloc, raised,
                 orderOk, pairOk, leadOk, errOk, endOk, lastPos>>

\* LIMIT reached, interrupt, an error elsewhere, or this worker's error: the walker is reset (cleanup_on_reset,
\* set_overflow_page, set_page) and every queued key value is cleared
Stop ==
  /\ phase \in {"fresh", "check", "eval", "look", "next", "error"}
  /\ phase' = "stopped"
  /\ freed' = IF Mutant = "leak_queue" THEN freed \cup ({ck} \cap alloc) ELSE alloc
  /\ UNCHANGED <<look0, dist, nOid, base, rej, cov, errKey, ev, ck, co, hf, aend, errAhead, windowed, evals, rk, slotKey, alloc,
                 counted, consumedKeys, raised, ended, orderOk, pairOk, leadOk, errOk, endOk, lastPos>>

Done == phase \in {"stopped", "done"} /\ UNCHANGED vars

Next == Fresh \/ Check \/ EvalAhead \/ WindowDone \/ Look \/ NextKey \/ Stop \/ Done

Spec == Init /\ [][Next]_vars

(* ---------------- claims ---------------- *)

\* C1: the worker looks up its leaf's qualifying OIDs once each, in key order
WorkerOrder == orderOk
\* C7: a lookup reads the key value of its own key
KeyPairing == pairOk
\* C3 (worker): every OID from the current one to H ahead (Cap - 1 when the OID buffer's bound is smaller), up to
\* the leaf's end or an erroring key, was in a hinted window before its lookup
WorkerLead == leadOk
\* C8: once the walker stops, every key value copied by an evaluation was cleared, and none twice
NoKeyLeak == phase \in {"stopped", "done"} => freed = alloc
\* C9: a key filter error is raised only when the lookups reach its key, as without the look-ahead
ErrorInOrder == errOk
\* C10: the trace counters count the keys whose rows were looked up (qualified keys), and every key read once
\* (read_keys), as without the look-ahead
CountsConsumed ==
  /\ phase \in {"stopped", "done"} => counted = consumedKeys \ rej
  /\ \A k \in Keys : rk[k] <= 1
  /\ phase = "done" => \A k \in Keys : rk[k] = 1
\* C11: the leaf's range end is signaled only after the last queued key was drained
EndAfterDrain == endOk
\* C12: every key is evaluated (read, key range, key filter) once, as without the look-ahead; only the key the
\* look-ahead stopped at is evaluated a second time, by the lookups (an erroring key here; the key past the range's
\* end takes the same path)
EvalOnce == \A k \in Keys : evals[k] <= IF k = errKey THEN 2 ELSE 1
\* C13: a key the key range or the key filter rejects takes no queue entry: its copied value is cleared at once
NoRejectedEntry == alloc \cap rej = {}
\* C14: a worker with no heap lookup (covering index) never evaluates ahead and never checks a window
NoWindowWithoutLookup == cov => ~windowed
\* C16: a worker's scan that stops after k lookups has told the OS about at most 3k + W0 OIDs (look0 lookups on the
\* leaves before this one, lastPos + 1 on this one; hf: the OIDs of this leaf told)
StopWaste == hf <= 2 * look0 + 3 * (lastPos + 1) + W0
\* C15: the OIDs evaluated ahead of the lookup stay within the OID buffer's bound (the key that crosses it included)
BufferBound == phase \in {"check", "eval", "look", "next"} => EvalEnd <= Max(base[ck + 1], Pos(ck, co) + CapWin + MaxO - 1)

\* witness: a key is evaluated ahead while an earlier key is still being looked up
NotQueued == ~(phase = "look" /\ ev > ck)
\* witness: the look-ahead passed a rejected key and stopped at the leaf's end, before the lookups reached it
NotSkippedStop == ~(aend /\ errKey = 0 /\ \E k \in rej : ck < k /\ k <= ev)
\* witness: the key the look-ahead stopped at on an error is raised by the lookups
NotErrorTwice == ~(errAhead /\ raised)
\* witness: a covering scan drains its leaf
NotCoveredDone == ~(cov /\ phase = "done" /\ \E k \in Keys : nOid[k] > 0)

Live == {"fresh", "check", "eval", "look", "next"}

\* well-formedness of the cursors: evaluation runs ahead of the lookups and never past an erroring key
CursorWf ==
  /\ ck <= ev + 1
  /\ phase \in {"check", "eval", "look", "next"} => ck <= NK /\ ck <= ev /\ ck \notin rej
  /\ ck <= NK => co <= nOid[ck] + 1
  /\ phase \in {"eval", "look"} => co <= nOid[ck]
  /\ phase = "next" => co = nOid[ck] + 1
  /\ ErrAt = "defer" /\ errKey > 0 => ev < errKey /\ ck <= errKey
  /\ phase = "done" => ck = NK + 1 /\ ev = NK
  /\ phase = "error" => ck <= NK /\ ck = errKey /\ ev = ck - 1

\* the stop of the look-ahead: it reached the leaf's end or an erroring key, every OID up to there hinted
StopWf ==
  /\ phase = "eval" => ~cov
  /\ phase = "eval" /\ aend => EvalEnd < Pos(ck, co) + ND
  /\ aend => ~cov /\ windowed /\ ev = Barrier - 1 /\ phase \notin {"error", "done"}
  /\ aend /\ phase \notin {"eval", "stopped"} => hf = EvalEnd
  /\ errAhead => errKey > 0 /\ ~cov /\ ev = errKey - 1 /\ (aend \/ phase \in {"error", "stopped"})
  /\ cov => ~windowed /\ ~aend /\ ~errAhead /\ ev <= ck

\* every key evaluated once, the erroring key once more for each of the look-ahead and the lookups
EvalsWf == \A k \in Keys :
  evals[k] = (IF k <= ev THEN 1 ELSE 0) + (IF k = errKey /\ errAhead THEN 1 ELSE 0)
             + (IF k = errKey /\ raised THEN 1 ELSE 0)

\* read_keys: the keys the lookups passed, the current one included once read
RkWf == \A k \in Keys :
  /\ k < ck => rk[k] = 1
  /\ k > ck => rk[k] = 0
  /\ k = ck /\ phase \in {"check", "eval", "look", "next", "error"} => rk[k] = 1
  /\ k = ck /\ phase = "fresh" => rk[k] = 0
  /\ rk[k] <= 1

\* the last lookup is the one before the cursor
LastWf == phase \in Live => lastPos = IF ck > NK THEN base[NK + 1] - 1 ELSE base[ck] + co - 2

\* between keys the lookup cursor is at the key's first OID, and the OIDs evaluated ahead keep C15's bound from it
FreshWf == phase = "fresh" => co = 1 /\ (ck <= NK => EvalEnd <= base[ck] + CapWin + MaxO - 1)

\* the distance grows only as fast as the lookups; a window fires when half of the current one is left
DistWf ==
  /\ 3 * dist <= 2 * (look0 + hf) + W0
  /\ phase = "eval" => Pos(ck, co) + H >= hf

\* the hint frontier never passes what was evaluated
HfWf == hf >= 0 /\ hf <= EvalEnd

\* before a lookup the window covers H OIDs ahead, or the barrier
LookLead == phase = "look" /\ ~cov => hf > Min(Pos(Barrier, 1) - 1, Pos(ck, co) + Lead)

AllocWf ==
  /\ alloc = {k \in Keys : k <= ev /\ k \notin rej}
  /\ consumedKeys = {k \in Keys : k < ck}
  /\ phase # "stopped" => freed = consumedKeys \ rej
  /\ CountAt = "consume" => counted = consumedKeys \ rej
  /\ Mutant = "none" => slotKey = 0 /\ ended = (ck > NK)
  /\ raised => errKey > 0 /\ phase \in {"error", "stopped"} /\ ck = errKey

IndInv ==
  /\ TypeOK
  /\ BaseWf
  /\ KeysWf
  /\ CursorWf
  /\ StopWf
  /\ EvalsWf
  /\ RkWf
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
  /\ EvalOnce
  /\ NoRejectedEntry
  /\ NoWindowWithoutLookup
  /\ BufferBound
  /\ FreshWf
  /\ DistWf
  /\ StopWaste

=============================================================================
