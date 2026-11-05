------------------------ MODULE PageBatchWalk_proofs ------------------------
(* TLAPS proof that IndInv is inductive for the correct variant, in both modes and for any number of pages and
   slots, and that it implies the safety claims (the premises of the TLA rule INV1). *)
EXTENDS PageBatchWalk, TLAPS
\* timeout: 7200

ASSUME Correct == Mutant = "none"

THEOREM InitInv == Init => IndInv
<1> SUFFICES ASSUME Init PROVE IndInv OBVIOUS
<1> USE Assm DEF Init, IsAns, Ans, HasAns, Le, AnsIn, Kinds, Phases, Pages, Slots, Rows, Free, Emit, ClearChunk, StartChunk, ChunkDone, Least
<1>0. /\ started = FALSE /\ fixed = FALSE /\ cur = 1 /\ ph = "next" /\ unfixedFlag = FALSE /\ front = 0 /\ rpos = 0
      /\ cstart = 0 /\ cend = 0 /\ npos = 0 /\ more = FALSE /\ ptrValid = FALSE /\ 1 \in Pages /\ NS \in Nat
  OBVIOUS
<1>x. ph \notin {"run", "runrefix", "consume", "copy", "emit"} /\ ph # "row" /\ ph # "done" OBVIOUS
<1>1. IGhost BY <1>0, <1>x DEF IGhost
<1>2. IRec BY <1>0, <1>x DEF IRec
<1>3. IAlive BY <1>0, <1>x DEF IAlive
<1>4. IPhaseB BY <1>0, <1>x DEF IPhaseB
<1>5. IPhase BY <1>0, <1>x DEF IPhase
<1>6. IFixB BY <1>0, <1>x DEF IFixB
<1>7. IFix BY <1>0, <1>x DEF IFix
<1>8. IFront BY <1>0, <1>x DEF IFront
<1>9. IChunkB BY <1>0, <1>x DEF IChunkB
<1>10. IChunk BY <1>0, <1>x DEF IChunk
<1>11. IEm BY <1>0, <1>x DEF IEm
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11 DEF IndInv

