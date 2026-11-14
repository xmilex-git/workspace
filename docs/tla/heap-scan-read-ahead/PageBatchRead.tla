--------------------------- MODULE PageBatchRead ---------------------------
(***************************************************************************)
(* Reading a run of pages into the page buffer with one read (CBRD-28043). *)
(*                                                                         *)
(* A sector-based heap scan that is about to fix a page which is not in    *)
(* the buffer loads the run of listed pages that follows it in the sector  *)
(* (D18).  The batch reader marks each page of the run "being read" (the   *)
(* buffer lock of pgbuf_lock_page) without waiting: a page that is in the  *)
(* buffer, or that another thread is reading, ends the run.  It then takes *)
(* one BCB per marked page (a shortage shortens the run and unmarks the    *)
(* rest), looks every page up in the double write buffer, reads the pages  *)
(* the double write buffer does not hold from the volume, and puts each    *)
(* page into the hash chain, unmarks it and wakes the threads waiting for  *)
(* it.  It leaves the pages unfixed; the scan fixes them one at a time as  *)
(* before.                                                                 *)
(*                                                                         *)
(* Beside it a single-page fixer runs today's miss path (mark or wait,     *)
(* one BCB, double write buffer, read, insert, unmark), and the            *)
(* environment modifies buffered pages, flushes them into the double write *)
(* buffer, writes the double write buffer to the volume, removes its       *)
(* slots, and evicts clean pages.                                          *)
(*                                                                         *)
(* Claims (MAP.md): C6 a page in the buffer holds the page's latest        *)
(* content; C7 a page is never marked or loaded while it is in the buffer  *)
(* (one BCB per page); C8 a reader that ended holds no mark and no BCB;    *)
(* C9 every reader and fixer ends (no lost wakeup, no deadlock).           *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS N,         \* pages 1..N, contiguous in one sector
          MaxVer,    \* a page's content versions 1..MaxVer
          Bcbs,      \* BCBs of the buffer
          MaxBatch,  \* pages of one batch at most
          MaxFix,    \* fixes of the single-page fixer
          MaxErrors, \* read errors in a run
          Mutant     \* "none" or one wrong variant below

\* Mutant: "no_lock" | "lock_over_buffered" | "dwb_after_read" | "read_over_dwb" | "short_keeps_lock"
\*         | "error_keeps_lock" | "error_keeps_bcb" | "no_wake"

\* apalache-type: N Int
\* apalache-type: MaxVer Int
\* apalache-type: Bcbs Int
\* apalache-type: MaxBatch Int
\* apalache-type: MaxFix Int
\* apalache-type: MaxErrors Int
\* apalache-type: Mutant Str
\* apalache-type: ver Int -> Int
\* apalache-type: disk Int -> Int
\* apalache-type: dwb Int -> Int
\* apalache-type: buf Int -> Int
\* apalache-type: dirty Int -> Bool
\* apalache-type: lock Int -> Int
\* apalache-type: wait Int
\* apalache-type: woken Bool
\* apalache-type: nfree Int
\* apalache-type: pc Int -> Str
\* apalache-type: mine Int -> Set(Int)
\* apalache-type: got Int -> Set(Int)
\* apalache-type: chk Int -> Set(Int)
\* apalache-type: rd Int -> Set(Int)
\* apalache-type: cont Int -> (Int -> Int)
\* apalache-type: cursor Int -> Int
\* apalache-type: fixes Int
\* apalache-type: errs Int
\* apalache-type: stale Bool
\* apalache-type: inst Int -> Int
\* apalache-type: fromDwb Bool
\* apalache-type: shrunk Bool
\* apalache-type: wokeAfter Bool
\* apalache-type: cutLocked Bool
\* apalache-type: dropped Bool
\* apalache-type: errored Bool

CInit ==
  /\ N = 3
  /\ MaxVer = 2
  /\ Bcbs = 3
  /\ MaxBatch = 3
  /\ MaxFix \in Nat
  /\ MaxErrors \in Nat
  /\ Mutant = "none"

VARIABLES ver,       \* page -> its latest content version
          disk,      \* page -> the version on the volume
          dwb,       \* page -> the version in the double write buffer (0 = no slot)
          buf,       \* page -> the version in the page buffer (0 = not in the buffer)
          dirty,     \* page -> the buffered copy is newer than the double write buffer and the volume
          lock,      \* page -> the thread reading it (0 = none): the buffer lock
          wait,      \* the page the fixer waits for (0 = none)
          woken,     \* the fixer was woken
          nfree,     \* BCBs nobody holds
          pc,        \* thread -> its step
          mine,      \* thread -> pages it marked
          got,       \* thread -> pages it holds a BCB for
          chk,       \* thread -> pages it looked up in the double write buffer
          rd,        \* thread -> pages it read from the volume
          cont,      \* thread -> page -> the version in its BCB (0 = nothing yet)
          cursor,    \* batch reader -> the next page of its run
          fixes,     \* fixes the fixer finished
          errs,      \* read errors so far
          stale,     \* ghost: a page entered the buffer with a version that is not its latest
          inst,      \* ghost: batch reader -> pages it put into the buffer, counted up to 2
          fromDwb,   \* ghost: a batch page came from the double write buffer
          shrunk,    \* ghost: a batch was shortened by a BCB shortage
          wokeAfter, \* ghost: the fixer waited for a batch page and was woken
          cutLocked, \* ghost: a run ended at a page another thread was reading
          dropped,   \* ghost: a batch page was not put into the buffer (deallocated page)
          errored    \* ghost: a batch ended on a read error

vars == <<ver, disk, dwb, buf, dirty, lock, wait, woken, nfree, pc, mine, got, chk, rd, cont, cursor, fixes, errs,
          stale, inst, fromDwb, shrunk, wokeAfter, cutLocked, dropped, errored>>


P == 1..N
BT == {1, 2}     \* batch readers
F == 3           \* the single-page fixer
T == {1, 2, 3}

NoCont == [p \in P |-> 0]
Latest(p) == IF dwb[p] # 0 THEN dwb[p] ELSE disk[p]

Init ==
  /\ ver = [p \in P |-> 1]
  /\ disk = [p \in P |-> 1]
  /\ dwb = [p \in P |-> 0]
  /\ buf = [p \in P |-> 0]
  /\ dirty = [p \in P |-> FALSE]
  /\ lock = [p \in P |-> 0]
  /\ wait = 0
  /\ woken = FALSE
  /\ nfree = Bcbs
  /\ pc = [t \in T |-> "idle"]
  /\ mine = [t \in T |-> {}]
  /\ got = [t \in T |-> {}]
  /\ chk = [t \in T |-> {}]
  /\ rd = [t \in T |-> {}]
  /\ cont = [t \in T |-> NoCont]
  /\ cursor = [t \in T |-> 0]
  /\ fixes = 0
  /\ errs = 0
  /\ stale = FALSE
  /\ inst = [t \in T |-> 0]
  /\ fromDwb = FALSE
  /\ shrunk = FALSE
  /\ wokeAfter = FALSE
  /\ cutLocked = FALSE
  /\ dropped = FALSE
  /\ errored = FALSE

---------------------------------------------------------------------------
\* The environment: other transactions and the flush threads.

Modify(p) ==
  /\ buf[p] # 0
  /\ ver[p] < MaxVer
  /\ ver' = [ver EXCEPT ![p] = ver[p] + 1]
  /\ buf' = [buf EXCEPT ![p] = ver[p] + 1]
  /\ dirty' = [dirty EXCEPT ![p] = TRUE]
  /\ UNCHANGED <<disk, dwb, lock, wait, woken, nfree, pc, mine, got, chk, rd, cont, cursor, fixes, errs, stale, inst,
                 wokeAfter, fromDwb, shrunk, cutLocked, dropped, errored>>

Flush(p) ==
  /\ buf[p] # 0
  /\ dirty[p]
  /\ dwb' = [dwb EXCEPT ![p] = buf[p]]
  /\ dirty' = [dirty EXCEPT ![p] = FALSE]
  /\ UNCHANGED <<ver, disk, buf, lock, wait, woken, nfree, pc, mine, got, chk, rd, cont, cursor, fixes, errs, stale,
                 inst, wokeAfter, fromDwb, shrunk, cutLocked, dropped, errored>>

DwbWrite(p) ==
  /\ dwb[p] # 0
  /\ disk[p] # dwb[p]
  /\ disk' = [disk EXCEPT ![p] = dwb[p]]
  /\ UNCHANGED <<ver, dwb, buf, dirty, lock, wait, woken, nfree, pc, mine, got, chk, rd, cont, cursor, fixes, errs,
                 stale, inst, wokeAfter, fromDwb, shrunk, cutLocked, dropped, errored>>

DwbRemove(p) ==
  /\ dwb[p] # 0
  /\ disk[p] = dwb[p]
  /\ dwb' = [dwb EXCEPT ![p] = 0]
  /\ UNCHANGED <<ver, disk, buf, dirty, lock, wait, woken, nfree, pc, mine, got, chk, rd, cont, cursor, fixes, errs,
                 stale, inst, wokeAfter, fromDwb, shrunk, cutLocked, dropped, errored>>

Evict(p) ==
  /\ buf[p] # 0
  /\ ~dirty[p]
  /\ buf' = [buf EXCEPT ![p] = 0]
  /\ nfree' = nfree + 1
  /\ UNCHANGED <<ver, disk, dwb, dirty, lock, wait, woken, pc, mine, got, chk, rd, cont, cursor, fixes, errs, stale, inst, wokeAfter,
                 fromDwb, shrunk, cutLocked, dropped, errored>>

Env == \E p \in P : Modify(p) \/ Flush(p) \/ DwbWrite(p) \/ DwbRemove(p) \/ Evict(p)

---------------------------------------------------------------------------
\* Unmarking the pages S of thread t wakes the fixer when it waits for one of them.

LockAfter(S, t) == [p \in P |-> IF p \in S /\ lock[p] = t THEN 0 ELSE lock[p]]
Wakes(S, t) == wait \in S /\ lock[wait] = t /\ Mutant # "no_wake"

\* The step after the BCBs are taken, after the double write buffer lookups, after the reads.
AfterAlloc == IF Mutant = "dwb_after_read" THEN "read" ELSE "dwb"
AfterDwb == IF Mutant = "dwb_after_read" THEN "inst" ELSE "read"
AfterRead == IF Mutant = "dwb_after_read" THEN "dwb" ELSE "inst"

Reset(t) ==
  /\ mine' = [mine EXCEPT ![t] = {}]
  /\ got' = [got EXCEPT ![t] = {}]
  /\ chk' = [chk EXCEPT ![t] = {}]
  /\ rd' = [rd EXCEPT ![t] = {}]
  /\ cont' = [cont EXCEPT ![t] = NoCont]

---------------------------------------------------------------------------
\* A batch reader.

BStart(t, s) ==
  /\ pc[t] = "idle"
  /\ pc' = [pc EXCEPT ![t] = "lock"]
  /\ cursor' = [cursor EXCEPT ![t] = s]
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, lock, wait, woken, nfree, mine, got, chk, rd, cont, fixes, errs, stale, inst, wokeAfter,
                 fromDwb, shrunk, cutLocked, dropped, errored>>

\* Under the page's hash mutex: mark the page, or end the run here.
CanMark(t, p) ==
  /\ p <= N
  /\ Cardinality(mine[t]) < MaxBatch
  /\ buf[p] = 0 \/ Mutant = "lock_over_buffered"
  /\ lock[p] = 0 \/ Mutant = "no_lock"

BLock(t) ==
  /\ pc[t] = "lock"
  /\ LET p == cursor[t] IN
       IF CanMark(t, p)
       THEN /\ lock' = IF Mutant = "no_lock" THEN lock ELSE [lock EXCEPT ![p] = t]
            /\ mine' = [mine EXCEPT ![t] = mine[t] \cup {p}]
            /\ cursor' = [cursor EXCEPT ![t] = p + 1]
            /\ UNCHANGED <<pc, cutLocked>>
       ELSE /\ pc' = [pc EXCEPT ![t] = IF mine[t] = {} THEN "done" ELSE "alloc"]
            /\ cutLocked' = (cutLocked \/ (p <= N /\ lock[p] # 0 /\ lock[p] # t))
            /\ UNCHANGED <<lock, mine, cursor>>
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, wait, woken, nfree, got, chk, rd, cont, fixes, errs, stale, inst, wokeAfter, fromDwb,
                 shrunk, dropped, errored>>

\* One BCB for the lowest marked page that has none.
BAlloc(t) ==
  /\ pc[t] = "alloc"
  /\ nfree > 0
  /\ \E p \in mine[t] \ got[t] :
       /\ \A q \in mine[t] \ got[t] : p <= q
       /\ got' = [got EXCEPT ![t] = got[t] \cup {p}]
       /\ pc' = [pc EXCEPT ![t] = IF mine[t] \ got[t] = {p} THEN AfterAlloc ELSE "alloc"]
  /\ nfree' = nfree - 1
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, lock, wait, woken, mine, chk, rd, cont, cursor, fixes, errs, stale, inst, wokeAfter,
                 fromDwb, shrunk, cutLocked, dropped, errored>>

\* No BCB for the next page (no victim, or the wait for one was interrupted): the run ends at the pages that have one.
BAllocShort(t) ==
  /\ pc[t] = "alloc"
  /\ LET tail == mine[t] \ got[t] IN
       /\ tail # {}
       /\ lock' = IF Mutant = "short_keeps_lock" THEN lock ELSE LockAfter(tail, t)
       /\ woken' = (woken \/ (Mutant # "short_keeps_lock" /\ Wakes(tail, t)))
       /\ wokeAfter' = (wokeAfter \/ (Mutant # "short_keeps_lock" /\ Wakes(tail, t)))
       /\ mine' = [mine EXCEPT ![t] = got[t]]
  /\ pc' = [pc EXCEPT ![t] = IF got[t] = {} THEN "done" ELSE AfterAlloc]
  /\ shrunk' = TRUE
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, wait, nfree, got, chk, rd, cont, cursor, fixes, errs, stale, inst, fromDwb, cutLocked,
                 dropped, errored>>

\* A page the double write buffer holds is copied from it.
BDwb(t) ==
  /\ pc[t] = "dwb"
  /\ \E p \in got[t] \ chk[t] :
       /\ chk' = [chk EXCEPT ![t] = chk[t] \cup {p}]
       /\ cont' = IF dwb[p] # 0 THEN [cont EXCEPT ![t][p] = dwb[p]] ELSE cont
       /\ fromDwb' = (fromDwb \/ dwb[p] # 0)
       /\ pc' = [pc EXCEPT ![t] = IF got[t] \ chk[t] = {p} THEN AfterDwb ELSE "dwb"]
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, lock, wait, woken, nfree, mine, got, rd, cursor, fixes, errs, stale, inst, wokeAfter,
                 shrunk, cutLocked, dropped, errored>>

\* The pages the read covers: those the double write buffer did not give.
ToRead(t) == {p \in got[t] \ rd[t] : cont[t][p] = 0 \/ Mutant = "read_over_dwb"}

BRead(t) ==
  /\ pc[t] = "read"
  /\ ToRead(t) # {}
  /\ \E p \in ToRead(t) :
       /\ rd' = [rd EXCEPT ![t] = rd[t] \cup {p}]
       /\ cont' = [cont EXCEPT ![t][p] = disk[p]]
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, lock, wait, woken, nfree, pc, mine, got, chk, cursor, fixes, errs, stale, inst,
                 wokeAfter, fromDwb, shrunk, cutLocked, dropped, errored>>

BReadDone(t) ==
  /\ pc[t] = "read"
  /\ ToRead(t) = {}
  /\ pc' = [pc EXCEPT ![t] = AfterRead]
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, lock, wait, woken, nfree, mine, got, chk, rd, cont, cursor, fixes, errs, stale, inst,
                 wokeAfter, fromDwb, shrunk, cutLocked, dropped, errored>>

\* A read error: every BCB goes back, every page is unmarked.
BReadError(t) ==
  /\ pc[t] = "read"
  /\ errs < MaxErrors
  /\ errs' = errs + 1
  /\ lock' = IF Mutant = "error_keeps_lock" THEN lock ELSE LockAfter(mine[t], t)
  /\ woken' = (woken \/ (Mutant # "error_keeps_lock" /\ Wakes(mine[t], t)))
  /\ wokeAfter' = (wokeAfter \/ (Mutant # "error_keeps_lock" /\ Wakes(mine[t], t)))
  /\ nfree' = IF Mutant = "error_keeps_bcb" THEN nfree ELSE nfree + Cardinality(got[t])
  /\ pc' = [pc EXCEPT ![t] = "done"]
  /\ errored' = TRUE
  /\ Reset(t)
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, wait, cursor, fixes, stale, inst, fromDwb, shrunk, cutLocked, dropped>>

\* A page enters the hash chain (or its BCB goes back: a deallocated page), is unmarked, and its waiters wake.
BInstall(t, keep) ==
  /\ pc[t] = "inst"
  /\ \E p \in got[t] :
       LET enter == keep /\ (Mutant # "no_lock" \/ buf[p] = 0) IN
       /\ buf' = IF enter THEN [buf EXCEPT ![p] = cont[t][p]] ELSE buf
       /\ dirty' = IF enter THEN [dirty EXCEPT ![p] = FALSE] ELSE dirty
       /\ stale' = (stale \/ (enter /\ cont[t][p] # ver[p]))
       /\ nfree' = IF enter THEN nfree ELSE nfree + 1
       /\ inst' = [inst EXCEPT ![t] = IF enter /\ inst[t] < 2 THEN inst[t] + 1 ELSE inst[t]]
       /\ dropped' = (dropped \/ ~keep)
       /\ lock' = LockAfter({p}, t)
       /\ woken' = (woken \/ Wakes({p}, t))
       /\ wokeAfter' = (wokeAfter \/ Wakes({p}, t))
       /\ IF got[t] = {p}
          THEN /\ pc' = [pc EXCEPT ![t] = "done"]
               /\ Reset(t)
          ELSE /\ got' = [got EXCEPT ![t] = got[t] \ {p}]
               /\ mine' = [mine EXCEPT ![t] = mine[t] \ {p}]
               /\ chk' = [chk EXCEPT ![t] = chk[t] \ {p}]
               /\ rd' = [rd EXCEPT ![t] = rd[t] \ {p}]
               /\ cont' = [cont EXCEPT ![t][p] = 0]
               /\ UNCHANGED pc
  /\ UNCHANGED <<ver, disk, dwb, wait, cursor, fixes, errs, fromDwb, shrunk, cutLocked, errored>>

Batch(t) ==
  \/ \E s \in P : BStart(t, s)
  \/ BLock(t) \/ BAlloc(t) \/ BAllocShort(t) \/ BDwb(t) \/ BRead(t) \/ BReadDone(t) \/ BReadError(t)
  \/ \E keep \in BOOLEAN : BInstall(t, keep)

---------------------------------------------------------------------------
\* The single-page fixer: today's miss path.

FLookup(p) ==
  /\ pc[F] = "idle"
  /\ fixes < MaxFix
  /\ IF buf[p] # 0
     THEN /\ fixes' = fixes + 1
          /\ UNCHANGED <<lock, wait, pc, mine>>
     ELSE IF lock[p] # 0
     THEN /\ wait' = p
          /\ pc' = [pc EXCEPT ![F] = "wait"]
          /\ UNCHANGED <<lock, mine, fixes>>
     ELSE /\ lock' = [lock EXCEPT ![p] = F]
          /\ mine' = [mine EXCEPT ![F] = {p}]
          /\ pc' = [pc EXCEPT ![F] = "alloc"]
          /\ UNCHANGED <<wait, fixes>>
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, woken, nfree, got, chk, rd, cont, cursor, errs, stale, inst, wokeAfter, fromDwb, shrunk, cutLocked, dropped, errored>>

FWake ==
  /\ pc[F] = "wait"
  /\ woken
  /\ woken' = FALSE
  /\ wait' = 0
  /\ pc' = [pc EXCEPT ![F] = "idle"]
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, lock, nfree, mine, got, chk, rd, cont, cursor, fixes, errs, stale, inst, wokeAfter,
                 fromDwb, shrunk, cutLocked, dropped, errored>>

FAlloc ==
  /\ pc[F] = "alloc"
  /\ nfree > 0
  /\ nfree' = nfree - 1
  /\ got' = [got EXCEPT ![F] = mine[F]]
  /\ pc' = [pc EXCEPT ![F] = "dwb"]
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, lock, wait, woken, mine, chk, rd, cont, cursor, fixes, errs, stale, inst, wokeAfter,
                 fromDwb, shrunk, cutLocked, dropped, errored>>

FAllocFail ==
  /\ pc[F] = "alloc"
  /\ lock' = LockAfter(mine[F], F)
  /\ mine' = [mine EXCEPT ![F] = {}]
  /\ fixes' = fixes + 1
  /\ pc' = [pc EXCEPT ![F] = "idle"]
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, wait, woken, nfree, got, chk, rd, cont, cursor, errs, stale, inst, wokeAfter, fromDwb, shrunk, cutLocked, dropped, errored>>

FDwb ==
  /\ pc[F] = "dwb"
  /\ \E p \in got[F] :
       /\ chk' = [chk EXCEPT ![F] = {p}]
       /\ cont' = IF dwb[p] # 0 THEN [cont EXCEPT ![F][p] = dwb[p]] ELSE cont
       /\ pc' = [pc EXCEPT ![F] = IF dwb[p] # 0 THEN "inst" ELSE "read"]
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, lock, wait, woken, nfree, mine, got, rd, cursor, fixes, errs, stale, inst, wokeAfter,
                 fromDwb, shrunk, cutLocked, dropped, errored>>

FRead ==
  /\ pc[F] = "read"
  /\ \E p \in got[F] :
       /\ rd' = [rd EXCEPT ![F] = {p}]
       /\ cont' = [cont EXCEPT ![F][p] = disk[p]]
  /\ pc' = [pc EXCEPT ![F] = "inst"]
  /\ UNCHANGED <<ver, disk, dwb, dirty, buf, lock, wait, woken, nfree, mine, got, chk, cursor, fixes, errs, stale, inst, wokeAfter,
                 fromDwb, shrunk, cutLocked, dropped, errored>>

FInstall ==
  /\ pc[F] = "inst"
  /\ \E p \in got[F] :
       /\ buf' = [buf EXCEPT ![p] = cont[F][p]]
       /\ dirty' = [dirty EXCEPT ![p] = FALSE]
       /\ stale' = (stale \/ cont[F][p] # ver[p])
       /\ lock' = LockAfter({p}, F)
  /\ fixes' = fixes + 1
  /\ pc' = [pc EXCEPT ![F] = "idle"]
  /\ Reset(F)
  /\ UNCHANGED <<ver, disk, dwb, wait, woken, nfree, cursor, errs, inst, wokeAfter, fromDwb, shrunk, cutLocked, dropped, errored>>

Fixer == (\E p \in P : FLookup(p)) \/ FWake \/ FAlloc \/ FAllocFail \/ FDwb \/ FRead \/ FInstall

---------------------------------------------------------------------------

AllDone == (\A t \in BT : pc[t] = "done") /\ pc[F] = "idle" /\ fixes = MaxFix

Idle == AllDone /\ UNCHANGED vars

Threads == (\E t \in BT : Batch(t)) \/ Fixer

Next == Env \/ Threads \/ Idle

Spec == Init /\ [][Next]_vars /\ WF_vars(Threads)

---------------------------------------------------------------------------
\* Properties.

Held == UNION {got[t] : t \in T}

TypeOK ==
  /\ ver \in [P -> 1..MaxVer]
  /\ disk \in [P -> 1..MaxVer]
  /\ dwb \in [P -> 0..MaxVer]
  /\ buf \in [P -> 0..MaxVer]
  /\ dirty \in [P -> BOOLEAN]
  /\ lock \in [P -> 0..3]
  /\ wait \in 0..N
  /\ woken \in BOOLEAN
  /\ nfree \in 0..Bcbs
  /\ pc \in [T -> {"idle", "lock", "alloc", "dwb", "read", "inst", "wait", "done"}]
  /\ mine \in [T -> SUBSET P]
  /\ got \in [T -> SUBSET P]
  /\ chk \in [T -> SUBSET P]
  /\ rd \in [T -> SUBSET P]
  /\ cont \in [T -> [P -> 0..MaxVer]]
  /\ cursor \in [T -> 0..(N + 1)]
  /\ fixes \in 0..MaxFix
  /\ errs \in 0..MaxErrors
  /\ stale \in BOOLEAN
  /\ inst \in [T -> 0..2]
  /\ fromDwb \in BOOLEAN
  /\ shrunk \in BOOLEAN
  /\ wokeAfter \in BOOLEAN
  /\ cutLocked \in BOOLEAN
  /\ dropped \in BOOLEAN
  /\ errored \in BOOLEAN

\* C6: a page in the buffer holds the page's latest content.
NoStale == ~stale /\ \A p \in P : buf[p] # 0 => buf[p] = ver[p]

\* C7: a page being read is not in the buffer (so it gets one BCB).
OneCopy == \A p \in P : lock[p] # 0 => buf[p] = 0

\* C8: a mark belongs to a thread that is still reading that page, and every BCB is accounted for.
NoLockLeft == \A p \in P : lock[p] # 0 => (p \in mine[lock[p]] /\ pc[lock[p]] \in {"lock", "alloc", "dwb", "read", "inst"})
BcbConserved == nfree + Cardinality({p \in P : buf[p] # 0}) + Cardinality(got[1]) + Cardinality(got[2])
                + Cardinality(got[F]) = Bcbs

\* C9: every reader and the fixer end.
Ends == <>AllDone

\* What the volume and the double write buffer hold for a page that is not dirty in the buffer.
Durable == \A p \in P : (buf[p] = 0 \/ ~dirty[p]) => Latest(p) = ver[p]

\* The reading threads' bookkeeping.
Marks ==
  /\ \A t \in T : \A p \in mine[t] : lock[p] = t
  /\ \A t \in T : got[t] \subseteq mine[t] /\ chk[t] \subseteq got[t] /\ rd[t] \subseteq got[t]
  /\ \A t \in T : pc[t] \in {"idle", "done", "wait"} => (mine[t] = {} /\ got[t] = {} /\ chk[t] = {} /\ rd[t] = {}
                                                        /\ cont[t] = NoCont)
  /\ \A t \in T : pc[t] \in {"dwb", "read", "inst"} => (mine[t] = got[t] /\ got[t] # {})
  /\ \A t \in T : pc[t] = "alloc" => mine[t] # {}
  /\ \A t \in T : pc[t] = "lock" => (got[t] = {} /\ chk[t] = {} /\ rd[t] = {} /\ cont[t] = NoCont)
  /\ \A t \in T : pc[t] \in {"lock", "alloc"} => (chk[t] = {} /\ rd[t] = {} /\ cont[t] = NoCont)
  /\ \A t \in T : pc[t] \in {"read", "inst"} => chk[t] = got[t]
  /\ \A t \in T : pc[t] = "inst" => \A p \in got[t] : cont[t][p] # 0
  /\ \A t \in T : \A p \in P : cont[t][p] # 0 => p \in chk[t]
  /\ \A t \in T : \A p \in rd[t] : cont[t][p] # 0
  /\ \A t \in BT : pc[t] # "wait"
  /\ pc[F] \notin {"lock", "done"}
  /\ Cardinality(mine[F]) <= 1
  /\ pc[F] = "alloc" => got[F] = {}
  /\ pc[F] = "dwb" => chk[F] = {}
  /\ pc[F] = "read" => (rd[F] = {} /\ \A p \in got[F] : cont[F][p] = 0)
  /\ pc[F] \in {"alloc", "dwb", "read", "inst"} => fixes < MaxFix
  /\ \A p \in P : buf[p] = 0 => ~dirty[p]
  /\ \A t \in BT : Cardinality(mine[t]) <= MaxBatch
  /\ \A t \in BT : \A p \in mine[t] : p < cursor[t]
  /\ \A t \in BT : pc[t] \in {"lock", "alloc", "dwb", "read", "inst"} => cursor[t] \in 1..(N + 1)

\* What a reading thread's BCB holds is the page's latest content.
Contents ==
  /\ \A t \in T : \A p \in chk[t] : cont[t][p] = 0 => dwb[p] = 0
  /\ \A t \in T : \A p \in P : cont[t][p] # 0 => cont[t][p] = ver[p]

\* The fixer waits only for a page somebody is reading, or it was woken.
Waits ==
  /\ (wait # 0) = (pc[F] = "wait")
  /\ woken => pc[F] = "wait"
  /\ (pc[F] = "wait" /\ ~woken) => lock[wait] # 0

IndInv ==
  /\ TypeOK
  /\ NoStale
  /\ OneCopy
  /\ NoLockLeft
  /\ BcbConserved
  /\ Durable
  /\ Marks
  /\ Contents
  /\ Waits

\* Witnesses.
NotBatchTwo == \A t \in BT : inst[t] < 2
NotFromDwb == ~(fromDwb /\ \E t \in BT : inst[t] > 0)
NotShrunk == ~(shrunk /\ \E t \in BT : inst[t] > 0)
NotWokeAfter == ~(wokeAfter /\ fixes > 0)
NotCutLocked == ~cutLocked
NotDropped == ~dropped
NotErrored == ~(errored /\ AllDone)
NotAllDone == ~AllDone
=============================================================================
