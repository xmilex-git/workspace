------------------------------- MODULE HaGate -------------------------------
(* CBRD-27430 B3: HA admission, the reset at a transaction boundary and the two write gates of a folded
   session.

   A CAS was a CS client of the server. Three things kept its writes off a server that must not take them:
     G1  the client library's own counter (db_Disable_modifications of the CAS process): raised at boot for
         a read-only client type or read_only, raised and lowered around a builtin method call; the db_ API
         entry points refuse with -581 while it is above zero.
     G2  the server's gate of the transaction (tdes->disable_modifications), seeded at every transaction
         boundary from the server's own global (logtb_disable_update at standby / read_only) unless the
         client type may write on a standby. Checked (a) by the wire dispatch for every request marked
         CHECK_DB_MODIFICATION and (b) inside the executor and the serial code. A refusal rolls the
         transaction back and marks the connection reset_on_commit.
     R   the reset table (xtran_should_connection_reset) at every commit / rollback: the CAS dropped its
         database connection and ran its host loop again.
   In the folded server the client half runs in the session's thread: G1 is the session's counter, G2(a) is
   checked where the client half enters the server half, R closes the driver connection, and the host loop's
   strict pass is the admission check at session establishment.

   Roles: sessions 1..NS (one thread each), the HA state changer (heartbeat thread, and the unregistering
   session for to-be-standby -> standby), the environment (drivers, brokers of four access modes).

   Write kinds:  "dml"  db_ entry point, then the executor's check      (INSERT / UPDATE / DELETE)
                 "ddl"  db_ entry point, then a CHECK_DB_MODIFICATION request (schema change, flush)
                 "wire" a CHECK_DB_MODIFICATION request with no entry-point check (savepoint)
                 "srv"  only a check inside the server (serial NEXT_VALUE)

   TypesC, KindsC: the client types brokers hand over and the write kinds sessions try (all of them but in the
   scale cfg)
   Wit: the witness ghosts record (TRUE in the witness cfgs only; they multiply the state space)
   Mutant: "none" | "shared_global" | "no_boundary_gate" | "no_reset" | "no_roc" | "reset_no_close"
           | "lenient_admit" | "no_maint_row" | "no_tbs_row" | "reg_dbms" | "resume_keeps" | "d8_tdes"
           | "enable_ignores_ro" *)
EXTENDS Naturals, FiniteSets

CONSTANTS NS, TypesC, KindsC, IsReplica, ROMode, HaInit, GInit, HaMoves, Wit, Mutant

\* apalache-type: NS Int
\* apalache-type: TypesC Set(Str)
\* apalache-type: KindsC Set(Str)
\* apalache-type: IsReplica Bool
\* apalache-type: ROMode Bool
\* apalache-type: HaInit Str
\* apalache-type: GInit Int
\* apalache-type: HaMoves Bool
\* apalache-type: Wit Bool
\* apalache-type: Mutant Str
\* apalache-type: ha Str
\* apalache-type: gG Int
\* apalache-type: pendDis Bool
\* apalache-type: pendEn Bool
\* apalache-type: hbMid Bool
\* apalache-type: ph Int -> Str
\* apalache-type: ty Int -> Str
\* apalache-type: kept Int -> Bool
\* apalache-type: cnt Int -> Int
\* apalache-type: inM Int -> Int
\* apalache-type: base Int -> Int
\* apalache-type: bref Int -> Int
\* apalache-type: upd Int -> Bool
\* apalache-type: hu Int -> Bool
\* apalache-type: roc Int -> Bool
\* apalache-type: rocRef Int -> Bool
\* apalache-type: rst Int -> Bool
\* apalache-type: ref Int -> Str
\* apalache-type: badW Bool
\* apalache-type: leak Bool
\* apalache-type: spur Bool
\* apalache-type: div Bool
\* apalache-type: missed Bool
\* apalache-type: sessG Bool
\* apalache-type: admBad Bool
\* apalache-type: wApplied Bool
\* apalache-type: wExempt Bool
\* apalache-type: wRocReset Bool
\* apalache-type: wResumed Bool

