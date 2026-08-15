# Debezium 소스 커넥터 개발 계약 — SPI·offset·snapshot·JNA 선례

티켓: xmilex-git/workspace#32 (지도 #30, D6·D7 실행 가능성 검증)
조사일: 2026-08-15
1차 소스: debezium 본체 clone `7bb44e29` (2026-08-14, 3.7.0-SNAPSHOT) 및
debezium-connector-informix clone (각 `.git_ignored_dir/scratch/` shallow clone).
아래 file:line 인용은 모두 이 두 clone 기준. 웹 인용은 각 절에 URL 명기.

## 핵심 결론 3줄

- **(a) 스켈레톤**: 필수 클래스는 **약 20개**, 전부 `debezium-connector-common` 모듈 위에
  구현한다 (relational/pipeline 프레임워크가 `debezium-core`에서 이 모듈로 추출됨).
  레퍼런스는 **Informix 커넥터를 거의 1:1로 미러**하되, schema history만 Postgres 모델
  (non-historized)로 바꾼다. §1에 티켓이 그대로 따라갈 클래스 목록.
- **(b) LSA offset**: **충돌 없음.** offset은 "flat `Map<String, primitive>`" 계약이고,
  MySQL(binlog_filename+position+row+gtid), Informix(commit/change/begin lsn) 등 다필드
  position 선례가 이미 다수. LSA는 `page_id`(Long)·`lsa_offset`(Long)·`epoch`(String 또는
  signed-bit Long)의 **평탄한 키 3개로 분해**하면 된다. 중첩 Map/Struct만 금지. §2.
- **(c) JNA**: **hard blocker 없음.** 우려하던 "native lib는 classloader 하나만" JVM 규칙은
  `System.loadLibrary` 경유에만 적용되고, **JNA는 대상 라이브러리를 자체 `dlopen`으로 열므로
  해당 없음** (JNA `Native.open`, source-code 확인). Connect **source** 커넥터가 native .so를
  요구하는 공식 선례도 존재 (Debezium Oracle XStream). 남는 것은 운영 제약 7건 — §5.

---

## 1. 커넥터 골격 (조사 항목 1)

### 1.1 모듈 의존성 — debezium-core가 아니라 debezium-connector-common

relational·pipeline 프레임워크(`RelationalDatabaseSchema`, `BaseSourceTask`,
`ChangeEventSourceCoordinator`, `JdbcConnection` 등)는 현재 **`debezium-connector-common`**
모듈에 있다. Informix pom의 의존 블록이 그대로 본보기: `debezium-connector-common`,
`debezium-config`, `debezium-util`, `debezium-storage-kafka`, `debezium-storage-file`,
`debezium-connect-plugins` + JDBC 드라이버(`provided`) + `connect-api`(`provided`)
(`debezium-connector-informix/pom.xml:171-205`). CUBRID는 여기에 `net.java.dev.jna:jna` 추가.

### 1.2 클래스 목록 (스켈레톤 티켓이 그대로 구현할 순서)

Informix 전 클래스를 sqlserver와 교차 확인한 결과, 필수 계약은 두 커넥터에서 동일한 20개.

