--------------------------- MODULE BvLastRow_proofs ---------------------------
(* TLAPS proof that IndInv is an inductive invariant of the PR head
   (Mutant = "none") and of the candidate fix (Mutant = "fix") for every number
   of source rows N >= 1 and every input class, that it implies the safety
   claims C1-C6 on both, that the fix also keeps develop's paths (C8), and
   Spec => []IndInv. *)
EXTENDS BvLastRow, TLAPS

ASSUME Correct == Mutant \in {"none", "fix"}


THEOREM InitInv == Init => IndInv
  BY Assm DEF Init, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath,
     R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore,
     R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none

LEMMA GenInv == IndInv /\ Gen => IndInv'
<1> SUFFICES ASSUME IndInv, Gen PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct
<1>1. BoolOK'
  BY DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>2. IntOK'
  BY DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>3. StrOK'
  BY DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>4. R_pre'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>5. R_gen'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>6. R_path'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>7. R_ghost'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>8. R_lp'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>9. R_kept'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>10. R_unflagged'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>11. R_alloc'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>12. R_loop'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>13. R_restore'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>14. R_output'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>15. R_out'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>16. R_done'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>17. R_copy'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>18. R_err'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>19. R_cleared'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>20. R_none'
  BY <1>1, <1>2, <1>3 DEF Gen, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA PathInv == IndInv /\ Path => IndInv'
<1> SUFFICES ASSUME IndInv, Path PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct
<1>1. BoolOK'
  BY DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>2. IntOK'
  BY DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>3. StrOK'
  BY DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>4. R_pre'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>5. R_gen'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>6. R_path'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>7. R_ghost'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>8. R_lp'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>9. R_kept'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>10. R_unflagged'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>11. R_alloc'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>12. R_loop'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>13. R_restore'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>14. R_output'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>15. R_out'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>16. R_done'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>17. R_copy'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>18. R_err'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>19. R_cleared'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>20. R_none'
  BY <1>1, <1>2, <1>3 DEF Path, ChoosePath, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA RowInv == ASSUME IndInv, NEW p \in BOOLEAN, Row(p) PROVE IndInv'
<1> USE Assm, Correct
<1> H == Row(p)
<1>0. IndInv /\ Row(p) OBVIOUS
<1>1. BoolOK'
  BY <1>0 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>2. IntOK'
  BY <1>0 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>3. StrOK'
  BY <1>0 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>4. R_pre'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>5. R_gen'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>6. R_path'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>7. R_ghost'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>8. R_lp'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>9. R_kept'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>10. R_unflagged'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>11. R_alloc'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>12. R_loop'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>13. R_restore'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>14. R_output'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>15. R_out'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>16. R_done'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>17. R_copy'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>18. R_err'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>19. R_cleared'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>20. R_none'
  BY <1>0, <1>1, <1>2, <1>3 DEF Row, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA RowKeepFailInv == IndInv /\ RowKeepFail => IndInv'
<1> SUFFICES ASSUME IndInv, RowKeepFail PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct
<1>1. BoolOK'
  BY DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>2. IntOK'
  BY DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>3. StrOK'
  BY DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>4. R_pre'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>5. R_gen'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>6. R_path'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>7. R_ghost'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>8. R_lp'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>9. R_kept'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>10. R_unflagged'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>11. R_alloc'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>12. R_loop'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>13. R_restore'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>14. R_output'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>15. R_out'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>16. R_done'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>17. R_copy'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>18. R_err'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>19. R_cleared'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>20. R_none'
  BY <1>1, <1>2, <1>3 DEF RowKeepFail, Keeps, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA CloseInv == IndInv /\ Close => IndInv'
<1> SUFFICES ASSUME IndInv, Close PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct
<1>1. BoolOK'
  BY DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>2. IntOK'
  BY DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>3. StrOK'
  BY DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>4. R_pre'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>5. R_gen'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>6. R_path'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>7. R_ghost'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>8. R_lp'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>9. R_kept'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>10. R_unflagged'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>11. R_alloc'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>12. R_loop'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>13. R_restore'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>14. R_output'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>15. R_out'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>16. R_done'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>17. R_copy'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>18. R_err'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>19. R_cleared'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>20. R_none'
  BY <1>1, <1>2, <1>3 DEF Close, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA RestoreInv == IndInv /\ Restore => IndInv'
