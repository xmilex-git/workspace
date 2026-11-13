# GcFields — the fields of the GROUP_CONCAT accumulator after every append (PR 8398, CBRD-27926)

Model of CUBRID/cubrid#8398 at `ea06eca48` (`Fix = "none"`, `SepFix = FALSE`) and at its head `175c6e716`
(`Fix = "prec"`: `327e3d759` writes the maximum precision; `SepFix = TRUE`: `5d9afc902` appends no separator for
a NULL one) (worktree `~/dev/cubrid-worktree/CBRD-27926`), against its merge base develop `0661d2c12`. `GcBuf` (sibling
directory) models the buffer protocol; its MAP.md excluded the value fields ("a decision table over value
classes, checked at runtime"), and the runtime check it named (develop vs head output diff) cannot see a
field a reader does not print. A review comment (soheejung-cs, 2026-11-09, string_opfunc.c:1541) found one:
`db_string_append` leaves `TP_FLOATING_PRECISION_VALUE` where develop's `db_value_domain_init` writes the
maximum. This model puts develop's path (`dev`) and the PR's path (`pr`) side by side on the same inputs
and compares every field a reader can see.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | After every append the PR's accumulator holds the fields develop's leaves (type, precision, size, characters, length cache, zero-byte position, codeset, collation, NULL, compression cache). | `db_string_append` header comment (string_opfunc.c:1351: "leaving string1 what db_string_concatenate (string1, string2, string1) leaves it"); PR Remarks |
| C2 | The written result is develop's: its type, the precision a domain resolves it to (`tp_domain_resolve_value`, `db_make_*` turn -1 into the maximum), bytes, length, codeset, collation, NULL. | JIRA Specification Changes ("GROUP_CONCAT 결과 ... 바뀌지 않습니다"); PR Remarks |
| C3 | A compressed copy of bytes the value no longer holds is never written. | `pr_do_db_value_string_compression` caches the copy in the value (object_primitive.c:14882); an in-place append keeps the cache fields |
| C4 | A cached character length is the content's. | `db_get_string_length` returns the cache when it is not -1 (string_opfunc.c:8524) |
| C5 | `db_string_append_zero_bytes` runs on a VARCHAR only. | its `assert (DB_VALUE_DOMAIN_TYPE (string) == DB_TYPE_VARCHAR && bytes > 0)` |

## Refinement map (model -> code)

| Model | Code | One step because |
|---|---|---|
| value record `t p sz ln lc zp zl cs co nul cmp` | `DB_VALUE_DOMAIN_TYPE`, `domain.char_info.length`, `data.ch.medium.size` (bits for a bit string), `intl_char_count` over the bytes, `data.ch.medium.length`, the first zero byte / characters before it (strlen in `db_string_fix_string_size`), `data.ch.medium.codeset`, `domain.char_info.collation_id`, `is_null`, `compressed_size` | |
| `DomInit` | `db_macro.c:db_value_domain_init` VARCHAR/VARBIT: -1 or 0 -> maximum; CHAR/BIT: -1 stays | |
| `Mk` | `qstr_make_typed_string` -> `db_make_{char,varchar,bit,varbit}` -> `db_make_db_char` (length -1, compression not yet, `is_null` for 0 bytes under `oracle_style_empty_string`) | |
| `Clone` | `pr_clone_value` -> `mr_setval_string` (keeps length and compression cache) / `mr_setval_varbit` (remakes) | |
| `Coerce` | `db_value_domain_init (&temp, type, QSTR_VALUE_PRECISION (x))` + `db_char_string_coerce` | |
| `DevCat` | develop `string_opfunc.c:db_string_concatenate` with `qstr_concatenate` / `qstr_bit_concatenate` | |
| `DevStep` | develop `query_opfunc.c:qdata_concatenate_dbval` (spare bytes: `qstr_make_typed_string (..., size + spare_bytes, cs (dbval1), co (dbval1))`) + the caller's `pr_clone_value (&tmp_val, accumulator)` when `tmp_val` is not NULL | the node is owned by one thread for the call (GcBuf's map) |
| `PrApp`, `PrAppChar`, `PrAppB`, `PrAppC*` | PR `string_opfunc.c:db_string_append`: CHAR/BIT start branch, VARBIT branch, VARCHAR branch with the codeset branch | same |
| `Reserve` | `string_opfunc.c:qstr_reserve` (remakes the value, restores the length, clears `is_null`); `g` = it runs (capacity), forced after a capacity reset (`fresh`, the coerced string1) | same |
| `PrZero` | `db_string_append_zero_bytes` + `db_string_put_cs_and_collation` with the pre-append codeset (`qdata_append_chars_to_dbval`) | same |
| `Cuts`, `Trunc` | `qdata_concatenate_dbval`'s `res_size >= max` / `res_size + val_size > max` branches, `db_string_limit_size_string` | |
| `AppStep` kinds `first` / `sep` / `val` | `qdata_group_concat_first_value` (`db_value_domain_init` + `db_string_make_empty_typed_string` of the domain, `is_null = 0` under oracle style), `qdata_group_concat_value` (separator, then value) | |
| `wfirst`, `msep`, `mval`, `MergeClone`, `Borrow`, `Restore` | px workers' clones; `px_scan_result_handler.cpp:finalize_node` (`qdata_group_concat_value (orig, worker value)` or `capacity = 0` + `pr_clone_value`), `rehome_node<PT_GROUP_CONCAT>` BORROW / RESTORE | under `writer_results_mutex` / coordinator thread (GcBuf's map) |
| `SepSet`, `OraSep`, `SepFix` | the separator `accumulator.value2` set by `xasl_generation.c` (default `','`, a literal, NULL for bits); under oracle style `SEPARATOR ''` is NULL: at `ea06eca48` (`SepFix = FALSE`) `qdata_group_concat_value` filled `value2` with an empty string, after the fix no separator is appended | |
| `Fin` / `FixSize` | `qdata_finalize_aggregate_list`: `db_string_fix_string_size` for a non-NULL GROUP_CONCAT (character types only, strlen) | |
| `Compress`, `Write` | `mr_lengthval/writeval_string` -> `pr_do_db_value_string_compression` when the output tuple is written; `qexec_clear_agg_list` / `qexec_gby_finalize_group_dim` | |
| `Fix = "prec"` | `327e3d759`: `db_string_append` writes `DB_MAX_VARCHAR_PRECISION` / `DB_MAX_VARBIT_PRECISION` where `ea06eca48` wrote `TP_FLOATING_PRECISION_VALUE` (`Fix = "none"`) | |