| # | 클래스 | 상위 타입 (정확한 supertype) | 근거 (clone 내 선언 위치) |
|---|---|---|---|
| 1 | `Module` | 없음 (유틸) — `build.version` 리소스 읽음 | informix `Module.java` |
| 2 | `CubridConnector` | `RelationalBaseSourceConnector` | `debezium-connector-common/.../connector/common/RelationalBaseSourceConnector.java:24` |
| 3 | `CubridConnectorConfig` | **`RelationalDatabaseConnectorConfig`** (non-historized, §4 결정) | `.../relational/RelationalDatabaseConnectorConfig.java:51` |
| 4 | `CubridConnectorTask` | `BaseSourceTask<P,O>` | `.../connector/common/BaseSourceTask.java:80` |
| 5 | `CubridTaskContext` | `CdcSourceTaskContext` | `.../connector/common/CdcSourceTaskContext.java:24` |
| 6 | `CubridPartition` (+`Provider`) | `AbstractPartition` impl `Partition` | `.../relational/AbstractPartition.java:19`; `.../pipeline/spi/Partition.java:17` |
| 7 | `SourceInfo` | `BaseSourceInfo` | `.../connector/common/BaseSourceInfo.java` |
| 8 | `CubridOffsetContext` (+`Loader`) | `CommonOffsetContext<SourceInfo>`; Loader는 `OffsetContext.Loader<O>` | `.../pipeline/CommonOffsetContext.java:17`; `.../pipeline/spi/OffsetContext.java:33,38` |
| 9 | `CubridSourceInfoStructMaker` | `AbstractSourceInfoStructMaker<SourceInfo>` | `.../connector/AbstractSourceInfoStructMaker.java:24` |
| 10 | `CubridConnection` | `JdbcConnection` | `.../jdbc/JdbcConnection.java:84` |
| 11 | `CubridValueConverters` | `JdbcValueConverters` | `.../jdbc/JdbcValueConverters.java:83` |
| 12 | `CubridDefaultValueConverter` | impl `DefaultValueConverter` | informix 대응물 |
| 13 | `CubridDatabaseSchema` | **`RelationalDatabaseSchema`** (non-historized, §4 결정) | `.../relational/RelationalDatabaseSchema.java:35` |
| 14 | `CubridSchemaFactory` | `SchemaFactory` | `.../schema/SchemaFactory.java:41` |
| 15 | `CubridChangeEventSourceFactory` | impl `ChangeEventSourceFactory<P,O>` | `.../pipeline/source/spi/ChangeEventSourceFactory.java:21` |
| 16 | `CubridSnapshotChangeEventSource` | `RelationalSnapshotChangeEventSource<P,O>` | `.../relational/RelationalSnapshotChangeEventSource.java:90` |
| 17 | `CubridChangeRecordEmitter` | `RelationalChangeRecordEmitter<P>` | `.../relational/RelationalChangeRecordEmitter.java:28` |
| 18 | `CubridStreamingChangeEventSource` | impl `StreamingChangeEventSource<P,O>` — **JNA 래핑이 사는 곳, 최대 실작업 클래스** | `.../pipeline/source/spi/StreamingChangeEventSource.java:21` |
| 19 | `CubridErrorHandler` | `ErrorHandler` | `.../pipeline/ErrorHandler.java:22` |
| 20 | `CubridEventMetadataProvider` | impl `EventMetadataProvider` | `.../pipeline/source/spi/EventMetadataProvider.java:25` |
| +21 | `Lsa` (position value object) | 없음 — informix `Lsn`/`TxLogPosition` 유사 comparable 래퍼 | informix `Lsn.java` |

리소스 2개 필수:
- `META-INF/services/org.apache.kafka.connect.source.SourceConnector` → `io.debezium.connector.cubrid.CubridConnector` (plugin discovery)
- `io/debezium/connector/cubrid/build.version` → `version=${project.version}` (Maven resource filtering, `Module.version()`이 읽음)

**명시적으로 불필요 (v1에서 제외 확인)**: custom `ChangeEventSourceCoordinator` subclass와
JMX metrics 계층(sqlserver만 보유, informix는 plain coordinator + `DefaultChangeEventSourceMetricsFactory`),
`IncrementalSnapshotChangeEventSource`(factory에서 `Optional.empty()` 반환,
informix `InformixChangeEventSourceFactory.java:80-91`), DDL parser
(`getDdlParser()` → `null`, informix `InformixDatabaseSchema.java:80`),
`SnapshotLock`/`SnapshotQuery` SPI 커스텀, CloudEvents, `TransactionMonitor` 커스텀.
Informix의 `stream/*` 패키지(자체 CDC 엔진 추상화)는 core 요구사항이 아니라 Informix 고유물 —
CUBRID의 대응물은 #18 내부의 JNA 래퍼다.

### 1.3 배선 (task start → coordinator → sources → queue → poll)

1. Kafka Connect가 `start(Map)` 호출 → `BaseSourceTask.start`는 **final**
   (`BaseSourceTask.java:240`) → 커넥터의 `start(Configuration)` 오버라이드로 위임
   (informix `InformixConnectorTask.java:84`).
2. 그 안에서: `getPreviousOffsets(Partition.Provider, OffsetContext.Loader)` →
   `CubridDatabaseSchema` 생성 → `ChangeEventQueue.Builder`로 큐 생성 → `ErrorHandler`,
   `EventDispatcher`, `SignalProcessor`, `NotificationService` (전부 core 제공) →
   **`new CubridChangeEventSourceFactory(...)`를 `new ChangeEventSourceCoordinator<>(...)`에
   주입** (`InformixConnectorTask.java:180`) → `coordinator.start(...)` (`:193`).
