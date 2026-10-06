# PR 8022 리뷰 검토 — soheejung-cs 인라인 42건 + 07:23 의 8건 + 설계 리뷰 2건 (2026-10-06, 리뷰 대상 cb0514bb7)

- 대상: CUBRID/cubrid#8022 머리 `cb0514bb7` (= dpin 워크트리 HEAD, fork/dpin).
- 리뷰: soheejung-cs 2026-10-06 07:17~07:23Z 인라인 42건. 원문 `.git_ignored_dir/scratch/pr8022-review-1006/comments.json`.
- 기준: map xmilex-git/workspace#312 의 잠긴 결정 — P0 현행 답 유지(예외 = 크래시·assert), 미확정 도메인 오류(-1383)의 실행 검사, develop 행 시점 해석으로의 폴백 금지, D-356-01, D-372, Out of scope 의 develop 결함 보존.
- 정적 확인: 리드, cb0514bb7. 런타임: Sonnet 워커 3레인(fast-sa, develop f1bd99e optdebug `dpin20/install-dev2-optdebug` vs PR cb0514bb7 optdebug `dpin21/install-c-optdebug`), 산출물 `.git_ignored_dir/scratch/pr8022-review-1006/probes/{a,b,c}`. 레인 A·C 는 StructuredOutput JSON 파손으로 placeholder 를 반환했고 결과는 대화 기록·출력 파일에서 재구성했다.

## 판정 (리뷰 번호 = 게시 순서)

