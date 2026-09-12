# CAS 통합 제품화: 접속·제어·배포·보안 경계

조사 기준은 `xmilex-git/cubrid@d533969e4db6ef94d512d91f463790bab559790a`이다. shell/HA 전부 통과를 가정하고 정적 소스를 읽었다. 빌드, 실행 재현, 엔진 수정은 하지 않았다. 아래 **코드 결손**은 해당 분기/연산을 소스에서 확인했다는 뜻이며 운영 재현 완료를 뜻하지 않는다. **감사 과제**는 전체 경로 검증 전 확정 결함으로 올리지 않는다.

브로커와 DB 동거, V12 단일, 프로세스 재분리 기각은 이미 결정된 계약이다. 이를 다시 설계할 필요는 없다. 다만 이 계약 안에서도 제품용 접속 제어는 더 구현해야 한다. 우선순위는 **외부 입력/실패의 서버 자원 격리 → 취소 대상 신원 → 재시작 상태 회계 → 지원 배포 계약과 운영 진단**이다.

## 1. 먼저 구현: TLS 초기 접속에도 시간·자원·해제 계약 적용

**P1, 실패 경로 코드 결손 + admission 설계 보완.** TLS가 지원되는 제품으로 출시한다면 정상 SQL/HA 결과와 독립적으로 해결할 항목이다.

