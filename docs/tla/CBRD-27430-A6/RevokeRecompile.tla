--------------------------- MODULE RevokeRecompile ---------------------------
(* CBRD-27430 A6: a REVOKE touches the class so that other sessions' prepared
   statements recompile, and the recompile checks the authorization again.

   au_revoke_class (authenticate_grant.cpp) updates the grantee's
   authorization instance (obj_inst_lock X, an MVCC update), then
   sm_touch_class: dbt_edit/finish of the class under SCH_M, whose flush
   (locator_update_force) removes the class's XASL cache entries. The commit
   (log_commit_local) makes the update visible (logtb_complete_mvcc), removes
   the entries again (log_cleanup_modified_class) and releases the locks
   (lock_unlock_all), in that order.

   A grantee session compiles a statement on the class: SCH_S on the class
   (pt_class_pre_fetch / au_fetch_class, held to the end of the transaction),
   then check_authorization, whose Au_cache bits for the class are computed
   once per transaction by authenticate_cache::update from the grantee's
   groups and grants. The plan goes into the XASL cache and the session keeps
   the handle. A kept handle runs again without a compile:
   xcache_find_xasl_id_for_execute finds the entry, locks the class (IS) and
   checks the entry was not removed meanwhile; a removed entry is
   ER_QPROC_INVALID_XASLNODE and the session compiles again.

   authenticate_cache::update reads the groups and grants at their latest
   committed version (LC_FETCH_COMMITTED_VERSION, no lock, no snapshot;
   SERVER_MODE). Before A6 it read them through the transaction's snapshot
   (mutant "snapshot-auth").

   One class t, one grantee user, one REVOKE. Sessions 1..NS are the
   grantee's; the revoker is a DBA session. A separate dropper process drops
   another class that has an index and a grant (sm_delete_class_mop).

   Constants:
     NS        grantee sessions
     MaxStmt   statements per grantee session (a commit or rollback ends a
               transaction, the next statement starts one)
     AllowRR   whether a transaction may run under REPEATABLE READ
     Mutant    "none" | "snapshot-auth" | "committed-locks" | "cached-lock"
               | "no-touch" | "touch-no-lock" | "no-recheck" | "no-au-reset"
               | "drop-free-first" *)
EXTENDS Naturals

CONSTANTS NS, MaxStmt, AllowRR, Mutant

\* apalache-type: NS Int
\* apalache-type: MaxStmt Int
\* apalache-type: AllowRR Bool
\* apalache-type: Mutant Str
\* apalache-type: rev Str
\* apalache-type: pc Int -> Str
\* apalache-type: iso Int -> Str
\* apalache-type: sLock Int -> Bool
\* apalache-type: auS Int -> Bool
\* apalache-type: wsAuth Int -> Str
\* apalache-type: snap Int -> Str
\* apalache-type: auc Int -> Str
\* apalache-type: tranAfter Int -> Bool
\* apalache-type: tid Int -> Int
\* apalache-type: stmts Int -> Int
\* apalache-type: handle Int -> Int
\* apalache-type: xdel Int -> Bool
\* apalache-type: xpost Int -> Bool
\* apalache-type: nextId Int
\* apalache-type: live Int
\* apalache-type: dropPc Str
\* apalache-type: bad Bool
\* apalache-type: badDel Bool
\* apalache-type: dropCrash Bool

Sess == 1..NS
MaxId == NS * MaxStmt * 2 + 3
Ids == 1..MaxId

ASSUME Assm ==
  /\ NS \in Nat \ {0} /\ MaxStmt \in Nat \ {0}
  /\ AllowRR \in BOOLEAN
  /\ Mutant \in {"none", "snapshot-auth", "committed-locks", "cached-lock", "no-touch", "touch-no-lock",
                "no-recheck", "no-au-reset", "drop-free-first"}

