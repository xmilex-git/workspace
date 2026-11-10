------------------------------- MODULE HandoffInd -------------------------------
(* Apalache's inductive check of Handoff's IndInv. IndInit draws every variable with Gen (sequences, sets and
   records of bounded size, integers unbounded) and keeps the states IndInv admits; NEXT is Handoff's Next.
   Role sets stay fixed (J = 2 sessions, MaxConn = 3 channels, NT = 1); the slot cap and the fault budgets range
   over every natural. Checked by Apalache only (EXTENDS Apalache). *)
EXTENDS Handoff, Apalache

CInit ==
  /\ J = 2 /\ NT = 1 /\ MaxConn = 3 /\ Mutant = "none"
  /\ MaxSlots \in Nat /\ MaxSlots >= 1
  /\ MaxCrash \in Nat /\ MaxRestart \in Nat /\ MaxTimeout \in Nat /\ MaxCancel \in Nat
  /\ HasStop \in BOOLEAN

IndInit ==
  /\ sUp = Gen(1) /\ sInc = Gen(1) /\ nextTok = Gen(1) /\ stopping = Gen(1) /\ stopPc = Gen(1)
  /\ mFreed = Gen(1) /\ finishers = Gen(1) /\ tranOwner = Gen(1) /\ latest = Gen(1)
  /\ sess = Gen(2) /\ sCh = Gen(3)
  /\ bInc = Gen(1) /\ bCh = Gen(3) /\ published = Gen(1) /\ tokens = Gen(3) /\ slots = Gen(1)
  /\ mailbox = Gen(3) /\ dpc = Gen(1) /\ dj = Gen(1) /\ dch = Gen(1) /\ jobs = Gen(2) /\ cpc = Gen(1) /\ cx = Gen(1)
  /\ b2s = Gen(3) /\ s2b = Gen(3)
  /\ crashes = Gen(1) /\ restarts = Gen(1) /\ timeouts = Gen(1) /\ cancels = Gen(1)
  /\ uaf = Gen(1) /\ badFd = Gen(1) /\ wrongCancel = Gen(1) /\ overCap = Gen(1) /\ hit = Gen(3)
  /\ DOMAIN tranOwner = Trans /\ DOMAIN sess = Jobs /\ DOMAIN jobs = Jobs
  /\ DOMAIN sCh = Conns /\ DOMAIN bCh = Conns /\ DOMAIN mailbox = Conns /\ DOMAIN b2s = Conns /\ DOMAIN s2b = Conns
  /\ IndInv
=============================================================================
