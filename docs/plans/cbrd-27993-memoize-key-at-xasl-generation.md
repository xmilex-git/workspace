# CBRD-27993 구현 정리 — 메모이즈 키를 XASL 생성 때 정한다

상태: 구현 전 (2026-11-10, grill-with-tla 1~6라운드 결정 반영, 열린 질문 없음).
근거: `docs/tla/CBRD-27993/` (MAP.md 결정 D1~D23, claim C1~C3), ADR 0053, GLOSSARY "메모이즈 키".
기준 코드: develop 2dac6ecc2, 워크트리 `~/dev/cubrid-worktree/CBRD-27993`.

## 1. 고치는 결함과 목표

- 결함: 가운데 스캔 x의 memoize 키에 뒤 스캔 y의 컬럼이 들어간다. `pt_get_mvcc_reev_range_data`가 range term의 next 체인까지 x의 where_range로 복사한다. 서버 `key_maker`(`memoize.cpp`)는 where_range의 TYPE_CONSTANT를 모두 키로 모은다. `storage::put`이 행마다 키를 다시 읽으므로, y가 바뀔 때 한 키의 행이 여러 키로 쪼개진다. develop 재현 결과는 memo on `1250 749361`, memo off `1381 826674`이다 (`.git_ignored_dir/scratch/cbrd27993/probe1/`).
- 목표 (claim):
  - C1: memoize한 NL은 모든 바깥 행에 대해 memoize off와 같은 inner 행을 돌려준다.
  - C2: memo가 답하는 키는 그 키의 inner 행 전부이거나 "행 없음" 하나다.
- 키의 정의 (D2, D9): join 순서에서 inner보다 앞선 스캔의 컬럼만 키다. 뒤 스캔의 컬럼, inner 자신의 컬럼, 부질의 결과, 바깥 질의의 상관 값은 키가 아니다.

## 2. 변경 목록

### 2.1 키 수집 — `src/optimizer/plan_generation.c` `gen_outer`, NL 분기 (D3, D8, D13, D16)

`scan = gen_inner (...)` 직후, 지금 `XASL_NO_MEMOIZE`를 정하는 자리(develop 2748~2756)에서 한다.

1. term 집합은 `predset`과 inner plan의 term이다. inner plan의 term은 `qo_collect_inner_scan_terms`가 모으는 `sarged_terms`, `plan_un.scan.terms`, `kf_terms`, follow의 path term이다. 이 함수는 지금 static이므로 query_planner.c 밖에서 쓸 수 있게 연다. select 목록에서 inner에 붙은 부질의(`new_subqueries`에만 있는 것)는 키에 넣지 않는다 (D13).
2. term마다 `QO_TERM_PT_EXPR`의 next를 끊고 `parser_walk_tree`로 훑는다. `qo_expr_segs`처럼 next를 임시로 끊었다가 복원한다.
   - inner plan 노드의 파생 테이블(`QO_NODE_ENTITY_SPEC (node)->info.spec.derived_table`)도 같이 훑는다. 그 파생 테이블이 바깥 컬럼을 읽을 때만 재사용 검사를 건다. 상관되지 않은 파생 테이블은 한 번 만들어지므로 memoize를 켜도 끄도 같은 리스트를 읽는다. 바깥 행에 상관된 파생 테이블은 바깥 행마다 다시 만들어지므로, 그것이 읽는 바깥 컬럼도 inner의 입력이다 (D24, 첫 구현의 CTP에서 발견).
   - 키 전용 pre 함수는 PT_NAME 중 spec_id가 바깥 plan 노드(`outer->info->nodes`의 `QO_NODE_ENTITY_SPEC`)의 것만 모은다.
   - PRIOR, CONNECT_BY_ROOT, SYS_CONNECT_BY_PATH에서 멈추지 않는다. `set_seg_expr`과 다른 점이다.
   - 부질의의 GROUP BY, HAVING, 분석 함수, CONNECT BY, derived table, JSON_TABLE expr은 기본 훑기가 내려간다.
   - 같은 (spec_id, 속성)은 한 번만 넣는다.
