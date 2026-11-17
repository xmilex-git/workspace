----------------------------- MODULE ConfigPush -----------------------------
(* CBRD-27430 B2: a broker's conf reaches its sessions in the folded server.

   A CAS read its broker's conf from the broker's shared memory, so broker_changer changed it for every CAS
   at once. A session of the server has a copy: the broker takes a copy of its shared memory (a snapshot)
   for every HANDOFF, and for a SESSION_CONFIG to every server after broker_changer changed the shared
   memory. A copy carries a seq that grows with every snapshot of the broker, across its restarts too.
   A server keeps, per broker, the copy with the largest seq it was sent (latest), gives a session the
   newer of latest and what its HANDOFF carries, and replaces a session's copy only by a newer one. The
   session's thread takes a changed copy at a request boundary.

   Messages are delivered in any order, and a message whose sender gave up (a reply that did not come in
   time) may still be handled later: the channel a broker dials after a timeout has its own thread on the
   server, beside the thread of the channel it left.

   Roles: the broker's dispatcher (one HANDOFF at a time), its control thread (one push at a time),
   broker_changer (the environment), ND servers each with its channel threads (one SESSION_CONFIG handled
   at a time under registry_mutex), NS sessions with their threads.

   Constants:
     NS, ND      sessions, servers            MaxV      conf changes of broker_changer
     MaxRestart  broker restarts
     Mutant      "none" | "no_seq_order" | "no_latest" | "read_then_clear" | "flag_before_write"
                 | "no_dial_all" | "snap_unlocked" | "seq_restart" *)
EXTENDS Naturals, FiniteSets

CONSTANTS NS, ND, MaxV, MaxRestart, Mutant

\* apalache-type: NS Int
\* apalache-type: ND Int
\* apalache-type: MaxV Int
\* apalache-type: MaxRestart Int
\* apalache-type: Mutant Str
\* apalache-type: shmv Int
\* apalache-type: seq Int
\* apalache-type: known Set(Int)
\* apalache-type: pushReq Int
\* apalache-type: restarts Int
\* apalache-type: dpc Str
\* apalache-type: ds Int
\* apalache-type: dd Int
\* apalache-type: dv Int
\* apalache-type: dq Int
\* apalache-type: cpc Str
\* apalache-type: cv Int
\* apalache-type: cq Int
\* apalache-type: cok Bool
\* apalache-type: ctodo Set(Int)
\* apalache-type: cw Int
\* apalache-type: net Set({t: Str, s: Int, d: Int, v: Int, q: Int})
\* apalache-type: okv Int
\* apalache-type: okq Int
\* apalache-type: lv Int -> Int
\* apalache-type: lq Int -> Int
\* apalache-type: rl Int -> Int
\* apalache-type: rv Int -> Int
\* apalache-type: st Int -> Str
\* apalache-type: sdb Int -> Int
\* apalache-type: bv Int -> Int
\* apalache-type: bq Int -> Int
\* apalache-type: hv Int -> Int
\* apalache-type: hq Int -> Int
\* apalache-type: changed Int -> Bool
\* apalache-type: tpc Int -> Str
\* apalache-type: wph Int -> Str

\* shmv: the conf in the broker's shared memory, as a version
\* seq: the seq of the broker's last snapshot
\* known: servers the broker has a channel to
\* pushReq: pushes broker_changer asked for and the control thread did not start
\* dpc, ds, dd, dv, dq: the dispatcher and its HANDOFF
\* cpc, cv, cq, cok, ctodo, cw: the control thread, its push and the server it asks
\* net: messages sent and not handled
\* okv, okq: the conf of the last push the broker answered as delivered
\* lv, lq: per server: the broker's latest conf
\* rl, rv: per server: the seq and conf of the SESSION_CONFIG being handled, 0 when none
\* st, sdb: per session: "none" | "live" | "done", and its server
\* bv, bq: per session: the copy in its binding
\* hv, hq: per session: the copy its thread works with
\* changed: per session: the binding's flag
\* tpc: per session thread: "run" | "read" (cleared the flag) | "clear" (mutant: read first)
\* wph: per session: its place in the SESSION_CONFIG being handled: "none" | "todo" | "flag"
VARIABLES shmv, seq, known, pushReq, restarts, dpc, ds, dd, dv, dq, cpc, cv, cq, cok, ctodo, cw, net, okv,
          okq, lv, lq, rl, rv, st, sdb, bv, bq, hv, hq, changed, tpc, wph

