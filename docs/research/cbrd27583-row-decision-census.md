# CBRD-27583 전수조사 — 행마다·스캔마다 타입을 정하는 자리 (기준: 8022 전 develop `be683e04c^`)

조사 방법: `be683e04c^` 의 서버 실행 코드(src/query, src/storage, src/sp, src/xasl, src/method, set_object.c)에서
타입·변환·비교 방법을 값으로 고르는 API 를 함수 단위로 모았다 — `tp_value_compare(_with_error)`, `db_value_compare`,
`tp_value_coerce(_strict)`, `tp_value_cast(_preserve_domain)`, `tp_value_auto_cast`, `tp_domain_resolve_value`,
`tp_more_general_type`, `tp_infer_common_domain`, `LANG_RT_COMMON_COLL`, `pr_type->cmpval`, `qdata_{add,subtract,multiply,divide}_dbval`,
`qdata_coerce_dbval_to_numeric`, 그리고 늦은 바인딩 표시 `DB_TYPE_VARIABLE`·`original_domain`·`is_domain_resolved`·
`(g_)agg_domains_resolved`·`is_first_exec_time`. 721 줄, 188 함수. 원자료: `.git_ignored_dir/scratch/census27583/byfunc.tsv`.
8022 감사표(`domain-pin-audit.md` S-01~S-43)와 함께 읽는다. 감사표 지점 중 이 API 패턴으로 잡히지 않는 것은 §11 에 따로 적었다.

처리 기호:
- **C** 컴파일이 정해 그 결정이 속한 develop 구조(비교 항·연산자 몸체·키 목록·집계 노드 등)에 싣는다. 행은 찾아 둔 변환기·비교 함수만 부른다.
- **S** 바인드·자동 파라미터 값의 변환: 클라이언트가 보내기 전에 기대 도메인으로 한 번, 두 도메인이 필요하면 파생 자리 (Q31, 2026-10-16 재결정: 서버 변환 없음).
- **D** 지운다: 타입 서명 플랜에서는 VARIABLE·LEAVE 가 생기지 않아 조건이 늘 거짓이다.
- **X** 범위 밖: DDL·카탈로그·통계·serial·트리거 — 질의 실행의 행 경로가 아니다.
- **E** 예외: 데이터 자체가 타입을 지닌다(플랜이 정할 수 없다).

## 1. 실행 중 플랜 도메인을 쓰고 되돌리는 자리 (늦은 바인딩) — 전부 D

| 지점 | 무엇을 | 언제 |
|---|---|---|
| fetch.c `fetch_peek_arith` | VARIABLE 결과 도메인을 값으로 정하고 `original_domain` 으로 되돌림, collation 재확정 | 행 |
| fetch.c `fetch_peek_dbval_slow` | VARIABLE regu 도메인 = `tp_domain_resolve_value` | 행 |
| query_executor.c `qexec_resolve_domains_on_sort_list` · `qexec_resolve_domains_for_group_by` | 정렬·GROUP BY 키 도메인을 첫 값으로 | 블록 실행 |
| query_executor.c `qexec_resolve_domains_for_aggregation` · `qexec_end_one_iteration` · `qexec_execute_mainblock_internal` (`agg_domains_resolved`) | 집계 피연산자·누산기 도메인을 첫 non-NULL 값으로 | 첫 행 |
| query_executor.c `resolve_domain:` 블록, query_analytic.cpp `qdata_evaluate_analytic_func` (VARIABLE ×12) · `qdata_analytic_is_plain_sum_avg`, xasl_analytic `is_first_exec_time` | 분석 함수 도메인·누산 타입을 파티션 첫 값으로 | 파티션 첫 행 |
| query_aggregate.cpp `qdata_update_agg_interpolation_func_value_and_domain`, query_opfunc.c `qdata_update_interpolation_func_value_and_domain` | MEDIAN/PERCENTILE 도메인을 첫 값 캐스케이드로 | 첫 값 |
| list_file.c `qfile_update_domains_on_type_list` · `qfile_unify_types` · `qfile_initialize_sort_key_info`, query_opfunc.c `qdata_generate_tuple_desc_unresolved/for_valptr_list`, qfile_tuple_layout.h `qfile_tuple_resolve_column` 외 (`is_domain_resolved`) | 리스트 파일 열 도메인을 첫 튜플로 | 첫 튜플 |
| scan_manager.c `resolve_domains_on_list_scan` | 리스트 스캔 열 도메인 | 스캔 open |
| query_executor.c `qexec_sync_start_with_type_list` | CONNECT BY 시작 리스트 타입 맞춤 | 블록 |
| query_executor.c `qexec_topn_cmpval` VARIABLE 분기 | top-N 키 도메인 폴백 | 행 |
| px_scan_result_handler.cpp (`is_domain_resolved`, `agg_domains_resolved`, 루트 역전파 L96·L722), px_scan.cpp L1733·L1985 | 병렬 워커의 도메인 확정과 리더 플랜으로 역전파 | 워커 첫 행 |
| query_executor.c `qexec_clear_{arith_list,regu_var,pos_desc,analytic_function_list,agg_list}`, xasl_spawner.cpp | `original_domain` 원복·복사 | clear |

