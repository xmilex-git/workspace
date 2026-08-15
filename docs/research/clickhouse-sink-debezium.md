# ClickHouse Kafka Connect Sink × Debezium envelope — 지원 범위 조사

- 티켓: xmilex-git/workspace#31 (지도: #30)
- 조사일: 2026-08-15
- 근거 등급 표기: **[공식]** = 공식 문서, **[소스]** = sink 소스 코드 (ClickHouse/clickhouse-kafka-connect, 2026-08-15 조회 기준 main), **[커뮤니티]** = 블로그/QA, **[추론]** = 본 조사자의 결합 추론

## TL;DR

**기성품만으로 POC upsert/tombstone 경로 구성 가능하다. 경로는 두 개다.**

- **경로 A (권장 baseline)**: 소스 커넥터에 `ExtractNewRecordState` SMT 체인. 성숙하고 선례 다수(ClickHouse 공식 블로그 포함). 단 두 곳에 마찰 — `_version UInt128` 전달과 `__deleted`(string)의 UInt8 매핑 — 은 **스키마를 살짝 굽히면(UInt64 + Bool) SMT 없이도 해소**되고, §9.2 스키마를 그대로 고수하면 ~50줄 커스텀 SMT가 필요하다.
- **경로 B (신규, 관찰 대상)**: sink v1.4.0(2026-07-15)부터 **`debeziumCDCEnabled=true` native envelope 모드**가 있다. 문서화 전(2026-08-04 갱신된 공식 문서 페이지에 없음)이고 version 추출이 PG/MySQL/SQL Server에 하드코딩돼 있으나, **우리 커스텀 커넥터가 `source.lsn`을 int64 숫자로 내면 그대로 탄다**. SMT 자체가 불필요해진다. 신품이라 POC baseline으로는 A, 실험 항목으로 B를 권한다.

---

## 1. Debezium envelope 처리

### sink 자체는 envelope를 해석하지 않는다 (기본 동작)

- sink는 메시지 필드명을 대상 테이블 컬럼명에 **이름으로 매핑**해 insert하는 단순 모델이다. 중첩 구조는 그대로 넣으면 "all my data is blank/zeroes"가 되며, 공식 문서의 troubleshooting이 CDC(Debezium) 사례에 `Flatten` transform을 권한다. **[공식]** https://clickhouse.com/docs/integrations/kafka/clickhouse-kafka-connect-sink (2026-08-04 갱신)
- Limitations에 **"Deletes aren't supported"** 명시. delete를 행 삭제로 바꿔주지 않는다 — tombstone 경로는 전적으로 upstream 변환 + ReplacingMergeTree 몫이다. **[공식]** 위 문서
- 실사용 보고: unwrap 없이 넣으면 `op=d` 레코드가 무시된다. **[커뮤니티]** https://stackoverflow.com/questions/78458720 (2024-05)

### 경로 A: `ExtractNewRecordState` (unwrap) SMT

- `io.debezium.transforms.ExtractNewRecordState`가 envelope에서 `after`를 꺼내 평탄화한다. `delete.tombstone.handling.mode=rewrite`일 때 `op=d`는 **`before` 내용 + `__deleted:"true"` 필드가 붙은 일반 행**이 되고 **Kafka tombstone(null value) 레코드는 제거**된다. **[공식]** https://debezium.io/documentation/reference/stable/transformations/event-flattening.html
  - 주의 1: `__deleted`는 **string** `"true"/"false"`다. UInt8 컬럼에 직행하지 않는다 (→ §2).
  - 주의 2: delete 행의 비-키 컬럼은 `before` full image에서 온다. **CUBRID 커넥터가 full before image를 채워야** 하며(P0 CDC 사실 항목과 일치), 비어 있어도 RMT delete 수렴에는 ORDER BY 컬럼 + version + deleted flag만 있으면 된다. **[공식+추론]** ClickHouse CDC 블로그 Part 1의 delete 행 요건: https://clickhouse.com/blog/clickhouse-postgresql-change-data-capture-cdc-part-1 (2023-06-15)
  - 주의 3: 옵션명이 Debezium 버전에 따라 다르다(구: `delete.handling.mode` + `drop.tombstones`). 위 표기는 현행 stable(3.x) 기준.
