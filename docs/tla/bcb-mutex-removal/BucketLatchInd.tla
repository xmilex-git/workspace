----------------------------- MODULE BucketLatchInd -----------------------------
(* Apalache's inductive check of BucketLatch's IndInv. IndInit draws every variable with Gen and keeps the
   states IndInv admits; NEXT is BucketLatch's Next. Role sets stay fixed (2 workers and the flush daemon,
   2 BCBs, 3 pages, 2 buckets) with the chosen design (PromoteWait = FALSE, WakeAtEnd = "flag", every operation but the conditional fixes); the
   operation budget and the fault budgets range over every natural. Checked by Apalache only. *)
EXTENDS BucketLatch, Apalache

CInit ==
  /\ NT = 2 /\ NB = 2 /\ NP = 3 /\ NK = 2
  /\ Ops = {"R", "W", "P", "C", "D", "V"} /\ Daemon = TRUE
  /\ PromoteWait = FALSE /\ WakeAtEnd = "flag" /\ Mutant = "none"
  /\ MaxOps \in Nat /\ MaxTimeouts \in Nat /\ MaxSpur \in Nat /\ MaxErr \in Nat /\ MaxEnv \in Nat

IndInit ==
  /\ pc = Gen(3) /\ rp = Gen(3) /\ rm = Gen(3) /\ hb = Gen(3) /\ hm = Gen(3) /\ ops = Gen(3)
  /\ inq = Gen(3) /\ wm = Gen(3) /\ tk = Gen(3) /\ posted = Gen(3) /\ pv = Gen(3) /\ cver = Gen(3)
  /\ cpg = Gen(3) /\ cerr = Gen(3) /\ tick = Gen(1)
  /\ vpid = Gen(2) /\ mode = Gen(2) /\ fcnt = Gen(2) /\ dirty = Gen(2) /\ writing = Gen(2)
  /\ wwait = Gen(2) /\ touched = Gen(2) /\ bver = Gen(2)
  /\ diskVer = Gen(3) /\ latest = Gen(3) /\ exh = Gen(2)
  /\ tmo = Gen(1) /\ spur = Gen(1) /\ errs = Gen(1) /\ envs = Gen(1) /\ barge = Gen(1)
  /\ prom = Gen(2) /\ avd = Gen(2) /\ reg = Gen(3) /\ areq = Gen(2) /\ dealloc = Gen(3)
  /\ DOMAIN pc = Procs /\ DOMAIN rp = Procs /\ DOMAIN rm = Procs /\ DOMAIN hb = Procs /\ DOMAIN hm = Procs
  /\ DOMAIN ops = Procs /\ DOMAIN inq = Procs /\ DOMAIN wm = Procs /\ DOMAIN tk = Procs
  /\ DOMAIN posted = Procs /\ DOMAIN pv = Procs /\ DOMAIN cver = Procs /\ DOMAIN cpg = Procs
  /\ DOMAIN cerr = Procs
  /\ DOMAIN vpid = Bcbs /\ DOMAIN mode = Bcbs /\ DOMAIN fcnt = Bcbs /\ DOMAIN dirty = Bcbs
  /\ DOMAIN writing = Bcbs /\ DOMAIN wwait = Bcbs /\ DOMAIN touched = Bcbs /\ DOMAIN bver = Bcbs
  /\ DOMAIN diskVer = Pages /\ DOMAIN latest = Pages /\ DOMAIN exh = Bkts
  /\ DOMAIN prom = Bcbs /\ DOMAIN avd = Bcbs /\ DOMAIN reg = Procs /\ DOMAIN areq = Bcbs
  /\ DOMAIN dealloc = Pages
  /\ IndInv
=============================================================================