VARIABLES rev, \* the revoker: idle, updated, locked, committed, cleaned, done, aborted
  pc,         \* a grantee session's step
  iso,        \* its transaction's isolation
  sLock,      \* it holds SCH_S / IS on t (to the end of its transaction)
  auS,        \* it holds S on its authorization instance (mutant "committed-locks")
  wsAuth,     \* the grants its workspace holds as locked, so never fetches again (mutant "cached-lock")
  snap,       \* its MVCC snapshot: none, or the grant state it sees
  auc,        \* its Au_cache bits for t: none (invalid), grant, revoked
  tranAfter,  \* its transaction began after the REVOKE committed (ghost)
  tid,        \* its transaction number (ghost)
  stmts,      \* statements it started
  handle,     \* its prepared handle: an XASL cache entry id, 0 = none
  xdel,       \* entry id -> marked deleted (XCACHE_ENTRY_MARK_DELETED)
  xpost,      \* entry id -> inserted after the touch (ghost)
  nextId,     \* next entry id
  live,       \* the entry the statement's sha1 finds, 0 = none
  dropPc,     \* the dropper
  bad,        \* ghost: a plan ran in a grantee transaction that began after the REVOKE committed
  badDel,     \* ghost: a removed entry ran
  dropCrash   \* ghost: the DROP's touch met freed disk structures

vars == <<rev, pc, iso, sLock, auS, wsAuth, snap, auc, tranAfter, tid, stmts, handle, xdel, xpost, nextId, live,
          dropPc, bad, badDel, dropCrash>>

Committed == rev \in {"committed", "cleaned", "done"}
\* the latest committed grant state, which a snapshot built now also sees
View == IF Committed THEN "revoked" ELSE "grant"
\* the revoker holds SCH_M on t
SM == rev \in {"locked", "committed", "cleaned"} /\ Mutant /= "touch-no-lock"
Touches == Mutant /= "no-touch"

RemoveAll == /\ xdel' = [i \in Ids |-> IF i < nextId THEN TRUE ELSE xdel[i]]
             /\ live' = 0

Init ==
  /\ rev = "idle"
  /\ pc = [s \in Sess |-> "idle"]
  /\ iso = [s \in Sess |-> "RC"]
  /\ sLock = [s \in Sess |-> FALSE]
  /\ auS = [s \in Sess |-> FALSE]
  /\ wsAuth = [s \in Sess |-> "none"]
  /\ snap = [s \in Sess |-> "none"]
  /\ auc = [s \in Sess |-> "none"]
  /\ tranAfter = [s \in Sess |-> FALSE]
  /\ tid = [s \in Sess |-> 0]
  /\ stmts = [s \in Sess |-> 0]
  /\ handle = [s \in Sess |-> 0]
  /\ xdel = [i \in Ids |-> FALSE]
  /\ xpost = [i \in Ids |-> FALSE]
  /\ nextId = 1
  /\ live = 0
  /\ dropPc = "start"
  /\ bad = FALSE /\ badDel = FALSE /\ dropCrash = FALSE

AuVars == <<auS, wsAuth, snap, auc>>
SessVars == <<pc, iso, sLock, AuVars, tranAfter, tid, stmts, handle>>
XVars == <<xdel, xpost, nextId, live>>
\* @type: <<Bool, Bool, Bool>>;
Ghosts == <<bad, badDel, dropCrash>>

(* ---------------- the revoker ---------------- *)

\* au_revoke_class: au_fetch_instance (auth, AU_FETCH_UPDATE) and obj_inst_lock (auth, 1) take X on the
\* grantee's authorization instance; set_put_element / drop_grant_entry, delete_auth
RUpdate ==
  /\ rev = "idle"
  /\ \A s \in Sess : ~auS[s]
  /\ rev' = "updated"
  /\ UNCHANGED <<SessVars, XVars, dropPc, Ghosts>>

\* sm_touch_class: SCH_M on t (dbt_edit_class), flush (locator_update_force -> xcache_remove_by_oid)
RTouch ==
  /\ rev = "updated" /\ Touches
  /\ Mutant = "touch-no-lock" \/ \A s \in Sess : ~sLock[s]
  /\ rev' = "locked"
  /\ RemoveAll
  /\ UNCHANGED <<SessVars, xpost, nextId, dropPc, Ghosts>>

