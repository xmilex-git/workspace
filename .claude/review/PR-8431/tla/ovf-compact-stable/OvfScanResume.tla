--------------------------- MODULE OvfScanResume ---------------------------
(***************************************************************************)
(* A range scan over one key of a non-unique index whose OID buffer fills  *)
(* in the middle of the key's overflow chain (btree.c:30760-31063           *)
(* btree_range_scan_select_visible_oids), resumed by OID (CBRD-27401,       *)
(* btree.c:15470 btree_ovf_scan_locate_resume).  One scan iteration holds   *)
(* the key's leaf READ latch from its resume point to its stop, so it is    *)
(* one step; between iterations every OvfDirChain writer step (insert and   *)
(* its split, vacuum or rollback removal including the leaf swap, COMPACT)  *)
(* may run.  Objects visible to the scan's snapshot are never physically    *)
(* removed while the scan runs (vacuum keeps them); new objects are         *)
(* invisible to it.                                                        *)
(***************************************************************************)
EXTENDS OvfDirChain

CONSTANTS SMutant, Fix

ASSUME SMutant \in {"none", "page_resume", "anchor_processed", "stop_empty", "resume_blocked"}
ASSUME Fix \in {"none", "swap_first"}

VARIABLES
  spc,     \* "idle" | "susp" (OID buffer full, no latch held) | "done"
  vis,     \* ghost: the objects the snapshot sees (at most one version per OID)
  ret,     \* objects returned by the scan
  dup,     \* ghost: an object returned twice
  anchor,  \* bts->O_last_oid: OID of the last visible chain object accepted, 0 = NULL
  ovpid    \* bts->O_vpid: last overflow page with a visible object (page_resume only)

svars == <<spc, vis, ret, dup, anchor, ovpid>>
allvars == <<vars, svars>>
SView == <<View, svars>>

OneVersionPerOid(S) == \A a, b \in S : Oid(a) = Oid(b) => a = b

(* objects of chain[ci] from position k on, then the following pages through chain[cj] *)
RECURSIVE Span(_, _, _)
Span(ci, k, cj) ==
  IF ci > cj THEN <<>>
  ELSE SubSeq(data[chain[ci]], k, Len(data[chain[ci]])) \o Span(ci + 1, 1, cj)

LastVisPg(V, ci, k, cj, dflt) ==
  LET has(j) == \E x \in DOMAIN data[chain[j]] : data[chain[j]][x] \in V /\ (j > ci \/ x >= k)
  IN IF \E j \in ci..cj : has(j)
     THEN chain[CHOOSE j \in ci..cj : has(j) /\ \A j2 \in (j + 1)..cj : ~has(j2)]
     ELSE dflt

(* one iteration over the chain: process chain[ci] from position k through chain[cj], then stop
   (OID buffer full, btree.c:30975) or reach the chain's end.  A stop needs at least one chain
   object accepted in this iteration: a key starts only when the buffer has room for its leaf
   objects plus one full overflow page (btree.c:30774 with the estimate of btree.c:29759), and a
   resumed iteration starts with an empty buffer, so a page never overflows the buffer before a
   visible chain object was taken (MAP.md, refinement map: ScanStop). *)
ChainIter(V, ci, k, base, keyStart) ==
  \E cj \in ci..Len(chain) :
    LET seg == Span(ci, k, cj)
        acc == SelectSeq(seg, LAMBDA o : o \in V)
        stop == cj < Len(chain)
        last == IF SMutant = "anchor_processed" THEN Oid(Last(seg))
                ELSE IF acc = <<>> THEN anchor ELSE Oid(Last(acc))
    IN /\ stop => (acc # <<>> \/ SMutant = "stop_empty")
       /\ ret' = base \cup Range(acc)
       /\ dup' = (dup \/ Range(acc) \cap base # {} \/ Len(acc) # Cardinality(Range(acc)))
       /\ anchor' = last
       /\ ovpid' = LastVisPg(V, ci, k, cj, IF keyStart THEN chain[1] ELSE ovpid)
       /\ spc' = IF stop THEN "susp" ELSE "done"

(* the key reached: its leaf record objects, then the chain from its first page; the key start
   resets O_last_visible_oid (btree.c:30910), so the anchor is 0 until a chain object is accepted *)
KeyIter(V) ==
  LET lacc == leaf \cap V IN
  IF chain = <<>>
  THEN /\ ret' = ret \cup lacc
       /\ dup' = (dup \/ lacc \cap ret # {})
       /\ anchor' = 0 /\ ovpid' = NoPg /\ spc' = "done"
  ELSE /\ anchor = 0
       /\ ChainIter(V, 1, 1, ret \cup lacc, TRUE)

SStart ==
  /\ spc = "idle"
  /\ Idle
  /\ leaf # {}
  /\ \E V \in SUBSET live :
       /\ OneVersionPerOid(V)
       /\ vis' = V
       /\ KeyIter(V)
  /\ UNCHANGED vars

(* btree_ovf_scan_locate_resume: route the anchor, walk forward over fully processed pages *)
Freed == MaxPg + 100   \* resume point: the saved page was deallocated (page_resume)
RECURSIVE FwdFrom(_)
FwdFrom(ci) ==
  IF ci > Len(chain) THEN <<0, 0>>
  ELSE IF Oid(Last(data[chain[ci]])) > anchor
       THEN <<ci, CHOOSE x \in DOMAIN data[chain[ci]] :
                     Oid(data[chain[ci]][x]) > anchor /\ \A y \in 1..(x - 1) : ~(Oid(data[chain[ci]][y]) > anchor)>>
       ELSE FwdFrom(ci + 1)

ResumePoint ==
  IF chain = <<>> THEN <<0, 0>>
  ELSE IF SMutant = "page_resume"
       THEN IF ovpid \notin Range(chain) THEN <<Freed, 0>>
            ELSE IF IndexOf(chain, ovpid) = Len(chain) THEN <<0, 0>>
            ELSE <<IndexOf(chain, ovpid) + 1, 1>>
  ELSE IF anchor = 0 THEN <<1, 1>>
  ELSE IF hdr[chain[1]] = "N" THEN FwdFrom(1)
  ELSE FwdFrom(IndexOf(chain, dir[Locate(anchor)[1]][Locate(anchor)[2]].pg))

SResume ==
  /\ spc = "susp"
  /\ Idle
  /\ SMutant = "resume_blocked" => leaf = {}   \* mutant: the resume waits on a condition that never holds
  /\ LET rp == ResumePoint IN
     IF rp[1] = Freed
     THEN /\ bad' = bad \cup {"resume_freed_page"}
          /\ spc' = "done"
          /\ UNCHANGED <<chain, data, hdr, dir, leaf, live, stale, pend, seen, vis, ret, dup, anchor, ovpid>>
     ELSE IF rp[1] = 0
     THEN /\ spc' = "done"
          /\ UNCHANGED <<vars, vis, ret, dup, anchor, ovpid>>
     ELSE /\ ChainIter(vis, rp[1], rp[2], ret, FALSE)
          /\ UNCHANGED <<vars, vis>>

(* candidate fix: the leaf swap takes the first page's FIRST (smallest) object *)
RemoveSwapFirst(o) ==
  /\ Idle
  /\ o \in leaf
  /\ chain # <<>>
  /\ leaf' = {data[chain[1]][1]}
  /\ live' = live \ {o}
  /\ RemoveObjAt(1, 1, {"swap"})
  /\ UNCHANGED <<stale, pend>>

(* writers between iterations; the snapshot's visible objects are never physically removed *)
Env ==
  /\ spc # "done"
  /\ \/ \E o \in Obj : Insert(o)
     \/ \E o \in Obj \ vis :
          IF Fix # "none" /\ o \in leaf /\ chain # <<>> THEN RemoveSwapFirst(o) ELSE Remove(o)
     \/ Pull
  /\ UNCHANGED svars

\* the run ends with the scan (cubrid-tla P8)
SEnd == spc = "done" /\ UNCHANGED allvars

SInit == Init /\ spc = "idle" /\ vis = {} /\ ret = {} /\ dup = FALSE /\ anchor = 0 /\ ovpid = NoPg

SNext == SStart \/ SResume \/ Env \/ SEnd

SSpec == SInit /\ [][SNext]_allvars /\ WF_allvars(SResume)

(***************************************************************************)
\* C6: every object the snapshot sees is returned exactly once
NoDup == ~dup
ExactlyOnce == spc = "done" => ret = vis
NoResumeError == bad = {}
\* C7: the scan finishes
ScanFinishes == (spc = "susp") ~> (spc = "done")

\* witnesses
NoMergeWhileSusp == ~(spc = "susp" /\ "merge" \in seen)
NoPartialWhileSusp == ~(spc = "susp" /\ "partial" \in seen)
=============================================================================
