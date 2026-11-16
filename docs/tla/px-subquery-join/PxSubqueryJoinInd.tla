--------------------------- MODULE PxSubqueryJoinInd ---------------------------
(* Apalache's inductive check of PxSubqueryJoin's IndInv. IndInit draws every variable with Gen and
   keeps the states IndInv admits; NEXT is PxSubqueryJoin's Next. The cfg fixes the design (Mode
   "event", WakeAlways, no InlineFail), the main cfg's tree, its two workers and the late executor; WorkFail and the
   spurious-failure budget MaxSpur stay open (every value). Checked by Apalache only. *)
EXTENDS PxSubqueryJoin, Apalache

CInit == WorkFail \in BOOLEAN /\ MaxSpur \in Nat

\* Gen takes a literal bound: 5 is the stack bound Depth of the base tree
IndInit ==
  /\ stack = Gen(5) /\ queue = Gen(6) /\ pending = Gen(3) /\ freed = Gen(3)
  /\ runs = Gen(6) /\ ranBy = Gen(6) /\ ended = Gen(6) /\ refused = Gen(6) /\ returned = Gen(3)
  /\ qfreed = Gen(1) /\ interrupt = Gen(1) /\ completed = Gen(1)
  /\ alive = Gen(3) /\ asleep = Gen(3) /\ qheld = Gen(1)
  /\ epoch = Gen(1) /\ sleepers = Gen(1) /\ e0 = Gen(3)
  /\ uaf = Gen(1) /\ idle = Gen(3) /\ spur = Gen(1)
  /\ DOMAIN stack = Threads /\ DOMAIN asleep = Threads /\ DOMAIN e0 = Threads /\ DOMAIN idle = Threads
  /\ DOMAIN alive = Workers
  /\ DOMAIN pending = Execs /\ DOMAIN freed = Execs
  /\ DOMAIN runs = Jobs /\ DOMAIN ranBy = Jobs
  /\ IndInv
=============================================================================
