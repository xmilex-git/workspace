# StrShare — which string an assignment shares, and that the shared buffer outlives the record build (CUBRID/cubrid#8378, CBRD-27847)

Code: `~/dev/cubrid-worktree/PR-8378-rv` at `c45aac991` (`e97790141` + `91465a14a`, merged with develop `e98bdd885`).
The model covers the two engine commits: `heap_attrinfo_can_share_string ()` and the shared branch of
`heap_attrinfo_set_converted ()` (`src/storage/heap_file.c`). One `Assign` is one call for one attribute; one
row is the assignments of a row followed by the `Build` that reads them.

## Claim and sources

| # | Claim | Source |
|---|---|---|
| C1 | A value the attribute shares leaves the attribute the value the cast leaves: the same record bytes (codeset encoding, characters, padding) and the same domain (type, codeset, collation, precision as `tp_domain_resolve_value` reads it, length). | PR body TO-BE ("저장되는 바이트와 오류는 같다"); `heap_attrinfo_can_share_string` comment ("The cast would only copy such a value", "the value is of the attribute's domain - precision and collation, as the match heap_attrinfo_set tries first (TP_EXACT_MATCH)"); JIRA CBRD-27847 Expected Result 2 |
| C2 | A shared buffer stays as it is until the record is built: no holder releases it between the assignment and `locator_allocate_copy_area_by_attr_info`. With reevaluation off this holds for every holder; with it on, an owned reevaluated value is never shared (the clear in `locator_mvcc_reev_cond_assigns`). | `heap_attrinfo_set_converted` comment (`attr_val(in)`: "its buffer must stay as it is until the record is built"); `heap_attrinfo_can_share_string` comment ("A value that owns its buffer is cast into a copy: its holder may clear it before the record is written"); Codex thread 4463663921 and the author's reply 4476596452 (reevaluation disabled by `pt_to_update_xasl` / `pt_to_delete_xasl`) |
| C3 | The shared path fails exactly where the cast fails, with the same error: a value longer than the column fails, and no value the cast stores is refused. | PR body TO-BE ("오류는 같다"), Implementation ("넘치는 값은 지금처럼 캐스트가 오류를 냅니다", "최대를 넘는 선언 정밀도는 공유하지 않습니다(빌려 넣는 `setval` 이 거부합니다)"); JIRA Expected Result 2 |
| C4 | Every value of the column's type, codeset, collation and precision that fits the precision (a CHAR or BIT fills it) and owns no buffer is shared, an unset variable precision counting as the maximum. | PR body TO-BE ("정확히 같고, 길이가 정밀도 안에 들고, 버퍼를 소유하지 않는 값은 그 버퍼를 빌려 넣는다"), Implementation (정해지지 않은 정밀도는 최대값); JIRA Expected Result 1 (문자열 열 1개당 명령 기울기) |

## Refinement map (model -> code)

