----------------------------- MODULE AutoSession -----------------------------
(* CBRD-27430 B1b: KEEP_CONNECTION=AUTO in the folded server.

   A broker has MaxSlots handoff slots for all its databases. A session of an AUTO broker that is idle at a
   request boundary (no transaction, no holdable cursor, no XA prepare, no method/SP callback resource) may be
   told to yield: its thread closes the driver connection, keeps the server session with its client context
   (detach) and gives the slot back. The driver connects again with the session id and the session secret it
   was given (the 20-byte driver session of CBRD-27434) and, after the password login, goes on with the kept
   session on a new thread (resume). A kept session nobody resumes is removed by the session control daemon
   after session_state_timeout, counted from the detach.

   Roles:
     T   attachment threads: one std::thread per handed-over driver connection (no executor reuse)
     S   server sessions (ids grow; sdb[s] is the database server that holds s)
     D   database servers behind the one broker; each runs a controller (its control channel thread)
     the broker's dispatcher (one job at a time), the session control daemon, the environment (drivers,
     cubrid broker reset, time)

   Constants:
     NT, NS, ND  sizes of T, S, D          MaxSlots  the broker's handoff slots
     MaxReq      requests a thread serves  MaxPass   daemon passes   MaxResets  broker resets
     QMax        control messages queued per channel
     Mutant      "none" | "no_excl" | "no_secret" | "no_auth" | "fail_destroys" | "no_renew" | "no_recheck"
                 | "retry_after_claim" | "no_watch_scan" | "no_idle_hint" | "reuse" | "leak_on_yield"
                 | "idle_dirty" | "no_begin" | "fresh_ctx" | "no_reset_check" | "reset_no_cas" *)
EXTENDS Naturals, FiniteSets

CONSTANTS NT, NS, ND, MaxSlots, MaxReq, MaxPass, MaxResets, QMax, Mutant

\* apalache-type: NT Int
\* apalache-type: NS Int
\* apalache-type: ND Int
\* apalache-type: MaxSlots Int
\* apalache-type: MaxReq Int
\* apalache-type: MaxPass Int
\* apalache-type: MaxResets Int
\* apalache-type: QMax Int
\* apalache-type: Mutant Str
\* apalache-type: pc Int -> Str
\* apalache-type: st Int -> Str
\* apalache-type: db Int -> Int
\* apalache-type: tgt Int -> Int
\* apalache-type: cred Int -> Str
\* apalache-type: att Int -> Int
\* apalache-type: cx Int -> Int
\* apalache-type: yld Int -> Bool
\* apalache-type: clean Int -> Bool
\* apalache-type: wake Int -> Bool
\* apalache-type: rreq Int -> Bool
\* apalache-type: reqs Int -> Int
\* apalache-type: slot Int -> Bool
\* apalache-type: obs Int -> Int
\* apalache-type: verK Int -> Int
\* apalache-type: resumed Int -> Bool
\* apalache-type: fail Int -> Bool
\* apalache-type: dirtyStart Int -> Bool
\* apalache-type: present Int -> Bool
\* apalache-type: kept Int -> Bool
\* apalache-type: ref Int -> Int
\* apalache-type: exp Int -> Bool
\* apalache-type: holder Int -> Int
\* apalache-type: orphan Int -> Bool
\* apalache-type: tear Int -> Int
\* apalache-type: ver Int -> Int
\* apalache-type: sdb Int -> Int
\* apalache-type: nextSid Int
\* apalache-type: slock Int
\* apalache-type: xpc Str
\* apalache-type: xcand Int
\* apalache-type: snapTaken Bool
\* apalache-type: snap Set(Int)
\* apalache-type: passes Int
\* apalache-type: cpc Int -> Str
\* apalache-type: ccand Int -> Int
\* apalache-type: q Int -> (Int -> Str)
\* apalache-type: qn Int -> Int
\* apalache-type: wreq Int -> Bool
\* apalache-type: rset Int -> Set(Int)
\* apalache-type: bpc Str
\* apalache-type: job Int
\* apalache-type: tryLeft Set(Int)
\* apalache-type: tryD Int
\* apalache-type: tryRep Str
\* apalache-type: claimed Bool
\* apalache-type: watching Bool
\* apalache-type: wset Set(Int)
\* apalache-type: hint Bool
\* apalache-type: slotsUsed Int
\* apalache-type: jobYields Int
\* apalache-type: resets Int
\* apalache-type: badExec Bool
\* apalache-type: expInUse Bool
\* apalache-type: failDestroyed Bool
\* apalache-type: tlsDirty Bool
\* apalache-type: crossYield Bool

Mutants == {"none", "no_excl", "no_secret", "no_auth", "fail_destroys", "no_renew", "no_recheck",
            "retry_after_claim", "no_watch_scan", "no_idle_hint", "reuse", "leak_on_yield", "idle_dirty",
            "no_begin", "fresh_ctx", "no_reset_check", "reset_no_cas"}

ASSUME Assm ==
  /\ NT \in Nat \ {0} /\ NS \in Nat \ {0} /\ ND \in Nat \ {0} /\ MaxSlots \in Nat \ {0}
  /\ MaxReq \in Nat /\ MaxPass \in Nat /\ MaxResets \in Nat /\ QMax \in Nat \ {0}
  /\ Mutant \in Mutants

T == 1..NT
S == 1..NS
D == 1..ND
QIdx == 1..QMax

Creds == {"good", "badsecret", "badauth"}
\* a thread's steps: the handoff ("new" until the broker admits it), the session claim, its request loop
\* (RunPcs), and the retire tail
RunPcs == {"top", "rst", "wch", "wx", "wait", "exec", "exit"}
Pcs == {"new", "claim", "swap", "auth"} \cup RunPcs \cup {"end", "free", "deact", "send", "done"}
States == {"busy", "idle", "yielded", "closing"}
Msgs == {"none", "try", "w1", "w0", "reset"}
CPcs == {"idle", "tcas", "twake", "w1", "wscan", "wx", "rmark", "rcas"}
BPcs == {"free", "top", "try", "tryw", "watch", "wait"}
XPcs == {"scan", "recheck", "tear"}

