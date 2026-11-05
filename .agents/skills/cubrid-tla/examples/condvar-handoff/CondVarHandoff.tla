--------------------------- MODULE CondVarHandoff ---------------------------
(* One thread waits on a condition variable until another publishes "ready".
   Shows the two classic holes: a signal sent without the mutex can fall
   between the waiter's check and its wait (lost wakeup), and a waiter that
   re-checks with "if" instead of "while" consumes on a spurious wakeup.
   pthread_cond_wait's release-and-sleep is one step (W_wait); its wake-up
   and mutex reacquire are two (W_wake). *)
EXTENDS Naturals

CONSTANTS Waiter, Signaler, Mutant, MaxSpurious
ASSUME Assm == /\ Waiter # Signaler /\ MaxSpurious \in Nat
               /\ "spurious" \notin {Waiter, Signaler}
               /\ Mutant \in {"none", "signal_without_mutex", "if_not_while"}
\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: Waiter Str
\* apalache-type: Signaler Str
\* apalache-type: Mutant Str
\* apalache-type: MaxSpurious Int
\* apalache-type: locked Bool
\* apalache-type: ready Bool
\* apalache-type: sleeping Bool
\* apalache-type: badConsume Bool
\* apalache-type: sleptOnce Bool
\* apalache-type: spuriousLeft Int
\* apalache-type: pc Str -> Str

(* --algorithm CondVarHandoff
variables
  locked = FALSE,      \* the mutex
  ready = FALSE,       \* the predicate the mutex protects
  sleeping = FALSE,    \* waiter is inside pthread_cond_wait
  badConsume = FALSE,  \* ghost: consumed while not ready
  sleptOnce = FALSE,   \* ghost: the waiter went to sleep at least once
  spuriousLeft = MaxSpurious;

define
  \* Boolean and integer typing kept apart: tlapm 1.4.5's SMT encoding cannot
  \* mix them (see the cubrid-tla skill, TLAPS on this host).
  BoolOK == /\ locked \in BOOLEAN /\ ready \in BOOLEAN /\ sleeping \in BOOLEAN
            /\ badConsume \in BOOLEAN /\ sleptOnce \in BOOLEAN
  CountOK == spuriousLeft \in 0..MaxSpurious
  TypeOK == BoolOK /\ CountOK
  NoConsumeBeforeReady == ~badConsume
  WaiterFinishes == <>(pc[Waiter] = "Done")
  NotSleptAndWoken == ~(pc[Waiter] = "Done" /\ ready /\ sleptOnce)
end define;

fair process waiter = Waiter
begin
  W_lock:
    await ~locked;
    locked := TRUE;
  W_check:
    if ready then goto W_consume end if;
  W_wait:
    sleeping := TRUE || locked := FALSE || sleptOnce := TRUE;
  W_wake:
    await ~sleeping /\ ~locked;
    locked := TRUE;
    if Mutant = "if_not_while" then goto W_consume else goto W_check end if;
  W_consume:
    if ~ready then badConsume := TRUE end if;
    locked := FALSE;
end process;

fair process signaler = Signaler
begin
  S_lock:
    if Mutant # "signal_without_mutex" then
      await ~locked;
      locked := TRUE;
    end if;
  S_set:
    ready := TRUE;
  S_signal:
    sleeping := FALSE;
  S_unlock:
    if Mutant # "signal_without_mutex" then locked := FALSE end if;
end process;

\* The OS may wake a sleeping waiter at any time, but only finitely often:
\* endless spurious wakeups would let the waiter keep retaking the (unfair)
\* mutex and starve the signaler, which weak fairness cannot exclude. No
\* fairness on this process, so no liveness argument leans on a wakeup.
process spurious = "spurious"
begin
  X_wake:
    while pc[Waiter] # "Done" do
      X_one:
        await (sleeping /\ spuriousLeft > 0) \/ pc[Waiter] = "Done";
        if sleeping then
          sleeping := FALSE || spuriousLeft := spuriousLeft - 1;
        end if;
    end while;
end process;
end algorithm; *)
\* BEGIN TRANSLATION
VARIABLES locked, ready, sleeping, badConsume, sleptOnce, spuriousLeft, pc

(* define statement *)
BoolOK == /\ locked \in BOOLEAN /\ ready \in BOOLEAN /\ sleeping \in BOOLEAN
          /\ badConsume \in BOOLEAN /\ sleptOnce \in BOOLEAN
CountOK == spuriousLeft \in 0..MaxSpurious
TypeOK == BoolOK /\ CountOK
NoConsumeBeforeReady == ~badConsume
WaiterFinishes == <>(pc[Waiter] = "Done")
NotSleptAndWoken == ~(pc[Waiter] = "Done" /\ ready /\ sleptOnce)


vars == << locked, ready, sleeping, badConsume, sleptOnce, spuriousLeft, pc
        >>

ProcSet == {Waiter} \cup {Signaler} \cup {"spurious"}

Init == (* Global variables *)
        /\ locked = FALSE
        /\ ready = FALSE
        /\ sleeping = FALSE
        /\ badConsume = FALSE
        /\ sleptOnce = FALSE
        /\ spuriousLeft = MaxSpurious
        /\ pc = [self \in ProcSet |-> CASE self = Waiter -> "W_lock"
                                        [] self = Signaler -> "S_lock"
                                        [] self = "spurious" -> "X_wake"]

W_lock == /\ pc[Waiter] = "W_lock"
          /\ ~locked
          /\ locked' = TRUE
          /\ pc' = [pc EXCEPT ![Waiter] = "W_check"]
          /\ UNCHANGED << ready, sleeping, badConsume, sleptOnce, spuriousLeft >>

