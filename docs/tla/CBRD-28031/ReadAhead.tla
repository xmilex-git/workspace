------------------------------ MODULE ReadAhead ------------------------------
(* CBRD-28031: the read-ahead hint of a serial index scan's heap lookups.
   One scan reads NB OID buffers in turn (call_get_next_index_oidset); before each lookup
   (scan_next_index_scan) it may check a window of the next OIDs (scan_index_read_ahead) and hand the
   window's heap pages that are not in the page buffer to the OS (pgbuf_read_ahead). Other threads
   load and evict pages at any time (Env). Positions are 0-based, as curr_oidno. *)
EXTENDS Integers, FiniteSets

CONSTANTS NB, MaxN, NP, D, W0, Carry, Single, INF, OnePage, Probe, Mutant
\* NB buffers of 1..MaxN OIDs, NP heap pages, window: the first one of a buffer holds W0 OIDs and every next one
\* twice the one before, up to D (the scan's ahead_limit: SCAN_INDEX_READ_AHEAD_DISTANCE for a serial scan, a share
\* of it for a parallel index scan worker, D18; W0 <= D); the next window is checked when half of the
\* current one was looked up (D13). Carry: "reset" (every OID buffer starts at W0) or "keep" (a buffer starts
\* from the distance the buffer before it reached; not taken), Single: the scan is the inner scan of a NL semi/anti
\* join (QPROC_SINGLE_INNER), which stops at its first match: its first OID's page is read at once and its windows
\* start after it, with 2 OIDs (D17),
\* INF for INT_MAX, OnePage: "skip" (every window of one page is left unchecked) or "ahead" (only a window
\* that starts at the current OID and holds one page is left unchecked), Probe: "locked" (each page looked up
\* in the buffer hash under the bucket mutex) or "racy" (no mutex: the answer may be wrong either way)

\* apalache-type: NB Int
\* apalache-type: MaxN Int
\* apalache-type: NP Int
\* apalache-type: D Int
\* apalache-type: W0 Int
\* apalache-type: Carry Str
\* apalache-type: Single Bool
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
\* apalache-type: dist Int
\* apalache-type: toldEnd Int -> Int

\* Apalache: the bounds of the main cfg (the ranges over them are constant ranges)
CInit ==
  /\ NB = 2
  /\ MaxN = 6
  /\ NP = 2
  /\ D = 4
  /\ W0 = 1
  /\ Carry = "reset"
  /\ Single \in BOOLEAN
  /\ INF = 100
  /\ OnePage = "ahead"
  /\ Probe = "racy"
  /\ Mutant = "none"

Pos == 0..(MaxN - 1)
Pages == 1..NP
Min(x, y) == IF x < y THEN x ELSE y
Max(x, y) == IF x > y THEN x ELSE y

ASSUME W0 <= D

VARIABLES size, page, b, curr, phase, next, resident, served, hinted, lookedIn, orderOk, boundsOk, dist, toldEnd

vars == <<size, page, b, curr, phase, next, resident, served, hinted, lookedIn, orderOk, boundsOk, dist, toldEnd>>

N == size[Max(b, 1)]
\* the lead of the current window: the next one is checked when this many OIDs of it are left
H == dist \div 2
\* the window after the current one
NextDist == IF Mutant = "fixed" THEN D ELSE IF dist = 0 THEN W0 ELSE IF Mutant = "no_distance_cap" THEN 2 * dist ELSE Min(2 * dist, D)

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
  /\ dist \in 0..D
  /\ toldEnd \in [1..NB -> 0..MaxN]

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
  /\ dist = 0
  /\ toldEnd = [k \in 1..NB |-> 0]

