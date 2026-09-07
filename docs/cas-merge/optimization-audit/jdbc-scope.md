# JDBC 후속 구현 범위: 외부 cubrid-jdbc와 PL internal JDBC

이 문서는 정적 조사 당시의 사실·대안을 보존한다. 현재 결정은 [최종 판정](../candidate-disposition.md)과 [브레인스토밍](../optimization-brainstorm.md)을 따른다.

## 기준과 조사 한계

- 엔진: frozen `dbf0b6409ab8e15516a2df5580bffc0e5c1dcfe4`.
- 엔진이 지정한 cubrid-jdbc submodule revision: `a3ebfb76bf4f0150fb8bd643e6dc2b5491b3d1cf` (`engine/.gitmodules`/gitlink). 엔진 submodule working tree는 미초기화 상태여서 `/home/cubrid/dev/cubrid/cubrid-jdbc` object database의 해당 commit을 `git show`로 읽었다. 별도 checkout HEAD `4a40cb95...`를 근거로 쓰지 않았다.
- 정적 범위 확인만 수행했다. protocol capture, YCSB 실행, driver test, 호환 버전 matrix 전수 확인은 하지 않았다.

## 1. 외부 cubrid-jdbc: 서버 공유 plan은 우선 protocol-transparent

### 현재 경계

1. JDBC `Connection.prepareStatement`는 `CUBRIDConnection.java:159-165, 800-838`에서 연결의 `prepare(...)`를 호출한다. 옵션 `prepStmtCache`가 켜지고 SQL 길이 제한을 만족하면 같은 **연결 안에서** SQL→`PreparedStatement`를 캐시한다(`CUBRIDConnection.java:93,116-118,817-837`; `UConnection.java:1474-1493`). 연결 close에서 cache를 비운다(`CUBRIDConnection.java:641-647`). 이것은 process-wide/server-wide 준비 객체 공유가 아니다.
2. `UConnection.prepareInternal`은 기존 CAS protocol `PREPARE(2)`에 SQL, prepare flag, autocommit, deferred close handles를 싣고 응답으로 `UStatement`를 만든다(`UConnection.java:1300-1330`). `UStatement.init`은 응답의 serverHandler, result-cache lifetime, statement type, marker count, updatable, column count/metadata를 연결-local 객체에 저장한다(`UStatement.java:166-203`).
3. 서버는 `cas_execute.c:816-868`에서 handle별 `DB_SESSION`을 열고 compile하여 `srv_handle->is_prepared`, stmt id와 metadata를 만든다. execute는 해당 handle/session에 bind한 뒤 `db_execute_and_keep_statement`를 호출한다(`cas_execute.c:1135-1217`). 공유 native plan을 도입해도 이 mutable handle, bind, result/cursor는 연결/실행별로 남아야 한다.
4. cached/pooled handle의 XASL이 무효화되면 서버는 `ER_QPROC_INVALID_XASLNODE`/`ER_HEAP_UNKNOWN_OBJECT`를 `CAS_ER_STMT_POOLING(-10024)`로 바꾼다(`cas_execute.c:1246-1253`). JDBC는 execute와 batch에서 이를 감지해 `PREPARE_XASL_CACHE_PINNED`를 붙여 `reset`→동일 SQL 재prepare→execute를 한 번 시도한다(`UStatement.java:950-1014,1152-1173`; `UErrorCode.java:106`).
5. fetch는 execute와 별도 CAS `FETCH` 요청이며 statement 내부 page cache가 맞으면 요청하지 않고, 아니면 handler/cursor position/fetch size를 전송한다(`UStatement.java:1176-1200,1769-1821`). prepare 응답 metadata와 cursor page behavior는 JDBC-visible 계약이다.

### 후속 구현 판정

- **외부 JDBC API 또는 CAS v12 wire 변경은 shared native plan의 필수 조건이 아니다.** 서버가 `(SQL 정본 + 사용자/스키마/컴파일 영향 설정/prepare flags)`로 공유 immutable prepared/native plan을 찾고, 기존 connection-local `serverHandler`에 참조와 mutable execution state만 붙이면 JDBC의 PREPARE/EXECUTE/FETCH 응답은 유지할 수 있다.
- 반드시 유지할 호환 계약: serverHandler identity/lifetime과 CLOSE/deferred-close, marker 및 column metadata, prepare flags(include OID/updatable/query-info/holdable/pinned/call), autocommit/generated keys, per-execution bind/result/cursor, invalidation 때 `CAS_ER_STMT_POOLING` 재준비, reconnect 후 reset, protocol version의 기존 framing.
- shared plan eviction은 살아 있는 handle 참조를 UAF로 만들면 안 된다. 확정된 Q5에 맞춰 유휴 핸들이 큰 plan을 영구 pin하지 않도록 하고, generation mismatch를 execute 전에 검출해 내부 재준비 또는 기존 `CAS_ER_STMT_POOLING` 규약으로 수렴시킨다. 실제 실행·커서의 참조 수명은 별도로 보호한다. DDL/통계/recompile 무효화의 기존 외부 관찰 결과를 유지한다.
- 외부 wire 최적화는 현재 맵의 V12 무변경 계약과 구분한다. 예: PREPARE 응답 metadata version/reference, prepare+execute/first-fetch 결합. 이런 새 외부 wire 동작은 현재 채택된 server-transparent JDBC 연동과는 별도 범위다. 공유 native plan 연동 구현은 기존 wire를 유지한다. 엔진에는 이미 CAS `PREPARE_AND_EXECUTE(41)` handler가 있다(`cas_protocol.h:245`, `cas_function.c:922-947`)지만 이 조사에서 cubrid-jdbc가 이를 일반 PreparedStatement에 사용하는 근거는 찾지 못했다.

