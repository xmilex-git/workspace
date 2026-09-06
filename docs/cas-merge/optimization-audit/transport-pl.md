# CAS merge 내부 transport/copy/result/value 및 PL/JVM 감사

- 대상: frozen engine `dbf0b6409ab8e15516a2df5580bffc0e5c1dcfe4`, 비교 upstream `e374c7a24c46449c3f79e9413a6f4ff3d23b16c2`
- 범위: `network_interface_cl`의 SERVER_MODE 직접 호출, query result/list/cursor, DB_VALUE/object/set 변환, method/PL executor/internal JDBC/Java protocol
- 성격: 2026-09-06 현재 코드의 정적 감사. 코드 변경·실행·벤치마크 없음. 따라서 아래는 제거 후보와 계측 우선순위이지 성능 판정이 아니다(MEAS-01/04/06/07).

## 결론과 우선순위

| ID | 남은 CAS 분리 시대 구조 | 적용 빈도 / YCSB | 정적 비용 상한 | 권고 |
|---|---|---|---|---|
| T1 | 실행 바인드 `DB_VALUE[]` 전량 clone | prepared execute마다; YCSB 직접 관련 | `N` DB_VALUE 할당/초기화/clear + 가변 payload 총 `B` 바이트 deep-copy | OBJECT만 OID 정규화하고 나머지는 borrowed view/희소 override로 전달 |
| T2 | 결과 첫 페이지를 client-owned wire 수명처럼 보존하고 cursor가 다시 복사 | 결과 query마다; YCSB read 직접 관련 | 현재 최대 `2P` memcpy + 두 사본의 `2P` 일시 메모리 (`P=DB_PAGESIZE=CURSOR_BUFFER_SIZE`, runtime DB page 크기) | list/query 수명 pin 또는 페이지 소유권 transfer; 최소한 두 번째 copy를 move로 |
| T3 | client cursor가 list-id와 별도 page/area를 항상 소유 | 결과 cursor마다; YCSB read 관련 | domain pointer `C*sizeof(ptr)`, page `P`, buffer area 2개 alloc | SERVER_MODE 전용 cursor view로 list-id/type-domain borrow, page transfer/pin |
| T4 | 모든 client API→xserver wrapper의 hat/error-stack context hop | 문장 내 여러 번; YCSB 관련 | 호출마다 TLS/stack 상태 read-write 및 함수 경계 | server-session 전용 typed facade로 묶고 최외곽에서 한 번만 경계 설정 |
| T5 | PL INTERNAL_JDBC 요청을 같은 스레드 client-half용으로 pack→unpack | PL 호출의 prepare/execute/OID 등; 보통 YCSB 무관 | callback마다 요청 payload `R` 1회 생성+1회 parse+queue node | JVM request decode 뒤 typed callback 직접 호출; JVM 응답 pack은 유지 |
| T6 | PL fetch의 tuple DB_VALUE 중간 벡터 반복 copy | PL result row마다; 보통 YCSB 무관 | 행당 `C` readval + `C` vector copy + `C` result copy; OID면 추가 `(C-1)` copy | packer로 row를 직접 emit하거나 move-only row builder 사용 |
| T7 | PL prepare/execute 분리 왕복과 column metadata 재전송 | PL 내부 SQL마다; 보통 YCSB 무관 | SELECT의 prepare+execute+첫 fetch는 3 JVM 왕복; metadata 중복은 응답 포함 조건에 따름 | combined prepare-execute 및 첫 fetch 동봉; statement lifetime/cache 불변식 명시 |
| T8 | PL SET pack이 `set_get_element`로 매 원소 DB_VALUE copy | SET 인자/결과; YCSB 거의 무관 | 원소 `E`마다 copy+clear+재귀 pack | `set_get_element_nocopy`/iterator view로 pack (코드 TODO와 일치) |

`xasl_to_stream`/`stream_to_xasl`은 다른 담당 범위지만 한 가지 판단은 명시한다. 내부 prepared object를 공유하려는 목표에서 XASL stream은 캐시가 따뜻해도 구조적 부채다. top profile에 안 보였다는 사실은 직접 비용의 현재 크기만 말한다. parser arena→packed bytes→unpack arena가 객체 정체성과 공유 가능한 불변 plan을 끊어 놓으므로, shared immutable plan + per-execution mutable state로 가는 설계에서 반드시 별도 축으로 다뤄야 한다(SER-01, MEM-05, COH-05). 외부 CS/utility와 disk format 소비자는 계속 필요하므로 그 포맷 삭제와 내부 경로 제거는 분리해야 한다.

