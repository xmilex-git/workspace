--------------------------- MODULE PxErrorHandoff ---------------------------
(* Leader/worker error handoff of a parallel query (the px_scan pattern).
   Each worker records its error in its own holder; the leader adopts an
   error into its thread-local context only after it has waited for every
   worker, and frees the workers' state after that. Mutant selects a known
   wrong variant so the properties are shown to catch it. *)
EXTENDS Naturals, FiniteSets

CONSTANTS Workers, Leader, Mutant
ASSUME Assm == /\ Leader \notin Workers
               /\ Mutant \in {"none", "early_adopt", "no_join_on_error", "lost_done_on_interrupt"}

(* --algorithm PxErrorHandoff
variables
  started = FALSE,            \* workers spawned
  interrupted = FALSE,        \* leader or a worker asked everyone to stop
  done = [w \in Workers |-> FALSE],
  holder = [w \in Workers |-> "none"],   \* worker-owned error holder
  failed = [w \in Workers |-> FALSE],    \* ghost: the worker hit an error
  leaderErr = "none",         \* leader's thread-local error context
  leaderFailed = FALSE,       \* ghost: the leader hit its own error
  freed = FALSE,              \* worker state (holders, buffers) freed
  uaf = FALSE;                \* ghost: a worker touched freed state

define
  TypeOK == /\ started \in BOOLEAN /\ interrupted \in BOOLEAN
            /\ done \in [Workers -> BOOLEAN]
            /\ holder \in [Workers -> {"none", "err"}]
            /\ failed \in [Workers -> BOOLEAN]
            /\ leaderErr \in {"none", "err"}
            /\ leaderFailed \in BOOLEAN /\ freed \in BOOLEAN /\ uaf \in BOOLEAN
  \* Safety: no worker touches state the leader already freed.
  NoUseAfterFree == ~uaf
  \* Safety: once the leader is finished, it reports an error iff someone failed.
  NoLostError == pc[Leader] = "Done" =>
                   (leaderErr = "err" <=> (leaderFailed \/ \E w \in Workers : failed[w]))
  \* Liveness: the query finishes.
  LeaderFinishes == <>(pc[Leader] = "Done")
  \* Witness predicates (each must be reachable; its witness cfg expects a violation).
  NotWorkerErrorAdopted == ~(pc[Leader] = "Done" /\ leaderErr = "err" /\ ~leaderFailed)
  NotLeaderErrorPath == ~(pc[Leader] = "Done" /\ leaderFailed /\ \E w \in Workers : ~failed[w] /\ done[w])
end define;

fair process worker \in Workers
begin
  W_wait:
    await started;
  W_run:
    either
      skip;                                   \* scan finishes normally
    or
      if freed then uaf := TRUE end if;       \* error: write own holder
      holder[self] := "err" || failed[self] := TRUE;
      interrupted := TRUE;
    or
      await interrupted;                      \* sees the interrupt, stops early
    end either;
  W_done:
    if freed then uaf := TRUE end if;
    if Mutant # "lost_done_on_interrupt" \/ ~interrupted then
      done[self] := TRUE;
    end if;
end process;

fair process leader = Leader
begin
  L_spawn:
    started := TRUE;
  L_work:
    either
      skip;
    or
      leaderFailed := TRUE || leaderErr := "err" || interrupted := TRUE;
      if Mutant = "no_join_on_error" then goto L_free end if;
    end either;
  L_join:
    if Mutant = "early_adopt" then
      await \E w \in Workers : done[w];
    else
      await \A w \in Workers : done[w];
    end if;
  L_adopt:
    if \E w \in Workers : holder[w] = "err" then leaderErr := "err" end if;
  L_free:
    freed := TRUE;
end process;
end algorithm; *)
\* BEGIN TRANSLATION
VARIABLES started, interrupted, done, holder, failed, leaderErr, leaderFailed, 
          freed, uaf, pc

(* define statement *)
TypeOK == /\ started \in BOOLEAN /\ interrupted \in BOOLEAN
          /\ done \in [Workers -> BOOLEAN]
          /\ holder \in [Workers -> {"none", "err"}]
          /\ failed \in [Workers -> BOOLEAN]
          /\ leaderErr \in {"none", "err"}
          /\ leaderFailed \in BOOLEAN /\ freed \in BOOLEAN /\ uaf \in BOOLEAN

NoUseAfterFree == ~uaf

NoLostError == pc[Leader] = "Done" =>
                 (leaderErr = "err" <=> (leaderFailed \/ \E w \in Workers : failed[w]))

LeaderFinishes == <>(pc[Leader] = "Done")

NotWorkerErrorAdopted == ~(pc[Leader] = "Done" /\ leaderErr = "err" /\ ~leaderFailed)
NotLeaderErrorPath == ~(pc[Leader] = "Done" /\ leaderFailed /\ \E w \in Workers : ~failed[w] /\ done[w])


vars == << started, interrupted, done, holder, failed, leaderErr, 
           leaderFailed, freed, uaf, pc >>

ProcSet == (Workers) \cup {Leader}

Init == (* Global variables *)
        /\ started = FALSE
        /\ interrupted = FALSE
        /\ done = [w \in Workers |-> FALSE]
        /\ holder = [w \in Workers |-> "none"]
        /\ failed = [w \in Workers |-> FALSE]
        /\ leaderErr = "none"
        /\ leaderFailed = FALSE
        /\ freed = FALSE
        /\ uaf = FALSE
        /\ pc = [self \in ProcSet |-> CASE self \in Workers -> "W_wait"
                                        [] self = Leader -> "L_spawn"]