### 최소 검증 범위

- pinned/non-pinned prepare, pooling on/off에서 invalid XASL→`CAS_ER_STMT_POOLING`→한 번 재prepare가 동일하게 동작.
- 동일 SQL 100 JDBC connections가 한 shared plan을 참조하되 각 handle의 bind/result/cursor/metadata와 close가 독립적임을 계수.
- DDL/권한/통계/recompile/connection reconnect 후 stale handle이 새 generation으로 안전하게 이동.
- YCSB C/A의 기존 연결별 cachedStatements는 그대로 두고 server unique plan 1, session handle N, concurrent execution state K를 별도 관찰.

## 2. PL internal JDBC: T5/T7은 Java와 C++ protocol 구현이 필요

### 현재 경계

- Java `pl_engine/.../jsp/impl/SUConnection.java:69-98`의 `request`는 cub_pl→cub_server 실제 UDS/TCP 경계를 왕복한다. PREPARE/EXECUTE/FETCH는 각각 `:127-149`, `:168-212`에서 독립 메시지다.
- 서버 `pl_executor.cpp:401-452,511-590`가 `SP_CODE_INTERNAL_JDBC`를 decode한다. PREPARE/EXECUTE는 `:650-742`에서 다시 `send_data_to_client_recv`로 넘긴다.
- `pl_execution_stack_context.hpp:125-135` → `network_callback_sr.hpp:35-70`는 typed args를 extensible block으로 pack한다. merged bracket에서는 `network_callback_sr.cpp:38-56`이 같은 worker에서 이를 unpack해 `method_dispatch`; response는 session handler queue에서 `:81-96`으로 회수한다. 이 **두 번째 request packet/queue adapter**가 T5의 내부 제거 대상이다.
- JVM으로 돌려보낼 response pack은 실제 process boundary 때문에 유지한다. prepare/execute bookkeeping을 위해 server가 response를 다시 unpack하는 부분만 typed side result로 줄일 수 있다.

### 필요한 구현 family

1. **T5 typed callback seam(C++):** `method_callback/query_handler`에 prepare/execute/OID/collection 등의 typed entry를 두고, merged SERVER_MODE는 `method_dispatch`용 request pack/queue를 거치지 않는다. 반환은 `typed bookkeeping + JVM-compatible response block`. legacy CS/SA packer endpoint는 adapter로 유지한다.
2. **T7 combined command(Java+C++):** PL protocol에 capability/version을 둔 `PREPARE_EXECUTE`와 선택적 first-fetch payload를 추가한다. Java `SUConnection`/`SUStatement`가 새 명령을 선택하고, C++ `pl_executor`, method query handler/struct가 처리한다. 구버전 상대에는 현재 PREPARE→EXECUTE→FETCH로 fallback한다.
3. **metadata 중복 축소(Java+C++):** prepare metadata를 handle generation과 함께 캐시하고 execute가 같은 generation이면 재전송을 생략한다. metadata가 실제 포함되는 statement/result 종류만 대상으로 한다.

### 불변식과 gate

- 실제 JVM socket framing, Java value codec, error mapping, nested call order는 유지한다.
- `db_on_server` hat, er-stack isolation/floor, auth push/pop, libcas recursion limit, transaction/thread binding, deferred query-handler reclaim를 typed seam에서도 보존한다.
- SELECT의 zero-row end, generated keys, OUT/ResultSet, holdable cursor, interrupt/timeout, transaction-control 차이(PL/CSQL vs Java SP)를 회귀 검증한다.
- 왕복 수 주장은 조건부다: 새 SELECT를 prepare하고 `rs.next()`하는 경우 현재 최소 prepare+execute+fetch 3회. DML은 보통 2회, Java가 statement를 재사용하면 execute(+fetch)만 발생한다.
- 기본 YCSB는 PL internal JDBC를 실행하지 않으므로 별도 PL/JavaSP micro workload가 필요하다. 외부 JDBC YCSB 결과로 T5/T7을 판정하지 않는다.

## 최종 scope

- 채택된 shared prepared/native XASL 구현에 **외부 cubrid-jdbc 호환 gate**를 포함한다. 첫 구현은 서버 투명 변경으로 잡고 driver source 변경을 의무화하지 않는다.
- 채택된 PL 후속 T5/T7은 실제 C++/Java 양쪽 구현 항목으로 등록한다. T5 request adapter 제거와 T7 왕복/metadata 결합은 독립 단계로 나누어 검증한다.
- 외부 JDBC 새 wire 설계는 현재 계약 밖이며, PL 내부 JDBC protocol 결합과 혼동하지 않는다.
