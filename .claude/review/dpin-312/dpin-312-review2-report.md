# dpin / #312 정적 리뷰 ② — 코드 직관성 · cpp-perf-rules

**티켓:** [dpin-18c #369](https://github.com/xmilex-git/workspace/issues/369) · 반영: [dpin-18b #368](https://github.com/xmilex-git/workspace/issues/368)(사용자 지시 2026-09-27)
**Base / HEAD:** `c63a3b993` / `8a2cf1264` (develop 재기반 #357 뒤, #368 C1~C3 포함; 미커밋 C4 작업 트리 제외)
**범위:** 35 커밋, 87 파일, +41,306 / −7,585. 정적 소스 리뷰만(빌드·CTP·측정 없음). #368 이 이미 확정한 결함(B-1·A-F2·B-2·A-F1·A-Q1·PX `pr_clone_value`)은 다시 세지 않는다.
**읽기 사본:** `.git_ignored_dir/scratch/312-review-0927b/head/`(HEAD 소스), `…/diff/`(base..HEAD 파일별 디프). `파일:줄` 은 HEAD 기준, 디프 줄은 `(diff)`.
**규칙:** cpp-perf-rules — BR-04/A59(행 루프의 고정 조건 재검사), A60/CC-05(행당 out-of-line 호출), BR-06/A61(다중 디스패치), MEM-02/05(hot/cold), ALLOC-01/02, GLOB-01/05, PAR-14, PHYS-01/11, MEAS-01/06/07/08, CC-08.

> **TL;DR** — 게이트 뒤 코드는 "결정을 읽는다" 로 읽히게 됐고(FETCH_ALL_CONST 춤·첫 값 캐스케이드·S-30 삭제 등), 새 모듈의 저장소 설계(단일 블록·arena·static_assert)는 규칙집대로다. 남은 것은 셋이다. **P1 하나**: `T_TO_NUMBER` 가 아직 플랜/캐시 도메인에 쓴다(R2-07). **P2 셋**: 행마다 재검사되는 불변 가드 사슬(`RESOLVED_CELL`, R2-03), 비교 행 경로의 이중 디스패치 + site 간접(R2-08), 로드의 O(n²) 레코드 매칭(R2-21). 나머지는 정리(P3)다. 크기 판정은 #345 P1~P8 측정이 한다(MEAS-01); 구조적 사실은 소스로 확실하다.

## 발견 목록

형식: `R2-NN [축] [규칙] [심각도]` — 요지 / 근거 / 제안. 심각도: P1 불변식·정확성, P2 행·로드 경로 비용(구조 확실, 크기는 측정), P3 정리.

### P1

- **R2-07 [정확성·직관성] [D-355-08·ADR 0020] [P1]** `src/query/fetch.c:3302-3303` `T_TO_NUMBER` 가 `domain->precision = …; domain->scale = …;` 로 도메인에 쓴다. `domain = qexec_node_domain (vd, regu_var->domain, regu_var->domain_plan)` 는 (a) 플랜 노드의 컴파일 도메인 — 스트림 언팩 `or_unpack_domain` → `or_get_domain` → `tp_domain_cache` (`object_representation.c:3761-3769`, `stream_to_xasl.c:5692`): **캐시 공유 도메인** — 이거나 (b) 게이트가 준 `taken` 도메인(해석기 결과는 캐시 도메인, `domain_resolver.h:60`). 실행이 플랜/캐시 도메인에 쓴다 — "실행은 플랜 노드의 도메인에 쓰지 않는다"(D-355-01/08) 의 마지막 예외이고, 캐시 도메인이면 세션 간 공유 상태 변조다. develop 에도 같은 줄이 있어(`c63a3b993` fetch.c:3075 `regu_var->domain->precision = …`) P0 답은 같다 — 답이 아니라 불변식 문제. 제안: 도메인 쓰기 삭제(값 `arithptr->value` 가 `numeric_info` p/s 를 이미 가짐); p/s 를 도메인에서 읽는 소비자가 있으면 그 소비자를 값으로 돌리거나 셀(`taken`)로 표현.

### P2 (구조는 확실, 크기는 #345 P1~P8 측정이 정한다 — MEAS-01)

- **R2-03 [perf] [BR-04·A59, CC-05] [P2]** 행마다 `qexec_node_domain` → `RESOLVED_CELL` 불변 가드 사슬. `src/query/query_executor.h:138-152`: `vd`·`xasl_state`·`item`·`cell<=0`·`plan`·`cell>n_cells`·항목 포인터 범위 = 분기 7 + 종속 로드 4, 그 뒤에야 `taken[cell]`. develop 은 필드 로드 1회. 자리(전부 행 루프): `fetch.c:847-848` `fetch_peek_arith` 진입부 **2회**(regu 항목·arith 항목) = 모든 산술 노드 × 모든 행; `fetch_peek_dbval_pos` 위치당 2회(diff 5308-5316); `fetch_peek_dbval_slow` TYPE_POSITION 1회; APPLY_COLLATION 1회; `query_aggregate.cpp` `qdata_evaluate_aggregate_list` 집계 × 행 2회(diff 87-88); `query_analytic.cpp` `qdata_evaluate_analytic_func` 진입 2회 + `qdata_analytic_is_plain_sum_avg` 2회 = 행당 4회(diff 34-36, 76-77); 인라인 `fetch_peek_dbval` 의 OPEN regu 는 `qexec_node_took_domain` 로 같은 사슬. 이 조건들은 실행 중 불변 — A59 정의 그대로. 제안 두 단계: (a) 행 경로용 축약 `item != NULL && item->cell > 0 ? (taken[cell-1] ?: compiled) : compiled` 두 분기, 나머지 가드는 `assert`; (b) 근본 — 게이트 끝에서 셀 배열을 컴파일 도메인으로 미리 채워 NULL 폴백을 없애고(`qexec_take_domain` 의 `domain == compiled ? NULL` 규칙 폐기), 산술 노드에 항목 하나만 두면(R2-06) 행 경로가 로드 1회. `fetch_session_read_value`·`fetch_convert_to_branch_decision` 의 `RESOLVED_GATE_NODE`(→ `RESOLVED_OWNS_SLOT` 7 분기) 도 같은 부류.

- **R2-08 [perf] [BR-06·A61, BR-04] [P2]** 비교 행 경로의 이중 디스패치와 site 간접. `src/query/query_evaluator.c` `eval_value_rel_cmp` → `eval_planned_compare` → `eval_site_compare`(kernel AT_GATE 면 `vd`·`xasl_state`·`compares` NULL 3검사 + `resolved.compares[site]` 간접, 행마다) → `eval_compare_planned`(`value[side] >= 0` ×2, NULL ×2, kernel OBJECT/KEYS 검사) → `domain_compare_values`(`domain_resolver.c:1350` kernel **switch 다시**). 행마다 고정 분기 ≥ 7 + out-of-line 호출 2. #368 "A 표준" 항목(kernel·conv[s])의 구체 모양이다. 제안: (a) 스캔 open/술어 컨텍스트 준비 때 AT_GATE 자리의 `&resolved.compares[site]` 를 한 번 캐시(플랜 불변은 지키면서 실행 소유 포인터 배열); (b) kernel 을 게이트가 정한 함수 포인터로(A61: `compare->fn (…)`) 해 switch 둘을 간접호출 1 로. MEAS-06 으로 판정.

- **R2-21 [perf 로드] [PRIORITY 1 · ALLOC-01] [P2, 측정]** `src/query/domain_plan.c` `stx_build_domain_plan` 의 O(n²) 레코드 매칭 셋: 별칭 매칭(4024-4046: TYPE_CONSTANT 레코드 × 전체 레코드), 생산자 매칭(4049-4065: 같은 모양), ref 배정(4114-4140: 바인드 레코드 × 선행 레코드 전체). 언팩(클론 생성)마다 돈다. `IN (?×4096)`: 바인드 4,096 × 레코드 ~1.5만 ≈ 6×10⁷ 포인터 비교/언팩. xcache 클론이 재사용되면 실행당 수치(#368 C2 표)에는 안 보이지만 prepare·첫 실행·클론 miss(문장이 도는 워크로드)에는 보인다. 여기에 레코드마다 `db_private_alloc`(`domain_add_item`, 언팩당 ~1.5만 malloc/free). 제안: `val_pos` → 첫 레코드 배열, `dbvalptr` → 레코드 해시(또는 output 포인터로 정렬 뒤 이분 탐색)로 O(n); 레코드는 bump allocator. 측정: 4,096 바인드 IN 의 prepare + 첫 실행 latency, 클론 miss 워크로드.

- **R2-18 [perf 절차] [CC-08·MEAS-08] [충족 확인]** `object_domain.c` +24K 줄·`domain_plan.c`/`domain_resolver.c` 7.4K 줄이 `libcubrid.so` `.text` 를 키워 실행기 핫 심볼 위상이 움직인다 — #345 본문에 "MEAS-01/02/06/08 … hot symbol 정렬 위상 게이트" 와 e4f86135a 주의가 이미 있다. 추가 요구 없음.

### P3 (정리·직관성)

- **R2-01 [PHYS-01] [P3]** `src/query/domain_plan.h:23` 이 `object_domain_convert.h` 를 포함하지만 그 심볼을 하나도 쓰지 않는다(grep 0). `query_executor.h:37` → `domain_plan.h` 경유로 `<array>`·템플릿 선언이 `query_executor.h` 를 포함하는 모든 TU 에 퍼진다. 제안: `domain_plan.h` 에서 제거, `domain_resolver.c`(19 사용) 에서만 포함.
- **R2-02 [직관성] [P3]** 같은 함수 포인터 타입 두 이름: `DOMAIN_CONV_FUNC`(`domain_resolver.h:29`) / `DOMAIN_CONVERTER`(`object_domain_convert.h:34`). `domain_lookup_converter` 가 `DOMAIN_CTX`(`domain_resolver.h:54`) 와 `DOMAIN_CONVERT_MODE`(`object_domain_convert.h:66`) 두 enum 으로 오버로드 — 호출 자리에서 어느 격자인지 enum 이름으로만 구분된다. 제안: typedef 하나, 어댑터는 `domain_lookup_converter_for_context`.
- **R2-04 [직관성] [P3]** 경계 (b) 오류 idiom 복제: `er_set (…, ER_QPROC_DOMAIN_UNRESOLVED, 4, "execute", "", <항목 인덱스 삼항식 3줄>, pr_type_name (…))` 인라인이 fetch.c 5 · query_executor.c 6 · px_scan_result_handler.cpp 2 · scan_manager.c 1 · btree.c 1 · query_evaluator.c 2 곳. 같은 일을 하는 `qexec_domain_unresolved ()`(`query_executor.h:279`) 가 있고 fetch.c 안에서도 5 곳은 헬퍼, 5 곳은 인라인으로 혼용. 제안: 경계 (b) 는 헬퍼 하나(항목 없는 자리용 오버로드 추가; `assert (false)` 도 헬퍼 안으로).
- **R2-05 [직관성] [P3]** `fetch.c` (diff 1256-1272) `no_value_domain` 블록: `if (!DB_IS_NULL) { domain = no_value_domain; er_set…; goto error; } domain = no_value_domain;` — `goto` 앞 대입은 죽은 문장.
- **R2-06 [직관성·MEM] [P3]** 산술 노드 하나에 계획 항목 둘: regu 항목(`domain_plan.c:1297` `"regu"`) + arith 항목(`:1072` `"arith"`) → 셀 둘, 행마다 조회 둘(R2-03), 항목당 80B + cold 32B. develop 의 두 도메인 필드(`regu->domain`/`arith->domain`)를 그대로 미러한 결과. `fetch_peek_arith` 가 DECIDED 때 `qexec_take_domain` 을 두 항목에 각각 부른다(diff 324-329). 제안: INARITH/OUTARITH regu 는 arith 항목의 ALIAS 로 두고 셀 하나만.
- **R2-09 [직관성] [P3]** `eval_value_rel_cmp` 시그니처 8 인자(`query_evaluator.c:442-445`), 그중 `develop2` 는 optdebug 그림자 검사 전용인데 release 시그니처에 남는다. `eval_assert_planned_compare` 의 기본 인자(`bool asks_comparable = true`)는 `.c` 파일에서 이 코드베이스 관행 밖. 제안: 그림자 검사 인자·헬퍼(`eval_report_planned_*`, `eval_assert_planned_*`, ~120줄)를 NDEBUG 로 묶고 release 시그니처에서 뺀다. 최종 PR 에 그림자 검사를 남길지(D-333 정책)는 사용자 결정.
- **R2-10 [PHYS-11] [P3]** `query_evaluator.c:78-79,91` 파일 스코프 `static const DOMAIN_COMPARE eval_Compare_null = eval_values_decision (…)` — 함수 호출로 초기화되는 정적(동적 초기화). 제안: `eval_values_decision`/`eval_keys_decision` 을 `constexpr`(집합체 초기화, C++14) 로 → `static constexpr`.
- **R2-11 [GLOB-05] [P3]** `scan_manager.c` (diff 2029-2036) `thread_local scan_Sort_search_keys` 를 `key_val_compare` 가 **매 비교마다** 읽는다 — `libcubrid.so` 의 TLS 접근은 general-dynamic 모델이면 `__tls_get_addr` 호출. 범위 K 개 정렬 = K·log K 회(IN(?×4096) ≈ 5×10⁴/실행). 제안: 파일은 C++ 로 컴파일되므로 `std::sort` + 람다 캡처(또는 비교자 객체); thread_local 삭제.
- **R2-12 [BR-04·A59] [P3]** `scan_manager.c` `scan_next_list_scan`(diff 7357-7363) 이 호출마다(= 반환 행마다) `scan_plan_list_scan_domains` 로 `scan_pred.regu_list`·`rest_regu_list` 를 걷고 regu 마다 `qexec_node_open` + `qexec_position_open`(RESOLVED_CELL ×2). develop 도 호출마다 걸었지만(`resolve_domains_on_list_scan`, 타입 비교 1회) 검사가 무거워졌다; 첫 호출 뒤 결과는 불변. 제안: list scan start 로 올려 1회.
- **R2-13 [PAR-14·ALLOC] [P3, 측정]** PX: `qexec_deep_copy_xasl_state`(`query_executor.c:3800-3889`) 가 작업마다 게이트 상태 전체(값 clone + 슬롯표 + 비교 결정 + 원소 표 + 키 결정 블록 + 셀 3배열)를 복사한다. develop 은 `dbval_ptr` 만 clone. 비용 = 작업 수 × 상태 크기. #345 셀에 작업 수 큰 병렬 스캔 변형이 있는지 확인; 근거 없이는 제안 없음(MEAS-01).
- **R2-14 [GLOB-01] [P3]** 행 단위 변환 자리마다 `perfmon_inc_stat (…, PSTAT_QM_NUM_PLANNED_CONVERT)` (`domain_resolver.c:1301,1315`, `scan_manager.c` diff 644, `query_hash_scan.c` diff 305, `fetch.c` diff 152) — 전역 `pstat_Global` 읽기 + 분기 per 변환. 캠페인 계측 10종을 최종 PR 에 남기는가? 남긴다면 게이트/셋업 계수만 남기고 행 단위 증가는 스캔 단위로 hoist. (`btree.c:22147` 은 `perfmon_is_perf_tracking ()` 로 감쌌지만 비용은 같다.)
- **R2-15 [MEM-02/05] [P3, 측정 뒤]** `DOMAIN_COMPARE` 80B(`domain_resolver.h:150-173`): 행이 읽는 필드(kernel·coercion·collation·value[2]·codeset_side·cmp·conv[2]·target[2] ≈ 60B)와 게이트/오류 전용(first·source[2]·converted_first·failed·reason·rank·site·volatile_reads)이 섞여 있고 정렬 보장이 없어 두 캐시라인에 걸친다. 제안: hot 을 앞 48B 로 모으고 `static_assert`. R2-08 (b) 를 하면 hot 은 `fn·cmp·conv[2]·target[2]·collation·value[2]` 뿐.
- **R2-16 [직관성] [P3]** G1 단계 번호가 코드에 4·5·7·7b·8 만 보인다(`query_executor.c:5979-6103`); 1~3·6 은 인터페이스 §3.1 에만 있다. 제안: 함수 머리 주석에 전체 단계표 한 번(1 값 복사 = 5905-5977, 2 GATE 슬롯 도메인, 3 …, 6 seal = 6028).
- **R2-19 [MEAS-07 tail] [P3]** `domain_resolver.c:2130-2259` 키 쌍 표를 첫 사용 질의가 lazy 로 만든다(n ≈ 27 원소 타입 + 3 문자/ENUM 타입 × 등록 collation 수 ≈ 100 → 쌍 ~10⁴, `domain_resolve_comparison` ~2×10⁴ 회, pool 임시 `malloc` 2·n²·80B ≈ 1.6MB 뒤 realloc). 첫 질의 하나의 꼬리 지연. DCL(acquire/release + mutex) 자체는 맞다. 제안: 부트(lang 초기화 뒤)에서 만들기.
- **R2-20 [직관성] [P3]** 긴 함수: `stx_build_domain_plan` 406줄(12 단계가 한 절차; 4307-4386 의 ~80줄은 ctx 목록 해제 → `domain_load_context_free`; 별칭/생산자 연결·ref 배정을 이름 있는 단계로), `domain_walk_regu` 284줄(F_ELT/문자 함수 링크 1370-1436 의 66줄 → `domain_link_string_function`), `domain_walk_xasl` 263줄, `domain_resolve_function` 220줄(NULL 전파 switch + 결과 switch — 연산자별 표 하나로).
- **R2-22 [직관성] [P3]** `object_domain.c:20589-26881` `domain_convert_table` — 6.3K 줄 손으로 쓴 3차원 집합체 초기화(5,043 셀). `#if !defined (SERVER_MODE)` 셀 249 개 중 **231 개는 양 분기가 같다**(죽은 전처리). DB_TYPE 하나 추가 = 3 모드 × 2 방향 × N 행 편집. 제안: 숫자 표(`tp_make_numeric_convert_table`, `index_sequence` 생성)처럼 규칙 목록 → constexpr 생성; 최소한 동일 분기 `#if` 231 개 제거.
- **R2-23 [직관성] [P3]** `query_analytic.cpp` 첫 값 분기(diff 440-570): 날짜/시간 8 case(DATE·DATETIME·DATETIMETZ·DATETIMELTZ·TIMESTAMP·TIMESTAMPTZ·TIMESTAMPLTZ·TIME)가 전부 `domain = tp_domain_resolve_default (opr_type)` 로 같다 — `if (TP_IS_DATE_OR_TIME_TYPE (opr_type))` 한 줄. develop 모양이지만 이 캠페인이 블록을 다시 짰다(`planned` 래핑·재들여쓰기).
- **R2-24 [MEAS 위생] [P3]** `perf_monitor.h` (diff 62-77): 새 카운터 10종은 `ATOMIC_INC_64` 로 트랜잭션 공유 배열에 더한다(PX 워커 포함, 같은 캐시라인 — MEM-03/PAR-01). 수집이 켜진 상태(`@collect_exec_stats=1`)의 PX 셀 타이밍을 카운터 자체가 왜곡한다. #345: ms 런과 카운터 런을 분리.

### 긍정(유지할 것)

- `FETCH_GATE_READING` enum + `fetch_arith_gate_reading` (`fetch.c:78-128`): develop 의 FETCH_ALL_CONST/NOT_CONST 플래그 춤(−230줄)과 F_ELT/F_INSERT_SUBSTRING 상수성 판정 삭제 — 게이트 뒤 fetch 가 "결정을 읽는다" 로 읽힌다.
- `scan_key_state` 단일 블록 + `static_assert` 정렬(`scan_manager.c` diff 207-217), `qexec_alloc_resolved_domains` 단일 블록(`query_executor.c:3693-3783`), `domain_plan_alloc` 이 언팩 arena(`stx_alloc_struct`) 사용 — ALLOC-01/02.
- `scan_dbvals_to_midxkey`: 3 루프 + `retry: goto` 에서 1 루프 + `scan_key_column` 규칙 하나로. `qdata_plan_hscan_keys`: open 1회 규칙 결정 + 행은 switch 하나.
- `domain_key_pairs` 의 DCL(atomic acquire/release + mutex) 정확(PAR-02). `btree_compare_key_with`: `search_keys == NULL` 경로가 develop 과 동일하게 남고 함수 포인터로 midxkey 원소 비교 주입.
- compat/base: `date_conversion_error`(5 필드 스택 객체) + `_core`/wrapper 분리 — BR-08(오류 플래그 + cold 핸들러) 그대로(474 `_core`, 561 leaf). `numeric_coerce_value_to_num<SRC>` if-constexpr 템플릿 + legacy switch 래퍼 — 셀 안 타입 switch 0(D-328-01). 숫자 변환 표는 `index_sequence` 로 컴파일 시점 생성.
- 파서: `pt_is_op_hv_late_bind` → `pt_is_op_gate_dependent` 이름·주석이 새 의미를 말한다; `pt_gate_limit_regu` 헬퍼 하나로 LIMIT 5 자리 통일.

## 헤더·물리 설계 관찰

- `domain_plan.h` → `domain_resolver.h` → `object_domain.h`; `query_executor.h` → `domain_plan.h`(Has-A: `xasl_state::resolved`, 정당). `object_domain_convert.h` 포함은 R2-01.
- `regu_var.hpp`/`xasl_*.hpp`: `original_domain` 필드 → `domain_plan_item *`(같은 8B, 스트림 불변) — D-355-08 그대로. `alsm_eval_term` 40B(F-352-10 주석 있음).
- `scan_manager.h`: `INDX_SCAN_ID`/`PARALLEL_INDEX_SCAN_ID` 미러 필드 3개 + `static_assert (offsetof …)`.

## 반영 제안(우선순위)

1. R2-07 (P1, 작음).
2. R2-03 (a) + R2-06 + R2-12 (행 경로 A59 — 한 묶음), R2-08 (a)/(b), R2-21 (로드 O(n)). 각각 #345 셀로 크기 판정.
3. P3 정리: R2-01·02·04·05·09·10·11·16·20·22·23 (동작 불변, 커밋 1개로 묶기 가능), R2-14·19·24 는 사용자 결정(계측 잔존·부트 초기화·측정 위생).