## 후보 상세

### T1. execute마다 바인드 전량 deep clone

- 호출 경로: `query_cl.c:128 execute_query` → `network_interface_cl.c:7565 qmgr_execute_query` → `:7740` 이후 SERVER/SA 분기 → `:7763-7787` 배열 초기화 및 OBJECT→OID/그 외 `db_value_clone` → `:7798 xqmgr_execute_query` → `query_manager.c:1309`.
- prepare-and-execute도 `network_interface_cl.c:7837` → `:7928-7963` → `:7967 xqmgr_prepare_and_execute_query`로 동형이다.
- 소유권 이유: wire 경로는 서버가 unpack한 독립 DB_VALUE를 가졌다. 현재 clone은 그 수명/서버 의미를 모사하고 `:7805-7813`, `:7974-7982`에서 clear/free한다. OBJECT는 MOP가 client workspace 객체이므로 OID 정규화가 필수다.
- 제거안: 입력 배열을 `const DB_VALUE*`로 borrow하고 OBJECT 위치만 작은 override 배열 또는 실행 인자 accessor에서 OID로 치환한다. 가변 문자열/collection을 실행기가 보관하거나 수정하는 소비자가 발견되면 그 타입/위치만 clone한다. 소유권 transfer는 호출자가 실행 종료까지 값을 보유하므로 동기 execute에서 가능하다.
- 불변식: server hat에는 MOP가 들어가면 안 됨; xqmgr가 입력 payload를 free/변경/비동기 보관하지 않아야 함; 중첩 PL 재진입 중 caller 값 수명 유지; NULL 및 clone 실패 오류 동일.
- 비용식: 현재 `N*sizeof(DB_VALUE)` 할당 + `N` null-init + `N` 분기 + 비-OBJECT payload 합 `B` copy/allocation + `N` clear. 공유 view는 OBJECT 수 `O`에 대해 `O*sizeof(DB_VALUE)` 정도로 축소 가능. ALLOC-01/02, MEM-01/05, COH-12.
- YCSB: prepared statement bind가 매 operation 실행하므로 최상위 후보다. 실제 type(키 문자열과 갱신 payload를 포함하는 값)이면 `B`는 작아도 배열 alloc/init/clear는 그대로다.

### T2. 결과 첫 페이지의 2단계 복사

- 생성: `qmgr_execute_query`가 `xqmgr_execute_query` 후 `network_interface_cl.c:7801-7803 qmgr_attach_first_page_copy`; prepare-and-execute도 `:7970-7972`.
- 함수는 `:201-240`: temp list first page를 pin/read하고 `malloc(DB_PAGESIZE)` 후 page 전체 `memcpy`, 원 페이지 unfix, `list_id->last_pgptr`에 client-owned copy를 단다.
- 소비: query result가 `cursor_open` → `cursor.c:1241 cursor_copy_list_id`; `cursor_copy_list_id:113-143`는 구조체를 memcpy하고 domain pointer array를 복사하며 `last_pgptr`가 있으면 `malloc(CURSOR_BUFFER_SIZE)` + 다시 전체 memcpy한다. `cursor_buffer_last_page:956-959`가 그 복사본을 읽는다.
- 해제: 첫 list-id copy와 cursor copy 모두 `cursor_free_list_id`(`cursor.h:86-103`)가 `last_pgptr`를 free한다. 첫 copy가 필요한 이유는 autocommit generated-key read-back이 즉시 `xqmgr_end_query` 뒤에도 읽기 때문이라는 `network_interface_cl.c:201-209` 계약이다.
- 제거안: (A) `cursor_copy_list_id`가 heap page ownership을 source에서 destination으로 move하는 SERVER_MODE API, (B) query/list lifetime refcount/pin을 cursor까지 연장해 원 page를 borrow, (C) generated-key만 필요한 경로면 실제 tuple 길이만 compact copy. A가 가장 국소적이며 두 번째 P-byte copy를 없앤다.
- 불변식: source와 destination 중 정확히 하나만 free; query end 뒤 page 유효; fallback page fetch가 query 생존 시만 가능; CS가 받은 packet ownership은 기존 유지; overflow/next VPID framing 유지.
- 비용식: 현행 page당 `P + P` byte copy, 2 alloc, 최고 `2P` 별도 메모리. A는 `P` copy/1 alloc, B는 0 copy. MEM-01/07, ALLOC-01, COH-12.
- YCSB: read 결과가 작아도 페이지 크기 전체를 복사하므로 tuple 수와 무관한 고정 비용이다.

