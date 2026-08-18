# 초기 적재는 Debezium JDBC 스냅샷 재사용 — 쓰기 정지 barrier와 snapshot `_version`=0 (§8.1)

CUBRID→ClickHouse HTAP POC(지도: xmilex-git/workspace#30, 결정 티켓: #38)에서 초기
적재를 **별도 벌크 로더 없이 Debezium relational 프레임워크의 JDBC 스냅샷**
(`RelationalSnapshotChangeEventSource` + CUBRID JDBC)으로 수행하고, htap-cubrid.md
§8.1의 쓰기 정지 barrier 절차를 snapshot→streaming 전환에 아래 규칙으로 매핑한다.

근거가 된 JDBC 실측(driver 11.3.2.0058 ↔ server 11.5.0.2451, 프로브 원출력
`.git_ignored_dir/scratch/jdbc-probe/`):

- `DatabaseMetaData` **충실도 통과**: `getColumns`(타입·SIZE·DECIMAL_DIGITS·NULLABLE
  정확), `getPrimaryKeys`(복합 PK KEY_SEQ 포함 정상). #32의 미검증 2건 중 첫째 해소.
- 결함 2건: ① `getColumns`가 JDBC 3.0 형태(18컬럼) — `IS_AUTOINCREMENT`(23번) 부재.
  debezium-core `JdbcConnection.readTableColumn`이 `getString(23)`을 **무방비 인덱스
  접근**(`JdbcConnection.java:1322`)하므로 `readTableColumn` 오버라이드가 **필수**다
  (가드 후 `ResultSetMetaData.isAutoIncrement`로 보완 가능). ② `getIndexInfo`는
  null 쓰레기행 — Debezium PK 경로는 `getPrimaryKeys`라 무해.
- catalog/schema 인자는 **완전 무시**된다(존재하지 않는 스키마명도 필터 안 됨,
  TABLE_CAT=null, TABLE_SCHEM=소유자 대문자). 테이블 선별은 전적으로
  `table.include.list` 몫.
- `LIMIT`은 MySQL 스타일만(`LIMIT n [OFFSET m]`), ANSI `OFFSET..FETCH`는 문법 에러
  → chunked 병렬 스냅샷의 기본 boundary 쿼리 사용 불가. #32의 미검증 둘째 해소:
  **`snapshot.max.threads=1` legacy 경로 고정**.
- `LOCK TABLE` 계열 문장은 CUBRID에 **존재하지 않는다**(매뉴얼·실행 모두 확인).
  행 잠금은 `SELECT ... FOR UPDATE`뿐(동시 UPDATE 블록 실측).
- **REPEATABLE READ는 다문장 일관 스냅샷을 실제 제공**하고(기본값 READ COMMITTED는
  불안정), 열린 RR 리더는 **DDL(ALTER)을 블록**한다. SERIALIZABLE은 10.0+에서 RR과
  동일(키워드만 잔존).
- TIMESTAMP·DATETIME이 둘 다 `java.sql.Types.TIMESTAMP`(93) — 구분은 vendor
  `TYPE_NAME` 문자열(+SIZE 19/0 vs 23/3)로만 가능. value converter에서 TYPE_NAME
  기준 분기 필수.

## 확정 규칙

**D1 — JDBC 스냅샷 재사용, fallback 미설계**: 실측 통과가 근거. 향후 특정
타입/케이스에서 메타데이터 구멍이 발견되면 1차 대응은 **해당 타입 미지원 문서화**이지
카탈로그 raw SQL 보정층이 아니다(필요해지면 그때 별도 티켓). 벌크 로더 분리는 type
mapping·envelope 생성이 두 코드패스로 이원화되어 기각.

**D2 — 쓰기 정지는 운영자 절차, 커넥터는 잠그지 않는다**: 정지 범위는 **캡처 대상
테이블만**(`table.include.list`). `lockTablesForSchemaSnapshot`/
`releaseSchemaSnapshotLocks`는 no-op. LOCK TABLE 부재로 커넥터 강제 잠금은 애초에
불가하고, `FOR UPDATE` 전행 잠금은 정지가 보장되면 중복이다. 단 스냅샷 트랜잭션은
`prepare`에서 **REPEATABLE READ로 승격**한다 — 비용 0으로 다문장 일관 뷰와 스냅샷 중
DDL 블록(실측 확인)을 이중 방어로 얻는다.

**D3 — barrier LSA는 커넥터가 JNA로 직접 캡처**(기제는 [ADR 0012](0012-pure-java-log-client-standalone-repo.md)
이후 순수 Java log client로 대체 — `CubridLogClient` facade 불변이라 결정 자체는 유지):
`determineSnapshotOffset`에서
`cubrid_log_connect` → `cubrid_log_find_lsa(현재시각)`. 운영자 수동 주입은 전사
오류원이라 기각. 프레임워크 순서상 스냅샷 select 전에 호출되므로 §8.1의
"정지→barrier 기록→scan" 순서와 자동 합치.

**D4 — snapshot row의 `_version`은 전부 0**: snapshot read 이벤트(op=r)의
`source.lsn`(=event counter)을 0으로 고정. streaming counter는 1부터 시작하므로
어떤 CDC 이벤트든 반드시 snapshot row를 이긴다 — §8.2 "barrier보다 낮게"의
counter-축(ADR 0004) 번역.

**D5 — snapshot→streaming 전환점 = anchor 단일 규칙**: snapshot 완료 시 offset을
`{page_id, lsa_offset} = barrier LSA, seq = 0, epoch = 0`(ADR 0004의 4키)으로 넘기고,
streaming은 barrier부터 추출하며 counter를 1부터 센다. barrier가 Kafka Connect
offset topic 외 별도로 영속화되는 곳은 없다. 쓰기 정지 중에도 **비대상 테이블**의
트랜잭션이 로그에 남아 counter를 소모할 수 있으나(비-TIMER 아이템), 카운터 결정성은
유지되므로 무해 — 필터만 되고 번호는 매겨진다.

**D6 — `snapshot.mode`는 `initial`(기본) + `no_data`만 지원 문서화**: `no_data`는
데이터 단계 skip이라 공짜이고 "기존 적재본에 CDC 재부착" 운영에 필요하다. 이때도
barrier는 D3 규칙 그대로. 나머지는 미지원이 아니라 **미검증**으로 기록한다 —
`initial_only`/`always`는 프레임워크가 처리해 사실상 공짜, `never`는 no_data와 동일
처리로 소액, `when_needed`만 anchor 유효성 판정 로직이 필요한 실비용,
`recovery`류는 non-historized 스키마 모델(#32)이라 해당 없음.

**D7 — 드라이버는 호스트의 11.3.2.0058 사용**: 격리 설치본(11.5)에 `jdbc/` 부재.
실측이 이 조합으로 통과했고 교체는 pom 한 줄이라 무비용. "11.5 드라이버에서
getColumns 형태가 다를 수 있음"은 알려진 제약.

**필수 오버라이드 추가분** (#32의 9개 목록에 얹음): `readTableColumn`(18컬럼 가드),
`quoteIdentifier`/`quotedTableIdString` 명시 오버라이드(연구 문서 §3.2의 쌍따옴표
하드코딩 함정 — CUBRID quote 문자는 실측 `"`라 우연히 일치하나 명시가 안전),
value converter의 TYPE_NAME 기반 TIMESTAMP/DATETIME 분기.

## 스냅샷 절차 체크리스트 (운영자 수동 단계 포함)

1. 대상 테이블(table.include.list) **쓰기 정지** — 워크로드 정지 확인 (수동)
2. 커넥터 배포·시작 (`snapshot.mode=initial`) — 이후 3은 커넥터 자동
3. 커넥터: RR 트랜잭션 → JNA barrier LSA 캡처 → 테이블 scan → Kafka → ClickHouse 적재
4. **row count 검증**: CUBRID `COUNT(*)` vs ClickHouse canonical view `count()` (수동)
   — checksum·차등 비교는 differential check(#41) 소관, 여기서 이중 설계하지 않는다
5. 커넥터 **streaming 진입 확인** (로그/메트릭) (수동)
6. **쓰기 재개** (수동)

**실패 규칙**: 스냅샷 완주 전 실패 시 offset이 없어 재시작은 처음부터 재수행되는데,
부분 적재분은 전부 `_version=0`이라 재적재가 덮지 못한다 → **ClickHouse 대상 테이블
truncate 후 재수행**이 필수. 쓰기 재개는 반드시 5(streaming 진입 확인) 뒤에만.
ADR 0004의 "offset만 삭제하는 운영 금지"와 짝을 이룬다.

## Considered Options

- **별도 벌크 로더**(csql unload → ClickHouse insert, 커넥터는 no_data): type
  mapping·envelope·수렴 검증이 두 코드패스로 이원화. 기각.
- **커넥터 강제 잠금**: LOCK TABLE 문장 부재로 원안 불가, `FOR UPDATE` 전행 X-lock은
  쓰기 정지가 보장되면 중복이고 대형 테이블에서 잠금 비용만 추가. 기각.
- **DatabaseMetaData fallback(카탈로그 raw SQL 보정층) 사전 설계**: 통과한 시험에
  대비책을 미리 짓는 과잉 — 구멍 발견 시 미지원 문서화가 1차 대응. 미설계.
- **barrier LSA 운영자 수동 주입**: 사람이 옮겨 적는 지점이 오류원. 기각.

## Consequences

- online snapshot token(§8.2/8.3)은 이 ADR의 범위 밖 — 지도 fog에 유지된다.
- 커넥터 스켈레톤의 스냅샷 TODO 주석이 workspace#39/#40으로 오표기돼 있다 — 이 ADR을
  코드에 반영하는 구현 티켓에서 #38로 정정한다.
- `no_data` 재부착 운영에서도 barrier 이전 이벤트는 영원히 오지 않으므로, 기존
  적재본이 barrier 시점과 정합한다는 보장은 운영자 책임이다(체크리스트 1과 동일한
  쓰기 정지 아래에서만 안전).
