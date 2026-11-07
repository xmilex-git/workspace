------------------------------ MODULE CscParams ------------------------------
(* CBRD-27430 A5: the sysprm and boot lifecycle of the folded server's sessions.

   Extends the A4 model of one client context (csc) per session (CscSessions, linked from
   docs/tla/CBRD-27430-A4) with what A5 changes:

   - the server boot initializes the client-half modules every session shares (areas, SHOW metadata,
     static methods, the dynamic loader, the login name and IP) before it accepts a session, so a
     session boot takes no boot lock (CscSessions ServerInit = TRUE);
   - the client parameters a session sets are its own: server-session and client-only session
     parameters live in the session's parameter array, which the client half reads and writes in a
     bracket in the client hat; the client-compile parameters the client half reads (ansi_quotes,
     the optimizer's cost_*, ...) became session parameters; SET OPTIMIZATION COST lives in the csc;
     a server-only parameter stays one process value, which only a DBA changes;
   - the plan-cache key prints the session's values;
   - csc_teardown frees the session's client state (savepoints, triggers, authorization caches,
     schema descriptors, query results, kept trees) before ws_final frees the MOPs they refer to.

   Parameter classes (Cls), one parameter of each:
     "ss"    server-session parameter (no_backslash_escapes)
     "co"    client-only session parameter, printed into the plan-cache key (intl_date_lang)
     "cc"    client-compile parameter (ansi_quotes, cost_seq_page)
     "cost"  SET OPTIMIZATION COST of one plan kind
     "sv"    server-only parameter (group_concat_max_len)
   Values: Conf (0) is the cubrid.conf value, Dflt (1) the built-in default; a SET writes 1.
   Session 1 is a DBA, every other session is not. *)
EXTENDS CscSessions

\* apalache-type: gv Str -> Int
\* apalache-type: sv Int -> (Str -> Int)
\* apalache-type: want Int -> (Str -> Int)
\* apalache-type: wantG Int
\* apalache-type: cache Int -> Int
\* apalache-type: showH Int
\* apalache-type: res Int -> Bool
\* apalache-type: bootCC Int
\* apalache-type: cap Bool
\* apalache-type: prmBad Bool
\* apalache-type: planBad Bool
\* apalache-type: authBad Bool
\* apalache-type: parityBad Bool
\* apalache-type: showUaf Bool
\* apalache-type: leak Bool
\* apalache-type: tearUaf Bool
\* apalache-type: refusedNonDba Bool
\* apalache-type: planHit Bool
\* apalache-type: ownRead Bool
\* apalache-type: resFreed Bool

VARIABLES gv, sv, want, wantG, cache, showH, res, bootCC, cap,
  prmBad, planBad, authBad, parityBad, showUaf, leak, tearUaf, refusedNonDba, planHit, ownRead, resFreed

v5 == <<gv, sv, want, wantG, cache, showH, res, bootCC, cap,
  prmBad, planBad, authBad, parityBad, showUaf, leak, tearUaf, refusedNonDba, planHit, ownRead, resFreed>>
all == <<vars, v5>>

Cls == {"ss", "co", "cc", "cost", "sv"}
SessCls == Cls \ {"sv"}
Conf == 0
Dflt == 1
NoCache == 2
SharedHeap == 99
IsDba(s) == s = 1

\* where a value of class c lives for the client half of session s
OnProcess(c) ==
  \/ c = "sv"
  \/ c = "co" /\ Mutant = "no_readthrough"
  \/ c = "cc" /\ Mutant \in {"cc_process", "cas_restore"}
  \/ c = "cost" /\ Mutant = "shared_cost"

\* the conf load: develop's server skips the client-only parameters (built-in defaults)
BootVal(c) == IF Mutant = "no_conf_load" /\ c \in {"co", "cc"} THEN Dflt ELSE Conf

