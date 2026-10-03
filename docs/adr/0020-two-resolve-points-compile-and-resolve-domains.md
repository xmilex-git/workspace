---
status: accepted
date: 2026-10-03 (2026-09-22 판 #320 과 그 뒤 정정들을 최종 구현 기준으로 다시 씀)
basis: CUBRID/cubrid#8022 HEAD 23a5e5561 (develop 15e7dc8b5 동기화)
locked-by: xmilex-git/workspace#320 (2026-09-22) · #323 D-323-08 (2026-09-22) · #355 (2026-09-26) · #366·#367 (2026-09-27) · #374 (2026-09-29)
---
# 도메인·collation 확정 지점은 컴파일(로드 도출 포함)과 실행 전 도메인 확정 두 곳뿐이다 (도메인 계획 불변, 실행별 답은 XASL_STATE, PX 워커는 상속만, 행 시점 확정 0)

질의의 도메인·collation 은 **컴파일**(클라이언트 파서 → XASL 스트림; 서버의 로드 도출은 그 순수 함수)과 **실행 전 도메인 확정**(`qexec_resolve_domains` — `qexec_execute_query` 가 값 배열을 만든 직후·`qexec_execute_mainblock` 전, 실행당 1회) 두 곳에서만 정해진다. 그 뒤 fetch·비교·집계·정렬·리스트 파일·인덱스 키·PX 워커 어디에서도 값을 보고 도메인을 정하거나 보정하거나 되돌리지 않는다 — develop 의 행 시점 확정 43곳(감사표 S-01~S-43)은 삭제되거나 확정을 읽는 자리가 됐다.

- **컴파일**은 develop 과 같은 도메인을 같은 필드로 싣는다. 가변 도메인 자리는 타입이면 `tp_Variable_domain`(`pt_make_regu_hostvar`), collation 이면 develop 의 LEAVE·ENFORCE 그대로다. regu·arith·pred 스트림 레이아웃은 필터 술어·함수 인덱스 식으로 카탈로그에 저장되는 디스크 포맷이라 바꾸지 않는다. 새 스트림 항목은 `INDX_INFO.key_type`(B-tree 키 도메인; access spec 은 디스크에 없다) 하나다.
- **로드 도출**은 `stx_map_stream_to_xasl` 안의 `stx_build_domain_plan` 이 세 로드 경로(플랜 캐시 클론·비캐시 `qmgr_process_query`·PX 워커 언팩) 공통으로 1회 한다. 결과 `DOMAIN_PLAN` 은 unpack arena 에 살고 읽기 전용이다: 노드마다 도메인 계획 항목(`DOMAIN_PLAN_ITEM` — 고정 도메인의 답 `fixed` 또는 확정 도메인 표 번호 `resolved_index`, 피연산자 부류 `OPERAND_CONST`/`ROW`/`CORRELATED`/`NON_CACHEABLE`, POS 참조 `ref`, 확정 변환기), 늦은 바인딩 노드 목록(생산자 우선), 확정 비교 계획(`DOMAIN_COMPARE_PLAN`), ALL/SOME 원소 계획, 인덱스 키 계획(`domain_plan_index` — `key_type` 에서 bound·컬럼마다 `DOMAIN_KEY_RULE`: INDEX/STRICT/KEEP/CONSTANT/LATE_BIND), 상수식·세션변수·상수 가지 목록. 노드는 `plan_item` 포인터만 받고(`REGU_VARIABLE`·`ARITH_TYPE`·`AGGREGATE_TYPE`·`ANALYTIC_TYPE`·`QFILE_TUPLE_VALUE_POSITION`), `INDX_INFO.key_plan`, 루트 `XASL_NODE.domain_plan` — 전부 스트림에 없고 구조체 크기는 develop 과 같다(`original_domain`/`original_opr_dbtype` 이 있던 자리). 로드 끝에 항목 없는 가변 도메인이 남으면 미확정 도메인 오류다. 필터·함수 인덱스 스트림은 가변 POS 가 있으면 로드를 거부하고(`stx_index_stream_rejected`; 실행 전 확정 없이 평가되는 스트림이라 정할 곳이 없다), 그 술어의 비교는 로드가 확정한다(`domain_plan_stream_compares`).
- **실행 전 도메인 확정**은 순서가 고정이다(`qexec_resolve_domains_internal`): `qexec_init_resolved_domains`(값·확정 블록 1개 할당, 입력 보존) → POS 참조마다 값 공유(`qexec_share_value`)와 가변 POS 의 바인드 도메인 기록 → 늦은 바인딩 노드를 생산자 우선으로(`qexec_resolve_late_bind_node` → `domain_resolve`) → 확정 비교와 ALL/SOME 원소(`qexec_resolve_compare`·`qexec_resolve_elements`; 상수 쪽은 1회 변환해 자기 값) → 표를 읽을 수 있게 `frozen` → 상수식 1회 평가와 그 위의 노드·비교(`qexec_evaluate_constant_expression`) → 세션변수 문장 타입(`qexec_resolve_session_variables`) → 인덱스 키 상수 원소와 키 비교 표(`qexec_resolve_index_keys`) → 상수 가지 아래 미룬 상수 오류 판정(`qexec_raise_deferred_errors`). 실패는 전부 실행 전 오류다. mainblock 안에서는 확정도 표 쓰기도 없다 — 상관 값·비상관 부질의 결과는 스코프 진입 뒤 첫 사용 때 확정 변환기로 1회 바꾼 실행 임시값(`DOMAIN_EXECUTION_TEMPORARY`)이고, 상관 복합 키는 range open 이 같은 변환기를 값에만 적용한다.
- **실행별 답은 XASL_STATE 에만** 둔다(세 수명): 확정 도메인 표 `resolved_domain`(`RESOLVED_DOMAIN_TABLE` — `in`·`vals`·`domains[]`·`compares[]`·`elements[]`·`indexes[]`·`value_states[]`; 확정이 채우고 봉인, 행은 읽기만), 실행 도메인 `domain_execution`(`DOMAIN_EXECUTION_STATE` — `node_domains[]`·`operand_types[]`·`interpolation_list_domains[]`: develop 이 실행 중 노드 필드에 쓰고 clear 에서 되돌리던 답의 자리; `temporaries[]`·`scope_generations[]`: 실행 임시값), 미룬 상수 오류(`qexec_resolve_domains` 의 지역 목록). 도메인 계획 노드 필드에는 쓰지 않으므로 `original_*` 필드와 `qexec_clear_*` 원복은 없다.
- **행**은 고정 항목이면 `item->fixed`, 가변이면 `qexec_late_bind_domain` 으로 확정을 읽고 확정 변환기(`tp_value_convert`)만 부른다: 산술 `fetch_arith_binary`/`fetch_cast_operand`, 비교 `eval_compare_term`, 세션변수 읽기 `fetch_session_read_value`, 집계는 첫 행 전 `qexec_setup_aggregate_domains`(PX 워커는 `qexec_setup_parallel_aggregates`), 리스트 파일은 열 때 `qdata_get_valptr_type_list`, 인덱스 키는 range open 의 `scan_key_column` 과 B-tree 의 `domain_search_key_compare`.
- **PX 워커**는 `qexec_deep_copy_xasl_state`/`qexec_free_xasl_state` 한 쌍이 `qexec_copy_resolved_domains` 로 값 배열(워커 소유 clone)과 확정 도메인 표를 깊은 복사해 상속만 한다(`px_query_task`·`px_scan_task` 모두 이 한 경로). 워커의 확정 0, 루트 역전파 0.
- **미확정 도메인 오류** `ER_QPROC_DOMAIN_UNRESOLVED`(-1383): 로드 검사와 실행 검사(`fetch_peek_arith`·`eval_value_rel_cmp`·`qdata_get_valptr_type_list`·`scan_key_column`·`domain_search_key_compare` 등)에서 optdebug 는 assert, release 는 이 오류다. 재컴파일 트리거 목록에 넣지 않는다. CTP sql·medium 전수에서 0 이다.

결정 원문: #312 D-M3, #318 D-318-01~06, #323 D-323-01~09·13~18, #341 D-341-04, #342 D-342-02~06, #355 D-355-01·08·09, #357(번호 -1383), #366 D-366-01~06, #367 D-367-01~07, #374 D-374-07~18. 정본: `docs/research/domain-pin-architecture.md` §1, `domain-pin-interface.md`, `pr8022-domain-state-guide.md`(필드·수명·PX 복사), `domain-pin-audit.md`(삭제 감사).

## Considered Options

- **명시 계획 표를 스트림 새 섹션 + 노드마다 `plan_idx` 로 팩**(전략 B): 기각. 노드 레이아웃이 디스크 포맷이고, 도메인의 진실이 노드 필드와 표 두 곳이 된다. B 의 "덤프로 검사" 장점은 로드 도출 결과를 qdump 에 찍어 얻는다.
- **실행마다 트리 전체에 타입 패스**(전략 C): 기각. 정적 계획에도 매 실행 O(트리), 파서 격자의 서버 복제, prepare 응답 컬럼 메타 불가 — 이전 캠페인 "잔여 확정" 이 실패한 모양(L-40·L-41).
- **플랜 캐시를 바인드 타입 서명으로 변형**(D): 지도 범위 밖.
- **블록마다 확정하는 두 번째 단계**(G2, #318 초안 D-318-08): 폐기(D-323-08). 결정이 블록마다 반복된다. 실행 임시값과 range open 의 값 변환으로 대신한다.
- **develop 방식 유지**(실행이 노드 필드에 쓰고 clear 에서 되돌림): 기각. 플랜 캐시 클론을 여러 실행이 공유하고(원복 누락 = 오염), PX 워커의 역전파·교차 mspace free(L-42·L-46)가 거기서 나왔다.
- **`ER_QPROC_INVALID_XASLNODE` 재사용**: 기각. 클라이언트가 그 코드를 받으면 xasl_id 를 버리고 조용히 재컴파일·재실행해(`db_vdb.c`) 위반을 숨긴다.
- **실행별 답을 플랜 노드 안 union/비팩 flags 에 인라인**(인터페이스 β): 측정 뒤 보류(D-323-16) — 지금은 포인터 하나.

## Consequences

- 비용: 로드당 도메인 계획 메모리(XASL 캐시 항목 단순 조회 +9~10%, 2,000 바인드 `INSERT … VALUES` +83%), 실행당 할당 블록 1개 + 가변 항목 수만큼의 확정. 명령 수는 모든 벤치 셀에서 develop 대비 +5% 이내이고, 다른 타입 바인드는 행당 타입 판정이 사라져 줄었다(`domain-pin-bench-baseline.md` §6).
- 헤더 계약: `domain_rules.h` ← `domain_plan.h` ← `domain_resolve.h` ← `query_executor.h`/`fetch.h`, 서버 전용(`#error Belongs to server module`), `parser/`·`compat/`·`broker/`·`method/` 포함 금지.
- ALTER 가 바꾼 컬럼을 술어가 읽는 필터 인덱스는 재컴파일해 재구축한다(`do_recreate_filter_index_constr`, `SM_PREDICATE_INFO.att_ids`) — 스트림 도메인이 옛 타입으로 남지 않는다(#359).
- `pt_make_regu_hostvar` 의 "바인드 값 타입을 도메인으로" 단계와 바인드 피크 재계획의 값 타입 도메인은 없다(클라이언트에 숨어 있던 세 번째 확정 지점, D-318-05). 재계획은 값을 비용 추정에만 쓴다.
- 실행 응답 컬럼 메타: 가변 도메인이 결과 컬럼인 문장(`SELECT ?`)은 develop 처럼 실행 응답의 `include_column_info` 로 갱신한다.
- 되돌리는 길: 스트림 레이아웃이 불변이라 서버 측만 되돌려도 저장된 필터 스트림과 호환된다. `INDX_INFO.key_type` 은 클라이언트·서버 lockstep(같은 빌드) 요구 그대로다.
