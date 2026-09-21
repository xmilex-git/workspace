# 서버 실행 하위의 도메인·collation 결정·보정·복원 지점 — 전수 인벤토리(삭제 목록 + 게이트 요구사항)

지도: xmilex-git/workspace#312 · 티켓: #314 · 작성 2026-09-22 · 기준: CUBRID/cubrid `develop` `cad27172b`(워크트리 `~/dev/cubrid-worktree/dpin`)
짝 티켓: #313(클라이언트 파서 규칙, `domain-pin-rules-parser.md`) · #321(서버 측 coerce·산술·비교·집계·키 변환 **규칙**) — 이 문서는 **지점(어디서·언제·무엇으로 결정하는가)** 만 다루고, 각 지점이 적용하는 변환 규칙의 옳고 그름은 #321·#317 이 다룬다.
경험치 렛저(`domain-pin-lessons.md`) L-40~L-51 대응은 §6 표에 있다.

인용 표기: `fe:NNNN` = `src/query/fetch.c`, `qx:NNNN` = `src/query/query_executor.c`, `qa:NNNN` = `src/query/query_aggregate.cpp`,
`qn:NNNN` = `src/query/query_analytic.cpp`, `qe:NNNN` = `src/query/query_evaluator.c`, `sm:NNNN` = `src/query/scan_manager.c`,
`lf:NNNN` = `src/query/list_file.c`, `bt:NNNN` = `src/storage/btree.c`, `hj:NNNN` = `src/query/query_hash_join.c`,
`px:NNNN` = `src/query/parallel/px_scan/px_scan_result_handler.cpp`, `pxs:NNNN` = `src/query/parallel/px_scan/px_scan.cpp`,
`sx:NNNN` = `src/query/stream_to_xasl.c`, `sp:NNNN` = `src/xasl/xasl_spawner.cpp`, `qo:NNNN` = `src/query/query_opfunc.c`,
`ss:NNNN` = `src/session/session.c`, `mc:NNNN` = `src/method/method_callback.cpp`.

빈도 어휘: **행당** = 스캔/fetch 되는 행마다 · **첫값까지 행당** = 첫 non-NULL 값을 볼 때까지 행마다 재시도 · **실행당** = XASL(하위 블록 포함) 실행 1회 · **패스당** = 정렬/그룹/분석 패스 1회 · **range당** = 인덱스 키 range 생성 1회(상관·조인 키는 외부 행마다 반복) · **키당** = 인덱스 키 비교/추가 1회.

---

## 0. 한 장 요약 — 실행 하위가 늦은 바인딩을 처리하는 현행 파이프라인

```
컴파일(클라이언트)   pt_make_regu_hostvar: MAYBE 슬롯 → regu.domain = DB_TYPE_VARIABLE (또는 collation_flag ≠ NORMAL)   [#313]
                     파생 소비자(산술 결과·리스트 컬럼·위치 서술자·누산기)도 VARIABLE 로 전파
load(서버)           stx_*: original_domain = domain 저장                                  sx:5615 5861 5874 5982 6259 6844
실행 진입            qexec_execute_query: vd.dbval_ptr = 클라이언트가 보낸 바인드 값 그대로(서버 측 캐스트 0)     qx:17456
                     ┌ 게이트 후보 지점: mainblock_internal 이 aptr_list 를 도는 qx:16538 **이전**, PX 스폰 이전
행마다               fetch_peek_dbval_slow: VARIABLE regu 도메인 ← 값 도메인 (FAST_PEEK 차단)      fe:5225 5241 5273
                     fetch_peek_arith: 도메인 탈착(NULL) → 값으로 재확정 → 오류 시 원복          fe:1316 4465 4603
                     eval_value_rel_cmp: 값 타입 분기 + in-place coerce + compare_with_error       qe:220~276
첫 튜플              qfile_update_domains_on_type_list: 리스트 컬럼 도메인 ← outptr regu 도메인(미해결이면 다음 튜플)   qx:991 lf:7041
첫값까지             qexec_resolve_domains_for_aggregation / qdata_evaluate_analytic_func 첫값 블록  qx:21504 qn:188 696
패스 진입            resolve_domains_on_sort_list / for_group_by / analytic_state / list_scan     qx:21176 21223 23130 sm:8216
키 range             scan_dbvals_to_midxkey: strict coerce 실패 → 값 도메인 setdomain            sm:2020~2110
PX                   워커 클론이 각자 resolve → 루트로 역전파                                    px:926 2145 2683 pxs:1977
실행 종료            qexec_clear_*: domain = original_domain (클론 재사용 대비 원복)               qx:1484 1519 1773 2301 2356
```