## 2. 행마다 두 값의 타입으로 비교 방법을 고르는 자리

| 지점 | 무엇을 | 처리 | 결정을 싣는 곳 |
|---|---|---|---|
| query_evaluator.c `eval_value_rel_cmp` | `tp_more_general_type` + rhs 제자리 coerce + `tp_value_compare_with_error` | C | 비교 항(`comp_eval_term`, `alsm_eval_term`) |
| query_executor.c `qexec_cmp_tpl_vals_merge` | 머지 조인 열 쌍 비교 | C | 머지 정보(`ls_merge` 열 쌍) |
| query_executor.c `qexec_compare_valptr_with_tuple`, `qexec_groupby_index` | 정렬된 GROUP BY 키 경계 비교 | C | GROUP BY 키 목록 |
| query_executor.c `qexec_topn_cmpval` | top-N 정렬 키 비교 | C | top-N 정렬 항목 |
| query_aggregate.cpp `qdata_agg_hkey_compare` | 해시 GROUP BY 키 비교 | C | 해시 GROUP BY 키 목록 |
| query_hash_scan.c `qdata_hscan_key_compare` | 해시 리스트 스캔 키 비교 | C | 해시 스캔 키 목록 |
| query_hash_join.c `hjoin_fetch_key` | 해시 조인 키 비교 | C | 해시 조인 키 목록 |
| scan_manager.c `scan_key_compare` · `eliminate_duplicated_keys` | 키 범위 정렬·중복 제거 | C | 인덱스 키 목록 |
| btree.c `btree_compare_key` 폴백 | 도메인이 다른 키를 `tp_value_compare_with_error` 로 | C | 인덱스 키 목록(검색 키 비교 방법) |
| query_aggregate.cpp `qdata_aggregate_value_to_accumulator` MIN/MAX, `qdata_calculate_aggregate_cume_dist_percent_rank`, `qdata_evaluate_aggregate_hierarchy` | 누산기와 값 비교 | C | 집계 노드 |
| query_analytic.cpp `qdata_evaluate_analytic_func` MIN/MAX | 같음 | C | 분석 노드 |
| arithmetic.c `db_least_or_greatest`, `db_width_bucket_calculate_numeric` | LEAST/GREATEST·WIDTH_BUCKET 비교 | C | 연산자 몸체 |
| partition.c `partition_do_regu_variables_match` · `partition_prune_range` | 가지치기 값과 파티션 경계 비교 | C | 가지치기 정보(파티션 키 도메인 고정) |
| query_executor.c `qexec_check_limit_clause`, `qexec_get_orderbynum_upper_bound` | LIMIT·ORDERBY_NUM 상한 비교 | 실행당 1회 — 그대로 |
| px_scan_instnum.cpp L271·L280 | instnum 상한을 BIGINT 로 coerce·비교 | 실행당 1회 — 그대로 |
| set_object.c `col_value_compare`·`col_bsearch`·`col_find`·`setobj_*`(compare·union·difference·intersection·issome·ismember) | 컬렉션 원소 비교 | 상수 컬렉션(IN 목록): C, 원소 도메인이 정해진 컬렉션 열: C, 타입 없는 컬렉션 값: E | 비교 항의 원소 비교 |