3. 모은 이름마다 DB_VALUE와 도메인을 찾는다. `pt_attribute_to_regu`의 table_info 분기와 같은 방법을 쓴다: `pt_find_table_info (spec_id, symbols->table_info)` → `pt_find_attribute (attr, table_info->attribute_list)` → `pt_index_value (table_info->value_list, index)`. 도메인은 CBRD-27583의 `regu_produced_domain`과 같은 값이어야 한다. 이는 value_list의 `dom`인데, 구현 때 D10 assert로 대조한다. 대응에 실패한 이름이 하나라도 있으면 `XASL_NO_MEMOIZE`로 둔다 (안전 기본값).
   - list file 문맥(`symbols->current_listfile`)은 `make_hashjoin_proc`에서만 켜진다. 해시 조인 val_list도 같은 DB_VALUE를 가리키므로(`new_val->val = src_val->val`) table_info 대응과 같다.
4. 같은 term 집합에 `pt_is_result_reuse_safe`(2.4, D21)를 돌려 false면 `XASL_NO_MEMOIZE`다. 이 검사는 셋을 거부한다.
   - 비결정 연산자(D11, D23): SYS_GUID, UUID, RAND, DRAND, RANDOM, DRANDOM, CURRENT_VALUE, NEXT_VALUE, INCR, DECR, EXEC_STATS, TRACE_STATS, SLEEP. ROW_COUNT와 LAST_INSERT_ID는 문장 동안 고정이라 넣지 않는다.
   - DETERMINISTIC이 아닌 저장 함수(D12): PT_METHOD_CALL의 저장 함수 directive를 `jsp_find_stored_procedure`로 얻은 카탈로그 객체에서 읽는다(`SP_DIRECTIVE_DETERMINISTIC`). CS와 SA 모두에서 검사한다.
   - 세션 변수 (D18, D22): term에 세션 변수 읽기(`PT_EVALUATE_VARIABLE`)나 대입(`PT_DEFINE_VARIABLE`)이 있으면 거부한다. 문장이 대입하는지는 보지 않는다.
5. 결과를 inner XASL의 새 필드 `memoize_key`에 싣는다. 키가 비어도(바깥 값을 읽지 않는 inner) 싣는다. 이때는 `n_elements = 0`이고, 모든 바깥 행이 한 키로 probe한다 (D17). 키가 없음(NULL, memoize 안 함)과 빈 키(0개)를 구별한다.
6. `qo_nl_inner_memoize_is_useless`는 별도의 term segment 대신, 모은 키 이름의 segment로 NDV를 추정한다 (D16). 키 수집을 먼저 하고 그 segment 집합을 넘긴다.

`pt_gen_simple_plan` 경로(최적화 off, 식이 아닌 conjunct, `OPTIMIZATION_LIMIT` 초과, OOM)는 키가 없으므로 memoize하지 않는다 (D15).

### 2.2 XASL 필드와 직렬화 (D3)

- `src/query/xasl.h` `XASL_NODE`: `memoize_key`를 추가한다. 모양은 `SQ_KEY`(`subquery_cache.h`: `dbv_array`, `domains`, `n_elements`)를 재사용하고, 없으면 NULL이다.
- `src/query/xasl_to_stream.c`: `xts_process_sq_cache`처럼 DB_VALUE 배열과 도메인을 쓴다. `xts_save_db_value`가 방문 포인터 표를 쓰므로, 키 슬롯은 바깥 val_list와 같은 offset으로 저장된다(별칭 유지). 크기 계산 함수에도 더한다.
- `src/query/stream_to_xasl.c`: `stx_build_sq_cache`처럼 푼다. XASL 초기화(develop 274행 `memoize_storage = NULL` 근처)에서 NULL로 둔다. 복제본과 병렬 worker는 스트림을 다시 풀어 만들므로, 키 슬롯이 각자의 val_list를 가리킨다.
- `src/query/query_dump.c`: sq_cache 키 출력 옆에 memoize 키를 출력한다.

### 2.3 서버 — `src/query/memoize.cpp`