\* log_commit_local: logtb_complete_mvcc (the update becomes visible)
RCommit ==
  /\ rev = IF Touches THEN "locked" ELSE "updated"
  /\ rev' = "committed"
  /\ UNCHANGED <<SessVars, XVars, dropPc, Ghosts>>

\* log_cleanup_modified_class -> xcache_remove_by_oid
RCleanup ==
  /\ rev = "committed"
  /\ rev' = "cleaned"
  /\ IF Touches THEN RemoveAll ELSE UNCHANGED <<xdel, live>>
  /\ UNCHANGED <<SessVars, xpost, nextId, dropPc, Ghosts>>

\* lock_unlock_all
RUnlock ==
  /\ rev = "cleaned"
  /\ rev' = "done"
  /\ UNCHANGED <<SessVars, XVars, dropPc, Ghosts>>

\* the REVOKE fails (SCH_M lock timeout, deadlock victim, an error of the touch) and rolls back:
\* log_abort_local removes the entries of a touched class
RAbort ==
  /\ rev \in {"updated", "locked"}
  /\ rev' = "aborted"
  /\ IF rev = "locked" THEN RemoveAll ELSE UNCHANGED <<xdel, live>>
  /\ UNCHANGED <<SessVars, xpost, nextId, dropPc, Ghosts>>

(* ---------------- a grantee session ---------------- *)

\* the grant state an authorization read returns now
GrantRead(s) ==
  IF Mutant = "snapshot-auth" THEN (IF snap[s] /= "none" THEN snap[s] ELSE View)
  ELSE IF Mutant = "cached-lock" /\ wsAuth[s] /= "none" THEN wsAuth[s]
  ELSE View

\* the read's side effects: the snapshot it builds, the lock it takes, the copy it caches as locked
ReadEffects(s) ==
  /\ snap' = [snap EXCEPT ![s] = IF Mutant = "snapshot-auth" /\ @ = "none" THEN View ELSE @]
  /\ auS' = [auS EXCEPT ![s] = @ \/ Mutant = "committed-locks"]
  /\ wsAuth' = [wsAuth EXCEPT ![s] = IF Mutant = "cached-lock" /\ @ = "none" THEN View ELSE @]

\* the first statement of a transaction starts it
SBegin(s) ==
  /\ pc[s] = "idle" /\ stmts[s] < MaxStmt
  /\ pc' = [pc EXCEPT ![s] = "stmt"]
  /\ tranAfter' = [tranAfter EXCEPT ![s] = Committed]
  /\ tid' = [tid EXCEPT ![s] = @ + 1]
  /\ \E i \in (IF AllowRR THEN {"RC", "RR"} ELSE {"RC"}) : iso' = [iso EXCEPT ![s] = i]
  /\ UNCHANGED <<rev, sLock, AuVars, stmts, handle, XVars, dropPc, Ghosts>>

\* a statement starts (RC: db_invalidate_mvcc_snapshot_before_statement); a new prepare or a kept handle
SStmt(s) ==
  /\ pc[s] = "stmt" /\ stmts[s] < MaxStmt
  /\ stmts' = [stmts EXCEPT ![s] = @ + 1]
  /\ snap' = [snap EXCEPT ![s] = IF iso[s] = "RC" THEN "none" ELSE @]
  /\ \/ /\ pc' = [pc EXCEPT ![s] = "pre"]
        /\ handle' = [handle EXCEPT ![s] = 0]
     \/ /\ handle[s] /= 0
        /\ pc' = [pc EXCEPT ![s] = "elook"]
        /\ UNCHANGED handle
  /\ UNCHANGED <<rev, iso, sLock, auS, wsAuth, auc, tranAfter, tid, XVars, dropPc, Ghosts>>

\* the authorization check of another class before t's class lock (in the same statement under RC through a
\* view or synonym resolved after pt_class_pre_fetch, or an earlier statement of an RR transaction): it reads
\* the grants, and builds the snapshot when the read goes through it
SAuOther(s) ==
  /\ pc[s] = "pre"
  /\ ReadEffects(s)
  /\ pc' = [pc EXCEPT ![s] = "plock"]
  /\ UNCHANGED <<rev, iso, sLock, auc, tranAfter, tid, stmts, handle, XVars, dropPc, Ghosts>>

