------------------------------ MODULE ReadAhead ------------------------------
(* CBRD-28031: the read-ahead hint of a serial index scan's heap lookups.
   One scan reads NB OID buffers in turn (call_get_next_index_oidset); before each lookup
   (scan_next_index_scan) it may check a window of the next OIDs (scan_index_read_ahead) and hand the
   window's heap pages that are not in the page buffer to the OS (pgbuf_read_ahead). Other threads
   load and evict pages at any time (Env). Positions are 0-based, as curr_oidno. *)
EXTENDS Integers, FiniteSets

CONSTANTS NB, MaxN, NP, D, INF, OnePage, Probe, Mutant
\* NB buffers of 1..MaxN OIDs, NP heap pages, window D (SCAN_INDEX_READ_AHEAD_DISTANCE, checked D/2 ahead),
\* INF for INT_MAX, OnePage: "skip" (every window of one page is left unchecked) or "ahead" (only a window
\* that starts at the current OID and holds one page is left unchecked), Probe: "locked" (each page looked up
\* in the buffer hash under the bucket mutex) or "racy" (no mutex: the answer may be wrong either way)

\* apalache-type: NB Int
\* apalache-type: MaxN Int
\* apalache-type: NP Int
\* apalache-type: D Int
\* apalache-type: INF Int
\* apalache-type: OnePage Str
\* apalache-type: Probe Str
\* apalache-type: Mutant Str
\* apalache-type: size Int -> Int
\* apalache-type: page Int -> (Int -> Int)
\* apalache-type: b Int
\* apalache-type: curr Int
\* apalache-type: phase Str
\* apalache-type: next Int
\* apalache-type: resident Set(Int)
\* apalache-type: served Int -> Set(Int)
\* apalache-type: hinted Set(Int)
\* apalache-type: lookedIn Int -> Int
\* apalache-type: orderOk Bool
\* apalache-type: boundsOk Bool

\* Apalache: the bounds of the main cfg (the ranges over them are constant ranges)
CInit ==
  /\ NB = 2
  /\ MaxN = 6
  /\ NP = 2
  /\ D = 4
  /\ INF = 100
  /\ OnePage = "ahead"
  /\ Probe = "racy"
  /\ Mutant = "none"

H == D \div 2
Pos == 0..(MaxN - 1)
Pages == 1..NP
Min(x, y) == IF x < y THEN x ELSE y
Max(x, y) == IF x > y THEN x ELSE y

VARIABLES size, page, b, curr, phase, next, resident, served, hinted, lookedIn, orderOk, boundsOk

vars == <<size, page, b, curr, phase, next, resident, served, hinted, lookedIn, orderOk, boundsOk>>

N == size[Max(b, 1)]

TypeOK ==
  /\ size \in [1..NB -> 1..MaxN]
  /\ page \in [1..NB -> [Pos -> Pages]]
  /\ b \in 0..NB
  /\ curr \in -1..MaxN
  /\ phase \in {"fill", "check", "look", "end"}
  /\ next \in 0..INF
  /\ resident \in SUBSET Pages
  /\ served \in [1..NB -> SUBSET Pos]
  /\ hinted \in SUBSET Pages
  /\ lookedIn \in [1..NB -> 0..MaxN]
  /\ orderOk \in BOOLEAN
  /\ boundsOk \in BOOLEAN

Init ==
  /\ size \in [1..NB -> 1..MaxN]
  /\ page \in [1..NB -> [Pos -> Pages]]
  /\ \A k \in 1..NB : \A i \in Pos : i >= size[k] => page[k][i] = 1
  /\ b = 0
  /\ curr = -1
  /\ phase = "fill"
  /\ next = INF
  /\ resident \in SUBSET Pages
  /\ served = [k \in 1..NB |-> {}]
  /\ hinted = {}
  /\ lookedIn = [k \in 1..NB |-> 0]
  /\ orderOk = TRUE
  /\ boundsOk = TRUE

\* call_get_next_index_oidset: the next OID buffer; a buffer of two or more OIDs is checked from its first OID
Fill ==
  /\ phase = "fill"
  /\ IF b = NB
       THEN /\ phase' = "end"
            /\ UNCHANGED <<b, curr, next>>
       ELSE /\ b' = b + 1
            /\ curr' = 0
            /\ phase' = "check"
            /\ next' = IF size[b + 1] > 1 THEN 0 ELSE INF
  /\ UNCHANGED <<size, page, resident, served, hinted, lookedIn, orderOk, boundsOk>>

