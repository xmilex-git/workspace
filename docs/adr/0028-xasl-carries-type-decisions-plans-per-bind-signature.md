---
status: accepted
date: 2026-10-16
issue: CBRD-27583 (CBRD-27510 / PR 8022 의 구조를 대체)
supersedes: ADR 0019, 0020, 0021, 0022, 0023, 0024, 0027 (삭제)
---

# XASL 이 타입 결정을 직접 싣고, 플랜은 바인드 타입 서명마다 하나이며, 서버는 실행 중에 타입을 정하지 않는다

PR 8022 는 "언제 정하나" 를 로드 도출과 실행 전 도메인 확정 두 층으로 만들고, 결정을 노드 밖의 표(`DOMAIN_PLAN`, `RESOLVED_DOMAIN_TABLE`, `DOMAIN_EXECUTION_STATE`)에 두었다. 그 결과 regu 를 평가하는 함수가 바깥 상태를 읽고, 바인드 없는 문장도 실행마다 확정 단계를 지나며, 같은 타입의 반복 실행이 같은 결정을 다시 했다. 이 ADR 은 그 층을 없애고 결정을 컴파일로 돌려놓는다. 결정 원문: CBRD-27583 본문의 대원칙 1~4 (2026-10-16 그릴링 Q1~Q47).

