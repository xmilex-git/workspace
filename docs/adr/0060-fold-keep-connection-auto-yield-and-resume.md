---
status: accepted
date: 2026-11-17
---

# 폴드의 KEEP_CONNECTION=AUTO: 세션 양보는 YIELD_TRY와 유휴 감시로, 재개는 develop의 세션 secret으로, 스레드는 연결마다 새로

CAS 폴드(CBRD-27430, PR 7837)에서 `KEEP_CONNECTION=AUTO` 브로커의 세션은 핸드오프 슬롯이 모자랄 때 유휴 세션이 드라이버 연결을 닫고 슬롯을 돌려주며(세션 양보), 드라이버의 다음 접속이 그 세션을 이어 쓴다(세션 재개). 옛 구현(`cas-merge` @ `cdb9da11e`의 늦은 B1 커밋 6개)에는 설계 티켓이 없었고, 재이식([B1b](https://github.com/xmilex-git/workspace/issues/632))에서 claim 8개(C1–C8)를 사용자와 세운 뒤 세 가지를 옛 구현과 다르게 정했다.

1. **재개 인증은 develop의 세션 secret을 쓴다.** develop CBRD-27434(`7d9720559`)가 20바이트 드라이버 세션의 뒤 8바이트에 세션 secret을 넣었고, 보관된 세션의 만료를 떠난 시점부터 세며, 데몬이 지우기 전에 state mutex 아래에서 다시 확인한다. 옛 구현의 nonce·`auto_detached`·`auto_expires`·`auto_user`는 같은 자리, 같은 역할이라 이식하지 않는다. 양보는 develop의 keep-session 종료에 `csc_kept` 표식 하나를 더한 것이고, 재개는 state mutex 아래의 claim 한 번(`session_claim_kept_context`: 서버 키, secret, `csc_kept && ref_count == 0`)이다. 사용자 일치와 비밀번호는 `boot_resume_client`가 확인하고, 실패하면 세션을 다시 보관 상태로 둔다.
2. **양보 프로토콜은 YIELD_TRY + IDLE_WATCH/IDLE_HINT 하나다.** 옛 구현은 슬롯 소유 DB가 하나일 때 `yield_requested` 플래그(세션이 스스로 소비)를, 여럿일 때 YIELD_TRY와 감시를 썼다. 플래그 경로와 그 경합 보정(`ae4a8e6081`의 요구 반환)은 이식하지 않는다. 접속 프런트는 슬롯을 쥔 서버에 차례로 YIELD_TRY를 보내 하나가 양보하면 기다리기만 하고, 유휴 세션이 없으면 감시를 걸어 힌트가 오면 다시 시도한다.
3. **executor 재사용은 이식하지 않는다**(사용자 결정 2026-11-17). 연결마다 새 세션 스레드라 스레드에 남는 상태(`CAS_TLS`, 파서 TLS, 호출 단위 `thread_local`)가 다음 세션으로 넘어가지 않는다.

검증: `docs/tla/CBRD-27430-B1b`(`AutoSession`). C3의 liveness("기다리는 접속 프런트가 유휴 세션 뒤에 남지 않는다")는 플래그 없이 성립하고(`AutoSession.live.cfg`), 감시 쪽 두 가드를 뺀 mutant(`no-watch-scan`, `no-idle-hint`)는 깨진다. 결과 기록은 그 디렉터리 MAP.md의 `## Result`.

## Considered Options

- **옛 nonce 경로 이식**: 기각 — develop의 secret과 와이어 자리가 겹치고(둘 다 뒤 8바이트), 만료·재접속 경합 처리를 두 벌 갖게 된다.
- **`yield_requested` 플래그 유지(단일 DB 빠른 경로)**: 기각 — 슬롯 압박 때만 타는 경로에서 제어 채널 왕복 한 번을 아끼는 대신 exchange 경합 세 군데와 요구 반환 로직이 따라온다. TLC로 플래그 없는 설계의 claim 성립을 확인했다.
- **executor 재사용 이식**: 기각(사용자) — 옛 커밋은 wip이고 측정 기록이 없다. 재사용하려면 스레드 상태 전수 census가 필요하다. 필요해지면 최종 YCSB 뒤 별도 티켓.

## Consequences

- AUTO 세션만 세션 secret을 받는다. 그 외 연결은 세션이 곧 연결이라(#116 D5) 뒤 8바이트가 0이다.
- 양보가 아닌 연결 종료(드라이버 close, 소켓 오류)는 `cas.c`처럼 롤백하고 세션을 끝낸다. B1a까지는 세션이 `session_state_timeout`까지 남았다.
- 재개된 연결의 CAS 수준 상태(statement handle, 드라이버가 건 isolation·lock timeout)는 새 연결과 같다. 세션 변수·세션 파라미터·워크스페이스·현재 스키마는 유지된다.
- `KEEP_CONNECTION`의 기본값이 AUTO라, 폴드 브로커의 기본 동작이 이 경로다.
- `cubrid broker reset`은 제어 채널의 RESET 메시지로 서버에 닿는다. 서버 쪽 처리와 모델(C8)은 이 단계에 있고, 관리 명령에서 브로커를 거쳐 RESET을 보내는 배선은 B2(세션 제어 소켓)가 한다.
- claim이 `active_time`을 갱신하므로, secret을 가진 쪽의 실패한 재개 시도도 만료 시계를 다시 센다.
- YIELD_TRY 응답 타임아웃(5초) 뒤 서버가 늦게 양보시키면 요구 하나에 양보가 둘이 될 수 있다(재접속 한 번의 비용, C3이 허용).
