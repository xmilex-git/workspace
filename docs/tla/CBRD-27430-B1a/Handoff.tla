------------------------------- MODULE Handoff -------------------------------
(* CBRD-27430 B1a: the broker hands a driver connection to the database server that will run its session.

   The broker keeps one control channel per database on the server's adoption socket (a UNIX stream). Its single
   dispatch thread takes a queued driver connection, finds or dials the channel (connect, HELLO, RESYNC), checks a
   handoff slot is free (slots_used < MAX_NUM_APPL_SERVER) and sends HANDOFF with the driver's fd (SCM_RIGHTS), then
   waits for the reply. The channel's reader thread applies every slot transition in wire order: HANDOFF_ACK and
   RESYNC_REPLY entries admit a token (+1 slot), SESSION_END releases one, the channel's death drops the tokens it
   admitted. A query cancel looks the token up and sends CANCEL on a channel.

   The server runs one thread per channel (HELLO, HANDOFF, CANCEL, RESYNC in order), registers each adopted
   session under a token (registry_mutex), answers HANDOFF_ACK and starts the session thread. A session ends by
   cleaning up (closing its binding and waiting for cancel pins), tearing its transaction down, erasing its registry
   entry, sending SESSION_END on its channel and closing the driver fd. stop() drains the sessions and frees the
   manager.

   Faults: a server crash (sessions and channels vanish; tokens restart at 1), a broker restart (its tables vanish,
   sessions survive), a reply timeout (the broker kills that channel), a server stop, a capacity reject.

   Constants:
     J          driver connections (each becomes at most one session; its id is the job's)
     MaxSlots   the broker's handoff slots
     NT         server transaction indices
     MaxConn    control-channel connections dialed in the whole run
     MaxCrash, MaxRestart, MaxTimeout, MaxCancel  fault and cancel budgets
     HasStop    a server stop may happen
     Mutant     a known-wrong variant (MAP.md "Mutants") or "none" *)
EXTENDS Naturals, FiniteSets, Sequences

CONSTANTS J, MaxSlots, NT, MaxConn, MaxCrash, MaxRestart, MaxTimeout, MaxCancel, HasStop, Mutant

\* apalache-type: J Int
\* apalache-type: MaxSlots Int
\* apalache-type: NT Int
\* apalache-type: MaxConn Int
\* apalache-type: MaxCrash Int
\* apalache-type: MaxRestart Int
\* apalache-type: MaxTimeout Int
\* apalache-type: MaxCancel Int
\* apalache-type: HasStop Bool
\* apalache-type: Mutant Str

Mutants == {"none", "end_by_entry", "end_any_gen", "cancel_by_db", "no_pin", "hello_fail_shutdown",
            "no_stop_recheck", "ack_ignored", "admit_before_dial", "close_before_erase", "resync_unlocked",
            "ack_after_spawn", "no_finisher_wait"}

ASSUME Assm ==
  /\ J \in Nat \ {0} /\ MaxSlots \in Nat \ {0} /\ NT \in Nat \ {0} /\ MaxConn \in Nat \ {0}
  /\ MaxCrash \in Nat /\ MaxRestart \in Nat /\ MaxTimeout \in Nat /\ MaxCancel \in Nat
  /\ HasStop \in BOOLEAN /\ Mutant \in Mutants

Jobs == 1..J
Conns == 1..MaxConn
Trans == 1..NT

(* control messages; one record shape for every op (Apalache) — tok/s for ACK, END, CANCEL (s is the ghost session
   id the sender means), toks for RESYNC_REPLY (pairs <<token, session>>) *)
\* @typeAlias: msg = {op: Str, tok: Int, s: Int, toks: Set(<<Int, Int>>)};
\* @type: (Str, Int, Int) => $msg;
Msg(op, tok, s) == [op |-> op, tok |-> tok, s |-> s, toks |-> {}]
NoMsg == Msg("none", 0, 0)

(* session phases, in order: "none" (not adopted), "reg" (registered, thread not started), "run", "clean" (binding
   closing, waiting for cancel pins), "torn" (transaction released, still registered), "fin1" (erased, channel not
   yet looked up), "fin2" (channel chosen), "fin3" (END sent or skipped), "done" (driver fd closed), "dead" (died with
   its server) *)
InReg == {"reg", "run", "clean", "torn"}
Alive == InReg \cup {"fin1", "fin2", "fin3"}

(* server: sUp .. sCh (sess: [Jobs -> session record], sCh: [Conns -> the server end of a channel]); broker: bInc ..
   cx; wire: b2s, s2b; fault budgets: crashes .. cancels; violation ghosts: uaf .. overCap; witness ghost: hit *)
VARIABLES sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, latest, sess, sCh,
  bInc, bCh, published, tokens, slots, mailbox, dpc, dj, dch, jobs, cpc, cx,
  b2s, s2b,
  crashes, restarts, timeouts, cancels,
  uaf, badFd, wrongCancel, overCap, hit

\* apalache-type: sUp Bool
\* apalache-type: sInc Int
\* apalache-type: nextTok Int
\* apalache-type: stopping Bool
\* apalache-type: stopPc Str
\* apalache-type: mFreed Bool
\* apalache-type: finishers Int
\* apalache-type: tranOwner Int -> Int
\* apalache-type: latest Int
\* apalache-type: sess Int -> {st: Str, tok: Int, inc: Int, conn: Int, tran: Int, pins: Int, closing: Bool, fch: Int, fdClosed: Bool, logged: Bool, acked: Bool}
\* apalache-type: sCh Int -> {st: Str, inc: Int, inMap: Bool, rdShut: Bool, hpc: Str, hs: Int, ctok: Int, ctgt: Int, ctran: Int, cs: Int, snap: Set(Int)}
\* apalache-type: bInc Int
\* apalache-type: bCh Int -> {st: Str, shut: Bool, inc: Int}
\* apalache-type: published Int
\* apalache-type: tokens Set({tok: Int, gen: Int, s: Int})
\* apalache-type: slots Int
\* apalache-type: mailbox Int -> {op: Str, tok: Int, s: Int, toks: Set(<<Int, Int>>)}
\* apalache-type: dpc Str
\* apalache-type: dj Int
\* apalache-type: dch Int
\* apalache-type: jobs Int -> Str
\* apalache-type: cpc Str
\* apalache-type: cx {tok: Int, gen: Int, s: Int}
\* apalache-type: b2s Int -> Seq({op: Str, tok: Int, s: Int, toks: Set(<<Int, Int>>)})
\* apalache-type: s2b Int -> Seq({op: Str, tok: Int, s: Int, toks: Set(<<Int, Int>>)})
\* apalache-type: crashes Int
\* apalache-type: restarts Int
\* apalache-type: timeouts Int
\* apalache-type: cancels Int
\* apalache-type: uaf Bool
\* apalache-type: badFd Bool
\* apalache-type: wrongCancel Bool
\* apalache-type: overCap Bool
\* apalache-type: hit Set(Str)

srvVars == <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, latest, sess, sCh>>
brkVars == <<bInc, bCh, published, tokens, slots, mailbox, dpc, dj, dch, jobs, cpc, cx>>
\* @type: <<Int -> Seq($msg), Int -> Seq($msg)>>;
wire == <<b2s, s2b>>
\* @type: <<Int, Int, Int, Int>>;
budgets == <<crashes, restarts, timeouts, cancels>>
ghosts == <<uaf, badFd, wrongCancel, overCap, hit>>
vars == <<srvVars, brkVars, wire, budgets, ghosts>>

NoSess == [st |-> "none", tok |-> 0, inc |-> 0, conn |-> 0, tran |-> 0, pins |-> 0, closing |-> FALSE, fch |-> 0,
           fdClosed |-> FALSE, logged |-> FALSE, acked |-> FALSE]
NoSCh == [st |-> "none", inc |-> 0, inMap |-> FALSE, rdShut |-> FALSE, hpc |-> "idle", hs |-> 0, ctok |-> 0,
          ctgt |-> 0, ctran |-> 0, cs |-> 0, snap |-> {}]
NoBCh == [st |-> "none", shut |-> FALSE, inc |-> 0]
NoTok == [tok |-> 0, gen |-> 0, s |-> 0]

SessSt == {"none", "reg", "run", "clean", "torn", "fin1", "fin2", "fin3", "done", "dead"}
SChSt == {"none", "pend", "open", "dead"}
HPcs == {"idle", "h_check", "h_reg", "h_ack", "h_spawn", "c_int", "r_send"}
BChSt == {"none", "dial", "pub", "dead", "dropped", "gone"}
DPcs == {"idle", "admit", "getch", "hello", "resync", "send", "wait"}
JobSt == {"queued", "inflight", "acked", "rejected", "nosrv", "full", "lostack", "lost"}
StopPcs == {"no", "shut_ch", "shut_sess", "drain", "fin_wait", "join", "free", "done"}
Ops == {"none", "HELLO", "HELLO_ACK", "HANDOFF", "ACK", "REJECT", "CANCEL", "RESYNC", "RESYNC_REPLY", "END"}

TypeOK ==
  /\ sUp \in BOOLEAN /\ sInc \in Nat /\ nextTok \in Nat /\ stopping \in BOOLEAN /\ stopPc \in StopPcs
  /\ mFreed \in BOOLEAN /\ finishers \in Nat /\ tranOwner \in [Trans -> 0..J] /\ latest \in 0..MaxConn
  /\ \A s \in Jobs : sess[s].st \in SessSt /\ sess[s].tran \in 0..NT /\ sess[s].conn \in 0..MaxConn
  /\ \A c \in Conns : sCh[c].st \in SChSt /\ sCh[c].hpc \in HPcs /\ bCh[c].st \in BChSt
  /\ bInc \in Nat /\ published \in 0..MaxConn /\ slots \in Nat
  /\ dpc \in DPcs /\ dj \in 0..J /\ dch \in 0..MaxConn /\ jobs \in [Jobs -> JobSt] /\ cpc \in {"idle", "send"}
  /\ \A c \in Conns : mailbox[c].op \in Ops
  /\ uaf \in BOOLEAN /\ badFd \in BOOLEAN /\ wrongCancel \in BOOLEAN /\ overCap \in BOOLEAN

Init ==
  /\ sUp = TRUE /\ sInc = 1 /\ nextTok = 1 /\ stopping = FALSE /\ stopPc = "no" /\ mFreed = FALSE
  /\ finishers = 0 /\ tranOwner = [x \in Trans |-> 0] /\ latest = 0
  /\ sess = [s \in Jobs |-> NoSess] /\ sCh = [c \in Conns |-> NoSCh]
  /\ bInc = 1 /\ bCh = [c \in Conns |-> NoBCh] /\ published = 0 /\ tokens = {} /\ slots = 0
  /\ mailbox = [c \in Conns |-> NoMsg]
  /\ dpc = "idle" /\ dj = 0 /\ dch = 0 /\ jobs = [s \in Jobs |-> "queued"] /\ cpc = "idle" /\ cx = NoTok
  /\ b2s = [c \in Conns |-> <<>>] /\ s2b = [c \in Conns |-> <<>>]
  /\ crashes = 0 /\ restarts = 0 /\ timeouts = 0 /\ cancels = 0
  /\ uaf = FALSE /\ badFd = FALSE /\ wrongCancel = FALSE /\ overCap = FALSE /\ hit = {}

-----------------------------------------------------------------------------
(* wire *)

\* the broker's side of c reads: its reader thread is alive and the broker has not shut the socket
BrkReads(c) == bCh[c].st \in {"dial", "pub"} /\ ~bCh[c].shut
\* the server's side of c is open (its fd is not invalidated under send_mutex)
SrvOpen(c) == sCh[c].st \in {"pend", "open"} /\ ~sCh[c].rdShut
\* a server send on c (send_mutex held, fd checked) delivers iff the broker still reads; otherwise EPIPE
SrvSendOk(c) == sCh[c].st = "open" /\ ~sCh[c].rdShut /\ BrkReads(c)
SrvSend(c, m) == s2b' = [s2b EXCEPT ![c] = Append(@, m)]
\* a broker send on c delivers iff its fd is valid and the server end is not closed
BrkSendOk(c) == BrkReads(c) /\ SrvOpen(c)
BrkSend(c, m) == b2s' = [b2s EXCEPT ![c] = Append(@, m)]

Hit(x) == hit' = hit \cup {x}

\* the broker's handoff slots held by channels that still read (a killed channel's late admissions are dropped)
LiveCount == Cardinality({x \in tokens : BrkReads(x.gen)})