SSkipOther(s) ==
  /\ pc[s] = "pre"
  /\ pc' = [pc EXCEPT ![s] = "plock"]
  /\ UNCHANGED <<rev, iso, sLock, AuVars, tranAfter, tid, stmts, handle, XVars, dropPc, Ghosts>>

\* pt_class_pre_fetch / au_fetch_class: SCH_S on t (waits while the revoker holds SCH_M)
SPLock(s) ==
  /\ pc[s] = "plock"
  /\ sLock[s] \/ ~SM
  /\ sLock' = [sLock EXCEPT ![s] = TRUE]
  /\ pc' = [pc EXCEPT ![s] = "au"]
  /\ UNCHANGED <<rev, iso, AuVars, tranAfter, tid, stmts, handle, XVars, dropPc, Ghosts>>

\* check_authorization: the Au_cache bits, else authenticate_cache::update reads the groups and grants
SAu(s) ==
  /\ pc[s] = "au"
  /\ IF auc[s] /= "none"
     THEN UNCHANGED AuVars
     ELSE /\ ReadEffects(s)
          /\ auc' = [auc EXCEPT ![s] = GrantRead(s)]
  /\ LET view == IF auc[s] /= "none" THEN auc[s] ELSE GrantRead(s) IN
     IF view = "revoked"
     THEN /\ pc' = [pc EXCEPT ![s] = "end"]      \* ER_PT_SEMANTIC (not authorized)
          /\ handle' = [handle EXCEPT ![s] = 0]
     ELSE /\ pc' = [pc EXCEPT ![s] = "ins"]
          /\ UNCHANGED handle
  /\ UNCHANGED <<rev, iso, sLock, tranAfter, tid, stmts, XVars, dropPc, Ghosts>>

\* xcache_insert: the sha1 finds a live entry, or a new one is inserted
SIns(s) ==
  /\ pc[s] = "ins"
  /\ IF live /= 0
     THEN /\ handle' = [handle EXCEPT ![s] = live]
          /\ UNCHANGED XVars
     ELSE /\ nextId <= MaxId
          /\ handle' = [handle EXCEPT ![s] = nextId]
          /\ xdel' = [xdel EXCEPT ![nextId] = FALSE]
          /\ xpost' = [xpost EXCEPT ![nextId] = rev \in {"locked", "committed", "cleaned", "done"}]
          /\ live' = nextId
          /\ nextId' = nextId + 1
  /\ pc' = [pc EXCEPT ![s] = "elook"]
  /\ UNCHANGED <<rev, iso, sLock, AuVars, tranAfter, tid, stmts, dropPc, Ghosts>>

\* xcache_find_xasl_id_for_execute: the entry by xasl_id (sha1 + time_stored); gone or removed -> recompile
SELook(s) ==
  /\ pc[s] = "elook"
  /\ pc' = [pc EXCEPT ![s] = IF handle[s] = 0 \/ xdel[handle[s]] THEN "pre" ELSE "elock"]
  /\ UNCHANGED <<rev, iso, sLock, AuVars, tranAfter, tid, stmts, handle, XVars, dropPc, Ghosts>>

\* lock_object on every related class (IS on t; waits while the revoker holds SCH_M)
SELock(s) ==
  /\ pc[s] = "elock"
  /\ sLock[s] \/ ~SM
  /\ sLock' = [sLock EXCEPT ![s] = TRUE]
  /\ pc' = [pc EXCEPT ![s] = "echeck"]
  /\ UNCHANGED <<rev, iso, AuVars, tranAfter, tid, stmts, handle, XVars, dropPc, Ghosts>>

\* after the locks: XCACHE_ENTRY_MARK_DELETED -> recompile; else the plan runs
SECheck(s) ==
  /\ pc[s] = "echeck"
  /\ IF xdel[handle[s]] /\ Mutant /= "no-recheck"
     THEN /\ pc' = [pc EXCEPT ![s] = "pre"]
          /\ UNCHANGED Ghosts
     ELSE /\ pc' = [pc EXCEPT ![s] = "end"]
          /\ bad' = (bad \/ tranAfter[s])
          /\ badDel' = (badDel \/ xdel[handle[s]])
          /\ UNCHANGED dropCrash
  /\ UNCHANGED <<rev, iso, sLock, AuVars, tranAfter, tid, stmts, handle, XVars, dropPc>>

