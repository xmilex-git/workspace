--------------------------- MODULE PageBatchWalk ---------------------------
(* The page batch's serial heap walk (CBRD-27361, develop be0a9ab1f).

   One scan walks the heap chain page by page.  On each page it collects chunks
   (heap_page_collect_visible), evaluates them (expr_batch_run), and either
   accumulates them (chain mode: aggregate / GROUP BY / projection consumers,
   qexec_batch_scan_chain) or copies them out and lets the page go while the
   rows go out one by one (iter mode: the filter iterator, scan_batch_iter_next).
   A chunk the batch declines, or a record whose visible version is not on the
   page, hands the page to the row path from the chunk's first slot
   (scan_batch_page_rowmode).  Concurrent transactions and vacuum change pages
   the scan does not hold.

   A record is one of
     "vis"  REC_HOME, visible, of a representation the plan decodes
     "rep"  REC_HOME, visible, of a representation the plan has not learned
     "off"  visible, but its visible version is not on the page (relocated,
            overflow, or an older version in the log)
     "inv"  not visible to the snapshot (deleted before it, inserted after it)
     "none" an empty slot
   The snapshot fixes which records are visible: the environment never moves a
   record into or out of {vis, rep, off} (AnsStable). *)
EXTENDS Naturals, FiniteSets

CONSTANTS NP, NS, Mode, Mutant
ASSUME Assm == /\ NP \in Nat /\ NP >= 1 /\ NS \in Nat /\ NS >= 1
               /\ Mode \in {"chain", "iter"}
               /\ Mutant \in {"none", "no_unfixed_check", "exc_resume_at_slot", "fallback_from_pos",
                              "fallback_after_consume", "unfix_before_next", "iter_release_empty",
                              "tail_drop"}

Pages == 1..NP
Slots == 1..NS
Rows == Pages \X Slots
Kinds == {"vis", "rep", "off", "inv", "none"}
Phases == {"next", "nexthop", "collect", "learn", "learnrefix", "run", "runrefix",
           "consume", "copy", "emit", "row", "done", "error"}

VARIABLES
  rec,          \* [Rows -> Kinds]: the heap's records
  alive,        \* [Pages -> BOOLEAN]: the page is in the heap chain
  learned,      \* the plan learned the "rep" representation (expr_batch_plan_learn_repr)
  em,           \* ghost [Rows -> BOOLEAN]: the row went to the consumer
  ph,           \* the scan's phase
  cur,          \* the page the walk is on (HEAP_SCAN_ID.batch_vpid)
  fixed,        \* the scan cache's watcher holds cur
  front,        \* ghost: every visible row up to <<cur, front>> went out, none after
  cstart,       \* chunk_start: the slot the chunk started after
  cend,         \* the chunk's last slot
  npos,         \* the slot the next collection resumes after (the *slot heap_page_collect_visible returns)
  more,         \* S_SUCCESS: the page may have more (batch_page_more)
  rpos,         \* the row path's position (HEAP_SCAN_ID.curr_oid.slotid)
  ptrValid,     \* the page stayed fixed since the chunk was collected (its peeked rows are valid)
  unfixedFlag,  \* PGBUF_WATCHER.page_was_unfixed
  started,      \* batch_started
  uaf,          \* ghost: a peeked row read without the page held since its collection
  badFix,       \* ghost: a page fixed after vacuum may have removed it
  dup,          \* ghost: a row went out twice
  stray,        \* ghost: a row the snapshot does not see went out
  sawChunk, sawRow, sawDrop  \* ghosts for the witnesses

vars == <<rec, alive, learned, em, ph, cur, fixed, front, cstart, cend, npos, more, rpos,
          ptrValid, unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>

IsAns(k) == k \in {"vis", "rep", "off"}
Ans(p, s) == IsAns(rec[<<p, s>>])
HasAns(p) == \E s \in Slots : Ans(p, s)
Le(r1, r2) == r1[1] < r2[1] \/ (r1[1] = r2[1] /\ r1[2] <= r2[2])
\* x is the least element of S (the actions pick it with \E, so the proof needs no Min)
Least(x, S) == x \in S /\ \A y \in S : x <= y