-----------------------------------------------------------------------------
(* broker: dispatch thread (brd_dispatch_job, channel_get_or_dial) *)

DStart ==
  /\ dpc = "idle" /\ \E j \in Jobs : jobs[j] = "queued"
  /\ \E j \in Jobs :
       /\ jobs[j] = "queued"
       /\ jobs' = [jobs EXCEPT ![j] = "inflight"]
       /\ dj' = j
  /\ dpc' = IF Mutant = "admit_before_dial" THEN "admit" ELSE "getch"
  /\ UNCHANGED <<srvVars, bInc, bCh, published, tokens, slots, mailbox, dch, cpc, cx, wire, budgets, ghosts>>

\* the admission wait: a slot is free (or the wait times out: a queue wait happens only when the slots are full)
DAdmit ==
  /\ dpc = "admit"
  /\ IF slots < MaxSlots
     THEN /\ dpc' = IF Mutant = "admit_before_dial" THEN "getch" ELSE "send"
          /\ UNCHANGED <<jobs, dj>>
     ELSE /\ jobs' = [jobs EXCEPT ![dj] = "full"] /\ dpc' = "idle" /\ dj' = 0
  /\ UNCHANGED <<srvVars, bInc, bCh, published, tokens, slots, mailbox, dch, cpc, cx, wire, budgets, ghosts>>