- `storage::new_storage`는 `key_maker` 대신 `xasl->memoize_key`의 배열과 도메인으로 `storage::init`을 부른다. `memoize_key == NULL`이면 저장소를 만들지 않는다. `key_cnt == 0` 거부를 지운다 (D17). 길이 0인 키의 hash와 equal이 한 값으로 모이는지 확인한다 (`key::hash`는 0, `key::equal`은 true).
- `key_maker`는 `#if !defined (NDEBUG)`에서만 남긴다 (D10). 키가 만들어질 때 옛 훑기를 돌려 확인한다. 술어(where_key, where_pred, where_range, if_pred, after_join_pred)와 그 술어가 참조하는 dptr에서 찾은 TYPE_CONSTANT 중 앞선 스캔의 val_list를 가리키는 것이 모두 `memoize_key`에 있는지 assert한다. "앞선 스캔"은 실행기의 scan_ptr 사슬에서 inner보다 앞선 노드의 val_list다. select 목록에서만 붙은 dptr은 제외한다 (D13).
- `nondeterministic_check`를 지운다 (D11).
- `possible_check` (D7, D14):
  - level 0은 그대로 둔다.
  - level ≥ 1의 CONNECT BY, GROUP BY, 분석 함수, HAVING 부질의 거부를 지운다.
  - level ≥ 1에서 key_maker 한계 때문에 있던 거부도 지운다: spec 없음, `spec->next`, bptr/fptr, LINK가 아닌 dptr, 집합 타입 val_list, JSON_TABLE·SET·REGUVAL_LIST 대상.
  - level ≥ 1에서 스냅샷 밖 데이터를 읽는 경우는 남긴다: 시스템 클래스와 MVCC 비활성 클래스, 레코드·페이지·키·노드 정보와 스키마 접근, METHOD, SHOWSTMT, DBLINK, CLASS_ATTR.
- `storage::put`은 지금처럼 행마다 키 슬롯을 읽는다 (D5).
- CBRD-27567의 dptr 상관 참조 처리(서브쿼리 키 수집, dptr 결과 제거)는 key_maker와 함께 사라진다. 필터 부질의의 바깥 참조는 2.1의 term 훑기가 모은다.

### 2.4 공용 재사용 검사와 상관 부질의 캐시 — `src/parser/xasl_generation.c` (D19, D20, D21)

- `pt_check_corr_subquery_not_cachable_expr`를 `pt_check_reuse_unsafe_expr`로 이름을 바꾸고 넓힌다. 이 함수는 `parser_walk_tree` pre 콜백이다. 기존 8개 연산자에 INCR, DECR, EXEC_STATS, TRACE_STATS, SLEEP을 더하고(D23), 다음 두 가지를 더한다.
  - DETERMINISTIC이 아닌 저장 함수 (PT_METHOD_CALL, directive를 읽는 새 helper)
  - 세션 변수의 읽기와 대입 (`PT_EVALUATE_VARIABLE`, `PT_DEFINE_VARIABLE`). 문장이 대입하는지는 보지 않는다 (D22).
- 감싸는 함수 `pt_is_result_reuse_safe (parser, tree)`를 둔다. memoize 키 수집(2.1)과 `pt_prepare_corr_subquery_hash_result_cache`가 함께 부른다.
- `pt_make_sq_cache_key_struct`의 TYPE_SP 분기에서 `is_deterministic` 검사와 `#if defined (CS_MODE)` 가드를 지운다. 공용 검사가 두 모드 모두에서 같은 규칙을 적용한다. SA에서도 서명은 만들어지므로(`pt_stored_procedure_to_regu` → `jsp_make_pl_signature`) 모드 구분이 필요 없다.
- 검증: probe `sp-sa/`에서 SA의 ND가 10개, `sessvar/sq.sql`에서 캐시 on이 84여야 한다. DETERMINISTIC 함수와 대입 없는 `@v` 읽기는 지금처럼 캐시되어야 한다.

### 2.5 손대지 않는 것

- `pt_get_mvcc_reev_range_data`의 next 체인 복사 (D6).
- `storage::put`의 키 재사용 (D5).
- 저장소 수명: mainblock 실행마다 다시 만든다. D9가 여기에 기댄다. 이 사실은 `new_memoize_storage` 호출부에 주석으로 남긴다.

## 3. 검증 계획

CLAUDE.md의 검증 정책을 따른다. 단위 테스트는 쓰지 않는다.

