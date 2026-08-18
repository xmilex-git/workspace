# 1.0 CDC 권한 = per-table SELECT + 서버 relation 사전 — DBA 의존 제거, owner 전면 채택

CUBRID Debezium 커넥터 1.0의 CDC 전용 권한 스펙을 정한다(지도:
xmilex-git/workspace#48, 티켓: #55). 커넥터는 `database.user: dba`로 DBA 그룹 계정을
요구했다(최종 스펙 §3.3-7, future-work 8). 조사는 CUBRID 엔진 소스 실사(worktree
`htap-cdc-wt`) + 라이브 `htapdb` 실측 + Debezium PG·Oracle 공식 문서.

결정: **새 시스템 권한(`CDC_READER`)을 만들지 않는다.** CDC 세션 인가를 요청한 캡처
대상 테이블의 **per-table `SELECT` 권한**으로 대체하고, 커넥터가 DBA를 필요로 했던
숨은 의존 두 개(`_db_class` 카탈로그 조회, 무자격 테이블명)를 각각 **서버가 내려주는
relation 사전**과 **owner 전면 채택**으로 없앤다. 강제력은 CUBRID의 다른 모든 권한과
동일한 클라이언트측 수준이며, 그 사실을 제약으로 명기한다.

## 배경 — 조사로 확인된 사실

- **F1/F2 — 기존 DBA 검사는 클라이언트 라이브러리에만 있다.** `cubrid_log_db_login()`
  (`src/api/cubrid_log.c:874-921`)이 `au_login` → `db_restart` →
  `au_is_dba_group_member()` → `db_shutdown()`. 이후 CDC 데이터 채널은 **별도 CSS
  연결**이고(`connection_cl.cpp:929`, `DATA_REQUEST`+dbname만, `DB_CLIENT_TYPE_UNKNOWN`),
  서버측 `scdc_start_session()`(`network_interface_sr.cpp:11414`)의 유일한 거부 조건은
  `supplemental_log == 0`이다 — 사용자 식별·인증 코드가 없다.
- **F3 — 그러나 이는 CDC 고유 결함이 아니다.** `xboot_register_client()`
  (`boot_sr.c:3167`)도 비밀번호를 검증하지 않고 클라이언트가 선언한 `db_user`를 그대로
  기록한다. CUBRID의 인증·객체 권한은 통째로 클라이언트측 모델이다.
- **F4 — CUBRID의 기존 로그 열람 기능은 전부 DBA 전용.** flashback은 더 거칠게
  `db_login("DBA", dba_password)`를 하드코딩한다(`util_cs.c:4795`).
- **F5 — 서버측 per-table 필터는 실재한다.** `cdc_is_filtered_class()`가 loginfo
  producer에서 강제되고(`log_manager.c:10988·11018·11072`), DDL 아이템도 classoid가
  NULL이 아닌 한 같은 필터를 탄다(`log_manager.c:13488`). 목록이 비면 전체 허용,
  시스템 클래스는 항상 제외.
- **F6 — 빌트인 principal은 DBA·PUBLIC 둘뿐**이고 `au_install()`이 db 생성 시 만든다
  (`authenticate_context.cpp:281·963`). 세 번째 추가는 db 생성 + 기존 DB migrate +
  unload/load 경로가 모두 걸린다.
- **F7 — 선례는 "로그 읽기 권한 ≠ 테이블 읽기 권한" 분리.** Oracle은 전용 유저 +
  `LOGMINING` 롤 + `SELECT ANY TABLE` + `SELECT_CATALOG_ROLE`(`oracle.adoc:2560-2585`,
  문서가 "elevated privileges 주지 말라" 명기), PG는 `CREATE ROLE … REPLICATION LOGIN`
  + 테이블 SELECT를 그룹 롤로(`postgresql.adoc:2205-2279`).
- **F9 (실측) — 비-DBA 계정은 무자격 테이블명을 쓸 수 없다.** `cdctest`로 접속해
  `SELECT ... FROM t_order` → `Unknown class "cdctest.t_order"`. `dba.t_order`로
  자격을 붙이면 정상(테이블 SELECT 권한만으로 성공). 커넥터의 `quotedTableIdString`
  (`CubridConnection.java:70-72`)은 무자격이라 계정 전환 즉시 스냅샷이 깨진다.
- **F10 (실측) — `_db_class`는 비-DBA에게 닫혀 있다.** `SELECT is not authorized on
  _db_class`. 소유자는 DBA이고 grant 대상은 `Au_information_schema_user`뿐이다
  (`schema_system_catalog_install.cpp:425-465`). PUBLIC 뷰 `db_class`에는 OID 컬럼
  (`class_of`)이 아예 없다(같은 파일 1306-1333) — 대체 경로가 없다. 그런데 커넥터는
  `SELECT class_of, class_name FROM _db_class`로 classoid↔테이블 맵을 만들고
  (`CubridConnection.java:158`) 이 맵이 extraction 지정과 이벤트 라우팅 양쪽에 쓰인다.
  **즉 사전 없이는 비-DBA 계정으로 CDC가 원천 불가능하다.**
- **F11 (실측)** — `GRANT SELECT ON _db_class TO <user>`는 DBA가 부여 가능하고 즉시
  동작한다(79행 조회 성공). 단 `_db_class`는 권한 필터가 없어 카탈로그 전체가 보인다
  (PUBLIC 뷰 `db_class`는 호출자 권한으로 행이 필터됨 — 같은 계정이 뷰 경유로는 1행).
- **F12/F13 — 아이템 타입 추가는 레이아웃상 ABI 안전하고 사내 선례가 있다.**
  `union cubrid_data_item`의 최대 멤버는 `DML`이라 작은 구조체 추가는 union 크기를
  바꾸지 않는다(`cubrid_log.h:119-126`). #47이 같은 union에 `ROLLBACK_TO`를 추가했다
  (엔진 `56afad65a`). **결정적 차이**: `ROLLBACK_TO`는 `LOG_SYSOP_END`에서 파생되어
  위치가 있고 결정적이라 카운트해도 안전하지만, relation 사전은 세션에 매인 사건이라
  결정적이지 않다 → D6.
- **F14** — CUBRID 식별자는 큰따옴표로 감싸도 점(.)을 포함할 수 없다
  (`manual en/sql/identifier.rst:54`) → `owner.table` 파싱은 모호하지 않다.
- **F15 (실측) — PUBLIC 카탈로그 뷰만으로 owner-aware 스키마 발견이 가능하다.**
  `db_class`에 `owner_name`, `db_attribute`에 `owner_name`·`data_type`·`prec`·`scale`·
  `default_value`·`is_nullable`·`def_order`가 있고 둘 다 호출자 권한으로 행이 필터된다.
- **F16 — supplemental log는 대상 필터와 무관하게 전 테이블에 기록된다.**
  `heap_file.c:2810` — `supplemental_log > 0`이고 classoid가 유효하면 append. 필터는
  **전달**만 줄이고 **기록**은 못 줄인다.

## 확정 규칙

- **D1 — 새 시스템 권한을 만들지 않는다.** `CDC_READER`라는 빌트인 롤/그룹(F6)을
  추가하지 않고, CDC 세션 인가를 **요청한 캡처 대상 테이블 전부에 대한 `AU_SELECT`
  보유**로 정의한다. `cubrid_log_db_login()`의 `au_is_dba_group_member()` 검사를 이
  검사로 교체한다. **근거**: "CDC를 쓸 수 있는가"의 coarse gate는 이미 `supplemental_log`
  서버 파라미터(DBA 전용·인스턴스 단위)가 수행하므로 롤은 그것을 사용자 단위로
  중복하며, 빌트인 principal 추가는 db 생성·migrate·unload/load까지 번지는 유일한
  항목이라 1.0 리스크 대비 이득이 가장 나쁘다. **대가**: 로그는 현재 행보다 많은 것
  (이력·before image)을 주므로 SELECT만으로 이력이 열린다 — Oracle/PG의 분리 철학(F7)과
  어긋나는 지점이며 D10에 한계로 명기한다.
- **D2 — extraction 목록 미지정(= 로그 전체)은 DBA만.** 검사 대상이 없으면 D1이
  무력해지므로, 커넥터는 `table.include.list`를 **필수**로 강제한다. 사전 범위(D5)를
  정하기 위해서도 목록이 반드시 있어야 한다.
- **D3 — 이름 기반 extraction 지정.** `cubrid_log_set_extraction_table()`의 이름
  (`owner.table`) 기반 변형을 추가하고, 이름→classoid 해석을 **서버**가 수행한다.
  해석 실패(아직 없는 테이블)는 경고 후 미포함 — mid-stream CREATE를 캡처하지 않는
  ADR 0008 D3와 같은 규칙이다. 이로써 classoid는 커넥터 API 밖으로 나가지 않는다.
- **D4 — 서버가 relation 사전을 in-band 아이템으로 내려준다.** 새 data item type을
  추가해 `(classoid, owner, table)`을 커넥터에 알린다. 사전이 그 classoid의 **첫 사용
  아이템보다 반드시 앞선다**는 것이 프로토콜 계약이다. 재연결·`find_lsa`로 세션이
  갈리면 announce 집합을 초기화해 다시 보낸다(커넥터는 사전을 영속 캐시하지 않는다).
  이름 해석 실패(이미 DROP된 테이블의 밀린 로그) 시의 표현은 flashback의 `invalid_class`
  선례를 따른다. **owner와 table은 엔진이 분리해 담는다** — 커넥터가 문자열을 파싱하지
  않게 한다(F14로 파싱 자체는 안전하지만, owner는 토픽 이름에서 떼고 SQL에는 붙이는
  독립 취급 대상이다). **근거**: PG의 relation 메시지와 동형(literal parity)이며,
  사전을 스트림 안에 두면 런타임에 대상 집합이 변할 수 있게 되는 post-1.0(incremental
  snapshot·mid-stream 테이블 추가)에서 구조를 바꾸지 않아도 된다.
- **D5 — 사전 범위 = extraction으로 지정된 테이블만.** DB의 캡처 가능한 전체를 주지
  않는다. **이것이 `_db_class` grant를 불필요하게 만드는 핵심**이다 — 사전 범위가 D1의
  권한 경계(SELECT 검사를 통과한 집합)와 정확히 일치해야 하며, 전체를 내려주면
  "카탈로그 전체 이름 열람"을 API로 되살리는 셈이 된다.
- **D6 — relation 사전 아이템은 이벤트 카운터에서 제외한다(TIMER와 동일).**
  `CubridStreamingChangeEventSource.processBatch()`는 TIMER를 뺀 모든 아이템에서
  `state.counter++`하며(`:239-243`), 발행하지 않는 아이템(abandon된 트랜잭션,
  비대상 테이블)까지 "결정성을 위해" 센다. 사전은 로그 위치에서 파생되지 않은
  **세션 사건**이라 재연결마다 재전송되므로, 세면 같은 로그 위치를 재생했을 때 같은
  행 이벤트가 **다른 `_version`을 받는다** → at-least-once 중복이 RMT에서 수렴한다는
  #41의 증명(byte-identical `_version`)이 무효화된다. 사전 아이템은 또한 **트랜잭션
  버퍼를 우회**해야 한다(트랜잭션에 속하지 않으며 ADR 0007의 abandon으로 유실되면
  안 된다). **이 규칙이 이 ADR에서 가장 깨지기 쉬운 지점이다** — 회귀 검증은 재연결 후
  `_version` byte-identical 재생(#41 하네스)으로 고정한다.
- **D7 — 권한 실패 전용 에러 코드를 신설한다.** `CUBRID_LOG_FAILED_LOGIN` 재사용이
  아니라 새 코드를 enum 끝에 append하고(ABI 안전), 커넥터는 이를 **non-retriable**로
  분류한다. **근거**: 제한 계정 전환 후 가장 흔한 설정 실수가 권한 누락인데,
  "비밀번호 틀림"과 "권한 없음"이 같은 코드로 오면 기술지원 1차 진단이 항상 헛돈다.
- **D8 — owner 전면 채택, ADR 0006 D5 개정.** ① 토픽 이름 `htapcdc.<owner>.<table>`
  ② `table.include.list`도 `owner.table`(= CUBRID `unique_name` 문법) ③ 스냅샷 SQL은
  owner-qualified. DB명은 `topic.prefix`와 `database.dbname`이 담당하며 토픽에서 빠진다
  (CDC 세션이 DB 하나에 매여 모호성이 없다). **근거**: Debezium 표준 토픽 규칙이
  `topicPrefix.schemaName.tableName`으로 PG·Oracle·DB2·SQL Server·Informix 전부 동일
  하고(`postgresql.adoc:346`, `oracle.adoc:430`, `db2.adoc:517`, `sqlserver.adoc:539`,
  `informix.adoc:455`) 가운데 자리는 DB의 2단 네임스페이스 = Oracle에서는 소유자다.
  CUBRID의 2단 네임스페이스는 owner이므로 DB명을 넣은 기존 선택이 규칙 이탈이었다.
  ADR 0006 D5의 근거("드라이버가 schema 인자를 무시해 owner를 식별자로 못 쓴다")는
  실사 결과 부정확하다 — 컬럼 조회는 bare 테이블명만 쓰므로(`CubridConnection.java:114`)
  TableId의 schema 슬롯 값과 무관하다. 대가는 sink 설정 2줄
  (`htap-poc/sink/clickhouse-sink.json:13-14`)과 기존 토픽 폐기 + resnapshot이며,
  1.0 릴리스 전이라 설치 기반이 없어 실비용이 없다.
- **D9 — owner가 다른 동명 테이블을 완전 지원한다.** 컬럼 조회를 JDBC
  `getColumns(null, null, <bare>, null)`에서 **PUBLIC 카탈로그 뷰 `db_attribute`
  (owner_name 필터) 쿼리로 교체**한다(F15). 현재 경로는 `dba.t_order`와 `app.t_order`의
  컬럼을 **조용히 병합**하는 실재 버그이며 ADR 0006 D5의 "POC는 dba 단독 소유" 전제가
  이를 가리고 있었다. 부수 효과로 ADR 0005의 드라이버 메타데이터 우회들이 사라진다.
  **대가**: 컬럼 발견 경로 재작성 + 타입 매핑 전면 재검증 — 1.0 범위 확대를 의식적으로
  수용했고(#55 결정), 재검증은 #58(type mapping 경계 corpus)에 명기한다.
- **D10 — 최소 버전 정책: 서버 버전 혼용 없음.** 사전(D4)·이름 기반 지정(D3)을
  지원하는 엔진 버전부터만 연결한다. 구버전 서버용 `_db_class` fallback을 **두지
  않는다** — 남기면 (i) grant 요구가 가이드에서 사라지지 않아 이 결정의 실익이 없어지고
  (ii) 코드 경로가 둘로 갈려 기술지원 진단이 두 배가 된다. 최소 버전 미달 시의 명시적
  에러는 #62(버전 협상)에 위임하며, **#62가 D3·D4 구현의 선행이다**.
  *(#62 종결: 런타임 버전 검사·협상 메커니즘을 **만들지 않는다** — 서버·커넥터는
  lockstep 출하로 버전이 다른 상황을 제품 시나리오로 상정하지 않으며, 최소 서버
  버전은 매뉴얼 제약 절(#59)에 문서로만 명기한다. 이로써 D3·D4 선행 해소.)*
- **D11 — 강제력의 한계를 명기한다(정직성 규칙).** 이 결정은 **최소권한(ergonomics·
  감사)** 만을 목표로 한다. 서버측 강제는 하지 않는다 — CDC 세션에 신원을 실어
  `scdc_start_session()`에서 검사하는 것은 CDC만의 문제가 아니라 CUBRID 인증 모델
  전체의 문제이고(F3), CDC만 막아도 옆 테이블은 그대로이므로 보안 이득이 없다.
  따라서 ① 권한 검사는 세션 시작 1회이며 스트리밍 중 `REVOKE`는 진행 중인 세션을
  **멈추지 못한다**(다음 재연결부터 유효) ② 강제력은 CUBRID의 다른 모든 권한과 동일한
  클라이언트측 수준이다. 두 사실을 ADR과 세팅 가이드(#59)에 **한계로 명문화**하고,
  서버측 강제는 CUBRID 엔진팀 별건으로 넘긴다. 주기적 권한 재확인(커넥터가 JDBC로
  polling 후 halt)은 채택하지 않는다 — 서버가 여전히 신원을 모르는 이상 강제력 착시만
  키운다.
- **D12 — 세팅 가이드(#59) 명기 사항.** ① CDC 계정 grant 목록: 캡처 대상 테이블
  `SELECT`만(카탈로그 grant 불요 — D5) ② **DB에는 "이 테이블이 CDC 대상"이라는 영속
  표식이 없다**: 대상 집합은 커넥터 설정에서 나와 세션마다 선언되는 휘발성 필터이며,
  구별 기준은 이름이 아니라 classoid다. Oracle(`ALTER TABLE … ADD SUPPLEMENTAL LOG
  DATA`)·PG(`CREATE PUBLICATION`)와 달리 DB에 남지 않으므로 지원팀이 "이 DB의 CDC
  대상"을 DB에 물을 수 없고 유일한 출처는 커넥터 설정이다 ③ **supplemental log는 대상
  필터와 무관하게 전 테이블에 기록된다**(F16) — #61이 측정한 오버헤드(bulk +2.4%·
  single +0.5%)는 인스턴스 전체 비용이며 대상을 좁혀도 줄지 않는다("대상만 좁히면
  오버헤드도 준다"는 오해를 선제 차단) ④ 최소 서버 버전(D10) ⑤ D11의 한계 2종.

## 기각한 대안

- **A — 빌트인 롤 `CDC_READER`(Oracle LOGMINING parity)**: 로그 전체 권한을 롤로 부여.
  기각 근거 D1 — 빌트인 principal 추가가 db 생성·migrate·unload/load까지 번지고,
  coarse gate는 `supplemental_log`가 이미 수행한다. 티켓 제목의 전제였던 이름
  `CDC_READER`도 이로써 버린다.
- **C — A+B(CDC_READER 게이트 + per-table SELECT 교집합)**: 가장 옳고 가장 비싸다.
  1.0 범위 초과.
- **`GRANT SELECT ON _db_class`를 가이드로 요구(엔진 무변경)**: F11로 동작이 실증됐고
  Oracle의 `SELECT_CATALOG_ROLE` 부여와 같은 모양이라 1.0 후보였다. 기각 근거 —
  카탈로그 전체 이름·소유자가 CDC 계정에 노출되고, D4/D5가 같은 목표를 노출 없이
  달성하며, 운영자에게 grant를 하나 더 떠넘긴다. (엔진 변경을 피해야 하는 상황이
  생기면 이것이 escape hatch다.)
- **`db_class` 뷰에 `class_of` 컬럼 추가**: 뷰는 이미 권한 필터가 걸려 "읽을 수 있는
  테이블의 classoid만" 노출되는 정확한 답이지만, 카탈로그 뷰 정의 변경 = DB 마이그레이션
  이라 D1이 A를 기각한 근거와 같은 비용이 된다.
- **사전을 세션 핸드셰이크 응답으로 1회 전달(in-band 아님)**: 1.0에서는 대상 집합이
  세션 내 불변이므로(DDL halt) 정적 사전이 성립하고 D6의 카운터 위험이 원천 소멸한다.
  기각 근거 — post-1.0에서 집합이 런타임에 변할 수 있게 되면 in-band로 다시 옮겨야
  하며, PG parity를 명시적으로 택했다(#55 결정). **대신 D6를 확정 규칙으로 승격해
  위험을 상수화했다.**
- **동명 테이블은 1.0 제약 + fail-fast로 처리**: bare 이름이 owner 간 유일해야 한다는
  제약을 문서화하고 기동 시 검사. 기각 근거 — owner를 토픽 이름에 올리면(D8) 사용자는
  당연히 둘 다 캡처 가능하다고 기대하며, 제약은 그 기대를 배신한다. 1.0 확대를 수용했다.

## 트레이드오프 (명시)

**이 결정은 보안 강화가 아니라 최소권한이다**(D11). 커넥터 설정에서 DBA 비밀번호가
사라지고 계정 회수·감사가 가능해지지만, 강제력은 CUBRID의 다른 권한과 같은 클라이언트측
수준이며 진행 중인 세션은 REVOKE로 멈추지 않는다. 이 한계를 제품 문서에 정직하게 쓰는
것이 이 ADR의 조건이다 — 서버측 강제를 이 지도의 성과로 포장하는 것이 가장 위험한 답이다.

**D6는 정합성 계약과 직접 맞닿아 있다.** relation 사전을 카운터에 세는 실수 하나로
#41이 증명한 RMT 수렴이 무효가 되고, 증상은 "재연결 후 중복 행이 안 합쳐진다"로만
나타난다. in-band(D4)를 택한 대가이며, 회귀 검증을 필수 완료 조건으로 묶는다.
