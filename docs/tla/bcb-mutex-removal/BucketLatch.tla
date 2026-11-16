---------------------------- MODULE BucketLatch ----------------------------
(***************************************************************************)
(* Page buffer without the per-BCB mutex (design, docs/tla/bcb-mutex-removal). *)
(*                                                                         *)
(* Every BCB's state -- fix count, latch mode, waiter list, page identity, *)
(* dirty and write-in-progress flags -- changes only under the latch of    *)
(* the hash bucket of the page the BCB holds.  The bucket latch is a       *)
(* read-write latch: a READ fix holds it shared and raises the fix count   *)
(* atomically; WRITE fixes, waiter-list changes, victim claims, flush      *)
(* start and end hold it exclusive.  One step = one bucket-latch critical  *)
(* section (shared sections touch only the latch word by CAS and read      *)
(* fields that need the exclusive latch to change).  Only a fixer that     *)
(* missed holds its bucket latch across steps, while it looks for a victim *)
(* (exh).                                                                  *)
(*                                                                         *)
(* Waiters are woken, never granted: a releaser posts the compatible       *)
(* waiters at the head of the list, stopping at the first WRITE waiter; a  *)
(* woken, timed-out or spuriously woken waiter takes the bucket latch,     *)
(* removes its own entry and retries the fix from the hash chain.  A new   *)
(* request does not look at the waiter list (barging).                     *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

\* PromoteWait TRUE (comparison only) releases the READ and waits for WRITE as an ordinary writer.
\* FALSE (D13): a promotion that is not alone keeps its READ, marks the BCB promotion-pending (new
\* READ requests then wait) and waits until it is the only holder and no write is in progress; a
\* second promotion on a pending BCB fails (ER_PAGE_LATCH_PROMOTE_FAIL) and its caller re-fixes WRITE.
\* WakeAtEnd tells how a waiter blocked only by a write in progress is woken: "flag" = the releaser
\* that leaves it blocked sets the write-waiter flag, "always" = the end of a write posts whenever
\* the list is not empty, "none" = only waiters that saw the write set the flag.
CONSTANTS NT,          \* worker threads 1..NT
          NB,          \* BCBs 1..NB
          NP,          \* pages 1..NP
          NK,          \* hash buckets 1..NK
          MaxOps,      \* operations per worker
          Ops,         \* operations a worker may pick
          MaxTimeouts, \* latch timeouts / interrupts (faults)
          MaxSpur,     \* spurious wakeups (faults)
          MaxErr,      \* I/O errors: a claim's page read, a flush's page copy (faults)
          MaxEnv,      \* invalidations (environment)
          Daemon,      \* a page flush daemon exists
          PromoteWait, \* comparison only (D13): TRUE = a promotion that is not alone waits for WRITE
          WakeAtEnd,   \* D14: "flag" (chosen), "always" or "none" (comparison cfgs)
          Mutant       \* "none" or one known-wrong variant

\* apalache-type: NT Int
\* apalache-type: NB Int
\* apalache-type: NP Int
\* apalache-type: NK Int
\* apalache-type: MaxOps Int
\* apalache-type: Ops Set(Str)
\* apalache-type: MaxTimeouts Int
\* apalache-type: MaxSpur Int
\* apalache-type: MaxErr Int
\* apalache-type: MaxEnv Int
\* apalache-type: Daemon Bool
\* apalache-type: PromoteWait Bool
\* apalache-type: WakeAtEnd Str
\* apalache-type: Mutant Str
\* apalache-type: pc Int -> Str
\* apalache-type: rp Int -> Int
\* apalache-type: rm Int -> Str
\* apalache-type: hb Int -> Int
\* apalache-type: hm Int -> Str
\* apalache-type: ops Int -> Int
\* apalache-type: inq Int -> Bool
\* apalache-type: wm Int -> Str
\* apalache-type: tk Int -> Int
\* apalache-type: posted Int -> Bool
\* apalache-type: pv Int -> Int
\* apalache-type: cver Int -> Int
\* apalache-type: cpg Int -> Int
\* apalache-type: cerr Int -> Bool
\* apalache-type: tick Int
\* apalache-type: vpid Int -> Int
\* apalache-type: mode Int -> Str
\* apalache-type: fcnt Int -> Int
\* apalache-type: dirty Int -> Bool
\* apalache-type: writing Int -> Bool
\* apalache-type: wwait Int -> Bool
\* apalache-type: touched Int -> Bool
\* apalache-type: bver Int -> Int
\* apalache-type: diskVer Int -> Int
\* apalache-type: latest Int -> Int
\* apalache-type: exh Int -> Int
\* apalache-type: tmo Int
\* apalache-type: spur Int
\* apalache-type: errs Int
\* apalache-type: envs Int
\* apalache-type: barge Bool
\* apalache-type: prom Int -> Int
\* apalache-type: avd Int -> Int
\* apalache-type: reg Int -> Int
\* apalache-type: areq Int -> Bool
\* apalache-type: dealloc Int -> Bool
\* apalache-type: shk Int -> Int
\* apalache-type: unf Int -> Int

\* Ops: "R" read fix, "Rc" conditional read fix, "W" write fix, "Wc" conditional write fix,
\*      "P" read fix then promote to write, "C" synchronous flush of a page (checkpoint, backup),
\*      "D" read fix that prevents the page's deallocation while it waits (OLD_PAGE_PREVENT_DEALLOC),
\*      "V" vacuum: WRITE fix of an emptied heap page, deallocated at the unfix unless prevented

Workers == 1..NT
D == NT + 1
Procs == IF Daemon THEN 1..(NT + 1) ELSE 1..NT
Bcbs == 1..NB
Pages == 1..NP
Bkts == 1..NK
Bkt(p) == ((p - 1) % NK) + 1

VARIABLES pc,      \* Procs -> program counter
          rp,      \* Procs -> requested page (0: none)
          rm,      \* Procs -> requested op
          hb,      \* Procs -> BCB held, loaded, copied or waited on (0: none)
          hm,      \* Procs -> latch mode held ("": none)
          ops,     \* Procs -> operations left
          inq,     \* Procs -> has an entry in hb's waiter list
          wm,      \* Procs -> mode waited for ("R", "W", "F")
          tk,      \* Procs -> ticket of the waiter entry (list order)
          posted,  \* Procs -> a wakeup is pending on its semaphore
          pv,      \* Procs -> page version seen when a promotion started (-1: none)
          cver,    \* Procs -> version of the page copy in flight
          cpg,     \* Procs -> page of the copy in flight
          cerr,    \* Procs -> the copy failed
          tick,    \* next waiter ticket
          vpid,    \* Bcbs -> page held (0: none)
          mode,    \* Bcbs -> "N", "R", "W"
          fcnt,    \* Bcbs -> fix count
          dirty,   \* Bcbs -> dirty flag
          writing, \* Bcbs -> a flush copies the page (write in progress)
          wwait,   \* Bcbs -> a waiter waits for the write to complete
          touched, \* Bcbs -> use mark left by the last unfix (second chance)
          bver,    \* Bcbs -> version of the page image in the BCB
          diskVer, \* Pages -> version durable on disk
          latest,  \* Pages -> latest version written by any WRITE holder
          exh,     \* Bkts -> thread holding the bucket latch exclusive across steps (0: none)
          tmo, spur, errs, envs,  \* fault budgets used
          barge,   \* ghost: a READ was granted while a WRITE waiter was queued
          prom,    \* Bcbs -> the promoter waiting on it with its READ kept (0: none)
          avd,     \* Bcbs -> deallocation-prevention registrations (count_fix_and_avoid_dealloc low bits)
          reg,     \* Procs -> BCB registered against deallocation (0 none, -1 caller's neighbor latch)
          areq,    \* Bcbs -> a flush asked the WRITE holder to flush at its unfix (ASYNC_FLUSH_REQ)
          dealloc, \* Pages -> the page was deallocated
          shk,     \* Bkts -> threads inside a shared section that spans steps (a READ unfix)
          unf      \* Procs -> fix count a READ unfix left (-1: none)

vars == <<pc, rp, rm, hb, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick,
          vpid, mode, fcnt, dirty, writing, wwait, touched, bver, diskVer, latest, exh,
          tmo, spur, errs, envs, barge, prom, avd, reg, areq, dealloc, shk, unf>>

Resident(p) == {b \in Bcbs : vpid[b] = p}
Waiters(b) == {w \in Procs : inq[w] /\ hb[w] = b}
NoX(k) == exh[k] = 0
FreeK(k) == exh[k] = 0 /\ shk[k] = 0
Holding == {"hold", "load", "pwait"}

\* can a reader or writer waiter proceed on a BCB in state (md, wr, promotion pending pr)? a pending
\* promotion keeps new readers out
CompatM(m, md, wr, pr) ==
  IF m = "R" THEN md \in {"N", "R"} /\ ~pr
  ELSE IF m = "W" THEN md = "N" /\ ~wr
  ELSE FALSE

\* reader and writer waiters a releaser posts when it leaves b in state (md, wr, promotion pending pr):
\* from the head, every compatible waiter before the first WRITE waiter; a WRITE waiter at the head
\* alone. Flush waiters are posted by the end of the flush only (pgbuf_wake_flush_waiters).
PostFrom(ws0, md, wr, pr) ==
  LET ws == {w \in ws0 : wm[w] # "F"}
      heads == {h \in ws : \A v \in ws : tk[h] <= tk[v]}
      wsW == {w \in ws : wm[w] = "W"}
  IN IF \E h \in heads : wm[h] = "W"
     THEN IF CompatM("W", md, wr, pr) THEN heads ELSE {}
     ELSE {w \in ws : CompatM(wm[w], md, wr, pr) /\ \A v \in wsW : tk[w] < tk[v]}

PostSet(b, md, wr) == PostFrom(Waiters(b), md, wr, prom[b] # 0)
PostSetP(b, md, wr, pr) == PostFrom(Waiters(b), md, wr, pr)
FWaiters(b) == {w \in Waiters(b) : wm[w] = "F"}

\* the same rule over the waiters other than ex (a waiter that is removing its own entry)
PostSetEx(b, md, wr, ex) == PostFrom(Waiters(b) \ {ex}, md, wr, prom[b] # 0)

Post(S) == posted' = [w \in Procs |-> posted[w] \/ w \in S]

\* a waiter leaving the list clears its own wakeup and passes the wakeup on to the waiters left
\* (mutant leave_no_pass: it does not)
Leave(t) ==
  LET b == hb[t]
      S == IF Mutant = "leave_no_pass" THEN {} ELSE PostSetEx(b, mode[b], writing[b], t)
  IN /\ posted' = [w \in Procs |-> IF w = t THEN FALSE ELSE posted[w] \/ w \in S]
     /\ wwait' = [wwait EXCEPT ![b] =
                    @ \/ (WakeAtEnd = "flag" /\ writing[b] /\ Waiters(b) \ {t} # {})]

------------------------------------------------------------------------------
Init ==
  /\ pc = [t \in Procs |-> IF t = D THEN "scan" ELSE "idle"]
  /\ rp = [t \in Procs |-> 0]
  /\ rm = [t \in Procs |-> ""]
  /\ hb = [t \in Procs |-> 0]
  /\ hm = [t \in Procs |-> ""]
  /\ ops = [t \in Procs |-> IF t = D THEN 0 ELSE MaxOps]
  /\ inq = [t \in Procs |-> FALSE]
  /\ wm = [t \in Procs |-> ""]
  /\ tk = [t \in Procs |-> 0]
  /\ posted = [t \in Procs |-> FALSE]
  /\ pv = [t \in Procs |-> -1]
  /\ cver = [t \in Procs |-> 0]
  /\ cpg = [t \in Procs |-> 0]
  /\ cerr = [t \in Procs |-> FALSE]
  /\ tick = 1
  /\ vpid = [b \in Bcbs |-> IF b <= NP THEN b ELSE 0]
  /\ mode = [b \in Bcbs |-> "N"]
  /\ fcnt = [b \in Bcbs |-> 0]
  /\ dirty = [b \in Bcbs |-> FALSE]
  /\ writing = [b \in Bcbs |-> FALSE]
  /\ wwait = [b \in Bcbs |-> FALSE]
  /\ touched = [b \in Bcbs |-> FALSE]
  /\ bver = [b \in Bcbs |-> 0]
  /\ diskVer = [p \in Pages |-> 0]
  /\ latest = [p \in Pages |-> 0]
  /\ exh = [k \in Bkts |-> 0]
  /\ tmo = 0 /\ spur = 0 /\ errs = 0 /\ envs = 0
  /\ barge = FALSE
  /\ prom = [b \in Bcbs |-> 0]
  /\ avd = [b \in Bcbs |-> 0]
  /\ reg = [t \in Procs |-> 0]
  /\ areq = [b \in Bcbs |-> FALSE]
  /\ dealloc = [p \in Pages |-> FALSE]
  /\ shk = [k \in Bkts |-> 0]
  /\ unf = [t \in Procs |-> -1]

------------------------------------------------------------------------------
IsRead(o) == o \in {"R", "Rc", "P", "D"}
IsWrite(o) == o \in {"W", "Wc", "V"}

\* drop t's deallocation-prevention registration (the code's unregister is a no-op on a count already
\* reset, pgbuf_bcb_unregister_avoid_deallocation)
Unreg(t) ==
  /\ avd' = IF reg[t] > 0 THEN [avd EXCEPT ![reg[t]] = IF @ > 0 THEN @ - 1 ELSE 0] ELSE avd
  /\ reg' = [reg EXCEPT ![t] = 0]

\* register t against the deallocation of b's page, moving a registration left on another BCB
RegAt(t, b) ==
  IF reg[t] = b
  THEN UNCHANGED <<avd, reg>>
  ELSE /\ avd' = [c \in Bcbs |-> avd[c] + (IF c = b THEN 1 ELSE 0)
                                       - (IF c = reg[t] /\ avd[c] > 0 THEN 1 ELSE 0)]
       /\ reg' = [reg EXCEPT ![t] = b]

\* t's registration sits on a BCB whose page read failed after t left its waiter list
RegLost(t) == rm[t] = "D" /\ reg[t] > 0 /\ vpid[reg[t]] # rp[t]

\* the promoter to wake when a release leaves it the only holder with no write in progress
PromPost(b, nf, wr) == IF prom[b] # 0 /\ nf = 1 /\ ~wr THEN {prom[b]} ELSE {}

\* a worker picks its next operation; a deallocation-preventing fix starts on a page its caller still
\* sees linked (the caller holds the neighbor page that links it)
Begin(t) ==
  /\ pc[t] = "idle" /\ ops[t] > 0
  /\ \E p \in Pages, o \in Ops :
       /\ o = "D" => ~dealloc[p]
       /\ rp' = [rp EXCEPT ![t] = p]
       /\ rm' = [rm EXCEPT ![t] = o]
       /\ reg' = [reg EXCEPT ![t] = IF o = "D" THEN -1 ELSE 0]
  /\ ops' = [ops EXCEPT ![t] = @ - 1]
  /\ pc' = [pc EXCEPT ![t] = "fix"]
  /\ UNCHANGED <<hb, hm, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, mode, fcnt, dirty,
                 writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, errs, envs, barge,
                 prom, avd, areq, dealloc, shk, unf>>

Finish(t) ==
  /\ t \in Workers /\ pc[t] = "idle" /\ ops[t] = 0
  /\ pc' = [pc EXCEPT ![t] = "done"]
  /\ UNCHANGED <<rp, rm, hb, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, mode,
                 fcnt, dirty, writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur,
                 errs, envs, barge, prom, avd, reg, areq, dealloc, shk, unf>>

\* READ fix under the shared bucket latch: walk the chain, raise the count by CAS; a pending promotion
\* keeps new readers out; the fix drops its deallocation-prevention registration
FixShared(t) ==
  /\ pc[t] = "fix" /\ IsRead(rm[t]) /\ ~RegLost(t)
  /\ NoX(Bkt(rp[t]))
  /\ \E b \in Resident(rp[t]) :
       /\ mode[b] \in {"N", "R"} /\ prom[b] = 0
       /\ IF Mutant = "pin_after_latch"
          THEN \* the lookup under the latch, the pin after releasing it
               /\ hb' = [hb EXCEPT ![t] = b]
               /\ pc' = [pc EXCEPT ![t] = "pin"]
               /\ UNCHANGED <<mode, fcnt, hm, barge, avd, reg>>
          ELSE /\ mode' = [mode EXCEPT ![b] = "R"]
               /\ fcnt' = [fcnt EXCEPT ![b] = @ + 1]
               /\ hb' = [hb EXCEPT ![t] = b]
               /\ hm' = [hm EXCEPT ![t] = "R"]
               /\ pc' = [pc EXCEPT ![t] = "hold"]
               /\ barge' = (barge \/ \E w \in Waiters(b) : wm[w] = "W")
               /\ Unreg(t)
  /\ UNCHANGED <<rp, rm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, dirty,
                 writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, errs, envs,
                 prom, areq, dealloc, shk, unf>>

\* mutant pin_after_latch: the CAS on the word alone, after the latch was released
Pin(t) ==
  /\ pc[t] = "pin"
  /\ LET b == hb[t] IN
       /\ mode[b] \in {"N", "R"}
       /\ mode' = [mode EXCEPT ![b] = "R"]
       /\ fcnt' = [fcnt EXCEPT ![b] = @ + 1]
  /\ hm' = [hm EXCEPT ![t] = "R"]
  /\ pc' = [pc EXCEPT ![t] = "hold"]
  /\ Unreg(t)
  /\ UNCHANGED <<rp, rm, hb, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, dirty,
                 writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, errs, envs, barge,
                 prom, areq, dealloc, shk, unf>>

\* enqueue t on b waiting for mode m (under the exclusive bucket latch)
Enqueue(t, b, m, setW) ==
  /\ inq' = [inq EXCEPT ![t] = TRUE]
  /\ hb' = [hb EXCEPT ![t] = b]
  /\ wm' = [wm EXCEPT ![t] = m]
  /\ tk' = [tk EXCEPT ![t] = tick]
  /\ tick' = tick + 1
  /\ posted' = [posted EXCEPT ![t] = FALSE]
  /\ wwait' = [wwait EXCEPT ![b] = @ \/ setW]
  /\ pc' = [pc EXCEPT ![t] = "sleep"]

\* the exclusive-latch path of a fix: a READ that cannot go shared, WRITE, a synchronous flush,
\* or a miss (then the latch stays held while a victim is looked for)
FixExcl(t) ==
  /\ pc[t] = "fix" /\ ~RegLost(t)
  /\ LET p == rp[t]
         k == Bkt(p)
     IN /\ FreeK(k)
        /\ IsRead(rm[t]) => ~(\E b \in Resident(p) : mode[b] \in {"N", "R"} /\ prom[b] = 0)
        /\ IF Resident(p) # {}
           THEN \E b \in Resident(p) :
             IF IsRead(rm[t])
             THEN \* WRITE-latched, or a promotion is pending
                  IF rm[t] = "Rc"
                  THEN /\ pc' = [pc EXCEPT ![t] = "idle"]
                       /\ UNCHANGED <<hb, inq, wm, tk, tick, posted, wwait, writing, dirty, cver, cpg,
                                      mode, fcnt, hm, exh, pv, avd, reg, areq>>
                  ELSE /\ Enqueue(t, b, "R", FALSE)
                       \* a deallocation-preventing fix registers before it waits and keeps the
                       \* registration across its retries (mutant reg_at_grant: only at the grant)
                       /\ IF rm[t] # "D" THEN UNCHANGED <<avd, reg>>
                          ELSE IF Mutant = "reg_at_grant"
                          THEN /\ reg' = [reg EXCEPT ![t] = 0]
                               /\ UNCHANGED avd
                          ELSE RegAt(t, b)
                       /\ UNCHANGED <<writing, dirty, cver, cpg, mode, fcnt, hm, exh, pv, areq>>
             ELSE IF IsWrite(rm[t])
             THEN IF (mode[b] = "N" \/ (Mutant = "write_ignores_readers" /\ mode[b] = "R"))
                     /\ (~writing[b] \/ Mutant = "write_ignores_writing")
                  THEN /\ mode' = [mode EXCEPT ![b] = "W"]
                       /\ fcnt' = [fcnt EXCEPT ![b] = @ + 1]
                       /\ hb' = [hb EXCEPT ![t] = b]
                       /\ hm' = [hm EXCEPT ![t] = "W"]
                       /\ pc' = [pc EXCEPT ![t] = "hold"]
                       /\ UNCHANGED <<inq, wm, tk, tick, posted, wwait, writing, dirty, cver, cpg, exh,
                                      pv, avd, reg, areq>>
                  ELSE IF rm[t] = "Wc"
                  THEN /\ pc' = [pc EXCEPT ![t] = "idle"]
                       /\ UNCHANGED <<mode, fcnt, hb, hm, inq, wm, tk, tick, posted, wwait, writing,
                                      dirty, cver, cpg, exh, pv, avd, reg, areq>>
                  ELSE /\ Enqueue(t, b, "W", writing[b])
                       /\ UNCHANGED <<mode, fcnt, hm, writing, dirty, cver, cpg, exh, pv, avd, reg, areq>>
             ELSE \* "C": synchronous flush of p (pgbuf_bcb_safe_flush_internal)
                  IF ~dirty[b] /\ ~writing[b]
                  THEN /\ pc' = [pc EXCEPT ![t] = "idle"]
                       /\ UNCHANGED <<mode, fcnt, hb, hm, inq, wm, tk, tick, posted, wwait, writing,
                                      dirty, cver, cpg, exh, pv, avd, reg, areq>>
                  ELSE IF writing[b]
                  THEN \* wait for the flush in progress; its end wakes every flush waiter
                       /\ Enqueue(t, b, "F", FALSE)
                       /\ UNCHANGED <<mode, fcnt, hm, writing, dirty, cver, cpg, exh, pv, avd, reg, areq>>
                  ELSE IF mode[b] = "W"
                  THEN \* ask the WRITE holder to flush at its unfix, and wait for that flush
                       /\ areq' = [areq EXCEPT ![b] = TRUE]
                       /\ Enqueue(t, b, "F", FALSE)
                       /\ UNCHANGED <<mode, fcnt, hm, writing, dirty, cver, cpg, exh, pv, avd, reg>>
                  ELSE /\ writing' = [writing EXCEPT ![b] = TRUE]
                       /\ dirty' = [dirty EXCEPT ![b] = FALSE]
                       /\ cver' = [cver EXCEPT ![t] = bver[b]]
                       /\ cpg' = [cpg EXCEPT ![t] = p]
                       /\ hb' = [hb EXCEPT ![t] = b]
                       /\ pc' = [pc EXCEPT ![t] = "copy"]
                       /\ UNCHANGED <<mode, fcnt, hm, inq, wm, tk, tick, posted, wwait, exh, pv, avd,
                                      reg, areq>>
           ELSE IF rm[t] = "C"
           THEN /\ pc' = [pc EXCEPT ![t] = "idle"]
                /\ UNCHANGED <<mode, fcnt, hb, hm, inq, wm, tk, tick, posted, wwait, writing, dirty,
                               cver, cpg, exh, pv, avd, reg, areq>>
           ELSE /\ exh' = [exh EXCEPT ![k] = IF Mutant = "miss_no_latch" THEN 0 ELSE t]
                /\ pc' = [pc EXCEPT ![t] = "miss"]
                /\ UNCHANGED <<mode, fcnt, hb, hm, inq, wm, tk, tick, posted, wwait, writing, dirty,
                               cver, cpg, pv, avd, reg, areq>>
  /\ UNCHANGED <<rp, rm, ops, cerr, vpid, touched, bver, diskVer, latest, tmo, spur, errs, envs,
                 barge, prom, dealloc, shk, unf>>

\* a deallocation-preventing fix back from its wait finds the BCB it registered on emptied by a failed
\* read: it drops the registration and fails (D18); mutant regloss_retry: it searches again unprotected
FixRegLost(t) ==
  /\ pc[t] = "fix" /\ RegLost(t)
  /\ Unreg(t)
  /\ pc' = [pc EXCEPT ![t] = IF Mutant = "regloss_retry" THEN "fix" ELSE "idle"]
  /\ UNCHANGED <<rp, rm, hb, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, mode,
                 fcnt, dirty, writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, errs,
                 envs, barge, prom, areq, dealloc, shk, unf>>

\* a BCB a victim search may take (a BCB registered against deallocation stays: the registrant
\* may be between its wakeup and its retry; mutant victim_ignores_avd: develop's rule)
Victimizable(b) ==
  /\ (fcnt[b] = 0 /\ mode[b] = "N") \/ Mutant = "claim_ignores_fix"
  /\ Waiters(b) = {} \/ Mutant = "claim_ignores_waiters"
  /\ ~dirty[b] \/ Mutant = "claim_dirty"
  /\ ~writing[b]
  /\ avd[b] = 0 \/ Mutant = "victim_ignores_avd"

\* the candidate's bucket latch is free (taken without waiting) or is the one already held
CandLatchOk(t, b) ==
  vpid[b] = 0 \/ Bkt(vpid[b]) = Bkt(rp[t]) \/ FreeK(Bkt(vpid[b]))

\* the first victimizable BCB in t's LRU order (private lists differ per thread: odd threads
\* walk down, even threads up); used only by the mutant victim_wait
FirstVictim(t) ==
  {b \in Bcbs : Victimizable(b) /\
                \A c \in Bcbs : Victimizable(c) => (IF t % 2 = 1 THEN c <= b ELSE b <= c)}

\* a fixer that missed takes a victim while holding its own bucket latch exclusive; any victimizable
\* candidate whose bucket latch it gets without waiting (mutant victim_wait: the first one in its LRU
\* order, waiting for that candidate's latch); the claim resets the BCB's counts and flags
\* (pgbuf_claim_move)
MissClaim(t) ==
  /\ pc[t] = "miss"
  /\ \E b \in Bcbs :
       /\ CandLatchOk(t, b)
       /\ Victimizable(b)
       /\ Mutant = "victim_wait" => b \in FirstVictim(t)
       /\ IF touched[b]
          THEN \* second chance: clear the use mark, look further
               /\ touched' = [touched EXCEPT ![b] = FALSE]
               /\ UNCHANGED <<vpid, mode, fcnt, bver, hb, pc, exh, avd, reg, areq>>
          ELSE /\ vpid' = [vpid EXCEPT ![b] = rp[t]]
               /\ mode' = [mode EXCEPT ![b] = "W"]
               /\ fcnt' = [fcnt EXCEPT ![b] = 1]
               /\ bver' = [bver EXCEPT ![b] = diskVer[rp[t]]]
               /\ touched' = [touched EXCEPT ![b] = FALSE]
               /\ hb' = [hb EXCEPT ![t] = b]
               /\ pc' = [pc EXCEPT ![t] = "load"]
               /\ exh' = [exh EXCEPT ![Bkt(rp[t])] = 0]
               /\ avd' = [c \in Bcbs |-> IF c = b THEN 0
                                         ELSE IF c = reg[t] /\ avd[c] > 0 THEN avd[c] - 1
                                         ELSE avd[c]]
               /\ reg' = [reg EXCEPT ![t] = 0]
               /\ areq' = [areq EXCEPT ![b] = FALSE]
  /\ UNCHANGED <<rp, rm, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, dirty, writing,
                 wwait, diskVer, latest, tmo, spur, errs, envs, barge, prom, dealloc, shk, unf>>

\* no candidate can be taken now: release the latch and retry the fix
\* (mutant victim_wait: keep the latch while a victim exists whose bucket latch is busy)
MissGiveUp(t) ==
  /\ pc[t] = "miss"
  /\ ~\E b \in Bcbs : CandLatchOk(t, b) /\ Victimizable(b)
  /\ Mutant = "victim_wait" => ~\E b \in Bcbs : Victimizable(b)
  /\ exh' = [exh EXCEPT ![Bkt(rp[t])] = 0]
  /\ pc' = [pc EXCEPT ![t] = "fix"]
  /\ UNCHANGED <<rp, rm, hb, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, mode,
                 fcnt, dirty, writing, wwait, touched, bver, diskVer, latest, tmo, spur, errs,
                 envs, barge, prom, avd, reg, areq, dealloc, shk, unf>>

\* the read is done: a READ request turns the loader's WRITE into READ and posts the readers
LoadEnd(t) ==
  /\ pc[t] = "load"
  /\ FreeK(Bkt(rp[t]))
  /\ LET b == hb[t] IN
       IF IsRead(rm[t])
       THEN /\ mode' = [mode EXCEPT ![b] = "R"]
            /\ hm' = [hm EXCEPT ![t] = "R"]
            /\ Post(PostSet(b, "R", writing[b]))
       ELSE /\ hm' = [hm EXCEPT ![t] = "W"]
            /\ UNCHANGED <<mode, posted>>
  /\ pc' = [pc EXCEPT ![t] = "hold"]
  /\ UNCHANGED <<rp, rm, hb, ops, inq, wm, tk, pv, cver, cpg, cerr, tick, vpid, fcnt, dirty,
                 writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, errs, envs, barge,
                 prom, avd, reg, areq, dealloc, shk, unf>>

\* the page read of a claim fails (exclusive latch): the BCB leaves the chain empty and every
\* waiter on it is woken; each removes its own entry, sees the BCB no longer holds its page and
\* searches the chain again (mutant loaderr_no_post: the waiters are not woken); the registrations of
\* deallocation-preventing waiters stay until each leaves, and the BCB is not reused before
LoadErr(t) ==
  /\ pc[t] = "load" /\ errs < MaxErr
  /\ errs' = errs + 1
  /\ FreeK(Bkt(rp[t]))
  /\ LET b == hb[t] IN
       /\ vpid' = [vpid EXCEPT ![b] = 0]
       /\ mode' = [mode EXCEPT ![b] = "N"]
       /\ fcnt' = [fcnt EXCEPT ![b] = 0]
       /\ Post(IF Mutant = "loaderr_no_post" THEN {} ELSE Waiters(b))
  /\ hb' = [hb EXCEPT ![t] = 0]
  /\ pc' = [pc EXCEPT ![t] = "idle"]
  /\ UNCHANGED <<rp, rm, hm, ops, inq, wm, tk, pv, cver, cpg, cerr, tick, dirty, writing, wwait,
                 touched, bver, diskVer, latest, exh, tmo, spur, envs, barge, prom, avd, reg, areq,
                 dealloc, shk, unf>>

\* promotion of a held READ to WRITE (exclusive latch). Alone and no write in progress: in place.
\* Otherwise (D13) the promoter keeps its READ, marks the BCB promotion-pending and waits to be woken
\* as the only holder with no write in progress; a second promotion on a pending BCB fails at once and
\* its caller unfixes and fixes WRITE (mutant promote_both_wait: the second waits too). PromoteWait
\* (comparison): release the READ and wait as a WRITE waiter.
Promote(t) ==
  /\ pc[t] = "hold" /\ rm[t] = "P" /\ hm[t] = "R"
  /\ LET b == hb[t]
         nf == fcnt[b] - 1
     IN /\ FreeK(Bkt(vpid[b]))
        /\ rm' = [rm EXCEPT ![t] = "W"]
        /\ IF fcnt[b] = 1 /\ (~writing[b] \/ Mutant = "write_ignores_writing")
           THEN /\ mode' = [mode EXCEPT ![b] = "W"]
                /\ hm' = [hm EXCEPT ![t] = "W"]
                /\ pv' = [pv EXCEPT ![t] = bver[b]]
                /\ UNCHANGED <<fcnt, pc, inq, wm, tk, tick, posted, wwait, hb, prom>>
           ELSE IF PromoteWait
           THEN /\ fcnt' = [fcnt EXCEPT ![b] = nf]
                /\ mode' = [mode EXCEPT ![b] = IF nf = 0 THEN "N" ELSE @]
                /\ hm' = [hm EXCEPT ![t] = ""]
                /\ pv' = [pv EXCEPT ![t] = bver[b]]
                /\ Enqueue(t, b, "W", writing[b])
                /\ UNCHANGED prom
           ELSE IF prom[b] # 0 /\ Mutant # "promote_both_wait"
           THEN \* fcnt[b] >= 2 here (the pending promoter and t)
                /\ fcnt' = [fcnt EXCEPT ![b] = nf]
                /\ hm' = [hm EXCEPT ![t] = ""]
                /\ hb' = [hb EXCEPT ![t] = 0]
                /\ pc' = [pc EXCEPT ![t] = "fix"]
                /\ Post(PromPost(b, nf, writing[b]))
                /\ UNCHANGED <<mode, pv, inq, wm, tk, tick, wwait, prom>>
           ELSE /\ prom' = [prom EXCEPT ![b] = IF @ # 0 THEN @ ELSE t]
                /\ pc' = [pc EXCEPT ![t] = "pwait"]
                /\ pv' = [pv EXCEPT ![t] = bver[b]]
                /\ UNCHANGED <<fcnt, mode, hm, hb, inq, wm, tk, tick, posted, wwait>>
  /\ UNCHANGED <<rp, ops, cver, cpg, cerr, vpid, dirty, writing, touched, bver, diskVer, latest,
                 exh, tmo, spur, errs, envs, barge, avd, reg, areq, dealloc, shk, unf>>

\* a waiting promoter wakes (posted, or spuriously) and takes the BCB to WRITE when it is the only
\* holder and no write is in progress; otherwise it waits again
PromWake(t, spurious) ==
  /\ pc[t] = "pwait"
  /\ IF spurious THEN ~posted[t] /\ spur < MaxSpur /\ spur' = spur + 1
                 ELSE posted[t] /\ UNCHANGED spur
  /\ LET b == hb[t] IN
       /\ FreeK(Bkt(vpid[b]))
       /\ posted' = [posted EXCEPT ![t] = FALSE]
       /\ IF fcnt[b] = 1 /\ ~writing[b]
          THEN /\ mode' = [mode EXCEPT ![b] = "W"]
               /\ hm' = [hm EXCEPT ![t] = "W"]
               /\ prom' = [prom EXCEPT ![b] = IF @ = t THEN 0 ELSE @]
               /\ pc' = [pc EXCEPT ![t] = "hold"]
          ELSE UNCHANGED <<mode, hm, prom, pc>>
  /\ UNCHANGED <<rp, rm, hb, ops, inq, wm, tk, pv, cver, cpg, cerr, tick, vpid, fcnt, dirty,
                 writing, wwait, touched, bver, diskVer, latest, exh, tmo, errs, envs, barge, avd,
                 reg, areq, dealloc, shk, unf>>

\* a waiting promoter's latch timeout or interrupt: clear the pending mark and wake the readers the mark
\* held off (mutant promote_cancel_no_post: does not wake them); the promotion fails with the READ kept,
\* and its caller unfixes it and fixes WRITE (the caller's unfix merged into this step: the state between
\* is an ordinary READ hold)
PromTimeout(t) ==
  /\ pc[t] = "pwait" /\ tmo < MaxTimeouts
  /\ tmo' = tmo + 1
  /\ LET b == hb[t]
         nf == fcnt[b] - 1
         nm == IF nf = 0 THEN "N" ELSE mode[b]
         S == IF Mutant = "promote_cancel_no_post" THEN {} ELSE PostSetP(b, nm, writing[b], FALSE)
     IN /\ FreeK(Bkt(vpid[b]))
        /\ fcnt' = [fcnt EXCEPT ![b] = nf]
        /\ mode' = [mode EXCEPT ![b] = nm]
        /\ prom' = [prom EXCEPT ![b] = IF @ = t THEN 0 ELSE @]
        /\ touched' = [touched EXCEPT ![b] = @ \/ nf = 0]
        /\ posted' = [w \in Procs |-> IF w = t THEN FALSE ELSE posted[w] \/ w \in S]
        /\ wwait' = [wwait EXCEPT ![b] =
                       @ \/ (WakeAtEnd = "flag" /\ nf = 0 /\ writing[b] /\ Waiters(b) # {})]
  /\ hb' = [hb EXCEPT ![t] = 0]
  /\ hm' = [hm EXCEPT ![t] = ""]
  /\ pv' = [pv EXCEPT ![t] = -1]
  /\ pc' = [pc EXCEPT ![t] = "fix"]
  /\ UNCHANGED <<rp, rm, ops, inq, wm, tk, cver, cpg, cerr, tick, vpid, dirty, writing, bver,
                 diskVer, latest, exh, spur, errs, envs, barge, avd, reg, areq, dealloc, shk, unf>>

\* WRITE unfix (exclusive section): the holder's change lands in the page; the unfix idles the latch,
\* leaves the use mark and posts the waiters; a release that leaves a pending promoter alone posts it. A WRITE holder
\* asked to flush (ASYNC_FLUSH_REQ) starts that flush in the same critical section and copies the page
\* itself (mutant unfix_ignores_areq). Vacuum deallocates the page at its unfix unless a fix registered
\* against it, a reader or writer waits on it, or a fixer still on its way holds the linking page.
Unfix(t) ==
  /\ pc[t] = "hold" /\ ~(rm[t] = "P" /\ hm[t] = "R")
  /\ hm[t] = "W"
  /\ LET b == hb[t]
         p == vpid[b]
         nf == fcnt[b] - 1
         nm == IF nf = 0 THEN "N" ELSE mode[b]
         fl == hm[t] = "W" /\ areq[b] /\ Mutant # "unfix_ignores_areq"
         dl == /\ rm[t] = "V" /\ hm[t] = "W" /\ avd[b] = 0
               /\ ~\E w \in Waiters(b) : wm[w] \in {"R", "W"}
               /\ ~\E u \in Workers : rm[u] = "D" /\ reg[u] = -1 /\ rp[u] = p /\ pc[u] \in {"fix", "miss"}
         S == (IF nf = 0 /\ Mutant # "unfix_no_post" THEN PostSet(b, "N", writing[b]) ELSE {})
              \cup (IF Mutant = "promote_no_post" THEN {} ELSE PromPost(b, nf, writing[b]))
     IN /\ FreeK(Bkt(p))
        /\ fcnt' = [fcnt EXCEPT ![b] = nf]
        /\ mode' = [mode EXCEPT ![b] = nm]
        /\ IF hm[t] = "W"
           THEN /\ bver' = [bver EXCEPT ![b] = @ + 1]
                /\ latest' = [latest EXCEPT ![p] = bver[b] + 1]
                /\ dirty' = [dirty EXCEPT ![b] = ~fl]
           ELSE UNCHANGED <<bver, latest, dirty>>
        /\ writing' = [writing EXCEPT ![b] = @ \/ fl]
        /\ areq' = [areq EXCEPT ![b] = @ /\ ~fl]
        /\ cver' = IF fl THEN [cver EXCEPT ![t] = bver[b] + 1] ELSE cver
        /\ cpg' = IF fl THEN [cpg EXCEPT ![t] = p] ELSE cpg
        /\ dealloc' = IF dl THEN [dealloc EXCEPT ![p] = TRUE] ELSE dealloc
        /\ touched' = [touched EXCEPT ![b] = @ \/ nf = 0]
        /\ Post(S)
        /\ wwait' = [wwait EXCEPT ![b] =
                       @ \/ (WakeAtEnd = "flag" /\ nf = 0 /\ writing[b] /\ Waiters(b) # {})]
        /\ hb' = [hb EXCEPT ![t] = IF fl THEN b ELSE 0]
        /\ pc' = [pc EXCEPT ![t] = IF fl THEN "copy" ELSE "idle"]
  /\ hm' = [hm EXCEPT ![t] = ""]
  /\ pv' = [pv EXCEPT ![t] = -1]
  /\ UNCHANGED <<rp, rm, ops, inq, wm, tk, cerr, tick, vpid, diskVer, exh, tmo, spur, errs, envs,
                 barge, prom, avd, reg, shk, unf>>

\* READ unfix (D5): the shared bucket latch, held across two steps. First the fix-count CAS (the last one
\* idles the latch and leaves the use mark; no LRU work), then, still under the shared latch, the wake
\* rule over the waiter list as it is now (a reader that re-fixed meanwhile changes what is admitted:
\* the rule reads the latch mode again) and the pending promoter left alone. Exclusive sections wait
\* for both steps (the list and the BCB's identity cannot change in between).
UnfixR1(t) ==
  /\ pc[t] = "hold" /\ hm[t] = "R" /\ rm[t] # "P"
  /\ LET b == hb[t]
         k == Bkt(vpid[b])
         nf == fcnt[b] - 1
     IN /\ NoX(k)
        /\ fcnt' = [fcnt EXCEPT ![b] = nf]
        /\ mode' = [mode EXCEPT ![b] = IF nf = 0 THEN "N" ELSE @]
        /\ touched' = [touched EXCEPT ![b] = @ \/ nf = 0]
        /\ shk' = [shk EXCEPT ![k] = @ + 1]
        /\ unf' = [unf EXCEPT ![t] = nf]
  /\ hm' = [hm EXCEPT ![t] = ""]
  /\ pv' = [pv EXCEPT ![t] = -1]
  /\ pc' = [pc EXCEPT ![t] = "unfix2"]
  /\ UNCHANGED <<rp, rm, hb, ops, inq, wm, tk, posted, cver, cpg, cerr, tick, vpid, dirty, writing,
                 wwait, bver, diskVer, latest, exh, tmo, spur, errs, envs, barge, prom, avd, reg, areq,
                 dealloc>>

UnfixR2(t) ==
  /\ pc[t] = "unfix2"
  /\ LET b == hb[t]
         k == Bkt(vpid[b])
         S == (IF unf[t] = 0 /\ Mutant # "unfix_no_post" THEN PostSet(b, mode[b], writing[b]) ELSE {})
              \cup (IF Mutant = "promote_no_post" THEN {} ELSE PromPost(b, fcnt[b], writing[b]))
     IN /\ Post(S)
        /\ wwait' = [wwait EXCEPT ![b] =
                       @ \/ (WakeAtEnd = "flag" /\ unf[t] = 0 /\ writing[b] /\ Waiters(b) # {})]
        /\ shk' = [shk EXCEPT ![k] = @ - 1]
  /\ unf' = [unf EXCEPT ![t] = -1]
  /\ hb' = [hb EXCEPT ![t] = 0]
  /\ pc' = [pc EXCEPT ![t] = "idle"]
  /\ UNCHANGED <<rp, rm, hm, ops, inq, wm, tk, pv, cver, cpg, cerr, tick, vpid, mode, fcnt, dirty,
                 writing, touched, bver, diskVer, latest, exh, tmo, spur, errs, envs, barge, prom, avd,
                 reg, areq, dealloc>>

\* a waiter wakes (posted, or spuriously) and retries from the chain after removing its own entry; a
\* deallocation-preventing fix keeps its registration (mutant reg_per_wait: drops it and registers
\* again when it waits again), and fails when the read of its page failed (D18)
WakeRetry(t, spurious) ==
  /\ pc[t] = "sleep" /\ inq[t]
  /\ IF spurious THEN ~posted[t] /\ spur < MaxSpur /\ spur' = spur + 1
                 ELSE posted[t] /\ UNCHANGED spur
  /\ FreeK(Bkt(rp[t]))
  /\ inq' = [inq EXCEPT ![t] = FALSE]
  /\ Leave(t)
  /\ hb' = [hb EXCEPT ![t] = 0]
  /\ IF rm[t] = "D" /\ vpid[hb[t]] # rp[t]
     THEN /\ pc' = [pc EXCEPT ![t] = "idle"]
          /\ Unreg(t)
     ELSE /\ pc' = [pc EXCEPT ![t] = "fix"]
          /\ IF rm[t] = "D" /\ Mutant = "reg_per_wait" THEN Unreg(t) ELSE UNCHANGED <<avd, reg>>
  /\ UNCHANGED <<rp, rm, hm, ops, wm, tk, pv, cver, cpg, cerr, tick, vpid, mode, fcnt, dirty,
                 writing, touched, bver, diskVer, latest, exh, tmo, errs, envs, barge, prom, areq,
                 dealloc, shk, unf>>

\* a waiter's latch timeout or interrupt: remove its own entry; retry if the BCB now admits it,
\* otherwise the fix fails (mutant timeout_no_remove: leave the entry behind)
Timeout(t) ==
  /\ pc[t] = "sleep" /\ inq[t] /\ tmo < MaxTimeouts
  /\ tmo' = tmo + 1
  /\ FreeK(Bkt(rp[t]))
  /\ inq' = [inq EXCEPT ![t] = Mutant = "timeout_no_remove"]
  /\ Leave(t)
  /\ LET b == hb[t] IN
       IF CompatM(wm[t], mode[b], writing[b], prom[b] # 0) /\ ~(rm[t] = "D" /\ vpid[b] # rp[t])
       THEN /\ pc' = [pc EXCEPT ![t] = "fix"]
            /\ hb' = [hb EXCEPT ![t] = IF Mutant = "timeout_no_remove" THEN @ ELSE 0]
            /\ UNCHANGED <<pv, avd, reg>>
       ELSE /\ pc' = [pc EXCEPT ![t] = "idle"]
            /\ hb' = [hb EXCEPT ![t] = IF Mutant = "timeout_no_remove" THEN @ ELSE 0]
            /\ pv' = [pv EXCEPT ![t] = -1]
            /\ Unreg(t)
  /\ UNCHANGED <<rp, rm, hm, ops, wm, tk, cver, cpg, cerr, tick, vpid, mode, fcnt, dirty, writing,
                 touched, bver, diskVer, latest, exh, spur, errs, envs, barge, prom, areq, dealloc, shk, unf>>

\* the page copy of a flush (no latch held; the write-in-progress flag keeps WRITE out)
Copy(t) ==
  /\ pc[t] = "copy"
  /\ \/ /\ errs < MaxErr /\ errs' = errs + 1
        /\ cerr' = [cerr EXCEPT ![t] = TRUE]
     \/ /\ UNCHANGED errs
        /\ cerr' = [cerr EXCEPT ![t] = FALSE]
  /\ cver' = [cver EXCEPT ![t] = bver[hb[t]]]
  /\ pc' = [pc EXCEPT ![t] = "cend"]
  /\ UNCHANGED <<rp, rm, hb, hm, ops, inq, wm, tk, posted, pv, cpg, tick, vpid, mode, fcnt, dirty,
                 writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, envs, barge, prom,
                 avd, reg, areq, dealloc, shk, unf>>

\* the end of a flush (exclusive latch): clear the flag; on error the page is dirty again; wake every
\* flush waiter, the reader and writer waiters the write held off, and a pending promoter left alone
\* (mutants flend_no_post, flend_no_prom_post)
CopyEnd(t) ==
  /\ pc[t] = "cend"
  /\ LET b == hb[t]
         S == (IF (wwait[b] \/ (WakeAtEnd = "always" /\ Waiters(b) # {})) /\ Mutant # "flend_no_post"
               THEN PostSet(b, mode[b], FALSE) ELSE {})
              \cup (IF Mutant = "flend_no_post" THEN {} ELSE FWaiters(b))
              \cup (IF Mutant = "flend_no_prom_post" THEN {} ELSE PromPost(b, fcnt[b], FALSE))
     IN /\ FreeK(Bkt(vpid[b]))
        /\ writing' = [writing EXCEPT ![b] = FALSE]
        /\ IF cerr[t]
           THEN /\ dirty' = [dirty EXCEPT ![b] = Mutant # "flerr_no_redirty"]
                /\ UNCHANGED diskVer
           ELSE /\ diskVer' = [diskVer EXCEPT ![cpg[t]] = cver[t]]
                /\ UNCHANGED dirty
        /\ wwait' = [wwait EXCEPT ![b] = FALSE]
        /\ Post(S)
  /\ hb' = [hb EXCEPT ![t] = 0]
  /\ pc' = [pc EXCEPT ![t] = IF t = D THEN "scan" ELSE "idle"]
  /\ UNCHANGED <<rp, rm, hm, ops, inq, wm, tk, pv, cver, cpg, cerr, tick, vpid, mode, fcnt,
                 touched, bver, latest, exh, tmo, spur, errs, envs, barge, prom, avd, reg, areq,
                 dealloc, shk, unf>>

\* the page flush daemon takes a dirty page it can write now (exclusive latch)
DaemonStart ==
  /\ Daemon /\ pc[D] = "scan"
  /\ \E b \in Bcbs :
       /\ vpid[b] # 0 /\ dirty[b] /\ ~writing[b] /\ mode[b] # "W"
       /\ FreeK(Bkt(vpid[b]))
       /\ writing' = [writing EXCEPT ![b] = TRUE]
       /\ dirty' = [dirty EXCEPT ![b] = FALSE]
       /\ cver' = [cver EXCEPT ![D] = bver[b]]
       /\ cpg' = [cpg EXCEPT ![D] = vpid[b]]
       /\ hb' = [hb EXCEPT ![D] = b]
  /\ pc' = [pc EXCEPT ![D] = "copy"]
  /\ UNCHANGED <<rp, rm, hm, ops, inq, wm, tk, posted, pv, cerr, tick, vpid, mode, fcnt, wwait,
                 touched, bver, diskVer, latest, exh, tmo, spur, errs, envs, barge, prom, avd, reg,
                 areq, dealloc, shk, unf>>

\* the daemon finds a dirty page WRITE-latched: it asks the holder to flush at its unfix
DaemonAsk ==
  /\ Daemon /\ pc[D] = "scan"
  /\ \E b \in Bcbs :
       /\ vpid[b] # 0 /\ dirty[b] /\ ~writing[b] /\ mode[b] = "W" /\ ~areq[b]
       /\ FreeK(Bkt(vpid[b]))
       /\ areq' = [areq EXCEPT ![b] = TRUE]
  /\ UNCHANGED <<pc, rp, rm, hb, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, mode,
                 fcnt, dirty, writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, errs,
                 envs, barge, prom, avd, reg, dealloc, shk, unf>>

DaemonDone ==
  /\ Daemon /\ pc[D] = "scan"
  /\ \A w \in Workers : pc[w] = "done"
  /\ \A b \in Bcbs : ~dirty[b]
  /\ pc' = [pc EXCEPT ![D] = "done"]
  /\ UNCHANGED <<rp, rm, hb, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, mode,
                 fcnt, dirty, writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, errs,
                 envs, barge, prom, avd, reg, areq, dealloc, shk, unf>>

\* environment: a clean, unfixed BCB without waiters or deallocation-prevention registrations is
\* invalidated
Invalidate ==
  /\ envs < MaxEnv
  /\ \E b \in Bcbs :
       /\ vpid[b] # 0 /\ fcnt[b] = 0 /\ mode[b] = "N" /\ Waiters(b) = {} /\ avd[b] = 0
       /\ ~dirty[b] /\ ~writing[b]
       /\ FreeK(Bkt(vpid[b]))
       /\ vpid' = [vpid EXCEPT ![b] = 0]
       /\ touched' = [touched EXCEPT ![b] = FALSE]
  /\ envs' = envs + 1
  /\ UNCHANGED <<pc, rp, rm, hb, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, mode,
                 fcnt, dirty, writing, wwait, bver, diskVer, latest, exh, tmo, spur, errs, barge,
                 prom, avd, reg, areq, dealloc, shk, unf>>

AllDone == \A t \in Procs : pc[t] = "done"

Terminating == AllDone /\ UNCHANGED vars

\* the non-fault steps of one process
ProcStep(t) ==
  \/ Begin(t) \/ Finish(t) \/ FixShared(t) \/ Pin(t) \/ FixExcl(t) \/ FixRegLost(t) \/ MissClaim(t)
  \/ MissGiveUp(t) \/ LoadEnd(t) \/ LoadErr(t) \/ Promote(t) \/ PromWake(t, FALSE) \/ Unfix(t)
  \/ UnfixR1(t) \/ UnfixR2(t)
  \/ WakeRetry(t, FALSE) \/ Copy(t) \/ CopyEnd(t)

DaemonStep == DaemonStart \/ DaemonAsk \/ DaemonDone

Next ==
  \/ \E t \in Procs : ProcStep(t) \/ WakeRetry(t, TRUE) \/ PromWake(t, TRUE) \/ Timeout(t)
                      \/ PromTimeout(t)
  \/ DaemonStep
  \/ Invalidate
  \/ Terminating

Spec == Init /\ [][Next]_vars

FairSpec == Spec /\ \A t \in Procs : WF_vars(ProcStep(t)) /\ WF_vars(DaemonStep)

------------------------------------------------------------------------------
\* Properties

TypeOK ==
  /\ \A t \in Procs :
       /\ pc[t] \in {"idle", "fix", "pin", "miss", "load", "hold", "pwait", "unfix2", "sleep", "copy",
                     "cend", "scan", "done"}
       /\ unf[t] >= -1
       /\ rp[t] \in 0..NP /\ hb[t] \in 0..NB /\ cpg[t] \in 0..NP
       /\ rm[t] \in {"", "R", "Rc", "W", "Wc", "P", "C", "D", "V"} /\ hm[t] \in {"", "R", "W"}
       /\ wm[t] \in {"", "R", "W", "F"}
       /\ ops[t] >= 0 /\ ops[t] <= MaxOps
       /\ tk[t] >= 0 /\ pv[t] >= -1 /\ cver[t] >= 0
       /\ inq[t] \in BOOLEAN /\ posted[t] \in BOOLEAN /\ cerr[t] \in BOOLEAN
       /\ reg[t] >= -1 /\ reg[t] <= NB
  /\ \A b \in Bcbs :
       /\ mode[b] \in {"N", "R", "W"} /\ fcnt[b] >= 0 /\ fcnt[b] <= NT /\ vpid[b] \in 0..NP
       /\ bver[b] >= 0 /\ prom[b] \in 0..NT /\ avd[b] >= 0 /\ avd[b] <= NT
       /\ dirty[b] \in BOOLEAN /\ writing[b] \in BOOLEAN /\ wwait[b] \in BOOLEAN /\ touched[b] \in BOOLEAN
       /\ areq[b] \in BOOLEAN
  /\ \A p \in Pages : diskVer[p] >= 0 /\ latest[p] >= 0 /\ dealloc[p] \in BOOLEAN
  /\ \A k \in Bkts : exh[k] \in 0..NT
  /\ tick >= 1
  /\ tmo >= 0 /\ tmo <= MaxTimeouts /\ spur >= 0 /\ spur <= MaxSpur
  /\ errs >= 0 /\ errs <= MaxErr /\ envs >= 0 /\ envs <= MaxEnv
  /\ barge \in BOOLEAN

HoldersOf(b) == {t \in Workers : pc[t] \in Holding /\ hb[t] = b}

\* a READ unfix is between its fix-count CAS and its wake step on b
Unfixing(b) == \E t \in Workers : pc[t] = "unfix2" /\ hb[t] = b

\* C1 the fix count is the number of holders; the latch is idle exactly when nobody holds it
FcntExact ==
  \A b \in Bcbs : fcnt[b] = Cardinality(HoldersOf(b)) /\ (mode[b] = "N" <=> fcnt[b] = 0)

\* C2 a WRITE latch has one holder and no reader beside it
Exclusive ==
  \A b \in Bcbs : mode[b] = "W" => fcnt[b] = 1

\* C3 a fix returns, and keeps while held, the BCB of the page asked for
SamePage ==
  \A t \in Workers : pc[t] \in Holding => vpid[hb[t]] = rp[t]

\* C4 nothing writes a page while it is copied for a flush, so the copy is the page as it was
NoWriteDuringCopy ==
  /\ \A b \in Bcbs : writing[b] => mode[b] # "W"
  /\ \A t \in Procs : pc[t] = "cend" => cver[t] = bver[hb[t]]

\* C5 the latest change of every page is on disk or in the BCB holding it
NoLostUpdate ==
  \A p \in Pages : latest[p] = diskVer[p] \/ \E b \in Bcbs : vpid[b] = p /\ bver[b] = latest[p]

\* C6 a waiter entry belongs to a thread asleep on it, waiting for the page the BCB still holds, or
\* for no page once the read of that page failed
NoStaleWaiter ==
  \A t \in Procs : inq[t] => (pc[t] = "sleep" /\ vpid[hb[t]] \in {rp[t], 0})

\* C7 a latch nobody holds and no flush is copying never has waiters of whom none is woken, while
\* no thread is on its way to fix that page (a fixer releases and posts in turn); a pending promoter
\* left the only holder with no write in progress is woken
NoStrandedWaiter ==
  /\ \A b \in Bcbs :
       ~(/\ Waiters(b) # {}
         /\ fcnt[b] = 0 /\ ~writing[b]
         /\ \A w \in Waiters(b) : ~posted[w]
         /\ ~\E t \in Workers : pc[t] = "fix" /\ rp[t] = vpid[b]
         /\ ~Unfixing(b))
  /\ \A b \in Bcbs : ~(prom[b] # 0 /\ fcnt[b] = 1 /\ ~writing[b] /\ ~posted[prom[b]] /\ ~Unfixing(b))

\* C8 a page is held by at most one BCB
UniqueResident == \A p \in Pages : Cardinality(Resident(p)) <= 1

\* C9 a promotion hands over as WRITE the page the promoter read: nobody changes it in between
PromoteStable ==
  \A t \in Workers : (pc[t] = "hold" /\ hm[t] = "W" /\ pv[t] >= 0) => bver[hb[t]] = pv[t]

\* C10 a deallocation-preventing fix never gets a page that was deallocated
PreventDealloc ==
  \A t \in Workers : (rm[t] = "D" /\ pc[t] \in Holding) => ~dealloc[rp[t]]

\* C11 a waiter the wake rule admits now is already woken
PromptWake ==
  \A b \in Bcbs : (vpid[b] # 0 /\ ~Unfixing(b)) => \A w \in PostSet(b, mode[b], writing[b]) : posted[w]

\* C7 (liveness) every worker finishes its operations and the daemon finishes
Termination == <>AllDone

\* Well-formedness and the strengthening conjuncts the inductive check needs

Copying == {"copy", "cend"}

\* each process's fields in the shape its program counter allows
Shape ==
  /\ \A t \in Procs :
       /\ (t = D) => pc[t] \in {"scan", "copy", "cend", "done"} /\ rp[t] = 0 /\ ~inq[t] /\ hm[t] = ""
       /\ (t # D) => pc[t] \notin {"scan"}
       /\ pc[t] \in {"idle", "done", "fix", "miss", "scan"} => hb[t] = 0
       /\ pc[t] \in {"load", "hold", "pwait", "unfix2", "sleep", "copy", "cend", "pin"} => hb[t] \in Bcbs
       /\ (pc[t] = "unfix2") <=> unf[t] >= 0
       /\ pc[t] = "unfix2" => vpid[hb[t]] # 0
       /\ (hm[t] # "") <=> pc[t] \in {"hold", "pwait"}
       /\ inq[t] <=> pc[t] = "sleep"
       /\ posted[t] => inq[t] \/ pc[t] = "pwait"
       /\ (t # D /\ pc[t] \notin {"idle", "done"}) => rp[t] \in Pages /\ rm[t] \in Ops \cup {"W"}
       /\ pc[t] = "sleep" =>
            /\ wm[t] \in {"R", "W", "F"}
            /\ wm[t] = "R" => rm[t] \in {"R", "P", "D"}
            /\ wm[t] = "W" => rm[t] \in {"W", "V"}
            /\ wm[t] = "F" <=> rm[t] = "C"
            /\ tk[t] >= 1 /\ tk[t] < tick
       /\ (t # D /\ pc[t] \in Copying) => rm[t] \in {"C", "W", "V"}
       /\ pc[t] = "hold" /\ rm[t] = "P" => hm[t] = "R"
       /\ pc[t] = "hold" /\ hm[t] = "W" => mode[hb[t]] = "W"
       /\ pc[t] \in {"hold", "pwait"} /\ hm[t] = "R" => mode[hb[t]] = "R"
       /\ pc[t] = "pwait" => hm[t] = "R" /\ rm[t] = "W" /\ prom[hb[t]] = t /\ pv[t] = bver[hb[t]]
       /\ pc[t] = "load" => mode[hb[t]] = "W" /\ vpid[hb[t]] = rp[t] /\ ~dirty[hb[t]] /\ ~writing[hb[t]]
       /\ pc[t] = "miss" => exh[Bkt(rp[t])] = t /\ Resident(rp[t]) = {}
       /\ pc[t] \in Copying => writing[hb[t]] /\ cpg[t] = vpid[hb[t]] /\ cver[t] = bver[hb[t]]
       /\ pv[t] # -1 => pc[t] \in {"hold", "pwait"} /\ bver[hb[t]] = pv[t]
       /\ pv[t] # -1 /\ pc[t] = "hold" => hm[t] = "W"
       /\ pc[t] # "pin"
  /\ \A k \in Bkts : exh[k] # 0 => pc[exh[k]] = "miss" /\ Bkt(rp[exh[k]]) = k
  /\ \A t, u \in Procs : (t # u /\ inq[t] /\ inq[u]) => tk[t] # tk[u]
  /\ \A b \in Bcbs : prom[b] # 0 => pc[prom[b]] = "pwait" /\ hb[prom[b]] = b
  /\ \A k \in Bkts : shk[k] = Cardinality({t \in Workers : pc[t] = "unfix2" /\ Bkt(vpid[hb[t]]) = k})
  /\ \A k \in Bkts : shk[k] > 0 => exh[k] = 0

\* a write in progress has exactly one copier
OneCopier ==
  \A b \in Bcbs :
    /\ writing[b] => \E t \in Procs : pc[t] \in Copying /\ hb[t] = b
    /\ \A t, u \in Procs : (pc[t] \in Copying /\ pc[u] \in Copying /\ hb[t] = b /\ hb[u] = b) => t = u

\* an empty BCB is idle and clean, and every waiter left on it (after a failed read) is woken
EmptyIdle ==
  \A b \in Bcbs : vpid[b] = 0 =>
    /\ fcnt[b] = 0 /\ mode[b] = "N" /\ ~dirty[b] /\ ~writing[b] /\ ~areq[b] /\ prom[b] = 0
    /\ \A w \in Waiters(b) : posted[w]

\* where the latest version of each page is
Versions ==
  /\ \A b \in Bcbs : vpid[b] # 0 => bver[b] = latest[vpid[b]]
  /\ \A b \in Bcbs : (vpid[b] # 0 /\ ~dirty[b] /\ ~writing[b]) => diskVer[vpid[b]] = bver[b]
  /\ \A p \in Pages : Resident(p) = {} => diskVer[p] = latest[p]

\* waiters of whom none is woken have a reason to be woken later: a holder whose release posts, a
\* write in progress whose end posts, a WRITE holder asked to flush at its unfix
WaitReason ==
  \A b \in Bcbs :
    (Waiters(b) # {} /\ \A w \in Waiters(b) : ~posted[w]) =>
      /\ (\E w \in Waiters(b) : wm[w] # "F") => fcnt[b] > 0 \/ (writing[b] /\ wwait[b]) \/ Unfixing(b)
      /\ (\E w \in Waiters(b) : wm[w] = "F") => writing[b] \/ (mode[b] = "W" /\ areq[b])

\* a waiter that only a write in progress holds off has the write-waiter flag set for it
WriteWaitFlag ==
  \A b \in Bcbs : (writing[b] /\ vpid[b] # 0) =>
    wwait[b] \/ Unfixing(b) \/ \A w \in PostSetP(b, mode[b], FALSE, prom[b] # 0) : posted[w]

\* a flush request stands only on a dirty WRITE-latched page no flush is writing
FlushRequest ==
  \A b \in Bcbs : areq[b] => vpid[b] # 0 /\ dirty[b] /\ mode[b] = "W" /\ ~writing[b]

\* every deallocation-prevention registration belongs to a fix on its way to the page the BCB holds,
\* or asleep on it
Registrations ==
  /\ \A b \in Bcbs : avd[b] = Cardinality({t \in Workers : reg[t] = b})
  /\ \A t \in Procs :
       /\ reg[t] # 0 => t \in Workers /\ rm[t] = "D"
       /\ reg[t] = -1 => pc[t] \in {"fix", "miss"}
       /\ reg[t] > 0 =>
            \/ pc[t] = "fix" /\ vpid[reg[t]] \in {rp[t], 0}
            \/ pc[t] = "sleep" /\ hb[t] = reg[t]
       /\ (rm[t] = "D" /\ pc[t] \in {"fix", "miss"}) => reg[t] # 0
       /\ (rm[t] = "D" /\ pc[t] = "sleep") => reg[t] = hb[t]
       /\ (rm[t] = "D" /\ pc[t] \in {"fix", "miss", "load", "hold"} /\ reg[t] # 0 /\ ~RegLost(t)) => ~dealloc[rp[t]]
       /\ (rm[t] = "D" /\ pc[t] = "sleep" /\ vpid[hb[t]] = rp[t]) => ~dealloc[rp[t]]

IndInv ==
  /\ TypeOK
  /\ Shape
  /\ OneCopier
  /\ EmptyIdle
  /\ Versions
  /\ WaitReason
  /\ FlushRequest
  /\ WriteWaitFlag
  /\ Registrations
  /\ FcntExact
  /\ Exclusive
  /\ SamePage
  /\ NoWriteDuringCopy
  /\ NoLostUpdate
  /\ NoStaleWaiter
  /\ NoStrandedWaiter
  /\ UniqueResident
  /\ PromoteStable
  /\ PreventDealloc
  /\ PromptWake

\* Witnesses: outcomes that must be reachable (each cfg expects the invariant violated)
NotBarged == ~barge
NotWriteWaitsForCopy == ~\E t \in Workers : inq[t] /\ wm[t] = "W" /\ writing[hb[t]]
NotReclaimed == ~\E t \in Workers : pc[t] = "load"
NotCopyFailed == ~\E t \in Procs : pc[t] = "cend" /\ cerr[t]
NotFlushWaiter == ~\E t \in Workers : inq[t] /\ wm[t] = "F"
NotTimedOutRetry == ~(tmo > 0 /\ \E t \in Workers : pc[t] = "hold")
NotPromoteWaiting == ~\E t \in Workers : pc[t] = "pwait"
NotSecondPromoteFailed == ~\E t \in Workers : pc[t] = "fix" /\ rm[t] = "W" /\ \E b \in Bcbs : prom[b] # 0 /\ vpid[b] = rp[t]
NotHolderFlushed == ~\E t \in Workers : pc[t] = "copy" /\ rm[t] \in {"W", "V"}
NotDeallocPrevented == ~\E t \in Workers : rm[t] = "V" /\ pc[t] = "hold" /\ avd[hb[t]] > 0
NotDeallocated == ~\E p \in Pages : dealloc[p]
=============================================================================
