# E2E 수직 슬라이스 — 스냅샷 후 I/U/D/COMMIT/ABORT 전 구간 관통 (ticket #40)

티켓: [#40](https://github.com/xmilex-git/workspace/issues/40) · 근거: ADR 0003(cond⊕changed 병합)·
ADR 0004(카운터 position·트랜잭션 버퍼링)·ADR 0005(JDBC 스냅샷·쓰기 정지 barrier),
sink 체인 계약은 [`../sink/`](../sink/README.md)(#39).

**경로**: CUBRID(htapdb) → `debezium-connector-cubrid`(fork 브랜치 `cubrid-connector`) →
Kafka `htapcdc.htapdb.<table>` → 공식 ClickHouse sink → RMT → canonical `FINAL` view.

## 구성

| 파일 | 내용 |
|---|---|
| `build-connector.sh` | fork 모듈 빌드(JDK21/mvn 3.9 핀) → 플러그인 jar 5종을 Connect 마운트에 배치 (`podman unshare` — `:U` 마운트 소유권) |
| `cubrid-source.json` | 소스 커넥터 config — SMT 체인 포함 (아래 실측) |
| `register-source.sh` | Connect REST PUT (idempotent) |
| `reset-pipeline.sh` | source stop→offset 삭제→삭제, 토픽 purge, CH truncate, sink 재시작 (ADR 0004: offset만 지우는 운영 금지 — 항상 스냅샷 재수행과 짝) |
| `seed-cubrid.sql` | 쓰기 정지 하 스냅샷 대상 상태 (t_order 2행, t_item 2행) |
| `streaming-workload.sql` | I/U/D × COMMIT/ABORT + §7.7 전 케이스 (T1~T7) |
| `run-e2e.sh` | 전체 오케스트레이션 + 완료 조건 3건 assert |

실행 (인프라·sink 체인·htapdb 서버 준비 후):

```bash
./build-connector.sh && podman restart htap-connect
./run-e2e.sh          # PASS (2026-08-16 실측)
```

## 실측으로 확정된 사실 (2026-08-16)

- **완료 조건 3건 전부 통과**: ① ABORT 트랜잭션(INSERT id=99·UPDATE·DELETE) 미반영,
  ② §7.7 수렴 — same-PK 다중 update(21→22→23), insert→delete(무행), delete→insert(새 행),
  PK 변경(old PK tombstone `_op=d,_is_deleted=true` + new PK insert, 동일 `_version` — 같은 DML
  아이템에서 파생), ③ barrier 전후 gap 없음 — 스냅샷 행(`_version=0`)과 스트리밍 CDC가 수렴,
  CUBRID 최종 상태와 canonical view 완전 일치.
- **토픽 메시지 계약 실측** (#31 step-1 항목 ① 해소): SMT 체인
  `ExtractNewRecordState(rewrite, add.fields=op:_op,source.lsn:_version, add.fields.prefix="")`
  → `ReplaceField(__deleted→_is_deleted)` → `Cast(_is_deleted:boolean)` 조합이
  `../sink/samples/README.md` 계약과 정확히 일치하는 출력을 냈다:
  평탄화 row + `_op`(r/c/u/d) + `_version`(숫자) + `_is_deleted`(**JSON boolean** — rewrite의
  string "true"를 Cast가 boolean으로 변환), DECIMAL=string, DATETIME=ISO8601 `...Z`.
  rename 시에도 `add.fields.prefix` 기본값 `__`가 앞에 붙으므로 빈 문자열 지정이 필수.
- **offset 왕복**: 워커 재시작 후 영속 anchor(`page_id/lsa_offset/seq/epoch`)에서 재개
  ("Resuming ... at anchor LSA(page=1062,off=14840) with counter 39"), 재시작 직후 변경이
  ~6초 내 canonical view 도달.
- **스트리밍 값 인코딩** (엔진 실측, 하네스 P0 보완): DATETIME은 소스 주석의
  `YYYY-MM-DD ...`가 아니라 CUBRID 기본 출력 포맷 **`hh:mm:ss[.fff] AM MM/DD/YYYY`**
  (len 정확, 패딩 없음). INT/SHORT/BIGINT/FLOAT/DOUBLE=LE 바이너리, NUMERIC=10진 문자열,
  CHAR/VARCHAR=raw UTF-8.
- **classoid → 테이블 매핑**: `_db_class.class_of`의 JDBC OID 문자열 `@page|slot|vol` ↔
  로그 classoid `vol<<48 | slot<<32 | page` 재조합이 실덤프와 일치 (커넥터가 스트리밍 시작 시
  1회 조회).
- **barrier 중첩(알려진 동작)**: `cubrid_log_find_lsa`는 초 단위 timestamp 해상도라 barrier가
  스냅샷 직전 커밋 몇 건을 다시 포함할 수 있다 — 재생 이벤트는 스냅샷과 동일 값 + 더 높은
  `_version`이므로 RMT에서 무해하게 수렴 (at-least-once 의미론에 포함).
- **인프라 전제** (`../infra/up.sh`에 반영): JNA `.so`는 `$CUBRID` **설치본 전체**를
  `/opt/cubrid`로 ro 마운트 (`lib/libcascci.so.11.2 → ../cci/lib/` 심링크 때문에 lib만으로는
  불가) + `LD_LIBRARY_PATH=/opt/cubrid/lib` + **`CUBRID=/opt/cubrid` env 필수**(없으면
  libcubridcs가 프로세스를 종료시켜 워커 사망). 컨테이너→호스트 CUBRID 접속은
  `cubrid-host`(호스트 LAN IP `--add-host`) — rootless netavark에서 게이트웨이/
  host.containers.internal 경유 불가.

## 결정 (traceability)

- **D1 — TableId schema = 논리 DB명(`htapdb`)**: CUBRID owner 스키마 대신 DB명을 쓰면
  기본 topic naming이 그대로 `htapcdc.htapdb.<table>`(#39 D2)이 되고 include list도
  `htapdb.t_order` 형태로 자연스럽다. JDBC 메타데이터는 catalog/schema 인자를 무시하므로
  (ADR 0005) 조회는 전부 bare 테이블명. POC는 dba 단독 소유 전제.
- **D2 — offset anchor와 이벤트 카운터의 분리**: `CubridOffsetContext`가 영속하는 것은
  anchor(가장 오래된 in-flight 트랜잭션의 배치 경계 LSA + 그 시점 누적 카운터)이고,
  `source.lsn`은 이벤트별 카운터. 같은 필드로 쓰면 재시작 시 version 재부여가 어긋난다
  (ADR 0004의 재시작 재계수 규칙 구현).
- **D3 — DATETIME은 wall-clock passthrough로 ZonedTimestamp화**: 스냅샷(JDBC Timestamp)과
  스트리밍(문자열 파싱→Timestamp)이 같은 워커 JVM(UTC)에서 같은 벽시계 문자열로 렌더 —
  두 경로의 값이 byte-identical해 수렴 검증이 성립. 시간대 의미론(서버 tz ↔ UTC 매핑)은
  POC 범위 밖으로 명시.
- **D4 — 검증은 canonical view 최종 상태 비교**: raw 물리 행은 RMT 머지 시점에 따라 변하므로
  assert 대상이 아니다(#39 D3와 동일 근거). tombstone 물리 확인은 informational로만.