VARIABLES ha,       \* ha_Server_state
          gG,       \* the server's db_Disable_modifications (logtb_disable_update / logtb_enable_update)
          pendDis,  \* a state change reached standby; its logtb_disable_update has not run yet
          pendEn,   \* a state change reached active / maintenance; its logtb_enable_update has not run yet
          hbMid,    \* the changer is inside css_change_ha_server_state after its first transit (holds the csect)
          ph,       \* "off" | "adm" | "boot" | "idle" | "tran" | "c2" | "end"
          ty,       \* the client type synthesized from the broker's ACCESS_MODE x REPLICA_ONLY
          kept,     \* the session's client context is kept after a yield (KEEP_CONNECTION=AUTO)
          cnt,      \* G1: the session's counter
          inM,      \* the session is inside a builtin method call
          base,     \* G2: tdes->disable_modifications
          bref,     \* ghost: what the CS server's tdes would hold
          upd,      \* the transaction has written
          hu,       \* has_updated as read before the commit
          roc,      \* conn->reset_on_commit
          rocRef,   \* ghost: what the CS server's conn->reset_on_commit would hold
          rst,      \* the session's connect status is RESET: the driver connection closes
          ref,      \* ghost: how the last connection attempt was refused: "none" | "retry" | "dbms"
          badW, leak, spur, div, missed, sessG, admBad,   \* violation ghosts
          wApplied, wExempt, wRocReset, wResumed      \* witness ghosts

vars == <<ha, gG, pendDis, pendEn, hbMid, ph, ty, kept, cnt, inM, base, bref, upd, hu, roc, rocRef, rst, ref,
          badW, leak, spur, div, missed, sessG, admBad, wApplied, wExempt, wRocReset, wResumed>>

S == 1..NS
Types == {"RW", "RO", "SO", "RWR"}
HaStates == {"idle", "active", "tbs", "standby", "tba", "maint"}
Kinds == {"dml", "ddl", "wire", "srv"}

Normal(t) == t \in {"RW", "RO", "RWR"}          \* BOOT_NORMAL_CLIENT_TYPE (SLAVE_ONLY is not)
ReadOnly(t) == t \in {"RO", "SO"}               \* BOOT_READ_ONLY_CLIENT_TYPE
ReplicaOnly(t) == t = "RWR"                     \* BOOT_REPLICA_ONLY_BROKER_CLIENT_TYPE
Wos(t) == t = "RWR"                             \* BOOT_WRITE_ON_STANDY_CLIENT_TYPE

(* xtran_should_connection_reset; d is css_is_ha_repl_delayed (), a folded session never ignores it *)
ResetRow(t, h, u, r, d) ==
  IF u /\ h = "tbs" /\ Normal(t) THEN TRUE
  ELSE IF h = "standby" THEN
         IF t = "RW" THEN TRUE
         ELSE IF Normal(t) /\ r THEN TRUE
         ELSE d
  ELSE IF h = "active" /\ t = "SO" THEN TRUE
  ELSE h = "maint"

(* conn->reset_on_commit after the table ran *)
RocAfter(t, h, u, r, d) ==
  IF u /\ h = "tbs" /\ Normal(t) THEN r
  ELSE IF h = "standby" THEN
         IF t = "RW" THEN r
         ELSE IF Normal(t) /\ r THEN FALSE
         ELSE IF d THEN FALSE ELSE r
  ELSE r

(* admission_check at session establishment *)
Reject(t, h, d) ==
  \/ ReplicaOnly(t) /\ ~IsReplica
  \/ h = "maint" /\ Mutant # "no_maint_row"
  \/ h = "tbs" /\ Normal(t) /\ Mutant # "no_tbs_row"
  \/ h = "standby" /\ t = "RW" /\ Mutant # "lenient_admit"
  \/ h = "standby" /\ d
  \/ h = "active" /\ t = "SO"