\* scan_next_index_scan: the check before the lookup of curr, scan_index_read_ahead when it fires
\* racyAbsent: the pages a racy check finds absent (any set: the check takes no lock)
Check(racyAbsent) ==
  /\ phase = "check"
  /\ phase' = "look"
  /\ IF (IF Mutant = "late_trigger" THEN curr >= next ELSE curr + H >= next)
       THEN LET start == Max(next, curr)
                stop == IF Mutant = "no_count_bound" THEN curr + D ELSE Min(N, curr + D)
                win == {x \in Pos : start <= x /\ x < stop}
                wp == {page[b][i] : i \in win}
                own == {i \in win : page[b][i] = page[b][curr]}
                absent == IF Probe = "racy" THEN racyAbsent \cap wp ELSE wp \ resident
                skipped == Cardinality(wp) <= 1 /\ (OnePage = "skip" \/ start = curr)
            IN /\ boundsOk' = (boundsOk /\ 0 <= start /\ curr <= start /\ stop <= N /\ stop - start <= D)
               /\ next' = IF stop >= N THEN INF ELSE stop
               /\ IF skipped
                    THEN /\ served' = [served EXCEPT ![b] = @ \cup own]
                         /\ UNCHANGED <<hinted, curr>>
                    ELSE /\ served' = [served EXCEPT ![b] = @ \cup win]
                         /\ hinted' = hinted \cup absent
                         /\ curr' = IF Mutant = "cursor" THEN stop - 1 ELSE curr
       ELSE UNCHANGED <<next, served, hinted, boundsOk, curr>>
  /\ UNCHANGED <<size, page, b, resident, lookedIn, orderOk>>

\* scan_next_index_lookup_heap: pgbuf_fix of the OID's heap page, then the cursor moves on
Look ==
  /\ phase = "look"
  /\ orderOk' = (orderOk /\ curr = lookedIn[b] /\ \A k \in 1..NB : k < b => lookedIn[k] = size[k])
  /\ lookedIn' = [lookedIn EXCEPT ![b] = @ + 1]
  /\ resident' = resident \cup {page[b][curr]}
  /\ IF curr < N - 1
       THEN /\ curr' = curr + 1
            /\ phase' = "check"
       ELSE /\ phase' = "fill"
            /\ UNCHANGED curr
  /\ UNCHANGED <<size, page, b, next, served, hinted, boundsOk>>

\* other threads fix and victimize pages
Env ==
  /\ phase # "end"
  /\ resident' \in SUBSET Pages
  /\ resident' # resident
  /\ UNCHANGED <<size, page, b, curr, phase, next, served, hinted, lookedIn, orderOk, boundsOk>>

Done == phase = "end" /\ UNCHANGED vars

Next == Fill \/ (\E racyAbsent \in SUBSET Pages : Check(racyAbsent)) \/ Look \/ Env \/ Done

Spec == Init /\ [][Next]_vars

(* ---------------- claims ---------------- *)

\* C1: the lookups take the OIDs of every buffer once, in buffer order
LookupOrder == orderOk

\* C2: a window lies inside the buffer, starts at or after the current OID and holds at most D OIDs
WindowBound == boundsOk

\* C3: before the lookup of an OID of a buffer of two or more OIDs, every OID from it to H ahead was in a window
\* checked against the buffer, or is on the page being looked up
Lead ==
  (phase = "look" /\ N > 1) =>
    \A j \in Pos : (curr <= j /\ j <= Min(N - 1, curr + H)) => (j \in served[b] \/ page[b][j] = page[b][curr])

\* witness: a page is hinted
NotHinted == hinted = {}

\* the first OID of the buffer not yet in a checked window
Frontier == IF next = INF THEN N ELSE next

\* well-formedness: the cursor and the frontier inside the current buffer
CursorWf ==
  /\ phase \in {"check", "look"} => b >= 1 /\ curr >= 0 /\ curr < N
  /\ phase = "fill" => (b = 0 \/ curr = N - 1)
  /\ phase = "end" => b = NB
  /\ phase = "fill" /\ b = 0 => curr = -1

FrontierWf ==
  /\ phase \in {"check", "look"} /\ N = 1 => next = INF
  /\ phase \in {"check", "look"} /\ next # INF => next >= curr /\ next <= N
  /\ phase = "look" /\ N > 1 => (next = INF \/ next > curr + H)

\* every OID from the cursor to the frontier is in a checked window
ServedPrefix ==
  phase \in {"check", "look"} /\ N > 1 =>
    \A j \in Pos : (curr <= j /\ j < Frontier) => j \in served[b]

\* lookups so far: every earlier buffer whole, this one up to the cursor
LookedWf ==
  /\ \A k \in 1..NB : k < b => lookedIn[k] = size[k]
  /\ \A k \in 1..NB : k > b => lookedIn[k] = 0
  /\ phase = "check" => lookedIn[b] = curr
  /\ phase = "look" => lookedIn[b] = curr
  /\ phase = "fill" /\ b >= 1 => lookedIn[b] = size[b]
  /\ phase = "end" => lookedIn[b] = size[b]

PageWf == \A k \in 1..NB : \A i \in Pos : i >= size[k] => page[k][i] = 1

IndInv ==
  /\ TypeOK
  /\ PageWf
  /\ CursorWf
  /\ FrontierWf
  /\ LookedWf
  /\ ServedPrefix
  /\ LookupOrder
  /\ WindowBound
  /\ Lead

=============================================================================