\* environment steps keep every record's visibility to the snapshot
LEMMA EnvAns == ASSUME IRec, Env PROVE (\A r \in Rows : IsAns(rec'[r]) = IsAns(rec[r])) /\ rec' \in [Rows -> Kinds]
  BY DEF Env, EnvUpdate, EnvVacuum, EnvInsert, EnvRemove, IRec, IsAns, Kinds

THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct DEF IsAns, Ans, HasAns, Le, AnsIn, Kinds, Phases, Pages, Slots, Rows, Free, Emit, ClearChunk, StartChunk, ChunkDone, Least
<1>0. NS \in Nat /\ NP \in Nat /\ Slots \subseteq Nat /\ Pages \subseteq Nat /\ 1 \in Pages OBVIOUS
<1>h. HasAns(cur) => alive[cur]
  <2>1. cur \in Pages /\ rec \in [Rows -> Kinds] BY DEF IndInv, IFix, IRec
  <2>2. ~alive[cur] => \A s \in Slots : rec[<<cur, s>>] = "none" BY <2>1 DEF IndInv, IAlive
  <2>. QED BY <2>2
<1>c. \A a, b \in 0..NS : AnsIn(a, b) # {} => HasAns(cur) OBVIOUS
<1>f. /\ cur \in Pages /\ fixed \in BOOLEAN /\ started \in BOOLEAN /\ ph \in Phases /\ learned \in BOOLEAN
      /\ unfixedFlag \in BOOLEAN /\ more \in BOOLEAN /\ ptrValid \in BOOLEAN
      /\ cstart \in 0..NS /\ cend \in 0..NS /\ npos \in 0..NS /\ front \in 0..NS /\ rpos \in 0..NS
  BY DEF IndInv, IFix, IPhase, IChunk, IFront, IFixB, IPhaseB, IChunkB
<1>1. CASE NextFirst
  <2> USE <1>1
  <2>p1. IGhost' BY <1>1, <1>0, <1>h, <1>c, <1>f DEF IGhost, NextFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>1, <1>0, <1>h, <1>c, <1>f DEF IRec, NextFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>1, <1>0, <1>h, <1>c, <1>f DEF IAlive, NextFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>1, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, NextFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>1, <1>0, <1>h, <1>c, <1>f DEF IPhase, NextFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>1, <1>0, <1>h, <1>c, <1>f DEF IFixB, NextFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>1, <1>0, <1>h, <1>c, <1>f DEF IFix, NextFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>1, <1>0, <1>h, <1>c, <1>f DEF IFront, NextFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>1, <1>0, <1>h, <1>c, <1>f DEF IChunkB, NextFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>1, <1>0, <1>h, <1>c, <1>f DEF IChunk, NextFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>1, <1>0, <1>h, <1>c, <1>f DEF IEm, NextFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>2. CASE NextRefix
  <2> USE <1>2
  <2>p1. IGhost' BY <1>2, <1>0, <1>h, <1>c, <1>f DEF IGhost, NextRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>2, <1>0, <1>h, <1>c, <1>f DEF IRec, NextRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>2, <1>0, <1>h, <1>c, <1>f DEF IAlive, NextRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>2, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, NextRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>2, <1>0, <1>h, <1>c, <1>f DEF IPhase, NextRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>2, <1>0, <1>h, <1>c, <1>f DEF IFixB, NextRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>2, <1>0, <1>h, <1>c, <1>f DEF IFix, NextRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>2, <1>0, <1>h, <1>c, <1>f DEF IFront, NextRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>2, <1>0, <1>h, <1>c, <1>f DEF IChunkB, NextRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>2, <1>0, <1>h, <1>c, <1>f DEF IChunk, NextRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>2, <1>0, <1>h, <1>c, <1>f DEF IEm, NextRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>3. CASE CollectRefix
  <2> USE <1>3
  <2>p1. IGhost' BY <1>3, <1>0, <1>h, <1>c, <1>f DEF IGhost, CollectRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>3, <1>0, <1>h, <1>c, <1>f DEF IRec, CollectRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>3, <1>0, <1>h, <1>c, <1>f DEF IAlive, CollectRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>3, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, CollectRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>3, <1>0, <1>h, <1>c, <1>f DEF IPhase, CollectRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>3, <1>0, <1>h, <1>c, <1>f DEF IFixB, CollectRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>3, <1>0, <1>h, <1>c, <1>f DEF IFix, CollectRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>3, <1>0, <1>h, <1>c, <1>f DEF IFront, CollectRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>3, <1>0, <1>h, <1>c, <1>f DEF IChunkB, CollectRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>3, <1>0, <1>h, <1>c, <1>f DEF IChunk, CollectRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>3, <1>0, <1>h, <1>c, <1>f DEF IEm, CollectRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>4. CASE Learn
  <2> USE <1>4
  <2>p1. IGhost' BY <1>4, <1>0, <1>h, <1>c, <1>f DEF IGhost, Learn, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>4, <1>0, <1>h, <1>c, <1>f DEF IRec, Learn, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>4, <1>0, <1>h, <1>c, <1>f DEF IAlive, Learn, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>4, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, Learn, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>4, <1>0, <1>h, <1>c, <1>f DEF IPhase, Learn, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>4, <1>0, <1>h, <1>c, <1>f DEF IFixB, Learn, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>4, <1>0, <1>h, <1>c, <1>f DEF IFix, Learn, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>4, <1>0, <1>h, <1>c, <1>f DEF IFront, Learn, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>4, <1>0, <1>h, <1>c, <1>f DEF IChunkB, Learn, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>4, <1>0, <1>h, <1>c, <1>f DEF IChunk, Learn, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>4, <1>0, <1>h, <1>c, <1>f DEF IEm, Learn, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>5. CASE LearnDrop
  <2> USE <1>5
  <2>p1. IGhost' BY <1>5, <1>0, <1>h, <1>c, <1>f DEF IGhost, LearnDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>5, <1>0, <1>h, <1>c, <1>f DEF IRec, LearnDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>5, <1>0, <1>h, <1>c, <1>f DEF IAlive, LearnDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>5, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, LearnDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>5, <1>0, <1>h, <1>c, <1>f DEF IPhase, LearnDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>5, <1>0, <1>h, <1>c, <1>f DEF IFixB, LearnDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>5, <1>0, <1>h, <1>c, <1>f DEF IFix, LearnDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>5, <1>0, <1>h, <1>c, <1>f DEF IFront, LearnDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>5, <1>0, <1>h, <1>c, <1>f DEF IChunkB, LearnDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>5, <1>0, <1>h, <1>c, <1>f DEF IChunk, LearnDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>5, <1>0, <1>h, <1>c, <1>f DEF IEm, LearnDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>6. CASE LearnRefix
  <2> USE <1>6
  <2>p1. IGhost' BY <1>6, <1>0, <1>h, <1>c, <1>f DEF IGhost, LearnRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>6, <1>0, <1>h, <1>c, <1>f DEF IRec, LearnRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>6, <1>0, <1>h, <1>c, <1>f DEF IAlive, LearnRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>6, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, LearnRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>6, <1>0, <1>h, <1>c, <1>f DEF IPhase, LearnRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>6, <1>0, <1>h, <1>c, <1>f DEF IFixB, LearnRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>6, <1>0, <1>h, <1>c, <1>f DEF IFix, LearnRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>6, <1>0, <1>h, <1>c, <1>f DEF IFront, LearnRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>6, <1>0, <1>h, <1>c, <1>f DEF IChunkB, LearnRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>6, <1>0, <1>h, <1>c, <1>f DEF IChunk, LearnRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>6, <1>0, <1>h, <1>c, <1>f DEF IEm, LearnRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>7. CASE RunOk
  <2> USE <1>7
  <2>p1. IGhost' BY <1>7, <1>0, <1>h, <1>c, <1>f DEF IGhost, RunOk, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>7, <1>0, <1>h, <1>c, <1>f DEF IRec, RunOk, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>7, <1>0, <1>h, <1>c, <1>f DEF IAlive, RunOk, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>7, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, RunOk, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>7, <1>0, <1>h, <1>c, <1>f DEF IPhase, RunOk, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>7, <1>0, <1>h, <1>c, <1>f DEF IFixB, RunOk, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>7, <1>0, <1>h, <1>c, <1>f DEF IFix, RunOk, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>7, <1>0, <1>h, <1>c, <1>f DEF IFront, RunOk, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>7, <1>0, <1>h, <1>c, <1>f DEF IChunkB, RunOk, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>7, <1>0, <1>h, <1>c, <1>f DEF IChunk, RunOk, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>7, <1>0, <1>h, <1>c, <1>f DEF IEm, RunOk, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>8. CASE RunDecline
  <2> USE <1>8
  <2>p1. IGhost' BY <1>8, <1>0, <1>h, <1>c, <1>f DEF IGhost, RunDecline, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>8, <1>0, <1>h, <1>c, <1>f DEF IRec, RunDecline, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>8, <1>0, <1>h, <1>c, <1>f DEF IAlive, RunDecline, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>8, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, RunDecline, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>8, <1>0, <1>h, <1>c, <1>f DEF IPhase, RunDecline, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>8, <1>0, <1>h, <1>c, <1>f DEF IFixB, RunDecline, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>8, <1>0, <1>h, <1>c, <1>f DEF IFix, RunDecline, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>8, <1>0, <1>h, <1>c, <1>f DEF IFront, RunDecline, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>8, <1>0, <1>h, <1>c, <1>f DEF IChunkB, RunDecline, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>8, <1>0, <1>h, <1>c, <1>f DEF IChunk, RunDecline, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>8, <1>0, <1>h, <1>c, <1>f DEF IEm, RunDecline, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>9. CASE RunError
  <2> USE <1>9
  <2>p1. IGhost' BY <1>9, <1>0, <1>h, <1>c, <1>f DEF IGhost, RunError, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>9, <1>0, <1>h, <1>c, <1>f DEF IRec, RunError, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>9, <1>0, <1>h, <1>c, <1>f DEF IAlive, RunError, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>9, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, RunError, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>9, <1>0, <1>h, <1>c, <1>f DEF IPhase, RunError, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>9, <1>0, <1>h, <1>c, <1>f DEF IFixB, RunError, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>9, <1>0, <1>h, <1>c, <1>f DEF IFix, RunError, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>9, <1>0, <1>h, <1>c, <1>f DEF IFront, RunError, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>9, <1>0, <1>h, <1>c, <1>f DEF IChunkB, RunError, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>9, <1>0, <1>h, <1>c, <1>f DEF IChunk, RunError, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>9, <1>0, <1>h, <1>c, <1>f DEF IEm, RunError, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>10. CASE RunDrop
  <2> USE <1>10
  <2>q. HasAns(cur)' = HasAns(cur) /\ AnsIn(cstart, cend)' = AnsIn(cstart, cend) BY DEF RunDrop
  <2>p1. IGhost' BY <1>10, <1>0, <1>h, <1>c, <1>f, <2>q DEF IGhost, RunDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>10, <1>0, <1>h, <1>c, <1>f, <2>q DEF IRec, RunDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>10, <1>0, <1>h, <1>c, <1>f, <2>q DEF IAlive, RunDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>10, <1>0, <1>h, <1>c, <1>f, <2>q DEF IPhaseB, RunDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>10, <1>0, <1>h, <1>c, <1>f, <2>q DEF IPhase, RunDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>10, <1>0, <1>h, <1>c, <1>f, <2>q DEF IFixB, RunDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>10, <1>0, <1>h, <1>c, <1>f, <2>q DEF IFix, RunDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>10, <1>0, <1>h, <1>c, <1>f, <2>q DEF IFront, RunDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>10, <1>0, <1>h, <1>c, <1>f, <2>q DEF IChunkB, RunDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>10, <1>0, <1>h, <1>c, <1>f, <2>q DEF IEm, RunDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>a. /\ ph = "run" /\ ph' = "runrefix" /\ ptrValid' = FALSE
        /\ UNCHANGED <<cstart, cend, npos, more, front, unfixedFlag>>
    BY DEF RunDrop
  <2>b. /\ cstart \in 0..NS /\ cend \in 0..NS /\ npos \in 0..NS
        /\ cstart <= front /\ front <= cend /\ npos = cend /\ AnsIn(cstart, cend) # {}
        /\ (~more => cend = NS) /\ front = cstart /\ (ph = "runrefix" => ~ptrValid)
    BY <2>a DEF IndInv, IChunk
  <2>p10. IChunk'
    <3> HIDE DEF AnsIn
    <3>. QED BY <2>a, <2>b, <2>q DEF IChunk
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p11, <2>p10 DEF IndInv
<1>11. CASE RunRefix
  <2> USE <1>11
  <2>q. HasAns(cur)' = HasAns(cur) /\ AnsIn(cstart, cend)' = AnsIn(cstart, cend) BY DEF RunRefix
  <2>p1. IGhost' BY <1>11, <1>0, <1>h, <1>c, <1>f, <2>q DEF IGhost, RunRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>11, <1>0, <1>h, <1>c, <1>f, <2>q DEF IRec, RunRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>11, <1>0, <1>h, <1>c, <1>f, <2>q DEF IAlive, RunRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>11, <1>0, <1>h, <1>c, <1>f, <2>q DEF IPhaseB, RunRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>11, <1>0, <1>h, <1>c, <1>f, <2>q DEF IPhase, RunRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>11, <1>0, <1>h, <1>c, <1>f, <2>q DEF IFixB, RunRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>11, <1>0, <1>h, <1>c, <1>f, <2>q DEF IFix, RunRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>11, <1>0, <1>h, <1>c, <1>f, <2>q DEF IFront, RunRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>11, <1>0, <1>h, <1>c, <1>f, <2>q DEF IChunkB, RunRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>11, <1>0, <1>h, <1>c, <1>f, <2>q DEF IEm, RunRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>a. /\ ph = "runrefix" /\ ph' = "run" /\ unfixedFlag' = TRUE
        /\ UNCHANGED <<cstart, cend, npos, more, front, ptrValid>>
    BY DEF RunRefix
  <2>b. /\ cstart \in 0..NS /\ cend \in 0..NS /\ npos \in 0..NS
        /\ cstart <= front /\ front <= cend /\ npos = cend /\ AnsIn(cstart, cend) # {}
        /\ (~more => cend = NS) /\ front = cstart /\ (ph = "runrefix" => ~ptrValid)
    BY <2>a DEF IndInv, IChunk
  <2>p10. IChunk'
    <3> HIDE DEF AnsIn
    <3>. QED BY <2>a, <2>b, <2>q DEF IChunk
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p11, <2>p10 DEF IndInv
<1>12. CASE ConsumeEnd
  <2> USE <1>12
  <2>p1. IGhost' BY <1>12, <1>0, <1>h, <1>c, <1>f DEF IGhost, ConsumeEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>12, <1>0, <1>h, <1>c, <1>f DEF IRec, ConsumeEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>12, <1>0, <1>h, <1>c, <1>f DEF IAlive, ConsumeEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>12, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, ConsumeEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>12, <1>0, <1>h, <1>c, <1>f DEF IPhase, ConsumeEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>12, <1>0, <1>h, <1>c, <1>f DEF IFixB, ConsumeEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>12, <1>0, <1>h, <1>c, <1>f DEF IFix, ConsumeEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>12, <1>0, <1>h, <1>c, <1>f DEF IFront, ConsumeEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>12, <1>0, <1>h, <1>c, <1>f DEF IChunkB, ConsumeEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>12, <1>0, <1>h, <1>c, <1>f DEF IChunk, ConsumeEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>12, <1>0, <1>h, <1>c, <1>f DEF IEm, ConsumeEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>13. CASE Copy
  <2> USE <1>13
  <2>q. HasAns(cur)' = HasAns(cur) /\ AnsIn(cstart, cend)' = AnsIn(cstart, cend) BY DEF Copy
  <2>p1. IGhost' BY <1>13, <1>0, <1>h, <1>c, <1>f, <2>q DEF IGhost, Copy, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>13, <1>0, <1>h, <1>c, <1>f, <2>q DEF IRec, Copy, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>13, <1>0, <1>h, <1>c, <1>f, <2>q DEF IAlive, Copy, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>13, <1>0, <1>h, <1>c, <1>f, <2>q DEF IPhaseB, Copy, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>13, <1>0, <1>h, <1>c, <1>f, <2>q DEF IPhase, Copy, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>13, <1>0, <1>h, <1>c, <1>f, <2>q DEF IFixB, Copy, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>13, <1>0, <1>h, <1>c, <1>f, <2>q DEF IFront, Copy, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>13, <1>0, <1>h, <1>c, <1>f, <2>q DEF IChunkB, Copy, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>13, <1>0, <1>h, <1>c, <1>f, <2>q DEF IChunk, Copy, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>13, <1>0, <1>h, <1>c, <1>f, <2>q DEF IEm, Copy, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>a. /\ ph = "copy" /\ ph' = "emit" /\ fixed' = FALSE
        /\ UNCHANGED <<cur, started, alive, unfixedFlag>>
    BY DEF Copy
  <2>b. started BY <2>a DEF IndInv, IPhase
  <2>c. HasAns(cur) BY <2>a, <1>c, <1>f DEF IndInv, IChunk
  <2>p7. IFix'
    <3> HIDE DEF HasAns
    <3>. QED BY <2>a, <2>b, <2>c, <2>q, <1>f DEF IFix
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p8, <2>p9, <2>p10, <2>p11, <2>p7 DEF IndInv
<1>14. CASE EmitEnd
  <2> USE <1>14
  <2>p1. IGhost' BY <1>14, <1>0, <1>h, <1>c, <1>f DEF IGhost, EmitEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>14, <1>0, <1>h, <1>c, <1>f DEF IRec, EmitEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>14, <1>0, <1>h, <1>c, <1>f DEF IAlive, EmitEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>14, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, EmitEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>14, <1>0, <1>h, <1>c, <1>f DEF IPhase, EmitEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>14, <1>0, <1>h, <1>c, <1>f DEF IFixB, EmitEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>14, <1>0, <1>h, <1>c, <1>f DEF IFix, EmitEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>14, <1>0, <1>h, <1>c, <1>f DEF IFront, EmitEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>14, <1>0, <1>h, <1>c, <1>f DEF IChunkB, EmitEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>14, <1>0, <1>h, <1>c, <1>f DEF IChunk, EmitEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>14, <1>0, <1>h, <1>c, <1>f DEF IEm, EmitEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>15. CASE RowRefix
  <2> USE <1>15
  <2>p1. IGhost' BY <1>15, <1>0, <1>h, <1>c, <1>f DEF IGhost, RowRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>15, <1>0, <1>h, <1>c, <1>f DEF IRec, RowRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>15, <1>0, <1>h, <1>c, <1>f DEF IAlive, RowRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>15, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, RowRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>15, <1>0, <1>h, <1>c, <1>f DEF IPhase, RowRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>15, <1>0, <1>h, <1>c, <1>f DEF IFixB, RowRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>15, <1>0, <1>h, <1>c, <1>f DEF IFix, RowRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>15, <1>0, <1>h, <1>c, <1>f DEF IFront, RowRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>15, <1>0, <1>h, <1>c, <1>f DEF IChunkB, RowRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>15, <1>0, <1>h, <1>c, <1>f DEF IChunk, RowRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>15, <1>0, <1>h, <1>c, <1>f DEF IEm, RowRefix, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>16. CASE RowEnd
  <2> USE <1>16
  <2>p1. IGhost' BY <1>16, <1>0, <1>h, <1>c, <1>f DEF IGhost, RowEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>16, <1>0, <1>h, <1>c, <1>f DEF IRec, RowEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>16, <1>0, <1>h, <1>c, <1>f DEF IAlive, RowEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>16, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, RowEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>16, <1>0, <1>h, <1>c, <1>f DEF IPhase, RowEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>16, <1>0, <1>h, <1>c, <1>f DEF IFixB, RowEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>16, <1>0, <1>h, <1>c, <1>f DEF IFix, RowEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>16, <1>0, <1>h, <1>c, <1>f DEF IFront, RowEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>16, <1>0, <1>h, <1>c, <1>f DEF IChunkB, RowEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>16, <1>0, <1>h, <1>c, <1>f DEF IChunk, RowEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>16, <1>0, <1>h, <1>c, <1>f DEF IEm, RowEnd, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>17. CASE Interrupt
  <2> USE <1>17
  <2>p1. IGhost' BY <1>17, <1>0, <1>h, <1>c, <1>f DEF IGhost, Interrupt, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>17, <1>0, <1>h, <1>c, <1>f DEF IRec, Interrupt, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>17, <1>0, <1>h, <1>c, <1>f DEF IAlive, Interrupt, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>17, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, Interrupt, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>17, <1>0, <1>h, <1>c, <1>f DEF IPhase, Interrupt, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>17, <1>0, <1>h, <1>c, <1>f DEF IFixB, Interrupt, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>17, <1>0, <1>h, <1>c, <1>f DEF IFix, Interrupt, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>17, <1>0, <1>h, <1>c, <1>f DEF IFront, Interrupt, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>17, <1>0, <1>h, <1>c, <1>f DEF IChunkB, Interrupt, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>17, <1>0, <1>h, <1>c, <1>f DEF IChunk, Interrupt, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>17, <1>0, <1>h, <1>c, <1>f DEF IEm, Interrupt, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>18. CASE NextUnfixFirst
  <2> USE <1>18
  <2>p1. IGhost' BY <1>18, <1>0, <1>h, <1>c, <1>f DEF IGhost, NextUnfixFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>18, <1>0, <1>h, <1>c, <1>f DEF IRec, NextUnfixFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>18, <1>0, <1>h, <1>c, <1>f DEF IAlive, NextUnfixFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>18, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, NextUnfixFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>18, <1>0, <1>h, <1>c, <1>f DEF IPhase, NextUnfixFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>18, <1>0, <1>h, <1>c, <1>f DEF IFixB, NextUnfixFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>18, <1>0, <1>h, <1>c, <1>f DEF IFix, NextUnfixFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>18, <1>0, <1>h, <1>c, <1>f DEF IFront, NextUnfixFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>18, <1>0, <1>h, <1>c, <1>f DEF IChunkB, NextUnfixFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>18, <1>0, <1>h, <1>c, <1>f DEF IChunk, NextUnfixFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>18, <1>0, <1>h, <1>c, <1>f DEF IEm, NextUnfixFirst, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>19. CASE NextHopLate
  <2> USE <1>19
  <2>p1. IGhost' BY <1>19, <1>0, <1>h, <1>c, <1>f DEF IGhost, NextHopLate, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>19, <1>0, <1>h, <1>c, <1>f DEF IRec, NextHopLate, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>19, <1>0, <1>h, <1>c, <1>f DEF IAlive, NextHopLate, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>19, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, NextHopLate, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>19, <1>0, <1>h, <1>c, <1>f DEF IPhase, NextHopLate, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>19, <1>0, <1>h, <1>c, <1>f DEF IFixB, NextHopLate, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>19, <1>0, <1>h, <1>c, <1>f DEF IFix, NextHopLate, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>19, <1>0, <1>h, <1>c, <1>f DEF IFront, NextHopLate, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>19, <1>0, <1>h, <1>c, <1>f DEF IChunkB, NextHopLate, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>19, <1>0, <1>h, <1>c, <1>f DEF IChunk, NextHopLate, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>19, <1>0, <1>h, <1>c, <1>f DEF IEm, NextHopLate, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>20. CASE ConsumeFallback
  <2> USE <1>20
  <2>p1. IGhost' BY <1>20, <1>0, <1>h, <1>c, <1>f DEF IGhost, ConsumeFallback, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>20, <1>0, <1>h, <1>c, <1>f DEF IRec, ConsumeFallback, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>20, <1>0, <1>h, <1>c, <1>f DEF IAlive, ConsumeFallback, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>20, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, ConsumeFallback, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>20, <1>0, <1>h, <1>c, <1>f DEF IPhase, ConsumeFallback, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>20, <1>0, <1>h, <1>c, <1>f DEF IFixB, ConsumeFallback, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>20, <1>0, <1>h, <1>c, <1>f DEF IFix, ConsumeFallback, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>20, <1>0, <1>h, <1>c, <1>f DEF IFront, ConsumeFallback, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>20, <1>0, <1>h, <1>c, <1>f DEF IChunkB, ConsumeFallback, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>20, <1>0, <1>h, <1>c, <1>f DEF IChunk, ConsumeFallback, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>20, <1>0, <1>h, <1>c, <1>f DEF IEm, ConsumeFallback, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>21. CASE ConsumeDrop
  <2> USE <1>21
  <2>p1. IGhost' BY <1>21, <1>0, <1>h, <1>c, <1>f DEF IGhost, ConsumeDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <1>21, <1>0, <1>h, <1>c, <1>f DEF IRec, ConsumeDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <1>21, <1>0, <1>h, <1>c, <1>f DEF IAlive, ConsumeDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <1>21, <1>0, <1>h, <1>c, <1>f DEF IPhaseB, ConsumeDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <1>21, <1>0, <1>h, <1>c, <1>f DEF IPhase, ConsumeDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <1>21, <1>0, <1>h, <1>c, <1>f DEF IFixB, ConsumeDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <1>21, <1>0, <1>h, <1>c, <1>f DEF IFix, ConsumeDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <1>21, <1>0, <1>h, <1>c, <1>f DEF IFront, ConsumeDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <1>21, <1>0, <1>h, <1>c, <1>f DEF IChunkB, ConsumeDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <1>21, <1>0, <1>h, <1>c, <1>f DEF IChunk, ConsumeDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <1>21, <1>0, <1>h, <1>c, <1>f DEF IEm, ConsumeDrop, IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>22. CASE NextHop
  <2> USE <1>22 DEF IndInv
  <2>0. ph = "next" /\ started /\ fixed /\ Hop
        /\ UNCHANGED <<rec, alive, learned, em, cstart, cend, npos, more, rpos, ptrValid, started,
                       uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
    BY DEF NextHop
  <2>t. cur \in Pages /\ front \in 0..NS /\ rec \in [Rows -> Kinds] /\ em \in [Rows -> BOOLEAN] /\ alive \in [Pages -> BOOLEAN]
        /\ \A r \in Rows : em[r] = (started /\ IsAns(rec[r]) /\ Le(r, <<cur, front>>))
        /\ \A p \in Pages : ~alive[p] => \A s \in Slots : rec[<<p, s>>] = "none"
    BY <2>0 DEF IFix, IFront, IRec, IEm, IAlive
  <2>1. \A s \in Slots : s > front => ~Ans(cur, s) BY <2>0 DEF IFront
  <2>3. CASE Later = {}
    <3>1. fixed' = FALSE /\ ph' = "done" /\ UNCHANGED <<cur, front, unfixedFlag>> BY <2>0, <2>3 DEF Hop
    <3>2. \A r \in Rows : IsAns(rec[r]) => Le(r, <<cur, front>>)
      <4> TAKE r \in Rows
      <4>1. PICK a \in Pages, b \in Slots : r = <<a, b>> BY DEF Rows
      <4>2. a > cur => ~alive[a] BY <2>3, <4>1 DEF Later
      <4>3. a \in Nat /\ b \in Nat /\ cur \in Nat /\ front \in Nat BY <1>0, <2>t, <4>1
      <4>4. Le(r, <<cur, front>>) <=> (a < cur \/ (a = cur /\ b <= front)) BY <4>1
      <4>5. a > cur => ~IsAns(rec[r]) BY <4>1, <4>2, <2>t
      <4>6. a = cur /\ b > front => ~IsAns(rec[r]) BY <4>1, <2>1
      <4>. QED BY <4>3, <4>4, <4>5, <4>6
    <3>p1. IGhost' BY <2>0, <2>t, <3>1, <3>2 DEF IGhost
    <3>p2. IRec' BY <2>0, <2>t, <3>1, <3>2 DEF IRec
    <3>p3. IAlive' BY <2>0, <2>t, <3>1, <3>2 DEF IAlive
    <3>p4. IPhaseB' BY <2>0, <2>t, <3>1, <3>2 DEF IPhaseB
    <3>p5. IPhase' BY <2>0, <2>t, <3>1, <3>2 DEF IPhase
    <3>p6. IFixB' BY <2>0, <2>t, <3>1, <3>2 DEF IFixB
    <3>p7. IFix' BY <2>0, <2>t, <3>1, <3>2 DEF IFix
    <3>p8. IFront' BY <2>0, <2>t, <3>1, <3>2 DEF IFront
    <3>p9. IChunkB' BY <2>0, <2>t, <3>1, <3>2 DEF IChunkB
    <3>p10. IChunk' BY <2>0, <2>t, <3>1, <3>2 DEF IChunk
    <3>p11. IEm' BY <2>0, <2>t, <3>1, <3>2 DEF IEm
    <3>. QED BY <3>p1, <3>p2, <3>p3, <3>p4, <3>p5, <3>p6, <3>p7, <3>p8, <3>p9, <3>p10, <3>p11 DEF IndInv
  <2>4. CASE Later # {}
    <3>1. PICK q \in Later : Least(q, Later) /\ cur' = q BY <2>0, <2>4 DEF Hop
    <3>2. fixed' = TRUE /\ front' = 0 /\ unfixedFlag' = FALSE /\ ph' = "collect" BY <2>0, <2>4 DEF Hop
    <3>3. q \in Pages /\ q > cur /\ alive[q] /\ \A m \in Pages : m > cur /\ m < q => ~alive[m]
      BY <3>1, <1>0 DEF Later
    <3>4. \A r \in Rows : em[r] = (started /\ IsAns(rec[r]) /\ Le(r, <<q, 0>>))
      <4> TAKE r \in Rows
      <4>1. PICK a \in Pages, b \in Slots : r = <<a, b>> BY DEF Rows
      <4>2. em[r] = (IsAns(rec[r]) /\ Le(r, <<cur, front>>)) BY <2>0, <2>t
      <4>3. a \in Nat /\ b \in Nat /\ b >= 1 /\ cur \in Nat /\ q \in Nat /\ front \in Nat BY <1>0, <2>t, <3>3, <4>1
      <4>4. Le(r, <<cur, front>>) <=> (a < cur \/ (a = cur /\ b <= front)) BY <4>1
      <4>5. Le(r, <<q, 0>>) <=> a < q BY <4>1, <4>3
      <4>6. a > cur /\ a < q => ~IsAns(rec[r]) BY <3>3, <4>1, <2>t
      <4>7. a = cur /\ b > front => ~IsAns(rec[r]) BY <2>1, <4>1
      <4>8. CASE a < cur BY <4>2, <4>3, <4>4, <4>5, <4>8, <3>3, <2>0
      <4>9. CASE a = cur BY <4>2, <4>3, <4>4, <4>5, <4>7, <4>9, <3>3, <2>0
      <4>10. CASE a > cur /\ a < q BY <4>2, <4>3, <4>4, <4>5, <4>6, <4>10, <2>0
      <4>11. CASE a >= q BY <4>2, <4>3, <4>4, <4>5, <4>11, <3>3, <2>0
      <4>. QED BY <4>3, <4>8, <4>9, <4>10, <4>11
    <3>p1. IGhost' BY <2>0, <2>t, <3>1, <3>2, <3>3, <3>4 DEF IGhost
    <3>p2. IRec' BY <2>0, <2>t, <3>1, <3>2, <3>3, <3>4 DEF IRec
    <3>p3. IAlive' BY <2>0, <2>t, <3>1, <3>2, <3>3, <3>4 DEF IAlive
    <3>p4. IPhaseB' BY <2>0, <2>t, <3>1, <3>2, <3>3, <3>4 DEF IPhaseB
    <3>p5. IPhase' BY <2>0, <2>t, <3>1, <3>2, <3>3, <3>4 DEF IPhase
    <3>p6. IFixB' BY <2>0, <2>t, <3>1, <3>2, <3>3, <3>4 DEF IFixB
    <3>p7. IFix' BY <2>0, <2>t, <3>1, <3>2, <3>3, <3>4 DEF IFix
    <3>p8. IFront' BY <2>0, <2>t, <3>1, <3>2, <3>3, <3>4 DEF IFront
    <3>p9. IChunkB' BY <2>0, <2>t, <3>1, <3>2, <3>3, <3>4 DEF IChunkB
    <3>p10. IChunk' BY <2>0, <2>t, <3>1, <3>2, <3>3, <3>4 DEF IChunk
    <3>p11. IEm' BY <2>0, <2>t, <3>1, <3>2, <3>3, <3>4 DEF IEm
    <3>. QED BY <3>p1, <3>p2, <3>p3, <3>p4, <3>p5, <3>p6, <3>p7, <3>p8, <3>p9, <3>p10, <3>p11 DEF IndInv
  <2>. QED BY <2>3, <2>4
<1>23. CASE Collect
  <2> USE <1>23 DEF IndInv
  <2>0. ph = "collect" /\ fixed /\ started BY DEF Collect, IPhase
  <2>a. front \in 0..NS /\ cur \in Pages /\ rec \in [Rows -> Kinds] /\ alive[cur] BY <2>0 DEF IFront, IFix, IRec
  <2>e. PICK e \in 1..(NS + 1) :
          /\ IsE(e, cur, front)
          /\ \/ /\ V(cur, front, e) # {}
                /\ \/ \E c \in V(cur, front, e) : StartChunk(c, c, TRUE)
                   \/ e <= NS /\ StartChunk(e - 1, e - 1, TRUE)
                   \/ e = NS + 1 /\ StartChunk(NS, NS, FALSE)
             \/ /\ V(cur, front, e) = {} /\ e <= NS
                /\ IF Eff(rec[<<cur, e>>]) = "rep" THEN ph' = "learn" /\ rpos' = 0
                   ELSE ph' = "row" /\ rpos' = front
                /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front, cstart, cend, npos, more, ptrValid,
                               unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
             \/ /\ V(cur, front, e) = {} /\ e = NS + 1
                /\ ph' = "next"
                /\ fixed' = fixed
                /\ UNCHANGED <<rec, alive, learned, em, cur, front, cstart, cend, npos, more, rpos, ptrValid,
                               unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
    BY DEF Collect
  <2>b. /\ (e <= NS <=> Exc(cur, front) # {})
        /\ (e <= NS => e \in Exc(cur, front))
        /\ (e = NS + 1 => Exc(cur, front) = {})
    <3>1. Exc(cur, front) \subseteq 1..NS BY DEF Exc
    <3>2. CASE Exc(cur, front) = {}
      <4>1. e = NS + 1 BY <2>e, <3>2 DEF IsE
      <4>. QED BY <4>1, <3>2, <1>0
    <3>3. CASE Exc(cur, front) # {}
      <4>1. e \in Exc(cur, front) BY <2>e, <3>3 DEF IsE, Least
      <4>. QED BY <4>1, <3>1, <1>0
    <3>. QED BY <3>2, <3>3
  <2>c. \A t \in V(cur, front, e) : t \in Slots /\ t > front /\ t < e /\ Ans(cur, t)
    BY <2>a DEF V, Eff
  <2>1. CASE /\ V(cur, front, e) # {} /\ \E c \in V(cur, front, e) : StartChunk(c, c, TRUE)
    <3>1. PICK c \in V(cur, front, e) : StartChunk(c, c, TRUE) BY <2>1
    <3>2. c \in Slots /\ c > front /\ Ans(cur, c) BY <2>c
    <3>3. AnsIn(front, c) # {} /\ c \in 0..NS /\ front <= c BY <3>2, <2>a, <1>0
    <3>s. ph' = "run" /\ cstart' = front /\ cend' = c /\ npos' = c /\ ptrValid' = TRUE /\ more' = TRUE
          /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front, rpos, unfixedFlag, started,
                         uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
      BY <3>1 DEF StartChunk
    <3>p1. IGhost' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3 DEF IGhost
    <3>p2. IRec' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3 DEF IRec
    <3>p3. IAlive' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3 DEF IAlive
    <3>p4. IPhaseB' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3 DEF IPhaseB
    <3>p5. IPhase' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3 DEF IPhase
    <3>p6. IFixB' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3 DEF IFixB
    <3>p7. IFix' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3 DEF IFix
    <3>p8. IFront' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3 DEF IFront
    <3>p9. IChunkB' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3 DEF IChunkB
    <3>p10. IChunk' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3 DEF IChunk
    <3>p11. IEm' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3 DEF IEm
    <3>. QED BY <3>p1, <3>p2, <3>p3, <3>p4, <3>p5, <3>p6, <3>p7, <3>p8, <3>p9, <3>p10, <3>p11 DEF IndInv
  <2>2. CASE /\ V(cur, front, e) # {} /\ e <= NS /\ StartChunk(e - 1, e - 1, TRUE)
    <3>1. PICK t \in V(cur, front, e) : TRUE BY <2>2
    <3>2. t \in Slots /\ t > front /\ t <= e - 1 /\ Ans(cur, t) BY <2>c, <1>0
    <3>3. AnsIn(front, e - 1) # {} BY <3>2
    <3>4. e - 1 \in 0..NS /\ front <= e - 1 BY <3>2, <2>2, <1>0, <2>a
    <3>s. ph' = "run" /\ cstart' = front /\ cend' = e - 1 /\ npos' = e - 1 /\ ptrValid' = TRUE /\ more' = TRUE
          /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front, rpos, unfixedFlag, started,
                         uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
      BY <2>2 DEF StartChunk
    <3>p1. IGhost' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4 DEF IGhost
    <3>p2. IRec' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4 DEF IRec
    <3>p3. IAlive' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4 DEF IAlive
    <3>p4. IPhaseB' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4 DEF IPhaseB
    <3>p5. IPhase' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4 DEF IPhase
    <3>p6. IFixB' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4 DEF IFixB
    <3>p7. IFix' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4 DEF IFix
    <3>p8. IFront' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4 DEF IFront
    <3>p9. IChunkB' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4 DEF IChunkB
    <3>p10. IChunk' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4 DEF IChunk
    <3>p11. IEm' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4 DEF IEm
    <3>. QED BY <3>p1, <3>p2, <3>p3, <3>p4, <3>p5, <3>p6, <3>p7, <3>p8, <3>p9, <3>p10, <3>p11 DEF IndInv
  <2>3. CASE /\ V(cur, front, e) # {} /\ e = NS + 1 /\ StartChunk(NS, NS, FALSE)
    <3>1. PICK t \in V(cur, front, e) : TRUE BY <2>3
    <3>2. t \in Slots /\ t > front /\ Ans(cur, t) BY <2>c
    <3>3. t \in AnsIn(front, NS) BY <3>2, <1>0
    <3>4. AnsIn(front, NS) # {} /\ NS \in 0..NS /\ front <= NS BY <3>3, <2>a, <1>0
    <3>5. AnsIn(front, NS)' # {} BY <3>3, <2>3, <2>a, <1>0 DEF StartChunk
    <3>s. ph' = "run" /\ cstart' = front /\ cend' = NS /\ npos' = NS /\ ptrValid' = TRUE /\ more' = FALSE
          /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front, rpos, unfixedFlag, started,
                         uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
      BY <2>3 DEF StartChunk
    <3>p1. IGhost' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4, <3>5 DEF IGhost
    <3>p2. IRec' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4, <3>5 DEF IRec
    <3>p3. IAlive' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4, <3>5 DEF IAlive
    <3>p4. IPhaseB' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4, <3>5 DEF IPhaseB
    <3>p5. IPhase' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4, <3>5 DEF IPhase
    <3>p6. IFixB' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4, <3>5 DEF IFixB
    <3>p7. IFix' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4, <3>5 DEF IFix
    <3>p8. IFront' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4, <3>5 DEF IFront
    <3>p9. IChunkB' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4, <3>5 DEF IChunkB
    <3>p10. IChunk' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4, <3>5 DEF IChunk
    <3>p11. IEm' BY <2>0, <2>a, <3>s, <3>1, <3>2, <3>3, <3>4, <3>5 DEF IEm
    <3>. QED BY <3>p1, <3>p2, <3>p3, <3>p4, <3>p5, <3>p6, <3>p7, <3>p8, <3>p9, <3>p10, <3>p11 DEF IndInv
  <2>4. CASE /\ V(cur, front, e) = {} /\ e <= NS
             /\ IF Eff(rec[<<cur, e>>]) = "rep" THEN ph' = "learn" /\ rpos' = 0
                ELSE ph' = "row" /\ rpos' = front
             /\ UNCHANGED <<rec, alive, learned, em, cur, fixed, front, cstart, cend, npos, more, ptrValid,
                            unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
    <3>1. e \in Exc(cur, front) BY <2>4, <2>b
    <3>2. e \in Slots /\ e > front /\ Ans(cur, e) BY <3>1, <2>a DEF Exc, Eff
    <3>3. (ph' = "learn" /\ rpos' = 0) \/ (ph' = "row" /\ rpos' = front) BY <2>4
    <3>p1. IGhost' BY <2>0, <2>a, <2>4, <3>2, <3>3 DEF IGhost
    <3>p2. IRec' BY <2>0, <2>a, <2>4, <3>2, <3>3 DEF IRec
    <3>p3. IAlive' BY <2>0, <2>a, <2>4, <3>2, <3>3 DEF IAlive
    <3>p4. IPhaseB' BY <2>0, <2>a, <2>4, <3>2, <3>3 DEF IPhaseB
    <3>p5. IPhase' BY <2>0, <2>a, <2>4, <3>2, <3>3 DEF IPhase
    <3>p6. IFixB' BY <2>0, <2>a, <2>4, <3>2, <3>3 DEF IFixB
    <3>p7. IFix' BY <2>0, <2>a, <2>4, <3>2, <3>3 DEF IFix
    <3>p8. IFront' BY <2>0, <2>a, <2>4, <3>2, <3>3 DEF IFront
    <3>p9. IChunkB' BY <2>0, <2>a, <2>4, <3>2, <3>3 DEF IChunkB
    <3>p10. IChunk' BY <2>0, <2>a, <2>4, <3>2, <3>3 DEF IChunk
    <3>p11. IEm' BY <2>0, <2>a, <2>4, <3>2, <3>3 DEF IEm
    <3>. QED BY <3>p1, <3>p2, <3>p3, <3>p4, <3>p5, <3>p6, <3>p7, <3>p8, <3>p9, <3>p10, <3>p11 DEF IndInv
  <2>5. CASE /\ V(cur, front, e) = {} /\ e = NS + 1
             /\ ph' = "next"
             /\ fixed' = fixed
             /\ UNCHANGED <<rec, alive, learned, em, cur, front, cstart, cend, npos, more, rpos, ptrValid,
                            unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
    <3>1. Exc(cur, front) = {} BY <2>5, <2>b
    <3>2. \A s \in Slots : s > front => ~Ans(cur, s)
      <4> TAKE s \in Slots
      <4>1. s > front /\ Ans(cur, s) => s \in Exc(cur, front) \/ s \in V(cur, front, e)
        BY <2>5, <2>a, <1>0 DEF Exc, V, Eff
      <4>. QED BY <4>1, <3>1, <2>5
    <3>p1. IGhost' BY <2>0, <2>a, <2>5, <3>2 DEF IGhost
    <3>p2. IRec' BY <2>0, <2>a, <2>5, <3>2 DEF IRec
    <3>p3. IAlive' BY <2>0, <2>a, <2>5, <3>2 DEF IAlive
    <3>p4. IPhaseB' BY <2>0, <2>a, <2>5, <3>2 DEF IPhaseB
    <3>p5. IPhase' BY <2>0, <2>a, <2>5, <3>2 DEF IPhase
    <3>p6. IFixB' BY <2>0, <2>a, <2>5, <3>2 DEF IFixB
    <3>p7. IFix' BY <2>0, <2>a, <2>5, <3>2 DEF IFix
    <3>p8. IFront' BY <2>0, <2>a, <2>5, <3>2 DEF IFront
    <3>p9. IChunkB' BY <2>0, <2>a, <2>5, <3>2 DEF IChunkB
    <3>p10. IChunk' BY <2>0, <2>a, <2>5, <3>2 DEF IChunk
    <3>p11. IEm' BY <2>0, <2>a, <2>5, <3>2 DEF IEm
    <3>. QED BY <3>p1, <3>p2, <3>p3, <3>p4, <3>p5, <3>p6, <3>p7, <3>p8, <3>p9, <3>p10, <3>p11 DEF IndInv
  <2>. QED BY <2>e, <2>1, <2>2, <2>3, <2>4, <2>5
<1>24. CASE ConsumeRow
  <2> USE <1>24 DEF IndInv
  <2>0. ph = "consume" /\ started  BY DEF ConsumeRow, IPhase
  <2>a. front \in 0..NS /\ cur \in Pages /\ rec \in [Rows -> Kinds] /\ em \in [Rows -> BOOLEAN]
        /\ \A r \in Rows : em[r] = (started /\ IsAns(rec[r]) /\ Le(r, <<cur, front>>))
    BY <2>0 DEF IFront, IFix, IRec, IEm
  <2>b. /\ cstart <= front /\ front <= cend /\ npos = cend /\ cend \in 0..NS /\ AnsIn(cstart, cend) # {}
        /\ (~more => cend = NS) /\ cstart \in 0..NS /\ more \in BOOLEAN /\ ptrValid \in BOOLEAN /\ rpos = 0 /\ fixed /\ ptrValid
    BY <2>0 DEF IFront, IChunk, IFix, IChunkB, IFixB
  <2>s. PICK s \in AnsIn(front, cend) :
          /\ Least(s, AnsIn(front, cend))
          /\ Emit(<<cur, s>>) /\ front' = s
    BY DEF ConsumeRow
  <2>g. /\ uaf' = (uaf \/ ~fixed \/ ~ptrValid) /\ sawChunk' = TRUE
        /\ UNCHANGED <<rec, alive, learned, ph, cur, fixed, cstart, cend, npos, more, rpos, ptrValid,
                       unfixedFlag, started, badFix, sawRow, sawDrop>>
    BY DEF ConsumeRow
  <2>e1. s \in Slots /\ s > front /\ IsAns(rec[<<cur, s>>]) /\ s <= cend BY <2>b, <2>s DEF AnsIn
  <2>e2. \A t \in Slots : front < t /\ t < s => ~IsAns(rec[<<cur, t>>]) BY <2>b, <2>s, <2>e1, <1>0 DEF AnsIn
  <2>f1. <<cur, s>> \in Rows /\ cur \in Nat /\ s \in Nat /\ front \in Nat BY <2>a, <2>e1, <1>0
  <2>f2. ~em[<<cur, s>>]
    <3>1. em[<<cur, s>>] = (started /\ IsAns(rec[<<cur, s>>]) /\ Le(<<cur, s>>, <<cur, front>>)) BY <2>a, <2>f1
    <3>2. ~Le(<<cur, s>>, <<cur, front>>) BY <2>e1, <2>f1
    <3>. QED BY <3>1, <3>2
  <2>f3. \A r \in Rows : em'[r] = (started' /\ IsAns(rec'[r]) /\ Le(r, <<cur', front'>>))
    <3> TAKE r \in Rows
    <3>1. PICK a \in Pages, b \in Slots : r = <<a, b>> BY DEF Rows
    <3>2. a \in Nat /\ b \in Nat BY <3>1, <1>0
    <3>0. started' = started /\ rec' = rec /\ cur' = cur /\ front' = s /\ started BY <2>g, <2>s, <2>0
    <3>3. CASE r = <<cur, s>>
      <4>1. em'[r] = TRUE BY <3>3, <2>s, <2>f1, <2>a DEF Emit
      <4>2. Le(r, <<cur, s>>) BY <3>3, <2>f1
      <4>. QED BY <4>1, <4>2, <3>0, <3>3, <2>e1
    <3>4. CASE r # <<cur, s>>
      <4>1. em'[r] = em[r] BY <3>4, <2>s, <2>f1, <2>a DEF Emit
      <4>2. Le(r, <<cur, s>>) <=> (a < cur \/ (a = cur /\ b <= s)) BY <3>1
      <4>3. Le(r, <<cur, front>>) <=> (a < cur \/ (a = cur /\ b <= front)) BY <3>1
      <4>4. a = cur /\ b = s => FALSE BY <3>1, <3>4
      <4>5. a = cur /\ front < b /\ b < s => ~IsAns(rec[r]) BY <3>1, <2>e2
      <4>6. em[r] = (IsAns(rec[r]) /\ Le(r, <<cur, front>>)) BY <2>a, <2>0
      <4>7. a \in Nat /\ b \in Nat /\ cur \in Nat /\ s \in Nat /\ front \in Nat /\ front < s BY <3>2, <2>f1, <2>e1
      <4>8. em'[r] = (started' /\ IsAns(rec'[r]) /\ Le(r, <<cur', front'>>)) <=> em[r] = (IsAns(rec[r]) /\ Le(r, <<cur, s>>))
        BY <4>1, <3>0
      <4>9. CASE a # cur BY <4>2, <4>3, <4>6, <4>7, <4>8, <4>9
      <4>10. CASE a = cur /\ b <= front BY <4>2, <4>3, <4>6, <4>7, <4>8, <4>10
      <4>11. CASE a = cur /\ front < b /\ b < s BY <4>2, <4>3, <4>5, <4>6, <4>7, <4>8, <4>11
      <4>12. CASE a = cur /\ b > s BY <4>2, <4>3, <4>6, <4>7, <4>8, <4>12
      <4>. QED BY <4>4, <4>7, <4>9, <4>10, <4>11, <4>12
    <3>. QED BY <3>3, <3>4
  <2>f4. em' \in [Rows -> BOOLEAN] /\ dup' = FALSE /\ stray' = FALSE BY <2>s, <2>a, <2>f1, <2>f2, <2>e1 DEF Emit, IGhost
  <2>f5. front' = s /\ s \in 0..NS BY <2>s, <2>e1, <1>0
  <2>p1. IGhost' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IGhost
  <2>p2. IRec' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IRec
  <2>p3. IAlive' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IAlive
  <2>p4. IPhaseB' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IPhaseB
  <2>p5. IPhase' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IPhase
  <2>p6. IFixB' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IFixB
  <2>p7. IFix' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IFix
  <2>p8. IFront' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IFront
  <2>p9. IChunkB' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IChunkB
  <2>p10. IChunk' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IChunk
  <2>p11. IEm' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>25. CASE EmitRow
  <2> USE <1>25 DEF IndInv
  <2>0. ph = "emit" /\ started  BY DEF EmitRow, IPhase
  <2>a. front \in 0..NS /\ cur \in Pages /\ rec \in [Rows -> Kinds] /\ em \in [Rows -> BOOLEAN]
        /\ \A r \in Rows : em[r] = (started /\ IsAns(rec[r]) /\ Le(r, <<cur, front>>))
    BY <2>0 DEF IFront, IFix, IRec, IEm
  <2>b. /\ cstart <= front /\ front <= cend /\ npos = cend /\ cend \in 0..NS /\ AnsIn(cstart, cend) # {}
        /\ (~more => cend = NS) /\ cstart \in 0..NS /\ more \in BOOLEAN /\ ptrValid \in BOOLEAN /\ rpos = 0
        /\ (~fixed => HasAns(cur))
    BY <2>0 DEF IFront, IChunk, IFix, IChunkB, IFixB
  <2>s. PICK s \in AnsIn(front, cend) :
          /\ Least(s, AnsIn(front, cend))
          /\ Emit(<<cur, s>>) /\ front' = s
    BY DEF EmitRow
  <2>g. /\ sawChunk' = TRUE
        /\ UNCHANGED <<rec, alive, learned, ph, cur, fixed, cstart, cend, npos, more, rpos, ptrValid,
                       unfixedFlag, started, uaf, badFix, sawRow, sawDrop>>
    BY DEF EmitRow
  <2>e1. s \in Slots /\ s > front /\ IsAns(rec[<<cur, s>>]) /\ s <= cend BY <2>b, <2>s DEF AnsIn
  <2>e2. \A t \in Slots : front < t /\ t < s => ~IsAns(rec[<<cur, t>>]) BY <2>b, <2>s, <2>e1, <1>0 DEF AnsIn
  <2>f1. <<cur, s>> \in Rows /\ cur \in Nat /\ s \in Nat /\ front \in Nat BY <2>a, <2>e1, <1>0
  <2>f2. ~em[<<cur, s>>]
    <3>1. em[<<cur, s>>] = (started /\ IsAns(rec[<<cur, s>>]) /\ Le(<<cur, s>>, <<cur, front>>)) BY <2>a, <2>f1
    <3>2. ~Le(<<cur, s>>, <<cur, front>>) BY <2>e1, <2>f1
    <3>. QED BY <3>1, <3>2
  <2>f3. \A r \in Rows : em'[r] = (started' /\ IsAns(rec'[r]) /\ Le(r, <<cur', front'>>))
    <3> TAKE r \in Rows
    <3>1. PICK a \in Pages, b \in Slots : r = <<a, b>> BY DEF Rows
    <3>2. a \in Nat /\ b \in Nat BY <3>1, <1>0
    <3>0. started' = started /\ rec' = rec /\ cur' = cur /\ front' = s /\ started BY <2>g, <2>s, <2>0
    <3>3. CASE r = <<cur, s>>
      <4>1. em'[r] = TRUE BY <3>3, <2>s, <2>f1, <2>a DEF Emit
      <4>2. Le(r, <<cur, s>>) BY <3>3, <2>f1
      <4>. QED BY <4>1, <4>2, <3>0, <3>3, <2>e1
    <3>4. CASE r # <<cur, s>>
      <4>1. em'[r] = em[r] BY <3>4, <2>s, <2>f1, <2>a DEF Emit
      <4>2. Le(r, <<cur, s>>) <=> (a < cur \/ (a = cur /\ b <= s)) BY <3>1
      <4>3. Le(r, <<cur, front>>) <=> (a < cur \/ (a = cur /\ b <= front)) BY <3>1
      <4>4. a = cur /\ b = s => FALSE BY <3>1, <3>4
      <4>5. a = cur /\ front < b /\ b < s => ~IsAns(rec[r]) BY <3>1, <2>e2
      <4>6. em[r] = (IsAns(rec[r]) /\ Le(r, <<cur, front>>)) BY <2>a, <2>0
      <4>7. a \in Nat /\ b \in Nat /\ cur \in Nat /\ s \in Nat /\ front \in Nat /\ front < s BY <3>2, <2>f1, <2>e1
      <4>8. em'[r] = (started' /\ IsAns(rec'[r]) /\ Le(r, <<cur', front'>>)) <=> em[r] = (IsAns(rec[r]) /\ Le(r, <<cur, s>>))
        BY <4>1, <3>0
      <4>9. CASE a # cur BY <4>2, <4>3, <4>6, <4>7, <4>8, <4>9
      <4>10. CASE a = cur /\ b <= front BY <4>2, <4>3, <4>6, <4>7, <4>8, <4>10
      <4>11. CASE a = cur /\ front < b /\ b < s BY <4>2, <4>3, <4>5, <4>6, <4>7, <4>8, <4>11
      <4>12. CASE a = cur /\ b > s BY <4>2, <4>3, <4>6, <4>7, <4>8, <4>12
      <4>. QED BY <4>4, <4>7, <4>9, <4>10, <4>11, <4>12
    <3>. QED BY <3>3, <3>4
  <2>f4. em' \in [Rows -> BOOLEAN] /\ dup' = FALSE /\ stray' = FALSE BY <2>s, <2>a, <2>f1, <2>f2, <2>e1 DEF Emit, IGhost
  <2>f5. front' = s /\ s \in 0..NS BY <2>s, <2>e1, <1>0
  <2>p1. IGhost' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IGhost
  <2>p2. IRec' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IRec
  <2>p3. IAlive' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IAlive
  <2>p4. IPhaseB' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IPhaseB
  <2>p5. IPhase' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IPhase
  <2>p6. IFixB' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IFixB
  <2>p7. IFix' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IFix
  <2>p8. IFront' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IFront
  <2>p9. IChunkB' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IChunkB
  <2>p10. IChunk' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IChunk
  <2>p11. IEm' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>26. CASE RowNext
  <2> USE <1>26 DEF IndInv
  <2>0. ph = "row" /\ started /\ fixed BY DEF RowNext, IPhase
  <2>a. front \in 0..NS /\ cur \in Pages /\ rec \in [Rows -> Kinds] /\ em \in [Rows -> BOOLEAN]
        /\ \A r \in Rows : em[r] = (started /\ IsAns(rec[r]) /\ Le(r, <<cur, front>>))
    BY <2>0 DEF IFront, IFix, IRec, IEm
  <2>b. /\ rpos = front /\ cstart = 0 /\ cend = 0 /\ npos = 0 /\ more = FALSE /\ ptrValid = FALSE
    BY <2>0 DEF IFront, IChunk, IFix, IChunkB, IFixB
  <2>s. PICK s \in AnsIn(rpos, NS) :
          /\ Least(s, AnsIn(rpos, NS))
          /\ Emit(<<cur, s>>) /\ rpos' = s /\ front' = s
          /\ fixed' \in BOOLEAN
    BY DEF RowNext
  <2>g. /\ sawRow' = TRUE
        /\ UNCHANGED <<rec, alive, learned, ph, cur, cstart, cend, npos, more, ptrValid, unfixedFlag,
                       started, uaf, badFix, sawChunk, sawDrop>>
    BY DEF RowNext
  <2>e1. s \in Slots /\ s > front /\ IsAns(rec[<<cur, s>>]) /\ s <= NS BY <2>b, <2>s DEF AnsIn
  <2>e2. \A t \in Slots : front < t /\ t < s => ~IsAns(rec[<<cur, t>>]) BY <2>b, <2>s, <2>e1, <1>0 DEF AnsIn
  <2>f1. <<cur, s>> \in Rows /\ cur \in Nat /\ s \in Nat /\ front \in Nat BY <2>a, <2>e1, <1>0
  <2>f2. ~em[<<cur, s>>]
    <3>1. em[<<cur, s>>] = (started /\ IsAns(rec[<<cur, s>>]) /\ Le(<<cur, s>>, <<cur, front>>)) BY <2>a, <2>f1
    <3>2. ~Le(<<cur, s>>, <<cur, front>>) BY <2>e1, <2>f1
    <3>. QED BY <3>1, <3>2
  <2>f3. \A r \in Rows : em'[r] = (started' /\ IsAns(rec'[r]) /\ Le(r, <<cur', front'>>))
    <3> TAKE r \in Rows
    <3>1. PICK a \in Pages, b \in Slots : r = <<a, b>> BY DEF Rows
    <3>2. a \in Nat /\ b \in Nat BY <3>1, <1>0
    <3>0. started' = started /\ rec' = rec /\ cur' = cur /\ front' = s /\ started BY <2>g, <2>s, <2>0
    <3>3. CASE r = <<cur, s>>
      <4>1. em'[r] = TRUE BY <3>3, <2>s, <2>f1, <2>a DEF Emit
      <4>2. Le(r, <<cur, s>>) BY <3>3, <2>f1
      <4>. QED BY <4>1, <4>2, <3>0, <3>3, <2>e1
    <3>4. CASE r # <<cur, s>>
      <4>1. em'[r] = em[r] BY <3>4, <2>s, <2>f1, <2>a DEF Emit
      <4>2. Le(r, <<cur, s>>) <=> (a < cur \/ (a = cur /\ b <= s)) BY <3>1
      <4>3. Le(r, <<cur, front>>) <=> (a < cur \/ (a = cur /\ b <= front)) BY <3>1
      <4>4. a = cur /\ b = s => FALSE BY <3>1, <3>4
      <4>5. a = cur /\ front < b /\ b < s => ~IsAns(rec[r]) BY <3>1, <2>e2
      <4>6. em[r] = (IsAns(rec[r]) /\ Le(r, <<cur, front>>)) BY <2>a, <2>0
      <4>7. a \in Nat /\ b \in Nat /\ cur \in Nat /\ s \in Nat /\ front \in Nat /\ front < s BY <3>2, <2>f1, <2>e1
      <4>8. em'[r] = (started' /\ IsAns(rec'[r]) /\ Le(r, <<cur', front'>>)) <=> em[r] = (IsAns(rec[r]) /\ Le(r, <<cur, s>>))
        BY <4>1, <3>0
      <4>9. CASE a # cur BY <4>2, <4>3, <4>6, <4>7, <4>8, <4>9
      <4>10. CASE a = cur /\ b <= front BY <4>2, <4>3, <4>6, <4>7, <4>8, <4>10
      <4>11. CASE a = cur /\ front < b /\ b < s BY <4>2, <4>3, <4>5, <4>6, <4>7, <4>8, <4>11
      <4>12. CASE a = cur /\ b > s BY <4>2, <4>3, <4>6, <4>7, <4>8, <4>12
      <4>. QED BY <4>4, <4>7, <4>9, <4>10, <4>11, <4>12
    <3>. QED BY <3>3, <3>4
  <2>f4. em' \in [Rows -> BOOLEAN] /\ dup' = FALSE /\ stray' = FALSE BY <2>s, <2>a, <2>f1, <2>f2, <2>e1 DEF Emit, IGhost
  <2>f5. front' = s /\ s \in 0..NS BY <2>s, <2>e1, <1>0
  <2>p1. IGhost' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IGhost
  <2>p2. IRec' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IRec
  <2>p3. IAlive' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IAlive
  <2>p4. IPhaseB' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IPhaseB
  <2>p5. IPhase' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IPhase
  <2>p6. IFixB' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IFixB
  <2>p7. IFix' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IFix
  <2>p8. IFront' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IFront
  <2>p9. IChunkB' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IChunkB
  <2>p10. IChunk' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IChunk
  <2>p11. IEm' BY <2>0, <2>a, <2>b, <2>s, <2>g, <2>e1, <2>f1, <2>f2, <2>f3, <2>f4, <2>f5, <1>0 DEF IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>27. CASE Env
  <2> USE <1>27 DEF IndInv
  <2>0. /\ \A r \in Rows : IsAns(rec'[r]) = IsAns(rec[r])
        /\ rec' \in [Rows -> Kinds]
        /\ UNCHANGED <<learned, em, ph, cur, fixed, front, cstart, cend, npos, more, rpos, ptrValid, unfixedFlag,
                       started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>>
    BY EnvAns DEF Env, EnvUpdate, EnvVacuum, EnvInsert, EnvRemove, EnvVars
  <2>t. cur \in Pages BY DEF IFix
  <2>1. \A s \in Slots : Ans(cur, s)' = Ans(cur, s) BY <2>0, <2>t DEF Rows
  <2>2. HasAns(cur)' = HasAns(cur) BY <2>1
  <2>3. \A a, b \in 0..NS : AnsIn(a, b)' = AnsIn(a, b) BY <2>1
  <2>4. IAlive' /\ (fixed => alive'[cur])
    <3>1. CASE EnvUpdate
      <4>1. PICK r \in Rows : rec[r] \in {"vis", "rep"} /\ Free(r[1]) /\ rec' = [rec EXCEPT ![r] = "off"] /\ UNCHANGED alive
        BY <3>1 DEF EnvUpdate
      <4>. QED BY <4>1 DEF IAlive, IFix, IRec, Rows
    <3>2. CASE EnvVacuum
      <4>1. PICK r \in Rows : rec[r] = "inv" /\ Free(r[1]) /\ rec' = [rec EXCEPT ![r] = "none"] /\ UNCHANGED alive
        BY <3>2 DEF EnvVacuum
      <4>. QED BY <4>1 DEF IAlive, IFix, IRec, Rows
    <3>3. CASE EnvInsert
      <4>1. PICK r \in Rows : rec[r] = "none" /\ alive[r[1]] /\ Free(r[1]) /\ rec' = [rec EXCEPT ![r] = "inv"]
                              /\ UNCHANGED alive
        BY <3>3 DEF EnvInsert
      <4>2. PICK a \in Pages, b \in Slots : r = <<a, b>> BY <4>1 DEF Rows
      <4>. QED BY <4>1, <4>2 DEF IAlive, IFix, IRec, Rows
    <3>4. CASE EnvRemove
      <4>1. PICK p \in Pages : /\ p # 1 /\ alive[p] /\ Free(p) /\ \A s \in Slots : rec[<<p, s>>] = "none"
                               /\ alive' = [alive EXCEPT ![p] = FALSE] /\ UNCHANGED rec
        BY <3>4 DEF EnvRemove
      <4>. QED BY <4>1 DEF IAlive, IFix
    <3>. QED BY <3>1, <3>2, <3>3, <3>4 DEF Env
  <2> HIDE DEF Ans, HasAns, AnsIn
  <2>p1. IGhost' BY <2>0, <2>1, <2>2, <2>3, <2>4 DEF IGhost, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p2. IRec' BY <2>0, <2>1, <2>2, <2>3, <2>4 DEF IRec, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p4. IPhaseB' BY <2>0, <2>1, <2>2, <2>3, <2>4 DEF IPhaseB, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p5. IPhase' BY <2>0, <2>1, <2>2, <2>3, <2>4 DEF IPhase, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p6. IFixB' BY <2>0, <2>1, <2>2, <2>3, <2>4 DEF IFixB, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p7. IFix' BY <2>0, <2>1, <2>2, <2>3, <2>4 DEF IFix, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p8. IFront' BY <2>0, <2>1, <2>2, <2>3, <2>4 DEF IFront, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p9. IChunkB' BY <2>0, <2>1, <2>2, <2>3, <2>4 DEF IChunkB, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p10. IChunk' BY <2>0, <2>1, <2>2, <2>3, <2>4 DEF IChunk, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p11. IEm' BY <2>0, <2>1, <2>2, <2>3, <2>4 DEF IEm, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm
  <2>p3. IAlive' BY <2>4
  <2>. QED BY <2>p1, <2>p10, <2>p11, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9 DEF IndInv
<1>28. CASE Terminating
  <2> USE <1>28 DEF IndInv
  <2>0. UNCHANGED vars BY DEF Terminating, vars
  <2>1. UNCHANGED <<rec, alive, learned, em, ph, cur, fixed, front, cstart, cend, npos, more, rpos>> BY <2>0 DEF vars
  <2>2. UNCHANGED <<ptrValid, unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>> BY <2>0 DEF vars
  <2>3. /\ HasAns(cur)' = HasAns(cur)
        /\ \A s \in Slots : Ans(cur, s)' = Ans(cur, s)
        /\ \A a, b \in 0..NS : AnsIn(a, b)' = AnsIn(a, b)
    BY <2>1
  <2> HIDE DEF Ans, HasAns, AnsIn
  <2>p1. IGhost' BY <2>1, <2>2, <2>3 DEF IGhost
  <2>p2. IRec' BY <2>1, <2>2, <2>3 DEF IRec
  <2>p3. IAlive' BY <2>1, <2>2, <2>3 DEF IAlive
  <2>p4. IPhaseB' BY <2>1, <2>2, <2>3 DEF IPhaseB
  <2>p5. IPhase' BY <2>1, <2>2, <2>3 DEF IPhase
  <2>p6. IFixB' BY <2>1, <2>2, <2>3 DEF IFixB
  <2>p7. IFix' BY <2>1, <2>2, <2>3 DEF IFix
  <2>p8. IFront' BY <2>1, <2>2, <2>3 DEF IFront
  <2>p9. IChunkB' BY <2>1, <2>2, <2>3 DEF IChunkB
  <2>p10. IChunk' BY <2>1, <2>2, <2>3 DEF IChunk
  <2>p11. IEm' BY <2>1, <2>2, <2>3 DEF IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>29. CASE UNCHANGED vars
  <2> USE <1>29 DEF IndInv
  <2>0. UNCHANGED vars BY DEF vars
  <2>1. UNCHANGED <<rec, alive, learned, em, ph, cur, fixed, front, cstart, cend, npos, more, rpos>> BY <2>0 DEF vars
  <2>2. UNCHANGED <<ptrValid, unfixedFlag, started, uaf, badFix, dup, stray, sawChunk, sawRow, sawDrop>> BY <2>0 DEF vars
  <2>3. /\ HasAns(cur)' = HasAns(cur)
        /\ \A s \in Slots : Ans(cur, s)' = Ans(cur, s)
        /\ \A a, b \in 0..NS : AnsIn(a, b)' = AnsIn(a, b)
    BY <2>1
  <2> HIDE DEF Ans, HasAns, AnsIn
  <2>p1. IGhost' BY <2>1, <2>2, <2>3 DEF IGhost
  <2>p2. IRec' BY <2>1, <2>2, <2>3 DEF IRec
  <2>p3. IAlive' BY <2>1, <2>2, <2>3 DEF IAlive
  <2>p4. IPhaseB' BY <2>1, <2>2, <2>3 DEF IPhaseB
  <2>p5. IPhase' BY <2>1, <2>2, <2>3 DEF IPhase
  <2>p6. IFixB' BY <2>1, <2>2, <2>3 DEF IFixB
  <2>p7. IFix' BY <2>1, <2>2, <2>3 DEF IFix
  <2>p8. IFront' BY <2>1, <2>2, <2>3 DEF IFront
  <2>p9. IChunkB' BY <2>1, <2>2, <2>3 DEF IChunkB
  <2>p10. IChunk' BY <2>1, <2>2, <2>3 DEF IChunk
  <2>p11. IEm' BY <2>1, <2>2, <2>3 DEF IEm
  <2>. QED BY <2>p1, <2>p2, <2>p3, <2>p4, <2>p5, <2>p6, <2>p7, <2>p8, <2>p9, <2>p10, <2>p11 DEF IndInv
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23, <1>24, <1>25, <1>26, <1>27, <1>28, <1>29 DEF Next, Scan

THEOREM InvSafe == IndInv => /\ NoUseAfterUnfix /\ NoFixOfRemovedPage /\ NoDuplicate /\ NoInvisibleRow
                             /\ Complete /\ TypeOK
  BY DEF IndInv, IGhost, IRec, IAlive, IPhaseB, IPhase, IFixB, IFix, IFront, IChunkB, IChunk, IEm, NoUseAfterUnfix, NoFixOfRemovedPage, NoDuplicate, NoInvisibleRow,
         Complete, TypeOK, Phases
=============================================================================
