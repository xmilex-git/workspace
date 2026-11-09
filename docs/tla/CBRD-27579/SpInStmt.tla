------------------------------ MODULE SpInStmt ------------------------------
(* CBRD-27579: what a stored procedure (SP) may do, judged by where it was invoked, and what else
   the engine must hold so that none of the linked defects (CBRD-27590, 27591, 27603, 27614)
   can happen.

   An SP runs on the PL server; its SQL, COMMIT and ROLLBACK come back to the client as callbacks
   while the client waits for a server request.  req[1..dep] are the requests the callbacks of
   each nesting level arrive under: "stmt" a query execution, "call" the PL_CALL of a CALL
   statement, "expr" a client-evaluated SP expression; trig marks a trigger condition or action
   running below them.

   One outer statement is in progress for every top except "call":
     stmtT    SELECT f (x) FROM t x: single-table scan (innermost block: fixed candidate);
              plan: heap, index scan (OID buffer), or a materialized inline view (list)
     stmtTnl  SELECT /*+ ordered use_nl */ ..., f (x) FROM t x, t_one: driving scan (cached candidate)
     stmtS    SELECT s.name, f () FROM db_serial s
     stmtSnl  the same as the NL driving scan
     stmtSnv  the NL scan of db_serial with s_b.NEXT_VALUE in the select list, no SP (CBRD-27590)
     trigCall / trigExpr  the write phase of UPDATE t whose row trigger runs CALL p () / evaluates
              the condition f () on the client
   The scanned class has N rows on one page; heap[r] is row r's version (0 = deleted), copy[r]
   what a cached page copy, a list file or an OID buffer holds.  On db_serial, row N is s_b,
   which NEXT_VALUE bumps.

   Off names the protections a cfg removes; Off = {} is the design.
     G1 / G1t  rule 1: TCL and DDL rejected inside a SQL statement / a trigger     (PR 8182)
     G2        rule 2: DML rejected inside a SQL statement                         (PR 8182)
     CLS-SA, CLS-EXPR, CLS-INHERIT, EXEC  PR 8182's classification: the SA request flag, the
               expression call, the inherited depth, the decision at execute    (PR 8182)
     P2  no page latch held across an SP call: no fixed scan in a block that calls an SP
     P3  a unilateral abort raised while a statement is in progress waits until that statement
         has unwound; meanwhile every request of the transaction fails
     P4  no cached scan of db_serial in a statement that can write it (NEXT_VALUE or an SP)
     DML-IN-TRIG  not a protection: the over-strict variant that also rejects DML in a trigger
         action's CALL (the mutant of C3)
   PR 8182 at 0f920af80 = Off {"P2", "P3", "P4"}. *)
EXTENDS Naturals

CONSTANTS N, MaxD, K, Off, Tops, Modes
\* apalache-type: N Int
\* apalache-type: MaxD Int
\* apalache-type: K Int
\* apalache-type: Off Set(Str)
\* apalache-type: Tops Set(Str)
\* apalache-type: Modes Set(Str)

AllTops == {"call", "stmtT", "stmtTnl", "stmtS", "stmtSnl", "stmtSnv", "trigCall", "trigExpr"}
StmtTops == {"stmtT", "stmtTnl", "stmtS", "stmtSnl", "stmtSnv"}
TrigTops == {"trigCall", "trigExpr"}
SerialTops == {"stmtS", "stmtSnl", "stmtSnv"}
TTops == {"stmtT", "stmtTnl"}
Prot == {"G1", "G1t", "G2", "CLS-SA", "CLS-EXPR", "CLS-INHERIT", "EXEC", "P2", "P3", "P4", "DML-IN-TRIG"}

ASSUME Assm == /\ N \in Nat /\ N >= 2 /\ MaxD \in Nat /\ MaxD >= 1 /\ K \in Nat /\ K >= 1
               /\ Off \subseteq Prot /\ Tops \subseteq AllTops
               /\ Modes \subseteq {"CS", "SA"}

