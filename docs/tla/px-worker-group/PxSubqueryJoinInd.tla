--------------------------- MODULE PxSubqueryJoinInd ---------------------------
(* Apalache's inductive check of PxSubqueryJoin's IndInv. IndInit draws every variable with Gen and
   keeps the states IndInv admits; NEXT is PxSubqueryJoin's Next. The design is fixed (Mode "event",
   WakeAlways, Budget "group", SqPolicy "elastic", no InlineFail); the tree and the workers are fixed
   per cfg (apalache-base: the main cfg's tree and 2 workers; apalache-bin3: the 14-job tree and 3 workers);
   the group size B, the operator's ask Want and the spurious-failure budget MaxSpur range over every
   natural. Checked by Apalache only. *)
EXTENDS PxSubqueryJoin, Apalache

\* The cfg fixes the design, the tree and the workers (CONSTANTS, so Apalache folds the tree tables);
\* CInit leaves the rest open.
CInit == WorkFail \in BOOLEAN /\ MaxSpur \in Nat /\ B \in Nat /\ Want \in Nat

\* Gen takes a literal bound: one draw per tree size (5: base, 15: bin3; the stack bound Depth)
Shape ==
  /\ DOMAIN stack = Threads /\ DOMAIN asleep = Threads /\ DOMAIN e0 = Threads /\ DOMAIN idle = Threads
  /\ DOMAIN alive = Workers /\ DOMAIN hold = Workers
  /\ DOMAIN pending = Execs /\ DOMAIN freed = Execs
  /\ DOMAIN opHeld = Jobs /\ DOMAIN runs = Jobs /\ DOMAIN ranBy = Jobs
Scalars ==
  /\ qfreed = Gen(1) /\ interrupt = Gen(1) /\ completed = Gen(1)
  /\ alive = Gen(4) /\ hold = Gen(4) /\ ptask = Gen(1) /\ asleep = Gen(4) /\ qheld = Gen(1)
  /\ epoch = Gen(1) /\ sleepers = Gen(1) /\ e0 = Gen(4) /\ grp = Gen(1)
  /\ opSum = Gen(1) /\ poolTake = Gen(1) /\ uaf = Gen(1) /\ idle = Gen(4) /\ spur = Gen(1)

IndInitBase ==
  /\ stack = Gen(5) /\ queue = Gen(5) /\ pending = Gen(5) /\ freed = Gen(5)
  /\ opHeld = Gen(5) /\ runs = Gen(5) /\ ranBy = Gen(5) /\ ended = Gen(5) /\ returned = Gen(5)
  /\ Scalars /\ Shape /\ IndInv

IndInitBin3 ==
  /\ stack = Gen(15) /\ queue = Gen(15) /\ pending = Gen(15) /\ freed = Gen(15)
  /\ opHeld = Gen(15) /\ runs = Gen(15) /\ ranBy = Gen(15) /\ ended = Gen(15) /\ returned = Gen(15)
  /\ Scalars /\ Shape /\ IndInv
=============================================================================
