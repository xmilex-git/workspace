# cas-merge 제품화 잔여 과제 — 코드/아키텍처 감사 (2026-09-12)

맵: [CAS 통합 후속 지도 #207](https://github.com/xmilex-git/workspace/issues/207) · 대상: `cas-merge` head `d533969e4` (develop merge-base `14d21ef51`) · 방법: 읽기 전용 코드 감사 4축(세션 상태·메모리, 보안·격리, 접속 프런트·수명주기, 기능 패리티·코드 건강) + 리드의 P0 재검증. 빌드·실행·재현 없음.

질문: **shell/HA TC를 전부 통과한다고 가정할 때, 제품화를 위해 코드/아키텍처 차원에서 추가로 구현·해결해야 할 것이 남았는가? 무엇부터인가?**

답: 남았다. 기능 패리티는 사실상 완료됐고(부록의 "query replace inert"는 구버전 기술 — `driver_session.cpp:806`에서 세션마다 초기화됨), 남은 것은 세 묶음이다. ① CAS가 프로세스였기 때문에 전역이어도 됐던 상태가 폴드 후 **세션 간 공유로 변한 결함**(작지만 정확성 결함, TC로는 거의 잡히지 않음), ② 핸드오프·HA·취소 프로토콜의 **경계 조건**, ③ 스레드 모델·메모리 예산·격리·Windows·유틸 채널 같은 **정책 결정이 필요한 아키텍처 항목**.

표기: [V] 코드 직접 확인(리드 재검증 포함), [A] 감사 에이전트 확인, [D] 문서 근거만.

## Tier 0 — 세션 격리 결함 (제품화 전 필수, 대부분 S 규모)

"세션 소유여야 할 상태가 프로세스 전역으로 남은" 클래스. 맵의 B4 파생 fog("전수 감사 미완")가 정확히 이 클래스다. 이번 감사에서 신규 확정된 멤버:

| # | 항목 | 코드 | 증상 | 규모 |
|---|---|---|---|---|
| 0-1 | `lang_Parser_use_client_charset` 프로세스 전역 static [V] | `src/base/language_support.c:2684` (주석 "unguarded"); 쓰기 `cas_execute.c:8565-8585`(스키마 질의 중 false↔true), 읽기 `cas_execute.c:4014-4064` | 세션 A가 스키마 정보 요청 중이면 동시 세션 B의 문자열 바인드가 시스템 charset/collation으로 들어감 — 조용한 데이터·비교 오류 | S |
| 0-2 | `xa_prepare_flag` 프로세스 전역 static [V] | `src/broker/cas_xa.c:45` (CAS_TLS 리다이렉트 없음); `src/connection/driver_session.cpp:853`이 이 값으로 접속 종료 시 롤백 여부 결정 | 한 세션의 XA prepare가 **모든 세션**의 disconnect 롤백을 억제 → 미완료 트랜잭션 잔류. XA 테스트 0건 | S |
| 0-3 | 세션 파서/문장 포인터를 전역 static에 보관 [V] | `src/optimizer/histogram/histogram_cl.cpp:490-491`, 설정 `:2857`, 읽기 `:606` (주석 "Client-side single-threaded") | 타 세션의 histogram_walk가 A의 파서·문장을 참조 → A 종료 후 UAF/wild pointer(B4-D9 크래시 시그니처) | S |
| 0-4 | `SET SYSTEM PARAMETERS`의 FOR_CLIENT∧¬FOR_SESSION 파라미터가 공유 `prm_Def`에 기록 [V] | `src/base/system_parameter.c:7924-7936`(브래킷 내 FOR_CLIENT 통과) → `sysprm_set_value_internal :9813`은 FOR_SESSION만 세션 리다이렉트. 대상 86개(insert_mode, oracle_style_outerjoin, hostvar_late_binding, ansi_quotes, pipes_as_concat, qo_dump, er_log_level, plan_cache_bind_sensitivity …) | 한 세션의 SET이 전 세션 옵티마이저·의미론을 바꿈; 문자열 값 free/replace 무락; 브로커별 cubrid.conf 차등 불가. 열린 티켓 [#235](https://github.com/xmilex-git/workspace/issues/235) | M |
| 0-5 | 옵티마이저 비용 vtable 전역 변이 [A] | `src/optimizer/query_planner.c:5511-5524` `all_vtbls[i]->cost_fn` 교체; `query_graph.c:378` QO_PARAM_COST에 SERVER_MODE 분기 없음 | `SET OPTIMIZATION COST`/csql `;cost` 한 번이 전 세션 플랜 선택을 바꿈 | S |
| 0-6 | `lc_Is_siginterrupt` 프로세스 static → 취소 리셋 공백 [A] | `src/transaction/locator_cl.c:117, 192-199`; 요청 시작 `db_set_interrupt(0)` `cas_dispatch.c:527-530` | 늦게 도착한 cancel이 다음 문장을 abort | S |
| 0-7 | 접속마다 프로세스 전역 부작용 [A] | SIGFPE 핸들러 재설치 `src/object/db_admin.c:80, 988-996`(2번째 접속부터 prev==자기 자신 → SIGFPE 시 무한 재귀, 서버 핸들러 덮어씀); `Static_method_table` push가 `boot_Restart_mutex` 밖 `src/object/schema_manager.c:190, 542-564` | 접속 폭주 시 리스트 손상 / 서버 시그널 처리 오염 | S |
| 0-8 | **검출 게이트 부재** [A] | 세션 리다이렉트 매크로가 .c 내부 `#define X (csc_*()->f)` 41개(+헤더 9); 누락은 무경고 컴파일 → 0-2가 실제 누락 사례 | 위 항목을 고쳐도 같은 클래스가 재발 | S(스크립트) |

**권고 순서**: 0-1 → 0-3 → 0-2 → 0-5/0-6/0-7 → 0-4(#235 결정 선행) → 0-8(static 선언 vs 리다이렉트 대조 스크립트를 게이트에 편입, 세션 간 SET/charset 격리 unit 추가).

## Tier 1 — 프로토콜·수명주기·입력 경계 결함

| # | 항목 | 코드 | 위험 | 등급 | 규모 |
|---|---|---|---|---|---|
| 1-1 | HA reset 경로가 세션을 영구 잔류시키고 드라이버에 무통보 종료 [V] | commit/abort → `xtran_should_connection_reset` → `db_Connect_status=RESET` (`network_interface_cl.c:3144-3146`) → `ux_end_tran`이 `as_info->reset_flag=TRUE` (`cas_execute.c:1014-1017`, `cas_error.c:83`) → `FN_KEEP_SESS`+`db_set_keep_session(true)` (`cas_dispatch.c:877-885`) → `session_state_destroy(keep=true)` (`session.c:823-827`) → GC가 keep 세션 영구 skip (`session.c:1003-1007`). 입양 세션은 재부착 불가(`driver_session.cpp:447-461`) | 페일백/standby 전환마다 세션 상태+client context 누수; 드라이버는 다음 요청에서 EOF(에러 프레임 없음). 레거시 "세션 유지 후 재부착" 계약을 반만 옮김. *감사 간 충돌 해소: 서버 측 writer(`ux_end_tran`)가 존재하므로 inert가 아님* | P0 | S |
| 1-2 | 브로커 슬롯 = 동시 연결 수, 무기한 대기·DB 간 HOL 차단 [V] | `max_slots=MAX_NUM_APPL_SERVER`(기본 40, `broker_config.h:48`); 단일 dispatch 스레드가 30ms 스핀 대기, 데드라인 없음 (`broker_direct.cpp:1514`); 서버 `CLIENTS_EXCEEDED` 거절도 무한 재시도 (`:1623`) | 풀 크기 >40인 기존 운영 환경은 day-1 로그인 타임아웃; 한 DB 포화가 브로커 전체 핸드오프 정지; 서버 max_clients와 이중 게이트. idle OUT_TRAN 연결은 슬롯+스레드 무기한 점유(session_timeout은 IN_TRAN에만, `cas_dispatch.c:538-541`) | P0 | M |
| 1-3 | 핸드오프 5초 타임아웃 후 fd 이중 소유 [A] | `channel_request` 5초 (`broker_direct.cpp:82, 647-660`); sendmsg로 fd 전달 후 ACK 지연 시 브로커가 같은 fd에 에러 프레임 기록+close (`:1592-1600`), 서버 세션은 connect reply 기록 중; 미처리 SESSION_END는 `orphan_ends` 영구 적재 (`:503`) | 서버 stall(checkpoint·swap) 시 와이어 오염 + 슬롯 회계 불일치 | P1 | M |
| 1-4 | CAS 인자 디코더 음수 길이 미검증 [V] | `src/broker/cas_network.c` `net_decode_str`: `i_val<0`이면 `remain_size < i_val` 통과 → `cur_p += i_val` 역방향, `remain_size` 증가, argv REALLOC 무한 성장. develop CAS와 동일 코드 | 레거시는 CAS 프로세스만 죽었으나 이제 cub_server 크래시/메모리 고갈(인증된 PUBLIC 세션 1개로) | P0 | S |
| 1-5 | 요청 본문 상한 1 GiB 사전 할당 [A] | `cas_dispatch.c:75` `CAS_DISPATCH_REQUEST_BODY_MAX=1 GiB`, `:552-562` 검사 후 즉시 MALLOC; `driver_session.cpp:106` `REQUEST_BODY_MAX=16 MiB`와 상수 분기 | 인증 세션 N × 1 GiB = 서버 OOM-kill(#128 D3 "OOM=문장 에러"가 큰 할당엔 불성립) | P1 | S |
| 1-6 | 폴드 csql 본체의 longjmp 탈출 [A] | `src/executables/csql.c:3536-3547` `csql_exit`→`longjmp`; setjmp `:4653, 4736`; C++ 프레임(`cas_csql.cpp` std::string/vector, fopencookie) 위를 넘음; release에서 `assert(env_armed)` 소멸 → unarmed csql_exit가 조용히 return | 소멸자 미실행(UB)·락 미해제·치명 지점 이후 계속 실행 | P1 | M |
| 1-7 | 접속 부트 전역 직렬화 [A] | `db_restart_ex` 전체가 `boot_Restart_mutex` (`src/transaction/boot_cl.c:1215-1216`) | 페일오버 후 600건 재접속·풀 워밍업이 단일 스레드 한계(레거시는 CAS별 병렬) | P1 | L |
| 1-8 | receiver(accept) 스레드가 제어 채널에 동기 블록 [A] | ST `brd_status` (`broker.c:907`→`broker_direct.cpp:1711`, 5초), QC `brd_cancel` (`broker.c:969`→`:1638`, dial 최대 10초) | 서버 stall 시 브로커가 새 접속을 5~10초 못 받음 | P1 | S |
| 1-9 | 취소 토큰 순차 정수 + port=0 관용 [A] | 토큰 1부터 순차 (`adoption.cpp:165, 943`); anti-spoof `broker_direct.cpp:1638-1700`, 관용식 `:1683-1690`은 레거시 CANCEL 헤더(port=0)면 IP 불일치도 통과 | 브로커 포트 도달 호스트가 작은 정수 반복으로 임의 세션 취소(DoS) | P1 | S |
| 1-10 | 깊이 가드 범위·스택 크기 [A] | `PT_MAX_NESTING_DEPTH 16384`는 표현식 체인·함수 인자·CASE만 (`csql_grammar.y:462-469`); 서브쿼리 중첩·pt_walk·XASL 생성·옵티마이저 재귀 무가드; 세션 스레드 스택 미지정 (`adoption.cpp:968-969`) | 깊은 서브쿼리/뷰 중첩 → 스택 고갈 → sigaltstack 진단 후 서버 전체 fail-fast | P1 | M |
| 1-11 | SSL 브로커 단일 DB 라우팅 [A] | 암호화 db_info를 peek 불가 → `DIRECT_HANDOFF_SSL_DB` 하나로 고정 (`broker_config.c:1391-1398`, `driver_session.cpp:671-680`) | 멀티 DB SSL 브로커 회귀(DB마다 브로커·포트 분리 필요, 미문서) | P1 | M/L |
| 1-12 | 소형 누수·잔존 [A] | `srv_handle_table` 배열 미해제 (`cas_handle.c:52, 88-97`); claim_entry 실패 시 SSL 객체 미해제 (`driver_session.cpp:595-601`); qlist 균형 검사 stand-down (`query_executor.c:17462-17481`); `er_set(FATAL)` 잔존 (`boot_cl.c:2299, 2313`, `xasl_generation.c:10434`); `db_Preferred_hosts` free+strdup 전역 (`db_admin.c:588-598`, 도달 경로는 reconnect만) | churn 환경 누적, debug 한정 검출 공백 | P2 | S |

## Tier 2 — 아키텍처·정책 결정이 필요한 항목

| # | 항목 | 현재 | 결정할 것 | 규모 |
|---|---|---|---|---|
| 2-1 | **스레드 모델·메모리 거버넌스** [V/A] | 접속=detached `std::thread`(`adoption.cpp:968`), 브래킷을 연결 수명 내내 보유(`driver_session.cpp:613→896`); 스레드당 TLS **245,752 B**(cas-merge `libcubrid.so` PT_TLS, develop은 544 B; `sql_log_buffer` 163,840 `cas_log.c:68`, `ddl_audit_handle` 19,200 …) — 워커풀·데몬 등 **모든** 서버 스레드가 부담; 세션 예산/쿼터/유휴 회수/세션별 바이트 관측 없음; 상한 = `max_clients` 4000 + `max_prepared_stmt_count` 2000; css 슬롯·브로커 슬롯 이중 회계 | 열린 티켓 [#237](https://github.com/xmilex-git/workspace/issues/237)의 예산·게이트 확정. quick-win: TLS 대형 버퍼 지연 힙 할당(−180 KiB/스레드), 세션 바이트 계수·상한. 장기: 워커 풀 전환 시 CAS_TLS 96곳·CSQL_PARSER_TLS 170곳의 귀속 전제 재설계 | L |
| 2-2 | **장애 격리 = 서버 fail-fast (D1)** [A] | sigaltstack(`thread_entry.cpp:380`)·깊이 가드·AREA failure_function(`area_alloc.c:214`) 구현됨; 시그널 catch/격리 계층 없음 | 정책은 결정됐으나 제품 자세(auto_restart·크래시 루프 억제 기본값·운영 문서)로 굳혀야 함. 1-4 같은 레거시 CAS 결함 전부가 서버 결함이 되므로 fn_* 인자 파서 전수 감사(fuzz 수준) 선행 | L(정책)+M |
| 2-3 | **유틸/관리 채널(legacy RPC) 무인증** [V] | `network_interface_sr.cpp:4022-4028` 타입 필터만(ADMIN_UTILITY·LOG_COPIER·LOG_APPLIER·COMPACTDB_WOS·LOADDB); `boot_sr.c:3247-3251` 클라이언트 제시 `db_user`를 패스워드 검사 없이 tdes에 기록; ACL 미적용 | develop 선존 구멍(레거시 CS는 클라이언트 au_start 신뢰). 그러나 드라이버 경로가 #118 D3 서버 핸드셰이크로 바뀐 뒤 **유일하게 남은 신뢰-클라이언트 경로**. 최소안: 원격 바인드 기본 차단(loopback) + HA 호스트 허용목록; 정식: SO_PEERCRED(입양 소켓 패턴) / 공유 비밀·mTLS | L |
| 2-4 | **Windows** [A] | cub_server 빌드 불가 구조: `adoption.cpp`/`driver_session.cpp`가 CONNECTION_SOURCES에 무조건 포함(`cubrid/CMakeLists.txt:218-219`), `<sys/un.h>`·SCM_RIGHTS·SO_PEERCRED·flock·fopencookie 무가드(신규 9파일 WINDOWS 가드 0); `cs/CMakeLists.txt:26, 566` CSQL_THIN·csql_wire.c 무조건 적용, Windows cub_cas는 CSQL_REQUEST를 fn_not_supported(`cas_dispatch.c:127`). AppVeyor는 PR에서 한 번도 실행되지 않음 | 지원 유지(가드·분기 추가) vs 명시 미지원 선언 후 `cas.c`(790행 WinMain)·`cas_common_main.c`(1,054행)·SHARD 92참조/26파일·WIN_FW 12 정리 | M |
| 2-5 | **운영 표면 정합** [A] | 설정 소스 2중: 브로커 경유 세션은 handoff config(broker.conf 전량, `broker_direct.cpp:1542-1545`)가 cubrid.conf `cas_*` 20개를 덮음(`driver_session.cpp:748`), direct csql만 `cas_*` 사용; PREFERRED_HOSTS/CONNECT_ORDER/RECONNECT_TIME은 파싱되지만 inert(`cas_server_support.cpp:143`); 로그 파일명 `<name>_<N>.sql.log`의 N 의미 변경(flock 리스 슬롯 `var/cas_log_slots/`), access log 경로 변경, `sql_log2` 전면 stub, `cas_session_timeout` 기본 −1; 입양 소켓 `$CUBRID_TMP`(기본 `/tmp`)·same-uid 전제; conf 템플릿·매뉴얼 미반영 | 우선순위 명문화, inert 파라미터 경고, 소켓 경로 `$CUBRID/var` 0700 이전, 문서화 | M |
| 2-6 | **물리 설계** [A] | 서버 lib가 `src/broker` 24파일+csql 5파일 컴파일(`cubrid/CMakeLists.txt:750-788`); broker↔connection↔object include 순환(`broker_direct.cpp:67`이 `src/connection/adoption.hpp`; `boot_sr.c:55-57`이 `work_space.h`) — PHYS-02; 로컬 `extern` ≈35곳 — PHYS-11; `#undef FREE` 임시조치; 신규 모드 seam 271블록(`network_interface_cl.c` CS dual-body 171 잔존, `csql.c` 3플레이버 57 seam) — PHYS-04/08; 테스트 트레이서 `server_compile_tracer.cpp` 1,292행이 제품 lib에 상주하고 env `CUBRID_M0_TRACER_*`로 서버 내 SQL 실행(`network_sr.c:38, 1155`); 문법/렉서 `-fpermissive -Wno-error`(`cubrid/CMakeLists.txt:834-838`) | 핸드오프 프로토콜을 헤더 단독 `src/adoption/`로 승격해 순환 제거; extern 헤더화; 트레이서를 UNIT_TEST 옵션 빌드로 분리 | M |
| 2-7 | **테스트 공백** [A] | unit 19건(동시 파스 8스레드·ACL·슬롯/리스·admission·wire 헬퍼). 0커버리지: XA 전 경로, 제어채널 프레이밍·RESYNC·SESSION_END·SESSION_CONFIG, SSL 핸드오프, 동시 disconnect teardown(smoke case 6은 4세션 1회), 서브쿼리 깊이, 세션 간 SET/charset 격리, OOM 주입, 다세션 생성·사용·종료 스트레스 | Tier 0/1 수정마다 짝 unit 추가; "접속이 서버 전역을 건드리지 않는다" 불변식 unit | M |

## 정상 확인된 것 (추가 조치 불요) [V/A]

- 인증: `authenticate_context.cpp:562-690` perform_login이 서버 스레드에서 실행, au_ctx 세션 스코프; 드라이버 session_id 재부착 무력화; 핸드셰이크 실패 → 에러 회신 후 retire. ACL 서버측 fail-closed(`cas_server_support.cpp:522, 614-640`). SSL 서버 종단·세션 로컬·CTX 누수 방지. REVOKE 갭 `sm_touch_class` chn bump(`authenticate_grant.cpp:701-716`). thin csql SIGINT 전용 취소 스레드(`csql_wire.c:78-121`, Codex #8 반영됨). 원격 `--sysadm/--read-only` 거절.
- 세션 컨텍스트: ws/tm/sm/tr/au/db/Qres_table/plan dump/obt/label/method args가 `client_session_context`로 리다이렉트, teardown 순서(`client_session_context.cpp:231-286`) 정상; xcache는 stream malloc 복사, 호스트 변수 OBJECT는 OID 정규화, fpcache MOP 참조 없음. OOM: lea 실패 `ER_OUT_OF_VIRTUAL_MEMORY`, AREA 실패 tran abort, 파서 OOM은 `PT_SET_JMP_ENV` 내 longjmp만 — 문장 에러로 귀결. retire 단일 경로에서 conn 슬롯·csc·fd·토큰 각 1회 정리.
- 프로토콜: 브로커 재시작 HELLO+RESYNC 토큰 재구축, 서버 재시작 시 채널 death→토큰·슬롯 해제·신규 접속 −677 프레임, killtran의 입양 fd shutdown+인터럽트, SHARD conf 단계 거절, 32/64비트 폭 가정 결함 없음(handoff 구조체 고정폭).
- 패리티: ACL·SQL/slow/DDL 로그·autocommit·statement pooling·schema info·질의 취소·SSL·JDBC 캐시 TTL+changer 세션 선택자·query replace·histogram/plan 출력 구현. cgw/DBLINK 무변경.

## 미확인·주의

- JDBC/CCI 소스가 저장소에 없어 −677·`CAS_ER_FREE_SERVER`가 드라이버 재시도 화이트리스트인지 미확인.
- 실제 페일백·접속 폭주·OOM 시나리오는 재현하지 않았다(코드 독해 기준).
- 1-4(디코더)·2-3(유틸 채널)은 develop 선존. 폴드가 만든 결함이 아니라 **폴드가 격리를 없애 심각도가 오른** 항목이다.
- 두 감사가 1-1의 도달성에서 충돌했고(`reset_flag` writer 유무), 리드가 `cas_execute.c:1014`·`cas_error.c:83`에서 서버 측 writer를 확인해 P0로 확정했다.

## 권고 구현 순서 (제품화 착수 시)

1. **Tier 0 전부 + 검출 게이트(0-8)** — 각 S 규모, 정확성 결함, TC 통과와 무관하게 상용 동시성에서 재현된다. #235 결정이 0-4의 선행.
2. **1-1 HA reset, 1-4 디코더 가드, 1-2 슬롯 데드라인·거절 정책** — 운영 day-1 사고 후보.
3. **1-3, 1-5, 1-6, 1-8, 1-9** — 경계 조건·입력 검증·비차단화.
4. **Tier 2 결정** — 2-1 메모리 예산(#237)과 2-3 유틸 채널·2-4 Windows는 사용자/리뷰어 정책 결정이 선행; 2-5 운영 표면·2-6 물리 설계는 PR 분할 논의와 함께.
5. **1-7 부트 직렬화, 1-10 깊이 가드, 2-7 테스트** — 규모 큰 항목은 위 결정 뒤.

감사 원문(4축 보고)은 이 세션 대화에만 있으며, 표는 그 요지를 리드가 재검증·통합한 것이다.