1. 빌드: optdebug와 release 모두. 바꾼 파일마다 `-fsyntax-only`를 먼저 돌린다.
2. 재현 smoke: probe1의 SQL로 memo on과 off가 같은지 본다. 같은 데이터를 파티션 테이블로 바꾼 경우도 본다.
3. 풀린 모양: inner의 필터 부질의에 GROUP BY, 분석 함수, HAVING 부질의, CONNECT BY(PRIOR 안의 바깥 컬럼 포함), 두 테이블 조인, derived table이 있는 경우를 본다. memo on/off 결과가 같아야 하고 `MEMOIZE` trace 줄이 나와야 한다.
4. 거부 유지와 새 거부:
   - 풀린 부분 안의 RANDOM은 memoize하지 않아야 한다.
   - DETERMINISTIC이 아닌 저장 함수는 CS와 SA 모두에서 memoize하지 않아야 한다.
   - 스냅샷 밖 데이터를 읽는 부질의는 memoize하지 않아야 한다.
   - 세션 변수 probe `.git_ignored_dir/scratch/cbrd27993/sessvar/`의 memo on/off가 같아야 한다. 대입이 없는 문장의 `@v` 읽기도 memoize와 상관 부질의 캐시를 쓰지 않아야 한다 (D22).
   - 빈 키 inner(바깥 값을 읽지 않는 NL inner)는 memoize되고 결과가 off와 같아야 한다. trace에서 hit가 바깥 행 수 - 1이어야 한다.
   - 상관 부질의 캐시: 2.4의 검증.
5. D9: memoize되는 NL을 가진 상관 부질의를 바깥 질의 값이 바뀌는 행에서 실행한다. memo on과 off를 비교한다.
6. 병렬 실행과 파티션 inner(블록마다 저장소 갱신)에서 on/off가 같은지 본다.
7. D10 assert: optdebug CTP sql과 medium 전체를 돌려 assert가 0건이어야 한다. 키가 놓친 모양이 있으면 이 assert가 질의를 알려 준다.
8. CTP: sql, medium 전체와 memoize 관련 디렉터리를 돌린다. 풀린 모양과 저장 함수 거부로 바뀌는 `MEMOIZE` trace 정답은 하나씩 원인을 확인한 뒤 갱신한다.
9. TC: `cubrid-tc-author`로 CBRD-27993 재현과 3~5번 모양을 memo on/off 쌍으로 만든다.
10. TLA+: 구현 spec이 `docs/tla/CBRD-27993/` 설계 spec을 refinement한다. 구현 빌드의 trace validation도 한다 (cubrid-tla 9단계, P50).

## 4. 질문

- Q20 (결정, D20): 상관 부질의 캐시에도 claim C3("캐시를 쓴 결과는 끈 결과와 같다")을 둔다.
- Q21 (결정, D21): 비결정 검사를 memoize와 상관 부질의 캐시가 함께 쓰는 파스 트리 함수 하나로 모은다. 이름은 두 기능에 맞게 `pt_check_reuse_unsafe_expr` / `pt_is_result_reuse_safe`로 한다.
- Q22 (결정, D22): 이름 비교도, 문장의 대입 여부 확인도 하지 않는다. 세션 변수를 읽거나 대입하면 재사용하지 않는다.
- Q23 (결정, D23): 공용 검사의 연산자 목록에 INCR, DECR, EXEC_STATS, TRACE_STATS, SLEEP을 더한다. ROW_COUNT와 LAST_INSERT_ID는 문장 동안 바뀌지 않으므로 더하지 않는다.

## 5. 위험

- XASL 형식이 바뀐다. 같은 버전 안의 plan cache만 쓰므로 호환 문제는 없다. 다만 직렬화, 역직렬화, dump, 크기 계산 네 곳을 빠짐없이 맞춰야 한다.
- 거부를 풀거나 빈 키를 받으면 memoize가 걸리는 질의가 늘어난다. 저장 함수 거부와 세션 변수 거부는 memoize가 꺼지는 질의를 만든다. 셋 다 CTP의 `MEMOIZE` trace 정답을 바꿀 수 있다.
- 상관 부질의 캐시: SA 모드에서 DETERMINISTIC이 아닌 저장 함수 캐시가 꺼지고, 세션 변수를 읽는 부질의 캐시가 모두 꺼진다. 결과가 바뀌는 쪽은 develop이 틀리던 경우뿐이다. 대입 없이 `@v`를 매개변수처럼 쓰는 질의는 결과는 같고 캐시와 memoize만 잃는다 (D22, 사용자가 단순한 검사를 택함).
- 키 수집의 완전성은 term 집합이 `gen_inner`가 XASL로 만드는 술어와 같다는 데 기댄다. 이 가정은 D10 assert가 CTP에서 확인한다.