\* the published live channel, or a dial; no listening server is the retryable connect failure (#117 D5)
DGetCh ==
  /\ dpc = "getch"
  /\ IF published # 0
     THEN /\ dch' = published
          /\ dpc' = IF Mutant = "admit_before_dial" THEN "send" ELSE "admit"
          /\ UNCHANGED <<bCh, sCh, b2s, jobs, dj>>
     ELSE IF sUp /\ ~stopping /\ \E c \in Conns : bCh[c].st = "none"
     THEN LET c == CHOOSE n \in Conns : bCh[n].st = "none" /\ \A d \in Conns : d < n => bCh[d].st # "none" IN
            /\ bCh' = [bCh EXCEPT ![c] = [st |-> "dial", shut |-> FALSE, inc |-> bInc]]
            /\ sCh' = [sCh EXCEPT ![c] = [NoSCh EXCEPT !.st = "pend", !.inc = sInc]]
            /\ b2s' = [b2s EXCEPT ![c] = <<Msg("HELLO", 0, 0)>>]
            /\ dch' = c /\ dpc' = "hello"
            /\ UNCHANGED <<jobs, dj>>
     ELSE /\ jobs' = [jobs EXCEPT ![dj] = "nosrv"] /\ dpc' = "idle" /\ dj' = 0
          /\ UNCHANGED <<bCh, sCh, b2s, dch>>
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, latest, sess>>
  /\ UNCHANGED <<bInc, published, tokens, slots, mailbox, cpc, cx, s2b, budgets, ghosts>>

DHello ==
  /\ dpc = "hello" /\ mailbox[dch].op = "HELLO_ACK" /\ BrkSendOk(dch)
  /\ mailbox' = [mailbox EXCEPT ![dch] = NoMsg]
  /\ BrkSend(dch, Msg("RESYNC", 0, 0))
  /\ dpc' = "resync"
  /\ UNCHANGED <<srvVars, bInc, bCh, published, tokens, slots, dj, dch, jobs, cpc, cx, s2b, budgets, ghosts>>

\* the reader already admitted the snapshot; publish the channel
DResync ==
  /\ dpc = "resync" /\ mailbox[dch].op = "RESYNC_REPLY" /\ bCh[dch].st = "dial"
  /\ mailbox' = [mailbox EXCEPT ![dch] = NoMsg]
  /\ bCh' = [bCh EXCEPT ![dch].st = "pub"]
  /\ published' = dch
  /\ dpc' = IF Mutant = "admit_before_dial" THEN "send" ELSE "admit"
  /\ UNCHANGED <<srvVars, bInc, tokens, slots, dj, dch, jobs, cpc, cx, wire, budgets, ghosts>>

\* HELLO or RESYNC got no answer: the channel died under the request, or the reply timed out (the broker kills it)
DDialFail ==
  /\ dpc \in {"hello", "resync"}
  /\ \/ /\ ~BrkSendOk(dch)
        \* channel_kill: dead, and its fd shut down under send_mutex while it is still open
        /\ bCh' = IF BrkReads(dch) THEN [bCh EXCEPT ![dch].shut = TRUE] ELSE bCh
        /\ UNCHANGED timeouts
        \* the old code shut the dialed fd down by number; the reader may have closed it already
        /\ badFd' = (badFd \/ (Mutant = "hello_fail_shutdown" /\ bCh[dch].st \in {"dead", "dropped"}))
     \/ /\ timeouts < MaxTimeout /\ BrkReads(dch) /\ mailbox[dch].op = "none"
        /\ bCh' = [bCh EXCEPT ![dch].shut = TRUE]
        /\ timeouts' = timeouts + 1
        /\ UNCHANGED badFd
  /\ jobs' = [jobs EXCEPT ![dj] = "nosrv"] /\ dpc' = "idle" /\ dj' = 0
  /\ UNCHANGED <<srvVars, bInc, published, tokens, slots, mailbox, dch, cpc, cx, wire, crashes, restarts, cancels,
                 uaf, wrongCancel, overCap, hit>>

\* HANDOFF with the driver's fd (one sendmsg under send_mutex); a channel that cannot take it rejects the driver
DSend ==
  /\ dpc = "send"
  /\ mailbox' = [mailbox EXCEPT ![dch] = NoMsg]
  /\ IF BrkSendOk(dch) /\ bCh[dch].st = "pub"
     THEN /\ BrkSend(dch, Msg("HANDOFF", 0, dj))
          /\ dpc' = "wait"
          /\ overCap' = (overCap \/ LiveCount >= MaxSlots)
          /\ UNCHANGED <<jobs, dj>>
     ELSE /\ jobs' = [jobs EXCEPT ![dj] = "rejected"] /\ dpc' = "idle" /\ dj' = 0
          /\ UNCHANGED <<b2s, overCap>>
  /\ UNCHANGED <<srvVars, bInc, bCh, published, tokens, slots, dch, cpc, cx, s2b, budgets, uaf, badFd, wrongCancel, hit>>

\* the reply: ACK (the reader admitted the token first), REJECT, the channel's death, or a timeout that kills it;
\* after the fd went out the broker never answers the driver itself
DWait ==
  /\ dpc = "wait"
  /\ \/ /\ mailbox[dch].op = "ACK"
        /\ jobs' = [jobs EXCEPT ![dj] = "acked"] /\ Hit("acked")
        /\ UNCHANGED <<bCh, timeouts>>
     \/ /\ mailbox[dch].op = "REJECT"
        /\ jobs' = [jobs EXCEPT ![dj] = "rejected"]
        /\ UNCHANGED <<bCh, timeouts, hit>>
     \/ /\ mailbox[dch].op = "none" /\ ~BrkReads(dch)
        /\ jobs' = [jobs EXCEPT ![dj] = "lostack"]
        /\ UNCHANGED <<bCh, timeouts, hit>>
     \/ /\ mailbox[dch].op = "none" /\ BrkReads(dch) /\ timeouts < MaxTimeout
        /\ bCh' = [bCh EXCEPT ![dch].shut = TRUE]
        /\ timeouts' = timeouts + 1
        /\ jobs' = [jobs EXCEPT ![dj] = "lostack"] /\ Hit("timeout")
  /\ mailbox' = [mailbox EXCEPT ![dch] = NoMsg]
  /\ dpc' = "idle" /\ dj' = 0
  /\ UNCHANGED <<srvVars, bInc, published, tokens, slots, dch, cpc, cx, wire, crashes, restarts, cancels,
                 uaf, badFd, wrongCancel, overCap>>

-----------------------------------------------------------------------------
(* broker: channel reader threads (channel_reader_run) *)

\* @type: (Int, Int, Int) => {tok: Int, gen: Int, s: Int};
Admit(c, t, s) == [tok |-> t, gen |-> c, s |-> s]

\* SESSION_END releases the token this channel admitted (the old code: any entry of the channel's database)
EndMatch(c, t) ==
  {x \in tokens : x.tok = t /\ (x.gen = c \/ Mutant = "end_any_gen")}

RRecv(c) ==
  /\ bCh[c].st \in {"dial", "pub"} /\ s2b[c] # <<>>
  /\ LET m == Head(s2b[c]) IN
       /\ s2b' = [s2b EXCEPT ![c] = Tail(@)]
       /\ IF m.op = "END"
          THEN /\ IF EndMatch(c, m.tok) = {}
                  THEN UNCHANGED <<tokens, slots>>
                  ELSE \E x \in EndMatch(c, m.tok) : tokens' = tokens \ {x} /\ slots' = slots - 1
               /\ UNCHANGED <<mailbox, hit>>
          ELSE /\ IF m.op = "ACK"
                  THEN /\ tokens' = tokens \cup {Admit(c, m.tok, m.s)}
                       /\ slots' = slots + (IF Admit(c, m.tok, m.s) \in tokens THEN 0 ELSE 1)
                       /\ UNCHANGED hit
                  ELSE IF m.op = "RESYNC_REPLY"
                  THEN LET new == {Admit(c, p[1], p[2]) : p \in m.toks} IN
                         /\ tokens' = tokens \cup new
                         /\ slots' = slots + Cardinality(new \ tokens)
                         /\ hit' = IF new # {} THEN hit \cup {"readmit"} ELSE hit
                  ELSE UNCHANGED <<tokens, slots, hit>>
               /\ mailbox' = [mailbox EXCEPT ![c] = m]
  /\ UNCHANGED <<srvVars, bInc, bCh, published, dpc, dj, dch, jobs, cpc, cx, b2s, budgets, uaf, badFd, wrongCancel,
                 overCap>>

\* recv fails: the server closed its end (crash, stop, its own protocol error) or this broker killed the channel.
\* dead.store, close under send_mutex, erase from the channel map ...
RDie(c) ==
  /\ bCh[c].st \in {"dial", "pub"}
  \* stop's shutdown (SHUT_RDWR) ends the stream for the broker before the channel thread closes the fd
  /\ bCh[c].shut \/ ((sCh[c].st = "dead" \/ sCh[c].rdShut) /\ s2b[c] = <<>>)
  /\ bCh' = [bCh EXCEPT ![c].st = "dead"]
  /\ published' = IF published = c THEN 0 ELSE published
  /\ UNCHANGED <<srvVars, bInc, tokens, slots, mailbox, dpc, dj, dch, jobs, cpc, cx, wire, budgets, ghosts>>

\* ... then tokens_drop_for_channel: the tokens this channel admitted
RDrop(c) ==
  /\ bCh[c].st = "dead"
  /\ LET gone == {x \in tokens : x.gen = c} IN
       /\ tokens' = tokens \ gone
       /\ slots' = slots - Cardinality(gone)
  /\ bCh' = [bCh EXCEPT ![c].st = "dropped"]
  /\ UNCHANGED <<srvVars, bInc, published, mailbox, dpc, dj, dch, jobs, cpc, cx, wire, budgets, ghosts>>

-----------------------------------------------------------------------------
(* broker: a query cancel (brd_cancel: the token table lookup, then CANCEL on a channel) *)

CnLook ==
  /\ cpc = "idle" /\ cancels < MaxCancel
  /\ \E x \in tokens : cx' = x
  /\ cpc' = "send" /\ cancels' = cancels + 1
  /\ UNCHANGED <<srvVars, bInc, bCh, published, tokens, slots, mailbox, dpc, dj, dch, jobs, wire,
                 crashes, restarts, timeouts, ghosts>>

\* the channel that admitted the token (old: the database's current channel)
CancelCh == IF Mutant = "cancel_by_db" THEN published ELSE cx.gen

CnSend ==
  /\ cpc = "send"
  /\ IF CancelCh # 0 /\ BrkSendOk(CancelCh) /\ bCh[CancelCh].st = "pub"
     THEN BrkSend(CancelCh, Msg("CANCEL", cx.tok, cx.s))
     ELSE UNCHANGED b2s
  /\ cpc' = "idle" /\ cx' = NoTok
  /\ UNCHANGED <<srvVars, bInc, bCh, published, tokens, slots, mailbox, dpc, dj, dch, jobs, s2b, budgets, ghosts>>

-----------------------------------------------------------------------------
(* server: accept thread and channel threads (adoption.cpp) *)

\* accept a dialed connection; reap the channels whose threads ended
SAccept(c) ==
  /\ sCh[c].st = "pend" /\ sUp /\ ~stopping /\ \A d \in Conns : d < c => sCh[d].st # "pend"
  /\ sCh' = [d \in Conns |->
               IF d = c THEN [sCh[c] EXCEPT !.st = "open", !.inMap = TRUE]
               ELSE IF sCh[d].st = "dead" THEN [sCh[d] EXCEPT !.inMap = FALSE]
               ELSE sCh[d]]
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, latest, sess, brkVars, wire, budgets,
                 ghosts>>

SRecv(c) ==
  /\ sCh[c].st = "open" /\ sCh[c].hpc = "idle" /\ b2s[c] # <<>>
  /\ LET m == Head(b2s[c]) IN
       /\ b2s' = [b2s EXCEPT ![c] = Tail(@)]
       /\ CASE m.op = "HELLO" ->
                 /\ IF SrvSendOk(c) THEN SrvSend(c, Msg("HELLO_ACK", 0, 0)) ELSE UNCHANGED s2b
                 \* the broker's newest channel (accept order): SESSION_ENDs go here
                 /\ latest' = IF c > latest THEN c ELSE latest
                 /\ UNCHANGED sCh
            [] m.op = "HANDOFF" ->
                 /\ sCh' = [sCh EXCEPT ![c].hpc = "h_check", ![c].hs = m.s]
                 /\ UNCHANGED <<s2b, latest>>
            [] m.op = "CANCEL" ->
                 /\ sCh' = [sCh EXCEPT ![c].hpc = "c_int", ![c].ctok = m.tok, ![c].ctgt = m.s]
                 /\ UNCHANGED <<s2b, latest>>
            [] m.op = "RESYNC" ->
                 /\ sCh' = [sCh EXCEPT ![c].hpc = "r_send"]
                 /\ UNCHANGED <<s2b, latest>>
            [] OTHER -> UNCHANGED <<sCh, s2b, latest>>
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, sess, brkVars, budgets, ghosts>>

\* recv fails (the broker closed or shut its end, or stop() shut this one): close under send_mutex, fd = -1,
\* dead; the map entry stays until the accept thread reaps it
SEof(c) ==
  /\ sCh[c].st = "open" /\ sCh[c].hpc = "idle"
  /\ \/ sCh[c].rdShut
     \/ b2s[c] = <<>> /\ (bCh[c].shut \/ bCh[c].st \in {"dead", "dropped", "gone"})
  /\ sCh' = [sCh EXCEPT ![c].st = "dead"]
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, latest, sess, brkVars, wire, budgets,
                 ghosts>>

\* RESYNC: snapshot this broker's registry entries and write the reply while holding this channel's send_mutex
\* (send_mutex -> registry_mutex), so a SESSION_END of a token in the snapshot follows the reply on the wire.
\* resync_unlocked: snapshot, release, then send.
Snapshot == {s \in Jobs : sess[s].st \in InReg /\ sess[s].inc = sInc}
\* @type: (Set(Int)) => $msg;
ReplyOf(snap) == [Msg("RESYNC_REPLY", 0, 0) EXCEPT !.toks = {<<sess[s].tok, s>> : s \in snap}]

SResync(c) ==
  /\ sCh[c].st = "open" /\ sCh[c].hpc = "r_send"
  /\ IF Mutant = "resync_unlocked" /\ sCh[c].snap = {} /\ Snapshot # {}
     THEN /\ sCh' = [sCh EXCEPT ![c].snap = Snapshot]
          /\ UNCHANGED s2b
     ELSE LET snap == IF Mutant = "resync_unlocked" THEN sCh[c].snap ELSE Snapshot IN
            /\ IF SrvSendOk(c) THEN SrvSend(c, ReplyOf(snap)) ELSE UNCHANGED s2b
            /\ sCh' = [sCh EXCEPT ![c].hpc = "idle", ![c].snap = {}]
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, latest, sess, brkVars, b2s,
                 budgets, ghosts>>

\* handle_handoff: refuse while stopping; css_increment_num_conn may refuse (CLIENTS_EXCEEDED); both close the fd
\* and answer HANDOFF_REJECT
Reject(c) == IF SrvSendOk(c) THEN SrvSend(c, Msg("REJECT", 0, 0)) ELSE UNCHANGED s2b

SHCheck(c) ==
  /\ sCh[c].st = "open" /\ sCh[c].hpc = "h_check"
  /\ \/ stopping /\ Reject(c) /\ sCh' = [sCh EXCEPT ![c].hpc = "idle", ![c].hs = 0]
     \/ ~stopping /\ Reject(c) /\ sCh' = [sCh EXCEPT ![c].hpc = "idle", ![c].hs = 0]  \* capacity
     \/ ~stopping /\ sCh' = [sCh EXCEPT ![c].hpc = "h_reg"] /\ UNCHANGED s2b
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, latest, sess, brkVars, b2s, budgets,
                 ghosts>>

\* register under registry_mutex, re-reading stopping there (old: no re-check)
SHReg(c) ==
  /\ sCh[c].st = "open" /\ sCh[c].hpc = "h_reg"
  /\ LET s == sCh[c].hs IN
       IF stopping /\ Mutant # "no_stop_recheck"
       THEN /\ Reject(c)
            /\ sCh' = [sCh EXCEPT ![c].hpc = "idle", ![c].hs = 0]
            /\ UNCHANGED <<sess, nextTok>>
       ELSE /\ sess' = [sess EXCEPT ![s] = [NoSess EXCEPT !.st = "reg", !.tok = nextTok, !.inc = sInc, !.conn = c]]
            /\ nextTok' = nextTok + 1
            /\ sCh' = [sCh EXCEPT ![c].hpc = IF Mutant = "ack_after_spawn" THEN "h_spawn" ELSE "h_ack"]
            /\ UNCHANGED s2b
  /\ UNCHANGED <<sUp, sInc, stopping, stopPc, mFreed, finishers, tranOwner, latest, brkVars, b2s, budgets, ghosts>>

\* HANDOFF_ACK before the session thread exists; an ACK the broker can no longer read means the broker gave the
\* handoff up: the adoption is undone the way a session ends (refund, registry_session_finished — whose SESSION_END
\* reaches a channel that re-synced the token meanwhile — and close the fd). ack_ignored: start the session anyway.
SHAck(c) ==
  /\ sCh[c].st = "open" /\ sCh[c].hpc = "h_ack"
  /\ LET s == sCh[c].hs IN
       IF SrvSendOk(c)
       THEN /\ SrvSend(c, Msg("ACK", sess[s].tok, s))
            /\ sCh' = [sCh EXCEPT ![c].hpc = IF Mutant = "ack_after_spawn" THEN "idle" ELSE "h_spawn",
                                  ![c].hs = IF Mutant = "ack_after_spawn" THEN 0 ELSE s]
            /\ sess' = [sess EXCEPT ![s].acked = TRUE]
       ELSE IF Mutant \in {"ack_ignored", "ack_after_spawn"}
       THEN /\ sCh' = [sCh EXCEPT ![c].hpc = IF Mutant = "ack_after_spawn" THEN "idle" ELSE "h_spawn",
                                  ![c].hs = IF Mutant = "ack_after_spawn" THEN 0 ELSE s]
            /\ UNCHANGED <<sess, s2b>>
       ELSE /\ sess' = [sess EXCEPT ![s].st = "clean", ![s].closing = TRUE]
            /\ sCh' = [sCh EXCEPT ![c].hpc = "idle", ![c].hs = 0]
            /\ UNCHANGED s2b
  /\ hit' = IF ~SrvSendOk(c) /\ Mutant \notin {"ack_ignored", "ack_after_spawn"} THEN hit \cup {"undone"} ELSE hit
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, latest, brkVars, b2s, budgets,
                 uaf, badFd, wrongCancel, overCap>>

