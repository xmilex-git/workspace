# Debezium Postgres·Oracle 커넥터의 DDL/schema evolution 처리 — 선례 조사

지도 xmilex-git/workspace#48, 티켓 #52의 결정 근거. 기준: 로컬 Debezium `3.0.0.Final`
체크아웃(`~/htap-cdc/debezium`, 태그 v3.0.0.Final) 소스 + 공식 `.adoc` 문서 실측.
인용의 `file:line`은 해당 태그 기준이다.

## 요약 비교

| 축 | Postgres | Oracle (LogMiner) | CUBRID 시사점 |
|---|---|---|---|
| 스키마 모델 | non-historized — history topic 없음, 재시작 시 catalog 재조회 | historized — schema history topic + ANTLR DDL 파서 | CUBRID 로그는 이벤트에 스키마 메타 없음 → PG식 불가, Oracle식은 파서 신규 개발 |
| DDL 이벤트 발행 | 불가 (`include.schema.changes` 옵션 자체가 제거됨) | schema change topic 발행 (CREATE/ALTER/DROP) | 1.0 미발행 |
| DDL 시 동작 | 멈추지 않음 — Relation 메시지로 사후 추적, 어긋나면 **조용히 컬럼 누락** | 파싱 불가 DDL이면 **기본 fail-stop** (`skip.unparseable.ddl=false`, non-retriable) | fail-stop이 제품 선례 |
| 트랜잭션 drain barrier | 없음 | 없음 (offset 전진 여부만 조정) | drain 불채택 근거 |
| TRUNCATE | `op:"t"`, key=null — `skipped.operations` 기본 `"t"`라 **기본 skip** | 동일 (DDL로 수신 후 DML op `t`로 변환, 기본 skip) | parity는 "무시"지만 RMT current-state 계약과 충돌 |
| DDL 복구 런북 | 없음 (snapshot 도구만 제공) | lock-step FAQ: DML 소진 대기 → 커넥터 정지 → DDL → 재시작; 파싱 실패 시 시그널로 스키마 주입 | 정지→DDL→resnapshot 절차의 선례 |

## Postgres 상세

- non-historized: `PostgresSchema extends RelationalDatabaseSchema`,
  `tableInformationComplete()` 항상 false (`PostgresSchema.java:287-291`). schema change
  topic 없음 — `PostgresConnectorConfig.java:1296` `.excluding(INCLUDE_SCHEMA_CHANGES)`.
  문서: "Logical decoding does not support DDL changes" (`postgresql.adoc:88`).
- 자동 추적의 실체: pgoutput `R`(Relation) 메시지가 DML에 앞서 컬럼 구조를 실어다 주고,
  커넥터는 수신 즉시 in-memory 스키마 교체 + out-of-band JDBC로 default/PK 재조회
  (`PgOutputMessageDecoder.java:289-357`). **DML이 발생해야만 반영되는 piggyback 방식.**
- 멈추지 않는 대신 조용히 깨진다: 스키마 불일치 시
  "column will be omitted from the change event" WARN 후 컬럼 누락 발행
  (`PostgresChangeRecordEmitter.java:197-214`). DROP TABLE은 WARN 후 no-op
  (`PostgresSchema.java:122-126`) — downstream 유령 테이블.
- 연속 DDL 시 out-of-band 조회가 '미래' 스키마를 반환하는 temporal race를 코드 주석이
  인정하고 best-effort 보정만 존재 (`PgOutputMessageDecoder.java:344-352`).
- TRUNCATE: `decodeTruncate` (`PgOutputMessageDecoder.java:529-573`) → op `"t"`,
  key=null, before/after 없음 (`PostgresChangeRecordEmitter.java:97-101`). 게이트는
  `skipped.operations` 기본 `"t"` (`CommonConnectorConfig.java:767`,
  `postgresql.adoc:3697` "By default, truncate operations are skipped"). JDBC sink도
  `truncate.enabled=false` 기본.
