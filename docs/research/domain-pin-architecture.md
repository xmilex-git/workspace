# 도메인·collation 사전 확정 — 아키텍처 §1 전략 (정본)

지도: xmilex-git/workspace#312 · 티켓: #318(전략) · 짝 티켓: #323(인터페이스 design-it-twice) · #325(변환기 표·계획 슬롯·게이트 표) · 작성 2026-09-22 · 기준 엔진: `develop` `cad27172b`(워크트리 `~/dev/cubrid-worktree/dpin`).
입력: 규칙표 `domain-pin-rule-table.md`(P0~P7, §2~§6 확정 시점 C/G/X·부류 K/R/S) · 실행 지점 전수 `domain-pin-exec-sites.md`(S-01~S-43, G-01~G-08) · 파서 규칙 `domain-pin-rules-parser.md` §2 · 서버 규칙 `domain-pin-rules-server.md` §6 · 렛저 `domain-pin-lessons.md`(L-08, L-40~L-49 전부 §7 대응표) · #318 코멘트 "#317 에서 넘어온 필수 입력" 1~7.
결정 기록: #318 코멘트 "결정 기록"(D-318-nn). 이 문서의 §1.4 "선택" 은 그 코멘트가 잠근 뒤에만 정본이다.

인용 표기는 `domain-pin-exec-sites.md` 와 같다(`fe:` fetch.c, `qx:` query_executor.c, `qe:` query_evaluator.c, `sx:` stream_to_xasl.c, `xs:` xasl_to_stream.c, `xg:` xasl_generation.c, `pd:` parse_dbi.c, `vdb:` db_vdb.c, `qm:` query_manager.c, `pxt:` px_scan_task.cpp, `pxq:` px_query_task.cpp, `co:` class_object.c). `cpp-perf-rules` 규칙은 ID 로 인용한다.

이 문서가 정하는 것은 **전략(방향·기각)** 이다. 자료구조·함수 시그니처·호출 순서는 #323 이, 변환기 표·슬롯 ID·게이트 표의 형태는 #325 가 정한다.

---

## 1.1 seam 스캔 — 현행 코드에서 도메인 결정이 사는 곳

`codebase-design` 어휘: **모듈** = 인터페이스 + 구현, **seam** = 행동을 바꿀 수 있는 위치, **깊이** = 인터페이스 단위당 숨겨진 행동량.

현행에는 "이 regu 의 도메인은 무엇인가" 를 소유하는 모듈이 **없다**. 인터페이스는 `regu->domain` 필드 하나인데, 그 필드를 43곳(S-01~S-43)이 실행 중에 읽고·쓰고·복원한다 — 인터페이스가 구현만큼 넓은 **얕은 모듈**의 극단이며, 삭제 테스트를 하면 복잡도가 43곳으로 흩어져 되살아난다. 아래 표는 그 결정이 통과하는 seam 을 로드 경로 순서로 잡은 것이다.