\* the session thread starts (submit_session); after the manager is freed it would run on freed memory
SHSpawn(c) ==
  /\ sCh[c].st = "open" /\ sCh[c].hpc = "h_spawn"
  /\ LET s == sCh[c].hs IN
       /\ sess' = [sess EXCEPT ![s].st = IF @ = "reg" THEN "run" ELSE @]
       /\ sCh' = [sCh EXCEPT ![c].hpc = IF Mutant = "ack_after_spawn" THEN "h_ack" ELSE "idle",
                             ![c].hs = IF Mutant = "ack_after_spawn" THEN s ELSE 0]
       /\ uaf' = (uaf \/ mFreed)
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, latest, brkVars, wire, budgets,
                 badFd, wrongCancel, overCap, hit>>

\* handle_cancel: look the token up and pin the binding (a closing binding is not pinned) under the binding mutex,
\* interrupt the pinned transaction, unpin. no_pin: copy the registry's tran index and interrupt after unlocking.
CancelTarget(c) == {s \in Jobs : sess[s].st \in InReg /\ sess[s].inc = sInc /\ sess[s].tok = sCh[c].ctok}

SCancel(c) ==
  /\ sCh[c].st = "open" /\ sCh[c].hpc = "c_int"
  /\ IF sCh[c].cs = 0
     THEN \* lookup (+ pin)
          IF CancelTarget(c) = {} \/ \A s \in CancelTarget(c) : sess[s].closing /\ Mutant # "no_pin"
          THEN /\ sCh' = [sCh EXCEPT ![c].hpc = "idle", ![c].ctok = 0, ![c].ctgt = 0]
               /\ UNCHANGED <<sess, wrongCancel, hit>>
          ELSE \E s \in CancelTarget(c) :
                 /\ ~sess[s].closing \/ Mutant = "no_pin"
                 /\ sCh' = [sCh EXCEPT ![c].cs = s, ![c].ctran = sess[s].tran]
                 /\ sess' = IF Mutant = "no_pin" THEN sess ELSE [sess EXCEPT ![s].pins = @ + 1]
                 /\ UNCHANGED <<wrongCancel, hit>>
     ELSE \* interrupt the copied transaction index, unpin
          LET x == sCh[c].ctran IN
            /\ wrongCancel' = (wrongCancel \/ (x # 0 /\ tranOwner[x] # 0 /\ tranOwner[x] # sCh[c].ctgt))
            /\ IF x # 0 /\ tranOwner[x] = sCh[c].ctgt /\ tranOwner[x] # 0 THEN Hit("cancelled") ELSE UNCHANGED hit
            /\ sess' = IF Mutant = "no_pin" THEN sess ELSE [sess EXCEPT ![sCh[c].cs].pins = @ - 1]
            /\ sCh' = [sCh EXCEPT ![c].hpc = "idle", ![c].ctok = 0, ![c].ctgt = 0, ![c].cs = 0, ![c].ctran = 0]
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, latest, brkVars, wire, budgets,
                 uaf, badFd, overCap>>

-----------------------------------------------------------------------------
(* server: a session thread (driver_session_run, its retire path) *)

