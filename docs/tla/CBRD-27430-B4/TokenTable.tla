------------------------------ MODULE TokenTable ------------------------------
(* CBRD-27430 B4: one broker in front of several databases.

   A session's token is the kernel thread id of its thread. No two live threads of the host share one, but an
   id is free again when its thread ends, so a session of another server may get it while the broker still
   holds the first session's entry (its SESSION_END unread, or its server gone and the channel's death not
   seen yet), and so may a later session of the same server. The model lets a server give a new session any
   token none of its live sessions has, which makes equal tokens the common case instead of the rare one. The broker keeps one token table and one slot count
   (MAX_NUM_APPL_SERVER) for all databases; an entry belongs to the channel that admitted it. A database's SESSION_END, its channel's death and
   a query cancel must reach that database's entry only, and the slot count must bound the broker's sessions
   over all databases, also after the broker restarted and before a client asked for some database again.

   The wire order of one channel (HANDOFF_ACK, SESSION_END, RESYNC_REPLY as its reader applies them), the
   channel generations of one database and the descriptor lifetimes are the B1a model (Handoff.tla). Here a
   server's message reaches the broker in the step that sends it when the database's channel is in sync, and
   one database has one channel at a time.

   Roles: the broker's dispatch thread (one job at a time), its receiver's cancel helper, ND servers, the
   environment (crash, restart, a server that does not answer, a channel the broker gives up, broker restart).

   Constants:
     ND, NT, NP   databases, token values, client ports
     NSid         session ids a server gives (0 = a driver below PROTOCOL_V13: no id is asked of it)
     MaxSlots     MAX_NUM_APPL_SERVER
     Max*         bounds of the environment
     Mutant       "none" | "no_scan" | "map_overwrite" | "end_any_db" | "drop_all" | "cancel_first"
                  | "no_sid_check" | "no_port_check" *)
EXTENDS Integers, FiniteSets

CONSTANTS ND, NT, NP, NSid, MaxSlots, MaxConn, MaxCrash, MaxBR, MaxKill, MaxHang, MaxCancel, Mutant

\* apalache-type: ND Int
\* apalache-type: NT Int
\* apalache-type: NP Int
\* apalache-type: NSid Int
\* apalache-type: MaxSlots Int
\* apalache-type: MaxConn Int
\* apalache-type: MaxCrash Int
\* apalache-type: MaxBR Int
\* apalache-type: MaxKill Int
\* apalache-type: MaxHang Int
\* apalache-type: MaxCancel Int
\* apalache-type: Mutant Str
\* apalache-type: sport Int -> (Int -> Int)
\* apalache-type: ssid Int -> (Int -> Int)
\* apalache-type: up Int -> Bool
\* apalache-type: ans Int -> Bool
\* apalache-type: sinc Int -> Int
\* apalache-type: ch Int -> Bool
\* apalache-type: chinc Int -> Int
\* apalache-type: chgen Int -> Int
\* apalache-type: gen Int
\* apalache-type: tb Int -> (Int -> Int)
\* apalache-type: slots Int
\* apalache-type: pending Bool
\* apalache-type: lost Int -> Bool
\* apalache-type: todo Set(Int)
\* apalache-type: dpc Str
\* apalache-type: ddb Int
\* apalache-type: dport Int
\* apalache-type: cpc Str
\* apalache-type: ctd Int
\* apalache-type: ctok Int
\* apalache-type: cgen Int
\* apalache-type: cport Int
\* apalache-type: csid Int
\* apalache-type: wrongCancel Bool
\* apalache-type: overCap Bool
\* apalache-type: refused Bool
\* apalache-type: hit Bool
\* apalache-type: ambPick Bool
\* apalache-type: nconn Int
\* apalache-type: ncr Int
\* apalache-type: nbr Int
\* apalache-type: nk Int
\* apalache-type: nh Int
\* apalache-type: ncan Int