- **타입은 컴파일이 정한다.** 플랜은 바인드 타입 서명마다 하나다. 서명은 캐시 키 텍스트의 호스트 변수 토큰이다: 지금의 ` ?:N ` 에 타입(문자열은 CHAR/VARCHAR·codeset·collation, NUMERIC 은 하나, NULL 은 NULL)을 더해 찍고, 사용자 바인드와 자동 파라미터 리터럴을 같은 형식으로 찍는다(리터럴 collation 은 SET NAMES 가 정하므로 텍스트에 없다). 읽는 세션변수 타입과 STR_TO_DATE 포맷 분류도 키 텍스트에 들어간다. 별도 서명 문자열·접미사는 없다. 타입이 정해지지 않은 플랜(일반 플랜)은 없고 서명 수 상한도 없다. 바인드 자리의 타입은 클라이언트 타입 검사가 정한다 — 문맥이 정하던 기대 도메인(develop 의 `pt_preset_hostvar`)에 더해, 문맥이 못 정하던 자리는 값의 타입으로 정해 모든 자리가 기대 도메인을 갖는다. 새 서명은 develop 의 텍스트 재컴파일 경로(`do_recompile_and_execute_prepared_statement`, JDBC 쪽 `db_check_where_need_recompile` 의 재파싱)로 다시 컴파일한다 — 더하는 것은 "값은 안 보이고 타입만 보이는 컴파일" 표시() 하나다(Q8, 2026-10-16: develop 의 "값을 묶고 컴파일" 은 `pt_coerce_value` 가 값을 바꾸는 값 굽기라 쓸 수 없고, 보관 트리는 타입 검사 뒤 모양이라 사본 재검사도 안 된다). 타입만 보이는 컴파일은 값을 플랜에 넣지 않는다: SELECT 는 develop 처럼 값을 묶기 전에 컴파일하되 자리마다 값의 타입 헤더만 가진 NULL(`do_set_user_host_variable_types`)을 두어, `set_host_var` 가 막지 않는 값 읽기(LIKE 재작성·MRO·SORT-LIMIT 검사)가 타입 키로 캐시되는 플랜에 값을 굽지 못하게 한다(뼈대 2차 리뷰: 두 갈래를 합쳐 SELECT 도 값을 묶고 컴파일한 것은 CBRD-27582 류 회귀 — 되돌림). DML 은 develop 처럼 값을 묶고 컴파일한다(클라이언트 트리거 UPDATE 의 OID 수집 부질의). 값 없는 PREPARE 는 기대 도메인 없는 자리가 있으면 XASL 을 만들지 않는다. XASL 생성은 바인드에 대해 아무 결정도 하지 않는다.
- **자리는 두 종류다(Q9).** 문맥 타입 자리(INSERT 값, 문자열·날짜 컬럼 비교)는 지금처럼 기대 도메인으로 캐스트한다. 값 타입 자리(`int_col = ?`, `? + ?`, `sum(?)`)는 값의 타입으로 컴파일하고(`host_var_compiled_domains`), 비교는 타입 검사가 규칙 모듈(`domain_resolve_comparison`, 행 규칙의 표)로 쌍을 정해 바인드 쪽 목표가 있으면 그것을 기대 도메인으로 두고(클라이언트가 보내기 전 캐스트) 없으면 항이 컬럼 쪽을 바꾼다(`pt_typed_bind_comparison`, `def_type == MAYBE` 조기 반환 앞). 리터럴 규칙(`ic = '1.5'` → 리터럴을 INT 로, 2)이 아니라 행 규칙이라 답이 develop 과 같다. 값 타입 자리에 다른 타입이 오면 캐스트하지 않고 그 서명으로 재컴파일한다(INT 플랜에 1.5 를 INT 로 바꾸면 답이 틀린다). 캐시 키 토큰 = 보내는 값의 타입 = 플랜의 regu 도메인. 바인드 값은 선택도에만 쓰고 플랜에 굽지 않는다(LIMIT peek 예외, `hostvar_late_binding` 은 현행).
- **결정은 그 결정이 속한 XASL 구조에 산다.** 비교 항·연산자 노드·집계/분석 노드·키 원소·대입 목록. 값 포인터는 생산자의 타입을 싣는다. 스트림은 바꾸는 쪽의 목표 도메인과 비교 방법을 싣고 역직렬화가 규칙 모듈의 같은 변환기 함수(`domain_compare_converter`, ASSIGN 모드 — COMPARE 모드로 다시 찾으면 NUMERIC→DOUBLE 이 비호환이 된다)로 포인터를 둔다. 평가 함수는 자기 노드·피연산자 값·실행 입력(`vd->dbval_ptr`, sysdate, 세션변수 값)만 읽는다.
- **인덱스 키는 열마다 셋 중 하나를 컴파일이 적는다.** 같은 타입 → 그대로; 손실 없는 쌍 → 값 쪽 변환기(바인드는 push 캐스트, 식은 스캔 열릴 때 한 번); 손실 가능한 쌍(DOUBLE·NUMERIC 값 vs INT 인덱스) → 인덱스 쪽을 값 타입으로, 하강 비교마다 고정 변환기. develop 의 strict-or-keep(`btree_coerce_key`, 값 의존)과 비교마다의 `TP_ARE_COMPARABLE_KEY_TYPES`/`tp_value_compare_with_error`(`btree_compare_key_with`)는 삭제, 8022 의 스캔당 고정 비교기(`btree_compare_search_key`, `pr_midxkey_compare_resolved`)는 결정을 키 원소에서 받는 실행 부품으로 남긴다. 혼합 키 도메인도 컴파일이 만들어 싣는다. 키 필터는 비교 항과 같은 구조(`eval_key_filter` → `eval_pred`). key limit 바인드는 타입 검사가 BIGINT 로. 답은 같다(strict 성공 = 정확히 표현 = 넓은 타입에서 순서 동일); 정수값 DOUBLE 바인드는 하강 비교마다 변환 하나를 더 낸다(기록만).
- **실행 중 타입 결정 0.** 행마다·스캔마다 두 값의 타입으로 변환·비교 방법을 고르던 develop 코드(인덱스 키 strict-or-keep, 비교 전 공통 타입, 리스트 열·집계·분석의 첫 값 확정, PX 역전파)와 8022 의 확정 층을 모두 지운다. 키 비교는 "어느 쪽을 어느 도메인으로 바꿔 비교하는가" 를 컴파일이 타입 쌍으로 정해 키 원소에 싣는다(INT 인덱스 대 DOUBLE 값 → 인덱스 쪽을 DOUBLE 로). 함수 본문의 타입 switch 도 같은 원칙으로 컴파일이 고른다 — 후속 이슈 없이 한 PR.
- **서버는 실행 전에 아무것도 바꾸지 않는다.** 바인드 값은 develop 처럼 클라이언트가 보내기 전에 기대 도메인으로 한 번 바꾼다(`pt_set_host_variables`). 한 호스트 변수가 두 도메인을 요구하는 자리(옵티마이저 전이 항 `t1.ic = ? AND t2.vc = t1.ic` → `cast(t2.vc as double) = ?:0`, `mq_copypush_sargable_terms` 복사, `?:0` 재사용 문법)는 타입 검사가 두 번째 자리에 파생 자리(자동 파라미터처럼 `host_var_count + auto_param_count` 뒤 번호)를 주고 클라이언트가 변환해 채운다 — develop 은 마지막 기대 도메인 하나로 바꾸고 나머지는 행마다 다시 바꿨다. 변환 실패는 develop 의 컴파일 타입 자리와 같이 바인드 시점 오류다("실패하면 원래 값" 은 없다 — 항이 변환된 값을 전제로 결정하므로 원래 값이 행에 오면 타입 불일치다). `vd->dbval_ptr` 는 클라이언트 배열 그대로 const 이고 PX 워커는 포인터를 공유한다(optdebug 체크섬으로 검증).
- **예외는 데이터가 타입을 지니는 곳뿐.** 원소 타입이 섞인 컬렉션의 원소, JSON 스칼라. DBLink 원격 열은 스캔 시작에 열마다 한 번.
- **8022 에서 남기는 것은 실행 부품.** 타입 쌍 변환기(`object_domain_convert`, `tp_value_find_converter`), 타입 규칙 모듈(`domain_rules`, 클라이언트·서버 공통으로 이동), 계획된 산술 `DOMAIN_ARITH`, 비교 연산자별 함수. 근거: develop 의 `tp_value_cast_internal` 은 행마다 이중 switch 다(cpp-perf-rules A61·BR-04 확장·CLOW-14 단서).
- **develop 대비 최소 변경.** be683e04c 를 되돌린 위에 위 결정만 얹는다. 세션변수는 첫 SET 타입 고정(-1386), 문자열 MEDIAN/PERCENTILE 은 DOUBLE(-1118 하나), ADDTIME 문자열 바인드는 VARCHAR, 상수 실패 시점·리스트 precision 표시는 develop 으로 복귀, 집합 연산 -456·ELT 병합·분석 AVG(FLOAT) DOUBLE 은 유지.