- 운영 문서: DDL 전용 런북 없음. 명시 규칙은 "incremental snapshot 중 스키마 변경
  미지원" (`postgresql.adoc:233-236`)뿐이고, ad hoc/incremental/blocking snapshot
  도구만 제공.

## Oracle 상세

- historized: redo log OPERATION_CODE=5 → `handleSchemaChange()`
  (`AbstractLogMinerEventProcessor.java:946-1034`) → ANTLR `OracleDdlParser` →
  in-memory + history topic 갱신, `include.schema.changes=true`(기본) 시 schema change
  topic 발행. 처리 대상은 리스너 5종 — CREATE/ALTER/DROP TABLE, TRUNCATE, COMMENT
  (`OracleDdlParserListener.java:34-38`). CREATE INDEX 등 테이블명 없는 DDL은 emitter
  이전에 무시 (`AbstractLogMinerEventProcessor.java:980`).
- **fail-stop이 기본**: 파싱 불가 DDL → `ParsingException` 그대로 throw
  (`OracleSchemaChangeEventEmitter.java:106-115`), non-retriable → task FAILED.
  `schema.history.internal.skip.unparseable.ddl` 기본 false — 문서 왈 "stop processing
  so a human can fix the issue. The safe default is `false`". 문서:
  "By default, the connector stops when it encounters a DDL statement that it cannot
  parse" (`oracle.adoc:4644`).
- 함정: 기본 `store.only.captured.tables.ddl=false`에서 LogMiner 쿼리가 테이블 필터
  **바깥**의 전체 DDL을 긁어 (`LogMinerQueryBuilder.java:124-126,177-179`) 비대상
  테이블 DDL로도 죽을 수 있다. — CUBRID는 서버가 extraction 필터 밖 DDL을 이미
  걸러줘서(`log_manager.c:13416`, `ER_CDC_IGNORE_LOG_INFO`) 이 사고가 구조적으로 차단됨.
- drain barrier 없음: DDL 처리 시 in-flight 트랜잭션을 비우지 않고 offset SCN 전진
  여부만 조정 (`AbstractLogMinerEventProcessor.java:983-1001`).
- TRUNCATE: DDL로 수신 → `TruncateReceiver` 우회로 DML `op:"t"` 변환
  (`OracleSchemaChangeEventEmitter.java:143-148`), `skipped.operations` 기본 `"t"`라
  기본 미발행 (`oracle.adoc:4162-4172`).
- 운영 절차: `online_catalog` 모드 lock-step — "stop the connector, apply the schema
  change, and restart the connector" (`oracle.adoc:5444`, §915-921); 파싱 실패 복구는
  `schema-changes` 시그널로 스키마 주입 + `skip.unparseable.ddl=true` 재시작 후 원복
  (`oracle.adoc:4639-4721`); incremental snapshot 중 스키마 변경 미지원
  (`oracle.adoc:375`).

## CUBRID 전제 사실 (엔진·POC 실측)

- supplemental log는 DDL을 1급으로 노출: `LOG_SUPPLEMENT_DDL`
  (`src/transaction/log_record.hpp:422`), `cubrid_log` DDL item은
  trid·user·ddl_type(CREATE/ALTER/DROP/RENAME/TRUNCATE)·object_type(TABLE/INDEX/…)·
  oid·classoid·**DDL 문장 전문**을 담는다 (`src/api/cubrid_log.h:71-80`).
  서버가 extraction 필터 밖 테이블·시스템 클래스 DDL은 걸러서 안 보낸다
  (`log_manager.c:13416-13424`).
- POC 커넥터는 DDL item을 완전히 파싱한 뒤 이벤트 카운터만 세고 폐기
  (`CubridStreamingChangeEventSource.java:298-300`). 스키마는 시작 시 JDBC 메타데이터
  1회 조회 — 로그 item에는 컬럼 인덱스+raw bytes뿐이라 mid-stream ALTER 시
  ADD COLUMN만 범위 초과 예외로 잡히고 **DROP/RENAME/타입 변경은 조용히 오디코딩**
  (`CubridLogValueDecoder.java:45-47`).
