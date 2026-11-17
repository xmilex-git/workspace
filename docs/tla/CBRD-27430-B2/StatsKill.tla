------------------------------ MODULE StatsKill ------------------------------
(* CBRD-27430 B2: what another thread reads or reaches of a driver session.

   SHOW SESSION STATUS: a session's thread counts its work in its CAS slot (as_info), several fields per
   request, and at a request boundary copies them as one row into its registry binding under the binding's
   control_mutex. A reader takes registry_mutex and copies each binding's row under control_mutex. It never
   reads a session thread's slot.

   An administrative kill of a transaction: css_shutdown_conn_by_tran_index calls registry_shutdown_session,
   which holds registry_mutex over the registry and pins each binding (binding_pin: users + 1 under the
   binding's mutex unless the session is closing; the pin carries the binding's transaction index and
   descriptor) and shuts down the read side of the descriptor of the session that has the transaction. The
   session's cleanup marks the binding closing, waits until no pin is left, erases its entry under
   registry_mutex and only then closes its descriptor, whose number the next accepted connection may get.

   Roles: NS session threads (each: one connection after another is not modeled; a session ends once),
   one reader, one killer.

   Constants:
     NS, MaxReq  sessions, requests per session
     NF          descriptor numbers
     Mutant      "none" | "read_slot" | "unpinned_unlocked" *)
EXTENDS Naturals, FiniteSets

CONSTANTS NS, MaxReq, NF, Mutant

\* apalache-type: NS Int
\* apalache-type: MaxReq Int
\* apalache-type: NF Int
\* apalache-type: Mutant Str
\* apalache-type: pc Int -> Str
\* apalache-type: sa Int -> Int
\* apalache-type: sb Int -> Int
\* apalache-type: ra Int -> Int
\* apalache-type: rb Int -> Int
\* apalache-type: pub Int -> Bool
\* apalache-type: reg Int -> Bool
\* apalache-type: fd Int -> Int
\* apalache-type: owner Int -> Int
\* apalache-type: bfd Int -> Int
\* apalache-type: users Int -> Int
\* apalache-type: closing Int -> Bool
\* apalache-type: rlock Str
\* apalache-type: rpc Str
\* apalache-type: rs Int
\* apalache-type: ga Int
\* apalache-type: gb Int
\* apalache-type: kpc Str
\* apalache-type: ks Int
\* apalache-type: kfd Int
\* apalache-type: badShut Bool
\* apalache-type: shuts Int

\* pc: per session: "none" | "run" | "mid" | "bound" | "drain" | "erase" | "close" | "done"
\* sa, sb: per session: two counters of its CAS slot, equal at every request boundary
\* ra, rb, pub: per session: the row in its binding, and whether one was published
\* reg: per session: its entry is in the registry
\* fd: per session: its connection's descriptor number, 0 when it has none
\* owner: per descriptor number: the session whose open connection it is, 0 when closed
\* bfd, users, closing: per session binding: client_fd (0 when cleared), pins, closing
\* rlock: registry_mutex: "free" | "reader" | "killer" | "sess"
\* rpc, rs, ga, gb: the reader: "idle" | "scan" | "half" (mutant), the session it is at, its copy
\* kpc, ks, kfd: the killer: "idle" | "scan" | "pinned", the session it pinned, the descriptor
\* badShut, shuts: a shutdown reached a descriptor that is not the pinned session's open one
VARIABLES pc, sa, sb, ra, rb, pub, reg, fd, owner, bfd, users, closing, rlock, rpc, rs, ga, gb, kpc, ks,
          kfd, badShut, shuts

vars == <<pc, sa, sb, ra, rb, pub, reg, fd, owner, bfd, users, closing, rlock, rpc, rs, ga, gb, kpc, ks, kfd,
          badShut, shuts>>

S == 1..NS
F == 1..NF

\* @type: <<Int -> Int, Int -> Int>>;
slotVars == <<sa, sb>>
rowVars == <<ra, rb, pub>>
\* @type: <<Int -> Int, Int -> Int>>;
fdVars == <<fd, owner>>
bindVars == <<bfd, users, closing>>
readerVars == <<rpc, rs, ga, gb>>
killerVars == <<kpc, ks, kfd, badShut, shuts>>

