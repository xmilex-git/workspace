---------------------------- MODULE CoveredVisit ----------------------------
(* CBRD-28031: the rows of a block's innermost covered index scan taken where the B-tree selects each object.
   The B-tree range scan (btree_range_scan) walks the keys of the range leaf by leaf under the leaf's latch;
   for every selected object of a key (btree_select_visible_object_for_range_scan) it either writes the key
   to the scan's covering list (btree_dump_curr_key), which scan_next_index_scan reads back row by row after
   the latch is released, or, when the executor attached a visit (qexec_covered_visit_scan,
   INDX_SCAN_ID::gby_skip->visit), hands the object to the block at once (qexec_covered_visit: the inner
   predicates and qexec_end_one_iteration) and leaves nothing in the batch.
   Objects are numbered 1..N in key order; KeyOf(i) is the key of object i (PerKey objects a key). *)
EXTENDS Integers, FiniteSets

CONSTANTS NK, PerKey, Cap, SubChoices, FailChoices, Mutant
\* NK keys of PerKey objects each, Cap: the objects a covering list batch holds before the scan returns to deliver
\* them, SubChoices: whether the block runs something for each row that fixes pages or waits (then no fixed scan is
\* allowed), FailChoices: the object whose row raises an error in the block (0: none); a behavior picks one of each

\* apalache-type: NK Int
\* apalache-type: PerKey Int
\* apalache-type: Cap Int
\* apalache-type: SubChoices Set(Bool)
\* apalache-type: FailChoices Set(Int)
\* apalache-type: Subquery Bool
\* apalache-type: FailAt Int
\* apalache-type: Mutant Str
\* apalache-type: visit Bool
\* apalache-type: phase Str
\* apalache-type: nextObj Int
\* apalache-type: latched Bool
\* apalache-type: batch Int
\* apalache-type: batchFrom Int
\* apalache-type: done Int
\* apalache-type: twice Bool
\* apalache-type: order Bool
\* apalache-type: listWrites Int
\* apalache-type: fixUnderLatch Bool
\* apalache-type: err Bool
\* apalache-type: afterErr Bool

CInit ==
  /\ NK = 2
  /\ PerKey = 2
  /\ Cap = 2
  /\ SubChoices = {TRUE, FALSE}
  /\ FailChoices = {0, 3}
  /\ Mutant = "none"

VARIABLES Subquery, FailAt,   \* this behavior's choices
          visit,          \* the executor attached the visit (decided once, when the scans are opened)
          phase,          \* "open", "walk" (the B-tree holds or looks for a leaf), "deliver", "end"
          nextObj,        \* the first object the B-tree has not selected yet
          latched,        \* the scan thread holds a leaf latch
          batch,          \* objects in the covering list not yet delivered
          batchFrom,      \* the first of them
          done,           \* objects the block took so far
          twice, order,   \* ghosts: an object reached the block twice; the objects reached it in key order
          listWrites,     \* ghost: keys written to the covering list
          fixUnderLatch,  \* ghost: the block's row work fixed a page while the scan held its leaf latch
          err,            \* the statement failed
          afterErr        \* ghost: a row reached the block after the error

vars == <<Subquery, FailAt, visit, phase, nextObj, latched, batch, batchFrom, done, twice, order, listWrites, fixUnderLatch, err,
          afterErr>>

N == NK * PerKey
KeyOf(i) == (i - 1) \div PerKey + 1

Init ==
  /\ Subquery \in SubChoices
  /\ FailAt \in FailChoices
  /\ visit = FALSE
  /\ phase = "open"
  /\ nextObj = 1
  /\ latched = FALSE
  /\ batch = 0
  /\ batchFrom = 1
  /\ done = 0
  /\ twice = FALSE
  /\ order = TRUE
  /\ listWrites = 0
  /\ fixUnderLatch = FALSE
  /\ err = FALSE
  /\ afterErr = FALSE

