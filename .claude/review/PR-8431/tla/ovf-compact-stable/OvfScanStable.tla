--------------------------- MODULE OvfScanStable ---------------------------
(***************************************************************************)
(* PR #8431 (CBRD-27972) head 6cc3c42d4: ALTER INDEX ... COMPACT appends   *)
(* to a key's overflow chain only while the key's leaf record holds a      *)
(* stable object (insert committed, no delete MVCCID), checked under the   *)
(* same leaf WRITE latch as the pulls (xbtree_compact_overflow,            *)
(* btree_compact_leaf_has_stable_object); indexes of MVCC-disabled classes *)
(* are not compacted.  OvfScanResume let any object outside the scan's     *)
(* snapshot be removed at any time; here every object carries its MVCC     *)
(* state, so a removal is a rollback of an uncommitted insert or a vacuum  *)
(* of a committed delete, and vacuum keeps every object that was stable    *)
(* while the scan's snapshot lives (the scan is the oldest snapshot).      *)
(***************************************************************************)
EXTENDS OvfScanResume

CONSTANTS GFix, GMutant, NoMvcc

ASSUME GFix \in {"none", "stable_leaf"}
ASSUME GMutant \in {"none", "stale_check", "delid_stable", "uncommitted_stable", "no_class_check",
                    "env_vacuum_ignores_snapshot"}
ASSUME NoMvcc \in BOOLEAN

VARIABLES st,     \* [Obj -> {"none","ins","stable","delu","delc"}]: MVCC state of each object
  prot,   \* objects stable at some point while the scan's snapshot lives: vacuum keeps them
  cok,    \* stale_check mutant only: the stable-leaf answer of an earlier latch round
  pulled, \* ghost: a COMPACT pull ran during the current suspension
  lostg   \* ghost: a leaf swap during a suspension moved an object the scan had not returned

gvars == <<st, prot, cok, pulled, lostg>>
gall == <<allvars, gvars>>
GView == <<SView, st, prot, cok, pulled>>

Susp == spc = "susp"

(* btree_compact_leaf_has_stable_object: no delete MVCCID, insert MVCCID neither ours nor active;
   an object of an MVCC-disabled class carries neither, so the callback would call it stable *)
StableAs(o) ==
  IF NoMvcc THEN TRUE
  ELSE IF GMutant = "delid_stable" THEN st[o] \in {"stable", "delu", "delc"}
  ELSE IF GMutant = "uncommitted_stable" THEN st[o] \in {"stable", "ins"}
  ELSE st[o] = "stable"
LeafHasStable == \E o \in leaf : StableAs(o)

\* xbtree_compact_overflow: the class check at entry, then the leaf check in the pull's latch round
Guard ==
  \/ GFix = "none"
  \/ /\ ~NoMvcc \/ GMutant = "no_class_check"
     /\ IF GMutant = "stale_check" THEN cok ELSE LeafHasStable

(* vacuum removes a committed delete, rollback an uncommitted insert; a class without MVCC removes
   physically at any time.  The scan's snapshot keeps what it sees and what was stable during it. *)
Removable(o) == NoMvcc \/ st[o] \in {"ins", "delc"}
Protected(o) ==
  Susp /\ ~NoMvcc /\ (o \in vis \/ (o \in prot /\ GMutant # "env_vacuum_ignores_snapshot"))

AddProt(o) == prot' = IF Susp THEN prot \cup {o} ELSE prot

InsertS(o) ==
  /\ \A x \in live : Oid(x) = Oid(o) => (~NoMvcc /\ st[x] = "delc")   \* an OID is reused only after its delete
  /\ Insert(o)
  /\ st' = [st EXCEPT ![o] = IF NoMvcc THEN "stable" ELSE "ins"]
  /\ UNCHANGED <<prot, cok, pulled, lostg>>

Mvcc(o, from, to) ==
  /\ ~NoMvcc /\ o \in live /\ st[o] = from
  /\ st' = [st EXCEPT ![o] = to]
  /\ IF to = "stable" THEN AddProt(o) ELSE UNCHANGED prot
  /\ UNCHANGED <<vars, cok, pulled, lostg>>

CommitIns(o) == Mvcc(o, "ins", "stable")
DeleteS(o) == Mvcc(o, "stable", "delu")
CommitDel(o) == Mvcc(o, "delu", "delc")
AbortDel(o) == Mvcc(o, "delu", "stable")

LostBySwap(o) ==
  Susp /\ o \in leaf /\ chain # <<>> /\ Last(data[chain[1]]) \in vis \ ret

RemoveS(o) ==
  /\ o \in live
  /\ Removable(o)
  /\ ~Protected(o)
  /\ ~NoMvcc => o \notin vis   \* OvfScanResume's Env: the snapshot keeps what it sees; no snapshot without MVCC
  /\ Remove(o)
  /\ st' = [st EXCEPT ![o] = "none"]
  /\ lostg' = (lostg \/ LostBySwap(o))
  /\ UNCHANGED <<prot, cok, pulled>>

PullS ==
  /\ Guard
  /\ Pull
  /\ pulled' = (pulled \/ Susp)
  /\ UNCHANGED <<st, prot, cok, lostg>>

\* stale_check mutant: the answer is taken in one latch round and reused after a yield
CompactCheck ==
  /\ GMutant = "stale_check"
  /\ Idle
  /\ cok' = LeafHasStable
  /\ UNCHANGED <<vars, st, prot, pulled, lostg>>

\* the key is skipped (pairs_skipped): a COMPACT refused a chain it could have pulled
CompactSkip ==
  /\ GFix # "none" /\ Compact /\ Idle
  /\ Len(chain) >= 2 /\ hdr[chain[1]] = "H"
  /\ ~Guard
  /\ "skip" \notin seen
  /\ seen' = seen \cup {"skip"}
  /\ UNCHANGED <<chain, data, hdr, dir, leaf, live, stale, pend, bad, gvars>>

EnvS ==
  /\ spc # "done"
  /\ \/ \E o \in Obj : InsertS(o) \/ CommitIns(o) \/ DeleteS(o) \/ CommitDel(o) \/ AbortDel(o) \/ RemoveS(o)
     \/ PullS
     \/ CompactCheck
     \/ CompactSkip
  /\ UNCHANGED svars

VisNow == IF NoMvcc THEN live ELSE {o \in live : st[o] \in {"stable", "delu"}}

(* the scan's snapshot sees committed inserts whose delete is not committed; KeyIter reads the key *)
SStartS ==
  /\ spc = "idle"
  /\ Idle
  /\ leaf # {}
  /\ vis' = VisNow
  /\ KeyIter(VisNow)
  /\ prot' = IF NoMvcc THEN {} ELSE {o \in live : st[o] = "stable"}
  /\ pulled' = FALSE
  /\ UNCHANGED <<vars, st, cok, lostg>>

SResumeS ==
  /\ SResume
  /\ pulled' = FALSE
  /\ UNCHANGED <<st, prot, cok, lostg>>

SEndS == spc = "done" /\ UNCHANGED gall

GInit == SInit /\ st = [o \in Obj |-> "none"] /\ prot = {} /\ cok = FALSE /\ pulled = FALSE /\ lostg = FALSE

GNext == SStartS \/ SResumeS \/ EnvS \/ SEndS

GSpec == GInit /\ [][GNext]_gall /\ WF_gall(SResumeS)

(***************************************************************************)
\* C1 (ExactlyOnce, NoDup from OvfScanResume) and C2: no swap moves an unreturned object
NoLostSwap == ~lostg
\* C4: COMPACT never pulls in an index of a class without MVCC
NoCompactNoMvcc == NoMvcc => seen \cap {"merge", "partial"} = {}
\* without MVCC objects go at any time; every object seen at the scan's start and still live at its end is returned
Complete == spc = "done" => vis \cap live \subseteq ret
\* C3 (well-formedness of the MVCC ghost): the stable objects seen during the suspension are protected
StableProtected == Susp /\ ~NoMvcc => \A o \in live : st[o] = "stable" => o \in prot \cup vis

\* refinement to the abstract guard model
A == INSTANCE OvfGuard WITH
       spc <- spc,
       u <- pulled,
       ls <- ~NoMvcc /\ \E o \in leaf : st[o] = "stable",
       lp <- \E o \in leaf : Protected(o),
       lost <- lostg,
       AMutant <- "none"
GuardRefined == A!Spec

\* witnesses
NoPullWhileSusp == ~(Susp /\ pulled)
NoSkip == "skip" \notin seen
=============================================================================