- 메타데이터 승격은 `add.fields`(기본 `__` prefix, `add.fields.prefix`로 변경 가능, `원래이름:새이름` rename 문법 지원). **[공식]** 같은 문서
- tombstone이 sink까지 흘러가는 경우(예: `rewrite-with-tombstone`): sink는 value가 null인 레코드를 `EmptyRecordConvertor`로 빈 레코드 처리한다 — 에러가 아니라 skip. **[소스]** `sink/data/Record.java` `getConvertor()` — `data == null → emptyRecordConvertor`, `sink/data/convert/EmptyRecordConvertor.java`

### 경로 B: native `debeziumCDCEnabled` 모드 (v1.4.0+)

- 2026-05-19 커밋 `88f5ea24` "feat: add Debezium CDC envelope support with LSN-based versioning"으로 도입, **v1.4.0(2026-07-15)부터 릴리스에 포함**(compare API로 tag 포함 확인: v1.3.10에는 없음). **[소스]**
- 동작 (`sink/data/convert/DebeziumRecordConvertor.java`): **[소스]**
  - 활성화: `debeziumCDCEnabled=true` **그리고 value schema name이 `.Envelope`로 끝날 때**. 즉 **schema 있는 converter 필수** (Avro+SR, 또는 `JsonConverter` + `value.converter.schemas.enable=true`). schemaless JSON에서는 절대 발동하지 않는다.
  - 라우팅: `op=c/r/u` → `after` + `is_deleted=0`, `op=d` → `before` + `is_deleted=1`, `op=t`(truncate)와 null struct → skip.
  - 주입 컬럼명 **강제**: `_version`, **`is_deleted`** — §9.2의 `_is_deleted`와 이름이 다르다.
  - `_version` 추출 우선순위 하드코딩: `source.lsn`(Number) → `source.gtid`("uuid:N"의 N) → `source.pos` → SQL Server `commit_lsn`/`change_lsn` 조합(UInt128: high 64 = commit, low 64 = change). 전부 실패 시 **0으로 경고 후 진행** — version 전멸 위험.
  - 대상 테이블로 `ReplacingMergeTree(_version, is_deleted)`를 전제한다고 config 설명에 명시.
- **CUBRID 함의 [추론]**: 커스텀 커넥터가 SourceInfo에 `lsn`이라는 이름의 int64 필드(예: commit_page/offset을 64bit로 pack)를 넣으면 이 모드를 기성품 그대로 쓸 수 있다. 128bit version이 꼭 필요하면 SQL Server 형식(`commit_lsn`/`change_lsn`, `"a:b:c"` hex 문자열)을 흉내 내는 방법이 있으나 기괴하다. 문서화 전 + 릴리스 1개월 차라 **POC baseline으로 삼지 말고 실험 항목**으로 두는 것을 권한다.

---

## 2. ReplacingMergeTree 매핑 (`_version`, `_is_deleted` 채우기)

### 표준 선례 (PostgreSQL → ClickHouse)

- ClickHouse 공식 블로그와 다수 가이드의 표준형: `add.fields=op,source.lsn` + `rewrite` 모드로 **`source.lsn`을 version 컬럼으로** 쓴다. LSN은 단조 증가하고 이벤트 내용에서 결정적이므로 RMT version 요건을 만족한다. **[공식]** CDC 블로그 Part 1 (위), **[커뮤니티]** https://www.quantrail-data.com/postgresql-to-clickhouse-cdc-debezium-kafka (2026-06-09, Debezium 3.5 + sink v1.3.7 + CH 26.3으로 동작 확인한 튜토리얼)
- RMT 요건 요약 **[공식]** (블로그 Part 1): ORDER BY = 소스 PK(불변), 모든 change 행에 동일 key 값, version은 행 단위 단조 증가, delete 행은 key + 높은 version + deleted=1만 있으면 됨.

### 우리 스키마(§9.2)와의 마찰 두 곳