Init ==
  /\ pc = [s \in S |-> "none"]
  /\ sa = [s \in S |-> 0] /\ sb = [s \in S |-> 0]
  /\ ra = [s \in S |-> 0] /\ rb = [s \in S |-> 0] /\ pub = [s \in S |-> FALSE]
  /\ reg = [s \in S |-> FALSE]
  /\ fd = [s \in S |-> 0]
  /\ owner = [f \in F |-> 0]
  /\ bfd = [s \in S |-> 0] /\ users = [s \in S |-> 0] /\ closing = [s \in S |-> FALSE]
  /\ rlock = "free"
  /\ rpc = "idle" /\ rs = 1 /\ ga = 0 /\ gb = 0
  /\ kpc = "idle" /\ ks = 1 /\ kfd = 0
  /\ badShut = FALSE /\ shuts = 0

(* ---- a session ---- *)

\* the broker's connection is accepted on a free descriptor number and handed over (handle_handoff registers
\* the binding under registry_mutex)
SNew(s, f) ==
  /\ pc[s] = "none" /\ owner[f] = 0 /\ rlock = "free"
  /\ owner' = [owner EXCEPT ![f] = s] /\ fd' = [fd EXCEPT ![s] = f]
  /\ bfd' = [bfd EXCEPT ![s] = f]
  /\ reg' = [reg EXCEPT ![s] = TRUE]
  /\ pc' = [pc EXCEPT ![s] = "bound"]
  /\ UNCHANGED <<slotVars, rowVars, users, closing, rlock, readerVars, killerVars>>

\* registry_publish_stats under control_mutex: the slot's counters as one row.  The request loop publishes after
\* every return of cas_process_request, the one that found the connection closed too.
SPublish(s) ==
  /\ pc[s] \in {"bound", "run"}
  /\ ra' = [ra EXCEPT ![s] = sa[s]] /\ rb' = [rb EXCEPT ![s] = sb[s]] /\ pub' = [pub EXCEPT ![s] = TRUE]
  /\ pc' = [pc EXCEPT ![s] = "run"]
  /\ UNCHANGED <<slotVars, reg, fdVars, bindVars, rlock, readerVars, killerVars>>

\* a request counts in the slot: one field, then another
SReqA(s) ==
  /\ pc[s] = "run" /\ sa[s] < MaxReq
  /\ sa' = [sa EXCEPT ![s] = sa[s] + 1]
  /\ pc' = [pc EXCEPT ![s] = "mid"]
  /\ UNCHANGED <<sb, rowVars, reg, fdVars, bindVars, rlock, readerVars, killerVars>>

SReqB(s) ==
  /\ pc[s] = "mid"
  /\ sb' = [sb EXCEPT ![s] = sb[s] + 1]
  /\ pc' = [pc EXCEPT ![s] = "bound"]
  /\ UNCHANGED <<sa, rowVars, reg, fdVars, bindVars, rlock, readerVars, killerVars>>

