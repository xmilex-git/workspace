# CAS 통합 코드 해설

[본문으로 돌아가기](develop-vs-cas-merge-briefing.md) · [운영·검증·파일 목록](develop-vs-cas-merge-appendices.md)

코드 비교 기준은 develop `e374c7a24`와 통합 `31702ac4a`다. 아래 링크와 발췌는 해당 커밋의 실제 코드다. 생략한 문맥은 명시하며, 경로 표는 완전한 stack trace가 아니라 대표 흐름을 압축한 설명이다.

## 1. 일반 prepared SELECT의 대표 경로

명시적 commit을 사용하는 일반 드라이버 연결을 기준으로 읽는다. autocommit 경로는 별도이며 execute 응답에 첫 fetch가 동승하는 경우도 있다. 표 사이의 wrapper를 모두 펼친 호출 스택으로 읽지 않는다.

| 단계 | 통합 후 코드 위치 | 리뷰 질문 |
|---|---|---|
| fd 입양·전담 스레드 | [adoption.cpp:507](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/adoption.cpp#L507) | HANDOFF_ACK와 스레드 시작 순서·실패 시 fd 책임은 맞는가 |
| 컨텍스트 활성화 | [driver_session.cpp:532](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/driver_session.cpp#L532) | 스레드 등록·client context·서버 conn이 어떤 순서로 만들어지는가 |
| 인증·세션 소유권 이전 | [driver_session.cpp:679](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/driver_session.cpp#L679) | db_restart_ex 이후 session_adopt_client_context가 수명을 넘겨받는가 |
| 요청 dispatch | [cas_dispatch.c:684](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_dispatch.c#L684) | 기존 function code가 어떤 CAS handler를 부르는가 |
| prepare·compile | [cas_execute.c:840](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_execute.c#L840), [db_vdb.c:1110](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/compat/db_vdb.c#L1110) | ux_prepare의 문장 핸들과 db_compile_statement의 세션 상태가 일치하는가 |
| SELECT 계획·캐시 | [execute_statement.c:15375](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/query/execute_statement.c#L15375) | cache miss의 XASL 생성·stream 변환과 hit 경로를 구분하는가 |
| native prepare | [network_interface_cl.c:7523](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_interface_cl.c#L7523) | 직접 호출해도 stream 소유권이 보존되는가 |
| execute | [cas_execute.c:1216](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_execute.c#L1216), [network_interface_cl.c:7767](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_interface_cl.c#L7767) | db_execute_and_keep_statement와 OBJECT→OID/clone·첫 페이지 사본의 수명이 맞는가 |
| fetch | [cas_execute.c:5437](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_execute.c#L5437), [network_interface_cl.c:7359](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_interface_cl.c#L7359) | db_query_next_tuple와 추가 list page 접근이 해제된 결과를 참조하지 않는가 |
| 명시적 commit | [cas_execute.c:967](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/broker/cas_execute.c#L967) | ux_end_tran의 정리 뒤 db_commit_transaction이 실행되는가 |
| 연결 종료 | [driver_session.cpp:748](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/connection/driver_session.cpp#L748) | rollback 예외(XA prepared)·ux_end_session·conn·context·thread·fd 정리가 짝을 이루는가 |

## 2. 실제 코드 전후 비교 세 가지

### 2.1 수송을 없애도 stream의 소유권은 남는다

기존 CS 경로는 [query prepare 요청을 전송](https://github.com/xmilex-git/cubrid/blob/e374c7a24c46449c3f79e9413a6f4ff3d23b16c2/src/communication/network_interface_cl.c#L7186)한다.

```c
  req_error =
    net_client_request2 (NET_SERVER_QM_QUERY_PREPARE, request, request_size, reply,
                         OR_ALIGNED_BUF_SIZE (a_reply), (char *) stream->buffer, stream->buffer_size,
                         &reply_buffer, &reply_buffer_size);
```

통합의 non-CS 경로는 [서버 함수를 직접 호출](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_interface_cl.c#L7520)한다. 아래는 함수 일부이며 뒤의 오류 처리·exit_server는 생략했다. 발췌의 들여쓰기만 문서에 맞췄다.

```c
  INIT_XASL_NODE_HEADER (server_stream.xasl_header);

  /* call the server routine of query prepare */
  error_code = xqmgr_prepare_query (thread_p, context, &server_stream);
  if (server_stream.buffer != NULL)
    {
      free_and_init (server_stream.buffer);
    }
```

이 직접 호출 경로는 SA용으로 이미 존재했고 SERVER_MODE에서도 쓰도록 확장한 것이다. 새로 발명한 실행기를 뜻하지 않는다. 앞선 코드에서 stream을 malloc 버퍼로 복사하며, 캐시가 소유권을 가져갔는지에 따라 남은 버퍼를 정리한다. RPC가 없어졌다고 stream과 free까지 지워서는 안 되는 이유다.

### 2.2 같은 이름의 전역 접근을 세션별 접근으로 바꾼다

기존 [work_space.c](https://github.com/xmilex-git/cubrid/blob/e374c7a24c46449c3f79e9413a6f4ff3d23b16c2/src/object/work_space.c#L84)는 프로세스 전역 테이블을 둔다.

```c
WS_MOP_TABLE_ENTRY *ws_Mop_table = NULL;
```

통합의 [work_space.h](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/work_space.h#L497)는 SERVER_MODE 문맥에서 이름을 세션 컨텍스트로 연결한다.

```c
#define ws_Mop_table (csc_ws ()->mop_table)
#define ws_Mop_table_size (csc_ws ()->mop_table_size)
```

호출부 전체를 새 API로 바꾸지 않고도 기존 client 절반이 자기 세션의 테이블을 보게 한다. 다만 매크로 치환만으로 수명·동시성이 해결되지는 않는다. [csc_activate의 핵심 두 줄](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/client_session_context.cpp#L64)은 접근 직렬화와 현재 컨텍스트 연결을 각각 수행한다.

```cpp
  ctx->bracket_mutex.lock ();
  tl_Csc_active = ctx;
```

TLS 포인터는 현재 접근 대상을 가리킨다. 소유권은 서버 세션에 있다. [세션 소멸](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/session/session.c#L390)은 csc_retire_and_delete를 호출하며, 자기 브래킷 안에서 은퇴하면 [orphan 표시로 삭제를 미룬다](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/client_session_context.cpp#L276). [deactivate](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/object/client_session_context.cpp#L71)에서 teardown·unlock·delete의 순서를 완성한다.

### 2.3 PL 콜백을 현재 서버 스레드에서 종단한다

기존 [xs_callback_send](https://github.com/xmilex-git/cubrid/blob/e374c7a24c46449c3f79e9413a6f4ff3d23b16c2/src/communication/network_callback_sr.cpp#L54)의 송신 부분이다.

```cpp
  /* send */
  unsigned int rid = css_get_comm_request_id (thread_p);
  return css_send_reply_and_data_to_client_direct (thread_p->conn_entry, rid, reply, OR_ALIGNED_BUF_SIZE (a_reply),
         (char *) mem.get_read_ptr (), (int) mem.get_size ());
```

통합은 앞에 [활성 세션 브래킷 분기](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_callback_sr.cpp#L44)를 둔다. 아래 연속 네 줄 뒤에는 에러 ID 보정과 return이 이어지며, 여기서는 생략했다.

```cpp
  if (csc_bracket_is_active ())
    {
      packing_unpacker unpacker (mem.get_read_ptr (), mem.get_size ());
      int error = method_dispatch (unpacker);
```

분기의 근거는 “서버 프로세스인가”가 아니라 “client 절반이 지금 이 세션 문맥에서 실행 가능한가”다. 활성 브래킷이 없는 legacy 경로는 아래 wire 송신으로 계속 간다. JVM 자체를 제거한 변경도 아니다.

[enter_server/exit_server](https://github.com/xmilex-git/cubrid/blob/31702ac4a31cd2b1237812d5150a8cff9076d209/src/communication/network_interface_cl.c#L144)는 같은 스레드에서 실행 모자와 error stack을 전환·복원한다. csc_activate처럼 세션 브래킷 락을 새로 잡는 동작과 혼동하면 중첩 실행을 잘못 해석하게 된다.

## 3. 아키텍처와 핵심 규약

### 3.1 연결 입양과 제어 채널

브로커는 드라이버의 초기 패킷을 비차단으로 살펴 DB 이름을 알아내고, DB별 UNIX 입양 소켓으로 fd를 전달한다. 서버에는 기존 master 연결과 나란히 입양 연결 경로가 생긴다. 지속 제어 채널은 세션 종료 통지·질의 취소·상태 동기화에 쓰인다.

슬롯과 취소 토큰은 실제 CAS PID와 구분해야 한다. 서버가 발급하는 토큰으로 취소 대상을 식별하고 브로커가 대응을 관리한다. 서버의 client 상한과 브로커의 수용량 제한은 모두 남는다. 연결 종료·거절·서버 재시작 시 슬롯 반환과 재동기화가 정확해야 한다.

읽을 코드: `src/connection/adoption.cpp`, `driver_session.cpp`, `src/broker/broker.c`, 관련 헤더. 접속 프런트와 wire dispatch의 경계를 먼저 보고 오류 경로의 fd 소유권을 따라간다. [브로커↔서버 커넥션 핸드오프 설계](https://github.com/xmilex-git/workspace/issues/117).

### 3.2 세션 객체 컨텍스트와 TLS는 역할이 다르다

`client_session_context`는 client 절반의 워크스페이스·스키마·권한·질의 결과·부트 상태를 담는다. 서버 `session_state`의 `csc_p`가 수명의 기준이다. TLS는 지금 실행 중인 스레드가 이 컨텍스트에 접근하는 수단이지, 세션 객체의 영구 소유자가 아니다.

반면 현재 CAS 화자는 입양된 연결당 전담 스레드를 사용한다. 따라서 `CAS_TLS`로 바꾼 CAS 정적 상태는 이 연결-스레드 대응 아래 세션별 상태가 된다. 향후 epoll/워커 풀로 바꿀 때 이 전제를 그대로 둘 수 없다.

| 용어·심볼 | 뜻 | 리뷰에서 피할 혼동 |
|---|---|---|
| 세션 객체 컨텍스트 | 컴파일에 필요한 client 절반 상태 | 전부 서버 전역 캐시로 공유된다는 해석 |
| `csc_activate/deactivate`·브래킷 | 현재 세션 컨텍스트의 실행 범위·직렬화 | 단순 TLS 포인터 설정만으로 보는 것 |
| `db_on_server` | 지금 서버 절반 의미론으로 실행하는지 | 현재 프로세스가 서버인지 판별하는 것 |
| `csc_bracket_is_active()` | 세션 객체 문맥이 활성인지 | 서버 모자에서는 MOP가 절대 없다는 가정 |
| `CAS_TLS` | CAS 화자의 연결 전담 스레드 상태 | 일반 서버 워커에서도 자동 세션 귀속된다는 가정 |
| `CSQL_PARSER_TLS` | 파서·컴파일 임시 상태의 스레드 분리 | 파스 결과의 세션 수명까지 해결한다는 가정 |

동일 서버 스레드가 client 절반과 server 절반을 오간다. 따라서 `#if SERVER_MODE`를 런타임 의미론으로 그대로 읽을 수 없다. 특히 OBJECT/MOP와 OID의 구별에는 현재 모자뿐 아니라 소유권과 브래킷이 필요하다. [client workspace·스키마/locator 캐시의 서버측 세션-스코프 재설계](https://github.com/xmilex-git/workspace/issues/123).

### 3.3 RPC 경계를 함수 경계로 접는다

주요 경계는 `src/communication/network_interface_cl.c`다. `qmgr_prepare_query`, `qmgr_execute_query`, `qmgr_prepare_and_execute_query` 같은 client 진입점이 서버 내부 호출로 이어진다. SA 모드의 직접 호출 경로를 참고하되 SA의 단일 클라이언트·락 생략 가정을 가져와서는 안 된다.

native DB_VALUE 진입에서는 OBJECT를 서버 OID 의미론으로 정규화해야 한다. 결과 첫 페이지 사본의 수명도 보존해야 한다. 수송이 사라졌다고 이전 pack/unpack이 해주던 소유권 분리까지 생략할 수는 없다.

XASL stream은 유지한다. 캐시는 이미 packed stream과 unpack된 실행 클론 풀을 보관한다. prepared 실행이 매번 전체 pack/unpack한다는 설명은 맞지 않는다. 유틸리티 RPC·영속 인덱스 술어·병렬 워커 클론도 stream에 의존한다. [RPC 경계 접기 설계 — cas↔server request의 함수 전환·XASL stream 경로](https://github.com/xmilex-git/workspace/issues/124), [XASL 경로 사실 조사](../research/cas-merge-opt-xasl-no-stream.md).

## 4. 모듈별 변경과 리뷰 초점

### 4.1 빌드와 파서

`cubrid/CMakeLists.txt`의 client 절반 소스 편입과 CAS 화자 소스 편입이 출발점이다. `broker/CMakeLists.txt`는 Linux CAS 실행 파일을 없애고 Windows 경로를 남긴다. 단순 소스 이동 PR로 보기 어려운 이유는 같은 파일이 다른 모드로 컴파일되기 때문이다.

파서의 수기 전역과 bison/flex 생성물 전역을 `CSQL_PARSER_TLS`로 분리한다. 생성물 후처리 CMake는 생성기 버전 변경으로 TLS 전환이 빠지지 않는지도 확인해야 한다. 파서 라벨처럼 세션 수명을 갖는 것은 TLS 임시 상태와 분리한다. `src/parser/csql_parser_tls.h`, grammar/lexer, `src/query/xasl_to_stream.c`가 해당한다. [파서 재진입화 + parse_tree 소유권 정리](https://github.com/xmilex-git/workspace/issues/131).

### 4.2 워크스페이스·객체·메모리

`client_session_context.hpp/.cpp`와 `work_space.c`, `schema_manager.c`, `object_domain.c`, `set_object.c` 등을 함께 읽는다. 워크스페이스를 없앤 것이 아니다. MOP·DDL 쓰기 표현·스키마 표현은 세션별로 유지하고 teardown에서 정리한다.

AREA는 공유하는 기존 동기화 기계 위에 둔다. 전부 per-session AREA로 복제하지 않는다. 서버 private heap과 워크스페이스 할당의 경계도 구별한다. 다른 수명의 힙으로 만든 포인터를 캐시에 남기면 세션 종료 후 UAF가 된다.

CTP에서 실제 발견한 대표 문제는 OBJECT 도메인의 NULL OID끼리 동등 판정해 다른 클래스가 같은 도메인으로 매칭된 경우다. 통합의 검증 단위는 단일 SELECT 성공보다 **서로 다른 세션의 생성·사용·종료 반복**이어야 한다. [MOP/워크스페이스 per-session化](https://github.com/xmilex-git/workspace/issues/133), [medium 잔존 24 NOK — -494 클래스 잔여 + order-by tie C5 판정](https://github.com/xmilex-git/workspace/issues/174).

### 4.3 인증·DDL·파라미터

인증된 서버 세션에 client 권한 컨텍스트를 연결한다. REVOKE는 `sm_touch_class`를 통한 chn 변경으로 prepared 문장의 재검사를 유도한다. 이 과정의 추가 스키마 락 비용은 수용한 설계 비용이다. DROP에서는 디스크 구조 해제 후 권한 경로가 클래스를 재구성하지 않도록 순서가 중요하다.

`src/base/system_parameter.c/.h`에서는 기존 client 전용 파라미터를 서버가 읽고 세션 값에 반영하도록 바뀐다. `PRM_SESSION_READTHROUGH`와 `cas_*` 실행 파라미터가 그 연결점이다. 공유 stub에 세션 값을 덮어쓰는 것은 서버 전역 데이터 레이스가 될 수 있다. 세션 파라미터와 프로세스 전역 설정을 한 규칙으로 설명해서는 안 된다.

[DDL 권한처리 서버 이전 구현](https://github.com/xmilex-git/workspace/issues/135), [create_table_reuseoid 세션 파라미터 CS-wire 미반영](https://github.com/xmilex-git/workspace/issues/159).

### 4.4 CAS 화자·로그·SSL·ACL

`cas_dispatch.c`와 `cas_conn_helpers.c`는 기존 CAS 처리 루프를 서버에서 사용할 수 있게 분리한 축이다. `cas_execute.c`, `cas_handle.c`, `cas_log.c` 등은 서버에서 동시에 여러 세션을 처리하므로 기존 정적 변수의 수명과 동시성 전제가 달라진다.

로그의 생산자는 서버로 이동한다. CAS 로그 포맷을 보존한다는 결정과 기존 per-CAS 파일명·status 행을 보존한다는 결정은 별개다. SSL 종단도 서버로 이동하며 브로커는 암호화된 접속을 라우팅할 정보가 필요하다. IP ACL 프런트와 DB·사용자별 서버 검사를 구분한다.

statement 핸들 풀은 계속 세션별이다. 세션 간 prepared descriptor 공유는 아직 후속 후보다. [CAS 프로토콜 화자 완성](https://github.com/xmilex-git/workspace/issues/139), [prepared statement 공유 사실 조사](../research/cas-merge-opt-shared-prepared-statement.md).

### 4.5 PL/CSQL·JavaSP

`src/communication/network_callback_sr.cpp`의 `xs_callback_send` 경계에서 `method_dispatch`로 같은 스레드 안에서 들어간다. `method_query_handler`와 `method_struct_value`의 값·핸들 소유권도 함께 바뀐다. 핸들 캐시는 워크스페이스가 살아 있는 동안 정리할 수 있도록 client session context에 귀속된다.

wire로 복사하던 객체를 직접 넘기면 alias를 소유 포인터로 오해할 수 있다. 실제 `execute_info::call_info`의 내장 객체 alias를 delete한 결함이 있었고, 소유권 구분으로 고쳤다. 에러 격리·중첩 호출 후 deferred 핸들 정리도 정상 경로와 함께 읽어야 한다.

JVM의 PREPARE·EXECUTE·FETCH 왕복을 합치는 최적화는 이번 구현의 성과가 아니다. [plcsql/javasp in-process 종단 구현](https://github.com/xmilex-git/workspace/issues/136), [PL wire 우회 사실 조사](../research/cas-merge-opt-pl-inprocess-call.md).

### 4.6 csql과 유틸리티 채널

`src/executables/csql_wire.c`와 csql 결과 포매터를 본다. CS 모드에서는 `csql_wire.c`가 CAS V12 프로토콜로 직접 요청을 보내고 서버가 기존 포매터로 텍스트를 만든다. 현재 구현은 CCI API 호출을 사용하지 않는다. 설계 기록의 “CCI 전송 재사용”은 현재 코드의 라이브러리 의존을 설명하는 표현으로 쓰지 않는다. 클라이언트는 표시와 터미널 처리를 담당한다. 로컬 csql은 입양 UNIX 소켓으로 연결해 브로커 없이 사용할 수 있다. 원격 csql은 대상 노드 브로커가 필요하다. `csql -S`는 SA 경로로 남는다.

관리 유틸리티의 `libcubridcs`를 지우거나 별도 라이브러리로 물리 분할한 것은 아니다. boot 등록의 client type 허용목록으로 일반 SQL 경로와 관리·HA 경로를 구별한다. CDC API와 cub_manager의 CI 실패는 이 도달성 계약을 다시 확인해야 한다는 신호다. 로그만으로 단일 근인을 확정하지 않는다.

[csql thin-client화·유틸리티 전용 라이브러리 분리 설계](https://github.com/xmilex-git/workspace/issues/126).

### 4.7 HA·취소·실패 경계

브로커의 ACCESS_MODE를 서버가 client type으로 합성하고 접속 시 HA 상태와 대조한다. 트랜잭션 경계의 reset은 드라이버의 기존 재접속 규약으로 돌려준다. CAS가 수행하던 별도 failover 계층은 사라지고 드라이버 altHosts가 중요해진다.

서버가 없으면 빠르게 retryable 접속 실패를 반환하고, 실행 중 서버 사망은 연결 실패로 드라이버에 드러난다. 접속 허용·읽기 전용·REPLICA/SO·유지보수 상태를 한 가지 정상 master 접속 테스트로 대신할 수 없다. 기존 2-pass 허용의 일부 최종 상태를 포기하는 엄격 단일-pass 정책도 의도된 의미 차이다. [HA 접속 의미론 — ACCESS_MODE 라우팅·standby 거절·altHosts failover의 서버 직결 재배치](https://github.com/xmilex-git/workspace/issues/121).

### 4.8 에러와 크래시의 영향 범위

서버에 컴파일러가 들어오면 컴파일러의 메모리 손상이 서버 전체를 죽일 수 있다. 시그널을 잡아 longjmp로 세션만 살리는 새 격리 계층은 도입하지 않는다. 불변식 위반은 fail-fast를 유지하고, 사용자 입력 오류는 에러 경로로 처리한다. OOM은 문장 에러·필요 시 트랜잭션 abort로 대응한다.

표현식 깊이 가드, 스레드별 sigaltstack, 워크스페이스 abort 경로가 추가됐다. 초기 깊이 한도와 후속 CTP 수정 후 한도는 다르므로 옛 스테이지 기록의 1024를 현재 값으로 인용하지 않는다. 중첩 서브쿼리 전체를 포괄하는 안전 증명도 아니다. [컴파일러 편입 후 에러/크래시 격리 정책](https://github.com/xmilex-git/workspace/issues/128).

### 4.9 회귀 수정과 추가 편입 범위

최종 비교에는 초기 구조 편입 뒤 CTP가 검출한 수정도 포함된다. 이를 TLS 변경의 부수적인 줄 수정으로만 묶으면 리뷰에서 값 규약과 동시성 계약을 놓친다.

| 영역 | 코드 | 바뀐 이유 |
|---|---|---|
| SP·메서드 반환값 | `fetch.c`, `method_invoke_group.cpp` | client MOP 반환을 server OID 의미론으로 정규화 |
| SP 결정성 | `pl_signature.cpp/.hpp` | SERVER_MODE에서도 결정성 정보를 전달·초기화 |
| 병렬 쿼리 종료 | `px_query_executor.cpp` | 내부 sibling 종료가 남긴 PL 세션 interrupt 정리 |
| open system operation | `external_sort.c`, `query_hash_join.c` | 디스패처가 가진 topop과 워커의 대기로 생기는 자기 데드락 방지 |
| 페이지 버퍼·중첩 실행 | `page_buffer.c` 등 | 외부 method 실행이 일시 중단된 문맥 보호 |
| 세션 설정 읽기 | `cas_function.c`·`CAS_SHM_CFG` | 공유 stub의 원시 값 대신 해당 세션 설정 사용 |
| 검증 진입점 | `server_compile_tracer.cpp`·`unit_tests/server_compile/` | 서버 내부 컴파일·실제 드라이버 경로를 반복 검증 |

MERGE 병렬 sort 데드락과 메서드 인자 배열 언더할당처럼 develop 선존으로 판정한 수정도 섞여 있다. 통합 고유 회귀와 상류 공통 결함을 구분해 반입 순서를 논의한다. [MERGE 병렬 group-by sort 자기-데드락](https://github.com/xmilex-git/workspace/issues/164), [ws_decache_all_instances SIGSEGV — sql-fix](https://github.com/xmilex-git/workspace/issues/175).