W_check == /\ pc[Waiter] = "W_check"
           /\ IF ready
                 THEN /\ pc' = [pc EXCEPT ![Waiter] = "W_consume"]
                 ELSE /\ pc' = [pc EXCEPT ![Waiter] = "W_wait"]
           /\ UNCHANGED << locked, ready, sleeping, badConsume, sleptOnce, 
                           spuriousLeft >>

W_wait == /\ pc[Waiter] = "W_wait"
          /\ /\ locked' = FALSE
             /\ sleeping' = TRUE
             /\ sleptOnce' = TRUE
          /\ pc' = [pc EXCEPT ![Waiter] = "W_wake"]
          /\ UNCHANGED << ready, badConsume, spuriousLeft >>

W_wake == /\ pc[Waiter] = "W_wake"
          /\ ~sleeping /\ ~locked
          /\ locked' = TRUE
          /\ IF Mutant = "if_not_while"
                THEN /\ pc' = [pc EXCEPT ![Waiter] = "W_consume"]
                ELSE /\ pc' = [pc EXCEPT ![Waiter] = "W_check"]
          /\ UNCHANGED << ready, sleeping, badConsume, sleptOnce, spuriousLeft >>

W_consume == /\ pc[Waiter] = "W_consume"
             /\ IF ~ready
                   THEN /\ badConsume' = TRUE
                   ELSE /\ TRUE
                        /\ UNCHANGED badConsume
             /\ locked' = FALSE
             /\ pc' = [pc EXCEPT ![Waiter] = "Done"]
             /\ UNCHANGED << ready, sleeping, sleptOnce, spuriousLeft >>

waiter == W_lock \/ W_check \/ W_wait \/ W_wake \/ W_consume

S_lock == /\ pc[Signaler] = "S_lock"
          /\ IF Mutant # "signal_without_mutex"
                THEN /\ ~locked
                     /\ locked' = TRUE
                ELSE /\ TRUE
                     /\ UNCHANGED locked
          /\ pc' = [pc EXCEPT ![Signaler] = "S_set"]
          /\ UNCHANGED << ready, sleeping, badConsume, sleptOnce, spuriousLeft >>

S_set == /\ pc[Signaler] = "S_set"
         /\ ready' = TRUE
         /\ pc' = [pc EXCEPT ![Signaler] = "S_signal"]
         /\ UNCHANGED << locked, sleeping, badConsume, sleptOnce, spuriousLeft >>

S_signal == /\ pc[Signaler] = "S_signal"
            /\ sleeping' = FALSE
            /\ pc' = [pc EXCEPT ![Signaler] = "S_unlock"]
            /\ UNCHANGED << locked, ready, badConsume, sleptOnce, spuriousLeft >>

S_unlock == /\ pc[Signaler] = "S_unlock"
            /\ IF Mutant # "signal_without_mutex"
                  THEN /\ locked' = FALSE
                  ELSE /\ TRUE
                       /\ UNCHANGED locked
            /\ pc' = [pc EXCEPT ![Signaler] = "Done"]
            /\ UNCHANGED << ready, sleeping, badConsume, sleptOnce, 
                            spuriousLeft >>

signaler == S_lock \/ S_set \/ S_signal \/ S_unlock

X_wake == /\ pc["spurious"] = "X_wake"
          /\ IF pc[Waiter] # "Done"
                THEN /\ pc' = [pc EXCEPT !["spurious"] = "X_one"]
                ELSE /\ pc' = [pc EXCEPT !["spurious"] = "Done"]
          /\ UNCHANGED << locked, ready, sleeping, badConsume, sleptOnce, 
                          spuriousLeft >>

X_one == /\ pc["spurious"] = "X_one"
         /\ (sleeping /\ spuriousLeft > 0) \/ pc[Waiter] = "Done"
         /\ IF sleeping
               THEN /\ /\ sleeping' = FALSE
                       /\ spuriousLeft' = spuriousLeft - 1
               ELSE /\ TRUE
                    /\ UNCHANGED << sleeping, spuriousLeft >>
         /\ pc' = [pc EXCEPT !["spurious"] = "X_wake"]
         /\ UNCHANGED << locked, ready, badConsume, sleptOnce >>

spurious == X_wake \/ X_one

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == waiter \/ signaler \/ spurious
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ WF_vars(waiter)
        /\ WF_vars(signaler)

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION

(* Inductive invariant of the correct variant: checked by TLC from every
   IndInv state and proved by TLAPS in CondVarHandoff_proofs.tla. *)
Labels == {"W_lock", "W_check", "W_wait", "W_wake", "W_consume",
           "S_lock", "S_set", "S_signal", "S_unlock", "X_wake", "X_one", "Done"}
PcOK == /\ pc \in [ProcSet -> Labels]
        /\ pc[Waiter] \in {"W_lock", "W_check", "W_wait", "W_wake", "W_consume", "Done"}
        /\ pc[Signaler] \in {"S_lock", "S_set", "S_signal", "S_unlock", "Done"}
        /\ pc["spurious"] \in {"X_wake", "X_one", "Done"}
IndInv == /\ TypeOK /\ PcOK
          /\ ~badConsume
          /\ pc[Waiter] = "W_consume" => ready
          /\ sleeping => pc[Waiter] = "W_wake"

(* Apalache's constant initialization for CondVarHandoff.apalache-indinv.cfg: the inductive
   check covers every MaxSpurious at once, where the TLC inductive cfg fixes it to 2. *)
CInit == Waiter = "w" /\ Signaler = "s" /\ Mutant = "none" /\ MaxSpurious \in Nat
=============================================================================
