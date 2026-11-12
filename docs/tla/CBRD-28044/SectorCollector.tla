--------------------------- MODULE SectorCollector ---------------------------
(* The ownership of a FILE_FTAB_COLLECTOR's partsect_ftab across one call site:
   file_get_all_data_sectors () (file_manager.c) fills the caller's collector, and each of its six
   callers frees the array on its own exits; file_destroy () (file_manager.c) owns a collector of its
   own.  One thread per call site and nothing shared between call sites, so a behavior runs one site
   (chosen in Init). *)
EXTENDS Naturals

CONSTANTS Fix, DestroyFix, Mutant, MaxIter
\* apalache-type: Fix Str
\* apalache-type: DestroyFix Bool
\* apalache-type: Mutant Str
\* apalache-type: MaxIter Int

\* Fix: "none" = develop; "caller" = init_on_main declares the collector with
\*   FILE_FTAB_COLLECTOR_INITIALIZER and drops its free on failure (CBRD-27285's shape);
\*   "callee" = file_get_all_data_sectors empties collector_out before its first exit and
\*   init_on_main drops its free on failure; "both" = callee + caller.
\* DestroyFix: file_destroy sets ftab_collector.partsect_ftab = NULL before its first goto exit.
\* Mutant: "none" | "callee_free_no_null" | "callee_leak" | "px_no_free_ok".

GadsSites == {"pxheap", "list", "btsort", "capacity", "histo_split", "histo_full"}
Sites == GadsSites \cup {"destroy"}
Ptrs == {"garbage", "null", "owned", "dangling"}
Exits == {"fix_fail", "oom_first", "fail_after_alloc", "ok"}

CalleeResets == Fix \in {"callee", "both"}

\* the call site's code facts (refinement map in MAP.md)
DeclInit(s) == \/ s \in {"list", "capacity", "histo_split", "histo_full"}
               \/ s = "pxheap" /\ Fix \in {"caller", "both"}
FreeOnFail(s) == \/ s \in {"list", "capacity"}
                 \/ s = "pxheap" /\ Fix = "none"
Iters(s) == IF s \in {"list", "btsort"} THEN MaxIter ELSE 1

VARIABLES site, pc, ptr, res, iter, allocs, frees, badFree, temp, lastExit
\* apalache-type: site Str
\* apalache-type: pc Str
\* apalache-type: ptr Str
\* apalache-type: res Str
\* apalache-type: iter Int
\* apalache-type: allocs Int
\* apalache-type: frees Int
\* apalache-type: badFree Bool
\* apalache-type: temp Bool
\* apalache-type: lastExit Str

vars == <<site, pc, ptr, res, iter, allocs, frees, badFree, temp, lastExit>>

\* ptr: what collector.partsect_ftab holds: an uninitialized stack value ("garbage"), NULL, an
\*   array this site owns ("owned"), or an array already freed but not NULLed ("dangling").
\* res: the result of the last file_get_all_data_sectors call.  iter: the loop's iteration
\*   (dependent list files, the classes of an index).  allocs, frees: arrays allocated into the
\*   collector and freed (ghosts).  badFree: a free of a value the allocator did not hand out or
\*   already took back (ghost).  temp: file_destroy's is_temp.  lastExit: witnesses' ghost.

Init ==
  /\ site \in Sites
  /\ pc = IF site = "destroy" THEN "unreg" ELSE "call"
  /\ ptr = IF site = "destroy" THEN (IF DestroyFix THEN "null" ELSE "garbage")
           ELSE (IF DeclInit(site) THEN "null" ELSE "garbage")
  /\ res = "none"
  /\ iter = 1
  /\ allocs = 0
  /\ frees = 0
  /\ badFree = FALSE
  /\ temp \in BOOLEAN
  /\ lastExit = "none"

\* db_private_free (_and_init) of collector.partsect_ftab
FreePtr(p) == IF p = "owned" THEN frees + 1 ELSE frees
FreeBad(p) == p \in {"garbage", "dangling"}

\* file_get_all_data_sectors: one call, one exit
Call ==
  /\ site \in GadsSites /\ pc = "call"
  /\ \E e \in Exits :
       /\ lastExit' = e
       /\ CASE e = "fix_fail" ->           \* pgbuf_fix of the file header fails (interrupt, latch timeout)
                 /\ ptr' = IF CalleeResets THEN "null" ELSE ptr
                 /\ res' = "fail" /\ UNCHANGED <<allocs, frees>>
            [] e = "oom_first" ->          \* the first db_private_alloc returns NULL into collector_out
                 /\ ptr' = "null" /\ res' = "fail" /\ UNCHANGED <<allocs, frees>>
            [] e = "fail_after_alloc" ->   \* second alloc OOM, or a file_extdata_apply_funcs error
                 /\ allocs' = allocs + 1
                 /\ IF Mutant = "callee_leak"
                      THEN frees' = frees /\ ptr' = "owned"
                      ELSE frees' = frees + 1
                           /\ ptr' = IF Mutant = "callee_free_no_null" THEN "dangling" ELSE "null"
                 /\ res' = "fail"
            [] e = "ok" ->
                 /\ allocs' = allocs + 1 /\ ptr' = "owned" /\ res' = "ok" /\ UNCHANGED frees
  /\ pc' = "after"
  /\ UNCHANGED <<site, iter, badFree, temp>>

\* the caller's code after the call returns
AfterFail ==
  /\ site \in GadsSites /\ pc = "after" /\ res = "fail"
  /\ IF FreeOnFail(site) /\ ptr # "null"
       THEN /\ frees' = FreePtr(ptr) /\ badFree' = (badFree \/ FreeBad(ptr)) /\ ptr' = "null"
       ELSE UNCHANGED <<frees, badFree, ptr>>
  /\ pc' = "done"
  /\ UNCHANGED <<site, res, iter, allocs, temp, lastExit>>

AfterOk ==
  /\ site \in GadsSites /\ pc = "after" /\ res = "ok"
  /\ IF site = "pxheap" /\ Mutant = "px_no_free_ok"
       THEN UNCHANGED <<frees, ptr>>
       ELSE frees' = FreePtr(ptr) /\ ptr' = "null"
  /\ IF iter < Iters(site)
       THEN pc' = "call" /\ iter' = iter + 1
       ELSE pc' = "done" /\ UNCHANGED iter
  /\ UNCHANGED <<site, res, allocs, badFree, temp, lastExit>>

\* file_destroy
DUnreg ==
  /\ site = "destroy" /\ pc = "unreg"
  /\ IF temp THEN pc' = "reset" /\ lastExit' = "none"
     ELSE \E ok \in BOOLEAN :         \* file_tracker_unregister: pgbuf_fix of the tracker page, sysop
            /\ pc' = IF ok THEN "reset" ELSE "exit"
            /\ lastExit' = IF ok THEN "none" ELSE "unreg_fail"
  /\ UNCHANGED <<site, ptr, res, iter, allocs, frees, badFree, temp>>

DReset ==
  /\ site = "destroy" /\ pc = "reset"
  /\ ptr' = "null" /\ pc' = "collect"
  /\ UNCHANGED <<site, res, iter, allocs, frees, badFree, temp, lastExit>>

DCollect ==
  /\ site = "destroy" /\ pc = "collect"
  /\ \/ UNCHANGED <<ptr, allocs>>                       \* header fix or vsid collection fails, or alloc OOM
     \/ ptr' = "owned" /\ allocs' = allocs + 1          \* ftab array allocated; the rest of the body ends at exit
  /\ pc' = "exit"
  /\ UNCHANGED <<site, res, iter, frees, badFree, temp, lastExit>>

DExit ==
  /\ site = "destroy" /\ pc = "exit"
  /\ IF ptr # "null"
       THEN frees' = FreePtr(ptr) /\ badFree' = (badFree \/ FreeBad(ptr)) /\ ptr' = "null"
       ELSE UNCHANGED <<frees, badFree, ptr>>
  /\ pc' = "done"
  /\ UNCHANGED <<site, res, iter, allocs, temp, lastExit>>

Done == pc = "done" /\ UNCHANGED vars

Next == Call \/ AfterFail \/ AfterOk \/ DUnreg \/ DReset \/ DCollect \/ DExit \/ Done

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
TypeOK ==
  /\ site \in Sites
  /\ pc \in {"call", "after", "unreg", "reset", "collect", "exit", "done"}
  /\ ptr \in Ptrs
  /\ res \in {"none", "ok", "fail"}
  /\ iter \in 1..MaxIter
  /\ allocs \in 0..MaxIter
  /\ frees \in 0..MaxIter
  /\ badFree \in BOOLEAN
  /\ temp \in BOOLEAN
  /\ lastExit \in Exits \cup {"none", "unreg_fail"}

\* C1
NoBadFree == ~badFree
\* C2
NoLeak == pc = "done" => allocs = frees
\* C3 (candidate): every failure return leaves the collector empty
FailLeavesEmpty == (site \in GadsSites /\ pc = "after" /\ res = "fail") => ptr = "null"

\* witnesses
NotPxFixFailDone == ~(site = "pxheap" /\ pc = "done" /\ lastExit = "fix_fail")
NotDestroyUnregFail == ~(site = "destroy" /\ pc = "done" /\ lastExit = "unreg_fail")
NotLoopFailAfterOk == ~(site \in {"list", "btsort"} /\ pc = "done" /\ iter = 2 /\ res = "fail")

-----------------------------------------------------------------------------
\* inductive invariant (Mutant = "none")
GadsPc == site \in GadsSites => pc \in {"call", "after", "done"}
DestroyPc == site = "destroy" => pc \in {"unreg", "reset", "collect", "exit", "done"}
OwnedCount == ptr = "owned" <=> allocs = frees + 1
NotOwnedCount == ptr # "owned" => allocs = frees
NoDangling == ptr # "dangling"
OwnedOnlyAfter == ptr = "owned" => (pc = "after" /\ res = "ok") \/ (site = "destroy" /\ pc = "exit")
GarbageSafe ==
  ptr = "garbage" =>
    \/ site \in GadsSites /\ ~DeclInit(site) /\ ~FreeOnFail(site) /\ ~CalleeResets
    \/ site \in GadsSites /\ ~DeclInit(site) /\ pc = "call" /\ iter = 1
    \/ site = "destroy" /\ ~DestroyFix /\ pc = "unreg"
DestroyShape ==
  site = "destroy" =>
    /\ iter = 1 /\ res = "none" /\ lastExit \in {"none", "unreg_fail"}
    /\ pc \in {"unreg", "reset", "collect"} => allocs = 0 /\ frees = 0 /\ lastExit = "none"
    /\ pc = "exit" /\ lastExit = "unreg_fail" => ptr # "owned"
GadsShape == site \in GadsSites => lastExit # "unreg_fail" /\ (pc # "call" => lastExit # "none")
IterRange == iter <= Iters(site) /\ (iter > 1 => site \in {"list", "btsort"})
AllocBound == allocs <= iter
ResCall == pc = "call" => /\ allocs + 1 <= iter
                          /\ IF iter = 1 THEN res = "none" ELSE res = "ok"

IndInv ==
  /\ TypeOK
  /\ GadsPc
  /\ DestroyPc
  /\ OwnedCount
  /\ NotOwnedCount
  /\ NoDangling
  /\ OwnedOnlyAfter
  /\ GarbageSafe
  /\ DestroyShape
  /\ GadsShape
  /\ IterRange
  /\ AllocBound
  /\ ResCall
  /\ NoBadFree
  /\ NoLeak

CInit == Fix = "callee" /\ DestroyFix = TRUE /\ Mutant = "none" /\ MaxIter = 2
=============================================================================