### T3. cursor/list descriptor의 client-owned 복제

- `cursor.c:107-145`는 `QFILE_LIST_ID` 전체 shallow memcpy 뒤 `type_list.domp`를 `C*sizeof(TP_DOMAIN*)`로 복제한다. `cursor_open:1236-1251`은 이어 `CURSOR_BUFFER_AREA_SIZE`를 별도 할당한다.
- 과거 이유: client cursor는 서버 packet/list descriptor와 독립 수명이어야 했다. 합쳐진 session에서는 query entry와 cursor가 같은 주소 공간이고 T2의 수명 문제만 해결하면 immutable type domains를 공유할 수 있다.
- 제거안: `cursor_open_server_view`가 query entry/list-id를 const borrow하고 cursor의 mutable scan/buffer만 소유. 또는 descriptor refcount handle. domain은 캐시/스키마 lifetime을 확인한 뒤 const span으로 공유한다.
- 불변식: schema/domain invalidation 동안 cursor domain 생존; cursor는 `tpl_descr`, `sort_list`, `last_pgptr`를 free하지 않음; query close 순서; legacy CS ABI 유지.
- 비용식: cursor당 descriptor memcpy + `C` pointer copy + 최대 page `P` + buffer area alloc. DS-01, MEM-01/05, ALLOC-02.

### T4. wrapper 단위의 가상 client/server context hop

- `network_interface_cl.c:138-197`: SERVER_MODE에서도 `enter_server`가 `db_on_server++`, `er_stack_push_if_exists`, thread lookup을 하고 `exit_server`가 error 복원 및 flag 감소를 한다. 파일의 수많은 `#else /* CS_MODE */` wrapper가 실제 xserver 함수를 직접 부르면서도 이 쌍을 반복한다. 예: query execute `:7796-7815`, transaction commit `:3120-3143`, session `:4835-4889`.
- 과거 이유: SA에서 client/server heap/error 상태를 모사. merge에서는 같은 worker와 이미 활성화된 `client_session_context`를 쓴다.
- 제거안: 한 driver request 최외곽에서 server-hat scope를 설정하고 내부 typed facade는 기존 thread pointer를 전달한다. wrapper별 error isolation이 의미 있는 곳만 명시적 scope로 남긴다.
- 불변식: 중첩 method dispatch가 `db_on_server=0`으로 client-half를 실행하는 계약(`query_method.cpp:208-270`); er stack floor; private allocation routing; thread/transaction identity.
- 비용은 wrapper 호출 수 `W`에 비례한 TLS read/write와 stack bookkeeping. 작아도 모든 operation에 반복되는 구조이므로 함께 계측한다. GLOB-01/05, BR-04, CC-05.

### T5. PL 내부 callback 요청의 같은-address-space pack/unpack

- 현재 경로: JVM `SUConnection.request`(`pl_engine/.../SUConnection.java:69-98`) → cub_pl socket → `pl_executor.cpp:401-452 response_invoke_command` → `:511-590 response_callback_command` → `execution_stack::send_data_to_client_recv`가 callback payload block 생성 → `network_callback_sr.cpp:38-56 xs_callback_send`가 bracket이면 같은 스레드에서 `packing_unpacker`와 `method_dispatch` → `query_method.cpp:296-329` header/command 재-unpack → callback handler.
- 응답은 handler queue(`network_callback_sr.cpp:81-96`)에서 꺼내 `pl_executor.cpp:660-680`/`:694-739`가 header/일부 객체를 다시 unpack한 후 동일 block을 JVM으로 보낸다.
- 구분: JVM↔cub_server UDS/TCP framing과 Java 호환 pack은 실제 외부 프로세스 경계이므로 필요하다. 같은 worker에서 client-half에 도달하기 위한 요청 block과 queue는 CAS process separation 잔재다. 응답 block은 JVM consumer 때문에 필요하지만, server-side bookkeeping을 위해 전체 `prepare_info`/`execute_info`를 unpack할 필요는 typed result를 함께 반환하면 줄일 수 있다.
- 제거안: JVM request를 한 번 decode해 typed `prepare/execute/...` 함수를 직접 호출하고, 그 함수가 `{typed bookkeeping result, JVM response block}`을 반환. 기존 packer endpoint는 legacy CS/SA adapter로 유지.
- 불변식: `db_on_server` hat, er isolation/floor, libcas nesting max 15, auth push/pop, deferred handler reclaim, transaction/thread 동일성, 오류 -294/-889 전파, response byte compatibility.
- 비용식: callback당 제거 가능분은 request `R` bytes write+read, extensible block allocation/growth, queue push/pop, header dispatch. SER-01, ALLOC-01/02, MEM-01, PHYS-10.
- YCSB: 일반 YCSB는 SP를 호출하지 않는 한 미실행. PL workload에서 측정해야 한다.

