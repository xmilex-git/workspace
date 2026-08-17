# 트랜잭션 버퍼 정책은 Debezium Oracle parity — opt-in count threshold·retention, 초과 시 abandon

CUBRID Debezium 커넥터의 trid별 트랜잭션 버퍼(ADR 0004: COMMIT-publish / ABORT-폐기,
in-memory 무제한)에 제품 상한 정책을 정한다(지도: xmilex-git/workspace#48, 티켓: #49).
결정: **Debezium Oracle 커넥터(LogMiner)의 정책 구조를 그대로 따른다.** 상세 선례 조사는
[docs/research/debezium-oracle-txn-buffer.md](../research/debezium-oracle-txn-buffer.md)
(Debezium v3.0.0.Final 소스 + 공식 문서 기준).

CUBRID CDC는 Postgres logical decoding처럼 서버가 커밋-순서 완성본을 주는 모델이 아니라
Oracle redo log처럼 **log-order raw 아이템(미커밋 포함)** 을 주는 모델이므로, 트랜잭션
재조립·버퍼링이 커넥터 몫이다. 같은 문제를 가진 유일한 제품 선례가 Oracle 커넥터이고,
우리 재시작 anchor(ADR 0004)가 Oracle restart SCN과 동일 구조라 정책이 그대로 이식된다.

## 확정 규칙

- **D1 — 초과 시 동작 = abandon(트랜잭션 단위 폐기) + WARN + metric.** fail-fast나
  bytes 상한, disk spill은 도입하지 않는다. Oracle 동작 근거:
  [`AbstractLogMinerEventProcessor.java#L1870-L1877`](https://github.com/debezium/debezium/blob/v3.0.0.Final/debezium-connector-oracle/src/main/java/io/debezium/connector/oracle/logminer/processor/AbstractLogMinerEventProcessor.java#L1870-L1877)
  (threshold 초과 abandon), 폐기가 다운스트림 영구 유실임은
  [공식 문서 `log.mining.transaction.retention.ms`](https://debezium.io/documentation/reference/3.0/connectors/oracle.html#oracle-property-log-mining-transaction-retention-ms)
  에 명시.
- **D2 — 상한 단위 = 트랜잭션당 이벤트 개수만.** config
  `transaction.events.threshold` (기본 **0 = 무제한**, opt-in). 전역(합산) 상한 없음.
  Oracle 대응: `log.mining.buffer.transaction.events.threshold`
  ([문서](https://debezium.io/documentation/reference/3.0/connectors/oracle.html#oracle-property-log-mining-buffer-transaction-events-threshold)).
- **D3 — max transaction age = retention abandon.** config `transaction.retention.ms`
  (기본 **0 = 무기한**, opt-in). 초과 트랜잭션은 abandon하고 **재시작 anchor를 그
  트랜잭션 너머로 전진**시킨다(다음 oldest in-flight 시작점, 없으면 배치 out_lsa).
  abandon된 trid의 후속 이벤트는 skip 목록으로 무시한다. 1차 목적은 heap이 아니라
  **oldest in-flight가 anchor를 붙들어 supplemental log 보존기간을 넘기는 것 방지** —
  Oracle과 동일
  ([`#L1880-L1936`](https://github.com/debezium/debezium/blob/v3.0.0.Final/debezium-connector-oracle/src/main/java/io/debezium/connector/oracle/logminer/processor/AbstractLogMinerEventProcessor.java#L1880-L1936),
  offset 전진은 L1931).
- **D4 — 배포 환경 전제를 고정하지 않는다.** Oracle처럼 "heap은 워크로드의 대형·장기
  트랜잭션을 수용하도록 잡아라"는 문서 경고로 대신한다
  ([문서 buffering 절](https://debezium.io/documentation/reference/3.0/connectors/oracle.html#oracle-event-buffering)).
  예시 수치는 기술지원 세팅 가이드(#59)에서 제시.
- **D5 — 재연결 시 in-flight 규칙 = ADR 0004 anchor 재생이 곧 규칙.** in-memory 버퍼는
  영속하지 않고, 재시작 시 anchor(oldest in-flight 시작 배치 경계)부터 재추출해 버퍼를
  재구축한다. Oracle memory buffer의 재마이닝과 동일 구조
  ([문서 `log.mining.buffer.type`](https://debezium.io/documentation/reference/3.0/connectors/oracle.html#oracle-property-log-mining-buffer-type):
  "the buffer state is not persisted across restarts"). #44 검증(크래시 복구가 undone
  트랜잭션에 ABORT DCL을 방출)으로 zombie 버퍼 없음이 확인되어 별도 방어 규칙 불요.
- **운영 metric (JMX)**: `NumberOfActiveTransactions`, `NumberOfOversizedTransactions`
  (D2 발동 횟수), `AbandonedTransactionCount`/`AbandonedTransactionIds`(D3),
  `OldestInflightAgeInMilliseconds`(경보 핵심 지표 — Oracle `OldestScnAgeInMilliseconds`
  대응,
  [`LogMinerStreamingChangeEventSourceMetricsMXBean.java`](https://github.com/debezium/debezium/blob/v3.0.0.Final/debezium-connector-oracle/src/main/java/io/debezium/connector/oracle/logminer/LogMinerStreamingChangeEventSourceMetricsMXBean.java)).
  커넥터 heap bytes metric은 Oracle에도 없으며 두지 않는다.

## 트레이드오프 (명시)

**abandon = 다운스트림 영구 유실이다** — anchor가 전진하므로 재시작해도 복구되지 않고,
복구 수단은 재스냅샷뿐이다. 즉 diff-check 0 mismatch 보증은 **threshold/retention
미발동 조건 하에서만** 성립하며, 이 조건은 매뉴얼(#59)에 명시한다. 기본값이 둘 다
0(무제한)이므로 out-of-the-box에서는 유실이 없고 대신 OOM 위험을 운영자가 heap
sizing으로 진다 — Oracle도 동일한 트레이드오프를 택했다: OOM 이슈
([DBZ-3808](https://issues.redhat.com/browse/DBZ-3808), 수정
[PR #2667](https://github.com/debezium/debezium/pull/2667))를 겪고도 bytes-cap이나
fail-fast가 아니라 **커넥터 연결 지속(트랜잭션 단위 포기 + metric 경보) 우선**으로
갔다. 정합성 회복은 metric 감지 → 재스냅샷이라는 운영 절차에 위임한 것이다.

disk spill(Infinispan/Ehcache buffer type)은 배제가 아니라 **후속 과제** — 캐시 4~5종
XML 설정, 전용 serializer 계층, incubating 품질(silent eviction 버그
[DBZ-8874](https://issues.redhat.com/browse/DBZ-8874), threshold 시 event 미정리
[DBZ-8880](https://issues.redhat.com/browse/DBZ-8880))의 비용 때문에 1.0에서 뺀다.
탈출구: D1~D3는 전부 opt-in config라 spill 도입 시에도 호환 유지된다.
