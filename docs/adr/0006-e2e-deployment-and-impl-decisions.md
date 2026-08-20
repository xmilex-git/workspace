# E2E 수직 슬라이스의 배포·구현 결정 — 컨테이너 마운트, 토픽 reset, SMT 체인, 커넥터 내부 구조 (#40)

CUBRID→ClickHouse HTAP POC(지도: xmilex-git/workspace#30, 실행 티켓: #40)에서 E2E 관통을
성립시키기 위해 내린 배포·구현 결정 모음. 각각은 작지만 재현·운영 시 추적이 어려운
"암묵지"가 되기 쉬워 여기 고정한다. 근거 실측은 #40 resolution과 `htap-poc/e2e/README.md`.

## 확정 결정

**D1 — Connect 컨테이너에 CUBRID 설치본 *전체*를 ro 마운트 + env 2종 (`infra/up.sh`)**:
JNA가 dlopen하는 `libcubridcs.so`를 위해 `$CUBRID` 설치본 전체를 `/opt/cubrid`로 read-only
마운트한다. `lib/`만 마운트하는 안은 **불가** — `lib/libcascci.so.11.2`가
`../cci/lib/libcascci.so.11.2`로 가는 상대 심링크라 컨테이너 안에서 깨진다(실측:
UnsatisfiedLinkError). 추가로 `LD_LIBRARY_PATH=/opt/cubrid/lib`와 **`CUBRID=/opt/cubrid`
env가 필수** — `CUBRID` env 부재 시 libcubridcs가 "root directory environment variable
$CUBRID is not set"을 찍고 **프로세스를 종료시켜 워커가 통째로 죽는다**(#32가 경고한
"segfault=워커 사망"의 exit 변종, 실측). `.so`는 plugin.path 밖(#32 규칙) — 마운트 지점이
그 자체로 이행이다.
- 롤백: 마운트 경로·env는 `up.sh`의 `CUBRID_INSTALL` 변수 하나로 오버라이드 가능.
- **개정 예고 ([ADR 0012](0012-pure-java-log-client-standalone-repo.md))**: 순수 Java
  포팅(#72) 완료 시 JNA가 사라져 이 마운트·env 2종 자체가 불요해진다 — D1은 포팅
  전까지만 유효.

**D2 — 컨테이너→호스트 CUBRID 접속은 호스트 LAN IP의 `--add-host cubrid-host`**:
rootless podman(netavark)에서 ① `host.containers.internal`은 도달 불가 주소(이 호스트에선
게이트웨이 장비 IP)로 풀리고 ② 브리지 게이트웨이(10.89.0.1)는 호스트 서비스로 포워딩되지
않는다 — 둘 다 실측 실패. 유일하게 통하는 경로는 **호스트 LAN IP**(실측 192.168.6.34)라,
`up.sh`가 `ip route get`으로 자동 감지해 `--add-host "cubrid-host:$IP"`로 주입하고 소스
커넥터 config는 `database.hostname=cubrid-host` 고정 별칭만 본다.
- 비용: 호스트 IP 변경 시 컨테이너 재생성 필요. 오버라이드: `CUBRID_HOST_IP` env.

**D3 — 파이프라인 reset에서 토픽은 "삭제 후 자동 되살림"을 그대로 이용 (`e2e/reset-pipeline.sh`)**:
데이터 토픽을 delete하면 sink 컨슈머의 metadata 요청이 broker의
`auto.create.topics.enable`로 토픽을 **즉시 빈 상태로 재생성**한다(실측: delete rc=0 직후
list에 재등장). 처음엔 "삭제 완료 대기 후 명시적 create"를 시도했으나 이 레이스 탓에 영원히
대기/충돌 — 명시적 create를 버리고 **delete = purge**로 재정의했다. 순서 규칙도 함께 고정:
source 커넥터는 반드시 **stop → `DELETE /offsets` → delete** (같은 이름 재등록이 옛 anchor를
조용히 이어받는 것을 차단 — ADR 0004의 "offset만 삭제하는 운영 금지"의 실행형).
- 전제: 단일 노드 POC(파티션 1/RF 1이 auto-create 기본과 일치). 프로덕션 reset 절차는 별도.

**D4 — 스켈레톤 미러링의 마지막 조각: snapshot SPI는 커넥터가 직접 제공**:
#32/#37의 "Informix 클래스 미러 + Postgres non-historized" 노선을 유지하되, 실행해 보니
v3.0.0.Final 프레임워크는 `select_all` **SnapshotQuery SPI 구현이 커넥터 모듈에 없으면
기동 자체가 실패**한다(core는 Snapshotter/SnapshotLock만 기본 제공, 실측:
"Unable to find select_all snapshot query mode"). Postgres의 `SelectAllSnapshotQuery`를
그대로 미러해 `META-INF/services/io.debezium.snapshot.spi.SnapshotQuery`로 등록했다.
SnapshotLock은 `getSnapshotLockingMode()=empty` → core의 `no_locking_support`로 충분
(ADR 0005 D2와 합치).

**D5 — TableId의 schema 자리 = CUBRID owner** (2026-08-18 개정, ADR 0011 D8·D9):

~~논리 DB명(`htapdb`)~~ → **owner**. 토픽은 `htapcdc.<owner>.<table>`, include list는
`owner.table`(= CUBRID `unique_name` 문법), 스냅샷 SQL은 owner-qualified다. DB명은
`topic.prefix`·`database.dbname`이 담당하고 토픽에서 빠진다.

개정 근거: Debezium 표준 토픽 규칙 `topicPrefix.schemaName.tableName`은 PG·Oracle·DB2·
SQL Server·Informix가 전부 동일하며 가운데 자리는 DB의 2단 네임스페이스(Oracle에서는
소유자)다 — CUBRID의 2단 네임스페이스는 owner이므로 DB명을 넣은 원 결정이 규칙 이탈이었다.
원 결정의 근거였던 "드라이버가 카탈로그/스키마 인자를 무시해 `TABLE_SCHEM`(=owner)을
식별자로 쓸 수 없다"는 실사 결과 부정확하다: 컬럼 조회는 bare 테이블명만 쓰므로
(`CubridConnection.java:114`) TableId의 schema 슬롯 값과 무관하다. 실제 이유는 당시
sink 계약(#39)을 건드리지 않는 편의였다.

원 결정의 전제였던 **"POC는 dba 단독 소유"는 폐기**한다 — `getColumns(null, null,
<bare>, null)`은 owner가 다른 동명 테이블의 컬럼을 조용히 병합하는 실재 버그였고,
ADR 0011 D9가 컬럼 조회를 PUBLIC 뷰 `db_attribute`(owner_name 필터)로 교체해
동명 테이블을 완전 지원한다. 대가는 sink 설정 2줄(`htap-poc/sink/clickhouse-sink.json:13-14`)
과 기존 토픽 폐기 + resnapshot이며, 1.0 릴리스 전이라 설치 기반이 없어 실비용이 없다.

**D6 — offset의 anchor와 이벤트 카운터는 별도 상태**:
`CubridOffsetContext`가 영속하는 4키(`page_id/lsa_offset/seq/epoch`)는 **anchor**(가장
오래된 in-flight 트랜잭션의 배치 경계 LSA + 그 경계 시점 누적 카운터)이고, envelope의
`source.lsn`은 **이벤트별 카운터**다. 하나의 seq 필드로 겸용하면 재시작 시 "anchor부터
재계수해 같은 이벤트에 같은 번호"(ADR 0004)가 무너진다 — 마지막 발행 이벤트의 번호에서
이어 세면 재생 구간의 이벤트가 원본과 다른 `_version`을 받는다. 구현은
`SourceInfo.seq`(이벤트) vs `OffsetContext.anchorLsa/anchorSeq`(영속)로 분리.

**D7 — SMT 체인 확정 (#31 step-1 항목 ① 실측 해소, `e2e/cubrid-source.json`)**:
```
ExtractNewRecordState(delete.tombstone.handling.mode=rewrite,
                      add.fields=op:_op,source.lsn:_version, add.fields.prefix="")
→ ReplaceField$Value(renames=__deleted:_is_deleted)
→ Cast$Value(spec=_is_deleted:boolean)
```
실측 2건이 이 형태를 강제한다: ① `add.fields`는 **rename을 지정해도** 기본 프리픽스
`__`를 앞에 붙인다(`__op`가 아니라 `___op`가 됨) → `add.fields.prefix=""` 필수.
② rewrite의 `__deleted`는 **string** "true"/"false"라(코드 확인) sink의 CH `Bool` 컬럼
계약(JSON boolean)에 맞추려면 Cast가 필요하고, Kafka Cast의 string→boolean이 실제로
동작함을 토픽 실물로 확인했다. 결과 레코드는 `sink/samples/README.md` 계약과 일치 —
sink config 무변경.

**D8 — DATETIME 디코딩은 실측 포맷 + wall-clock passthrough**:
로그 아이템의 DATETIME 값은 엔진 소스 주석의 `YYYY-MM-DD HH24:MI:SS.FF`가 아니라
**CUBRID 기본 출력 포맷 `hh:mm:ss[.fff] AM MM/DD/YYYY`**로 도착한다(실측, len 정확·패딩
없음 — P0 덤프엔 DATETIME 샘플이 없어 #40에서 보완). 디코더는 이 포맷(+JDBC escape
포맷 fallback)을 파싱해 `java.sql.Timestamp`로 만들고, 스냅샷(JDBC)과 스트리밍이 **같은
워커 JVM(UTC)에서 같은 벽시계 문자열**(ZonedTimestamp ISO8601 `...Z`)로 렌더된다 —
두 경로 값이 byte-identical이라 수렴 검증이 성립. 서버 tz↔UTC의 의미론적 매핑은 POC
범위 밖(알려진 제약).

> **[추기 2026-08-20, workspace#76/#85]** D8의 wall-clock passthrough 계약은 **폐기**
> — 리뷰 #48 P0-3이 이 계약을 silent corruption으로 판정했다(instant 스키마
> `ZonedTimestamp`에 wall-clock 페이로드). 대체 계약(#76-D3, 기준 문서
> [wire v2 명세](../htap-cdc-wire-v2.md)): 엔진이 temporal 전종을 ISO 텍스트로
> 송출하고(dead format 소생 + CDC 데몬 tz UTC — #84), 커넥터는 typeName으로 분기해
> TIMESTAMP는 **진짜 instant**(`ZonedTimestamp`, UTC 자릿수→Instant 복원),
> DATETIME은 **offset 없는 ISO 문자열**(zone-less 유지)로 낸다. v1 AM/PM 포맷
> 파서·JDBC escape fallback은 삭제(strict 파서 + lockstep 안전망). 스냅샷 결정론은
> 워커 JVM UTC 규율 대신 커넥터의 매 접속 `SET TIME ZONE 'UTC'` 자가 고정으로 강제.
> 구현 workspace#85 (커넥터 `CubridTemporal`/`CubridValueConverters`/`CubridConnection`).

**D9 — classoid→테이블 매핑은 `_db_class.class_of` 1회 조회**:
DML 아이템의 classoid(uint64)는 엔진 OID 구조체의 8바이트 memcpy이고, JDBC
`_db_class.class_of`의 OID 문자열 `@page|slot|vol`을 `vol<<48 | slot<<32 | page`로
재조합하면 정확히 일치한다(P0 덤프 3개 테이블로 검증). 스트리밍 시작 시 카탈로그를 1회
읽어 map을 만든다 — DDL 이벤트 관찰(기존 테이블에 무력)이나 엔진 패치가 필요 없다.
전제: 스키마 고정 POC(스트리밍 중 CREATE TABLE은 map에 없어 스킵됨 — DDL 처리는 지도 fog).

**D10 — 스키마 부트스트랩은 태스크 시작 시 매번 JDBC로 (Postgres 모델)**:
non-historized라 스냅샷을 건너뛰는 재시작(offset 보유)에서는 아무도 스키마를 채우지
않는다 — 태스크 `start()`에서 include 대상 테이블 구조를 DB에서 읽어 `schema.refresh()`
하는 것을 상시 경로로 했다(스냅샷의 `readTableStructure`도 같은 헬퍼 재사용). 비용은
시작 시 테이블당 메타데이터 쿼리 몇 개로 무시 가능.

## Considered Options

- **D1 대안 — `.so`를 jar에 번들해 JNA 추출**(#32가 언급한 경로): 설치본 심링크 구조와
  `CUBRID` env 요구 때문에 단일 .so 번들로는 어차피 부족하다. 마운트가 더 정직함. 기각.
- **D2 대안 — `--network=host`**: 한 방에 풀리지만 세 컨테이너의 포트 격리·재현성(#34
  결정)을 깬다. 기각.
- **D3 대안 — auto.create 비활성화 + 명시적 토픽 관리**: 프로덕션에선 옳지만 POC 브로커
  설정 변경 반경이 크고, sink가 계속 붙어 있는 한 delete-wait는 영원히 안 끝난다. 기각.
- **D5 대안 — sink config 2줄 수정(#39가 열어둔 경로)**: 소스 쪽 한 곳(TableId 재귀속)이
  sink·샘플·verify 전부를 무변경으로 유지하므로 우세. 기각.
- **D7 대안 — 커스텀 SMT로 한 번에 변환**: #31의 "기성품만으로 성립" 결정에 역행. 기각.

## Consequences

- `find_lsa`의 초 단위 해상도 때문에 barrier가 스냅샷 직전 커밋 몇 건을 다시 포함할 수
  있다(실측) — 재생 이벤트는 동일 값 + 더 높은 `_version`이라 RMT 수렴에 무해하지만,
  중복 계수 검증(#41)은 이 중첩을 전제로 설계해야 한다.
- D6의 anchor 의미론상, 발행 직후 크래시하면 anchor 이후의 committed 트랜잭션 전체가
  재발행될 수 있다 — at-least-once(ADR 0004) 그대로이며 exactly-once 아님.
- D10 덕에 "스냅샷 없이 CDC 재부착"(ADR 0005 D6의 `no_data`) 경로도 스키마 확보가 보장된다.