Callers of the entry points are GcBuf's (code-index `callers`): `qdata_concatenate_dbval` <-
`qdata_group_concat_first_value`, `qdata_group_concat_value`; those <- `qdata_evaluate_aggregate_list`,
`qdata_finalize_aggregate_list` (ORDER BY / DISTINCT replay), `accumulate_node`, `finalize_node`.
`db_string_append` / `db_string_append_zero_bytes` <- `qdata_append_chars_to_dbval` only.

## Fault table

| Fault | Modeled as |
|---|---|
| a value of the other category (bit vs character) | not modeled: type checking casts the argument to the function's domain (CBRD-27583); both paths return an error before writing (`ER_QSTR_INCOMPATIBLE_CODE_SETS` / `ER_QSTR_INVALID_DATA_TYPE`) |
| a different collation | not modeled: `qdata_concatenate_dbval` asserts the collations are equal (query_opfunc.c:2786); both paths return `ER_QSTR_INCOMPATIBLE_COLLATIONS` |
| a codeset different from the collation's | modeled (`Css = {"u", "k"}`, `dcs`): the codeset branch of both paths; no run of the workload took it (mixed `_euckr` separators are coerced at compile time) |
| OOM, `ER_QPROC_STRING_SIZE_TOO_BIG` | GcBuf's (`Fail`); the accumulator is unchanged on both paths |
| compression between appends | `Mutant = "compress-mid"`: the accumulator reaches `mr_lengthval/writeval_string` only through the output tuple after `qdata_finalize_aggregate_list` |
| NULL value | not modeled: GROUP_CONCAT does not aggregate a NULL argument; a NULL cut (`oracle_style_empty_string`, 0 bytes kept) is modeled (`v.nul`) |
| crash, DML, vacuum, latches, HA, spurious wakeup | not applicable: private memory of one query |
| interrupt during a parallel scan | GcBuf's (`ErrEnd`); fields of a failing query are not written |

## Mutants

All on the head (`Fix = "prec"`, `SepFix`) except `mutant-float-prec`, which is `ea06eca48`'s precision (`Fix = "none"`, the review's finding), so only the mutant's change can break the property.

