# FoldText — PR 8428 (CBRD-27961) statement text across a set-operation fold, head 3599b53b4

Code: PR head `3599b53b4a1ed4aafcb22c80552f04e4ee3ecd48` (merge-base develop `38c931e7d`): `src/parser/semantic_check.c`
(`pt_fold_union`), `src/compat/db_vdb.c` (`db_compile_statement_local`, read by `db_recompile_for_bind_signature`).
Client side only (CAS, csql): one thread compiles one statement at a time; no shared state across threads.

## Claim and sources

| # | Claim | Kind | Source |
|---|---|---|---|
| C1 | A driver session whose statement folds a set operation recompiles it for the bind signature: no `ER_QPROC_INVALID_XASLNODE` (-452), and the text recompiled is the statement's own | safety | JIRA CBRD-27961 Expected Result (1 row, no error); PR body Purpose |
| C2 | A set operation inside a subquery folds to a node that keeps the text it had | equivalence | PR body Implementation ("부질의 안의 집합 연산은 ... 달라지는 것이 없습니다") |
| C3 | After compilation the statement node carries its own text and length (XASL cache user text, tranlist, error log), also for the second statement of a text and for a node `pt_compile` or `mq_translate` returned | safety | PR body Implementation and Remarks (부수 변화); commit fdd1e3c8b message |

## Refinement map (model -> code, head)

| Model | Code | One step because |
|---|---|---|
| `Parse` | parser: `csql_grammar.y` statement end sets the statement node's `sql_user_text_len`; `parser_new_node` gives every node `g_query_string` / `g_query_string_len` (the previous statement's length); `db_compile_statement_local` saves `sql_user_text`, `sql_user_text_len` with `stmt_start_line` | client-private |
| `FoldTop` | `pt_semantic_check_local` / `pt_eval_type` -> `pt_fold_union` on the statement: the active arm, or `mq_rewrite_query_as_derived` (a node from `parser_new_node`, text = the last parsed statement); head copies the set operation's text to it | one function |
| `FoldSub` | the same on a set operation inside a subquery | one function |
| `FoldNothing` | `pt_fold_union` with `STATEMENT_SET_FOLD_NOTHING` (logged with nothing=1; no run reached it) | one function |
| `Compiled` | `statement = statement_result` after `pt_compile` | |
| `Translate` | `mq_translate`: the same node, a new node from `parser_new_node` (`fresh`: `g_query_string` = the last statement parsed), or the PR body's case `view` (a node made after a view's text was parsed; no run reached it) | |
| `Restore` | the end of `db_compile_statement_local`: `statement->sql_user_text = sql_user_text; ...len = sql_user_text_len` | |
| `Recompile` | `db_recompile_for_bind_signature`: dimension 1 needs `sql_user_text` and a length (else -452) and compiles that text (`db_compile_signature_text`); dimension > 1 compiles `original_buffer` | |
| `NoRecompile`, `Reset` | a compilation without bind values; the next statement | |

Functions of the diff: `pt_fold_union` (`FoldTop`, `FoldSub`), `db_compile_statement_local` (`Parse`, `Restore`).

## Fault model

| Fault | Modeled as |
|---|---|
| error return (semantic error, translation error) | not modeled: `db_compile_statement_local` returns before the restore and the statement is not executed |
| interrupt, lock, latch, OOM, crash, vacuum, DML, HA | not applicable: parse-tree state of one client compilation |
| concurrent threads | not applicable: a CAS compiles one statement at a time |
| other pt_compile callers (triggers, view definitions, CREATE ... AS SELECT) | not modeled: none reaches `db_recompile_for_bind_signature`; their text is cosmetic |
| execution-time fold of a bound copy | not modeled: `db_execute_and_keep_statement_local` copies the statement, binds the values (`pt_bind_values_to_hostvars`) and runs `pt_semantic_type` again, outside the save/restore; a fold there keeps its text only by the copy in `pt_fold_union` (read by the XASL cache entry and the CDC / SBR statement text, `execute_statement.c`) |

## Properties

`RecompileOK` (C1), `SubUnchanged` (C2), `OwnText` (C3), `IndInv`; `Terminates` on one statement (`liveness`).

## Mutants

| cfg | Change (code) | Expected | Kills |
|---|---|---|---|
| `mutant-merge-base` | neither the fold copy nor the restore (develop 38c931e7d) | `OwnText` | C1, C3 |
| `mutant-no-restore` | the fold copy alone (head before fdd1e3c8b): a fresh node of the first of two statements carries the second's text | `OwnText` | C3 |
| `mutant-no-fold-copy` | the restore alone: a derived table made around a subquery's arm takes the last statement's text | `SubUnchanged` | C2 |