| # | 자리 | 판정 | 처리 |
|---|---|---|---|
| 1 | qexec_groupby 계획 실패 → 미초기화 gbstate 해제 | 실제 결함(PR 유입) | 계획 호출 전 0 초기화 |
| 2 | qexec_execute_analytic 같은 모양 | 실제 결함(PR 유입) | 0 초기화. 세 번째 호출자 orderby_distinct 는 바로 return(안전) |
| 3 | px writer -1383 er_set 누락 | 전제 틀림(정정): `list_columns_unresolved` 가 true 전에 `domain_unresolved_error` 로 er_set(px_scan_result_handler.cpp:72) | 근거로 답변 + 함수 주석 |
| 4 | tp_domain_status_er_set 의 DOMAIN_TRUNCATED | 현재 도달 없음, 계약 빈틈 | case 추가(캐스트와 같은 OVERFLOW 매핑) |
| 5 | -1383 노드 인자 = n_items | 실제 결함(문구) | -1 또는 실패 항목 번호 |
| 6 | 원소 행 항목 NULL → -1383 | 전제 틀림: 표가 원소 타입·등록 collation 전부를 덮음, NULL 원소는 VALUES 에서 다르지 않음 | 근거로 답변(폴백 제안은 Q3 로 거절) |
| 7 | IMPLICIT 변환기 탐색의 JSON | 전제 틀림: 캐스트는 JSON 을 먼저 벗기고 develop 과 같은 타입으로 검사, 해시 스캔은 JSON 을 tp_value_coerce 로. 탐침 4파일 develop = PR | 근거로 답변 |
| 8 | B-tree 키 비교의 표 NULL 폴백 없음 | 실제(OOM 전용) | 형제와 같은 폴백 |
| 9 | 플랜 노드의 누산기 도메인 | 맞음 — PR 이 추가한 operand_coercion·temporary 도 노드에 씀 | Q13: 실행 도메인으로 이동 |
| 10 | copied_from_leader 확인 장치 | 보강 | Q12 assert 커밋(clone_xasl 의 `m_xasl->domain_plan` 과 리더 계획 개수 비교) |
| 11 | 왜 실행 직전인가 | 보강 | 헤더 문단 |
| 12 | object_domain_convert.h 의 numeric_opfunc.h | 이름 없는 enum(DB_DATA_STATUS) 이라 전방 선언 불가, 두 공유 프로토타입 때문 | 답변 + object .c 의 domain_rules.h 이유 주석 |
| 13 | 스펙 변경 4·1 재현 불가 | 리뷰어 SQL(`where 1 = 0`)은 컴파일이 접음. 문서 SQL·행으로 비는 가지는 재현(develop 값 vs PR -456/-454) | SQL 로 답변 |
| 14 | 행 경로 날짜 변환 오류 코드 | 전제 틀림: 지적 자리는 문자열→문자열, develop 행 경로도 -181. 탐침 약 1,400문장 사용자 오류 코드 전부 같음 | 근거로 답변 |
| 15 | CONNECT BY 해시 probe NUMERIC 휴리스틱 | develop 결함 확인: 리뷰어 TC 해시 5행 vs NO_HASH 9행, develop = PR, select 목록 순서에 따라 답이 바뀜 | develop 동작이라 범위 밖, workspace 이슈 |
| 16 | NVL 계열 문자 규칙 default | 리뷰어 맞음 — 아래 16-a·b·c | develop 답으로 되돌림 |
| 17 | release DIRECT/CONVERT 값 타입 미검사 | 맞음(D-368-08) | 주석·본문 한 줄 |
| 18 | VALUES 비교의 -1383 | 탐침 약 66,000문장 -1383 0건 | 정책 유지(Q3), VARIABLE 쪽 형태 열거 + TC. 탐침이 드러낸 18-1~4 는 아래 |
| 19 | 인덱스 스트림 검사 단일 관문 | 보강 | Q12 assert 커밋 |
| 20 | tp_value_coerce_strict src == dest | develop 동작, 호출자 없음 | 답변만(별도 이슈) |
| 21·22 | TIMESTAMP→DATE decode 실패 무시 | develop 에 같은 비대칭(object_domain.c:8591 vs 8598), PR 은 기계적 추출 | 답변만(별도 이슈) |
| 23·24 | tp_value_convert 계약 주석 | 보강 | 주석 |
| 25 | dblink const 벗김 | 맞음 | const 인자 |
| 26 | domain_set_links 재호출 | 보강 | Q12 assert 커밋 + 주석 |
| 27 | 256 상한 변수명 | 맞음 | depth 이름·상수 + Q12 assert |
| 28 | ROW 분기 센티넬 | 맞음 | domain_stream_by_keys |
| 29 | 실행 도메인 배열 상한 | 번호 매김이 보장(assert 존재) | D-372: 릴리스 검사 없이 주석 |
| 30 | can_compare NULL | 맞음 | 가드 |
| 31 | ENUM collation 차이 | 맞음 | 키 정의와 같은 조건 |
| 32 | ENUM 가지 ELT/CASE | develop = PR, -1383 없음(공통 파서 assert 는 develop 결함) | 답변 |
| 33 | 가지 변환 실패 상태 평탄화 | 맞음 | tp_domain_status_er_set |
| 34 | fetch_constant_evaluated 가드 | 보강 | 주석 + Q12 assert |
| 35 | 지운 함수 이름 | 맞음 | 주석 |
| 36 | qfile_unify_types 빈 쪽 collation 검사 생략 | 계획 도메인은 NORMAL(로드 검사) | 주석 |
| 37 | PX 잡당 깊은 복사 | develop 도 잡마다 바인드 값을 전부 복제, PR 은 표 memcpy 추가 | 답변 |
| 38 | deep copy 실패 오류 덮어쓰기 | 맞음, 같은 모양이 px_scan_task.cpp:656 에도 | 두 자리 수정 |
| 39 | 누산기 공유의 실행 도메인 | 탐침 develop = PR, avg = sum/count 246건 | Q12 assert |
| 40 | eval_resolved_comparison 완화 | 보강 | 주석 + Q12 assert |
| 41 | OBJECT/KEYS 의 dbval vs value[] | 맞음 | value[] 전달 + Q12 assert |
| 42 | 해시 스캔 FAIL -181 → -1383 | 설계 충돌(P0, D-356-01, #361) — 문구까지 develop 과 같음(탐침 30/30 `Cannot coerce value of domain "numeric" to domain "*variable*"`) | 유지 + FAIL 주석 |

## 탐침이 드러낸 develop / PR 차이 (스펙 변경 문서에 없음)

- 16-a `nullif/least/greatest(?, char5_col)` 에 'AB': develop 'AB' / 'AB   ', PR NULL / 'AB'(리터럴·`=` 와 같음) — PR 의 답 변경. 원인(gdb, w4/d1): 비교 계획이 아니라 클라이언트의 바인드 캐스트다. #330 `51880e7c8` 이 같은 타입 문자열 변환기에 넣은 clone 빠른 경로가 ENFORCE collation 바인드(VARCHAR 기대, CHAR 값)를 CHAR 로 남겨 `mr_cmpval_char`(후행 공백 무시)로 비교했다. develop 은 `db_char_string_coerce` 로 VARCHAR 목표에 쓴다. 빠른 경로 제거 `a4d174c57`.
- 16-b `nvl/ifnull/coalesce(iso88591·euckr CHAR 컬럼, ?)` 의 GROUP BY·DISTINCT·ORDER BY·윈도 키: develop 3그룹, PR 4그룹(리터럴과도 다름) — 회귀.
- 16-c `nvl2(c1, v1, ?)` 정렬: develop CHAR 의미(1,2,3,5,4), PR VARCHAR 의미(1,3,5,2,4 = 리터럴) — PR 의 답 변경. 16-b 와 원인 같음(NVL 계열이 문자 규칙 default MERGE → VARCHAR).
- 18-1 `> any (select concat(?, ?) …)` NULL 바인드: develop optdebug assert(query_executor.c:1355), PR 정상 — develop 결함.
- 18-2 `cs = any (select concat(?, ?) from tb union all select cs from tb)` NULL,NULL: develop -1150(qfile_unify_types collation 플래그 검사, develop list_file.c:933 — NULL 만 받은 식의 collation 이 정해지지 않은 채 UNION 에 닿음), PR 값. develop 결함 계열(§11 D2·D6).
- 18-3 `select ta.id, q.k from ta, (select ? k from tb) q where ta.ci = q.k` 에 '1': develop q.k = 1.0e+00(비교의 제자리 변환 흔적), PR '1'.
- 18-4 union of binds + `where k = 'a'`: develop -181, PR -456(§5 부류). if/ELT/CASE/DECODE 날짜 바인드의 -181 인자: develop "date"·"numeric", PR "character"·"integer".

## 첫 수집에서 빠진 8건 (07:23:31~41Z, 티켓 번호 50~57)

| # | 지적 | 판정 | 처리 |
|---|---|---|---|
| 50 | 해시 리스트 스캔 빌드 키 절단 TC 없음 | 탐침: NO_MERGE+WHERE·DISTINCT·UNION ALL 파생 테이블이 해시 리스트 스캔에 닿고, 절단이 필요한 빌드 값은 develop·PR 모두 -181(NO_HASH_LIST_SCAN 은 행). BIT 프로브는 컴파일러가 캐스트 | TC 22 (develop 답) |
| 51 | TRUNCATED → `tp_domain_status_er_set` 무오류 | W3 `c788b2bf0` 이 이미 막음 | 커밋으로 답변 |
| 52 | 단일 컬럼 분기가 fetch range 를 구분 안 함 | 맞음(도달 불가: ISS fetch range 키는 F_MIDXKEY 뿐) | `bound` 한 번 `8975ddab8` |
| 53 | pisid 미러 static_assert 둘 없음 | 맞음 | `8975ddab8` |
| 54 | MRO `key_plan` 검사가 행 경로 | 전제 틀림: develop 의 스캔당 1회 블록 안, 보장자 `scan_open_index_key_plan` | 주석 `8975ddab8` |
| 55 | SA 표 final 두 번 사이 재생성 | 전제 틀림: SA 정상 종료는 EXCEPT_COMMON_MODULES 라 한 번, 둘 다 도는 경로는 emergency_patch 뿐이고 final 은 멱등 | 답변 |
| 56 | 부팅 표 비용 수치 | 측정(게이트 3) | 수치로 답변 |
| 57 | `analytic_sum_avg_function_info` 공용체 크기 | W5 `590e1c707` 이 구조체를 없앰 | 커밋으로 답변 |

설계 리뷰 48·49(08:53Z)는 D-379-23·24 로 답변 게시(batch2). 49 의 후속(09:49Z, 변환기 정책 행렬 주석)은 행렬을 gdb 로 다시 뽑아 대조한 뒤 넣는다.

## 결과 (2026-10-06 저녁)

- 게이트 2(`696cc54a7`): 1·2번의 release gdb jump 재현이 `Query execution failure #5451`/`#21647` 오류로 끝난다(크래시 0). W7 assert 중 27번(체인 상한)만 발화 — CONNECT BY 가 분할 테이블·조인 위일 때 sql 80 + medium 2 케이스; gdb 로 2개짜리 순환(regu_list_pred 위치 ↔ outptr_list 값 포인터) 확인, 제거 `ba1d836df`. 10·19·26·31·34·40·41·46 은 미발화 → 유지.
- W8 센서스: CTP sql 17497/17497 + medium 975/975 에서 VALUES 로 계획된 비교 0건(계측 빌드, gdb 강제 양성 대조).
- W4c: TC answer 에 실린 -181 문구와 PR 문구가 다른 자리 없음(sql answer 는 코드만, private-ex 는 문구 없음) → 엔진 변경 없음, 23문장 차이는 스펙 문서 §13.
- D-379-31: 산술·SUM/AVG 상수 피연산자 변환을 G1 으로(`8b18bc895`), 산술 규칙의 파라미터 읽기를 필요한 경로로(`90501f34e`).

## 결정 (grill-with-docs 세션, 2026-10-06)

- Q1 map #312 아래 새 티켓(dpin-22)에 검증표·결정·커밋 계획.
- Q2/Q11 42번 -181 유지 + FAIL 주석.
- Q3 18번: VALUES + -1383 실행 검사 유지, 행 비교 폴백·KEYS 없음. VARIABLE 쪽 형태 열거 + TC, 닿는 형태가 나오면 실행 전 확정을 고친다.
- Q4 29번: assert 유지 + 성립 근거 주석(D-372).
- Q5 20·21·22번: "develop 에서도 나는 동작, 별도 이슈" 답글만.
- Q6/Q13 누산기 도메인(value_dom·value2_dom·operand_coercion·temporary), g_agg_domains_resolved(→ 보간 첫 값 확인 대기, value_dom 은 셋업에서), 분석 sum_avg.operand_coercion 을 실행 도메인으로 옮긴다.
- Q14 그 커밋만 release 벤치 A/B(집계·분석·GROUP BY·PX 셀, develop 대비 +5%, D-345-01), 행은 블록 진입 때 잡은 포인터로.
- Q7 결함 수정·주석 일괄 수용, 12번은 답변 + 주석, 25번 수용.
- Q8 리드가 구현, 런타임은 Sonnet/xhigh 워커.
- Q9 답글 초안(한국어) → 승인 → push 뒤 게시.
- Q10 `/cubrid-pr-sync 8022` 로 develop 먼저.
- Q12/Q21 리뷰어 제안 assert(10, 19, 26, 27, 34, 39, 40, 41)를 한 커밋으로 넣고 optdebug CTP sql·medium. 터진 것은 그 SQL 을 근거로 빼고 반박, 안 터진 것은 둔다. shell 은 upstream CI 에서 같은 방식.
- Q15 보간 첫 값 확인(-1118/-181 구분) 유지 — 도메인을 바꾸지 않는다(셋업의 도메인을 확인할 뿐). CONTEXT.md 용어 추가.
- Q16 15·20·21·22번은 workspace 이슈 하나로 추적, JIRA 는 요청 시에만.
- Q17 순서: pr-sync(+ develop 머리 optdebug 빌드) → A/B 재확인(Q22) → 수정 커밋들 → 게이트 → push(확인) → 답글 → `/run all`.
- Q18 기준: develop 이 크래시·assert 인 자리만 문서화, 나머지는 develop 답·코드·문구로 되돌린다. 16-a·b·c 와 18-4 의 -181 인자는 되돌림, 18-1·18-2 는 §11(NULL 만 받은 식의 collation 미결정 계열), 18-3 은 §3, 18-4 의 union -456 은 §5 표. 되돌리는 데 행 시점 판단이 필요하면 멈추고 다시 묻는다.
- Q19' PR 이 만든 답 변경은 이 티켓 범위(범위 추가 기록).
- Q20 되돌린 답(16-a·b·c)을 develop 답으로 고정하는 TC 를 `tc/pr-8022` `_36_guava/cbrd_27510/` 에. 1·2번은 gdb jump 재현을 증거로.
- Q22 같은 develop 기준(sync 머리)으로 차이 문장 A/B 재확인 뒤 되돌리기.