| cfg | Change (code) | Expected | Kills |
|---|---|---|---|
| `mutant-float-prec` | `ea06eca48`: `db_string_append` leaves `TP_FLOATING_PRECISION_VALUE` | `AccEq` | C1 |
| `mutant-no-pad` | the VARCHAR branch ignores string2's pad characters | `AccEq` violated | C1 |
| `mutant-no-cs-restore` | no `db_string_put_cs_and_collation` after the zero bytes | `AccEq` | C1 |
| `mutant-reserve-keeps-null` | `qstr_reserve` does not clear `is_null` | `AccEq` | C1 |
| `mutant-no-pad-out` | as `no-pad`, checked on the written result | `OutView` | C2 |
| `mutant-compress-mid` | the accumulator is compressed between appends, and `db_string_fix_string_size` keeps the cache (an in-place size fix). A compression between appends alone is harmless: `db_string_fix_string_size` remakes the value with `qstr_make_typed_string` (string_opfunc.c:6265) and `db_make_db_char` sets `compressed_size = DB_NOT_YET_COMPRESSED` (dbtype_function.i:1109), so the mutant removes both protections | `NoStaleWrite` | C3 |
| `mutant-no-lc-reset` | `db_string_append_zero_bytes` keeps the length cache | `LenCache` | C4 |
| `mutant-len-is-size` | the VARCHAR branch caches the byte count as the length | `LenCache` | C4 |
| `mutant-keep-char` | a CHAR start value takes the VARCHAR branch | `NoAssert` | C5 |

## Dead expressions

- `GcFields.tla:393`, `GcFields.tla:394`, `GcFields.tla:395`, `GcFields.tla:396`, `GcFields.tla:397`, `GcFields.tla:398` (`DoApp2`, the append's state update), `GcFields.tla:423`, `GcFields.tla:424`, `GcFields.tla:425`, `GcFields.tla:426`, `GcFields.tla:427`, `GcFields.tla:428`, `GcFields.tla:429` (`After`, the step kind's bookkeeping) and `GcFields.tla:438`
  (`AppStep`'s UNCHANGED): reported unevaluated by both `GcFields` and `GcFields.px`, yet they fire. They are reached
  only through `AppStep`'s nested operator calls with arguments, whose evaluation TLC's coverage counts at the call
  site, not at these definition lines. Evidence that they run: every append changes `dev`/`pr` (the trace cfgs
  accept recorded runs whose every event is an append), `witness-spare`, `witness-pad`, `witness-coerce-acc`,
  `witness-coerce-v`, `witness-trunc-null` and `witness-merge-app` / `witness-merge-cut` reach the `seen` events
  that only line 398 adds, and `witness-merge-app` reaches the `"mval"` step of line 429.
- `GcFields.tla:458`, `GcFields.tla:459`, `GcFields.tla:460` (`Borrow`), `GcFields.tla:465`, `GcFields.tla:466`, `GcFields.tla:467`, `GcFields.tla:468`, `GcFields.tla:469`, `GcFields.tla:470` (`MergeClone`), `GcFields.tla:475`, `GcFields.tla:476`, `GcFields.tla:477`, `GcFields.tla:478`, `GcFields.tla:479` (`Restore`): the parallel coordinator's steps, guarded by
  `mode = "px"`; dead in `GcFields` (serial only), evaluated in `GcFields.px` (not in its dead list) and reached by
  `witness-merge-clone`, `witness-restore-erases`.

## Result

- 2026-11-09/10, `tools/tla/tla-check .claude/review/PR-8398/tla/gc-fields`: `RESULT: OK`, run dir
  `.git_ignored_dir/scratch/tla/gc-fields-20261109-220954-2141464` (PR head `175c6e716`).
- TLC distinct states: main (serial) 35,161, `px` 168,954, `scale-max4` 60,241, `sep0` 35,269. Mutants each
  rejected by the property named in Mutants: `compress-mid` 49,423, `float-prec` 761, `keep-char` 1,807,
  `len-is-size` 763, `no-cs-restore` 2,377, `no-lc-reset` 1,812, `no-pad-out` 14,120, `no-pad` 770,
  `reserve-keeps-null` 1,511. All 18 witnesses reached (`restore-erases` after 1,379,323 distinct states, 1 h 21 min).
- Trace: `witness-trace-dev-orano`, `-dev-orayes`, `-pr-orano`, `-pr-orayes` (develop and PR runs, Oracle mode off
  and on) and `-pr-as-dev` accepted; `reject-swap`, `reject-lc-flip` and `reject-ea06-as-dev` refused.
- Apalache `GcFieldsInd.apalache-indinv`: IndInv inductive (260 s). The last CTI before it (a merge cutting a worker
  value that already carries spare zero bytes, counted as fewer characters than its bytes) was a model error, fixed
  in `CutOK` from `db_string_limit_size_string` (`string_opfunc.c:6182`); the fix left the reachable states unchanged
  (px 168,954 before and after).
- TLAPS 요청 없음.
- spec sha256: `GcFields.tla` b8742ea5aab59cd80eb874861aa3b9f9804b1bde3faa05926fb534e2a735c990, `GcFieldsInd.tla`
  f791ef583fedf65d0bd8bc9588c4c6785c9a12b6f0a988e0d41ec93b3b02086a, `GcFieldsTrace.tla`
  718cb0f23680c70837be85c53a9f9a5067cb9c9751df363ce5499a7b621c3baa.
