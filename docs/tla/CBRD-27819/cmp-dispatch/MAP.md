# CmpDispatch — which cmpval a decided comparison runs, on which values (CBRD-27819, CUBRID/cubrid#8349)

Code: worktree `~/dev/cubrid-worktree/CBRD-27819` at `74bed19c0` (`01092958a` merged with develop `21c6e635d`);
the finding was made at `7c1130bed`.
The model covers the dispatch half of the PR (commits `66b0b3a9d`, `35e43e8c2`, `735464f0d`, `7c1130bed`):
an integer (SHORT, INTEGER, BIGINT) against a NUMERIC keeps both types and runs an exact cmpval chosen
from the two source types; every other pair runs the compared type's cmpval after the decided
conversions. One run of the spec is one comparison from the client's decision to the server's call.

**The pass cfgs model `01092958a`**: `domain_compare_cmp ()` takes the decided compare and returns the exact
cmpval only when neither side has a conversion target; the decision, the unpack and the key bound's mirror all
call it. `7c1130bed`, which applied that rule at the unpack only, is the mutant `head`; it violates C1 (see
Counterexamples), and `01092958a` is the fix of that counterexample.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | Every installed cmpval reads values of the types it was made for: an exact cmpval gets the unconverted integer and NUMERIC, a type's cmpval gets values of that type — for a stream from an old (develop) client and from a new one, at every server site that installs a cmpval. | `7c1130bed` commit message ("an XASL that converts one side (a stream compiled before the exact pair) compares the converted values by the target type's cmpval"); PR reply to the HyunukLee review (r1: old client → PR server is supported and was fixed) |
| C2 | Every comparison answers the order of the two values (the exact order; develop's answer for these values). | PR body Purpose ("결과 값 … 바뀌지 않습니다") and Implementation 2 |
| C3 | A new stream compares an integer against a NUMERIC by the exact cmpval with no conversion, at every site (decide, unpack, key-bound mirror, expression leaf). | PR body Implementation 2 ("서버는 행마다 정수 타입을 보지 않습니다", "식 프로그램도 이 비교를 씁니다") |

## Refinement map (model -> code)

| Model | Code (`74bed19c0`) | One step because |
|---|---|---|
| `Init` choice of `client` | the binary that compiled the XASL stream: develop (`old`) or the PR (`new`) | input class |
| `Init` choice of `site` | `decide`: an in-process decision used as is (`domain_compute_comparison`, SA/client); `unpack`: `stream_to_xasl.c:stx_unpack_decided_compare` (callers `stx_unpack_compare`, `stx_build_hashjoin_proc`, `stx_build_element_compares`, `stx_build_key_compares` tables/bounds/nonleaf); `mirror`: `stx_build_key_compares:6194` → `domain_compare_mirror` → `btree.c:btree_compare_key_to_bound` (`px_scan_index_leaf_slot_walker.cpp:check_key_in_range`); `expr`: `expr_compile.c:expr_pred_exact_number` (scan-predicate leaf 3043, compiled predicate 4641) on the unpacked compare | input class |
| `ty`, `val` | the two source types (`DOMAIN_COMPARE.source`) and values; tenths so every value is exact in every type the model converts to | input class |
| `DecideStep`, `Decide(old, ..)` | develop `domain_compute_comparison`: `tp_value_compare_common_domain` → `COERCE_SECOND_TO_FIRST/FIRST_TO_SECOND` by `tp_more_general_type`, the less general side converts (`object_domain.c:6338`); cmpval `pr_type_from_id (after[0])` | client-side pure function, no shared state |
| `Decide(new, ..)`, `DecSkip`, `DecConv`, `DecAfter0` | `domain_rules.c:2424` skips the coercion for `domain_compare_is_exact_number`; `2485` `domain_compare_cmp (result)` | same |
| `DomainCompareCmp`, `ExactCmp`, `IntIndex` | `domain_rules.c:1185 domain_compare_cmp`: `target[0]`/`target[1]` set or not an exact pair → `pr_type_from_id` of the first value's converted type; else the `exact[2][3]` table of `domain_cmpval_{short,int,bigint}_numeric` / `numeric_{short,int,bigint}` (1131-1170). A model compare "converts" a side when `conv[i] = 1`, which the code marks by `target[i] != NULL` | pure |
| `Install`, `Unpack` | `stream_to_xasl.c:1930 domain_compare_cmp (compare)` after `target[side]` is set for each `converts` bit (1919-1926) | server-side, on the thread unpacking the XASL; no shared state |
| `Install`, `Mirror` | `domain_rules.c:2340-2358 domain_compare_mirror`: swap sides and targets, `cmp = domain_compare_cmp (mirrored)`; mutant `head` = `7c1130bed`'s `domain_compare_cmp (msrc0, msrc1, mconv0 ? mtarget0 : msrc0)`, which ignored the conversions | same |
| `Install`, `ExprLeaf` | `expr_compile.c:2595-2607`: exact pair, decided compare DIRECT, `conv[0] == conv[1] == NULL`, sources equal to the term's types | same |
| `Eval`, `Actual` | `domain_compare_converted` (1927-1967) converts `conv[s]` sides then calls `cmp->cmpval`; DIRECT calls `cmpval` on the values as they are (`domain_compare_values`, `btree_compare_bound_key` 24249) | one call |
| `Eval`, interpreted branch | an expression term that is no exact leaf: `eval_value_rel_cmp` / `tp_value_compare` with coercion, type-safe by construction | one call |
| `Reads` | the `db_get_*` each cmpval does: `db_get_short/int/bigint` on the integer side, `db_locate_numeric` on the NUMERIC side; a type's cmpval reads both as that type | — |
| `bad`, `wrong`, `usedExact` | ghosts: a cmpval read a value of another type (optdebug: the `db_get_bigint` type assert, `dbtype_function.i:190`); a type-safe comparison answered against the values' order; the exact cmpval ran | — |
| `Answer`, `no_reverse` | `domain_compare_reverse` in the NUMERIC-first cmpvals (`numeric_compare_bigint_num_exact` answers integer-first) | — |

`numeric_compare_bigint_num_exact`'s arithmetic is abstracted to `Sign(x - y)`; the PR's differential harness covers it (Bounds and limits).

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `TypeSafe` | invariant | `~bad` | C1 |
| `ExactAnswer` | invariant | `~wrong` | C2 |
| `NewExactPair` | invariant | done, new client, exact pair ⇒ the exact cmpval ran and nothing was converted | C3 |
| `IndInv` | inductive invariant | every variable is the function of the inputs the phase has computed; `bad = wrong = FALSE`; TLAPS-proved for every `MaxV` | C1-C3 |

## Fault model and environment assumptions

| Item | Modeled as |
|---|---|
| error return | not applicable to C1-C3: a conversion failure (`domain_compare_conversion_failed`) answers before the cmpval runs; int → NUMERIC/BIGINT/DOUBLE of these values cannot fail |
| interrupt / query cancel | not applicable: the decision is made once per XASL; a cancelled scan runs no further comparison |
| lock timeout, deadlock victim, conditional latch failure | not applicable: no lock or latch is taken in the decision or the install; the B-tree page latch around `btree_compare_key_to_bound` does not change which cmpval runs |
| OOM | not applicable: `or_unpack_domain` failure fails the unpack before any cmpval is installed |
| crash / `kill -9` | not applicable: no durable state; a server abort is the observable effect of `bad` in optdebug |
| spurious wakeup | not applicable: no condition wait |
| concurrent DML, vacuum, checkpoint, page flush | not applicable: they change the values compared, not their types or the installed cmpval; every value class is enumerated |
| HA log apply | not applicable: the applier compiles with the server's own binary (`new`) |
| parallel workers | each worker runs the bound's shared, read-only `DOMAIN_KEY_BOUND` compares installed once at unpack; no worker writes them |
| client/server version mix | modeled: `client = old` is a develop client against the PR server; a PR client against a develop server is out of scope (PR reply r1: lockstep upgrade) |

No liveness claim: a run is four steps and terminates (the main cfg checks deadlock freedom up to `Done`).

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-head-mirror` | `domain_compare_mirror` as in `7c1130bed`: exact cmpval for a mirrored exact pair even when a side converts | `TypeSafe` violated: old client, site mirror, SHORT×NUMERIC | C1 |
| `mutant-pre-7c1130bed` | unpack picks `domain_compare_cmp (src0, src1, compared)` regardless of the conversions (`74bfc7b69`) | `TypeSafe` violated (the HyunukLee abort, fail-before of `7c1130bed`) | C1 |
| `mutant-decide-converts` | the new client converts the integer side of an exact pair (no `domain_compare_is_exact_number` skip at 2424) | `NewExactPair` violated: the pair compares as NUMERICs | C3 |
| `mutant-wrong-int-index` | the `exact[][]` column of SHORT and INTEGER exchanged | `TypeSafe` violated | C1 |
| `mutant-expr-no-conv-check` | `expr_pred_exact_number` without the DIRECT / no-conversion test | `TypeSafe` violated: an old stream's NUMERIC cmpval runs on the unconverted integer | C1 |
| `mutant-no-reverse` | NUMERIC-first cmpvals without `domain_compare_reverse` | `ExactAnswer` violated | C2 |
| `mutant-unpack-generic` | unpack always installs `pr_type_from_id` (develop's unpack) | `NewExactPair` violated | C3 |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-old-mirror` | an old client's exact pair (converted) runs at the mirror site type-safely |
| `witness-new-exact-mirror` | a new client's NUMERIC-first pair with different values runs the exact cmpval at the mirror site |

## Dead expressions (pass cfg)

`tla-check` reported no dead-expression lines for `CmpDispatch.cfg` or the scale cfg.

## Counterexamples

| cfg | Trace | Class |
|---|---|---|
| `mutant-head-mirror` (= `7c1130bed`) | Init: client old, site mirror, `ty = <<SHORT, NUMERIC>>`; DecideStep: develop converts the SHORT side to NUMERIC (`conv = <<TRUE, FALSE>>`, CONVERT); Install: unpack installs NUMERIC's cmpval (correct), the mirror swaps to `src = <<NUMERIC, SHORT>>, conv = <<FALSE, TRUE>>` and `domain_compare_cmp` returns `domain_cmpval_numeric_short`; Eval: `domain_compare_converted` converts side 1 to NUMERIC and the cmpval calls `db_get_short` on it → `bad` | **Hole, reproduced.** Every step maps to code and no guard forbids it. Runtime: develop optdebug client (`~/optdebug/CUBRID-cbrd27819-dev`, ef2c78cda) → PR optdebug server (`~/optdebug/CUBRID-cbrd27819-head10`, 7c1130bed), `select /*+ parallel(4) */ count(*) from tp where b > 2.5 using index tpb` (BIGINT index, 300,000 rows): server abort, core pid 1879814, stack `db_get_bigint` assert ← `domain_cmpval_bigint_numeric` ← `domain_compare_converted` ← `btree_compare_key_to_bound` ← `parallel_index_scan::leaf_slot_walker::check_key_in_range`; gdb on the server shows the unpacked bound `src = 22,31 (NUMERIC, BIGINT), conv[1] != NULL` entering `domain_compare_mirror`. Release develop 1802aa581 client → PR release server: no abort, wrong counts 270000 / 0 / 0 / 0 / 0 instead of 299100 / 600 / 600 / 600 / 600 (the `no_parallel_scan` twin 600 is right). develop → develop and PR → PR: 299100 / 600 ×5. Fixed by `01092958a`: the same runs on `~/optdebug/CUBRID-cbrd27819-head11` (libcubrid `e6dbec2f4e432edf`) and `~/release/CUBRID-cbrd27819-head11` (`07b6791b4b00ff55`), develop client and same-version client: 299100 / 600 ×5 and the unpack-path queries of the HyunukLee repro 1 / 3 / 1, core 0; head10 by the same method aborted again (fail-before). Evidence `.git_ignored_dir/scratch/cbrd27819/tla-mirror/` |

## Bounds and limits

- TLC: 5 numeric types (SHORT, INTEGER, BIGINT, NUMERIC, DOUBLE) × 2 clients × 4 sites × values in tenths
  `-1.0..1.0` step 0.5 (`MaxV = 10`); scale cfg `MaxV = 20`. TLAPS proves C1-C3 for every `MaxV`.
- Not modeled: FLOAT, MONETARY, strings, dates and collations (pairs the PR does not touch: `domain_compare_cmp`
  returns `pr_type_from_id (compared)` for them, as develop); `DOMAIN_COMPARE_RANK` / `OBJECT` / `VALUES` methods
  (no cmpval); a PR client against a develop server.
- Not modeled here (no interleaving or decision table to model; covered by the PR's differential harness, counts
  in the PR body): `numeric_compare_bigint_num_exact` / `numeric_db_value_compare` arithmetic, Schubfach
  shortest digits, DOUBLE/FLOAT → NUMERIC and → string, add/sub/mul word paths, ROUND/TRUNC/FLOOR/CEIL,
  `mht_valhash` normalization (affects only the hit rate of tables that decide by comparison).
- Trace validation: not required — the change touches no latch, lock, mutex, condvar, atomic, WAL, vacuum or PX
  coordination protocol. The runtime runs above (gdb on `domain_compare_mirror`, the core) tie the hole's trace to the build.

## Proof method

`CmpDispatch_proofs.tla` is generated by `gen_proofs.py` (`python3 gen_proofs.py > CmpDispatch_proofs.tla`): for
every client and type pair it proves the decision, its unpack and the mirror equal to record literals step by
step, then each site's C1/typing/C3 from those equations; the generator evaluates the spec's operators only to
write the literals, so a wrong evaluation makes a step fail and proves nothing. `StepInv` takes each fact from the
action definition separately: a step citing a fact that holds a CASE, an `\E` or a boolean-valued `IF` failed in
every prover on tlapm 1.4.5 here. The spec keeps conversions as 0/1 flags, builds records instead of `EXCEPT`,
and writes boolean assignments as `IF … THEN TRUE ELSE FALSE` for the same reason (cubrid-tla P3/P4).

## Result

- 2026-11-05, `tools/tla/tla-check docs/tla/CBRD-27819/cmp-dispatch`, toolchain `rr034sppv8gw9k63ppwwb5028rx2chmf-tla-tools`:
  `RESULT: OK`; run dir `.git_ignored_dir/scratch/tla/cmp-dispatch-20261105-211451-1996312`.
- TLC (generated/distinct states, depth): main 12635/10108 (4); scale `MaxV = 20` 38115/30492 (4); inductive
  20216/10108 (1); 7 mutants rejected — head-mirror, pre-7c1130bed, wrong-int-index, expr-no-conv-check
  (`TypeSafe`), no-reverse (`ExactAnswer`), decide-converts, unpack-generic (`NewExactPair`); 2 witnesses reached.
- TLAPS: 7652/7652 obligations proved (`InitInv`, `StepInv`, `InvSafe`), none omitted.
- Spec sha256: `CmpDispatch.tla` 7c90cad6d0f57444f4013ba75c3d104b3f0e323e7dc0b93fd9921440d4b4fc80,
  `CmpDispatch_proofs.tla` 85f6572e57912b6fd28df034244c7016290eb774a52feeec7901d3efd2fb2dfe.
- Engine: finding reproduced on `7c1130bed` (`~/optdebug/CUBRID-cbrd27819-head10`); fix `01092958a`, merged head
  `74bed19c0` (optdebug libcubrid `163e8bc5a3bc440d`, release `a209a407a83ccec5`): develop client → PR server and
  PR → PR answers equal develop's, core 0; medium 975/975, shell `cbrd_27215_expr_program` 1/1 (private-ex `308e9c98a`).
- Trace validation: not required (no latch/lock/condvar/atomic/WAL/vacuum/PX protocol change); see Bounds and limits.