\* qexec_execute_mainblock_internal: the visit is attached only where a fixed scan is allowed
Open ==
  /\ UNCHANGED <<Subquery, FailAt>>
  /\ phase = "open"
  /\ visit' = (IF Mutant = "attach_nonlocal" THEN TRUE ELSE ~Subquery)
  /\ phase' = "walk"
  /\ UNCHANGED <<nextObj, latched, batch, batchFrom, done, twice, order, listWrites, fixUnderLatch, err, afterErr>>

\* the block takes object i (qexec_covered_visit, or the row loop for a delivered row)
Take(i, underLatch) ==
  /\ done' = done + 1
  /\ twice' = (twice \/ i <= done)
  /\ order' = (order /\ i = done + 1)
  /\ fixUnderLatch' = (fixUnderLatch \/ (underLatch /\ Subquery))
  /\ afterErr' = (afterErr \/ err)
  /\ err' = (err \/ i = FailAt)

\* btree_range_scan fixes the leaf of the next key (after a restart too: it resumes at the first key not consumed)
Fix ==
  /\ UNCHANGED <<Subquery, FailAt>>
  /\ phase = "walk" /\ ~latched /\ ~err
  /\ latched' = TRUE
  /\ UNCHANGED <<visit, phase, nextObj, batch, batchFrom, done, twice, order, listWrites, fixUnderLatch, err, afterErr>>