\* Leaf SQL of an SP.  delT / updT write the next row of t, dmlU another table, nextval bumps
\* s_b, url is DML through a Java URL connection (another transaction), lockwait is a SELECT
\* that waits on another transaction's lock and becomes the deadlock victim.
Leaf == {"selT", "delT", "updT", "dmlU", "commit", "ddlT", "nextval", "url", "lockwait"}
Nest == {"callG", "selG"}
Cat(o) == IF o \in {"delT", "updT", "dmlU"} THEN "DML"
          ELSE IF o = "commit" THEN "TCL"
          ELSE IF o = "ddlT" THEN "DDL"
          ELSE "OTHER"

BadTags == {"ruleBreakTCL", "ruleBreakDDL", "ruleBreakDML", "overReject", "txnEndMid",
            "useAfterEnd", "ddlMid", "selfWait", "crossWait", "stale", "dangling"}
EvTags == {"dmlCall", "dmlTrig", "rejDmlSql", "rejDmlNested", "rejTclTrig", "rejDdlSql",
           "nestThenAllowed", "nextvalSql", "urlSql", "selSql", "tclCall", "caught", "stmtDone",
           "abortDeferred", "writeSkipsDeleted", "directNextval", "victimSql"}

VARIABLES mode, top, acc, pos, heap, copy, emitted, ph, req, dep, left, err, trig,
          tempOk, snapOk, abortPend, failed, prep, bad, ev
\* apalache-type: mode Str
\* apalache-type: top Str
\* apalache-type: acc Str
\* apalache-type: pos Int
\* apalache-type: heap Int -> Int
\* apalache-type: copy Int -> Int
\* apalache-type: emitted Set(Int)
\* apalache-type: ph Str
\* apalache-type: req Int -> Str
\* apalache-type: dep Int
\* apalache-type: left Int -> Int
\* apalache-type: err Bool
\* apalache-type: trig Bool
\* apalache-type: tempOk Bool
\* apalache-type: snapOk Bool
\* apalache-type: abortPend Bool
\* apalache-type: failed Bool
\* apalache-type: prep Str -> Str
\* apalache-type: bad Set(Str)
\* apalache-type: ev Set(Str)

vars == <<mode, top, acc, pos, heap, copy, emitted, ph, req, dep, left, err, trig,
          tempOk, snapOk, abortPend, failed, prep, bad, ev>>

Depths == 1..MaxD
Rows == 1..N
Cls == IF top \in SerialTops THEN "S" ELSE "T"
HasSP == top # "stmtSnv"

\* ---- scan choice (query_executor.c qexec_execute_mainblock_internal, qexec_is_cached_scan_eligible)
\* fixed: the innermost scan block unless XASL_NO_FIXED_SCAN (set for a serial operator,
\* xasl_generation.c); P2 adds "the block calls an SP".  cached: the level-0 driving scan when not
\* fixed; P4 refuses it for db_serial when the statement can write db_serial.
ScanMode(t, plan) ==
  LET innermost == t \in {"stmtT", "stmtS"}
      sp == t # "stmtSnv"
      fixedOK == innermost /\ sp /\ "P2" \in Off
      cachedOK == t \in TTops \/ "P4" \in Off
  IN IF plan = "index" THEN "index"
     ELSE IF plan = "list" THEN "list"
     ELSE IF fixedOK THEN "fixed"
     ELSE IF cachedOK THEN "cached"
     ELSE "plain"
Plans(t) == IF t = "stmtT" THEN {"heap", "index", "list"} ELSE {"heap"}

\* the outer fixed scan keeps the page latched while the SP of the row runs
Latched == acc = "fixed" /\ ph = "sp"

\* ---- the rule (JIRA body, "1. 규칙" and its table)
InSqlRule == \E i \in Depths : i <= dep /\ req[i] \in {"stmt", "expr"}
RuleAllows(c) == IF c \in {"TCL", "DDL"} THEN ~InSqlRule /\ ~trig
                 ELSE IF c = "DML" THEN ~InSqlRule
                 ELSE TRUE