**핵심 관찰 세 가지.**
1. 서버는 바인드 값을 **한 번도 슬롯 도메인으로 변환하지 않는다**. `TYPE_POS_VALUE` fetch 는 `vd->dbval_ptr + pos` 포인터를 그대로 돌려준다(fe:4745~4757). 변환은 전부 "값 타입을 보고 도메인을 값에 맞추는" 방향(도메인 ← 값)이고, 값 ← 도메인 방향은 CAS 측 `pt_set_host_variables`(#313) 뿐이다. 따라서 게이트(D-M4)는 **새 방향**을 추가하는 것이고, 아래 지점들은 그 반대 방향이므로 전부 폐기 가능하다.
2. `TP_DOMAIN_TYPE(d) == DB_TYPE_VARIABLE || TP_DOMAIN_COLLATION_FLAG(d) != TP_DOMAIN_COLL_NORMAL` 한 조건문에 타입 축과 collation 축이 섞여 있다(L-47). 실행 하위에서 이 쌍 조건은 **26곳**(§4 표) — 타입 축만 지우면 collation 축 26곳이 그대로 남는다.
3. `hostvar_late_binding` 파라미터의 서버 측 소비자는 **0** 이다(`type_checking.c:19714`, `query_rewrite.c:501`, `name_resolution.c:3805` 전부 클라이언트). 서버 하위는 파라미터가 아니라 **도메인이 VARIABLE 인지**로만 분기한다 → 파라미터를 지워도 서버 코드는 달라지지 않고, 서버 코드를 지우려면 컴파일이 VARIABLE 을 내보내지 않아야 한다.

---

## 1. 삭제 목록 — 지점별 전수표

열: **빈도** / **결정 입력**(무엇을 보고 정하는가) / **대체**(계획+게이트로 대체 가능한가) / **게이트 요구**(§2 G-번호) / **렛저**.
"대체" 값: **계획** = 컴파일 변환 계획이 도메인을 싣고 지점은 삭제 · **게이트** = 게이트 값 변환으로 도달 불가가 되어 삭제(경계 assert 로 교체) · **규칙표** = 값·행 의존 **의미**가 걸려 있어 #317/#321 이 행을 정해야 삭제 여부가 갈림 · **유지** = 도메인 결정이 아니라 연산 구현(값 타입 dispatch)이라 삭제 대상 아님.

### 1.1 fetch — 식 평가

| ID | 지점 | 빈도 | 결정 입력 | 대체 | 게이트 요구 | 렛저 |
|---|---|---|---|---|---|---|
| S-01 | `fetch_peek_arith` 도메인 탈착 fe:1316(VARIABLE→NULL) → 결과 값으로 재확정 fe:4465~4477 → 오류 시 원복 fe:4603 | 행당 | 산술 **결과 값** | 계획 | G-03(a) | L-42 L-51 |
| S-02 | 같은 함수, `collation_flag ≠ NORMAL` 이면 결과 값에서 도메인 재확정 fe:4479~4490 | 행당 | 결과 값의 collation | 계획(collation 축) | G-04 | L-47 |
| S-03 | `T_ADD`/`T_STRCAT` oracle-empty-string 결과 타입 검사 fe:863, fe:1330 (`VARIABLE || 문자형` 이면 우측 fetch) | 행당 | regu 도메인 | 계획 | G-03(a) | L-51 |
| S-04 | `T_NVL`/`T_COALESCE` fe:3306~3313 · `T_NVL2` fe:3346~3365 · `T_NULLIF` fe:3871~3879 · `T_LEAST` fe:3921~3930 · `T_GREATEST` fe:3952~3961: `target_domain == NULL`(=S-01 이 탈착한 VARIABLE) 이면 두 값에서 `tp_domain_resolve_value`+`tp_infer_common_domain` | 행당 | **두 피연산자 값** | 규칙표 → 계획 | G-03(a), G-08(1) | L-51 |
| S-05 | `fetch_peek_dbval_slow` fe:5225~5229: `VARIABLE || collation_flag` 이면 `regu_var->domain ← 값 도메인` | 행당(FAST_PEEK 가 fe:5273 에서 차단되므로 슬롯 regu 는 매번 slow 경로) | 슬롯 **값** | 계획 | G-01 G-03(b) | L-51 |
| S-06 | 같은 함수 `TYPE_REGUVAL_LIST`(다중 행 VALUES) fe:5233~5262: 현재 행 regu 도메인 ← 값, 첫 행과 타입·collation 비교해 `ER_QPROC_INCOMPATIBLE_TYPES`/`ER_QSTR_INCOMPATIBLE_COLLATIONS` | 행당 | 첫 행 값 vs 현재 행 값 | 규칙표 → 계획(다중 행 VALUES 슬롯 부류, #313 A) | G-03(b), G-08(2) | L-10~L-21 |
| S-07 | `T_EVALUATE_VARIABLE` fe:4023: `session_get_variable` 이 저장 시점 타입의 값을 그대로 복제 ss:2081~2104; regu 는 `FETCH_NOT_CONST` | fetch 마다 | 세션변수 **저장값 타입** | 규칙표(읽기 타입 행) → 게이트 | G-08(3) | L-10~L-21 |
| S-08 | `qdata_strcat_dbval` qo:6446~6452 등 `qdata_*_dbval` 계열의 값 타입 dispatch(`DB_VALUE_DOMAIN_TYPE` 로 분기해 교차 캐스트) | 행당 | 피연산자 값 타입 | **유지**(연산 구현). 게이트 뒤엔 값 타입 = 계획 도메인이므로 분기가 결정적이 됨 | G-01 | L-49 |

### 1.2 비교·조건

| ID | 지점 | 빈도 | 결정 입력 | 대체 | 게이트 요구 | 렛저 |
|---|---|---|---|---|---|---|
| S-09 | `eval_value_rel_cmp` qe:220~262: rhs 가 `FETCH_ALL_CONST` 이고 값 타입이 다르면 (숫자·문자→DOUBLE / 날짜·문자→날짜 / 숫자 일반화) **in-place** `tp_value_coerce`(힙 전환 포함) | 행당(비교마다 타입 검사; 상수 coerce 자체는 1회) | 두 값 타입 | 게이트(비교 도메인으로 변환 뒤 `cmpval` 직접) + 규칙표(문자 vs 숫자 비교 방향) | G-01 G-08(4) | L-06 L-51 |
| S-10 | 같은 함수 qe:271/276 `tp_value_compare_with_error(…, do_coercion=1)`: 타입 불일치 시 내부 임시 강제변환 | 행당 | 두 값 타입 | 게이트 → 같은 타입이면 coercion 경로 0회(경계 assert) | G-01 G-07 | L-51 |
| S-11 | `qexec_topn_cmpval` qx:27786: 정렬 키 도메인이 VARIABLE 이면 `tp_value_compare`(coercion) 로 폴백 | 행당(top-N 힙 비교) | 정렬 키 도메인 | 계획 | G-03(c) | L-44 |
| S-12 | `btree_compare_key` bt:22095~22119: 키 타입이 비교 불가 조합이면 `tp_value_compare_with_error` 폴백 | 키당 | 키 값 타입 vs 인덱스 도메인 | 게이트(키 변환 뒤 도달 불가) → 경계 | G-05 G-07 | L-45 |

### 1.3 리스트 파일·정렬·그룹

| ID | 지점 | 빈도 | 결정 입력 | 대체 | 게이트 요구 | 렛저 |
|---|---|---|---|---|---|---|
| S-13 | `qfile_update_domains_on_type_list` lf:7041~7115 (호출 qx:991 `qexec_generate_tuple_descriptor`, px:888): 리스트 컬럼 VARIABLE 이면 outptr regu 도메인으로; regu 도 VARIABLE 이면 `is_domain_resolved=false` 로 다음 튜플 재시도 | 첫값까지 행당 | outptr regu 도메인(= S-05 가 값에서 정한 것) | 계획(리스트 컬럼 도메인 = 생산자 계획 도메인) | G-03(d) | L-41 L-51 |
| S-14 | `qdata_get_valptr_type_list` qo:~424~470 / ~628(호출 qx:5527 15365 15417, sm:726, px:240): 리스트 type_list 를 outptr regu 도메인에서 생성 — VARIABLE 을 그대로 실어 S-13 의 씨앗이 됨 | 실행당 | regu 도메인 | 계획 + **경계 (b)** 설치 위치 | G-07 | L-48 |
| S-15 | `qfile_unify_types` lf:910~921 (호출 lf:2775 집합연산, lf:3396, qx:18799 재귀 CTE): 한쪽 리스트 컬럼이 VARIABLE 이면 상대 도메인 채택, `assert_release(tuple_cnt == 0)` | 실행당 | 상대 리스트 도메인 | 계획(UNION/CTE 컬럼 도메인 컴파일 확정, #313 문맥 없는 슬롯 부류) | G-03(d) | L-41 |
| S-16 | `qfile_initialize_sort_key_info` lf:4505: 정렬 키 도메인 VARIABLE 이면 리스트 type_list 의 `cmpdisk` 사용 | 패스당 | 리스트 컬럼 도메인 | 계획 | G-03(c) | L-51 |
| S-17 | `qexec_resolve_domains_on_sort_list` qx:21176~21205: ORDER BY(qx:4187) · GROUP BY(qx:21233) · 분석 정렬(qx:22465) 위치 서술자 도메인 ← 참조 regu 도메인 | 패스당 | outptr regu 도메인 | 계획(위치 서술자 도메인 = 생산자 도메인) | G-03(c) | L-41 L-51 |
| S-18 | `qexec_resolve_domains_for_group_by` qx:21223~21470: g_regu_list · g_hk_sort_regu_list · 집계 피연산자/도메인/누산기(MIN/MAX/SUM, GROUP_CONCAT 은 비문자면 VARCHAR qx:21348) · g_outptr_list · 해시 키 도메인 · part/sorted_part 리스트 type_list | 실행당(GROUP BY 진입 qx:5506) | outptr regu 도메인 | 계획 | G-03(c)(e)(f) | L-41 L-43 L-51 |
| S-19 | `qexec_initialize_analytic_state` qx:23130~23145 `resolve_domain:` a_regu_list `TYPE_POSITION` 도메인 ← 리스트 type_list | 패스당 | 리스트 컬럼 도메인 | 계획 | G-03(c) | L-51 |
| S-20 | `resolve_domains_on_list_scan` sm:8216~8300 + `resolve_domain_on_regu_operand` sm:8312: list scan 의 scan_pred/rest regu(`TYPE_POSITION`) 와 비교 predicate 피연산자(`TYPE_CONSTANT`) 도메인 ← 리스트 type_list; 호출은 `scan_next_list_scan` sm:7163, `scan_build_hash_list_scan` sm:8795 진입마다 | 스캔 진입당(상관 list scan 은 외부 행마다 재진입 → 사실상 행당) | 리스트 컬럼 도메인 | 계획 | G-03(c)(d) | L-51 |
| S-21 | `qexec_execute_connect_by` qx:17975~18020: 프로브 regu 가 float NUMERIC 이면 rest_regu 의 고정 p/s 로 도메인 사본 교체 | 실행당 | rest_regu 도메인(값 아님 — **컴파일 도메인 불일치 보정**) | 계획(컴파일이 프로브 도메인을 정확히) | G-03(c) | L-51 |
| S-22 | `qdata_hash_join` 도메인 준비 hj:1015~1040: outer/inner 리스트 type_list 에서 공통 타입 추론, coerce 도메인 | 실행당 | 리스트 컬럼 도메인 | 계획(조인 키 공통 도메인 컴파일 확정) | G-03(c) | — |

### 1.4 집계·분석 함수

| ID | 지점 | 빈도 | 결정 입력 | 대체 | 게이트 요구 | 렛저 |
|---|---|---|---|---|---|---|
| S-23 | `qexec_resolve_domains_for_aggregation` qx:21504~21820 (호출 `qexec_end_one_iteration` qx:1219 BUILDLIST · qx:1333 BUILDVALUE, `*resolved` 가 0 이면 다음 튜플 재호출): 피연산자 **값**으로 `agg_p->domain`/`opr_dbtype` (문자 SUM/AVG→DOUBLE qx:21610, 비문자 GROUP_CONCAT→VARCHAR qx:21614, 그 외 값 도메인 qx:21618) → 누산기 value/value2 도메인(SUM/AVG 는 값 타입별 NUMERIC/DOUBLE/기본 qx:21640~21662) → MEDIAN/PERCENTILE 비숫자·비날짜면 DOUBLE→DATETIME→TIME **시도 캐스트** qx:21686~21770 → distinct/sort 리스트 도메인 ← 값 qx:21780~21791 → 누산기 `db_value_domain_init` | 첫값까지 행당 | 첫 non-NULL **값** | 계획(누산기·결과 도메인 = 피연산자 계획 도메인에서 컴파일 계산) + 규칙표(MEDIAN 시도 캐스트 순서, 문자 SUM 규칙) | G-03(e) G-08(5) | L-43 L-51 |
| S-24 | BUILDVALUE 출력 regu 도메인 ← 집계 도메인 qx:1360~1380 | 실행당 | agg domain | 계획 | G-03(e) | L-41 |
| S-25 | `qdata_finalize_aggregate_list` qa:1873~1879: distinct/sort 리스트 정렬 키 도메인 ← 리스트 type_list | 패스당 | 리스트 도메인 | 계획 | G-03(c) | L-43 |
| S-26 | `qdata_update_agg_interpolation_func_value_and_domain` qa:3343~3346: MEDIAN/PERCENTILE 도메인 ← 값 타입 | 행당 | 값 타입 | 계획 + 규칙표 | G-03(e) G-08(5) | L-43 |
| S-27 | `qdata_evaluate_analytic_func` qn:188~259: `opr_dbtype VARIABLE || collation_flag` 이고 값이 non-NULL 이면 함수별 기본 도메인(COUNT→BIGINT, AVG/STDDEV→DOUBLE, SUM 숫자면 값 도메인 아니면 DOUBLE, MEDIAN 숫자면 DOUBLE 아니면 값, 기타 값) → 피연산자 coerce → `func_p->value` init → distinct 리스트 도메인 ← 함수 도메인; 이후 행은 리스트 도메인으로 coerce qn:284~292 | 첫값까지 행당 + 행당 coerce | 첫 non-NULL 값 | 계획 + 규칙표 | G-03(e) G-08(5) | L-43 |
| S-28 | 같은 함수 `is_first_exec_time` 첫값 블록 qn:683~792: 보간 함수 도메인을 첫 값 타입 switch 로(숫자 → 상수 피연산자/PERCENTILE_DISC 면 값 도메인, 아니면 DOUBLE; 날짜/시간 8종은 각각) | 첫값 1회 | 첫 값 타입 | 계획 | G-03(e) | L-43 |
| S-29 | `qdata_analytic_is_plain_sum_avg` qn:59 / `qdata_agg_is_plain_sum_avg`: `opr_dbtype VARIABLE || collation_flag` 이면 빠른 경로 차단 | 행당 검사 | 도메인 | 계획(조건 자체 삭제) | G-03(e) | L-51 |

### 1.5 인덱스 키

| ID | 지점 | 빈도 | 결정 입력 | 대체 | 게이트 요구 | 렛저 |
|---|---|---|---|---|---|---|
| S-30 | `scan_dbvals_to_midxkey` sm:1871~2280 (경로: `scan_get_index_oidset` sm:2690 → `scan_regu_key_to_index_key` sm:2328): 키 값을 인덱스 도메인으로 `tp_value_coerce_strict`; 실패하거나 NUMERIC/CHAR/BIT 정확 일치가 아니면 **값 도메인**으로 새 setdomain 을 만들어 `prebuilt_midxkey_domains[range]` 에 캐시(sm:2251); 첫 컬럼이 NULL 도메인이면 `retry` sm:2079~2085 | range당(`scan_get_index_oidset` 는 sm:536 ISS · sm:5113 · sm:5660 에서 range/외부 행마다) | 키 **값** vs 인덱스 도메인 | 계획: 키 변환 전략(AS_IS / 값 p/s / strict / 불가)을 스캔 준비 1회로, 바인드 불변 키는 실행당 1회 변환, 상관·조인 키는 range 마다 **값 변환만**(전략 재추론 없음) + 규칙표(`int_col = 1.5` 정확성 유지 여부) | G-05 G-08(6) | L-45(a)(b)(c)(f)(g) |
| S-31 | `scan_get_next_iss_value` sm:612, sm:629: ISS 스텝마다 key1/key2 첫 피연산자를 `TYPE_DBVAL` 로 바꾸고 도메인 ← `last_key` 값 도메인 | ISS 스텝당 | 마지막 키 값 | 계획(첫 컬럼 도메인 = 인덱스 스키마 `key_type->setdomain`) | G-05 | L-45(d)(e) |
| S-32 | `btree_range_opt_check_add_index_key` bt:22282~22320: MRO `sort_col_dom` 을 `tp_Null_domain` 으로 시딩하고 키 추가마다 NULL 인 컬럼을 키 값 도메인으로 채움 | 키당(`has_null_domain` 동안) | 키 값 | 계획(인덱스 스키마 오름차순 사본으로 시딩) | G-05 | L-44 |
| S-33 | `scan_check_user_given_keylimit_overflow` sm:880~886 `assert(NUMERIC)`: **계획 도메인을 믿는 소비자** — 값이 계획 도메인과 다르면 노출 | 실행당 | 계획 도메인 | 유지(게이트 뒤 불변식으로 보호됨; auto-param 도메인이 값보다 넓은 경우 L-22 를 규칙표가 먼저 좁혀야) | G-01 G-08(7) | L-49 |

### 1.6 PX 워커·XASL 클론

| ID | 지점 | 빈도 | 결정 입력 | 대체 | 게이트 요구 | 렛저 |
|---|---|---|---|---|---|---|
| S-34 | 워커별 집계 도메인 resolve: px:926 (HS_ACCEPT_ALL g_agg), px:2145 (BUILDVALUE_OPT write), pxs:1977 (`m_g_agg_domain_resolve_need`) → `qexec_resolve_domains_for_aggregation_for_parallel_*` qx:21474/21484 | 워커별 첫값까지 행당 | 워커가 본 첫 값 | 계획 상속(D-M3: 워커 결정 0) | G-06 | L-46 |
| S-35 | 워커→루트 역전파 px:2683~2687: `orig_agg_p->opr_dbtype == VARIABLE && cur_agg_p != VARIABLE` 이면 도메인 복사 | 워커 병합당 | 워커 도메인 | 계획 상속 | G-06 | L-46 |
| S-36 | 행당 누산기 폴백 px:1655, 1750, 1979, 2000: `value_dom == NULL || tp_Null_domain` 이면 값 도메인 | 행당 | 값 | 계획 | G-03(e) G-06 | L-43 L-46 |
| S-37 | 리스트 도메인 워커 확정 `update_domains_on_type_list_by_val_list` px:58~80 (호출 px:1091, px:888), atomic `m_type_list[i].store` 로 공유 | 첫값까지 튜플당 | 워커 val_list 값 도메인 | 계획(리스트 컬럼 도메인이 스트림에 실려 워커도 같은 값을 읽음) | G-03(d) G-06 | L-46 |
| S-38 | 클론 원복 `qexec_clear_arith_list` qx:1484 · `qexec_clear_regu_var` qx:1519 · `qexec_clear_pos_desc` qx:1773 · `qexec_clear_analytic_function_list` qx:2301 · `qexec_clear_agg_list` qx:2356: `domain = original_domain`, `opr_dbtype = original_opr_dbtype`; 원본은 load 시 sx:5615 5861 5874 5982 6259 6844, PX 스폰 시 sp:279 400 566 | 실행 종료당(`XASL_DECACHE_CLONE` 여부와 무관) | — | 계획(플랜 불변 + 실행 상태 분리 → `original_domain`/`original_opr_dbtype` 필드와 원복 코드 삭제) | G-02 | L-42 |
| S-39 | 힙 전환 패턴 `REGU_VARIABLE_CLEAR_AT_CLONE_DECACHE` → `db_change_private_heap(thread_p, 0)` qe:227~231, qx:21716~21719: 클론 공유 상수를 in-place coerce 할 때 소유 힙을 바꿈 | 변환당 | — | 게이트(값 변환은 게이트가 연결 스레드 XASL_STATE 소유 버퍼에 1회; 실행 중 in-place coerce 0) | G-01 G-06 | L-46 |

### 1.7 기타(INSERT 기본식·세션·PL·캐시)

| ID | 지점 | 빈도 | 결정 입력 | 대체 | 게이트 요구 | 렛저 |
|---|---|---|---|---|---|---|
| S-40 | `qexec_generate_row_default_expr` qx:13110~13127 / `qexec_execute_insert` qx:13650~13660: 컬럼이 비문자면 `db_to_char` 결과 도메인을 포맷 값(`format_val`)에서 결정 | 행당(INSERT 행) | 포맷 **값** | 규칙표(TO_CHAR 값 슬롯 부류) | G-08(8) | L-51 |
| S-41 | PL/CSQL 바인드 mc:660~680: 마커의 `expected_domain` 이 NULL 이면 `pt_node_to_db_domain`, 그래도 NULL 타입이면 값 NULL — **서버 실행 하위에는 별도 지점 없음**(prepare 시 타입 소실은 #313 의 문제) | prepare당 | 파서 expected_domain | 규칙표(#313 PL 인자 부류) | G-08(3) | L-10~L-21 |
| S-42 | 함수 인덱스·필터 predicate 스트림 `fpcache_claim`/`filter_pred_cache.c`: 게이트가 없는 load 경로, 오류 삼킴 | load당 | — | 경계(잔여 VARIABLE 이면 load 거부) | G-07 | L-40 L-48 |
| S-43 | `hostvar_late_binding` 파라미터: 서버 측 소비자 0 | — | — | 클라이언트 측 deprecated 처리(#320 마무리 항목) | — | — |

---

## 2. 게이트 요구사항 목록 — 위 지점을 지우면 게이트·계획이 대신 제공해야 하는 것

| ID | 요구 | 근거 지점 | 비고(아키텍처 #318 / 인터페이스 #323 입력) |
|---|---|---|---|
| G-01 | **값 변환 1회**: `xasl_state->vd.dbval_ptr[i]`(호스트 변수·auto-param) 를 계획의 **바인드 도메인**(타입+p/s+codeset+collation)으로 변환. 위치 = `qexec_execute_query` 가 `xasl_state` 를 만든 직후, `qexec_execute_mainblock_internal` 이 aptr_list 를 도는 qx:16538 **이전**, PX 태스크 스폰 이전. 변환 결과의 소유자 = 연결 스레드의 `XASL_STATE`(값 버퍼 자체를 바꾸거나 별도 배열) | S-05 S-09 S-10 S-12 S-33 S-39 | 변환 뒤 불변식 "값 타입 = 계획 도메인" 이 성립해야 S-08·S-33 같은 값 타입 dispatch/계획 신뢰 소비자가 결정적이 된다. 변환 실패 = 실행 전 오류(행 중간 오류 없음). 서버가 값을 바꾸므로 클라이언트 `pt_set_host_variables` 캐스트와의 이중 변환 관계는 #323 이 정한다. |
| G-02 | **플랜 불변**: 실행 중 XASL 트리(regu/arith/agg/analytic/pos_descr/list type_list)의 도메인 필드에 쓰지 않는다. 실행별 상태는 `XASL_STATE` 에만. 그러면 `original_domain`/`original_opr_dbtype` 과 원복 5곳, PX 스폰의 원본 복사 3곳이 사라진다 | S-38 S-39 | 클론·xcache·PX 세 로드 경로(L-40) 모두 같은 스트림에서 계획을 읽는다. |
| G-03 | **계획이 실어야 하는 도메인 항목**(전부 컴파일 확정, VARIABLE·`COLL_LEAVE` 없이): (a) 산술/함수 regu 결과 도메인 (b) 슬롯 regu(`TYPE_POS_VALUE`, auto-param `TYPE_DBVAL`) 도메인 (c) 위치 서술자(ORDER BY·GROUP BY·분석 정렬·list scan·해시 키·조인 키·connect-by 프로브)·정렬 키 도메인 (d) 리스트 파일 컬럼 도메인(outptr → type_list; 하위질의·CTE·MERGE·INSERT…SELECT·집합연산 포함) (e) 집계/분석 함수의 `domain`·`opr_dbtype`·누산기 value/value2·distinct/sort 리스트 도메인 (f) GROUP BY 해시 part/sorted_part 리스트 type_list | S-01 S-03 S-05 S-11 S-13~S-29 S-36 S-37 | 파생 소비자까지 계획에 포함해야 게이트 순회가 필요 없다(L-41). 계획 항목의 자료구조는 #323 design-it-twice. |
| G-04 | **collation 확정**: 슬롯·문자 연산자 결과·리스트 컬럼의 `collation_flag` 를 컴파일에서 `COLL_NORMAL` 로 확정(LEAVE 계약 폐기 여부는 #322). 폐기하지 않으면 §4 의 26곳 쌍 조건 중 collation 축이 그대로 남는다 | S-02 S-05 §4 | D-M4(게이트에서 collation 까지 확정) |
| G-05 | **인덱스 키 변환 계획**: range 마다가 아니라 스캔 준비 1회에 전략 확정; 바인드 불변 키는 게이트/스캔 open 에서 1회 변환, 상관·조인·skip-scan 키는 range 마다 값 변환만; key1/key2 기술 분리; ISS 내림차순 bound 이동용 계획 쌍; ISS 첫 컬럼·MRO 정렬 컬럼 도메인은 인덱스 스키마(`key_type`)에서, XASL(`INDX_INFO`)에 실어 카탈로그 재계산 회피; `prebuilt_midxkey_domains` 해제 | S-12 S-30 S-31 S-32 | L-45 7항목 그대로. |
| G-06 | **PX 상속**: 워커 클론은 계획을 상속하고 값은 루트가 변환한 `vd` 를 복제(qx:3692~3714 의 clone 경로)해 받는다; 워커는 도메인을 결정하지도 역전파하지도 않는다; 게이트가 만든 값의 소유 스레드·해제 시점을 계획/상태에 명시(교차 mspace free 금지) | S-34~S-37 S-39 | D-M3. |
| G-07 | **검증 경계**: (a) load 경계 — `stx_*` 에서 계획 밖 VARIABLE 잔여를 거부하되 설계상 VARIABLE 인 예외 목록(`TYPE_REGU_VAR_LIST` 포장 노드·분석 윈도우 정렬 키·집합 연산 컬럼, L-48(a))을 표로; 함수 인덱스·필터 predicate 는 게이트가 없으므로 load 거부 + `fpcache_claim` 오류 삼킴 수정 (b) 실행 경계 — `qdata_get_valptr_type_list` 에 assert + release 오류, `fetch_peek_dbval_slow`·`btree_compare_key` 폴백·`eval_value_rel_cmp` coercion 경로에 "도달 0" assert | S-10 S-12 S-14 S-42 | 경계가 곧 "행당 결정 0회" 의 증거(마이크로벤치 #316 과 짝). |
| G-08 | **규칙표가 먼저 정해야 게이트가 대체할 수 있는 값 의존 의미**(#317/#321 행): (1) NVL/COALESCE/NVL2/NULLIF/LEAST/GREATEST 결과 공통 타입 (2) 다중 행 VALUES 슬롯의 행 간 타입·collation 일치 규칙 (3) 세션변수 읽기 타입·PL 인자 타입 (4) 문자 vs 숫자/날짜 비교의 변환 방향 (5) SUM/AVG 문자→DOUBLE, GROUP_CONCAT→VARCHAR, MEDIAN/PERCENTILE 시도 캐스트 순서, 분석 함수별 기본 도메인 (6) 키 strict 변환 실패 시 값 도메인 키 유지(`int_col = 1.5` 정확성) 여부 (7) auto-param 슬롯 도메인이 값보다 넓은 경우(L-22) (8) TO_CHAR 포맷 값에서 결과 도메인 | S-04 S-06 S-07 S-09 S-23 S-26 S-27 S-30 S-33 S-40 S-41 | 이 8개는 "구현 편의" 가 아니라 **값을 봐야 정해지는 의미**였던 것들 — 규칙표가 컴파일 시점 규칙으로 바꿔야 삭제된다. 나머지 지점은 전부 구현 편의(값이 없어서 미룬 것)라 계획만 있으면 지운다. |

---

## 3. 대체 불가 판정 — "왜" 의 분류

| 분류 | 지점 | 판정 |
|---|---|---|
| 구현 편의(값이 없어 미룸) — **계획만 있으면 삭제** | S-01 S-02 S-03 S-05 S-11 S-13~S-22 S-24 S-25 S-28 S-29 S-31 S-32 S-34~S-39 | 결정 입력이 "값" 이어도 규칙은 값 타입 → 도메인의 항등 사상이라 컴파일 도메인으로 대체된다. |
| 값·행 의존 의미 — **규칙표 행 확정 뒤 삭제** | S-04 S-06 S-07 S-09 S-23 S-26 S-27 S-30 S-40 S-41 | G-08 목록. 현행은 "첫 값" 또는 "두 값" 의 타입에 따라 결과 타입이 달라진다 — D-M2 의 공통 타입(DOUBLE/VARCHAR) 적용 후보. |
| 연산 구현(값 타입 dispatch) — **유지, 결정적화** | S-08 S-33 S-10/S-12 의 coercion 함수 자체 | `qdata_*_dbval`·`tp_value_compare_with_error`·`btree_compare_key` 는 삭제 대상이 아니라 게이트 뒤 "타입 불일치 경로 도달 0" 을 assert 하는 경계 위치. |
| 게이트 밖 — **경계로 처리** | S-42 S-43 | 함수 인덱스/필터 predicate 는 실행 진입이 없다; 파라미터는 클라이언트 측. |

---

## 4. 타입 축 · collation 축 쌍 조건 지점(26곳) — L-47 의 실체

`TP_DOMAIN_TYPE(d) == DB_TYPE_VARIABLE || TP_DOMAIN_COLLATION_FLAG(d) != TP_DOMAIN_COLL_NORMAL` 형태로 두 축이 한 조건에 묶인 곳. 타입 축을 지운 뒤 collation 축이 남으면 이 지점이 그대로 남는다(#322 입력).

| 부류 | 지점 |
|---|---|
| 연산자 결과 (2) | fe:4479(S-02), fe:5226(S-05) |
| REGUVAL_LIST (1) | fe:5239(S-06) |
| 리스트 컬럼·위치 서술자 (11) | lf:7082(S-13), qx:1362(S-24), qx:21193(S-17), qx:21249 21277 21405(S-18), qx:23137(S-19), qx:27787(S-11), sm:8231 8254 8287 8293(S-20) |
| 집계·분석 (9) | qx:21328 21336 21440(S-18), qx:21605(S-23), qa:1876(S-25), qa:3343(S-26), qn:59(S-29), qn:188(S-27), sm:8240 8264(S-20 하위) |
| 빠른 경로 차단 (3) | fe:5273(S-05 FAST_PEEK), qn:59, `qdata_agg_is_plain_sum_avg` |

---

## 5. 게이트 위치와 실행 순서 근거

- `qexec_execute_query` qx:17456 이 `xasl_state.vd.dbval_ptr = dbval_ptr`(클라이언트가 보낸 값, `const`) 로 상태를 만든다. 서버 측에서 이 배열을 도메인으로 변환하는 코드는 **없다**(fe:4745~4757 은 포인터 반환뿐).
- `qexec_execute_mainblock_internal` qx:16150 은 qx:16538 에서 `aptr_list`(하위 XASL: 상관 없는 서브쿼리·CTE·INSERT…SELECT 소스)를 먼저 실행한다. 이 하위 블록도 같은 `vd` 를 읽으므로 게이트는 **aptr 실행 전** 이어야 한다. L-46 의 사고(연결 스레드가 만든 값을 aptr 를 실행한 PX 워커가 해제)는 게이트가 이 순서와 소유를 명시하지 않아서였다.
- PX 는 qx:3692~3714 에서 `xasl_state` 와 `vd` 를 워커별로 clone 한다 — 게이트 변환은 이 clone **이전** 에 끝나야 워커가 변환된 값을 복제한다(G-06).
- 서브쿼리 캐시(`sq_get`/`sq_put` fe:4763~4785)는 값을 키로 쓴다 — 게이트 변환 뒤의 값으로 키가 만들어지므로 변환은 캐시 조회 이전(= 실행 진입) 이어야 한다.

---

## 6. 경험치 렛저 대응표 (L-40~L-51)

| 렛저 | 이 문서에서 다룬 곳 |
|---|---|
| L-40 pack/unpack·세 로드 경로·함수 인덱스 게이트 부재 | §0 load 행, S-38(sx/sp 원본 저장), S-42, G-02, G-07(a) |
| L-41 파생 소비자 미포함 | S-13 S-15 S-17 S-18 S-24, G-03(c)(d)(e) — "계획이 파생 소비자까지" |
| L-42 original_domain 원복 | S-01(fe:4603), S-38, G-02 |
| L-43 누산기·분석함수 첫값 | S-23 S-25~S-29 S-36, G-03(e), G-08(5) |
| L-44 MRO 정렬 도메인 시딩 | S-11 S-32, G-05 |
| L-45 인덱스 키 변환 7항목 | S-12 S-30 S-31 S-32, G-05 |
| L-46 PX 워커 역전파·교차 mspace free | S-34~S-37 S-39, §5 aptr 순서, G-01 소유, G-06 |
| L-47 collation 축 | S-02 S-05, §4 26곳, G-04 |
| L-48 검증 경계 예외 목록·fpcache 오류 삼킴 | S-14 S-42, G-07 |
| L-49 플랜 도메인을 믿는 소비자 | S-08 S-33, G-01 불변식, G-08(7) |
| L-50 부수 관측 변화 | 범위 밖(탐침 #319 의 답안 변경 목록) — 이 문서의 삭제 지점 중 trace/오류 코드에 닿는 것은 S-12(btree 폴백 오류 코드), S-30(키 변환 오류 코드) |
| L-51 행당 비용 지점 씨앗 목록 | 전 항목이 S-01~S-40 에 1:1 로 들어감: fast-peek 차단=S-05, rel_cmp=S-09, compare_with_error=S-10, 산술 탈착=S-01, REGUVAL_LIST=S-06, 리스트 재시도=S-13, btree 폴백=S-12, 클론 원복=S-38, list_scan=S-20, GROUP BY/정렬/해시/분석=S-17~S-19, connect-by=S-21, INSERT db_to_char=S-40, COALESCE 류=S-04, GROUP_CONCAT VARCHAR=S-18/S-23 |

---

## 7. 결론 — 아키텍처 티켓(#318)·인터페이스 티켓(#323)에 넘기는 것

1. **삭제 지점 43개(S-01~S-43)** 중 게이트+계획만으로 지워지는 것 27, 규칙표 행이 먼저 필요한 것 10(G-08), 유지·결정적화 4, 게이트 밖 경계 2.
2. **게이트가 새로 추가하는 방향**은 "값 ← 도메인" 이며 서버에 전례가 없다(현행은 전부 "도메인 ← 값"). 위치는 `qexec_execute_query` 직후·aptr 실행 전·PX clone 전·서브쿼리 캐시 조회 전 한 곳(§5).
3. **계획 항목 6종(G-03 a~f)+키 변환 계획(G-05)** 이 스트림에 실려야 하고, 실리면 `original_domain` 계열 필드·원복·PX 역전파가 통째로 사라진다(G-02, G-06).
4. **collation 축 26곳(§4)** 은 타입 축과 별개로 #322 가 LEAVE 계약을 폐기해야 지워진다.
5. **행당 결정 0회의 증거**는 §1 의 "행당/첫값까지 행당" 지점 전부가 경계 assert 로 바뀌는 것(G-07) — 마이크로벤치(#316)는 S-05(FAST_PEEK 복원)·S-09/S-10(비교 coercion 0)·S-13(리스트 재시도 0)·S-23(집계 첫값 대기 0) 네 축을 잰다.