## 3. 행마다 타입으로 연산 방법을 고르는 자리

| 지점 | 무엇을 | 처리 |
|---|---|---|
| query_opfunc.c `qdata_{add,subtract,multiply,divide}_dbval` 과 그 아래 타입쌍 함수 28개, `qdata_increment_dbval`, `qdata_coerce_dbval_to_numeric` | 두 값 타입으로 연산 고르기 | C: 연산자 몸체에 연산 종류(8022 `DOMAIN_ARITH`, `qdata_arith_dbval`)와 피연산자 변환기 |
| query_opfunc.c `qdata_strcat_dbval`, `qdata_concatenate_dbval` | `||`·CONCAT 의 값 타입 판정 | C |
| query_aggregate.cpp `qdata_aggregate_value_to_accumulator`·`qdata_aggregate_accumulator_to_accumulator`·`qdata_finalize_aggregate_list` (SUM/AVG/STDDEV/VARIANCE) | 누산·마무리의 타입 판정과 coerce | C: 집계 노드 |
| query_analytic.cpp `qdata_evaluate_analytic_func`·`qdata_finalize_analytic_func` | 같음 | C: 분석 노드 |
| query_executor.c `qexec_analytic_evaluate_offset_function` | LEAD/LAG offset·default coerce | C (+ S: 바인드 default) |
| list_file.c `qfile_compare_with_interpolation_domain` | 보간 정렬 비교마다 캐스트 | C |

## 4. 대상이 고정된 캐스트 (원 타입도 서명별 플랜에서 고정)

| 지점 | 대상 | 처리 |
|---|---|---|
| query_executor.c `qexec_execute_insert`·`qexec_generate_row_default_expr`, heap_file.c `heap_attrinfo_set` | 컬럼 도메인 | C: 대입 목록에 변환기 |
| query_opfunc.c `qdata_get_dbval_from_constant_regu_variable`, `qdata_cast_to_domain`, `qdata_coerce_result_to_domain` | 리스트 열·노드 결과 도메인 | C: 출력 목록·연산자 몸체 |
| fetch.c CAST·NVL·COALESCE·CASE·DECODE·IF 결과 캐스트 (`tp_value_cast` 계열) | 노드 도메인 | C (27583 C7 `domain_operand_cast_target`) |
| access_json_table.cpp L157·L187, scan_json_table.cpp | JSON_TABLE 열 도메인 | C (JSON 원소 쪽은 E) |
| partition.c `partition_prune_hash` · `partition_prune_for_function` | 파티션 키 도메인 | C |
| fetch.c `fetch_and_coerce_key_limit_lower`, scan_manager.c `scan_fetch_and_coerce_key_limit_upper` | 키 리밋 BIGINT | S(바인드) / C |
| query_executor.c `qexec_fill_sort_limit` · `qexec_setup_topn_proc` | LIMIT BIGINT | 실행당 1회 — 그대로 |
| query_hash_scan.c `qdata_copy_hscan_key(_without_alloc)`, query_hash_join.c `hjoin_init_domain_info`(`tp_more_general_type`) | 해시 키를 공통 도메인으로 | C: 키 목록에 공통 도메인과 쪽별 변환기 |
| set_object.c `assign_set_value`·`setobj_ismember` | 컬렉션 원소 도메인 | 원소 도메인이 있으면 C, 없으면 E |
| btree.c `btree_store_overflow_key` | 인덱스 키 도메인 | 원 타입 = 키 타입 — 그대로 |

## 5. 스캔 open 마다 값으로 정하는 자리

