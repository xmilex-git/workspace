--------------------------- MODULE ReadAheadPool ---------------------------
(***************************************************************************)
(* Where the serial walk's read-ahead gets its threads (workspace #642,    *)
(* D24): one server-wide pool of Slots threads.  A walk that enters a      *)
(* sector asks the pool to read the sectors ahead of it, up to a distance  *)
(* that grows as the walk goes (Ramp).  A request is a copy of the sector  *)
(* (volume, sector, page bitmap): it holds nothing of the walk, so a walk  *)
(* ends without waiting for its requests.  The pool takes a request only   *)
(* while one of its threads is free (try_task): a refused request is not   *)
(* queued, the walk reads that sector itself when it gets there.           *)
(*                                                                         *)
(* A sector is the unit here: PageBatchRead has the run of pages it reads. *)
(* buf[s]: "out" (not in the buffer), "reading" (buffer-locked by a reader *)
(* that never waits), "in".  A walk waits for a sector being read, reads   *)
(* a sector that is out itself, and holds the sector it is in (the page    *)
(* latch) so it is not evicted.  Several walks share the pool and the      *)
(* buffer.  A walk may stop at any time (a LIMIT, an error, an interrupt). *)
(*                                                                         *)
(* Claims (MAP.md): C13 the walks and their requests end; C14 a walk over  *)
(* sectors all in the buffer sends no request; C15 a walk that ends after  *)
(* k sectors has sent at most 2k+1 requests; C16 nothing reads a walk's    *)
(* memory after the walk ended; C17 a walk never waits for a pool thread;  *)
(* C18 a sector read itself after a refusal does not grow the distance.   *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

\* Ramp: "each" the distance doubles at every sector the walk enters; "walked" it doubles when the walk has entered
\* twice the distance; "wait" it doubles after a sector the walk waited for or read itself, and goes down by one at
\* each sector found in the buffer after more than MaxWin such sectors in a row; "wait_capped" is "wait", never
\* longer than the sectors entered.  CountRefused: under the "wait" ramps, a sector the walk read itself because the
\* pool refused it makes the distance grow.
CONSTANTS S,         \* sectors of the table 1..S, in file order
          NW,        \* walks
          Slots,     \* threads of the read-ahead pool
          MaxWin,    \* the longest read-ahead distance, in sectors
          MaxEvict,  \* evictions of the environment
          MaxErr,    \* read errors
          Start,     \* "cold" | "hot" | "any": which sectors are in the buffer at the start
          Ramp,      \* "each" | "walked" | "wait" | "wait_capped" (above)
          HotCheck,  \* the walk does not ask for a sector that is in the buffer
          CountRefused,  \* (above)
          Mutant     \* "none" | "task_reads_scan" | "push_blocks" | "no_ramp" | "no_hot_check" | "err_keeps_lock"

Sec == 1..S
Wk == 1..NW
Sl == 1..Slots

\* apalache-type: S Int
\* apalache-type: NW Int
\* apalache-type: Slots Int
\* apalache-type: MaxWin Int
\* apalache-type: MaxEvict Int
\* apalache-type: MaxErr Int
\* apalache-type: Start Str
\* apalache-type: Ramp Str
\* apalache-type: HotCheck Bool
\* apalache-type: CountRefused Bool
\* apalache-type: Mutant Str
\* apalache-type: buf Int -> Str
\* apalache-type: ldr Int -> Int
\* apalache-type: pos Int -> Int
\* apalache-type: wpc Int -> Str
\* apalache-type: win Int -> Int
\* apalache-type: req Int -> Int
\* apalache-type: tgt Int -> Int
\* apalache-type: nreq Int -> Int
\* apalache-type: tsec Int -> Int
\* apalache-type: town Int -> Int
\* apalache-type: tst Int -> Str
\* apalache-type: evs Int
\* apalache-type: errs Int
\* apalache-type: hot0 Bool
\* apalache-type: uaf Bool
\* apalache-type: used Bool
\* apalache-type: cross Bool
\* apalache-type: stale Bool
\* apalache-type: selfRead Bool
\* apalache-type: refused Bool
\* apalache-type: mcause Int -> Str
\* apalache-type: unreq Int -> Bool
\* apalache-type: cover Int -> Int
\* apalache-type: hits Int -> Int
\* apalache-type: shrunk Bool
\* apalache-type: grewOnRefused Bool

\* The inductive check: the role sets fixed, the integer bounds open (MaxWin up to 16, the code's longest distance).
CInit ==
  /\ S = 3
  /\ NW = 2
  /\ Slots = 2
  /\ MaxWin \in 1..16
  /\ MaxEvict \in Nat
  /\ MaxErr \in Nat
  /\ Start \in {"cold", "hot", "any"}
  /\ Ramp = "wait_capped"
  /\ HotCheck = TRUE
  /\ CountRefused = FALSE
  /\ Mutant = "none"

VARIABLES buf,       \* sector -> "out" | "reading" | "in"
          ldr,       \* sector -> the walk whose request put it into the buffer (0 = none or since read again)
          pos,       \* walk -> the sector it is in (0 = before the first)
          wpc,       \* walk -> "enter" | "req" | "slotwait" | "fix" | "read" | "hold" | "done"
          win,       \* walk -> read-ahead distance
          req,       \* walk -> the last sector it asked for or let pass (sectors up to pos are its own)
          tgt,       \* walk -> the last sector it asks for at this sector
          nreq,      \* walk -> requests it sent (ghost of the cost, C15)
          tsec,      \* slot -> the sector of its request (0 = free)
          town,      \* slot -> the walk that sent it (ghost: the request holds no reference to it)
          tst,       \* slot -> "free" | "new" | "read"
          evs,       \* evictions so far
          errs,      \* read errors so far
          hot0,      \* ghost: every sector was in the buffer at the start
          uaf,       \* ghost: a request read the memory of a walk that had ended
          used,      \* ghost: a walk found a sector a request had put into the buffer
          cross,     \* ghost: ... a request of another walk
          stale,     \* ghost: a request started after its walk had passed its sector
          selfRead,  \* ghost: a walk read a sector itself
          refused,   \* ghost: the pool refused a request (no free thread)
          mcause,    \* walk -> why it missed its sector: "none" | "wait" | "self" | "refused" (read itself after a refusal)
          unreq,     \* walk -> the sector it is in was within its distance but not asked for (the pool refused)
          cover,     \* walk -> the last sector its distance ever reached
          hits,     \* walk -> sectors in a row it found in the buffer (saturates at MaxWin + 1)
          shrunk,   \* ghost: a walk's distance went down
          grewOnRefused  \* ghost: a walk's distance grew after it read itself a sector the pool had refused

\* @type: <<Int -> Int, Int -> Str, Int -> Int, Int -> Int, Int -> Int, Int -> Int, Int -> Str, Int -> Int, Int -> Bool, Int -> Int>>;
walkVars == <<pos, wpc, win, req, tgt, nreq, mcause, hits, unreq, cover>>
\* @type: <<Int -> Int, Int -> Int, Int -> Str>>;
taskVars == <<tsec, town, tst>>
\* @type: <<Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool>>;
ghost == <<hot0, uaf, used, cross, stale, selfRead, refused, shrunk, grewOnRefused>>
\* @type: <<Int -> Str, Int -> Int, <<Int -> Int, Int -> Str, Int -> Int, Int -> Int, Int -> Int, Int -> Int, Int -> Str, Int -> Int, Int -> Bool, Int -> Int>>, <<Int -> Int, Int -> Int, Int -> Str>>, Int, Int, <<Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool>>>>;
vars == <<buf, ldr, walkVars, taskVars, evs, errs, ghost>>

Min(a, b) == IF a < b THEN a ELSE b

StartBuf ==
  IF Start = "cold" THEN {[s \in Sec |-> "out"]}
  ELSE IF Start = "hot" THEN {[s \in Sec |-> "in"]}
  ELSE [Sec -> {"out", "in"}]

Init ==
  /\ buf \in StartBuf
  /\ ldr = [s \in Sec |-> 0]
  /\ pos = [w \in Wk |-> 0]
  /\ wpc = [w \in Wk |-> "enter"]
  /\ win = [w \in Wk |-> 1]
  /\ req = [w \in Wk |-> 0]
  /\ tgt = [w \in Wk |-> 0]
  /\ nreq = [w \in Wk |-> 0]
  /\ tsec = [i \in Sl |-> 0]
  /\ town = [i \in Sl |-> 0]
  /\ tst = [i \in Sl |-> "free"]
  /\ evs = 0
  /\ errs = 0
  /\ hot0 = (\A s \in Sec : buf[s] = "in")
  /\ uaf = FALSE
  /\ used = FALSE
  /\ cross = FALSE
  /\ stale = FALSE
  /\ selfRead = FALSE
  /\ refused = FALSE
  /\ mcause = [w \in Wk |-> "none"]
  /\ unreq = [w \in Wk |-> FALSE]
  /\ cover = [w \in Wk |-> 0]
  /\ hits = [w \in Wk |-> 0]
  /\ shrunk = FALSE
  /\ grewOnRefused = FALSE

---------------------------------------------------------------------------
\* A walk.

\* The distance at the sector s the walk enters, from the distance cur it had, whether it waited at the sector
\* before (m) and how many sectors in a row it found in the buffer (h).
WaitWin(cur, m, h) ==
  IF m THEN Min(MaxWin, 2 * cur) ELSE IF h > MaxWin /\ cur > 1 THEN cur - 1 ELSE cur

NewWin(cur, s, m, h) ==
  IF Mutant = "no_ramp" THEN MaxWin
  ELSE IF Ramp = "each" THEN (IF s = 1 THEN 1 ELSE Min(MaxWin, 2 * cur))
  ELSE IF Ramp = "walked" THEN (IF s >= 2 * cur THEN Min(MaxWin, 2 * cur) ELSE cur)
  ELSE IF Ramp = "wait" THEN WaitWin(cur, m, h)
  ELSE LET ww == WaitWin(cur, m, h) IN Min(ww, s)

\* Enters the next sector (scan_heap_next_listed_page at page offset 0): fixes its distance and what it asks for.
WEnter(w) ==
  /\ wpc[w] = "enter" /\ pos[w] < S
  /\ LET s == pos[w] + 1
         cur == win[w]
         m == mcause[w] \in (IF CountRefused THEN {"wait", "self", "refused"} ELSE {"wait", "self"})
         h == hits[w]
         nw == NewWin(cur, s, m, h)
         last == Min(S, s + nw)
     IN /\ pos' = [pos EXCEPT ![w] = s]
        /\ win' = [win EXCEPT ![w] = nw]
        /\ tgt' = [tgt EXCEPT ![w] = last]
        /\ cover' = [cover EXCEPT ![w] = IF cover[w] < last THEN last ELSE cover[w]]
        /\ unreq' = [unreq EXCEPT ![w] = (req[w] < s /\ cover[w] >= s)]
        /\ req' = [req EXCEPT ![w] = IF req[w] < s THEN s ELSE req[w]]
        /\ wpc' = [wpc EXCEPT ![w] = "req"]
        /\ mcause' = [mcause EXCEPT ![w] = "none"]
        /\ shrunk' = (shrunk \/ nw < cur)
        /\ grewOnRefused' = (grewOnRefused \/ (nw > cur /\ mcause[w] = "refused"))
  /\ UNCHANGED <<buf, ldr, nreq, hits, taskVars, evs, errs, hot0, uaf, used, cross, stale, selfRead, refused>>

FreeSlots == {i \in Sl : tst[i] = "free"}

\* Asks for the next sector: skipped when it is in the buffer, else try_task (one step under the pool's mutex).
WReq(w) ==
  /\ wpc[w] \in {"req", "slotwait"} /\ req[w] < tgt[w]
  /\ LET t == req[w] + 1 IN
     IF HotCheck /\ Mutant # "no_hot_check" /\ buf[t] = "in"
     THEN /\ req' = [req EXCEPT ![w] = t]
          /\ wpc' = [wpc EXCEPT ![w] = "req"]
          /\ UNCHANGED <<buf, ldr, pos, win, tgt, nreq, mcause, hits, unreq, cover, taskVars, evs, errs, ghost>>
     ELSE IF FreeSlots # {}
     THEN \E i \in FreeSlots : (\A k \in FreeSlots : i <= k) /\
          /\ tsec' = [tsec EXCEPT ![i] = t]
          /\ town' = [town EXCEPT ![i] = w]
          /\ tst' = [tst EXCEPT ![i] = "new"]
          /\ nreq' = [nreq EXCEPT ![w] = nreq[w] + 1]
          /\ req' = [req EXCEPT ![w] = t]
          /\ wpc' = [wpc EXCEPT ![w] = "req"]
          /\ UNCHANGED <<buf, ldr, pos, win, tgt, mcause, hits, unreq, cover, evs, errs, ghost>>
     ELSE IF Mutant = "push_blocks"
     THEN /\ wpc[w] = "req"
          /\ wpc' = [wpc EXCEPT ![w] = "slotwait"]
          /\ UNCHANGED <<buf, ldr, pos, win, req, tgt, nreq, mcause, hits, unreq, cover, taskVars, evs, errs, ghost>>
     ELSE /\ wpc' = [wpc EXCEPT ![w] = "fix"]
          /\ refused' = TRUE
          /\ UNCHANGED <<buf, ldr, pos, win, req, tgt, nreq, mcause, hits, unreq, cover, taskVars, evs, errs, hot0, uaf, used, cross, stale, selfRead, shrunk, grewOnRefused>>

WReqEnd(w) ==
  /\ wpc[w] = "req" /\ req[w] >= tgt[w]
  /\ wpc' = [wpc EXCEPT ![w] = "fix"]
  /\ UNCHANGED <<buf, ldr, pos, win, req, tgt, nreq, mcause, hits, unreq, cover, taskVars, evs, errs, ghost>>

\* Fixes its sector: in the buffer, or read by the walk itself (D18's batch read); waits while another reads it.
WFix(w) ==
  /\ wpc[w] = "fix"
  /\ LET s == pos[w] IN
     \/ /\ buf[s] = "in"
        /\ wpc' = [wpc EXCEPT ![w] = "hold"]
        /\ used' = (used \/ ldr[s] # 0)
        /\ cross' = (cross \/ (ldr[s] # 0 /\ ldr[s] # w))
        /\ hits' = [hits EXCEPT ![w] = IF mcause[w] # "none" THEN 0 ELSE Min(MaxWin + 1, hits[w] + 1)]
        /\ UNCHANGED <<buf, ldr, pos, win, req, tgt, nreq, mcause, unreq, cover, taskVars, evs, errs, hot0, uaf, stale, selfRead, refused, shrunk, grewOnRefused>>
     \/ /\ buf[s] = "out"
        /\ buf' = [buf EXCEPT ![s] = "reading"]
        /\ wpc' = [wpc EXCEPT ![w] = "read"]
        /\ selfRead' = TRUE
        /\ mcause' = [mcause EXCEPT ![w] = IF mcause[w] = "wait" THEN "wait" ELSE IF unreq[w] THEN "refused" ELSE "self"]
        /\ hits' = [hits EXCEPT ![w] = 0]
        /\ UNCHANGED <<ldr, pos, win, req, tgt, nreq, unreq, cover, taskVars, evs, errs, hot0, uaf, used, cross, stale, refused, shrunk, grewOnRefused>>

\* Finds its sector being read by another thread: it will wait (pgbuf_lock_page); the wait is the signal.
WWait(w) ==
  /\ wpc[w] = "fix" /\ buf[pos[w]] = "reading" /\ mcause[w] = "none"
  /\ mcause' = [mcause EXCEPT ![w] = "wait"]
  /\ hits' = [hits EXCEPT ![w] = 0]
  /\ UNCHANGED <<buf, ldr, pos, wpc, win, req, tgt, nreq, unreq, cover, taskVars, evs, errs, ghost>>

WReadDone(w) ==
  /\ wpc[w] = "read"
  /\ buf' = [buf EXCEPT ![pos[w]] = "in"]
  /\ ldr' = [ldr EXCEPT ![pos[w]] = 0]
  /\ wpc' = [wpc EXCEPT ![w] = "hold"]
  /\ UNCHANGED <<pos, win, req, tgt, nreq, mcause, hits, unreq, cover, taskVars, evs, errs, ghost>>

\* The walk's own read fails: the scan ends with the error.
WReadErr(w) ==
  /\ wpc[w] = "read" /\ errs < MaxErr
  /\ buf' = [buf EXCEPT ![pos[w]] = "out"]
  /\ wpc' = [wpc EXCEPT ![w] = "done"]
  /\ errs' = errs + 1
  /\ UNCHANGED <<ldr, pos, win, req, tgt, nreq, mcause, hits, unreq, cover, taskVars, evs, ghost>>

\* Lets its sector go: the next one, or the end of the bitmap.
WNext(w) ==
  /\ wpc[w] = "hold"
  /\ wpc' = [wpc EXCEPT ![w] = IF pos[w] < S THEN "enter" ELSE "done"]
  /\ UNCHANGED <<buf, ldr, pos, win, req, tgt, nreq, mcause, hits, unreq, cover, taskVars, evs, errs, ghost>>

\* Stops before the end (a LIMIT, an error, an interrupt); its memory is freed with nothing to wait for.
WStop(w) ==
  /\ wpc[w] \in {"enter", "req", "fix", "hold"}
  /\ wpc' = [wpc EXCEPT ![w] = "done"]
  /\ UNCHANGED <<buf, ldr, pos, win, req, tgt, nreq, mcause, hits, unreq, cover, taskVars, evs, errs, ghost>>

WalkProg(w) == WEnter(w) \/ WReq(w) \/ WReqEnd(w) \/ WFix(w) \/ WWait(w) \/ WReadDone(w) \/ WReadErr(w) \/ WNext(w)

---------------------------------------------------------------------------
\* A pool thread running a request.

\* Buffer-locks the sector when it is out, else ends (a run ends at a page in the buffer or being read).
TLock(i) ==
  /\ tst[i] = "new"
  /\ LET t == tsec[i]
         o == town[i]
     IN /\ uaf' = (uaf \/ (Mutant = "task_reads_scan" /\ wpc[o] = "done"))
        /\ stale' = (stale \/ pos[o] >= t)
        /\ IF buf[t] = "out"
           THEN /\ buf' = [buf EXCEPT ![t] = "reading"]
                /\ tst' = [tst EXCEPT ![i] = "read"]
                /\ UNCHANGED <<tsec, town>>
           ELSE /\ tst' = [tst EXCEPT ![i] = "free"]
                /\ tsec' = [tsec EXCEPT ![i] = 0]
                /\ town' = [town EXCEPT ![i] = 0]
                /\ UNCHANGED buf
  /\ UNCHANGED <<ldr, walkVars, evs, errs, hot0, used, cross, selfRead, refused, shrunk, grewOnRefused>>

TDone(i) ==
  /\ tst[i] = "read"
  /\ buf' = [buf EXCEPT ![tsec[i]] = "in"]
  /\ ldr' = [ldr EXCEPT ![tsec[i]] = town[i]]
  /\ tst' = [tst EXCEPT ![i] = "free"]
  /\ tsec' = [tsec EXCEPT ![i] = 0]
  /\ town' = [town EXCEPT ![i] = 0]
  /\ UNCHANGED <<walkVars, evs, errs, ghost>>

\* The read fails: the buffer lock goes (C8), nothing is reported; the walk reads the sector itself.
TErr(i) ==
  /\ tst[i] = "read" /\ errs < MaxErr
  /\ buf' = [buf EXCEPT ![tsec[i]] = IF Mutant = "err_keeps_lock" THEN "reading" ELSE "out"]
  /\ tst' = [tst EXCEPT ![i] = "free"]
  /\ tsec' = [tsec EXCEPT ![i] = 0]
  /\ town' = [town EXCEPT ![i] = 0]
  /\ errs' = errs + 1
  /\ UNCHANGED <<ldr, walkVars, evs, ghost>>

TaskProg(i) == TLock(i) \/ TDone(i) \/ TErr(i)

---------------------------------------------------------------------------
\* The environment: a sector no walk holds is evicted.

Evict(s) ==
  /\ buf[s] = "in" /\ evs < MaxEvict
  /\ \A w \in Wk : ~(wpc[w] = "hold" /\ pos[w] = s)
  /\ buf' = [buf EXCEPT ![s] = "out"]
  /\ ldr' = [ldr EXCEPT ![s] = 0]
  /\ evs' = evs + 1
  /\ UNCHANGED <<walkVars, taskVars, errs, ghost>>

AllDone == (\A w \in Wk : wpc[w] = "done") /\ (\A i \in Sl : tst[i] = "free")
Idle == AllDone /\ UNCHANGED vars

Next ==
  \/ \E w \in Wk : WalkProg(w) \/ WStop(w)
  \/ \E i \in Sl : TaskProg(i)
  \/ \E s \in Sec : Evict(s)
  \/ Idle

\* The walks' own steps and the pool's are fair; stopping early and evicting are not.
Spec == Init /\ [][Next]_vars /\ (\A w \in Wk : WF_vars(WalkProg(w))) /\ (\A i \in Sl : WF_vars(TaskProg(i)))

---------------------------------------------------------------------------
\* Properties.

TypeOK ==
  /\ buf \in [Sec -> {"out", "reading", "in"}]
  /\ ldr \in [Sec -> 0..NW]
  /\ pos \in [Wk -> 0..S]
  /\ wpc \in [Wk -> {"enter", "req", "slotwait", "fix", "read", "hold", "done"}]
  /\ win \in [Wk -> 1..16]
  /\ \A w \in Wk : win[w] <= MaxWin
  /\ req \in [Wk -> 0..S]
  /\ tgt \in [Wk -> 0..S]
  /\ nreq \in [Wk -> 0..S]
  /\ tsec \in [Sl -> 0..S]
  /\ town \in [Sl -> 0..NW]
  /\ tst \in [Sl -> {"free", "new", "read"}]
  /\ evs \in Nat
  /\ evs <= MaxEvict
  /\ errs \in Nat
  /\ errs <= MaxErr
  /\ hot0 \in BOOLEAN
  /\ uaf \in BOOLEAN
  /\ used \in BOOLEAN
  /\ cross \in BOOLEAN
  /\ stale \in BOOLEAN
  /\ selfRead \in BOOLEAN
  /\ refused \in BOOLEAN
  /\ mcause \in [Wk -> {"none", "wait", "self", "refused"}]
  /\ unreq \in [Wk -> BOOLEAN]
  /\ cover \in [Wk -> 0..S]
  /\ hits \in [Wk -> 0..17]
  /\ \A w \in Wk : hits[w] <= MaxWin + 1
  /\ shrunk \in BOOLEAN
  /\ grewOnRefused \in BOOLEAN

\* C13: the walks and their requests end.
Ends == <>AllDone

\* C14: a walk over a table whose sectors all stay in the buffer sends no request.
HotNoRequest == (hot0 /\ evs = 0) => \A w \in Wk : nreq[w] = 0

\* C15: a walk that has entered k sectors has sent at most 2k+1 requests.
WasteBound == \A w \in Wk : nreq[w] <= 2 * pos[w] + 1

\* C16: nothing reads a walk's memory after the walk ended.
NoUseAfterEnd == ~uaf

\* C17: a walk never waits for a pool thread.
NoSlotWait == \A w \in Wk : wpc[w] # "slotwait"

\* Witnesses.
NotUsed == ~used
NotCross == ~cross
NotStale == ~stale
NotRefused == ~refused
NotHotDone == ~(AllDone /\ hot0 /\ evs = 0)
NotAllDone == ~AllDone
NotShrunk == ~shrunk
NotGrewOnRefused == ~grewOnRefused

\* C18: a sector the walk read itself because the pool refused it does not make the distance grow.
NoGrowOnRefused == ~grewOnRefused

---------------------------------------------------------------------------
\* The inductive invariant (Ramp = "wait_capped", CountRefused = FALSE, no mutant).

\* A pool slot is free with nothing in it, or holds a request for a sector of a walk.
SlotShape ==
  \A i \in Sl :
    IF tst[i] = "free" THEN tsec[i] = 0 /\ town[i] = 0
    ELSE tsec[i] >= 1 /\ town[i] >= 1

\* A walk past its first entry is in a sector; one that enters has a sector left.
WalkShape ==
  \A w \in Wk :
    /\ wpc[w] \in {"req", "slotwait", "fix", "read", "hold"} => pos[w] >= 1
    /\ wpc[w] = "enter" => pos[w] < S
    /\ wpc[w] = "hold" => buf[pos[w]] = "in"
    /\ wpc[w] = "read" => buf[pos[w]] = "reading"
    /\ tst \in [Sl -> {"free", "new", "read"}]

\* A sector being read has one reader, a pool thread or a walk, and the reader sees it buffer-locked.
ReadShape ==
  /\ \A i \in Sl : tst[i] = "read" => buf[tsec[i]] = "reading"
  /\ \A i, j \in Sl : (i # j /\ tst[i] = "read" /\ tst[j] = "read") => tsec[i] # tsec[j]
  /\ \A i \in Sl, w \in Wk : (tst[i] = "read" /\ wpc[w] = "read") => tsec[i] # pos[w]
  /\ \A v, w \in Wk : (v # w /\ wpc[v] = "read" /\ wpc[w] = "read") => pos[v] # pos[w]

\* What a walk asked for: every request is for a distinct sector after the first, up to req; req never passes the
\* farthest sector its distance reached, and that is at most twice the sectors entered (the cap of "wait_capped").
AskShape ==
  \A w \in Wk :
    /\ nreq[w] <= (IF req[w] = 0 THEN 0 ELSE req[w] - 1)
    /\ req[w] >= pos[w]
    /\ wpc[w] \in {"req", "slotwait"} => tgt[w] >= pos[w]
    /\ req[w] <= cover[w] \/ req[w] = pos[w]
    /\ cover[w] <= 2 * pos[w]
    /\ tgt[w] <= cover[w]
    /\ win[w] <= (IF pos[w] = 0 THEN 1 ELSE pos[w])

\* Before any eviction, a table that started all in the buffer stays there and no request exists.
HotStays ==
  (hot0 /\ evs = 0) => ((\A s \in Sec : buf[s] = "in") /\ (\A i \in Sl : tst[i] = "free"))

IndInv ==
  /\ TypeOK
  /\ SlotShape
  /\ WalkShape
  /\ ReadShape
  /\ AskShape
  /\ HotStays
  /\ HotNoRequest
  /\ WasteBound
  /\ NoUseAfterEnd
  /\ NoSlotWait
  /\ NoGrowOnRefused

=============================================================================
