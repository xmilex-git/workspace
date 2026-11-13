---------------------------- MODULE FuncIdxCover ----------------------------
(* PR #6466 (CBRD-25984) at f1f4f21ea: how one index scan of a table that has a function index on F = f(arg)
   decides covering and key filters (optimizer), routes F to the result kept in the key (XASL generation),
   and what each consumer of F reads at run time. One query, one scan node; the inputs are the shape of the
   index and of the query, chosen in Init. Rows share one key value: a row whose stored key value is not the
   value F gives for its own arguments in this session is "stale". *)
EXTENDS Naturals

CONSTANTS NR, Mutant, NegZero
\* apalache-type: NR Int
\* apalache-type: Mutant Str
\* apalache-type: NegZero Bool

Rows == 1..NR
Mutants == {"none", "develop", "no_sarg_class", "no_join_expr", "no_domain_gate", "no_session_gate",
            "gate_before_fseg", "loose_kept", "mro_minus1", "no_uncover", "no_routable", "kf_no_exact",
            "kf_develop", "plain_no_skip", "fix_negzero"}
ASSUME NR \in Nat /\ NR >= 1 /\ Mutant \in Mutants /\ NegZero \in BOOLEAN

VARIABLES phase,
  funcIdx, argInKey, useF, fInSel, fInSarg, fInOuter, fInJoin, mixed, rawArg, extraCol, heapStmt, agg,
  domBad, sess, negZero, listfile, looseHint, mro, stale,
  cover, kf, icover, loose, fic, rsel, rkf,
  ok, err, abort
\* apalache-type: phase Str
\* apalache-type: funcIdx Bool
\* apalache-type: argInKey Bool
\* apalache-type: useF Bool
\* apalache-type: fInSel Bool
\* apalache-type: fInSarg Bool
\* apalache-type: fInOuter Bool
\* apalache-type: fInJoin Bool
\* apalache-type: mixed Bool
\* apalache-type: rawArg Bool
\* apalache-type: extraCol Bool
\* apalache-type: heapStmt Bool
\* apalache-type: agg Bool
\* apalache-type: domBad Bool
\* apalache-type: sess Bool
\* apalache-type: negZero Bool
\* apalache-type: listfile Bool
\* apalache-type: looseHint Bool
\* apalache-type: mro Bool
\* apalache-type: stale Int -> Bool
\* apalache-type: cover Bool
\* apalache-type: kf Bool
\* apalache-type: icover Bool
\* apalache-type: loose Bool
\* apalache-type: fic Bool
\* apalache-type: rsel Bool
\* apalache-type: rkf Bool
\* apalache-type: ok Int -> Bool
\* apalache-type: err Bool
\* apalache-type: abort Bool

vars == <<phase, funcIdx, argInKey, useF, fInSel, fInSarg, fInOuter, fInJoin, mixed, rawArg, extraCol, heapStmt,
          agg, domBad, sess, negZero, listfile, looseHint, mro, stale, cover, kf, icover, loose, fic, rsel, rkf,
          ok, err, abort>>

M(x) == Mutant = x

(* ---- optimizer: qo_is_coverage_index, qo_index_forbids_key_filter ---- *)
ArgRef == useF \/ rawArg \/ mixed
\* qo_seg_used_raw_walk: an expression printed like F but spanning two specs is a raw use of the argument
MixedRaw == mixed /\ ~M("no_join_expr")
\* qo_seg_used_only_in_func_index: the argument appears only inside F
OnlyInF == funcIdx /\ ~agg /\ useF /\ ~rawArg /\ ~MixedRaw
Cover0 == ~ArgRef \/ argInKey \/ OnlyInF
\* qo_is_func_index_routable
Routable == ~heapStmt \/ M("no_routable")
\* qo_is_func_index_key_result_exact (the signed-zero gate exists only in the candidate fix)
KeyExact == (~domBad \/ M("no_domain_gate")) /\ (~sess \/ M("no_session_gate")) /\ (~negZero \/ ~M("fix_negzero"))
\* the term loop: only a sarg of this node is routed
OtherOK == ~fInJoin /\ (~fInOuter \/ M("no_sarg_class"))
\* a column the query reads that is neither a key column nor an argument of F
CoverDev == ~extraCol /\ ~useF /\ (~ArgRef \/ argInKey)
CoverHead ==
  ~extraCol /\
  IF ~funcIdx THEN (~ArgRef \/ argInKey) /\ (~useF \/ ~M("plain_no_skip"))
  ELSE IF ~useF THEN Cover0 /\ (Routable \/ ~M("gate_before_fseg"))
  ELSE Cover0 /\ Routable /\ KeyExact /\ OtherOK