\* call_get_next_index_oidset: the next OID buffer; a buffer of two or more OIDs is checked from its first OID
Fill ==
  /\ phase = "fill"
  /\ IF b = NB
       THEN /\ phase' = "end"
            /\ UNCHANGED <<b, curr, next, dist, served, toldEnd>>
       ELSE /\ b' = b + 1
            /\ curr' = 0
            /\ phase' = "check"
            /\ IF Single /\ Mutant # "single_as_other" /\ size[b + 1] > 1
                 THEN \* the first OID is looked up at once: the windows start after it
                      /\ next' = 1
                      /\ dist' = 1
                      /\ served' = [served EXCEPT ![b + 1] = {0}]
                      /\ toldEnd' = [toldEnd EXCEPT ![b + 1] = 1]
                 ELSE /\ next' = IF size[b + 1] > 1 THEN 0 ELSE INF
                      /\ dist' = IF Carry = "keep" THEN dist ELSE 0
                      /\ UNCHANGED <<served, toldEnd>>
  /\ UNCHANGED <<size, page, resident, hinted, lookedIn, orderOk, boundsOk>>

\* scan_next_index_scan: the check before the lookup of curr, scan_index_read_ahead when it fires
\* racyAbsent: the pages a racy check finds absent (any set: the check takes no lock)
Check(racyAbsent) ==
  /\ phase = "check"
  /\ phase' = "look"
  /\ IF (IF Mutant = "late_trigger" THEN curr >= next ELSE curr + H >= next)
       THEN LET start == Max(next, curr)
                stop == IF Mutant = "no_count_bound" THEN curr + NextDist
                        ELSE IF Mutant = "eager_frontier" THEN Min(N, start + NextDist)
                        ELSE Min(N, curr + NextDist)
                win == {x \in Pos : start <= x /\ x < stop}
                wp == {page[b][i] : i \in win}
                own == {i \in win : page[b][i] = page[b][curr]}
                absent == IF Probe = "racy" THEN racyAbsent \cap wp ELSE wp \ resident
                skipped == Cardinality(wp) <= 1 /\ (OnePage = "skip" \/ start = curr)
            IN /\ boundsOk' = (boundsOk /\ 0 <= start /\ curr <= start /\ stop <= N /\ stop - start <= D)
               /\ next' = IF stop >= N THEN INF ELSE stop
               \* a window cut short by the buffer's end does not make the next one larger
               /\ dist' = IF curr + NextDist <= N THEN NextDist ELSE dist
               /\ toldEnd' = [toldEnd EXCEPT ![b] = Min(stop, MaxN)]
               /\ IF skipped
                    THEN /\ served' = [served EXCEPT ![b] = @ \cup own]
                         /\ UNCHANGED <<hinted, curr>>
                    ELSE /\ served' = [served EXCEPT ![b] = @ \cup win]
                         /\ hinted' = hinted \cup absent
                         /\ curr' = IF Mutant = "cursor" THEN stop - 1 ELSE curr
       ELSE UNCHANGED <<next, served, hinted, boundsOk, curr, dist, toldEnd>>
  /\ UNCHANGED <<size, page, b, resident, lookedIn, orderOk>>

\* scan_next_index_lookup_heap: pgbuf_fix of the OID's heap page, then the cursor moves on
Look ==
  /\ phase = "look"
  /\ orderOk' = (orderOk /\ curr = lookedIn[b])
  /\ lookedIn' = [lookedIn EXCEPT ![b] = @ + 1]
  /\ resident' = resident \cup {page[b][curr]}
  /\ IF curr < N - 1
       THEN /\ curr' = curr + 1
            /\ phase' = "check"
       ELSE /\ phase' = "fill"
            /\ UNCHANGED curr
  /\ UNCHANGED <<size, page, b, next, served, hinted, boundsOk, dist, toldEnd>>

\* the scan stops before the buffer's next lookup (the first match of a semi/anti join's inner scan, LIMIT, an
\* error or interrupt): its next buffer, if any, is filled by the next rescan
StopEarly ==
  /\ phase = "check"
  /\ phase' = "fill"
  /\ UNCHANGED <<size, page, b, curr, next, resident, served, hinted, lookedIn, orderOk, boundsOk, dist, toldEnd>>

\* other threads fix and victimize pages
Env ==
  /\ phase # "end"
  /\ resident' \in SUBSET Pages
  /\ resident' # resident
  /\ UNCHANGED <<size, page, b, curr, phase, next, served, hinted, lookedIn, orderOk, boundsOk, dist, toldEnd>>

Done == phase = "end" /\ UNCHANGED vars

Next == Fill \/ (\E racyAbsent \in SUBSET Pages : Check(racyAbsent)) \/ Look \/ StopEarly \/ Env \/ Done