vars == <<shmv, seq, known, pushReq, restarts, dpc, ds, dd, dv, dq, cpc, cv, cq, cok, ctodo, cw, net, okv, okq,
          lv, lq, rl, rv, st, sdb, bv, bq, hv, hq, changed, tpc, wph>>

S == 1..NS
D == 1..ND
MaxSeq == NS + MaxV + 1

brokerVars == <<shmv, seq, known, pushReq, restarts>>
dispVars == <<dpc, ds, dd, dv, dq>>
ctlVars == <<cpc, cv, cq, cok, ctodo, cw>>
\* @type: <<Int, Int>>;
okVars == <<okv, okq>>
\* @type: <<Int -> Int, Int -> Int>>;
latestVars == <<lv, lq>>
handleVars == <<rl, rv, wph>>
bindVars == <<bv, bq, changed>>
threadVars == <<hv, hq, tpc>>
sessVars == <<st, sdb>>

Init ==
  /\ shmv = 0 /\ seq = 0 /\ known = {} /\ pushReq = 0 /\ restarts = 0
  /\ dpc = "idle" /\ ds = 1 /\ dd = 1 /\ dv = 0 /\ dq = 0
  /\ cpc = "idle" /\ cv = 0 /\ cq = 0 /\ cok = TRUE /\ ctodo = {} /\ cw = 1
  /\ net = {}
  /\ okv = 0 /\ okq = 0
  /\ lv = [d \in D |-> 0] /\ lq = [d \in D |-> 0]
  /\ rl = [d \in D |-> 0] /\ rv = [d \in D |-> 0]
  /\ st = [s \in S |-> "none"] /\ sdb = [s \in S |-> 1]
  /\ bv = [s \in S |-> 0] /\ bq = [s \in S |-> 0]
  /\ hv = [s \in S |-> 0] /\ hq = [s \in S |-> 0]
  /\ changed = [s \in S |-> FALSE]
  /\ tpc = [s \in S |-> "run"]
  /\ wph = [s \in S |-> "none"]

