---
status: accepted
date: 2026-11-18
---

# 폴드 세션의 쓰기 금지 게이트는 둘이다: 세션 소유 카운터와 폴드 경계의 요청 검사. HA 접속 판정은 세션 수립 때 한 번

CAS는 브로커의 ACCESS_MODE·REPLICA_ONLY에 따른 클라이언트 타입으로 서버에 접속했고, 쓰면 안 되는 서버에 쓰지 못하게 막는 장치가 셋 있었다. (1) CAS에 링크된 클라이언트 라이브러리의 카운터 `db_Disable_modifications`(읽기 전용 타입·`read_only`면 부팅 때 올리고, builtin 메서드 호출 동안 올렸다 내림)를 `db_` 진입점의 `CHECK_MODIFICATION_*`가 읽는다. (2) 서버는 트랜잭션 경계마다 `tdes->disable_modifications`를 서버 자신의 전역(standby·`read_only`)에서 심고, wire 디스패치(`net_server_request`)가 `CHECK_DB_MODIFICATION` 요청마다, 그리고 실행기·시리얼 코드가 직접 검사한다. 거절은 트랜잭션을 롤백하고 연결에 `reset_on_commit`을 남긴다. (3) 커밋·롤백마다 reset 표(`xtran_should_connection_reset`)가 연결을 다시 맺으라고 지시하고, CAS는 호스트 목록을 처음부터 다시 돈다.

CAS 폴드(CBRD-27430, PR 7837)의 세션은 client 절반이 서버 스레드 안에서 돈다. [B3 재이식](https://github.com/xmilex-git/workspace/issues/634)에서 TLA+ 모델(`docs/tla/CBRD-27430-B3`, `HaGate`)과 develop 실측으로 다음을 정했다.

1. **client 절반의 카운터는 세션의 것이다**(`csc_db ()->disable_modifications`). CAS 프로세스 하나가 가졌던 것을 세션 하나가 갖는다. 서버의 `db_Disable_modifications`는 서버만 쓴다(`logtb_disable_update`/`logtb_enable_update`). 보관 세션을 다른 접근 모드의 브로커로 재개하면 카운터를 새 타입으로 다시 정한다.
2. **wire의 요청 검사는 폴드 경계가 한다.** `network_sr.c`가 `CHECK_DB_MODIFICATION`으로 표시한 요청의 in-process 스텁 27개가 서버 절반에 들어가기 전에 트랜잭션의 게이트를 묻는다(`modification_is_refused`). 거절은 `exit_server`가 롤백하고 `reset_on_commit`을 남긴다(`return_error_to_client`와 같은 일).
3. **경계 reset은 드라이버 연결을 닫는다.** 커밋·롤백이 reset 표를 묻고, RESET이면 그 경계에서 요청 루프가 끝난다([#121](https://github.com/xmilex-git/workspace/issues/121) D3).
4. **접속 판정은 세션 수립 때 한 번, 엄격하게**(#121 D2). reset 표가 첫 경계에서 닫을 조합(read-write×standby, slave-only×active, 복제 지연×standby, to-be-standby의 일반 클라이언트, maintenance)과 replica가 아닌 서버의 replica-only 브로커를 `CAS_ER_FREE_SERVER`로 거절한다. 판정을 통과한 뒤 서버가 to-be-standby로 바뀌어 등록이 거절돼도 같은 오류로 바꿔 보낸다. 드라이버는 이 오류에 다음 altHost로 간다.

#121 D8은 "편입된 `CHECK_MODIFICATION_*` 매크로를 `tdes->disable_modifications`로 일원화"였고 옛 구현은 그에 따라 읽기 전용 타입의 tdes 게이트를 1로 심었다. 그러면 develop에서 실행되던 문장이 서버에서 거절된다: 읽기 전용(RO) 브로커에서 `SELECT 시리얼.NEXT_VALUE`와 savepoint는 develop(CAS 경유)에서 성공하는데, tdes 게이트가 1이면 `serial.c`가(CS 클라이언트라면 wire 검사도) -581을 낸다. 모델의 비교 cfg `mutant-d8-tdes`가 이 차이로 `SameAsClient`를 위반한다. 그래서 D8의 뜻(프로세스 전역을 client 절반이 쓰지 않는다)만 남기고 방법을 1번으로 바꿨다(사용자 확인 2026-11-18).

검증(`cas-fold-v2`): 같은 문장을 develop 설치본의 CAS와 폴드 세션에 돌린 출력이 일치(RW·RO·SO 브로커, `read_only` 서버; 툴링 scratch `fold-v2/b3/smoke/smoke_b3.sh`), 계측 빌드에서 demotion·promotion·maintenance·등록 경합·교차 브로커 재개 실행 6건을 모델이 수용.

## Considered Options

- **#121 D8 그대로(매크로가 tdes 게이트를 읽고, 읽기 전용 타입은 tdes 게이트 1)**: 기각 — RO 브로커의 `NEXT_VALUE`·savepoint가 -581이 되고, CS 클라이언트(`csql -r`)의 서버 쪽 동작도 바뀐다.
- **진입점 매크로가 세션 카운터와 tdes 게이트를 함께 읽기(경계 검사 없이)**: 기각 — 진입점 매크로를 지나지 않는 요청(savepoint, flush)이 standby에서 통과하고, CS에서는 서버가 롤백·`reset_on_commit`으로 답하던 거절이 진입점의 단순 오류로 바뀐다.
- **관용 접속(standby에도 read-write 세션을 받고 문장마다 -581)**: #121 D2에서 이미 기각 — failover 뒤 옛 active가 세션을 받아 드라이버가 새 active로 가지 못한다.