1. **`_version UInt128`**: Kafka Connect 타입 체계에 128bit 정수가 없다. 선택지:
   - (i) **UInt64로 축소** — POC는 단일 소스라 commit_page(상위)/offset(하위) pack으로 충분할 수 있고, 경로 B와도 호환된다. *스키마 변경이므로 결정 필요.*
   - (ii) 커넥터가 **10진 문자열**로 emit → schemaless JSON 경로에서 ClickHouse가 UInt128 컬럼에 string을 parse. JSONEachRow의 숫자-from-string 허용에 기대는데, **동작은 POC step 1에서 실측 확인 필요** [추론, 미검증].
   - (iii) 커스텀 SMT로 조립 — 우리는 어차피 커넥터를 Java로 쓰므로 비용 낮음.
2. **`__deleted`(string) → `_is_deleted UInt8`**: 기성 `Cast` SMT는 "true" 문자열→int 캐스팅이 안 된다. 선택지:
   - (i) 컬럼을 **`_is_deleted Bool`**로 선언(CH Bool = UInt8 저장) + `ReplaceField$Value`로 `__deleted→_is_deleted` rename. JSON "true" → Bool parse는 표준 동작. RMT `is_deleted` 인자로 Bool 컬럼이 허용되는지는 **확인 필요** [추론].
   - (ii) 커스텀 SMT에서 함께 처리 — (1)(iii)과 묶으면 하나의 ~50줄 SMT로 두 마찰이 모두 사라진다.

**권고 [추론]**: POC에서는 §9.2를 교조적으로 지키기보다 **sink 현실에 맞춰 POC 스키마를 조정**(UInt64 version + Bool flag)하고, 제품 스키마(UInt128/UInt8)가 확정 요건이면 그 시점에 커스텀 SMT 1개를 추가하는 것이 최소 비용이다. 이는 티켓 "ClickHouse 물리 테이블 + sink 설정"에서 결정할 사항.

### 메타 컬럼 승격 concrete 안

커스텀 커넥터가 SourceInfo(`source` struct)에 POC 메타를 넣고 SMT로 승격:

```properties
transforms=unwrap
transforms.unwrap.type=io.debezium.transforms.ExtractNewRecordState
transforms.unwrap.delete.tombstone.handling.mode=rewrite
transforms.unwrap.add.fields.prefix=
transforms.unwrap.add.fields=op:_op,source.lsn:_version,source.commit_ts:_commit_ts,source.event_id:_event_id,source.schema_version:_schema_version
```

- `add.fields.prefix=`(빈 값)로 `__` prefix를 제거하고 rename 문법으로 §9.2 이름을 직접 맞춘다. prefix/rename 상호작용의 정확한 결과 이름은 **step 1에서 실물 메시지로 확인**할 것(문서가 조합 사례를 명시하지 않음) [확인 필요].
- `_source_epoch`/`_record_page` 등 나머지 §9.2 메타도 같은 방식으로 승격 가능. envelope에 없는 필드를 지정해도 SMT는 에러 내지 않고 추가한다(**[공식]** event-flattening 문서).

---

## 3. 전달 보장

- **exactly-once 공식 지원**: `exactlyOnce=true`, **KeeperMap을 state store로 사용**. 요구: ClickHouse ≥ 23.3(그 미만이면 커넥터가 기동 거부), self-hosted 클러스터에서는 `keeperOnCluster`로 `connect_state` 테이블의 ON CLUSTER 지정. **[공식]** sink 문서
  - **단일 노드 POC 전제 조건 [추론]**: KeeperMap은 (Zoo)Keeper coordination이 필요하므로 단일 CH 컨테이너에 **embedded ClickHouse Keeper 설정**이 있어야 한다. compose 작성 시 반영.
  - 제약 **[공식]**: 내부 buffering(`bufferCount>0`)과 비호환(배치 경계가 바뀌면 block dedup + offset 상태기계가 깨짐); async insert 병용 시 `wait_for_async_insert=1` 필수; offset rewind/토픽 재생성 시 `connect_state`를 수동 정리해야 하며 그 자체가 exactly-once에 영향("State mismatch" troubleshooting).
