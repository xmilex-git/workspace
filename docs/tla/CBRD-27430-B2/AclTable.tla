------------------------------ MODULE AclTable ------------------------------
(* CBRD-27430 B2: the db:dbuser:ip table of the driver sessions (cas_access_control_file).

   A load reads the file into a table of its own and puts that table in place of the one the checks read;
   when the file is missing or cannot be read in full the place is cleared and marked failed, and a check
   then rejects every client that is not the local host. A check reads the table and the mark together.
   Loads are `cubrid server acl reload` and the load the first check makes.

   Roles: NL loading threads, NC checking session threads, the administrator who edits the file.

   Constants:
     NL, NC   loaders, checkers      MaxF   edits of the file
     Mutant   "none" | "load_unserialized" | "check_unlocked" *)
EXTENDS Naturals, FiniteSets

CONSTANTS NL, NC, MaxF, Mutant

\* apalache-type: NL Int
\* apalache-type: NC Int
\* apalache-type: MaxF Int
\* apalache-type: Mutant Str
\* apalache-type: fver Int
\* apalache-type: fbad Bool
\* apalache-type: tver Int
\* apalache-type: failed Bool
\* apalache-type: loaded Bool
\* apalache-type: loadLock Int
\* apalache-type: lpc Int -> Str
\* apalache-type: lver Int -> Int
\* apalache-type: lbad Int -> Bool
\* apalache-type: doneMax Int
\* apalache-type: pubs Set({v: Int, f: Bool})
\* apalache-type: cpc Int -> Str
\* apalache-type: sver Int -> Int
\* apalache-type: sfail Int -> Bool

\* fver, fbad: the file: its edit count, and whether it can be read in full
\* tver: the table in place: the edit it was read from, 0 when cleared
\* failed, loaded: cas_Acl_load_failed, cas_Acl_loaded
\* loadLock: cas_Acl_load_mutex: the loader that has it, 0 when free
\* lpc, lver, lbad: per loader: "idle" | "parse" | "swap", and what it read
\* doneMax: the newest edit a finished load read
\* pubs: every pair of table and mark that was in place
\* cpc, sver, sfail: per checker: "idle" | "half" (mutant) | "done", and what it read
VARIABLES fver, fbad, tver, failed, loaded, loadLock, lpc, lver, lbad, doneMax, pubs, cpc, sver, sfail

vars == <<fver, fbad, tver, failed, loaded, loadLock, lpc, lver, lbad, doneMax, pubs, cpc, sver, sfail>>

L == 1..NL
C == 1..NC

Init ==
  /\ fver = 1 /\ fbad = FALSE
  /\ tver = 0 /\ failed = FALSE /\ loaded = FALSE
  /\ loadLock = 0
  /\ lpc = [l \in L |-> "idle"] /\ lver = [l \in L |-> 0] /\ lbad = [l \in L |-> FALSE]
  /\ doneMax = 0
  /\ pubs = {}
  /\ cpc = [c \in C |-> "idle"] /\ sver = [c \in C |-> 0] /\ sfail = [c \in C |-> FALSE]

\* the administrator rewrites the file; a rewrite may leave it unreadable
FEdit(bad) ==
  /\ fver <= MaxF
  /\ fver' = fver + 1 /\ fbad' = bad
  /\ UNCHANGED <<tver, failed, loaded, loadLock, lpc, lver, lbad, doneMax, pubs, cpc, sver, sfail>>

\* cas_server_acl_reload takes cas_Acl_load_mutex
LStart(l) ==
  /\ lpc[l] = "idle"
  /\ IF Mutant = "load_unserialized" THEN UNCHANGED loadLock ELSE loadLock = 0 /\ loadLock' = l
  /\ lpc' = [lpc EXCEPT ![l] = "parse"]
  /\ UNCHANGED <<fver, fbad, tver, failed, loaded, lver, lbad, doneMax, pubs, cpc, sver, sfail>>

\* cas_acl_parse: the file as it is now, into the loader's own table
LParse(l) ==
  /\ lpc[l] = "parse"
  /\ lver' = [lver EXCEPT ![l] = fver] /\ lbad' = [lbad EXCEPT ![l] = fbad]
  /\ lpc' = [lpc EXCEPT ![l] = "swap"]
  /\ UNCHANGED <<fver, fbad, tver, failed, loaded, loadLock, doneMax, pubs, cpc, sver, sfail>>

