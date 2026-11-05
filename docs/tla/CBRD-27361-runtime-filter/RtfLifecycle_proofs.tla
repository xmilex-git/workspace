------------------------ MODULE RtfLifecycle_proofs ------------------------
(* TLAPS proof that IndInv is inductive for the correct variant, for any set of workers, keys and row budget,
   and that it implies the safety claims (the premises of the TLA rule INV1). *)
EXTENDS RtfLifecycle, TLAPS

ASSUME Correct == Mutant = "none"

THEOREM InitInv == Init => IndInv
<1> SUFFICES ASSUME Init PROVE IndInv OBVIOUS
<1> USE Assm DEF Init, LPhases, WPhases
<1>0. /\ merged = [w \in Workers |-> FALSE] /\ read = FALSE /\ snap = [w \in Workers |-> 0]
      /\ wph = [w \in Workers |-> "idle"] /\ MaxRows \in Nat
  OBVIOUS
<1>1. IGhost BY <1>0 DEF IGhost
<1>2. ILeader BY <1>0 DEF ILeader
<1>3. IFilter BY <1>0 DEF IFilter
<1>4. IWorkers BY <1>0 DEF IWorkers
<1>5. IMerge
  <2>1. merged \in [Workers -> BOOLEAN] BY <1>0
  <2>2. snap \in [Workers -> 0..MaxRows] BY <1>0
  <2>3. \A w \in Workers : ~merged[w] /\ wph[w] = "idle" BY <1>0
  <2>. QED BY <2>1, <2>2, <2>3, <1>0 DEF IMerge
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5 DEF IndInv

THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct DEF LPhases, WPhases, Held
<1>1. CASE LFirst
  <2>1. IGhost' BY <1>1 DEF LFirst, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>1 DEF LFirst, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>1 DEF LFirst, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>1 DEF LFirst, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>1 DEF LFirst, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>2. CASE LBuild
  <2>1. IGhost' BY <1>2 DEF LBuild, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>2 DEF LBuild, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>2 DEF LBuild, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>2 DEF LBuild, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>2 DEF LBuild, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>3. CASE LBuildFail
  <2>1. IGhost' BY <1>3 DEF LBuildFail, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>3 DEF LBuildFail, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>3 DEF LBuildFail, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>3 DEF LBuildFail, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>3 DEF LBuildFail, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>4. CASE LInterrupt
  <2>1. IGhost' BY <1>4 DEF LInterrupt, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>4 DEF LInterrupt, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>4 DEF LInterrupt, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>4 DEF LInterrupt, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>4 DEF LInterrupt, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>5. CASE LScanEnd
  <2>1. IGhost' BY <1>5 DEF LScanEnd, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>5 DEF LScanEnd, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>5 DEF LScanEnd, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>5 DEF LScanEnd, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>5 DEF LScanEnd, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>6. CASE LClose
  <2>1. IGhost' BY <1>6 DEF LClose, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>6 DEF LClose, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>6 DEF LClose, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>6 DEF LClose, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>6 DEF LClose, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>7. CASE LSignalStop
  <2>1. IGhost' BY <1>7 DEF LSignalStop, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>7 DEF LSignalStop, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>7 DEF LSignalStop, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>7 DEF LSignalStop, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>7 DEF LSignalStop, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>8. CASE LRelease
  <2>0. \A x \in Workers : Held[x] = rows[x]
    <3> SUFFICES ASSUME NEW x \in Workers PROVE Held[x] = rows[x] OBVIOUS
    <3>1. lph = "release" BY <1>8 DEF LRelease
    <3>2. wph[x] \in {"idle", "done"} BY <3>1 DEF IndInv, IWorkers
    <3>3. merged[x] \/ rows[x] = 0 BY <3>2 DEF IndInv, IWorkers, IMerge
    <3>. QED BY <3>3
  <2>h. Held = rows BY <2>0 DEF IndInv, IWorkers, IMerge
  <2>i. lph' = "done" BY <1>8 DEF LRelease
  <2>1. IGhost' BY <1>8, <2>h, <2>i DEF LRelease, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>8, <2>h, <2>i DEF LRelease, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>8, <2>h, <2>i DEF LRelease, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>8, <2>h, <2>i DEF LRelease, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>8, <2>h, <2>i DEF LRelease, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>9. CASE LReadEarly
  <2>1. IGhost' BY <1>9 DEF LReadEarly, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>9 DEF LReadEarly, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>9 DEF LReadEarly, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>9 DEF LReadEarly, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>9 DEF LReadEarly, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>10. ASSUME NEW v \in Workers, WBind(v) PROVE IndInv'
  <2>1. IGhost' BY <1>10 DEF WBind, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>10 DEF WBind, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>10 DEF WBind, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>10 DEF WBind, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>10 DEF WBind, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>11. ASSUME NEW v \in Workers, WRow(v) PROVE IndInv'
  <2>1. IGhost' BY <1>11 DEF WRow, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>11 DEF WRow, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>11 DEF WRow, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>11 DEF WRow, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>11 DEF WRow, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>12. ASSUME NEW v \in Workers, WProbe(v) PROVE IndInv'
  <2>1. IGhost' BY <1>12 DEF WProbe, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>12 DEF WProbe, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>12 DEF WProbe, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>12 DEF WProbe, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>12 DEF WProbe, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>13. ASSUME NEW v \in Workers, WSample(v) PROVE IndInv'
  <2>1. IGhost' BY <1>13 DEF WSample, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>13 DEF WSample, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>13 DEF WSample, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>13 DEF WSample, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>13 DEF WSample, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>14. ASSUME NEW v \in Workers, WEnd(v) PROVE IndInv'
  <2>1. IGhost' BY <1>14 DEF WEnd, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>14 DEF WEnd, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>14 DEF WEnd, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>14 DEF WEnd, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>14 DEF WEnd, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>15. ASSUME NEW v \in Workers, WError(v) PROVE IndInv'
  <2>1. IGhost' BY <1>15 DEF WError, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>15 DEF WError, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>15 DEF WError, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>15 DEF WError, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>15 DEF WError, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>16. ASSUME NEW v \in Workers, WSkip(v) PROVE IndInv'
  <2>1. IGhost' BY <1>16 DEF WSkip, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>16 DEF WSkip, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>16 DEF WSkip, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>16 DEF WSkip, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>16 DEF WSkip, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>17. ASSUME NEW v \in Workers, WFinalize(v) PROVE IndInv'
  <2>1. IGhost' BY <1>17 DEF WFinalize, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>17 DEF WFinalize, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>17 DEF WFinalize, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>17 DEF WFinalize, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>17 DEF WFinalize, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>18. CASE Terminating
  <2>1. IGhost' BY <1>18 DEF Terminating, vars, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>18 DEF Terminating, vars, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>18 DEF Terminating, vars, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>18 DEF Terminating, vars, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>18 DEF Terminating, vars, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>19. CASE UNCHANGED vars
  <2>1. IGhost' BY <1>19 DEF vars, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>2. ILeader' BY <1>19 DEF vars, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>3. IFilter' BY <1>19 DEF vars, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>4. IWorkers' BY <1>19 DEF vars, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>5. IMerge' BY <1>19 DEF vars, IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge
  <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5 DEF IndInv
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19 DEF Next

THEOREM InvSafe == IndInv => NoUseAfterFree /\ NoFalseNegative /\ CountsComplete /\ TypeOK
  BY DEF IndInv, IGhost, ILeader, IFilter, IWorkers, IMerge, NoUseAfterFree, NoFalseNegative, CountsComplete, TypeOK
=============================================================================