| Model | Code (`c45aac991`) | One step because |
|---|---|---|
| `Assign`, `AssignWith(v, d)` | `heap_file.c:heap_attrinfo_set_converted` (12948), called from `query_executor.c` UPDATE 16138/16143, ODKU 17763/17781, INSERT 19166/19352 and `locator_sr.c:locator_mvcc_reev_cond_assigns` 14352/14363 | runs in the statement's thread on its private `HEAP_CACHE_ATTRINFO`; no latch, lock or shared write |
| `v` (`t`, `pt`, `cs`, `co`, `p`, `len`, `wide`, `nc`) | `DB_VALUE_DOMAIN_TYPE (attr_val)`, `value_type`, `db_get_string_codeset/collation`, `db_value_precision`, `db_get_string_length` (characters; bits for a bit string), `db_get_string_size` (bytes; `wide` = more bytes than characters), `DB_NEED_CLEAR` | input class |
| `d` (`Cols`) | `value->last_attrepr->domain` (`catalog`): type, `TP_DOMAIN_CODESET`, `TP_DOMAIN_COLLATION`, `precision`; `ColPrecs` = a declared precision and the type's maximum (STRING) | input class |
| `Shares` | 12969-12972: `value_type == TP_DOMAIN_TYPE (catalog)`, `DB_VALUE_DOMAIN_TYPE (attr_val) == value_type`, then `heap_attrinfo_can_share_string` (the fixed-copy branch is out of the model) | pure test |
| `CanShareString` | `heap_attrinfo_can_share_string` (12888): `DB_NEED_CLEAR` 12893, codeset and collation 12899-12900, `precision` with the unset VARCHAR/VARBIT normalization 12907-12911, `!= domain->precision` 12913, CHAR/BIT `length == precision` 12923, VARCHAR `size <= precision` 12925, `length <= precision` 12929 | pure test |
| `Setval` | 12977 `pr_type->setval (&value->dbvalue, attr_val, false)`: the value as it is, refused with `ER_INVALID_PRECISION` above the maximum precision | one call |
| `Cast` | 12984 `tp_value_auto_cast_with_precision_check_converter` into `catalog`: codeset conversion, `DOMAIN_OVERFLOW` (-427) for a longer value, fixed-type padding with the codeset's pad character (`PadOf`: euckr 0xA1A1, binary 0x00, otherwise space) | one call |
| `Record`, `Runs`, `WriterPad` | `locator_allocate_copy_area_by_attr_info` -> `heap_attrinfo_transform_to_disk` -> `data_writeval`: the value's bytes, a fixed type shorter than the column padded with a space (zero bits) | — |
| `Build` | `locator_sr.c:locator_allocate_copy_area_by_attr_info` (7990), from `locator_attribute_info_force` 8206 and `qexec_oid_of_duplicate_key_update` (the ODKU key lookup) | reads the attribute values once, in the same thread |
| error ends the row | every caller `GOTO_EXIT_ON_ERROR` / `goto exit_on_error` on `rc != NO_ERROR`: the row is not built | — |
| `h = "tuple"` | UPDATE `vallist->val` / INSERT `insert->vals[k]` peeked from the select's list file tuple; the scan keeps the tuple until its next `qfile_scan_list_next`, after the force | holder is the statement's own scan |
| `h = "const"` | `assign->constant`, plan constants and host variables (`vd->dbval_ptr`): live for the XASL / query | — |
| `h = "odku"` | `qexec_execute_duplicate_key_update`: the old row read `COPY` into the scan cache area (`qexec_settle_on_duplicate` 17173), `heap_attrinfo_read_dbvalues` peeks it; the force gets `&rec_descriptor` (8130 `copy_recdes = *rec_descriptor`), so it does not reread into that area | `EarlyRelease` false unless `odku_reread` |
| `h = "reevExpr"`, `EarlyRelease` | `locator_mvcc_reev_cond_assigns` 14367-14370: `pr_clear_value (dbval)` right after the assignment when `need_clear` | reachable only with `ReevOn` |
| `h = "reevPage"`, `EarlyRelease` | `locator_mvcc_reeval_scan_filters` 14488 `heap_scancache_end (&local_scan_cache)` before the force builds the record (Codex thread) | reachable only with `ReevOn` |
| `ReevOn = FALSE` | `xasl_generation.c` 25899-25901 (`pt_to_delete_xasl`) and 26652-26654 (`pt_to_update_xasl`): "These two lines disable reevaluation"; MERGE locks at select (31185) | code fact |
| `uafOwned`, `uafPage`, `eqViol`, `errViol`, `shareViol`, `saw*` | ghosts | — |

## Properties

| Name | Kind | Statement | Claim |
|---|---|---|---|
| `TypeOK` | invariant | variable types | — |
| `SameValue` | invariant | `~eqViol` | C1 |
| `NoDangling` (`NoDanglingOwned /\ NoDanglingPage`) | invariant | no Build reads a released shared buffer | C2 |
| `SameError` | invariant | `~errViol` | C3 |
| `SharesExact` | invariant | `~shareViol` | C4 |
| `BorrowsInv` | invariant | a borrow released early belongs to a reevaluation (or the mutant) | C2 |
| `IndInv` | inductive invariant | no violation flag set; with reevaluation off no borrow is released early | C1-C4 |

## Fault model and environment assumptions

| Item | Modeled as |
|---|---|
| error return | modeled: the cast's overflow and the shared `setval`'s `ER_INVALID_PRECISION` end the row; a later failure (unique violation in the force) happens after `Build` read the values |
| interrupt / query cancel | not applicable: an interrupt raised between the assignment and the force returns an error and the row is not built (same as an error return) |
| lock timeout, deadlock victim | not applicable before `Build`: the ODKU row lock is taken in `qexec_settle_on_duplicate` before the old row is read; UPDATE rows are locked at select (`PT_SELECT_INFO_MVCC_LOCK_NEEDED`) |
| OOM | not applicable to C1-C4: `setval (copy=false)` allocates nothing; the cast's OOM is an error return |
| crash / `kill -9` | not applicable: nothing durable is written before `Build`; the attribute cache is process memory |
| spurious wakeup | not applicable: no wait |
| concurrent DML, vacuum | not applicable: the list file tuple and the ODKU old row are copies owned by this thread (list file page fixed by its scan, scan cache area private); the reevaluation that rereads a row is `ReevOn` |
| checkpoint, page flush | not applicable: a flush does not move a fixed page or a private area |
| HA log apply | not applicable: the applier writes through `locator_attribute_info_force` from its own attribute values (`heap_attrinfo_set`, not this function) |
| parallel query workers | not applicable: INSERT, UPDATE and MERGE assignments run in the statement's thread |
| MVCC reevaluation | modeled as the constant `ReevOn`; FALSE is the code (`pt_to_update_xasl`, `pt_to_delete_xasl`) |

