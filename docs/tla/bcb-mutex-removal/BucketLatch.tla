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

\* PromoteWait TRUE releases the READ and waits for WRITE (develop's PGBUF_PROMOTE_SHARED_READER);
\* FALSE fails (ER_PAGE_LATCH_PROMOTE_FAIL) and the caller re-fixes WRITE.
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

\* Ops: "R" read fix, "Rc" conditional read fix, "W" write fix, "Wc" conditional write fix,
\*      "P" read fix then promote to write, "C" synchronous flush of a page (checkpoint, backup)

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
          barge    \* ghost: a READ was granted while a WRITE waiter was queued

vars == <<pc, rp, rm, hb, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick,
          vpid, mode, fcnt, dirty, writing, wwait, touched, bver, diskVer, latest, exh,
          tmo, spur, errs, envs, barge>>

Resident(p) == {b \in Bcbs : vpid[b] = p}
Waiters(b) == {w \in Procs : inq[w] /\ hb[w] = b}
FreeK(k) == exh[k] = 0
Holding == {"hold", "load"}

\* can a waiter of mode m proceed on a BCB in state (md, wr)?
CompatM(m, md, wr) ==
  IF m = "R" THEN md \in {"N", "R"}
  ELSE IF m = "W" THEN md = "N" /\ ~wr
  ELSE md # "W" /\ ~wr

\* waiters a releaser posts when it leaves b in state (md, wr): from the head, every compatible
\* waiter before the first WRITE waiter; a WRITE waiter at the head alone
PostFrom(ws, md, wr) ==
  LET heads == {h \in ws : \A v \in ws : tk[h] <= tk[v]}
      wsW == {w \in ws : wm[w] = "W"}
  IN IF \E h \in heads : wm[h] = "W"
     THEN IF CompatM("W", md, wr) THEN heads ELSE {}
     ELSE {w \in ws : CompatM(wm[w], md, wr) /\ \A v \in wsW : tk[w] < tk[v]}

PostSet(b, md, wr) == PostFrom(Waiters(b), md, wr)

\* the same rule over the waiters other than ex (a waiter that is removing its own entry)
PostSetEx(b, md, wr, ex) == PostFrom(Waiters(b) \ {ex}, md, wr)

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

------------------------------------------------------------------------------
\* a worker picks its next operation
Begin(t) ==
  /\ pc[t] = "idle" /\ ops[t] > 0
  /\ \E p \in Pages, o \in Ops :
       /\ rp' = [rp EXCEPT ![t] = p]
       /\ rm' = [rm EXCEPT ![t] = o]
  /\ ops' = [ops EXCEPT ![t] = @ - 1]
  /\ pc' = [pc EXCEPT ![t] = "fix"]
  /\ UNCHANGED <<hb, hm, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, mode, fcnt, dirty,
                 writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, errs, envs, barge>>

Finish(t) ==
  /\ t \in Workers /\ pc[t] = "idle" /\ ops[t] = 0
  /\ pc' = [pc EXCEPT ![t] = "done"]
  /\ UNCHANGED <<rp, rm, hb, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, mode,
                 fcnt, dirty, writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur,
                 errs, envs, barge>>

IsRead(o) == o \in {"R", "Rc", "P"}

\* READ fix under the shared bucket latch: walk the chain, raise the count by CAS
FixShared(t) ==
  /\ pc[t] = "fix" /\ IsRead(rm[t])
  /\ FreeK(Bkt(rp[t]))
  /\ \E b \in Resident(rp[t]) :
       /\ mode[b] \in {"N", "R"}
       /\ IF Mutant = "pin_after_latch"
          THEN \* the lookup under the latch, the pin after releasing it
               /\ hb' = [hb EXCEPT ![t] = b]
               /\ pc' = [pc EXCEPT ![t] = "pin"]
               /\ UNCHANGED <<mode, fcnt, hm, barge>>
          ELSE /\ mode' = [mode EXCEPT ![b] = "R"]
               /\ fcnt' = [fcnt EXCEPT ![b] = @ + 1]
               /\ hb' = [hb EXCEPT ![t] = b]
               /\ hm' = [hm EXCEPT ![t] = "R"]
               /\ pc' = [pc EXCEPT ![t] = "hold"]
               /\ barge' = (barge \/ \E w \in Waiters(b) : wm[w] = "W")
  /\ UNCHANGED <<rp, rm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, dirty,
                 writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, errs, envs>>

\* mutant pin_after_latch: the CAS on the word alone, after the latch was released
Pin(t) ==
  /\ pc[t] = "pin"
  /\ LET b == hb[t] IN
       /\ mode[b] \in {"N", "R"}
       /\ mode' = [mode EXCEPT ![b] = "R"]
       /\ fcnt' = [fcnt EXCEPT ![b] = @ + 1]
  /\ hm' = [hm EXCEPT ![t] = "R"]
  /\ pc' = [pc EXCEPT ![t] = "hold"]
  /\ UNCHANGED <<rp, rm, hb, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, dirty,
                 writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, errs, envs, barge>>

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
  /\ pc[t] = "fix"
  /\ LET p == rp[t]
         k == Bkt(p)
     IN /\ FreeK(k)
        /\ IsRead(rm[t]) => ~(\E b \in Resident(p) : mode[b] \in {"N", "R"})
        /\ IF Resident(p) # {}
           THEN \E b \in Resident(p) :
             IF IsRead(rm[t])
             THEN \* mode[b] = "W" here
                  IF rm[t] = "Rc"
                  THEN /\ pc' = [pc EXCEPT ![t] = "idle"]
                       /\ UNCHANGED <<hb, inq, wm, tk, tick, posted, wwait, writing, dirty, cver, cpg,
                                      mode, fcnt, hm, exh, pv>>
                  ELSE /\ Enqueue(t, b, "R", FALSE)
                       /\ UNCHANGED <<writing, dirty, cver, cpg, mode, fcnt, hm, exh, pv>>
             ELSE IF rm[t] \in {"W", "Wc"}
             THEN IF (mode[b] = "N" \/ (Mutant = "write_ignores_readers" /\ mode[b] = "R"))
                     /\ (~writing[b] \/ Mutant = "write_ignores_writing")
                  THEN /\ mode' = [mode EXCEPT ![b] = "W"]
                       /\ fcnt' = [fcnt EXCEPT ![b] = @ + 1]
                       /\ hb' = [hb EXCEPT ![t] = b]
                       /\ hm' = [hm EXCEPT ![t] = "W"]
                       /\ pc' = [pc EXCEPT ![t] = "hold"]
                       /\ UNCHANGED <<inq, wm, tk, tick, posted, wwait, writing, dirty, cver, cpg, exh, pv>>
                  ELSE IF rm[t] = "Wc"
                  THEN /\ pc' = [pc EXCEPT ![t] = "idle"]
                       /\ UNCHANGED <<mode, fcnt, hb, hm, inq, wm, tk, tick, posted, wwait, writing,
                                      dirty, cver, cpg, exh, pv>>
                  ELSE /\ Enqueue(t, b, "W", writing[b])
                       /\ UNCHANGED <<mode, fcnt, hm, writing, dirty, cver, cpg, exh, pv>>
             ELSE \* "C": synchronous flush of p
                  IF ~dirty[b] /\ ~writing[b]
                  THEN /\ pc' = [pc EXCEPT ![t] = "idle"]
                       /\ UNCHANGED <<mode, fcnt, hb, hm, inq, wm, tk, tick, posted, wwait, writing,
                                      dirty, cver, cpg, exh, pv>>
                  ELSE IF writing[b] \/ mode[b] = "W"
                  THEN /\ Enqueue(t, b, "F", writing[b])
                       /\ UNCHANGED <<mode, fcnt, hm, writing, dirty, cver, cpg, exh, pv>>
                  ELSE /\ writing' = [writing EXCEPT ![b] = TRUE]
                       /\ dirty' = [dirty EXCEPT ![b] = FALSE]
                       /\ cver' = [cver EXCEPT ![t] = bver[b]]
                       /\ cpg' = [cpg EXCEPT ![t] = p]
                       /\ hb' = [hb EXCEPT ![t] = b]
                       /\ pc' = [pc EXCEPT ![t] = "copy"]
                       /\ UNCHANGED <<mode, fcnt, hm, inq, wm, tk, tick, posted, wwait, exh, pv>>
           ELSE IF rm[t] = "C"
           THEN /\ pc' = [pc EXCEPT ![t] = "idle"]
                /\ UNCHANGED <<mode, fcnt, hb, hm, inq, wm, tk, tick, posted, wwait, writing, dirty,
                               cver, cpg, exh, pv>>
           ELSE /\ exh' = [exh EXCEPT ![k] = IF Mutant = "miss_no_latch" THEN 0 ELSE t]
                /\ pc' = [pc EXCEPT ![t] = "miss"]
                /\ UNCHANGED <<mode, fcnt, hb, hm, inq, wm, tk, tick, posted, wwait, writing, dirty,
                               cver, cpg, pv>>
  /\ UNCHANGED <<rp, rm, ops, cerr, vpid, touched, bver, diskVer, latest, tmo, spur, errs, envs, barge>>

\* a BCB a victim search may take
Victimizable(b) ==
  /\ (fcnt[b] = 0 /\ mode[b] = "N") \/ Mutant = "claim_ignores_fix"
  /\ Waiters(b) = {} \/ Mutant = "claim_ignores_waiters"
  /\ ~dirty[b] \/ Mutant = "claim_dirty"
  /\ ~writing[b]

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
\* order, waiting for that candidate's latch)
MissClaim(t) ==
  /\ pc[t] = "miss"
  /\ \E b \in Bcbs :
       /\ CandLatchOk(t, b)
       /\ Victimizable(b)
       /\ Mutant = "victim_wait" => b \in FirstVictim(t)
       /\ IF touched[b]
          THEN \* second chance: clear the use mark, look further
               /\ touched' = [touched EXCEPT ![b] = FALSE]
               /\ UNCHANGED <<vpid, mode, fcnt, bver, hb, pc, exh>>
          ELSE /\ vpid' = [vpid EXCEPT ![b] = rp[t]]
               /\ mode' = [mode EXCEPT ![b] = "W"]
               /\ fcnt' = [fcnt EXCEPT ![b] = 1]
               /\ bver' = [bver EXCEPT ![b] = diskVer[rp[t]]]
               /\ touched' = [touched EXCEPT ![b] = FALSE]
               /\ hb' = [hb EXCEPT ![t] = b]
               /\ pc' = [pc EXCEPT ![t] = "load"]
               /\ exh' = [exh EXCEPT ![Bkt(rp[t])] = 0]
  /\ UNCHANGED <<rp, rm, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, dirty, writing,
                 wwait, diskVer, latest, tmo, spur, errs, envs, barge>>

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
                 envs, barge>>

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
                 writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, errs, envs, barge>>

\* the page read of a claim fails (exclusive latch): the BCB leaves the chain empty and every
\* waiter on it is woken; each removes its own entry, sees the BCB no longer holds its page and
\* searches the chain again (mutant loaderr_no_post: the waiters are not woken)
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
                 touched, bver, diskVer, latest, exh, tmo, spur, envs, barge>>

\* promotion of a held READ to WRITE (exclusive latch): in place when alone, otherwise release the
\* READ and wait as a WRITE waiter (mutant promote_keep_read: wait still holding the READ)
Promote(t) ==
  /\ pc[t] = "hold" /\ rm[t] = "P" /\ hm[t] = "R"
  /\ LET b == hb[t] IN
       /\ FreeK(Bkt(vpid[b]))
       /\ rm' = [rm EXCEPT ![t] = "W"]
       /\ pv' = [pv EXCEPT ![t] = IF ~PromoteWait /\ ~(fcnt[b] = 1 /\ ~writing[b]) THEN -1 ELSE bver[b]]
       /\ IF fcnt[b] = 1 /\ (~writing[b] \/ Mutant = "write_ignores_writing")
          THEN /\ mode' = [mode EXCEPT ![b] = "W"]
               /\ hm' = [hm EXCEPT ![t] = "W"]
               /\ UNCHANGED <<fcnt, pc, inq, wm, tk, tick, posted, wwait, hb>>
          ELSE IF ~PromoteWait
          THEN \* not alone (or a write in progress): fail, keep the READ; the caller unfixes and re-fixes
               \* WRITE (modeled as the end of this operation)
               /\ fcnt' = [fcnt EXCEPT ![b] = @ - 1]
               /\ mode' = [mode EXCEPT ![b] = IF fcnt[b] = 1 THEN "N" ELSE @]
               /\ hm' = [hm EXCEPT ![t] = ""]
               /\ hb' = [hb EXCEPT ![t] = 0]
               /\ pc' = [pc EXCEPT ![t] = "idle"]
               /\ Post(IF fcnt[b] = 1 THEN PostSet(b, "N", writing[b]) ELSE {})
               /\ wwait' = [wwait EXCEPT ![b] =
                              @ \/ (WakeAtEnd = "flag" /\ fcnt[b] = 1 /\ writing[b] /\ Waiters(b) # {})]
               /\ UNCHANGED <<inq, wm, tk, tick>>
          ELSE /\ fcnt' = [fcnt EXCEPT ![b] = @ - 1]
               /\ mode' = [mode EXCEPT ![b] = IF fcnt[b] = 1 THEN "N" ELSE @]
               /\ hm' = [hm EXCEPT ![t] = ""]
               /\ Enqueue(t, b, "W", writing[b])
  /\ UNCHANGED <<rp, ops, cver, cpg, cerr, vpid, dirty, writing, touched, bver, diskVer, latest,
                 exh, tmo, spur, errs, envs, barge>>

\* unfix: a WRITE holder's change lands in the page; the last unfix idles the latch, leaves the use
\* mark and posts the waiters
Unfix(t) ==
  /\ pc[t] = "hold" /\ ~(rm[t] = "P" /\ hm[t] = "R")
  /\ LET b == hb[t]
         p == vpid[b]
         nf == fcnt[b] - 1
         nm == IF nf = 0 THEN "N" ELSE mode[b]
     IN /\ FreeK(Bkt(p))
        /\ fcnt' = [fcnt EXCEPT ![b] = nf]
        /\ mode' = [mode EXCEPT ![b] = nm]
        /\ IF hm[t] = "W"
           THEN /\ bver' = [bver EXCEPT ![b] = @ + 1]
                /\ latest' = [latest EXCEPT ![p] = bver[b] + 1]
                /\ dirty' = [dirty EXCEPT ![b] = TRUE]
           ELSE UNCHANGED <<bver, latest, dirty>>
        /\ touched' = [touched EXCEPT ![b] = @ \/ nf = 0]
        /\ IF nf = 0 /\ Mutant # "unfix_no_post"
           THEN Post(PostSet(b, "N", writing[b]))
           ELSE UNCHANGED posted
        /\ wwait' = [wwait EXCEPT ![b] =
                       @ \/ (WakeAtEnd = "flag" /\ nf = 0 /\ writing[b] /\ Waiters(b) # {})]
  /\ hb' = [hb EXCEPT ![t] = 0]
  /\ hm' = [hm EXCEPT ![t] = ""]
  /\ pv' = [pv EXCEPT ![t] = -1]
  /\ pc' = [pc EXCEPT ![t] = "idle"]
  /\ UNCHANGED <<rp, rm, ops, inq, wm, tk, cver, cpg, cerr, tick, vpid, writing, diskVer,
                 exh, tmo, spur, errs, envs, barge>>

\* a waiter wakes (posted, or spuriously) and retries from the chain after removing its own entry
WakeRetry(t, spurious) ==
  /\ pc[t] = "sleep" /\ inq[t]
  /\ IF spurious THEN ~posted[t] /\ spur < MaxSpur /\ spur' = spur + 1
                 ELSE posted[t] /\ UNCHANGED spur
  /\ FreeK(Bkt(rp[t]))
  /\ inq' = [inq EXCEPT ![t] = FALSE]
  /\ Leave(t)
  /\ hb' = [hb EXCEPT ![t] = 0]
  /\ pc' = [pc EXCEPT ![t] = "fix"]
  /\ UNCHANGED <<rp, rm, hm, ops, wm, tk, pv, cver, cpg, cerr, tick, vpid, mode, fcnt, dirty,
                 writing, touched, bver, diskVer, latest, exh, tmo, errs, envs, barge>>

\* a waiter's latch timeout or interrupt: remove its own entry; retry if the BCB now admits it,
\* otherwise the fix fails (mutant timeout_no_remove: leave the entry behind)
Timeout(t) ==
  /\ pc[t] = "sleep" /\ inq[t] /\ tmo < MaxTimeouts
  /\ tmo' = tmo + 1
  /\ FreeK(Bkt(rp[t]))
  /\ inq' = [inq EXCEPT ![t] = Mutant = "timeout_no_remove"]
  /\ Leave(t)
  /\ IF CompatM(wm[t], mode[hb[t]], writing[hb[t]])
     THEN /\ pc' = [pc EXCEPT ![t] = "fix"]
          /\ hb' = [hb EXCEPT ![t] = IF Mutant = "timeout_no_remove" THEN @ ELSE 0]
          /\ UNCHANGED pv
     ELSE /\ pc' = [pc EXCEPT ![t] = "idle"]
          /\ hb' = [hb EXCEPT ![t] = IF Mutant = "timeout_no_remove" THEN @ ELSE 0]
          /\ pv' = [pv EXCEPT ![t] = -1]
  /\ UNCHANGED <<rp, rm, hm, ops, wm, tk, cver, cpg, cerr, tick, vpid, mode, fcnt, dirty, writing,
                 touched, bver, diskVer, latest, exh, spur, errs, envs, barge>>

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
                 writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, envs, barge>>

\* the end of a flush (exclusive latch): clear the flag; on error the page is dirty again; wake the
\* waiters for the write
CopyEnd(t) ==
  /\ pc[t] = "cend"
  /\ LET b == hb[t] IN
       /\ FreeK(Bkt(vpid[b]))
       /\ writing' = [writing EXCEPT ![b] = FALSE]
       /\ IF cerr[t]
          THEN /\ dirty' = [dirty EXCEPT ![b] = Mutant # "flerr_no_redirty"]
               /\ UNCHANGED diskVer
          ELSE /\ diskVer' = [diskVer EXCEPT ![cpg[t]] = cver[t]]
               /\ UNCHANGED dirty
       /\ wwait' = [wwait EXCEPT ![b] = FALSE]
       /\ IF (wwait[b] \/ (WakeAtEnd = "always" /\ Waiters(b) # {})) /\ Mutant # "flend_no_post"
          THEN Post(PostSet(b, mode[b], FALSE))
          ELSE UNCHANGED posted
  /\ hb' = [hb EXCEPT ![t] = 0]
  /\ pc' = [pc EXCEPT ![t] = IF t = D THEN "scan" ELSE "idle"]
  /\ UNCHANGED <<rp, rm, hm, ops, inq, wm, tk, pv, cver, cpg, cerr, tick, vpid, mode, fcnt,
                 touched, bver, latest, exh, tmo, spur, errs, envs, barge>>

\* the page flush daemon takes a dirty page it can write now (exclusive latch); a WRITE-latched or
\* already written page is left for later
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
                 touched, bver, diskVer, latest, exh, tmo, spur, errs, envs, barge>>

DaemonDone ==
  /\ Daemon /\ pc[D] = "scan"
  /\ \A w \in Workers : pc[w] = "done"
  /\ \A b \in Bcbs : ~dirty[b]
  /\ pc' = [pc EXCEPT ![D] = "done"]
  /\ UNCHANGED <<rp, rm, hb, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, vpid, mode,
                 fcnt, dirty, writing, wwait, touched, bver, diskVer, latest, exh, tmo, spur, errs,
                 envs, barge>>

\* environment: a clean, unfixed BCB without waiters is invalidated (page deallocated)
Invalidate ==
  /\ envs < MaxEnv
  /\ \E b \in Bcbs :
       /\ vpid[b] # 0 /\ fcnt[b] = 0 /\ mode[b] = "N" /\ Waiters(b) = {}
       /\ ~dirty[b] /\ ~writing[b]
       /\ FreeK(Bkt(vpid[b]))
       /\ vpid' = [vpid EXCEPT ![b] = 0]
       /\ touched' = [touched EXCEPT ![b] = FALSE]
  /\ envs' = envs + 1
  /\ UNCHANGED <<pc, rp, rm, hb, hm, ops, inq, wm, tk, posted, pv, cver, cpg, cerr, tick, mode,
                 fcnt, dirty, writing, wwait, bver, diskVer, latest, exh, tmo, spur, errs, barge>>

AllDone == \A t \in Procs : pc[t] = "done"

Terminating == AllDone /\ UNCHANGED vars

\* the non-fault steps of one process
ProcStep(t) ==
  \/ Begin(t) \/ Finish(t) \/ FixShared(t) \/ Pin(t) \/ FixExcl(t) \/ MissClaim(t)
  \/ MissGiveUp(t) \/ LoadEnd(t) \/ LoadErr(t) \/ Promote(t) \/ Unfix(t) \/ WakeRetry(t, FALSE)
  \/ Copy(t) \/ CopyEnd(t)

DaemonStep == DaemonStart \/ DaemonDone

Next ==
  \/ \E t \in Procs : ProcStep(t) \/ WakeRetry(t, TRUE) \/ Timeout(t)
  \/ DaemonStep
  \/ Invalidate
  \/ Terminating

Spec == Init /\ [][Next]_vars

FairSpec == Spec /\ \A t \in Procs : WF_vars(ProcStep(t)) /\ WF_vars(DaemonStep)

------------------------------------------------------------------------------
\* Properties

TypeOK ==
  /\ \A t \in Procs :
       /\ pc[t] \in {"idle", "fix", "pin", "miss", "load", "hold", "sleep", "copy", "cend", "scan", "done"}
       /\ rp[t] \in 0..NP /\ hb[t] \in 0..NB /\ cpg[t] \in 0..NP
       /\ rm[t] \in {"", "R", "Rc", "W", "Wc", "P", "C"} /\ hm[t] \in {"", "R", "W"}
       /\ wm[t] \in {"", "R", "W", "F"}
       /\ ops[t] >= 0 /\ ops[t] <= MaxOps
       /\ tk[t] >= 0 /\ pv[t] >= -1 /\ cver[t] >= 0
       /\ inq[t] \in BOOLEAN /\ posted[t] \in BOOLEAN /\ cerr[t] \in BOOLEAN
  /\ \A b \in Bcbs :
       /\ mode[b] \in {"N", "R", "W"} /\ fcnt[b] >= 0 /\ fcnt[b] <= NT /\ vpid[b] \in 0..NP
       /\ bver[b] >= 0
       /\ dirty[b] \in BOOLEAN /\ writing[b] \in BOOLEAN /\ wwait[b] \in BOOLEAN /\ touched[b] \in BOOLEAN
  /\ \A p \in Pages : diskVer[p] >= 0 /\ latest[p] >= 0
  /\ \A k \in Bkts : exh[k] \in 0..NT
  /\ tick >= 1
  /\ tmo >= 0 /\ tmo <= MaxTimeouts /\ spur >= 0 /\ spur <= MaxSpur
  /\ errs >= 0 /\ errs <= MaxErr /\ envs >= 0 /\ envs <= MaxEnv
  /\ barge \in BOOLEAN

HoldersOf(b) == {t \in Workers : pc[t] \in Holding /\ hb[t] = b}

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
\* no thread is on its way to fix that page (a fixer releases and posts in turn)
NoStrandedWaiter ==
  \A b \in Bcbs :
    ~(/\ Waiters(b) # {}
      /\ fcnt[b] = 0 /\ ~writing[b]
      /\ \A w \in Waiters(b) : ~posted[w]
      /\ ~\E t \in Workers : pc[t] = "fix" /\ rp[t] = vpid[b])

\* C8 a page is held by at most one BCB
UniqueResident == \A p \in Pages : Cardinality(Resident(p)) <= 1

\* C9 a promotion that had to wait hands over a page nobody changed since the promoter's read
PromoteStable ==
  \A t \in Workers : (pc[t] = "hold" /\ hm[t] = "W" /\ pv[t] >= 0) => bver[hb[t]] = pv[t]

\* C10 (liveness) every worker finishes its operations and the daemon finishes
Termination == <>AllDone

\* Well-formedness and the strengthening conjuncts the inductive check needs

Copying == {"copy", "cend"}

\* each process's fields in the shape its program counter allows
Shape ==
  /\ \A t \in Procs :
       /\ (t = D) => pc[t] \in {"scan", "copy", "cend", "done"} /\ rp[t] = 0 /\ ~inq[t] /\ hm[t] = ""
       /\ (t # D) => pc[t] \notin {"scan"}
       /\ pc[t] \in {"idle", "done", "fix", "miss", "scan"} => hb[t] = 0
       /\ pc[t] \in {"load", "hold", "sleep", "copy", "cend", "pin"} => hb[t] \in Bcbs
       /\ (hm[t] # "") <=> pc[t] = "hold"
       /\ inq[t] <=> pc[t] = "sleep"
       /\ posted[t] => inq[t]
       /\ (t # D /\ pc[t] \notin {"idle", "done"}) => rp[t] \in Pages /\ rm[t] \in Ops \cup {"W"}
       /\ pc[t] = "sleep" =>
            /\ wm[t] \in {"R", "W", "F"}
            /\ wm[t] = "R" => rm[t] \in {"R", "P"}
            /\ wm[t] = "W" => rm[t] = "W"
            /\ wm[t] = "F" <=> rm[t] = "C"
            /\ tk[t] >= 1 /\ tk[t] < tick
       /\ (t # D /\ pc[t] \in Copying) => rm[t] = "C"
       /\ pc[t] = "hold" /\ rm[t] = "P" => hm[t] = "R"
       /\ pc[t] = "hold" /\ hm[t] = "W" => mode[hb[t]] = "W"
       /\ pc[t] = "hold" /\ hm[t] = "R" => mode[hb[t]] = "R"
       /\ pc[t] = "load" => mode[hb[t]] = "W" /\ vpid[hb[t]] = rp[t] /\ ~dirty[hb[t]] /\ ~writing[hb[t]]
       /\ pc[t] = "miss" => exh[Bkt(rp[t])] = t /\ Resident(rp[t]) = {}
       /\ pc[t] \in Copying => writing[hb[t]] /\ cpg[t] = vpid[hb[t]] /\ cver[t] = bver[hb[t]]
       /\ pv[t] # -1 => pc[t] = "hold" /\ hm[t] = "W" /\ bver[hb[t]] = pv[t]
       /\ pc[t] # "pin"
  /\ \A k \in Bkts : exh[k] # 0 => pc[exh[k]] = "miss" /\ Bkt(rp[exh[k]]) = k
  /\ \A t, u \in Procs : (t # u /\ inq[t] /\ inq[u]) => tk[t] # tk[u]

\* a write in progress has exactly one copier
OneCopier ==
  \A b \in Bcbs :
    /\ writing[b] => \E t \in Procs : pc[t] \in Copying /\ hb[t] = b
    /\ \A t, u \in Procs : (pc[t] \in Copying /\ pc[u] \in Copying /\ hb[t] = b /\ hb[u] = b) => t = u

\* an empty BCB is idle and clean, and every waiter left on it (after a failed read) is woken
EmptyIdle ==
  \A b \in Bcbs : vpid[b] = 0 =>
    fcnt[b] = 0 /\ mode[b] = "N" /\ ~dirty[b] /\ ~writing[b] /\ \A w \in Waiters(b) : posted[w]

\* where the latest version of each page is
Versions ==
  /\ \A b \in Bcbs : vpid[b] # 0 => bver[b] = latest[vpid[b]]
  /\ \A b \in Bcbs : (vpid[b] # 0 /\ ~dirty[b] /\ ~writing[b]) => diskVer[vpid[b]] = bver[b]
  /\ \A p \in Pages : Resident(p) = {} => diskVer[p] = latest[p]

\* waiters of whom none is woken have a reason to be woken later: a holder whose release posts, or
\* a write in progress whose end posts
WaitReason ==
  \A b \in Bcbs :
    (Waiters(b) # {} /\ \A w \in Waiters(b) : ~posted[w]) =>
      fcnt[b] > 0 \/ (writing[b] /\ wwait[b])

IndInv ==
  /\ TypeOK
  /\ Shape
  /\ OneCopier
  /\ EmptyIdle
  /\ Versions
  /\ WaitReason
  /\ FcntExact
  /\ Exclusive
  /\ SamePage
  /\ NoWriteDuringCopy
  /\ NoLostUpdate
  /\ NoStaleWaiter
  /\ NoStrandedWaiter
  /\ UniqueResident
  /\ PromoteStable

\* Witnesses: outcomes that must be reachable (each cfg expects the invariant violated)
NotBarged == ~barge
NotWriteWaitsForCopy == ~\E t \in Workers : inq[t] /\ wm[t] = "W" /\ writing[hb[t]]
NotReclaimed == ~\E t \in Workers : pc[t] = "load"
NotCopyFailed == ~\E t \in Procs : pc[t] = "cend" /\ cerr[t]
NotFlushWaiter == ~\E t \in Workers : inq[t] /\ wm[t] = "F"
NotTimedOutRetry == ~(tmo > 0 /\ \E t \in Workers : pc[t] = "hold")
=============================================================================