| # | seam | 위치 | 현행 행동 | 관찰(전략 제약) |
|---|---|---|---|---|
| M1 | 컴파일 → 스트림 | `pt_make_regu_hostvar` xg:6391~6510; `xts_process_regu_variable` xs:5377(도메인을 regu 앞에 pack); 도메인 pack 지점 6곳(regu·arith·agg·analytic·pos_descr·list type) | 슬롯 도메인 결정 순서 = data_type → **바인드 값 타입**(set_host_var==1 이면) → expected_domain → type_enum(MAYBE→VARIABLE). 스트림 헤더는 `dbval_cnt`+OID 목록뿐(xs:292~305) | (a) 도메인은 **이미 노드마다 스트림에 실린다** — 빠진 것은 값이 VARIABLE/LEAVE 인 것이지 자리가 아니다. (b) 2단계(값 타입)는 플랜을 바인드 값에 종속시킨다(M7). |
| M2 | 스트림 → 트리(로드) | `stx_map_stream_to_xasl` sx:212~272 — 호출자 3: xcache 클론(`xcache_find_xasl_id_for_execute` → sx), 비캐시(`qmgr_process_query`), **PX 워커 자체 unpack** pxt:623; `stx_build_regu_variable` sx:5607 이 `original_domain = domain` 을 로드 시 도출(sx:5615·5861·5874·5982·6259·6844) | 로드는 결정하지 않지만 "로드 시 도출해 비팩 필드에 두는" 전례(`original_domain`)가 있다 | 세 로드 경로가 **한 함수**를 지난다 → 로드 시 1회 도출 패스의 seam 은 하나(L-40 의 세 경로 문제가 이 seam 하나로 닫힌다). |
| M3 | 온디스크 스트림 | 필터 predicate `pred_stream` 은 카탈로그에 VARCHAR 로 저장(co:845~848), 함수 인덱스 `expr_stream` 동일(class_object.h:511); 둘 다 `stx_map_stream_to_filter_pred`/`_func_pred` 로 regu·arith·pred 코덱을 **그대로** 쓴다 | — | **regu·arith·pred·domain 의 스트림 레이아웃은 디스크 포맷이다.** 바꾸면 기존 DB 의 필터/함수 인덱스가 깨진다(버전 분기 없음). xasl_node 헤더·access spec(INDX_INFO) 레이아웃은 디스크에 없다. `flags` 정수의 미사용 비트 추가는 레이아웃 불변. |
| M4 | 실행 진입 | `qexec_execute_query` qx:17456: `xasl_state.vd.dbval_ptr = (DB_VALUE *) dbval_ptr`(const 캐스트; SERVER_MODE 는 qm:1427 qmgr 사설 힙 배열, **SA_MODE 는 클라이언트 `parser->host_variables` 그 자체** qm:1441) → `qexec_execute_mainblock` → `_internal` qx:16150: aptr 실행 qx:16538 → 비상관 스칼라 서브쿼리 precompute qx:16696 → `qexec_start_mainblock_iterations` qx:16720 | 서버 측 "값 ← 도메인" 변환 0줄(#314 관찰 1) | 게이트 K 부류 자리 = vd 형성 직후·mainblock 전(G-01). S 부류(aptr 리스트·precomp 결과·상관 값) 자리 = 블록마다 aptr 뒤·iterations 시작 전(D-317-18). SA_MODE 별칭 때문에 게이트가 **입력 배열을 제자리 변환하면 클라이언트 값이 바뀐다**. |
| M5 | 실행 상태 | `XASL_STATE` = {`VAL_DESCR vd`(dbval_ptr·dbval_cnt·sys_datetime·epoch·lrand·drand·back-ptr, 48B), query_id, qp_xasl_line}(query_executor.h:74~93); aptr/dptr/상관 서브쿼리는 같은 포인터(`EXECUTE_REGU_VARIABLE_XASL` xasl.h:554) | 실행당 하나 | 실행별 상태의 집은 이미 있다(P5). 게이트 표는 여기에 붙는다. |
| M6 | PX 상속 | `qexec_deep_copy_xasl_state` qx:3678(pxq:123 잡마다, px_query_executor.cpp:48 루트) — vd 를 복사하고 `dbval_ptr[]` 을 `pr_clone_value` 로 깊은 복사; **두 번째 복사 경로** pxt:648 `memcpy(m_vd, m_orig_vd)` + clone 루프(같은 일을 따로 구현) | 워커는 값 배열 사본을 받고 도메인은 각자 resolve(S-34~S-37) | 상속 seam 이 둘이다 → 하나로 합쳐야 게이트 표 상속이 한 곳에 산다. 워커 사본은 워커 힙 소유·워커가 해제(ALLOC-08/A64 충족 조건). |
| M7 | 클라이언트 바인드·재계획 | `pt_set_host_variables` pd:3072(CAS 가 expected_domain 으로 `tp_value_cast_preserve_domain`); `do_replan_statement_with_bind_peek` vdb:3496(첫 실행에 값을 바인드한 채 `do_prepare_statement` 재생성 → M1 2단계가 **값 타입**을 regu 도메인에 실음 → 같은 sha1 캐시 항목 교체) | 클라이언트가 값을 캐스트(D-M4 반대) + 재계획 플랜이 첫 바인드 타입에 종속 | 클라이언트에 숨은 **세 번째 결정 지점**(바인드 피크 재계획의 값 타입 도메인)이 있다. L-49 가 "오답 없음" 이었던 이유는 실행이 값 타입만 읽어서였다 — 게이트가 계획 도메인으로 변환하는 순간 이 플랜은 첫 바인드 타입을 다른 실행에 강제한다 → 2단계는 삭제 대상. |
| M8 | fetch·비교 행 경로 | `TYPE_POS_VALUE` fe:4745(vd 포인터 반환, `FETCH_ALL_CONST` 를 **실행 중 플랜 플래그에 기록**), `eval_value_rel_cmp` qe:220~276(상수 제자리 coerce + 힙 전환 qe:227, L-46 원인), `qexec_clear_regu_var` qx:1519(도메인 원복·플래그 클리어·FAST_PEEK 클리어) | 상수성·도메인이 행 경로에서 결정되고 클론 종료 시 원복 | `FETCH_ALL_CONST`/`FAST_PEEK`/`AGG_OPERAND`(qx:21839 워커마다 재도출)는 **트리 모양의 순수 함수**인데 실행마다 재도출·원복된다(A59·A62 — 불변 값을 행 루프에서 다시 씀). 로드 시 1회 도출로 옮기면 사라지는 부류. |
| M9 | 게이트 밖 로드 | `fpcache_claim`·filter pred 스트림: 실행 진입 없음, 오류 삼킴(S-42) | — | 경계 (a) 의 예외 입구. 슬롯이 없으므로 GATE 표시가 있으면 로드 거부. |

**seam 스캔의 결론 세 줄.**
1. 계획의 *자리*는 이미 스트림에 있다(M1a). 새로 실어야 할 것은 도메인 **값**(VARIABLE/LEAVE → 확정 도메인)과 인덱스 키 도메인(`key_type`, L-45(f))뿐이고, 후자는 디스크에 없는 access-spec 레이아웃이다(M3).
2. 결정이 아닌 **도출**(슬롯 ID·피연산자 부류·변환기 선택·게이트 의존 노드 목록)은 로드된 트리의 순수 함수이므로 로드 seam 하나(M2)에서 1회 계산해 비팩 필드에 둘 수 있다 — `original_domain` 전례, `FETCH_ALL_CONST` 재도출(M8)의 정반대.
3. 실행별 상태(변환된 슬롯 값·게이트 표)의 집(M5)과 상속 seam(M6)은 있으나 상속 경로가 둘이다.

`/improve-codebase-architecture` HTML 보고서는 이 세션이 만들지 못했다(스킬이 모델 호출 금지 — 사용자가 직접 실행). 위 표가 그 대체 산출물이며, 보고서를 원하면 사용자가 스킬을 실행해 이 표와 대조한다(D-318-09 로 결정).

---

## 1.2 후보 전략

세 후보는 "결정은 컴파일·게이트 두 곳"(D-M3)을 공유하고 **계획을 어디에 어떤 형태로 두는가**에서 갈린다.

| | **A. 도메인은 스트림, 도출은 로드, 상태는 XASL_STATE** | **B. 명시 계획 표를 스트림에 팩** | **C. 서버 게이트 전면 타입 패스** |
|---|---|---|---|
| 계획 표현 | 컴파일이 **기존 도메인 필드**(regu·arith·agg·analytic·pos_descr·list type)를 전부 확정 도메인으로 채운다(VARIABLE·LEAVE 0). 게이트 확정 슬롯은 `regu->flags` 의 새 비트 1개. 인덱스 키 도메인은 `INDX_INFO` 에 `key_type` 추가. 슬롯 ID·부류(K/R/S)·변환기·게이트 의존 노드 목록은 **로드 시 1회 도출**해 비팩 필드(`original_domain` 자리)에 둔다 | 컴파일이 슬롯 표(슬롯 ID → 바인드 도메인/collation 또는 GATE 규칙 ID)와 변환기 표(노드 참조 → 변환기 ID)를 만들어 XASL 스트림의 **새 섹션**(헤더) + 노드마다 `plan_idx` 정수로 팩 | 컴파일은 현행(슬롯 VARIABLE + expected_domain 슬롯 표만 스트림), 서버 게이트가 실행마다 트리 전체에 타입 추론 패스를 돌려 XASL_STATE 오버레이에 도메인·변환기를 채운다 |
| 스트림·디스크 | regu/arith/pred **레이아웃 불변**(플래그 비트만) → 필터/함수 인덱스 스트림 호환(M3). access spec 레이아웃만 변경(디스크 없음) | regu/arith/pred 에 `plan_idx` → **디스크 포맷 변경**(필터/함수 인덱스 스트림) → 버전 분기 또는 두 레이아웃 | 슬롯 표 섹션만 추가, 노드 레이아웃 불변 |
| 진실의 원천 | 도메인 1곳(노드 필드). 변환기는 도메인의 순수 함수 | 도메인이 노드 필드 **와** 계획 표 두 곳(P6 위반 위험: 둘이 어긋나면 누가 맞나) | 도메인이 실행마다 새로 생김(플랜에 없음) |
| 게이트 비용 | K 슬롯 변환 N회 + G 노드 목록 길이만큼(정적 계획이면 **0 순회**) | 같음 | **트리 전체 순회 매 실행**(정적 계획도) — #318 입력 3 "정적 계획 슬롯은 순회 0" 위반 |
| 그리드 소재 | C 행 = 파서 그리드(현행), G 행 = 서버 값 그리드(현행 늦은 바인딩 코드를 한 모듈로 모음). 두 그리드는 현행 그대로(P0, #321 §5 의 24행 불일치 유지) | 클라이언트가 R/G 행의 변환기까지 골라야 하므로 **서버 값 그리드를 클라이언트에 복제**(같은 규칙 두 코드, P6) | 서버 그리드가 파서 그리드를 다시 구현(두 그리드 경쟁, P0 답 유지 어려움) |
| prepare 응답 메타(L-31) | 컴파일 도메인 → 그대로 | 그대로 | 게이트 전엔 미확정(L-24 구멍 전면) |
| 이전 캠페인 대비 | L-40(스트림 무변경 로드 도출)·L-41(파생 소비자 계획 포함)·L-42(플랜 불변)·L-46(워커 결정 0) 을 전부 구조로 흡수 | L-40 이 피한 pack/unpack·arena·6 루트 부착 문제를 다시 연다 | 이전 캠페인 "잔여 확정" 의 확대판 — L-40·L-41 이 실패한 모양 |
| 위험 | 로드 도출 패스가 PX 워커 unpack 마다 돈다(트리 크기 비례, unpack 자체와 같은 차수); 도출 규칙이 컴파일 결정과 어긋나면 로드 경계가 잡아야 한다 | 스트림 크기·xcache 메모리 증가, 클라이언트·서버 표 동기화 | 실행당 O(트리) 고정 비용, 컬럼 메타 |

**기각 사유.**
- **C 기각**: 정적 계획에도 매 실행 트리 순회(BR-04 의 반대 방향: 불변 결정을 실행마다 재계산), 파서 그리드를 서버에 복제, prepare 응답 메타 불가, 이전 캠페인이 실패한 모양(L-40·L-41). D-M3·D-317-18 과 상충.
- **B 기각(전면 채택으로는)**: 필터/함수 인덱스 스트림이 디스크 포맷이라 노드 레이아웃 변경은 마이그레이션 없이는 불가(M3); 도메인의 진실 두 곳(P6); 클라이언트에 서버 값 그리드 복제. 단 B 의 "명시 표" 장점(플랜 덤프로 검사 가능)은 A 에서 **로드 도출 결과를 `SHOW PLAN`/trace 에 출력**하는 것으로 얻는다(#323 항목).
- **D(플랜 캐시 타입 변형)**: Out of scope(D-M3) — 재론 없음.

**권고: A.** 근거는 §1.1 결론 1~3 그대로다 — 자리는 있고 값만 없다, 도출은 순수 함수다, 상태의 집은 있다.

---

## 1.3 전략 A 의 결정 1~5 (방향; 형태는 #323·#325)

### 결정 1 — 변환 계획의 표현
- **컴파일이 채우는 것(스트림 값 변경, 레이아웃 불변)**: G-03 (a)~(f) 전 항목의 도메인 필드를 C 규칙 결과로 확정. `DB_TYPE_VARIABLE`·`TP_DOMAIN_COLL_LEAVE` 는 XASL 에서 사라진다(§6 귀결). 게이트 확정 슬롯·게이트 의존 노드(예: `? + ?` 의 arith, `sum(?)` 의 agg)는 도메인 자리에 **placeholder 도메인 + GATE 플래그 비트**를 싣는다(placeholder 의 정확한 값 — NULL 도메인 vs VARIABLE 유지 — 는 #325; 경계 (a) 는 "GATE 플래그 없는 VARIABLE" 만 거부하도록 짝을 맞춘다).
- **컴파일이 새로 싣는 것(레이아웃 변경, 디스크 없음)**: `INDX_INFO.key_type`(인덱스 키 도메인, L-45(f)) — 로드 시 키 변환 계획 도출의 입력. 그 외 노드 레이아웃 변경 0.
- **로드가 도출하는 것(비팩 필드)**: 슬롯 ID(트리 순회 순서로 결정적 부여 — 세 로드 경로가 같은 ID 를 얻는다), 피연산자 부류 K/R/S(regu 타입에서: `TYPE_POS_VALUE`/`TYPE_DBVAL`/상수 부분트리 = K, `TYPE_ATTR_ID`·`TYPE_POSITION` 하위 = R, 상관 `TYPE_CONSTANT`·외부 `TYPE_POSITION`·aptr 결과 = S — 현행 `FETCH_ALL_CONST` 지연 도출의 로드 시 버전), 비교·산술·키 원소·대입의 **변환기**(현행 서버 변환 표를 (원 도메인, 목표 도메인) → 함수 ID 로 옮긴 표에서 조회, D-317-16·19), **게이트 의존 노드 목록**(GATE 슬롯을 피연산자로 갖는 노드를 생산자 우선 순서로 모은 배열 — 게이트는 이 배열만 돈다), K 부류 상수 부분트리의 계획 슬롯(게이트가 1회 평가해 캐시할 자리). 저장 위치는 `original_domain`/`original_opr_dbtype` 이 있던 자리(필드 수·구조체 크기 증가 0, MEM-02).
- **호스트 변수/auto-param 슬롯 인덱스와의 대응**: 슬롯 ID ≠ `val_pos`. `val_pos` 는 바인드 배열 인덱스(사용자 `?` + auto-param), 슬롯 ID 는 계획 항목 인덱스(게이트 표 인덱스). 한 `val_pos` 를 여러 regu 가 참조할 수 있으므로(키 range regu + 잔여 필터 regu 등) 바인드 값 변환은 `val_pos` 당 1회(바인드 도메인 = 그 `?` 의 미러 도메인, 참조 regu 간 도메인이 다르면 K 변환기가 게이트에서 1회 더 적용), 게이트 표 항목은 슬롯 ID 당 1개. 두 인덱스 공간의 대응은 로드 도출 결과에 저장한다. **한 `val_pos` 의 참조 regu 들이 서로 다른 바인드 도메인을 요구하는 경우가 실제로 있는지**는 #323 이 탐침으로 확인한다(있으면 바인드 도메인은 "가장 좁은 공통" 이 아니라 참조별 K 변환기로 푼다 — 결정 자체는 여기서: 슬롯 값은 1회 변환, 참조별 차이는 변환기).
- **스트림 포맷·플랜 캐시·클론 호환**: 스트림 코덱 변경은 `INDX_INFO` 1곳 + `flags` 비트 → 클라이언트·서버 lockstep 은 현행 요구 그대로(같은 빌드), 디스크 호환 유지. 플랜 캐시 키·클론 풀 변경 없음. 로드 도출은 xcache 클론당 1회(클론 풀 재사용 시 재도출 0), PX 워커 unpack 당 1회.
- **기각**: regu/arith/pred 레이아웃 변경(M3), 계획 표를 스트림에 별도 섹션으로(B), 슬롯 ID 를 컴파일이 부여해 팩(레이아웃 변경 + 세 로드 경로 동기화 문제 재현).

### 결정 2 — 서버 게이트
- **위치·횟수**: 게이트는 **두 단계, 결정은 한 곳**이다.
  - **G1 실행 게이트(실행당 1회)**: `qexec_execute_query` 가 `vd` 를 만든 직후·`qexec_execute_mainblock` 전(qx:17579 다음). 하는 일 — ① `vd.dbval_ptr[]` 의 각 `val_pos` 를 바인드 도메인으로 변환(K 슬롯; 실패 = 실행 전 오류, 현행 -494 계열 코드 유지 B4·U0) ② GATE 슬롯의 도메인·collation 을 값에서 확정(값 타입 + `LANG_RT_COMMON_COLL` 병합, C3) ③ 게이트 의존 노드 목록을 생산자 우선으로 1회 돌며 파생 소비자(산술 결과·리스트 컬럼·누산기·정렬 키·비교 도메인·변환기)를 게이트 표에 채움 ④ K 부류 상수 부분트리를 1회 평가해 계획 슬롯에 캐시(현행 `FETCH_ALL_CONST` 제자리 coerce 대체, L-46). 정적 계획(GATE 슬롯 0)은 ②③ 이 빈 배열 순회 = 0.
  - **G2 블록 게이트(XASL 블록당 1회, 결정 0)**: `qexec_execute_mainblock_internal` 의 aptr 실행·precompute(qx:16538~16716) 뒤·`qexec_start_mainblock_iterations` 전. 하는 일 — S 부류(비상관 서브쿼리 결과·aptr 리스트 컬럼)를 계획된 변환기로 소비 블록 도메인에 맞춘다. 상관 키·조인 키(range 마다)는 range open 에서 같은 변환기를 값에만 적용(전략 재추론 0, L-45(a)(b)). 여기서 도메인을 *정하는* 코드는 없다(D-317-18 의 "블록마다" 는 이 G2 를 뜻한다).
- **게이트가 만든 값의 소유**: 변환된 슬롯 값은 **XASL_STATE 가 소유하는 별도 배열**에 둔다(`vd.dbval_ptr` 는 그 배열을 가리키고 입력 배열은 `const` 로 남긴다). 이유 — SA_MODE 에서 입력 배열은 클라이언트 `parser->host_variables` 자체(M4)라 제자리 변환은 클라이언트 값을 바꾼다; 결과 캐시 키(`params.vals`)·`copy_bind_value_to_tdes` 는 원 값 기준이므로 게이트 전 사본이 맞다. 해제 = 만든 스레드가 `qexec_execute_query` 종료 시(연결 스레드) — 실행 중 어느 워커도 이 배열을 해제하지 않는다.
- **PX 상속**: `qexec_deep_copy_xasl_state` **하나**가 값 배열 + 게이트 표를 워커 힙에 깊은 복사한다(pxt:648 의 별도 memcpy 경로는 이 함수 호출로 대체). 워커는 자기 사본을 자기가 해제(ALLOC-08/A64 만족), 도메인을 정하지도(S-34·S-36) 역전파하지도(S-35) 않는다(D-M3, G-06). 워커가 unpack 한 트리는 같은 로드 도출을 거치므로 슬롯 ID 가 루트와 같다.
- **기각**: 게이트를 `qmgr_process_query`(qm:1237, 언팩 직후)에 두는 것 — XASL_STATE 가 아직 없다; 게이트를 스캔 open 마다 두는 것(L-41 의 MERGE 하위 문제를 이유로) — 결정이 블록마다 반복된다(D-317-18 은 결정이 아니라 변환의 블록 단위 적용).

### 결정 3 — 삭제 경계(검증 경계)의 형식
- **경계 (a) 로드**: 로드 도출 패스 끝에서 "GATE 플래그 없는 VARIABLE/LEAVE 도메인" 을 거부. 예외 표(설계상 VARIABLE 인 자리: `TYPE_REGU_VAR_LIST` 포장 노드·분석 윈도우 정렬 키·집합 연산 컬럼, L-48(a))는 #323 이 로드 도출 코드 옆에 **표로** 둔다. 필터/함수 인덱스 스트림 로드(`stx_map_stream_to_filter_pred`/`_func_pred`)는 GATE 플래그가 하나라도 있으면 거부, `fpcache_claim` 의 오류 삼킴(S-42)은 이 PR 에서 고친다.
- **경계 (b) 실행**: 삭제한 지점마다 optdebug `assert` + release **전용 오류 코드** 반환. 코드는 **새로 하나**(`ER_QPROC_UNRESOLVED_DOMAIN` 류, 이름은 #323) — `ER_QPROC_INVALID_XASLNODE` 재사용 **기각**: 클라이언트가 그 코드를 받으면 xasl_id 를 버리고 **조용히 재컴파일·재실행**한다(vdb:2277~2296) → 경계 위반이 재컴파일로 숨는다. 새 코드는 재컴파일 트리거 목록에 넣지 않는다. 오류 메시지는 XASL id·regu 위치·도메인을 싣는다(qp_xasl_line 활용).
- **경계 위치**(G-07(b)): `qdata_get_valptr_type_list`(리스트 컬럼), `fetch_peek_dbval_slow` 의 VARIABLE 분기 자리, `btree_compare_key` 폴백 자리, `eval_value_rel_cmp` coercion 자리, 집계 첫값 대기 자리, `scan_dbvals_to_midxkey` 전략 재추론 자리. 이 경계들의 "도달 0" 이 마이크로벤치 카운터(#316 §4, #324)와 짝이다.

### 결정 4 — 클라이언트
- **바인드 값은 그대로 보낸다**: `pt_set_host_variables` 의 `tp_value_cast_preserve_domain` 분기 삭제(복제만; 참조 OID 검사는 유지). CHAR 도메인의 VARCHAR 값 유지(pd:3128)는 게이트의 B7 규칙으로 옮긴다. `host_var_expected_domains[]` 는 남는다 — prepare 응답의 파라미터 메타·PL/CSQL 보고(mc:650~670, S6)·바인드 피크 재계획의 입력이다. 사용자 `?` 배열 vs auto-param 카운트 불변식은 assert 로 고정(L-30).
- **플랜은 값에 종속되지 않는다**: `pt_make_regu_hostvar` 2단계(값 타입으로 도메인, xg:6418~6445) **삭제**. 바인드 피크 재계획(vdb:3496)은 값을 **비용 추정에만** 쓰고 도메인은 1·3·4 단계(형제 미러·expected_domain)로만 정한다 → 같은 sha1 캐시 항목이 어떤 바인드 타입에서도 같은 슬롯 도메인을 가진다(L-49 의 전제 회복). `hostvar_late_binding=yes` 의 값 치환 재컴파일(nr:3790) 은 파라미터 deprecated 처리(#320)와 함께 클라이언트에서 제거.
- **결과 컬럼 메타데이터**: 컴파일 도메인이 prepare 응답에 실린다(현행 경로). 게이트 확정 슬롯이 결과 컬럼인 문장(`SELECT ?`, `SELECT ? UNION SELECT ?`, `SELECT sum(?)`)은 현행처럼 실행 응답의 `include_column_info` 로 갱신(L-31 재사용) — 이것이 "게이트 잔여" 의 전부이며 L-24 의 미실행 문장 메타는 후속(D-317-15) 그대로.
- **기각**: 클라이언트가 게이트 규칙을 흉내 내 값을 미리 변환하는 이중 변환(D-M4 위반, L-30 사고 재현).

### 결정 5 — 인덱스 키 변환
- **계획 표기**: 키 range 원소마다 로드 도출이 (인덱스 컬럼 도메인 ← `INDX_INFO.key_type`, 키 regu 부류 K/S, 변환기) 를 고정한다. **K 키**(바인드·auto-param·상수식): G1 이 strict-or-keep 을 1회 적용 — strict 성공이면 인덱스 도메인 값, 실패면 값 도메인 + 비교 변환기(B30·B31; midxkey `setdomain` 도 이때 1회 조립 → `need_new_setdomain`/`prebuilt_midxkey_domains` 삭제). **S 키**(상관·조인·skip-scan): range open 마다 같은 변환기를 값에만 적용(전략 재추론 0). key1/key2 는 계획 항목을 분리(L-45(c)); ISS 내림차순 bound 이동은 fetch 범위용 계획 쌍(L-45(d)); ISS 첫 컬럼·MRO 정렬 컬럼 도메인은 `key_type` 오름차순 사본(L-44·L-45(e)); `prebuilt_midxkey_domains` 해제 누수(L-45(g))는 필드 자체가 사라져 해소.
- **기각**: 카탈로그에서 로드 시 `key_type` 재계산(unpack 중 페이지 접근) — `INDX_INFO` 에 싣는다.

---

## 1.4 선택 (D-318-nn 코멘트가 잠근 뒤 채움)

2026-09-22 #318 "결정 기록 1라운드" — 사용자가 권고 전부를 채택("모두 추천대로"). 바뀐 항목 없음.

| # | 결정 | 근거·기각 |
|---|---|---|
| D-318-01 | **전략 A** 채택(§1.2). B·C 기각, D 는 Out of scope | 자리는 있고 값만 없다(M1) · 노드 레이아웃은 디스크 포맷(M3) · 도출은 순수 함수(M2·M8) · 상태의 집은 XASL_STATE(M5) |
| D-318-02 | 로드 도출 패스는 `stx_map_stream_to_xasl` 안(언팩 직후, 세 호출자 공통). 필터/함수 인덱스 로드는 GATE 플래그 있으면 거부 | 호출자가 잊을 수 없음, 클론 풀 재사용 시 재도출 0 |
| D-318-03 | 게이트 산출 값은 XASL_STATE 소유 별도 배열, 입력 `dbval_ptr` 는 const 유지, 해제 = 만든 스레드가 실행 종료 시 | SA_MODE 별칭(M4), 결과 캐시·tdes 사본은 원 값 기준 |
| D-318-04 | 경계 (b) 의 release 오류 코드는 **신설**(이름은 #323), 재컴파일 트리거에 넣지 않음. `ER_QPROC_INVALID_XASLNODE` 재사용 기각 | vdb:2277 의 조용한 재컴파일이 위반을 숨김 |
| D-318-05 | `pt_make_regu_hostvar` 2단계(값 타입 도메인) 삭제, 바인드 피크 재계획은 값을 비용 추정에만 | 클라이언트 세 번째 결정 지점 제거(M7, D-M3) |
| D-318-06 | PX 상속은 `qexec_deep_copy_xasl_state` 하나(pxt:648 경로 대체) | 상속 seam 둘 → 한쪽만 복사하는 사고(L-46 부류) |
| D-318-07 | G 행 그리드 = 서버 전용 모듈 하나("도메인 해석기", `query/`), 로드 도출(R 변환기)과 G1(G 도메인)이 공용. `object/` 공유 기각 | 두 그리드(파서 C / 서버 G)는 현행대로 유지하되 각 한 벌(P0·P6), PHYS-05 |
| D-318-08 | G2 = `qexec_execute_mainblock_internal` precompute 뒤·`qexec_start_mainblock_iterations` 직전, 결정 0·변환기 적용만; 상관·조인 키는 range open | D-317-18 해석 확정 |
| D-318-09 | HTML 보고서는 §1.1 seam 표로 갈음; 필요 시 사용자가 스킬 직접 실행 후 차이만 코멘트 | 스킬 모델 호출 금지 |
| D-318-10 | CONTEXT.md 용어 추가: 로드 도출 · 게이트 표 · 실행 게이트/블록 게이트(G1/G2) | "결정 vs 도출" 이 전략의 핵심 어휘 |

짝 티켓으로 넘긴 것(이 티켓 수락 기준 밖, L-08): `val_pos` 다중 참조 regu 의 바인드 도메인 불일치 탐침·경계 예외 표·오류 코드 이름·`SHOW PLAN` 로드 도출 출력 → #323; GATE 노드의 placeholder 도메인 값·변환기 표·슬롯 ID 부여 순서·게이트 의존 노드 목록 형태 → #325; 구현 축 §1.7 의 순서·커밋 단위 → #320.

---

## 1.5 삭제 목록 초안 — 전략 A 에서 각 지점이 사라지는 축

축: **CP** = 컴파일이 도메인을 채워 지점이 도달 불가 · **LD** = 로드 도출이 대체 · **G1/G2** = 게이트가 대체 · **KEEP** = 유지·결정적화(경계 assert 자리) · **X** = 실행 결정 잔존(F10).

| 축 | 지점 | 비고 |
|---|---|---|
| CP | S-03 S-11 S-13 S-14(씨앗) S-15 S-16 S-17 S-18 S-19 S-20 S-21 S-22 S-24 S-25 S-29 S-37 | 도메인 필드가 확정이면 조건 자체가 거짓 → 코드 삭제 + 경계 (b) |
| CP+G1 | S-01 S-02 S-04 S-05 S-06 S-23 S-26 S-27 S-28 S-36 | 정적이면 CP, GATE 피연산자면 G1 이 게이트 표에 채움(첫값 대기·시도 캐스트 삭제) |
| G1 | S-07(세션변수 읽기 = 슬롯, S4·S5) S-09(상수 제자리 coerce → 계획 슬롯 캐시) S-10(같은 타입 → coercion 0) S-39(힙 전환) S-40(TO_CHAR 포맷 값, F1·F2) S-41(PL 인자 선언 타입, S6) | |
| LD | S-38(`original_domain` 원복 5곳 + sx 6곳 + sp 3곳 — 필드 자체 제거) S-33(계획 도메인 신뢰 소비자 — 불변식으로 보호) M8 의 `FETCH_ALL_CONST`/`FAST_PEEK`/`AGG_OPERAND` 재도출·클리어 | 플랜 불변(G-02) |
| G1+G2 | S-12 S-30 S-31 S-32(키: K 는 G1, S 는 G2/range open) S-34 S-35(PX 상속) | |
| KEEP | S-08(`qdata_*_dbval` 값 타입 dispatch — 게이트 뒤 결정적) S-10/S-12 의 함수 자체 | 경계 assert 위치 |
| 경계 | S-42(필터/함수 인덱스 로드 거부 + 오류 삼킴 수정) S-43(파라미터, #320) | |
| X | F10 `median(varchar_col)`·`percentile_cont … order by varchar_col` | 삭제 대상 아님(D-317-15) |
| collation | #314 §4 26곳: 쌍 조건의 두 축이 함께 사라진다(LEAVE 0, D-322-01) — `qfile_unify_types` -1509 분기·`qexec_end_one_iteration` 플래그 분기 포함 | §6 귀결 (2) |

---

## 1.6 이 PR 에서 고칠 develop 결함(#318 입력 6)이 사라지는 자리

| 결함 | 축 | 왜 사라지나 |
|---|---|---|
| `coalesce(enum_col, ?)` collation 래핑 assert(tc:22826, D1) | — | **후속 #326**(D-322-04). 이 PR 은 건드리지 않음 |
| `group_concat(?)` NULL LEAVE 플래그 assert(qx:1375, D2) | CP+G1 | 누산기 도메인이 게이트 표에서 확정, LEAVE 소멸(C10) |
| `group_concat(s + ?)` 리스트 기록/판독 불일치 assert(op:10996, D3) | CP | `s + ?` 는 VARCHAR 미러(C11) → 리스트 컬럼 도메인 = 값 타입 불변식 |
| `sum(?) over` 날짜 assert(qx:23654, D4) | G1 | 분석 누산기 도메인을 게이트가 값 타입으로 확정(F7), 첫값 블록 삭제 |
| `to_char(col, ?)` BIGINT assert(string_opfunc.c:25792, D5) | G1 | 포맷 슬롯이 게이트 확정(F2) → 오류로 |
| `? UNION ALL ?`·재귀 CTE NULL·NULL assert(lf:913, D6) | G1 | 리스트 컬럼 도메인이 게이트 표(U3: NULL·NULL 은 VARCHAR NULL), `qfile_unify_types` VARIABLE 분기 삭제 |
| `enum IN (NULL, NULL)` assert(dbtype_function.i:678, D7) | CP | B13 컬렉션 원소 미러 → NULL 원소도 ENUM 도메인 typed NULL |
| `INSERT int_col ← ?` DATE 0행 | G1 | U0 대입 캐스트가 게이트에서 -494 |
| `char(n)_col = ?` VARCHAR 값 NULL | CP+G1 | B7: 슬롯 VARCHAR 미러 + 게이트 문자화, 클라이언트 캐스트 삭제 |
| `enum_col < ?` TIME 2행 | G1 | B14: 게이트 ENUM 변환 표 → 범위 밖 -494(값 A/B 뒤) |

---

## 1.7 구현 축(#320 분할 입력; 순서·커밋 단위는 #320)

1. **계측**(#324, 구현보다 먼저): 카운터 8종(#316 §4, D-317-20 재정의).
2. **로드 도출 + 경계 (a)**: 슬롯 ID·부류·변환기 표·게이트 의존 목록·`original_domain` 제거·`FETCH_ALL_CONST` 계열 로드 시 도출. `INDX_INFO.key_type`. 이 단계까지는 컴파일이 VARIABLE 을 내보내도 동작(GATE 플래그 없는 VARIABLE 은 아직 허용 → 경계 (a) 는 마지막에 켠다).
3. **G1 게이트 + XASL_STATE 확장 + PX 상속 단일화**: 값 배열 소유·게이트 표·`qexec_deep_copy_xasl_state` 통합.
4. **컴파일 확정(타입 축)**: 규칙표 §2~§4 C 행 → `pt_make_regu_hostvar` 2단계 삭제, 늦은 바인딩 연산자 목록(`pt_is_op_hv_late_bind`) 비우기, 파생 소비자 도메인, GATE 플래그. 클라이언트 캐스트 삭제.
5. **컴파일 확정(collation 축)**: §6 C1~C18 — LEAVE 제거, 형제 ENFORCE 직접 인자, 중첩 계획 CAST.
6. **G2 + 키 변환 계획**: S 부류·키 K/S·ISS/MRO 시딩.
7. **실행 하위 삭제 + 경계 (b) + 경계 (a) 켜기**: §1.5 표 순서로, 게이트 CTP 마다.
8. **마무리**: 파라미터 deprecated, 매뉴얼/릴리스 노트, TC PR, 정적 감사표.

---

## 1.8 렛저 대응표(L-08, L-40~L-49)와 cpp-perf-rules 인용

| L / 규칙 | 이 문서에서 |
|---|---|
| L-08 수락 기준 고정 | 이 티켓의 산출 = §1 전략·결정 1~5 방향·삭제 초안·구현 축. 자료구조·시그니처·경계 예외 표·`val_pos` 다중 참조 탐침은 #323, 변환기 표는 #325 — 여기서 올리지 않는다 |
| L-40 pack/unpack·세 로드 경로 | M2·M3, 결정 1(레이아웃 불변·로드 도출), 경계 (a) 필터/함수 인덱스 |
| L-41 파생 소비자 | 결정 1(게이트 의존 노드 목록·생산자 우선), 결정 2 G1 ③, CP 축 |
| L-42 `original_domain` 원복 | LD 축, 결정 1 비팩 필드 재사용, G-02 |
| L-43 누산기·분석 첫값 | CP+G1 축 S-23·S-27·S-28·S-36, D2·D4 |
| L-44 MRO 시딩 | 결정 5(`key_type` 오름차순 사본) |
| L-45 키 7항목 | 결정 5 전체 |
| L-46 워커·교차 mspace free | M6, 결정 2 소유·상속(ALLOC-08/A64), S-39 |
| L-47 collation 축 | §1.5 collation 행, 결정 1(LEAVE 0) |
| L-48 경계 예외·오류 삼킴 | 결정 3 |
| L-49 플랜 도메인 신뢰 소비자 | M7(바인드 피크 재계획의 값 타입 도메인 삭제), 결정 4, S-33 KEEP |
| BR-04 / A59 / A62 | M8: 불변 도출(`FETCH_ALL_CONST`·FAST_PEEK·도메인 원복)을 실행 루프에서 로드 시 1회로 — 결정 1 |
| BR-06 / A61 | P4: 비교·산술의 (타입×연산자) 변환기를 로드에 고정, 행 경로의 다단 switch 제거 — #325 |
| ALLOC-08 / A64 | 결정 2: 게이트 값·게이트 표의 소유 스레드 = 만든 스레드, 워커는 자기 사본 |
| MEM-02 | 결정 1: `original_domain` 자리 재사용으로 regu/arith/agg 구조체 크기 불변 |
| PHYS-05 | 변환기 표·게이트 그리드는 서버 전용 모듈에 두고 클라이언트 헤더로 새지 않게(#323 seam) |
