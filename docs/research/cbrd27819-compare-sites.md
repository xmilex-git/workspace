# 비교값이 닿아야 하는 자리 전수 census (workspace #565, 지도 #562)

2026-10-30. 질문: 비교값(ADR 0037 — BIGINT/NUMERIC × DOUBLE/FLOAT 은 DOUBLE/FLOAT 쪽의 가장 짧은 왕복 십진수로 정확히 판정)이 닿아야 하는 코드 자리는 어디이고, 자리마다 지금 공통 타입을 어떻게 정하며, 어디서(클라이언트/서버/XASL) 결정되고, 바꿔야 하는가. 다음 티켓(디스패치 설계 #567)이 이 표를 전제로 한다.

- 기준: develop `7b7e84d25`(2026-10-30, a199916d4 이후), 조사용 worktree `~/dev/cubrid-worktree/CBRD-27819-census`. 줄 번호는 이 HEAD 기준.
- 방법: `tools/code-index/code-index` 의 `callers` 로 두 비교 커널과 그 결정 함수 23개의 호출 자리 전수(산출 `.git_ignored_dir/scratch/cbrd27819/565/callers.txt`, 177줄), 비교 방식(`DOMAIN_COMPARE_DIRECT/CONVERT`)·conv 유무로 분기하는 자리는 rg 로 전수. 실측은 SA smoke 4회(`tools/fast-gate/fast-sa.sh`, install `~/optdebug/CUBRID-cbrd27819-s1c` — survey 브랜치 빌드, 환경 변수 게이트 꺼짐; 이 표의 파일들은 develop HEAD 와 `domain_key_values_equal`(CBRD-27804) 15줄만 다르다). 프로브·출력: `.git_ignored_dir/scratch/cbrd27819/565/smoke/{p1,p2,p3,p4}.sql`, `out/s1c.p{1,2,3,4}.out`.
- SA 와 CS 의 결정 전달은 같다: SA 도 XASL 을 `xts_*` 로 직렬화하고 `stx_*` 로 푼다. CS 에서만 도는 것은 병렬 경로(병렬 해시 조인·병렬 merge join·px_scan)이고, 아래 표에 따로 적었다.

## 1. 결론

1. **비교 결정은 커널 두 개에 모여 있다.** (K1) `domain_compute_comparison` (`src/query/domain_rules.c:2298`) — 컴파일러가 XASL 에 싣는 `DOMAIN_COMPARE` 와 서버의 타입 쌍 비교표의 원천. (K2) `tp_value_compare_with_error` (`src/object/object_domain.c:6536`) — 행 시점에 값의 타입을 보고 정하는 비교. 둘 다 `tp_value_compare_common_domain` (`object_domain.c:6338`) → `tp_more_general_type` (`:6305`, 순위표 `db_type_rank` `:110`)으로 BIGINT/NUMERIC × DOUBLE 은 DOUBLE, × FLOAT 은 FLOAT 로 변환해 그 타입의 cmpval 로 비교한다. 순위표는 결과 타입(`tp_infer_common_domain` `:7667`)·해시 키 도메인에도 쓰이므로 **순위표가 아니라 두 커널에서 이 쌍을 가로채야** 산술·집계 결과 타입 불변(ADR 0037)이 지켜진다.
2. **두 커널을 바꾸면 그대로 따라오는 자리**(표 3.2): 술어 항, CASE/DECODE/IF, IN 리스트·SOME/ALL·IN 서브쿼리(세미 조인), MERGE ON, 정렬 병합 조인, B-tree 경계 비교, 다중 키 정렬·중복 제거·병합(27797), RANGE/LIST 파티션 가지치기, 바인드 타입 결정·플랜 캐시, 컬렉션·JSON 원소, 옵티마이저·클라이언트의 상수 비교. 단 **"따라온다"는 새 비교가 `conv[0] = conv[1] = NULL`(어느 쪽도 변환하지 않음)로 표현될 때만** 성립한다 — 소비자 넷이 conv 유무로 분기한다(`pt_bind_comparison_target`, `domain_key_compare_merges`, `pt_comparison_keeps_key`, `expr_compile` 의 리터럴 고정).
3. **커널을 거치지 않아 따로 바꿔야 하는 자리**(표 3.3): (a) NULLIF 의 클라이언트 강제 공통 타입 CAST — 답이 바뀐다; (a') 동등 항 축약(`qo_reduce_equality_terms`)이 NUMERIC 열의 DOUBLE 상수를 16자리로 잘라 다른 쓰임에 복사 — develop 에서도 틀린 답; (b) 해시 조인의 키 도메인(DOUBLE)과 해시 일치 뒤 재검사(변환된 DOUBLE 끼리 비교) — 답이 바뀐다; (c) 해시 리스트 스캔의 NUMERIC × DOUBLE 키 도메인 — 엔진 NUMERIC→DOUBLE 변환의 2 ulp 오차(#563)로 같은 값이 다른 해시가 되어 행이 빠질 수 있다; (d) XASL 직렬화의 비교 표현(`xts_pack_decided_compare`/`stx_unpack_decided_compare`)과 cmp 재유도(`domain_compare_mirror`); (e) 구현 형태에 따라: 병렬 merge join 적격 판정, B-tree 의 DIRECT 빠른 경로, DIRECT 연산자 함수표, 범위 확장(`merges`)의 NUMERIC × DOUBLE 분기 정리.
4. **해시 재검사(확정, 코드)**: 해시 조인은 해시 일치 뒤 build 쪽 키를 다시 읽어 probe 키와 비교한다(`query_hash_join.c:2849`, 병렬 해시 조인도 같은 `hjoin_fetch_key`). 그러나 비교 대상은 **공통 도메인(DOUBLE)으로 변환된 값**이고 비교도 그 도메인의 DIRECT 비교라(`domain_decide_hash_join_key` → `domain_resolve_comparison_uncoerced`), 원래 술어로는 다시 보지 않는다 — 조인 항은 hash_terms 로 빠져 during/after-join 술어에 남지 않는다(`plan_generation.c` `make_hashjoin_proc`). 해시 리스트 스캔은 해시 일치 뒤 **원래 술어 전체를 다시 평가**한다(`scan_manager.c:8138`; 키 목록은 `pt_split_hash_attrs` 가 술어를 복사해 만든다, `xasl_generation.c:3025`). 해시 GROUP BY 는 한 열의 키가 한 도메인이라 섞인 비교가 없다.
5. **develop 실측 — 같은 질의가 경로마다 답이 다르다**(표 4). 단일 열 인덱스·NL·해시·병합 조인은 DOUBLE 로 같은 두 행을 돌려주는데, 다중 열 인덱스·다중 키 병합·RANGE/HASH 파티션 가지치기·LIST 파티션은 그중 일부만 돌려준다. 비교값 규칙에서는 모든 경로의 답이 하나로 모인다.

## 2. 두 커널

| 커널 | 자리 | 지금 하는 일 (BIGINT/NUMERIC × DOUBLE/FLOAT) | 결정되는 곳 | 비교값 적용에 필요한 데이터 |
|---|---|---|---|---|
| K0 공통 타입 규칙 | `object_domain.c:6338` `tp_value_compare_common_domain`, `:6305` `tp_more_general_type`, `:110` `db_type_rank` | 순위 NUMERIC(4) < FLOAT(5) < DOUBLE(6): BIGINT/NUMERIC 쪽을 FLOAT/DOUBLE 로 (`SECOND_TO_FIRST`/`FIRST_TO_SECOND`). 문자열 × 수는 `TO_DOUBLE` | 공용(cs/sa/server) | 두 타입 |
| K1 미리 결정 | `domain_rules.c:2298-2418` `domain_compute_comparison` (분기 `:2327`), 표 `domain_key_pairs_make` `:2565`, 진입 `domain_resolve_comparison` `:2803`·`domain_decide_comparison` `:2742` | conv = BIGINT/NUMERIC 쪽을 DOUBLE(FLOAT) 기본 도메인으로, `cmp = pr_type_from_id(DOUBLE)`, method CONVERT | 클라이언트(xasl_generation·xts) 가 결정해 XASL 에 싣고, 서버는 stream index·해시 조인 fallback·타입 쌍 표에서 같은 함수로 다시 결정 | **두 값의 타입(DB_TYPE)만**. NUMERIC 의 정밀도·scale 은 값이 지니므로 도메인 불필요 |
| K2 행 시점 | `object_domain.c:6536` `tp_value_compare_with_error` (변환 `:6644`~) | 같은 규칙을 행마다 `tp_value_coerce` 로 | 공용 | 두 값 |

`domain_resolve_compare` (`domain_rules.c:1108`, `DOMAIN_CTX_COMPARE`)도 같은 규칙을 갖지만 호출 경로가 없다: `domain_resolve` 의 호출자 6곳은 `domain_late_bind_context` 등으로 COMPARE 를 넘기지 않고 rg 로도 `DOMAIN_CTX_COMPARE` 의 외부 사용은 0. 바꿀 때 맞추거나 지운다.

## 3. 자리 표

열: **결정** = 결정이 내려지는 곳(C 클라이언트 컴파일, X XASL 에 실려 서버가 풂, S 서버 행 시점). **데이터** = 비교값 적용에 필요한 것. **변경** = 예 / 아니오 / 따라옴(커널을 바꾸면 자동) / 확인 필요.

### 3.1 전달·표현

| 자리 | file:line | 지금 | 결정 | 데이터 | 변경 | 근거 |
|---|---|---|---|---|---|---|
| 비교 직렬화 | `xasl_to_stream.c:7429` `xts_pack_decided_compare` (+ sizeof) | method 8비트, coercion, first, converts, source[2], converted_first, rank, collation, codeset_side, conv 가 있으면 target 도메인 | C→X | 새 비교의 표현(새 method 값 또는 플래그)과 두 source 타입 | 예 | 새 비교를 실을 칸이 필요 |
| 비교 풀기 | `stream_to_xasl.c:1888` `stx_unpack_decided_compare` (cmp 재유도 `:1919-1923`), `:1933` `stx_unpack_compare` | cmp 를 `pr_type_from_id(target 또는 source[0])` 로 다시 만든다 | X→S | 두 source 타입 | 예 | survey S1-2 가 바로 이 줄을 바꿨다 |
| 거울 비교 | `domain_rules.c:2239` `domain_compare_mirror` (호출 `stream_to_xasl.c:6059`, `xasl_generation.c:14619`) | 양쪽을 바꾸고 cmp 를 `pr_type_from_id` 로 다시 만든다 | C, X | 두 source 타입 | 예 | 인덱스 키가 왼쪽인 B-tree 비교가 이것을 쓴다 |
| 연산자 함수표 | `query_evaluator.c:640-650` `eval_Direct_operator_functions`, `domain_compare_set_operator_functions` | DIRECT 이면 연산자별 함수, 아니면 `eval_value_rel_cmp` | X→S | method | 구현 형태에 따라 | 새 method 면 표에 없음(느린 경로로 정확), DIRECT+전용 cmpval 이면 그대로 |
| 행 비교 스위치 | `query_evaluator.c:270` `eval_compare_resolved`, `domain_rules.c:1926` `domain_compare_values`, `:3028` `domain_compare_decided` | method 로 분기 | S | method | 구현 형태에 따라 | 새 method 면 세 스위치에 경우 추가 |

### 3.2 커널을 따라오는 자리

| 자리 | file:line | 지금 공통 타입 | 결정 | 데이터 | 변경 | 근거·실측 |
|---|---|---|---|---|---|---|
| 술어 항 (`=`, `<`, …) | `stream_to_xasl.c:5349` `stx_build_term_compare` → `eval_compare_resolved` | K1 | X | 두 타입 | 따라옴 | Q05 `b = d`, Q06 `n = d`: 1행(DOUBLE 로 같음) |
| 식 컴파일러의 리터럴 고정 | `expr_compile.c:2773-2782` (`expr_scan_pred_build` `:2694`) | 비교가 오른쪽 리터럴만 왼쪽 타입으로 바꾸면(conv[1]) 한 번 바꿔 고정하고 같은 타입 빠른 비교 | S(unpack 뒤) | conv 유무 | 따라옴(성능 확인 필요) | 새 비교가 conv 없음이면 고정이 꺼지고 일반 경로로 정확; DOUBLE 열 × BIGINT 리터럴의 빠른 경로가 사라짐 → #567·#572 |
| CASE / DECODE / IF | `xasl_generation.c:11438`, `:11463`, `:10408` (pred 를 `pt_to_pred_expr` 로) | 술어 항 | X | 두 타입 | 따라옴 | Q08·Q09 `case b when 2^53e0`: 두 행 'Y'; R15 searched CASE |
| BETWEEN | 술어 범위(`t.b>=? and t.b<=?`) | 술어 항 | X | 두 타입 | 따라옴 | S01·S02·S07: 비교 피연산자에 CAST 없음 (`pt_is_op_with_forced_common_type` 에 BETWEEN 이 있으나 비교 피연산자에는 CAST 가 붙지 않음) |
| IN 상수 리스트 | `query_evaluator.c:259` `eval_element_compare`, `stream_to_xasl.c:5522` `stx_constant_elements_compare`, `:5556`·`:5582` `stx_build_element_compares` | 타입 쌍 표(K1 셀) | X | 항목 타입 × 원소 타입 | 따라옴 | R06 `b+0 in (2^53e0, 1e0)`: 두 행 |
| SOME/ALL, IN 서브쿼리 | ALSM 항 / 세미 조인 재작성 | 술어 항·조인 항 | X | 두 타입 | 따라옴 | Q18·R07 세미 조인, R08 `>= all` |
| MERGE ON | 조인 항 | 술어 항 | X | 두 타입 | 따라옴 | R18: 두 행 'hit' |
| 정렬 병합 조인 | `stream_to_xasl.c:3784-3800` (merge_compares), 각 입력은 자기 도메인으로 정렬 | K1 | X | 두 열 타입 | 따라옴 | 가장 짧은 십진수는 d 에 단조 증가라 양쪽 정렬 순서와 섞인 비교가 일관. Q13 |
| 병렬 merge join | `px_merge_join_partition.cpp:67` 적격(DIRECT·coercion 1 만), `:147` `cmp_keys` → `tp_value_compare` | K1 판정 + K2 | S(CS 전용) | method | 구현 형태에 따라 | 새 method 면 병렬 꺼짐(정확, 느림); DIRECT+cmpval 이면 `cmp_keys` 가 K2 를 따라감 |
| B-tree 경계 비교 | `btree.c:23627` (`btree_compare_bound_key`), DIRECT 는 `cmp->cmpval` 직접 | K1 (DOMAIN_KEY_BOUND.compares) | X | 두 타입 | 따라옴(빠른 경로는 구현 형태에 따라) | Q01 단일 열 인덱스: 두 행 |
| 키 비교 결정 | `xasl_generation.c:14374` `pt_decide_key_compare`, `:14451` `pt_decide_key_compares` | K1 | C | 경계 도메인 × 인덱스 열 도메인 | 따라옴 | |
| 키 원소 규칙 | `domain_rules.c:2195` `domain_key_rule`, `:2168` `domain_key_converts_losslessly` (호출 `xasl_generation.c:14179` `pt_decide_key_element`) | BIGINT/NUMERIC/DOUBLE 사이는 KEEP(자기 도메인으로 두고 결정된 비교로) | C | 경계 도메인 × 인덱스 열 도메인, 연산자(올림·내림 방향) | **예** (#566) | #566 결정 1: 비교값 v(d) 를 키 도메인으로 올림·내림해 경계로 쓴다(정수 아닌 값과의 `=` 는 빈 범위, 도메인 밖은 빈 범위·전체 범위). 지금의 KEEP 은 그 변환이 없다 |
| 범위 확장 `merges` (CBRD-27583 사양 14) | `domain_rules.c:2212-2236` `domain_key_compare_merges` (호출 `xasl_generation.c:14628`; 사용 `btree.c:5439`, `:5768`, `:5845`, `:5860`, `:20408`) | 인덱스 쪽이 변환되면(BIGINT→DOUBLE) 같은 키가 여럿이므로 경계에서 같은 키 끝까지 이동; NUMERIC × DOUBLE 은 precision > 15 일 때 | C→X | conv[1]·target | 따라옴 + 정리 | 새 비교가 conv 없음이면 `:2226` 에서 false → 확장 꺼짐(원하는 결과). `:2229-2233` NUMERIC×DOUBLE 분기와 `domain_rules.h:586` 주석은 죽음 → 지움 (ADR 0037 "사양 14 의 범위 확장은 이 규칙으로 대체") |
| 다중 키 정렬·중복 제거·병합 (27797) | `scan_manager.c:1107` `scan_key_compare`, `:1248` `eliminate_duplicated_keys`, `:1284` `merge_key_ranges`, `:1410` `check_key_vals` → `domain_rules.c:3062` `domain_key_ranges_element_compare` | DOMAIN_KEY_RANGES 표(K1 셀) | X | 경계 도메인 class 쌍 | 따라옴 | R11 `b = 9007199254740992 or b = 2^53e0`: id 2 만(DOUBLE 로 같은 id 1 이 병합에서 빠짐), Q21 `in (…993, 2^53e0)`: id 1 만 |
| RANGE/LIST 파티션 가지치기 | `partition.c:1708` `partition_compare_key` → 항의 결정 비교 | 술어 항 | X | 항의 비교 | 따라옴 | Q15 RANGE: …993 만(2^53 로 같은 …992 가 든 p0 을 버림), Q16 LIST: …992 만 |
| 파티션 키 타입 | `semantic_check.c:6250` 목록 | 정수·날짜·문자만 (NUMERIC/DOUBLE/FLOAT 키 불가) | C | — | — | 섞인 비교는 BIGINT 키 × DOUBLE/FLOAT 값뿐 |
| 바인드 타입 결정 | `type_checking.c:4601` `pt_bind_comparison_target`, `:4673` `pt_typed_bind_comparison` | K1: 바인드 쪽에 conv 가 있으면 클라이언트가 그 타입으로 rule cast(파생 위치) | C | 바인드 값 도메인 × 짝 도메인 | 따라옴 | R17 DOUBLE 열 = BIGINT 바인드 …993: 클라이언트가 DOUBLE 로 캐스트해 1행. 새 비교가 conv 없음이면 rule cast 가 사라짐 |
| 플랜 캐시 | 바인드 타입 서명 `pt_print_host_var` " ?:N:type", `xasl_cache.c:1590` `xcache_decide_param_compare(s)` (같은 타입 두 값) | 위치마다 값 타입 | C·S | 값 타입 | 아니오 | DOUBLE 바인드 × BIGINT 열은 이미 별도 서명(R16, Q01 의 자동 매개변수 `?:0`); 서명 비교는 같은 타입끼리 |
| 컬렉션 원소 | `set_object.c:321` `col_element_compare` → `domain_compare_by_type_pair` `domain_rules.c:2954` | 타입 쌍 표 | S | 두 값 | 따라옴 | R20 `{b} = {d}`: 1행 |
| JSON 스칼라 | `object_primitive.c:15437` `mr_cmpval_json` → 타입 쌍 표 | 타입 쌍 표 | S | 두 값 | 따라옴, **사양 확인 필요** | S06 `cast(b as json) = cast(d as json)`: …993 과 2^53e0 이 같음. 커널을 바꾸면 JSON 숫자 비교도 바뀐다 — ADR 0037 범위에 넣을지 #566 |
| 다중 열 키 원소 | `object_primitive.c:7718` `pr_midxkey_compare_element` | K2 | S | 두 값 | 따라옴 | |
| 옵티마이저 상수 비교 | `query_rewrite_term.c:3202` `qo_compare_dbvalue_with_optype` (상수 범위 병합), `query_planner.c:13087` `qo_between_range_is_empty`, `:13379`·`:13432` `qo_all_some_in_selectivity` | K2 | C | 두 값 | 따라옴 | 범위 항 병합이 K2 답을 쓰므로 바뀌지 않으면 항이 잘못 합쳐진다 |
| 클라이언트 상수 접기 | `type_checking.c:13018` `pt_evaluate_db_value_expr` | K2 | C | 두 값 | 따라옴 | S09 `where 9007199254740993 = 9007199254740992e0`: 참 |
| 해시 테이블 키 동등 | `memory_hash.c:824` `mht_compare_dbvalues_are_equal` | K2 | S | 두 값 | 따라옴 | 한 테이블의 키는 보통 한 타입 |

### 3.3 커널을 거치지 않는 자리 — 따로 바꿔야 함

| 자리 | file:line | 지금 공통 타입 | 결정 | 데이터 | 변경 | 근거·실측 |
|---|---|---|---|---|---|---|
| **NULLIF** | 강제 공통 타입 `type_checking.c:21083` `pt_is_op_with_forced_common_type` (NULLIF·LEAST·GREATEST·IFNULL·COALESCE·NVL·NVL2·BETWEEN), 반환 타입 `:6472` `pt_expr_get_return_type`, 인자 강제 `:5691` `pt_coerce_expr_arguments`; 서버 비교 `stream_to_xasl.c:7528-7565`(decided.compares) → `fetch.c:1044`; 상수 접기 `type_checking.c:17486` | 클라이언트가 피연산자를 공통 타입(DOUBLE)으로 `CAST` 한 뒤 서버가 DOUBLE × DOUBLE 로 비교 | C (CAST 삽입) + X | 원 피연산자 도메인 2개 + 결과 도메인(DOUBLE 유지) | **예** | Q10 `nullif(b, 2^53e0)` 는 `nullif(cast(t.b as double), …)` 로 재작성되어 …993 도 NULL; S03 상수 접기도 NULL. 비교값 규칙에서는 …993 ≠ 2^53 이므로 2^53(DOUBLE 로 변환된 b) 을 돌려줘야 한다 |
| LEAST / GREATEST | 같은 강제 공통 타입, 서버 `arithmetic.c:6616` `db_least_or_greatest` | DOUBLE 로 CAST 후 비교 | C + X | — | 아니오 | 결과 타입이 DOUBLE 로 고정. DOUBLE 로 같으면 어느 쪽을 골라도 같은 DOUBLE, 다르면 순서가 일치(단조) → 답 불변. Q20 |
| **해시 조인 키** | 키 도메인 `domain_rules.c:2818` `domain_resolve_hash_key` (K1 target + 순위 `:2838`), 결정 `:2770` `domain_decide_hash_join_key`, 직렬화 `xasl_to_stream.c:7610`(+ sizeof `:7662`), 풀기 `stream_to_xasl.c:3958`, 행 `query_hash_join.c:2749` `hjoin_fetch_key`(변환 `:2795-2830`, 재검사 `:2849`), `:2732` `hjoin_compare_key`; 병렬 `px_hash_join_task_manager.cpp:223`, `:979`, `:1019`, `:1268`, `:1351` | 두 열을 DOUBLE 로 변환해 해시하고, 해시 일치 뒤 **변환된 값끼리** DIRECT DOUBLE 비교 | C→X | 두 열 도메인, 해시 도메인(새 규칙으로 같은 값이 같은 해시를 갖는 도메인), 재검사용 원 값 또는 그 도메인에서의 동등이 새 동등과 같다는 보장 | **예** | Q12 `t.b = u.d` 해시 조인: 두 행(…993 도 2^53 과 조인). R12 NUMERIC 도 같음. 재검사가 원 술어가 아니므로 커널만 바꾸면 해시 조인만 옛 답을 낸다 |
| 해시 함수 (#574 확정) | 해시 조인 `qdata_hash_scan_value` ← `hjoin_build`/`hjoin_inner_probe`, 해시 GROUP BY `qdata_hash_agg_hkey`, 서브쿼리 캐시·memoize·파티션 해시·`qexec_bind_checksum` 는 모두 `memory_hash.c` `mht_get_hash_number`. `mht_valhash` 의 NUMERIC 가지는 결과 캐시(`qfile_hash_db_value_array`)와 `ws_vmop` 에서만(gdb: 해시 조인·해시 GROUP BY 에서 0회) | 키 도메인으로 변환된 값의 해시 | S | 키 도메인 | 아니오(해시 함수 자체) | 바뀌어야 하는 것은 해시 함수가 아니라 해시 전에 값을 바꿔 넣는 키 도메인(위 행·아래 행)이다 |
| 해시 리스트 스캔 키 | `xasl_generation.c:7170` `pt_hash_key_domain`, `:7224` `pt_decide_hash_list_keys`(IMPLICIT 변환), build/probe `scan_manager.c:3493`·`8105`, 재검사 `:8138` | 공통 도메인 DOUBLE 로 해시, 일치 뒤 원 술어 재평가 | C→X | 두 열 도메인 | BIGINT·FLOAT 쪽 **아니오**, NUMERIC × DOUBLE **예** | 재검사가 원 술어라 해시 충돌은 걸러진다. 남는 위험은 새 규칙으로 같은 두 값이 다른 해시를 갖는 것(놓침): BIGINT→DOUBLE·BIGINT→FLOAT 는 정확한 반올림이라 n = shortest(d) 이면 변환값 = d. NUMERIC→DOUBLE 은 `numeric_coerce_num_to_double` 이 최대 2 ulp 틀린다(#563 `work/numconv2.out`) → 정확 반올림 변환 또는 다른 해시 도메인. 실측 없음(smoke 의 Q22 는 해시 리스트 스캔을 타지 않음) |
| HASH 파티션·함수 파티션 가지치기 | 결정 `xasl_generation.c:15243` `pt_set_prune_domains`, IN 허용 `:15222` `pt_comparison_keeps_key`, 풀기 `stream_to_xasl.c:5404` `stx_unpack_prune_conversion`, 행 `partition.c:1671` `partition_convert_value`, `:1286` `partition_prune_hash`(`:1303`), `:1807` `partition_prune_elements`, 함수 `:2545`·`:2583` | 값을 키 도메인(BIGINT)으로 변환해 해시·식 평가 | C→X | 키 도메인 × 값 도메인 | 아니오 (조건부) | 키는 정수뿐. 정수인 DOUBLE 은 BIGINT 로 정확히 변환되고, 정수 아닌 DOUBLE 은 반올림한 키의 파티션을 고르지만 그 값과 같은 행이 없다; 변환 실패(2^63 이상)는 가지치기를 포기(`:1852`). 전제(#566 결정 6 으로 성립): 정수 아닌 DOUBLE 은 어떤 정수와도 같지 않다. `pt_comparison_keeps_key` 주석("BIGINT key against a DOUBLE element compares in DOUBLE")은 낡음 → 새 비교가 conv 없음이면 true 가 되어 IN 리스트도 가지치기한다. R04 HASH `b = 2^53e0`: …992 만(…993 누락) |
| **동등 항 축약** (#566 에서 추가) | `query_rewrite_term.c:568` `qo_reduce_equality_terms` (상수 강제 변환 `:996` `tp_value_cast_force`) | `열 = 상수` 를 찾아 같은 열의 다른 쓰임을 상수로 바꾼다. 열 타입이 매개변수 타입(NUMERIC·문자열·BIT)이면 상수를 **열 도메인으로 강제 CAST**(DOUBLE→NUMERIC 은 16자리 절단)한 값으로, 아니면(BIGINT) 상수 그대로 | C | 열 도메인 × 상수 타입 | **예** (NUMERIC) | T01 `n = 12345678901234568e0 and m = n`(n=m=12345678901234568): 축약 뒤 `m = 12345678901234560` → 0행, T02 `n = …e0` 단독·T03 `m = n` 단독은 1행. develop 에서 이미 틀리고 비교값 규칙에서도 틀린다 — 복사 값이 비교값(가장 짧은 십진수)이어야 하거나, 변환이 정확하지 않으면 축약하지 않아야 한다. BIGINT 열(T04)은 상수를 그대로 복사하고, n = shortest(d) 가 정확한 동등이라 다른 쓰임과 일관 → 아니오 |
| UNIQUE / PK 탐색 | SELECT 는 인덱스 경로(Q17), INSERT/UPDATE 의 중복·FK 검사는 대입 뒤 같은 타입 | — | — | — | 아니오 | Q17 `uq.b = 2^53e0`: …993 을 찾음(DOUBLE 로 같음) — 인덱스 경로 행에서 따라옴 |
| DML 라우팅 (INSERT) | 대입(CAST) 뒤 키 타입으로 라우팅 | 같은 타입 | — | — | 아니오 | UPDATE/DELETE 의 WHERE 는 가지치기 행을 따름 |

### 3.4 같은 도메인끼리라 해당 없음

해시 GROUP BY `query_aggregate.cpp:3211` `qdata_agg_hkey_compare` / `domain_compare_in_domain`, GROUP BY skip `query_executor.c:23367`, 분석 함수 `:27134`, TOP-N `:30026`, 집계 병합 `stream_to_xasl.c:7787`, memoize·서브쿼리 캐시 `domain_rules.c:1885` `domain_key_values_equal`, px_scan MIN/MAX `px_scan_result_handler.cpp:1745`, 카탈로그·serial(`catalog_class.c`, `execute_statement.c`), 통계(`btree.c:6893`). 결과 타입(`tp_infer_common_domain`, IFNULL/COALESCE/NVL)은 비교가 아니다.

### 3.5 범위 경계 (사양 확인)

- **FLOAT**: BIGINT/NUMERIC × FLOAT 은 지금 FLOAT 로 비교한다(K0 순위 FLOAT > NUMERIC). R14 `f = b` 에서 FLOAT 16777216 이 BIGINT 16777217 과 같다. #566 결정 4: NUMERIC × FLOAT 의 비교값은 float32 의 가장 짧은 십진수, FLOAT × INTEGER/BIGINT 은 DOUBLE 로 넓혀 비교(같은 PR) — 둘 다 K0 의 FLOAT 판정을 K1·K2 에서 가로채야 한다.
- **NaN·inf**(#566 결정 3): 전순서 -inf < 수 < +inf < NaN 을 K1·K2·해시 키·정렬 병합·인덱스 범위가 공유한다.
- **문자열 × 수**(`TP_COMPARE_COERCE_TO_DOUBLE`, `object_domain.c:6344`): 열 대 열은 DOUBLE 로 비교한다. 리터럴은 클라이언트가 열 타입으로 바꾼다(S05 `b = '9007199254740992'` → `b = 9007199254740992`). ADR 0037 범위(BIGINT/NUMERIC × DOUBLE/FLOAT) 밖 — 넣을지 #566.
- **JSON 숫자**: 위 3.2. 커널과 타입 쌍 표를 바꾸면 자동으로 바뀐다.

## 4. develop 실측 (같은 데이터, 경로별 답)

데이터: `t(id, b BIGINT, n NUMERIC(20,0), d DOUBLE, f FLOAT)` 에 id 1 = (…993, …993, 2^53e0, 16777216f), id 2 = (…992, …992, 1e0, 1f). `u.d = 2^53e0`. `…993` = 9007199254740993 = 2^53+1. DOUBLE 비교에서는 …992 와 …993 이 모두 2^53e0 과 같고, 비교값 규칙에서는 …992 만 같다.

| 프로브 | 경로 | develop 답 | 비교값 규칙 |
|---|---|---|---|
| Q01 `b = 2^53e0` | 단일 열 인덱스 | id 1, 2 | id 2 |
| R09 `b = 2^53e0 and id = 1` (인덱스 (b,id), 3행 테이블) / S04 같은 모양(2행) | 다중 열 인덱스 | 0행 / id 1 (흔들림) | 0행 |
| R11 `b = …992 or b = 2^53e0` | 다중 키 병합 | id 2 | id 2 |
| Q21 `b in (…993, 2^53e0)` | 다중 키 병합 | id 1 | id 1, 2 |
| Q05 `b = d` | 술어 | id 1 | 0행 |
| Q12/Q13/Q14 `t.b = u.d` | 해시 / 병합 / NL 조인 | id 1, 2 (셋 다) | id 2 |
| Q15 RANGE 파티션 `b = 2^53e0` | 가지치기 | …993 | …992 |
| Q16 LIST 파티션 | 가지치기 | …992 | …992 |
| R04 HASH 파티션 | 가지치기(변환) | …992 | …992 |
| Q10 `nullif(b, 2^53e0)` | 클라이언트 CAST | NULL, NULL | 2^53(id 1), NULL(id 2) |
| R17 `d = ?` ← BIGINT …993 | 바인드 rule cast | id 1 | 0행 |
| R14 `f = b` (16777216f, 16777217) | FLOAT 비교 | id 3 | 0행 |
| S06 JSON `cast(b as json) = cast(d as json)` | 타입 쌍 표 | id 1 | 0행(사양 확인) |
| S09 `9007199254740993 = 9007199254740992e0` | 상수 접기 | 참 | 거짓 |
| T01 `n = 12345678901234568e0 and m = n` (n = m = 12345678901234568) | 동등 항 축약 | 0행 (T02·T03 단독은 1행) | 1행 |

## 5. 디스패치 설계(#567)에 넘기는 사실

1. 가로챌 곳은 K1(`domain_compute_comparison`)과 K2(`tp_value_compare_with_error`) 두 곳, 판정 입력은 두 DB_TYPE 뿐이다. 순위표(K0)를 바꾸면 결과 타입·해시 키 도메인까지 바뀐다.
2. 표현은 **"어느 쪽도 변환하지 않는 비교"(conv 둘 다 NULL)** 여야 소비자 넷(바인드 rule cast, 범위 확장 merges, IN 가지치기 허용, 리터럴 고정)이 저절로 맞는다. 그 위에서 (가) 새 method 값을 두면 method 스위치 3곳·연산자 함수표·병렬 merge join 적격·B-tree 빠른 경로를 손봐야 하고, (나) DIRECT + 전용 cmpval(`PR_TYPE` 복사, survey S1-2 의 `domain_compare_cmp` 모양)이면 그 자리들은 그대로지만 cmp 를 다시 만드는 세 곳(`stx_unpack_decided_compare`, `domain_compare_mirror`, `domain_compute_comparison`)이 두 source 타입으로 전용 cmpval 을 골라야 한다.
3. 따로 바꿀 곳: NULLIF(클라이언트 CAST 와 상수 접기), 동등 항 축약의 NUMERIC 강제 CAST(`qo_reduce_equality_terms`), 해시 조인(키 도메인과 재검사), 해시 리스트 스캔의 NUMERIC × DOUBLE 키, `domain_key_compare_merges` 의 죽는 분기 정리, `domain_resolve_compare` 정리.
4. #566 이 정한 것과 맞춘 결과: 정수 아닌 DOUBLE 은 정수와 같지 않다(|d| ≥ 2^53 은 모두 정수, 그 아래 v(d) 는 정수 아님) → HASH 파티션 가지치기는 '아니오'의 전제가 성립. 키 원소 규칙은 #566 결정 1 로 '예'. #566 이 다루지 않은 사양 질문: **JSON 숫자 비교**(커널을 바꾸면 자동으로 바뀜), **문자열 × 수**(`TO_DOUBLE`).
5. 실측하지 않은 것: 해시 리스트 스캔 경로(코드로만 판정), CS 모드 병렬 경로(병렬 해시 조인·병렬 merge join — 코드로 같은 함수임을 확인).
