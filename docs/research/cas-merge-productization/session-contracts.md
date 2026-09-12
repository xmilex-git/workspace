# CAS 통합 제품화: 세션·전역·중첩 실행 소유권 조사

조사 기준: `xmilex-git/cubrid@d533969e4db6ef94d512d91f463790bab559790a`. 소스 정적 조사만 수행했고 빌드·실행·TC는 수행하지 않았다. 이 문서의 “확정”은 해당 소유권/동기화 결손을 코드와 호출 경로에서 확인했다는 뜻이며 실행 재현을 뜻하지 않는다. 기존 지도 기록은 후보 발견에만 쓰고 현재 소스를 다시 확인했다.

## 판단

shell/HA 전부 통과해도 남는 제품 작업이 있다. 가장 먼저 **세션 명령이 여전히 쓰는 프로세스 전역 상태를 닫고**, **레거시 native METHOD를 서버 내부에서 어떤 계약으로 지원할지 결정·구현**해야 한다. 그 다음은 이미 도입된 CSC를 전면 재작성하는 일이 아니라 **PL 중첩 실행과 자원 귀속의 불변식을 복원하는 일**이다. 현재 동기·연결당 스레드 모델을 즉시 worker pool로 바꾸거나 workspace를 제거해야 제품화되는 것은 아니다.

## 1. 확정 결손: optimizer cost override가 다른 세션의 컴파일을 바꾼다

현재 `QO_PARAM_LEVEL`은 CSC 세션 override로 옮겼지만 `QO_PARAM_COST`는 그대로 `qo_plan_set_cost_fn()`에 전달한다. 이 함수는 프로세스 전역 `all_vtbls[]`가 가리키는 `cost_fn`을 직접 바꾼다. optimizer는 같은 함수 포인터를 읽어 비용을 계산한다. setter/getter/reader에 이를 보호하는 공통 잠금이나 세션 선택은 없다.

구체 경로:

1. thin csql `;set cost seq-scan i`의 `S_CMD_SET_PARAM`은 서버로 전달된다. 서버 allowlist에도 같은 명령이 있다. [csql.c:1189](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/executables/csql.c#L1189), [csql.c:1247](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/executables/csql.c#L1247)
2. 서버 명령 dispatcher가 `csql_set_sys_param(argument)`를 실행하고, `cost` 문법이면 권한 검사나 세션 저장 없이 `qo_plan_set_cost_fn()`을 호출한다. [csql.c:1614](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/executables/csql.c#L1614), [csql.c:3098](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/executables/csql.c#L3098)
3. 전역 vtbl 목록과 `cost_fn` write는 각각 `query_planner.c:446`, `5511/5520/5524`에 있다. 같은 함수 포인터는 `794`, `2878`에서 호출된다. [전역 목록](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/optimizer/query_planner.c#L446), [setter](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/optimizer/query_planner.c#L5494), [reader](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/optimizer/query_planner.c#L794)

따라서 A 세션의 디버그 설정이 B 세션의 새 실행계획을 바꿀 수 있고, 병렬 컴파일과 setter의 동시 실행은 C++ data race이다. CAS 시절 한 프로세스 안에 갇혔던 설정의 영향 범위가 서버 전체로 바뀐 사례다. 한 명령이 순서대로 잘 동작하는 TC로는 격리 계약을 확인할 수 없다.

**최소 구현:** vtbl의 기본 함수는 불변으로 두고 cost 선택을 CSC에 저장한다. 실제 컴파일 진입 시 해당 값을 optimizer 문맥으로 가져와 한 컴파일 동안 고정한다. 기능을 제품에서 유지할 이유가 없다면 서버 진입점에서 이 override를 명시적으로 거절하는 것도 작은 해법이다. 단순 mutex만 추가하면 data race는 줄여도 다른 세션에 설정이 전파되는 의미론은 남는다. 이미 구현한 LEVEL 경로를 참고할 수 있다. [query_graph.c:355](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/optimizer/query_graph.c#L355)

**완료 계약:** A의 `cost` 설정·조회·재설정은 A에만 적용되고, B와 새 세션의 기본값은 유지된다. 동시 컴파일 중 함수 포인터 전역 write가 없으며, A가 연결을 끊어도 B의 비용 모델은 변하지 않는다.

## 2. 확정 결손 + 제품 결정: native METHOD 로더와 사용자 C 코드의 실행 계약

레거시 METHOD가 현재도 서버 내부에서 동적 라이브러리까지 도달한다. “builtin”이라는 함수명은 실제 사용자 native METHOD를 차단하는 allowlist가 아니다.

경로는 `method_invoke_builtin_internal()` → `obj_send_array()` → `obj_send_method_array()`의 lazy link → `sm_link_method()` → `sm_dynamic_link_class()` → `sm_link_dynamic_methods()` → `dl_load_object_module()`이다. [query_method.cpp:475](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/method/query_method.cpp#L475), [object_accessor.c:3221](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/object_accessor.c#L3221), [schema_manager.c:1681](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/schema_manager.c#L1681), [schema_manager.c:1197](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/schema_manager.c#L1197)

**소스상 확정된 동기화 결손:** `dl_Errno`, `dl_Loader`가 process-global이고, Linux `dl_load_objects()`는 공통 candidate 목록 및 handler 배열을 늘리고 기존 배열을 free하며 `handler.top`을 수정한다. `dl_resolve_symbol()`은 동일 배열을 순회한다. 세션 CSC mutex는 세션마다 다르므로 이 공통 자료구조를 보호하지 않는다. `boot_Restart_mutex`는 부트만 직렬화하며 부트 이후 lazy method link에는 걸리지 않는다. [dynamic_load.c:189](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/dynamic_load.c#L189), [로드·재할당:1535](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/dynamic_load.c#L1535), [symbol 순회:1648](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/dynamic_load.c#L1648), [부트 잠금](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/transaction/boot_cl.c#L1209)

**별도의 제품 계약 위험:** dlopen 자체가 thread-safe여도 CUBRID가 관리하는 위 배열과 사용자 .so의 `static` 상태는 자동으로 안전해지지 않는다. 기존 확장 메서드의 static buffer, process-global DB handle, signal/exit, allocator 사용을 CAS 프로세스 격리가 대신 감싸던 범위가 이제 `cub_server`다. 특정 확장 코드의 결함을 발견했다는 뜻은 아니며, 기존 native METHOD의 호환성을 “wire가 같으므로 보존된다”고 선언할 수 없다는 뜻이다.

**가장 먼저 할 결정:** 제품에서 사용자 동적 native METHOD를 계속 지원할지, 지원 범위를 제한할지 확정한다. 지원을 유지한다면 (a) 로더 전체 load+resolve 작업의 동기화, (b) 라이브러리 및 symbol namespace와 수명, (c) 재진입/동시 호출 및 메모리 소유권 ABI, (d) 기존 확장 마이그레이션 계약이 필요하다. 로더 mutex를 native 함수 실행 전체까지 무조건 넓히는 방식은 DB 재진입/락 대기와 교착할 수 있으므로 별도로 설계해야 한다. 지원에서 제외한다면 dynamic-link 진입 전에 명확한 오류를 내고, 내장 메서드와 Java/PLCSQL 지원 범위를 구분해 문서화해야 한다.

**완료 계약:** 지원되는 호출에는 라이브러리 수명과 동시 실행 계약이 있고 load/resolve의 공유 가변 자료구조는 보호된다. 지원되지 않는 호출은 실제 dlopen 전에 결정적으로 거절된다. 일반 SQL 두 세션의 native 호출이 서로의 로더 에러나 candidate state를 덮어쓰지 않는다.

## 3. 확정된 관측 공백: PL callback 이후 qlist balance 검사가 세션 전체에서 사라진다

`csc_has_method_callback_state()`는 현재 callback 안에 있는지, 몇 개의 list가 합법적으로 살아 있는지를 세지 않고 `method_callback_handler != nullptr`만 검사한다. handler는 첫 사용 때 생성되고 세션 teardown까지 유지된다. qexec의 list balance assert는 이 값이 true이면 모두 건너뛴다. 따라서 한 번 callback을 쓴 세션은 뒤의 일반 쿼리에서도 해당 누수 검사를 받지 않는다. [판별자](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/client_session_context.cpp#L126), [lazy 생성](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/method/method_callback.cpp#L1236), [qexec stand-down](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/query/query_executor.c#L17460)

이는 **현재 실제 list leak이 있다는 증거는 아니다.** 하지만 제품 수명 동안 증명해야 할 자원 귀속을 boolean 예외로 대체한 구현은 남아 있다. shell/HA가 모두 green이어도 이 검사는 문제를 보고하지 않도록 되어 있다.

**최소 구현:** callback kept handle이 소유한 list 수를 정확히 기록하고 outer query의 전후 delta에서 그 귀속분만 제외한다. handler close, deferred drain, transaction end, disconnect의 감소 규칙을 하나의 Interface에 모은다. 세션마다 넓게 검사 생략하는 boolean은 제거한다.

**완료 계약:** 정상 retained cursor는 오탐을 내지 않으며 callback 이후의 무관한 일반 SQL에서도 누수 검사가 유지된다. transaction end/close/disconnect 후 해당 소유 카운트는 0이고 취소·중첩 오류에도 균형이 맞는다.

## 4. 결함으로 단정하지 않는 필수 감사: 실행 상태와 할당 출처

CSC 도입 자체는 현재 들어가 있다. driver thread는 `csc_activate()` 후 연결의 request loop 전체를 수행하고 종료 때 `csc_deactivate()`한다. CSC mutex도 이 전체 기간 유지된다. CAS handle table과 CAS identity는 여전히 TLS다. 따라서 현재 안정성의 실질 계약은 “한 연결의 client-half는 같은 스레드에서 동기로 실행”이다. 헤더의 pooled worker 설명을 근거로 요청 스레드 이동이 이미 지원된다고 보면 안 된다. [driver_session.cpp:612](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L612), [request loop·retire](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L834), [CAS handle TLS](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_handle.c#L52)

PL callback은 같은 thread에서 `db_on_server`를 client 모드로 바꾸고 error-stack floor/libcas depth를 저장·복원한다. 또 `pgbuf_unfix_all()`은 callback 안에서는 outer executor의 pin을 지키기 위해 sweep을 생략한다. 이들은 필요한 조치이며 “누락됐다”고 다시 주장하면 안 된다. 다만 callback이 새로 만드는 자원과 outer executor가 원래 가진 자원을 구분하는 계약을 정밀하게 감사할 지점이다. [method_dispatch](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/method/query_method.cpp#L209), [page pin sweep 예외](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/storage/page_buffer.c#L3197)

메모리 쪽에서 workspace의 alloc/free는 CSC heap을 사용해 스레드 신원 문제를 해결했다. 그러나 일반 `db_private_alloc/free`는 **포인터의 할당 출처가 아니라 현재 bracket + `db_on_server` 모자**로 heap을 결정한다. `enter_server/exit_server`는 모자와 error stack만 전환한다. 즉 경계를 넘어 보존되는 포인터에는 여전히 “어디서 할당하고 누가 어느 모자로 해제하는가”라는 짝 계약이 필요하다. 현재 wrong-heap 재현 경로를 확인한 것은 아니다. [quick_fit.c:39](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/quick_fit.c#L39), [alloc 경로](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/memory_alloc.c#L468), [free 경로](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/memory_alloc.c#L815), [전환](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/communication/network_interface_cl.c#L149)

**필요 작업:** client→server→PL→client 재진입에서 반환/보존되는 DB_VALUE·list/cursor·prepared handle을 대상으로 소유자와 수명, 해제 함수를 명시한다. 확정 누락이 발견된 경로를 고치고 debug 귀속 검사를 넣는다. 모든 allocation에 header를 추가하는 전면 재설계부터 시작할 필요는 없다. C++ RAII guard는 상태 복원 규약을 한곳에 모을 수 있는 선택지지만 그 자체가 정확성 증명은 아니다. `cpp-perf-rules`의 ALLOC-08/A64 기준상 최적화보다 이 소유권이 우선이다.

**완료 계약:** nested success/caught error/propagated error/취소 후 CSC, auth user, `db_on_server`, error floor, libcas depth, caller의 page pin 상태가 정해진 값으로 돌아온다. retained 값은 명시된 owner가 살아 있는 동안만 참조한다. 실제 연결 모델을 유지한다면 pooling 전환은 후속 성능·확장성 결정으로 남겨도 된다.

## 5. 현재 코드에서 해소 확인한 과거 fog

| 과거 우려 | 현재 코드 판정 |
|---|---|
| method callback singleton이 cross-session handle을 보유 | `method_callback_handler`와 runtime args가 CSC 소유이고 CSC teardown에서 workspace보다 먼저 해제된다. [CSC 필드](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/client_session_context.hpp#L143), [teardown](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/client_session_context.cpp#L251) |
| MOP 포함 domain이 process cache에 살아남음 | MOP 가능 domain은 CSC `tp_domains`에 분리하고 workspace 종료 이후 sweep한다. 세션 도메인 UAF를 기존 결손으로 다시 올리지 않는다. [필드](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/client_session_context.hpp#L123), [순서](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/client_session_context.cpp#L280) |
| DDL log 전역 | `DDL_TLS`가 SERVER_MODE에서 thread_local이다. 현재 연결 thread 고정 계약 아래 격리된다. [ddl_log.c:110](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/ddl_log.c#L110) |
| 세션마다 cas_Shm_stub config를 쓰는 race | owner thread의 `cas_session_cfg` snapshot으로 옮겼고 pending config generation을 소비한다. [cas_server_support.cpp:180](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_server_support.cpp#L180) |
| class REVOKE 이후 다른 세션 prepared plan 그대로 실행 | SERVER_MODE `au_revoke_class()`가 `sm_touch_class()`로 CHN/XASL invalidation 경로를 태운다. 전체 auth 의미론 검증을 완료했다는 뜻은 아니지만 “무효화 구현 없음”은 현재 사실이 아니다. [authenticate_grant.cpp:705](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/authenticate_grant.cpp#L705) |
| CSC own-session 종료 시 자가 deadlock | own active context의 retire는 `orphaned` 표시 후 bracket exit에서 teardown한다. [client_session_context.cpp:293](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/client_session_context.cpp#L293) |
| SHOW metadata가 최초 연결 workspace에 귀속 | process-lifetime 별도 boot CSC로 빌드한다. [show_meta.c:996](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/parser/show_meta.c#L996) |

`sp_builtin_definition`의 MOP 보관과 parser 함수벡터 lazy-init도 보이지만, 전자는 확인한 caller가 createdb 전용이고 후자는 최초 파서 생성의 startup 순서까지 증명하지 않았다. 이를 현재 동시 SQL 결함으로 격상하지 않았다.

## 권장 구현 순서

1. **세션 격리 위반 제거:** cost override 등 실제 서버 전역 write를 각 의미론에 맞게 세션/컴파일/서버 관리 설정으로 귀속한다. 이 항목은 코드 수정이 필요한 확정 결손이다.
2. **native METHOD 지원 계약 확정 및 강제:** 유지한다면 loader 수명·동기화·ABI를 구현하고, 제외한다면 실행 전에 명확히 막는다. 계약 없이 현재 lazy dlopen 경로를 제품 지원으로 승인하지 않는다.
3. **중첩 실행의 자원 귀속 복원:** qlist kept-handle 카운트와 소유권 검사를 구현하고 callback error/pin/transaction 복원 규약을 한곳에 모은다. 실제 leak을 찾았다는 주장과 관측 공백 보완을 구별한다.
4. **cross-seam 포인터와 teardown 계약 감사:** 지금의 owner thread 모델을 명문화하고, 직렬화 제거/borrow/native XASL/worker-pool 등의 다음 변경은 그 계약을 입력으로 삼는다. 선택적 성능 작업보다 먼저 완료한다.

이 순서는 shell/HA TC 처리 일정을 대신하지 않는다. TC 결과와 별개로 제품이 지켜야 할 격리·지원 범위·수명 불변식을 코드에서 완성하는 순서다.