\* the statement ended (ran, or the compile was refused); the next one runs in the same transaction
SNext(s) ==
  /\ pc[s] = "end" /\ stmts[s] < MaxStmt
  /\ pc' = [pc EXCEPT ![s] = "stmt"]
  /\ UNCHANGED <<rev, iso, sLock, AuVars, tranAfter, tid, stmts, handle, XVars, dropPc, Ghosts>>

\* commit, or rollback after a lock timeout / deadlock while waiting: locks released (the workspace's locks
\* too), snapshot dropped, Au_cache reset (the workspace's transaction callback)
EndTran(s) ==
  /\ pc' = [pc EXCEPT ![s] = "idle"]
  /\ sLock' = [sLock EXCEPT ![s] = FALSE]
  /\ auS' = [auS EXCEPT ![s] = FALSE]
  /\ wsAuth' = [wsAuth EXCEPT ![s] = "none"]
  /\ snap' = [snap EXCEPT ![s] = "none"]
  /\ auc' = [auc EXCEPT ![s] = IF Mutant = "no-au-reset" THEN @ ELSE "none"]
  /\ UNCHANGED <<rev, iso, tranAfter, tid, stmts, handle, XVars, dropPc, Ghosts>>

SCommit(s) == pc[s] = "end" /\ EndTran(s)
SAbort(s) == pc[s] \in {"plock", "elock"} /\ EndTran(s)

(* ---------------- the dropper (another class with an index and a grant) ---------------- *)

\* sm_delete_class_mop: au_object_revoke_all_privileges (each au_revoke_class touches the class, which
\* rebuilds the representation through transfer_disk_structures), then transfer_disk_structures (NULL)
\* frees the indexes; a touch after the free meets con->index_btid already NULL (deallocate_index)
DRevoke ==
  /\ dropPc = IF Mutant = "drop-free-first" THEN "freed" ELSE "start"
  /\ dropPc' = IF Mutant = "drop-free-first" THEN "done" ELSE "revoked"
  /\ dropCrash' = (Mutant = "drop-free-first")
  /\ UNCHANGED <<rev, SessVars, XVars, bad, badDel>>

DFree ==
  /\ dropPc = IF Mutant = "drop-free-first" THEN "start" ELSE "revoked"
  /\ dropPc' = IF Mutant = "drop-free-first" THEN "freed" ELSE "done"
  /\ UNCHANGED <<rev, SessVars, XVars, Ghosts>>

Done ==
  /\ rev \in {"done", "aborted"} /\ dropPc = "done"
  /\ \A s \in Sess : pc[s] = "idle" /\ stmts[s] = MaxStmt
  /\ UNCHANGED vars

Next ==
  \/ RUpdate \/ RTouch \/ RCommit \/ RCleanup \/ RUnlock \/ RAbort
  \/ \E s \in Sess : \/ SBegin(s) \/ SStmt(s) \/ SAuOther(s) \/ SSkipOther(s) \/ SPLock(s) \/ SAu(s)
                     \/ SIns(s) \/ SELook(s) \/ SELock(s) \/ SECheck(s) \/ SNext(s) \/ SCommit(s)
                     \/ SAbort(s)
  \/ DRevoke \/ DFree
  \/ Done

Spec == Init /\ [][Next]_vars

(* ---------------- properties ---------------- *)

TypeOK ==
  /\ rev \in {"idle", "updated", "locked", "committed", "cleaned", "done", "aborted"}
  /\ pc \in [Sess -> {"idle", "stmt", "pre", "plock", "au", "ins", "elook", "elock", "echeck", "end"}]
  /\ iso \in [Sess -> {"RC", "RR"}]
  /\ sLock \in [Sess -> BOOLEAN] /\ auS \in [Sess -> BOOLEAN]
  /\ wsAuth \in [Sess -> {"none", "grant", "revoked"}]
  /\ snap \in [Sess -> {"none", "grant", "revoked"}]
  /\ auc \in [Sess -> {"none", "grant", "revoked"}]
  /\ tranAfter \in [Sess -> BOOLEAN]
  /\ tid \in [Sess -> 0..MaxStmt] /\ stmts \in [Sess -> 0..MaxStmt]
  /\ handle \in [Sess -> 0..MaxId]
  /\ xdel \in [Ids -> BOOLEAN] /\ xpost \in [Ids -> BOOLEAN]
  /\ nextId \in 1..(MaxId + 1) /\ live \in 0..MaxId
  /\ dropPc \in {"start", "revoked", "freed", "done"}
  /\ bad \in BOOLEAN /\ badDel \in BOOLEAN /\ dropCrash \in BOOLEAN

\* C1: a grantee transaction that began after the REVOKE committed runs no plan on t
NoRevokedRun == ~bad
\* C4: an execution that holds t's lock never runs an entry a schema change removed
NoRemovedRun == ~badDel
\* C3: the DROP's revoke never touches a class whose disk structures were freed
NoDropCrash == ~dropCrash
\* C5: reading the grants takes no lock, so a REVOKE never waits for a grantee transaction over them
NoGranteeAuthLock == \A s \in Sess : ~auS[s]

\* witnesses
NotKeptRecompiled == ~(\E s \in Sess : pc[s] = "pre" /\ handle[s] /= 0 /\ xdel[handle[s]] /\ Committed)
NotRefusedAfter == ~(\E s \in Sess : tranAfter[s] /\ pc[s] = "end" /\ auc[s] = "revoked")
NotRefusedInOldTran == ~(\E s \in Sess : ~tranAfter[s] /\ Committed /\ pc[s] = "end" /\ auc[s] = "revoked"
                                       /\ iso[s] = "RR")
NotRevokeAborted == rev /= "aborted"

(* ---------------- inductive invariant (Mutant "none") ---------------- *)

IndInv ==
  /\ TypeOK
  /\ ~bad /\ ~badDel /\ ~dropCrash
  /\ \A s \in Sess : ~auS[s] /\ wsAuth[s] = "none" /\ snap[s] = "none"
  /\ live /= 0 => live < nextId /\ ~xdel[live]
  /\ \A i \in Ids : i >= nextId => ~xdel[i] /\ ~xpost[i]
  /\ \A s \in Sess : handle[s] < nextId
  /\ \A s \in Sess : pc[s] \in {"elook", "elock", "echeck"} => handle[s] /= 0
  /\ \A s \in Sess : pc[s] = "idle" => ~sLock[s] /\ auc[s] = "none"
  /\ \A s \in Sess : IF pc[s] = "stmt" THEN tid[s] <= stmts[s] + 1 ELSE tid[s] <= stmts[s]
  /\ \A s \in Sess : auc[s] /= "none" => sLock[s]
  /\ \A s \in Sess : pc[s] \in {"au", "ins", "echeck"} => sLock[s]
  /\ dropPc /= "freed"
  /\ \A s \in Sess : pc[s] = "ins" => auc[s] = "grant"
  \* the revoker's SCH_M excludes every grantee's class lock
  /\ SM => \A s \in Sess : ~sLock[s]
  /\ rev \in {"locked", "committed", "cleaned"} => Mutant /= "touch-no-lock"
  /\ rev \in {"idle", "updated"} => \A i \in Ids : ~xpost[i]
  \* from the touch on, every entry is removed and no compile passes the check
  /\ rev \in {"locked", "committed", "cleaned", "done"} => \A i \in Ids : i < nextId => xdel[i]
  /\ rev \in {"locked", "committed", "cleaned", "done"} => \A s \in Sess : auc[s] /= "grant"
  /\ \A s \in Sess : tranAfter[s] => Committed
  /\ \A s \in Sess : pc[s] = "echeck" /\ ~xdel[handle[s]] => sLock[s] /\ ~SM

=============================================================================