\* ---- PR 8182's classification
\* sp_In_sql_depth counts callbacks dispatched under a query-execution request (network_cl.c
\* net_client_request_with_callback; SA: query_method.cpp method_dispatch under
\* sp_Sa_query_request) and client-evaluated expression calls (jsp_cl.cpp PT_IS_MTHD_EXPR);
\* sp_In_trigger_depth counts trigger_manager.c execute_activity.
Counted(i) == IF req[i] = "stmt" THEN mode = "CS" \/ "CLS-SA" \notin Off
              ELSE IF req[i] = "expr" THEN "CLS-EXPR" \notin Off
              ELSE FALSE
InSqlCode == IF "CLS-INHERIT" \in Off THEN dep \in Depths /\ Counted(dep)
             ELSE \E i \in Depths : i <= dep /\ Counted(i)
CodeAllows(c) == IF c \in {"TCL", "DDL"}
                   THEN (~InSqlCode \/ "G1" \in Off) /\ (~trig \/ "G1t" \in Off)
                 ELSE IF c = "DML" THEN (~InSqlCode \/ "G2" \in Off) /\ ~(trig /\ "DML-IN-TRIG" \in Off)
                 ELSE TRUE
\* sp_check_statement_allowed runs at execute; EXEC removed keeps the first decision with the
\* SQL handler reused for the same text in the transaction (method_query_handler.cpp)
Decision(o) == IF "EXEC" \in Off /\ prep[o] # "none" THEN prep[o] = "allow"
               ELSE CodeAllows(Cat(o))
PrepNext(o) == IF "EXEC" \in Off /\ prep[o] = "none"
                 THEN [prep EXCEPT ![o] = IF CodeAllows(Cat(o)) THEN "allow" ELSE "deny"]
                 ELSE prep

