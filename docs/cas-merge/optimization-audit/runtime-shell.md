# 접속·CAS 상태·버퍼·파서 scratch 감사

코드 기준: `dbf0b6409ab8e15516a2df5580bffc0e5c1dcfe4`. 현재 소스의 호출·생성·해제 경로를 확인했다. 실행·sizeof·RSS 측정은 하지 않았다.

## R1. 접속당 전용 스레드와 CAS_TLS 세션 상태

- `adoption.cpp:516-517,645-646`는 접속마다 `std::thread(driver_session_run)`를 생성하고 detach한다. `driver_session.cpp:496-503`은 fd를 blocking으로 복원하고, `:532-552`에서 thread entry와 client_session_context를 잡은 뒤 `:748`에서 연결 수명 전체를 request loop로 보낸다.
- `cas_common_vars.h:33-39`의 주석과 `CAS_TLS=thread_local`이 legacy process-global을 session-local로 옮긴 선택을 명시한다. 소켓 없는 `CSS_CONN_ENTRY`도 별도로 만든다(`driver_session.cpp:554-566`).
- 기회는 요청 수명에 종속된 상태와 연결 수명 상태를 분리해, I/O 대기 연결이 실행 worker·파서 scratch·stack을 독점하지 않도록 하는 것이다. 공유 prepared 객체 자체는 이 변경 없이도 가능하다.
- 단순히 thread pool로 보내면 TLS의 사용자·핸들·SSL·에러·parser 상태가 다른 세션에 섞인다. 명시적 세션 소유권, 요청 직렬화, 중첩 PL의 thread/transaction 규약, cancel/종료 순서를 먼저 바꿔야 한다.
- 메모리는 `연결 수 × (thread stack/TLS/thread-entry floor)`; stack 예약과 실제 RSS는 다르다. YCSB 장수 연결에서도 고정항은 노출된다. MEM-05, GLOB-05, COH-12, ALLOC-08, PAR-08.

## R2. 로그 미사용 여부와 무관한 대형 TLS 배열 선언

- `cas_log.c:59-68`: `8192+163840=172032 bytes=168KiB`의 두 배열을 TLS로 선언한다. `:174-202`는 SQL 로그를 열 때 큰 배열을 `setvbuf`에 전달한다.
- 현재 선언 단위는 활성 로그 수가 아니라 스레드다. 이것은 코드상 TLS 크기이며 모든 페이지가 실제 resident라는 뜻은 아니다. 서버의 다른 worker에 대한 TLS 할당·touch 동작도 런타임 측정해야 한다.
- 기존 파일명·로그 정책을 유지하면서 로그 활성화 시 buffer를 lazy allocate하고 close 때 반환하거나 활성 생산자용 제한된 buffer pool을 쓸 수 있다. 하나의 mutable 전역 버퍼 공유는 동시 로그가 섞여 잘못된다.
- 로그 파일 구조 재설계는 이번 후보에 포함하지 않는다. YCSB SQL_LOG=OFF에서도 논리 TLS footprint를 관찰하되 RSS 절감은 실측한다. ALLOC-02/05, MEM-05, COH-12.

## R3. 접속 수명 전체에 묶인 기본 80KiB 출력 버퍼

- `driver_session.cpp:438-473`는 연결 request loop 진입 시 `malloc(NET_BUF_ALLOC_SIZE)`하고 연결이 끝날 때만 destroy한다.
- `cas_net_buf.h:78-82,99`: 기본 NET_BUF_SIZE 16KiB + EXTRA_SIZE 64KiB = 80KiB다. `cas_server_support.cpp:133`의 stub net_buf_size=0과 `cas_net_buf.c:865-868`이 기본값 경로를 만든다.
- `cas_net_buf.c:65-78`의 clear는 payload 길이만 비우고 allocation을 유지하며 `:419-436`은 64KiB 단위로 자란다. 큰 응답 이후 커넥션이 유휴해도 high-water capacity가 남는다.
- 작은 초기 buffer + bounded growth/trim, 또는 active-request buffer pool이 후보. 외부 CAS wire의 바이트와 전송 완료까지의 수명은 유지한다. 단순 매 요청 free는 메모리와 malloc CPU의 교환이므로 기본 정책으로 단정하지 않는다.
- 기본 요청 loop N개가 잡은 allocation 용량은 `N×80KiB` (100개면 약 7.81MiB, allocator overhead 제외). 실제 resident와 peak 응답은 별도다. ALLOC-01/02/04, MEM-05.

