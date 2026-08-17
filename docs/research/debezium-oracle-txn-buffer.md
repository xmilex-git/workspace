# Debezium Oracle 커넥터(LogMiner)의 transaction buffering 구현 조사

- 조사일: 2026-08-17
- 대상 버전:
  - **소스**: 로컬 clone `~/htap-cdc/debezium` (branch `cubrid-connector`, `git describe` = **v3.0.0.Final**-4). 아래 소스 인용의 파일 경로·라인 번호는 모두 이 트리 기준.
  - **문서**: 동일 트리의 `documentation/modules/ROOT/pages/connectors/oracle.adoc` (3.0 기준) + main branch 최신 adoc(raw.githubusercontent.com, 2026-08-17 fetch — ehcache 문서화는 3.0 adoc에 없고 이후 버전에서 추가됨).
- 용도: CUBRID 커넥터 transaction-buffer 정책 결정(wayfinder #49)의 선례 조사.

경로 축약: `OCC` = `debezium-connector-oracle/src/main/java/io/debezium/connector/oracle/OracleConnectorConfig.java`, `ALEP` = `.../logminer/processor/AbstractLogMinerEventProcessor.java`, `MXB` = `.../logminer/LogMinerStreamingChangeEventSourceMetricsMXBean.java`, `DOC` = `documentation/modules/ROOT/pages/connectors/oracle.adoc`.

---

## 1. `log.mining.buffer.type` 옵션과 기본값

정의: `OCC` L334-349 (`Field.create("log.mining.buffer.type")`, `.withEnum(LogMiningBufferType.class, LogMiningBufferType.MEMORY)` → **기본값 `memory`**). enum과 각 processor 매핑은 `OCC` L1418-1478 (`LogMiningBufferType`).

| 값 | 구현 클래스 | 동작 |
|---|---|---|
| `memory` (기본) | `MemoryLogMinerEventProcessor` | JVM heap에 전 트랜잭션 데이터 버퍼링. 재시작 시 버퍼 비영속 — "When this option is active, the buffer state is not persisted across restarts. Following a restart, recreate the buffer from the SCN value of the current offset." (`DOC` L3946-3953) |
| `infinispan_embedded` | `EmbeddedInfinispanLogMinerEventProcessor` | embedded Infinispan cache로 버퍼링 + 디스크 영속 (`OCC` L345) |
| `infinispan_remote` | `RemoteInfinispanLogMinerEventProcessor` | 원격 Infinispan cluster(Hotrod client)로 버퍼링 + 영속 (`OCC` L347) |
| `ehcache` | `EhcacheLogMinerEventProcessor` | embedded Ehcache로 버퍼링 + 디스크 영속 (`OCC` L348). 3.0 코드에는 존재하나 3.0 문서에는 미기재(`grep -c ehcache` = 0), main branch 문서에 정식 기재(main adoc L1289 `[[oracle-event-buffering-ehcache]]`) |

Infinispan buffer는 문서상 **incubating** — "The Infinispan buffer type is considered incubating; the cache formats may change between versions and may require a re-snapshot." (`DOC` L1056).

버퍼는 왜 필요한가(문서의 설계 배경): Oracle redo에는 commit/rollback 미확정 변경이 interleave되어 오므로, commit 확인 전까지 내부 버퍼에 보관하고 commit 시 Kafka로 방출, rollback 시 폐기 (`DOC` L976-982 "Event buffering").

## 2. 트랜잭션별/전역 메모리·바이트 한도

**바이트 기반 한도는 어느 buffer type에도 없다.** 존재하는 유일한 상한은 **트랜잭션당 이벤트 개수** 한도:

- `log.mining.buffer.transaction.events.threshold` (`OCC` L352-362): 기본 **0 = 무제한** ("Defaults to 0, meaning that no threshold is applied and transactions can have unlimited events."). 초과 시 해당 트랜잭션 전체를 abandon.
- 집행 지점: `ALEP` L1592-1595 (`addToTransaction()`에서 `isTransactionOverEventThreshold()` → `abandonTransactionOverEventThreshold()`), 판정 L1863-1868, 처리 L1870-1877 — WARN 로그 + `metrics.incrementWarningCount()` + cache 제거 + `incrementOversizedTransactionCount()`.

전역(모든 트랜잭션 합산) 한도는 이벤트 수 기준으로도 없다. `memory` 타입에서 heap을 보호하는 것은 사실상:
1. 위 events threshold(옵트인),
2. `log.mining.transaction.retention.ms`(시간 기반 abandon, §3),
3. 운영자가 heap을 워크로드에 맞게 잡으라는 문서 경고 — "If you use the `memory` buffer setting, be sure that the amount of memory that you allocate to the Java process can accommodate long-running and large transactions in your environment." (`DOC` L987-990),
4. 근본적으로는 off-heap(spill) buffer type으로 전환하는 것.

## 3. `log.mining.transaction.retention.ms` 의미

- 정의: `OCC` L172-182. 기본 **0** = "all transactions are retained"(commit/rollback까지 무기한 보관).
- 문서 의미: "Any transaction that exceeds this configured value is **discarded entirely**, and the connector does **not emit any messages** for the operations that were part of the transaction." (`DOC` L4066-4074) → **초과 트랜잭션 데이터는 다운스트림에서 영구 유실**된다 (에러로 죽지 않고 조용히 — 단 WARN 로그와 metric은 남김).
- 구현: `ALEP` L1880-1936 `abandonTransactions(Duration retention)`:
  - 임계 SCN 계산은 DB 질의로 수행 — `getLastScnToAbandon()` L1966-1992가 `SqlUtils.getScnByTimeDeltaQuery(lastProcessedScn, retention)`(TIMESTAMP↔SCN 변환)를 실행, 실패 시 트랜잭션 change time 기반 fallback.
  - start SCN ≤ 임계 SCN인 모든 트랜잭션을 cache에서 제거하며 **WARN 로그** 2종("All transactions with SCN <= {} will be abandoned.", "Transaction {} … is being abandoned." L1896, L1902) + `metrics.addAbandonedTransactionId(key)` L1909.
  - abandon 후 **`offsetContext.setScn(thresholdScn)` (L1931)** — offset을 임계 SCN으로 전진시키므로 재시작해도 해당 트랜잭션은 복구 불가(유실 확정), 그리고 oldest txn이 offset을 무한정 잡아두는 것을 끊어 archive log 만료로부터 offset을 보호한다.
  - abandon된 트랜잭션의 후속 이벤트가 도착하면 `abandonedTransactionsCache`로 식별하여 skip ("Event for abandoned transaction {}, skipped." `ALEP` L1577-1579).
- retention의 1차 목적은 heap 보호라기보다 **long-running 트랜잭션이 restart SCN을 오래된 archive log에 묶어두는 것 방지**이다(§5 참조). heap 보호는 부수 효과.

## 4. 버퍼 관련 JMX 스트리밍 metric (MXBean getter → JMX attribute명)

`MXB` (LogMinerStreamingChangeEventSourceMetricsMXBean.java) 기준:

- `NumberOfActiveTransactions` (L194) — 버퍼 내 현재 활성 트랜잭션 수
- `NumberOfRolledBackTransactions` (L199), `RolledBackTransactionIds` (L365)
- `NumberOfOversizedTransactions` (L204) — events.threshold 초과로 폐기된 수 (`DOC` L4550-4553)
- `AbandonedTransactionIds` (L358), `AbandonedTransactionCount` (L360) — retention 초과로 abandon된 최근 트랜잭션 (`DOC` L4573-4580)
- `OldestScn` (L145), `OldestScnAgeInMilliseconds` (L150) — 버퍼 내 가장 오래된 트랜잭션의 start SCN/나이. **버퍼 적체(lag/heap 위험) 알람의 핵심 지표**
- `MillisecondsToKeepTransactionsInBuffer` (L111) / legacy `HoursToKeepTransactionInBuffer` (L63) — retention 설정값 노출
- `RegisteredDmlCount` (L81) — 버퍼에 등록된 DML 수
- 처리량·지연: `CommitThroughput` (L254), `LagFromSourceInMilliseconds` (L317, min/max L325/L333), `LastCommitDurationInMilliseconds` (L274) 등
- **버퍼의 JVM 메모리 사용량(bytes) metric은 없다.** 메모리류 metric은 Oracle 서버 세션 측 `MiningSessionUserGlobalAreaMemoryInBytes`/`...MaxMemoryInBytes`, `MiningSessionProcessGlobalAreaMemoryInBytes`/`...MaxMemoryInBytes` (L338-353) 뿐이며 이는 DB의 UGA/PGA이지 커넥터 heap이 아니다.

## 5. 재시작/재접속 시 resume 위치와 영속 버퍼의 상호작용

- **restart SCN = 버퍼 내 가장 오래된 in-flight 트랜잭션의 start SCN - 1.** 매 mining iteration 종료 시 `calculateNewStartScn()` (`ALEP` L374-428)이 `offsetContext.setScn(minCacheScn.isNull() ? endScn : minCacheScn.subtract(Scn.valueOf(1)))` (L418, LOB off 경로; LOB on 경로 L404)로 offset을 기록한다. 즉 in-flight 트랜잭션이 있는 한 offset은 그 시작점 뒤로 묶인다.
- `memory` 타입: 재시작 시 버퍼가 사라지므로 offset SCN(=oldest in-flight start - 1)부터 **redo를 다시 읽어 버퍼를 재구축**한다 (`DOC` L3946-3953). 이미 방출한 커밋 트랜잭션의 중복 방출은 processed-transactions 추적(`isRecentlyProcessed`, `ALEP` L1581-1584)과 commit SCN offset으로 억제.
- `infinispan_*`/`ehcache` 타입: 버퍼가 디스크에 영속 — "All caches should be configured this way to avoid loss of transaction events across connector restarts if a transaction is in-progress." (`DOC` L1016-1017). 재시작 시 캐시가 preload되어 in-flight 이벤트가 보존된다 (`AbstractInfinispanLogMinerEventProcessor.java` L23 "uses Infinispan to persist the transaction cache across restarts on disk").
- `log.mining.buffer.drop.on.stop` (`OCC` L406-414, 기본 **false**): true면 graceful stop 시 영속 캐시 삭제. 문서는 "Set to `true` only in testing or development environments." (main adoc, drop.on.stop 항목). embedded infinispan의 close()에서 dropBufferOnStop이면 4개 캐시 clear + removeCache (`EmbeddedInfinispanLogMinerEventProcessor.java` L88-103).
- 주의(문서 IMPORTANT, `DOC` L1056-1061): infinispan buffer를 쓰던 커넥터를 제거해도 캐시 파일은 자동 삭제되지 않음 — 같은 위치를 재사용하려면 수동 삭제 필요.

## 6. 명시적 fail-fast / OOM 방지 장치

**heap 사용량을 감시해 abort하는 메커니즘은 없다.** 존재하는 것은 전부 "트랜잭션 단위 포기" 계열:

- events threshold 초과 시 abandon + WARN (`ALEP` L1870-1877) — fail이 아니라 데이터 폐기로 방어.
- retention 초과 시 abandon + WARN (`ALEP` L1880-1936).
- 그 외에는 문서 경고(heap 크기 조정, `DOC` L987-990)와 off-heap buffer type 권고가 전부. 즉 **기본 설정(memory + threshold 0 + retention 0)에서는 초대형/초장기 트랜잭션이 그대로 OOM으로 이어질 수 있고**, 이는 실제로 겪어온 문제다(과거 DBZ-3808 "Fix OutOfMemoryError with MemoryTransactionCache", PR debezium/debezium#2667).

## 7. Infinispan/Ehcache spill 채택 시 운영 부담

- **캐시 개수**: 버퍼는 단일 캐시가 아니라 캐시 4종 — `transactions`, `events`, `processed-transactions`, `schema-changes` (`CacheProvider.java` L18-33; 문서 IMPORTANT `DOC` L1021-1026 "There should be a cache defined for `transactions`, `events`, `processed-transactions`, and `schema-changes`."). 최신(main) ehcache 문서에는 `rollbacks`까지 **5종** (main adoc L1321-1327 예시).
- **infinispan_embedded**: 캐시 4종 각각에 대해 **XML 설정을 커넥터 property로 직접 기입** (`log.mining.buffer.infinispan.cache.transactions|events|processed_transactions|schema_changes`, `OCC` L363-405). buffer type이 infinispan이면 이 필드들은 **필수**(`validateLogMiningInfinispanCacheConfiguration`, `OCC` L2061-2068). JSON property 안에 XML을 넣어야 하므로 줄바꿈 제거/`\n` 치환 필요 (`DOC` L1027-1029 NOTE). 영속 file-store 경로는 모든 런타임 환경에서 접근 가능한 공유 위치여야 함 (`DOC` L1018).
- **infinispan_remote**: 위 4종 XML + **별도 Infinispan 서버 클러스터 운영** + Hotrod client 설정. 최소 필수 `log.mining.buffer.infinispan.client.hotrod.server_list` (`OCC` L2046-2058 validation; `DOC` L1063-1071). `log.mining.buffer.infinispan.client.*` prefix가 Hotrod `infinispan.client.*`로 그대로 전달.
- **ehcache**: 외부 서버는 불필요하나 `log.mining.buffer.ehcache.global.config`(persistence 디렉터리 등) + 캐시별 `...transactions|processedtransactions|schemachanges|events(.rollbacks은 신버전).config` XML fragment가 **필수** (`OCC` L596-637, `validateEhcacheConfigFieldRequired` L2170-2177; global config에는 `<cache/>`/`<default-serializers/>` 금지 — L2153-2168). 캐시별 heap entry 수·disk bytes 상한 설정 가능 (main adoc L1308-1314 `<resources><heap unit="entries">512</heap><disk unit="B">1024000000</disk></resources>`).
- **직렬화 비용**: ehcache는 이벤트 타입별 커스텀 serializer 계층이 통째로 필요했다 (`.../processor/ehcache/serialization/` 아래 20여 클래스) — spill 구현의 숨은 비용.
- **품질 주의**: Infinispan buffer는 incubating(캐시 포맷 변경 시 re-snapshot 가능성, `DOC` L1056), ehcache는 상한 도달 시 조용히 entry를 evict하는 버그가 있었음(DBZ-8874, Debezium 3.1/3.2 release notes).

## 8. (보너스) bytes 기반 cap 부재에 대한 논의

- bytes-cap을 도입하자는 명시적 설계 논의 문서는 확인하지 못했다. 대신 프로젝트의 실제 궤적이 답을 보여준다:
  - OOM 발생(DBZ-3808, PR debezium/debezium#2667 "Fix OutOfMemoryError with MemoryTransactionCache") → 해법으로 bytes-cap이 아니라 **off-heap/영속 buffer type 추가(Infinispan, 이후 Ehcache)** 와 **event-count threshold**(`log.mining.buffer.transaction.events.threshold`)를 선택.
  - 추정 가능한 이유(공식 근거 아님, 코드 구조에서 유추): 이벤트는 파싱된 객체(LogMinerEvent)로 보관되어 정확한 bytes 계측 비용이 크고, 개수 기준이 구현·운영 모두 단순하다. 캐시 backend별(heap/Infinispan/ehcache)로 bytes 의미가 달라지는 것도 한 요인 — bytes 상한은 ehcache의 `<disk unit="B">`처럼 **backend 설정으로 위임**되어 있다 (main adoc L1308-1314).
  - threshold 경로 자체의 후속 버그: DBZ-8880 "Transaction events are not removed when transaction event count over threshold" (3.1/3.2 release notes) — count 기반 상한조차 event cache 정리 누락 이슈가 있었다.
- 커뮤니티 실전 가이드(공식 블로그 debezium.io "Debezium for Oracle - Part 3: Performance and Debugging", 2023-06-29)도 memory buffer OOM의 대응책으로 heap 증설 또는 infinispan 전환을 안내한다.

---

## CUBRID 커넥터 정책에 주는 시사점 (요약)

1. Debezium의 선례는 "**기본 = 무제한 heap 버퍼 + 옵트인 안전장치(count threshold, time retention) + spill은 별도 buffer type**" 구조. bytes-cap은 어디에도 없다.
2. 안전장치 발동의 일관된 패턴: **fail하지 않고 트랜잭션 단위로 discard + WARN 로그 + 전용 metric(Oversized/Abandoned) + offset 전진**. 유실은 다운스트림에 침묵(스키마상 표시 없음)이므로 metric 알람이 유일한 감지 수단.
3. restart SCN을 oldest in-flight start-1로 유지하는 설계와 retention의 결합 — retention은 heap보다 **offset이 로그 보존기간을 벗어나는 것**을 막는 장치로 이해해야 한다.
4. spill 채택 비용이 상당함(캐시 4~5종 XML 설정, serializer 구현, incubating 품질) — 초기 버전에서 memory-only + count/time 상한 + 관측 metric으로 시작하는 것이 Debezium 궤적과 일치한다.