Init5 ==
  /\ Init
  /\ gv = [c \in Cls |-> BootVal(c)]
  /\ sv = [s \in Sess |-> [c \in Cls |-> Conf]]
  /\ want = [s \in Sess |-> [c \in Cls |-> Conf]]
  /\ wantG = Conf
  /\ cache = [k \in {Conf, Dflt} |-> NoCache]
  /\ showH = IF Mutant = "show_in_session" THEN 0 ELSE SharedHeap
  /\ res = [s \in Sess |-> FALSE]
  /\ bootCC = Conf /\ cap = FALSE
  /\ prmBad = FALSE /\ planBad = FALSE /\ authBad = FALSE /\ parityBad = FALSE /\ showUaf = FALSE
  /\ leak = FALSE /\ tearUaf = FALSE
  /\ refusedNonDba = FALSE /\ planHit = FALSE /\ ownRead = FALSE /\ resFreed = FALSE

(* ---- hooks: what an A4 lifecycle step does to the A5 state ---- *)

Reg(s) == sst[s] = "none" /\ sst'[s] = "live"
Torn == {c \in Sess : torn'[c] > torn[c]}

\* db_restart_ex registered the session: csession_find_or_create_session seeds its parameter array from the
\* process values (sysprm_alloc_session_parameters_from_defaults); in develop, the first boot built the SHOW
\* metadata in its own workspace heap; the old CAS restore (cas_execute.c ux_set_default_setting) captured
\* ansi_quotes on the first session and wrote it back to the process value on every later one
RegHook ==
  /\ sv' = [s \in Sess |-> IF Reg(s) THEN gv ELSE sv[s]]
  /\ want' = [s \in Sess |-> IF Reg(s) THEN [c \in Cls |-> Conf] ELSE want[s]]
  /\ showH' = IF Mutant = "show_in_session" /\ showH = 0 /\ \E s \in Sess : Reg(s)
              THEN CHOOSE s \in Sess : Reg(s) ELSE showH
  /\ IF Mutant = "cas_restore" /\ \E s \in Sess : Reg(s)
     THEN IF cap THEN gv' = [gv EXCEPT !["cc"] = bootCC] /\ UNCHANGED <<bootCC, cap>>
          ELSE bootCC' = gv["cc"] /\ cap' = TRUE /\ UNCHANGED gv
     ELSE UNCHANGED <<gv, bootCC, cap>>

\* csc_teardown of a context (A4 Teardown): the session's client state goes before ws_final frees the MOPs it refers
\* to; A4's teardown freed none of it
TearHook ==
  /\ res' = [c \in Sess |-> IF c \in Torn THEN FALSE ELSE res[c]]
  /\ leak' = (leak \/ (Mutant = "a4_teardown" /\ \E c \in Torn : res[c]))
  /\ tearUaf' = (tearUaf \/ (Mutant = "ws_first" /\ \E c \in Torn : res[c]))
  /\ resFreed' = (resFreed \/ (Mutant # "a4_teardown" /\ \E c \in Torn : res[c]))

Hook ==
  /\ RegHook /\ TearHook
  /\ UNCHANGED <<wantG, cache, prmBad, planBad, authBad, parityBad, showUaf, refusedNonDba, planHit, ownRead>>

(* ---- the client half's work in a session's bracket ---- *)

W5(s) == CanWork(s) /\ Touch(s) /\ Step(s, "work") /\ UNCHANGED <<WorkVars, clsH, pvH, badFree, TmVars>>

\* the value the client half of session s reads for class c
Val(s, c) == IF OnProcess(c) THEN gv[c] ELSE sv[s][c]
Want(s, c) == IF c = "sv" THEN wantG ELSE want[s][c]

\* SET SYSTEM PARAMETERS / SET OPTIMIZATION COST in a bracket (db_set_system_parameters): the client half applies the
\* CS client's scope rules (sysprm_generate_new_value), a server parameter needs a DBA and is applied by the folded
\* server leg (sysprm_change_server_parameters, server hat: the server's rules), the client half applies the client
\* ones (sysprm_change_parameter_values, client hat). server_scope is the A4 code (the server's rules in the bracket),
\* hat_blind the client's rules in the server leg too
TSet(s, c) ==
  /\ W5(s)
  /\ IF c = "sv"
     THEN IF ~IsDba(s) /\ Mutant # "server_scope"
          THEN /\ refusedNonDba' = TRUE
               /\ UNCHANGED <<gv, sv, want, wantG, authBad, parityBad>>
          ELSE /\ authBad' = (authBad \/ ~IsDba(s))
               /\ gv' = IF Mutant = "hat_blind" THEN gv ELSE [gv EXCEPT !["sv"] = Dflt]
               /\ wantG' = Dflt
               /\ UNCHANGED <<sv, want, parityBad, refusedNonDba>>
     ELSE IF c = "cc" /\ Mutant = "server_scope"
     THEN /\ parityBad' = TRUE
          /\ UNCHANGED <<gv, sv, want, wantG, authBad, refusedNonDba>>
     ELSE /\ IF OnProcess(c) THEN gv' = [gv EXCEPT ![c] = Dflt] /\ UNCHANGED sv
             ELSE sv' = [sv EXCEPT ![s][c] = Dflt] /\ UNCHANGED gv
          /\ want' = [want EXCEPT ![s][c] = Dflt]
          /\ UNCHANGED <<wantG, authBad, parityBad, refusedNonDba>>
  /\ UNCHANGED <<cache, showH, res, bootCC, cap, prmBad, planBad, showUaf, leak, tearUaf, planHit, ownRead, resFreed>>

\* a read of every class by the client half: the prm_get_*_value getters, the escape-character validator
\* (sysprm_validate_escape_char_parameters: ss), the plan dump's tuned-cost check (qo_plan_dump_cost_params: cc)
RawRead(via, c) == (via = "validator" /\ c = "ss" /\ Mutant = "raw_validator")
                   \/ (via = "plandump" /\ c = "cc" /\ Mutant = "raw_plandump")
ReadVal(s, via, c) == IF RawRead(via, c) THEN gv[c] ELSE Val(s, c)

Vias == {"getter", "validator", "plandump"}

\* one step reads every class through every path: the reads are of the session's own copies (or the process values
\* nobody but a DBA writes), so their order inside the bracket does not matter
TRead(s) ==
  /\ W5(s)
  /\ prmBad' = (prmBad \/ \E via \in Vias, c \in Cls : ReadVal(s, via, c) # Want(s, c))
  /\ ownRead' = (ownRead \/ \E c \in SessCls : want[s][c] = Dflt /\ ReadVal(s, "getter", c) = Dflt)
  /\ UNCHANGED <<gv, sv, want, wantG, cache, showH, res, bootCC, cap, planBad, authBad, parityBad, showUaf, leak,
                 tearUaf, refusedNonDba, planHit, resFreed>>

\* compile with the XASL cache: the key carries the printed query-string parameters
\* (sysprm_print_parameters_for_qry_string); a hit runs a plan compiled under the entry's values
Key(s) == IF Mutant = "key_process" THEN gv["co"] ELSE Val(s, "co")

TCompile(s) ==
  /\ W5(s)
  /\ IF cache[Key(s)] = NoCache
     THEN cache' = [cache EXCEPT ![Key(s)] = Val(s, "co")] /\ UNCHANGED <<planBad, planHit>>
     ELSE /\ planBad' = (planBad \/ cache[Key(s)] # Val(s, "co"))
          /\ planHit' = TRUE
          /\ UNCHANGED cache
  /\ UNCHANGED <<gv, sv, want, wantG, showH, res, bootCC, cap, prmBad, authBad, parityBad, showUaf, leak, tearUaf,
                 refusedNonDba, ownRead, resFreed>>

\* SHOW <statement> reads the SHOW metadata (show_Metas)
TShow(s) ==
  /\ W5(s)
  /\ showUaf' = (showUaf \/ showH = 0 \/ (showH \in Sess /\ torn[showH] > 0))
  /\ UNCHANGED <<gv, sv, want, wantG, cache, showH, res, bootCC, cap, prmBad, planBad, authBad, parityBad, leak,
                 tearUaf, refusedNonDba, planHit, ownRead, resFreed>>

\* the session leaves client state behind: a savepoint, a trigger, an authorization cache entry, a schema descriptor,
\* an open query result, a kept tree
TAlloc(s) ==
  /\ W5(s)
  /\ res' = [res EXCEPT ![s] = TRUE]
  /\ UNCHANGED <<gv, sv, want, wantG, cache, showH, bootCC, cap, prmBad, planBad, authBad, parityBad, showUaf, leak,
                 tearUaf, refusedNonDba, planHit, ownRead, resFreed>>

Work5(s) ==
  \/ \E c \in Cls : TSet(s, c)
  \/ TRead(s)
  \/ TCompile(s) \/ TShow(s) \/ TAlloc(s)

(* ---- the A4 lifecycle without the attacher and A4's own work steps (checked by docs/tla/CBRD-27430-A4) ---- *)

Life(s) ==
  \/ TNew(s) \/ TAct(s) \/ TBootLock(s) \/ TAreaCheck(s) \/ TAreaMake(s) \/ TReg(s) \/ TBootFail(s) \/ TAdopt(s)
  \/ TEnd1(s) \/ TEnd2(s) \/ TDoneWork(s) \/ TUnreg(s) \/ TLateOp(s) \/ TDeact(s) \/ TUnlock(s) \/ TReread(s)
  \/ TDel(s) \/ TNotAdopted(s) \/ TRAct(s) \/ TRTear(s)

TStep5(s) == (Life(s) /\ Hook) \/ Work5(s)
DStep5 == DStep /\ Hook

Next5 ==
  \/ \E s \in Sess : TStep5(s)
  \/ DStep5
  \/ Finished /\ UNCHANGED v5

Fairness5 ==
  /\ \A s \in Sess : WF_all(TStep5(s) /\ ~TBootFail(s))
  /\ WF_all(DStep5)

Spec5 == Init5 /\ [][Next5]_all /\ Fairness5

(* ---- properties ---- *)

\* C1: a session's client half reads what it set, and never another session's value of a session parameter; a
\* server-only parameter is the one process value its last DBA SET wrote
SessionParams == ~prmBad

\* C1: a cached plan runs only under the parameter values it was compiled with
PlanKey == ~planBad

\* C5: a SET in a folded session follows the CS client's rules: a server parameter needs a DBA, a client-only one
\* is applied
ScopeRules == ~authBad /\ ~parityBad

\* C2: the SHOW metadata every session reads outlives every session
NoShowUaf == ~showUaf

\* C3: the session's client state is freed with the session, before ws_final frees the MOPs it refers to
NoLeak == ~leak
TearOrder == ~tearUaf

TypeOK5 ==
  /\ gv \in [Cls -> {Conf, Dflt}]
  /\ sv \in [Sess -> [Cls -> {Conf, Dflt}]]
  /\ want \in [Sess -> [Cls -> {Conf, Dflt}]]
  /\ wantG \in {Conf, Dflt}
  /\ cache \in [{Conf, Dflt} -> {Conf, Dflt, NoCache}]
  /\ showH \in {0, SharedHeap} \cup Sess
  /\ res \in [Sess -> BOOLEAN]

(* ---- inductive invariant (A4's, with the A5 state) ---- *)

R5 ==
  /\ TypeOK5
  /\ bootCC \in {Conf, Dflt} /\ cap \in BOOLEAN
  /\ prmBad = FALSE /\ planBad = FALSE /\ authBad = FALSE /\ parityBad = FALSE /\ showUaf = FALSE
  /\ leak = FALSE /\ tearUaf = FALSE
  /\ refusedNonDba \in BOOLEAN /\ planHit \in BOOLEAN /\ ownRead \in BOOLEAN /\ resFreed \in BOOLEAN
  \* the process values are the conf values, but a server parameter's, which is the last DBA SET
  /\ \A c \in SessCls : gv[c] = Conf
  /\ gv["sv"] = wantG
  \* a session's copies are what it set (or the conf values its registration seeded)
  /\ \A s \in Sess : \A c \in SessCls : sv[s][c] = want[s][c]
  \* a cache entry was compiled under the values its key printed
  /\ \A k \in {Conf, Dflt} : cache[k] \in {NoCache, k}
  /\ showH = SharedHeap
  \* client state lives in a context that was not torn down
  /\ \A s \in Sess : res[s] => torn[s] = 0

IndInv5 == IndInv /\ R5

CInit5 ==
  /\ N = 2 /\ MaxWork \in Nat /\ MaxWork >= 1
  /\ Attach = FALSE /\ Xfer = FALSE /\ ServerInit = TRUE /\ Mutant = "none"

\* witnesses
NotRefusedNonDba == ~refusedNonDba
NotPlanHit == ~planHit
NotOwnRead == ~ownRead
NotResFreed == ~resFreed

=============================================================================