## R4. TLS 연결마다 SSL_CTX와 인증서 재구성

- `cas_ssl.c:141-158`은 매 `cas_init_ssl`마다 SSL_CTX 생성·인증서/키 로드·검증을 한다. `:162`의 SSL 객체는 연결 전용이며, SERVER_MODE 성공 경로는 `:188-191`에서 CTX의 최초 참조를 놓고 SSL이 보유한 참조로 수명을 유지한다.
- 세션별 SSL은 필요하지만 같은 인증 설정의 SSL_CTX까지 매 연결 새로 만들 필요가 있는지는 별개다. 서버 소유의 불변 TLS 설정 generation과 연결별 SSL로 분리할 후보다. 인증서 변경은 generation 교체와 참조 수명으로 처리한다.
- 현재 OPENSSL 소비 계약과 인증서 갱신 정책은 별도 확인해야 한다. 이는 메모리/접속 준비 비용 후보이며 일반 비-TLS YCSB는 실행하지 않는다. ALLOC-05, MEM-05, PAR-10.

## R5. 실제 SHM 대신 전체 T_SHM_APPL_SERVER를 남긴 stub

- `cas_server_support.cpp:68-69`: process static `cas_Shm_stub`과 TLS `cas_As_slot`이 따로 있다. boot는 stub 전체를 memset한다(`:109-113`).
- `broker_shm.h:651-659`에는 ACL 배열, job_queue 4097개, shard 정보, as_info 4096개, unusable-database 배열까지 들어 있다. 필요한 작은 설정 레코드를 위해 과거 SHM의 전체 자료형을 보유하는 형태다.
- folded server에 필요한 최소 config type/accessor를 도입해 실제 legacy broker SHM ABI와 분리할 후보. 정확한 바이트는 `sizeof(T_SHM_APPL_SERVER)`·ELF symbol·RSS로 확인한다.
- 소스에서 `shm_appl->as_info[]`가 완전히 사라진 것은 아니다. `cas_conn_helpers.c:236,259`는 legacy KEEP_CON_AUTO 함수 안에서 참조하지만, 서버는 `cur_keep_con=KEEP_CON_ON`으로 시작하고 `cas_dispatch.c:461-467`에서 AUTO 진입을 배제한다. 이번 확인에서 이후 ON→AUTO writer는 찾지 못했다. 이 참조를 실행 결함으로 판정하지 않는다. 최소 type으로 바꾸려면 비활성 legacy body도 guard/prune해야 컴파일된다.
- 메모리 고정항 개선이며 boot memset CPU는 우선순위 근거가 아니다. MEM-05, GLOB-03, PHYS-10.

## R6. CAS 슬롯·semaphore와 서버 진단 상태의 이중 구조

- `cas_As_slot`은 여전히 pid/psize/restart/shard용 필드를 포함한 `T_APPL_SERVER_INFO`(`broker_shm.h:291-388`)다. 실제 세션 신원/실행 상태는 server session/connection에도 있다.
- `cas_server_support.cpp:534-559`의 CON_STATUS lock wrapper는 sem_wait/post 그대로다. `cas_dispatch.c:713-715,767-772`에도 남아 있다.
- `adoption.cpp:264-323`는 TLS slot 포인터를 registry에 게시하고 SHOW용 worker가 counters/string을 읽는다. reader의 registry mutex와 writer의 부분 semaphore는 동일 동기화 경계가 아니다. 이는 코드상 계약 정리가 필요한 후보이며 이번에 실행 race를 재현한 것은 아니다.
- 서버의 진단용 snapshot과 session-owned mutable 상태를 분리하면 obsolete slot fields와 semaphore 관례를 함께 재검토할 수 있다. 전역 registry lock을 매 YCSB 요청에 추가하는 방식도 경합을 만들 수 있으므로 정답으로 단정하지 않는다. 운영 출력 계약은 별도 운영 정책 결정에 맞춘다.
- COH-01/04/10, MEM-05, PAR-10. 동기화 제거 전에 reader/writer와 종료 수명을 명시해야 한다.

## R7. 요청마다 body malloc과 argv의 원소별 realloc

