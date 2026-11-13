----------------------------- MODULE PartWalk -----------------------------
(* PR #8356 (CBRD-27866) at 60058202c: a partitioned NL inner walked per outer
   row. One executor thread drives the inner scan; every step is one branch of
   qexec_reset_sa_inner_scan_block, qexec_execute_scan, qexec_open_row_partition,
   qexec_init_next_partition or qexec_open_scan. The interleaving the model
   explores is over input classes: the join kind, the inner rows per partition,
   the outer keys, per-row pruning, the memo (absent, present, dropped midway)
   and a re-execution of the scan (a subquery run again).
   Mutant "block" is the merge-base: the scan block iterator runs every outer
   row again for each partition (qexec_next_scan_block_iterations). *)
EXTENDS Naturals, FiniteSets

CONSTANTS NP, NR, NK, NExec, Mutant
ASSUME Assm == /\ NP \in Nat /\ NP >= 1 /\ NR \in Nat /\ NR >= 1 /\ NK \in Nat /\ NK >= 1
               /\ NExec \in Nat
               /\ Mutant \in {"none", "block", "no_reopen_reset", "no_fetched_restore",
                              "all_partitions_outer", "no_force_partition", "memo_done_each_partition",
                              "no_success_latch", "has_next_ignores_pruned"}

\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: NP Int
\* apalache-type: NR Int
\* apalache-type: NK Int
\* apalache-type: NExec Int
\* apalache-type: Mutant Str
\* apalache-type: kind Str
\* apalache-type: prune Bool
\* apalache-type: home Int -> Int
\* apalache-type: data Int -> Set(Int)
\* apalache-type: outer Int -> Int
\* apalache-type: memoOn Bool
\* apalache-type: row Int
\* apalache-type: pc Str
\* apalache-type: execLeft Int
\* apalache-type: blk Int
\* apalache-type: cur Int
\* apalache-type: started Bool
\* apalache-type: pos Bool
\* apalache-type: sf Bool
\* apalache-type: nf Bool
\* apalache-type: pending Bool
\* apalache-type: loaded Bool
\* apalache-type: rp Set(Int)
\* apalache-type: currNull Bool
\* apalache-type: em Int -> (Int -> Int)
\* apalache-type: memoRec Int -> (Int -> Int)
\* apalache-type: memoDone Int -> Bool
\* apalache-type: reads Int -> Int
\* apalache-type: opened Set(Int)
\* apalache-type: hit Bool
\* apalache-type: err Bool

Parts == 1..NP
Slots == 0..NP          \* 0: the NULL row of an outer join, or the outer row a SEMI / ANTI inner lets through
Rows == 1..NR
Keys == 1..NK
Kinds == {"inner", "left", "semi", "anti"}
Zero == [s \in Slots |-> 0]
EndRes == NP + 1      \* scan_next_scan returned S_END
Min(S) == CHOOSE x \in S : \A y \in S : x <= y

VARIABLES kind, prune, home, data, outer,   \* the input, fixed by Init
  memoOn,      \* xasl->memoize_storage != NULL
  row,         \* the outer row being joined
  pc,          \* where the executor is
  execLeft,    \* re-executions of the scan still to come
  blk,         \* mutant "block": the partition the block iterator is on
  cur,         \* spec->curent (0: NULL)
  started,     \* spec->s_id.status == S_STARTED
  pos,         \* the open partition already returned its row for the key
  sf,          \* s_id.single_fetched
  nf,          \* s_id.null_fetched
  pending,     \* spec->row_rewind_pending
  loaded,      \* spec->row_pruning != NULL
  rp,          \* the partitions whose row_pruned is set
  currNull,    \* xasl->curr_spec == NULL
  em,          \* ghost: rows the join returned per outer row and slot
  memoRec, memoDone,   \* the memo entry per key, and whether memoize_put_nullptr closed it
  reads,       \* ghost: times each outer row was read in this execution
  opened,      \* ghost: partitions the current outer row opened or reset
  hit,         \* ghost: the memo answered the current outer row
  err          \* ghost: qexec_open_scan failed on a re-execution

vars == << kind, prune, home, data, outer, memoOn, row, pc, execLeft, blk, cur, started, pos, sf, nf,
           pending, loaded, rp, currNull, em, memoRec, memoDone, reads, opened, hit, err >>