3. Coordinator가 자체 스레드에서 `executeChangeEventSources`
   (`ChangeEventSourceCoordinator.java:209-227`): snapshot source `execute` (`:319`) →
   완료 시에만 `streamEvents(...)` (`:227`) → factory의
   `getStreamingChangeEventSource()` → `execute(context, partition, offsetContext)`.
   여기가 JNA polling 루프: `context.isRunning()` 체크하며
   `dispatcher.dispatchDataChangeEvent(partition, tableId, new CubridChangeRecordEmitter(...))`
   → 내부적으로 `queue.enqueue`.
4. Connect의 `poll()`도 final (`BaseSourceTask.java:353`) → `doPoll()` 구현은
   `queue.poll()` drain 한 줄.

## 2. offset 계약 (조사 항목 2) — LSA+epoch 충돌 여부

**충돌 없음.** 근거:

- 계약의 실체는 `OffsetContext.getOffset(): Map<String,?>`
  (`.../pipeline/spi/OffsetContext.java:59`, 직접 확인)이며 이 Map이 그대로
  `new SourceRecord(...)`에 들어간다 (`EventDispatcher.java:535-536`).
- Kafka Connect 자체는 중첩 구조도 허용하지만, **Debezium 전 커넥터가 flat
  String→primitive(String/Long/Integer/Boolean) 관례를 지킨다**. 다필드 선례:
  - MySQL: `binlog_filename`(String) + `binlog_position`(long) + `binlog_row_in_event`(int)
    + `gtid_set`(String) — page+offset+epoch의 구조적 등가물 (`MySqlOffsetContext.java:51-67`).
  - SQL Server: `commit_lsn` + `change_lsn` 문자열 + `event_serial_no` long
    (`SqlServerOffsetContext.java:59-73`).
  - Informix: `commit_lsn`/`change_lsn`/`begin_lsn` — 그리고 informix `Lsn.java:57-63`은
    32-bit loguniq + 32-bit logpos 복합을 signed 64-bit로 패킹한다. **"page+offset" 패킹
    문제를 이미 푼 선례.**
- **권장 인코딩**: 평탄 키 3개 — `page_id`(Long), `lsa_offset`(Long),
  `epoch`(uint64라 Java unsigned 부재 → String, 또는 signed-bit-pattern Long +
  `Long.compareUnsigned`) + 프레임워크 표준 `snapshot`/`snapshot_completed` 키.
- **재시작 경로**: `BaseSourceTask.getPreviousOffsets()` (`BaseSourceTask.java:614-616`) →
  `OffsetReader.offsets()` (`OffsetReader.java:46`, Connect `OffsetStorageReader`의
  JSON 역직렬화 결과) → `Loader.load(Map)` (`:57`) → `Offsets.of(...)` → coordinator가
  `getTheOnlyOffset()` 사용. **함정: JSON 역직렬화가 작은 값을 Integer로 돌려줄 수 있다.**
  sqlserver는 `(Long) offset.get(...)` 하드캐스트 (`SqlServerOffsetContext.java:120`) —
  깨지기 쉬움. CUBRID Loader는 `OffsetUtils.longOffsetValue()` (`OffsetUtils.java:15-27`,
  Number/문자열 모두 수용) 사용.
- **source struct는 별개**: 이벤트 `source` 블록은 typed `Struct`+`Schema`이므로 거기서는
  `page_id` INT64 / `lsa_offset` INT32 / `epoch` INT64·STRING을 **타입 그대로** 노출 가능
  (Postgres가 LSN을 `OPTIONAL_INT64_SCHEMA`로 노출, `PostgresSourceInfoStructMaker.java:26-28`).
  평탄화 제약은 offset Map에만 적용.
- **snapshot 마커**: `snapshot`(SnapshotType) + `snapshot_completed`(boolean)를 offset에
  실어 재시작 시 `Loader.loadSnapshot()/loadSnapshotCompleted()`
  (`OffsetContext.java:40-54`)로 복원 — 중단된 스냅샷은
  `RelationalSnapshotChangeEventSource.java:149-151`에서 재수행 판정.
- **`event(DataCollectionId, Instant)` 의무**: 매 이벤트 dispatch 직전에 호출되어
  sourceInfo의 테이블·타임스탬프를 갱신해야 하며, LSA/epoch 필드는 그 전에 별도
  `setChangePosition(...)`류로 최신화돼 있어야 한다 (dispatch 직후 `getOffset()`이 읽힘;
  호출점 예 `SqlServerStreamingChangeEventSource.java:354,538`).