- `cas_dispatch.c:541-570`은 frame 길이 검사 후 요청 body를 malloc하고 `net_decode_str`에 넘긴다. 종료 시 `:880-881`에서 body와 argv를 free한다.
- `cas_network.c:393-440`는 argument를 찾을 때마다 argc를 늘리고 `realloc(argv,sizeof(void*)×argc)`한다.
- 외부 드라이버 frame decode는 필요하다. 그러나 요청 scratch는 작은 inline argv + overflow buffer, bounded reusable body, 또는 worker arena로 처리할 수 있다. 이 할당 전략은 CAS 제거 전에도 개선 가능했던 legacy 구현이며 통합의 필연적 결과로만 설명하지 않는다.
- 요청 body를 참조하는 argv·bind의 소비가 끝나기 전 buffer를 재사용하면 안 된다. shared prepared object가 원래 body를 참조하지 않도록 freeze/소유권 경계를 지킨다. YCSB execute마다 노출, ALLOC-01/02/04, STR-01.

## R8. 구버전 protocol/SHARD/재접속 경로를 서버에서도 함께 운반

- 서버 admission은 `driver_session.cpp:602-607`에서 protocol<V12를 거절한다. 그런데 `cas_dispatch.c:588-602,687-705`의 V2/V7/V8 이전 분기와 mutable type-conversion 설정은 공통 speaker에 남아 있다.
- SHARD·KEEP_CON_AUTO·CAS 메모리 기반 restart 경로도 공통 소스에 남으며, 서버는 SHARD OFF/KEEP_CON_ON으로 초기화한다.
- native server facade를 만들 때 활성 역할만 남기고 legacy CAS/CGW 빌드의 compatibility adapter를 분리할 수 있다. 사용자에게 보이는 driver function/오류 계약을 임의로 바꾸는 것은 포함하지 않는다.
- 이는 구조 단순화 후보이고 큰 메모리/속도 절감 수치는 없다. 접속 시 불변인 프로토콜 판단의 반복도 source evidence와 실제 분기 profile을 구분한다. BR-04, PHYS-10.

## R9. hint 정의와 파싱 중 상태를 한 TLS 테이블로 복제

- `csql_grammar.y:24061-24140`의 `parser_hint_table`은 token·hint 종류·길이와 arg_list·is_hit을 함께 둔 TLS 배열이다. `scanner_support.c:284-333`은 각 스레드의 첫 사용에 같은 정의를 정렬·길이 계산·lead-offset 인덱싱한다.
- `scanner_support.c:342-350`은 arg_list를 해제한다. immutable hint 정의/길이/검색 인덱스와 parse별 hit bitmap·argument node 참조를 분리하면 고정 정의를 process에서 한 번 보유할 수 있다.
- 파서의 다른 default stack 배열(`csql_grammar.y:22854-23580`)과 `g_msg[1024]`(`csql_lexer.l:115`)도 TLS다. 상태 자체는 파싱마다 필요하지만 파싱하지 않는 연결의 수명과 묶을 이유는 R1과 함께 재검토한다.
- 중첩 parse에서 outer scratch를 덮지 않는 계약이 필요하다. 본 후보는 준비 단계 메모리/작업 중복이며 YCSB warm 실행 CPU에 크게 노출된다고 주장하지 않는다. MEM-05, GLOB-03/05, ALLOC-05.

## 범위 점검

CMake의 CLIENT_HALF_SOURCES/CAS_SPEAKER_SOURCES/CSQL_BODY_SOURCES와 upstream 대비 232개 변경 파일 목록을 조사 입구로 사용했다. 관련 소유권·호출 경로는 분야별 보고서에서 다뤘다. 232개 파일의 모든 행이나 모든 mutable-field write를 전수 검증했다는 뜻은 아니다.

기존 domain의 MOP-free 공유, process AREA, xcache 공유, in-process PL dispatch는 이미 구현돼 있어 신규 성과로 세지 않는다. 관리자·HA·DBLINK/CGW·JVM·driver·디스크는 실제 외부 경계가 남으므로 같은-process 제거 논리를 일괄 적용하지 않는다. csql 서버 렌더는 이미 역할이 이전된 경로이며, 렌더 출력 자체는 해당 실행 결과이므로 다른 세션과 공유할 준비 객체와 구분한다.