### T6. PL fetch row 중간 복제

- `pl_query_cursor.cpp:132-210 next_row`는 list tuple을 PEEK한 뒤 열마다 `data_readval(..., true, ...)`로 owning `m_current_tuple` DB_VALUE를 만든다.
- `get_current_tuple`이 `std::vector<DB_VALUE>`를 값으로 반환한다(`pl_query_cursor.hpp:68`, `.cpp:240-244`). `pl_executor.cpp:793`에서 첫 vector copy, OID 포함이면 `:799`에서 sub-vector 추가 copy, `result_tuple_info` 생성자는 `method_struct_query.cpp:772-786`에서 다시 element assignment copy한다. destructor는 `:798-803`에서 각 value를 clear한다.
- 이어 `fetch_info::pack`(`:863-870`) → `result_tuple_info::pack:806-820`이 각 DB_VALUE를 `dbvalue_java`로 직렬화하고, Java `SUResultTuple.java:22-41`가 다시 Value 객체 배열을 만든다. Java 객체화는 소비자 호환상 필요하지만 C++ 중간 복사는 필요하지 않다.
- 복사의 정체는 payload deep clone이 아니라 DB_VALUE 구조체의 shallow copy와 vector allocation이다. `data_readval(..., true)`가 만든 payload를 중간 구조체 복사 뒤 결과 destructor가 해제하는 기존 소유권 전달 계약이다. 이를 새로운 double-free 결함으로 판정하지 않는다.
- 제거안: cursor의 current tuple을 `const span<DB_VALUE>`로 노출하고 response packer가 즉시 emit; OID 열은 index skip. 또는 vector를 move하여 `result_tuple_info`가 단일 소유. fetch block 전체를 한 번 reserve(`rows*cols` 예상 크기).
- 불변식: pack 완료까지 tuple payload 생존, 다음 `next_row` 전 소비, OID hidden-column 제거, type/codeset/date mapping, error시 이미 읽은 값 clear.
- 비용식: `F` rows, `C` cols이면 현재 최소 `F*C` readval + `F*C` vector copy + `F*C` result copy; OID면 추가 `F*(C-1)`. direct emit은 readval도 tuple bytes→Java wire 직접 변환기로 합칠 가능성이 있다. ALLOC-01/02, CPP-02, MEM-01, SER-03.

### T7. PL prepare/execute/fetch 왕복 및 metadata 중복

- Java는 `SUConnection.prepare:127-149`, `execute:168-197`, `fetch:199-212`를 각각 동기 `request`한다. SELECT가 prepare/execute/첫 fetch를 각각 수행하면 통상 3 JVM socket round trip이며, DML은 보통 2회이고 Java statement 재사용 시 prepare는 생략된다. handler cache hit만으로 PREPARE 왕복이 사라지지는 않는다. 이후 결과는 1000행 단위로 추가 fetch한다(`pl_query_cursor.cpp:40`).
- prepare 응답은 `prepare_info::pack`(`method_struct_query.cpp:263-273`)에서 column metadata를 보낸다. execute 응답도 `execute_info::pack:649-675`에서 `column_infos`를 다시 전송한다.
- 제거안: PL 전용 `prepare_execute` 명령과 첫 fetch page 동봉. 반복 정적 SQL은 Java generated code의 statement reference 및 server handler cache와 결합해 prepare 생략. 동일 metadata version/id를 execute에서 참조.
- 불변식: recompile flag, user/tran_id별 handler cache, marker modes, holdable/resultset lifetime, zero-row 즉시 end(`pl_executor.cpp:719-730`), interrupt/timeout, nested call ordering, Java protocol version fallback.
- 비용식: SELECT가 prepare·execute·첫 fetch를 각각 요청하면 3회이며, DML은 보통 2회, Java statement를 재사용하면 prepare가 생략된다. handler cache hit은 prepare 왕복 자체를 없애지는 않는다. 결합 명령은 첫 세 요청을 1회로 묶는 후보이며 추가 fetch 수는 결과량에 따른다. metadata는 execute 응답에 column_infos가 포함되는 경우에만 중복분을 줄일 수 있다. SYS-05, SER-01, DS-01. YCSB 기본과 무관.