- **EOS(exactly-once)는 선택 사항.** `SourceConnector.exactlyOnceSupport()` 오버라이드는
  postgres/oracle/sqlserver/mongodb/binlog만 있고 (`PostgresConnector.java:139` 직접 확인),
  **informix는 구현하지 않는다** (grep 0건). 프레임워크 요구사항이 아니므로 CUBRID v1은
  미구현 — LSA 단조성(로그 wraparound·epoch 경계)이 실측으로 확정된 뒤 재검토.

## 3. snapshot 계약 (조사 항목 3)

### 3.1 재사용 조건

`RelationalSnapshotChangeEventSource` + `JdbcConnection`은 **CUBRID JDBC 드라이버의
`DatabaseMetaData`(getTables/getColumns/getPrimaryKeys)가 충실하면 재사용 가능**.
스키마 읽기 경로 `JdbcConnection.readSchema(...)` (`JdbcConnection.java:1213-1291`)는
전부 `java.sql.DatabaseMetaData` 경유 — vendor SQL 없음.

컴파일러가 강제하는 필수 오버라이드 9개 (raw SQL 지점 굵게):

1. `prepare` — `AbstractSnapshotChangeEventSource.java:213`
2. `getAllTableIds` — `RelationalSnapshotChangeEventSource.java:418`
3. **`lockTablesForSchemaSnapshot`** — `:423` (vendor lock SQL)
4. **`determineSnapshotOffset`** — `:433` (**barrier의 핵심** — CUBRID는 SQL이 아니라
   JNA/native로 현재 LSA를 읽게 될 가능성이 높음. informix는 raw SQL
   `select uniqid, used ... from sysmaster:syslogs where is_current=1`,
   `InformixConnection.java:84-90`)
5. `readTableStructure` — `:439` (보통 portable `readSchema` 호출뿐)
6. `releaseSchemaSnapshotLocks` — `:446` (savepoint rollback 관례)
7. `getCreateTableEvent` — `:509` 직후
8. **`getSnapshotSelect`** — `:1239` (테이블별 SELECT 문안)
9. `copyOffset` — `:810`

값 변환은 `CubridValueConverters extends JdbcValueConverters`
(`schemaBuilder :161` / `converter :266` 오버라이드; informix가 NUMERIC/DECIMAL을
특수처리하는 `InformixValueConverters.java:52`가 본보기). 컬럼 후처리 훅은
`overrideColumn(column)` (`JdbcConnection.java:1413-1444` 경로) — CUBRID의
BIT/SET/MULTISET/SEQUENCE 특이 타입 처리 지점.

### 3.2 identifier quoting 함정

`quotedTableIdString(TableId)`의 기본 구현은 **생성자에 넘긴 quote 문자를 무시하고
쌍따옴표를 하드코딩**한다 (`JdbcConnection.java:1830-1832` → `TableId.toDoubleQuotedString()`,
직접 확인). MySQL도 informix도 이 메서드를 명시 오버라이드해서 우회한다
(`BinlogConnectorConnection.java:73-75`; `InformixConnection.java:157-176`).
CUBRID도 ctor 인자에 의존하지 말고 `quoteIdentifier`/`quotedTableIdString` 둘 다
명시 오버라이드할 것.

### 3.3 snapshot→streaming 전환점 (barrier)

- 프레임워크 보장은 **순서뿐**: snapshot이 완전히 끝나면(`isCompletedOrSkipped`)
  `SnapshotResult.getOffset()`을 **그대로** streaming source의 시작 offset으로 넘긴다
  (`ChangeEventSourceCoordinator.java:209-227,319,335-370`). **plain initial snapshot에는
  dedup/window 로직이 전혀 없다** (watermark 기반 dedup은 incremental snapshot 전용 별개
  기제). 즉 "읽은 데이터와 잡은 offset의 정합"은 100% 커넥터 책임.
- 정합 확보의 두 선례: **lock 기반** (sqlserver/informix — isolation을 REPEATABLE_READ로
  올리고 savepoint + 전 테이블 LOCK, **잠긴 상태에서 max log position 캡처**, savepoint
  rollback으로 락 해제 후 같은 트랜잭션 뷰에서 데이터 읽기; informix
  `InformixSnapshotChangeEventSource.java:71-135`) vs **exported snapshot 기반**
  (postgres — slot 생성이 LSN+snapshot name을 원자적으로 반환).
- **CUBRID에는 exported snapshot 원시가 없으므로 lock 기반 패턴이 맞고, 이는 POC의
  "쓰기 정지 스냅샷" 결정(지도 Notes)과 정확히 합치한다.** 쓰기 정지 중 JNA로 현재 LSA를
  캡처하면 barrier 성립. 상세 규칙은 티켓 #38(grilling)의 몫.