\* login: the session takes a transaction index (registry_set_tran_index)
SLogin(s) ==
  /\ sess[s].st = "run" /\ ~sess[s].logged
  /\ \E x \in Trans :
       /\ tranOwner[x] = 0
       /\ tranOwner' = [tranOwner EXCEPT ![x] = s]
       /\ sess' = [sess EXCEPT ![s].tran = x, ![s].logged = TRUE]
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, latest, sCh, brkVars, wire, budgets, ghosts>>

\* the driver closes, or stop() shut its fd down: registry_begin_session_cleanup closes the binding (no_pin: the old
\* code had no cleanup step and released the transaction at once, the registry keeping its stale tran index);
\* close_before_erase: the old code closed the driver fd here, before the registry erase
SEnd(s) ==
  /\ sess[s].st = "run"
  /\ IF Mutant = "no_pin"
     THEN /\ sess' = [sess EXCEPT ![s].st = "torn"]
          /\ tranOwner' = IF sess[s].tran # 0 THEN [tranOwner EXCEPT ![sess[s].tran] = 0] ELSE tranOwner
     ELSE /\ sess' = [sess EXCEPT ![s].st = "clean", ![s].closing = TRUE,
                                  ![s].fdClosed = (Mutant = "close_before_erase")]
          /\ UNCHANGED tranOwner
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, latest, sCh, brkVars, wire, budgets, ghosts>>

\* the binding drained (no cancel pin): release the transaction
SClean(s) ==
  /\ sess[s].st = "clean" /\ sess[s].pins = 0
  /\ tranOwner' = IF sess[s].tran # 0 THEN [tranOwner EXCEPT ![sess[s].tran] = 0] ELSE tranOwner
  /\ sess' = [sess EXCEPT ![s].st = "torn", ![s].tran = 0]
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, latest, sCh, brkVars, wire, budgets, ghosts>>

\* registry_session_finished: active_finishers++, erase under registry_mutex reading the entry's channel
SErase(s) ==
  /\ sess[s].st = "torn"
  /\ sess' = [sess EXCEPT ![s].st = "fin1", ![s].fch = sess[s].conn]
  /\ finishers' = finishers + 1
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, tranOwner, latest, sCh, brkVars, wire, budgets, ghosts>>

\* the channel lookup under channels_mutex: the newest channel (accept order) of the session's broker; a broker
\* that dialed it holds no live channel older than it. end_by_entry (the old code): the entry's own channel while it
\* is in the map, otherwise any open channel of the same broker.
SPick(s) ==
  /\ sess[s].st = "fin1"
  /\ LET c0 == sess[s].fch
         others == {d \in Conns : sCh[d].inMap /\ sCh[d].st = "open" /\ sCh[d].inc = sess[s].inc}
     IN IF Mutant # "end_by_entry"
        THEN sess' = [sess EXCEPT ![s].st = "fin2", ![s].fch = latest]
        ELSE IF c0 # 0 /\ sCh[c0].inMap
        THEN sess' = [sess EXCEPT ![s].st = "fin2"]
        ELSE IF others # {}
        THEN \E d \in others : sess' = [sess EXCEPT ![s].st = "fin2", ![s].fch = d]
        ELSE sess' = [sess EXCEPT ![s].st = "fin2", ![s].fch = 0]
  /\ uaf' = (uaf \/ mFreed)
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, latest, sCh, brkVars, wire,
                 budgets, badFd, wrongCancel, overCap, hit>>

\* SESSION_END under the channel's send_mutex (fd checked), then active_finishers--
SSendEnd(s) ==
  /\ sess[s].st = "fin2"
  /\ LET c == sess[s].fch IN
       IF c # 0 /\ SrvSendOk(c) THEN SrvSend(c, Msg("END", sess[s].tok, s)) ELSE UNCHANGED s2b
  /\ sess' = [sess EXCEPT ![s].st = "fin3"]
  /\ finishers' = finishers - 1
  /\ uaf' = (uaf \/ mFreed)
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, tranOwner, latest, sCh, brkVars, b2s, budgets,
                 badFd, wrongCancel, overCap, hit>>

SClose(s) ==
  /\ sess[s].st = "fin3"
  /\ sess' = [sess EXCEPT ![s].st = "done", ![s].fdClosed = TRUE]
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, stopPc, mFreed, finishers, tranOwner, latest, sCh, brkVars, wire, budgets,
                 ghosts>>

-----------------------------------------------------------------------------
(* server: stop() *)

StopBegin ==
  /\ HasStop /\ sUp /\ stopPc = "no"
  /\ stopping' = TRUE /\ stopPc' = "shut_ch"
  \* the listen socket closes: a pending connection is never accepted
  /\ sCh' = [c \in Conns |-> IF sCh[c].st = "pend" THEN [sCh[c] EXCEPT !.st = "dead"] ELSE sCh[c]]
  /\ UNCHANGED <<sUp, sInc, nextTok, mFreed, finishers, tranOwner, latest, sess, brkVars, wire, budgets, ghosts>>

StopShutCh ==
  /\ stopPc = "shut_ch"
  /\ sCh' = [c \in Conns |-> IF sCh[c].st = "open" THEN [sCh[c] EXCEPT !.rdShut = TRUE] ELSE sCh[c]]
  /\ stopPc' = "shut_sess"
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, mFreed, finishers, tranOwner, latest, sess, brkVars, wire, budgets, ghosts>>

\* under registry_mutex: shut every registered session's driver fd down (and interrupt it)
StopShutSess ==
  /\ stopPc = "shut_sess"
  /\ badFd' = (badFd \/ \E s \in Jobs : sess[s].st \in InReg /\ sess[s].inc = sInc /\ sess[s].fdClosed)
  /\ stopPc' = "drain"
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, mFreed, finishers, tranOwner, latest, sess, sCh, brkVars, wire, budgets,
                 uaf, wrongCancel, overCap, hit>>

StopDrain ==
  /\ stopPc = "drain" /\ \A s \in Jobs : ~(sess[s].st \in InReg /\ sess[s].inc = sInc)
  /\ stopPc' = "fin_wait"
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, mFreed, finishers, tranOwner, latest, sess, sCh, brkVars, wire, budgets, ghosts>>

StopFinWait ==
  /\ stopPc = "fin_wait" /\ (finishers = 0 \/ Mutant = "no_finisher_wait")
  /\ stopPc' = "join"
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, mFreed, finishers, tranOwner, latest, sess, sCh, brkVars, wire, budgets, ghosts>>

\* join the channel threads (each finishes the handler it is in, then sees its shut fd)
StopJoin ==
  /\ stopPc = "join" /\ \A c \in Conns : sCh[c].st # "open"
  /\ stopPc' = "free"
  /\ UNCHANGED <<sUp, sInc, nextTok, stopping, mFreed, finishers, tranOwner, latest, sess, sCh, brkVars, wire, budgets, ghosts>>

\* delete the manager; a session, finisher or handler of this server still alive would touch it afterwards
StopFree ==
  /\ stopPc = "free"
  /\ uaf' = (uaf \/ \E s \in Jobs : sess[s].inc = sInc /\ sess[s].st \in InReg \cup {"fin1", "fin2"})
  /\ mFreed' = TRUE /\ stopPc' = "done" /\ sUp' = FALSE
  /\ hit' = IF \E s \in Jobs : sess[s].st = "done" THEN hit \cup {"stopped"} ELSE hit
  /\ UNCHANGED <<sInc, nextTok, stopping, finishers, tranOwner, latest, sess, sCh, brkVars, wire, budgets,
                 badFd, wrongCancel, overCap>>

-----------------------------------------------------------------------------
(* faults *)

\* the server process dies: its sessions, transactions and channel ends vanish (buffered replies stay readable)
SCrash ==
  /\ sUp /\ stopPc = "no" /\ crashes < MaxCrash
  /\ sUp' = FALSE /\ crashes' = crashes + 1
  /\ sess' = [s \in Jobs |-> IF sess[s].st \in Alive \cup {"reg"} THEN [sess[s] EXCEPT !.st = "dead"] ELSE sess[s]]
  /\ tranOwner' = [x \in Trans |-> 0] /\ latest' = 0
  /\ sCh' = [c \in Conns |-> IF sCh[c].st \in {"pend", "open"}
                             THEN [NoSCh EXCEPT !.st = "dead", !.inc = sCh[c].inc] ELSE [sCh[c] EXCEPT !.inMap = FALSE]]
  /\ b2s' = [c \in Conns |-> <<>>]
  /\ finishers' = 0
  /\ UNCHANGED <<sInc, nextTok, stopping, stopPc, mFreed, brkVars, s2b, restarts, timeouts, cancels, ghosts>>

\* the server comes back: a new manager, tokens from 1 again
SRestart ==
  /\ ~sUp /\ stopPc = "no"
  /\ sUp' = TRUE /\ sInc' = sInc + 1 /\ nextTok' = 1
  /\ UNCHANGED <<stopping, stopPc, mFreed, finishers, tranOwner, latest, sess, sCh, brkVars, wire, budgets, ghosts>>