### T8. PL collection pack의 per-element copy

- `method_struct_value.cpp:193-214 dbvalue_java::pack_value_internal`: SET/MULTISET/SEQUENCE에서 원소마다 `set_get_element` → recursive pack → `db_value_clear`. 코드 자체가 `set_get_element_nocopy` TODO를 남긴다.
- 외부 JVM wire 직렬화는 필수지만 원소 DB_VALUE 소유 복사는 필요하지 않다. const iterator/nocopy accessor로 즉시 pack한다.
- 불변식: set storage는 pack 완료까지 불변, nested collection lifetime, NULL/domain/codeset semantics, iterator 중 mutation 금지.
- 비용식: `E` 원소당 clone/clear와 variable payload allocation 제거; wire `Σencoded(elem)`은 유지. ALLOC-01, STR-01, MEM-01.

## 외부/내부 경계 판정

- 유지가 필요한 실제 경계: driver↔server CAS protocol, legacy external CAS/CS clients, cub_pl JVM↔cub_server UDS/TCP, utility/HA channels, catalog/disk의 packed format.
- 내부 adaptation 후보: SERVER_MODE `network_interface_cl` wrapper의 wire 수명 모사, 같은-thread method callback request block/queue, result/list descriptor의 client-owned copy, DB_VALUE 전량 clone.
- JVM 응답 pack과 Java Value 객체 생성은 consumer compatibility 때문에 유지 대상이다. 다만 서버 안의 중간 객체 수와 왕복 수는 줄일 수 있다.

## 계측 순서와 완료 범위

1. YCSB A/C prepared path에서 T1 alloc/clone bytes와 T2 page copy count/bytes를 카운터로 분리한다. wall-clock median+dispersion, absolute alloc/copy counts를 함께 기록한다(MEAS-04/06/07).
2. SERVER_MODE wrapper 호출 수 `W`와 `enter/exit_server` children time을 잰다. 낮게 나오더라도 typed facade 설계의 유지보수/구조 비용과 직접 비용을 분리한다.
3. 별도 PL micro workload에서 prepare/execute/fetch 왕복 수, callback request block bytes, fetch `F*C` copy/alloc 수를 기록한다. YCSB 결과로 PL 후보를 기각하지 않는다.
4. T2 ownership-transfer 실험은 double-free/UAF를 ASAN과 generated-key/autocommit/zero-row/overflow-page로 검증한다. T1은 scalar/string/object/set bind와 nested SP를 검증한다.

확인한 현재 코드: communication network client/server callback, query cursor/list/query manager reachability, compat DB_VALUE contract, method dispatch/value/query structs, PL executor/query cursor, Java SUConnection/SUResultTuple. 시간 제한상 모든 `network_interface_cl.c` wrapper, 모든 DB_VALUE 타입 구현, JDBC/CCI driver statement pool, PL compiler-generated statement reuse, legacy utility consumers의 전 호출처는 전수 열거하지 못했다. 기존 연구 문서는 길 찾기에만 사용했고 위 라인/심볼은 frozen tree에서 다시 확인했다.

## 독립 검증 보충

- T1: `query_manager.c:1294`는 입력 DB_VALUE 배열을 호출 동안 빌리며 해제하거나 호출 뒤 보유하지 않는다고 명시한다. `qmgr_process_query`와 `qexec_execute_query`는 const DB_VALUE 입력으로 동기 소비한다. 다만 `copy_bind_value_to_tdes`(`:1414,1716-1764`)의 진단용 history clone과 result-cache용 clone(`:1419-1435`)은 별도의 보유 목적이므로 wrapper clone 절감에 합산하지 않는다.
- T2/T3: `CURSOR_BUFFER_SIZE=DB_PAGESIZE`는 runtime `db_User_page_size`이고, 별도 `CURSOR_BUFFER_AREA_SIZE=IO_MAX_PAGE_SIZE`는 16KiB다(`cursor.c:49-50`, `storage_common.h:93,97,101`).
- T6: payload deep copy 횟수와 중간 DB_VALUE 구조체 복사 횟수를 분리한다. 기존 shallow-copy chain을 새 결함으로 보고하지 않는다.
- T7: prepare 응답과 execute 응답의 metadata 중복은 execute.column_infos 포함 여부를 계수해야 한다. 실제 Java statement 재사용 여부와 서버 handler cache hit은 다른 조건이다.
