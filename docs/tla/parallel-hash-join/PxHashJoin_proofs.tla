\* timeout: 5400
-------------------------- MODULE PxHashJoin_proofs --------------------------
(* TLAPS proof that IndInv is an inductive invariant of the correct variant and implies
   ExactlyOnce, NoUseAfterFree, NoLostError and NoLeakedInterrupt, for any set of workers, any
   NU, NM, NP, Phase and NullFill: InitInv and InvSafe (_base), StepInv from the per-action
   lemmas of _lead, _wsimple, _claim, _proc and _rest, and Safe == Spec => []IndInv through PTL (LS4).
   Generated layout; Safe with InvSafe gives Spec => [](the four safety properties). *)
EXTENDS PxHashJoin_proofs_lead, PxHashJoin_proofs_wsimple, PxHashJoin_proofs_claim, PxHashJoin_proofs_proc, PxHashJoin_proofs_rest

THEOREM StepInv == IndInv /\ [Next]_vars => IndInv'
<1> SUFFICES ASSUME IndInv, [Next]_vars PROVE IndInv'
  OBVIOUS
<1>1. CASE L_push
  BY <1>1, Step_L_push
<1>2. CASE L_join
  BY <1>2, Step_L_join
<1>3. CASE L_after
  BY <1>3, Step_L_after
<1>4. CASE L_free
  BY <1>4, Step_L_free
<1>5. CASE L_fallback
  BY <1>5, Step_L_fallback
<1>6. CASE U_cancel
  BY <1>6, Step_U_cancel
<1>7. ASSUME NEW self \in Workers, W_start(self) PROVE IndInv'
  BY <1>7, Step_W_start
<1>8. ASSUME NEW self \in Workers, W_check(self) PROVE IndInv'
  BY <1>8, Step_W_check
<1>9. ASSUME NEW self \in Workers, W_claim(self) PROVE IndInv'
  BY <1>9, Step_W_claim
<1>10. ASSUME NEW self \in Workers, W_cas_write(self) PROVE IndInv'
  BY <1>10, Step_W_cas_write
<1>11. ASSUME NEW self \in Workers, W_fa_write(self) PROVE IndInv'
  BY <1>11, Step_W_fa_write
<1>12. ASSUME NEW self \in Workers, W_proc(self) PROVE IndInv'
  BY <1>12, Step_W_proc
<1>13. ASSUME NEW self \in Workers, W_fl(self) PROVE IndInv'
  BY <1>13, Step_W_fl
<1>14. ASSUME NEW self \in Workers, W_fl_write(self) PROVE IndInv'
  BY <1>14, Step_W_fl_write
<1>15. ASSUME NEW self \in Workers, W_err(self) PROVE IndInv'
  BY <1>15, Step_W_err
<1>16. ASSUME NEW self \in Workers, W_swap(self) PROVE IndInv'
  BY <1>16, Step_W_swap
<1>17. ASSUME NEW self \in Workers, W_rearm(self) PROVE IndInv'
  BY <1>17, Step_W_rearm
<1>18. ASSUME NEW self \in Workers, W_cleanup(self) PROVE IndInv'
  BY <1>18, Step_W_cleanup
<1>19. ASSUME NEW self \in Workers, W_merge(self) PROVE IndInv'
  BY <1>19, Step_W_merge
<1>20. ASSUME NEW self \in Workers, W_pclean(self) PROVE IndInv'
  BY <1>20, Step_W_pclean
<1>21. ASSUME NEW self \in Workers, W_end(self) PROVE IndInv'
  BY <1>21, Step_W_end
<1>22. CASE Terminating
  BY <1>22, Step_Terminating
<1>23. CASE UNCHANGED vars
  BY <1>23, Step_Unchanged
<1>. QED
  BY <1>1, <1>2, <1>3, <1>4, <1>5, <1>6, <1>7, <1>8, <1>9, <1>10, <1>11, <1>12, <1>13, <1>14, <1>15, <1>16, <1>17, <1>18, <1>19, <1>20, <1>21, <1>22, <1>23 DEF Next, leader, user, worker

THEOREM Safe == Spec => []IndInv
  BY InitInv, StepInv, PTL DEF Spec
=============================================================================