\* the broker restarts: its tables and channel ends vanish (adopted sessions keep running); a handoff in flight is
\* lost with it, queued drivers reconnect to the new incarnation
BRestart ==
  /\ restarts < MaxRestart
  /\ restarts' = restarts + 1
  /\ bInc' = bInc + 1
  /\ bCh' = [c \in Conns |-> IF bCh[c].st \in {"dial", "pub", "dead"} THEN [bCh[c] EXCEPT !.st = "gone"] ELSE bCh[c]]
  /\ published' = 0 /\ tokens' = {} /\ slots' = 0 /\ mailbox' = [c \in Conns |-> NoMsg]
  /\ jobs' = IF dj # 0 THEN [jobs EXCEPT ![dj] = "lost"] ELSE jobs
  /\ dpc' = "idle" /\ dj' = 0 /\ dch' = 0 /\ cpc' = "idle" /\ cx' = NoTok
  /\ s2b' = [c \in Conns |-> <<>>]
  /\ UNCHANGED <<srvVars, b2s, crashes, timeouts, cancels, ghosts>>

\* the run is over: no driver is left to hand off and no thread is inside a handler (drivers may stay connected)
Terminating ==
  /\ dpc = "idle" /\ cpc = "idle" /\ \A j \in Jobs : jobs[j] # "queued"
  /\ \A c \in Conns : sCh[c].hpc = "idle"
  /\ stopPc \in {"no", "done"}
  /\ UNCHANGED vars

-----------------------------------------------------------------------------

Next ==
  \/ DStart \/ DAdmit \/ DGetCh \/ DHello \/ DResync \/ DDialFail \/ DSend \/ DWait
  \/ \E c \in Conns : RRecv(c) \/ RDie(c) \/ RDrop(c)
  \/ CnLook \/ CnSend
  \/ \E c \in Conns : SAccept(c) \/ SRecv(c) \/ SEof(c) \/ SResync(c) \/ SHCheck(c) \/ SHReg(c) \/ SHAck(c)
                      \/ SHSpawn(c) \/ SCancel(c)
  \/ \E s \in Jobs : SLogin(s) \/ SEnd(s) \/ SClean(s) \/ SErase(s) \/ SPick(s) \/ SSendEnd(s) \/ SClose(s)
  \/ StopBegin \/ StopShutCh \/ StopShutSess \/ StopDrain \/ StopFinWait \/ StopJoin \/ StopFree
  \/ SCrash \/ SRestart \/ BRestart
  \/ Terminating

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* properties *)

\* nothing is in flight: every thread is idle or blocked on an outside event, every message was read
Quiescent ==
  /\ dpc = "idle" /\ cpc = "idle"
  /\ \A c \in Conns :
       /\ sCh[c].hpc = "idle"
       /\ sCh[c].st = "open" => b2s[c] = <<>>
       /\ bCh[c].st \in {"dial", "pub"} => s2b[c] = <<>>
       /\ bCh[c].st # "dead"
       /\ ~(bCh[c].st \in {"dial", "pub"} /\ (bCh[c].shut \/ sCh[c].st = "dead" \/ sCh[c].rdShut))
       /\ ~(sCh[c].st = "open" /\ (sCh[c].rdShut \/ bCh[c].shut \/ bCh[c].st \in {"dead", "dropped", "gone"}))
  /\ \A s \in Jobs : sess[s].st \notin {"reg", "clean", "torn", "fin1", "fin2", "fin3"}

LiveSession(s) == sess[s].st = "run" /\ sess[s].inc = sInc /\ sUp

\* C1: at rest every broker slot belongs to a live session (no leak) ...
NoLeak == Quiescent => \A x \in tokens : LiveSession(x.s) /\ sess[x.s].tok = x.tok
\* ... and, once the database's channel is published (re-synced), every live session holds one (no undercount)
NoUndercount == Quiescent /\ published # 0 => \A s \in Jobs : LiveSession(s) => \E x \in tokens : x.s = s
SlotsMatch == slots = Cardinality(tokens)
\* C2: no shutdown or write through a closed (possibly reused) descriptor
NoBadFd == ~badFd
\* C3: a cancel interrupts only the session whose token the broker looked up
CancelIsolation == ~wrongCancel
\* C4: a handoff goes out only while a slot is free, counted after the channel's re-sync
NoOverCap == ~overCap
\* C5: stop() frees the manager only when nothing of this server can touch it again
NoUseAfterFree == ~uaf

-----------------------------------------------------------------------------
(* the inductive invariant *)

\* the field ranges every action keeps; Apalache's inductive check reads no record field outside them
\* @type: ($msg) => Bool;
MsgOK(m) == m.op \in Ops /\ m.tok \in Nat /\ m.s \in 0..J /\ \A p \in m.toks : p[1] \in Nat /\ p[2] \in Jobs
\* @type: ({tok: Int, gen: Int, s: Int}) => Bool;
TokOK(x) == x.tok \in Nat /\ x.gen \in 0..MaxConn /\ x.s \in 0..J
FieldsOK ==
  /\ \A s \in Jobs : sess[s].tok \in Nat /\ sess[s].inc \in Nat /\ sess[s].pins \in Nat /\ sess[s].fch \in 0..MaxConn
  /\ \A c \in Conns :
       /\ sCh[c].inc \in Nat /\ sCh[c].hs \in 0..J /\ sCh[c].ctok \in Nat /\ sCh[c].ctgt \in 0..J
       /\ sCh[c].ctran \in 0..NT /\ sCh[c].cs \in 0..J /\ sCh[c].snap \subseteq Jobs /\ bCh[c].inc \in Nat
       /\ MsgOK(mailbox[c]) /\ \A k \in DOMAIN b2s[c] : MsgOK(b2s[c][k])
       /\ \A k \in DOMAIN s2b[c] : MsgOK(s2b[c][k])
  /\ \A x \in tokens : TokOK(x) /\ x.gen # 0 /\ x.s # 0
  /\ TokOK(cx) /\ nextTok >= 1
  /\ dpc # "idle" => dj \in Jobs /\ jobs[dj] = "inflight"
  /\ dpc \in {"admit", "hello", "resync", "send", "wait"} => dch \in Conns
  /\ cpc = "send" => cx.gen \in Conns /\ cx.s \in Jobs

Max0(S) == IF S = {} THEN 0 ELSE CHOOSE m \in S : \A n \in S : n <= m

LiveCh(c) == BrkReads(c) /\ sCh[c].st = "open" /\ ~sCh[c].rdShut
HelloPending(c) == b2s[c] # <<>> /\ Head(b2s[c]).op = "HELLO"
\* @type: (Seq($msg)) => Set(Int);
Positions(q) == DOMAIN q
\* the server's session s still owes SESSION_END for token t to channel c
Owes(s, t, c) ==
  /\ sess[s].tok = t /\ sess[s].inc = sInc /\ sUp
  /\ \/ sess[s].st \in InReg \cup {"fin1"}
     \/ sess[s].st = "fin2" /\ sess[s].fch = c