\* the connection ends (the client left, the kill's shutdown, or a login that failed before the first row):
\* registry_begin_session_cleanup marks closing
SCleanup(s) ==
  /\ pc[s] \in {"bound", "run"}
  /\ closing' = [closing EXCEPT ![s] = TRUE]
  /\ pc' = [pc EXCEPT ![s] = "drain"]
  /\ UNCHANGED <<slotVars, rowVars, reg, fdVars, bfd, users, rlock, readerVars, killerVars>>

\* ... and waits until no pin is left, then clears the binding's descriptor
SDrain(s) ==
  /\ pc[s] = "drain" /\ users[s] = 0
  /\ bfd' = [bfd EXCEPT ![s] = 0]
  /\ pc' = [pc EXCEPT ![s] = "erase"]
  /\ UNCHANGED <<slotVars, rowVars, reg, fdVars, users, closing, rlock, readerVars, killerVars>>

\* registry_session_finished erases the entry under registry_mutex
SErase(s) ==
  /\ pc[s] = "erase" /\ rlock = "free"
  /\ reg' = [reg EXCEPT ![s] = FALSE]
  /\ pc' = [pc EXCEPT ![s] = "close"]
  /\ UNCHANGED <<slotVars, rowVars, fdVars, bindVars, rlock, readerVars, killerVars>>

\* close (client_fd): the number is free for the next connection
SClose(s) ==
  /\ pc[s] = "close"
  /\ owner' = [owner EXCEPT ![fd[s]] = 0]
  /\ fd' = [fd EXCEPT ![s] = 0]
  /\ pc' = [pc EXCEPT ![s] = "done"]
  /\ UNCHANGED <<slotVars, rowVars, reg, bindVars, rlock, readerVars, killerVars>>

(* ---- the reader: registry_stats_snapshot ---- *)

RBegin ==
  /\ rpc = "idle" /\ rlock = "free"
  /\ rlock' = "reader" /\ rpc' = "scan"
  /\ UNCHANGED <<pc, slotVars, rowVars, reg, fdVars, bindVars, rs, ga, gb, killerVars>>

\* one binding's row under control_mutex
RRow(s) ==
  /\ rpc = "scan" /\ reg[s] /\ pub[s]
  /\ rs' = s
  /\ IF Mutant = "read_slot"
       THEN ga' = sa[s] /\ UNCHANGED gb /\ rpc' = "half"
       ELSE ga' = ra[s] /\ gb' = rb[s] /\ UNCHANGED rpc
  /\ UNCHANGED <<pc, slotVars, rowVars, reg, fdVars, bindVars, rlock, killerVars>>

\* mutant: the slot's second field, read after the first with the session's thread running
RSlotB ==
  /\ rpc = "half"
  /\ gb' = sb[rs] /\ rpc' = "scan"
  /\ UNCHANGED <<pc, slotVars, rowVars, reg, fdVars, bindVars, rlock, rs, ga, killerVars>>

REnd ==
  /\ rpc = "scan"
  /\ rlock' = "free" /\ rpc' = "idle"
  /\ UNCHANGED <<pc, slotVars, rowVars, reg, fdVars, bindVars, rs, ga, gb, killerVars>>

(* ---- the killer: registry_shutdown_session ---- *)

Locked == Mutant # "unpinned_unlocked"

KBegin ==
  /\ kpc = "idle"
  /\ IF Locked THEN rlock = "free" /\ rlock' = "killer" ELSE UNCHANGED rlock
  /\ kpc' = "scan"
  /\ UNCHANGED <<pc, slotVars, rowVars, reg, fdVars, bindVars, readerVars, ks, kfd, badShut, shuts>>

\* binding_pin of the session that has the transaction: users + 1 unless closing, and the descriptor copied
KPin(s) ==
  /\ kpc = "scan" /\ reg[s] /\ bfd[s] # 0 /\ shuts < NS
  /\ IF Locked
       THEN ~closing[s] /\ users' = [users EXCEPT ![s] = users[s] + 1]
       ELSE UNCHANGED users
  /\ ks' = s /\ kfd' = bfd[s]
  /\ kpc' = "pinned"
  /\ UNCHANGED <<pc, slotVars, rowVars, reg, fdVars, bfd, closing, rlock, readerVars, badShut, shuts>>

\* shutdown (pin.client_fd, SHUT_RD), then the pin is dropped
KShut ==
  /\ kpc = "pinned"
  /\ badShut' = (badShut \/ owner[kfd] # ks)
  /\ shuts' = shuts + 1
  /\ IF Locked THEN users' = [users EXCEPT ![ks] = users[ks] - 1] ELSE UNCHANGED users
  /\ kpc' = "scan"
  /\ UNCHANGED <<pc, slotVars, rowVars, reg, fdVars, bfd, closing, rlock, readerVars, ks, kfd>>

KEnd ==
  /\ kpc = "scan"
  /\ IF Locked THEN rlock' = "free" ELSE UNCHANGED rlock
  /\ kpc' = "idle"
  /\ UNCHANGED <<pc, slotVars, rowVars, reg, fdVars, bindVars, readerVars, ks, kfd, badShut, shuts>>

Next ==
  \/ \E s \in S, f \in F : SNew(s, f)
  \/ \E s \in S : SPublish(s) \/ SReqA(s) \/ SReqB(s) \/ SCleanup(s) \/ SDrain(s) \/ SErase(s) \/ SClose(s)
  \/ RBegin \/ RSlotB \/ REnd \/ \E s \in S : RRow(s)
  \/ KBegin \/ KShut \/ KEnd \/ \E s \in S : KPin(s)

Spec == Init /\ [][Next]_vars

Pcs == {"none", "run", "mid", "bound", "drain", "erase", "close", "done"}

TypeOK ==
  /\ pc \in [S -> Pcs]
  /\ sa \in [S -> 0..MaxReq] /\ sb \in [S -> 0..MaxReq] /\ ra \in [S -> 0..MaxReq] /\ rb \in [S -> 0..MaxReq]
  /\ pub \in [S -> BOOLEAN] /\ reg \in [S -> BOOLEAN]
  /\ fd \in [S -> 0..NF] /\ bfd \in [S -> 0..NF]
  /\ users \in [S -> 0..1] /\ closing \in [S -> BOOLEAN]
  /\ owner \in [F -> 0..NS]
  /\ rlock \in {"free", "reader", "killer"}
  /\ rpc \in {"idle", "scan", "half"} /\ rs \in S /\ ga \in 0..MaxReq /\ gb \in 0..MaxReq
  /\ kpc \in {"idle", "scan", "pinned"} /\ ks \in S /\ kfd \in 0..NF
  /\ badShut \in BOOLEAN /\ shuts \in 0..NS

\* C4: a row SHOW SESSION STATUS reads is one publication: the counters of one request boundary
RowWhole == rpc # "half" => ga = gb

\* the binding's row is one publication too
RowPublished == \A s \in S : ra[s] = rb[s]

\* C8: a kill shuts down only the open descriptor of the session it pinned
KillRight == ~badShut

\* the descriptor table and the sessions agree
FdConsistent ==
  /\ \A s \in S : fd[s] # 0 => owner[fd[s]] = s
  /\ \A f \in F : owner[f] # 0 => fd[owner[f]] = f
  /\ \A s \in S : bfd[s] # 0 => bfd[s] = fd[s]

(* ---- the inductive invariant ---- *)

\* the slot's two counters are equal except inside a request
SlotWf == \A s \in S : IF pc[s] = "mid" THEN sa[s] = sb[s] + 1 ELSE sa[s] = sb[s]

\* what a session has at each place of its life
SessionWf ==
  \A s \in S :
    /\ reg[s] <=> pc[s] \in {"bound", "run", "mid", "drain", "erase"}
    /\ fd[s] # 0 <=> pc[s] \in {"bound", "run", "mid", "drain", "erase", "close"}
    /\ bfd[s] # 0 <=> pc[s] \in {"bound", "run", "mid", "drain"}
    /\ closing[s] <=> pc[s] \in {"drain", "erase", "close", "done"}

\* registry_mutex is the reader's or the killer's while they scan
LockWf ==
  /\ rlock = "reader" <=> rpc # "idle"
  /\ rlock = "killer" <=> kpc # "idle"
  /\ rpc # "half"

\* the killer's pin: the pinned session is registered and its descriptor is the one the pin carries
PinWf ==
  /\ \A s \in S : users[s] = IF kpc = "pinned" /\ ks = s THEN 1 ELSE 0
  /\ kpc = "pinned" => reg[ks] /\ bfd[ks] # 0 /\ kfd = bfd[ks] /\ shuts < NS

IndInv ==
  /\ TypeOK
  /\ SlotWf
  /\ SessionWf
  /\ LockWf
  /\ PinWf
  /\ FdConsistent
  /\ RowPublished
  /\ RowWhole
  /\ KillRight

CInit == NS = 2 /\ MaxReq = 2 /\ NF = 2 /\ Mutant = "none"

\* witnesses
NotRead == ~(rpc = "scan" /\ ga = MaxReq /\ MaxReq > 0)
NotKilled == shuts = 0
NotFdReused == ~(\E s \in S, t \in S : s # t /\ pc[s] = "done" /\ pc[t] = "run")
NotKillWaited == ~(\E s \in S : pc[s] = "drain" /\ users[s] > 0)

=============================================================================