\* what heap_page_collect_visible decides, from slot f of page p
Eff(k) == IF k = "rep" /\ learned THEN "vis" ELSE k
Exc(p, f) == {s \in Slots : s > f /\ Eff(rec[<<p, s>>]) \in {"off", "rep"}}
\* e is the first record after f the page does not answer for, NS + 1 when there is none
IsE(e, p, f) == IF Exc(p, f) = {} THEN e = NS + 1 ELSE Least(e, Exc(p, f))
V(p, f, e) == {s \in Slots : f < s /\ s < e /\ Eff(rec[<<p, s>>]) = "vis"}
\* the visible rows of cur after slot a up to slot b
AnsIn(a, b) == {s \in Slots : a < s /\ s <= b /\ Ans(cur, s)}

\* ---------------------------------------------------------------- properties
TypeOK == /\ rec \in [Rows -> Kinds]
          /\ alive \in [Pages -> BOOLEAN]
          /\ em \in [Rows -> BOOLEAN]
          /\ ph \in Phases
          /\ cur \in Pages
          /\ front \in 0..NS /\ cstart \in 0..NS /\ cend \in 0..NS /\ npos \in 0..NS /\ rpos \in 0..NS
          /\ learned \in BOOLEAN /\ fixed \in BOOLEAN /\ more \in BOOLEAN /\ ptrValid \in BOOLEAN
          /\ unfixedFlag \in BOOLEAN /\ started \in BOOLEAN
          /\ uaf \in BOOLEAN /\ badFix \in BOOLEAN /\ dup \in BOOLEAN /\ stray \in BOOLEAN
          /\ sawChunk \in BOOLEAN /\ sawRow \in BOOLEAN /\ sawDrop \in BOOLEAN

