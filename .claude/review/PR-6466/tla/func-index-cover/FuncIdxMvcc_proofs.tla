-------------------------- MODULE FuncIdxMvcc_proofs --------------------------
(* TLAPS proof of the INV1 premises of FuncIdxMvcc for the correct variant, any number of updates. *)
EXTENDS FuncIdxMvcc, TLAPS

ASSUME Correct == Mutant = "none"
ASSUME Assm == NU \in Nat /\ NU >= 1

USE Correct, Assm

THEOREM InitInv == Init => IndInv
  BY DEF Init, IndInv, TypeOK, R_upd, R_ent, R_read, U1, U2, U3, U4, U5, U6, U7, U8, E1, E2, E3, E4, E5, E6, D1, D2, D3, D4, D5, D6, D7, D8, Upd, Ver

\* the only entry the snapshot sees is the snapshot version's
LEMMA VisIff == ASSUME IndInv, rphase = "scan", NEW e \in Ver PROVE Visible(e) <=> e = vs
<1> USE DEF IndInv, TypeOK, R_upd, R_ent, R_read, U1, U2, U3, U4, U5, U6, U7, U8, E1, E2, E3, E4, E5, E6, D1, D2, D3, D4, D5, D6, D7, D8, Upd, Ver
<1>1. CASE e = vs
  <2>1. ent[e]
    BY <1>1
  <2>2. e = 1 \/ InSnap(e - 1)
    BY <1>1 DEF InSnap
  <2>3. ~(delBy[e] # 0 /\ InSnap(delBy[e]))
    BY <1>1 DEF InSnap
  <2>. QED
    BY <1>1, <2>1, <2>2, <2>3 DEF Visible, M
<1>2. CASE e < vs
  <2>1. CASE ~ent[e]
    BY <2>1, <1>2 DEF Visible, M
  <2>2. CASE ent[e]
    <3>1. e < head
      BY <1>2
    <3>2. delBy[e] \in Upd /\ status[delBy[e]] = "committed" /\ e <= delBy[e]
          /\ \A k \in Upd : (e <= k /\ k < delBy[e]) => status[k] = "aborted"
      BY <3>1, <2>2
    <3>3. vs # 1 /\ status[vs - 1] = "committed"
      BY <1>2
    <3>4. delBy[e] < vs
      BY <3>2, <3>3, <1>2
    <3>5. InSnap(delBy[e])
      BY <3>2, <3>4 DEF InSnap
    <3>. QED
      BY <3>2, <3>5, <1>2 DEF Visible, M
  <2>. QED
    BY <2>1, <2>2
<1>3. CASE e > vs
  <2>1. ~(e = 1) /\ ~InSnap(e - 1)
    BY <1>3 DEF InSnap
  <2>. QED
    BY <2>1, <1>3 DEF Visible, M
<1>. QED
  BY <1>1, <1>2, <1>3

\* the active update's index is at or above the head version
LEMMA HeadBelowCur == ASSUME IndInv, cur # 0 PROVE head <= cur
  BY DEF IndInv, TypeOK, R_upd, U3, U5, U6, Upd, Ver

LEMMA BeginStep == IndInv /\ Begin => IndInv'
<1> SUFFICES ASSUME IndInv, Begin PROVE IndInv'
  OBVIOUS
<1>a. cur = 0 /\ head <= next /\ next \in Upd
  BY DEF IndInv, TypeOK, R_upd, U5, Begin, Upd
<1>b. \A k \in Upd : k # next => status'[k] = status[k]
  BY DEF Begin, IndInv, TypeOK, Upd
<1> USE DEF IndInv, TypeOK, R_upd, R_ent, R_read, U1, U2, U3, U4, U5, U6, U7, U8, E1, E2, E3, E4, E5, E6, D1, D2, D3, D4, D5, D6, D7, D8, Upd, Ver, Begin
<1>T. TypeOK'
  OBVIOUS
<1>U1. U1'
  BY <1>a
<1>U2. U2'
  BY <1>a
<1>U3. U3'
  BY <1>a
<1>U4. U4'
  BY <1>a
<1>U5. U5'
  BY <1>a
<1>U6. U6'
  BY <1>a
<1>U7. U7'
  BY <1>a
<1>U8. U8'
  BY <1>a
<1>E1. E1'
  BY <1>a
<1>E2. E2'
  BY <1>a
<1>E3. E3'
  BY <1>a
<1>E4. E4'
  BY <1>a
<1>E5. E5'
  BY <1>a
<1>E6. E6'
  <2> SUFFICES ASSUME NEW e \in Ver, e > 1, e <= head', ent'[e] PROVE status'[e - 1] = "committed"
    BY DEF E6
  <2>1. head' = head /\ ent'[e] = ent[e] /\ e - 1 \in Upd /\ e - 1 < head
    BY <1>a DEF Begin
  <2>2. status[e - 1] = "committed"
    BY <2>1 DEF E6
  <2>3. status'[e - 1] = status[e - 1]
    BY <1>a, <1>b, <2>1
  <2>. QED
    BY <2>2, <2>3
<1>D1. D1'
  BY <1>a
<1>D2. D2'
  BY <1>a
<1>D3. D3'
  <2> SUFFICES ASSUME rphase' # "idle", vs' # 1 PROVE status'[vs' - 1] = "committed"
    BY DEF D3
  <2>1. vs' = vs /\ rphase' = rphase /\ vs - 1 \in Upd /\ vs - 1 # next /\ status[vs - 1] = "committed"
    BY <1>a DEF Begin
  <2>. QED
    BY <1>b, <2>1
<1>D4. D4'
  BY <1>a
<1>D5. D5'
  BY <1>a
<1>D6. D6'
  BY <1>a
<1>D7. D7'
  BY <1>a
<1>D8. D8'
  BY <1>a
<1>. QED
  BY <1>T, <1>U1, <1>U2, <1>U3, <1>U4, <1>U5, <1>U6, <1>U7, <1>U8, <1>E1, <1>E2, <1>E3, <1>E4, <1>E5, <1>E6, <1>D1, <1>D2, <1>D3, <1>D4, <1>D5, <1>D6, <1>D7, <1>D8 DEF IndInv, TypeOK, R_upd, R_ent, R_read

LEMMA CommitStep == IndInv /\ Commit => IndInv'
<1> SUFFICES ASSUME IndInv, Commit PROVE IndInv'
  OBVIOUS
<1>a. cur # 0 /\ head <= cur /\ cur = next - 1
  BY HeadBelowCur DEF IndInv, R_upd, U3, Commit
<1>b. \A k \in Upd : k # cur => status'[k] = status[k]
  BY <1>a DEF Commit, IndInv, TypeOK, Upd
<1> USE DEF IndInv, TypeOK, R_upd, R_ent, R_read, U1, U2, U3, U4, U5, U6, U7, U8, E1, E2, E3, E4, E5, E6, D1, D2, D3, D4, D5, D6, D7, D8, Upd, Ver, Commit
<1>T. TypeOK'
  OBVIOUS
<1>U1. U1'
  BY <1>a
<1>U2. U2'
  BY <1>a
<1>U3. U3'
  BY <1>a
<1>U4. U4'
  BY <1>a
<1>U5. U5'
  BY <1>a
<1>U6. U6'
  BY <1>a
<1>U7. U7'
  BY <1>a
<1>U8. U8'
  BY <1>a
<1>E1. E1'
  BY <1>a
<1>E2. E2'
  BY <1>a
<1>E3. E3'
  BY <1>a
<1>E4. E4'
  BY <1>a
<1>E5. E5'
  <2> SUFFICES ASSUME NEW e \in Ver, e < head', ent'[e]
               PROVE (/\ delBy[e] \in Upd /\ status[delBy[e]] = "committed" /\ e <= delBy[e]
                      /\ \A k \in Upd : (e <= k /\ k < delBy[e]) => status[k] = "aborted")'
    OBVIOUS
  <2>1. CASE e < head
    <3>1. delBy[e] \in Upd /\ status[delBy[e]] = "committed" /\ e <= delBy[e] /\ delBy[e] + 1 <= head
          /\ \A k \in Upd : (e <= k /\ k < delBy[e]) => status[k] = "aborted"
      BY <2>1, <1>a
    <3>. QED
      BY <3>1, <1>a
  <2>2. CASE e = head
    BY <2>2, <1>a
  <2>. QED
    BY <2>1, <2>2, <1>a
<1>E6. E6'
  BY <1>a, <1>b
<1>D1. D1'
  BY <1>a
<1>D2. D2'
  BY <1>a
<1>D3. D3'
  BY <1>a
<1>D4. D4'
  BY <1>a
<1>D5. D5'
  BY <1>a
<1>D6. D6'
  BY <1>a
<1>D7. D7'
  BY <1>a
<1>D8. D8'
  BY <1>a
<1>. QED
  BY <1>T, <1>U1, <1>U2, <1>U3, <1>U4, <1>U5, <1>U6, <1>U7, <1>U8, <1>E1, <1>E2, <1>E3, <1>E4, <1>E5, <1>E6, <1>D1, <1>D2, <1>D3, <1>D4, <1>D5, <1>D6, <1>D7, <1>D8 DEF IndInv, TypeOK, R_upd, R_ent, R_read

LEMMA AbortStep == IndInv /\ Abort => IndInv'
<1> SUFFICES ASSUME IndInv, Abort PROVE IndInv'
  OBVIOUS
<1>a. cur # 0 /\ head <= cur /\ cur = next - 1
  BY HeadBelowCur DEF IndInv, R_upd, U3, Abort
<1>b. \A k \in Upd : k < head => status'[k] = status[k]
  BY <1>a DEF Abort, IndInv, TypeOK, Upd, Ver
<1>T0. TypeOK'
  <2>1. cur \in Upd /\ cur + 1 \in Ver /\ head \in Ver
    BY <1>a DEF IndInv, TypeOK, Upd, Ver
  <2>2. status' \in [Upd -> {"none", "active", "committed", "aborted"}]
    BY <2>1 DEF Abort, IndInv, TypeOK
  <2>3. ent' \in [Ver -> BOOLEAN]
    BY <2>1 DEF Abort, IndInv, TypeOK
  <2>4. delBy' \in [Ver -> 0..NU]
    BY <2>1 DEF Abort, IndInv, TypeOK
  <2>5. cur' \in 0..NU /\ next' = next /\ head' = head
    BY DEF Abort
  <2>. QED
    BY <2>2, <2>3, <2>4, <2>5 DEF Abort, IndInv, TypeOK
<1> USE DEF IndInv, TypeOK, R_upd, R_ent, R_read, U1, U2, U3, U4, U5, U6, U7, U8, E1, E2, E3, E4, E5, E6, D1, D2, D3, D4, D5, D6, D7, D8, Upd, Ver, Abort
<1>T. TypeOK'
  BY <1>T0
<1>U1. U1'
  BY <1>a
<1>U2. U2'
  BY <1>a
<1>U3. U3'
  BY <1>a
<1>U4. U4'
  BY <1>a
<1>U5. U5'
  BY <1>a
<1>U6. U6'
  BY <1>a
<1>U7. U7'
  BY <1>a
<1>U8. U8'
  BY <1>a
<1>E1. E1'
  BY <1>a
<1>E2. E2'
  BY <1>a
<1>E3. E3'
  BY <1>a
<1>E4. E4'
  BY <1>a
<1>E5. E5'
  <2> SUFFICES ASSUME NEW e \in Ver, e < head, ent'[e]
               PROVE (/\ delBy[e] \in Upd /\ status[delBy[e]] = "committed" /\ e <= delBy[e]
                      /\ \A k \in Upd : (e <= k /\ k < delBy[e]) => status[k] = "aborted")'
    BY <1>a
  <2>1. delBy[e] \in Upd /\ status[delBy[e]] = "committed" /\ e <= delBy[e] /\ delBy[e] + 1 <= head
        /\ \A k \in Upd : (e <= k /\ k < delBy[e]) => status[k] = "aborted"
    BY <1>a
  <2>2. delBy'[e] = delBy[e]
    BY <1>a
  <2>3. \A k \in Upd : k < head => status'[k] = status[k]
    BY <1>a
  <2>4. status'[delBy[e]] = "committed"
    BY <2>1, <2>3
  <2>5. \A k \in Upd : (e <= k /\ k < delBy[e]) => status'[k] = "aborted"
    BY <2>1, <2>3
  <2>. QED
    BY <2>1, <2>2, <2>4, <2>5
<1>E6. E6'
  <2> SUFFICES ASSUME NEW e \in Ver, e > 1, e <= head', ent'[e] PROVE status'[e - 1] = "committed"
    BY DEF E6
  <2>0. head' = head /\ e # cur + 1 /\ e - 1 \in Upd /\ e - 1 < head
    BY <1>a DEF Abort
  <2>1. head' = head /\ ent'[e] = ent[e] /\ e - 1 \in Upd /\ e - 1 < head
    BY <2>0 DEF Abort
  <2>2. status[e - 1] = "committed"
    BY <2>1 DEF E6
  <2>3. status'[e - 1] = status[e - 1]
    BY <1>a, <1>b, <2>1
  <2>. QED
    BY <2>2, <2>3
<1>D1. D1'
  BY <1>a
<1>D2. D2'
  BY <1>a
<1>D3. D3'
  BY <1>a
<1>D4. D4'
  BY <1>a
<1>D5. D5'
  BY <1>a
<1>D6. D6'
  BY <1>a
<1>D7. D7'
  BY <1>a
<1>D8. D8'
  BY <1>a
<1>. QED
  BY <1>T, <1>U1, <1>U2, <1>U3, <1>U4, <1>U5, <1>U6, <1>U7, <1>U8, <1>E1, <1>E2, <1>E3, <1>E4, <1>E5, <1>E6, <1>D1, <1>D2, <1>D3, <1>D4, <1>D5, <1>D6, <1>D7, <1>D8 DEF IndInv, TypeOK, R_upd, R_ent, R_read

LEMMA VacuumStep == ASSUME IndInv, NEW v \in Ver, Vacuum(v) PROVE IndInv'
<1>a. v < head /\ v <= delBy[v] /\ (cur # 0 => v # cur + 1)
  BY HeadBelowCur DEF IndInv, TypeOK, R_upd, R_ent, U3, U4, U7, E1, E3, E4, E5, Vacuum, Upd, Ver
<1>b. rphase = "scan" => v < vs
  BY <1>a DEF Vacuum, M, InSnap, IndInv, TypeOK, Ver, Upd
<1> USE DEF IndInv, TypeOK, R_upd, R_ent, R_read, U1, U2, U3, U4, U5, U6, U7, U8, E1, E2, E3, E4, E5, E6, D1, D2, D3, D4, D5, D6, D7, D8, Upd, Ver, Vacuum
<1>T. TypeOK'
  OBVIOUS
<1>U1. U1'
  BY <1>a, <1>b
<1>U2. U2'
  BY <1>a, <1>b
<1>U3. U3'
  BY <1>a, <1>b
<1>U4. U4'
  BY <1>a, <1>b
<1>U5. U5'
  BY <1>a, <1>b
<1>U6. U6'
  BY <1>a, <1>b
<1>U7. U7'
  BY <1>a, <1>b
<1>U8. U8'
  BY <1>a, <1>b
<1>E1. E1'
  BY <1>a, <1>b
<1>E2. E2'
  BY <1>a, <1>b
<1>E3. E3'
  BY <1>a, <1>b
<1>E4. E4'
  BY <1>a, <1>b
<1>E5. E5'
  BY <1>a, <1>b
<1>E6. E6'
  BY <1>a, <1>b
<1>D1. D1'
  BY <1>a, <1>b
<1>D2. D2'
  BY <1>a, <1>b
<1>D3. D3'
  BY <1>a, <1>b
<1>D4. D4'
  BY <1>a, <1>b
<1>D5. D5'
  BY <1>a, <1>b
<1>D6. D6'
  BY <1>a, <1>b
<1>D7. D7'
  BY <1>a, <1>b
<1>D8. D8'
  BY <1>a, <1>b
<1>. QED
  BY <1>T, <1>U1, <1>U2, <1>U3, <1>U4, <1>U5, <1>U6, <1>U7, <1>U8, <1>E1, <1>E2, <1>E3, <1>E4, <1>E5, <1>E6, <1>D1, <1>D2, <1>D3, <1>D4, <1>D5, <1>D6, <1>D7, <1>D8 DEF IndInv, TypeOK, R_upd, R_ent, R_read

LEMMA StartStep == IndInv /\ Start => IndInv'
<1> SUFFICES ASSUME IndInv, Start PROVE IndInv'
  OBVIOUS
<1>a. cur = 0 \/ head <= cur
  BY HeadBelowCur
<1> USE DEF IndInv, TypeOK, R_upd, R_ent, R_read, U1, U2, U3, U4, U5, U6, U7, U8, E1, E2, E3, E4, E5, E6, D1, D2, D3, D4, D5, D6, D7, D8, Upd, Ver, Start
<1>T. TypeOK'
  OBVIOUS
<1>U1. U1'
  BY <1>a
<1>U2. U2'
  BY <1>a
<1>U3. U3'
  BY <1>a
<1>U4. U4'
  BY <1>a
<1>U5. U5'
  BY <1>a
<1>U6. U6'
  BY <1>a
<1>U7. U7'
  BY <1>a
<1>U8. U8'
  BY <1>a
<1>E1. E1'
  BY <1>a
<1>E2. E2'
  BY <1>a
<1>E3. E3'
  BY <1>a
<1>E4. E4'
  BY <1>a
<1>E5. E5'
  BY <1>a
<1>E6. E6'
  BY <1>a
<1>D1. D1'
  BY <1>a
<1>D2. D2'
  BY <1>a
<1>D3. D3'
  BY <1>a
<1>D4. D4'
  BY <1>a
<1>D5. D5'
  BY <1>a
<1>D6. D6'
  BY <1>a
<1>D7. D7'
  BY <1>a
<1>D8. D8'
  BY <1>a
<1>. QED
  BY <1>T, <1>U1, <1>U2, <1>U3, <1>U4, <1>U5, <1>U6, <1>U7, <1>U8, <1>E1, <1>E2, <1>E3, <1>E4, <1>E5, <1>E6, <1>D1, <1>D2, <1>D3, <1>D4, <1>D5, <1>D6, <1>D7, <1>D8 DEF IndInv, TypeOK, R_upd, R_ent, R_read

LEMMA ScanStep == IndInv /\ Scan => IndInv'
<1> SUFFICES ASSUME IndInv, Scan PROVE IndInv'
  OBVIOUS
<1>a. Visible(pos) <=> pos = vs
  BY VisIff DEF Scan, IndInv, TypeOK, Ver
<1>b. pos = vs => (Out(pos) = vs /\ ((Visible(pos) /\ KfPass(pos) /\ DataPass(pos)) <=> fv[vs]))
  BY <1>a DEF Out, HeapVer, M, KfPass, DataPass, IndInv, TypeOK
<1>c. pos = vs => (~ret[vs] /\ ~gone[vs])
  BY DEF IndInv, TypeOK, R_read, D4, D5, Scan, Ver
<1>d. ret' = (IF Visible(pos) /\ KfPass(pos) /\ DataPass(pos) THEN [ret EXCEPT ![Out(pos)] = TRUE] ELSE ret)
     /\ dup' = (IF Visible(pos) /\ KfPass(pos) /\ DataPass(pos) THEN dup \/ ret[Out(pos)] ELSE dup)
     /\ lost' = (IF Visible(pos) /\ KfPass(pos) /\ DataPass(pos) THEN lost \/ gone[Out(pos)] ELSE lost)
  BY DEF Scan
<1> USE DEF IndInv, TypeOK, R_upd, R_ent, R_read, U1, U2, U3, U4, U5, U6, U7, U8, E1, E2, E3, E4, E5, E6, D1, D2, D3, D4, D5, D6, D7, D8, Upd, Ver, Scan
<1>T. TypeOK'
  OBVIOUS
<1>U1. U1'
  BY <1>a, <1>b, <1>c, <1>d
<1>U2. U2'
  BY <1>a, <1>b, <1>c, <1>d
<1>U3. U3'
  BY <1>a, <1>b, <1>c, <1>d
<1>U4. U4'
  BY <1>a, <1>b, <1>c, <1>d
<1>U5. U5'
  BY <1>a, <1>b, <1>c, <1>d
<1>U6. U6'
  BY <1>a, <1>b, <1>c, <1>d
<1>U7. U7'
  BY <1>a, <1>b, <1>c, <1>d
<1>U8. U8'
  BY <1>a, <1>b, <1>c, <1>d
<1>E1. E1'
  BY <1>a, <1>b, <1>c, <1>d
<1>E2. E2'
  BY <1>a, <1>b, <1>c, <1>d
<1>E3. E3'
  BY <1>a, <1>b, <1>c, <1>d
<1>E4. E4'
  BY <1>a, <1>b, <1>c, <1>d
<1>E5. E5'
  BY <1>a, <1>b, <1>c, <1>d
<1>E6. E6'
  BY <1>a, <1>b, <1>c, <1>d
<1>D1. D1'
  BY <1>a, <1>b, <1>c, <1>d
<1>D2. D2'
  BY <1>a, <1>b, <1>c, <1>d
<1>D3. D3'
  BY <1>a, <1>b, <1>c, <1>d
<1>D4. D4'
  BY <1>a, <1>b, <1>c, <1>d
<1>D5. D5'
  BY <1>a, <1>b, <1>c, <1>d
<1>D6. D6'
  BY <1>a, <1>b, <1>c, <1>d
<1>D7. D7'
  BY <1>a, <1>b, <1>c, <1>d
<1>D8. D8'
  BY <1>a, <1>b, <1>c, <1>d
<1>. QED
  BY <1>T, <1>U1, <1>U2, <1>U3, <1>U4, <1>U5, <1>U6, <1>U7, <1>U8, <1>E1, <1>E2, <1>E3, <1>E4, <1>E5, <1>E6, <1>D1, <1>D2, <1>D3, <1>D4, <1>D5, <1>D6, <1>D7, <1>D8 DEF IndInv, TypeOK, R_upd, R_ent, R_read

LEMMA FinishStep == IndInv /\ Finish => IndInv'
  BY DEF IndInv, TypeOK, R_upd, R_ent, R_read, U1, U2, U3, U4, U5, U6, U7, U8, E1, E2, E3, E4, E5, E6, D1, D2, D3, D4, D5, D6, D7, D8, Upd, Ver, Finish

LEMMA StutterStep == IndInv /\ UNCHANGED vars => IndInv'
  BY DEF IndInv, TypeOK, R_upd, R_ent, R_read, U1, U2, U3, U4, U5, U6, U7, U8, E1, E2, E3, E4, E5, E6, D1, D2, D3, D4, D5, D6, D7, D8, Upd, Ver, vars

THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1>1. CASE Begin
  BY <1>1, BeginStep
<1>2. CASE Commit
  BY <1>2, CommitStep
<1>3. CASE Abort
  BY <1>3, AbortStep
<1>4. CASE \E e \in Ver : Vacuum(e)
  BY <1>4, VacuumStep
<1>5. CASE Start
  BY <1>5, StartStep
<1>6. CASE Scan
  BY <1>6, ScanStep
<1>7. CASE Finish
  BY <1>7, FinishStep
<1>8. CASE UNCHANGED vars
  BY <1>8, StutterStep
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8 DEF Next

THEOREM InvSafe == IndInv => ResultOK /\ NoWrongRow
  BY DEF IndInv, TypeOK, R_read, D5, D6, D7, D8, ResultOK, NoWrongRow, Ver

THEOREM SpecSafe == Spec => []IndInv
  BY InitInv, StepInv, PTL DEF Spec
=============================================================================
