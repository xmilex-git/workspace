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