EndAfter(c, t, k) == \E k2 \in Positions(s2b[c]) : k2 > k /\ s2b[c][k2].op = "END" /\ s2b[c][k2].tok = t
\* an admission of (t, s) at position k of c's queue (0: already in the table) is balanced
Accounted(c, t, s, k) == ~LiveCh(c) \/ Owes(s, t, c) \/ EndAfter(c, t, k)
Replies(c) == {k \in Positions(s2b[c]) : s2b[c][k].op # "END"}
Expect(d) ==
  IF d = "hello" THEN {"HELLO_ACK"} ELSE IF d = "resync" THEN {"RESYNC_REPLY"} ELSE IF d = "wait" THEN {"ACK", "REJECT"}
  ELSE {}
\* @type: ($msg) => Bool;
IsAdm(m) == m.op \in {"ACK", "RESYNC_REPLY"}
\* @type: ($msg) => Set(<<Int, Int>>);
AdmPairs(m) == IF m.op = "ACK" THEN {<<m.tok, m.s>>} ELSE m.toks
\* the session's identity a message or a token names, on c's server incarnation
Names(c, t, s) == s \in Jobs /\ sess[s].st # "none" /\ sess[s].tok = t /\ sess[s].inc = sCh[c].inc
RsDone(c) == bCh[c].st = "pub" \/ (dpc = "resync" /\ dch = c /\ ~(\E k \in Positions(b2s[c]) : b2s[c][k].op = "RESYNC")
                                       /\ sCh[c].hpc # "r_send")
HasAdm(s, c) ==
  \/ \E x \in tokens : x.s = s /\ x.gen = c
  \/ \E k \in Positions(s2b[c]) : IsAdm(s2b[c][k]) /\ \E p \in AdmPairs(s2b[c][k]) : p[2] = s
Pinners(s) == {c \in Conns : sCh[c].hpc = "c_int" /\ sCh[c].cs = s}

Inv01 ==
  TypeOK /\ FieldsOK
Inv02 ==
  ~uaf /\ ~badFd /\ ~wrongCancel /\ ~overCap
Inv03 ==
  SlotsMatch
  \* channels: created in dial order, at most the newest one read by the broker
Inv04 ==
  \A c \in Conns :
    /\ (bCh[c].st = "none") <=> (sCh[c].st = "none")
    /\ sCh[c].st = "none" =>
         sCh[c] = NoSCh /\ bCh[c] = NoBCh /\ mailbox[c] = NoMsg /\ b2s[c] = <<>> /\ s2b[c] = <<>>
    \* a channel the server has not accepted yet carries only the broker's HELLO
    /\ sCh[c].st = "pend" =>
         sCh[c] = [NoSCh EXCEPT !.st = "pend", !.inc = sCh[c].inc] /\ mailbox[c] = NoMsg /\ s2b[c] = <<>> /\ bCh[c].st # "pub"
Inv05 ==
  \A c, d \in Conns : c < d /\ bCh[d].st # "none" => bCh[c].st # "none"
Inv06 ==
  \A c \in Conns : BrkReads(c) => \A d \in Conns : d > c => bCh[d].st = "none"
Inv07 ==
  \A c \in Conns : bCh[c].st = "pub" <=> published = c
Inv08 ==
  \A c \in Conns : sCh[c].st \in {"pend", "open"} => sCh[c].inc = sInc /\ sUp
Inv09 ==
  \A c \in Conns : sCh[c].st = "pend" => b2s[c] = <<Msg("HELLO", 0, 0)>>
Inv10 ==
  \A c \in Conns : bCh[c].st = "gone" => s2b[c] = <<>>
  \* SESSION_ENDs reach the broker's newest channel
Inv11 ==
  latest # 0 => bCh[latest].st # "none" /\ sCh[latest].inc = sInc
Inv12 ==
  \A c \in Conns : sCh[c].st = "open" /\ ~HelloPending(c) => latest >= c
Inv13 ==
  \A c \in Conns : HelloPending(c) /\ BrkReads(c) => latest < c
  \* every token, queued admission, SESSION_END and CANCEL names the session that holds the token
Inv14 ==
  \A x \in tokens : bCh[x.gen].st \in {"dial", "pub", "dead"} /\ sCh[x.gen].st \in {"open", "dead"} /\ Names(x.gen, x.tok, x.s)
Inv15 ==
  \A x, y \in tokens : x.gen = y.gen /\ x.tok = y.tok => x = y
Inv16 ==
  \A c \in Conns : \A k \in Positions(s2b[c]) :
       /\ s2b[c][k].op \in {"ACK", "END"} => Names(c, s2b[c][k].tok, s2b[c][k].s)
       /\ s2b[c][k].op = "RESYNC_REPLY" => \A p \in s2b[c][k].toks : Names(c, p[1], p[2])
Inv17 ==
  \A c \in Conns : \A k \in Positions(b2s[c]) : b2s[c][k].op = "CANCEL" => Names(c, b2s[c][k].tok, b2s[c][k].s)
Inv18 ==
  cpc = "send" => Names(cx.gen, cx.tok, cx.s) /\ bCh[cx.gen].st # "none"
Inv19 ==
  \A s1, s2 \in Jobs : s1 # s2 /\ sess[s1].st # "none" /\ sess[s2].st # "none" /\ sess[s1].inc = sess[s2].inc
       => sess[s1].tok # sess[s2].tok
Inv20 ==
  \A s \in Jobs : sess[s].st # "none" => sess[s].inc <= sInc /\ (sess[s].inc = sInc => sess[s].tok < nextTok)
Inv21 ==
  \A s \in Jobs : sess[s].st # "none" => sess[s].conn \in Conns /\ sess[s].tok >= 1
  \* C1: every admission is balanced by a live session or a SESSION_END behind it
Inv22 ==
  \A x \in tokens : Accounted(x.gen, x.tok, x.s, 0)
Inv23 ==
  \A c \in Conns : \A k \in Positions(s2b[c]) : IsAdm(s2b[c][k]) =>
       \A p \in AdmPairs(s2b[c][k]) : Accounted(c, p[1], p[2], k)
  \* C1: an acknowledged session is admitted on the broker's re-synced live channel
Inv24 ==
  \A c \in Conns : \A s \in Jobs :
       LiveCh(c) /\ RsDone(c) /\ sess[s].acked /\ sess[s].inc = sInc /\ sess[s].st \in InReg => HasAdm(s, c)
Inv25 ==
  \A s \in Jobs : sess[s].st = "run" => sess[s].acked
Inv26 ==
  \A s \in Jobs : sess[s].acked /\ sess[s].st \in InReg /\ sess[s].inc = sInc =>
       \/ ~BrkReads(sess[s].conn) \/ sess[s].conn = Max0({c \in Conns : bCh[c].st # "none"})
Inv27 ==
  \A c \in Conns : sCh[c].hpc \in {"h_ack", "h_spawn"} =>
       /\ sCh[c].hs \in Jobs /\ sess[sCh[c].hs].st = "reg" /\ sess[sCh[c].hs].conn = c /\ sess[sCh[c].hs].inc = sInc
       /\ (sCh[c].hpc = "h_spawn") <=> sess[sCh[c].hs].acked
Inv28 ==
  \A c \in Conns : sCh[c].hpc = "h_reg" => sCh[c].hs \in Jobs /\ sess[sCh[c].hs].st = "none"
Inv29 ==
  \A s \in Jobs : sess[s].st = "reg" => \E c \in Conns : sCh[c].hpc \in {"h_ack", "h_spawn"} /\ sCh[c].hs = s
  \* C4: admissions travel only to the dispatcher's own request, and a HANDOFF goes out under the cap
Inv30 ==
  \A c \in Conns : BrkReads(c) =>
    \* one request at a time on a channel the broker still reads: at most one reply on the wire or in the mailbox,
    \* and it answers the dispatcher's current request
    /\ Cardinality(Replies(c)) + (IF mailbox[c].op = "none" THEN 0 ELSE 1) <= 1
    /\ \A k \in Replies(c) : dch = c /\ s2b[c][k].op \in Expect(dpc)
    /\ mailbox[c].op # "none" => dch = c /\ mailbox[c].op \in Expect(dpc)
    \* a reply exists only once the server consumed the request and left its handling
    /\ (Replies(c) # {} \/ mailbox[c].op # "none") =>
         /\ \A k \in Positions(b2s[c]) : b2s[c][k].op \notin {"HELLO", "RESYNC", "HANDOFF"}
         /\ sCh[c].hpc \in {"idle", "h_spawn", "c_int"}
Inv31 ==
  /\ dpc = "send" => LiveCount < MaxSlots
  /\ dpc \in {"admit", "send", "wait"} => bCh[dch].st # "none"
Inv32 ==
  dpc \in {"hello", "resync"} => bCh[dch].st # "pub" /\ dch # 0 /\ published = 0 /\ ~bCh[dch].shut
  \* C2: a driver fd is closed only by its finished session
Inv33 ==
  \A s \in Jobs : sess[s].fdClosed => sess[s].st \in {"done", "dead"}
  \* C3: a pinned session keeps its transaction; the pin and the broker's target are the same session
Inv34 ==
  \A s \in Jobs : sess[s].tran # 0 /\ sess[s].st # "dead" => tranOwner[sess[s].tran] = s /\ sess[s].st \in {"run", "clean"}
Inv35 ==
  \A x \in Trans : tranOwner[x] # 0 => sess[tranOwner[x]].tran = x
Inv36 ==
  \A s \in Jobs : sess[s].st \in {"none", "reg", "run", "clean", "torn", "fin1", "fin2", "fin3", "done"} =>
       sess[s].pins = Cardinality(Pinners(s))
Inv37 ==
  \A s \in Jobs : (sess[s].st \in {"run", "reg"} => ~sess[s].closing) /\ (sess[s].st \in {"clean", "torn"} => sess[s].closing)
Inv38 ==
  \A c \in Conns : sCh[c].hpc = "c_int" /\ sCh[c].cs # 0 =>
       /\ sCh[c].cs = sCh[c].ctgt /\ sess[sCh[c].cs].st \in {"reg", "run", "clean"}
       /\ sCh[c].ctran \in {0, sess[sCh[c].cs].tran}
Inv39 ==
  \A c \in Conns : sCh[c].hpc = "c_int" => Names(c, sCh[c].ctok, sCh[c].ctgt)
Inv40 ==
  \A c \in Conns : sCh[c].hpc # "idle" => sCh[c].st = "open"
  \* C5: stop() frees only an empty manager
Inv41 ==
  stopping <=> stopPc # "no"
Inv42 ==
  finishers = Cardinality({s \in Jobs : sess[s].st \in {"fin1", "fin2"}})
Inv43 ==
  stopPc \in {"fin_wait", "join", "free", "done"} => \A s \in Jobs : ~(sess[s].st \in InReg /\ sess[s].inc = sInc)
Inv44 ==
  stopPc \in {"fin_wait", "join", "free", "done"} => \A c \in Conns : sCh[c].hpc \notin {"h_ack", "h_spawn"}
Inv45 ==
  stopPc \in {"join", "free", "done"} => finishers = 0
Inv46 ==
  stopPc \in {"free", "done"} => \A c \in Conns : sCh[c].st # "open"
Inv47 ==
  stopPc # "no" => \A c \in Conns : sCh[c].st # "pend"
Inv48 ==
  mFreed <=> stopPc = "done"
Inv49 ==
  \A s \in Jobs : sess[s].st \in {"fin1", "fin2"} => sess[s].inc = sInc /\ sUp
  \* a crashed server holds no session and no newest channel
Inv50 ==
  ~sUp /\ stopPc = "no" => latest = 0 /\ finishers = 0 /\ \A s \in Jobs : sess[s].st \in {"none", "done", "dead"}
  \* the broker reads only its published channel or the one it is dialing
Inv51 ==
  \A c \in Conns : BrkReads(c) => published = c \/ (dch = c /\ dpc \in {"hello", "resync"})
  \* a driver is handed off once: one HANDOFF on the wire or one channel handling it, before its session exists
Inv52 ==
  \A c \in Conns : \A k \in Positions(b2s[c]) : b2s[c][k].op = "HANDOFF" =>
       /\ b2s[c][k].s \in Jobs /\ sess[b2s[c][k].s].st = "none"
       /\ \A d \in Conns : sCh[d].hpc \in {"h_check", "h_reg"} => sCh[d].hs # b2s[c][k].s
       /\ \A d \in Conns : \A k2 \in Positions(b2s[d]) :
            b2s[d][k2].op = "HANDOFF" /\ b2s[d][k2].s = b2s[c][k].s => d = c /\ k2 = k
Inv53 ==
  \A c \in Conns : sCh[c].hpc \in {"h_check", "h_reg"} =>
       /\ sCh[c].hs \in Jobs /\ sess[sCh[c].hs].st = "none"
       /\ \A d \in Conns : d # c /\ sCh[d].hpc \in {"h_check", "h_reg"} => sCh[d].hs # sCh[c].hs
  \* each direction carries only its own operations; HELLO opens the channel and is never sent again
Inv54 ==
  \A c \in Conns :
    /\ \A k \in Positions(b2s[c]) :
         b2s[c][k].op \in {"HELLO", "RESYNC", "HANDOFF", "CANCEL"} /\ (b2s[c][k].op = "HELLO" => k = 1)
    /\ \A k \in Positions(s2b[c]) : s2b[c][k].op \in {"HELLO_ACK", "ACK", "REJECT", "RESYNC_REPLY", "END"}
    /\ mailbox[c].op \in {"none", "HELLO_ACK", "ACK", "REJECT", "RESYNC_REPLY"}
  \* a channel handler's fields hold only its current request; incarnations never run ahead
Inv55 ==
  \A c \in Conns :
    /\ sCh[c].hpc # "c_int" => sCh[c].ctok = 0 /\ sCh[c].ctgt = 0 /\ sCh[c].cs = 0 /\ sCh[c].ctran = 0
    /\ sCh[c].cs = 0 => sCh[c].ctran = 0
    /\ sCh[c].hpc \in {"idle", "c_int", "r_send"} => sCh[c].hs = 0
    /\ sCh[c].snap = {}
    /\ sCh[c].inc <= sInc /\ bCh[c].inc <= bInc
    /\ mailbox[c].op = "none" => mailbox[c] = NoMsg
  \* every message has the shape its sender builds
\* @type: ($msg) => Bool;
Shaped(m) ==
  IF m.op \in {"none", "HELLO", "HELLO_ACK", "RESYNC", "REJECT"} THEN m = Msg(m.op, 0, 0)
  ELSE IF m.op = "HANDOFF" THEN m = Msg("HANDOFF", 0, m.s)
  ELSE IF m.op = "RESYNC_REPLY" THEN m.tok = 0 /\ m.s = 0
  ELSE m.toks = {}
Inv56 ==
  \A c \in Conns :
    /\ Shaped(mailbox[c])
    /\ \A k \in Positions(b2s[c]) : Shaped(b2s[c][k])
    /\ \A k \in Positions(s2b[c]) : Shaped(s2b[c][k])
  \* a session sends its SESSION_END once, after it left the registry
Inv57 ==
  \A c \in Conns : \A k \in Positions(s2b[c]) : s2b[c][k].op = "END" =>
       /\ sess[s2b[c][k].s].st \in {"fin3", "done", "dead"}
       /\ \A d \in Conns : \A k2 \in Positions(s2b[d]) :
            s2b[d][k2].op = "END" /\ s2b[d][k2].s = s2b[c][k].s => d = c /\ k2 = k
  \* a driver not yet handed off has no session, no HANDOFF on the wire and no channel handling it
Inv58 ==
  /\ \A s \in Jobs : sess[s].st = "none" => sess[s] = NoSess
  /\ \A j \in Jobs : jobs[j] = "queued" \/ (dj = j /\ dpc \in {"admit", "getch", "hello", "resync", "send"}) =>
       /\ sess[j].st = "none" /\ (jobs[j] = "queued" => dj # j)
       /\ \A c \in Conns : sCh[c].hpc \in {"h_check", "h_reg"} => sCh[c].hs # j
       /\ \A c \in Conns : \A k \in Positions(b2s[c]) : b2s[c][k].op = "HANDOFF" => b2s[c][k].s # j
  \* the broker sends nothing behind its HELLO until the server answered it
Inv59 ==
  \A c \in Conns : HelloPending(c) =>
       /\ b2s[c] = <<Msg("HELLO", 0, 0)>> /\ s2b[c] = <<>> /\ mailbox[c] = NoMsg /\ bCh[c].st # "pub"
       /\ sCh[c].hpc = "idle"
       /\ BrkReads(c) => dch = c /\ dpc = "hello"
  \* a crash ends every session of its incarnation
Inv60 ==
  \A s \in Jobs : sess[s].st \in Alive => sess[s].inc = sInc /\ (sUp \/ sess[s].st = "fin3")
  \* a signing-off session's channel is one the server already greeted
Inv61 ==
  \A s \in Jobs : sess[s].st = "fin2" => sess[s].fch <= latest
  \* a channel carries one RESYNC, sent and handled while the dispatcher waits for its reply
Inv62 ==
  \A c \in Conns :
    /\ Cardinality({k \in Positions(b2s[c]) : b2s[c][k].op = "RESYNC"}) + (IF sCh[c].hpc = "r_send" THEN 1 ELSE 0) <= 1
    /\ BrkReads(c) /\ ((\E k \in Positions(b2s[c]) : b2s[c][k].op = "RESYNC") \/ sCh[c].hpc = "r_send") =>
         dpc = "resync" /\ dch = c
  \* HANDOFF and CANCEL go out only on a published channel, after its RESYNC was answered
Inv63 ==
  \A c \in Conns : (\E k \in Positions(b2s[c]) : b2s[c][k].op \in {"HANDOFF", "CANCEL"}) =>
       bCh[c].st \notin {"none", "dial"} /\ sCh[c].hpc # "r_send"
  \* incarnations start at 1; a channel admits nothing before the server answered its HELLO; a session past its
  \* registration is closing
Inv64 ==
  /\ sInc >= 1 /\ bInc >= 1
  /\ \A c \in Conns : HelloPending(c) => \A x \in tokens : x.gen # c
  /\ \A s \in Jobs : sess[s].st \in {"clean", "torn", "fin1", "fin2", "fin3", "done"} => sess[s].closing

IndInv ==
  /\ Inv01
  /\ Inv02
  /\ Inv03
  /\ Inv04
  /\ Inv05
  /\ Inv06
  /\ Inv07
  /\ Inv08
  /\ Inv09
  /\ Inv10
  /\ Inv11
  /\ Inv12
  /\ Inv13
  /\ Inv14
  /\ Inv15
  /\ Inv16
  /\ Inv17
  /\ Inv18
  /\ Inv19
  /\ Inv20
  /\ Inv21
  /\ Inv22
  /\ Inv23
  /\ Inv24
  /\ Inv25
  /\ Inv26
  /\ Inv27
  /\ Inv28
  /\ Inv29
  /\ Inv30
  /\ Inv31
  /\ Inv32
  /\ Inv33
  /\ Inv34
  /\ Inv35
  /\ Inv36
  /\ Inv37
  /\ Inv38
  /\ Inv39
  /\ Inv40
  /\ Inv41
  /\ Inv42
  /\ Inv43
  /\ Inv44
  /\ Inv45
  /\ Inv46
  /\ Inv47
  /\ Inv48
  /\ Inv49
  /\ Inv50
  /\ Inv51
  /\ Inv52
  /\ Inv53
  /\ Inv54
  /\ Inv55
  /\ Inv56
  /\ Inv57
  /\ Inv58
  /\ Inv59
  /\ Inv60
  /\ Inv61
  /\ Inv62
  /\ Inv63
  /\ Inv64

\* witnesses: reachable outcomes
NotAcked == "acked" \notin hit
NotCancelled == "cancelled" \notin hit
NotTimedOut == "timeout" \notin hit
NotNoServer == \A j \in Jobs : jobs[j] # "nosrv"
NotFull == \A j \in Jobs : jobs[j] # "full"
NotReadmitted == "readmit" \notin hit
NotStoppedClean == "stopped" \notin hit
NotUndone == "undone" \notin hit

=============================================================================
