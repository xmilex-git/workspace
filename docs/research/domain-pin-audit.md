# 실행 하위 삭제 감사표 — S-01~S-43 + collation 쌍 조건 26곳 (D-320-04)

지도: xmilex-git/workspace#312 · 신설: #340(dpin-14, 2026-09-24) · 확정: #344(dpin-18)
지점 정본: `domain-pin-exec-sites.md` §1(S-01~S-43)·§4(collation 26곳) · 삭제 축: `domain-pin-architecture.md` §1.5

## 판정 규칙 (D-320-04)

지점은 ① **정적 근거**(계획·게이트 뒤 조건이 거짓임을 코드로 설명)와 ② 그 티켓의 CTP sql 전수·medium 에서 해당 카운터 0 을 **모두** 만족할 때만 삭제한다. 하나라도 어긋나면 멈추고 티켓에 재계획한다. 카운터가 0 이어도 정적 근거가 서지 않으면(CTP 가 그 경로를 밟지 않았을 뿐) 지우지 않고 셀 TC 를 먼저 더한다. 유지 지점은 optdebug assert 경계와 근거 한 줄을 둔다. "값·행에 따라 의미가 진짜 남는다"는 판정은 규칙표 행과 사용자 승인이 있어야 한다(아래 **X**).

판정 어휘: **삭제**(코드 없음) · **읽기**(자리는 남고 계획·게이트 결정을 읽는다, 값에서 정하지 않음) · **경계**(도달 0 을 optdebug assert + release `ER_QPROC_DOMAIN_UNRESOLVED` -1382 로 지킨다) · **유지**(연산 구현, 결정이 아님) · **X**(승인된 값 의존 의미 — 근거 결정 번호) · **대기**(소유 티켓이 아직 열려 있음).

카운터 증거는 perfmon 카운터(`SHOW EXEC STATISTICS`, 셀 하네스)와 진단 빌드 CTP 전수 집계(각 카운터 증가 자리에 이유별 한 줄을 찍는 빌드, 커밋하지 않음) 두 가지다. CTP 는 perfmon 추적을 켜지 않으므로 전수 증거는 진단 집계와 경계 assert(코어 0)다.

## 1. 지점 S-01~S-43