## Considered Options

- **변수 타입(일반) 플랜을 남기고 서명 상한을 둠**(ADR 0027): 기각. 일반 플랜이 있으면 실행 전 확정 층과 VARIABLE 노드가 남는다. 캐시 비대화의 원인은 타입이 아니라 자동 파라미터가 안 되던 리터럴 값이었다(CUBRIDSUS-8511·8618).
- **노드 밖 계획 표·실행 상태 표**(ADR 0020): 기각. 평가 함수가 바깥을 읽고, PX 소유 검사·번호 정렬 전제가 생기며, 캐시 산정 밖 메모리가 는다.
- **regu 에 목표 도메인·변환기·변환 칸 필드 추가**: 기각. 서명별 플랜에서는 소비자 쪽 develop 구조에 결정을 두면 충분하고, 값의 변환은 클라이언트가 보내기 전에 끝난다(파생 자리).
- **상수 실패를 실행 전에 보고**(8022 사양 변경 1): 기각. 가지 분석 구조가 필요하다. develop 시점으로 복귀.
- **변환기까지 전부 되돌림**: 기각. 행당 이중 switch 로 돌아간다.
- **캐시 키에 별도 서명 문자열을 접미**(뼈대 PR 262 1차, `;bt={…}`): 기각. 키 텍스트는 이미 호스트 변수마다 토큰을 찍고 그 자리에서 값을 읽을 수 있다. 접미사는 `alias_print` 가 캐시돼 다시 찍히지 않는 것을 피하려는 우회였다 — 재컴파일 전에 비우면 된다.
- **XASL 생성이 바인드 결정을 하고 서버가 실행 전에 새 자리로 변환**(뼈대 PR 262 1차, `BIND_CONVERSION`·`qexec_convert_bind_values`): 기각. (1) XASL 생성은 캐시 미스 세션만 돌리므로 적중 세션은 그 결정을 모른다 — 그래서 변환 목록을 스트림에 싣고 서버가 하게 됐다. (2) 클라이언트는 원래 개수만 보내 `qmgr_process_query` 의 `dbval_cnt` 검사가 -452 를 내고, 재컴파일 루프가 타입 없는 플랜으로 답했다(2026-10-16 gdb 추적: 뼈대 스모크의 "변환 한 번" 은 실제로는 develop 플랜이 답한 것). (3) 실행이 캐시된 XASL 에 변환기 포인터를 써 넣었다. (4) 변환 실패가 원래 값을 두어 항의 전제와 어긋나 optdebug assert(`int_col = ?` 에 'abc').
- **변환 불가 값에 별도 서명 플랜**: 기각. develop 이 컴파일 타입 자리에 이미 하는 바인드 시점 오류 하나로 충분하다.

