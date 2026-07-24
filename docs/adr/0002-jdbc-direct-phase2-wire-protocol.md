# JDBC direct execution Phase 2 wire protocol — CSS experimental opcode + TLV, PoC 축소 범위

Status: accepted (Phase 3 재검토 예정)

JDBC direct prepared execution Phase 2(이슈 xmilex-git/cubrid#163)의 목적은 성능 개선폭
측정이며, 게이트는 YCSB Workload C 단독이다(Workload B/direct UPDATE는 Phase 3).
wire 경계는 Phase 1 PoC의 CSS transport + `ENABLE_JDBC_DIRECT_POC` 게이팅을 연장한다.
`NET_SERVER_JDBC_DIRECT_POC_EXECUTE_SELECT1`을 generic execute opcode 하나로 교체하고,
request/reply 양쪽에 version int를 실어 mismatch 시 협상 없이 fail-fast한다.
행 데이터와 bind parameter의 wire 표현은 direct handler가 만들고 JDBC는 그것만 안다 —
서버 내부 표현(OR pack, list-file page, packed DB_VALUE)은 wire에 노출하지 않는다.

- 연결 모델: CAS prepare/control connection + server direct execute connection 이중 유지.
  prepare-후-CAS-종료(detach)와 session ownership 이전은 Phase 3 재고.
- 적격성 = JDBC 쪽 direct 분기 조건: connection property opt-in AND SELECT AND
  autoCommit=true AND 유효 isolation == TRAN_READ_COMMITTED(direct attach가 등록하는
  `TRAN_DEFAULT_ISOLATION_LEVEL()`과 동일해야 함; 명시적 setTransactionIsolation과
  서버 conf `isolation_level` 변경 모두 커버) AND broker statement pooling ON AND
  지원 bind type AND 의미 비보존 실행 옵션 없음(maxRows/maxFieldSize/scrollable/
  sensitive/queryPlan/executeAll/async/queryTimeout>0 → CAS 강등). 조건이 하나라도
  깨지면 별도 fallback 장치 없이 **기존 CAS 코드가 default branch로 실행**된다(같은
  의미, 다른 경로). YCSB load(INSERT)는 direct=off URL로 별도 invocation.
- CAS handle lifecycle: statement pooling OFF에서는 CAS auto-commit마다 non-holdable
  srv handle이 전부 해제되어(ux_end_tran_cleanup) fallback용으로 유지한 handle이 즉시
  죽는다. 따라서 pooling ON이 direct의 전제이며(JDBC 게이트 + take_xasl 서버측 belt),
  pooling ON에서 handle은 JDBC close()의 CLOSE_USTATEMENT로 정확히 1회 해제된다.
- TAKE_XASL 오류 분류: CAS가 명시적으로 거절한 경우(CAS_ER_ARGS)만 CAS 강등.
  통신/protocol 오류는 삼키지 않고 전파한다(desync된 connection으로 계속 실행 금지).
- transaction: direct는 auto-commit read-only 실행기. commit은 CAS 경로와 동일한
  `TRAN_AUTO_COMMIT | EXECUTE_QUERY_WITH_COMMIT` + `stran_server_auto_commit_or_abort`.
  handler 안에서 실행→직렬화→end query→commit 동기 완결(deferred end-query 없음).
  read-only fast commit 최적화는 engine 공통 경로라 Phase 3 성능 후보로만 기록.
- 결과: single-response 모델. 결과 전체가 응답 1개에 들어가야 하며 상한 초과는 명시적
  에러(silent truncation 금지). cursor/page fetch/result close protocol 없음.
- type 집합(결과·bind 동일): **VARCHAR, INT, NULL** — YCSB C(VARCHAR)와 `SELECT 1`
  smoke(INT)에 필요한 전부. 그 외 type은 prepare/bind 시점에 CAS 경로로.
  column metadata는 direct 응답에 싣지 않고 CAS prepare 반환값을 재사용한다.
- bind wire 형식: custom TLV `{type tag, byte length, payload(4-byte padded)}` —
  NULL은 tag 0/len 0으로 표현하며 별도 null flag 필드는 없다(실구현 기준) → direct
  handler가 `db_make_*`로 DB_VALUE 배열 조립 후 `xqmgr_execute_query()`에 전달.
  param 수는 CAS prepare의 host var 수와 서버에서 대조(조용한 오답 방지). 문자열은
  connection charset bytes 그대로 전송, 서버 기본 codeset/collation + host-var
  coercion에 맡긴다(비기본 charset DB는 비지원). batch/generated keys 제외.
- 경계 검사: request는 len 음수/1 MiB 초과/overflow/trailing bytes를 fail-fast로
  거부. 응답은 값 삽입 **전에** 1 MiB 상한을 검사해 일시적 초과 할당도 없다.
  JDBC는 rowCount×colCount를 response 크기와 대조한 뒤에만 배열을 할당한다.
- 오류: reply의 status int에 server errid를 실을 뿐 message 문자열은 미전송. JDBC는
  errid 포함 SQLException을 던지고 디버깅은 server 로그로. warning 미전송.
  SQLState/CAS 에러코드 parity는 Phase 3.
- timeout/cancel: `setQueryTimeout(>0)`은 direct 비적격(CAS 강등, 의미 보존).
  direct in-flight에 대한 `cancel()`은 무효 — known limitation으로 문서화.
- disconnect: 신규 코드 0줄, 기존 CSS client-disconnect 정리 경로에 의존. 측정 위생으로
  run 세트 종료 후 `cubrid tranlist` 기준 tran/session 누수 0을 1회 확인한다.
- 보안: Phase 1과 동일 — localhost-only, 고정 PoC credential. auth/TLS/remote는 Phase 3.

## Considered Options

- 기존 client/server network interface 재사용(`NET_SERVER_QM_QUERY_EXECUTE` + list-file
  page fetch): 기각. 응답이 QFILE_LIST_ID + page 단위 전송이고 tuple이 서버 내부 디스크
  표현이라, Java 디코딩은 사실상 C client 스택(or_unpack, page layout) 재구현이 된다.
- 정식 versioned direct-execution protocol(협상·downgrade·mixed-version): 기각(연기).
  public compatibility contract는 Phase 3 항목이다.
- bind를 packed DB_VALUE(or_pack) 형식으로 전송: 기각. domain packing까지 Java로
  재구현해야 하므로 위 첫 기각 사유의 축소판이다.
- prepare-후-CAS-종료(footprint 반납): 연기. idle CAS는 execute loop에 없어 throughput
  이득이 아니고(Phase 1 +70.8%가 이중 연결 상태에서 실측), detach는 UConnection 사용처
  전체 가드 + 재prepare 소멸이라 Phase 3의 CAS 의존 제거 작업에 속한다.

## Consequences

- Phase 2 성공 게이트는 합격 숫자가 아니라 **깨끗한 CAS vs Direct 비교 그 자체**다:
  YCSB Workload C, recordcount 5M(≈5 GiB, `data_buffer_size`를 데이터셋보다 크게 잡고
  측정 전 warm), thread 지점은 2와 32만, 지점당 warmup + 20초 1회(read-only라 반복
  median 생략), CPU/NUMA pinning 없이 자유 측정, 같은 빌드(release)·conf·DB에서
  URL만 CAS/Direct 교체, 측정 중 빌드 병행 금지. 보고는 throughput + YCSB p50/p95/p99
  + `cubrid_rel` + 원자료. 완주 조건: direct run 에러 0(`ER_SES_SESSION_EXPIRED` 0,
  error-log flood 없음), run 세트 후 tran/session 누수 0 확인 1회.

- 이슈 #163 Phase 2 acceptance 초안 중 SQLState parity, cancel 지원, capability 테스트
  고정, cursor fetch semantics는 PoC 축소로 미충족 — 이슈 comment에 명시하고 Phase 3로
  이월한다(조용한 acceptance 축소 금지).
- protocol 상수/wire layout의 SSOT는 engine header 1곳 + JDBC 상수 class 1곳 + 본 문서.
- direct 경로가 꺼져도 기능 회귀 없음(성능만 CAS 수준으로 복귀).
