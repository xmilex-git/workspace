------------------------------ MODULE PxCteFirst ------------------------------
(* The order of the aptrs of one block that has a parallel subquery executor, against the list
   files they read (CBRD-28126, review of PR #8556, 2026-11-18). A CTE's list is read by its
   siblings; the design runs every CTE of the block on the dispatching thread before the first
   sibling becomes a job, so a reference to a CTE no longer keeps the statement serial, and the
   checker reads the list scans of the subqueries a joined scan evaluates per row.
   An aptr "starts" when it opens the lists it reads: a reader that starts before its producer
   ended reads a list that is empty or being written (bad). *)
EXTENDS Naturals, FiniteSets

CONSTANTS Shapes, Dispatch, Checker, Workers

\* apalache-type: Shapes Set(Str)
\* apalache-type: Dispatch Str
\* apalache-type: Checker Str
\* apalache-type: Workers Set(Str)
\* apalache-type: sh Str
\* apalache-type: st Int -> Str
\* apalache-type: mpc Str
\* apalache-type: i Int
\* apalache-type: q Set(Int)
\* apalache-type: mjob Int
\* apalache-type: mcur Int
\* apalache-type: wcur Str -> Int
\* apalache-type: added Set(Int)
\* apalache-type: bad Bool

VARIABLES sh, st, mpc, i, q, mjob, mcur, wcur, added, bad

vars == <<sh, st, mpc, i, q, mjob, mcur, wcur, added, bad>>

U == 1..4                                   \* the aptr slots of the block, in aptr list order

(* The shapes. An aptr reads <<r, p>>: r opens the list p writes. Hidden reads sit in a subquery
   that a joined scan of r evaluates per row (scan_ptr->dptr_list / fptr_list), which develop's
   checker does not visit.
     q5o  : c; q reads c from a joined scan's correlated subquery; o reads nothing (the repro)
     q0   : c; q and o read c directly (derived tables over the CTE)
     cte2 : c1; c2 reads c1; q reads c2 from a joined scan; o
     late : o; q reads c from a joined scan; c last (an order the generator does not make)
     hid  : x (no CTE); q reads x from a joined scan; o
     c1q  : c; q reads c *)
Present == CASE sh = "cte2" -> 1..4
           [] sh = "c1q"  -> 1..2
           [] OTHER       -> 1..3

Cte == CASE sh = "cte2" -> {1, 2}
       [] sh = "late" -> {3}
       [] sh = "hid"  -> {}
       [] OTHER       -> {1}

\* @type: Set(<<Int, Int>>);
Reads == CASE sh = "q5o"  -> {<<2, 1>>}
         [] sh = "q0"   -> {<<2, 1>>, <<3, 1>>}
         [] sh = "cte2" -> {<<2, 1>>, <<3, 2>>}
         [] sh = "late" -> {<<2, 3>>}
         [] sh = "hid"  -> {<<2, 1>>}
         [] OTHER       -> {<<2, 1>>}

\* @type: Set(<<Int, Int>>);
Hidden == CASE sh = "q5o"  -> {<<2, 1>>}
          [] sh = "cte2" -> {<<3, 2>>}
          [] sh = "late" -> {<<2, 3>>}
          [] sh = "hid"  -> {<<2, 1>>}
          [] OTHER       -> {}

(* The checker (px_query_checker.cpp), decided once before execution.
     develop          : no visit of a joined scan's subqueries; any sibling read blocks; CTEs count
     visit_only       : visits them; any sibling read blocks; CTEs count
     cte_ok_no_visit  : a read of a CTE does not block, CTEs do not count; no visit
     cte_ok_count_all : visits, a read of a CTE does not block, but CTEs count as jobs
     visit_cte_ok     : the design: visits, a read of a CTE does not block, only non-CTEs count *)
\* @type: Set(<<Int, Int>>);
Visible == IF Checker \in {"develop", "cte_ok_no_visit"} THEN Reads \ Hidden ELSE Reads

\* @type: Set(<<Int, Int>>);
Blocking == IF Checker \in {"develop", "visit_only"} THEN Visible
            ELSE {e \in Visible : e[2] \notin Cte}

Counted == IF Checker \in {"visit_cte_ok", "cte_ok_no_visit"} THEN Present \ Cte ELSE Present

Parallel == Cardinality(Counted) >= 2 /\ Blocking = {}

(* The dispatch (query_executor.c, the aptr loop of qexec_execute_mainblock_internal).
     develop      : every aptr of a parallel block is a job, a CTE too
     cte_first    : the design: every CTE runs inline, in list order, before the first job
     cte_in_place : a CTE runs inline where the list order meets it, the others are jobs *)
AsJob(a) == Parallel /\ (Dispatch = "develop" \/ a \notin Cte)

\* a started aptr opens the lists it reads
Open(a) == /\ st' = [st EXCEPT ![a] = "run"]
           /\ bad' = (bad \/ \E e \in Reads : e[1] = a /\ st[e[2]] # "done")

\* add_job: the first job is kept for run_jobs' caller, the others go to the queue
Add(a) == /\ added' = added \cup {a}
          /\ IF mjob = 0 THEN mjob' = a /\ q' = q ELSE q' = q \cup {a} /\ mjob' = mjob

Init == /\ sh \in Shapes
        /\ st = [a \in U |-> IF a \in Present THEN "init" ELSE "done"]
        /\ mpc = IF Parallel /\ Dispatch = "cte_first" THEN "pre" ELSE "disp"
        /\ i = 1 /\ q = {} /\ mjob = 0 /\ mcur = 0
        /\ wcur = [w \in Workers |-> 0] /\ added = {} /\ bad = FALSE

\* cte_first: the CTEs of the block, in list order, on the dispatching thread
MainPre == /\ mpc = "pre" /\ mcur = 0
           /\ IF i > 4 THEN mpc' = "disp" /\ i' = 1 /\ UNCHANGED <<st, bad, mcur>>
              ELSE IF i \in Cte THEN mcur' = i /\ Open(i) /\ i' = i + 1 /\ UNCHANGED mpc
              ELSE i' = i + 1 /\ UNCHANGED <<st, bad, mcur, mpc>>
           /\ UNCHANGED <<sh, q, mjob, wcur, added>>

\* the dispatch loop: an aptr that already ran is skipped, a job is added, the rest runs inline
MainDisp == /\ mpc = "disp" /\ mcur = 0
            /\ \/ i > 4 /\ mpc' = "runm" /\ UNCHANGED <<st, bad, i, q, mjob, mcur, added>>
               \/ i <= 4 /\ st[i] # "init" /\ i' = i + 1 /\ UNCHANGED <<mpc, st, bad, q, mjob, mcur, added>>
               \/ i <= 4 /\ st[i] = "init" /\ AsJob(i) /\ Add(i) /\ i' = i + 1 /\ UNCHANGED <<mpc, st, bad, mcur>>
               \/ i <= 4 /\ st[i] = "init" /\ ~AsJob(i) /\ mcur' = i /\ Open(i) /\ i' = i + 1
                  /\ UNCHANGED <<mpc, q, mjob, added>>
            /\ UNCHANGED <<sh, wcur>>

\* run_jobs: the kept job, then queued jobs, then wait until every added job ended
MainRun == /\ mpc = "runm" /\ mcur = 0
           /\ IF mjob # 0 THEN mcur' = mjob /\ mjob' = 0 /\ Open(mjob) /\ UNCHANGED <<q, mpc>>
              ELSE IF q # {} THEN \E a \in q : q' = q \ {a} /\ mcur' = a /\ Open(a) /\ UNCHANGED <<mjob, mpc>>
              ELSE (\A a \in added : st[a] = "done") /\ mpc' = "fin" /\ UNCHANGED <<st, bad, q, mjob, mcur>>
           /\ UNCHANGED <<sh, i, wcur, added>>

MainEnd == /\ mcur # 0
           /\ st' = [st EXCEPT ![mcur] = "done"] /\ mcur' = 0
           /\ UNCHANGED <<sh, mpc, i, q, mjob, wcur, added, bad>>

\* a worker pops a queued job at any time after its push (a superset of the code, where the
\* workers start with the root's run_jobs)
WorkerPop(w) == /\ wcur[w] = 0
                /\ \E a \in q : q' = q \ {a} /\ wcur' = [wcur EXCEPT ![w] = a] /\ Open(a)
                /\ UNCHANGED <<sh, mpc, i, mjob, mcur, added>>

WorkerEnd(w) == /\ wcur[w] # 0
                /\ st' = [st EXCEPT ![wcur[w]] = "done"] /\ wcur' = [wcur EXCEPT ![w] = 0]
                /\ UNCHANGED <<sh, mpc, i, q, mjob, mcur, added, bad>>

Done == mpc = "fin" /\ UNCHANGED vars

Next == \/ MainPre \/ MainDisp \/ MainRun \/ MainEnd
        \/ \E w \in Workers : WorkerPop(w) \/ WorkerEnd(w)
        \/ Done

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
St == {"init", "run", "done"}

TypeOK == /\ sh \in Shapes /\ st \in [U -> St] /\ mpc \in {"pre", "disp", "runm", "fin"}
          /\ i \in 1..5 /\ q \subseteq U /\ mjob \in 0..4 /\ mcur \in 0..4
          /\ wcur \in [Workers -> 0..4] /\ added \subseteq U /\ bad \in BOOLEAN

\* C7: no aptr opens a list before the aptr writing it ended
NoEarlyRead == ~bad

\* C8: a block whose siblings read nothing but CTEs keeps its executor
ParallelKept == sh \in {"q0", "q5o", "cte2"} => Parallel

\* C9: a block gets an executor only for two jobs or more
JobsAtLeastTwo == Parallel => Cardinality({a \in Present : AsJob(a)}) >= 2

\* C10: the block ends with every aptr ended
AllEndedAtFin == mpc = "fin" => \A a \in U : st[a] = "done"

\* witness: two non-CTE siblings run at once after the CTEs
NotOverlap == ~(\E a, b \in Present \ Cte : a # b /\ st[a] = "run" /\ st[b] = "run")

-----------------------------------------------------------------------------
\* the inductive invariant of the design (Dispatch "cte_first", Checker "visit_cte_ok")
ShapeOrder == \A e \in Reads : (~Parallel \/ e[1] \in Cte) => e[2] < e[1]
OnlyCteRead == Parallel => \A e \in Reads : e[2] \in Cte
Absent == \A a \in U \ Present : st[a] = "done" /\ a \notin added /\ a # mcur /\ a # mjob
StartedReadDone == \A a \in U : st[a] # "init" => \A e \in Reads : e[1] = a => st[e[2]] = "done"
Running == \A a \in U : st[a] = "run" <=> (a = mcur \/ \E w \in Workers : wcur[w] = a)
WorkersDistinct == /\ \A w1, w2 \in Workers : (w1 # w2 /\ wcur[w1] # 0) => wcur[w1] # wcur[w2]
                   /\ mcur # 0 => \A w \in Workers : wcur[w] # mcur
WorkerJobs == \A w \in Workers : wcur[w] # 0 => wcur[w] \in added
JobBook == /\ q \subseteq added /\ (mjob # 0 => mjob \in added /\ st[mjob] = "init")
           /\ mjob \notin q /\ \A a \in q : st[a] = "init"
           /\ \A a \in added : st[a] = "init" => (a \in q \/ a = mjob)
MjobFirst == q # {} => mjob # 0 \/ mpc \in {"runm", "fin"}
PreOnlyParallel == mpc = "pre" => Parallel
Pre == mpc = "pre" => /\ q = {} /\ mjob = 0 /\ added = {} /\ \A w \in Workers : wcur[w] = 0
                      /\ \A a \in Present : ((a >= i /\ a # mcur) \/ a \notin Cte) => st[a] = "init"
                      /\ \A c \in Cte : (c < i /\ c # mcur) => st[c] = "done"
                      /\ (mcur # 0 => mcur \in Cte /\ mcur = i - 1)
PostPre == (Parallel /\ mpc # "pre") => \A c \in Cte : st[c] = "done" /\ c \notin added
ParDisp == (Parallel /\ mpc = "disp") => /\ mcur = 0
                                         /\ \A a \in Present \ Cte : /\ (a >= i => st[a] = "init" /\ a \notin added)
                                                                    /\ (a < i => a \in added)
ParRun == (Parallel /\ mpc \in {"runm", "fin"}) => i = 5 /\ added = Present \ Cte
Serial == ~Parallel => /\ q = {} /\ mjob = 0 /\ added = {} /\ \A w \in Workers : wcur[w] = 0
                       /\ mpc # "pre"
                       /\ (mpc = "disp" => /\ \A a \in Present : (a < i /\ a # mcur) => st[a] = "done"
                                           /\ \A a \in Present : a >= i => st[a] = "init"
                                           /\ (mcur # 0 => mcur = i - 1))
                       /\ (mpc \in {"runm", "fin"} => mcur = 0 /\ i = 5 /\ \A a \in U : st[a] = "done")

IndInv ==
  /\ TypeOK
  /\ NoEarlyRead
  /\ ShapeOrder
  /\ OnlyCteRead
  /\ Absent
  /\ StartedReadDone
  /\ Running
  /\ WorkersDistinct
  /\ WorkerJobs
  /\ JobBook
  /\ MjobFirst
  /\ PreOnlyParallel
  /\ Pre
  /\ PostPre
  /\ ParDisp
  /\ ParRun
  /\ Serial
  /\ AllEndedAtFin

\* Apalache's inductive check: every state IndInv admits, one step
IndInit == /\ sh \in Shapes /\ st \in [U -> St] /\ mpc \in {"pre", "disp", "runm", "fin"} /\ i \in 1..5
           /\ q \in SUBSET U /\ mjob \in 0..4 /\ mcur \in 0..4 /\ wcur \in [Workers -> 0..4]
           /\ added \in SUBSET U /\ bad \in BOOLEAN /\ IndInv
=============================================================================