<1> SUFFICES ASSUME IndInv, Restore PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct
<1>1. BoolOK'
  BY DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>2. IntOK'
  BY DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>3. StrOK'
  BY DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>4. R_pre'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>5. R_gen'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>6. R_path'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>7. R_ghost'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>8. R_lp'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>9. R_kept'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>10. R_unflagged'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>11. R_alloc'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>12. R_loop'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>13. R_restore'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>14. R_output'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>15. R_out'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>16. R_done'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>17. R_copy'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>18. R_err'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>19. R_cleared'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>20. R_none'
  BY <1>1, <1>2, <1>3 DEF Restore, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA OutputInv == IndInv /\ Output => IndInv'
<1> SUFFICES ASSUME IndInv, Output PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct
<1>1. BoolOK'
  BY DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>2. IntOK'
  BY DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>3. StrOK'
  BY DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>4. R_pre'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>5. R_gen'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>6. R_path'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>7. R_ghost'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>8. R_lp'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>9. R_kept'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>10. R_unflagged'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>11. R_alloc'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>12. R_loop'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>13. R_restore'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>14. R_output'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>15. R_out'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>16. R_done'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>17. R_copy'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>18. R_err'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>19. R_cleared'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>20. R_none'
  BY <1>1, <1>2, <1>3 DEF Output, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA ClearInv == IndInv /\ Clear => IndInv'
<1> SUFFICES ASSUME IndInv, Clear PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct
<1>1. BoolOK'
  BY DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>2. IntOK'
  BY DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>3. StrOK'
  BY DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>4. R_pre'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>5. R_gen'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>6. R_path'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>7. R_ghost'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>8. R_lp'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>9. R_kept'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>10. R_unflagged'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>11. R_alloc'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>12. R_loop'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>13. R_restore'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>14. R_output'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>15. R_out'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>16. R_done'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>17. R_copy'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>18. R_err'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>19. R_cleared'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>20. R_none'
  BY <1>1, <1>2, <1>3 DEF Clear, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

LEMMA StutterInv == IndInv /\ (Terminating \/ UNCHANGED vars) => IndInv'
<1> SUFFICES ASSUME IndInv, (Terminating \/ UNCHANGED vars) PROVE IndInv'
  OBVIOUS
<1> USE Assm, Correct
<1>1. BoolOK'
  BY DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>2. IntOK'
  BY DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>3. StrOK'
  BY DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>4. R_pre'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>5. R_gen'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>6. R_path'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>7. R_ghost'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>8. R_lp'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>9. R_kept'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>10. R_unflagged'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>11. R_alloc'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>12. R_loop'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>13. R_restore'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>14. R_output'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>15. R_out'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>16. R_done'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>17. R_copy'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>18. R_err'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>19. R_cleared'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>20. R_none'
  BY <1>1, <1>2, <1>3 DEF Terminating, vars, IndInv, TypeOK, BoolOK, IntOK, StrOK, Phases, Paths, BasePath, DevelopNullPath, R_pre, R_gen, R_path, R_ghost, R_lp, R_kept, R_unflagged, R_alloc, R_loop, R_restore, R_output, R_out, R_done, R_copy, R_err, R_cleared, R_none
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20 DEF IndInv, TypeOK

THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1>1. CASE Gen BY <1>1, GenInv
<1>2. CASE Path BY <1>2, PathInv
<1>3. CASE \E p \in BOOLEAN : Row(p) BY <1>3, RowInv
<1>4. CASE RowKeepFail BY <1>4, RowKeepFailInv
<1>5. CASE Close BY <1>5, CloseInv
<1>6. CASE Restore BY <1>6, RestoreInv
<1>7. CASE Output BY <1>7, OutputInv
<1>8. CASE Clear BY <1>8, ClearInv
<1>9. CASE Terminating \/ UNCHANGED vars BY <1>9, StutterInv
<1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9 DEF Next

THEOREM InvSafe == IndInv => /\ OutputIsLastPassed /\ DoneHasOutput /\ NoDanglingRead
                             /\ ImageMatchesServer /\ CopyErrorNotLost /\ NoLeakNoDoubleFree
                             /\ OtherQueriesUnchanged
  BY DEF IndInv, R_out, R_done, R_ghost, R_copy, R_cleared, R_path, R_gen, OutputIsLastPassed,
     DoneHasOutput, NoDanglingRead, ImageMatchesServer, CopyErrorNotLost, NoLeakNoDoubleFree,
     OtherQueriesUnchanged, DevelopNullPath, R_lp, R_none, TypeOK, IntOK

THEOREM FixKeepsOptimizations == Mutant = "fix" /\ IndInv => OptimizationsKept
  BY DEF IndInv, R_path, OptimizationsKept

THEOREM Safe == Spec => []IndInv
  BY InitInv, StepInv, PTL DEF Spec
=============================================================================