\* one key under the latch: every object of it is visited or written to the list (a covered scan never stops inside
\* a key). The key's objects are taken one step each to let an error stop the scan between them.
Select ==
  /\ UNCHANGED <<Subquery, FailAt>>
  /\ phase = "walk" /\ latched /\ nextObj <= N
  /\ (err /\ Mutant # "swallow_error") = FALSE
  /\ IF visit
       THEN /\ Take(nextObj, TRUE)
            /\ nextObj' = nextObj + 1
            /\ IF Mutant = "visit_and_dump" \/ Mutant = "count_batch"
                 THEN /\ batch' = batch + 1
                      /\ listWrites' = IF Mutant = "visit_and_dump" THEN listWrites + 1 ELSE listWrites
                 ELSE UNCHANGED <<batch, listWrites>>
            /\ UNCHANGED <<batchFrom, latched, phase, visit>>
       ELSE /\ batch' = batch + 1
            /\ listWrites' = listWrites + 1
            /\ nextObj' = nextObj + 1
            /\ UNCHANGED <<batchFrom, latched, phase, visit, done, twice, order, fixUnderLatch, err, afterErr>>

\* the scan returns: at the range's end, when the batch reached its capacity at a key boundary, or with the block's
\* error; the leaf latch is released on every one of them
Return ==
  /\ UNCHANGED <<Subquery, FailAt>>
  /\ phase = "walk" /\ latched
  /\ \/ nextObj > N
     \/ (batch >= Cap /\ (nextObj - 1) % PerKey = 0)
     \/ (err /\ Mutant # "swallow_error")
  /\ latched' = (Mutant = "keep_latch" /\ err)
  /\ phase' = IF err /\ Mutant # "swallow_error" THEN "end" ELSE "deliver"
  /\ UNCHANGED <<visit, nextObj, batch, batchFrom, done, twice, order, listWrites, fixUnderLatch, err, afterErr>>

\* the leaf latch is lost between two keys (the next leaf could not be latched at once): the walk restarts
Restart ==
  /\ UNCHANGED <<Subquery, FailAt>>
  /\ phase = "walk" /\ latched /\ nextObj <= N /\ (nextObj - 1) % PerKey = 0 /\ ~err
  /\ latched' = FALSE
  /\ UNCHANGED <<visit, phase, nextObj, batch, batchFrom, done, twice, order, listWrites, fixUnderLatch, err, afterErr>>

\* scan_next_index_scan reads a row of the covering list and the row loop takes it; no latch is held
Deliver ==
  /\ UNCHANGED <<Subquery, FailAt>>
  /\ phase = "deliver" /\ batch > 0 /\ ~err
  /\ Take(batchFrom, FALSE)
  /\ batch' = batch - 1
  /\ batchFrom' = batchFrom + 1
  /\ UNCHANGED <<visit, phase, nextObj, latched, listWrites>>

Again ==
  /\ UNCHANGED <<Subquery, FailAt>>
  /\ phase = "deliver" /\ (batch = 0 \/ err)
  /\ phase' = IF nextObj > N \/ err THEN "end" ELSE "walk"
  /\ batchFrom' = IF err \/ (visit /\ Mutant # "visit_and_dump" /\ Mutant # "count_batch") THEN batchFrom ELSE nextObj
  /\ UNCHANGED <<visit, nextObj, latched, batch, done, twice, order, listWrites, fixUnderLatch, err, afterErr>>

Done == phase = "end" /\ UNCHANGED vars

Next == Open \/ Fix \/ Select \/ Return \/ Restart \/ Deliver \/ Again \/ Done

Spec == Init /\ [][Next]_vars

----
TypeOK ==
  /\ Subquery \in SubChoices
  /\ FailAt \in FailChoices
  /\ visit \in BOOLEAN
  /\ phase \in {"open", "walk", "deliver", "end"}
  /\ nextObj \in 1..(N + 1)
  /\ latched \in BOOLEAN
  /\ batch \in 0..N
  /\ batchFrom \in 1..(N + 1)
  /\ done \in 0..(2 * N)
  /\ twice \in BOOLEAN
  /\ order \in BOOLEAN
  /\ listWrites \in 0..N
  /\ fixUnderLatch \in BOOLEAN
  /\ err \in BOOLEAN
  /\ afterErr \in BOOLEAN

\* C19: the block takes every selected object once, in key order, visited or delivered
ExactlyOnce == ~twice /\ order
AllTaken == (phase = "end" /\ ~err) => done = N
\* C20: a visited key is never written to the covering list
NoListWrite == visit => listWrites = 0
\* C21: the block's row work fixes no page and waits for nothing while the scan holds its leaf latch
LatchLocal == ~fixUnderLatch
\* C22: an error of the block ends the scan: no later row reaches the block, and no leaf stays latched
ErrorStops == ~afterErr /\ (phase = "end" => ~latched)

Shape ==
  /\ phase = "open" => (nextObj = 1 /\ done = 0 /\ batch = 0 /\ batchFrom = 1 /\ listWrites = 0 /\ ~latched /\ ~visit
                        /\ ~err)
  /\ phase # "open" => visit = ~Subquery
  /\ phase \in {"deliver", "end"} => ~latched
  /\ visit => (batch = 0 /\ batchFrom = 1 /\ listWrites = 0 /\ done = nextObj - 1)
  /\ ~visit => (batchFrom + batch = nextObj /\ done = batchFrom - 1 /\ listWrites = nextObj - 1)
  /\ err <=> (FailAt # 0 /\ done >= FailAt)
  /\ err => done = FailAt
  /\ phase = "walk" /\ ~latched => (nextObj - 1) % PerKey = 0
  /\ phase = "deliver" => ((nextObj - 1) % PerKey = 0 \/ err)
  /\ phase = "deliver" /\ visit => (nextObj = N + 1 \/ err)
  /\ phase = "end" /\ ~err => (nextObj = N + 1 /\ batch = 0)
  /\ ~afterErr /\ ~fixUnderLatch

IndInv == TypeOK /\ Shape /\ ExactlyOnce /\ AllTaken /\ NoListWrite /\ LatchLocal /\ ErrorStops

\* witnesses
NotVisited == ~(visit /\ done > 0)
NotListed == listWrites = 0
NotFailedUnderLatch == ~(visit /\ err)
NotRestarted == ~(phase = "walk" /\ ~latched /\ nextObj > 1)
=============================================================================
