# PL/CSQL·JavaSP의 wire 우회 — 서버 세션 컨텍스트에서 직접 재호출 가능성 (사실 조사)

- 티켓: [#215](https://github.com/xmilex-git/workspace/issues/215) (Part of #207), research/AFK
- 기준 코드: cas-merge tip `/home/cubrid/dev/worktrees/wf143-gate` @ `7117c8a66` (== xmilex/cas-merge tip). 비교: upstream develop `/home/cubrid/dev/cubrid` @ `6dbf6d92f`.
- 선행 조사 인용: `docs/research/cas-merge-final-gate-and-defect-log-1.md` (A7, 결함 1·7a·8·17).
- 아래 `path:line`은 모두 cas-merge 트리 기준. Java는 `pl_engine/pl_server/src/main/java/com/cubrid/` 이하 상대경로.

## 0. 요약표

| 질문 | 답 (근거는 본문 절 번호) |
|---|---|
| JVM(cub_pl)↔cub_server 사이는 "CAS wire"인가? | **아니다.** JVM 쪽 server-side JDBC(`jdbc:default:connection`)는 CAS 프로토콜(`cas_execute.c`/`net_buf`)을 전혀 말하지 않는다. `cubpacking` packer 기반의 자체 콜백 프로토콜(`METHOD_CALLBACK_*`, `sp_constants.hpp:205-247`)을 `SP_CODE_INTERNAL_JDBC`(0x08) 프레임으로 소켓에 실어 보낸다 (§1.2). |
| 폴드가 바꾼 것 | 서버 스레드 → (레거시: CSS wire → CAS 프로세스) 구간이 **같은 스레드의 in-process `method_dispatch()`** 로 종단됨 (`network_callback_sr.cpp:38-56, 81-97`). 핸들 캐시·runtime_args·er 격리 floor가 세션(csc) 소유로 이동 (§2). |
| 폴드 후 남은 hop | **JVM↔서버 소켓 왕복은 그대로**. `pl_executor.cpp`·`pl_execution_stack_context.*`·`pl_connection.*`·`pl_comm.*`·`pl_query_cursor.*`와 `pl_engine/` Java 트리 전부가 upstream develop과 바이트 동일 (§2.3). |
| 프로시저 안 `SELECT` 1회의 JVM 왕복 수 | prepare 1 + execute 1 + fetch ⌈rows/1000⌉(최소 1) = **최소 3회** 소켓 왕복. 첫 연결 시 GET_DB_PARAMETER +1. CHANGE_RIGHTS×2·METHOD_REQUEST_END는 in-process (§1.4). |
| "서버가 폴드된 CAS 화자(`ux_prepare/ux_execute/ux_fetch`)를 직접 호출"의 의미 | 콜백 핸들러(`method_callback.cpp`)와 CAS 화자(`cas_execute.c`)는 **같은 스레드·같은 csc 위에서 이미 같은 client-half API(`db_open_buffer`→`db_compile_statement`→`db_execute_and_keep_statement`)에 도달**하는 두 개의 병렬 프론트엔드다. `ux_*`는 `T_NET_BUF`에 **CAS wire 포맷**으로 쓰기 때문에 JVM이 읽는 packer 포맷과 맞지 않는다. 바꿔 끼우면 절약은 없고 변환 계층만 추가된다 (§3). |
| 서버↔client-half 구간에서 실제로 남은 비용 | 같은 프로세스 안의 packer pack/unpack(memcpy 급). 응답 블록은 JVM으로 verbatim 전달되므로 그 pack은 어차피 필요 (§3.2). |
| PL/CSQL 정적 SQL은 서버측 컴파일인가? | **컴파일 시점에는 의미 분석만** 서버가 한다(`GET_SQL_SEMANTICS`, `PREPARE_STATIC_SQL`). 결과는 재작성된 SQL **텍스트**로 생성 Java 클래스에 박히고, **실행 시점마다 `conn.prepareStatement(text)`로 JVM→서버 prepare 콜백**을 다시 탄다. XASL 캐시 히트는 되지만 parse/semantic은 핸들 캐시 미스 시 매번 (§4.1). |
| JavaSP와의 차이 | 실행 경로는 동일(둘 다 server-side JDBC → INTERNAL_JDBC 콜백). 차이는 (a) transaction_control 기본값(PL/CSQL 항상 true, JavaSP는 `PRM_ID_PL_TRANSACTION_CONTROL`), (b) PL/CSQL은 컴파일 시 서버 의미 분석 왕복이 추가 (§4). |
| 제약 | 스레드 동일성(스택·커서·tran_index 바인딩), 중첩 15, 인터럽트는 500ms 폴링 + 세션 마크, -294 pass-through/-889 wrap, autocommit 없음(commit/rollback→END_TRANSACTION 콜백, 7a), 핸들은 executor 종료 시 reset(세션은 유지) (§5). |
| 결론 | "wire 우회"는 서버↔client-half 구간에서 **이미 완료**되었다. 남은 지배 비용은 JVM 경계이며, 이것은 `cas_execute` 재호출로는 줄지 않는다. 줄이려면 JVM 왕복 수 자체(prepare+execute 합치기, 첫 fetch 페이지 동봉, 핸들 재사용 조건 완화)를 손대야 한다 (§6). |

## 1. 현재 런타임 경로 (cas-merge)

### 1.1 진입점 두 개

| 진입 | 위치 | 설명 |
|---|---|---|
| 서버 실행기(SELECT 안 SP 호출, METHOD scan 등) | `src/query/fetch.c:4213-4255` (TYPE_SP) | `cubpl::executor executor(sig)` → `fetch_args_peek` → `execute` → 결과 `method_result_to_server_semantics` 정규화(4255). 에러는 `ER_SP_EXECUTE_ERROR` wrap (4238-4249). |
| 폴드 client-half `CALL` 문 | `src/communication/network_interface_cl.c:11582-11649` (`pl_call` 非CS 분기) | `enter_server()` 후 같은 executor 사용. `db_make_null(&ret_value)`가 결함 8 수정(11590-11592). -294 pass-through·-889 wrap 11614-11623. |
| 레거시 CAS 클라이언트용 서버 콜백 | `src/communication/network_interface_sr.cpp:11289-11330, 11403-11450` | 브로커-CAS 연결이 남아 있을 때의 wire 경로. 폴드 세션과 무관. |

### 1.2 executor → JVM → 콜백 루프

1. `executor::execute` (`src/sp/pl_executor.cpp:273-326`): `change_exec_rights(auth)`(330-361, METHOD_CALLBACK_CHANGE_RIGHTS를 **client-half로**, JVM 아님) → `request_invoke_command` → `response_invoke_command` → 종료 시 `reset_query_handlers()`.
2. `request_invoke_command` (363-387): 세션 파라미터 + `prepare_args`(인자 DB_VALUE들; `src/method/method_struct_invoke.cpp:87-103`, 값마다 `dbvalue_java`) + `invoke_java`(시그니처·auth·arg mode/type·transaction_control; `pl_executor.cpp:67-84`)를 `send_data_to_java`로 소켓 송신. 소켓은 세션이 claim한 커넥션(`pl_execution_stack_context.cpp:186-198`, `pl_session.cpp:223-250`), UDS 또는 TCP (`src/sp/pl_comm.c:256-272, 288-348`).
3. `response_invoke_command` (400-455): JVM이 보내는 프레임의 첫 int가 `SP_CODE_INTERNAL_JDBC`(0x08, `src/sp/pl_comm.h:48`)이면 `response_callback_command`(510-591)로 분기하고 루프 계속, `SP_CODE_RESULT/ERROR`면 종료.
4. JVM 쪽: `jsp/ExecuteThread.java:520-530 sendCommand(ByteBuffer)`가 `RequestCode.INTERNAL_JDBC`를 붙여 쓰고, `jsp/impl/SUConnection.java:69-100 request()`가 바로 `receiveBuffer()`로 블록한다. 즉 **INTERNAL_JDBC = "JVM 안의 server-side JDBC 드라이버가 서버에 SQL/OID 서비스를 요청하는 프레임"** 이고, 그 페이로드는 `METHOD_CALLBACK_*` 코드 + packer 직렬화다. `jsp/jdbc/CUBRIDServerSideDriver.java:48,102` (`jdbc:default:connection` → `Context.getConnection`).

### 1.3 콜백 종류별 종단 위치

| 콜백 | 서버 처리 위치 | 어디서 끝나나 |
|---|---|---|
| QUERY_PREPARE | `pl_executor.cpp:650-682` → `send_data_to_client_recv` | client-half `callback_handler::prepare` (`src/method/method_callback.cpp:194-251`) → `query_handler::prepare_query` (`src/method/method_query_handler.cpp:790-858`: `db_open_buffer` 801, `db_compile_statement` 829, `db_session_set_holdable` 848) |
| QUERY_EXECUTE | `pl_executor.cpp:684-742` | `callback_handler::execute` (254-307) → `execute_internal` (688-770: `db_push_values` 1096, `db_execute_and_keep_statement` 732, peek 740). 서버측 후처리: SELECT면 `add_cursor`(715) 또는 0행이면 즉시 `xqmgr_end_query`(719-729). |
| FETCH | `pl_executor.cpp:744-827` | **서버측에서 직접** 끝난다. `query_cursor`가 list file을 `qfile_open_list_scan`/`qfile_scan_list_next`로 읽어 `data_readval`(`src/sp/pl_query_cursor.cpp:73-84, 131-218`). client-half 왕복 없음. |
| GET_DB_PARAMETER / GET_CODE_ATTR / SET_PL_SESSION_PARAM | `pl_executor.cpp:605-648, 996-1038, 1040-1076` | 서버측에서 직접. |
| OID_GET/PUT/CMD, COLLECTION, MAKE_OUT_RS, GET_GENERATED_KEYS, END_TRANSACTION | `pl_executor.cpp:829-994` | client-half (`method_callback.cpp:158-191, 309-460`). |
| CHANGE_RIGHTS (JVM 무관) | `pl_executor.cpp:330-361` | client-half `change_rights` (1037-1067, `au_perform_push_user/pop_user`) — 응답 없음. |
| METHOD_REQUEST_END (JVM 무관) | `pl_execution_stack_context.cpp:79-95` | client-half `free_query_handle(id,false)` → `reset()` (`method_callback.cpp:1121-1147`, `method_query_handler.cpp:69-73`). |

컴파일 시 콜백(GET_SQL_SEMANTICS/GET_GLOBAL_SEMANTICS)은 §4.1.

### 1.4 왕복 1회당 직렬화되는 것

| 방향/메시지 | 필드 (pack 순서) | 위치 |
|---|---|---|
| 서버→JVM INVOKE | sys_param 벡터, `prepare_args`(group_id, tran_id, n, 각 인자 `dbvalue_java`: type int + 값; 문자열은 codeset int + 바이트), `invoke_java`(tran_id, signature str, auth str, lang, n, [mode,type]×n, result_type, tc bool) | `method_struct_invoke.cpp:87-103`, `method_struct_value.cpp:61-250`, `pl_executor.cpp:67-84` |
| JVM→서버 PREPARE 요청 | sql string, flag, (서버가 tran_id 추가) | `pl_executor.cpp:658, 680`, `SUConnection.java:127-150` |
| 서버→JVM PREPARE 응답 `prepare_info` | handle_id, stmt_type, num_markers, n, `column_info`×n (db_type, set_type, charset, scale, prec, col_name, attr_name, class_name, default_value_string, is_non_null, auto_increment, unique_key, primary_key, reverse_index, reverse_unique, foreign_key, shared = 5 스칼라 + 4 문자열 + 8 int) | `method_struct_query.cpp:254-265, 132-153` |
| JVM→서버 EXECUTE 요청 `execute_request` | handler_id, execute_flag, max_field, is_forward_only, has_parameter, n, 각 param `pack_db_value` + param_modes | `method_struct_query.cpp:508-540` |
| 서버→JVM EXECUTE 응답 `execute_info` | handle_id, num_affected, `query_result_info`(stmt_type, tuple_count, ins_oid, include_oid, query_id), n, [stmt_type, num_markers, `column_info`×n] **(컬럼 메타 재전송)**, has_call_info + `prepare_call_info` | `method_struct_query.cpp:640-666, 464-471` |
| JVM→서버 FETCH 요청 | qid, pos, fetch_count, fetch_flag | `pl_executor.cpp:754`, `SUConnection.java:199-212` |
| 서버→JVM FETCH 응답 `fetch_info` | n, `result_tuple_info`×n (index, attr n, 각 attr `dbvalue_java`, oid) | `method_struct_query.cpp:854-862, 797-811` |
| JVM→서버 RESULT | `RequestCode.RESULT`, 반환값 `packValue`, OUT 인자들 | `ExecuteThread.java:494-506` |

fetch 페이지 크기: JVM 기본 1000 (`jsp/impl/SUStatement.java:43`), 서버 커서 기본 1000 (`pl_query_cursor.cpp:40`). 결과셋 페이지는 **행 단위로 DB_VALUE→dbvalue_java 재직렬화**된다(list file 튜플을 `data_readval`로 DB_VALUE로 풀고 다시 pack; `pl_query_cursor.cpp:165-199` → `method_struct_query.cpp:797-811`).

**프로시저 안 `SELECT` 1회의 왕복 수**(JVM↔서버 소켓 기준):

| 단계 | 소켓 왕복 | in-process 콜백 |
|---|---|---|
| 첫 `getConnection` (세션당 1회, clientInfo에 type 없을 때) | GET_DB_PARAMETER 1 | — |
| `conn.prepareStatement` | PREPARE 1 | callback prepare 1 |
| `executeQuery` | EXECUTE 1 | callback execute 1 |
| `rs.next()` 첫 호출 | FETCH 1 (이후 1000행마다 +1) | 없음(서버 커서) |
| `pstmt.close()` | **0** (`SUFunctionCode.java:75` CURSOR_CLOSE 주석 처리; `CUBRIDServerSidePreparedStatement.java:140,182` "statementHandler.close()?") | — |
| executor 종료 | — | CHANGE_RIGHTS pop 1 + METHOD_REQUEST_END 1 |

즉 최소 3회(prepare/execute/fetch) 소켓 왕복. 0행 SELECT도 `rs.next()`가 FETCH를 보내고 서버가 `cursor==nullptr`로 `ER_SP_INVALID_CURSOR` 응답을 만든다(`pl_executor.cpp:757-764`; JVM은 이 코드를 특별 처리 `SUConnection.java:83-88`). 루프 안 정적 SQL은 `pstmtRef` 최적화로 prepare 1회만 (`predefined/sp/SpLib.java:659-671`, `compiler/visitor/JavaCodeWriter.java:2175-2186`).

핸들 캐시 히트 조건: 같은 SQL 텍스트 + 미점유 + (tran_id 미설정 또는 동일 tid) + 같은 user (`method_callback.cpp:202-206`). 히트 시 `db_compile_statement`를 건너뛴다. JVM 쪽 `Context.checkTranId`는 tid가 바뀌면 statement를 invalidate (`jsp/context/Context.java:134-151`).

## 2. 폴드가 이미 바꾼 것 / 남은 것

### 2.1 hop 다이어그램

레거시 CS (upstream develop, 브로커-CAS):

```
[cub_server worker thread]                 [CAS process]                         [cub_pl JVM]
 fetch.c TYPE_SP → executor
   ── INVOKE ──────────────────────────────────────────────── UDS/TCP ──────────▶ ExecuteThread
                                                                                   conn.prepareStatement
   ◀── INTERNAL_JDBC(PREPARE) ────────────────────────────────────────────────────┘
   xs_callback_send: METHOD_CALL reply
   ── CSS wire ─────────────────▶ method_dispatch (CS_MODE)
                                   callback_handler::prepare → db_compile_statement
   ◀── CSS wire (xs_queue_send) ─┘
   ── INTERNAL_JDBC 응답 ─────────────────────────────────── UDS/TCP ──────────▶ SUConnection.request 반환
   (EXECUTE 동일, FETCH는 서버 커서에서 바로 응답)
```

cas-merge (폴드 세션, `csc_bracket_is_active()`):

```
[cub_server 세션 스레드 = CAS 화자 = 서버 실행기 = client-half]              [cub_pl JVM]
 driver_session request_loop → cas_process_request → fn_execute → ux_execute
   → db_execute… → 서버 hat: fetch.c TYPE_SP → executor
   ── INVOKE ───────────────────────────────────── UDS/TCP ───────────────────▶ ExecuteThread
   ◀── INTERNAL_JDBC(PREPARE) ──────────────────────────────────────────────────┘
   xs_callback_send → (bracket) method_dispatch (SERVER_MODE, 같은 스레드, db_on_server=0)
       → callback_handler::prepare → db_compile_statement   ← client-half, csc 소유 핸들 캐시
   xs_callback_receive ← csc handler의 m_data_queue (메모리)
   ── INTERNAL_JDBC 응답 ───────────────────────── UDS/TCP ───────────────────▶ SUConnection.request 반환
```

### 2.2 바뀐 코드 위치

| 변화 | 위치 |
|---|---|
| xs_callback in-process 종단 | `src/communication/network_callback_sr.cpp:38-56` (send→`method_dispatch`), `81-97` (receive→csc handler 큐). 브래킷 없는 스레드(레거시 CAS)는 기존 wire 경로 58-78, 99-118 유지. |
| SERVER_MODE `method_dispatch` | `src/method/query_method.cpp:208-271`: `db_on_server` hat 토글(212-213, 269), er_stack 격리 push/pop(219, 260-267), **er_dispatch_floor**(225-227, 258; 결함 1), libcas depth·중첩 한도(229-235), 최외곽에서 deferred 핸들 회수(247-256). |
| 핸들 캐시 세션 소유 | `src/method/method_callback.cpp:1232-1244` (`csc_current()->method_callback_handler`), `src/object/client_session_context.hpp:144`; 세션 종료 시 `method_callback_session_final` 1260-1270. |
| runtime_args 세션 소유 | `query_method.cpp:82-84`, `client_session_context.hpp:147`. |
| clearall floor | `src/transaction/transaction_cl.c:85` `er_stack_clear_above(csc_er_stack_floor())`, `client_session_context.cpp:106-110`. |
| 결함 7a: dispatch 중 commit의 page sweep 생략 | `src/storage/page_buffer.c:3197-3206` `csc_in_method_dispatch()`, `client_session_context.cpp:112-118` (`tm.libcas_depth > 0`). |
| 결함 8: `pl_call` ret_value 초기화 | `network_interface_cl.c:11590-11592`. |
| `get_session()`이 브래킷 스레드 허용 | `src/sp/pl_session.cpp:52-58` (upstream은 TT_WORKER만). |
| method eid thread_local | `src/communication/network_callback_cl.cpp:27-30`. |
| 결과 MOP→OID 정규화 | `src/sp/method_invoke_group.cpp:47-96, 211-218`, `fetch.c:4252-4255`. |
| 결함 17: px sibling interrupt의 PL 세션 마크 철회 | 선행 조사 §결함 17 (본 조사 범위 밖, 코드 위치 미확인 — §7). |

### 2.3 남은 것 — JVM 경계는 무변경

`diff -rq`(cas-merge vs upstream `6dbf6d92f`) 결과 `src/sp/`에서 달라진 파일은 `jsp_cl.*`, `method_invoke_group.*`, `pl_session.cpp`, `pl_signature.*`만이다. **`pl_executor.cpp`, `pl_execution_stack_context.*`, `pl_connection.*`, `pl_comm.*`, `pl_query_cursor.*`, `pl_compile_handler.*`, 그리고 `pl_engine/pl_server/src/main/java` 전체가 동일**하다. 따라서 서버↔JVM 프레이밍·직렬화·왕복 수는 upstream과 같다.

또 하나: 폴드 세션 스레드는 CAS 화자 그 자체다. `src/connection/driver_session.cpp:437-473 request_loop`가 `cas_process_request`(cas_dispatch)를 돌리고, 스레드 시작 시 `csc_activate(ctx)`(551-552). `cas_execute.c`는 cub_server에 링크된다(`cubrid/CMakeLists.txt:749`). 즉 한 세션 스레드 위에 **client-half 프론트엔드가 둘** 있다: (a) 드라이버 요청용 `cas_execute.c`(`T_SRV_HANDLE`, `cas_handle.c:61-148`, `net_buf`), (b) PL 콜백용 `method_callback.cpp`(`query_handler`, packer). 둘은 각자 `db_open_buffer`/`db_compile_statement`/`db_execute_and_keep_statement`에 도달한다(`cas_execute.c:816, 839, 1186` vs `method_query_handler.cpp:801, 829, 732`).

## 3. "서버가 폴드된 CAS 화자를 직접 호출"의 구체화

### 3.1 호출 가능한 진입점과 그 형태

| CAS 진입점 | 시그니처 요지 | 출력 형식 |
|---|---|---|
| `ux_prepare` | `(sql, flag, auto_commit_mode, T_NET_BUF*, T_REQ_INFO*, seq)` `src/broker/cas_execute.c:681-682` | `hm_new_srv_handle`로 `T_SRV_HANDLE` 생성, 컬럼 메타를 `net_buf_column_info_set`로 **CAS wire 포맷**에 기록 |
| `ux_execute` | `(T_SRV_HANDLE*, flag, max_col_size, max_row, argc, void**argv, T_NET_BUF*, T_REQ_INFO*, cache_time…)` 1055-1056 | 바인드는 `make_bind_value`(argv = wire 인코딩 바이트), 결과를 net_buf에 |
| `ux_fetch` | `(T_SRV_HANDLE*, cursor_pos, fetch_count, fetch_flag, result_set_index, T_NET_BUF*, T_REQ_INFO*)` 2505-2506 → `fetch_result` → `cur_tuple` → `dbval_to_net_buf` 4226-4273 | 튜플을 CAS wire 포맷으로 |
| `ux_end_tran` | 937 | — |
| `fn_prepare_and_execute` | `cas_function.c:649` (prepare+execute 1왕복) | 참고: CAS wire엔 합친 요청이 이미 있다 |

이들은 thread_local CAS 전역(`req_info`, `as_info`, srv handle 테이블)을 전제하고(`driver_session.cpp:434-436` 주석), 입력 인자도 wire 인코딩(`argv`)이며 출력도 wire 인코딩이다. 반면 JVM `SUConnection`은 `prepare_info`/`execute_info`/`fetch_info` packer 포맷을 unpack한다(§1.4). **따라서 콜백 핸들러에서 `ux_*`를 부르면 (i) JVM 요청(packer)을 argv(wire)로, (ii) net_buf(wire)를 다시 packer로 두 번 변환해야 한다.** 절약되는 직렬화는 없고, 커서도 문제다: 현재 FETCH는 서버 list file을 직접 읽는데(§1.3) `ux_fetch`는 client-half `DB_QUERY_RESULT` 커서를 쓴다 — 폴드 이전으로 되돌리는 셈이다.

### 3.2 서버↔client-half 구간에 실제 남은 비용

폴드 후 이 구간은 소켓이 아니다. 남은 것은:

1. 요청 pack: `xs_callback_send_args`가 (code, sql, flag, tid)를 `extensible_block`에 pack (`network_callback_sr.hpp:60-65`) → `method_dispatch_internal`이 `header`·code·필드를 unpack (`query_method.cpp:300, method_callback.cpp:92, 199`).
2. 응답 pack: `xs_pack_and_queue(METHOD_RESPONSE_SUCCESS, prepare_info)` → csc handler `m_data_queue` → `xs_callback_receive`가 람다에 블록을 넘김 (`network_callback_sr.cpp:87-95`).
3. 람다는 헤더만 unpack해 `handle_id`/`query_id`를 읽고 **같은 블록을 JVM에 verbatim 송신** (`pl_executor.cpp:660-678, 694-736`).

즉 2번의 pack은 JVM 프레임을 만드는 작업이라 어차피 필요하다. 없앨 수 있는 것은 1번의 pack/unpack 한 쌍과 3번의 헤더 재-unpack, 그리고 `m_data_queue`의 블록 소유권 이동 정도다. 이는 memcpy 규모이고, 콜백 하나에 소켓 왕복 1회(JVM 쪽 unpack·JDBC 객체 생성·Java 값 변환 포함)가 붙어 있는 구조에서 지배 비용이 아니다. 

pack을 우회해 `callback_handler::prepare(sql, flag, tid)`를 직접 호출하는 형태는 가능하나(둘은 이미 같은 스레드·같은 csc), 그 경우 `method_dispatch`가 주는 것들 — `db_on_server` hat 전환, er_stack 격리·floor, libcas depth(중첩 한도·7a sweep gate·deferred 핸들 회수) — 을 그대로 감싸야 한다(`query_method.cpp:208-271`). 이 브래킷은 프로세스 경계를 번역한 것이라 우회 시에도 필요하다(선행 조사 결함 1·7a).

### 3.3 무엇이 남는가

- **JVM 경계**: 프로시저 본문(JavaSP의 사용자 코드, PL/CSQL의 트랜스파일 Java)이 JVM에서 실행되는 한, SQL 1문당 prepare/execute/fetch 소켓 왕복은 서버 쪽 어떤 재배선으로도 사라지지 않는다.
- JVM 쪽 값 변환: `dbvalue_java` unpack → Java `Value` → JDBC getter, 반대로 bind → `pack_db_value`.
- 폴드가 이미 제거한 것: CSS wire 왕복(서버→CAS→서버) 1콜백당 1회, CAS 프로세스 컨텍스트 스위치, CAS 프로세스 측 packer 재-unpack.

## 4. PL/CSQL과 JavaSP의 분리

### 4.1 PL/CSQL — 컴파일은 JVM, 정적 SQL 의미 분석만 서버

컴파일(DDL 시점):

1. `CREATE PROCEDURE/FUNCTION … AS <plcsql>` → `src/sp/jsp_cl.cpp:1145-1165` `plcsql_transfer_file(compile_request, compile_response)` → 폴드 분기 `network_interface_cl.c:11942-11953` `compile_handler.compile` (`enter_server` 후).
2. `src/sp/pl_compile_handler.cpp:112-113`: `SP_CODE_COMPILE`로 JVM 송신 → `ExecuteThread.java:386-457 processCompile` → `PlcsqlCompilerMain.compilePLCSQL`(404).
3. 컴파일러가 정적 SQL마다 `compiler/serverapi/ServerAPI.java:51-61 getSqlSemantics` → `REQUEST_SQL_SEMANTICS` → 서버 `pl_compile_handler.cpp:146-153` → client-half `callback_handler::get_sql_semantics` (`method_callback.cpp:544-743`): `prepare_compile`(`method_query_handler.cpp:241-254`, `PREPARE_STATIC_SQL` → `PARSER_FOR_PLCSQL_STATIC_SQL` 795-798, 최적화 레벨 2 강제)로 파싱·의미 검사 후 **`parser_print_tree`로 재작성 텍스트**(584), 컬럼 타입, host var 타입/도메인, INTO 변수를 돌려주고 **핸들은 즉시 폐기**(703 `free_query_handle(…, true)`). 서버측 XASL/plan은 여기서 만들어지지 않는다(compile만).
4. JVM이 Java 소스 생성(`compiler/visitor/JavaCodeWriter.java:110` `final Connection conn = DriverManager.getConnection("jdbc:default:connection::")`; 정적 SQL은 `2150-2155` `pstmt = conn.prepareStatement(sql_text); rs = pstmt.executeQuery()` 템플릿; `compiler/ast/StmtStaticSql.java:53` 재작성 텍스트를 `ExprStr`로 박음) → 메모리 javac(`ExecuteThread.java:406-421`) → jar 바이트 base64 → `_db_stored_procedure_code`에 저장(`jsp_cl.cpp:1248-1249`).

실행:

- 서버 `executor` → INVOKE → JVM이 클래스 로드·리플렉션 호출(`jsp/StoredProcedure.java:322-327`) → 정적 SQL은 **JavaSP와 완전히 같은 server-side JDBC 경로**(§1.2-1.4)로 prepare/execute/fetch 콜백. `method_callback.cpp:580-584` 주석이 이를 명시한다("embedded verbatim in the compiled PL/CSQL class and re-parsed at runtime").
- 따라서 "정적 SQL이 서버측 컴파일러로 이미 오는가"의 답: **의미 분석 결과(타입)만 컴파일 시점에 오고, 실행 계획은 실행 시점 prepare 콜백에서 매번 `db_compile_statement`를 다시 탄다**(핸들 캐시 히트 시 생략, XASL 캐시로 plan은 재사용).
- 트랜잭션 제어: PL/CSQL은 항상 `transaction_control=true` (`pl_executor.cpp:64, 383`), `COMMIT/ROLLBACK` 문은 `conn.commit()` → END_TRANSACTION 콜백.

### 4.2 JavaSP

- 사용자 Java 코드가 `DriverManager.getConnection("jdbc:default:connection")` → `CUBRIDServerSideDriver.java:102` → `Context.getConnection` → `CUBRIDServerSideConnection` → `SUConnection` → INTERNAL_JDBC 콜백. SQL 컴파일·실행은 전부 서버 client-half(`method_query_handler`)에서.
- `setAutoCommit` no-op, `getAutoCommit()==false` (`CUBRIDServerSideConnection.java:160-167`). `commit()/rollback()`은 `context.canTransactionControl()`일 때만 END_TRANSACTION (169-193; `Context.java:208-222`; 기본 `transaction_control=false` `CUBRIDServerSideDriver.java:134`; 서버 파라미터 `PRM_ID_PL_TRANSACTION_CONTROL` `pl_executor.cpp:383`).
- 결과셋 반환(OUT ResultSet): `MAKE_OUT_RS` 콜백으로 커서 소유 스레드 교체(`pl_executor.cpp:904-947`, `pl_query_cursor.cpp:220-232`), 반환 시 세션 커서로 승격(`pl_executor.cpp:389-398`, `pl_execution_stack_context.cpp:152-169`).

### 4.3 한 줄 비교

| | PL/CSQL | JavaSP |
|---|---|---|
| 본문 실행 위치 | JVM(트랜스파일된 Java) | JVM(사용자 Java) |
| SQL 컴파일 | 컴파일 시 서버 의미 분석(핸들 폐기) + 실행 시 prepare 콜백 | 실행 시 prepare 콜백 |
| SQL 실행·fetch | INTERNAL_JDBC 콜백 (동일) | 동일 |
| transaction_control | 항상 true | 기본 false, 파라미터로 |
| 추가 왕복 | DDL 시 COMPILE 1 + SQL_SEMANTICS·GLOBAL_SEMANTICS n | 없음 |

## 5. 제약과 근거 위치

| 제약 | 근거 |
|---|---|
| **트랜잭션 조인 = 스레드 동일성.** `execution_stack`이 생성 스레드와 tran id를 들고(`pl_execution_stack_context.cpp:33-44, 206-211`), 콜백은 그 스레드에서 처리된다. `query_cursor`는 스레드의 tran_index로 `qmgr_get_query_entry`(`pl_query_cursor.cpp:55-56, 95-96`)하고, 스레드가 바뀌면 scan을 닫고 재소유(220-232). callback_execute의 `xqmgr_end_query`도 같은 스레드(`pl_executor.cpp:719-729`). `method_dispatch`는 `csc_bracket_is_active()` 스레드에서만(`network_callback_sr.cpp:44`), `get_session()`도 브래킷 스레드 조건(`pl_session.cpp:52-58`). 다른 스레드로 콜백을 넘기는 설계(예: JVM 응답을 별도 워커가 처리)는 이 바인딩을 전부 깨뜨린다. |
| **hat 전환.** dispatch 안은 `db_on_server=0`(client-half 규칙, `query_method.cpp:212-213`), 나올 때 복원. 결과 MOP는 서버 hat에서 OID로 정규화 필요(`fetch.c:4252-4255`). |
| **중첩 깊이 15.** `METHOD_MAX_RECURSION_DEPTH` `src/sp/sp_constants.hpp:160`; 세션 스택(`pl_session.cpp:113-117`, 초과 시 `ER_SP_TOO_MANY_NESTED_CALL` + 세션 interrupt)과 libcas depth(`query_method.cpp:229-235`) 이중 적용. |
| **인터럽트/취소.** JVM 응답 대기는 500ms 타임아웃 폴링 + `interrupt_handler`(`pl_execution_stack_context.hpp:150-166`, `.cpp:247-266`: `logtb_is_interrupted` → 커넥션 invalidate → 세션 `set_local_error_for_interrupt`, `pl_connection.cpp:335-373`). JVM 쪽은 소켓 IOException으로 스레드 종료(`ExecuteThread.java:203-209`). 세션 interrupt 마크는 스택 push/pop 때 검사·정리(`pl_session.cpp:120-136, 188-192, 312-382`); 결함 17은 이 마크가 쿼리를 넘어 생존한 사례. in-process dispatch 중(client-half 실행 중)에는 별도 취소 경로가 없고 서버 호출 내부의 tran interrupt 검사에 의존. |
| **에러 전파.** JVM 에러 → `SP_CODE_ERROR` → `set_error_message` → `ER_SP_EXECUTE_ERROR`(-889) (`pl_executor.cpp:493-498`); 호출측 wrap `fetch.c:4238-4249`, `pl_call` `network_interface_cl.c:11614-11623`, 레거시 `network_interface_sr.cpp:11310-11318`. **-294(`ER_SM_INVALID_METHOD_ENV`) pass-through**는 이 세 곳 모두에 있고, in-process `xs_callback_send`는 raw dispatch status가 아니라 `er_errid()`를 돌려야 그 pass-through가 동작한다(`network_callback_sr.cpp:48-54`). 콜백 에러는 `error_context`(err_id, msg, file, line; `method_error.cpp:86-101`, `ER_METHOD_CALLBACK`으로 로깅)로 JVM에 가고 JVM은 `ER_SP_INVALID_CURSOR` 외 전부 `ER_DBMS`로 매핑(`SUConnection.java:83-95`); 문자열 "no query handler"를 JVM이 식별자로 쓴다(`method_callback.cpp:262-264`). dispatch er 격리·floor(`query_method.cpp:215-227, 258-267`; 결함 1). |
| **autocommit 없음.** JVM 커넥션은 항상 non-autocommit(§4.2). commit/rollback은 END_TRANSACTION 콜백 → abort면 서버측 `destroy_all_cursors`(`pl_executor.cpp:974-985`) → client-half `db_commit/abort_transaction`(`method_callback.cpp:164-171`). 폴드에서 이 커밋은 **정지 중인 외부 실행기와 같은 스레드**에서 일어나므로 `pgbuf_unfix_all` sweep을 dispatch 중엔 생략(`page_buffer.c:3197-3206`; 결함 7a). 트랜잭션 경계에서 deferred된 핸들은 최외곽 dispatch 종료 시 회수(`query_method.cpp:244-256`). |
| **결과셋/핸들 수명.** 핸들은 DB_SESSION holdable(`method_query_handler.cpp:848`); qid→handler 맵(`method_callback.cpp:271-277`); 서버 커서는 스택 소유(`pl_execution_stack_context.cpp:97-117`), 스택 소멸 시 파괴(46-65, 171-184); 반환 결과셋은 세션 커서로 승격(152-169, `pl_executor.cpp:389-398`). executor 종료 시 `METHOD_REQUEST_END`로 스택의 핸들을 `reset()`(점유 해제·qresult 종료, DB_SESSION은 유지 → 다음 prepare 캐시 히트 가능; `method_callback.cpp:1135-1146`). JVM은 tid 변경 시 statement invalidate(`Context.java:149-151`). 핸들 캐시 재사용 조건에 tid 일치가 있어 트랜잭션이 바뀌면 재컴파일(`method_callback.cpp:204`). |
| **권한.** 각 CALL마다 CHANGE_RIGHTS push/pop 콜백(`pl_executor.cpp:296, 321, 330-361`) → `au_perform_push_user`(`method_callback.cpp:1046-1062`). |

## 6. 이 조사가 시사하는 선택지 (사실 기반 정리, 설계 결정 아님)

1. **`cas_execute.c` 재호출은 비목표.** 두 프론트엔드가 이미 같은 스레드·csc·db_* 계층에 있고, `ux_*`의 입출력은 JVM이 읽지 않는 CAS wire 포맷이다(§3.1).
2. **서버↔client-half packer 우회**는 가능하지만 memcpy 급 절약이며 `method_dispatch` 브래킷(hat·er floor·libcas depth)을 그대로 요구한다(§3.2).
3. **JVM 왕복 수를 줄이는 것만 실질 이득**이다. 코드 사실에 근거한 후보: (a) PREPARE+EXECUTE 합치기(CAS wire엔 `fn_prepare_and_execute`가 있으나 INTERNAL_JDBC 콜백엔 없음), (b) EXECUTE 응답에 첫 fetch 페이지 동봉(현재 EXECUTE 응답은 컬럼 메타를 재전송하면서 튜플은 0개 §1.4), (c) 0행 SELECT의 FETCH 왕복 제거(JVM이 `tuple_count`를 이미 받으므로), (d) 핸들 캐시 히트 조건의 tid 일치 완화(트랜잭션마다 재컴파일 §5). 이들은 모두 `pl_executor.cpp`(서버)와 `pl_engine` Java(프로토콜 양단)를 함께 바꾸는 작업이고 폴드와 독립적이다.
4. PL/CSQL 정적 SQL을 실행 시 재-prepare 없이 쓰려면 컴파일 시 서버가 만든 핸들/plan을 유지·참조하는 새 계약이 필요하다(현재는 의미 분석 후 핸들 폐기 §4.1). 이것은 JVM 왕복을 줄이지는 않고 서버측 parse/semantic 비용만 줄인다.

## 7. 확인 못 한 것

- **실측 없음.** 왕복 수는 코드 경로에서 도출한 값이며 프로파일/카운터로 확인하지 않았다(빌드·실행 금지 조건).
- `SUStatement.fetch()`가 0행(`tuple_count==0`)일 때 FETCH를 정말 보내는지는 코드상 그렇게 읽히나(`SUStatement.java:333-357`에 tuple_count 가드 없음), JDBC `ResultSet.next()` 상위 경로(`CUBRIDServerSideResultSet.java:115-126, 196`)의 사전 가드는 끝까지 추적하지 않았다.
- 결함 17 수정(px `run_jobs`의 `clear_interrupt`)의 정확한 파일:라인은 이번 트리에서 재확인하지 않았다(선행 조사 인용).
- `xs_pack_and_queue`(client-half 응답 큐잉)의 정의 파일(`network_callback_cl.*`)은 호출 관계만 확인했고 본문은 읽지 않았다.
- JVM 쪽 값 변환 비용(`dbvalue_java` unpack → `Value` → JDBC getter)의 코드 위치(`jsp/value/*`, `jsp/data/*`)는 열지 않았다.
- 레거시 브로커-CAS 연결이 cas-merge 빌드에서 실제로 여전히 wire 경로를 타는지(정책상 남겨둔 것인지, 제거 예정인지)는 코드 존재만 확인했다(`network_callback_sr.cpp:58-78, 99-118`).
- `prepare_info` 컬럼 메타가 EXECUTE 응답에 재전송되는 조건(`column_infos.size()>0`인 경우)이 항상 참인지 — `execute_info` 조립부(`method_query_handler.cpp:929-` `set_prepare_column_list_info`)의 호출 조건은 확인하지 않았다.