CoverD == IF M("develop") THEN CoverDev ELSE CoverHead
KfD(c) == funcIdx /\ fInSarg /\
  (IF M("develop") \/ M("kf_develop") THEN c ELSE c \/ (Routable /\ (KeyExact \/ M("kf_no_exact"))))

(* ---- XASL generation: pt_uncover_func_index_scans, pt_make_func_index_cover, pt_collect_func_index_cover ---- *)
Uncover == listfile /\ funcIdx /\ ~argInKey /\ ArgRef /\ ~M("no_uncover")
FicD == ~M("develop") /\ funcIdx /\ Routable /\ useF

(* ---- execution ---- *)
\* a covered scan has the argument only when it is a key column; a heap scan always has it
ArgAvail == ~icover \/ argInKey
RowOK(r) ==
  /\ fInSel => (IF rsel THEN ~stale[r] ELSE ArgAvail)
  /\ fInSarg => (IF kf THEN (IF rkf THEN ~stale[r] ELSE argInKey) ELSE ArgAvail)
  /\ (fInOuter \/ fInJoin \/ mixed \/ rawArg) => ArgAvail
\* heap re-evaluation reads the pseudo result attribute from the heap; MRO dump with col id -1 misses it
ErrD == (heapStmt /\ (rsel \/ rkf)) \/ (mro /\ rsel /\ M("mro_minus1"))
\* qo_is_index_loose_scan asserts index_cover
AbortD == loose /\ ~icover

InputOK ==
  /\ useF = (fInSel \/ fInSarg \/ fInOuter \/ fInJoin)
  /\ (domBad \/ sess \/ negZero) => funcIdx
  /\ negZero => NegZero
  /\ mro => ~listfile
  /\ ~stale[1]
  /\ \A r \in Rows : stale[r] => (domBad \/ sess \/ negZero)

Init ==
  /\ phase = "plan"
  /\ funcIdx \in BOOLEAN /\ argInKey \in BOOLEAN /\ useF \in BOOLEAN /\ fInSel \in BOOLEAN
  /\ fInSarg \in BOOLEAN /\ fInOuter \in BOOLEAN /\ fInJoin \in BOOLEAN /\ mixed \in BOOLEAN
  /\ rawArg \in BOOLEAN /\ extraCol \in BOOLEAN /\ heapStmt \in BOOLEAN /\ agg \in BOOLEAN /\ domBad \in BOOLEAN
  /\ sess \in BOOLEAN /\ negZero \in BOOLEAN /\ listfile \in BOOLEAN /\ looseHint \in BOOLEAN
  /\ mro \in BOOLEAN /\ stale \in [Rows -> BOOLEAN]
  /\ InputOK
  /\ cover = FALSE /\ kf = FALSE
  /\ icover = FALSE /\ loose = FALSE /\ fic = FALSE /\ rsel = FALSE /\ rkf = FALSE
  /\ ok = [r \in Rows |-> FALSE] /\ err = FALSE /\ abort = FALSE

Plan ==
  /\ phase = "plan" /\ phase' = "gen"
  /\ cover' = CoverD
  /\ kf' = KfD(CoverD)
  /\ UNCHANGED <<funcIdx, argInKey, useF, fInSel, fInSarg, fInOuter, fInJoin, mixed, rawArg, extraCol, heapStmt, agg,
                 domBad, sess, negZero, listfile, looseHint, mro, stale,
                 icover, loose, fic, rsel, rkf, ok, err, abort>>

Gen ==
  /\ phase = "gen" /\ phase' = "exec"
  /\ icover' = (cover /\ ~Uncover)
  /\ loose' = (looseHint /\ cover /\ (~Uncover \/ M("loose_kept")))
  /\ fic' = FicD
  /\ rsel' = (FicD /\ cover /\ ~Uncover /\ ~listfile /\ ~agg)
  /\ rkf' = (kf /\ FicD)
  /\ UNCHANGED <<funcIdx, argInKey, useF, fInSel, fInSarg, fInOuter, fInJoin, mixed, rawArg, extraCol, heapStmt, agg,
                 domBad, sess, negZero, listfile, looseHint, mro, stale,
                 cover, kf, ok, err, abort>>