- 병렬 스냅샷 신경로(chunked)는 `buildSelectPrimaryKeyBoundaries`(`JdbcConnection.java:1731-1746`,
  기본 ANSI `OFFSET..FETCH`)·`nullsSortLast`(`:1749-1755`) 등 추가 dialect 훅을 요구 —
  v1은 `snapshot.max.threads=1`로 legacy 경로(`RelationalSnapshotChangeEventSource.java:549-568`)에
  머물러 회피 가능.

## 4. schema history (조사 항목 4) — 회피 가능

**필수 아님.** schema history topic은 `DatabaseSchema.isHistorized()==true`
(`HistorizedRelationalDatabaseSchema`)일 때만 요구된다. 프레임워크의 모든 history 동작이
`isHistorized()`로 gate돼 있다 (`BaseSourceTask.java:105,128,137`;
`ChangeEventSourceCoordinator.java:146`; `EventDispatcher.java:160,198`).
**Postgres가 증명하는 non-historized 경로**: `PostgresSchema extends RelationalDatabaseSchema`
(`PostgresSchema.java:45`, 직접 확인; `RelationalDatabaseSchema.java:140`
`isHistorized() → false`, 직접 확인) — history topic 없이 (재)시작 때마다 JDBC 카탈로그를
`schema.refresh(...)`로 다시 읽는다 (`PostgresSnapshotChangeEventSource.java:256`,
`PostgresStreamingChangeEventSource.java:141`).

**결정 제안**: 고정 스키마 POC인 CUBRID는 Postgres 모델 채택 —
`CubridConnectorConfig extends RelationalDatabaseConnectorConfig`,
`CubridDatabaseSchema extends RelationalDatabaseSchema`. §1.2 표는 이 결정을 반영했다
(informix 원형은 historized라는 점만 다름). 잃는 것: DDL replay, 과거 스키마 기준의
이벤트 해석, `schema.history.internal.*` 안전망 — 전부 "스트리밍 중 DDL 없음" 전제와
무모순. DDL 지원이 오면 historized로 승격 (지도의 "Not yet specified" 항목과 일치).

## 5. 네이티브 의존성 선례 (조사 항목 5) — hard blocker 없음

웹 조사 (근거 등급: official-doc / source-code / community / inference 구분):

- **선례 확정**: Debezium Oracle **XStream** adapter — Instant Client native 라이브러리
  (OCI thick driver) 필수, `LD_LIBRARY_PATH` + `-Djava.library.path` 지시
  [official-doc: debezium.io/documentation/reference/stable/connectors/oracle.html].
  Confluent Oracle XStream CDC **Source** Connector도 동일 [official-doc:
  docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/getting-started.html].
  패턴: **jar는 plugin 디렉토리, native .so는 워커 환경(env/JVM arg)** — .so는 plugin
  packaging의 일부가 아니다. (Db2·Informix는 native 아님 — 검증된 negative. IBM MQ/SAP
  HANA는 미확인: no evidence found.)
- **`.so`를 plugin.path에 그냥 두면 안 보인다**: Connect의 plugin 스캔은 dir/.jar/.zip/.class만
  수집 [source-code: kafka `PluginUtils.java` PLUGIN_PATH_FILTER]. 배포 옵션 3가지:
  (1) jar 안 `{os-arch}/libcubrid_log.so`로 번들 → JNA가 classpath에서 `jna.tmpdir`로
  추출·로드 [official-doc: JNA NativeLibrary javadoc — 단 tmpdir가 exec 가능해야 함,
  noexec /tmp·SELinux에서 깨짐], (2) 파일시스템 설치 + `-Djna.library.path` (JNA 공식
  선호 방법), (3) `LD_LIBRARY_PATH` (워커 기동 전 설정).
- **classloader 규칙은 비적용**: "native library는 classloader 하나만" 규칙
  (`jdk NativeLibraries.java`: "already loaded in another classloader",
  충돌 키는 canonical path)은 `System.loadLibrary` 경유에만 해당.
  **JNA는 대상 라이브러리를 `Native.open`(자체 dlopen)으로 열므로 `libcubrid_log.so`에는
  이 규칙이 적용되지 않는다** [source-code: jna `NativeLibrary.loadLibrary()`].
  JNA 자신의 `jnidispatch`도 기본 설정(`jna.nosys=true` 기본)에서는 classloader별 임시
  파일로 추출되어 충돌 없음 [source-code: jna `Native.loadNativeDispatchLibrary()`].
  **단 `jna.nosys=false`/`jna.boot.library.path`+`jna.noclasspath`/`jna.nounpack` 조합은
  이 위험을 부활시키므로 설정 금지.**
