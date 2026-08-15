# 이벤트 position은 결정적 아이템 카운터로 합성 — offset 4키·_version UInt64 (§7.4 개정)

CUBRID→ClickHouse HTAP POC(지도: xmilex-git/workspace#30, 판정 티켓: #36)에서 Debezium
offset과 ClickHouse `_version`의 재료가 될 **이벤트 position**을, 커넥터가 유지하는
**결정적 비-TIMER 아이템 카운터**로 합성하기로 했다.

근거가 된 P0 실측(#33 덤프 9종):

- `CUBRID_LOG_ITEM`에는 **per-item position이 없다.** LSA는 `cubrid_log_extract()`의
  배치 커서(`in_lsa → out_lsa`)로만 존재한다.
- flat `uint64_t` LSA의 분해는 **low 48비트 = pageid, high 16비트 = offset**으로 실측
  확정했다(pageid 176→923 단조 증가, offset 항상 < 16384). 따라서 **raw uint64는 비교
  불가** — offset이 상위 비트라 페이지가 넘어가면 raw 값이 역행한다. 외부로 나가는 모든
  표현은 (pageid, offset) 명시 직렬화만 쓴다.
- 트랜잭션 경계: DML(trid 부착)이 선행하고 `COMMIT`/`ABORT` DCL이 사후 도착한다.
  trid는 서버 런타임 id로 재사용될 수 있으나, DCL 수신 시 해당 trid 버퍼를 비우므로
  스트림 내 충돌은 없다.

배치 out_lsa를 position으로 쓰면 재시작 시 배치 경계가 달라져 **같은 이벤트가 원본보다
낮은 version을 받는 역전**이 가능하다(늦은 이벤트가 이른 이벤트에게 짐 → RMT 오수렴).
카운터는 이 문제가 없다: 로그는 append-only라 **고정 LSA에서의 비-TIMER 아이템 시퀀스는
결정적**이므로, offset에 카운터를 영속화해 재시작 시 이어 세면 같은 이벤트는 언제나 같은
번호를 받는다.

## 확정 규칙

**Debezium offset — flat 4키** (#32의 "flat 3키" 결정을 이 ADR로 개정):

```json
{ "page_id": ..., "lsa_offset": ..., "seq": ..., "epoch": 0 }
```

- `page_id`/`lsa_offset`: 재시작 anchor. **아직 COMMIT되지 않은 가장 오래된 in-flight
  트랜잭션의 첫 DML이 도착한 배치의 경계 LSA** (없으면 마지막 배치 out_lsa). COMMIT
  위치에서 재개하면 그보다 먼저 시작한 진행 중 트랜잭션의 DML을 잃는다 — Debezium
  Oracle(LogMiner)의 restart SCN과 같은 구조.
- `seq`: anchor 시점의 누적 비-TIMER 아이템 카운터. 재시작 시 이 값부터 이어 센다.
- `epoch`: HA failover 세대 자리 예약. POC에서는 상수 0 (HA는 지도 범위 밖).

**`_version` (UInt64)** = `epoch[상위 16비트] | event_counter[하위 48비트]`.
DML 이벤트마다 카운터가 고유하므로 sub_sequence가 필요 없다(같은 트랜잭션 내 같은 PK
연속 변경도 카운터 순서 = 문장 순서). 2^48이면 초당 10만 이벤트로 89년.
htap-cubrid.md §7.4의 초안(`UInt128 = epoch|page_id|offset|sub_seq`)에서 이탈한다 —
per-item LSA가 없어 page/offset 재료 자체가 존재하지 않기 때문이다.

**envelope 노출**: `source.lsn` = event_counter (필드명은 Debezium 관례, 의미는 LSA가
아니라 카운터). #31의 `ExtractNewRecordState` + `add.fields=op,source.lsn` 파이프라인이
무변경으로 성립한다. 관측용으로 `source.tx_id`(trid), `source.commit_ts`(COMMIT DCL
timestamp)를 함께 노출하되 `_version`으로 승격하지 않는다.

**트랜잭션 버퍼링**: trid별로 DML을 버퍼링, COMMIT DCL 수신 시 로그 순서대로 publish,
ABORT DCL 수신 시 폐기. COMMIT 전 publish 금지. 버퍼는 **in-memory 무제한**(30k행
단일 트랜잭션 실측이 68배치로 도착 — 전량 힙에 든다). 상한·spill은 제품 단계 과제.

**TIMER → heartbeat**: TIMER 아이템(~1초, 유휴에도 out_lsa 전진)은 Debezium heartbeat
메커니즘에 매핑해 레코드 없이 offset만 전진시킨다. 유휴 후 재시작의 재스캔 비용과
아카이브 로그 보존 창 경합을 없앤다.

**재전송 semantics**: 커넥터는 at-least-once를 보장한다. 재시작 시 anchor부터 재추출하며
그 이후의 committed 트랜잭션 전부가 재발행될 수 있다. 재발행 이벤트는 원본과 동일한
event_counter(따라서 동일한 `_version`)와 동일한 내용을 가지므로 RMT canonical view에서
정확히 수렴한다. exactly-once·중복 억제는 하지 않는다(#31 결정 유지). ABORT된
트랜잭션은 원 실행이든 재전송이든 발행되지 않는다.

## Considered Options

- **`max_log_item=1`로 아이템 단위 out_lsa 확보**: replay 결정성 가정이 필요 없는 유일한
  무패치 대안이나, 아이템당 RPC 1회 — 30k행 트랜잭션 = 30k 왕복으로 처리량 붕괴. 기각.
- **엔진 패치로 per-item LSA 노출**: 가장 정직한 해법이나 D9(우회 우선)·ADR 0003과 같은
  무패치 기조에 역행. 기각이 아니라 **fallback으로 보존** — replay 결정성 검증이 깨지면
  엔진 최소 패치 티켓 승격(사용자 확인 필수)으로 간다.
- **배치 out_lsa + 배치 내 index를 position으로**: 재시작 시 배치 경계 비결정성으로
  version 역전 가능(위 본문). 기각.

## Consequences

- **전제 2건은 실측 티켓으로 검증한다**(둘 다 이 ADR의 성립 조건):
  ① **replay 결정성** — 같은 LSA에서 2회 추출한 비-TIMER 아이템 시퀀스 diff. 깨지면
  엔진 패치 fallback 승격. → **검증 통과** (#43, 2026-08-16): 동일 start_ts 2회 추출,
  s08 30k-행 트랜잭션 포함 비-TIMER 30,072 아이템(정규화 90,182라인)이 byte-identical.
  배치 경계는 달랐음(65 vs 66 라운드) — 카운터 position 성립. ② **크래시 복구 트랜잭션의 DCL 방출 여부** — 서버 kill 후
  recovery가 undo한 트랜잭션이 ABORT DCL을 내보내는지. 안 내보내면 좀비 trid 버퍼
  오염이 가능하므로 "서버 재연결 감지 시 전체 버퍼 폐기" 규칙을 확정한다.
- **savepoint 부분 rollback은 정합성 미보장 — POC 알려진 제약.** s06 실측: `ROLLBACK TO
  SAVEPOINT`로 취소된 DML이 보상 이벤트 없이 스트림에 그대로 남고 COMMIT까지 도착한다.
  COMMIT-publish 규칙은 이 경우 **팬텀 행**(커밋된 적 없는 INSERT/UPDATE)을 ClickHouse에
  싣는다. 스트림만으로는 식별이 원천 불가능해 커넥터 측 완화가 없다. POC 완료 계약
  (differential check)의 워크로드에서 savepoint를 배제하고, 프로덕션 경로는 supplemental
  log에 savepoint 마커/보상 이벤트를 추가하는 엔진 보강이 필요하다(지도 fog에 기록).
- 카운터는 커넥터 프로세스 상태가 아니라 **offset의 일부**다 — Kafka Connect offset
  topic이 유일한 영속화 지점이며, offset 초기화(스트림 재시작)는 카운터 세대가 바뀌는
  것이므로 스냅샷 재수행 없이 offset만 지우는 운영은 금지다(version 비교 축이 무너진다).