\* servers
\*   sport[d][t]  client port of the live session with token t of database d's server, 0 when none
\*   ssid[d][t]   its session id (0: a driver that is asked for none)
\*   up[d]        the server listens on its adoption socket;  ans[d]: it answers a HELLO
\*   sinc[d]      the server's incarnation
\* broker
\*   ch[d]        a channel to database d is in the map (not dead)
\*   chinc[d]     the server incarnation it was dialed to;  chgen[d]: its generation;  gen: the last generation
\*   tb[d][t]     the token table's entry (token t, admitted by d's channel): the client port, 0 when none
\*   slots        slots_used
\*   pending      a channel died or the broker started: the servers must be asked again before a slot is given
\*   lost[d]      the broker gave up d's server while it was listening (reply timeout, a dial not answered)
\*   todo         databases the running scan has not asked yet
\*   dpc, ddb, dport   the dispatch thread: "idle" | "scan" | "dial" | "wait" | "send", its job's database, port
\*   cpc ...      the cancel helper: "idle" | "look", and the entry it looked up (database, token, generation)
\*                with the port and session id of the request
\* ghosts: wrongCancel, overCap, refused (an ambiguous cancel was refused), hit (a cancel interrupted a session),
\*         ambPick (a cancel was sent on one of several entries its request matched)
VARIABLES sport, ssid, up, ans, sinc, ch, chinc, chgen, gen, tb, slots, pending, lost, todo, dpc, ddb, dport,
          cpc, ctd, ctok, cgen, cport, csid, wrongCancel, overCap, refused, hit, ambPick, nconn, ncr, nbr, nk, nh, ncan

srv == <<sport, ssid, up, ans, sinc>>
chn == <<ch, chinc, chgen, gen>>
dsp == <<dpc, ddb, dport>>
can == <<cpc, ctd, ctok, cgen, cport, csid>>
\* @type: <<Bool, Bool, Bool, Bool, Bool>>;
gho == <<wrongCancel, overCap, refused, hit, ambPick>>
\* @type: <<Int, Int, Int, Int, Int, Int>>;
cnt == <<nconn, ncr, nbr, nk, nh, ncan>>
vars == <<srv, chn, tb, slots, pending, lost, todo, dsp, can, gho, cnt>>

D == 1..ND
T == 1..NT
P == 1..NP