\* under cas_Acl_mutex: the table and the mark change together; then cas_Acl_load_mutex is released
LSwap(l) ==
  /\ lpc[l] = "swap"
  /\ tver' = lver[l] /\ failed' = lbad[l] /\ loaded' = TRUE
  /\ pubs' = pubs \union {[v |-> lver[l], f |-> lbad[l]]}
  /\ doneMax' = IF lver[l] > doneMax THEN lver[l] ELSE doneMax
  /\ loadLock' = IF loadLock = l THEN 0 ELSE loadLock
  /\ lpc' = [lpc EXCEPT ![l] = "idle"]
  /\ UNCHANGED <<fver, fbad, lver, lbad, cpc, sver, sfail>>

\* cas_server_acl_check under cas_Acl_mutex: the table and the mark as one read
CCheck(c) ==
  /\ cpc[c] = "idle" /\ loaded
  /\ sfail' = [sfail EXCEPT ![c] = failed]
  /\ IF Mutant = "check_unlocked"
       THEN cpc' = [cpc EXCEPT ![c] = "half"] /\ UNCHANGED sver
       ELSE cpc' = [cpc EXCEPT ![c] = "done"] /\ sver' = [sver EXCEPT ![c] = tver]
  /\ UNCHANGED <<fver, fbad, tver, failed, loaded, loadLock, lpc, lver, lbad, doneMax, pubs>>

\* mutant: the table read in a second step, with no mutex around the two
CCheckTable(c) ==
  /\ cpc[c] = "half"
  /\ sver' = [sver EXCEPT ![c] = tver]
  /\ cpc' = [cpc EXCEPT ![c] = "done"]
  /\ UNCHANGED <<fver, fbad, tver, failed, loaded, loadLock, lpc, lver, lbad, doneMax, pubs, sfail>>

\* the next client of the session's broker
CAgain(c) ==
  /\ cpc[c] = "done"
  /\ cpc' = [cpc EXCEPT ![c] = "idle"]
  /\ UNCHANGED <<fver, fbad, tver, failed, loaded, loadLock, lpc, lver, lbad, doneMax, pubs, sver, sfail>>

Next ==
  \/ \E bad \in BOOLEAN : FEdit(bad)
  \/ \E l \in L : LStart(l) \/ LParse(l) \/ LSwap(l)
  \/ \E c \in C : CCheck(c) \/ CCheckTable(c) \/ CAgain(c)

Spec == Init /\ [][Next]_vars

Vers == 0..(MaxF + 1)
Pubs == [v : Vers, f : BOOLEAN]

TypeOK ==
  /\ fver \in 1..(MaxF + 1) /\ fbad \in BOOLEAN
  /\ tver \in Vers /\ failed \in BOOLEAN /\ loaded \in BOOLEAN
  /\ loadLock \in 0..NL
  /\ lpc \in [L -> {"idle", "parse", "swap"}] /\ lver \in [L -> Vers] /\ lbad \in [L -> BOOLEAN]
  /\ doneMax \in Vers
  /\ pubs \in SUBSET Pubs
  /\ cpc \in [C -> {"idle", "half", "done"}] /\ sver \in [C -> Vers] /\ sfail \in [C -> BOOLEAN]

\* C2: a check is decided by one table and its mark as they were in place together
OneTable == \A c \in C : cpc[c] = "done" => [v |-> sver[c], f |-> sfail[c]] \in pubs

\* C2: the table in place was read from the file no earlier than any finished load read it
Fresh == loaded => tver >= doneMax

(* ---- the inductive invariant ---- *)

\* a loader between its start and its swap has cas_Acl_load_mutex, and nobody else has it
LoaderHasLock == \A l \in L : lpc[l] \in {"parse", "swap"} <=> loadLock = l

\* what a loader read is no newer than the file and no older than what any finished load read
ReadIsRecent == \A l \in L : lpc[l] = "swap" => lver[l] <= fver /\ lver[l] >= doneMax

\* the file is at least as new as anything read from it
FileNewest == doneMax <= fver /\ tver <= fver

\* what is in place was put there by a load
InPlaceIsPublished ==
  /\ loaded => [v |-> tver, f |-> failed] \in pubs
  /\ ~loaded => tver = 0 /\ doneMax = 0 /\ pubs = {}

\* a check is at one step
CheckOneStep == \A c \in C : cpc[c] # "half"

IndInv ==
  /\ TypeOK
  /\ LoaderHasLock
  /\ ReadIsRecent
  /\ FileNewest
  /\ InPlaceIsPublished
  /\ CheckOneStep
  /\ OneTable
  /\ Fresh

CInit == NL = 2 /\ NC = 2 /\ MaxF = 2 /\ Mutant = "none"

\* witnesses
NotFailClosed == ~(\E c \in C : cpc[c] = "done" /\ sfail[c])
NotReloaded == ~(\E c \in C : cpc[c] = "done" /\ sver[c] > 1 /\ ~sfail[c])

=============================================================================
