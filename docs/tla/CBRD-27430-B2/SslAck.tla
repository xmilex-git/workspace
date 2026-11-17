------------------------------- MODULE SslAck -------------------------------
(* CBRD-27430 B2: when the broker answers a driver's connect.

   A driver sends its 10-byte header and waits for a 4-byte answer: 0 (the ack) or an error code. After the
   ack a cleartext driver sends its db_info, which the broker reads to route by database name; an SSL driver
   starts the TLS handshake and gives its peer one second to answer, so its ack must wait until a server has
   the connection. The broker parks an SSL client without the ack, routes it to DIRECT_HANDOFF_SSL_DB,
   waits for a handoff slot, hands the descriptor to the server and sends the ack when HANDOFF_ACK arrives.
   Whatever fails before that (no slot in time, no server, HANDOFF_REJECT, a channel failure with the
   descriptor still the broker's) is answered with the error code in place of the ack.

   One client: the steps of one connect are the receiver's, then the dispatcher's, with the server's
   handling between the dispatcher's request and its reply; other clients appear as the slot the dispatcher
   may not get.

   Constants:
     Ssl     the client is an SSL client
     Mutant  "none" | "ack_at_park" | "ack_before_reply" *)
EXTENDS Naturals

CONSTANTS Ssl, Mutant

\* apalache-type: Ssl Bool
\* apalache-type: Mutant Str
\* apalache-type: bpc Str
\* apalache-type: acked Bool
\* apalache-type: erred Bool
\* apalache-type: order Str
\* apalache-type: held Bool
\* apalache-type: ackHeld Bool
\* apalache-type: spc Str
\* apalache-type: brokerFd Bool

\* bpc: the broker's place in the connect: "recv" | "peek" | "queued" | "dial" | "slot" | "request"
\*   | "reply" | "end"
\* acked: the broker sent the ack
\* erred: the broker sent an error code
\* order: what the driver was sent first: "" | "ack" | "err"
\* held: a server registered the session: it has the descriptor
\* ackHeld: the ack was sent while a server had the connection (SSL clients)
\* spc: the server's place: "none" | "acked" | "rejected" | "late" | "serving" | "closed"
\* brokerFd: the broker still has its copy of the descriptor
VARIABLES bpc, acked, erred, order, held, ackHeld, spc, brokerFd

vars == <<bpc, acked, erred, order, held, ackHeld, spc, brokerFd>>

Init ==
  /\ bpc = "recv" /\ acked = FALSE /\ erred = FALSE /\ order = ""
  /\ held = FALSE /\ ackHeld = TRUE /\ spc = "none" /\ brokerFd = TRUE

First(what) == IF order = "" THEN what ELSE order

SendAck ==
  /\ acked' = TRUE /\ order' = First("ack")
  /\ ackHeld' = IF Ssl THEN held ELSE ackHeld

SendErr == erred' = TRUE /\ order' = First("err")

\* brd_park_client: a cleartext client is acked and its db_info awaited; an SSL client is queued unacked
BPark ==
  /\ bpc = "recv"
  /\ IF Ssl /\ Mutant # "ack_at_park"
       THEN bpc' = "queued" /\ UNCHANGED <<acked, order, ackHeld>>
       ELSE SendAck /\ bpc' = IF Ssl THEN "queued" ELSE "peek"
  /\ UNCHANGED <<erred, held, spc, brokerFd>>

\* the peek engine: the db_info came, or its time ran out (the connection is dropped, as a CAS dropped it)
BPeeked ==
  /\ bpc = "peek"
  /\ bpc' = "queued"
  /\ UNCHANGED <<acked, erred, order, held, ackHeld, spc, brokerFd>>

BPeekTimeout ==
  /\ bpc = "peek"
  /\ bpc' = "end" /\ brokerFd' = FALSE
  /\ UNCHANGED <<acked, erred, order, held, ackHeld, spc>>

\* brd_dispatch_job takes the job
BDequeue ==
  /\ bpc = "queued"
  /\ bpc' = "dial"
  /\ UNCHANGED <<acked, erred, order, held, ackHeld, spc, brokerFd>>

\* channel_get_or_dial: the server is up, or not
BDial(up) ==
  /\ bpc = "dial"
  /\ IF up THEN bpc' = "slot" /\ UNCHANGED <<erred, order, brokerFd>>
           ELSE SendErr /\ bpc' = "end" /\ brokerFd' = FALSE
  /\ UNCHANGED <<acked, held, ackHeld, spc>>

\* brd_wait_for_slot: a slot, or the admission budget ran out
BSlot(got) ==
  /\ bpc = "slot"
  /\ IF got THEN bpc' = "request" /\ UNCHANGED <<erred, order, brokerFd>>
            ELSE SendErr /\ bpc' = "end" /\ brokerFd' = FALSE
  /\ UNCHANGED <<acked, held, ackHeld, spc>>

\* the HANDOFF with the descriptor is sent; the channel may fail before the descriptor left
BRequest(sent) ==
  /\ bpc = "request"
  /\ IF sent
       THEN /\ bpc' = "reply"
            /\ IF Mutant = "ack_before_reply" /\ Ssl THEN SendAck ELSE UNCHANGED <<acked, order, ackHeld>>
            /\ UNCHANGED <<erred, brokerFd>>
       ELSE /\ SendErr /\ bpc' = "end" /\ brokerFd' = FALSE
            /\ UNCHANGED <<acked, ackHeld>>
  /\ UNCHANGED <<held, spc>>

\* the server's channel thread: handle_handoff registers the session and answers HANDOFF_ACK, or refuses
SHandle(ok) ==
  /\ bpc = "reply" /\ spc = "none"
  /\ IF ok THEN spc' = "acked" /\ held' = TRUE ELSE spc' = "rejected" /\ UNCHANGED held
  /\ UNCHANGED <<bpc, acked, erred, order, ackHeld, brokerFd>>

\* HANDOFF_ACK read: the ack an SSL client waits for, then the broker closes its copy
BAck ==
  /\ bpc = "reply" /\ spc = "acked"
  /\ IF Ssl /\ ~acked THEN SendAck ELSE UNCHANGED <<acked, order, ackHeld>>
  /\ bpc' = "end" /\ brokerFd' = FALSE
  /\ spc' = "serving"
  /\ UNCHANGED <<erred, held>>

\* HANDOFF_REJECT read: the error code, the broker closes the connection
BReject ==
  /\ bpc = "reply" /\ spc = "rejected"
  /\ SendErr /\ bpc' = "end" /\ brokerFd' = FALSE
  /\ UNCHANGED <<acked, held, ackHeld, spc>>

\* no reply in time and the descriptor left: the broker closes its copy and says nothing; the server serves
\* the connection or drops it (an SSL client that was not acked sends nothing, and the handshake's time ends)
BReplyTimeout ==
  /\ bpc = "reply" /\ spc \in {"none", "acked"}
  /\ bpc' = "end" /\ brokerFd' = FALSE
  /\ spc' = "late"
  /\ UNCHANGED <<acked, erred, order, held, ackHeld>>

SLate ==
  /\ spc = "late"
  /\ spc' = "closed"
  /\ UNCHANGED <<bpc, acked, erred, order, held, ackHeld, brokerFd>>

Next ==
  \/ BPark \/ BPeeked \/ BPeekTimeout \/ BDequeue \/ BAck \/ BReject \/ BReplyTimeout \/ SLate
  \/ \E b \in BOOLEAN : BDial(b) \/ BSlot(b) \/ BRequest(b) \/ SHandle(b)

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ bpc \in {"recv", "peek", "queued", "dial", "slot", "request", "reply", "end"}
  /\ acked \in BOOLEAN /\ erred \in BOOLEAN /\ order \in {"", "ack", "err"}
  /\ held \in BOOLEAN /\ ackHeld \in BOOLEAN
  /\ spc \in {"none", "acked", "rejected", "late", "serving", "closed"}
  /\ brokerFd \in BOOLEAN

\* C1: an SSL client is sent the ack only while a server has its connection
AckAfterHandoff == ackHeld

\* C1: an SSL client is sent the ack or one error code, never both
OneAnswer == Ssl => ~(acked /\ erred)

\* the broker writes to the client only while it has the descriptor, and at most one error code
AnswerShape == (order = "ack" => acked) /\ (order = "err" => erred /\ ~acked)

(* ---- the inductive invariant ---- *)

\* the broker has the descriptor until its part of the connect ends
FdUntilEnd == brokerFd <=> bpc # "end"

\* what the driver was sent first, and what it was sent
OrderWf ==
  /\ order = "" <=> (~acked /\ ~erred)
  /\ order = "ack" => acked
  /\ order = "err" => erred /\ ~acked

\* a cleartext client is acked when it is parked; an SSL client only by the HANDOFF_ACK
AckPlace ==
  /\ ~Ssl => (acked <=> bpc # "recv")
  /\ Ssl /\ acked => bpc = "end" /\ spc = "serving"

\* an error code ends the broker's part
ErrEnds == erred => bpc = "end" /\ spc \in {"none", "rejected"}

\* the server's place against the broker's
ServerPlace ==
  /\ spc # "none" => bpc \in {"reply", "end"}
  /\ bpc = "reply" => spc \in {"none", "acked", "rejected"}
  /\ spc \in {"serving", "late", "closed"} => bpc = "end"
  /\ bpc = "end" /\ spc = "rejected" => erred
  /\ spc \in {"acked", "serving"} => held
  /\ held => spc \in {"acked", "serving", "late", "closed"}

IndInv ==
  /\ TypeOK
  /\ FdUntilEnd
  /\ OrderWf
  /\ AckPlace
  /\ ErrEnds
  /\ ServerPlace
  /\ AckAfterHandoff
  /\ OneAnswer
  /\ AnswerShape

CInit == Ssl \in BOOLEAN /\ Mutant = "none"

\* witnesses
NotServed == ~(spc = "serving" /\ acked /\ ~erred)
NotRefusedUnacked == ~(bpc = "end" /\ erred /\ ~acked)
NotSilent == ~(bpc = "end" /\ ~acked /\ ~erred /\ spc = "closed")
NotAckThenErr == ~(acked /\ erred)

=============================================================================
