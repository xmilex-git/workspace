# 폴드 이후 엔진 개발자에게 무엇이 바뀌는가

작성 2026-10-06. 대상: PR 7837(cas-merge)이 develop에 들어간 뒤 엔진 코드를 고치는 개발자. 근거: PR 7837 본문과 소스, 이 저장소의 #122·#123·#126·#118·#256 결정.

## 1. 무엇이 어디로 갔는가

지금까지 SQL은 `cub_cas` 프로세스 안의 클라이언트 라이브러리(`libcubridcs`)가 컴파일하고, 서버는 XASL을 받아 실행했습니다. 폴드 뒤에는 그 클라이언트 절반 — 파서, 컴파일러, 워크스페이스, 권한 검사, 트리거 관리자, 스키마 관리자, 클라이언트측 트랜잭션 상태 — 이 `cub_server`에 함께 컴파일됩니다(SERVER_MODE). 드라이버 요청은 서버 워커 스레드가 CAS 프로토콜(V12)을 직접 읽고, 같은 스레드에서 컴파일하고 실행합니다.

`libcubridcs` 자체는 그대로 남습니다. 관리 유틸리티(cub_admin 전부, loaddb·unloaddb·compactdb 포함)와 HA 데몬 4종만 그 경로로 서버에 붙고, 서버는 boot 등록 시 DB_CLIENT_TYPE 허용목록으로 일반·드라이버 타입을 거절합니다. 이 경로의 이름은 **유틸리티 채널**입니다(#126 D7/D8). `csql -S`도 변경이 없습니다.

접속 흐름은 다음과 같습니다.

1. 드라이버가 브로커에 붙습니다. 브로커는 accept, IP ACL, admission(잡큐)만 하고 연결 fd를 같은 호스트의 `cub_server`에 넘깁니다(`broker_direct.cpp`). 브로커 호스트와 DB 호스트가 같아야 합니다.
2. 서버가 연결을 입양하고(`adoption.cpp`), 세션을 만들며, 그 뒤의 모든 요청은 `driver_session.cpp`가 CAS 프로토콜로 처리합니다. V12 미만 드라이버는 이 시점에 거절됩니다.
3. HA 상태에 따라 받아도 즉시 reset될 조합(RW x standby 등)은 세션 수립 시점에 재시도 가능한 형태로 거절합니다(#121 D2).

## 2. 코드를 쓸 때 지켜야 하는 것

### 2.1 클라이언트 절반 코드에 프로세스 전역 가변 상태를 두지 않습니다

CAS 시절에는 프로세스가 곧 세션이라 전역 변수가 세션 상태였습니다. 이제 한 프로세스에 세션이 수천 개 있습니다. 클라이언트 절반이 들고 있던 전역은 두 곳으로 갔습니다.

- **`client_session_context`** (`src/object/client_session_context.hpp`): 세션이 소유하는 상태. 권한 컨텍스트(`au_context`), 워크스페이스(MOP 테이블·dirty 리스트·클래스명 캐시·lea 힙), 클라이언트측 트랜잭션 상태(`tm_Tran_*`), 스키마 관리자 상태(루트 클래스 MOP·디스크립터·current schema), 트리거 캐시, 객체 템플릿, savepoint 카운터, 실행 계획 트레이스, MOP를 품는 도메인 노드의 세션별 리스트 등이 멤버입니다. 소유자는 서버 세션(`session_state`)입니다.
- **스레드별 저장소**: 파서와 CAS 코드의 가변 전역(`cas_common_vars.*` 등)은 TLS로 갔습니다.

새 전역을 추가하면 다른 세션의 답을 조용히 바꿉니다. #256이 머지 뒤 과제로 적어 둔 "비세션 client-only 설정과 optimizer cost override의 전역 변경"이 바로 이 부류의 잔존 사례입니다.

### 2.2 워커 스레드는 세션에 붙어 있지 않습니다

`cub_server`는 요청마다 풀에서 워커를 꺼냅니다. 한 연결의 다음 요청이 다른 워커에서 돌고, 한 연결의 out-of-band 요청(인터럽트·로그라이터·메서드 콜백)이 동시에 다른 워커에 도착할 수 있습니다(#123 D3). 그래서:

- 세션 컨텍스트는 TLS에 두지 않습니다. 워커는 요청을 처리하는 동안만 **활성화 브래킷**을 통해 세션의 `client_session_context`에 접근하고, `thread_local`에는 브래킷만 실립니다.
- 브래킷은 전 구간 `bracket_mutex`를 잡습니다. 한 세션에 대한 클라이언트 절반 작업은 직렬입니다. 브래킷 밖에서 세션 상태를 만지는 코드는 잘못된 코드입니다.
- 요청 사이에 `thread_local`로 세션 정보를 캐시하지 않습니다.

### 2.3 실행 핫패스는 세션 객체 컨텍스트를 참조하지 않습니다

워크스페이스(SM_CLASS, MOP)는 컴파일러와 DDL이 쓰는 스키마 표현이자 DDL의 쓰기 경로입니다. 프로세스 경계가 사라졌다고 실행기(qexec·스캔·락)에서 그것을 읽기 시작하면 콜드 계층이 핫패스로 들어옵니다. 이 불변식은 리뷰 기준입니다(#123 D1).

### 2.4 MOP는 세션 경계를 넘지 않습니다

세션이 만든 MOP를 프로세스 공유 구조(캐시·도메인 노드·전역 리스트)에 넣으면 세션이 끝난 뒤 use-after-free가 됩니다. PR에서 이미 한 번 고친 부류(B4-D9: 도메인 캐시가 품은 워크스페이스 MOP)입니다. 반대 방향 — 프로세스 공유 객체를 세션 teardown이 해제하는 것 — 도 같은 사고입니다.

### 2.5 에러 스택과 메서드 호출

클라이언트 절반의 `er_stack_clearall`은 CAS 시절 자기 프로세스의 스택만 지웠습니다. 이제 서버 실행기의 프레임 위에서 돌므로 `er_dispatch_floor` 아래 프레임은 건드리지 않습니다. 메서드·PL 콜백은 CAS로 되돌아가지 않고 호출한 서버 워커 스레드가 동기 처리합니다(#120).

### 2.6 권한

권한 검사는 컴파일 시점에 그대로 있고(#118 D1), 세션 수립 핸드셰이크에서 서버가 `_db_user` 패스워드를 직접 검증한 신원만 참조합니다. 요청 안에 실린 사용자명이나 DBA 플래그를 믿는 코드는 쓰지 않습니다.

## 3. csql과 유틸리티

- 클라이언트·서버 모드 csql은 **thin csql**입니다. CCI 전송으로 CAS 프로토콜을 말하고, 결과 텍스트는 서버가 기존 포매터(`csql_result_format`)를 세션 워크스페이스 위에서 실행해 렌더링합니다(`csql_wire.*`, `cas_csql.cpp`). 세션 커맨드(`;schema` 류)도 같은 방식입니다. 클라이언트에서 stdout으로 내보내던 메시지("Statistics updated successfully", TRACE)는 `render_stdout`으로 보내야 thin 클라이언트가 봅니다.
- 로컬 csql은 브로커 없이 서버의 UNIX 소켓에 직결합니다. `csql -S`는 `libcubridsa` dlopen 그대로입니다.
- 유틸리티는 1절의 유틸리티 채널로 동작하며 코드 변경이 없습니다.

## 4. 운영 표면에서 달라진 것

TC와 운영 스크립트가 흔히 전제하는 것들입니다.

| 항목 | 폴드 뒤 |
|---|---|
| `cub_cas` 프로세스 | 없음(UNIX). APPL_SERVER=CAS 브로커는 항상 direct handoff |
| `cubrid broker status`의 CAS 행 | 없음 |
| per-CAS `sql_log` 파일 | 없음 |
| `broker_changer`의 CAS 실행 파라미터 | 서버 파라미터(cas_*)로 이동, broker_changer는 거절 |
| `killtran`·`tranlist`의 프로그램명 | `driver_session` |
| SHARD | 지원하지 않음(설정 오류) |
| Windows, cas_cgw | 기존 appl-server 풀 유지 |
| V12 미만 드라이버 | 접속 시 거절 |

## 5. 빌드·디버그

- 프로세스가 하나입니다. 드라이버 요청의 코어는 `cub_server` 코어이고, 컴파일 중 크래시도 거기서 납니다.
- CTP는 thin csql로 돕니다. CTP 통과는 드라이버 경로 전체의 통과를 겸합니다.
- `unit_tests/server_compile/`에 서버 내 컴파일 경로의 단위·스모크 테스트가 있습니다.

## 6. 머지 뒤 남는 과제(#256)

릴리스 전까지 끝내야 하는 것들입니다. 새 코드가 이 영역을 지나면 과제 상태를 먼저 확인하세요.

1. CAS 디코더 입력 검증(signed 길이)과 할당·SSL_CTX·컨텍스트 초기화 실패 회수
2. 비세션 client-only 설정과 optimizer cost override의 전역 변경 제거
3. cancel 대상 transaction index의 재사용 보호, 다중 DB/RESYNC identity, 조기 SESSION_END 회계
4. 요청·세션·서버 단위 자원 상한, PREPARE부터의 deadline, 활성 compile/execute 제한
5. native C METHOD: 서버 내 로더와 사용자 .so의 thread-safe 계약, 지원 범위 결정
6. 실행 계약 명문화(top-level / PL 재진입 / 유틸리티), qlist retained-handle 회계

메모리 쪽은 별도입니다. CAS 시절 프로세스가 들고 있어야 했던 상태(prepared 핸들, SM_CLASS 사본, TLS 블록, 출력·요청 버퍼)가 지금은 세션마다 복제돼 있고(연결당 0.3~0.6 MB), 공유 준비 객체·세대 교체 스키마 디스크립터로 옮기는 작업은 후속입니다(#237). 공유 객체의 pin은 세션 핸들 단위이고, 실행마다 refcount를 올리는 설계는 쓰지 않습니다.