Spec == Init /\ [][Next]_vars

(* ---------------- claims ---------------- *)

\* C1: the lookups take the OIDs of every buffer once, in buffer order (all of them unless the scan stops)
LookupOrder == orderOk

\* C2: a window lies inside the buffer, starts at or after the current OID and holds at most D OIDs
WindowBound == boundsOk

\* C3: before the lookup of an OID of a buffer of two or more OIDs, every OID from it to H ahead (half of the
\* current window) was in a window checked against the buffer, or is on the page being looked up
Lead ==
  (phase = "look" /\ N > 1) =>
    \A j \in Pos : (curr <= j /\ j <= Min(N - 1, curr + H)) => (j \in served[b] \/ page[b][j] = page[b][curr])

\* C16: a scan that stops after looking up k OIDs of a buffer has told the OS about at most 3k + W0 OIDs of it
\* (a first-match inner scan: 3k + 1)
First == IF Single THEN 1 ELSE W0
StopWaste == \A k \in 1..NB : toldEnd[k] <= 3 * lookedIn[k] + First

\* C17: the OIDs of a buffer the scan told the OS about and has not looked up yet are at most D (the window is
\* measured from the OID being looked up, not from the frontier)
Outstanding == \A k \in 1..NB : toldEnd[k] - lookedIn[k] <= D

\* witness: the windows run more than twice the lookups ahead (the bound of C16 is 3k + W0, not 2k + W0)
NotOver2k == \A k \in 1..NB : toldEnd[k] <= 2 * lookedIn[k] + First

\* witness: a page is hinted
NotHinted == hinted = {}

\* the first OID of the buffer not yet in a checked window
Frontier == IF next = INF THEN N ELSE next

\* well-formedness: the cursor and the frontier inside the current buffer
CursorWf ==
  /\ phase \in {"check", "look"} => b >= 1 /\ curr >= 0 /\ curr < N
  /\ phase = "fill" => (b = 0 \/ (curr >= 0 /\ curr <= N - 1))
  /\ phase = "end" => b = NB
  /\ phase = "fill" /\ b = 0 => curr = -1

FrontierWf ==
  /\ phase \in {"check", "look"} /\ N = 1 => next = INF
  /\ phase \in {"check", "look"} /\ next # INF => next >= curr /\ next <= N
  /\ phase = "look" /\ N > 1 => (next = INF \/ next > curr + H)
  /\ phase \in {"check", "look"} /\ next # INF => next <= curr + dist

\* every OID from the cursor to the frontier is in a checked window
ServedPrefix ==
  phase \in {"check", "look"} /\ N > 1 =>
    \A j \in Pos : (curr <= j /\ j < Frontier) => j \in served[b]

\* the windows of the current buffer end at the frontier; the distance stays small enough for the next window
ToldWf ==
  /\ \A k \in 1..NB : k > b => toldEnd[k] = 0
  /\ \A k \in 1..NB : toldEnd[k] <= size[k]
  /\ phase \in {"check", "look"} /\ next # INF => toldEnd[b] = next /\ 3 * dist <= 2 * next + First
  /\ phase \in {"check", "look"} /\ N = 1 => toldEnd[b] = 0

\* lookups so far: a prefix of every earlier buffer, this one up to the cursor
LookedWf ==
  /\ \A k \in 1..NB : lookedIn[k] <= size[k]
  /\ \A k \in 1..NB : k > b => lookedIn[k] = 0
  /\ phase = "check" => lookedIn[b] = curr
  /\ phase = "look" => lookedIn[b] = curr
  /\ phase = "fill" /\ b >= 1 => lookedIn[b] \in {curr, curr + 1}

PageWf == \A k \in 1..NB : \A i \in Pos : i >= size[k] => page[k][i] = 1

IndInv ==
  /\ TypeOK
  /\ PageWf
  /\ CursorWf
  /\ FrontierWf
  /\ LookedWf
  /\ ServedPrefix
  /\ ToldWf
  /\ LookupOrder
  /\ WindowBound
  /\ Lead
  /\ StopWaste
  /\ Outstanding

=============================================================================
