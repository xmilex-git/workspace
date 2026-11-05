---------------------------- MODULE AtomicLatch ----------------------------
(* The atomic latch of one page-buffer BCB (CBRD-26425, PR #6704) as it is in
   develop 21c6e635d: the 64-bit word {latch_mode, waiter_exists, fcnt} changed
   only by CAS, the BCB mutex that serializes every slow path, the lock-free
   READ fix and unfix that take no mutex, the BCB wait queue with per-thread
   request mode and fix count, the latch timeout that removes a waiter, the
   wakeup of waiters by the last unfix, promotion, and the flush that queues
   PGBUF_LATCH_FLUSH waiters. One CAS loop = one step at its successful CAS
   (its decisions read only the word and mutex- or thread-owned state), except
   where the loop reads unprotected state first: those reads are their own
   steps. Refinement map, faults and results: MAP.md.

   Also modeled: the flush daemon's hand-off to the post-flush daemon, flush I/O
   errors and the errors between pgbuf_bcb_mark_is_flushing and the BCB unlock,
   the interrupt of a PGBUF_LATCH_FLUSH waiter, page invalidation (the BCB leaves
   the hash chain and is reused for another page), and, with TornReads, a
   lock-free hash walk or vpid compare that matches a BCB holding another page
   (concurrent rehash, a vpid read torn against the claimer's write).

   Code: the subset of known holes kept as the code has them (MAP.md, Findings):
     "H1" lock-free fix trusts a vpid read before its CAS (ABA after eviction)
     "H2" the timeout handler adds the next waiter's fcnt before re-checking it
     "H3" a READ holder's WRITE fix sets fcnt to 1 instead of adding 1
     "H4" the idle grant expects waiter_exists = FALSE and spins otherwise
     "A"  pgbuf_timed_sleep's ER_CSS_PTHREAD_COND_TIMEDOUT branch reads
          resume_status and writes request_latch_mode without the entry lock
     "E"  an error after pgbuf_bcb_mark_is_flushing and before the BCB unlock
          (TDE encryption, DWB slot) returns with FLUSHING set and DIRTY cleared
   Code = {} is the candidate fix of all six. *)
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS Threads, Flushers, Pages, None,
          MaxOps, MaxHold, MaxTimeouts, MaxFlush, Ops, DirtyAtStart,
          MaxErr,     \* flush errors (I/O, TDE, DWB) the environment may raise
          MaxEnv,     \* page invalidations (pgbuf_invalidate, _all, discard of a temp page)
          Daemons,    \* flushers that are the page flush daemon (may hand off to post-flush)
          TornReads,  \* the lock-free path may match a BCB that holds another page
          Code, Mutant

Procs == Threads \cup Flushers
Holes == {"H1", "H2", "H3", "H4", "A", "E"}
Mutants == {"none", "lf_unfix_last", "lf_any_mode", "lf_no_vpid_check",
            "block_no_bit", "flush_wake_no_clear", "lf_fix_ignores_bit",
            "unlatch_no_wakeup", "flush_intr_no_clear", "flerr_no_wake"}

ASSUME Assm == /\ Threads # {} /\ Pages # {} /\ Threads \cap Flushers = {}
               /\ None \notin Procs
               /\ MaxOps \in Nat /\ MaxHold \in Nat \ {0} /\ MaxTimeouts \in Nat
               /\ MaxFlush \in Nat /\ DirtyAtStart \subseteq BOOLEAN
               /\ Ops \subseteq {"fixR", "fixW", "fixRc", "fixWc", "promote"}
               /\ MaxErr \in Nat /\ MaxEnv \in Nat /\ Daemons \subseteq Flushers
               /\ TornReads \in BOOLEAN
               /\ Code \subseteq Holes /\ Mutant \in Mutants

VARIABLES
  word,      \* bufptr->atomic_latch: [m |-> latch_mode, w |-> waiter_exists, f |-> fcnt]
  mtx,       \* owner of the BCB mutex, None when free
  vpid,      \* bufptr->vpid
  q,         \* bufptr->next_wait_thrd chain, head first
  req,       \* thread_p->request_latch_mode ("N" = gave up, "F" = flush waiter)
  reqf,      \* thread_p->request_fix_count
  resumed,   \* thread_p->resume_status = THREAD_PGBUF_RESUMED
  promoter,  \* thread_p->wait_for_latch_promote
  hold,      \* holder->fix_count of the thread's holder entry on this BCB
  want,      \* the vpid the thread's current pgbuf_fix asks for
  rq, cnd,   \* request mode and condition of the current fix
  lw,        \* the word a CAS loop loaded (local)
  ehg,       \* can_grant of pgbuf_timed_sleep_error_handling (local)
  wi,        \* position of the wakeup loop in the queue (local)
  budget,    \* operations left per thread, flushes left per flusher
  toLeft,    \* latch timeouts / interrupts left (fault budget)
  dirty, flushing, async,  \* BCB flags DIRTY, FLUSHING_TO_DISK, ASYNC_FLUSH_REQ
  pc,
  wrongUse, spin, doubleLock, healFired, negFcnt, \* violation ghosts
  valid,     \* the BCB is in the hash chain under vpid (FALSE: invalid list or direct victim)
  errLeft,   \* flush errors left (fault budget)
  envLeft,   \* invalidations left
  ioErr,     \* the flush I/O in flight of a process failed (local)
  pfPend     \* the BCB sits in the post-flush queue (flushed_bcbs), FLUSHING still set

vars == <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
          lw, ehg, wi, budget, toLeft, dirty, flushing, async, pc,
          wrongUse, spin, doubleLock, healFired, negFcnt,
          valid, errLeft, envLeft, ioErr, pfPend>>
extra == <<valid, errLeft, envLeft, ioErr, pfPend>>

Word(m, w, f) == [m |-> m, w |-> w, f |-> f]
Range(s) == {s[i] : i \in 1..Len(s)}
RemoveAt(s, i) == SubSeq(s, 1, i - 1) \o SubSeq(s, i + 1, Len(s))
RemoveAll(s, x) == SelectSeq(s, LAMBDA e : e # x)
RWWaiting == \E i \in 1..Len(q) : req[q[i]] \in {"R", "W"}
H(h) == h \in Code

Init == /\ word = Word("N", FALSE, 0)
        /\ mtx = None
        /\ vpid \in Pages
        /\ q = <<>>
        /\ req = [p \in Procs |-> "N"]
        /\ reqf = [p \in Procs |-> 0]
        /\ resumed = [p \in Procs |-> FALSE]
        /\ promoter = [p \in Procs |-> FALSE]
        /\ hold = [t \in Threads |-> 0]
        /\ want \in [Threads -> Pages]
        /\ rq = [t \in Threads |-> "R"]
        /\ cnd = [t \in Threads |-> FALSE]
        /\ lw = [p \in Procs |-> Word("N", FALSE, 0)]
        /\ ehg = [t \in Threads |-> FALSE]
        /\ wi = [t \in Threads |-> 1]
        /\ budget = [p \in Procs |-> IF p \in Threads THEN MaxOps ELSE MaxFlush]
        /\ toLeft = MaxTimeouts
        /\ dirty \in DirtyAtStart /\ flushing = FALSE /\ async = FALSE
        /\ pc = [p \in Procs |-> IF p \in Threads THEN "idle" ELSE "fz_lock"]
        /\ wrongUse = FALSE /\ spin = FALSE /\ doubleLock = FALSE
        /\ healFired = FALSE /\ negFcnt = FALSE
        /\ valid = TRUE /\ errLeft = MaxErr /\ envLeft = MaxEnv
        /\ ioErr = [p \in Procs |-> FALSE] /\ pfPend = FALSE

Go(p, l) == pc' = [pc EXCEPT ![p] = l]

-----------------------------------------------------------------------------
(* pgbuf_fix: pick the operation *)
Begin_(t) ==
  /\ pc[t] = "idle" /\ budget[t] > 0
  /\ \E op \in Ops, p \in (IF hold[t] > 0 THEN {want[t]} ELSE Pages) :
       /\ op \in {"fixR", "fixW", "fixRc", "fixWc"} => hold[t] < MaxHold
       /\ op = "promote" => hold[t] > 0 /\ word.m = "R"
       /\ want' = [want EXCEPT ![t] = p]
       /\ rq' = [rq EXCEPT ![t] = IF op \in {"fixR", "fixRc"} THEN "R" ELSE "W"]
       /\ cnd' = [cnd EXCEPT ![t] = op \in {"fixRc", "fixWc"}]
       /\ Go(t, CASE op = "fixR" -> "lf_load"
                  [] op = "promote" -> "pr_lock"
                  [] OTHER -> "m_lock")
  /\ budget' = [budget EXCEPT ![t] = @ - 1]
  /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, lw, ehg, wi,
                 toLeft, dirty, flushing, async, wrongUse, spin, doubleLock, healFired, negFcnt>>

Finish_(t) == /\ pc[t] = "idle" /\ budget[t] = 0 /\ hold[t] = 0
             /\ Go(t, "Done")
             /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                            lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                            wrongUse, spin, doubleLock, healFired, negFcnt>>

(* pgbuf_lockfree_fix_ro: hash search without the bucket mutex, load the word,
   check it and the vpid, then CAS fcnt + 1 *)
LfLoad_(t) ==
  /\ pc[t] = "lf_load"
  /\ IF ((vpid = want[t] /\ valid) \/ TornReads)
           /\ (word.m = "R" \/ Mutant = "lf_any_mode")
           /\ (~word.w \/ Mutant = "lf_fix_ignores_bit") /\ word.f > 0
       THEN /\ lw' = [lw EXCEPT ![t] = word]
            /\ Go(t, IF Mutant = "lf_no_vpid_check" THEN "lf_cas" ELSE "lf_vpid")
       ELSE /\ Go(t, "m_lock") /\ UNCHANGED lw
  /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                 ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

LfVpid_(t) ==
  /\ pc[t] = "lf_vpid"
  /\ Go(t, IF (vpid = want[t] /\ valid) \/ TornReads THEN "lf_cas" ELSE "m_lock")
  /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

LfCas_(t) ==
  /\ pc[t] = "lf_cas"
  /\ IF word = lw[t]
       THEN /\ word' = [word EXCEPT !.f = @ + 1]
            /\ hold' = [hold EXCEPT ![t] = @ + 1]
            /\ Go(t, IF H("H1") \/ Mutant = "lf_no_vpid_check" THEN "use" ELSE "lf_recheck")
       ELSE /\ Go(t, "lf_load") /\ UNCHANGED <<word, hold>>
  /\ UNCHANGED <<mtx, vpid, q, req, reqf, resumed, promoter, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

\* candidate fix for H1: the fix now pins the BCB, so a vpid read after the CAS is stable
LfRecheck_(t) ==
  /\ pc[t] = "lf_recheck"
  /\ Go(t, IF vpid = want[t] /\ valid THEN "use" ELSE "unfix")
  /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

\* pgbuf_fix returns the page to its caller
Use_(t) ==
  /\ pc[t] = "use"
  /\ wrongUse' = (wrongUse \/ vpid # want[t] \/ ~valid)
  /\ Go(t, "idle")
  /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 spin, doubleLock, healFired, negFcnt>>

-----------------------------------------------------------------------------
(* slow path: PGBUF_BCB_LOCK, then pgbuf_latch_bcb_upon_fix *)
Lock_(p, from, to) ==
  /\ pc[p] = from /\ mtx = None
  /\ mtx' = p /\ Go(p, to)
  /\ UNCHANGED <<word, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

\* block: pgbuf_block_bcb -> pgbuf_timed_sleep (thread_lock_entry, then BCB unlock)
Block(t, nw, rf) ==
  /\ word' = nw
  /\ q' = Append(q, t)
  /\ req' = [req EXCEPT ![t] = rq[t]] /\ reqf' = [reqf EXCEPT ![t] = rf]
  /\ resumed' = [resumed EXCEPT ![t] = FALSE]
  /\ mtx' = None /\ Go(t, "wait")

Grant(t, nw) == /\ word' = nw /\ hold' = [hold EXCEPT ![t] = @ + 1]
                /\ mtx' = None /\ Go(t, "use")

Reject(t, nw) == /\ word' = nw /\ mtx' = None /\ Go(t, "idle")

MFix(t) ==
  /\ pc[t] = "m_fix"
  /\ LET heal == word.m = "N" /\ word.w /\ q = <<>>
         w0 == IF heal THEN [word EXCEPT !.w = FALSE] ELSE word
         bitOn == IF Mutant = "block_no_bit" THEN w0.w ELSE TRUE
         idle == w0.m = "N"
     IN
     /\ healFired' = (healFired \/ heal)
     /\ IF ~(vpid = want[t] /\ valid)
          THEN \* not resident: claim this BCB if it can be victimized, else another BCB serves it
               IF w0.f = 0 /\ idle /\ q = <<>> /\ ~dirty /\ ~flushing
                 THEN /\ vpid' = want[t] /\ valid' = TRUE
                      /\ IF w0.w /\ H("H4")
                           THEN /\ spin' = TRUE /\ Go(t, "spin")
                                /\ UNCHANGED <<word, mtx, hold>>
                           ELSE /\ Grant(t, Word(rq[t], w0.w, 1)) /\ UNCHANGED spin
                      /\ UNCHANGED <<q, req, reqf, resumed, promoter>>
                 ELSE /\ word' = w0 /\ mtx' = None /\ Go(t, "idle")
                      /\ UNCHANGED <<vpid, valid, q, req, reqf, resumed, promoter, hold, spin>>
        ELSE /\ UNCHANGED <<vpid, valid>>
             /\ IF idle
                  THEN \* idle grant: H4 force-expects waiter_exists = FALSE
                       /\ IF w0.w /\ H("H4")
                            THEN /\ spin' = TRUE /\ Go(t, "spin")
                                 /\ word' = w0 /\ UNCHANGED <<mtx, hold>>
                            ELSE /\ Grant(t, Word(rq[t], w0.w, 1)) /\ UNCHANGED spin
                       /\ UNCHANGED <<q, req, reqf, resumed, promoter>>
                  ELSE /\ UNCHANGED spin
                       /\ IF rq[t] = "R" /\ w0.m = "R"
                            THEN IF ~w0.w \/ hold[t] > 0
                                   THEN Grant(t, [w0 EXCEPT !.f = @ + 1])
                                        /\ UNCHANGED <<q, req, reqf, resumed, promoter>>
                                 ELSE IF cnd[t]
                                   THEN Reject(t, w0) /\ UNCHANGED <<q, req, reqf, resumed, promoter, hold>>
                                 ELSE Block(t, [w0 EXCEPT !.w = bitOn], 1) /\ UNCHANGED <<promoter, hold>>
                          ELSE IF hold[t] > 0 /\ w0.m = "W"
                            THEN Grant(t, [w0 EXCEPT !.f = @ + 1])
                                 /\ UNCHANGED <<q, req, reqf, resumed, promoter>>
                          ELSE IF hold[t] > 0 /\ w0.f = hold[t]
                            THEN \* READ holder alone asks WRITE: in-place upgrade
                                 Grant(t, Word("W", w0.w, IF H("H3") THEN 1 ELSE w0.f + 1))
                                 /\ UNCHANGED <<q, req, reqf, resumed, promoter>>
                          ELSE IF cnd[t]
                            THEN Reject(t, [w0 EXCEPT !.w = TRUE])
                                 /\ UNCHANGED <<q, req, reqf, resumed, promoter, hold>>
                          ELSE IF hold[t] > 0
                            THEN \* promote_needed: give the read fixes back and wait for WRITE
                                 /\ Block(t, [w0 EXCEPT !.f = @ - hold[t], !.w = bitOn], 1 + hold[t])
                                 /\ hold' = [hold EXCEPT ![t] = 0]
                                 /\ UNCHANGED promoter
                          ELSE Block(t, [w0 EXCEPT !.w = bitOn], 1) /\ UNCHANGED <<promoter, hold>>
  /\ UNCHANGED <<want, rq, cnd, lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, doubleLock, negFcnt, errLeft, envLeft, ioErr, pfPend>>

(* pgbuf_promote_read_latch (PGBUF_PROMOTE_SHARED_READER) under the BCB mutex *)
PrFix_(t) ==
  /\ pc[t] = "pr_fix"
  /\ LET headPromoter == q # <<>> /\ promoter[Head(q)]
     IN IF word.f = hold[t]
          THEN IF word.w /\ headPromoter
                 THEN mtx' = None /\ Go(t, "idle") /\ UNCHANGED <<word, q, req, reqf, resumed, promoter, hold>>
                 ELSE /\ word' = [word EXCEPT !.m = "W"] /\ mtx' = None /\ Go(t, "idle")
                      /\ UNCHANGED <<q, req, reqf, resumed, promoter, hold>>
          ELSE IF headPromoter
                 THEN mtx' = None /\ Go(t, "idle") /\ UNCHANGED <<word, q, req, reqf, resumed, promoter, hold>>
                 ELSE \* pgbuf_block_bcb (as_promote): first in the queue
                      /\ word' = [word EXCEPT !.f = @ - hold[t],
                                              !.w = IF Mutant = "block_no_bit" THEN @ ELSE TRUE]
                      /\ q' = <<t>> \o q
                      /\ req' = [req EXCEPT ![t] = "W"] /\ reqf' = [reqf EXCEPT ![t] = hold[t]]
                      /\ resumed' = [resumed EXCEPT ![t] = FALSE]
                      /\ promoter' = [promoter EXCEPT ![t] = TRUE]
                      /\ hold' = [hold EXCEPT ![t] = 0]
                      /\ mtx' = None /\ Go(t, "wait")
  /\ UNCHANGED <<vpid, want, rq, cnd, lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

-----------------------------------------------------------------------------
(* the wait (pgbuf_timed_sleep) *)
\* the waker's thread_lock_entry is held from its check to its CAS
EntryLocked(e) == \E t \in Threads : pc[t] = "wk_cas" /\ wi[t] <= Len(q) /\ q[wi[t]] = e

Woken_(t) ==
  /\ pc[t] = "wait" /\ resumed[t] /\ ~EntryLocked(t)
  /\ hold' = [hold EXCEPT ![t] = reqf[t]]
  /\ promoter' = [promoter EXCEPT ![t] = FALSE]
  /\ Go(t, "use")
  /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

\* fault: the thread is interrupted (r == NO_ERROR, not resumed: thread_lock_entry
\* again, then the check), or, with "A" fixed, the timed wait expires and the branch
\* re-takes the entry lock the same way
Timeout_(t) ==
  /\ pc[t] = "wait" /\ toLeft > 0 /\ ~EntryLocked(t)
  /\ toLeft' = toLeft - 1
  /\ promoter' = [promoter EXCEPT ![t] = FALSE]
  /\ IF resumed[t]
       THEN /\ hold' = [hold EXCEPT ![t] = reqf[t]] /\ Go(t, "use") /\ UNCHANGED req
       ELSE /\ req' = [req EXCEPT ![t] = "N"] /\ Go(t, "to_lock") /\ UNCHANGED hold
  /\ UNCHANGED <<word, mtx, vpid, q, reqf, resumed, want, rq, cnd,
                 lw, ehg, wi, budget, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

\* "A": ER_CSS_PTHREAD_COND_TIMEDOUT. thread_suspend_timeout_wakeup_and_unlock_entry
\* returned with the entry unlocked (thread_entry.cpp:600); the branch reads
\* resume_status (page_buffer.c:7420) and writes request_latch_mode = NO_LATCH
\* (7436) without it, and logtb_is_current_active == false re-sleeps (try_again,
\* resume_status = SUSPENDED at 7392) without it too.
TimedOut_(t) ==
  /\ H("A") /\ pc[t] = "wait" /\ ~resumed[t] /\ toLeft > 0 /\ ~EntryLocked(t)
  /\ toLeft' = toLeft - 1
  /\ Go(t, "to_chk")
  /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

ToChk_(t) ==
  /\ pc[t] = "to_chk"
  /\ IF resumed[t]
       THEN /\ hold' = [hold EXCEPT ![t] = reqf[t]] /\ promoter' = [promoter EXCEPT ![t] = FALSE]
            /\ Go(t, "use")
       ELSE /\ \E l \in {"to_set", "to_retry"} : Go(t, l)
            /\ UNCHANGED <<hold, promoter>>
  /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

ToSet_(t) ==
  /\ pc[t] = "to_set"
  /\ req' = [req EXCEPT ![t] = "N"] /\ promoter' = [promoter EXCEPT ![t] = FALSE]
  /\ Go(t, "to_lock")
  /\ UNCHANGED <<word, mtx, vpid, q, reqf, resumed, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

ToRetry_(t) ==
  /\ pc[t] = "to_retry"
  /\ resumed' = [resumed EXCEPT ![t] = FALSE]
  /\ Go(t, "wait")
  /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

Release(p, to) == mtx' = None /\ Go(p, to)

(* pgbuf_timed_sleep_error_handling *)
Eh_(t) ==
  /\ pc[t] = "eh"
  /\ IF q = <<>>
       THEN Release(t, "idle") /\ UNCHANGED q
       ELSE IF Head(q) # t
         THEN q' = RemoveAll(q, t) /\ Release(t, "idle")
         ELSE q' = Tail(q) /\ mtx' = mtx /\ Go(t, "eh_loop")
  /\ UNCHANGED <<word, vpid, req, reqf, resumed, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

\* case 3 loop. H2: the CAS reads the next waiter's request mode without its entry
\* lock and adds its fix count; the re-check under the entry lock comes after.
EhLoop_(t) ==
  /\ pc[t] = "eh_loop"
  /\ IF q = <<>>
       THEN Release(t, "idle") /\ UNCHANGED <<word, q, resumed, ehg>>
       ELSE LET c == Head(q) IN
            IF H("H2")
              THEN /\ ehg' = [ehg EXCEPT ![t] = word.m = "R" /\ req[c] = "R"]
                   /\ IF word.m = "R" /\ req[c] = "R"
                        THEN word' = [word EXCEPT !.f = @ + reqf[c]]
                        ELSE UNCHANGED word
                   /\ Go(t, "eh_lk") /\ UNCHANGED <<mtx, q, resumed>>
              ELSE /\ UNCHANGED ehg
                   /\ IF word.m = "R" /\ req[c] = "R"
                        THEN /\ word' = [word EXCEPT !.f = @ + reqf[c]]
                             /\ q' = Tail(q) /\ resumed' = [resumed EXCEPT ![c] = TRUE]
                             /\ Go(t, "eh_loop") /\ UNCHANGED mtx
                        ELSE Release(t, "idle") /\ UNCHANGED <<word, q, resumed>>
  /\ UNCHANGED <<vpid, req, reqf, promoter, hold, want, rq, cnd,
                 lw, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

EhLk_(t) ==
  /\ pc[t] = "eh_lk"
  /\ LET c == Head(q) IN
     IF ehg[t] /\ req[c] = "R"
       THEN /\ q' = Tail(q) /\ resumed' = [resumed EXCEPT ![c] = TRUE]
            /\ Go(t, "eh_loop") /\ UNCHANGED mtx
       ELSE Release(t, "idle") /\ UNCHANGED <<q, resumed>>
  /\ UNCHANGED <<word, vpid, req, reqf, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

-----------------------------------------------------------------------------
(* pgbuf_unfix: pgbuf_unlatch_thrd_holder, then pgbuf_lockfree_unfix_ro, else
   the mutex path pgbuf_unlatch_bcb_upon_unfix *)
Unfix_(t) ==
  /\ (pc[t] = "idle" /\ hold[t] > 0) \/ pc[t] = "unfix"
  /\ hold' = [hold EXCEPT ![t] = @ - 1]
  /\ IF word.m = "R" /\ ~word.w /\ (word.f # 1 \/ Mutant = "lf_unfix_last")
       THEN word' = [word EXCEPT !.f = @ - 1] /\ Go(t, "idle")
       ELSE Go(t, "uf_lock") /\ UNCHANGED word
  /\ UNCHANGED <<mtx, vpid, q, req, reqf, resumed, promoter, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

UfUnl_(t) ==
  /\ pc[t] = "uf_unl"
  /\ IF word.f - 1 < 0
       THEN /\ word' = Word("N", FALSE, 0) /\ negFcnt' = TRUE
            /\ Go(t, IF Mutant = "unlatch_no_wakeup" THEN "uf_async" ELSE "wk")
       ELSE /\ word' = [word EXCEPT !.f = @ - 1, !.m = IF word.f - 1 = 0 THEN "N" ELSE @]
            /\ Go(t, IF word.f - 1 = 0 /\ Mutant # "unlatch_no_wakeup" THEN "wk" ELSE "uf_async")
            /\ UNCHANGED negFcnt
  /\ dirty' = (dirty \/ word.m = "W")
  /\ wi' = [wi EXCEPT ![t] = 1]
  /\ UNCHANGED <<mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                 lw, ehg, budget, toLeft, flushing, async,
                 wrongUse, spin, doubleLock, healFired>>

(* pgbuf_wakeup_reader_writer: one waiter per step *)
WkEnd(t) == /\ word' = IF RWWaiting THEN word ELSE [word EXCEPT !.w = FALSE]
            /\ Go(t, "uf_async")

Wk_(t) ==
  /\ pc[t] = "wk"
  /\ IF wi[t] > Len(q)
       THEN WkEnd(t) /\ UNCHANGED <<q, wi, lw>>
       ELSE LET e == q[wi[t]] IN
            IF req[e] = "N"
              THEN q' = RemoveAt(q, wi[t]) /\ UNCHANGED <<word, wi, lw, pc>>
            ELSE IF req[e] = "F"
              THEN wi' = [wi EXCEPT ![t] = @ + 1] /\ UNCHANGED <<word, q, lw, pc>>
            ELSE IF word.m = "N" \/ (word.m = "R" /\ req[e] = "R")
              THEN \* thread_lock_entry (e) taken here, inside the CAS loop
                   lw' = [lw EXCEPT ![t] = word] /\ Go(t, "wk_cas") /\ UNCHANGED <<word, q, wi>>
            ELSE IF word.m = "R"
              THEN wi' = [wi EXCEPT ![t] = @ + 1] /\ UNCHANGED <<word, q, lw, pc>>
            ELSE WkEnd(t) /\ UNCHANGED <<q, wi, lw>>
  /\ UNCHANGED <<mtx, vpid, req, reqf, resumed, promoter, hold, want, rq, cnd,
                 ehg, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

\* a failed CAS loops back to thread_lock_entry on the entry it already holds
WkCas_(t) ==
  /\ pc[t] = "wk_cas"
  /\ LET e == q[wi[t]] IN
     IF word # lw[t]
       THEN /\ doubleLock' = TRUE /\ Go(t, "dead")
            /\ UNCHANGED <<word, q, resumed>>
       ELSE /\ word' = Word(req[e], word.w, word.f + reqf[e])
            /\ q' = RemoveAt(q, wi[t])
            /\ resumed' = [resumed EXCEPT ![e] = TRUE]
            /\ Go(t, "wk") /\ UNCHANGED doubleLock
  /\ UNCHANGED <<mtx, vpid, req, reqf, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, healFired, negFcnt>>

\* pgbuf_wake_flush_waiters: dequeue every FLUSH waiter and wake it, then
\* (CBRD-27084) clear waiter_exists if no reader or writer is left
WakeFlushWaiters(noClear) ==
  LET isF(e) == req[e] = "F" /\ e \in Flushers
      q2 == SelectSeq(q, LAMBDA e : ~isF(e))
  IN /\ q' = q2
     /\ resumed' = [e \in Procs |-> IF e \in Range(q) /\ isF(e) THEN TRUE ELSE resumed[e]]
     /\ word' = IF ~noClear /\ ~(\E i \in 1..Len(q2) : req[q2[i]] \in {"R", "W"})
                  THEN [word EXCEPT !.w = FALSE] ELSE word

(* pgbuf_bcb_flush_with_wal up to the BCB unlock: pgbuf_bcb_mark_is_flushing, then
   the page copy (tde_encrypt_data_page, dwb_set_data_on_next_slot), which may fail
   and return with the BCB still locked; the caller unlocks *)
StartFlush(p, next) ==
  \/ /\ flushing' = TRUE /\ dirty' = FALSE /\ async' = FALSE
     /\ Release(p, "fl_io") /\ UNCHANGED <<errLeft, word, q, resumed>>
  \/ /\ errLeft > 0 /\ errLeft' = errLeft - 1
     /\ IF H("E")
          THEN /\ flushing' = TRUE /\ dirty' = FALSE /\ async' = FALSE
               /\ UNCHANGED <<word, q, resumed>>
          ELSE \* fix: what the I/O error path does (page_buffer.c:11079-11088):
               \* pgbuf_bcb_mark_was_not_flushed (was_dirty), pgbuf_wake_flush_waiters
               /\ async' = FALSE /\ UNCHANGED <<flushing, dirty>>
               /\ WakeFlushWaiters(Mutant = "flush_wake_no_clear")
     /\ Release(p, next)

(* pgbuf_bcb_is_async_flush_request -> pgbuf_bcb_safe_flush_force_unlock (async) *)
UfAsync(t) ==
  /\ pc[t] = "uf_async"
  /\ IF async /\ dirty /\ ~flushing
          /\ (word.m \in {"N", "R"} \/ hold[t] > 0)
       THEN StartFlush(t, "idle")
       ELSE Release(t, "idle") /\ UNCHANGED <<flushing, dirty, async, errLeft, word, q, resumed>>
  /\ UNCHANGED <<vpid, req, reqf, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, wrongUse, spin, doubleLock, healFired, negFcnt,
                 valid, envLeft, ioErr, pfPend>>

-----------------------------------------------------------------------------
(* flush: pgbuf_bcb_safe_flush_internal (synchronous), pgbuf_bcb_flush_with_wal *)
\* a flusher in Daemons is the page flush daemon (pgbuf_flush_victim_candidates,
\* pgbuf_flush_neighbor_safe): it calls pgbuf_bcb_flush_with_wal directly and skips
\* a page it cannot flush now; the others are synchronous safe flushes
FzDec(f) ==
  /\ pc[f] = "fz_dec"
  /\ IF ~dirty
       THEN Release(f, "fz_next") /\ UNCHANGED <<word, q, req, resumed, flushing, dirty, async, errLeft>>
       ELSE IF ~flushing /\ word.m \in {"N", "R"}
         THEN StartFlush(f, "fz_next") /\ UNCHANGED req
       ELSE IF f \in Daemons
         THEN Release(f, "fz_next") /\ UNCHANGED <<word, q, req, resumed, flushing, dirty, async, errLeft>>
         ELSE \* write-latched or being flushed: wait for the flush as PGBUF_LATCH_FLUSH
              /\ word' = [word EXCEPT !.w = TRUE]
              /\ async' = (async \/ ~flushing)
              /\ q' = Append(q, f) /\ req' = [req EXCEPT ![f] = "F"]
              /\ resumed' = [resumed EXCEPT ![f] = FALSE]
              /\ Release(f, "fz_wait") /\ UNCHANGED <<flushing, dirty, errLeft>>
  /\ UNCHANGED <<vpid, reqf, promoter, hold, want, rq, cnd, lw, ehg, wi, budget, toLeft,
                 wrongUse, spin, doubleLock, healFired, negFcnt, valid, envLeft, ioErr, pfPend>>

\* the write I/O ran without the BCB mutex; relock, then pgbuf_bcb_mark_was_flushed or,
\* on an I/O error, pgbuf_bcb_mark_was_not_flushed (DIRTY back), and wake the FLUSH waiters
FlDone(p) ==
  /\ pc[p] = "fl_done"
  /\ flushing' = FALSE
  /\ dirty' = (dirty \/ ioErr[p])
  /\ IF ioErr[p] /\ Mutant = "flerr_no_wake"
       THEN UNCHANGED <<q, resumed, word>>
       ELSE WakeFlushWaiters(Mutant = "flush_wake_no_clear")
  /\ ioErr' = [ioErr EXCEPT ![p] = FALSE]
  /\ Release(p, IF p \in Flushers THEN "fz_next" ELSE "idle")
  /\ UNCHANGED <<vpid, req, reqf, promoter, hold, want, rq, cnd, lw, ehg, wi, budget, toLeft,
                 async, wrongUse, spin, doubleLock, healFired, negFcnt,
                 valid, errLeft, envLeft, pfPend>>

\* the write I/O: it succeeds, fails (fileio_write / dwb_add_page error), or, for the
\* flush daemon under victim pressure, succeeds and hands the BCB to the post-flush
\* daemon without relocking it (pgbuf_Pool.flushed_bcbs->produce)
FlIo(p) ==
  /\ pc[p] = "fl_io"
  /\ \/ /\ Go(p, "fl_relock") /\ UNCHANGED <<ioErr, errLeft, pfPend>>
     \/ /\ errLeft > 0 /\ errLeft' = errLeft - 1
        /\ ioErr' = [ioErr EXCEPT ![p] = TRUE] /\ Go(p, "fl_relock") /\ UNCHANGED pfPend
     \/ /\ p \in Daemons /\ ~pfPend /\ pfPend' = TRUE
        /\ Go(p, "fz_next") /\ UNCHANGED <<ioErr, errLeft>>
  /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt, valid, envLeft>>

(* pgbuf_assign_flushed_pages (post-flush daemon) under the BCB mutex: maybe assign
   the BCB as a direct victim (it then leaves the hash chain when the waiting thread
   claims it, MFix), pgbuf_bcb_mark_was_flushed, pgbuf_wake_flush_waiters *)
PostFlush ==
  /\ pfPend /\ mtx = None
  /\ pfPend' = FALSE /\ flushing' = FALSE
  /\ WakeFlushWaiters(Mutant = "flush_wake_no_clear")
  /\ UNCHANGED <<mtx, vpid, req, reqf, promoter, hold, want, rq, cnd, lw, ehg, wi, budget, toLeft,
                 dirty, async, pc, wrongUse, spin, doubleLock, healFired, negFcnt,
                 valid, errLeft, envLeft, ioErr>>

(* page invalidation under the BCB mutex: pgbuf_invalidate (after the last unfix,
   fcnt == 0 and not pgbuf_bcb_avoid_victim), pgbuf_invalidate_all (after a flush),
   pgbuf_copy_temp_page_to_area_and_discard (not fixed by any, not flushing, no async
   request; a dirty page is discarded); pgbuf_invalidate_bcb removes the BCB from the
   hash chain into the invalid list *)
Inval ==
  /\ envLeft > 0 /\ mtx = None /\ valid
  /\ word.f = 0 /\ ~flushing /\ ~async
  /\ (q = <<>> \/ ~dirty)   \* discard: not fixed by any (no waiter); pgbuf_invalidate: not dirty
  /\ envLeft' = envLeft - 1 /\ valid' = FALSE /\ dirty' = FALSE
  /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, flushing, async, pc,
                 wrongUse, spin, doubleLock, healFired, negFcnt, errLeft, ioErr, pfPend>>

\* fault: the FLUSH waiter is interrupted (pgbuf_block_bcb, resume_status not RESUMED)
FzIntr_(f) == /\ pc[f] = "fz_wait" /\ ~resumed[f] /\ toLeft > 0
             /\ toLeft' = toLeft - 1 /\ Go(f, "fz_ilock")
             /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                            lw, ehg, wi, budget, dirty, flushing, async,
                            wrongUse, spin, doubleLock, healFired, negFcnt>>

\* under the BCB mutex: remove itself and reconcile waiter_exists; already woken: nothing
FzIrm_(f) ==
  /\ pc[f] = "fz_irm"
  /\ IF f \in Range(q)
       THEN LET q2 == RemoveAll(q, f) IN
            /\ q' = q2
            /\ word' = IF Mutant # "flush_intr_no_clear"
                           /\ ~(\E i \in 1..Len(q2) : req[q2[i]] \in {"R", "W"})
                          THEN [word EXCEPT !.w = FALSE] ELSE word
       ELSE UNCHANGED <<q, word>>
  /\ Release(f, "fz_next")
  /\ UNCHANGED <<vpid, req, reqf, resumed, promoter, hold, want, rq, cnd,
                 lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                 wrongUse, spin, doubleLock, healFired, negFcnt>>

FzWait_(f) == /\ pc[f] = "fz_wait" /\ resumed[f] /\ Go(f, "fz_next")
             /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                            lw, ehg, wi, budget, toLeft, dirty, flushing, async,
                            wrongUse, spin, doubleLock, healFired, negFcnt>>

FzNext_(f) == /\ pc[f] = "fz_next"
             /\ budget' = [budget EXCEPT ![f] = @ - 1]
             /\ Go(f, IF budget[f] > 1 THEN "fz_lock" ELSE "Done")
             /\ UNCHANGED <<word, mtx, vpid, q, req, reqf, resumed, promoter, hold, want, rq, cnd,
                            lw, ehg, wi, toLeft, dirty, flushing, async,
                            wrongUse, spin, doubleLock, healFired, negFcnt>>

-----------------------------------------------------------------------------
\* the actions that leave the extra variables alone, each kept under its own name
\* so TLC's coverage reports every one of them
Begin(t) == Begin_(t) /\ UNCHANGED extra
Finish(t) == Finish_(t) /\ UNCHANGED extra
LfLoad(t) == LfLoad_(t) /\ UNCHANGED extra
LfVpid(t) == LfVpid_(t) /\ UNCHANGED extra
LfCas(t) == LfCas_(t) /\ UNCHANGED extra
LfRecheck(t) == LfRecheck_(t) /\ UNCHANGED extra
Use(t) == Use_(t) /\ UNCHANGED extra
PrFix(t) == PrFix_(t) /\ UNCHANGED extra
Woken(t) == Woken_(t) /\ UNCHANGED extra
ToChk(t) == ToChk_(t) /\ UNCHANGED extra
ToSet(t) == ToSet_(t) /\ UNCHANGED extra
ToRetry(t) == ToRetry_(t) /\ UNCHANGED extra
Eh(t) == Eh_(t) /\ UNCHANGED extra
EhLoop(t) == EhLoop_(t) /\ UNCHANGED extra
EhLk(t) == EhLk_(t) /\ UNCHANGED extra
Unfix(t) == Unfix_(t) /\ UNCHANGED extra
UfUnl(t) == UfUnl_(t) /\ UNCHANGED extra
Wk(t) == Wk_(t) /\ UNCHANGED extra
WkCas(t) == WkCas_(t) /\ UNCHANGED extra
Timeout(t) == Timeout_(t) /\ UNCHANGED extra
TimedOut(t) == TimedOut_(t) /\ UNCHANGED extra
FzIrm(f) == FzIrm_(f) /\ UNCHANGED extra
FzWait(f) == FzWait_(f) /\ UNCHANGED extra
FzNext(f) == FzNext_(f) /\ UNCHANGED extra
FzIntr(f) == FzIntr_(f) /\ UNCHANGED extra
Lock(p, from, to) == Lock_(p, from, to) /\ UNCHANGED extra

ThreadStep(t) ==
  \/ Begin(t) \/ Finish(t) \/ LfLoad(t) \/ LfVpid(t) \/ LfCas(t) \/ LfRecheck(t) \/ Use(t)
  \/ Lock(t, "m_lock", "m_fix") \/ MFix(t) \/ Lock(t, "pr_lock", "pr_fix") \/ PrFix(t)
  \/ Woken(t) \/ ToChk(t) \/ ToSet(t) \/ ToRetry(t)
  \/ Lock(t, "to_lock", "eh") \/ Eh(t) \/ EhLoop(t) \/ EhLk(t)
  \/ Unfix(t) \/ Lock(t, "uf_lock", "uf_unl") \/ UfUnl(t) \/ Wk(t) \/ WkCas(t) \/ UfAsync(t)
  \/ FlIo(t) \/ Lock(t, "fl_relock", "fl_done") \/ FlDone(t)

FlusherStep(f) ==
  \/ Lock(f, "fz_lock", "fz_dec") \/ FzDec(f) \/ FlIo(f) \/ Lock(f, "fl_relock", "fl_done")
  \/ FlDone(f) \/ Lock(f, "fz_ilock", "fz_irm") \/ FzIrm(f) \/ FzWait(f) \/ FzNext(f)

\* faults: no fairness
Fault == \/ \E t \in Threads : Timeout(t) \/ TimedOut(t)
         \/ \E f \in Flushers : FzIntr(f)
         \/ Inval

Terminating == /\ \A p \in Procs : pc[p] = "Done"
               /\ UNCHANGED vars

Next == \/ \E t \in Threads : ThreadStep(t)
        \/ \E f \in Flushers : FlusherStep(f)
        \/ PostFlush
        \/ Fault
        \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ \A t \in Threads : WF_vars(ThreadStep(t))
        /\ \A f \in Flushers : WF_vars(FlusherStep(f))
        /\ WF_vars(PostFlush)

-----------------------------------------------------------------------------
(* properties *)
\* fixes a thread holds or has been handed: a woken waiter, an unfix between
\* its holder decrement and its CAS
\* H2's handler adds the head waiter's count before it re-checks the waiter: that
\* count is in flight until eh_lk hands it over or (the hole) drops it
InFlight(t) == \E u \in Threads : pc[u] = "eh_lk" /\ ehg[u] /\ q # <<>> /\ Head(q) = t
Granted(t) == hold[t] + (IF pc[t] \in {"uf_lock", "uf_unl"} THEN 1 ELSE 0)
                      + (IF pc[t] \in {"wait", "to_chk", "to_set", "to_retry"} /\ resumed[t]
                           THEN reqf[t] ELSE 0)
Counted(t) == Granted(t) + (IF pc[t] = "wait" /\ ~resumed[t] /\ InFlight(t) THEN reqf[t] ELSE 0)
RECURSIVE SumOver(_)
SumOver(S) == IF S = {} THEN 0 ELSE LET x == CHOOSE x \in S : TRUE IN Counted(x) + SumOver(S \ {x})

\* C1: fcnt counts exactly the fixes threads hold, and is zero exactly when idle
FcntExact == /\ word.f = SumOver(Threads)
             /\ (word.m = "N") <=> (word.f = 0)
             /\ ~negFcnt
\* C3: pgbuf_fix returns the page it was asked for
SamePage == ~wrongUse
\* C5: the mutex holder never spins on the idle grant, and the heal never fires
NoSpin == ~spin /\ ~healFired
\* C6: the waker never re-locks an entry it holds
NoDoubleLock == ~doubleLock
\* C7: an idle latch with a free mutex has no reader or writer waiting
NoStrandedWaiter == (mtx = None /\ word.m = "N") => ~RWWaiting

\* C2, C4 through the abstract latch
Holders == {t \in Threads : Granted(t) > 0}
WaitSet(m) == {t \in Threads : t \in Range(q) /\ req[t] = m}
PL == INSTANCE PageLatch WITH T <- Threads, mode <- word.m, holders <- Holders,
                              bit <- word.w, QR <- WaitSet("R"), QW <- WaitSet("W"), page <- vpid
Refines == PL!Spec

\* C7 liveness
AllDone == <>(\A p \in Procs : pc[p] = "Done")

\* witnesses: outcomes that must be reachable
NotWokenFromQueue == ~(\E t \in Threads : pc[t] = "wait" /\ resumed[t] /\ reqf[t] > 0)
NotTimedOutGaveUp == ~(\E t \in Threads : pc[t] = "eh")
NotRecheckMiss == ~(\E t \in Threads : pc[t] = "lf_recheck" /\ vpid # want[t])
NotFlushWaitAtIdle == ~(word.m = "N" /\ \E f \in Flushers : f \in Range(q) /\ ~resumed[f])
NotPromotedByWait == ~(\E t \in Threads : promoter[t] /\ resumed[t])
NotLockFreeShared == ~(\E t \in Threads : pc[t] = "use" /\ word.m = "R" /\ word.f > 1)
NotWaitOnHandoff == ~(pfPend /\ \E f \in Flushers : f \in Range(q) /\ req[f] = "F")
NotIoErrDone == ~(\E p \in Procs : pc[p] = "fl_done" /\ ioErr[p])
NotReclaimedAfterInval == ~(\E t \in Threads : pc[t] = "use" /\ envLeft < MaxEnv /\ valid)
NotFlushIntrRemoved == ~(\E f \in Flushers : pc[f] = "fz_irm" /\ f \in Range(q))

TypeOK == /\ word.m \in {"N", "R", "W"} /\ word.w \in BOOLEAN /\ word.f \in Int
          /\ mtx \in Procs \cup {None} /\ vpid \in Pages /\ valid \in BOOLEAN
=============================================================================
