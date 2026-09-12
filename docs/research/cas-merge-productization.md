# CAS 통합 제품화 재평가 — 테스트 통과 이후 남는 코드·아키텍처 과제

- 조사일: 2026-09-12
- 기준: `xmilex-git/cubrid@d533969e4db6ef94d512d91f463790bab559790a` — 조사 시작 때의 [CAS 통합 PR](https://github.com/CUBRID/cubrid/pull/7837) head
- 질문/정본 결정: [CAS 통합 제품화 재평가 — 테스트 통과 이후 남는 코드·아키텍처 과제와 구현 순서](https://github.com/xmilex-git/workspace/issues/256)
- 전제: shell TC는 해결해 반영하고 HA는 feature branch 병합 후 manual test로 해결한다. 여기서는 두 검증이 모두 통과해도 남는 제품 구현 과제를 평가한다.
- 방법: 현재 소스와 기존 결정의 대조 및 독립 소스 감사. 엔진 수정·빌드·TC·장애 재현·새 성능 측정은 하지 않았다. 아래 **확정 결손**은 소스상 처리 누락/공유 경로가 확인됐다는 뜻이며, 운영 장애를 실측했다는 뜻은 아니다. 동시성 항목은 가능한 실행 순서를 제시한 정적 분석이다.

## 판단

**제품화 전에 남은 작업이 있다. 가장 먼저 완성할 것은 서버 안에서 실행되는 클라이언트 요청의 자원·상태·실패 계약이다.** 지금 구현은 실제 SQL/DDL/PL을 처리하는 통합체로서 성립하지만, 예전 CAS 프로세스의 수명·자원·전역변수 전제를 서버 안에서 모두 대체한 상태는 아니다.

핵심 질문은 세 가지다. 한 세션의 잘못된 입력이나 큰 작업이 어디까지 영향을 주는가, 세션이 끝나거나 취소된 뒤 무엇이 반드시 회수되는가, 예전에는 프로세스마다 달랐던 상태가 이제도 연결별로 독립적인가. 일반 회귀 TC가 통과해도 이 계약의 빈칸은 남을 수 있다. 이미 정한 멀티스레드 통합 방향 안에서 해결할 수 있는 작업들이다.

## 구현 우선순위

| 순서 | 제품화 작업 | 현재 판정 | 최초 구현 단위 | 완료 조건 |
|---|---|---|---|---|
| 1 | 잘못된 wire 입력·일반 OOM·초기화 실패를 요청/세션 실패로 처리 | 길이 검증·할당 실패 처리의 구체적 결손 | decoder의 중첩 길이/개수/진행 보장, realloc·TLS·context 초기화 실패 회수 | 입력/할당 실패가 DB 전체 종료나 무한 처리로 번지지 않고 FD·예약·메모리가 회수됨 |
| 2 | 컴파일 설정과 실행 상태의 연결별 독립성 | client-only 설정·cost 함수 포인터의 전역 변경 확인 | 설정 분류표, 세션 저장/조회, 컴파일 시작 시 설정 snapshot | A의 설정·종료가 B의 컴파일 의미와 비용모델에 영향을 주지 않음 |
| 3 | 접속·취소·종료·재시작의 동일한 세션 수명 계약 | 재사용 identity와 RESYNC 순서에 정적 결손 | registry의 수명 보호, 취소 대상 식별, snapshot/END 일관성 | 다른 세션 취소 0, live 세션과 슬롯 회계 일치, 종료 후 참조/좌석 잔류 0 |
| 4 | 요청 전체의 바이트·시간·동시 작업량 제한 | 개수 제한은 있으나 바이트/전체 deadline/컴파일 취소 공백 | outer I/O 예산 → compiler budget/cancel → retained object 회계 | 지원 용량에서 큰 입력·느린 클라이언트·compile 폭주를 유한 자원으로 처리/거절 |
| 5 | native C METHOD의 제품 지원 계약 | 서버 내부 로딩/실행과 무잠금 전역 로더 확인 | 지원 여부 결정 후 로더/ABI/배치 계약 구현 또는 명시적 거절 | 기존 CAS용 라이브러리를 그대로 안전하다고 간주하는 경로가 없음 |
| 6 | 유지보수 가능한 요청 실행 인터페이스와 운영 진단 | context/hat/TLS 조합의 암묵적 계약이 다수 | 기존 진입점에 request scope를 모으고 수명/설정/예산/에러 복원 책임을 명시 | 새 SQL 경로가 같은 계약을 통과하며 운영자가 소유 세션·단계·잔류 자원을 추적 가능 |

1~3은 이미 확인한 코드 결손부터 수정할 수 있다. 4~5의 제품 정책은 병렬로 정하고, 6의 인터페이스 정리는 앞 작업을 수용하는 만큼 진행한다. 큰 리팩터링을 끝내야 작은 수정이 가능하도록 순서를 뒤집을 필요는 없다.

## 1. CAS가 제공하던 실패 격리를 코드로 대체해야 한다

### wire parser: 바깥 메시지 크기 검사만으로 부족하다

`cas_process_request`는 전체 body 크기를 검사한 뒤 `net_decode_str`를 호출한다. 그런데 decoder는 인자 길이를 signed 정수로 읽고 `남은 크기 < 인자 길이`만 검사한다. 음수 길이를 거부하지 않아 포인터가 뒤로 움직이거나 처리 위치가 진행하지 않는 경우가 가능하다. 이는 서버 안에서 반복 파싱·argv 성장으로 이어질 수 있는 구체적인 결손이다. [dispatch 진입](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_dispatch.c#L549), [decoder](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_network.c#L395).

이 decoder의 동일한 구조는 조사일 upstream develop에도 존재한다. 따라서 모든 결함의 발생 원인을 CAS 통합으로 귀속해서는 안 된다. 제품화 책임은 **그 코드가 이제 데이터베이스 서버의 주소공간과 자원을 직접 사용한다는 것**에 있다. 먼저 구조적 wire validator에서 인자 길이·개수·덧셈 overflow·전진 보장을 확인하고, 함수별 인자의 크기/문자열 종료/중첩 데이터 검증을 같은 기준으로 감사해야 한다.

### OOM/초기화 실패: 프로세스 종료가 하던 회수가 사라졌다

`net_buf_realloc`과 decoder의 argv realloc은 반환값으로 원래 포인터를 덮어써, 실패 시 기존 할당 참조를 잃는다. `driver_session_run`의 context 생성 후 NULL 검사도 없다. 이 빌드의 명시적 `new` wrapper는 `noexcept`로 malloc 실패를 반환할 수 있으므로, 모든 실패가 자동으로 C++ 예외 처리에 들어간다고 가정할 수 없다. TLS 초기화도 성공 경로의 `SSL_CTX` 참조 해제와 실패 경로 해제가 비대칭이다. [응답 버퍼](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_net_buf.c#L419), [context 생성](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L612), [allocation wrapper](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/memory_wrapper.hpp#L50), [TLS 초기화](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_ssl.c#L141).

예상 가능한 입력 오류·예산 초과·할당 실패는 요청 또는 세션 오류로 정리하고, 내부 공유 상태 훼손은 기존 fail-fast 정책을 유지하는 것이 맞다. 시그널을 잡아 손상된 서버를 계속 실행시키는 방식은 해결책이 아니다. 구현은 FD/SSL/context/registry/admission의 취득·양도·환급 단계를 한곳에서 관리하는 작은 수명 단위부터 시작한다.

## 2. 프로세스 전역 상태를 서버에 옮긴 뒤의 의미가 아직 완전히 정리되지 않았다

### 비세션 client-only 설정

`default_histogram_bucket_count`는 현재도 `PRM_FOR_CLIENT | PRM_USER_CHANGE`이며 세션 파라미터가 아니다. 조회 함수는 `PRM_SESSION_READTHROUGH`일 때만 세션 값을 읽고, 나머지는 전역 `prm_Def`를 읽는다. 설정 변경도 `PRM_FOR_SESSION`이 아니면 전역값에 저장한다. UPDATE STATISTICS/ANALYZE의 기본 bucket 수는 이 경로를 사용한다. 따라서 단순히 thin csql에서 SET을 전달하는 것만으로 연결별 기존 의미를 보존하지 못한다. [정의](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/system_parameter.c#L5427), [조회](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/system_parameter.h#L884), [저장](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/system_parameter.c#L9815), [소비자](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/query/execute_schema.c#L4327).

이 과제는 이미 [비세션 client-only 컴파일 설정 — 연결별 격리와 클라이언트 설정 전달](https://github.com/xmilex-git/workspace/issues/235)에 있으므로 새로 중복 티켓을 만들지 않는다. 제품 우선순위를 올려야 한다. 컴파일 의미를 바꾸는 설정, 서버 운영 설정, 세션에서 변경 가능한 설정을 분류하고 저장·조회·초기 전달·재접속 기본값을 함께 닫는다. 캐시 키/무효화도 의미를 바꾸는 설정과 일치해야 한다.

### optimizer cost override

folded csql의 `;set cost`는 `qo_plan_set_cost_fn`으로 이어지고, 그 함수는 전역 `all_vtbls[].cost_fn`을 변경한다. 다른 세션의 optimizer가 같은 함수 포인터를 읽는다. 세션별 `bracket_mutex`는 서로 다른 세션 사이의 이 변경을 보호하지 않는다. [csql 진입](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/executables/csql.c#L3098), [전역 변경](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/optimizer/query_planner.c#L5494), [optimizer 소비](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/optimizer/query_planner.c#L794).

최소 해법은 cost override를 세션/compile snapshot으로 옮기거나, 지원하지 않는 debug 명령으로 명확히 거절하는 것이다. 전역 mutex만 추가하면 데이터 레이스는 줄여도 A가 B의 비용모델을 바꾸는 의미 문제는 남는다. 이 예를 기준으로 mutable singleton을 감사하되 이미 세션화한 모든 모듈을 다시 작성할 필요는 없다.

## 3. 취소·종료·브로커 재시작을 하나의 수명 모델로 완성해야 한다

현재 registry, 취소 토큰, RESYNC, 종료 전 identity 제거 등 보호 장치는 이미 있다. 다만 정적 감사에서 다음 순서 문제가 남는다. 상세 근거는 [접속·배포 감사](cas-merge-productization/deployment-security.md)에 있다.

- **취소 대상 재사용:** token에서 tran_index를 찾은 뒤 registry mutex를 풀고 interrupt를 설정한다. 그 사이 종료가 index를 해제하고 새 세션이 재사용하면 다른 트랜잭션을 겨냥할 수 있다. 해결에는 대상의 세대/수명 보호가 필요하다.
- **다중 DB 취소 식별:** 서버별로 발급되는 token을 브로커가 함께 관리한다. 재시작 후 복원에서 client port가 사라지면 같은 IP의 여러 DB에서 같은 token을 구분하지 못할 수 있다. STATUS 경로도 보유한 session identity를 충분히 사용하지 않는지 함께 수정해야 한다.
- **RESYNC와 종료의 경쟁:** snapshot을 만든 뒤 실제 token 삽입 전 SESSION_END가 도착할 수 있다. 정상 handoff는 먼저 온 종료를 소비하지만 RESYNC 복원은 그 처리가 달라 이미 끝난 세션을 슬롯 회계에 되살릴 수 있다.

제어 채널의 blocking send가 send mutex를 보유하고 stop도 같은 mutex를 요구하는 경로, 세션 drain timeout 후 엔진 종료와 남은 실행의 관계도 추가 감사 대상이다. 이 두 항목은 실제 정지/자원 사용 오류를 재현한 결함으로 올리지 않았다.

위 identity/RESYNC 항목은 아직 실행 재현한 장애가 아니라, 소스에서 성립하는 interleaving이다. 설계 완료 조건은 **취소가 원래 세션만 대상으로 하고, END가 중복/지연/선도착해도 한 번만 회수되며, 복원 뒤 live registry와 admission 회계가 일치하는 것**이다. wire 변경 없이 브로커 내부 handle과 서버 내부 generation/lifetime을 보강할 수 있는 범위부터 정한다. 이미 선행 수정한 재시작 슬롯 누수를 포괄적으로 '미해결'이라 부르지 않고, 이번에 확인한 복원 순서의 잔여 문제만 다룬다.

## 4. 서버 내부 컴파일러에 자원 상한과 취소 계약이 필요하다

현재 연결 수와 prepared statement **개수**의 제한은 존재한다. 그러나 개수 제한은 서버 전체의 바이트 사용량이나 활성 작업량을 보장하지 않는다.

- 실제 CAS 요청 body 상한은 **1 GiB**이며 전체 크기를 먼저 할당한다. 소스에 남은 16 MiB `REQUEST_BODY_MAX`는 이 버전에서 사용되지 않는다. 파서 arena·SQL 복사·응답 buffer·보관 핸들을 합친 요청/세션/서버 바이트 예산이 필요하다. 이 값은 요청 상한이지 실제 RSS 실측값이 아니다.
- TLS와 본문 수신은 blocking 경로가 있고, 부분 read마다 상대 timeout을 다시 적용한다. 조금씩 계속 수신하는 경우 전체 body 완료 시간에는 상한이 없다. 송신의 poll 뒤 blocking write도 전체 응답 완료 deadline과 같지 않다.
- 일반 PREPARE에는 EXECUTE와 같은 timeout 설정이 없고, CPU만 사용하는 파서/옵티마이저 구간에는 중단 지연 상한이 확인되지 않았다. 락 대기 등에서 interrupt를 읽을 수 있으므로 '취소가 전혀 없다'는 뜻은 아니다.
- expression 깊이 가드는 있지만 서브쿼리·긴 next 목록·rewrite 결과·오류 정리의 전체 C stack 사용을 제한하지 않는다. `sigaltstack`은 진단 장치다.
- driver session thread는 기존 request worker pool을 통하지 않고 직접 컴파일/실행한다. 기존 `max_request_concurrency`와 제품의 SQL 활성 작업량을 동일하게 볼 수 없다.

[자원·취소 감사](cas-merge-productization/resource-failure.md)에 각 call path와 기존 방어를 기록했다. 최소 구현은 **요청 컨텍스트에 byte budget·monotonic deadline·취소 상태를 두고, admission/수신/컴파일/실행/송신이 이를 함께 사용하는 것**이다. PL/trigger 재진입은 부모 요청의 트랜잭션·예산을 승계하고 permit을 중복 획득하지 않아야 한다. 요청 종료 후 살아남는 prepared/holdable 객체는 세션 보관 예산으로 소유권을 넘긴다.

지원 용량 내에서 이 계약을 만족하면 연결당 스레드 모델을 첫 출시에서 유지할 수 있다. shared worker pool로의 변경은 세션 affinity, TLS, allocator 소유권을 다시 바꾸므로 별도 근거가 필요하다. 메모리 상수는 이번에 임의로 정하지 않는다. [메모리 footprint 결정](https://github.com/xmilex-git/workspace/issues/237)의 실제 바이트 귀속을 입력으로 제품 상한을 정한다.

## 5. native C METHOD는 지원 정책 자체가 제품화 선결이다

현재 SQL의 native method 경로는 `method_invoke_builtin_internal → obj_send_array → sm_link_method → sm_dynamic_link_class → dl_load_object_module`로 이어진다. 이 로더와 사용자 함수가 이제 서버 프로세스에서 실행된다. `dl_Loader/dl_Errno` 및 후보/handler 배열은 전역이고 정상 SQL 중 동시 load/resolve를 직렬화하는 보호가 확인되지 않는다. [동적 로딩 경로](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/schema_manager.c#L1197), [전역 로더](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/base/dynamic_load.c#L189), [세션·확장 코드 감사](cas-merge-productization/session-contracts.md).

로더 잠금을 고쳐도 기존 라이브러리의 mutable static, 비재진입 함수, `exit/abort`, 메모리 손상까지 안전해지지는 않는다. 예전 CAS에 배치하던 라이브러리의 서버 호스트 배치와 ABI도 달라진다. 따라서 첫 출시에서 지원한다면 thread-safe/reentrant ABI와 신뢰·배치·로딩 정책을 명시하고 필요한 코드 보호를 구현해야 한다. 지원 준비가 안 됐다면 조용히 기존 경로로 실행하기보다 명확히 거절하고 이행 조건을 제시해야 한다.

지원/제외의 제품 선택은 사용자 결정으로 남긴다. 컴파일러를 별도 프로세스로 분리하는 기각 노선을 다시 여는 권고가 아니다. 이 질문은 [native C METHOD 지원과 서버 내 실행 안전성 결정](https://github.com/xmilex-git/workspace/issues/258)에 분리했다.

## 6. 유지보수: '모두 세션화했다'를 지속적으로 지킬 인터페이스가 필요하다

현재 `client_session_context`는 세션의 durable state를 모으고 `csc_activate/deactivate`로 접근한다. 이것은 필요한 기반이며 유지한다. 동시에 `db_on_server`, error-stack floor, CAS/CSQL TLS, private heap, nested callback state가 여러 진입점의 호출 순서에 의존한다. CSC 헤더의 pooled worker 설명과 실제 driver session의 전용 thread 모델도 구별해 문서화해야 한다. [CSC 계약](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/client_session_context.hpp#L19), [bracket 구현](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/client_session_context.cpp#L52), [전용 thread](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L480).

권장 구현은 거대한 컴파일러 재작성보다 작은 request-execution 인터페이스다. 호출자는 세션·요청 종류·입력·deadline을 제공하고, 내부에서 CSC/트랜잭션/할당/에러/취소 상태를 연결하며, 모든 반환 경로에서 복원한다. top-level, PL 재진입, utility 경로의 차이는 이 인터페이스의 명시적 계약으로 남긴다. 기존 연결 단위 CSC bracket을 요청마다 무조건 중첩 활성화하면 현재의 비중첩 규약을 위반하므로, scope는 이미 가진 소유권을 승계하는 경우를 구별해야 한다. 내부 함수 전체에 새로운 추상 계층을 강제할 필요는 없다.

특히 callback 상태가 한 번 생긴 세션은 qlist balance assert를 우회하는 경로가 있다. 이것은 누수 발생의 증거가 아니라 **누수 회계가 닫히지 않은 증거**다. 요청·kept handle·세션 보관 객체의 소유자를 구분해 정밀 회계로 대체해야 한다. [현재 stand-down](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/query/query_executor.c#L17465).

운영 진단에도 같은 identity를 사용한다. SHOW SESSION STATUS와 기존 로그는 이미 있으므로 '관측 수단이 없다'고 할 수는 없다. 추가 예산·deadline·admission을 구현할 때 세션/요청별 사용 바이트, 처리 단계, 대기·취소 이유, 준비문·holdable 잔류를 기존 진단에 연결해야 한다. 현재 SHOW snapshot은 registry mutex로 slot 포인터 수명을 보호하지만 slot의 counter/string writer와 동기화하지 않는다고 코드가 명시한다. 단순히 오래된 통계를 허용하는 것과 C++ data race를 허용하는 것은 다르므로, 새 계측 전에 owner-published snapshot 또는 적절한 atomic/잠금으로 관측 계약을 보완해야 한다. [현재 snapshot](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L129). 예전 CAS PID/RSS/restart만으로 세션 문제를 설명하던 운영 모델은 그대로 적용할 수 없다.

## 이미 해결된 것과 첫 출시 필수가 아닌 것

과거 지도 fog를 현재 결손으로 그대로 옮기지 않았다. `cas_Shm_stub`의 세션별 write는 현재 thread-local config snapshot으로 분리되어 있고 pending config도 소유 세션 thread가 적용한다. method callback handler는 CSC 소유이며, DDL 로그 상태도 TLS화되어 있다. MOP를 품는 domain cache는 세션별로 분리하고 teardown에 연결했다. [config snapshot](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_server_support.cpp#L180), [callback/domain 소유권](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/object/client_session_context.hpp#L128).

다음은 성능·메모리 개선 후보로 의미가 있지만, 위의 안전성·수명 계약을 만들기 위한 필수 선행조건은 아니다.

- 세션 간 prepared statement 공유와 compiler catalog 표현 통합.
- native XASL 정본과 실행별 state 분리, 직렬화 제거.
- 연결당 thread 제거, 모든 로그의 비동기화.
- PoC U1 lock fastpath, U3 classrepr pin 등 별도 서버 성능 개선.

특히 측정용 PoC는 제품 구현과 동일하지 않다. U1은 강한 락·승격/강등·rollback/lock 관측 경로, U3 pin은 DDL/decache/스레드 종료 수명, body alias·첫 페이지 slot은 재컴파일/holdable/PL 재진입/에러 정리에서 원본 생존을 증명해야 한다. P6는 immutable plan과 mutable execution state, 캐시 invalidation, reclaim 계약이 필요하다. YCSB 수치가 좋아도 이 작업은 별도로 남는다. [기존 PoC 처분 기록과 조건](https://github.com/xmilex-git/workspace/issues/253), [U1 결정](https://github.com/xmilex-git/workspace/issues/246), [U2/U3 결정](https://github.com/xmilex-git/workspace/issues/248), [바인드/스크래치 결정](https://github.com/xmilex-git/workspace/issues/249).

브로커·DB 동일 호스트, V12 드라이버, SHARD 미지원, 원격 thin csql의 특권 모드 제약 등은 기존의 명시적 결정이다. 이를 모두 구현 누락으로 세지 않는다. 다만 첫 제품의 지원 표와 설치/업그레이드 사전 검사가 그 선택을 실제로 강제해야 한다. rolling upgrade나 구버전 관리 도구 호환성을 제공하려면 별도 호환 작업이 필요하며, 이미 제공된다고 가정해서는 안 된다.

## 지도에 반영한 결정과 다음 입력

- **D1:** 이 조사의 결론은 제품 출시 가능 판정이 아니라, 확인된 결손과 추가 제품 계약에 기반한 구현 우선순위다. CI/HA 완료로 이 목록이 자동 소멸하지 않는다.
- **D2:** 먼저 입력/실패 처리·설정 격리·수명 경쟁을 보강하고, 요청 자원/취소 계약을 구현한다. native METHOD 지원 정책을 동시에 확정한다.
- **D3:** 기존 멀티스레드 통합·wire 호환·per-session workspace 결정을 유지한다. 공유 prepared/XASL/worker pool 최적화는 안전성 작업과 독립적으로 채택한다.
- **D4:** 기존 설정/메모리 티켓을 재사용한다. 이번 조사에서 선명해진 제품 정책 질문은 [요청 자원 상한·컴파일 취소·실패 범위 결정](https://github.com/xmilex-git/workspace/issues/257)과 [native C METHOD 지원과 서버 내 실행 안전성 결정](https://github.com/xmilex-git/workspace/issues/258)에 둔다. 사용자 대신 지원 범위나 수치 예산을 확정하지 않았다.

상세 코드 감사: [세션·확장 코드](cas-merge-productization/session-contracts.md), [자원·취소·실패](cas-merge-productization/resource-failure.md), [접속·배포](cas-merge-productization/deployment-security.md). 신규 TC 구현은 기존 지도 정책대로 QA가 담당하며, 여기의 완료 조건은 후속 단일 test.md의 입력이다.
