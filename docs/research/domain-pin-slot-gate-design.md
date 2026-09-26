# 슬롯 도메인은 게이트가 정한다 — develop 동일 동작 설계 (v1, 2026-09-24 사용자 승인)

지도 xmilex-git/workspace#312 · 티켓 #336 · 작성 2026-09-24 · 기준 엔진 `dpin 6c50f939f`(#335 까지) + #336 미커밋 작업 트리
계기: #336 게이트 런(`sql-20260923T185234Z-2646995`, NOK 111)의 허용 diff 를 케이스별 SQL 로 보고한 뒤 사용자 결정 — "전부 develop 과 동일 작동하게 바꿔야 하고, domain 만 gate 에서 정해지게끔 설계해야 한다". 사용자 승인(2026-09-24): "Q1,Q2는 추천대로. Q3는 별도 티켓으로 관리(develop 결함은), 경계는 납득완료. 진행" — D-336-A~F 확정, Q1 = D-336-E 채택, Q2 = #338 도 같은 원칙(collation 도 게이트가 값에서, 답은 develop), Q3 = develop 결함 후보는 별도 이슈.

---

## 0. 결정 (제안 D-336-A ~ F — 승인 뒤 정본)

| 번호 | 결정 | 근거 | 대가 | 되돌리기 |
|---|---|---|---|---|
| **D-336-A** | 규칙표 §7 "답안 변경 목록" 을 **전부 철회**한다. #327 의 D-327-02(넓은 바인드)·D-327-09(`? + n` 날짜 65곳)·D-327-03~08(A3'·A13'·F1-T·U13·U7 사슬·A8'')·D-327-11(소비자 우선)이 정한 답안 변경은 이 결정으로 대체된다. 상위 원칙 P0(develop 답 유지)가 §7 보다 앞선다. | 사용자 검토 결과: 65곳 -494·표기·strict·오류 코드 이동 전부 기각 | #319 프로토타입·#327 개정·#336 미러 구현이 만든 답안 변경은 버린다 | 규칙표 §7 을 되살리고 미러를 다시 켠다(아래 3절 "제거" 항목이 그 목록) |
| **D-336-B** | **컴파일은 슬롯의 타입을 만들지 않는다.** develop 이 이미 클라이언트에서 캐스트하는 자리(비교·대입의 기대 도메인, `host_var_expected_domains[]`)만 컴파일 도메인이고, 그 밖의 모든 슬롯(산술·함수·공통값·UNION/VALUES·TO_CHAR·LIMIT·세션변수 읽기, ENUM 도메인·ENFORCE collation 도메인 자리)은 `REGU_VARIABLE_GATE` 다. | "domain 만 gate 에서" | 컴파일이 형제로부터 슬롯 타입을 알 수 있는 자리도 게이트로 미룬다 — 실행 시작 때 1회 결정이므로 행당 비용은 없다(D-323-05) | 없음(이 문서의 핵심) |
| **D-336-C** | **게이트(G1, `qexec_resolve_domains`)가 슬롯과 게이트 의존 노드의 도메인을 바인드 값의 타입으로 develop 격자(`domain_resolve`, #333 이 옮긴 현행 값 격자)대로 확정한다.** 답은 develop 과 같다 — #335 가 이 경로로 CTP sql 17468/17468·medium 975/975 를 통과했다. | 격자가 develop 그대로이므로 값이 같으면 답이 같다 | 개선 가능성(예: `bit_and(i1+?)` 의 develop 오답, VALUES 슬롯 -456)도 develop 그대로 둔다 — 결함은 별도 이슈로 | — |
| **D-336-D** | #336 의 나머지 범위는 **불변식**이다: (1) 비-GATE 바인드는 값 타입 == 계획 도메인(카운터 `Num_domain_bind_plan_mismatch` 0 + optdebug assert), (2) 세션변수 읽기는 게이트 노드(S5), (3) 로드 경계 (a) ON(예외 배열 X-1~X-5·X-8~X-11), (4) 리터럴 문장과 바인드 문장의 계획 분리(캐시 키 `host_var_cnt`), (5) LIMIT 슬롯 GATE, (6) VALUES 전-슬롯 행의 로드 GATE 복원, (7) 로드 거부 경로 해제 순서. 게이트 = **CTP sql 17468/17468 · medium 975/975(diff 0)**, TC expected 갱신 0. | 티켓 종료 조건 1~3 은 답을 바꾸지 않고도 성립한다 | — | — |
| **D-336-E** | 세션변수: 게이트가 실행 시작 시 저장값 타입으로 노드 도메인을 정하되, **행의 값 타입이 그 결정과 다르면 develop 처럼 값 타입으로 늦은 해석**한다(오류·변환 없음, P-S2 `(@v := @v + 1), (@v := '2.5')` 는 develop 의 4). 표 재조회(D-325-10)는 dpin-14 몫. | develop 동일 | 종료 조건 2 의 "세션변수 셀 fetch 카운터 0" 은 타입이 바뀌지 않는 문장에서만 0 | dpin-14 가 재조회로 바꿀 때 |
| **D-336-F** | 규칙표를 개정한다: §7 전 행 → "철회(D-336-A)"; §2~§4 의 C 행(슬롯 미러) → G 행(게이트 확정, 값 격자); U0(대입 캐스트)·B 행의 비교 기대 도메인은 develop 그대로라 불변; F1/F1-T/F1'·S4 미러·소비자 우선(P1 둘째 문장)·X1(미러 실패 정책) 삭제; ADR 0021 정정 절에 "컴파일 미러 없음" 추가. #337·#338·#340·dpin-17 영향은 7절. | 정본 일치 | 문서 개정 1회 | — |

---

## 1. 원칙 한 장

```
컴파일(클라이언트)   develop 그대로 타입 검사. 슬롯은 두 종류뿐:
                     (가) develop 이 클라이언트 캐스트하는 자리 — host_var_expected_domains[i] 가 있고
                         ENUM 도 ENFORCE 도 아닌 것 → 계획 도메인 = 그 도메인 (값도 그 도메인으로 온다)
                     (나) 그 밖의 전부 → REGU_VARIABLE_GATE (계획 도메인 VARIABLE)
                     노드: 피연산자에 (나) 가 있으면 게이트 의존 노드(pt_is_op_gate_dependent, 컴파일 타입 VARIABLE)
로드(서버)           domain_plan: (가) 는 고정 항목, (나) 는 슬롯 항목, 게이트 의존 노드는 gate_nodes 목록.
                     경계 (a): 그 밖에 VARIABLE 이 남으면 -1383 (예외 X-1~X-5 만; X-8~X-10 은 #337, X-11 은 #338 이 없앰)
게이트(G1)           슬롯 도메인 = 바인드 값의 도메인(tp_domain_resolve_value)
                     게이트 의존 노드 = domain_resolve(문맥, opcode, 피연산자 도메인들) — develop 의 값 격자 그대로
                     세션변수 읽기 = 실행 시작 시 저장값의 도메인
fetch                게이트 의존 노드는 G1 의 결정을 읽는다(문자 결과는 #338 부터 읽는다; MySQL 호환 모드·세션변수 타입 변경 행은
                     develop 의 늦은 해석 유지 — dpin-14; CAST 노드는 컴파일 대상 도메인 그대로 —
                     UNION 의 `CAST(x AS uncertain)` 은 develop 처럼 -181, L-18)
```

답이 develop 과 같은 이유: (가) 는 develop 이 하던 캐스트 그대로이고, (나) 는 develop 이 실행 때 값에서 정하던 것을 실행 시작 때 같은 격자로 한 번 정하는 것뿐이다. 다른 점은 "언제·몇 번" 이지 "무엇" 이 아니다(#333 격자 이관의 shadow assert 가 그 동치를 확인했다).

## 2. 슬롯 분류표

| 자리 | develop 의 클라이언트 캐스트 | 계획 | 게이트 | 예 |
|---|---|---|---|---|
| 비교 기대 도메인(`col op ?`, 캐스트 있는 행 B) | 있음(`pt_preset_hostvar`) | 고정(ASSIGN 캐스트 도메인) | 없음 | `varchar_col = ?` |
| 비교인데 캐스트 없는 자리(B4 `int_col = ?` 등 F-1) | 없음 | GATE | 값 도메인 | `c_int = ?` (카운터 셀 P1-int) |
| 대입(U0: INSERT/UPDATE/MERGE 직접 `?`) | 있음 | 고정 | 없음 | `insert … values (?)` |
| ENFORCE collation 기대 도메인(문자 형제) | collation 만 바꿈(F-336-01) | GATE + collation 기록 | 값 도메인(문자) | `str_col + ?`, `ifnull(char_col, ?)` |
| ENUM 도메인(CUBRIDSUS-9007) | 없음 | GATE | 값 도메인 | `enum_col < ?` |
| 산술·함수·공통값·UNION/VALUES·TO_CHAR 인자 | 없음 | GATE | 값 도메인, 노드는 격자 | `i + ?`, `? + 1`, `ifnull(?, 1)`, `to_char(?, fmt)`, `values (?),(?)` |
| LIMIT/KEYLIMIT | 없음 | GATE(D-336-05) | 값 도메인 | `limit ?`, `limit 0 + ?` |
| auto-param 리터럴 | 컴파일 타입 그대로 | 고정 | 없음 | `where i = 1` 의 `?:n` |
| 세션변수 읽기 | 없음 | 게이트 노드(S5) | 저장값 도메인 | `@v`, `@v + 1`, `sum(@v)` |

## 3. 지금 #336 작업 트리의 처리

| 파일 | 남긴다(불변식·경계) | 제거한다(답을 바꾸는 미러·그 부속) |
|---|---|---|
| `parser/type_checking.c` | `pt_is_op_hv_late_bind` → `pt_is_op_gate_dependent` 이름·주석 | `pt_mirror_slot`·`pt_mirror_slot_pair`·`pt_mirror_common_value_slots`·`pt_is_slot_mirror_sibling_type`·`pt_is_slot_argument`·`pt_is_session_variable_read`·`pt_consumer_mirror_domain`·`pt_to_char_format_type`·`pt_preset_hostvar_operand`; PLUS/MINUS 전처리, TIMES/DIVIDE/MODULUS·IFNULL/NVL/COALESCE/NULLIF/LEAST/GREATEST·NVL2·TO_CHAR·PT_CAST(시스템 UNION 캐스트) 훅; `pt_is_consumer_mirror_value`·`pt_push_assignment_domains`·`pt_push_update_assignment_domains` 와 `pt_eval_type_pre` 의 INSERT/MERGE/UPDATE 훅; `pt_preset_hostvar` 의 모드 기록 |
| `parser/semantic_check.c` | — | U2/U4(`pt_is_union_slot_branch`, `pt_get_common_type_for_union` 의 슬롯 가지 미러), U16(`pt_coerce_insert_values` 서브쿼리 `?`) |
| `parser/xasl_generation.c` | `pt_make_regu_hostvar`: 계획 도메인 = `host_var_expected_domains[i]`(UNKNOWN·ENUM·ENFORCE 는 GATE) — F-336-01; `pt_gate_limit_regu` 10곳 | — |
| `parser/parse_tree.h`·`csql_grammar.y`·`name_resolution.c`·`parse_tree.c`·`object/db_vdb.c`·`db_query.h/.c`·`parse_dbi.c`·`parser.h` | — | `host_var_convert_modes[]` 전부(할당·복사·pack/unpack·저장/복원)와 `pt_convert_bind_value`(OPERAND 모드) — 캐스트는 develop 의 `tp_value_cast_preserve_domain` 한 벌로 돌아간다 |
| `object/object_domain.c`·`query/numeric_opfunc.c/.h` | — | strict NUMERIC 무손실 leaf(`tp_numeric_from_num<STRICT>` 정수 분기)·`numeric_is_fraction_part_zero` extern — 미러가 없으면 호출자 0 |
| `parser/parse_tree_cl.c` | 캐시 키 `;host_var_cnt=N`(F-335-04 ②) | — |
| `base/perf_monitor.h/.c`·`parser_support.c` | `Num_domain_bind_plan_mismatch` | — |
| `query/query_executor.c/.h` | S5 게이트 노드(`qexec_resolve_gate_node` 의 `T_EVALUATE_VARIABLE`), 상수 참조 순회의 GATE/COLLATION_GATE 기록·불일치 카운터·assert, `RESOLVED_GATE_NODE` release 컴파일 | — |
| `query/domain_plan.h/.c` | 플래그 확장·`DERIVED`·`COLLATION_GATE`, `domain_plan_check_load = true`, 예외표 X-1~X-5·X-8~X-11, `T_EVALUATE_VARIABLE` 게이트 노드, 검증·-1383 | — |
| `query/stream_to_xasl.c` | 로드 거부 해제 순서(`stx_free_visited_ptrs` 뒤 해제, SA 전역 NULL), VALUES 전-슬롯 행 GATE 복원 | — |
| `query/fetch.c` | 게이트 의존 노드의 G1 결정 읽기(비문자·비 MySQL 호환), 그림자 assert 의 문자·NULL 결정 제외 | `fetch_convert_session_variable` 과 `T_EVALUATE_VARIABLE` 의 행 값 변환 → D-336-E 의 "타입이 다르면 늦은 해석" 으로 교체(`operand_class == OPERAND_VOLATILE` 노드는 피연산자 값 타입이 G1 결정과 같을 때만 결정을 읽는다; 다르면 develop 경로) |
| `query/query_dump.c` | 플래그 `%03x` | — |
| dpin-tc `domain_counters.sql/.answer` | `bind_plan_mismatch` 셀(0) | — |

제거 뒤 남는 diff 는 대략 파일 12개 안팎이며, 답을 바꾸는 줄이 하나도 없어야 한다(3절 게이트).

## 4. 세션변수 (D-336-E 상세)

- G1: `@v` 읽기 노드는 게이트 노드 — 실행 시작 시 `session_get_variable` 의 값 도메인(미정의면 NULL 도메인, 오류는 develop 처럼 행 읽기에서).
- 그 위 노드(`@v + 1`, `abs(@v)`, `sum(@v)`): 게이트 의존 노드로 G1 이 격자로 확정.
- fetch(구현): `@v` 읽기 노드가 행 값을 읽었을 때 그 타입이 G1 의 결정과 다르면(`@v := '2.5'` 가 문장 중간에 타입을 바꿈) `xasl_state->resolved.volatile_changed` 를 켜고 그 읽기부터 **VOLATILE 부류 노드 전부가 남은 실행 동안 develop 의 늦은 해석**으로 계산한다(카운터 +1씩). 바뀌기 전 행은 결정을 읽는다(카운터 0). 값·오류 모두 develop 과 같다. 행마다 피연산자 도메인을 대조하는 정밀한 형태(바뀐 노드만)는 dpin-14 의 표 재조회와 함께. **#340**: 정밀한 형태가 들어갔다 — 전역 `volatile_changed` 대신 읽기별 마스크(`changed_reads` × 칸의 `slot_volatile_reads`)라, 바뀐 읽기에 기대는 결정만 develop 의 늦은 해석을 받고 다른 VOLATILE 노드는 계속 결정을 읽는다. 내용으로 분류하는 노드(ADDTIME 왼쪽 문자열, STR_TO_DATE 포맷)는 타입이 같아도 부류가 바뀌면 같은 표시를 한다(`fetch_volatile_class_holds`). 표 재조회는 쓰지 않는다(D-336-A·E).
- 문자 세션변수(`@b` CHAR(8) 이 concat 으로 자라는 bug_bts_4562): #338 부터 문자 결정도 읽고, 행 값의 타입뿐 아니라 precision·codeset·collation 이 결정과 다르면 같은 폴백(`volatile_changed`)이 켜진다(`fetch_value_leaves_domain`).
- 종료 조건 2 의 표현을 "타입이 바뀌지 않는 세션변수 셀에서 0" 으로 고친다.

## 5. 규칙표·ADR 개정 (D-336-F 상세)

- §0 P1: "형제 미러" 문장을 "슬롯의 도메인은 게이트가 값에서 정한다; 컴파일 도메인은 develop 의 클라이언트 캐스트 자리뿐" 으로. 소비자 우선 문장 삭제.
- §2~§4: 확정 시점 부호 C 인 슬롯 행(A5·A5'·A6·A8'·A3'·A13'·U2·U4·U7·U13·F1·F1-T·F1'·S4·U16 등) → G. K 게이트 열은 "값 도메인, 격자" 로. U0·B 행 중 develop 이 캐스트하는 자리는 그대로(C 이지만 미러가 아니라 develop 의 캐스트).
- §7: 표 전체를 "철회(D-336-A, 2026-09-24)" 로 표시하고 남긴다(이력). "불변 목표" 문단은 전부 불변으로 승격.
- §5(결함 소멸)·X1(미러 실패 정책): 미러가 없으므로 X1 삭제; 결함(`bit_and(i1+?)` 오답, VALUES 슬롯 -456, `'1' + n'2'` NULL)은 별도 이슈 후보 목록으로 옮긴다.
- ADR 0021 정정 절: "미러 슬롯(dpin-10)의 변환도 같은 자리" 문장 삭제, "컴파일은 슬롯 타입을 만들지 않는다(D-336-B)" 추가. ADR 0019/0020 은 영향 없음(스트림·GATE 비트 그대로).
- `domain-pin-converters.md` §5 세션변수 A/B(P-S2·S5·S8·S10 의 -494/NULL) → develop 값으로 되돌림. `domain-pin-interface.md` §3.1 3단계 주석을 D-336-E 로.

## 6. 검증·게이트

1. 양 빌드 green.
2. optdebug CTP sql 전수 + medium: **NOK 0**(17468/17468 · 975/975), 코어 0, assert 0, `Num_domain_bind_plan_mismatch` 0, 볼륨 overlay 잔여 0.
3. SA A/B(develop optdebug vs dpin optdebug): probe1·2·4·6 의 결과 diff 0(플랜 텍스트 `host_var_cnt` 접미사 제외).
4. 카운터 harness(t335-c3r1 대비): 결과 행 405/405 동일; `Num_domain_resolve_fetch` 는 B4 `int_col = ?` 셀에서 0 → 1(develop 이 캐스트하지 않던 슬롯이 GATE 가 되어 fetch 의 옛 경로가 1회 읽음 — dpin-14 가 게이트 표 읽기로 0 으로 만든다), P1-string·P6-in·P3-agg 는 감소; `Num_planned_convert`·`Num_domain_px_resolve` 불변. 이 증가는 설계상의 것으로 해소 코멘트에 적는다.
5. 로드 경계 (a) ON 상태로 2 통과.

## 7. 다른 티켓에 미치는 영향

| 티켓 | 영향 |
|---|---|
| #337 dpin-11 | 파생 소비자가 생산자의 칸(ALIAS)이나 도메인을 싣고 X-8~X-10 을 없앴다(인터페이스 §2 구현(#337)·§6). |
| **#338 dpin-12** | Q2 로 같은 원칙 적용 — **구현 완료(2026-09-24)**: 컴파일은 develop 의 collation 추론 그대로, LEAVE·ENFORCE 문자 항목은 로드가 게이트 칸(`COLLATION_GATE` 슬롯·collation 게이트 노드·생산자 칸)으로 덮고 G1 이 값과 연산자 실행 규칙으로 정한다. -1150/-622 시점은 develop(결정 없음 → 행이 낸다), 문자 precision 은 값이 정한다(D-338-03, 사용자 승인). X-11 삭제, fetch 문자 결과 제외 해제. 결정 D-338-01~07 은 #338 해소 코멘트. |
| #339 dpin-13 | 같은 원칙으로 **구현 없음**(2026-09-24): PL/CSQL 정적 SQL 의 `?` 는 사용자 `?` 와 같은 슬롯이다 — 실행 때 바인드가 `db_push_values` 로 JDBC 와 같은 캐스트 자리를 지나고, 나머지 슬롯은 게이트가 PL 이 보낸 값의 도메인을 쓴다. 선언 타입 전달(D-317-06·D-323-10·ADR 0021 Consequences 셋째 항목)은 대체(ADR 0021 정정 3, 규칙표 S6). develop 답은 TC `_07_misc/domain_plcsql_slot` 이 고정한다. |
| #340 dpin-14 | 전제 강화: fetch 가 게이트 표를 읽어 값 판정을 지우는 일이 이 설계의 핵심 실행 측. 세션변수 행 재조회(D-325-10)·MySQL 호환 모드·문자 결과가 남은 늦은 해석 원천. |
| dpin-17 릴리스 노트 | `? + n` 날짜 바인드 안내 불필요(답 불변). |
| #325 변환기 표·ADR 0021 | OPERAND 모드 클라이언트 캐스트 삭제; 게이트 변환기(실행 스코프 1회, D-325)는 그대로. |

## 8. 열린 결정(사용자) — 답변 완료(2026-09-24): Q1 채택 · Q2 #338 재정의 · Q3 별도 이슈

- **Q1** D-336-E 방식(행마다 타입 비교 → 같으면 결정, 다르면 develop 늦은 해석) 채택 여부. 대안: #336 은 세션변수 노드를 전부 늦은 해석에 두고(#335 상태) dpin-14 에 통째로 넘김 — 종료 조건 2 를 dpin-14 로 이관.
- **Q2** #338(collation 축)도 "게이트가 정하고 답은 develop" 으로 재정의할지.
- **Q3** develop 결함 후보(`bit_and(i1+?)` 오답, 다중 행 VALUES 슬롯 -456, `'1' + n'2'` NULL, `limit 0+?` 조용한 1행)를 별도 이슈로 낼지(이 캠페인 밖).
