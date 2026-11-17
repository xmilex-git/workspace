---
status: accepted
date: 2026-11-17
---

# 폴드 세션의 브로커 conf는 핸드오프로 받는 사본이고, 로그 인덱스는 호스트 잠금이며, 세션 상태는 요청 경계의 복사본이다

CAS 폴드(CBRD-27430, PR 7837)에서 CAS가 자기 연결을 위해 하던 일(브로커 conf 읽기, SQL/slow/access/DDL 로그, ACCESS_CONTROL, TLS 종단, 상태 표시, `broker_changer`·`cubrid broker reset`·kill의 대상이 되는 것)을 서버의 세션 스레드가 한다. 옛 구현(`cas-merge` @ `cdb9da11e`의 B2 커밋 36개, 설계는 [#139](https://github.com/xmilex-git/workspace/issues/139) B2-D1~D12)을 재이식([B2](https://github.com/xmilex-git/workspace/issues/633))하면서 다섯 가지를 옛 구현과 다르게 정했다.

1. **브로커 conf는 서버 파라미터가 아니라 세션 설정 사본이다**(사용자 결정 2026-11-17). 옛 구현은 `cas_*` 서버 파라미터 16개와 고정 `shm_appl` stub을 두었다. 이제 CAS가 공유 메모리에서 읽던 값은 모두 `session_config`의 필드이고, 핸드오프가 실어 오며 `broker_changer`가 바꾸면 SESSION_CONFIG로 다시 온다. 서버 파라미터는 ACCESS_CONTROL 3개(`cas_access_control`, `cas_access_control_file`, `cas_access_control_default_allow`)뿐이다. 브로커를 거치지 않는 접속(thin csql)이 쓸 값은 B5가 정한다.
2. **사본에는 설정 seq가 붙는다.** 브로커는 타임아웃 뒤 채널을 버리고 다시 연결하는데, 서버에서는 버려진 채널의 스레드가 받아 둔 메시지를 뒤늦게 처리할 수 있다. 서버는 브로커별 최신 사본을 기억하고 세션의 사본을 더 큰 seq로만 바꾼다. 브로커 재시작 뒤의 seq는 시계(마이크로초)에서 시작해 이전보다 크다.
3. **변경은 요청 경계에서 적용된다.** 세션은 요청 헤더를 읽은 직후 새 사본을 가져가고, 트랜잭션 밖이면 로그를 다시 연다. CAS는 트랜잭션 밖에서 1초 안에 따라왔다 — 유휴 세션은 다음 요청 때 따라온다.
4. **로그 인덱스는 호스트의 잠금 파일 임대다.** 옛 구현은 서버 안의 할당기였고 파일 이름에 DB 이름을 썼다. 한 브로커의 세션이 여러 서버에 있고 브로커 재시작을 넘겨 살므로 `var/cas_log_slots/<브로커>_<N>.lock`의 `flock`으로 잡고, 파일 이름은 CAS 때와 같은 `<브로커>_<N>`이다.
5. **SHOW SESSION STATUS는 게시된 복사본을 읽는다**(사용자 결정 2026-11-17). 옛 구현은 다른 스레드의 통계 슬롯을 동기화 없이 읽었다(C++ data race, "best-effort"). 세션이 요청 경계마다 행을 세션별 mutex 아래에 복사해 두고, 읽는 쪽은 그 복사본만 읽는다. 세션의 요청 경로에는 경계마다 mutex 한 번과 행 복사 한 번이 더해진다.

그대로 둔 것: SSL 접속은 `DIRECT_HANDOFF_SSL_DB`로 보내고 접속 응답은 HANDOFF_ACK 뒤에 보낸다(B2-D9). TLS 컨텍스트는 develop의 CAS처럼 연결마다 만든다 — 옛 구현의 공유 `SSL_CTX`와 그 재적재는 이식하지 않았다. `broker_changer`의 CAS 번호 지정(`broker_changer <브로커> <N> ...`)은 DIRECT_HANDOFF 브로커에서 거절한다(세션 하나만 고르는 선택자는 만들지 않았다).

검증: `docs/tla/CBRD-27430-B2`(`ConfigPush`, `AclTable`, `LogLease`, `StatsKill`, `SslAck`). 2번과 ACL 적재 순서(적재 전체를 mutex로 직렬화)는 모델이 처음 설계에서 찾은 구멍이다. 결과 기록은 그 디렉터리 MAP.md의 `## Result`.

## Considered Options

- **`cas_*` 서버 파라미터(옛 방식)**: 기각(사용자) — 브로커 conf와 서버 conf에 같은 설정이 두 벌 생기고, 브로커마다 다른 값을 줄 수 없다.
- **서버가 브로커의 공유 메모리를 직접 읽기**: 기각 — 서버가 브로커의 shm key와 수명에 묶이고, 브로커 재시작 때 세션이 읽던 메모리가 사라진다.
- **SHOW SESSION STATUS가 슬롯을 atomic 필드로 읽기**: 기각 — 필드마다는 온전해도 행은 요청 도중의 값이 섞인다. 통계 필드 전부를 atomic으로 바꾸는 것보다 경계마다 복사 한 번이 싸고, 모델의 단계도 하나다.
- **세션별 선택자(`broker_changer <브로커> <N>`)**: 기각 — CAS 번호는 없고, 로그 인덱스는 세션이 끝나면 다른 세션의 것이 된다.

## Consequences

- `broker_changer`의 "OK"는 그 브로커의 세션이 있는 모든 서버가 응답했다는 뜻이다. 응답하지 않은 서버가 있으면 "some sessions keep the previous setting"을 출력한다. 공유 메모리는 이미 바뀌었으므로 그 뒤의 핸드오프는 새 값을 갖는다.
- 브로커 conf 값은 세션이 로그인할 때의 사본에서 시작하므로, 브로커 없이 서버만 재시작해도 값이 유지된다.
- 로그 잠금 파일은 지우지 않는다(지우면 쥐고 있는 잠금 옆에 새 inode가 생긴다).
- 접근 제어 파일을 읽지 못하면 loopback 외에는 아무도 허용하지 않는다. 다시 읽기는 `cubrid server acl reload`다.
- KEEP_CONNECTION=ON 세션은 트랜잭션 밖 SESSION_TIMEOUT이 없다(연결이 곧 세션). 이 동작은 사용자 확인 대기 중이다(B2 해결 코멘트의 D-1).