| ID | 지점(요약) | 판정 | 티켓 | 정적 근거 | 카운터 증거 | 경계 위치 |
|---|---|---|---|---|---|---|
| S-01 | `fetch_peek_arith` 도메인 탈착→값 재확정→원복 | 읽기 · 경계 · X(D-336-E) | #340 | 게이트 의존 노드는 실행의 첫 계산에서 G1 결정을 읽는다(`fetch_arith_gate_reading`). "값 없음" 결정(NULL 피연산자·거부 쌍·병합 불가 collation·VARIABLE 목표 CAST)은 도메인 없이 계산해 NULL 이나 연산자 오류만 낸다. 탈착·재확정·원복은 세션변수 읽기가 결정을 벗어난 뒤의 첫 계산(D-336-E)과 게이트 상태 없는 vd(F-334-01 → #352)에만 남는다 | 진단 전수 `sql-20260924T121845Z-1064659`·`medium-20260924T121845Z-1064660`: 늦은 해석 12줄 전부 `bug_bts_4562`(D-336-E) · 게이트 `sql-20260924T145139Z-1311656` 17462/17462 · `medium-20260924T145139Z-1311657` 975/975 · 카운터 P1/P2/P8 fetch 0(p0·p24) | `fetch_arith_gate_reading` UNRESOLVED → assert + -1382 · "값 없음" 노드의 비NULL 값 → assert + -1382 |
| S-02 | 같은 함수, collation 재확정 | 읽기 · 경계 · X(D-338-02 → #343, D-336-E) | #340 | collation 게이트 노드(#338)의 결정을 읽는다. 게이트가 정하지 못한 노드(D-338-02)와 바뀐 세션변수 읽기 위의 결정만 행이 값에서 정한다(`fetch_row_reads_string_domain`) | 진단 전수 `sql-20260924T121845Z-1064659`·`medium-20260924T121845Z-1064660`: 미결정 15줄·11가지(D-338-02, 목록은 #343 인계), 3줄 `bug_bts_6605`(D-336-E) · 게이트 `sql-20260924T145139Z-1311656` 17462/17462 · `medium-20260924T145139Z-1311657` 975/975 | `fetch_row_reads_string_domain` 거짓 → assert + -1382 |
| S-03 | oracle 빈 문자열 결과 타입 VARIABLE 검사 | 읽기 | #340 | 결과 도메인이 열려 있으면 게이트 결정의 타입으로 검사한다 | — | — |
| S-04 | NVL/COALESCE/NVL2/NULLIF/LEAST/GREATEST 두 값 공통 타입 추론 | 읽기 · 경계 · X(S-01 의 늦은 해석 경로) | #340 | 결정된 노드는 해석기(dpin-07)가 준 공통값 도메인을 읽어 추론 자리에 오지 않는다. "값 없음" 노드는 인자가 모두 NULL 이면 NULL. 추론은 S-01 이 늦은 해석을 남긴 경로에만 | 게이트 `sql-20260924T145139Z-1311656` 17462/17462 · `medium-20260924T145139Z-1311657` 975/975 | `assert (no_value_domain == NULL)` |
| S-05 | `fetch_peek_dbval_slow` VARIABLE/collation 확정 블록 | 읽기 · 경계 · X(S-09 → #352, D-338-02 → #343, D-336-E, F-334-01 → #352) | #340 | 슬롯은 바인드 값 도메인(#336), 값 포인터·위치는 생산자(#337), 문자 함수는 자기 결정(#338)을 읽는다(`fetch_read_plan_domain`, optdebug 그림자 assert: 타입·codeset·collation). 로드가 못 걷던 두 regu(비상관 스칼라 부분질의의 미리 실행 regu, 집계 PERCENTILE 비율)를 걷고, 식 안의 GROUP_CONCAT 누산기 독자는 collation 게이트 노드다. 그림자 assert 가 PX 워커 클론의 누산기 도메인 누수를 잡아 워커가 쓰기 전에 비운다(D-340-09) | 진단 전수 `sql-20260924T121845Z-1064659`·`medium-20260924T121845Z-1064660`: S-09 제자리 6 케이스(#352 인계), D-338-02 4줄(`bug_bts_13782` ELT), 로드 누락 2줄(`issue_11088/11089 _11_subquery`)·GROUP_CONCAT 1줄(`collation_gate_probes`) — 뒤 둘은 게이트 런에서 결정 읽기 · 게이트 `sql-20260924T145139Z-1311656` 17462/17462 · `medium-20260924T145139Z-1311657` 975/975 · PX 동시 세션 30회차 abort 0 | `fetch_read_plan_domain` → assert + -1382 |
| S-06 | REGUVAL_LIST 행 도메인 확정 | 읽기 · 경계 | #340 | 행마다 자기 항목의 결정을 S-05 처럼 읽는다 | 게이트 `sql-20260924T145139Z-1311656` 17462/17462 · `medium-20260924T145139Z-1311657` 975/975 | S-05 와 같음 |
| S-07 | 세션변수 읽기(`T_EVALUATE_VARIABLE`) | 읽기(게이트 노드, #336 S5) · X(D-336-E) | #336·#340 | 읽기가 결정을 벗어나면 그 읽기 비트를 켜고, 그 비트에 기대는 결정만 늦은 해석(읽기별 마스크 `slot_volatile_reads` × `changed_reads`). 표 재조회(D-325-10)는 쓰지 않는다 | 진단 전수 `sql-20260924T121845Z-1064659`·`medium-20260924T121845Z-1064660`: 29줄 전부 `bug_bts_4562` · 카운터 셀 [N-sv-change] 2, 그 밖 0 | — |
| S-08 | `qdata_*_dbval` 값 타입 dispatch | 유지 | — | 연산 구현(결정 아님) | — | — |
| S-09 | `eval_value_rel_cmp` rhs 제자리 coerce | 대기 | #352 | | | |
| S-10 | `tp_value_compare_with_error (do_coercion=1)` 술어 호출 | 대기 | #352 | | | |
| S-11 | `qexec_topn_cmpval` VARIABLE 폴백 | 읽기 · X(D-336-E) | #340 | 정렬 키마다 계획 도메인을 top-N 준비 때 1회 읽어 `cmpval` 을 직접 부른다(`qexec_topn_sort_domains`). 세션변수 읽기에 기대는 키는 값이 도메인을 벗어난 비교에서만 값 타입으로 비교 | 카운터 P4-topn `Num_domain_coerce_compare` 실행당 1,004,600 → 1(남은 1 = LIMIT 절 `qexec_check_limit_clause`, #352 인계) | — |
| S-12 | `btree_compare_key` 비교 불가 폴백 | 대기(경계) | #342 | | | |
| S-13 | `qfile_update_domains_on_type_list` | 대기 | #341 | | | |
| S-14 | `qdata_get_valptr_type_list` | 대기(경계) | #341 | | | |
| S-15 | `qfile_unify_types` VARIABLE 채택·-1509 | 대기 | #341 | | | |
| S-16 | `qfile_initialize_sort_key_info` cmpdisk 폴백 | 대기 | #341 | | | |
| S-17 | `qexec_resolve_domains_on_sort_list` | 대기 | #341 | | | |
| S-18 | `qexec_resolve_domains_for_group_by` | 대기 | #341 | | | |
| S-19 | 분석 `resolve_domain:` 블록 | 대기 | #341 | | | |
| S-20 | `resolve_domains_on_list_scan` | 대기 | #341 | | | |
| S-21 | connect-by 프로브 NUMERIC p/s 보정 | 대기 | #341 | | | |
| S-22 | 해시 조인 조인 키 공통 타입 | 대기 | #341 | | | |
| S-23 | `qexec_resolve_domains_for_aggregation` | 대기 | #341 | | | |
| S-24 | BUILDVALUE 출력 regu 도메인 | 대기 | #341 | | | |
| S-25 | `qdata_finalize_aggregate_list` distinct/sort 도메인 | 대기 | #341 | | | |
| S-26 | `qdata_update_agg_interpolation_func_value_and_domain` | 대기 | #341 | | | |
| S-27 | 분석 첫값 도메인 블록 | 대기 | #341 | | | |
| S-28 | 분석 보간 첫값 switch | 대기 | #341 | | | |
| S-29 | `qdata_analytic_is_plain_sum_avg` 차단 조건 | 대기 | #341 | | | |
| S-30 | `scan_dbvals_to_midxkey` strict 시도·setdomain | 대기 | #342 | | | |
| S-31 | ISS `last_key` 도메인 | 대기 | #342 | | | |
| S-32 | MRO `tp_Null_domain` 시딩 | 대기 | #342 | | | |
| S-33 | keylimit NUMERIC assert(계획 도메인 신뢰) | 유지 | #342 | 불변식이 보호 | — | 기존 assert |
| S-34 | PX 워커 집계 도메인 resolve | 대기 | #343 | | | |
| S-35 | PX 루트 역전파 | 대기 | #343 | | | |
| S-36 | PX 행당 누산기 폴백 | 대기 | #343 | | | |
| S-37 | `update_domains_on_type_list_by_val_list` | 대기 | #343 | | | |
| S-38 | `qexec_clear_*` 원복 + `original_domain` 필드 | 대기 | #343 | | | |
| S-39 | 힙 전환(qe 쪽 · qx 집계 쪽) | 대기 | #352(qe) · #341(qx) | | | |
| S-40 | `db_to_char` 결과 도메인(INSERT 기본식) | 대기 | #343 | | | |
| S-41 | PL/CSQL 바인드 선언 타입 | 해당 없음 | #339 | PL `?` = 사용자 `?`(D-339-01) | — | — |
| S-42 | 필터·함수 인덱스 스트림 | 대기(경계) | #343 | | | |
| S-43 | `hostvar_late_binding` 파라미터 | 대기 | #344 | | | |

## 2. collation 쌍 조건 26곳 (`VARIABLE || collation_flag != NORMAL`)

#343 이 26곳을 모두 지운다. 아래 "이 티켓 자리" 는 조건을 지우지 않고 그 안의 값 판정만 바꾼 티켓이다.

| # | 자리 | 부류 | 이 티켓 자리 | 판정 | 티켓 |
|---|---|---|---|---|---|
| C-01 | fe:4479 (S-02) | 연산자 결과 | #340 — 조건 안의 값 판정은 결정 읽기 | 대기 | #343 |
| C-02 | fe:5226 (S-05) | 연산자 결과 | #340 — 조건 안의 값 판정은 결정 읽기 | 대기 | #343 |
| C-03 | fe:5239 (S-06) | REGUVAL_LIST | #340 — 조건 안의 값 판정은 결정 읽기 | 대기 | #343 |
| C-04 | lf:7082 (S-13) | 리스트 컬럼 | #341 | 대기 | #343 |
| C-05 | qx:1362 (S-24) | 리스트 컬럼 | #341 | 대기 | #343 |
| C-06 | qx:21193 (S-17) | 위치 서술자 | #341 | 대기 | #343 |
| C-07 | qx:21249 (S-18) | 위치 서술자 | #341 | 대기 | #343 |
| C-08 | qx:21277 (S-18) | 위치 서술자 | #341 | 대기 | #343 |
| C-09 | qx:21405 (S-18) | 위치 서술자 | #341 | 대기 | #343 |
| C-10 | qx:23137 (S-19) | 위치 서술자 | #341 | 대기 | #343 |
| C-11 | qx:27787 (S-11) | 정렬 키 | #340 — 계획 도메인 읽기 | 대기 | #343 |
| C-12 | sm:8231 (S-20) | 리스트 스캔 | #341 | 대기 | #343 |
| C-13 | sm:8254 (S-20) | 리스트 스캔 | #341 | 대기 | #343 |
| C-14 | sm:8287 (S-20) | 리스트 스캔 | #341 | 대기 | #343 |
| C-15 | sm:8293 (S-20) | 리스트 스캔 | #341 | 대기 | #343 |
| C-16 | qx:21328 (S-18) | 집계 | #341 | 대기 | #343 |
| C-17 | qx:21336 (S-18) | 집계 | #341 | 대기 | #343 |
| C-18 | qx:21440 (S-18) | 집계 | #341 | 대기 | #343 |
| C-19 | qx:21605 (S-23) | 집계 | #341 | 대기 | #343 |
| C-20 | qa:1876 (S-25) | 집계 | #341 | 대기 | #343 |
| C-21 | qa:3343 (S-26) | 집계 | #341 | 대기 | #343 |
| C-22 | qn:59 (S-29) | 분석·빠른 경로 차단 | #341 | 대기 | #343 |
| C-23 | qn:188 (S-27) | 분석 | #341 | 대기 | #343 |
| C-24 | sm:8240 (S-20 하위) | 집계 | #341 | 대기 | #343 |
| C-25 | sm:8264 (S-20 하위) | 집계 | #341 | 대기 | #343 |
| C-26 | fe:5273 (S-05 FAST_PEEK) | 빠른 경로 차단 | #340 — S-05 가 결정을 읽은 뒤 빠른 경로가 켜진다 | 대기 | #343 |

좌표(fe/qx/lf/sm/qa/qn)는 `domain-pin-exec-sites.md` 작성 기준(develop `cad27172b`)이다. 지금 소스의 줄 번호는 다르다.
