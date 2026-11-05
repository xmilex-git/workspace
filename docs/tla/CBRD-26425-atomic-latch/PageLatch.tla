----------------------------- MODULE PageLatch -----------------------------
(* The page latch of one buffer (BCB) as the page buffer promises it, without
   the encoding: a latch mode, the set of threads holding a fix, the
   waiter_exists bit, the threads queued for READ or WRITE, and the page the
   buffer holds. AtomicLatch.tla (the atomic-latch code of CBRD-26425) must
   refine this spec; IndInv is proved by TLAPS in PageLatch_proofs.tla. *)
EXTENDS Naturals, FiniteSets

CONSTANTS T, Pages
ASSUME PLAssm == T # {} /\ Pages # {}

VARIABLES mode, holders, bit, QR, QW, page
vars == <<mode, holders, bit, QR, QW, page>>

Modes == {"N", "R", "W"}

Init == /\ mode = "N" /\ holders = {} /\ bit = FALSE
        /\ QR = {} /\ QW = {} /\ page \in Pages

Waiting == QR \cup QW

\* a thread takes an idle latch (pgbuf_latch_bcb_upon_fix, idle page)
Acquire(t, m) == /\ mode = "N" /\ t \notin Waiting /\ m \in {"R", "W"}
                 /\ mode' = m /\ holders' = {t}
                 /\ UNCHANGED <<bit, QR, QW, page>>

\* a victimized buffer is claimed for another page and latched at once
EvictAcquire(t, m, p) == /\ mode = "N" /\ Waiting = {} /\ t \notin Waiting
                         /\ m \in {"R", "W"} /\ p \in Pages
                         /\ mode' = m /\ holders' = {t} /\ page' = p
                         /\ UNCHANGED <<bit, QR, QW>>

\* a reader joins a read latch: no waiter ahead of it, or it already holds a fix
Join(t) == /\ mode = "R" /\ t \notin Waiting /\ t \notin holders
           /\ ~bit
           /\ holders' = holders \cup {t}
           /\ UNCHANGED <<mode, bit, QR, QW, page>>

\* the single reader becomes the writer (in-place promotion)
Upgrade(t) == /\ mode = "R" /\ holders = {t}
              /\ mode' = "W"
              /\ UNCHANGED <<holders, bit, QR, QW, page>>

\* a holder drops its last fix; the latch goes idle with the last holder
Release(t) == /\ t \in holders
              /\ holders' = holders \ {t}
              /\ mode' = IF holders' = {} THEN "N" ELSE mode
              /\ UNCHANGED <<bit, QR, QW, page>>

\* a reader that must wait for WRITE gives its read fixes back and queues
ReleaseEnqueue(t) == /\ mode = "R" /\ t \in holders /\ holders # {t}
                     /\ holders' = holders \ {t} /\ QW' = QW \cup {t} /\ bit' = TRUE
                     /\ UNCHANGED <<mode, QR, page>>

Enqueue(t, m) == /\ t \notin holders /\ t \notin Waiting /\ mode # "N"
                 /\ bit' = TRUE
                 /\ IF m = "R" THEN QR' = QR \cup {t} /\ UNCHANGED QW
                               ELSE QW' = QW \cup {t} /\ UNCHANGED QR
                 /\ UNCHANGED <<mode, holders, page>>

\* a waiter is handed the latch by the thread that frees it
GrantR(t) == /\ t \in QR /\ mode \in {"N", "R"}
             /\ QR' = QR \ {t} /\ holders' = holders \cup {t} /\ mode' = "R"
             /\ UNCHANGED <<bit, QW, page>>
GrantW(t) == /\ t \in QW /\ mode = "N"
             /\ QW' = QW \ {t} /\ holders' = {t} /\ mode' = "W"
             /\ UNCHANGED <<bit, QR, page>>

\* a waiter gives up (latch timeout, interrupt)
Leave(t) == /\ t \in Waiting
            /\ QR' = QR \ {t} /\ QW' = QW \ {t}
            /\ UNCHANGED <<mode, holders, bit, page>>

\* the bit may be raised spuriously (conditional reject, flush waiter) ...
SetBit == /\ bit' = TRUE /\ UNCHANGED <<mode, holders, QR, QW, page>>
\* ... but cleared only when no reader or writer waits
ClearBit == /\ Waiting = {} /\ bit' = FALSE
            /\ UNCHANGED <<mode, holders, QR, QW, page>>

Next == \/ \E t \in T, m \in {"R", "W"} : Acquire(t, m) \/ Enqueue(t, m)
        \/ \E t \in T, m \in {"R", "W"}, p \in Pages : EvictAcquire(t, m, p)
        \/ \E t \in T : Join(t) \/ Upgrade(t) \/ Release(t) \/ ReleaseEnqueue(t)
                        \/ GrantR(t) \/ GrantW(t) \/ Leave(t)
        \/ SetBit \/ ClearBit

Spec == Init /\ [][Next]_vars

TypeOK == /\ mode \in Modes /\ holders \in SUBSET T /\ bit \in BOOLEAN
          /\ QR \in SUBSET T /\ QW \in SUBSET T /\ page \in Pages

\* C2: a write latch has exactly one holder; an idle latch has none
Exclusive == /\ (mode = "N") <=> (holders = {})
             /\ mode = "W" => \A s, u \in holders : s = u
\* C4: while a reader or writer waits, waiter_exists is set
WaiterBit == Waiting # {} => bit
\* a thread never both holds and waits
HoldOrWait == /\ holders \cap Waiting = {} /\ QR \cap QW = {}

IndInv == TypeOK /\ Exclusive /\ WaiterBit /\ HoldOrWait

\* witness: two readers share the latch
NotShared == Cardinality(holders) < 2
=============================================================================