NoUseAfterUnfix == ~uaf                                         \* C2
NoFixOfRemovedPage == ~badFix                                   \* C3
NoDuplicate == ~dup                                             \* C1
NoInvisibleRow == ~stray                                        \* C1
Complete == ph = "done" => \A r \in Rows : IsAns(rec[r]) => em[r]  \* C1
\* the environment assumption the model's equivalence rests on
AnsStable == [][\A r \in Rows : IsAns(rec[r]) = IsAns(rec'[r])]_vars

\* witnesses
NotDoneMixed == ~(ph = "done" /\ sawChunk /\ sawRow /\ sawDrop)
NotDoneAfterRemoval == ~(ph = "done" /\ sawChunk /\ \E p \in Pages : ~alive[p])

\* ---------------------------------------------------------------- the scan
Emit(r) == /\ em' = [em EXCEPT ![r] = TRUE]
           /\ dup' = (dup \/ em[r])
           /\ stray' = (stray \/ ~IsAns(rec[r]))

Init == /\ rec \in [Rows -> Kinds]
        /\ alive = [p \in Pages |-> TRUE]
        /\ learned = FALSE
        /\ em = [r \in Rows |-> FALSE]
        /\ ph = "next" /\ cur = 1 /\ fixed = FALSE
        /\ front = 0 /\ cstart = 0 /\ cend = 0 /\ npos = 0 /\ more = FALSE /\ rpos = 0
        /\ ptrValid = FALSE /\ unfixedFlag = FALSE /\ started = FALSE
        /\ uaf = FALSE /\ badFix = FALSE /\ dup = FALSE /\ stray = FALSE
        /\ sawChunk = FALSE /\ sawRow = FALSE /\ sawDrop = FALSE

\* scan_batch_next_page: the header page first
NextFirst == /\ ph = "next" /\ ~started
             /\ cur' = 1 /\ fixed' = TRUE /\ front' = 0 /\ started' = TRUE /\ unfixedFlag' = FALSE
             /\ ph' = "collect"
             /\ UNCHANGED <<rec, alive, learned, em, cstart, cend, npos, more, rpos, ptrValid,
                            uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>

\* scan_batch_next_page with the page let go: fixed again to find its successor
NextRefix == /\ ph = "next" /\ started /\ ~fixed
             /\ fixed' = TRUE /\ badFix' = (badFix \/ ~alive[cur]) /\ unfixedFlag' = FALSE
             /\ UNCHANGED <<rec, alive, learned, em, ph, cur, front, cstart, cend, npos, more, rpos,
                            ptrValid, started, uaf, dup, stray, sawChunk, sawRow, sawDrop>>

\* the chunk's slots and flags are read only while a chunk is out; the model zeroes them after it
ClearChunk == cstart' = 0 /\ cend' = 0 /\ npos' = 0 /\ more' = FALSE /\ ptrValid' = FALSE

\* heap_vpid_next from the held page, the next page fixed (OLD_PAGE_PREVENT_DEALLOC) before the held one
\* is released (pgbuf_replace_watcher): both latched, one step
Later == {q \in Pages : q > cur /\ alive[q]}
Hop == IF Later = {}
       THEN /\ fixed' = FALSE /\ ph' = "done"
            /\ UNCHANGED <<cur, front, unfixedFlag>>
       ELSE /\ \E q \in Later : Least(q, Later) /\ cur' = q
            /\ fixed' = TRUE /\ front' = 0 /\ unfixedFlag' = FALSE /\ ph' = "collect"

NextHop == /\ ph = "next" /\ started /\ fixed /\ Mutant # "unfix_before_next"
           /\ Hop
           /\ UNCHANGED <<rec, alive, learned, em, cstart, cend, npos, more, rpos, ptrValid, started,
                          uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>

\* mutant: the held page released before its successor is found and fixed
NextUnfixFirst == /\ ph = "next" /\ started /\ fixed /\ Mutant = "unfix_before_next"
                  /\ fixed' = FALSE /\ ph' = "nexthop"
                  /\ UNCHANGED <<rec, alive, learned, em, cur, front, cstart, cend, npos, more, rpos,
                                 ptrValid, unfixedFlag, started, uaf, badFix, dup, stray,
                                 sawChunk, sawRow, sawDrop>>
NextHopLate == /\ ph = "nexthop"
               /\ badFix' = (badFix \/ ~alive[cur])
               /\ Hop
               /\ UNCHANGED <<rec, alive, learned, em, cstart, cend, npos, more, rpos, ptrValid, started,
                              uaf, dup, stray, sawChunk, sawRow, sawDrop>>

\* heap_page_collect_visible fixes the page when the watcher was let go (iter mode, after a chunk's rows went out)
CollectRefix == /\ ph = "collect" /\ ~fixed
                /\ fixed' = TRUE /\ badFix' = (badFix \/ ~alive[cur]) /\ unfixedFlag' = FALSE
                /\ UNCHANGED <<rec, alive, learned, em, ph, cur, front, cstart, cend, npos, more, rpos,
                               ptrValid, started, uaf, dup, stray, sawChunk, sawRow, sawDrop>>

\* heap_page_collect_visible under the page's read latch: one step.  The cap may end the chunk at any visible
\* row (EXPR_BATCH_CHUNK_BYTES abstracted).
StartChunk(c, nx, m) ==
  /\ cstart' = front /\ cend' = c /\ npos' = nx /\ more' = m /\ ptrValid' = TRUE /\ ph' = "run"
  /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front, rpos, unfixedFlag, started,
                 uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>

Collect ==
  /\ ph = "collect" /\ fixed
  /\ \E e \in 1..(NS + 1) :
       /\ IsE(e, cur, front)
       /\ \/ /\ V(cur, front, e) # {}
             /\ \/ \E c \in V(cur, front, e) : StartChunk(c, c, TRUE)                  \* the cap
                \/ /\ e <= NS                                                     \* the record that ends the chunk
                   /\ StartChunk(e - 1, IF Mutant = "exc_resume_at_slot" THEN e ELSE e - 1, TRUE)
                \/ e = NS + 1 /\ StartChunk(NS, NS, FALSE)                         \* S_END with rows
          \/ /\ V(cur, front, e) = {} /\ e <= NS                                     \* S_DOESNT_FIT
             /\ IF Eff(rec[<<cur, e>>]) = "rep" THEN ph' = "learn" /\ rpos' = 0
                ELSE ph' = "row" /\ rpos' = front
             /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front, cstart, cend, npos, more, ptrValid,
                            unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
          \/ /\ V(cur, front, e) = {} /\ e = NS + 1                                  \* S_END, nothing left
             /\ ph' = "next"
             /\ fixed' = (fixed /\ ~(Mode = "iter" /\ Mutant = "iter_release_empty"))
             /\ UNCHANGED <<rec, alive, learned, em, cur, front, cstart, cend, npos, more, rpos, ptrValid,
                            unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>

\* scan_batch_collect_chunk: expr_batch_plan_learn_repr on a record of an unlearned representation, nothing
\* collected; it reads the class record, whose ordered fix may let the page go and fix it again (LearnDrop)
Learn == /\ ph = "learn" /\ fixed
         /\ \/ learned' = TRUE /\ ph' = "collect" /\ UNCHANGED rpos
            \/ ph' = "row" /\ rpos' = front /\ UNCHANGED learned
         /\ UNCHANGED <<rec, alive, em, cur, fixed, front, cstart, cend, npos, more, ptrValid, unfixedFlag,
                        started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
LearnDrop == /\ ph = "learn" /\ fixed
             /\ fixed' = FALSE /\ ptrValid' = FALSE /\ ph' = "learnrefix" /\ sawDrop' = TRUE
             /\ UNCHANGED <<rec, alive, learned, em, cur, front, cstart, cend, npos, more, rpos, unfixedFlag,
                            started, uaf, badFix, dup, stray, sawChunk, sawRow>>
LearnRefix == /\ ph = "learnrefix"
              /\ fixed' = TRUE /\ badFix' = (badFix \/ ~alive[cur]) /\ unfixedFlag' = TRUE /\ ph' = "learn"
              /\ UNCHANGED <<rec, alive, learned, em, cur, front, cstart, cend, npos, more, rpos, ptrValid,
                             started, uaf, dup, stray, sawChunk, sawRow, sawDrop>>

\* expr_batch_run: the chunk's filter and steps.  It declines (EXPR_BATCH_FALLBACK) or fails before anything is
\* accumulated; an ordered fix on this thread under it may let the page go and fix it again (RunDrop), and
\* page_was_unfixed then hands the chunk back.
RunOk == /\ ph = "run" /\ fixed
         /\ (~unfixedFlag \/ Mutant = "no_unfixed_check")
         /\ ph' = IF Mode = "chain" THEN "consume" ELSE "copy"
         /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front, cstart, cend, npos, more, rpos, ptrValid,
                        unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
RunDecline == /\ ph = "run" /\ fixed
              /\ ph' = "row"
              /\ rpos' = IF Mutant = "fallback_from_pos" THEN npos ELSE cstart
              /\ ClearChunk
              /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front,
                             unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
RunError == /\ ph = "run" /\ fixed
            /\ ph' = "error"
            /\ ClearChunk
            /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front, rpos,
                           unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
RunDrop == /\ ph = "run" /\ fixed
           /\ fixed' = FALSE /\ ptrValid' = FALSE /\ ph' = "runrefix" /\ sawDrop' = TRUE
           /\ UNCHANGED <<rec, alive, learned, em, cur, front, cstart, cend, npos, more, rpos, unfixedFlag,
                          started, uaf, badFix, dup, stray, sawChunk, sawRow>>
RunRefix == /\ ph = "runrefix"
            /\ fixed' = TRUE /\ badFix' = (badFix \/ ~alive[cur]) /\ unfixedFlag' = TRUE /\ ph' = "run"
            /\ UNCHANGED <<rec, alive, learned, em, cur, front, cstart, cend, npos, more, rpos, ptrValid,
                           started, uaf, dup, stray, sawChunk, sawRow, sawDrop>>

\* the chain's blocking node takes the chunk's rows from the page, in row order (one step per row: finer than
\* the code, where the whole chunk is one step under the latch)
ChunkDone == /\ front' = npos /\ ph' = (IF more THEN "collect" ELSE "next") /\ ClearChunk
ConsumeRow == /\ ph = "consume"
              /\ AnsIn(front, cend) # {}
              /\ \E s \in AnsIn(front, cend) : Least(s, AnsIn(front, cend)) /\ Emit(<<cur, s>>) /\ front' = s
              /\ uaf' = (uaf \/ ~fixed \/ ~ptrValid)
              /\ sawChunk' = TRUE
              /\ UNCHANGED <<rec, alive, learned, ph, cur, fixed, cstart, cend, npos, more, rpos, ptrValid,
                             unfixedFlag, started, badFix, sawRow, sawDrop>>
ConsumeEnd == /\ ph = "consume"
              /\ AnsIn(front, cend) = {}
              /\ ChunkDone
              /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, rpos,
                             unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
\* mutant: a node accumulates part of the chunk and then hands it back
ConsumeFallback == /\ ph = "consume" /\ Mutant = "fallback_after_consume" /\ front > cstart
                   /\ ph' = "row" /\ rpos' = cstart /\ ClearChunk
                   /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front,
                                  unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>

\* environment-assumption mutant: an ordered fix on this thread under the blocking node lets the page go and fixes
\* it again (qexec_batch_eligible () and the fixed-scan rules keep every such operator off a batch block)
ConsumeDrop == /\ ph = "consume" /\ Mutant = "tail_drop" /\ ptrValid
               /\ ptrValid' = FALSE /\ unfixedFlag' = TRUE /\ sawDrop' = TRUE
               /\ UNCHANGED <<rec, alive, learned, em, ph, cur, fixed, front, cstart, cend, npos, more, rpos,
                              started, uaf, badFix, dup, stray, sawChunk, sawRow>>

\* scan_batch_iter_next: the kept rows' records copied out (scan_batch_copy_kept), then the page let go
Copy == /\ ph = "copy"
        /\ uaf' = (uaf \/ ~fixed \/ ~ptrValid)
        /\ fixed' = FALSE /\ ptrValid' = FALSE /\ ph' = "emit"
        /\ UNCHANGED <<rec, alive, learned, em, cur, front, cstart, cend, npos, more, rpos, unfixedFlag,
                       started, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
EmitRow == /\ ph = "emit"
           /\ AnsIn(front, cend) # {}
           /\ \E s \in AnsIn(front, cend) : Least(s, AnsIn(front, cend)) /\ Emit(<<cur, s>>) /\ front' = s
           /\ sawChunk' = TRUE
           /\ UNCHANGED <<rec, alive, learned, ph, cur, fixed, cstart, cend, npos, more, rpos, ptrValid,
                          unfixedFlag, started, uaf, badFix, sawRow, sawDrop>>
EmitEnd == /\ ph = "emit"
           /\ AnsIn(front, cend) = {}
           /\ ChunkDone
           /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, rpos,
                          unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>

\* the row path over the rest of the page (heap_next_1page from curr_oid): fixed again when it was let go
RowRefix == /\ ph = "row" /\ ~fixed
            /\ fixed' = TRUE /\ badFix' = (badFix \/ ~alive[cur]) /\ unfixedFlag' = FALSE
            /\ UNCHANGED <<rec, alive, learned, em, ph, cur, front, cstart, cend, npos, more, rpos, ptrValid,
                           started, uaf, dup, stray, sawChunk, sawRow, sawDrop>>
\* one row under the latch.  A previous-version walk or a forward-page fetch lets the home page go (keep FALSE);
\* the filter iterator lets it go after every row (release_after_row)
RowNext == /\ ph = "row" /\ fixed
           /\ AnsIn(rpos, NS) # {}
           /\ \E s \in AnsIn(rpos, NS) :
                /\ Least(s, AnsIn(rpos, NS)) /\ Emit(<<cur, s>>) /\ rpos' = s /\ front' = s
                /\ \/ fixed' = FALSE /\ (Mode = "iter" \/ rec[<<cur, s>>] = "off")
                   \/ fixed' = TRUE /\ Mode = "chain"
           /\ sawRow' = TRUE
           /\ UNCHANGED <<rec, alive, learned, ph, cur, cstart, cend, npos, more, ptrValid, unfixedFlag,
                          started, uaf, badFix, sawChunk, sawDrop>>
\* S_END: the page stays held, so that scan_batch_next_page finds its successor from it
RowEnd == /\ ph = "row" /\ fixed
          /\ AnsIn(rpos, NS) = {}
          /\ ph' = "next" /\ rpos' = 0
          /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front, cstart, cend, npos, more, ptrValid,
                         unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>

\* an interrupt or an error the row path raises: the scan stops
Interrupt == /\ ph \in {"collect", "row"}
             /\ ph' = "error" /\ rpos' = 0
             /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front, cstart, cend, npos, more, ptrValid,
                            unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>

Scan == NextFirst \/ NextRefix \/ NextHop \/ NextUnfixFirst \/ NextHopLate \/ CollectRefix \/ Collect
        \/ Learn \/ LearnDrop \/ LearnRefix \/ RunOk \/ RunDecline \/ RunError \/ RunDrop \/ RunRefix
        \/ ConsumeRow \/ ConsumeEnd \/ ConsumeFallback \/ ConsumeDrop \/ Copy \/ EmitRow \/ EmitEnd
        \/ RowRefix \/ RowNext \/ RowEnd \/ Interrupt

\* ---------------------------------------------------------------- the environment
\* Writers take the page's write latch, which the scan's read latch excludes.
Free(p) == ~(fixed /\ cur = p)
EnvVars == <<learned, em, ph, cur, fixed, front, cstart, cend, npos, more, rpos, ptrValid, unfixedFlag,
             started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
\* an update (MVCC: the new version in place, the old one in the log) or a delete by a transaction the snapshot
\* does not see: the row stays visible to the snapshot, its version is in the log now
EnvUpdate == \E r \in Rows : /\ rec[r] \in {"vis", "rep"} /\ Free(r[1])
                             /\ rec' = [rec EXCEPT ![r] = "off"]
                             /\ UNCHANGED <<alive>> /\ UNCHANGED EnvVars
\* vacuum removes a record no snapshot sees
EnvVacuum == \E r \in Rows : /\ rec[r] = "inv" /\ Free(r[1])
                             /\ rec' = [rec EXCEPT ![r] = "none"]
                             /\ UNCHANGED <<alive>> /\ UNCHANGED EnvVars
\* an insert the snapshot does not see, into a free slot of a page in the chain
EnvInsert == \E r \in Rows : /\ rec[r] = "none" /\ alive[r[1]] /\ Free(r[1])
                             /\ rec' = [rec EXCEPT ![r] = "inv"]
                             /\ UNCHANGED <<alive>> /\ UNCHANGED EnvVars
\* heap_remove_page_on_vacuum: an empty page leaves the chain; it write-latches the page and its neighbours
EnvRemove == \E p \in Pages :
               /\ p # 1 /\ alive[p] /\ Free(p)
               /\ \A s \in Slots : rec[<<p, s>>] = "none"
               /\ \A q \in Pages : (alive[q] /\ q # p /\ ~\E m \in Pages : alive[m] /\ m # p
                                        /\ ((q < m /\ m < p) \/ (p < m /\ m < q))) => Free(q)
               /\ alive' = [alive EXCEPT ![p] = FALSE]
               /\ UNCHANGED <<rec>> /\ UNCHANGED EnvVars

Env == EnvUpdate \/ EnvVacuum \/ EnvInsert \/ EnvRemove

Terminating == ph \in {"done", "error"} /\ UNCHANGED vars

Next == Scan \/ Env \/ Terminating
Spec == Init /\ [][Next]_vars

\* ---------------------------------------------------------------- inductive invariant
\* IndInv in parts (the TLAPS proof takes them one at a time), written in the order TLC enumerates them
\* (INIT IndInv): each variable bound, then what constrains it
IGhost == /\ uaf = FALSE /\ badFix = FALSE /\ dup = FALSE /\ stray = FALSE
          /\ sawChunk \in BOOLEAN /\ sawRow \in BOOLEAN /\ sawDrop \in BOOLEAN
IRec == rec \in [Rows -> Kinds]
IAlive == /\ alive \in [Pages -> BOOLEAN]
          /\ alive[1]
          /\ \A p \in Pages : ~alive[p] => \A s \in Slots : rec[<<p, s>>] = "none"
\* boolean typing apart from the rest (P4)
IPhaseB == learned \in BOOLEAN /\ started \in BOOLEAN
IFixB == fixed \in BOOLEAN /\ unfixedFlag \in BOOLEAN
IChunkB == more \in BOOLEAN /\ ptrValid \in BOOLEAN
IPhase == /\ ph \in Phases
          /\ Mutant # "unfix_before_next" => ph # "nexthop"
          /\ ~started => ph = "next"
          /\ ph \in {"collect", "learn", "learnrefix", "run", "runrefix", "consume", "copy", "emit", "row",
                     "done", "error"} => started
IFix == /\ cur \in Pages
        /\ ~started => cur = 1
        /\ fixed => alive[cur]
        /\ ~started => ~fixed
        /\ started /\ ~fixed /\ ph \notin {"done", "error"} => HasAns(cur)
        /\ ph \in {"runrefix", "learnrefix"} => ~fixed
        /\ ph \in {"consume", "copy", "run", "learn"} => fixed
        /\ ph = "done" => ~fixed
        /\ ~started => ~unfixedFlag
IFront == /\ front \in 0..NS
          /\ ~started => front = 0
          /\ ph = "next" /\ started => \A s \in Slots : s > front => ~Ans(cur, s)
          /\ ph \in {"learn", "learnrefix"} => \E s \in Slots : s > front /\ Ans(cur, s)
          /\ rpos \in 0..NS
          /\ rpos = IF ph = "row" THEN front ELSE 0
IChunk == /\ cstart \in 0..NS /\ cend \in 0..NS /\ npos \in 0..NS
          /\ IF ph \in {"run", "runrefix", "consume", "copy", "emit"}
             THEN /\ cstart <= front /\ front <= cend /\ npos = cend
                  /\ AnsIn(cstart, cend) # {}
                  /\ (~more => cend = NS)
                  /\ (ph \in {"run", "runrefix", "copy"} => front = cstart)
                  /\ (ph \in {"consume", "copy"} => ptrValid)
                  /\ (ph = "run" /\ ~ptrValid => unfixedFlag)
                  /\ (ph = "runrefix" => ~ptrValid)
             ELSE cstart = 0 /\ cend = 0 /\ npos = 0 /\ more = FALSE /\ ptrValid = FALSE
IEm == /\ em \in [Rows -> BOOLEAN]
       /\ \A r \in Rows : em[r] = (started /\ IsAns(rec[r]) /\ Le(r, <<cur, front>>))
       /\ ph = "done" => \A r \in Rows : IsAns(rec[r]) => em[r]

IndInv == IGhost /\ IRec /\ IAlive /\ IPhaseB /\ IPhase /\ IFixB /\ IFix /\ IFront /\ IChunkB /\ IChunk /\ IEm
=============================================================================