(* thread t
     pc, st      its step; its binding's execution_state
     db, tgt, cred  the database the driver named, the session it presents (0: none) and what it knows:
                 "good", "badsecret" (wrong session secret), "badauth" (right secret, wrong user or password)
     att         the session its conn entry is attached to (conn->session_p), 0: none
     cx          the session whose client context its bracket holds, 0: none (its own unadopted context is not
                 modelled)
     yld         the connection ended by a yield (registry_auto_finish)
     clean       the request boundary it is at allows a detach
     wake        its wake eventfd is readable;  rreq  its binding's reset_requested
     reqs        requests it served;  slot  it holds a broker slot (HANDOFF_ACK until SESSION_END)
     obs, verK   the session state it found in the context it activated / the state the session had when claimed
     resumed, fail  it claimed a kept session / its login on it failed
     dirtyStart  ghost: it started on a thread that served another session
   session s
     present, kept, ref, exp  in the session hash; kept for a resume (csc_kept); ref_count; older than
                 session_state_timeout by its active_time
     holder      the thread inside its client context's bracket (0: none)
     orphan      destroyed from inside its bracket, the context is torn down when the bracket closes
     tear        ghost: teardowns of its client context;  ver  its session state (a counter of requests)
     slock       the session whose state mutex the daemon holds across its teardown (0: none)
   daemon   xpc, xcand, snapTaken, snap (the active connections' sessions, read once per pass), passes
   controller of d   cpc, ccand, q/qn (its channel's queue), wreq (watch_requested), rset (bindings a reset
                 still has to mark)
   broker   bpc, job, tryLeft, tryD, tryRep, claimed, watching, wset, hint (an IDLE_HINT arrived since the
                 dispatcher last read the generation), slotsUsed, jobYields (ghost), resets
   ghosts   badExec, expInUse, failDestroyed, tlsDirty, crossYield *)
VARIABLES pc, st, db, tgt, cred, att, cx, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail,
          dirtyStart,
          present, kept, ref, exp, holder, orphan, tear, ver, sdb, nextSid, slock,
          xpc, xcand, snapTaken, snap, passes,
          cpc, ccand, q, qn, wreq, rset,
          bpc, job, tryLeft, tryD, tryRep, claimed, watching, wset, hint, slotsUsed, jobYields, resets,
          badExec, expInUse, failDestroyed, tlsDirty, crossYield

tvars == <<pc, st, db, tgt, cred, att, cx, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail,
           dirtyStart>>
svars == <<present, kept, ref, exp, holder, orphan, tear, ver, sdb, nextSid, slock>>
xvars == <<xpc, xcand, snapTaken, snap, passes>>
cvars == <<cpc, ccand, q, qn, wreq, rset>>
bvars == <<bpc, job, tryLeft, tryD, tryRep, claimed, watching, wset, hint, slotsUsed, jobYields, resets>>
\* @type: <<Bool, Bool, Bool, Bool, Bool>>;
gvars == <<badExec, expInUse, failDestroyed, tlsDirty, crossYield>>
vars == <<tvars, svars, xvars, cvars, bvars, gvars>>

TypeOK ==
  /\ pc \in [T -> Pcs] /\ st \in [T -> States] /\ db \in [T -> D] /\ tgt \in [T -> 0..NS]
  /\ cred \in [T -> Creds] /\ att \in [T -> 0..NS] /\ cx \in [T -> 0..NS]
  /\ yld \in [T -> BOOLEAN] /\ clean \in [T -> BOOLEAN] /\ wake \in [T -> BOOLEAN] /\ rreq \in [T -> BOOLEAN]
  /\ reqs \in [T -> 0..MaxReq] /\ slot \in [T -> BOOLEAN]
  /\ obs \in [T -> 0..(NT * MaxReq)] /\ verK \in [T -> 0..(NT * MaxReq)]
  /\ resumed \in [T -> BOOLEAN] /\ fail \in [T -> BOOLEAN] /\ dirtyStart \in [T -> BOOLEAN]
  /\ present \in [S -> BOOLEAN] /\ kept \in [S -> BOOLEAN] /\ ref \in [S -> 0..NT] /\ exp \in [S -> BOOLEAN]
  /\ holder \in [S -> 0..NT] /\ orphan \in [S -> BOOLEAN] /\ tear \in [S -> 0..(NT + 1)]
  /\ ver \in [S -> 0..(NT * MaxReq)] /\ sdb \in [S -> D] /\ nextSid \in 1..(NS + 1) /\ slock \in 0..NS
  /\ xpc \in XPcs /\ xcand \in 0..NS /\ snapTaken \in BOOLEAN /\ snap \in SUBSET S /\ passes \in 0..MaxPass
  /\ cpc \in [D -> CPcs] /\ ccand \in [D -> 0..NT] /\ q \in [D -> [QIdx -> Msgs]] /\ qn \in [D -> 0..QMax]
  /\ wreq \in [D -> BOOLEAN] /\ rset \in [D -> SUBSET T]
  /\ bpc \in BPcs /\ job \in 0..NT /\ tryLeft \in SUBSET D /\ tryD \in 0..ND
  /\ tryRep \in {"none", "yes", "no"} /\ claimed \in BOOLEAN /\ watching \in BOOLEAN /\ wset \in SUBSET D
  /\ hint \in BOOLEAN /\ slotsUsed \in 0..(NT + 1) /\ jobYields \in 0..NT /\ resets \in 0..MaxResets
  /\ badExec \in BOOLEAN /\ expInUse \in BOOLEAN /\ failDestroyed \in BOOLEAN /\ tlsDirty \in BOOLEAN
  /\ crossYield \in BOOLEAN

Init ==
  /\ pc = [t \in T |-> "new"] /\ st = [t \in T |-> "busy"] /\ db = [t \in T |-> 1] /\ tgt = [t \in T |-> 0]
  /\ cred = [t \in T |-> "good"] /\ att = [t \in T |-> 0] /\ cx = [t \in T |-> 0]
  /\ yld = [t \in T |-> FALSE] /\ clean = [t \in T |-> FALSE] /\ wake = [t \in T |-> FALSE]
  /\ rreq = [t \in T |-> FALSE] /\ reqs = [t \in T |-> 0] /\ slot = [t \in T |-> FALSE]
  /\ obs = [t \in T |-> 0] /\ verK = [t \in T |-> 0] /\ resumed = [t \in T |-> FALSE]
  /\ fail = [t \in T |-> FALSE] /\ dirtyStart = [t \in T |-> FALSE]
  /\ present = [s \in S |-> FALSE] /\ kept = [s \in S |-> FALSE] /\ ref = [s \in S |-> 0]
  /\ exp = [s \in S |-> FALSE] /\ holder = [s \in S |-> 0] /\ orphan = [s \in S |-> FALSE]
  /\ tear = [s \in S |-> 0] /\ ver = [s \in S |-> 0] /\ sdb = [s \in S |-> 1] /\ nextSid = 1 /\ slock = 0
  /\ xpc = "scan" /\ xcand = 0 /\ snapTaken = FALSE /\ snap = {} /\ passes = 0
  /\ cpc = [d \in D |-> "idle"] /\ ccand = [d \in D |-> 0] /\ q = [d \in D |-> [i \in QIdx |-> "none"]]
  /\ qn = [d \in D |-> 0] /\ wreq = [d \in D |-> FALSE] /\ rset = [d \in D |-> {}]
  /\ bpc = "free" /\ job = 0 /\ tryLeft = {} /\ tryD = 0 /\ tryRep = "none" /\ claimed = FALSE
  /\ watching = FALSE /\ wset = {} /\ hint = FALSE /\ slotsUsed = 0 /\ jobYields = 0 /\ resets = 0
  /\ badExec = FALSE /\ expInUse = FALSE /\ failDestroyed = FALSE /\ tlsDirty = FALSE /\ crossYield = FALSE

\* the databases that hold a slot of the broker (the token table's owners)
Owners == {d \in D : \E u \in T : slot[u] /\ db[u] = d}
\* the registry entries of database d: from the handoff until the session signs off
Reg(d) == {u \in T : db[u] = d /\ pc[u] \notin {"new", "done"}}
\* bindings of database d a controller's scan finds idle
IdleIn(d) == {u \in Reg(d) : st[u] = "idle"}
\* the control channel of d: one message appended, the head removed
Enq(d, m) == [q EXCEPT ![d] = [i \in QIdx |-> IF i = qn[d] + 1 THEN m ELSE q[d][i]]]
EnqAll(W, m) == [d \in D |-> IF d \in W THEN [i \in QIdx |-> IF i = qn[d] + 1 THEN m ELSE q[d][i]] ELSE q[d]]
QnAll(W) == [d \in D |-> IF d \in W THEN qn[d] + 1 ELSE qn[d]]
Room(W) == \A d \in W : qn[d] < QMax
Deq(d) == [q EXCEPT ![d] = [i \in QIdx |-> IF i < QMax THEN q[d][i + 1] ELSE "none"]]

(* ------------------------------------------------------------------------------------------------------- *)
(* the broker's dispatcher: one job at a time                                                              *)

\* a driver connects: a new session, or a session id with what the driver knows of it
BStart(t, d, s, c) ==
  /\ bpc = "free" /\ pc[t] = "new" /\ \A u \in T : u < t => pc[u] # "new"
  /\ \/ s = 0 /\ c = "good"
     \/ s \in S /\ s < nextSid /\ sdb[s] = d
  /\ job' = t /\ bpc' = "top"
  /\ db' = [db EXCEPT ![t] = d] /\ tgt' = [tgt EXCEPT ![t] = s] /\ cred' = [cred EXCEPT ![t] = c]
  /\ dirtyStart' = [dirtyStart EXCEPT ![t] = (Mutant = "reuse" /\ tlsDirty)]
  /\ UNCHANGED <<pc, st, att, cx, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail>>
  /\ UNCHANGED <<tryLeft, tryD, tryRep, claimed, watching, wset, hint, slotsUsed, jobYields, resets>>
  /\ UNCHANGED <<svars, xvars, cvars, gvars>>

\* the job is admitted: HANDOFF, HANDOFF_ACK (B1a), the session thread starts
Admitted ==
  /\ pc' = [pc EXCEPT ![job] = "claim"] /\ slot' = [slot EXCEPT ![job] = TRUE]
  /\ slotsUsed' = slotsUsed + 1
  /\ bpc' = "free" /\ job' = 0 /\ claimed' = FALSE /\ watching' = FALSE /\ jobYields' = 0
  /\ crossYield' = (crossYield \/ (claimed /\ tryD # db[job]))

\* the top of the admission loop: read the hint generation, then the owners
BTop ==
  /\ bpc = "top"
  /\ IF slotsUsed < MaxSlots
       THEN /\ Admitted
            /\ UNCHANGED <<tryLeft, hint>>
       ELSE /\ hint' = FALSE /\ tryLeft' = Owners /\ bpc' = "try"
            /\ UNCHANGED <<pc, slot, slotsUsed, job, claimed, watching, jobYields, crossYield>>
  /\ UNCHANGED <<st, db, tgt, cred, att, cx, yld, clean, wake, rreq, reqs, obs, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<tryD, tryRep, wset, resets>>
  /\ UNCHANGED <<svars, xvars, cvars, badExec, expInUse, failDestroyed, tlsDirty>>

\* YIELD_TRY to one owner, answered before the next
BTry(d) ==
  /\ bpc = "try" /\ d \in tryLeft /\ qn[d] < QMax
  /\ q' = Enq(d, "try") /\ qn' = [qn EXCEPT ![d] = qn[d] + 1]
  /\ tryD' = d /\ tryRep' = "none" /\ bpc' = "tryw"
  /\ UNCHANGED <<job, tryLeft, claimed, watching, wset, hint, slotsUsed, jobYields, resets>>
  /\ UNCHANGED <<cpc, ccand, wreq, rset>>
  /\ UNCHANGED <<tvars, svars, xvars, gvars>>

BTryRep ==
  /\ bpc = "tryw" /\ tryRep # "none"
  /\ IF tryRep = "yes"
       THEN /\ claimed' = TRUE /\ jobYields' = jobYields + 1 /\ bpc' = "wait"
            /\ UNCHANGED tryLeft
       ELSE /\ tryLeft' = tryLeft \ {tryD}
            /\ bpc' = IF tryLeft \ {tryD} = {} THEN "watch" ELSE "try"
            /\ UNCHANGED <<claimed, jobYields>>
  /\ tryRep' = "none"
  /\ UNCHANGED <<job, tryD, watching, wset, hint, slotsUsed, resets>>
  /\ UNCHANGED <<tvars, svars, xvars, cvars, gvars>>

\* no owner had an idle session: ask every owner for a hint when one goes idle
BWatch ==
  /\ bpc = "watch" /\ Room(Owners)
  /\ q' = EnqAll(Owners, "w1") /\ qn' = QnAll(Owners)
  /\ wset' = Owners /\ watching' = TRUE /\ bpc' = "wait"
  /\ UNCHANGED <<job, tryLeft, tryD, tryRep, claimed, hint, slotsUsed, jobYields, resets>>
  /\ UNCHANGED <<cpc, ccand, wreq, rset>>
  /\ UNCHANGED <<tvars, svars, xvars, gvars>>

\* the wait ends: the watch is withdrawn on the channels it was sent to
Cancel == IF watching THEN q' = EnqAll(wset, "w0") /\ qn' = QnAll(wset) ELSE UNCHANGED <<q, qn>>
CanCancel == watching => Room(wset)

BSlot ==
  /\ bpc = "wait" /\ slotsUsed < MaxSlots /\ CanCancel
  /\ Cancel /\ Admitted
  /\ UNCHANGED <<st, db, tgt, cred, att, cx, yld, clean, wake, rreq, reqs, obs, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<tryLeft, tryD, tryRep, wset, hint, resets>>
  /\ UNCHANGED <<cpc, ccand, wreq, rset>>
  /\ UNCHANGED <<svars, xvars, badExec, expInUse, failDestroyed, tlsDirty>>

\* a hint ends the wait; mutant retry_after_claim: so does impatience, while the claimed session is on its way out
BHint ==
  /\ bpc = "wait" /\ CanCancel
  /\ (watching /\ hint) \/ (Mutant = "retry_after_claim" /\ claimed)
  /\ Cancel /\ watching' = FALSE /\ bpc' = "top"
  /\ UNCHANGED <<job, tryLeft, tryD, tryRep, claimed, wset, hint, slotsUsed, jobYields, resets>>
  /\ UNCHANGED <<cpc, ccand, wreq, rset>>
  /\ UNCHANGED <<tvars, svars, xvars, gvars>>

\* the admission deadline: the driver gets the retryable error
BTimeout ==
  /\ bpc = "wait" /\ CanCancel
  /\ Cancel
  /\ pc' = [pc EXCEPT ![job] = "done"]
  /\ bpc' = "free" /\ job' = 0 /\ claimed' = FALSE /\ watching' = FALSE /\ jobYields' = 0
  /\ UNCHANGED <<st, db, tgt, cred, att, cx, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail,
                 dirtyStart>>
  /\ UNCHANGED <<tryLeft, tryD, tryRep, wset, hint, slotsUsed, resets>>
  /\ UNCHANGED <<cpc, ccand, wreq, rset>>
  /\ UNCHANGED <<svars, xvars, gvars>>

\* cubrid broker reset reaches the server of d
EReset(d) ==
  /\ resets < MaxResets /\ qn[d] < QMax
  /\ q' = Enq(d, "reset") /\ qn' = [qn EXCEPT ![d] = qn[d] + 1] /\ resets' = resets + 1
  /\ UNCHANGED <<bpc, job, tryLeft, tryD, tryRep, claimed, watching, wset, hint, slotsUsed, jobYields>>
  /\ UNCHANGED <<cpc, ccand, wreq, rset>>
  /\ UNCHANGED <<tvars, svars, xvars, gvars>>

(* ------------------------------------------------------------------------------------------------------- *)
(* the controller of database d: its control channel thread, one message at a time                         *)

CStart(d) ==
  /\ cpc[d] = "idle" /\ qn[d] > 0
  /\ q' = Deq(d) /\ qn' = [qn EXCEPT ![d] = qn[d] - 1]
  /\ LET m == q[d][1] IN
       /\ cpc' = [cpc EXCEPT ![d] = IF m = "try" /\ Reg(d) # {} THEN "tcas"
                                     ELSE IF m = "w1" THEN "w1"
                                     ELSE IF m = "reset" /\ Reg(d) # {} THEN "rmark"
                                     ELSE "idle"]
       /\ wreq' = IF m = "w0" THEN [wreq EXCEPT ![d] = FALSE] ELSE wreq
       /\ rset' = IF m \in {"try", "reset"} THEN [rset EXCEPT ![d] = Reg(d)] ELSE rset
       /\ tryRep' = IF m = "try" /\ Reg(d) = {} THEN "no" ELSE tryRep
  /\ UNCHANGED <<ccand>>
  /\ UNCHANGED <<bpc, job, tryLeft, tryD, claimed, watching, wset, hint, slotsUsed, jobYields, resets>>
  /\ UNCHANGED <<tvars, svars, xvars, gvars>>

\* YIELD_TRY: one pass over the registry under registry_mutex, a compare-and-swap idle -> yielded per binding;
\* the first that succeeds is the answer yes, none is the answer no
CTCas(d, u) ==
  /\ cpc[d] = "tcas" /\ u \in rset[d]
  /\ IF st[u] = "idle"
       THEN /\ st' = [st EXCEPT ![u] = "yielded"] /\ ccand' = [ccand EXCEPT ![d] = u]
            /\ rset' = [rset EXCEPT ![d] = {}] /\ cpc' = [cpc EXCEPT ![d] = "twake"]
            /\ UNCHANGED tryRep
       ELSE /\ rset' = [rset EXCEPT ![d] = rset[d] \ {u}]
            /\ cpc' = [cpc EXCEPT ![d] = IF rset[d] \ {u} = {} THEN "idle" ELSE "tcas"]
            /\ tryRep' = IF rset[d] \ {u} = {} THEN "no" ELSE tryRep
            /\ UNCHANGED <<st, ccand>>
  /\ UNCHANGED <<pc, db, tgt, cred, att, cx, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail,
                 dirtyStart>>
  /\ UNCHANGED <<q, qn, wreq>>
  /\ UNCHANGED <<bpc, job, tryLeft, tryD, claimed, watching, wset, hint, slotsUsed, jobYields, resets>>
  /\ UNCHANGED <<svars, xvars, gvars>>

CTWake(d) ==
  /\ cpc[d] = "twake"
  /\ wake' = [wake EXCEPT ![ccand[d]] = TRUE]
  /\ tryRep' = "yes" /\ cpc' = [cpc EXCEPT ![d] = "idle"]
  /\ UNCHANGED <<pc, st, db, tgt, cred, att, cx, yld, clean, rreq, reqs, slot, obs, verK, resumed, fail,
                 dirtyStart>>
  /\ UNCHANGED <<ccand, q, qn, wreq, rset>>
  /\ UNCHANGED <<bpc, job, tryLeft, tryD, claimed, watching, wset, hint, slotsUsed, jobYields, resets>>
  /\ UNCHANGED <<svars, xvars, gvars>>

\* IDLE_WATCH(1): the request is published before the scan for a binding that is idle already
CW1(d) ==
  /\ cpc[d] = "w1"
  /\ wreq' = [wreq EXCEPT ![d] = TRUE]
  /\ cpc' = [cpc EXCEPT ![d] = IF Mutant = "no_watch_scan" THEN "idle" ELSE "wscan"]
  /\ UNCHANGED <<ccand, q, qn, rset>>
  /\ UNCHANGED <<tvars, svars, xvars, bvars, gvars>>

CWScan(d) ==
  /\ cpc[d] = "wscan"
  /\ cpc' = [cpc EXCEPT ![d] = IF IdleIn(d) # {} THEN "wx" ELSE "idle"]
  /\ UNCHANGED <<ccand, q, qn, wreq, rset>>
  /\ UNCHANGED <<tvars, svars, xvars, bvars, gvars>>

\* watch_requested.exchange (false): whoever takes it sends the one IDLE_HINT
CWX(d) ==
  /\ cpc[d] = "wx"
  /\ wreq' = [wreq EXCEPT ![d] = FALSE]
  /\ hint' = (hint \/ wreq[d])
  /\ cpc' = [cpc EXCEPT ![d] = "idle"]
  /\ UNCHANGED <<ccand, q, qn, rset>>
  /\ UNCHANGED <<bpc, job, tryLeft, tryD, tryRep, claimed, watching, wset, slotsUsed, jobYields, resets>>
  /\ UNCHANGED <<tvars, svars, xvars, gvars>>

\* broker reset: mark the binding, then yield it when it is idle now
CRMark(d, u) ==
  /\ cpc[d] = "rmark" /\ u \in rset[d]
  /\ rreq' = [rreq EXCEPT ![u] = TRUE]
  /\ ccand' = [ccand EXCEPT ![d] = u] /\ cpc' = [cpc EXCEPT ![d] = "rcas"]
  /\ UNCHANGED <<pc, st, db, tgt, cred, att, cx, yld, clean, wake, reqs, slot, obs, verK, resumed, fail,
                 dirtyStart>>
  /\ UNCHANGED <<q, qn, wreq, rset>>
  /\ UNCHANGED <<svars, xvars, bvars, gvars>>

CRCas(d) ==
  /\ cpc[d] = "rcas"
  /\ LET u == ccand[d] IN
       /\ IF st[u] = "idle" /\ Mutant # "reset_no_cas"
            THEN st' = [st EXCEPT ![u] = "yielded"] /\ wake' = [wake EXCEPT ![u] = TRUE]
            ELSE UNCHANGED <<st, wake>>
       /\ rset' = [rset EXCEPT ![d] = rset[d] \ {u}]
       /\ cpc' = [cpc EXCEPT ![d] = IF rset[d] \ {u} = {} THEN "idle" ELSE "rmark"]
  /\ UNCHANGED <<pc, db, tgt, cred, att, cx, yld, clean, rreq, reqs, slot, obs, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<ccand, q, qn, wreq>>
  /\ UNCHANGED <<svars, xvars, bvars, gvars>>

(* ------------------------------------------------------------------------------------------------------- *)
(* the session thread of one driver connection                                                             *)

\* a new session for this connection: no session presented, or the presented one is gone (expired)
Create(t) ==
  /\ pc[t] = "claim" /\ (IF tgt[t] = 0 THEN TRUE ELSE ~present[tgt[t]])
  /\ IF nextSid <= NS
       THEN /\ present' = [present EXCEPT ![nextSid] = TRUE] /\ ref' = [ref EXCEPT ![nextSid] = 1]
            /\ sdb' = [sdb EXCEPT ![nextSid] = db[t]] /\ holder' = [holder EXCEPT ![nextSid] = t]
            /\ nextSid' = nextSid + 1
            /\ att' = [att EXCEPT ![t] = nextSid] /\ cx' = [cx EXCEPT ![t] = nextSid]
            /\ pc' = [pc EXCEPT ![t] = "top"]
       ELSE /\ pc' = [pc EXCEPT ![t] = "send"]
            /\ UNCHANGED <<present, ref, sdb, holder, nextSid, att, cx>>
  /\ UNCHANGED <<st, db, tgt, cred, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<kept, exp, orphan, tear, ver, slock>>
  /\ UNCHANGED <<xvars, cvars, bvars, gvars>>

\* session_claim_kept_context, under the session's state mutex: the secret, then kept and unreferenced
Claim(t) ==
  /\ pc[t] = "claim" /\ tgt[t] # 0 /\ present[tgt[t]] /\ slock # tgt[t]
  /\ LET s == tgt[t] IN
       IF /\ (cred[t] # "badsecret" \/ Mutant = "no_secret")
          /\ ((kept[s] /\ ref[s] = 0) \/ Mutant = "no_excl")
         THEN /\ ref' = [ref EXCEPT ![s] = ref[s] + 1] /\ kept' = [kept EXCEPT ![s] = FALSE]
              /\ exp' = IF Mutant = "no_renew" THEN exp ELSE [exp EXCEPT ![s] = FALSE]
              /\ att' = [att EXCEPT ![t] = s] /\ resumed' = [resumed EXCEPT ![t] = TRUE]
              /\ verK' = [verK EXCEPT ![t] = ver[s]]
              /\ pc' = [pc EXCEPT ![t] = "swap"]
         ELSE /\ pc' = [pc EXCEPT ![t] = "send"]
              /\ UNCHANGED <<ref, kept, exp, att, resumed, verK>>
  /\ UNCHANGED <<st, db, tgt, cred, cx, yld, clean, wake, rreq, reqs, slot, obs, fail, dirtyStart>>
  /\ UNCHANGED <<present, holder, orphan, tear, ver, sdb, nextSid, slock>>
  /\ UNCHANGED <<xvars, cvars, bvars, gvars>>

\* the thread leaves its own context and enters the kept one once its bracket is free
Swap(t) ==
  /\ pc[t] = "swap" /\ holder[att[t]] = 0
  /\ holder' = [holder EXCEPT ![att[t]] = t] /\ cx' = [cx EXCEPT ![t] = att[t]]
  /\ obs' = [obs EXCEPT ![t] = IF Mutant = "fresh_ctx" THEN 0 ELSE ver[att[t]]]
  /\ pc' = [pc EXCEPT ![t] = "auth"]
  /\ UNCHANGED <<st, db, tgt, cred, att, yld, clean, wake, rreq, reqs, slot, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<present, kept, ref, exp, orphan, tear, ver, sdb, nextSid, slock>>
  /\ UNCHANGED <<xvars, cvars, bvars, gvars>>

\* boot_resume_client: the user must be the session's and the password right
Auth(t) ==
  /\ pc[t] = "auth"
  /\ IF cred[t] = "good" \/ Mutant = "no_auth"
       THEN pc' = [pc EXCEPT ![t] = "top"] /\ UNCHANGED fail
       ELSE pc' = [pc EXCEPT ![t] = "end"] /\ fail' = [fail EXCEPT ![t] = TRUE]
  /\ UNCHANGED <<st, db, tgt, cred, att, cx, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, dirtyStart>>
  /\ UNCHANGED <<svars, xvars, cvars, bvars, gvars>>

\* the top of the request loop: registry_auto_ready publishes idle at a boundary that allows a detach
Top(t, c) ==
  /\ pc[t] = "top"
  /\ clean' = [clean EXCEPT ![t] = c]
  /\ IF c \/ Mutant = "idle_dirty"
       THEN st' = [st EXCEPT ![t] = "idle"]
            /\ pc' = [pc EXCEPT ![t] = IF Mutant = "no_reset_check" THEN "wch" ELSE "rst"]
       ELSE UNCHANGED st /\ pc' = [pc EXCEPT ![t] = "wait"]
  /\ UNCHANGED <<db, tgt, cred, att, cx, yld, wake, rreq, reqs, slot, obs, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<svars, xvars, cvars, bvars, gvars>>

\* a broker reset that found this session busy: yield now
Rst(t) ==
  /\ pc[t] = "rst"
  /\ IF rreq[t]
       THEN /\ st' = [st EXCEPT ![t] = IF st[t] = "idle" THEN "yielded" ELSE st[t]]
            /\ wake' = [wake EXCEPT ![t] = TRUE]
            /\ pc' = [pc EXCEPT ![t] = "wait"]
       ELSE /\ pc' = [pc EXCEPT ![t] = "wch"]
            /\ UNCHANGED <<st, wake>>
  /\ UNCHANGED <<db, tgt, cred, att, cx, yld, clean, rreq, reqs, slot, obs, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<svars, xvars, cvars, bvars, gvars>>

\* a dispatcher watches for an idle session
Wch(t) ==
  /\ pc[t] = "wch"
  /\ pc' = [pc EXCEPT ![t] = IF wreq[db[t]] /\ st[t] = "idle" /\ Mutant # "no_idle_hint" THEN "wx" ELSE "wait"]
  /\ UNCHANGED <<st, db, tgt, cred, att, cx, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail,
                 dirtyStart>>
  /\ UNCHANGED <<svars, xvars, cvars, bvars, gvars>>

Wx(t) ==
  /\ pc[t] = "wx"
  /\ wreq' = [wreq EXCEPT ![db[t]] = FALSE]
  /\ hint' = (hint \/ wreq[db[t]])
  /\ pc' = [pc EXCEPT ![t] = "wait"]
  /\ UNCHANGED <<st, db, tgt, cred, att, cx, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail,
                 dirtyStart>>
  /\ UNCHANGED <<cpc, ccand, q, qn, rset>>
  /\ UNCHANGED <<bpc, job, tryLeft, tryD, tryRep, claimed, watching, wset, slotsUsed, jobYields, resets>>
  /\ UNCHANGED <<svars, xvars, gvars>>

\* poll: the wake descriptor
WakeSeen(t) ==
  /\ pc[t] = "wait" /\ wake[t]
  /\ wake' = [wake EXCEPT ![t] = FALSE]
  /\ pc' = [pc EXCEPT ![t] = IF st[t] = "yielded" THEN "exit" ELSE "wait"]
  /\ UNCHANGED <<st, db, tgt, cred, att, cx, yld, clean, rreq, reqs, slot, obs, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<svars, xvars, cvars, bvars, gvars>>

\* poll: a request header; registry_auto_begin_request takes the binding back from idle, or loses to a yield
Request(t) ==
  /\ pc[t] = "wait" /\ reqs[t] < MaxReq
  /\ IF st[t] = "yielded" /\ Mutant # "no_begin"
       THEN pc' = [pc EXCEPT ![t] = "exit"] /\ UNCHANGED <<st, reqs>>
       ELSE /\ st' = [st EXCEPT ![t] = IF st[t] = "idle" THEN "busy" ELSE st[t]]
            /\ reqs' = [reqs EXCEPT ![t] = reqs[t] + 1]
            /\ pc' = [pc EXCEPT ![t] = "exec"]
  /\ UNCHANGED <<db, tgt, cred, att, cx, yld, clean, wake, rreq, slot, obs, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<svars, xvars, cvars, bvars, gvars>>

Exec(t) ==
  /\ pc[t] = "exec"
  /\ ver' = [ver EXCEPT ![att[t]] = IF ver[att[t]] < NT * MaxReq THEN ver[att[t]] + 1 ELSE ver[att[t]]]
  /\ badExec' = (badExec \/ st[t] # "busy")
  /\ pc' = [pc EXCEPT ![t] = "top"]
  /\ UNCHANGED <<st, db, tgt, cred, att, cx, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail,
                 dirtyStart>>
  /\ UNCHANGED <<present, kept, ref, exp, holder, orphan, tear, sdb, nextSid, slock>>
  /\ UNCHANGED <<expInUse, failDestroyed, tlsDirty, crossYield>>
  /\ UNCHANGED <<xvars, cvars, bvars>>

\* poll: the driver closed the connection, or the socket failed
ClientClose(t) ==
  /\ pc[t] = "wait"
  /\ pc' = [pc EXCEPT ![t] = "exit"]
  /\ UNCHANGED <<st, db, tgt, cred, att, cx, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail,
                 dirtyStart>>
  /\ UNCHANGED <<svars, xvars, cvars, bvars, gvars>>

\* registry_auto_finish: state.exchange (closing) decides whether the connection ended by a yield
Finish(t) ==
  /\ pc[t] = "exit"
  /\ yld' = [yld EXCEPT ![t] = (st[t] = "yielded")]
  /\ st' = [st EXCEPT ![t] = "closing"] /\ rreq' = [rreq EXCEPT ![t] = FALSE]
  /\ pc' = [pc EXCEPT ![t] = "end"]
  /\ UNCHANGED <<db, tgt, cred, att, cx, clean, wake, reqs, slot, obs, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<svars, xvars, cvars, bvars, gvars>>

\* db_end_session under the state mutex: keep the session after a yield or a failed login, end it otherwise
EndSession(t) ==
  /\ pc[t] = "end" /\ slock # att[t]
  /\ LET s == att[t] IN
       IF (yld[t] \/ fail[t]) /\ ~(fail[t] /\ Mutant = "fail_destroys")
         THEN /\ kept' = [kept EXCEPT ![s] = TRUE]
              /\ exp' = IF yld[t] THEN [exp EXCEPT ![s] = FALSE] ELSE exp
              /\ UNCHANGED <<present, ref, orphan, att, failDestroyed>>
         ELSE /\ present' = [present EXCEPT ![s] = FALSE] /\ kept' = [kept EXCEPT ![s] = FALSE]
              /\ ref' = [ref EXCEPT ![s] = ref[s] - 1] /\ orphan' = [orphan EXCEPT ![s] = TRUE]
              /\ att' = [att EXCEPT ![t] = 0]
              /\ failDestroyed' = (failDestroyed \/ fail[t])
              /\ UNCHANGED exp
  /\ pc' = [pc EXCEPT ![t] = "free"]
  /\ UNCHANGED <<st, db, tgt, cred, cx, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<holder, tear, ver, sdb, nextSid, slock>>
  /\ UNCHANGED <<badExec, expInUse, tlsDirty, crossYield>>
  /\ UNCHANGED <<xvars, cvars, bvars>>

\* css_free_conn: the connection's reference to a kept session
FreeConn(t) ==
  /\ pc[t] = "free"
  /\ IF att[t] # 0
       THEN ref' = [ref EXCEPT ![att[t]] = ref[att[t]] - 1] /\ att' = [att EXCEPT ![t] = 0]
       ELSE UNCHANGED <<ref, att>>
  /\ pc' = [pc EXCEPT ![t] = "deact"]
  /\ UNCHANGED <<st, db, tgt, cred, cx, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<present, kept, exp, holder, orphan, tear, ver, sdb, nextSid, slock>>
  /\ UNCHANGED <<xvars, cvars, bvars, gvars>>

\* csc_deactivate: an orphaned context is torn down by the thread that leaves it
Deact(t) ==
  /\ pc[t] = "deact"
  /\ holder' = [holder EXCEPT ![cx[t]] = 0]
  /\ tear' = [tear EXCEPT ![cx[t]] = IF orphan[cx[t]] THEN tear[cx[t]] + 1 ELSE tear[cx[t]]]
  /\ orphan' = [orphan EXCEPT ![cx[t]] = FALSE]
  /\ cx' = [cx EXCEPT ![t] = 0]
  /\ pc' = [pc EXCEPT ![t] = "send"]
  /\ UNCHANGED <<st, db, tgt, cred, att, yld, clean, wake, rreq, reqs, slot, obs, verK, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<present, kept, ref, exp, ver, sdb, nextSid, slock>>
  /\ UNCHANGED <<xvars, cvars, bvars, gvars>>

\* registry_session_finished: SESSION_END gives the slot back (B1a)
Send(t) ==
  /\ pc[t] = "send"
  /\ slot' = [slot EXCEPT ![t] = FALSE]
  /\ slotsUsed' = IF Mutant = "leak_on_yield" /\ yld[t] THEN slotsUsed ELSE slotsUsed - 1
  /\ tlsDirty' = TRUE
  /\ pc' = [pc EXCEPT ![t] = "done"]
  /\ obs' = [obs EXCEPT ![t] = 0] /\ verK' = [verK EXCEPT ![t] = 0] /\ reqs' = [reqs EXCEPT ![t] = 0]
  /\ UNCHANGED <<st, db, tgt, cred, att, cx, yld, clean, wake, rreq, resumed, fail, dirtyStart>>
  /\ UNCHANGED <<bpc, job, tryLeft, tryD, tryRep, claimed, watching, wset, hint, jobYields, resets>>
  /\ UNCHANGED <<badExec, expInUse, failDestroyed, crossYield>>
  /\ UNCHANGED <<svars, xvars, cvars>>

(* ------------------------------------------------------------------------------------------------------- *)
(* the session control daemon and time                                                                     *)

\* a kept session's active_time gets older than session_state_timeout (an attached one is on the active
\* connections' list, which refreshes it); not inside a daemon pass, which is far shorter than the timeout
Timeout(s) ==
  /\ present[s] /\ kept[s] /\ ref[s] = 0 /\ ~exp[s] /\ ~snapTaken /\ xpc = "scan"
  /\ exp' = [exp EXCEPT ![s] = TRUE]
  /\ UNCHANGED <<present, kept, ref, holder, orphan, tear, ver, sdb, nextSid, slock>>
  /\ UNCHANGED <<tvars, xvars, cvars, bvars, gvars>>

\* session_check_timeout in the iteration: the active connections are read once per pass
XScan(s) ==
  /\ xpc = "scan" /\ present[s] /\ exp[s] /\ passes < MaxPass
  /\ LET sn == IF snapTaken THEN snap ELSE {s2 \in S : \E u \in T : att[u] = s2} IN
       /\ snap' = sn /\ snapTaken' = TRUE
       /\ IF s \in sn
            THEN exp' = [exp EXCEPT ![s] = FALSE] /\ UNCHANGED <<xpc, xcand>>
            ELSE xcand' = s /\ xpc' = "recheck" /\ UNCHANGED exp
  /\ UNCHANGED passes
  /\ UNCHANGED <<present, kept, ref, holder, orphan, tear, ver, sdb, nextSid, slock>>
  /\ UNCHANGED <<tvars, cvars, bvars, gvars>>

\* the second check under the state mutex, kept until the session is erased
XRecheck ==
  /\ xpc = "recheck"
  /\ IF present[xcand] /\ ((exp[xcand] /\ xcand \notin snap) \/ Mutant = "no_recheck")
       THEN /\ slock' = xcand /\ xpc' = "tear"
            /\ expInUse' = (expInUse \/ ref[xcand] > 0)
       ELSE /\ xpc' = "scan" /\ UNCHANGED <<slock, expInUse>>
  /\ UNCHANGED <<xcand, snapTaken, snap, passes>>
  /\ UNCHANGED <<present, kept, ref, exp, holder, orphan, tear, ver, sdb, nextSid>>
  /\ UNCHANGED <<badExec, failDestroyed, tlsDirty, crossYield>>
  /\ UNCHANGED <<tvars, cvars, bvars>>

\* session_state_uninit -> csc_retire_and_delete: the daemon enters the bracket, tears the context down and
\* erases the session
XTear ==
  /\ xpc = "tear" /\ holder[xcand] = 0
  /\ tear' = [tear EXCEPT ![xcand] = tear[xcand] + 1]
  /\ present' = [present EXCEPT ![xcand] = FALSE] /\ kept' = [kept EXCEPT ![xcand] = FALSE]
  /\ slock' = 0 /\ xpc' = "scan"
  /\ UNCHANGED <<ref, exp, holder, orphan, ver, sdb, nextSid>>
  /\ UNCHANGED <<xcand, snapTaken, snap, passes>>
  /\ UNCHANGED <<tvars, cvars, bvars, gvars>>

XEndPass ==
  /\ xpc = "scan" /\ snapTaken /\ passes < MaxPass
  /\ snapTaken' = FALSE /\ snap' = {} /\ passes' = passes + 1
  /\ UNCHANGED <<xpc, xcand>>
  /\ UNCHANGED <<tvars, svars, cvars, bvars, gvars>>

(* ------------------------------------------------------------------------------------------------------- *)

\* every connection is over: the run ends here
Finished == (\A t \in T : pc[t] = "done") /\ UNCHANGED vars

TStep(t) ==
  \/ Create(t) \/ Claim(t) \/ Swap(t) \/ Auth(t) \/ Rst(t) \/ Wch(t) \/ Wx(t) \/ WakeSeen(t) \/ Exec(t)
  \/ Finish(t) \/ EndSession(t) \/ FreeConn(t) \/ Deact(t) \/ Send(t) \/ \E c \in BOOLEAN : Top(t, c)
CStep(d) ==
  \/ CStart(d) \/ CTWake(d) \/ CW1(d) \/ CWScan(d) \/ CWX(d) \/ CRCas(d)
  \/ \E u \in T : CTCas(d, u) \/ CRMark(d, u)
BStep == BTop \/ BTryRep \/ BWatch \/ BSlot \/ BHint \/ \E d \in D : BTry(d)
Env ==
  \/ \E t \in T, d \in D, s \in 0..NS, c \in Creds : BStart(t, d, s, c)
  \/ \E t \in T : Request(t) \/ ClientClose(t)
  \/ \E d \in D : EReset(d)
  \/ \E s \in S : Timeout(s) \/ XScan(s)
  \/ XRecheck \/ XTear \/ XEndPass \/ BTimeout

Next == (\E t \in T : TStep(t)) \/ (\E d \in D : CStep(d)) \/ BStep \/ Env \/ Finished

Spec == Init /\ [][Next]_vars

\* the session threads, the controllers and the dispatcher keep running; drivers, resets, the daemon and the
\* admission deadline are the environment and get no fairness
FairSpec ==
  /\ Spec
  /\ \A t \in T : WF_vars(TStep(t))
  /\ \A d \in D : WF_vars(CStep(d))
  /\ WF_vars(BStep)

(* ---- properties ---- *)

Attached(s) == {t \in T : att[t] = s}

\* C1: a kept session is taken by one connection, with the secret and the login
OneAttachment == \A s \in S : Cardinality(Attached(s)) <= 1 /\ ref[s] = Cardinality(Attached(s))
NoIntruder ==
  \A t \in T : /\ att[t] # 0 /\ resumed[t] => cred[t] # "badsecret"
               /\ pc[t] \in RunPcs /\ resumed[t] => cred[t] = "good"
FailedLoginKeeps == ~failDestroyed

\* C2: one teardown per session, never under a connection
OneTeardown == \A s \in S : tear[s] <= 1
NoExpiryInUse == ~expInUse
AttachedIsPresent == \A t \in T : att[t] # 0 => present[att[t]]
ContextAlive == \A t \in T : cx[t] # 0 => (tear[cx[t]] = 0 /\ holder[cx[t]] = t)

\* C3: one demand yields one session at most
OneYieldPerDemand == jobYields <= 1

\* C4: a session thread starts with no state of another session
StartClean == \A t \in T : ~dirtyStart[t]

\* C5: the broker's slots are the connections it handed over
SlotExact == slotsUsed = Cardinality({t \in T : slot[t]}) /\ slotsUsed <= MaxSlots

\* C6: a session is kept only from a boundary that allows it, and no request runs on a yielded binding
CleanDetach == \A t \in T : (yld[t] \/ st[t] = "yielded") => clean[t]
NoExecAfterYield == ~badExec

\* C7: the resumed connection finds the session as it was left; a kept session holds no connection
Retained == \A t \in T : (resumed[t] /\ pc[t] \in RunPcs \cup {"auth"}) => obs[t] = verK[t]
KeptHoldsNothing == \A s \in S : (kept[s] /\ ref[s] = 0) => Attached(s) = {}

\* C8: a session marked by a reset is not left waiting idle
NoParkedReset ==
  \A t \in T : ~(/\ rreq[t] /\ pc[t] = "wait" /\ st[t] = "idle"
                 /\ ~(cpc[db[t]] = "rcas" /\ ccand[db[t]] = t))

\* the wake descriptor is written only for a yielded binding (cas_network.c ends the wait on it)
WakeMeansYielded == \A t \in T : wake[t] => st[t] \in {"yielded", "closing"} \/ pc[t] = "done"

\* C3 (liveness): a waiting dispatcher does not stay behind a session that waits idle
Stuck == job # 0 /\ bpc # "free" /\ slotsUsed >= MaxSlots /\ \E u \in T : pc[u] = "wait" /\ st[u] = "idle"
NoStuck == Stuck ~> ~Stuck

(* ---- the inductive invariant ---- *)
TailPcs == {"end", "free", "deact", "send", "done"}

\* where a thread is fixes what it holds
WfThread ==
  \A t \in T :
    /\ slot[t] <=> pc[t] \notin {"new", "done"}
    /\ pc[t] \in {"new", "claim", "send", "done"} => att[t] = 0 /\ cx[t] = 0
    /\ pc[t] = "swap" => att[t] # 0 /\ cx[t] = 0 /\ verK[t] = ver[att[t]]
    /\ pc[t] \in RunPcs \cup {"auth", "end"} => att[t] # 0 /\ cx[t] = att[t]
    /\ pc[t] = "free" => cx[t] # 0 /\ (att[t] = 0 \/ att[t] = cx[t])
    /\ pc[t] = "deact" => att[t] = 0 /\ cx[t] # 0
    /\ pc[t] \in {"swap", "auth"} => resumed[t]
    /\ pc[t] \in {"new", "claim"} => ~resumed[t] /\ ~fail[t] /\ ~yld[t]
    /\ att[t] < nextSid /\ cx[t] < nextSid /\ tgt[t] < nextSid
\* the binding's state against the thread's step
WfState ==
  \A t \in T :
    /\ pc[t] \in {"new", "claim", "swap", "auth", "top", "exec"} => st[t] = "busy"
    /\ st[t] \in {"idle", "yielded"} => pc[t] \in {"rst", "wch", "wx", "wait", "exit"} /\ clean[t]
    /\ st[t] = "closing" => pc[t] \in TailPcs
    /\ pc[t] = "rst" => st[t] \in {"idle", "yielded"}
    /\ yld[t] => st[t] = "closing" /\ clean[t]
    /\ fail[t] => pc[t] \in TailPcs /\ resumed[t] /\ ~yld[t] /\ st[t] = "busy"
\* a session's fields against its life: unused, present (attached or kept), destroyed, torn down
WfSession ==
  \A s \in S :
    /\ s >= nextSid => ~present[s] /\ ~kept[s] /\ ref[s] = 0 /\ holder[s] = 0 /\ ~orphan[s] /\ tear[s] = 0 /\ ~exp[s]
    /\ kept[s] => present[s]
    /\ present[s] => tear[s] = 0 /\ ~orphan[s]
    /\ ~present[s] => ref[s] = 0
    /\ orphan[s] => tear[s] = 0 /\ holder[s] # 0
    /\ tear[s] = 1 => holder[s] = 0
    /\ exp[s] => ref[s] = 0 /\ (present[s] => kept[s])
\* the bracket's holder and the thread's active context name each other
HolderCx ==
  /\ \A t \in T : cx[t] # 0 => holder[cx[t]] = t /\ (present[cx[t]] \/ orphan[cx[t]])
  /\ \A s \in S : holder[s] # 0 => cx[holder[s]] = s
\* an attached connection's session: kept only between the end of the session and the conn entry's release
AttachState ==
  \A t \in T :
    /\ (att[t] # 0 /\ kept[att[t]]) => pc[t] = "free"
    /\ (pc[t] = "free" /\ att[t] # 0) => kept[att[t]]
DaemonWf ==
  /\ (slock # 0) <=> (xpc = "tear")
  /\ slock # 0 => slock = xcand
  /\ xpc \in {"recheck", "tear"} => xcand # 0 /\ xcand < nextSid /\ snapTaken
  /\ xpc = "tear" => present[xcand] /\ ref[xcand] = 0
ControlWf ==
  \A d \in D :
    /\ cpc[d] \in {"twake", "rcas"} => ccand[d] # 0 /\ db[ccand[d]] = d /\ pc[ccand[d]] # "new"
    /\ cpc[d] = "twake" => st[ccand[d]] \in {"yielded", "closing"}
    /\ \A u \in rset[d] : db[u] = d /\ pc[u] # "new"
\* a marked session that waits idle has the reset's compare-and-swap still to come
ResetPending ==
  \A t \in T : (rreq[t] /\ st[t] = "idle" /\ pc[t] \in {"wch", "wx", "wait"})
                   => (cpc[db[t]] = "rcas" /\ ccand[db[t]] = t)
BrokerWf ==
  /\ (bpc = "free") <=> (job = 0)
  /\ job # 0 => pc[job] = "new"
  /\ claimed => bpc = "wait"
  /\ watching => bpc = "wait" /\ ~claimed
  /\ jobYields = (IF claimed THEN 1 ELSE 0)

IndInv ==
  /\ TypeOK
  /\ WfThread
  /\ WfState
  /\ WfSession
  /\ HolderCx
  /\ AttachState
  /\ DaemonWf
  /\ ControlWf
  /\ ResetPending
  /\ BrokerWf
  /\ OneAttachment
  /\ NoIntruder
  /\ FailedLoginKeeps
  /\ OneTeardown
  /\ NoExpiryInUse
  /\ AttachedIsPresent
  /\ ContextAlive
  /\ OneYieldPerDemand
  /\ StartClean
  /\ SlotExact
  /\ CleanDetach
  /\ NoExecAfterYield
  /\ Retained
  /\ KeptHoldsNothing
  /\ NoParkedReset
  /\ WakeMeansYielded

\* Apalache's inductive check: MaxPass and MaxResets range over Nat; the role set sizes and the bounds that are
\* codomains or domains of functions (Apalache needs constant ranges there) are the main cfg's
CInit ==
  /\ NT = 2 /\ NS = 2 /\ ND = 1 /\ MaxSlots = 1 /\ MaxReq = 1 /\ QMax = 3
  /\ MaxPass \in Nat /\ MaxResets \in Nat
  /\ Mutant = "none"

\* the same check one size up in every role set
CInit3 ==
  /\ NT = 3 /\ NS = 3 /\ ND = 2 /\ MaxSlots = 2 /\ MaxReq = 2 /\ QMax = 3
  /\ MaxPass \in Nat /\ MaxResets \in Nat
  /\ Mutant = "none"

(* ---- witnesses: outcomes that must be reachable ---- *)
NotResumed == ~\E t \in T : resumed[t] /\ pc[t] = "exec" /\ verK[t] > 0
NotExpiredFresh == ~\E t \in T : tgt[t] # 0 /\ att[t] # 0 /\ att[t] # tgt[t]
NotRejected == ~\E t \in T : tgt[t] # 0 /\ present[tgt[t]] /\ cred[t] = "good" /\ pc[t] = "send" /\ ~resumed[t]
NotLoginFailed == ~\E t \in T : fail[t] /\ pc[t] = "done" /\ kept[tgt[t]]
NotCrossYield == ~crossYield
NotHinted == ~(hint /\ bpc = "wait" /\ watching)
\* with MaxSlots = NT no dispatcher ever waits, so a yield there is a reset's
NotResetYield == ~\E t \in T : yld[t]
NotLostRequest == ~\E t \in T : pc[t] = "exit" /\ st[t] = "yielded" /\ ~wake[t] /\ reqs[t] > 0
NotExpired == ~\E s \in S : tear[s] = 1 /\ ~present[s] /\ passes > 0
=============================================================================