Key == outer[row]
Matches(k) == {p \in Parts : k \in data[p]}
Exp(k) ==
  CASE kind = "inner" -> [s \in Slots |-> IF s > 0 /\ k \in data[s] THEN 1 ELSE 0]
    [] kind = "left" -> IF Matches(k) # {} THEN [s \in Slots |-> IF s > 0 /\ k \in data[s] THEN 1 ELSE 0]
                        ELSE [s \in Slots |-> IF s = 0 THEN 1 ELSE 0]
    [] kind = "semi" -> [s \in Slots |-> IF s = 0 /\ Matches(k) # {} THEN 1 ELSE 0]
    [] kind = "anti" -> [s \in Slots |-> IF s = 0 /\ Matches(k) = {} THEN 1 ELSE 0]
\* what a memo hit returns: an ANTI entry records the match, any other the rows returned
Replay(k) ==
  IF kind = "anti" THEN [s \in Slots |-> IF s = 0 /\ \A p \in Parts : memoRec[k][p] = 0 THEN 1 ELSE 0]
  ELSE memoRec[k]
Live(p) == ~loaded \/ p \notin rp
\* qexec_row_partition_has_next
HasNext == cur # 0 /\ \E p \in Parts : p > cur /\ (Mutant = "has_next_ignores_pruned" \/ Live(p))
NextLive == {p \in Parts : p > cur /\ Live(p)}
\* @type: (Int -> Int, Int) => (Int -> Int);
Inc(f, s) == [f EXCEPT ![s] = @ + 1]

TypeOK ==
  /\ kind \in Kinds /\ prune \in BOOLEAN /\ home \in [Keys -> 0..NP] /\ data \in [Parts -> SUBSET Keys]
  /\ outer \in [Rows -> Keys] /\ memoOn \in BOOLEAN /\ row \in Rows
  /\ pc \in {"reset", "enter", "open", "loop", "rowend", "done"}
  /\ execLeft \in 0..NExec /\ blk \in Parts /\ cur \in 0..NP
  /\ started \in BOOLEAN /\ pos \in BOOLEAN /\ sf \in BOOLEAN /\ nf \in BOOLEAN /\ pending \in BOOLEAN
  /\ loaded \in BOOLEAN /\ rp \in SUBSET Parts /\ currNull \in BOOLEAN
  /\ em \in [Rows -> [Slots -> Nat]] /\ memoRec \in [Keys -> [Slots -> Nat]] /\ memoDone \in [Keys -> BOOLEAN]
  /\ reads \in [Rows -> Nat] /\ opened \in SUBSET Parts /\ hit \in BOOLEAN /\ err \in BOOLEAN

\* C1: the outer row is read once per execution
ReadOnce == \A x \in Rows : reads[x] <= 1
\* C2: the join returns develop's rows
ResultOK == (pc = "done" /\ ~err) => \A x \in Rows : em[x] = Exp(outer[x])
\* C2: a closed memo entry answers what the walk returns
MemoSound == \A k \in Keys : memoDone[k] => Replay(k) = Exp(k)
\* C3: a row whose key has a partition, pruned by its join value, opens only that partition
PruneOK == (prune /\ Mutant # "block" /\ pc \in {"loop", "rowend"} /\ home[Key] \in Parts) =>
             opened \subseteq {home[Key]}
\* C4: a row the memo answers switches no partition
HitOpensNone == hit => opened = {}
\* C5: a re-executed scan opens
NoReopenError == ~err
\* C6: the walk stops on the last partition the row reads and never goes back to the root class
NoRootBlock == ~(pc = "loop" /\ cur = 0)
\* liveness: every execution ends
Terminates == <>(pc = "done" /\ (execLeft = 0 \/ err))

\* witnesses
NotLeftNullRow == ~(kind = "left" /\ pc = "rowend" /\ em[row][0] = 1 /\ ~hit)
NotForcedPartition == ~(prune /\ kind \in {"left", "anti"} /\ pc = "loop" /\ cur = 1 /\ home[Key] # 1)
NotHit == ~(pc = "rowend" /\ hit)
NotReused == ~(pc = "loop" /\ row > 1 /\ opened = {cur} /\ cur = NP)
NotReopened == ~(execLeft < NExec /\ pc = "rowend")
NotUnprunedWalk == ~(prune /\ home[Key] \notin Parts /\ pc = "loop" /\ cur = NP /\ NP > 1)
NotMemoDropped == ~(~memoOn /\ pc = "done" /\ \E k \in Keys : memoDone[k])

Init ==
  /\ kind \in Kinds /\ prune \in BOOLEAN /\ home \in [Keys -> 0..NP]
  /\ data \in {d \in [Parts -> SUBSET Keys] :
                 prune => \A p \in Parts : \A k \in d[p] : home[k] = p}
  /\ outer \in [Rows -> Keys] /\ memoOn \in BOOLEAN
  /\ row = 1 /\ pc = "reset" /\ execLeft = NExec /\ blk = 1
  \* qexec_open_scan starts a select on its first partition
  /\ cur = 1 /\ started = TRUE /\ pos = FALSE /\ sf = FALSE /\ nf = FALSE
  /\ pending = FALSE /\ loaded = FALSE /\ rp = {} /\ currNull = FALSE
  /\ em = [x \in Rows |-> Zero] /\ memoRec = [k \in Keys |-> Zero] /\ memoDone = [k \in Keys |-> FALSE]
  /\ reads = [x \in Rows |-> 0] /\ opened = {} /\ hit = FALSE /\ err = FALSE

Input == << kind, prune, home, data, outer >>

\* qexec_reset_sa_inner_scan_block: the deferred walk only marks the rewind; the block iterator resets its block
Reset ==
  /\ pc = "reset"
  /\ reads' = Inc(reads, row)
  /\ IF Mutant = "block"
       THEN /\ pending' = FALSE /\ pos' = FALSE /\ nf' = FALSE
       ELSE /\ pending' = TRUE /\ UNCHANGED << pos, nf >>
  /\ sf' = FALSE /\ currNull' = FALSE /\ opened' = {} /\ hit' = FALSE
  /\ pc' = "enter"
  /\ UNCHANGED << Input, memoOn, row, execLeft, blk, cur, started, loaded, rp, em, memoRec, memoDone, err >>

\* qexec_execute_scan: the memo check, which clears the rewind on a hit
Enter ==
  /\ pc = "enter"
  /\ IF memoOn /\ memoDone[Key]
       THEN /\ em' = [em EXCEPT ![row] = Replay(Key)]
            /\ pending' = FALSE /\ hit' = TRUE /\ pc' = "rowend"
            /\ UNCHANGED memoRec
       ELSE /\ memoRec' = [memoRec EXCEPT ![Key] = IF memoDone[Key] THEN @ ELSE Zero]
            /\ pc' = IF Mutant = "block" THEN "loop" ELSE "open"
            /\ UNCHANGED << em, pending, hit >>
  /\ UNCHANGED << Input, memoOn, row, execLeft, blk, cur, started, pos, sf, nf, loaded, rp, currNull,
                  memoDone, reads, opened, err >>

\* qexec_open_row_partition with partition_prune_spec_for_row and qexec_init_next_partition
OpenRow ==
  /\ pc = "open"
  /\ pending
  \* partition_prune_spec_for_row: a key with a partition keeps only it; for a key with none the pruning
  \* function may keep none (the terms' sets do not meet) or, finding no match, prune nothing
  \* (partition_prune_range: MATCH_OK with nothing added is MATCH_NOT_FOUND)
  /\ \E none \in BOOLEAN : LET
         rp1 == IF ~prune THEN rp
                ELSE IF home[Key] \in Parts \/ none THEN {p \in Parts : p # home[Key]} ELSE {}
         ld == loaded \/ prune
         cand == {p \in Parts : ~ld \/ p \notin rp1}
         first0 == IF cand = {} THEN 0 ELSE Min(cand)
         force == first0 = 0 /\ kind \in {"left", "anti"} /\ Mutant # "no_force_partition"
         first == IF force THEN 1 ELSE first0
         rp2 == IF force THEN rp1 \ {1} ELSE rp1
     IN /\ pending' = FALSE /\ loaded' = ld /\ rp' = rp2
        /\ IF first # 0 /\ first = cur /\ started
             THEN \* scan_reset_scan_block on the partition still open
                  /\ pos' = FALSE /\ sf' = FALSE /\ nf' = FALSE /\ currNull' = FALSE
                  /\ opened' = opened \cup {first} /\ pc' = "loop"
                  /\ UNCHANGED << cur, started, memoRec, memoDone >>
           ELSE IF first = 0
             THEN \* every partition pruned: S_END, the memo keeps the empty answer
                  /\ cur' = 0 /\ currNull' = TRUE /\ pc' = "rowend"
                  /\ memoDone' = IF memoOn THEN [memoDone EXCEPT ![Key] = TRUE] ELSE memoDone
                  /\ UNCHANGED << started, pos, sf, nf, memoRec, opened >>
           ELSE \* scan_switch_index_partition, or close and open
                  /\ cur' = first /\ started' = TRUE /\ pos' = FALSE /\ sf' = FALSE /\ nf' = FALSE
                  /\ currNull' = FALSE /\ opened' = opened \cup {first} /\ pc' = "loop"
                  /\ UNCHANGED << memoRec, memoDone >>
  /\ UNCHANGED << Input, memoOn, row, execLeft, blk, em, reads, hit, err >>

\* memoize_put: a closed entry takes no more rows
Put(s) == IF memoOn /\ ~memoDone[Key] THEN [memoRec EXCEPT ![Key] = Inc(@, s)] ELSE memoRec
Close == IF memoOn THEN [memoDone EXCEPT ![Key] = TRUE] ELSE memoDone

\* one pass of qexec_execute_scan's do-loop: scan_next_scan and the branch on its result
Loop ==
  /\ pc = "loop"
  /\ LET mode == CASE kind = "left" -> IF HasNext /\ Mutant # "all_partitions_outer" /\ Mutant # "block"
                                         THEN "in" ELSE "out"
                   [] kind = "inner" -> "in"
                   [] kind \in {"semi", "anti"} -> "si"
         match == cur \in Parts /\ Key \in data[cur] /\ ~pos
         \* scan_next_scan: S_SUCCESS with a row (slot > 0) or the NULL row (slot 0), or S_END (EndRes)
         res == CASE mode = "in" -> IF match THEN cur ELSE EndRes
                  [] mode = "out" -> IF nf THEN EndRes ELSE IF match THEN cur ELSE IF ~sf THEN 0 ELSE EndRes
                  [] mode = "si" -> IF sf THEN EndRes ELSE IF match THEN cur ELSE EndRes
         sf1 == IF res # EndRes /\ (mode # "in" \/ (kind = "left" /\ Mutant # "no_success_latch")) THEN TRUE ELSE sf
         lastLive == ~HasNext \/ NextLive = {}
     IN IF res # EndRes
        THEN /\ pos' = (pos \/ res > 0) /\ nf' = (nf \/ res = 0) /\ sf' = sf1
             /\ CASE kind \in {"inner", "left"} ->
                       /\ em' = [em EXCEPT ![row] = Inc(@, res)] /\ memoRec' = Put(res)
                       /\ pc' = "loop" /\ UNCHANGED memoDone
                  [] kind = "semi" ->
                       /\ em' = [em EXCEPT ![row] = Inc(@, 0)] /\ memoRec' = Put(0) /\ memoDone' = Close
                       /\ pc' = "loop"
                  [] kind = "anti" ->
                       \* the match closes the entry; the outer row is suppressed
                       /\ memoRec' = Put(res) /\ memoDone' = Close /\ pc' = "rowend" /\ UNCHANGED em
             /\ UNCHANGED << cur, currNull, opened >>
        ELSE IF Mutant = "block"
        THEN \* the block iterator: this block is done for the row
             /\ pc' = "rowend" /\ UNCHANGED << em, memoRec, memoDone, pos, sf, nf, cur, currNull, opened >>
        ELSE IF kind \in {"inner", "left"} \/ ~sf
        THEN IF HasNext
             THEN \* qexec_next_scan_block -> qexec_init_next_partition, past the pruned partitions
                  \* past the last live partition qexec_init_next_partition goes back to the root class
                  LET nxt == IF NextLive = {} THEN 0 ELSE Min(NextLive) IN
                  /\ cur' = nxt /\ pos' = FALSE /\ nf' = FALSE /\ UNCHANGED currNull
                  /\ sf' = IF kind = "left" /\ Mutant # "no_fetched_restore" THEN sf ELSE FALSE
                  /\ memoDone' = IF Mutant = "memo_done_each_partition" /\ kind \in {"inner", "left"}
                                   THEN Close ELSE memoDone
                  /\ opened' = IF nxt = 0 THEN opened ELSE opened \cup {nxt}
                  /\ pc' = "loop"
                  /\ UNCHANGED << em, memoRec >>
             ELSE \* the last partition: the key is exhausted; ANTI lets the row through
                  \* (qexec_execute_sa_anti_survive) and is entered again for it
                  /\ memoDone' = Close
                  /\ em' = IF kind = "anti" THEN [em EXCEPT ![row] = Inc(@, 0)] ELSE em
                  /\ sf' = TRUE /\ pc' = IF kind = "anti" THEN "loop" ELSE "rowend"
                  /\ UNCHANGED << memoRec, pos, nf, cur, currNull, opened >>
        ELSE \* a SEMI / ANTI re-entry after its row was decided
             /\ pc' = "rowend" /\ UNCHANGED << em, memoRec, memoDone, pos, sf, nf, cur, currNull, opened >>
  /\ UNCHANGED << Input, memoOn, row, execLeft, blk, started, pending, loaded, rp, reads, hit, err >>

\* the outer moves to its next row; the block iterator moves to its next partition after the last row
RowEnd ==
  /\ pc = "rowend"
  /\ IF row < NR
       THEN /\ row' = row + 1 /\ pc' = "reset" /\ UNCHANGED << blk, cur, pos >>
       ELSE IF Mutant = "block" /\ blk < NP
       THEN /\ row' = 1 /\ blk' = blk + 1 /\ cur' = blk + 1 /\ pos' = FALSE /\ pc' = "reset"
       ELSE /\ pc' = "done" /\ UNCHANGED << row, blk, cur, pos >>
  /\ UNCHANGED << Input, memoOn, execLeft, started, sf, nf, pending, loaded, rp, currNull, em, memoRec,
                  memoDone, reads, opened, hit, err >>

\* a subquery run again: qexec_close_scan (curent = NULL), then qexec_open_scan's first partition; the scan
\* chain's memo storage is built again for the execution
Reopen ==
  /\ pc = "done" /\ execLeft > 0 /\ ~err
  /\ LET rp1 == IF Mutant = "no_reopen_reset" THEN rp ELSE {}
         cand == {p \in Parts : ~loaded \/ p \notin rp1}
     IN /\ rp' = rp1
        /\ IF cand = {}
             THEN /\ err' = TRUE /\ cur' = 0 /\ started' = FALSE /\ pc' = "done"
                  /\ UNCHANGED << row, blk, em, reads >>
             ELSE /\ cur' = Min(cand) /\ started' = TRUE /\ row' = 1 /\ blk' = 1 /\ pc' = "reset"
                  /\ em' = [x \in Rows |-> Zero] /\ reads' = [x \in Rows |-> 0] /\ UNCHANGED err
  /\ execLeft' = execLeft - 1 /\ pos' = FALSE /\ sf' = FALSE /\ nf' = FALSE /\ currNull' = FALSE
  \* the execution builds its memo storage again (or none)
  /\ memoOn' \in BOOLEAN /\ memoRec' = [k \in Keys |-> Zero] /\ memoDone' = [k \in Keys |-> FALSE]
  /\ UNCHANGED << Input, pending, loaded, opened, hit >>

\* the memo storage is dropped (budget or hit-ratio check): later rows are not memoized
MemoDrop ==
  /\ memoOn /\ pc # "done"
  /\ memoOn' = FALSE
  /\ UNCHANGED << Input, row, pc, execLeft, blk, cur, started, pos, sf, nf, pending, loaded, rp, currNull, em,
                  memoRec, memoDone, reads, opened, hit, err >>

Finished == pc = "done" /\ (execLeft = 0 \/ err) /\ UNCHANGED vars

Next == Reset \/ Enter \/ OpenRow \/ Loop \/ RowEnd \/ Reopen \/ MemoDrop \/ Finished
Spec == Init /\ [][Next]_vars /\ WF_vars(Reset \/ Enter \/ OpenRow \/ Loop \/ RowEnd \/ Reopen)

\* inductive invariant, conjunct by conjunct (cubrid-tla P15)
Bit == 0..1
\* TypeOK with the counters bounded: the correct variant never returns a row twice
TypeB ==
  /\ kind \in Kinds /\ prune \in BOOLEAN /\ home \in [Keys -> 0..NP] /\ data \in [Parts -> SUBSET Keys]
  /\ outer \in [Rows -> Keys] /\ memoOn \in BOOLEAN /\ row \in Rows
  /\ pc \in {"reset", "enter", "open", "loop", "rowend", "done"}
  /\ execLeft \in 0..NExec /\ blk \in Parts /\ cur \in 0..NP
  /\ started \in BOOLEAN /\ pos \in BOOLEAN /\ sf \in BOOLEAN /\ nf \in BOOLEAN /\ pending \in BOOLEAN
  /\ loaded \in BOOLEAN /\ rp \in SUBSET Parts /\ currNull \in BOOLEAN
  /\ em \in [Rows -> [Slots -> Bit]] /\ memoRec \in [Keys -> [Slots -> Bit]] /\ memoDone \in [Keys -> BOOLEAN]
  /\ reads \in [Rows -> Bit] /\ opened \in SUBSET Parts /\ hit \in BOOLEAN /\ err \in BOOLEAN
\* the rows of the walk so far: the partitions before cur, and cur once it returned its row
Seen(p) == p < cur \/ (p = cur /\ pos)
PartialIn == [s \in Slots |-> IF s > 0 /\ Key \in data[s] /\ Seen(s) THEN 1 ELSE 0]
NoMatchSeen == \A p \in Parts : Seen(p) => Key \notin data[p]
R_rows == \A x \in Rows : /\ x < row => em[x] = Exp(outer[x]) /\ reads[x] = 1
                          /\ x > row => em[x] = Zero /\ reads[x] = 0
R_reads == reads[row] = IF pc = "reset" THEN 0 ELSE 1
R_pre == /\ pc \in {"reset", "enter", "open"} => em[row] = Zero
         /\ pc \in {"enter", "open"} => ~hit /\ opened = {}
R_open == /\ pc \in {"enter", "open"} => pending
          /\ pc = "open" => (memoOn /\ ~memoDone[Key] => memoRec[Key] = Zero)
R_end == pc \in {"rowend", "done"} => em[row] = Exp(Key)
R_done == pc = "done" => row = NR
R_hit == hit => opened = {} /\ pc \in {"rowend", "done", "reset"}
R_rp == pc \in {"loop", "rowend"} /\ ~hit => \A p \in Parts : loaded /\ p \in rp => Key \notin data[p]
R_prune == pc \in {"loop", "rowend"} /\ prune /\ ~hit =>
             /\ loaded
             /\ \/ rp = Parts \ {home[Key]}
                \/ home[Key] \notin Parts /\ kind \in {"left", "anti"} /\ rp = Parts \ {1}
                \/ home[Key] \notin Parts /\ rp = {}
R_loaded == loaded => prune
R_opened == pc \in {"loop", "rowend"} /\ prune => PruneOK
R_loop == pc = "loop" =>
  /\ cur \in Parts /\ started /\ ~pending /\ ~hit /\ ~currNull
  /\ pos => Key \in data[cur]
R_inner == pc = "loop" /\ kind = "inner" => em[row] = PartialIn /\ ~nf
R_left == pc = "loop" /\ kind = "left" =>
  /\ em[row] = [s \in Slots |-> IF s = 0 THEN (IF nf THEN 1 ELSE 0) ELSE PartialIn[s]]
  /\ sf = (nf \/ \E p \in Parts : PartialIn[p] = 1)
  /\ nf => Matches(Key) = {} /\ ~pos /\ ~HasNext
R_semi == pc = "loop" /\ kind = "semi" =>
  /\ em[row] = [s \in Slots |-> IF s = 0 /\ sf THEN 1 ELSE 0] /\ ~nf
  /\ sf => pos
  /\ ~sf => NoMatchSeen
R_anti == pc = "loop" /\ kind = "anti" =>
  \/ em[row] = Zero /\ ~sf /\ ~nf /\ ~pos /\ NoMatchSeen
  \* re-entered after the row went through
  \/ sf /\ em[row] = Exp(Key) /\ Matches(Key) = {} /\ ~HasNext /\ (memoOn => memoDone[Key])
R_memo == pc = "loop" /\ memoOn /\ ~memoDone[Key] /\ ~(kind = "anti" /\ sf) =>
            memoRec[Key] = (IF kind = "anti" THEN Zero ELSE em[row])
IndInv ==
  /\ TypeB
  /\ prune => \A p \in Parts : \A k \in data[p] : home[k] = p
  /\ MemoSound /\ NoReopenError /\ HitOpensNone /\ NoRootBlock
  /\ R_rows /\ R_reads /\ R_pre /\ R_open /\ R_end /\ R_done /\ R_hit /\ R_rp /\ R_prune /\ R_loaded /\ R_opened
  /\ R_loop /\ R_inner /\ R_left /\ R_semi /\ R_anti /\ R_memo

\* the safety claims follow from IndInv

(* Apalache's constant initialization for PartWalk.apalache-indinv.cfg: the sizes of the main cfg,
   every state of IndInv at once (TLC's inductive cfg enumerates the smallest sizes) *)
CInit == NP = 2 /\ NR = 2 /\ NK = 2 /\ NExec = 1 /\ Mutant = "none"
=============================================================================
