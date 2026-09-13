# PostgreSQL의 접속·세션 수명과 CUBRID AUTO 호환 적용안

조사일: 2026-09-13. 담당: Codex 리드 직접 소스 독해. 빌드·실행·성능 측정 없음.

작업: [CAS 통합 제품화 준비 — 코드·아키텍처 6대 과제 통합](https://github.com/xmilex-git/workspace/issues/259).

## 결론

PostgreSQL 본체에는 일반 SQL 세션을 다른 클라이언트에 빌려주는 풀이 없다. 접속마다 backend 프로세스를 만들고, 그 backend가 같은 연결의 요청을 반복 처리하다 연결 종료 시 종료한다. 접속 수 초과는 거절한다. 많은 클라이언트를 적은 backend로 처리하는 것은 PgBouncer 같은 외부 풀러의 역할이다.

CUBRID에 적용할 것은 PostgreSQL의 프로세스 모델보다 **세션 상태의 소유권, 메시지/트랜잭션 자원의 정리 경계, 접속과 실행 용량의 별도 회계**다. 기존 AUTO 호환을 목표로 한다면 PgBouncer transaction pooling의 세션 기능 제한을 가져올 수 없다. 논리 세션의 보존·재연결을 먼저 설계하고 실행 자원 재사용 범위를 결정해야 한다. 풀만 추가하는 변경으로는 현재의 접속 슬롯 상한이나 세션 수명 결합이 해소되지 않는다.

이 문서는 조사 결과와 설계 권고다. 풀 도입·새 설정·타임아웃 수치·제품 정책을 확정하거나 구현 완료로 판정하지 않는다.

## 조사 기준

| 대상 | 고정 기준 | 방법 |
|---|---|---|
| PostgreSQL | `/home/cubrid/dev/postgres`, `5713b437abed7085e7d59849c6e9e0f4f469633d`, configure.ac의 `20devel` | 로컬 소스·동봉 SGML 직접 확인 |
| CUBRID 통합 | `/home/cubrid/dev/worktrees/wf235-final`, `67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437` | 로컬 소스 직접 확인 |
| CUBRID 기존 CAS | `/home/cubrid/dev/cubrid`, `develop`의 `c3967ec22` | 기존 AUTO 선택·연결 교체 경로 확인 |
| PgBouncer | 2026-09-13 열람 공식 features/config 문서 | 문서 조사. 로컬 구현 및 실행은 미검증 |

PostgreSQL의 `/docs/current/` 웹 문서는 열람 시 18 문서로 표시됐다. 아래 내부 함수·슬롯 계산·메모리 구현 설명은 로컬 **20devel의 고정 커밋**을 기준으로 한다. 외부 풀러 문서의 기본값을 CUBRID 설정값으로 채택하지 않는다.

## 1. PostgreSQL 본체는 어떻게 처리하는가

### 1.1 접속마다 backend 하나

호출 경로는 `postmaster accept → BackendStartup → postmaster_child_launch → BackendMain → InitProcess → PostgresMain`이다. backend는 `PostgresMain`의 루프에서 같은 소켓의 명령을 읽는다. EOF/Terminate는 `proc_exit(0)`으로 끝난다. 연결 간 backend 재배정 경로가 아니다.

근거: [BackendStartup](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/postmaster/postmaster.c#L3576), [BackendMain](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/tcop/backend_startup.c#L76), [명령 대기](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/tcop/postgres.c#L4867), [연결 종료](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/tcop/postgres.c#L5159). [공식 구조 문서](https://www.postgresql.org/docs/current/connect-estab.html)도 같은 모델을 설명한다.

따라서 유휴 연결도 backend와 접속 슬롯을 계속 보유한다. 쿼리가 끝났다는 이유로 그 backend가 다른 클라이언트를 받지 않는다. parallel/background worker는 이 일반 접속 backend 재사용 문제와 별개다.

### 1.2 슬롯 부족은 접속 오류

`InitProcess`는 일반 backend용 `PGPROC` free list에서 엔트리를 가져온다. 없으면 `ERRCODE_TOO_MANY_CONNECTIONS`로 해당 backend를 종료한다. 인증 후에는 관리자/예약 권한용 잔여 슬롯을 추가 검사한다. 이 경로에는 기존 CUBRID의 idle CAS 양보나 빈자리 대기 잡큐가 없다. 커널 listen backlog·인증 전 처리와 SQL backend 입장 대기는 구분해야 한다.

근거: [PGPROC 취득·부족 거절](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/storage/lmgr/proc.c#L435), [예약석 검사](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/utils/init/postinit.c#L979).

`pmchild_pools`와 `freeProcs`라는 이름은 주의해야 한다. 이들은 프로세스 추적/공유 제어 구조체의 슬롯 풀이다. 기존 SQL 세션·살아 있는 backend를 빌려주는 풀이 아니다. 이 checkout의 일반 child 추적 슬롯은 인증 중 접속 등을 위해 `2 * (MaxConnections + max_wal_senders)`이고, 실제 일반 backend 제한은 별도 PGPROC 배열에서 적용한다. 따라서 child 추적 슬롯 수를 SQL 수용량으로 읽으면 틀린다. [pmchild 설명](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/postmaster/pmchild.c#L101), [종료 시 PGPROC 반환](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/storage/lmgr/proc.c#L1079).

### 1.3 유휴 타임아웃은 세션 종료

`idle_session_timeout`은 트랜잭션 밖에서 기다리는 세션을 시간 기준으로 종료하며 기본 0은 비활성이다. 만료 시 FATAL 경로로 연결을 끝낸다. 새 접속이 기다린다는 압력에 따라 자리를 양보하거나, 종료한 세션을 새 backend에서 복원하는 기능은 아니다.

근거: [설정 정의](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/doc/src/sgml/config.sgml#L10822), [idle timer 설정](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/tcop/postgres.c#L4815), [만료 처리](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/tcop/postgres.c#L3668).

### 1.4 같은 backend 안에서는 수명을 나눠 재사용

| 자원 | PostgreSQL 처리 | CUBRID에 주는 입력 |
|---|---|---|
| 메시지 임시 메모리 | `MessageContext`를 명령 루프마다 reset | 요청 종료 시 회수할 객체와 보관할 객체를 구분 |
| 트랜잭션 메모리 | `TopTransactionContext` 자체를 남기고 commit에서 reset | 자원 소유 컨테이너 재사용과 세션 재사용은 별개 |
| 저장된 준비문 계획 | `CacheMemoryContext` 밑으로 옮겨 메시지보다 오래 보관 | 준비문·결과·workspace를 무조건 요청 arena와 함께 해제하지 않음 |
| 락·버퍼 pin 등 | `ResourceOwner`와 트랜잭션 종료 훅으로 순서 있게 정리 | 메모리 reset만으로 실행 자원 반환 완료라고 판단하지 않음 |

근거: [MessageContext 생성](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/tcop/postgres.c#L4526), [명령별 reset](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/tcop/postgres.c#L4716), [트랜잭션 reset](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/access/transam/xact.c#L1653), [계획 보관](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/utils/cache/plancache.c#L568), [ResourceOwner 정리 순서](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/access/transam/xact.c#L2434).

이 재사용은 **같은 backend의 세션 안에서** 일어난다. `CacheMemoryContext`가 모든 backend의 공유 계획 캐시라는 뜻도 아니다. PostgreSQL의 process-global 상태·sigsetjmp 오류 복구를 CUBRID의 멀티스레드/C++ 호출 프레임에 그대로 이식할 수 있다는 근거가 아니다.

## 2. PgBouncer가 추가하는 계층

PostgreSQL 동봉 문서도 다수 접속의 메모리 문제에 외부 connection pooler를 대안으로 제시한다. [runtime.sgml](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/doc/src/sgml/runtime.sgml#L1384).

PgBouncer는 클라이언트 연결과 PostgreSQL backend 연결을 별도로 관리한다.

| 모드 | backend 반환 시점 | 이번 문제와의 관계 |
|---|---|---|
| session pooling | 클라이언트 연결 종료 | 연결이 살아 있는 유휴 클라이언트의 점유는 풀지 못함 |
| transaction pooling | 트랜잭션 종료 | 다수 클라이언트를 소수 backend에 배정하나 세션 기능 제약 |
| statement pooling | 문장 종료 | 다중 문장 트랜잭션 불허로 기존 CUBRID 대체 부적합 |

Transaction pooling은 임의의 세션 SET/RESET, WITH HOLD cursor, SQL PREPARE/DEALLOCATE 등을 일반적으로 보존하지 않는다. 일부 설정 추적과 프로토콜 준비문 지원은 별도 기능이다. [공식 기능표](https://www.pgbouncer.org/features.html).

설정은 클라이언트 수와 backend 수를 따로 제한한다. 풀은 DB/사용자 단위로 구분되며 대기 시간 제한도 제공한다. 프로토콜 준비문은 `max_prepared_statements`를 활성화하면 추적·이름 변환·필요 시 재준비한다. 임의 SQL 세션 상태 전체를 저장·복원하는 기능은 아니다. Session pooling의 반환 정리는 기본 `DISCARD ALL`이고 transaction pooling에서는 기본적으로 그 reset을 실행하지 않는다. [공식 설정](https://www.pgbouncer.org/config.html).

PostgreSQL wire는 `ReadyForQuery`에 `I`(트랜잭션 밖), `T`(진행 중), `E`(실패한 트랜잭션)를 명시한다. `ReadyForQuery`가 왔다는 사실만으로 트랜잭션이 끝났다고 판단하면 안 된다. [송신](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/tcop/dest.c#L268), [상태 코드](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/access/transam/xact.c#L5057).

`DISCARD ALL`은 다음 클라이언트를 위해 backend를 초기화한다. A의 상태를 보존해 나중에 A에게 복원하는 것과 다르다. 실제 구현은 설정·준비문·portal·세션 advisory lock·임시 테이블·sequence cache 등을 정리한다. [DiscardAll](https://github.com/postgres/postgres/blob/5713b437abed7085e7d59849c6e9e0f4f469633d/src/backend/commands/discard.c#L57).

## 3. CUBRID에서 그대로 적용할 수 없는 이유

### 3.1 기존 AUTO와 새 접속 모델의 차이

기존 `find_idle_cas`는 CAS 풀이 최대에 도달했을 때 AUTO·OUT_TRAN·holdable 없음·cas_change_mode=AUTO인 후보를 골라 `CLOSE_AND_CONNECT`로 전환한다. 요청 도착과의 경합은 con_status 락으로 재확인한다. 드라이버가 전달한 세션 ID/서버 키를 받아 기존 서버 세션을 이어갈 수 있는 경로가 함께 존재한다. [기존 CAS 후보 선택](https://github.com/CUBRID/cubrid/blob/c3967ec22/src/broker/broker.c#L2730), [기존 세션 ID 반영](https://github.com/CUBRID/cubrid/blob/c3967ec22/src/broker/cas.c#L312).

현재 통합은 연결 유지 모드를 ON으로 고정하고, 세션 ID를 무시해 새 세션을 만든다. 세션이 CSC를 소유하고, 연결 스레드는 CSC bracket을 연결 수명 동안 잡는다. 초기 설계의 [접속 프런트 결정](https://github.com/xmilex-git/workspace/issues/116)은 다중화 상실을 명시적으로 수용했다. AUTO 복원은 그 결정의 일부를 다시 설계하는 일이다.

근거: [KEEP_CON_ON](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/broker/cas_server_support.cpp#L298), [항상 새 세션](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/connection/driver_session.cpp#L447), [CSC 취득](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/connection/driver_session.cpp#L610), [소유권 채택](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/session/session.c#L2934).

정정: 앞선 제품화 감사의 “session_timeout은 IN_TRAN에만 적용되어 OUT_TRAN은 항상 무한 유지”는 현재 통합 ON 경로 전체를 설명하지 못한다. `net_read_header_keep_con_on`은 양수 session_timeout을 OUT_TRAN에도 적용한다. 다만 시간 만료는 접속 압력에 따른 AUTO 양보를 대신하지 않는다. [실제 ON 대기 경로](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/broker/cas_conn_helpers.c#L106).

### 3.2 풀을 넣어도 남는 결합

| 현재 결합 | 필요한 계약 |
|---|---|
| CSC 안의 인증·설정·MOP workspace·tm 상태 혼재 | 논리 세션 보존분과 실행 연결에 종속된 부분 분류 |
| CAS 전역을 옮긴 TLS 상태 | 실행자 변경 시 저장/복원/초기화 및 스레드 전용 힙 소유권 |
| 연결마다 CSS/normal 접속 슬롯·트랜잭션 등록 | 반환할 자리와 계속 보관할 논리 세션을 별도 회계 |
| `SESSION_END`가 현재 broker 슬롯 반환 신호 | 논리 세션 만료와 물리 연결/실행 자리 반환을 혼동하지 않는 내부 계약 |
| 기존 세션에 `csc_p` 하나만 허용 | 동시에 두 연결이 붙지 않는 재연결 상태 전이·소유권 검증 |
| keep 플래그가 session GC를 건너뜀 | 돌아오지 않은 detached 세션의 유한 만료·바이트 예산 |

근거: [CSC 데이터](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/object/client_session_context.hpp#L61), [CAS TLS](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/broker/cas_common_vars.h#L94), [CSS 슬롯 취득](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/connection/connection_sr.c#L579), [keep GC 제외](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/session/session.c#L1003).

PgBouncer 자체는 PostgreSQL 프로토콜용이므로 CUBRID 앞에 그대로 연결해 해결할 수 없다. 같은 모양의 외부 CUBRID proxy를 만들면 매 SQL이 중계 계층을 다시 지나간다. 현재 목표인 브로커의 접속 전용 역할과 서버 직결 1-hop을 유지하려면 적용 지점은 서버 내부의 세션/실행 자원 관리다. 이는 구조 비교에 따른 설계 판단이다.

## 4. 적용 선택지와 권고

| 선택지 | 사용자 동작 | 작업 및 제약 | 판단 |
|---|---|---|---|
| A. PostgreSQL 본체처럼 연결별 실행자 유지·접속 상한에서 거절 | 현재 통합과 가까움 | 가장 단순하지만 기존 AUTO 다중화 요구를 충족하지 않음 | 이번 요구의 해법 아님 |
| B. AUTO 호환 양보 + 논리 세션 재연결 | 안전한 유휴 연결을 양보하고 재접속 시 상태 보존 | detach/attach, 상태 보존, 슬롯·취소·만료 계약 필요 | 현재 목표의 우선 설계안 |
| C. 소켓·논리 세션 유지 + 유한 실행자 풀 | 유휴 TCP는 유지하면서 실행할 때 자원 대여 | 비차단 I/O, 세션별 직렬화, TLS·allocator 전환, CSS/등록 수명 분리 필요 | 큰 후속 구조. 기존 풀 사용만으로 구현되지 않음 |

**권고 순서:** B의 상태·수명 계약부터 정하고, 동일 계약 위에서 스레드/버퍼/문맥을 재사용할 수 있는 범위를 검증한다. 재접속 비용이 제품 목표를 막는다는 측정이 나오면 C를 별도 규모의 설계로 판단한다. PostgreSQL 사례만으로 새 세션 풀 전체가 필수라고 결론내리지 않는다.

CUBRID에는 이미 `cubthread::entry_manager`의 create/retire/recycle 확장 지점이 있다. 새 범용 스레드 풀을 처음부터 만들기 전에 이 기반을 검토한다. 이 기능은 실행 context 관리이지 인증된 논리 세션·CAS 프로토콜 상태·CSS 슬롯을 자동으로 분리하는 기능은 아니다. [기존 entry_manager](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/thread/thread_entry_task.hpp#L59).

### B에서 먼저 확정할 불변식

1. 동일 논리 세션에는 실행 소유자가 최대 하나다. 양보 확정과 새 요청 시작 중 하나만 성공한다.
2. 양보는 처리 중인 요청·트랜잭션·보관 결과·PL 재진입·XA 등에서 안전성이 확인된 경계에서만 한다. 단순 `OUT_TRAN` 관측만으로 종료하지 않는다.
3. 브로커는 자신이 소유한 연결 범위에서 양보를 요청하고, 서버가 동기화된 상태로 판정한다. SHOW용 best-effort 통계 포인터는 정확성 판단에 사용하지 않는다.
4. 반환 완료 전 새 슬롯을 발행하지 않는다. 지연/중복 종료와 취소는 연결 세대로 구별한다. 대기 중인 새 접속과 재접속 사이의 기아 방지 규약도 필요하다.
5. 재접속은 해당 사용자의 보관 세션인지 검증한다. 기존 서버 공통 키와 세션 번호를 무조건 신뢰하는 방식으로 되돌리지 않는다.
6. 세션 변수·설정은 보존한다. driver prepared handle의 재준비, SQL PREPARE 상태, holdable 결과는 각각 기존 계약과 비교한다. CSC 전체 보관 또는 전부 reset 중 하나를 임의로 선택하지 않는다.
7. detached 세션에는 만료와 바이트 회계를 둔다. 영구 keep 플래그만 켜서 보관하지 않는다. HA/서버 재시작과 정상 AUTO 양보는 구분한다.

## 5. 병목 판단: 확인된 구조와 미측정 비용

| 확인된 구조 | 예상 영향 — 아직 성능 측정 아님 | 확인 방법 |
|---|---|---|
| `boot_Restart_mutex`가 접속 초기화 전체 직렬화 | 양보마다 full boot하면 재접속 폭주에서 경합 | mutex 대기/보유 시간, 재접속 수/초, 접속 p95/p99 |
| 단일 broker dispatch와 30ms 슬롯 대기 | 한 요청이 기다리는 동안 후속 DB 접속도 지연 | 포화 DB A + 여유 DB B, 큐 체류/진행 이벤트 |
| 제어채널 `request_mutex`를 응답까지 보유 | 동기 양보 왕복을 추가하면 채널 직렬 구간 증가 | handoff/양보/상태 조회의 대기시간 분리 |
| 연결마다 스레드·CSC·인증·TLS·로그 초기화/해제 | 잦은 물리 교체에서 반복 비용 | 양보 1회 비용 분해, allocator/스레드 생성 계수 |
| 보관 세션·prepared·workspace | 실행자 수를 줄여도 논리 세션 메모리는 남음 | 연결 수와 보관 세션 수를 독립 sweep, PSS/귀속 바이트 |

근거: [boot 직렬화](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/transaction/boot_cl.c#L1208), [슬롯 대기](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/broker/broker_direct.cpp#L1510), [채널 요청 직렬화](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/broker/broker_direct.cpp#L545), [접속 스레드 생성](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/connection/adoption.cpp#L968).

PG도 fork·인증·공유 메타데이터 등록 비용이 없어지는 것은 아니다. PgBouncer는 backend 연결을 유지하여 그 반복을 줄이는 구조다. 이 사실은 CUBRID의 특정 성능 개선율을 보장하지 않는다. cpp-perf-rules의 MEAS-01/04/07(실측·반복·분산), PAR-05(락 범위), PAR-16(대기 전략), ALLOC-08(해제 소유권)을 판단 기준으로 삼는다.

## 6. 구현 후 검증 계획 및 QA 인계 입력

현재는 실행하지 않았다. 신규 testcase PR은 만들지 않고, 최종 단일 test.md에 아래 요구를 합친다.

- 수용성: 슬롯 K보다 많은 논리 클라이언트가 짧은 트랜잭션을 교대로 실행. 기본 AUTO 및 연결 고정 모드와 각각 비교.
- 상태 보존: A의 세션 변수·컴파일 설정·SQL PREPARE·driver prepared 사용 후 양보/재접속. A 유지, B 오염 없음.
- 양보 제외: 진행 중 트랜잭션·holdable·PL/trigger 재진입·XA 상태. 응답 송신/다음 요청 수신과 양보 경합.
- 수명: 동시 재접속·잘못된 세션 참조·늦은 cancel·중복/지연 SESSION_END·broker RESYNC·클라이언트 소멸·만료.
- 자원: 반복 양보 후 normal/CSS/broker 슬롯 일치, FD/스레드/보관 바이트 회수. 관리자·HA 예약석 보존.
- 성능: 기존 AUTO, 현재 통합, 후보를 같은 환경에서 비교. 낮은 부하, 연결 초과 교대 부하, 전원 활성 부하, 접속 burst, 느린 소비자, 다중 DB 포화를 구분. 처리량·접속/질의 p95/p99·mutex 대기·재접속/재준비 횟수·PSS를 반복 측정하고 median/분산 기록.
- 실제 빌드·재현·검증·core/gdb 작업은 실행 워커에 위임하며, 소스 조사·설계·판단은 리드가 직접 수행한다.

검증 데이터가 없으므로 풀 크기·대기시간·보관 세션 예산이나 성능 향상 수치는 이 조사에서 정하지 않는다.

## 7. 추가 원인 분석 — 기존 CAS의 병렬성과 통합 후 직렬화

사용자 후속 질문: 기존에는 왜 이 구조를 지원할 수 있었고, 통합 후 왜 달라졌으며, 어떤 설계가 맞는가?

**기존도 경합이 없지는 않았다.** `find_idle_cas`는 broker_shm_mutex와 후보 CAS의 con_status 락을 사용했고, dispatch는 빈 CAS를 기다리며 30ms sleep했다. 엔진 내부 락·접속 등록도 공유 자원이다. 기존의 장점은 초기화·클라이언트 상태의 소유 범위가 CAS 프로세스마다 분리돼 있었다는 데 있다. [기존 선택 락](https://github.com/CUBRID/cubrid/blob/c3967ec22/src/broker/broker.c#L2700), [기존 dispatch 대기](https://github.com/CUBRID/cubrid/blob/c3967ec22/src/broker/broker.c#L1211).

**기존 CAS는 준비된 DB 연결도 재사용했다.** `ux_database_connect`는 미접속·DB/host 변경 등의 경우에 `db_restart_ex`를 호출한다. 같은 DB/host의 연결이 살아 있으면 cache_user_info/자격증명 조건에 따라 `au_login`으로 재인증하고 `db_find_or_create_session`으로 논리 세션을 연결한다. CAS 초기화 전체를 클라이언트 교체마다 반복하는 구조가 아니다. 재인증 실패 등은 shutdown/full connect로 돌아갈 수 있으므로 모든 교체가 저비용이라는 뜻은 아니다. [전체 분기](https://github.com/CUBRID/cubrid/blob/c3967ec22/src/broker/cas_execute.c#L384), [재인증·세션 연결](https://github.com/CUBRID/cubrid/blob/c3967ec22/src/broker/cas_execute.c#L496).

통합 후에는 두 변화가 겹쳤다.

1. **소유 범위 변화:** 프로세스별 초기화 상태가 한 서버 주소공간에 모였다. client-half 부트에 process-once 초기화와 세션 초기화가 섞여 있고 once flag가 일반 변수여서, `boot_restart_client` 전체를 전역 mutex로 보호했다. 브로커별 mutex로 교체하면 동일 공용 상태를 다른 락으로 동시에 변경하게 된다.
2. **수명 정책 변화:** 접속=스레드=새 논리 세션으로 묶고 기존 세션 재연결을 폐기했다. 현재 `driver_session_run`은 새 접속마다 `db_restart_ex`를 호출한다. 기존 CAS의 warm DB 연결 재사용 경로와 다르다. AUTO 상실은 mutex 자체 때문이 아니라 이 수명 정책과 슬롯 회계 변경 때문이다.

근거: [부트 보호의 이유](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/transaction/boot_cl.c#L1208), [접속별 부트](https://github.com/xmilex-git/cubrid/blob/67c6fe88c54bb627e75f0eef4daa2e3dfe8c8437/src/connection/driver_session.cpp#L761).

설계 권고는 다음 소유권을 복원하는 것이다. 공용 모듈 초기화는 서버 수명에, 사용자 상태는 논리 세션 수명에, 재사용 가능한 실행 자원은 실행 소유자에게 귀속한다. 프로세스 공용 상태를 전수 분류하고 재진입성을 확인한 뒤에만 부트의 전역 보호 범위를 줄인다. broker별 세션 그룹은 서버 안에서 admission·양보·회계를 나누는 수단이다. 실제 브로커 측 manager는 이미 브로커별이므로 서버 공용 부트까지 자동으로 병렬화하는 수단은 아니다.

브로커별 관리자는 짧은 상태 전이와 예약을 담당하고, 인증·초기화·양보 정리 완료를 기다리며 그룹 전체를 붙잡지 않는다. 개별 세션의 요청 시작과 양보 확정은 동기화하고, 전체 서버 용량과 엔진 공유 자료구조의 동기화는 유지한다. 실행 자원을 재사용할 때는 세션별 인증·설정·workspace의 잔류가 없는 attach/detach 계약을 먼저 증명한다. 이는 설계 제안이며 새 풀·구체 구현에 대한 최종 HITL 결정은 아니다.