(* ---- broker_changer and the broker's restart ---- *)

\* admin_conf_change: the shared memory, then a request on the session control socket
AChange ==
  /\ shmv < MaxV
  /\ shmv' = shmv + 1
  /\ pushReq' = pushReq + 1
  /\ UNCHANGED <<seq, known, restarts, dispVars, ctlVars, net, okVars, latestVars, handleVars, sessVars,
                 bindVars, threadVars>>

\* the broker stops and starts: no channel, no request; its sessions stay on their servers and its messages
\* may still be handled.  The new process starts its seq above the old one's (brd_init, the clock).
BRestart ==
  /\ restarts < MaxRestart
  /\ dpc = "idle" /\ cpc = "idle"
  /\ restarts' = restarts + 1
  /\ known' = {}
  /\ pushReq' = 0
  /\ seq' = IF Mutant = "seq_restart" THEN 0 ELSE seq
  /\ UNCHANGED <<shmv, dispVars, ctlVars, net, okVars, latestVars, handleVars, sessVars, bindVars, threadVars>>

(* ---- the dispatcher: brd_dispatch_job ---- *)

DStart(s, d) ==
  /\ dpc = "idle" /\ st[s] = "none"
  /\ \A m \in net : ~(m.t = "H" /\ m.s = s)
  /\ dpc' = "snap" /\ ds' = s /\ dd' = d
  /\ UNCHANGED <<dv, dq, brokerVars, ctlVars, net, okVars, latestVars, handleVars, sessVars, bindVars,
                 threadVars>>

\* config_snapshot: the shared memory and the seq under config_mutex
DSnap ==
  /\ dpc = "snap" /\ seq < MaxSeq
  /\ dv' = shmv
  /\ IF Mutant = "snap_unlocked"
       THEN /\ dpc' = "seqn" /\ UNCHANGED dq /\ UNCHANGED seq
       ELSE /\ dpc' = "send" /\ dq' = seq + 1 /\ seq' = seq + 1
  /\ UNCHANGED <<ds, dd, shmv, known, pushReq, restarts, ctlVars, net, okVars, latestVars, handleVars,
                 sessVars, bindVars, threadVars>>

\* mutant: the seq taken after the shared memory was read, with no mutex around the two
DSnapSeq ==
  /\ dpc = "seqn" /\ seq < MaxSeq
  /\ dpc' = "send" /\ dq' = seq + 1 /\ seq' = seq + 1
  /\ UNCHANGED <<ds, dd, dv, shmv, known, pushReq, restarts, ctlVars, net, okVars, latestVars, handleVars,
                 sessVars, bindVars, threadVars>>

DSend ==
  /\ dpc = "send"
  /\ net' = net \union {[t |-> "H", s |-> ds, d |-> dd, v |-> dv, q |-> dq]}
  /\ known' = known \union {dd}
  /\ dpc' = "wait"
  /\ UNCHANGED <<ds, dd, dv, dq, shmv, seq, pushReq, restarts, ctlVars, okVars, latestVars, handleVars,
                 sessVars, bindVars, threadVars>>

\* HANDOFF_ACK or HANDOFF_REJECT came
DReply ==
  /\ dpc = "wait"
  /\ \A m \in net : ~(m.t = "H" /\ m.s = ds)
  /\ dpc' = "idle"
  /\ UNCHANGED <<ds, dd, dv, dq, brokerVars, ctlVars, net, okVars, latestVars, handleVars, sessVars,
                 bindVars, threadVars>>

\* no reply in time: the channel is given up, the message may still be handled
DTimeout ==
  /\ dpc = "wait"
  /\ dpc' = "idle"
  /\ known' = known \ {dd}
  /\ UNCHANGED <<ds, dd, dv, dq, shmv, seq, pushReq, restarts, ctlVars, net, okVars, latestVars, handleVars,
                 sessVars, bindVars, threadVars>>

(* ---- the control thread: control_broadcast ---- *)

CStart ==
  /\ cpc = "idle" /\ pushReq > 0
  /\ pushReq' = pushReq - 1
  /\ cpc' = "dial"
  /\ UNCHANGED <<shmv, seq, known, restarts, cv, cq, cok, ctodo, cw, dispVars, net, okVars, latestVars,
                 handleVars, sessVars, bindVars, threadVars>>

\* every adoption socket is dialed: a server whose sessions outlived the broker's restart has no channel yet
CDial ==
  /\ cpc = "dial"
  /\ ctodo' = IF Mutant = "no_dial_all" THEN known ELSE D
  /\ known' = known \union ctodo'
  /\ cok' = TRUE
  /\ cpc' = "snap"
  /\ UNCHANGED <<shmv, seq, pushReq, restarts, cv, cq, cw, dispVars, net, okVars, latestVars, handleVars,
                 sessVars, bindVars, threadVars>>

CSnap ==
  /\ cpc = "snap" /\ seq < MaxSeq
  /\ cv' = shmv /\ cq' = seq + 1 /\ seq' = seq + 1
  /\ cpc' = "send"
  /\ UNCHANGED <<shmv, known, pushReq, restarts, cok, ctodo, cw, dispVars, net, okVars, latestVars, handleVars,
                 sessVars, bindVars, threadVars>>

CSend(d) ==
  /\ cpc = "send" /\ d \in ctodo
  /\ net' = net \union {[t |-> "C", s |-> 0, d |-> d, v |-> cv, q |-> cq]}
  /\ cpc' = "wait" /\ cw' = d
  /\ UNCHANGED <<brokerVars, cv, cq, cok, ctodo, dispVars, okVars, latestVars, handleVars, sessVars,
                 bindVars, threadVars>>

\* SESSION_CONFIG_REPLY of server d
CReply(d) ==
  /\ cpc = "wait" /\ d = cw
  /\ [t |-> "C", s |-> 0, d |-> d, v |-> cv, q |-> cq] \notin net
  /\ ctodo' = ctodo \ {d}
  /\ cpc' = "send"
  /\ UNCHANGED <<brokerVars, cv, cq, cok, cw, dispVars, net, okVars, latestVars, handleVars, sessVars,
                 bindVars, threadVars>>

CTimeout(d) ==
  /\ cpc = "wait" /\ d = cw
  /\ [t |-> "C", s |-> 0, d |-> d, v |-> cv, q |-> cq] \in net
  /\ ctodo' = ctodo \ {d}
  /\ cok' = FALSE
  /\ known' = known \ {d}
  /\ cpc' = "send"
  /\ UNCHANGED <<shmv, seq, pushReq, restarts, cv, cq, cw, dispVars, net, okVars, latestVars, handleVars,
                 sessVars, bindVars, threadVars>>

\* the answer to broker_changer: delivered, or "some sessions keep the previous setting"
CDone ==
  /\ cpc = "send" /\ ctodo = {}
  /\ cpc' = "idle"
  /\ IF cok /\ cq > okq THEN okv' = cv /\ okq' = cq ELSE UNCHANGED okVars
  /\ UNCHANGED <<brokerVars, cv, cq, cok, ctodo, cw, dispVars, net, latestVars, handleVars, sessVars, bindVars,
                 threadVars>>

(* ---- a server ---- *)

Newer(q, d) == Mutant = "no_latest" \/ q >= lq[d]

\* handle_handoff: the session is registered with the newer of its HANDOFF's conf and the broker's latest
SHandoff(m) ==
  /\ m \in net /\ m.t = "H" /\ st[m.s] = "none" /\ rl[m.d] = 0
  /\ net' = net \ {m}
  /\ st' = [st EXCEPT ![m.s] = "live"]
  /\ sdb' = [sdb EXCEPT ![m.s] = m.d]
  /\ LET useq == IF Newer(m.q, m.d) THEN m.q ELSE lq[m.d]
         usev == IF Newer(m.q, m.d) THEN m.v ELSE lv[m.d]
     IN /\ bq' = [bq EXCEPT ![m.s] = useq] /\ bv' = [bv EXCEPT ![m.s] = usev]
        /\ hq' = [hq EXCEPT ![m.s] = useq] /\ hv' = [hv EXCEPT ![m.s] = usev]
  /\ IF m.q > lq[m.d]
       THEN lq' = [lq EXCEPT ![m.d] = m.q] /\ lv' = [lv EXCEPT ![m.d] = m.v]
       ELSE UNCHANGED latestVars
  /\ UNCHANGED <<brokerVars, dispVars, ctlVars, okVars, handleVars, changed, tpc>>

\* a HANDOFF refused, or undone because its ACK could not be sent: no session
SRefuse(m) ==
  /\ m \in net /\ m.t = "H" /\ st[m.s] = "none"
  /\ net' = net \ {m}
  /\ st' = [st EXCEPT ![m.s] = "done"]
  /\ UNCHANGED <<sdb, brokerVars, dispVars, ctlVars, okVars, latestVars, handleVars, bindVars, threadVars>>

\* handle_session_config takes registry_mutex: latest, then every session of the broker
SConfigBegin(m) ==
  /\ m \in net /\ m.t = "C" /\ rl[m.d] = 0
  /\ rl' = [rl EXCEPT ![m.d] = m.q] /\ rv' = [rv EXCEPT ![m.d] = m.v]
  /\ IF m.q > lq[m.d]
       THEN lq' = [lq EXCEPT ![m.d] = m.q] /\ lv' = [lv EXCEPT ![m.d] = m.v]
       ELSE UNCHANGED latestVars
  /\ wph' = [s \in S |-> IF st[s] = "live" /\ sdb[s] = m.d THEN "todo" ELSE wph[s]]
  /\ UNCHANGED <<brokerVars, dispVars, ctlVars, net, okVars, sessVars, bindVars, threadVars>>

\* under the session's control_mutex: a newer conf replaces the session's
SWrite(s) ==
  /\ wph[s] = "todo"
  /\ LET d == sdb[s]
         take == Mutant = "no_seq_order" \/ rl[d] > bq[s]
     IN IF take
          THEN /\ wph' = [wph EXCEPT ![s] = "flag"]
               /\ IF Mutant = "flag_before_write"
                    THEN changed' = [changed EXCEPT ![s] = TRUE] /\ UNCHANGED bv /\ UNCHANGED bq
                    ELSE /\ bq' = [bq EXCEPT ![s] = rl[d]] /\ bv' = [bv EXCEPT ![s] = rv[d]]
                         /\ UNCHANGED changed
          ELSE wph' = [wph EXCEPT ![s] = "none"] /\ UNCHANGED bindVars
  /\ UNCHANGED <<brokerVars, dispVars, ctlVars, net, okVars, latestVars, rl, rv, sessVars, threadVars>>

\* config_changed.store (true), after the mutex was released
SFlag(s) ==
  /\ wph[s] = "flag"
  /\ wph' = [wph EXCEPT ![s] = "none"]
  /\ IF Mutant = "flag_before_write"
       THEN /\ bq' = [bq EXCEPT ![s] = rl[sdb[s]]] /\ bv' = [bv EXCEPT ![s] = rv[sdb[s]]]
            /\ UNCHANGED changed
       ELSE changed' = [changed EXCEPT ![s] = TRUE] /\ UNCHANGED bv /\ UNCHANGED bq
  /\ UNCHANGED <<brokerVars, dispVars, ctlVars, net, okVars, latestVars, rl, rv, sessVars, threadVars>>

\* registry_mutex released, SESSION_CONFIG_REPLY sent
SConfigEnd(m) ==
  /\ m \in net /\ m.t = "C" /\ rl[m.d] = m.q
  /\ \A s \in S : sdb[s] = m.d => wph[s] = "none"
  /\ rl' = [rl EXCEPT ![m.d] = 0] /\ rv' = [rv EXCEPT ![m.d] = 0]
  /\ net' = net \ {m}
  /\ UNCHANGED <<brokerVars, dispVars, ctlVars, okVars, latestVars, wph, sessVars, bindVars, threadVars>>

(* ---- a session's thread: registry_take_config at a request boundary ---- *)

\* config_changed.exchange (false)
TClear(s) ==
  /\ st[s] = "live"
  /\ IF Mutant = "read_then_clear"
       THEN /\ tpc[s] = "clear"
            /\ tpc' = [tpc EXCEPT ![s] = "run"]
       ELSE /\ tpc[s] = "run" /\ changed[s]
            /\ tpc' = [tpc EXCEPT ![s] = "read"]
  /\ changed' = [changed EXCEPT ![s] = FALSE]
  /\ UNCHANGED <<brokerVars, dispVars, ctlVars, net, okVars, latestVars, handleVars, sessVars, bv, bq, hv, hq>>

\* the copy under control_mutex, then cas_server_session_config_apply
TRead(s) ==
  /\ st[s] = "live"
  /\ IF Mutant = "read_then_clear"
       THEN /\ tpc[s] = "run" /\ changed[s]
            /\ tpc' = [tpc EXCEPT ![s] = "clear"]
       ELSE /\ tpc[s] = "read"
            /\ tpc' = [tpc EXCEPT ![s] = "run"]
  /\ hv' = [hv EXCEPT ![s] = bv[s]] /\ hq' = [hq EXCEPT ![s] = bq[s]]
  /\ UNCHANGED <<brokerVars, dispVars, ctlVars, net, okVars, latestVars, handleVars, sessVars, bindVars>>

\* registry_session_finished erases the entry under registry_mutex
TFinish(s) ==
  /\ st[s] = "live" /\ tpc[s] = "run" /\ rl[sdb[s]] = 0
  /\ st' = [st EXCEPT ![s] = "done"]
  /\ UNCHANGED <<sdb, brokerVars, dispVars, ctlVars, net, okVars, latestVars, handleVars, bindVars, threadVars>>

\* every session ended and nothing is left to send or handle
Finished ==
  /\ \A s \in S : st[s] = "done"
  /\ dpc = "idle" /\ cpc = "idle" /\ pushReq = 0 /\ net = {}
  /\ UNCHANGED vars

Next ==
  \/ Finished
  \/ AChange \/ BRestart
  \/ \E s \in S, d \in D : DStart(s, d)
  \/ DSnap \/ DSnapSeq \/ DSend \/ DReply \/ DTimeout
  \/ CStart \/ CDial \/ CSnap \/ CDone
  \/ \E d \in D : CSend(d) \/ CReply(d) \/ CTimeout(d)
  \/ \E m \in net : SHandoff(m) \/ SRefuse(m) \/ SConfigBegin(m) \/ SConfigEnd(m)
  \/ \E s \in S : SWrite(s) \/ SFlag(s) \/ TClear(s) \/ TRead(s) \/ TFinish(s)

Spec == Init /\ [][Next]_vars

Fair ==
  /\ \A s \in S : WF_vars(TClear(s)) /\ WF_vars(TRead(s)) /\ WF_vars(SWrite(s)) /\ WF_vars(SFlag(s))

LiveSpec == Spec /\ Fair

(* ---- properties ---- *)

Msg == [t : {"H", "C"}, s : 0..NS, d : D, v : 0..MaxV, q : 1..MaxSeq]

TypeOK ==
  /\ shmv \in 0..MaxV /\ seq \in 0..MaxSeq /\ known \in SUBSET D /\ pushReq \in 0..MaxV
  /\ restarts \in 0..MaxRestart
  /\ dpc \in {"idle", "snap", "seqn", "send", "wait"} /\ ds \in S /\ dd \in D /\ dv \in 0..MaxV
  /\ dq \in 0..MaxSeq
  /\ cpc \in {"idle", "dial", "snap", "send", "wait"} /\ cv \in 0..MaxV /\ cq \in 0..MaxSeq
  /\ cok \in BOOLEAN /\ ctodo \in SUBSET D /\ cw \in D
  /\ net \in SUBSET Msg
  /\ okv \in 0..MaxV /\ okq \in 0..MaxSeq
  /\ lv \in [D -> 0..MaxV] /\ lq \in [D -> 0..MaxSeq] /\ rl \in [D -> 0..MaxSeq] /\ rv \in [D -> 0..MaxV]
  /\ st \in [S -> {"none", "live", "done"}] /\ sdb \in [S -> D]
  /\ bv \in [S -> 0..MaxV] /\ bq \in [S -> 0..MaxSeq] /\ hv \in [S -> 0..MaxV] /\ hq \in [S -> 0..MaxSeq]
  /\ changed \in [S -> BOOLEAN] /\ tpc \in [S -> {"run", "read", "clear"}]
  /\ wph \in [S -> {"none", "todo", "flag"}]

Live(s) == st[s] = "live"

\* the session's thread will take the binding's copy: the flag is set, or about to be, or was just cleared
Pending(s) == changed[s] \/ tpc[s] = "read" \/ wph[s] = "flag"

\* C6: after the broker answered a change as delivered, no session of the broker works with an older conf
\* without having the change waiting for its next request boundary
NoStale == \A s \in S : Live(s) => hv[s] >= okv \/ (bv[s] >= okv /\ Pending(s))

\* C6: a session's copies only move to a later conf
ThreadBehindBinding == \A s \in S : Live(s) => hq[s] <= bq[s] /\ hv[s] <= bv[s]

\* a larger seq is a later conf, in every copy a server holds
SeqOrdersConf ==
  /\ \A s \in S, t \in S : Live(s) /\ Live(t) /\ bq[s] <= bq[t] => bv[s] <= bv[t]
  /\ \A s \in S : Live(s) /\ bq[s] >= okq => bv[s] >= okv

(* ---- the inductive invariant ---- *)

\* every copy of the conf that exists: a seq and the conf it was taken with
Copies ==
  {[q |-> dq, v |-> dv], [q |-> cq, v |-> cv], [q |-> okq, v |-> okv]}
    \union {[q |-> m.q, v |-> m.v] : m \in net}
    \union {[q |-> lq[d], v |-> lv[d]] : d \in D} \union {[q |-> rl[d], v |-> rv[d]] : d \in D}
    \union {[q |-> bq[s], v |-> bv[s]] : s \in S} \union {[q |-> hq[s], v |-> hv[s]] : s \in S}

\* a copy is a snapshot the broker took, or the empty one
CopyWf == \A c \in Copies : c.q <= seq /\ c.v <= shmv /\ (c.q = 0 => c.v = 0)

\* a larger seq is a later conf, over every pair of copies
CopyOrder == \A a \in Copies, b \in Copies : a.q <= b.q => a.v <= b.v

\* the correct variant has no mutant's place; a request is counted once
PlaceWf ==
  /\ dpc # "seqn" /\ \A s \in S : tpc[s] # "clear"
  /\ pushReq <= shmv
  /\ dpc \in {"send", "wait"} => dq >= 1
  /\ cpc \in {"send", "wait"} => cq >= 1
  /\ cpc = "snap" => ctodo = D

\* a HANDOFF names its session, a SESSION_CONFIG none
MsgWf == \A m \in net : IF m.t = "H" THEN m.s \in S ELSE m.s = 0

\* a SESSION_CONFIG being handled is in the net, and latest has it or a newer one
HandleWf ==
  \A d \in D :
    /\ rl[d] = 0 => rv[d] = 0
    /\ rl[d] # 0 => /\ [t |-> "C", s |-> 0, d |-> d, v |-> rv[d], q |-> rl[d]] \in net
                    /\ rl[d] <= lq[d]

\* a session has a place in a SESSION_CONFIG only while it is live and its server handles one
WphWf == \A s \in S : wph[s] # "none" => Live(s) /\ rl[sdb[s]] # 0

\* a session of a server that handles a SESSION_CONFIG has it or a newer one, or the handler has not come to it
Cover == \A s \in S : Live(s) => bq[s] >= rl[sdb[s]] \/ wph[s] = "todo"

HandledAt(d, q) == lq[d] >= q /\ \A s \in S : Live(s) /\ sdb[s] = d => bq[s] >= q

\* a server that replied to the push in time has it in latest and in every session
PushProgress ==
  (cpc \in {"send", "wait"} /\ cok) =>
    \A d \in D :
      (d \notin ctodo \/ (cpc = "wait" /\ d = cw /\ [t |-> "C", s |-> 0, d |-> d, v |-> cv, q |-> cq] \notin net))
        => HandledAt(d, cq)

\* a push answered as delivered is in every server's latest and in every session
Delivered == \A d \in D : HandledAt(d, okq)

\* the thread has the binding's copy, or will take it
ThreadSync == \A s \in S : Live(s) => (hq[s] = bq[s] /\ hv[s] = bv[s]) \/ Pending(s)

IndInv ==
  /\ TypeOK
  /\ CopyWf
  /\ CopyOrder
  /\ PlaceWf
  /\ MsgWf
  /\ HandleWf
  /\ WphWf
  /\ Cover
  /\ PushProgress
  /\ Delivered
  /\ ThreadSync
  /\ NoStale
  /\ ThreadBehindBinding
  /\ SeqOrdersConf

CInit == NS = 2 /\ ND = 2 /\ MaxV = 1 /\ MaxRestart = 1 /\ Mutant = "none"

\* witnesses
NotApplied == ~(\E s \in S : Live(s) /\ hv[s] = MaxV /\ MaxV > 0 /\ okv = MaxV)
NotLateOlder == ~(\E m \in net : m.t = "C" /\ m.q < okq)
NotSurvivorReached == ~(restarts > 0 /\ \E s \in S : Live(s) /\ hv[s] = MaxV /\ MaxV > 0 /\ bq[s] > 1)
NotPartial == ~(cpc = "send" /\ ctodo = {} /\ ~cok)

\* C6 liveness: under fair session threads, a delivered change is applied by every session that stays
Applied == (okv = MaxV) ~> (\A s \in S : Live(s) => hv[s] >= MaxV)

=============================================================================