- **at-least-once에서 중복이 무해한 조건 [공식+추론]**: version이 **이벤트 내용(log position)에서 결정적**이면 재전송 중복은 (key, version, 동일 내용) 행의 재삽입일 뿐이고 RMT merge + `FINAL`에서 하나로 수렴한다. 우리 `_version`은 log position 유래이므로 만족. ingest 시각 등 비결정적 version을 쓰면 이 성질이 깨진다 — 금지. 재시작 구간의 배치 경계는 달라질 수 있으므로 **block-level dedup에는 기대지 말 것**.
- **POC 권고 [추론]**: at-least-once(`exactlyOnce=false`)로 시작해 differential check로 수렴을 실증하고(이게 #30의 완료 계약이 실제로 요구하는 것), 그 뒤 `exactlyOnce=true`를 켜서 재시작 시나리오를 재실행하는 2단 구성. 중복 무해화가 실증되면 exactly-once는 필수가 아니라 최적화다.

---

## 4. 형식: JSON vs Avro

- **Schema Registry 없이 JSON으로 시작 가능** — schemaless JSON은 공식 지원이며 JSONEachRow로 insert된다. **[공식]** sink 문서. 단 경로 B는 schema가 필요하므로, SR 없이 경로 B를 실험하려면 `JsonConverter` + `schemas.enable=true`(메시지마다 schema 내장, 대역폭 손해)를 쓴다.
- **Decimal**: Debezium 기본 `decimal.handling.mode=precise`는 Connect `Decimal`(bytes)로 나가며 JSON 직렬화 시 base64 문자열이 된다 — schemaless 경로에서 깨진다. **`decimal.handling.mode=string`으로 설정**하면 `"1234.56"` → CH `Decimal(18,2)` parse로 정밀도 보존. `double`은 정밀도 손실이라 금지. schema 경로(Avro)에서는 sink가 Connect `Decimal`을 공식 지원한다. **[공식]** sink 데이터타입 표 + Debezium connector 문서 / 조합은 [추론]
- **DateTime64(6)**: Debezium 기본(adaptive)은 micros int64(`io.debezium.time.MicroTimestamp`)로 나간다. schemaless JSON에서 큰 정수가 DateTime64 컬럼에 그대로 가면 초 단위로 오독될 위험이 크다. 우리 커넥터가 **`io.debezium.time.ZonedTimestamp`(ISO8601 문자열, UTC)로 emit**하는 것이 가장 안전하다(sink는 DateTime64 컬럼에 문자열 입력을 처리하며 `dateTimeFormats` 옵션도 있음; 경로 B 코드도 ZonedTimestamp pass-through를 명시). **[소스+공식]** — 정확한 파싱 결과는 step 1 실측 항목.
- **Avro 채택 시 주의 [공식]**: sink는 Avro `fixed` decimal logical type, nullable union, record union을 지원하지 않는다.
- **권고 [추론]**: POC는 **JSON(schemaless) + decimal=string + 시각=ISO8601 문자열**로 시작. Avro+SR은 §5가 durable bus 요건으로 이미 SR을 상정하므로 제품 단계 전환 항목으로 넘긴다.

---

## 5. 대안 비교: Kafka table engine

- §5/[R11]의 판정(공식 sink 우선) 재확인. Kafka Engine은 at-least-once + 드문 중복 명시, exactly-once 없음, DLQ 없음, 소비가 CH 서버 수명에 묶임. **[공식]**
- 다만 Kafka Engine + Materialized View는 **envelope 해석을 SQL(JSONExtract)로 처리**할 수 있어 SMT 체인 자체가 불필요하고, Kafka Connect worker라는 프로세스 하나가 통째로 줄어든다 — 단일 노드 podman POC에서는 실질적 이점이다. **[추론]**
- **결정이 뒤집힐 조건 [추론]**: (a) Kafka Connect worker가 단일 노드 자원에서 감당 불가로 판명, (b) SMT/타입 마찰이 커스텀 SMT로도 해소 불가, (c) POC 목적이 "제품 경로 검증"이 아니라 "수렴 semantics 검증"으로만 좁혀질 때. (a)(b)는 발생 가능성 낮음. **b가 아니라면 공식 sink 유지** — POC가 제품 v1 아키텍처(§5의 sink 이점 목록: DLQ, transaction boundary 인식, watermark 등 커스텀 sink로의 진화 경로 포함)를 대표해야 하기 때문.

---

## 산출물 (b): sink connector config 초안

"ClickHouse 물리 테이블 + sink 설정" 티켓용. 경로 A + JSON schemaless + at-least-once 기준.

```json
{
  "name": "clickhouse-sink-poc",
  "config": {
    "connector.class": "com.clickhouse.kafka.connect.ClickHouseSinkConnector",
    "tasks.max": "1",
    "hostname": "clickhouse",
    "port": "8123",
    "ssl": "false",
    "database": "htap",
    "username": "default",
    "password": "<PASSWORD>",

    "topics": "cubrid.pocdb.orders, cubrid.pocdb.customers",
    "topic2TableMap": "cubrid.pocdb.orders=orders_current_local, cubrid.pocdb.customers=customers_current_local",

    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",

    "exactlyOnce": "false",
    "errors.retry.timeout": "60000",
    "errors.tolerance": "none",
    "clickhouseSettings": "date_time_input_format=best_effort"
  }
}
```

- unwrap SMT 체인(§2)은 **소스 커넥터 쪽**에 두는 것을 권한다: sink 쪽에 두면 Kafka 토픽에 full envelope가 남아 §9.5 history/replay 요구와 맞고, sink 쪽 재처리 유연성도 생긴다(Debezium 공식 문서가 이 배치를 명시적으로 지원). 2단계로 exactly-once 실험 시 `exactlyOnce=true` + CH embedded Keeper + (자원상 필요하면) `keeperOnCluster`는 불필요(단일 노드).
- DLQ는 POC 초기엔 `errors.tolerance=none`(즉시 실패 노출)이 낫고, 회복 시나리오 단계에서 `all`+DLQ로 전환.

## 산출물 (c): 막히는 지점과 우회안

| 마찰 | 우회안 | 비용 |
|---|---|---|
| `_version UInt128`을 Connect가 못 나름 | UInt64로 축소 / 10진 문자열 emit(실측 필요) / 커스텀 SMT | 스키마 결정 1건 |
| `__deleted` string → UInt8 | `Bool` 컬럼 + rename SMT / 커스텀 SMT | 소 |
| `_is_deleted` vs 경로 B의 `is_deleted` 이름 충돌 | 경로 선택 시 컬럼명 확정 (A면 자유, B면 `is_deleted`) | 결정 1건 |
| DateTime64 micros 오독 | 커넥터가 ZonedTimestamp(ISO8601)로 emit | 커넥터 설계에 반영 |
| Decimal base64 깨짐 | `decimal.handling.mode=string` | config 1줄 |
| 경로 B가 schema 요구 | `JsonConverter schemas.enable=true` (SR 불필요) | 대역폭 |
| exactly-once에 Keeper 필요 | CH embedded Keeper 설정 / at-least-once로 시작 | compose 반영 |

## step 1(하네스)에서 실측 확인할 것

1. `add.fields.prefix=` + rename 조합의 실제 출력 필드명.
2. UInt128 컬럼에 10진 문자열 insert(JSONEachRow) 동작 여부.
3. RMT `is_deleted` 인자로 `Bool` 컬럼 허용 여부.
4. ISO8601 문자열 → `DateTime64(6,'UTC')` parse (best_effort 설정 포함).
5. 경로 B: 커스텀 커넥터 `source.lsn`으로 `_version` 주입 확인 (실험 항목).

## 출처 일람

- ClickHouse Kafka Connect Sink 공식 문서 (2026-08-04 갱신): https://clickhouse.com/docs/integrations/kafka/clickhouse-kafka-connect-sink
- sink 소스 (2026-08-15 조회, main): `sink/data/convert/DebeziumRecordConvertor.java`, `sink/data/Record.java`, `sink/ClickHouseSinkConfig.java` — https://github.com/ClickHouse/clickhouse-kafka-connect ; 도입 커밋 `88f5ea24`(2026-05-19), v1.4.0 릴리스(2026-07-15) 포함 확인
- Debezium event-flattening SMT (stable): https://debezium.io/documentation/reference/stable/transformations/event-flattening.html
- ClickHouse 공식 블로그 "CDC with PostgreSQL and ClickHouse — Part 1" (2023-06-15): https://clickhouse.com/blog/clickhouse-postgresql-change-data-capture-cdc-part-1
- [커뮤니티] quantrail-data 튜토리얼 (2026-06-09, 버전 고정 동작 예제): https://www.quantrail-data.com/postgresql-to-clickhouse-cdc-debezium-kafka
- [커뮤니티] StackOverflow 78458720 (2024-05, delete 무시 사례): https://stackoverflow.com/questions/78458720