## Consequences

- 스트림 레이아웃(카탈로그 스트림 포함)이 바뀐다. develop 의 디스크 호환 수준은 이미 11.5 이고 미출시이므로 11.5 GA 전에 넣고 구 레이아웃 코덱은 두지 않는다.
- 캐시 키 텍스트의 호스트 변수 토큰에 타입이 붙어 plandump·SQL_ID TC 답이 바뀐다: `where [dba.t].[n]= ?:0 ?193=…;bind_var_cnt=1` → `… ?:0:22 ?193=…`(DB_TYPE 번호), 문자열 ` ?:0:25.3.0 `(타입.codeset.collation id; plandump 실측 2026-10-16, JIRA 사양 변경 1 에 전문). `;bind_var_cnt=N` 은 그대로. 자동 파라미터도 타입·collation 을 찍으므로 `a = 1`/`a = 1.5`, SET NAMES 가 다른 세션은 항목이 갈린다(develop 은 리터럴 collation 을 플랜에 굽고도 키에 없었다). CBRD-27490(바인드 변형)과 키 형식을 맞춘다.
- 숫자 컬럼과 비교하는 `?` 에 변환 불가 값을 주면 행의 -181 대신 바인드 시점 오류이고, 실행되지 않는 분기의 항도 같이 오류다(사양 변경).
- 합격 기준: CTP sql/medium 전수·shell 이 develop 과 같음(사양 변경 제외), 실행당 명령 수가 모든 벤치 셀에서 develop 이하, 문장당 서명 수·캐시 메모리 분포 기록, 체크섬 assert 0.
- 진행: 최신 develop 위 구조 뼈대 PR(fork `xmilex-git/cubrid#262`) → 구조 승인(2026-10-16 `91947b4d3`) → 전체 구현은 CUBRID/cubrid develop 을 향한 PR 하나(뼈대를 cherry-pick 한 `CBRD-27583-impl`). 파생 자리·드라이버 경로의 서명 재컴파일·값 없는 PREPARE 의 XASL 생략은 전체 구현에서.
- develop `b8199438e`(CBRD-27215, 2026-10-16 머지)의 식 스텝 프로그램(`expr_compile.c`·`fetch_arith_ops.c`)은 유지한다. 프로그램 번역은 노드 결정 필드의 낮추기이지 결정이 아니다: 자체 바인드 타입 서명·재컴파일과 8022 해결 표 읽기는 지우고(플랜 하나가 서명 하나), 커널의 tp_* 결정 호출은 해석기와 같은 노드 변환기로 바꾸며, 번역 시점도 실행 중 결정 카운터의 예외가 아니다. 되돌리기(약 12,000 줄)는 하지 않는다: 7658 이 바꾼 답은 이미 develop 의 답이고, 프로그램이 노드 필드만 읽으면 원칙 1~3 과 충돌하지 않는다. 자세한 것은 design.md 4.10, 전수조사 §13.
- 스모크에서 드러난 것: 변환 실패 메시지가 EXECUTE 경로에서 타입 이름을 비운다("Cannot coerce host var to type .", `do_cast_host_variables_to_expected_domain` 이 도메인 포인터를 이름 자리에 넘김) — 전체 구현에서 고친다.
- 전수조사: `docs/research/cbrd27583-row-decision-census.md`.