| 지점 | 무엇을 | 처리 |
|---|---|---|
| btree.c `btree_coerce_key` | 키 값을 strict 로 바꿔 보고 실패하면 그대로(KEEP) | C: 타입 쌍으로 정한다 — 모든 값이 손실 없이 바뀌는 쌍이면 검색 키를 바꾸고, 아니면(NUMERIC 검색 키 대 INT 인덱스) 공통 타입으로 비교하는 검색 키 비교를 컴파일이 고른다. 값에 따른 strict-or-keep 은 없앤다. 상관 키(외부 행마다 바뀌는 키)도 같은 규칙 |
| scan_manager.c `scan_dbvals_to_midxkey` | 다중 컬럼 키의 strict 시도와 섞인 setdomain | C: 같은 규칙을 컬럼마다 |
| btree.c `btree_range_opt_check_add_index_key` | MRO 키 도메인 | C |
| query_hash_join.c `hjoin_init_domain_info` | 조인 키 공통 타입 | C |

## 6. 행마다 collation 을 두 값으로 병합하는 자리 (`LANG_RT_COMMON_COLL`)

string_opfunc.c `db_string_compare`·`db_string_concatenate`·`db_string_instr`·`db_string_position`·`db_string_prefix_compare`·
`db_string_like`·`db_string_rlike`·`db_string_regexp_{count,instr,like,replace,substr}`·`db_string_replace`·`db_find_string_in_in_set`
(16곳), `tp_value_change_coll_and_codeset` 7곳. 서명별 플랜에서 두 피연산자의 collation 은 컴파일이 안다(바인드 collation 이 서명에 있다, Q25).
처리는 Q43 의 경계 결정에 따른다.

## 7. 함수 안의 타입별 구현과 값 내용 판정

- 수학·문자·날짜 함수 본문의 타입 switch(arithmetic.c `db_round_dbval`·`db_trunc_dbval`·`db_bit_count_dbval`·`db_width_bucket`,
  string_opfunc.c `db_unix_timestamp`·`db_time_format`·`get_date_time_info`·`db_ascii`·`db_value_to_enumeration_value` 등):
  입력 타입은 서명별 플랜에서 고정이다. 값 내용으로 목표 타입을 고르는 것(ROUND/TRUNC 의 문자열 인자, WIDTH_BUCKET, UNIX_TIMESTAMP, HEX, ASCII)은 함수의 사양이다 → Q43·Q44.

## 8. 외부가 타입을 정하는 값 — E

- DBLink 원격 결과(dblink_scan.c L1403 `tp_value_cast_preserve_domain`): 원격 드라이버가 행마다 타입을 준다. 로컬 열 도메인 쪽 변환기는 원격 열 타입을 컴파일이 알면 C.
- JSON 값 안의 스칼라, 타입 없는 컬렉션의 원소.
- SP(pl_executor.cpp L240~ `is_supported_type`): 인자 값 타입 검사는 서명별 플랜에서 컴파일로(C). 선언 타입으로의 변환은 PL 서버가 한다(엔진 밖). 반환 값을 regu 도메인으로 바꾸는 변환기는 C.

## 9. 범위 밖 — X

execute_statement.c(serial·auto_increment·trigger·savepoint·default 식), execute_schema.c(파티션 DDL), serial.c, catalog_class.c,
system_catalog.c, statistics_sr.c, heap_file.c `heap_object_upgrade_domain`(ALTER), btree.c 통계(`btree_get_subtree_stats`·`btree_get_stats_midxkey`),
method_callback.cpp·method_query_util.cpp(클라이언트 메서드), jsp_cl.cpp·pl_session.cpp(클라이언트).

## 10. 8022 에서 남기는 실행 부품

행에서 결정을 없애려면 "고른 것을 부르는" 부품이 있어야 한다. 이것들은 8022 에 이미 있고 측정 근거가 있다.