Zero == [t \in T |-> 0]
\* @type: (Int -> Int) => Int;
Cnt(f) == Cardinality({t \in T : f[t] # 0})
InSync(d) == ch[d] /\ up[d] /\ chinc[d] = sinc[d]
\* the broker's sessions on the servers it has not given up
TrueCnt == Cardinality({x \in D \X T : ~lost[x[1]] /\ sport[x[1]][x[2]] # 0})

Init ==
  /\ sport = [d \in D |-> Zero] /\ ssid = [d \in D |-> Zero]
  /\ up = [d \in D |-> TRUE] /\ ans = [d \in D |-> TRUE] /\ sinc = [d \in D |-> 0]
  /\ ch = [d \in D |-> FALSE] /\ chinc = [d \in D |-> 0] /\ chgen = [d \in D |-> 0] /\ gen = 0
  /\ tb = [d \in D |-> Zero] /\ slots = 0 /\ pending = TRUE /\ lost = [d \in D |-> FALSE] /\ todo = {}
  /\ dpc = "idle" /\ ddb = 1 /\ dport = 1
  /\ cpc = "idle" /\ ctd = 1 /\ ctok = 1 /\ cgen = 0 /\ cport = 0 /\ csid = 0
  /\ wrongCancel = FALSE /\ overCap = FALSE /\ refused = FALSE /\ hit = FALSE /\ ambPick = FALSE
  /\ nconn = 0 /\ ncr = 0 /\ nbr = 0 /\ nk = 0 /\ nh = 0 /\ ncan = 0

\* tokens_admit of every entry of a RESYNC_REPLY (e's table is empty: its last channel's death dropped it).
\* mutant map_overwrite: a map keyed by the token alone, an equal token of another database is replaced
AdmitAll(e) ==
  [d \in D |-> [t \in T |-> IF d = e THEN sport[e][t]
                            ELSE IF Mutant = "map_overwrite" /\ sport[e][t] # 0 THEN 0 ELSE tb[d][t]]]

\* channel_get_or_dial: connect, HELLO, RESYNC; the reader admits the snapshot
Dial(e) ==
  /\ ch' = [ch EXCEPT ![e] = TRUE] /\ chinc' = [chinc EXCEPT ![e] = sinc[e]]
  /\ gen' = gen + 1 /\ chgen' = [chgen EXCEPT ![e] = gen + 1]
  /\ tb' = AdmitAll(e) /\ slots' = slots + Cnt(sport[e])
  /\ lost' = [lost EXCEPT ![e] = FALSE]

\* a database with no channel is asked, when its server listens and answers; one that listens and does not
\* answer is given up; a socket nobody listens on is a server that stopped
Ask(e) ==
  IF up[e] /\ ans[e] THEN Dial(e)
  ELSE /\ lost' = [lost EXCEPT ![e] = up[e]] /\ UNCHANGED <<chn, tb, slots>>

\* the channel's death: tokens_drop_for_channel.  mutant drop_all: every database's entries go
Death(e) ==
  /\ ch' = [ch EXCEPT ![e] = FALSE]
  /\ tb' = IF Mutant = "drop_all" THEN [d \in D |-> Zero] ELSE [tb EXCEPT ![e] = Zero]
  /\ slots' = IF Mutant = "drop_all" THEN 0 ELSE slots - Cnt(tb[e])
  /\ pending' = TRUE
  /\ UNCHANGED <<chinc, chgen, gen>>

(* ---- the dispatch thread ---- *)

\* brd_dispatch_job takes a job; the flag is read and cleared together
DStart(d, p) ==
  /\ dpc = "idle" /\ nconn < MaxConn
  /\ \A e \in D, t \in T : sport[e][t] # p
  /\ ddb' = d /\ dport' = p /\ nconn' = nconn + 1
  /\ IF pending /\ Mutant # "no_scan"
       THEN dpc' = "scan" /\ todo' = D /\ pending' = FALSE
       ELSE dpc' = "dial" /\ UNCHANGED <<todo, pending>>
  /\ UNCHANGED <<srv, chn, tb, slots, lost, can, gho, ncr, nbr, nk, nh, ncan>>

\* the scan of the adoption sockets: one database per step
DScan(e) ==
  /\ dpc = "scan" /\ e \in todo
  /\ todo' = todo \ {e}
  /\ IF ch[e] THEN UNCHANGED <<chn, tb, slots, lost>> ELSE Ask(e)
  /\ UNCHANGED <<srv, pending, dsp, can, gho, cnt>>

DScanEnd ==
  /\ dpc = "scan" /\ todo = {}
  /\ dpc' = "dial"
  /\ UNCHANGED <<srv, chn, tb, slots, pending, lost, todo, ddb, dport, can, gho, cnt>>

\* the job's own database: no channel and no answer is the retryable rejection
DDial ==
  /\ dpc = "dial"
  /\ IF ch[ddb] THEN dpc' = "wait" /\ UNCHANGED <<chn, tb, slots, lost>>
     ELSE /\ Ask(ddb)
          /\ dpc' = IF up[ddb] /\ ans[ddb] THEN "wait" ELSE "idle"
  /\ UNCHANGED <<srv, pending, todo, ddb, dport, can, gho, cnt>>

\* brd_wait_for_slot
DWait ==
  /\ dpc = "wait" /\ slots < MaxSlots
  /\ dpc' = "send"
  /\ UNCHANGED <<srv, chn, tb, slots, pending, lost, todo, ddb, dport, can, gho, cnt>>

\* the admission budget ran out
DGiveUp ==
  /\ dpc = "wait"
  /\ dpc' = "idle"
  /\ UNCHANGED <<srv, chn, tb, slots, pending, lost, todo, ddb, dport, can, gho, cnt>>

\* HANDOFF; the server registers the session under its thread's id (any token no live session of this server
\* has) and the reader admits the ACK
DSendOk(t, sid) ==
  /\ dpc = "send" /\ InSync(ddb) /\ sport[ddb][t] = 0
  /\ sport' = [sport EXCEPT ![ddb][t] = dport] /\ ssid' = [ssid EXCEPT ![ddb][t] = sid]
  /\ tb' = [d \in D |-> [u \in T |-> IF d = ddb /\ u = t THEN dport
                                     ELSE IF Mutant = "map_overwrite" /\ u = t THEN 0 ELSE tb[d][u]]]
  /\ slots' = slots + 1
  /\ overCap' = (overCap \/ TrueCnt >= MaxSlots)
  /\ dpc' = "idle"
  /\ UNCHANGED <<up, ans, sinc, chn, pending, lost, todo, ddb, dport, can, wrongCancel, refused, hit, ambPick, cnt>>

\* the server refuses (capacity, shutdown), or the channel died since the dial
DSendNo ==
  /\ dpc = "send" /\ (InSync(ddb) \/ ~ch[ddb])
  /\ dpc' = "idle"
  /\ UNCHANGED <<srv, chn, tb, slots, pending, lost, todo, ddb, dport, can, gho, cnt>>

\* the HANDOFF written to a server that is gone: the request fails and kills the channel
DSendDead ==
  /\ dpc = "send" /\ ch[ddb] /\ ~InSync(ddb)
  /\ Death(ddb) /\ dpc' = "idle"
  /\ UNCHANGED <<srv, lost, todo, ddb, dport, can, gho, cnt>>

(* ---- the servers ---- *)

\* a session ends: SESSION_END on the database's channel; tokens_end erases this channel's entry of the token.
\* mutant end_any_db: the first entry with the token value, whatever channel admitted it
SEnd(e, t) ==
  /\ sport[e][t] # 0
  /\ sport' = [sport EXCEPT ![e][t] = 0] /\ ssid' = [ssid EXCEPT ![e][t] = 0]
  /\ IF InSync(e)
       THEN IF Mutant = "end_any_db"
              THEN \/ \E f \in D : tb[f][t] # 0 /\ tb' = [tb EXCEPT ![f][t] = 0] /\ slots' = slots - 1
                   \/ (\A f \in D : tb[f][t] = 0) /\ UNCHANGED tb /\ UNCHANGED slots
              ELSE IF tb[e][t] # 0 THEN tb' = [tb EXCEPT ![e][t] = 0] /\ slots' = slots - 1
                   ELSE UNCHANGED tb /\ UNCHANGED slots
       ELSE UNCHANGED tb /\ UNCHANGED slots
  /\ UNCHANGED <<up, ans, sinc, chn, pending, lost, todo, dsp, can, gho, cnt>>

SCrash(e) ==
  /\ up[e] /\ ncr < MaxCrash
  /\ sport' = [sport EXCEPT ![e] = Zero] /\ ssid' = [ssid EXCEPT ![e] = Zero]
  /\ up' = [up EXCEPT ![e] = FALSE] /\ ncr' = ncr + 1
  /\ UNCHANGED <<ans, sinc, chn, tb, slots, pending, lost, todo, dsp, can, gho, nconn, nbr, nk, nh, ncan>>

SRestart(e) ==
  /\ ~up[e]
  /\ up' = [up EXCEPT ![e] = TRUE] /\ ans' = [ans EXCEPT ![e] = TRUE]
  /\ sinc' = [sinc EXCEPT ![e] = sinc[e] + 1]
  /\ UNCHANGED <<sport, ssid, chn, tb, slots, pending, lost, todo, dsp, can, gho, cnt>>

\* a server stops answering, or answers again
Hang(e) ==
  /\ up[e] /\ nh < MaxHang
  /\ ans' = [ans EXCEPT ![e] = ~ans[e]] /\ nh' = nh + 1
  /\ UNCHANGED <<sport, ssid, up, sinc, chn, tb, slots, pending, lost, todo, dsp, can, gho, nconn, ncr, nbr, nk, ncan>>

(* ---- the broker's channels ---- *)

\* the reader's recv fails: the server is gone
RDie(e) ==
  /\ ch[e] /\ ~InSync(e)
  /\ Death(e)
  /\ UNCHANGED <<srv, lost, todo, dsp, can, gho, cnt>>

\* the broker gives a channel up (a reply timeout), or the server closes it: the server's sessions go on
Kill(e) ==
  /\ ch[e] /\ nk < MaxKill
  /\ Death(e) /\ lost' = [lost EXCEPT ![e] = up[e]] /\ nk' = nk + 1
  /\ UNCHANGED <<srv, todo, dsp, can, gho, nconn, ncr, nbr, nh, ncan>>

\* the broker process restarts: its table is gone, the sessions stay
BRestart ==
  /\ nbr < MaxBR
  /\ ch' = [d \in D |-> FALSE] /\ tb' = [d \in D |-> Zero] /\ slots' = 0
  /\ pending' = TRUE /\ lost' = [d \in D |-> FALSE] /\ todo' = {}
  /\ dpc' = "idle" /\ cpc' = "idle" /\ nbr' = nbr + 1
  /\ UNCHANGED <<srv, chinc, chgen, gen, ddb, dport, ctd, ctok, cgen, cport, csid, gho, nconn, ncr, nk, nh, ncan>>

(* ---- query cancel ---- *)

\* brd_token_channel: the entries of the token whose port is the request's (a request without a port: any).
\* More than one is no answer.  mutant cancel_first: the first of them
CnLook(t, q, s) ==
  /\ cpc = "idle" /\ ncan < MaxCancel
  /\ LET cands == {e \in D : tb[e][t] # 0 /\ (q = 0 \/ tb[e][t] = q)} IN
       \/ /\ cands # {} /\ (Cardinality(cands) = 1 \/ Mutant = "cancel_first")
          /\ \E e \in cands : ctd' = e /\ cgen' = chgen[e]
          /\ cpc' = "look" /\ ctok' = t /\ cport' = q /\ csid' = s
          /\ ambPick' = (ambPick \/ Cardinality(cands) > 1)
          /\ UNCHANGED refused
       \/ /\ Cardinality(cands) > 1 /\ Mutant # "cancel_first"
          /\ refused' = TRUE
          /\ UNCHANGED can /\ UNCHANGED ambPick
  /\ ncan' = ncan + 1
  /\ UNCHANGED <<srv, chn, tb, slots, pending, lost, todo, dsp, wrongCancel, overCap, hit, nconn, ncr, nbr, nk, nh>>

CnHits ==
  /\ ch[ctd] /\ chgen[ctd] = cgen /\ InSync(ctd) /\ sport[ctd][ctok] # 0
  /\ (Mutant = "no_port_check" \/ cport = 0 \/ sport[ctd][ctok] = cport)
  /\ (Mutant = "no_sid_check" \/ ssid[ctd][ctok] = csid)

\* channel_of_token and CANCEL on it; the server interrupts the session that has the token now, when the
\* request's port and session id are that session's.  mutants no_sid_check, no_port_check: the server does not ask
CnSend ==
  /\ cpc = "look"
  /\ cpc' = "idle"
  /\ IF CnHits
       THEN /\ hit' = TRUE
            /\ wrongCancel' = (wrongCancel \/ ~((cport = 0 \/ sport[ctd][ctok] = cport) /\ ssid[ctd][ctok] = csid))
       ELSE UNCHANGED hit /\ UNCHANGED wrongCancel
  /\ UNCHANGED <<srv, chn, tb, slots, pending, lost, todo, dsp, ctd, ctok, cgen, cport, csid, overCap, refused, ambPick, cnt>>

Next ==
  \/ \E d \in D, p \in P : DStart(d, p)
  \/ \E e \in D : DScan(e)
  \/ DScanEnd \/ DDial \/ DWait \/ DGiveUp \/ DSendNo \/ DSendDead
  \/ \E t \in T, sid \in 0..NSid : DSendOk(t, sid)
  \/ \E e \in D, t \in T : SEnd(e, t)
  \/ \E e \in D : SCrash(e) \/ SRestart(e) \/ Hang(e) \/ RDie(e) \/ Kill(e)
  \/ BRestart
  \/ \E t \in T, q \in 0..NP, s \in 0..NSid : CnLook(t, q, s)
  \/ CnSend

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ sport \in [D -> [T -> 0..NP]] /\ ssid \in [D -> [T -> 0..NSid]]
  /\ up \in [D -> BOOLEAN] /\ ans \in [D -> BOOLEAN] /\ sinc \in [D -> Nat]
  /\ ch \in [D -> BOOLEAN] /\ chinc \in [D -> Nat] /\ chgen \in [D -> Nat] /\ gen \in Nat
  /\ tb \in [D -> [T -> 0..NP]] /\ slots \in Int /\ pending \in BOOLEAN /\ lost \in [D -> BOOLEAN]
  /\ todo \in SUBSET D
  /\ dpc \in {"idle", "scan", "dial", "wait", "send"} /\ ddb \in D /\ dport \in P
  /\ cpc \in {"idle", "look"} /\ ctd \in D /\ ctok \in T /\ cgen \in Nat /\ cport \in 0..NP /\ csid \in 0..NSid
  /\ wrongCancel \in BOOLEAN /\ overCap \in BOOLEAN /\ refused \in BOOLEAN /\ hit \in BOOLEAN /\ ambPick \in BOOLEAN
  /\ nconn \in Nat /\ ncr \in Nat /\ nbr \in Nat /\ nk \in Nat /\ nh \in Nat /\ ncan \in Nat

\* C1: slots_used is the size of the token table
SlotsMatch == slots = Cardinality({x \in D \X T : tb[x[1]][x[2]] # 0})

\* C1: a database's entries are the live sessions of its server, whatever the other databases' tokens are
TableExact == \A e \in D : InSync(e) => tb[e] = sport[e]

\* C1: a dead channel leaves no entry
NoOrphan == \A e \in D : ~ch[e] => tb[e] = Zero

\* C1: a cancel interrupts only a session with the request's port and session id
CancelIsolation == ~wrongCancel

\* C1: a cancel whose request matches the entries of several sessions is sent to none of them
NoAmbiguousPick == ~ambPick

\* C2: a HANDOFF goes out only while the broker's sessions, over every database it has not given up, leave a slot
NoOverCap == ~overCap

(* ---- the inductive invariant ---- *)

\* a server that is down has no session, and no session id is left of a session that ended
Unissued ==
  \A e \in D :
    /\ ~up[e] => sport[e] = Zero
    /\ \A t \in T : sport[e][t] = 0 => ssid[e][t] = 0

\* a server holds sessions of this broker only under the incarnation its channel was dialed to
LiveIsSynced == \A e \in D : ch[e] /\ sport[e] # Zero => chinc[e] = sinc[e]

ChanWf == \A e \in D : chgen[e] <= gen /\ chinc[e] <= sinc[e]

\* every database that holds sessions and is not given up has its channel, or is still to be asked
Covered ==
  \A e \in D : ~lost[e] /\ sport[e] # Zero /\ ~ch[e] => (dpc = "idle" /\ pending) \/ (dpc = "scan" /\ e \in todo)

DispWf ==
  /\ dpc # "scan" => todo = {}
  /\ dpc = "send" => slots < MaxSlots

\* the entry a cancel looked up is of a generation the broker gave
LookWf == cpc = "look" => cgen <= gen

Ghosts == ~wrongCancel /\ ~overCap /\ ~ambPick

IndInv ==
  /\ TypeOK
  /\ SlotsMatch
  /\ TableExact
  /\ NoOrphan
  /\ Unissued
  /\ LiveIsSynced
  /\ ChanWf
  /\ Covered
  /\ DispWf
  /\ LookWf
  /\ Ghosts
  /\ CancelIsolation
  /\ NoAmbiguousPick
  /\ NoOverCap

CInit ==
  /\ ND = 2 /\ NT = 2 /\ NP = 2 /\ NSid = 2 /\ MaxSlots = 2 /\ MaxConn = 3 /\ MaxCrash = 1 /\ MaxBR = 1
  /\ MaxKill = 1 /\ MaxHang = 1 /\ MaxCancel = 2 /\ Mutant = "none"

\* witnesses
NotCollide == ~(\E t \in T : tb[1][t] # 0 /\ tb[2][t] # 0)
NotRefused == ~refused
NotHit == ~hit
NotScanSynced == ~(dpc = "dial" /\ nbr > 0 /\ \E e \in D : e # ddb /\ ch[e] /\ tb[e] # Zero)
NotHeldByOther == ~(dpc = "wait" /\ slots >= MaxSlots /\ tb[ddb] = Zero)
NotGivenUp == ~(\E e \in D : lost[e] /\ sport[e] # Zero)
=============================================================================
