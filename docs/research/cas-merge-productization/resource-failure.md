# CAS 통합 제품화: 자원·취소·장애 경계 검토

검토 기준은 `xmilex-git/cubrid@d533969e4db6ef94d512d91f463790bab559790a`의 실제 소스이다. 빌드·실행·결함 재현은 하지 않았다. 아래의 **확정**은 해당 방어/소유권 처리가 소스에 존재하거나 빠져 있다는 뜻이며, 운영에서 서버 장애가 발생했다는 뜻은 아니다. 사용자 전제대로 shell/HA TC green은 별도로 놓았다.

제품화에서 먼저 필요한 것은 더 작은 연결당 메모리나 더 빠른 실행기가 아니라, **한 연결이 소비할 수 있는 자원과 실패가 반환되는 범위를 코드로 제한하는 일**이다. 이 변경은 CAS를 서버로 통합한다는 결정 안에서 가능하다. 연결당 스레드를 당장 풀로 바꾸거나 컴파일을 별도 프로세스로 되돌릴 필요는 없다.

## 1. 요청·컴파일·보관 객체의 바이트 예산 — 확정된 방어 공백, 제품 필수

현재도 제한은 있다. 접속 시 `css_increment_num_conn`으로 연결 수를 제한하고, 준비문 수도 `max_prepared_stmt_count`로 제한한다. 다만 이 둘은 **메모리 양**을 제한하지 않는다. [연결 입장 제한](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L914), [준비문 개수 제한](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_handle.c#L69).

실제 정상 요청은 최대 **1 GiB**까지 허용하며, 본문을 받기 전에 전체 크기를 `MALLOC`한다. 그 뒤 PREPARE에서는 SQL 문자열을 또 복사하고 파서가 노드/문자열 블록을 추가 할당한다. 파서 할당자는 실제 malloc 실패를 처리하지만 요청·세션·서버별 바이트 예산을 확인하지 않는다. 따라서 N개 연결의 큰 요청이 겹칠 때 연결 개수 제한과 1 GiB 상한만으로 DB의 공유 메모리를 보호하지 못한다. 이론상 100개의 최대 본문 할당만으로 100 GiB가 요구되며, 이는 실측 RSS 값이 아니다. [본문 상한과 선할당](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_dispatch.c#L69), [할당 위치](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_dispatch.c#L549), [SQL 복사](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_execute.c#L717), [파서 노드](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/parser/parse_tree.c#L219), [파서 문자열](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/parser/parse_tree.c#L379).

응답 버퍼도 커진 뒤 `net_buf_clear`에서 크기만 0으로 만들고 backing allocation은 세션이 끝날 때까지 보관한다. 오래 살아 있는 연결이 한 번 큰 결과를 받으면 그 high-water memory가 남는 구조다. [clear/destroy](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_net_buf.c#L65), [성장](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_net_buf.c#L419), [연결 종료 시 destroy](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L533).

구현 순서는 ① 수신 본문·응답 버퍼에 요청/서버 예산 예약·환급, ② 파서/옵티마이저 임시 메모리 예산, ③ 준비문·holdable 결과·세션 workspace의 보관 바이트 귀속이다. 초과 시 신규 요청을 명확한 오류로 거절하고 이미 시작한 변경은 정리해야 한다. 1 GiB를 무조건 낮추면 기존 대형 값 호환성이 깨질 수 있으므로, wire의 최대 값과 운영자가 정하는 동시 바이트 예산은 분리한다. 완료 조건은 "할당 실패가 나지 않았다"가 아니라 **동시 최대 입력에도 정해진 예산을 넘지 않으며 거절된 요청의 예약·핸들·트랜잭션 상태가 모두 환급되는 것**이다.

`driver_session.cpp:106`의 16 MiB `REQUEST_BODY_MAX`는 이 버전에서 참조되지 않는 상수다. 핸드셰이크는 고정 크기 `db_info`를 읽고, 정상 요청의 유효 상한은 `cas_dispatch.c`의 1 GiB이다. 두 상한을 혼동해서는 안 된다. [고정 핸드셰이크 읽기](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L577).

## 2. 식 깊이 제한을 전체 컴파일 스택 안전성으로 확장 — 확정된 범위 공백, 장애 발생 깊이는 미실측

문법의 `PT_MAX_NESTING_DEPTH=16384`는 expression의 깊이를 기록한다. CASE/DECODE 등의 합성 경로도 일부 보완되어 있다. 하지만 이것으로 전체 SQL 컴파일 스택이 제한되지는 않는다. 공통 walker는 노드별 자식뿐 아니라 `or_next`와 `next` 리스트까지 C 재귀 호출로 방문한다. SELECT는 select-list/from/where 등도 재귀 방문한다. 즉 중첩 서브쿼리뿐 아니라 긴 형제 노드 목록, 뷰/CTE 확장 및 rewrite가 만드는 트리도 따로 고려해야 한다. [expression guard](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/parser/csql_grammar.y#L462), [공통 walker의 next 재귀](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/parser/parse_tree_cl.c#L1077), [SELECT 자식 방문](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/parser/parse_tree_cl.c#L14808).

현재 alternate signal stack은 스택 오버플로 시 진단을 남기는 장치다. 요청을 정상 오류로 되돌리는 방어가 아니다. fatal handler는 기본 시그널 동작으로 돌아가고, debug abort handler는 서버 자체를 abort한다. 따라서 "8 MiB 스택 + 16384 + sigaltstack"을 제품의 입력 안전성 계약으로 삼을 수 없다. [alternate stack 의도](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/thread/thread_entry.cpp#L352), [fatal handler](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/executables/server.c#L212), [서버 abort](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/executables/server.c#L287).

최소 구현은 입력 문법·rewrite 결과·공통 walker에 동일한 노드/깊이 예산을 전달하고, budget 초과를 parser 오류로 반환하는 것이다. 긴 `next` 목록처럼 반복형으로 바꿀 수 있는 경로는 명시적 stack/반복으로 처리한다. 재귀를 전부 한꺼번에 제거할 필요는 없지만 오류 정리 경로도 같은 깊이에 안전해야 한다. 완료 조건은 **허용 깊이 이내 모든 지원 shape가 실제 서버 스택에서 동작하고, 제한 초과는 해당 문장만 오류로 종료**하는 것이다. 지도에서 "실사례가 나오면 방어"로 남은 서브쿼리 깊이 항목은 제품 출시 관점에서는 선행 작업으로 승격할 필요가 있다.

## 3. PREPARE부터 끝까지 취소 가능한 실행 예산 — 확정된 적용 범위 공백

취소 전달 자체는 구현되어 있다. 제어 채널이 트랜잭션 interrupt를 설정한다. 그러나 PREPARE의 `fn_prepare → ux_prepare → db_open_buffer → db_compile_statement`는 driver-session 스레드에서 직접 수행되며, 일반 PREPARE는 `set_query_timeout`을 호출하지 않는다. 해당 함수는 EXECUTE에서 호출하고 `tran_set_query_timeout`은 나중에 실행 함수로 전달할 timeout을 저장한다. 파서 공통 walker와 조사한 문법/옵티마이저 핵심 파일에는 이 interrupt/deadline을 정기적으로 확인하는 경로가 없다. 락 획득 등 서버 기능으로 내려가면 interrupt를 관찰할 수 있으므로 **컴파일 취소가 전혀 안 된다**가 아니라 **CPU만 사용하는 파싱/최적화 구간의 중단 지연 상한이 없다**가 정확하다. [취소 전달](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L1130), [prepare 진입](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_function.c#L274), [실제 compile](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_execute.c#L816), [execute timeout 설정](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_function.c#L612), [timeout 저장 계약](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/transaction/transaction_cl.c#L1320).

또한 연결당 생성한 스레드가 CAS dispatch와 `xqmgr_execute_query`를 직접 실행한다. `max_request_concurrency/max_request_worker`로 설정한 기존 request worker pool을 이 경로가 통과하지 않는다. 이것만으로 지원 용량에서 느리다는 결론은 낼 수 없다. 다만 연결 수 제한과 별도로 "얼마나 많은 컴파일/실행을 동시에 허용하는가"라는 제품 정책이 필요하다. [스레드 생성](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L968), [직접 dispatch](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_dispatch.c#L700), [직접 query execute](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/communication/network_interface_sr.cpp#L6245), [기존 worker pool 설정](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/server_support.c#L679).

최소 구현은 요청 컨텍스트의 monotonic deadline/cancel generation과 파서·옵티마이저의 안전한 중단 지점, 그리고 활성 compile/execute admission이다. admission 대기 중에도 취소 가능해야 하며 PL/trigger 내부 재진입이 자기 permit을 재획득해 교착하지 않도록 해야 한다. worker pool 전환은 이 계약을 충족하는 유일한 방법이 아니다. 완료 조건은 **큐 대기·컴파일·실행 각각에서 취소 응답 시간이 유한하고, 취소 뒤 해당 연결의 다음 요청 및 다른 연결이 정상 동작**하는 것이다.

## 4. 수신·송신의 절대 deadline과 느린 소비자 제어 — 확정된 I/O 공백, 로그의 광역 영향은 추가 감사

세션 시작 시 전달받은 fd에서 `O_NONBLOCK`을 제거한다. 본문 수신은 `net_read_stream`이 `read_buffer`를 반복하며 매번 같은 전체 상대 timeout으로 `poll`한다. 따라서 timeout보다 짧은 간격으로 조금씩 보내면 본문 전체 완료 시간에는 상한이 없다. 1번의 선할당과 결합하면 큰 본문 버퍼를 오래 보유할 수 있다. [blocking fd 전환](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L557), [부분 읽기 반복](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_network.c#L308), [매번 상대 poll timeout](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_network.c#L544).

송신도 `poll(POLLOUT)` 후 blocking `WRITE_TO_NET`을 실행한다. poll은 일부 쓰기 가능 상태를 알려줄 뿐 큰 blocking write의 완료 시간을 보장하지 않는다. 핸드셰이크의 `read_full/write_full`도 직접 blocking read/write loop다. 그러므로 query timeout만으로 느린 수신·송신 고객의 서버 자원 보유 시간을 제한할 수 없다. [송신 경로](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_network.c#L623), [핸드셰이크 helper](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L112).

최소 구현은 handshake/header/body/write 각 단계에 monotonic 절대 deadline을 부여하고, nonblocking I/O 또는 남은 시간으로 제한된 I/O를 사용하며, pending output byte cap을 메모리 예산과 연결하는 것이다. 끊을 때 cursor/holdable/transaction/slot이 정리되는 계약도 포함한다. **한 연결당 스레드라는 이유만으로 풀 재설계를 출시 blocker로 만들 필요는 없다.**

SQL/slow log는 같은 세션 실행 경로에서 동기 `fwrite/fflush/ftruncate`를 수행한다. 이는 느린 로그 저장소가 해당 세션을 오래 붙잡을 수 있다는 근거지만, 전체 DB 교착의 증거는 아니다. 제품 전 추가 감사 대상은 로그 I/O 중 공유 락·catalog/XASL pin·트랜잭션 락이 무엇을 유지하는지다. 이미 지도에서 로그 파일 구조 재설계는 후속으로 제외했으므로, 비동기 로그 전면 도입을 이번 필수로 제안하지 않는다. 필요한 경우에만 bounded queue·drop/error 정책 또는 락 밖 I/O로 좁게 개선한다. [동기 fwrite](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_log.c#L1334), [동기 truncate/flush](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_log.c#L1441).

## 5. OOM·할당 실패를 정상 세션 실패로 끝내기 — 일부 구체적 결함, 전체 감사 필요

새 접속 경로는 `ctx = new client_session_context()` 다음에 NULL 검사 없이 `csc_activate(ctx)`를 호출한다. 이 번역 단위 마지막에 포함하는 `memory_wrapper.hpp`는 SERVER_MODE의 명시적 `new`를 `cub_alloc`을 반환하는 **noexcept 할당**으로 치환한다. `cub_alloc`은 malloc 실패 시 NULL을 그대로 반환한다. 따라서 이 위치는 `bad_alloc`을 가정할 문제가 아니라, NULL이 `csc_activate`의 assert/`ctx->bracket_mutex.lock()`으로 들어가는 구체적 실패 경로다. [ctx 생성](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L612), [new 래퍼](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/memory_wrapper.hpp#L54), [cub_alloc](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/memory_cwrapper.h#L90), [ctx 참조](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/client_session_context.cpp#L53).

추가 감사 대상은 STL 컨테이너/문자열의 할당 실패와 접속 registry 삽입의 오류 경계다. `handle_handoff`의 registry 삽입은 오류 경계 밖에 있고, thread 생성만 `system_error`를 잡는다. 반면 accept의 channel map 삽입은 `bad_alloc`을 잡는다. 명시적 new와 STL 내부 allocator의 동작은 구분해서 점검해야 한다. [registry 삽입과 catch 범위](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L938), [accept 오류 처리](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L1449).

또한 `net_buf_realloc`은 realloc 반환값을 기존 포인터에 바로 덮어쓴다. 실패 시 원래 큰 버퍼를 해제할 참조가 사라져 누수가 되고, 세션 종료로도 그 할당을 회수하지 못한다. `net_decode_str`의 argv 성장도 같은 모양이다. CAS 프로세스 종료가 마지막 회수 장치였던 코드를 서버 내부로 넣었으므로, 이런 실패 경로의 의미가 달라진다. [응답 버퍼 realloc](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_net_buf.c#L428), [argv realloc](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_network.c#L433).

최소 구현은 알려진 할당 실패를 기존 오류 모델로 변환하고, 포인터/FD/입장 좌석/registry token의 실패 원자성을 보장하는 것이다. 모든 예외를 무조건 잡고 계속 실행하자는 뜻은 아니다. 메모리 훼손이나 엔진 invariant 위반은 여전히 프로세스 fatal일 수 있다. 제품 경계는 **잘못된 입력·예산 초과·일반 OOM은 해당 요청/세션 오류, 내부 훼손은 fatal**로 나눈다. 완료 조건은 각 단계의 강제 할당 실패에서 서버 생존과 예약/FD/메모리 환급이 모두 성립하는 것이다.

## 권장 구현 순서와 이번에 구현하지 않아도 되는 것

1. 작은 확정 결함부터 제거한다: OOM 포인터 유실, admission 예외 경계, malformed wire의 길이 검증(별도 프로토콜 보고 참조).
2. 가장 바깥 경계에 요청/응답 바이트 예약과 handshake/body/write 절대 deadline을 만든다.
3. 같은 요청 컨텍스트를 파서·옵티마이저에 전달해 메모리/노드/깊이/cancel 예산을 구현한다. 정리 경로까지 함께 다룬다.
4. 지원 max_clients 범위와 활성 compile/execute 제한을 확정하고, 준비문/holdable/workspace 보관 바이트를 포함한 제품 용량 계약을 닫는다.
5. 로그 I/O의 자원 보유 범위를 감사하고, 실제 광역 영향을 확인한 부분만 수정한다.

thread-per-connection 제거, prepared statement 전역 공유, XASL 직렬화 제거, 캐시라인/할당 횟수 최적화는 이 다섯 계약의 전제 조건이 아니다. 지도 PoC의 성능 이득은 해당 구현의 별도 채택 근거이며, 정상 입력의 YCSB 개선이나 연결당 idle 메모리 절감은 위의 최대치/실패 안전성을 대신 증명하지 않는다. `cpp-perf-rules`의 correctness > memory safety > performance 우선순위와 "최적화는 실측 후" 원칙에 따라, 여기서는 기존 구조를 지키는 최소 방어 구현을 우선한다.