Exec ==
  /\ phase = "exec" /\ phase' = "done"
  /\ ok' = [r \in Rows |-> RowOK(r)]
  /\ err' = ErrD
  /\ abort' = AbortD
  /\ UNCHANGED <<funcIdx, argInKey, useF, fInSel, fInSarg, fInOuter, fInJoin, mixed, rawArg, extraCol, heapStmt, agg,
                 domBad, sess, negZero, listfile, looseHint, mro, stale,
                 cover, kf, icover, loose, fic, rsel, rkf>>

Next == Plan \/ Gen \/ Exec
Spec == Init /\ [][Next]_vars

(* ---- properties ---- *)
Planned == phase \in {"gen", "exec", "done"}
Safe == ~extraCol /\ funcIdx /\ useF /\ ~heapStmt /\ ~domBad /\ ~sess /\ ~negZero /\ ~fInOuter /\ ~fInJoin /\ ~rawArg /\ ~mixed /\ ~agg

TypeOK ==
  /\ phase \in {"plan", "gen", "exec", "done"}
  /\ funcIdx \in BOOLEAN /\ argInKey \in BOOLEAN /\ useF \in BOOLEAN /\ fInSel \in BOOLEAN
  /\ fInSarg \in BOOLEAN /\ fInOuter \in BOOLEAN /\ fInJoin \in BOOLEAN /\ mixed \in BOOLEAN
  /\ rawArg \in BOOLEAN /\ extraCol \in BOOLEAN /\ heapStmt \in BOOLEAN /\ agg \in BOOLEAN /\ domBad \in BOOLEAN
  /\ sess \in BOOLEAN /\ negZero \in BOOLEAN /\ listfile \in BOOLEAN /\ looseHint \in BOOLEAN
  /\ mro \in BOOLEAN /\ stale \in [Rows -> BOOLEAN]
  /\ cover \in BOOLEAN /\ kf \in BOOLEAN
  /\ icover \in BOOLEAN /\ loose \in BOOLEAN /\ fic \in BOOLEAN /\ rsel \in BOOLEAN /\ rkf \in BOOLEAN
  /\ ok \in [Rows -> BOOLEAN] /\ err \in BOOLEAN /\ abort \in BOOLEAN

\* C2 C4 C5: every consumer of F gets the value develop computes, with no error and no abort
Equiv == phase = "done" => ((\A r \in Rows : ok[r]) /\ ~err /\ ~abort)
\* C1: the JIRA case is covered, and its projection read from the key when nothing puts the scan in a list file
CoverWhenSafe == (Planned /\ Safe) => cover
RouteWhenSafe == (phase \in {"exec", "done"} /\ Safe /\ fInSel /\ ~listfile) => rsel
\* C3: a key filter on F is allowed without covering when the key result is exact
KfWhenSafe == (Planned /\ funcIdx /\ fInSarg /\ ~heapStmt /\ ~domBad /\ ~sess /\ ~negZero) => kf
\* C6: a plain index on the argument covers a query that reads F
PlainCover == (Planned /\ ~extraCol /\ ~funcIdx /\ argInKey) => cover
\* C7: a function index whose expression the query does not read is decided as develop
NoFAsDevelop == (Planned /\ funcIdx /\ ~useF) => (cover = CoverDev)

IndInv ==
  /\ TypeOK
  /\ InputOK
  /\ Planned => (cover = CoverD /\ kf = KfD(CoverD))
  /\ phase \in {"exec", "done"} =>
       (/\ icover = (cover /\ ~Uncover)
        /\ loose = (looseHint /\ cover /\ (~Uncover \/ M("loose_kept")))
        /\ fic = FicD
        /\ rsel = (FicD /\ cover /\ ~Uncover /\ ~listfile /\ ~agg)
        /\ rkf = (kf /\ FicD))
  /\ phase = "done" => (ok = [r \in Rows |-> RowOK(r)] /\ err = ErrD /\ abort = AbortD)

(* ---- witnesses ---- *)
NotRoutedCover == ~(phase = "done" /\ rsel /\ fInSel)
NotNonCoverKf == ~(phase = "done" /\ rkf /\ ~icover)
NotUncovered == ~(phase = "done" /\ cover /\ ~icover)
NotPlainCoverWithF == ~(phase = "done" /\ ~funcIdx /\ useF /\ icover)
NotStaleSafe == ~(phase = "done" /\ stale[NR] /\ fInSel /\ ~rsel)

\* Apalache inductive check: the correct variant, every row count is not expressible over a function set,
\* so the row count is fixed and the rest is symbolic
CInit == NR = 2 /\ Mutant = "none" /\ NegZero = FALSE
=============================================================================