\* a statement is in progress: the outer one, or a nested SELECT of an SP
StmtInProgress == (top \in StmtTops \cup TrigTops /\ ph # "end")
                  \/ \E i \in Depths : i <= dep /\ req[i] = "stmt"

Seen(r) == IF acc \in {"cached", "list"} THEN copy[r] ELSE heap[r]
NextRow == IF pos < N THEN pos + 1 ELSE N
Bump(v) == IF v = 0 THEN 0 ELSE v + 1
Tracked(c) == top # "call" /\ Cls = c

\* ---------------------------------------------------------------- initial state
Init ==
  /\ mode \in Modes
  /\ top \in Tops
  /\ \E plan \in Plans(top) :
       acc = IF top \in StmtTops THEN ScanMode(top, plan)
             ELSE IF top \in TrigTops THEN "list" ELSE "none"
  /\ heap = [r \in Rows |-> 1]
  /\ copy = [r \in Rows |-> 1]
  /\ emitted = {}
  /\ ph = IF top = "call" THEN "sp" ELSE IF top \in TrigTops THEN "wfire" ELSE "read"
  /\ pos = IF top = "call" THEN 0 ELSE 1
  /\ req = [i \in Depths |-> IF i = 1 /\ top = "call" THEN "call" ELSE "none"]
  /\ dep = IF top = "call" THEN 1 ELSE 0
  /\ \E k \in 1..K : left = [i \in Depths |-> IF i = 1 /\ top = "call" THEN k ELSE 0]
  /\ err = FALSE
  /\ trig = FALSE
  /\ tempOk = TRUE
  /\ snapOk = TRUE
  /\ abortPend = FALSE
  /\ failed = FALSE
  /\ prep = [o \in Leaf |-> "none"]
  /\ bad = {}
  /\ ev = {}

\* ---------------------------------------------------------------- outer statement
\* read row pos (fixed: PEEK under the latch; cached / list: the copy; index: the next OID of the
\* buffer fetched from the heap), then the select list calls the SP of the row
ReadRow ==
  /\ ph = "read"
  /\ IF ~snapOk \/ ~tempOk
       THEN \* CBRD-27603 (temp pages freed) / 11-06 comment (snapshot reset): the scan resumes on
            \* a transaction that ended under it
            /\ bad' = bad \cup {"useAfterEnd"}
            /\ ph' = "end" /\ failed' = TRUE
            /\ UNCHANGED <<heap, emitted, req, dep, left, ev>>
       ELSE LET v == Seen(pos)
                dangling == acc = "index" /\ heap[pos] = 0 /\ mode = "SA"
            IN /\ bad' = bad \cup (IF dangling THEN {"dangling"} ELSE {})
                             \cup (IF v > 0 /\ v # heap[pos] THEN {"stale"} ELSE {})
               /\ emitted' = IF v > 0 /\ ~dangling THEN emitted \cup {pos} ELSE emitted
               /\ IF HasSP
                    THEN /\ ph' = "sp" /\ dep' = 1
                         /\ req' = [req EXCEPT ![1] = "stmt"]
                         /\ \E k \in 1..K : left' = [left EXCEPT ![1] = k]
                         /\ UNCHANGED <<heap, ev>>
                    ELSE \* NEXT_VALUE in the select list writes s_b (serial.c xserial_get_next_value)
                         /\ ph' = "after"
                         /\ heap' = [heap EXCEPT ![N] = Bump(heap[N])]
                         /\ ev' = ev \cup {"directNextval"}
                         /\ UNCHANGED <<req, dep, left>>
               /\ UNCHANGED failed
  /\ UNCHANGED <<mode, top, acc, pos, copy, err, trig, tempOk, snapOk, abortPend, prep>>

AfterSp ==
  /\ ph = "after"
  /\ IF abortPend
       THEN \* P3: the outer statement fails at its next check; the abort runs once it unwound
            /\ ph' = "end" /\ failed' = TRUE /\ ev' = ev \cup {"abortDeferred"}
            /\ UNCHANGED pos
       ELSE /\ IF pos < N THEN ph' = "read" /\ pos' = pos + 1 ELSE ph' = "close" /\ UNCHANGED pos
            /\ UNCHANGED <<failed, ev>>
  /\ UNCHANGED <<mode, top, acc, heap, copy, emitted, req, dep, left, err, trig, tempOk, snapOk,
                 abortPend, prep, bad>>

\* the scan closes its list file
Close ==
  /\ ph = "close"
  /\ bad' = IF tempOk THEN bad ELSE bad \cup {"useAfterEnd"}
  /\ failed' = ~tempOk
  /\ ev' = IF tempOk THEN ev \cup {"stmtDone"} ELSE ev
  /\ ph' = "end"
  /\ UNCHANGED <<mode, top, acc, pos, heap, copy, emitted, req, dep, left, err, trig, tempOk, snapOk,
                 abortPend, prep>>

\* trigger_manager.c execute_activity: a row trigger of a class with triggers runs on the client
\* after the DML read every target row into a list file (execute_statement.c do_update: server_update
\* is false when has_trigger)
WFire ==
  /\ ph = "wfire"
  /\ trig' = TRUE /\ ph' = "sp" /\ dep' = 1
  /\ req' = [req EXCEPT ![1] = IF top = "trigCall" THEN "call" ELSE "expr"]
  /\ \E k \in 1..K : left' = [left EXCEPT ![1] = k]
  /\ UNCHANGED <<mode, top, acc, pos, heap, copy, emitted, err, tempOk, snapOk, abortPend, failed,
                 prep, bad, ev>>

\* the DML writes target row pos; a row its trigger already deleted is skipped (probe 11-09, SA
\* and CS: "3 rows affected" of 5, no error)
WWrite ==
  /\ ph = "wwrite"
  /\ IF abortPend
       THEN /\ ph' = "end" /\ failed' = TRUE /\ ev' = ev \cup {"abortDeferred"}
            /\ UNCHANGED <<pos, heap, bad>>
       ELSE IF ~tempOk
       THEN /\ bad' = bad \cup {"useAfterEnd"} /\ ph' = "end" /\ failed' = TRUE
            /\ UNCHANGED <<pos, heap, ev>>
       ELSE /\ heap' = [heap EXCEPT ![pos] = Bump(heap[pos])]
            /\ ev' = IF heap[pos] = 0 THEN ev \cup {"writeSkipsDeleted"} ELSE ev
            /\ IF pos < N THEN ph' = "wfire" /\ pos' = pos + 1 ELSE ph' = "end" /\ UNCHANGED pos
            /\ UNCHANGED <<failed, bad>>
  /\ UNCHANGED <<mode, top, acc, copy, emitted, req, dep, left, err, trig, tempOk, snapOk,
                 abortPend, prep>>

\* ---------------------------------------------------------------- SP body
\* One leaf callback: sp_check_statement_allowed at execute (method_query_handler.cpp,
\* method_callback.cpp end_transaction / OID callbacks), then the statement.
\*   selfW   the write waits on the latch its own suspended outer scan holds (CBRD-27591; for
\*           NEXT_VALUE: serial.c xserial_get_next_value -> heap_prepare_object_page, probe 11-09)
\*   aborts  a unilateral abort: the deadlock victim (lock_manager.c lock_set_error_for_aborted) or
\*           the latch timeout after selfW (page_buffer.c pgbuf_timed_sleep); the code aborts when
\*           the failing request returns (network_interface_sr.cpp return_error_to_client)
\*   cross   a URL connection's write waits behind the outer fixed scan; its own timeout aborts
\*           that other transaction and the SP gets the error
SpLeaf(o) ==
  LET ctx == IF trig THEN "trig" ELSE IF InSqlRule THEN "sql" ELSE "call"
      ok == Decision(o)
      selfW == ok /\ Latched /\ ((o \in {"delT", "updT"} /\ Cls = "T") \/ (o = "nextval" /\ Cls = "S"))
      cross == ok /\ o = "url" /\ Latched /\ Cls = "T"
      aborts == selfW \/ (ok /\ o = "lockwait")
      deferred == aborts /\ StmtInProgress /\ "P3" \notin Off
      ends == (aborts /\ ~deferred) \/ (ok /\ o = "commit")
      rule == RuleAllows(Cat(o))
      rb == IF ok /\ ~rule
              THEN IF Cat(o) = "DML" THEN {"ruleBreakDML"}
                   ELSE IF Cat(o) = "TCL" THEN {"ruleBreakTCL"} ELSE {"ruleBreakDDL"}
              ELSE {}
      newBad == rb \cup (IF ~ok /\ rule THEN {"overReject"} ELSE {})
                   \cup (IF selfW THEN {"selfWait"} ELSE {})
                   \cup (IF cross THEN {"crossWait"} ELSE {})
                   \cup (IF ends /\ StmtInProgress THEN {"txnEndMid"} ELSE {})
                   \cup (IF ok /\ o = "ddlT" /\ StmtInProgress THEN {"ddlMid"} ELSE {})
      newEv == (IF ok /\ Cat(o) = "DML" /\ ctx = "call" THEN {"dmlCall"} ELSE {})
                 \cup (IF ok /\ Cat(o) = "DML" /\ ctx = "call" /\ top = "call" /\ dep = 1
                          /\ "rejDmlNested" \in ev THEN {"nestThenAllowed"} ELSE {})
                 \cup (IF ok /\ Cat(o) = "DML" /\ ctx = "trig" THEN {"dmlTrig"} ELSE {})
                 \cup (IF ~ok /\ Cat(o) = "DML" /\ ctx = "sql" THEN {"rejDmlSql"} ELSE {})
                 \cup (IF ~ok /\ Cat(o) = "DML" /\ top = "call" /\ dep > 1 THEN {"rejDmlNested"} ELSE {})
                 \cup (IF ~ok /\ Cat(o) = "TCL" /\ ctx = "trig" THEN {"rejTclTrig"} ELSE {})
                 \cup (IF ~ok /\ Cat(o) = "DDL" /\ ctx = "sql" THEN {"rejDdlSql"} ELSE {})
                 \cup (IF ok /\ Cat(o) = "TCL" /\ ctx = "call" THEN {"tclCall"} ELSE {})
                 \cup (IF ok /\ o = "nextval" /\ ctx = "sql" /\ ~selfW THEN {"nextvalSql"} ELSE {})
                 \cup (IF ok /\ o = "url" /\ ctx = "sql" /\ ~cross THEN {"urlSql"} ELSE {})
                 \cup (IF ok /\ o = "selT" /\ ctx = "sql" THEN {"selSql"} ELSE {})
                 \cup (IF ok /\ o = "lockwait" /\ ctx = "sql" THEN {"victimSql"} ELSE {})
  IN IF abortPend
       THEN \* P3: every request of the transaction fails while the abort is pending
            /\ err' = TRUE
            /\ UNCHANGED <<heap, tempOk, snapOk, abortPend, bad, ev, prep>>
       ELSE /\ prep' = PrepNext(o)
            /\ err' = (~ok \/ aborts \/ cross)
            /\ abortPend' = deferred
            /\ tempOk' = (tempOk /\ ~ends)
            /\ snapOk' = (snapOk /\ ~ends)
            /\ heap' = IF ok /\ ~selfW /\ o \in {"delT", "updT"} /\ Tracked("T")
                         THEN [heap EXCEPT ![NextRow] = IF o = "delT" THEN 0 ELSE Bump(heap[NextRow])]
                       ELSE IF ok /\ ~selfW /\ o = "nextval" /\ Tracked("S")
                         THEN [heap EXCEPT ![N] = Bump(heap[N])]
                       ELSE heap
            /\ bad' = bad \cup newBad
            /\ ev' = ev \cup newEv

SpOp ==
  /\ ph = "sp" /\ dep \in Depths /\ ~err /\ left[dep] > 0
  /\ \E o \in Leaf \cup Nest :
       /\ mode = "SA" => o \notin {"url", "lockwait"}
       /\ o \in Nest => dep < MaxD
       /\ IF o \in Nest
            THEN /\ IF abortPend
                      THEN /\ err' = TRUE
                           /\ left' = [left EXCEPT ![dep] = @ - 1]
                           /\ UNCHANGED <<req, dep>>
                      ELSE /\ dep' = dep + 1
                           /\ req' = [req EXCEPT ![dep + 1] = IF o = "callG" THEN "call" ELSE "stmt"]
                           /\ \E k \in 1..K : left' = [left EXCEPT ![dep] = @ - 1, ![dep + 1] = k]
                           /\ UNCHANGED err
                 /\ UNCHANGED <<heap, tempOk, snapOk, abortPend, bad, ev, prep>>
            ELSE /\ left' = [left EXCEPT ![dep] = @ - 1]
                 /\ SpLeaf(o)
                 /\ UNCHANGED <<req, dep>>
  /\ UNCHANGED <<mode, top, acc, pos, copy, emitted, ph, trig, failed>>

\* the SP handles the error (PL/CSQL EXCEPTION, Java catch) and goes on
Catch ==
  /\ ph = "sp" /\ err
  /\ err' = FALSE /\ ev' = ev \cup {"caught"}
  /\ UNCHANGED <<mode, top, acc, pos, heap, copy, emitted, ph, req, dep, left, trig, tempOk, snapOk,
                 abortPend, failed, prep, bad>>

\* the SP returns (e: with its error) to the request it ran under
Pop(e) ==
  /\ dep' = dep - 1
  /\ req' = [req EXCEPT ![dep] = "none"]
  /\ left' = [left EXCEPT ![dep] = 0]
  /\ IF dep > 1
       THEN /\ err' = e
            /\ UNCHANGED <<ph, trig, failed>>
       ELSE /\ err' = FALSE
            /\ trig' = FALSE
            /\ ph' = IF top = "call" \/ e THEN "end"
                     ELSE IF top \in TrigTops THEN "wwrite" ELSE "after"
            /\ failed' = e

Propagate ==
  /\ ph = "sp" /\ err
  /\ Pop(TRUE)
  /\ UNCHANGED <<mode, top, acc, pos, heap, copy, emitted, tempOk, snapOk, abortPend, prep, bad, ev>>

Return ==
  /\ ph = "sp" /\ ~err /\ left[dep] = 0
  /\ Pop(FALSE)
  /\ UNCHANGED <<mode, top, acc, pos, heap, copy, emitted, tempOk, snapOk, abortPend, prep, bad, ev>>

Done ==
  /\ ph = "end"
  /\ UNCHANGED vars

Next == ReadRow \/ AfterSp \/ Close \/ WFire \/ WWrite \/ SpOp \/ Catch \/ Propagate \/ Return \/ Done

Spec == Init /\ [][Next]_vars

\* ---------------------------------------------------------------- properties
TypeOK ==
  /\ mode \in {"CS", "SA"}
  /\ top \in AllTops
  /\ acc \in {"none", "fixed", "cached", "plain", "index", "list"}
  /\ pos \in 0..N
  /\ DOMAIN heap = Rows /\ \A r \in Rows : heap[r] >= 0
  /\ DOMAIN copy = Rows /\ \A r \in Rows : copy[r] >= 0
  /\ emitted \subseteq Rows
  /\ ph \in {"read", "sp", "after", "close", "wfire", "wwrite", "end"}
  /\ DOMAIN req = Depths /\ \A i \in Depths : req[i] \in {"none", "call", "stmt", "expr"}
  /\ dep \in 0..MaxD
  /\ DOMAIN left = Depths /\ \A i \in Depths : left[i] \in 0..K
  /\ err \in BOOLEAN /\ trig \in BOOLEAN /\ tempOk \in BOOLEAN /\ snapOk \in BOOLEAN
  /\ abortPend \in BOOLEAN /\ failed \in BOOLEAN
  /\ DOMAIN prep = Leaf /\ \A o \in Leaf : prep[o] \in {"none", "allow", "deny"}
  /\ bad \subseteq BadTags
  /\ ev \subseteq EvTags

\* C1 rule 1, C2 rule 2, C3 nothing the rule allows is rejected
Rule1 == /\ "ruleBreakTCL" \notin bad /\ "ruleBreakDDL" \notin bad
Rule2 == "ruleBreakDML" \notin bad
NoOverReject == "overReject" \notin bad
\* C4 CBRD-27603 and the 11-06 comment: the transaction does not end under a running statement
NoTxnEndMidStmt == "txnEndMid" \notin bad
NoUseAfterEnd == "useAfterEnd" \notin bad
\* C5 DDL does not change a class under a running statement
NoDdlMidStmt == "ddlMid" \notin bad
\* C6 CBRD-27591: nothing the SP waits for waits on the latch of its suspended outer scan
NoSelfWait == "selfWait" \notin bad
NoCrossWait == "crossWait" \notin bad
\* C7 CBRD-27590: a returned row is the row as it is when returned
NoStaleRead == "stale" \notin bad
\* C8 CBRD-27614: the index scan never fetches an OID deleted in place
NoDanglingOid == "dangling" \notin bad
\* C9 the answer over t does not depend on the plan (CBRD-27614 comment 10-13)
PlanIndependent == (top \in TTops /\ ph = "end" /\ ~failed) => emitted = Rows

Safety == Rule1 /\ Rule2 /\ NoOverReject /\ NoTxnEndMidStmt /\ NoUseAfterEnd /\ NoDdlMidStmt
          /\ NoSelfWait /\ NoCrossWait /\ NoStaleRead /\ NoDanglingOid /\ PlanIndependent

\* witnesses: each must be reachable
NotDmlCall == "dmlCall" \notin ev
NotDmlTrig == "dmlTrig" \notin ev
NotRejDmlSql == "rejDmlSql" \notin ev
NotRejTclTrig == "rejTclTrig" \notin ev
NotRejDdlSql == "rejDdlSql" \notin ev
NotNestThenAllowed == "nestThenAllowed" \notin ev
NotNextvalSql == "nextvalSql" \notin ev
NotUrlSql == "urlSql" \notin ev
NotSelSql == "selSql" \notin ev
NotTclCall == "tclCall" \notin ev
NotStmtDone == "stmtDone" \notin ev
NotAbortDeferred == "abortDeferred" \notin ev
NotWriteSkipsDeleted == "writeSkipsDeleted" \notin ev
NotDirectNextvalDone == ~("directNextval" \in ev /\ "stmtDone" \in ev)

\* ---------------------------------------------------------------- inductive invariant (Off = {})
Frame1 == IF top \in {"call", "trigCall"} THEN "call" ELSE IF top = "trigExpr" THEN "expr" ELSE "stmt"

PhaseOfTop ==
  /\ top = "call" => ph \in {"sp", "end"}
  /\ top \in StmtTops => ph \in {"read", "sp", "after", "close", "end"}
  /\ top \in TrigTops => ph \in {"wfire", "sp", "wwrite", "end"}
AccOfTop ==
  /\ top = "call" => acc = "none"
  /\ top \in TrigTops => acc = "list"
  /\ top \in StmtTops => \E p \in Plans(top) : acc = ScanMode(top, p)
DepPhase == (ph = "sp") = (dep >= 1)
FramesShape == \A i \in Depths :
                 /\ i <= dep => req[i] # "none"
                 /\ i > dep => (req[i] = "none" /\ left[i] = 0)
                 /\ i >= 2 => req[i] \in {"none", "call", "stmt"}
FirstFrame == dep >= 1 => req[1] = Frame1
TrigShape == trig = (top \in TrigTops /\ ph = "sp")
ErrShape == err => ph = "sp"
PosShape == /\ top = "call" => pos = 0
            /\ top # "call" => pos \in Rows
            /\ ph = "close" => pos = N
NoSpUnderDirect == top = "stmtSnv" => ph # "sp"
PrepUnused == \A o \in Leaf : prep[o] = "none"
CopyInitial == \A r \in Rows : copy[r] = 1
TUntouched == top \in TTops => \A r \in Rows : heap[r] = 1
EmittedPrefix ==
  top \in TTops =>
    /\ ph = "read" => emitted = {r \in Rows : r < pos}
    /\ ph \in {"sp", "after", "close"} => emitted = {r \in Rows : r <= pos}
    /\ (ph = "end" /\ ~failed) => emitted = Rows
TxnAlive == (top \in StmtTops \cup TrigTops /\ ph # "end") => (tempOk /\ snapOk)
BadEmpty == bad = {}

IndInv ==
  /\ TypeOK
  /\ PhaseOfTop
  /\ AccOfTop
  /\ DepPhase
  /\ FramesShape
  /\ FirstFrame
  /\ TrigShape
  /\ ErrShape
  /\ PosShape
  /\ NoSpUnderDirect
  /\ PrepUnused
  /\ CopyInitial
  /\ TUntouched
  /\ EmittedPrefix
  /\ TxnAlive
  /\ BadEmpty
  /\ Rule1
  /\ Rule2
  /\ NoOverReject
  /\ NoTxnEndMidStmt
  /\ NoUseAfterEnd
  /\ NoDdlMidStmt
  /\ NoSelfWait
  /\ NoCrossWait
  /\ NoStaleRead
  /\ NoDanglingOid
  /\ PlanIndependent

=============================================================================
