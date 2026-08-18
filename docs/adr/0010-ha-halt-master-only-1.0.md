# 1.0 HA 지원 = HA halt — master-only 캡처, 노드 전환 감지 시 fail-fast, 복구는 resnapshot

CUBRID Debezium 커넥터 1.0의 HA failover 지원 수준을 정한다(지도:
xmilex-git/workspace#48, 티켓: #54). `_version`의 epoch 비트는 자리만 예약됐고
failover·split-brain·old primary 재등장은 미검증이었다(후속 리뷰 §7.5). 선례 조사는
[docs/research/cdc-ha-supplemental-precedents.md](../research/cdc-ha-supplemental-precedents.md)
(CUBRID 엔진 소스 실사 + Debezium PG·Oracle 공식 문서).

결정: **epoch 실구현도, 순수 문서 제약도 아닌 HA halt** — 캡처 대상은 master 하나로
고정하고(single master 구조상 유일한 소스), master가 아니게 된 노드 또는 다른 노드에
붙는 순간을 감지해 fail-fast하며, 복구는 resnapshot 단일 절차로 고정한다. failover 후
이어읽기는 CUBRID의 노드별 LSA 좌표계(Oracle SCN 동일성·PG17 failover slot 같은 보존
수단 부재) 탓에 엔진 보강 없이 원천 불성립이고, 선례들의 1.0급 "HA 지원"도 실체는
문서화된 수동 복구 절차라 이 수준이 parity다(Debezium PG의 "슬롯 재생성 +
`snapshot.mode=always`" 권고와 동형).

## 배경 — 조용한 오염 경로 2종

조사에서 실증·확인된, 방치 시 무경고로 잘못된 데이터를 만드는 경로:

- **경로 A — 새 master 재접속**: old master의 anchor `{page_id, lsa_offset}`는 새
  master 로그에서 좌표계가 다른 별개 값이다. 명시 에러가 아니라 "유효해 보이는 엉뚱한
  위치"로 해석될 수 있다 (#62의 버전 skew SIGSEGV와 같은 부류의 미정의 동작).
- **경로 B — 강등된 old master 재접속**: 같은 노드라 anchor 재생이 **성공**하고, 이후
  applylogdb 재실행 스트림(트랜잭션 경계·사용자·supplemental 유무가 원본과 다를 수
  있음)을 무경고 방출한다. CDC 경로에 HA 상태 게이트가 전혀 없어 실제로 굴러간다
  (`scdc_start_session()`의 유일한 거부 조건은 `supplemental_log==0`).

## 확정 규칙

- **D1 — 캡처 대상 = master 단일 노드.** standby/slave 캡처는 지원하지 않는다
  (Oracle ADG식 standby 캡처는 선례에서도 3.4-dev incubating 수준).
- **D2 — HA halt 가드 (커넥터-only, 엔진 무변경).** offset에 소스 노드 식별자를
  저장하고, 재접속 시 ① 노드가 바뀌었거나(경로 A 차단) ② 접속 노드가 master 상태가
  아니면(경로 B 차단) fail-fast한다. 식별자·master 상태 판별 수단은 구현 티켓(#66)에서
  실측 확정한다. **escape hatch**: 신뢰할 판별 수단이 없다고 판명되면 해당 축은
  문서-only 제약으로 격하하고 이 ADR에 추기한다.
- **D3 — 복구 = resnapshot 단일 절차.** DDL halt(ADR 0008)·online snapshot(ADR 0009)과
  같은 문법. failover 후 새 master를 소스로 blocking snapshot부터 다시 시작한다
  (shadow swap 표준, ADR 0009 운영 절차).
- **D4 — epoch 비트 유지.** `_version`의 epoch[16] 자리와 offset 4키의 `epoch` 필드는
  상수 0 그대로 둔다. 제거는 offset 스키마·`_version` 포맷 변경이라 오히려 비용이고,
  장래 HA 이어읽기(세대 구분)에 필요해질 개연성이 조사로 오히려 높아졌다.
- **D5 — 세팅 가이드(#59) 명기 사항.** ① HA 구성 시 `supplemental_log`를 전 승격 후보
  노드에 설정(노드별 파라미터 — Oracle과 달리 자동 전파 없음, slave 자기 로그의
  supplemental은 slave 설정에 달림) ② failover 운영 절차: 커넥터 정지 → 새 master로
  접속 재구성 → resnapshot ③ 제약: failover 시 이어읽기 미지원, HA halt 발동 조건.
- **D6 — failover 후 무중단 이어읽기는 out of scope.** epoch 실구현, 노드 간 로그
  좌표계의 엔진 보강, failover fault campaign이 걸린 별개 규모 — 이 지도(1.0)의
  destination 밖이며 재개하려면 새 지도가 필요하다. `find_lsa(시각)` 기반 중복 허용
  catch-up(RMT 멱등성 활용)은 그때의 출발 후보로만 기록한다.

## 기각한 대안

- **풀 포함(epoch 구현 + fault campaign)**: 선례 1.0조차 안 한 수준 + CUBRID는 LSA
  좌표계 문제로 엔진 보강 선행 필요 — 1.0 일정 초과.
- **순수 문서 제약(코드 무변경)**: 경로 A·B의 조용한 오염이 "운영자 절차 준수"에만
  걸림. 고객 다수가 HA 구성이라 failover는 정상 운영 이벤트 — 기술지원 관점에서 부적격.

## 추기 (2026-08-18, 구현 티켓 #66) — 판별 수단 실측 확정

D2의 두 축 모두 신뢰할 판별 수단이 확정되어 **escape hatch(문서-only 격하)는 발동하지
않았다**. 다만 식별자 축에 잔여 갭 1건을 문서 제약으로 남긴다.

- **판별 수단 = JDBC `SHOW LOG HEADER` 단일 질의** (11.5 라이브 서버 실측):
  `Ha_server_state`가 디스크 로그 헤더의 HA 상태(비-HA 서버는 `'idle'`,
  HA 노드는 `'active'`/`'standby'`/`'to-be-*'`/`'maintenance'`/`'dead'` —
  `boot.h`의 상태 문자열), `Creation_time`이 DB 생성 시각이다.
  이 문은 엔진에서 **DBA 전용**(`show_meta.c` `only_for_dba`) — 커넥터 JDBC 유저는
  DBA 그룹이어야 하며, 읽기 실패 시 가드는 조용히 건너뛰지 않고 fail-closed한다
  (#68 권한 스펙과 조율 필요).
- **노드 식별자 = `<설정 hostname>@<Creation_time millis>`**, offset의 5번째 키
  `node`(문자열)로 저장(ADR 0004의 숫자 4키에 추가; `node` 없는 기존 offset은 최초
  재접속 시 경고 없이 스탬프 — 업그레이드 경로). hostname 축이 표준 failover 절차
  (운영자가 새 master로 재지향)를, creation time 축이 `createdb`로 독립 생성된
  클러스터의 노드 전환을 잡는다.
- **허용 상태 = {`active`, `idle`}** — 그 외 전부(전이 상태 포함) fail-fast.
  스냅샷 측도 시작 전 상태 축을 검사한다(standby 데이터로 스냅샷 후 스트리밍이
  섞이는 것을 차단).
- **잔여 갭 (문서 제약)**: master를 따라가는 VIP/DNS(hostname 불변) + backup/restore로
  구축한 slave(creation time 보존)의 조합에서는 노드 전환이 식별자에 나타나지 않는다
  — 이때는 상태 축(새 master는 `active`)도 통과하므로 경로 A가 미검출될 수 있다.
  세팅 가이드(#59)에 "failover 시 반드시 커넥터 정지 → resnapshot" 절차와 함께 이
  갭을 명기한다.
- 검증: 단위 10건(경로 A/B·전이 상태·offset round-trip·legacy 스탬프) 포함 60/60
  PASS, e2e 정상 경로 PASS + offset `node` 키 실측, 라이브 경로 A 재현(재지향 후
  task FAILED·재시작 시 결정론적 재정지·원복 후 diff-check 0).

## 추기 (2026-08-18, #70) — 노드 사실 출처를 CDC in-band로 전환

가드의 판별 수단이 JDBC `SHOW LOG HEADER`(DBA 전용, 위 추기)에서 **CDC START_SESSION
응답 in-band**로 바뀌었다 (workspace#70, ADR 0011의 DBA 의존 제거를 완성하는 마지막 조각).

- **D-a — 서버가 START_SESSION 성공 응답에 `(ha_server_state, db_creation)`을 싣는다.**
  근거: ① `SHOW LOG HEADER`는 클라이언트측 `only_for_dba` 하드 게이트라 비-DBA 경로가
  없다(grant 불가) ② HA 상태는 원래 모든 클라이언트가 로그인 credential로 받는 값이라
  (csql 프롬프트) 노출 확대가 아니다 ③ PG replication 연결의 `IDENTIFY_SYSTEM`
  (systemid+timeline) parity ④ **정확성 개선**: 사실이 JDBC(broker 경유)가 아니라 로그
  스트림이 실제로 나오는 그 서버에서 온다. 에러 응답은 기존 bare int 유지.
- **식별자 재료 = `db_creation`(디스크 로그 헤더, epoch 초)×1000.** 종전 구현의
  `Creation_time`(=`vol_creation`)과 값이 다르므로 **이 빌드 이전에 스탬프된 offset은
  최초 재접속에서 경로 A halt가 난다** — 1.0 릴리스 전이라 설치 기반이 없고, 복구는
  표준 resnapshot 절차 그대로 (e2e에서 실측·확인).
- **상태 축 값 변화**: 비-HA 서버의 라이브 상태는 `active`(구 디스크 헤더는 `idle`).
  허용 집합 {active, idle}은 두 출처 모두 포함하므로 판정 불변.
- **blocking snapshot의 상태 축**: on-demand blocking snapshot은 barrier 세션을 열지
  않으므로 자체 상태 검사가 없다 — 라이브 스트리밍 세션(연결 시 양 축 검증, 재연결마다
  재검증)의 우산 아래에서만 실행된다는 것을 전제로 한다(세션 시작 1회 검사라는 D11
  성격과 동일). 초기·중단 재개 스냅샷은 barrier 세션의 사실로 상태 축을 검사한다.
- 구버전 서버(사실 없는 4바이트 응답)는 연결 단계에서 명시적 버전 에러로 정지
  (ADR 0011 D10; #62 lockstep — 런타임 협상 없음).