W_wait(self) == /\ pc[self] = "W_wait"
                /\ started
                /\ pc' = [pc EXCEPT ![self] = "W_run"]
                /\ UNCHANGED << started, interrupted, done, holder, failed, 
                                leaderErr, leaderFailed, freed, uaf >>

W_run(self) == /\ pc[self] = "W_run"
               /\ \/ /\ TRUE
                     /\ UNCHANGED <<interrupted, holder, failed, uaf>>
                  \/ /\ IF freed
                           THEN /\ uaf' = TRUE
                           ELSE /\ TRUE
                                /\ uaf' = uaf
                     /\ /\ failed' = [failed EXCEPT ![self] = TRUE]
                        /\ holder' = [holder EXCEPT ![self] = "err"]
                     /\ interrupted' = TRUE
                  \/ /\ interrupted
                     /\ UNCHANGED <<interrupted, holder, failed, uaf>>
               /\ pc' = [pc EXCEPT ![self] = "W_done"]
               /\ UNCHANGED << started, done, leaderErr, leaderFailed, freed >>

W_done(self) == /\ pc[self] = "W_done"
                /\ IF freed
                      THEN /\ uaf' = TRUE
                      ELSE /\ TRUE
                           /\ uaf' = uaf
                /\ IF Mutant # "lost_done_on_interrupt" \/ ~interrupted
                      THEN /\ done' = [done EXCEPT ![self] = TRUE]
                      ELSE /\ TRUE
                           /\ done' = done
                /\ pc' = [pc EXCEPT ![self] = "Done"]
                /\ UNCHANGED << started, interrupted, holder, failed, 
                                leaderErr, leaderFailed, freed >>

worker(self) == W_wait(self) \/ W_run(self) \/ W_done(self)

L_spawn == /\ pc[Leader] = "L_spawn"
           /\ started' = TRUE
           /\ pc' = [pc EXCEPT ![Leader] = "L_work"]
           /\ UNCHANGED << interrupted, done, holder, failed, leaderErr, 
                           leaderFailed, freed, uaf >>

L_work == /\ pc[Leader] = "L_work"
          /\ \/ /\ TRUE
                /\ pc' = [pc EXCEPT ![Leader] = "L_join"]
                /\ UNCHANGED <<interrupted, leaderErr, leaderFailed>>
             \/ /\ /\ interrupted' = TRUE
                   /\ leaderErr' = "err"
                   /\ leaderFailed' = TRUE
                /\ IF Mutant = "no_join_on_error"
                      THEN /\ pc' = [pc EXCEPT ![Leader] = "L_free"]
                      ELSE /\ pc' = [pc EXCEPT ![Leader] = "L_join"]
          /\ UNCHANGED << started, done, holder, failed, freed, uaf >>

L_join == /\ pc[Leader] = "L_join"
          /\ IF Mutant = "early_adopt"
                THEN /\ \E w \in Workers : done[w]
                ELSE /\ \A w \in Workers : done[w]
          /\ pc' = [pc EXCEPT ![Leader] = "L_adopt"]
          /\ UNCHANGED << started, interrupted, done, holder, failed, 
                          leaderErr, leaderFailed, freed, uaf >>

L_adopt == /\ pc[Leader] = "L_adopt"
           /\ IF \E w \in Workers : holder[w] = "err"
                 THEN /\ leaderErr' = "err"
                 ELSE /\ TRUE
                      /\ UNCHANGED leaderErr
           /\ pc' = [pc EXCEPT ![Leader] = "L_free"]
           /\ UNCHANGED << started, interrupted, done, holder, failed, 
                           leaderFailed, freed, uaf >>

L_free == /\ pc[Leader] = "L_free"
          /\ freed' = TRUE
          /\ pc' = [pc EXCEPT ![Leader] = "Done"]
          /\ UNCHANGED << started, interrupted, done, holder, failed, 
                          leaderErr, leaderFailed, uaf >>

leader == L_spawn \/ L_work \/ L_join \/ L_adopt \/ L_free

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == leader
           \/ (\E self \in Workers: worker(self))
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ \A self \in Workers : WF_vars(worker(self))
        /\ WF_vars(leader)

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION

(* Inductive invariant of the correct variant (Mutant = "none"): checked by
   TLC from every IndInv state (PxErrorHandoff.inductive-*.cfg) and proved
   for any number of workers in PxErrorHandoff_proofs.tla. *)
WLabels == {"W_wait", "W_run", "W_done", "Done"}
LLabels == {"L_spawn", "L_work", "L_join", "L_adopt", "L_free", "Done"}
PcOK == pc \in [ProcSet -> WLabels \cup LLabels]
IndInv ==
  /\ TypeOK /\ PcOK
  /\ \A w \in Workers : pc[w] \in WLabels
  /\ pc[Leader] \in LLabels
  /\ ~uaf
  /\ \A w \in Workers : done[w] <=> pc[w] = "Done"
  /\ \A w \in Workers : failed[w] <=> holder[w] = "err"
  /\ \A w \in Workers : failed[w] => pc[w] \in {"W_done", "Done"}
  /\ freed <=> pc[Leader] = "Done"
  /\ pc[Leader] \in {"L_adopt", "L_free", "Done"} => \A w \in Workers : done[w]
  /\ pc[Leader] \in {"L_free", "Done"} =>
       (leaderErr = "err" <=> (leaderFailed \/ \E w \in Workers : failed[w]))
  /\ pc[Leader] \notin {"L_free", "Done"} => (leaderErr = "err" <=> leaderFailed)
IndInit == IndInv
=============================================================================
