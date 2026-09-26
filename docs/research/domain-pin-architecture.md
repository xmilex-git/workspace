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
- **스트림 포맷·플랜 캐시·클론 호환**: 스트림 코덱 변경은 `INDX_INFO` 1곳 + `flags` 비트 → 클라이언트·서버 lockstep 은 현행 요구 그대로(같은 빌드), 디스크 호환 유지. 플랜 캐시 키·클론 풀 변경 없음. 로드 도출은 xcache 클론당 1회(클론 풀 재사용 시 재도출 0), PX 워커 unpack 당 1회. **기록(F-335-04, #335)**: 플랜 캐시 키(해시 텍스트 SHA-1)는 auto-param 과 사용자 `?` 를 구분하지 않아 리터럴 문장과 바인드 문장이 계획 하나를 쓴다 — 계획에 형태별 결정(캐스트·미러 도메인)을 실으면 컴파일 순서로 답이 갈린다. #335 는 캐스트를 클라이언트에 두어(D-335-08) 키를 바꾸지 않았고, 미러 도메인이 형태별로 다른 dpin-10 이 이 전제를 다시 다룬다.
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
- **플랜은 값에 종속되지 않는다**: `pt_make_regu_hostvar` 2단계(값 타입으로 도메인, xg:6418~6445) **삭제**. 바인드 피크 재계획(vdb:3496)은 값을 **비용 추정에만** 쓰고 도메인은 1·3·4 단계(형제 미러·expected_domain)로만 정한다 → 같은 sha1 캐시 항목이 어떤 바인드 타입에서도 같은 슬롯 도메인을 가진다(L-49 의 전제 회복). `hostvar_late_binding=yes` 의 값 치환 재컴파일(nr:3790) 은 파라미터 deprecated 처리(#320)와 함께 클라이언트에서 제거. **기록(F-335-04)**: 사용자 호스트 변수에 대해서는 성립하지만 auto-param 은 리터럴 도메인(B33)을 가져 같은 sha1 의 리터럴 문장과 바인드 문장은 슬롯 도메인이 다를 수 있다.
- **결과 컬럼 메타데이터**: 컴파일 도메인이 prepare 응답에 실린다(현행 경로). 게이트 확정 슬롯이 결과 컬럼인 문장(`SELECT ?`, `SELECT ? UNION SELECT ?`, `SELECT sum(?)`)은 현행처럼 실행 응답의 `include_column_info` 로 갱신(L-31 재사용) — 이것이 "게이트 잔여" 의 전부이며 L-24 의 미실행 문장 메타는 후속(D-317-15) 그대로.
- **기각**: 클라이언트가 게이트 규칙을 흉내 내 값을 미리 변환하는 이중 변환(D-M4 위반, L-30 사고 재현).

### 결정 5 — 인덱스 키 변환
- **계획 표기**: 키 range 원소마다 로드 도출이 (인덱스 컬럼 도메인 ← `INDX_INFO.key_type`, 키 regu 부류 K/S, 변환기) 를 고정한다. **K 키**(바인드·auto-param·상수식): G1 이 strict-or-keep 을 1회 적용 — strict 성공이면 인덱스 도메인 값, 실패면 값 도메인 + 비교 변환기(B30·B31; midxkey `setdomain` 도 이때 1회 조립 → `need_new_setdomain`/`prebuilt_midxkey_domains` 삭제). **S 키**(상관·조인·skip-scan): range open 마다 같은 변환기를 값에만 적용(전략 재추론 0). key1/key2 는 계획 항목을 분리(L-45(c)); ISS 내림차순 bound 이동은 fetch 범위용 계획 쌍(L-45(d)); ISS 첫 컬럼·MRO 정렬 컬럼 도메인은 `key_type` 오름차순 사본(L-44·L-45(e)); `prebuilt_midxkey_domains` 해제 누수(L-45(g))는 필드 자체가 사라져 해소. 구현(#342): 단일 컬럼 키는 값 그대로이고 비교가 키 비교 표를 읽는다(F-342-01) — 인터페이스 §5 #342 상태.
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

축: **CP** = 컴파일이 도메인을 채워 지점이 도달 불가 · **LD** = 로드 도출이 대체 · **G1/G2** = 게이트가 대체 · **KEEP** = 유지·결정적화(경계 assert 자리) · **X** = 실행 결정 잔존 — D-335-10(2026-09-24) 뒤 없음(F10 은 CP).

| 축 | 지점 | 비고 |
|---|---|---|
| CP | S-03 S-11 S-13 S-14(씨앗) S-15 S-16 S-17 S-18 S-19 S-20 S-21 S-22 S-24 S-25 S-29 S-37 | 도메인 필드가 확정이면 조건 자체가 거짓 → 코드 삭제 + 경계 (b) |
| CP+G1 | S-01 S-02 S-04 S-05 S-06 S-23 S-26 S-27 S-28 S-36 | 정적이면 CP, GATE 피연산자면 G1 이 게이트 표에 채움(첫값 대기·시도 캐스트 삭제) |
| G1 | S-07(세션변수 읽기 = 슬롯, S4·S5) S-09(상수 제자리 coerce → 계획 슬롯 캐시) S-10(같은 타입 → coercion 0) S-39(힙 전환) S-40(TO_CHAR 포맷 값, F1·F2) S-41(PL 인자 선언 타입, S6) | |
| LD | S-38(`original_domain` 원복 5곳 + sx 6곳 + sp 3곳 — 필드 자체 제거) S-33(계획 도메인 신뢰 소비자 — 불변식으로 보호) M8 의 `FETCH_ALL_CONST`/`FAST_PEEK`/`AGG_OPERAND` 재도출·클리어 | 플랜 불변(G-02) |
| G1+G2 | S-12 S-30 S-31 S-32(키: K 는 G1, S 는 G2/range open) S-34 S-35(PX 상속) | |
| KEEP | S-08(`qdata_*_dbval` 값 타입 dispatch — 게이트 뒤 결정적) S-10/S-12 의 함수 자체 | 경계 assert 위치 |
| 경계 | S-42(필터/함수 인덱스 로드 거부 + 오류 삼킴 수정) S-43(파라미터, #320) | |
| X | ~~F10~~ | D-335-10: F10 은 CP(컴파일 DOUBLE) — 잔존 X 없음 |
| collation | #314 §4 26곳: 쌍 조건의 두 축이 함께 사라진다(LEAVE 0, D-322-01) — `qfile_unify_types` -1509 분기·`qexec_end_one_iteration` 플래그 분기 포함 | §6 귀결 (2) |

---

## 1.6 이 PR 에서 고칠 develop 결함(#318 입력 6)이 사라지는 자리

| 결함 | 축 | 왜 사라지나 |
|---|---|---|
| `coalesce(enum_col, ?)` collation 래핑 assert(tc:22826, D1) | — | **후속 #326**(D-322-04). 이 PR 은 건드리지 않음 |
| `group_concat(?)` NULL LEAVE 플래그 assert(qx:1375, D2) | CP+G1 | 누산기 도메인이 게이트 표에서 확정, LEAVE 소멸(C10) — **소멸 확인(#340 A/B)**: develop optdebug 만 멈춘다 |
| `group_concat(s + ?)` 리스트 기록/판독 불일치 assert(op:10996, D3) | CP | `s + ?` 는 VARCHAR 미러(C11) → 리스트 컬럼 도메인 = 값 타입 불변식 — **소멸 확인(#340)**: dpin optdebug 는 `'ax,bx'` 와 develop 의 변환 오류 |
| `sum(?) over` 날짜 assert(qx:23654, D4) | G1 | 분석 누산기 도메인을 게이트가 값 타입으로 확정(F7), 첫값 블록 삭제 — **소멸 확인(#341 A/B)**: develop optdebug(a0c1b6c)는 `qexec_analytic_add_tuple` 에서 멈추고, dpin 은 변환 오류(-181, #337 의 D4 수정)를 낸다. `count(distinct ?) over (…)` 의 문자 바인드도 같은 부류다(develop 은 COUNT 의 BIGINT 로 피연산자를 변환하다 오류 코드 없이 실패) |
| `to_char(col, ?)` BIGINT assert(string_opfunc.c:25792, D5) | G1 | 포맷 슬롯이 게이트 확정(F2) → 오류로 — **남는다(#358)**: F2 포맷 미러가 D-336-B 로 철회됐고 자리는 `date_to_char` 의 포맷 타입 검사다. develop·dpin 이 같은 백트레이스로 멈추고 release 는 서버 SIGSEGV(리터럴 포맷은 -783) → 캠페인 밖 [#363](https://github.com/xmilex-git/workspace/issues/363) |
| `? UNION ALL ?`·재귀 CTE NULL·NULL assert(lf:913, D6) | G1 | 리스트 컬럼 도메인이 게이트 표(U3: NULL·NULL 은 VARCHAR NULL), `qfile_unify_types` VARIABLE 분기 삭제 — **소멸 확인(#341 A/B)**: develop optdebug 는 `qfile_unify_types` 에서 멈추고, dpin 은 답한다(빈 쪽은 값을 주지 않는다, S-15) |
| `enum IN (NULL, NULL)` assert(dbtype_function.i:678, D7) | CP | B13 컬렉션 원소 미러 → NULL 원소도 ENUM 도메인 typed NULL — **남는다(#340)**: 미러가 D-336-B 로 철회됐고 자리는 파서 상수 접기다. develop·dpin 이 같은 백트레이스로 멈추는 develop 결함 → 캠페인 밖 [#353](https://github.com/xmilex-git/workspace/issues/353) |
| `INSERT int_col ← ?` DATE 0행 | G1 | U0 대입 캐스트가 게이트에서 -494 — **결함 아님(#358)**: develop 도 클라이언트 캐스트가 -494 로 멈춘다(csql·JDBC). 0행은 #317 탐침 파서가 EXECUTE 오류를 놓친 측정 오류 |
| `char(n)_col = ?` VARCHAR 값 NULL | CP+G1 | B7: 슬롯 VARCHAR 미러 + 게이트 문자화, 클라이언트 캐스트 삭제 |
| `enum_col < ?` TIME 2행 | G1 | B14: 게이트 ENUM 변환 표 → 범위 밖 -494(값 A/B 뒤) — **슬롯 결함 아님(#358)**: 리터럴 `enum_col < time'…'` 과 같은 답(ENUM 라벨을 TIME 으로 바꿔 견준다) → 후속 [#360](https://github.com/xmilex-git/workspace/issues/360) |
| `coalesce(cast(? as datetime), cast(? as datetime), ?)` 결과 도메인의 collation 플래그(L-19, 규칙표 C15·U13) | — | **develop 에 없음(#358)**: 이전 캠페인 변경의 산물이었다. 같은 문장에서 dpin 의 G1 공통값 결정이 NULL 인 상수 피연산자를 계획 도메인으로 읽어 develop 과 다르다 → [dpin-17g #364](https://github.com/xmilex-git/workspace/issues/364) |

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

---

# §2 인터페이스 (티켓 #323, design-it-twice — 작성 2026-09-22)

§1 이 잠근 전략 A 안에서 **자료구조·시그니처·호출 순서**를 정한다. 두 안 이상을 병렬로 만들어 비교하고 하나를 고른 뒤(§2.2~§2.4), 그 안의 시그니처·호출 순서·삭제 목록을 정본으로 둔다(§2.5~). 결정 기록은 #323 코멘트 "결정 기록"(D-323-nn); §2.4 "선택" 은 그 코멘트가 잠근 뒤에만 정본이다. 변환기 표의 **내용**(타입 쌍 → 함수)과 슬롯 placeholder 도메인 값은 #325.

## 2.0 문제 틀 — 어떤 인터페이스든 만족해야 하는 제약과 소스 사실

### 2.0.1 제약(잠긴 결정에서 따라오는 것)

| # | 제약 | 출처 |
|---|---|---|
| K1 | regu/arith/pred/domain 스트림 **레이아웃 불변**(디스크 포맷). 새 스트림 항목은 `INDX_INFO.key_type` 하나, `regu->flags` 미사용 비트 1개 | D-318-01, M3 |
| K2 | 슬롯 ID·부류 K/R/S·변환기·게이트 의존 노드 목록은 **로드 도출**(`stx_map_stream_to_xasl` 안 1회, 세 호출자 공통), 저장은 `original_domain`/`original_opr_dbtype` 자리(구조체 크기 불변, MEM-02) | D-318-02, 결정 1 |
| K3 | 결정 지점 = 컴파일 + **G1**(`qexec_execute_query` vd 형성 직후, 실행당 1회). **G2**(블록당, precompute 뒤·iterations 전)는 변환기 적용만. 상관·조인 키는 range open 에서 값 변환만 | D-318-08, D-317-18 |
| K4 | 게이트 산출 값은 **XASL_STATE 소유 별도 배열**, 입력 `dbval_ptr` 는 const, 해제 = 만든 스레드가 실행 종료 시. PX 상속은 `qexec_deep_copy_xasl_state` 하나 | D-318-03·06 |
| K5 | 경계 (b) 오류 코드 **신설**, 재컴파일 트리거 목록에 넣지 않음. 경계 (a) 는 GATE 플래그 없는 VARIABLE/LEAVE 거부 + 예외 표 | D-318-04, 결정 3 |
| K6 | 클라이언트 캐스트 삭제, `pt_make_regu_hostvar` 2단계 삭제, `host_var_expected_domains[]` 유지(메타·PL·바인드 피크) | D-318-05, 결정 4, D-M4 |
| K7 | 게이트 표 항목 = (도메인, collation) 한 쌍 + 변환기 + **실패 정책**(-494 / NULL / keep) | D-322 귀결 (1), D-327-10 |
| K8 | 게이트 의존 노드는 미러하지 않고 G1 이 **생산자 우선**(안쪽→바깥, aptr→mainblock) 1회 순회 | D-327-08 |
| K9 | 한 `?` 의 다중 참조는 **참조별 K 변환기 + 참조별 값 자리**, 공유 원 값 불변 | 결정 1, D-327-10, §2.0.2 F-323-08 |
| K10 | 행 루프 안 미확정 검사·재추론 0(BR-04·A59·A62), 게이트 실행당 1회, 정적 계획은 G1 순회 0 | cpp-perf-rules, #318 입력 3 |
| K11 | G 행 그리드 = `query/` 전용 도메인 해석기, 클라이언트 헤더로 새지 않음(PHYS-05) | D-318-07 |

### 2.0.2 소스 사실(리드가 dpin `cad27172b` 에서 확인; 설계 입력)

| # | 사실 | 위치 |
|---|---|---|
| F-323-01 | `REGU_VARIABLE` = {type, flags, domain, **original_domain**, vfetch_to, xasl, value(union)}; 플래그는 0x01~0x2000 까지 사용(FETCH_ALL_CONST 0x40·FETCH_NOT_CONST 0x80·CLEAR_AT_CLONE_DECACHE 0x100·FAST_PEEK 0x1000·AGG_OPERAND 0x2000). 언팩은 `original_domain = domain` 만 하고 FETCH_* 플래그는 스트림에 없음을 assert | `src/query/regu_var.hpp:129~200`, sx:5613~5622 |
| F-323-02 | `ARITH_TYPE` = {domain, **original_domain**, value, left/right/third, opcode, misc_operand, pred, rand_seed(서버 전용)}; `AGGREGATE_TYPE` = {…, domain, **original_domain**, function, option, opr_dbtype, **original_opr_dbtype**, operands, list_id, btid, sort_list, info, accumulator, accumulator_domain(서버 전용) …}; `ANALYTIC_TYPE` 같은 두 쌍; `QFILE_TUPLE_VALUE_POSITION` = {dom, **original_domain**, pos_no} | regu_var.hpp:128, xasl_aggregate.hpp:85~92, xasl_analytic.hpp:73~77, query_list.h:321~324 |
| F-323-03 | `XASL_STATE` = {`VAL_DESCR vd`, query_id, qp_xasl_line}; `qexec_execute_query` 는 `xasl_state.vd.dbval_ptr = (DB_VALUE *) dbval_ptr`(const 캐스트) 뒤 `qexec_execute_mainblock` 호출. `qexec_deep_copy_xasl_state`(qx:3678) 는 vd 를 복사하고 `dbval_ptr[]` 을 `pr_clone_value`; `qexec_free_xasl_state` 가 짝. **PX 워커 unpack 경로(pxt:648~672)는 같은 복사를 `memcpy(m_vd, m_orig_vd)` + clone 루프로 따로 구현** — 상속 seam 둘 | query_executor.h:74~93, qx:17578~17585, qx:3678~3735, px_scan_task.cpp:648 |
| F-323-04 | 로드 경로 3: xcache 클론 `xcache_find_xasl_id_for_execute`(xasl_cache.c:1133) · 비캐시 `qmgr_process_query`(query_manager.c:1219) · PX 워커 자체 unpack(px_scan_task.cpp:623). 세 곳 모두 `stx_map_stream_to_xasl (thread_p, &tree, use_clone, stream, size, &unpack_info)`. 언팩 노드는 `stx_alloc_struct` 로 **unpack arena**(`XASL_UNPACK_INFO.alloc_buf` + `additional_buffers` 체인)에서 할당되고 `free_xasl_unpack_info` 가 트리와 함께 해제 → 로드 도출 배열도 같은 arena 에 두면 수명이 트리와 같다. `XASL_CLONE` = {xasl_buf(unpack info), xasl} | stream_to_xasl.c:212, xasl_unpack_info.hpp:49~70, xasl_unpack_info.cpp:69~102, xasl_cache.h:63 |
| F-323-05 | `INDX_INFO` 스트림 순서: btid, coverage, range_type, key_info(key_cnt, key_ranges[], key_vals[], is_constant, key_limit_reset, is_user_given_keylimit, key_limit_l, key_limit_u), orderby_desc, groupby_desc, use_desc_index, orderby_skip, groupby_skip, use_iss, ils_prefix_len, func_idx_col_id, cov_list_id, iss_range(range, key1; key2 는 항상 NULL). `KEY_RANGE` = {key1, key2, range}. access-spec 레이아웃은 디스크에 없음 | access_spec.hpp:56~104, xasl_to_stream.c:4760~4830, stream_to_xasl.c:4784~4900 |
| F-323-06 | 키 변환 현행: `scan_dbvals_to_midxkey (…, btree_domainp, num_term, func, vd, key_minmax, is_iss, prebuilt_midxkey_domain)` 가 원소마다 `tp_value_coerce_strict` → 실패·NUMERIC/CHAR/BIT 비정확 일치면 `need_new_setdomain` → 값 도메인 setdomain 을 `INDX_SCAN_ID.prebuilt_midxkey_domains[range]` 에 캐시(range 마다 재판정). ISS 는 `isidp->bt_scan.btid_int.key_type->setdomain` 을 읽어 `skipped_range->key1` 의 `TYPE_DBVAL` 피연산자를 last_key 로 갱신. `parallel_index_scan_id` 도 같은 `prebuilt_midxkey_domains` 필드를 미러 | scan_manager.c:405~470, 1871~2150, 3745~3755, 5418~5425; scan_manager.h:291·345 |
| F-323-07 | 재컴파일 트리거: 클라이언트 `db_vdb.c:2277`(`ER_QPROC_XASLNODE_RECOMPILE_REQUESTED`·`ER_QPROC_INVALID_XASLNODE`·`ER_QPROC_RESULT_CACHE_INVALID` 면 xasl_id 버리고 `do_prepare_statement` 재시도), `db_vdb.c:1102·2174·2218·2314·2390·2537`, `cas_execute.c:1188·1502·2376`(pooled 핸들 재준비·재시도), `cas_common_execute.c:364`, `method_callback.cpp:276`, `trigger_manager.c:4971`. 오류 코드 꼬리 `ER_LAST_ERROR = -1381`(`-1380 ER_SP_PARALLEL_ENABLE_NO_SQL`), 메시지는 `msg/*/cubrid.msg` `$set 5` 의 `1381 Last Error` 앞 | error_code.h:1778~1780 |
| F-323-08 | **`val_pos` 다중 참조가 실제로 생기는 재작성 2곳**: (R1) `qo_reduce_equality_terms` — `qo_is_reduceable_const` 가 `PT_IS_CONST_INPUT_HOSTVAR` 를 참으로 보고, `attr = ?` 를 찾으면 같은 `?`(인덱스 동일)를 `parser_copy_tree`/`pt_lambda_with_arg` 로 다른 항의 `attr` 자리에 대입한다 → `t1.i = ? AND t1.i = t2.b` 가 `t2.b = ?` 를 얻어 같은 `val_pos` 가 INTEGER 형제와 BIGINT 형제를 동시에 가진다(파라미터화 타입 형제면 복사본을 `pt_wrap_with_cast_op` 로 감싼다). (R2) `pt_copypush_terms` — 파생 테이블이 UNION 이면 같은 term_list 복사를 `arg1`·`arg2` 양 가지에 푸시(view_transform.c:4505~4506) → 가지 컬럼 타입이 다르면 참조별 미러가 갈린다. `expected_domain` 은 노드마다이고 `host_var_expected_domains[idx]` 는 마지막 `pt_preset_hostvar` 가 이긴다(tc:8617) | query_rewrite_term.c:418~433, 585~640, 830~900; view_transform.c:4386~4506; type_checking.c:8617 |
| F-323-09 | `host_var_expected_domains[]` 소비자: `pt_set_host_variables`(pd:3110, 캐스트 — 삭제 대상), `db_vdb.c:2954`(prepare_info 로 pack → `db_query.c:461·546·639` 와이어), `db_vdb.c:3209`(바인드 피크), `db_vdb.c:3311~3449`(EXECUTE PREPARE 부모 파서 공유), `method_callback.cpp:657`(PL 보고 `semantics.hvs[idx].type/precision/scale/charset`), `semantic_check.c:13412`(SET 대입 lhs 도메인 결정), `name_resolution.c:11901~11908`(배열 성장, 초기 `PT_TYPE_NONE`), `type_checking.c:8617`(쓰기). auto-param 은 `idx >= host_var_count` 이면 `marker->expected_domain` 직접 | 위치 열 |
| F-323-10 | `pt_set_host_variables`: `host_var_count > count` 면 경고 후 return; 각 값에 `pt_is_reference_to_reusable_oid` 검사 → `hv_dom` 이 UNKNOWN/ENUM 이면 `pr_clone_value`, 아니면 `tp_value_cast_preserve_domain`(반올림) + CHAR 도메인의 VARCHAR 값은 원 값 유지(pd:3128). `pt_make_regu_hostvar` 4단계: data_type → **바인드 값 타입**(`set_host_var==1 || typ != NULL`) → expected_domain → type_enum; 값이 없으면 `db_value_domain_init` 으로 프리셋, 있으면 `tp_value_cast` | parse_dbi.c:3072~3140, xasl_generation.c:6391~6510 |
| F-323-11 | 실행 응답 컬럼 메타: `cas_execute.c` 세 곳(1292·1637·1834)이 `include_column_info` 바이트 뒤 `prepare_column_list_info_set`(6811) 로 컬럼 정보를 다시 보낸다(L-31 경로 현존) | cas_execute.c |
| F-323-12 | 늦은 바인딩 연산자 목록 `pt_is_op_hv_late_bind`: ABS·CEIL·FLOOR·PLUS·DIVIDE·MODULUS·TIMES·MINUS·ROUND·TRUNC·UNARY_MINUS·EVALUATE/DEFINE_VARIABLE·ADDTIME·TO_CHAR·HEX·CONV·ASCII·IFNULL·NVL·NVL2·COALESCE·NULLIF·LEAST·GREATEST·FROM_TZ·NEW_TIME·STR_TO_DATE·HOURF·MINUTEF·SECONDF·BIT/OCTET_LENGTH·TO_DATE/DATETIME(_TZ)/TIME/TIMESTAMP(_TZ). `hostvar_late_binding` 소비자 3: `query_rewrite.c:501`·`name_resolution.c:3805`·`type_checking.c:19714`(전부 클라이언트) | type_checking.c:20528~20573 |
| F-323-13 | G2 자리: `qexec_execute_mainblock_internal` 은 aptr 실행(qx:16538~) → 비상관 스칼라 서브쿼리 precompute 루프(qx:16696~16716, `fetch_peek_dbval (…, subq->precomp_owner_regu, &xasl_state->vd, …)`) → `qexec_start_mainblock_iterations`(qx:16720). PX 루트는 `px_query_executor.cpp:48` 에서 `qexec_deep_copy_xasl_state`, 잡은 `px_query_task.cpp:123/235` 에서 복사·해제. `qexec_mark_aggregate_operand_expressions` 는 워커 unpack 마다 재도출(M8 부류) | qx:16538~16720, px_query_executor.cpp:48·94 |
| F-323-14 | 세션변수 읽기는 `T_EVALUATE_VARIABLE` arith 가 `session_get_variable` 로 저장값을 복제(FETCH_NOT_CONST) — 슬롯이지만 `vd` 배열에 없다 → 게이트가 다루려면 계획 슬롯(참조 자리)이 값을 받아야 한다 | fetch.c:4023~4030, session.c:2081 |
| F-323-15 | 필터/함수 인덱스 로드 `fpcache_claim` 은 `stx_map_stream_to_filter_pred` 오류를 그대로 반환하지만(fpc:408~416) 호출자 쪽 삼킴은 S-42 대로 확인 필요; `EXECUTE_REGU_VARIABLE_XASL`(xasl.h:554) 이 상관 서브쿼리를 regu 에서 실행 | filter_pred_cache.c:355~416, xasl.h:554 |
| F-323-16 | XASL 덤프는 `qdump_print_xasl`(query_dump.c, CUBRID_DEBUG 검사 경로 qx:17500) 과 trace JSON `qdump_print_stats_json`(query_dump.c:3175, `SET TRACE ON` → `SHOW TRACE`); 클라이언트 `SHOW PLAN` 은 플랜 텍스트(재작성 질의 포함) | query_dump.c, query_manager.c:1372·1907 |
| F-323-17 | 술어 노드 `comp_eval_term` = {lhs, rhs, rel_op, `DB_TYPE type`}(24B), `eval_term` union 은 like_eval_term(포인터 3)과 같은 크기, `pred_expr` 는 pred 스트림(디스크 포맷)에 팩 — 항목 포인터를 둘 비팩 자리가 없다 | xasl_predicate.hpp:99~160 |
| F-323-18 | `vd->dbval_ptr` 소비자 8곳: fetch.h:72·fetch.c:4756(TYPE_POS_VALUE), partition.c:1019·1020·1642·1802(파티션 프루닝 호스트 변수 값), dblink_scan.c:592(원격 바인드), query_executor.c:28970(서브쿼리 결과 캐시 키 `params.vals`), 그 외는 복사·해제(qx:3699~3732, px_scan.cpp:1623~2114) | 위치 열 |

### 2.0.3 의존 범주(codebase-design DEEPENING 어휘)

- **내부 상태**(XASL_STATE 게이트 표·값 배열) — 모듈이 소유, 인터페이스 밖으로 안 새는 것이 목표.
- **읽기 전용 입력**(로드된 트리·`vd.dbval_ptr[]`·`INDX_INFO.key_type`) — 순수 함수의 입력.
- **외부 규칙 표**(서버 값 격자·변환기 표(#325)·`LANG_RT_COMMON_COLL`) — 도메인 해석기 모듈이 감싼다.
- **교차 seam**(클라이언트 파서 격자·CAS 메타 경로·PL 마커 보고) — 서버 인터페이스와 코드가 다르고 계약(스트림 도메인 값·플래그 비트·`key_type`)으로만 만난다.

### 2.0.4 예시 스케치(제안 아님 — 제약을 구체화하는 그림)

```
load:   stx_map_stream_to_xasl → [unpack] → derive(tree): slot ids, K/R/S, converters, gate-dependent list, key plans  (arena)
exec:   qexec_execute_query: vd ← (const) dbval_ptr
        G1(plan, vd) → state.values[] (val_pos 당 1회 변환) + state.gate[] (슬롯 ID → dom, coll, conv, policy)
        mainblock_internal: aptr → precompute → G2(plan, state) → iterations
        range open: key plan (K: state 값 / S: converter(값))
        PX: deep_copy(state) 하나
row:    fetch/compare/key: node.derived → converter 직접 호출, 타입 판정 0
```

### 2.0.5 런타임 탐침(Sonnet 워커, optdebug `11.5.0.2600-cad2717`, 로그 `.git_ignored_dir/scratch/312-323/probe/`)

| # | 실측 | 의미 |
|---|---|---|
| P-1 (R1) | `PREPARE p1 FROM 'SELECT t1.i, t2.x FROM t1, t2 WHERE t1.i = ? AND t1.i = t2.b'` → 재작성 질의 `where [t2].b= ?:0 and [t1].i= ?:0 and [t1].i=[t2].b` — 같은 `?:0` 이 INT 형제와 BIGINT 형제 옆에 **CAST 없이** 두 번 | 참조별 미러 도메인이 갈리는 실제 사례. 1.5 → 0행, `'1'`/`1.0e0` → 1행(오류 없음) |
| P-2 (R2) | UNION ALL 파생 테이블 `v.c = ?` → 양 가지에 푸시: `cast([t1].i as double)= ?:0` / `[t1].d= ?:0` | 푸시 전에 UNION 공통 타입(DOUBLE)이 **컬럼 쪽**에 CAST 로 들어가므로 두 참조의 형제 타입은 같다 — R2 는 참조가 늘지만 도메인은 안 갈린다(중복 제거 대상) |
| P-3 (F-1) | gdb `pt_set_host_variables`: `i = ?`·`i + ? > 0`·R1 의 `?` 는 `host_var_expected_domains[0]` 이 **DB_TYPE_NULL(0)/precision 0** — `s = ?` 는 VARCHAR(1073741823, coll 1), `c = ?` 는 CHAR(-1, coll 1) | 오늘 클라이언트 캐스트는 문자 컬럼 형제에만 걸린다(#319 F-1 확정). 정수 미러 슬롯(A5·B4·B9)의 변환은 이 PR 에서 **처음 생기는** 변환이므로 strict-or-keep·strict 정책이 규칙표 그대로 구현돼야 답이 유지된다 |
| P-4 | `csql -S`(SA) 는 `SET TRACE ON` 이 동작하지 않는다(`do_send_plan_trace_to_session` → `csession_set_session_variables` 의 SA 분기) | 트레이스 근거 수집은 CS 모드로 |

## 2.1 세 안 (병렬 설계, 각 안의 정본은 `domain-pin-interface-candidates/`)

세 안 모두 전략 A 의 잠긴 결정(K1~K11) 안에서 만들어졌고, 다음은 **세 안이 독립적으로 같은 답에 이른 것**이라 사실상 확정으로 본다: `original_domain`/`original_opr_dbtype` 자리를 로드 도출 결과로 재사용(구조체 크기 불변) · 스트림 변경은 `REGU_VARIABLE_GATE = 0x4000` 비트 + `INDX_INFO.key_type`(`func_idx_col_id` 다음) 뿐 · 로드 도출 결과는 unpack arena 소유(트리와 같은 수명, 클론 풀 재사용 시 재도출 0) · 슬롯 ID 는 후위 트리 순회 1회로 부여(생산자 우선이 순회 순서에서 따라 나옴) · 바인드 값은 **참조(regu)마다** 변환값 자리를 갖고 공유 원 값은 불변(K9) · 게이트 표는 XASL_STATE 확장 · `qexec_deep_copy_xasl_state` 하나로 상속(pxt:648 경로 삭제) · 신설 오류 코드 -1383 · 클라이언트 캐스트·`pt_make_regu_hostvar` 2단계 삭제 · 도메인 해석기는 `query/` 전용.

| | **α 최소 진입점** ([정본](domain-pin-interface-candidates/alpha-minimal-entry-points.md)) | **β 데이터 지향** ([정본](domain-pin-interface-candidates/beta-data-oriented.md)) | **γ 해석기 포트·어댑터** ([정본](domain-pin-interface-candidates/gamma-resolver-port.md)) |
|---|---|---|---|
| 서버 진입점 | 3: `xplan_derive(root, arena, kind)` · `xgate_apply(xasl, xs, scope∈{EXEC,BLOCK,RANGE})` · `xgate_peek/xgate_entry`(inline 읽기) | 6: `dpin_derive_plan` · `dpin_reject_if_gated` · `dpin_gate_execute`(G1) · `dpin_gate_block`(G2) · `dpin_key_open` · inline 읽기 2 | 포트 1(`dres::resolve`) + 어댑터 함수 `dplan_derive` · `dgate_run_g1/g2` · `dgate_apply` · `dgate_free` · `dkey_make_range` |
| 노드 8B 자리 | `XPLAN_ITEM *`(arena; cls·slot·ref·val_pos·fail·정적 답 `st{domain,conv[3],setdomain}`·ISS `pair`) | `union dpin_ref { conv_fn ; {slot_id, policy, val_pos} }` — 판별자는 `flags` 의 **비팩 비트 3개**(K/R/S) | `DPLAN_NODE *`(arena; slot_id·cls·conv[3]·fail[3]·val_pos·ref_ord) |
| 게이트 표 | AoS `XGATE_ENTRY{domain, conv[3], setdomain}` — GATE·KEEP_LAZY·키 range 항목만; 정적 답은 항목 안 `st` 에 인라인 | SoA 병렬 배열 `domain[]·conv[]·value[]·key_setdomain[]` 한 번의 64B 정렬 할당; n_slots==0 이면 할당 0 | AoS `DGATE_ENTRY{dom, coll_id, conv[3], fail[3], val*}` — 표를 항상 완전하게(정적도 복사) |
| 값 배열 | G1 뒤 **`vd.dbval_ptr = gate.vals`**(0..dbval_cnt = 1차 참조 = val_pos 인덱스, 뒤는 2차 참조), 원 입력은 `gate.in`(const) — 기존 `vd->dbval_ptr[val_pos]` 소비자 무변경 | `vd.dbval_ptr` 는 입력 그대로, `TYPE_POS_VALUE` fetch 가 `gate.value[slot]` 을 읽도록 교체 | 같음(`entries[slot].val`) |
| 다중 참조 | (val_pos, 도메인, 정책) 삼중으로 **중복 제거** | 참조마다 슬롯 | 참조마다 슬롯(`ref_ord`) |
| 파생 소비자 | `XPLAN_ALIAS`: 생산자 slot 공유, 표 항목 없음 | 게이트 목록 원소(`DPIN_GN_LIST_COL` 등) | 게이트 의존 노드 목록의 `LIST_COLUMN/AGG/ANALYTIC` ctx |
| B4 strict-or-keep | `XPLAN_KEEP_LAZY` 항목: 로드가 기본 답을 채우고 G1 이 keep 실패 시에만 표 덮어쓰기 | rhs regu 슬롯의 `conv[slot] != NULL` 실행당 고정 분기 | 비교 노드를 게이트 의존으로(in_slot 에 K 슬롯) |
| 해석기 seam | `xdom_resolve(op, doms[], n, fail) → {domain, conv[3]}` + `xconv_lookup(src, dst, fail)` | `dpin_resolve(opcode, ctx, args[3]) → result, conv[3]` + `dpin_converter` + `dpin_merge_collation` | `resolve(ctx, opcode, operand[]{dom,val_type,coll,coercibility,is_gate_slot}, consumer_dom) → answer{dom, coll_id, conv[3], fail[3], needs_gate, err}` — **needs_gate 로 로드 도출이 G 행을 판별**, 규칙표 행 = 단위 테스트 1개, CMake 로 `parser/` 포함 금지 |
| PX 상속 | 값 깊은 복사, **표는 읽기 전용 포인터 공유** | 값·표 깊은 복사(워커 힙, false sharing 0) | 값·표 깊은 복사, `owner/is_copy`, 워커의 G1 호출 assert |
| PL 선언 타입 | `parser->host_var_decl_domains[]` 새 배열(형제로 취급), prepare 요청에 배열 추가 | `host_var_expected_domains[]` 를 prepare 요청 필드로 **선점** | `semantics.hvs[]` 를 입력으로도 사용(wire 필드 추가 없음) |
| 트레이스 | qdump 에 항목 전부, trace JSON 에는 정적 요약만(실행당 답은 카운터로) | trace JSON 에 실행당 답까지 | trace JSON 에 실행당 답까지 |
| 오류 코드 이름 | `ER_QPROC_DOMAIN_UNRESOLVED`(phase 인자) | `ER_QPROC_DOMAIN_NOT_PLANNED` | `ER_QPROC_UNRESOLVED_DOMAIN` |
| 실패 정책 | 4(ERROR/NULL/KEEP/**ROUND**) | 3 | 3 |

## 2.2 비교 — 깊이·지역성·seam 위치

**깊이(인터페이스 단위당 숨긴 행동).** α 가 가장 깊다: 호출자(query_executor·scan_manager·fetch)는 "스코프가 열렸다" 와 "이 regu 의 값을 달라" 두 사실만 알면 되고, 슬롯 부여·부류 판정·다중 참조·실패 정책·키 setdomain 조립이 전부 구현이다. 삭제 테스트를 통과한다(지우면 43곳이 되살아난다). γ 의 깊이는 **해석 포트**에 있다 — 규칙표 §2~§6 의 서버 값 격자·collation 병합·ENUM 표·집계 기본 도메인이 함수 하나 뒤로 모이고, 로드 도출과 G1 이 같은 함수를 부르므로 "로드가 고른 변환기 ≠ 게이트가 고른 변환기" 가 구조적으로 불가능하다. 다만 γ 가 스스로 적었듯 `resolve()` 가 `tp_infer_common_domain`·`LANG_RT_COMMON_COLL` 을 그냥 되부르는 pass-through 로 구현되면 얕아진다 — 원 자리를 **옮기고 지워야** 한다(P6). β 는 행 경로의 깊이(한 필드 + 한 포인터)가 가장 좋지만 진입점이 6개로 가장 넓고, G2 가 거의 pass-through 임을 정직하게 인정했다.

**지역성(변경이 모이는 곳).** 규칙 개정은 γ 에서 한 곳(포트 구현 + 같은 이름의 테스트)이다. α 는 규칙이 `xdom_resolve`/`xconv_lookup` 두 함수에 모이므로 비슷하지만 ctx 개념이 없어(연산자만) 대입/비교/집계 문맥별 실패 정책(X1)이 호출자에 흩어질 위험이 있다. β 는 `union` 의 판별자가 노드 밖(`flags` 비팩 비트)에 있어 잘못 읽으면 함수 포인터를 정수로 읽는다 — optdebug assert 로 막지만, 더 큰 문제는 **비팩 비트가 스트림 `flags` 정수를 공유**한다는 것이다(팩 시 마스킹 필요, 서버 측 재팩·`xasl_spawner` 경로에서 새는 사고 부류). 또 regu/arith 는 8B 하나라 "R 변환기 + G 슬롯" 을 동시에 못 갖는다(β 는 그런 노드가 없다고 주장하나 KEEP_LAZY 비교의 lhs 가 그 예다).

**seam 위치.** 세 안 모두 로드 seam(`stx_map_stream_to_xasl` 끝)과 실행 seam(G1/G2/range)을 같은 자리에 둔다. 차이는 (i) 값 배열 seam — α 는 `vd.dbval_ptr` 자체를 게이트 산출 배열로 바꿔 **기존 소비자 8곳**(fetch.h:72, fetch.c:4756, partition.c:1019·1020·1642·1802, dblink_scan.c:592, qx:28970 서브쿼리 결과 캐시 키)을 코드 변경 없이 1차 참조 변환값으로 옮기고, β/γ 는 fetch 만 바꾸고 나머지는 원 값을 본다. D-318-03 의 문구("`vd.dbval_ptr` 는 그 배열을 가리키고 입력 배열은 const 로 남긴다")는 α 와 같다. 소비자별로는 partition pruning(컬럼 미러 도메인 값이 맞다)·서브쿼리 결과 캐시 키(변환값 기준이 더 정확: `'1'` 과 `1` 이 같은 항목)는 변환값이 옳고, **dblink 바인드(원격에 원 값)** 만 `gate.in` 을 읽어야 한다. (ii) 술어 노드 — 세 안 모두 비켜 갔다: `comp_eval_term{lhs, rhs, rel_op, DB_TYPE type}` 은 24B union 이고 스트림 레이아웃이 디스크 포맷이라 항목 포인터를 둘 자리가 없다(F-323-17). 답은 "변환기는 피연산자 regu 항목에, 비교 도메인은 K regu 의 KEEP_LAZY 슬롯 또는 두 피연산자 항목의 정적 답에" — α·β 가 암묵적으로 택한 모양이며 §2.3 에서 명시한다.

**결론.** 골격은 α(진입점 3, 항목 포인터, ALIAS, 값 배열 교체, KEEP_LAZY, 스코프 하나), 해석 seam 은 γ(ctx 있는 포트 + needs_gate + 행당 테스트 + 헤더 강제), 비용 보장은 β(정적 계획 할당 0, 값·표 한 번의 64B 정렬 할당, 행 경로 분기는 실행당 고정값만). 기각: β 의 union/비팩 flags 비트, α 의 표 읽기 전용 공유(D-318-06 문자 그대로 깊은 복사 — L-46 부류 사고의 소유 규칙을 단순하게), γ 의 "정적 항목도 표에 복사"(정적 계획 0 비용 위반), α 의 4번째 정책 ROUND(정책이 아니라 대입 변환기 선택 — `xconv_lookup` 의 ctx 인자).

### 2.2.1 cpp-perf-rules 로 본 세 안 (정적 검토 — 측정은 #316 셀·#324 카운터가 한다, MEAS 규약)

행 경로 기준 셀: `int_col = ?`(K 참조 + 비교 변환기), `col + ?`(R 변환기), 키 range 원소. "의존 로드" 는 regu 에서 변환기/값에 닿기까지의 포인터 사슬 길이.

| 규칙 | α 최소 진입점 | β 데이터 지향 | γ 해석기 포트 | 종합안 H |
|---|---|---|---|---|
| BR-04·A59·A62(불변 판정·저장을 루프 밖으로) | 로드 도출 1회, `FETCH_ALL_CONST`/원복 소멸 ✔ | 같음 ✔ | 같음 ✔ — 단 정적 항목까지 실행마다 표에 복사(실행당 O(n) 불변 작업) ✖ | α ✔ + β 의 정적 계획 0 보장 |
| BR-06·A61(다단 switch → 사전 확정 함수 포인터) | `st.conv[k]` 포인터, NULL 이면 호출 생략 ✔ | 노드 안 포인터, NULL 생략 ✔ | `entries[slot].conv` ✔ (`dgate_apply` 가 inline 이어야 CC-05 통과) | ✔ |
| 의존 로드 사슬(행당) | regu→item→conv = **2** | regu→conv = **1**(R), regu→slot→value = 1(K) | regu→item→slot→entries = **3** | 2 (접근자 뒤에 숨김 — 1 로 줄이는 변형은 §2.2.2) |
| MEM-02(핫 구조체 64B) | 노드 크기 불변 ✔; 항목 ~56B 1줄 | 노드 크기 불변 ✔, 항목 배열은 cold ✔ | 노드 불변 ✔; 항목 ~24B | ✔ |
| MEM-05(핫/콜드 분리) | 항목에 핫(ref·slot·conv)과 콜드(ctx·opcode·pair·이름) 혼재 △ | 핫 8B 는 노드 안, 콜드는 `dpin_plan` 배열 ✔ | 항목이 작아 △ | 항목의 콜드 필드를 `plan->items_cold[]` 로 분리(구현 규율) |
| MEM-04(AoS/SoA) | AoS 표(항목 1줄에 domain·conv·setdomain) ✔ 비교 경로에 유리 | SoA 4배열 — 비교 한 번에 value·conv·domain 이 세 줄 △ | AoS ✔ | AoS |
| MEM-03(false sharing) | 워커 사본은 워커 private heap → 자연 분리 ✔ | 64B 정렬 명시 ✔ | ✔ | 한 블록 64B 정렬 |
| ALLOC-01/03(행·실행당 할당) | 정적 계획: `vals` clone 만(D-318-03 요구) ✔; 항목은 arena ✔ | 정적 계획 표 할당 0 ✔ | 정적도 entries 복사 → 실행당 할당 ✖ | β 보장 채택 |
| ALLOC-08·A64(교차 스레드 소유) | 값 사본은 워커 소유 ✔, **표는 읽기 전용 공유**(루트 해제 순서 계약 필요) △ | 값·표 워커 사본, owner assert ✔ | 같음 + `is_copy` 로 워커의 G1 호출 거부 ✔ | 깊은 복사 + owner assert |
| 메모리 안전(규약 3: 정확성 > 메모리 안전 > 성능) | 항목 포인터, 판별자 = 항목 내부 ✔ | **union 의 판별자가 노드 밖 `flags` 비팩 비트** — 잘못 읽으면 함수 포인터를 정수로, 비팩 비트가 스트림 정수와 공유 ✖ | ✔ | α 방식 |
| CC-05·A60(행당 무조건 호출) | 항등 변환기 NULL 로 호출 생략 ✔ | ✔ | `dgate_apply` 함수 경유면 ✖ → inline 요구 | inline 접근자 |
| PHYS-01/05(헤더 절연·레벨화) | 서버 전용 헤더 1 △ | 서버 전용 헤더 1 △ | 레벨 1/3 헤더 분리 + CMake 포함 금지 ✔ | γ 방식 |
| CPP-09 vs PHYS-05 충돌 | 해당 없음(가상 호출 없음) | 없음 | 포트는 일반 함수 — 가상 호출 0 ✔ | ✔ |

**판정.** 규칙 위반 수로는 **H ≥ α > γ > β(원형)**. β 의 유일한 우위(행당 의존 로드 1 vs 2)는 union 판별자를 스트림 `flags` 비팩 비트에 두는 대가로 얻은 것이라 규약 3(메모리 안전 > 성능)에서 진다. γ 는 규칙 seam 이 가장 좋지만 "정적 항목도 표에 복사" 가 BR-04 확장의 정반대(실행당 불변 작업)다. α 는 표 읽기 전용 공유만 △.

### 2.2.2 α 와 β 의 실제 차이는 접근자 뒤의 레이아웃 하나 — 측정으로 정한다

`xgate_peek`/`XPLAN_CONV` 접근자가 노드 8B 의 해석을 숨기므로, "노드 8B = 항목 포인터(α, 의존 로드 2)" 와 "노드 8B = `{int32 ref_or_slot; int16 cls; int16 item_idx}` POD + R 변환기는 `plan->conv_hot[item_idx]`(의존 로드 1~2, 판별자는 노드 안)" 는 **인터페이스 불변의 구현 변형**이다. 규약 1(측정 없이 최적화 금지)에 따라 초기 구현은 α 레이아웃으로 하고, #324 카운터·#316 P1~P8 셀에서 fetch 경로가 병목으로 잡히면 POD 변형으로 바꾼다(접근자만 수정, 호출자 0). 오늘의 `tp_value_compare_with_error` rank 사슬·`DB_VALUE_DOMAIN_TYPE` 2단 디스패치(수십 분기)를 지우는 이득에 비해 L1 히트 1회(~4 cycle)는 측정 전에는 판단하지 않는다.

## 2.3 종합안 H — 인터페이스 (초안; **정본은 `domain-pin-interface.md` v4**)

> 2026-09-22 사용자 검토로 이름과 계약이 바뀌었다: 축약 접두(`x`/`d`) 금지 → `DOMAIN_PLAN`/`RESOLVED_DOMAIN`/`stx_build_domain_plan`/`qexec_resolve_domains`; G2·range 시점 결정 함수 삭제(mainblock 진입 전 트리 전체 확정, 이후 읽기 전용); 정적 리뷰 R1~R9 반영(VOLATILE 부류, 혼합 setdomain 스크래치, 결과 캐시 키 원 값, 고정 조건 호이스팅, 실행 임시값, 헤더 허용/금지, PX 해제 경로, const 뷰, 측정 보류). 아래 §2.3~§2.12 는 종합 당시의 초안이며 충돌 시 `domain-pin-interface.md` 가 이긴다.



### 2.3.1 공개 진입점(서버, `src/query/xasl_plan.hpp`)

```c
/* E1 로드 도출 — stx_map_stream_to_xasl / _filter_pred / _func_pred 의 언팩 직후 1회 (세 로드 경로 공통, D-318-02).
 * 순수 함수: 같은 스트림 → 같은 items/slots/refs. 결과는 unpack arena. PRED 종류는 GATE 비트가 있으면 거부(경계 (a)). */
typedef enum { XPLAN_KIND_QUERY, XPLAN_KIND_PRED } XPLAN_KIND;
int xplan_derive (THREAD_ENTRY *thread_p, xasl_node *root, XASL_UNPACK_INFO *arena, XPLAN_KIND kind);

/* E2 게이트 적용 — 스코프당 1회. EXEC(G1) 만 결정, BLOCK(G2)·RANGE 는 계획된 변환기 적용만 (D-318-08). */
typedef enum { XGATE_SCOPE_EXEC, XGATE_SCOPE_BLOCK, XGATE_SCOPE_RANGE } XGATE_SCOPE;
int xgate_apply (THREAD_ENTRY *thread_p, xasl_node *xasl, xasl_state *xs, XGATE_SCOPE scope);

/* E3 읽기 — 행 경로의 유일한 접근자(inline, 실행당 고정 분기 1). */
static inline DB_VALUE           *xgate_peek  (const VAL_DESCR *vd, const REGU_VARIABLE *regu);   /* 참조별 변환값 = vd->dbval_ptr[item->ref] */
static inline const XGATE_ENTRY  *xgate_entry (const VAL_DESCR *vd, const XPLAN_ITEM *item);      /* item->slot < 0 ? &item->st : &xs->gate.table[item->slot] */
#define XPLAN_DOMAIN(vd, item)   (xgate_entry ((vd), (item))->domain)
#define XPLAN_CONV(vd, item, k)  (xgate_entry ((vd), (item))->conv[(k)])

/* 수명(기존 함수군의 확장 — 새 진입점으로 세지 않음) */
xasl_state *qexec_deep_copy_xasl_state (THREAD_ENTRY *, xasl_state *);   /* vd(=vals) + gate.table 깊은 복사, owner = 워커 */
void        qexec_free_xasl_state      (THREAD_ENTRY *, xasl_state *);   /* assert (gate.owner == thread_p) */
void        qexec_clear_xasl_state     (THREAD_ENTRY *, xasl_state *);   /* 루트(스택) 용: vals/table 해제, vd.dbval_ptr = NULL */
```

### 2.3.2 해석 포트(서버, `src/query/xasl_domain_resolver.hpp` — `parser/`·`compat/`·`broker/`·`method/` 포함 금지, CMake include 경로로 강제)

```cpp
namespace cubquery::dres {
  enum class ctx : uint8_t { ARITH, COMPARE, ASSIGN, COMMON_VALUE, AGG, ANALYTIC, FUNC_ARG, LIST_COLUMN, KEY_ELEM };
  typedef int (*conv_fn) (THREAD_ENTRY *, const DB_VALUE *src, DB_VALUE *dst, const TP_DOMAIN *dom);   /* #325 표의 원소; NULL = 항등 */
  enum class fail_policy : uint8_t { ERROR_494, NULL_IF_PRM, KEEP };                                     /* X1, D-327-10 */
  struct operand { const TP_DOMAIN *dom; DB_TYPE val_type; int coll_id; uint8_t coercibility; bool is_gate_slot; };
  struct answer  { const TP_DOMAIN *dom; int coll_id; conv_fn conv[3]; fail_policy fail[3]; bool needs_gate; int err; };
  /* 유일한 규칙 seam. 순수 함수·할당 0·er_set 0. 로드 어댑터는 val_type=NULL 로 부르고 needs_gate 로 G 행을 판별, G1 어댑터는 값 타입을 넣어 부른다. */
  answer  resolve (ctx c, int opcode, const operand *ops, int nops, const TP_DOMAIN *consumer_dom);
  conv_fn lookup  (DB_TYPE src, const TP_DOMAIN *dst, ctx c);        /* (원 타입, 목표, 문맥) → 고정 함수; 대입 문맥은 반올림 캐스트, 산술·비교는 strict */
  const char *conv_name (conv_fn f);                                  /* 덤프 전용 */
}
```

### 2.3.3 타입 — 로드 도출 결과(arena, 불변)

```c
typedef enum { XPLAN_K = 1, XPLAN_R = 2, XPLAN_S = 3 } XPLAN_CLASS;
struct xgate_entry { TP_DOMAIN *domain; /* collation 포함, flag NORMAL */ dres::conv_fn conv[3]; dres::fail_policy fail[3]; TP_DOMAIN *setdomain; /* 키 range 항목만 */ };
struct xplan_item  {
  short cls;  short flags;   /* XPLAN_GATE 0x01 · KEY1 0x02 · KEY2 0x04 · ISS 0x08 · ALIAS 0x10(생산자 slot 공유) · KEEP_LAZY 0x20 (X_RESIDUAL 0x40 은 D-335-10 으로 삭제) */
  int slot;                  /* 게이트 표 인덱스, -1 = 정적(답은 st) */
  int ref;                   /* K 참조의 값 인덱스(vd->dbval_ptr[ref]); TYPE_POS_VALUE·TYPE_DBVAL 외 -1 */
  int val_pos;               /* 바인드 배열 인덱스 또는 -1 (auto-param TYPE_DBVAL 은 -1, src = regu->value.dbvalptr) */
  dres::ctx ctx;  int opcode;/* 이 항목이 결과인 문맥(게이트 의존 노드 재해석·덤프) */
  struct xgate_entry st;     /* 정적 답(로드 확정) */
  const struct xplan_item *pair;   /* ISS 내림차순 fetch 범위 짝 */
};
struct xplan {               /* 트리당 1개: xasl_node->xplan (블록마다 같은 포인터), xasl_node->xplan_blk (블록의 S 항목) */
  int n_items;  xplan_item *items;          /* 부여 순서 */
  int n_slots;                              /* = GATE + KEEP_LAZY + 키 range 항목 (정적 계획 0) */
  int n_refs;   int dbval_cnt;              /* n_refs = dbval_cnt + 2차 참조 수 */
  int n_gate_nodes;  xplan_item **gate_nodes;   /* 생산자 우선 = 후위 순회 순서 */
  int n_refs_k;      xplan_item **refs_k;       /* K 참조 항목(ref 오름차순) */
  int n_keys;        struct xplan_key *keys;    /* §2.5 */
  const char **item_name;                   /* 덤프용("?:0", "arith@qx", "agg#2", "key[1].k1[0]") */
};
```
필드 재사용(MEM-02): `regu_variable_node::original_domain` → `xplan_item *xplan`; `arith_list_node::original_domain` → 동일; `aggregate_list_node::original_domain` → 동일, `original_opr_dbtype`(4B) → `int xplan_acc`(누산기 value2 항목, -1 없음); `analytic_list_node` 동일; `qfile_tuple_value_position::original_domain` → 동일. 스트림 비트: `REGU_VARIABLE_GATE = 0x4000`(컴파일 세팅, 팩됨). agg 는 `flag.dummy` → `flag.gate`, analytic 은 `flag` 의 미사용 비트. **부류 K/R/S 는 항목에만**(flags 비팩 비트 없음). `xasl_node` 에 `xplan`·`xplan_blk` 포인터 2개 추가(디스크 무관).

### 2.3.4 타입 — 실행 상태(XASL_STATE 확장)

```c
struct xgate_state {
  const DB_VALUE *in;      /* 입력 배열(const; SA_MODE 는 parser->host_variables 자체) — 실행 중 어느 스레드도 쓰지 않는다 (I3) */
  DB_VALUE *vals;          /* [n_refs] 참조별 변환값. G1 뒤 vd.dbval_ptr == vals (I1) */
  xgate_entry *table;      /* [n_slots] 게이트 표. G1 뒤 불변 */
  int n_vals, n_slots;
  THREAD_ENTRY *owner;     /* 해제할 수 있는 유일한 스레드 (ALLOC-08/A64) */
  const xplan *plan;
};
struct xasl_state { VAL_DESCR vd; QUERY_ID query_id; int qp_xasl_line; xgate_state gate; };
```
`vals`·`table` 은 **한 번의** `db_private_alloc`(64B 정렬, `vals` 가 앞). 정적 계획(`n_slots == 0 && n_refs == dbval_cnt`)은 `table` 없이 `vals` 에 `dbval_cnt` 개 clone 만(β 의 0 비용 보장; clone 자체는 D-318-03 의 별도 배열 요구). PX 사본은 워커 힙에 같은 형상(false sharing 0).

**불변식.** (I1) G1 뒤 `vd.dbval_ptr == gate.vals`, `vals[val_pos]` 는 그 `?` 의 1차 참조 값 → 기존 8곳 소비자는 1차 참조 변환값을 본다(dblink_scan.c:592 만 `gate.in` 으로 변경 — 원격에는 원 값). (I2) 모든 K 참조에서 `DB_VALUE_DOMAIN_TYPE (vals[ref]) == TP_DOMAIN_TYPE (XPLAN_DOMAIN (item))` 이거나 `fail == KEEP` 으로 표에 기록된 항목(B4) — 경계 (b) assert, `xgate_apply(EXEC)` 끝. (I3) `gate.in` 불변. (I4) 세 로드 경로가 같은 `n_items/n_slots/n_refs` 와 각 항목의 `slot/ref` 를 얻는다 — 워커 진입 시 `assert (worker->xplan->n_slots == root_gate->n_slots)`. (I5) `gate_nodes` 는 생산자 우선(항목 i 의 피연산자 j 는 i 앞). (I6) 술어 노드는 항목을 갖지 않는다 — 변환기는 피연산자 regu 항목의 `conv[0]`(자기 값 → 소비 도메인), 비교 도메인은 K regu 의 KEEP_LAZY 슬롯(B4·B5) 또는 두 피연산자 항목의 정적 답(B25; 같은 도메인).

### 2.3.5 호출 순서

```
qexec_execute_query (qx:17456)
  xasl_state.vd.dbval_ptr = (DB_VALUE *) dbval_ptr;  vd.dbval_cnt = dbval_cnt;   (qx:17578~17579 그대로)
  … sys_datetime/epoch …
+ xgate_apply (thread_p, xasl, &xasl_state, XGATE_SCOPE_EXEC);      ← G1 (aptr·PX clone·sq_get 전). 실패 = 실행 전 오류 → query_error
  qexec_execute_mainblock (…)
+ qexec_clear_xasl_state (thread_p, &xasl_state);                  ← 정상·오류 경로 모두

qexec_execute_mainblock_internal (qx:16150)
  aptr_list 실행 (qx:16538~)  — 하위 블록은 같은 xasl_state, 자기 블록의 G2
  precompute (qx:16696~16716)
+ xgate_apply (thread_p, xasl, xasl_state, XGATE_SCOPE_BLOCK);      ← G2: xasl->xplan_blk 의 S 항목에 변환기 적용만; 정적이면 첫 줄 반환
  qexec_start_mainblock_iterations (qx:16720)

scan_regu_key_to_index_key (sm:2328)
+ xgate_apply (…, XGATE_SCOPE_RANGE);                               ← S 키만(K 키는 G1 에서 끝, 항목 플래그로 건너뜀)

fetch_peek_dbval TYPE_POS_VALUE (fe:4756, fetch.h:72)   *peek_dbval = xgate_peek (vd, regu_var);   (FETCH_ALL_CONST 세팅 삭제 — 로드 도출 cls)
EXECUTE_REGU_VARIABLE_XASL (xasl.h:554) 뒤 상관 TYPE_CONSTANT      item->cls == XPLAN_S 면 conv 적용(스코프 = 외부 행)
px_query_executor.cpp:48 / px_query_task.cpp:123 / pxt:648 → qexec_deep_copy_xasl_state (vals + table)
```

**G1 알고리즘(`xgate_apply(EXEC)`).** ① `assert (plan->dbval_cnt == vd.dbval_cnt)`(L-30 서버 측); `vals[n_refs]`·`table[n_slots]` 할당, `gate.in = vd.dbval_ptr`, `vd.dbval_ptr = vals`. ② `refs_k` 순회: `src = in[val_pos]`(auto-param 은 `regu->value.dbvalptr`); 정적 항목이면 `fn = dres::lookup (DB_VALUE_DOMAIN_TYPE (src), item->st.domain, item->ctx)` 실행당 1회 → `fn (src, &vals[ref], dom)`; 실패 → `fail`: ERROR_494 는 즉시 반환(코드는 현행 -494 계열), NULL_IF_PRM 은 `vals[ref] = NULL`(파라미터 no 면 ERROR), KEEP 은 `pr_clone_value (src, &vals[ref])` + KEEP_LAZY 슬롯을 `dres::resolve (COMPARE, …, {계획 도메인, 값 도메인})` 로 재확정(비교 DOUBLE, `conv[0] = int→double`). GATE 슬롯(P2)은 `table[slot].domain = tp_domain_resolve_value (src)`(codeset·collation 포함) + clone; 세션변수 K 슬롯은 `session_get_variable` 로 src 를 읽는다(S4·S5). ③ `gate_nodes` 순회(I5): 피연산자 도메인을 `XPLAN_DOMAIN` 으로 읽어 `dres::resolve (item->ctx, opcode, ops, n, consumer_dom)` → `table[slot]`(산술 결과·COALESCE 류 공통 타입·누산기·리스트 컬럼·collation 병합 `LANG_RT_COMMON_COLL` 이 여기서 1회; err -1150/-622 는 G1 시점). ④ 키 range K 항목: strict-or-keep → `table[slot].setdomain` 1회 조립(§2.5). 정적 계획은 ②(clone 만)③④ 가 빈 배열.

## 2.4 `val_pos` 다중 참조 (탐침 P-1·P-2, F-323-08)

참조 = (val_pos, 목표 도메인, 실패 정책) 삼중. 로드 도출이 `TYPE_POS_VALUE` regu 를 만날 때마다 삼중으로 **중복 제거**해 `ref` 를 준다: 첫 참조는 `ref = val_pos`(1차), 삼중이 다른 뒤 참조는 `ref = dbval_cnt + k`(2차), 같은 삼중은 같은 `ref`(변환 1회). R1(`t1.i = ?` INT/KEEP 와 `t2.b = ?` BIGINT/KEEP)은 두 자리, R2(양 가지 DOUBLE/KEEP)는 한 자리. 실패 정책 NULL 은 그 `ref` 에만 들어가고 `gate.in` 은 불변(D-327-10). 게이트 표에는 참조가 항목을 만들지 않는다(값 배열만). `KEYLIMIT ?`(B34)·LIKE 재작성(`PT_LIKE_LOWER_BOUND(?)`)도 같은 메커니즘. `host_var_expected_domains[idx]`(마지막 기록자 승)는 prepare 메타 전용으로 남고 변환의 입력이 아니다.

## 2.5 인덱스 키 변환 계획 (L-45 a~g)

- **스트림** `INDX_INFO.key_type`(TP_DOMAIN*): `xts_process_indx_info`(xs:4760) 의 `func_idx_col_id` 다음·`cov_list_id` 오프셋 앞에 `OR_PACK_DOMAIN_OBJECT_TO_OID`, `stx_build_indx_info`(sx:4784) 같은 자리에 `or_unpack_domain`, `xts_sizeof_indx_info`(xs:7024) 에 `or_packed_domain_size`. 컴파일은 `index_entryp->key_type` 그대로(f). access-spec 레이아웃, 디스크 무관.
- **항목** `struct xplan_key { KEY_RANGE *range; int slot; /* setdomain 자리 */ char cls; /* K: 전 원소 K, S: 하나라도 S */ int ncols1, ncols2; xplan_item **elems1, **elems2; /* key1/key2 분리 (c) */ TP_DOMAIN *asc_key_type; /* is_desc 0 사본 (e) */ TP_DOMAIN *keep_setdomain; /* S 키 keep 경로용 대체 setdomain, 로드가 arena 에 미리 */ }`. 원소 항목의 목표 = `key_type->setdomain[i]`(midxkey) 또는 `key_type`(단일).
- **K 키(G1 1회)**: 원소마다 `dres::lookup (…, KEY_ELEM)`(strict 의미) → 성공 = 인덱스 도메인 값, 실패 = 값 유지 + 그 원소만 값 도메인(B30·B31, 현행 의미). `table[slot].setdomain` 을 이때 1회 조립 → `need_new_setdomain`·`prebuilt_midxkey_domains`(sm.h:291·345, sm:1889~2148·2251·3745·5418) 삭제, 해제는 게이트 표와 함께(g). `btree_compare_key` 폴백(S-12) 자리는 원소 항목 `conv[0]`(idx_elem → 값 도메인 비교 변환기) 호출 + 경계 assert.
- **S 키(range open)**: `xgate_apply(RANGE)` 가 로드 고정 변환기를 값에 적용하고 결과(성공/실패)로 `st.setdomain`/`keep_setdomain` 중 하나를 **고르기만** 한다 — 도메인 생성도 전략 재추론도 없다(a·b).
- **ISS**: `iss_range.key1` 첫 컬럼 도메인 = `asc_key_type->setdomain` 첫 원소(sm:447~458 현행 읽기 유지, S-31 값 도메인 대입 삭제); 내림차순 bound 이동(key1→key2)은 두 항목이 `pair` 로 서로를 가리키는 fetch 범위 짝(d). **MRO**: `btree_range_opt_check_add_index_key`(S-32) `sort_col_dom` 을 `asc_key_type` 으로 스캔 준비 시 1회 시딩(L-44), `has_null_domain` 루프 삭제.

## 2.6 검증 경계

**(a) 로드(`xplan_derive` 끝).** "도메인이 VARIABLE/LEAVE 인데 GATE 비트도 ALIAS 도 아닌" 항목 → `ER_QPROC_DOMAIN_UNRESOLVED`(phase "load"). 예외 표는 `xasl_plan.cpp` 의 도출 코드 바로 옆 정적 배열 `xplan_load_exceptions[]`:

| # | 자리 | 왜 설계상 VARIABLE 인가 | 처리 |
|---|---|---|---|
| X-1 | `TYPE_REGU_VAR_LIST` 포장 regu(CUME_DIST/PERCENT_RANK) | 값이 아니라 목록 | 항목 없음(자식만) |
| X-2 | `REGU_VARIABLE_ANALYTIC_WINDOW` 정렬 키 regu | 리스트 컬럼 도메인을 ALIAS 로 | ALIAS |
| X-3 | 집합 연산 리스트 컬럼 pos_descr | 가지가 GATE 면 공통 도메인은 게이트 표(U3/C8) | ALIAS→GATE |
| X-4 | `TYPE_LIST_ID`·`TYPE_ORDERBY_NUM`·`TYPE_INST_NUM` 등 값 없는 regu | 도메인 무의미 | 항목 없음 |
| X-5 | `TYPE_FUNCTION` 집합 생성자(F_SEQUENCE/F_SET…) | 컬렉션 도메인은 원소에서 | 정적(원소 ALIAS) |
| X-6 | `T_EVALUATE_VARIABLE` 세션변수 읽기 | S4 형제 있으면 미러 정적, 없으면 GATE(S5) — 컴파일이 비트를 단다 | GATE 비트 요구 |
| X-7 | ~~F10 인자~~ | **폐기(D-335-10)**: 컴파일 DOUBLE | — |

필터/함수 인덱스: `stx_map_stream_to_filter_pred`/`_func_pred` 가 `xplan_derive (…, XPLAN_KIND_PRED)` — GATE 비트 하나라도 있으면 거부. `fpcache_claim`(filter_pred_cache.c:355~416)의 `NO_ERROR + NULL` 삼킴(S-42)은 오류 전파로 수정.

**(b) 실행.** `ER_QPROC_DOMAIN_UNRESOLVED = -1383`(`error_code.h`, `ER_LAST_ERROR` → -1384), `msg/*/cubrid.msg` `$set 5`: `1383 Domain of a query node is unresolved at %1$s (query %2$s, node %3$d, domain %4$s).` 인자 = phase("load"/"execute"), `xasl->query_alias`(없으면 `qp_xasl_line`), 항목 인덱스(`item_name`), 도메인 이름. optdebug 는 같은 자리에 `assert`. 설치 자리: `qdata_get_valptr_type_list`, `fetch_peek_dbval_slow` 옛 VARIABLE 분기, `btree_compare_key` 폴백, `eval_value_rel_cmp` coercion 자리, 집계 첫값 대기 자리, `scan_dbvals_to_midxkey` 재추론 자리 + I2 assert. 각 자리는 #324 카운터와 1:1. **재컴파일 트리거 제외**: db_vdb.c:2277(·1102·2174·2218·2314·2390·2537), cas_execute.c:1188·1502·2376, cas_common_execute.c:364, method_callback.cpp:276, trigger_manager.c:4971 — 어디에도 넣지 않는다(D-318-04).

## 2.7 클라이언트 경로

- `pt_set_host_variables`(pd:3072): `is_ref` 검사 + `pr_clear_value/pr_clone_value` 만. `tp_value_cast_preserve_domain` 분기·CHAR 원 값 유지 분기(pd:3128) 삭제(B7 의미는 게이트 CHAR 변환기, D-327-01). `MSGCAT_SEMANTIC_CANT_COERCE_TO` 는 이 지점에서 사라지고 G1 의 -494 계열이 된다(F-5: 시점 이동, 코드 동일 — 탐침 P-3: 정수 미러 슬롯은 오늘 캐스트가 없었으므로 이 PR 에서 처음 생기는 변환이다).
- `host_var_expected_domains[]` 남는 소비자(F-323-09): prepare 메타(vdb:2954·db_query.c), PL 보고(mc:657), semantic_check.c:13412, 하위 세션 공유(vdb:3350·3436), 바인드 피크(vdb:3209, 비용 추정만). 삭제 소비자: pd:3110.
- `pt_make_regu_hostvar`(xg:6391): 2단계(xg:6418~6445)와 꼬리 `tp_value_cast`(xg:6493~6500) 삭제; 미바인드 `db_value_domain_init` 프리셋(xg:6484)은 typed NULL 의미라 유지. 순서 = data_type → expected_domain → type_enum → GATE 면 placeholder + `REGU_VARIABLE_GATE`. 형제 미러·소비자 도메인 우선은 첫 패스 확정 + 재평가 멱등(F-3).
- L-30: `pt_to_xasl` 끝 `assert (parser->dbval_cnt == parser->host_var_count + parser->auto_param_count)`; 서버 G1 ①.
- L-31: prepare 응답은 컴파일 도메인. GATE 결과 컬럼(`SELECT ?`·`? UNION ?`·`sum(?)`)은 `list_id.type_list` 가 `XPLAN_DOMAIN` 으로 만들어지므로 실행 응답 `include_column_info`(cas_execute.c:1292·1637·1834) 현행 경로로 갱신 — wire 변경 0.
- S6 PL/CSQL: PL 서버 → `method_callback.cpp:608` prepare **요청**에 마커별 (DB_TYPE, precision, scale, codeset, collation) 배열 추가(미지정 = DB_TYPE_NULL); 클라이언트 파서에 `parser->host_var_decl_domains[]`(별도 배열, JDBC 는 NULL)를 `db_compile_statement` 전에 주입; 타입 검사는 이 도메인을 `?` 노드의 **형제**(P1 의 PL 선언 타입)로 본다. 보고 경로(mc:650~675)는 그대로. `host_var_expected_domains[]` 선점 방식(β)은 tc:8617 이 덮어쓰므로 기각.
- `hostvar_late_binding`(nr:3805·qr:501·tc:19714)·`pt_is_op_hv_late_bind`(tc:20520) 는 #320 마무리.

## 2.8 SHOW PLAN / trace

- `qdump_print_regu_variable`(query_dump.c): regu 마다 `{plan #<item> cls=K|R|S slot=<n>|static ref=<n> conv=<name> fail=ERR|NULL|KEEP gate|X}`; `qdump_print_xasl` 첫 줄 `plan: items=N slots=S refs=R(+k) gate_nodes=G`.
- trace(`SET TRACE ON` → `SHOW TRACE`, `qdump_print_stats_json` query_dump.c:3175): **D-323 결정 대상** — (a) 변경 없음(관찰은 #324 카운터로; TC 불변) / (b) 루트에 정적 요약 `"plan": {slots, refs, gate_nodes}` 추가(트레이스 TC expected 갱신 = §7 답안 변경 행 추가) / (c) 실행당 답까지. 권고 (a): 로드 도출 결과는 qdump 로 검사 가능하고(B 안 장점 흡수), 트레이스 텍스트는 불변 목표(L-50).
- 클라이언트 `SHOW PLAN` 텍스트(`?:0`)는 불변(§7 `cbrd_25374`).

## 2.9 삭제 목록(S-01~S-43 + collation 26곳)과 테스트 표면

| 축 | 지점 | 도달 불가하게 만드는 인터페이스 요소 |
|---|---|---|
| CP | S-03 S-11 S-13 S-14 S-15 S-16 S-17 S-18 S-19 S-20 S-21 S-22 S-24 S-25 S-29 S-37 | 노드 도메인 확정(VARIABLE·LEAVE 0) + 파생 소비자 ALIAS → `XPLAN_DOMAIN` 읽기만; S-14 자리에 경계 (b) |
| CP+G1 | S-01 S-02 S-04 S-05 S-06 S-23 S-26 S-27 S-28 S-36 | 정적이면 `item->st`, GATE 면 `table[slot]`(G1 ③ `dres::resolve`) — 탈착·복원·첫값 대기·시도 캐스트·두 값 추론(S-04) 삭제; S-06 다중 행 VALUES 는 열 항목 하나(C9 병합은 G1) |
| G1 | S-07 S-09 S-10 S-39 S-40 S-41 | K 참조 변환(`refs_k`), `xgate_peek`; S-09/S-10 자리는 `conv[]` 호출 + I2; S-39 힙 전환은 in-place coerce 소멸 |
| LD | S-38(sx 6·sp 3·qx 원복 5) S-33 M8(`FETCH_ALL_CONST`/`FAST_PEEK`/`AGG_OPERAND` 재도출 fe:4745·fe:5273·qx:1533~1536·qx:21839·pxt:675) | `original_domain` → `xplan`(G-02); 상수성·AGG_OPERAND 는 `item->cls`(A59/A62) |
| G1+G2 | S-12 S-30 S-31 S-32 S-34 S-35 | §2.5 키 계획, `pair`, MRO 시딩; 워커는 `table` 사본만(역전파 삭제) |
| KEEP | S-08 S-10/S-12 함수 자체 | I2 뒤 결정적; 경계 assert 위치 |
| 경계 | S-42(PRED 거부 + `fpcache_claim` 전파) S-43(#320) | `XPLAN_KIND_PRED` |
| X | ~~F10~~ | 없음(D-335-10, X-7 폐기) |
| collation | #314 §4 26곳(fe:4479 5226 5239 · lf:7082 qx:1362 21193 21249 21277 21405 23137 27787 sm:8231 8254 8287 8293 · qx:21328 21336 21440 21605 qa:1876 3343 qn:59 188 sm:8240 8264 · fe:5273 `qdata_agg_is_plain_sum_avg`) + `qfile_unify_types` -1509 분기·`qexec_end_one_iteration` 플래그 분기 | `xgate_entry.domain` 의 collation_flag 항상 NORMAL(C3 병합은 G1 ③) — 쌍 조건 두 축이 함께 |

**테스트 표면 = 인터페이스.** (T1) 포트 단위(`unit_tests/query/test_domain_resolver.cpp`): 규칙표 행마다 케이스 1개 — §2 A-행(ARITH), §3 B-행(COMPARE/KEY_ELEM), §4 U/F/S/X 행, §6 C-행(coll_id) — 입력 (ctx, opcode, operand[], consumer_dom), 기대 (dom, coll, conv, fail, err); asis-matrix 셀 라벨을 케이스 이름으로 → 게이트 CTP diff 가 나면 같은 이름의 포트 테스트가 먼저 깨진다. `dres_vs_parser_grid`: 규칙표 C 행을 고정 데이터로 두고 서버 `resolve()` 와 asis-matrix 실측(파서 답)을 대조 — 파서를 서버 테스트에 링크하지 않는다. (T2) 로드 도출 결정성: 같은 스트림을 세 경로로 로드해 `items[]` 의 (cls, slot, ref, val_pos) 비교(I4 상시 assert + 단위). (T3) G1 단위: 합성 XPLAN + 값 배열 → `vals/table`(R1·R2, KEEP, NULL 정책, GATE collation 병합 -1150). (T4) 경계: VARIABLE 스트림 → -1383, PRED+GATE → -1383. (T5) 행동: 규칙 셀·§7·CTP sql 전수+medium(optdebug). (T6) 카운터 8종 = 0.

## 2.10 렛저 대응표

| L | 종합안에서 |
|---|---|
| L-30 | §2.7 카운트 assert(`pt_to_xasl`) + G1 ①; 클라이언트 캐스트 삭제로 OOB 순회 소멸 |
| L-40 | §2.3.1 E1 이 세 로드 경로 공통, XPLAN 은 arena(pack 0), PRED 종류 거부 |
| L-41 | ALIAS + `gate_nodes` 생산자 우선(후위 순회), MERGE/CTE 하위는 aptr 순서로 같은 순회 |
| L-42 | `original_domain` → `xplan`(원복 코드·필드 소멸), 상태는 `xgate_state` 만 |
| L-43 | 누산기·분석 = `xplan_acc` 항목(ALIAS/GATE, ctx AGG/ANALYTIC), 첫값 블록 삭제 |
| L-45 | §2.5 (a) 로드/G1 1회 (b) K=EXEC·S=RANGE (c) elems1/elems2 (d) pair (e)(f) `asc_key_type`←`INDX_INFO.key_type` (g) setdomain 은 게이트 표 소유 |
| L-46 | `gate.owner`, 값·표 깊은 복사 하나(pxt:648 교체), 워커 결정 0(EXEC 스코프 호출 assert), S-39 힙 전환 소멸 |
| L-48 | X-1~X-7 를 도출 코드 옆에, `fpcache_claim` 삼킴 수정, -1383 + 재컴파일 트리거 제외 |
| L-49 | I2(값 타입 = 계획 도메인, KEEP 은 표에 기록), S-33 KEEP, B33 auto-param 은 K 참조로 실제 변환 |

## 2.11 cpp-perf-rules 인용

BR-04·A59·A62(불변 도출을 루프 밖·로드 1회로: cls·FETCH_ALL_CONST·AGG_OPERAND·원복) · BR-06/A61(행 경로 switch → 로드 고정 함수 포인터, 항등은 NULL 로 호출 생략) · MEM-02(노드 크기 불변, arena 항목) · ALLOC-08/A64(값·표 소유 스레드 = 만든 스레드, 워커 사본) · PHYS-01/05(해석기 헤더 레벨 1, `parser/` 포함 금지를 CMake 로) · 캐시(값·표 한 블록 64B 정렬, 워커 사본 분리).

## 2.12 결정 목록(제안 — #323 코멘트 "결정 기록" 이 잠근 뒤 정본)

| # | 결정(권고) | 대안·기각 근거 |
|---|---|---|
| D-323-01 | 골격 = **α**(진입점 3: `xplan_derive`/`xgate_apply(scope)`/`xgate_peek`), 노드 8B 자리 = 항목 포인터(arena) | β union + 비팩 flags 비트 기각(스트림 정수 공유·판별자 외부·R변환기+슬롯 동시 불가) |
| D-323-02 | 규칙 seam = **γ 포트** `dres::resolve(ctx, opcode, operand[], consumer_dom) → answer{dom, coll, conv[3], fail[3], needs_gate, err}` + `lookup`; 로드 도출·G1·키가 공용, 규칙표 행 = 단위 테스트 1개, `parser/` 포함 금지 CMake 강제 | α 의 ctx 없는 `xdom_resolve` 는 X1 문맥별 정책을 호출자에 흩뜨림 |
| D-323-03 | 값 배열 = α: G1 뒤 `vd.dbval_ptr = gate.vals`(1차 참조 = val_pos 인덱스, 2차는 뒤), 원 입력 `gate.in` const — 기존 8곳 소비자 무변경, **dblink 만 `gate.in`** | β/γ 의 fetch 우회는 partition.c·qx:28970 이 원 값을 보게 되어 소비자마다 판단 필요 |
| D-323-04 | 참조 = (val_pos, 도메인, 정책) 삼중 중복 제거(R2 는 1회 변환), 표 항목 없음 | 참조마다 슬롯(β/γ)은 단순하나 R2 65곳 부류에서 변환 2배 |
| D-323-05 | 게이트 표 항목 `{domain, conv[3], fail[3], setdomain}` AoS; 표는 GATE·KEEP_LAZY·키 range 만, 정적 답은 항목 `st` 인라인 → 정적 계획 `n_slots = 0`, 할당은 `vals` clone 뿐(β 보장) | γ 의 "정적도 표에 복사" 는 실행당 O(n) |
| D-323-06 | PX 상속 = 값·표 **깊은 복사**(D-318-06 문자 그대로), 한 블록 64B 정렬, `owner` assert, 워커의 EXEC 스코프 호출 assert | α 의 표 읽기 전용 공유는 루트 해제 순서에 계약을 하나 더 만든다(L-46 부류) |
| D-323-07 | 술어 노드는 항목 없음(I6): 변환기는 피연산자 regu 항목 `conv[0]`, 비교 도메인은 K regu 의 KEEP_LAZY 슬롯 / 정적 답 | `comp_eval_term` 24B union·디스크 포맷이라 자리 없음(F-323-17) |
| D-323-08 | G2·range = `xgate_apply(BLOCK|RANGE)` 스코프; S 키 keep 경로 setdomain 은 로드가 arena 에 미리 | 별도 진입점(β/γ)은 호출자가 잊는 사고 부류 |
| D-323-09 | 경계 오류 `ER_QPROC_DOMAIN_UNRESOLVED = -1383`(phase·query·node·domain), 예외 표 X-1~X-7 | 이름 후보 `DOMAIN_NOT_PLANNED`·`UNRESOLVED_DOMAIN` |
| D-323-10 | PL 선언 타입 = `parser->host_var_decl_domains[]` 별도 배열(형제 취급) + prepare 요청 wire 배열 | expected_domains 선점(β)은 tc:8617 이 덮어씀; hvs 재사용(γ)은 mode 의미 혼용 |
| D-323-11 | 트레이스 = qdump 전부 + trace JSON **변경 없음**(관찰은 #324 카운터) | (b)/(c) 는 트레이스 TC expected 갱신 |
| D-323-12 | 실패 정책 3종(ERROR_494/NULL_IF_PRM/KEEP); 대입 반올림은 `lookup(…, ASSIGN)` 의 변환기 선택 | α 의 ROUND 정책 |
| D-323-13 | agg/analytic: `original_domain` → `xplan`, `original_opr_dbtype` → `int xplan_acc` | — |
| D-323-14 | 스트림 비트는 `REGU_VARIABLE_GATE 0x4000` 하나; 부류는 항목에만 | β 비팩 비트 |
| D-323-15 | 헤더 = `query/xasl_plan.hpp`(항목·표·진입점, 레벨 3) · `query/xasl_domain_resolver.hpp`(포트, 레벨 1: `dbtype_def.h`·도메인 전방선언·연산자 enum 만) | — |