Comparison `restore-only` (P76, expect pass, claims C1 and C3 only): within `db_compile_statement_local` the restore
alone keeps C1 and C3 (runtime: a release build of the head without the `pt_fold_union` hunk passes the TC dir,
103/103). Both sites protect C1 and C3 there (cubrid-tla P74: the second site is `db_vdb.c`
`db_compile_statement_local`, the restore). The fold copy is still the only protection of the execution-time fold of
a bound copy (fault table), so it is not redundant.

## Witnesses

| cfg | Outcome |
|---|---|
| `witness-fold`, `witness-wrap`, `witness-subfold` | a top fold to the arm, to a derived table, a fold inside a subquery |
| `witness-fresh`, `witness-view` | a translation that returns a new node (last statement's text; a view's text) |
| `witness-restored` | the restore changes the node's text |

## Dead expressions

| Line | Explanation |
|---|---|
| FoldText.tla:155 | `Reset` (liveness cfg only): `OneStmt` excludes it |
| FoldText.tla:156 | `Reset` (liveness cfg only): `OneStmt` excludes it |
| FoldText.tla:157 | `Reset` (liveness cfg only): `OneStmt` excludes it |

## Bounds

- main: NStmt = 2 (a text of one or two statements; every statement, every fold and translation shape), two folds.
- scale: NStmt = 3. Apalache `apalache-indinv`: `INIT IndInv` with NStmt = 3 (Owners needs a constant range).

## Trace validation

Instrumented scratch worktree `~/dev/cubrid-worktree/pr8428-instr` = 3599b53b4 + `.git_ignored_dir/scratch/pr8428/tla/instrument.py`
(TLATRACE at the save in `db_compile_statement_local` = Parse, `pt_fold_union`'s assignment = Fold, a new node from
`pt_compile` / `mq_translate` = NewTop, the restore = Restore, `db_recompile_for_bind_signature`'s check =
Recompile; every field is a pointer and length comparison the build made), optdebug, prefix
`~/optdebug/CUBRID-pr8428-tla`, libcubridcs.so sha256 `d7f7f64849df88cd...`. CS server port 1700, broker 36000.

| Run | What | cfg | Result |
|---|---|---|---|
| jdbc | JDBC (driver 11.5 jar of the install) prepared statements with binds: TC Cases 1-5, a fold inside an IN subquery, a view with a folding UNION ALL, a plain statement; 16 compilations, 8 recompiles | `witness-trace-jdbc` | accepted (depth 105) |
| csql-multi | csql, two statements in one text (the second folds; its arm has the first's length 35) | `witness-trace-csql-multi` | accepted |
| vclass | csql, virtual class hierarchies (`select ... from all vp` with `vq under vp`, a view over `all cp`): three translations return a new node | `witness-trace-vclass` | accepted |
| corrupted jdbc: the first restore finds another text (pre 1 -> 0) | | `reject-restore-changed` | refused |
| corrupted jdbc: the first recompile fails (ok 1 -> 0) | | `reject-recompile-err` | refused |

No run reached a restore that changed the text (every Restore logged pre=1): the fold copy already gave the folded
node its text, and every new node from `mq_translate` (`ok=1`, 4 runs) already had it. The PR body's `view` case
and `FoldNothing` stay unreached by the runs; the model keeps them.

## Counterexamples

None from the correct variant.

## Findings

None. (`restore-only` passes, but the fold copy also covers the execution-time fold of a bound copy, fault table.)

## Result

- 2026-11-11, `tools/tla/tla-check .claude/review/PR-8428/tla/fold-text` -> `RESULT: OK` (18 cfgs), run dir
  `.git_ignored_dir/scratch/tla/fold-text-20261111-151656-1724560`.
- main 21,337 / 12,591 distinct, depth 23; scale (NStmt = 3) 42,655 / 25,249; restore-only 25,838 / 15,450 (pass);
  Apalache IndInv inductive (NStmt = 3); 3 mutants rejected; 6 witnesses reached; liveness on one statement pass.
- Trace: 3 runs accepted, 2 corrupted runs refused, on 3599b53b4 + TLATRACE, optdebug.
- TLAPS 요청 없음.
- spec sha256: `50889f6c...9d8070d1` FoldText.tla, `508a99db...bcbf1d3a` FoldTextTrace.tla, `a8086cba...08df327b` FoldTextTraceData.tla.
