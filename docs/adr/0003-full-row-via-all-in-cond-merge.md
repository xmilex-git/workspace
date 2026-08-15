# full row 복원은 all_in_cond=1 병합 — 엔진 무변경 (§7.5 선택지 2)

CUBRID→ClickHouse HTAP POC(지도: xmilex-git/workspace#30, 판정 티켓: #35)에서 current-state
복제본에 필요한 **full after-image**를, CUBRID CDC 이벤트의 `cond`(before)와 `changed`(after)를
커넥터가 병합해 만들기로 했다. `cubrid_log_set_all_in_cond(1)`을 켜면 UPDATE/DELETE의 cond가
undo 레코드에서 완전 복원한 **테이블 전 컬럼 before-image**가 됨을 소스(log_manager.c
`cdc_make_dml_loginfo()` — 플래그는 "PK만 추리는 최적화"를 끄는 것뿐)와 실측(s04 덤프,
NULL 시나리오 덤프)으로 확정했다. `full after = cond(before) ⊕ changed(after)` — 상태 저장 없음,
추가 조회 없음, 엔진 패치 없음. htap-cubrid.md §7.5가 선택지 1(엔진 확장)을 권장한 것은
all_in_cond의 실동작을 모르던 시점의 판단이다.

## Considered Options

- **선택지 1 — 엔진 패치로 typed full image 제공**: 이미 있는 정보의 재전송이라 패치가
  정당화되지 않음 (D9: 우회 우선). 기각이 아니라 **fallback으로 보존** — 후속 검증(E2E 등)에서
  병합에 구멍이 나면 JDBC lookback이나 state store가 아니라 엔진 최소 패치 티켓 승격(사용자
  확인 필수)으로 간다. 구멍은 로그에 이미 있는 정보의 *표현* 문제일 가능성이 높아 패치 반경이
  작고, lookback(read-skew)·state store(복구 복잡도)는 비용이 항구적이기 때문.
- **선택지 3 — embedded state store**: 저장소 규모·복구 복잡도. 기각.
- **선택지 4 — commit 후 JDBC PK lookup**: 조회 시점에 다음 트랜잭션이 반영된 값을 읽는
  read-skew 근본 결함. 기각.
- **선택지 5 — ClickHouse sparse-update 엔진**: #31에서 잠근 RMT 경로를 버리게 됨. 기각.

## Consequences

- **DELETE는 PK만으로 충분** — sink는 `_version` + `__deleted` RMT라 tombstone 행의 비-PK
  컬럼 값은 무의미. Debezium+PostgreSQL의 기본(REPLICA IDENTITY DEFAULT = before에 PK만)과
  같은 계약이다. all_in_cond=1이 주는 DELETE full before는 요구 조건이 아니라 공짜 보너스로,
  Debezium envelope의 `before`에 그대로 싣는다 (UPDATE도 동일 — before를 채운다, D6의 표준
  envelope 충실도 우선). PG의 REPLICA IDENTITY FULL과 달리 추가 로깅 비용이 없다 — cond
  확장은 어차피 기록되는 undo 로그에서 추출 시점에 복원된다.
- 커넥터 구현이 지켜야 할 실측 계약 3건: ① NULL과 `''`는 둘 다 len=0 — 판별자는 데이터
  포인터의 NULL 여부뿐. ② changed는 SET 절이 아니라 실제 값 diff — no-op UPDATE는 DML 아이템
  없이 COMMIT만 남으므로 "DML 없는 커밋"이 정상. ③ CHAR 후행 공백·collation 동등 값은 "안
  바뀜" 처리될 수 있음(코드 근거, state 복제에는 무해).