No liveness claim: a run is at most `Rows` rows and ends in `Finished`.

## Mutants

| cfg | Change | Expected | Kills |
|---|---|---|---|
| `mutant-develop` | the merge-base: no string is shared | `SharesExact` violated (fail-before of the perf claim) | C4 |
| `mutant-no-codeset` | drop the codeset test (12899) | `SameValue` violated: an iso88591 value with a utf8 collation id shared into a utf8 column keeps its iso88591 bytes | C1 |
| `mutant-no-collation` | drop the collation test (12900) | `SameValue` violated: a utf8_en_ci value keeps its collation in a utf8_bin column | C1 |
| `mutant-no-precision` | drop `precision != domain->precision` (12913) | `SameValue` violated: the attribute keeps the value's precision | C1 |
| `mutant-over-as-max` | normalize an oversized variable precision to the maximum too | `SameError` violated: `setval` refuses (`ER_INVALID_PRECISION`) a value the cast stores | C3 |
| `mutant-char-any-len` | a CHAR / BIT shares at any length up to the precision (`<=` at 12923, the first commit's rule) | `SameValue` violated: a short euckr / binary CHAR is padded with spaces instead of 0xA1A1 / 0x00 | C1 |
| `mutant-trust-precision` | VARCHAR / VARBIT shared without the length test | `SameError` violated: a value longer than its precision is stored where the cast fails | C3 |
| `mutant-no-premise` | drop `DB_VALUE_DOMAIN_TYPE (attr_val) == value_type` (12971) | `SameValue` violated: a CHAR value the plan typed VARCHAR is shared into a VARCHAR column | C1 |
| `mutant-no-unset-norm` | no normalization of an unset precision (12908-12911) | `SharesExact` violated: an unset VARCHAR into STRING is cast | C4 |
| `mutant-size-only` | VARCHAR decided by its byte size only, no character count (12929 for VARCHAR) | `SharesExact` violated: a multibyte value within the precision is cast | C4 |
| `mutant-odku-reread` | the ODKU force rereads the old row into the scan cache area (no `rec_descriptor`) | `NoDangling` violated | C2 |
| `mutant-no-needclear` | drop `DB_NEED_CLEAR` (12893), reevaluation on | `NoDanglingOwned` violated: the owned reevaluated value is cleared before the build | C2 |

## Witnesses

| cfg | Reached state |
|---|---|
| `witness-char-count` | a VARCHAR whose byte size exceeds the precision is shared after the character count |
| `witness-nonspace-full` | a full euckr / binary CHAR is shared |
| `witness-cast-err` | a cast fails (a value longer than the column) |
| `witness-reev-page` | with reevaluation on, a non-owned value read through `locator_mvcc_reeval_scan_filters`'s local scan cache is shared and its page is unfixed before the build (the Codex path; unreachable with `ReevOn = FALSE`) |
| `StrShareTrace.witness-trace-tc` | the instrumented PR head's run of TC `cbrd_27847` is a behavior of the spec |
| `StrShareTrace.reject-flip-share` | the same run with event 76 (a full CHAR(10) shared, `sh=1`) flipped to `sh=0` is refused there |
| `StrShareTrace.reject-flip-error` | the same run with event 554 (the Case 5 VARCHAR(32) overflow, `er=1`) flipped to `er=0` is refused there |

## Trace validation

- Build: `~/optdebug/CUBRID-pr8378-tla`, optdebug, PR head `c45aac991` plus the review-only TLATRACE patch in the
  scratch worktree `~/dev/cubrid-worktree/PR-8378-rv` (`heap_tla_trace_assign` at the end of
  `heap_attrinfo_set_converted`, `heap_tla_trace_build` at the entry of `locator_allocate_copy_area_by_attr_info`,
  emitted only after an assignment of this thread); libcubrid `3466009e56aa3388`, libcubridsa `1fc1a4a83c6ff2db`.
- Run: SA mode (`csql -S`, DB `en_US.utf8`), the TC PR #4007 case `sql/_36_guava/cbrd_27847/cases/cbrd_27847.sql`
  (tc `c3c88d5ab`) as is: 600 events, 461 Assign (167 shared, 5 failed with the cast's -427 overflow), 139 Build;
  `traces/tc.log`. Every Assign the spec accepts is matched on its relations (types, codesets, collation equality,
  need_clear, precision classes, length and byte size against the column) and on the branch and error the spec
  computes.
- Covered by the run: shared VARCHAR, CHAR (utf8, euckr, binary), BIT, BIT VARYING; a VARCHAR shared after the
  character count (byte size over the precision); casts for need_clear values, another precision, collation
  (utf8_en_ci), codeset (iso88591 into utf8), type (VARCHAR into CHAR, VARBIT into BIT, BIT into VARBIT); overflow
  errors. Not in the run: an unset or oversized precision (`un=1`, `po=1`), the inconsistent codeset/collation pair,
  reevaluation (unreachable). Holder releases are not logged (the spec chooses the holder).

## Dead expressions (pass cfg)

`tla-check` reported no dead-expression lines for `StrShare.cfg`.

## Bounds and limits

- TLC: `MaxPrec = 3`, column precisions {2, 3}, value precisions 0..4 (0 = unset), lengths 0..4, `NCols = 2`, `Rows = 2`; scale `MaxPrec = 4`, `NCols = 3`, `Rows = 2`; `reev-on` as the main cfg with `ReevOn = TRUE`. Five codeset/collation pairs plus one inconsistent pair; CHAR, VARCHAR, BIT, BIT VARYING; a wide character takes 3 bytes (utf8 Hangul).
- Apalache: IndInv inductive for every `NCols` and `Rows` with `MaxPrec = 3` (value ranges need constant bounds).
- Not modeled: the fixed-copy branch (unchanged), cross-family values (a string into a bit column: the converter path, unchanged), codeset conversion failures, the cast's actual byte arithmetic (abstracted to codeset + character count + pad runs), LOB/collection types.
- The holder lifetimes (tuple, const, odku) are code facts read at `c45aac991`; the trace does not log releases.

## Counterexamples

| cfg | Trace | Class |
|---|---|---|
| `witness-reev-page` (expected) | `ReevOn = TRUE`: a reevaluated assignment reads a non-owned string through `locator_mvcc_reeval_scan_filters`'s local scan cache, the head shares it, `heap_scancache_end` unfixes the page, `Build` reads it | **Not reachable at `c45aac991`**: `pt_to_update_xasl` / `pt_to_delete_xasl` clear the reevaluation flags (code fact above); the author's reply 4476596452 records it and states the copy the path would need if reevaluation came back. The main cfg (`ReevOn = FALSE`) has no counterexample. |

No correct-variant cfg produced a counterexample.

## Observations (not findings)

- The `DB_NEED_CLEAR` guard (12893) is killed only with reevaluation on (`mutant-no-needclear` under `ReevOn = TRUE`); with
  it off, every owned value's holder (a decompressed list value, an expression result) keeps it past the build, so the
  guard protects the reevaluation path and keeps develop's copy of owned values. Its own comment says so.
- The codeset test (12899) is killed only by a value whose collation id belongs to another codeset (the model's
  inconsistent pair); for a value whose codeset is its collation's, the collation test alone decides.

## Result

- 2026-11-06, `tools/tla/tla-check --workers 8 .claude/review/PR-8378/tla/str-share`, toolchain
  `rr034sppv8gw9k63ppwwb5028rx2chmf-tla-tools`: `RESULT: OK`; run dir
  `.git_ignored_dir/scratch/tla/str-share-20261106-113209-3713579`.
- TLC (generated/distinct, depth): main 1814796/137 (7); scale `MaxPrec = 4, NCols = 3` 7030809/233 (9); `reev-on`
  3689888/367 (7); 12 mutants rejected — `SameValue`: char-any-len, no-codeset, no-collation, no-precision, no-premise;
  `SameError`: over-as-max, trust-precision; `SharesExact`: develop, no-unset-norm, size-only; `NoDangling`:
  odku-reread; `NoDanglingOwned`: no-needclear; 4 witnesses reached (cast-err, char-count, nonspace-full, reev-page).
- Apalache: `apalache-indinv` pass (IndInv inductive for every `NCols`, `Rows`, `MaxPrec = 3`); a scratch copy with
  `Mutant = "no_codeset"` in `CInit` fails it (`violation IndInv`), so the check is not vacuous.
- TLAPS: 요청 없음.
- Trace: `witness-trace-tc` accepted all 600 events (depth 601); `reject-flip-share` stops at event 76 (depth 76),
  `reject-flip-error` at event 554 (depth 554).
- Spec sha256: `StrShare.tla` a0e0f521949699016b675b3f4d8f3103931b578e778d550cd56f0b2decef321d,
  `StrShareTrace.tla` ea118f2fd7734d9304f828d38e7b70bff616916081c1d692523b96982476833f,
  `StrShareTraceData.tla` 7352ce0f37c2ba305e837512bcc0ec5298cbea02a9bfce842d7f28c6786a4f9a.
- Engine: `c45aac991` + TLATRACE patch, optdebug, libcubrid `3466009e56aa3388`, libcubridsa `1fc1a4a83c6ff2db`.