(* what the host loop's strict pass and the first boundary of the reset table refuse *)
RefTable(t, h, d) == (ReplicaOnly(t) /\ ~IsReplica) \/ ResetRow(t, h, TRUE, FALSE, d)

(* the seed of tdes->disable_modifications: logtb_clear_tdes *)
Seed(t) == IF Wos(t) THEN 0
           ELSE IF Mutant = "d8_tdes" /\ ReadOnly(t) THEN 1
           ELSE IF gG > 0 THEN 1 ELSE 0
SeedRef(t) == IF Wos(t) THEN 0 ELSE IF gG > 0 THEN 1 ELSE 0

Raise(t) == IF ReadOnly(t) \/ ROMode THEN 1 ELSE 0     \* boot_restart_client's raise

(* the gate the db_ entry points read *)
ClientGate(s) == IF Mutant = "shared_global" THEN gG
                 ELSE IF Mutant = "d8_tdes" THEN base[s] + inM[s]
                 ELSE cnt[s]

Own(s) == inM[s] = 1 \/ ReadOnly(ty[s]) \/ ROMode       \* the CAS's own counter is above zero
Clients == {s \in S : ph[s] \in {"idle", "tran", "c2", "end"} /\ Normal(ty[s])}   \* logtb_count_clients

Init ==
  /\ ha = HaInit /\ gG = GInit /\ pendDis = FALSE /\ pendEn = FALSE /\ hbMid = FALSE
  /\ ph = [s \in S |-> "off"] /\ ty = [s \in S |-> "RW"] /\ kept = [s \in S |-> FALSE]
  /\ cnt = [s \in S |-> 0] /\ inM = [s \in S |-> 0]
  /\ base = [s \in S |-> 0] /\ bref = [s \in S |-> 0]
  /\ upd = [s \in S |-> FALSE] /\ hu = [s \in S |-> FALSE]
  /\ roc = [s \in S |-> FALSE] /\ rocRef = [s \in S |-> FALSE] /\ rst = [s \in S |-> FALSE]
  /\ ref = [s \in S |-> "none"]
  /\ badW = FALSE /\ leak = FALSE /\ spur = FALSE /\ div = FALSE /\ missed = FALSE /\ sessG = FALSE /\ admBad = FALSE
  /\ wApplied = FALSE /\ wExempt = FALSE /\ wRocReset = FALSE /\ wResumed = FALSE

--------------------------------------------------------------------------------
(* the HA state changer *)

HaVars == <<ph, ty, kept, cnt, inM, base, bref, upd, hu, roc, rocRef, rst, ref, badW, leak, spur, div,
            missed, sessG, admBad, wApplied, wExempt, wRocReset, wResumed>>

(* active -> to-be-standby: css_change_ha_server_state (STANDBY), first transit *)
Demote1 ==
  /\ HaMoves /\ ~hbMid /\ ha \in {"active", "maint"}
  /\ ha' = "tbs" /\ hbMid' = TRUE
  /\ UNCHANGED <<gG, pendDis, pendEn>> /\ UNCHANGED HaVars

(* ... and, still under the csect, to standby when no normal client is registered *)
Demote2 ==
  /\ hbMid /\ ha = "tbs"
  /\ hbMid' = FALSE
  /\ IF Clients = {} THEN ha' = "standby" /\ pendDis' = TRUE ELSE UNCHANGED <<ha, pendDis>>
  /\ UNCHANGED <<gG, pendEn>> /\ UNCHANGED HaVars

(* standby -> to-be-active -> active *)
Promote1 ==
  /\ HaMoves /\ ~IsReplica /\ ~hbMid /\ ha = "standby"
  /\ ha' = "tba"
  /\ UNCHANGED <<gG, pendDis, pendEn, hbMid>> /\ UNCHANGED HaVars

Promote2 ==
  /\ ~hbMid /\ ha = "tba"
  /\ ha' = "active" /\ pendEn' = TRUE
  /\ UNCHANGED <<gG, pendDis, hbMid>> /\ UNCHANGED HaVars

(* standby -> maintenance *)
Maint ==
  /\ HaMoves /\ ~hbMid /\ ha = "standby"
  /\ ha' = "maint" /\ pendEn' = TRUE
  /\ UNCHANGED <<gG, pendDis, hbMid>> /\ UNCHANGED HaVars

GateDis == /\ pendDis /\ gG' = 1 /\ pendDis' = FALSE
           /\ UNCHANGED <<ha, pendEn, hbMid>> /\ UNCHANGED HaVars
(* logtb_enable_update leaves the gate of a read_only server set *)
GateEn == /\ pendEn /\ gG' = (IF ROMode /\ Mutant # "enable_ignores_ro" THEN gG ELSE 0) /\ pendEn' = FALSE
          /\ UNCHANGED <<ha, pendDis, hbMid>> /\ UNCHANGED HaVars

--------------------------------------------------------------------------------
(* a session *)

(* the ghosts an action leaves alone, written per variable: Apalache cannot type a tuple of one type *)
KeepV0 == badW' = badW /\ leak' = leak /\ spur' = spur /\ div' = div /\ missed' = missed
KeepV == KeepV0 /\ sessG' = sessG /\ admBad' = admBad
KeepW0 == wApplied' = wApplied /\ wExempt' = wExempt /\ wRocReset' = wRocReset
KeepW == KeepW0 /\ wResumed' = wResumed
HaAll == <<ha, gG, pendDis, pendEn, hbMid>>

(* the broker hands a driver connection over; its conf gives the client type. A kept session's driver comes
   back through any broker of the database. *)
Connect(s, t) ==
  /\ ph[s] = "off"
  /\ ph' = [ph EXCEPT ![s] = "adm"] /\ ty' = [ty EXCEPT ![s] = t]
  /\ ref' = [ref EXCEPT ![s] = "none"]
  /\ UNCHANGED HaAll
  /\ UNCHANGED <<kept, cnt, inM, base, bref, upd, hu, roc, rocRef, rst>> /\ KeepV /\ KeepW

(* admission_check: one read of the HA state and of the replication delay *)
Admit(s, d) ==
  /\ ph[s] = "adm"
  /\ d => ha = "standby"
  /\ IF Reject(ty[s], ha, d)
       THEN ph' = [ph EXCEPT ![s] = "off"] /\ ref' = [ref EXCEPT ![s] = "retry"]
       ELSE ph' = [ph EXCEPT ![s] = "boot"] /\ UNCHANGED ref
  /\ UNCHANGED HaAll
  /\ UNCHANGED <<ty, kept, cnt, inM, base, bref, upd, hu, roc, rocRef, rst>> /\ KeepV0 /\ sessG' = sessG /\ KeepW
  /\ admBad' = (admBad \/ (Reject(ty[s], ha, d) # RefTable(ty[s], ha, d)))

(* the client half's boot and xboot_register_client: the to-be-standby drain refuses a normal client; else
   the transaction is assigned (logtb_clear_tdes seeds its gate) and the session's counter starts *)
Register(s) ==
  /\ ph[s] = "boot"
  /\ IF ha = "tbs" /\ Normal(ty[s])
       THEN /\ ph' = [ph EXCEPT ![s] = "off"]
            /\ ref' = [ref EXCEPT ![s] = IF Mutant = "reg_dbms" THEN "dbms" ELSE "retry"]
            /\ UNCHANGED <<cnt, base, bref, kept, gG, sessG, wResumed, roc, rocRef, rst, upd>>
       ELSE /\ ph' = [ph EXCEPT ![s] = "idle"]
            /\ UNCHANGED ref
            /\ kept' = [kept EXCEPT ![s] = FALSE]
            /\ wResumed' = (Wit /\ (wResumed \/ kept[s]))
            /\ base' = [base EXCEPT ![s] = Seed(ty[s])]
            /\ bref' = [bref EXCEPT ![s] = SeedRef(ty[s])]
            /\ roc' = [roc EXCEPT ![s] = FALSE] /\ rocRef' = [rocRef EXCEPT ![s] = FALSE]
            /\ rst' = [rst EXCEPT ![s] = FALSE] /\ upd' = [upd EXCEPT ![s] = FALSE]
            /\ IF Mutant = "shared_global"
                 THEN /\ gG' = (IF gG + Raise(ty[s]) > 2 * NS + 1 THEN gG ELSE gG + Raise(ty[s]))
                      /\ sessG' = (sessG \/ Raise(ty[s]) > 0)
                      /\ UNCHANGED cnt
                 ELSE /\ cnt' = [cnt EXCEPT ![s] = IF Mutant = "resume_keeps" /\ kept[s] THEN cnt[s]
                                                    ELSE IF Mutant = "d8_tdes" THEN 0 ELSE Raise(ty[s])]
                      /\ UNCHANGED <<gG, sessG>>
  /\ UNCHANGED <<ha, pendDis, pendEn, hbMid, ty, inM, hu>>
  /\ KeepV0 /\ admBad' = admBad /\ KeepW0

Begin(s) ==
  /\ ph[s] = "idle" /\ (rst[s] => Mutant = "reset_no_close")
  /\ ph' = [ph EXCEPT ![s] = "tran"]
  /\ UNCHANGED HaAll
  /\ UNCHANGED <<ty, kept, cnt, inM, base, bref, upd, hu, roc, rocRef, rst, ref>> /\ KeepV /\ KeepW

(* method_invoke_builtin_internal: db_disable_modification () ... db_enable_modification () *)
MBegin(s) ==
  /\ ph[s] = "tran" /\ inM[s] = 0
  /\ inM' = [inM EXCEPT ![s] = 1]
  /\ IF Mutant = "shared_global"
       THEN gG' = (IF gG > 2 * NS THEN gG ELSE gG + 1) /\ sessG' = TRUE /\ UNCHANGED cnt
       ELSE cnt' = [cnt EXCEPT ![s] = cnt[s] + 1] /\ UNCHANGED <<gG, sessG>>
  /\ UNCHANGED <<ha, pendDis, pendEn, hbMid, ph, ty, kept, base, bref, upd, hu, roc, rocRef, rst, ref>>
  /\ KeepV0 /\ admBad' = admBad /\ KeepW

MEnd(s) ==
  /\ ph[s] = "tran" /\ inM[s] = 1
  /\ inM' = [inM EXCEPT ![s] = 0]
  /\ IF Mutant = "shared_global"
       THEN gG' = (IF gG > 0 THEN gG - 1 ELSE 0) /\ sessG' = TRUE /\ UNCHANGED cnt
       ELSE cnt' = [cnt EXCEPT ![s] = IF cnt[s] > 0 THEN cnt[s] - 1 ELSE 0] /\ UNCHANGED <<gG, sessG>>
  /\ UNCHANGED <<ha, pendDis, pendEn, hbMid, ph, ty, kept, base, bref, upd, hu, roc, rocRef, rst, ref>>
  /\ KeepV0 /\ admBad' = admBad /\ KeepW

(* one write of kind k; its three outcomes *)
ClChecked(k) == k \in {"dml", "ddl"}
SrvChecked(k) == k \in {"dml", "srv"} \/ Mutant # "no_boundary_gate"

(* how a write of kind k ends for s now: refused at an entry point, refused by the server, applied *)
WOut(s, k) == IF ClChecked(k) /\ ClientGate(s) > 0 THEN "cl"
              ELSE IF SrvChecked(k) /\ base[s] > 0 THEN "sv" ELSE "ok"

Write(s, k) ==
  /\ ph[s] = "tran"
  /\ LET cl == ClChecked(k) /\ ClientGate(s) > 0
         sv == ~cl /\ SrvChecked(k) /\ base[s] > 0
         ok == ~cl /\ ~sv
         rcl == ClChecked(k) /\ Own(s)             \* the CS client refuses
         rsv == ~rcl /\ bref[s] > 0                \* the CS server refuses
     IN /\ div' = (div \/ cl # rcl \/ sv # rsv)
        /\ spur' = (spur \/ (cl /\ ~Own(s)))
        /\ leak' = (leak \/ (ok /\ ClChecked(k) /\ Own(s)))
        /\ badW' = (badW \/ (ok /\ base[s] > 0))
        /\ wApplied' = (Wit /\ (wApplied \/ ok))
        /\ wExempt' = (Wit /\ (wExempt \/ (ok /\ gG > 0 /\ Wos(ty[s]))))
        (* a refusal of the server rolls the transaction back (its gate is seeded again) and marks the
           connection *)
        /\ upd' = [upd EXCEPT ![s] = IF ok THEN TRUE ELSE IF sv THEN FALSE ELSE upd[s]]
        /\ base' = [base EXCEPT ![s] = IF sv THEN Seed(ty[s]) ELSE base[s]]
        /\ bref' = [bref EXCEPT ![s] = IF rsv THEN SeedRef(ty[s]) ELSE bref[s]]
        /\ roc' = [roc EXCEPT ![s] = IF sv /\ Mutant # "no_roc" THEN TRUE ELSE roc[s]]
        /\ rocRef' = [rocRef EXCEPT ![s] = IF rsv THEN TRUE ELSE rocRef[s]]
  /\ UNCHANGED HaAll
  /\ UNCHANGED <<ph, ty, kept, cnt, inM, hu, rst, ref, missed, sessG, admBad, wRocReset, wResumed>>

(* commit or rollback, first half: has_updated is read, the transaction ends, its gate is seeded again *)
End1(s) ==
  /\ ph[s] = "tran" /\ inM[s] = 0
  /\ ph' = [ph EXCEPT ![s] = "c2"]
  /\ hu' = [hu EXCEPT ![s] = upd[s]] /\ upd' = [upd EXCEPT ![s] = FALSE]
  /\ base' = [base EXCEPT ![s] = Seed(ty[s])]
  /\ bref' = [bref EXCEPT ![s] = SeedRef(ty[s])]
  /\ UNCHANGED HaAll
  /\ UNCHANGED <<ty, kept, cnt, inM, roc, rocRef, rst, ref>> /\ KeepV /\ KeepW

(* second half: the reset table reads the HA state; RESET closes the driver connection at this boundary *)
End2(s, d) ==
  /\ ph[s] = "c2"
  /\ d => ha = "standby"
  /\ LET r == ResetRow(ty[s], ha, hu[s], roc[s], d) /\ Mutant # "no_reset"
         rr == ResetRow(ty[s], ha, hu[s], rocRef[s], d)
     IN /\ rst' = [rst EXCEPT ![s] = r]
        /\ missed' = (missed \/ (rr /\ ~r))
        /\ wRocReset' = (Wit /\ (wRocReset \/ (r /\ roc[s] /\ ty[s] # "RW" /\ ~d)))
        /\ ph' = [ph EXCEPT ![s] = IF r /\ Mutant # "reset_no_close" THEN "end" ELSE "idle"]
  /\ roc' = [roc EXCEPT ![s] = RocAfter(ty[s], ha, hu[s], roc[s], d)]
  /\ rocRef' = [rocRef EXCEPT ![s] = RocAfter(ty[s], ha, hu[s], rocRef[s], d)]
  /\ hu' = [hu EXCEPT ![s] = FALSE]
  /\ UNCHANGED HaAll
  /\ UNCHANGED <<ty, kept, cnt, inM, base, bref, upd, ref>>
  /\ badW' = badW /\ leak' = leak /\ spur' = spur /\ div' = div /\ sessG' = sessG /\ admBad' = admBad
  /\ wApplied' = wApplied /\ wExempt' = wExempt /\ wResumed' = wResumed

(* the connection ends (a reset, the driver's close, or a yield that keeps the client context): the
   transaction is unregistered; the last normal client of a to-be-standby server takes it to standby *)
Leave(s, y) ==
  /\ \/ ph[s] = "end" /\ ~y
     \/ ph[s] = "idle"
  /\ ph' = [ph EXCEPT ![s] = "off"]
  /\ kept' = [kept EXCEPT ![s] = y]
  /\ rst' = [rst EXCEPT ![s] = FALSE]
  /\ IF ha = "tbs" /\ ~hbMid /\ Clients \subseteq {s} /\ Normal(ty[s])
       THEN ha' = "standby" /\ pendDis' = TRUE
       ELSE UNCHANGED <<ha, pendDis>>
  /\ IF Mutant = "shared_global"
       THEN UNCHANGED cnt             \* nothing lowers what the boot raised: the session's end calls no db_shutdown
       ELSE cnt' = [cnt EXCEPT ![s] = IF y THEN cnt[s] ELSE 0]
  /\ UNCHANGED <<gG, sessG>>
  /\ UNCHANGED <<pendEn, hbMid, ty, inM, base, bref, upd, hu, roc, rocRef, ref>>
  /\ KeepV0 /\ admBad' = admBad /\ KeepW

SNext(s) ==
  \/ \E t \in TypesC : Connect(s, t)
  \/ \E d \in BOOLEAN : Admit(s, d) \/ End2(s, d)
  \/ Register(s) \/ Begin(s) \/ MBegin(s) \/ MEnd(s) \/ End1(s)
  \/ \E k \in KindsC : Write(s, k)
  \/ \E y \in BOOLEAN : Leave(s, y)

Next == Demote1 \/ Demote2 \/ Promote1 \/ Promote2 \/ Maint \/ GateDis \/ GateEn \/ \E s \in S : SNext(s)

Spec == Init /\ [][Next]_vars

--------------------------------------------------------------------------------
(* properties *)

TypeOK ==
  /\ ha \in HaStates /\ gG \in 0..(2 * NS + 1)
  /\ pendDis \in BOOLEAN /\ pendEn \in BOOLEAN /\ hbMid \in BOOLEAN
  /\ ph \in [S -> {"off", "adm", "boot", "idle", "tran", "c2", "end"}]
  /\ ty \in [S -> Types] /\ kept \in [S -> BOOLEAN]
  /\ cnt \in [S -> 0..2] /\ inM \in [S -> 0..1] /\ base \in [S -> 0..1] /\ bref \in [S -> 0..1]
  /\ upd \in [S -> BOOLEAN] /\ hu \in [S -> BOOLEAN] /\ roc \in [S -> BOOLEAN]
  /\ rocRef \in [S -> BOOLEAN] /\ rst \in [S -> BOOLEAN]
  /\ ref \in [S -> {"none", "retry", "dbms"}]
  /\ badW \in BOOLEAN /\ leak \in BOOLEAN /\ spur \in BOOLEAN /\ div \in BOOLEAN /\ missed \in BOOLEAN
  /\ sessG \in BOOLEAN /\ admBad \in BOOLEAN /\ wApplied \in BOOLEAN /\ wExempt \in BOOLEAN /\ wRocReset \in BOOLEAN
  /\ wResumed \in BOOLEAN

(* C1 *)
NoGatedWrite == ~badW                       \* no write is applied in a transaction whose gate is set
ServerGateOwned == ~sessG                   \* a session never writes the server's gate
ReadOnlyHolds == ROMode => gG > 0           \* the gate of a read_only server stays set
ResetHonoured == ~missed                    \* a boundary the reset table refuses closes the connection
NoTranAfterReset == \A s \in S : ph[s] = "tran" => ~rst[s]
(* C2 *)
AdmitMatchesTable == ~admBad               \* the admission check refuses exactly what the reset table would close
RefusalRetryable == \A s \in S : ref[s] # "dbms"
(* C3 *)
NoWriteInRegion == ~leak                    \* my protected region and my read-only type refuse my writes
NoForeignRefusal == ~spur                   \* nothing but my own counter refuses me at an entry point
(* C4 *)
SameAsClient == ~div                        \* every write ends as it did for a CAS on the CS server

(* supporting conjuncts *)
InvOff == \A s \in S : ph[s] \in {"off", "adm", "boot"} => inM[s] = 0 /\ ~rst[s] /\ (~kept[s] => cnt[s] = 0)
InvKept == \A s \in S : kept[s] => ph[s] \in {"off", "adm", "boot"}
InvCnt == \A s \in S : ph[s] \in {"idle", "tran", "c2", "end"} => cnt[s] = Raise(ty[s]) + inM[s]
InvRegion == \A s \in S : inM[s] = 1 => ph[s] = "tran"
InvBase == \A s \in S : base[s] = bref[s]
InvRoc == \A s \in S : roc[s] = rocRef[s]
InvRst == \A s \in S : rst[s] => ph[s] = "end"
InvWos == \A s \in S : Wos(ty[s]) /\ ph[s] \in {"idle", "tran", "c2", "end"} => base[s] = 0
InvG == gG \in 0..1
InvMid == hbMid => ha = "tbs"
InvHu == \A s \in S : hu[s] => ph[s] = "c2"

IndInv ==
  /\ TypeOK
  /\ NoGatedWrite
  /\ ServerGateOwned
  /\ ReadOnlyHolds
  /\ ResetHonoured
  /\ NoTranAfterReset
  /\ AdmitMatchesTable
  /\ RefusalRetryable
  /\ NoWriteInRegion
  /\ NoForeignRefusal
  /\ SameAsClient
  /\ InvOff
  /\ InvKept
  /\ InvCnt
  /\ InvRegion
  /\ InvBase
  /\ InvRoc
  /\ InvRst
  /\ InvWos
  /\ InvG
  /\ InvMid
  /\ InvHu

(* witnesses *)
NotApplied == ~wApplied
NotExemptWrite == ~wExempt                  \* a write-on-standby type writes while the server's gate is set
NotRocReset == ~wRocReset                   \* a reset the server's refusal caused (reset_on_commit)
NotResumed == ~wResumed
NotReset == \A s \in S : ~rst[s]
NotRefusedAtAdmission == \A s \in S : ~(ref[s] = "retry" /\ ph[s] = "off")
NotDrained == ~(ha = "standby" /\ gG = 1 /\ HaInit = "active")   \* a demotion completed
NotStandbyWithSession == ~(ha = "standby" /\ gG = 1 /\ \E s \in S : ph[s] = "tran")

(* Apalache: the session set is fixed, every other constant is a cfg value *)
CInit == NS = 2 /\ TypesC = Types /\ KindsC = Kinds /\ IsReplica \in BOOLEAN /\ ROMode \in BOOLEAN /\ HaInit \in HaStates /\ GInit \in 0..1
         /\ (ROMode => GInit = 1) /\ HaMoves \in BOOLEAN /\ Wit \in BOOLEAN /\ Mutant = "none"
=============================================================================