- **crash 격리는 배포 문제**: native segfault는 워커 JVM 전체(동거 커넥터 전부)를 죽인다
  [official-doc: JNI spec + JNA FAQ]. 관례적 완화는 **이 커넥터 전용 Connect 워커/클러스터**
  [community: Strimzi discussion #9783 등]. Debezium 스스로도 같은 문제의 out-of-process
  대안(OpenLogReplicator — 외부 C++ 리더를 host:port 서비스로)을 병행 출하 —
  segfault 반경이 수용 불가로 판명되면 v2 설계 후보 [official-doc: oracle 커넥터 문서].
  POC의 podman 단일 노드에서는 무시 가능, 문서화만.
- 기타: `.so`의 전이 의존 누락은 **조용히** 실패할 수 있음(oracle의 libaio 선례) → 기동 시
  로드 self-check 권장; JDK 24+ 워커는 `--enable-native-access` 필요 [official-doc: JEP 472];
  `libcubrid_log`의 스레드 안전성(Connect task 스레드에서 호출됨)은 CUBRID 쪽에서 확인 필요
  — 본 조사 범위 밖.

## 6. 빌드/포크 (조사 항목 6)

- **툴체인**: JDK **21** 이상 (`pom.xml:59,75` — enforcer `jdk.min.version=21`; 커넥터
  bytecode target은 17, `debezium.java.connector.target`, `pom.xml:62` 직접 확인),
  Maven **3.9.8** 이상 (enforcer `pom.xml:405-413`) — 단 `./mvnw` wrapper가 repo에 있어
  로컬 Maven 불요.
- **fork 내 새 모듈 추가**: root `pom.xml`의 `<modules>` 목록(`pom.xml:205-242`)에
  `<module>debezium-connector-cubrid</module>` 한 줄 추가.
- **해당 모듈만 빌드·테스트**:
  ```
  ./mvnw clean install -pl :debezium-connector-cubrid -am           # 의존 포함 빌드+테스트
  ./mvnw clean install -pl :debezium-connector-cubrid -am -DskipITs  # IT 제외
  ./mvnw clean verify  -pl :debezium-connector-cubrid -am -Dquick    # 산출물만 (테스트·checkstyle·formatter 전부 skip; quick 프로파일 pom.xml:457-467)
  ```
  `-pl :모듈` 관용구는 README가 postgres로 직접 예시 (`README.md:138`).
- **대안 배치**: informix처럼 **out-of-tree 별도 repo**(`debezium-parent`를 Maven
  `<parent>`로 참조, `debezium-connector-informix/pom.xml:4-8`)도 성립하지만, D10
  (fork 브랜치에서 개발)과 upstream 제출 목표(D6)상 **in-tree 모듈이 맞다**.

## 조사 방법·한계

- 조사 경로: debezium 및 debezium-connector-informix를 shallow clone하여 소스 직접 열람
  (병렬 서브에이전트 4개 + 웹 조사 1개; 핵심 주장 — RelationalDatabaseSchema 위치,
  `isHistorized` 기본값, `getOffset` 시그니처, `quotedTableIdString` 쌍따옴표 하드코딩,
  postgres의 non-historized·EOS 오버라이드, JDK/quick 프로파일 — 은 본 세션에서 clone에
  재확인).
- 한계: (1) line 번호는 3.7.0-SNAPSHOT `7bb44e29` 기준 — fork 시점의 base가 다르면 드리프트
  가능(클래스 계약 자체는 안정적). (2) CUBRID JDBC 드라이버의 `DatabaseMetaData` 충실도·
  `LIMIT`/`OFFSET..FETCH` 지원 여부는 **미검증** — 스켈레톤 티켓(#37)에서 실측 필요.
  (3) `libcubrid_log`의 스레드 안전성 미검증. (4) IBM MQ/SAP HANA 커넥터의 native 여부,
  native+plugin isolation 관련 KAFKA- JIRA 존재 여부는 증거 미발견(no evidence found).
  (5) 참고문서 htap-cubrid.md는 repo가 아니라 `~/Downloads/htap-cubrid.md`에만 존재
  (지도 Notes의 "이 repo의" 표기와 불일치 — 별도 정리 필요).