- 타입 쌍별 변환기 `object_domain_convert.cpp` 와 `tp_value_find_converter` — develop 의 `tp_value_cast_internal` 은 행마다 목표 타입 switch 와 원 타입 switch 를 두 번 탄다(cpp-perf-rules A61, BR-04 확장). 준비 단계에서 함수 포인터를 고정하는 것이 규칙의 처방이다(CLOW-14 단서).
- 타입 규칙 `domain_rules.c` — 컴파일로 옮겨 클라이언트·서버 공통.
- 산술의 계획된 연산 종류 `DOMAIN_ARITH`·`qdata_arith_dbval`(b3dca26dd) — 28개 `qdata_*_to_dbval` 디스패처를 대체했다.
- 비교의 연산자별 함수(`DOMAIN_COMPARE` 의 DIRECT 연산자 함수, #371 D3) — 측정: `SUM(c_int * ?) … GROUP BY` 실행당 −53.4M(#372).

지우는 것은 "언제 정하나" 층이다: 로드 도출(`domain_plan.c`), 실행 전 확정(`domain_resolve.c`), 실행 상태 표(`domain_state.h`),
그리고 행 코드가 그 표를 읽는 부분.

## 11. 감사표(S-01~S-43) 중 위 API 패턴 밖의 지점

| 감사표 | 무엇을 | 처리 |
|---|---|---|
| S-04 | NVL·COALESCE·NVL2·NULLIF·LEAST·GREATEST 두 값의 공통 타입 추론 (`fetch_peek_arith` 안) | C: 연산자 몸체 |
| S-06 | REGUVAL_LIST(VALUES 절) 행 도메인 | C |
| S-07 | 세션변수 읽기 `T_EVALUATE_VARIABLE` — 값의 타입이 행의 도메인 | 타입은 첫 SET 고정·서명(Q15·Q26)이라 C. 값 읽기만 행 |
| S-21 | CONNECT BY 프로브 NUMERIC precision/scale 보정 | C |
| S-31 | ISS `last_key` 도메인 | C |
| S-32 | MRO 정렬 열 `tp_Null_domain` 시딩 | C |
| S-33 | 키 리밋 NUMERIC assert | S/C (§4 키 리밋) |
| S-36 | PX 행당 누산기 폴백 | D |
| S-39 | 힙 전환(qe·qx 집계) | 도메인 결정 아님 — 확인만 |
| S-40 | `db_to_char` 결과 도메인(INSERT 기본식) | C |
| S-41 | PL/CSQL 정적 SQL 바인드 선언 타입 | 클라이언트(PL 컴파일) — 서명에 선언 타입이 들어간다 |
| S-42 | 필터·함수 인덱스 스트림 | C: DDL 컴파일이 정하고 스트림에 싣는다 |
| S-43 | `hostvar_late_binding` 파라미터 | 서명별 플랜에서는 의미가 없어진다 — 파라미터 처리는 Q 로 정한다 |

## 12. PR 8022 헤드(b3dca26dd)에 남아 있던 행 시점 타입 switch 7가지 (2026-10-16, 사용자 제공 목록)

| 남은 자리 | 처리 | 결정을 싣는 곳 |
|---|---|---|
| 산술 leaf 의 피연산자 타입 switch (`qdata_number_as_*`, NUMERIC·MONETARY 쪽 판정, DOUBLE 나눗셈 overflow 검사, 날짜 leaf 의 swap 과 타입 switch) | C | 연산자 노드: 피연산자 읽기 함수 2개 + leaf 함수 포인터 |
| `\|\|` 의 숫자 덧셈 (`qdata_strcat_dbval` 이 행마다 규칙을 읽음) | C | 연산자 노드(T_STRCAT 도 산술 결정을 가짐) |
| 출력 컬럼 값 캐스트 (`qdata_get_dbval_from_constant_regu_variable` 의 `tp_value_auto_cast`) | C | 출력 목록의 열마다 변환기 |
| 누산기 진입 fast path 의 값 타입 비교 (`SUM_ACC_IS_AGG_SUPPORTED_TYPE`, `sum_type_for`) | C | 집계·분석 노드: 누산 경로 고정 |
| OCTET/BIT/CHAR_LENGTH 의 인자 캐스트 | C | 연산자 노드의 피연산자 변환기 (`domain_operand_cast_target`) |
| collation 늦은 바인딩 노드의 VARCHAR/CHAR 변환기 선택 | D | 서명별 플랜에서 피연산자 타입이 고정이라 변환기가 하나 |
| `db_*` 함수 원시 연산 내부의 인자 타입 검사 | C (Q43) | 연산자·함수 노드가 타입별 구현을 가리킴 |

## 13. develop `b8199438e` CBRD-27215 (2026-10-16 머지) 가 더한 스텝 프로그램의 자리 — 구현자가 채운다

`expr_compile.c`(6250 줄) 와 `fetch_arith_ops.c`(5640 줄, `fetch_peek_arith` 본문 이동) 는 이 전수조사의 기준(`be683e04c^`) 뒤에 들어와 §1~§12 에 없다.
실측(b8199438e, `tp_value_cast|tp_value_auto_cast|tp_value_coerce|tp_value_compare|tp_more_general_type` 호출 줄): `expr_compile.c` 13, `fetch_arith_ops.c` 23.
8022 층을 읽는 자리 16 곳(`expr_prog_signature_matches`, `expr_item_resolution`, `expr_arith_exec_domain`, `expr_regu_exec_domain` 의 `qexec_get/set_node_domain`, `expr_pos_value_index`, `fetch_arith_ops.c` 의 `qexec_get_node_domain` 3 곳)은 전부 **D** 다
(플랜 하나가 서명 하나, 바인드는 컴파일된 도메인으로 도착, `vd->dbval_ptr` 는 const). 처리는 design.md 4.10.
`fetch_arith_ops.c` 로 옮겨간 `fetch_peek_arith` 본문의 자리는 §2~§3 의 `fetch.c` 행이 그대로 적용된다(함수 이름이 같다).

채운 날 2026-10-16 (구현자, 브랜치 CBRD-27583-impl, develop `3beb7654b`). 줄 번호는 그 develop 기준. 타입이 서명별 플랜에서 고정이므로
아래 tp_* 호출은 전부 원 타입·목표 타입이 컴파일에 알려진 변환·비교다 — **E** 는 없다. 프로그램 번역은 노드의 결정 필드에서 변환기·비교 함수를
가져오고(design 4.10), 해석기(`fetch_arith_ops.c`)와 같은 필드를 읽는다.

### 13-1. `tp_*` 호출 (expr_compile.c 13, fetch_arith_ops.c 23)

| 지점 | 호출 | 무엇을 | 처리 | 결정을 싣는 곳 |
|---|---|---|---|---|
| expr_compile.c:290 `expr_coerce_result_to_domain` | `tp_value_coerce` | 커널 결과를 노드 도메인으로 (`qdata_coerce_result_to_domain` 거울) | C | 연산자 노드의 결과 변환기 (4.2, 4.6 `qdata_coerce_result_to_domain` 과 같은 필드) |
| expr_compile.c:674 `expr_k_cast` | `tp_value_cast_force` | CAST/CAST_WRAP 를 고정 목표로 | C | CAST 노드의 변환기 (4.2 `domain_operand_cast_target`) |
| expr_compile.c:690 `expr_k_cast_strict` | `tp_value_cast` | STRICT CAST_WRAP | C | 같음 (엄격 모드 변환기) |
| expr_compile.c:820 `expr_k_nullif` | `tp_value_compare_with_error` | NULLIF 의 두 값 비교 | C | NULLIF 노드의 비교 결정 (4.1 과 같은 `DOMAIN_COMPARE`) |
| expr_compile.c:829 `expr_k_nullif` | `tp_value_cast` | 왼쪽 값을 결과 도메인으로 | C | NULLIF 노드의 가지 변환기 (4.2) |
| expr_compile.c:939 `expr_pred_generic_cmp` | `tp_value_compare_with_error` | fast_type 이 없는 비교의 일반 경로 | C | 비교 항 `compare` (4.1): 결정된 항은 연산자별 함수, 일반 경로 없음 |
| expr_compile.c:1062 `expr_pred_eval` | `tp_value_compare_with_error` | CASE/IF 술어의 비교 | C | 같음 (4.1) |
| expr_compile.c:1082 `expr_pred_eval` | `tp_value_compare_with_error` | 같음(다른 연산자) | C | 같음 (4.1) |
| expr_compile.c:1336 `expr_k_case_pub_cast` | `tp_value_auto_cast` | CASE 가지 값을 CASE 도메인으로 | C | CASE 노드의 가지 변환기 (4.2) |
| expr_compile.c:1377 `expr_k_predicate_cast` | `tp_value_auto_cast` | 술어 결과(정수)를 노드 도메인으로 | C | 연산자 노드의 결과 변환기 (4.2) |
| expr_compile.c:2937 `expr_scan_pred_build` | `tp_more_general_type` | 숫자 상수 쪽을 더 일반 타입으로 고정할지 | C | 비교 항 `cmp_target` (4.1): 어느 쪽을 바꾸는지는 항이 안다 — 번역은 결정 없이 항의 변환기로 상수를 한 번 바꾼다(평가) |
| expr_compile.c:2945 `expr_scan_pred_build` | `tp_value_coerce` | 그 상수 변환 | C | 같음 (항의 변환기) |
| expr_compile.c:3670 `expr_compile_pred_impl` | (fast_type = UNKNOWN → `tp_value_compare_with_error`) | 직접 비교 타입이 없으면 일반 비교 | C | 비교 항 `compare` 의 직접 비교 타입 (4.1) |
| fetch_arith_ops.c:112 `fetch_session_read_value` | `tp_value_cast` | 세션변수 값의 타입 검사(8022 -1384) | D | 세션변수 타입은 첫 SET 고정·키에 있음 (4.8) — 함수째 삭제 |
| fetch_arith_ops.c:301 `fetch_cast_operand` | `tp_value_cast_with_converter` | CAST 피연산자를 결정된 변환기로 | C | CAST 노드의 변환기 (4.2) — 지금은 8022 표에서 찾음 |
| fetch_arith_ops.c:311 `fetch_cast_operand` | `tp_value_cast_with_converter` | 같음(값 타입으로 찾기) | C | 같음 |
| fetch_arith_ops.c:315 `fetch_cast_operand` | `tp_value_cast`/`tp_value_cast_force` | 결정 없는 CAST 의 폴백 | C | 같음 — 폴백 삭제 |
| fetch_arith_ops.c:1464 `fetch_op_octet_length` | `tp_value_cast` | 인자를 VARBIT 로 | C | 연산자 노드의 피연산자 변환기 (§12 OCTET/BIT/CHAR_LENGTH) |
| fetch_arith_ops.c:1480 `fetch_op_octet_length` | `tp_value_cast` | 인자를 CHAR 로 | C | 같음 |
| fetch_arith_ops.c:1523 `fetch_op_bit_length` | `tp_value_cast` | 인자를 VARBIT 로 | C | 같음 |
| fetch_arith_ops.c:1540 `fetch_op_bit_length` | `tp_value_cast` | 인자를 CHAR 로 | C | 같음 |
| fetch_arith_ops.c:3184 `fetch_op_to_date` | `tp_value_cast` | 왼쪽 인자를 CHAR 로 | C | 연산자 노드의 피연산자 변환기 (4.2) |
| fetch_arith_ops.c:3225 `fetch_op_to_time` | `tp_value_cast` | 같음 | C | 같음 |
| fetch_arith_ops.c:3269 `fetch_op_to_timestamp` | `tp_value_cast` | 같음 | C | 같음 |
| fetch_arith_ops.c:3314 `fetch_op_to_datetime` | `tp_value_cast` | 같음 | C | 같음 |
| fetch_arith_ops.c:3562 `fetch_op_case` | `tp_value_auto_cast` | 고른 가지 값을 CASE 도메인으로 | C | CASE 노드의 가지 변환기 (4.2) |
| fetch_arith_ops.c:3607 `fetch_op_predicate` | `tp_value_auto_cast` | 술어 결과를 노드 도메인으로 | C | 결과 변환기 (4.2) |
| fetch_arith_ops.c:3802 `fetch_op_concat` | `tp_value_auto_cast` | 피연산자를 CONCAT 도메인으로 | C | 피연산자 변환기 (4.2) |
| fetch_arith_ops.c:3837 `fetch_op_concat_ws` | `tp_value_auto_cast` | 구분자를 도메인으로 | C | 같음 |
| fetch_arith_ops.c:3846 `fetch_op_concat_ws` | `tp_value_auto_cast` | 피연산자를 도메인으로 | C | 같음 |
| fetch_arith_ops.c:3878 `fetch_op_concat_ws` | `tp_value_auto_cast` | 같음(다른 갈래) | C | 같음 |
| fetch_arith_ops.c:4033 `fetch_op_left` | `tp_value_auto_cast` | 길이 인자를 INTEGER 로 | C | 피연산자 변환기 (4.2) |
| fetch_arith_ops.c:4089 `fetch_op_right` | `tp_value_auto_cast` | 같음 | C | 같음 |
| fetch_arith_ops.c:4404 `fetch_op_nullif` | `tp_value_cast` | 왼쪽 값을 결과 도메인으로 | C | NULLIF 노드의 가지 변환기 (4.2, §11 S-04) |
| fetch_arith_ops.c:4468 `fetch_op_least` | `tp_value_cast` | 결과를 공통 도메인으로 | C | LEAST 노드의 공통 도메인·가지 변환기 (§11 S-04) |
| fetch_arith_ops.c:4514 `fetch_op_greatest` | `tp_value_cast` | 같음 | C | GREATEST 노드 (§11 S-04) |
| fetch_arith_ops.c:4540 `fetch_op_sys_connect_by_path` | `tp_value_auto_cast` | 경로 결과를 노드 도메인으로 | C | 결과 변환기 (4.2) |

### 13-2. 8022 층을 읽는 자리 — 전부 D (design 4.10)

| 지점 | 무엇을 | 처리 |
|---|---|---|
| expr_compile.c `EXPR_PROG.hv_types`·`n_hv`, `expr_prog_signature_matches`, `expr_prog_signature_ok`·`expr_scan_pred_signature_ok` 의 타입 검사·재번역 | 프로그램의 바인드 타입 서명 | D: 플랜 하나 = 서명 하나 |
| expr_compile.c `expr_item_resolution`, `expr_arith_exec_domain`, `expr_arith_number_plan` 의 `plan_item->fixed` / 해결 표 | 숫자 커널 선택·노드 도메인 | D → 연산자 노드 `DOMAIN_ARITH` (4.2) |
| expr_compile.c `expr_regu_exec_domain` (`qexec_get_node_domain`/`qexec_set_node_domain`) | 소비자가 읽는 노드 도메인 | D → `regu->domain` |
| expr_compile.c `expr_pos_value_index` | resolve_domains 의 바인드 변환 사본 | D → `regu->value.val_pos` (`vd->dbval_ptr` const) |
| expr_compile.c `DOMAIN_PLAN_LATE_BIND(_COLLATION/_COERCION)` 검사 4곳, `DOMAIN_PLAN_ITEM_COMPARES` 2곳 | 늦은 바인딩 노드 거절 | D: 서명별 플랜에 없다 |
| fetch_arith_ops.c `qexec_get_node_domain` 3곳, `qexec_late_bind_domain` 5곳, `plan_item` 읽기 | 피연산자 도메인·해결 | D → 피연산자 regu 도메인 |
| fetch.c (7658) `fetch_arith_constant_evaluated`, `fetch_arith_resolved_domain` 호출과 `qexec_set_node_domain` | 상수 선평가·노드 도메인 기록 | D (§8 fetch.c 행) |

### 13-3. 7658 의 다른 소비자

| 지점 | 무엇을 | 처리 |
|---|---|---|
| query_aggregate.cpp (7658) `qexec_accumulator_domain (vd, plan_item)` 비교 | SUM/AVG 누산기 공유 판정 | C → 집계 노드의 누산 도메인 (4.3) |
| query_aggregate.cpp:`expr_prog_signature_ok` 호출 | 피연산자 프로그램 서명 검사 | D |
| px_scan_result_handler.cpp:`expr_prog_signature_ok` 호출 (BUILDVALUE_OPT) | 같음 | D |
| query_opfunc.c (7658) `qexec_get_node_domain`·`expr_regu_exec_domain`·`qexec_consumer_domain` | 프로그램이 내놓은 노드의 소비자 도메인 | D → `regu->domain` |
| query_opfunc.c / query_evaluator.c `expr_prog_signature_ok`·`expr_scan_pred_signature_ok` 호출 | 서명 검사 | D |
| query_executor.c 주석(서명 재검사) | — | 문구 정리 |
| heap_file.c (7658) | 투영 프로그램 호출부 — 8022 층 읽기 없음 | 그대로 |