- `cas_init_ssl`은 매 접속 `SSL_CTX_new`를 수행한다. 인증서/키 로드 실패, 인증서 유효성 실패, `SSL_set_fd` 실패, `SSL_accept` 실패는 `ctx`의 원래 참조를 해제하지 않는다. 성공 경로만 `SERVER_MODE`에서 `SSL_CTX_free`를 호출한다. `SSL_new` 실패 경로에는 이미 free가 있다. 따라서 성공 경로 수정만으로 실패 접속 누적을 막지 못한다. [cas_ssl.c:141–191](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_ssl.c#L141).
- 소켓을 blocking으로 바꾸고 `SSL_accept`한 뒤 encrypted db_info를 읽는다. 이 구간은 서버 thread entry 등록과 DB 인증보다 앞선다. driver session 경로에는 이 단계의 receive deadline 설정이 없다. 정상 세션의 idle timeout만으로는 이 구간을 회수하지 못한다. [cas_ssl.c:104–108,177](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_ssl.c#L104), [driver_session.cpp:568–608](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L568).
- 이미 `css_increment_num_conn`이 handoff 전에 있어 무제한 DB 접속은 아니다. TLS 실패 때 quota를 환불하는 코드도 있다. 그러나 한도까지 인증 전 접속이 멈추면 정상 이용자의 입장을 막을 수 있다. [adoption.cpp:914–921](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L914), [driver_session.cpp:576–589](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L576).

최소 구현은 SSL/CTX/FD/quota의 모든 종료 경로 단일화, TLS+초기 db_info의 절대 deadline, 인증 전 접속 예산과 거절/시간초과 계측이다. 기존 CAS에서 프로세스 종료가 회수해 주던 실패 할당은 이제 서버 수명 누수이므로 TLS 외 인증 실패/연결 중단 경로에도 같은 감사를 적용해야 한다. 완료 계약은 정상·오인증·TLS 오류·초기 패킷 중단을 반복해도 서버 자원이 기준선으로 돌아오고 신규 정상 연결은 유계 시간 안에 성공하거나 명시적으로 거절되는 것이다.

## 2. 먼저 구현: cancel/status의 대상은 DB와 재시작을 넘어 유일해야 함

**P1, 소스상 대상 식별 결손.** 현재 토큰은 서버마다 `next_token=1`에서 시작한다. 브로커는 여러 DB의 같은 토큰을 multimap에 넣어 IP/port로 구분한다. 정상 연결의 exact match는 이미 구현되어 있으나 다음 경우에 정보가 부족하다.

- RESYNC는 token+IP만 보내며 포트가 없다. 재시작 브로커는 `clt_port=0`으로 복원한다. 같은 클라이언트 IP에서 서로 다른 DB에 같은 토큰이 있으면 exact match를 할 수 없고 IP-only 첫 항목으로 취소를 보낸다. [adoption.hpp:163–175](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.hpp#L163), [broker_direct.cpp:808–814](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_direct.cpp#L808), [broker_direct.cpp:1662–1680](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_direct.cpp#L1662).
- ST에는 실제로 `session_id`가 전송되지만 direct 경로는 이를 `brd_status`에 전달하지 않는다. `brd_status`는 token의 첫 DB를 선택한다. 구 CAS 경로는 pid와 session_id를 함께 검사한다. [broker.c:888–918](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker.c#L888), [broker_direct.cpp:1711–1729](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_direct.cpp#L1711).
- cancel 대상의 `tran_index`를 registry lock 아래에서 읽지만 lock을 푼 후 interrupt한다. 세션 cleanup은 같은 lock 아래에서 identity를 지운 다음 transaction index를 반납한다. 따라서 A index 읽기 → A 종료/반납 → B가 index 재사용 → A cancel이 B interrupt라는 interleaving을 현재 함수 계약이 막지 않는다. interrupt 함수는 index의 현재 TDES를 찾으며 token/generation은 검사하지 않는다. [adoption.cpp:1117–1132](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L1117), [adoption.cpp:662–675](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L662), [driver_session.cpp:859–876](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L859), [log_tran_table.c:2886–2900](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/transaction/log_tran_table.c#L2886).

이미 관리용 `registry_shutdown_client`는 registry mutex를 잡은 채 interrupt와 transport shutdown을 수행한다. 이쪽이 수명 보호의 비교 근거다. 단순히 새 락을 늘리는 것보다 cancel에도 동일한 수명 pin 또는 generation 검사 계약을 적용해야 한다. [adoption.cpp:635–655](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L635).

V12 wire 변경 없이 먼저 가능한 일은 RESYNC에 port/session identity를 보존하고 기존 ST session_id를 끝까지 전달하는 것이다. 최종적으로 한 브로커가 발행하는 opaque token을 전체 DB/epoch 범위에서 유일하게 만들거나, 내부 token 배정을 충돌 없이 하는 설계가 필요하다. 모호한 요청은 첫 항목 선택 대신 거절해야 한다. 완료 계약은 다중 DB·동일 IP·재시작·disconnect/cancel 경합에서도 **잘못된 세션을 취소하거나 상태로 반환하지 않는 것**이다.

보안 측면에서는 `clt_port=0`인 레거시 취소에 동일 IP를 반드시 요구하지 않는 허용 분기도 남았다. 구 CAS 코드에도 있던 규칙이므로 새 취약점이라고 단정하지 않는다. 하지만 이제 값이 PID 대신 단순 증가 토큰인 만큼 제품 취소 경계에서 이 호환 예외를 유지할지 명시적으로 결정해야 한다. [broker_direct.cpp:1683–1689](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_direct.cpp#L1683), [broker.c:930–985](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker.c#L930).

## 3. 먼저 구현: RESYNC를 snapshot+이벤트의 원자적 상태 교체로 만들기

**P1, 소스상 회계 경쟁 조건.** 이미 재동기화, SESSION_END, 조기 종료 ACK 보정이 구현되어 있다. 그러나 RESYNC가 같은 수준의 수명 규칙을 아직 충족하지 못한다.

1. 서버 `handle_resync`는 registry lock 안에서 live token snapshot을 만든다.
2. lock을 풀고 응답한다. 그 사이 snapshot 안의 세션이 종료될 수 있다.
3. broker reader는 아직 자기 테이블에 없는 SESSION_END를 `orphan_ends`에 넣는다.
4. RESYNC 처리자는 snapshot의 token을 그대로 넣고 live_count만큼 슬롯을 증가시킨다. **`orphan_ends`를 소비하지 않는다.** 정상 HANDOFF_ACK 처리자는 이 orphan을 지우며 슬롯 취득 여부를 결정한다.

이 순서는 서버 snapshot 직후 종료 또는 broker가 RESYNC reply를 받았으나 토큰 삽입 전 종료에서도 성립한다. 이미 끝난 세션이 토큰/슬롯에 살아남아 접속 용량이 줄 수 있다. [adoption.cpp:1153–1177](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L1153), [broker_direct.cpp:474–504](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_direct.cpp#L474), [broker_direct.cpp:795–820](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_direct.cpp#L795), [HANDOFF_ACK 보정:1580–1595](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_direct.cpp#L1580).

최소 구현은 RESYNC snapshot 적용과 END 소비를 같은 lock/epoch 아래에서 조정하고 실제 복원 token 수로 슬롯 회계를 하는 것이다. 실패/잘린 RESYNC를 정상 연결로 publish하지 않아야 한다. 지금은 응답이 기대 모양인 경우에만 회계를 한 뒤, 실패한 경우에도 아래의 channel map publish로 진행할 수 있다. [broker_direct.cpp:795–825](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_direct.cpp#L795).

더 넓게는 old/new channel generation, ACK의 FD 소유권, broker 재시작/일시 제어 채널 단절/DB 재시작을 구분하는 상태 전이 표를 코드와 맞춰야 한다. 모든 channel death를 session death처럼 취급하며 DB token을 버리는 현재 동작은 서버가 살아 있는 단절과 구분되지 않는다. [broker_direct.cpp:520–539](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_direct.cpp#L520). 완료 계약은 **복구 후 broker 슬롯 수=그 broker 소유 live session 수**, 중복/유실 END에 대한 멱등성, old generation이 새 token을 지우지 않는 것이다.

## 4. 운영 제어 채널도 멈추지 않는 종료 계약 필요

**P2, 코드 근거 있는 감사 과제.** 서버 제어 채널 `send_message`는 `send_mutex`를 잡고 blocking send를 수행한다. 서버 stop도 이 mutex를 잡아야 fd shutdown을 할 수 있다. broker가 살아 있으나 읽지 않는 경우 send-buffer가 찬 채 mutex를 보유하면 stop의 shutdown 자체가 mutex를 기다리는 구조다. 실제 buffer saturation으로 도달시킬 수 있는지 유계 재현이 필요하다. [adoption.cpp:187–229](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L187), [adoption.cpp:1583–1593](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L1583).

이미 fd close/send 경쟁은 mutex로 보호하고, channel thread는 joinable로 관리하며, 세션 registry 삭제 전에 fd를 닫지 않는 방어가 있다. 문제는 방어 미구현 전부가 아니라 **수명 안전과 shutdown 진행 보장 두 조건을 동시에 만족하는지**다. 최소 계약은 control send deadline 또는 유계 queue, stop이 blocked sender를 깨울 수 있는 소유권, drain timeout 후 서버 자원 해체 정책이다. 현재 세션 drain은 30초 뒤 manager만 누수시키는 fallback이며, 이때 여전히 실행 중인 세션이 다른 엔진 기반 자원을 사용하지 않는지 별도 검토해야 한다. [adoption.cpp:1597–1625](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L1597).

## 5. 지원 배포·보안 경계의 출시 계약과 진단 구현

**P1 출시 계약 / P2 구현 보완.** 아래는 의도된 범위 축소를 번복할 요구가 아니다.

| 정해진/현재 구현 계약 | 제품화에 필요한 마무리 |
|---|---|
| 일반 UNIX CAS broker는 `DIRECT_HANDOFF=OFF`를 읽어도 이후 강제 ON | OFF를 롤백 방법으로 안내하지 않기. 호환성 사전 점검과 구/신 설치 전환·되돌리기 절차, 지원 조합을 릴리스 단위로 확정하기. |
| 브로커→서버는 같은 호스트 AF_UNIX, protocol version 정확히 일치 | 설치/컨테이너의 UID, socket directory, mount namespace, 양쪽 binary/control ABI 일치를 검사하기. driver V12 호환과 내부 broker/server ABI 호환을 분리해서 알려야 함. |
| TLS db_info는 암호화되어 broker가 읽지 못함. `DIRECT_HANDOFF_SSL_DB` 필수 | TLS broker별 단일 DB 라우팅과 인증서 위치/교체를 설치 도구와 예제 설정에서 지원. 기존 다중 DB TLS 구성의 migration 지원. 다중 DB TLS 자체를 필수 재구현으로 올리지는 않음. |
| SHARD는 UNIX에서 명시적 설정 오류 | 미지원 선언과 사전 점검이 이미 있음. 다시 구현할 자동 blocker 아님. |
| 원격 SQL은 대상 노드 broker 필요, 구 fat SQL utility registration 거절 | 지원 driver/CCI/CS API/Manager/CSQL 조합과 원격 관리 제약을 표로 고정. 거절이 generic handshake error로 보이면 실행 가능한 migration hint를 제공. |

근거: [broker_config.c:1294–1302](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_config.c#L1294), [broker_config.c:1365–1399](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_config.c#L1365), [adoption.hpp:25–51](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.hpp#L25), [broker_direct.cpp:765–788](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_direct.cpp#L765), [cas_ssl.c:111–112](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_ssl.c#L111), [network_interface_sr.cpp:4022–4034](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/communication/network_interface_sr.cpp#L4022).

보안 경계에서 이미 된 일은 adoption socket의 owner-only 권한, local DIRECT_CONNECT의 same-UID/CSQL type 검사, broker 접속 ACL, 실제 드라이버 credential을 사용한 서버 내 `db_restart_ex`이다. 따라서 일반 SQL 인증이 전부 미구현이라는 결론은 맞지 않는다. [adoption.cpp:995–1013](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L995), [adoption.cpp:1540–1555](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L1540), [driver_session.cpp:712–728,765](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/driver_session.cpp#L712).

다만 utility/HA 채널의 `BOOT_UTIL_CHANNEL_CLIENT_TYPE`는 client가 선언한 type 허용목록이다. 이 체크 자체는 프로그램의 신원 인증이 아니다. 허용 type으로 들어간 뒤 native RPC 권한과 실제 비밀번호 검증이 어디서 강제되는지, OS 동일 UID를 어느 정도 신뢰하는지, native endpoint를 신뢰 네트워크로 제한하는 것이 출시 전제인지 명시해야 한다. 새 authenticated utility endpoint는 선택 가능한 후속 설계이며 이 조사만으로 무조건 구현 blocker라고 단정하지 않는다. [boot.h:71–82](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/transaction/boot.h#L71), [server_ping_with_handshake:578–584](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/communication/network_interface_sr.cpp#L578), [sboot_register_client:4018–4034](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/communication/network_interface_sr.cpp#L4018).

운영 계측도 없는 상태는 아니다. broker status에는 ACCEPTED/HANDOFFS/REJECTED/SLOTS가 있고 서버에는 SHOW SESSION STATUS가 있다. 추가 구현의 목표는 접속 실패 이유·TLS/인증 전 대기·handoff latency·RESYNC 실패/epoch·cancel target mismatch를 release에서 확인할 수 있게 하는 것이다. [broker_monitor.c:1235–1243](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/broker_monitor.c#L1235).

SHOW 통계 snapshot은 registry mutex가 포인터 수명만 보호하며 counter/string writer와 동기화하지 않는다고 주석에 명시되어 있다. 단순 stale 통계 허용과 C++ data race 허용은 다르므로 atomic counter, 세션이 게시하는 snapshot 등으로 thread-safe 관측 계약이 필요하다. 새 dashboard보다 앞선 구현이다. [adoption.cpp:129–138](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L129), [adoption.cpp:697–723](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/connection/adoption.cpp#L697).

## 별도 입력 검토: CAS frame decoder의 실패 격리

리드 요청으로 resource 담당자의 finding도 교차 확인했다. `net_decode_str`은 signed argument length의 음수를 거절하지 않는다. conceptual body `func 1byte + length=-4 4bytes`이면 body 크기 5는 외곽 cap을 통과한다. decode loop는 remain `4→0→4`, pointer `msg+1→msg+5→msg+1`로 전진하지 않고 `argc/realloc`만 증가한다. 실서비스 실행은 하지 않았다. 이 경우는 악성 SQL도 필요 없이 인증된 driver의 작은 잘못된 frame만으로 decoder의 진행 보장이 깨지는 정적 근거다. [cas_network.c:414–441](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_network.c#L414), [cas_dispatch.c:552–582](https://github.com/xmilex-git/cubrid/blob/d533969e4db6ef94d512d91f463790bab559790a/src/broker/cas_dispatch.c#L552).

이 항목은 해당 담당 보고서의 P0 경계로 합치는 것이 좋다. 외곽 body 크기 제한만으로는 내부 arg의 음수·최소 폭·개수·전진·합계 overflow 검증을 대신하지 못한다. 기존 CAS 코드에서 유래했더라도 이제 실패가 DB 프로세스 전체에 귀속되므로 제품 통합의 선행 구현이다.
