---------------------------- MODULE PxClearLists ----------------------------
(***************************************************************************)
(* PR 8436 (CBRD-27959) review model, head 1e5fcd7ca.  A UNION ALL whose   *)
(* arms each hold a correlated IN subquery.  Parallel subquery execution   *)
(* runs arm 1 on the request thread and every later arm on a worker        *)
(* (px_query_execute); serial execution runs the arms one after another on *)
(* the request thread.  Per outer row an arm executes its subquery NI      *)
(* times: each execution destroys the subquery's previous list file        *)
(* (qexec_clear_head_lists_with_truncate) and creates a new one, which the *)
(* IN check then reads.  At the end of the row qexec_intprt_fnc calls      *)
(* qexec_clear_all_lists on the arm: the head clears the arm's own         *)
(* subquery list; develop also walked arm->next, the next arm, and         *)
(* destroyed that arm's list (Mutant "develop").  After every arm ended,   *)
(* qexec_execute_query -> qexec_clear_xasl destroys what is left.  Temp    *)
(* files are reused once freed, so a stale reference reads another list.   *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets, TLC

CONSTANTS NA, NR, NI, NF, Parallel, Mutant
ASSUME NA \in 2..3 /\ NR \in 1..3 /\ NI \in 1..3 /\ NF \in 1..6
ASSUME Parallel \in BOOLEAN
ASSUME Mutant \in {"none", "develop", "no-own-clear", "row-keep-id", "trunc-no-free", "no-final"}

\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: NA Int
\* apalache-type: NR Int
\* apalache-type: NI Int
\* apalache-type: NF Int
\* apalache-type: Parallel Bool
\* apalache-type: Mutant Str
\* apalache-type: pc Int -> Str
\* apalache-type: row Int -> Int
\* apalache-type: ex Int -> Int
\* apalache-type: cur Int -> Int
\* apalache-type: held Int -> Int
\* apalache-type: owner Int -> Int
\* apalache-type: final Bool
\* apalache-type: uaf Bool
\* apalache-type: dbl Bool

Arms == 1..NA
Files == 1..NF
None == 0
Free == 0

VARIABLES pc,     \* [Arms -> {"wait","exec","create","use","endrow","rowdone","done"}]
  row,    \* outer rows done
  ex,     \* subquery executions done in this row
  cur,    \* the subquery's list_id (shared XASL memory): its temp file, or None
  held,   \* the file the arm's IN check reads (its last creation)
  owner,  \* [Files -> Arms \cup {Free}]
  final,  \* qexec_clear_xasl done
  uaf,    \* ghost: a read of a file another list owns or nobody owns
  dbl     \* ghost: a free of a free file


vars == <<pc, row, ex, cur, held, owner, final, uaf, dbl>>

\* serial: arm a starts when arm a-1 is done; parallel: all start at once
CanStart(a) == IF Parallel \/ a = 1 THEN TRUE ELSE pc[a - 1] = "done"

Init ==
  /\ pc = [a \in Arms |-> "wait"] /\ row = [a \in Arms |-> 0] /\ ex = [a \in Arms |-> 0]
  /\ cur = [a \in Arms |-> None] /\ held = [a \in Arms |-> None]
  /\ owner = [f \in Files |-> Free] /\ final = FALSE /\ uaf = FALSE /\ dbl = FALSE

\* @type: (Int -> Int, Int) => (Int -> Int);
FreeF(o, f) == IF f = None THEN o ELSE [o EXCEPT ![f] = Free]
\* @type: (Int -> Int, Int) => Bool;
DblF(o, f) == f # None /\ o[f] = Free

Start(a) ==
  /\ pc[a] = "wait" /\ CanStart(a)
  /\ pc' = [pc EXCEPT ![a] = IF NR = 0 THEN "done" ELSE "exec"]
  /\ UNCHANGED <<row, ex, cur, held, owner, final, uaf, dbl>>

(* qexec_execute_dptr_list (truncate) -> qexec_clear_head_lists_with_truncate -> qexec_clear_xasl_head: the
   subquery's previous list is destroyed *)
Trunc(a) ==
  /\ pc[a] = "exec"
  /\ owner' = IF Mutant = "trunc-no-free" THEN owner ELSE FreeF(owner, cur[a])
  /\ dbl' = (dbl \/ (Mutant # "trunc-no-free" /\ DblF(owner, cur[a])))
  /\ cur' = [cur EXCEPT ![a] = None]
  /\ pc' = [pc EXCEPT ![a] = "create"]
  /\ UNCHANGED <<row, ex, held, final, uaf>>

(* the subquery's qexec_execute_mainblock: a new list on a free temp file (qmgr reuses freed files) *)
Create(a) ==
  /\ pc[a] = "create"
  /\ \E f \in Files :
       /\ owner[f] = Free
       /\ owner' = [owner EXCEPT ![f] = a]
       /\ cur' = [cur EXCEPT ![a] = f]
       /\ held' = [held EXCEPT ![a] = f]
  /\ pc' = [pc EXCEPT ![a] = "use"]
  /\ UNCHANGED <<row, ex, final, uaf, dbl>>

(* the IN check reads the list it just made (eval_pred over the list scan) *)
Use(a) ==
  /\ pc[a] = "use"
  /\ uaf' = (uaf \/ owner[held[a]] # a)
  /\ ex' = [ex EXCEPT ![a] = ex[a] + 1]
  /\ pc' = [pc EXCEPT ![a] = IF ex[a] + 1 < NI THEN "exec" ELSE "endrow"]
  /\ UNCHANGED <<row, cur, held, owner, final, dbl>>

(* qexec_intprt_fnc: qexec_clear_all_lists (arm) -> qexec_clear_scan_all_lists -> qexec_clear_head_lists: the arm's
   own subquery list; develop also cleared arm->next, the next arm's subquery list *)
NextArm(a) == IF a < NA /\ Mutant = "develop" THEN a + 1 ELSE None
EndRow(a) ==
  /\ pc[a] = "endrow"
  /\ LET own == IF Mutant = "no-own-clear" THEN None ELSE cur[a]
         o1 == FreeF(owner, own)
         nx == NextArm(a)
         nf == IF nx = None THEN None ELSE cur[nx]
     IN /\ owner' = FreeF(o1, nf)
        /\ dbl' = (dbl \/ DblF(owner, own) \/ DblF(o1, nf))
        \* row-keep-id: the clear destroys the file but leaves the list_id naming it
        /\ cur' = [b \in Arms |-> IF (b = a /\ own # None /\ Mutant # "row-keep-id") \/ (nx # None /\ b = nx)
                                  THEN None ELSE cur[b]]
  /\ pc' = [pc EXCEPT ![a] = "rowdone"]
  /\ UNCHANGED <<row, ex, held, final, uaf>>

RowDone(a) ==
  /\ pc[a] = "rowdone"
  /\ row' = [row EXCEPT ![a] = row[a] + 1]
  /\ ex' = [ex EXCEPT ![a] = 0]
  /\ pc' = [pc EXCEPT ![a] = IF row[a] + 1 < NR THEN "exec" ELSE "done"]
  /\ UNCHANGED <<cur, held, owner, final, uaf, dbl>>

(* qexec_execute_query -> qexec_clear_xasl, on the request thread after every arm ended *)
Final ==
  /\ ~final /\ \A a \in Arms : pc[a] = "done"
  /\ Mutant # "no-final"
  /\ owner' = [f \in Files |-> IF \E a \in Arms : cur[a] = f THEN Free ELSE owner[f]]
  /\ cur' = [a \in Arms |-> None]
  /\ final' = TRUE
  /\ UNCHANGED <<pc, row, ex, held, uaf, dbl>>

Finished == final /\ UNCHANGED vars

Next == \/ \E a \in Arms : Start(a) \/ Trunc(a) \/ Create(a) \/ Use(a) \/ EndRow(a) \/ RowDone(a)
        \/ Final \/ Finished
Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)
Pcs == {"wait", "exec", "create", "use", "endrow", "rowdone", "done"}
TypeOK ==
  /\ pc \in [Arms -> Pcs] /\ row \in [Arms -> 0..3] /\ ex \in [Arms -> 0..3]   \* 3: the largest NR, NI (ASSUME)
  /\ \A a \in Arms : row[a] >= 0 /\ row[a] <= NR /\ ex[a] >= 0 /\ ex[a] <= NI
  /\ cur \in [Arms -> Files \cup {None}] /\ held \in [Arms -> Files \cup {None}]
  /\ owner \in [Files -> Arms \cup {Free}] /\ final \in BOOLEAN /\ uaf \in BOOLEAN /\ dbl \in BOOLEAN

\* C1: the IN check of an arm reads the list it made for this row (no use of a freed or reused temp file)
NoUseAfterFree == ~uaf
\* C2: no temp file is freed twice
NoDoubleFree == ~dbl
\* C3: after its per-row clear an arm holds no subquery list (qexec_clear_all_lists' purpose)
RowClean == \A a \in Arms : pc[a] = "rowdone" => cur[a] = None
\* C4: the query leaves no temp file behind
NoLeak == final => \A f \in Files : owner[f] = Free

\* the files an arm holds are its own: the structure the safety properties rest on
OwnsCur == \A a \in Arms : cur[a] # None => owner[cur[a]] = a
Distinct == \A a, b \in Arms : a # b /\ cur[a] # None => cur[a] # cur[b]
OnlyCur == \A f \in Files : owner[f] # Free => cur[owner[f]] = f
IndInv ==
  /\ TypeOK /\ NoUseAfterFree /\ NoDoubleFree /\ RowClean /\ NoLeak
  /\ OwnsCur /\ OnlyCur
  /\ \A a \in Arms : pc[a] = "use" => held[a] = cur[a] /\ cur[a] # None
  /\ \A a \in Arms : pc[a] \in {"wait", "done"} => cur[a] = None
  /\ \A a \in Arms : pc[a] = "create" => cur[a] = None
  /\ \A a \in Arms : ~Parallel /\ pc[a] # "wait" => \A b \in Arms : b < a => pc[b] = "done"
  /\ \A a \in Arms : pc[a] = "wait" => row[a] = 0 /\ ex[a] = 0
  /\ \A a \in Arms : pc[a] \in {"exec", "create", "use"} => ex[a] < NI /\ row[a] < NR
  /\ \A a \in Arms : pc[a] \in {"endrow", "rowdone"} => ex[a] = NI /\ row[a] < NR
  /\ \A a \in Arms : pc[a] = "done" => ex[a] = 0 /\ row[a] = NR
  /\ final => \A a \in Arms : pc[a] = "done"

Terminates == <>final

\* witnesses
NotTwoActive == ~(\E a, b \in Arms : a # b /\ pc[a] = "use" /\ pc[b] = "use")

\* Apalache: the integer constants over their ranges, two arms and three files (the domains must be fixed)
CInit == NA = 2 /\ NF = 3 /\ NR \in 1..3 /\ NI \in 1..3 /\ Parallel \in BOOLEAN /\ Mutant = "none"
=============================================================================
