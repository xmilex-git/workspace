# cpp-perf-rules 관점 — 폴드 핫패스 규칙 ID 재검토와 측정 계획 (wf218)

- 결정 티켓: [브레인스토밍 2: cpp-perf-rules 규칙 ID 렌즈로 폴드 핫패스 재검토 — 후보 발굴·측정 계획](https://github.com/xmilex-git/workspace/issues/218)
- 입력: [브레인스토밍 1 결정](optimization-brainstorm.md) D1~D9, [전체 판정](candidate-disposition.md), [invalidation 계약](invalidation-policy.md), [#177 YCSB 게이트 프로파일](https://github.com/xmilex-git/workspace/issues/177), 규칙집 `cpp-perf-rules`(규칙 ID는 그 문서 기준).
- 코드 기준: `xmilex-git/cubrid cas-merge` PR head `702d62c6a`(2026-09-08). 사실 확인은 `d1cf63b06` 트리와 설치본 `11.5.0.2812-30937a9`에서 수행했고, 그 사이 커밋은 여기서 다루는 핫패스를 바꾸지 않았다.
- 비교 기준: upstream develop `e374c7a24`.
- 이 문서는 후보의 **채택 여부를 바꾸지 않는다**(#216 D1~D9 유지). 각 후보에 규칙 ID·폴드 신규 비용의 실체·op당 기대 효과·측정 방법·게이트 여부를 붙이고, 새로 드러난 후보와 "후보 아님" 판정을 기록한다. 속도 %는 실측 인용에만 쓴다(MEAS-01).

## 0. 규칙집 사용 규약을 이 노력에 적용한 결과

| 규약 | 적용 |
|---|---|
| 측정 없는 최적화 제안 금지(프로토콜 1, MEAS-01) | 기대 효과는 **op당 제거되는 연산·바이트·호출 수**로만 쓴다. %는 #177 프로파일과 wf218 귀속 프로브의 실측만 인용한다. |
| 핫/콜드 분리(프로토콜 2) | 핫 = 세션 스레드의 요청 루프(`cas_process_request`→`ux_execute`/`ux_fetch`/`ux_auto_commit`)와 그 아래 실행기·락·커밋. 콜드 = 접속 수립·SSL·conf 로드·세션 종료. 콜드는 **메모리 고정항**과 **접속 폭주 시 직렬화**로만 평가한다. |
| 우선순위 결정 절차(§19) | 폴드가 남긴 축은 3(메모리 접근·복사), 4(할당), 4.5(컴파일러를 막는 TLS·전역), 6(동기화)이다. 1(알고리즘)·2(데이터량)은 폴드 무관. |
| 두 빌드는 두 ELF(프로토콜 12, CC-08) | 엔진 전체가 `libcubrid.so` 하나에 있어 **모든** 최적화 PR이 같은 DSO의 심볼 배치를 바꾼다. 핫루프 delta를 주장하는 PR은 Appendix E 위상 diff를 먼저 통과한다(MEAS-08). |
| 약한 메모리 모델(프로토콜 8) | fastpath 락·공유 준비 객체의 세대 교체는 acquire/release로 표현하고 x86 TSO에 의존하지 않는다(COH-10). |

## 1. 게이트·측정 규약 결정 (사용자 확정, 2026-09-09)

| ID | 결정 | 근거 규칙 |
|---|---|---|
| G1 | 최적화 구현 PR의 공식 게이트 = YCSB **C×3·A×3 median + MAD**, p50/p99 병기, Appendix E hot-symbol 위상 diff. 단일 실행 게이트는 스모크로 격하. | MEAS-04/07/08 |
| G2 | 게이트 conf = #125 conf + **체크포인트-조용**(`checkpoint_every_size=256G`, `checkpoint_interval=120min`). 서버 이벤트 로그의 체크포인트 0회가 레그 유효 조건. p99가 기준선 중앙값 대비 **+10% 초과면 귀속 필수 hold**(자동 fail 아님), 귀속 실패 시 fail. 비교 대상은 이제 #125가 아니라 cas-merge 자기 자신이므로 conf를 통제 변수로 바꾼다. 체크포인트 페이싱은 상류 후보로 분리. | MEAS-07, PAR-16 |
| G3 | TLS `initial-exec`는 구조 작업과 독립된 **선행 quick-win**. 미니 게이트: `__tls_get_addr` 지분→0 확인 + G1. | GLOB-05 |
| G4 | 값당 hat/브래킷 분기와 래퍼당 `enter/exit_server`는 **T4/P6에 흡수**. 커널 특수화는 T4 이후 `perf annotate`에 잔존 분기 0.5% 이상일 때만. | BR-04/A59, CC-05 |
| G5 | R 계열(접속당 스레드·TLS 블록·출력 버퍼)은 **연결 100/1,000 2점 sweep**, 1차 지표 = 연결당 RSS/PSS 기울기. 1,000 레그만 `max_clients=1100`. | MEM-05, PAR-13 |
| G6 | 클래스 IS 락 경합은 **PG식 fastpath** 방향(retention+revoke 기각 — DDL 대기 의미론·기아 보존 계약을 건드림). | PAR-10, COH-12 |
| G7 | 폴드 무관 상류급 항목은 "상류 후보"로 표기하고 폴드 성과에 합산하지 않는다. | MEAS-06(원인 분리) |
| G8 | PGO는 기록만. 다중 워크로드 프로파일과 별도 제품 variant가 선결. | CC-02, CC-09 2단 |
| G9 | prepare-churn 진단 레그(게이트 아님). | MEAS-04(대표 워크로드) |
| G10 | 현 head 귀속 프로브는 이 티켓에서 Sonnet 워커가 수행([스펙](https://github.com/xmilex-git/workspace/issues/218#issuecomment-5594773683)). | MEAS-02 |

## 2. 사실 — 폴드가 만든 비용의 실체 (읽기 전용 조사, 2026-09-09)

| 항목 | 사실 | 출처 |
|---|---|---|
| 링크 구조 | `cub_server`는 `server.c` 한 파일 실행 파일(PIE, BIND_NOW), 엔진 전체(client-half·CAS speaker·csql body 포함)가 `libcubrid.so`(-O2 -finline-functions -fPIC, GCC 8.5, BFD ld). LTO·PGO·`-march`·`-falign-functions`·`-ftls-model` 없음. | `util/CMakeLists.txt:79-92`, `cubrid/CMakeLists.txt:906-916`, `CMakeLists.txt:218-244,653-655` |
| TLS 모델 | `tls_model` 속성 0건 → `-fPIC` .so 기본값 **general-dynamic**. `.text`의 `call __tls_get_addr` develop 231 → cas-merge **5,463**. TLS 세그먼트 develop 456B → 설치본 **245,720B(≈240KiB)**, `.tbss` 243,832B는 **모든 서버 스레드** 생성 시 zero-fill. | `readelf -l libcubrid.so.11.5`, 빌드 트리 objdump 계수 |
| TLS 큰 항목 | `cas_log.c:67-68` `sql_log_buffer` 163,840B + `cas_log_buffer` 8,192B(=168KiB, `SQL_LOG_BUFFER_SIZE`는 `cur_sql_log_mode != NONE`일 때만 사용), `:91` 경로 버퍼 4,096×2, `plan_file_name` 1,054. 파서 TLS 배열(`csql_grammar.y`, `g_msg[1024]`). `cursor.c:1200` `static thread_local QFILE_LIST_ID empty_list_id`. | agent 조사 §5·§10 |
| 세션 컨텍스트 | `client_session_context` 힙 19,872B/연결. 접근자 `csc_current()` 32곳·`au_ctx()` 38곳·`csc_bracket_is_active()` 52곳(`object_domain.c` 11, `object_primitive.c` 3, `memory_alloc.c` `DB_PRIVATE_IS_CLIENT_HALF` 3). 실행기·스캔 파일에 직접 호출 0. | `client_session_context.cpp:35,53,91`, `authenticate.c:103` |
| **진짜 핫 TLS 지점** | `quick_fit.c:43` `#define ws_Heap_id (csc_ws ()->heap_id)` — SERVER_MODE의 **모든 `db_ws_alloc`/`db_ws_free`/`db_ws_realloc`이 `csc_current()`를 경유**. `:45`는 `DB_IS_UTILITY_THREAD()`를 false로 고정. | agent 조사 §4 |
| VALUE_IS_CLIENT_HALF | 정의 1곳·사용 4곳, 전부 `method_struct_value.cpp`(Java SP 값 pack/unpack). 스캔·비교 경로 0곳. 엔진 쪽 유일한 release 분기는 `object_primitive.c:5206` `mr_data_writeval_object`의 `db_on_server && !csc_bracket_is_active()`. | `method_struct_value.cpp:42,227,363,516,701` |
| 브래킷 뮤텍스 | `csc_activate`(`bracket_mutex`)는 **연결당 1회**(`driver_session.cpp:583`, 해제 `:843`); 요청 루프 `:489-495`→`cas_process_request`는 브래킷·뮤텍스를 잡지 않음. 비경합. | agent 조사 §6 |
| XASL_NODE | `sizeof` 1,320 → **1,328(+8B)**. 이관 fog의 "+16B"는 정정. `projected_size`/`cardinality` 무조건화가 tail padding에 흡수. | `xasl.h` diff 6줄 |
| 스레드 모델 | 접속마다 `std::thread(driver_session_run).detach()`, blocking `recv`, 스택 크기 미지정(glibc 기본), epoll·풀 없음. TCP_NODELAY는 서버가 아니라 **브로커가 accept 직후 설정**(`broker.c:867`)하고 fd가 옵션을 들고 넘어옴. | `adoption.cpp:568,697`, `driver_session.cpp:162,531-534` |
| AREA | 프로세스 공유 AREA 7개(`Value_area`·`tp_Domain_area`·`Set_*`·`Objlist_area`), 세션별 없음. `area_mutex`는 블록 추가 시만(`area_alloc.c:420`); `area_free`는 락 없이 `area_find_block` 포인터 체이싱(`:717`). `LF_BITMAP`의 `entry_count_in_use`와 `start_idx`가 **한 캐시라인, 패딩 없음**. | `area_alloc.c:72,198-203,526` |
| 세션 도메인 리스트 | 타입별 침입형 리스트 헤드 배열(`object_domain.c:1902`), 내용 기반 라우팅(`:1943`, MOP 포함 시만 세션). interning(`tp_domain_cache :3085`)마다 TLS 1회 + MOP 재귀 스캔, 프로세스 전역 `tp_domain_cache_lock`(`:3150`) 유지. `tp_domain_match`에서는 리스트를 걷지 않음. | agent 조사 §9 |
| 결과 복사 | 결과당 `qmgr_attach_first_page_copy`(`network_interface_cl.c:201-240`, `malloc(DB_PAGESIZE)`+16KiB memcpy) → `cursor_copy_list_id`(`cursor.c:107-143`, 구조체 memcpy + `domp` 복사 + **또 한 번 16KiB memcpy**) + `buffer_area` 16KiB malloc(`:1250`). 즉 **결과 하나에 ≈32KiB memcpy + ≈48KiB malloc, 행 수 무관**. `pt_new_query_result_descriptor`(`query_result.c:1075`) 자체는 복사 없음. | agent 조사 §10 |
| 요청 스크래치 | 요청마다 body `malloc` + 인자마다 `realloc(argv)`(`cas_dispatch.c:541-570`, `cas_network.c:393-440`). | runtime-shell R7 |
| 서버 선존 — 커밋 | `logtb_tran_clear_update_stats`(`log_tran_table.c:3443`)는 NULL만 검사, 비어 있어도 `mht_clear`가 101 버킷 전부 기록(`memory_hash.c:1262`). 커밋당 **4회**(`:4365`·`:1644` × 해시 2개) + 무가드 전체 순회 2회(`:4346`, `:4360`). | agent 조사 §2a |
| 서버 선존 — classrepr | 버킷 뮤텍스 + 엔트리 뮤텍스(trylock→block)(`heap_file.c:2026,2032,2049`), `heap_attrinfo_start`가 문장마다 경유(`:9711`). 전역 싱글턴은 LRU·free 리스트 뮤텍스만. | agent 조사 §2b |
| 서버 선존 — 락 | `LK_RES::res_mutex`(`lock_manager.c:666`), `find_or_insert`가 함께 잠금(`:3651`). 클래스 락 hash 우회 `lock_find_class_entry`(`:3636-3644,1751`)는 **같은 트랜잭션 안의 재요청**만 도움(모드 무관). autocommit은 문장마다 `lock_unlock_all`→다음 문장이 다시 hash+`res_mutex`. IS 전용 fastpath·retention 없음. 100세션이 `usertable` 클래스 엔트리 하나를 공유. | agent 조사 §2c |
| 브로커 핸드오프 | dispatch **단일 스레드**(`broker.c:603`), 매니저 전역 `config_mutex`를 **왕복 내내** 보유(`broker_direct.cpp:1251-1293`), 채널 `request_mutex` + 5초 타임아웃 reply 대기(`:430,527`), admission은 30ms `sleep_for` 폴링(`:1236-1243`), DB당 AF_UNIX 채널 1개. YCSB는 시작 시 100회만 발생(재접속 0: `rcTime`은 altHosts failback 타이머). | agent 조사 §3·§4 |
| 체크포인트 | `checkpoint_every_size` 100,000페이지, `checkpoint_interval` 6분 기본 → A 레그(688초) 안에서 반드시 발화. #177: 버스트 1,069회, 구간 처리량 −89%. | `system_parameter.c:1425,1447` |
| statdump | 카운터는 `pstat_Global.n_watchers > 0`일 때만 누적(`perf_monitor.h:1455`), `-c`는 interval 0이면 강제. "전부 0"은 결함이 아니라 워처 부착 직후 출력이라는 의미. | agent 조사 §2e |
| 호스트 | 2소켓 NUMA(Xeon 4216, 32 CPU, node0 128GB), 세션 스레드 비고정. | `numactl --hardware` |

## 3. 후보별 규칙 렌즈

판정 열: **흡수**(채택된 구조 작업에 규칙 ID만 부여), **독립**(별도 미니 게이트로 선행 가능), **상류**(폴드 무관·상류 보고 후보), **측정 후**(프로브가 판별자), **후보 아님**(사실로 소거).

### 3.1 폴드가 새로 만든 비용

| ID | 후보 | 규칙 ID | 폴드 비용의 실체 | op당 기대 효과 | 측정(MEAS) | 게이트 | 판정 |
|---|---|---|---|---|---|---|---|
| N1 | TLS `initial-exec` 전환 | GLOB-05/A24, GLOB-08, COSTS(GD 20–50 vs IE 1–3 cycles) | 5,463개 `__tls_get_addr` 호출 지점, #177 self 1.0–1.4% | TLS 접근당 −(20~50)+(1~3) cycles, 접근 수/op는 프로브 L2 호출자 분해로 확정. `__tls_get_addr` self는 0으로 수렴하되 호출자의 `%fs` 상대 load는 남으므로 벽시계 이득 상한 = 그 지분 | L2 `__tls_get_addr` 호출자 분해, L3 IPC, G1 벽시계 | **필수** + **레이아웃 게이트 필수**(전 TU 코드젠 변경) | **독립(G3)**. 수단: `cubrid` 타깃에 `-ftls-model=initial-exec`. 전제: `libcubrid.so`는 DT_NEEDED로만 로드(dlopen 0건 — 구현 PR에서 `grep dlopen` + `ldd` 재확인). 좁은 대안: `db_on_server`·`tl_Csc_active`·`CAS_TLS` 변수에만 `__attribute__((tls_model("initial-exec")))`. 실패 모드: 어떤 프로세스가 `libcubrid.so`를 dlopen하면 "cannot allocate memory in static TLS block" |
| N2 | `ws_Heap_id`의 alloc/free당 `csc_current()` | GLOB-05(포인터 캐시), CC-05/A60(매 호출 out-of-line), BR-04 | `quick_fit.c:43` — 워크스페이스 alloc/free마다 TLS read + 호출 | alloc/free당 −1 TLS 접근 −1 호출. 횟수/op는 L2 `db_ws_alloc`/`db_ws_free` children | L2 | G1 | **흡수(T4·S9)**. T4 typed facade가 요청 최외곽에서 `csc`를 한 번 잡아 heap id를 인자로 전달. N1 이후에도 남는 항목이라 T4의 첫 구체 대상으로 명시 |
| N3 | hat/브래킷 값당 분기 | BR-04/A59, GLOB-05 | `VALUE_IS_CLIENT_HALF` 4곳(Java SP 직렬화만), `csc_bracket_is_active` 52곳(도메인 11·값 3·할당 3), `object_primitive.c:5206` 1곳 | 스캔 핫패스 노출 0건 확인 → op당 효과 없음. Java SP 값당 −1 TLS read | L2에 `csc_bracket_is_active` 등장 여부 | 없음 | **흡수(T4/P6, G4)**. 특수화 불요 |
| N4 | `enter_server`/`exit_server` 래퍼 hop(T4) | GLOB-01/05, CC-05, BR-08(er_stack push/pop) | `network_interface_cl.c:138-197` 래퍼마다 `db_on_server++`·er_stack push·thread lookup | 래퍼 호출 W/op × (TLS rw 2 + 호출 3). W는 L2 children | L2 `enter_server`/`exit_server` children | G1 | **흡수(T4 채택)** |
| N5 | 스레드당 TLS 블록 240KiB zero-fill | MEM-05(핫/콜드 동거), ALLOC-05 역방향, GLOB-05 | `.tbss` 243,832B — 세션 스레드뿐 아니라 **모든** 서버 스레드에 생성 시 memset. SQL_LOG=OFF에서도 168KiB 로그 버퍼 상주 | 스레드당 −(168KiB+8KiB+8KiB+…) RSS. 1,000연결 ≈ −240MiB. 정확한 상주량은 L5/L5′ | L5/L5′ smaps 기울기 | **G5 sweep** | **흡수(R2·R9 채택)**. R2 수단: `cur_sql_log_mode != NONE` 시 lazy malloc + 종료 시 반환; R9: 파서 TLS 배열 → 프로세스 불변 정의 + parse별 scratch |
| N6 | 접속당 스레드 + 80KiB 출력 버퍼(R1·R3) | PAR-13(스레드>코어), PAR-16(blocking recv = 커널 대기 선택), MEM-05, ALLOC-02/05 | detached 스레드·8MiB 스택 예약·80KiB high-water 버퍼/연결 | 연결당 고정항 감소; CPU는 요청당 wakeup 1회가 어느 모델에서도 남아 이득 미주장 | L5/L5′ 기울기, L5′ p99 | **G5 sweep** | **흡수(R1 후속·R3 채택)**. R1 전제: TLS 세션 상태의 명시적 소유권 이전(PAR-08) — 풀 전환 시 세션당 TLS를 요청 컨텍스트 객체로 옮기지 않으면 상태가 섞임 |
| N7 | 요청 body malloc + argv realloc(R7) | ALLOC-01/A01, ALLOC-02, PAR-11(#177 malloc 6.7–9.1%) | 요청당 malloc 1 + realloc argc회 + free 2 | 요청당 −(1+argc) malloc/realloc | L2 `malloc` 호출자 분해(`cas_dispatch`·`cas_network` 지분) | G1 | **흡수(R7 채택)**. 수단: inline argv[16]+overflow, 요청 body는 세션 소유 bounded 버퍼(다음 요청까지 소비 완료 계약) |
| N8 | 바인드 전량 clone(T1) | ALLOC-01, MEM-01, COH-12 | execute당 N개 DB_VALUE alloc/init/clone/clear | execute당 −N clone −N clear −1 배열 alloc(OBJECT만 OID 정규화) | L2 `db_value_clone` 지분 | G1 | **흡수(T1 채택)** |
| N9 | 결과 첫 페이지 2단 복사(T2·T3) | MEM-01/07, ALLOC-01, COH-12(복사→소유권 이전), MEAS-07(고정비는 산포를 키움) | 결과당 16KiB memcpy ×2 + malloc ≈48KiB, 행 수 무관. #177 `__memmove` 3.7–4.1% | 결과당 −16KiB memcpy(옵션 A: cursor가 페이지 소유권 move) 또는 −32KiB(옵션 B: query 수명 pin) −2~3 malloc. C 147k ops/s 기준 memcpy 대역 ≈ 4.7GB/s 소거 후보(계수에서 유도, 속도 주장 아님) | L2 `memmove` 호출자(`cursor_copy_list_id`·`qmgr_attach_first_page_copy`) | G1 | **흡수(T2·T3 채택)**. 불변식: generated-key autocommit read-back 계약(`network_interface_cl.c:201-209`) |
| N10 | XASL_NODE 크기 | MEM-02 | +8B(1,320→1,328, 이미 21 캐시라인) | 없음 | — | — | **후보 아님**(fog "+16B" 정정 기록) |
| N11 | 요청 디스패치 브래킷 뮤텍스 | PAR-05/10 | 연결당 1회, 비경합 | 없음 | — | — | **후보 아님** |
| N12 | AREA `LF_BITMAP` false sharing·`area_free` 체이싱 | MEM-03/COH-04(카운터 2개 한 라인), MEM-01, PAR-11 | 프로세스 공유 7 AREA; #177 top-25에 부재 | 경합 시 라인 왕복 −1/alloc; 현재 근거 없음 | **L4 c2c HITM**이 판별자 | — | **측정 후**(S9 현행 유지). c2c에 `area_*`/`lf_bitmap` 라인이 없으면 종결 |
| N13 | 세션 도메인 리스트 | GLOB-05, MEM-01 | interning당 TLS 1 + MOP 재귀 스캔; match 경로 무관 | 미미 | L2에 `tp_domain_cache` 등장 여부 | — | **후보 아님**(S4 현행 유지) |
| N14 | 세션 컨텍스트 19,872B + MOP 테이블·LEA 힙 고정항(S2·S9) | MEM-05, ALLOC-03/05 | 연결당 고정항 | 연결당 −(빈 테이블 lazy) | L5 S2 기울기 | **G5 sweep** | **흡수(S2·S9 채택)** |

### 3.2 폴드가 드러냈지만 서버 선존인 비용 (G7: 상류 후보, 폴드 성과에 미합산)

| ID | 후보 | 규칙 ID | 실체 | op당 기대 효과 | 측정 | 판정 |
|---|---|---|---|---|---|---|
| U1 | 클래스 IS 락 fastpath | PAR-10(read-mostly 공유 뮤텍스 회피), COH-12(트랜잭션 로컬 소유), GLOB-09(강한 락 카운터 샤딩), COH-10 | 문장마다 `find_or_insert`+`res_mutex`; #177 뮤텍스 self 1.2%/0.97%, futex 실대기 1위 | 문장당 −1 공유 hash 탐색 −2 `res_mutex`(획득·`lock_unlock_all`) | L2 `lock_*`·`__pthread_mutex_lock` 호출자, L4 `lk_res` HITM, L3 IPC | **채택(#216 후속 구현, G6 방향 확정)**. 설계 스케치: 트랜잭션 `tran_lock`에 약한 클래스 락(IS/IX) fastpath 슬롯 N개; 클래스별 "강한 락 대기·보유 카운터"(샤딩·relaxed 읽기, 강한 요청자만 acquire/release)를 fastpath 진입 전 확인; X/SIX/SCH-M 요청자는 카운터를 올린 뒤 기존 fastpath 엔트리를 `res_mutex` 아래 공유 테이블로 이전 후 정상 경로. 문장별 획득·반납 의미론과 DDL 대기 의미론 유지, 기아 없음. 실패 모드: 이전 중 race → 강한 요청자 측 재검사 루프 |
| U2 | read-only 커밋의 `mht_clear` 빈 가드 | CC-05/A60(대부분 no-op인 무조건 호출), BR-07 | 커밋당 101버킷 ×4 + 순회 2; #177 1.1–1.4% | 커밋당 −404 포인터 store −2 순회(갱신 통계 없을 때) | L2 `mht_clear`·`logtb_complete_mvcc` | **상류 후보**. `nentries==0` 단락 또는 dirty 플래그 |
| U3 | classrepr 버킷·엔트리 뮤텍스(문장당 `heap_attrinfo_start`) | PAR-10(COW/epoch pin), COSTS(비경합 뮤텍스 20–50) | #177 0.56–0.85% | 문장당 −2 뮤텍스(버킷+엔트리) | L2 호출자 분해 | **상류 후보** |
| U4 | 체크포인트 flush 버스트 × 포그라운드 래치 | PAR-16(페이싱), MEAS-07 | A p99 +40%의 주범, 처리량 증가가 트리거를 앞당김 | 게이트에서는 G2로 격리; 제품에서는 페이싱 파라미터(`checkpoint_sleep_msecs` 등) 튠 | G2 레그 유효성 검사 | **상류 후보** + **게이트 통제 변수** |
| U5 | qmgr/qfile 뮤텍스 | PAR-10 | #177 0.51–0.74% | — | L2 | **상류 후보**(기록) |
| U6 | `tp_domain_cache_lock` 전역 뮤텍스 | PAR-10 | interning마다 프로세스 전역 뮤텍스 | interning 빈도/op는 L2 | L2 | **측정 후**(선존) |

### 3.3 새로 드러난 후보

| ID | 후보 | 규칙 ID | 실체 | 기대 효과 | 측정 | 판정 |
|---|---|---|---|---|---|---|
| X1 | 브로커 핸드오프 파이프라이닝 | **PAR-05/A15**(락을 잡은 채 I/O·왕복), PAR-16/A71(30ms sleep 폴링의 지연 비용 미기술), SYS-01 | dispatch 단일 스레드 + 전역 `config_mutex`를 5초 타임아웃 왕복 내내 보유 + 채널 `request_mutex`. YCSB steady에는 미노출(100회/시작), 접속 폭주(풀 재충전·failover)에서 직렬화 | 접속 N개 수립 시간 ≈ N×RTT 순차 → 요청 id 다중 in-flight로 병렬화; `config_mutex`는 스냅숏 복사 구간으로 축소 | **L8** 순차 vs 16스레드 접속 지연 | **신규·콜드 후속 후보**. 채택 여부는 L8 수치와 운영 요구(접속 폭주 시나리오)로 결정 — 이 티켓은 기록만 |
| X2 | 커밋당 `log_commit` 고정비 | COSTS(syscall·fsync), SYS-01 | #177 children 7.4%(autocommit) — 선존 | — | L2 | **기록만**(폴드 무관, 상류 성능 트랙) |
| X3 | NUMA 배치 | PAR-09(first-touch), COH-02 | 2소켓 호스트에서 데이터 버퍼·AREA는 부트 스레드가 first-touch → node0 편중 가능; 세션 스레드 비고정 | 원격 노드 접근 1.5–2× | L5 `numastat -p` | **측정 후**. 폴드 무관이나 게이트 산포 원인 후보 |

### 3.4 안티패턴 카탈로그 매핑(발견 즉시 표기 규약)

| 코드 | 위치 | 대응 후보 |
|---|---|---|
| A24 반복 TLS 조회 | `quick_fit.c:43` alloc/free 경로 | N2 |
| A60 대부분 no-op인 무조건 호출 | `log_tran_table.c:3443` `mht_clear` ×4/commit | U2 |
| A01 핫루프 malloc | `cas_dispatch.c:541-570`, `cursor.c:1250`, `network_interface_cl.c:201-240` | N7·N9 |
| A15 락 아래 I/O | `broker_direct.cpp:1251-1293` `config_mutex` 왕복 보유 | X1 |
| A71 CPU 예산 없는 폴링 대기 | `broker_direct.cpp:1236-1243` 30ms sleep 폴링 | X1 |
| A72 NODELAY 결정 미기술 | `driver_session.cpp` 입양 fd — 브로커 `broker.c:867` 의존이 코드에 미기술 | 주석 1줄(후보 아님) |
| A80/A81 레이아웃 게이트 생략 | 향후 모든 최적화 PR | G1 |

## 4. 측정 계획 — 구현 노력의 진입·판정 계측

| 후보군 | 1차 지표 | 도구·레그 | 판정 기준 |
|---|---|---|---|
| N1 TLS | `__tls_get_addr` self%, IPC, C/A median | `perf record -e cycles --call-graph dwarf`, `perf stat`, G1 | self→0, median 비악화, 위상 diff 통과 |
| N2·N4 T4 | `csc_current`/`enter_server` children, 호출 수/op | L2 children, uprobe 카운트(선택) | 호출 수/op 감소분 = 설계 계수와 일치 |
| N5·N6·N14 R/S 고정항 | 연결당 RSS/PSS 기울기(100·1,000), 스레드 수 | L5/L5′ smaps_rollup ×3, `numastat` | 기울기 감소 = 설계 계수(예: R2 −168KiB/연결) |
| N7·N8·N9 할당·복사 | malloc 호출 수/op, memcpy 바이트/op | L2 `malloc`·`memmove` 호출자, `perf stat -e` 없음 → 카운터는 perfmon 샤드(GLOB-09) 또는 debug 계수 | 계수 감소 + median 비악화 + p99 산포(MAD) 감소 |
| U1 락 | `lock_*`·`__pthread_mutex_lock` self, futex 대기, `lk_res` HITM | L2·L4, `perf c2c` | HITM 라인에서 `lk_res` 소거, futex 대기 감소 |
| U2 mht_clear | `mht_clear` self | L2 | 0 수렴 |
| 게이트 공통 | C×3·A×3 median+MAD, p50/p99, 체크포인트 0회, 위상 diff | G1·G2 | p99 +10% 초과 → 귀속 hold |
| 진단 | prepare-churn 처리량·컴파일 경로 지분 | L6 | P1–P6 기대 효과 산정 입력(게이트 아님) |

TMA L1은 프로세스·user-only 카운터로 수동 산출한다(Cascade Lake, `stalled-cycles-*` 미지원): Retiring = `uops_retired.retire_slots`/4c, Frontend = `idq_uops_not_delivered.core`/4c, BadSpec = (`uops_issued.any` − `retire_slots` + 4·`int_misc.recovery_cycles`)/4c, Backend = 나머지. 권한이 열리면 `perf stat --topdown -a`로 교차 확인한다(MEAS-08 보고 규칙).

## 5. 귀속 프로브 결과 (wf218, 현 head) — 후보별 계수 확정

전문·원자료 출처: [cas-merge 귀속 프로브 2026-09](../research/cas-merge-perf-probe-2026-09.md). 등급 INDICATIVE, 전 레그 체크포인트 0회(G2 conf 유효), A READ p99 6,067µs(MAD 374) — #177의 11,279µs 대비 꼬리 오염 제거 확인.

| 후보 | 프로브 실측 | 3절 판정에 미치는 영향 |
|---|---|---|
| N1 TLS | `__tls_get_addr` self **1.85%(C) / 1.39%(A)** — #177(1.0–1.4%)보다 높음. 호출자는 `csc_current` 0.31% 외 파편화 | 독립 quick-win 유지·강화. 미니 게이트 기준 = 이 self가 0으로 |
| N2 alloc/free TLS | 파편화 구간에 잠김(0.3% 미만/지점) | T4 첫 대상 유지; 계수는 `--percent-limit 0.1` 재분해로 |
| N9 페이지 복사 | `__memmove` 4.52%의 86% = `cursor_copy_list_id` 2.00 + `qmgr_attach_first_page_copy` 1.90; children **5.73%**(C) | T2·T3 기대 효과 상한 ≈ C 사이클 5~6% (게이트로 확정) |
| P3 메타데이터 | `malloc` 4.09% 중 **`db_cp_query_type` 1.18%**(execute마다 `DB_QUERY_TYPE` 복사) | P3에 실측 근거 추가 — 1순위 근거 강화 |
| N7 요청 스크래치 | malloc 파편화 구간 | 계수 미확정(재분해 필요) |
| U1 클래스 IS 락 | `lock_internal_perform_lock_object` 2.95%(C), 그중 **`lock_find_my_holder_entry` 1.97%**(트랜잭션 보유 목록 선형 탐색); A에서 `xcache_find_xasl_id_for_execute`→`lock_object` 0.96%. `__pthread_mutex_lock` 귀속: `lock_unlock_all` 0.39~0.50 | fastpath 설계에 **보유 목록 O(n) 탐색 제거**(슬롯 배열/해시) 요건 추가. `lk_res` 캐시라인 HITM은 상위 20에 없음 → 경합 실체는 뮤텍스 대기+탐색 |
| U2 mht_clear | **1.32%(C) / 1.04%(A)**, 전부 `logtb_tran_clear_update_stats`←`log_commit_local` | 상류 후보 계수 확정 |
| U3 classrepr | `heap_classrepr_get/free` 뮤텍스 0.54~1.17%, **c2c 라인 #1 HITM**(엔트리 뮤텍스+필드) | 상류 후보, COH-02 확증 |
| N12 AREA | c2c 상위 20에 `area_*`/`LF_BITMAP` 없음 | **종결 방향**(S9 현행 유지). 필요 시 재측정만 |
| N5·N6·N14 연결 고정항 | 스레드 **+1/연결**, 연결 종료 시 반환 **315 kB/연결**(1,000), prepare·execute 증분 354~429 kB, 유휴 추정 512 kB(기준선 편차) | R2/R3/S2/S9 기대 효과 = 이 315~512 kB 안의 비중; 1,000연결 ≈ 315~512 MB |
| X1 핸드오프 직렬화 | 16스레드 병렬이 처리율 1.3~1.8배·연결당 p50 7~9배(≈1 ms 단일 서버), p90~p99 **≈100 ms 계단** | 콜드 후속 후보 유지, 계단 원인 후속 |
| **신규 F1: frontend-bound** | TMA L1 **FE 44~56%**, retiring 12~16%, IPC 0.58/0.45; DSB→MITE 페널티 1%뿐 | I-cache/iTLB/resteer 축 신설 → CC-08 레이아웃 게이트의 중요도 상승, BR-08/CC-05 콜드 코드 분리·`-finline-functions` 재검토를 측정 후보로 추가(MEAS-02 3단계: `icache_64b.iftag_stall`, `itlb_misses.walk_pending`, `frontend_retired.*`) |
| **신규 F2: xcache 엔트리 라인 HITM** | c2c 라인 #3: 한 엔트리의 SHA1/size/fix 필드에 43~56% HITM | P6 공유 준비 객체 설계 요건: 불변 키와 가변 카운터를 **다른 캐시라인**에(COH-04), fix count는 세션 로컬 ref 또는 샤딩(GLOB-09) |
| **신규 F3: QMGR 질의 엔트리 라인 HITM** | c2c 라인 #0: 질의 엔트리 상태 필드(0x0/0x20)+뮤텍스(0x38) 왕복 | 선존. 전역 풀 재사용이 코어 간 transfer를 만듦 → 스레드 로컬 엔트리 캐시(COH-12) 상류 후보 |
| 게이트 도구 | statdump는 워처 부착 후에만 누적(`-i` 모드 사용) | 측정 계획 4절에 반영 |
| NUMA | 부트 구조 node1 편중(448/2,900 MB), 실행 중 45/55 | 산포 원인 후보로만 기록 |

미측정·편차(프로브 문서 9절): dwarf 샘플 유실로 self%는 근사, C 커널 샘플 무효, 1100-conf 부트 기준선 없음, L6 생략, 100 ms 계단 원인 미확정.

## 6. 범위 밖·미확인

- 후보 채택/기각은 #216 결정을 따르며 이 문서는 바꾸지 않았다. X1·X3은 신규 발견으로 기록만 했고 채택 결정은 후속이다.
- 사실 조사는 정적 읽기와 ELF 검사다. `__tls_get_addr` 5,463은 빌드 트리 `objdump` 계수이고 설치본 TLS 세그먼트는 `readelf` 값이라 트리가 다르다(둘 다 폴드 빌드).
- `libcubrid.so`가 어디서도 dlopen되지 않는다는 전제는 N1 구현 PR에서 재확인해야 한다(`csql -S`는 `libcubridsa` dlopen — 별개 라이브러리).
- PGO(G8)·LTO·`-march`는 기록만. 적용 시 CC-01/02 규칙대로 별도 variant·다중 워크로드 프로파일이 선결이다.
